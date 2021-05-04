pragma solidity ^0.6.7;

import "../../lib/ds-test/src/test.sol";
import "../GebUniswapv3LiquidityManager.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";
import "./TestHelpers.sol";
import "./fuzz/GebUniswapv3LiquidityManagerFuzz.sol";
import "./OracleLikeMock.sol";

contract GebTest is DSTest {
    Fuzzer f;

    function setUp() public {
        f = new Fuzzer();
    }

    function test_fff() public {
        // f.init();
        f.user_Deposit(2, 100008);
        f.user_WithDraw(2, 99999);
        f.user_Mint(3, -887270, 887270, 10000);
        f.user_Burn(3, -887270, 887270, 5000);
        assertTrue(false);
    }
}
