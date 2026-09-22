// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @notice Mutation-sensitive checks against production math, not a scoring replica.
contract DegeneretteV73MutationKills is Test {
    DegeneretteMathHarness private h;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    function testKillColorGating() public view {
        (uint8 s,) = h.score(0, 0x01010101, 0);
        assertEq(s, 4);
        assertGt(h.payout(s, 0, 1, 1 ether, 0), 0);
    }

    function testKillHeroWeightAndPayFloor() public view {
        (uint8 s,) = h.score(0, 0x09090908, 0);
        assertEq(s, 2);
        assertEq(h.payout(s, 0, 1, 1 ether, 0), 0.45 ether);
        (s,) = h.score(0, 0x09090809, 0);
        assertEq(s, 1);
        assertEq(h.payout(s, 0, 1, 1 ether, 0), 0);
    }

    function testKillUnmatchedGoldBoost() public view {
        (, uint8 g) = h.score(0x38383838, 0, 0);
        assertEq(g, 0);
        (, g) = h.score(0x38383838, 0x38383838, 0);
        assertEq(g, 4);
    }

    function testKillRigJackpotFabrication() public view {
        // All symbols and three colors match: gate succeeds but M=7 must be untouched.
        assertEq(h.rig(0, 8, 0, 0), 8);
        (uint8 s,) = h.score(0, 8, 0);
        assertEq(s, 8);
    }

    function testKillRigFloorOnHeroAlone() public view {
        assertEq(h.rig(0, 0x09090908, 0, 0), 0x09090908);
    }

    function testKillOldSixtyPercentGate() public view {
        uint256 lifted;
        // Exactly two ordinary symbols match; all seven non-hero axes remain score-bearing.
        for (uint256 seed; seed < 1000; ++seed) {
            if (h.rig(0, 0x09080809, 0, seed) != 0x09080809) ++lifted;
        }
        assertEq(lifted, 50);
    }

    function testRigCanHelpColorWithoutItsSymbolAndBoostMatchedGold() public view {
        uint32 p = 0x38383838;
        uint32 r = 0x38383801; // six ordinary matches, hero symbol/color both miss
        uint32 fixedResult = h.rig(p, r, 0, 0);
        assertEq(fixedResult, 0x38383839); // only hero color is eligible
        (uint8 score, uint8 gold) = h.score(p, fixedResult, 0);
        assertEq(score, 7);
        assertEq(gold, 4);
        assertEq(h.payout(score, gold, 3, 1 ether, 0), 729.98849975 ether);
    }
}
