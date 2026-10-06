// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";

/// @notice Mutation-sensitive checks against production math, not a scoring replica.
/// @dev Boards: the player's lane 0 is its wild hero (0x40 = symbol 0), other player lanes color 0
///      symbol 0 unless stated; house lane 0x09 (color 1, symbol 1) misses both axes.
contract DegeneretteV73MutationKills is Test {
    DegeneretteMathHarness private h;

    function setUp() public {
        h = new DegeneretteMathHarness();
    }

    function testKillHeroDoubleSymbolWeightAndPayFloor() public view {
        (uint8 s,) = h.score(0x40, 0x09090908); // hero symbol + guaranteed hero color only
        assertEq(s, 2);
        assertEq(h.payout(s, 0, 1, 1 ether, 0), 0);
        assertEq(h.payout(3, 0, 1, 1 ether, 0), 0.45 ether);
    }

    function testKillSymbolGatedHeroColor() public view {
        (uint8 s,) = h.score(0x40, 0x09090909);
        assertEq(s, 1, "the hero color scores without its symbol");
    }

    function testKillOneSidedWildScoredAsTwo() public view {
        (uint8 s, uint8 w) = h.score(0x40, 0x09094909); // house wild meets an ordinary player color
        assertEq(s, 2);
        assertEq(w, 1);
        (s, w) = h.score(0x40, 0x09090949); // wild meets wild on the hero lane
        assertEq(s, 2);
        assertEq(w, 1);
    }

    function testKillGoldPremium() public view {
        (uint8 gold, uint8 goldWilds) = h.score(0x38383840, 0x38383809);
        (uint8 plain, uint8 plainWilds) = h.score(0x10101040, 0x10101009);
        assertEq(gold, plain);
        assertEq(goldWilds, 0);
        assertEq(plainWilds, 0);
    }

    function testKillPlayerWildCountedInWilds() public view {
        (, uint8 w) = h.score(0x40, 0x09090909);
        assertEq(w, 0, "only house wilds multiply the payout");
        (, w) = h.score(0x40, 0x49494949);
        assertEq(w, 4);
    }

    function testKillRigJackpotFabrication() public view {
        // Hero symbol and every other axis but one symbol match: M = 7, never helped.
        assertEq(h.rig(0x40, 0x00000100, 0, 0), 0x00000100);
        (uint8 s,) = h.score(0x40, 0x00000100);
        assertEq(s, 7);
        // The same board with a house wild on the hero lane scores 8 and is still M = 7.
        assertEq(h.rig(0x40, 0x00000140, 0, 0), 0x00000140);
    }

    function testKillRigFloorBelowPayingScore() public view {
        assertEq(h.rig(0x40, 0x09090908, 0, 0), 0x09090908, "a score-2 bust is never rescued");
    }

    function testKillOldSixtyPercentGate() public view {
        uint256 lifted;
        // Score 3: hero symbol, hero color and one ordinary symbol.
        for (uint256 seed; seed < 1000; ++seed) {
            if (h.rig(0x40, 0x09090808, 0, seed) != 0x09090808) ++lifted;
        }
        assertEq(lifted, 50);
    }

    function testRigHelpsColorWithoutItsSymbolAndNeverTouchesWilds() public view {
        uint32 p = 0x38383840; // lanes 1..3 gold, symbol 0
        uint32 r = 0x40380001; // M = 6: only lane 1's color is eligible
        uint32 fixedResult = h.rig(p, r, 0, 0);
        assertEq(fixedResult, 0x40383801);
        (uint8 score, uint8 wilds) = h.score(p, fixedResult);
        assertEq(score, 7);
        assertEq(wilds, 1);
        assertEq(h.payout(score, wilds, 3, 1 ether, 0), 450.192883046875 ether);
    }
}
