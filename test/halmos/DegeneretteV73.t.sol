// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @title Degenerette v73 independent-color symbolic proofs (pillar hardening — Halmos track).
/// @notice Proves for ALL 2^32 × 2^32 (player, reel) tickets and every hero quadrant the two
///         load-bearing arithmetic facts the audit argued informally — on a loop mirror of
///         `_score` (DegenerusGameDegeneretteModule.sol), the form it had before the branch-free
///         rewrite (same approach as SolvencyArithmetic.t.sol mirroring the storage packing).
///         (0) binds the production `_score` to that mirror for every input, so (1) and (2) hold
///         for the deployed code:
///
///         (0) PARITY — the production branch-free `_score` returns the mirror's score and
///             matched-gold count for all 2^32 × 2^32 tickets and every hero byte.
///
///         (1) SCORE BOUND — `_score` is always in {0..9}. A score outside that range would index
///             the packed payout slot / S8 / S9 dispatch out of its calibrated domain (a solvency /
///             OOB hazard). Proven ⇒ `_getBasePayoutBps` is always reached with s ≤ 9.
///
///         (2) JACKPOT CHARACTERIZATION — `_score == 9  ⟺  all 8 axes match (M == 8)`. This is the
///             load-bearing lemma behind "the WWXRP rig can NEVER fabricate the S=9 jackpot": the rig
///             fires only when honest M ≤ 6 and forces exactly ONE axis (a code fact pinned by
///             test/mutation/DegeneretteV73MutationKills.t.sol), so post-force M ≤ 7 < 8, hence by (2)
///             the rigged score is never 9. (1)+(2) are the symbolic backbone of the RNG/solvency
///             pillar attestation.
///
/// @dev halmos --contract DegeneretteV73HalmosTest --solver-timeout-assertion 120000
contract DegeneretteV73HalmosTest is Test {
    DegeneretteMathHarness private h;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    /// @dev Matched gold per the loop form: a quadrant whose colors match and whose player color is
    ///      gold (7) counts once.
    function _goldMatches(uint32 playerTicket, uint32 resultTicket) internal pure returns (uint8 g) {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7) && ((pQuad >> 3) & 7) == 7) {
                unchecked {
                    ++g;
                }
            }
            unchecked {
                ++q;
            }
        }
    }

    /// @notice (0) The production `_score` equals the loop mirror everywhere.
    function check_production_score_matches_mirror(uint32 pt, uint32 rt, uint8 hero) public view {
        (uint8 s, uint8 g) = h.score(pt, rt, hero);
        assert(s == _score(pt, rt, hero));
        assert(g == _goldMatches(pt, rt));
    }

    /// @dev Exact mirror of the FROZEN independent-color `_score`: per quadrant a symbol match scores +1
    ///      (hero +2); the quadrant's color independently scores +1.
    function _score(uint32 playerTicket, uint32 resultTicket, uint8 heroQuadrant)
        internal
        pure
        returns (uint8 s)
    {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            if ((pQuad & 7) == (rQuad & 7)) {
                unchecked {
                    s += (q == heroQuadrant) ? 2 : 1;

                }
            }
            if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7)) ++s;
            unchecked {
                ++q;
            }
        }
    }

    /// @dev Count all 8 per-axis matches (color + symbol per quadrant) — the rig's `m`.
    function _matchCount(uint32 playerTicket, uint32 resultTicket) internal pure returns (uint8 m) {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));
            if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7)) {
                unchecked {
                    ++m;
                }
            }
            if ((pQuad & 7) == (rQuad & 7)) {
                unchecked {
                    ++m;
                }
            }
            unchecked {
                ++q;
            }
        }
    }

    /// @notice (1) `_score` is bounded to {0..9} for every input (hero quadrant < 4).
    function check_score_in_range(uint32 pt, uint32 rt, uint8 hero) public pure {
        vm.assume(hero < 4);
        uint8 s = _score(pt, rt, hero);
        assert(s <= 9);
    }

    /// @notice (2) `_score == 9` exactly characterizes the all-8-axes match (M == 8) — neither side
    ///         can hold without the other. This is what makes the m>=7 rig cap a hard no-S=9 guarantee.
    function check_score9_iff_allMatch(uint32 pt, uint32 rt, uint8 hero) public pure {
        vm.assume(hero < 4);
        uint8 s = _score(pt, rt, hero);
        uint8 m = _matchCount(pt, rt);
        assert((s == 9) == (m == 8));
    }

    /// @notice Corollary used by the rig: if at most 7 axes match (M <= 7) the score is never the
    ///         jackpot. (Direct consequence of (2); stated separately as the exact post-force bound —
    ///         a fired rig roll starts at M <= 6 and adds one axis, so M <= 7 here.)
    function check_le7_axes_never_jackpot(uint32 pt, uint32 rt, uint8 hero) public pure {
        vm.assume(hero < 4);
        uint8 m = _matchCount(pt, rt);
        vm.assume(m <= 7);
        uint8 s = _score(pt, rt, hero);
        assert(s < 9);
    }
}
