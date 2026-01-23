// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Minimal mock of DegenerusAdmin._linkAmountToEth for tests.
contract MockAdminLink {
    uint256 private constant LINK_ETH_PRICE = 0.01 ether; // 0.01 ETH per LINK

    function _linkAmountToEth(uint256 amount) external pure returns (uint256 ethAmount) {
        ethAmount = (amount * LINK_ETH_PRICE) / 1 ether;
    }
}
