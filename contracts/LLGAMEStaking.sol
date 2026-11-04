// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title LLGAME locked staking and referral contract
/// @notice No owner, no setter, no pause. All values are constants or immutables.
contract LLGAMEStaking {
    using SafeCast for uint256;

    struct StakeInfo {
        address staker;     // the beneficiary: claims the reward and withdraws the principal
        uint64 start;       // timestamp of the stake block; the reward accrues from it to start + term days
        uint32 term;        // 180, 360 or 1080, in days
        uint128 principal;  // zero once withdrawn
        uint128 reward;     // allocated at stake time
        uint128 claimed;
    }

    struct Account {
        address referrer;   // zero for a root
        bool seen;
    }

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 private constant REFERRAL_PERCENT = 20;

    IERC20 public immutable TOKEN;
    address public immutable AIRDROP;
    address private immutable PAIR;
    address private immutable DEPLOYMENT;

    uint256 public reserve;                         // the unallocated stake reserve
    uint256 public nextStakeId;
    mapping(uint256 => StakeInfo) private _stakes;
    mapping(address => uint256) public activeStakeOf;
    mapping(address => Account) private _accounts;

    event Staked(uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount, uint32 term);
    event StakeDelegated(uint256 indexed stakeId, uint256 indexed delegatedStakeId, address indexed delegate, address staker, uint256 amount);
    event ReferralBound(address indexed account, address indexed referrer);

    error InvalidAmount();
    error InvalidTerm();
    error InvalidBeneficiary();
    error ReserveShort();
    error NotStaker();
    error NotToken();
    error Withdrawn();
    error NotMatured();

    /// @dev Deployed by the deployment contract after the initial reserve has been transferred to this address.
    constructor(IERC20 token_, address airdrop_, address pair_) {
        TOKEN = token_;
        AIRDROP = airdrop_;
        PAIR = pair_;
        DEPLOYMENT = msg.sender;
        reserve = token_.balanceOf(address(this));
    }

    // ------------------------------------------------------------------ views

    /// @notice The fixed ecosystem-account set, excluded from referral binding in either direction.
    function excluded(address account) public view returns (bool) {
        return account == PAIR || account == address(this) || account == DEPLOYMENT || account == DEAD
            || account == AIRDROP;
    }

    function stakeInfo(uint256 stakeId) external view returns (StakeInfo memory) {
        return _stakes[stakeId];
    }

    /// @notice Accrued minus claimed, never negative.
    function claimable(uint256 stakeId) public view returns (uint256) {
        StakeInfo storage s = _stakes[stakeId];
        uint256 accrued = _accrued(s);
        return accrued > s.claimed ? accrued - s.claimed : 0;
    }

    function seen(address account) external view returns (bool) {
        return _accounts[account].seen;
    }

    function referrerOf(address account) external view returns (address) {
        return _accounts[account].referrer;
    }

    // ---------------------------------------------------------------- staking

    function stake(uint256 amount, uint32 term, address beneficiary) external returns (uint256) {
        return _stake(amount, term, beneficiary);
    }

    function stakeWithPermit(
        uint256 amount,
        uint32 term,
        address beneficiary,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        // A front-run permit leaves the allowance in place; the transfer below decides.
        try IERC20Permit(address(TOKEN)).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        return _stake(amount, term, beneficiary);
    }

    function _stake(uint256 amount, uint32 term, address beneficiary) private returns (uint256 stakeId) {
        // 1. checks
        uint256 rate = _rate(term);
        if (amount < _minStakeAmount(term)) revert InvalidAmount();
        if (beneficiary == address(0) || (excluded(beneficiary) && beneficiary != AIRDROP)) revert InvalidBeneficiary();

        // 2. allocate the reward and the referral budget
        uint256 reward = amount * rate / 100;
        uint256 budget = amount * REFERRAL_PERCENT / 100;
        uint256 available = reserve;
        if (available < reward + budget) revert ReserveShort();
        reserve = available - reward - budget;

        // 3. write the stake
        stakeId = _open(beneficiary, amount, reward, term);

        // 4. pull the principal; the recipient is the staking contract, so no receipt is reported
        TOKEN.transferFrom(msg.sender, address(this), amount);

        // 5. bind an unseen beneficiary to the payer
        _see(beneficiary, msg.sender);

        // 6. referral walk
        uint256 remainder = budget - _payReferrals(beneficiary, amount);

        // 7. events; the remainder becomes an AIRDROP stake with the ordinary reward and no referral budget
        emit Staked(stakeId, beneficiary, msg.sender, amount, term);
        if (remainder != 0) {
            uint256 airdropReward = remainder * rate / 100;
            available = reserve;
            if (available < airdropReward) revert ReserveShort();
            reserve = available - airdropReward;
            uint256 airdropId = _open(AIRDROP, remainder, airdropReward, term);
            emit Staked(airdropId, AIRDROP, address(this), remainder, term);
        }
    }

    function delegateStake(uint256 stakeId, uint256 amount, address delegateAddress) external returns (uint256 delegatedStakeId) {
        StakeInfo storage s = _stakes[stakeId];
        if (s.staker != msg.sender || msg.sender == AIRDROP) revert NotStaker(); // AIRDROP stakes are not delegable

        uint256 principal = s.principal;
        if (principal == 0) revert Withdrawn();
        if (amount > principal) revert InvalidAmount();

        // Both the delegated amount and the remainder must meet the minimum.
        uint256 minAmount = _minStakeAmount(s.term);
        if (amount < minAmount || (amount < principal && principal - amount < minAmount)) {
            revert InvalidAmount();
        }

        if (delegateAddress == address(0) || delegateAddress == msg.sender
            || (excluded(delegateAddress) && delegateAddress != AIRDROP)
        ) revert InvalidBeneficiary();

        // Settle accrued rewards before changing ownership or splitting the stake.
        _claim(s);
        _see(delegateAddress, msg.sender);

        if (amount == principal) {
            // Full delegation: reuse the existing stake record.
            s.staker = delegateAddress;
            delegatedStakeId = stakeId;
        } else {
            // Partial delegation: split the existing stake proportionally.
            uint256 dReward = uint256(s.reward) * amount / principal;
            uint256 dClaimed = uint256(s.claimed) * amount / principal;

            s.principal = (principal - amount).toUint128();
            s.reward -= dReward.toUint128();
            s.claimed -= dClaimed.toUint128();

            delegatedStakeId = nextStakeId++;
            _stakes[delegatedStakeId] = StakeInfo({
                staker: delegateAddress,
                start: s.start,
                term: s.term,
                principal: amount.toUint128(),
                reward: dReward.toUint128(),
                claimed: dClaimed.toUint128()
            });
        }

        activeStakeOf[msg.sender] -= amount;
        activeStakeOf[delegateAddress] += amount;

        emit StakeDelegated(stakeId, delegatedStakeId, delegateAddress, msg.sender, amount);
    }

    /// @notice The staker only: pays the accrued, unclaimed reward.
    function claim(uint256 stakeId) external {
        StakeInfo storage s = _stakes[stakeId];
        if (s.staker != msg.sender) revert NotStaker();
        _claim(s);
    }

    /// @notice The staker only, after the term: pays the principal and the unclaimed reward.
    function withdraw(uint256 stakeId) external {
        StakeInfo storage s = _stakes[stakeId];
        if (s.staker != msg.sender) revert NotStaker();
        uint256 principal = s.principal;
        if (principal == 0) revert Withdrawn();
        if (block.timestamp < uint256(s.start) + uint256(s.term) * 1 days) revert NotMatured();

        uint256 payout = principal + s.reward - s.claimed;
        s.principal = 0;
        s.claimed = s.reward;
        activeStakeOf[msg.sender] -= principal;
        TOKEN.transfer(msg.sender, payout);
    }

    /// @notice TOKEN only: reports a positive transfer to an account that held no LLGAME.
    function noteReceipt(address from, address to) external {
        if (msg.sender != address(TOKEN)) revert NotToken();
        _see(to, from);
    }

    // -------------------------------------------------------------- internals

    function _minStakeAmount(uint32 term) private pure returns (uint256) {
        if (term == 180) return 115_200_000;
        if (term == 360) return 96_000_000;
        if (term == 1080) return 72_000_000;
        revert InvalidTerm();
    }

    function _rate(uint32 term) private pure returns (uint256) {
        if (term == 180) return 30;
        if (term == 360) return 72;
        if (term == 1080) return 288;
        revert InvalidTerm();
    }

    function _open(address staker, uint256 amount, uint256 reward, uint32 term) private returns (uint256 stakeId) {
        stakeId = nextStakeId++;
        _stakes[stakeId] = StakeInfo({
            staker: staker,
            start: uint64(block.timestamp),
            term: term,
            principal: amount.toUint128(),
            reward: reward.toUint128(),
            claimed: 0
        });
        activeStakeOf[staker] += amount;
    }

    function _accrued(StakeInfo storage s) private view returns (uint256) {
        uint256 start = s.start;
        uint256 duration = uint256(s.term) * 1 days;
        if (block.timestamp >= start + duration) return s.reward;
        return uint256(s.reward) * (block.timestamp - start) / duration;
    }

    function _claim(StakeInfo storage s) private {
        uint256 accrued = _accrued(s);
        uint256 claimed = s.claimed;
        if (accrued <= claimed) return;
        s.claimed = accrued.toUint128();
        TOKEN.transfer(s.staker, accrued - claimed);
    }

    /// @dev Decides an account's referral status once, when it is first seen.
    function _see(address account, address sender) private {
        Account storage a = _accounts[account];
        if (a.seen) return;
        a.seen = true;
        if (activeStakeOf[sender] != 0 && sender != account && !excluded(sender) && !excluded(account)) {
            a.referrer = sender;
            emit ReferralBound(account, sender);
        }
    }

    /// @dev Pays eligible uplines; stops at a root, at a zero share or at the first ineligible upline.
    function _payReferrals(address staker, uint256 amount) private returns (uint256 paid) {
        address upline = _accounts[staker].referrer;
        uint256 share = amount / 10;
        uint256 requiredCap = amount;
        while (upline != address(0) && share != 0) {
            uint256 liquid = TOKEN.balanceOf(upline);
            uint256 staked = activeStakeOf[upline];
            if (liquid == 0 || staked == 0 || liquid + staked < requiredCap) break;
            paid += share;
            TOKEN.transfer(upline, share);
            upline = _accounts[upline].referrer;
            share >>= 1;
            requiredCap <<= 1;
        }
    }
}
