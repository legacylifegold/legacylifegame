// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LLGAME} from "../contracts/LLGAME.sol";
import {LLGAMEStaking} from "../contracts/LLGAMEStaking.sol";
import {LLGAMEReferral} from "../contracts/LLGAMEReferral.sol";
import {LLGAMEDeployment} from "../contracts/LLGAMEDeployment.sol";

/// @dev A token of 18 decimals, its supply minted to its deployer.
contract Token18 is ERC20 {
    constructor() ERC20("Eighteen", "E18") { _mint(msg.sender, 1e36); }
}

/// @dev A token of 9 decimals that burns a tenth of every transfer between two accounts.
contract FeeToken is ERC20 {
    constructor() ERC20("Fee", "FEE") { _mint(msg.sender, 1e30); }

    function decimals() public pure override returns (uint8) { return 9; }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 10;
            super._update(from, address(0), fee);
            value -= fee;
        }
        super._update(from, to, value);
    }
}

contract WBNB9 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable { balanceOf[msg.sender] += msg.value; }

    function withdraw(uint256 wad) external {
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad); // 2,300-gas stipend, as the real WBNB
    }

    function transfer(address to, uint256 v) external returns (bool) { return transferFrom(msg.sender, to, v); }

    function transferFrom(address f, address to, uint256 v) public returns (bool) {
        if (f != msg.sender) allowance[f][msg.sender] -= v;
        balanceOf[f] -= v;
        balanceOf[to] += v;
        return true;
    }
}

interface IFactory {
    function createPair(address, address) external returns (address);
    function getPair(address, address) external view returns (address);
}

interface IPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256, uint256, address, bytes calldata) external;
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @dev A staking contract answering the launch interface and nothing more: per token a reserve, AIRDROP, pair,
///      deployment contract and active stakes. As the staking contract does, it takes only a pair of the token and
///      WBNB, and a stake costs the reserve its 288% reward and its 20% referral and 10% premium budgets, which,
///      its staker being taken for a root, it pays to AIRDROP as liquid tokens. `divertBudgets` pays them to
///      another address instead.
///      `misreportPair` makes it answer a pair other than the one passed.
contract MockLaunchStaking {
    struct Ledger {
        address airdrop;
        address pair;
        address deployment;
        uint256 reserve;
    }

    address public immutable WBNB;
    mapping(address => Ledger) public ledger;
    mapping(address => mapping(address => uint256)) public activeStakeOf;
    bool public misreportPair;
    bool public divertBudgets;

    constructor(address wbnb) { WBNB = wbnb; }

    function setMisreportPair(bool on) external { misreportPair = on; }

    function setDivertBudgets(bool on) external { divertBudgets = on; }

    function reserve(address token) external view returns (uint256) { return ledger[token].reserve; }

    function airdropOf(address token) external view returns (address) { return ledger[token].airdrop; }

    function pairOf(address token) external view returns (address) {
        return misreportPair ? address(1) : ledger[token].pair;
    }

    function deploymentOf(address token) external view returns (address) { return ledger[token].deployment; }

    function initialize(address token, address airdrop, address pair, uint256 amount) external {
        Ledger storage l = ledger[token];
        require(l.airdrop == address(0) && airdrop != address(0) && amount != 0, "initialize");
        (address t0, address t1) = (IPair(pair).token0(), IPair(pair).token1());
        require((t0 == token && t1 == WBNB) || (t0 == WBNB && t1 == token), "pair");
        (l.airdrop, l.pair, l.deployment) = (airdrop, pair, msg.sender);
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        l.reserve += amount;
    }

    function fund(address token, uint256 amount) external {
        require(ledger[token].airdrop != address(0), "fund");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        ledger[token].reserve += amount;
    }

    function stake(address token, uint256 amount, address beneficiary) external returns (uint256) {
        Ledger storage l = ledger[token];
        require(l.airdrop != address(0), "stake");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        uint256 budgets = amount * 20 / 100 + amount * 10 / 100;
        uint256 cost = amount * 288 / 100 + budgets;
        require(l.reserve >= cost, "reserve short");
        l.reserve -= cost;
        activeStakeOf[token][beneficiary] += amount;
        IERC20(token).transfer(divertBudgets ? address(0xbeef) : l.airdrop, budgets);
        return 0;
    }
}

/// @dev A contract of no factory: it names the two tokens it was given and answers nothing else.
contract NamedPair {
    address public token0;
    address public token1;

    constructor(address a, address b) { (token0, token1) = (a, b); }
}

/// @dev A referral contract whose `bind` burns all the gas it is given, as a binding that runs out of gas does, and
///      whose forest is empty.
contract GasBurningReferral {
    function bind(address, address, string calldata, string calldata, string calldata, bytes calldata) external pure {
        assembly { invalid() }
    }

    function referrerOf(address) external pure returns (address) { return address(0); }
}

/// @dev The chain every test runs on: WBNB and the PancakeSwap v2 factory at the addresses the deployment contract
///      names, the token published by its holder and the deployment contract published for it, not yet launched.
abstract contract LLGAMEChain is Test {
    uint256 constant U = 1e9; // one LLGAME
    uint256 constant TOTAL = 340_000_000_000_000_000_000_000_000_000 * U;
    uint256 constant POOL_SUPPLY_CAP = 1_000_000 * U;
    uint256 constant AUTHORS_SUPPLY = 200_000 * U;
    // what the creators' stake, opened unbound, takes from the reserve: 576,000 reward and 60,000 of referral and
    // premium budgets, which go to AIRDROP as liquid LLGAME
    uint256 constant CREATORS_BUDGETS = 60_000 * U;
    uint256 constant CREATORS_COST = 576_000 * U + CREATORS_BUDGETS;
    uint256 constant R_LAUNCH = TOTAL - POOL_SUPPLY_CAP - AUTHORS_SUPPLY - CREATORS_COST; // TOTAL - 1,836,000 LLGAME
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    // PancakeSwap v2 factory and WBNB of the chain this branch is built for: BSC mainnet
    address constant BSC_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address constant BSC_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address publisher = makeAddr("publisher");
    address authors = makeAddr("authors");
    address airdrop = makeAddr("airdrop");
    address holder;
    uint256 holderKey;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");

    WBNB9 wbnb;
    IFactory factory;
    LLGAMEDeployment dep;
    LLGAME token;
    IPair pair;

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        // the deployment contract hardcodes the BSC mainnet factory and WBNB: place local copies there
        vm.etch(BSC_WBNB, address(new WBNB9()).code);
        wbnb = WBNB9(BSC_WBNB);
        deployCodeTo("PancakeFactory.sol:PancakeFactory", abi.encode(address(this)), BSC_FACTORY);
        factory = IFactory(BSC_FACTORY);
        // the token is published first, its whole supply minted to its publisher, the holder
        (holder, holderKey) = makeAddrAndKey("holder");
        vm.prank(holder);
        token = new LLGAME();
        vm.prank(publisher);
        dep = new LLGAMEDeployment(address(token), authors, airdrop);
        pair = IPair(dep.pair());
    }

    /// @dev The holder's permit of `value` to the deployment contract, valid for an hour.
    function _permit(uint256 value) internal view returns (uint256 deadline, uint8 v, bytes32 r, bytes32 s) {
        deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                holder, address(dep), value, token.nonces(holder), deadline
            )
        );
        (v, r, s) = vm.sign(holderKey, keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)));
    }

    /// @dev AUTHORS launches on the holder's permit: the deployment contract holds the whole supply.
    function _launch() internal {
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _permit(TOTAL);
        vm.prank(authors);
        dep.launch(holder, deadline, v, r, s);
    }

    /// @dev BNB that AUTHORS sends to the deployment contract.
    function _supply(uint256 bnb) internal {
        vm.deal(authors, authors.balance + bnb);
        vm.prank(authors);
        (bool ok,) = address(dep).call{value: bnb}("");
        require(ok, "supply failed");
    }

    function _poolLlgame() internal view returns (uint256) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        return pair.token0() == address(token) ? r0 : r1;
    }

    function _buy(address user, uint256 bnb) internal returns (uint256 out) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        bool wbnbIs0 = pair.token0() == address(wbnb);
        (uint256 rIn, uint256 rOut) = wbnbIs0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        out = bnb * 998 * rOut / (rIn * 1000 + bnb * 998);
        vm.deal(user, bnb);
        vm.startPrank(user);
        wbnb.deposit{value: bnb}();
        wbnb.transfer(address(pair), bnb);
        vm.stopPrank();
        pair.swap(wbnbIs0 ? 0 : out, wbnbIs0 ? out : 0, user, "");
    }
}

/// @dev The deployment contract against a staking contract that answers ILaunchStaking and nothing more.
contract LLGAMEDeploymentTest is LLGAMEChain {
    MockLaunchStaking mock;

    function setUp() public override {
        super.setUp();
        mock = new MockLaunchStaking(BSC_WBNB);
    }

    function _setStaking() internal {
        _launch();
        vm.prank(authors);
        dep.setStaking(address(mock));
    }

    function _setPoolAmounts(uint256 llgame, uint256 bnb) internal {
        vm.prank(authors);
        dep.setPoolAmounts(llgame, bnb);
    }

    function _sendBnb(address from, uint256 bnb) internal returns (bool ok) {
        vm.deal(from, from.balance + bnb);
        vm.prank(from);
        (ok,) = address(dep).call{value: bnb}("");
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-PARAMETERS
    function test_constructorRejectsFixedAddresses() public {
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(alice, authors, airdrop); // a token address without code
        address[6] memory fixedAddrs = [address(0), DEAD, BSC_FACTORY, BSC_WBNB, address(token), address(pair)];
        for (uint256 i; i < fixedAddrs.length; i++) {
            vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
            new LLGAMEDeployment(address(token), fixedAddrs[i], airdrop);
            vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
            new LLGAMEDeployment(address(token), authors, fixedAddrs[i]);
        }
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(address(token), authors, authors);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-LAUNCH permit
    function test_launchOnPermit() public {
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.NotLaunched));
        assertEq(dep.PUBLISHER(), publisher);
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _permit(TOTAL);
        // AUTHORS alone: neither the publisher nor the holder
        vm.prank(publisher);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.launch(holder, deadline, v, r, s);
        vm.prank(holder);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.launch(holder, deadline, v, r, s);

        vm.prank(authors);
        dep.launch(holder, deadline, v, r, s);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Launched));
        assertEq(token.balanceOf(address(dep)), TOTAL, "the whole supply");
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(authors), 0, "nothing to AUTHORS");

        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.launch(holder, deadline, v, r, s); // once
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-LAUNCH allowance
    function test_launchOnAllowance() public {
        // a holder short of the whole supply is refused, its allowance notwithstanding
        vm.startPrank(holder);
        token.transfer(alice, 1);
        token.approve(address(dep), TOTAL);
        vm.stopPrank();
        vm.prank(authors);
        vm.expectRevert();
        dep.launch(holder, 0, 0, 0, 0);

        // the supply moved on to a holder that approves instead of signing, as a smart wallet does
        vm.prank(alice);
        token.transfer(bob, 1);
        vm.prank(holder);
        token.transfer(bob, TOTAL - 1);
        vm.prank(bob);
        token.approve(address(dep), TOTAL);
        vm.prank(authors);
        dep.launch(bob, 0, 0, 0, 0);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Launched));
        assertEq(token.balanceOf(address(dep)), TOTAL);
        assertEq(token.balanceOf(bob), 0);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-STAKING set
    function test_setStaking() public {
        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.setStaking(address(mock)); // before the launch
        _launch();

        // no pool call before the staking contract is set
        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.setPoolAmounts(1_000 * U, 1 ether);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.close();
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.abort();
        vm.stopPrank();
        assertFalse(_sendBnb(authors, 1 ether), "BNB before the staking contract");

        vm.prank(publisher);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.setStaking(address(mock));

        vm.prank(authors);
        dep.setStaking(address(mock));
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
        assertEq(dep.staking(), address(mock));
        assertEq(mock.reserve(address(token)), R_LAUNCH, "the reserve less the creators' stake's whole cost");
        assertEq(mock.airdropOf(address(token)), airdrop);
        assertEq(mock.pairOf(address(token)), address(pair));
        assertEq(mock.deploymentOf(address(token)), address(dep), "the caller of initialize");
        assertEq(mock.activeStakeOf(address(token), authors), AUTHORS_SUPPLY, "the creators' stake");
        assertEq(mock.activeStakeOf(address(token), airdrop), 0, "no AIRDROP stake");
        assertEq(token.balanceOf(airdrop), CREATORS_BUDGETS, "the budgets, liquid");
        assertEq(token.balanceOf(address(mock)) + token.balanceOf(airdrop), TOTAL - POOL_SUPPLY_CAP);
        assertEq(token.balanceOf(address(dep)), POOL_SUPPLY_CAP);
        assertEq(token.balanceOf(authors), 0, "nothing to AUTHORS");

        MockLaunchStaking other = new MockLaunchStaking(BSC_WBNB);
        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.setStaking(address(other)); // once
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-STAKING refused
    function test_setStakingRefused() public {
        _launch();
        MockLaunchStaking holding = new MockLaunchStaking(BSC_WBNB);
        deal(address(token), address(holding), 1);
        MockLaunchStaking initialized = new MockLaunchStaking(BSC_WBNB);
        deal(address(token), address(this), 1);
        token.approve(address(initialized), 1);
        initialized.initialize(address(token), airdrop, address(pair), 1);
        MockLaunchStaking liar = new MockLaunchStaking(BSC_WBNB);
        liar.setMisreportPair(true);
        MockLaunchStaking diverter = new MockLaunchStaking(BSC_WBNB);
        diverter.setDivertBudgets(true);

        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidStaking.selector);
        dep.setStaking(alice); // no code
        vm.expectRevert(LLGAMEDeployment.InvalidStaking.selector);
        dep.setStaking(address(holding)); // holds LLGAME
        vm.expectRevert(LLGAMEDeployment.InvalidStaking.selector);
        dep.setStaking(address(initialized)); // the token already initialized there
        vm.expectRevert(LLGAMEDeployment.LaunchCheckFailed.selector);
        dep.setStaking(address(liar)); // reports another pair than the one passed
        vm.expectRevert(LLGAMEDeployment.LaunchCheckFailed.selector);
        dep.setStaking(address(diverter)); // the budgets of the creators' stake paid to neither it nor AIRDROP
        vm.stopPrank();
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Launched));
        assertEq(dep.staking(), address(0));
        assertEq(token.balanceOf(address(dep)), TOTAL, "nothing moved");

        vm.prank(authors);
        dep.setStaking(address(mock));
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-POOL proportion
    function test_poolSuppliedInProportion() public {
        _setStaking();
        assertEq(address(pair), factory.getPair(address(token), address(wbnb)), "the canonical pair");
        assertFalse(_sendBnb(authors, 1 ether), "BNB before the amounts are set");

        _setPoolAmounts(100_000 * U, 10 ether);
        assertFalse(_sendBnb(alice, 1 ether), "BNB of another account");

        _supply(1 ether);
        assertEq(dep.poolBnb(), 1 ether);
        assertEq(dep.poolLlgame(), 10_000 * U);
        assertEq(_poolLlgame(), 10_000 * U);
        assertEq(wbnb.balanceOf(address(pair)), 1 ether);
        assertEq(token.balanceOf(address(dep)), POOL_SUPPLY_CAP - 10_000 * U, "the rest held");
        uint256 lp1 = pair.balanceOf(address(dep));
        assertGt(lp1, 0, "LP tokens to the deployment contract");

        _supply(4 ether);
        assertEq(_poolLlgame(), 50_000 * U, "LLGAME in proportion to BNB");
        assertApproxEqRel(pair.balanceOf(address(dep)), lp1 * 5, 1e12, "LP grows with the pool");

        _supply(6 ether); // beyond the BNB amount: the LLGAME stops at its own
        assertEq(dep.poolBnb(), 11 ether);
        assertEq(dep.poolLlgame(), 100_000 * U);
        assertEq(_poolLlgame(), 100_000 * U);
        assertEq(wbnb.balanceOf(address(pair)), 11 ether);
        assertEq(token.balanceOf(address(dep)), POOL_SUPPLY_CAP - 100_000 * U);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-POOL amounts
    function test_poolAmounts() public {
        _setStaking();
        vm.prank(alice);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.setPoolAmounts(1_000 * U, 1 ether);

        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        dep.setPoolAmounts(POOL_SUPPLY_CAP + 1, 1 ether);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        dep.setPoolAmounts(0, 1 ether);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        dep.setPoolAmounts(1_000 * U, 0);
        // free until the first BNB, raised and lowered alike
        dep.setPoolAmounts(POOL_SUPPLY_CAP, 1 ether);
        dep.setPoolAmounts(1_000 * U, 4 ether);
        vm.stopPrank();
        _supply(1 ether);
        assertEq(dep.poolLlgame(), 250 * U, "the price of the amounts last set");

        // afterwards neither below what the pool was supplied with
        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        dep.setPoolAmounts(250 * U - 1, 4 ether);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        dep.setPoolAmounts(1_000 * U, 1 ether - 1);
        dep.setPoolAmounts(4_000 * U, 4 ether); // a lower BNB price of LLGAME for the BNB still to come
        vm.stopPrank();
        _supply(1 ether);
        assertEq(dep.poolBnb(), 2 ether);
        assertEq(dep.poolLlgame(), 2_000 * U, "brought up to llgame * poolBnb / bnb");
        assertEq(_poolLlgame(), 2_000 * U);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-POOL skim
    function test_firstSupplySkimsStrayWbnb() public {
        // a pair created ahead of the publication is the one taken
        LLGAME other = new LLGAME();
        address p = factory.createPair(address(other), address(wbnb));
        assertEq(new LLGAMEDeployment(address(other), authors, airdrop).pair(), p);

        // WBNB sent to the pair before the first BNB is skimmed to DEAD
        vm.deal(address(this), 5 ether);
        wbnb.deposit{value: 5 ether}();
        wbnb.transfer(address(pair), 5 ether);
        _setStaking();
        _setPoolAmounts(10_000 * U, 10 ether);
        _supply(1 ether);
        assertEq(wbnb.balanceOf(DEAD), 5 ether);
        assertEq(wbnb.balanceOf(address(pair)), 1 ether);
        assertEq(_poolLlgame(), 1_000 * U);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-CLOSE mock
    function test_close() public {
        _setStaking();
        _setPoolAmounts(100_000 * U, 10 ether);
        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.PoolNotSupplied.selector);
        dep.close();

        _supply(10 ether);
        _buy(bob, 0.1 ether);
        vm.prank(bob);
        token.transfer(address(dep), 1); // LLGAME sent to the deployment contract directly

        vm.prank(publisher);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.close();

        uint256 r0 = mock.reserve(address(token));
        vm.prank(authors);
        dep.close();
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertEq(pair.balanceOf(address(dep)), 0);
        assertEq(pair.balanceOf(DEAD), pair.totalSupply() - 1000, "the LP tokens at DEAD, the pair's minimum excepted");
        assertEq(token.balanceOf(address(dep)), 0);
        assertEq(mock.reserve(address(token)) - r0, POOL_SUPPLY_CAP - 100_000 * U + 1, "the unused rest and the donation");

        // nothing accepted afterwards
        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.close();
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.abort();
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.setPoolAmounts(100_000 * U, 10 ether);
        vm.stopPrank();
        assertFalse(_sendBnb(authors, 1 ether), "BNB after the close");
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ABORT mock
    function test_abort() public {
        _setStaking();
        _setPoolAmounts(10_000 * U, 10 ether);
        _supply(4 ether);
        _buy(alice, 2 ether); // a buyer's BNB enters the pool before the abort

        vm.prank(publisher);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.abort();
        vm.prank(alice);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.abort();

        uint256 r0 = mock.reserve(address(token));
        uint256 b0 = authors.balance;
        uint256 supply = token.totalSupply();
        vm.prank(authors);
        dep.abort();
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Aborted));
        assertEq(pair.balanceOf(address(dep)), 0, "the liquidity removed");
        assertEq(token.balanceOf(address(dep)), 0);
        assertEq(wbnb.balanceOf(address(dep)), 0);
        assertEq(address(dep).balance, 0);
        assertEq(token.totalSupply(), supply, "nothing burned");
        uint256 funded = mock.reserve(address(token)) - r0;
        assertGt(funded, POOL_SUPPLY_CAP - 4_000 * U, "the held rest and the LLGAME recovered from the pool");
        assertEq(token.balanceOf(address(mock)), TOTAL - POOL_SUPPLY_CAP - CREATORS_BUDGETS + funded);
        assertGt(authors.balance - b0, 4 ether, "the recovered BNB, the buyer's included, to AUTHORS");
        assertEq(mock.activeStakeOf(address(token), authors), AUTHORS_SUPPLY, "the creators' stake remains");

        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.abort();
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.close();
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.setPoolAmounts(10_000 * U, 10 ether);
        vm.stopPrank();
        assertFalse(_sendBnb(authors, 1 ether), "BNB after the abort");

        // before the first BNB: no liquidity to remove, the whole cap to the reserve, no BNB recovered
        LLGAME t2 = new LLGAME();
        LLGAMEDeployment d2 = new LLGAMEDeployment(address(t2), authors, airdrop);
        t2.approve(address(d2), TOTAL);
        MockLaunchStaking m2 = new MockLaunchStaking(BSC_WBNB);
        b0 = authors.balance;
        vm.startPrank(authors);
        d2.launch(address(this), 0, 0, 0, 0);
        d2.setStaking(address(m2));
        d2.abort();
        vm.stopPrank();
        assertEq(m2.reserve(address(t2)), R_LAUNCH + POOL_SUPPLY_CAP, "the whole cap to the reserve");
        assertEq(t2.balanceOf(address(d2)), 0);
        assertEq(authors.balance, b0);
    }

    // syngate: LEGACYLIFE-BSC-NETWORK
    function test_networkBinding() public view {
        assertEq(address(dep.FACTORY()), BSC_FACTORY);
        assertEq(address(dep.WBNB()), BSC_WBNB);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-TOKEN
    function test_tokenMintsWholeSupplyOnce() public {
        LLGAME t = new LLGAME();
        assertEq(t.name(), "Legacy Life Game");
        assertEq(t.symbol(), "LLGAME");
        assertEq(t.decimals(), 9);
        assertEq(t.totalSupply(), TOTAL);
        assertEq(t.balanceOf(address(this)), TOTAL, "the deployer holds the whole supply");
        t.burn(1 * U); // the supply only shrinks
        assertEq(t.totalSupply(), TOTAL - 1 * U);
    }
}

/// @dev The staking scenarios on the ecosystem as the deployment contract sets it up: launched on the holder's
///      permit, a referral contract and the staking contract reading it published, the staking contract set by
///      the deployment contract and, by `_close`, a pool of 10,000 LLGAME and 10 BNB supplied and closed.
contract LLGAMETest is LLGAMEChain {
    string constant SITE = "https://legacylife.online";
    string constant NONCE = "a1B2c3D4e5F6g7H8";
    string constant ISSUED_AT = "2026-11-25T10:00:00Z";
    uint256 constant MIN = 72_000_000;

    LLGAMEReferral referral;
    LLGAMEStaking staking;
    address t; // the LLGAME ledger's token

    function setUp() public override {
        super.setUp();
        _launch();
        referral = new LLGAMEReferral();
        staking = new LLGAMEStaking(address(referral), BSC_WBNB);
        vm.prank(authors);
        dep.setStaking(address(staking));
        t = address(token);
    }

    function _close() internal {
        vm.prank(authors);
        dep.setPoolAmounts(10_000 * U, 10 ether);
        _supply(10 ether);
        vm.prank(authors);
        dep.close();
    }

    /// @dev A staking contract of its own for the LLGAME token, on a referral double whose `bind` burns all its gas,
    ///      its reserve funded by this contract.
    function _burningStaking() internal returns (LLGAMEStaking s) {
        s = new LLGAMEStaking(address(new GasBurningReferral()), BSC_WBNB);
        _give(address(this), 1_000_000 * U);
        token.approve(address(s), 1_000_000 * U);
        s.initialize(t, airdrop, address(pair), 1_000_000 * U);
    }

    function _stake(address payer, uint256 amount, address beneficiary) internal returns (uint256 id) {
        vm.startPrank(payer);
        token.approve(address(staking), amount);
        id = staking.stake(t, amount, beneficiary);
        vm.stopPrank();
    }

    /// @dev Gives `who` LLGAME out of thin air: the pool holds only 10,000 LLGAME, too little for the staking scenarios.
    function _give(address who, uint256 amount) internal {
        deal(t, who, token.balanceOf(who) + amount, true);
    }

    /// @dev The agreement the referral contract rebuilds, signed by `key` as a `personal_sign`.
    function _sign(uint256 key, address account, address to) internal view returns (bytes memory) {
        bytes memory message = bytes(
            string.concat(
                "legacylife.online wants you to sign in with your Ethereum account:\n",
                vm.toString(account),
                "\n\nI agree that ",
                vm.toString(to),
                " is my referrer in Legacy Life Game.\n\nURI: https://legacylife.online\nVersion: 1\nChain ID: ",
                vm.toString(block.chainid),
                "\nNonce: a1B2c3D4e5F6g7H8\nIssued At: 2026-11-25T10:00:00Z\nResources:\n- urn:llgame:referrer:",
                vm.toString(to)
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", vm.toString(message.length), message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Binds the account made of `name` to `to` in the referral contract, on its own signature.
    function _bind(string memory name, address to) internal returns (address account) {
        uint256 key;
        (account, key) = makeAddrAndKey(name);
        referral.bind(account, to, SITE, NONCE, ISSUED_AT, _sign(key, account, to));
    }

    function _assertSolvent(address tk) internal view {
        uint256 owed = staking.reserve(tk);
        uint256 n = staking.nextStakeId(tk);
        for (uint256 i; i < n; i++) {
            LLGAMEStaking.StakeInfo memory s = staking.stakeInfo(tk, i);
            owed += uint256(s.principal) + s.reward - s.claimed;
        }
        assertLe(owed, IERC20(tk).balanceOf(address(staking)), "insolvent");
    }

    function _lastStake() internal view returns (LLGAMEStaking.StakeInfo memory) {
        return staking.stakeInfo(t, staking.nextStakeId(t) - 1);
    }

    /// @dev The chain carol → bob → alice, both uplines eligible: alice 900 LLGAME staked and the rest of
    ///      100,000 liquid, bob 900 staked and 9,100 liquid, both below every premium tier, carol 5,000 liquid.
    ///      Each stake opens before its staker is bound, so none of them pays a share.
    function _trio() internal {
        _give(alice, 100_000 * U);
        _stake(alice, 900 * U, alice);
        _give(bob, 10_000 * U);
        _stake(bob, 900 * U, bob);
        _give(carol, 5_000 * U);
        _bind("bob", alice);
        _bind("carol", bob);
    }

    /// @dev A chain of `depth` eligible uplines above a fresh staker, each account holding 11,000 LLGAME liquid
    ///      and 1,000 LLGAME staked; returns the staker, bound to the lowest upline.
    function _chain(uint256 depth, string memory tag) internal returns (address staker) {
        address upper = makeAddr(string.concat(tag, "0"));
        _give(upper, 12_000 * U);
        _stake(upper, 1_000 * U, upper);
        for (uint256 i = 1; i <= depth; i++) {
            address lower = makeAddr(string.concat(tag, vm.toString(i)));
            _give(lower, 12_000 * U);
            _stake(lower, 1_000 * U, lower);
            _bind(string.concat(tag, vm.toString(i)), upper);
            upper = lower;
        }
        staker = upper;
    }

    /// @dev A chain of `depth` uplines above a fresh staker, `tag0` the root, each upline holding 2^30 LLGAME
    ///      liquid and 2^30 LLGAME staked, eligible at every level up to the 31st; returns the staker, `tag<depth>`,
    ///      which holds nothing. Each stake opens before its staker is bound, so none of them pays a share.
    function _deepChain(uint256 depth, string memory tag) internal returns (address staker) {
        uint256 rich = (1 << 30) * U;
        for (uint256 i; i <= depth; i++) {
            string memory name = string.concat(tag, vm.toString(i));
            address lower = makeAddr(name);
            if (i != depth) {
                _give(lower, 2 * rich);
                _stake(lower, rich, lower);
            }
            if (i != 0) _bind(name, staker);
            staker = lower;
        }
    }

    /// @dev A fresh staker, holding nothing, under `depth` uplines of one kind: 0 with neither stake nor balance,
    ///      1 eligible for its level share alone, 2 on the premium tier of its level with no liquid LLGAME, 3 on
    ///      that tier and eligible for its level share. Above level 10, the top tier, an upline of kind 2 or 3 is
    ///      eligible for its level share alone. Each stake opens before its staker is bound.
    function _gasChain(string memory tag, uint256 depth, uint256 kind) internal returns (address staker) {
        uint256[10] memory tiers =
            [uint256(1_000), 3_000, 5_000, 10_000, 30_000, 50_000, 100_000, 300_000, 500_000, 1_000_000];
        for (uint256 i; i <= depth; i++) {
            string memory name = string.concat(tag, vm.toString(i));
            address lower = makeAddr(name);
            if (i != depth && kind != 0) {
                uint256 n = depth - i; // its level
                uint256 staked = kind == 1 ? 600 * U : n <= 10 ? tiers[n - 1] * U : (1 << 30) * U;
                uint256 liquid = n > 10 ? (1 << 30) * U : kind == 2 ? 0 : 1_000 * U;
                _give(lower, staked + liquid);
                _stake(lower, staked, lower);
            }
            if (i != 0) _bind(name, staker);
            staker = lower;
        }
    }

    /// @dev Gas of the plain stake of `amount` by `payer` for itself, its approval aside.
    function _stakeGas(address payer, uint256 amount) internal returns (uint256) {
        vm.startPrank(payer);
        token.approve(address(staking), amount);
        staking.stake(t, amount, payer);
        vm.stopPrank();
        return vm.lastCallGas().gasTotalUsed;
    }

    // ----------------------------------------------------------------- launch

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-STAKING ledger
    function test_setStakingOpensLedger() public {
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
        assertEq(dep.staking(), address(staking));
        assertEq(staking.deploymentOf(t), address(dep));
        // the creators' stake opens with AUTHORS unbound: no upline, both budgets paid to AIRDROP as liquid LLGAME
        assertEq(referral.referrerOf(authors), address(0));
        assertEq(staking.nextStakeId(t), 1, "the creators' stake alone");
        LLGAMEStaking.StakeInfo memory a = staking.stakeInfo(t, 0);
        assertEq(a.staker, authors);
        assertEq(a.principal, AUTHORS_SUPPLY);
        assertEq(a.reward, 576_000 * U, "288% of the principal");
        assertEq(staking.activeStakeOf(t, authors), AUTHORS_SUPPLY);
        assertEq(staking.activeStakeOf(t, airdrop), 0, "no AIRDROP stake");
        assertEq(token.balanceOf(airdrop), CREATORS_BUDGETS, "the 20% referral and 10% premium budgets, liquid");
        assertEq(staking.reserve(t), TOTAL - 1_836_000 * U, "R_launch");
        assertEq(staking.reserve(t), R_LAUNCH);
        assertEq(token.balanceOf(address(staking)), TOTAL - POOL_SUPPLY_CAP - CREATORS_BUDGETS);
        assertEq(token.balanceOf(address(staking)) + token.balanceOf(airdrop), TOTAL - POOL_SUPPLY_CAP);
        assertEq(token.balanceOf(address(dep)), POOL_SUPPLY_CAP);
        assertEq(token.balanceOf(authors), 0, "nothing to AUTHORS");
        _assertSolvent(t);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-CLOSE ledger
    function test_closeFundsLedger() public {
        uint256 r0 = staking.reserve(t);
        _close(); // 10,000 LLGAME of the cap with 10 BNB
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertEq(staking.reserve(t) - r0, POOL_SUPPLY_CAP - 10_000 * U, "the unused rest of the cap");
        assertEq(staking.reserve(t), R_LAUNCH + POOL_SUPPLY_CAP - 10_000 * U);
        assertEq(token.balanceOf(address(dep)), 0);
        assertEq(token.balanceOf(address(staking)), TOTAL - 10_000 * U - CREATORS_BUDGETS);
        assertEq(token.balanceOf(airdrop), CREATORS_BUDGETS);
        _assertSolvent(t);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ABORT ledger
    function test_abortFundsLedger() public {
        vm.prank(authors);
        dep.setPoolAmounts(10_000 * U, 10 ether);
        _supply(4 ether);
        uint256 r0 = staking.reserve(t);
        uint256 b0 = authors.balance;
        vm.prank(authors);
        dep.abort();
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Aborted));
        // all LLGAME but the pair's locked minimum liquidity reaches the reserve
        assertEq(staking.reserve(t) - r0, POOL_SUPPLY_CAP - token.balanceOf(address(pair)));
        assertEq(token.balanceOf(address(staking)) + token.balanceOf(address(pair)) + token.balanceOf(airdrop), TOTAL);
        assertEq(token.balanceOf(address(dep)), 0);
        assertApproxEqAbs(authors.balance - b0, 4 ether, 1e9, "the recovered BNB to AUTHORS");
        assertEq(staking.activeStakeOf(t, authors), AUTHORS_SUPPLY, "the creators' stake remains");
        _assertSolvent(t);
    }

    // ----------------------------------------------------------------- ledger

    // syngate: LEGACYLIFE-BSC-STAKING-TOKEN-LEDGER
    function test_tokenLedger() public {
        // LLGAME's ledger opened by the deployment contract's call
        assertEq(staking.airdropOf(t), airdrop);
        assertEq(staking.pairOf(t), address(pair));
        assertEq(staking.deploymentOf(t), address(dep), "the caller of initialize");
        _give(address(this), 1_000 * U);
        token.approve(address(staking), type(uint256).max);
        vm.expectRevert(LLGAMEStaking.AlreadyInitialized.selector);
        staking.initialize(t, alice, address(pair), 1 * U);

        // later funding is pulled from any caller
        uint256 r0 = staking.reserve(t);
        vm.startPrank(alice);
        _give(alice, 100 * U);
        token.approve(address(staking), 100 * U);
        staking.fund(t, 100 * U);
        vm.stopPrank();
        assertEq(staking.reserve(t) - r0, 100 * U);
        assertEq(token.balanceOf(alice), 0);

        // another token: no stake and no funding before its ledger opens
        LLGAME other = new LLGAME();
        address o = address(other);
        other.approve(address(staking), type(uint256).max);
        vm.expectRevert(LLGAMEStaking.NotInitialized.selector);
        staking.stake(o, 1_000 * U, carol);
        vm.expectRevert(LLGAMEStaking.NotInitialized.selector);
        staking.fund(o, 1 * U);
        // a pair not of the token and WBNB is refused
        vm.expectRevert(LLGAMEStaking.InvalidPair.selector);
        staking.initialize(o, bob, address(pair), 1_000_000 * U);
        address mixed = factory.createPair(o, t);
        vm.expectRevert(LLGAMEStaking.InvalidPair.selector);
        staking.initialize(o, bob, mixed, 1_000_000 * U);

        address otherPair = factory.createPair(o, BSC_WBNB);
        uint256 b0 = other.balanceOf(address(this));
        staking.initialize(o, bob, otherPair, 1_000_000 * U);
        assertEq(b0 - other.balanceOf(address(this)), 1_000_000 * U, "the first reserve pulled from the caller");
        assertEq(staking.reserve(o), 1_000_000 * U);
        assertEq(staking.airdropOf(o), bob);
        assertEq(staking.pairOf(o), otherPair);
        assertEq(staking.deploymentOf(o), address(this));

        // the two ledgers never mix: stakes, ids, active stakes, reserves and ecosystem accounts are their own
        uint256 rT = staking.reserve(t);
        uint256 nT = staking.nextStakeId(t);
        uint256 id = staking.stake(o, 1_000 * U, carol);
        assertEq(id, 0, "the other ledger's first stake");
        assertEq(staking.stakeInfo(o, id).staker, carol);
        assertEq(staking.stakeInfo(t, 0).staker, authors, "LLGAME's first stake is the creators'");
        assertEq(staking.activeStakeOf(o, carol), 1_000 * U);
        assertEq(staking.activeStakeOf(t, carol), 0);
        assertEq(staking.activeStakeOf(o, bob), 0, "no AIRDROP stake");
        assertEq(other.balanceOf(bob), 300 * U, "its remainder, liquid, to its own AIRDROP");
        assertEq(staking.reserve(t), rT);
        assertEq(staking.nextStakeId(t), nT);
        assertTrue(staking.excluded(o, bob));
        assertFalse(staking.excluded(t, bob));
        _assertSolvent(t);
        _assertSolvent(o);
    }

    // syngate: LEGACYLIFE-BSC-STAKING-PAIR-ORIGIN
    function test_pairTakenOnItsTokensAloneAndNeverCalledAgain() public {
        // a contract of no factory that names the token and WBNB opens the ledger and is its ecosystem account
        LLGAME other = new LLGAME();
        address o = address(other);
        other.approve(address(staking), type(uint256).max);
        address named = address(new NamedPair(BSC_WBNB, o));
        staking.initialize(o, bob, named, 1_000_000 * U);
        assertEq(staking.pairOf(o), named);
        assertTrue(staking.excluded(o, named), "kept as an ecosystem account");
        vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
        staking.stake(o, 1_000 * U, named);

        // from here on it answers no call at all, and none is made: a stake with its walk and its remainder, at a
        // gas price, a claim and a withdrawal pass without it
        vm.etch(named, hex"fe");
        vm.expectCall(named, bytes(""), 0);
        other.transfer(alice, 10_000 * U);
        vm.startPrank(alice);
        other.approve(address(staking), 1_000 * U);
        uint256 aliceId = staking.stake(o, 1_000 * U, alice);
        vm.stopPrank();
        address erin = _bind("erin", alice);
        other.transfer(erin, 1_000 * U);
        vm.txGasPrice(5 gwei);
        vm.startPrank(erin);
        other.approve(address(staking), 1_000 * U);
        uint256 erinId = staking.stake(o, 1_000 * U, erin);
        vm.stopPrank();
        vm.txGasPrice(0);
        assertEq(other.balanceOf(alice), 9_110 * U, "the walk paid level 1 its share and its 1% award in full");
        assertEq(other.balanceOf(erin), 0, "the payer refunded nothing");
        assertEq(other.balanceOf(bob), (300 + 190) * U, "AIRDROP, liquid: alice's 300 and the 190 of erin's 300 less 110 paid");
        skip(30 days);
        vm.prank(erin);
        staking.claim(o, erinId);
        assertEq(other.balanceOf(erin), 80 * U, "8% in 30 days");
        skip(1080 days);
        vm.prank(alice);
        staking.withdraw(o, aliceId);
        assertEq(other.balanceOf(alice), (9_110 + 1_000 + 2_880) * U);
        _assertSolvent(o);
    }

    // ----------------------------------------------------------------- stakes

    // syngate: LEGACYLIFE-BSC-STAKE-ALLOCATION
    function test_stakeAllocatesRewardAndBudget() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 r0 = staking.reserve(t);
        uint256 id = _stake(alice, 1_000 * U, alice);
        LLGAMEStaking.StakeInfo memory s = staking.stakeInfo(t, id);
        assertEq(s.principal, 1_000 * U);
        assertEq(s.reward, 2_880 * U, "288% of the principal");
        // reward + 20% referral budget + 10% premium budget, and nothing more though a root pays neither budget out
        assertEq(r0 - staking.reserve(t), (2_880 + 200 + 100) * U);
        vm.startPrank(alice);
        token.approve(address(staking), 1_000 * U);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.stake(t, MIN - 1, alice);
        staking.stake(t, MIN, alice);
        vm.stopPrank();
        _assertSolvent(t);

        // the minimum is in base units whatever the token, and a reserve one base unit short of the reward and
        // the two budgets refuses the stake
        Token18 e = new Token18();
        address o = address(e);
        e.approve(address(staking), type(uint256).max);
        staking.initialize(o, bob, factory.createPair(o, BSC_WBNB), 3 * MIN);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.stake(o, MIN - 1, alice);
        uint256 cost = MIN * 288 / 100 + MIN * 20 / 100 + MIN * 10 / 100; // 3.18 × MIN
        vm.expectRevert(LLGAMEStaking.ReserveShort.selector);
        staking.stake(o, MIN, alice);
        staking.fund(o, cost - 3 * MIN - 1);
        vm.expectRevert(LLGAMEStaking.ReserveShort.selector);
        staking.stake(o, MIN, alice);
        staking.fund(o, 1);
        id = staking.stake(o, MIN, alice);
        assertEq(staking.stakeInfo(o, id).principal, MIN);
        assertEq(staking.reserve(o), 0, "the whole reserve: exactly the reward and the two budgets");
        _assertSolvent(o);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-BENEFICIARY
    function test_stakeBeneficiary() public {
        _close();
        _give(alice, 100_000 * U);
        // the stake belongs to the account the payer names, not to the payer
        uint256 id = _stake(alice, 1_000 * U, bob);
        assertEq(staking.stakeInfo(t, id).staker, bob);
        assertEq(staking.activeStakeOf(t, bob), 1_000 * U);
        assertEq(staking.activeStakeOf(t, alice), 0);
        skip(10 days);
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.NotStaker.selector);
        staking.claim(t, id);

        // the zero address and the ecosystem accounts other than AIRDROP are refused
        address[5] memory refused = [address(0), address(pair), address(staking), address(dep), DEAD];
        vm.startPrank(alice);
        token.approve(address(staking), 2_000 * U);
        for (uint256 i; i < refused.length; i++) {
            vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
            staking.stake(t, 1_000 * U, refused[i]);
        }
        id = staking.stake(t, 1_000 * U, airdrop);
        vm.stopPrank();
        assertEq(staking.stakeInfo(t, id).staker, airdrop, "AIRDROP may be staked for");
    }

    // syngate: LEGACYLIFE-BSC-STAKE-PERMIT
    function test_stakeWithPermit() public {
        _close();
        (address owner, uint256 pk) = makeAddrAndKey("owner");
        _give(owner, 100_000 * U);
        uint256 amount = 1_000 * U;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner, address(staking), amount, token.nonces(owner), deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)));
        assertEq(token.allowance(owner, address(staking)), 0, "no approval beforehand");
        vm.prank(owner);
        uint256 id = staking.stakeWithPermit(t, amount, bob, deadline, v, r, s);
        assertEq(staking.stakeInfo(t, id).staker, bob);
        assertEq(staking.activeStakeOf(t, bob), amount);
        assertEq(token.balanceOf(owner), 100_000 * U - amount, "paid by the signer");
    }

    // syngate: LEGACYLIFE-BSC-STAKE-REFERRAL
    function test_stakeWithReferral() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        (address invited, uint256 key) = makeAddrAndKey("invited");
        (, uint256 bobKey) = makeAddrAndKey("bob");
        _give(invited, 1_000 * U);

        // a refused binding, signed by another key, does not fail the stake: the account stays unbound
        uint256 ad0 = token.balanceOf(airdrop);
        vm.startPrank(invited);
        token.approve(address(staking), 1_000 * U);
        staking.stakeWithReferral(t, 1_000 * U, invited, alice, SITE, NONCE, ISSUED_AT, _sign(bobKey, invited, alice));
        vm.stopPrank();
        assertEq(staking.activeStakeOf(t, invited), 1_000 * U);
        assertEq(referral.referrerOf(invited), address(0));
        assertEq(token.balanceOf(airdrop) - ad0, 300 * U, "no upline: both budgets to AIRDROP, liquid");

        // the beneficiary's own signature, passed by another payer, binds before the walk: alice paid in that stake
        uint256 a0 = token.balanceOf(alice);
        ad0 = token.balanceOf(airdrop);
        _give(carol, 1_000 * U);
        vm.startPrank(carol);
        token.approve(address(staking), 1_000 * U);
        staking.stakeWithReferral(t, 1_000 * U, invited, alice, SITE, NONCE, ISSUED_AT, _sign(key, invited, alice));
        vm.stopPrank();
        assertEq(referral.referrerOf(invited), alice);
        assertEq(token.balanceOf(alice) - a0, 140 * U, "level 1 share and the 4% award of her 10,000 LLGAME stake");
        assertEq(token.balanceOf(airdrop) - ad0, 160 * U, "the rest of both budgets to AIRDROP");

        // a binding refused as already written does not fail the stake either
        _give(carol, 1_000 * U);
        vm.startPrank(carol);
        token.approve(address(staking), 1_000 * U);
        staking.stakeWithReferral(t, 1_000 * U, invited, carol, SITE, NONCE, ISSUED_AT, _sign(key, invited, carol));
        vm.stopPrank();
        assertEq(referral.referrerOf(invited), alice);
        assertEq(staking.activeStakeOf(t, invited), 3_000 * U);

        // a binding that ran out of gas is no refusal: the stake reverts whole, though the gas left would finish it
        LLGAMEStaking burning = _burningStaking();
        _give(carol, 1_000 * U);
        uint256 c0 = token.balanceOf(carol);
        vm.startPrank(carol);
        token.approve(address(burning), 1_000 * U);
        vm.expectRevert(LLGAMEStaking.BindOutOfGas.selector);
        burning.stakeWithReferral(t, 1_000 * U, invited, alice, SITE, NONCE, ISSUED_AT, hex"");
        vm.stopPrank();
        assertEq(burning.nextStakeId(t), 0, "no stake opened unbound");
        assertEq(burning.activeStakeOf(t, invited), 0);
        assertEq(token.balanceOf(carol), c0, "the principal stays with the payer");
        _assertSolvent(t);
    }

    /// @dev `owner`'s permit of `value` to the staking contract, signed by `key`, valid for an hour.
    function _stakePermit(uint256 key, address owner, uint256 value)
        internal
        view
        returns (LLGAMEStaking.PermitSignature memory)
    {
        return _permitTo(address(staking), key, owner, value);
    }

    /// @dev `owner`'s permit of `value` to `spender`, signed by `key`, valid for an hour.
    function _permitTo(address spender, uint256 key, address owner, uint256 value)
        internal
        view
        returns (LLGAMEStaking.PermitSignature memory p)
    {
        p.deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner, spender, value, token.nonces(owner), p.deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(key, keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)));
        p.v = v;
        p.r = r;
        p.s = s;
    }

    // syngate: LEGACYLIFE-BSC-STAKE-PERMIT-REFERRAL
    function test_stakeWithPermitAndReferral() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        (address invited, uint256 key) = makeAddrAndKey("invited");
        _give(invited, 2_000 * U);
        uint256 a0 = token.balanceOf(alice);
        LLGAMEStaking.ReferralBinding memory b = LLGAMEStaking.ReferralBinding({
            referrer: alice, site: SITE, nonce: NONCE, issuedAt: ISSUED_AT, signature: _sign(key, invited, alice)
        });

        // the first stake of an invited account: no approval and no binding beforehand, both signed, one transaction
        LLGAMEStaking.PermitSignature memory p = _stakePermit(key, invited, 1_000 * U);
        assertEq(token.allowance(invited, address(staking)), 0, "no approval beforehand");
        assertEq(referral.referrerOf(invited), address(0), "no binding beforehand");
        uint256 ad0 = token.balanceOf(airdrop);
        vm.prank(invited);
        uint256 id = staking.stakeWithPermitAndReferral(t, 1_000 * U, invited, b, p);
        assertEq(staking.stakeInfo(t, id).staker, invited);
        assertEq(staking.activeStakeOf(t, invited), 1_000 * U);
        assertEq(token.balanceOf(invited), 1_000 * U, "paid on the signed approval");
        assertEq(referral.referrerOf(invited), alice, "bound on the signed agreement");
        assertEq(token.balanceOf(alice) - a0, 140 * U, "bound before the walk: level 1 share and 4% award");
        assertEq(token.balanceOf(airdrop) - ad0, 160 * U, "the rest of both budgets to AIRDROP");

        // a permit submitted ahead by someone else and a binding already written fail neither: the allowance stakes
        p = _stakePermit(key, invited, 1_000 * U);
        token.permit(invited, address(staking), 1_000 * U, p.deadline, p.v, p.r, p.s);
        vm.prank(invited);
        staking.stakeWithPermitAndReferral(t, 1_000 * U, invited, b, p);
        assertEq(staking.activeStakeOf(t, invited), 2_000 * U);
        assertEq(referral.referrerOf(invited), alice);

        // neither an approval nor a valid permit: the transfer refuses the stake
        _give(invited, 1_000 * U);
        vm.prank(invited);
        vm.expectRevert();
        staking.stakeWithPermitAndReferral(t, 1_000 * U, invited, b, p);

        // a binding that ran out of gas is no refusal: the stake reverts whole, the permit's effect with it
        LLGAMEStaking burning = _burningStaking();
        p = _permitTo(address(burning), key, invited, 1_000 * U);
        uint256 i0 = token.balanceOf(invited);
        vm.prank(invited);
        vm.expectRevert(LLGAMEStaking.BindOutOfGas.selector);
        burning.stakeWithPermitAndReferral(t, 1_000 * U, invited, b, p);
        assertEq(burning.nextStakeId(t), 0, "no stake opened unbound");
        assertEq(token.allowance(invited, address(burning)), 0, "the permit reverted with the stake");
        assertEq(token.balanceOf(invited), i0, "the principal stays with the payer");
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-CLAIM
    function test_claim() public {
        _close();
        _give(carol, 1_000 * U);
        uint256 id = _stake(carol, 1_000 * U, alice); // carol pays, alice stakes
        uint256 start = block.timestamp;
        assertEq(staking.claimable(t, id), 0);
        vm.warp(start + 270 days);
        assertEq(staking.claimable(t, id), 720 * U, "a quarter of the term, a quarter of 2,880");

        // the staker alone: neither the payer nor another account
        vm.prank(carol);
        vm.expectRevert(LLGAMEStaking.NotStaker.selector);
        staking.claim(t, id);
        vm.prank(bob);
        vm.expectRevert(LLGAMEStaking.NotStaker.selector);
        staking.claim(t, id);

        vm.prank(alice);
        staking.claim(t, id);
        assertEq(token.balanceOf(alice), 720 * U);
        assertEq(staking.claimable(t, id), 0);
        vm.warp(start + 810 days);
        assertEq(staking.claimable(t, id), 1_440 * U, "accrued since, the claimed part kept");
        vm.warp(start + 2_000 days);
        assertEq(staking.claimable(t, id), 2_160 * U, "capped by the allocated reward");
        vm.prank(alice);
        staking.claim(t, id);
        assertEq(token.balanceOf(alice), 2_880 * U);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-WITHDRAW
    function test_withdraw() public {
        _close();
        _give(alice, 1_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);
        uint256 start = block.timestamp;
        vm.warp(start + 540 days);
        vm.prank(alice);
        staking.claim(t, id);
        assertEq(token.balanceOf(alice), 1_440 * U);

        vm.warp(start + 1080 days - 1);
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.NotMatured.selector);
        staking.withdraw(t, id);

        vm.warp(start + 1080 days);
        vm.prank(bob);
        vm.expectRevert(LLGAMEStaking.NotStaker.selector);
        staking.withdraw(t, id);
        vm.prank(alice);
        staking.withdraw(t, id);
        assertEq(token.balanceOf(alice), 1_440 * U + 2_440 * U, "principal and unclaimed reward");
        assertEq(staking.activeStakeOf(t, alice), 0);
        assertEq(staking.claimable(t, id), 0);
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.AlreadyWithdrawn.selector);
        staking.withdraw(t, id);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-DELEGATION
    function test_delegate() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);

        // the staker alone, both parts at least the minimum, the delegate no excluded account
        vm.prank(bob);
        vm.expectRevert(LLGAMEStaking.NotStaker.selector);
        staking.delegateStake(t, id, 250 * U, bob);
        vm.startPrank(alice);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.delegateStake(t, id, MIN - 1, bob);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.delegateStake(t, id, 1_000 * U - (MIN - 1), bob);
        vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
        staking.delegateStake(t, id, 250 * U, address(pair));
        vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
        staking.delegateStake(t, id, 250 * U, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 540 days);

        uint256 b0 = token.balanceOf(alice);
        vm.prank(alice);
        uint256 did = staking.delegateStake(t, id, 250 * U, bob);
        assertEq(token.balanceOf(alice) - b0, 1_440 * U, "accrued reward paid before split");

        LLGAMEStaking.StakeInfo memory o = staking.stakeInfo(t, id);
        LLGAMEStaking.StakeInfo memory d = staking.stakeInfo(t, did);
        assertEq(d.staker, bob);
        assertEq(o.principal, 750 * U);
        assertEq(d.principal, 250 * U);
        assertEq(o.reward, 2_160 * U);
        assertEq(d.reward, 720 * U, "pro rata");
        assertEq(d.claimed, 360 * U);
        assertEq(uint256(o.claimed) + d.claimed, 1_440 * U);
        assertEq(d.start, o.start, "the same unlock date");
        assertEq(staking.claimable(t, did), 0);
        assertEq(staking.activeStakeOf(t, alice), 750 * U);
        assertEq(staking.activeStakeOf(t, bob), 250 * U);

        // full delegation of the rest: the stake changes hands
        uint256 nextId = staking.nextStakeId(t);
        vm.prank(alice);
        uint256 did2 = staking.delegateStake(t, id, 750 * U, carol);
        assertEq(did2, id);
        assertEq(staking.nextStakeId(t), nextId, "no new stake record");
        LLGAMEStaking.StakeInfo memory reassigned = staking.stakeInfo(t, id);
        assertEq(reassigned.staker, carol);
        assertEq(reassigned.principal, 750 * U);
        assertEq(reassigned.start, o.start);
        assertEq(staking.activeStakeOf(t, alice), 0);
        assertEq(staking.activeStakeOf(t, carol), 750 * U);

        // both parts unlock at the original date: the delegate cannot withdraw before it
        vm.warp(uint256(o.start) + 1080 days - 1);
        vm.prank(bob);
        vm.expectRevert(LLGAMEStaking.NotMatured.selector);
        staking.withdraw(t, did);
        vm.warp(uint256(o.start) + 1080 days);
        b0 = token.balanceOf(carol);
        vm.prank(carol);
        staking.withdraw(t, did2);
        assertEq(token.balanceOf(carol) - b0, 750 * U + 1_080 * U);
        b0 = token.balanceOf(bob);
        vm.prank(bob);
        staking.withdraw(t, did);
        assertEq(token.balanceOf(bob) - b0, 250 * U + 360 * U);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-DELEGATION-FULL
    function test_fullDelegation() public {
        _close();
        _give(alice, 1_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);
        vm.warp(block.timestamp + 270 days);
        LLGAMEStaking.StakeInfo memory before = staking.stakeInfo(t, id);
        uint256 next = staking.nextStakeId(t);

        vm.expectEmit(true, true, true, true, address(staking));
        emit LLGAMEStaking.StakeDelegated(t, bob, alice, id, id, 1_000 * U);
        vm.prank(alice);
        uint256 did = staking.delegateStake(t, id, 1_000 * U, bob);

        // the stake itself, under its id, now bob's; no new stake opened
        assertEq(did, id);
        assertEq(staking.nextStakeId(t), next, "no new stake");
        LLGAMEStaking.StakeInfo memory s = staking.stakeInfo(t, id);
        assertEq(s.staker, bob);
        assertEq(s.principal, before.principal);
        assertEq(s.reward, before.reward);
        assertEq(s.start, before.start);
        assertEq(s.claimed, 720 * U, "alice's accrued reward settled to her first");
        assertEq(token.balanceOf(alice), 720 * U);
        assertEq(staking.activeStakeOf(t, alice), 0);
        assertEq(staking.activeStakeOf(t, bob), 1_000 * U);

        // alice keeps no right over it; bob claims and, at the original unlock, withdraws it
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.NotStaker.selector);
        staking.claim(t, id);
        vm.warp(uint256(s.start) + 1080 days);
        vm.prank(bob);
        staking.withdraw(t, id);
        assertEq(token.balanceOf(bob), 1_000 * U + 2_160 * U);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-RECEIVED
    function test_receivedPrincipal() public {
        FeeToken f = new FeeToken();
        address o = address(f);
        f.approve(address(staking), type(uint256).max);
        // the first reserve is credited as received too: 10,000,000 sent, 9,000,000 arrive
        staking.initialize(o, bob, factory.createPair(o, BSC_WBNB), 10_000_000 * U);
        assertEq(staking.reserve(o), 9_000_000 * U);
        f.transfer(alice, 2_000 * U); // 1,800 arrive

        // alice sends 1,000: 900 arrive, and the stake is allocated on 900
        vm.startPrank(alice);
        f.approve(address(staking), type(uint256).max);
        uint256 r0 = staking.reserve(o);
        uint256 b0 = f.balanceOf(address(staking));
        uint256 id = staking.stake(o, 1_000 * U, alice);
        vm.stopPrank();
        LLGAMEStaking.StakeInfo memory s = staking.stakeInfo(o, id);
        assertEq(s.principal, 900 * U, "the principal is what arrived");
        assertEq(s.reward, 2_592 * U, "288% of what arrived");
        assertEq(staking.activeStakeOf(o, alice), 900 * U);
        assertEq(staking.activeStakeOf(o, bob), 0, "no AIRDROP stake");
        assertEq(f.balanceOf(bob), 243 * U, "the budgets, 20% and 10% of what arrived, liquid, less the token's own fee");
        assertEq(r0 - staking.reserve(o), (2_592 + 270) * U);
        assertEq(f.balanceOf(address(staking)) - b0, (900 - 270) * U);

        // an amount at the minimum whose arrival falls short of it is refused
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.stake(o, MIN, alice);
        _assertSolvent(o);
    }

    // syngate: LEGACYLIFE-BSC-STAKE-DONATION
    function test_donationNotCredited() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);
        uint256 r0 = staking.reserve(t);
        uint256 b0 = token.balanceOf(address(staking));
        vm.prank(alice);
        token.transfer(address(staking), 100 * U);
        assertEq(token.balanceOf(address(staking)) - b0, 100 * U);
        assertEq(staking.reserve(t), r0, "not the reserve");
        assertEq(staking.activeStakeOf(t, alice), 1_000 * U, "not a stake");
        assertEq(staking.stakeInfo(t, id).reward, 2_880 * U, "not a reward");
        _assertSolvent(t);
    }

    // --------------------------------------------------------------- referral

    // syngate: LEGACYLIFE-BSC-REFERRAL-BINDING payer
    function test_payerBindsNothing() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 1_000 * U, alice);
        // a staker's stake for another account binds it to nobody
        uint256 id = _stake(alice, 1_000 * U, bob);
        assertEq(referral.referrerOf(bob), address(0));
        // nor does a delegation
        vm.prank(bob);
        staking.delegateStake(t, id, 500 * U, carol);
        assertEq(referral.referrerOf(carol), address(0));
        // their own stakes pay the payer nothing
        uint256 a0 = token.balanceOf(alice);
        _give(bob, 1_000 * U);
        _stake(bob, 1_000 * U, bob);
        _give(carol, 1_000 * U);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(carol, 1_000 * U, carol);
        assertEq(token.balanceOf(alice), a0);
        assertEq(token.balanceOf(airdrop) - ad0, 300 * U, "a root: both budgets to AIRDROP, liquid");
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-BINDING transfer
    function test_transferBindsNothing() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 1_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 100 * U);
        assertEq(referral.referrerOf(bob), address(0));
        uint256 a0 = token.balanceOf(alice);
        _stake(bob, 50 * U, bob);
        assertEq(token.balanceOf(alice), a0, "the sender is no upline");
        assertEq(referral.referrerOf(bob), address(0));
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-BINDING airdrop
    function test_ecosystemAccountNeverInWalk() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        // AIRDROP bound to alice in the referral contract: its stakes run no walk
        _bind("airdrop", alice);
        assertEq(referral.referrerOf(airdrop), alice);
        uint256 a0 = token.balanceOf(alice);
        _give(carol, 1_000 * U);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(carol, 1_000 * U, airdrop);
        assertEq(token.balanceOf(alice), a0, "no walk for AIRDROP's stake");
        assertEq(token.balanceOf(airdrop) - ad0, 300 * U, "both budgets to the remainder, liquid");

        // dave bound to AIRDROP, which holds a balance and a stake: AIRDROP is passed over, alice paid at level 2
        _give(airdrop, 1_000 * U);
        _bind("dave", airdrop);
        uint256 d0 = token.balanceOf(airdrop);
        _give(dave, 1_000 * U);
        _stake(dave, 1_000 * U, dave);
        assertEq(
            token.balanceOf(airdrop) - d0, 210 * U, "AIRDROP paid no share nor award: only the 210 left of both budgets"
        );
        assertEq(token.balanceOf(alice) - a0, 90 * U, "her level 2 share and her 4% award, none of it taken by AIRDROP");
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-SHARE payout
    function test_referralPayout() public {
        _close();
        _trio();
        // bob's stake: alice at level 1, a tenth
        uint256 a0 = token.balanceOf(alice);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(bob, 90 * U, bob);
        assertEq(token.balanceOf(alice) - a0, 9 * U);
        assertEq(token.balanceOf(airdrop) - ad0, 18 * U, "the 27 of both budgets less 9 paid");

        // carol's stake: bob at level 1 a tenth, alice at level 2 a twentieth
        a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        uint256 ad1 = token.balanceOf(airdrop);
        _stake(carol, 1_000 * U, carol);
        assertEq(token.balanceOf(bob) - b0, 100 * U);
        assertEq(token.balanceOf(alice) - a0, 50 * U);
        assertEq(token.balanceOf(airdrop) - ad1, 150 * U);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-SHARE threshold
    function test_payoutNeedsLiquidAndStakeAtEveryLevel() public {
        _close();
        address a2 = makeAddr("a2");
        address b1 = makeAddr("b1");
        address c = makeAddr("c");
        _give(a2, 1 * U);
        _stake(a2, 1 * U, a2);
        _give(b1, 1 * U);
        _stake(b1, 1 * U, b1);
        _bind("b1", a2);
        _bind("c", b1);
        _give(c, 2_000 * U);

        // level 1 b1: stake 1 LLGAME but liquid 1 LLGAME less a base unit; level 2 a2: liquid 1,000 LLGAME but
        // stake 1 LLGAME, short of 2: neither is paid
        deal(t, b1, 1 * U - 1, true);
        deal(t, a2, 1_000 * U, true);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(c, 1_000 * U, c);
        assertEq(token.balanceOf(b1), 1 * U - 1);
        assertEq(token.balanceOf(a2), 1_000 * U);
        assertEq(token.balanceOf(airdrop) - ad0, 300 * U, "both budgets unpaid");

        // b1 at exactly 1 LLGAME liquid, a2 at exactly 2 LLGAME staked: both paid
        deal(t, b1, 1 * U, true);
        _stake(a2, 1 * U, a2);
        assertEq(staking.activeStakeOf(t, a2), 2 * U);
        uint256 a0 = token.balanceOf(a2);
        _stake(c, 1_000 * U, c);
        assertEq(token.balanceOf(b1) - 1 * U, 100 * U);
        assertEq(token.balanceOf(a2) - a0, 50 * U);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-PREMIUM example
    function test_premiumAwardWorkedExample() public {
        _close();
        // the chain of the white paper's example, #1 its root and each account bound to the one before, by active
        // stake in LLGAME: #3 holds 200,000 of its 300,000 by delegation, #2 holds no liquid LLGAME, #4 too little
        // stake for its level, the others 1,000 LLGAME liquid. #9 stakes 100 LLGAME.
        uint256[9] memory staked = [uint256(0), 30_000, 500, 100_000, 5, 1_000, 10, 5_000, 100];
        address[10] memory a;
        for (uint256 i = 1; i <= 9; i++) {
            string memory name = string.concat("ex", vm.toString(i));
            a[i] = makeAddr(name);
            if (i != 9) {
                _give(a[i], staked[i] * U + (i == 2 ? 0 : 1_000 * U));
                _stake(a[i], staked[i] * U, a[i]);
            }
            if (i != 1) _bind(name, a[i - 1]);
        }
        _give(dave, 200_000 * U);
        uint256 id = _stake(dave, 200_000 * U, dave);
        vm.prank(dave);
        staking.delegateStake(t, id, 200_000 * U, a[3]);
        assertEq(staking.activeStakeOf(t, a[3]), 300_000 * U, "delegated stakes count");

        uint256[9] memory before;
        for (uint256 i = 1; i <= 8; i++) {
            before[i] = token.balanceOf(a[i]);
        }
        _give(a[9], 100 * U);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(a[9], 100 * U, a[9]);
        // #8 10; #7 5 + 3% = 8; #6 2.5; #5 1.25, its 1% within the 3% paid; #4 nothing; #3 0.3125 + (8% - 3%) =
        // 5.3125; #2 nothing; #1 0.078125, its 5% within the 8% paid
        uint256[9] memory due =
            [uint256(0), 78_125_000, 0, 5_312_500_000, 0, 1_250_000_000, 2_500_000_000, 8 * U, 10 * U];
        for (uint256 i = 1; i <= 8; i++) {
            assertEq(token.balanceOf(a[i]) - before[i], due[i], string.concat("#", vm.toString(i)));
        }
        assertEq(
            token.balanceOf(airdrop) - ad0, 2_859_375_000, "the 30 of both budgets less 19.140625 of shares and 8 of awards"
        );
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-PREMIUM tiers
    function test_premiumTiersByActiveStakeAlone() public {
        _close();
        // three uplines without a base unit of liquid LLGAME: the nearest stakes 1,000 LLGAME exactly, the 1% tier;
        // the next a base unit short of 3,000, still 1%; the root 1,000,000, the top tier
        address top = makeAddr("pm1");
        _give(top, 1_000_000 * U);
        _stake(top, 1_000_000 * U, top);
        address mid = makeAddr("pm2");
        _give(mid, 3_000 * U - 1);
        _stake(mid, 3_000 * U - 1, mid);
        _bind("pm2", top);
        address near = makeAddr("pm3");
        _give(near, 1_000 * U);
        uint256 nearId = _stake(near, 1_000 * U, near);
        _bind("pm3", mid);
        address s = _bind("pm4", near);
        _give(s, 1_000 * U);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(s, 1_000 * U, s);
        assertEq(token.balanceOf(near), 10 * U, "1% of the stake, and no level share without liquid LLGAME");
        assertEq(token.balanceOf(mid), 0, "its 1% is already paid to a nearer upline");
        assertEq(token.balanceOf(top), 90 * U, "10% less the 1% paid");
        assertEq(token.balanceOf(airdrop) - ad0, 200 * U, "the 10% budget paid out whole and no more, the 20% unpaid");

        // a base unit less under the nearest: below every tier, its 1% goes to the next upline that meets one
        skip(1080 days);
        vm.startPrank(near);
        staking.withdraw(t, nearId);
        token.transfer(dave, token.balanceOf(near));
        vm.stopPrank();
        _give(near, 1_000 * U - 1);
        _stake(near, 1_000 * U - 1, near);
        deal(t, mid, 0, true); // the awards of that stake taken away: no liquid LLGAME again
        deal(t, top, 0, true);
        _give(s, 1_000 * U);
        _stake(s, 1_000 * U, s);
        assertEq(token.balanceOf(near), 0, "below every tier");
        assertEq(token.balanceOf(mid), 10 * U, "the 1% tier, first met here");
        assertEq(token.balanceOf(top), 90 * U);
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-PASS-OVER
    function test_ineligibleUplineIsPassedOver() public {
        _close();
        _trio();
        // alice's stake grows to 10,000 LLGAME, the 4% tier. bob moves all liquid away: ineligible for his level 1
        // share, while his stake of 900 LLGAME is below every tier
        _stake(alice, 9_100 * U, alice);
        uint256 bobLiquid = token.balanceOf(bob);
        vm.prank(bob);
        token.transfer(dave, bobLiquid);
        assertGt(staking.activeStakeOf(t, bob), 1 * U);

        uint256 a0 = token.balanceOf(alice);
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(carol, 1_000 * U, carol);
        assertEq(token.balanceOf(bob), 0, "bob passed over");
        assertEq(token.balanceOf(alice) - a0, 90 * U, "alice paid her level 2 share and her whole 4% award beyond him");
        assertEq(token.balanceOf(airdrop) - ad0, 210 * U, "the 300 of both budgets less 90 paid");
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-WALK-END root
    function test_walkEndsAtRoot() public {
        _close();
        _trio();
        // carol's uplines end with alice, a root at level 2: both are paid their shares in full and the walk ends
        // there, at any gas price, the payer refunded nothing
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        uint256 c0 = token.balanceOf(carol);
        uint256 ad0 = token.balanceOf(airdrop);
        vm.txGasPrice(1_000_000 gwei);
        _stake(carol, 1_000 * U, carol);
        vm.txGasPrice(0);
        assertEq(token.balanceOf(bob) - b0, 100 * U, "level 1 in full");
        assertEq(token.balanceOf(alice) - a0, 50 * U, "level 2 in full");
        assertEq(c0 - token.balanceOf(carol), 1_000 * U, "the payer refunded nothing");
        assertEq(token.balanceOf(airdrop) - ad0, 150 * U, "the 300 of both budgets less both shares");

        // a root staker has no upline: both budgets to AIRDROP
        ad0 = token.balanceOf(airdrop);
        _stake(alice, 1_000 * U, alice);
        assertEq(referral.referrerOf(alice), address(0));
        assertEq(token.balanceOf(airdrop) - ad0, 300 * U, "both budgets to AIRDROP");
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-WALK-END level_30
    function test_walkEndsAfterLevel30() public {
        _close();
        address s = _deepChain(32, "deep-");
        address level1 = makeAddr("deep-31");
        address level30 = makeAddr("deep-2");
        address level31 = makeAddr("deep-1");
        // a stake of 10 x 2^30 LLGAME: the shares halve from 2^30 LLGAME at level 1 to 2 LLGAME at level 30, and
        // level 31, eligible as the others are, would be due 1 LLGAME. Every upline is on the top premium tier, so
        // level 1 takes the whole 10% award, another 2^30 LLGAME
        uint256 amount = 10 * (1 << 30) * U;
        _give(s, amount);
        uint256 b1 = token.balanceOf(level1);
        uint256 b30 = token.balanceOf(level30);
        uint256 b31 = token.balanceOf(level31);
        uint256 b32 = token.balanceOf(makeAddr("deep-0"));
        uint256 ad0 = token.balanceOf(airdrop);
        _stake(s, amount, s);
        // on-chain figure under `--isolate -vv`, the slots of every level cold
        emit log_named_uint("gas of a stake walking 30 paid levels", vm.lastCallGas().gasTotalUsed);
        assertEq(token.balanceOf(level1) - b1, (1 << 31) * U, "level 1: a tenth and the whole 10% award");
        assertEq(token.balanceOf(level30) - b30, 2 * U, "level 30: the tenth halved 29 times");
        assertEq(token.balanceOf(level31), b31, "no level 31");
        assertEq(token.balanceOf(makeAddr("deep-0")), b32, "nor any above it");
        assertEq(token.balanceOf(s), 0, "the payer refunded nothing");
        assertEq(
            token.balanceOf(airdrop) - ad0, 2 * U, "the budgets of 3 x 2^30 LLGAME less the 30 shares and the award"
        );
        _assertSolvent(t);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-WALK-END gas
    function test_walkSameWhateverGasAndGasPrice() public {
        _close();
        address s = _deepChain(32, "gas-");
        address level1 = makeAddr("gas-31");
        uint256 amount = 10 * (1 << 30) * U;
        _give(s, amount);
        vm.prank(s);
        token.approve(address(staking), amount);
        uint256 b1 = token.balanceOf(level1);
        uint256 ad0 = token.balanceOf(airdrop);
        uint256 next = staking.nextStakeId(t);
        bytes memory data = abi.encodeCall(staking.stake, (t, amount, s));
        uint256 passed;
        uint256 failed;
        // the same stake, 30 levels deep, on 100,000 to 3,000,000 gas and at gas prices from zero to a million gwei:
        // it either passes with the whole walk paid and nothing refunded, or reverts whole
        for (uint256 i = 1; i <= 30; i++) {
            uint256 snap = vm.snapshotState();
            vm.txGasPrice(i % 3 == 0 ? 0 : i % 3 == 1 ? 1 gwei : 1_000_000 gwei);
            vm.prank(s);
            (bool ok,) = address(staking).call{gas: i * 100_000}(data);
            if (ok) {
                passed++;
                assertEq(token.balanceOf(level1) - b1, (1 << 31) * U, "level 1 paid its share and award in full");
                assertEq(token.balanceOf(airdrop) - ad0, 2 * U, "all 30 levels paid in full");
                assertEq(token.balanceOf(s), 0, "the payer refunded nothing");
            } else {
                failed++;
                assertEq(token.balanceOf(level1), b1, "nothing paid");
                assertEq(token.balanceOf(s), amount, "nothing pulled");
                assertEq(staking.nextStakeId(t), next, "no stake opened");
            }
            vm.revertToState(snap);
        }
        vm.txGasPrice(0);
        assertGt(failed, 0, "a call short of gas reverts whole");
        assertGt(passed, 0);
    }

    uint256 constant ROOT_STAKE_GAS = 205_000; // a stake with no upline needs no more
    uint256 constant LEVEL_GAS = 38_000;       // a level examined adds no more

    /// @dev Run with `--isolate -vv` for on-chain figures: every call is then a transaction of its own and the
    ///      slots of a level are cold, as they are on chain.
    // syngate: LEGACYLIFE-BSC-REFERRAL-WALK-GAS
    function test_walkGasBoundedByLevel() public {
        _close();
        address s = makeAddr("gas-warm");
        _give(s, 2_000 * U);
        _stakeGas(s, 1_000 * U);

        // no upline: the same gas from the minimum principal to a billion LLGAME
        uint256 root;
        uint256[3] memory amounts = [MIN, 1_000 * U, 1_000_000_000 * U];
        for (uint256 j; j < 3; j++) {
            s = makeAddr(string.concat("gas-root", vm.toString(j)));
            _give(s, 2 * amounts[j]);
            uint256 g = _stakeGas(s, amounts[j]);
            emit log_named_uint("gas of a stake with no upline", g);
            if (j != 0) assertApproxEqAbs(g, root, 1_000, "the same gas whatever the amount");
            if (g > root) root = g;
        }
        assertLe(root, ROOT_STAKE_GAS, "a stake with no upline");

        // one to five levels of each kind: every level adds no more than the bound
        string[4] memory kinds = ["nothing", "its level share", "a premium award", "both"];
        for (uint256 k; k < 4; k++) {
            uint256 prev = root;
            uint256 most;
            for (uint256 d = 1; d <= 5; d++) {
                s = _gasChain(string.concat("gas", vm.toString(k), "-", vm.toString(d), "-"), d, k);
                _give(s, 2_000 * U);
                uint256 g = _stakeGas(s, 1_000 * U);
                assertLe(g, prev + LEVEL_GAS, string.concat("a level paid ", kinds[k]));
                if (g > prev && g - prev > most) most = g - prev;
                prev = g;
            }
            emit log_named_uint(string.concat("most gas added by a level paid ", kinds[k]), most);
        }

        // the costliest walk: ten premium awards to accounts holding no LLGAME, then twenty level shares
        s = _gasChain("gas30-", 30, 2);
        uint256 amount = 10 * (1 << 30) * U;
        _give(s, 2 * amount);
        uint256 g30 = _stakeGas(s, amount);
        emit log_named_uint("gas of the costliest stake of 30 levels", g30);
        assertLe(g30, ROOT_STAKE_GAS + 30 * LEVEL_GAS, "no stake needs more than the 30-level figure");
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-REMAINDER
    function test_unpaidBudgetTransferredToAirdrop() public {
        _close();
        _trio();
        // alice's stake grows to 10,000 LLGAME, the 4% tier. carol's stake: bob and alice paid 150 of the 200
        // referral budget, alice 40 of the 100 premium budget; the rest of both goes to AIRDROP in the same call
        _stake(alice, 9_100 * U, alice);
        uint256 next = staking.nextStakeId(t);
        uint256 r0 = staking.reserve(t);
        uint256 a0 = token.balanceOf(airdrop);
        uint256 active0 = staking.activeStakeOf(t, airdrop);
        vm.startPrank(carol);
        token.approve(address(staking), 1_000 * U);
        vm.expectEmit(t);
        emit IERC20.Transfer(address(staking), airdrop, 110 * U);
        staking.stake(t, 1_000 * U, carol);
        vm.stopPrank();
        assertEq(token.balanceOf(airdrop) - a0, 110 * U, "what the two budgets leave unpaid, 50 and 60, liquid");
        assertEq(staking.nextStakeId(t), next + 1, "carol's stake alone: no stake opened for AIRDROP");
        assertEq(staking.activeStakeOf(t, airdrop), active0, "AIRDROP's active stake unchanged");
        assertEq(r0 - staking.reserve(t), (2_880 + 200 + 100) * U, "no reward allocated for the remainder");
        _assertSolvent(t);
    }

    // ----------------------------------------------------------------- events

    /// @dev The logs the staking contract emitted under the event `signature` since `vm.recordLogs()`, in order.
    function _stakingLogs(string memory signature) internal returns (Vm.Log[] memory found) {
        bytes32 topic0 = keccak256(bytes(signature));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        found = new Vm.Log[](logs.length);
        uint256 n;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(staking) && logs[i].topics[0] == topic0) found[n++] = logs[i];
        }
        assembly {
            mstore(found, n)
        }
    }

    /// @dev An address as the topic an indexed parameter makes of it.
    function _topic(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    // syngate: LEGACYLIFE-BSC-STAKING-EVENT-FILTERS
    function test_eventsIndexedByTokenAndAccount() public {
        _close();
        // Initialized: the ledger of a token that charges its transfers names the reserve received, 900 of 1,000
        FeeToken f = new FeeToken();
        f.approve(address(staking), type(uint256).max);
        address feePair = factory.createPair(address(f), BSC_WBNB);
        vm.recordLogs();
        staking.initialize(address(f), bob, feePair, 1_000 * U);
        Vm.Log[] memory logs = _stakingLogs("Initialized(address,address,address,address,uint256)");
        assertEq(logs.length, 1, "Initialized");
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[1], _topic(address(f)), "token");
        assertEq(logs[0].topics[2], _topic(bob), "AIRDROP");
        assertEq(logs[0].topics[3], _topic(feePair), "pair");
        assertEq(logs[0].data, abi.encode(address(this), 900 * U), "the deployment contract and the reserve received");

        // Staked: alice pays a stake of bob's
        _give(alice, 1_000 * U);
        vm.recordLogs();
        uint256 id = _stake(alice, 1_000 * U, bob);
        logs = _stakingLogs("Staked(address,address,address,uint256,uint256)");
        assertEq(logs.length, 1, "Staked");
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[1], _topic(t), "token");
        assertEq(logs[0].topics[2], _topic(bob), "staker");
        assertEq(logs[0].topics[3], _topic(alice), "payer");
        assertEq(logs[0].data, abi.encode(id, 1_000 * U), "the stake id, unindexed, and the amount");

        // StakeDelegated: bob splits 400 LLGAME of it to carol
        vm.recordLogs();
        vm.prank(bob);
        uint256 delegatedId = staking.delegateStake(t, id, 400 * U, carol);
        logs = _stakingLogs("StakeDelegated(address,address,address,uint256,uint256,uint256)");
        assertEq(logs.length, 1, "StakeDelegated");
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[1], _topic(t), "token");
        assertEq(logs[0].topics[2], _topic(carol), "delegate");
        assertEq(logs[0].topics[3], _topic(bob), "delegating staker");
        assertEq(logs[0].data, abi.encode(id, delegatedId, 400 * U), "both stake ids, unindexed, and the amount");
    }

    // syngate: LEGACYLIFE-BSC-STAKE-WITHDRAWN
    function test_withdrawalRecorded() public {
        _close();
        _give(alice, 1_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);
        uint256 start = block.timestamp;
        vm.warp(start + 540 days);
        vm.prank(alice);
        staking.claim(t, id); // half the reward of 2,880 claimed ahead
        vm.warp(start + 1080 days);
        uint256 b0 = token.balanceOf(alice);
        vm.recordLogs();
        vm.prank(alice);
        staking.withdraw(t, id);
        Vm.Log[] memory logs = _stakingLogs("Withdrawn(address,address,uint256,uint256,uint256)");
        assertEq(logs.length, 1, "Withdrawn");
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[1], _topic(t), "token");
        assertEq(logs[0].topics[2], _topic(alice), "staker");
        assertEq(
            logs[0].data, abi.encode(id, 1_000 * U, 1_440 * U), "the stake, the principal returned, the reward paid with it"
        );
        assertEq(token.balanceOf(alice) - b0, 2_440 * U, "the two are what the withdrawal transferred");
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-PAID
    function test_referralPayoutRecorded() public {
        _close();
        _trio();
        // dave -> carol -> bob -> alice. carol stakes nothing: passed over at level 1. bob, 900 LLGAME staked, is due
        // his level 2 share alone; alice, her stake grown to 10,000 LLGAME, her level 3 share and the 4% award
        _stake(alice, 9_100 * U, alice);
        _bind("dave", carol);
        _give(dave, 1_000 * U);
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        uint256 ad0 = token.balanceOf(airdrop);
        vm.recordLogs();
        uint256 id = _stake(dave, 1_000 * U, dave);
        Vm.Log[] memory logs = _stakingLogs("ReferralPaid(address,address,address,uint256,uint256,uint256,uint256)");
        assertEq(logs.length, 2, "one for each upline paid: none for carol, passed over, nor for AIRDROP's remainder");
        for (uint256 i; i < 2; i++) {
            assertEq(logs[i].topics.length, 4);
            assertEq(logs[i].topics[1], _topic(t), "token");
            assertEq(logs[i].topics[2], _topic(i == 0 ? bob : alice), "upline");
            assertEq(logs[i].topics[3], _topic(dave), "staker");
        }
        assertEq(logs[0].data, abi.encode(id, 2, 50 * U, 0), "bob: the stake, level 2, its share, no award");
        assertEq(logs[1].data, abi.encode(id, 3, 25 * U, 40 * U), "alice: the stake, level 3, its share, 4% award");
        assertEq(token.balanceOf(bob) - b0, 50 * U, "share and award sum to the transfer made");
        assertEq(token.balanceOf(alice) - a0, 65 * U, "share and award sum to the transfer made");
        assertEq(token.balanceOf(airdrop) - ad0, 185 * U, "the remainder, transferred with no record of this kind");
    }
}
