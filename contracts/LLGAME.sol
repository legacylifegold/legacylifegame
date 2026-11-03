// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

interface IReceiptObserver {
    function noteReceipt(address from, address to) external;
}

/// @title Legacy Life Game (LLGAME)
/// @notice Locked BEP-20 token: the whole supply is minted once to the deployer; no owner, no role.
contract LLGAME is ERC20, ERC20Burnable, ERC20Permit {
    uint256 public constant TOTAL_SUPPLY = 340_000_000_000_000_000_000_000_000_000e9;

    address public immutable STAKING;

    constructor(address staking_) ERC20("Legacy Life Game", "LLGAME") ERC20Permit("Legacy Life Game") {
        STAKING = staking_;
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    /// @dev Reports every positive transfer to an account that held no LLGAME before it,
    ///      except mints, burns and transfers to the staking contract. Amounts are unchanged.
    function _update(address from, address to, uint256 value) internal override {
        bool report = from != address(0) && to != address(0) && to != STAKING && value != 0 && balanceOf(to) == 0;
        super._update(from, to, value);
        if (report) IReceiptObserver(STAKING).noteReceipt(from, to);
    }
}
