// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LLGAME} from "./LLGAME.sol";
import {LLGAMEStaking} from "./LLGAMEStaking.sol";

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
    function createPair(address tokenA, address tokenB) external returns (address);
}

interface IPancakePair {
    function balanceOf(address owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function skim(address to) external;
    function sync() external;
}

interface IWBNB {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

/// @title LLGAME deployment contract
/// @notice Launches the ecosystem on its first funding round and closes when funding reaches at least
///         POOL_BNB. Every round adds its BNB to the pool with LLGAME in proportion to it, at the fixed
///         launch ratio POOL_SUPPLY / POOL_BNB; the deployment contract holds the rest of POOL_SUPPLY
///         until close. Its only privileged call is PUBLISHER's abort.
contract LLGAMEDeployment {
    enum State { NotLaunched, Funding, Closed, Aborted }

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 private constant POOL_SUPPLY = 1_000_000e9;
    uint256 private constant AUTHORS_SUPPLY = 250_000e9;
    uint32 private constant AUTHORS_TERM = 1080;

    /// @dev PancakeSwap v2 factory and WBNB on BNB Smart Chain mainnet.
    IPancakeFactory public constant FACTORY = IPancakeFactory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);
    IWBNB public constant WBNB = IWBNB(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address public immutable AUTHORS;
    address public immutable AIRDROP;
    uint256 public immutable POOL_BNB;
    address public immutable PUBLISHER;

    State public state;
    LLGAME public token;
    LLGAMEStaking public staking;
    IPancakePair public pair;
    uint256 public funded;          // BNB of all rounds
    uint256 public poolSupplied;    // LLGAME added to the pool, min(POOL_SUPPLY, POOL_SUPPLY × funded / POOL_BNB)
    uint256 public withdrawn;       // BNB recovered by an abort
    mapping(address => uint256) public depositOf;

    error InvalidParameter();
    error InvalidState();
    error NotPublisher();
    error NothingToRefund();
    error AddressMismatch();
    error LaunchCheckFailed();
    error RefundFailed();

    /// @dev Non-payable; the sender becomes PUBLISHER. AUTHORS and AIRDROP must be distinct accounts and
    ///      neither may be a fixed address known at publication: zero, DEAD, FACTORY or WBNB. The token,
    ///      pair and staking contract do not exist before activation and are not checked.
    constructor(address authors_, address airdrop_, uint256 poolBnb_) {
        if (
            _isFixed(authors_) || _isFixed(airdrop_) || authors_ == airdrop_ || poolBnb_ == 0
                || poolBnb_ > type(uint112).max
        ) revert InvalidParameter();
        AUTHORS = authors_;
        AIRDROP = airdrop_;
        POOL_BNB = poolBnb_;
        PUBLISHER = msg.sender;
    }

    /// @notice A funding round: any sender, msg.value > 0, in NotLaunched or Funding.
    receive() external payable {
        if (msg.sender == address(WBNB)) return; // unwrapping during abort
        if (msg.value == 0) revert InvalidParameter();

        State current = state;
        if (current == State.NotLaunched) _launch();
        else if (current != State.Funding) revert InvalidState();

        funded += msg.value;
        depositOf[msg.sender] += msg.value;
        _addLiquidity();

        if (funded >= POOL_BNB) {
            if (token.balanceOf(address(this)) != 0) revert LaunchCheckFailed();
            pair.transfer(DEAD, pair.balanceOf(address(this)));
            state = State.Closed;
        }
    }

    /// @notice PUBLISHER only, in Funding: removes the launch liquidity, burns its LLGAME and the held rest of
    ///         POOL_SUPPLY, keeps its BNB for refunds.
    function abort() external {
        if (msg.sender != PUBLISHER) revert NotPublisher();
        if (state != State.Funding) revert InvalidState();
        state = State.Aborted;

        IPancakePair p = pair;
        p.transfer(address(p), p.balanceOf(address(this)));
        p.burn(address(this));

        LLGAME t = token;
        t.burn(t.balanceOf(address(this)));

        uint256 amount = WBNB.balanceOf(address(this));
        WBNB.withdraw(amount);
        withdrawn = amount;
    }

    /// @notice A funder, in Aborted, once: floor(withdrawn × depositOf / funded).
    function refund() external {
        if (state != State.Aborted) revert InvalidState();
        uint256 deposit = depositOf[msg.sender];
        if (deposit == 0) revert NothingToRefund();
        depositOf[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: withdrawn * deposit / funded}("");
        if (!ok) revert RefundFailed();
    }

    // -------------------------------------------------------------- internals

    function _launch() private {
        // CREATE addresses of this contract: nonce 1 for the token, nonce 2 for the staking contract.
        address predictedStaking = _createAddress(2);

        LLGAME t = new LLGAME(predictedStaking);
        uint256 total = t.TOTAL_SUPPLY();
        t.transfer(predictedStaking, total - POOL_SUPPLY - AUTHORS_SUPPLY);

        address p = FACTORY.getPair(address(t), address(WBNB));
        if (p == address(0)) p = FACTORY.createPair(address(t), address(WBNB));

        LLGAMEStaking s = new LLGAMEStaking(t, AIRDROP, p);
        if (address(s) != predictedStaking) revert AddressMismatch();

        // Before the token existed the pair could hold only an unsynchronised WBNB balance.
        IPancakePair(p).skim(DEAD);

        t.approve(address(s), AUTHORS_SUPPLY);
        s.stake(AUTHORS_SUPPLY, AUTHORS_TERM, AUTHORS);

        if (
            t.totalSupply() != total || t.balanceOf(address(this)) != POOL_SUPPLY || t.balanceOf(p) != 0
                || t.balanceOf(address(s)) != total - POOL_SUPPLY || s.activeStakeOf(AUTHORS) != AUTHORS_SUPPLY
        ) revert LaunchCheckFailed();

        token = t;
        staking = s;
        pair = IPancakePair(p);
        state = State.Funding;
    }

    /// @dev Adds the round's BNB and the LLGAME that brings the pool's share of POOL_SUPPLY to
    ///      min(POOL_SUPPLY, POOL_SUPPLY × funded / POOL_BNB), minting LP tokens to this contract.
    ///      Computed from the cumulative total, so rounding never drifts and the round reaching
    ///      POOL_BNB adds the whole held rest. A round minting no LP tokens reverts in the pair.
    function _addLiquidity() private {
        IPancakePair p = pair;
        uint256 target = funded >= POOL_BNB ? POOL_SUPPLY : POOL_SUPPLY * funded / POOL_BNB;
        uint256 amount = target - poolSupplied;
        poolSupplied = target;

        if (amount != 0) token.transfer(address(p), amount);
        WBNB.deposit{value: msg.value}();
        WBNB.transfer(address(p), msg.value);
        p.mint(address(this));
    }

    function _isFixed(address account) private pure returns (bool) {
        return account == address(0) || account == DEAD || account == address(FACTORY) || account == address(WBNB);
    }

    /// @dev RLP address of a CREATE from this contract for nonce 1..127.
    function _createAddress(uint8 nonce) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(this), bytes1(nonce))))));
    }
}
