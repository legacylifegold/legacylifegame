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
    /// @dev The host of the site the agreements are signed on, https://legacylife.online, as `bind` takes it.
    string private constant SITE = "legacylife.online";
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
        return _signMessage(key, _message(account, to));
    }

    /// @dev The same agreement as a dApp at `origin` words it, `host` being what it writes of that origin on the
    ///      first line; the two are given apart, as the dApp reads them from the page.
    function _messageOn(string memory origin, string memory host, address account, address to)
        private
        view
        returns (bytes memory)
    {
        return bytes(
            string.concat(
                host,
                " wants you to sign in with your Ethereum account:\n",
                vm.toString(account),
                "\n\nI agree that ",
                vm.toString(to),
                " is my referrer in Legacy Life Game.\n\nURI: ",
                origin,
                "\nVersion: 1\nChain ID: ",
                vm.toString(block.chainid),
                "\nNonce: a1B2c3D4e5F6g7H8\nIssued At: 2026-11-25T10:00:00Z\nResources:\n- urn:llgame:referrer:",
                vm.toString(to)
            )
        );
    }

    function _signMessage(uint256 key, bytes memory message) private pure returns (bytes memory) {
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

    // syngate: LEGACYLIFE-BSC-REFERRAL-SIGNATURE signer
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
        referral.bind(alice, referrer, "legacylife.example", NONCE, ISSUED_AT, own);
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(alice, referrer, SITE, "a1B2c3D4e5F6g7H9", ISSUED_AT, own);
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(alice, referrer, SITE, NONCE, "2026-11-25T10:00:01Z", own);
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

    // syngate: LEGACYLIFE-BSC-REFERRAL-SIGNATURE https_origin
    function test_httpsOriginBindsByHost() public {
        (address carol, uint256 carolKey) = makeAddrAndKey("carol");

        // today's message of the dApp at https://legacylife.online, signed as it stands
        bytes memory signed = _signMessage(aliceKey, _message(alice, referrer));
        // the origin is no host: with its scheme passed, the URI rebuilt is not the one signed
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(alice, referrer, "https://legacylife.online", NONCE, ISSUED_AT, signed);
        assertEq(referral.referrerOf(alice), address(0));
        // its host passed, the scheme is the contract's to write: the signature binds as signed
        referral.bind(alice, referrer, "legacylife.online", NONCE, ISSUED_AT, signed);
        assertEq(referral.referrerOf(alice), referrer);

        // any https origin, a subdomain and a port being part of its host
        bytes memory ported = _signMessage(
            bobKey, _messageOn("https://play.legacylife.online:8443", "play.legacylife.online:8443", bob, referrer)
        );
        referral.bind(bob, referrer, "play.legacylife.online:8443", NONCE, ISSUED_AT, ported);
        assertEq(referral.referrerOf(bob), referrer);

        // a signature made on an http site has no host that rebuilds it
        bytes memory plain =
            _signMessage(carolKey, _messageOn("http://legacylife.online", "legacylife.online", carol, referrer));
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(carol, referrer, "legacylife.online", NONCE, ISSUED_AT, plain);
        vm.expectRevert(LLGAMEReferral.InvalidSignature.selector);
        referral.bind(carol, referrer, "http://legacylife.online", NONCE, ISSUED_AT, plain);
        assertEq(referral.referrerOf(carol), address(0));
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

    // ------------------------------------------------------------------ root lookup

    function _bindIn(LLGAMEReferral where, uint256 key, address account, address to) private {
        where.bind(account, to, SITE, NONCE, ISSUED_AT, _sign(key, account, to));
    }

    /// @dev The chain `tag0 <- tag1 <- ... <- tag<depth>` in `referral`, `tag0` its root, each bound to the one before.
    function _chain(string memory tag, uint256 depth) private returns (address[] memory a, uint256[] memory k) {
        a = new address[](depth + 1);
        k = new uint256[](depth + 1);
        for (uint256 i; i <= depth; ++i) {
            (a[i], k[i]) = makeAddrAndKey(string.concat(tag, vm.toString(i)));
            if (i > 0) _bindIn(referral, k[i], a[i], a[i - 1]);
        }
    }

    /// @dev Binds under `to` a new account that already has a referee, so its binding looks up the root of `to`.
    function _bindWithReferee(string memory tag, address to) private {
        (address x, uint256 xKey) = makeAddrAndKey(tag);
        (address y, uint256 yKey) = makeAddrAndKey(string.concat(tag, "-referee"));
        _bindIn(referral, yKey, y, x);
        _bindIn(referral, xKey, x, to);
    }

    function _assertRoot(address account, address root, uint256 depth, uint256 hops) private view {
        (address r, uint256 d, uint256 h) = ILLGAMEReferral(referral).findRoot(account);
        assertEq(r, root, "root");
        assertEq(d, depth, "depth");
        assertEq(h, hops, "hops");
    }

    /// @dev The gas of the call itself, the caller's own frame left out.
    function _gasOf(address target, bytes memory data) private returns (uint256 used) {
        (bool ok,) = target.call(data);
        used = vm.lastCallGas().gasTotalUsed;
        assertTrue(ok, "bound");
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-BIND-GAS
    function test_bindingGasDepthFree() public {
        LLGAMEReferral shallow = new LLGAMEReferral();
        (address ref, uint256 refKey) = makeAddrAndKey("ref");
        (address newbie, uint256 newbieKey) = makeAddrAndKey("newbie");

        // the same referrer at depth 1 in one contract and at depth 30 in the other
        (address[] memory chain,) = _chain("deep", 29);
        _bindIn(shallow, refKey, ref, chain[0]);
        _bindIn(referral, refKey, ref, chain[29]);
        assertEq(_depth(shallow, ref), 1);
        assertEq(_depth(referral, ref), 30);

        // an account with no referee bound under it: the same call costs the same gas in both
        bytes memory data = abi.encodeCall(
            LLGAMEReferral.bind, (newbie, ref, SITE, NONCE, ISSUED_AT, _sign(newbieKey, newbie, ref))
        );
        uint256 low = _gasOf(address(shallow), data);
        uint256 high = _gasOf(address(referral), data);
        assertEq(high, low, "binding gas independent of the referrer's depth");
        assertEq(shallow.referrerOf(newbie), ref);
        assertEq(referral.referrerOf(newbie), ref);
    }

    function _depth(LLGAMEReferral where, address account) private view returns (uint256 depth) {
        (, depth,) = where.findRoot(account);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-LAST-ROOT
    function test_lastRoot() public {
        assertEq(referral.SAVE_ROOT_AFTER_HOPS(), 8);
        (address[] memory a, uint256[] memory k) = _chain("a", 9);
        _assertRoot(a[8], a[0], 8, 8);
        _assertRoot(a[9], a[0], 9, 9);

        // a search of SAVE_ROOT_AFTER_HOPS hops saves nothing
        _bindWithReferee("x", a[8]);
        _assertRoot(a[8], a[0], 8, 8);

        // a longer search saves the root with its steps for the account it started from, and for it alone
        _bindWithReferee("z", a[9]);
        _assertRoot(a[9], a[0], 9, 1);
        _assertRoot(a[8], a[0], 8, 8);
        _assertRoot(a[5], a[0], 5, 5);

        // the root bound in turn: the saved root turns stale, its steps stay exact, the search goes on from it
        address w = makeAddr("w");
        _bindIn(referral, k[0], a[0], w);
        _assertRoot(a[9], w, 10, 2);
        _assertRoot(a[8], w, 9, 9);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-SHORTEN-SEARCH
    function test_shortenRootSearch() public {
        (address[] memory a,) = _chain("r", 20);
        _assertRoot(a[20], a[0], 20, 20);

        // any caller, at most the hops named: five referrers, then the last root and four more
        vm.prank(other);
        referral.shortenRootSearch(a[20], 5);
        _assertRoot(a[20], a[0], 20, 16);
        vm.prank(other);
        referral.shortenRootSearch(a[20], 5);
        _assertRoot(a[20], a[0], 20, 12);

        // never past the root
        referral.shortenRootSearch(a[20], 100);
        _assertRoot(a[20], a[0], 20, 1);
        referral.shortenRootSearch(a[0], 100);
        _assertRoot(a[0], a[0], 0, 0);

        // a last root that would not move is not written: no hop, one hop, or the root already saved
        vm.record();
        referral.shortenRootSearch(a[5], 0);
        referral.shortenRootSearch(a[5], 1);
        referral.shortenRootSearch(a[20], 100);
        (, bytes32[] memory writes) = vm.accesses(address(referral));
        assertEq(writes.length, 0, "nothing written");
        _assertRoot(a[5], a[0], 5, 5);

        // a chain too deep for one search shortened over several calls of a few hops each
        (, , uint256 hops) = referral.findRoot(a[19]);
        uint256 calls;
        while (hops > 1) {
            referral.shortenRootSearch(a[19], 3);
            (, , uint256 now_) = referral.findRoot(a[19]);
            assertLt(now_, hops, "each call shortens the search");
            hops = now_;
            ++calls;
        }
        assertGt(calls, 1);
        _assertRoot(a[19], a[0], 19, 1);
    }

    // syngate: LEGACYLIFE-BSC-REFERRAL-FIND-ROOT
    function test_findRoot() public {
        // a root answers itself, an account never bound included
        address stranger = makeAddr("stranger");
        _assertRoot(stranger, stranger, 0, 0);

        (address[] memory a,) = _chain("p", 3);
        for (uint256 i; i <= 3; ++i) {
            _assertRoot(a[i], a[0], i, i);
        }

        // the depth counts the bindings, the hops what a root search takes now
        referral.shortenRootSearch(a[3], 3);
        _assertRoot(a[3], a[0], 3, 1);
        _assertRoot(a[2], a[0], 2, 2);
    }
}
