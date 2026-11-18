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
    uint256 constant POOL_BNB_SUPPLY = 10 ether;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    // PancakeSwap v2 factory and WBNB of the chain this branch is built for: BSC testnet
    address constant BSC_FACTORY = 0x6725F303b657a9451d8BA641348b6761A6CC7a17;
    address constant BSC_WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

    address publisher = makeAddr("publisher");
    address authors = makeAddr("authors");
    address airdrop = makeAddr("airdrop");
    address funder = makeAddr("funder");
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
        // the publication is the launch: the ecosystem exists from here on, unfunded
        vm.prank(publisher);
        dep = new LLGAMEDeployment(authors, airdrop, POOL_BNB_SUPPLY);
        assertEq(address(dep.FACTORY()), BSC_FACTORY);
        assertEq(address(dep.WBNB()), BSC_WBNB);
        token = dep.token();
        staking = dep.staking();
        pair = IPair(address(dep.pair()));
    }

    function _fund(address who, uint256 v) internal {
        vm.deal(who, v);
        vm.prank(who);
        (bool ok,) = address(dep).call{value: v}("");
        require(ok, "fund failed");
    }

    /// @dev Funds the whole POOL_BNB_SUPPLY in one round: the pool holds POOL_SUPPLY and funding is closed.
    function _close() internal {
        _fund(funder, POOL_BNB_SUPPLY);
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

    function _stake(address payer, uint256 amount, address beneficiary) internal returns (uint256 id) {
        vm.startPrank(payer);
        token.approve(address(staking), amount);
        id = staking.stake(amount, beneficiary);
        vm.stopPrank();
    }

    /// @dev Gives `who` LLGAME out of thin air: the pool holds only POOL_SUPPLY, too little for the staking scenarios.
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

    // ---------------------------------------------------------------- launch

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ACTIVATION launch
    function test_launch() public {
        // the constructor alone, run in setUp with no round sent, has launched the ecosystem
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
        assertEq(dep.PUBLISHER(), publisher);
        assertEq(dep.funded(), 0, "nothing funded");
        assertEq(address(dep).balance, 0);
        assertEq(token.decimals(), 9);
        assertEq(token.totalSupply(), TOTAL);
        assertEq(address(pair), factory.getPair(address(token), address(wbnb)), "the canonical pair");
        // the pool is empty: the whole POOL_SUPPLY is held for the funding rounds
        assertEq(pair.totalSupply(), 0);
        assertEq(token.balanceOf(address(pair)), 0);
        assertEq(wbnb.balanceOf(address(pair)), 0);
        assertEq(token.balanceOf(address(dep)), 10_000 * U);
        assertEq(dep.poolSupplied(), 0);
        assertEq(token.balanceOf(address(staking)), TOTAL - 10_000 * U);

        // creators' stake and its AIRDROP remainder stake
        LLGAMEStaking.StakeInfo memory a = staking.stakeInfo(0);
        assertEq(a.staker, authors);
        assertEq(a.principal, 500_000 * U);
        assertEq(a.reward, 1_440_000 * U);
        LLGAMEStaking.StakeInfo memory d = staking.stakeInfo(1);
        assertEq(d.staker, airdrop);
        assertEq(d.principal, 100_000 * U);
        assertEq(d.reward, 288_000 * U);
        assertEq(staking.activeStakeOf(airdrop), 100_000 * U);
        assertEq(staking.reserve(), TOTAL - 2_338_000 * U, "R_launch");
        assertTrue(staking.seen(authors));
        assertEq(staking.referrerOf(authors), address(0));
        _assertSolvent();

        // no BNB can be attached to the publication: the same creation succeeds without it and fails with it
        bytes memory init =
            abi.encodePacked(type(LLGAMEDeployment).creationCode, abi.encode(authors, airdrop, POOL_BNB_SUPPLY));
        vm.deal(address(this), 1 ether);
        address bare;
        address paid;
        assembly {
            bare := create(0, add(init, 0x20), mload(init))
            paid := create(1, add(init, 0x20), mload(init))
        }
        assertTrue(bare != address(0), "publication without BNB");
        assertEq(paid, address(0), "publication with BNB attached");
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ACTIVATION pair
    function test_precreatedPairDonationSkimmed() public {
        // predict the publisher's next deployment contract and its token (the contract's nonce 1), and
        // pre-create the pair with a WBNB donation
        address predicted = vm.computeCreateAddress(publisher, vm.getNonce(publisher));
        address predictedToken = vm.computeCreateAddress(predicted, 1);
        address p = factory.createPair(predictedToken, address(wbnb));
        vm.deal(address(this), 5 ether);
        wbnb.deposit{value: 5 ether}();
        wbnb.transfer(p, 5 ether);

        vm.prank(publisher);
        dep = new LLGAMEDeployment(authors, airdrop, POOL_BNB_SUPPLY);
        assertEq(address(dep), predicted);
        assertEq(address(dep.token()), predictedToken);
        assertEq(address(dep.pair()), p);
        assertEq(wbnb.balanceOf(DEAD), 5 ether);
        assertEq(wbnb.balanceOf(p), 0, "the pool starts empty");
        _fund(funder, 0.1 ether);
        assertEq(wbnb.balanceOf(p), 0.1 ether);
    }

    function _poolLlgame() internal view returns (uint256) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        return pair.token0() == address(token) ? r0 : r1;
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ROUNDS
    function test_roundsAndClose() public {
        _fund(funder, 1 ether); // the first round finds the pool empty
        assertEq(_poolLlgame(), 1_000 * U);
        assertEq(token.balanceOf(address(dep)), 9_000 * U);
        assertEq(dep.poolSupplied(), 1_000 * U);
        assertEq(wbnb.balanceOf(address(pair)), 1 ether);
        assertEq(dep.depositOf(funder), 1 ether);
        uint256 lp1 = pair.balanceOf(address(dep));
        _fund(alice, 4 ether);
        assertEq(_poolLlgame(), 5_000 * U, "LLGAME in proportion to BNB");
        assertEq(token.balanceOf(address(dep)), 5_000 * U, "rest held until close");
        assertApproxEqRel(pair.balanceOf(address(dep)), lp1 * 5, 1e12, "LP grows with the pool");
        _fund(bob, 3 ether);
        assertEq(_poolLlgame(), 8_000 * U);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Funding));
        _fund(carol, 5 ether); // overshoots POOL_BNB_SUPPLY: all of it enters the pool with the held rest
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertEq(dep.funded(), 13 ether);
        assertEq(wbnb.balanceOf(address(pair)), 13 ether);
        assertEq(_poolLlgame(), 10_000 * U);
        assertEq(token.balanceOf(address(dep)), 0);
        assertEq(dep.poolSupplied(), 10_000 * U);
        assertGt(pair.balanceOf(DEAD), 0);
        assertEq(pair.balanceOf(address(dep)), 0);

        vm.deal(dave, 1 ether);
        vm.prank(dave);
        (bool ok,) = address(dep).call{value: 1 ether}("");
        assertFalse(ok, "funding after close");
        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.InvalidState.selector);
        dep.abort();
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-PARAMETERS
    function test_constructorRejectsFixedAddresses() public {
        address[4] memory fixedAddrs = [address(0), DEAD, BSC_FACTORY, BSC_WBNB];
        for (uint256 i; i < fixedAddrs.length; i++) {
            vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
            new LLGAMEDeployment(fixedAddrs[i], airdrop, POOL_BNB_SUPPLY);
            vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
            new LLGAMEDeployment(authors, fixedAddrs[i], POOL_BNB_SUPPLY);
        }
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(authors, authors, POOL_BNB_SUPPLY);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(authors, airdrop, 0);
        vm.expectRevert(LLGAMEDeployment.InvalidParameter.selector);
        new LLGAMEDeployment(authors, airdrop, uint256(type(uint112).max) + 1);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-CLOSE one_round
    function test_closeInOneRound() public {
        _fund(funder, POOL_BNB_SUPPLY); // the first round after the publication
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertEq(_poolLlgame(), 10_000 * U);
        assertEq(token.balanceOf(address(dep)), 0);
        assertGt(pair.balanceOf(DEAD), 0);
        assertEq(pair.balanceOf(address(dep)), 0);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-CLOSE donation
    function test_LLGAME_DEPLOYMENT_CLOSE() public {
        _fund(funder, 1 ether);
        _buy(bob, 0.01 ether);
        vm.prank(bob);
        token.transfer(address(dep), 1); // dust sent to the deployment contract during funding
        _fund(carol, 9 ether);
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Closed));
        assertEq(dep.poolSupplied(), 10_000 * U, "the pool got exactly POOL_SUPPLY");
        assertEq(token.balanceOf(address(dep)), 1, "the donation stays, unaccounted");
        assertGt(pair.balanceOf(DEAD), 0);
        assertEq(pair.balanceOf(address(dep)), 0);
    }

    // syngate: LEGACY-LIFE-GAME-BSC-DEPLOYMENT-ABORT
    function test_abortRefundsProRata() public {
        _fund(funder, 1 ether);
        _fund(alice, 3 ether);
        _buy(bob, 2 ether); // a buyer's BNB enters the pool before the abort

        // AUTHORS alone: neither a funder nor the publisher
        vm.prank(alice);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.abort();
        vm.prank(publisher);
        vm.expectRevert(LLGAMEDeployment.NotAuthors.selector);
        dep.abort();

        uint256 supplyBefore = token.totalSupply();
        vm.prank(authors);
        dep.abort();
        assertEq(uint8(dep.state()), uint8(LLGAMEDeployment.State.Aborted));
        // the held 6,000 LLGAME and the pool's LLGAME are burned
        assertLt(token.totalSupply(), supplyBefore - 6_000 * U, "pool and held LLGAME burned");
        assertEq(token.balanceOf(address(dep)), 0);

        uint256 w = dep.withdrawn();
        assertGt(w, 4 ether); // includes the buyer's BNB, less the locked minimum liquidity

        vm.prank(alice);
        dep.refund();
        assertEq(alice.balance, w * 3 ether / 4 ether);
        vm.prank(funder);
        dep.refund();
        assertEq(funder.balance, w * 1 ether / 4 ether);
        vm.prank(authors);
        vm.expectRevert(LLGAMEDeployment.NothingToRefund.selector);
        dep.refund(); // the abort gives AUTHORS nothing
        vm.prank(alice);
        vm.expectRevert(LLGAMEDeployment.NothingToRefund.selector);
        dep.refund();

        vm.deal(dave, 1 ether);
        vm.prank(dave);
        (bool ok,) = address(dep).call{value: 1 ether}("");
        assertFalse(ok, "funding after abort");

        // before the first round there is no liquidity to remove: the held POOL_SUPPLY is burned, nothing is recovered
        LLGAMEDeployment unfunded = new LLGAMEDeployment(authors, airdrop, POOL_BNB_SUPPLY);
        vm.prank(authors);
        unfunded.abort();
        assertEq(uint8(unfunded.state()), uint8(LLGAMEDeployment.State.Aborted));
        assertEq(unfunded.token().totalSupply(), TOTAL - 10_000 * U);
        assertEq(unfunded.withdrawn(), 0);
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
