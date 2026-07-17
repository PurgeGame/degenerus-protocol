// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {
    IDegenerusGameBoonModule,
    IDegenerusGameFoilPackModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusGameMintStreakUtils, IDegenerusVaultOwner} from "./DegenerusGameMintStreakUtils.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";

/**
 * @title DegenerusGameMintModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling mint history and ticket activation.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 *
 * ## Functions
 *
 * - `_recordMintData`: Track per-player mint history and update Activity Score metrics
 *
 * ## Activity Score System
 *
 * Player engagement is tracked through multiple loyalty metrics:
 * - **Level Count**: Total levels minted (lifetime participation)
 * - **Level Streak**: Consecutive level purchases
 * - **Quest Streak**: Daily quest completion streak (tracked in DegenerusQuests)
 * - **Affiliate Points**: Referral program bonus points (tracked in DegenerusAffiliate)
 * - **Whale Pass**: Active pass type (10-lvl or 100-lvl)
 *
 * ### Mint Data Bit Packing Layout (mintPacked_):
 *
 * ```
 * Bits 0-23:    lastLevel          - Last level with ETH mint
 * Bits 24-47:   levelCount         - Total levels minted (lifetime) [Activity Score]
 * Bits 48-71:   levelStreak        - Consecutive levels minted [Activity Score]
 * Bits 72-103:  lastMintDay        - Day index of last mint
 * Bits 104-127: unitsLevel         - Level index for levelUnits tracking
 * Bits 128-151: frozenUntilLevel   - Whale pass: freeze stats until this level (0 = not frozen)
 * Bits 152-153: whalePassType    - Active pass type (0=none, 1=10-lvl, 3=100-lvl) [Activity Score]
 * Bits 154-159: (unused)
 * Bits 160-183: mintStreakLast      - Last level credited for mint streak
 * Bit  184:     hasDeityPass        - Deity pass flag
 * Bits 185-208: affBonusLevel       - Cached affiliate bonus level
 * Bits 209-214: affBonusPoints      - Cached affiliate bonus points (0-50)
 * Bits 215-222: curseCount          - Cashout/smite curse counter (0-20)
 * Bits 223-227: (unused)
 * Bits 228-243: levelUnits         - Units minted this level
 * Bit 244:      (unused)
 * ```
 *
 * Note: Quest Streak is tracked in DegenerusQuests.questPlayerState.
 * Affiliate Points are tracked in DegenerusAffiliate and cached in mintPacked_ bits 185-214 on level transitions.
 *
 * ## Trait Generation
 *
 * Trait tickets are generated per queue entry in _raritySymbolBatch (not from a tokenId):
 * an LCG seeded by keccak256(baseKey, VRF entropyWord, groupIdx) — baseKey packs
 * (level, queueIdx, player, owed) — drives each entry's roll.
 * - Entry index & 3 selects the quadrant/category (0-63, 64-127, 128-191, 192-255)
 * - traitFromWord maps the word through an 8×8 weighted color×symbol grid
 * - Higher-numbered sub-traits within each category are slightly rarer
 */
contract DegenerusGameMintModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Safe write budget for gas control (keeps cold batch under 15M gas).
    uint32 private constant WRITES_BUDGET_SAFE = 550;

    /// @dev LCG multiplier for trait generation.
    uint64 private constant TICKET_LCG_MULT = 6364136223846793005;

    // -------------------------------------------------------------------------
    // Purchase / Lootbox Constants
    // -------------------------------------------------------------------------

    /// @dev Loot box minimum purchase amount (0.01 ETH).
    uint256 private constant LOOTBOX_MIN = 0.01 ether;
    /// @dev Coin-presale-box minimum purchase amount (0.01 ETH). Checked on the
    ///      REQUESTED amount BEFORE the exactly-50-ETH clamp, so a sub-floor gap to
    ///      the 50-ETH cap can never lock the presale close.
    uint256 private constant PRESALE_BOX_MIN = 0.01 ether;
    /// @dev Absolute minimum ticket buy-in (ETH equivalent).
    uint256 private constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;

    /// @dev Lootbox boost value cap and expiry for the next lootbox purchase.
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether;
    uint32 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;

    /// @dev Loot box pool split: 90% future, 10% next.
    uint16 private constant LOOTBOX_SPLIT_FUTURE_BPS = 9000;
    uint16 private constant LOOTBOX_SPLIT_NEXT_BPS = 1000;

    /// @dev Share of ticket purchases routed to future prize pool (10%).
    uint16 private constant PURCHASE_TO_FUTURE_BPS = 1000;

    /// @dev Number of daily jackpots per level (must match AdvanceModule).
    uint8 private constant JACKPOT_LEVEL_CAP = 5;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LootBoxBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 amount
    );
    /// @notice Emitted when a coin-presale box is bought and queued for resolution.
    /// @param buyer The player who bought the box.
    /// @param index The shared lootbox RNG index the box queued at.
    /// @param amount The applied box ETH (post-clamp).
    /// @param closing True iff this buy crossed the 50-ETH cap (latches presaleOver;
    ///        sweeps the Pool.PresaleBox remainder at this box's open).
    event PresaleBoxBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 amount,
        bool closing
    );

    /// @notice entryQuantityScaled in purchase units (4 * QTY_SCALE = 400 = one whole ticket);
    ///         weiIn = ETH-in for the manual-mint ticket leg (any funding source). The box leg
    ///         rides LootBoxBuy, so the two stay disjoint for off-chain ETH-in totals.
    event EntriesBought(address indexed buyer, uint256 entryQuantityScaled, uint256 weiIn);

    event BoostUsed(
        address indexed player,
        uint24 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    // -------------------------------------------------------------------------
    // Mint Payment + Data Recording
    // -------------------------------------------------------------------------

    /// @notice Record a mint payment, funded by ETH, claimable winnings, and/or afking.
    /// @dev Direct internal call on the ETH-purchase path (this frame already runs in the
    ///      Game's storage context). `ethForLeg` is the exact fresh-ETH value the caller
    ///      allocates to this leg — every payment-mode check binds to it, never to the outer
    ///      purchase tx's msg.value (a combined purchase splits one msg.value across legs).
    ///      Payment modes:
    ///      - DirectEth: fresh ETH first (overage ignored); afking covers any shortfall; claimable skipped
    ///      - Claimable: deduct from claimableWinnings (ethForLeg must be 0)
    ///      - Combined: ETH first, then claimable for remainder
    ///      Afking covers any remaining shortfall on every mode.
    ///
    ///      SECURITY: Validates minimum payment amounts; overage is ignored for accounting.
    ///      Splits the prize contribution into its next/future shares and RETURNS them so the
    ///      caller can fold the ticket and lootbox legs into one prize-pool RMW.
    ///
    /// @param player The player address to record mint for.
    /// @param costWei Total cost in wei for this mint.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param ethForLeg Fresh ETH allocated to this leg by the caller.
    /// @return nextShare Portion of this leg's contribution destined for the next prize pool.
    /// @return futureShare Portion destined for the future prize pool.
    /// @return claimableDraw Per-player claimable + afking drawn; caller subtracts it from claimablePool.
    /// @custom:reverts E If payment validation fails or the funding tiers fall short.
    function _recordMintPayment(
        address player,
        uint256 costWei,
        MintPaymentKind payKind,
        uint256 ethForLeg
    ) internal returns (uint256 nextShare, uint256 futureShare, uint256 claimableDraw) {
        uint256 prizeContribution;
        (prizeContribution, claimableDraw) = _processMintPayment(
            player,
            costWei,
            payKind,
            ethForLeg
        );
        if (prizeContribution != 0) {
            futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;
            nextShare = prizeContribution - futureShare;
        }
    }

    /// @dev Process mint payment and return amount contributed to prize pool.
    ///      Handles three payment modes with strict validation:
    ///
    ///      DirectEth: fresh ETH first (overage ignored); afking covers any shortfall; claimable skipped
    ///      Claimable: ethForLeg must be 0, deduct from claimableWinnings
    ///      Combined: ETH first (any amount ≤ cost), then claimable for rest
    ///
    ///      SECURITY: Leaves 1 wei sentinel in claimable to prevent zeroing.
    ///      The per-player claimable/afking balances are debited here; the matching claimablePool
    ///      decrement is deferred to the caller (returned as claimableDraw) so a combined buy folds
    ///      both legs into one pool RMW.
    ///
    /// @param player Player whose claimable balance to check/deduct.
    /// @param amount Total cost in wei to cover.
    /// @param payKind Payment method enum.
    /// @param ethForLeg Fresh ETH allocated to this leg by the caller.
    /// @return prizeContribution Amount contributing to next/future prize pools.
    /// @return claimableDraw Per-player claimable + afking drawn; caller subtracts it from claimablePool.
    function _processMintPayment(
        address player,
        uint256 amount,
        MintPaymentKind payKind,
        uint256 ethForLeg
    ) private returns (uint256 prizeContribution, uint256 claimableDraw) {
        uint256 ethUsed;
        uint256 claimableUsed;
        uint256 newClaimableBalance;
        if (payKind == MintPaymentKind.DirectEth) {
            // Direct ETH: fresh ETH first (overpay ignored), afking covers any shortfall;
            // claimable is skipped on this kind.
            ethUsed = ethForLeg < amount ? ethForLeg : amount;
        } else if (payKind == MintPaymentKind.Claimable) {
            // No fresh ETH allowed: draw claimable to the 1-wei sentinel, then afking.
            if (ethForLeg != 0) revert E();
            uint256 claimable = _claimableOf(player);
            if (claimable > 1) {
                uint256 available = claimable - 1; // Preserve 1 wei sentinel
                claimableUsed = amount < available ? amount : available;
                if (claimableUsed != 0) {
                    unchecked {
                        newClaimableBalance = claimable - claimableUsed;
                    }
                }
            }
        } else if (payKind == MintPaymentKind.Combined) {
            // ETH first, then claimable to the sentinel, then afking for any remainder.
            if (ethForLeg > amount) revert E();
            ethUsed = ethForLeg;
            uint256 remaining = amount - ethForLeg;
            if (remaining != 0) {
                uint256 claimable = _claimableOf(player);
                if (claimable > 1) {
                    uint256 available = claimable - 1; // Preserve 1 wei sentinel
                    claimableUsed = remaining < available
                        ? remaining
                        : available;
                    if (claimableUsed != 0) {
                        unchecked {
                            newClaimableBalance = claimable - claimableUsed;
                        }
                    }
                }
            }
        } else {
            revert E();
        }

        // Afking tier: the player's prepaid afking covers whatever fresh ETH + claimable did
        // not. afking is fresh-ETH-equivalent (own deposited principal), so it counts toward
        // prizeContribution. Reverts when the three tiers together fall short of the cost.
        uint256 afkingUsed = amount - ethUsed - claimableUsed;

        if (claimableUsed != 0 || afkingUsed != 0) {
            // One load + store of the packed per-player slot; the helper's per-half guards
            // reproduce the sequential claimable-then-afking debit reverts exactly (the
            // high-half guard IS the afking-sufficiency check).
            _debitClaimableAndAfking(player, claimableUsed, afkingUsed);
            // The claimablePool decrement for this draw is deferred to the caller, which folds
            // the ticket and lootbox legs into one RMW. claimableDraw is the per-player amount
            // drawn here (claimable + afking) that the caller must subtract from claimablePool.
            claimableDraw = claimableUsed + afkingUsed;
        }
        prizeContribution = ethUsed + claimableUsed + afkingUsed;

        if (claimableUsed != 0) {
            emit ClaimableSpent(
                player,
                claimableUsed,
                newClaimableBalance,
                payKind,
                amount
            );
        }
        if (afkingUsed != 0) {
            emit AfkingSpent(player, afkingUsed);
        }
    }

    // -------------------------------------------------------------------------
    // Future Ticket Activation
    // -------------------------------------------------------------------------

    /// @notice Activate future-pool tickets for a given level, bounded by a write budget.
    /// @param lvl The level whose queued tickets to process.
    /// @param entropy VRF-derived entropy for rarity rolls. Caller passes today's daily RNG word
    ///                (rngWordByDay[day]) so entropy cannot be clobbered by mid-day state changes.
    /// @return worked   True if at least one ticket was minted this call.
    /// @return finished True if the entire queue for `lvl` has been drained.
    /// @return writesUsed Write-budget units consumed (each storage write or skip costs one unit).
    function processFutureTicketBatch(
        uint24 lvl,
        uint256 entropy
    ) external returns (bool worked, bool finished, uint32 writesUsed) {
        bool inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT));
        uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);
        mapping(address => uint40) storage owedMap = entriesOwedPacked[rk];
        address[] storage queue = ticketQueue[rk];
        uint256 total = queue.length;
        if (total == 0) {
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true, 0);
        }

        if (!inFarFuture && ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        if (idx >= total) {
            _releaseTicketQueue(rk);
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true, 0);
        }

        // Set up write budget with cold storage scaling on first batch
        uint32 writesBudget = WRITES_BUDGET_SAFE;
        if (idx == 0) {
            writesBudget -= (writesBudget * 35) / 100; // 65% scaling for cold storage
        }

        uint32 used;
        uint32 processed; // Track within-player progress

        // Trait-batch scratch buffers shared by every entry this call (zeroed between
        // entries inside _raritySymbolBatch), so memory does not grow per queue entry.
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;

        while (idx < total && used < writesBudget) {
            address player = queue[idx];
            uint40 packed = owedMap[player];
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            uint256 baseKey = (uint256(lvl) << 224) |
                (idx << 192) |
                (uint256(uint160(player)) << 32) |
                uint256(owed);
            if (owed == 0) {
                if (rem == 0) {
                    if (packed != 0) {
                        owedMap[player] = 0;
                    }
                    // Charge one budget unit for skip/cleanup progress so sparse
                    // queues cannot consume unbounded work in one call.
                    unchecked {
                        ++idx;
                        ++used;
                    }
                    processed = 0;
                    continue;
                }
                if (!_rollRemainder(entropy, baseKey, rem)) {
                    owedMap[player] = 0;
                    unchecked {
                        ++idx;
                        ++used;
                    }
                    processed = 0;
                    continue;
                }
                uint40 rolledPacked = uint40(1) << 8;
                if (rolledPacked != packed) {
                    owedMap[player] = rolledPacked;
                }
                packed = rolledPacked;
                owed = 1;
                rem = 0;
            }
            uint32 room = writesBudget - used;
            uint32 baseOv = (processed == 0 && owed <= 2) ? 4 : 2;
            if (room <= baseOv) break;
            room -= baseOv;

            uint32 maxT = (room <= 256) ? (room / 2) : (room - 256);
            uint32 take = owed > maxT ? maxT : owed;
            // Budget-limited takes stay whole-ticket (%4) aligned: `processed` does not
            // survive a cross-call resume, so the quadrant cycle (i & 3) restarts at 0 —
            // an aligned split boundary makes that restart the correct continuation.
            if (take != owed) take &= ~uint32(3);
            if (take == 0) break;

            _raritySymbolBatch(
                player,
                baseKey,
                processed,
                take,
                entropy,
                counts,
                touchedTraits
            );
            emit TraitsGenerated(player, baseKey, take);

            // Calculate actual write cost
            uint32 writesThis = (take <= 256) ? (take * 2) : (take + 256);
            writesThis += baseOv;
            if (take == owed) writesThis += 1;

            uint32 remainingOwed;
            unchecked {
                remainingOwed = owed - take;
            }
            if (remainingOwed == 0 && rem != 0) {
                if (_rollRemainder(entropy, baseKey, rem)) {
                    remainingOwed = 1;
                }
                rem = 0;
            }
            uint40 newPacked = (uint40(remainingOwed) << 8) | uint40(rem);
            if (newPacked != packed) {
                owedMap[player] = newPacked;
            }
            unchecked {
                processed += take;
                used += writesThis;
            }

            if (remainingOwed == 0) {
                unchecked {
                    ++idx;
                }
                processed = 0;
            }
        }

        worked = (used > 0);
        writesUsed = used;
        finished = (idx >= total);
        if (finished) {
            _releaseTicketQueue(rk);
            if (!inFarFuture) {
                uint24 ffk = _tqFarFutureKey(lvl);
                if (ticketQueue[ffk].length > 0) {
                    ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                    ticketCursor = 0;
                    finished = false;
                } else {
                    ticketCursor = 0;
                    ticketLevel = 0;
                }
            } else {
                ticketCursor = 0;
                ticketLevel = 0;
            }
        } else {
            // Mid-queue stop: persist the resume cursor. The finished paths above
            // write their own terminal cursor/level pair, so the shared packed slot
            // is stored exactly once per path.
            ticketCursor = uint32(idx);
        }
    }

    /// @dev Generates trait tickets in batch for a player's ticket awards using LCG-based PRNG.
    ///      Uses inline assembly for gas-efficient bulk storage writes.
    /// @param player Address receiving the trait tickets.
    /// @param baseKey Encoded key carrying (lvl, queueIdx, player, owed) packed across 256 bits.
    ///                The owed value in the low 32 bits mutates per emission, so multi-call
    ///                drains hash distinct seeds across calls on the same player.
    /// @param startIndex Starting position within this player's owed tickets for this batch.
    /// @param count Number of ticket entries to process this batch.
    /// @param entropyWord VRF entropy for trait generation.
    /// @param counts Caller-allocated all-zero scratch tracking how many times each trait
    ///               was generated; the touched entries are re-zeroed before return, so one
    ///               allocation serves every entry of a batch loop.
    /// @param touchedTraits Caller-allocated scratch listing the traits generated this call
    ///                      (only the first `touchedLen` entries are read).
    function _raritySymbolBatch(
        address player,
        uint256 baseKey,
        uint32 startIndex,
        uint32 count,
        uint256 entropyWord,
        uint32[256] memory counts,
        uint8[256] memory touchedTraits
    ) private {
        uint16 touchedLen;

        uint32 endIndex;
        unchecked {
            endIndex = startIndex + count;
        }
        uint32 i = startIndex;

        // Generate traits in groups of 16, using LCG for deterministic randomness.
        while (i < endIndex) {
            uint32 groupIdx = i >> 4;

            // Hash all inputs so player address (stored in baseKey bits 191-32)
            // reaches the low 32 bits of s. LCG iteration preserves low-bit
            // independence, so the category bucket — derived from the low 32
            // bits of s — inherits whatever entropy the seed's low bits carry.
            uint256 seed = uint256(
                keccak256(abi.encode(baseKey, entropyWord, groupIdx))
            );
            uint64 s = uint64(seed) | 1;
            uint8 offset = uint8(i & 15);
            unchecked {
                s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset);
            }

            for (uint8 j = offset; j < 16 && i < endIndex; ) {
                unchecked {
                    s = s * TICKET_LCG_MULT + 1; // LCG step

                    // Generate trait using weighted distribution, add quadrant offset.
                    uint8 traitId = DegenerusTraitUtils.traitFromWord(s) +
                        (uint8(i & 3) << 6);

                    // Track first occurrence of each trait for batch writing.
                    if (counts[traitId]++ == 0) {
                        touchedTraits[touchedLen++] = traitId;
                    }
                    ++i;
                    ++j;
                }
            }
        }

        // Extract level from baseKey for storage slot calculation.
        uint24 lvl = uint24(baseKey >> 224);

        // Calculate the storage slot for this level's trait arrays.
        // Layout assumption: lvlTraitEntry is mapping(uint24 => address[256]).
        // Solidity stores mapping(key => fixedArray) as keccak256(key . slot) + index,
        // with dynamic array elements at keccak256(keccak256(key . slot) + index).
        // This relies on the standard Solidity storage layout (stable since 0.4.x).
        // Safe here because the contract is non-upgradeable.
        uint256 levelSlot;
        assembly ("memory-safe") {
            mstore(0x00, lvl)
            mstore(0x20, lvlTraitEntry.slot)
            levelSlot := keccak256(0x00, 0x40)
        }

        // Batch-write trait tickets to storage using assembly for gas efficiency.
        for (uint16 u; u < touchedLen; ) {
            uint8 traitId = touchedTraits[u];
            uint32 occurrences = counts[traitId];
            // Restore the all-zero invariant on the shared scratch buffer.
            counts[traitId] = 0;

            assembly ("memory-safe") {
                // Get array length slot and current length.
                let elem := add(levelSlot, traitId)
                let len := sload(elem)
                let newLen := add(len, occurrences)
                sstore(elem, newLen)

                // Calculate data slot and write player address `occurrences` times.
                mstore(0x00, elem)
                let data := keccak256(0x00, 0x20)
                let dst := add(data, len)
                for {
                    let k := 0
                } lt(k, occurrences) {
                    k := add(k, 1)
                } {
                    sstore(dst, player)
                    dst := add(dst, 1)
                }
            }
            unchecked {
                ++u;
            }
        }
    }

    /// @dev Roll remainder chance for a fractional ticket (0-99).
    function _rollRemainder(
        uint256 entropy,
        uint256 rollSalt,
        uint8 rem
    ) private pure returns (bool win) {
        // Hash via scratch-slot keccak so player address (stored in rollSalt
        // bits 191-32) reaches the low 7 bits of rollEntropy consumed by
        // `% QTY_SCALE`. A plain XOR mix only diffuses bits a fixed span
        // outward, leaving upper player-address bits invisible to the roll
        // outcome; keccak gives full low-bit diffusion of the high-bit input.
        uint256 rollEntropy = EntropyLib.hash2(entropy, rollSalt);
        return (rollEntropy % QTY_SCALE) < rem;
    }

    // -------------------------------------------------------------------------
    // External Entry Point — Current-Level Ticket Batch Processing
    // -------------------------------------------------------------------------

    /// @notice Processes a batch of current-level tickets with gas-bounded iteration.
    /// @dev Called iteratively until all tickets for the level are processed. Uses a writes budget
    ///      to stay within block gas limits. The first batch in a new level round is
    ///      scaled down by 35% to account for cold storage access costs.
    /// @param lvl Level whose tickets should be processed.
    /// @return finished True if all tickets for this level have been fully processed.
    /// @return didWork True if this call materialized at least one ticket entry or foil
    ///         buyer. Lets the advance chain break out before composing a finishing batch
    ///         with a same-tx BAF/jackpot, even when the batch both starts and finishes in
    ///         one call (cursor returns to 0, so a cursor-delta probe would read no work).
    function processTicketBatch(uint24 lvl)
        external
        returns (bool finished, bool didWork)
    {
        uint24 rk = _tqReadKey(lvl);
        mapping(address => uint40) storage owedMap = entriesOwedPacked[rk];
        address[] storage queue = ticketQueue[rk];
        uint256 total = queue.length;

        if (ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        uint32 writesBudget = WRITES_BUDGET_SAFE;
        if (idx == 0) {
            writesBudget -= (writesBudget * 35) / 100; // 65% scaling for cold storage
        }

        if (idx >= total) {
            // Normal queue already drained (empty this level, or finished on a prior
            // tx). Still drain the per-buy-day foil buckets on the full budget before
            // declaring the level finished — the readiness gate depends on it. Returns
            // false (resume next tx) only if a budget-short foil pack defers. _drainFoil
            // short-circuits on _foilDrainPending, so a no-foil call is a single SLOAD.
            if (total != 0) {
                _releaseTicketQueue(rk);
            }
            (bool foilDoneEmpty, bool foilDrainedEmpty) = _drainFoil(writesBudget);
            ticketCursor = 0;
            if (foilDoneEmpty) {
                ticketLevel = 0;
                return (true, foilDrainedEmpty);
            }
            return (false, foilDrainedEmpty);
        }

        uint256 entropy = lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1];

        uint32 used;
        uint32 processed;

        // Trait-batch scratch buffers shared by every normal entry this call (zeroed
        // between entries inside _raritySymbolBatch), so memory does not grow per
        // queue entry. The foil drain runs in a separate module and owns its scratch.
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;

        while (idx < total && used < writesBudget) {
            (uint32 writesUsed, uint32 take, bool advance) = _processOneTicketEntry(
                queue[idx],
                lvl,
                owedMap,
                writesBudget - used,
                processed,
                entropy,
                idx,
                counts,
                touchedTraits
            );
            if (writesUsed == 0 && !advance) break;
            unchecked {
                used += writesUsed;
                if (advance) {
                    ++idx;
                    processed = 0;
                } else {
                    // Advance the within-player startIndex by the per-iter ticket
                    // count, matching processFutureTicketBatch. A gas-budget-derived
                    // writesUsed>>1 heuristic would diverge for take > 256.
                    processed += take;
                }
            }
        }

        if (idx >= total) {
            // Normal queue drained. Continue into the per-buy-day foil buckets on the
            // leftover write budget (one shared envelope, so the combined advance
            // stays gas-bounded). A foil buyer resolves a fixed FOIL_PACK_ENTRIES
            // (16) boosted entries atomically; foilDrainDay/foilCursor make a
            // budget-short deferral resumable. Only when BOTH the queue and the foil
            // drain are caught up is the level finished, so the readiness gate cannot
            // let the jackpot draw early.
            if (total != 0) {
                _releaseTicketQueue(rk);
            }
            // A final loop iteration can push `used` past writesBudget, so clamp the
            // leftover to 0 (an over-budget call leaves no room for foil and defers it
            // to the next tx) rather than underflowing the subtraction.
            uint32 foilRoom = used >= writesBudget ? 0 : writesBudget - used;
            (bool foilDone, bool foilDrained) = _drainFoil(foilRoom);
            // Real work this call iff the normal loop consumed budget OR a foil buyer
            // resolved — the signal the advance chain reads to refuse same-tx composition.
            bool didWorkThisCall = used > 0 || foilDrained;
            if (foilDone) {
                ticketCursor = 0;
                ticketLevel = 0;
                return (true, didWorkThisCall);
            }
            // Foil queue has more entries than the budget could fit: resume next tx.
            // The normal cursor stays at its terminal position (idx == total).
            ticketCursor = uint32(idx);
            return (false, didWorkThisCall);
        }
        // Mid-queue stop: persist the resume cursor. The finished path above writes
        // its own terminal cursor/level pair, so the shared packed slot is stored
        // exactly once per path.
        ticketCursor = uint32(idx);
        return (false, used > 0);
    }

    /// @dev Hand the per-buy-day foil buckets to the foil module on the leftover write
    ///      budget after the normal queue is exhausted. The drain itself lives in
    ///      DegenerusGameFoilPackModule (this near-full module would otherwise exceed
    ///      the EIP-170 runtime limit); the delegatecall runs there in the Game's
    ///      storage context, so it walks foilDrainDay/foilCursor and writes the same
    ///      lvlTraitEntry buckets this module would have. When no foil drain is
    ///      pending (none ever bought, or every sealed bucket already drained) the foil
    ///      module is not invoked at all — the common advance carries no foil-module
    ///      dependency, gas, or brick surface.
    /// @return done True iff the foil drain has caught up (no sealed bucket remains).
    /// @return drained True if this call resolved at least one foil buyer.
    function _drainFoil(uint32 room) private returns (bool done, bool drained) {
        if (!_foilDrainPending()) return (true, false);
        // A foil buyer costs a fixed FOIL_PACK_ENTRIES*2 + 3 budget units; if the
        // normal queue already consumed the budget there is no room for even one, so
        // defer to the next tx WITHOUT the delegatecall (pending foil is never "done"
        // here — the readiness gate keeps the draw blocked until it drains).
        if (room < (FOIL_PACK_ENTRIES * 2) + 3) return (false, false);
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_FOILPACK_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameFoilPackModule.processFoilDrain.selector,
                    room
                )
            );
        if (!ok) {
            if (data.length == 0) revert E();
            assembly ("memory-safe") {
                revert(add(32, data), mload(data))
            }
        }
        return abi.decode(data, (bool, bool));
    }

    /// @dev Resolves the zero-owed remainder case for ticket processing.
    function _resolveZeroOwedRemainder(
        uint40 packed,
        mapping(address => uint40) storage owedMap,
        address player,
        uint256 entropy,
        uint256 baseKey
    ) private returns (uint40 newPacked, bool skip) {
        uint8 rem = uint8(packed);
        if (rem == 0) {
            if (packed != 0) {
                owedMap[player] = 0;
            }
            return (0, true);
        }

        bool win = _rollRemainder(entropy, baseKey, rem);
        if (!win) {
            owedMap[player] = 0;
            return (0, true);
        }

        newPacked = uint40(1) << 8;
        if (newPacked != packed) {
            owedMap[player] = newPacked;
        }
        return (newPacked, false);
    }

    /// @dev Processes a single ticket entry, returning writes used and whether to advance.
    function _processOneTicketEntry(
        address player,
        uint24 lvl,
        mapping(address => uint40) storage owedMap,
        uint32 room,
        uint32 processed,
        uint256 entropy,
        uint256 queueIdx,
        uint32[256] memory counts,
        uint8[256] memory touchedTraits
    ) private returns (uint32 writesUsed, uint32 take, bool advance) {
        uint40 packed = owedMap[player];
        uint32 owed = uint32(packed >> 8);
        uint256 baseKey = (uint256(lvl) << 224) |
            (queueIdx << 192) |
            (uint256(uint160(player)) << 32) |
            uint256(owed);

        if (owed == 0) {
            bool skip;
            (packed, skip) = _resolveZeroOwedRemainder(
                packed,
                owedMap,
                player,
                entropy,
                baseKey
            );
            if (skip) return (1, 0, true);
            owed = 1;
        }

        uint32 baseOv = (processed == 0 && owed <= 2) ? 4 : 2;
        if (room <= baseOv) return (0, 0, false);
        {
            uint32 availRoom = room - baseOv;
            uint32 maxT = (availRoom <= 256)
                ? (availRoom >> 1)
                : (availRoom - 256);
            take = owed > maxT ? maxT : owed;
        }
        // Budget-limited takes stay whole-ticket (%4) aligned so the quadrant cycle
        // restarts correctly on a cross-call resume (see processFutureTicketBatch).
        if (take != owed) take &= ~uint32(3);
        if (take == 0) return (0, 0, false);

        _raritySymbolBatch(
            player,
            baseKey,
            processed,
            take,
            entropy,
            counts,
            touchedTraits
        );
        emit TraitsGenerated(player, baseKey, take);

        writesUsed =
            ((take <= 256) ? (take << 1) : (take + 256)) +
            baseOv +
            (take == owed ? 1 : 0);

        uint8 rem = uint8(packed);
        uint32 remainingOwed;
        unchecked {
            remainingOwed = owed - take;
        }
        if (remainingOwed == 0 && rem != 0) {
            if (_rollRemainder(entropy, baseKey, rem)) {
                remainingOwed = 1;
            }
            rem = 0;
        }
        uint40 newPacked = (uint40(remainingOwed) << 8) | uint40(rem);
        if (newPacked != packed) {
            owedMap[player] = newPacked;
        }
        advance = remainingOwed == 0;
    }

    // -------------------------------------------------------------------------
    // Purchases and Loot Boxes
    // -------------------------------------------------------------------------

    /// @notice Purchase tickets and loot boxes for a buyer.
    /// @dev Delegatecalled by DegenerusGame. Handles payment routing, affiliates, and queues.
    /// @param buyer Recipient of the purchased items.
    /// @param entryQuantityScaled Number of tickets to purchase (2 decimals, scaled by 100).
    /// @param lootBoxAmount ETH amount for loot boxes.
    /// @param affiliateCode Referral code for affiliate attribution.
    /// @param payKind Payment kind selector (ETH/claimable/combined).
    function purchase(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        _purchaseFor(
            buyer,
            entryQuantityScaled,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    /// @notice Explicit-ethValue ticket-buy entry: like `purchase`, but the fresh-ETH portion
    ///         is the `ethValue` parameter rather than `msg.value`. Sole caller: the facade's
    ///         foil purchase, which funds the ticket/lootbox leg with the fresh ETH it carved
    ///         while the buyer's msg.value is in flight (that msg.value is ignored here — only
    ///         ethValue is spent). payable so the carried msg.value does not revert the
    ///         delegatecall.
    function purchaseWith(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) external payable {
        _purchaseForWith(
            buyer,
            entryQuantityScaled,
            lootBoxAmount,
            affiliateCode,
            payKind,
            ethValue
        );
    }

    /// @notice Redeem FLIP for current-jackpot tickets — allowed only inside the jackpot window.
    /// @dev Reverts unless the FLIP purchase window is open: the prize target is met in the purchase
    ///      phase, or the jackpot phase is live, with no RNG in flight. Outside that window FLIP ticket
    ///      purchases revert so bonus tickets and prize ETH accrue to real-ETH buyers.
    /// @param buyer Recipient of the purchased tickets.
    /// @param entryQuantityScaled Number of tickets to purchase (2 decimals, scaled by 100).
    function redeemFlip(
        address buyer,
        uint256 entryQuantityScaled
    ) external {
        _redeemFlipFor(buyer, entryQuantityScaled);
    }

    function _redeemFlipFor(
        address buyer,
        uint256 entryQuantityScaled
    ) private {
        if (_livenessTriggered()) revert E();

        if (entryQuantityScaled != 0) {
            // FLIP purchase window: opens the first time a redeem lands once the prize target is met
            // in the purchase phase with no RNG in flight, latching a single warm slot-0 bit. It stays
            // open through the jackpot days and is cleared in the advance at the final jackpot day's RNG
            // request — the boundary where new tickets route to the next level (rngLockedFlag stays set
            // from that request until _unlockRng, so it can never flip back on during the wind-down).
            // While it is closed (an open/stalled purchase phase) FLIP purchases revert, so bonus
            // tickets and prize ETH accrue to real-ETH buyers. The target-met condition holds for the
            // whole of lastPurchaseDay, so even a one-day purchase phase still offers that day as a
            // redemption window.
            if (!ticketRedemptionOpen) {
                if (
                    rngLockedFlag ||
                    _getNextPrizePool() < levelPrizePool[level]
                ) revert E();
                ticketRedemptionOpen = true;
            }

            uint24 cachedLevel = level;
            (
                ,
                uint32 adjustedQty32,
                uint24 targetLevel,
                uint32 flipMintUnits,
                ,
                ,
                ,
                ,
            ) = _callTicketPurchase(
                    buyer,
                    entryQuantityScaled,
                    MintPaymentKind.DirectEth,
                    true,
                    0,
                    jackpotPhaseFlag
                );

            // MINT_FLIP quest leg only (no ETH spend, no lootbox): skips activity
            // score, affiliate, and non-mint quests. The returned reward is a FLIP
            // flip stake, awarded via creditFlip — the full coin cost was already
            // burned inside _callTicketPurchase.
            {
                uint256 nextLevelPrice = PriceLookupLib.priceForLevel(
                    cachedLevel + 1
                );
                (uint256 questReward, , , bool questCompleted) = quests
                    .handlePurchase(
                        buyer,
                        0,
                        flipMintUnits,
                        0,
                        nextLevelPrice,
                        nextLevelPrice
                    );
                if (questCompleted && questReward != 0) {
                    coinflip.creditFlip(buyer, questReward);
                }
            }

            // Queue tickets on the captured adjusted quantity.
            if (adjustedQty32 != 0) {
                _queueEntriesScaled(buyer, targetLevel, adjustedQty32, false);
            }
        }
    }

    /// @notice Emitted on a far-future salvage swap (sellFarFutureEntries).
    /// @dev `buyer` is the counterparty that funded the swap and received the far-future tickets:
    ///      sDGNRS normally, or the vault on the owner-enabled fallback when sDGNRS cannot fund it.
    ///      cashWei subdivides into ethCashWei (relabeled claimable) + flipTokens (buyer-owned FLIP
    ///      burned, paid to the player as flip credit). value(flipTokens) + ethCashWei == cashWei.
    event FarFutureSwap(
        address indexed player,
        address indexed buyer,
        uint256 lineCount,
        uint256 totalBudgetWei,
        uint256 ticketWei,
        uint256 ethCashWei,
        uint256 flipTokens
    );

    /// @notice Quote a far-future salvage swap WITHOUT executing (the UI offer; -EV by design).
    /// @dev Read-only twin of sellFarFutureEntries: shares the exact valuation (curve + daily
    ///      per-player jitter + ETH/FLIP split) the executing path uses, so the displayed offer
    ///      matches what would be paid. Resolves the same buyer the executing path would (sDGNRS, or
    ///      the vault on the owner-enabled fallback) so the ETH/FLIP breakdown reflects the actual
    ///      counterparty's FLIP inventory. Reverts on an ineligible distance or a zero /
    ///      non-whole-ticket quantity (entry counts in multiples of 4); does
    ///      NOT check ownership (a quote for the given bundle). When the resolved buyer holds no FLIP
    ///      (or the seed targets zero) the whole cash leg is paid in ETH; conserved as ethCashWei +
    ///      value(flipTokens).
    /// @return totalFaceWei Sum of priceForLevel(L) * n / 4 over all lines (per-entry face; bundle face).
    /// @return totalBudget Total ETH the buyer would pay (the -EV offer).
    /// @return ticketWei Portion delivered as current-level tickets.
    /// @return ethCashWei Cash portion delivered as withdrawable ETH claimable.
    /// @return flipTokens Cash portion delivered as FLIP (burned from the buyer, paid as flip credit).
    function previewSellFarFutureEntries(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities
    )
        external
        view
        returns (
            uint256 totalFaceWei,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 ethCashWei,
            uint256 flipTokens
        )
    {
        uint24 cl = _activeTicketLevel();
        uint256 oneTicketWei = PriceLookupLib.priceForLevel(cl);
        uint256 seed = _farFutureSeed(player);
        uint256 cashWei;
        (totalFaceWei, totalBudget, ticketWei, cashWei) = _quoteFarFutureSwap(
            levels,
            quantities,
            cl,
            oneTicketWei,
            seed
        );
        // Display the split for the buyer the executing path would resolve; fall back to sDGNRS as the
        // nominal counterparty when neither can fund (the preview still shows the -EV offer).
        address buyer = _resolveSalvageBuyer(totalBudget);
        if (buyer == address(0)) buyer = ContractAddresses.SDGNRS;
        (ethCashWei, flipTokens) = _quoteFarFutureFlipSplit(
            cashWei,
            oneTicketWei,
            seed,
            buyer
        );
    }

    /// @notice Sell far-future ticket entries (current-level tickets + cash; -EV exit) to sDGNRS, or to
    ///         the vault on the owner-enabled fallback when sDGNRS cannot fund the swap.
    /// @dev Delegatecalled from DegenerusGame.sellFarFutureEntries with an already-resolved `player`
    ///      (so no _resolvePlayer here). Mass-sells far-future ticket ENTRIES (4 entries = 1 whole ticket;
    ///      6 <= d = L - currentLevel <= 100) for ONE aggregated current-level mint (a normal recycled
    ///      Claimable mint) + a cash
    ///      residual. The counterparty is resolved by _resolveSalvageBuyer: sDGNRS first (funded from
    ///      claimableWinnings[SDGNRS] above a >=1 ETH floor), else the vault if its owner enabled the
    ///      fallback and it can fund above its owner-set reserve floor; the offer price is identical
    ///      either way. No pendingRedemptionEthValue term, no daily cap. Valuation + daily jitter are
    ///      shared with the preview via _quoteFarFutureSwap. The fully-liquidated seller is swap-popped
    ///      from ticketQueue (membership <=> packed != 0 maintained; far-future jackpot samplers unchanged).
    /// @custom:reverts E On bad input/distance/holdings, too-small budget, no buyer able to fund (sDGNRS
    ///                   below its >=1 ETH floor and no vault fallback), gameOver/liveness, or a stale
    ///                   queue index.
    /// @custom:reverts RngLocked While the RNG window is locked (freeze invariant).
    function sellFarFutureEntries(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint256[] calldata queueIndices
    ) external {
        if (rngLockedFlag) revert RngLocked();
        if (gameOver) revert E();
        if (_livenessTriggered()) revert E();
        uint256 len = levels.length;
        if (
            len == 0 ||
            len > 32 ||
            quantities.length != len ||
            queueIndices.length != len
        ) revert E();

        uint24 cl = _activeTicketLevel();
        uint256 oneTicketWei = PriceLookupLib.priceForLevel(cl);
        uint256 seed = _farFutureSeed(player);
        (
            ,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 cashWei
        ) = _quoteFarFutureSwap(levels, quantities, cl, oneTicketWei, seed);
        if (totalBudget < oneTicketWei / 4) revert E(); // too small to deliver even 1 entry

        // Resolve the counterparty fail-closed: sDGNRS funds from its OWN claimable above a >=1 ETH
        // floor; if it cannot and the vault owner enabled the fallback, the vault buys above its
        // owner-set reserve floor; otherwise address(0) -> revert. The gambling-burn redemption desk is
        // protected STRUCTURALLY (its ETH is segregated out of claimable at submit), so NO
        // pendingRedemptionEthValue term is needed; NO daily cap. The full budget is gated against the
        // buyer's claimable even though only the ETH part leaves claimable below (the FLIP part is paid
        // from the buyer's FLIP) — a strictly more conservative funding check.
        address buyer = _resolveSalvageBuyer(totalBudget);
        if (buyer == address(0)) revert E();

        // Split the cash leg: pay an ETH part (claimable relabel) + a FLIP part burned from the buyer's
        // FLIP, with an ETH fallback when the buyer holds no FLIP. The split conserves the cash-leg
        // value (ethCashWei + value(flipTokens) == cashWei), so the offer is unchanged.
        (uint256 ethCashWei, uint256 flipTokens) = _quoteFarFutureFlipSplit(
            cashWei,
            oneTicketWei,
            seed,
            buyer
        );

        // Debit the seller's far entries (quantities[i] IS the entry count, 4 per whole ticket; swap-pop on
        // full sell-out) and credit the buyer the same entries. Distances were validated by
        // _quoteFarFutureSwap; sequential processing handles duplicate levels (a later same-level line reads
        // the decremented balance and reverts if it over-sells; only the line that zeroes the packed slot pops).
        for (uint256 i; i < len; ) {
            uint24 L = uint24(levels[i]);
            uint32 entries = uint32(quantities[i]);
            _removeFarFutureEntries(player, L, entries, queueIndices[i]);
            _queueEntries(buyer, L, entries, false);
            unchecked {
                ++i;
            }
        }

        // Relabel only the ETH portion (ticket leg + ETH cash) buyer -> player as claimable; the buyer
        // funds from its claimable (and, for the vault, its prepaid afking) — both claimablePool-backed,
        // so the move is total-preserving (claimablePool unchanged). The FLIP part never touches
        // claimable. Solvency-positive: ethRelabel <= totalBudget.
        uint256 ethRelabel = ticketWei + ethCashWei;
        _debitSalvageEth(buyer, ethRelabel);
        _creditClaimable(player, ethRelabel);
        // FLIP part: drain the buyer's FLIP (held first, then claimable coinflip stake, then the
        // auto-rebuy carry — the full salvage waterfall, symmetric with the redemption desk) and pay the
        // player as flip credit, not a token transfer. flipTokens <= the buyer's spendable (quote cap),
        // so the burn always covers.
        if (flipTokens != 0) {
            coin.burnCoinForSalvage(buyer, flipTokens);
            coinflip.creditFlip(player, flipTokens);
        }

        // Ticket leg = NORMAL recycled mint of `ticketWei` of current-level tickets from the player's
        // claimable (routes 90% next / 10% future + queues current tickets). Leftover (~ethCashWei) is
        // the player's withdrawable cash. qty in purchase units (4 * QTY_SCALE = 400 = one whole ticket).
        uint256 qty = (ticketWei * 4 * QTY_SCALE) / oneTicketWei;
        _purchaseFor(player, qty, 0, bytes32(0), MintPaymentKind.Claimable);

        emit FarFutureSwap(player, buyer, len, totalBudget, ticketWei, ethCashWei, flipTokens);
    }

    /// @dev Resolve the salvage-swap counterparty for a budget, fail-closed. sDGNRS first when its OWN
    ///      claimable covers totalBudget above a >=1 ETH floor; else the vault when its owner has enabled
    ///      the salvage-buy fallback AND its game-side ETH (claimable + prepaid afking, both backed by
    ///      claimablePool) covers totalBudget above the owner-set reserve floor; else address(0) (no buyer
    ///      can fund). The vault owner stages reserve ETH into the afking half via depositAfkingFunding.
    ///      Shared by the executing path and the preview so the displayed counterparty matches the one
    ///      charged. The vault config is a freeze-safe owner storage read (never a VRF-window value), and
    ///      the whole swap reverts under rngLockedFlag at the entrypoint, so this never runs in the lock.
    /// @param totalBudget The -EV ETH budget the buyer must fund above its floor.
    /// @return buyer The counterparty (sDGNRS, the vault, or address(0) if none can fund).
    function _resolveSalvageBuyer(uint256 totalBudget) internal view returns (address buyer) {
        if (_claimableOf(ContractAddresses.SDGNRS) >= totalBudget + 1 ether) {
            return ContractAddresses.SDGNRS;
        }
        (bool enabled, uint256 vaultFloorWei) = IDegenerusVaultOwner(
            ContractAddresses.VAULT
        ).salvageBuyConfig();
        if (
            enabled &&
            _claimableOf(ContractAddresses.VAULT) +
                _afkingOf(ContractAddresses.VAULT) >=
            totalBudget + vaultFloorWei
        ) {
            return ContractAddresses.VAULT;
        }
        return address(0);
    }

    /// @dev Debit `amount` of a salvage buyer's game-side ETH and book it where solvency stays intact.
    ///      sDGNRS funds purely from its claimable. The vault funds from claimable FIRST, then its prepaid
    ///      afking half (both are claimablePool-backed, so the buyer->seller move is total-preserving and
    ///      leaves claimablePool unchanged). The caller guarantees the resolved buyer covers `amount`.
    function _debitSalvageEth(address buyer, uint256 amount) private {
        if (buyer == ContractAddresses.VAULT) {
            uint256 fromClaimable = _claimableOf(buyer);
            if (fromClaimable >= amount) {
                _debitClaimable(buyer, amount);
                if (amount != 0) emit ClaimableSpent(buyer, amount, fromClaimable - amount, MintPaymentKind.Internal, amount);
            } else {
                _debitClaimableAndAfking(buyer, fromClaimable, amount - fromClaimable);
                if (fromClaimable != 0) emit ClaimableSpent(buyer, fromClaimable, 0, MintPaymentKind.Internal, fromClaimable);
                uint256 afkingPart = amount - fromClaimable;
                if (afkingPart != 0) emit AfkingSpent(buyer, afkingPart);
            }
        } else {
            _debitClaimable(buyer, amount);
            if (amount != 0) emit ClaimableSpent(buyer, amount, _claimableOf(buyer), MintPaymentKind.Internal, amount);
        }
    }

    /// @dev Debit `entries` (owed is in entries, 4 per whole ticket) of the player's far-future tickets
    ///      at level L. On full sell-out (packed == 0) verify the caller-supplied queue index and O(1)
    ///      swap-pop the seller out of ticketQueue[ffk], MAINTAINING `membership <=> packed != 0`
    ///      (so the far-future jackpot samplers need no change and gain no hot-path read). Partial sells
    ///      and sells that leave `rem` do not pop.
    function _removeFarFutureEntries(
        address player,
        uint24 L,
        uint32 entries,
        uint256 idx
    ) internal {
        uint24 ffk = _tqFarFutureKey(L);
        uint40 packed = entriesOwedPacked[ffk][player];
        uint32 owed = uint32(packed >> 8);
        if (owed < entries) revert E(); // ownership / over-sell guard
        uint8 rem = uint8(packed);
        uint32 newOwed = owed - entries;
        if (newOwed == 0 && rem == 0) {
            address[] storage q = ticketQueue[ffk];
            if (q[idx] != player) revert E(); // verify the caller-supplied index
            uint256 lastPos = q.length - 1;
            if (idx != lastPos) q[idx] = q[lastPos];
            q.pop();
            entriesOwedPacked[ffk][player] = 0;
        } else {
            entriesOwedPacked[ffk][player] = (uint40(newOwed) << 8) | uint40(rem);
        }
    }

    /// @dev Single-tx callers: the fresh-ETH portion is `msg.value`. Read here (a private fn)
    ///      so external non-payable callers (e.g. claimable-only paths) never reference msg.value.
    function _purchaseFor(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        ) = _purchaseCostInputs(entryQuantityScaled);
        // Single-tx path: cap fresh ETH at the mint cost and credit any overpay to the
        // payer's withdrawable afking, so excess never reverts or strands. The afking
        // ticket-buy path (purchaseWith) bypasses this, so it is unaffected.
        uint256 cost = ticketCost + lootBoxAmount;
        uint256 fresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < cost ? msg.value : cost);
        if (msg.value > fresh) _creditAfkingValue(msg.sender, msg.value - fresh);
        _purchaseForWithCached(
            buyer,
            entryQuantityScaled,
            lootBoxAmount,
            affiliateCode,
            payKind,
            fresh,
            cachedJpFlag,
            cachedLevel,
            priceWei,
            ticketCost
        );
    }

    /// @dev Phase flag, level, whole-ticket price at the active purchase level, and the
    ///      ticket cost of `entryQuantityScaled` — read and computed once per purchase, then
    ///      threaded into _purchaseForWithCached so no caller recomputes them.
    function _purchaseCostInputs(uint256 entryQuantityScaled)
        private
        view
        returns (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        )
    {
        cachedJpFlag = jackpotPhaseFlag;
        cachedLevel = level;
        // Quote at the SAME level the queue delivers to (_activeTicketLevel), so the
        // final-jackpot-day reroute to level+1 cannot leave the charge / EntriesBought event /
        // affiliate / quest basis mispriced against the tickets actually queued.
        priceWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
        ticketCost = (priceWei * entryQuantityScaled) / (4 * QTY_SCALE);
    }

    function _purchaseForWith(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) private {
        (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        ) = _purchaseCostInputs(entryQuantityScaled);
        _purchaseForWithCached(
            buyer,
            entryQuantityScaled,
            lootBoxAmount,
            affiliateCode,
            payKind,
            ethValue,
            cachedJpFlag,
            cachedLevel,
            priceWei,
            ticketCost
        );
    }

    /// @dev Core purchase body. `cachedJpFlag`/`cachedLevel`/`priceWei`/`ticketCost` are the
    ///      caller's same-frame _purchaseCostInputs snapshot (no external call sits between
    ///      that read and this frame, so the values cannot have changed).
    function _purchaseForWithCached(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        bool cachedJpFlag,
        uint24 cachedLevel,
        uint256 priceWei,
        uint256 ticketCost
    ) private {
        if (_livenessTriggered()) revert E();
        uint256 lootboxFlipCredit;

        if (lootBoxAmount != 0 && lootBoxAmount < LOOTBOX_MIN) revert E();

        uint256 totalCost = ticketCost + lootBoxAmount;
        if (totalCost == 0) revert E();

        // Ticket-leg ETH-in (any funding source). The lootbox leg is carried by LootBoxBuy, so
        // the two events stay disjoint for off-chain ETH-in totals.
        if (ticketCost != 0) emit EntriesBought(buyer, entryQuantityScaled, ticketCost);

        // DirectEth draws no claimable on either leg, so the recycle-bonus basis below is
        // necessarily zero there — the balance snapshot is skipped on that kind.
        uint256 initialClaimable;
        if (payKind != MintPaymentKind.DirectEth) {
            initialClaimable = _claimableOf(buyer);
        }

        // ethValue is the per-slice fresh-ETH portion (== msg.value for single-tx callers; the
        // explicit afking ticket-buy slice routed through purchaseWith from the process STAGE).
        uint256 remainingEth = ethValue;
        uint256 lootboxFreshEth = 0;
        uint256 lootboxClaimableUsed = 0;
        // Lootbox-leg claimable + afking drawn here; folded with the ticket leg's draw into one
        // claimablePool decrement below.
        uint256 lootboxPoolDraw = 0;
        if (lootBoxAmount != 0) {
            // Lootbox payment uses msg.value first; afking covers any shortfall, and
            // claimable too unless the buyer insisted on DirectEth.
            if (remainingEth >= lootBoxAmount) {
                lootboxFreshEth = lootBoxAmount;
                unchecked {
                    remainingEth -= lootBoxAmount;
                }
            } else {
                lootboxFreshEth = remainingEth;
                uint256 shortfall = lootBoxAmount - remainingEth;
                remainingEth = 0;

                // Draw the shortfall from claimable (live balance == the entry snapshot
                // here; the mint leg has not run yet) then afking. afking is fresh-ETH-
                // equivalent for routing; claimable is recycled. DirectEth skips claimable.
                (uint256 cUsed, uint256 aUsed) = _settleShortfallNoPool(
                    buyer,
                    shortfall,
                    payKind != MintPaymentKind.DirectEth
                );
                lootboxFreshEth += aUsed;
                lootboxClaimableUsed = cUsed;
                lootboxPoolDraw = cUsed + aUsed;
            }
        }

        // --- Ticket purchase (returns quest units, defers x00 bonus + ticket queuing) ---
        uint32 flipMintUnits;
        uint32 adjustedQty;
        uint24 targetLevel;
        uint256 ticketFreshFlip;
        uint256 ticketRecycledFlip;
        // Prize-pool shares per leg (ticket here, lootbox below). Each leg keeps its own
        // next/future split; the two sums fold into a single _addPrizeContribution below.
        uint256 ticketNextShare;
        uint256 ticketFutureShare;
        // Ticket-leg claimable + afking drawn; folded with the lootbox draw into one pool RMW.
        uint256 ticketClaimableDraw;
        if (ticketCost != 0) {
            (
                lootboxFlipCredit,
                adjustedQty,
                targetLevel,
                flipMintUnits,
                ticketFreshFlip,
                ticketRecycledFlip,
                ticketNextShare,
                ticketFutureShare,
                ticketClaimableDraw
            ) = _callTicketPurchase(
                    buyer,
                    entryQuantityScaled,
                    payKind,
                    false,
                    remainingEth,
                    cachedJpFlag
                );
        }

        // --- Lootbox setup (pool splits, RNG request, presale/distress tracking) ---
        uint48 lbIndex;
        bool lbFirstDeposit;
        // The box's amount + distress fraction are computed here (score-independent); the EV
        // inputs (adj, score) are computed in the score block below, then all four pack into
        // the single lootboxEth slot in ONE SSTORE. The prior frozen score / adj (for a
        // subsequent deposit) are snapshotted here from the pre-deposit packed word.
        uint256 lbNewAmount;
        uint256 lbDistressUnits;
        uint64 lbPriorAdj;
        uint16 lbPriorScore;
        uint256 lbNextShare;
        uint256 lbFutureShare;
        if (lootBoxAmount != 0) {
            // Lootbox spend joins the minted-units tally (400 units = one ticket-price),
            // combining with the ticket leg so cumulative spend of either kind crosses
            // the whole-ticket participation floor (mint day / streak / quest gate).
            _recordLootboxUnits(buyer, lootBoxAmount);
            // Single SLOAD of the packed slot, written back once below. Nothing in
            // between touches lootboxRngPacked (the queue push writes boxPlayers;
            // the boost consume writes boonPacked only).
            uint256 lrWord = lootboxRngPacked;
            lbIndex = uint48((lrWord >> LR_INDEX_SHIFT) & LR_INDEX_MASK);

            uint256 packed = lootboxEth[lbIndex][buyer];
            uint256 existingAmount = packed & LB_AMOUNT_MASK;
            (, lbPriorAdj, lbPriorScore, ) = _unpackLootbox(packed);

            if (existingAmount == 0) {
                lbFirstDeposit = true;
                // First deposit for this (index, buyer): enqueue the box index for
                // the permissionless box auto-open cursor. The consumer-side
                // walk gates each index on lootboxRngWordByIndex != 0 (VRF
                // orphan-index protection), so enqueue is producer-only here. The
                // per-buy LootBoxBuy event (below) carries the index for off-chain.
                boxPlayers[lbIndex].push(buyer);
            }
            // Subsequent deposits accumulate onto the existing box. No day-coherence gate and no
            // stored day at all: the box binds to lootboxRngWordByIndex[index] and rolls from the
            // LIVE open level, so cross-day deposits at an un-advanced index (only reachable in the
            // pre-first-advance genesis window) are harmless.

            uint256 boostedAmount = _applyLootboxBoostOnPurchase(buyer, lootBoxAmount);
            lbNewAmount = existingAmount + boostedAmount;
            uint256 newPendingEth = ((lrWord >> LR_PENDING_ETH_SHIFT) &
                LR_PENDING_ETH_MASK) + _packEthToMilliEth(lootBoxAmount);
            lootboxRngPacked =
                (lrWord & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)) |
                ((newPendingEth & LR_PENDING_ETH_MASK) << LR_PENDING_ETH_SHIFT);

            bool distress = _isDistressMode();
            // Distress fraction rides in the packed slot at 0.01-ETH granularity. Accumulate
            // the per-deposit units (sub-0.01-ETH residue on the bonus basis is accepted); the
            // existing units come from the box's prior packed word.
            lbDistressUnits = (packed >> LB_DISTRESS_SHIFT) & LB_DISTRESS_MASK;
            if (distress) {
                lbDistressUnits += boostedAmount / LB_DISTRESS_SCALE;
            }
            // Rake-free: ALL lootbox ETH (presale and after) routes 100% to the
            // prize pools. Distress routes 100% next; otherwise 90% future / 10% next.
            uint256 futureBps;
            uint256 nextBps;
            if (distress) {
                futureBps = 0;
                nextBps = 10_000;
            } else {
                futureBps = LOOTBOX_SPLIT_FUTURE_BPS;
                nextBps = LOOTBOX_SPLIT_NEXT_BPS;
            }

            // Each leg's split is held in locals; the combined pool RMW runs once below.
            lbFutureShare = (lootBoxAmount * futureBps) / 10_000;
            lbNextShare = (lootBoxAmount * nextBps) / 10_000;

            emit LootBoxBuy(buyer, lbIndex, lootBoxAmount);
        }

        // --- One combined prize-pool RMW for both legs ---
        // Each leg's next/future split was computed above (ticket inside _callTicketPurchase,
        // lootbox in the block above); summing the post-split totals lands both in a single
        // packed write. This runs before the quest-handler / affiliate calls so no
        // observer ever sees a half-applied contribution, and prizePoolFrozen never flips
        // mid-purchase, so both legs route to the same accumulator.
        _addPrizeContribution(
            uint128(ticketNextShare + lbNextShare),
            uint128(ticketFutureShare + lbFutureShare)
        );

        // --- One combined claimablePool decrement for both legs ---
        // Each leg already debited the buyer's per-player claimable/afking balance (the lootbox
        // shortfall settle above and _processMintPayment inside _callTicketPurchase); their pool
        // draws fold into a single decrement here, before the quest handler / affiliate calls. The
        // only external interactions in this deferral window are the boon-consume delegatecall
        // (reads no claimablePool, makes no reentrant call) and a read-only affiliate staticcall,
        // so no observer ever sees a half-applied pool, and the solvency identity holds at every
        // tx boundary.
        uint256 totalClaimableDraw = ticketClaimableDraw + lootboxPoolDraw;
        if (totalClaimableDraw != 0) {
            claimablePool -= uint128(totalClaimableDraw);
        }

        // --- Single quest handler call (post-action: handlers execute before score) ---
        // MINT_ETH quest progress is credited 1:1 in wei on the gross ETH-denominated
        // ticket + lootbox spend (totalCost), regardless of fresh-vs-recycled funding source.
        uint32 questStreak;
        {
            (
                uint256 questReward,
                uint8 questType,
                uint32 streak,
                bool questCompleted
            ) = quests.handlePurchase(
                    buyer,
                    totalCost,
                    flipMintUnits,
                    lootBoxAmount,
                    priceWei,
                    // During the purchase phase the purchase level IS cachedLevel + 1,
                    // so priceWei already equals priceForLevel(cachedLevel + 1); only
                    // jackpot-phase buys need the lookup.
                    cachedJpFlag
                        ? PriceLookupLib.priceForLevel(cachedLevel + 1)
                        : priceWei
                );
            // Unified score: a live afking sub reads the Sub-side streak (the run's funded days +
            // in-run secondaries, reflecting any secondary just completed by this buy); a non-afker
            // uses the streak the handler returned (no second quest STATICCALL).
            (bool afkLive, uint32 afkStreak) = _liveAfkingStreak(buyer);
            questStreak = afkLive ? afkStreak : streak;
            if (questCompleted) {
                lootboxFlipCredit += questReward;
                // Every purchase carries ETH spend (totalCost != 0 enforced at entry).
                if (questType == 1) {
                    _recordMintStreakForLevel(buyer, _activeTicketLevel());
                }
            }
        }

        // --- Cure: any buy worth >= 1 ticket clears the cashout/smite curse, so the curing
        //     buy already scores un-penalized (cleared before the score read below). ---
        if (totalCost >= priceWei) {
            _clearCurse(buyer);
        }

        // --- Compute score ONCE (post-action). Only the x00 century bonus and the lootbox
        //     EV/taper consume it, so a ticket-only non-x00 buy skips the score and its
        //     affiliate staticcall entirely. ---
        uint256 cachedScore;
        if (lootBoxAmount != 0 || targetLevel % 100 == 0) {
            cachedScore = _playerActivityScore(buyer, questStreak);
        }

        // --- x00 century bonus (uses cached post-action score) ---
        if (ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0) {
            uint256 bonusQty = (uint256(adjustedQty) *
                ActivityCurveLib.centuryBps(cachedScore)) /
                ActivityCurveLib.CENTURY_MAX_BPS;
            if (bonusQty != 0) {
                // 20-ETH allowance in the bonus lane's scaled-entry units
                // (4 * QTY_SCALE units = 1 whole ticket = priceWei).
                uint256 maxBonus = (20 ether * 4 * QTY_SCALE) / priceWei;
                uint256 used = _centuryUsedFor(buyer, targetLevel);
                uint256 remaining = maxBonus > used ? maxBonus - used : 0;
                if (bonusQty > remaining) bonusQty = remaining;
                if (bonusQty != 0) {
                    _setCenturyUsedFor(buyer, targetLevel, used + bonusQty);
                    adjustedQty += uint32(bonusQty);
                }
            }
        }

        // --- Queue tickets ---
        if (adjustedQty != 0) {
            _queueEntriesScaled(buyer, targetLevel, adjustedQty, false);
        }

        // --- Lootbox EV score write (uses cached score). Affiliate legs are settled below by the
        //     single combined call, alongside the ticket legs. ---
        if (lootBoxAmount != 0) {
            // Purchase-time EV-cap tally. The box's multiplier is frozen from the
            // first-deposit score snapshot; the cap key is cachedLevel + 1 (the lootbox
            // open level == the resolver's currentLevel = level + 1). Bonus boxes
            // (mult > NEUTRAL) draw add = min(deposit, CAP - used) from the shared
            // per-(player, level) accumulator and accumulate adjustedPortion; sub-neutral/
            // neutral boxes draw zero cap. amount + adj + score + distressUnits then land
            // in the single lootboxEth slot in one SSTORE.
            uint16 lbScore;
            uint64 lbAdj;
            if (lbFirstDeposit) {
                lbScore = uint16(cachedScore);
                uint256 mult = _lootboxEvMultiplierFromScore(cachedScore);
                if (mult > LOOTBOX_EV_NEUTRAL_BPS) {
                    uint256 used = _lootboxEvUsedFor(buyer, cachedLevel + 1);
                    uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                        ? 0
                        : LOOTBOX_EV_BENEFIT_CAP - used;
                    uint256 add = lootBoxAmount < remaining ? lootBoxAmount : remaining;
                    if (add != 0) {
                        _setLootboxEvUsedFor(buyer, cachedLevel + 1, used + add);
                        lbAdj = uint64(add);
                    }
                }
            } else {
                // Subsequent deposit: the frozen score and accumulated adj come from the
                // box's PRIOR packed word (snapshotted above), the multiplier stays frozen
                // from the first-deposit snapshot.
                lbScore = lbPriorScore;
                lbAdj = lbPriorAdj;
                if (lootBoxAmount != 0) {
                    uint256 mult = _lootboxEvMultiplierFromScore(
                        uint256(lbPriorScore)
                    );
                    if (mult > LOOTBOX_EV_NEUTRAL_BPS) {
                        uint256 used = _lootboxEvUsedFor(buyer, cachedLevel + 1);
                        uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                            ? 0
                            : LOOTBOX_EV_BENEFIT_CAP - used;
                        uint256 add = lootBoxAmount < remaining ? lootBoxAmount : remaining;
                        if (add != 0) {
                            _setLootboxEvUsedFor(buyer, cachedLevel + 1, used + add);
                            lbAdj = lbPriorAdj + uint64(add);
                        }
                    }
                }
            }
            lootboxEth[lbIndex][buyer] =
                _packLootbox(lbNewAmount, lbAdj, lbScore, lbDistressUnits);
        }

        // Settle all affiliate legs (ticket + lootbox, fresh + recycled) in ONE call. The kickback
        // joins the buyer's flip credit; the rolled winner credit is returned and paired below.
        // Runs unconditionally — every purchase carries ETH spend (totalCost != 0 enforced at
        // entry); affiliate scores freeze at level + 1.
        address affWinner;
        uint256 affWinnerCredit;
        {
            uint256 lbFreshFlip = lootboxFreshEth != 0
                ? _ethToFlipValue(lootboxFreshEth, priceWei)
                : 0;
            uint256 lbRecycledFlip = lootboxClaimableUsed != 0
                ? _ethToFlipValue(lootboxClaimableUsed, priceWei)
                : 0;
            uint256 affKickback;
            (affWinner, affWinnerCredit, affKickback) = affiliate.payAffiliateCombined(
                affiliateCode,
                buyer,
                cachedLevel + 1,
                ticketFreshFlip,
                ticketRecycledFlip,
                lbFreshFlip,
                lbRecycledFlip,
                uint16(cachedScore)
            );
            lootboxFlipCredit += affKickback;
        }

        // Coin-presale-box credit accrual: while the box presale is open, every ETH
        // ticket + lootbox spend (fresh + recycled) earns 25% spendable box credit.
        // Covers the afking ticket buy, which routes through this path.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += totalCost / 4;
        }

        // Recycle bonus: spending at least 3 whole tickets' worth of claimable
        // winnings (priceWei is the per-whole-ticket cost) earns 10% of the
        // recycled value back as FLIP flip credit, regardless of any remaining
        // claimable balance. DirectEth draws no claimable on either leg, so the
        // basis is necessarily zero there and the balance read is skipped.
        if (payKind != MintPaymentKind.DirectEth) {
            uint256 finalClaimable = _claimableOf(buyer);
            uint256 totalClaimableUsed = initialClaimable > finalClaimable
                ? initialClaimable - finalClaimable
                : 0;
            if (totalClaimableUsed >= priceWei * 3) {
                lootboxFlipCredit +=
                    (totalClaimableUsed * PRICE_COIN_UNIT) /
                    (priceWei * 10);
            }
        }

        // One Coinflip write for the buyer credit + the rolled affiliate winner. winner != buyer
        // (winner == sender credits nothing), so no slot collision; the pair call skips zero legs.
        if (lootboxFlipCredit != 0 || affWinnerCredit != 0) {
            coinflip.creditFlipPair(
                buyer,
                lootboxFlipCredit,
                affWinner,
                affWinnerCredit
            );
        }
    }

    /// @notice Buy a credit-gated coin-presale box (standalone), funded by msg.value
    ///         plus an optional claimable shortfall.
    /// @dev The box queues at the current lootbox RNG index and resolves off the
    ///      committed word later (RNG-freeze discipline). Reverts once presaleOver.
    /// @param buyer Player receiving the box (already operator-resolved by the entrypoint).
    /// @param boxAmount Requested box ETH (>= PRESALE_BOX_MIN, checked pre-clamp).
    function buyPresaleBox(address buyer, uint256 boxAmount) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value against empty local state.
        if (address(this) != ContractAddresses.GAME) revert E();
        _buyPresaleBoxFor(buyer, boxAmount, msg.value);
    }

    /// @notice Buy tickets/lootbox (earning 25% presale-box credit) AND a presale box
    ///         in one call, sharing one RNG index. The mint leg is funded by msg.value;
    ///         the box leg is funded from the caller's claimable (a ledger move,
    ///         covered by the just-earned + banked credit gate).
    /// @param buyer Player receiving both legs (already operator-resolved by the entrypoint).
    /// @param entryQuantityScaled Tickets to buy (0 to skip).
    /// @param lootBoxAmount ETH lootbox spend (0 to skip).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (>= PRESALE_BOX_MIN, claimable-funded).
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external payable {
        // Split msg.value across both legs so the box accepts the same funding mix as
        // every other purchase. The mint leg takes fresh ETH up to its own cost — capped
        // so the Combined/DirectEth payment guards never revert on or strand overpay;
        // the remainder funds the box as fresh ETH, with claimable/afking covering any
        // box shortfall. Claimable payKind sends no fresh ETH to the mint leg, leaving
        // all of msg.value for the box.
        (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        ) = _purchaseCostInputs(entryQuantityScaled);
        uint256 mintCost = ticketCost + lootBoxAmount;
        uint256 mintFresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < mintCost ? msg.value : mintCost);
        // Mint leg first: accrues the 25% presale-box credit that gates the box below.
        _purchaseForWithCached(
            buyer,
            entryQuantityScaled,
            lootBoxAmount,
            affiliateCode,
            payKind,
            mintFresh,
            cachedJpFlag,
            cachedLevel,
            priceWei,
            ticketCost
        );
        // Box leg gets the leftover fresh ETH; it queues at the SAME current LR_INDEX as
        // the mint leg's lootbox (LR_INDEX does not advance mid-tx), so both share one
        // index for co-resolution.
        _buyPresaleBoxFor(buyer, boxAmount, msg.value - mintFresh);
    }

    /// @dev Core credit-gated presale-box buy: clamp-to-50 close, 1:1 credit consume,
    ///      msg.value + claimable-shortfall payment, 80/20 ETH routing via
    ///      _creditBoxProceeds, queue-at-index, last-buyer latch.
    /// @param buyer Player receiving the box.
    /// @param boxAmount Requested box ETH (the MIN floor + no-overpay checks key on this).
    /// @param valueForBox The fresh-ETH (msg.value) portion available to fund the box.
    function _buyPresaleBoxFor(
        address buyer,
        uint256 boxAmount,
        uint256 valueForBox
    ) private {
        if (presaleOver) revert E();
        if (_livenessTriggered()) revert E();
        // MIN floor on the REQUESTED amount, BEFORE the exactly-50 clamp, so a
        // sub-floor gap to the 50-ETH cap can never lock the close.
        if (boxAmount < PRESALE_BOX_MIN) revert E();
        // Overpay vs the requested amount is credited to the payer's afking, not reverted.
        if (valueForBox > boxAmount) {
            _creditAfkingValue(msg.sender, valueForBox - boxAmount);
            valueForBox = boxAmount;
        }

        uint256 sold = presaleBoxEthSold;
        uint256 remaining = PRESALE_BOX_ETH_CAP - sold; // sold <= cap by construction
        if (remaining == 0) revert E(); // sold out

        // Clamp the crossing box to land cumulative box-ETH at exactly 50.
        uint256 applied = boxAmount > remaining ? remaining : boxAmount;
        bool closing = applied == remaining;

        // Credit gate: consume spendable presale-box credit 1:1 (no clamp-to-credit;
        // an over-credit request reverts — the caller sizes the box to their credit).
        if (applied > presaleBoxCredit[buyer]) revert E();
        unchecked {
            presaleBoxCredit[buyer] -= applied;
        }

        // Payment: msg.value first (capped at the applied amount; clamp excess -> afking),
        // claimable shortfall for the rest (STRICT 1-wei sentinel preserved).
        uint256 freshUsed = valueForBox > applied ? applied : valueForBox;
        uint256 refund = valueForBox - freshUsed;
        uint256 shortfall = applied - freshUsed;
        _settleShortfall(buyer, shortfall, true);

        // 80/20 routing: claimablePool += applied; VAULT 80% + SDGNRS 20% claimable.
        // The claimable-funded portion (shortfall) nets pool delta 0 (debited above,
        // re-credited here); the fresh-ETH portion bumps the pool by that ETH.
        _creditBoxProceeds(applied);

        // Queue at the current lootbox RNG index (shared with a same-tx mint lootbox).
        // The word for the current index is uncommitted until the index advances, so
        // the box is always queued pre-entropy (RNG freeze).
        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (index == 0) revert E();
        if (lootboxRngWordByIndex[index] != 0) revert E();
        // One box per (index, player): the buy-time cumulative position (sold) is
        // frozen into the record for the DGNRS-tier roll, so accumulation would make
        // that snapshot ambiguous. Open this box (or wait for the next index) first.
        if (presaleBoxEth[index][buyer] != 0) revert E();

        // Pack: [bit 255: closing][bits 96:191: soldBefore][bits 0:95: applied].
        // soldBefore (cumulative box ETH before this buy) freezes the 5-tier DGNRS
        // curve input so the resolution reads no mutable SLOAD (RNG freeze).
        presaleBoxEth[index][buyer] =
            uint256(uint96(applied)) |
            (uint256(uint96(sold)) << PRESALE_BOX_SOLD_SHIFT) |
            (closing ? PRESALE_BOX_CLOSING_FLAG : 0);
        // First box deposit at this index: enqueue for the permissionless auto-open.
        boxPlayers[index].push(buyer);

        presaleBoxEthSold = uint96(sold + applied);
        if (closing) {
            // Latch the terminal in the crossing buy (stops further credit accrual
            // and box buys). The swept pool remainder is paid at this box's open.
            presaleOver = true;
            // This crossing buy sits at the highest index any presale box can occupy. The sweep
            // flips presaleDrained once it advances past this index (all presale boxes opened),
            // after which the open paths skip the cold presaleBoxEth SLOAD.
            presaleCloseIndex = index;
        }

        emit PresaleBoxBuy(buyer, index, applied, closing);

        // Fresh ETH the clamp-to-50 left unused is credited to the payer's afking, not
        // sent back via a value call (no reentrancy surface, consistent with overpay).
        _creditAfkingValue(msg.sender, refund);
    }

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Execute ticket purchase: payment, boost, affiliate routing, quest unit accumulation.
    ///      x00 century bonus and ticket queuing are handled by _purchaseFor after score computation.
    /// @return bonusCredit Bulk/recycle bonus flip credit (affiliate kickback is added by the caller)
    /// @return adjustedQty32 Adjusted ticket quantity (with boost, without x00 bonus)
    /// @return targetLevel The level tickets are queued to
    /// @return flipMintUnits FLIP-paid mint quest units
    /// @return ticketFreshFlip Ticket fresh-rate FLIP basis for the caller's combined affiliate call
    /// @return ticketRecycledFlip Ticket recycled-rate FLIP basis for the caller's combined affiliate call
    function _callTicketPurchase(
        address buyer,
        uint256 quantity,
        MintPaymentKind payKind,
        bool payInCoin,
        uint256 value,
        bool cachedJpFlag
    )
        private
        returns (
            uint256 bonusCredit,
            uint32 adjustedQty32,
            uint24 targetLevel,
            uint32 flipMintUnits,
            uint256 ticketFreshFlip,
            uint256 ticketRecycledFlip,
            uint256 ticketNextShare,
            uint256 ticketFutureShare,
            uint256 ticketClaimableDraw
        )
    {
        if (quantity == 0) revert E();
        // Liveness is gated by both callers (_purchaseForWithCached / _redeemFlipFor)
        // before any state is touched, so it is not re-evaluated here.
        // compressedJackpotFlag / jackpotCounter are consumed only on jackpot-phase
        // buys (every use below is short-circuit-gated on cachedJpFlag), so the
        // slot-0 reads are skipped during the purchase phase. nextStep mirrors the
        // JackpotModule step size for the level's remaining daily jackpots.
        uint8 cachedComp;
        uint8 cachedCnt;
        uint8 nextStep = 1;
        if (cachedJpFlag) {
            cachedComp = compressedJackpotFlag;
            cachedCnt = jackpotCounter;
            if (
                cachedComp == 1 &&
                cachedCnt > 0 &&
                cachedCnt < JACKPOT_LEVEL_CAP - 1
            ) {
                nextStep = 2;
            }
        }
        // Single source of truth shared with the purchase quote (so charge == award) and the
        // foil delivery. Routes to level+1 on the final jackpot day's RNG request to prevent
        // tickets stranded in a level whose draws have ended (_endPhase breaks before _unlockRng).
        targetLevel = _activeTicketLevel();
        uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
        uint256 costWei = (priceWei * quantity) / (4 * QTY_SCALE);
        if (costWei == 0) revert E();
        if (costWei < TICKET_MIN_BUYIN_WEI) revert E();

        uint256 adjustedQuantity = quantity;
        if (!payInCoin) {
            // Nested delegatecall straight into the boon module (this frame already
            // runs in the Game's storage context), skipping the external self-call
            // round trip through the Game dispatcher.
            (bool boostOk, bytes memory boostData) = ContractAddresses
                .GAME_BOON_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameBoonModule.consumePurchaseBoost.selector,
                        buyer
                    )
                );
            if (!boostOk) _revertDelegate(boostData);
            uint16 boostBps = abi.decode(boostData, (uint16));
            if (boostBps != 0) {
                uint256 cappedValue = costWei > LOOTBOX_BOOST_MAX_VALUE
                    ? LOOTBOX_BOOST_MAX_VALUE
                    : costWei;
                uint256 cappedQty = priceWei == 0
                    ? 0
                    : ((cappedValue * 4 * QTY_SCALE) / priceWei);
                adjustedQuantity += (cappedQty * boostBps) / 10_000;
            }
        }
        adjustedQty32 = uint32(adjustedQuantity);

        if (payInCoin) {
            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) /
                QTY_SCALE;
            _coinReceive(buyer, coinCost);

            // MINT_FLIP quest units (the reward is credited by the caller).
            uint32 questQty = uint32(quantity / (4 * QTY_SCALE));
            if (questQty != 0) {
                flipMintUnits += questQty;
            }
        } else {
            uint32 mintUnits = adjustedQty32;

            // DirectEth never draws claimable, so freshEth == costWei with no balance
            // reads; the other kinds snapshot the balance around the payment call to
            // measure the claimable draw.
            uint256 claimableBefore;
            if (payKind != MintPaymentKind.DirectEth) {
                claimableBefore = _claimableOf(buyer);
            }
            // Direct internal payment processing — `value` is the exact ETH this leg carries
            // (what the former value-bearing self-call re-scoped into its msg.value). The
            // prize-pool shares are returned, not written, so the caller folds the ticket and
            // lootbox legs into one pool RMW.
            (
                ticketNextShare,
                ticketFutureShare,
                ticketClaimableDraw
            ) = _recordMintPayment(buyer, costWei, payKind, value);
            // Mint-data recording runs after the payment processing, before the freshEth
            // read (it touches neither claimable nor pool state either way).
            _recordMintData(buyer, targetLevel, mintUnits);

            // Fresh ETH for the affiliate split = ticket cost minus the recycled claimable
            // portion the payment just drew; the afking-drawn portion counts as fresh (own
            // principal -> fresh-rate affiliate, including the lootbox activity score). Pay-kind
            // validation already ran inside the payment processing.
            uint256 freshEth = payKind == MintPaymentKind.DirectEth
                ? costWei
                : costWei - (claimableBefore - _claimableOf(buyer));

            // Day before final jackpot draw (not turbo): +100 FLIP per ticket for affiliates
            // Basis inflated by 7/5 (lvl 0-3, 25% rate) or 3/2 (lvl 4+, 20% rate) to yield +100 after scaling
            uint256 freshFlip = freshEth != 0
                ? _ethToFlipValue(freshEth, priceWei)
                : 0;
            if (freshFlip != 0 && cachedJpFlag && cachedComp != 2) {
                if (cachedCnt + nextStep >= JACKPOT_LEVEL_CAP) {
                    freshFlip = targetLevel <= 3
                        ? (freshFlip * 7) / 5
                        : (freshFlip * 3) / 2;
                }
            }

            // Affiliate is settled ONCE for the whole buy by the caller (payAffiliateCombined),
            // which needs this leg's fresh + recycled FLIP components. Fresh = the fresh-rate
            // basis (afking-drawn principal counts as fresh, already folded into freshFlip);
            // recycled = the claimable portion (costWei - freshEth) at the recycled rate. The
            // per-payKind split collapses to (freshFlip, recycledEth): DirectEth has no recycled
            // (recycledEth == 0); Combined/Claimable carry the claimable draw.
            uint256 recycledEth = costWei - freshEth;
            ticketFreshFlip = freshFlip;
            ticketRecycledFlip = recycledEth != 0
                ? _ethToFlipValue(recycledEth, priceWei)
                : 0;

            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) /
                QTY_SCALE;
            bonusCredit = coinCost / 10;
            if (quantity >= 10 * 4 * QTY_SCALE) {
                bonusCredit +=
                    (quantity * PRICE_COIN_UNIT) /
                    (80 * QTY_SCALE);
            }
        }
    }

    function _coinReceive(address payer, uint256 amount) private {
        coin.burnCoin(payer, amount);
    }

    /// @dev Convert ETH-denominated spend to FLIP base units at current ticket price.
    function _ethToFlipValue(
        uint256 amountWei,
        uint256 priceWei
    ) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }

    /// @dev Calculate boost amount given base amount and bonus bps
    function _calculateBoost(
        uint256 amount,
        uint16 bonusBps
    ) private pure returns (uint256) {
        uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE
            ? LOOTBOX_BOOST_MAX_VALUE
            : amount;
        unchecked {
            return (cappedAmount * bonusBps) / 10_000;
        }
    }

    function _applyLootboxBoostOnPurchase(
        address player,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return boostedAmount;

        // The purchase day (== the buy is happening now) — read here, only on the boost path.
        uint24 day = _simulatedDayIndex();
        // Deity-granted boosts are valid only on the grant day.
        uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
        if (deityDay != 0 && deityDay != day) {
            bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
            return boostedAmount;
        }
        // Check expiry
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (
            stampDay != 0 && day > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS
        ) {
            // Expired: clear lootbox fields
            bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
            return boostedAmount;
        }

        // Apply boost
        uint16 boostBps = _lootboxTierToBps(tier);
        boostedAmount += _calculateBoost(amount, boostBps);

        // Clear lootbox fields (consumed)
        bp.slot0 = s0 & BP_LOOTBOX_CLEAR;

        emit BoostUsed(player, day, amount, boostedAmount, boostBps);
    }
}