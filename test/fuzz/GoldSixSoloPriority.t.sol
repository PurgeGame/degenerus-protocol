// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {JackpotSoloTester} from "../../contracts/test/JackpotSoloTester.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";

contract GoldSixSoloPriorityTest is Test {
    JackpotSoloTester private picker;

    function setUp() public { picker = new JackpotSoloTester(); }

    function testFuzzSurvivingGoldSixWinsAgainstEveryOtherBoard(
        uint8 a, uint8 b, uint8 c, uint256 entropy
    ) public view {
        uint8[4] memory traits = [a & 63, (b & 63) | 64, (c & 63) | 128, uint8(253)];
        assertEq(picker.pickSoloQuadrant(traits, entropy), 3);
    }

    function testAllGoldBoardOnlyGivesDicePriorityWhenGoldSixSurvives() public view {
        bool kept;
        bool replaced;
        for (uint256 word; word < 100 && !(kept && replaced); ++word) {
            uint8 dice = GoldSixLib.daily(253, word);
            uint8[4] memory traits = [uint8(56), 120, 184, dice];
            // Entropy zero would choose quadrant zero in the ordinary four-gold tie.
            uint8 solo = picker.pickSoloQuadrant(traits, 0);
            if (dice == 253) {
                assertEq(solo, 3);
                kept = true;
            } else {
                assertEq(solo, 0);
                replaced = true;
            }
        }
        assertTrue(kept && replaced, "both daily survival outcomes exercised");
    }

    function testSilverSixDoesNotTrumpAnotherGold() public view {
        uint8[4] memory traits = [uint8(56), 64, 128, 245];
        assertEq(picker.pickSoloQuadrant(traits, type(uint256).max), 0);
    }

    function testFuzzOtherBoardsKeepTheirOriginalRotationAndGoldTieBreak(uint256 entropy) public view {
        for (uint8 mask; mask < 16; ++mask) {
            uint8[4] memory traits;
            uint8[4] memory golds;
            uint8 count;
            for (uint8 q; q < 4; ++q) {
                traits[q] = q * 64;
                if ((mask & (1 << q)) != 0) {
                    traits[q] |= 56; // Gold symbol zero, including Dice: never gold six.
                    golds[count++] = q;
                }
            }
            uint8 expected = count == 0 ? uint8(3 - (entropy & 3)) : golds[(entropy >> 4) % count];
            assertEq(picker.pickSoloQuadrant(traits, entropy), expected);
        }
    }
}
