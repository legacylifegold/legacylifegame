// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
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

contract LLGAMETest is Test {
    uint256 constant U = 1e9; // one LLGAME
    uint256 constant TOTAL = 340_000_000_000_000_000_000_000_000_000 * U;
    uint256 constant POOL_BNB = 10 ether;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant BSC_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address constant BSC_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address publisher = makeAddr("publisher");
    address authors = makeAddr("authors");
    address airdrop = makeAddr("airdrop");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");

    WBNB9 wbnb;
    IFactory factory;
    LLGAMEDeployment dep;
    LLGAME token;
    LLGAMEStaking staking;
    IPair pair;

    function setUp() public {
        vm.warp(1_700_000_000);
        // the deployment contract hardcodes the BSC mainnet factory and WBNB: place local copies there
        vm.etch(BSC_WBNB, address(new WBNB9()).code);
        wbnb = WBNB9(BSC_WBNB);
        deployCodeTo("PancakeFactory.sol:PancakeFactory", abi.encode(address(this)), BSC_FACTORY);
        factory = IFactory(BSC_FACTORY);
        vm.prank(publisher);
        dep = new LLGAMEDeployment(authors, airdrop, POOL_BNB);
        assertEq(address(dep.FACTORY()), BSC_FACTORY);
        assertEq(address(dep.WBNB()), BSC_WBNB);
    }

    function _fund(address who, uint256 v) internal {
        vm.deal(who, v);
        vm.prank(who);
        (bool ok,) = address(dep).call{value: v}("");
        require(ok, "fund failed");
    }

    function _launch(uint256 v) internal {
        _fund(publisher, v);
        token = dep.token();
        staking = dep.staking();
        pair = IPair(address(dep.pair()));
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

    function _stake(address payer, uint256 amount, uint32 term, address beneficiary) internal returns (uint256 id) {
        vm.startPrank(payer);
        token.approve(address(staking), amount);
        id = staking.stake(amount, term, beneficiary);
        vm.stopPrank();
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

    // ---------------------------------------------------------------- launch

    function test_launch() public {
        _launch(0.1 ether);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
        assertEq(token.decimals(), 9);
        assertEq(token.totalSupply(), TOTAL);
        assertEq(token.STAKING(), address(staking));
        // 0.1 of 10 BNB: the pool gets 1% of POOL_SUPPLY, the rest is held until close
        assertEq(token.balanceOf(address(pair)), 10_000 * U);
        assertEq(token.balanceOf(address(dep)), 990_000 * U);
        assertEq(dep.poolSupplied(), 10_000 * U);
        assertEq(token.balanceOf(address(staking)), TOTAL - 1_000_000 * U);
        assertGt(pair.balanceOf(address(dep)), 0);
        assertEq(wbnb.balanceOf(address(pair)), 0.1 ether);

        // creators' stake and its AIRDROP remainder stake
        LLGAMEStaking.StakeInfo memory a = staking.stakeInfo(0);
        assertEq(a.staker, authors);
        assertEq(a.principal, 250_000 * U);
        assertEq(a.reward, 720_000 * U);
        assertEq(a.term, 1080);
        LLGAMEStaking.StakeInfo memory d = staking.stakeInfo(1);
        assertEq(d.staker, airdrop);
        assertEq(d.principal, 50_000 * U);
        assertEq(d.reward, 144_000 * U);
        assertEq(staking.activeStakeOf(airdrop), 50_000 * U);
        assertEq(staking.reserve(), TOTAL - 2_164_000 * U, "R_launch");
        assertTrue(staking.seen(authors));
        assertEq(staking.referrerOf(authors), address(0));
        _assertSolvent();
    }

    function test_precreatedPairDonationSkimmed() public {
        // predict the token address (deployment nonce 1) and pre-create the pair with a WBNB donation
        address predictedToken = vm.computeCreateAddress(address(dep), 1);
        address p = factory.createPair(predictedToken, address(wbnb));
        vm.deal(address(this), 5 ether);
        wbnb.deposit{value: 5 ether}();
        wbnb.transfer(p, 5 ether);
        _launch(0.1 ether);
        assertEq(address(pair), p);
        assertEq(wbnb.balanceOf(DEAD), 5 ether);
        assertEq(wbnb.balanceOf(p), 0.1 ether);
    }

    function _poolLlgame() internal view returns (uint256) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        return pair.token0() == address(token) ? r0 : r1;
    }

    function test_roundsAndClose() public {
        _launch(1 ether);
        assertEq(_poolLlgame(), 100_000 * U);
        uint256 lp1 = pair.balanceOf(address(dep));
        _fund(alice, 4 ether);
        assertEq(_poolLlgame(), 500_000 * U, "LLGAME in proportion to BNB");
        assertEq(token.balanceOf(address(dep)), 500_000 * U, "rest held until close");
        assertApproxEqRel(pair.balanceOf(address(dep)), lp1 * 5, 1e12, "LP grows with the pool");
        _fund(bob, 3 ether);
        assertEq(_poolLlgame(), 800_000 * U);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
        _fund(carol, 5 ether); // overshoots POOL_BNB: all of it enters the pool with the held rest
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertEq(dep.funded(), 13 ether);
        assertEq(wbnb.balanceOf(address(pair)), 13 ether);
        assertEq(_poolLlgame(), 1_000_000 * U);
        assertEq(token.balanceOf(address(dep)), 0);
        assertEq(dep.poolSupplied(), 1_000_000 * U);
        assertGt(pair.balanceOf(DEAD), 0);
        assertEq(pair.balanceOf(address(dep)), 0);

        vm.deal(dave, 1 ether);
        vm.prank(dave);
        (bool ok,) = address(dep).call{value: 1 ether}("");
        assertFalse(ok, "funding after close");
        vm.prank(publisher);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.abort();
    }

    function test_constructorRejectsFixedAddresses() public {
        address[4] memory fixedAddrs = [address(0), DEAD, BSC_FACTORY, BSC_WBNB];
        for (uint256 i; i < fixedAddrs.length; i++) {
            vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
            new LLGAMEDeployment(fixedAddrs[i], airdrop, POOL_BNB);
            vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
            new LLGAMEDeployment(authors, fixedAddrs[i], POOL_BNB);
        }
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(authors, authors, POOL_BNB);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(authors, airdrop, 0);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(authors, airdrop, uint256(type(uint112).max) + 1);
    }

    function test_launchAndCloseInOneRound() public {
        _launch(POOL_BNB);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertGt(pair.balanceOf(DEAD), 0);
    }

    function test_abortRefundsProRata() public {
        _launch(1 ether);
        _fund(alice, 3 ether);
        _buy(bob, 2 ether); // a buyer's BNB enters the pool before the abort

        vm.expectRevert(LLGAMEDeployment.NotPublisher.selector);
        dep.abort();

        uint256 supplyBefore = token.totalSupply();
        vm.prank(publisher);
        dep.abort();
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Aborted));
        // the held 600,000 LLGAME and the pool's LLGAME are burned
        assertLt(token.totalSupply(), supplyBefore - 600_000 * U, "pool and held LLGAME burned");
        assertEq(token.balanceOf(address(dep)), 0);

        uint256 w = dep.withdrawn();
        assertGt(w, 4 ether); // includes the buyer's BNB, less the locked minimum liquidity

        vm.prank(alice);
        dep.refund();
        assertEq(alice.balance, w * 3 ether / 4 ether);
        vm.prank(publisher);
        dep.refund();
        assertEq(publisher.balance, w * 1 ether / 4 ether);
        vm.prank(alice);
        vm.expectRevert(LLGAMEDeployment.NothingToRefund.selector);
        dep.refund();

        vm.deal(dave, 1 ether);
        vm.prank(dave);
        (bool ok,) = address(dep).call{value: 1 ether}("");
        assertFalse(ok, "funding after abort");
    }

    // --------------------------------------------------------------- referral

    function test_referralBindingAndPayout() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        assertTrue(staking.seen(alice));
        assertEq(staking.referrerOf(alice), address(0), "pair is excluded");

        uint256 aBal = token.balanceOf(alice);
        _stake(alice, aBal / 2, 180, alice);

        // alice (a staker) sends bob his first LLGAME: bob is bound to alice
        vm.prank(alice);
        token.transfer(bob, 1_000 * U);
        assertEq(staking.referrerOf(bob), alice);

        // bob stakes 1000: alice is eligible at level 1 and gets 10%
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 nextId = staking.nextStakeId();
        _stake(bob, 1_000 * U, 360, bob);
        assertEq(token.balanceOf(alice) - aliceBefore, 100 * U);
        LLGAMEStaking.StakeInfo memory r = staking.stakeInfo(nextId + 1);
        assertEq(r.staker, airdrop);
        assertEq(r.principal, 100 * U); // 200 budget − 100 paid
        assertEq(r.reward, 72 * U);     // ordinary 360-day reward on the remainder
        assertEq(r.term, 360);

        // carol's first LLGAME comes from alice, a staker; dave's from carol, who has no stake
        vm.prank(alice);
        token.transfer(carol, 2_000 * U);
        assertEq(staking.referrerOf(carol), alice);
        vm.prank(carol);
        token.transfer(dave, 500 * U);
        assertEq(staking.referrerOf(dave), address(0), "carol has no stake yet");
        _assertSolvent();
    }

    function test_payoutNeedsLiquidAndStakeAtEveryLevel() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        _stake(alice, 10_000 * U, 180, alice);
        vm.prank(alice);
        token.transfer(bob, 30_000 * U);
        _stake(bob, 10_000 * U, 180, bob);
        vm.prank(bob);
        token.transfer(carol, 1_000 * U);
        assertEq(staking.referrerOf(carol), bob);

        // level 1 bob: cap 30k ≥ 1k, liquid > 0, stake > 0 → paid 100; level 2 alice: cap ≥ 2k → paid 50
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        _stake(carol, 1_000 * U, 180, carol);
        assertEq(token.balanceOf(bob) - b0, 100 * U);
        assertEq(token.balanceOf(alice) - a0, 50 * U);

        // bob moves all liquid LLGAME away → ineligible at level 1, the walk stops before alice
        uint256 bobLiquid = token.balanceOf(bob);
        vm.prank(bob);
        token.transfer(dave, bobLiquid);
        vm.prank(alice);
        token.transfer(carol, 1_000 * U);
        a0 = token.balanceOf(alice);
        _stake(carol, 1_000 * U, 180, carol);
        assertEq(token.balanceOf(alice), a0, "walk stopped at bob");
        _assertSolvent();
    }

    function test_airdropNeverRefers() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        _stake(alice, 1_000 * U, 180, airdrop); // anyone may stake for AIRDROP
        assertGt(staking.activeStakeOf(airdrop), 0);
        vm.prank(alice);
        token.transfer(airdrop, 100 * U);
        assertEq(staking.referrerOf(airdrop), address(0), "AIRDROP is never referred");
        vm.prank(airdrop);
        token.transfer(dave, 10 * U);
        assertTrue(staking.seen(dave));
        assertEq(staking.referrerOf(dave), address(0), "AIRDROP is never a referrer");
    }

    function test_stakeForUnseenBeneficiaryBindsPayer() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        _stake(alice, 1_000 * U, 180, alice);
        _stake(alice, 500 * U, 180, bob);
        assertEq(staking.referrerOf(bob), alice);
        assertEq(staking.activeStakeOf(bob), 500 * U);
    }

    function test_excludedBeneficiaryRejected() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 1_000 * U);
        vm.expectRevert(LLGAMEStaking.InvalidBeneficiary.selector);
        staking.stake(1_000 * U, 180, address(pair));
        vm.expectRevert(LLGAMEStaking.InvalidTerm.selector);
        staking.stake(1_000 * U, 181, alice);
        vm.stopPrank();
    }

    // ------------------------------------------------- claim, withdraw, delegate

    function test_claimWithdraw() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        uint256 id = _stake(alice, 1_000 * U, 180, alice);
        vm.warp(block.timestamp + 90 days);
        assertEq(staking.claimable(id), 150 * U);
        uint256 b0 = token.balanceOf(alice);
        vm.prank(alice);
        staking.claim(id);
        assertEq(token.balanceOf(alice) - b0, 150 * U);

        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.NotMatured.selector);
        staking.withdraw(id);

        vm.warp(block.timestamp + 90 days);
        b0 = token.balanceOf(alice);
        vm.prank(alice);
        staking.withdraw(id);
        assertEq(token.balanceOf(alice) - b0, 1_150 * U, "principal and unclaimed reward");
        assertEq(staking.activeStakeOf(alice), 0);
        assertEq(staking.claimable(id), 0);
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.Withdrawn.selector);
        staking.withdraw(id);
        _assertSolvent();
    }

    function test_delegate() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        uint256 id = _stake(alice, 1_000 * U, 360, alice);

        uint256 minAmount = 96_000_000;

        // delegated amount below the minimum
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.delegateStake(id, minAmount - 1, bob);

        // remaining amount below the minimum
        vm.prank(alice);
        vm.expectRevert(LLGAMEStaking.InvalidAmount.selector);
        staking.delegateStake(id, 1_000 * U - (minAmount - 1), bob);

        vm.warp(block.timestamp + 180 days);

        uint256 b0 = token.balanceOf(alice);
        vm.prank(alice);
        uint256 did = staking.delegateStake(id, 250 * U, bob);
        assertEq(token.balanceOf(alice) - b0, 360 * U, "accrued reward paid before split");
        assertEq(staking.referrerOf(bob), alice);

        LLGAMEStaking.StakeInfo memory o = staking.stakeInfo(id);
        LLGAMEStaking.StakeInfo memory d = staking.stakeInfo(did);
        assertEq(o.principal, 750 * U);
        assertEq(d.principal, 250 * U);
        assertEq(uint256(o.reward) + d.reward, 720 * U);
        assertEq(uint256(o.claimed) + d.claimed, 360 * U);
        assertEq(d.start, o.start);
        assertEq(d.term, o.term);
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
        assertEq(reassigned.reward, 540 * U);
        assertEq(reassigned.claimed, 270 * U);
        assertEq(reassigned.start, o.start);
        assertEq(reassigned.term, o.term);

        assertEq(staking.referrerOf(carol), alice);
        assertEq(staking.activeStakeOf(alice), 0);
        assertEq(staking.activeStakeOf(bob), 250 * U);
        assertEq(staking.activeStakeOf(carol), 750 * U);

        vm.warp(block.timestamp + 180 days);

        b0 = token.balanceOf(carol);
        vm.prank(carol);
        staking.withdraw(did2);
        assertEq(token.balanceOf(carol) - b0, 750 * U + 270 * U);

        assertEq(staking.activeStakeOf(carol), 0);
        _assertSolvent();
    }

    function test_stakeWithPermit() public {
        _launch(10 ether);
        (address owner, uint256 pk) = makeAddrAndKey("owner");
        _buy(owner, 1 ether);
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
        staking.stakeWithPermit(amount, 180, owner, deadline, v, r, s);
        assertEq(staking.activeStakeOf(owner), amount);
    }

    function test_noteReceiptOnlyToken() public {
        _launch(10 ether);
        vm.expectRevert(LLGAMEStaking.NotToken.selector);
        staking.noteReceipt(alice, bob);
    }

    function test_donationNotCredited() public {
        _launch(10 ether);
        _buy(alice, 1 ether);
        uint256 r0 = staking.reserve();
        vm.prank(alice);
        token.transfer(address(staking), 100 * U);
        assertEq(staking.reserve(), r0);
    }
}
