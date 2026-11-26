// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title Legacy Life Game (LLGAME)
/// @notice Locked BEP-20 token: the whole supply is minted once to the deployer; no owner, no role.
contract LLGAME is ERC20, ERC20Burnable, ERC20Permit {
    uint256 public constant TOTAL_SUPPLY = 340_000_000_000_000_000_000_000_000_000e9;

    constructor() ERC20("Legacy Life Game", "LLGAME") ERC20Permit("Legacy Life Game") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
