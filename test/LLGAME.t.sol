// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LLGAME} from "../contracts/LLGAME.sol";
import {LLGAMEStaking} from "../contracts/LLGAMEStaking.sol";
import {LLGAMEDeployment} from "../contracts/LLGAMEDeployment.sol";

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
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256, uint256, address, bytes calldata) external;
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @dev A staking contract answering the launch interface and nothing more: per token a reserve, AIRDROP, pair,
///      deployment contract and active stakes. `misreportPair` makes it answer a pair other than the one passed.
contract MockLaunchStaking {
    struct Ledger {
        address airdrop;
        address pair;
        address deployment;
        uint256 reserve;
    }

    mapping(address => Ledger) public ledger;
    mapping(address => mapping(address => uint256)) public activeStakeOf;
    bool public misreportPair;

    function setMisreportPair(bool on) external { misreportPair = on; }

    function reserve(address token) external view returns (uint256) { return ledger[token].reserve; }

    function airdropOf(address token) external view returns (address) { return ledger[token].airdrop; }

    function pairOf(address token) external view returns (address) {
        return misreportPair ? address(1) : ledger[token].pair;
    }

    function deploymentOf(address token) external view returns (address) { return ledger[token].deployment; }

    function initialize(address token, address airdrop, address pair, uint256 amount) external {
        Ledger storage l = ledger[token];
        require(l.airdrop == address(0) && airdrop != address(0) && amount != 0, "initialize");
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
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        activeStakeOf[token][beneficiary] += amount;
        return 0;
    }
}

/// @dev The chain every test runs on: WBNB and the PancakeSwap v2 factory at the addresses the deployment contract
///      names, the token published by its holder and the deployment contract published for it, not yet launched.
abstract contract LLGAMEChain is Test {
    uint256 constant U = 1e9; // one LLGAME
    uint256 constant TOTAL = 340_000_000_000_000_000_000_000_000_000 * U;
    uint256 constant POOL_SUPPLY_CAP = 1_000_000 * U;
    uint256 constant AUTHORS_SUPPLY = 500_000 * U;
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
        mock = new MockLaunchStaking();
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
        assertEq(mock.reserve(address(token)), TOTAL - POOL_SUPPLY_CAP - AUTHORS_SUPPLY, "the reserve");
        assertEq(mock.airdropOf(address(token)), airdrop);
        assertEq(mock.pairOf(address(token)), address(pair));
        assertEq(mock.deploymentOf(address(token)), address(dep), "the caller of initialize");
        assertEq(mock.activeStakeOf(address(token), authors), AUTHORS_SUPPLY, "the creators' stake");
        assertEq(token.balanceOf(address(mock)), TOTAL - POOL_SUPPLY_CAP);
        assertEq(token.balanceOf(address(dep)), POOL_SUPPLY_CAP);
        assertEq(token.balanceOf(authors), 0, "nothing to AUTHORS");

        MockLaunchStaking other = new MockLaunchStaking();
        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.setStaking(address(other)); // once
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-STAKING refused
    function test_setStakingRefused() public {
        _launch();
        MockLaunchStaking holding = new MockLaunchStaking();
        deal(address(token), address(holding), 1);
        MockLaunchStaking initialized = new MockLaunchStaking();
        deal(address(token), address(this), 1);
        token.approve(address(initialized), 1);
        initialized.initialize(address(token), airdrop, address(pair), 1);
        MockLaunchStaking liar = new MockLaunchStaking();
        liar.setMisreportPair(true);

        vm.startPrank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidStaking.selector);
        dep.setStaking(alice); // no code
        vm.expectRevert(LLGAMEDeployment.InvalidStaking.selector);
        dep.setStaking(address(holding)); // holds LLGAME
        vm.expectRevert(LLGAMEDeployment.InvalidStaking.selector);
        dep.setStaking(address(initialized)); // the token already initialized there
        vm.expectRevert(LLGAMEDeployment.LaunchCheckFailed.selector);
        dep.setStaking(address(liar)); // reports another pair than the one passed
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

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-CLOSE
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

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ABORT
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
        assertEq(token.balanceOf(address(mock)), TOTAL - POOL_SUPPLY_CAP + funded);
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
        MockLaunchStaking m2 = new MockLaunchStaking();
        b0 = authors.balance;
        vm.startPrank(authors);
        d2.launch(address(this), 0, 0, 0, 0);
        d2.setStaking(address(m2));
        d2.abort();
        vm.stopPrank();
        assertEq(m2.reserve(address(t2)), TOTAL - AUTHORS_SUPPLY, "the whole cap to the reserve");
        assertEq(t2.balanceOf(address(d2)), 0);
        assertEq(authors.balance, b0);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-NETWORK
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
///      permit, the staking contract set and, by `_close`, a pool of 10,000 LLGAME and 10 BNB supplied and closed.
contract LLGAMETest is LLGAMEChain {
    LLGAMEStaking staking;

    function setUp() public override {
        super.setUp();
        _launch();
        staking = new LLGAMEStaking(IERC20(address(token)), airdrop, address(pair));
        vm.prank(authors);
        dep.setStaking(address(staking));
    }

    function _close() internal {
        vm.startPrank(authors);
        dep.setPoolAmounts(10_000 * U, 10 ether);
        vm.stopPrank();
        _supply(10 ether);
        vm.prank(authors);
        dep.close();
    }

    function _stake(address payer, uint256 amount, address beneficiary) internal returns (uint256 id) {
        vm.startPrank(payer);
        token.approve(address(staking), amount);
        id = staking.stake(amount, beneficiary);
        vm.stopPrank();
    }

    /// @dev Gives `who` LLGAME out of thin air: the pool holds only 10,000 LLGAME, too little for the staking scenarios.
    function _give(address who, uint256 amount) internal {
        deal(address(token), who, token.balanceOf(who) + amount, true);
    }

    function _assertSolvent() internal view {
        uint256 owed = staking.reserve();
        uint256 n = staking.nextStakeId();
        for (uint256 i; i < n; i++) {
            LLGAMEStaking.StakeInfo memory s = staking.stakeInfo(i);
            owed += uint256(s.principal) + s.reward - s.claimed;
        }
        assertLe(owed, token.balanceOf(address(staking)), "insolvent");
    }

    // --------------------------------------------------------------- referral

    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-SHARE payout
    function test_referralBindingAndPayout() public {
        _close();
        _give(alice, 100_000 * U);
        assertFalse(staking.seen(alice), "a purchase marks nothing");
        assertEq(staking.referrerOf(alice), address(0));

        uint256 aBal = token.balanceOf(alice);
        _stake(alice, aBal / 2, alice);
        assertTrue(staking.seen(alice));
        assertEq(staking.referrerOf(alice), address(0), "self-staked: a root");

        // alice (a staker) sends bob LLGAME: no binding; her stake for him binds him to her
        vm.prank(alice);
        token.transfer(bob, 1_000 * U);
        assertFalse(staking.seen(bob));
        _stake(alice, 500 * U, bob);
        assertEq(staking.referrerOf(bob), alice);

        // bob stakes 1000: alice is eligible at level 1 and gets 10%
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 nextId = staking.nextStakeId();
        _stake(bob, 1_000 * U, bob);
        assertEq(token.balanceOf(alice) - aliceBefore, 100 * U);
        LLGAMEStaking.StakeInfo memory r = staking.stakeInfo(nextId + 1);
        assertEq(r.staker, airdrop);
        assertEq(r.principal, 100 * U); // 200 budget − 100 paid
        assertEq(r.reward, 288 * U);    // ordinary reward on the remainder

        // a transfer binds nothing; a stake opened by a payer without a stake leaves the beneficiary a root
        vm.prank(alice);
        token.transfer(carol, 2_000 * U);
        assertFalse(staking.seen(carol));
        _stake(carol, 500 * U, dave);
        assertTrue(staking.seen(dave));
        assertEq(staking.referrerOf(dave), address(0), "carol has no stake yet");
        assertEq(staking.referrerOf(carol), address(0));
        _assertSolvent();
    }

    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-SHARE threshold
    function test_payoutNeedsLiquidAndStakeAtEveryLevel() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 30_000 * U);
        _stake(alice, 1_000 * U, bob); // binds bob to alice
        assertEq(staking.referrerOf(bob), alice);
        _stake(bob, 10_000 * U, bob);
        vm.prank(bob);
        token.transfer(carol, 1_000 * U);
        _stake(bob, 1_000 * U, carol); // binds carol to bob
        assertEq(staking.referrerOf(carol), bob);

        // level 1 bob: liquid ≥ 1 LLGAME and stake ≥ 1 LLGAME → paid 100; level 2 alice: liquid ≥ 2 LLGAME, stake ≥ 2 LLGAME → paid 50
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        _stake(carol, 1_000 * U, carol);
        assertEq(token.balanceOf(bob) - b0, 100 * U);
        assertEq(token.balanceOf(alice) - a0, 50 * U);

        // bob moves all liquid LLGAME away → ineligible at level 1 and passed over, alice is still paid at level 2
        uint256 bobLiquid = token.balanceOf(bob);
        vm.prank(bob);
        token.transfer(dave, bobLiquid);
        vm.prank(alice);
        token.transfer(carol, 1_000 * U);
        a0 = token.balanceOf(alice);
        _stake(carol, 1_000 * U, carol);
        assertEq(token.balanceOf(alice) - a0, 50 * U, "bob passed over, alice paid at level 2");
        _assertSolvent();
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-PASS-OVER
    function test_ineligibleUplineIsPassedOver() public {
        _close();
        _give(alice, 100_000 * U);
        // alice → bob → carol referral chain
        _stake(alice, 10_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 10_000 * U);
        _stake(alice, 1_000 * U, bob); // binds bob to alice
        assertEq(staking.referrerOf(bob), alice);
        _stake(bob, 1_000 * U, bob);
        vm.prank(bob);
        token.transfer(carol, 5_000 * U);
        _stake(bob, 1_000 * U, carol); // binds carol to bob
        assertEq(staking.referrerOf(carol), bob);

        // bob moves all liquid away → level 1 ineligible on balanceOf check
        uint256 bobLiquid = token.balanceOf(bob);
        vm.prank(bob);
        token.transfer(dave, bobLiquid);
        assertEq(token.balanceOf(bob), 0);
        assertGt(staking.activeStakeOf(bob), 1, "bob's stake principal still held");

        // carol stakes 1000: bob ineligible and unpaid, alice paid her level 2 share
        uint256 a0 = token.balanceOf(alice);
        _stake(carol, 1_000 * U, carol);
        assertEq(token.balanceOf(bob), 0, "bob passed over");
        assertEq(token.balanceOf(alice) - a0, 50 * U, "alice paid beyond the ineligible level");
        // 200 budget − 50 paid → AIRDROP
        LLGAMEStaking.StakeInfo memory r = staking.stakeInfo(staking.nextStakeId() - 1);
        assertEq(r.staker, airdrop);
        assertEq(r.principal, 150 * U);
        _assertSolvent();
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-WALK-END share_not_worth
    function test_walkEndsWhereShareIsNotWorthLevelGas() public {
        _close();
        _give(alice, 100_000 * U);
        // alice → bob → carol referral chain, both uplines eligible
        _stake(alice, 10_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 10_000 * U);
        _stake(alice, 1_000 * U, bob);
        _stake(bob, 1_000 * U, bob);
        vm.prank(bob);
        token.transfer(carol, 5_000 * U);
        _stake(bob, 1_000 * U, carol);
        assertEq(staking.referrerOf(carol), bob);

        // pool of 10,000 LLGAME and 10 BNB held for a whole price window: at the 0.5 gwei cap a gas unit is worth
        // 0.0000005 LLGAME, a level about 0.0075 LLGAME. Both levels are paid their share less the gas charge,
        // which goes to carol, the caller.
        skip(31 minutes);
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        uint256 c0 = token.balanceOf(carol);
        vm.txGasPrice(5 gwei);
        _stake(carol, 1_000 * U, carol);
        uint256 bobPaid = token.balanceOf(bob) - b0;
        uint256 alicePaid = token.balanceOf(alice) - a0;
        uint256 refund = token.balanceOf(carol) + 1_000 * U - c0;
        assertGt(refund, 0, "caller refunded");
        assertLt(bobPaid, 100 * U, "level 1 charged its gas");
        assertGt(bobPaid, 99 * U);
        assertLt(alicePaid, 50 * U, "level 2 charged its gas");
        assertGt(alicePaid, 49 * U);
        assertEq(bobPaid + alicePaid + refund, 150 * U, "the charges are what the caller is refunded");
        LLGAMEStaking.StakeInfo memory r = staking.stakeInfo(staking.nextStakeId() - 1);
        assertEq(r.staker, airdrop);
        assertEq(r.principal, 50 * U, "200 budget less both shares");

        // a gas price a billion times higher is valued at the cap: the charges stay of the same order
        b0 = token.balanceOf(bob);
        c0 = token.balanceOf(carol);
        vm.txGasPrice(1_000_000_000 gwei);
        _stake(carol, 1_000 * U, carol);
        vm.txGasPrice(0);
        assertGt(token.balanceOf(bob) - b0, 99 * U, "gas price capped");
        assertLt(token.balanceOf(carol) + 1_000 * U - c0, 1 * U, "refund at the capped gas price");
        _assertSolvent();
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-GAS-CHARGE passed_level
    function test_gasOfPassedLevelRefundedFromItsShare() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 10_000 * U);
        _stake(alice, 1_000 * U, bob);
        _stake(bob, 1_000 * U, bob);
        vm.prank(bob);
        token.transfer(carol, 5_000 * U);
        _stake(bob, 1_000 * U, carol);
        uint256 bobLiquid = token.balanceOf(bob);
        vm.prank(bob);
        token.transfer(dave, bobLiquid); // bob ineligible at level 1

        uint256 a0 = token.balanceOf(alice);
        uint256 c0 = token.balanceOf(carol);
        skip(31 minutes);
        vm.txGasPrice(5 gwei);
        _stake(carol, 1_000 * U, carol);
        vm.txGasPrice(0);
        uint256 alicePaid = token.balanceOf(alice) - a0;
        uint256 refund = token.balanceOf(carol) + 1_000 * U - c0;
        assertEq(token.balanceOf(bob), 0, "bob passed over");
        assertLt(alicePaid, 50 * U);
        assertGt(alicePaid, 40 * U);
        assertGt(alicePaid + refund, 50 * U, "the passed level's gas is refunded too, from its own share");
        assertEq(staking.stakeInfo(staking.nextStakeId() - 1).principal, 200 * U - alicePaid - refund);
        _assertSolvent();
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-WALK-END deep
    function test_deepWalkEndsBeforeShareBelowItsGas() public {
        _close();
        address s = _chain(8, "deep-");
        address top = makeAddr("deep-0");
        address direct = makeAddr("deep-7");
        uint256 t0 = token.balanceOf(top);
        uint256 d0 = token.balanceOf(direct);
        uint256 s0 = token.balanceOf(s);
        // a stake of 7 LLGAME: shares halve from 0.7 to 0.0055 LLGAME; at the 0.5 gwei cap a level's gas is
        // worth some thousandths of an LLGAME, so it outweighs the top share and the walk ends below it. The
        // refund stays within a tenth of the 1.4 LLGAME budget.
        skip(31 minutes);
        vm.txGasPrice(5 gwei);
        _stake(s, 7 * U, s);
        vm.txGasPrice(0);
        uint256 refund = token.balanceOf(s) + 7 * U - s0;
        emit log_named_uint("refund, base units", refund);
        assertEq(token.balanceOf(top), t0, "walk ended before the top level");
        assertGt(token.balanceOf(direct), d0);
        assertLt(token.balanceOf(direct) - d0, 1 * U);
        assertGt(refund, 0, "caller refunded");
        assertLe(refund, 14 * U / 100, "refund within a tenth of the budget");
        _assertSolvent();
    }

    /// @dev A chain of `depth` eligible uplines above a fresh staker, each upline holding 10,000 LLGAME liquid
    ///      and 1,000 LLGAME staked; returns the staker, bound to the lowest upline.
    function _chain(uint256 depth, string memory tag) internal returns (address staker) {
        address upper = makeAddr(string.concat(tag, "0"));
        _give(upper, 12_000 * U);
        _stake(upper, 1_000 * U, upper);
        for (uint256 i = 1; i <= depth; i++) {
            address lower = makeAddr(string.concat(tag, vm.toString(i)));
            _give(upper, 1_000 * U);
            _stake(upper, 1_000 * U, lower); // binds lower to upper
            _give(lower, 12_000 * U);
            upper = lower;
        }
        staker = upper;
    }

    /// @dev Gas of a stake whose walk pays `depth` levels, the staker already seen and bound.
    function _walkGas(uint256 depth) internal returns (uint256) {
        address s = _chain(depth, string.concat("lvl", vm.toString(depth), "-"));
        vm.startPrank(s);
        token.approve(address(staking), 1_000_000 * U);
        _give(s, 1_000_000 * U);
        staking.stake(1_000_000 * U, s);
        vm.stopPrank();
        return vm.lastCallGas().gasTotalUsed;
    }

    /// @dev Reports the gas of one paid level, measured as the difference of stakes walking 1 to 8 levels. Run
    ///      with `--isolate -vv` for on-chain figures: every call is then a transaction of its own and the slots
    ///      of a level are cold, as they are on chain. The contract measures the gas itself, with gasleft().
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-GAS-CHARGE measured
    function test_levelGasMeasured() public {
        _close();
        uint256 prev = _walkGas(1);
        uint256 maxLevel;
        for (uint256 d = 2; d <= 8; d++) {
            uint256 g = _walkGas(d);
            emit log_named_uint(string.concat("gas of level ", vm.toString(d)), g - prev);
            if (g - prev > maxLevel) maxLevel = g - prev;
            prev = g;
        }
        emit log_named_uint("max gas of one paid level", maxLevel);
        assertGt(maxLevel, 0);
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-WALK-END root
    function test_rootStakerReadsNoReserves() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 nextId = staking.nextStakeId();
        vm.expectCall(address(pair), abi.encodeWithSelector(IPair.getReserves.selector), 0);
        vm.txGasPrice(1_000_000 gwei);
        _stake(alice, 1_000 * U, alice);
        vm.txGasPrice(0);
        assertEq(staking.referrerOf(alice), address(0));
        assertEq(staking.stakeInfo(nextId + 1).principal, 200 * U, "the whole budget to AIRDROP");
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-PRICE-GUARD current
    function test_currentPriceBeforeReferenceStored() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 10_000 * U);
        _stake(alice, 1_000 * U, bob);
        _stake(bob, 1_000 * U, bob);
        vm.prank(bob);
        token.transfer(carol, 5_000 * U);
        _stake(bob, 1_000 * U, carol);

        // the pair's reserves were set in this block, so no reference price is stored yet: the gas is valued at
        // the current reserves, 10,000 LLGAME per 10 BNB, both levels are charged and the caller refunded
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        uint256 c0 = token.balanceOf(carol);
        vm.txGasPrice(5 gwei);
        _stake(carol, 1_000 * U, carol);
        vm.txGasPrice(0);
        uint256 bobPaid = token.balanceOf(bob) - b0;
        uint256 alicePaid = token.balanceOf(alice) - a0;
        uint256 refund = token.balanceOf(carol) + 1_000 * U - c0;
        assertGt(refund, 0, "caller refunded at the current price");
        assertLt(bobPaid, 100 * U, "level 1 charged its gas");
        assertGt(bobPaid, 99 * U);
        assertLt(alicePaid, 50 * U, "level 2 charged its gas");
        assertGt(alicePaid, 49 * U);
        assertEq(bobPaid + alicePaid + refund, 150 * U, "the charges are what the caller is refunded");
        _assertSolvent();
    }

    // LEGACY-LIFE-GAME-BSC-REFERRAL-WALK
    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-PRICE-GUARD dropped
    function test_droppedPriceValuedAtReference() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 10_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 10_000 * U);
        _stake(alice, 1_000 * U, bob);
        _stake(bob, 1_000 * U, bob);
        vm.prank(bob);
        token.transfer(carol, 5_000 * U);
        _stake(bob, 1_000 * U, carol);

        // the pool's reserves stand since an earlier block: this walk stores the current price as the reference
        skip(31 minutes);
        vm.txGasPrice(5 gwei);
        uint256 c0 = token.balanceOf(carol);
        _stake(carol, 1_000 * U, carol);
        uint256 steady = token.balanceOf(carol) + 1_000 * U - c0;
        assertGt(steady, 0);

        (uint112 r0, uint112 r1, uint32 t) = pair.getReserves();
        bool wbnbIs0 = pair.token0() == address(wbnb);

        // LLGAME ten times cheaper than its reference: the gas is valued at the reference, not ten times dearer
        vm.mockCall(
            address(pair),
            abi.encodeWithSelector(IPair.getReserves.selector),
            wbnbIs0 ? abi.encode(r0, r1 * 10, t) : abi.encode(r0 * 10, r1, t)
        );
        c0 = token.balanceOf(carol);
        _stake(carol, 1_000 * U, carol);
        uint256 dropped = token.balanceOf(carol) + 1_000 * U - c0;
        assertGt(dropped, 0);
        assertLt(dropped, 2 * steady, "a dropped price does not raise the refund");

        // a period later the dropped price still stands: the reference follows it by one guard step only
        skip(31 minutes);
        c0 = token.balanceOf(carol);
        _stake(carol, 1_000 * U, carol);
        assertLt(token.balanceOf(carol) + 1_000 * U - c0, 2 * steady, "the reference follows a drop by steps");

        // LLGAME ten times dearer: the current price is used and the refund shrinks
        vm.mockCall(
            address(pair),
            abi.encodeWithSelector(IPair.getReserves.selector),
            wbnbIs0 ? abi.encode(r0, r1 / 10, t) : abi.encode(r0 / 10, r1, t)
        );
        c0 = token.balanceOf(carol);
        _stake(carol, 1_000 * U, carol);
        uint256 raised = token.balanceOf(carol) + 1_000 * U - c0;
        assertLt(raised, steady / 2, "a raised price lowers the refund");

        vm.clearMockedCalls();
        vm.txGasPrice(0);
        _assertSolvent();
    }

    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-BINDING airdrop
    function test_airdropNeverRefers() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 1_000 * U, airdrop); // anyone may stake for AIRDROP
        assertGt(staking.activeStakeOf(airdrop), 0);
        assertEq(staking.referrerOf(airdrop), address(0), "AIRDROP is never referred");
        vm.prank(alice);
        token.transfer(airdrop, 100 * U);
        _stake(airdrop, 10 * U, dave);
        assertTrue(staking.seen(dave));
        assertEq(staking.referrerOf(dave), address(0), "AIRDROP is never a referrer");
    }

    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-BINDING unseen
    function test_stakeForUnseenBeneficiaryBindsPayer() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 1_000 * U, alice);
        _stake(alice, 500 * U, bob);
        assertEq(staking.referrerOf(bob), alice);
        assertEq(staking.activeStakeOf(bob), 500 * U);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-BENEFICIARY
    function test_excludedBeneficiaryRejected() public {
        _close();
        _give(alice, 100_000 * U);
        vm.startPrank(alice);
        token.approve(address(staking), 1_000 * U);
        vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
        staking.stake(1_000 * U, address(pair));
        vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
        staking.stake(1_000 * U, address(0));
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.stake(72_000_000 - 1, alice);
        vm.stopPrank();
    }

    // ------------------------------------------------- claim, withdraw, delegate

    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-CLAIM
    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-WITHDRAW
    function test_claimWithdraw() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);
        vm.warp(block.timestamp + 540 days);
        assertEq(staking.claimable(id), 1_440 * U);
        uint256 b0 = token.balanceOf(alice);
        vm.prank(alice);
        staking.claim(id);
        assertEq(token.balanceOf(alice) - b0, 1_440 * U);

        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.NotMatured.selector);
        staking.withdraw(id);

        vm.warp(block.timestamp + 540 days);
        b0 = token.balanceOf(alice);
        vm.prank(alice);
        staking.withdraw(id);
        assertEq(token.balanceOf(alice) - b0, 2_440 * U, "principal and unclaimed reward");
        assertEq(staking.activeStakeOf(alice), 0);
        assertEq(staking.claimable(id), 0);
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.Withdrawn.selector);
        staking.withdraw(id);
        _assertSolvent();
    }

    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-DELEGATION
    function test_delegate() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice);

        uint256 minAmount = 72_000_000;

        // delegated amount below the minimum
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.delegateStake(id, minAmount - 1, bob);

        // remaining amount below the minimum
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.delegateStake(id, 1_000 * U - (minAmount - 1), bob);

        vm.warp(block.timestamp + 540 days);

        uint256 b0 = token.balanceOf(alice);
        vm.prank(alice);
        uint256 did = staking.delegateStake(id, 250 * U, bob);
        assertEq(token.balanceOf(alice) - b0, 1_440 * U, "accrued reward paid before split");
        assertEq(staking.referrerOf(bob), alice);

        LLGAMEStaking.StakeInfo memory o = staking.stakeInfo(id);
        LLGAMEStaking.StakeInfo memory d = staking.stakeInfo(did);
        assertEq(o.principal, 750 * U);
        assertEq(d.principal, 250 * U);
        assertEq(uint256(o.reward) + d.reward, 2_880 * U);
        assertEq(uint256(o.claimed) + d.claimed, 1_440 * U);
        assertEq(d.start, o.start);
        assertEq(staking.claimable(did), 0);
        assertEq(staking.activeStakeOf(alice), 750 * U);
        assertEq(staking.activeStakeOf(bob), 250 * U);

        // full delegation of the rest: reuse the existing stake record
        uint256 nextId = staking.nextStakeId();

        vm.prank(alice);
        uint256 did2 = staking.delegateStake(id, 750 * U, carol);

        assertEq(did2, id);
        assertEq(staking.nextStakeId(), nextId, "no new stake record");

        LLGAMEStaking.StakeInfo memory reassigned = staking.stakeInfo(id);
        assertEq(reassigned.staker, carol);
        assertEq(reassigned.principal, 750 * U);
        assertEq(reassigned.reward, 2_160 * U);
        assertEq(reassigned.claimed, 1_080 * U);
        assertEq(reassigned.start, o.start);

        assertEq(staking.referrerOf(carol), alice);
        assertEq(staking.activeStakeOf(alice), 0);
        assertEq(staking.activeStakeOf(bob), 250 * U);
        assertEq(staking.activeStakeOf(carol), 750 * U);

        vm.warp(block.timestamp + 540 days);

        b0 = token.balanceOf(carol);
        vm.prank(carol);
        staking.withdraw(did2);
        assertEq(token.balanceOf(carol) - b0, 750 * U + 1_080 * U);

        assertEq(staking.activeStakeOf(carol), 0);
        _assertSolvent();
    }

    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-PERMIT
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
        vm.prank(owner);
        staking.stakeWithPermit(amount, owner, deadline, v, r, s);
        assertEq(staking.activeStakeOf(owner), amount);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-BINDING transfer
    function test_transferBindsNothing() public {
        _close();
        _give(alice, 100_000 * U);
        _stake(alice, 1_000 * U, alice);
        vm.prank(alice);
        token.transfer(bob, 100 * U);
        assertFalse(staking.seen(bob));
        assertEq(staking.referrerOf(bob), address(0));
        // bob's own first stake makes him a root: a transfer is no binding path
        _stake(bob, 50 * U, bob);
        assertTrue(staking.seen(bob));
        assertEq(staking.referrerOf(bob), address(0));
    }

    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-DONATION
    function test_donationNotCredited() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 r0 = staking.reserve();
        vm.prank(alice);
        token.transfer(address(staking), 100 * U);
        assertEq(staking.reserve(), r0);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-STAKE-ALLOCATION
    function test_stakeAllocatesRewardAndBudget() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 r0 = staking.reserve();
        uint256 id = _stake(alice, 1_000 * U, alice);
        LLGAMEStaking.StakeInfo memory s = staking.stakeInfo(id);
        assertEq(s.principal, 1_000 * U);
        assertEq(s.reward, 2_880 * U, "288% of the principal");
        // reward + 20% budget + the ordinary reward of the AIRDROP stake made of the unpaid budget (a root pays none)
        assertEq(r0 - staking.reserve(), (2_880 + 200 + 576) * U);
        vm.startPrank(alice);
        token.approve(address(staking), 1_000 * U);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.stake(72_000_000 - 1, alice);
        vm.stopPrank();
        _assertSolvent();
    }

    // syngate: LEGACY-LIFE-GAME-BSC-REFERRAL-REMAINDER
    function test_unpaidBudgetBecomesAirdropStake() public {
        _close();
        _give(alice, 100_000 * U);
        uint256 id = _stake(alice, 1_000 * U, alice); // a root: no upline is paid
        LLGAMEStaking.StakeInfo memory d = staking.stakeInfo(id + 1);
        assertEq(d.staker, airdrop);
        assertEq(d.principal, 200 * U, "the whole 20% budget");
        assertEq(d.reward, 576 * U, "the ordinary reward, no referral budget");
    }
}
