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
    using SafeMath for uint256;
    PoolUser[4] public users;

    constructor() public {
        setUp();
    }

    // --- All Possible Actions ---
    function changeThreshold(uint256 val) public {
        manager.modifyParameters(bytes32("threshold"), val);
    }

    function rebalancePosition() public {
        manager.rebalance();
    }

    function depositForRecipient(address recipient, uint128 liquidityAmount) public {
        manager.deposit(liquidityAmount, address(this));
    }

    function withdrawForRecipient(address recipient, uint128 liquidityAmount) public {
        uint128 max_uint128 = uint128(0 - 1);
        manager.withdraw(liquidityAmount, address(this));
    }

    function user_Deposit(uint8 user, uint128 liq) public {
        users[user % 4].doDeposit(liq);
    }

    function user_WithDraw(uint8 user, uint128 liq) public {
        users[user % 4].doWithdraw(liq);
    }

    function user_Mint(
        uint8 user,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidityAmount
    ) public {
        users[user % 4].doMintOnPool(lowerTick, upperTick, liquidityAmount);
    }

    function user_Burn(
        uint8 user,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidityAmount
    ) public {
        users[user % 4].doBurnOnPool(lowerTick, upperTick, liquidityAmount);
    }

    function user_Collect(
        uint8 user,
        int24 lowerTick,
        int24 upperTick,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public {
        users[user % 4].doCollectFromPool(lowerTick, upperTick, recipient, amount0Requested, amount1Requested);
    }

    function user_Swap(
        uint8 user,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public {
        users[user % 4].doSwap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, bytes(""));
    }

    // --- Echidna Tests ---

    function echidna_manager_supply_equal_liquidity() public returns (bool) {
        (bytes32 posId, , , ) = manager.position();
        (uint128 _liquidity, , , , ) = pool.positions(posId);
        return (manager.totalSupply() == _liquidity);
    }

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
    PoolUser u4;

    PoolViewer pv;

    function setUp() internal {
        oracle = new OracleLikeMock();
        // Deploy each token
        testRai = new TestRAI("RAI");
        testWeth = new TestWETH("WETH");
        (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));
        // Deploy Pool
        pv = new PoolViewer();

        pool = UniswapV3Pool(helper_deployV3Pool(token0, token1, 500, initialPoolPrice));
        manager = new GebUniswapV3LiquidityManager("Geb-Uniswap-Manager", "GUM", address(testRai), threshold, delay, address(pool), bytes32("ETH"), oracle, pv);
        u1 = new PoolUser(manager, pool, testRai, testWeth);
        u2 = new PoolUser(manager, pool, testRai, testWeth);
        u3 = new PoolUser(manager, pool, testRai, testWeth);
        u4 = new PoolUser(manager, pool, testRai, testWeth);

        users[0] = u1;
        users[1] = u2;
        users[2] = u3;
        users[3] = u4;

        //Transfer tokens for address
        address[] memory adds = new address[](4);
        adds[0] = address(u1);
        adds[1] = address(u2);
        adds[2] = address(u3);
        adds[3] = address(u4);
        helper_transferToAdds(adds);
    }

    function helper_deployV3Pool(
        address _token0,
        address _token1,
        uint256 fee,
        uint160 _initialPoolPrice
    ) internal returns (address _pool) {
        UniswapV3Factory fac = new UniswapV3Factory();
        _pool = fac.createPool(token0, token1, uint24(fee));
        UniswapV3Pool(_pool).initialize(_initialPoolPrice);
    }

    function helper_changeRedemptionPrice(uint256 newPrice) public {
        oracle.setSystemCoinPrice(newPrice);
    }

    function helper_changeCollateralPrice(uint256 newPrice) public {
        oracle.setCollateralPrice(newPrice);
    }

    function helper_transferToAdds(address[] memory adds) internal {
        for (uint256 i = 0; i < adds.length; i++) {
            testWeth.transfer(adds[i], 100000 ether);
            testRai.transfer(adds[i], 100000 ether);
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
