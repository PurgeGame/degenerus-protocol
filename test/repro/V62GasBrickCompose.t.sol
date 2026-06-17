// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title V62GasBrickCompose -- regression guard for the V62-02 fix.
///
/// @notice V62-02 (adjudicated vs frozen c4d48008): the new-day advanceGame path ran the afking
///         subscriber STAGE then, when the cursor reached the set end in ONE chunk
///         (subsFullyProcessed == true), FELL THROUGH to rngGate -> _backfillGapDays with no
///         intervening stage-break. The v60 decouple (AdvanceModule STAGE_GAP_BACKFILLED) breaks
///         AFTER rngGate -- it decouples the gap backfill from the DOWNSTREAM daily jackpot, not
///         from the UPSTREAM subscriber stage. So a single advanceGame() could run BOTH a saturated
///         all-evict subscriber chunk (~9.7M cold, measured in V56AfkingGasMarginal::testResidualR1)
///         AND the 120-day gap backfill (~7M) in one tx -- summing past EIP-7825's 16,777,216 per-tx
///         cap, permanently bricking advanceGame during stall recovery.
///
///         THE FIX (AdvanceModule, STAGE_SUBS_BACKFILL_DEFERRED): when the subscriber set drains to
///         its end in a chunk AND a multi-day VRF-stall gap backfill is pending, advanceGame breaks
///         BEFORE rngGate -- the upstream mirror of the STAGE_GAP_BACKFILLED decouple. The heavy
///         completing subscriber chunk runs alone in one tx; the backfill (then the jackpot) run in
///         their own subsequent txs, each under the per-tx ceiling. dailyIdx is unadvanced and
///         rngWordByDay[day] stays unset, so advanceDue() remains true and the next advance proceeds.
///
///         The control-flow gate this guards (AdvanceModule subscriber stage):
///           1. `_runSubscriberStage(day)` runs (weight-budgeted, SUB_STAGE_WEIGHT_BUDGET = 500).
///           2. If `_subCursor < _subscribers.length` after the stage -> BREAK STAGE_SUBS_WORKING
///              (partial drain; rngGate / backfill do NOT run this tx).
///           3. When the cursor reaches the (shrinking) set end -> `subsFullyProcessed = true`; if a
///              gap backfill is pending -> BREAK STAGE_SUBS_BACKFILL_DEFERRED (segregated); else fall
///              through to rngGate as normal.
///         The all-evict branch (GameAfkingModule) does `_removeFromSet` (swap-pop) + `continue`
///         WITHOUT advancing the cursor, so with cursor at 0 and every sub evicting, the set drains
///         to empty in ONE saturated chunk -- the heaviest completing chunk, now segregated.
///
/// @dev TEST-ONLY. NO contracts/*.sol is mutated. Reuses the V56AfkingGasMarginal driving harness
///      patterns verbatim (the funded-sub grounded subscribe, the deity-pass grant, the pass-evict
///      forcing via _clearDeityPass + _pokeValidThroughLevel + _setLevel, the gap-resume precondition
///      injection from testGapResumePerAdvanceCeilingAndDecouple, the vm.cool cold first-touch). All
///      pinned slots are the v61/c4d48008 storageLayout offsets carried from V56AfkingGasMarginal.
contract V62GasBrickCompose is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (forge inspect DegenerusGame storageLayout, v61/c4d48008)
    // (carried verbatim from V56AfkingGasMarginal so the probes are slot-faithful)
    // -------------------------------------------------------------------------
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant SUBOF_SLOT = 54;       // post V62 lootbox repack: was 58
    uint256 private constant SUBSCRIBERS_SLOT = 56; // post V62 lootbox repack: was 60

    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel (bytes 1..3)

    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;

    uint256 private constant HEADER_SLOT = 0;
    uint256 private constant OFF_DAILY_IDX = 4;          // uint32 @ byte 4

    // -------------------------------------------------------------------------
    // Bounds + composition geometry
    // -------------------------------------------------------------------------

    /// @dev The hard EIP-7825 per-transaction gas cap. A single advanceGame tx above this can never
    ///      complete -> permanent advanceGame DoS / forced unrecoverable game-over (the brick).
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    /// @dev SUB_STAGE_WEIGHT_BUDGET (AdvanceModule): the per-chunk gas-weight budget. With
    ///      SUB_STAGE_EVICT_WEIGHT = 7 the budget admits BUDGET/EVICT_WEIGHT = 357 evicts per chunk
    ///      (the saturated all-evict chunk, ~9.7M cold per test_AllEvictSaturatedChunk_LIVE_Measured).
    uint256 internal constant SUB_STAGE_WEIGHT_BUDGET = 2500;

    /// @dev The all-evict set size for the composed chunk. CRITICAL STRUCTURAL CONSTRAINT: for the
    ///      chunk to FALL THROUGH to rngGate (the composition), the loop must exit via
    ///      `cursor >= _subscribers.length` (cursor reached end -> subsFullyProcessed) and NOT via
    ///      `weight >= SUB_STAGE_WEIGHT_BUDGET`. An evict is weight 7, so a chunk that fully drains
    ///      (falls through) carries < 2500 weight; a chunk that hits 2500 weight BREAKS (STAGE_SUBS_WORKING)
    ///      and never reaches the backfill in that tx. So the worst COMPOSABLE evict count is just under
    ///      the budget: 356 evicting subs × 7 + the 2 deploy-exempt VAULT/SDGNRS skips (weight 1 each) = 2494
    ///      weight is the heaviest set that still fully drains in ONE chunk and falls through to the backfill.
    uint256 internal constant EVICTING_SUBS = 356;

    /// @dev The VRF/keeper stall length (days). _backfillGapDays caps the backfill loop at 120 days;
    ///      120 is the binding worst case. Stalling > 120 days still backfills exactly 120 (the cap).
    uint256 internal constant STALL_DAYS = 130; // > 120 so the cap (120) is the binding backfilled count

    uint256 private constant DRAIN_MAX_ITERATIONS = 240;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 100_000_000 ether);
    }

    // =========================================================================
    // V62-02 — the composed single-tx brick repro
    // =========================================================================

    /// @notice THE VERDICT TEST (post-fix regression guard). Seed BOTH preconditions and measure the
    ///         realistic COLD stall-recovery sequence (subs funded/stamped on prior txs, so their slots +
    ///         the cross-contract finalize are cold first-touches, exactly the regime
    ///         V56AfkingGasMarginal::testResidualR1 measures the all-evict chunk in). With the fix the
    ///         near-saturated all-evict subscriber chunk runs ALONE in tx1 (STAGE_SUBS_BACKFILL_DEFERRED)
    ///         and the 120-day gap backfill is segregated into tx2. Assert BOTH legs stay under the
    ///         EIP-7825 per-tx cap (16,777,216) and that the work actually happened (non-vacuity). If a
    ///         regression re-merged the two legs, the segregation asserts fail loudly.
    function testV62_02FixSegregatesBackfillCold() public {
        Result memory r = _seedAndMeasure(EVICTING_SUBS, true);
        _logResult("cold", r);

        // Non-vacuity: the heavy subscriber chunk really evicted the set in tx1.
        assertGt(r.evicted, 0, "non-vacuity: the subscriber stage actually evicted subs in tx1");
        assertTrue(r.subsFullyProcessed, "non-vacuity: the set drained to its end in tx1 (subsFullyProcessed)");

        // FIX: tx1 carried the subscriber chunk only — the backfill did NOT compose into it.
        assertEq(r.backfilled, 0, "FIX: the gap backfill did NOT run in tx1 (segregated by STAGE_SUBS_BACKFILL_DEFERRED)");
        assertFalse(r.composed, "FIX: tx1 is NOT the composed (evict + backfill) brick");
        assertLt(r.txGas, EIP7825_TX_GAS_CAP, "FIX: the lone subscriber chunk stays under the EIP-7825 per-tx cap");

        // The backfill is segregated into its own subsequent tx — and that tx is also under the cap.
        assertTrue(r.ranSecondTx, "FIX: a follow-up advanceGame runs (advanceDue stayed true - liveness preserved)");
        assertGt(r.tx2Backfilled, 100, "FIX: a near-full 120-day backfill ran in the SEPARATE follow-up tx");
        assertLt(r.tx2Gas, EIP7825_TX_GAS_CAP, "FIX: the lone backfill tx stays under the EIP-7825 per-tx cap");
    }

    /// @notice DIAGNOSTIC: the SAME scenario measured WARM (same-tx slots). The fix is a control-flow
    ///         break, so the segregation is independent of slot temperature — the backfill is deferred
    ///         to tx2 warm just as it is cold (only the absolute gas differs). Asserts the segregation
    ///         and logs both legs so the warm/cold gas floors sit side by side.
    function testV62_02WarmFloorDiagnostic() public {
        Result memory r = _seedAndMeasure(EVICTING_SUBS, false);
        _logResult("warm", r);
        assertFalse(r.composed, "warm: the fix segregates regardless of slot temperature (no composition)");
        assertEq(r.backfilled, 0, "warm: the gap backfill is still deferred out of tx1");
        assertTrue(r.ranSecondTx && r.tx2Backfilled > 100, "warm: the backfill still runs in the separate follow-up tx");
    }

    /// @notice CONTROL: the BOUNDARY. With a FULL-budget evicting set (>= 357 evicts) the chunk hits the
    ///         SUB_STAGE_WEIGHT_BUDGET (2500) BEFORE the cursor reaches the set end, so the stage BREAKS
    ///         (STAGE_SUBS_WORKING) and the gap backfill does NOT run in that tx — there is no
    ///         composition. This proves the composition is bounded to the fall-through chunk (< 2500
    ///         weight): the saturated chunk and the backfill canNOT share a tx. It also proves the verdict
    ///         test is measuring the REAL worst composable case, not an over-sized artifact.
    function testV62_02BoundaryFullBudgetBreaksNoCompose() public {
        // 600 evicting subs -> the first chunk evicts ~500 (budget) and BREAKS; the cursor does not reach
        // the end, subsFullyProcessed stays false, rngGate/backfill do not run this tx.
        Result memory r = _seedAndMeasure(600, true);
        _logResult("boundary_600", r);
        assertGt(r.evicted, 0, "control: the over-budget chunk still evicted subs");
        // The defining control assertion: the gap backfill did NOT run in the same tx (stage broke).
        assertEq(r.backfilled, 0, "CONTROL: a full-budget (>=500) evict chunk BREAKS -> NO backfill composes in that tx");
        assertEq(r.subsFullyProcessed ? uint256(1) : uint256(0), 0, "CONTROL: subsFullyProcessed stayed false (stage broke, did not fall through)");
    }

    // =========================================================================
    // The seed + measure core (parameterized by evicting-sub count + cold flag)
    // =========================================================================

    struct Result {
        uint256 txGas; // tx1: the subscriber completing chunk
        uint256 evicted;
        uint256 backfilled; // gap days backfilled IN tx1 (0 once segregated)
        uint256 expectedBackfilled;
        uint256 remaining;
        bool composed; // both legs in tx1 (false once segregated)
        bool subsFullyProcessed;
        // Second leg: the deferred-backfill tx that runs immediately after tx1.
        uint256 tx2Gas;
        uint256 tx2Backfilled;
        bool ranSecondTx;
    }

    /// @dev Seed the all-evict subscriber set + the 120-day gap-backfill precondition, then bracket ONE
    ///      advanceGame() and decompose what ran. `evictCount` sizes the evicting set; `cold` re-colds
    ///      the game storage (vm.cool) before the bracketed advance (the realistic first-touch regime).
    function _seedAndMeasure(uint256 evictCount, bool cold) internal returns (Result memory r) {
        // ---- (A) Build the all-evict subscriber set ----
        // Settle clean first (no in-flight RNG -> advanceGame won't revert RngNotReady).
        _settleClean(uint256(keccak256(abi.encodePacked("v62_base_", _u(evictCount)))) | 1);

        // Grounded subs (deity + funded -> the D-11/D-12 subscribe gates pass), as
        // V56AfkingGasMarginal::_measureEvictStageGas[Cold] builds them.
        for (uint256 i; i < evictCount; ++i) {
            address who = makeAddr(string(abi.encodePacked("v62_", _u(i))));
            _grantDeityPass(who);
            _fundPool(who, 5 ether);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0));
        }

        // Open the grounded subscribe's pending boxes first — the no-orphan guard (AfkingModule:1164)
        // would otherwise SKIP a pending-box sub (cheap, weight 1) instead of routing it to the heavy
        // EVICT branch. Opening clears them so the forced crossing routes every sub through EVICT.
        vm.prank(makeAddr("v62_ev_open"));
        game.openBoxes(evictCount * 2);

        // Force the pass-evict crossing on every sub (clear deity bit -> finite horizon 0 +
        // validThroughLevel 0 < currentLevel) so each routes through EVICT (_finalizeAfking + delete +
        // swap-pop), weight SUB_STAGE_EVICT_WEIGHT.
        for (uint256 i; i < evictCount; ++i) {
            address who = makeAddr(string(abi.encodePacked("v62_", _u(i))));
            _clearDeityPass(who);
            _pokeValidThroughLevel(who, 0);
        }
        _setLevel(10);

        uint256 subCountBefore = _subscriberCount();
        require(subCountBefore >= evictCount, "fixture: the full evicting set is in _subscribers");

        // ---- (B) Inject the 120-day gap-backfill precondition ----
        // (same technique as V56AfkingGasMarginal::testGapResumePerAdvanceCeilingAndDecouple)
        _setHeaderField(14, 3, 10); // level = 10 (the 120-day inactivity clock guards liveness, not lvl-0 idle)
        // A fresh resumed-day VRF word ready (rngWordCurrent slot 3) — the gap-backfill trigger.
        vm.store(address(game), bytes32(uint256(3)), bytes32(uint256(keccak256("v62_freshword")) | 1));

        uint32 idxBeforeStall = _dailyIdx();

        // The stall: warp STALL_DAYS whole days WITHOUT advancing so currentDayView() runs far ahead of
        // dailyIdx -> `day > idx + 1 && rngWordByDay[idx + 1] == 0` (the backfill precondition).
        vm.warp(block.timestamp + STALL_DAYS * 1 days);
        uint32 resumeDay = game.currentDayView();
        _setHeaderField(0, 4, resumeDay - 1);            // psd kept recent (game alive: resumeDay-psd=1)
        _setHeaderField(8, 6, uint48(block.timestamp));  // rngRequestTime within the 14-day VRF grace

        require(resumeDay > idxBeforeStall + 1, "fixture: a multi-day gap opened (day >> dailyIdx)");
        require(rngWordByDay(idxBeforeStall + 1) == 0, "fixture: the gap range is unbackfilled pre-resume");
        require(game.advanceDue(), "fixture: advanceDue on resume");

        uint256 rawGap = uint256(resumeDay - idxBeforeStall - 1);
        r.expectedBackfilled = rawGap > 120 ? 120 : rawGap;

        uint256 backfilledBefore = _countBackfilled(idxBeforeStall, resumeDay);

        // ---- (C) Measure ONE advanceGame() — the composed tx ----
        if (cold) vm.cool(address(game)); // realistic stall-recovery first-touch (matches testResidualR1)
        uint256 gasBefore = gasleft();
        game.advanceGame();
        r.txGas = gasBefore - gasleft();

        // ---- (D) Decompose tx1 ----
        uint256 subCountAfter = _subscriberCount();
        r.remaining = subCountAfter;
        r.evicted = subCountBefore > subCountAfter ? subCountBefore - subCountAfter : 0;
        uint256 backfilledAfter = _countBackfilled(idxBeforeStall, resumeDay);
        r.backfilled = backfilledAfter > backfilledBefore ? backfilledAfter - backfilledBefore : 0;
        r.composed = (r.evicted > 0) && (r.backfilled > 0);
        r.subsFullyProcessed = _subsFullyProcessed();

        // ---- (E) Measure the immediate next advanceGame (the deferred-backfill leg) ----
        // Post-fix, when tx1 segregated the subscriber chunk (STAGE_SUBS_BACKFILL_DEFERRED), the
        // backfill runs ALONE here. Measured cold too (the realistic stall-recovery first-touch).
        if (game.advanceDue()) {
            if (cold) vm.cool(address(game));
            uint256 gas2Before = gasleft();
            game.advanceGame();
            r.tx2Gas = gas2Before - gasleft();
            r.ranSecondTx = true;
            uint256 backfilledAfter2 = _countBackfilled(idxBeforeStall, resumeDay);
            r.tx2Backfilled = backfilledAfter2 > backfilledAfter ? backfilledAfter2 - backfilledAfter : 0;
        }
    }

    /// @dev Count non-zero rngWordByDay entries in the gap range (idxBeforeStall+1 .. resumeDay-1).
    function _countBackfilled(uint32 idxBeforeStall, uint32 resumeDay) internal view returns (uint256 c) {
        for (uint256 d = 1; d <= STALL_DAYS + 1; ++d) {
            uint32 probe = uint32(uint256(idxBeforeStall) + d);
            if (probe >= resumeDay) break;
            if (rngWordByDay(probe) != 0) c++;
        }
    }

    function _logResult(string memory tag, Result memory r) internal {
        emit log_named_string("regime", tag);
        emit log_named_uint("tx1_subscriber_chunk_gas", r.txGas);
        emit log_named_uint("tx2_deferred_backfill_gas", r.tx2Gas);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);
        emit log_named_uint("subscribers_evicted_in_final_chunk", r.evicted);
        emit log_named_uint("gap_days_backfilled_in_tx1", r.backfilled);
        emit log_named_uint("gap_days_backfilled_in_tx2", r.tx2Backfilled);
        emit log_named_uint("gap_days_expected_capped120", r.expectedBackfilled);
        emit log_named_uint("subscribers_remaining_after", r.remaining);
        emit log_named_uint("subs_fully_processed_flag", r.subsFullyProcessed ? 1 : 0);
        emit log_named_string(
            "composition_status",
            r.composed
                ? "COMPOSED: the all-evict subscriber chunk AND the gap backfill ran in ONE advanceGame tx"
                : "SEGREGATED: a stage-break (STAGE_SUBS_BACKFILL_DEFERRED) split the subscriber stage from the gap backfill"
        );
        emit log_named_string(
            "verdict",
            (r.txGas > EIP7825_TX_GAS_CAP || r.tx2Gas > EIP7825_TX_GAS_CAP)
                ? "A LEG EXCEEDS 16,777,216 (EIP-7825 brick)"
                : "BOTH LEGS UNDER 16,777,216 (no brick)"
        );
    }

    // =========================================================================
    // Internal driving harness (ported verbatim from V56AfkingGasMarginal)
    // =========================================================================

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

    function _clearDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _pokeValidThroughLevel(address who, uint24 lvl) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF)) << (OFF_VALIDTHROUGH * 8);
        cur = (cur & ~mask) | ((uint256(lvl) << (OFF_VALIDTHROUGH * 8)) & mask);
        vm.store(address(game), slot, bytes32(cur));
    }

    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (14 * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (14 * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _setHeaderField(uint256 offBytes, uint256 widthBytes, uint256 value) internal {
        uint256 cur = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT))));
        uint256 mask = ((uint256(1) << (widthBytes * 8)) - 1) << (offBytes * 8);
        cur = (cur & ~mask) | ((value << (offBytes * 8)) & mask);
        vm.store(address(game), bytes32(uint256(HEADER_SLOT)), bytes32(cur));
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    function _dailyIdx() internal view returns (uint32) {
        uint256 p = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT)))) >> (OFF_DAILY_IDX * 8);
        return uint32(p & 0xFFFFFFFF);
    }

    /// @dev Read `subsFullyProcessed` (storage slot for the bool, packed in the slot-0 region per the
    ///      layout key). Surfaced for the diagnostic log only (composition is asserted via evicted +
    ///      backfilled, which are unambiguous). subsFullyProcessed lives at slot 0 byte 28 (the
    ///      DegenerusGameStorage layout comment), but to avoid depending on that exact packing for a
    ///      load-bearing check it is read leniently and used only as a log.
    function _subsFullyProcessed() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT))));
        return ((s0 >> (28 * 8)) & 0xFF) != 0;
    }

    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    // ---- VRF settle drain (ported from V56AfkingGasMarginal) ----

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
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

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
