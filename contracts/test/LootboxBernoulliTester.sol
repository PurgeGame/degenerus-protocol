// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title LootboxBernoulliTester
/// @notice Test helper that exposes the manual-path Bernoulli whole-ticket collapse
///         arithmetic from `DegenerusGameLootboxModule._resolveLootboxCommon` as
///         external-pure passthroughs. Enables direct empirical verification of:
///           - EV-neutrality of the round-up: `E[whole] * 100 == scaledPre`
///           - Boundary cases at scaledPre ∈ {0, 1, 99, 100, 101, 199, 200}
///           - bits[152..167] bit-slice independence from other primary-chunk consumers
///           - Magnitude equivalence: `LOOTBOX_WWXRP_CONSOLATION == LOOTBOX_WWXRP_PRIZE`
///         under Phase 274 v39.0 audit scope (D-274-BIT-SLICE-01, D-274-WX-AMOUNT-01).
/// @dev    The arithmetic mirrored here is the EXACT instruction sequence that ships
///         in `DegenerusGameLootboxModule._resolveLootboxCommon` (L1039-1046 at v39
///         HEAD). The test suite asserts byte-identical reproduction by grepping the
///         production source for the canonical pattern; if either drifts, the
///         drift-detection test fails first and the math test becomes informative
///         only after that drift is reconciled. Pattern mirrors the
///         `TraitUtilsTester` / `JackpotSoloTester` / `PriceLookupTester` precedent.
contract LootboxBernoulliTester {
    /// @notice TICKET_SCALE mirror from `DegenerusGameStorage.sol:165`.
    uint256 public constant TICKET_SCALE = 100;

    /// @notice Magnitudes from `DegenerusGameLootboxModule.sol:305-311`.
    uint256 public constant LOOTBOX_WWXRP_PRIZE = 1 ether;
    uint256 public constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;

    /// @notice Bernoulli whole-ticket collapse on bits[152..167] of `seed`.
    /// @dev Exact instruction-sequence parity with the manual branch of
    ///      `_resolveLootboxCommon` at L1039-1046:
    ///        uint32 scaledPre = futureTickets;
    ///        uint32 whole = futureTickets / uint32(TICKET_SCALE);
    ///        uint32 frac  = futureTickets % uint32(TICKET_SCALE);
    ///        bool roundedUp = false;
    ///        if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
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
        whole = scaledPre / uint32(TICKET_SCALE);
        uint32 frac = scaledPre % uint32(TICKET_SCALE);
        roundedUp = false;
        if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
            unchecked {
                whole += 1;
            }
            roundedUp = true;
        }
    }

    /// @notice Expose the raw bit-slice consumed by the Bernoulli math.
    /// @return slice `uint16(seed >> 152) % uint16(TICKET_SCALE)` — the [0..99] value
    ///               compared against `frac` in the round-up gate.
    function bernoulliSlice(uint256 seed) external pure returns (uint16 slice) {
        slice = uint16(seed >> 152) % uint16(TICKET_SCALE);
    }

    /// @notice Mirror of the ticket-path cold-bust consolation gate in
    ///         `DegenerusGameLootboxModule._resolveLootboxCommon`: runs the Bernoulli
    ///         collapse, then applies the `payColdBustConsolation && whole == 0` gate
    ///         that decides whether the `LOOTBOX_WWXRP_CONSOLATION` payout fires.
    /// @dev    Instruction-sequence parity with the production gate:
    ///           _queueTickets(player, targetLevel, whole, false);
    ///           if (payColdBustConsolation && whole == 0) {
    ///               wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
    ///           }
    ///         The manual callers (`openLootBox`, `openFlipLootBox`) pass
    ///         `payColdBustConsolation = true`; the auto-resolve callers
    ///         (`resolveLootboxDirect`, `resolveRedemptionLootbox`) pass `false`.
    /// @param payColdBustConsolation The per-caller flag gating the consolation payout.
    /// @param scaledPre Pre-Bernoulli scaled ticket count.
    /// @param seed Per-resolution 256-bit keccak seed.
    /// @return consolationFires True iff the WWXRP cold-bust consolation would be paid.
    function coldBustConsolationFires(
        bool payColdBustConsolation,
        uint32 scaledPre,
        uint256 seed
    ) external pure returns (bool consolationFires) {
        uint32 whole = scaledPre / uint32(TICKET_SCALE);
        uint32 frac = scaledPre % uint32(TICKET_SCALE);
        if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
            unchecked {
                whole += 1;
            }
        }
        consolationFires = payColdBustConsolation && whole == 0;
    }

    /// @notice Expose the raw 16-bit pre-mod slice for chi² independence testing.
    /// @return raw16 `uint16(seed >> 152)` — the full 16-bit slice before the mod-100.
    function bernoulliRaw16(uint256 seed) external pure returns (uint16 raw16) {
        raw16 = uint16(seed >> 152);
    }
}
