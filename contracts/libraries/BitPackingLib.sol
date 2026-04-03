// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title BitPackingLib
 * @notice Library for bit-packed storage field operations and mint data constants.
 * @dev Consolidates packed field manipulation used across DegenerusGame, modules, and helpers.
 *
 *      Mint data layout (256 bits):
 *      [0-23]    LAST_LEVEL_SHIFT            - Last level purchased (24 bits)
 *      [24-47]   LEVEL_COUNT_SHIFT           - Total level purchases (24 bits)
 *      [48-71]   LEVEL_STREAK_SHIFT          - Consecutive level streak (24 bits, managed by MintStreakUtils)
 *      [72-103]  DAY_SHIFT                   - Day index of last purchase (32 bits)
 *      [104-127] LEVEL_UNITS_LEVEL_SHIFT     - Level for unit tracking (24 bits)
 *      [128-151] FROZEN_UNTIL_LEVEL_SHIFT    - Frozen level for whale bundles (24 bits)
 *      [152-153] WHALE_BUNDLE_TYPE_SHIFT     - Bundle type (2 bits: 0=none, 1=10-lvl, 3=100-lvl)
 *      [154-159] (unused)
 *      [160-183] MINT_STREAK_LAST_COMPLETED  - Last level credited for mint streak (24 bits, managed by MintStreakUtils)
 *      [184]     HAS_DEITY_PASS_SHIFT        - Deity pass flag (1 bit)
 *      [185-208] AFFILIATE_BONUS_LEVEL_SHIFT - Cached affiliate bonus level (24 bits)
 *      [209-214] AFFILIATE_BONUS_POINTS_SHIFT - Cached affiliate bonus points (6 bits)
 *      [215-227] (unused)
 *      [228-243] LEVEL_UNITS_SHIFT           - Units purchased at current level (16 bits)
 *      [244-255] (reserved)
 */
library BitPackingLib {
    // -------------------------------------------------------------------------
    // Bit Masks
    // -------------------------------------------------------------------------

    /// @notice 16-bit mask for level units field
    uint256 internal constant MASK_16 = (uint256(1) << 16) - 1;

    /// @notice 24-bit mask for level/count/streak fields
    uint256 internal constant MASK_24 = (uint256(1) << 24) - 1;

    /// @notice 32-bit mask for day field
    uint256 internal constant MASK_32 = (uint256(1) << 32) - 1;

    /// @notice 6-bit mask for affiliate bonus points field
    uint256 internal constant MASK_6 = (uint256(1) << 6) - 1;

    // -------------------------------------------------------------------------
    // Bit Shift Positions
    // -------------------------------------------------------------------------

    /// @notice Bit position for last level purchased (bits 0-23)
    uint256 internal constant LAST_LEVEL_SHIFT = 0;

    /// @notice Bit position for total level count (bits 24-47)
    uint256 internal constant LEVEL_COUNT_SHIFT = 24;

    /// @notice Bit position for consecutive streak (bits 48-71)
    uint256 internal constant LEVEL_STREAK_SHIFT = 48;

    /// @notice Bit position for day index (bits 72-103)
    uint256 internal constant DAY_SHIFT = 72;

    /// @notice Bit position for level units tracking level (bits 104-127)
    uint256 internal constant LEVEL_UNITS_LEVEL_SHIFT = 104;

    /// @notice Bit position for frozen until level (bits 128-151)
    uint256 internal constant FROZEN_UNTIL_LEVEL_SHIFT = 128;

    /// @notice Bit position for whale bundle type (bits 152-153)
    uint256 internal constant WHALE_BUNDLE_TYPE_SHIFT = 152;
    /// @notice Mask for 2-bit whale bundle type field
    uint256 internal constant MASK_2 = 0x3;

    /// @notice Bit position for deity pass flag (bit 184)
    uint256 internal constant HAS_DEITY_PASS_SHIFT = 184;
    /// @notice Mask for 1-bit flag field
    uint256 internal constant MASK_1 = 0x1;

    /// @notice Bit position for cached affiliate bonus level (bits 185-208)
    uint256 internal constant AFFILIATE_BONUS_LEVEL_SHIFT = 185;

    /// @notice Bit position for cached affiliate bonus points (bits 209-214)
    uint256 internal constant AFFILIATE_BONUS_POINTS_SHIFT = 209;

    /// @notice Bit position for level units count (bits 228-243)
    uint256 internal constant LEVEL_UNITS_SHIFT = 228;

    // -------------------------------------------------------------------------
    // Packing Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Set a packed field value within a 256-bit word.
     * @dev Clears the target field then sets the new value.
     *      Formula: (data & ~(mask << shift)) | ((value & mask) << shift)
     * @param data The packed data word.
     * @param shift Bit position of the field.
     * @param mask Bit mask for the field width.
     * @param value New value for the field (will be masked to field width).
     * @return The updated packed data word with the new field value.
     */
    function setPacked(
        uint256 data,
        uint256 shift,
        uint256 mask,
        uint256 value
    ) internal pure returns (uint256) {
        return (data & ~(mask << shift)) | ((value & mask) << shift);
    }

}
