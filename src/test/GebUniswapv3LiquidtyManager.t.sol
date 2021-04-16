pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-math/math.sol";
import "../GebUniswapv3LiquidtyManager.sol";
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
  uint256 delay = 20 minutes; //10 minutes

  uint160 initialPoolPrice = 25054144837504793118641380156;

  PoolUser u1;
  PoolUser u2;
  PoolUser u3;

  function setUp() public override {
    // Depoly GEB
    super.setUp();

    deployIndex(bytes32("ENGLISH"));
    // helper_addAuth();
    // Deploy each token
    testRai = new TestRAI("RAI");
    testWeth = new TestWETH("WETH");
    (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));

    // Deploy Pool
    pool = UniswapV3Pool(helper_deployV3Pool(token0, token1, 500));
    emit log_named_address("pol", address(pool));

    //We have to give an inital price to the wethUsd // This meas 10:1(10 RAI for 1 ETH).
    //This number is the sqrt of the price = sqrt(0.1) multiplied by 2 ** 96
    pool.initialize(uint160(initialPoolPrice));
    manager = new GebUniswapV3LiquidityManager("Geb-Uniswap-Manager", "GUM", address(testRai), threshold, delay, address(pool), oracleRelayer);

    u1 = new PoolUser(manager);
    u2 = new PoolUser(manager);
    u3 = new PoolUser(manager);

    // address[] memory adds = new address[](3);
    // adds[0] = address(u1);
    // adds[1] = address(u2);
    // adds[2] = address(u3);
    // helper_transferAndApprove(adds);
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
    //Before making deposit, we need to send tokens to the pool
    //Those values are roughly the amount needed for 1e18 of liquidity
    testRai.transfer(address(manager), raiAmount);
    testWeth.transfer(address(manager), wethAmount);
    address p = address(manager.pool());
    emit log_named_address("pool", p);

    //Adding liquidty without changing current price. To use the full amount of tokens we would need to add sqrt(10)
    //But we'll add an approximation
    manager.deposit(3.15 ether);
    (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity) = manager.position();
    (uint128 _li, , , , ) = pool.positions(id);
    emit log_named_uint("liq", uniLiquidity);
    emit log_named_uint("_li", _li);

    uint256 liquidityReceived = manager.totalSupply();
    assertTrue(liquidityReceived == 3.15 ether);

    uint256 liqReceived = manager.balanceOf(address(this));
    assertTrue(liqReceived == 3.15 ether);

    uint256 bal0 = testRai.balanceOf(address(pool));
    uint256 bal1 = testWeth.balanceOf(address(pool));
    //there's some leftover coins in the manager contract, so rounding here is needed
    assertTrue(bal0 / raiAmount == 0);
    assertTrue(bal1 / wethAmount == 0);

    bytes32 positionID = keccak256(abi.encodePacked(address(manager), int24(-887270), int24(887270)));
    (uint128 _liquidity, , , , ) = pool.positions(positionID);
    // emit log_named_uint("liq", _liquidity);
    // emit log_named_uint("bal0", bal0 / raiAmount);
    // emit log_named_uint("bal1", bal1 / wethAmount);
    //assertTrue(false);
  }

  function test_deposit_and_Rebalancing() public {
    uint256 wethAmount = 1 ether;
    uint256 raiAmount = 10 ether;
    //Before making deposit, we need to send tokens to the pool
    //Those values are roughly the amount needed for 1e18 of liquidity
    testRai.transfer(address(manager), raiAmount);
    testWeth.transfer(address(manager), wethAmount);
    address p = address(manager.pool());
    emit log_named_address("pool", p);

    //Adding liquidty without changing current price. To use the full amount of tokens we would need to add sqrt(10)
    //But we'll add an approximation
    manager.depositAndRabalance(3.15 ether);
    (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity) = manager.position();
    (uint128 _li, , , , ) = pool.positions(id);
    emit log_named_uint("liq", uniLiquidity);
    emit log_named_uint("_li", _li);

    uint256 liquidityReceived = manager.totalSupply();
    assertTrue(liquidityReceived == 3.15 ether);

    uint256 liqReceived = manager.balanceOf(address(this));
    assertTrue(liqReceived == 3.15 ether);

    uint256 bal0 = testRai.balanceOf(address(pool));
    uint256 bal1 = testWeth.balanceOf(address(pool));
    //there's some leftover coins in the manager contract, so rounding here is needed
    assertTrue(bal0 / raiAmount == 0);
    assertTrue(bal1 / wethAmount == 0);

    // bytes32 positionID = keccak256(abi.encodePacked(address(manager), int24(-887270), int24(887270)));
    // (uint128 _liquidity, , , , ) = pool.positions(positionID);
    // emit log_named_uint("liq", _liquidity);
    // emit log_named_uint("bal0", bal0 / raiAmount);
    // emit log_named_uint("bal1", bal1 / wethAmount);
    //assertTrue(false);
  }

  function test_rebalancing_pool() public {
    helper_addLiquidity(); //Starting with a bit of liquidity
    uint256 redemptionPrice = oracleRelayer.redemptionPrice();
    (OracleLike oracle, , ) = oracleRelayer.collateralTypes(bytes32("ETH"));
    (uint256 ethUsd, bool valid) = oracle.getResultWithValidity();
    assertTrue(valid);

    uint160 sqrtRedPriceX96 = uint160(sqrt((ethUsd * 2**96) / redemptionPrice));
    int24 targetTick = TickMath.getTickAtSqrtRatio(sqrtRedPriceX96);
    int24 spacedTick = targetTick - (targetTick % 10);

    manager.rebalance();

    (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity) = manager.position();

    uint256 bal0 = testRai.balanceOf(address(pool));
    uint256 bal1 = testWeth.balanceOf(address(pool));
    uint256 bal2 = testRai.balanceOf(address(manager));
    uint256 bal3 = testWeth.balanceOf(address(manager));
    //Sums of tokens are consistent
    assert(bal2 + bal0 == 10 ether);
    assert(bal3 + bal1 == 1 ether);

    (uint160 currPrice, , , , , , ) = pool.slot0();
    uint256 liq =
      LiquidityAmounts.getLiquidityForAmounts(currPrice, TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(upperTick), bal0, bal1);
    assertTrue(uniLiquidity / liq == 0);
  }

  function test_burining_liquidity() public {
    uint256 wethAmount = 1 ether;
    uint256 raiAmount = 10 ether;
    helper_addLiquidity(); //Starting with a bit of liquidity
    uint256 balanceBefore = testRai.balanceOf(address(this));

    uint256 liq = manager.balanceOf(address(this));
    (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity) = manager.position();
    (uint128 _li, , , , ) = pool.positions(id);
    emit log_named_uint("liq", uniLiquidity);
    emit log_named_uint("_li", _li);

    //withdraw half of liquidity
    manager.withdraw(liq / 2);
    assertTrue(manager.balanceOf(address(this)) == liq / 2);

    (uint128 _li2, , , , ) = pool.positions(id);
    emit log_named_uint("_li2", _li2);

    uint256 balanceAfter = testRai.balanceOf(address(this));
    emit log_named_uint("bal", balanceAfter - balanceBefore);
    emit log_named_uint("bal3", raiAmount / 2);
    assertTrue((balanceAfter - balanceBefore) / raiAmount / 2 == 0);
    //assertTrue(false);
  }

  function test_multiple_users_adding_liquidity() public {
    // helper_addLiquidity(); //Starting with a bit of liquidity

    (uint160 u1_sqrtRatioX96, , , , , , ) = pool.slot0();

    //Should make market price increase
    uint256 u1_raiAmount = 5 ether;
    uint256 u1_wethAmount = 2 ether;
    //Before making deposit, we need to send tokens to the pool
    //Those values are roughly the amount needed for 1e18 of liquidity
    testWeth.transfer(address(manager), u1_raiAmount);
    testRai.transfer(address(manager), u1_wethAmount);

    (bytes32 id, int24 lowerTick, int24 upperTick, uint128 uniLiquidity1) = manager.position();

    uint128 u1_liquidity = helper_getLiquidityAmountsForTicks(u1_sqrtRatioX96, lowerTick, upperTick, 5 ether, 1 ether);

    uint128 max = pool.maxLiquidityPerTick();
    emit log_named_uint("max", max);
    emit log_named_uint("u1", u1_liquidity);
    emit log_named_uint("uni", uniLiquidity1);

    u1.doDeposit(u1_liquidity);

    // totalSupply should be equal both liquidities
    assertTrue(manager.totalSupply() == uniLiquidity1 + u1_liquidity);

    //Getting new pool information
    (bytes32 _, int24 lowerTick2, int24 upperTick2, uint128 uniLiquidity2) = manager.position();
    assertTrue(uniLiquidity2 == uniLiquidity1 + u1_liquidity);

    //Pool position shouldn't have changed
    assertTrue(lowerTick == lowerTick2);
    assertTrue(upperTick == upperTick2);
    // assertTrue(false);
  }

  // HELPER FUNCTIONS

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

  // function helper_transferAndApprove(address[] memory adds) public {
  //   for (uint256 i = 0; i < adds.length; i++) {
  //     testWeth.transfer(adds[i], 3 ether);
  //     testRai.transfer(adds[i], 3 ether);

  //     PoolUser(address(adds[i]).approve(address(testRai), 3 ether));
  //     PoolUser(address(adds[i]).approve(address(testWeth), 3 ether));
  //   }
  // }

  function helper_addLiquidity() public {
    uint256 wethAmount = 1 ether;
    uint256 raiAmount = 10 ether;
    //Before making deposit, we need to send tokens to the pool
    //Those values are roughly the amount needed for 1e18 of liquidity
    testRai.transfer(address(manager), raiAmount);
    testWeth.transfer(address(manager), wethAmount);

    //Adding liquidty without changing current price. To use the full amount of tokens we would need to add sqrt(10)
    //But we'll add an approximation
    manager.deposit(3.15 ether);
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
}
