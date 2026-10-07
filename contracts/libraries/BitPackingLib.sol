// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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

/**
 * @title BitPackingLib
 * @notice Library for bit-packed storage field operations and mint data constants.
 * @dev Consolidates packed field manipulation used across DegenerusGame, modules, and helpers.
 *
 *      Mint data layout (256 bits, contiguous):
 *      [0-23]    LAST_LEVEL_SHIFT            - Last level purchased (24 bits)
 *      [24-47]   LEVEL_COUNT_SHIFT           - Total level purchases (24 bits)
 *      [48-71]   LEVEL_STREAK_SHIFT          - Consecutive level streak (24 bits, managed by MintStreakUtils)
 *      [72-95]   DAY_SHIFT                   - Day index of last purchase (24 bits)
 *      [96-119]  LEVEL_UNITS_LEVEL_SHIFT     - Level for unit tracking (24 bits)
 *      [120-143] FROZEN_UNTIL_LEVEL_SHIFT    - Frozen level for lazy/whale passes (24 bits)
 *      [144-145] WHALE_PASS_TYPE_SHIFT       - Pass type (2 bits: 0=none, 1=lazy/10-lvl, 3=whale/100-lvl)
 *      [146]     SEAT_CLAIMED_SHIFT          - AFKing seat mint latch (1 bit)
 *      [147]     SMURF_FLAG_SHIFT            - Smurf account flag (1 bit; written only by createSmurf)
 *      [148-171] MINT_STREAK_LAST_COMPLETED  - Last level credited for mint streak (24 bits, managed by MintStreakUtils)
 *      [172]     HAS_DEITY_PASS_SHIFT        - Deity pass flag (1 bit)
 *      [173-196] AFFILIATE_BONUS_LEVEL_SHIFT - Cached affiliate bonus level (24 bits)
 *      [197-202] AFFILIATE_BONUS_POINTS_SHIFT - Cached affiliate bonus points (6 bits)
 *      [203-207] CURSE_COUNT_SHIFT           - Cashout/smite curse counter (5 bits, capped at 20)
 *      [208-223] LEVEL_UNITS_SHIFT           - Units purchased at current level (16 bits)
 *      [224-255] WALLET_ID_SHIFT             - Permanent wallet ID (32 bits; written only at registration)
 */
library BitPackingLib {
    // -------------------------------------------------------------------------
    // Bit Masks
    // -------------------------------------------------------------------------

    /// @notice 16-bit mask for level units field
    uint256 internal constant MASK_16 = (uint256(1) << 16) - 1;

    /// @notice 24-bit mask for level/count/streak fields
    uint256 internal constant MASK_24 = (uint256(1) << 24) - 1;

    /// @notice 6-bit mask for affiliate bonus points field
    uint256 internal constant MASK_6 = (uint256(1) << 6) - 1;

    /// @notice 5-bit mask for the curse counter field
    uint256 internal constant MASK_5 = (uint256(1) << 5) - 1;

    // -------------------------------------------------------------------------
    // Bit Shift Positions
    // -------------------------------------------------------------------------

    /// @notice Bit position for last level purchased (bits 0-23)
    uint256 internal constant LAST_LEVEL_SHIFT = 0;

    /// @notice Bit position for total level count (bits 24-47)
    uint256 internal constant LEVEL_COUNT_SHIFT = 24;

    /// @notice Bit position for consecutive streak (bits 48-71)
    uint256 internal constant LEVEL_STREAK_SHIFT = 48;

    /// @notice Bit position for day index (bits 72-95)
    uint256 internal constant DAY_SHIFT = 72;

    /// @notice Bit position for level units tracking level (bits 96-119)
    uint256 internal constant LEVEL_UNITS_LEVEL_SHIFT = 96;

    /// @notice Bit position for frozen until level (bits 120-143)
    uint256 internal constant FROZEN_UNTIL_LEVEL_SHIFT = 120;

    /// @notice Bit position for whale pass type (bits 144-145)
    uint256 internal constant WHALE_PASS_TYPE_SHIFT = 144;

    /// @notice Bit position for the AFKing seat latch (bit 146). Set on an
    ///         account's FIRST pass PURCHASE (whale/lazy/deity), which is also
    ///         when the seat is minted to the account's payee; one free-tranche
    ///         seat per account, ever. Passes that are won (the whale-pass claim
    ///         lane) or conferred (a deity buyer's affiliate) never set it. This
    ///         bit is the sole once-per-account guard — the token caps the tranche
    ///         at 1,000 but keeps no per-account record of its own.
    uint256 internal constant SEAT_CLAIMED_SHIFT = 146;

    /// @notice Bit position for the smurf flag (bit 147). Set once, by createSmurf, on
    ///         a smurf key's mint word. A path holding a mint word decides the payee
    ///         from it: clear means the key is the payee; set means the owner lane of
    ///         the wallet-table element names the payee.
    uint256 internal constant SMURF_FLAG_SHIFT = 147;

    /// @notice Bit position for last level credited for mint streak (bits 148-171)
    uint256 internal constant MINT_STREAK_LAST_COMPLETED_SHIFT = 148;

    /// @notice Bit position for deity pass flag (bit 172)
    uint256 internal constant HAS_DEITY_PASS_SHIFT = 172;

    /// @notice Bit position for cached affiliate bonus level (bits 173-196)
    uint256 internal constant AFFILIATE_BONUS_LEVEL_SHIFT = 173;

    /// @notice Bit position for cached affiliate bonus points (bits 197-202)
    uint256 internal constant AFFILIATE_BONUS_POINTS_SHIFT = 197;

    /// @notice Bit position for the cashout/smite curse counter (bits 203-207)
    uint256 internal constant CURSE_COUNT_SHIFT = 203;

    /// @notice Bit position for level units count (bits 208-223)
    uint256 internal constant LEVEL_UNITS_SHIFT = 208;

    /// @notice Bit position for the permanent wallet ID (bits 224-255). The ID is the
    ///         wallet's position in the Game wallet table; zero means unregistered.
    uint256 internal constant WALLET_ID_SHIFT = 224;

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
