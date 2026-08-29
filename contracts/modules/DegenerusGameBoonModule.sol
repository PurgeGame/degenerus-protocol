// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
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
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";

/**
 * @title DegenerusGameBoonModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for boon consumption and expiry maintenance.
 *
 * @dev Consumes coinflip, purchase, and decimator boons; separately clears expired
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
contract DegenerusGameBoonModule is DegenerusGameStorage {
    // =========================================================================
    // Constants
    // =========================================================================

    uint24 private constant COINFLIP_BOON_EXPIRY_DAYS = 2;
    uint24 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;
    uint24 private constant PURCHASE_BOOST_EXPIRY_DAYS = 4;
    uint24 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    // =========================================================================
    // Boon Consumption Functions
    // =========================================================================

    /// @notice Consume a player's coinflip OR craps boon and return the bonus BPS.
    /// @dev ONE trusted selector, two lanes, named by the caller. The Game façade authorizes
    ///      exactly COIN and COINFLIP on this selector and delegatecall preserves the original
    ///      caller, so COINFLIP spends the coinflip boon on a manual deposit and COIN (FLIP)
    ///      spends the craps boon on a paid craps burn. The lanes are disjoint and neither
    ///      caller can reach the other's. Sharing the selector is what lets the craps family
    ///      ship without a byte of new code in the size-critical Game façade.
    /// @param player The player address to consume boon for
    /// @return boonBps The bonus in basis points (0 if no boon, 500/1000/2500 otherwise)
    function consumeCoinflipBoon(address player) external returns (uint16 boonBps) {
        if (player == address(0)) return 0;
        if (msg.sender == ContractAddresses.COIN) return _consumeCrapsBoon(player);
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_COINFLIP_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 currentDay = uint24(_simulatedDayIndex());
        uint24 deityDay = uint24(s0 >> BP_DEITY_COINFLIP_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot0 = s0 & BP_COINFLIP_CLEAR;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_COINFLIP_DAY_SHIFT);
        if (stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS) {
            bp.slot0 = s0 & BP_COINFLIP_CLEAR;
            return 0;
        }
        boonBps = _coinflipTierToBps(tier);
        bp.slot0 = s0 & BP_COINFLIP_CLEAR;
        emit BoonConsumed(player, 1, boonBps);
    }

    /// @dev Spend the craps lane — slot1's low 24 bits, so no shift on this path. An expired
    ///      lane pays nothing and is cleared here, matching every other consumption site.
    ///      The tier decodes 5/10/25% off the coinflip table the family mirrors.
    function _consumeCrapsBoon(address player) private returns (uint16 boonBps) {
        BoonPacked storage bp = boonPacked[player];
        uint256 s1 = bp.slot1;
        uint256 lane = s1 & BP_LANE_MASK;
        uint8 tier = uint8(lane & BP_LANE_TIER_MASK);
        if (tier == 0) return 0;
        if (!_boonLaneLive(lane, uint24(_simulatedDayIndex()))) {
            bp.slot1 = s1 & ~BP_LANE_MASK;
            return 0;
        }
        boonBps = _coinflipTierToBps(tier);
        bp.slot1 = s1 & ~BP_LANE_MASK;
        emit BoonConsumed(player, 6, boonBps);
    }

    /// @notice Consume a player's purchase boost and return the bonus BPS
    /// @dev Called via nested delegatecall from MintModule during ticket purchase.
    ///      Payable: the purchase carries its ETH as msg.value, which delegatecall
    ///      keeps in flight through this nested dispatch.
    /// @param player The player address to consume boost for
    /// @return boostBps The bonus in basis points (0 if no boost, 500/1500/2500 otherwise)
    function consumePurchaseBoost(address player) external payable returns (uint16 boostBps) {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (empty local state returns silently).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (player == address(0)) return 0;
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_PURCHASE_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 currentDay = uint24(_simulatedDayIndex());
        uint24 deityDay = uint24(s0 >> BP_DEITY_PURCHASE_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot0 = s0 & BP_PURCHASE_CLEAR;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_PURCHASE_DAY_SHIFT);
        if (stampDay > 0 && currentDay > stampDay + PURCHASE_BOOST_EXPIRY_DAYS) {
            bp.slot0 = s0 & BP_PURCHASE_CLEAR;
            return 0;
        }
        boostBps = _purchaseTierToBps(tier);
        bp.slot0 = s0 & BP_PURCHASE_CLEAR;
        emit BoonConsumed(player, 2, boostBps);
    }

    /// @notice Consume a player's decimator boost and return the bonus BPS
    /// @param player The player address to consume boost for
    /// @return boostBps The bonus in basis points (0 if no boost, 1000/2500/5000 otherwise)
    function consumeDecimatorBoost(address player) external returns (uint16 boostBps) {
        if (player == address(0)) return 0;
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_DECIMATOR_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 currentDay = uint24(_simulatedDayIndex());
        uint24 deityDay = uint24(s0 >> BP_DEITY_DECIMATOR_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot0 = s0 & BP_DECIMATOR_CLEAR;
            return 0;
        }
        boostBps = _decimatorTierToBps(tier);
        bp.slot0 = s0 & BP_DECIMATOR_CLEAR;
        emit BoonConsumed(player, 3, boostBps);
    }

    /// @notice Consume a player's degenerette stake boon for a bet in `currency`
    /// @dev Called via nested delegatecall from the Degenerette module during bet placement.
    ///      Payable: an ETH bet carries its stake as msg.value, which delegatecall keeps in
    ///      flight through this nested dispatch.
    ///
    ///      Each currency has its own independent lane; a bet reads and spends ONLY its own
    ///      currency's lane, so a WWXRP bet can never burn a held ETH boon — boons for the
    ///      other currencies are untouched by construction. An expired lane pays nothing
    ///      and is cleared here.
    /// @param player The player placing the bet
    /// @param currency The bet's currency (0=ETH, 1=FLIP, 3=WWXRP)
    /// @return boostBps The stake bonus in basis points (0 if none, else 400/800/1200)
    function consumeDegeneretteBoon(
        address player,
        uint8 currency
    ) external payable returns (uint16 boostBps) {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (empty local state returns silently).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (player == address(0)) return 0;
        BoonPacked storage bp = boonPacked[player];
        uint256 s1 = bp.slot1;
        uint256 shift = _degeneretteLaneShift(currency);
        uint256 lane = (s1 >> shift) & BP_LANE_MASK;
        uint8 tier = uint8(lane & BP_LANE_TIER_MASK);
        if (tier == 0) return 0;
        if (!_boonLaneLive(lane, uint24(_simulatedDayIndex()))) {
            bp.slot1 = s1 & ~(BP_LANE_MASK << shift);
            return 0;
        }
        boostBps = _degeneretteTierToBps(tier);
        bp.slot1 = s1 & ~(BP_LANE_MASK << shift);
        emit BoonConsumed(player, 4, boostBps);
    }

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
    /// @param player The player address to check and clear expired boons for
    /// @return hasAnyBoon True if the player has at least one active (non-expired) boon
    function checkAndClearExpiredBoon(address player) public payable returns (bool hasAnyBoon) {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (empty local state returns silently).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint24 currentDay = uint24(_simulatedDayIndex());
        BoonPacked storage bp = boonPacked[player];
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
        {
            uint24 deityWhaleDay = uint24(s0 >> BP_DEITY_WHALE_DAY_SHIFT);
            if (deityWhaleDay != 0 && deityWhaleDay != currentDay) {
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

        // --- Slot 1: Degenerette lanes (one independent boon per bet currency) ---
        bool degeneretteLive;
        for (uint256 i; i < 3; ++i) {
            uint256 laneShift = BP_DEGEN_LANE0_SHIFT + i * 24;
            uint256 lane = (s1 >> laneShift) & BP_LANE_MASK;
            if (lane & BP_LANE_TIER_MASK == 0) continue;
            if (_boonLaneLive(lane, currentDay)) {
                degeneretteLive = true;
            } else {
                s1 = s1 & ~(BP_LANE_MASK << laneShift);
                changed1 = true;
            }
        }

        // Write back only changed slots
        if (changed0) bp.slot0 = s0;
        if (changed1) bp.slot1 = s1;

        return (whaleDayLocal != 0 ||
            lazyPassDayLocal != 0 ||
            coinflipTierLocal != 0 ||
            lootboxTierLocal != 0 ||
            purchaseTierLocal != 0 ||
            decimatorTierLocal != 0 ||
            degeneretteLive ||
            crapsLive ||
            deityPassTierLocal != 0);
    }

    /// @notice Emitted when a box awards a whale pass.
    event LootBoxWhalePassJackpot(
        address indexed player,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 entriesPerLevel,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    /// @notice Emitted when a box delivers a boon-family reward.
    event LootBoxReward(
        address indexed player,
        uint8 indexed rewardType,
        uint256 lootboxAmount,
        uint256 amount
    );

    /// @notice Emitted when a box-drawn boon is discarded rather than delivered — the
    ///         statically-drawn type is permanently unusable by this player.
    event BoonDiscarded(address indexed player, uint8 boonType);

    /// @notice Emitted when a deity issues a boon to another player.
    event DeityBoonIssued(
        address indexed deity,
        address indexed recipient,
        uint24 indexed day,
        uint8 slot,
        uint8 boonType
    );

    // =========================================================================
    // Box-drawn boons (relocated from the Lootbox module)
    // =========================================================================
    //
    // The draw table, its weights and every delivery branch live here rather than in the
    // Lootbox module: this is the boon module, and that one had run out of EIP-170 headroom.
    // The Lootbox module reaches this through ONE delegatecall per entry — see `rollBoxBoons`,
    // which loops the entry's boxes internally rather than making the caller pay a call frame
    // per box.

    /// @dev Portion of lootbox EV reserved for boon/pass draw (10%)
    uint16 private constant LOOTBOX_BOON_BUDGET_BPS = 1000;
    /// @dev Maximum boon/pass budget per lootbox (1 ETH scaled)
    uint256 private constant LOOTBOX_BOON_MAX_BUDGET =
        1 ether;
    /// @dev Assumed utilization of max boon value (50%)
    uint16 private constant LOOTBOX_BOON_UTILIZATION_BPS = 5000;
    /// @dev Whale boon discount tiers 1/2/3 (10%, 20%, 35%).
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS = 1000;
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_20_BPS = 2000;
    uint16 private constant LOOTBOX_WHALE_BOON_DISCOUNT_35_BPS = 3500;
    /// @dev Lazy pass boon discount tiers (10%, 25%, 50%).
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_10_BPS = 1000;
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_25_BPS = 2500;
    uint16 private constant LOOTBOX_LAZY_PASS_DISCOUNT_50_BPS = 5000;
    /// @dev Tier identifier for 10% deity pass discount boon (1000 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_10 = 1;
    /// @dev Tier identifier for the tier-2 deity pass discount boon (20%, 2000 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_20 = 2;
    /// @dev Tier identifier for the tier-3 deity pass discount boon (35%, 3500 bps)
    uint8 private constant DEITY_PASS_BOON_TIER_35 = 3;
    /// @dev Threshold used by deity-pass discount boon availability logic.
    uint32 private constant DEITY_PASS_MAX_TOTAL = 32;
    /// @dev 5% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_BOON_BONUS_BPS = 500;
    /// @dev Maximum bonus amount for coinflip boon (5000 FLIP)
    uint256 private constant LOOTBOX_BOON_MAX_BONUS = 5000 ether;
    /// @dev Deity pass base price (used for deity discount boon EV estimation).
    uint256 private constant DEITY_PASS_BASE = 24 ether;
    /// @dev 10% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_COINFLIP_10_BONUS_BPS = 1000;
    /// @dev 25% bonus in basis points for coinflip boon
    uint16 private constant LOOTBOX_COINFLIP_25_BONUS_BPS = 2500;
    /// @dev 5% purchase boost in basis points
    uint16 private constant LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS = 500;
    /// @dev 15% purchase boost in basis points
    uint16 private constant LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS = 1500;
    /// @dev 25% purchase boost in basis points
    uint16 private constant LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS = 2500;
    /// @dev 10% decimator boost in basis points
    uint16 private constant LOOTBOX_DECIMATOR_10_BONUS_BPS = 1000;
    /// @dev 25% decimator boost in basis points
    uint16 private constant LOOTBOX_DECIMATOR_25_BONUS_BPS = 2500;
    /// @dev 50% decimator boost in basis points
    uint16 private constant LOOTBOX_DECIMATOR_50_BONUS_BPS = 5000;
    /// @dev 10 point activity boon bonus
    uint24 private constant LOOTBOX_ACTIVITY_BOON_10_BONUS = 10;
    /// @dev 25 point activity boon bonus
    uint24 private constant LOOTBOX_ACTIVITY_BOON_25_BONUS = 25;
    /// @dev 50 point activity boon bonus
    uint24 private constant LOOTBOX_ACTIVITY_BOON_50_BONUS = 50;
    /// @dev Quest-streak shields granted per quest-shield boon
    uint16 private constant LOOTBOX_QUEST_SHIELD_GRANT = 1;
    /// @dev Whale pass price (200 entries = 50 tickets over 100 levels)
    uint256 private constant LOOTBOX_WHALE_PASS_PRICE =
        4.50 ether;
    /// @dev Probability scale for granular boon rolls (ppm = 1e6).
    uint256 private constant BOON_PPM_SCALE = 1_000_000;
    /// @dev Number of boon slots available per deity per day
    uint8 private constant DEITY_DAILY_BOON_COUNT = 3;
    /// @dev Lifetime cap on deity boons a single deity may issue to a single recipient
    uint8 private constant DEITY_RECIPIENT_BOON_CAP = 10;
    /// @dev Boon type: 5% coinflip bonus
    uint8 private constant BOON_COINFLIP_5 = 1;
    /// @dev Boon type: 10% coinflip bonus
    uint8 private constant BOON_COINFLIP_10 = 2;
    /// @dev Boon type: 25% coinflip bonus
    uint8 private constant BOON_COINFLIP_25 = 3;
    /// @dev Boon type: grant one quest-streak shield
    uint8 private constant BOON_QUEST_SHIELD = 4;
    /// @dev Boon type: 5% lootbox boost
    uint8 private constant BOON_LOOTBOX_5 = 5;
    /// @dev Boon type: 15% lootbox boost
    uint8 private constant BOON_LOOTBOX_15 = 6;
    /// @dev Boon type: 5% purchase boost
    uint8 private constant BOON_PURCHASE_5 = 7;
    /// @dev Boon type: 15% purchase boost
    uint8 private constant BOON_PURCHASE_15 = 8;
    /// @dev Boon type: 25% purchase boost
    uint8 private constant BOON_PURCHASE_25 = 9;
    /// @dev Boon type: 10% decimator boost
    uint8 private constant BOON_DECIMATOR_10 = 13;
    /// @dev Boon type: 25% decimator boost
    uint8 private constant BOON_DECIMATOR_25 = 14;
    /// @dev Boon type: 50% decimator boost
    uint8 private constant BOON_DECIMATOR_50 = 15;
    /// @dev Boon type: 10% whale discount
    uint8 private constant BOON_WHALE_10 = 16;
    /// @dev Boon type: 10 point activity bonus
    uint8 private constant BOON_ACTIVITY_10 = 17;
    /// @dev Boon type: 25 point activity bonus
    uint8 private constant BOON_ACTIVITY_25 = 18;
    /// @dev Boon type: 50 point activity bonus
    uint8 private constant BOON_ACTIVITY_50 = 19;
    /// @dev Boon type: 25% lootbox boost
    uint8 private constant BOON_LOOTBOX_25 = 22;
    /// @dev Boon type: tier-2 whale discount (20%)
    uint8 private constant BOON_WHALE_20 = 23;
    /// @dev Boon type: tier-3 whale discount (35%)
    uint8 private constant BOON_WHALE_35 = 24;
    /// @dev Boon type: 10% deity pass discount
    uint8 private constant BOON_DEITY_PASS_10 = 25;
    /// @dev Boon type: tier-2 deity pass discount (20%)
    uint8 private constant BOON_DEITY_PASS_20 = 26;
    /// @dev Boon type: tier-3 deity pass discount (35%)
    uint8 private constant BOON_DEITY_PASS_35 = 27;
    /// @dev Boon type: whale pass award
    uint8 private constant BOON_WHALE_PASS = 28;
    /// @dev Boon type: 10% lazy pass discount
    uint8 private constant BOON_LAZY_PASS_10 = 29;
    /// @dev Boon type: 25% lazy pass discount
    uint8 private constant BOON_LAZY_PASS_25 = 30;
    /// @dev Boon type: 50% lazy pass discount
    uint8 private constant BOON_LAZY_PASS_50 = 31;
    /// @dev Degenerette stake boons, contiguous 32-40 (ids 10-12 and 20-21 stay free).
    ///      Each targets ONE bet currency; the tier byte written to `boonPacked` re-orders
    ///      them by value (see `_degeneretteTierToBps`).
    uint8 private constant BOON_DEGEN_ETH_4 = 32;
    uint8 private constant BOON_DEGEN_ETH_8 = 33;
    uint8 private constant BOON_DEGEN_ETH_12 = 34;
    uint8 private constant BOON_DEGEN_FLIP_4 = 35;
    uint8 private constant BOON_DEGEN_FLIP_8 = 36;
    uint8 private constant BOON_DEGEN_FLIP_12 = 37;
    uint8 private constant BOON_DEGEN_WWXRP_4 = 38;
    uint8 private constant BOON_DEGEN_WWXRP_8 = 39;
    uint8 private constant BOON_DEGEN_WWXRP_12 = 40;
    /// @dev Craps stake boons. A successful self-funded craps purchase burns in full and carries
    ///      the boon onto its slip; the tier then boosts that slip's BANKROLL RETURN by 5/10/25%
    ///      when it settles, off a base capped at 60,000 FLIP. Nothing is credited at entry, and a
    ///      busted run pays no bonus.
    uint8 private constant BOON_CRAPS_5 = 41;
    uint8 private constant BOON_CRAPS_10 = 42;
    uint8 private constant BOON_CRAPS_25 = 43;
    /// @dev Weight for 5% coinflip boon
    uint16 private constant BOON_WEIGHT_COINFLIP_5 = 200;
    /// @dev Weight for 10% coinflip boon
    uint16 private constant BOON_WEIGHT_COINFLIP_10 = 40;
    /// @dev Weight for 25% coinflip boon
    uint16 private constant BOON_WEIGHT_COINFLIP_25 = 8;
    /// @dev Weight for 5% lootbox boost boon
    uint16 private constant BOON_WEIGHT_LOOTBOX_5 = 200;
    /// @dev Weight for 15% lootbox boost boon
    uint16 private constant BOON_WEIGHT_LOOTBOX_15 = 30;
    /// @dev Weight for 25% lootbox boost boon
    uint16 private constant BOON_WEIGHT_LOOTBOX_25 = 8;
    /// @dev Weight for 5% purchase boost boon
    uint16 private constant BOON_WEIGHT_PURCHASE_5 = 400;
    /// @dev Weight for 15% purchase boost boon
    uint16 private constant BOON_WEIGHT_PURCHASE_15 = 80;
    /// @dev Weight for 25% purchase boost boon
    uint16 private constant BOON_WEIGHT_PURCHASE_25 = 16;
    /// @dev Weight for 10% decimator boost boon
    uint16 private constant BOON_WEIGHT_DECIMATOR_10 = 40;
    /// @dev Weight for 25% decimator boost boon
    uint16 private constant BOON_WEIGHT_DECIMATOR_25 = 8;
    /// @dev Weight for 50% decimator boost boon
    uint16 private constant BOON_WEIGHT_DECIMATOR_50 = 2;
    /// @dev Weight for 10% whale boon
    uint16 private constant BOON_WEIGHT_WHALE_10 = 28;
    /// @dev Weight for tier-2 whale boon (20%)
    uint16 private constant BOON_WEIGHT_WHALE_20 = 10;
    /// @dev Weight for tier-3 whale boon (35%)
    uint16 private constant BOON_WEIGHT_WHALE_35 = 2;
    /// @dev Weight for 10% deity pass discount boon
    uint16 private constant BOON_WEIGHT_DEITY_PASS_10 = 28;
    /// @dev Weight for tier-2 deity pass discount boon (20%)
    uint16 private constant BOON_WEIGHT_DEITY_PASS_20 = 10;
    /// @dev Weight for tier-3 deity pass discount boon (35%)
    uint16 private constant BOON_WEIGHT_DEITY_PASS_35 = 2;
    /// @dev Weight for 10 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_10 = 100;
    /// @dev Weight for 25 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_25 = 30;
    /// @dev Weight for 50 point activity boon
    uint16 private constant BOON_WEIGHT_ACTIVITY_50 = 4;
    /// @dev Weight for the quest-streak-shield boon
    uint16 private constant BOON_WEIGHT_QUEST_SHIELD = 200;
    /// @dev Weight for whale pass award
    uint16 private constant BOON_WEIGHT_WHALE_PASS = 2;
    /// @dev Weight for 10% lazy pass discount boon
    uint16 private constant BOON_WEIGHT_LAZY_PASS_10 = 30;
    /// @dev Weight for 25% lazy pass discount boon
    uint16 private constant BOON_WEIGHT_LAZY_PASS_25 = 8;
    /// @dev Weight for 50% lazy pass discount boon
    uint16 private constant BOON_WEIGHT_LAZY_PASS_50 = 2;
    /// @dev Combined weight of deity pass discount boons (10% + 25% + 50%)
    uint16 private constant BOON_WEIGHT_DEITY_PASS_ALL = 40;
    /// @dev Weights for the degenerette stake boons. ETH and FLIP taper hard (200/50/10)
    ///      because their stake bonus is real value; WWXRP sits flat at 200 across all three
    ///      tiers — it is worthless by design, so a bigger WWXRP boon costs the game nothing.
    uint16 private constant BOON_WEIGHT_DEGEN_ETH_4 = 200;
    uint16 private constant BOON_WEIGHT_DEGEN_ETH_8 = 50;
    uint16 private constant BOON_WEIGHT_DEGEN_ETH_12 = 10;
    uint16 private constant BOON_WEIGHT_DEGEN_FLIP_4 = 200;
    uint16 private constant BOON_WEIGHT_DEGEN_FLIP_8 = 50;
    uint16 private constant BOON_WEIGHT_DEGEN_FLIP_12 = 10;
    uint16 private constant BOON_WEIGHT_DEGEN_WWXRP_4 = 200;
    uint16 private constant BOON_WEIGHT_DEGEN_WWXRP_8 = 200;
    uint16 private constant BOON_WEIGHT_DEGEN_WWXRP_12 = 200;
    /// @dev Craps stake-boon weights, taken from the coinflip family they mirror.
    uint16 private constant BOON_WEIGHT_CRAPS_5 = 200;
    uint16 private constant BOON_WEIGHT_CRAPS_10 = 40;
    uint16 private constant BOON_WEIGHT_CRAPS_25 = 8;
    /// @dev Fixed nominal deity-pass price for the boon-chance normalization (mid-curve k=16:
    ///      BASE + 16·17/2 ether). The live triangular price is collectively player-movable
    ///      (pass purchases), so it must not reach `totalChance` — a constant keeps the hit
    ///      boundary a pure function of committed inputs. The mis-pricing only moves boon
    ///      FREQUENCY, never a payout amount, and is bounded by the deity tiers' 40/2856
    ///      weight share.
    uint256 private constant DEITY_PASS_NOMINAL_PRICE = DEITY_PASS_BASE + 136 ether;
    /// @dev Total weight sum when decimator boons are allowed (includes the +200 quest-shield weight)
    ///      The three craps families are appended at the TAIL of the walk (band 2608..2855), so
    ///      every boundary below them is unmoved and the deity roll's two skip bands
    ///      (pre-decimator, pre-deity-pass) need no adjustment.
    uint16 private constant BOON_WEIGHT_TOTAL = 2856;
    /// @dev Exact closed form of the weighted max-value table used to normalize boon frequency.
    ///      Every fixed-price family contributes 1568 ETH of weight*value; every FLIP-priced
    ///      family collapses to 3270 times the live ticket price; lazy discounts collapse to
    ///      6 times the ten-level lazy-pass value. Activity, quest-shield and WWXRP boons carry
    ///      weight but intentionally contribute zero value.
    uint256 private constant BOON_FIXED_WEIGHTED_MAX = 1568 ether;
    uint256 private constant BOON_PRICE_WEIGHT = 4230;
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
    /// @dev Cursor position where the decimator band starts in the `_boonFromRoll` walk
    ///      (sum of the coinflip + lootbox + purchase weights ahead of it).
    uint16 private constant BOON_WEIGHT_PRE_DECIMATOR = 982;
    /// @dev Combined weight of the three decimator tiers (a band the deity roll skips).
    uint16 private constant BOON_WEIGHT_DECIMATOR_ALL = 50;
    /// @dev Cursor position where the deity-pass band starts (pre-dec 982 + dec 50 +
    ///      whale-discount 40), in full-table coordinates after the dec skip re-adds 50.
    uint16 private constant BOON_WEIGHT_PRE_DEITY_PASS = 1072;
    uint32 private constant WHALE_PASS_ENTRIES_PER_LEVEL = 2;

    /// @dev Convert FLIP amount to ETH value using current price (`priceWei` is
    ///      always a non-zero price-table constant).
    function _flipToEthValue(
        uint256 flipAmount,
        uint256 priceWei
    ) private pure returns (uint256 valueWei) {
        if (flipAmount == 0) return 0;
        valueWei = (flipAmount * priceWei) / PRICE_COIN_UNIT;
    }

    /// @dev Coinflip boon cap for max deposit (100k FLIP) used in EV estimation.
    uint256 private constant COINFLIP_BOON_MAX_DEPOSIT = 100_000 ether;

    /// @dev Decimator boon cap for base amount (50k FLIP) used in EV estimation.
    uint256 private constant DECIMATOR_BOON_CAP = 50_000 ether;

    /// @dev 15% lootbox boost in basis points
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500;

    /// @dev 25% lootbox boost in basis points
    uint16 private constant LOOTBOX_BOOST_25_BONUS_BPS = 2500;

    /// @dev Whale pass standard entries per level (4 entries = 1 ticket). Reported in the
    ///      LootBoxWhalePassJackpot event for downstream indexers; the
    ///      actual ticket materialization happens in claimWhalePass.
    /// @dev 5% lootbox boost in basis points
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500;

    /// @dev Whale pass standard price (used for whale discount boon EV estimation).
    uint256 private constant WHALE_PASS_STANDARD_PRICE =
        4 ether;

    error SelfBoon(); // deity attempted to issue a boon to themselves
    error InvalidSlot(); // deity boon slot index is >= DEITY_DAILY_BOON_COUNT
    error RecipientAlreadyBoonedToday(); // recipient already received a deity boon on the current day
    error RecipientBoonCapReached(); // recipient hit the lifetime cap on boons from this deity
    error SlotAlreadyUsed(); // deity boon slot has already been used on the current day
    error RngNotReady(); // deity boon requested before the day's word landed

    /// @notice Draw boons for every box in one opened entry.
    /// @dev Delegatecall entrypoint from the Lootbox module; runs in the Game's storage context.
    ///      ONE call covers the whole entry: the caller passes how many boxes it rolled and the
    ///      per-box budget, and the loop lives here. Under the count model an entry can hold a
    ///      hundred boxes, and a call frame per box — each of which used to make up to two
    ///      delegatecalls of its own for expiry and activity — is the cost this collapses.
    ///
    ///      Each box still gets its OWN draw off a counter-tagged seed, so a box is a bet here
    ///      too; what is shared is the frame, not the outcome.
    /// @param player Box owner.
    /// @param perBoxBudget Boon budget of a single box, in wei of ETH-equivalent value.
    /// @param boxCount Boxes rolled in this entry.
    /// @param originalAmount One box's resolution amount, for the reward events.
    /// @param currentLevel Open level (level + 1), threaded from the resolver.
    /// @param seed Player-mixed entry seed; box i draws off `hash2(seed, nonceBase + i)`.
    /// @param nonceBase Global box position of this batch's first box within its entry, so two
    ///        tiers of one entry can never share a draw index (and therefore a roll value).
    function rollBoxBoons(
        address player,
        uint256 perBoxBudget,
        uint256 boxCount,
        uint256 originalAmount,
        uint24 currentLevel,
        uint256 seed,
        uint256 nonceBase
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (perBoxBudget == 0 || boxCount == 0) return;

        (uint256 expectedPerBoon, uint24 currentDay) = _boxBoonContext(player, currentLevel);
        if (expectedPerBoon == 0) return;
        _rollBoxBoonLane(
            player,
            perBoxBudget,
            boxCount,
            originalAmount,
            seed,
            nonceBase,
            expectedPerBoon,
            currentDay
        );
    }

    /// @notice Draw boons for every populated tier in one mixed box order.
    /// @dev Counts are five packed uint8 lanes in small/medium/large/custom/cover order. Amounts
    ///      remain independent: each lane computes its own capped chance, preserving the current
    ///      saturation economics exactly. Nonces advance cumulatively in the same tier order.
    function rollBoxBoonTiers(
        address player,
        uint256[5] calldata amounts,
        uint40 countsPacked,
        uint24 currentLevel,
        uint256 seed
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (countsPacked == 0) return;

        (uint256 expectedPerBoon, uint24 currentDay) = _boxBoonContext(player, currentLevel);
        if (expectedPerBoon == 0) return;

        uint256 nonceBase;
        for (uint256 lane; lane < 5; ) {
            uint256 count = uint8(countsPacked >> (lane * 8));
            uint256 amount = amounts[lane];
            if (count != 0 && amount != 0) {
                _rollBoxBoonLane(
                    player,
                    _boxBoonBudget(amount),
                    count,
                    amount,
                    seed,
                    nonceBase,
                    expectedPerBoon,
                    currentDay
                );
                nonceBase += count;
            }
            unchecked {
                ++lane;
            }
        }
    }

    /// @dev Clear expiry and derive the immutable-for-this-entry normalization once.
    function _boxBoonContext(
        address player,
        uint24 currentLevel
    ) private returns (uint256 expectedPerBoon, uint24 currentDay) {

        // Expiry cleanup runs ONCE for the entry, not once per box: it is a property of the
        // player's held boons, which no draw below changes in a way that would re-arm it.
        BoonPacked storage bp = boonPacked[player];
        if (bp.slot0 != 0 || bp.slot1 != 0) checkAndClearExpiredBoon(player);

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
        address player,
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
            uint256 roll = uint32(EntropyLib.hash2(seed, nonceBase + i) >> 120) %
                BOON_PPM_SCALE;
            if (roll < totalChance) {
                _deliverBoon(
                    player,
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

    function _boxBoonBudget(uint256 amount) private pure returns (uint256 boonBudget) {
        boonBudget = (amount * LOOTBOX_BOON_BUDGET_BPS) / 10_000;
        if (boonBudget > LOOTBOX_BOON_MAX_BUDGET) boonBudget = LOOTBOX_BOON_MAX_BUDGET;
    }


    /// @dev Keep-or-discard delivery filter for a lootbox-drawn boon. The TYPE is already
    ///      fixed (static table); live state may only decide whether the known outcome is
    ///      delivered. A discard writes nothing — occupying the category slot with a dead
    ///      boon would block a later useful one under upgrade-only semantics — and emits
    ///      `BoonDiscarded` so indexers keep the full draw history.
    ///
    ///      Only PERMANENTLY dead types are discarded, and only the deity-pass family
    ///      qualifies: the recipient already holds a pass, or supply is capped, so no future
    ///      state makes the discount spendable. Decimator tiers are always delivered even
    ///      outside a burn window — a lootbox-sourced decimator boon carries NO time expiry
    ///      (BoonModule: "no time expiry, only deity day"), so it simply waits for the next
    ///      window; discarding it would destroy a bankable reward. Every other type is
    ///      likewise always deliverable — lazy boons bypass the purchase level gate at
    ///      consumption, so no level condition exists for them.
    function _deliverBoon(
        address player,
        uint8 boonType,
        uint24 currentDay,
        uint256 originalAmount
    ) private {
        if (boonType >= BOON_DEITY_PASS_10 && boonType <= BOON_DEITY_PASS_35) {
            if (
                mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 1 ||
                deityPassOwners.length >= DEITY_PASS_MAX_TOTAL
            ) {
                emit BoonDiscarded(player, boonType);
                return;
            }
        }
        _applyBoon(player, boonType, 0, currentDay, originalAmount, false);
    }

    /// @dev Apply a boon to a player. Handles both lootbox-sourced and deity-sourced boons.
    ///      Both sources use upgrade semantics (only if higher tier/amount).
    ///      Lootbox boons: emit events, deity day = 0.
    ///      Deity boons: no events, deity day = day.
    ///      All boon state is stored in boonPacked[player] (2-slot packed struct).
    ///      Players can hold one boon per category simultaneously (8 categories).
    ///      Isolated bit fields per category -- applying a boon in one category cannot
    ///      affect another category's bits (targeted bitmask operations: & ~mask | value).
    function _applyBoon(
        address player,
        uint8 boonType,
        uint24 day,
        uint24 currentDay,
        uint256 originalAmount,
        bool isDeity
    ) private {
        // Every state-touching branch below resolves the same per-player record; derive its
        // storage slot once (a pointer, not a cached value — reads stay live). The two
        // slot-less branches (quest-shield, whale-pass) simply never touch it.
        BoonPacked storage bp = boonPacked[player];
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
                // Set coinflipDay = currentDay
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_COINFLIP_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_COINFLIP_DAY_SHIFT);
                // Set deityCoinflipDay = isDeity ? day : 0
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_COINFLIP_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_COINFLIP_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) emit LootBoxReward(player, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS);
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
                // Clear lootbox fields, set new values
                s0 = s0 & BP_LOOTBOX_CLEAR;
                s0 = s0 | (uint256(uint24(currentDay)) << BP_LOOTBOX_DAY_SHIFT);
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = s0 | (uint256(deityDayVal) << BP_DEITY_LOOTBOX_DAY_SHIFT);
                s0 = s0 | (uint256(activeTier) << BP_LOOTBOX_TIER_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) {
                // Map active tier back to BPS and rewardType for event
                uint16 activeBps = _lootboxTierToBps(activeTier);
                uint8 rewardType = activeTier == 3 ? 6 : (activeTier == 2 ? 5 : 4);
                emit LootBoxReward(player, rewardType, originalAmount, activeBps);
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
                // Set purchaseDay = currentDay
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_PURCHASE_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_PURCHASE_DAY_SHIFT);
                // Set deityPurchaseDay
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_PURCHASE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_PURCHASE_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) {
                uint8 rewardType = bps == LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS
                    ? 6 : (bps == LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS ? 5 : 4);
                emit LootBoxReward(player, rewardType, originalAmount, bps);
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
                // Set deityDecimatorDay (no award day for decimator)
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_DECIMATOR_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DECIMATOR_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) emit LootBoxReward(player, 8, originalAmount, bps);
            return;
        }

        // Whale discount boons (types 16, 23, 24) — slot0
        if (boonType == BOON_WHALE_10 || boonType == BOON_WHALE_20 || boonType == BOON_WHALE_35) {
            uint16 bps = boonType == BOON_WHALE_35
                ? LOOTBOX_WHALE_BOON_DISCOUNT_35_BPS
                : (boonType == BOON_WHALE_20 ? LOOTBOX_WHALE_BOON_DISCOUNT_20_BPS : LOOTBOX_WHALE_BOON_DISCOUNT_10_BPS);
            uint256 s0 = bp.slot0;
            uint8 newTier = _whaleBpsToTier(bps);
            uint8 existingTier = uint8(s0 >> BP_WHALE_TIER_SHIFT);
            // Only a genuine tier upgrade applies the boon and (re)sets its expiry; an
            // ignored lower/equal-tier roll is a no-op and must not refresh the timer.
            if (newTier > existingTier) {
                s0 = (s0 & ~(uint256(BP_MASK_8) << BP_WHALE_TIER_SHIFT)) | (uint256(newTier) << BP_WHALE_TIER_SHIFT);
                // whaleDay = isDeity ? day : currentDay
                uint24 whaleDayVal = isDeity ? uint24(day) : uint24(currentDay);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_WHALE_DAY_SHIFT)) | (uint256(whaleDayVal) << BP_WHALE_DAY_SHIFT);
                // deityWhaleDay = isDeity ? day : 0
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s0 = (s0 & ~(uint256(BP_MASK_24) << BP_DEITY_WHALE_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_WHALE_DAY_SHIFT);
                bp.slot0 = s0;
            }
            if (!isDeity) emit LootBoxReward(player, 9, originalAmount, bps);
            return;
        }

        // Quest-streak-shield boon (type 4) — instant grant, no boon-mapping state.
        // Runs in GAME's delegatecall context, so the call to QUESTS is GAME-authorized.
        if (boonType == BOON_QUEST_SHIELD) {
            IDegenerusQuests(ContractAddresses.QUESTS).awardQuestStreakShield(player, LOOTBOX_QUEST_SHIELD_GRANT);
            if (!isDeity) emit LootBoxReward(player, 12, originalAmount, LOOTBOX_QUEST_SHIELD_GRANT);
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
            _creditActivity(player, amt, currentDay);
            if (!isDeity) emit LootBoxReward(player, 10, originalAmount, amt);
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
                // Set deityPassDay = currentDay
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_PASS_DAY_SHIFT)) | (uint256(uint24(currentDay)) << BP_DEITY_PASS_DAY_SHIFT);
                // Set deityDeityPassDay
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_DEITY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_DEITY_PASS_DAY_SHIFT);
                bp.slot1 = s1;
            }
            if (!isDeity) {
                uint16 bps = tier == DEITY_PASS_BOON_TIER_35 ? 3500 : (tier == DEITY_PASS_BOON_TIER_20 ? 2000 : 1000);
                emit LootBoxReward(player, 10, originalAmount, bps);
            }
            return;
        }

        // Whale pass (type 28) — no boon mapping access, delegates to _activateWhalePass
        if (boonType == BOON_WHALE_PASS) {
            _activateWhalePass(player);
            if (!isDeity) {
                // `level + 1` records the level AT BOX-OPEN TIME for indexers;
                // actual ticket queuing is deferred to claim-time, so the queued
                // tickets start at the level when the player calls claimWhalePass —
                // not necessarily `level + 1` here.
                emit LootBoxWhalePassJackpot(player, originalAmount, level + 1, WHALE_PASS_ENTRIES_PER_LEVEL, 0, 0);
            }
            return;
        }

        // Degenerette stake boons (types 32-40) — slot1, one independent 24-bit lane per
        // bet currency (ETH / FLIP / WWXRP). A roll competes ONLY within its own currency's
        // lane, so boons for different currencies coexist and a held boon is never displaced
        // by one of another currency. The boon is spent by the next bet in ITS OWN currency.
        if (boonType >= BOON_DEGEN_ETH_4 && boonType <= BOON_DEGEN_WWXRP_12) {
            // 32/33/34 -> ETH lane, 35/36/37 -> FLIP lane, 38/39/40 -> WWXRP lane;
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
                bp.slot1 = (s1 & ~(BP_LANE_MASK << laneShift)) | (fresh << laneShift);
            }
            if (!isDeity) {
                // The value field is the rolled boonType itself (32-40): unlike bps —
                // identical across currencies — it identifies both the currency and size.
                emit LootBoxReward(player, 13, originalAmount, boonType);
            }
            return;
        }

        // Craps stake boons (types 41-43) — slot1's LOW lane, the same 24-bit encoding a
        // degenerette lane uses. One lane, spent by the next paid craps burn; the tier decodes
        // 5/10/25% off the coinflip table this family mirrors.
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
                bp.slot1 = (s1 & ~BP_LANE_MASK) |
                    (stamp << BP_LANE_DAY_SHIFT) |
                    (isDeity ? BP_LANE_DEITY_BIT : 0) |
                    newTier;
            }
            // The value field is the rolled boonType (41-43), which names the tier directly.
            if (!isDeity) emit LootBoxReward(player, 14, originalAmount, boonType);
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
                // lazyPassDay = isDeity ? day : currentDay
                uint24 lazyDayVal = isDeity ? uint24(day) : uint24(currentDay);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_LAZY_PASS_DAY_SHIFT)) | (uint256(lazyDayVal) << BP_LAZY_PASS_DAY_SHIFT);
                // deityLazyPassDay = isDeity ? day : 0
                uint24 deityDayVal = isDeity ? uint24(day) : uint24(0);
                s1 = (s1 & ~(uint256(BP_MASK_24) << BP_DEITY_LAZY_PASS_DAY_SHIFT)) | (uint256(deityDayVal) << BP_DEITY_LAZY_PASS_DAY_SHIFT);
                bp.slot1 = s1;
            }
            if (!isDeity) emit LootBoxReward(player, 11, originalAmount, bps);
        }
    }

    /// @dev Pay an activity award straight into the player's stats: `levelCount` (the
    ///      activity-score input) plus the matching quest-streak bonus. Both legs saturate
    ///      rather than revert — an award must never be able to brick a box open or a gift.
    /// @param player Award recipient.
    /// @param amt Activity points awarded (10, 25 or 50).
    /// @param currentDay Day index the award is credited on.
    function _creditActivity(address player, uint24 amt, uint24 currentDay) private {
        uint256 prevData = mintPacked_[player];
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
            mintPacked_[player] = data;
            emit MintRecorded(player, data);
        }

        quests.awardQuestStreakBonus(player, uint16(amt), currentDay);
        emit BoonConsumed(player, 5, uint16(amt));
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
            return BOON_DEGEN_WWXRP_4;
        }
        if (roll < 2608) {
            if (roll < 2408) return BOON_DEGEN_WWXRP_8;
            return BOON_DEGEN_WWXRP_12;
        }
        if (roll < 2808) return BOON_CRAPS_5;
        if (roll < 2848) return BOON_CRAPS_10;
        return BOON_CRAPS_25;
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
        // Preserve the old unchecked uint24-wrap behavior at the mathematical type boundary.
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

    /// @dev Activate a 100-level whale pass for a player by recording an O(1)
    ///      pending claim. Opens are uniform O(1) regardless of pass status.
    ///      Materialization (stats + 100 levels × tickets) is deferred to the
    ///      player-paid `claimWhalePass` endpoint, where the stats helper is
    ///      applied immediately after the read-then-zero of `whalePassClaims[player]`.
    function _activateWhalePass(address player) private {
        // O(1) record of one half-pass claim.
        whalePassClaims[player] += 1;
    }

    /// @notice Issue a deity boon to a recipient
    /// @dev Deity can issue up to 3 boons per day, one per recipient per day.
    ///      A deity can issue at most DEITY_RECIPIENT_BOON_CAP boons to any one
    ///      recipient over the game's lifetime.
    /// @param deity The deity pass holder issuing the boon
    /// @param recipient The player receiving the boon
    /// @param slot The slot index (0-2) to use
    /// @custom:reverts ZeroAddress When deity or recipient is zero address
    /// @custom:reverts SelfBoon When deity tries to issue boon to themselves
    /// @custom:reverts InvalidSlot When slot is >= 3
    /// @custom:reverts Unauthorized When deity does not own a deity pass
    /// @custom:reverts RngNotReady When no RNG is available for the day
    /// @custom:reverts RecipientAlreadyBoonedToday When recipient already received a boon today
    /// @custom:reverts RecipientBoonCapReached When this deity has hit the lifetime boon cap for the recipient
    /// @custom:reverts SlotAlreadyUsed When slot was already used today
    function issueDeityBoon(address deity, address recipient, uint8 slot) external {
        if (deity == address(0) || recipient == address(0)) revert ZeroAddress();
        if (deity == recipient) revert SelfBoon();
        if (slot >= DEITY_DAILY_BOON_COUNT) revert InvalidSlot();
        if (mintPacked_[deity] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 == 0) revert Unauthorized();

        uint24 day = _simulatedDayIndex();
        uint256 rngWord = rngWordByDay[day];
        if (rngWord == 0) revert RngNotReady();
        // Day + used-mask share one slot (deityBoonPacked). On a day rollover the mask
        // starts empty: a stale day's mask is never read (every reader gates on the day
        // matching), and the single packed write below re-stamps the day with the fresh
        // mask in one store.
        uint32 boonPacked = deityBoonPacked[deity];
        uint8 mask = uint24(boonPacked) == day ? uint8(boonPacked >> 24) : 0;
        // One boon per recipient per day, across all deities.
        if (deityBoonRecipientDay[recipient] == day) revert RecipientAlreadyBoonedToday();
        // Lifetime cap is per (deity, recipient) pair.
        uint8 pairBoonCount = deityRecipientBoonCount[deity][recipient];
        if (pairBoonCount >= DEITY_RECIPIENT_BOON_CAP) revert RecipientBoonCapReached();

        uint8 slotMask = uint8(1) << slot;
        if ((mask & slotMask) != 0) revert SlotAlreadyUsed();
        deityBoonPacked[deity] =
            uint32(day) |
            (uint32(mask | slotMask) << 24);
        deityBoonRecipientDay[recipient] = day;
        deityRecipientBoonCount[deity][recipient] = pairBoonCount + 1;

        // Every menu type is always issuable — the deity roll excludes the two
        // conditionally-usable families (decimator, deity-pass) unconditionally — so
        // issuance never reverts on the rolled type.
        uint8 boonType = _deityBoonForSlot(deity, day, slot, rngWord);
        _applyBoon(recipient, boonType, day, day, 0, true);

        emit DeityBoonIssued(deity, recipient, day, slot, boonType);
    }

    /// @dev Deterministically generate a boon type for a deity's slot on a given day.
    /// @param deity The deity address
    /// @param day The day index
    /// @param slot The slot index (0-2)
    /// @param rngWord The day's VRF word (`rngWordByDay[day]`, nonzero-checked by the caller)
    /// @return boonType The boon type (1-43; 10-12 and 20-21 are unused)
    /// @dev Static modulus + static mapping: the day's three-slot menu is fixed the moment
    ///      the word lands. Eligibility must not reach the modulus — the issuer controls
    ///      issuance timing, so any live term here would let a deity re-map a slot by
    ///      issuing before/after a window or supply flip. Decimator AND deity-pass tiers
    ///      are excluded UNCONDITIONALLY (not eligibility-gated — that would be the same
    ///      live term): a gift slot must never arrive dead, so those types are
    ///      lootbox-only and every menu slot is always issuable to any valid recipient.
    ///      The reduced roll skips both bands arithmetically — the composed mapping is
    ///      exactly the renormalized 2,766-weight table over the same walk.
    function _deityBoonForSlot(
        address deity,
        uint24 day,
        uint8 slot,
        uint256 rngWord
    ) private pure returns (uint8 boonType) {
        uint256 seed = uint256(keccak256(abi.encode(rngWord, deity, day, slot)));
        uint256 roll = seed %
            (BOON_WEIGHT_TOTAL - BOON_WEIGHT_DECIMATOR_ALL - BOON_WEIGHT_DEITY_PASS_ALL);
        if (roll >= BOON_WEIGHT_PRE_DECIMATOR) roll += BOON_WEIGHT_DECIMATOR_ALL;
        if (roll >= BOON_WEIGHT_PRE_DEITY_PASS) roll += BOON_WEIGHT_DEITY_PASS_ALL;
        return _boonFromRoll(roll);
    }

}
