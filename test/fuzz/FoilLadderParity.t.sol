// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";

/// @title FoilLadderParityTest
/// @notice Pins the live foil producer — `foilCuts(multBps)` (the cumulative
///         cutoff ladder) + `foilTrait(s, cut)` (the walk + symbol) — against a
///         frozen reference copy of the prior inline producer. The ladder depends
///         only on multBps, so it is hoisted once; these fuzz proofs assert the
///         hoist is byte-identical and the ladder stays well-formed (monotone,
///         sums to exactly 15360) across the full multBps range [20000, 60000].
contract FoilLadderParityTest is Test {
    /// @dev Frozen reference: the pre-refactor inline `traitFromWordFoil` body.
    function _oldTraitFromWordFoil(uint64 s, uint16 multBps) internal pure returns (uint8) {
        unchecked {
            uint256 boost = uint256(multBps) - 10000;
            uint256 w3 = uint256(32) * 60;
            uint256 w4 = (uint256(16) * 60 * (50000 + boost * 2)) / 50000;
            uint256 w5 = (uint256(8) * 60 * (50000 + boost * 3)) / 50000;
            uint256 w6 = (uint256(6) * 60 * (50000 + boost * 4)) / 50000;
            uint256 w7 = (uint256(2) * 60 * (50000 + boost * 5)) / 50000;
            uint256 rem = 15360 - (w3 + w4 + w5 + w6 + w7);
            uint256 common = rem / 3;
            uint256 c0 = common + (rem - common * 3);

            uint256 scaled = (uint64(uint32(s)) * 15360) >> 32;
            uint8 color;
            uint256 cut = c0;
            if (scaled < cut) color = 0;
            else if (scaled < (cut += common)) color = 1;
            else if (scaled < (cut += common)) color = 2;
            else if (scaled < (cut += w3)) color = 3;
            else if (scaled < (cut += w4)) color = 4;
            else if (scaled < (cut += w5)) color = 5;
            else if (scaled < (cut += w6)) color = 6;
            else color = 7;

            uint8 symbol = uint8(s >> 32) & 7;
            return (color << 3) | symbol;
        }
    }

    /// @dev Map a raw fuzz word into the valid frozen multiplier range.
    function _mult(uint16 raw) internal pure returns (uint16) {
        return uint16(20000 + (uint256(raw) % 40001)); // [20000, 60000]
    }

    /// @notice The hoist path foilTrait(s, foilCuts(m)) — the live foil producer
    ///         used by the queue drain and the foil claim — equals the old inline
    ///         producer.
    function testFuzz_foilTraitHoistParity(uint64 s, uint16 raw) public {
        uint16 m = _mult(raw);
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(m);
        assertEq(DegenerusTraitUtils.foilTrait(s, cut), _oldTraitFromWordFoil(s, m));
    }

    /// @notice The cutoff ladder is monotone non-decreasing and the seven cutoffs
    ///         plus the gold width sum to exactly 15360 (no negative widths) across
    ///         the full multiplier range.
    function testFuzz_foilCutsWellFormed(uint16 raw) public {
        uint16 m = _mult(raw);
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(m);
        for (uint256 i = 1; i < 7; i++) {
            assertLe(cut[i - 1], cut[i]);
        }
        uint256 boost = uint256(m) - 10000;
        uint256 w7 = (uint256(2) * 60 * (50000 + boost * 5)) / 50000;
        assertEq(cut[6] + w7, 15360); // gold region = [cut[6], 15360)
        assertLe(cut[6], 15360);
    }
}
