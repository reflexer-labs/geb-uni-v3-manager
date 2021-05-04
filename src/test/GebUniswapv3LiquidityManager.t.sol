pragma solidity 0.6.7;

import "../../lib/ds-test/src/test.sol";
import "../GebUniswapv3LiquidityManager.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";
import "./TestHelpers.sol";
import "./OracleLikeMock.sol";

contract GebUniswapv3LiquidityManagerTest is DSTest {
    Hevm hevm;

    GebUniswapV3LiquidityManager manager;
    UniswapV3Pool pool;
    TestRAI testRai;
    TestWETH testWeth;
    OracleLikeMock oracle;
    address token0;
    address token1;

    uint256 threshold = 360000;  // 36%
    uint256 delay = 120 minutes; // 10 minutes

    uint160 initialPoolPrice;

    PoolUser u1;
    PoolUser u2;
    PoolUser u3;
    PoolUser u4;

    PoolUser[4] public users;
    PoolViewer pv;

    function setUp() public {
        // Deploy GEB
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        oracle = new OracleLikeMock();

        // Deploy each token
        testRai = new TestRAI("RAI");
        testWeth = new TestWETH("WETH");
        (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));

        pv = new PoolViewer();

        // Deploy Pool
        pool = UniswapV3Pool(helper_deployV3Pool(token0, token1, 500));

        // We have to give an inital price to WETH
        // This means 10:1 (10 RAI for 1 ETH)
        // This number is the sqrt of the price = sqrt(0.1) multiplied by 2 ** 96
        manager = new GebUniswapV3LiquidityManager("Geb-Uniswap-Manager", "GUM", address(testRai), threshold, delay, address(pool), bytes32("ETH"), oracle, pv);

        //Will initialize the pool with current price
        initialPoolPrice = helper_getRebalancePrice();
        pool.initialize(initialPoolPrice);

        u1 = new PoolUser(manager, pool, testRai, testWeth);
        u2 = new PoolUser(manager, pool, testRai, testWeth);
        u3 = new PoolUser(manager, pool, testRai, testWeth);
        u4 = new PoolUser(manager, pool, testRai, testWeth);

        users[0] = u1;
        users[1] = u2;
        users[2] = u3;
        users[3] = u4;

        helper_transferToAdds(users);

        // Make the pool start with some spread out liquidity
        helper_addWhaleLiquidity();
    }

    // --- Math ---
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

    // --- Helpers ---
    function helper_deployV3Pool(
        address _token0,
        address _token1,
        uint256 fee
    ) internal returns (address _pool) {
        UniswapV3Factory fac = new UniswapV3Factory();
        _pool = fac.createPool(token0, token1, uint24(fee));
    }

    function helper_changeRedemptionPrice(uint256 newPrice) public {
        oracle.setSystemCoinPrice(newPrice);
    }

    function helper_transferToAdds(PoolUser[4] memory adds) public {
        for (uint256 i = 0; i < adds.length; i++) {
            testWeth.transfer(address(adds[i]), 30000 ether);
            testRai.transfer(address(adds[i]), 120000000000 ether);
        }
    }

    function helper_getRebalancePrice() public returns (uint160) {
        // 1. Get prices from the oracle
        (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();

        // 2. Calculate the price ratio
        uint160 sqrtPriceX96;
        if (!(address(pool.token0()) == address(testRai))) {
            sqrtPriceX96 = uint160(sqrt((redemptionPrice << 96) / ethUsdPrice));
        } else {
            sqrtPriceX96 = uint160(sqrt((ethUsdPrice << 96) / redemptionPrice));
        }
        return sqrtPriceX96;
    }

    function helper_addWhaleLiquidity() public {
        uint256 wethAmount = 300 ether;
        uint256 raiAmount = 1200000000 ether;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, -887270, 887270, wethAmount, raiAmount);
        int24 low = -887270;
        int24 upp = 887270;
        pool.mint(address(this), low, upp, liq, bytes(""));
    }

    function helper_addLiquidity(uint8 user) public {
        (bytes32 i_id, , , uint128 i_uniLiquidity) = manager.position();
        (uint128 i_liquidity, , , , ) = pool.positions(i_id);
        PoolUser u = users[(user - 1) % 4];
        uint256 wethAmount = 3000 ether;
        uint256 raiAmount = 1000000 ether;

        u.doApprove(address(testRai), address(manager), raiAmount);
        u.doApprove(address(testWeth), address(manager), wethAmount);

        (int24 newLower, int24 newUpper, ) = manager.getNextTicks();

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, newLower, newUpper, wethAmount, raiAmount);
        u.doDeposit(liq);
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

    function helper_do_swap() public {
        (uint160 currentPrice, , , , , , ) = pool.slot0();
        uint160 sqrtLimitPrice = currentPrice - 100000000000000;
        pool.swap(address(this), true, 10 ether, sqrtLimitPrice, bytes(""));
    }

    function helper_get_random_zeroForOne_priceLimit(int256 _amountSpecified) internal view returns (uint160 sqrtPriceLimitX96) {
        // help echidna a bit by calculating a valid sqrtPriceLimitX96 using the amount as random seed
        (uint160 currentPrice, , , , , , ) = pool.slot0();
        uint160 minimumPrice = TickMath.MIN_SQRT_RATIO;
        sqrtPriceLimitX96 = minimumPrice + uint160((uint256(_amountSpecified > 0 ? _amountSpecified : -_amountSpecified) % (currentPrice - minimumPrice)));
    }

    function helper_get_random_oneForZero_priceLimit(int256 _amountSpecified) internal view returns (uint160 sqrtPriceLimitX96) {
        // help echidna a bit by calculating a valid sqrtPriceLimitX96 using the amount as random seed
        (uint160 currentPrice, , , , , , ) = pool.slot0();
        uint160 maximumPrice = TickMath.MAX_SQRT_RATIO;
        sqrtPriceLimitX96 = currentPrice + uint160((uint256(_amountSpecified > 0 ? _amountSpecified : -_amountSpecified) % (maximumPrice - currentPrice)));
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        testRai.transfer(msg.sender, amount0Owed);
        testWeth.transfer(msg.sender, amount0Owed);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (address(pool.token0()) == address(testRai)) {
            if (amount0Delta > 0) testRai.transfer(msg.sender, uint256(amount0Delta));
            if (amount1Delta > 0) testWeth.transfer(msg.sender, uint256(amount1Delta));
        } else {
            if (amount1Delta > 0) testRai.transfer(msg.sender, uint256(amount1Delta));
            if (amount0Delta > 0) testWeth.transfer(msg.sender, uint256(amount0Delta));
        }
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

        address relayer_ = address(manager.oracle());
        assertTrue(relayer_ == address(oracle));
    }

    function test_sanity_pool() public {
        address token0_ = pool.token0();
        assertTrue(token0_ == token0);

        address token1_ = pool.token1();
        assertTrue(token1_ == token1);

        (uint160 poolPrice_, , , , , , ) = pool.slot0();
        assertTrue(poolPrice_ == initialPoolPrice);
    }

    function test_modify_threshold() public {
        uint256 newThreshold = 200000;
        manager.modifyParameters(bytes32("threshold"), newThreshold);
        assertTrue(manager.threshold() == newThreshold);
    }

    function testFail_invalid_threshold_tickspacing() public {
        uint256 newThreshold = 400002;
        manager.modifyParameters(bytes32("threshold"), newThreshold);
    }

    function testFail_invalid_threshold() public {
        uint256 newThreshold = 20;
        manager.modifyParameters(bytes32("threshold"), newThreshold);
    }

    function test_modify_delay() public {
        uint256 newDelay = 340 minutes;
        manager.modifyParameters(bytes32("delay"), newDelay);
        assertTrue(manager.delay() == newDelay);
    }

    function testFail_invalid_delay() public {
        uint256 newDelay = 20 days;
        manager.modifyParameters(bytes32("delay"), newDelay);
    }

    function test_modify_oracle() public {
        address newOracle = address(new OracleLikeMock());
        manager.modifyParameters(bytes32("oracle"), newOracle);
        assertTrue(address(manager.oracle()) == newOracle);
    }

    function testFail_modify_invalid_oracle() public {
        address newOracle = address(0x4);
        manager.modifyParameters(bytes32("oracle"), newOracle);
    }

    function testFail_thirdyParty_changingParameter() public {
        bytes memory data = abi.encodeWithSignature("modifyParameters(bytes32,uint256)", bytes32("threshold"), 20000);
        u1.doArbitrary(address(manager), data);
    }

    function testFail_thirdyParty_changingOracle() public {
        bytes memory data = abi.encodeWithSignature("modifyParameters(bytes32,address)", bytes32("oracle"), address(4));
        u1.doArbitrary(address(manager), data);
    }

    function test_get_prices() public {
        (uint256 redemptionPrice, uint256 tokenPrice) = manager.getPrices();
        assertTrue(redemptionPrice == 1200000000 ether);
        assertTrue(tokenPrice == 300 ether);
    }

    function test_get_next_ticks() public {
        (int24 _nextLowerTick, int24 _nextUpperTick, ) = manager.getNextTicks();
        assertTrue(_nextLowerTick >= -887270 && _nextLowerTick <= 0);
        assertTrue(_nextUpperTick >= _nextLowerTick && _nextUpperTick <= 0);
    }

    function test_get_token0_from_liquidity() public {
        helper_addLiquidity(1);
        helper_addLiquidity(2);
        uint128 liq = uint128(manager.balanceOf(address(u2)));

        uint256 tkn0Amt = manager.getToken0FromLiquidity(liq);

        (uint256 amount0, ) = u2.doWithdraw(liq);

        emit log_named_uint("tkn0Amt", tkn0Amt);
        emit log_named_uint("amount0", amount0);
        assertTrue(tkn0Amt == amount0);
    }

    function test_get_token0_from_liquidity_burning() public {
        helper_addLiquidity(1);
        helper_addLiquidity(2);
        uint128 liq = uint128(manager.balanceOf(address(u2)));

        uint256 tkn0Amt = manager.getToken0FromLiquidity(liq);
        emit log_named_address("man", address(manager));

        (uint256 amount0, ) = u2.doWithdraw(liq);

        emit log_named_uint("tkn0Amt", tkn0Amt);
        emit log_named_uint("amount0", amount0);
        assertTrue(tkn0Amt == amount0);
    }

    function test_get_token1_from_liquidity() public {
        helper_addLiquidity(1);
        helper_addLiquidity(2);
        uint128 liq = uint128(manager.balanceOf(address(u2)));

        uint256 tkn1Amt = manager.getToken1FromLiquidity(liq);

        (, uint256 amount1) = u2.doWithdraw(liq);

        emit log_named_uint("tkn1Amt", tkn1Amt);
        emit log_named_uint("amount1", amount1);
        assertTrue(tkn1Amt == amount1);
    }

    function test_example() public {
        // --- User 1 deposits in pool ---
        helper_addLiquidity(1);
        uint256 balance_u1 = manager.balanceOf(address(u1));
        emit log_named_uint("balance_u1", balance_u1); // 21316282116

        // --- If one were to withdraw ---
        (uint256 amount0, uint256 amount1) = manager.getTokenAmountsFromLiquidity(uint128(balance_u1));
        emit log_named_uint("amount0", amount0); // 2999999999751809927114
        emit log_named_uint("amount1", amount1); // 0

        // We need some pool info
        (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity1) = manager.position();
        (uint160 u1_sqrtRatioX96, , , , , , ) = pool.slot0();

        // --- Trying again using both amounts---
        // 1. With 0 for amount1
        uint128 u1_liquidity = helper_getLiquidityAmountsForTicks(u1_sqrtRatioX96, lowerTick, upperTick, amount0, amount1);
        emit log_named_uint("u1_liquidity", u1_liquidity); // 0

        // 2. With 1 for amount1
        uint128 u2_liquidity = helper_getLiquidityAmountsForTicks(u1_sqrtRatioX96, lowerTick, upperTick, amount0, 1);
        emit log_named_uint("u2_liquidity", u2_liquidity); // 21316282114 -> quite close to the inital liquidity amount
    }

    function test_adding_liquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u1.doApprove(address(testRai), address(manager), raiAmount);
        u1.doApprove(address(testWeth), address(manager), wethAmount);

        (uint160 price1, , , , , , ) = pool.slot0();
        (int24 newLower, int24 newUpper, ) = manager.getNextTicks();

        uint128 liq = helper_getLiquidityAmountsForTicks(price1, newLower, newUpper, 1 ether, 10 ether);
        emit log_named_uint("liq", liq);

        {
            (int24 _nlower, int24 _nupper, ) = manager.getNextTicks();

            (uint160 currPrice, , , , , , ) = pool.slot0();
            (uint256 amount0, ) =
                LiquidityAmounts.getAmountsForLiquidity(currPrice, TickMath.getSqrtRatioAtTick(_nlower), TickMath.getSqrtRatioAtTick(_nupper), liq);

            uint256 balBefore = testWeth.balanceOf(address(u1));

            u1.doDeposit(liq);

            uint256 balAfter = testWeth.balanceOf(address(u1));
            emit log_named_uint("initEth", (balBefore - balAfter) / amount0);
            assertTrue((balBefore - balAfter) / amount0 == 1);
        }

        (bytes32 id, , , uint128 uniLiquidity) = manager.position();
        (uint128 _liquidity, , , , ) = pool.positions(id);
        assertTrue(uniLiquidity == _liquidity);

        uint256 liquidityReceived = manager.totalSupply();
        assertTrue(liquidityReceived == liq);

        uint256 liqReceived = manager.balanceOf(address(u1));
        assertTrue(liqReceived == liq);
    }

    function testFail_adding_zero_liquidity() public {
        u2.doDeposit(0);
    }

    function test_rebalancing_pool() public {
        // Start with little liquidity
        helper_addLiquidity(1);
        helper_addLiquidity(2);
        helper_addLiquidity(3);

        testRai.approve(address(manager), 10);
        testWeth.approve(address(manager), 10);

        (uint256 red, uint256 usd) = manager.getPrices();
        emit log_named_uint("red", red);
        emit log_named_uint("usd", usd);

        (bytes32 init_id, int24 init_lowerTick, int24 init_upperTick, uint128 init_uniLiquidity) = manager.position();
        if (init_lowerTick > 0) {
            emit log_named_uint("pos init_lowerTick", helper_getAbsInt24(init_lowerTick));
        } else {
            emit log_named_uint("neg init_lowerTick", helper_getAbsInt24(init_lowerTick));
        }

        if (init_upperTick > 0) {
            emit log_named_uint("pos init_upperTick", helper_getAbsInt24(init_upperTick));
        } else {
            emit log_named_uint("neg init_upperTick", helper_getAbsInt24(init_upperTick));
        }
        hevm.warp(2 days); // Advance to the future

        helper_changeRedemptionPrice(1400000000 ether); // Making RAI a bit more expensive

        (int24 newLower, int24 newUpper, ) = manager.getNextTicks();
        if (newLower > 0) {
            emit log_named_uint("pos newLower", helper_getAbsInt24(newLower));
        } else {
            emit log_named_uint("neg newLower", helper_getAbsInt24(newLower));
        }

        if (newUpper > 0) {
            emit log_named_uint("pos newUpper", helper_getAbsInt24(newUpper));
        } else {
            emit log_named_uint("neg newUpper", helper_getAbsInt24(newUpper));
        }

        // The lower bound might still be the same, since it's currently the MIN_TICK
        assertTrue(init_upperTick != newUpper);

        manager.rebalance();
        // emit log_named_uint("am0", collected0);
        // emit log_named_uint("am1", collected1);

        (uint128 _liquidity, , , , ) = pool.positions(init_id);
        assertTrue(_liquidity == 0); //We should have burned the whole old position

        (bytes32 end_id, int24 end_lowerTick, int24 end_upperTick, uint128 end_uniLiquidity) = manager.position();

        emit log_named_uint("end_uniLiquidity", end_uniLiquidity);
        emit log_named_uint("init_uniLiquidity", init_uniLiquidity);
        assertTrue(end_uniLiquidity <= init_uniLiquidity);
        // assertTrue(false);
    }

    function testFail_early_rebalancing() public {
        hevm.warp(2 days);    // Advance to the future
        manager.rebalance();  // Should pass
        hevm.warp(2 minutes); // Advance to the future
        manager.rebalance();  // Should fail
    }

    function test_withdrawing_liquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;
        helper_addLiquidity(1); // Starting with a bit of liquidity

        uint256 liq = manager.balanceOf(address(u1));
        (bytes32 inti_id, , , uint128 inti_uniLiquidity) = manager.position();
        (uint128 _li, , , , ) = pool.positions(inti_id);

        assertTrue(liq == _li);
        emit log_named_uint("liq", liq);
        emit log_named_uint("liq", inti_uniLiquidity);
        emit log_named_uint("_li", _li);

        // Withdraw half of the liquidity
        (uint256 bal0, uint256 bal1) = u1.doWithdraw(uint128(liq / 2));
        emit log_named_uint("bal0", liq / 2);
        emit log_named_uint("bal1", manager.balanceOf(address(u1)));
        assertTrue(manager.balanceOf(address(u1)) == liq / 2);

        (uint128 _li2, , , , ) = pool.positions(inti_id);
        emit log_named_uint("_li2", _li2);
        emit log_named_uint("_li / 2", _li / 2);
        assertTrue(_li2 == _li / 2);

        (bytes32 end_id, , , uint128 end_uniLiquidity) = manager.position();
        emit log_named_uint("inti_uniLiquidity", inti_uniLiquidity / 2);
        emit log_named_uint("end_uniLiquidity", end_uniLiquidity);
        assertTrue(end_uniLiquidity == inti_uniLiquidity / 2);
    }

    function testFail_withdrawing_zero_liq() public {
        helper_addLiquidity(3); //Starting with a bit of liquidity
        u3.doWithdraw(0);
    }

    function testFail_calling_uni_callback() public {
        manager.uniswapV3MintCallback(0, 0, "");
    }

    function test_collecting_fees() public {
        (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();
        emit log_named_uint("redemptionPrice", redemptionPrice); // redemptionPrice: 1000000000000000000000000000
        emit log_named_uint("ethUsdPrice", ethUsdPrice);         // ethUsdPrice: 300000000000000000000

        (uint160 price0, int24 tick0, , , , , ) = pool.slot0();
        emit log_named_uint("price1", price0);
        if (tick0 > 0) {
            emit log_named_uint("pos tick0", helper_getAbsInt24(tick0));
        } else {
            emit log_named_uint("neg tick0", helper_getAbsInt24(tick0));
        }

        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u2.doApprove(address(testRai), address(manager), raiAmount);
        u2.doApprove(address(testWeth), address(manager), wethAmount);

        (uint160 price1, , , , , , ) = pool.slot0();
        (int24 newLower, int24 newUpper, ) = manager.getNextTicks();

        uint128 liq = helper_getLiquidityAmountsForTicks(price1, newLower, newUpper, 1 ether, 10 ether);

        uint256 bal0w = testWeth.balanceOf(address(u2));
        uint256 bal0r = testRai.balanceOf(address(u2));
        u2.doDeposit(liq);

        helper_do_swap();

        u2.doWithdraw(liq);

        uint256 bal1w = testWeth.balanceOf(address(u2));
        uint256 bal1r = testRai.balanceOf(address(u2));
        emit log_named_uint("bal0w", bal0w);
        emit log_named_uint("bal0r", bal0r);
        emit log_named_uint("bal1w", bal1w);
        emit log_named_uint("bal1r", bal1r);

        (uint160 price2, , , , , , ) = pool.slot0();

        emit log_named_uint("price1", price1);
        emit log_named_uint("price2", price2);

        (bytes32 id, , , ) = manager.position();
        (uint128 _liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(id);

        emit log_named_uint("_liquidity", _liquidity);
        emit log_named_uint("feeGrowthInside0LastX128", feeGrowthInside0LastX128);
        emit log_named_uint("feeGrowthInside1LastX128", feeGrowthInside1LastX128);
        emit log_named_uint("tokensOwed0", tokensOwed0);
        emit log_named_uint("tokensOwed1", tokensOwed1);

        assertTrue(bal1w > bal0w);
    }

    function test_multiple_users_depositing() public {
        helper_addLiquidity(1); // Starting with a bit of liquidity
        uint256 u1_balance = manager.balanceOf(address(u1));
        assert(u1_balance == manager.totalSupply());

        helper_addLiquidity(2); // Starting with a bit of liquidity
        uint256 u2_balance = manager.balanceOf(address(u2));
        assert(u1_balance + u2_balance == manager.totalSupply());

        helper_addLiquidity(3); // Starting with a bit of liquidity
        uint256 u3_balance = manager.balanceOf(address(u3));
        assert(u1_balance + u2_balance + u3_balance == manager.totalSupply());
    }

    function test_mint_transfer_and_burn() public {
        helper_addLiquidity(1); //Starting with a bit of liquidity
        u1.doTransfer(address(manager), address(u3), manager.balanceOf(address(u1)));
        u3.doWithdraw(uint128(manager.balanceOf(address(u3))));
    }

    function test_liquidty_proportional_to_balance() public {
        testRai.approve(address(manager), 10);
        testWeth.approve(address(manager), 10);
        helper_addLiquidity(1);

        // Make RAI twice more expensive
        helper_changeRedemptionPrice(2000000000 ether);

        // Add some liquidity
        helper_addLiquidity(1);

        // Return to the original price
        helper_changeRedemptionPrice(1200000000 ether);
        hevm.warp(2 days);

        manager.rebalance();

        (bytes32 id, , , uint128 uniLiquidity1) = manager.position();
        (uint128 _liquidity, , , , ) = pool.positions(id);
        emit log_named_uint("_liquidity", _liquidity);
        emit log_named_uint("liq", uniLiquidity1);
        emit log_named_uint("bal", manager.balanceOf(address(u1)));

        // user should be able to withdraw their whole balance. Balance != Liquidity
        u1.doWithdraw(uint128(manager.balanceOf(address(u1))));
    }

    function test_multiple_users_adding_liquidity() public {
        uint256 u1_raiAmount = 5 ether;
        uint256 u1_wethAmount = 2 ether;

        u1.doApprove(address(testRai), address(manager), u1_raiAmount);
        u1.doApprove(address(testWeth), address(manager), u1_wethAmount);

        (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity1) = manager.position();
        (uint160 u1_sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 u1_liquidity = helper_getLiquidityAmountsForTicks(u1_sqrtRatioX96, lowerTick, upperTick, u1_wethAmount, u1_raiAmount);

        u1.doDeposit(u1_liquidity);

        // totalSupply should equal the sum of both liquidity amounts
        assertTrue(manager.totalSupply() == uniLiquidity1 + u1_liquidity);

        // Getting new pool information
        (, int24 lowerTick2, int24 upperTick2, uint128 uniLiquidity2) = manager.position();
        assertTrue(uniLiquidity2 == uniLiquidity1 + u1_liquidity);

        // Pool position shouldn't have changed
        assertTrue(lowerTick == lowerTick2);
        assertTrue(upperTick == upperTick2);

        // Make the redemption price change
        helper_changeRedemptionPrice(800000000 ether);

        uint256 u2_raiAmount = 5 ether;
        uint256 u2_wethAmount = 2 ether;

        u2.doApprove(address(testRai), address(manager), u2_raiAmount);
        u2.doApprove(address(testWeth), address(manager), u2_wethAmount);

        (int24 u2_lowerTick, int24 u2_upperTick, ) = manager.getNextTicks();
        (uint160 u2_sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 u2_liquidity = helper_getLiquidityAmountsForTicks(u2_sqrtRatioX96, u2_lowerTick, u2_upperTick, u2_wethAmount, u2_raiAmount);

        u2.doDeposit(u2_liquidity);

        emit log_named_uint("u2_upperTick", helper_getAbsInt24(u2_upperTick));
        emit log_named_uint("upperTick2", helper_getAbsInt24(upperTick2));
        // totalSupply should be equal to the sum of the liquidity amounts
        assertTrue(manager.totalSupply() == u1_liquidity + u2_liquidity);
        assertTrue(u2_upperTick < upperTick2);

        // assertTrue(false);
    }

    function test_getNextTicks_return_correctly() public {
        helper_addLiquidity(1); // Starting with a bit of liquidity
        helper_addLiquidity(2); // Starting with a bit of liquidity
        helper_addLiquidity(3); // Starting with a bit of liquidity

        testRai.approve(address(manager), 10);
        testWeth.approve(address(manager), 10);
        hevm.warp(2 days); // Advance to the future

        helper_changeRedemptionPrice(800000000 ether);
        (int24 lower, int24 upper, int24 price) = manager.getNextTicks();

        manager.rebalance();

        (bytes32 end_id, int24 end_lowerTick, int24 end_upperTick, uint128 end_uniLiquidity) = manager.position();
        assertTrue(lower == end_lowerTick);
        assertTrue(upper == end_upperTick);
    }

    function test_getter_return_correct_amount() public {
        helper_addLiquidity(1); //Starting with a bit of liquidity

        uint256 balance_u1 = manager.balanceOf(address(u1));

        (uint256 amount0, uint256 amount1) = manager.getTokenAmountsFromLiquidity(uint128(balance_u1));

        (uint256 ac_amount0, uint256 ac_amount1) = u1.doWithdraw(uint128(balance_u1));

        assertTrue(amount0 == ac_amount0);
        assertTrue(amount1 == ac_amount1);
    }

    function test_sqrt_conversion() public {
        // Using the Uniswap SDK to arrive at those numbers
        (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();

        uint160 sqrtRedPriceX96 = uint160(sqrt((ethUsdPrice * 2**96) / redemptionPrice));
        assertTrue(sqrtRedPriceX96 == 140737488355); // Value taken from Uniswap SDK
    }

    function testFail_try_minting_zero_liquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u1.doApprove(address(testRai), address(manager), raiAmount);
        u1.doApprove(address(testWeth), address(manager), wethAmount);

        emit log_named_uint("depositing", 0);
        u1.doDeposit(0);
    }

    function testFail_minting_largest_liquidity() public {
        uint256 wethAmount = 1 ether;
        uint256 raiAmount = 10 ether;

        u1.doApprove(address(testRai), address(manager), raiAmount);
        u1.doApprove(address(testWeth), address(manager), wethAmount);

        emit log_named_uint("depositing", 0);
        u1.doDeposit(uint128(0 - 1));
    }

    function testFail_burning_zero_liquidity() public {
        helper_addLiquidity(3);

        u3.doWithdraw(0);
    }

    function testFail_burning_more_than_owned_liquidity() public {
        helper_addLiquidity(3);

        u3.doWithdraw(uint128(0 - 1));
    }
}
