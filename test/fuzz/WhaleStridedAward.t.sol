// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// =============================================================================
// WhaleStridedAward.t.sol
// -----------------------------------------------------------------------------
// Unit coverage for `_queueHalfPassAward` (DegenerusGameStorage): half-pass
// awards decompose into whole-ticket (4-entry) chunks so every chunk spans all
// four trait quadrants at materialization:
//   - base leg: (h/4)*4 entries on every level of the span,
//   - h%4 == 2: one whole ticket every 2nd level (offsets 0, 2, ...),
//   - h%4 == 1: one whole ticket every 4th level (offsets 0, 4, ...),
//   - h%4 == 3: both remainder legs, the every-4th leg shifted +1 so the two
//     cover disjoint levels.
// Invariants under test: per-level owed is always a whole-ticket multiple
// (owed % 4 == 0), total entries are conserved (h × span for 4-aligned spans;
// buyer-favorable ceil on odd spans), each covered level enqueues the buyer
// exactly once, and the strided walk keeps the per-level far-future RNG-lock
// revert of the contiguous walk.
//
// The harness IS the storage contract (every module inherits the identical
// DegenerusGameStorage layout), so owed/queue state is read back directly.
// =============================================================================

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract HalfPassAwardHarness is DegenerusGameStorage {
    function award(
        address buyer,
        uint24 startLevel,
        uint24 span,
        uint256 halfPasses
    ) external {
        _queueHalfPassAward(buyer, startLevel, span, halfPasses, false);
    }

    function setRngLocked(bool v) external {
        rngLockedFlag = v;
    }

    /// @dev Resolve the same key the production walk writes for `lvl` at level 0
    ///      (write slot for lvl <= 5, far-future key beyond) and return owed entries.
    function owedAt(uint24 lvl, address buyer) external view returns (uint32) {
        uint24 key = lvl > level + 5 ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
        return uint32(entriesOwedPacked[key][buyer] >> 8);
    }

    function queueLenAt(uint24 lvl) external view returns (uint256) {
        uint24 key = lvl > level + 5 ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
        return ticketQueue[key].length;
    }
}

contract WhaleStridedAwardTest is Test {
    HalfPassAwardHarness private h;
    address private buyer;

    uint24 private constant START = 1;
    uint24 private constant SPAN = 100;

    function setUp() public {
        h = new HalfPassAwardHarness();
        buyer = makeAddr("strided_buyer");
    }

    /// @dev Sum owed entries across the span and assert per-level whole-ticket
    ///      granularity plus exactly-once queue membership on covered levels.
    function _sumAndCheckGranularity(uint24 span) internal view returns (uint256 sum) {
        for (uint24 i = 0; i < span; ++i) {
            uint32 owed = h.owedAt(START + i, buyer);
            assertEq(owed % 4, 0, "per-level owed must be whole tickets");
            assertEq(
                h.queueLenAt(START + i),
                owed != 0 ? 1 : 0,
                "covered level enqueues buyer exactly once"
            );
            sum += owed;
        }
    }

    /// @notice 1 whale pass (h=2): one whole ticket every 2nd level, nothing between.
    function testSinglePassEveryOtherLevel() public {
        h.award(buyer, START, SPAN, 2);
        for (uint24 i = 0; i < SPAN; ++i) {
            uint32 expected = i % 2 == 0 ? 4 : 0;
            assertEq(h.owedAt(START + i, buyer), expected, "h=2 stride-2 shape");
        }
        assertEq(_sumAndCheckGranularity(SPAN), 200, "h=2 conserves 2 x span");
    }

    /// @notice 2 passes (h=4): dense whole ticket per level — same coverage as the
    ///         legacy 4-entries-per-level award.
    function testTwoPassesDense() public {
        h.award(buyer, START, SPAN, 4);
        for (uint24 i = 0; i < SPAN; ++i) {
            assertEq(h.owedAt(START + i, buyer), 4, "h=4 dense shape");
        }
        assertEq(_sumAndCheckGranularity(SPAN), 400, "h=4 conserves 4 x span");
    }

    /// @notice 3 passes (h=6): dense base plus one extra ticket every 2nd level.
    function testThreePassesBasePlusStride() public {
        h.award(buyer, START, SPAN, 6);
        for (uint24 i = 0; i < SPAN; ++i) {
            uint32 expected = i % 2 == 0 ? 8 : 4;
            assertEq(h.owedAt(START + i, buyer), expected, "h=6 base+stride shape");
        }
        assertEq(_sumAndCheckGranularity(SPAN), 600, "h=6 conserves 6 x span");
    }

    /// @notice 1 half-pass (h=1): one whole ticket every 4th level.
    function testSingleHalfPassEveryFourth() public {
        h.award(buyer, START, SPAN, 1);
        for (uint24 i = 0; i < SPAN; ++i) {
            uint32 expected = i % 4 == 0 ? 4 : 0;
            assertEq(h.owedAt(START + i, buyer), expected, "h=1 stride-4 shape");
        }
        assertEq(_sumAndCheckGranularity(SPAN), 100, "h=1 conserves 1 x span");
    }

    /// @notice 3 half-passes (h=3): stride-2 leg at offsets 0,2,... plus stride-4 leg
    ///         at offsets 1,5,... — disjoint, so no level holds more than one chunk.
    function testRemainderThreeDisjointLegs() public {
        h.award(buyer, START, SPAN, 3);
        for (uint24 i = 0; i < SPAN; ++i) {
            uint32 expected;
            if (i % 2 == 0) expected = 4;
            else if (i % 4 == 1) expected = 4;
            else expected = 0;
            uint32 owed = h.owedAt(START + i, buyer);
            assertEq(owed, expected, "h=3 disjoint-legs shape");
            assertLe(owed, 4, "remainder legs never stack on one level");
        }
        assertEq(_sumAndCheckGranularity(SPAN), 300, "h=3 conserves 3 x span");
    }

    /// @notice 5 half-passes (h=5): dense base plus the stride-4 remainder.
    function testFiveHalfPassesBasePlusQuarterStride() public {
        h.award(buyer, START, SPAN, 5);
        for (uint24 i = 0; i < SPAN; ++i) {
            uint32 expected = i % 4 == 0 ? 8 : 4;
            assertEq(h.owedAt(START + i, buyer), expected, "h=5 base+stride-4 shape");
        }
        assertEq(_sumAndCheckGranularity(SPAN), 500, "h=5 conserves 5 x span");
    }

    /// @notice Odd span rounds covered-level counts up: h=2 over 91 levels covers 46
    ///         levels (184 entries — at most one whole ticket over 2 x 91, buyer-favorable).
    function testOddSpanCeilBuyerFavorable() public {
        h.award(buyer, START, 91, 2);
        assertEq(h.owedAt(START + 90, buyer), 4, "last even offset of odd span covered");
        assertEq(h.owedAt(START + 89, buyer), 0, "odd offsets uncovered");
        assertEq(_sumAndCheckGranularity(91), 184, "ceil rounding adds at most one ticket");
    }

    /// @notice h=0 is a no-op (award sites guard it, the helper must still be safe).
    function testZeroHalfPassesNoop() public {
        h.award(buyer, START, SPAN, 0);
        assertEq(_sumAndCheckGranularity(SPAN), 0, "h=0 queues nothing");
    }

    /// @notice The strided walk preserves the per-level RNG-lock revert: any leg
    ///         reaching past level+5 under an RNG lock reverts like the contiguous walk.
    function testRngLockBlocksStridedFarFuture() public {
        h.setRngLocked(true);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.award(buyer, START, SPAN, 2);
    }

    /// @notice Fuzz: for any half-pass count, per-level owed stays whole-ticket and the
    ///         total is exactly h x span on the 4-aligned 100-level span.
    function testFuzzConservationAndGranularity(uint256 halfPasses) public {
        halfPasses = bound(halfPasses, 0, 1000);
        h.award(buyer, START, SPAN, halfPasses);
        assertEq(
            _sumAndCheckGranularity(SPAN),
            halfPasses * SPAN,
            "total entries = halfPasses x span"
        );
    }
}
