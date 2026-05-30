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
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
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
contract DegenerusGameMintModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
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
    /// @dev Coin-presale-box minimum purchase amount (0.01 ETH). Checked on the
    ///      REQUESTED amount BEFORE the exactly-50-ETH clamp, so a sub-floor gap to
    ///      the 50-ETH cap can never lock the presale close.
    uint256 private constant PRESALE_BOX_MIN = 0.01 ether;
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
        mapping(address => uint40) storage owedMap = ticketsOwedPacked[rk];
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
            if (take == 0) break;

            _raritySymbolBatch(player, baseKey, processed, take, entropy);
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
    /// @param baseKey Encoded key carrying (lvl, queueIdx, player, owed) packed across 256 bits.
    ///                The owed value in the low 32 bits mutates per emission, so multi-call
    ///                drains hash distinct seeds across calls on the same player.
    /// @param startIndex Starting position within this player's owed tickets for this batch.
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
        // `% TICKET_SCALE`. A plain XOR mix only diffuses bits a fixed span
        // outward, leaving upper player-address bits invisible to the roll
        // outcome; keccak gives full low-bit diffusion of the high-bit input.
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
        mapping(address => uint40) storage owedMap = ticketsOwedPacked[rk];
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
            (uint32 writesUsed, uint32 take, bool advance) = _processOneTicketEntry(
                queue[idx],
                lvl,
                owedMap,
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
                    // MINTDIV-02: align with processFutureTicketBatch:502 — advance
                    // the within-player startIndex by the per-iter ticket count, not
                    // by the gas-budget-derived writesUsed>>1 heuristic (which diverged
                    // for take > 256 per 334-MINTDIV01-REACHABILITY-VERDICT).
                    processed += take;
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
        uint256 queueIdx
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
        if (take == 0) return (0, 0, false);

        _raritySymbolBatch(player, baseKey, processed, take, entropy);
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

    /// @notice Afking-batch purchase entry: like `purchase`, but the fresh-ETH portion is an
    ///         explicit `ethValue` parameter rather than `msg.value`. Lets `batchPurchase` run
    ///         many subscriber buys inline in one frame (the contract holds the aggregate ETH),
    ///         instead of one value-bearing self-call per slice. Reached only via the
    ///         AF_KING-gated `batchPurchase` delegatecall.
    function purchaseWith(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) external {
        _purchaseForWith(
            buyer,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind,
            ethValue
        );
    }

    /// @notice Purchase tickets with BURNIE.
    /// @dev BURNIE ticket purchases require RNG unlocked and gameOverPossible=false.
    /// @param buyer Recipient of the purchased tickets.
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100).
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity
    ) external {
        _purchaseCoinFor(buyer, ticketQuantity);
    }

    function _purchaseCoinFor(
        address buyer,
        uint256 ticketQuantity
    ) private {
        if (_livenessTriggered()) revert E();

        if (ticketQuantity != 0) {
            // ENF-01: Block BURNIE tickets when drip projection cannot cover nextPool deficit.
            if (gameOverPossible) revert GameOverPossible();
            _callTicketPurchase(
                buyer,
                ticketQuantity,
                MintPaymentKind.DirectEth,
                true,
                bytes32(0),
                0,
                level,
                jackpotPhaseFlag
            );
        }
    }

    /// @notice Emitted on a far-future salvage swap (sellFarFutureTickets).
    event FarFutureSwap(
        address indexed player,
        uint256 lineCount,
        uint256 totalBudgetWei,
        uint256 ticketWei,
        uint256 cashWei
    );

    /// @notice Sell far-future ticket entries to sDGNRS (current-level tickets + cash; -EV exit).
    /// @dev Delegatecalled from DegenerusGame.sellFarFutureTickets with an already-resolved `player`
    ///      (so no _resolvePlayer here). Mass-sells WHOLE far-future tickets (6 <= d = L - currentLevel
    ///      <= 100) for ONE aggregated current-level mint (a normal recycled Claimable mint) + a cash
    ///      residual, funded fail-closed from claimableWinnings[SDGNRS] to a >=1 ETH floor (no
    ///      pendingRedemptionEthValue term, no daily cap). Valuation + daily jitter are shared with the
    ///      preview via _quoteFarFutureSwap. The fully-liquidated seller is swap-popped from ticketQueue
    ///      (membership <=> packed != 0 maintained; far-future jackpot samplers unchanged).
    /// @custom:reverts E On bad input/distance/holdings, too-small budget, insufficient sDGNRS
    ///                   claimable (>=1 ETH floor), gameOver/liveness, or a stale queue index.
    /// @custom:reverts RngLocked While the RNG window is locked (freeze invariant).
    function sellFarFutureTickets(
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

        uint256 oneTicketWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
        (
            ,
            uint256 totalBudget,
            uint256 ticketWei,

        ) = _quoteFarFutureSwap(player, levels, quantities);
        if (totalBudget < oneTicketWei) revert E(); // too small to deliver even 1 whole ticket

        // Fund fail-closed from sDGNRS's OWN claimable, leaving a >=1 ETH floor. The gambling-burn
        // redemption desk is protected STRUCTURALLY (its ETH is segregated out of claimable at submit),
        // so NO pendingRedemptionEthValue term is needed; NO daily cap.
        if (claimableWinnings[ContractAddresses.SDGNRS] < totalBudget + 1 ether)
            revert E();

        // Debit the seller's far entries (owed is in entries, 4 per whole ticket; swap-pop on full
        // sell-out) and credit sDGNRS the same entries. Distances were validated by _quoteFarFutureSwap;
        // sequential processing handles duplicate levels (a later same-level line reads the decremented
        // balance and reverts if it over-sells; only the line that zeroes the packed slot pops).
        for (uint256 i; i < len; ) {
            uint24 L = uint24(levels[i]);
            uint32 entries = uint32(quantities[i]) * 4;
            _removeFarFutureTickets(player, L, entries, queueIndices[i]);
            _queueTickets(ContractAddresses.SDGNRS, L, entries, false);
            unchecked {
                ++i;
            }
        }

        // Move the whole budget sDGNRS -> player as claimable (relabel; claimablePool unchanged).
        claimableWinnings[ContractAddresses.SDGNRS] -= totalBudget;
        claimableWinnings[player] += totalBudget;

        // Ticket leg = NORMAL recycled mint of `ticketWei` of current-level tickets from the player's
        // claimable (routes 90% next / 10% future + queues current tickets). Leftover (~cashWei) is the
        // player's withdrawable cash. qty in purchase units (4 * TICKET_SCALE = 400 = one whole ticket).
        uint256 qty = (ticketWei * 4 * TICKET_SCALE) / oneTicketWei;
        _purchaseFor(player, qty, 0, bytes32(0), MintPaymentKind.Claimable);

        emit FarFutureSwap(player, len, totalBudget, ticketWei, totalBudget - ticketWei);
    }

    /// @dev Debit `entries` (owed is in entries, 4 per whole ticket) of the player's far-future tickets
    ///      at level L. On full sell-out (packed == 0) verify the caller-supplied queue index and O(1)
    ///      swap-pop the seller out of ticketQueue[ffk], MAINTAINING `membership <=> packed != 0`
    ///      (so the far-future jackpot samplers need no change and gain no hot-path read). Partial sells
    ///      and sells that leave `rem` do not pop.
    function _removeFarFutureTickets(
        address player,
        uint24 L,
        uint32 entries,
        uint256 idx
    ) internal {
        uint24 ffk = _tqFarFutureKey(L);
        uint40 packed = ticketsOwedPacked[ffk][player];
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
            ticketsOwedPacked[ffk][player] = 0;
        } else {
            ticketsOwedPacked[ffk][player] = (uint40(newOwed) << 8) | uint40(rem);
        }
    }

    /// @dev Single-tx callers: the fresh-ETH portion is `msg.value`. Read here (a private fn)
    ///      so external non-payable callers (e.g. claimable-only paths) never reference msg.value.
    function _purchaseFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        _purchaseForWith(
            buyer,
            ticketQuantity,
            lootBoxAmount,
            affiliateCode,
            payKind,
            msg.value
        );
    }

    function _purchaseForWith(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) private {
        if (_livenessTriggered()) revert E();
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

        // ethValue is the per-slice fresh-ETH portion (== msg.value for single-tx callers; the
        // explicit afking batch slice for batchPurchase, which processes many buys in one frame).
        uint256 remainingEth = ethValue;
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

                // Snapshot basis: the lootbox shortfall draws against the claimable
                // captured at function entry (the mint leg's claimable use is tracked
                // separately via initialClaimable/finalClaimable).
                _settleClaimableShortfall(buyer, initialClaimable, shortfall);
                lootboxClaimableUsed = shortfall;
            }
        }

        // --- Ticket purchase (returns quest units, defers x00 bonus + ticket queuing) ---
        uint32 burnieMintUnits;
        uint32 adjustedQty;
        uint24 targetLevel;
        if (ticketCost != 0) {
            (
                lootboxFlipCredit,
                adjustedQty,
                targetLevel,
                burnieMintUnits
            ) = _callTicketPurchase(
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
                // score+1 and baseLevel+1 (cachedLevel + 1, DIV-1) are packed into
                // lootboxPurchasePacked after score computation below
                emit LootBoxIdx(buyer, uint32(lbIndex), lbDay);
                // First deposit for this (index, buyer): enqueue the box index for
                // the permissionless box auto-open cursor. The consumer-side
                // walk gates each index on lootboxRngWordByIndex != 0 (VRF
                // orphan-index protection), so enqueue is producer-only here.
                IDegenerusGame(address(this)).enqueueBoxForAutoOpen(lbIndex, buyer);
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
                uint256 psPacked = presaleStatePacked;
                uint256 newMintEth = ((psPacked >> PS_MINT_ETH_SHIFT) & PS_MINT_ETH_MASK) + lootBoxAmount;
                psPacked = (psPacked & ~(PS_MINT_ETH_MASK << PS_MINT_ETH_SHIFT))
                         | ((newMintEth & PS_MINT_ETH_MASK) << PS_MINT_ETH_SHIFT);
                if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) {
                    psPacked &= ~uint256(PS_ACTIVE_MASK);
                }
                presaleStatePacked = psPacked;
            }

            bool distress = _isDistressMode();
            if (distress) {
                lootboxDistressEth[lbIndex][buyer] += boostedAmount;
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

            uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
            uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;

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

            emit LootBoxBuy(buyer, lbDay, lootBoxAmount, presale, cachedLevel);
        }

        // --- Single quest handler call (post-action: handlers execute before score) ---
        // MINT_ETH quest progress is credited 1:1 in wei on the gross ETH-denominated
        // ticket + lootbox spend, regardless of fresh-vs-recycled funding source.
        uint256 ethMintSpendWei = ticketCost + lootBoxAmount;
        uint32 questStreak;
        {
            (
                uint256 questReward,
                uint8 questType,
                uint32 streak,
                bool questCompleted
            ) = quests.handlePurchase(
                    buyer,
                    ethMintSpendWei,
                    burnieMintUnits,
                    lootBoxAmount,
                    priceWei,
                    PriceLookupLib.priceForLevel(cachedLevel + 1)
                );
            questStreak = streak;
            if (questCompleted) {
                lootboxFlipCredit += questReward;
                if (ethMintSpendWei > 0 && questType == 1) {
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
            // Purchase-time EV-cap tally. The box's multiplier is frozen from the
            // first-deposit score snapshot; the cap key is cachedLevel + 1 (the lootbox
            // open level == the resolver's currentLevel = level + 1). Bonus boxes
            // (mult > NEUTRAL) draw add = min(deposit, CAP - used) from the shared
            // per-(player, level) accumulator and accumulate adjustedPortion into the
            // packed word; sub-neutral/neutral boxes draw zero cap.
            if (lbFirstDeposit) {
                uint64 adj;
                uint256 mult = _lootboxEvMultiplierFromScore(cachedScore);
                if (mult > LOOTBOX_EV_NEUTRAL_BPS) {
                    uint256 used = lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1];
                    uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                        ? 0
                        : LOOTBOX_EV_BENEFIT_CAP - used;
                    uint256 add = lootBoxAmount < remaining ? lootBoxAmount : remaining;
                    lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1] = used + add;
                    adj = uint64(add);
                }
                lootboxPurchasePacked[lbIndex][buyer] = _packLootboxPurchase(
                    uint16(cachedScore + 1),
                    adj,
                    uint24(cachedLevel + 1)
                );
            } else if (lootBoxAmount != 0) {
                (
                    uint16 scorePlus1,
                    uint64 adj,
                    uint24 baseLevelPlus1
                ) = _unpackLootboxPurchase(lootboxPurchasePacked[lbIndex][buyer]);
                uint256 mult = _lootboxEvMultiplierFromScore(
                    uint256(scorePlus1 - 1)
                );
                if (mult > LOOTBOX_EV_NEUTRAL_BPS) {
                    uint256 used = lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1];
                    uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                        ? 0
                        : LOOTBOX_EV_BENEFIT_CAP - used;
                    uint256 add = lootBoxAmount < remaining ? lootBoxAmount : remaining;
                    if (add != 0) {
                        lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1] = used + add;
                        lootboxPurchasePacked[lbIndex][buyer] = _packLootboxPurchase(
                            scorePlus1,
                            adj + uint64(add),
                            baseLevelPlus1
                        );
                    }
                }
            }
        }

        // Coin-presale-box credit accrual: while the box presale is open, every ETH
        // ticket + lootbox spend (fresh + recycled) earns 25% spendable box credit.
        // Covers batchPurchase, which routes through this path.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += (ticketCost + lootBoxAmount) / 4;
        }

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

    /// @notice Buy a credit-gated coin-presale box (standalone), funded by msg.value
    ///         plus an optional claimable shortfall (CPAY-02).
    /// @dev The box queues at the current lootbox RNG index and resolves off the
    ///      committed word later (RNG-freeze discipline). Reverts once presaleOver.
    /// @param buyer Player receiving the box (already operator-resolved by the entrypoint).
    /// @param boxAmount Requested box ETH (>= PRESALE_BOX_MIN, checked pre-clamp).
    function buyPresaleBox(address buyer, uint256 boxAmount) external payable {
        _buyPresaleBoxFor(buyer, boxAmount, msg.value);
    }

    /// @notice Buy tickets/lootbox (earning 25% presale-box credit) AND a presale box
    ///         in one call, sharing one RNG index. The mint leg is funded by msg.value;
    ///         the box leg is funded from the caller's claimable (CPAY-02 ledger move,
    ///         covered by the just-earned + banked credit gate).
    /// @param buyer Player receiving both legs (already operator-resolved by the entrypoint).
    /// @param ticketQuantity Tickets to buy (0 to skip).
    /// @param lootBoxAmount ETH lootbox spend (0 to skip).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (>= PRESALE_BOX_MIN, claimable-funded).
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external {
        // Mint leg first: consumes msg.value and accrues presaleBoxCredit, so the
        // just-earned credit is available to gate the box bought below.
        _purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind);
        // Box leg pays purely from claimable (no fresh ETH passed); the mint already
        // consumed msg.value. The box queues at the SAME current LR_INDEX as the mint
        // leg's lootbox (LR_INDEX does not advance mid-tx), so both share one index.
        _buyPresaleBoxFor(buyer, boxAmount, 0);
    }

    /// @dev Core credit-gated presale-box buy: clamp-to-50 close, 1:1 credit consume,
    ///      msg.value + claimable-shortfall payment (CPAY-02), 80/20 ETH routing via
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
        // No overpay vs the requested amount (CPAY: msg.value > cost reverts).
        if (valueForBox > boxAmount) revert E();

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

        // Payment: msg.value first (capped at the applied amount; clamp excess refunded),
        // claimable shortfall for the rest (STRICT 1-wei sentinel preserved).
        uint256 freshUsed = valueForBox > applied ? applied : valueForBox;
        uint256 refund = valueForBox - freshUsed;
        uint256 shortfall = applied - freshUsed;
        _settleClaimableShortfall(buyer, claimableWinnings[buyer], shortfall);

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
        // curve input so the resolution reads no mutable SLOAD (RNG freeze, R4).
        presaleBoxEth[index][buyer] =
            uint256(uint96(applied)) |
            (uint256(uint96(sold)) << PRESALE_BOX_SOLD_SHIFT) |
            (closing ? PRESALE_BOX_CLOSING_FLAG : 0);
        // First box deposit at this index: enqueue for the permissionless auto-open.
        IDegenerusGame(address(this)).enqueueBoxForAutoOpen(index, buyer);

        presaleBoxEthSold = uint96(sold + applied);
        if (closing) {
            // Latch the terminal in the crossing buy (stops further credit accrual
            // and box buys). The swept pool remainder is paid at this box's open.
            presaleOver = true;
        }

        emit PresaleBoxBuy(buyer, index, applied, closing);

        if (refund != 0) {
            (bool ok, ) = payable(msg.sender).call{value: refund}("");
            if (!ok) revert E();
        }
    }

    /// @dev Execute ticket purchase: payment, boost, affiliate routing, quest unit accumulation.
    ///      x00 century bonus and ticket queuing are handled by _purchaseFor after score computation.
    /// @return bonusCredit Affiliate kickback + bulk bonus flip credit
    /// @return adjustedQty32 Adjusted ticket quantity (with boost, without x00 bonus)
    /// @return targetLevel The level tickets are queued to
    /// @return burnieMintUnits BURNIE-paid mint quest units
    function _callTicketPurchase(
        address buyer,
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
            uint32 burnieMintUnits
        )
    {
        if (quantity == 0) revert E();
        if (_livenessTriggered()) revert E();
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
                .consumePurchaseBoost(buyer);
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
            _coinReceive(buyer, coinCost);

            // Accumulate BURNIE mint quest units (deferred to handlePurchase)
            uint32 questQty = uint32(quantity / (4 * TICKET_SCALE));
            if (questQty != 0) {
                burnieMintUnits += questQty;
            }
        } else {
            uint32 mintUnits = adjustedQty32;

            IDegenerusGame(address(this)).recordMint{value: value}(
                buyer,
                targetLevel,
                costWei,
                mintUnits,
                payKind
            );

            uint256 freshEth;
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
