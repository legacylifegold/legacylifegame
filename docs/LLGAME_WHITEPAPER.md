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

- `AUTHORS_SUPPLY = 200,000` LLGAME - creators' stake, locked for 1080 days: an ordinary stake opened for the fixed `AUTHORS` address when the staking contract is set;
- up to `POOL_SUPPLY_CAP = 1,000,000` LLGAME paired with BNB in a launch liquidity pool, in the amounts `AUTHORS` sets during funding, whose liquidity provider (LP) tokens are sent to `DEAD` when funding closes;
- the remaining supply, with the pool's unused part at close, is held by the staking contract. After the creators' stake is opened, the unallocated part becomes the reserve that funds subsequent staking rewards and referral allocations.

Holders receive value through:

- staking for 1080 days, with rewards accruing over time and claimable as they accrue;
- the referral program: a referral budget and a premium budget of each stake, paid inside the stake call to the staker's uplines;
- gamified airdrops: any non-zero unpaid remainder of those budgets is transferred in the same call to the special `AIRDROP` address as liquid LLGAME, so the accumulated airdrop budget is visible on chain as its balance;

The operational ecosystem consists of the token, a staking contract, a referral contract and a DEX pair, brought together by a separate deployment contract. Two separately controlled addresses participate in its economics: `AUTHORS`, the ordinary beneficiary of the creators' stake, and `AIRDROP`, the special address for accumulated referral remainders.:

| Part | Role | Administration |
|---|---|---|
| Token (`LLGAME`) | OpenZeppelin v5 `ERC20`, `ERC20Burnable`, `ERC20Permit`, 9 decimals, no access control module, no transfer hook and no reference to another contract of the ecosystem | None: locked at publication |
| Pool | PancakeSwap v2 LLGAME/WBNB pair, launch LP position sent to `DEAD` at close | None: the pair is DEX code, its protocol `feeTo` share excepted |
| Staking | Holds the reserve and the ecosystem-account set; submits a beneficiary's signed referral binding to the referral contract; takes stakes paid by their caller for a beneficiary, splits a part of a stake to a delegate, or hands it the whole stake, at its staker's request, allocates rewards, pays referral shares and premium awards to eligible uplines, transfers any non-zero unpaid remainder of their budgets to `AIRDROP` inside the stake call | None: locked at launch |
| Referral | Standalone record of who referred whom, written on each account's own signature; references no token and no staking contract | None: locked at publication |
| Deployment contract | Takes the whole supply of the published token, funds the staking contract `AUTHORS` names and opens the creators' stake there, builds the pool from the amounts `AUTHORS` sets and closes at `AUTHORS`' call | Every call `AUTHORS`' alone; no right of its publisher, no upgrade path, no return of LLGAME to `AUTHORS` |
| `AUTHORS` address | Fixed beneficiary of the creators' stake and the one account able to call the deployment contract; to the token and the staking contract an ordinary account with no exclusion or privilege | Its key or multisig policy controls that account and every call of the deployment contract until close; it has no right over a locked contract |
| `AIRDROP` address | Special address receiving the unpaid remainders of the referral and premium budgets as liquid LLGAME for later airdrops; cannot participate in the referral program as referrer or referred account | Its key or multisig policy spends what it receives, and stakes, claims and withdraws under the common staking rules |

### 1.1 Terms

| Term | Meaning |
|---|---|
| Locked contract | A contract deployed final: no owner, admin role, settable parameter, pause, upgrade or administrator withdrawal; every table and threshold is a constant or immutable. Staking principal and rewards remain withdrawable only through the fixed user-facing rules |
| Ecosystem account | A fixed system address excluded from the referral program, never paid a referral share or a premium award and its stakes running no walk: the launch pair, staking contract, deployment contract, dead address and `AIRDROP` |
| Staker | The beneficiary of a stake: the account whose active stake it is, whose reward ledger it feeds, to which the principal returns and whose uplines the stake's referral walk pays |
| Payer | The caller of `stake`, whose LLGAME funds the stake; the staker itself in the common case |
| Stake reserve | LLGAME in the staking contract not allocated to any stake |
| Referral budget | 20% of each ordinary stake's amount, taken from the stake reserve at stake time and paid recursively to eligible uplines by the halving share formula; any non-zero unpaid remainder is transferred to `AIRDROP` |
| Premium budget | 10% of each ordinary stake's amount, taken from the stake reserve at stake time and paid to the uplines whose active stake meets a tier of the premium table (section 6); its unpaid remainder joins the referral budget's in the one transfer to `AIRDROP` |
| Operator | The party running the game; it cannot change the locked contracts or their payout rules |
| Deployment contract | A launcher bound at publication to the token and to `AUTHORS`, whose calls alone it takes: it pulls the supply, sets the staking contract, supplies the pool and closes (section 7) |
| Funding | From the setting of the staking contract until close or abort (section 7) |
| `derived` | Marks a statement that follows from the rules stated elsewhere, not a separate rule |

## 2. Invariants

Every part of the ecosystem is bound by the following; the requirements of sections 3 to 7 are consequences of these invariants.

1. **Locked at launch.** The token and the staking contract are locked contracts. No proxy, upgradeable part or contract-administration signer exists in the token or staking contracts; the deployment contract's calls are `AUTHORS`' alone and end at close, and the staking contract is the one `AUTHORS` names there, once.
2. **No mint after creation.** The token's constructor mints the whole supply and no function can mint again. Every staking reward and referral allocation is funded from the staking contract's pre-minted holdings.
3. **No administration of value.** No key can move LLGAME out of a locked contract except through its fixed rules: staking principal withdrawal, reward claim, referral payout and the transfer of the referral remainder to `AIRDROP`. From close, the launch LP position is irretrievably held at `DEAD`; during funding only an abort removes its liquidity, returning its BNB to `AUTHORS`; PancakeSwap may separately mint protocol-fee LP shares to its configured `feeTo` address under the DEX's own rules, as described in section 4. `AIRDROP` claims and withdraws under the common rules and has no administrative right over any contract.
4. **Fixed conditions.** The staking term and rate, the referral and premium budgets, the referral formula and the premium table, the fixed `AUTHORS` beneficiary, the `AIRDROP` address and the fixed ecosystem-account exclusion set are immutable or constants of the contracts that use them.
5. **Solvent by construction.** Nothing is owed beyond what is allocated: a stake reverts when the stake reserve cannot cover its reward and its referral and premium budgets; the referral walk pays eligible shares within the stake's referral budget and premium awards within its premium budget in the same call, and any unpaid part of both is transferred to `AIRDROP` in that call, so no part of the budgets stays owed. The sum of the staking contract's accounted ledgers—principal still held, allocated rewards not yet claimed and unallocated reserve—never exceeds its LLGAME balance. A direct token transfer to the staking contract outside `stake` and `fund` is an unsolicited donation: it is not credited to the reserve or any stake ledger and has no withdrawal path.
6. **Deterministic binding and payouts.** A referral binding is written only on the account's own signature over its referrer, once, and never where it would close a cycle; a plain token transfer binds nothing. Referral shares are paid to uplines whose liquid balance and `activeStakeOf` both meet the level's fixed threshold, down to the level at which the walk ends, and premium awards to uplines whose `activeStakeOf` meets a tier of the fixed premium table (section 6). No off-chain party can alter the binding, the shares, the awards or the thresholds, and the staker cannot either through its stake transaction: the walk reads neither its gas, its gas price nor the pool's price, and a transaction short of gas for it reverts whole. Distribution of the LLGAME `AIRDROP` receives is an off-chain activity and is not controlled by the contracts.
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
- `POOL_SUPPLY_CAP` is one part in 3.4 × 10^23 of the total supply. The pool is the initial DEX source of freely tradable LLGAME; the creators' principal is locked in staking, while reserve distributions occur only through the staking rules. Tokens subsequently circulate through ordinary transfers, staking payouts, referral payouts and any off-chain airdrops funded by the remainders `AIRDROP` receives.
- The launch LP tokens are held at the dead address, so that position is locked without a locker contract or owner. Swap fees remain in the pair's reserves; the PancakeSwap protocol may separately mint `feeTo` LP shares under its own factory-controlled fee mechanism.

## 5. Staking

A holder stakes an amount `A` for the fixed term of 1080 days, with `stake(amount, beneficiary)`. The caller is the payer: the amount is pulled from its balance. The beneficiary is the staker: the stake belongs to that account. In the common case, the caller names itself, but anyone can open a stake for anyone else. The staking contract allocates at stake time, out of the stake reserve, everything the stake will ever cost; a stake that the reserve cannot cover reverts. The staking contract is published with two immutables, the referral contract (section 6) and the wrapped native coin, WBNB, and is not bound to one token: it keeps for every token a ledger of its own, with its reserve, stakes, `activeStakeOf`, `AIRDROP` account, launch pair and deployment contract, and everything stated here of the staking contract is stated of its LLGAME ledger, its calls naming the token ahead of their other arguments. A token's ledger opens with `initialize(token, airdrop, pair, amount)`, which pulls a non-zero amount from its caller into the reserve and fixes with it, once, the token's `AIRDROP` account, its launch pair and, as the caller, its deployment contract; no stake of the token opens before. The pair named must name the token and WBNB as its two tokens, whatever liquidity it holds, and any other is refused; nothing more is proven of it, and the staking contract keeps it as an ecosystem account and never calls it again. The call is free to any holder of a token. For LLGAME the whole supply is held by its one holder and then by the deployment contract until that contract makes the call, so nobody else can make it first (`derived`). From then on its reserve is credited by `fund(amount)`, which pulls the amount from any caller irrevocably. Direct LLGAME transfers to the staking address are not treated as reserve deposits; they remain unaccounted surplus and cannot be withdrawn. Every amount pulled, a reserve or a principal, is credited as what the contract's balance of the token grew by, so a token that charges its transfers is accounted as received; a token whose balances change without a transfer is not supported, its ledger alone bearing the difference.

Every public `stake` or `stakeWithPermit` call must meet the minimum principal of **72,000,000 base units**, 0.072 LLGAME.

This limit targets an average accrued reward of at least one base unit per average BSC block, using the documented 0.45-second average block interval. It is a count of base units, the same for every token whatever its decimals.

| Allocation at stake time | Amount | Destination |
|---|---|---|
| Reward | 288% of `A`, that is 8% of `A` per 30 days | The staker's reward ledger, released linearly over the term |
| Referral budget | 20% of `A` (section 6) | Allocated from the stake reserve; eligible shares are paid immediately and the remainder is transferred to `AIRDROP` (section 6) |
| Premium budget | 10% of `A` (section 6) | Allocated from the stake reserve; awards are paid immediately to the uplines on a premium tier and the remainder joins the referral remainder in the transfer to `AIRDROP` (section 6) |

The reward accrues linearly from the stake block to the unlock, and the staker claims the accrued part at any time, capped by the allocated reward; the ledger keeps the claimed amount, so a fully claimed stake reads and claims cleanly. The principal is returned to the staker, with the unclaimed reward, at the end of the term, once. There is no early withdrawal and no compounding: a holder that wants to restake takes its payout and stakes again, which triggers new referral and premium budgets. The contract keeps `activeStakeOf[account]`, the sum of the account's stake principals still held by the staking contract, including matured stakes whose principal has not yet been withdrawn. It enters the upline's payout eligibility and sets its premium tier (section 6). It is incremented when a stake opens and decremented exactly once when that stake's principal is withdrawn. No separate staker flag or registration state is needed.

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

// the events, written in full: each is indexed by its token and the accounts it concerns
event Initialized(address indexed token, address indexed airdrop, address indexed pair, address deployment,
                  uint256 reserve);   // the first reserve as received
event Staked(address indexed token, address indexed staker, address indexed payer, uint256 stakeId, uint256 amount);
event StakeDelegated(address indexed token, address indexed delegate, address indexed staker,
                     uint256 stakeId, uint256 delegatedStakeId, uint256 amount);   // staker: the delegating one
event Withdrawn(address indexed token, address indexed staker, uint256 stakeId, uint256 principal, uint256 reward);
event ReferralPaid(address indexed token, address indexed upline, address indexed staker,
                   uint256 stakeId, uint256 level, uint256 share, uint256 award);   // section 6

constructor(address referral, address wbnb);

function REFERRAL() external view returns (address);   // the referral contract the walk reads
function WBNB() external view returns (address);       // the other token of every pair a ledger takes
function AIRDROP() external view returns (address);
function excluded(address account) external view returns (bool);         // the fixed ecosystem-account set

function stake(uint256 amount, address beneficiary) external returns (uint256 stakeId);
function stakeWithReferral(uint256 amount, address beneficiary, address referrer, string calldata site,
                           string calldata nonce, string calldata issuedAt, bytes calldata signature)
    external returns (uint256 stakeId);   // submits the beneficiary's signed binding first (section 6)
function initialize(address token, address airdrop, address pair, uint256 amount) external;   // once per token: links its ledger and pulls its first reserve
function fund(uint256 amount) external;   // any caller, once initialized: pulls its LLGAME into the reserve, irrevocably
function stakeWithPermit(uint256 amount, address beneficiary,
                         uint256 deadline, uint8 v, bytes32 r, bytes32 s) external returns (uint256 stakeId);
struct ReferralBinding { address referrer; string site; string nonce; string issuedAt; bytes signature; }
struct PermitSignature { uint256 deadline; uint8 v; bytes32 r; bytes32 s; }
function stakeWithPermitAndReferral(uint256 amount, address beneficiary, ReferralBinding calldata binding,
                                    PermitSignature calldata permit)
    external returns (uint256 stakeId);   // the payer's permit and the beneficiary's binding together
function delegateStake(uint256 stakeId, uint256 amount, address delegateAddress)
    external returns (uint256 delegatedStakeId);   // the staker only (section 5.3)
function claim(uint256 stakeId) external;      // the staker only: the accrued, unclaimed reward
function withdraw(uint256 stakeId) external;   // the staker only, after the term: the principal and the unclaimed reward

function stakeInfo(uint256 stakeId) external view returns (StakeInfo memory);
function claimable(uint256 stakeId) external view returns (uint256);   // accrued minus claimed, never negative
function activeStakeOf(address account) external view returns (uint256);
function reserve() external view returns (uint256);                    // the unallocated stake reserve
```

`stakeWithPermit` signs the payer's approval with `ERC20Permit` and does what `stake` does in one transaction. `stakeWithPermitAndReferral` does the same for `stakeWithReferral`, so an invited account's first stake, approval and binding included, is one transaction; a permit that fails, submitted ahead by someone else, leaves the allowance to decide and does not fail the stake by itself. Only the staker claims and withdraws: the payer has no right over the stake once it is open. Its staker may delegate all or part of it (section 5.3). Every event is indexed by its token and the accounts it concerns, so the logs of one ledger are found by token and by account; stake ids and amounts are their data. `Initialized` names, beside the token, `AIRDROP`, the pair and the deployment contract, the first reserve as received. `Staked` is indexed by staker and payer, `StakeDelegated` by the delegate and the delegating staker. `Withdrawn`, indexed by staker, names the stake, the principal returned and the unclaimed reward paid with it, the two summing to the transfer made. `ReferralPaid` records each upline's payout (section 6). `claim` and the remainder's transfer to `AIRDROP` emit no event of their own: the token's `Transfer` from the staking contract records the amount paid, and `stakeInfo` the state of the stake. The referral forest is read from the referral contract (section 6).

### 5.2 Stake procedure

`stake(amount, beneficiary)` runs these steps in this order; any failing check reverts the whole call, the transfers it has already made included, so the call needs no rollback of its own:

1. Check that `amount` is at least the minimum principal in section 8.1, and `beneficiary` is neither the zero address nor any ecosystem account other than `AIRDROP`. The caller must also choose a beneficiary able to call `claim` and `withdraw`; the contract cannot generically verify that an arbitrary smart wallet supports those calls.
2. Pull `amount` from the payer: `transferFrom(msg.sender, staking, amount)`, reverting on a refused or failed transfer. The principal is what the contract's balance of the token grew by, and it must also meet the minimum principal. Every later step is computed on it.
3. Allocate the reward, the referral budget and the premium budget from the stake reserve; revert when the reserve is short.
4. Write the ordinary stake under the beneficiary: `stakeId`, the principal, the stake block and the allocated reward; add the principal to `activeStakeOf[beneficiary]`.
5. When the call carries a referrer and the beneficiary's signature, submit them to the referral contract (section 6); a refused binding changes nothing and does not fail the stake. A submission that ran out of gas is no refusal: the stake reverts when the submission left less than a 63rd of the gas at hand before it, the most a call that spent all it was given leaves, so no stake opens unbound for want of gas.
6. Walk the beneficiary's uplines recursively, pay each eligible upline its level share and each upline on a premium tier its award (section 6), then, if the unpaid part of the two budgets is non-zero, transfer it to `AIRDROP` (section 6).
7. Emit `Staked` with the staker and payer.

### 5.3 Stake delegation

`delegateStake(stakeId, amount, delegateAddress)` splits an ordinary stake and hands the split part to another account, or, for the whole principal, hands the stake itself. It runs these steps in this order; any failing check reverts the whole call:

1. Check that the caller is the stake's staker, its principal is not withdrawn, `amount` is at least the minimum principal, and `amount ≤ principal`. If `amount < principal`, the principal remaining in the original stake must also be at least that minimum. Check also that `delegateAddress` is neither the zero address, the caller nor any ecosystem account other than `AIRDROP`.
2. Pay the caller the stake's accrued, unclaimed reward, as `claim` does, so that the reward accrued before delegation stays with the caller.
3. If `amount < principal`, write a new ordinary stake under the delegate with principal `amount`, the original stake block, reward allocation `floor(reward × amount / principal)` and claimed amount `floor(claimed × amount / principal)`; the original stake keeps the remainders of principal, reward and claimed amount. If `amount = principal`, make the delegate the staker of the stake itself, which keeps its `stakeId`, principal, reward and claimed amount, and open no new stake: `delegatedStakeId` is then `stakeId`. Either way, move `amount` from `activeStakeOf[caller]` to `activeStakeOf[delegate]`.
4. Emit `StakeDelegated`; for a full delegation its two stake IDs are equal.

Delegation moves no LLGAME and touches no reserve: no reward, referral budget or premium budget is allocated, no referral walk runs and nothing is transferred to `AIRDROP`. Both parts keep the original unlock date. A full delegation leaves no empty record behind under the caller, so a stake ID always names a stake with a staker able to claim it (`derived`). The delegated stake is ordinary in every other respect: only the delegate claims and withdraws it, and the delegate may delegate a part of it again. The delegated principal counts toward the delegate's level thresholds and premium tier and no longer toward the caller's (`derived`).

## 6. Referral program

The referral program is funded inside the stake call from two budgets taken from the stake reserve: the referral budget, 20% of the stake amount `A`, paid as level shares, and the premium budget, 10% of `A`, paid as premium awards. An LLGAME transfer runs no recipient code, so an upline cannot revert a stake or reenter the contract through token receipt; for a token that does run code on a transfer, every call of the staking contract that moves tokens is closed to reentry. The principal is pulled before the ordinary stake and its reserve allocation are recorded, and the walk runs after both (section 5.2); the remainder is transferred to `AIRDROP` once the shares and awards have been paid.

The referral bindings are kept by the referral contract, a standalone locked contract that references no token and no staking contract: it stores for an account the referrer that account has signed for, and answers queries.

```solidity
// Referral contract: interface sketch
event ReferralBound(address indexed account, address indexed referrer);

function bind(address account, address referrer, string calldata site, string calldata nonce,
              string calldata issuedAt, bytes calldata signature) external;            // any caller
function referrerOf(address account) external view returns (address);                  // zero while unbound
function shortenRootSearch(address account, uint256 maxHops) external;                             // any caller
function findRoot(address account) external view returns (address root, uint256 depth, uint256 hops);
```

A binding is the account's signature over its agreement to the referrer: an EIP-4361 message, signed as an EIP-191 personal message on the site of the game's dApp:

```
<host> wants you to sign in with your Ethereum account:
<account>

I agree that <referrer> is my referrer in Legacy Life Game.

URI: https://<host>
Version: 1
Chain ID: <chain id>
Nonce: <nonce>
Issued At: <time>
Resources:
- urn:llgame:referrer:<referrer>
```

The host is the `https` origin the account signed on without its scheme, its port included where it has one; both addresses carry their EIP-55 checksum, every line ends with a line feed and the last with none. `bind` rebuilds the message from its arguments and the chain it runs on, so an agreement signed for another chain binds nothing. Of the site it is passed the host alone, as `site`, and writes the `https` scheme of the URI itself: a signature made on an `https` site binds as signed, one made on a site of another scheme binds nothing. The host, the nonce and the time are passed as signed and not judged: an agreement binds whichever site collected it, and its nonce and time protect nothing on chain, the rule itself letting a binding take effect once. `bind` may be submitted by anyone and writes `referrerOf[account]` only when the signature is the account's own over exactly that message, the account has no referrer yet, and the referrer is neither the zero address, the account itself nor an account below it in the forest. The signature of a plain account is checked by ECDSA and that of a smart wallet by ERC-1271. A written binding is final: no function rewrites or removes it, and a signature for another referrer submitted afterwards is refused.

The signature is collected off chain: the game's dApp, opened by a referral link naming the referrer, asks the account to sign and keeps the first signature it is given. Whoever opens a stake for the account, the account itself or another payer, may pass the referrer and the signature, with the host of the site and the nonce and time it was signed with, along with the stake: the staking contract submits them to the referral contract before the walk, and a missing or refused signature leaves the account as it was without failing the stake. An unbound account stays bindable, by a later stake or by `bind` directly. Who pays a stake binds nothing, nor does a token transfer.

The staking contract reads `referrerOf` for the walk and applies its own exclusions to what it reads: `AIRDROP` and the other ecosystem accounts are never paid a referral share or a premium award and their stakes run no walk, whatever the referral contract holds for them. The bindings form a forest, and a binding could close a cycle only where the account already has referees, its referrer then possibly below it. `bind` therefore checks nothing more for an account with no referee, whose binding costs the same gas whatever the depth of its referrer's chain. For an account with referees it looks up the referrer's root and refuses the binding when that root is the account itself, the account, still unbound, being the root of everything below it; an account that already has referees stays bindable to any account not below it.

The root search follows last roots. An account's last root is the root a search found above it, saved with the steps to it, the number of bindings between the two. Bindings being final, a saved last root stays the account's ancestor at exactly those steps; it only stops being a root once it is bound in its turn, and the search goes on from it over its own last root or, where an account has none saved, over its referrer, each a hop. A search that took more than `SAVE_ROOT_AFTER_HOPS = 8` hops saves the root found, with the summed steps, as the last root of the account it started from, so the next search from there takes one hop; a shorter search writes nothing, and a shallow network pays for no saved root. The hops of a search therefore follow the number of roots bound since the last roots were saved, not the depth of the chain.

`shortenRootSearch(account, maxHops)`, open to any caller, climbs at most `maxHops` hops from the account, never past its root, and saves the ancestor reached, with its steps, as the account's last root where the climb went beyond its first hop. It is the maintenance call for a chain whose root search no longer fits one transaction: such a chain is advanced over several transactions, so no account stays unbindable for the depth of what is below it. No stake and no page of the dApp needs it otherwise.

`findRoot(account)` answers the account's root, its depth, the number of bindings between it and that root, and the hops a root search from it takes now; a root answers itself, zero and zero. The depth, up to `MAX_LEVELS`, prices the referral walk of the account's stake, and the hops price the root search of a binding to that account.

For a stake of amount `A`, the staking contract walks from the staker's direct upline upward. An upline is eligible for its level share when both its liquid balance and its `activeStakeOf` separately meet the level's threshold. The halving share schedule keeps the total payout within the 20% budget, while the doubling requirement limits eligibility at each successive level. At level `n` (starting at 1):

- `share(n) = (A / 10) >> (n − 1)`, that is `floor(A / (10 × 2^(n − 1)))`;
- `required(n) = (1 << (n − 1)) × 10^9` base units, that is `2^(n − 1)` LLGAME, a fixed amount independent of `A`;
- eligible only when `balanceOf(account) ≥ required(n)` and `activeStakeOf(account) ≥ required(n)` separately.

The walk is a filter, not a single chain: an upline that fails its level's threshold is passed over, its share staying in the remainder, and the walk goes on to the next upline, whose level number, share and threshold count the passed level too. A stake therefore reaches a farther upline over an undercapitalized account, at that upline's own higher threshold and halved share.

Beside its level share, an upline is due a premium award by its `activeStakeOf` alone, stakes delegated to it included, whatever its liquid balance, its level and its level share. The premium table names the percent of `A` for the active stake the upline holds, in whole LLGAME:

| Active stake of at least, LLGAME | Premium percent |
|---:|---:|
| 1,000 | 1% |
| 3,000 | 2% |
| 5,000 | 3% |
| 10,000 | 4% |
| 30,000 | 5% |
| 50,000 | 6% |
| 100,000 | 7% |
| 300,000 | 8% |
| 500,000 | 9% |
| 1,000,000 | 10% |

An upline whose tier names `p` percent is paid `floor(A × (p − q) / 100)`, `q` being the highest percent already paid to an upline nearer to the staker, zero until the first award. An upline whose tier does not exceed `q`, or whose active stake is below the first tier, is paid no award, and the walk goes on. The awards of one stake therefore sum to no more than the percent of the highest tier met along the walk, within the 10% premium budget, and the nearest upline on the top tier takes what is left of it (`derived`). An upline due a level share and an award is paid both in one transfer. Each upline paid is recorded by one `ReferralPaid`, indexed by token, upline and staker and naming the stake, the upline's level, its level share and its award, the two summing to that transfer; an upline passed over is recorded by none, and neither is the remainder's transfer to `AIRDROP`.

For example, #9 stakes 100 LLGAME under this chain, #1 its root and each account referred by the one before:

| Account | Active stake, LLGAME | Level | Level share, LLGAME | Premium award, LLGAME | Paid, LLGAME |
|---|---:|---:|---:|---:|---:|
| #8 | 100 | 1 | 10 | none: below every tier | 10 |
| #7 | 5,000 | 2 | 5 | 3: the 3% tier | 8 |
| #6 | 10 | 3 | 2.5 | none | 2.5 |
| #5 | 1,000 | 4 | 1.25 | none: its 1% is within the 3% paid | 1.25 |
| #4 | 5 | 5 | none: its stake is short of the 16 LLGAME of its level | none | 0 |
| #3 | 300,000 | 6 | 0.3125 | 5: the 8% tier less the 3% paid | 5.3125 |
| #2 | 500 | 7 | none: it holds no liquid LLGAME | none | 0 |
| #1 | 30,000 | 8 | 0.078125 | none: its 5% is within the 8% paid | 0.078125 |

The uplines are paid 19.140625 LLGAME of the 20 LLGAME referral budget and 8 LLGAME of the 10 LLGAME premium budget; the 2.859375 LLGAME left of both are transferred to `AIRDROP`.

The walk ends at the first of:

- a root: the current account has no referrer;
- level 30: no upline above level `MAX_LEVELS = 30` is examined, however long the chain.

The gas of the walk is the payer's, as of the whole stake transaction, and none of it is refunded. The walk measures no gas and reads neither the gas price nor the pool, so a stake pays the same shares to the same uplines in whatever transaction carries it; a transaction with too little gas for the walk reverts whole, the stake with it, and no walk is cut short. The level limit bounds that gas whatever the length of the chain: a stake with no upline costs the same gas whatever its amount, and each level examined adds a bounded amount, whether it pays a level share, a premium award, both or nothing. A share halved to zero, reached once `2^(n − 1) > A / 10`, pays nothing. The thresholds are 1 LLGAME, 2 LLGAME, 4 LLGAME, 8 LLGAME, and so on, doubling each level, up to `2^29` LLGAME at level 30.

Eligibility is evaluated after the stake principal has been pulled from the payer and the beneficiary's stake has been recorded; when the payer is the direct upline, the amount just transferred into the new stake does not count as its liquid balance. The threshold applies to the liquid balance and to `activeStakeOf` independently, not to their sum, and does not scale with the stake amount: the liquid balance is what the account can spend now, while `activeStakeOf` includes matured stakes whose principal has not yet been withdrawn and excludes that principal from its `balanceOf`. Both are decremented or spent respectively when principal is withdrawn or liquid funds leave. The sum of the individually rounded shares cannot exceed the rounded 20% referral budget.

The referral budget is `floor(20 × A / 100)` base units and the premium budget `floor(10 × A / 100)`. Each level's share is rounded down in base units and calculated from the original stake amount, not from the previous upline's payout. The eligibility threshold is independent of `A`: an upline whose balance or stake is below `2^(n − 1)` LLGAME is passed over however large the stake. With `m = floor(A / 10)`, when a chain pays every level until the share reaches zero, its shares sum to `2m − popcount(m)`, the number of one bits of `m` subtracted; this is at most `2m − 1` and never exceeds the budget `floor(A / 5) ≥ 2m` (`derived`). A shorter chain, or one cut at level 30, pays less. The remainder is therefore at least one base unit whenever `m > 0`. Whatever the two budgets leave unpaid, when non-zero, is transferred to `AIRDROP` in the same stake call as liquid LLGAME, opening no stake and allocating no reward; a remainder of zero base units transfers nothing. The contract pays no more than `20% × A` in shares and `10% × A` in awards (this holds automatically by the math definition).

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
    uint256 private constant AUTHORS_SUPPLY = 200_000 * 10 ** 9;
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
- verifies `airdropOf(token)` and `pairOf(token)` as passed, `activeStakeOf(AUTHORS) == AUTHORS_SUPPLY`, the balances of the staking contract and of `AIRDROP` together `TOTAL_SUPPLY − POOL_SUPPLY_CAP`, so that the budgets of the creators' stake, unpaid for want of an upline, reached `AIRDROP` and nowhere else, and its own balance of `POOL_SUPPLY_CAP`;
- enters `Funding`.

`AIRDROP` holds no LLGAME before that call, the deployment contract holding the whole supply (`derived`). These checks prove that the contract answers the interface of section 7.1 and recorded the creators' stake, not how it behaves afterwards: the staking contract is `AUTHORS`' choice, and the invariants of section 2 hold for the ecosystem only as far as the contract named keeps them. The deployment contract knows nothing of a referral contract; whether the staking contract uses one is its own matter. No pool call passes before `setStaking`.

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
| `AUTHORS_SUPPLY` | 200,000 LLGAME (`200,000 × 10^9` base units), predefined and not configurable |
| Creators' stake | `AUTHORS_SUPPLY` staked for 1080 days under the ordinary staking rules: 288% reward allocation, 20% referral budget and 10% premium budget |
| Referral budget | 20% of each ordinary stake amount |
| Premium budget | 10% of each ordinary stake amount |
| Premium award | The percent of `A` that the premium table of section 6 names for the upline's `activeStakeOf`, less the highest percent paid to a nearer upline |
| Referral shares | `(A / 10) >> (n−1)` base units per level |
| Referral binding | Written once on the account's own signature over its referrer, never closing a cycle; a plain token transfer binds nothing |
| Referral payout eligibility | At every level `n`, `balanceOf(upline) >= (1 << (n−1)) × 10^9` and `activeStakeOf(upline) >= (1 << (n−1)) × 10^9` base units (that is, `2^(n−1)` LLGAME each), applied separately, with no dependence on `A` |
| Referral walk end | A root, or after level `MAX_LEVELS`; an ineligible upline is passed over |
| `MAX_LEVELS` | 30, the highest level of upline a referral walk examines |
| Referral walk gas | The payer's, as of the whole stake transaction: not measured, not valued in LLGAME and not refunded |
| Staking term | 1080 days, the only term |
| Minimum ordinary stake principal | 72,000,000 base units of any token. Applies to every public stake call and to delegated stake portions |
| Reward rate | 288% of principal over the term |
| Reward release | Linear over the stake term, claimable by the staker as it accrues |
| Pool | PancakeSwap v2 LLGAME/WBNB pair; launch LP position sent to `DEAD` at close |
| Funding | BNB sent by `AUTHORS`, entering the pool with LLGAME in the proportion of the pool amounts `AUTHORS` set, until `AUTHORS` closes |
| Unpaid remainder | Whatever the referral and premium budgets leave unpaid, when non-zero, is transferred to `AIRDROP` in the stake call as liquid LLGAME, opening no stake and allocating no reward |

### 8.2 Values fixed before publication

Every value in this table must be final before the contract that takes it is published: the token, `AUTHORS` and `AIRDROP` are passed to the deployment contract's constructor, which hands `AIRDROP` to the staking contract with its reserve, and nothing changes them afterwards. `AIRDROP` is distinct from every other excluded or DEX infrastructure address.

| Parameter | Meaning | Requirement |
|---|---|---|
| `AUTHORS` | Address that receives the creators' stake and alone calls the deployment contract | Non-zero; not in the staking contract's `excluded` set; must be an EOA or a smart wallet able to call the staking contract and every call of the deployment contract |
| `AIRDROP` | Special address receiving the referral remainders | Non-zero; distinct from `AUTHORS`, the token, pair, staking contract, deployment contract, `DEAD`, factory and WBNB; included in `excluded`; must be an EOA or a smart wallet able to call the staking contract |
| Token | Address of the published LLGAME token | Holds the token's code; its whole supply is at one holder, whose permit or approval `AUTHORS` has for the launch |

## 9. Reserve accounting

The staking reserve is finite and is the source of every staking reward, referral payment and `AIRDROP` remainder. The contract allocates the full cost of each stake when that stake is opened. It never promises a reward or referral amount that has not already been reserved. In the formulas below, `floor(x)` denotes integer division with the same rounding used by the staking contract.

### 9.1 Cost of an ordinary stake

For a stake of principal `A`, the principal itself is transferred by the payer and is not taken from the unallocated reserve. The reserve funds the reward allocation, the 20% referral budget and the 10% premium budget:

| Reward allocation | Referral allocation | Premium allocation | Total reserve allocation |
|---:|---:|---:|---:|
| 288% of `A` | 20% of `A` | 10% of `A` | 3.18 × `A` |

The referral and premium allocations are fully spent at stake time: the shares and awards paid to uplines and the unpaid remainder transferred to `AIRDROP` leave the staking contract in the stake call, so no part of the 30% stays behind as a liability or returns to the reserve.

### 9.2 Reserve after the staking contract is set

When the staking contract is set, the deployment contract funds it with `TOTAL_SUPPLY − POOL_SUPPLY_CAP − AUTHORS_SUPPLY`, keeps `POOL_SUPPLY_CAP` for the pool and opens the creators' stake for `AUTHORS`.

The creators' stake follows the ordinary 1080-day rules. Since `AUTHORS` is unbound when its stake opens, it has no upline; the full 40,000 LLGAME referral allocation and 20,000 LLGAME premium allocation are therefore transferred to `AIRDROP`, 60,000 LLGAME in all. The creators' stake also allocates its 576,000 LLGAME reward. The unallocated reserve is then:

```
R_launch = TOTAL_SUPPLY − POOL_SUPPLY_CAP − AUTHORS_SUPPLY
          − floor(288 × AUTHORS_SUPPLY / 100)
          − floor(20 × AUTHORS_SUPPLY / 100) − floor(10 × AUTHORS_SUPPLY / 100)

         = 3.4 × 10^29 − 1,836,000 LLGAME
```

The subtraction comprises 1,000,000 LLGAME held for the pool, whose unused part returns to the reserve at close, and 200,000 LLGAME principal, 576,000 LLGAME reward, 40,000 LLGAME referral allocation and 20,000 LLGAME premium allocation for the creators' stake. The result is positive and exact with the stated integer-floor operations. The staking contract's token balance at that moment is `TOTAL_SUPPLY − POOL_SUPPLY_CAP − 60,000` LLGAME, the two budgets having left it for `AIRDROP`; that balance is divided between the creators' principal and reward and `R_launch`.

### 9.3 Capacity and duration

For a new ordinary stake of amount `A`, the unallocated reserve must cover `3.18 × A`. Ignoring integer rounding, the maximum cumulative principal amount that can be opened against a reserve `R` is therefore `R / 3.18`.

This is a cumulative stake-volume bound, not a simultaneous-stake limit or a calendar-lifetime guarantee. The actual duration depends primarily on aggregate new stake volume. Referral and premium eligibility changes the destination of the fixed allocations, not their reserve cost; restaking rewards or withdrawn principal can increase later stake volume, while principal withdrawals themselves do not replenish the reserve. The market price and available DEX liquidity may influence demand, but they do not mathematically guarantee a minimum reserve lifetime. The contract's enforceable guarantee is narrower and stronger: every accepted stake is fully allocated at entry, and a new stake reverts if its full reward, referral and premium allocation cannot be covered.

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
