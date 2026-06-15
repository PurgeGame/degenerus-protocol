// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @dev Vault interface for the DGVE-majority bounty-eligibility tier (cold path).
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
    /// @notice Vault-owner salvage-buyer fallback config: whether the vault buys far-future tickets
    ///         when sDGNRS cannot fund the swap, and the ETH (wei) reserve it keeps untouched.
    function salvageBuyConfig() external view returns (bool enabled, uint256 floorWei);
}

/// @dev Shared mint streak and activity score utilities. Contains _playerActivityScore
///      (5-component scoring: mint streak, mint count, quest streak, affiliate bonus, deity/whale pass)
///      and mint streak helpers (credits on completed 1x price ETH quest).
abstract contract DegenerusGameMintStreakUtils is DegenerusGameStorage {
    /// @dev Mask for clearing last-completed + streak fields in one pass.
    uint256 private constant MINT_STREAK_FIELDS_MASK =
        (BitPackingLib.MASK_24 << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) |
        (BitPackingLib.MASK_24 << BitPackingLib.LEVEL_STREAK_SHIFT);

    /// @dev Soft pay-gate for the mintBurnie advance bounty: is `who` entitled to the
    ///      advance bounty right now? The advance work itself is always permitted — this
    ///      only decides whether the keeper earns the re-homed bounty, so real participants
    ///      get first shot while anyone may still do the work for free. Tiers, cheapest
    ///      first with short-circuit: minted today/yesterday, deity pass, anyone 30+ min
    ///      into the day, any pass holder 15+ min in, active afking sub, and finally the
    ///      DGVE-majority owner (the only external call, reached on the cold path only).
    function _bountyEligible(address who) internal view returns (bool) {
        uint24 gateIdx = dailyIdx;
        if (gateIdx == 0) return true; // first day — nothing to earn against yet

        uint256 mintData = mintPacked_[who];
        // Minted today or yesterday — the participation signal, no extra read.
        uint24 lastEthDay = uint24(
            (mintData >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32
        );
        if (lastEthDay + 1 >= gateIdx) return true;

        // Deity pass — always earns.
        if ((mintData >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0) return true;

        // 82620 = 22:57 UTC = the daily reset; elapsed is pure arithmetic, no SLOAD.
        uint256 elapsed = (block.timestamp - 82620) % 1 days;
        // Anyone, 30+ min into the day.
        if (elapsed >= 30 minutes) return true;
        // Any pass holder, 15+ min in.
        if (elapsed >= 15 minutes) {
            uint24 frozenUntilLevel = uint24(
                (mintData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                    BitPackingLib.MASK_24
            );
            if (frozenUntilLevel >= level) return true;
        }

        // Active afking subscriber — the daily auto-buy is participation that never
        // stamps DAY_SHIFT, so the lastEthDay check above misses it.
        if (_subOf[who].dailyQuantity != 0) return true;

        // DGVE majority owner — last resort, the only external call.
        return IDegenerusVaultOwner(ContractAddresses.VAULT).isVaultOwner(who);
    }

    /// @dev Record a mint streak completion for a given level (idempotent per level).
    function _recordMintStreakForLevel(address player, uint24 mintLevel) internal {
        if (player == address(0)) return;
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

    /// @dev Returns the active ticket level for direct ticket purchases.
    ///      During jackpot phase, direct tickets target the current level.
    ///      During purchase phase, direct tickets target the next level.
    function _activeTicketLevel() internal view returns (uint24) {
        return jackpotPhaseFlag ? level : level + 1;
    }

    /// @dev Far-future salvage discount curve (bps of face): two lines, 15% @ d6 -> 10% @ d20 ->
    ///      5% @ d100. Caller guarantees 6 <= d <= 100. Integer truncation is sub-bps, acceptable.
    function _farFutureFractionBps(uint256 d) internal pure returns (uint256) {
        if (d <= 20) return 1500 - ((d - 6) * 500) / 14; // 15% -> 10%
        return 1000 - ((d - 20) * 500) / 80; // 10% -> 5%
    }

    /// @dev Shared far-future salvage QUOTE (read-only valuation) used by BOTH the executing
    ///      entrypoint (MintModule.sellFarFutureTickets) and the preview view
    ///      (DegenerusGame.previewSellFarFutureTickets), so the offer shown can never drift from the
    ///      offer executed. Values each line at priceForLevel(L) with the two-line fractionBps(d)
    ///      curve + the daily per-player jitter seeded from the SETTLED prior-day VRF word
    ///      (freeze-safe). Reverts on an ineligible distance or zero quantity; does NOT check
    ///      ownership (the executing path checks holdings at debit). The split clamps the ticket leg
    ///      to <= totalBudget so the preview is safe for a too-small bundle (the executing path
    ///      separately requires totalBudget >= one whole current ticket).
    /// @param cl The active ticket level (caller-computed, shared with the split).
    /// @param oneTicketWei priceForLevel(cl) (caller-computed, shared with the split).
    /// @param seed The per-player daily salvage seed (_farFutureSeed — one computation
    ///        site keeps preview/exec parity by construction).
    /// @return totalFaceWei Sum of priceForLevel(L) * n over all lines.
    /// @return totalBudget Sum of jittered, distance-scaled budgets (ETH sDGNRS would pay).
    /// @return ticketWei Current-level ticket leg (jittered share, floored at 1 whole ticket).
    /// @return cashWei Withdrawable cash residual (totalBudget - ticketWei).
    function _quoteFarFutureSwap(
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint24 cl,
        uint256 oneTicketWei,
        uint256 seed
    )
        internal
        view
        returns (
            uint256 totalFaceWei,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 cashWei
        )
    {
        uint256 jitterMult = 7000 + (seed % 4001); // fraction multiplier [70%, 110%]
        uint256 ticketShareBps = 4000 + ((seed >> 128) % 4001); // ticket share [40%,80%] (cash [20%,60%])

        uint256 len = levels.length;
        for (uint256 i; i < len; ) {
            uint24 L = uint24(levels[i]);
            uint256 d = uint256(L) - uint256(cl); // reverts if L < cl
            if (d < 6 || d > 100) revert E();
            uint256 n = quantities[i];
            if (n == 0 || n > type(uint32).max) revert E();
            uint256 faceWei = PriceLookupLib.priceForLevel(L) * n;
            totalFaceWei += faceWei;
            totalBudget +=
                (faceWei * _farFutureFractionBps(d) * jitterMult) /
                (10_000 * 10_000);
            unchecked {
                ++i;
            }
        }

        ticketWei = (totalBudget * ticketShareBps) / 10_000;
        if (ticketWei < oneTicketWei) ticketWei = oneTicketWei;
        if (ticketWei > totalBudget) ticketWei = totalBudget; // preview-safety clamp (too-small bundle)
        cashWei = totalBudget - ticketWei;
    }

    /// @dev Splits the cash leg of a salvage swap into an ETH part and a BURNIE part, sharing the
    ///      SAME settled prior-day seed as _quoteFarFutureSwap (no new VRF). A third bit-slice of the
    ///      seed picks an ETH-denominated target in [0, cashWei]; the BURNIE part is capped at the
    ///      BURNIE the buyer actually owns (burnable held + claimable coinflip stake + auto-rebuy
    ///      carry), with the shortfall and the zero-available case falling back to ETH. The value of
    ///      the cash leg is conserved: ethCashWei + (value of burnieTokens) == cashWei, so the offer
    ///      stays <= the no-arb ceiling regardless of the split. Both the preview and the executing
    ///      path call this, so the displayed ETH/BURNIE breakdown matches what is paid.
    /// @param cashWei The cash residual being split (totalBudget - ticketWei).
    /// @param priceWei priceForLevel(active ticket level) (caller-computed).
    /// @param seed The per-player daily salvage seed (same word as _quoteFarFutureSwap).
    /// @param buyer The counterparty funding the swap (sDGNRS, or the vault on the owner-enabled fallback).
    /// @return ethCashWei ETH part relabeled to the player (cashWei - the BURNIE part's ETH value).
    /// @return burnieTokens BURNIE base units transferred from the buyer to the player.
    function _quoteFarFutureBurnieSplit(
        uint256 cashWei,
        uint256 priceWei,
        uint256 seed,
        address buyer
    ) internal view returns (uint256 ethCashWei, uint256 burnieTokens) {
        if (cashWei == 0) return (0, 0);

        // Third slice (distinct window from the jitter [bits 0..] and ticket-share [bits 128..]
        // slices): an ETH target in [0, cashWei].
        uint256 targetEth = ((seed >> 64) % (cashWei + 1));
        if (targetEth == 0) return (cashWei, 0);

        if (priceWei == 0) return (cashWei, 0);

        // Cap the BURNIE part at buyer-owned BURNIE (burnable held + claimable coinflip stake +
        // auto-rebuy carry), valued at the current ticket price. The uncovered remainder is paid as ETH.
        uint256 ownedBurnie = coin.balanceOfSpendableForSalvage(buyer);
        uint256 targetBurnie = (targetEth * PRICE_COIN_UNIT) / priceWei;
        burnieTokens = targetBurnie <= ownedBurnie ? targetBurnie : ownedBurnie;
        // ETH value of the BURNIE actually payable (re-derived from tokens so conservation is exact).
        uint256 burnieEth = (burnieTokens * priceWei) / PRICE_COIN_UNIT;
        if (burnieEth > cashWei) burnieEth = cashWei; // defensive; rounding can never exceed cashWei
        ethCashWei = cashWei - burnieEth;
    }

    /// @dev Per-player daily salvage seed: the seller hashed with the SETTLED prior-day
    ///      VRF word (freeze-safe). Single computation site shared by the swap quote and
    ///      the BURNIE split so preview and execution always derive the same offer.
    function _farFutureSeed(address player) internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(player, rngWordByDay[_simulatedDayIndex() - 1])
            )
        );
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
        return _playerActivityScoreAt(player, questStreak, streakBaseLevel, level);
    }

    /// @dev Activity score body operating on a caller-supplied current level, so every
    ///      level comparison (pass window, mint count, affiliate cache) shares one read.
    /// @param player The player address to calculate score for.
    /// @param questStreak Quest streak value (pre-fetched from handler return or external view).
    /// @param streakBaseLevel Level used for mint streak calculation.
    /// @param currLevel The game's current level.
    /// @return scoreBps Total activity score in basis points.
    function _playerActivityScoreAt(
        address player,
        uint32 questStreak,
        uint24 streakBaseLevel,
        uint24 currLevel
    ) internal view returns (uint256 scoreBps) {
        if (player == address(0)) return 0;

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
        uint8 bundleType = uint8(
            (packed >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3
        );
        bool passActive = frozenUntilLevel >= currLevel &&
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

            // Quest streak: 0.5% per quest completion, uncapped (the hard cap on the
            // total score below bounds the sum).
            bonusBps += uint256(questStreak) * 50;

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
            } else if (frozenUntilLevel >= currLevel) {
                // Whale pass bonus: varies by bundle type (only active while frozen)
                if (bundleType == 1) {
                    bonusBps += 1000; // +10% for 10-level bundle
                } else if (bundleType == 3) {
                    bonusBps += 4000; // +40% for 100-level bundle
                }
            }
        }

        // Cashout/smite curse penalty: each point lowers the activity score by 100 bps,
        // floored at 0. Rides the mintPacked_ word already loaded above (zero new SLOAD).
        uint256 curse = (packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_8;
        if (curse != 0) {
            uint256 penaltyBps = curse * 100;
            bonusBps = bonusBps > penaltyBps ? bonusBps - penaltyBps : 0;
        }

        scoreBps = bonusBps > ACTIVITY_SCORE_HARD_CAP_BPS
            ? ACTIVITY_SCORE_HARD_CAP_BPS
            : bonusBps;
    }

    /// @dev Convenience wrapper using the active ticket level (current level during
    ///      jackpot phase, next level otherwise) as streakBaseLevel, derived from a
    ///      single hoisted level read shared with the score body.
    /// @param player The player address to calculate score for.
    /// @param questStreak Quest streak value (pre-fetched from handler return or external view).
    /// @return scoreBps Total activity score in basis points.
    function _playerActivityScore(
        address player,
        uint32 questStreak
    ) internal view returns (uint256 scoreBps) {
        uint24 currLevel = level;
        return
            _playerActivityScoreAt(
                player,
                questStreak,
                jackpotPhaseFlag ? currLevel : currLevel + 1,
                currLevel
            );
    }

    // =========================================================================
    // Cashout / smite curse counter (mintPacked_ bits 215-222)
    // =========================================================================

    /// @dev Curse cap = 20 points (-2000 bps max). Doubles as the uint8-wrap guard: a
    ///      saturating +2 can never wrap the 8-bit field 254->0.
    uint8 internal constant CURSE_COUNT_CAP = 20;

    /// @dev Add a saturating +2 curse stack to `target` (no SSTORE once at the cap).
    function _applyCurseStack(address target) internal {
        uint256 packed = mintPacked_[target];
        uint256 curse = (packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_8;
        if (curse >= CURSE_COUNT_CAP) return;
        uint256 newCurse = curse + 2;
        if (newCurse > CURSE_COUNT_CAP) newCurse = CURSE_COUNT_CAP;
        mintPacked_[target] = BitPackingLib.setPacked(
            packed,
            BitPackingLib.CURSE_COUNT_SHIFT,
            BitPackingLib.MASK_8,
            newCurse
        );
    }

    /// @dev Clear `target`'s curse counter to 0 (field-isolated; no SSTORE when already 0).
    function _clearCurse(address target) internal {
        uint256 packed = mintPacked_[target];
        if ((packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_8 == 0) return;
        mintPacked_[target] = BitPackingLib.setPacked(
            packed,
            BitPackingLib.CURSE_COUNT_SHIFT,
            BitPackingLib.MASK_8,
            0
        );
    }

    /// @dev Stamp the current simulated day into `player`'s DAY_SHIFT field for lootbox
    ///      activity / bounty eligibility (no-op when already stamped today). Shared by the
    ///      pass-bundled lootbox leg and the plain standalone lootbox buy.
    function _recordLootboxMintDay(address player, uint256 cachedPacked) internal {
        uint24 day = _simulatedDayIndex();
        uint24 prevDay = uint24(
            (cachedPacked >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32
        );
        if (prevDay == day) {
            return;
        }
        uint256 clearedDay = cachedPacked &
            ~(BitPackingLib.MASK_32 << BitPackingLib.DAY_SHIFT);
        mintPacked_[player] =
            clearedDay |
            (uint256(day) << BitPackingLib.DAY_SHIFT);
    }
}
