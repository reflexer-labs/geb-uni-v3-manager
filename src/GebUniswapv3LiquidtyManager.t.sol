pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebUniswapv3LiquidtyManager.sol";

contract GebUniswapv3LiquidtyManagerTest is DSTest {
    GebUniswapv3LiquidtyManager manager;

    function setUp() public {
        manager = new GebUniswapv3LiquidtyManager();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
