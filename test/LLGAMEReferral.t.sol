// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {LLGAMEReferral} from "../contracts/LLGAMEReferral.sol";
import {ILLGAMEReferral} from "../contracts/ILLGAMEReferral.sol";

/// @dev A smart wallet answering ERC-1271 for its owner's key.
contract OwnedWallet {
    address private immutable OWNER;

    constructor(address owner_) { OWNER = owner_; }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        return ECDSA.recover(hash, signature) == OWNER ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

contract LLGAMEReferralTest is Test {
    string private constant SITE = "https://legacylife.online";
    string private constant NONCE = "a1B2c3D4e5F6g7H8";
    string private constant ISSUED_AT = "2026-11-25T10:00:00Z";

    LLGAMEReferral private referral;
    address private referrer = makeAddr("referrer");
    address private other = makeAddr("other");
    address private alice;
    uint256 private aliceKey;
    address private bob;
    uint256 private bobKey;

    function setUp() public {
        referral = new LLGAMEReferral();
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
    }

    /// @dev The agreement as the dApp words it (`referralMessage` of its shared code), written out here on its own:
    ///      the addresses checksummed by forge, the chain the one the test runs on.
    function _message(address account, address to) private view returns (bytes memory) {
        return bytes(
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
    }

    /// @dev The `personal_sign` of the agreement by `key`, 65 bytes as a wallet gives them.
    function _sign(uint256 key, address account, address to) private view returns (bytes memory) {
        bytes memory message = _message(account, to);
        bytes32 digest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", vm.toString(message.length), message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _refused(address account, address to, bytes memory signature) private {
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(account, to, SITE, NONCE, ISSUED_AT, signature);
        assertEq(referral.referrerOf(account), address(0), "nothing written");
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-SIGNATURE
    function test_bindingSignature() public {
        bytes memory own = _sign(aliceKey, alice, referrer);
        assertEq(own.length, 65);

        // another account's signature over the same agreement
        _refused(alice, referrer, _sign(bobKey, alice, referrer));
        // the account's own signature, submitted for another referrer
        _refused(alice, other, own);
        // the account's own signature over the agreement of another chain
        uint256 chain = block.chainid;
        vm.chainId(56);
        bytes memory elsewhere = _sign(aliceKey, alice, referrer);
        vm.chainId(chain);
        _refused(alice, referrer, elsewhere);
        // the same agreement passed with another site, nonce or time than signed
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(alice, referrer, "https://legacylife.example", NONCE, ISSUED_AT, own);
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(alice, referrer, SITE, "a1B2c3D4e5F6g7H9", ISSUED_AT, own);
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(alice, referrer, SITE, NONCE, "2026-11-25T10:00:01Z", own);
        // a site that is no https origin
        vm.expectRevert(LLGAMEReferral.InvalidSite.selector);
        referral.bind(alice, referrer, "http://legacylife.online", NONCE, ISSUED_AT, own);
        assertEq(referral.referrerOf(alice), address(0));

        // any caller submits the account's own signature (ECDSA)
        vm.expectEmit(true, true, false, true, address(referral));
        emit LLGAMEReferral.ReferralBound(alice, referrer);
        vm.prank(other);
        referral.bind(alice, referrer, SITE, NONCE, ISSUED_AT, own);
        assertEq(referral.referrerOf(alice), referrer);

        // a smart wallet's signature is its own answer (ERC-1271): its owner's key passes, another key does not
        address wallet = address(new OwnedWallet(bob));
        _refused(wallet, referrer, _sign(aliceKey, wallet, referrer));
        bytes memory walletSignature = _sign(bobKey, wallet, referrer);
        referral.bind(wallet, referrer, SITE, NONCE, ISSUED_AT, walletSignature);
        assertEq(referral.referrerOf(wallet), referrer);

        // the signature is not kept: the contract's one record of the account is its referrer
        assertEq(vm.load(address(referral), keccak256(abi.encode(alice, uint256(0)))), bytes32(uint256(uint160(referrer))));
    }

    /// @dev A binding the account validly signed for, refused by the rule `reason` names; nothing is written.
    function _refusedBy(bytes4 reason, uint256 key, address account, address to, address kept) private {
        bytes memory signature = _sign(key, account, to);
        vm.expectRevert(reason);
        referral.bind(account, to, SITE, NONCE, ISSUED_AT, signature);
        assertEq(ILLGAMEReferral(referral).referrerOf(account), kept, "binding unchanged");
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-FINAL
    function test_writtenBindingFinal() public {
        // the query is the interface's: the contract is read as an ILLGAMEReferral
        ILLGAMEReferral query = referral;
        (address carol, uint256 carolKey) = makeAddrAndKey("carol");
        assertEq(query.referrerOf(alice), address(0), "zero while unbound");

        // to the zero address and to the account itself
        _refusedBy(LLGAMEReferral.InvalidReferrer.selector, aliceKey, alice, address(0), address(0));
        _refusedBy(LLGAMEReferral.InvalidReferrer.selector, aliceKey, alice, alice, address(0));

        // bob under alice, carol under bob
        query.bind(bob, alice, SITE, NONCE, ISSUED_AT, _sign(bobKey, bob, alice));
        query.bind(carol, bob, SITE, NONCE, ISSUED_AT, _sign(carolKey, carol, bob));
        assertEq(query.referrerOf(bob), alice);
        assertEq(query.referrerOf(carol), bob);

        // to an account below it: its direct referee and one two levels down
        _refusedBy(LLGAMEReferral.InvalidReferrer.selector, aliceKey, alice, bob, address(0));
        _refusedBy(LLGAMEReferral.InvalidReferrer.selector, aliceKey, alice, carol, address(0));

        // an account with referees stays bindable to an account not below it
        bytes memory first = _sign(aliceKey, alice, referrer);
        query.bind(alice, referrer, SITE, NONCE, ISSUED_AT, first);
        assertEq(query.referrerOf(alice), referrer);

        // never rebound: another referrer the account signed for, the same binding again, and the bindings below it
        _refusedBy(LLGAMEReferral.AlreadyBound.selector, aliceKey, alice, other, referrer);
        vm.expectRevert(LLGAMEReferral.AlreadyBound.selector);
        query.bind(alice, referrer, SITE, NONCE, ISSUED_AT, first);
        _refusedBy(LLGAMEReferral.AlreadyBound.selector, bobKey, bob, referrer, alice);
        _refusedBy(LLGAMEReferral.AlreadyBound.selector, carolKey, carol, alice, bob);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-QUERY
    function test_referrerQuery() public {
        ILLGAMEReferral query = referral;
        (address carol, uint256 carolKey) = makeAddrAndKey("carol");
        address stranger = makeAddr("stranger");

        // nothing bound: every account reads zero
        assertEq(query.referrerOf(alice), address(0));
        assertEq(query.referrerOf(stranger), address(0));

        // the chain carol -> bob -> alice -> referrer, bound bottom-up and top-down alike
        query.bind(carol, bob, SITE, NONCE, ISSUED_AT, _sign(carolKey, carol, bob));
        query.bind(alice, referrer, SITE, NONCE, ISSUED_AT, _sign(aliceKey, alice, referrer));
        query.bind(bob, alice, SITE, NONCE, ISSUED_AT, _sign(bobKey, bob, alice));

        // who referred whom, read back up the chain to its root
        address up = carol;
        address[4] memory chain = [bob, alice, referrer, address(0)];
        for (uint256 i; i < chain.length; ++i) {
            up = query.referrerOf(up);
            assertEq(up, chain[i], "the referrer its binding names");
        }
        // an account never bound still reads zero, and so does the chain's root
        assertEq(query.referrerOf(stranger), address(0));
        assertEq(query.referrerOf(referrer), address(0), "the root has none");
    }
}
