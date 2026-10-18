// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @dev Test-side encoders/decoders for the box purchase input that `purchase()`'s third
///      parameter carries — [quantity:7][kind:2][customUnits:21], every bit at or above 30 zero,
///      kind 0 small / 1 medium / 2 large / 3 custom, custom units in 0.001 ETH — and for the
///      stored 85-bit queue entry (LB_* layout in DegenerusGameStorage), three per storage word.
///      One box type per purchase; each purchase is its own entry.
///
///      Migration rule: an old test that passed `X` wei of lootbox spend buys the SAME wei as
///      ONE custom box of size X — `boCustom(X)` — when X is a whole number of 0.001 ETH.
library BoxOrderLib {
    uint256 internal constant SCALE = 0.001 ether; // LB_VALUE_UNIT
    uint256 internal constant UNITS_MIN = 10; // BOX_CUSTOM_MIN_UNITS
    uint256 internal constant UNITS_MAX = 2_000_000; // LB_UNITS_MAX
    uint256 internal constant KIND_SMALL = 0;
    uint256 internal constant KIND_MED = 1;
    uint256 internal constant KIND_LARGE = 2;
    uint256 internal constant KIND_CUSTOM = 3;
    uint256 internal constant ENTRY_BITS = 85;
    uint256 internal constant ENTRY_MASK = (uint256(1) << 85) - 1;
    uint256 internal constant SCORE_CODE_EXACT = 2042;
    uint256 internal constant SCORE_CODE_STEP = 14;
    uint256 internal constant SCORE_CAP = 30_000;

    // ---- purchase input ----

    /// @dev Raw input: `qty` boxes of `kind`, `units` per box for a custom (zero for presets).
    function boInput(uint256 kind, uint256 qty, uint256 units) internal pure returns (uint256) {
        return qty | (kind << 7) | (units << 9);
    }

    /// @dev One custom box of `wei_` (a whole number of 0.001 ETH, 0.01..2,000 ETH).
    function boCustom(uint256 wei_) internal pure returns (uint256) {
        return boCustoms(1, wei_);
    }

    /// @dev One custom box of `wei_` FLOORED to 0.001 ETH — for fuzz handlers whose generated
    ///      amounts are not aligned. Purchase overpay auto-credits to afking, so sending the
    ///      un-floored wei as value stays safe. Returns 0 (no box) below one unit; the contract
    ///      rejects a custom below 10 units like any other undersized input.
    function boCustomFloor(uint256 wei_) internal pure returns (uint256) {
        uint256 units = wei_ / SCALE;
        if (units == 0) return 0;
        return boInput(KIND_CUSTOM, 1, units);
    }

    /// @dev `n` custom boxes of `wei_` each.
    function boCustoms(uint256 n, uint256 wei_) internal pure returns (uint256) {
        require(wei_ % SCALE == 0 && wei_ / SCALE >= UNITS_MIN && wei_ / SCALE <= UNITS_MAX, "boCustoms: size");
        require(n != 0 && n <= 100, "boCustoms: count");
        return boInput(KIND_CUSTOM, n, wei_ / SCALE);
    }

    /// @dev `n` small boxes (1x the purchase level's ticket price each).
    function boSmalls(uint256 n) internal pure returns (uint256) {
        require(n != 0 && n <= 100, "boSmalls: count");
        return boInput(KIND_SMALL, n, 0);
    }

    /// @dev `n` medium boxes (5x).
    function boMeds(uint256 n) internal pure returns (uint256) {
        require(n != 0 && n <= 100, "boMeds: count");
        return boInput(KIND_MED, n, 0);
    }

    /// @dev `n` large boxes (25x).
    function boLarges(uint256 n) internal pure returns (uint256) {
        require(n != 0 && n <= 100, "boLarges: count");
        return boInput(KIND_LARGE, n, 0);
    }

    /// @dev Count-shaped encoder for one box type: exactly one of the four counts is nonzero.
    function boOrder(
        uint256 small,
        uint256 med,
        uint256 large,
        uint256 customCount,
        uint256 customSizeWei
    ) internal pure returns (uint256) {
        uint256 kinds = (small != 0 ? 1 : 0) + (med != 0 ? 1 : 0) + (large != 0 ? 1 : 0) + (customCount != 0 ? 1 : 0);
        require(kinds == 1, "boOrder: one box type per purchase");
        if (customCount != 0) return boCustoms(customCount, customSizeWei);
        require(customSizeWei == 0, "boOrder: preset with size");
        if (small != 0) return boSmalls(small);
        if (med != 0) return boMeds(med);
        return boLarges(large);
    }

    // ---- stored entry decoders (LB_* layout in DegenerusGameStorage) ----

    function boId(uint256 entry) internal pure returns (uint32) {
        return uint32(entry);
    }

    /// @dev Per-box value in 0.001 ETH units.
    function boUnits(uint256 entry) internal pure returns (uint256) {
        return (entry >> 32) & 0x1FFFFF;
    }

    /// @dev Per-box value in wei.
    function boSizeWei(uint256 entry) internal pure returns (uint256) {
        return boUnits(entry) * SCALE;
    }

    function boScoreCode(uint256 entry) internal pure returns (uint256) {
        return (entry >> 53) & 0xFFF;
    }

    /// @dev The frozen whole-point score the resolver decodes.
    function boScore(uint256 entry) internal pure returns (uint256) {
        return scoreFromCode(boScoreCode(entry));
    }

    function boBoostBps(uint256 entry) internal pure returns (uint256) {
        return (entry >> 65) & 0xFFF;
    }

    /// @dev Boxes the entry resolves.
    function boCount(uint256 entry) internal pure returns (uint256) {
        return (entry >> 77) & 0x7F;
    }

    function boDistress(uint256 entry) internal pure returns (bool) {
        return (entry >> 84) & 1 == 1;
    }

    /// @dev Entry bits 85..255, which every decoded entry leaves zero.
    function boHighBits(uint256 entry) internal pure returns (uint256) {
        return entry >> 85;
    }

    /// @dev Nominal wei the entry represents (quantity x per-box value).
    function boNominal(uint256 entry) internal pure returns (uint256) {
        return boCount(entry) * boSizeWei(entry);
    }

    /// @dev Assemble an entry from its fields (for seeding raw storage).
    function boEntry(uint32 id, uint256 units, uint256 scoreCode, uint256 boostBps, uint256 qty, bool distress)
        internal
        pure
        returns (uint256)
    {
        return uint256(id) | (units << 32) | (scoreCode << 53) | (boostBps << 65) | (qty << 77)
            | (distress ? uint256(1) << 84 : 0);
    }

    // ---- queue addressing ----

    /// @dev Word offset of logical position `p` from the buffer's data base.
    function boWordIndex(uint256 p) internal pure returns (uint256) {
        return p / 3;
    }

    /// @dev Bit shift of logical position `p` within its word.
    function boLaneShift(uint256 p) internal pure returns (uint256) {
        return (p % 3) * ENTRY_BITS;
    }

    /// @dev Entry of logical position `p` from its physical word.
    function boLane(uint256 physicalWord, uint256 p) internal pure returns (uint256) {
        return (physicalWord >> boLaneShift(p)) & ENTRY_MASK;
    }

    /// @dev `physicalWord` with logical position `p`'s lane replaced by `entry`.
    function boWithLane(uint256 physicalWord, uint256 p, uint256 entry) internal pure returns (uint256) {
        uint256 shift = boLaneShift(p);
        return (physicalWord & ~(ENTRY_MASK << shift)) | ((entry & ENTRY_MASK) << shift);
    }

    // ---- activity score code (mirrors the Lootbox module's _scoreCode/_scoreFromCode) ----

    function scoreCode(uint256 score) internal pure returns (uint256) {
        if (score > SCORE_CAP) score = SCORE_CAP;
        return score <= SCORE_CODE_EXACT ? score : SCORE_CODE_EXACT + (score - SCORE_CODE_EXACT) / SCORE_CODE_STEP;
    }

    function scoreFromCode(uint256 code) internal pure returns (uint256) {
        return code <= SCORE_CODE_EXACT ? code : SCORE_CODE_EXACT + (code - SCORE_CODE_EXACT) * SCORE_CODE_STEP;
    }
}
