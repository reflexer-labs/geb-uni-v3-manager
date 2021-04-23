pragma solidity ^0.6.7;

import { ERC20 } from "../.././erc20/ERC20.sol";
import { IUniswapV3Pool } from "../.././uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "../.././uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "../.././uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "../.././uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "../.././uni/libraries/TickMath.sol";
import "../../uni/UniswapV3Factory.sol";
import ".././TestHelpers.sol";
import ".././GebUniswapv3LiquidityManager.t.sol";

/**
 * Interface contract aimed at fuzzing the Uniswap Liquidity Manager
 * Very similar to GebUniswap v3 tester
 */
contract Fuzzer {
    constructor() public {
        //That set's the manager in a base state
        setUp();
    }

    //Onlu doing deposits from this address, and no swaps hapenning
    function depositForRecipient(address recipient, uint128 liquidityAmount) public {
        manager.deposit(liquidityAmount, recipient);
    }

    function withdrawForRecipient(address recipient, uint128 liquidityAmount) public {
        uint128 max_uint128 = uint128(0 - 1);
        manager.withdraw(liquidityAmount, recipient, max_uint128, max_uint128);
    }

    function echidna_manager_supply_equal_liquidity() public returns (bool) {
        (bytes32 posId, , , ) = manager.position();
        (uint128 _liquidity, , , , ) = pool.positions(posId);
        return (manager.totalSupply() == _liquidity);
    }

    // --- Copied from test file ---
    GebUniswapV3LiquidityManager manager;
    UniswapV3Pool pool;
    TestRAI testRai;
    TestWETH testWeth;
    OracleLikeMock oracle;
    address token0;
    address token1;

    uint256 threshold = 500000; //50%
    uint256 delay = 120 minutes; //10 minutes

    uint160 initialPoolPrice = 25054144837504793118641380156;
    // uint160 initialPoolPrice = 890102030748522;

    PoolUser u1;
    PoolUser u2;
    PoolUser u3;
    PoolUser u4_whale;

    function setUp() internal {
        oracle = new OracleLikeMock();

        // Deploy each token
        testRai = new TestRAI("RAI");
        testWeth = new TestWETH("WETH");
        (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));

        // Deploy Pool
        pool = UniswapV3Pool(helper_deployV3Pool(token0, token1, 500, initialPoolPrice));
        // manager = new GebUniswapV3LiquidityManager("Geb-Uniswap-Manager", "GUM", address(testRai), threshold, delay, address(pool), bytes32("ETH"), oracle);

        // // u1 = new PoolUser(manager);
        // // u2 = new PoolUser(manager);
        // // u3 = new PoolUser(manager);
        // u4_whale = new PoolUser(manager);

        // //Make the pool start with some spread out liquidity
        // helper_addWhaleLiquidity();
    }

    function helper_deployV3Pool(
        address _token0,
        address _token1,
        uint256 fee,
        uint160 initialPoolPrice
    ) internal returns (address _pool) {
        UniswapV3Factory fac = new UniswapV3Factory();
        // _pool = fac.createPool(token0, token1, uint24(fee));
        //We have to give an inital price to the wethUsd // This meas 10:1(10 RAI for 1 ETH).
        //This number is the sqrt of the price = sqrt(0.1) multiplied by 2 ** 96
        // UniswapV3Pool(_pool).initialize(initialPoolPrice);
    }

    function helper_changeRedemptionPrice(uint256 newPrice) internal {
        oracle.setSystemCoinPrice(newPrice);
    }

    function helper_transferToAdds(address[] memory adds) internal {
        for (uint256 i = 0; i < adds.length; i++) {
            testWeth.transfer(adds[i], 100 ether);
            testRai.transfer(adds[i], 100 ether);
        }
    }

    function helper_addWhaleLiquidity() internal {
        uint256 wethAmount = 10000 ether;
        uint256 raiAmount = 100000 ether;

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, -887270, 887270, wethAmount, raiAmount);

        pool.mint(address(u4_whale), -887270, 887270, liq, bytes(""));
    }

    function helper_addLiquidity() internal {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u1.doApprove(address(testRai), address(manager), raiAmount);
        u1.doApprove(address(testWeth), address(manager), wethAmount);

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, -887270, 887270, wethAmount, raiAmount);

        //Adding liquidty without changing current price. To use the full amount of tokens we would need to add sqrt(10)
        //But we'll add an approximation
        u1.doDeposit(liq);
    }

    function helper_getLiquidityAmountsForTicks(
        uint160 sqrtRatioX96,
        int24 _lowerTick,
        int24 upperTick,
        uint256 t0am,
        uint256 t1am
    ) internal returns (uint128 liquidity) {
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            t0am,
            t1am
        );
    }

    function helper_getAbsInt24(int24 val) internal returns (uint256 abs) {
        if (val > 0) {
            abs = uint256(val);
        } else {
            abs = uint256(val * int24(-1));
        }
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
        testRai.transfer(msg.sender, amount0Owed);
        testWeth.transfer(msg.sender, amount0Owed);
    }
}
