# Legacy Life Game (LLGAME) white paper

## Introduction

### Game

Legacy Life is an educational economic game whose player creates avatars, buys capital goods, attracts partners, develops a team, runs a simulated business and distributes its proceeds.

Gameplay tests the player inside simulated economic and social relations: capital is committed, agreements create links, team growth changes payouts and every reward comes from a visible budget.

### Token backend

Legacy Life game token is the game's independent finance backend: a BEP-20 token and locked staking contract on BNB Smart Chain. The game server keeps story, quests, characters and interface; the contracts keep balances, stakes, referral links, payout rules, and the operator cannot rewrite them or move a player's money.

The token emulates finance rather than offering it: payments, fixed-term deposits, referral network to conquer the market, all game-scaled but real on chain.

## 1. Ecosystem

Legacy Life game (LLGAME) is the BEP-20 token on BNB Smart Chain (BSC). Its whole supply is minted once, to its publisher, when the token is published, ahead of every other contract:

- 3.4 × 10^29 LLGAME, that is 340,000,000,000,000,000,000,000,000,000 LLGAME, sized in section 9.4

The supply is allocated as follows:

- `AUTHORS_SUPPLY = 500,000` LLGAME - creators' stake, locked for 1080 days: an ordinary stake opened for the fixed `AUTHORS` address when the staking contract is set;
- up to `POOL_SUPPLY_CAP = 1,000,000` LLGAME paired with BNB in a launch liquidity pool, in the amounts `AUTHORS` sets during funding, whose liquidity provider (LP) tokens are sent to `DEAD` when funding closes;
- the remaining supply, with the pool's unused part at close, is held by the staking contract. After the creators' stake is opened, the unallocated part becomes the reserve that funds subsequent staking rewards and referral allocations.

Holders receive value through:

- staking for 1080 days, with rewards accruing over time and claimable as they accrue;
- the referral program: a budget of each stake, paid inside the stake call to the staker's uplines;
- gamified airdrops: any non-zero unpaid remainder of that budget is recorded immediately as a stake for the special `AIRDROP` address, making the accumulated airdrop budget transparent and predictable on chain;

The operational ecosystem consists of the token, a staking contract, a referral contract and a DEX pair, brought together by a separate deployment contract. Two separately controlled addresses participate in its economics: `AUTHORS`, the ordinary beneficiary of the creators' stake, and `AIRDROP`, the special address for accumulated referral remainders.:

| Part | Role | Administration |
|---|---|---|
| Token (`LLGAME`) | OpenZeppelin v5 `ERC20`, `ERC20Burnable`, `ERC20Permit`, 9 decimals, no access control module, no transfer hook and no reference to another contract of the ecosystem | None: locked at publication |
| Pool | PancakeSwap v2 LLGAME/WBNB pair, launch LP position sent to `DEAD` at close | None: the pair is DEX code, its protocol `feeTo` share excepted |
| Staking | Holds the reserve and the ecosystem-account set; submits a beneficiary's signed referral binding to the referral contract; takes stakes paid by their caller for a beneficiary, splits a part of a stake to a delegate at its staker's request, allocates rewards, pays referral shares to eligible uplines, records any non-zero unpaid referral remainder as an `AIRDROP` stake inside the stake call | None: locked at launch |
| Referral | Standalone record of who referred whom, written on each account's own signature; references no token and no staking contract | None: locked at publication |
| Deployment contract | Takes the whole supply of the published token, funds the staking contract `AUTHORS` names and opens the creators' stake there, builds the pool from the amounts `AUTHORS` sets and closes at `AUTHORS`' call | Every call `AUTHORS`' alone; no right of its publisher, no upgrade path, no return of LLGAME to `AUTHORS` |
| `AUTHORS` address | Fixed beneficiary of the creators' stake and the one account able to call the deployment contract; to the token and the staking contract an ordinary account with no exclusion or privilege | Its key or multisig policy controls that account and every call of the deployment contract until close; it has no right over a locked contract |
| `AIRDROP` address | Special address whose stakes accumulate unpaid referral-budget remainders for later airdrops; cannot participate in the referral program as referrer or referred account | Its key or multisig policy claims and withdraws under the common staking rules |

### 1.1 Terms

| Term | Meaning |
|---|---|
| Locked contract | A contract deployed final: no owner, admin role, settable parameter, pause, upgrade or administrator withdrawal; every table and threshold is a constant or immutable. Staking principal and rewards remain withdrawable only through the fixed user-facing rules |
| Ecosystem account | A fixed system address excluded from the referral program, never paid a referral share and its stakes running no walk: the launch pair, staking contract, deployment contract, dead address and `AIRDROP` |
| Staker | The beneficiary of a stake: the account whose active stake it is, whose reward ledger it feeds, to which the principal returns and whose uplines the stake's referral walk pays |
| Payer | The caller of `stake`, whose LLGAME funds the stake; the staker itself in the common case |
| Stake reserve | LLGAME in the staking contract not allocated to any stake |
| Referral budget | 20% of each ordinary stake's amount, taken from the stake reserve at stake time and paid recursively to eligible uplines by the halving share formula; any non-zero unpaid remainder is recorded as an `AIRDROP` stake |
| Operator | The party running the game; it cannot change the locked contracts or their payout rules |
| Deployment contract | A launcher bound at publication to the token and to `AUTHORS`, whose calls alone it takes: it pulls the supply, sets the staking contract, supplies the pool and closes (section 7) |
| Funding | From the setting of the staking contract until close or abort (section 7) |
| `derived` | Marks a statement that follows from the rules stated elsewhere, not a separate rule |

## 2. Invariants

Every part of the ecosystem is bound by the following; the requirements of sections 3 to 7 are consequences of these invariants.

1. **Locked at launch.** The token and the staking contract are locked contracts. No proxy, upgradeable part or contract-administration signer exists in the token or staking contracts; the deployment contract's calls are `AUTHORS`' alone and end at close, and the staking contract is the one `AUTHORS` names there, once.
2. **No mint after creation.** The token's constructor mints the whole supply and no function can mint again. Every staking reward and referral allocation is funded from the staking contract's pre-minted holdings.
3. **No administration of value.** No key can move LLGAME out of a locked contract except through its fixed rules: staking principal withdrawal, reward claim, and referral payout. From close, the launch LP position is irretrievably held at `DEAD`; during funding only an abort removes its liquidity, returning its BNB to `AUTHORS`; PancakeSwap may separately mint protocol-fee LP shares to its configured `feeTo` address under the DEX's own rules, as described in section 4. `AIRDROP` claims and withdraws under the common rules and has no administrative right over any contract.
4. **Fixed conditions.** The staking term and rate, the referral budget and referral formula, the fixed `AUTHORS` beneficiary, the `AIRDROP` address and the fixed ecosystem-account exclusion set are immutable or constants of the contracts that use them.
5. **Solvent by construction.** Nothing is owed beyond what is allocated: a stake reverts when the stake reserve cannot cover its reward, its referral budget and the reward of its `AIRDROP` stake; the referral walk pays eligible shares within the stake's referral budget in the same call, and any unpaid part is recorded as an `AIRDROP` stake. The sum of the staking contract's accounted ledgers—principal still held, allocated rewards not yet claimed and unallocated reserve—never exceeds its LLGAME balance. A direct token transfer to the staking contract outside `stake` and `fund` is an unsolicited donation: it is not credited to the reserve or any stake ledger and has no withdrawal path.
6. **Deterministic binding and payouts.** A referral binding is written only on the account's own signature over its referrer, once, and never where it would close a cycle; a plain token transfer binds nothing. Referral shares are paid to uplines whose liquid balance and `activeStakeOf` both meet the level's fixed threshold, down to the level at which the walk ends (section 6). No off-chain party can alter the binding, the shares or the thresholds; the staker alone, through the gas price of its stake transaction up to its fixed cap and the pool's price within the guard of its reference price, can end the walk of its own stake earlier and raise the gas charge that the walk takes from the shares and refunds to the payer, never extend the walk or redirect a share beyond that charge. Distribution of matured funds withdrawn by `AIRDROP` is an off-chain activity and is not controlled by the contracts.
7. **No transfer tax.** The token overrides no transfer logic: an ordinary transfer deducts no fee, redirects no part and calls no other contract.

## 3. Token

- Name Legacy Life Game, symbol LLGAME, 9 decimals, total supply `TOTAL_SUPPLY = 3.4 × 10^29` LLGAME, that is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38`. Every stored token balance and token-denominated stake or reserve ledger is bounded by total supply and fits a `uint128`; intermediate calculations and referral thresholds use `uint256` (section 9.4).
- The constructor mints the whole `TOTAL_SUPPLY` to its deployer, an account its creators control; the deployment contract pulls it from its holder at launch. The token emits no further mint ever. All LLGAME amounts passed to token and staking functions are expressed in base units; BNB amounts are expressed in wei. The prose expresses token balances in LLGAME (9 decimals).
- The token keeps no referral state and holds no reference to the staking contract: it is the plain composition of the three OpenZeppelin contracts.
- `ERC20Burnable` lets any holder burn its own tokens; nothing in the ecosystem requires a burn.
- `ERC20Permit` lets a holder approve the staking contract by signature, so a stake is one transaction.
- The token inherits no access control module: there is no owner, no role and no function that would need one.

### 3.1 Interface

The token adds nothing to the OpenZeppelin `ERC20`, `ERC20Burnable` and `ERC20Permit` interfaces.

## 4. Pool

The launch pool is the canonical PancakeSwap v2 LLGAME/WBNB pair. At close it holds:

- The LLGAME, at most `POOL_SUPPLY_CAP`, and the BNB as WBNB that `AUTHORS` supplied (section 7.2). Their ratio is the launch price, which `AUTHORS` sets and corrects for the BNB rate until the close.
- `POOL_SUPPLY_CAP` is one part in 3.4 × 10^23 of the total supply. The pool is the initial DEX source of freely tradable LLGAME; the creators' principal is locked in staking, while reserve distributions occur only through the staking rules. Tokens subsequently circulate through ordinary transfers, staking payouts, referral payouts and any off-chain airdrops funded by matured `AIRDROP` withdrawals.
- The launch LP tokens are held at the dead address, so that position is locked without a locker contract or owner. Swap fees remain in the pair's reserves; the PancakeSwap protocol may separately mint `feeTo` LP shares under its own factory-controlled fee mechanism.

## 5. Staking

A holder stakes an amount `A` for the fixed term of 1080 days, with `stake(amount, beneficiary)`. The caller is the payer: the amount is pulled from its balance. The beneficiary is the staker: the stake belongs to that account. In the common case, the caller names itself, but anyone can open a stake for anyone else. The staking contract allocates at stake time, out of the stake reserve, everything the stake will ever cost; a stake that the reserve cannot cover reverts. The staking contract is not bound to one token: it keeps for every token a ledger of its own, with its reserve, stakes, `activeStakeOf`, `AIRDROP` account, launch pair and deployment contract, and everything stated here of the staking contract is stated of its LLGAME ledger, its calls naming the token ahead of their other arguments. A token's ledger opens with `initialize(token, airdrop, pair, amount)`, which funds the reserve with a non-zero amount and fixes with it, once, the token's `AIRDROP` account, its launch pair and, as the caller, its deployment contract; no stake of the token opens before. The call is free to any holder of a token. For LLGAME the whole supply is held by its one holder and then by the deployment contract until that contract makes the call, so nobody else can make it first (`derived`). From then on its reserve is credited by `fund(amount)`, which pulls the amount from any caller irrevocably. Direct LLGAME transfers to the staking address are not treated as reserve deposits; they remain unaccounted surplus and cannot be withdrawn.

Every public `stake` or `stakeWithPermit` call must meet the minimum principal of **0.072 LLGAME** (72,000,000 base units).

This limit targets an average accrued reward of at least one base unit per average BSC block, using the documented 0.45-second average block interval. The minimum applies to public stake calls; the internally created referral-remainder `AIRDROP` stake described in section 5.2 is exempt.

| Allocation at stake time | Amount | Destination |
|---|---|---|
| Reward | 288% of `A`, that is 8% of `A` per 30 days | The staker's reward ledger, released linearly over the term |
| Referral budget | 20% of `A` (section 6) | Allocated from the stake reserve; eligible shares are paid immediately and the remainder becomes an `AIRDROP` stake (section 6) |

The reward accrues linearly from the stake block to the unlock, and the staker claims the accrued part at any time, capped by the allocated reward; the ledger keeps the claimed amount, so a fully claimed stake reads and claims cleanly. The principal is returned to the staker, with the unclaimed reward, at the end of the term, once. There is no early withdrawal and no compounding: a holder that wants to restake takes its payout and stakes again, which triggers a new referral budget. The contract keeps `activeStakeOf[account]`, the sum of the account's stake principals still held by the staking contract, including matured stakes whose principal has not yet been withdrawn. It enters the upline's payout eligibility (section 6). It is incremented when a stake opens and decremented exactly once when that stake's principal is withdrawn. No separate staker flag or registration state is needed.

### 5.1 Interface

```solidity
// Staking contract: interface sketch of one token's ledger; every other call and view below takes the token
// as its first argument
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

function REFERRAL() external view returns (address);   // the referral contract the walk reads
function AIRDROP() external view returns (address);
function excluded(address account) external view returns (bool);         // the fixed ecosystem-account set

function stake(uint256 amount, address beneficiary) external returns (uint256 stakeId);
function stakeWithReferral(uint256 amount, address beneficiary, address referrer, bytes calldata signature)
    external returns (uint256 stakeId);   // submits the beneficiary's signed binding first (section 6)
function initialize(address token, address airdrop, address pair, uint256 amount) external;   // once per token: links its ledger and funds its reserve
function fund(uint256 amount) external;   // any caller, once initialized: credits its LLGAME to the reserve, irrevocably
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
```

`stakeWithPermit` signs the payer's approval with `ERC20Permit` and does what `stake` does in one transaction. Only the staker claims and withdraws: the payer has no right over the stake once it is open. Its staker may delegate all or part of it (section 5.3). `claim` and `withdraw` emit no event of their own: the token's `Transfer` from the staking contract records the amount paid, and `stakeInfo` the state of the stake. The referral forest is read from the referral contract (section 6).

### 5.2 Stake procedure

`stake(amount, beneficiary)` runs these steps in this order; any failing check reverts the whole call:

1. Check that `amount` is at least the minimum principal in section 8.1, and `beneficiary` is neither the zero address nor any ecosystem account other than `AIRDROP`. The caller must also choose a beneficiary able to call `claim` and `withdraw`; the contract cannot generically verify that an arbitrary smart wallet supports those calls.
2. Allocate the reward and the referral budget from the stake reserve; revert when the reserve is short.
3. Write the ordinary stake under the beneficiary: `stakeId`, the amount, the stake block and the allocated reward; add the amount to `activeStakeOf[beneficiary]`. This stake ledger and the reserve allocation are recorded before the principal transfer.
4. Pull `amount` from the payer: `transferFrom(msg.sender, staking, amount)`.
5. When the call carries a referrer and the beneficiary's signature, submit them to the referral contract (section 6); a refused binding changes nothing and does not fail the stake.
6. Walk the beneficiary's uplines recursively, pay each eligible upline its level share less the level's gas charge and refund the charges to the payer (section 6), then, if the unpaid part of the 20% referral budget is non-zero, record it immediately as an `AIRDROP` stake (section 6), allocating its ordinary reward from the stake reserve; revert when the reserve is short.
7. Emit `Staked` with the ordinary staker and payer. If an `AIRDROP` stake is recorded by this call, emit `Staked` for it as well, with its stake ID, `AIRDROP` as the staker, the staking contract as the payer, and the amount. This records an internal reserve allocation, not a second payer transfer, and it follows the originating stake's `Staked` in the same transaction.

### 5.3 Stake delegation

`delegateStake(stakeId, amount, delegateAddress)` splits an ordinary stake and hands the split part to another account. It runs these steps in this order; any failing check reverts the whole call:

1. Check that the caller is the stake's staker, its principal is not withdrawn, `amount` is at least the minimum principal, and `amount ≤ principal`. If `amount < principal`, the principal remaining in the original stake must also be at least that minimum. Check also that `delegateAddress` is neither the zero address, the caller nor any ecosystem account other than `AIRDROP`.
2. Pay the caller the stake's accrued, unclaimed reward, as `claim` does, so that the reward accrued before delegation stays with the caller.
3. Write a new ordinary stake under the delegate with principal `amount`, the original stake block, reward allocation `floor(reward × amount / principal)` and claimed amount `floor(claimed × amount / principal)`; the original stake keeps the remainders of principal, reward and claimed amount. Move `amount` from `activeStakeOf[caller]` to `activeStakeOf[delegate]`.
4. Emit `StakeDelegated`.

Delegation moves no LLGAME and touches no reserve: no reward or referral budget is allocated, no referral walk runs and no `AIRDROP` stake is recorded. Both parts keep the original unlock date. The delegated stake is ordinary in every other respect: only the delegate claims and withdraws it, and the delegate may delegate a part of it again.

## 6. Referral program

The referral program is funded inside the stake call from a budget equal to 20% of the stake amount `A`, taken from the stake reserve. An LLGAME transfer runs no recipient code, so an upline cannot revert a stake or reenter the contract through token receipt. The ordinary stake and reserve allocation are recorded before the principal transfer (section 5.2); the `AIRDROP` stake is recorded once the referral shares have been determined.

The referral bindings are kept by the referral contract, a standalone locked contract that references no token and no staking contract: it stores for an account the referrer that account has signed for, and answers queries.

```solidity
// Referral contract: interface sketch
event ReferralBound(address indexed account, address indexed referrer);

function bind(address account, address referrer, bytes calldata signature) external;   // any caller
function referrerOf(address account) external view returns (address);                  // zero while unbound
```

A binding is the account's EIP-712 signature over the referrer's address, under the referral contract's own domain. `bind` may be submitted by anyone and writes `referrerOf[account]` only when the signature is the account's own over exactly that referrer, the account has no referrer yet, and the referrer is neither the zero address, the account itself nor an account below it in the forest. The signature of a plain account is checked by ECDSA and that of a smart wallet by ERC-1271. A written binding is final: no function rewrites or removes it, and a signature for another referrer submitted afterwards is refused. The signature carries no nonce and no deadline, the rule itself letting it take effect once.

The signature is collected off chain: the game's dApp, opened by a referral link naming the referrer, asks the account to sign and keeps the first signature it is given. Whoever opens a stake for the account, the account itself or another payer, may pass the referrer and the signature along with the stake: the staking contract submits them to the referral contract before the walk, and a missing or refused signature leaves the account as it was without failing the stake. An unbound account stays bindable, by a later stake or by `bind` directly. Who pays a stake binds nothing, nor does a token transfer.

The staking contract reads `referrerOf` for the walk and applies its own exclusions to what it reads: `AIRDROP` and the other ecosystem accounts are never paid a referral share and their stakes run no walk, whatever the referral contract holds for them. The bindings form a forest: `bind` walks from the referrer up its chain of referrers to the root and refuses the binding when it meets the account, so no binding closes a cycle. The walk is paid by whoever submits the binding and grows with the depth of the referrer's chain; an account that already has referees stays bindable to any account not below it.

For a stake of amount `A`, the staking contract walks from the staker's direct upline upward. An upline is eligible when both its liquid balance and its `activeStakeOf` separately meet the level's threshold. The halving share schedule keeps the total payout within the 20% budget, while the doubling requirement limits eligibility at each successive level. At level `n` (starting at 1):

- `share(n) = (A / 10) >> (n − 1)`, that is `floor(A / (10 × 2^(n − 1)))`;
- `required(n) = (1 << (n − 1)) × 10^9` base units, that is `2^(n − 1)` LLGAME, a fixed amount independent of `A`;
- eligible only when `balanceOf(account) ≥ required(n)` and `activeStakeOf(account) ≥ required(n)` separately.

The walk is a filter, not a single chain: an upline that fails its level's threshold is passed over, its share less the level's gas charge staying in the remainder, and the walk goes on to the next upline, whose level number, share and threshold count the passed level too. A stake therefore reaches a farther upline over an undercapitalized account, at that upline's own higher threshold and halved share.

The number of levels has organic math limit: the walk ends at the first of:

- a root: the current account has no referrer;
- a share not worth its gas: `share(n) ≤ gasCost(n)`, which includes the zero share reached once `2^(n − 1) > A / 10`.

The payer pays the gas of the walk in BNB, as of the whole stake transaction, and is refunded in LLGAME out of the shares. `gasCost(n)` is the worth, in LLGAME base units, of the gas the walk has consumed since the previous level was charged, for level 1 since the walk began: `floor(gas × min(tx.gasprice, MAX_GAS_PRICE) × bnbPrice)`, with the gas measured at run time, the gas price of the stake transaction valued at no more than `MAX_GAS_PRICE = 0.5 gwei`, and `bnbPrice` the launch pair's price of BNB in LLGAME, guarded by a reference price the staking contract keeps. Every level examined is charged out of its own share: the charge is its `gasCost(n)`, cut to what is left of the stake's refund allowance, `floor(A / 50)`, a tenth of the referral budget. An eligible upline is paid its share less the charge, a passed-over level leaves its share less the charge in the remainder, and the charges of all levels are paid to the payer in one LLGAME transfer when the walk ends. The gas of the last level examined and of that transfer is not refunded.

`bnbPrice` is the pair's current price, from the reserves as the stake transaction finds them, unless LLGAME stands there more than `PRICE_GUARD_PERCENT = 5` percent below the reference price, when the reference is used: an LLGAME price pushed down for a stake does not raise its refund, and one pushed up only lowers it. The reference is an approximate recent price of the pair, kept in one storage slot: a walk running at least `PRICE_PERIOD = 30 minutes` after the reference was last set, and finding the pair's reserves untouched in its block, sets it to the current price or, where LLGAME stands lower than the guard allows, raises it by one guard step, a factor of 100/95; the walks until the next such one use it unchanged. A pool moved inside the stake transaction or earlier in its block never sets the reference. Until the first such walk stores a reference, the current price is used unguarded. `gasCost` is zero, charging nothing and leaving the zero share as the only such end, when the gas price is zero or the pair holds no liquidity; nothing is measured or read for a root staker. The share halves at each level while the gas of a level does not grow, so the number of levels examined is logarithmic in `A`, whatever the length of the chain and however many of its uplines are passed over; one paid level takes about 14,900 gas with its slots cold (`illustrative`). The staker's influence is bounded: a gas price above `MAX_GAS_PRICE` changes nothing, a pool price moved inside the stake transaction raises the worth of the gas by no more than about 5% over the reference, which a lowered LLGAME price raises by one step per period and only when held across a block boundary against arbitrage, while no reference is stored the current price is unguarded, and whatever the inputs a charge is less than the share it is taken from, the charges of a stake stay within a tenth of its referral budget, and the shares of the levels not reached go to the remainder (`derived`). The thresholds are 1 LLGAME, 2 LLGAME, 4 LLGAME, 8 LLGAME, and so on, doubling each level.

Eligibility is evaluated after the stake principal has been pulled from the payer and the beneficiary's stake has been recorded; when the payer is the direct upline, the amount just transferred into the new stake does not count as its liquid balance. The threshold applies to the liquid balance and to `activeStakeOf` independently, not to their sum, and does not scale with the stake amount: the liquid balance is what the account can spend now, while `activeStakeOf` includes matured stakes whose principal has not yet been withdrawn and excludes that principal from its `balanceOf`. Both are decremented or spent respectively when principal is withdrawn or liquid funds leave. The sum of the individually rounded shares cannot exceed the rounded 20% referral budget.

The referral budget is `floor(20 × A / 100)` base units. Each level's share is rounded down in base units and calculated from the original stake amount, not from the previous upline's payout. The eligibility threshold is independent of `A`: an upline whose balance or stake is below `2^(n − 1)` LLGAME is passed over however large the stake. With `m = floor(A / 10)`, when a chain pays every level until the share reaches zero, its shares sum to `2m − popcount(m)`, the number of one bits of `m` subtracted; this is at most `2m − 1` and never exceeds the budget `floor(A / 5) ≥ 2m` (`derived`). A shorter chain pays less. The remainder is therefore at least one base unit whenever `m > 0`. Any non-zero budget remainder is immediately recorded as an `AIRDROP` stake in the same stake call, with the ordinary reward and no referral budget. If the remainder rounds to zero base units, no `AIRDROP` stake is created. The contract pays no more than `20% × A` (this holds automatically by the math definition).

## 7. Deployment contract

The deployment contract takes the whole supply of the token, published before it, hands the reserve to a staking contract named later and builds the launch pool. Its constructor fixes the token, `AUTHORS` and `AIRDROP` as immutables, resolves the canonical pair, creating it if absent, and records its sender as `PUBLISHER`, a record no call checks: the publisher keeps no right over the contract. Every call of the contract is `AUTHORS`' alone. `AUTHORS_SUPPLY` and `POOL_SUPPLY_CAP` are predefined constants. The contract has no upgrade path and no call that returns LLGAME to `AUTHORS`: the supply it took leaves it only to the staking contract or to the pool.

### 7.1 Interface

```solidity
// Deployment contract — interface sketch
// What a staking contract must answer to be set
interface ILaunchStaking {
    function reserve(address token) external view returns (uint256);
    function activeStakeOf(address token, address account) external view returns (uint256);
    function airdropOf(address token) external view returns (address);   // zero until the token is initialized
    function pairOf(address token) external view returns (address);
    // once per token, amount > 0: fixes the token's AIRDROP, pair and, as the caller, deployment contract,
    // and credits the amount to its reserve
    function initialize(address token, address airdrop, address pair, uint256 amount) external;
    function fund(address token, uint256 amount) external;   // credits the caller's tokens to the token's reserve
    function stake(address token, uint256 amount, address beneficiary) external returns (uint256 stakeId);
}

contract Deployment {
    uint256 private constant AUTHORS_SUPPLY = 500_000 * 10 ** 9;
    uint256 private constant POOL_SUPPLY_CAP = 1_000_000 * 10 ** 9;

    enum State { NotLaunched, Launched, Funding, Closed, Aborted }

    // Non-payable; the sender is recorded as PUBLISHER.
    constructor(address token_, address authors_, address airdrop_);

    // AUTHORS only, each in the state named.
    function launch(address holder, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;   // NotLaunched
    function setStaking(address staking_) external;                              // Launched, once
    function setPoolAmounts(uint256 llgame, uint256 bnb) external;       // Funding, any number of times
    receive() external payable;                                                  // Funding, amounts set: supplies the pool
    function close() external;                                                   // Funding
    function abort() external;                                                   // Funding

    function PUBLISHER() external view returns (address);   // the sender of the publication
    function state() external view returns (State);
    function staking() external view returns (address);     // zero until set
    function pair() external view returns (address);
    function poolLlgame() external view returns (uint256);  // LLGAME supplied to the pool
    function poolBnb() external view returns (uint256);     // BNB supplied to the pool
}
```

### 7.2 Launch, staking and pool

The contract passes through its states in one order, each step a call of `AUTHORS`:

| State | Entered by | Holds |
|---|---|---|
| `NotLaunched` | Publication | Nothing |
| `Launched` | `launch` | The whole supply |
| `Funding` | `setStaking` | `POOL_SUPPLY_CAP` less what the pool received |
| `Closed` | `close` | Nothing |
| `Aborted` | `abort` | Nothing |

`launch(holder, deadline, v, r, s)` pulls the token's whole `totalSupply()` from `holder`, the account the token's publication minted the supply to or one it was moved to since, which need not be `AUTHORS`. It pulls on the holder's `ERC20Permit` signature passed, naming the deployment contract as spender, or, where the permit fails, on an allowance already in place: a permit submitted ahead by someone else, or an `approve` by a holder that is a smart wallet and cannot sign one. The holder sends no transaction of its own; the signature serves no one but the deployment contract, and the call passes only when the contract then holds the whole supply.

`setStaking(staking_)` names the staking contract, once and irrevocably. The address must hold code, answer `airdropOf(token)` with the zero address, the token not yet initialized there, and hold no LLGAME. The call then:
- funds it with `TOTAL_SUPPLY − POOL_SUPPLY_CAP − AUTHORS_SUPPLY` through `initialize(token, AIRDROP, pair, amount)`, which fixes there for the token, once and with its reserve, the `AIRDROP` account, the launch pair and, as its caller, the deployment contract;
- opens the creators' stake with `stake(token, AUTHORS_SUPPLY, AUTHORS)`;
- verifies `airdropOf(token)` and `pairOf(token)` as passed, `activeStakeOf(AUTHORS) == AUTHORS_SUPPLY`, a staking balance of `TOTAL_SUPPLY − POOL_SUPPLY_CAP` and its own balance of `POOL_SUPPLY_CAP`;
- enters `Funding`.

These checks prove that the contract answers the interface of section 7.1 and recorded the creators' stake, not how it behaves afterwards: the staking contract is `AUTHORS`' choice, and the invariants of section 2 hold for the ecosystem only as far as the contract named keeps them. The deployment contract knows nothing of a referral contract; whether the staking contract uses one is its own matter. No pool call passes before `setStaking`.

`setPoolAmounts(llgame, bnb)` sets the pool's target amounts and moves nothing: `llgame`, at most `POOL_SUPPLY_CAP`, to be paired with `bnb`. Until the first BNB arrives `AUTHORS` changes them freely, the pair holding no liquidity, and so fixes the launch price for the BNB rate of the day; afterwards neither may be set below what the pool was already supplied with.

The pool is supplied by BNB that `AUTHORS` sends to the contract in `Funding`, once the amounts are set; any other transfer reverts. Each transfer adds its BNB to `poolBnb()`, brings `poolLlgame()` up to `min(llgame, floor(llgame × poolBnb / bnb))`, never down, sends both additions to the pair and mints LP tokens to the deployment contract; the first one skims the pair's stray WBNB to `DEAD` beforehand. The pair is live from that first transfer on. Amounts changed afterwards change the LLGAME that later BNB brings, and move the pool's price only as far as that BNB carries it.

`close()` requires a supplied pool, sends the LP tokens to `DEAD`, funds the staking reserve with the unused rest of `POOL_SUPPLY_CAP` and enters `Closed`.

### 7.3 Abort

In `Funding`, `abort` removes the liquidity of the LP tokens held, funds the staking reserve with the LLGAME received and the LLGAME still held, unwraps the WBNB received, pays it to `AUTHORS`, the one account that supplied BNB, and enters `Aborted`. Before the first BNB there are no LP tokens: the abort then funds the reserve with the whole `POOL_SUPPLY_CAP` and recovers no BNB. The token and the staking contract, with its reserve and the creators' stake, remain as set.

### 7.4 Guarantees

| Property | Guarantee held |
|---|---|
| Token and `AUTHORS` immutable, supply split by constants | Once launched, the supply can reach only the staking contract or the pool; `AUTHORS` receives LLGAME only as the staker of the creators' stake |
| Every call `AUTHORS`' alone, none the publisher's | The key that signs the publication keeps no right over the launch; no third party can launch, name a staking contract, fund the pool or close |
| Staking linked when funded | The staking contract takes `AIRDROP`, the pair and the deployment contract from the call that funds its reserve, not from its own publication: they are the deployment contract's values by construction |
| Staking set once | The reserve and the creators' stake go to one contract, readable from `staking()` before any pool call; it cannot be replaced |
| Pool amounts only raised, LLGAME within `POOL_SUPPLY_CAP` | `AUTHORS` cannot take liquidity back short of an abort, nor put more than the cap into the pool; the launch price itself is `AUTHORS`' decision until the close |
| Canonical pair | Only the factory-computed pair is used, known from the publication on |
| LP tokens sent to `DEAD` at close | Liquidity is locked without a locker or owner; invariant 3 |
| States in one order | Each of `launch`, `setStaking`, `close` and `abort` passes once; nothing is accepted after `Closed` or `Aborted` |

After `Closed` or `Aborted` the deployment contract holds none of the launch's value and is inert. LLGAME sent to it directly, at any time, is an unsolicited donation with no withdrawal path: a close or an abort funds it to the staking reserve with the rest.

From `setStaking` on the creators' stake accrues a reward `AUTHORS` can claim, and the pair is open to anyone: liquidity or trades by a holder of that LLGAME change the pair's reserves beside the amounts the deployment contract supplied (`derived`).

## 8. Parameters

### 8.1 Fixed by the design

| Parameter | Value |
|---|---|
| `DECIMALS` | 9 |
| `TOTAL_SUPPLY` | 3.4 × 10^29 LLGAME, `3.4 × 10^38` base units, minted once |
| `POOL_SUPPLY_CAP` | 1,000,000 LLGAME (`1,000,000 × 10^9` base units), the most LLGAME the pool is supplied with |
| `AUTHORS_SUPPLY` | 500,000 LLGAME (`500,000 × 10^9` base units), predefined and not configurable |
| Creators' stake | `AUTHORS_SUPPLY` staked for 1080 days under the ordinary staking rules: 288% reward allocation and 20% referral budget |
| Referral budget | 20% of each ordinary stake amount |
| Referral shares | `(A / 10) >> (n−1)` base units per level |
| Referral binding | Written once on the account's own signature over its referrer, never closing a cycle; a plain token transfer binds nothing |
| Referral payout eligibility | At every level `n`, `balanceOf(upline) >= (1 << (n−1)) × 10^9` and `activeStakeOf(upline) >= (1 << (n−1)) × 10^9` base units (that is, `2^(n−1)` LLGAME each), applied separately, with no dependence on `A` |
| Referral walk end | A root, or the first level `n` with `share(n) ≤ gasCost(n)`; an ineligible upline is passed over |
| Referral gas refund | `gasCost(n) = floor(gas × min(tx.gasprice, MAX_GAS_PRICE) × bnbPrice)` for the gas measured since the previous charge, taken from the share of every level examined and paid to the payer in LLGAME |
| `MAX_GAS_PRICE` | 0.5 gwei, the highest gas price a referral gas refund is valued at |
| Referral gas refund allowance | `floor(A / 50)` per stake, a tenth of its referral budget |
| `PRICE_PERIOD` | 30 minutes, the shortest time between two settings of the reference price of BNB in LLGAME |
| `PRICE_GUARD_PERCENT` | 5: a current LLGAME price further below the reference is replaced by the reference, which follows it by a factor of 100/95 per setting |
| Staking term | 1080 days, the only term |
| Minimum ordinary stake principal | 72,000,000 base units. Applies to public `stake` / `stakeWithPermit` calls and delegated stake portions; internally created `AIRDROP` referral-remainder stakes are exempt |
| Reward rate | 288% of principal over the term |
| Reward release | Linear over the stake term, claimable by the staker as it accrues |
| Pool | PancakeSwap v2 LLGAME/WBNB pair; launch LP position sent to `DEAD` at close |
| Funding | BNB sent by `AUTHORS`, entering the pool with LLGAME in the proportion of the pool amounts `AUTHORS` set, until `AUTHORS` closes |
| Unpaid referral remainder | Any non-zero remainder is recorded immediately as an `AIRDROP` stake, with the 1080-day term, the ordinary reward and no referral budget |

### 8.2 Values fixed before publication

Every value in this table must be final before the contract that takes it is published: the token, `AUTHORS` and `AIRDROP` are passed to the deployment contract's constructor, which hands `AIRDROP` to the staking contract with its reserve, and nothing changes them afterwards. `AIRDROP` is distinct from every other excluded or DEX infrastructure address.

| Parameter | Meaning | Requirement |
|---|---|---|
| `AUTHORS` | Address that receives the creators' stake and alone calls the deployment contract | Non-zero; not in the staking contract's `excluded` set; must be an EOA or a smart wallet able to call the staking contract and every call of the deployment contract |
| `AIRDROP` | Special address for referral-remainder stakes | Non-zero; distinct from `AUTHORS`, the token, pair, staking contract, deployment contract, `DEAD`, factory and WBNB; included in `excluded`; must be an EOA or a smart wallet able to call the staking contract |
| Token | Address of the published LLGAME token | Holds the token's code; its whole supply is at one holder, whose permit or approval `AUTHORS` has for the launch |

## 9. Reserve accounting

The staking reserve is finite and is the source of every staking reward, referral payment and `AIRDROP` stake. The contract allocates the full cost of each stake when that stake is opened. It never promises a reward or referral amount that has not already been reserved. In the formulas below, `floor(x)` denotes integer division with the same rounding used by the staking contract.

### 9.1 Cost of an ordinary stake

For a stake of principal `A`, the principal itself is transferred by the payer and is not taken from the unallocated reserve. The reserve funds the reward allocation, the 20% referral budget and the reward of the `AIRDROP` stake made of its unpaid remainder:

| Reward allocation | Referral allocation | `AIRDROP` stake reward | Total reserve allocation `c × A` |
|---:|---:|---:|---:|
| 288% of `A` | 20% of `A` | up to 57.6% of `A` | 3.08 to 3.656 × `A` |

The referral allocation is fully accounted for at stake time. Shares paid to eligible uplines leave the staking contract immediately. The unpaid remainder is not free reserve: it is a liability recorded as an `AIRDROP` stake, whose reward is allocated in addition. It therefore remains part of the allocated 20% and cannot be counted again as available reserve.

### 9.2 Reserve after the staking contract is set

When the staking contract is set, the deployment contract funds it with `TOTAL_SUPPLY − POOL_SUPPLY_CAP − AUTHORS_SUPPLY`, keeps `POOL_SUPPLY_CAP` for the pool and opens the creators' stake for `AUTHORS`.

The creators' stake follows the ordinary 1080-day rules. Since `AUTHORS` is unbound when its stake opens, it has no upline; the full 100,000 LLGAME referral allocation therefore becomes an `AIRDROP` stake with its own 288,000 LLGAME reward. The creators' stake also allocates its 1,440,000 LLGAME reward. The unallocated reserve is then:

```
R_launch = TOTAL_SUPPLY − POOL_SUPPLY_CAP − AUTHORS_SUPPLY
          − floor(288 × AUTHORS_SUPPLY / 100)
          − floor(20 × AUTHORS_SUPPLY / 100)
          − floor(288 × floor(20 × AUTHORS_SUPPLY / 100) / 100)

         = 3.4 × 10^29 − 3,328,000 LLGAME
```

The subtraction comprises 1,000,000 LLGAME held for the pool, whose unused part returns to the reserve at close, and 500,000 LLGAME principal, 1,440,000 LLGAME reward and 100,000 LLGAME referral allocation for the creators' stake, and 288,000 LLGAME reward of the resulting `AIRDROP` stake. The result is positive and exact with the stated integer-floor operations. The staking contract's token balance at that moment is `TOTAL_SUPPLY − POOL_SUPPLY_CAP`; that balance is divided between the creators' principal and reward, the `AIRDROP` stake's principal and reward, and `R_launch`.

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
