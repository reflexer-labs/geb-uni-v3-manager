pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "../GebUniswapv3LiquidityManager.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";
import "../erc20/ERC20.sol";

// --- Token Contracts ---
contract TestRAI is ERC20 {
    constructor(string memory symbol) public ERC20(symbol, symbol) {
        _mint(msg.sender, 5000000 ether);
    }
}

contract TestWETH is ERC20 {
    constructor(string memory symbol) public ERC20(symbol, symbol) {
        _mint(msg.sender, 1000000 ether);
    }
}

abstract contract Hevm {
    function warp(uint256) public virtual;

    function roll(uint256) public virtual;
}

contract PoolUser {
    GebUniswapV3LiquidityManager manager;

    constructor(GebUniswapV3LiquidityManager man) public {
        manager = man;
    }

    function doDeposit(uint128 liquidityAmount) public {
        manager.deposit(liquidityAmount, address(this));
    }

    function doWithdraw(uint128 liquidityAmount) public returns (uint256 amount0, uint256 amount1) {
        uint128 max_uint128 = uint128(0 - 1);
        (amount0, amount1) = manager.withdraw(liquidityAmount, address(this), max_uint128, max_uint128);
    }

    function doApprove(
        address token,
        address who,
        uint256 amount
    ) public {
        IERC20(token).approve(who, amount);
    }
}
