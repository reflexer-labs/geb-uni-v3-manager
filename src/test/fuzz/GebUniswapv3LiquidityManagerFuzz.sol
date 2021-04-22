pragma solidity ^0.6.7;

import "../../../lib/geb/src/OracleRelayer.sol";
import { ERC20 } from "../.././erc20/ERC20.sol";
import { IUniswapV3Pool } from "../.././uni/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "../.././uni/interfaces/callback/IUniswapV3MintCallback.sol";
import { TransferHelper } from "../.././uni/libraries/TransferHelper.sol";
import { LiquidityAmounts } from "../.././uni/libraries/LiquidityAmounts.sol";
import { TickMath } from "../.././uni/libraries/TickMath.sol";
import ".././TestHelpers.sol";
import ".././GebUniswapv3LiquidityManager.t.sol";

/**
 * Interface contract aimed at fuzzing the Uniswap Liquidity Manager
 * Very similar to GebUniswap v3 tester
 */
contract Fuzzer is GebUniswapv3LiquidtyManagerTest {
    constructor() public {
        //That set's the manager in a base state
        setUp();
    }

    //Onlu doing deposits from this address, and no swaps hapenning
    function depositForRecipient(address recipient, uint128 liquidityAmount) public {
        manager.deposit(liquidityAmount, recipient);
    }

    function withdrawForRecipient(address recipient, uint128 liquidityAmount) public {
        uint128 max_uint128 = uint128(0 - 1);
        manager.withdraw(liquidityAmount, recipient, max_uint128, max_uint128);
    }

     function echidna_manager_supply_equal_liquidity() public returns (bool) {
        (uint128 _liquidity, , , , ) = pool.positions(manager.position.id);
        return (manager.totalSupply() == _liquidity);
    }
}
}
