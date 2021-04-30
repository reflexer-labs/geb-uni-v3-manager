pragma solidity ^0.6.7;

import "../../lib/ds-test/src/test.sol";
import "../GebUniswapv3LiquidityManager.sol";
import "../uni/UniswapV3Factory.sol";
import "../uni/UniswapV3Pool.sol";
import "../erc20/ERC20.sol";

// --- Token Contracts ---
contract TestRAI is ERC20 {
    constructor(string memory _symbol) public ERC20(_symbol, _symbol) {
        _mint(msg.sender, 5000000 ether);
    }
}

contract TestWETH is ERC20 {
    constructor(string memory _symbol) public ERC20(_symbol, _symbol) {
        _mint(msg.sender, 1000000 ether);
    }
}

abstract contract Hevm {
    function warp(uint256) public virtual;

    function roll(uint256) public virtual;
}

contract PoolUser {
    GebUniswapV3LiquidityManager manager;
    TestRAI rai;
    TestWETH weth;
    UniswapV3Pool pool;

    constructor(
        GebUniswapV3LiquidityManager man,
        UniswapV3Pool _pool,
        TestRAI _r,
        TestWETH _w
    ) public {
        pool = _pool;
        manager = man;
        rai = _r;
        weth = _w;
    }

    function doTransfer(
        address token,
        address to,
        uint256 amount
    ) public {
        ERC20(token).transfer(to, amount);
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

    function doMintOnPool(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidityAmount
    ) public {
        pool.mint(address(this), lowerTick, upperTick, liquidityAmount, bytes(""));
    }

    function doBurnOnPool(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidityAmount
    ) public {
        pool.burn(lowerTick, upperTick, liquidityAmount);
    }

    function doCollectFromPool(
        int24 lowerTick,
        int24 upperTick,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public {
        pool.collect(recipient, lowerTick, upperTick, amount0Requested, amount1Requested);
    }

    function doSwap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes memory data
    ) public {
        pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (address(pool.token0()) == address(rai)) {
            if (amount0Delta > 0) rai.transfer(msg.sender, uint256(amount0Delta));
            if (amount1Delta > 0) weth.transfer(msg.sender, uint256(amount1Delta));
        } else {
            if (amount1Delta > 0) rai.transfer(msg.sender, uint256(amount1Delta));
            if (amount0Delta > 0) weth.transfer(msg.sender, uint256(amount0Delta));
        }
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        if (address(pool.token0()) == address(rai)) {
            rai.transfer(msg.sender, amount0Owed);
            weth.transfer(msg.sender, amount1Owed);
        } else {
            rai.transfer(msg.sender, amount1Owed);
            weth.transfer(msg.sender, amount0Owed);
        }
    }

    function doArbitrary(address target, bytes calldata data) external {
        (bool succ, ) = target.call(data);
        require(succ, "call failed");
    }
}
