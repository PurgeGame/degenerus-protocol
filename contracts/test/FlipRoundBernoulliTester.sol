// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";

/// @title FlipRoundBernoulliTester
/// @notice Test helper that exposes `FlipRoundLib.roundFlipToHundreds` and the threshold
///         gate wrapped around it at every call site, as external-pure passthroughs.
///         Enables direct empirical verification of:
///           - EV-neutrality of the collapse: `E[rounded] ≈ floorWholeFlip(amount)`
///             (exact under an ideal uniform mod-100 draw; the uint32 % 100 bias is ~2e-8)
///           - Boundary cases at remainders {0, 1, 37, 50, 99} whole FLIP, and the
///             zero-dust decomposition (FLIP has 0 decimals, so no sub-token residue exists)
///           - The `> FLIP_ROUND_THRESHOLD` gate: at or below 1,000 FLIP the award is
///             paid unchanged, so small wins never round to nothing
/// @dev    The arithmetic mirrored here is the EXACT library the production sites call —
///         this tester delegates rather than re-implementing, so no drift is possible in
///         the primitive itself. The threshold gate IS re-implemented (production inlines
///         it at each site), and the suite grep-pins the production form.
contract FlipRoundBernoulliTester {
    /// @notice Mirrors of the `FlipRoundLib` constants, for assertion in JS.
    uint256 public constant FLIP_ROUND_UNIT = FlipRoundLib.FLIP_ROUND_UNIT;
    uint256 public constant FLIP_ROUND_THRESHOLD =
        FlipRoundLib.FLIP_ROUND_THRESHOLD;

    /// @notice The bare primitive, ungated.
    /// @param amount Raw award in whole FLIP (FLIP has 0 decimals).
    /// @param entropy Word derived from a committed VRF word plus immutable award data.
    /// @return rounded `amount` collapsed onto a multiple of `FLIP_ROUND_UNIT`.
    function roundFlipToHundreds(uint256 amount, uint256 entropy)
        external
        pure
        returns (uint256 rounded)
    {
        rounded = FlipRoundLib.roundFlipToHundreds(amount, entropy);
    }

    /// @notice The primitive behind the threshold gate every §3c call site applies.
    /// @dev Instruction-sequence parity with the production gate:
    ///        amount = amount > FlipRoundLib.FLIP_ROUND_THRESHOLD
    ///            ? FlipRoundLib.roundFlipToHundreds(amount, entropy)
    ///            : amount;
    /// @return paid The amount the site credits: collapsed onto a 100-FLIP multiple above
    ///              the threshold, unchanged at or below it.
    function roundGated(uint256 amount, uint256 entropy)
        external
        pure
        returns (uint256 paid)
    {
        paid = amount > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(amount, entropy)
            : amount;
    }

    /// @notice The sub-threshold half of the policy, exposed on its own (FLIP has 0
    ///         decimals, so the amount passes through unchanged).
    /// @return floored `amount`, unchanged.
    function floorWholeFlip(uint256 amount)
        external
        pure
        returns (uint256 floored)
    {
        floored = amount;
    }

    /// @notice Decompose an award the way the primitive does, for boundary assertions.
    /// @return hundreds Whole 100-FLIP units in `amount`.
    /// @return remFlip The 0..99 whole-FLIP remainder the round-up probability keys on.
    /// @return dustWei Always zero: whole-FLIP amounts leave no sub-token residue.
    function decompose(uint256 amount)
        external
        pure
        returns (uint256 hundreds, uint256 remFlip, uint256 dustWei)
    {
        hundreds = amount / FlipRoundLib.FLIP_ROUND_UNIT;
        remFlip = amount % FlipRoundLib.FLIP_ROUND_UNIT;
        dustWei = 0;
    }

    /// @notice Expose the [0..99] compare value consumed by the round-up gate.
    /// @return slice `uint32(entropy) % 100` — compared against the whole-FLIP remainder.
    function roundSlice(uint256 entropy) external pure returns (uint32 slice) {
        slice = uint32(uint32(entropy) % 100);
    }

    /// @notice Expose the raw 32-bit pre-mod window for chi² independence testing.
    /// @return raw32 `uint32(entropy)` — the full 32-bit window before the mod-100.
    function roundRaw32(uint256 entropy) external pure returns (uint32 raw32) {
        raw32 = uint32(entropy);
    }
}
