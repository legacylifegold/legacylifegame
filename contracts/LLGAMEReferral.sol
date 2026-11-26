
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ILLGAMEReferral} from "./ILLGAMEReferral.sol";

/// @title LLGAME locked referral contract
/// @notice Who referred whom, written on each account's own signed agreement. No owner, no setter, no pause; it
///         references no token and no staking contract.
contract LLGAMEReferral is ILLGAMEReferral {
    event ReferralBound(address indexed account, address indexed referrer);

    error AlreadyBound();
    error InvalidReferrer();
    error InvalidSignature();

    /// @notice A root search that took more hops than this saves the root it found as the last root of the account
    ///         it started from.
    uint256 public constant SAVE_ROOT_AFTER_HOPS = 8;

    /// @inheritdoc ILLGAMEReferral
    mapping(address account => address) public override referrerOf;

    /// @dev What the forest keeps of an account beside its referrer. Bindings being final, a saved `lastRoot` stays
    ///      the account's ancestor at exactly `stepsToLastRoot`; it only stops being a root once it is bound in its
    ///      turn, and a root search goes on from it.
    struct ForestNode {
        address lastRoot;         // the root last saved for the account, or the ancestor shortenRootSearch reached; zero while none
        uint88 stepsToLastRoot;   // the bindings between the account and lastRoot
        bool hasReferees;         // some account is bound to this one
    }

    mapping(address account => ForestNode) private _nodeOf;

    /// @notice Binds `account` to `referrer` on the account's own signature over its agreement: the EIP-4361 message
    ///         the dApp had it sign as an EIP-191 personal message on the `https` site whose host is `site`, passed
    ///         without the scheme, with `nonce` and `issuedAt` as signed. Any caller; a binding is written once and
    ///         never closes a cycle.
    function bind(
        address account,
        address referrer,
        string calldata site,
        string calldata nonce,
        string calldata issuedAt,
        bytes calldata signature
    ) external override {
        if (referrerOf[account] != address(0)) revert AlreadyBound();
        if (referrer == address(0) || referrer == account) revert InvalidReferrer();
        // only an account with referees can close a cycle: unbound, it is the root of everything below it, so a
        // referrer below it has it for its root; an account with no referee checks nothing, whatever the depth
        if (_nodeOf[account].hasReferees && _rootOf(referrer) == account) revert InvalidReferrer();
        bytes32 digest =
            MessageHashUtils.toEthSignedMessageHash(_agreementMessage(account, referrer, site, nonce, issuedAt));
        // ECDSA for a plain account, ERC-1271 for one with code
        if (!SignatureChecker.isValidSignatureNow(account, digest, signature)) revert InvalidSignature();
        referrerOf[account] = referrer;
        ForestNode storage referrerNode = _nodeOf[referrer];
        if (!referrerNode.hasReferees) referrerNode.hasReferees = true;
        emit ReferralBound(account, referrer);
    }

    /// @inheritdoc ILLGAMEReferral
    function shortenRootSearch(address account, uint256 maxHops) external override {
        (address ancestor, uint256 steps, uint256 hops) = _searchRoot(account, maxHops);
        // a single hop ends where the account's first hop leads already: nothing new to save
        if (hops > 1) _saveLastRoot(account, ancestor, steps);
    }

    /// @inheritdoc ILLGAMEReferral
    function findRoot(address account) external view override returns (address root, uint256 depth, uint256 hops) {
        return _searchRoot(account, type(uint256).max);
    }

    /// @dev The root of `account`, saved as its last root when the search took more than SAVE_ROOT_AFTER_HOPS hops.
    function _rootOf(address account) private returns (address root) {
        uint256 steps;
        uint256 hops;
        (root, steps, hops) = _searchRoot(account, type(uint256).max);
        if (hops > SAVE_ROOT_AFTER_HOPS) _saveLastRoot(account, root, steps);
    }

    /// @dev Climbs from `account` at most `maxHops` hops and stops at a root. A hop goes to the current account's
    ///      saved last root or, where it has none, to its referrer. Returns the `ancestor` reached, the `steps`,
    ///      the bindings between `account` and it, and the `hops` taken.
    function _searchRoot(address account, uint256 maxHops)
        private
        view
        returns (address ancestor, uint256 steps, uint256 hops)
    {
        ancestor = account;
        while (hops < maxHops) {
            ForestNode storage node = _nodeOf[ancestor];
            address next = node.lastRoot;
            uint256 stepsToNext = node.stepsToLastRoot;
            if (next == address(0)) {
                next = referrerOf[ancestor];
                if (next == address(0)) break; // a root
                stepsToNext = 1;
            }
            ancestor = next;
            steps += stepsToNext;
            ++hops;
        }
    }

    function _saveLastRoot(address account, address ancestor, uint256 steps) private {
        ForestNode storage node = _nodeOf[account];
        node.lastRoot = ancestor;
        node.stepsToLastRoot = uint88(steps);
    }

    /// @dev The agreement's text, byte for byte as the dApp builds it: the site's host, the account, the statement
    ///      naming the referrer, the site's `https` origin, this chain, the nonce and the time, and the referrer as
    ///      its resource; both addresses with their EIP-55 checksum, lines ended with a line feed, the last with none.
    function _agreementMessage(
        address account,
        address referrer,
        string calldata site,
        string calldata nonce,
        string calldata issuedAt
    ) private view returns (bytes memory) {
        bytes memory referrerText = bytes(Strings.toChecksumHexString(referrer));
        return bytes.concat(_messageUpToUri(account, referrerText, site), _messageFromVersion(nonce, issuedAt), referrerText);
    }

    /// @dev From the host to the `URI` line, whose origin is the host under the `https` scheme written here: `site`
    ///      is the host alone, and a signature over a URI of another scheme cannot be rebuilt.
    function _messageUpToUri(address account, bytes memory referrerText, string calldata site)
        private
        pure
        returns (bytes memory)
    {
        bytes calldata host = bytes(site);
        return bytes.concat(
            host,
            " wants you to sign in with your Ethereum account:\n",
            bytes(Strings.toChecksumHexString(account)),
            "\n\nI agree that ",
            referrerText,
            " is my referrer in Legacy Life Game.\n\nURI: https://",
            host
        );
    }

    /// @dev From the `Version` line to the resource's prefix.
    function _messageFromVersion(string calldata nonce, string calldata issuedAt) private view returns (bytes memory) {
        return bytes.concat(
            "\nVersion: 1\nChain ID: ",
            bytes(Strings.toString(block.chainid)),
            "\nNonce: ",
            bytes(nonce),
            "\nIssued At: ",
            bytes(issuedAt),
            "\nResources:\n- urn:llgame:referrer:"
        );
    }
}
