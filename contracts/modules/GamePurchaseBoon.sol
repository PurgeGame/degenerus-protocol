// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

abstract contract GamePurchaseBoon is DegenerusGameStorage {
    /// @dev Purchase boosts expire after four days; deity grants last only their grant day.
    uint24 internal constant PURCHASE_BOOST_EXPIRY_DAYS = 4;

    /// @dev Consume a live purchase boost and return its bonus in basis points.
    function _consumePurchaseBoost(uint32 id) internal returns (uint16 boostBps) {
        BoonPacked storage bp = boonPacked[id];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_PURCHASE_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 currentDay = uint24(_gameDay());
        uint24 deityDay = uint24(s0 >> BP_DEITY_PURCHASE_DAY_SHIFT);
        if (deityDay != 0 && deityDay != currentDay) {
            bp.slot0 = (s0 & BP_PURCHASE_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_PURCHASE_DAY_SHIFT);
        if (stampDay > 0 && currentDay > stampDay + PURCHASE_BOOST_EXPIRY_DAYS) {
            bp.slot0 = (s0 & BP_PURCHASE_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        boostBps = _purchaseTierToBps(tier);
        bp.slot0 = (s0 & BP_PURCHASE_CLEAR) | BP_SLOT0_RETAINED;
        emit BoonConsumed(id, 2, boostBps);
    }
}
