// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ILLGAMEReferral} from "./ILLGAMEReferral.sol";

interface ILaunchPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title LLGAME locked staking contract
/// @notice No owner, no setter, no pause. All values are constants or immutables. Keeps a ledger of its own for
///         every token, each opened once by `initialize`, and reads the referral forest from the referral contract
///         named at its construction.
contract LLGAMEStaking is ReentrancyGuardTransient {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant STAKE_TERM = 1080 days;
    uint256 private constant MIN_PRINCIPAL = 72_000_000;
    uint256 private constant REWARD_PERCENT = 288;
    uint256 private constant REFERRAL_PERCENT = 20;
    uint256 private constant PREMIUM_PERCENT = 10;       // the premium budget, and the top tier of the premium table
    uint256 private constant MAX_LEVELS = 30;            // the referral walk examines no upline above this level
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    struct StakeInfo {
        address staker;     // the beneficiary: claims the reward and withdraws the principal
        uint64 start;       // timestamp of the stake block; the reward accrues from it to start + STAKE_TERM
        uint128 principal;  // zero once withdrawn
        uint128 reward;     // allocated at stake time
        uint128 claimed;
    }

    /// @dev The beneficiary's signed agreement to `referrer`, as the referral contract's `bind` takes it.
    struct ReferralBinding {
        address referrer;
        string site;
        string nonce;
        string issuedAt;
        bytes signature;
    }

    /// @dev The payer's `ERC20Permit` signature approving the staking contract for the stake amount.
    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @dev One token's ledger. `airdrop` is zero until the ledger is opened.
    struct Ledger {
        address airdrop;
        address pair;          // names the token and WBNB as its tokens: an ecosystem account, never called again
        address deployment;    // the caller of initialize
        uint256 oneToken;      // 10^decimals, read once when the ledger opens
        uint256 reserve;       // the unallocated stake reserve
        uint256 nextStakeId;
        mapping(uint256 => StakeInfo) stakes;
        mapping(address => uint256) activeStakeOf;
    }

    ILLGAMEReferral public immutable REFERRAL;
    address public immutable WBNB;

    mapping(address token => Ledger) private _ledgerOf;

    // Every event is indexed by its token and the accounts it concerns, so a ledger's logs are found by token and
    // account; stake ids and amounts are data.

    /// @dev `reserve` is the first reserve as received.
    event Initialized(
        address indexed token, address indexed airdrop, address indexed pair, address deployment, uint256 reserve
    );
    event Staked(address indexed token, address indexed staker, address indexed payer, uint256 stakeId, uint256 amount);
    /// @dev `staker` is the delegating staker; for a full delegation the two stake ids are equal.
    event StakeDelegated(
        address indexed token,
        address indexed delegate,
        address indexed staker,
        uint256 stakeId,
        uint256 delegatedStakeId,
        uint256 amount
    );
    /// @dev The principal returned and the unclaimed reward paid with it, in one transfer.
    event Withdrawn(address indexed token, address indexed staker, uint256 stakeId, uint256 principal, uint256 reward);
    /// @dev Once for each upline the walk of stake `stakeId` pays: its level share and its premium award, summing to
    ///      the transfer made. None for an upline passed over nor for the remainder's transfer to AIRDROP, which
    ///      the token's Transfer records.
    event ReferralPaid(
        address indexed token,
        address indexed upline,
        address indexed staker,
        uint256 stakeId,
        uint256 level,
        uint256 share,
        uint256 award
    );

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidParameter();
    error InvalidPair();
    error InvalidAmount();
    error InvalidBeneficiary();
    error ReserveShort();
    error NotStaker();
    error AlreadyWithdrawn();
    error NotMatured();
    error BindOutOfGas();

    constructor(address referral, address wbnb) {
        if (referral.code.length == 0 || wbnb == address(0)) revert InvalidParameter();
        REFERRAL = ILLGAMEReferral(referral);
        WBNB = wbnb;
    }

    // ------------------------------------------------------------------ views

    function airdropOf(address token) external view returns (address) { return _ledgerOf[token].airdrop; }

    function pairOf(address token) external view returns (address) { return _ledgerOf[token].pair; }

    function deploymentOf(address token) external view returns (address) { return _ledgerOf[token].deployment; }

    function reserve(address token) external view returns (uint256) { return _ledgerOf[token].reserve; }

    function nextStakeId(address token) external view returns (uint256) { return _ledgerOf[token].nextStakeId; }

    function activeStakeOf(address token, address account) external view returns (uint256) {
        return _ledgerOf[token].activeStakeOf[account];
    }

    function stakeInfo(address token, uint256 stakeId) external view returns (StakeInfo memory) {
        return _ledgerOf[token].stakes[stakeId];
    }

    /// @notice Accrued minus claimed, never negative.
    function claimable(address token, uint256 stakeId) external view returns (uint256) {
        StakeInfo storage record = _ledgerOf[token].stakes[stakeId];
        uint256 accrued = _accruedReward(record);
        return accrued > record.claimed ? accrued - record.claimed : 0;
    }

    /// @notice The fixed ecosystem-account set of a token's ledger: never paid a referral share, its stakes running
    ///         no walk.
    function excluded(address token, address account) external view returns (bool) {
        return _isEcosystemAccount(_ledgerOf[token], account);
    }

    // ----------------------------------------------------------------- ledger

    /// @notice Once per token: opens its ledger, fixing its AIRDROP, its pair of the token and WBNB and, as the
    ///         caller, its deployment contract, and pulls its first reserve, a non-zero amount, from the caller.
    function initialize(address token, address airdrop, address pair, uint256 amount) external nonReentrant {
        Ledger storage ledger = _ledgerOf[token];
        if (ledger.airdrop != address(0)) revert AlreadyInitialized();
        if (airdrop == address(0) || amount == 0) revert InvalidParameter();
        address wbnb = WBNB;
        address pairToken0 = ILaunchPair(pair).token0();
        address pairToken1 = ILaunchPair(pair).token1();
        bool tokenAndWbnb =
            (pairToken0 == token && pairToken1 == wbnb) || (pairToken0 == wbnb && pairToken1 == token);
        if (token == wbnb || !tokenAndWbnb) revert InvalidPair();
        ledger.oneToken = 10 ** IERC20Metadata(token).decimals();
        ledger.airdrop = airdrop;
        ledger.pair = pair;
        ledger.deployment = msg.sender;
        uint256 received = _collect(token, amount);
        ledger.reserve = received;
        emit Initialized(token, airdrop, pair, msg.sender, received);
    }

    /// @notice Any caller, the ledger open: pulls the amount from the caller into the token's reserve, irrevocably.
    function fund(address token, uint256 amount) external nonReentrant {
        Ledger storage ledger = _openedLedger(token);
        ledger.reserve += _collect(token, amount);
    }

    // ---------------------------------------------------------------- staking

    function stake(address token, uint256 amount, address beneficiary) external nonReentrant returns (uint256 stakeId) {
        uint256 received;
        (stakeId, received) = _openStake(token, amount, beneficiary);
        _payBudgets(token, stakeId, beneficiary, received);
    }

    function stakeWithPermit(
        address token,
        uint256 amount,
        address beneficiary,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256 stakeId) {
        // A front-run permit leaves the allowance in place; the transfer decides.
        try IERC20Permit(token).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        uint256 received;
        (stakeId, received) = _openStake(token, amount, beneficiary);
        _payBudgets(token, stakeId, beneficiary, received);
    }

    /// @notice Stakes as `stake` does, submitting the beneficiary's signed binding to `referrer` to the referral
    ///         contract before the walk; a refused binding does not fail the stake.
    function stakeWithReferral(
        address token,
        uint256 amount,
        address beneficiary,
        address referrer,
        string calldata site,
        string calldata nonce,
        string calldata issuedAt,
        bytes calldata signature
    ) external nonReentrant returns (uint256 stakeId) {
        uint256 received;
        (stakeId, received) = _openStake(token, amount, beneficiary);
        _bindReferrer(beneficiary, ReferralBinding(referrer, site, nonce, issuedAt, signature));
        _payBudgets(token, stakeId, beneficiary, received);
    }

    /// @notice Stakes as `stakeWithReferral` does, on the payer's signed approval as `stakeWithPermit` does: an
    ///         invited account's first stake in one transaction. Neither a failed permit nor a refused binding
    ///         fails the stake; the transfer decides.
    function stakeWithPermitAndReferral(
        address token,
        uint256 amount,
        address beneficiary,
        ReferralBinding calldata binding,
        PermitSignature calldata permit
    ) external nonReentrant returns (uint256 stakeId) {
        // A front-run permit leaves the allowance in place; the transfer decides.
        try IERC20Permit(token).permit(msg.sender, address(this), amount, permit.deadline, permit.v, permit.r, permit.s) {} catch {}
        uint256 received;
        (stakeId, received) = _openStake(token, amount, beneficiary);
        _bindReferrer(beneficiary, binding);
        _payBudgets(token, stakeId, beneficiary, received);
    }

    /// @notice The staker only: splits `amount` of the stake to `delegateAddress`, pro rata, both parts keeping the
    ///         unlock date; the accrued reward is paid to the staker first.
    function delegateStake(address token, uint256 stakeId, uint256 amount, address delegateAddress)
        external
        nonReentrant
        returns (uint256 delegatedStakeId)
    {
        Ledger storage ledger = _ledgerOf[token];
        StakeInfo storage record = ledger.stakes[stakeId];
        // AIRDROP stakes are not delegable
        if (record.staker != msg.sender || msg.sender == ledger.airdrop) revert NotStaker();

        uint256 principal = record.principal;
        if (principal == 0) revert AlreadyWithdrawn();
        if (amount > principal) revert InvalidAmount();
        // Both the delegated amount and the remainder must meet the minimum.
        if (amount < MIN_PRINCIPAL || (amount < principal && principal - amount < MIN_PRINCIPAL)) revert InvalidAmount();
        if (delegateAddress == address(0) || delegateAddress == msg.sender
            || (_isEcosystemAccount(ledger, delegateAddress) && delegateAddress != ledger.airdrop)
        ) revert InvalidBeneficiary();

        // Settle the accrued reward before changing ownership or splitting the stake.
        _claimReward(token, record);

        if (amount == principal) {
            // Full delegation: the existing stake record changes hands.
            record.staker = delegateAddress;
            delegatedStakeId = stakeId;
        } else {
            uint256 delegatedReward = uint256(record.reward) * amount / principal;
            uint256 delegatedClaimed = uint256(record.claimed) * amount / principal;
            record.principal = (principal - amount).toUint128();
            record.reward -= delegatedReward.toUint128();
            record.claimed -= delegatedClaimed.toUint128();

            delegatedStakeId = ledger.nextStakeId++;
            ledger.stakes[delegatedStakeId] = StakeInfo({
                staker: delegateAddress,
                start: record.start,
                principal: amount.toUint128(),
                reward: delegatedReward.toUint128(),
                claimed: delegatedClaimed.toUint128()
            });
        }

        ledger.activeStakeOf[msg.sender] -= amount;
        ledger.activeStakeOf[delegateAddress] += amount;

        emit StakeDelegated(token, delegateAddress, msg.sender, stakeId, delegatedStakeId, amount);
    }

    /// @notice The staker only: pays the accrued, unclaimed reward.
    function claim(address token, uint256 stakeId) external nonReentrant {
        StakeInfo storage record = _ledgerOf[token].stakes[stakeId];
        if (record.staker != msg.sender) revert NotStaker();
        _claimReward(token, record);
    }

    /// @notice The staker only, after the term: pays the principal and the unclaimed reward.
    function withdraw(address token, uint256 stakeId) external nonReentrant {
        Ledger storage ledger = _ledgerOf[token];
        StakeInfo storage record = ledger.stakes[stakeId];
        if (record.staker != msg.sender) revert NotStaker();
        uint256 principal = record.principal;
        if (principal == 0) revert AlreadyWithdrawn();
        if (block.timestamp < uint256(record.start) + STAKE_TERM) revert NotMatured();

        uint256 reward = record.reward - record.claimed;
        record.principal = 0;
        record.claimed = record.reward;
        ledger.activeStakeOf[msg.sender] -= principal;
        IERC20(token).safeTransfer(msg.sender, principal + reward);
        emit Withdrawn(token, msg.sender, stakeId, principal, reward);
    }

    // -------------------------------------------------------------- internals

    function _openedLedger(address token) private view returns (Ledger storage ledger) {
        ledger = _ledgerOf[token];
        if (ledger.airdrop == address(0)) revert NotInitialized();
    }

    function _isEcosystemAccount(Ledger storage ledger, address account) private view returns (bool) {
        return account == ledger.pair || account == address(this) || account == ledger.deployment || account == DEAD
            || account == ledger.airdrop;
    }

    /// @dev Pulls `amount` from the caller; returns what the contract's balance of the token grew by.
    function _collect(address token, uint256 amount) private returns (uint256) {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        return IERC20(token).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev The referral budget and the premium budget of a stake together.
    function _referralBudgets(uint256 principal) private pure returns (uint256) {
        return principal * REFERRAL_PERCENT / 100 + principal * PREMIUM_PERCENT / 100;
    }

    /// @dev Checks the stake, pulls its principal, allocates its reward and its referral and premium budgets from
    ///      the reserve and writes it under the beneficiary.
    function _openStake(address token, uint256 amount, address beneficiary)
        private
        returns (uint256 stakeId, uint256 received)
    {
        Ledger storage ledger = _openedLedger(token);
        if (amount < MIN_PRINCIPAL) revert InvalidAmount();
        if (beneficiary == address(0) || (_isEcosystemAccount(ledger, beneficiary) && beneficiary != ledger.airdrop)) {
            revert InvalidBeneficiary();
        }

        received = _collect(token, amount);
        if (received < MIN_PRINCIPAL) revert InvalidAmount();

        uint256 reward = received * REWARD_PERCENT / 100;
        uint256 budgets = _referralBudgets(received);
        uint256 unallocated = ledger.reserve;
        if (unallocated < reward + budgets) revert ReserveShort();
        ledger.reserve = unallocated - reward - budgets;

        stakeId = _registerStake(ledger, beneficiary, received, reward);
    }

    /// @dev Submits the beneficiary's signed binding to the referral contract. A refusal is caught and changes
    ///      nothing. A submission that ran out of gas is no refusal: it left the call less than a 63rd of the gas
    ///      at hand before it, the most a call that spent all it was given leaves, and the stake reverts, so no
    ///      stake opens unbound for want of gas.
    function _bindReferrer(address beneficiary, ReferralBinding memory binding) private {
        uint256 gasBefore = gasleft();
        try REFERRAL.bind(
            beneficiary, binding.referrer, binding.site, binding.nonce, binding.issuedAt, binding.signature
        ) {}
        catch {
            if (gasleft() < gasBefore / 63) revert BindOutOfGas();
        }
    }

    /// @dev Runs the referral walk and transfers what the two budgets leave unpaid to AIRDROP as liquid tokens,
    ///      opening no stake and allocating no reward.
    function _payBudgets(address token, uint256 stakeId, address beneficiary, uint256 received) private {
        Ledger storage ledger = _ledgerOf[token];
        uint256 budgets = _referralBudgets(received);
        // the stakes of an ecosystem account run no walk
        uint256 paid =
            _isEcosystemAccount(ledger, beneficiary) ? 0 : _payUplines(token, ledger, beneficiary, stakeId, received);
        uint256 remainder = budgets - paid;
        if (remainder != 0) IERC20(token).safeTransfer(ledger.airdrop, remainder);

        emit Staked(token, beneficiary, msg.sender, stakeId, received);
    }

    function _registerStake(Ledger storage ledger, address staker, uint256 principal, uint256 reward)
        private
        returns (uint256 stakeId)
    {
        stakeId = ledger.nextStakeId++;
        ledger.stakes[stakeId] = StakeInfo({
            staker: staker,
            start: uint64(block.timestamp),
            principal: principal.toUint128(),
            reward: reward.toUint128(),
            claimed: 0
        });
        ledger.activeStakeOf[staker] += principal;
    }

    function _accruedReward(StakeInfo storage record) private view returns (uint256) {
        uint256 start = record.start;
        if (block.timestamp >= start + STAKE_TERM) return record.reward;
        return uint256(record.reward) * (block.timestamp - start) / STAKE_TERM;
    }

    function _claimReward(address token, StakeInfo storage record) private {
        uint256 accrued = _accruedReward(record);
        uint256 claimed = record.claimed;
        if (accrued <= claimed) return;
        record.claimed = accrued.toUint128();
        IERC20(token).safeTransfer(record.staker, accrued - claimed);
    }

    /// @dev Walks the staker's uplines as the referral contract records them, level by level. An upline is paid,
    ///      in one transfer recorded by one ReferralPaid, its level's share where it is eligible for it and its
    ///      premium award: the percent of the stake its tier of the premium table names less the highest percent
    ///      paid to a nearer upline, so the awards of a stake sum to its highest tier met, within PREMIUM_PERCENT.
    ///      What an upline is not due stays in the remainder and the walk goes on. Ends at a root or after level
    ///      MAX_LEVELS, the same whatever gas and gas price the call carries: the gas is the caller's, none of it
    ///      is measured, valued or refunded, and a call short of gas for the walk reverts whole. Returns the shares
    ///      and awards paid together.
    function _payUplines(address token, Ledger storage ledger, address staker, uint256 stakeId, uint256 principal)
        private
        returns (uint256 paid)
    {
        address upline = staker;
        uint256 levelShare = principal / 10;
        // level n needs balanceOf and activeStakeOf each >= (1 << (n - 1)) whole tokens, separately
        uint256 required = ledger.oneToken;
        uint256 paidPercent; // the highest premium percent paid so far, to a nearer upline
        for (uint256 level = 1; level <= MAX_LEVELS; level++) {
            upline = REFERRAL.referrerOf(upline);
            if (upline == address(0)) break;
            (uint256 share, uint256 tierPercent) = _uplineDue(token, ledger, upline, required, levelShare);
            uint256 award;
            if (tierPercent > paidPercent) {
                award = principal * (tierPercent - paidPercent) / 100;
                paidPercent = tierPercent;
            }
            if (share != 0 || award != 0) {
                paid += share + award;
                _payUpline(token, upline, staker, stakeId, level, share, award);
            }
            levelShare >>= 1;
            required <<= 1;
        }
    }

    /// @dev Transfers an upline its level share and premium award together and records the payout.
    function _payUpline(
        address token,
        address upline,
        address staker,
        uint256 stakeId,
        uint256 level,
        uint256 share,
        uint256 award
    ) private {
        IERC20(token).safeTransfer(upline, share + award);
        emit ReferralPaid(token, upline, staker, stakeId, level, share, award);
    }

    /// @dev What an upline is due at its level: `share`, the level's share where the upline's balance and active
    ///      stake each meet `required`, and `tierPercent`, the percent of the premium table its active stake
    ///      meets, whatever its balance. Both zero for an ecosystem account.
    function _uplineDue(address token, Ledger storage ledger, address upline, uint256 required, uint256 levelShare)
        private
        view
        returns (uint256 share, uint256 tierPercent)
    {
        if (_isEcosystemAccount(ledger, upline)) return (0, 0);
        uint256 activeStake = ledger.activeStakeOf[upline];
        if (levelShare != 0 && activeStake >= required && IERC20(token).balanceOf(upline) >= required) {
            share = levelShare;
        }
        tierPercent = _premiumPercent(activeStake / ledger.oneToken);
    }

    /// @dev The premium table: the percent of a stake awarded to an upline of that active stake, in whole tokens.
    function _premiumPercent(uint256 wholeTokens) private pure returns (uint256) {
        if (wholeTokens < 1_000) return 0;
        if (wholeTokens < 3_000) return 1;
        if (wholeTokens < 5_000) return 2;
        if (wholeTokens < 10_000) return 3;
        if (wholeTokens < 30_000) return 4;
        if (wholeTokens < 50_000) return 5;
        if (wholeTokens < 100_000) return 6;
        if (wholeTokens < 300_000) return 7;
        if (wholeTokens < 500_000) return 8;
        if (wholeTokens < 1_000_000) return 9;
        return PREMIUM_PERCENT;
    }
}
