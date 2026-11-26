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

    uint256 private constant TERM = 1080 days;
    uint256 private constant MIN_STAKE = 72_000_000;
    uint256 private constant RATE = 288;
    uint256 private constant REFERRAL_PERCENT = 20;
    uint256 private constant PREMIUM_PERCENT = 10;       // the premium budget, and the top tier of the premium table
    uint256 private constant MAX_LEVELS = 30;            // the referral walk examines no upline above this level
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    struct StakeInfo {
        address staker;     // the beneficiary: claims the reward and withdraws the principal
        uint64 start;       // timestamp of the stake block; the reward accrues from it to start + TERM
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
        uint256 unit;          // 10^decimals, read once when the ledger opens
        uint256 reserve;       // the unallocated stake reserve
        uint256 nextStakeId;
        mapping(uint256 => StakeInfo) stakes;
        mapping(address => uint256) activeStakeOf;
    }

    ILLGAMEReferral public immutable REFERRAL;
    address public immutable WBNB;

    mapping(address token => Ledger) private _ledgers;

    event Initialized(address indexed token, address indexed airdrop, address indexed pair, address deployment);
    /// @dev Also for an AIRDROP remainder stake: staker AIRDROP, payer the staking contract.
    event Staked(address token, uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount);
    event StakeDelegated(
        address token,
        uint256 indexed stakeId,
        uint256 indexed delegatedStakeId,
        address indexed delegate,
        address staker,
        uint256 amount
    );

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidParameter();
    error InvalidPair();
    error InvalidAmount();
    error InvalidBeneficiary();
    error ReserveShort();
    error NotStaker();
    error Withdrawn();
    error NotMatured();

    constructor(address referral, address wbnb) {
        if (referral.code.length == 0 || wbnb == address(0)) revert InvalidParameter();
        REFERRAL = ILLGAMEReferral(referral);
        WBNB = wbnb;
    }

    // ------------------------------------------------------------------ views

    function airdropOf(address token) external view returns (address) { return _ledgers[token].airdrop; }

    function pairOf(address token) external view returns (address) { return _ledgers[token].pair; }

    function deploymentOf(address token) external view returns (address) { return _ledgers[token].deployment; }

    function reserve(address token) external view returns (uint256) { return _ledgers[token].reserve; }

    function nextStakeId(address token) external view returns (uint256) { return _ledgers[token].nextStakeId; }

    function activeStakeOf(address token, address account) external view returns (uint256) {
        return _ledgers[token].activeStakeOf[account];
    }

    function stakeInfo(address token, uint256 stakeId) external view returns (StakeInfo memory) {
        return _ledgers[token].stakes[stakeId];
    }

    /// @notice Accrued minus claimed, never negative.
    function claimable(address token, uint256 stakeId) external view returns (uint256) {
        StakeInfo storage s = _ledgers[token].stakes[stakeId];
        uint256 accrued = _accrued(s);
        return accrued > s.claimed ? accrued - s.claimed : 0;
    }

    /// @notice The fixed ecosystem-account set of a token's ledger: never paid a referral share, its stakes running
    ///         no walk.
    function excluded(address token, address account) external view returns (bool) {
        return _excluded(_ledgers[token], account);
    }

    // ----------------------------------------------------------------- ledger

    /// @notice Once per token: opens its ledger, fixing its AIRDROP, its pair of the token and WBNB and, as the
    ///         caller, its deployment contract, and pulls its first reserve, a non-zero amount, from the caller.
    function initialize(address token, address airdrop, address pair, uint256 amount) external nonReentrant {
        Ledger storage l = _ledgers[token];
        if (l.airdrop != address(0)) revert AlreadyInitialized();
        if (airdrop == address(0) || amount == 0) revert InvalidParameter();
        address wbnb = WBNB;
        address t0 = ILaunchPair(pair).token0();
        address t1 = ILaunchPair(pair).token1();
        if (token == wbnb || !((t0 == token && t1 == wbnb) || (t0 == wbnb && t1 == token))) revert InvalidPair();
        l.unit = 10 ** IERC20Metadata(token).decimals();
        l.airdrop = airdrop;
        l.pair = pair;
        l.deployment = msg.sender;
        l.reserve = _pull(token, amount);
        emit Initialized(token, airdrop, pair, msg.sender);
    }

    /// @notice Any caller, the ledger open: pulls the amount from the caller into the token's reserve, irrevocably.
    function fund(address token, uint256 amount) external nonReentrant {
        Ledger storage l = _opened(token);
        l.reserve += _pull(token, amount);
    }

    // ---------------------------------------------------------------- staking

    function stake(address token, uint256 amount, address beneficiary) external nonReentrant returns (uint256 stakeId) {
        uint256 received;
        (stakeId, received) = _begin(token, amount, beneficiary);
        _finish(token, stakeId, beneficiary, received);
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
        (stakeId, received) = _begin(token, amount, beneficiary);
        _finish(token, stakeId, beneficiary, received);
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
        (stakeId, received) = _begin(token, amount, beneficiary);
        try REFERRAL.bind(beneficiary, referrer, site, nonce, issuedAt, signature) {} catch {}
        _finish(token, stakeId, beneficiary, received);
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
        (stakeId, received) = _begin(token, amount, beneficiary);
        try REFERRAL.bind(
            beneficiary, binding.referrer, binding.site, binding.nonce, binding.issuedAt, binding.signature
        ) {} catch {}
        _finish(token, stakeId, beneficiary, received);
    }

    /// @notice The staker only: splits `amount` of the stake to `delegateAddress`, pro rata, both parts keeping the
    ///         unlock date; the accrued reward is paid to the staker first.
    function delegateStake(address token, uint256 stakeId, uint256 amount, address delegateAddress)
        external
        nonReentrant
        returns (uint256 delegatedStakeId)
    {
        Ledger storage l = _ledgers[token];
        StakeInfo storage s = l.stakes[stakeId];
        if (s.staker != msg.sender || msg.sender == l.airdrop) revert NotStaker(); // AIRDROP stakes are not delegable

        uint256 principal = s.principal;
        if (principal == 0) revert Withdrawn();
        if (amount > principal) revert InvalidAmount();
        // Both the delegated amount and the remainder must meet the minimum.
        if (amount < MIN_STAKE || (amount < principal && principal - amount < MIN_STAKE)) revert InvalidAmount();
        if (delegateAddress == address(0) || delegateAddress == msg.sender
            || (_excluded(l, delegateAddress) && delegateAddress != l.airdrop)
        ) revert InvalidBeneficiary();

        // Settle the accrued reward before changing ownership or splitting the stake.
        _claim(token, s);

        if (amount == principal) {
            // Full delegation: the existing stake record changes hands.
            s.staker = delegateAddress;
            delegatedStakeId = stakeId;
        } else {
            uint256 dReward = uint256(s.reward) * amount / principal;
            uint256 dClaimed = uint256(s.claimed) * amount / principal;
            s.principal = (principal - amount).toUint128();
            s.reward -= dReward.toUint128();
            s.claimed -= dClaimed.toUint128();

            delegatedStakeId = l.nextStakeId++;
            l.stakes[delegatedStakeId] = StakeInfo({
                staker: delegateAddress,
                start: s.start,
                principal: amount.toUint128(),
                reward: dReward.toUint128(),
                claimed: dClaimed.toUint128()
            });
        }

        l.activeStakeOf[msg.sender] -= amount;
        l.activeStakeOf[delegateAddress] += amount;

        emit StakeDelegated(token, stakeId, delegatedStakeId, delegateAddress, msg.sender, amount);
    }

    /// @notice The staker only: pays the accrued, unclaimed reward.
    function claim(address token, uint256 stakeId) external nonReentrant {
        StakeInfo storage s = _ledgers[token].stakes[stakeId];
        if (s.staker != msg.sender) revert NotStaker();
        _claim(token, s);
    }

    /// @notice The staker only, after the term: pays the principal and the unclaimed reward.
    function withdraw(address token, uint256 stakeId) external nonReentrant {
        Ledger storage l = _ledgers[token];
        StakeInfo storage s = l.stakes[stakeId];
        if (s.staker != msg.sender) revert NotStaker();
        uint256 principal = s.principal;
        if (principal == 0) revert Withdrawn();
        if (block.timestamp < uint256(s.start) + TERM) revert NotMatured();

        uint256 payout = principal + s.reward - s.claimed;
        s.principal = 0;
        s.claimed = s.reward;
        l.activeStakeOf[msg.sender] -= principal;
        IERC20(token).safeTransfer(msg.sender, payout);
    }

    // -------------------------------------------------------------- internals

    function _opened(address token) private view returns (Ledger storage l) {
        l = _ledgers[token];
        if (l.airdrop == address(0)) revert NotInitialized();
    }

    function _excluded(Ledger storage l, address account) private view returns (bool) {
        return account == l.pair || account == address(this) || account == l.deployment || account == DEAD
            || account == l.airdrop;
    }

    /// @dev Pulls `amount` from the caller; returns what the contract's balance of the token grew by.
    function _pull(address token, uint256 amount) private returns (uint256) {
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        return IERC20(token).balanceOf(address(this)) - before;
    }

    /// @dev The referral budget and the premium budget of a stake together.
    function _budgets(uint256 received) private pure returns (uint256) {
        return received * REFERRAL_PERCENT / 100 + received * PREMIUM_PERCENT / 100;
    }

    /// @dev Checks the stake, pulls its principal, allocates its reward and its referral and premium budgets from
    ///      the reserve and writes it under the beneficiary.
    function _begin(address token, uint256 amount, address beneficiary) private returns (uint256 stakeId, uint256 received) {
        Ledger storage l = _opened(token);
        if (amount < MIN_STAKE) revert InvalidAmount();
        if (beneficiary == address(0) || (_excluded(l, beneficiary) && beneficiary != l.airdrop)) revert InvalidBeneficiary();

        received = _pull(token, amount);
        if (received < MIN_STAKE) revert InvalidAmount();

        uint256 reward = received * RATE / 100;
        uint256 budget = _budgets(received);
        uint256 available = l.reserve;
        if (available < reward + budget) revert ReserveShort();
        l.reserve = available - reward - budget;

        stakeId = _open(l, beneficiary, received, reward);
    }

    /// @dev Runs the referral walk and records what the two budgets leave unpaid as one AIRDROP stake with the
    ///      ordinary reward.
    function _finish(address token, uint256 stakeId, address beneficiary, uint256 received) private {
        Ledger storage l = _ledgers[token];
        uint256 budget = _budgets(received);
        // the stakes of an ecosystem account run no walk
        uint256 paid = _excluded(l, beneficiary) ? 0 : _payReferrals(token, l, beneficiary, received);
        uint256 remainder = budget - paid;

        emit Staked(token, stakeId, beneficiary, msg.sender, received);
        if (remainder != 0) {
            uint256 airdropReward = remainder * RATE / 100;
            uint256 available = l.reserve;
            if (available < airdropReward) revert ReserveShort();
            l.reserve = available - airdropReward;
            address airdrop = l.airdrop;
            uint256 airdropId = _open(l, airdrop, remainder, airdropReward);
            emit Staked(token, airdropId, airdrop, address(this), remainder);
        }
    }

    function _open(Ledger storage l, address staker, uint256 amount, uint256 reward) private returns (uint256 stakeId) {
        stakeId = l.nextStakeId++;
        l.stakes[stakeId] = StakeInfo({
            staker: staker,
            start: uint64(block.timestamp),
            principal: amount.toUint128(),
            reward: reward.toUint128(),
            claimed: 0
        });
        l.activeStakeOf[staker] += amount;
    }

    function _accrued(StakeInfo storage s) private view returns (uint256) {
        uint256 start = s.start;
        if (block.timestamp >= start + TERM) return s.reward;
        return uint256(s.reward) * (block.timestamp - start) / TERM;
    }

    function _claim(address token, StakeInfo storage s) private {
        uint256 accrued = _accrued(s);
        uint256 claimed = s.claimed;
        if (accrued <= claimed) return;
        s.claimed = accrued.toUint128();
        IERC20(token).safeTransfer(s.staker, accrued - claimed);
    }

    /// @dev Walks the staker's uplines as the referral contract records them, level by level. An upline is paid,
    ///      in one transfer, its level's share where it is eligible for it and its premium award: the percent of
    ///      the stake its tier of the premium table names less the highest percent paid to a nearer upline, so the
    ///      awards of a stake sum to its highest tier met, within PREMIUM_PERCENT. What an upline is not due stays
    ///      in the remainder and the walk goes on. Ends at a root or after level MAX_LEVELS, the same whatever gas
    ///      and gas price the call carries: the gas is the caller's, none of it is measured, valued or refunded,
    ///      and a call short of gas for the walk reverts whole. Returns the shares and awards paid together.
    function _payReferrals(address token, Ledger storage l, address staker, uint256 amount) private returns (uint256 paid) {
        address upline = staker;
        uint256 share = amount / 10;
        uint256 required = l.unit; // level n needs balanceOf and activeStakeOf each >= (1 << (n - 1)) units, separately
        uint256 percent; // the highest premium percent paid so far, to a nearer upline
        for (uint256 level; level < MAX_LEVELS; level++) {
            upline = REFERRAL.referrerOf(upline);
            if (upline == address(0)) break;
            (uint256 value, uint256 tier) = _due(token, l, upline, required, share);
            if (tier > percent) {
                value += amount * (tier - percent) / 100;
                percent = tier;
            }
            if (value != 0) {
                paid += value;
                IERC20(token).safeTransfer(upline, value);
            }
            share >>= 1;
            required <<= 1;
        }
    }

    /// @dev What an upline is due at its level: `value`, the level's share where the upline's balance and active
    ///      stake each meet `required`, and `tier`, the percent of the premium table its active stake meets,
    ///      whatever its balance. Both zero for an ecosystem account.
    function _due(address token, Ledger storage l, address upline, uint256 required, uint256 share)
        private
        view
        returns (uint256 value, uint256 tier)
    {
        if (_excluded(l, upline)) return (0, 0);
        uint256 active = l.activeStakeOf[upline];
        if (share != 0 && active >= required && IERC20(token).balanceOf(upline) >= required) value = share;
        tier = _premiumTier(active / l.unit);
    }

    /// @dev The premium table: the percent of a stake awarded to an upline of that active stake, in whole tokens.
    function _premiumTier(uint256 active) private pure returns (uint256) {
        if (active < 1_000) return 0;
        if (active < 3_000) return 1;
        if (active < 5_000) return 2;
        if (active < 10_000) return 3;
        if (active < 30_000) return 4;
        if (active < 50_000) return 5;
        if (active < 100_000) return 6;
        if (active < 300_000) return 7;
        if (active < 500_000) return 8;
        if (active < 1_000_000) return 9;
        return PREMIUM_PERCENT;
    }
}
