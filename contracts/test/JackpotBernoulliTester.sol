// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title JackpotBernoulliTester
/// @notice Test helper that exposes the jackpot ticket-roll Bernoulli whole-ticket
///         collapse arithmetic from `DegenerusGameJackpotModule._jackpotTicketRoll`
///         as external-pure passthroughs. Enables direct empirical verification of:
///           - EV-neutrality of the round-up: `E[whole] * 100 == scaledTickets`
///           - Boundary cases at scaledTickets ∈ {0, 1, 99, 100, 101, 199, 200}
///           - bits[96..127] bit-slice independence from the bits[0..12]
///             path/level-selection consumers in the same `entropy` word
///           - 2-roll uniqueness across the `EntropyLib.hash2(entropy, entropy)`
///             keccak self-mix evolution between the medium-amount-branch rolls
/// @dev    The arithmetic mirrored here is the EXACT instruction sequence that ships
///         in `DegenerusGameJackpotModule._jackpotTicketRoll` (the inline Bernoulli
///         block). The test suite asserts byte-identical reproduction by grepping the
///         production source for the canonical predicate
///         `(uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac`; if either drifts,
///         the drift-detection test fails first and the math test becomes informative
///         only after that drift is reconciled. The tester substitutes `seed` for the
///         production `entropy` local — same predicate, same slice offset `>> 96`.
///         This is the jackpot-surface analog of `LootboxBernoulliTester` with the
///         slice offset adapted `224 -> 96` (the jackpot inline Bernoulli reads
///         bits[96..127]; the lootbox manual/auto-resolve path reads bits[224..255]).
///         The round-up reads a uint32 window so the `% QTY_SCALE` modulo bias is
///         negligible (~2e-8).
contract JackpotBernoulliTester {
    /// @notice QTY_SCALE mirror from `DegenerusGameStorage.sol`.
    uint256 public constant QTY_SCALE = 100;

    /// @notice Bernoulli whole-ticket collapse on bits[96..127] of `seed`.
    /// @dev Exact instruction-sequence parity with the inline Bernoulli block of
    ///      `_jackpotTicketRoll` (contracts/modules/DegenerusGameJackpotModule.sol):
    ///        uint32 scaledTickets = uint32(quantityScaled);
    ///        uint32 whole = scaledTickets / uint32(QTY_SCALE);
    ///        uint32 frac  = scaledTickets % uint32(QTY_SCALE);
    ///        if (frac != 0 && (uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac) {
    ///            unchecked { whole += 1; }
    ///        }
    ///      The tester substitutes `seed` for the production `entropy` local; the
    ///      predicate and slice offset (`>> 96`) are otherwise byte-identical.
    /// @param scaledTickets Pre-Bernoulli scaled ticket count (== `uint32(quantityScaled)`
    ///                      at the inline-Bernoulli-block entry).
    /// @param seed Per-roll 256-bit entropy word (the production `entropy` local,
    ///             already evolved via `EntropyLib.hash2(entropy, entropy)` on
    ///             `_jackpotTicketRoll` entry).
    /// @return whole Post-collapse whole ticket count.
    /// @return roundedUp True iff the Bernoulli round-up fired (fractional path).
    function bernoulliWhole(uint32 scaledTickets, uint256 seed)
        external
        pure
        returns (uint32 whole, bool roundedUp)
    {
        whole = scaledTickets / uint32(QTY_SCALE);
        uint32 frac = scaledTickets % uint32(QTY_SCALE);
        roundedUp = false;
        if (frac != 0 && (uint32(seed >> 96) % uint32(QTY_SCALE)) < frac) {
            unchecked {
                whole += 1;
            }
            roundedUp = true;
        }
    }

    /// @notice Expose the [0..99] compare value consumed by the Bernoulli math.
    /// @return slice `uint32(seed >> 96) % uint32(QTY_SCALE)` — the [0..99] value
    ///               compared against `frac` in the round-up gate.
    function bernoulliSlice(uint256 seed) external pure returns (uint32 slice) {
        slice = uint32(seed >> 96) % uint32(QTY_SCALE);
    }

    /// @notice Expose the raw 32-bit pre-mod slice for chi² independence testing.
    /// @return raw32 `uint32(seed >> 96)` — the full 32-bit bits[96..127] slice
    ///               before the mod-100.
    function bernoulliRaw32(uint256 seed) external pure returns (uint32 raw32) {
        raw32 = uint32(seed >> 96);
    }
}
