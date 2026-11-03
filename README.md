# Legacy Life Game (LLGAME)

Legacy Life Game is a planned BEP-20 token and locked staking ecosystem on BNB Smart Chain, providing an on-chain finance backend for an educational economic game.

See the [white paper](docs/WHITEPAPER.md) for the ecosystem design.

## Build and test

Requires [Foundry](https://book.getfoundry.sh/).

```sh
git submodule update --init --recursive
forge test
```

The tests deploy the PancakeSwap v2 core (`lib/pancake-swap-core`, Solidity 0.5.16) alongside the contracts.
