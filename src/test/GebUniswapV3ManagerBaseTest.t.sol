pragma solidity 0.6.7;

import "../../lib/ds-test/src/test.sol";
import "../GebUniswapV3ManagerBase.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";
import "./TestHelpers.sol";
import "./OracleLikeMock.sol";

contract GebUniswapV3ManagerBaseTest is DSTest {

    Hevm hevm;
    GebUniswapV3ManagerBase manager;
    UniswapV3Pool pool;
    TestRAI testRai;
    TestWETH testWeth;
    OracleLikeMock oracle;

    address token0;
    address token1;

    uint160 initialPoolPrice;

    PoolUser u1;
    PoolUser u2;
    PoolUser u3;
    PoolUser u4;

    PoolUser[4] public users;
    PoolViewer pv;

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
}