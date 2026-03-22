// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";

/**
 * @title DegenerusGameBoonModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for boon consumption and lootbox view functions.
 *
 * @dev Split from DegenerusGameLootboxModule to stay under EIP-170 size limit.
 *      Called via `delegatecall` from DegenerusGame -- all storage reads/writes
 *      operate on the game contract's storage.
 *
 *      All boon state is packed into a 2-slot BoonPacked struct per player.
 *      Each function loads the relevant slot(s), modifies in memory, and writes
 *      back in a single SSTORE. See DegenerusGameStorage for bit layout.
 */
contract DegenerusGameBoonModule is DegenerusGameStorage {
    // =========================================================================
    // Constants
    // =========================================================================

    uint24 private constant COINFLIP_BOON_EXPIRY_DAYS = 2;
    uint24 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;
    uint24 private constant PURCHASE_BOOST_EXPIRY_DAYS = 4;
    uint24 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    IDegenerusQuests internal constant quests = IDegenerusQuests(ContractAddresses.QUESTS);

    // =========================================================================
    // Boon Consumption Functions
    // =========================================================================

    /// @notice Consume a player's coinflip boon and return the bonus BPS
    /// @param player The player address to consume boon for
    /// @return boonBps The bonus in basis points (0 if no boon, 500/1000/2500 otherwise)
    function consumeCoinflipBoon(address player) external returns (uint16 boonBps) {
        if (player == address(0)) return 0;
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
    }

    /// @notice Consume a player's purchase boost and return the bonus BPS
    /// @param player The player address to consume boost for
    /// @return boostBps The bonus in basis points (0 if no boost, 500/1500/2500 otherwise)
    function consumePurchaseBoost(address player) external returns (uint16 boostBps) {
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
    }

    // =========================================================================
    // Boon Maintenance Functions (called via nested delegatecall from LootboxModule)
    // =========================================================================

    /// @notice Clear all expired boons for a player and report if any remain active.
    /// @dev Called via nested delegatecall from LootboxModule during lootbox resolution.
    ///      Loads both packed slots (2 SLOADs), checks all boon categories for deity
    ///      and time-based expiry, clears expired fields in memory, writes back only
    ///      changed slots (at most 2 SSTOREs).
    /// @param player The player address to check and clear expired boons for
    /// @return hasAnyBoon True if the player has at least one active (non-expired) boon
    function checkAndClearExpiredBoon(address player) external returns (bool hasAnyBoon) {
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
            // Stale deity day clearing for inactive lootbox boon (matches original behavior)
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

        // --- Slot 1: Activity ---
        uint24 activityPendingLocal = uint24(s1 >> BP_ACTIVITY_PENDING_SHIFT);
        if (activityPendingLocal != 0) {
            uint24 deityDay = uint24(s1 >> BP_DEITY_ACTIVITY_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                s1 = s1 & BP_ACTIVITY_CLEAR;
                changed1 = true;
                activityPendingLocal = 0;
            } else {
                uint24 stampDay = uint24(s1 >> BP_ACTIVITY_DAY_SHIFT);
                if (stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS) {
                    s1 = s1 & BP_ACTIVITY_CLEAR;
                    changed1 = true;
                    activityPendingLocal = 0;
                }
            }
        }

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

        // Write back only changed slots
        if (changed0) bp.slot0 = s0;
        if (changed1) bp.slot1 = s1;

        return (whaleDayLocal != 0 ||
            lazyPassDayLocal != 0 ||
            coinflipTierLocal != 0 ||
            lootboxTierLocal != 0 ||
            purchaseTierLocal != 0 ||
            decimatorTierLocal != 0 ||
            activityPendingLocal != 0 ||
            deityPassTierLocal != 0);
    }

    /// @notice Consume a pending activity boon and apply it to player stats.
    /// @dev Called via nested delegatecall from LootboxModule during lootbox resolution.
    /// @param player Player address
    function consumeActivityBoon(address player) external {
        if (player == address(0)) return;
        BoonPacked storage bp = boonPacked[player];
        uint256 s1 = bp.slot1;
        uint24 pending = uint24(s1 >> BP_ACTIVITY_PENDING_SHIFT);
        if (pending == 0) return;

        uint24 currentDay = uint24(_simulatedDayIndex());
        uint24 deityDay = uint24(s1 >> BP_DEITY_ACTIVITY_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot1 = s1 & BP_ACTIVITY_CLEAR;
            return;
        }

        uint24 stampDay = uint24(s1 >> BP_ACTIVITY_DAY_SHIFT);
        if (stampDay > 0 && currentDay > stampDay + COINFLIP_BOON_EXPIRY_DAYS) {
            bp.slot1 = s1 & BP_ACTIVITY_CLEAR;
            return;
        }

        bp.slot1 = s1 & BP_ACTIVITY_CLEAR;

        uint256 prevData = mintPacked_[player];
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24
        );

        uint256 countSum = uint256(levelCount) + pending;
        uint24 newLevelCount = countSum > type(uint24).max
            ? type(uint24).max
            : uint24(countSum);
        uint256 data = prevData;
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24,
            newLevelCount
        );
        if (data != prevData) {
            mintPacked_[player] = data;
        }

        uint16 bonus = pending > type(uint16).max ? type(uint16).max : uint16(pending);
        if (currentDay != 0 && bonus != 0) {
            quests.awardQuestStreakBonus(player, bonus, currentDay);
        }
    }
}
