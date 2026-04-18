// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "../interfaces/IBurnieCoinflip.sol";
import {
    IDegenerusGame,
    MintPaymentKind
} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";

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
 * - `recordMintData`: Track per-player mint history and update Activity Score metrics
 *
 * ## Activity Score System
 *
 * Player engagement is tracked through multiple loyalty metrics:
 * - **Level Count**: Total levels minted (lifetime participation)
 * - **Level Streak**: Consecutive level purchases
 * - **Quest Streak**: Daily quest completion streak (tracked in DegenerusQuests)
 * - **Affiliate Points**: Referral program bonus points (tracked in DegenerusAffiliate)
 * - **Whale Bundle**: Active bundle type (10-lvl or 100-lvl)
 *
 * ### Mint Data Bit Packing Layout (mintPacked_):
 *
 * ```
 * Bits 0-23:    lastLevel          - Last level with ETH mint
 * Bits 24-47:   levelCount         - Total levels minted (lifetime) [Activity Score]
 * Bits 48-71:   levelStreak        - Consecutive levels minted [Activity Score]
 * Bits 72-103:  lastMintDay        - Day index of last mint
 * Bits 104-127: unitsLevel         - Level index for levelUnits tracking
 * Bits 128-151: frozenUntilLevel   - Whale bundle: freeze stats until this level (0 = not frozen)
 * Bits 152-153: whaleBundleType    - Active bundle type (0=none, 1=10-lvl, 3=100-lvl) [Activity Score]
 * Bits 154-159: (unused)
 * Bits 160-183: mintStreakLast      - Last level credited for mint streak
 * Bit  184:     hasDeityPass        - Deity pass flag
 * Bits 185-208: affBonusLevel       - Cached affiliate bonus level
 * Bits 209-214: affBonusPoints      - Cached affiliate bonus points (0-50)
 * Bits 215-227: (unused)
 * Bits 228-243: levelUnits         - Units minted this level
 * Bit 244:      (deprecated)       - Previously used for bonus tracking
 * ```
 *
 * Note: Quest Streak is tracked in DegenerusQuests.questPlayerState.
 * Affiliate Points are tracked in DegenerusAffiliate and cached in mintPacked_ bits 185-214 on level transitions.
 *
 * ## Trait Generation
 *
 * Traits are deterministically derived from tokenId via keccak256:
 * - Each token has 4 traits (one per quadrant: 0-63, 64-127, 128-191, 192-255)
 * - Uses 8×8 weighted grid for non-uniform distribution
 * - Higher-numbered sub-traits within each category are slightly rarer
 */
contract DegenerusGameMintModule is DegenerusGameMintStreakUtils {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
    /// @notice BURNIE ticket purchases are blocked when drip projection cannot cover nextPool deficit.
    error GameOverPossible();

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
    /// @dev BURNIE loot box minimum purchase amount.
    uint256 private constant BURNIE_LOOTBOX_MIN = 1000 ether;
    /// @dev Absolute minimum ticket buy-in (ETH equivalent).
    uint256 private constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;

    /// @dev Lootbox boost amounts applied to the next lootbox purchase.
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500;
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500;
    uint16 private constant LOOTBOX_BOOST_25_BONUS_BPS = 2500;
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether;
    uint32 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;

    /// @dev Loot box pool split: 90% future, 10% next.
    uint16 private constant LOOTBOX_SPLIT_FUTURE_BPS = 9000;
    uint16 private constant LOOTBOX_SPLIT_NEXT_BPS = 1000;

    /// @dev Loot box presale pool split: 50% future, 30% next, 20% vault.
    uint16 private constant LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 5000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_NEXT_BPS = 3000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_VAULT_BPS = 2000;

    /// @dev Number of daily jackpots per level (must match AdvanceModule).
    uint8 private constant JACKPOT_LEVEL_CAP = 5;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LootBoxBuy(
        address indexed buyer,
        uint32 indexed day,
        uint256 amount,
        bool presale,
        uint24 level
    );
    event LootBoxIdx(
        address indexed buyer,
        uint32 indexed index,
        uint32 indexed day
    );
    event BurnieLootBuy(
        address indexed buyer,
        uint32 indexed index,
        uint256 burnieAmount
    );
    event BoostUsed(
        address indexed player,
        uint32 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    // -------------------------------------------------------------------------
    // Mint Data Recording
    // -------------------------------------------------------------------------

    /**
     * @notice Record mint metadata and update Activity Score metrics.
     * @dev Called via delegatecall from DegenerusGame during recordMint().
     *      Updates the player's Activity Score metrics for tracking engagement.
     *
     * @param player Address of the player making the purchase.
     * @param lvl Target level for this purchase (level+1 during purchase phase, level during jackpot phase).
     * @param mintUnits Scaled ticket units purchased.
     *
     * ## Activity Score State Updates
     *
     * - `mintPacked_[player]` updated with level count, units, frozen-flag clearance, and affiliate bonus cache
     * - Only writes to storage if data actually changed
     *
     * ## Level Transition Logic
     *
     * - Same level: Just update units
     * - New level with <4 units: Only track units, don't count as "minted"
     * - New level with ≥4 units: Update level count total and refresh affiliate bonus cache
     */
    function recordMintData(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) external payable {
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
        // Early exit: New level with <4 units (not counted as "minted")
        // ---------------------------------------------------------------------

        if (!sameLevel && levelUnitsAfter < 4) {
            // Just update units, don't update level/streak/total
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
            }
            return;
        }

        // ---------------------------------------------------------------------
        // Update mint day
        // ---------------------------------------------------------------------

        uint32 day = _currentMintDay();
        data = _setMintDay(
            prevData,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
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
            }
            return;
        }

        // ---------------------------------------------------------------------
        // New level with ≥4 units: Full state update
        // ---------------------------------------------------------------------

        // Check for whale bundle frozen state
        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        bool isFrozen = frozenUntilLevel > 0 && lvl < frozenUntilLevel;

        // If frozen, skip updating total (it's pre-set by whale bundle)
        // If we've reached the frozen level, clear the flag and resume normal tracking
        if (frozenUntilLevel > 0 && lvl >= frozenUntilLevel) {
            // Clear frozen flag and whale bundle type - resume normal tracking from here
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT,
                BitPackingLib.MASK_24,
                0
            );
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT,
                3,
                0
            ); // Clear bundle type
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

        // Cache affiliate bonus for activity score (piggybacks on existing SSTORE)
        {
            uint256 affPoints = affiliate.affiliateBonusPointsBest(lvl, player);
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT,
                BitPackingLib.MASK_24,
                lvl
            );
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT,
                BitPackingLib.MASK_6,
                affPoints
            );
        }

        // ---------------------------------------------------------------------
        // Commit to storage (only if changed)
        // ---------------------------------------------------------------------

        if (data != prevData) {
            mintPacked_[player] = data;
        }
        return;
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
            delete ticketQueue[rk];
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

        while (idx < total && used < writesBudget) {
            address player = queue[idx];
            uint256 baseKey = (uint256(lvl) << 224) |
                (idx << 192) |
                (uint256(uint160(player)) << 32);
            uint40 packed = ticketsOwedPacked[rk][player];
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            if (owed == 0) {
                if (rem == 0) {
                    if (packed != 0) {
                        ticketsOwedPacked[rk][player] = 0;
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
                    ticketsOwedPacked[rk][player] = 0;
                    unchecked {
                        ++idx;
                        ++used;
                    }
                    processed = 0;
                    continue;
                }
                uint40 rolledPacked = uint40(1) << 8;
                if (rolledPacked != packed) {
                    ticketsOwedPacked[rk][player] = rolledPacked;
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
            if (take == 0) break;

            _raritySymbolBatch(player, baseKey, processed, take, entropy);
            emit TraitsGenerated(
                player,
                lvl,
                uint32(idx),
                processed,
                take,
                entropy
            );

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
                ticketsOwedPacked[rk][player] = newPacked;
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
        ticketCursor = uint32(idx);
        finished = (idx >= total);
        if (finished) {
            delete ticketQueue[rk];
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
        }
    }

    /// @dev Generates trait tickets in batch for a player's ticket awards using LCG-based PRNG.
    ///      Uses inline assembly for gas-efficient bulk storage writes.
    /// @param player Address receiving the trait tickets.
    /// @param baseKey Encoded key containing level, index, and player address.
    /// @param startIndex Starting position within this player's owed tickets.
    /// @param count Number of ticket entries to process this batch.
    /// @param entropyWord VRF entropy for trait generation.
    function _raritySymbolBatch(
        address player,
        uint256 baseKey,
        uint32 startIndex,
        uint32 count,
        uint256 entropyWord
    ) private {
        // Memory arrays to track which traits were generated and how many times.
        uint32[256] memory counts;
        uint8[256] memory touchedTraits;
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
        // Layout assumption: traitBurnTicket is mapping(uint24 => address[256]).
        // Solidity stores mapping(key => fixedArray) as keccak256(key . slot) + index,
        // with dynamic array elements at keccak256(keccak256(key . slot) + index).
        // This relies on the standard Solidity storage layout (stable since 0.4.x).
        // Safe here because the contract is non-upgradeable.
        uint256 levelSlot;
        assembly ("memory-safe") {
            mstore(0x00, lvl)
            mstore(0x20, traitBurnTicket.slot)
            levelSlot := keccak256(0x00, 0x40)
        }

        // Batch-write trait tickets to storage using assembly for gas efficiency.
        for (uint16 u; u < touchedLen; ) {
            uint8 traitId = touchedTraits[u];
            uint32 occurrences = counts[traitId];

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
        // `% TICKET_SCALE`. XOR + entropyStep's single-iteration xorshift only
        // diffuses bits ~40 positions outward, leaving upper player-address
        // bits invisible to the roll outcome.
        uint256 rollEntropy = EntropyLib.hash2(entropy, rollSalt);
        return (rollEntropy % TICKET_SCALE) < rem;
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
    function processTicketBatch(uint24 lvl) external returns (bool finished) {
        uint24 rk = _tqReadKey(lvl);
        address[] storage queue = ticketQueue[rk];
        uint256 total = queue.length;

        if (ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        if (idx >= total) {
            delete ticketQueue[rk];
            ticketCursor = 0;
            ticketLevel = 0;
            return true;
        }

        uint32 writesBudget = WRITES_BUDGET_SAFE;
        if (idx == 0) {
            writesBudget -= (writesBudget * 35) / 100; // 65% scaling for cold storage
        }

        uint32 used;
        uint256 entropy = lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1];
        uint32 processed;

        while (idx < total && used < writesBudget) {
            (uint32 writesUsed, bool advance) = _processOneTicketEntry(
                queue[idx],
                lvl,
                rk,
                writesBudget - used,
                processed,
                entropy,
                idx
            );
            if (writesUsed == 0 && !advance) break;
            unchecked {
                used += writesUsed;
                if (advance) {
                    ++idx;
                    processed = 0;
                } else {
                    processed += writesUsed >> 1;
                }
            }
        }

        ticketCursor = uint32(idx);

        if (idx >= total) {
            delete ticketQueue[rk];
            ticketCursor = 0;
            ticketLevel = 0;
            return true;
        }
        return false;
    }

    /// @dev Resolves the zero-owed remainder case for ticket processing.
    function _resolveZeroOwedRemainder(
        uint40 packed,
        uint24 rk,
        address player,
        uint256 entropy,
        uint256 rollSalt
    ) private returns (uint40 newPacked, bool skip) {
        uint8 rem = uint8(packed);
        if (rem == 0) {
            if (packed != 0) {
                ticketsOwedPacked[rk][player] = 0;
            }
            return (0, true);
        }

        bool win = _rollRemainder(entropy, rollSalt, rem);
        if (!win) {
            ticketsOwedPacked[rk][player] = 0;
            return (0, true);
        }

        newPacked = uint40(1) << 8;
        if (newPacked != packed) {
            ticketsOwedPacked[rk][player] = newPacked;
        }
        return (newPacked, false);
    }

    /// @dev Processes a single ticket entry, returning writes used and whether to advance.
    function _processOneTicketEntry(
        address player,
        uint24 lvl,
        uint24 rk,
        uint32 room,
        uint32 processed,
        uint256 entropy,
        uint256 queueIdx
    ) private returns (uint32 writesUsed, bool advance) {
        uint40 packed = ticketsOwedPacked[rk][player];
        uint32 owed = uint32(packed >> 8);
        uint256 rollSalt = (uint256(lvl) << 224) |
            (queueIdx << 192) |
            (uint256(uint160(player)) << 32);

        if (owed == 0) {
            bool skip;
            (packed, skip) = _resolveZeroOwedRemainder(
                packed,
                rk,
                player,
                entropy,
                rollSalt
            );
            if (skip) return (1, true);
            owed = 1;
        }

        uint32 baseOv = (processed == 0 && owed <= 2) ? 4 : 2;
        if (room <= baseOv) return (0, false);
        uint32 take;
        {
            uint32 availRoom = room - baseOv;
            uint32 maxT = (availRoom <= 256)
                ? (availRoom >> 1)
                : (availRoom - 256);
            take = owed > maxT ? maxT : owed;
        }
        if (take == 0) return (0, false);

        uint256 baseKey = (uint256(lvl) << 224) |
            (queueIdx << 192) |
            (uint256(uint160(player)) << 32);
        _raritySymbolBatch(player, baseKey, processed, take, entropy);
        emit TraitsGenerated(
            player,
            lvl,
            uint32(queueIdx),
            processed,
            take,
            entropy
        );

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
            if (_rollRemainder(entropy, rollSalt, rem)) {
                remainingOwed = 1;
            }
            rem = 0;
        }
        uint40 newPacked = (uint40(remainingOwed) << 8) | uint40(rem);
        if (newPacked != packed) {
            ticketsOwedPacked[rk][player] = newPacked;
        }
        advance = remainingOwed == 0;
    }

    // -------------------------------------------------------------------------
    // Purchases and Loot Boxes
    // -------------------------------------------------------------------------

    /// @notice Purchase tickets and loot boxes for a buyer.
    /// @dev Delegatecalled by DegenerusGame. Handles payment routing, affiliates, and queues.
    /// @param buyer Recipient of the purchased items.
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100).
    /// @param lootBoxAmount ETH amount for loot boxes.
    /// @param affiliateCode Referral code for affiliate attribution.
    /// @param payKind Payment kind selector (ETH/claimable/combined).
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        _purchaseFor(
            buyer,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind
        );
    }

    /// @notice Purchase tickets and optional BURNIE loot boxes.
    /// @dev BURNIE ticket purchases require RNG unlocked and gameOverPossible=false.
    ///      BURNIE loot boxes require RNG unlocked only.
    /// @param buyer Recipient of the purchased items.
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100).
    /// @param lootBoxBurnieAmount BURNIE amount to burn for loot boxes.
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external {
        _purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount);
    }

    /// @notice Purchase a low-EV loot box with BURNIE.
    /// @dev Uses the current lootbox RNG index; rewards are tickets + small BURNIE only.
    /// @param buyer Recipient of the loot box rewards.
    /// @param burnieAmount BURNIE amount to burn for the loot box.
    function purchaseBurnieLootbox(
        address buyer,
        uint256 burnieAmount
    ) external {
        if (buyer == address(0)) revert E();
        _purchaseBurnieLootboxFor(buyer, burnieAmount);
    }

    function _purchaseCoinFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) private {
        if (gameOver) revert E();

        if (ticketQuantity != 0) {
            // ENF-01: Block BURNIE tickets when drip projection cannot cover nextPool deficit.
            if (gameOverPossible) revert GameOverPossible();
            _callTicketPurchase(
                buyer,
                msg.sender,
                ticketQuantity,
                MintPaymentKind.DirectEth,
                true,
                bytes32(0),
                0,
                level,
                jackpotPhaseFlag
            );
        }

        if (lootBoxBurnieAmount != 0) {
            _purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount);
        }
    }

    function _purchaseFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        if (gameOver) revert E();
        uint256 lootboxFlipCredit;
        bool cachedJpFlag = jackpotPhaseFlag;
        uint24 cachedLevel = level;
        uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;
        uint256 priceWei = PriceLookupLib.priceForLevel(purchaseLevel);

        if (lootBoxAmount != 0 && lootBoxAmount < LOOTBOX_MIN) revert E();

        uint256 ticketCost = 0;

        if (ticketQuantity != 0) {
            ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE);
        }

        uint256 totalCost = ticketCost + lootBoxAmount;
        if (totalCost == 0) revert E();

        uint256 initialClaimable = claimableWinnings[buyer];

        uint256 remainingEth = msg.value;
        uint256 lootboxFreshEth = 0;
        uint256 lootboxClaimableUsed = 0;
        if (lootBoxAmount != 0) {
            // Lootbox payment uses msg.value first; optional claimable shortfall.
            if (remainingEth >= lootBoxAmount) {
                lootboxFreshEth = lootBoxAmount;
                unchecked {
                    remainingEth -= lootBoxAmount;
                }
            } else {
                // Allow claimable to cover lootbox shortfall unless user insisted on DirectEth.
                if (payKind == MintPaymentKind.DirectEth) revert E();
                lootboxFreshEth = remainingEth;
                uint256 shortfall = lootBoxAmount - remainingEth;
                remainingEth = 0;

                uint256 claimable = initialClaimable;
                // Preserve 1 wei sentinel (same as mint payments).
                if (claimable <= shortfall) revert E();
                unchecked {
                    claimableWinnings[buyer] = claimable - shortfall;
                }
                claimablePool -= uint128(shortfall);
                lootboxClaimableUsed = shortfall;
            }
        }

        // --- Ticket purchase (returns quest units, defers x00 bonus + ticket queuing) ---
        uint32 burnieMintUnits;
        uint32 adjustedQty;
        uint24 targetLevel;
        uint256 ticketFreshEth;
        if (ticketCost != 0) {
            (
                lootboxFlipCredit,
                adjustedQty,
                targetLevel,
                burnieMintUnits,
                ticketFreshEth
            ) = _callTicketPurchase(
                    buyer,
                    buyer,
                    ticketQuantity,
                    payKind,
                    false,
                    affiliateCode,
                    remainingEth,
                    cachedLevel,
                    cachedJpFlag
                );
        }

        // --- Lootbox setup (pool splits, RNG request, presale/distress tracking) ---
        uint32 lbDay;
        uint48 lbIndex;
        bool lbFirstDeposit;
        if (lootBoxAmount != 0) {
            lbDay = _simulatedDayIndex();
            lbIndex = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
            bool presale = _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0;

            uint256 packed = lootboxEth[lbIndex][buyer];
            uint256 existingAmount = packed & ((1 << 232) - 1);
            uint32 storedDay = lootboxDay[lbIndex][buyer];

            if (existingAmount == 0) {
                lbFirstDeposit = true;
                lootboxDay[lbIndex][buyer] = lbDay;
                lootboxBaseLevelPacked[lbIndex][buyer] = uint24(
                    cachedLevel + 1
                );
                // lootboxEvScorePacked written after score computation below
                emit LootBoxIdx(buyer, uint32(lbIndex), lbDay);
            } else {
                if (storedDay != lbDay) revert E();
            }

            uint256 boostedAmount = _applyLootboxBoostOnPurchase(
                buyer,
                lbDay,
                lootBoxAmount
            );
            uint256 existingBase = lootboxEthBase[lbIndex][buyer];
            if (existingAmount != 0 && existingBase == 0) {
                existingBase = existingAmount;
            }
            lootboxEthBase[lbIndex][buyer] = existingBase + lootBoxAmount;

            uint256 newAmount = existingAmount + boostedAmount;
            lootboxEth[lbIndex][buyer] =
                (uint256(cachedLevel + 1) << 232) |
                newAmount;
            _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, _lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK) + _packEthToMilliEth(lootBoxAmount));

            if (presale) {
                _psWrite(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK, _psRead(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK) + lootBoxAmount);
            }

            bool distress = _isDistressMode();
            if (distress) {
                lootboxDistressEth[lbIndex][buyer] += boostedAmount;
            }
            uint256 futureBps;
            uint256 nextBps;
            uint256 vaultBps;
            if (distress) {
                futureBps = 0;
                nextBps = 10_000;
                vaultBps = 0;
            } else {
                bool presaleSplit = cachedLevel == 0 &&
                    _getNextPrizePool() <= 50 ether;
                futureBps = presaleSplit
                    ? LOOTBOX_PRESALE_SPLIT_FUTURE_BPS
                    : LOOTBOX_SPLIT_FUTURE_BPS;
                nextBps = presaleSplit
                    ? LOOTBOX_PRESALE_SPLIT_NEXT_BPS
                    : LOOTBOX_SPLIT_NEXT_BPS;
                vaultBps = presaleSplit ? LOOTBOX_PRESALE_SPLIT_VAULT_BPS : 0;
            }

            uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
            uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
            uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;

            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(
                    pNext + uint128(nextShare),
                    pFuture + uint128(futureShare)
                );
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(
                    next + uint128(nextShare),
                    future + uint128(futureShare)
                );
            }
            if (vaultShare != 0) {
                (bool ok, ) = payable(ContractAddresses.VAULT).call{
                    value: vaultShare
                }("");
                if (!ok) revert E();
            }

            emit LootBoxBuy(buyer, lbDay, lootBoxAmount, presale, cachedLevel);
        }

        // --- Single quest handler call (post-action: handlers execute before score) ---
        // MINT_ETH quest progress is credited 1:1 in wei from fresh ETH across both paths
        // (ticket costWei + lootbox fresh ETH). Claimable-funded spend does not count.
        uint256 ethFreshWei = ticketFreshEth + lootboxFreshEth;
        uint32 questStreak;
        {
            (
                uint256 questReward,
                uint8 questType,
                uint32 streak,
                bool questCompleted
            ) = quests.handlePurchase(
                    buyer,
                    ethFreshWei,
                    burnieMintUnits,
                    lootBoxAmount,
                    priceWei,
                    PriceLookupLib.priceForLevel(cachedLevel + 1)
                );
            questStreak = streak;
            if (questCompleted) {
                lootboxFlipCredit += questReward;
                if (ethFreshWei > 0 && questType == 1) {
                    IDegenerusGame(address(this)).recordMintQuestStreak(buyer);
                }
            }
        }

        // --- Compute score ONCE (post-action, per D-08) ---
        uint256 cachedScore = _playerActivityScore(buyer, questStreak);

        // --- x00 century bonus (uses cached post-action score) ---
        if (ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0) {
            uint256 _score = cachedScore > 30_500 ? 30_500 : cachedScore;
            uint256 bonusQty = (uint256(adjustedQty) * _score) / 30_500;
            if (bonusQty != 0) {
                uint256 maxBonus = (20 ether) / (priceWei >> 2);
                uint256 used = centuryBonusLevel == targetLevel
                    ? centuryBonusUsed[buyer]
                    : 0;
                uint256 remaining = maxBonus > used ? maxBonus - used : 0;
                if (bonusQty > remaining) bonusQty = remaining;
                if (bonusQty != 0) {
                    centuryBonusLevel = targetLevel;
                    centuryBonusUsed[buyer] = used + bonusQty;
                    adjustedQty += uint32(bonusQty);
                }
            }
        }

        // --- Queue tickets (moved from _callTicketPurchase) ---
        if (adjustedQty != 0) {
            _queueTicketsScaled(buyer, targetLevel, adjustedQty, false);
        }

        // --- Lootbox affiliate calls + EV score write (uses cached score) ---
        if (lootBoxAmount != 0) {
            if (lootboxFreshEth != 0) {
                lootboxFlipCredit += affiliate.payAffiliate(
                    _ethToBurnieValue(lootboxFreshEth, priceWei),
                    affiliateCode,
                    buyer,
                    cachedLevel + 1,
                    true,
                    uint16(cachedScore)
                );
            }
            if (lootboxClaimableUsed != 0) {
                lootboxFlipCredit += affiliate.payAffiliate(
                    _ethToBurnieValue(lootboxClaimableUsed, priceWei),
                    affiliateCode,
                    buyer,
                    cachedLevel + 1,
                    false,
                    0
                );
            }
            if (lbFirstDeposit) {
                lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1);
            }
        }

        // Unified earlybird award: one call per purchase covering both ticket and lootbox fresh ETH.
        // Mathematically equivalent to two separate calls (quadratic curve telescopes).
        _awardEarlybirdDgnrs(buyer, ticketFreshEth + lootboxFreshEth);

        uint256 finalClaimable = payKind == MintPaymentKind.DirectEth
            ? initialClaimable
            : claimableWinnings[buyer];
        uint256 totalClaimableUsed = initialClaimable > finalClaimable
            ? initialClaimable - finalClaimable
            : 0;
        uint256 availableClaimable = finalClaimable > 1
            ? finalClaimable - 1
            : 0;
        uint256 minTicketUnitCost = priceWei / (4 * TICKET_SCALE);
        bool spentAllClaimable = totalClaimableUsed != 0 &&
            (availableClaimable == 0 ||
                (minTicketUnitCost != 0 &&
                    availableClaimable < minTicketUnitCost));

        if (spentAllClaimable && totalClaimableUsed >= priceWei * 3) {
            lootboxFlipCredit +=
                (totalClaimableUsed * PRICE_COIN_UNIT * 10) /
                (priceWei * 100);
        }

        if (lootboxFlipCredit != 0) {
            coinflip.creditFlip(buyer, lootboxFlipCredit);
        }
    }

    /// @dev Execute ticket purchase: payment, boost, affiliate routing, quest unit accumulation.
    ///      x00 century bonus and ticket queuing are handled by _purchaseFor after score computation.
    /// @return bonusCredit Affiliate kickback + bulk bonus flip credit
    /// @return adjustedQty32 Adjusted ticket quantity (with boost, without x00 bonus)
    /// @return targetLevel The level tickets are queued to
    /// @return burnieMintUnits BURNIE-paid mint quest units
    /// @return freshEth Fresh ETH portion of the ticket payment (0 for payInCoin and Claimable)
    function _callTicketPurchase(
        address buyer,
        address payer,
        uint256 quantity,
        MintPaymentKind payKind,
        bool payInCoin,
        bytes32 affiliateCode,
        uint256 value,
        uint24 cachedLevel,
        bool cachedJpFlag
    )
        private
        returns (
            uint256 bonusCredit,
            uint32 adjustedQty32,
            uint24 targetLevel,
            uint32 burnieMintUnits,
            uint256 freshEth
        )
    {
        if (quantity == 0) revert E();
        if (gameOver) revert E();
        uint8 cachedComp = compressedJackpotFlag;
        uint8 cachedCnt = jackpotCounter;
        targetLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;
        // Last jackpot day fix: route to level+1 to prevent stranded tickets
        // (_endPhase breaks before _unlockRng, so no future daily draw at this level)
        if (cachedJpFlag && rngLockedFlag) {
            uint8 step = cachedComp == 2
                ? JACKPOT_LEVEL_CAP
                : (cachedComp == 1 &&
                    cachedCnt > 0 &&
                    cachedCnt < JACKPOT_LEVEL_CAP - 1)
                    ? 2
                    : 1;
            if (cachedCnt + step >= JACKPOT_LEVEL_CAP)
                targetLevel = cachedLevel + 1;
        }
        // Affiliate scores always route to level + 1 so they freeze at
        // level transition and can be claimed against a fixed snapshot.
        uint24 affiliateLevel = cachedLevel + 1;

        uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
        uint256 costWei = (priceWei * quantity) / (4 * TICKET_SCALE);
        if (costWei == 0) revert E();
        if (costWei < TICKET_MIN_BUYIN_WEI) revert E();

        uint256 adjustedQuantity = quantity;
        if (!payInCoin) {
            uint16 boostBps = IDegenerusGame(address(this))
                .consumePurchaseBoost(payer);
            if (boostBps != 0) {
                uint256 cappedValue = costWei > LOOTBOX_BOOST_MAX_VALUE
                    ? LOOTBOX_BOOST_MAX_VALUE
                    : costWei;
                uint256 cappedQty = priceWei == 0
                    ? 0
                    : ((cappedValue * 4 * TICKET_SCALE) / priceWei);
                adjustedQuantity += (cappedQty * boostBps) / 10_000;
            }
        }
        adjustedQty32 = uint32(adjustedQuantity);

        if (payInCoin) {
            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) /
                TICKET_SCALE;
            _coinReceive(payer, coinCost);

            // Accumulate BURNIE mint quest units (deferred to handlePurchase)
            uint32 questQty = uint32(quantity / (4 * TICKET_SCALE));
            if (questQty != 0) {
                burnieMintUnits += questQty;
            }
        } else {
            uint32 mintUnits = adjustedQty32;

            IDegenerusGame(address(this)).recordMint{value: value}(
                payer,
                targetLevel,
                costWei,
                mintUnits,
                payKind
            );

            if (payKind == MintPaymentKind.DirectEth) {
                if (value < costWei) revert E();
                freshEth = costWei;
            } else if (payKind == MintPaymentKind.Claimable) {
                if (value != 0) revert E();
                freshEth = 0;
            } else if (payKind == MintPaymentKind.Combined) {
                if (value > costWei) revert E();
                freshEth = value;
            } else {
                revert E();
            }

            // Day before final jackpot draw (not turbo): +100 BURNIE per ticket for affiliates
            // Basis inflated by 7/5 (lvl 0-3, 25% rate) or 3/2 (lvl 4+, 20% rate) to yield +100 after scaling
            uint256 freshBurnie = freshEth != 0
                ? _ethToBurnieValue(freshEth, priceWei)
                : 0;
            if (freshBurnie != 0 && cachedJpFlag && cachedComp != 2) {
                // Compute next step size (mirrors JackpotModule logic)
                uint8 _nextStep = (cachedComp == 1 &&
                    cachedCnt > 0 &&
                    cachedCnt < JACKPOT_LEVEL_CAP - 1)
                    ? 2
                    : 1;
                if (cachedCnt + _nextStep >= JACKPOT_LEVEL_CAP) {
                    freshBurnie = targetLevel <= 3
                        ? (freshBurnie * 7) / 5
                        : (freshBurnie * 3) / 2;
                }
            }

            uint256 kickback;
            if (payKind == MintPaymentKind.Combined && freshEth != 0) {
                kickback += affiliate.payAffiliate(
                    freshBurnie,
                    affiliateCode,
                    buyer,
                    affiliateLevel,
                    true,
                    0
                );
                uint256 recycled = costWei - freshEth;
                if (recycled != 0) {
                    kickback += affiliate.payAffiliate(
                        _ethToBurnieValue(recycled, priceWei),
                        affiliateCode,
                        buyer,
                        affiliateLevel,
                        false,
                        0
                    );
                }
            } else if (payKind == MintPaymentKind.DirectEth) {
                kickback += affiliate.payAffiliate(
                    freshBurnie,
                    affiliateCode,
                    buyer,
                    affiliateLevel,
                    true,
                    0
                );
            } else {
                kickback += affiliate.payAffiliate(
                    _ethToBurnieValue(costWei, priceWei),
                    affiliateCode,
                    buyer,
                    affiliateLevel,
                    false,
                    0
                );
            }

            bonusCredit = kickback;
            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) /
                TICKET_SCALE;
            bonusCredit += coinCost / 10;
            if (quantity >= 10 * 4 * TICKET_SCALE) {
                bonusCredit +=
                    (quantity * PRICE_COIN_UNIT) /
                    (40 * TICKET_SCALE);
            }
        }
    }

    function _coinReceive(address payer, uint256 amount) private {
        coin.burnCoin(payer, amount);
    }

    /// @dev Convert ETH-denominated spend to BURNIE base units at current ticket price.
    function _ethToBurnieValue(
        uint256 amountWei,
        uint256 priceWei
    ) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }

    function _purchaseBurnieLootboxFor(
        address buyer,
        uint256 burnieAmount
    ) private {
        if (gameOver) revert E();
        if (burnieAmount < BURNIE_LOOTBOX_MIN) revert E();
        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (index == 0) revert E();

        coin.burnCoin(buyer, burnieAmount);

        {
            uint256 questUnitsRaw = burnieAmount / PRICE_COIN_UNIT;
            if (questUnitsRaw != 0) {
                _questMint(buyer, uint32(questUnitsRaw), false, 0);
            }
        }

        uint256 existingAmount = lootboxBurnie[index][buyer];
        if (lootboxDay[index][buyer] == 0) {
            lootboxDay[index][buyer] = _simulatedDayIndex();
        }
        lootboxBurnie[index][buyer] = existingAmount + burnieAmount;

        _lrWrite(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK, _lrRead(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK) + _packBurnieToWhole(burnieAmount));

        uint256 priceWei = PriceLookupLib.priceForLevel(level + 1);
        if (priceWei != 0) {
            uint256 virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
            if (virtualEth != 0) {
                _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, _lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK) + _packEthToMilliEth(virtualEth));
            }
        }

        emit BurnieLootBuy(buyer, uint32(index), burnieAmount);
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
        uint32 day,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return boostedAmount;

        // Check expiry
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (
            stampDay != 0 && uint24(day) > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS
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

    /// @dev Route quest progress to DegenerusQuests (standalone mint path only).
    ///      ETH mints: returns reward for caller to batch with kickbacks.
    ///      BURNIE mints: reward creditFlipped internally by handler (nothing to batch).
    function _questMint(
        address player,
        uint32 quantity,
        bool paidWithEth,
        uint256 mintPrice
    ) private returns (uint256) {
        (uint256 reward, uint8 questType, , bool completed) = quests.handleMint(
            player,
            quantity,
            paidWithEth,
            mintPrice
        );
        if (completed) {
            if (paidWithEth && questType == 1) {
                IDegenerusGame(address(this)).recordMintQuestStreak(player);
            }
            if (paidWithEth) return reward;
        }
        return 0;
    }
}
