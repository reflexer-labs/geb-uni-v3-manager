pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "../GebUniswapv3LiquidityManager.sol";
import "../../lib/geb-deploy/src/test/GebDeploy.t.base.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";
import "./TestHelpers.sol";

contract GebUniswapv3LiquidtyManagerTest is GebDeployTestBase {
    GebUniswapV3LiquidityManager manager;
    UniswapV3Pool pool;
    TestRAI testRai;
    TestWETH testWeth;
    address token0;
    address token1;

    uint256 threshold = 500000; //50%
    uint256 delay = 120 minutes; //10 minutes

    uint160 initialPoolPrice = 25054144837504793118641380156;

    PoolUser u1;
    PoolUser u2;
    PoolUser u3;
    PoolUser u4_whale;

    function setUp() public override {
        // Depoly GEB
        super.setUp();

        deployIndex(bytes32("ENGLISH"));
        helper_addAuth();
        // Deploy each token
        testRai = new TestRAI("RAI");
        testWeth = new TestWETH("WETH");
        (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));

        // Deploy Pool
        pool = UniswapV3Pool(helper_deployV3Pool(token0, token1, 500));

        //We have to give an inital price to the wethUsd // This meas 10:1(10 RAI for 1 ETH).
        //This number is the sqrt of the price = sqrt(0.1) multiplied by 2 ** 96
        pool.initialize(uint160(initialPoolPrice));
        manager = new GebUniswapV3LiquidityManager(
            "Geb-Uniswap-Manager",
            "GUM",
            address(testRai),
            threshold,
            delay,
            address(pool),
            bytes32("ETH"),
            oracleRelayer
        );

        u1 = new PoolUser(manager);
        u2 = new PoolUser(manager);
        u3 = new PoolUser(manager);
        u4_whale = new PoolUser(manager);

        address[] memory adds = new address[](3);
        adds[0] = address(u1);
        adds[1] = address(u2);
        adds[2] = address(u3);
        helper_transferToAdds(adds);

        //Make the pool start with some spread out liquidity
        helper_addWhaleLiquidity();
    }

    function test_sanity_uint_variables() public {
        uint256 _delay = manager.delay();
        assertTrue(_delay == delay);

        uint256 _threshold = manager.threshold();
        assertTrue(_threshold == threshold);
    }

    function test_sanity_variables_address() public {
        address token0_ = manager.token0();
        assertTrue(token0_ == address(testRai) || token0_ == address(testWeth));

        address token1_ = manager.token1();
        assertTrue(token1_ == address(testRai) || token1_ == address(testWeth));

        address pool_ = address(manager.pool());
        assertTrue(pool_ == address(pool));

        address relayer_ = address(manager.oracleRelayer());
        assertTrue(relayer_ == address(oracleRelayer));
    }

    function test_sanity_pool() public {
        address token0_ = pool.token0();
        assertTrue(token0_ == token0);

        address token1_ = pool.token1();
        assertTrue(token1_ == token1);

        (uint160 poolPrice_, , , , , , ) = pool.slot0();
        assertTrue(poolPrice_ == initialPoolPrice);
    }

    function test_adding_liquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u1.doApprove(address(testRai), address(manager), raiAmount);
        u1.doApprove(address(testWeth), address(manager), wethAmount);

        (uint160 currPrice, , , , , , ) = pool.slot0();
        (int24 newLower, int24 newUpper) = manager.getNextTicks();

        uint128 liq = helper_getLiquidityAmountsForTicks(currPrice, newLower, newUpper, 10 ether, 1 ether);
        emit log_named_uint("liq", liq);

        {
            (int24 _nlower, int24 _nupper) = manager.getNextTicks();

            (uint160 currPrice, , , , , , ) = pool.slot0();
            (, uint256 amount1) =
                LiquidityAmounts.getAmountsForLiquidity(currPrice, TickMath.getSqrtRatioAtTick(_nlower), TickMath.getSqrtRatioAtTick(_nupper), liq);

            uint256 balBefore = testWeth.balanceOf(address(u1));

            u1.doDeposit(liq);

            uint256 balAfter = testWeth.balanceOf(address(u1));
            emit log_named_uint("initEth", (balBefore - balAfter) / amount1);
            assertTrue((balBefore - balAfter) / amount1 == 1);
        }

        (bytes32 id, , , uint128 uniLiquidity) = manager.position();
        (uint128 _liquidity, , , , ) = pool.positions(id);
        assertTrue(uniLiquidity == _liquidity);

        uint256 liquidityReceived = manager.totalSupply();
        assertTrue(liquidityReceived == liq);

        uint256 liqReceived = manager.balanceOf(address(u1));
        assertTrue(liqReceived == liq);
    }

    function test_rebalancing_pool() public {
        helper_addLiquidity(); //Starting with a bit of liquidity
        (uint256 red, ) = manager.getPrices();

        (bytes32 init_id, int24 init_lowerTick, int24 init_upperTick, uint128 init_uniLiquidity) = manager.position();
        emit log_named_uint("red", red);
        hevm.warp(2 days); //Advance to the future

        helper_changeRedemptionPrice(500000000 ether); //Making RAI twice more expensive

        (int24 newLower, int24 newUpper) = manager.getNextTicks();

        // The lower bound might still be the same, since is current the MIN_TICK
        assertTrue(init_upperTick != newUpper);

        manager.rebalance();
        // emit log_named_uint("am0", collected0);
        // emit log_named_uint("am1", collected1);

        (uint128 _liquidity, , , , ) = pool.positions(init_id);
        assertTrue(_liquidity == 0); //We should have burned the whole old position

        (bytes32 end_id, int24 end_lowerTick, int24 end_upperTick, uint128 end_uniLiquidity) = manager.position();

        assertTrue(end_uniLiquidity <= init_uniLiquidity);
    }

    function test_burining_liquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;
        helper_addLiquidity(); //Starting with a bit of liquidity

        uint256 liq = manager.balanceOf(address(u1));
        (bytes32 inti_id, , , uint128 inti_uniLiquidity) = manager.position();
        (uint128 _li, , , , ) = pool.positions(inti_id);

        assertTrue(liq == _li);
        emit log_named_uint("liq", inti_uniLiquidity);
        emit log_named_uint("_li", _li);

        //withdraw half of liquidity
        (uint256 bal0, uint256 bal1) = u1.doWithdraw(uint128(liq / 2));
        emit log_named_uint("bal0", bal0);
        emit log_named_uint("bal1", bal1);
        assertTrue(manager.balanceOf(address(u1)) == liq / 2);

        (uint128 _li2, , , , ) = pool.positions(inti_id);
        emit log_named_uint("_li2", _li2);
        emit log_named_uint("_li / 2", _li / 2);
        assertTrue(_li2 == _li / 2);

        (bytes32 end_id, , , uint128 end_uniLiquidity) = manager.position();
        assertTrue(end_uniLiquidity == inti_uniLiquidity / 2);
    }

    function test_multiple_users_adding_liquidity() public {
        uint256 u1_raiAmount = 5 ether;
        uint256 u1_wethAmount = 2 ether;

        u1.doApprove(address(testRai), address(manager), u1_raiAmount);
        u1.doApprove(address(testWeth), address(manager), u1_wethAmount);

        (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity1) = manager.position();
        (uint160 u1_sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 u1_liquidity = helper_getLiquidityAmountsForTicks(u1_sqrtRatioX96, lowerTick, upperTick, 5 ether, 1 ether);

        u1.doDeposit(u1_liquidity);

        // totalSupply should be equal both liquidities
        assertTrue(manager.totalSupply() == uniLiquidity1 + u1_liquidity);

        //Getting new pool information
        (, int24 lowerTick2, int24 upperTick2, uint128 uniLiquidity2) = manager.position();
        assertTrue(uniLiquidity2 == uniLiquidity1 + u1_liquidity);

        //Pool position shouldn't have changed
        assertTrue(lowerTick == lowerTick2);
        assertTrue(upperTick == upperTick2);

        //Makind redemption price double
        helper_changeRedemptionPrice(800000000 ether);

        uint256 u2_raiAmount = 5 ether;
        uint256 u2_wethAmount = 2 ether;

        u2.doApprove(address(testRai), address(manager), u2_raiAmount);
        u2.doApprove(address(testWeth), address(manager), u2_wethAmount);

        (int24 u2_lowerTick, int24 u2_upperTick) = manager.getNextTicks();
        (uint160 u2_sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 u2_liquidity = helper_getLiquidityAmountsForTicks(u2_sqrtRatioX96, u2_lowerTick, u2_upperTick, u2_raiAmount, u2_wethAmount);

        u2.doDeposit(u2_liquidity);

        emit log_named_uint("u2_upperTick", helper_getAbsInt24(u2_upperTick));
        emit log_named_uint("upperTick2", helper_getAbsInt24(upperTick2));
        // totalSupply should be equal both liquidities
        assertTrue(manager.totalSupply() == u1_liquidity + u2_liquidity);
        assertTrue(u2_upperTick > upperTick2);

        // assertTrue(false);
    }

    function test_sqrt_conversion() public {
        //Using uniswap sdk to arrive at those numbers
        (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();

        uint160 sqrtRedPriceX96 = uint160(sqrt((ethUsdPrice * 2**96) / redemptionPrice));
        assertTrue(sqrtRedPriceX96 == 154170194117); //Value taken from uniswap sdk
    }

    function helper_deployV3Pool(
        address _token0,
        address _token1,
        uint256 fee
    ) internal returns (address _pool) {
        UniswapV3Factory fac = new UniswapV3Factory();
        _pool = fac.createPool(token0, token1, uint24(fee));
    }

    function helper_addAuth() public {
        // auth in stabilityFeeTreasury
        address usr = address(govActions);
        bytes32 tag;
        assembly {
            tag := extcodehash(usr)
        }
        bytes memory fax = abi.encodeWithSignature("addAuthorization(address,address)", address(oracleRelayer), address(this));
        uint256 eta = now;
        pause.scheduleTransaction(usr, tag, fax, eta);
        pause.executeTransaction(usr, tag, fax, eta);
    }

    function helper_changeRedemptionPrice(uint256 newPrice) public {
        oracleRelayer.modifyParameters("redemptionPrice", newPrice);
    }

    function helper_transferToAdds(address[] memory adds) public {
        for (uint256 i = 0; i < adds.length; i++) {
            testWeth.transfer(adds[i], 100 ether);
            testRai.transfer(adds[i], 100 ether);
        }
    }

    function helper_addWhaleLiquidity() public {
        uint256 wethAmount = 10000 ether;
        uint256 raiAmount = 100000 ether;

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, -887270, 887270, raiAmount, wethAmount);

        pool.mint(address(u4_whale), -887270, 887270, liq, bytes(""));
    }

    function helper_addLiquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u1.doApprove(address(testRai), address(manager), raiAmount);
        u1.doApprove(address(testWeth), address(manager), wethAmount);

        //Adding liquidty without changing current price. To use the full amount of tokens we would need to add sqrt(10)
        //But we'll add an approximation
        u1.doDeposit(5043482264979044174729352);
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

    function helper_getAbsInt24(int24 val) internal returns (uint256 abs) {
        if (val > 0) {
            abs = uint256(val);
        } else {
            abs = uint256(val * int24(-1));
        }
    }

    function sqrt(uint256 y) public pure returns (uint256 z) {
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
