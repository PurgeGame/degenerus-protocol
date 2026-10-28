// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RngTags} from "../libraries/RngTags.sol";
import {GameBoxInternals} from "./GameBoxInternals.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {GamePurchaseBoon} from "./GamePurchaseBoon.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";

/// @dev Shared internal implementation in Game storage.
abstract contract GameBoonActions is GamePurchaseBoon {
    uint24 internal constant COINFLIP_BOON_EXPIRY_DAYS = 2;

    /// @notice Consume the caller's coinflip, craps or WWXRP boon lane.
    /// @dev The Game facade authorizes COINFLIP, COIN and WWXRP. The original caller remains:
    ///      COINFLIP spends the coinflip boon, COIN spends the craps boon, and WWXRP spends its
    ///      ecosystem boon. Each caller reaches only its own lane through this shared selector.
    ///      ID 0 holds no boon state.
    /// @param id Wallet ID of the player to consume boon for
    /// @return boonBps Bonus BPS: WWXRP uses 400/800/1200; the other lanes use
    ///      500/1000/2500. Zero means no live boon.
    function _consumeActionBoon(uint32 id) internal returns (uint16 boonBps) {
        if (msg.sender == ContractAddresses.COIN) return _consumeCrapsBoon(id);
        if (msg.sender == ContractAddresses.WWXRP) return _consumeWwxrpBoon(id);
        BoonPacked storage bp = boonPacked[id];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_COINFLIP_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 currentDay = uint24(_gameDay());
        uint24 deityDay = uint24(s0 >> BP_DEITY_COINFLIP_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot0 = (s0 & BP_COINFLIP_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_COINFLIP_DAY_SHIFT);
        if (stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS) {
            bp.slot0 = (s0 & BP_COINFLIP_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        boonBps = _coinflipTierToBps(tier);
        bp.slot0 = (s0 & BP_COINFLIP_CLEAR) | BP_SLOT0_RETAINED;
        emit BoonConsumed(id, 1, boonBps);
    }

    /// @dev Spend the craps lane — slot1's low 24 bits, so no shift on this path. An expired
    ///      lane pays nothing and is cleared here, matching every other consumption site.
    ///      The tier decodes to the coinflip family's 500/1000/2500 bps wire values; FLIP maps
    ///      those to the one-hot mask the craps table pays at 5/10/15%.
    function _consumeCrapsBoon(uint32 id) internal returns (uint16 boonBps) {
        BoonPacked storage bp = boonPacked[id];
        uint256 s1 = bp.slot1;
        uint256 lane = s1 & BP_LANE_MASK;
        uint8 tier = uint8(lane & BP_LANE_TIER_MASK);
        if (tier == 0) return 0;
        if (!_boonLaneLive(lane, uint24(_gameDay()))) {
            bp.slot1 = (s1 & ~BP_LANE_MASK) | BP_SLOT1_RETAINED;
            return 0;
        }
        boonBps = _coinflipTierToBps(tier);
        bp.slot1 = (s1 & ~BP_LANE_MASK) | BP_SLOT1_RETAINED;
        emit BoonConsumed(id, 6, boonBps);
    }

    /// @dev Spend the WWXRP ecosystem lane. The token applies the returned bonus
    ///      to its consuming action; the boon module only owns the one-use tier.
    function _consumeWwxrpBoon(uint32 id) internal returns (uint16 boonBps) {
        BoonPacked storage bp = boonPacked[id];
        uint256 s1 = bp.slot1;
        uint256 lane = (s1 >> BP_WWXRP_LANE_SHIFT) & BP_LANE_MASK;
        uint8 tier = uint8(lane & BP_LANE_TIER_MASK);
        if (tier == 0) return 0;
        bp.slot1 = (s1 & ~(BP_LANE_MASK << BP_WWXRP_LANE_SHIFT)) | BP_SLOT1_RETAINED;
        if (!_boonLaneLive(lane, uint24(_gameDay()))) return 0;
        boonBps = uint16(tier) * 400;
        emit BoonConsumed(id, 7, boonBps);
    }

    /// @notice Consume a player's decimator boost and return the bonus BPS
    /// @param id Wallet ID of the player to consume boost for (ID 0 holds no boon state)
    /// @return boostBps The bonus in basis points (0 if no boost, 1000/2500/5000 otherwise)
    function _consumeDecimatorBoost(uint32 id) internal returns (uint16 boostBps) {
        BoonPacked storage bp = boonPacked[id];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_DECIMATOR_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 currentDay = uint24(_gameDay());
        uint24 deityDay = uint24(s0 >> BP_DEITY_DECIMATOR_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot0 = (s0 & BP_DECIMATOR_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        boostBps = _decimatorTierToBps(tier);
        bp.slot0 = (s0 & BP_DECIMATOR_CLEAR) | BP_SLOT0_RETAINED;
        emit BoonConsumed(id, 3, boostBps);
    }

    function _consumeDegeneretteStakeBoon(
        uint32 id,
        uint8 currency
    ) internal returns (uint16 boostBps) {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (empty local state returns silently).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (currency > 1) return 0;
        BoonPacked storage bp = boonPacked[id];
        uint256 s1 = bp.slot1;
        uint256 shift = _degeneretteLaneShift(currency);
        uint256 lane = (s1 >> shift) & BP_LANE_MASK;
        uint8 tier = uint8(lane & BP_LANE_TIER_MASK);
        if (tier == 0) return 0;
        if (!_boonLaneLive(lane, uint24(_gameDay()))) {
            bp.slot1 = (s1 & ~(BP_LANE_MASK << shift)) | BP_SLOT1_RETAINED;
            return 0;
        }
        boostBps = _degeneretteTierToBps(tier);
        bp.slot1 = (s1 & ~(BP_LANE_MASK << shift)) | BP_SLOT1_RETAINED;
        emit BoonConsumed(id, 4, boostBps);
    }

    /// @notice Emitted when a box awards a whale pass.
    event LootBoxWhalePassJackpot(
        uint32 indexed id,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 entriesPerLevel,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    /// @notice Emitted when a box delivers a boon-family reward.
    event LootBoxReward(
        uint32 indexed id,
        uint8 indexed rewardType,
        uint256 lootboxAmount,
        uint256 amount
    );

    /// @notice Emitted when a deity issues a boon to another player.
    event DeityBoonIssued(
        uint32 indexed deity,
        uint32 indexed recipient,
        uint24 indexed day,
        uint8 slot,
        uint8 boonType
    );

    /// @dev Whale boon discount tiers 1/2/3 (10%, 20%, 35%).
    uint16 internal constant LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS = 1000;

    uint16 internal constant LOOTBOX_WHALE_BOON_DISCOUNT_20_BPS = 2000;

    uint16 internal constant LOOTBOX_WHALE_BOON_DISCOUNT_35_BPS = 3500;

    /// @dev Lazy pass boon discount tiers (10%, 25%, 50%).
    uint16 internal constant LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS = 1000;

    uint16 internal constant LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS = 2500;

    uint16 internal constant LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS = 5000;

    /// @dev Tier identifier for 10% deity pass discount boon (1000 bps)
    uint8 internal constant DEITY_PASS_BOON_TIER_10 = 1;

    /// @dev Tier identifier for the tier-2 deity pass discount boon (20%, 2000 bps)
    uint8 internal constant DEITY_PASS_BOON_TIER_20 = 2;

    /// @dev Tier identifier for the tier-3 deity pass discount boon (35%, 3500 bps)
    uint8 internal constant DEITY_PASS_BOON_TIER_35 = 3;

    /// @dev 5% bonus in basis points for coinflip boon
    uint16 internal constant LOOTBOX_BOON_BONUS_BPS = 500;

    /// @dev Maximum bonus amount for coinflip boon (5000 FLIP)
    uint256 internal constant LOOTBOX_BOON_MAX_BONUS = 5000;

    /// @dev 10% bonus in basis points for coinflip boon
    uint16 internal constant LOOTBOX_COINFLIP_10_BONUS_BPS = 1000;

    /// @dev 25% bonus in basis points for coinflip boon
    uint16 internal constant LOOTBOX_COINFLIP_25_BONUS_BPS = 2500;

    /// @dev 5% purchase boost in basis points
    uint16 internal constant LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS = 500;

    /// @dev 15% purchase boost in basis points
    uint16 internal constant LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS = 1500;

    /// @dev 25% purchase boost in basis points
    uint16 internal constant LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS = 2500;

    /// @dev 10% decimator boost in basis points
    uint16 internal constant LOOTBOX_DECIMATOR_10_BONUS_BPS = 1000;

    /// @dev 25% decimator boost in basis points
    uint16 internal constant LOOTBOX_DECIMATOR_25_BONUS_BPS = 2500;

    /// @dev 50% decimator boost in basis points
    uint16 internal constant LOOTBOX_DECIMATOR_50_BONUS_BPS = 5000;

    /// @dev Activity award: +10 to the mint-level count and quest streak
    uint24 internal constant LOOTBOX_ACTIVITY_BOON_10_BONUS = 10;

    /// @dev Activity award: +25 to the mint-level count and quest streak
    uint24 internal constant LOOTBOX_ACTIVITY_BOON_25_BONUS = 25;

    /// @dev Activity award: +50 to the mint-level count and quest streak
    uint24 internal constant LOOTBOX_ACTIVITY_BOON_50_BONUS = 50;

    /// @dev Quest-streak shields granted per quest-shield boon
    uint16 internal constant LOOTBOX_QUEST_SHIELD_GRANT = 1;

    /// @dev Number of boon slots available per deity per day
    uint8 internal constant DEITY_DAILY_BOON_COUNT = 3;

    /// @dev Lifetime cap on deity boons a single deity may issue to a single recipient
    uint8 internal constant DEITY_RECIPIENT_BOON_CAP = 10;

    /// @dev Boon type: 5% coinflip bonus
    uint8 internal constant BOON_COINFLIP_5 = 1;

    /// @dev Boon type: 10% coinflip bonus
    uint8 internal constant BOON_COINFLIP_10 = 2;

    /// @dev Boon type: 25% coinflip bonus
    uint8 internal constant BOON_COINFLIP_25 = 3;

    /// @dev Boon type: grant one quest-streak shield
    uint8 internal constant BOON_QUEST_SHIELD = 4;

    /// @dev Boon type: 5% lootbox boost
    uint8 internal constant BOON_LOOTBOX_5 = 5;

    /// @dev Boon type: 15% lootbox boost
    uint8 internal constant BOON_LOOTBOX_15 = 6;

    /// @dev Boon type: 5% purchase boost
    uint8 internal constant BOON_PURCHASE_5 = 7;

    /// @dev Boon type: 15% purchase boost
    uint8 internal constant BOON_PURCHASE_15 = 8;

    /// @dev Boon type: 25% purchase boost
    uint8 internal constant BOON_PURCHASE_25 = 9;

    /// @dev Boon type: 10% decimator boost
    uint8 internal constant BOON_DECIMATOR_10 = 13;

    /// @dev Boon type: 25% decimator boost
    uint8 internal constant BOON_DECIMATOR_25 = 14;

    /// @dev Boon type: 50% decimator boost
    uint8 internal constant BOON_DECIMATOR_50 = 15;

    /// @dev Boon type: 10% whale discount
    uint8 internal constant BOON_WHALE_10 = 16;

    /// @dev Boon type: +10 activity award (mint-level count + quest streak)
    uint8 internal constant BOON_ACTIVITY_10 = 17;

    /// @dev Boon type: +25 activity award (mint-level count + quest streak)
    uint8 internal constant BOON_ACTIVITY_25 = 18;

    /// @dev Boon type: +50 activity award (mint-level count + quest streak)
    uint8 internal constant BOON_ACTIVITY_50 = 19;

    /// @dev Boon type: 25% lootbox boost
    uint8 internal constant BOON_LOOTBOX_25 = 22;

    /// @dev Boon type: tier-2 whale discount (20%)
    uint8 internal constant BOON_WHALE_20 = 23;

    /// @dev Boon type: tier-3 whale discount (35%)
    uint8 internal constant BOON_WHALE_35 = 24;

    /// @dev Boon type: 10% deity pass discount
    uint8 internal constant BOON_DEITY_PASS_10 = 25;

    /// @dev Boon type: tier-2 deity pass discount (20%)
    uint8 internal constant BOON_DEITY_PASS_20 = 26;

    /// @dev Boon type: tier-3 deity pass discount (35%)
    uint8 internal constant BOON_DEITY_PASS_35 = 27;

    /// @dev Boon type: whale pass award
    uint8 internal constant BOON_WHALE_PASS = 28;

    /// @dev Boon type: 10% lazy pass discount
    uint8 internal constant BOON_LAZY_PASS_10 = 29;

    /// @dev Boon type: 25% lazy pass discount
    uint8 internal constant BOON_LAZY_PASS_25 = 30;

    /// @dev Boon type: 50% lazy pass discount
    uint8 internal constant BOON_LAZY_PASS_50 = 31;

    /// @dev Degenerette stake boons, contiguous 32-37.
    ///      Each targets ONE bet currency; the tier byte written to `boonPacked` re-orders
    ///      them by value (see `_degeneretteTierToBps`).
    uint8 internal constant BOON_DEGEN_ETH_4 = 32;

    uint8 internal constant BOON_DEGEN_ETH_8 = 33;

    uint8 internal constant BOON_DEGEN_ETH_12 = 34;

    uint8 internal constant BOON_DEGEN_FLIP_4 = 35;

    uint8 internal constant BOON_DEGEN_FLIP_8 = 36;

    uint8 internal constant BOON_DEGEN_FLIP_12 = 37;

    /// @dev WWXRP ecosystem boons, consumed through the token for its supported actions.
    uint8 internal constant BOON_WWXRP_4 = 38;

    uint8 internal constant BOON_WWXRP_8 = 39;

    uint8 internal constant BOON_WWXRP_12 = 40;

    /// @dev Craps stake boons. A successful self-funded craps purchase burns in full and carries
    ///      the boon onto its slip; the tier then boosts that slip's BANKROLL RETURN by 5/10/15%
    ///      when it settles, off a base capped at 60,000 FLIP. Nothing is credited at entry, and a
    ///      busted run pays no bonus.
    uint8 internal constant BOON_CRAPS_5 = 41;

    uint8 internal constant BOON_CRAPS_10 = 42;

    uint8 internal constant BOON_CRAPS_15 = 43;

    /// @dev Combined weight of deity pass discount boons (10% + 20% + 35%)
    uint16 internal constant BOON_WEIGHT_DEITY_PASS_ALL = 40;

    /// @dev Total weight sum when decimator boons are allowed (includes the +200 quest-shield weight).
    ///      WWXRP occupies 2008..2607 and craps occupies the tail 2608..2855.
    uint16 internal constant BOON_WEIGHT_TOTAL = 2856;

    /// @dev Cursor position where the decimator band starts in the `_boonFromRoll` walk
    ///      (sum of the coinflip + lootbox + purchase weights ahead of it).
    uint16 internal constant BOON_WEIGHT_PRE_DECIMATOR = 982;

    /// @dev Combined weight of the three decimator tiers (a band the deity roll skips).
    uint16 internal constant BOON_WEIGHT_DECIMATOR_ALL = 50;

    /// @dev Cursor position where the deity-pass band starts (pre-dec 982 + dec 50 +
    ///      whale-discount 40), in full-table coordinates after the dec skip re-adds 50.
    uint16 internal constant BOON_WEIGHT_PRE_DEITY_PASS = 1072;

    /// @dev Whale pass standard entries per level (4 entries = 1 ticket). Reported in the
    ///      LootBoxWhalePassJackpot event for downstream indexers; the
    ///      actual ticket materialization happens in claimWhalePass.
    uint32 internal constant WHALE_PASS_ENTRIES_PER_LEVEL = 2;

    /// @notice Thrown when a deity attempts to issue a boon to themselves.
    error SelfBoon();

    /// @notice Thrown when the deity boon slot index is >= DEITY_DAILY_BOON_COUNT.
    error InvalidSlot();

    /// @notice Thrown when the recipient hit the lifetime cap on boons from this deity.
    error RecipientBoonCapReached();

    /// @notice Thrown when the deity boon slot has already been used on the current day.
    error SlotAlreadyUsed();

    /// @dev Apply a boon to a player. Handles both lootbox-sourced and deity-sourced boons.
    ///      Both sources use upgrade semantics (only if higher tier/amount).
    ///      Lootbox boons: emit LootBoxReward, deity day = 0.
    ///      Deity boons: no LootBoxReward; manual gifts log DeityBoonIssued, automatic
    ///      draws log ProtocolBoonDrawAwarded. Instant awards keep their own
    ///      BoonConsumed/MintRecorded/quest events. Deity day = day.
    ///      All boon state is stored in boonPacked[id] (2-slot packed struct).
    ///      Players can hold one boon per packed lane simultaneously (coinflip, lootbox,
    ///      purchase, decimator, whale, lazy, deity pass, craps, and one per Degenerette
    ///      currency); activity, quest-shield and whale-pass awards credit instantly.
    ///      Isolated bit fields per category -- applying a boon in one category cannot
    ///      affect another category's bits (targeted bitmask operations: & ~mask | value).
    function _applyBoon(
        uint32 id,
        uint8 boonType,
        uint24 day,
        uint24 currentDay,
        uint256 originalAmount,
        bool isDeity
    ) internal {
        // Every state-touching branch below resolves the same account record; derive its
        // storage slot once (a pointer, not a cached value — reads stay live). The two
        // slot-less branches (quest-shield, whale-pass) simply never touch it.
        BoonPacked storage bp = boonPacked[id];
        // Coinflip boons (types 1-3) — slot0
        if (boonType <= BOON_COINFLIP_25) {
            uint16 bps = boonType == BOON_COINFLIP_25
                ? LOOTBOX_COINFLIP_25_BONUS_BPS
                : (boonType == BOON_COINFLIP_10 ? LOOTBOX_COINFLIP_10_BONUS_BPS : LOOTBOX_BOON_BONUS_BPS);
            uint256 s0 = bp.slot0;
            uint8 newTier = _coinflipBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_COINFLIP_TIER_SHIFT);
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer
            // (nor zero a held deity boon's same-day flag).
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_COINFLIP_TIER_SHIFT)) | (uint256(newTier) << BP_COINFLIP_TIER_SHIFT);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_COINFLIP_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_COINFLIP_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_COINFLIP_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_COINFLIP_DAY_SHIFT);
                bp.slot0 = (s0) | BP_SLOT0_RETAINED;
            }
            if (!isDeity) emit LootBoxReward(id, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS);
            return;
        }

        // Lootbox boost boons (types 5, 6, 22) — slot0, single tier field
        if (boonType == BOON_LOOTBOX_5 || boonType == BOON_LOOTBOX_15 || boonType == BOON_LOOTBOX_25) {
            uint8 newTier = boonType == BOON_LOOTBOX_25 ? uint8(3) :
                            (boonType == BOON_LOOTBOX_15 ? uint8(2) : uint8(1));
            uint256 s0 = bp.slot0;
            uint8 existingTier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
            // Both deity and lootbox: upgrade semantics — keep higher tier
            uint8 activeTier = newTier > existingTier ? newTier : existingTier;
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s0 = s0 & BP_LOOTBOX_CLEAR;
                s0 = s0 | (uint256(uint24(currentDay)) << BP_LOOTBOX_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = s0 | (uint256(deityDayVal) << BP_DEITY_LOOTBOX_DAY_SHIFT);
                s0 = s0 | (uint256(activeTier) << BP_LOOTBOX_TIER_SHIFT);
                bp.slot0 = (s0) | BP_SLOT0_RETAINED;
            }
            if (!isDeity) {
                // Map active tier back to BPS and rewardType for event
                uint16 activeBps = _lootboxTierToBps(activeTier);
                uint8 rewardType = activeTier == 3 ? 6 : (activeTier == 2 ? 5 : 4);
                emit LootBoxReward(id, rewardType, originalAmount, activeBps);
            }
            return;
        }

        // Purchase boost boons (types 7, 8, 9) — slot0
        if (boonType == BOON_PURCHASE_5 || boonType == BOON_PURCHASE_15 || boonType == BOON_PURCHASE_25) {
            uint16 bps = boonType == BOON_PURCHASE_25
                ? LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS
                : (boonType == BOON_PURCHASE_15 ? LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS : LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS);
            uint256 s0 = bp.slot0;
            uint8 newTier = _purchaseBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_PURCHASE_TIER_SHIFT);
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_PURCHASE_TIER_SHIFT)) | (uint256(newTier) << BP_PURCHASE_TIER_SHIFT);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_PURCHASE_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_PURCHASE_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_PURCHASE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_PURCHASE_DAY_SHIFT);
                bp.slot0 = (s0) | BP_SLOT0_RETAINED;
            }
            if (!isDeity) {
                uint8 rewardType = bps == LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS
                    ? 6 : (bps == LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS ? 5 : 4);
                emit LootBoxReward(id, rewardType, originalAmount, bps);
            }
            return;
        }

        // Decimator boost boons (types 13, 14, 15) — slot0 (no award day, only tier + deity day)
        if (boonType == BOON_DECIMATOR_10 || boonType == BOON_DECIMATOR_25 || boonType == BOON_DECIMATOR_50) {
            uint16 bps = boonType == BOON_DECIMATOR_50
                ? LOOTBOX_DECIMATOR_50_BONUS_BPS
                : (boonType == BOON_DECIMATOR_25 ? LOOTBOX_DECIMATOR_25_BONUS_BPS : LOOTBOX_DECIMATOR_10_BONUS_BPS);
            uint256 s0 = bp.slot0;
            uint8 newTier = _decimatorBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_DECIMATOR_TIER_SHIFT);
            // Only a genuine tier upgrade applies the boon and (re)sets its deity-day; an
            // ignored lower/equal-tier roll is a no-op and must not zero a held deity boon.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_DECIMATOR_TIER_SHIFT)) | (uint256(newTier) << BP_DECIMATOR_TIER_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_DECIMATOR_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DECIMATOR_DAY_SHIFT);
                bp.slot0 = (s0) | BP_SLOT0_RETAINED;
            }
            if (!isDeity) emit LootBoxReward(id, 8, originalAmount, bps);
            return;
        }

        // Whale discount boons (types 16, 23, 24) — slot0
        if (boonType == BOON_WHALE_10 || boonType == BOON_WHALE_20 || boonType == BOON_WHALE_35) {
            uint16 bps = boonType == BOON_WHALE_35
                ? LOOTBOX_WHALE_BOON_DISCOUNT_35_BPS
                : (boonType == BOON_WHALE_20 ? LOOTBOX_WHALE_BOON_DISCOUNT_20_BPS : LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS);
            uint256 s0 = bp.slot0;
            uint8 newTier = _whaleBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_WHALE_TIER_SHIFT) & 3;
            // A dead lane never blocks a fresh award: the deity gift path applies without the
            // box-roll expiry sweep, so liveness is re-checked here — a deity-stamped lane lives
            // only on its day, a lootbox-rolled one for the same four days purchaseWhalePass honours.
            {
                uint24 heldDay = uint24(s0 >> BP_WHALE_DAY_SHIFT);
                uint24 heldDeityDay = uint24(s0 >> BP_DEITY_WHALE_DAY_SHIFT);
                bool live = heldDay != 0 &&
                    (heldDeityDay != 0 ? heldDeityDay == currentDay : currentDay <= heldDay + 4);
                if (!live) existingTier = 0;
            }
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(3) << BP_WHALE_TIER_SHIFT)) | (uint256(newTier) << BP_WHALE_TIER_SHIFT);
                uint24 whaleDayVal = isDeity ? uint24(day) : uint24(currentDay);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_WHALE_DAY_SHIFT)) | (uint256(whaleDayVal) << BP_WHALE_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_WHALE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_WHALE_DAY_SHIFT);
                bp.slot0 = (s0) | BP_SLOT0_RETAINED;
            }
            if (!isDeity) emit LootBoxReward(id, 9, originalAmount, bps);
            return;
        }

        // Quest-streak-shield boon (type 4) — instant grant, no boon-mapping state.
        // Runs in GAME's delegatecall context, so the call to QUESTS is GAME-authorized.
        if (boonType == BOON_QUEST_SHIELD) {
            IDegenerusQuests(ContractAddresses.QUESTS).awardQuestStreakShield(id, LOOTBOX_QUEST_SHIELD_GRANT);
            if (!isDeity) emit LootBoxReward(id, 12, originalAmount, LOOTBOX_QUEST_SHIELD_GRANT);
            return;
        }

        // Activity boons (types 17, 18, 19) — instant grant, no boon-mapping state. The
        // award is a straight stat credit with no consumption site of its own, so it lands
        // where it is drawn or gifted instead of parking in a slot for a later sweep. That
        // makes repeat wins additive (+10 then +50 pays +60, not +50) and lets a deity gift
        // reach a recipient who never opens a box.
        if (boonType == BOON_ACTIVITY_10 || boonType == BOON_ACTIVITY_25 || boonType == BOON_ACTIVITY_50) {
            uint24 amt = boonType == BOON_ACTIVITY_50
                ? LOOTBOX_ACTIVITY_BOON_50_BONUS
                : (boonType == BOON_ACTIVITY_25 ? LOOTBOX_ACTIVITY_BOON_25_BONUS : LOOTBOX_ACTIVITY_BOON_10_BONUS);
            _creditActivity(id, amt, currentDay);
            if (!isDeity) emit LootBoxReward(id, 10, originalAmount, amt);
            return;
        }

        // Deity pass discount boons (types 25, 26, 27) — slot1
        if (boonType == BOON_DEITY_PASS_10 || boonType == BOON_DEITY_PASS_20 || boonType == BOON_DEITY_PASS_35) {
            uint8 tier = boonType == BOON_DEITY_PASS_35
                ? DEITY_PASS_BOON_TIER_35
                : (boonType == BOON_DEITY_PASS_20 ? DEITY_PASS_BOON_TIER_20 : DEITY_PASS_BOON_TIER_10);
            uint256 s1 = bp.slot1;
            uint8 existingTier = uint8(s1 >> BP_DEITY_PASS_TIER_SHIFT);
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (tier > existingTier) {
                s1 = (s1 & ~(uint256(BP_MASK_8) << BP_DEITY_PASS_TIER_SHIFT)) | (uint256(tier) << BP_DEITY_PASS_TIER_SHIFT);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_PASS_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_DEITY_PASS_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_DEITY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DEITY_PASS_DAY_SHIFT);
                bp.slot1 = s1 | BP_SLOT1_RETAINED;
            }
            if (!isDeity) {
                uint16 bps = tier == DEITY_PASS_BOON_TIER_35 ? 3500 : (tier == DEITY_PASS_BOON_TIER_20 ? 2000 : 1000);
                emit LootBoxReward(id, 10, originalAmount, bps);
            }
            return;
        }

        // Whale pass (type 28) — no boon mapping access: an O(1) pending claim of two half
        // passes (one full pass); claimWhalePass materializes stats and tickets later.
        if (boonType == BOON_WHALE_PASS) {
            _addHalfPasses(id, 2);
            if (!isDeity) {
                // `level + 1` records the level AT BOX-OPEN TIME for indexers;
                // actual ticket queuing is deferred to claim-time, so the queued
                // tickets start at the level when the player calls claimWhalePass —
                // not necessarily `level + 1` here.
                emit LootBoxWhalePassJackpot(id, originalAmount, level + 1, WHALE_PASS_ENTRIES_PER_LEVEL, 0, 0);
            }
            return;
        }

        // ETH / FLIP stake boons (32-37) and WWXRP ecosystem boons (38-40) use
        // independent 24-bit lanes. A roll competes only within its own lane.
        // ETH / FLIP consume on a bet; WWXRP consumes through the token's actions.
        if (boonType >= BOON_DEGEN_ETH_4 && boonType <= BOON_WWXRP_12) {
            // 32/33/34 -> ETH, 35/36/37 -> FLIP, 38/39/40 -> WWXRP.
            // within a lane the three types map to tier 1/2/3 (+4/8/12%).
            uint8 offset = boonType - BOON_DEGEN_ETH_4;
            uint8 newTier = (offset % 3) + 1;
            uint256 laneShift = BP_DEGEN_LANE0_SHIFT + uint256(offset / 3) * 24;
            uint256 s1 = bp.slot1;
            uint256 lane = (s1 >> laneShift) & BP_LANE_MASK;
            // A dead lane never blocks a fresh award: the deity gift path applies without
            // the box-roll expiry sweep, so liveness is re-checked here, not assumed swept.
            uint8 heldTier = _boonLaneLive(lane, uint24(currentDay))
                ? uint8(lane & BP_LANE_TIER_MASK)
                : 0;
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > heldTier) {
                uint256 stamp = (isDeity ? uint256(uint24(day)) : uint256(uint24(currentDay))) &
                    BP_LANE_DAY_MASK;
                uint256 fresh = (stamp << BP_LANE_DAY_SHIFT) |
                    (isDeity ? BP_LANE_DEITY_BIT : 0) |
                    newTier;
                bp.slot1 = ((s1 & ~(BP_LANE_MASK << laneShift)) | (fresh << laneShift)) | BP_SLOT1_RETAINED;
            }
            if (!isDeity) {
                // The value field is the rolled boonType itself (32-40): unlike bps —
                // identical across currencies — it identifies both the currency and size.
                emit LootBoxReward(id, 13, originalAmount, boonType);
            }
            return;
        }

        // Craps stake boons (types 41-43) — slot1's LOW lane, the same 24-bit encoding a
        // degenerette lane uses. One lane, spent by the next paid craps burn; the tier rides the
        // coinflip family's wire values and the craps table pays it at 5/10/15%.
        if (boonType >= BOON_CRAPS_5) {
            uint8 newTier = boonType - BOON_CRAPS_5 + 1;
            uint256 s1 = bp.slot1;
            uint256 lane = s1 & BP_LANE_MASK;
            // A dead lane never blocks a fresh award: the deity gift path applies without
            // the box-roll expiry sweep, so liveness is re-checked here, not assumed swept.
            uint8 heldTier = _boonLaneLive(lane, uint24(currentDay))
                ? uint8(lane & BP_LANE_TIER_MASK)
                : 0;
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > heldTier) {
                uint256 stamp = (isDeity ? uint256(uint24(day)) : uint256(uint24(currentDay))) &
                    BP_LANE_DAY_MASK;
                bp.slot1 = ((s1 & ~BP_LANE_MASK) |
                    (stamp << BP_LANE_DAY_SHIFT) |
                    (isDeity ? BP_LANE_DEITY_BIT : 0) |
                    newTier) | BP_SLOT1_RETAINED;
            }
            // The value field is the rolled boonType (41-43), which names the tier directly.
            if (!isDeity) emit LootBoxReward(id, 14, originalAmount, boonType);
            return;
        }

        // Lazy pass discount boons (types 29, 30, 31) — slot1
        if (boonType == BOON_LAZY_PASS_10 || boonType == BOON_LAZY_PASS_25 || boonType == BOON_LAZY_PASS_50) {
            uint16 bps = boonType == BOON_LAZY_PASS_50
                ? LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS
                : (boonType == BOON_LAZY_PASS_25 ? LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS : LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS);
            uint256 s1 = bp.slot1;
            uint8 newTier = _lazyPassBpsToTier(bps);
            uint8 existingTier = uint8(s1 >> BP_LAZY_PASS_TIER_SHIFT);
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s1 = (s1 & ~(uint256(BP_MASK_8) << BP_LAZY_PASS_TIER_SHIFT)) | (uint256(newTier) << BP_LAZY_PASS_TIER_SHIFT);
                uint24 lazyDayVal = isDeity ? uint24(day) : uint24(currentDay);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_LAZY_PASS_DAY_SHIFT)) | (uint256(lazyDayVal) << BP_LAZY_PASS_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_LAZY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_LAZY_PASS_DAY_SHIFT);
                bp.slot1 = s1 | BP_SLOT1_RETAINED;
            }
            if (!isDeity) emit LootBoxReward(id, 11, originalAmount, bps);
        }
    }

    /// @dev Pay an activity award straight into the player's stats: `levelCount` (the
    ///      activity-score input) plus the matching quest-streak bonus. Both legs saturate
    ///      rather than revert — an award must never be able to brick a box open or a gift.
    /// @param id Award recipient's wallet ID (quest state key).
    /// @param amt Units added to the mint-level count and to the quest streak (10, 25 or 50).
    ///        The activity SCORE moves by whatever the score formula makes of them
    ///        (`_mintCountBonusPoints`, capped at 25, plus the streak-derived points).
    /// @param currentDay Day index the award is credited on.
    function _creditActivity(uint32 id, uint24 amt, uint24 currentDay) internal {
        uint256 prevData = mintPacked_[id];
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );

        uint256 countSum = uint256(levelCount) + amt;
        uint24 newLevelCount = countSum > type(uint24).max
            ? type(uint24).max
            : uint24(countSum);
        uint256 data = BitPackingLib.setPacked(
            prevData,
            BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24,
            newLevelCount
        );
        if (data != prevData) {
            mintPacked_[id] = data;
            emit MintRecorded(id, data);
        }

        quests.awardQuestStreakBonus(id, uint16(amt), currentDay);
        emit BoonConsumed(id, 5, uint16(amt));
    }

    /// @dev Weight-balanced lookup over the canonical cumulative boundaries. The split tree
    ///      averages about 4.5 comparisons per delivered boon instead of a linear walk's ~19.
    function _boonFromRoll(uint256 roll) internal pure returns (uint8) {
        if (roll < 1246) {
            if (roll < 486) {
                if (roll < 240) {
                    if (roll < 200) return BOON_COINFLIP_5;
                    return BOON_COINFLIP_10;
                }
                if (roll < 448) {
                    if (roll < 248) return BOON_COINFLIP_25;
                    return BOON_LOOTBOX_5;
                }
                if (roll < 478) return BOON_LOOTBOX_15;
                return BOON_LOOTBOX_25;
            }
            if (roll < 886) return BOON_PURCHASE_5;
            if (roll < 1070) {
                if (roll < 982) {
                    if (roll < 966) return BOON_PURCHASE_15;
                    return BOON_PURCHASE_25;
                }
                if (roll < 1022) return BOON_DECIMATOR_10;
                if (roll < 1032) {
                    if (roll < 1030) return BOON_DECIMATOR_25;
                    return BOON_DECIMATOR_50;
                }
                if (roll < 1060) return BOON_WHALE_10;
                return BOON_WHALE_20;
            }
            if (roll < 1112) {
                if (roll < 1100) {
                    if (roll < 1072) return BOON_WHALE_35;
                    return BOON_DEITY_PASS_10;
                }
                if (roll < 1110) return BOON_DEITY_PASS_20;
                return BOON_DEITY_PASS_35;
            }
            if (roll < 1212) return BOON_ACTIVITY_10;
            if (roll < 1242) return BOON_ACTIVITY_25;
            return BOON_ACTIVITY_50;
        }

        if (roll < 1948) {
            if (roll < 1688) {
                if (roll < 1478) {
                    if (roll < 1446) return BOON_QUEST_SHIELD;
                    if (roll < 1448) return BOON_WHALE_PASS;
                    return BOON_LAZY_PASS_10;
                }
                if (roll < 1488) {
                    if (roll < 1486) return BOON_LAZY_PASS_25;
                    return BOON_LAZY_PASS_50;
                }
                return BOON_DEGEN_ETH_4;
            }
            if (roll < 1748) {
                if (roll < 1738) return BOON_DEGEN_ETH_8;
                return BOON_DEGEN_ETH_12;
            }
            return BOON_DEGEN_FLIP_4;
        }

        if (roll < 2208) {
            if (roll < 2008) {
                if (roll < 1998) return BOON_DEGEN_FLIP_8;
                return BOON_DEGEN_FLIP_12;
            }
            return BOON_WWXRP_4;
        }
        if (roll < 2608) {
            if (roll < 2408) return BOON_WWXRP_8;
            return BOON_WWXRP_12;
        }
        if (roll < 2808) return BOON_CRAPS_5;
        if (roll < 2848) return BOON_CRAPS_10;
        return BOON_CRAPS_15;
    }

    /// @notice Issue a deity boon from deity account `deityId` to account `recipientId`.
    /// @dev A deity can issue up to 3 boons per day,
    ///      including several to one recipient. A deity can issue at most DEITY_RECIPIENT_BOON_CAP boons
    ///      to any one recipient over the game's lifetime. The menu uses the preceding day's
    ///      finalized RNG, so it can be previewed one game day before issuance. The deity side is
    ///      authorized under the account rule; the recipient is a third party that must already
    ///      hold an ID. Self boons are compared by ID (a deity may boon its owner or the owner's
    ///      other smurfs).
    /// @param deityId The deity account issuing the boon (0 = caller)
    /// @param recipientId The account receiving the boon (nonzero, allocated)
    /// @param slot The slot index (0-2) to use
    /// @custom:reverts NotApproved When the caller may not act for `deityId`
    /// @custom:reverts E When `deityId` or `recipientId` is unallocated, or `recipientId == 0`
    /// @custom:reverts SelfBoon When the deity account issues a boon to itself
    /// @custom:reverts InvalidSlot When slot is >= 3
    /// @custom:reverts Unauthorized When deity does not own a deity pass
    /// @custom:reverts RngNotReady When the preceding day has no finalized RNG word
    /// @custom:reverts RecipientBoonCapReached When this deity has hit the lifetime boon cap for the recipient
    /// @custom:reverts SlotAlreadyUsed When slot was already used today
    function _issueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) internal {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        deityId = _resolveAccountId(deityId);
        if (deityId == VAULT_WALLET_ID || deityId == SDGNRS_WALLET_ID) revert Unauthorized();
        // A boon is a gift: the recipient must already hold a wallet ID.
        _requireAllocated(recipientId);
        if (slot >= DEITY_DAILY_BOON_COUNT) revert InvalidSlot();
        uint256 deityWord = mintPacked_[deityId];
        if (deityWord >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 0) revert Unauthorized();
        if (deityId == recipientId) revert SelfBoon();

        uint24 day = _gameDay();
        uint256 rngWord = _recordedDailyWord(day - 1);
        if (rngWord == 0) revert GameBoxInternals.RngNotReady();
        // Day + used-mask share one slot (deityBoonPacked). On a day rollover the mask
        // starts empty: a stale day's mask is never read (every reader gates on the day
        // matching), and the single packed write below re-stamps the day with the fresh
        // mask in one store.
        uint64 boonPacked = deityBoonPacked[deityId];
        uint8 mask = uint24(boonPacked) == day ? uint8(boonPacked >> 24) : 0;
        // Lifetime cap is per (deity, recipient) pair.
        uint256 pairShift = uint256(uint8(boonPacked >> 32)) * 4;
        uint128 pairCounts = deityRecipientBoonCount[recipientId];
        uint8 pairBoonCount = uint8(pairCounts >> pairShift) & 15;
        if (pairBoonCount >= DEITY_RECIPIENT_BOON_CAP) revert RecipientBoonCapReached();

        uint8 slotMask = uint8(1) << slot;
        if ((mask & slotMask) != 0) revert SlotAlreadyUsed();
        deityBoonPacked[deityId] =
            (boonPacked & ~uint64(type(uint32).max)) | uint64(day) | (uint64(mask | slotMask) << 24);
        deityRecipientBoonCount[recipientId] = pairCounts + uint128(uint256(1) << pairShift);

        // Every menu type is always issuable — the deity roll excludes the two
        // conditionally-usable families (decimator, deity-pass) unconditionally — so
        // issuance never reverts on the rolled type.
        uint8 boonType = _deityBoonForSlot(deityId, day, slot, rngWord);
        _applyBoon(recipientId, boonType, day, day, 0, true);

        emit DeityBoonIssued(deityId, recipientId, day, slot, boonType);
    }

    /// @dev Deterministically generate a boon type for a deity's slot on a given day.
    /// @param deityId The deity's wallet ID (protocol issuers: VAULT 1, SDGNRS 2)
    /// @param day The day index
    /// @param slot The slot index (0-2)
    /// @param rngWord The preceding day's finalized word, or the award-day word
    ///                for an automatic protocol draw with no predecessor word.
    /// @return boonType The boon type (1-43; 10-12 and 20-21 are unused)
    /// @dev Static modulus + static mapping: the day's three-slot menu is fixed the moment
    ///      the preceding day's word lands. Eligibility must not reach the modulus — the issuer controls
    ///      issuance timing, so any live term here would let a deity re-map a slot by
    ///      issuing before/after a window or supply flip. Decimator AND deity-pass tiers
    ///      are excluded UNCONDITIONALLY (not eligibility-gated — that would be the same
    ///      live term): a gift slot must never arrive dead, so those types are
    ///      lootbox-only and every menu slot is always issuable to any valid recipient.
    ///      The reduced roll skips both bands arithmetically — the composed mapping is
    ///      exactly the renormalized 2,766-weight table over the same walk.
    function _deityBoonForSlot(
        uint32 deityId,
        uint24 day,
        uint8 slot,
        uint256 rngWord
    ) internal pure returns (uint8 boonType) {
        uint256 seed = uint256(EntropyLib.hash4(RngTags.DEITY_MENU, rngWord, (uint256(deityId) << 24) | day, slot));
        uint256 roll = seed %
            (BOON_WEIGHT_TOTAL - BOON_WEIGHT_DECIMATOR_ALL - BOON_WEIGHT_DEITY_PASS_ALL);
        if (roll >= BOON_WEIGHT_PRE_DECIMATOR) roll += BOON_WEIGHT_DECIMATOR_ALL;
        if (roll >= BOON_WEIGHT_PRE_DEITY_PASS) roll += BOON_WEIGHT_DEITY_PASS_ALL;
        return _boonFromRoll(roll);
    }
}
