// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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
 *      Called via `delegatecall` from DegenerusGame — all storage reads/writes
 *      operate on the game contract's storage.
 */
contract DegenerusGameBoonModule is DegenerusGameStorage {
    // =========================================================================
    // Constants
    // =========================================================================

    uint48 private constant COINFLIP_BOON_EXPIRY_SECONDS = 172800;
    uint48 private constant LOOTBOX_BOOST_EXPIRY_SECONDS = 172800;
    uint48 private constant PURCHASE_BOOST_EXPIRY_SECONDS = 345600;

    IDegenerusQuests internal constant quests = IDegenerusQuests(ContractAddresses.QUESTS);

    // =========================================================================
    // Boon Consumption Functions
    // =========================================================================

    /// @notice Consume a player's coinflip boon and return the bonus BPS
    /// @param player The player address to consume boon for
    /// @return boonBps The bonus in basis points (0 if no boon, 500/1000/2500 otherwise)
    function consumeCoinflipBoon(address player) external returns (uint16 boonBps) {
        if (player == address(0)) return 0;
        uint48 nowTs = uint48(block.timestamp);
        uint48 currentDay = _simulatedDayIndexAt(nowTs);
        uint48 deityDay = deityCoinflipBoonDay[player];
        if (deityDay != 0 && deityDay != currentDay) {
            coinflipBoonBps[player] = 0;
            coinflipBoonTimestamp[player] = 0;
            deityCoinflipBoonDay[player] = 0;
            return 0;
        }
        uint48 ts = coinflipBoonTimestamp[player];
        if (ts > 0 && uint256(nowTs) > uint256(ts) + COINFLIP_BOON_EXPIRY_SECONDS) {
            coinflipBoonBps[player] = 0;
            coinflipBoonTimestamp[player] = 0;
            deityCoinflipBoonDay[player] = 0;
            return 0;
        }
        boonBps = coinflipBoonBps[player];
        if (boonBps == 0) return 0;
        coinflipBoonBps[player] = 0;
        coinflipBoonTimestamp[player] = 0;
        deityCoinflipBoonDay[player] = 0;
    }

    /// @notice Consume a player's purchase boost and return the bonus BPS
    /// @param player The player address to consume boost for
    /// @return boostBps The bonus in basis points (0 if no boost, 500/1500/2500 otherwise)
    function consumePurchaseBoost(address player) external returns (uint16 boostBps) {
        if (player == address(0)) return 0;
        uint48 nowTs = uint48(block.timestamp);
        uint48 currentDay = _simulatedDayIndexAt(nowTs);
        uint48 deityDay = deityPurchaseBoostDay[player];
        if (deityDay != 0 && deityDay != currentDay) {
            purchaseBoostBps[player] = 0;
            purchaseBoostTimestamp[player] = 0;
            deityPurchaseBoostDay[player] = 0;
            return 0;
        }
        uint48 ts = purchaseBoostTimestamp[player];
        if (ts > 0 && uint256(nowTs) > uint256(ts) + PURCHASE_BOOST_EXPIRY_SECONDS) {
            purchaseBoostBps[player] = 0;
            purchaseBoostTimestamp[player] = 0;
            deityPurchaseBoostDay[player] = 0;
            return 0;
        }
        boostBps = purchaseBoostBps[player];
        if (boostBps == 0) return 0;
        purchaseBoostBps[player] = 0;
        purchaseBoostTimestamp[player] = 0;
        deityPurchaseBoostDay[player] = 0;
    }

    /// @notice Consume a player's decimator boost and return the bonus BPS
    /// @param player The player address to consume boost for
    /// @return boostBps The bonus in basis points (0 if no boost, 1000/2500/5000 otherwise)
    function consumeDecimatorBoost(address player) external returns (uint16 boostBps) {
        if (player == address(0)) return 0;
        uint48 currentDay = _simulatedDayIndex();
        uint48 deityDay = deityDecimatorBoostDay[player];
        if (deityDay != 0 && deityDay != currentDay) {
            decimatorBoostBps[player] = 0;
            deityDecimatorBoostDay[player] = 0;
            return 0;
        }
        boostBps = decimatorBoostBps[player];
        if (boostBps == 0) return 0;
        decimatorBoostBps[player] = 0;
        deityDecimatorBoostDay[player] = 0;
    }

    // =========================================================================
    // Boon Maintenance Functions (called via nested delegatecall from LootboxModule)
    // =========================================================================

    /// @notice Clear all expired boons for a player and report if any remain active.
    /// @dev Called via nested delegatecall from LootboxModule during lootbox resolution.
    /// @param player The player address to check and clear expired boons for
    /// @return hasAnyBoon True if the player has at least one active (non-expired) boon
    function checkAndClearExpiredBoon(address player) external returns (bool hasAnyBoon) {
        uint256 nowTs = block.timestamp;
        uint48 currentDay = _simulatedDayIndexAt(uint48(nowTs));

        uint16 coinflipBps = coinflipBoonBps[player];
        if (coinflipBps != 0) {
            uint48 deityDay = deityCoinflipBoonDay[player];
            if (deityDay != 0 && deityDay != currentDay) {
                coinflipBoonBps[player] = 0;
                coinflipBoonTimestamp[player] = 0;
                deityCoinflipBoonDay[player] = 0;
                coinflipBps = 0;
            } else {
                uint48 ts = coinflipBoonTimestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + COINFLIP_BOON_EXPIRY_SECONDS) {
                    coinflipBoonBps[player] = 0;
                    coinflipBoonTimestamp[player] = 0;
                    deityCoinflipBoonDay[player] = 0;
                    coinflipBps = 0;
                }
            }
        }

        bool lootbox25 = lootboxBoon25Active[player];
        if (lootbox25) {
            uint48 deityDay = deityLootboxBoon25Day[player];
            if (deityDay != 0 && deityDay != currentDay) {
                lootboxBoon25Active[player] = false;
                deityLootboxBoon25Day[player] = 0;
                lootbox25 = false;
            } else {
                uint48 ts = lootboxBoon25Timestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
                    lootboxBoon25Active[player] = false;
                    deityLootboxBoon25Day[player] = 0;
                    lootbox25 = false;
                }
            }
        } else {
            uint48 deityDay = deityLootboxBoon25Day[player];
            if (deityDay != 0 && deityDay != currentDay) {
                deityLootboxBoon25Day[player] = 0;
            }
        }

        bool lootbox15 = lootboxBoon15Active[player];
        if (lootbox15) {
            uint48 deityDay = deityLootboxBoon15Day[player];
            if (deityDay != 0 && deityDay != currentDay) {
                lootboxBoon15Active[player] = false;
                deityLootboxBoon15Day[player] = 0;
                lootbox15 = false;
            } else {
                uint48 ts = lootboxBoon15Timestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
                    lootboxBoon15Active[player] = false;
                    deityLootboxBoon15Day[player] = 0;
                    lootbox15 = false;
                }
            }
        } else {
            uint48 deityDay = deityLootboxBoon15Day[player];
            if (deityDay != 0 && deityDay != currentDay) {
                deityLootboxBoon15Day[player] = 0;
            }
        }

        bool lootbox5 = lootboxBoon5Active[player];
        if (lootbox5) {
            uint48 deityDay = deityLootboxBoon5Day[player];
            if (deityDay != 0 && deityDay != currentDay) {
                lootboxBoon5Active[player] = false;
                deityLootboxBoon5Day[player] = 0;
                lootbox5 = false;
            } else {
                uint48 ts = lootboxBoon5Timestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
                    lootboxBoon5Active[player] = false;
                    deityLootboxBoon5Day[player] = 0;
                    lootbox5 = false;
                }
            }
        } else {
            uint48 deityDay = deityLootboxBoon5Day[player];
            if (deityDay != 0 && deityDay != currentDay) {
                deityLootboxBoon5Day[player] = 0;
            }
        }

        uint16 purchaseBps = purchaseBoostBps[player];
        if (purchaseBps != 0) {
            uint48 deityDay = deityPurchaseBoostDay[player];
            if (deityDay != 0 && deityDay != currentDay) {
                purchaseBoostBps[player] = 0;
                purchaseBoostTimestamp[player] = 0;
                deityPurchaseBoostDay[player] = 0;
                purchaseBps = 0;
            } else {
                uint48 ts = purchaseBoostTimestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + PURCHASE_BOOST_EXPIRY_SECONDS) {
                    purchaseBoostBps[player] = 0;
                    purchaseBoostTimestamp[player] = 0;
                    deityPurchaseBoostDay[player] = 0;
                    purchaseBps = 0;
                }
            }
        }

        uint16 decimatorBps = decimatorBoostBps[player];
        if (decimatorBps != 0) {
            uint48 deityDay = deityDecimatorBoostDay[player];
            if (deityDay != 0 && deityDay != currentDay) {
                decimatorBoostBps[player] = 0;
                deityDecimatorBoostDay[player] = 0;
                decimatorBps = 0;
            }
        }

        uint48 whaleDay = whaleBoonDay[player];
        uint48 deityWhaleDay = deityWhaleBoonDay[player];
        if (deityWhaleDay != 0 && deityWhaleDay != currentDay) {
            whaleBoonDay[player] = 0;
            deityWhaleBoonDay[player] = 0;
            whaleBoonDiscountBps[player] = 0;
            whaleDay = 0;
        }
        uint48 lazyDay = lazyPassBoonDay[player];
        uint16 lazyDiscount = lazyPassBoonDiscountBps[player];
        if (lazyDay != 0 && currentDay > lazyDay + 4) {
            lazyPassBoonDay[player] = 0;
            if (lazyDiscount != 0) {
                lazyPassBoonDiscountBps[player] = 0;
            }
            lazyDay = 0;
            lazyDiscount = 0;
        } else if (lazyDay == 0 && lazyDiscount != 0) {
            lazyPassBoonDiscountBps[player] = 0;
            lazyDiscount = 0;
        }

        uint8 deityTier = deityPassBoonTier[player];
        if (deityTier != 0) {
            uint48 deityDay = deityDeityPassBoonDay[player];
            if (deityDay != 0) {
                if (currentDay > deityDay) {
                    deityPassBoonTier[player] = 0;
                    deityPassBoonTimestamp[player] = 0;
                    deityDeityPassBoonDay[player] = 0;
                    deityTier = 0;
                }
            } else {
                uint48 ts = deityPassBoonTimestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + PURCHASE_BOOST_EXPIRY_SECONDS) {
                    deityPassBoonTier[player] = 0;
                    deityPassBoonTimestamp[player] = 0;
                    deityTier = 0;
                }
            }
        }

        uint24 activityPending = activityBoonPending[player];
        if (activityPending != 0) {
            uint48 deityDay = deityActivityBoonDay[player];
            if (deityDay != 0 && deityDay != currentDay) {
                activityBoonPending[player] = 0;
                activityBoonTimestamp[player] = 0;
                deityActivityBoonDay[player] = 0;
                activityPending = 0;
            } else {
                uint48 ts = activityBoonTimestamp[player];
                if (ts > 0 && nowTs > uint256(ts) + COINFLIP_BOON_EXPIRY_SECONDS) {
                    activityBoonPending[player] = 0;
                    activityBoonTimestamp[player] = 0;
                    deityActivityBoonDay[player] = 0;
                    activityPending = 0;
                }
            }
        }

        return (whaleDay != 0 ||
            lazyDay != 0 ||
            coinflipBps != 0 ||
            lootbox25 ||
            lootbox15 ||
            lootbox5 ||
            purchaseBps != 0 ||
            decimatorBps != 0 ||
            activityPending != 0 ||
            deityTier != 0);
    }

    /// @notice Consume a pending activity boon and apply it to player stats.
    /// @dev Called via nested delegatecall from LootboxModule during lootbox resolution.
    /// @param player Player address
    function consumeActivityBoon(address player) external {
        uint24 pending = activityBoonPending[player];
        if (pending == 0 || player == address(0)) return;

        uint48 nowTs = uint48(block.timestamp);
        uint48 currentDay = _simulatedDayIndexAt(nowTs);
        uint48 deityDay = deityActivityBoonDay[player];
        if (deityDay != 0 && deityDay != currentDay) {
            activityBoonPending[player] = 0;
            activityBoonTimestamp[player] = 0;
            deityActivityBoonDay[player] = 0;
            return;
        }

        uint48 ts = activityBoonTimestamp[player];
        if (ts > 0 && uint256(nowTs) > uint256(ts) + COINFLIP_BOON_EXPIRY_SECONDS) {
            activityBoonPending[player] = 0;
            activityBoonTimestamp[player] = 0;
            deityActivityBoonDay[player] = 0;
            return;
        }

        activityBoonPending[player] = 0;
        activityBoonTimestamp[player] = 0;
        deityActivityBoonDay[player] = 0;

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
