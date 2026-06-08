// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title V62GasBrickCompose -- empirical reproduction of finding V62-02.
///
/// @notice V62-02 (adjudicated vs frozen c4d48008): the new-day advanceGame path runs the afking
///         subscriber STAGE then, when the cursor reaches the set end in ONE chunk
///         (subsFullyProcessed == true), FALLS THROUGH to rngGate -> _backfillGapDays with NO
///         intervening stage-break. The v60 decouple (AdvanceModule:363-366 `if (gapDays != 0) {
///         stage = STAGE_GAP_BACKFILLED; break; }`) breaks AFTER rngGate -- it decouples the gap
///         backfill from the DOWNSTREAM daily jackpot, NOT from the UPSTREAM subscriber stage. So a
///         single advanceGame() can run BOTH a saturated all-evict subscriber chunk (~13.3M cold,
///         measured in V56AfkingGasMarginal::testResidualR1) AND the 120-day gap backfill (~7M) in
///         one tx. If the sum exceeds EIP-7825's 16,777,216 per-tx cap, advanceGame can never
///         complete -> permanent brick during stall recovery.
///
///         The composition condition (control flow, AdvanceModule:321-366):
///           1. `_runSubscriberStage(day)` runs (weight-budgeted, SUB_STAGE_WEIGHT_BUDGET = 500).
///           2. If `_subCursor < _subscribers.length` after the stage -> BREAK STAGE_SUBS_WORKING
///              (partial drain; rngGate / backfill do NOT run this tx).
///           3. ONLY when the cursor reaches the (shrinking) set end -> `subsFullyProcessed = true`
///              -> FALL THROUGH to rngGate -> backfill, in the SAME tx.
///         The all-evict branch (GameAfkingModule:1214-1235) does `_removeFromSet` (swap-pop) +
///         `continue` WITHOUT advancing the cursor, so with cursor at 0 and every sub evicting, the
///         set drains to empty in ONE saturated chunk (weight = #evicts, capped by the 500 budget),
///         cursor reaches end (0 >= 0), subsFullyProcessed flips true -> rngGate -> 120-day backfill.
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
    uint256 private constant SUBOF_SLOT = 58;       // post V62 lootbox repack: was 62
    uint256 private constant SUBSCRIBERS_SLOT = 60; // post V62 lootbox repack: was 64

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

    /// @dev SUB_STAGE_WEIGHT_BUDGET (AdvanceModule:158): the per-chunk gas-weight budget. With
    ///      SUB_STAGE_EVICT_WEIGHT = 1 the budget admits BUDGET/EVICT_WEIGHT = 500 evicts per chunk
    ///      (the saturated all-evict chunk, the binding STAGE worst case ~13.3M cold per testResidualR1).
    uint256 internal constant SUB_STAGE_WEIGHT_BUDGET = 500;

    /// @dev The all-evict set size for the composed chunk. CRITICAL STRUCTURAL CONSTRAINT: for the
    ///      chunk to FALL THROUGH to rngGate (the composition), the loop must exit via
    ///      `cursor >= _subscribers.length` (cursor reached end -> subsFullyProcessed) and NOT via
    ///      `weight >= SUB_STAGE_WEIGHT_BUDGET`. An evict is weight 1, so a chunk that fully drains
    ///      (falls through) carries < 500 weight; a chunk that hits 500 weight BREAKS (STAGE_SUBS_WORKING)
    ///      and never reaches the backfill in that tx. So the worst COMPOSABLE evict count is just under
    ///      the budget. 497 evicting subs (+ the 2 deploy-exempt VAULT/SDGNRS skips = 499 weight) is the
    ///      heaviest set that still fully drains in ONE chunk and falls through to the 120-day backfill.
    uint256 internal constant EVICTING_SUBS = 497;

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

    /// @notice THE VERDICT TEST. Seed BOTH preconditions and measure ONE advanceGame() that runs the
    ///         (near-saturated, fall-through) all-evict subscriber chunk AND the 120-day gap backfill in
    ///         a single tx, COLD (the realistic stall-recovery regime — subs funded/stamped on prior txs,
    ///         so their slots + the cross-contract finalize are cold first-touches, exactly the regime
    ///         V56AfkingGasMarginal::testResidualR1 measures the all-evict chunk in). Assert the composed
    ///         tx EXCEEDS the EIP-7825 per-tx cap (16,777,216). If a stage-break separated the two legs
    ///         the non-vacuity asserts fail loudly (-> would refute V62-02).
    function testV62_02ComposedSingleTxBrickCold() public {
        Result memory r = _seedAndMeasure(EVICTING_SUBS, true);
        _logResult("cold", r);

        // Non-vacuity: BOTH legs executed in the one measured tx (a stage-break would make this vacuous).
        assertGt(r.evicted, 0, "non-vacuity: the subscriber stage actually evicted subs in the measured tx");
        assertGt(r.backfilled, 0, "non-vacuity: the gap backfill ran in the SAME measured tx (no stage-break)");
        assertTrue(r.composed, "V62-02 composition: both the evict chunk and the 120-day gap backfill ran in ONE tx");
        // The fall-through actually happened (the cursor reached the set end -> subsFullyProcessed),
        // so the backfill ran from the same advanceGame as the evict stage, not a separate tx.
        assertGt(r.backfilled, 100, "V62-02: a near-full 120-day backfill ran in the composed tx (not a 1-day residual)");

        // V62-02 CONFIRMED iff the single composed COLD tx exceeds the EIP-7825 per-tx cap.
        assertGt(
            r.txGas,
            EIP7825_TX_GAS_CAP,
            "V62-02 CONFIRMED: a single advanceGame tx composing the all-evict subscriber chunk + the 120-day gap backfill exceeds 16,777,216 (EIP-7825) -> permanent brick"
        );
    }

    /// @notice DIAGNOSTIC: the SAME composition measured WARM (same-tx slots). This is the
    ///         understatement regime — the subs were funded/stamped in THIS test tx, so their slots are
    ///         warm when the bracketed advance reads them. testResidualR1/testColdMarginalCalibration
    ///         document that warm same-tx slots understate the realistic cold cost by ~1.7-3x. The warm
    ///         floor is logged (not asserted over the cap) so the adjudicator sees both regimes side by
    ///         side and the cold number is anchored as the binding one.
    function testV62_02WarmFloorDiagnostic() public {
        Result memory r = _seedAndMeasure(EVICTING_SUBS, false);
        _logResult("warm", r);
        // The warm floor is genuinely the SAME composition (both legs ran) — only the slot temperature
        // differs. Asserting composition (not the cap) documents the warm understatement honestly.
        assertTrue(r.composed, "warm floor: the composition still occurs warm (only the slot temperature differs)");
        emit log_named_string(
            "warm_vs_cold_note",
            r.txGas > EIP7825_TX_GAS_CAP
                ? "warm composition ALSO exceeds the cap"
                : "warm composition is UNDER the cap (warm same-tx slots understate by ~1.7-3x; cold is the binding regime per testResidualR1)"
        );
    }

    /// @notice CONTROL: the BOUNDARY. With a FULL-budget evicting set (>= 500 evicts) the chunk hits the
    ///         SUB_STAGE_WEIGHT_BUDGET (500) BEFORE the cursor reaches the set end, so the stage BREAKS
    ///         (STAGE_SUBS_WORKING) and the gap backfill does NOT run in that tx — there is no
    ///         composition. This proves the composition is bounded to the fall-through chunk (< 500
    ///         weight): the saturated 500-weight chunk and the backfill canNOT share a tx. It also proves
    ///         the verdict test is measuring the REAL worst composable case, not an over-sized artifact.
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
        uint256 txGas;
        uint256 evicted;
        uint256 backfilled;
        uint256 expectedBackfilled;
        uint256 remaining;
        bool composed;
        bool subsFullyProcessed;
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

        // ---- (D) Decompose ----
        uint256 subCountAfter = _subscriberCount();
        r.remaining = subCountAfter;
        r.evicted = subCountBefore > subCountAfter ? subCountBefore - subCountAfter : 0;
        uint256 backfilledAfter = _countBackfilled(idxBeforeStall, resumeDay);
        r.backfilled = backfilledAfter > backfilledBefore ? backfilledAfter - backfilledBefore : 0;
        r.composed = (r.evicted > 0) && (r.backfilled > 0);
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
        emit log_named_uint("composed_advanceGame_tx_gas", r.txGas);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);
        emit log_named_uint("subscribers_evicted_in_final_chunk", r.evicted);
        emit log_named_uint("gap_days_backfilled", r.backfilled);
        emit log_named_uint("gap_days_expected_capped120", r.expectedBackfilled);
        emit log_named_uint("subscribers_remaining_after", r.remaining);
        emit log_named_uint("subs_fully_processed_flag", r.subsFullyProcessed ? 1 : 0);
        emit log_named_string(
            "composition_status",
            r.composed
                ? "COMPOSED: the all-evict subscriber chunk AND the gap backfill ran in ONE advanceGame tx"
                : "NOT COMPOSED: a stage-break separated the subscriber stage from the gap backfill"
        );
        emit log_named_string(
            "verdict",
            r.txGas > EIP7825_TX_GAS_CAP
                ? "EXCEEDS 16,777,216 (EIP-7825 brick)"
                : "UNDER 16,777,216 (no brick this regime)"
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
    ///      backfilled, which are unambiguous). subsFullyProcessed lives at slot 0 byte 29 (the
    ///      DegenerusGameStorage layout comment), but to avoid depending on that exact packing for a
    ///      load-bearing check it is read leniently and used only as a log.
    function _subsFullyProcessed() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT))));
        return ((s0 >> (29 * 8)) & 0xFF) != 0;
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
