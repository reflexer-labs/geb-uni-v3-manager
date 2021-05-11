// pragma solidity ^0.6.7;

// import "../../lib/ds-test/src/test.sol";
// import "../GebUniswapV3TwoTrancheManager.sol";
// import "../uni/UniswapV3Factory.sol";
// import "../uni/UniswapV3Pool.sol";
// import "./TestHelpers.sol";
// import "./OracleLikeMock.sol";

// contract GebUniswapv3TwoTrancheManagerTest is DSTest {
//     Hevm hevm;

//     GebUniswapV3TwoTrancheManager manager;
//     UniswapV3Pool pool;
//     TestRAI testRai;
//     TestWETH testWeth;
//     OracleLikeMock oracle;
//     address token0;
//     address token1;

//     uint256 threshold1 = 200000; //20%
//     uint256 threshold2 = 50000; //5%
//     uint128 ratio1 = 50; //36%
//     uint128 ratio2 = 50; //36%
//     uint256 delay = 120 minutes; //10 minutes

//     uint160 initialPoolPrice;

//     PoolUser u1;
//     PoolUser u2;
//     PoolUser u3;
//     PoolUser u4;

//     PoolUser[4] public users;
//     PoolViewer pv;

//     function setUp() public {
//         // Deploy GEB
//         hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
//         oracle = new OracleLikeMock();

//         // Deploy each token
//         testRai = new TestRAI("RAI");
//         testWeth = new TestWETH("WETH");
//         (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));

//         pv = new PoolViewer();

//         // Deploy Pool
//         pool = UniswapV3Pool(helper_deployV3Pool(token0, token1, 500));

//         // We have to give an inital price to WETH 
//         // This meas 10:1 (10 RAI for 1 ETH)
//         // This number is the sqrt of the price = sqrt(0.1) multiplied by 2 ** 96
//         manager = new GebUniswapV3TwoTrancheManager("Geb-Uniswap-Manager", "GUM", address(testRai), threshold1,threshold2, ratio1,ratio2, uint128(delay), address(pool), oracle, pv);

//         //Will initialize the pool with current price
//         initialPoolPrice = helper_getRebalancePrice();
//         pool.initialize(initialPoolPrice);

//         u1 = new PoolUser(manager, pool, testRai, testWeth);
//         u2 = new PoolUser(manager, pool, testRai, testWeth);
//         u3 = new PoolUser(manager, pool, testRai, testWeth);
//         u4 = new PoolUser(manager, pool, testRai, testWeth);

//         users[0] = u1;
//         users[1] = u2;
//         users[2] = u3;
//         users[3] = u4;

//         helper_transferToAdds(users);

//         // Make the pool start with some spread out liquidity
//         helper_addWhaleLiquidity();
//     }

//     // --- Math ---
//     function sqrt(uint256 y) public pure returns (uint256 z) {
//         if (y > 3) {
//             z = y;
//             uint256 x = y / 2 + 1;
//             while (x < z) {
//                 z = x;
//                 x = (y / x + x) / 2;
//             }
//         } else if (y != 0) {
//             z = 1;
//         }
//     }

//     // --- Helpers ---
//     function helper_deployV3Pool(
//         address _token0,
//         address _token1,
//         uint256 fee
//     ) internal returns (address _pool) {
//         UniswapV3Factory fac = new UniswapV3Factory();
//         _pool = fac.createPool(token0, token1, uint24(fee));
//     }

//     function helper_changeRedemptionPrice(uint256 newPrice) public {
//         oracle.setSystemCoinPrice(newPrice);
//     }

//     function helper_transferToAdds(PoolUser[4] memory adds) public {
//         for (uint256 i = 0; i < adds.length; i++) {
//             testWeth.transfer(address(adds[i]), 30000 ether);
//             testRai.transfer(address(adds[i]), 120000000000 ether);
//         }
//     }

//     function helper_getRebalancePrice() public returns (uint160) {
//         // 1. Get prices from the oracle relayer
//         (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();

//         // 2. Calculate the price ratio
//         uint160 sqrtPriceX96;
//         if (!(address(pool.token0()) == address(testRai))) {
//             sqrtPriceX96 = uint160(sqrt((redemptionPrice << 96) / ethUsdPrice));
//         } else {
//             sqrtPriceX96 = uint160(sqrt((ethUsdPrice << 96) / redemptionPrice));
//         }
//         return sqrtPriceX96;
//     }

//     function helper_addWhaleLiquidity() public {
//         uint256 wethAmount = 300 ether;
//         uint256 raiAmount = 1200000000 ether;
//         (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
//         uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, -887270, 887270, wethAmount, raiAmount);
//         int24 low = -887270;
//         int24 upp = 887270;
//         pool.mint(address(this), low, upp, liq, bytes(""));
//     }

//     function helper_addLiquidity(uint8 user) public {
//         // (bytes32 i_id, , , uint128 i_uniLiquidity,) = manager.position();
//         // (uint128 i_liquidity, , , , ) = pool.positions(i_id);
//         PoolUser u = users[(user - 1) % 4];
//         uint256 wethAmount = 3000 ether;
//         uint256 raiAmount = 1000000 ether;

//         u.doApprove(address(testRai), address(manager), raiAmount);
//         u.doApprove(address(testWeth), address(manager), wethAmount);

//         // (int24 newLower, int24 newUpper, ) = manager.getNextTicks(manager.getTargetTick());

//         // (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
//         // uint128 liq = helper_getLiquidityAmountsForTicks(sqrtRatioX96, newLower, newUpper, wethAmount, raiAmount);
//         u.doDeposit(100000);
//     }

//     function helper_getLiquidityAmountsForTicks(
//         uint160 sqrtRatioX96,
//         int24 _lowerTick,
//         int24 upperTick,
//         uint256 t0am,
//         uint256 t1am
//     ) public returns (uint128 liquidity) {
//         liquidity = LiquidityAmounts.getLiquidityForAmounts(
//             sqrtRatioX96,
//             TickMath.getSqrtRatioAtTick(_lowerTick),
//             TickMath.getSqrtRatioAtTick(upperTick),
//             t0am,
//             t1am
//         );
//     }

//     function helper_getAbsInt24(int24 val) internal returns (uint256 abs) {
//         if (val > 0) {
//             abs = uint256(val);
//         } else {
//             abs = uint256(val * int24(-1));
//         }
//     }

//     function helper_do_swap() public {
//         (uint160 currentPrice, , , , , , ) = pool.slot0();
//         uint160 sqrtLimitPrice = currentPrice - 100000000000000;
//         pool.swap(address(this), true, 10 ether, sqrtLimitPrice, bytes(""));
//     }

//     function helper_get_random_zeroForOne_priceLimit(int256 _amountSpecified) internal view returns (uint160 sqrtPriceLimitX96) {
//         // help echidna a bit by calculating a valid sqrtPriceLimitX96 using the amount as random seed
//         (uint160 currentPrice, , , , , , ) = pool.slot0();
//         uint160 minimumPrice = TickMath.MIN_SQRT_RATIO;
//         sqrtPriceLimitX96 = minimumPrice + uint160((uint256(_amountSpecified > 0 ? _amountSpecified : -_amountSpecified) % (currentPrice - minimumPrice)));
//     }

//     function helper_get_random_oneForZero_priceLimit(int256 _amountSpecified) internal view returns (uint160 sqrtPriceLimitX96) {
//         // help echidna a bit by calculating a valid sqrtPriceLimitX96 using the amount as random seed
//         (uint160 currentPrice, , , , , , ) = pool.slot0();
//         uint160 maximumPrice = TickMath.MAX_SQRT_RATIO;
//         sqrtPriceLimitX96 = currentPrice + uint160((uint256(_amountSpecified > 0 ? _amountSpecified : -_amountSpecified) % (maximumPrice - currentPrice)));
//     }

//     function uniswapV3MintCallback(
//         uint256 amount0Owed,
//         uint256 amount1Owed,
//         bytes calldata data
//     ) external {
//         testRai.transfer(msg.sender, amount0Owed);
//         testWeth.transfer(msg.sender, amount0Owed);
//     }

//     function uniswapV3SwapCallback(
//         int256 amount0Delta,
//         int256 amount1Delta,
//         bytes calldata data
//     ) external {
//         if (address(pool.token0()) == address(testRai)) {
//             if (amount0Delta > 0) testRai.transfer(msg.sender, uint256(amount0Delta));
//             if (amount1Delta > 0) testWeth.transfer(msg.sender, uint256(amount1Delta));
//         } else {
//             if (amount1Delta > 0) testRai.transfer(msg.sender, uint256(amount1Delta));
//             if (amount0Delta > 0) testWeth.transfer(msg.sender, uint256(amount0Delta));
//         }
//     }

//     function test_sanity_uint_variables() public {
//         uint256 _delay = manager.delay();
//         assertTrue(_delay == delay);
//     }

//     function test_sanity_positions() public {
//         (,,,,uint256 _threshold1) = manager.positions(0);
//         assertTrue(_threshold1 == threshold1);
//         uint256 _ratio1 = manager.ratio1();
//         assertTrue(_ratio1 == ratio1);

//         (,,,,uint256 _threshold2) = manager.positions(1);
//         assertTrue(_threshold2 == threshold2);
//         uint256 _ratio2 = manager.ratio2();
//         assertTrue(_ratio2 == ratio2);
//     }
//     function test_sanity_variables_address() public {
//         address token0_ = manager.token0();
//         assertTrue(token0_ == address(testRai) || token0_ == address(testWeth));

//         address token1_ = manager.token1();
//         assertTrue(token1_ == address(testRai) || token1_ == address(testWeth));

//         address pool_ = address(manager.pool());
//         assertTrue(pool_ == address(pool));

//         address relayer_ = address(manager.oracle());
//         assertTrue(relayer_ == address(oracle));
//     }

//     function test_sanity_pool() public {
//         address token0_ = pool.token0();
//         assertTrue(token0_ == token0);

//         address token1_ = pool.token1();
//         assertTrue(token1_ == token1);

//         (uint160 poolPrice_, , , , , , ) = pool.slot0();
//         assertTrue(poolPrice_ == initialPoolPrice);
//     }

//     function test_modify_delay() public {
//         uint256 newDelay = 340 minutes;
//         manager.modifyParameters(bytes32("delay"), newDelay);
//         assertTrue(manager.delay() == newDelay);
//     }

//     function testFail_invalid_delay() public {
//         uint256 newDelay = 20 days;
//         manager.modifyParameters(bytes32("delay"), newDelay);
//     }

//     function test_modify_oracle() public {
//         address newOracle = address(new OracleLikeMock());
//         manager.modifyParameters(bytes32("oracle"), newOracle);
//         assertTrue(address(manager.oracle()) == newOracle);
//     }

//     function testFail_modify_invalid_oracle() public {
//         address newOracle = address(0x4);
//         manager.modifyParameters(bytes32("oracle"), newOracle);
//     }

//     function testFail_thirdyParty_changingOracle() public {
//         bytes memory data = abi.encodeWithSignature("modifyParameters(bytes32,address)", bytes32("oracle"), address(4));
//         u1.doArbitrary(address(manager), data);
//     }

//     function test_get_prices() public {
//         (uint256 redemptionPrice, uint256 tokenPrice) = manager.getPrices();
//         assertTrue(redemptionPrice == 3000000000 ether);
//         assertTrue(tokenPrice == 4000000000000 ether);
//     }

//     function test_get_token0_from_liquidity() public {
//         helper_addLiquidity(1);
//         helper_addLiquidity(2);
//         uint128 liq = uint128(manager.balanceOf(address(u2)));

//         uint256 tkn0Amt = manager.getToken0FromLiquidity(liq);

//         (uint256 amount0, ) = u2.doWithdraw(liq);

//         emit log_named_uint("tkn0Amt", tkn0Amt);
//         emit log_named_uint("amount0", amount0);
//         assertTrue(tkn0Amt == amount0);
//     }

//     function test_get_token0_from_liquidity_burning() public {
//         helper_addLiquidity(1);
//         helper_addLiquidity(2);
//         uint128 liq = uint128(manager.balanceOf(address(u2)));

//         uint256 tkn0Amt = manager.getToken0FromLiquidity(liq);
//         emit log_named_address("man", address(manager));

//         (uint256 amount0, ) = u2.doWithdraw(liq);

//         emit log_named_uint("tkn0Amt", tkn0Amt);
//         emit log_named_uint("amount0", amount0);
//         assertTrue(tkn0Amt == amount0);
//     }

//     function test_get_token1_from_liquidity() public {
//         helper_addLiquidity(1);
//         helper_addLiquidity(2);
//         uint128 liq = uint128(manager.balanceOf(address(u2)));

//         uint256 tkn1Amt = manager.getToken1FromLiquidity(liq);

//         (, uint256 amount1) = u2.doWithdraw(liq);

//         emit log_named_uint("tkn1Amt", tkn1Amt);
//         emit log_named_uint("amount1", amount1);
//         assertTrue(tkn1Amt == amount1);
//     }


//     function testFail_adding_zero_liquidity() public {
//         u2.doDeposit(0);
//     }

//     function testFail_early_rebalancing() public {
//         hevm.warp(2 days); //Advance to the future
//         manager.rebalance(); // should pass
//         hevm.warp(2 minutes); //Advance to the future
//         manager.rebalance(); // should fail
//     }


//     function testFail_withdrawing_zero_liq() public {
//         helper_addLiquidity(3); //Starting with a bit of liquidity
//         u3.doWithdraw(0);
//     }

//     function testFail_calling_uni_callback() public {
//         manager.uniswapV3MintCallback(0, 0, "");
//     }

//     function test_collecting_fees() public {
//         (uint256 redemptionPrice, uint256 ethUsdPrice) = manager.getPrices();
//         emit log_named_uint("redemptionPrice", redemptionPrice); // redemptionPrice: 1000000000000000000000000000
//         emit log_named_uint("ethUsdPrice", ethUsdPrice); // ethUsdPrice: 300000000000000000000

//         (uint160 price0, int24 tick0, , , , , ) = pool.slot0();
//         emit log_named_uint("price1", price0);
//         if (tick0 > 0) {
//             emit log_named_uint("pos tick0", helper_getAbsInt24(tick0));
//         } else {
//             emit log_named_uint("neg tick0", helper_getAbsInt24(tick0));
//         }

//         uint256 wethAmount = 1 ether;
//         uint256 raiAmount = 10 ether;

//         uint256 bal0w = testWeth.balanceOf(address(u2));
//         uint256 bal0r = testRai.balanceOf(address(u2));
//         u2.doDeposit(10000);

//         helper_do_swap();

//         u2.doWithdraw(10000);

//         uint256 bal1w = testWeth.balanceOf(address(u2));
//         uint256 bal1r = testRai.balanceOf(address(u2));
//         emit log_named_uint("bal0w", bal0w);
//         emit log_named_uint("bal0r", bal0r);
//         emit log_named_uint("bal1w", bal1w);
//         emit log_named_uint("bal1r", bal1r);

//         assertTrue(bal1w > bal0w);
//     }

//     function test_multiple_users_depositing() public {
//         helper_addLiquidity(1); //Starting with a bit of liquidity
//         uint256 u1_balance = manager.balanceOf(address(u1));
//         assert(u1_balance == manager.totalSupply());

//         helper_addLiquidity(2); //Starting with a bit of liquidity
//         uint256 u2_balance = manager.balanceOf(address(u2));
//         assert(u1_balance + u2_balance == manager.totalSupply());

//         helper_addLiquidity(3); //Starting with a bit of liquidity
//         uint256 u3_balance = manager.balanceOf(address(u3));
//         assert(u1_balance + u2_balance + u3_balance == manager.totalSupply());
//     }

//     function test_mint_transfer_and_burn() public {
//         helper_addLiquidity(1); //Starting with a bit of liquidity
//         u1.doTransfer(address(manager), address(u3), manager.balanceOf(address(u1)));
//         u3.doWithdraw(uint128(manager.balanceOf(address(u3))));
//     }

//     function test_liquidty_proportional_to_balance() public {
//         testRai.approve(address(manager), 10);
//         testWeth.approve(address(manager), 10);
//         helper_addLiquidity(1);

//         // Make RAI twice more expensive
//         helper_changeRedemptionPrice(2000000000 ether);

//         // Add some liquidity
//         helper_addLiquidity(1);

//         // Return to the original price
//         helper_changeRedemptionPrice(1200000000 ether);
//         hevm.warp(2 days);

//         manager.rebalance();

//         // (bytes32 id, , , uint128 uniLiquidity1) = manager.position();
//         // (uint128 _liquidity, , , , ) = pool.positions(id);
//         // emit log_named_uint("_liquidity", _liquidity);
//         // emit log_named_uint("liq", uniLiquidity1);
//         // emit log_named_uint("bal", manager.balanceOf(address(u1)));
//         // user should be able to withdraw it's whole balance. Balance != Liquidity
//         u1.doWithdraw(uint128(manager.balanceOf(address(u1))));
//     }

    

   

//     function test_getter_return_correct_amount() public {
//         helper_addLiquidity(1); //Starting with a bit of liquidity

//         uint256 balance_u1 = manager.balanceOf(address(u1));

//         (uint256 amount0, uint256 amount1) = manager.getTokenAmountsFromLiquidity(uint128(balance_u1));

//         (uint256 ac_amount0, uint256 ac_amount1) = u1.doWithdraw(uint128(balance_u1));

//         assertTrue(amount0 == ac_amount0);
//         assertTrue(amount1 == ac_amount1);
//     }

//     function testFail_try_minting_zero_liquidity() public {
//         uint256 wethAmount = 1 ether;
//         uint256 raiAmount = 10 ether;

//         u1.doApprove(address(testRai), address(manager), raiAmount);
//         u1.doApprove(address(testWeth), address(manager), wethAmount);

//         emit log_named_uint("depositing", 0);
//         u1.doDeposit(0);
//     }

//     function testFail_minting_largest_liquidity() public {
//         uint256 wethAmount = 1 ether;
//         uint256 raiAmount = 10 ether;

//         u1.doApprove(address(testRai), address(manager), raiAmount);
//         u1.doApprove(address(testWeth), address(manager), wethAmount);

//         emit log_named_uint("depositing", 0);
//         u1.doDeposit(uint128(0 - 1));
//     }

//     function testFail_burning_zero_liquidity() public {
//         helper_addLiquidity(3);

//         u3.doWithdraw(0);
//     }

//     function testFail_burning_more_than_owned_liquidity() public {
//         helper_addLiquidity(3);

//         u3.doWithdraw(uint128(0 - 1));
//     }
// }
