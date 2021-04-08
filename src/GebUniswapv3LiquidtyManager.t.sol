pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebUniswapv3LiquidtyManager.sol";

import "../lib/geb-deploy/src/test/GebDeploy.t.base.sol";

contract GebUniswapv3LiquidtyManagerTest is GebDeployTestBase {
  GebUniswapv3LiquidtyManager manager;

  function setUp(
    string memory name_,
    string memory symbol_,
    uint256 _threshold,
    uint256 _delay,
    address token0_,
    address token1_,
    address pool_
  ) public {
    super.setUp();
    deployIndex(bytes32("ENGLISH"));
    manager = new GebUniswapv3LiquidtyManager(name_, symbol_, _threshold, _delay, token0_, token1_, pool_);
  }

  function testFail_basic_sanity() public {
    assertTrue(false);
  }

  function test_basic_sanity() public {
    assertTrue(true);
  }

  function test_basic_price_reading() public {
    emit log_named_uint("address", 111);
    assert(true);
  }
}
