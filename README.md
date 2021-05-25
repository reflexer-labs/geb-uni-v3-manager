# Uniswap V3 Liquidity Manager

A contract that manages Uniswap V3 positions for a pool containing a GEB system coin and wraps these positions into an ERC20 on behalf of the LPs.

## Use Cases

[Uniswap V3](https://uniswap.org/blog/uniswap-v3/) was recently launched, offering a new set of tools for liquidity providers. These tools are targeted at concentrated liquidity, a mechanism that allow LPs to deposit capital into a specific price range, thus maximizing their capital efficiency. A drawback of this mechanism is that it no longer allows fungibility along the entire price curve, making it impossible to represent all LP positions with a single token.

This contract tries to solve the fungibility problem by wrapping LP positions into a single ERC20. In this specific use case, it's intended to concentrate liquidity around a [non-pegged stable asset](https://medium.com/reflexer-labs/stability-without-pegs-8c6a1cbc7fbd)'s redemption price (aka moving peg).

## Overview of the Single Tranche Manager

The contract `GebUniswapV3LiquidityManager` is the contract that manages positions in a single tranche. For each deposit, it fetches the current redemption price and moves all deposited liquidity into a narrow band around it (what's defined as `threshold`). If there are no deposits for a long period of time, it's possible to force a `rebalance` separately.

As an example, if the threshold is set at 50% and the current redemption price is `1 RAI = 0.0012 ETH`, the contract will deposit its liquidity between ~`0.006` and ~`0.0018`.

This contract is still under active development and needs further testing as well as security audits.

## Overview of the Two Tranche Manager

The contract `GebUniswapV3TwoTrancheManager` is the contract that manages positions in two tranches.

Imagine the following scenario with 2 tranches:

-   Tranche 1: 10% of treasury, with a threshold of 5%
-   Tranche 2: 40% of treasury, with a threshold of 95%

These numbers can be optimized for each pool, according to volatility or other factors.

A shortcoming of this design is that both `rebalance()` and `deposit()` gas costs increase linearly with the second tranche.

## Future Improvements

Unlike Uniswap V2, Uniswap V3 can have multiple pools for the same pair, each one with a different fee structure. Currently, the liquidity manager can only operate in a single pool, meaning it'll have to choose a single fee tier. A future implementation might allow for multiple positions in multiple pools for the same pair.

## Learn More

To learn more about Reflexer, check the [official documentation](https://docs.reflexer.finance/), our [blog posts](https://medium.com/reflexer-labs) and our [stats page](https://stats.reflexer.finance/).

Moreover, we invite you to check the Uniswap V3 [repo](https://github.com/Uniswap/uniswap-v3-core), [whitepaper](https://uniswap.org/whitepaper-v3.pdf) and [docs](https://docs.uniswap.org/).

The code was inspired by [Uniswap Liquidity Dao](https://github.com/dmihal/uniswap-liquidity-dao).
