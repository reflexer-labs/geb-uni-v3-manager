pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebUniswapv3LiquidtyManager.sol";

contract GebUniswapv3LiquidtyManagerTest is DSTest {
  GebUniswapv3LiquidtyManager manager;

  function setUp(
    bytes32 symbol_,
    uint256 _threshold,
    uint256 _delay,
    address token0_,
    address token1_,
    address pool_
  ) public {
    manager = new GebUniswapv3LiquidtyManager(symbol_, _threshold, _delay, token0_, token1_, pool_);
  }

  function testFail_basic_sanity() public {
    assertTrue(false);
  }

  function test_basic_sanity() public {
    assertTrue(true);
  }
}
