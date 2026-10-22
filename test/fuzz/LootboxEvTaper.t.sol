// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {EvTaperRef} from "../helpers/EvTaperRef.sol";

contract EvTaperHarness is DegenerusGameStorage {
    function eligible(uint256 used, uint256 spend) external pure returns (uint256, uint256) {
        return _lootboxEvEligible(used, spend);
    }

    function setUsed(uint32 id, uint24 lvl, uint256 used) external {
        _setLootboxEvUsedFor(id, lvl, used);
    }

    function usedFor(uint32 id, uint24 lvl) external view returns (uint256) {
        return _lootboxEvUsedFor(id, lvl);
    }

    function word(uint32 id) external view returns (uint256) {
        return lootboxEvCapPacked[id];
    }
}

/// @notice The lootbox EV allowance taper: full weight to 10 ETH, half at 20 ETH, zero at 40 ETH,
///         and the 72-bit usage lanes that hold up to 40 ETH.
contract LootboxEvTaperTest is Test {
    EvTaperHarness private h;

    function setUp() public {
        h = new EvTaperHarness();
    }

    function _e(uint256 used, uint256 spend) private view returns (uint256 amount) {
        (amount,) = h.eligible(used, spend);
    }

    function test_SpotValues() public view {
        assertEq(_e(0, 10 ether), 10 ether);
        assertEq(_e(0, 15 ether), 14.375 ether);
        assertEq(_e(0, 20 ether), 17.5 ether);
        assertEq(_e(0, 40 ether), 22.5 ether);
        assertEq(_e(15 ether, 10 ether), 5.3125 ether);
        assertEq(_e(20 ether, 20 ether), 5 ether);
        (uint256 amount, uint256 usedAfter) = h.eligible(0, 100 ether);
        assertEq(amount, 22.5 ether, "the whole allowance");
        assertEq(usedAfter, 40 ether, "usage clamps at the end of the taper");
    }

    function test_ExhaustedAllowanceDrawsNothingAndKeepsUsage() public view {
        (uint256 amount, uint256 usedAfter) = h.eligible(40 ether, 5 ether);
        assertEq(amount, 0);
        assertEq(usedAfter, 40 ether);
        (amount, usedAfter) = h.eligible(41 ether, 5 ether);
        assertEq(amount, 0);
        assertEq(usedAfter, 41 ether);
    }

    /// @dev The marginal weight is continuous at each breakpoint: 1 at 10 ETH, 1/2 at 20 ETH,
    ///      0 at 40 ETH, approached from either side.
    function test_ContinuousAtBreakpoints() public view {
        uint256 d = 1e9; // small enough that the in-step curvature (d^2 / 40 ETH) is under 1 wei
        assertEq(_e(10 ether - d, d), d);
        assertApproxEqAbs(_e(10 ether, d), d, 1);
        assertApproxEqAbs(_e(20 ether - d, d), d / 2, 1);
        assertApproxEqAbs(_e(20 ether, d), d / 2, 1);
        assertLe(_e(40 ether - d, d), 1);
    }

    function testFuzz_FullWeightLegIsExact(uint256 used, uint256 spend) public view {
        used = bound(used, 0, 10 ether);
        spend = bound(spend, 0, 10 ether - used);
        (uint256 amount, uint256 usedAfter) = h.eligible(used, spend);
        assertEq(amount, spend, "identical to the old allowance below 10 ETH");
        assertEq(usedAfter, used + spend);
    }

    function testFuzz_MatchesReference(uint256 used, uint256 spend) public view {
        used = bound(used, 0, 45 ether);
        spend = bound(spend, 0, 100 ether);
        (uint256 amount, uint256 usedAfter) = h.eligible(used, spend);
        (uint256 refAmount, uint256 refUsedAfter) = EvTaperRef.eligible(used, spend);
        assertEq(usedAfter, refUsedAfter);
        assertLe(amount, refAmount, "rounding never favours the player");
        assertGe(amount + 2, refAmount, "one floor per segment");
        assertLe(amount, spend);
    }

    function testFuzz_MonotoneInSpend(uint256 used, uint256 a, uint256 b) public view {
        used = bound(used, 0, 45 ether);
        a = bound(a, 0, 50 ether);
        b = bound(b, 0, 50 ether);
        assertLe(_e(used, a), _e(used, a + b));
    }

    /// @dev Splitting a purchase can only lose wei: no split earns more than buying at once.
    function testFuzz_SplitNeverGains(uint256 used, uint256 a, uint256 b) public view {
        used = bound(used, 0, 45 ether);
        a = bound(a, 0, 50 ether);
        b = bound(b, 0, 50 ether);
        (uint256 first, uint256 mid) = h.eligible(used, a);
        uint256 whole = _e(used, a + b);
        uint256 parts = first + _e(mid, b);
        assertLe(parts, whole);
        assertGe(parts + 3, whole);
    }

    function test_LaneHoldsFortyEthInBothWindows() public {
        h.setUsed(7, 5, 40 ether);
        h.setUsed(7, 6, 39 ether);
        assertEq(h.usedFor(7, 5), 40 ether);
        assertEq(h.usedFor(7, 6), 39 ether);
        assertEq(h.word(7), 40 ether | (uint256(5) << 72) | (39 ether << 96) | (uint256(6) << 168));
        h.setUsed(7, 6, 40 ether);
        assertEq(h.usedFor(7, 5), 40 ether, "a write to one window leaves the other");
        assertEq(h.usedFor(7, 6), 40 ether);
    }

    function test_LaneFullWidthRoundTrips() public {
        uint256 maxUsed = (uint256(1) << 72) - 1;
        h.setUsed(9, 3, maxUsed);
        h.setUsed(9, 4, maxUsed);
        assertEq(h.usedFor(9, 3), maxUsed);
        assertEq(h.usedFor(9, 4), maxUsed);
        assertEq(h.word(9) >> 192, 0, "nothing above the two windows");
    }

    function test_FreshLevelEvictsTheSmallerLevel() public {
        h.setUsed(11, 5, 40 ether);
        h.setUsed(11, 6, 12 ether);
        h.setUsed(11, 7, 3 ether);
        assertEq(h.usedFor(11, 5), 0, "older level evicted");
        assertEq(h.usedFor(11, 6), 12 ether);
        assertEq(h.usedFor(11, 7), 3 ether);
    }

    function test_UnstampedLevelReadsFresh() public {
        h.setUsed(13, 8, 40 ether);
        assertEq(h.usedFor(13, 9), 0);
    }
}
