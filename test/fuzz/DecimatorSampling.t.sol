// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DecimatorSamplingLib as Sampling} from "../../contracts/libraries/DecimatorSamplingLib.sol";
import {DecimatorSampleReference as Ref} from "../helpers/DecimatorSamplingReference.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

contract DecimatorSamplingTest is Test {
    DegenerusGameLens private lens;

    function setUp() public { lens = new DegenerusGameLens(); }

    function _check(uint256 word, uint24 lvl, uint64 total) private view {
        uint16 count = Sampling.survivors(total);
        assertEq(count, Ref.count(total));
        uint256 rotate = Sampling.rotation(word, lvl, total);
        uint256 previous;
        for (uint256 i; i < count; ++i) {
            uint64 id = Sampling.sample(word, lvl, total, count, rotate, i);
            assertGt(id, 0);
            assertLe(id, total);
            // Inverting rotation yields strictly increasing positions in disjoint strata:
            // this proves pairwise distinct IDs without a quadratic uniqueness scan.
            uint256 pos = (uint256(id) - 1 + total - rotate) % total;
            assertGe(pos, i * total / count);
            assertLt(pos, (i + 1) * total / count);
            if (i != 0) assertGt(pos, previous);
            previous = pos;
            assertTrue(Ref.contains(word, lvl, total, id));
        }
        uint256 quota = (uint256(total) + 9) / 10;
        if (quota < 20) quota = 20;
        if (quota > total / 2) quota = total / 2;
        if (quota > 200) quota = 200;
        assertGe(count, quota, "the sampled field always fills every prize place");
        assertEq(lens.decSurvivorAt(word, lvl, total, 0), Ref.at(word, lvl, total, 0));
        assertEq(lens.decSurvivorAt(word, lvl, total, count - 1), Ref.at(word, lvl, total, count - 1));
    }

    function test_BoundariesAndIndependentPythonKeccakVectors() public view {
        uint64[8] memory totals = [uint64(1),2,3,1999,2000,2001,2500,2199023255550];
        uint64[8] memory first = [uint64(1),2,1,745,994,137,494,477487092165];
        uint64[8] memory middle = [uint64(1),2,2,1744,1993,1136,1743,1574978174598];
        uint64[8] memory last = [uint64(1),2,2,744,992,133,490,475176567688];
        for (uint256 i; i < totals.length; ++i) {
            uint64 total = totals[i];
            uint16 count = Ref.count(total);
            _check(777, 5, total);
            assertEq(lens.decSurvivorAt(777, 5, total, 0), first[i]);
            assertEq(lens.decSurvivorAt(777, 5, total, count / 2), middle[i]);
            assertEq(lens.decSurvivorAt(777, 5, total, count - 1), last[i]);
        }
    }

    function testFuzz_DistinctBoundedSurvivorsAndQuota(uint40 originals, uint40 generated,
        uint256 word, uint24 lvl) public view
    {
        uint64 n = uint64(bound(originals, 1, type(uint40).max));
        uint64 m = uint64(bound(generated, 0, n));
        _check(word, lvl, n + m);
    }

    function test_LensRejectsStrataOutsideTheField() public {
        vm.expectRevert(); lens.decSurvivorAt(777, 5, 0, 0);
        vm.expectRevert(); lens.decSurvivorAt(777, 5, 1, 1);
        vm.expectRevert(); lens.decSurvivorAt(777, 5, 2001, 1000);
    }
}
