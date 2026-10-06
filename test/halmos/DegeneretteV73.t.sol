// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @title Degenerette wild-color symbolic proofs (Halmos track).
/// @notice Proves, for all 2^32 × 2^32 (player, house) words, facts about the branch-free `_score`
///         (DegenerusGameDegeneretteModule.sol) through a loop mirror:
///
///         (0) PARITY — production `_score` returns the mirror's score and house wild count for
///             every input (bit 7 of a lane is ignored by both).
///
///         (1) SCORE BOUND — on a valid board (the player's only wild is the hero lane) the score is
///             in {1..9}, so the payout table is never indexed outside its calibrated domain.
///
///         (2) JACKPOT CHARACTERIZATION — on a valid board, `score == 9` exactly when all eight
///             axes match (M == 8, the hero color counting once) AND the house hero lane is wild.
///             Score = M + (house hero lane wild), so a WWXRP help (honest M <= 6, one axis forced)
///             leaves M <= 7 and the score below 9: the rig cannot fabricate the jackpot.
///
/// @dev FOUNDRY_PROFILE=halmos halmos --contract DegeneretteV73HalmosTest --forge-build-out forge-out-halmos --loop 5 --solver-timeout-assertion 120000
contract DegeneretteV73HalmosTest is Test {
    DegeneretteMathHarness private h;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    function _lane(uint32 word, uint8 q) private pure returns (uint8) {
        return uint8(word >> (q * 8));
    }

    /// @dev Loop mirror: symbol equal +1; color: two wilds +2, one wild +1, else equal colors +1.
    function _score(uint32 pt, uint32 rt) internal pure returns (uint8 s, uint8 w) {
        for (uint8 q = 0; q < 4; ) {
            uint8 a = _lane(pt, q);
            uint8 b = _lane(rt, q);
            bool aw = a & 0x40 != 0;
            bool bw = b & 0x40 != 0;
            unchecked {
                if ((a & 7) == (b & 7)) ++s;
                if (aw && bw) s += 2;
                else if (aw || bw) ++s;
                else if (((a >> 3) & 7) == ((b >> 3) & 7)) ++s;
                if (bw) ++w;
                ++q;
            }
        }
    }

    /// @dev Matched axes, the hero color counting once: symbols plus colors matched by equality
    ///      or by any wild.
    function _matchCount(uint32 pt, uint32 rt) internal pure returns (uint8 m) {
        for (uint8 q = 0; q < 4; ) {
            uint8 a = _lane(pt, q);
            uint8 b = _lane(rt, q);
            unchecked {
                if ((a & 7) == (b & 7)) ++m;
                if ((a | b) & 0x40 != 0 || ((a >> 3) & 7) == ((b >> 3) & 7)) ++m;
                ++q;
            }
        }
    }

    function _validPlayer(uint32 pt, uint8 hero) private pure returns (bool) {
        return hero < 4 && pt & 0x40404040 == uint32(0x40) << (hero * 8);
    }

    /// @notice (0) The production `_score` equals the loop mirror everywhere.
    function check_production_score_matches_mirror(uint32 pt, uint32 rt) public view {
        (uint8 s, uint8 w) = h.score(pt, rt);
        (uint8 ms, uint8 mw) = _score(pt, rt);
        assert(s == ms);
        assert(w == mw);
    }

    /// @notice (1) On a valid board the score is in {1..9}.
    function check_score_in_range(uint32 pt, uint32 rt, uint8 hero) public pure {
        vm.assume(_validPlayer(pt, hero));
        (uint8 s,) = _score(pt, rt);
        assert(s >= 1 && s <= 9);
    }

    /// @notice (2) On a valid board, S9 iff all eight axes match and the house hero lane is wild.
    function check_score9_iff_allMatch_and_heroWild(uint32 pt, uint32 rt, uint8 hero) public pure {
        vm.assume(_validPlayer(pt, hero));
        (uint8 s,) = _score(pt, rt);
        bool heroWild = _lane(rt, hero) & 0x40 != 0;
        assert((s == 9) == (_matchCount(pt, rt) == 8 && heroWild));
    }

    /// @notice Corollary used by the rig: at most seven matched axes never score the jackpot.
    function check_le7_axes_never_jackpot(uint32 pt, uint32 rt, uint8 hero) public pure {
        vm.assume(_validPlayer(pt, hero));
        vm.assume(_matchCount(pt, rt) <= 7);
        (uint8 s,) = _score(pt, rt);
        assert(s < 9);
    }
}
