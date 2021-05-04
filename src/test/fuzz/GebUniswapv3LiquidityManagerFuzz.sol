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
import ".././GebUniswapv3LiquidityManager.t.sol";

import "./uniswap/Setup.sol";
import "./uniswap/E2E_swap.sol";

/**
 * Interface contract aimed at fuzzing the Uniswap Liquidity Manager
 * Very similar to GebUniswap v3 tester
 */
contract Fuzzer is E2E_swap {
    using SafeMath for uint256;

    constructor() public {}

    // --- All Possible Actions ---
    function changeThreshold(uint256 val) public {
        //Requirement from uniswap
        if (!inited) {
            setUp();
            _init(uint128(val));
        }
        manager.modifyParameters(bytes32("threshold"), val);
    }

    function rebalancePosition() public {
        require(inited);
        manager.rebalance();
    }

    function changeRedemptionPrice(uint256 newPrice) public {
        if (!inited) {
            setUp();
            _init(uint128(newPrice));
        }
        oracle.setSystemCoinPrice(newPrice);
    }

    function changeCollateralPrice(uint256 newPrice) public {
        if (!inited) {
            setUp();
            _init(uint128(newPrice));
        }
        oracle.setCollateralPrice(newPrice);
    }

    function depositForRecipient(address recipient, uint128 liquidityAmount) public {
        if (!inited) {
            setUp();
            _init(liquidityAmount);
        }
        if (!inited) _init(liquidityAmount);
        manager.deposit(liquidityAmount, address(this));
    }

    function withdrawForRecipient(address recipient, uint128 liquidityAmount) public {
        if (!inited) {
            setUp();
            _init(liquidityAmount);
        }
        manager.withdraw(liquidityAmount, address(this));
    }

    function user_Deposit(uint8 user, uint128 liq) public {
        if (!inited) {
            setUp();
            _init(liq);
        }
        users[user % 4].doDeposit(liq);
    }

    function user_WithDraw(uint8 user, uint128 liq) public {
        if (!inited) {
            setUp();
            _init(liq);
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
            setUp();
            _init(liquidityAmount);
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
            setUp();
            _init(liquidityAmount);
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
            setUp();
            _init(amount0Requested);
        }
        users[user % 4].doCollectFromPool(lowerTick, upperTick, recipient, amount0Requested, amount1Requested);
    }

    function user_Swap(uint8 user, int256 _amount) public {
        if (!inited) {
            setUp();
            _init(uint128(user));
        }
        require(token0.balanceOf(address(swapper)) > 0);
        int256 _amountSpecified = -int256(_amount);

        uint160 sqrtPriceLimitX96 = get_random_oneForZero_priceLimit(_amount);
        users[user % 4].doSwap(false, _amountSpecified, sqrtPriceLimitX96);
    }

    // --- Echidna Tests ---

    function echidna_select_ticks_correctly() public returns (bool) {
        int24 tickPrice = manager.lastRebalancePrice();
        uint256 _threshold = manager.threshold();
        (bytes32 posId, int24 lower, int24 upper, ) = manager.position();
        return (lower + int24(_threshold) <= tickPrice && upper - int24(_threshold) >= tickPrice);
    }

    function echidna_position_integrity() public returns (bool) {
        (bytes32 posId, , , uint128 liq) = manager.position();
        (uint128 _liquidity, , , , ) = pool.positions(posId);
        return (liq == _liquidity);
    }

    function echidna_id_integrity() public returns (bool) {
        (bytes32 posId, int24 low, int24 up, uint128 liq) = manager.position();
        bytes32 id = keccak256(abi.encodePacked(address(manager), low, up));
        return (posId == id);
    }

    function echidna_supply_integrity() public returns (bool) {
        uint256 this_bal = manager.balanceOf(address(this));
        uint256 u1_bal = manager.balanceOf(address(u1));
        uint256 u2_bal = manager.balanceOf(address(u2));
        uint256 u3_bal = manager.balanceOf(address(u3));
        uint256 u4_bal = manager.balanceOf(address(u4));

        uint256 total = this_bal.add(u1_bal).add(u2_bal).add(u3_bal).add(u4_bal);
        return (manager.totalSupply() == total);
    }

    // --- Copied from test file ---

    GebUniswapV3LiquidityManager manager;
    OracleLikeMock oracle;

    uint256 threshold = 400000; //40%
    uint256 delay = 120 minutes; //10 minutes

    uint160 initialPoolPrice;

    FuzzUser u1;
    FuzzUser u2;
    FuzzUser u3;
    FuzzUser u4;

    FuzzUser[4] public users;
    PoolViewer pv;

    function setUp() public {
        oracle = new OracleLikeMock();
        pv = new PoolViewer();

        // manager = new GebUniswapV3LiquidityManager("Geb-Uniswap-Manager", "GUM", address(token0), threshold, delay, address(pool), bytes32("ETH"), oracle, pv);

        u1 = new FuzzUser(manager, token0, token1);
        u2 = new FuzzUser(manager, token0, token1);
        u3 = new FuzzUser(manager, token0, token1);
        u4 = new FuzzUser(manager, token0, token1);

        u1.setPool(pool);
        u2.setPool(pool);
        u3.setPool(pool);
        u4.setPool(pool);

        users[0] = u1;
        users[1] = u2;
        users[2] = u3;
        users[3] = u4;

        // helper_transferToAdds(users);
    }

    function helper_transferToAdds(FuzzUser[4] memory adds) internal {
        for (uint256 i = 0; i < adds.length; i++) {
            token0.transfer(address(adds[i]), 30000 ether);
            token1.transfer(address(adds[i]), 120000000000 ether);
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
