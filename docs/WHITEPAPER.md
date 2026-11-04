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

- `AUTHORS_SUPPLY = 250,000` LLGAME - creators' stake, locked for 1080 days: an ordinary stake opened for the fixed `AUTHORS` address inside the activation transaction;
- 1,000,000 LLGAME paired with BNB in a launch liquidity pool whose liquidity provider (LP) tokens are sent to `DEAD` when funding closes;
- the remaining supply is initially held by the staking contract. After the creators' stake is opened, the unallocated part becomes the reserve that funds subsequent staking rewards and referral allocations.

Holders receive value through:

- staking for 180, 360 or 1080 days, with rewards accruing over time and claimable as they accrue;
- the referral program: a budget of each stake, paid inside the stake call to the staker's uplines;
- gamified airdrops: any non-zero unpaid remainder of that budget is recorded immediately as a stake for the special `AIRDROP` address, making the accumulated airdrop budget transparent and predictable on chain;

The operational ecosystem consists of two locked contracts and a DEX pair, launched and funded by a separate deployment contract. Two separately controlled addresses participate in its economics: `AUTHORS`, the ordinary beneficiary of the creators' stake, and `AIRDROP`, the special address for accumulated referral remainders.:

| Part | Role | Administration |
|---|---|---|
| Token (`LLGAME`) | OpenZeppelin v5 `ERC20`, `ERC20Burnable`, `ERC20Permit`, 9 decimals, no access control module; its only addition is an `_update` override reporting to the staking contract every positive transfer to an account other than the staking contract that held no LLGAME | None: locked at launch |
| Pool | PancakeSwap v2 LLGAME/WBNB pair, launch LP position sent to `DEAD` at close | None: the pair is DEX code, its protocol `feeTo` share excepted |
| Staking | Holds the reserve, the ecosystem-account set and the referral forest; binds each account to the sender of its first LLGAME, its first stake's payer or its delegating staker; takes stakes paid by their caller for a beneficiary, splits a part of a stake to a delegate at its staker's request, allocates rewards, pays referral shares to eligible uplines, records any non-zero unpaid referral remainder as an `AIRDROP` stake inside the stake call | None: locked at launch |
| Deployment contract | Launcher published without attached BNB and with immutable parameters; creates the ecosystem on its first funding round and closes when funding reaches at least `POOL_BNB` | No owner, setter or withdrawal function; `PUBLISHER` may abort before close |
| `AUTHORS` address | Fixed beneficiary of the creators' stake; an ordinary account with no exclusion or contract privilege | Its key or multisig policy controls only that account; it has no contract privilege |
| `AIRDROP` address | Special address whose stakes accumulate unpaid referral-budget remainders for later airdrops; cannot participate in the referral program as referrer or referred account | Its key or multisig policy claims and withdraws under the common staking rules |

### 1.1 Terms

| Term | Meaning |
|---|---|
| Locked contract | A contract deployed final: no owner, admin role, settable parameter, pause, upgrade or administrator withdrawal; every table and threshold is a constant or immutable. Staking principal and rewards remain withdrawable only through the fixed user-facing rules |
| Ecosystem account | A fixed system address excluded from referral binding in either direction: the launch pair, staking contract, deployment contract, dead address and `AIRDROP` |
| Dead address | `0x000000000000000000000000000000000000dEaD`, which no key controls |
| Staker | The beneficiary of a stake: the account whose active stake it is, whose reward ledger it feeds, to which the principal returns and whose uplines the stake's referral walk pays |
| Payer | The caller of `stake`, whose LLGAME funds the stake; the staker itself in the common case |
| Stake reserve | LLGAME in the staking contract not allocated to any stake |
| Referral budget | 20% of each ordinary stake's amount, taken from the stake reserve at stake time and paid recursively to eligible uplines by the stake-sized cap formula; any non-zero unpaid remainder is recorded as an `AIRDROP` stake |
| Operator | The party running the game; it cannot change the locked contracts or their payout rules |
| Deployment contract | A launcher published without attached BNB and with immutable launch parameters; its first funding round creates the ecosystem, and the round bringing the total to at least `POOL_BNB` closes the funding |
| Activation transaction | The first funding round: a permissionless BNB transfer to the deployment contract that creates the token, staking contract and pool, funds liquidity and opens the creators' stake |
| Funding | From the activation transaction until close or abort (section 7) |
| `derived` | Marks a statement that follows from the rules stated elsewhere, not a separate rule |

## 2. Invariants

Every part of the ecosystem is bound by the following; the requirements of sections 3 to 7 are consequences of these invariants.

1. **Locked at launch.** The token and the staking contract are locked contracts. No proxy, upgradeable part or contract-administration signer exists in the token or staking contracts; the deployment contract's only privileged call is `PUBLISHER`'s abort during funding.
2. **No mint after creation.** The token's constructor mints the whole supply and no function can mint again. Every staking reward and referral allocation is funded from the staking contract's pre-minted holdings.
3. **No administration of value.** No key can move LLGAME out of a locked contract except through its fixed rules: staking principal withdrawal, reward claim, and referral payout. From close, the launch LP position is irretrievably held at `DEAD`; during funding only an abort removes its liquidity, refunding funders; PancakeSwap may separately mint protocol-fee LP shares to its configured `feeTo` address under the DEX's own rules, as described in section 4. `AIRDROP` claims and withdraws under the common rules and has no administrative right over any contract.
4. **Fixed conditions.** The staking terms and rates, the referral budget and referral formula, the fixed `AUTHORS` beneficiary, the `AIRDROP` address and the fixed ecosystem-account exclusion set are immutable or constants of the contracts that use them.
5. **Solvent by construction.** Nothing is owed beyond what is allocated: a stake reverts when the stake reserve cannot cover its reward, its referral budget and the reward of its `AIRDROP` stake; the referral walk pays eligible shares within the stake's referral budget in the same call, and any unpaid part is recorded as an `AIRDROP` stake. The sum of the staking contract's accounted ledgers—principal still held, allocated rewards not yet claimed and unallocated reserve—never exceeds its LLGAME balance. A direct token transfer to the staking contract outside `stake` is an unsolicited donation: it is not credited to the reserve or any stake ledger and has no withdrawal path.
6. **Deterministic binding and payouts.** The staking contract creates a referral binding only when the sender of a recipient's first LLGAME receipt (or the payer for an unseen stake beneficiary, or the delegating staker for an unseen delegate) has `activeStakeOf(sender) > 0` and neither endpoint is excluded. Referral shares are paid to uplines whose cap meets the level's threshold and whose liquid balance and `activeStakeOf` are both positive. No off-chain party can alter either calculation. Distribution of matured funds withdrawn by `AIRDROP` is an off-chain activity and is not controlled by the contracts.
7. **No transfer tax.** The token's `_update` hook reports receipts to the staking contract but does not deduct a fee or redirect any part of an ordinary transfer.

## 3. Token

- Name Legacy Life Game, symbol LLGAME, 9 decimals, total supply `TOTAL_SUPPLY = 3.4 × 10^29` LLGAME, that is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38`. Every stored token balance and token-denominated stake or reserve ledger is bounded by total supply and fits a `uint128`; intermediate calculations and referral-cap thresholds use `uint256` (section 9.4).
- The constructor mints the whole `TOTAL_SUPPLY` to its deployer, the deployment contract. The token emits no further mint ever. All LLGAME amounts passed to token and staking functions are expressed in base units; `POOL_BNB` is expressed in wei. The prose expresses token balances in LLGAME (9 decimals).
- `_update` calls `STAKING.noteReceipt(from, to)` on every positive transfer to an account that held no LLGAME before it, except mints, burns and transfers to the staking contract; it changes no amount.
- `ERC20Burnable` lets any holder burn its own tokens; nothing in the ecosystem requires a burn.
- `ERC20Permit` lets a holder approve the staking contract by signature, so a stake is one transaction.
- The token inherits no access control module: there is no owner, no role and no function that would need one.

### 3.1 Interface

```solidity
// Token: the interface beyond OpenZeppelin ERC20, ERC20Burnable and ERC20Permit
function STAKING() external view returns (address);   // immutable, predicted at deployment
```

## 4. Pool

The launch pool is the canonical PancakeSwap v2 LLGAME/WBNB pair. At close it holds:

- 1,000,000 LLGAME and at least `POOL_BNB` wei of BNB as WBNB. `POOL_BNB` is fixed before publication and may be selected to target approximately $10,000 at a reference BNB/USD quote. The actual USD value depends on the BNB/USD rate at close.
- The 1,000,000 LLGAME are one part in 3.4 × 10^23 of the total supply. The pool is the initial DEX source of freely tradable LLGAME; the creators' principal is locked in staking, while reserve distributions occur only through the staking rules. Tokens subsequently circulate through ordinary transfers, staking payouts, referral payouts and any off-chain airdrops funded by matured `AIRDROP` withdrawals.
- The launch LP tokens are held at the dead address, so that position is locked without a locker contract or owner. Swap fees remain in the pair's reserves; the PancakeSwap protocol may separately mint `feeTo` LP shares under its own factory-controlled fee mechanism.

## 5. Staking

A holder stakes an amount `A` for a term of 180, 360 or 1080 days, with `stake(amount, term, beneficiary)`. The caller is the payer: the amount is pulled from its balance. The beneficiary is the staker: the stake belongs to that account. In the common case, the caller names itself, but anyone can open a stake for anyone else. The staking contract allocates at stake time, out of the stake reserve, everything the stake will ever cost; a stake that the reserve cannot cover reverts. Its constructor initializes the unallocated reserve from `TOKEN.balanceOf(address(this))`. Later direct LLGAME transfers to the staking address are not treated as reserve deposits; without an explicit stake call they remain unaccounted surplus and cannot be withdrawn.

Every public `stake` or `stakeWithPermit` call must meet the term-specific minimum principal:

- **0.1152 LLGAME** for 180 days,
- **0.096 LLGAME** for 360 days,
-  **0.072 LLGAME** for 1080 days.

 These limits target an average accrued reward of at least one base unit per average BSC block, using the documented 0.45-second average block interval. The minimum applies to public stake calls; the internally created referral-remainder `AIRDROP` stake described in section 5.2 is exempt.

| Allocation at stake time | Amount | Destination |
|---|---|---|
| Reward | 30%, 72% or 288% of `A` for the three terms, that is 5%, 6% or 8% of `A` per 30 days, rising with the term | The staker's reward ledger, released linearly over the term |
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
    uint64  start;      // timestamp of the stake block; the reward accrues from it to start + term
    uint32  term;       // 180, 360 or 1080, in days
}

event Staked(uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount, uint32 term);
    // also for an AIRDROP remainder stake: staker AIRDROP, payer the staking contract
event StakeDelegated(uint256 indexed stakeId, uint256 indexed delegatedStakeId, address indexed delegate, address staker, uint256 amount);
event ReferralBound(address indexed account, address indexed referrer);   // a binding is written

function TOKEN() external view returns (address);
function AIRDROP() external view returns (address);
function excluded(address account) external view returns (bool);         // the fixed ecosystem-account set

function stake(uint256 amount, uint32 term, address beneficiary) external returns (uint256 stakeId);
function stakeWithPermit(uint256 amount, uint32 term, address beneficiary,
                         uint256 deadline, uint8 v, bytes32 r, bytes32 s) external returns (uint256 stakeId);
function delegateStake(uint256 stakeId, uint256 amount, address delegateAddress)
    external returns (uint256 delegatedStakeId);   // the staker only (section 5.3)
function claim(uint256 stakeId) external;      // the staker only: the accrued, unclaimed reward
function withdraw(uint256 stakeId) external;   // the staker only, after the term: the principal and the unclaimed reward
function noteReceipt(address from, address to) external;   // TOKEN only (section 6)

function stakeInfo(uint256 stakeId) external view returns (StakeInfo memory);
function claimable(uint256 stakeId) external view returns (uint256);   // accrued minus claimed, never negative
function activeStakeOf(address account) external view returns (uint256);
function reserve() external view returns (uint256);                    // the unallocated stake reserve
function seen(address account) external view returns (bool);
function referrerOf(address account) external view returns (address); // zero for a root
```

`stakeWithPermit` signs the payer's approval with `ERC20Permit` and does what `stake` does in one transaction. Only the staker claims and withdraws: the payer has no right over the stake once it is open. Its staker may delegate all or part of it (section 5.3). `claim` and `withdraw` emit no event of their own: the token's `Transfer` from the staking contract records the amount paid, and `stakeInfo` the state of the stake. `referrerOf` and `seen` together tell the game server the whole referral forest: a seen account with a zero `referrerOf` is a root, and `ReferralBound` lets it be indexed without reading every transfer.

### 5.2 Stake procedure

`stake(amount, term, beneficiary)` runs these steps in this order; any failing check reverts the whole call:

1. Check that `term` is in {180, 360, 1080} days, `amount` is at least the corresponding minimum principal in section 8.1, and `beneficiary` is neither the zero address nor any ecosystem account other than `AIRDROP`. The caller must also choose a beneficiary able to call `claim` and `withdraw`; the contract cannot generically verify that an arbitrary smart wallet supports those calls.
2. Allocate the reward and the referral budget from the stake reserve; revert when the reserve is short.
3. Write the ordinary stake under the beneficiary: `stakeId`, the amount, the term, the stake block and the allocated reward; add the amount to `activeStakeOf[beneficiary]`. This stake ledger and the reserve allocation are recorded before the principal transfer.
4. Pull `amount` from the payer: `transferFrom(msg.sender, staking, amount)`. The recipient is an ecosystem account, so the transfer does not create a referral binding.
5. When the beneficiary has never been seen, apply the binding rule of section 6 with the payer as sender: the beneficiary is marked seen, and bound to the payer only when neither address is in `excluded` and the payer already has `activeStakeOf(payer) > 0`. If any condition fails—including a payer with no ordinary stake, the deployment contract or `AIRDROP`—the beneficiary becomes an unbound root. An account already seen keeps its existing binding or root status.
6. Walk the beneficiary's uplines recursively and pay each eligible upline its level share, then, if the unpaid part of the 20% referral budget is non-zero, record it immediately as an `AIRDROP` stake (section 6), allocating its ordinary reward from the stake reserve; revert when the reserve is short.
7. Emit `Staked` with the ordinary staker and payer. If an `AIRDROP` stake is recorded by this call, emit `Staked` for it as well, with its stake ID, `AIRDROP` as the staker, the staking contract as the payer, the amount and the originating stake's term. This records an internal reserve allocation, not a second payer transfer, and it follows the originating stake's `Staked` in the same transaction.

The binding of step 5 keeps the referral forest acyclic: a binding is written only to a payer distinct from the beneficiary, and that payer must already have an ordinary stake principal (`activeStakeOf(payer) > 0`). The payer necessarily acquired LLGAME before opening that earlier stake and was therefore already seen before the new beneficiary is bound. Every new edge points to an account already seen (`derived`). A beneficiary the token has already seen, whether bound or a root, keeps its existing status whoever pays its stake.

### 5.3 Stake delegation

`delegateStake(stakeId, amount, delegateAddress)` splits an ordinary stake and hands the split part to another account. It runs these steps in this order; any failing check reverts the whole call:

1. Check that the caller is the stake's staker, its principal is not withdrawn, `amount` is at least the minimum principal for the stake's term, and `amount ≤ principal`. If `amount < principal`, the principal remaining in the original stake must also be at least that minimum. Check also that `delegateAddress` is neither the zero address, the caller nor any ecosystem account other than `AIRDROP`.
2. Pay the caller the stake's accrued, unclaimed reward, as `claim` does, so that the reward accrued before delegation stays with the caller.
3. When `delegateAddress` has never been seen, mark it seen and, unless the caller is `AIRDROP`, bind it to the caller as its referrer. The caller holds the stake being split, so `activeStakeOf(caller) > 0` holds. A delegate already seen keeps its existing binding or root status.
4. Write a new ordinary stake under the delegate with principal `amount`, the original term and stake block, reward allocation `floor(reward × amount / principal)` and claimed amount `floor(claimed × amount / principal)`; the original stake keeps the remainders of principal, reward and claimed amount. Move `amount` from `activeStakeOf[caller]` to `activeStakeOf[delegate]`.
5. Emit `StakeDelegated`.

Delegation moves no LLGAME and touches no reserve: no reward or referral budget is allocated, no referral walk runs and no `AIRDROP` stake is recorded. Both parts keep the original unlock date. The delegated stake is ordinary in every other respect: only the delegate claims and withdraws it, and the delegate may delegate a part of it again. The new binding keeps the referral forest acyclic, since the caller, a staker, was seen before the delegate (`derived`).

## 6. Referral program

The referral program is funded inside the stake call from a budget equal to 20% of the stake amount `A`, taken from the stake reserve. An LLGAME transfer runs no recipient code, so an upline cannot revert a stake or reenter the contract through token receipt. The ordinary stake and reserve allocation are recorded before the principal transfer (section 5.2); the `AIRDROP` stake is recorded once the referral shares have been determined. The uplines' receipts come from the staking contract, an ecosystem account, so they do not create referral bindings.

The staking contract keeps `seen`, `referrerOf` and the immutable ecosystem-account set `excluded`, and decides each account's referral status once, when the account is first seen; no function rewrites a binding. `noteReceipt(from, to)`, callable by the token alone, reports a receipt (section 3) and reverts for no other reason; it also runs inside the staking contract's own payouts, so no reentrancy guard covers it. An account not yet seen is marked seen on its first LLGAME receipt, and bound to the sender only when that sender already has an ordinary stake principal recorded (`activeStakeOf(sender) > 0`) and neither endpoint is excluded; an account already seen is left unchanged. When a stake is opened for an unseen beneficiary, the same test applies to the payer (section 5.2), and when a stake part is delegated to an unseen account, to the delegating staker (section 5.3). A first receipt from a pool or another sender without an ordinary stake leaves the recipient unbound as a root. The referral graph is a forest of these immutable bindings, with new roots appearing whenever a recipient's first sender does not qualify. `AIRDROP` is outside this forest under all circumstances: it cannot be a referrer, cannot be referred and is never paid a referral share.

For a stake of amount `A`, the staking contract walks from the staker's direct upline upward. An upline is eligible when its cap meets the level's threshold and both its liquid balance and its `activeStakeOf` are positive. The halving share schedule keeps the total payout within the 20% budget, while the doubling cap requirement limits eligibility at each successive level. At level `n` (starting at 1):

- `share(n) = (A / 10) >> (n − 1)`, that is `floor(A / (10 × 2^(n − 1)))`;
- `requiredCap(n) = A << (n − 1)`, that is `A × 2^(n − 1)`;
- `cap(account) = token.balanceOf(account) + activeStakeOf(account)`.

The number of levels has organic math limit: the walk ends at the first of:

- a root: the current account has no referrer;
- a zero share: `share` reaches zero once `2^(n − 1) > A / 10`.
- an ineligible upline.

Eligibility is evaluated after the stake principal has been pulled from the payer and the beneficiary's stake has been recorded; when the payer is the direct upline, the amount just transferred into the new stake does not count as its liquid balance. The cap includes both liquid account balance and the account's stake principal still held by the staking contract; that principal is not included in `balanceOf(account)`. `activeStakeOf` includes matured stakes whose principal has not yet been withdrawn and is decremented when principal is withdrawn. The sum of the individually rounded shares cannot exceed the rounded 20% referral budget.

The referral budget is `floor(20 × A / 100)` base units. Each level's share is rounded down in base units and calculated from the original stake amount, not from the previous upline's payout. With `m = floor(A / 10)`, the shares of a chain that pays every level until the share reaches zero sum to `2m − popcount(m)`, the number of one bits of `m` subtracted; this is at most `2m − 1` and never exceeds the budget `floor(A / 5) ≥ 2m` (`derived`). A shorter chain pays less. The remainder is therefore at least one base unit whenever `m > 0`. Any non-zero budget remainder is immediately recorded as an `AIRDROP` stake in the same stake call, using the originating stake's term, with the ordinary reward and no referral budget. If the remainder rounds to zero base units, no `AIRDROP` stake is created. The contract pays no more than `20% × A` (this holds automatically by the math definition).

## 7. Deployment contract

The deployment contract launches and funds the ecosystem. Its constructor fixes the launch parameters as immutables and records its sender as `PUBLISHER`; `AUTHORS_SUPPLY` is a predefined constant. It has no owner, setter or upgrade path; its only privileged call is `PUBLISHER`'s abort during funding.

### 7.1 Interface

```solidity
// Deployment contract — interface sketch
contract Deployment {
    uint256 private constant AUTHORS_SUPPLY = 250_000 * 10 ** 9;

    enum State { NotLaunched, Funding, Closed, Aborted }

    // Non-payable; the sender becomes PUBLISHER.
    constructor(address authors_, address airdrop_, uint256 poolBnb_);

    // A funding round: any sender, msg.value > 0, in NotLaunched or Funding.
    receive() external payable;

    function abort() external;    // PUBLISHER only, in Funding
    function refund() external;   // a funder, in Aborted, once

    function PUBLISHER() external view returns (address);
    function state() external view returns (State);
    function funded() external view returns (uint256);                   // BNB of all rounds
    function depositOf(address funder) external view returns (uint256);
}
```

### 7.2 Funding

A funding round is a native BNB transfer in state `NotLaunched` or `Funding` with `msg.value > 0`; any other transfer reverts. Each round adds `msg.value` to `funded()` and to the sender's `depositOf`.

The first round is the activation transaction. It:
- deploys the token, which mints the full supply to the deployment contract and fixes `STAKING`;
- transfers `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract's predicted address;
- deploys the staking contract with its reserve present and `excluded` fixed;
- resolves the canonical pair, creating it if absent, and skims its WBNB balance to `DEAD`;
- opens the creators' 1080-day stake for `AUTHORS`;
- verifies the total supply, the balance split, the creators' stake and a deployment-contract token balance of `POOL_SUPPLY`;
- enters `Funding`.

Every round, the first included, adds its BNB to the pool with LLGAME in proportion to it, `POOL_SUPPLY` per `POOL_BNB`, minting LP tokens to the deployment contract. The deployment contract holds the rest of `POOL_SUPPLY` until full funding.

The round that brings `funded()` to at least `POOL_BNB` adds the rest of `POOL_SUPPLY`, sends the launch LP tokens to `DEAD` and enters `Closed`. A first round of at least `POOL_BNB` launches and closes in one transaction.

### 7.3 Abort

In `Funding`, `abort` removes the liquidity of the launch LP tokens, burns the LLGAME received and the LLGAME still held, unwraps the WBNB received as `withdrawn` and enters `Aborted`. Each funder's `refund` pays `floor(withdrawn × depositOf(funder) / funded())` once. The token and staking contract remain as launched.

### 7.4 Guarantees

| Property | Guarantee held |
|---|---|
| Published separately without attached BNB | The launch configuration can be inspected before any funding |
| Every launch value a constant or immutable | Nobody can change `AUTHORS`, `AIRDROP`, `POOL_BNB` or any economic parameter after publication |
| Round bounds and states | The launch happens once; every round enters the pool; funding closes at `POOL_BNB` or more; nothing is accepted after `Closed` or `Aborted`; `abort` is impossible after `Closed` |
| Nonce-predicted `CREATE` addresses | The token's `STAKING` and the staking contract's `TOKEN` and `excluded` set are correct by construction |
| Canonical pair | Only the factory-computed pair is used |
| LP tokens sent to `DEAD` at close | Liquidity is locked without a locker or owner; invariant 3 |
| Creators' stake opened in the activation transaction | Locked for 1080 days by the same rules as every stake |

After `Closed` the deployment contract holds no value and is inert. After `Aborted` it holds only BNB not yet refunded.

## 8. Parameters

### 8.1 Fixed by the design

| Parameter | Value |
|---|---|
| `DECIMALS` | 9 |
| `TOTAL_SUPPLY` | 3.4 × 10^29 LLGAME, `3.4 × 10^38` base units, minted once |
| `POOL_SUPPLY` | 1,000,000 LLGAME (1,000,000 × 10^9 base units in Solidity) |
| `AUTHORS_SUPPLY` | 250,000 LLGAME (`250,000 × 10^9` base units), predefined and not configurable |
| Creators' stake | `AUTHORS_SUPPLY` staked for 1080 days under the ordinary staking rules: 288% reward allocation and 20% referral budget |
| Referral budget | 20% of each ordinary stake amount |
| Referral shares | `(A / 10) >> (n−1)` base units per level |
| Referral binding | On first receipt, the sender must have `activeStakeOf(sender) > 0` and neither endpoint may be in `excluded`; the same test applies to the payer when binding an unseen stake beneficiary |
| Referral payout eligibility | `balanceOf(upline) + activeStakeOf(upline) >= A << (n−1)`, `balanceOf(upline) > 0` and `activeStakeOf(upline) > 0` at every level `n` |
| Staking terms | 180, 360 and 1080 days |
| Minimum ordinary stake principal | 115,200,000 base units (180 days); 96,000,000 base units (360 days); 72,000,000 base units (1080 days). Applies to public `stake` / `stakeWithPermit` calls and delegated stake portions; internally created `AIRDROP` referral-remainder stakes are exempt |
| Reward rates | 30%, 72% and 288% of principal over the respective terms |
| Reward release | Linear over the stake term, claimable by the staker as it accrues |
| Pool | PancakeSwap v2 LLGAME/WBNB pair; launch LP position sent to `DEAD` at close |
| Funding | Rounds totalling at least `POOL_BNB` wei, each entering the pool with LLGAME in proportion to its BNB, `POOL_SUPPLY` per `POOL_BNB` |
| Unpaid referral remainder | Any non-zero remainder is recorded immediately as an `AIRDROP` stake, with the originating stake's term, the ordinary reward and no referral budget |

### 8.2 Values fixed before publication

Every value in this table must be final before the deployment contract is published. No value is supplied by the activation sender or changed after publication. `AIRDROP` is distinct from every other excluded or DEX infrastructure address.

| Parameter | Meaning | Requirement |
|---|---|---|
| `AUTHORS` | Ordinary address that receives the creators' stake | Non-zero; not in the staking contract's `excluded` set; must be an EOA or a smart wallet able to call the staking contract |
| `AIRDROP` | Special address for referral-remainder stakes | Non-zero; distinct from `AUTHORS`, the token, pair, staking contract, deployment contract, `DEAD`, factory and WBNB; included in `excluded`; must be an EOA or a smart wallet able to call the staking contract |
| `POOL_BNB` | Minimum total BNB in wei of all funding rounds | Fixed positive integer amount |

## 9. Reserve accounting

The staking reserve is finite and is the source of every staking reward, referral payment and `AIRDROP` stake. The contract allocates the full cost of each stake when that stake is opened. It never promises a reward or referral amount that has not already been reserved. In the formulas below, `floor(x)` denotes integer division with the same rounding used by the staking contract.

### 9.1 Cost of an ordinary stake

For a stake of principal `A`, the principal itself is transferred by the payer and is not taken from the unallocated reserve. The reserve funds the reward allocation, the 20% referral budget and the reward of the `AIRDROP` stake made of its unpaid remainder:

| Term | Reward allocation | Referral allocation | `AIRDROP` stake reward | Total reserve allocation `c × A` |
|---|---:|---:|---:|---:|
| 180 days | 30% of `A` | 20% of `A` | up to 6% of `A` | 0.50 to 0.56 × `A` |
| 360 days | 72% of `A` | 20% of `A` | up to 14.4% of `A` | 0.92 to 1.064 × `A` |
| 1080 days | 288% of `A` | 20% of `A` | up to 57.6% of `A` | 3.08 to 3.656 × `A` |

The referral allocation is fully accounted for at stake time. Shares paid to eligible uplines leave the staking contract immediately. The unpaid remainder is not free reserve: it is a liability recorded as an `AIRDROP` stake, whose reward is allocated in addition. It therefore remains part of the allocated 20% and cannot be counted again as available reserve.

### 9.2 Reserve immediately after activation

The token constructor mints the whole supply to the deployment contract, which transfers `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract. During activation, the deployment contract keeps `POOL_SUPPLY` for the pool and opens the creators' stake for `AUTHORS`.

The creators' stake follows the ordinary 1080-day rules. Since `AUTHORS` begins as an unbound root, it has no upline at activation; the full 50,000 LLGAME referral allocation therefore becomes an `AIRDROP` stake with its own 144,000 LLGAME reward. The creators' stake also allocates its 720,000 LLGAME reward. The unallocated reserve after activation is consequently:

```
R_launch = TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY
          − floor(288 × AUTHORS_SUPPLY / 100)
          − floor(20 × AUTHORS_SUPPLY / 100)
          − floor(288 × floor(20 × AUTHORS_SUPPLY / 100) / 100)

         = 3.4 × 10^29 − 2,164,000 LLGAME
```

The subtraction comprises 1,000,000 LLGAME for the pool and 250,000 LLGAME principal, 720,000 LLGAME reward and 50,000 LLGAME referral allocation for the creators' stake, and 144,000 LLGAME reward of the resulting `AIRDROP` stake. The result is positive and exact with the stated integer-floor operations; it assumes the deployment transaction completes successfully. The staking contract's token balance immediately after activation is `TOTAL_SUPPLY − POOL_SUPPLY`; that balance is divided between the creators' principal and reward, the `AIRDROP` stake's principal and reward, and `R_launch`.

### 9.3 Capacity and duration

For a new ordinary stake of amount `A`, the unallocated reserve must cover up to `0.56 × A`, `1.064 × A` or `3.656 × A`, depending on the selected term. Ignoring integer rounding, the maximum cumulative principal amount that can be opened against a reserve `R` is therefore bounded by:

- `R / 3.08` if every new stake uses the 1080-day term;
- `R / 0.92` if every new stake uses the 360-day term;
- `R / 0.50` if every new stake uses the 180-day term.

These are cumulative stake-volume bounds under the stated single-term assumptions, not simultaneous-stake limits or calendar-lifetime guarantees. The actual duration depends primarily on aggregate new stake volume and the mix of selected terms. Referral eligibility changes the destination of the fixed referral allocation, not its reserve cost; restaking rewards or withdrawn principal can increase later stake volume, while principal withdrawals themselves do not replenish the reserve. The market price and available DEX liquidity may influence demand, but they do not mathematically guarantee a minimum reserve lifetime. The contract's enforceable guarantee is narrower and stronger: every accepted stake is fully allocated at entry, and a new stake reverts if its full reward and referral allocation cannot be covered.

### 9.4 Sizing the supply

The supply is sized to fit the staking ledger's packed amount field. ERC-20 balances are `uint256`, but each stored token-denominated stake amount, principal, reward allocation and reserve amount is bounded by total supply and fits a `uint128`. Computed referral-cap thresholds and multiplication intermediates use `uint256` and are not packed into that field. With 9 decimals, `3.4 × 10^29` LLGAME is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38` and leaving approximately 0.08% of the range unused.

| Decimals | Supply | Base units | Width |
|---|---|---|---|
| 9 | 3.4 × 10^29 LLGAME | 3.4 × 10^38 | 128 bits |

At the intended reference price of about $0.01 per LLGAME at close, the smallest unit is worth a billionth of a cent. The actual USD price depends on the BNB/USD rate at close.


## Sources

1. OpenZeppelin Contracts 5.x, ERC20 API. https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
2. EIP-161: state trie clearing, contract nonce starting at one. https://eips.ethereum.org/EIPS/eip-161
3. PancakeSwap developer docs, v2 Factory and Addresses. https://developer.pancakeswap.finance/contracts/v2/addresses
4. `PancakePair` source: `MINIMUM_LIQUIDITY`, `mint(to)`, `skim(to)` and reserve accounting. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakePair.sol
5. `PancakeFactory` source: `createPair` uses CREATE2 and does not require either token address to contain token code. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakeFactory.sol
6. Solidity documentation: `receive()` handles empty-calldata transfers; `send()` and `transfer()` forward only the 2,300-gas stipend. https://docs.solidity.org/en/latest/contracts.html
7. BNB Smart Chain documentation, Introduction: 0.45-second average mainnet block interval. https://docs.bnbchain.org/bnb-smart-chain/introduction/
