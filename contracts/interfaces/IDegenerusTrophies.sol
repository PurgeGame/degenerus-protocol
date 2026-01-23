// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IDegenerusTrophies {
    function mintExterminator(
        address to,
        uint24 level,
        uint8 trait,
        bool invertFlag,
        uint96 exterminationWinnings,
        uint96 dgnrsReward
    ) external returns (uint256);
    function mintBaf(address to, uint24 level, uint96 dgnrsReward) external returns (uint256);
    function mintAffiliate(address to, uint24 level, uint96 score, uint96 dgnrsReward) external returns (uint256);
    function mintDeity(address to, uint24 level, uint96 dgnrsReward) external returns (uint256);
    function burnDeityTrophies(address owner, uint256 count) external returns (uint256 burned);
    function trophyDgnrs(uint256 tokenId) external view returns (uint96);
}
