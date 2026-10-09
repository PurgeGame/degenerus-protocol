// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Burns exactly `amount` gas (to loop granularity), or runs out of gas trying.
function burnGas(uint256 amount) view {
    uint256 g = gasleft();
    uint256 stop = g > amount ? g - amount : 0;
    while (gasleft() > stop) {}
}

function bubble(bytes memory data) pure {
    assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
}

/// @dev Metered work in its own frame and storage, reached by CALL like the Craps and
///      sDGNRS workers. A unit's declared size covers its burn, so estimates are honest
///      unless `runLying` says otherwise.
contract NestingWorker {
    uint256 internal constant UNIT_SLACK = 30_000;
    uint256 internal constant TAIL = 40_000;
    uint256 public units;

    function run(uint256 allowance, uint256 prelude, uint256 unitGas, uint256 maxUnits)
        external returns (MineFlipGas.Result memory r)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        burnGas(prelude);
        uint256 n;
        while (n < maxUnits && MineFlipGas.canRun(meter, unitGas + UNIT_SLACK, TAIL)) {
            burnGas(unitGas);
            ++n;
            MineFlipGas.markProgress(meter);
        }
        if (n != 0) {
            units += n;
            r.progressed = true;
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Units admitted on `declared` but actually burning `firstActual`, then `laterActual`.
    function runLying(uint256 allowance, uint256 declared, uint256 firstActual, uint256 laterActual, uint256 maxUnits)
        external returns (uint256 n)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        while (n < maxUnits && MineFlipGas.canRun(meter, declared, 0)) {
            burnGas(n == 0 ? firstActual : laterActual);
            ++n;
            MineFlipGas.markProgress(meter);
        }
        units += n;
        MineFlipGas.finish(meter);
    }

    /// @dev The meter as `start` builds it, bracketed by the gas before and after the call.
    function probe(uint256 word) external view returns (uint256 before, uint256 floor, uint256 afterStart, bool must, bool bounded) {
        before = gasleft();
        MineFlipGas.Meter memory meter = MineFlipGas.start(word);
        afterStart = gasleft();
        return (before, meter.floor, afterStart, meter.mustProgress, meter.bounded);
    }

    /// @dev What a parent at `word` hands its child for `tail`.
    function childProbe(uint256 word, uint256 tail)
        external view returns (uint256 childWord, uint256 forwarded, uint256 remainingBefore, uint256 gasBefore)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(word);
        remainingBefore = MineFlipGas.remaining(meter);
        gasBefore = gasleft();
        childWord = MineFlipGas.child(meter, tail);
        forwarded = MineFlipGas.forwardable(meter, tail);
    }
}

/// @dev Production frame shape in one contract that delegatecalls itself: root = MinerModule
///      (first action mandatory, the next one estimate-admitted), mid = AdvanceModule
///      runDailyPhase on an x0 purchase day (child sized with the seal tail, then the seal),
///      leaf = a jackpot module group loop.
contract NestingStack {
    uint256 internal constant UNIT_SLACK = 30_000;
    uint256 internal constant LEAF_TAIL = 40_000;
    uint256 public constant WORKER_BOUNDARY = 50_000;
    uint256 public constant SEAL_DECL = 1_600_000;
    uint256 public constant SEAL_ACTUAL = 1_500_000;
    /// @dev Root tail declared above its actual burn by the bookkeeping stores below.
    uint256 public constant ROOT_TAIL_OVERHEAD = 150_000;

    NestingWorker public immutable worker;

    uint256 public leafUnits;
    uint256 public midAfterLeaf;
    uint256 public rootAfterFirst;
    uint256 public workerAllowance;
    bool public sealDone;
    bool public rootDone;
    bool public workerDispatched;
    bool public workerProgressed;

    constructor() { worker = new NestingWorker(); }

    struct Run {
        uint32 multiplier;
        uint256 unitGas;
        uint256 maxUnits;
        bool externalFirst;
        uint256 workerPrelude;
        uint256 rootTail;
    }

    function root(Run calldata c) external {
        uint32 m = MineFlipGas.normalize(c.multiplier);
        uint256 rootDecl = c.rootTail + ROOT_TAIL_OVERHEAD;
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.budget(gasleft(), m, true));

        // First action: always attempted with all gas.
        uint256 allowance = MineFlipGas.child(meter, WORKER_BOUNDARY + rootDecl);
        uint256 forwarded = MineFlipGas.forwardable(meter, rootDecl);
        bool ok;
        bytes memory data;
        if (c.externalFirst) {
            (ok, data) = address(worker).call{gas: forwarded}(
                abi.encodeCall(NestingWorker.run, (allowance, 0, c.unitGas, c.maxUnits)));
        } else {
            (ok, data) = address(this).delegatecall{gas: forwarded}(
                abi.encodeCall(this.mid, (allowance, c.unitGas, c.maxUnits)));
        }
        if (!ok) bubble(data);
        MineFlipGas.markProgress(meter);
        rootAfterFirst = gasleft();

        // Second action: admitted on the MinerModule estimate, sized by child().
        if (MineFlipGas.canRun(meter, WORKER_BOUNDARY, rootDecl)) {
            uint256 next = MineFlipGas.child(meter, WORKER_BOUNDARY + rootDecl);
            workerDispatched = true;
            workerAllowance = next & type(uint192).max;
            (ok, data) = address(worker).call{gas: MineFlipGas.forwardable(meter, rootDecl)}(
                abi.encodeCall(NestingWorker.run, (next, c.workerPrelude, c.unitGas, 1)));
            // As MinerModule after progress: an empty (out-of-gas) refusal keeps the prefix,
            // every semantic error (WorkGasBound included) unwinds the whole call.
            if (!ok) {
                if (data.length != 0) bubble(data);
            } else {
                workerProgressed = abi.decode(data, (MineFlipGas.Result)).progressed;
            }
        }
        burnGas(c.rootTail);
        rootDone = true;
    }

    function mid(uint256 allowance, uint256 unitGas, uint256 maxUnits) external {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        if (!MineFlipGas.canRun(meter, 100_000, SEAL_DECL)) return;
        (bool ok, bytes memory data) = address(this).delegatecall(
            abi.encodeCall(this.leaf, (MineFlipGas.child(meter, SEAL_DECL), unitGas, maxUnits)));
        if (!ok) bubble(data);
        midAfterLeaf = gasleft();
        burnGas(SEAL_ACTUAL);
        sealDone = true;
        MineFlipGas.finish(meter);
    }

    function leaf(uint256 allowance, uint256 unitGas, uint256 maxUnits) external {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint256 n;
        while (n < maxUnits && MineFlipGas.canRun(meter, unitGas + UNIT_SLACK, LEAF_TAIL)) {
            burnGas(unitGas);
            ++n;
            MineFlipGas.markProgress(meter);
        }
        leafUnits = n;
        MineFlipGas.finish(meter);
    }
}

/// @notice Nested meter semantics: the floor always holds every ancestor's tail, the first
///         unit may run below it, and only estimate-admitted work is held to it at finish.
contract MineFlipGasNestingTest is Test {
    uint256 private constant CAP = 16_700_000;
    NestingStack private s;
    NestingWorker private w;

    function setUp() public {
        s = new NestingStack();
        w = s.worker();
    }

    function _cfg(uint32 mult, uint256 unitGas, uint256 maxUnits, bool ext, uint256 prelude, uint256 rootTail)
        private pure returns (NestingStack.Run memory c)
    {
        c = NestingStack.Run(mult, unitGas, maxUnits, ext, prelude, rootTail);
    }

    function _try(NestingStack.Run memory c, uint256 g) private returns (bool ok, bytes memory err) {
        (ok, err) = address(s).call{gas: g}(abi.encodeCall(NestingStack.root, (c)));
    }

    struct Sweep {
        uint256 firstOk;
        uint256 prevUnits;
        uint256 maxUnits;
        uint256 multiUnitRuns;
    }

    /// @dev Calls the root at every gas in [lo, hi] by `step` (and `hi` itself) from one state.
    ///      Once a call succeeds every larger one must too; a success always completes the
    ///      parent's mandatory tail; a child past its first unit leaves the declared tail.
    function _sweep(NestingStack.Run memory c, uint256 lo, uint256 hi, uint256 step, Sweep memory r) private {
        for (uint256 g = lo; ; g += step) {
            if (g > hi) g = hi;
            uint256 snap = vm.snapshotState();
            (bool ok, bytes memory err) = _try(c, g);
            if (ok) {
                if (r.firstOk == 0) r.firstOk = g;
                assertTrue(s.rootDone(), "the root tail ran");
                uint256 units = c.externalFirst ? w.units() : s.leafUnits();
                assertGe(units, 1, "the first unit ran");
                if (!c.externalFirst) {
                    assertTrue(s.sealDone(), "the mid frame's seal ran");
                    if (units > 1) assertGe(s.midAfterLeaf(), s.SEAL_DECL(), "seal tail left whole");
                }
                if (units > 1) {
                    ++r.multiUnitRuns;
                    assertGe(s.rootAfterFirst(), c.rootTail, "root tail left whole");
                }
                assertGe(units, r.prevUnits, "more gas never runs fewer units");
                r.prevUnits = units;
                if (units > r.maxUnits) r.maxUnits = units;
            } else {
                assertTrue(err.length == 0 || bytes4(err) != MineFlipGas.WorkGasBound.selector, "never WorkGasBound");
                if (r.firstOk != 0) {
                    emit log_named_uint("reverted at gas", g);
                    emit log_named_uint("after first success at", r.firstOk);
                    fail();
                }
            }
            vm.revertToStateAndDelete(snap);
            if (g == hi) break;
        }
    }

    function _monotonic(NestingStack.Run memory c) private returns (Sweep memory r) {
        _sweep(c, 500_000, CAP, 100_000, r);
        // Near the cap at a finer step.
        r.prevUnits = 0;
        uint256 firstOk = r.firstOk;
        _sweep(c, CAP - 700_000, CAP, 7_000, r);
        r.firstOk = firstOk;
        assertGt(r.firstOk, 0, "some gas completes the first unit and the tails");
        emit log_named_uint("first success", r.firstOk);
        emit log_named_uint("most units in one call", r.maxUnits);
    }

    // ---------------------------------------------------------------------
    // A first-mode child cannot eat its ancestors' tails
    // ---------------------------------------------------------------------

    /// @dev Old L-2: a first-mode leaf got floor 0 and, after its first group, kept admitting
    ///      groups down to its own tail, so the 1.5M seal ran out of gas. Each leaf unit is 1M;
    ///      the seal (1.5M) exceeds the 1/64 call retention at every gas up to 16.7M.
    function test_FirstModeLeafLeavesSealTail_SweepMonotonic() public {
        Sweep memory r = _monotonic(_cfg(10_000, 1_000_000, 50, false, 20_000, 0));
        assertGt(r.maxUnits, 10, "non-vacuous: many units after the first");
        assertGt(r.multiUnitRuns, 50, "non-vacuous: most sweeps ran past the first unit");
        assertLt(r.firstOk, 3_200_000, "first unit plus the declared tails is enough gas");
    }

    function test_FirstModeLeafLeavesSealTail_CalibratedSweepMonotonic() public {
        Sweep memory r = _monotonic(_cfg(15_000, 1_000_000, 50, false, 20_000, 0));
        assertGt(r.maxUnits, 5, "non-vacuous: many units after the first");
    }

    /// @dev Calibration so large every estimate fails: one mandatory unit, the seal, no more.
    function test_ExtremeCalibrationRunsOneUnitThenTail() public {
        NestingStack.Run memory c = _cfg(type(uint32).max, 1_000_000, 50, false, 20_000, 0);
        for (uint256 g = 3_000_000; g <= CAP; g += 1_000_000) {
            uint256 snap = vm.snapshotState();
            (bool ok,) = _try(c, g);
            assertTrue(ok);
            assertEq(s.leafUnits(), 1);
            assertTrue(s.sealDone());
            assertFalse(s.workerDispatched(), "no estimate admits the next action");
            vm.revertToStateAndDelete(snap);
        }
    }

    /// @dev Same property across a CALL boundary: the first action is an external worker
    ///      running many units, and the root then owes a 1.5M mandatory tail.
    function test_FirstModeExternalWorkerLeavesRootTail_SweepMonotonic() public {
        Sweep memory r = _monotonic(_cfg(10_000, 1_000_000, 50, true, 20_000, 1_500_000));
        assertGt(r.maxUnits, 10, "non-vacuous: many units after the first");
    }

    // ---------------------------------------------------------------------
    // A refused worker never reverts
    // ---------------------------------------------------------------------

    /// @dev Old L-1: the root admits its next worker at WB+tail+2k but child() reserves
    ///      WB+tail+12k, so the worker can start with allowance 0, or below its own prelude.
    ///      It must return no progress, never WorkGasBound, keeping the committed first action.
    function test_SecondWorkerInAdmissionBandNeverReverts() public {
        NestingStack.Run memory c = _cfg(10_000, 200_000, 1, false, 20_000, 0);
        uint256 zero;
        uint256 tiny;
        uint256 progressed;
        uint256 firstOk;
        for (uint256 g = 1_500_000; g <= 2_800_000; g += 1_000) {
            uint256 snap = vm.snapshotState();
            (bool ok, bytes memory err) = _try(c, g);
            if (ok) {
                if (firstOk == 0) firstOk = g;
                assertTrue(s.sealDone() && s.rootDone());
                if (s.workerDispatched()) {
                    uint256 a = s.workerAllowance();
                    if (a == 0) ++zero;
                    else if (a < c.workerPrelude) ++tiny;
                    if (s.workerProgressed()) ++progressed;
                    else assertEq(w.units(), 0);
                }
            } else {
                assertTrue(err.length == 0 || bytes4(err) != MineFlipGas.WorkGasBound.selector, "never WorkGasBound");
                assertEq(firstOk, 0, "no revert once the first action fits");
            }
            vm.revertToStateAndDelete(snap);
        }
        emit log_named_uint("first success", firstOk);
        emit log_named_uint("dispatches with zero allowance", zero);
        emit log_named_uint("dispatches below the prelude", tiny);
        assertGt(firstOk, 0);
        assertGt(zero, 0, "non-vacuous: a worker started with allowance 0");
        assertGt(tiny, 0, "non-vacuous: a worker started below its prelude");
        assertGt(progressed, 0, "a larger call reaches the worker's unit");
    }

    function test_NonFirstWorkerWithZeroOrTinyAllowanceReturnsNoProgress() public {
        uint256[4] memory words = [
            MineFlipGas.budget(0, 10_000, false),
            MineFlipGas.budget(5_000, 10_000, false),
            MineFlipGas.budget(1_000_000, type(uint32).max, false),
            uint256(0) // legacy uncalibrated zero allowance
        ];
        for (uint256 i; i < words.length; ++i) {
            MineFlipGas.Result memory r = w.run{gas: 2_000_000}(words[i], 20_000, 100_000, 3);
            assertFalse(r.progressed);
            assertEq(w.units(), 0);
        }
        // The same zero allowance in first mode still runs exactly its one mandatory unit.
        MineFlipGas.Result memory first = w.run{gas: 2_000_000}(MineFlipGas.budget(0, 10_000, true), 20_000, 100_000, 3);
        assertTrue(first.progressed);
        assertEq(w.units(), 1);
    }

    // ---------------------------------------------------------------------
    // finish(): only estimate-admitted work is held to the floor
    // ---------------------------------------------------------------------

    function test_FirstUnitBelowFloorDoesNotTripFinish() public {
        // Allowance 100k, unit 500k: the mandatory unit runs 400k below the floor.
        MineFlipGas.Result memory r = w.run{gas: 2_000_000}(MineFlipGas.budget(100_000, 10_000, true), 0, 500_000, 3);
        assertTrue(r.progressed);
        assertEq(w.units(), 1, "first unit only; the next is not admitted below the floor");
        // A first unit that overspends its own declaration is not an estimate failure either.
        assertEq(w.runLying{gas: 6_000_000}(MineFlipGas.budget(2_000_000, 10_000, true), 100_000, 3_000_000, 0, 1), 1);
    }

    function test_EstimateAdmittedOverspendStillRevertsWorkGasBound() public {
        // Non-first unit admitted at 100k, actually burning 3M of a 2M allowance.
        vm.expectRevert(MineFlipGas.WorkGasBound.selector);
        w.runLying{gas: 6_000_000}(MineFlipGas.budget(2_000_000, 10_000, false), 100_000, 3_000_000, 0, 1);
        // Legacy uncalibrated allowance, same overspend.
        vm.expectRevert(MineFlipGas.WorkGasBound.selector);
        w.runLying{gas: 6_000_000}(2_000_000, 100_000, 3_000_000, 0, 1);
        // First unit honest, the second admitted on its estimate then overspending.
        vm.expectRevert(MineFlipGas.WorkGasBound.selector);
        w.runLying{gas: 6_000_000}(MineFlipGas.budget(2_000_000, 10_000, true), 100_000, 50_000, 3_000_000, 2);
        // Control: honest estimates finish cleanly.
        assertEq(w.runLying{gas: 6_000_000}(MineFlipGas.budget(2_000_000, 10_000, false), 100_000, 90_000, 90_000, 5), 5);
    }

    // ---------------------------------------------------------------------
    // start/child/forwardable arithmetic
    // ---------------------------------------------------------------------

    function test_FirstModeFloorHoldsTheAllowanceTail() public view {
        uint256 allowance = 1_000_000;
        (uint256 before, uint256 floor, uint256 afterStart, bool must, bool bounded) =
            w.probe{gas: 3_000_000}(MineFlipGas.budget(allowance, 10_000, true));
        assertTrue(must);
        assertFalse(bounded);
        assertLe(floor, before - allowance, "floor from the entry gas");
        assertGe(floor, afterStart - allowance);
        assertGt(floor, 1_000_000, "first mode no longer zeroes the floor");
        // An allowance at or above the frame's gas leaves no floor.
        (,floor,,,) = w.probe{gas: 3_000_000}(MineFlipGas.budget(5_000_000, 10_000, true));
        assertEq(floor, 0);
    }

    function test_ChildCarriesReserveAdjustedAllowanceAndForwardsAllInFirstMode() public view {
        uint256 tail = 500_000;
        (uint256 word, uint256 fwd, uint256 remainingBefore, uint256 gasBefore) =
            w.childProbe{gas: 5_000_000}(MineFlipGas.budget(4_000_000, 10_000, true), tail);
        assertTrue(word & (uint256(1) << 224) != 0, "first bit carried");
        uint256 allowance = word & type(uint192).max;
        assertLe(allowance, remainingBefore - tail - MineFlipGas.CALL_RESERVE, "tail and call reserve withheld");
        assertGe(allowance + 5_000, remainingBefore - tail - MineFlipGas.CALL_RESERVE);
        assertGt(fwd + 5_000, gasBefore - 5_000, "first mode forwards all gas");
        assertGt(fwd, allowance + tail, "the call itself is not capped at the allowance");

        (word, fwd,,) = w.childProbe{gas: 5_000_000}(MineFlipGas.budget(4_000_000, 10_000, false), tail);
        assertEq(word & (uint256(1) << 224), 0);
        assertLe(fwd, (word & type(uint192).max) + 1_000, "later units forward only the allowance");
    }
}
