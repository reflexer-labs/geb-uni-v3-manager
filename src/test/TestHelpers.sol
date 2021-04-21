pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "../GebUniswapv3LiquidityManager.sol";
import "../../lib/geb-deploy/src/test/GebDeploy.t.base.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";

// --- Token Contracts ---
contract TestRAI is DSToken {
    constructor(string memory symbol) public DSToken(symbol, symbol) {
        decimals = 6;
        mint(100000 ether);
    }
}

contract TestWETH is DSToken {
    constructor(string memory symbol) public DSToken(symbol, symbol) {
        decimals = 6;
        mint(10000 ether);
    }
}

contract PoolUser {
    GebUniswapV3LiquidityManager manager;

    constructor(GebUniswapV3LiquidityManager man) public {
        manager = man;
    }

    function doDeposit(uint128 liquidityAmount) public {
        manager.deposit(liquidityAmount);
    }

    function doWithdraw(uint128 liquidityAmount)
        public
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityBurned
        )
    {
        return manager.withdraw(liquidityAmount);
    }

    function doApprove(
        address token,
        address who,
        uint256 amount
    ) public {
        DSToken(token).approve(who, amount);
    }
}
