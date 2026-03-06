// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
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
 * - `recordMintData`: Track per-player mint history and calculate BURNIE rewards
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
 * Bits 154-227: (reserved)         - Future use
 * Bits 228-243: levelUnits         - Units minted this level
 * Bit 244:      (deprecated)       - Previously used for bonus tracking
 * ```
 *
 * Note: Quest Streak and Affiliate Points are tracked separately in their respective contracts
 * (DegenerusQuests.questPlayerState and DegenerusAffiliate.affiliateBonusPointsBest).
 *
 * ## Trait Generation
 *
 * Traits are deterministically derived from tokenId via keccak256:
 * - Each token has 4 traits (one per quadrant: 0-63, 64-127, 128-191, 192-255)
 * - Uses 8×8 weighted grid for non-uniform distribution
 * - Higher-numbered sub-traits within each category are slightly rarer
 */
contract DegenerusGameMintModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Generic revert for overflow conditions.
    error E();
    /// @notice BURNIE ticket purchases are blocked within 30 days of the liveness-guard timeout.
    error CoinPurchaseCutoff();

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    IDegenerusCoin internal constant coin = IDegenerusCoin(ContractAddresses.COIN);
    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);
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
    /// @dev BURNIE loot box minimum purchase amount (scaled for testnet).
    uint256 private constant BURNIE_LOOTBOX_MIN = 1000 ether;
    /// @dev Absolute minimum ticket buy-in (ETH equivalent).
    uint256 private constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;

    /// @dev Lootbox boost amounts applied to the next lootbox purchase.
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500;
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500;
    uint16 private constant LOOTBOX_BOOST_25_BONUS_BPS = 2500;
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE =
        10 ether;
    uint48 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;

    /// @dev Loot box pool split: 90% future, 10% next.
    uint16 private constant LOOTBOX_SPLIT_FUTURE_BPS = 9000;
    uint16 private constant LOOTBOX_SPLIT_NEXT_BPS = 1000;

    /// @dev Loot box presale pool split: 40% future, 40% next, 20% vault.
    uint16 private constant LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 4000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_NEXT_BPS = 4000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_VAULT_BPS = 2000;

    /// @dev BURNIE ticket purchases are blocked this long after levelStartTime.
    ///      Prevents cheap positioning in the 30-day window before the liveness guard fires.
    uint256 private constant COIN_PURCHASE_CUTOFF = 335 days; // 365 - 30
    uint256 private constant COIN_PURCHASE_CUTOFF_LVL0 = 882 days; // 912 - 30

    /// @dev Number of daily jackpots per level (must match AdvanceModule).
    uint8 private constant JACKPOT_LEVEL_CAP = 5;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LootBoxBuy(
        address indexed buyer,
        uint48 indexed day,
        uint256 amount,
        bool presale,
        uint256 futureShare,
        uint256 nextPrizeShare,
        uint256 vaultShare,
        uint256 rewardShare
    );
    event LootBoxIdx(
        address indexed buyer,
        uint48 indexed index,
        uint48 indexed day
    );
    event BurnieLootBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 burnieAmount
    );
    event BoostUsed(
        address indexed player,
        uint48 indexed day,
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
     * @param lvl Current game level.
     * @param mintUnits Scaled ticket units purchased.
     * @return coinReward BURNIE amount to credit as coinflip stake (currently 0).
     *
     * ## Activity Score State Updates
     *
     * - `mintPacked_[player]` updated with level count, streak, whale bonuses, milestones
     * - Only writes to storage if data actually changed
     *
     * ## Level Transition Logic
     *
     * - Same level: Just update units
     * - New level with <4 units: Only track units, don't count as "minted"
     * - New level with ≥4 units: Update streak and total
     * - Century boundary (level 100, 200...): Total continues to accumulate
     */
    function recordMintData(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) external payable returns (uint256 coinReward) {
        // Load previous packed data
        uint256 prevData = mintPacked_[player];
        uint256 data;

        // ---------------------------------------------------------------------
        // Unpack previous state
        // ---------------------------------------------------------------------

        uint24 prevLevel = uint24((prevData >> BitPackingLib.LAST_LEVEL_SHIFT) & BitPackingLib.MASK_24);
        uint24 total = uint24((prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24);
        uint24 unitsLevel = uint24((prevData >> BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT) & BitPackingLib.MASK_24);

        bool sameLevel = prevLevel == lvl;
        bool sameUnitsLevel = unitsLevel == lvl;

        // ---------------------------------------------------------------------
        // Handle level units
        // ---------------------------------------------------------------------

        // Get previous level units (reset on level change)
        uint256 levelUnitsBefore = sameUnitsLevel ? ((prevData >> BitPackingLib.LEVEL_UNITS_SHIFT) & BitPackingLib.MASK_16) : 0;

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
            data = BitPackingLib.setPacked(prevData, BitPackingLib.LEVEL_UNITS_SHIFT, BitPackingLib.MASK_16, levelUnitsAfter);
            data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT, BitPackingLib.MASK_24, lvl);
            if (data != prevData) {
                mintPacked_[player] = data;
            }
            return coinReward;
        }

        // ---------------------------------------------------------------------
        // Update mint day
        // ---------------------------------------------------------------------

        uint32 day = _currentMintDay();
        data = _setMintDay(prevData, day, BitPackingLib.DAY_SHIFT, BitPackingLib.MASK_32);

        // ---------------------------------------------------------------------
        // Same level: Just update units
        // ---------------------------------------------------------------------

        if (sameLevel) {
            data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_UNITS_SHIFT, BitPackingLib.MASK_16, levelUnitsAfter);
            data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT, BitPackingLib.MASK_24, lvl);
            if (data != prevData) {
                mintPacked_[player] = data;
            }
            return coinReward;
        }

        // ---------------------------------------------------------------------
        // New level with ≥4 units: Full state update
        // ---------------------------------------------------------------------

        // Check for whale bundle frozen state
        uint24 frozenUntilLevel = uint24((prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
        bool isFrozen = frozenUntilLevel > 0 && lvl < frozenUntilLevel;

        // If frozen, skip updating total and streak (they're pre-set)
        // If we've reached the frozen level, clear the flag and resume normal tracking
        if (frozenUntilLevel > 0 && lvl >= frozenUntilLevel) {
            // Clear frozen flag and whale bundle type - resume normal tracking from here
            data = BitPackingLib.setPacked(data, BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT, BitPackingLib.MASK_24, 0);
            data = BitPackingLib.setPacked(data, BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT, 3, 0); // Clear bundle type
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
        data = BitPackingLib.setPacked(data, BitPackingLib.LAST_LEVEL_SHIFT, BitPackingLib.MASK_24, lvl);
        data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_COUNT_SHIFT, BitPackingLib.MASK_24, total);
        data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_UNITS_SHIFT, BitPackingLib.MASK_16, levelUnitsAfter);
        data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT, BitPackingLib.MASK_24, lvl);
        // Frozen flag is already set in data if it was modified above

        // ---------------------------------------------------------------------
        // Commit to storage (only if changed)
        // ---------------------------------------------------------------------

        if (data != prevData) {
            mintPacked_[player] = data;
        }
        return coinReward;
    }

    // -------------------------------------------------------------------------
    // Future Ticket Activation
    // -------------------------------------------------------------------------

    function processFutureTicketBatch(
        uint24 lvl
    ) external returns (bool worked, bool finished, uint32 writesUsed) {
        uint256 entropy = rngWordCurrent;
        address[] storage queue = ticketQueue[lvl];
        uint256 total = queue.length;
        if (total > type(uint32).max) revert E();
        if (total == 0) {
            ticketCursor = 0;
            ticketLevel = 0;
            return (false, true, 0);
        }

        if (ticketLevel != lvl) {
            ticketLevel = lvl;
            ticketCursor = 0;
        }

        uint256 idx = ticketCursor;
        if (idx >= total) {
            delete ticketQueue[lvl];
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
            uint40 packed = ticketsOwedPacked[lvl][player];
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            if (owed == 0) {
                if (rem == 0) {
                    if (packed != 0) {
                        ticketsOwedPacked[lvl][player] = 0;
                    }
                    // Charge one budget unit for skip/cleanup progress so sparse
                    // queues cannot consume unbounded work in one call.
                    unchecked { ++idx; ++used; }
                    processed = 0;
                    continue;
                }
                if (!_rollRemainder(entropy, baseKey, rem)) {
                    ticketsOwedPacked[lvl][player] = 0;
                    unchecked { ++idx; ++used; }
                    processed = 0;
                    continue;
                }
                uint40 rolledPacked = uint40(1) << 8;
                if (rolledPacked != packed) {
                    ticketsOwedPacked[lvl][player] = rolledPacked;
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
                ticketsOwedPacked[lvl][player] = newPacked;
            }
            unchecked {
                processed += take;
                used += writesThis;
            }

            if (remainingOwed == 0) {
                unchecked { ++idx; }
                processed = 0;
            }
        }

        worked = (used > 0);
        writesUsed = used;
        ticketCursor = uint32(idx);
        finished = (idx >= total);
        if (finished) {
            delete ticketQueue[lvl];
            ticketCursor = 0;
            ticketLevel = 0;
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
            uint32 groupIdx = i >> 4; // Group index (per 16 symbols)

            uint256 seed;
            unchecked {
                seed = (baseKey + groupIdx) ^ entropyWord;
            }
            uint64 s = uint64(seed) | 1; // Ensure odd for full LCG period
            uint8 offset = uint8(i & 15);
            unchecked {
                s = s * (TICKET_LCG_MULT + uint64(offset)) + uint64(offset);
            }

            for (uint8 j = offset; j < 16 && i < endIndex; ) {
                unchecked {
                    s = s * TICKET_LCG_MULT + 1; // LCG step

                    // Generate trait using weighted distribution, add quadrant offset.
                    uint8 traitId = DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6);

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
        uint256 rollEntropy = EntropyLib.entropyStep(entropy ^ rollSalt);
        return (rollEntropy % TICKET_SCALE) < rem;
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
    /// @dev BURNIE ticket and loot box purchases are allowed whenever RNG is unlocked.
    /// @param buyer Recipient of the purchased items.
    /// @param ticketQuantity Number of tickets to purchase (2 decimals, scaled by 100).
    /// @param lootBoxBurnieAmount BURNIE amount to burn for loot boxes.
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external {
        _purchaseCoinFor(
            buyer,
            ticketQuantity,
            lootBoxBurnieAmount
        );
    }

    /// @notice Purchase a low-EV loot box with BURNIE.
    /// @dev Uses the current lootbox RNG index; rewards are tickets + small BURNIE only.
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external {
        if (buyer == address(0)) revert E();
        _purchaseBurnieLootboxFor(buyer, burnieAmount);
    }

    function _purchaseCoinFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) private {
        address payer = msg.sender;

        if (ticketQuantity != 0) {
            // Block BURNIE tickets within 30 days of liveness-guard game over.
            uint256 elapsed = block.timestamp - levelStartTime;
            if (level == 0 ? elapsed > COIN_PURCHASE_CUTOFF_LVL0 : elapsed > COIN_PURCHASE_CUTOFF) revert CoinPurchaseCutoff();
            _callTicketPurchase(
                buyer,
                payer,
                ticketQuantity,
                MintPaymentKind.DirectEth,
                true,
                bytes32(0),
                0
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
        uint24 purchaseLevel = level + 1;
        uint256 priceWei = price;

        // Block lootbox purchases during BAF/Decimator resolution (jackpot levels)
        if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E();
        if (lootBoxAmount != 0 && lootBoxAmount < LOOTBOX_MIN) revert E();

        uint256 ticketCost = 0;

        if (ticketQuantity != 0) {
            if (ticketQuantity > type(uint32).max) revert E();
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

                uint256 claimable = claimableWinnings[buyer];
                // Preserve 1 wei sentinel (same as mint payments).
                if (claimable <= shortfall) revert E();
                unchecked {
                    claimableWinnings[buyer] = claimable - shortfall;
                }
                claimablePool -= shortfall;
                lootboxClaimableUsed = shortfall;
            }
        }

        if (ticketCost != 0) {
            _callTicketPurchase(
                buyer,
                buyer,
                ticketQuantity,
                payKind,
                false,
                affiliateCode,
                remainingEth
            );
        }

        if (lootBoxAmount != 0) {
            uint48 day = _simulatedDayIndex();
            uint48 index = lootboxRngIndex;
            bool presale = lootboxPresaleActive;

            uint256 packed = lootboxEth[index][buyer];
            uint256 existingAmount = packed & ((1 << 232) - 1);
            uint48 storedDay = lootboxDay[index][buyer];

            if (existingAmount == 0) {
                lootboxDay[index][buyer] = day;
                lootboxBaseLevelPacked[index][buyer] = uint24(level + 2);
                lootboxEvScorePacked[index][buyer] =
                    uint16(IDegenerusGame(address(this)).playerActivityScore(buyer) + 1);
                lootboxIndexQueue[buyer].push(index);
                emit LootBoxIdx(buyer, index, day);
            } else {
                if (storedDay != day) revert E();
            }

            uint256 boostedAmount = _applyLootboxBoostOnPurchase(
                buyer,
                day,
                lootBoxAmount
            );
            uint256 existingBase = lootboxEthBase[index][buyer];
            if (existingAmount != 0 && existingBase == 0) {
                existingBase = existingAmount;
            }
            lootboxEthBase[index][buyer] = existingBase + lootBoxAmount;

            // Pack: [232 bits: amount] [24 bits: purchase level]
            uint256 newAmount = existingAmount + boostedAmount;
            lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
            lootboxEthTotal += lootBoxAmount;
            _maybeRequestLootboxRng(lootBoxAmount);

            // Track mint-only lootbox ETH for presale cap (checked at phase transition)
            if (presale) {
                lootboxPresaleMintEth += lootBoxAmount;
            }

            uint256 futureBps = presale ? LOOTBOX_PRESALE_SPLIT_FUTURE_BPS : LOOTBOX_SPLIT_FUTURE_BPS;
            uint256 nextBps = presale ? LOOTBOX_PRESALE_SPLIT_NEXT_BPS : LOOTBOX_SPLIT_NEXT_BPS;
            uint256 vaultBps = presale ? LOOTBOX_PRESALE_SPLIT_VAULT_BPS : 0;

            uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
            uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
            uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;
            uint256 rewardShare;
            unchecked {
                rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare;
            }

            uint256 futureDelta = futureShare + rewardShare;
            if (futureDelta != 0) {
                futurePrizePool += futureDelta;
            }
            if (nextShare != 0) {
                nextPrizePool += nextShare;
            }
            if (vaultShare != 0) {
                (bool ok, ) = payable(ContractAddresses.VAULT).call{value: vaultShare}("");
                if (!ok) revert E();
            }

            // Always call affiliate - contract handles bytes32(0) by using stored code
            uint256 lootboxRakeback;
            if (lootboxFreshEth != 0) {
                lootboxRakeback = affiliate.payAffiliate(
                    _ethToBurnieValue(lootboxFreshEth, priceWei),
                    affiliateCode,
                    buyer,
                    purchaseLevel,
                    true,
                    uint16(IDegenerusGame(address(this)).playerActivityScore(buyer))
                );
            }
            if (lootboxClaimableUsed != 0) {
                lootboxRakeback += affiliate.payAffiliate(
                    _ethToBurnieValue(lootboxClaimableUsed, priceWei),
                    affiliateCode,
                    buyer,
                    purchaseLevel,
                    false,
                    0
                );
            }
            if (lootboxRakeback != 0) {
                coin.creditFlip(buyer, lootboxRakeback);
            }

            emit LootBoxBuy(buyer, day, lootBoxAmount, presale, futureShare, nextShare, vaultShare, rewardShare);

            // Match ticket purchase behavior: mint quest progress uses whole ticket-equivalent
            // units and only the fresh-ETH portion when claimable is mixed in.
            if (priceWei != 0) {
                uint256 questUnitsRaw = lootBoxAmount / priceWei;
                if (questUnitsRaw > type(uint32).max) {
                    questUnitsRaw = type(uint32).max;
                }
                if (questUnitsRaw != 0 && lootboxFreshEth != 0) {
                    uint256 scaled = (questUnitsRaw * lootboxFreshEth) / lootBoxAmount;
                    if (scaled != 0) {
                        coin.notifyQuestMint(buyer, uint32(scaled), true);
                    }
                }
            }

            // Lootbox quests continue tracking full lootbox spend (fresh + recycled).
            coin.notifyQuestLootBox(buyer, lootBoxAmount);
            _awardEarlybirdDgnrs(buyer, lootboxFreshEth, purchaseLevel);
        }

        uint256 finalClaimable = payKind == MintPaymentKind.DirectEth
            ? initialClaimable
            : claimableWinnings[buyer];
        uint256 totalClaimableUsed = initialClaimable > finalClaimable ? initialClaimable - finalClaimable : 0;
        uint256 availableClaimable = finalClaimable > 1 ? finalClaimable - 1 : 0;
        uint256 minTicketUnitCost = priceWei / (4 * TICKET_SCALE);
        bool spentAllClaimable = totalClaimableUsed != 0 &&
            (availableClaimable == 0 || (minTicketUnitCost != 0 && availableClaimable < minTicketUnitCost));

        if (spentAllClaimable && totalClaimableUsed >= priceWei * 3) {
            uint256 bonusAmount = (totalClaimableUsed * PRICE_COIN_UNIT * 10) / (priceWei * 100);
            if (bonusAmount != 0) {
                coin.creditFlip(buyer, bonusAmount);
            }
        }
    }

    function _callTicketPurchase(
        address buyer,
        address payer,
        uint256 quantity,
        MintPaymentKind payKind,
        bool payInCoin,
        bytes32 affiliateCode,
        uint256 value
    ) private {
        if (quantity == 0 || quantity > type(uint32).max) revert E();
        if (gameOver) revert E();
        if (rngLockedFlag) revert E();

        // Ticket routing differs by phase:
        // - purchase phase: tickets target next level
        // - jackpot phase: tickets target current level
        uint24 targetLevel = jackpotPhaseFlag ? level : level + 1;

        uint256 priceWei = price;
        uint256 costWei = (priceWei * quantity) / (4 * TICKET_SCALE);
        if (costWei == 0) revert E();
        if (costWei < TICKET_MIN_BUYIN_WEI) revert E();

        uint256 adjustedQuantity = quantity;
        if (!payInCoin) {
            uint16 boostBps = IDegenerusGame(address(this)).consumePurchaseBoost(
                payer
            );
            if (boostBps != 0) {
                uint256 cappedValue = costWei >
                    LOOTBOX_BOOST_MAX_VALUE
                    ? LOOTBOX_BOOST_MAX_VALUE
                    : costWei;
                uint256 cappedQty = priceWei == 0
                    ? 0
                    : ((cappedValue * 4 * TICKET_SCALE) / priceWei);
                adjustedQuantity += (cappedQty * boostBps) / 10_000;
            }
        }
        if (adjustedQuantity > type(uint32).max) {
            adjustedQuantity = type(uint32).max;
        }
        uint32 adjustedQty32 = uint32(adjustedQuantity);

        uint256 bonusCredit;
        if (payInCoin) {
            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
            _coinReceive(payer, coinCost);

            {
                uint32 questQty = uint32(quantity / (4 * TICKET_SCALE));
                if (questQty != 0) {
                    coin.notifyQuestMint(payer, questQty, false);
                }
            }

            bonusCredit = coinCost / 10;
        } else {
            uint32 mintUnits = adjustedQty32;

            (uint256 streakBonus, ) = IDegenerusGame(address(this))
                .recordMint{value: value}(
                payer,
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

            uint32 questUnits = uint32(quantity / (4 * TICKET_SCALE));
            if (questUnits != 0 && freshEth != 0) {
                uint256 scaled = (uint256(questUnits) * freshEth) / costWei;
                if (scaled != 0) {
                    coin.notifyQuestMint(payer, uint32(scaled), true);
                }
            }

            // Final jackpot day affiliate bonus: +10pp on fresh ETH
            uint256 freshBurnie = freshEth != 0
                ? _ethToBurnieValue(freshEth, priceWei)
                : 0;
            if (freshBurnie != 0 && jackpotPhaseFlag && jackpotCounter == JACKPOT_LEVEL_CAP - 1) {
                freshBurnie = targetLevel <= 3
                    ? (freshBurnie * 7) / 5
                    : (freshBurnie * 3) / 2;
            }

            uint256 rakeback;
            if (payKind == MintPaymentKind.Combined && freshEth != 0) {
                rakeback += affiliate.payAffiliate(
                    freshBurnie,
                    affiliateCode,
                    buyer,
                    targetLevel,
                    true,
                    0
                );
                uint256 recycled = costWei - freshEth;
                if (recycled != 0) {
                    rakeback += affiliate.payAffiliate(
                        _ethToBurnieValue(recycled, priceWei),
                        affiliateCode,
                        buyer,
                        targetLevel,
                        false,
                        0
                    );
                }
            } else if (payKind == MintPaymentKind.DirectEth) {
                rakeback += affiliate.payAffiliate(
                    freshBurnie,
                    affiliateCode,
                    buyer,
                    targetLevel,
                    true,
                    0
                );
            } else {
                rakeback += affiliate.payAffiliate(
                    _ethToBurnieValue(costWei, priceWei),
                    affiliateCode,
                    buyer,
                    targetLevel,
                    false,
                    0
                );
            }

            bonusCredit = streakBonus + rakeback;
            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
            bonusCredit += coinCost / 10;
            if (quantity >= 10 * 4 * TICKET_SCALE) {
                bonusCredit += (quantity * PRICE_COIN_UNIT) / (40 * TICKET_SCALE);
            }
            if (lastPurchaseDay && (targetLevel % 100) > 90) {
                bonusCredit += coinCost / 5;
            }

        }

        if (bonusCredit != 0) {
            coin.creditFlip(buyer, bonusCredit);
        }

        uint24 ticketLevel = targetLevel;
        uint256 ticketScaled = adjustedQuantity;

        if (ticketScaled > type(uint32).max) {
            ticketScaled = type(uint32).max;
        }
        if (ticketScaled != 0) {
            _queueTicketsScaled(buyer, ticketLevel, uint32(ticketScaled));
        }
    }

    function _coinReceive(
        address payer,
        uint256 amount
    ) private {
        coin.burnCoin(payer, amount);
    }

    /// @dev Convert ETH-denominated spend to BURNIE base units at current ticket price.
    function _ethToBurnieValue(uint256 amountWei, uint256 priceWei) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }

    function _purchaseBurnieLootboxFor(address buyer, uint256 burnieAmount) private {
        if (burnieAmount < BURNIE_LOOTBOX_MIN) revert E();
        uint48 index = lootboxRngIndex;
        if (index == 0) revert E();

        coin.burnCoin(buyer, burnieAmount);

        {
            uint256 questUnitsRaw = burnieAmount / PRICE_COIN_UNIT;
            if (questUnitsRaw > type(uint32).max) {
                questUnitsRaw = type(uint32).max;
            }
            if (questUnitsRaw != 0) {
                coin.notifyQuestMint(buyer, uint32(questUnitsRaw), false);
            }
        }

        uint256 existingAmount = lootboxBurnie[index][buyer];
        if (lootboxDay[index][buyer] == 0) {
            lootboxDay[index][buyer] = _simulatedDayIndex();
        }
        lootboxBurnie[index][buyer] = existingAmount + burnieAmount;

        lootboxRngPendingBurnie += burnieAmount;

        uint256 priceWei = price;
        if (priceWei != 0) {
            uint256 virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT;
            if (virtualEth != 0) {
                _maybeRequestLootboxRng(virtualEth);
            }
        }

        emit BurnieLootBuy(buyer, index, burnieAmount);
    }

    function _maybeRequestLootboxRng(uint256 lootBoxAmount) private {
        lootboxRngPendingEth += lootBoxAmount;
    }

    /// @dev Calculate boost amount given base amount and bonus bps
    function _calculateBoost(uint256 amount, uint16 bonusBps) private pure returns (uint256) {
        uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
        unchecked {
            return (cappedAmount * bonusBps) / 10_000;
        }
    }

    function _applyLootboxBoostOnPurchase(
        address player,
        uint48 day,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        uint16 consumedBoostBps = 0;

        // Check 25% boost first (rarest, best boost)
        bool has25 = lootboxBoon25Active[player];
        if (has25) {
            uint48 stampDay = lootboxBoon25Day[player];
            if (stampDay != 0 && day > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                lootboxBoon25Active[player] = false;
                has25 = false;
            }
        }
        if (has25) {
            boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_25_BONUS_BPS);
            consumedBoostBps = LOOTBOX_BOOST_25_BONUS_BPS;
            lootboxBoon25Active[player] = false;
        } else {
            // Check 15% boost
            bool has15 = lootboxBoon15Active[player];
            if (has15) {
                uint48 stampDay = lootboxBoon15Day[player];
                if (stampDay != 0 && day > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                    lootboxBoon15Active[player] = false;
                    has15 = false;
                }
            }
            if (has15) {
                boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_15_BONUS_BPS);
                consumedBoostBps = LOOTBOX_BOOST_15_BONUS_BPS;
                lootboxBoon15Active[player] = false;
            } else {
                // Check 5% boost if no 15% or 25% boost
                bool has5 = lootboxBoon5Active[player];
                if (has5) {
                    uint48 stampDay = lootboxBoon5Day[player];
                    if (stampDay != 0 && day > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                        lootboxBoon5Active[player] = false;
                        has5 = false;
                    }
                }
                if (has5) {
                    boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_5_BONUS_BPS);
                    consumedBoostBps = LOOTBOX_BOOST_5_BONUS_BPS;
                    lootboxBoon5Active[player] = false;
                }
            }
        }

        if (consumedBoostBps != 0) {
            emit BoostUsed(player, day, amount, boostedAmount, consumedBoostBps);
        }
    }

    /// @notice Resolve a lootbox directly (decimator claims) using provided RNG.
    /// @dev Access: ContractAddresses.JACKPOTS contract only. Presale is always false.
    ///      Does not touch lootbox purchase storage; uses current day for event tagging.
    /// @param player Player to receive lootbox rewards.
    /// @param amount Lootbox ETH amount to resolve.
    /// @param rngWord VRF random word from decimator jackpot resolution.
    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    
}
