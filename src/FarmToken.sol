// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title FarmToken
/// @notice A simple ERC20 with an open faucet, used both as the reward token and
///         as stakeable assets in the HarvestHub demo. Anyone can mint test tokens
///         so the live demo works without a privileged deployer handout.
/// @dev    Demo/testnet only — a real token would never expose an unbounded mint.
contract FarmToken is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 1000 ether;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// @notice Mint yourself 1000 test tokens.
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Mint an arbitrary amount to any address (used by deploy scripts).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
