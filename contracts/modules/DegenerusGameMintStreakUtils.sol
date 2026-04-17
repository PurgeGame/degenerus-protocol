// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";

/// @dev Shared mint streak and activity score utilities. Contains _playerActivityScore
///      (5-component scoring: mint streak, mint count, quest streak, affiliate bonus, deity/whale pass)
///      and mint streak helpers (credits on completed 1x price ETH quest).
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

    // =========================================================================
    // Activity Score (shared across DegenerusGame and DegeneretteModule)
    // =========================================================================

    /// @dev Returns the active ticket level for direct ticket purchases.
    ///      During jackpot phase, direct tickets target the current level.
    ///      During purchase phase, direct tickets target the next level.
    function _activeTicketLevel() internal view returns (uint24) {
        return jackpotPhaseFlag ? level : level + 1;
    }

    /// @dev Shared activity score computation with explicit quest streak and streak base level.
    ///      Accepts pre-fetched questStreak (eliminating STATICCALL to DegenerusQuests on hot path)
    ///      and streakBaseLevel (allowing DegeneretteModule to pass level + 1 instead of _activeTicketLevel()).
    /// @param player The player address to calculate score for.
    /// @param questStreak Quest streak value (pre-fetched from handler return or external view).
    /// @param streakBaseLevel Level used for mint streak calculation (typically _activeTicketLevel() or level + 1).
    /// @return scoreBps Total activity score in basis points.
    function _playerActivityScore(
        address player,
        uint32 questStreak,
        uint24 streakBaseLevel
    ) internal view returns (uint256 scoreBps) {
        if (player == address(0)) return 0;

        uint256 packed = mintPacked_[player];
        bool hasDeityPass = packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
        uint24 levelCount = uint24(
            (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );
        uint24 streak = _mintStreakEffective(player, streakBaseLevel);
        uint24 currLevel = level;
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint8 bundleType = uint8(
            (packed >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3
        );
        bool passActive = frozenUntilLevel > currLevel &&
            (bundleType == 1 || bundleType == 3);

        uint256 bonusBps;

        unchecked {
            if (hasDeityPass) {
                bonusBps = 50 * 100;
                bonusBps += 25 * 100;
            } else {
                // Mint streak: 1% per consecutive level minted, max 50%
                uint256 streakPoints = streak > 50 ? 50 : uint256(streak);
                // Mint count bonus: 1% each
                uint256 mintCountPoints = _mintCountBonusPoints(
                    levelCount,
                    currLevel
                );
                // Active pass = full participation credit
                if (passActive) {
                    if (streakPoints < PASS_STREAK_FLOOR_POINTS) {
                        streakPoints = PASS_STREAK_FLOOR_POINTS;
                    }
                    if (mintCountPoints < PASS_MINT_COUNT_FLOOR_POINTS) {
                        mintCountPoints = PASS_MINT_COUNT_FLOOR_POINTS;
                    }
                }
                bonusBps = streakPoints * 100;
                bonusBps += mintCountPoints * 100;
            }

            // Quest streak: 1% per quest streak, max 100%
            uint256 questStreakCapped = questStreak > 100 ? 100 : uint256(questStreak);
            bonusBps += questStreakCapped * 100;

            // Affiliate bonus (cached in mintPacked_ on level transitions)
            {
                uint256 cachedLevel = (packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) & BitPackingLib.MASK_24;
                uint256 affPoints;
                if (cachedLevel == uint256(currLevel)) {
                    affPoints = (packed >> BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT) & BitPackingLib.MASK_6;
                } else {
                    affPoints = affiliate.affiliateBonusPointsBest(currLevel, player);
                }
                bonusBps += affPoints * 100;
            }

            if (hasDeityPass) {
                bonusBps += DEITY_PASS_ACTIVITY_BONUS_BPS;
            } else if (frozenUntilLevel > currLevel) {
                // Whale pass bonus: varies by bundle type (only active while frozen)
                if (bundleType == 1) {
                    bonusBps += 1000; // +10% for 10-level bundle
                } else if (bundleType == 3) {
                    bonusBps += 4000; // +40% for 100-level bundle
                }
            }
        }

        scoreBps = bonusBps;
    }

    /// @dev Convenience wrapper using _activeTicketLevel() as streakBaseLevel.
    /// @param player The player address to calculate score for.
    /// @param questStreak Quest streak value (pre-fetched from handler return or external view).
    /// @return scoreBps Total activity score in basis points.
    function _playerActivityScore(
        address player,
        uint32 questStreak
    ) internal view returns (uint256 scoreBps) {
        return _playerActivityScore(player, questStreak, _activeTicketLevel());
    }
}
