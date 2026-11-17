# LLGAME network branches

## Branches

The deployment contract names the PancakeSwap v2 factory and the WBNB of its chain as constants, so a build belongs to one chain. Each chain has a branch of the repository, and a deployment is built from the branch of its chain; no constructor argument, setter or build flag chooses the chain.

| Branch | Chain | Id | Use |
|---|---|---|---|
| `main` | BSC mainnet | 56 | Production, a mainnet fork, and a local chain carrying copies of the factory and WBNB at the mainnet addresses |
| `bsc_testnet` | BSC testnet | 97 | Public rehearsal, and a testnet fork |

`bsc_testnet` is `main` with the overrides below and nothing else. Every change is made on `main` and merged into `bsc_testnet`; `bsc_testnet` is never merged into `main`.

## Overrides

| Contract | Constant | `main` | `bsc_testnet` |
|---|---|---|---|
| `LLGAMEDeployment` | `FACTORY` | `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73` | `0x6725F303b657a9451d8BA641348b6761A6CC7a17` |
| `LLGAMEDeployment` | `WBNB` | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` | `0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd` |
| `LLGAME` | none | | |
| `LLGAMEStaking` | none | | |

The token and the staking contract are the same source on both branches: the term, the rates and the referral constants are not shortened or scaled for the testnet, and a testnet stake matures after 1080 days as a production one does. The staking contract reaches the chain only through the pair the deployment contract hands it.

`test/LLGAME.t.sol` follows the override with its `BSC_FACTORY` and `BSC_WBNB` constants, the addresses its local factory and WBNB are placed at; `test_networkBinding` holds the deployment contract to them.

The testnet addresses are those the PancakeSwap v2 testnet router `0xD99D1c33F9fC3444f8101754aBC46c52416550D1` [3] returns on chain 97 from `factory()` and `WETH()`; that factory's `INIT_CODE_PAIR_HASH()` is `0xd0d4c4cd0848c93cb4fd1f498d7013ee6bfb25783ea21593d5834f5d250ece66`.

On BSC testnet the two mainnet addresses hold code as well, which is not the PancakeSwap testnet deployment (what it is: NOT VERIFIED). A `main` build published there therefore meets code, not an empty address: its publication runs the launch against that code and fails or completes as that code answers (which: NOT VERIFIED). The published contract is read back before any funding (Checks).

`AUTHORS`, `AIRDROP` and `POOL_BNB_SUPPLY` are constructor arguments and no matter of the branch. A testnet publication may name a `POOL_BNB_SUPPLY` far below the production one, which moves the launch price with it.

## Checks

```sh
git diff --stat main bsc_testnet          # contracts/LLGAMEDeployment.sol and test/LLGAME.t.sol only
git diff main bsc_testnet -- contracts    # the two constants and their comment line
forge test --match-test test_networkBinding
```

A published deployment contract tells its branch by its public constants, which must be the row of its chain in the table above:

```sh
cast call <deployment> 'FACTORY()(address)' --rpc-url <endpoint>
cast call <deployment> 'WBNB()(address)' --rpc-url <endpoint>
```

A contract published from the wrong branch is abandoned unfunded, or aborted by `AUTHORS`: its publication created a token, a staking contract and a pair of its own, which bind nothing else, and before its first funding round it holds no BNB.

## Testing at testnet

```sh
git status --short                        # nothing uncommitted under contracts/ and test/
git switch bsc_testnet
git merge main                            # take what main gained since the last rehearsal
forge test
cast chain-id --rpc-url https://bsc-testnet-dataseed.bnbchain.org      # 97
forge create contracts/LLGAMEDeployment.sol:LLGAMEDeployment \
    --rpc-url https://bsc-testnet-dataseed.bnbchain.org --account <keystore account> \
    --broadcast --verify --verifier sourcify \
    --constructor-args <AUTHORS> <AIRDROP> <POOL_BNB_SUPPLY in wei>
git switch main                           # the working tree is left on the production branch
```

The merge conflicts only where `main` changed one of the overridden lines; the testnet value is kept. The read-back of Checks follows the publication, then the first funding round.

## Deploying at production

```sh
git switch main
git status --short                        # empty: the build is exactly what is committed
git fetch origin && git diff --stat main origin/main                   # empty: the build is the published source
git grep -n -e 'FACTORY =' -e 'WBNB =' contracts/LLGAMEDeployment.sol  # the main column of Overrides
forge clean && forge test
cast chain-id --rpc-url https://bsc-dataseed.bnbchain.org              # 56
forge create contracts/LLGAMEDeployment.sol:LLGAMEDeployment \
    --rpc-url https://bsc-dataseed.bnbchain.org --account <keystore account> \
    --broadcast --verify --verifier sourcify \
    --constructor-args <AUTHORS> <AIRDROP> <POOL_BNB_SUPPLY in wei>
```

The read-back of Checks follows the publication, which is the activation transaction, and precedes the first funding round. A production deployment is never built while `bsc_testnet` is checked out, and never from a tree with uncommitted changes.
