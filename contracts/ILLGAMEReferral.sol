// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title LLGAME referral contract interface
/// @notice What the referral contract answers to its callers: the binding of an account on its own signature and the
///         query of who referred whom.
interface ILLGAMEReferral {
    /// @notice Binds `account` to `referrer` on the account's own signature over its agreement, signed on `site` with
    ///         `nonce` and `issuedAt`. Any caller; a binding is written once and never closes a cycle.
    function bind(
        address account,
        address referrer,
        string calldata site,
        string calldata nonce,
        string calldata issuedAt,
        bytes calldata signature
    ) external;

    /// @notice The referrer `account` signed for; zero while unbound.
    function referrerOf(address account) external view returns (address);
}
