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
        f.user_Swap(1, 1);
        f.echidna_select_ticks_correctly();
        // emit log_named_uint("amount0", amount0);

        assertTrue(false);
    }
}
