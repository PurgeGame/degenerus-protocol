// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title MintFlipLifecycleCoverage -- the mineFlip afking lifecycle invariant: every subscriber is
///        STAMPED an afking box each day (the buy/stamp leg), then after the day's RNG/jackpot work
///        every stamped box is OPENED (the open leg), and `mineFlip()` signals `NoWork()` ONLY once
///        both legs are fully drained. No subscriber is ever permanently skipped by either cursor leg.
///
/// @notice The two cursor legs, each proven non-stranding here:
///   - STAMP/BUY leg (DegenerusGameAdvanceModule `_runSubscriberStage`, cursor `_subCursor`): an
///     UNCONDITIONAL per-day reset (`_afkingResetDay != day -> _subCursor = 0; subsFullyProcessed =
///     false`) then a weight-budgeted walk of the FULL `[0, len)` set until `subsFullyProcessed`. So
///     every in-set sub is stamped each day.
///   - OPEN leg (mineFlip's Afking stage, GameAfkingModule `runAfkingWork_g8553`, cursor `_subOpenCursor`):
///     a FULL-RING scan that visits up to `len` subs from the cursor, wrapping mid-scan, admitting
///     each box against the call's gas allowance and resuming mid-ring across calls. The stage is
///     complete only once the WHOLE set is drained, never just the suffix `[cursor, len)`. The
///     HumanBoxes stage (`runHumanBoxWork_g315`) follows it in the fixed engine order.
///   - `mineFlip()` reverts `NoWork()` ONLY when no stage has work — i.e. advance, afking, and
///     human boxes all fully drained.
///
/// @notice A box is openable iff the entry-gate is open (`!rngLockedFlag && !_livenessTriggered`) AND
///   a pending stamped box AND `_recordedDailyWord(stamp day) != 0`.
///
/// @dev N is chosen > OPEN_BATCH = 80 so the open leg MUST span multiple calls and the cursor resumes
///   mid-ring (the load-bearing condition for the open leg's resume property — proven explicitly in
///   `test_OpenLegSpansMultipleCalls`). Reuses the V56SecUnmanipulable / AutoOpenCursorRing afking
///   drive VERBATIM (deity-pass + funded-sub + new-day STAGE harness, the fulfill-first settle loop,
///   the accumulating-`t` warp, the post-PACK Sub-slot offset block, the packed-cursor slot reads).
///   The full day cycle is driven through the production engine (mineFlip only);
///   per-sub state is read from the packed subscriber lanes. Test-only: ZERO contracts/*.sol mutation.
contract MintFlipLifecycleCoverage is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the post-PACK Sub-slot offset block
    // (forge inspect DegenerusGame storage: _subOf@52, _subscribers@54, _subscriberIndex@55,
    //  cursors@56 — _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4;
    //  subsFullyProcessed bool @slot0 byte28.)
    // -------------------------------------------------------------------------
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS;      // packed 85-bit lanes (length @ slot)
    uint256 private constant CURSOR_SLOT = GameSlots.SUB_CURSOR;           // packed: _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4
    uint256 private constant SUBCURSOR_BYTE = 0;         // byte offset of _subCursor within CURSOR_SLOT
    uint256 private constant OPEN_CURSOR_BYTE = 2;       // byte offset of _subOpenCursor within CURSOR_SLOT
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED;        // mintPacked_ mapping root (deity bit @ 184)

    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT;

    uint256 private constant OPEN_BATCH = 80; // GameAfkingModule.OPEN_BATCH (per-call open cap)

    /// @dev subsFullyProcessed lives at slot 0, byte 28 (a bool packed with the level word).
    uint256 private constant SUBS_FULLY_PROCESSED_BYTE = 28;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)
    uint256 private _deliverNonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // 1 — stamp-then-open full coverage, NoWork only after both legs drained
    // =========================================================================

    /// @notice The headline invariant. With N > OPEN_BATCH subs, drive ONE full day cycle:
    ///   (a) after the stamp phase, EVERY sub carries a pending box of the active day (full STAMP coverage,
    ///       proving the buy-leg cursor walked the whole [0, len) set with no strand);
    ///   (b) drain the boxes across MULTIPLE mineFlip calls (the open leg spans calls and
    ///       resumes mid-ring because N > OPEN_BATCH);
    ///   (c) after draining, EVERY sub has no pending stamped box (full OPEN coverage,
    ///       proving the open-leg full-ring scan reached every sub with no strand);
    ///   (d) ONLY THEN does `mineFlip()` revert `NoWork()` — never while either leg had pending work.
    function test_AllSubsStampedThenAllBoxesOpenedBeforeNoWork() public {
        uint256 N = 100; // the open leg must span >= 2 calls at the keeper allowance
        address[] memory subs = _spawnSubs(N, "life_");

        // --- STAMP phase: the new day's subscriber preparation stamps every in-set sub before
        // the day's request; the stamps commit to that request's word. ---
        _stampToRequest(uint256(keccak256("life_stamp")) | 1);

        // (a) FULL STAMP COVERAGE: every sub was stamped this day. The buy-leg cursor reached the set
        // end (subsFullyProcessed) and walked the whole [0, len) set — no sub left unstamped.
        assertTrue(_subsFullyProcessed(), "stamp phase completed (subsFullyProcessed)");
        assertGt(_stampDay(), 0, "non-vacuity: the STAGE stamped a real process day");
        for (uint256 i; i < N; i++) {
            // The box resolves on the session word of the request that commits it, once the
            // stamp day seals (the per-day word readiness gate became the read-cohort order).
            assertTrue(_isPending(subs[i]), "post-stamp: every sub carries a pending box committed to the day's request");
        }

        // (b) DRAIN through the keeper across MULTIPLE calls: the day's processing runs in minimal
        // checkpoints (the call that releases the lock opens what its leftover admits), then
        // realistic-allowance keeper calls drain the AFKing backlog, resuming mid-ring.
        address keeper = makeAddr("life_keeper");
        _grantDeityPass(keeper); // bounty-eligible so the full creditFlip_g317 path runs end-to-end
        uint256 openCalls = _drainDay(subs, keeper, uint256(keccak256("life_stampc")) | 1, false);
        assertGt(openCalls, 1, "load-bearing: draining the set spanned MULTIPLE open calls (cursor resumed mid-ring)");

        // (c) FULL OPEN COVERAGE: every sub's box was opened — no stamp left pending.
        for (uint256 i; i < N; i++) {
            assertFalse(_isPending(subs[i]), "OPEN coverage: every stamped box was opened (marker advanced)");
            assertFalse(_isOpenable(subs[i]), "OPEN coverage: no openable box left behind for any sub");
        }

        // (d) NoWork ONLY after every read consumer and trailing cohort is drained.
        _settleIdle(uint256(keccak256("life_idle")));
        require(!game.advanceDue() && !game.rngLocked(), "fixture: still clean -> NoWork is the genuine drained signal");
        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mineFlip(0);
    }

    /// @notice Load-bearing isolation: prove a SINGLE bounded mineFlip call does NOT
    ///         drain all N>OPEN_BATCH boxes — so the multi-call resume in the headline test is genuinely
    ///         exercised, not vacuously satisfied by a one-shot drain.
    function test_OpenLegSpansMultipleCalls() public {
        uint256 N = 100;
        address[] memory subs = _spawnSubs(N, "span_");
        _stampToRequest(uint256(keccak256("span_stamp")) | 1);
        for (uint256 i; i < N; i++) {
            assertTrue(_isPending(subs[i]), "fixture: each sub carries a pending box");
        }
        _toAfkingStage(uint256(keccak256("span_stampc")) | 1);

        // One bounded engine call (a realistic 2M allowance) cannot clear the
        // AFKing backlog: each box is admitted only while the remaining allowance covers its
        // declared bound. (The per-call OPEN_BATCH count cap became this gas admission.)
        uint256 openableBefore = _countOpenable(subs);
        assertGt(openableBefore, 0, "fixture: an AFKing backlog is the next work");
        uint256 openedOne = _openViaValveWith(subs, BOUNDED_OPEN_ALLOWANCE);
        assertGt(openedOne, 0, "non-vacuity: the bounded call opened boxes");
        uint256 myRemaining = _countOpenable(subs);
        assertGt(myRemaining, 0, "load-bearing: a single bounded call left some of my subs UN-opened (multi-call required)");
        assertGe(openableBefore - myRemaining, 1, "non-vacuity: the first call opened at least one of my subs");

        // Drain the rest in a COUNTED loop; assert it took MORE than one further call shape — i.e. the
        // open leg resumes the cursor mid-ring across calls until every one of my subs is drained.
        uint256 furtherCalls;
        for (uint256 i; i < 64; i++) {
            if (_countOpenable(subs) == 0) break;
            _openViaValveWith(subs, BOUNDED_OPEN_ALLOWANCE);
            furtherCalls++;
        }
        assertGe(furtherCalls, 1, "load-bearing: at least one more open call was needed to finish my subs");
        for (uint256 i; i < N; i++) {
            assertFalse(_isOpenable(subs[i]), "multiple open calls drained every one of my subs (full-ring resume)");
        }
        // Total distinct open calls used (first + further) exceeded one — the multi-call span is real.
        assertGt(1 + furtherCalls, 1, "load-bearing: draining the backlog spanned multiple open calls");
        // After a full drain the engine finds no box work on the ring (whole set drained).
        _drainAllOpenable();
        assertEq(_countPending(subs), 0, "drained: no sub carries a pending box");
        uint8 next = game.nextMinerAction();
        assertTrue(next != 9 && next != 10, "drained: the engine selects no AFKing or human box work"); // Afking, HumanBoxes
    }

    // =========================================================================
    // 2 — NoWork NEVER fires while pending work exists (stamp-pending OR open-pending)
    // =========================================================================

    /// @notice Across the cycle, `mineFlip()` never signals NoWork while ANY leg has work:
    ///   - while a stamp box is landed-and-unopened, mineFlip's open category has work (no NoWork);
    ///   - the only clean NoWork is after BOTH legs are fully drained.
    ///   Probes mineFlip at intermediate points and asserts it does NOT revert NoWork while work remains.
    function test_NoWorkNeverWhilePendingExists() public {
        uint256 N = 100;
        address[] memory subs = _spawnSubs(N, "nw_");

        // Stamp the whole set: every sub now has open-pending work committed to the day's request.
        _stampToRequest(uint256(keccak256("nw_stamp")) | 1);

        address keeper = makeAddr("nw_keeper");
        _grantDeityPass(keeper);

        // Drive the day; BEFORE each engine call assert NoWork does NOT fire while pending boxes
        // still exist (the probe proves the engine reports work, or waits for its word).
        uint256 cranks = _drainDay(subs, keeper, uint256(keccak256("nw_stampc")) | 1, true);
        assertGt(cranks, 1, "open phase spanned multiple cranks");
        assertEq(_countOpenable(subs), 0, "open phase fully drained the afking set");

        // Only now does NoWork genuinely fire (advance + afking + human + CRAPS all empty).
        _settleIdle(uint256(keccak256("nw_idle")));
        require(!game.advanceDue() && !game.rngLocked(), "fixture: clean -> NoWork is genuine");
        _quietCrapsTable();
        assertTrue(_mintFlipWouldNoWork(keeper), "NoWork fires once afking AND human boxes are fully drained");
    }

    // =========================================================================
    // 3 — churn: subscribe mid-cycle / across a day boundary still fully covered
    // =========================================================================

    /// @notice The strand trigger: a `subscribe` GROWS the set while a cursor sits at the old length.
    ///   Subscribe extra subs mid-cycle and across a day boundary, then run another full day cycle and
    ///   assert the churned subs are stamped (next-day, per the buy-leg per-day reset that rewinds the
    ///   cursor to 0) AND their boxes opened (open-leg full-ring) — none permanently skipped.
    function test_ChurnSubscribeMidCycleStillFullyCovered() public {
        // Wave 1: an initial set, stamped + opened through one clean cycle so both cursors walk to the
        // set length and PARK there (the exact pre-condition the strand needs).
        uint256 N1 = 90; // > OPEN_BATCH
        address[] memory wave1 = _spawnSubs(N1, "churn1_");
        _runStageNewDay(uint256(keccak256("churn_w1stamp")) | 1);
        _settleClean(uint256(keccak256("churn_w1stampc")) | 1);
        _drainAllOpenable(); // both cursors now parked at/near the set length
        for (uint256 i; i < N1; i++) {
            assertFalse(_isOpenable(wave1[i]), "wave1 fully opened before the churn");
        }
        uint16 stampCursorParked = _subCursor();
        uint16 openCursorParked = _openCursor();

        // CHURN: grow the set with fresh subs while the cursors are parked at the old length — exactly
        // the "subscribe grows the set while a cursor sits at the old length" strand trigger.
        uint256 N2 = 40;
        address[] memory wave2 = _spawnSubs(N2, "churn2_");
        assertEq(_subscribersLength(), N1 + N2 + _baseSubCount(), "the churn grew _subscribers (push, no cursor reset)");
        // Document the wedge geometry: the parked cursors are now mid-array indices (< the grown len).
        emit log_named_uint("parked stamp cursor", stampCursorParked);
        emit log_named_uint("parked open cursor", openCursorParked);
        emit log_named_uint("grown set length", _subscribersLength());

        // Run ANOTHER full day cycle. The buy-leg per-day reset rewinds _subCursor to 0 and re-walks the
        // WHOLE grown set, so the churned subs (and wave1) are all stamped for the new day.
        vm.recordLogs();
        _runStageNewDay(uint256(keccak256("churn_w2stamp")) | 1);
        _settleClean(uint256(keccak256("churn_w2stampc")) | 1);
        assertTrue(_subsFullyProcessed(), "the new-day STAGE drained the whole grown set");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint24 day2 = uint24(_stampDay());
        for (uint256 i; i < N2; i++) {
            assertEq(_deliveries(logs, wave2[i], day2), 1, "churn: each churned sub stamped on the new day (buy-leg reset re-walked the set)");
        }
        for (uint256 i; i < N1; i++) {
            assertEq(_deliveries(logs, wave1[i], day2), 1, "churn: each wave1 sub re-stamped on the new day too");
        }

        // The open leg's full-ring scan drains every sub regardless of where _subOpenCursor parked —
        // the churned (post-parked-cursor) subs and the wave1 subs ([0, parked-cursor)) all open.
        _drainAllOpenable();
        for (uint256 i; i < N2; i++) {
            assertFalse(_isPending(wave2[i]), "churn: each churned sub's box opened (full-ring reached it)");
        }
        for (uint256 i; i < N1; i++) {
            assertFalse(_isPending(wave1[i]), "churn: each wave1 sub's box opened (no strand below the parked cursor)");
        }

        // Both legs drained -> mineFlip cleanly signals NoWork (no churned sub permanently skipped).
        address keeper = makeAddr("churn_keeper");
        _grantDeityPass(keeper);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: clean");
        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mineFlip(0);
    }

    // =========================================================================
    // 4 — multi-day: every sub stamped AND opened EVERY day (per-day reset + full-ring hold)
    // =========================================================================

    /// @notice Run 3 consecutive day cycles with a fixed set; assert every sub is STAMPED on each day
    ///   (the buy-leg per-day reset re-walks the full set) AND OPENED on each day (the open-leg full-ring
    ///   scan drains the set), with strictly increasing per-day stamp/open markers — the invariant holds
    ///   across days, no sub permanently skipped on any day.
    function test_MultiDayEverySubEveryDay() public {
        uint256 N = 90; // > OPEN_BATCH so each day's open phase spans calls
        address[] memory subs = _spawnSubs(N, "multi_");

        uint32 prevDay;
        for (uint256 dayIdx; dayIdx < 3; dayIdx++) {
            // STAMP the whole set for this day.
            _stampToRequest(uint256(keccak256(abi.encode("multi_stamp", dayIdx))) | 1);
            assertTrue(_subsFullyProcessed(), "each day: the STAGE drained the whole set");

            uint32 dayMark = _stampDay();
            assertGt(dayMark, prevDay, "each day advances the stamp marker (a genuinely new day)");
            for (uint256 i; i < N; i++) {
                assertTrue(_isPending(subs[i]), "multi-day: every sub has a pending box this day");
            }

            // OPEN the whole set for this day (spans multiple calls at the keeper allowance).
            _drainDay(subs, makeAddr("multi_keeper"), uint256(keccak256(abi.encode("multi_stampc", dayIdx))) | 1, false);
            for (uint256 i; i < N; i++) {
                assertFalse(_isPending(subs[i]), "multi-day OPEN: every sub's box opened this day");
            }
            prevDay = dayMark;
        }
    }

    // =========================================================================
    // Box-drive helpers
    // =========================================================================

    /// @dev Spawn `n` seated, funded, lootbox-mode subscribers. They join `_subscribers`; the
    ///      first new-day STAGE buy stamps a box on each. Funding is generous so the daily
    ///      buys never underflow the pool (no funding-kill mid-test).
    function _spawnSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address p = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            _grantSeat(p);           // the AFKing Subscription Token is the sole subscribe credential
            _fundPool(p, 200 ether); // generous: covers every daily buy across the test
            _subscribeLootbox(p, 1);
            (, uint256 position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(p));
            require(position1 > 0, "fixture: the sub joined the set");
            subs[i] = p;
        }
    }

    /// @dev A realistic keeper allowance for the open leg: each AFKing box is admitted only while
    ///      the remaining allowance covers its declared bound, so a backlog spans calls.
    uint256 private constant BOUNDED_OPEN_ALLOWANCE = 2_000_000;

    function _isPending(address who) internal view returns (bool) {
        return GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf_g3120(who));
    }

    /// @dev The day the current cohort's boxes are stamped for.
    function _stampDay() internal view returns (uint32) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_RESET_DAY))) >> (8 * GameSlots.AFKING_RESET_DAY_OFFSET));
    }

    /// @dev AfkingDelivered events for `who` on `day` among `logs`.
    function _deliveries(Vm.Log[] memory logs, address who, uint24 day) internal view returns (uint256 c) {
        bytes32 sig = keccak256("AfkingDelivered(uint32,uint256)");
        uint32 id = game.walletIdOf_g3120(who);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length != 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            if (uint24(abi.decode(logs[i].data, (uint256)) >> 128) == day) ++c;
        }
    }

    function _countPending(address[] memory subs) internal view returns (uint256 c) {
        for (uint256 i; i < subs.length; i++) if (_isPending(subs[i])) c++;
    }

    /// @dev Settle the current day, move to the next, and step the engine in single-unit checkpoints
    ///      through the subscriber preparation until the day's request is the next work.
    function _stampToRequest(uint256 vrfWord) internal {
        _settleIdle(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        for (uint256 i; i < 600; i++) {
            if (game.nextMinerAction() == 16) return; // MinerAction.RequestDaily
            _stepSingleUnit();
        }
        revert("harness: the daily request never became the next work");
    }

    /// @dev Step the day's request and processing in single-unit checkpoints until its AFKing backlog
    ///      is the next work (the call that releases the lock opens what its leftover admits).
    function _toAfkingStage(uint256 vrfWord) internal {
        for (uint256 i; i < 600; i++) {
            if (game.nextMinerAction() == 8) return; // MinerAction.Afking
            _fulfillPending(vrfWord);
            if (game.advanceDue()) _stepSingleUnit();
        }
        revert("harness: the AFKing stage never became the next work");
    }

    /// @dev Drive the stamped day to completion: single-unit checkpoints up to the AFKing stage, then
    ///      `keeper` mineFlip calls at BOUNDED_OPEN_ALLOWANCE until every sub's box is open. Returns
    ///      the number of engine calls that opened at least one of `subs`. With `probe`, asserts
    ///      before every call that NoWork does not fire while any of `subs` is pending.
    function _drainDay(address[] memory subs, address keeper, uint256 vrfWord, bool probe)
        internal
        returns (uint256 openCalls)
    {
        for (uint256 i; i < 600 && game.nextMinerAction() != 8 && _countPending(subs) != 0; i++) {
            if (probe) assertFalse(_mintFlipWouldNoWork(keeper), "NoWork must NOT fire while open-pending boxes exist");
            _fulfillPending(vrfWord);
            if (!game.advanceDue()) continue;
            uint256 before = _countPending(subs);
            _stepSingleUnit();
            if (_countPending(subs) < before) openCalls++;
        }
        for (uint256 i; i < 200 && _countPending(subs) != 0; i++) {
            if (probe) assertFalse(_mintFlipWouldNoWork(keeper), "NoWork must NOT fire while open-pending boxes exist");
            _fulfillPending(vrfWord);
            if (!game.advanceDue()) continue;
            uint256 before = _countPending(subs);
            vm.prank(keeper);
            game.mineFlip{gas: BOUNDED_OPEN_ALLOWANCE}(0); // MUST NOT revert while boxes remain
            if (_countPending(subs) < before) openCalls++;
        }
        assertEq(_countPending(subs), 0, "harness: the day's stamped boxes all opened");
    }

    /// @dev Answer outstanding requests and finish delivered cohorts until the engine is idle.
    function _settleIdle(uint256 vrfWord) internal {
        for (uint256 i; i < 40; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool done) = mockVRF.pendingRequests(reqId);
                if (!done) mockVRF.fulfillRandomWords(reqId, vrfWord + i + 2);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) return;
            if (game.advanceDue()) game.mineFlip(0);
        }
        revert("harness: cohorts never settled");
    }

    /// @dev Maximum calibration admits the mandatory first unit and no optional
    ///      aggregation, preserving each checkpoint without a success-only gas search.
    function _stepSingleUnit() internal {
        game.mineFlip{gas: 30_000_000}(type(uint32).max);
    }

    /// @dev One engine call with a bounded gas allowance; returns how many of `subs` it opened.
    function _openViaValveWith(address[] memory subs, uint256 allowance) internal returns (uint256 opened) {
        uint256 before = _countPending(subs);
        vm.prank(makeAddr("life_opener"));
        game.mineFlip{gas: allowance}(0);
        opened = before - _countPending(subs);
    }

    /// @dev Count how many of `subs` currently carry an openable box.
    function _countOpenable(address[] memory subs) internal view returns (uint256 c) {
        for (uint256 i; i < subs.length; i++) if (_isOpenable(subs[i])) c++;
    }

    /// @dev Mine until the engine reports no work, so every stamped box has been opened in order.
    function _drainAllOpenable() internal {
        vm.startPrank(makeAddr("life_opener"));
        uint256 calls = _mineAll(256);
        vm.stopPrank();
        require(calls < 256, "drain did not converge");
    }

    /// @dev Would `keeper`'s mineFlip be the clean NoWork no-op RIGHT NOW? Probes via a try/catch that
    ///      reverts state on a successful call (so the probe never advances the drain). A NoWork revert
    ///      => true; any other outcome (work done, or any other revert) => false.
    function _mintFlipWouldNoWork(address keeper) internal returns (bool) {
        uint256 snap = vm.snapshotState();
        bool noWork;
        vm.prank(keeper);
        try game.mineFlip(0) {
            noWork = false; // a category had work -> not NoWork
        } catch (bytes memory reason) {
            noWork = (reason.length == 4 && bytes4(reason) == bytes4(keccak256("NoWork()")));
        }
        vm.revertToStateAndDelete(snap); // discard any state the probe mutated
        return noWork;
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (the accumulating-timestamp warp).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat_who = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, q, seat_who); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_idOf(who));
    }

    /// @dev `who`'s wallet ID, registering one through the production hook when it has none.
    function _idOf(address who) internal returns (uint32 id) {
        id = game.walletIdOf_g3120(who);
        if (id == 0) id = _giveWalletId(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf_g3120(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    // =========================================================================
    // Storage reads — subscriber set, cursors, the per-sub markers
    // =========================================================================

    /// @dev `_subscribers.length` (the dynamic-array length lives directly in its slot).
    function _subscribersLength() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev The number of subs the fixture self-subscribes at deploy (VAULT + SDGNRS via SUB-09), so
    ///      churn-count assertions account for the baseline non-test occupants.
    function _baseSubCount() internal pure returns (uint256) {
        return 2; // VAULT + sDGNRS self-subscribe in DeployProtocol
    }

    /// @dev Read the current `_subCursor` (byte 0..1 of the packed CURSOR_SLOT).
    function _subCursor() internal view returns (uint16) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT))));
        return uint16(packed >> (SUBCURSOR_BYTE * 8));
    }

    /// @dev Read the current `_subOpenCursor` (byte 2..3 of the packed CURSOR_SLOT).
    function _openCursor() internal view returns (uint16) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT))));
        return uint16(packed >> (OPEN_CURSOR_BYTE * 8));
    }

    /// @dev `subsFullyProcessed` (slot 0, byte 28 — a bool packed with the level word).
    function _subsFullyProcessed() internal view returns (bool) {
        uint256 p0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(p0 >> (SUBS_FULLY_PROCESSED_BYTE * 8)) != 0;
    }

    /// @dev Openable under the entry-gate: an unopened box of the current cohort and the cohort's
    ///      stamp-day word has landed.
    function _isOpenable(address who) internal view returns (bool) {
        if (!_isPending(who)) return false;
        return game.rngWordForDay(uint24(_stampDay())) != 0;
    }
}
