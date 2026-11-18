# LLGAME ecosystem parameters

The values that shape the ecosystem, each listed once, with where it originates and how it travels through the contracts to where it takes effect. **D** is `contracts/LLGAMEDeployment.sol`, **T** is `contracts/LLGAME.sol` and **S** is `contracts/LLGAMEStaking.sol`. Amounts are in base units, 10^9 per LLGAME.

## Tokenomics base parameters

| Name | Value | Origin | Comment |
|---|---|---|---|
| `POOL_SUPPLY` | 10,000 LLGAME | D `constant` | D `_launch`, run by the constructor: reserve subtraction → D check `balanceOf(D) == POOL_SUPPLY` → D `_addLiquidity`, run by every funding round, sends parts to the pair, tracked in `poolSupplied`, which reaches `POOL_SUPPLY` in the closing round → D `abort` burns the rest |
| `AUTHORS_SUPPLY` | 500,000 LLGAME | D `constant` | D `_launch` reserve subtraction → `approve(s, …)` → `s.stake(AUTHORS_SUPPLY, …)` → S `_stake` `amount`, giving a reward of 1,440,000, a budget of 100,000, and, the staker being a root without uplines, an AIRDROP remainder of 100,000 with a reward of 288,000 → D check on `activeStakeOf(AUTHORS)` |
| `POOL_BNB_SUPPLY` | 16.9 BNB, `16_900_000_000_000_000_000` wei, ~$10,000 at 591.77 USDT per BNB | D constructor argument `poolBnbSupply_` | Checked in D `> 0`, `≤ uint112.max` → D `immutable POOL_BNB_SUPPLY` → D `_addLiquidity` (`target = POOL_SUPPLY × funded / POOL_BNB_SUPPLY`) → D `receive` close condition `funded ≥ POOL_BNB_SUPPLY`. Never leaves D |

## Tokenomics algorithmic parameters

| Name&nbsp;&nbsp;&nbsp;&nbsp; | Value | Origin | Comment |
|---|---|---|---|
| Term | 1080 days | S `constant` `TERM` | S `_open` stamps every new stake, the AIRDROP remainder stake included, with `StakeInfo.start` → S `_accrued` (the reward accrues until `start + TERM`) and `withdraw` (matured at `start + TERM`). S `delegateStake` parts keep the original `start` |
| Reward rate | 288 % (8% month) | S `constant` `RATE` | S `_stake` `reward = amount × RATE / 100` and `airdropReward = remainder × RATE / 100` → `StakeInfo.reward` → S `_accrued`, `_claim`, `withdraw`, and the pro-rata split in S `delegateStake` |
| Minimum principal | 72,000,000 base units | S `constant` `MIN_STAKE` | S `_stake` → S `delegateStake` (both parts). The S AIRDROP remainder stake bypasses it because `_open` is direct |
| `REFERRAL_PERCENT` | 20 | S `constant` | S `_stake` `budget = amount × 20 / 100` → reserve deduction → `remainder = budget − paid` → AIRDROP remainder stake |
| Referral level share | `A / 10 >> (n−1)` | S `_payReferrals` literal `10` and shift | → `TOKEN.transfer(upline, share − cost)` → `paid` |
| Referral eligibility threshold | `1 << (n−1)` LLGAME | S `_payReferrals` from `UNIT` | Compared separately with `TOKEN.balanceOf(upline)` and `activeStakeOf[upline]`. An upline that fails is passed over and the walk goes on |
| Referral gas charge | `gas × min(tx.gasprice, MAX_GAS_PRICE) × bnbPrice`, the gas measured since the previous charge | S `_payReferrals` `gasleft()` differences | S `_payReferrals` ends the walk before the first level whose share is not above this cost, takes it, within the allowance, from the share of every level examined → one `TOKEN.transfer(msg.sender, refund)` → `paid`. About 14,900 gas per paid level, reported by `test_levelGasMeasured` under `forge test --isolate -vv` |
| `MAX_GAS_PRICE` | 0.5 gwei | S `constant` | S `_payReferrals` `min(tx.gasprice, MAX_GAS_PRICE)` |
| `REFUND_DIVISOR` | 10: the refund allowance is a tenth of the referral budget | S `constant` | S `_payReferrals` `allowance = amount × 20 / (100 × 10)`, reduced by every charge; a cost above what is left is cut to it |
| `PRICE_PERIOD` | 30 minutes | S `constant` | S `_bnbPrice`: at least a period after `_refTime`, and only when `PAIR.getReserves()` reports reserves last moved in an earlier block, stores the reference `_refPrice` (UQ112x112 base units per wei, ordered by S `immutable LLGAME_IS_TOKEN0`) and `_refTime`, one slot |
| `PRICE_GUARD_PERCENT` | 5 | S `constant` | S `_bnbPrice` returns the current price of `PAIR.getReserves()`, or `_refPrice` when that is non-zero and the current price × 95 exceeds it × 100, that is LLGAME more than 5% below its reference; a setting in that case is `_refPrice × 100 / 95`, otherwise the current price |

## Technical parameters

| Name | Origin | Comment |
|---|---|---|
| `PUBLISHER` | D `constructor` (`msg.sender`) | D `immutable PUBLISHER`, read through its getter alone: no call checks it |
| `AUTHORS` | D constructor argument `authors_` | Checked in D `_isFixed`, `≠ airdrop_` → D `immutable AUTHORS` → D `abort()` (only caller); D constructor → D `_launch(authors_, …)` as `s.stake(…, authors_)` → S `_stake` beneficiary → S `_open` stores `StakeInfo.staker` and `activeStakeOf[AUTHORS]` → S `_see(AUTHORS, D)` makes it a root, because D is excluded → D `_launch` check `activeStakeOf(authors_) == AUTHORS_SUPPLY`. S has no constant for it |
| `AIRDROP` | D constructor argument `airdrop_` | Checked in D `_isFixed`, `≠ authors_` → D `immutable AIRDROP`; D constructor → D `_launch(…, airdrop_)` as `new LLGAMEStaking(t, airdrop_, p)` → S `immutable AIRDROP` → S `excluded()`, S `_stake` (allowed as beneficiary, staker of remainder stakes), S `delegateStake` (caller refused, allowed as delegate) |
| Name / symbol | T constructor literals | "Legacy Life Game" / LLGAME. T `ERC20`, `ERC20Permit` domain |
