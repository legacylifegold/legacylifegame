// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

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

/// @notice What a staking contract must answer to be set by the deployment contract.
interface ILaunchStaking {
    function reserve(address token) external view returns (uint256);
    function activeStakeOf(address token, address account) external view returns (uint256);
    /// @dev Zero until the token is initialized.
    function airdropOf(address token) external view returns (address);
    function pairOf(address token) external view returns (address);
    /// @dev Once per token, amount > 0: fixes the token's AIRDROP, pair and, as the caller, deployment contract,
    ///      and credits the amount, pulled from the caller, to its reserve.
    function initialize(address token, address airdrop, address pair, uint256 amount) external;
    /// @dev Credits the caller's tokens to the token's reserve, irrevocably.
    function fund(address token, uint256 amount) external;
    function stake(address token, uint256 amount, address beneficiary) external returns (uint256 stakeId);
}

/// @title LLGAME deployment contract
/// @notice Takes the whole supply of the token published before it, hands the reserve and the creators' stake to
///         the staking contract named to it, supplies the pool and closes, each step a call of AUTHORS alone.
///         The publisher keeps no right over it, and no call returns LLGAME to AUTHORS: the supply leaves the
///         contract only to the staking contract or to the pool.
contract LLGAMEDeployment {
    enum State { NotLaunched, Launched, Funding, Closed, Aborted }

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 private constant AUTHORS_SUPPLY = 500_000e9;
    uint256 private constant POOL_SUPPLY_CAP = 1_000_000e9;

    /// @dev PancakeSwap v2 factory and WBNB on BNB Smart Chain mainnet.
    IPancakeFactory public constant FACTORY = IPancakeFactory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);
    IWBNB public constant WBNB = IWBNB(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20 public immutable token;
    address public immutable AUTHORS;
    address public immutable AIRDROP;
    address public immutable PUBLISHER; // a record of the publication: no call checks it
    address public immutable pair;      // the canonical LLGAME/WBNB pair

    State public state;
    address public staking;      // zero until set
    uint256 public poolLlgame;   // LLGAME supplied to the pool
    uint256 public poolBnb;      // BNB supplied to the pool
    uint256 public targetLlgame; // the pool amounts AUTHORS set: targetLlgame LLGAME to targetBnb BNB
    uint256 public targetBnb;

    error InvalidParameter();
    error InvalidState();
    error NotAuthors();
    error InvalidStaking();
    error LaunchCheckFailed();
    error PoolNotSupplied();
    error TransferFailed();

    modifier onlyAuthorsIn(State required) {
        if (msg.sender != AUTHORS) revert NotAuthors();
        if (state != required) revert InvalidState();
        _;
    }

    /// @dev Non-payable; the sender is recorded as PUBLISHER. The token must hold code; AUTHORS and AIRDROP must be
    ///      distinct accounts and neither may be a fixed address known at publication: zero, DEAD, FACTORY, WBNB,
    ///      the token or its pair, which the constructor resolves, creating it if absent.
    constructor(address token_, address authors_, address airdrop_) {
        if (token_.code.length == 0 || _isFixed(authors_, token_) || _isFixed(airdrop_, token_) || authors_ == airdrop_) {
            revert InvalidParameter();
        }
        address p = FACTORY.getPair(token_, address(WBNB));
        if (p == address(0)) p = FACTORY.createPair(token_, address(WBNB));
        if (authors_ == p || airdrop_ == p) revert InvalidParameter();
        token = IERC20(token_);
        AUTHORS = authors_;
        AIRDROP = airdrop_;
        PUBLISHER = msg.sender;
        pair = p;
    }

    /// @notice AUTHORS only, in NotLaunched: pulls the token's whole supply from `holder`, on its permit to this
    ///         contract or, where the permit fails, on an allowance already in place.
    function launch(address holder, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyAuthorsIn(State.NotLaunched) {
        IERC20 t = token;
        uint256 total = t.totalSupply();
        try IERC20Permit(address(t)).permit(holder, address(this), total, deadline, v, r, s) {} catch {}
        t.transferFrom(holder, address(this), total);
        if (t.balanceOf(address(this)) != total) revert LaunchCheckFailed();
        state = State.Launched;
    }

    /// @notice AUTHORS only, in Launched, once: names the staking contract, initializes its reserve with all the
    ///         supply but POOL_SUPPLY_CAP and AUTHORS_SUPPLY and opens the creators' stake there.
    function setStaking(address staking_) external onlyAuthorsIn(State.Launched) {
        IERC20 t = token;
        ILaunchStaking s = ILaunchStaking(staking_);
        if (staking_.code.length == 0 || t.balanceOf(staking_) != 0 || s.airdropOf(address(t)) != address(0)) {
            revert InvalidStaking();
        }
        staking = staking_;
        state = State.Funding;

        uint256 total = t.totalSupply();
        uint256 amount = total - POOL_SUPPLY_CAP - AUTHORS_SUPPLY;
        t.approve(staking_, amount);
        s.initialize(address(t), AIRDROP, pair, amount);
        t.approve(staking_, AUTHORS_SUPPLY);
        s.stake(address(t), AUTHORS_SUPPLY, AUTHORS);

        if (
            s.airdropOf(address(t)) != AIRDROP || s.pairOf(address(t)) != pair
                || s.activeStakeOf(address(t), AUTHORS) != AUTHORS_SUPPLY || t.balanceOf(staking_) != total - POOL_SUPPLY_CAP
                || t.balanceOf(address(this)) != POOL_SUPPLY_CAP
        ) revert LaunchCheckFailed();
    }

    /// @notice AUTHORS only, in Funding, any number of times: the pool amounts, `llgame` LLGAME, at most
    ///         POOL_SUPPLY_CAP, to `bnb` BNB. Nothing moves; neither may be set below what the pool was supplied with.
    function setPoolAmounts(uint256 llgame, uint256 bnb) external onlyAuthorsIn(State.Funding) {
        if (llgame == 0 || bnb == 0 || llgame > POOL_SUPPLY_CAP || llgame < poolLlgame || bnb < poolBnb) {
            revert InvalidParameter();
        }
        targetLlgame = llgame;
        targetBnb = bnb;
    }

    /// @notice AUTHORS only, in Funding, the amounts set: adds the BNB to the pool with the LLGAME that brings
    ///         poolLlgame up to min(llgame, llgame × poolBnb / bnb), never down, minting LP tokens to this contract.
    ///         The first transfer skims the pair's stray balances to DEAD beforehand.
    receive() external payable {
        if (msg.sender == address(WBNB)) return; // unwrapping during abort
        if (msg.sender != AUTHORS) revert NotAuthors();
        if (state != State.Funding) revert InvalidState();
        uint256 bnb = targetBnb;
        if (msg.value == 0 || bnb == 0) revert InvalidParameter();

        IPancakePair p = IPancakePair(pair);
        uint256 bnbSupplied = poolBnb;
        if (bnbSupplied == 0) p.skim(DEAD);
        bnbSupplied += msg.value;
        poolBnb = bnbSupplied;

        uint256 llgame = targetLlgame;
        uint256 target = llgame * bnbSupplied / bnb;
        if (target > llgame) target = llgame;
        uint256 llgameSupplied = poolLlgame;
        if (target > llgameSupplied) {
            poolLlgame = target;
            token.transfer(address(p), target - llgameSupplied);
        }
        WBNB.deposit{value: msg.value}();
        WBNB.transfer(address(p), msg.value);
        p.mint(address(this));
    }

    /// @notice AUTHORS only, in Funding, the pool supplied: sends the LP tokens to DEAD and funds the staking
    ///         reserve with all LLGAME this contract holds, the unused rest of POOL_SUPPLY_CAP and any sent to it.
    function close() external onlyAuthorsIn(State.Funding) {
        if (poolBnb == 0) revert PoolNotSupplied();
        state = State.Closed;
        IPancakePair p = IPancakePair(pair);
        p.transfer(DEAD, p.balanceOf(address(this)));
        _fundReserve();
    }

    /// @notice AUTHORS only, in Funding: removes the liquidity of the LP tokens held, funds the staking reserve with
    ///         all LLGAME this contract then holds and pays the recovered BNB to AUTHORS.
    function abort() external onlyAuthorsIn(State.Funding) {
        state = State.Aborted;
        IPancakePair p = IPancakePair(pair);
        uint256 liquidity = p.balanceOf(address(this));
        if (liquidity != 0) { // none before the first BNB
            p.transfer(address(p), liquidity);
            p.burn(address(this));
        }
        _fundReserve();

        uint256 amount = WBNB.balanceOf(address(this));
        if (amount != 0) {
            WBNB.withdraw(amount);
            (bool ok,) = AUTHORS.call{value: amount}("");
            if (!ok) revert TransferFailed();
        }
    }

    // -------------------------------------------------------------- internals

    function _fundReserve() private {
        IERC20 t = token;
        uint256 amount = t.balanceOf(address(this));
        if (amount == 0) return;
        t.approve(staking, amount);
        ILaunchStaking(staking).fund(address(t), amount);
    }

    function _isFixed(address account, address token_) private pure returns (bool) {
        return account == address(0) || account == DEAD || account == address(FACTORY) || account == address(WBNB)
            || account == token_;
    }
}
