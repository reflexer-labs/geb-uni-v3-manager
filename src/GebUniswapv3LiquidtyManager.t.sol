pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "./GebUniswapv3LiquidtyManager.sol";
import "../lib/geb-deploy/src/test/GebDeploy.t.base.sol";
import "./uni/UniswapV3Factory.sol";
import "./uni/UniswapV3Pool.sol";

// --- Token Contracts ---
contract TestRAI is DSToken {
  constructor(string memory symbol) public DSToken(symbol, symbol) {
    decimals = 6;
    mint(1000 ether);
  }
}

contract TestWETH is DSToken {
  constructor(string memory symbol) public DSToken(symbol, symbol) {
    decimals = 6;
    mint(100 ether);
  }
}

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

  function deployV3Pool(
    address _token0,
    address _token1,
    uint256 fee
  ) internal returns (address _pool) {
    UniswapV3Factory fac = new UniswapV3Factory();
    _pool = fac.createPool(token0, token1, uint24(fee));
  }

  function addLiquidity() public {
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

  function setUp() public override {
    // Depoly GEB
    super.setUp();
    deployIndex(bytes32("ENGLISH"));
    // Deploy each token
    testRai = new TestRAI("RAI");
    testWeth = new TestWETH("WETH");
    (token0, token1) = address(testRai) < address(testWeth) ? (address(testRai), address(testWeth)) : (address(testWeth), address(testRai));

    // Deploy Pool
    pool = UniswapV3Pool(deployV3Pool(token0, token1, 500));
    emit log_named_address("pol", address(pool));

    //We have to give an inital price to the wethUsd // This meas 10:1(10 RAI for 1 ETH).
    //This number is the sqrt of the price = sqrt(0.1) multiplied by 2 ** 96
    pool.initialize(uint160(25054144837504793118641380156));
    manager = new GebUniswapV3LiquidityManager("Geb-Uniswap-Manager", "GUM", address(testRai), threshold, delay, address(pool), oracleRelayer);
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
    // assertTrue(false);
  }

  function test_rebalancing_pool() public {
    addLiquidity(); //Starting with a bit of liquidity
    uint256 redemptionPrice = oracleRelayer.redemptionPrice();
    (OracleLike oracle, , ) = oracleRelayer.collateralTypes(bytes32("ETH"));
    (uint256 ethUsd, bool valid) = oracle.getResultWithValidity();
    assertTrue(valid);

    uint160 sqrtRedPriceX96 = uint160(sqrt((ethUsd * 2**96) / redemptionPrice));
    int24 targetTick = TickMath.getTickAtSqrtRatio(sqrtRedPriceX96);
    int24 spacedTick = targetTick - (targetTick % 10);
    // if (targetTick > 0) {
    //   emit log_named_uint("targetTickP", getAbsInt24(spacedTick));
    // } else {
    //   emit log_named_uint("targetTickN", getAbsInt24(spacedTick));
    // }

    (, int24 currentTick, , , , , ) = pool.slot0();
    // emit log_named_uint("bal0", sqrt((ethUsd * 2**96) / redemptionPrice));
    // if (currentTick > 0) {
    //   emit log_named_uint("tickP", uint256(currentTick));
    // } else {
    //   emit log_named_uint("tickN", uint256(currentTick * int24(-1)));
    // }

    (int24 newLower, int24 newUpper) = manager.getNextTicks();

    manager.rebalance();
    bytes32 positionID = keccak256(abi.encodePacked(address(manager), newLower, newUpper));
    (uint128 _liquidity, , , , ) = pool.positions(positionID);
    // emit log_named_uint("endLiq", _liquidity);
    // emit log_named_uint("endLiq", 3.15 ether);

    uint256 bal0 = testRai.balanceOf(address(pool));
    uint256 bal1 = testWeth.balanceOf(address(pool));
    uint256 bal2 = testRai.balanceOf(address(manager));
    uint256 bal3 = testWeth.balanceOf(address(manager));
    // emit log_named_uint("bal0", bal0);
    // emit log_named_uint("bal1", bal1);
    // emit log_named_uint("bal2", bal2);
    // emit log_named_uint("bal3", bal3);
    assert(bal2 + bal0 == 10 ether);
    assert(bal3 + bal1 == 1 ether);

    (uint160 currPrice, , , , , , ) = pool.slot0();
    uint256 liq = LiquidityAmounts.getLiquidityForAmounts(currPrice, TickMath.getSqrtRatioAtTick(newLower), TickMath.getSqrtRatioAtTick(newUpper), bal0, bal1);
    // emit log_named_uint("liq", liq / _liquidity);
    //A bit of rounding error
    assertTrue(_liquidity / liq == 0);
  }

  function test_burining_liquidity() public {
    uint256 wethAmount = 1 ether;
    uint256 raiAmount = 10 ether;
    addLiquidity(); //Starting with a bit of liquidity
    uint256 balanceBefore = testRai.balanceOf(address(this));

    uint256 liq = manager.balanceOf(address(this));
    //withdraw half of liquidity
    manager.withdraw(liq / 2);
    assertTrue(manager.balanceOf(address(this)) == liq / 2);

    uint256 balanceAfter = testRai.balanceOf(address(this));
    emit log_named_uint("bal", balanceAfter - balanceBefore);
    emit log_named_uint("bal3", raiAmount / 2);
    assertTrue((balanceAfter - balanceBefore) / raiAmount / 2 == 0);
  }

  function getAbsInt24(int24 val) internal returns (uint256 abs) {
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
