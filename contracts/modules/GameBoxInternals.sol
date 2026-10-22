// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @dev Shared resolver signatures for Game-storage box components.
abstract contract GameBoxInternals {
    error RngNotReady();

    function _boxResolveHumanBoxOrder(uint48 buffer, uint256 position, uint256 entry, uint256 rngWord, uint24 currentLevel)
        internal virtual;

    function _boxResolveAfkingBox(uint32 id, uint256 amount, uint24 day, uint256 rngWord, uint16 activityScore)
        internal virtual;

    function _boxResolveLootboxDirect(uint32 id, uint256 amount, uint256 rngWord, uint16 activityScore)
        internal virtual;

    function _boxRollBoxBoons(
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) internal virtual;

    function _boxConsumeDegeneretteBoon(
        uint32 id,
        uint8 currency
    ) internal virtual returns (uint16 boostBps);

    function _boxResolveWwxrpSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual returns (uint256 wwxrpOut);

    function _boxResolveFlipSpinsFromBox(
        uint32 playerId,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual returns (uint256 flipOut);

    function _boxResolveEthSpinFromBox(
        uint32 playerId,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint8 symbol
    ) internal virtual;
}
