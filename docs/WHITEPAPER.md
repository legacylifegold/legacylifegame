# Legacy Life Game (LLGAME) white paper

## Introduction

### Game

Legacy Life is an educational economic game whose player creates avatars, buys capital goods, attracts partners, develops a team, runs a simulated business and distributes its proceeds.

Gameplay tests the player inside simulated economic and social relations: capital is committed, agreements create links, team growth changes payouts and every reward comes from a visible budget.

### Token backend

Legacy Life game token is the game's independent finance backend: a BEP-20 token and locked staking contract on BNB Smart Chain. The game server keeps story, quests, characters and interface; the contracts keep balances, stakes, referral links, payout rules, and the operator cannot rewrite them or move a player's money.

The token emulates finance rather than offering it: payments, fixed-term deposits, referral network to conquer the market, all game-scaled but real on chain.

## 1. Ecosystem

Legacy Life game (LLGAME) is the BEP-20 token on BNB Smart Chain (BSC). Its whole supply is minted once, when the token is created inside the activation transaction:

- 3.4 × 10^29 LLGAME, that is 340,000,000,000,000,000,000,000,000,000 LLGAME, sized in section 9.4

The supply is allocated as follows:

- `AUTHORS_SUPPLY = 500,000` LLGAME - creators' stake, locked for 1080 days: an ordinary stake opened for the fixed `AUTHORS` address inside the activation transaction;
- 10,000 LLGAME paired with BNB in a launch liquidity pool whose liquidity provider (LP) tokens are sent to `DEAD` when funding closes;
- the remaining supply is initially held by the staking contract. After the creators' stake is opened, the unallocated part becomes the reserve that funds subsequent staking rewards and referral allocations.

Holders receive value through:

- staking for 1080 days, with rewards accruing over time and claimable as they accrue;
- the referral program: a budget of each stake, paid inside the stake call to the staker's uplines;
- gamified airdrops: any non-zero unpaid remainder of that budget is recorded immediately as a stake for the special `AIRDROP` address, making the accumulated airdrop budget transparent and predictable on chain;

The operational ecosystem consists of two locked contracts and a DEX pair, launched and funded by a separate deployment contract. Two separately controlled addresses participate in its economics: `AUTHORS`, the ordinary beneficiary of the creators' stake, and `AIRDROP`, the special address for accumulated referral remainders.:

| Part | Role | Administration |
|---|---|---|
| Token (`LLGAME`) | OpenZeppelin v5 `ERC20`, `ERC20Burnable`, `ERC20Permit`, 9 decimals, no access control module, no transfer hook and no reference to another contract of the ecosystem | None: locked at launch |
| Pool | PancakeSwap v2 LLGAME/WBNB pair, launch LP position sent to `DEAD` at close | None: the pair is DEX code, its protocol `feeTo` share excepted |
| Staking | Holds the reserve, the ecosystem-account set and the referral forest; binds an account to the payer of the first stake opened for it or to the staker delegating to it; takes stakes paid by their caller for a beneficiary, splits a part of a stake to a delegate at its staker's request, allocates rewards, pays referral shares to eligible uplines, records any non-zero unpaid referral remainder as an `AIRDROP` stake inside the stake call | None: locked at launch |
| Deployment contract | Launcher published without attached BNB and with immutable parameters; creates the ecosystem in its own publication, takes the funding rounds into the pool and closes when funding reaches at least `POOL_BNB_SUPPLY` | No owner, setter or withdrawal function and no right of its publisher; `AUTHORS` may abort before close |
| `AUTHORS` address | Fixed beneficiary of the creators' stake and the one account able to abort the funding; to the token and the staking contract an ordinary account with no exclusion or privilege | Its key or multisig policy controls that account and the deployment contract's abort during funding; it has no right over a locked contract |
| `AIRDROP` address | Special address whose stakes accumulate unpaid referral-budget remainders for later airdrops; cannot participate in the referral program as referrer or referred account | Its key or multisig policy claims and withdraws under the common staking rules |

### 1.1 Terms

| Term | Meaning |
|---|---|
| Locked contract | A contract deployed final: no owner, admin role, settable parameter, pause, upgrade or administrator withdrawal; every table and threshold is a constant or immutable. Staking principal and rewards remain withdrawable only through the fixed user-facing rules |
| Ecosystem account | A fixed system address excluded from referral binding in either direction: the launch pair, staking contract, deployment contract, dead address and `AIRDROP` |
| Staker | The beneficiary of a stake: the account whose active stake it is, whose reward ledger it feeds, to which the principal returns and whose uplines the stake's referral walk pays |
| Payer | The caller of `stake`, whose LLGAME funds the stake; the staker itself in the common case |
| Stake reserve | LLGAME in the staking contract not allocated to any stake |
| Referral budget | 20% of each ordinary stake's amount, taken from the stake reserve at stake time and paid recursively to eligible uplines by the halving share formula; any non-zero unpaid remainder is recorded as an `AIRDROP` stake |
| Operator | The party running the game; it cannot change the locked contracts or their payout rules |
| Deployment contract | A launcher published without attached BNB and with immutable launch parameters; its publication creates the ecosystem, and the funding round bringing the total to at least `POOL_BNB_SUPPLY` closes the funding |
| Activation transaction | The publication of the deployment contract: its constructor creates the token, staking contract and pair and opens the creators' stake, with no BNB attached and the pool left empty |
| Funding round | A permissionless BNB transfer to the deployment contract, entering the pool with LLGAME in proportion to it |
| Funding | From the activation transaction until close or abort (section 7) |
| `derived` | Marks a statement that follows from the rules stated elsewhere, not a separate rule |

## 2. Invariants

Every part of the ecosystem is bound by the following; the requirements of sections 3 to 7 are consequences of these invariants.

1. **Locked at launch.** The token and the staking contract are locked contracts. No proxy, upgradeable part or contract-administration signer exists in the token or staking contracts; the deployment contract's only privileged call is `AUTHORS`' abort during funding.
2. **No mint after creation.** The token's constructor mints the whole supply and no function can mint again. Every staking reward and referral allocation is funded from the staking contract's pre-minted holdings.
3. **No administration of value.** No key can move LLGAME out of a locked contract except through its fixed rules: staking principal withdrawal, reward claim, and referral payout. From close, the launch LP position is irretrievably held at `DEAD`; during funding only an abort removes its liquidity, refunding funders; PancakeSwap may separately mint protocol-fee LP shares to its configured `feeTo` address under the DEX's own rules, as described in section 4. `AIRDROP` claims and withdraws under the common rules and has no administrative right over any contract.
4. **Fixed conditions.** The staking term and rate, the referral budget and referral formula, the fixed `AUTHORS` beneficiary, the `AIRDROP` address and the fixed ecosystem-account exclusion set are immutable or constants of the contracts that use them.
5. **Solvent by construction.** Nothing is owed beyond what is allocated: a stake reverts when the stake reserve cannot cover its reward, its referral budget and the reward of its `AIRDROP` stake; the referral walk pays eligible shares within the stake's referral budget in the same call, and any unpaid part is recorded as an `AIRDROP` stake. The sum of the staking contract's accounted ledgers—principal still held, allocated rewards not yet claimed and unallocated reserve—never exceeds its LLGAME balance. A direct token transfer to the staking contract outside `stake` is an unsolicited donation: it is not credited to the reserve or any stake ledger and has no withdrawal path.
6. **Deterministic binding and payouts.** The staking contract creates a referral binding only when a stake is first opened for an account, or a stake part first delegated to it, and the payer (or the delegating staker) has `activeStakeOf > 0` and neither endpoint is excluded; a plain token transfer binds nothing. Referral shares are paid to uplines whose liquid balance and `activeStakeOf` both meet the level's fixed threshold, down to the level at which the walk ends (section 6). No off-chain party can alter the binding, the shares or the thresholds; the staker alone, through the gas price of its stake transaction up to its fixed cap and the pool's price within the guard of its reference price, can end the walk of its own stake earlier and raise the gas charge that the walk takes from the shares and refunds to the payer, never extend the walk or redirect a share beyond that charge. Distribution of matured funds withdrawn by `AIRDROP` is an off-chain activity and is not controlled by the contracts.
7. **No transfer tax.** The token overrides no transfer logic: an ordinary transfer deducts no fee, redirects no part and calls no other contract.

## 3. Token

- Name Legacy Life Game, symbol LLGAME, 9 decimals, total supply `TOTAL_SUPPLY = 3.4 × 10^29` LLGAME, that is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38`. Every stored token balance and token-denominated stake or reserve ledger is bounded by total supply and fits a `uint128`; intermediate calculations and referral thresholds use `uint256` (section 9.4).
- The constructor mints the whole `TOTAL_SUPPLY` to its deployer, the deployment contract. The token emits no further mint ever. All LLGAME amounts passed to token and staking functions are expressed in base units; `POOL_BNB_SUPPLY` is expressed in wei. The prose expresses token balances in LLGAME (9 decimals).
- The token keeps no referral state and holds no reference to the staking contract: it is the plain composition of the three OpenZeppelin contracts.
- `ERC20Burnable` lets any holder burn its own tokens; nothing in the ecosystem requires a burn.
- `ERC20Permit` lets a holder approve the staking contract by signature, so a stake is one transaction.
- The token inherits no access control module: there is no owner, no role and no function that would need one.

### 3.1 Interface

The token adds nothing to the OpenZeppelin `ERC20`, `ERC20Burnable` and `ERC20Permit` interfaces.

## 4. Pool

The launch pool is the canonical PancakeSwap v2 LLGAME/WBNB pair. At close it holds:

- 10,000 LLGAME and at least `POOL_BNB_SUPPLY` wei of BNB as WBNB. `POOL_BNB_SUPPLY` is 16.9 BNB, `16_900_000_000_000_000_000` wei, fixed before publication to target approximately $10,000 at a reference BNB/USDT quote of 591.77 (16.9 BNB ≈ $10,001). The actual USD value depends on the BNB/USD rate at close.
- The 10,000 LLGAME are one part in 3.4 × 10^25 of the total supply. The pool is the initial DEX source of freely tradable LLGAME; the creators' principal is locked in staking, while reserve distributions occur only through the staking rules. Tokens subsequently circulate through ordinary transfers, staking payouts, referral payouts and any off-chain airdrops funded by matured `AIRDROP` withdrawals.
- The launch LP tokens are held at the dead address, so that position is locked without a locker contract or owner. Swap fees remain in the pair's reserves; the PancakeSwap protocol may separately mint `feeTo` LP shares under its own factory-controlled fee mechanism.

## 5. Staking

A holder stakes an amount `A` for the fixed term of 1080 days, with `stake(amount, beneficiary)`. The caller is the payer: the amount is pulled from its balance. The beneficiary is the staker: the stake belongs to that account. In the common case, the caller names itself, but anyone can open a stake for anyone else. The staking contract allocates at stake time, out of the stake reserve, everything the stake will ever cost; a stake that the reserve cannot cover reverts. Its constructor initializes the unallocated reserve from `TOKEN.balanceOf(address(this))`. Later direct LLGAME transfers to the staking address are not treated as reserve deposits; without an explicit stake call they remain unaccounted surplus and cannot be withdrawn.

Every public `stake` or `stakeWithPermit` call must meet the minimum principal of **0.072 LLGAME** (72,000,000 base units).

This limit targets an average accrued reward of at least one base unit per average BSC block, using the documented 0.45-second average block interval. The minimum applies to public stake calls; the internally created referral-remainder `AIRDROP` stake described in section 5.2 is exempt.

| Allocation at stake time | Amount | Destination |
|---|---|---|
| Reward | 288% of `A`, that is 8% of `A` per 30 days | The staker's reward ledger, released linearly over the term |
| Referral budget | 20% of `A` (section 6) | Allocated from the stake reserve; eligible shares are paid immediately and the remainder becomes an `AIRDROP` stake (section 6) |

The reward accrues linearly from the stake block to the unlock, and the staker claims the accrued part at any time, capped by the allocated reward; the ledger keeps the claimed amount, so a fully claimed stake reads and claims cleanly. The principal is returned to the staker, with the unclaimed reward, at the end of the term, once. There is no early withdrawal and no compounding: a holder that wants to restake takes its payout and stakes again, which triggers a new referral budget. The contract keeps `activeStakeOf[account]`, the sum of the account's stake principals still held by the staking contract, including matured stakes whose principal has not yet been withdrawn. It decides whether an address may become a referrer when a binding is written and enters the upline's payout eligibility (section 6). It is incremented when a stake opens and decremented exactly once when that stake's principal is withdrawn. No separate staker flag or registration state is needed.

### 5.1 Interface

```solidity
// Staking contract: interface sketch
struct StakeInfo {
    address staker;     // the beneficiary: claims the reward and withdraws the principal
    uint128 principal;  // zero once withdrawn
    uint128 reward;     // allocated at stake time
    uint128 claimed;
    uint64  start;      // timestamp of the stake block; the reward accrues from it to start + 1080 days
}

event Staked(uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount);
    // also for an AIRDROP remainder stake: staker AIRDROP, payer the staking contract
event StakeDelegated(uint256 indexed stakeId, uint256 indexed delegatedStakeId, address indexed delegate, address staker, uint256 amount);
event ReferralBound(address indexed account, address indexed referrer);   // a binding is written

function TOKEN() external view returns (address);
function AIRDROP() external view returns (address);
function excluded(address account) external view returns (bool);         // the fixed ecosystem-account set

function stake(uint256 amount, address beneficiary) external returns (uint256 stakeId);
function stakeWithPermit(uint256 amount, address beneficiary,
                         uint256 deadline, uint8 v, bytes32 r, bytes32 s) external returns (uint256 stakeId);
function delegateStake(uint256 stakeId, uint256 amount, address delegateAddress)
    external returns (uint256 delegatedStakeId);   // the staker only (section 5.3)
function claim(uint256 stakeId) external;      // the staker only: the accrued, unclaimed reward
function withdraw(uint256 stakeId) external;   // the staker only, after the term: the principal and the unclaimed reward

function stakeInfo(uint256 stakeId) external view returns (StakeInfo memory);
function claimable(uint256 stakeId) external view returns (uint256);   // accrued minus claimed, never negative
function activeStakeOf(address account) external view returns (uint256);
function reserve() external view returns (uint256);                    // the unallocated stake reserve
function seen(address account) external view returns (bool);
function referrerOf(address account) external view returns (address); // zero for a root
```

`stakeWithPermit` signs the payer's approval with `ERC20Permit` and does what `stake` does in one transaction. Only the staker claims and withdraws: the payer has no right over the stake once it is open. Its staker may delegate all or part of it (section 5.3). `claim` and `withdraw` emit no event of their own: the token's `Transfer` from the staking contract records the amount paid, and `stakeInfo` the state of the stake. `referrerOf` and `seen` together tell the game server the whole referral forest: a seen account with a zero `referrerOf` is a root, and `ReferralBound` lets it be indexed without reading every transfer.

### 5.2 Stake procedure

`stake(amount, beneficiary)` runs these steps in this order; any failing check reverts the whole call:

1. Check that `amount` is at least the minimum principal in section 8.1, and `beneficiary` is neither the zero address nor any ecosystem account other than `AIRDROP`. The caller must also choose a beneficiary able to call `claim` and `withdraw`; the contract cannot generically verify that an arbitrary smart wallet supports those calls.
2. Allocate the reward and the referral budget from the stake reserve; revert when the reserve is short.
3. Write the ordinary stake under the beneficiary: `stakeId`, the amount, the stake block and the allocated reward; add the amount to `activeStakeOf[beneficiary]`. This stake ledger and the reserve allocation are recorded before the principal transfer.
4. Pull `amount` from the payer: `transferFrom(msg.sender, staking, amount)`.
5. When the beneficiary has never been seen, apply the binding rule of section 6: the beneficiary is marked seen, and bound to the payer only when neither address is in `excluded` and the payer already has `activeStakeOf(payer) > 0`. If any condition fails—including a payer with no ordinary stake, the deployment contract or `AIRDROP`—the beneficiary becomes an unbound root. An account already seen keeps its existing binding or root status.
6. Walk the beneficiary's uplines recursively, pay each eligible upline its level share less the level's gas charge and refund the charges to the payer (section 6), then, if the unpaid part of the 20% referral budget is non-zero, record it immediately as an `AIRDROP` stake (section 6), allocating its ordinary reward from the stake reserve; revert when the reserve is short.
7. Emit `Staked` with the ordinary staker and payer. If an `AIRDROP` stake is recorded by this call, emit `Staked` for it as well, with its stake ID, `AIRDROP` as the staker, the staking contract as the payer, and the amount. This records an internal reserve allocation, not a second payer transfer, and it follows the originating stake's `Staked` in the same transaction.

The binding of step 5 keeps the referral forest acyclic: a binding is written only to a payer distinct from the beneficiary, and that payer must already have an ordinary stake principal (`activeStakeOf(payer) > 0`). The payer holds `activeStakeOf(payer) > 0`, so a stake was opened or delegated for it earlier and it was marked seen before the new beneficiary is bound. Every new edge points to an account already seen (`derived`). A beneficiary already seen, whether bound or a root, keeps its existing status whoever pays its stake.

### 5.3 Stake delegation

`delegateStake(stakeId, amount, delegateAddress)` splits an ordinary stake and hands the split part to another account. It runs these steps in this order; any failing check reverts the whole call:

1. Check that the caller is the stake's staker, its principal is not withdrawn, `amount` is at least the minimum principal, and `amount ≤ principal`. If `amount < principal`, the principal remaining in the original stake must also be at least that minimum. Check also that `delegateAddress` is neither the zero address, the caller nor any ecosystem account other than `AIRDROP`.
2. Pay the caller the stake's accrued, unclaimed reward, as `claim` does, so that the reward accrued before delegation stays with the caller.
3. When `delegateAddress` has never been seen, mark it seen and, unless the caller is `AIRDROP`, bind it to the caller as its referrer. The caller holds the stake being split, so `activeStakeOf(caller) > 0` holds. A delegate already seen keeps its existing binding or root status.
4. Write a new ordinary stake under the delegate with principal `amount`, the original stake block, reward allocation `floor(reward × amount / principal)` and claimed amount `floor(claimed × amount / principal)`; the original stake keeps the remainders of principal, reward and claimed amount. Move `amount` from `activeStakeOf[caller]` to `activeStakeOf[delegate]`.
5. Emit `StakeDelegated`.

Delegation moves no LLGAME and touches no reserve: no reward or referral budget is allocated, no referral walk runs and no `AIRDROP` stake is recorded. Both parts keep the original unlock date. The delegated stake is ordinary in every other respect: only the delegate claims and withdraws it, and the delegate may delegate a part of it again. The new binding keeps the referral forest acyclic, since the caller, a staker, was seen before the delegate (`derived`).

## 6. Referral program

The referral program is funded inside the stake call from a budget equal to 20% of the stake amount `A`, taken from the stake reserve. An LLGAME transfer runs no recipient code, so an upline cannot revert a stake or reenter the contract through token receipt. The ordinary stake and reserve allocation are recorded before the principal transfer (section 5.2); the `AIRDROP` stake is recorded once the referral shares have been determined.

The staking contract keeps `seen`, `referrerOf` and the immutable ecosystem-account set `excluded`, and decides each account's referral status once, when the account is first seen; no function rewrites a binding. An account is seen when a stake is first opened for it as beneficiary (section 5.2) or a stake part is first delegated to it (section 5.3); a token transfer, however it reaches the account, neither marks it seen nor binds it. At that moment the account is marked seen, and bound to the payer (or the delegating staker) only when that sender already has an ordinary stake principal recorded (`activeStakeOf > 0`) and neither endpoint is excluded; an account already seen is left unchanged, so a holder that stakes for itself before anyone stakes for it, or whose first staker does not qualify, stays a root. The referral graph is a forest of these immutable bindings, with new roots appearing whenever an account's first staker does not qualify. `AIRDROP` is outside this forest under all circumstances: it cannot be a referrer, cannot be referred and is never paid a referral share.

For a stake of amount `A`, the staking contract walks from the staker's direct upline upward. An upline is eligible when both its liquid balance and its `activeStakeOf` separately meet the level's threshold. The halving share schedule keeps the total payout within the 20% budget, while the doubling requirement limits eligibility at each successive level. At level `n` (starting at 1):

- `share(n) = (A / 10) >> (n − 1)`, that is `floor(A / (10 × 2^(n − 1)))`;
- `required(n) = (1 << (n − 1)) × 10^9` base units, that is `2^(n − 1)` LLGAME, a fixed amount independent of `A`;
- eligible only when `balanceOf(account) ≥ required(n)` and `activeStakeOf(account) ≥ required(n)` separately.

The walk is a filter, not a single chain: an upline that fails its level's threshold is passed over, its share less the level's gas charge staying in the remainder, and the walk goes on to the next upline, whose level number, share and threshold count the passed level too. A stake therefore reaches a farther upline over an undercapitalized account, at that upline's own higher threshold and halved share.

The number of levels has organic math limit: the walk ends at the first of:

- a root: the current account has no referrer;
- a share not worth its gas: `share(n) ≤ gasCost(n)`, which includes the zero share reached once `2^(n − 1) > A / 10`.

The payer pays the gas of the walk in BNB, as of the whole stake transaction, and is refunded in LLGAME out of the shares. `gasCost(n)` is the worth, in LLGAME base units, of the gas the walk has consumed since the previous level was charged, for level 1 since the walk began: `floor(gas × min(tx.gasprice, MAX_GAS_PRICE) × bnbPrice)`, with the gas measured at run time, the gas price of the stake transaction valued at no more than `MAX_GAS_PRICE = 5 gwei`, and `bnbPrice` the launch pair's price of BNB in LLGAME, guarded by a reference price the staking contract keeps. Every level examined is charged out of its own share: the charge is its `gasCost(n)`, cut to what is left of the stake's refund allowance, `floor(A / 50)`, a tenth of the referral budget. An eligible upline is paid its share less the charge, a passed-over level leaves its share less the charge in the remainder, and the charges of all levels are paid to the payer in one LLGAME transfer when the walk ends. The gas of the last level examined and of that transfer is not refunded.

`bnbPrice` is the pair's current price, from the reserves as the stake transaction finds them, unless LLGAME stands there more than `PRICE_GUARD_PERCENT = 5` percent below the reference price, when the reference is used: an LLGAME price pushed down for a stake does not raise its refund, and one pushed up only lowers it. The reference is an approximate recent price of the pair, kept in one storage slot: a walk running at least `PRICE_PERIOD = 30 minutes` after the reference was last set, and finding the pair's reserves untouched in its block, sets it to the current price or, where LLGAME stands lower than the guard allows, raises it by one guard step, a factor of 100/95; the walks until the next such one use it unchanged. A pool moved inside the stake transaction or earlier in its block never sets the reference. Until the first such walk stores a reference, the current price is used unguarded. `gasCost` is zero, charging nothing and leaving the zero share as the only such end, when the gas price is zero or the pair holds no liquidity; nothing is measured or read for a root staker. The share halves at each level while the gas of a level does not grow, so the number of levels examined is logarithmic in `A`, whatever the length of the chain and however many of its uplines are passed over; one paid level takes about 14,900 gas with its slots cold (`illustrative`). The staker's influence is bounded: a gas price above `MAX_GAS_PRICE` changes nothing, a pool price moved inside the stake transaction raises the worth of the gas by no more than about 5% over the reference, which a lowered LLGAME price raises by one step per period and only when held across a block boundary against arbitrage, while no reference is stored the current price is unguarded, and whatever the inputs a charge is less than the share it is taken from, the charges of a stake stay within a tenth of its referral budget, and the shares of the levels not reached go to the remainder (`derived`). The thresholds are 1 LLGAME, 2 LLGAME, 4 LLGAME, 8 LLGAME, and so on, doubling each level.

Eligibility is evaluated after the stake principal has been pulled from the payer and the beneficiary's stake has been recorded; when the payer is the direct upline, the amount just transferred into the new stake does not count as its liquid balance. The threshold applies to the liquid balance and to `activeStakeOf` independently, not to their sum, and does not scale with the stake amount: the liquid balance is what the account can spend now, while `activeStakeOf` includes matured stakes whose principal has not yet been withdrawn and excludes that principal from its `balanceOf`. Both are decremented or spent respectively when principal is withdrawn or liquid funds leave. The sum of the individually rounded shares cannot exceed the rounded 20% referral budget.

The referral budget is `floor(20 × A / 100)` base units. Each level's share is rounded down in base units and calculated from the original stake amount, not from the previous upline's payout. The eligibility threshold is independent of `A`: an upline whose balance or stake is below `2^(n − 1)` LLGAME is passed over however large the stake. With `m = floor(A / 10)`, when a chain pays every level until the share reaches zero, its shares sum to `2m − popcount(m)`, the number of one bits of `m` subtracted; this is at most `2m − 1` and never exceeds the budget `floor(A / 5) ≥ 2m` (`derived`). A shorter chain pays less. The remainder is therefore at least one base unit whenever `m > 0`. Any non-zero budget remainder is immediately recorded as an `AIRDROP` stake in the same stake call, with the ordinary reward and no referral budget. If the remainder rounds to zero base units, no `AIRDROP` stake is created. The contract pays no more than `20% × A` (this holds automatically by the math definition).

## 7. Deployment contract

The deployment contract launches and funds the ecosystem. Its constructor fixes the launch parameters as immutables, launches the ecosystem and records its sender as `PUBLISHER`, a record no call checks: the publisher keeps no right over the contract. `AUTHORS_SUPPLY` is a predefined constant. The contract has no owner, setter or upgrade path; its only privileged call is `AUTHORS`' abort during funding.

### 7.1 Interface

```solidity
// Deployment contract — interface sketch
contract Deployment {
    uint256 private constant AUTHORS_SUPPLY = 500_000 * 10 ** 9;

    enum State { NotLaunched, Funding, Closed, Aborted }   // NotLaunched is never observed

    // The activation transaction: non-payable; the sender is recorded as PUBLISHER.
    constructor(address authors_, address airdrop_, uint256 poolBnbSupply_);

    // A funding round: any sender, msg.value > 0, in Funding.
    receive() external payable;

    function abort() external;    // AUTHORS only, in Funding
    function refund() external;   // a funder, in Aborted, once

    function PUBLISHER() external view returns (address);                // the sender of the publication
    function state() external view returns (State);
    function funded() external view returns (uint256);                   // BNB of all rounds
    function depositOf(address funder) external view returns (uint256);
}
```

### 7.2 Activation and funding

The activation transaction is the publication itself: the constructor is non-payable, so no BNB enters with it. After fixing the parameters it:
- deploys the token, which mints the full supply to the deployment contract;
- transfers `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract's predicted address;
- resolves the canonical pair, creating it if absent;
- deploys the staking contract with its reserve present and `excluded` fixed;
- skims the pair's WBNB balance to `DEAD`;
- opens the creators' 1080-day stake for `AUTHORS`;
- verifies the total supply, the balance split, the creators' stake, a pair holding no LLGAME and a deployment-contract token balance of `POOL_SUPPLY`;
- enters `Funding`, with nothing funded and the pool empty.

A published deployment contract is therefore in `Funding`: `NotLaunched`, the zero value of `State`, keeps the numbering of the states and is never observed.

A funding round is a native BNB transfer in state `Funding` with `msg.value > 0`; any other transfer reverts. Each round adds `msg.value` to `funded()` and to the sender's `depositOf`, and adds its BNB to the pool with LLGAME in proportion to it, `POOL_SUPPLY` per `POOL_BNB_SUPPLY`, minting LP tokens to the deployment contract. The deployment contract holds the rest of `POOL_SUPPLY` until full funding.

The round that brings `funded()` to at least `POOL_BNB_SUPPLY` adds the rest of `POOL_SUPPLY`, sends the launch LP tokens to `DEAD` and enters `Closed`. A first round of at least `POOL_BNB_SUPPLY` funds and closes in one transaction.

### 7.3 Abort

In `Funding`, `abort`, which `AUTHORS` alone may call, removes the liquidity of the launch LP tokens, burns the LLGAME received and the LLGAME still held, unwraps the WBNB received as `withdrawn` and enters `Aborted`. Before the first round there are no LP tokens: the abort then burns the whole `POOL_SUPPLY` and recovers nothing. Each funder's `refund` pays `floor(withdrawn × depositOf(funder) / funded())` once. The token and staking contract remain as launched.

### 7.4 Guarantees

| Property | Guarantee held |
|---|---|
| Ecosystem created by the publication, without attached BNB | The token, the staking contract, the pair and the launch configuration can be inspected before any funding |
| Every launch value a constant or immutable | Nobody can change `AUTHORS`, `AIRDROP`, `POOL_BNB_SUPPLY` or any economic parameter after publication |
| Round bounds and states | The launch happens once, in the constructor; every round enters the pool; funding closes at `POOL_BNB_SUPPLY` or more; nothing is accepted after `Closed` or `Aborted`; `abort` is impossible after `Closed` |
| Nonce-predicted `CREATE` addresses | The reserve sent to the staking contract's address before it exists and the staking contract's `excluded` set are correct by construction |
| Canonical pair | Only the factory-computed pair is used |
| LP tokens sent to `DEAD` at close | Liquidity is locked without a locker or owner; invariant 3 |
| Creators' stake opened in the activation transaction | Locked for 1080 days by the same rules as every stake |
| Abort held by `AUTHORS`, none by the publisher | The key that signs the publication keeps no right over the launch; funding is undone only by the fixed beneficiary of the creators' stake, and refunds every funder pro rata |

After `Closed` the deployment contract holds none of the launch's value and is inert. LLGAME sent to it directly, at any time, is an unsolicited donation: it does not enter the pool, does not hinder the close and has no withdrawal path after it; an abort burns it with the rest. After `Aborted` it holds only BNB not yet refunded.

Between the activation transaction and the first round the pair holds no liquidity, and the only LLGAME outside the contracts is the creators' stake reward `AUTHORS` has claimed: until the first round, only `AUTHORS` or a holder it paid can add liquidity to the pair ahead of the funders (`derived`).

## 8. Parameters

### 8.1 Fixed by the design

| Parameter | Value |
|---|---|
| `DECIMALS` | 9 |
| `TOTAL_SUPPLY` | 3.4 × 10^29 LLGAME, `3.4 × 10^38` base units, minted once |
| `POOL_SUPPLY` | 10,000 LLGAME (10,000 × 10^9 base units in Solidity) |
| `AUTHORS_SUPPLY` | 500,000 LLGAME (`500,000 × 10^9` base units), predefined and not configurable |
| Creators' stake | `AUTHORS_SUPPLY` staked for 1080 days under the ordinary staking rules: 288% reward allocation and 20% referral budget |
| Referral budget | 20% of each ordinary stake amount |
| Referral shares | `(A / 10) >> (n−1)` base units per level |
| Referral binding | When a stake is first opened for an account, or a stake part first delegated to it, the payer (or delegating staker) must have `activeStakeOf > 0` and neither endpoint may be in `excluded`; a plain token transfer binds nothing |
| Referral payout eligibility | At every level `n`, `balanceOf(upline) >= (1 << (n−1)) × 10^9` and `activeStakeOf(upline) >= (1 << (n−1)) × 10^9` base units (that is, `2^(n−1)` LLGAME each), applied separately, with no dependence on `A` |
| Referral walk end | A root, or the first level `n` with `share(n) ≤ gasCost(n)`; an ineligible upline is passed over |
| Referral gas refund | `gasCost(n) = floor(gas × min(tx.gasprice, MAX_GAS_PRICE) × bnbPrice)` for the gas measured since the previous charge, taken from the share of every level examined and paid to the payer in LLGAME |
| `MAX_GAS_PRICE` | 5 gwei, the highest gas price a referral gas refund is valued at |
| Referral gas refund allowance | `floor(A / 50)` per stake, a tenth of its referral budget |
| `PRICE_PERIOD` | 30 minutes, the shortest time between two settings of the reference price of BNB in LLGAME |
| `PRICE_GUARD_PERCENT` | 5: a current LLGAME price further below the reference is replaced by the reference, which follows it by a factor of 100/95 per setting |
| Staking term | 1080 days, the only term |
| Minimum ordinary stake principal | 72,000,000 base units. Applies to public `stake` / `stakeWithPermit` calls and delegated stake portions; internally created `AIRDROP` referral-remainder stakes are exempt |
| Reward rate | 288% of principal over the term |
| Reward release | Linear over the stake term, claimable by the staker as it accrues |
| Pool | PancakeSwap v2 LLGAME/WBNB pair; launch LP position sent to `DEAD` at close |
| Funding | Rounds totalling at least `POOL_BNB_SUPPLY` wei, each entering the pool with LLGAME in proportion to its BNB, `POOL_SUPPLY` per `POOL_BNB_SUPPLY` |
| Unpaid referral remainder | Any non-zero remainder is recorded immediately as an `AIRDROP` stake, with the 1080-day term, the ordinary reward and no referral budget |

### 8.2 Values fixed before publication

Every value in this table must be final before the deployment contract is published: the publisher passes it to the constructor and nothing changes it afterwards. `AIRDROP` is distinct from every other excluded or DEX infrastructure address.

| Parameter | Meaning | Requirement |
|---|---|---|
| `AUTHORS` | Address that receives the creators' stake and may abort the funding | Non-zero; not in the staking contract's `excluded` set; must be an EOA or a smart wallet able to call the staking contract and the deployment contract's `abort` |
| `AIRDROP` | Special address for referral-remainder stakes | Non-zero; distinct from `AUTHORS`, the token, pair, staking contract, deployment contract, `DEAD`, factory and WBNB; included in `excluded`; must be an EOA or a smart wallet able to call the staking contract |
| `POOL_BNB_SUPPLY` | Minimum total BNB in wei of all funding rounds | 16.9 BNB, `16_900_000_000_000_000_000` wei |

## 9. Reserve accounting

The staking reserve is finite and is the source of every staking reward, referral payment and `AIRDROP` stake. The contract allocates the full cost of each stake when that stake is opened. It never promises a reward or referral amount that has not already been reserved. In the formulas below, `floor(x)` denotes integer division with the same rounding used by the staking contract.

### 9.1 Cost of an ordinary stake

For a stake of principal `A`, the principal itself is transferred by the payer and is not taken from the unallocated reserve. The reserve funds the reward allocation, the 20% referral budget and the reward of the `AIRDROP` stake made of its unpaid remainder:

| Reward allocation | Referral allocation | `AIRDROP` stake reward | Total reserve allocation `c × A` |
|---:|---:|---:|---:|
| 288% of `A` | 20% of `A` | up to 57.6% of `A` | 3.08 to 3.656 × `A` |

The referral allocation is fully accounted for at stake time. Shares paid to eligible uplines leave the staking contract immediately. The unpaid remainder is not free reserve: it is a liability recorded as an `AIRDROP` stake, whose reward is allocated in addition. It therefore remains part of the allocated 20% and cannot be counted again as available reserve.

### 9.2 Reserve immediately after activation

The token constructor mints the whole supply to the deployment contract, which transfers `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract. During activation, the deployment contract keeps `POOL_SUPPLY` for the pool and opens the creators' stake for `AUTHORS`.

The creators' stake follows the ordinary 1080-day rules. Since `AUTHORS` begins as an unbound root, it has no upline at activation; the full 100,000 LLGAME referral allocation therefore becomes an `AIRDROP` stake with its own 288,000 LLGAME reward. The creators' stake also allocates its 1,440,000 LLGAME reward. The unallocated reserve after activation is consequently:

```
R_launch = TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY
          − floor(288 × AUTHORS_SUPPLY / 100)
          − floor(20 × AUTHORS_SUPPLY / 100)
          − floor(288 × floor(20 × AUTHORS_SUPPLY / 100) / 100)

         = 3.4 × 10^29 − 2,338,000 LLGAME
```

The subtraction comprises 10,000 LLGAME for the pool and 500,000 LLGAME principal, 1,440,000 LLGAME reward and 100,000 LLGAME referral allocation for the creators' stake, and 288,000 LLGAME reward of the resulting `AIRDROP` stake. The result is positive and exact with the stated integer-floor operations; it assumes the deployment transaction completes successfully. The staking contract's token balance immediately after activation is `TOTAL_SUPPLY − POOL_SUPPLY`; that balance is divided between the creators' principal and reward, the `AIRDROP` stake's principal and reward, and `R_launch`.

### 9.3 Capacity and duration

For a new ordinary stake of amount `A`, the unallocated reserve must cover up to `3.656 × A`. Ignoring integer rounding, the maximum cumulative principal amount that can be opened against a reserve `R` is therefore bounded by `R / 3.08`.

This is a cumulative stake-volume bound, not a simultaneous-stake limit or a calendar-lifetime guarantee. The actual duration depends primarily on aggregate new stake volume. Referral eligibility changes the destination of the fixed referral allocation, not its reserve cost; restaking rewards or withdrawn principal can increase later stake volume, while principal withdrawals themselves do not replenish the reserve. The market price and available DEX liquidity may influence demand, but they do not mathematically guarantee a minimum reserve lifetime. The contract's enforceable guarantee is narrower and stronger: every accepted stake is fully allocated at entry, and a new stake reverts if its full reward and referral allocation cannot be covered.

### 9.4 Sizing the supply

The supply is sized to fit the staking ledger's packed amount field. ERC-20 balances are `uint256`, but each stored token-denominated stake amount, principal, reward allocation and reserve amount is bounded by total supply and fits a `uint128`. Computed referral thresholds and multiplication intermediates use `uint256` and are not packed into that field. With 9 decimals, `3.4 × 10^29` LLGAME is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38` and leaving approximately 0.08% of the range unused.

| Decimals | Supply | Base units | Width |
|---|---|---|---|
| 9 | 3.4 × 10^29 LLGAME | 3.4 × 10^38 | 128 bits |


## Sources

1. OpenZeppelin Contracts 5.x, ERC20 API. https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
2. EIP-161: state trie clearing, contract nonce starting at one. https://eips.ethereum.org/EIPS/eip-161
3. PancakeSwap developer docs, v2 Factory and Addresses. https://developer.pancakeswap.finance/contracts/v2/addresses
4. `PancakePair` source: `MINIMUM_LIQUIDITY`, `mint(to)`, `skim(to)` and reserve accounting. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakePair.sol
5. `PancakeFactory` source: `createPair` uses CREATE2 and does not require either token address to contain token code. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakeFactory.sol
6. Solidity documentation: `receive()` handles empty-calldata transfers; `send()` and `transfer()` forward only the 2,300-gas stipend. https://docs.solidity.org/en/latest/contracts.html
7. BNB Smart Chain documentation, Introduction: 0.45-second average mainnet block interval. https://docs.bnbchain.org/bnb-smart-chain/introduction/
