// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RngTags} from "../libraries/RngTags.sol";

import {GameBoonActions} from "./GameBoonActions.sol";
import {GameBoxInternals} from "./GameBoxInternals.sol";

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

import {ContractAddresses} from "../ContractAddresses.sol";
import {GamePurchaseBoon} from "./GamePurchaseBoon.sol";

import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";

/**
 * @title DegenerusGameBoonModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for the boon lifecycle: box draws, deity issuance, consumption,
 *         and expiry maintenance.
 *
 * @dev Rolls and delivers box-drawn boons (`rollBoxBoons`), lets a
 *      deity-pass holder issue a daily boon to another player (`_issueDeityBoon`), consumes
 *      coinflip, craps, WWXRP, and decimator boons, and separately clears expired
 *      coinflip, lootbox, purchase, decimator, whale, deity-pass, and lazy-pass boons.
 *      Called via `delegatecall` from DegenerusGame -- all storage reads/writes
 *      operate on the game contract's storage.
 *
 *      All boon state is packed into a 2-slot BoonPacked struct per player.
 *      Each function loads the relevant slot(s), modifies in memory, and writes back only
 *      changed slots (at most 2 SSTOREs). Activity awards are the exception: they hold no
 *      slot at all and are credited to `mintPacked_` and the quest streak the moment they
 *      are drawn or gifted. See DegenerusGameStorage for bit layout.
 */
abstract contract DegenerusGameBoonModule is GameBoxInternals, GamePurchaseBoon, GameBoonActions
{
    error AlreadyOwnsDeityPass();
    error SymbolTaken();

    /// @notice Register both protocol deities and their first 100 perpetual tickets.
    function initProtocolDeity() external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (msg.sender != ContractAddresses.CREATOR || level != 0) revert E();
        // The Game constructor registered the protocol wallets as IDs 1-3.
        _registerDeity(VAULT_WALLET_ID, VAULT_DEITY_SYMBOL);
        _registerDeity(SDGNRS_WALLET_ID, SDGNRS_DEITY_SYMBOL);
        _latchConstructionSeat(VAULT_WALLET_ID);
        _latchConstructionSeat(SDGNRS_WALLET_ID);
        emit EntriesQueuedRange(VAULT_WALLET_ID, 1, 100, 1, DEITY_PERPETUAL_ENTRIES);
        emit EntriesQueuedRange(SDGNRS_WALLET_ID, 1, 100, 1, DEITY_PERPETUAL_ENTRIES);
        uint24 mintCeiling = _mintCeiling();
        uint24 writeSlotBit = ticketWriteSlot ? TICKET_SLOT_BIT : 0;
        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint24 key = lvl > mintCeiling ? _tqFarFutureKey(lvl) : lvl | writeSlotBit;
            _queueGenesisDeities(key);
        }
    }

    /// @dev Append both genesis wallets to one packed queue group.
    function _queueGenesisDeities(uint24 key) private {
        uint256 lanes;
        uint256 count;
        for (uint256 i; i < 2; ++i) {
            uint32 id = i == 0 ? VAULT_WALLET_ID : SDGNRS_WALLET_ID;
            uint80 packed = _entryPacked(key, id);
            if (packed == 0) {
                packed = uint80(id) << OWNER_IDX_SHIFT;
                lanes |= uint256(id) << (count * 32);
                ++count;
            }
            uint32 owed = _addOwed(uint32(packed >> 8), DEITY_PERPETUAL_ENTRIES,
                key & TICKET_FAR_FUTURE_BIT != 0);
            _setEntryOwed(key, id,
                (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(uint8(packed)));
        }
        if (count != 0) _tqAppendLanes(key, lanes, count);
    }

    function _latchConstructionSeat(uint32 who) private {
        uint256 packed = mintPacked_[who] | (uint256(1) << BitPackingLib.SEAT_CLAIMED_SHIFT);
        mintPacked_[who] = packed;
        emit MintRecorded(who, packed);
    }

    function _registerDeity(uint32 buyerId, uint8 symbolId) private {
        uint256 mp = mintPacked_[buyerId];
        if (mp >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) revert AlreadyOwnsDeityPass();
        if (deityBySymbol[symbolId] != 0) revert SymbolTaken();
        if (_deityCount() >= 32) revert E();
        uint256 packed = mp | (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT);
        mintPacked_[buyerId] = packed;
        deityBySymbol[symbolId] = buyerId;
        _pushDeityId(buyerId);
        emit MintRecorded(buyerId, packed);
        IGenesisDeityPassMint(ContractAddresses.DEITY_PASS).mint(_payee(_walletElement(buyerId)), symbolId);
    }

    /// @notice A protocol slot was automatically awarded to its winning bettor.
    event ProtocolBoonDrawAwarded(
        uint32 indexed issuerId, uint32 indexed winnerId, uint24 indexed day,
        uint8 slot, uint32 entryIndex, uint8 boonType
    );

    /// @notice Advance-only delegate target. Every funded pool has exactly three
    ///         awards, independently drawn with replacement. No recipient cap applies.
    /// @dev No public GAME selector routes here. Missing/expired/already-resolved work
    ///      is a no-op; a recipient's existing boon can only retain or upgrade its lane.
    function resolveProtocolBoonDraws(uint24 awardDay) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (gameOver || awardDay <= 1 || awardDay != _simulatedDayIndex()) return;
        uint256 menuWord = _recordedDailyWord(awardDay - 1);
        // Warm read: rngGate wrote this slot earlier in the same transaction, so passing the
        // word as calldata would cost more than reading it back.
        uint256 winnerWord = _recordedDailyWord(awardDay);
        if (winnerWord == 0) return;
        // Deployment day has no daily word. Draw its menu from the finalized
        // award-day word instead; the wager pool closed before that request.
        if (menuWord == 0) menuWord = winnerWord;
        _drawProtocolBoons(VAULT_WALLET_ID, awardDay, menuWord, winnerWord);
        _drawProtocolBoons(SDGNRS_WALLET_ID, awardDay, menuWord, winnerWord);
    }

    function _drawProtocolBoons(uint32 issuerId, uint24 awardDay, uint256 menuWord, uint256 winnerWord) private {
        uint24 day = awardDay - 1;
        // `day`'s ring slot (see protocolBoonPools). A slot tagged with another day holds an
        // older day's pool, which must never draw on this day's words: nothing was wagered on
        // `day`, so there is nothing to award.
        ProtocolBoonPool storage pool = protocolBoonPools[_protocolBoonIndex(issuerId)][day & 1];
        if (pool.day != day) return;
        uint64 totalWeight = pool.totalWeight;
        uint32 count = pool.entryCount;
        if (totalWeight == 0 || pool.awardedMask != 0) return;
        // Seal once before applying any reward. No retry or reroll after a collision.
        pool.awardedMask = 7;
        deityBoonPacked[issuerId] = (deityBoonPacked[issuerId] & ~uint64(type(uint32).max))
            | uint64(awardDay) | (uint64(7) << 24);
        if (count == 0) return;
        mapping(uint32 => ProtocolBoonEntry) storage entries = protocolBoonEntries[_protocolBoonIndex(issuerId)][day & 1];
        for (uint8 slot; slot < DEITY_DAILY_BOON_COUNT; ++slot) {
            uint256 roll = uint256(EntropyLib.hash4(RngTags.PROTOCOL_BOON_WINNER, winnerWord, issuerId, slot)) % totalWeight;
            // uint32-bounded entry count: at most 32 interval reads per award.
            uint32 lo;
            uint32 hi = count;
            while (lo < hi) {
                uint32 mid = lo + (hi - lo) / 2;
                if (entries[mid].cumulativeWeight <= roll) lo = mid + 1;
                else hi = mid;
            }
            uint32 winnerId = entries[lo].playerId;
            if (winnerId == 0) continue;
            uint8 boonType = _deityBoonForSlot(issuerId, awardDay, slot, menuWord);
            checkAndClearExpiredBoon(winnerId);
            _applyBoon(winnerId, boonType, awardDay, awardDay, 0, true);
            emit ProtocolBoonDrawAwarded(issuerId, winnerId, day, slot, lo, boonType);
        }
    }

    // =========================================================================
    // Constants
    // =========================================================================

    uint24 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;

    uint24 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    // =========================================================================
    // Boon Consumption Functions
    // =========================================================================

    // =========================================================================
    // Boon Maintenance Functions (called via nested delegatecall from LootboxModule)
    // =========================================================================

    /// @notice Clear all expired boons for a player and report if any remain active.
    /// @dev Called via nested delegatecall from LootboxModule during lootbox resolution.
    ///      Payable: redemption-claim resolution carries the sDGNRS ETH leg as msg.value,
    ///      which delegatecall keeps in flight through this nested dispatch.
    ///      Loads both packed slots (2 SLOADs), checks all boon categories for deity
    ///      and time-based expiry, clears expired fields in memory, writes back only
    ///      changed slots (at most 2 SSTOREs).
    /// @param id Wallet ID of the player to check and clear expired boons for
    /// @return hasAnyBoon True if the player has at least one active (non-expired) boon
    function checkAndClearExpiredBoon(uint32 id) public payable returns (bool hasAnyBoon) {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (empty local state returns silently).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint24 currentDay = uint24(_simulatedDayIndex());
        BoonPacked storage bp = boonPacked[id];
        uint256 s0 = bp.slot0;
        uint256 s1 = bp.slot1;
        bool changed0;
        bool changed1;

        // --- Slot 0: Coinflip ---
        uint8 coinflipTierLocal = uint8(s0 >> BP_COINFLIP_TIER_SHIFT);
        if (coinflipTierLocal != 0) {
            uint24 deityDay = uint24(s0 >> BP_DEITY_COINFLIP_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s0 = s0 & BP_COINFLIP_CLEAR;
                changed0 = true;
                coinflipTierLocal = 0;
            } else {
                uint24 stampDay = uint24(s0 >> BP_COINFLIP_DAY_SHIFT);
                if (stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS) {
                    s0 = s0 & BP_COINFLIP_CLEAR;
                    changed0 = true;
                    coinflipTierLocal = 0;
                }
            }
        }

        // --- Slot 0: Lootbox ---
        uint8 lootboxTierLocal = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (lootboxTierLocal != 0) {
            uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s0 = s0 & BP_LOOTBOX_CLEAR;
                changed0 = true;
                lootboxTierLocal = 0;
            } else {
                uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
                if (stampDay > 0 && currentDay > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                    s0 = s0 & BP_LOOTBOX_CLEAR;
                    changed0 = true;
                    lootboxTierLocal = 0;
                }
            }
        } else {
            // Stale deity day clearing for inactive lootbox boon
            uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s0 = s0 & BP_LOOTBOX_CLEAR;
                changed0 = true;
            }
        }

        // --- Slot 0: Purchase ---
        uint8 purchaseTierLocal = uint8(s0 >> BP_PURCHASE_TIER_SHIFT);
        if (purchaseTierLocal != 0) {
            uint24 deityDay = uint24(s0 >> BP_DEITY_PURCHASE_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s0 = s0 & BP_PURCHASE_CLEAR;
                changed0 = true;
                purchaseTierLocal = 0;
            } else {
                uint24 stampDay = uint24(s0 >> BP_PURCHASE_DAY_SHIFT);
                if (stampDay > 0 && currentDay > stampDay + PURCHASE_BOOST_EXPIRY_DAYS) {
                    s0 = s0 & BP_PURCHASE_CLEAR;
                    changed0 = true;
                    purchaseTierLocal = 0;
                }
            }
        }

        // --- Slot 0: Decimator (no time expiry, only deity day) ---
        uint8 decimatorTierLocal = uint8(s0 >> BP_DECIMATOR_TIER_SHIFT);
        if (decimatorTierLocal != 0) {
            uint24 deityDay = uint24(s0 >> BP_DEITY_DECIMATOR_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s0 = s0 & BP_DECIMATOR_CLEAR;
                changed0 = true;
                decimatorTierLocal = 0;
            }
        }

        // --- Slot 0: Whale ---
        uint24 whaleDayLocal = uint24(s0 >> BP_WHALE_DAY_SHIFT);
        if (whaleDayLocal != 0) {
            uint24 deityWhaleDay = uint24(s0 >> BP_DEITY_WHALE_DAY_SHIFT);
            if (deityWhaleDay != 0 && deityWhaleDay != currentDay) {
                s0 = s0 & BP_WHALE_CLEAR;
                changed0 = true;
                whaleDayLocal = 0;
            } else if (currentDay > whaleDayLocal + 4) {
                // Lootbox-rolled discount lapses after the same 4-day window purchaseWhalePass
                // honours, so a lapsed tier no longer blocks a lower re-roll as a "downgrade".
                s0 = s0 & BP_WHALE_CLEAR;
                changed0 = true;
                whaleDayLocal = 0;
            }
        }

        // Activity awards hold no slot: they are credited to player stats at award time,
        // so there is nothing here to expire.

        // --- Slot 1: Deity Pass ---
        uint8 deityPassTierLocal = uint8(s1 >> BP_DEITY_PASS_TIER_SHIFT);
        if (deityPassTierLocal != 0) {
            uint24 deityDay = uint24(s1 >> BP_DEITY_DEITY_PASS_DAY_SHIFT);
            if (deityDay != 0) {
                if (currentDay > deityDay) {
                    s1 = s1 & BP_DEITY_PASS_CLEAR;
                    changed1 = true;
                    deityPassTierLocal = 0;
                }
            } else {
                uint24 stampDay = uint24(s1 >> BP_DEITY_PASS_DAY_SHIFT);
                if (stampDay > 0 && currentDay > stampDay + DEITY_PASS_BOON_EXPIRY_DAYS) {
                    s1 = s1 & BP_DEITY_PASS_CLEAR;
                    changed1 = true;
                    deityPassTierLocal = 0;
                }
            }
        }

        // --- Slot 1: Lazy Pass ---
        uint24 lazyPassDayLocal = uint24(s1 >> BP_LAZY_PASS_DAY_SHIFT);
        if (lazyPassDayLocal != 0) {
            uint24 deityDay = uint24(s1 >> BP_DEITY_LAZY_PASS_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s1 = s1 & BP_LAZY_PASS_CLEAR;
                changed1 = true;
                lazyPassDayLocal = 0;
            } else if (currentDay > lazyPassDayLocal + 4) {
                s1 = s1 & BP_LAZY_PASS_CLEAR;
                changed1 = true;
                lazyPassDayLocal = 0;
            }
        }

        // --- Slot 1: Craps (the low lane) ---
        bool crapsLive;
        {
            uint256 lane = s1 & BP_LANE_MASK;
            if (lane & BP_LANE_TIER_MASK != 0) {
                if (_boonLaneLive(lane, currentDay)) {
                    crapsLive = true;
                } else {
                    s1 = s1 & ~BP_LANE_MASK;
                    changed1 = true;
                }
            }
        }

        // --- Slot 1: ETH / FLIP degenerette lanes and the WWXRP ecosystem lane. ---
        bool currencyBoonLive;
        for (uint256 i; i < 3; ++i) {
            uint256 laneShift = BP_DEGEN_LANE0_SHIFT + i * 24;
            uint256 lane = (s1 >> laneShift) & BP_LANE_MASK;
            if (lane & BP_LANE_TIER_MASK == 0) continue;
            if (_boonLaneLive(lane, currentDay)) {
                currencyBoonLive = true;
            } else {
                s1 = s1 & ~(BP_LANE_MASK << laneShift);
                changed1 = true;
            }
        }

        // Write back only changed slots
        if (changed0) bp.slot0 = (s0) | BP_SLOT0_RETAINED;
        if (changed1) bp.slot1 = s1 | BP_SLOT1_RETAINED;

        return (whaleDayLocal != 0 ||
            lazyPassDayLocal != 0 ||
            coinflipTierLocal != 0 ||
            lootboxTierLocal != 0 ||
            purchaseTierLocal != 0 ||
            decimatorTierLocal != 0 ||
            currencyBoonLive ||
            crapsLive ||
            deityPassTierLocal != 0);
    }

    /// @notice Emitted when a box-drawn boon is discarded rather than delivered — the
    ///         statically-drawn type is permanently unusable by this player.
    event BoonDiscarded(uint32 indexed id, uint8 boonType);

    // =========================================================================
    // Box-drawn boons
    // =========================================================================
    //
    // The draw table, its weights and every delivery branch execute in Game storage.
    // The Box resolver draws each entry's boons internally from position-derived seeds.

    /// @dev Assumed utilization of max boon value (50%)
    uint16 private constant LOOTBOX_BOON_UTILIZATION_BPS = 5000;

    /// @dev Threshold used by deity-pass discount boon availability logic.
    uint32 private constant DEITY_PASS_MAX_TOTAL = 32;

    /// @dev Probability scale for granular boon rolls (ppm = 1e6).
    uint256 private constant BOON_PPM_SCALE = 1_000_000;

    /// @dev Exact closed form of the weighted max-value table used to normalize boon frequency.
    ///      Every fixed-price family contributes 1568 ETH of weight*value; the FLIP-priced
    ///      families collapse to BOON_PRICE_WEIGHT = 4182 times the live ticket price (3270
    ///      coinflip/whale-pass/degenerette + 912 craps); lazy discounts collapse to
    ///      6 times the ten-level lazy-pass value. Activity, quest-shield and WWXRP boons
    ///      carry weight but contribute zero nominal value to this box-budget model.
    ///
    ///      The craps bankroll-payout family contributes the 912 of it: `200 x 3,000 + 40 x 6,000
    ///      + 8 x 9,000 = 912,000`, over the 1,000-FLIP ticket unit. Its top tier pays 15% of a
    ///      60,000-FLIP base — 9,000, not the 15,000 a 25% tier would — because the boon lifts
    ///      EVERY window a ticket plays, and a whole-day ticket plays seven.
    uint256 private constant BOON_FIXED_WEIGHTED_MAX = 1568 ether;
    uint256 private constant BOON_PRICE_WEIGHT = 4182;
    uint256 private constant BOON_LAZY_WEIGHT = 6;

    /// @dev Ten-level lazy-pass sums in 0.01-ETH units, packed one byte per start offset.
    ///      Levels 0-9 have intro prices; from level 10 onward the price curve repeats every
    ///      100 levels. Four cycle words cover offsets 0..99 in little-endian byte order.
    uint256 private constant LAZY_SUM_INTRO =
        0x00000000000000000000000000000000000000000000262422201e1b1815120f;
    uint256 private constant LAZY_SUM_CYCLE_0 =
        0x50504c4844403c3834302c28282828282828282828282828282828282828283c;
    uint256 private constant LAZY_SUM_CYCLE_1 =
        0x7878787874706c6864605c585450505050505050505050505050505050505050;
    uint256 private constant LAZY_SUM_CYCLE_2 =
        0x7884909ca8a09c9894908c8884807c7878787878787878787878787878787878;
    uint256 private constant LAZY_SUM_CYCLE_3 =
        0x000000000000000000000000000000000000000000000000000000004854606c;

    /// @notice Draw boons for every box in one opened entry.
    /// @dev External dispatch preserves the Game storage context. Box resolution calls
    ///      the internal body; each box draws from its own counter-tagged seed.
    /// @param id Box owner's wallet ID (boon state key).
    /// @param perBoxBudget Boon budget of a single box, in wei of ETH-equivalent value.
    /// @param boxCount Boxes rolled in this entry.
    /// @param originalAmount One box's resolution amount, for the reward events.
    /// @param currentLevel Open level (level + 1), threaded from the resolver.
    /// @param seed Player-mixed entry seed; box i draws off `hash2(seed, nonceBase + i)`.
    /// @param nonceBase Box position of this batch's first box within its entry.
    function rollBoxBoons(
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) external payable {
        _boxRollBoxBoons(id, perBoxBudget, boxCount, originalAmount, currentLevel, seed, nonceBase);
    }

    function _boxRollBoxBoons(
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) internal virtual override {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (perBoxBudget == 0 || boxCount == 0) return;

        (uint256 expectedPerBoon, uint24 currentDay) = _boxBoonContext(id, currentLevel);
        if (expectedPerBoon == 0) return;
        _rollBoxBoonLane(
            id,
            perBoxBudget,
            boxCount,
            originalAmount,
            seed,
            nonceBase,
            expectedPerBoon,
            currentDay
        );
    }

    /// @dev Clear expiry and derive the immutable-for-this-entry normalization once.
    function _boxBoonContext(
        uint32 id,
        uint24 currentLevel
    ) private returns (uint256 expectedPerBoon, uint24 currentDay) {

        // Expiry cleanup runs ONCE for the entry, not once per box: it is a property of the
        // player's held boons, which no draw below changes in a way that would re-arm it.
        BoonPacked storage bp = boonPacked[id];
        if ((bp.slot0 & ~BP_SLOT0_RETAINED) != 0 || (bp.slot1 & ~BP_SLOT1_RETAINED) != 0) checkAndClearExpiredBoon(id);

        // Pool stats are constant across the entry — same player, same level — so the exact
        // closed form is evaluated once rather than walking the static value table per box.
        uint256 avgMaxValue = _boonAvgMaxValue(currentLevel);
        if (avgMaxValue == 0) return (0, 0);

        expectedPerBoon = (avgMaxValue * LOOTBOX_BOON_UTILIZATION_BPS) / 10_000;
        if (expectedPerBoon == 0) return (0, 0);
        currentDay = _simulatedDayIndex();
    }

    /// @dev Roll one homogeneous tier using a normalization shared by the whole entry.
    function _rollBoxBoonLane(
        uint32 id,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint256 seed,
        uint256 nonceBase,
        uint256 expectedPerBoon,
        uint24 currentDay
    ) private {
        uint256 totalChance = (perBoxBudget * BOON_PPM_SCALE) / expectedPerBoon;
        if (totalChance > BOON_PPM_SCALE) totalChance = BOON_PPM_SCALE;
        if (totalChance == 0) return;

        for (uint256 i; i < boxCount; ) {
            uint256 roll = uint32(EntropyLib.hash3(RngTags.BOX_BOON_LANE, seed, nonceBase + i) >> 120) %
                BOON_PPM_SCALE;
            if (roll < totalChance) {
                _deliverBoon(
                    id,
                    _boonFromRoll((roll * BOON_WEIGHT_TOTAL) / totalChance),
                    currentDay,
                    originalAmount
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Keep-or-discard delivery filter for a lootbox-drawn boon. The TYPE is already
    ///      fixed (static table); live state may only decide whether the known outcome is
    ///      delivered. A discard writes nothing — occupying the category slot with a dead
    ///      boon would block a later useful one under upgrade-only semantics — and emits
    ///      `BoonDiscarded` so indexers keep the full draw history.
    ///
    ///      Only PERMANENTLY dead types are discarded, and the deity-pass family is the only
    ///      one filtered here: the recipient already holds a pass, or supply is capped, so no
    ///      future state makes the discount spendable. Decimator tiers are always delivered even
    ///      outside a burn window — a lootbox-sourced decimator boon carries NO time expiry
    ///      (BoonModule: "no time expiry, only deity day"), so it simply waits for the next
    ///      window; discarding it would destroy a bankable reward. Lazy boons bypass the
    ///      purchase level gate at consumption, so they carry no level condition; a deity
    ///      holder cannot buy a lazy pass at all, and that dead case is delivered anyway
    ///      rather than filtered.
    function _deliverBoon(
        uint32 id,
        uint8 boonType,
        uint24 currentDay,
        uint256 originalAmount
    ) private {
        if (boonType >= BOON_DEITY_PASS_10 && boonType <= BOON_DEITY_PASS_35) {
            if (
                mintPacked_[id] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 1 ||
                _deityCount() >= DEITY_PASS_MAX_TOTAL
            ) {
                emit BoonDiscarded(id, boonType);
                return;
            }
        }
        _applyBoon(id, boonType, 0, currentDay, originalAmount, false);
    }

    /// @dev Exact weighted-average max value of the static boon table. This is algebraically
    ///      identical to summing every family independently, but avoids dozens of repeated
    ///      multiplications/divisions on every box entry.
    function _boonAvgMaxValue(uint24 currentLevel) internal pure returns (uint256 avgMaxValue) {
        uint256 priceWei = PriceLookupLib.priceForLevel(currentLevel - 1);
        uint256 lazyPassValue = _lazyPassPriceForLevel(currentLevel + 1);
        uint256 weightedMax = BOON_FIXED_WEIGHTED_MAX +
            BOON_PRICE_WEIGHT * priceWei +
            BOON_LAZY_WEIGHT * lazyPassValue;
        avgMaxValue = weightedMax / BOON_WEIGHT_TOTAL;
    }

    /// @dev Get the value for a lazy pass at a specific level.
    ///      Value equals the sum of per-level ticket prices across 10 levels.
    /// @param passLevel The lazy pass start level
    /// @return The value in ETH (scaled by cost divisor)
    function _lazyPassPriceForLevel(
        uint24 passLevel
    ) internal pure returns (uint256) {
        // Wrap uint24 at the type boundary exactly as the unchecked per-level sum does.
        // Real game levels never approach it; keeping the fallback makes the optimization exact
        // over the function's full input domain as well as every reachable state.
        if (passLevel > type(uint24).max - 9) {
            uint256 wrappedTotal;
            for (uint24 i; i < 10; ) {
                unchecked {
                    wrappedTotal += PriceLookupLib.priceForLevel(passLevel + i);
                    ++i;
                }
            }
            return wrappedTotal;
        }

        uint256 table;
        uint256 byteIndex;
        if (passLevel < 10) {
            table = LAZY_SUM_INTRO;
            byteIndex = passLevel;
        } else {
            uint256 offset = passLevel % 100;
            byteIndex = offset & 31;
            if (offset < 32) {
                table = LAZY_SUM_CYCLE_0;
            } else if (offset < 64) {
                table = LAZY_SUM_CYCLE_1;
            } else if (offset < 96) {
                table = LAZY_SUM_CYCLE_2;
            } else {
                table = LAZY_SUM_CYCLE_3;
            }
        }
        return ((table >> (byteIndex * 8)) & 0xFF) * 0.01 ether;
    }

}

interface IGenesisDeityPassMint {
    function mint(address to, uint256 tokenId) external;
}
