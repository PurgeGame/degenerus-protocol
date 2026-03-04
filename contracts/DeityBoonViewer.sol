// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

interface IDeityBoonDataSource {
    function deityBoonData(address deity) external view returns (
        uint256 dailySeed,
        uint48 day,
        uint8 usedMask,
        bool decimatorOpen,
        bool deityPassAvailable
    );
}

/// @title DeityBoonViewer
/// @notice Standalone view contract for computing deity boon slot types.
///         Reads raw state from DegenerusGame.deityBoonData() and applies the
///         weighted random selection logic to determine boon types per slot.
contract DeityBoonViewer {

    uint8 private constant DEITY_DAILY_BOON_COUNT = 3;

    // Boon type IDs
    uint8 private constant DEITY_BOON_COINFLIP_5 = 1;
    uint8 private constant DEITY_BOON_COINFLIP_10 = 2;
    uint8 private constant DEITY_BOON_COINFLIP_25 = 3;
    uint8 private constant DEITY_BOON_LOOTBOX_5 = 5;
    uint8 private constant DEITY_BOON_LOOTBOX_15 = 6;
    uint8 private constant DEITY_BOON_PURCHASE_5 = 7;
    uint8 private constant DEITY_BOON_PURCHASE_15 = 8;
    uint8 private constant DEITY_BOON_PURCHASE_25 = 9;
    uint8 private constant DEITY_BOON_DECIMATOR_10 = 13;
    uint8 private constant DEITY_BOON_DECIMATOR_25 = 14;
    uint8 private constant DEITY_BOON_DECIMATOR_50 = 15;
    uint8 private constant DEITY_BOON_WHALE_10 = 16;
    uint8 private constant DEITY_BOON_ACTIVITY_10 = 17;
    uint8 private constant DEITY_BOON_ACTIVITY_25 = 18;
    uint8 private constant DEITY_BOON_ACTIVITY_50 = 19;
    uint8 private constant DEITY_BOON_LOOTBOX_25 = 22;
    uint8 private constant DEITY_BOON_WHALE_25 = 23;
    uint8 private constant DEITY_BOON_WHALE_50 = 24;
    uint8 private constant DEITY_BOON_DEITY_PASS_10 = 25;
    uint8 private constant DEITY_BOON_DEITY_PASS_25 = 26;
    uint8 private constant DEITY_BOON_DEITY_PASS_50 = 27;
    uint8 private constant DEITY_BOON_WHALE_PASS = 28;
    uint8 private constant DEITY_BOON_LAZY_PASS_10 = 29;
    uint8 private constant DEITY_BOON_LAZY_PASS_25 = 30;
    uint8 private constant DEITY_BOON_LAZY_PASS_50 = 31;

    // Boon weights
    uint16 private constant W_COINFLIP_5 = 200;
    uint16 private constant W_COINFLIP_10 = 40;
    uint16 private constant W_COINFLIP_25 = 8;
    uint16 private constant W_LOOTBOX_5 = 200;
    uint16 private constant W_LOOTBOX_15 = 30;
    uint16 private constant W_LOOTBOX_25 = 8;
    uint16 private constant W_PURCHASE_5 = 400;
    uint16 private constant W_PURCHASE_15 = 80;
    uint16 private constant W_PURCHASE_25 = 16;
    uint16 private constant W_DECIMATOR_10 = 40;
    uint16 private constant W_DECIMATOR_25 = 8;
    uint16 private constant W_DECIMATOR_50 = 2;
    uint16 private constant W_WHALE_10 = 28;
    uint16 private constant W_WHALE_25 = 10;
    uint16 private constant W_WHALE_50 = 2;
    uint16 private constant W_DEITY_PASS_10 = 28;
    uint16 private constant W_DEITY_PASS_25 = 10;
    uint16 private constant W_DEITY_PASS_50 = 2;
    uint16 private constant W_ACTIVITY_10 = 100;
    uint16 private constant W_ACTIVITY_25 = 30;
    uint16 private constant W_ACTIVITY_50 = 8;
    uint16 private constant W_WHALE_PASS = 8;
    uint16 private constant W_LAZY_PASS_10 = 30;
    uint16 private constant W_LAZY_PASS_25 = 8;
    uint16 private constant W_LAZY_PASS_50 = 2;
    uint16 private constant W_DEITY_PASS_ALL = 40;
    uint16 private constant W_TOTAL = 1298;
    uint16 private constant W_TOTAL_NO_DECIMATOR = 1248;

    /// @notice Compute deity boon slots for a given deity.
    /// @param game Address of the DegenerusGame contract.
    /// @param deity The deity address to query.
    /// @return slots Array of 3 boon type IDs for today's slots.
    /// @return usedMask Bitmask of slots already used today.
    /// @return day Current day index.
    function deityBoonSlots(
        address game,
        address deity
    ) external view returns (uint8[3] memory slots, uint8 usedMask, uint48 day) {
        (
            uint256 dailySeed,
            uint48 d,
            uint8 mask,
            bool decimatorOpen,
            bool deityPassAvailable
        ) = IDeityBoonDataSource(game).deityBoonData(deity);

        day = d;
        usedMask = mask;

        for (uint8 i = 0; i < DEITY_DAILY_BOON_COUNT; ) {
            uint256 seed = uint256(keccak256(abi.encode(dailySeed, deity, d, i)));
            uint256 total = decimatorOpen ? W_TOTAL : W_TOTAL_NO_DECIMATOR;
            if (!deityPassAvailable) total -= W_DEITY_PASS_ALL;
            slots[i] = _boonFromRoll(seed % total, decimatorOpen, deityPassAvailable);
            unchecked { ++i; }
        }
    }

    function _boonFromRoll(
        uint256 roll,
        bool decimatorAllowed,
        bool deityEligible
    ) private pure returns (uint8) {
        uint256 cursor = 0;
        cursor += W_COINFLIP_5;
        if (roll < cursor) return DEITY_BOON_COINFLIP_5;
        cursor += W_COINFLIP_10;
        if (roll < cursor) return DEITY_BOON_COINFLIP_10;
        cursor += W_COINFLIP_25;
        if (roll < cursor) return DEITY_BOON_COINFLIP_25;
        cursor += W_LOOTBOX_5;
        if (roll < cursor) return DEITY_BOON_LOOTBOX_5;
        cursor += W_LOOTBOX_15;
        if (roll < cursor) return DEITY_BOON_LOOTBOX_15;
        cursor += W_LOOTBOX_25;
        if (roll < cursor) return DEITY_BOON_LOOTBOX_25;
        cursor += W_PURCHASE_5;
        if (roll < cursor) return DEITY_BOON_PURCHASE_5;
        cursor += W_PURCHASE_15;
        if (roll < cursor) return DEITY_BOON_PURCHASE_15;
        cursor += W_PURCHASE_25;
        if (roll < cursor) return DEITY_BOON_PURCHASE_25;
        if (decimatorAllowed) {
            cursor += W_DECIMATOR_10;
            if (roll < cursor) return DEITY_BOON_DECIMATOR_10;
            cursor += W_DECIMATOR_25;
            if (roll < cursor) return DEITY_BOON_DECIMATOR_25;
            cursor += W_DECIMATOR_50;
            if (roll < cursor) return DEITY_BOON_DECIMATOR_50;
        }
        cursor += W_WHALE_10;
        if (roll < cursor) return DEITY_BOON_WHALE_10;
        cursor += W_WHALE_25;
        if (roll < cursor) return DEITY_BOON_WHALE_25;
        cursor += W_WHALE_50;
        if (roll < cursor) return DEITY_BOON_WHALE_50;
        if (deityEligible) {
            cursor += W_DEITY_PASS_10;
            if (roll < cursor) return DEITY_BOON_DEITY_PASS_10;
            cursor += W_DEITY_PASS_25;
            if (roll < cursor) return DEITY_BOON_DEITY_PASS_25;
            cursor += W_DEITY_PASS_50;
            if (roll < cursor) return DEITY_BOON_DEITY_PASS_50;
        }
        cursor += W_ACTIVITY_10;
        if (roll < cursor) return DEITY_BOON_ACTIVITY_10;
        cursor += W_ACTIVITY_25;
        if (roll < cursor) return DEITY_BOON_ACTIVITY_25;
        cursor += W_ACTIVITY_50;
        if (roll < cursor) return DEITY_BOON_ACTIVITY_50;
        cursor += W_WHALE_PASS;
        if (roll < cursor) return DEITY_BOON_WHALE_PASS;
        cursor += W_LAZY_PASS_10;
        if (roll < cursor) return DEITY_BOON_LAZY_PASS_10;
        cursor += W_LAZY_PASS_25;
        if (roll < cursor) return DEITY_BOON_LAZY_PASS_25;
        cursor += W_LAZY_PASS_50;
        if (roll < cursor) return DEITY_BOON_LAZY_PASS_50;
        return DEITY_BOON_ACTIVITY_50;
    }
}
