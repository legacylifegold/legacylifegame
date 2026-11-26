# LLGAME ecosystem parameters

The values that shape the ecosystem, each listed once, with where it originates and how it travels through the contracts to where it takes effect. **D** is `contracts/LLGAMEDeployment.sol`, **T** is `contracts/LLGAME.sol` and **S** is `contracts/LLGAMEStaking.sol`. Amounts are in base units, 10^9 per LLGAME.

## Tokenomics base parameters

| Name | Value | Origin | Comment |
|---|---|---|---|
| `POOL_SUPPLY_CAP` | 1,000,000 LLGAME | D `constant` | D `setStaking`: reserve subtraction → D check `balanceOf(D) == POOL_SUPPLY_CAP` → D `setPoolAmounts` bound of `llgame`, the parts sent to the pair tracked in `poolLlgame` → D `close` and D `abort` fund the rest to the S reserve through S `fund` |
| `AUTHORS_SUPPLY` | 200,000 LLGAME | D `constant` | D `setStaking` reserve subtraction → S `initialize` → `approve(staking_, …)` → `launchStaking.stake(token, AUTHORS_SUPPLY, AUTHORS)` → S `_openStake` `amount`, giving a reward of 576,000, a referral budget of 40,000, a premium budget of 20,000 and, the staker being a root without uplines, a remainder of 60,000 transferred to AIRDROP → D check on `activeStakeOf(AUTHORS)` and on the balances of S and AIRDROP together, `TOTAL − POOL_SUPPLY_CAP` |
| Pool amounts | Set by `AUTHORS` during funding, any number of times | D `setPoolAmounts` arguments `llgame`, `bnb` | Checked in D `≥ poolLlgame`, `≥ poolBnb`, `llgame ≤ POOL_SUPPLY_CAP` → stored, nothing moved → D `receive`, `AUTHORS` only, adds its BNB to `poolBnb`, brings `poolLlgame` to `llgame × poolBnb / bnb` and sends both additions to the pair. Their ratio is the launch price |

## Tokenomics algorithmic parameters

| Name&nbsp;&nbsp;&nbsp;&nbsp; | Value | Origin | Comment |
|---|---|---|---|
| Term | 1080 days | S `constant` `STAKE_TERM` | S `_registerStake` stamps every new stake with `StakeInfo.start` → S `_accruedReward` (the reward accrues until `start + STAKE_TERM`) and `withdraw` (matured at `start + STAKE_TERM`). S `delegateStake` parts keep the original `start` |
| Reward rate | 288 % (8% month) | S `constant` `REWARD_PERCENT` | S `_openStake` `reward = received × REWARD_PERCENT / 100` → `StakeInfo.reward` → S `_accruedReward`, `_claimReward`, `withdraw`, and the pro-rata split in S `delegateStake` |
| Minimum principal | 72,000,000 base units of any token | S `constant` `MIN_PRINCIPAL` | S `_openStake`, on the amount and on what the ledger received → S `delegateStake` (both parts) |
| `REFERRAL_PERCENT` | 20 | S `constant` | S `_referralBudgets` `principal × 20 / 100`, summed there with the premium budget → S `_openStake` reserve deduction → S `_payBudgets` `remainder = budgets − paid` → one transfer of the remainder to AIRDROP, no stake opened and no reward allocated |
| `PREMIUM_PERCENT` | 10 | S `constant` | S `_referralBudgets` `principal × 10 / 100`, travelling as `REFERRAL_PERCENT` does; also the top percent of the premium table |
| Referral level share | `A / 10 >> (n−1)` | S `_payUplines` literal `10` and shift | → S `_uplineDue` grants it to an eligible upline → S `_payUpline` transfers it, in one transfer with the upline's premium award, and emits `ReferralPaid` with the level, the share and the award → `paid` |
| Referral eligibility threshold | `1 << (n−1)` LLGAME | S `_payUplines` from the ledger's `oneToken`, `10 ** decimals()` read once in S `initialize` | S `_uplineDue` compares it separately with the token's `balanceOf(upline)` and the ledger's `activeStakeOf[upline]`; an ecosystem account fails it whatever it holds. An upline that fails is passed over and the walk goes on |
| Premium tier | Ten tiers, 1% to 10%, by active stake from 1,000 to 1,000,000 LLGAME | S `_premiumPercent` literals, in whole tokens of the ledger's `oneToken` | S `_uplineDue` reads the upline's `activeStakeOf` once, zero for an ecosystem account → S `_premiumPercent(activeStake / oneToken)` → S `_payUplines` awards `principal × (tierPercent − paidPercent) / 100` where `tierPercent` exceeds `paidPercent`, the highest percent paid so far, and raises `paidPercent` to it → S `_payUpline` → `paid` |
| `MAX_LEVELS` | 30 | S `constant` | S `_payUplines` reads the referral contract's `referrerOf` for at most 30 levels above the staker and ends before that only at a root. It reads neither `gasleft()`, `tx.gasprice` nor the pair: the gas is the payer's, none of it refunded, and a call short of it reverts whole. |
| Stake gas, no upline | About 154,200, bound 205,000 | Measured | The plain S `stake` of a first-time staker, its approval aside, the same whatever the amount. S `stakeWithPermit`, `stakeWithReferral` and `stakeWithPermitAndReferral` add the gas of the permit and of the referral contract's `bind` |
| Walk gas per level | Bound 38,000 | Measured | Added by each level examined, the `ReferralPaid` of a level paid included: about 6,500 where it pays nothing, 19,300 a level share, 19,600 a level share and a premium award, 36,700 a premium award to an account holding no LLGAME, the costliest and at most ten levels of a stake |
| Stake gas, 30 levels | 1,345,000 | 205,000 + 30 × 38,000 | No stake needs more; the costliest, ten awards to accounts holding no LLGAME and twenty level shares, takes about 908,800. The figures are those of transactions of their own, reported by `test_walkGasBoundedByLevel` under `forge test --isolate -vv`, which holds the bounds |

## Technical parameters

| Name | Origin | Comment |
|---|---|---|
| `PUBLISHER` | D `constructor` (`msg.sender`) | D `immutable PUBLISHER`, read through its getter alone: no call checks it |
| Token | D constructor argument `token_` | D `immutable` → D constructor resolves the pair of it and WBNB → D `launch` pulls its `totalSupply()` from the holder named in the call, on that holder's permit or approval → D `setStaking` passes it to S `initialize` |
| `AUTHORS` | D constructor argument `authors_` | D `immutable AUTHORS` → the only caller of D `launch`, `setStaking`, `setPoolAmounts`, `close` and `abort`; D `setStaking` → `launchStaking.stake(token, …, AUTHORS)` → S `_openStake` beneficiary → S `_registerStake` stores `StakeInfo.staker` and the ledger's `activeStakeOf[AUTHORS]` → D `setStaking` check `activeStakeOf(token, AUTHORS) == AUTHORS_SUPPLY`; D `abort` pays it the recovered BNB. S has no constant for it |
| Staking contract | D `setStaking` argument `staking_` | Checked in D: holds code, `airdropOf(token)` is zero, holds no LLGAME → D `staking`, set once → S `initialize(token, AIRDROP, pair, amount)` hands it the reserve with `AIRDROP`, the pair and D as its caller, then it receives the creators' stake and, at D `close` or `abort`, the rest of `POOL_SUPPLY_CAP` |
| Referral contract | S constructor argument `referral` | S `immutable REFERRAL` → S `stakeWithReferral` and S `stakeWithPermitAndReferral` submit the beneficiary's signed binding to its `bind` through S `_bindReferrer`, a refusal caught and a submission that left the call less than a 63rd of the gas at hand before it, out of gas, reverting the stake with `BindOutOfGas`, and S `_payUplines` reads its `referrerOf`. D does not know it |
| WBNB | S constructor argument `wbnb`; D `constant WBNB` | S `immutable WBNB` → S `initialize` refuses a pair whose `token0()` and `token1()` are not the token and WBNB |
| Launch pair | D constructor, the factory's pair of the token and WBNB | D `immutable pair` → D `setStaking` → S `initialize(token, airdrop, pair, amount)` stores it once for the token, its origin unproven → S `pairOf(token)` and S `excluded(token, …)`; S never calls it after `initialize` |
| `AIRDROP` | D constructor argument `airdrop_` | Checked in D `≠ authors_` → D `immutable AIRDROP` → D `setStaking` → S `initialize(token, airdrop, …)` stores it once for the token → D check against S `airdropOf(token)` → S `excluded(token, …)`, S `_openStake` (allowed as beneficiary), S `_payBudgets` (recipient of the remainder transfer, its own stakes running no walk), S `delegateStake` (caller refused, allowed as delegate) |
| Name / symbol | T constructor literals | "Legacy Life Game" / LLGAME. T `ERC20`, `ERC20Permit` domain |
