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
- 1,000,000 LLGAME paired with BNB in a launch liquidity pool whose liquidity provider (LP) tokens are sent to `DEAD`;
- the remaining supply is initially held by the staking contract. After the creators' stake is opened, the unallocated part becomes the reserve that funds subsequent staking rewards and referral allocations.

Holders receive value through:

- staking for 180, 360 or 1080 days, with rewards accruing over time and claimable as they accrue;
- the referral program: a budget of each stake, paid inside the stake call to the staker's uplines;
- gamified airdrops: any non-zero unpaid remainder of that budget is recorded immediately as a dedicated stake principal for the special `AIRDROP` address, making the accumulated airdrop budget transparent and predictable on chain;

The operational ecosystem consists of two locked contracts and a DEX pair, launched by a separate one-shot deployment contract. Two separately controlled addresses participate in its economics: `AUTHORS`, the ordinary beneficiary of the creators' stake, and `AIRDROP`, the special address for accumulated referral remainders. The deployment contract's address is included in the staking contract's `excluded` set, but the launcher has no role after activation. `AUTHORS` is not an ecosystem account and is not included in `excluded`:

| Part | Role | Administration |
|---|---|---|
| Token (`LLGAME`) | OpenZeppelin v5 `ERC20`, `ERC20Burnable`, `ERC20Permit`, 9 decimals, no access control module; its only addition is an `_update` override reporting to the staking contract every positive transfer to an account that held no LLGAME | None: locked at launch |
| Pool | PancakeSwap v2 LLGAME/WBNB pair, activation LP position sent to `DEAD` | None: the pair is DEX code, its protocol `feeTo` share excepted |
| Staking | Holds the reserve, the ecosystem-account set and the referral forest; binds each account to the sender of its first LLGAME, its first stake's payer or its delegating staker; takes stakes paid by their caller for a beneficiary, splits a part of a stake to a delegate at its staker's request, allocates rewards, pays referral shares to eligible uplines, records any non-zero unpaid referral remainder as dedicated `AIRDROP` stake principal inside the stake call | None: locked at launch |
| Deployment contract | One-shot launcher published without attached BNB and with immutable parameters; creates and funds the ecosystem only when it receives exactly `POOL_BNB` | No owner, setter or withdrawal function; permanently one-shot |
| `AUTHORS` address | Fixed beneficiary of the creators' stake; an ordinary account with no exclusion or contract privilege | Its key or multisig policy controls only that account; it has no contract privilege |
| `AIRDROP` address | Special address whose dedicated stake principal accumulates unpaid referral-budget remainders for later airdrops; cannot participate in the referral program as referrer or referred account | Its key or multisig policy can withdraw matured principal under the fixed staking rules |

### 1.1 Terms

| Term | Meaning |
|---|---|
| Locked contract | A contract deployed final: no owner, admin role, settable parameter, pause, upgrade or administrator withdrawal; every table and threshold is a constant or immutable. Staking principal and rewards remain withdrawable only through the fixed user-facing rules |
| Ecosystem account | A fixed system address excluded from referral binding in either direction: the launch pair, PancakeSwap router, staking contract, deployment contract, dead address and `AIRDROP`; third-party pools are not in this fixed set and are handled by the sender-stake requirement |
| Dead address | `0x000000000000000000000000000000000000dEaD`, which no key controls |
| Staker | The beneficiary of a stake: the account whose active stake it is, whose reward ledger it feeds, to which the principal returns and whose uplines the stake's referral walk pays |
| Payer | The caller of `stake`, whose LLGAME funds the stake; the staker itself in the common case |
| Stake reserve | LLGAME in the staking contract not allocated to any stake |
| Referral budget | 20% of each ordinary stake's amount, taken from the stake reserve at stake time and paid recursively to eligible uplines by the stake-sized cap formula; any non-zero unpaid remainder is recorded as a dedicated `AIRDROP` stake principal |
| Operator | The party running the game; it cannot change the locked contracts or their payout rules |
| Deployment contract | A one-shot, independently deployed contract published without attached BNB and with immutable launch parameters; its receipt of exactly `POOL_BNB` triggers atomic creation and funding of the ecosystem |
| Activation transaction | The permissionless, exact-value BNB transfer to the deployment contract; it creates the token, staking contract and pool, funds liquidity and opens the creators' stake in one transaction |

## 2. Invariants

Every part of the ecosystem is bound by the following; the requirements of sections 3 to 7 are consequences of these invariants.

1. **Locked at launch.** The token and the staking contract are locked contracts. No proxy, upgradeable part or contract-administration signer exists in the token, staking or deployment contracts.
2. **No mint after creation.** The token's constructor mints the whole supply and no function can mint again. Every staking reward and referral allocation is funded from the staking contract's pre-minted holdings.
3. **No administration of value.** No key can move LLGAME out of a locked contract except through its fixed rules: staking principal withdrawal, reward claim, referral payout and release of dedicated `AIRDROP` stake principal. The launch LP position is irretrievably held at `DEAD`; PancakeSwap may separately mint protocol-fee LP shares to its configured `feeTo` address under the DEX's own rules, as described in section 4. `AUTHORS` is an ordinary account with no contract privilege or exclusion; `AIRDROP` can withdraw only matured principal from its dedicated stakes and has no administrative right over any contract.
4. **Fixed conditions.** The staking terms and rates, the referral budget and referral formula, the fixed `AUTHORS` beneficiary, the `AIRDROP` address and the fixed ecosystem-account exclusion set are immutable or constants of the contracts that use them. `AUTHORS` is fixed as a stake beneficiary but is not an ecosystem account.
5. **Solvent by construction.** Nothing is owed beyond what is allocated: a stake reverts when the stake reserve cannot cover its reward and its referral budget; the referral walk pays eligible shares within the stake's referral budget in the same call, and any unpaid part is recorded as dedicated `AIRDROP` stake principal. The sum of the staking contract's accounted ledgers—ordinary principal still held, dedicated `AIRDROP` principal, allocated rewards not yet claimed and unallocated reserve—never exceeds its LLGAME balance. A direct token transfer to the staking contract outside `stake` is an unsolicited donation: it is not credited to the reserve or any stake ledger and has no withdrawal path.
6. **Deterministic binding and payouts.** The staking contract creates a referral binding only when the sender of a recipient's first LLGAME receipt (or the payer for an unseen stake beneficiary, or the delegating staker for an unseen delegate) has `activeStakeOf(sender) > 0` and neither endpoint is excluded. This is a binding-time test, not a continuing payout condition: referral shares are paid according to the level's cap threshold, with the additional positive-liquid-balance condition at level 1. No off-chain party can alter either calculation. Distribution of matured funds withdrawn by `AIRDROP` is an off-chain activity and is not controlled by the contracts.
7. **No transfer tax.** The token's `_update` hook reports receipts to the staking contract but does not deduct a fee or redirect any part of an ordinary transfer.

## 3. Token

- Name Legacy Life Game, symbol LLGAME, 9 decimals, total supply `TOTAL_SUPPLY = 3.4 × 10^29` LLGAME, that is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38`. Every stored token balance and token-denominated stake or reserve ledger is bounded by total supply and fits a `uint128`; intermediate calculations and referral-cap thresholds use `uint256` (section 9.4).
- The constructor mints `POOL_SUPPLY = 1,000,000` LLGAME plus the fixed `AUTHORS_SUPPLY = 250,000` LLGAME to the deployment contract, for the pool and the creators' stake, and the remaining `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract as its initial reserve allocation. `AUTHORS_SUPPLY` is the deployment contract's predefined constant of `250,000 × 10^9` base units, not a constructor argument; no contract exposes it as a method. The token emits no further mint ever. All LLGAME amounts passed to token and staking functions are expressed in base units; `POOL_BNB` is expressed in wei. The prose expresses token balances in LLGAME (9 decimals).
- `ERC20Burnable` lets any holder burn its own tokens; nothing in the ecosystem requires a burn.
- `ERC20Permit` lets a holder approve the staking contract by signature, so a stake is one transaction.
- The token inherits no access control module: there is no owner, no role and no function that would need one.
- The token's only addition to OpenZeppelin is the `_update` override and the immutable `STAKING` address it calls, predicted at deployment. After the balances are updated, an ordinary transfer (`from != address(0)` and `to != address(0)`) of a positive `value` to an account whose balance was zero before it calls `STAKING.noteReceipt(from, to)` (section 6); mint, burn, zero-value transfers and transfers to an account already holding LLGAME call nothing. A balance turns positive only by mint or by transfer, and the mint goes to the deployment and staking contracts alone, so every holder's first LLGAME receipt is reported (`derived`); a later receipt after the balance has dropped to zero is reported again and ignored. The token keeps no referral state, no ecosystem-account set and emits no event of its own.

### 3.1 Interface

```solidity
// Token: the interface beyond OpenZeppelin ERC20, ERC20Burnable and ERC20Permit
function STAKING() external view returns (address);   // immutable, predicted at deployment
```

## 4. Pool

The launch pool is the canonical PancakeSwap v2 LLGAME/WBNB pair. The activation transaction resolves it (creating it if absent), verifies that it has no LLGAME reserve or LP supply, then funds it and sends the launch LP position to `DEAD` atomically:

- The activation adds 1,000,000 LLGAME and exactly `POOL_BNB` wei of BNB, wrapped to WBNB by the deployment contract. `POOL_BNB` is fixed before publication and may be selected to target approximately $10,000 at a reference BNB/USD quote. Any WBNB already synchronized into a pre-created pair remains as a donation, so the actual opening WBNB reserve and price can differ from the amount supplied by the activation transaction. The actual USD value also depends on the BNB/USD rate at activation.
- The activation pool receives 1,000,000 LLGAME, one part in 3.4 × 10^23 of the total supply. It is the initial DEX source of freely tradable LLGAME; the creators' principal is locked in staking, while reserve distributions occur only through the staking rules. Tokens subsequently circulate through ordinary transfers, staking payouts, referral payouts and any off-chain airdrops funded by matured `AIRDROP` withdrawals.
- The LP tokens minted for the activation deposit are sent to the dead address, so that position is locked without a locker contract or owner. Swap fees remain in the pair's reserves; the PancakeSwap protocol may separately mint `feeTo` LP shares under its own factory-controlled fee mechanism.
- The pair address is computed by CREATE2 from the PancakeSwap factory, the predicted token address and WBNB, so it can be included in the staking contract's ecosystem-account set at creation. Because this address is predictable before activation, a third party may create the pair and donate WBNB to it. Un-synced excess WBNB is sent to `DEAD`; WBNB already committed to the pair's reserves is accepted as a donation and changes the opening reserve ratio. The activation procedure rejects any pre-existing LLGAME reserve or LP supply (section 7.2).
- Pools of LLGAME opened later by third parties are outside the fixed ecosystem-account exclusion set. On a buyer's first receipt directly from such a pool, the staking contract checks `activeStakeOf(pool)`: if it is zero, the buyer becomes an unbound root and the pool is not recorded as its referrer. A standard PancakeSwap V2 pair does not expose a function that calls the staking contract. However, because the public stake function accepts a beneficiary different from the payer, a third party can deliberately open a stake for a pool; this can make the pool pass the binding-time check for later first receipts. Referral payout eligibility is a separate test and does not require the upline to still have a stake; section 10 describes the remaining edge case.

## 5. Staking

A holder stakes an amount `A` for a term of 180, 360 or 1080 days, with `stake(amount, term, beneficiary)`. The caller is the payer: the amount is pulled from its balance. The beneficiary is the staker: the stake belongs to that account. In the common case, the caller names itself, but anyone can open a stake for anyone else; during activation, the deployment contract opens the creators' stake for `AUTHORS`. The staking contract allocates at stake time, out of the stake reserve, everything the stake will ever cost; a stake that the reserve cannot cover reverts. The staking contract is deployed at its predicted address after the token has minted its initial allocation there, so its constructor initializes the unallocated reserve from `TOKEN.balanceOf(address(this))`. Later direct LLGAME transfers to the staking address are not treated as reserve deposits; without an explicit stake call they remain unaccounted surplus and cannot be withdrawn.

| Allocation at stake time | Amount | Destination |
|---|---|---|
| Reward | 30%, 72% or 288% of `A` for the three terms, that is 5%, 6% or 8% of `A` per 30 days, rising with the term | The staker's reward ledger, released linearly over the term |
| Referral budget | 20% of `A` (section 6) | Allocated from the stake reserve; eligible shares are paid immediately and any non-zero unpaid remainder becomes dedicated `AIRDROP` stake principal using the originating stake's term, with no second reward or referral allocation |

The reward accrues linearly from the stake block to the unlock, and the staker claims the accrued part at any time, capped by the allocated reward; the ledger keeps the claimed amount, so a fully claimed stake reads and claims cleanly. The principal is returned to the staker at the end of the term, once. There is no early withdrawal and no compounding: a holder that wants to restake takes its payout and stakes again, which triggers a new referral budget. The contract keeps `activeStakeOf[account]`, the sum of the account's ordinary stake principals still held by the staking contract, including matured stakes whose principal has not yet been withdrawn. It decides whether an address may become a referrer when a binding is written and enters the upline's cap calculation (section 6), but a positive value is not a separate payout-eligibility requirement. It is incremented when a stake opens and decremented exactly once when that stake's principal is withdrawn. No separate staker flag or registration state is needed.

### 5.1 Interface

```solidity
// Staking contract: interface sketch
struct StakeInfo {
    address staker;     // the beneficiary: claims the reward and withdraws the principal
    uint128 principal;
    uint128 reward;     // allocated at stake time; zero for a dedicated AIRDROP stake
    uint128 claimed;
    uint64  start;      // timestamp of the stake block; the reward accrues from it to start + term
    uint32  term;       // 180, 360 or 1080 days
    bool    dedicated;  // a dedicated AIRDROP stake, outside activeStakeOf
    bool    withdrawn;
}

event Staked(uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount, uint32 term);
    // also for a dedicated AIRDROP stake: staker AIRDROP, payer the staking contract
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
function withdraw(uint256 stakeId) external;   // the staker only, after the term: the principal
function noteReceipt(address from, address to) external;   // TOKEN only (section 6)

function stakeInfo(uint256 stakeId) external view returns (StakeInfo memory);
function claimable(uint256 stakeId) external view returns (uint256);   // accrued minus claimed, never negative
function activeStakeOf(address account) external view returns (uint256);
function reserve() external view returns (uint256);                    // the unallocated stake reserve
function seen(address account) external view returns (bool);
function referrerOf(address account) external view returns (address); // zero for a root
```

`stakeWithPermit` signs the payer's approval with `ERC20Permit` and does what `stake` does in one transaction. Only the staker claims and withdraws: the payer has no right over the stake once it is open. The stake is not transferable as a whole; its staker may delegate a part of it (section 5.3). `AIRDROP` withdraws its dedicated stakes with the same `withdraw`. `claim` and `withdraw` emit no event of their own: the token's `Transfer` from the staking contract records the amount paid, and `stakeInfo` the state of the stake. `referrerOf` and `seen` together tell the game server the whole referral forest: a seen account with a zero `referrerOf` is a root, and `ReferralBound` lets it be indexed without reading every transfer.

### 5.2 Stake procedure

`stake(amount, term, beneficiary)` runs these steps in this order; any failing check reverts the whole call:

1. Check `amount > 0`, `term` in {180, 360, 1080} days and that `beneficiary` is neither the zero address nor any ecosystem account. The public stake path cannot use `AIRDROP` as a normal beneficiary; only the internal remainder-accounting path may create a dedicated stake for it. The caller must also choose a beneficiary able to call `claim` and `withdraw`; the contract cannot generically verify that an arbitrary smart wallet supports those calls.
2. Allocate the reward and the referral budget from the stake reserve; revert when the reserve is short.
3. Write the ordinary stake under the beneficiary: `stakeId`, the amount, the term, the stake block and the allocated reward; add the amount to `activeStakeOf[beneficiary]`. This stake ledger and the reserve allocation are recorded before the principal transfer.
4. Pull `amount` from the payer: `transferFrom(msg.sender, staking, amount)`. The recipient is an ecosystem account, so the transfer does not create a referral binding.
5. When the beneficiary has never been seen, apply the binding rule of section 6 with the payer as sender: the beneficiary is marked seen and bound to the payer only when the payer is a different address, neither address is in `excluded`, and the payer already has `activeStakeOf(payer) > 0`. If any condition fails—including a payer with no ordinary stake, the deployment contract or `AIRDROP`—the beneficiary becomes an unbound root. An account already seen keeps its existing binding or root status.
6. Walk the beneficiary's uplines recursively and pay each eligible upline its level share, then, if the unpaid part of the 20% referral budget is non-zero, record it immediately as a dedicated `AIRDROP` stake principal (section 6). This special principal uses the originating stake's term and does not itself trigger a reward or another referral budget. Payout eligibility depends on the level's cap requirement; at level 1 the upline must additionally have a positive liquid LLGAME balance. A positive `activeStakeOf` value is not required for payout.
7. Emit `Staked` with the ordinary staker and payer. If a non-zero dedicated `AIRDROP` principal is recorded by this call, emit `Staked` for it as well, with the dedicated stake ID, `AIRDROP` as the staker, the staking contract as the payer, the amount and the originating stake's term. This records an internal reserve allocation, not a second payer transfer, and it follows the originating stake's `Staked` in the same transaction.

The binding of step 5 keeps the referral forest acyclic: a binding is written only to a payer distinct from the beneficiary, and that payer must already have an ordinary stake principal (`activeStakeOf(payer) > 0`). The payer necessarily acquired LLGAME before opening that earlier stake and was therefore already seen before the new beneficiary is bound. Every new edge points to an account already seen (`derived`). A beneficiary the token has already seen, whether bound or a root, keeps its existing status whoever pays its stake.

The creators' 250,000 LLGAME stake follows the ordinary 1080-day rules: its 720,000 LLGAME reward (288%) is allocated and released linearly, its principal returns after 1080 days, and its entire 50,000 LLGAME referral allocation becomes dedicated `AIRDROP` stake principal because `AUTHORS` starts as an unbound root with no upline. The deployment contract is an ecosystem account and `AUTHORS` is not, so step 5 marks `AUTHORS` as an unbound root under the ordinary binding rule. `AUTHORS` is not excluded and may act as a referrer like any other holder.

The reserve available to ordinary stakes after activation is `R_launch`, calculated in section 9.2. The reserve-capacity implications are discussed in section 9.3.

### 5.3 Stake delegation

`delegateStake(stakeId, amount, delegateAddress)` splits an ordinary stake and hands the split part to another account. It runs these steps in this order; any failing check reverts the whole call:

1. Check that the caller is the stake's staker, the stake is ordinary and its principal not withdrawn, `0 < amount < principal`, and `delegateAddress` is neither the zero address, the caller nor any ecosystem account. Dedicated `AIRDROP` stakes cannot be delegated.
2. Pay the caller the stake's accrued, unclaimed reward, as `claim` does, so that the reward accrued before delegation stays with the caller.
3. When `delegateAddress` has never been seen, mark it seen and bind it to the caller as its referrer. The caller holds the stake being split, so `activeStakeOf(caller) > 0` holds. A delegate already seen keeps its existing binding or root status.
4. Write a new ordinary stake under the delegate with principal `amount`, the original term and stake block, reward allocation `floor(reward × amount / principal)` and claimed amount `floor(claimed × amount / principal)`; the original stake keeps the remainders of principal, reward and claimed amount. Move `amount` from `activeStakeOf[caller]` to `activeStakeOf[delegate]`.
5. Emit `StakeDelegated`.

Delegation moves no LLGAME and touches no reserve: no reward or referral budget is allocated, no referral walk runs and no `AIRDROP` principal is recorded. Both parts keep the original unlock date. The delegated stake is ordinary in every other respect: only the delegate claims and withdraws it, and the delegate may delegate a part of it again. The new binding keeps the referral forest acyclic, since the caller, a staker, was seen before the delegate (`derived`).

## 6. Referral program

The referral program is funded inside the stake call from a budget equal to 20% of the stake amount `A`, taken from the stake reserve. It keeps no unpaid referral balance: eligible uplines receive their shares immediately, and any non-zero unpaid remainder is recorded as a dedicated `AIRDROP` stake principal using the originating stake's term. This special principal does not trigger a second reward or referral allocation. An LLGAME transfer runs no recipient code (section 2), so an upline cannot revert a stake or reenter the contract through token receipt. The ordinary stake and reserve allocation are recorded before the principal transfer (section 5.2); the dedicated `AIRDROP` remainder is recorded once the referral shares have been determined. The uplines' receipts come from the staking contract, an ecosystem account, so they do not create referral bindings.

The staking contract keeps `seen`, `referrerOf` and the immutable ecosystem-account set `excluded`, and decides each account's referral status once, when the account is first seen; no function rewrites a binding. `noteReceipt(from, to)`, callable by the token alone, reports a receipt (section 3) and reverts for no other reason; it also runs inside the staking contract's own payouts, so no reentrancy guard covers it. An account not yet seen is marked seen and bound to the sender of its first LLGAME only when that sender already has an ordinary stake principal recorded (`activeStakeOf(sender) > 0`), the two differ and neither endpoint is excluded; an account already seen is left unchanged. When a stake is opened for an unseen beneficiary, the same test applies to the payer (section 5.2), and when a stake part is delegated to an unseen account, to the delegating staker (section 5.3). A first receipt from a pool or another sender without an ordinary stake leaves the recipient unbound as a root. The binding-time stake requirement is not an ongoing condition: after a binding has been written, the sender's later withdrawal does not erase it. The referral graph is a forest of these immutable bindings, with new roots appearing whenever a recipient's first sender does not qualify. `AIRDROP` is outside this forest under all circumstances: it cannot be a referrer, cannot be referred and is never paid a referral share.

For a stake of amount `A`, the staking contract walks from the staker's direct upline upward. The stake requirement has already been applied when each referral binding was created; it is not checked again when rewards are paid. Payout eligibility is determined by the cap, with an additional positive-liquid-balance condition at level 1. The halving share schedule keeps the total payout within the 20% budget, while the doubling cap requirement limits eligibility at each successive level. At level `n` (starting at 1):

- `share(n) = (A / 10) >> (n − 1)`, that is `floor(A / (10 × 2^(n − 1)))`;
- `requiredCap(n) = A << (n − 1)`, that is `A × 2^(n − 1)`;
- `cap(account) = token.balanceOf(account) + activeStakeOf(account)`;

The contract computes both with shifts instead of exponentiation: the walk starts from `A / 10` and `A` at level 1, and at each next level halves the share (`share >>= 1`) and doubles the threshold (`requiredCap <<= 1`). Each halving rounds down, and a repeated floor of halves equals the floor of the whole division, so the shifted share is exactly the formula's value (`derived`). Solidity does not check shifts for overflow. None occurs here: `A` fits a `uint128` and the threshold shifts by at most nine bits, so it stays below `2^137`.

There is no additional `activeStakeOf(account) > 0` payout condition. `activeStakeOf` contributes to the cap when an ordinary stake principal remains held, but liquid LLGAME alone can satisfy the cap after the upline has withdrawn all stakes.

Eligibility is evaluated after the stake principal has been pulled from the payer and the beneficiary's stake has been recorded. At every level, an upline is eligible when its cap meets that level's threshold. At level 1, the upline must additionally have a remaining liquid LLGAME balance greater than zero. Thus, when the payer is the direct upline, the payer must retain a positive liquid balance after funding the stake; the amount just transferred into the new stake does not count as liquid balance. The cap thresholds are `A` at level 1, `2A` at level 2, `4A` at level 3, and so on. The cap includes both liquid account balance and the account's ordinary stake principal still held by the staking contract; that principal is not included in `balanceOf(account)`. `activeStakeOf` includes matured ordinary stakes whose principal has not yet been withdrawn and is decremented when principal is withdrawn. Dedicated `AIRDROP` stake principal is not included. An upline with no remaining ordinary stake can still qualify if its liquid LLGAME balance alone meets the cap threshold; withdrawing a stake does not remove an existing referral binding. `AIRDROP` is explicitly excluded from the walk and can never receive a referral share. Eligibility is checked at each level, and the first ineligible upline stops the walk. The walk also stops after the fixed maximum of ten levels. The sum of the individually rounded shares cannot exceed the rounded 20% referral budget.

The referral budget is `floor(20 × A / 100)` base units. Each level's share is rounded down in base units and calculated from the original stake amount, not from the previous upline's payout. Before per-level integer rounding, the ten-level sum is `19.98046875% × A`; rounding can only reduce the paid sum. Any non-zero budget remainder is immediately recorded as dedicated `AIRDROP` stake principal in the same stake call, using the originating stake's term and generating no further reward or referral budget. If the remainder rounds to zero base units, no dedicated stake or corresponding event is created. The contract pays no more than `20% × A`; the ten-level maximum is a separate fixed execution bound.

## 7. Deployment contract

The deployment contract is an atomic, single-fire launcher with no administrative capability. Its constructor fixes the configurable launch parameters as immutables; `AUTHORS_SUPPLY` is a predefined constant, not a constructor parameter. The only mutable state is a one-way `launched` flag with no setter. There is no owner, upgrade path or privileged activation caller. Once published, the contract cannot be altered by any party.

### 7.1 Interface

```solidity
// Deployment contract — interface sketch
contract Deployment {
    uint256 private constant AUTHORS_SUPPLY = 250_000 * 10 ** 9;

    // Configurable launch parameters are immutable; AUTHORS_SUPPLY is a predefined constant.
    // The constructor is non-payable: no BNB can be attached at publication.
    constructor(
        address factory_, address router_, address wbnb_,
        address authors_, address airdrop_, uint256 poolBnb_,
        Params memory p_
    );

    // Receives at least POOL_BNB wei via empty-calldata native transfer; the full amount
    // funds the liquidity pool. First valid call triggers the complete launch atomically.
    receive() external payable;

    // True after a successful activation; reverts to false on a reverted attempt.
    bool public launched;
}
```

The constructor validates every supplied address and parameter. `POOL_BNB` is checked to be a positive integer not exceeding `type(uint112).max`. The `receive` function enforces `!launched` and `msg.value >= POOL_BNB` before setting `launched = true` and executing the launch sequence; the entire `msg.value` is wrapped into WBNB and deposited into the liquidity pool.

### 7.2 Features

**Immutable configuration.** Every address (`AUTHORS`, `AIRDROP`, PancakeSwap factory, router, WBNB), every economic parameter (supply amounts, staking terms, referral rates) and the `POOL_BNB` funding amount are stored as constants or immutables. The 250,000 LLGAME `AUTHORS_SUPPLY` is predefined and is not supplied in `Params` or any other constructor argument. None can be changed after publication, neither by the deployer nor by the activation funder.

**Predictable child addresses.** The deployment contract's first two `CREATE` operations are reserved for the token and staking contract. Their addresses are therefore predictable from the deployment contract's own address and its initial nonce of one, allowing the token's `STAKING` reference and the staking contract's `TOKEN` reference and `excluded` set to be fixed at construction.

**Atomic single-fire activation.** The first native BNB transfer carrying at least `POOL_BNB` triggers the complete launch in one transaction:
- deploy the token with the full supply minted and the `STAKING` address fixed;
- deploy the staking contract with the initial reserve allocation already present and the `excluded` set fixed;
- resolve the canonical PancakeSwap v2 LLGAME/WBNB pair, accepting pre-created pairs and synchronized WBNB donations, rejecting pre-existing LLGAME reserves or LP supply;
- wrap the entire received BNB and deposit it with the pool allocation of LLGAME, minting the launch LP position to `DEAD`;
- open the creators' 1080-day stake for the fixed `AUTHORS` address;
- verify the resulting on-chain state: total supply, balance split, creators' stake and empty deployment-contract token balance.

Insufficient funding, a second attempt or any failed step reverts the entire transaction, returning the BNB to the sender and leaving the `launched` flag `false` for a later valid attempt.

**No retained value.** After activation, the deployment contract holds none of the LLGAME, WBNB or BNB involved in the launch; the full `msg.value` is deposited into the pool. The contract has no withdrawal function, setter or administrative role. Any funds forcibly sent to it outside the `receive` path remain stranded.

**Pre-created pair resilience.** The PancakeSwap pair address is predictable from the factory, the predicted token address and WBNB. A third party may create the pair or donate WBNB to it before activation. The activation sequence handles this: unsynchronized excess WBNB is skimmed to `DEAD`; WBNB already synchronized into reserves is accepted as a locked donation and affects the opening reserve ratio.

| Step | Guarantee held |
|---|---|
| Deployment contract published separately without attached BNB | The launch configuration can be inspected before anyone funds it; the launcher has not created the token, staking contract or launch LP position |
| Every launch value stored as a constant or immutable | Neither the deployer nor the funder can change `AUTHORS`, `AIRDROP`, pool funding or any economic parameter after publication |
| Minimum `msg.value` check and one-shot `launched` flag | Only funding at or above the predefined minimum can activate the launch, and only once; the full amount funds the pool; a failed activation reverts the transfer |
| Nonce-predicted `CREATE` addresses from the deployment contract | The token's `STAKING` and the staking contract's `TOKEN` and six-address `excluded` set, all fixed at construction, are correct by construction |
| Canonical pair obtained and checked during activation | A third party may pre-create the predictable pair or donate WBNB to it; the launcher reuses only the factory-computed pair, sends unsynchronized excess to `DEAD`, accepts synchronized WBNB as a donation, and requires zero LLGAME reserves and balances and zero LP supply |
| LP minted to the dead address | Liquidity is locked without a locker or owner; invariant 3 |
| Creators' stake opened in the activation transaction | The authors' allocation is locked for 1080 days by the same rules as every stake, with no key able to shorten it |
| Final verification block | Supply, the split, the creators' stake, empty deployment-contract token balance and the LP position held at `DEAD` are facts of the activation transaction, not of a later audit |

### 7.3 After activation

Once launched, the deployment contract is inert. The token, staking contract and pair are independently verifiable on chain: anyone can confirm the immutable parameters, the absence of owner or admin roles, the one-shot activation, the initial LP position locked at `DEAD`, the creators' stake and the staking contract's balance against its ledgers. The activation sender receives no token allocation, LP position or administrative role. Any subsequent protocol-fee LP minting by PancakeSwap follows the DEX factory's own rules, independent of the deployment contract.

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
| Referral payout eligibility | `balanceOf(upline) + activeStakeOf(upline) >= A << (n−1)` at level `n`; level 1 additionally requires liquid balance `> 0`; no separate positive-stake condition |
| Staking terms | 180, 360 and 1080 days |
| Reward rates | 30%, 72% and 288% of principal over the respective terms |
| Reward release | Linear over the stake term, claimable by the staker as it accrues |
| Pool | PancakeSwap v2 LLGAME/WBNB pair; launch LP position sent to `DEAD` |
| Activation funding | At least `POOL_BNB` wei; the full amount enters the pool; the funder pays transaction gas separately |
| Stake entry point | `stake(amount, term, beneficiary)`, paid by the caller and owned by the beneficiary |
| Stake delegation | `delegateStake(stakeId, amount, delegate)` by the staker: splits `0 < amount < principal` with its proportional reward to the delegate, same term and unlock, no reserve allocation or referral budget; an unseen delegate is bound to the staker |
| Unpaid referral remainder | Any non-zero remainder is recorded immediately as dedicated `AIRDROP` stake principal, with the originating stake's term and no second reward or referral allocation |

### 8.2 Values fixed before publication

Every value in this table must be final before the deployment contract is published. No value is supplied by the activation sender or changed after publication. `AUTHORS` is distinct from all ecosystem and DEX infrastructure addresses but is not itself excluded. `AIRDROP` is distinct from every other excluded or DEX infrastructure address.

| Parameter | Meaning | Requirement |
|---|---|---|
| `AUTHORS` | Ordinary address that receives the creators' stake | Non-zero; distinct from the token, pair, staking contract, deployment contract, `DEAD`, `AIRDROP`, factory, router and WBNB; not included in the staking contract's `excluded` set; must be an EOA or a smart wallet able to call the staking contract |
| `AIRDROP` | Special address for dedicated referral-remainder stakes | Non-zero; distinct from `AUTHORS`, the token, pair, staking contract, deployment contract, `DEAD`, factory, router and WBNB; included in `excluded`, so it cannot be bound, refer or receive referral payouts; must be an EOA or a smart wallet able to call the staking contract |
| `POOL_BNB` | Exact BNB amount in wei sent by the activation transaction and wrapped into WBNB | Fixed positive integer amount |
| PancakeSwap addresses | Factory, router and WBNB contract addresses for the target BSC deployment | Fixed and verified against the intended network |

`AUTHORS` is not a protocol or ecosystem address. Because the creators' stake is opened by the excluded deployment contract during the atomic activation, before any public token interaction is possible, the normal binding rule marks `AUTHORS` as an unbound root. It remains an ordinary account: it can act as a referrer and receive referral shares if its position in another holder's referral tree makes it eligible, but it is not specially excluded from token transfers or referral logic. Both `AUTHORS` and `AIRDROP` should be controlled by an EOA or by a smart wallet whose owners can submit calls to the staking contract; otherwise, their principal could mature but remain unwithdrawable.

## 9. Reserve accounting

The staking reserve is finite and is the source of every staking reward, referral payment and dedicated `AIRDROP` stake principal. The contract allocates the full cost of each stake when that stake is opened. It never promises a reward or referral amount that has not already been reserved. In the formulas below, `floor(x)` denotes integer division with the same rounding used by the staking contract.

### 9.1 Cost of an ordinary stake

For a stake of principal `A`, the principal itself is transferred by the payer and is not taken from the unallocated reserve. The reserve funds the reward allocation and the 20% referral budget:

| Term | Reward allocation | Referral allocation | Total reserve allocation `c × A` |
|---|---:|---:|---:|
| 180 days | 30% of `A` | 20% of `A` | 0.50 × `A` |
| 360 days | 72% of `A` | 20% of `A` | 0.92 × `A` |
| 1080 days | 288% of `A` | 20% of `A` | 3.08 × `A` |

The referral allocation is fully accounted for at stake time. Shares paid to eligible uplines leave the staking contract immediately. The unpaid remainder is not free reserve: it is a liability recorded as dedicated `AIRDROP` stake principal. It therefore remains part of the allocated 20% and cannot be counted again as available reserve.

### 9.2 Reserve immediately after activation

The token constructor initially sends `POOL_SUPPLY + AUTHORS_SUPPLY` to the deployment contract and the balance `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract. During activation, the deployment contract transfers `POOL_SUPPLY` to the pair and opens the creators' stake for `AUTHORS`.

The creators' stake follows the ordinary 1080-day rules. Since `AUTHORS` begins as an unbound root, it has no upline at activation; the full 50,000 LLGAME referral allocation therefore becomes dedicated `AIRDROP` stake principal. The creators' stake also allocates its 720,000 LLGAME reward. The unallocated reserve after activation is consequently:

```
R_launch = TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY
          − floor(288 × AUTHORS_SUPPLY / 100)
          − floor(20 × AUTHORS_SUPPLY / 100)

         = 3.4 × 10^29 − 2,020,000 LLGAME
```

The subtraction comprises 1,000,000 LLGAME for the pool and 250,000 LLGAME principal, 720,000 LLGAME reward and 50,000 LLGAME referral allocation for the creators' stake. The result is positive and exact with the stated integer-floor operations; it assumes the deployment transaction completes successfully. The staking contract's token balance immediately after activation is `TOTAL_SUPPLY − POOL_SUPPLY`; that balance is divided between the creators' principal, their allocated reward, their dedicated `AIRDROP` principal and `R_launch`. Dedicated `AIRDROP` stakes are tracked separately from `activeStakeOf`, which counts only ordinary stakes used in referral-cap calculations.

### 9.3 Capacity and duration

For a new ordinary stake of amount `A`, the unallocated reserve must cover `0.50 × A`, `0.92 × A` or `3.08 × A`, depending on the selected term. Ignoring integer rounding, the maximum cumulative principal amount that can be opened against a reserve `R` is therefore bounded by:

- `R / 3.08` if every new stake uses the 1080-day term;
- `R / 0.92` if every new stake uses the 360-day term;
- `R / 0.50` if every new stake uses the 180-day term.

These are cumulative stake-volume bounds under the stated single-term assumptions, not simultaneous-stake limits or calendar-lifetime guarantees. The actual duration depends primarily on aggregate new stake volume and the mix of selected terms. Referral eligibility changes the destination of the fixed referral allocation, not its reserve cost; restaking rewards or withdrawn principal can increase later stake volume, while principal withdrawals themselves do not replenish the reserve. The market price and available DEX liquidity may influence demand, but they do not mathematically guarantee a minimum reserve lifetime. The contract's enforceable guarantee is narrower and stronger: every accepted stake is fully allocated at entry, and a new stake reverts if its full reward and referral allocation cannot be covered.

### 9.4 Sizing the supply

The supply is sized to fit the staking ledger's packed amount field. ERC-20 balances are `uint256`, but each stored token-denominated stake amount, principal, reward allocation and reserve amount is bounded by total supply and fits a `uint128`. Computed referral-cap thresholds and multiplication intermediates use `uint256` and are not packed into that field. With 9 decimals, `3.4 × 10^29` LLGAME is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38` and leaving approximately 0.08% of the width unused.

| Decimals | Supply | Base units | Width |
|---|---|---|---|
| 9 | 3.4 × 10^29 LLGAME | 3.4 × 10^38 | 128 bits |

At the intended reference launch price of about $0.01 per LLGAME, the smallest unit is worth a billionth of a cent. The actual initial USD price depends on the BNB/USD rate at activation and on any WBNB donation already synchronized into the canonical pair.


## Sources

1. OpenZeppelin Contracts 5.x, ERC20 API. https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
2. EIP-161: state trie clearing, contract nonce starting at one. https://eips.ethereum.org/EIPS/eip-161
3. PancakeSwap developer docs, v2 Factory and Addresses. https://developer.pancakeswap.finance/contracts/v2/addresses
4. `PancakePair` source: `MINIMUM_LIQUIDITY`, `mint(to)`, `skim(to)` and reserve accounting. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakePair.sol
5. `PancakeFactory` source: `createPair` uses CREATE2 and does not require either token address to contain token code. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakeFactory.sol
6. Solidity documentation: `receive()` handles empty-calldata transfers; `send()` and `transfer()` forward only the 2,300-gas stipend. https://docs.solidity.org/en/latest/contracts.html
