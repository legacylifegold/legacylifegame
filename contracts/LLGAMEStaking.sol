// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface ILaunchPair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/// @title LLGAME locked staking and referral contract
/// @notice No owner, no setter, no pause. All values are constants or immutables.
contract LLGAMEStaking {
    using SafeCast for uint256;

    uint256 private constant TERM = 1080 days;
    uint256 private constant MIN_STAKE = 72_000_000;
    uint256 private constant RATE = 288;

    struct StakeInfo {
        address staker;     // the beneficiary: claims the reward and withdraws the principal
        uint64 start;       // timestamp of the stake block; the reward accrues from it to start + TERM
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
    uint256 private constant MAX_GAS_PRICE = 0.5 gwei;   // the gas price a referral gas refund is valued at, at most
    uint256 private constant REFUND_DIVISOR = 10;        // the gas refund of a stake is at most 1/10 of its referral budget
    uint256 private constant PRICE_PERIOD = 30 minutes;  // the shortest time between two settings of the reference price
    uint256 private constant PRICE_GUARD_PERCENT = 5;    // LLGAME further below its reference price is valued at the reference
    uint256 private constant Q112 = 1 << 112;

    IERC20 public immutable TOKEN;
    address public immutable AIRDROP;
    address private immutable PAIR;
    bool private immutable LLGAME_IS_TOKEN0; // the order of the pair's reserves
    address private immutable DEPLOYMENT;
    uint256 private immutable UNIT; // 10^decimals, computed once at deployment

    uint256 public reserve;                         // the unallocated stake reserve
    uint256 public nextStakeId;
    mapping(uint256 => StakeInfo) private _stakes;
    mapping(address => uint256) public activeStakeOf;
    mapping(address => Account) private _accounts;

    // The reference price of BNB in LLGAME, an approximate recent price of the pair, UQ112x112 base units per
    // wei, and the time it was last set: one slot.
    uint224 private _refPrice;
    uint32 private _refTime;

    event Staked(uint256 indexed stakeId, address indexed staker, address indexed payer, uint256 amount);
    event StakeDelegated(uint256 indexed stakeId, uint256 indexed delegatedStakeId, address indexed delegate, address staker, uint256 amount);
    event ReferralBound(address indexed account, address indexed referrer);

    error InvalidAmount();
    error InvalidBeneficiary();
    error ReserveShort();
    error NotStaker();
    error Withdrawn();
    error NotMatured();

    /// @dev Deployed by the deployment contract after the initial reserve has been transferred to this address.
    constructor(IERC20 token_, address airdrop_, address pair_) {
        TOKEN = token_;
        AIRDROP = airdrop_;
        PAIR = pair_;
        LLGAME_IS_TOKEN0 = ILaunchPair(pair_).token0() == address(token_);
        DEPLOYMENT = msg.sender;
        UNIT = 10 ** IERC20Metadata(address(token_)).decimals();
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

    function stake(uint256 amount, address beneficiary) external returns (uint256) {
        return _stake(amount, beneficiary);
    }

    function stakeWithPermit(
        uint256 amount,
        address beneficiary,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        // A front-run permit leaves the allowance in place; the transfer below decides.
        try IERC20Permit(address(TOKEN)).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        return _stake(amount, beneficiary);
    }

    function _stake(uint256 amount, address beneficiary) private returns (uint256 stakeId) {
        // 1. checks
        if (amount < MIN_STAKE) revert InvalidAmount();
        if (beneficiary == address(0) || (excluded(beneficiary) && beneficiary != AIRDROP)) revert InvalidBeneficiary();

        // 2. allocate the reward and the referral budget
        uint256 reward = amount * RATE / 100;
        uint256 budget = amount * REFERRAL_PERCENT / 100;
        uint256 available = reserve;
        if (available < reward + budget) revert ReserveShort();
        reserve = available - reward - budget;

        // 3. write the stake
        stakeId = _open(beneficiary, amount, reward);

        // 4. pull the principal
        TOKEN.transferFrom(msg.sender, address(this), amount);

        // 5. bind an unseen beneficiary to the payer
        _see(beneficiary, msg.sender);

        // 6. referral walk
        uint256 remainder = budget - _payReferrals(beneficiary, amount);

        // 7. events; the remainder becomes an AIRDROP stake with the ordinary reward and no referral budget
        emit Staked(stakeId, beneficiary, msg.sender, amount);
        if (remainder != 0) {
            uint256 airdropReward = remainder * RATE / 100;
            available = reserve;
            if (available < airdropReward) revert ReserveShort();
            reserve = available - airdropReward;
            uint256 airdropId = _open(AIRDROP, remainder, airdropReward);
            emit Staked(airdropId, AIRDROP, address(this), remainder);
        }
    }

    function delegateStake(uint256 stakeId, uint256 amount, address delegateAddress) external returns (uint256 delegatedStakeId) {
        StakeInfo storage s = _stakes[stakeId];
        if (s.staker != msg.sender || msg.sender == AIRDROP) revert NotStaker(); // AIRDROP stakes are not delegable

        uint256 principal = s.principal;
        if (principal == 0) revert Withdrawn();
        if (amount > principal) revert InvalidAmount();

        // Both the delegated amount and the remainder must meet the minimum.
        if (amount < MIN_STAKE || (amount < principal && principal - amount < MIN_STAKE)) {
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
        if (block.timestamp < uint256(s.start) + TERM) revert NotMatured();

        uint256 payout = principal + s.reward - s.claimed;
        s.principal = 0;
        s.claimed = s.reward;
        activeStakeOf[msg.sender] -= principal;
        TOKEN.transfer(msg.sender, payout);
    }

    // -------------------------------------------------------------- internals

    function _open(address staker, uint256 amount, uint256 reward) private returns (uint256 stakeId) {
        stakeId = nextStakeId++;
        _stakes[stakeId] = StakeInfo({
            staker: staker,
            start: uint64(block.timestamp),
            principal: amount.toUint128(),
            reward: reward.toUint128(),
            claimed: 0
        });
        activeStakeOf[staker] += amount;
    }

    function _accrued(StakeInfo storage s) private view returns (uint256) {
        uint256 start = s.start;
        if (block.timestamp >= start + TERM) return s.reward;
        return uint256(s.reward) * (block.timestamp - start) / TERM;
    }

    function _claim(StakeInfo storage s) private {
        uint256 accrued = _accrued(s);
        uint256 claimed = s.claimed;
        if (accrued <= claimed) return;
        s.claimed = accrued.toUint128();
        TOKEN.transfer(s.staker, accrued - claimed);
    }

    /// @dev Decides an account's referral status once, when a stake is first opened for it or delegated to it:
    ///      it is bound to `sender`, the payer or the delegating staker, when that sender holds a stake and
    ///      neither is excluded. A token transfer never reaches it.
    function _see(address account, address sender) private {
        Account storage a = _accounts[account];
        if (a.seen) return;
        a.seen = true;
        if (activeStakeOf[sender] != 0 && sender != account && !excluded(sender) && !excluded(account)) {
            a.referrer = sender;
            emit ReferralBound(account, sender);
        }
    }

    /// @dev Walks the staker's uplines. The gas the walk has consumed since the previous level (for level 1,
    ///      since the walk began) is valued in LLGAME at the transaction's gas price, capped by MAX_GAS_PRICE,
    ///      and the pair's price, guarded by its reference price. Every level examined is charged that cost out of its own share,
    ///      while the charges of the stake stay within 1/REFUND_DIVISOR of its referral budget: an eligible
    ///      upline is paid its share less the charge, an ineligible one is passed over and the rest of its
    ///      share stays in the remainder. The charges are refunded to the caller, who paid that gas, in one
    ///      transfer. Ends at a root or before the first level whose share is no more than its gas cost.
    ///      Returns the shares paid and the gas refunded together.
    function _payReferrals(address staker, uint256 amount) private returns (uint256 paid) {
        uint256 gasMark = gasleft();
        address upline = _accounts[staker].referrer;
        if (upline == address(0)) return 0;
        uint256 share = amount / 10;
        uint256 required = UNIT; // level n needs balanceOf and activeStakeOf each >= (1 << (n - 1)) LLGAME, separately
        uint256 gasPrice = tx.gasprice < MAX_GAS_PRICE ? tx.gasprice : MAX_GAS_PRICE;
        uint256 bnbPrice = _bnbPrice();
        uint256 allowance = amount * REFERRAL_PERCENT / (100 * REFUND_DIVISOR);
        uint256 refund;
        while (upline != address(0)) {
            uint256 left = gasleft();
            uint256 cost = Math.mulDiv((gasMark - left) * gasPrice, bnbPrice, Q112);
            if (share <= cost) break;
            gasMark = left;
            if (cost > allowance) cost = allowance;
            allowance -= cost;
            refund += cost;
            if (TOKEN.balanceOf(upline) >= required && activeStakeOf[upline] >= required) {
                paid += share - cost;
                TOKEN.transfer(upline, share - cost);
            }
            upline = _accounts[upline].referrer;
            share >>= 1;
            required <<= 1;
        }
        if (refund != 0) {
            paid += refund;
            TOKEN.transfer(msg.sender, refund);
        }
    }

    /// @dev The price of BNB in LLGAME the gas is valued at, UQ112x112 base units per wei: the pair's current
    ///      price, unless LLGAME stands more than PRICE_GUARD_PERCENT below the reference price, when the
    ///      reference is used, so that a price pushed down for the stake does not raise the refund. The
    ///      reference is approximate: a call at least PRICE_PERIOD after it was last set, finding the pair's
    ///      reserves untouched in this block, sets it to the current price, or, where LLGAME stands lower than
    ///      the guard allows, raises it by one guard step. Reserves moved in the current block never set it.
    ///      The current price is unguarded until a reference is stored. Zero, which charges nothing and leaves
    ///      the zero share as the only end, while the pair holds no liquidity.
    function _bnbPrice() private returns (uint256 price) {
        unchecked {
            (uint112 reserve0, uint112 reserve1, uint32 pairTime) = ILaunchPair(PAIR).getReserves();
            uint256 llgame = LLGAME_IS_TOKEN0 ? reserve0 : reserve1;
            uint256 bnb = LLGAME_IS_TOKEN0 ? reserve1 : reserve0;
            if (llgame == 0 || bnb == 0) return 0;
            price = (llgame << 112) / bnb; // the pair's current price

            uint256 refPrice = _refPrice;
            // BNB dearer in LLGAME than the guard allows: LLGAME stands below its reference
            bool dropped = refPrice != 0 && price * (100 - PRICE_GUARD_PERCENT) > refPrice * 100;
            uint32 time = uint32(block.timestamp);
            if (pairTime != time && time - _refTime >= PRICE_PERIOD) {
                refPrice = dropped ? refPrice * 100 / (100 - PRICE_GUARD_PERCENT) : price;
                _refPrice = uint224(refPrice);
                _refTime = time;
            }
            if (dropped) price = refPrice;
        }
    }
}
