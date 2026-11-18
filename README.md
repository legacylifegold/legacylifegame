# Legacy Life Game (LLGAME)

Legacy Life Game is a planned BEP-20 token and locked staking ecosystem on BNB Smart Chain, providing an on-chain finance backend for an educational economic game.

See the [white paper](docs/WHITEPAPER.md) for the ecosystem design.

## Build and test

Requires [Foundry](https://book.getfoundry.sh/). The repository has no git submodules: OpenZeppelin Contracts and forge-std are pinned in `foundry.toml` and installed by Soldeer into `dependencies/`, each archive checked against `soldeer.lock`.

```sh
forge soldeer install
forge test
```

The tests deploy the PancakeSwap v2 core (vendored in `test/pancake-core`, Solidity 0.5.16) alongside the contracts.
