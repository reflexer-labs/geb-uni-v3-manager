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

    event AD(int24 la);

    function test_fff() public {
        // f.init(12);
        f.test_swap_exactOut_oneForZero(38173249315594130217491356682780247106);
        GebUniswapV3LiquidityManager manager = f.manager();
        uint256 t = manager.totalSupply();
        emit log_named_uint("t", t);
        // emit log_named_uint("amount0", amount0);

        assertTrue(false);
    }
}
