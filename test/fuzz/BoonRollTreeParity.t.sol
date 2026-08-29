// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {DeityBoonViewer} from "../../contracts/DeityBoonViewer.sol";

contract BoonRollTreeHarness is DegenerusGameBoonModule {
    function tree(uint256 roll) external pure returns (uint8) {
        return _boonFromRoll(roll);
    }
}

contract DeityBoonViewerTreeHarness is DeityBoonViewer {
    function tree(uint256 roll) external pure returns (uint8) {
        return _boonFromRoll(roll);
    }
}

contract BoonRollTreeParity is Test {
    BoonRollTreeHarness private harness;
    DeityBoonViewerTreeHarness private viewerHarness;

    function setUp() public {
        harness = new BoonRollTreeHarness();
        viewerHarness = new DeityBoonViewerTreeHarness();
    }

    function testEveryReachableWeightedRollMatchesCanonicalReference() public view {
        for (uint256 roll; roll < 2856; ++roll) {
            assertEq(harness.tree(roll), _reference(roll), "boon boundary drift");
        }
    }

    /// @dev The viewer restates the module's tree because neither contract can read the other;
    ///      this is what holds the two statements together on every reachable roll.
    function testViewerTreeMatchesCanonicalReferenceEverywhere() public view {
        for (uint256 roll; roll < 2856; ++roll) {
            assertEq(viewerHarness.tree(roll), _reference(roll), "viewer boundary drift");
        }
    }

    /// @dev Independent cumulative-boundary reference for the canonical static table.
    function _reference(uint256 roll) private pure returns (uint8) {
        if (roll < 200) return 1;
        if (roll < 240) return 2;
        if (roll < 248) return 3;
        if (roll < 448) return 5;
        if (roll < 478) return 6;
        if (roll < 486) return 22;
        if (roll < 886) return 7;
        if (roll < 966) return 8;
        if (roll < 982) return 9;
        if (roll < 1022) return 13;
        if (roll < 1030) return 14;
        if (roll < 1032) return 15;
        if (roll < 1060) return 16;
        if (roll < 1070) return 23;
        if (roll < 1072) return 24;
        if (roll < 1100) return 25;
        if (roll < 1110) return 26;
        if (roll < 1112) return 27;
        if (roll < 1212) return 17;
        if (roll < 1242) return 18;
        if (roll < 1246) return 19;
        if (roll < 1446) return 4;
        if (roll < 1448) return 28;
        if (roll < 1478) return 29;
        if (roll < 1486) return 30;
        if (roll < 1488) return 31;
        if (roll < 1688) return 32;
        if (roll < 1738) return 33;
        if (roll < 1748) return 34;
        if (roll < 1948) return 35;
        if (roll < 1998) return 36;
        if (roll < 2008) return 37;
        if (roll < 2208) return 38;
        if (roll < 2408) return 39;
        if (roll < 2608) return 40;
        if (roll < 2808) return 41;
        if (roll < 2848) return 42;
        return 43;
    }
}
