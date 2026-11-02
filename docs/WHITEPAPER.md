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

- `AUTHORS_SUPPLY` LLGAME - creators' stake, locked for 1080 days: an ordinary stake opened for the fixed `AUTHORS` address inside the activation transaction;
- 1,000,000 LLGAME paired with BNB in a launch liquidity pool whose liquidity provider (LP) tokens are sent to `DEAD`;
- the remaining supply is initially held by the staking contract. After the creators' stake is opened, the unallocated part becomes the reserve that funds subsequent staking rewards and referral allocations.

Holders receive value through:

- staking for 180, 360 or 1080 days, with rewards accruing over time and claimable as they accrue;
- the referral program: a budget of each stake, paid inside the stake call to the staker's uplines;
- gamified airdrops: any non-zero unpaid remainder of that budget is recorded immediately as a dedicated stake principal for the special `AIRDROP` address, making the accumulated airdrop budget transparent and predictable on chain;

The operational ecosystem consists of two locked contracts and a DEX pair, launched by a separate one-shot deployment contract. Two separately controlled addresses participate in its economics: `AUTHORS`, the ordinary beneficiary of the creators' stake, and `AIRDROP`, the special address for accumulated referral remainders. The deployment contract's address is included in the token's `excluded` set, but the launcher has no role after activation. `AUTHORS` is not an ecosystem account and is not included in `excluded`:

| Part | Role | Administration |
|---|---|---|
| Token (`LLGAME`) | OpenZeppelin v5 `ERC20`, `ERC20Burnable`, `ERC20Permit`, 9 decimals, no access control module; records a first-receipt referral binding only when the sender already has an ordinary stake principal recorded in the staking contract, or applies the same rule to the payer of a stake opened for an unseen beneficiary | None: locked at launch |
| Pool | PancakeSwap v2 LLGAME/WBNB pair, activation LP position sent to `DEAD` | None: the pair is DEX code, its protocol `feeTo` share excepted |
| Staking | Holds the reserve; takes stakes paid by their caller for a beneficiary, allocates rewards, pays referral shares to eligible uplines, records any non-zero unpaid referral remainder as dedicated `AIRDROP` stake principal inside the stake call | None: locked at launch |
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
6. **Deterministic binding and payouts.** The token creates a referral binding only when the sender of a recipient's first LLGAME receipt (or the payer for an unseen stake beneficiary) has `activeStakeOf(sender) > 0` and neither endpoint is excluded. This is a binding-time test, not a continuing payout condition: referral shares are paid according to the level's cap threshold, with the additional positive-liquid-balance condition at level 1. No off-chain party can alter either calculation. Distribution of matured funds withdrawn by `AIRDROP` is an off-chain activity and is not controlled by the contracts.
7. **No transfer tax.** The token's `_update` hook records first-receipt bindings but does not deduct a fee or redirect any part of an ordinary transfer.

## 3. Token

- Name Legacy Life Game, symbol LLGAME, 9 decimals, total supply `TOTAL_SUPPLY = 3.4 × 10^29` LLGAME, that is `3.4 × 10^38` base units, just below `2^128 ≈ 3.4028 × 10^38`. Every stored token balance and token-denominated stake or reserve ledger is bounded by total supply and fits a `uint128`; intermediate calculations and referral-cap thresholds use `uint256` (section 9.4).
- The constructor mints `POOL_SUPPLY = 1,000,000` LLGAME plus `AUTHORS_SUPPLY` LLGAME to the deployment contract, for the pool and the creators' stake, and the remaining `TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY` to the staking contract as its initial reserve allocation. The token emits no further mint ever. All LLGAME amounts passed to token and staking functions are expressed in base units; `POOL_BNB` is expressed in wei. The prose expresses token balances in LLGAME (9 decimals).
- `ERC20Burnable` lets any holder burn its own tokens; nothing in the ecosystem requires a burn.
- `ERC20Permit` lets a holder approve the staking contract by signature, so a stake is one transaction.
- The token inherits no access control module: there is no owner, no role and no function that would need one.
- The `_update` hook keeps `seen`, `referrerOf` and the immutable ecosystem-account set `excluded`. Referral binding runs only on ordinary transfers (`from != address(0)` and `to != address(0)`), not on mint or burn. On a recipient's first receipt, the token marks it `seen`; it writes `referrerOf[to] = from` only when neither endpoint is excluded, `from != to`, and `STAKING.activeStakeOf(from) > 0` at that moment. The staking address is immutable and predicted at deployment; the token performs this read only for an unseen recipient on an ordinary transfer, not on every transfer. If the sender has no ordinary stake principal recorded, the recipient becomes an unbound root. The check is made only when the recipient is first seen; there is no separate staker flag. `AIRDROP` is excluded in both directions and can never be a referrer or referred account, regardless of its dedicated stake principal. `AUTHORS` is not excluded and follows the same rules as every other ordinary account.
- `bindStaked(account, payer)`, callable by the staking contract alone (`msg.sender == STAKING`, an immutable), is the only other writer of `seen` and `referrerOf`. For a stake opened for an account the token has never seen, it marks the beneficiary seen and binds it to the payer only when `payer != account`, neither address is excluded, and `STAKING.activeStakeOf(payer) > 0`. Otherwise, the beneficiary becomes an unbound root. An account already seen is left unchanged. No function rewrites a binding. The `AIRDROP` address is rejected as either endpoint under all circumstances.

## 4. Pool

The launch pool is the canonical PancakeSwap v2 LLGAME/WBNB pair. The activation transaction resolves it (creating it if absent), verifies that it has no LLGAME reserve or LP supply, then funds it and sends the launch LP position to `DEAD` atomically:

- The activation adds 1,000,000 LLGAME and exactly `POOL_BNB` wei of BNB, wrapped to WBNB by the deployment contract. `POOL_BNB` is fixed before publication and may be selected to target approximately $10,000 at a reference BNB/USD quote. Any WBNB already synchronized into a pre-created pair remains as a donation, so the actual opening WBNB reserve and price can differ from the amount supplied by the activation transaction. The actual USD value also depends on the BNB/USD rate at activation.
- The activation pool receives 1,000,000 LLGAME, one part in 3.4 × 10^23 of the total supply. It is the initial DEX source of freely tradable LLGAME; the creators' principal is locked in staking, while reserve distributions occur only through the staking rules. Tokens subsequently circulate through ordinary transfers, staking payouts, referral payouts and any off-chain airdrops funded by matured `AIRDROP` withdrawals.
- The LP tokens minted for the activation deposit are sent to the dead address, so that position is locked without a locker contract or owner. Swap fees remain in the pair's reserves; the PancakeSwap protocol may separately mint `feeTo` LP shares under its own factory-controlled fee mechanism.
- The pair address is computed by CREATE2 from the PancakeSwap factory, the predicted token address and WBNB, so it can be included in the token's ecosystem account set at creation. Because this address is predictable before activation, a third party may create the pair and donate WBNB to it. Un-synced excess WBNB is sent to `DEAD`; WBNB already committed to the pair's reserves is accepted as a donation and changes the opening reserve ratio. The activation procedure rejects any pre-existing LLGAME reserve or LP supply (section 7.2).
- Pools of LLGAME opened later by third parties are outside the fixed ecosystem-account exclusion set. On a buyer's first receipt directly from such a pool, the token checks `activeStakeOf(pool)`: if it is zero, the buyer becomes an unbound root and the pool is not recorded as its referrer. A standard PancakeSwap V2 pair does not expose a function that calls the staking contract. However, because the public stake function accepts a beneficiary different from the payer, a third party can deliberately open a stake for a pool; this can make the pool pass the binding-time check for later first receipts. Referral payout eligibility is a separate test and does not require the upline to still have a stake; section 10 describes the remaining edge case.

## 5. Staking

A holder stakes an amount `A` for a term of 180, 360 or 1080 days, with `stake(amount, term, beneficiary)`. The caller is the payer: the amount is pulled from its balance. The beneficiary is the staker: the stake belongs to that account. In the common case, the caller names itself, but anyone can open a stake for anyone else; during activation, the deployment contract opens the creators' stake for `AUTHORS`. The staking contract allocates at stake time, out of the stake reserve, everything the stake will ever cost; a stake that the reserve cannot cover reverts. The staking contract is deployed at its predicted address after the token has minted its initial allocation there, so its constructor initializes the unallocated reserve from `TOKEN.balanceOf(address(this))`. Later direct LLGAME transfers to the staking address are not treated as reserve deposits; without an explicit stake call they remain unaccounted surplus and cannot be withdrawn.

| Allocation at stake time | Amount | Destination |
|---|---|---|
| Reward | 30%, 72% or 288% of `A` for the three terms, that is 5%, 6% or 8% of `A` per 30 days, rising with the term | The staker's reward ledger, released linearly over the term |
| Referral budget | 20% of `A` (section 6) | Allocated from the stake reserve; eligible shares are paid immediately and any non-zero unpaid remainder becomes dedicated `AIRDROP` stake principal using the originating stake's term, with no second reward or referral allocation |

The reward accrues linearly from the stake block to the unlock, and the staker claims the accrued part at any time, capped by the allocated reward; the ledger keeps the claimed amount, so a fully claimed stake reads and claims cleanly. The principal is returned to the staker at the end of the term, once. There is no early withdrawal and no compounding: a holder that wants to restake takes its payout and stakes again, which triggers a new referral budget. The contract keeps `activeStakeOf[account]`, the sum of the account's ordinary stake principals still held by the staking contract, including matured stakes whose principal has not yet been withdrawn. The token uses this value only to decide whether an address may create a referral binding when it is the sender of a first receipt (section 3); the staking contract also includes it in the upline's cap calculation (section 6), but a positive value is not a separate payout-eligibility requirement. It is incremented when a stake opens and decremented exactly once when that stake's principal is withdrawn. No separate staker flag or registration state is needed.

### 5.1 Interface

```solidity
// Staking contract, sketch — the stake-side interface
event Staked(uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount, uint32 term);
event RewardClaimed(uint256 indexed stakeId, address indexed staker, uint256 amount);
event Withdrawn(uint256 indexed stakeId, address indexed staker, uint256 principal);
event AirdropPrincipalRecorded(uint256 indexed sourceStakeId, uint256 indexed airdropStakeId, uint256 amount, uint32 term);

function stake(uint256 amount, uint32 term, address beneficiary) external returns (uint256 stakeId);
function stakeWithPermit(uint256 amount, uint32 term, address beneficiary,
                         uint256 deadline, uint8 v, bytes32 r, bytes32 s) external returns (uint256 stakeId);
function claim(uint256 stakeId) external;      // the staker only: the accrued, unclaimed reward
function withdraw(uint256 stakeId) external;   // the staker only, after the term: the principal
function activeStakeOf(address account) external view returns (uint256);
```

`stakeWithPermit` signs the payer's approval with `ERC20Permit` and does what `stake` does in one transaction. Only the staker claims and withdraws: the payer has no right over the stake once it is open, and the stake is not transferable.

### 5.2 Stake procedure

`stake(amount, term, beneficiary)` runs these steps in this order; any failing check reverts the whole call:

1. Check `amount > 0`, `term` in {180, 360, 1080} days and that `beneficiary` is neither the zero address nor any ecosystem account. The public stake path cannot use `AIRDROP` as a normal beneficiary; only the internal remainder-accounting path may create a dedicated stake for it. The caller must also choose a beneficiary able to call `claim` and `withdraw`; the contract cannot generically verify that an arbitrary smart wallet supports those calls.
2. Allocate the reward and the referral budget from the stake reserve; revert when the reserve is short.
3. Write the ordinary stake under the beneficiary: `stakeId`, the amount, the term, the stake block and the allocated reward; add the amount to `activeStakeOf[beneficiary]`. This stake ledger and the reserve allocation are recorded before the principal transfer.
4. Pull `amount` from the payer: `transferFrom(msg.sender, staking, amount)`. The recipient is an ecosystem account, so the transfer does not create a referral binding.
5. When the token has never seen the beneficiary, call `token.bindStaked(beneficiary, msg.sender)` (section 3): the beneficiary is marked seen and bound to the payer only when the payer is a different address, neither address is in `excluded`, and the payer already has `activeStakeOf(payer) > 0`. If any condition fails—including a payer with no ordinary stake, the deployment contract or `AIRDROP`—the beneficiary becomes an unbound root. An account already seen keeps its existing binding or root status.
6. Walk the beneficiary's uplines recursively and pay each eligible upline its level share, then, if the unpaid part of the 20% referral budget is non-zero, record it immediately as a dedicated `AIRDROP` stake principal (section 6). This special principal uses the originating stake's term and does not itself trigger a reward or another referral budget. Payout eligibility depends on the level's cap requirement; at level 1 the upline must additionally have a positive liquid LLGAME balance. A positive `activeStakeOf` value is not required for payout.
7. Emit `Staked` with the ordinary staker and payer. If a non-zero dedicated `AIRDROP` principal is recorded by this call, emit `AirdropPrincipalRecorded` with the originating stake ID, the dedicated stake ID, amount and term; this is an internal reserve allocation, not a second payer transfer.

The binding of step 5 keeps the referral forest acyclic: a binding is written only to a payer distinct from the beneficiary, and that payer must already have an ordinary stake principal (`activeStakeOf(payer) > 0`). The payer necessarily acquired LLGAME before opening that earlier stake and was therefore already seen before the new beneficiary is bound. Every new edge points to an account already seen (`derived`). A beneficiary the token has already seen, whether bound or a root, keeps its existing status whoever pays its stake.

The creators' stake follows the ordinary 1080-day rules: its 288% reward is allocated and released linearly, its principal returns after 1080 days, and its entire rounded referral allocation (if non-zero) becomes dedicated `AIRDROP` stake principal because `AUTHORS` starts as an unbound root with no upline. The deployment contract is an ecosystem account and `AUTHORS` is not, so `bindStaked` marks `AUTHORS` as an unbound root under the ordinary first-receipt rule. `AUTHORS` is not excluded and may act as a referrer like any other holder.

The reserve available to ordinary stakes after activation is `R_launch`, calculated in section 9.2. The reserve-capacity implications are discussed in section 9.3.

## 6. Referral program

The referral program is funded inside the stake call from a budget equal to 20% of the stake amount `A`, taken from the stake reserve. It keeps no unpaid referral balance: eligible uplines receive their shares immediately, and any non-zero unpaid remainder is recorded as a dedicated `AIRDROP` stake principal using the originating stake's term. This special principal does not trigger a second reward or referral allocation. An LLGAME transfer runs no recipient code (section 2), so an upline cannot revert a stake or reenter the contract through token receipt. The ordinary stake and reserve allocation are recorded before the principal transfer (section 5.2); the dedicated `AIRDROP` remainder is recorded once the referral shares have been determined. The uplines' receipts come from the staking contract, an ecosystem account, so they do not create referral bindings.

A holder is bound, in the token, to the sender of its first LLGAME only when that sender already has an ordinary stake principal recorded (`activeStakeOf(sender) > 0`) and neither endpoint is excluded. When a stake is opened for an unseen beneficiary, the same test applies to the payer (section 5.2). A first receipt from a pool or another sender without an ordinary stake leaves the recipient unbound as a root. The binding-time stake requirement is not an ongoing condition: after a binding has been written, the sender's later withdrawal does not erase it. The referral graph is a forest of these immutable bindings, with new roots appearing whenever a recipient's first sender does not qualify. `AIRDROP` is outside this forest under all circumstances: it cannot be a referrer, cannot be referred and is never paid a referral share.

For a stake of amount `A`, the staking contract walks from the staker's direct upline upward. The stake requirement has already been applied when each referral binding was created; it is not checked again when rewards are paid. Payout eligibility is determined by the cap, with an additional positive-liquid-balance condition at level 1. The halving share schedule keeps the total payout within the 20% budget, while the doubling cap requirement limits eligibility at each successive level. At level `n` (starting at 1):

- `share(n) = floor(10 × A / (100 × 2^(n − 1)))`; 
- `requiredCap(n) = A × 2^(n − 1)`;
- `cap(account) = token.balanceOf(account) + activeStakeOf(account)`;

There is no additional `activeStakeOf(account) > 0` payout condition. `activeStakeOf` contributes to the cap when an ordinary stake principal remains held, but liquid LLGAME alone can satisfy the cap after the upline has withdrawn all stakes.

Eligibility is evaluated after the stake principal has been pulled from the payer and the beneficiary's stake has been recorded. At every level, an upline is eligible when its cap meets that level's threshold. At level 1, the upline must additionally have a remaining liquid LLGAME balance greater than zero. Thus, when the payer is the direct upline, the payer must retain a positive liquid balance after funding the stake; the amount just transferred into the new stake does not count as liquid balance. The cap thresholds are `A` at level 1, `2A` at level 2, `4A` at level 3, and so on. The cap includes both liquid account balance and the account's ordinary stake principal still held by the staking contract; that principal is not included in `balanceOf(account)`. `activeStakeOf` includes matured ordinary stakes whose principal has not yet been withdrawn and is decremented when principal is withdrawn. Dedicated `AIRDROP` stake principal is not included. An upline with no remaining ordinary stake can still qualify if its liquid LLGAME balance alone meets the cap threshold; withdrawing a stake does not remove an existing referral binding. `AIRDROP` is explicitly excluded from the walk and can never receive a referral share. Eligibility is checked at each level, and the first ineligible upline stops the walk. The walk also stops after the fixed maximum of ten levels. The sum of the individually rounded shares cannot exceed the rounded 20% referral budget.

The referral budget is `floor(20 × A / 100)` base units. Each level's share is rounded down in base units and calculated from the original stake amount, not from the previous upline's payout. Before per-level integer rounding, the ten-level sum is `19.98046875% × A`; rounding can only reduce the paid sum. Any non-zero budget remainder is immediately recorded as dedicated `AIRDROP` stake principal in the same stake call, using the originating stake's term and generating no further reward or referral budget. If the remainder rounds to zero base units, no dedicated stake or corresponding event is created. The contract pays no more than `20% × A`; the ten-level maximum is a separate fixed execution bound.

## 7. Deployment scheme

The deployment is deliberately split into two independent steps. First, anyone can publish the deployment contract with every launch parameter already fixed and with no BNB attached. Later, the same person or an unrelated funder sends exactly the predefined pool-funding amount to that contract. Receipt of that exact amount triggers the complete ecosystem launch in the funding transaction itself. No founder synchronization, second signature or parameter hand-off is required.

The deployment contract is a one-shot launcher, not an administrator. Its constructor fixes every address and parameter used by the launch, including `AUTHORS`, `AIRDROP`, `AUTHORS_SUPPLY`, all staking and referral settings, the PancakeSwap factory/router/WBNB addresses and `POOL_BNB`. Each launch parameter is stored as a constant or immutable; the only mutable state is the one-way `launched` flag, which has no setter. There is no owner, upgrade path or privileged activation caller. The funder cannot change any launch parameter and receives no special rights.

### 7.1 Publish the deployment contract without attached BNB

1. Before publication, all values listed in section 8.2 are resolved. In particular, `AUTHORS` and `AIRDROP` are final addresses, and `POOL_BNB` is an exact integer amount in wei. No parameter is supplied later by the funder.
2. The deployer publishes the deployment contract with those values in its constructor. The constructor is not payable, so the deployment transaction cannot attach BNB as constructor value. The launcher does not intentionally receive funding at publication. Forced BNB sent to its predictable address before deployment is an unsolicited balance and is not part of the activation amount. The launcher does not create the token, staking contract or pair at this stage.
3. The source and constructor arguments are verified and published. Anyone can independently inspect the immutable values and calculate the deployment contract's address before deciding whether to fund it. The publisher pays the gas for this separate publication transaction; no BNB is attached as constructor value. As noted above, forced BNB sent to the predicted address is an unsolicited balance, not launch funding.

The deployment contract itself creates no child contracts before activation. Its first two `CREATE` operations are reserved for the token and staking contract, so their addresses can be predicted from the deployment contract address and its initial contract nonce. The predicted PancakeSwap pair address is public too: the factory's `createPair` function does not require either token address to contain token code, so a third party can create the pair before activation. A third party can also donate WBNB to that pair. Unsynchronized excess is skimmed to `DEAD`; WBNB already synchronized into reserves remains as a donation and affects the opening price, but does not prevent activation unless it would overflow the pair's `uint112` reserve. Section 7.2 accounts for both cases.

### 7.2 Activate by exact-value funding

The activation transaction is a native BNB transaction with empty calldata sent to the deployment contract and carrying exactly `POOL_BNB`. The contract's payable `receive()` function checks both that it has not already launched and that `msg.value == POOL_BNB`. A wrong amount or a second attempt reverts the whole transaction, including the incoming BNB. The first valid transfer executes the launch sequence below; any failed check or external call reverts the entire activation, leaving the deployment contract available for a later valid attempt.

The funding sender must also have enough BNB to pay the activation transaction's gas. EVM gas is paid by the transaction sender to the network; it is not part of `msg.value`, is not transferred to the deployment contract and cannot be spent by it as pool liquidity. Thus the sender's total outlay is `POOL_BNB` plus the actual network transaction fee, while the contract receives exactly `POOL_BNB`. The transaction must be submitted with enough gas for deployment; Solidity's 2,300-gas `transfer()`/`send()` stipend is not sufficient for this operation.

```solidity
// Deployment contract, sketch — constructor fixes every parameter;
// the first exact-value receive triggers the complete launch.
contract Deployment {
    address immutable FACTORY;
    address immutable ROUTER;
    address immutable WBNB;
    address immutable AUTHORS;
    address immutable AIRDROP;
    uint256 constant UNIT = 1e9;
    uint256 constant POOL_SUPPLY = 1_000_000 * UNIT;
    uint256 constant DESIGN_TOTAL_SUPPLY = 340000000000000000000000000000000000000; // 3.4e38 base units

    uint256 immutable POOL_BNB;
    uint256 immutable TOTAL_SUPPLY;
    uint256 immutable AUTHORS_SUPPLY;
    // IPancakeRouterLike exposes factory() and WETH() for network validation.
    // Every field of the staking and referral configuration
    // is copied into its own immutable in the constructor.

    bool public launched;

    constructor(
        address factory_, address router_, address wbnb_,
        address authors_, address airdrop_, uint256 poolBnb_,
        Params memory p_
    ) {
        // Constructor is non-payable: no BNB can be attached to publication.
        // Forced BNB sent to the predicted address may still exist and is not
        // included in the exact-value activation amount.
        require(factory_ != address(0) && router_ != address(0) && wbnb_ != address(0));
        require(factory_ != router_ && factory_ != wbnb_ && router_ != wbnb_);
        require(factory_.code.length > 0 && router_.code.length > 0 && wbnb_.code.length > 0);
        require(IPancakeRouterLike(router_).factory() == factory_);
        require(IPancakeRouterLike(router_).WETH() == wbnb_);
        require(poolBnb_ > 0 && poolBnb_ <= type(uint112).max);
        require(authors_ != address(0) && airdrop_ != address(0));
        require(authors_ != airdrop_);
        require(authors_ != factory_ && authors_ != router_ && authors_ != wbnb_ && authors_ != DEAD && authors_ != address(this));
        require(airdrop_ != factory_ && airdrop_ != router_ && airdrop_ != wbnb_ && airdrop_ != DEAD && airdrop_ != address(this));
        FACTORY = factory_;
        ROUTER = router_;
        WBNB = wbnb_;
        AUTHORS = authors_;
        AIRDROP = airdrop_;
        POOL_BNB = poolBnb_;
        // Supply and stake amounts are base units (9 decimals).
        require(p_.totalSupply == DESIGN_TOTAL_SUPPLY);
        require(p_.authorsSupply > 0 && p_.authorsSupply < p_.totalSupply - POOL_SUPPLY);
        uint256 creatorReward = (p_.authorsSupply * 288) / 100;
        uint256 creatorReferral = (p_.authorsSupply * 20) / 100;
        require(p_.totalSupply - POOL_SUPPLY > p_.authorsSupply + creatorReward + creatorReferral);
        TOTAL_SUPPLY = p_.totalSupply;
        AUTHORS_SUPPLY = p_.authorsSupply;
        // Copy every remaining p_ field to a dedicated immutable.
    }

    receive() external payable {
        require(!launched, "ALREADY_LAUNCHED");
        require(msg.value == POOL_BNB, "WRONG_FUNDING_AMOUNT");
        launched = true; // set before external calls; a revert rolls this back
        _activate();
    }

    function _activate() private {
        // 1. Predict the addresses needed by the immutable cross-references.
        //    EIP-161 gives a newly deployed contract nonce 1. No earlier CREATE
        //    is allowed, so these are this contract's first two CREATE addresses.
        address token   = _createAddress(address(this), 1);
        address staking = _createAddress(address(this), 2);
        address pair    = _pairFor(FACTORY, token, WBNB); // factory CREATE2

        require(AUTHORS != token && AUTHORS != pair && AUTHORS != ROUTER && AUTHORS != staking && AUTHORS != DEAD && AUTHORS != address(this) && AUTHORS != AIRDROP);
        require(AIRDROP != token && AIRDROP != pair && AIRDROP != ROUTER && AIRDROP != staking && AIRDROP != DEAD && AIRDROP != address(this));
        address[6] memory excluded = [
            pair, ROUTER, staking, DEAD, address(this), AIRDROP
        ];

        // 2. Deploy the locked contracts with all cross-references fixed.
        require(address(new LLGAME(
            excluded, staking, address(this),
            TOTAL_SUPPLY, POOL_SUPPLY + AUTHORS_SUPPLY
        )) == token);
        require(address(new Staking(
            token, AIRDROP, STAKING_PARAMS, REFERRAL_PARAMS
        )) == staking);

        // 3. Obtain the canonical pair. Anyone may have pre-created it after
        //    this launcher's address became public, so do not assume createPair
        //    will succeed. Reuse only the exact factory-computed pair.
        address existing = IFactory(FACTORY).getPair(token, WBNB);
        if (existing == address(0)) {
            require(IFactory(FACTORY).createPair(token, WBNB) == pair);
        } else {
            require(existing == pair);
        }

        // Remove unsynchronized donations. A WBNB donation already committed
        // to reserves by sync() cannot be skimmed; accept it as a locked donation.
        // It increases the WBNB reserve and changes the opening reserve ratio.
        IPair(pair).skim(DEAD);
        require(IPair(pair).totalSupply() == 0);
        (uint112 reserve0, uint112 reserve1,) = IPair(pair).getReserves();
        address token0 = IPair(pair).token0();
        address token1 = IPair(pair).token1();
        require((token0 == token && token1 == WBNB) || (token0 == WBNB && token1 == token));
        uint256 tokenReserve = token0 == token ? reserve0 : reserve1;
        uint256 wbnbReserve = token0 == WBNB ? reserve0 : reserve1;
        require(tokenReserve == 0);
        require(IERC20(token).balanceOf(pair) == 0);
        require(IERC20(WBNB).balanceOf(pair) == wbnbReserve);
        require(wbnbReserve + POOL_BNB <= type(uint112).max);

        IWBNB(WBNB).deposit{value: POOL_BNB}();
        IERC20(WBNB).transfer(pair, POOL_BNB);
        IERC20(token).transfer(pair, POOL_SUPPLY);
        IPair(pair).mint(DEAD); // initial LP position goes to DEAD; MINIMUM_LIQUIDITY is locked at address(0)

        // 4. Open the creators' 1080-day stake for the fixed AUTHORS address.
        IERC20(token).approve(staking, AUTHORS_SUPPLY);
        IStaking(staking).stake(AUTHORS_SUPPLY, 1080 days, AUTHORS);

        // 5. Verify the resulting state before activation can succeed.
        require(IERC20(token).totalSupply() == TOTAL_SUPPLY);
        require(IERC20(token).balanceOf(staking) == TOTAL_SUPPLY - POOL_SUPPLY);
        require(IERC20(token).balanceOf(AIRDROP) == 0);
        require(IStaking(staking).activeStakeOf(AUTHORS) == AUTHORS_SUPPLY);
        require(IERC20(token).balanceOf(address(this)) == 0);
        require(IPair(pair).balanceOf(DEAD) == IPair(pair).totalSupply() - 1000);
    }
}
```

The sketch omits routine validation, safe-transfer wrappers, concrete parameter structs and exact constructor signatures. The constructor's reserve validation uses the same integer reward and referral allocation arithmetic as the staking contract. Percentage allocations are rounded down in base units, as shown by the integer divisions in the sketch. Production code must also validate every immutable parameter, use safe-transfer wrappers, and implement the omitted helper functions and concrete parameter structs. The key deployment properties are the non-payable publication constructor, immutable launch configuration, exact-value one-shot `receive()` trigger and atomic launch body.

Why each step holds a guarantee:

| Step | Guarantee held |
|---|---|
| Deployment contract published separately without attached BNB | The launch configuration can be inspected before anyone funds it; the launcher has not created the token, staking contract or launch LP position. Unsynchronized WBNB sent to a pre-created pair is cleared during activation; any WBNB already synchronized into reserves remains as a donation |
| Every launch value stored as a constant or immutable | Neither the deployer nor the funder can change `AUTHORS`, `AIRDROP`, pool funding or any economic parameter after publication |
| Exact `msg.value` check and one-shot `launched` flag | Only the predefined funding amount can activate the launch, and only once; a failed activation reverts the transfer |
| Nonce-predicted `CREATE` addresses from the deployment contract | The token's six-address `excluded` set and the staking contract's `TOKEN`, both fixed at construction, are correct by construction; the token can query the predicted staking contract's `activeStakeOf` view when deciding first-receipt bindings |
| Canonical pair obtained and checked during activation | A third party may pre-create the predictable pair or donate WBNB to it; the launcher reuses only the factory-computed pair, sends unsynchronized excess to `DEAD`, accepts synchronized WBNB as a donation, and requires zero LLGAME reserves and balances and zero LP supply |
| LP minted to the dead address | Liquidity is locked without a locker or owner; invariant 3 |
| Creators' stake opened in the activation transaction | The authors' allocation is locked for 1080 days by the same rules as every stake, with no key able to shorten it |
| Final `require` block | Supply, the split, the creators' stake, empty deployment-contract token balance and the LP position held at `DEAD` are facts of the activation transaction, not of a later audit |

### 7.3 After activation

1. Anyone can verify the deployment contract's source and constructor arguments, then verify the activation transaction and the deployed token, staking contract and pair on BscScan.
2. Anyone can verify the immutable `POOL_BNB` value, `excluded` membership of the six accounts, `TOKEN`, `AIRDROP` and the referral parameters, the absence of any owner or role in the token and staking contracts, the pair's final reserves and LP balances, the activation trace's pre-mint checks (zero LLGAME reserve and zero LP supply; a synchronized WBNB donation may already be present), the creators' stake, the dedicated `AIRDROP` stake ledger and the staking contract's balance against its ledgers. The initial liquidity mint sends the initial LP position to `DEAD` and mints no protocol-fee LP shares; any later `feeTo` minting follows PancakeSwap's factory-controlled rules.

After the activation sequence, the deployment contract retains none of the LLGAME or WBNB allocated to it for the launch and none of the `POOL_BNB` received in the activation transaction. It has no admin or withdrawal function. The activation sender receives no token allocation, LP position or administrative role merely by funding the launch. Any BNB forcibly sent to the deployment address outside its `receive()` function, or any unsolicited ERC-20 token transferred to it, is not part of the activation funding and may remain stranded because the launcher has no withdrawal function.

## 8. Parameters

### 8.1 Fixed by the design

| Parameter | Value |
|---|---|
| `DECIMALS` | 9 |
| `TOTAL_SUPPLY` | 3.4 × 10^29 LLGAME, `3.4 × 10^38` base units, minted once |
| `POOL_SUPPLY` | 1,000,000 LLGAME (1,000,000 × 10^9 base units in Solidity) |
| Creators' stake | `AUTHORS_SUPPLY` staked for 1080 days under the ordinary staking rules: 288% reward allocation and 20% referral budget |
| Referral budget | 20% of each ordinary stake amount |
| Referral shares | `floor(10 × A / (100 × 2^(n−1)))` base units per level |
| Referral binding | On first receipt, the sender must have `activeStakeOf(sender) > 0` and neither endpoint may be in `excluded`; the same test applies to the payer when binding an unseen stake beneficiary |
| Referral payout eligibility | `balanceOf(upline) + activeStakeOf(upline) >= A × 2^(n−1)` at level `n`; level 1 additionally requires liquid balance `> 0`; no separate positive-stake condition |
| Staking terms | 180, 360 and 1080 days |
| Reward rates | 30%, 72% and 288% of principal over the respective terms |
| Reward release | Linear over the stake term, claimable by the staker as it accrues |
| Pool | PancakeSwap v2 LLGAME/WBNB pair; launch LP position sent to `DEAD` |
| Activation funding | Exactly `POOL_BNB` wei; the funder pays transaction gas separately |
| Stake entry point | `stake(amount, term, beneficiary)`, paid by the caller and owned by the beneficiary |
| Unpaid referral remainder | Any non-zero remainder is recorded immediately as dedicated `AIRDROP` stake principal, with the originating stake's term and no second reward or referral allocation |

### 8.2 Values fixed before publication

Every value in this table must be final before the deployment contract is published. `AUTHORS_SUPPLY` is encoded in 9-decimal base units in constructor arguments. No value is supplied by the activation sender or changed after publication. `AUTHORS` is distinct from all ecosystem and DEX infrastructure addresses but is not itself excluded. `AIRDROP` is distinct from every other excluded or DEX infrastructure address.

| Parameter | Meaning | Requirement |
|---|---|---|
| `AUTHORS` | Ordinary address that receives the creators' stake | Non-zero; distinct from the token, pair, staking contract, deployment contract, `DEAD`, `AIRDROP`, factory, router and WBNB; not included in the token's `excluded` set; must be an EOA or a smart wallet able to call the staking contract |
| `AUTHORS_SUPPLY` | Principal of the creators' 1080-day stake | Fixed in base units; after reserving its principal, 288% reward and 20% referral allocation, `R_launch` must remain positive |
| `AIRDROP` | Special address for dedicated referral-remainder stakes | Non-zero; distinct from `AUTHORS`, the token, pair, staking contract, deployment contract, `DEAD`, factory, router and WBNB; included in `excluded`, so it cannot be bound, refer or receive referral payouts; must be an EOA or a smart wallet able to call the staking contract |
| `POOL_BNB` | Exact BNB amount in wei sent by the activation transaction and wrapped into WBNB | Fixed positive integer amount |
| PancakeSwap addresses | Factory, router and WBNB contract addresses for the target BSC deployment | Fixed and verified against the intended network |

`AUTHORS` is not a protocol or ecosystem address. Because the creators' stake is opened by the excluded deployment contract during the atomic activation, before any public token interaction is possible, the normal `bindStaked` rule marks `AUTHORS` as an unbound root. It remains an ordinary account: it can act as a referrer and receive referral shares if its position in another holder's referral tree makes it eligible, but it is not specially excluded from token transfers or referral logic. Both `AUTHORS` and `AIRDROP` should be controlled by an EOA or by a smart wallet whose owners can submit calls to the staking contract; otherwise, their principal could mature but remain unwithdrawable.

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

The creators' stake follows the ordinary 1080-day rules. Since `AUTHORS` begins as an unbound root, it has no upline at activation; the full rounded 20% referral allocation (if non-zero) therefore becomes dedicated `AIRDROP` stake principal. The creators' stake also allocates its 288% reward. The unallocated reserve after activation is consequently:

```
R_launch = TOTAL_SUPPLY − POOL_SUPPLY − AUTHORS_SUPPLY
          − floor(288 × AUTHORS_SUPPLY / 100)
          − floor(20 × AUTHORS_SUPPLY / 100)

≈ TOTAL_SUPPLY − POOL_SUPPLY − 4.08 × AUTHORS_SUPPLY
```

The approximate factor `4.08` comprises the creators' 100% principal liability, 288% reward allocation and 20% referral allocation. The first expression is exact when the staking contract computes reward and referral allocations using the stated integer-floor operations. It assumes `AUTHORS_SUPPLY` is a valid 1080-day stake and the deployment transaction completes successfully. The staking contract's token balance immediately after activation is `TOTAL_SUPPLY − POOL_SUPPLY`; that balance is divided between the creators' principal, their allocated reward, their dedicated `AIRDROP` principal and `R_launch`. Dedicated `AIRDROP` stakes are tracked separately from `activeStakeOf`, which counts only ordinary stakes used in referral-cap calculations.

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

## 10. Residual risks at the ecosystem level

- **Contract beneficiaries and referral binding.** A stake belongs to its `beneficiary`, not its payer. A beneficiary must be able to call `claim` and `withdraw` itself; staking for a contract that cannot submit those calls can leave its principal and rewards permanently inaccessible. The same operational requirement applies to the fixed `AUTHORS` and `AIRDROP` addresses. Referral binding now requires the sender to have `activeStakeOf(sender) > 0` at the moment of the recipient's first receipt. A normal PancakeSwap V2 pair does not originate a stake call itself, so merely holding LLGAME does not make it a referrer. However, `stake(amount, term, beneficiary)` permits a payer to open a stake for any beneficiary, including a contract or DEX pair. A third party could therefore deliberately open a stake in a pool's name; because the pair cannot call `withdraw` itself, that principal may remain locked indefinitely and keep `activeStakeOf(pair) > 0`, allowing the pair to become a referrer for later first receipts. Once a binding exists, referral payout eligibility does not require the upline to retain a stake: the cap alone governs payout (plus the level-one liquid-balance condition). If such a pool is bound and meets the cap, a referral payout sent directly to it creates an excess balance that may be taken through the pair's public `skim` function. Preventing this deliberate edge case would require restricting contract beneficiaries or changing third-party staking; it is not solved by the binding-time check alone.
- **Airdrop address.** `AIRDROP` cannot refer or be referred. Any non-zero unpaid referral-budget remainder is accumulated on chain as dedicated stake principal under `AIRDROP`, using each originating stake's term and generating no additional reward or referral budget. Once principal matures, it is released to the `AIRDROP` address, whose key holder may use the funds for targeted airdrops; the contract cannot constrain off-chain distribution.
- **Pre-created pair donations.** A third party can create the predictable PancakeSwap pair before activation. Unsynchronized WBNB sent to it is skimmed to `DEAD`; WBNB that has already been synchronized into reserves cannot be removed by `skim` and remains as a donation. Such a donation changes the opening reserve ratio and price. The activation checks that the pair has no LP supply or LLGAME reserve and that adding `POOL_BNB` will not overflow the pair's `uint112` reserve.
- **Fixed economics.** Staking rates, terms and referral requirements cannot follow the market price. If market conditions change, the contracts continue to apply the published constants.
- **Regulatory reading.** Ten paid referral levels may be read as multi-level marketing. Each share is paid from the pre-minted reserve and is calculated from the stake that triggers it, not from a later entrant's principal. This economic distinction does not determine the applicable legal classification; that depends on the actual operation and relevant law.

## Sources

1. OpenZeppelin Contracts 5.x, ERC20 API. https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
2. EIP-161: state trie clearing, contract nonce starting at one. https://eips.ethereum.org/EIPS/eip-161
3. PancakeSwap developer docs, v2 Factory and Addresses. https://developer.pancakeswap.finance/contracts/v2/addresses
4. `PancakePair` source: `MINIMUM_LIQUIDITY`, `mint(to)`, `skim(to)` and reserve accounting. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakePair.sol
5. `PancakeFactory` source: `createPair` uses CREATE2 and does not require either token address to contain token code. https://github.com/pancakeswap/pancake-swap-core/blob/master/contracts/PancakeFactory.sol
6. Solidity documentation: `receive()` handles empty-calldata transfers; `send()` and `transfer()` forward only the 2,300-gas stipend. https://docs.solidity.org/en/latest/contracts.html
