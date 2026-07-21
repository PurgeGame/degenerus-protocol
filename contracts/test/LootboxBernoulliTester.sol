// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title LootboxBernoulliTester
/// @notice Test helper that exposes the manual-path Bernoulli whole-ticket collapse
///         arithmetic from `DegenerusGameLootboxModule._settleLootboxRoll` as
///         external-pure passthroughs. Enables direct empirical verification of:
///           - EV-neutrality of the round-up: `E[whole] * 100 ≈ scaledPre`
///             (exact under an ideal uniform mod-100 draw; the uint32 % 100 bias is ~2e-8)
///           - Boundary cases at scaledPre ∈ {0, 1, 99, 100, 101, 199, 200}
///           - bits[224..255] bit-slice independence from other primary-chunk consumers
///           - Magnitude equivalence: `LOOTBOX_WWXRP_CONSOLATION == LOOTBOX_WWXRP_PRIZE`
/// @dev    The arithmetic mirrored here is the EXACT instruction sequence that ships
///         in `DegenerusGameLootboxModule._settleLootboxRoll`. The test suite asserts
///         byte-identical reproduction by grepping the production source for the
///         canonical pattern; if either drifts, the drift-detection test fails first
///         and the math test becomes informative only after that drift is reconciled.
///         The round-up reads a uint32 window so the `% QTY_SCALE` modulo bias is
///         negligible (~2e-8).
contract LootboxBernoulliTester {
    /// @notice QTY_SCALE mirror from `DegenerusGameStorage.sol`.
    uint256 public constant QTY_SCALE = 100;

    /// @notice Magnitudes from `DegenerusGameLootboxModule.sol`.
    uint256 public constant LOOTBOX_WWXRP_PRIZE = 1 ether;
    uint256 public constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;

    /// @notice Bernoulli whole-ticket collapse on bits[224..255] of `seed`.
    /// @dev Instruction-sequence parity with the Bernoulli-collapse sub-step of the manual
    ///      branch of `_settleLootboxRoll`. Production wraps this with the upstream
    ///      distress-bonus adjustment (and its own uint32 saturation) and the downstream
    ///      `_queueEntries(player, rollLevel, wholeTicketsToEntries(whole), false)`:
    ///        uint32 scaledPre = futureTickets;
    ///        uint32 whole = futureTickets / uint32(QTY_SCALE);
    ///        uint32 frac  = futureTickets % uint32(QTY_SCALE);
    ///        bool roundedUp = false;
    ///        if (frac != 0 && (uint32(seed >> 224) % uint32(QTY_SCALE)) < frac) {
    ///            unchecked { whole += 1; }
    ///            roundedUp = true;
    ///        }
    /// @param scaledPre Pre-Bernoulli scaled ticket count (== `futureTickets` at the
    ///                  manual-branch entry).
    /// @param seed Per-resolution 256-bit keccak seed.
    /// @return whole Post-collapse whole ticket count.
    /// @return roundedUp True iff the Bernoulli round-up fired (fractional path).
    function bernoulliWhole(uint32 scaledPre, uint256 seed)
        external
        pure
        returns (uint32 whole, bool roundedUp)
    {
        whole = scaledPre / uint32(QTY_SCALE);
        uint32 frac = scaledPre % uint32(QTY_SCALE);
        roundedUp = false;
        if (frac != 0 && (uint32(seed >> 224) % uint32(QTY_SCALE)) < frac) {
            unchecked {
                whole += 1;
            }
            roundedUp = true;
        }
    }

    /// @notice Expose the [0..99] compare value consumed by the Bernoulli math.
    /// @return slice `uint32(seed >> 224) % uint32(QTY_SCALE)` — the [0..99] value
    ///               compared against `frac` in the round-up gate.
    function bernoulliSlice(uint256 seed) external pure returns (uint32 slice) {
        slice = uint32(seed >> 224) % uint32(QTY_SCALE);
    }

    /// @notice Mirror of the ticket-path cold-bust consolation gate in
    ///         `DegenerusGameLootboxModule._settleLootboxRoll`: runs the Bernoulli
    ///         collapse, then applies the `payColdBustConsolation && whole == 0` gate
    ///         that decides whether the `LOOTBOX_WWXRP_CONSOLATION` payout fires.
    /// @dev    Instruction-sequence parity with the production gate:
    ///           _queueEntries(player, rollLevel, whole, false);
    ///           if (payColdBustConsolation && whole == 0) {
    ///               wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
    ///           }
    ///         The manual callers and `resolveAfkingBox` pass `payColdBustConsolation = true`;
    ///         the other auto-resolve callers (`resolveLootboxDirect`,
    ///         `resolveRedemptionLootbox`) pass `false`.
    /// @param payColdBustConsolation The per-caller flag gating the consolation payout.
    /// @param scaledPre Pre-Bernoulli scaled ticket count.
    /// @param seed Per-resolution 256-bit keccak seed.
    /// @return consolationFires True iff the WWXRP cold-bust consolation would be paid.
    function coldBustConsolationFires(
        bool payColdBustConsolation,
        uint32 scaledPre,
        uint256 seed
    ) external pure returns (bool consolationFires) {
        uint32 whole = scaledPre / uint32(QTY_SCALE);
        uint32 frac = scaledPre % uint32(QTY_SCALE);
        if (frac != 0 && (uint32(seed >> 224) % uint32(QTY_SCALE)) < frac) {
            unchecked {
                whole += 1;
            }
        }
        consolationFires = payColdBustConsolation && whole == 0;
    }

    /// @notice Expose the raw 32-bit pre-mod slice for chi² independence testing.
    /// @return raw32 `uint32(seed >> 224)` — the full 32-bit slice before the mod-100.
    function bernoulliRaw32(uint256 seed) external pure returns (uint32 raw32) {
        raw32 = uint32(seed >> 224);
    }
}
