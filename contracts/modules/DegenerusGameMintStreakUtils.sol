// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";

/// @dev Shared mint streak helpers (credits on completed 1x price ETH quest).
abstract contract DegenerusGameMintStreakUtils is DegenerusGameStorage {
    /// @dev Packed mint data field storing last level credited for mint streak (24 bits).
    uint256 internal constant MINT_STREAK_LAST_COMPLETED_SHIFT = 160;
    /// @dev Mask for clearing last-completed + streak fields in one pass.
    uint256 private constant MINT_STREAK_FIELDS_MASK =
        (BitPackingLib.MASK_24 << MINT_STREAK_LAST_COMPLETED_SHIFT) |
        (BitPackingLib.MASK_24 << BitPackingLib.LEVEL_STREAK_SHIFT);

    /// @dev Record a mint streak completion for a given level (idempotent per level).
    function _recordMintStreakForLevel(address player, uint24 mintLevel) internal {
        if (player == address(0)) return;
        uint256 mintData = mintPacked_[player];
        uint24 lastCompleted = uint24(
            (mintData >> MINT_STREAK_LAST_COMPLETED_SHIFT) & BitPackingLib.MASK_24
        );
        if (lastCompleted == mintLevel) return;

        uint24 newStreak;
        if (lastCompleted != 0 && lastCompleted + 1 == mintLevel) {
            uint24 streak = uint24(
                (mintData >> BitPackingLib.LEVEL_STREAK_SHIFT) &
                    BitPackingLib.MASK_24
            );
            if (streak < type(uint24).max) {
                unchecked {
                    newStreak = streak + 1;
                }
            } else {
                newStreak = streak;
            }
        } else {
            newStreak = 1;
        }

        uint256 updated = (mintData & ~MINT_STREAK_FIELDS_MASK) |
            (uint256(mintLevel) << MINT_STREAK_LAST_COMPLETED_SHIFT) |
            (uint256(newStreak) << BitPackingLib.LEVEL_STREAK_SHIFT);
        mintPacked_[player] = updated;
    }

    /// @dev Effective mint streak (resets if a level was missed).
    function _mintStreakEffective(
        address player,
        uint24 currentMintLevel
    ) internal view returns (uint24 streak) {
        uint256 packed = mintPacked_[player];
        uint256 lastCompleted = (packed >> MINT_STREAK_LAST_COMPLETED_SHIFT) &
            BitPackingLib.MASK_24;
        if (lastCompleted == 0) return 0;
        if (uint256(currentMintLevel) > lastCompleted + 1) return 0;
        streak = uint24(
            (packed >> BitPackingLib.LEVEL_STREAK_SHIFT) & BitPackingLib.MASK_24
        );
    }
}
