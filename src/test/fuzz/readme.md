## Fuzzing the Uniswap V3 manager

### Setup

The initial setup was borrowed from Uniswap V3 fuzzing, and it starts a pool with random values. Complementarily, a manager is also deployed and connected to the pool.

A few actions are allowed to be performed:

1. All pool actions inherited from uni fuzzing, which include minting, burning and swapping directly on the pool.
2. Manager actions, such as depositing, withdrawing and rebalancing.
3. Function to change redemption price and the threshold.

### First run

The following properties were tested:

1. Position Integrity, which makes sure that the manager always tracks the position it has on uniswap correctly
2. Always has a position, which ensures that the manager is always invested in the pool
3. Id Integrity, which guarantees the manager keep track of the correct id position
4. Tick selection, that means the manager is always invested in a tick range at least half of threshold
5. Supply integrity, the sum of all balances always equals the total supply.

#### Results:

```bash

echidna_position_integrity: failed!💥
  Call sequence:
    test_swap_exactOut_zeroForOne(1)

echidna_always_has_a_position: failed!💥
  Call sequence:
    test_swap_exactOut_zeroForOne(1)

echidna_id_integrity: failed!💥
  Call sequence:
    test_swap_exactOut_zeroForOne(1)

echidna_select_ticks_correctly: failed!💥
  Call sequence:
    changeRedemptionPrice(2)

echidna_supply_integrity: failed!💥
  Call sequence:
    test_swap_exactOut_zeroForOne(1)


Unique instructions: 32005
Unique codehashes: 11
Seed: 4714442236582541202
```

#### Analysis:

All of the assertions were easily broken, but mostly due to the same issue: the market price detaching completely from the redemption price, either to a swap that crashes the price or to a direct redemption price change.

Therefore it's possible to conclude that when that happens, the manager contract itself loose it's purpose.

#### Adjustments:

-   Set initial pool parameters but close to the real world, and set the pool's initial price close to the starting redemption price
-   Bound the price changes to values closer to real world.

### Second run

After adjusting the parameters, a second round of fuzzing was run. Two more properties were added:

1. Manager contract never owns tokens, to ensure no leftover token0 or token1.
2. When the manager has an open position in the pool, it must also have a total supply greater than 0.

#### Results:

```
echidna_select_ticks_correctly: failed!💥
  Call sequence, shrinking (6378/50000):
    changeThreshold(10320)

echidna_position_integrity: passed! 🎉
echidna_manager_never_owns_tokens: passed! 🎉
echidna_manager_doesnt_have_position_if_supply_is_zero: passed! 🎉
echidna_supply_integrity: passed! 🎉
echidna_id_integrity: passed! 🎉
echidna_always_has_a_position: passed! 🎉

Seed: -8499657479103175191
```

#### Analysis:

After the adjustments, only one of the assertions is failing. This specific assertion guarantees that the manager range is at least half of the threshold, which should only happen if the redemption price is equal to either `MIN_THRESHOLD` or `MAX_THRESHOLD`.

However, the failure can happen from changing the `threshold` but not performing a rebalance or a deposit right afterwards, when Echidna will return a result based on the new threshold while the pool still has a position using the old one.

#### Adjustments:

-   While this does not need to be addressed in the real world, for the next iteration we'll force a rebalance after every parameter adjustments, in order to find deeper hidden bugs.

### Third run
