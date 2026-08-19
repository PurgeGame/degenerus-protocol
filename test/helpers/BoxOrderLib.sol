// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

/// @dev Test-side encoders/decoders for the packed box order that `purchase()`'s third
///      parameter now carries: [small:8][med:8][large:8][customCount:8][customSize:48 x1e12].
///
///      Migration rule: an old test that passed `X` wei of lootbox spend buys the SAME wei as
///      ONE custom box of size X — `boCustom(X)` — which is the closest semantic match to the
///      old accumulated single box (same spend, same pool contribution; the reward now settles
///      as one roll at full size instead of the old 0.5-ETH auto-split pair).
library BoxOrderLib {
    uint256 internal constant SCALE = 1e12; // LB_CUSTOM_SCALE

    /// @dev One custom box of `wei_` (must be a multiple of 1e12 — every old test literal is).
    function boCustom(uint256 wei_) internal pure returns (uint256) {
        require(wei_ % SCALE == 0 && wei_ != 0, "boCustom: granularity");
        return (uint256(1) << 24) | ((wei_ / SCALE) << 32);
    }

    /// @dev One custom box of `wei_` FLOORED to 1e12 granularity — for fuzz handlers whose
    ///      generated amounts are not aligned. Purchase overpay auto-credits to afking, so
    ///      sending the un-floored wei as value stays safe. Returns 0 (no box) below 1e12.
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

    /// @dev `n` small boxes (1x the frozen level's ticket price each).
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

    // ---- storage-word decoders (LB_* layout in DegenerusGameStorage) ----

    /// @dev Total boxes queued in a stored order word (four bought tiers + the cover box).
    function boCount(uint256 word) internal pure returns (uint256) {
        return
            ((word >> 81) & 0xFF) +
            ((word >> 89) & 0xFF) +
            ((word >> 97) & 0xFF) +
            ((word >> 105) & 0xFF) +
            (((word >> 161) & 0xFFFFFFFFFFFF) == 0 ? 0 : 1);
    }

    /// @dev Nominal wei a stored order represents — the migration replacement for the old
    ///      `lootboxEth` word's low-128-bit amount (which tests read as "the box's ETH").
    ///      NOTE: nominal excludes the boon boost the old amount included; tests asserting
    ///      the exact boosted amount must decode boostBps and gross up.
    function boNominal(uint256 word, uint256 levelPriceWei) internal pure returns (uint256) {
        uint256 customWei = ((word >> 113) & 0xFFFFFFFFFFFF) * SCALE;
        return
            (((word >> 81) & 0xFF) +
                5 *
                ((word >> 89) & 0xFF) +
                25 *
                ((word >> 97) & 0xFF)) *
            levelPriceWei +
            ((word >> 105) & 0xFF) *
            customWei +
            ((word >> 161) & 0xFFFFFFFFFFFF) *
            SCALE;
    }
}
