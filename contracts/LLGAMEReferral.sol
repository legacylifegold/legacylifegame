
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
    error InvalidSite();
    error InvalidSignature();

    /// @inheritdoc ILLGAMEReferral
    mapping(address account => address) public override referrerOf;

    /// @notice Binds `account` to `referrer` on the account's own signature over its agreement: the EIP-4361 message
    ///         the dApp had it sign as an EIP-191 personal message on `site` (an `https` origin), with `nonce` and
    ///         `issuedAt` as signed. Any caller; a binding is written once and never closes a cycle.
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
        // up the referrer's chain to its root: the account must not be above its own referrer
        for (address up = referrerOf[referrer]; up != address(0); up = referrerOf[up]) {
            if (up == account) revert InvalidReferrer();
        }
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(_agreement(account, referrer, site, nonce, issuedAt));
        // ECDSA for a plain account, ERC-1271 for one with code
        if (!SignatureChecker.isValidSignatureNow(account, digest, signature)) revert InvalidSignature();
        referrerOf[account] = referrer;
        emit ReferralBound(account, referrer);
    }

    /// @dev The agreement's text, byte for byte as the dApp builds it: the site's host, the account, the statement
    ///      naming the referrer, the site, this chain, the nonce and the time, and the referrer as its resource; both
    ///      addresses with their EIP-55 checksum, lines ended with a line feed, the last with none.
    function _agreement(
        address account,
        address referrer,
        string calldata site,
        string calldata nonce,
        string calldata issuedAt
    ) private view returns (bytes memory) {
        bytes memory who = bytes(Strings.toChecksumHexString(referrer));
        return bytes.concat(_opening(account, who, site), _closing(nonce, issuedAt), who);
    }

    /// @dev From the host to the `URI` line; the host is the site without its `https://`.
    function _opening(address account, bytes memory who, string calldata site) private pure returns (bytes memory) {
        bytes calldata origin = bytes(site);
        if (origin.length <= 8 || bytes8(origin[:8]) != bytes8("https://")) revert InvalidSite();
        return bytes.concat(
            origin[8:],
            " wants you to sign in with your Ethereum account:\n",
            bytes(Strings.toChecksumHexString(account)),
            "\n\nI agree that ",
            who,
            " is my referrer in Legacy Life Game.\n\nURI: ",
            origin
        );
    }

    /// @dev From the `Version` line to the resource's prefix.
    function _closing(string calldata nonce, string calldata issuedAt) private view returns (bytes memory) {
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
