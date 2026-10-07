// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @dev Vault interface for the DGVE-majority bounty-eligibility tier (cold path).
interface IDegenerusVaultOwner {
    /// @notice DegenerusVault's majority-DGVE-holder check for `account`.
    function isVaultOwner(address account) external view returns (bool);
    /// @notice Whether the vault buys liquidated accounts when sDGNRS cannot fund the price,
    ///         and the ETH (wei) reserve it keeps untouched.
    function liquidationBuyConfig() external view returns (bool enabled, uint256 floorWei);
}

/// @dev Shared mint streak and activity score utilities. Contains _playerActivityScore
///      (5-component scoring: mint streak, mint count, quest streak, affiliate bonus, deity/whale pass)
///      and mint streak helpers (credits on completed 1x price ETH quest).
abstract contract DegenerusGameMintStreakUtils is DegenerusGameStorage {
    /// @notice Thrown for an invalid whale-pass quantity.
    error InvalidQuantity();

    /// @dev Jackpots processed per level before the phase ends. Mirrors the per-module copies;
    ///      declared here for _activeTicketLevel's final-jackpot-day reroute.

    /// @notice Emitted whenever a player's cashout/smite curse counter changes, carrying the
    ///         resulting absolute value so indexers need no eth_call and never replay cap logic.
    /// @param player The cursed (or cured) player.
    /// @param newCurseCount The curse-counter field AFTER the change: stored curse points (0..20;
    ///        each smite or cashout-curse adds +2 saturating at 20; activity penalty = value points;
    ///        0 means cured).
    event CurseChanged(uint32 indexed player, uint8 newCurseCount);

    /// @dev Price-funded buyer selection. sDGNRS retains 1 ETH of claimable; the enabled
    ///      Vault retains its configured floor across claimable plus prepaid AFKing.
    ///      Both balances are claimablePool-backed; zero means neither buyer can fund.
    function _resolveLiquidationBuyer(uint256 totalBudget) internal view returns (uint32 buyer) {
        if (_claimableOf(SDGNRS_WALLET_ID) >= totalBudget + 1 ether) {
            return SDGNRS_WALLET_ID;
        }
        (bool enabled, uint256 vaultFloorWei) = IDegenerusVaultOwner(
            ContractAddresses.VAULT
        ).liquidationBuyConfig();
        if (
            enabled &&
            _claimableOf(VAULT_WALLET_ID) +
                _afkingOf(VAULT_WALLET_ID) >=
            totalBudget + vaultFloorWei
        ) {
            return VAULT_WALLET_ID;
        }
        return 0;
    }

    /// @dev Mask for clearing last-completed + streak fields in one pass.
    uint256 private constant MINT_STREAK_FIELDS_MASK =
        (BitPackingLib.MASK_24 << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) |
        (BitPackingLib.MASK_24 << BitPackingLib.LEVEL_STREAK_SHIFT);

    /// @dev Record a mint streak completion for a given level (idempotent per level).
    function _recordMintStreakForLevel(uint32 player, uint24 mintLevel) internal {
        if (player == 0) return;
        uint256 mintData = mintPacked_[player];
        uint24 lastCompleted = uint24(
            (mintData >> BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) & BitPackingLib.MASK_24
        );
        // Already covered (e.g. a pass front-load advanced lastCompleted to a future horizon):
        // a mint at or below it must not regress lastCompleted or reset the streak to 1.
        if (mintLevel <= lastCompleted) return;

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
            (uint256(mintLevel) << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) |
            (uint256(newStreak) << BitPackingLib.LEVEL_STREAK_SHIFT);
        mintPacked_[player] = updated;
        emit MintRecorded(player, updated);
    }

    /// @dev Effective mint streak computed from an already-loaded mintPacked_ word
    ///      (resets if a level was missed).
    function _mintStreakEffectiveFromPacked(
        uint256 packed,
        uint24 currentMintLevel
    ) internal pure returns (uint24 streak) {
        uint256 lastCompleted = (packed >> BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) &
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


    /// @dev Legacy far-future discount curve (bps of face): flat 15% for d2..d6, then two lines,
    ///      15% @ d6 -> 10% @ d20 -> 5% @ d100. Caller guarantees 2 <= d <= 100. Integer
    ///      truncation is sub-bps, acceptable.
    function _farFutureFractionBps(uint256 d) internal pure returns (uint256) {
        if (d <= 6) return 1500; // never above the d6 rate
        if (d <= 20) return 1500 - ((d - 6) * 500) / 14; // 15% -> 10%
        return 1000 - ((d - 20) * 500) / 80; // 10% -> 5%
    }





    /// @dev Whole-account quote. Queue tags distinguish current lanes from old ring cycles;
    ///      the account's entries remain in their original queues after ownership changes.
    function _quoteLiquidation(uint32 id) internal view
        returns (uint256 face, uint256 budget, uint256 ticketValue, uint256 price)
    {
        uint24 cl = _activeTicketLevel();
        uint256 seed = _farFutureSeed(id);
        uint256 jitter = 7000 + seed % 4001;
        for (uint256 distance = 2; distance <= 100; ++distance) {
            uint256 target = uint256(cl) + distance;
            if (target > type(uint24).max) break;
            uint256 lane = _farFutureLane(uint24(target), id);
            if (lane & 0x80000000 == 0) continue;
            uint256 entries = (lane & 0x3fffffff) & ~uint256(3);
            if (entries == 0) continue;
            uint256 value = PriceLookupLib.priceForLevel(uint24(target)) * entries / 4;
            face += value;
            budget += value * _farFutureFractionBps(distance) * jitter / 100_000_000;
        }
        ticketValue = budget * (4000 + ((seed >> 128) % 4001)) / 10_000;
        uint256 oneEntry = PriceLookupLib.priceForLevel(cl) / 4;
        if (ticketValue < oneEntry) ticketValue = oneEntry;
        if (ticketValue > budget) ticketValue = budget;
        price = budget - ticketValue + ticketValue / 4;
    }

    /// @dev Daily ID-seeded liquidation offer, shared by preview and execution.
    function _farFutureSeed(uint32 playerId) internal view returns (uint256) {
        return uint256(
            keccak256(abi.encode(uint256(playerId), _recordedDailyWord(_simulatedDayIndex() - 1)))
        );
    }

    /// @dev Activity score body operating on a caller-supplied current level, so every
    ///      level comparison (pass window, mint count, affiliate cache) shares one read.
    /// @param player The account ID to calculate score for.
    /// @param questStreak Quest streak value (pre-fetched from handler return or external view).
    /// @param streakBaseLevel Level used for mint streak calculation.
    /// @param currLevel The game's current level.
    /// @return scorePoints Total activity score in whole points.
    function _playerActivityScoreAt(
        uint32 player,
        uint32 questStreak,
        uint24 streakBaseLevel,
        uint24 currLevel
    ) internal view returns (uint256 scorePoints) {
        if (player == 0) return 0;

        uint256 packed = mintPacked_[player];
        bool hasDeityPass = packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
        uint24 levelCount = uint24(
            (packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );
        uint24 streak = _mintStreakEffectiveFromPacked(packed, streakBaseLevel);
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint8 passType = uint8(
            (packed >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3
        );
        bool passActive = frozenUntilLevel >= currLevel &&
            (passType == 1 || passType == 3);

        uint256 bonusPoints;

        unchecked {
            if (hasDeityPass) {
                bonusPoints = 50;
                bonusPoints += 25;
            } else {
                // Mint streak: 1 point per consecutive level minted, max 50 points
                uint256 streakPoints = streak > 50 ? 50 : uint256(streak);
                // Mint count bonus: floor(count * 25 / level), capped at 25 (100% participation = 25)
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
                bonusPoints = streakPoints;
                bonusPoints += mintCountPoints;
            }

            // Quest streak: 1 point per 2 quest completions, uncapped (the hard cap on
            // the total score below bounds the sum). The trailing half-point at odd
            // streak counts is dropped by the floor.
            bonusPoints += uint256(questStreak) / 2;

            // Affiliate bonus (cached in mintPacked_ on level transitions)
            {
                uint256 cachedLevel = (packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) & BitPackingLib.MASK_24;
                uint256 affPoints;
                if (cachedLevel == uint256(currLevel)) {
                    affPoints = (packed >> BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT) & BitPackingLib.MASK_6;
                } else {
                    affPoints = affiliate.affiliateBonusPointsBest(
                        currLevel, player
                    );
                }
                bonusPoints += affPoints;
            }

            if (hasDeityPass) {
                bonusPoints += DEITY_PASS_ACTIVITY_BONUS_POINTS;
            } else if (frozenUntilLevel >= currLevel) {
                // Pass bonus: varies by pass type (only active while frozen)
                if (passType == 1) {
                    bonusPoints += 10; // +10 points for the 10-level lazy pass
                } else if (passType == 3) {
                    bonusPoints += 40; // +40 points for the 100-level whale pass
                }
            }
        }

        // Cashout/smite curse penalty: each point lowers the activity score by 1 point,
        // floored at 0. Rides the mintPacked_ word already loaded above (zero new SLOAD).
        uint256 curse = (packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_5;
        if (curse != 0) {
            bonusPoints = bonusPoints > curse ? bonusPoints - curse : 0;
        }

        scorePoints = bonusPoints > ACTIVITY_SCORE_HARD_CAP_POINTS
            ? ACTIVITY_SCORE_HARD_CAP_POINTS
            : bonusPoints;
    }

    /// @dev Current-level affiliate points only depend on earlier levels. All earning
    ///      writers credit the next level, so this cache remains valid until level advances.
    ///      Only cache bits change; participation, pass, and curse fields are preserved.
    function _cacheAffiliateBonus(uint32 player, uint24 currLevel, uint256 packed)
        internal view returns (uint256)
    {
        if (((packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) & BitPackingLib.MASK_24) == currLevel) {
            return packed;
        }
        uint256 points = affiliate.affiliateBonusPointsBest(
            currLevel, player
        );
        packed = BitPackingLib.setPacked(
            packed, BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT, BitPackingLib.MASK_24, currLevel
        );
        return BitPackingLib.setPacked(
            packed, BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT, BitPackingLib.MASK_6, points
        );
    }

    function _playerActivityScoreCachedAt(
        uint32 player, uint32 questStreak, uint24 streakBaseLevel, uint24 currLevel
    ) internal returns (uint256) {
        if (player == 0) return 0;
        uint256 previous = mintPacked_[player];
        // Only persist beside durable purchase history. Mutable-only seat/curse
        // fields can later clear; leaving a cache-only word would incorrectly pass
        // the market's nonzero participation gate. This also avoids a fresh SSTORE.
        uint256 historyMask = (BitPackingLib.MASK_24 << BitPackingLib.LAST_LEVEL_SHIFT)
            | (BitPackingLib.MASK_24 << BitPackingLib.LEVEL_COUNT_SHIFT)
            | (BitPackingLib.MASK_24 << BitPackingLib.DAY_SHIFT);
        if ((previous & historyMask) == 0) {
            return _playerActivityScoreAt(player, questStreak, streakBaseLevel, currLevel);
        }
        uint256 packed = _cacheAffiliateBonus(player, currLevel, previous);
        if (packed != previous) mintPacked_[player] = packed;
        return _playerActivityScoreAt(player, questStreak, streakBaseLevel, currLevel);
    }

    function _playerActivityScoreCached(uint32 player, uint32 questStreak) internal returns (uint256) {
        return _playerActivityScoreCachedAt(player, questStreak, _activeTicketLevel(), level);
    }

    /// @dev Convenience wrapper using _activeTicketLevel() (the routed buy-now level) as
    ///      streakBaseLevel — so a terminal-jackpot deposit scores against the level its
    ///      participation records to — with currLevel (the actual level) for the score body.
    /// @param player The account ID to calculate score for.
    /// @param questStreak Quest streak value (pre-fetched from handler return or external view).
    /// @return scorePoints Total activity score in whole points.
    function _playerActivityScore(
        uint32 player,
        uint32 questStreak
    ) internal view returns (uint256 scorePoints) {
        uint24 currLevel = level;
        return
            _playerActivityScoreAt(
                player,
                questStreak,
                _activeTicketLevel(),
                currLevel
            );
    }

    // =========================================================================
    // Cashout / smite curse counter (mintPacked_ bits 203-207)
    // =========================================================================

    /// @dev Curse cap = 20 points (-20 points max). Doubles as the uint8-wrap guard: a
    ///      saturating +2 can never wrap the 8-bit field 254->0.
    uint8 internal constant CURSE_COUNT_CAP = 20;

    /// @dev Add a saturating +2 curse stack to `target` (no SSTORE once at the cap).
    function _applyCurseStack(uint32 target) internal {
        uint256 packed = mintPacked_[target];
        uint256 curse = (packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_5;
        if (curse >= CURSE_COUNT_CAP) return;
        uint256 newCurse = curse + 2;
        if (newCurse > CURSE_COUNT_CAP) newCurse = CURSE_COUNT_CAP;
        mintPacked_[target] = BitPackingLib.setPacked(
            packed,
            BitPackingLib.CURSE_COUNT_SHIFT,
            BitPackingLib.MASK_5,
            newCurse
        );
        emit CurseChanged(target, uint8(newCurse));
    }

    /// @dev Clear `target`'s curse counter to 0 (field-isolated; no SSTORE when already 0).
    function _clearCurse(uint32 target) internal {
        uint256 packed = mintPacked_[target];
        if ((packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_5 == 0) return;
        mintPacked_[target] = BitPackingLib.setPacked(
            packed,
            BitPackingLib.CURSE_COUNT_SHIFT,
            BitPackingLib.MASK_5,
            0
        );
        emit CurseChanged(target, 0);
    }

    /// @dev Fold lootbox ETH spend into the minted-units tally at the active ticket
    ///      level's price (4 * QTY_SCALE units = one ticket-price), so ticket and lootbox
    ///      spend accumulate into ONE participation measure: crossing the whole-ticket
    ///      floor counts the level as minted (mint day, streak, level count, quest
    ///      activity gate). Shared by the pass-bundled lootbox leg and the plain
    ///      standalone lootbox buy.
    function _recordLootboxUnits(uint32 player, uint256 lootboxWei) internal {
        // Routed level: lootbox participation counts toward the level the tickets route to.
        uint24 lvl = _activeTicketLevel();
        uint256 units = (lootboxWei * 4 * QTY_SCALE) /
            PriceLookupLib.priceForLevel(lvl);
        if (units == 0) return;
        if (units > type(uint32).max) units = type(uint32).max;
        _recordMintData(player, lvl, uint32(units));
    }

    /**
     * @notice Record mint metadata and update Activity Score metrics.
     * @dev Runs directly after the mint payment on the ETH-purchase path
     *      (the coin path never records mint data). Pure mintPacked_ accounting — touches
     *      no claimable or pool state.
     *
     * @param player Address of the player making the purchase.
     * @param lvl Target level for this purchase (`_activeTicketLevel()`: level+1 during the
     *        purchase phase and once the final jackpot draw is locked or the phase transition is
     *        underway, else the current jackpot level).
     * @param mintUnits Scaled ticket units purchased.
     *
     * ## Activity Score State Updates
     *
     * - `mintPacked_[player]` updated with level count, units, frozen-flag clearance, and affiliate bonus cache
     * - Only writes to storage if data actually changed
     *
     * ## Level Transition Logic
     *
     * - Same level: stamp mint day + accumulate units
     * - New level with <400 scaled units (4 * QTY_SCALE = one whole ticket): only track units, not "minted"
     * - New level with ≥400 scaled units: stamp mint day, bump lifetime level count (skipped while
     *   whale-pass frozen; pass flag/type clear once lvl passes frozenUntilLevel), refresh affiliate cache
     */
    function _recordMintData(
        uint32 player,
        uint24 lvl,
        uint32 mintUnits
    ) internal {
        // Load previous packed data
        uint256 prevData = mintPacked_[player];
        uint256 data;

        // ---------------------------------------------------------------------
        // Unpack previous state
        // ---------------------------------------------------------------------

        uint24 prevLevel = uint24(
            (prevData >> BitPackingLib.LAST_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        uint24 total = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 unitsLevel = uint24(
            (prevData >> BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );

        bool sameLevel = prevLevel == lvl;
        bool sameUnitsLevel = unitsLevel == lvl;

        // ---------------------------------------------------------------------
        // Handle level units
        // ---------------------------------------------------------------------

        // Get previous level units (reset on level change)
        uint256 levelUnitsBefore = sameUnitsLevel
            ? ((prevData >> BitPackingLib.LEVEL_UNITS_SHIFT) &
                BitPackingLib.MASK_16)
            : 0;

        // Calculate new level units (capped at 16-bit max)
        uint256 levelUnitsAfter = levelUnitsBefore + uint256(mintUnits);
        if (levelUnitsAfter > BitPackingLib.MASK_16) {
            levelUnitsAfter = BitPackingLib.MASK_16;
        }

        // ---------------------------------------------------------------------
        // Early exit: new level below one whole ticket's worth of units
        // (4 * QTY_SCALE = 1 ticket) — not counted as "minted": no mint-day
        // stamp, no level/streak/total. Units still accumulate, so cumulative
        // buys can cross the floor on a later buy.
        // ---------------------------------------------------------------------

        if (!sameLevel && levelUnitsAfter < 4 * QTY_SCALE) {
            data = BitPackingLib.setPacked(
                prevData,
                BitPackingLib.LEVEL_UNITS_SHIFT,
                BitPackingLib.MASK_16,
                levelUnitsAfter
            );
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT,
                BitPackingLib.MASK_24,
                lvl
            );
            if (data != prevData) {
                mintPacked_[player] = data;
                emit MintRecorded(player, data);
            }
            return;
        }

        // ---------------------------------------------------------------------
        // Update mint day
        // ---------------------------------------------------------------------

        uint24 day = _currentMintDay();
        data = _setMintDay(
            prevData,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_24
        );

        // ---------------------------------------------------------------------
        // Same level: Just update units
        // ---------------------------------------------------------------------

        if (sameLevel) {
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.LEVEL_UNITS_SHIFT,
                BitPackingLib.MASK_16,
                levelUnitsAfter
            );
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT,
                BitPackingLib.MASK_24,
                lvl
            );
            if (data != prevData) {
                mintPacked_[player] = data;
                emit MintRecorded(player, data);
            }
            return;
        }

        // ---------------------------------------------------------------------
        // New level with >= 400 scaled units (one whole ticket): full state update
        // ---------------------------------------------------------------------

        // Check for whale pass frozen state
        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        bool isFrozen = frozenUntilLevel > 0 && lvl <= frozenUntilLevel;

        // If frozen, skip updating total (it's pre-set by whale pass)
        // Once past the frozen level, clear the flag and resume normal tracking
        if (frozenUntilLevel > 0 && lvl > frozenUntilLevel) {
            // Clear frozen flag and whale pass type - resume normal tracking from here
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT,
                BitPackingLib.MASK_24,
                0
            );
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.WHALE_PASS_TYPE_SHIFT,
                3,
                0
            ); // Clear pass type
            frozenUntilLevel = 0;
            isFrozen = false;
        }

        if (!isFrozen) {
            // Update total (lifetime count)
            if (total < type(uint24).max) {
                unchecked {
                    total = uint24(total + 1);
                }
            }
        }

        // Pack all updated fields
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            lvl
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24,
            total
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_UNITS_SHIFT,
            BitPackingLib.MASK_16,
            levelUnitsAfter
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            lvl
        );
        // Frozen flag is already set in data if it was modified above

        // Score at the actual game level; the recorded ticket level can be one ahead.
        // Piggyback the current-level affiliate cache on this existing SSTORE.
        data = _cacheAffiliateBonus(player, level, data);

        // ---------------------------------------------------------------------
        // Commit to storage (only if changed)
        // ---------------------------------------------------------------------

        if (data != prevData) {
            mintPacked_[player] = data;
            emit MintRecorded(player, data);
        }
        return;
    }
}
