// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @dev Test-side encoders/decoders for the box purchase input that `purchase()`'s third
///      parameter carries — [small:8][med:8][large:8][customCount:8][customSize:56 gwei], every
///      bit at or above 88 zero — and for the stored queue entry (LB_* layout in
///      DegenerusGameStorage). Each purchase is its own entry.
///
///      Migration rule: an old test that passed `X` wei of lootbox spend buys the SAME wei as
///      ONE custom box of size X — `boCustom(X)`.
library BoxOrderLib {
    uint256 internal constant SCALE = 1 gwei; // LB_SIZE_UNIT

    /// @dev One custom box of `wei_` (must be a whole number of gwei).
    function boCustom(uint256 wei_) internal pure returns (uint256) {
        require(wei_ % SCALE == 0 && wei_ != 0, "boCustom: granularity");
        return (uint256(1) << 24) | ((wei_ / SCALE) << 32);
    }

    /// @dev One custom box of `wei_` FLOORED to gwei granularity — for fuzz handlers whose
    ///      generated amounts are not aligned. Purchase overpay auto-credits to afking, so
    ///      sending the un-floored wei as value stays safe. Returns 0 (no box) below 1 gwei.
    function boCustomFloor(uint256 wei_) internal pure returns (uint256) {
        uint256 units = wei_ / SCALE;
        if (units == 0) return 0;
        return (uint256(1) << 24) | (units << 32);
    }

    /// @dev `n` custom boxes of `wei_` each.
    function boCustoms(uint256 n, uint256 wei_) internal pure returns (uint256) {
        require(wei_ % SCALE == 0 && wei_ != 0 && n != 0 && n <= 100, "boCustoms: args");
        return (n << 24) | ((wei_ / SCALE) << 32);
    }

    /// @dev `n` small boxes (1x the purchase level's ticket price each).
    function boSmalls(uint256 n) internal pure returns (uint256) {
        require(n != 0 && n <= 100, "boSmalls: count");
        return n;
    }

    /// @dev Full-shape encoder.
    function boOrder(
        uint256 small,
        uint256 med,
        uint256 large,
        uint256 customCount,
        uint256 customSizeWei
    ) internal pure returns (uint256) {
        require(customSizeWei % SCALE == 0, "boOrder: granularity");
        return
            small |
            (med << 8) |
            (large << 16) |
            (customCount << 24) |
            ((customSizeWei / SCALE) << 32);
    }

    // ---- stored entry decoders (LB_* layout in DegenerusGameStorage) ----

    function boId(uint256 word) internal pure returns (uint32) {
        return uint32(word);
    }

    function boLevel(uint256 word) internal pure returns (uint24) {
        return uint24(word >> 32);
    }

    function boScore(uint256 word) internal pure returns (uint256) {
        return (word >> 56) & 0x7FFF;
    }

    function boBoostBps(uint256 word) internal pure returns (uint256) {
        return (word >> 71) & 0x3FFF;
    }

    function boEvBps(uint256 word) internal pure returns (uint256) {
        return (word >> 85) & 0x3FFF;
    }

    function boDistress(uint256 word) internal pure returns (bool) {
        return (word >> 99) & 1 == 1;
    }

    function boSmall(uint256 word) internal pure returns (uint256) {
        return (word >> 100) & 0x7F;
    }

    function boMed(uint256 word) internal pure returns (uint256) {
        return (word >> 107) & 0x7F;
    }

    function boLarge(uint256 word) internal pure returns (uint256) {
        return (word >> 114) & 0x7F;
    }

    function boCustomCount(uint256 word) internal pure returns (uint256) {
        return (word >> 121) & 0x7F;
    }

    /// @dev Custom or cover box size in wei.
    function boSizeWei(uint256 word) internal pure returns (uint256) {
        return ((word >> 128) & 0xFFFFFFFFFFFFFF) * SCALE;
    }

    function boCover(uint256 word) internal pure returns (bool) {
        return (word >> 184) & 1 == 1;
    }

    function boPresaleWei(uint256 word) internal pure returns (uint256) {
        return (word >> 185) & 0x3FFFFFFFFFFFFFFFF;
    }

    function boPresaleTier(uint256 word) internal pure returns (uint256) {
        return (word >> 251) & 7;
    }

    function boPresaleClosing(uint256 word) internal pure returns (bool) {
        return (word >> 254) & 1 == 1;
    }

    /// @dev Boxes a stored entry resolves (four bought tiers, or its one cover box).
    function boCount(uint256 word) internal pure returns (uint256) {
        return boSmall(word) + boMed(word) + boLarge(word) + boCustomCount(word) + (boCover(word) ? 1 : 0);
    }

    /// @dev Nominal wei a stored entry's ordinary leg represents at `levelPriceWei` (the price
    ///      of the entry's own level).
    function boNominal(uint256 word, uint256 levelPriceWei) internal pure returns (uint256) {
        uint256 size = boSizeWei(word);
        if (boCover(word)) return size;
        return (boSmall(word) + 5 * boMed(word) + 25 * boLarge(word)) * levelPriceWei + boCustomCount(word) * size;
    }
}
