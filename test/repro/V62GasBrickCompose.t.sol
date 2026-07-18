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
///         THE FIX (AdvanceModule, the VRF-outstanding entry gate): the subscriber STAGE never
///         runs while rngLockedFlag is set [request -> unlock]. A buffered word / pending gap
///         backfill only exists under that lock, so the locked recovery legs (backfill, jackpot
///         apply) never walk the ring, and the ring walk (the evictions) runs only after
///         _unlockRng — the composition is structurally impossible at ANY subscriber cap, and
///         the old completing-chunk deferral (STAGE_SUBS_BACKFILL_DEFERRED, stage 13, retired)
///         became unreachable and was deleted. advanceDue() stays true across the sequence, so
///         each leg proceeds on the next permissionless crank.
///
///         The control flow this guards (AdvanceModule subscriber stage, unlocked entries only):
///           1. `_runSubscriberStage(day)` runs (weight-budgeted, SUB_STAGE_WEIGHT_BUDGET = 2500).
///           2. If `_subCursor < _subscribers.length` after the stage -> BREAK STAGE_SUBS_WORKING
///              (partial drain; rngGate does NOT run this tx).
///           3. When the cursor reaches the (shrinking) set end -> `subsFullyProcessed = true`,
///              fall through to rngGate (a fresh request at most — never an apply, which would
///              have required the lock that gates the stage out).
///         The all-evict branch (GameAfkingModule) does `_removeFromSet` (swap-pop) + `continue`
///         WITHOUT advancing the cursor, so with cursor at 0 and every sub evicting, the set drains
///         to empty in ONE saturated chunk -- the heaviest completing chunk, always stage-only.
///
/// @dev TEST-ONLY. NO contracts/*.sol is mutated. Reuses the V56AfkingGasMarginal driving harness
///      patterns verbatim (the funded-sub grounded subscribe via `_grantSeat`, the funding-kill forcing
///      via `withdrawAfkingFunding` — the successor of the deleted pass-evict crossing; a sub's
///      membership no longer ends on a level crossing, only cancel / funding-skip kill / the coin's
///      seat-exit hook — the gap-resume precondition injection from
///      testGapResumePerAdvanceCeilingAndDecouple, the vm.cool cold first-touch). All pinned slots are
///      the v61/c4d48008 storageLayout offsets carried from V56AfkingGasMarginal.
contract V62GasBrickCompose is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (forge inspect DegenerusGame storageLayout, v61/c4d48008)
    // (carried verbatim from V56AfkingGasMarginal so the probes are slot-faithful)
    // -------------------------------------------------------------------------
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant SUBOF_SLOT = 53;       // post V62 lootbox repack: was 58
    uint256 private constant SUBSCRIBERS_SLOT = 55; // post V62 lootbox repack: was 60

    uint256 private constant HEADER_SLOT = 0;
    uint256 private constant OFF_DAILY_IDX = 3;          // uint24 @ byte 3

    // -------------------------------------------------------------------------
    // Bounds + composition geometry
    // -------------------------------------------------------------------------

    /// @dev The hard EIP-7825 per-transaction gas cap. A single advanceGame tx above this can never
    ///      complete -> permanent advanceGame DoS / forced unrecoverable game-over (the brick).
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    /// @dev SUB_STAGE_WEIGHT_BUDGET (AdvanceModule): the per-chunk gas-weight budget. With
    ///      SUB_STAGE_EVICT_WEIGHT = 8 the budget admits BUDGET/EVICT_WEIGHT = 312 evicts per chunk
    ///      (the saturated all-evict chunk, <10M cold per test_AllEvictSaturatedChunk_LIVE_Measured).
    uint256 internal constant SUB_STAGE_WEIGHT_BUDGET = 2500;

    /// @dev The all-evict set size for the composed chunk. CRITICAL STRUCTURAL CONSTRAINT: for the
    ///      chunk to FALL THROUGH to rngGate (the composition), the loop must exit via
    ///      `cursor >= _subscribers.length` (cursor reached end -> subsFullyProcessed) and NOT via
    ///      `weight >= SUB_STAGE_WEIGHT_BUDGET`. An evict is weight 8, so a chunk that fully drains
    ///      (falls through) carries < 2500 weight; a chunk that hits 2500 weight BREAKS (STAGE_SUBS_WORKING)
    ///      and never reaches the backfill in that tx. So the worst COMPOSABLE evict count is just under
    ///      the budget: 312 evicting subs × 8 + the 2 deploy-exempt VAULT/SDGNRS skips (SUB_STAGE_SKIP_WEIGHT
    ///      = 2 each) = 2500 weight — the last evict enters at 2492 < 2500, so this set still fully drains
    ///      in ONE chunk (the heaviest completing chunk).
    uint256 internal constant EVICTING_SUBS = 312;

    /// @dev The VRF/keeper stall length (days). The VRF-death deadman (_VRF_DEADMAN_DAYS = 120) sends any
    ///      advance with currentDay - dailyIdx > 120 to terminal game-over, so the LARGEST stall that still
    ///      resumes into the stage + gap-backfill path (rather than game-over) is exactly 120 — which yields
    ///      a 119-day backfill (gap = currentDay - dailyIdx - 1). The deadman, not the 120-day backfill-loop
    ///      cap, is now the binding bound on the backfilled count.
    uint256 internal constant STALL_DAYS = 120; // == _VRF_DEADMAN_DAYS: max stall that resumes (not game-over)

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

    /// @notice THE VERDICT TEST (post-fix regression guard). Seed BOTH preconditions and drive the
    ///         realistic COLD stall-recovery sequence leg by leg, organically (real request, real
    ///         mock-VRF fulfill). Under the VRF-outstanding entry gate the UNLOCKED resume entries
    ///         drain the ring (eviction chunks, then a cheap request), while the LOCKED legs (gap
    ///         backfill, jackpot apply) never walk the ring — so no advance tx can ever compose the
    ///         subscriber chunk with the backfill/jackpot legs, and EVERY leg stays under the
    ///         EIP-7825 per-tx cap (16,777,216). Non-vacuity: the full backfill and the full
    ///         evicting drain both actually happen across the sequence.
    function testV62_02GateSegregatesRecoveryCold() public {
        Result memory r = _seedAndMeasure(EVICTING_SUBS, true);
        _logResult("cold", r);

        // Non-vacuity: both heavy legs really ran (in separate txs).
        assertGt(r.totalBackfilled, 100, "non-vacuity: a near-full 120-day backfill ran");
        assertEq(r.totalEvicted, EVICTING_SUBS, "non-vacuity: the whole evicting set drained");

        // THE GATE: ring work and the gap backfill never share a tx (the ring drains on
        // the unlocked resume entries; the backfill runs under the lock, where the
        // entry gate keeps the stage out).
        assertFalse(r.composed, "GATE: no advance tx composed evictions with the gap backfill");

        // THE BRICK PREDICATE: every leg of the recovery fits under the per-tx cap.
        assertLt(r.maxLegGas, EIP7825_TX_GAS_CAP, "every recovery leg stays under the EIP-7825 per-tx cap");
    }

    /// @notice DIAGNOSTIC: the SAME scenario measured WARM (same-tx slots). The gate is control
    ///         flow, so the segregation is independent of slot temperature — only the absolute
    ///         gas differs.
    function testV62_02WarmFloorDiagnostic() public {
        Result memory r = _seedAndMeasure(EVICTING_SUBS, false);
        _logResult("warm", r);
        assertFalse(r.composed, "warm: the gate segregates regardless of slot temperature");
        assertEq(r.totalEvicted, EVICTING_SUBS, "warm: the evicting set still drains");
    }

    /// @notice CONTROL: the BOUNDARY. With an over-budget evicting set (600 > the 312-evict chunk
    ///         capacity) the post-unlock stage BREAKS at SUB_STAGE_WEIGHT_BUDGET and drains across
    ///         multiple chunks — proving the weight budget still chunks the ring walk after the
    ///         gate, and every chunk leg stays under the cap with no composition anywhere.
    function testV62_02BoundaryFullBudgetChunksAfterGate() public {
        Result memory r = _seedAndMeasure(600, true);
        _logResult("boundary_600", r);
        assertEq(r.totalEvicted, 600, "control: the over-budget set fully drained across chunks");
        assertGt(r.maxEvictedLeg, 0, "control: chunked eviction legs ran");
        assertLt(r.maxEvictedLeg, 600, "control: no single leg evicted the whole over-budget set (budget chunking)");
        assertFalse(r.composed, "CONTROL: chunked legs never compose with the backfill either");
        assertLt(r.maxLegGas, EIP7825_TX_GAS_CAP, "CONTROL: every chunked leg stays under the per-tx cap");
    }

    // =========================================================================
    // The seed + measure core (parameterized by evicting-sub count + cold flag)
    // =========================================================================

    /// @dev Max advance legs the recovery drive will spend before giving up (liveness
    ///      bound for the harness itself, far above the organic leg count).
    uint256 internal constant MAX_LEGS = 12;

    struct Result {
        uint256 legs; // advance txs driven
        uint256 maxLegGas; // the heaviest single leg — the brick predicate
        uint256 totalEvicted;
        uint256 totalBackfilled;
        uint256 expectedBackfilled;
        uint256 maxEvictedLeg; // heaviest evicting chunk (proves budget chunking)
        uint256 evictLegGas; // gas of that chunk's leg
        uint256 remaining;
        bool composed; // an eviction and a backfill shared one tx (must never)
        bool subsFullyProcessed;
    }

    /// @dev Seed the all-evict subscriber set + the 120-day gap-backfill precondition, then bracket ONE
    ///      advanceGame() and decompose what ran. `evictCount` sizes the evicting set; `cold` re-colds
    ///      the game storage (vm.cool) before the bracketed advance (the realistic first-touch regime).
    function _seedAndMeasure(uint256 evictCount, bool cold) internal returns (Result memory r) {
        // ---- (A) Build the all-evict subscriber set ----
        // Settle clean first (no in-flight RNG -> advanceGame won't revert RngNotReady).
        _settleClean(uint256(keccak256(abi.encodePacked("v62_base_", _u(evictCount)))) | 1);

        // Grounded subs (seat + funded -> the D-11/D-12 subscribe gates pass), as
        // V56AfkingGasMarginal::_measureEvictStageGas[Cold] builds them.
        address[] memory killSubs = new address[](evictCount);
        for (uint256 i; i < evictCount; ++i) {
            address who = makeAddr(string(abi.encodePacked("v62_", _u(i))));
            killSubs[i] = who;
            _grantSeat(who);
            _fundPool(who, 5 ether);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0));
        }

        // Open the grounded subscribe's pending boxes first — the no-orphan guard (AfkingModule:1164)
        // would otherwise SKIP a pending-box sub (cheap, weight 1) instead of routing it to the heavy
        // EVICT branch. Opening clears them so the forced funding-kill routes every sub through EVICT.
        vm.prank(makeAddr("v62_ev_open"));
        game.openBoxes(evictCount * 2);

        // Force the funding-kill on every sub: drain its afkingFunding bucket to 0 (after the grounded
        // day-0 cover-buy consumed its slice) so the STAGE's fresh-ETH resolve finds srcFunding(0) <
        // ethValue and each routes through EVICT (_finalizeAfking + delete + swap-pop), weight
        // SUB_STAGE_EVICT_WEIGHT — the successor of the deleted pass-evict crossing (membership no longer
        // ends on a level crossing, only cancel / funding-skip kill / the coin's seat-exit hook).
        for (uint256 i; i < evictCount; ++i) {
            uint256 bal = game.afkingFundingOf(killSubs[i]);
            if (bal > 0) {
                vm.prank(killSubs[i]);
                game.withdrawAfkingFunding(bal);
            }
        }

        uint256 subCountBefore = _subscriberCount();
        require(subCountBefore >= evictCount, "fixture: the full evicting set is in _subscribers");

        // ---- (B) The 120-day stall, driven ORGANICALLY ----
        // No RNG- or level-state pokes: the resume request, the lock, the fulfilled buffered
        // word and the backfill all arise from real advances + the mock VRF, so every branch
        // the recovery takes is the branch mainnet would take (the entry gate keys on the
        // real rngLockedFlag lifecycle). Level stays at genesis: the 120-day stall is within
        // the lvl-0 365-day idle clock, and the resume days settle without a level
        // transition (no charity-pick dependency in the fixture).

        uint32 idxBeforeStall = _dailyIdx();

        // The stall: warp STALL_DAYS whole days WITHOUT advancing so currentDayView() runs far ahead of
        // dailyIdx -> `day > idx + 1 && rngWordByDay[idx + 1] == 0` (the backfill precondition).
        vm.warp(block.timestamp + STALL_DAYS * 1 days);
        uint32 resumeDay = game.currentDayView();
        _setHeaderField(0, 3, resumeDay - 1);            // psd kept recent (game alive: resumeDay-psd=1)

        require(resumeDay > idxBeforeStall + 1, "fixture: a multi-day gap opened (day >> dailyIdx)");
        require(rngWordByDay(idxBeforeStall + 1) == 0, "fixture: the gap range is unbackfilled pre-resume");
        require(game.advanceDue(), "fixture: advanceDue on resume");

        uint256 rawGap = uint256(resumeDay - idxBeforeStall - 1);
        r.expectedBackfilled = rawGap > 120 ? 120 : rawGap;

        // ---- (C) Drive the recovery leg-by-leg and decompose every advance tx ----
        // Under the VRF-outstanding entry gate the organic recovery is a SEQUENCE: the
        // unlocked resume entry walks the ring FIRST (the eviction chunks, then the
        // completing chunk falls through to a cheap request), the fulfilled word arrives
        // buffered UNDER THE LOCK, and the locked legs (gap backfill, jackpot apply)
        // never walk the ring — so no single tx can compose ring work with the
        // backfill/jackpot legs. The loop records each leg, fulfills the mock VRF as
        // requests organically appear, and stops when the recovery converges.
        uint256 prevSubs = subCountBefore;
        uint256 prevBackfilled = _countBackfilled(idxBeforeStall, resumeDay);
        for (uint256 leg; leg < MAX_LEGS; ++leg) {
            if (!game.advanceDue()) break;
            if (cold) vm.cool(address(game)); // realistic stall-recovery first-touch per leg
            uint256 gasBefore = gasleft();
            game.advanceGame();
            uint256 gasUsed = gasBefore - gasleft();

            uint256 subsNow = _subscriberCount();
            uint256 backfilledNow = _countBackfilled(idxBeforeStall, resumeDay);
            uint256 evictedLeg = prevSubs > subsNow ? prevSubs - subsNow : 0;
            uint256 backfilledLeg = backfilledNow > prevBackfilled
                ? backfilledNow - prevBackfilled
                : 0;
            prevSubs = subsNow;
            prevBackfilled = backfilledNow;

            r.legs++;
            if (gasUsed > r.maxLegGas) r.maxLegGas = gasUsed;
            r.totalEvicted += evictedLeg;
            r.totalBackfilled += backfilledLeg;
            if (evictedLeg > 0 && backfilledLeg > 0) r.composed = true;
            if (evictedLeg > 0 && evictedLeg > r.maxEvictedLeg) {
                r.maxEvictedLeg = evictedLeg;
                r.evictLegGas = gasUsed;
            }

            // Fulfill any organically-fired VRF request so the next leg proceeds
            // (the buffered word then exists exactly as mainnet would hold it: locked).
            _fulfillPending(uint256(keccak256(abi.encodePacked("v62_word_", _u(leg)))) | 1);

            if (
                r.totalEvicted >= evictCount &&
                r.totalBackfilled >= r.expectedBackfilled
            ) break; // both heavy legs proven — the recovery converged
        }
        r.remaining = _subscriberCount();
        r.subsFullyProcessed = _subsFullyProcessed();
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
        emit log_named_uint("recovery_legs_driven", r.legs);
        emit log_named_uint("heaviest_leg_gas", r.maxLegGas);
        emit log_named_uint("evict_chunk_leg_gas", r.evictLegGas);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);
        emit log_named_uint("total_evicted", r.totalEvicted);
        emit log_named_uint("heaviest_evicting_leg", r.maxEvictedLeg);
        emit log_named_uint("total_gap_days_backfilled", r.totalBackfilled);
        emit log_named_uint("gap_days_expected_capped120", r.expectedBackfilled);
        emit log_named_uint("subscribers_remaining_after", r.remaining);
        emit log_named_uint("subs_fully_processed_flag", r.subsFullyProcessed ? 1 : 0);
        emit log_named_string(
            "composition_status",
            r.composed
                ? "COMPOSED: an advance tx carried BOTH ring evictions and gap backfill"
                : "SEGREGATED: the VRF-outstanding entry gate kept ring work and RNG resolution in separate txs"
        );
        emit log_named_string(
            "verdict",
            r.maxLegGas > EIP7825_TX_GAS_CAP
                ? "A LEG EXCEEDS 16,777,216 (EIP-7825 brick)"
                : "EVERY LEG UNDER 16,777,216 (no brick)"
        );
    }

    // =========================================================================
    // Internal driving harness (ported verbatim from V56AfkingGasMarginal)
    // =========================================================================

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
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
        return uint32(p & 0xFFFFFF);
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
