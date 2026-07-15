// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title MintFlipLifecycleCoverage -- the mintFlip afking lifecycle invariant: every subscriber is
///        STAMPED an afking box each day (the buy/stamp leg), then after the day's RNG/jackpot work
///        every stamped box is OPENED (the open leg), and `mintFlip()` signals `NoWork()` ONLY once
///        both legs are fully drained. No subscriber is ever permanently skipped by either cursor leg.
///
/// @notice The two cursor legs, each proven non-stranding here:
///   - STAMP/BUY leg (DegenerusGameAdvanceModule `_runSubscriberStage`, cursor `_subCursor`): an
///     UNCONDITIONAL per-day reset (`_afkingResetDay != day -> _subCursor = 0; subsFullyProcessed =
///     false`) then a weight-budgeted walk of the FULL `[0, len)` set until `subsFullyProcessed`. So
///     every in-set sub is stamped each day — `lastAutoBoughtDay == activeDay`.
///   - OPEN leg (GameAfkingModule `_autoOpen`, cursor `_subOpenCursor`): a FULL-RING scan that visits
///     up to `len` subs from the cursor, wrapping mid-scan, opening up to OPEN_BATCH (80) boxes per
///     call and resuming mid-ring across calls. A 0-open result means the WHOLE set is drained, never
///     just the suffix `[cursor, len)`. The open category then drains HUMAN boxes with the leftover
///     budget (the `openHumanBoxes` multi-index sweep) — the same afking-then-human order as `openBoxes`.
///   - `mintFlip()` reverts `NoWork()` ONLY when the advance category has no work AND `_autoOpen`
///     returns 0 AND the human-box sweep (`openHumanBoxes`) returns 0 — i.e. advance, afking, and
///     human boxes all fully drained.
///
/// @notice A box is openable iff the entry-gate is open (`!rngLockedFlag && !_livenessTriggered`) AND
///   `sub.lastOpenedDay < sub.lastAutoBoughtDay` AND `rngWordByDay[sub.lastAutoBoughtDay] != 0`.
///
/// @dev N is chosen > OPEN_BATCH = 80 so the open leg MUST span multiple calls and the cursor resumes
///   mid-ring (the load-bearing condition for the open leg's resume property — proven explicitly in
///   `test_OpenLegSpansMultipleCalls`). Reuses the V56SecUnmanipulable / AutoOpenCursorRing afking
///   drive VERBATIM (deity-pass + funded-sub + new-day STAGE harness, the fulfill-first settle loop,
///   the accumulating-`t` warp, the post-PACK Sub-slot offset block, the packed-cursor slot reads).
///   The full day cycle is driven through the production valves (advanceGame / openBoxes / mintFlip);
///   per-sub markers are read from `_subOf[player]`. Test-only: ZERO contracts/*.sol mutation.
contract MintFlipLifecycleCoverage is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the post-PACK Sub-slot offset block
    // (forge inspect DegenerusGame storage: _subOf@54, _subscribers@56, _subscriberIndex@57,
    //  cursors@58 — _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4;
    //  subsFullyProcessed bool @slot0 byte28.)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 53;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 55;      // address[] _subscribers (length @ slot; elements @ keccak256(slot)+i)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 56; // mapping(address => uint256) _subscriberIndex (1-indexed)
    uint256 private constant CURSOR_SLOT = 57;           // packed: _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4
    uint256 private constant SUBCURSOR_BYTE = 0;         // byte offset of _subCursor within CURSOR_SLOT
    uint256 private constant OPEN_CURSOR_BYTE = 2;       // byte offset of _subOpenCursor within CURSOR_SLOT
    uint256 private constant MINTPACKED_SLOT = 9;        // mintPacked_ mapping root (deity bit @ 184)

    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingFlip u24 @27 · subStreakLatch u16 @30
    uint256 private constant OFF_LASTBOUGHT = 10;     // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13;     // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184;

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
    }

    // =========================================================================
    // 1 — stamp-then-open full coverage, NoWork only after both legs drained
    // =========================================================================

    /// @notice The headline invariant. With N > OPEN_BATCH subs, drive ONE full day cycle:
    ///   (a) after the stamp phase, EVERY sub has `lastAutoBoughtDay == activeDay` (full STAMP coverage,
    ///       proving the buy-leg cursor walked the whole [0, len) set with no strand);
    ///   (b) drain the boxes across MULTIPLE mintFlip/openBoxes calls (the open leg spans calls and
    ///       resumes mid-ring because N > OPEN_BATCH);
    ///   (c) after draining, EVERY sub has `lastOpenedDay == lastAutoBoughtDay` (full OPEN coverage,
    ///       proving the open-leg full-ring scan reached every sub with no strand);
    ///   (d) ONLY THEN does `mintFlip()` revert `NoWork()` — never while either leg had pending work.
    function test_AllSubsStampedThenAllBoxesOpenedBeforeNoWork() public {
        uint256 N = 100; // > OPEN_BATCH (80): the open leg MUST span >= 2 calls
        address[] memory subs = _spawnSubs(N, "life_");

        // --- STAMP phase: one full day cycle stamps every in-set sub + lands the day's word. The STAGE
        // runs inside advanceGame across weight-budgeted advance calls until subsFullyProcessed. ---
        _runStageNewDay(uint256(keccak256("life_stamp")) | 1);
        _settleClean(uint256(keccak256("life_stampc")) | 1);

        // (a) FULL STAMP COVERAGE: every sub was stamped this day. The buy-leg cursor reached the set
        // end (subsFullyProcessed) and walked the whole [0, len) set — no sub left unstamped.
        assertTrue(_subsFullyProcessed(), "stamp phase completed (subsFullyProcessed)");
        uint32 activeDay = _lastBoughtDayOf(subs[0]);
        assertGt(activeDay, 0, "non-vacuity: the STAGE stamped a real process day");
        for (uint256 i; i < N; i++) {
            assertEq(_lastBoughtDayOf(subs[i]), activeDay, "STAMP coverage: every sub stamped for the active day");
            assertTrue(_isOpenable(subs[i]), "post-stamp: every sub carries a sealed openable box (word landed)");
        }

        // (b) DRAIN via the mintFlip keeper across MULTIPLE calls. Each mintFlip open category opens up
        // to OPEN_BATCH (80) boxes; with N=100 a single call cannot drain the set, so the cursor must
        // resume mid-ring across calls. Count the distinct open calls that did real work.
        address keeper = makeAddr("life_keeper");
        _grantDeityPass(keeper); // bounty-eligible so the full creditFlip path runs end-to-end
        require(!game.advanceDue() && !game.rngLocked(), "fixture: settled clean so mintFlip runs the OPEN leg");

        uint256 openCalls;
        for (uint256 i; i < 64; i++) {
            uint256 before = _countOpenable(subs);
            if (before == 0) break;
            vm.prank(keeper);
            game.mintFlip(); // open category: MUST NOT revert while boxes remain
            uint256 afterCnt = _countOpenable(subs);
            if (afterCnt < before) openCalls++;
            // Per-call bound: a single mintFlip open category never opens more than OPEN_BATCH boxes.
            assertLe(before - afterCnt, OPEN_BATCH, "per-call opens bounded by OPEN_BATCH");
        }
        assertGt(openCalls, 1, "load-bearing: draining N>OPEN_BATCH spanned MULTIPLE open calls (cursor resumed mid-ring)");

        // (c) FULL OPEN COVERAGE: every sub's box was opened — lastOpenedDay caught lastAutoBoughtDay.
        for (uint256 i; i < N; i++) {
            assertEq(_lastOpenedDayOf(subs[i]), _lastBoughtDayOf(subs[i]), "OPEN coverage: every stamped box was opened (marker advanced)");
            assertFalse(_isOpenable(subs[i]), "OPEN coverage: no openable box left behind for any sub");
        }

        // (d) NoWork ONLY after BOTH box types are drained. The afking ring is fully open (c); mintFlip's
        // open leg now ALSO drains HUMAN boxes after the afking ones (the subs' cover-buy / daily-buy
        // lootboxes), so the afking-keyed loop above can leave a human-box backlog the open leg would
        // still service. Clear it via the openBoxes valve (the same afking-then-human drain) so every
        // router category is genuinely empty -> the clean no-work signal (not a suffix-strand false positive).
        _drainAllOpenable();
        require(!game.advanceDue() && !game.rngLocked(), "fixture: still clean -> NoWork is the genuine drained signal");
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
    }

    /// @notice Load-bearing isolation: prove a SINGLE bounded open call (openBoxes(OPEN_BATCH)) does NOT
    ///         drain all N>OPEN_BATCH boxes — so the multi-call resume in the headline test is genuinely
    ///         exercised, not vacuously satisfied by a one-shot drain.
    function test_OpenLegSpansMultipleCalls() public {
        uint256 N = 100; // > OPEN_BATCH
        address[] memory subs = _spawnSubs(N, "span_");
        _runStageNewDay(uint256(keccak256("span_stamp")) | 1);
        _settleClean(uint256(keccak256("span_stampc")) | 1);
        for (uint256 i; i < N; i++) {
            assertTrue(_isOpenable(subs[i]), "fixture: each sub carries a sealed openable box");
        }

        // A single OPEN_BATCH-bounded open opens at most OPEN_BATCH (80) boxes ring-wide. With N=100 of
        // MY subs openable (plus the baseline self-subs), one call CANNOT clear all of my subs — so the
        // drain is genuinely multi-call, not a one-shot. (The valve drains the whole ring, so the exact
        // count opened ring-wide includes baseline boxes; the load-bearing fact is MY subs persist.)
        uint256 openableBefore = _countOpenable(subs); // == N
        assertEq(openableBefore, N, "fixture: all N of my subs are openable");
        uint256 openedOne = _openViaValve(OPEN_BATCH);
        // Weighted walk budget: baseline (non-fixture) subs in the ring cost 1 skip-unit each,
        // so a saturated call opens OPEN_BATCH minus the few units those skips consumed.
        assertLe(openedOne, OPEN_BATCH, "one bounded call never exceeds OPEN_BATCH opens");
        assertGe(openedOne, OPEN_BATCH - 4, "one bounded call opens ~OPEN_BATCH boxes ring-wide (saturated, minus skip units)");
        uint256 myRemaining = _countOpenable(subs);
        assertGt(myRemaining, 0, "load-bearing: a single OPEN_BATCH call left some of my subs UN-opened (multi-call required)");
        assertGe(openableBefore - myRemaining, 1, "non-vacuity: the first call opened at least one of my subs");

        // Drain the rest in a COUNTED loop; assert it took MORE than one further call shape — i.e. the
        // open leg resumes the cursor mid-ring across calls until every one of my subs is drained.
        uint256 furtherCalls;
        for (uint256 i; i < 64; i++) {
            if (_countOpenable(subs) == 0) break;
            _openViaValve(OPEN_BATCH);
            furtherCalls++;
        }
        assertGe(furtherCalls, 1, "load-bearing: at least one more open call was needed to finish my subs");
        for (uint256 i; i < N; i++) {
            assertFalse(_isOpenable(subs[i]), "multiple open calls drained every one of my subs (full-ring resume)");
        }
        // Total distinct open calls used (first + further) exceeded one — the multi-call span is real.
        assertGt(1 + furtherCalls, 1, "load-bearing: draining N>OPEN_BATCH spanned multiple open calls");
        // A follow-up open on the drained ring returns 0 (whole-set-drained signal).
        _drainAllOpenable();
        assertEq(_openViaValve(OPEN_BATCH), 0, "drained: a follow-up open returns 0 (whole set drained)");
    }

    // =========================================================================
    // 2 — NoWork NEVER fires while pending work exists (stamp-pending OR open-pending)
    // =========================================================================

    /// @notice Across the cycle, `mintFlip()` never signals NoWork while ANY leg has work:
    ///   - while a stamp box is landed-and-unopened, mintFlip's open category has work (no NoWork);
    ///   - the only clean NoWork is after BOTH legs are fully drained.
    ///   Probes mintFlip at intermediate points and asserts it does NOT revert NoWork while work remains.
    function test_NoWorkNeverWhilePendingExists() public {
        uint256 N = 100; // > OPEN_BATCH so the open phase spans calls
        address[] memory subs = _spawnSubs(N, "nw_");

        // Stamp the whole set + land the day's word: every sub now has open-pending work.
        _runStageNewDay(uint256(keccak256("nw_stamp")) | 1);
        _settleClean(uint256(keccak256("nw_stampc")) | 1);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: settled clean (open leg is the live category)");

        address keeper = makeAddr("nw_keeper");
        _grantDeityPass(keeper);

        // Crank the open category one bounded batch at a time; BEFORE each crank assert NoWork does NOT
        // fire while open-pending boxes still exist (the probe proves the open leg reports work).
        uint256 cranks;
        for (uint256 i; i < 64; i++) {
            uint256 pending = _countOpenable(subs);
            if (pending == 0) break;
            // PROBE: with pending boxes, a static mintFlip MUST NOT be the NoWork no-op.
            assertFalse(_mintFlipWouldNoWork(keeper), "NoWork must NOT fire while open-pending boxes exist");
            // Real crank to advance the drain.
            vm.prank(keeper);
            game.mintFlip();
            cranks++;
        }
        assertGt(cranks, 1, "open phase spanned multiple cranks (N>OPEN_BATCH)");
        assertEq(_countOpenable(subs), 0, "open phase fully drained the afking set");

        // mintFlip's open leg now also drains HUMAN boxes after the afking ones (the subs' cover-buy /
        // daily-buy lootboxes); the afking-keyed crank loop can leave a human-box backlog. Clear it so
        // the final probe sees every category empty.
        _drainAllOpenable();

        // Only now does NoWork genuinely fire (advance + afking + human all empty).
        require(!game.advanceDue() && !game.rngLocked(), "fixture: clean -> NoWork is genuine");
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
        _runStageNewDay(uint256(keccak256("churn_w2stamp")) | 1);
        _settleClean(uint256(keccak256("churn_w2stampc")) | 1);
        assertTrue(_subsFullyProcessed(), "the new-day STAGE drained the whole grown set");
        uint32 day2 = _lastBoughtDayOf(wave2[0]);
        for (uint256 i; i < N2; i++) {
            assertEq(_lastBoughtDayOf(wave2[i]), day2, "churn: each churned sub stamped on the new day (buy-leg reset re-walked the set)");
        }
        for (uint256 i; i < N1; i++) {
            assertEq(_lastBoughtDayOf(wave1[i]), day2, "churn: each wave1 sub re-stamped on the new day too");
        }

        // The open leg's full-ring scan drains every sub regardless of where _subOpenCursor parked —
        // the churned (post-parked-cursor) subs and the wave1 subs ([0, parked-cursor)) all open.
        _drainAllOpenable();
        for (uint256 i; i < N2; i++) {
            assertEq(_lastOpenedDayOf(wave2[i]), _lastBoughtDayOf(wave2[i]), "churn: each churned sub's box opened (full-ring reached it)");
        }
        for (uint256 i; i < N1; i++) {
            assertEq(_lastOpenedDayOf(wave1[i]), _lastBoughtDayOf(wave1[i]), "churn: each wave1 sub's box opened (no strand below the parked cursor)");
        }

        // Both legs drained -> mintFlip cleanly signals NoWork (no churned sub permanently skipped).
        address keeper = makeAddr("churn_keeper");
        _grantDeityPass(keeper);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: clean");
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
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
            _runStageNewDay(uint256(keccak256(abi.encode("multi_stamp", dayIdx))) | 1);
            _settleClean(uint256(keccak256(abi.encode("multi_stampc", dayIdx))) | 1);
            assertTrue(_subsFullyProcessed(), "each day: the STAGE drained the whole set");

            uint32 dayMark = _lastBoughtDayOf(subs[0]);
            assertGt(dayMark, prevDay, "each day advances the stamp marker (a genuinely new day)");
            for (uint256 i; i < N; i++) {
                assertEq(_lastBoughtDayOf(subs[i]), dayMark, "multi-day STAMP: every sub stamped this day");
                assertTrue(_isOpenable(subs[i]), "multi-day: every sub has an openable box this day");
            }

            // OPEN the whole set for this day (spans multiple calls; N>OPEN_BATCH).
            _drainAllOpenable();
            for (uint256 i; i < N; i++) {
                assertEq(_lastOpenedDayOf(subs[i]), dayMark, "multi-day OPEN: every sub's box opened this day");
            }
            prevDay = dayMark;
        }
    }

    // =========================================================================
    // Box-drive helpers
    // =========================================================================

    /// @dev Spawn `n` deity-passed, funded, lootbox-mode subscribers. They join `_subscribers`; the
    ///      first new-day STAGE buy stamps a box on each. Funding is generous so the cover-buy + daily
    ///      buys never underflow the pool (no funding-kill mid-test).
    function _spawnSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address p = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            _grantDeityPass(p);      // clears the pass gate (deity = sentinel horizon)
            _fundPool(p, 200 ether); // generous: grounds the cover-buy + every daily buy across the test
            _subscribeLootbox(p, 1);
            require(_subscriberIndexOf(p) > 0, "fixture: the sub joined the set");
            subs[i] = p;
        }
    }

    /// @dev Count how many of `subs` currently carry an openable box.
    function _countOpenable(address[] memory subs) internal view returns (uint256 c) {
        for (uint256 i; i < subs.length; i++) if (_isOpenable(subs[i])) c++;
    }

    /// @dev Drive the production open valve once: Game.openBoxes -> drainAfkingBoxes -> _autoOpen.
    function _openViaValve(uint256 maxCount) internal returns (uint256 opened) {
        vm.prank(makeAddr("life_opener"));
        opened = game.openBoxes(maxCount);
    }

    /// @dev Drain the open valve to empty (a 0-open call means the whole afking ring is drained).
    function _drainAllOpenable() internal {
        for (uint256 i; i < 256; i++) {
            if (_openViaValve(OPEN_BATCH) == 0) return;
        }
        revert("drain did not converge");
    }

    /// @dev Would `keeper`'s mintFlip be the clean NoWork no-op RIGHT NOW? Probes via a try/catch that
    ///      reverts state on a successful call (so the probe never advances the drain). A NoWork revert
    ///      => true; any other outcome (work done, or any other revert) => false.
    function _mintFlipWouldNoWork(address keeper) internal returns (bool) {
        uint256 snap = vm.snapshotState();
        bool noWork;
        vm.prank(keeper);
        try game.mintFlip() {
            noWork = false; // a category had work -> not NoWork
        } catch (bytes memory reason) {
            noWork = (reason.length == 4 && bytes4(reason) == bytes4(keccak256("NoWork()")));
        }
        vm.revertToState(snap); // discard any state the probe mutated
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
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
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
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
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

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    /// @dev Openable under the entry-gate: pending box (lastOpenedDay < lastAutoBoughtDay) AND the frozen
    ///      stamp-day word has landed (rngWordByDay[lastAutoBoughtDay] != 0). Mirrors the _autoOpen predicate.
    function _isOpenable(address who) internal view returns (bool) {
        uint32 bought = _lastBoughtDayOf(who);
        if (_lastOpenedDayOf(who) >= bought) return false;
        return game.rngWordForDay(uint24(bought)) != 0;
    }
}
