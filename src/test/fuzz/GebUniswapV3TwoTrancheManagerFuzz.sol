pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;
import { ERC20 } from "../.././erc20/ERC20.sol";
import { IUniswapV3Pool } from "../.././uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "../.././uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "../.././uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "../.././uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "../.././uni/libraries/TickMath.sol";
import "../../uni/UniswapV3Factory.sol";
import ".././TestHelpers.sol";
import ".././GebUniswapV3TwoTrancheManager.t.sol";

import "./uniswap/Setup.sol";
import "./uniswap/E2E_swap.sol";

/**
 * Interface contract aimed at fuzzing the Uniswap Liquidity Manager
 * Very similar to GebUniswap v3 tester
 */
contract Fuzzer is E2E_swap {
    using SafeMath for uint256;

    int24 lastRebalancePrice;
    uint swapCount;
    constructor() public {}

    // --- All Possible Actions ---
    function changeThreshold(uint256 val) public {
        if (!inited) {
            _init(uint128(val));
            setUp();
        }
        manager.modifyParameters(bytes32("threshold"), val);
        manager.rebalance();
    }

    function rebalancePosition() public {
        require(inited);
        lastRebalancePrice = manager.getTargetTick();
        manager.rebalance();
    }

    function changeRedemptionPrice(uint256 newPrice) public {
        require(newPrice > 600000000 ether && newPrice < 3600000000 ether);
        if (!inited) {
            _init(uint128(newPrice));
            setUp();
        }
        oracle.setSystemCoinPrice(newPrice);
    }

    function changeCollateralPrice(uint256 newPrice) public {
        require(newPrice > 100 ether && newPrice < 1000 ether);
        if (!inited) {
            _init(uint128(newPrice));
            setUp();
        }
        oracle.setCollateralPrice(newPrice);
    }

    //Not using recipient to test totalSupply integrity
    function depositForRecipient(address recipient, uint128 liquidityAmount) public {
        if (!inited) {
            _init(liquidityAmount);
            setUp();
        }
        if (!inited) _init(liquidityAmount);
        manager.deposit(liquidityAmount, address(this),0,0);
    }

    function withdrawForRecipient(address recipient, uint128 liquidityAmount) public {
        if (!inited) {
            _init(liquidityAmount);
            setUp();
        }
        manager.withdraw(liquidityAmount, address(this));
    }

    function user_Deposit(uint8 user, uint128 liq) public {
        if (!inited) {
            _init(liq);
            setUp();
        }
        users[user % 4].doDeposit(liq);
    }

    function user_WithDraw(uint8 user, uint128 liq) public {
        if (!inited) {
            _init(liq);
            setUp();
        }
        users[user % 4].doWithdraw(liq);
    }

    //Repeated from E2E_swap, but it doesn't hurt to allow pool depositors to interact with pool directly
    function user_Mint(
        uint8 user,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidityAmount
    ) public {
        if (!inited) {
            _init(liquidityAmount);
            setUp();
        }
        users[user % 4].doMint(lowerTick, upperTick, liquidityAmount);
    }

    function user_Burn(
        uint8 user,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidityAmount
    ) public {
        if (!inited) {
            _init(liquidityAmount);
            setUp();
        }
        users[user % 4].doBurn(lowerTick, upperTick, liquidityAmount);
    }

    function user_Collect(
        uint8 user,
        int24 lowerTick,
        int24 upperTick,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public {
        if (!inited) {
            _init(amount0Requested);
            setUp();
        }
        users[user % 4].doCollectFromPool(lowerTick, upperTick, recipient, amount0Requested, amount1Requested);
    }

    function user_Swap(uint8 user, int256 _amount) public {
        if (!inited) {
            _init(uint128(user));
            setUp();
        }
        require(token0.balanceOf(address(swapper)) > 0);
        int256 _amountSpecified = -int256(_amount);

        uint160 sqrtPriceLimitX96 = get_random_oneForZero_priceLimit(_amount);
        users[user % 4].doSwap(false, _amountSpecified, sqrtPriceLimitX96);
        swapCount++;
    }

    function claim_management_fees() public {
        if (swapCount > 0) {
            assert(manager.unclaimedToken0() > 0 || manager.unclaimedToken1() > 0);
            manager.claimManagementFees(address(0xFab));
            assert(manager.unclaimedToken0() == 0 && manager.unclaimedToken1() == 0);
        }
    }

    // --- Echidna Tests ---
    function echidna_position_integrity() public returns (bool) {
        if (!inited) {
            return true;
        }
        (bytes32 posId, , , uint128 liq,,,) = manager.positions(0);
        (uint128 _liquidity, , , , ) = pool.positions(posId);
        if (liq != _liquidity) return false;

        (posId, , , liq,,,) = manager.positions(1);
        (_liquidity, , , , ) = pool.positions(posId);
        return (liq == _liquidity);
    }

    function echidna_always_has_a_position() public returns (bool) {
        if (!inited) {
            return true;
        }
        (bytes32 posId, , , ,,,) = manager.positions(0);
        (uint128 _liquidity, , , , ) = pool.positions(posId);
        if (manager.totalSupply() > 0) return (_liquidity > 0);
        return true; // If there's no supply it's fine
    }

    function echidna_id_integrity() public returns (bool) {
        if (!inited) {
            return true;
        }
        (bytes32 posId, int24 low, int24 up, uint128 liq,,,) = manager.positions(0);
        bytes32 id = keccak256(abi.encodePacked(address(manager), low, up));
        return (posId == id);
    }

    event DC(int24 l);

    function echidna_select_ticks_correctly() public returns (bool) {
        if (!inited) {
            return true;
        }
        (bytes32 posId, int24 lower, int24 upper, ,uint256 _threshold,,) = manager.positions(0);
        if (lower + int24(_threshold) < lastRebalancePrice || upper - int24(_threshold) > lastRebalancePrice) return false;

        (posId, lower, upper, ,_threshold,,) = manager.positions(1);
        return (lower + int24(_threshold) >= lastRebalancePrice && upper - int24(_threshold) <= lastRebalancePrice);
    }

    function echidna_supply_integrity() public returns (bool) {
        if (!inited) {
            return true;
        }
        uint256 this_bal = manager.balanceOf(address(this));
        uint256 u1_bal = manager.balanceOf(address(u1));
        uint256 u2_bal = manager.balanceOf(address(u2));
        uint256 u3_bal = manager.balanceOf(address(u3));
        uint256 u4_bal = manager.balanceOf(address(u4));

        uint256 total = this_bal.add(u1_bal).add(u2_bal).add(u3_bal).add(u4_bal);
        return (manager.totalSupply() == total);
    }

    function echidna_manager_does_not_have_position_if_supply_is_zero() public returns (bool) {
        if (!inited) {
            return true;
        }
        (, , , uint128 liq,,,) = manager.positions(0);
        if (liq > 0) {
            return manager.totalSupply() > 0;
        } else {
            return true;
        }
    }

    // --- Copied from a test file ---
    GebUniswapV3TwoTrancheManager public manager;
    OracleLikeMock oracle;

    uint256 threshold1 = 200040; // 20%
    uint256 threshold2 = 50040;  // 5%
    uint128 ratio1 = 50;         // 36%
    uint128 ratio2 = 50;         // 36%

    uint256 delay = 120 minutes; // 10 minutes

    uint160 initialPoolPrice;

    FuzzUser2Tranche u1;
    FuzzUser2Tranche u2;
    FuzzUser2Tranche u3;
    FuzzUser2Tranche u4;

    FuzzUser2Tranche[4] public users;
    PoolViewer pv;

    function setUp() internal {
        oracle = new OracleLikeMock();
        pv = new PoolViewer();

        manager = new GebUniswapV3TwoTrancheManager("Geb-Uniswap-Manager", "GUM", address(token0), uint128(delay), 50, threshold1,threshold2, ratio1,ratio2, address(pool), oracle, pv, address(token1));

        u1 = new FuzzUser2Tranche(manager, token0, token1);
        u2 = new FuzzUser2Tranche(manager, token0, token1);
        u3 = new FuzzUser2Tranche(manager, token0, token1);
        u4 = new FuzzUser2Tranche(manager, token0, token1);

        u1.setPool(pool);
        u2.setPool(pool);
        u3.setPool(pool);
        u4.setPool(pool);

        users[0] = u1;
        users[1] = u2;
        users[2] = u3;
        users[3] = u4;

        token0.mintTo(address(this), 1000000 ether);
        token1.mintTo(address(this), 1000000 ether);

        token0.approve(address(manager), 1000000 ether);
        token1.approve(address(manager), 1000000 ether);

        helper_transferToAdds(users);

        set = true;
    }

    function helper_transferToAdds(FuzzUser2Tranche[4] memory adds) internal {
        for (uint256 i = 0; i < adds.length; i++) {
            token0.mintTo(address(adds[i]), 30000 ether);
            token1.mintTo(address(adds[i]), 120000000000 ether);

            adds[i].doApprove(address(token0), address(manager), 30000 ether);
            adds[i].doApprove(address(token1), address(manager), 120000000000 ether);
        }
    }

    function helper_getRebalancePrice() internal returns (uint160) {
        // 1. Get prices from the oracle relayer
        (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();

        // 2. Calculate the price ratio
        uint160 sqrtPriceX96;
        if (!(address(pool.token0()) == address(token0))) {
            sqrtPriceX96 = uint160(sqrt((redemptionPrice << 96) / ethUsdPrice));
        } else {
            sqrtPriceX96 = uint160(sqrt((ethUsdPrice << 96) / redemptionPrice));
        }
        return sqrtPriceX96;
    }

    function helper_getLiquidityAmountsForTicks(
        uint160 sqrtRatioX96,
        int24 _lowerTick,
        int24 upperTick,
        uint256 t0am,
        uint256 t1am
    ) public returns (uint128 liquidity) {
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            t0am,
            t1am
        );
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        token0.transfer(msg.sender, amount0Owed);
        token1.transfer(msg.sender, amount0Owed);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (address(pool.token0()) == address(token0)) {
            if (amount0Delta > 0) token0.transfer(msg.sender, uint256(amount0Delta));
            if (amount1Delta > 0) token1.transfer(msg.sender, uint256(amount1Delta));
        } else {
            if (amount1Delta > 0) token0.transfer(msg.sender, uint256(amount1Delta));
            if (amount0Delta > 0) token1.transfer(msg.sender, uint256(amount0Delta));
        }
    }
}
