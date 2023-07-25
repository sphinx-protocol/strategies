# Strategies

> :warning: The strategies in this repository are currently under development and have not been tested or audited. Use at your own risk.

Monorepo for automated market making strategies on [Sphinx](https://github.com/sphinx-protocol).

Sphinx is an AMM protocol on Starknet that ships with an integrated smart contract market maker to offer deep liquidity and yield for LPs.

This repository gathers a reusable library of automated market making strategies, allowing projects to launch and bootstrap liquidity for their tokens in minutes rather than months.

## Strategies

| Package                                  | Description                                                                                                                                                                                                                                                                                                |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [balanced](./strategies/balanced)        | Sets a symmetrical bid and ask price in order to maintain an inventory of base and quote assets at some target ratio, ideal for addressing impermanent loss and managing inventory risk. Based on the influential [Avellaneda & Stoikov paper](https://math.nyu.edu/~avellane/HighFrequencyTrading.pdf). |
| [replicating](./strategies/replicating/) | Replicates the bid and ask spread from a external exchange using an oracle price feed. Ideal for assets that already trade on liquid markets.                                                                                                                                                              |
| [stable](./strategies/stable/)           | Provides liquidity at discrete bid and ask prices, or a range of prices tightly banded around the peg. Ideal for stablecoin pairs.                                                                                                                                                                         |

## Setup

To set up a development environment, please follow these steps:

1. Install [Cairo](https://book.cairo-lang.org/ch01-01-installation.html).

2. Instal [Scarb](https://docs.swmansion.com/scarb/download).

3. Clone the repo.

   ```sh
   git clone https://github.com/sphinx-dex/strategies

   cd balanced

   scarb test
   ```

## Support

If you encounter issues or have questions, you can submit an issue on GitHub. You can also join our Discord for discussion and help.

## Contributing

We welcome contributions of all kinds from anyone. See our [Contribution Guide](./CONTRIBUTING.md) for more information on how to get involved.
