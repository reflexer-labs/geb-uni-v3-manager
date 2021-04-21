# Uniswap V3 Liquidity Manager

A contract that manage a uniswap v3 position and distribute liquidity erc20 for depositors.

## Use Cases

[Uniswap V3](https://uniswap.org/blog/uniswap-v3/) was recently launched offering a new set of tools for liquidity providers, specially with concentrated liquidity, a mechanism that allow to deposit only into a specific price range maximizing the capital efficiency. As a drawback it no longer provides erc20 liquidity tokens, making it impossible to offer incentives for liquidity mining.

This contract solves it by making a shared position that can be be autonomously rebalanced according to a specific set of rules and in return distributes a v2-like liquidity token for participants.

In this specific use case, it's intended to concentrate liquidity around a [Reflexer Index](https://medium.com/reflexer-labs/stability-without-pegs-8c6a1cbc7fbd) redemption price, specifically for the RAI/WETH pool.

## Overview

The contract `GebUniswapV3LiquidityManager` is the entity that maintain a position, the uniswap v3 term for liquidity, into the desired pool. At each deposit, it fetches the current redemption price and move all of it's liquidity to this price target + or - a defined `threshold`. If some time passes without any deposits, it's possible to force a `rebalance` by calling a specific function.

For example, if threshold is set at 50% and the current redemption price is `1 RAI = 0.0012 ETH` the contract will deposit its liquidity between ~`0.006` and ~`0.0018`. Those numbers are approximations because v3 doesn't handle prices directly, but rather [ticks](https://docs.uniswap.org/concepts/concentrated-liquidity#ticks)

This contract is still under active development and further tests, and security audits, are needed to be considered ready for production use.

## Future Improvements

#### Multiple tranches

Currently the contract only holds a single position in a v3 pool, but an improvement possible feature is to manage multiple positions, aiming to increase fees rewards at the same time minimizing risks.

Imagine this scenario with 3 tranches:

-   Tranche 1: 10% of treasury, with a threshold of 5%
-   Tranche 2: 40% of treasury, with a threshold of 15%
-   Tranche 3: 50% of treasury, with a threshold of 35%;

The specifics number can be optimized for each pool, according to it's volatility or other factores.

A shortcoming is that both `rebalance()` and `deposit()` gas costs increase linearly with each new added tranche, therefore too much granularity might mean that the contract becomes too expensive to be used.

#### Multi Pool

Unlike v2, v3 can have multiple pools for the same pair, with different fee structures. Currently, the liquidity manager can only operate in a single pool, meaning it'll have to choose a single fee tier to deposit it's liquidity into. A future implementation might allow for having positions in multiple pools for the same pair.

## Learn More

To learn more about Reflexer Indexes, check the [full documentation](https://docs.reflexer.finance/), our [blog posts](https://medium.com/reflexer-labs) and our [stats page](https://stats.reflexer.finance/)

Checkout Uniswap V3 [repo](https://github.com/Uniswap/uniswap-v3-core), [whitepaper](https://uniswap.org/whitepaper-v3.pdf) and [docs](https://docs.uniswap.org/)

The code was also inspired by [Uniswap Liquidity Dao](https://github.com/dmihal/uniswap-liquidity-dao)
