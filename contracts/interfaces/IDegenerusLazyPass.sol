// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IDegenerusLazyPass {
    function mintPasses(address to, uint256 quantity, uint24 passLevel) external;
    function inactiveBalanceOf(address owner) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function processAutoActivation(
        uint32 limit,
        uint24 level
    ) external returns (bool worked, bool finished);
}
