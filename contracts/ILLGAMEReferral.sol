// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title LLGAME referral contract interface
/// @notice What the referral contract answers to its callers: the binding of an account on its own signature and the
///         query of who referred whom.
interface ILLGAMEReferral {
    /// @notice Binds `account` to `referrer` on the account's own signature over its agreement, signed with `nonce`
    ///         and `issuedAt` on the `https` site whose host is `site`: the origin without its scheme, which the
    ///         contract writes itself. Any caller; a binding is written once and never closes a cycle.
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

    /// @notice Maintenance, any caller: climbs at most `maxHops` hops from `account`, never past its root, and saves
    ///         the ancestor reached as the account's last root, so a chain whose root search no longer fits one
    ///         transaction is shortened over several. No stake and no binding needs it otherwise.
    function shortenRootSearch(address account, uint256 maxHops) external;

    /// @notice The `root` above `account`, the account's `depth`, the bindings between the two, and the `hops` a root
    ///         search from it takes now; a root answers itself, zero and zero.
    function findRoot(address account) external view returns (address root, uint256 depth, uint256 hops);
}
