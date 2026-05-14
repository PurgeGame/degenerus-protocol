// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title JackpotBernoulliTester
/// @notice Test helper that exposes the jackpot ticket-roll Bernoulli whole-ticket
///         collapse arithmetic from `DegenerusGameJackpotModule._jackpotTicketRoll`
///         as external-pure passthroughs. Enables direct empirical verification of:
///           - EV-neutrality of the round-up: `E[whole] * 100 == scaledTickets`
///           - Boundary cases at scaledTickets ∈ {0, 1, 99, 100, 101, 199, 200}
///           - bits[200..215] bit-slice independence from the bits[0..12]
///             path/level-selection consumers in the same `entropy` word
///           - 2-roll uniqueness across the `EntropyLib.entropyStep` evolution
///             between the L2157/L2166 medium-amount-branch rolls
///         under Phase 276 v40.0 audit scope (D-276-INLINE-01).
/// @dev    The arithmetic mirrored here is the EXACT instruction sequence that ships
///         in `DegenerusGameJackpotModule._jackpotTicketRoll` (the inline Bernoulli
///         block at v40 HEAD post-Plan-A, committed at c473867e). The test suite
///         asserts byte-identical reproduction by grepping the production source
///         for the canonical predicate `(uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)`;
///         if either drifts, the drift-detection test fails first and the math test
///         becomes informative only after that drift is reconciled. The tester
///         substitutes `seed` for the production `entropy` local — same predicate,
///         same slice offset `>> 200`. Pattern mirrors the `TraitUtilsTester` /
///         `JackpotSoloTester` / `PriceLookupTester` / `LootboxBernoulliTester`
///         precedent. This is the jackpot-surface analog of `LootboxBernoulliTester`
///         with the slice offset adapted `152 -> 200` (the jackpot inline Bernoulli
///         reads bits[200..215]; the lootbox manual/auto-resolve path reads
///         bits[152..167]).
contract JackpotBernoulliTester {
    /// @notice TICKET_SCALE mirror from `DegenerusGameStorage.sol:165`.
    uint256 public constant TICKET_SCALE = 100;

    /// @notice Bernoulli whole-ticket collapse on bits[200..215] of `seed`.
    /// @dev Exact instruction-sequence parity with the inline Bernoulli block of
    ///      `_jackpotTicketRoll` (post-Plan-A, contracts/modules/DegenerusGameJackpotModule.sol):
    ///        uint32 scaledTickets = uint32(quantityScaled);
    ///        uint32 whole = scaledTickets / uint32(TICKET_SCALE);
    ///        uint32 frac  = scaledTickets % uint32(TICKET_SCALE);
    ///        if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) {
    ///            unchecked { whole += 1; }
    ///        }
    ///      The tester substitutes `seed` for the production `entropy` local; the
    ///      predicate and slice offset (`>> 200`) are otherwise byte-identical.
    /// @param scaledTickets Pre-Bernoulli scaled ticket count (== `uint32(quantityScaled)`
    ///                      at the inline-Bernoulli-block entry).
    /// @param seed Per-roll 256-bit entropy word (the production `entropy` local,
    ///             already evolved via `EntropyLib.entropyStep` on `_jackpotTicketRoll` entry).
    /// @return whole Post-collapse whole ticket count.
    /// @return roundedUp True iff the Bernoulli round-up fired (fractional path).
    function bernoulliWhole(uint32 scaledTickets, uint256 seed)
        external
        pure
        returns (uint32 whole, bool roundedUp)
    {
        whole = scaledTickets / uint32(TICKET_SCALE);
        uint32 frac = scaledTickets % uint32(TICKET_SCALE);
        roundedUp = false;
        if (frac != 0 && (uint16(seed >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) {
            unchecked {
                whole += 1;
            }
            roundedUp = true;
        }
    }

    /// @notice Expose the raw bit-slice consumed by the Bernoulli math.
    /// @return slice `uint16(seed >> 200) % uint16(TICKET_SCALE)` — the [0..99] value
    ///               compared against `frac` in the round-up gate.
    function bernoulliSlice(uint256 seed) external pure returns (uint16 slice) {
        slice = uint16(seed >> 200) % uint16(TICKET_SCALE);
    }

    /// @notice Expose the raw 16-bit pre-mod slice for chi² independence testing.
    /// @return raw16 `uint16(seed >> 200)` — the full 16-bit bits[200..215] slice
    ///               before the mod-100.
    function bernoulliRaw16(uint256 seed) external pure returns (uint16 raw16) {
        raw16 = uint16(seed >> 200);
    }
}
