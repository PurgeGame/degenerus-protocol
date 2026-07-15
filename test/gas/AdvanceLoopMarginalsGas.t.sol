// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";

/// @title AdvanceLoopMarginalsGas — direct per-item marginals for the two advance-internal
///        loops previously covered only transitively by the master advance fuzz
///        (audit/ASSURANCE-CASE.md, gas pillar): the orphan lootbox-index backfill walk
///        (`_backfillOrphanedLootboxIndices`, AdvanceModule) and the historical-RNG fallback
///        scan (`_getHistoricalRngFallback`, AdvanceModule). Each gets a measured worst-case
///        branch marginal (loop-N-divide, snapshot/revert two-near-N form per the CR-01 rule
///        in V56AfkingGasMarginal) plus a composed per-tx ceiling assertion, so each matrix
///        cell in the assurance case is independently green.
///
/// @notice ORPHAN-WALK growth model (why the injected counts are conservative): the walk has
///         no iteration cap — it scans backwards from lootboxRngIndex-1 until a filled index.
///         The index advances ONLY on a fresh request (`_finalizeRngRequest` isRetry=false) or
///         a mid-day lootbox request; 12h-timeout retries keep the reserved index (isRetry),
///         and every COMPLETED cycle fills its own index (`_finalizeLootboxRng` / the mid-day
///         fulfillment). Consecutive orphans therefore require repeated
///         fresh-request-then-never-fulfilled cycles, each of which needs vrfRequestId to be
///         zero again (a completed day) or the request-submission-revert path — single digits
///         per realistic stall. The 240-orphan composed case measured here sits two orders
///         above that, stacked on top of the capped 120-day gap backfill that shares the same
///         resume transaction.
///
/// @notice SEARCHDAY-SCAN bound: the loop is hard-capped at 30 iterations by construction
///         (`searchLimit = currentDay > 30 ? 30 : currentDay`), each a cold rngWordByDay
///         SLOAD. The marginal here measures the real per-iteration cost on the real branch
///         (gameover entropy fallback with a dead VRF request) and asserts the whole
///         fallback-committing advance sits far below the per-tx ceiling.
///
/// @dev Storage slots verified against `forge inspect DegenerusGame storageLayout` on the
///      current tree: header packed slot 0 (purchaseStartDay uint24 byte 0, dailyIdx uint24
///      byte 3, rngRequestTime uint48 byte 6, level uint24 byte 12), rngWordCurrent = 3,
///      rngWordByDay mapping = 10, lootboxRngPacked = 34 (lootboxRngIndex = low 48 bits),
///      lootboxRngWordByIndex mapping = 35. Test-only: ZERO contracts/*.sol mutated.
contract AdvanceLoopMarginalsGas is DeployProtocol {
    uint256 private constant HEADER_SLOT = 0;
    uint256 private constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10;
    uint256 private constant SLOT_LOOTBOX_RNG_PACKED = 34;
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35;
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF; // low 48 bits of slot 34

    /// @dev The 16.7M HARD never-exceed ceiling (USER-LOCKED dual bound; a breach on the
    ///      advance chain = a blocked required transition). Mirrors V56AfkingGasMarginal.
    uint256 private constant EFFECTIVE_GAS_CEILING = 16_700_000;
    /// @dev The 10M design comfort target (USER-LOCKED dual bound).
    uint256 private constant GAS_TARGET = 10_000_000;

    // Two-near-N orphan counts for the loop-N-divide marginal.
    uint48 private constant ORPHANS_LO = 64;
    uint48 private constant ORPHANS_HI = 192;
    // Composed worst case: capped 120-day gap backfill + this many orphans in ONE resume tx.
    uint48 private constant ORPHANS_WORST = 240;

    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helpers (fixture recipes ported from VRFStallEdgeCases / V56AfkingGasMarginal)
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> drain until unlocked.
    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Deploy + wire a fresh MockVRFCoordinator via the admin (re-issues any in-flight
    ///      daily request on the new coordinator, preserving the reserved lootbox index).
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
        _lastFulfilledReqId = 0;
    }

    function _lootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED))));
    }

    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), LOOTBOX_RNG_WORD_SLOT));
        return uint256(vm.load(address(game), slot));
    }

    function _rngWordByDay(uint24 day) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT));
        return uint256(vm.load(address(game), slot));
    }

    function _storeRngWordByDay(uint24 day, uint256 word) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day), RNG_WORD_BY_DAY_SLOT));
        vm.store(address(game), slot, bytes32(word));
    }

    /// @dev Bump lootboxRngIndex (low 48 bits of packed slot 34) by `extra`, preserving every
    ///      other packed field. The indices skipped over stay zero-worded — exactly the
    ///      orphaned shape the backfill walk exists to repair.
    function _injectOrphanIndices(uint48 extra) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED)));
        uint256 newIndex = (packed & LR_INDEX_MASK) + extra;
        packed = (packed & ~LR_INDEX_MASK) | (newIndex & LR_INDEX_MASK);
        vm.store(address(game), bytes32(SLOT_LOOTBOX_RNG_PACKED), bytes32(packed));
    }

    /// @dev Write a uint24 header field at byte offset `off` of packed slot 0.
    function _setHeaderU24(uint256 off, uint24 value) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(HEADER_SLOT)));
        uint256 shift = off * 8;
        packed = (packed & ~(uint256(0xFFFFFF) << shift)) | (uint256(value) << shift);
        vm.store(address(game), bytes32(HEADER_SLOT), bytes32(packed));
    }

    // ─────────────────────────────────────────────────────────────────────
    // (a) Orphan lootbox-index backfill walk — marginal + composed ceiling
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Shared stall fixture: complete day 2, strand a day-3 daily request, stall
    ///      `stallDays`, swap coordinators (re-issue), fulfill the re-issued request so the
    ///      NEXT advance runs the rngGate gap branch (gap backfill + orphan walk) in ONE tx.
    ///      Returns the pre-injection lootbox index.
    function _stallFixture(uint256 stallDays, uint256 resumeWord) internal returns (uint48 idx0) {
        _completeDay(0xDEAD0001);
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "fixture: day-3 daily request in flight");
        vm.warp((3 + stallDays) * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        uint256 reqId = newVRF.lastRequestId();
        assertTrue(reqId != 0, "fixture: swap re-issued the in-flight request");
        newVRF.fulfillRandomWords(reqId, resumeWord);
        idx0 = _lootboxRngIndex();
    }

    /// @dev Bracket the ONE resume advance that runs the rngGate gap branch (gap backfill +
    ///      orphan walk), with `orphans` extra zero-worded indices injected above the organic
    ///      cursor. The resume is staged (the STAGE-defer leg runs first, per the V62-02
    ///      decouple), so each advance is bracketed individually and the tx where the topmost
    ///      injected index flips zero→word is the backfill tx. Non-vacuity: that flip is
    ///      required within the advance budget.
    function _measureResumeAdvance(uint48 orphans) internal returns (uint256 gasUsed) {
        if (orphans != 0) _injectOrphanIndices(orphans);
        uint48 topIndex = _lootboxRngIndex() - 1;
        assertEq(_lootboxRngWord(topIndex), 0, "fixture: topmost injected index is orphaned");

        for (uint256 i = 0; i < 5; i++) {
            uint256 gasBefore = gasleft();
            game.advanceGame();
            uint256 thisAdvance = gasBefore - gasleft();
            if (_lootboxRngWord(topIndex) != 0) {
                return thisAdvance;
            }
        }
        revert("non-vacuity: the orphan walk never ran within 5 resume advances");
    }

    /// @notice Loop-N-divide marginal for the orphan walk: (gas at 192 orphans − gas at 64)
    ///         / 128, both measured from one identical post-stall baseline. The walk's
    ///         per-orphan work is a keccak + a zero→nonzero SSTORE + one event, so the
    ///         marginal is asserted inside a generous sanity band around that (~23K) and the
    ///         derived max-safe orphan count (vs the 16.7M ceiling, on top of the measured
    ///         fixed leg) is reported.
    function testOrphanWalkPerIndexMarginalLoopNDivide() public {
        _stallFixture(5, 0xAA050001);
        uint256 snap = vm.snapshotState();

        uint256 gasLo = _measureResumeAdvance(ORPHANS_LO);
        vm.revertToState(snap);
        uint256 gasHi = _measureResumeAdvance(ORPHANS_HI);

        uint256 perOrphan = (gasHi - gasLo) / (ORPHANS_HI - ORPHANS_LO);
        uint256 fixedLeg = gasLo - perOrphan * ORPHANS_LO;
        uint256 maxSafeOrphans = (EFFECTIVE_GAS_CEILING - fixedLeg) / perOrphan;

        emit log_named_uint("orphan_walk_gas_at_64", gasLo);
        emit log_named_uint("orphan_walk_gas_at_192", gasHi);
        emit log_named_uint("per_orphan_marginal_gas", perOrphan);
        emit log_named_uint("resume_fixed_leg_gas", fixedLeg);
        emit log_named_uint("derived_max_safe_orphans_vs_ceiling", maxSafeOrphans);

        // Sanity band: a zero→nonzero SSTORE (22.1K) + keccak + LOG2 + loop overhead lands
        // ~23-26K; a marginal outside [15K, 40K] means the loop's shape changed — re-derive.
        assertGt(perOrphan, 15_000, "per-orphan marginal below the plausible SSTORE floor");
        assertLt(perOrphan, 40_000, "per-orphan marginal above the plausible band");
    }

    /// @notice Composed worst case: the capped 120-day gap backfill AND a 240-orphan walk in
    ///         the SAME resume tx (they share the rngGate gap branch), asserted strictly
    ///         under the 16.7M never-exceed ceiling. 240 orphans is two orders above the
    ///         reachable accumulation rate (see the growth model in the contract natspec).
    function testGapBackfillPlusOrphanWalkComposedUnderCeiling() public {
        _stallFixture(123, 0xAA123001); // >121 days: the gap-day loop hits its 120 cap
        uint256 gasUsed = _measureResumeAdvance(ORPHANS_WORST);

        emit log_named_uint("composed_gap120_plus_240_orphans_gas", gasUsed);
        emit log_named_uint(
            "headroom_to_16p7M_gas",
            EFFECTIVE_GAS_CEILING > gasUsed ? EFFECTIVE_GAS_CEILING - gasUsed : 0
        );

        assertLt(
            gasUsed,
            EFFECTIVE_GAS_CEILING,
            "composed 120-day backfill + 240-orphan walk must stay under the 16.7M ceiling"
        );

        // The gap range actually backfilled (non-vacuity for the gap leg).
        assertTrue(_rngWordByDay(3) != 0, "non-vacuity: first gap day backfilled");
    }

    // ─────────────────────────────────────────────────────────────────────
    // (b) Historical-RNG fallback scan — per-iteration marginal on the real branch
    // ─────────────────────────────────────────────────────────────────────

    /// @dev Gameover-fallback fixture: complete day 2, strand a day-3 daily request, force
    ///      level=1 (header byte 12) so the 120-day inactivity clock is the alive-guard, keep
    ///      purchaseStartDay at its organic (early) value, and warp far past both the 120-day
    ///      clock and the 14-day gameover VRF-fallback delay. The next advance routes through
    ///      _gameOverEntropy's fallback leg, which runs _getHistoricalRngFallback(day) with
    ///      day > 30 → searchLimit 30, scanning rngWordByDay[1..29].
    function _gameoverFallbackFixture() internal {
        _completeDay(0xDEAD0001);
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "fixture: day-3 daily request in flight");
        _setHeaderU24(12, 1); // level = 1: the 120-day inactivity clock governs
        // 130 days: > 120-day inactivity (purchaseStartDay stays early) and the stranded
        // request is > 14 days old (GAMEOVER_RNG_FALLBACK_DELAY) — the fallback leg is armed.
        vm.warp(133 * 86400);
    }

    /// @notice Per-iteration marginal for the searchDay scan, measured on the real gameover
    ///         fallback branch as the delta between a full 29-iteration scan (organic state:
    ///         only day 2 has a word, found never reaches 5) and an early-break scan (days
    ///         1,3,4,5 pre-seeded so found hits 5 at searchDay 5). Both runs from one
    ///         identical baseline. Asserts the loop's absolute cost is noise against the
    ///         ceiling (its 30-iteration construct bound makes it structurally incapable of
    ///         threatening 16.7M) and the fallback-committing advance itself is far under
    ///         the 10M target.
    /// @dev Advance (bracketing each call) until the fallback commits the current day's word;
    ///      returns the gas of the committing advance. Staged-resume tolerant, mirroring
    ///      _measureResumeAdvance.
    function _measureFallbackCommitAdvance() internal returns (uint256 gasUsed) {
        uint24 day = uint24(game.currentDayView());
        for (uint256 i = 0; i < 5; i++) {
            uint256 gasBefore = gasleft();
            game.advanceGame();
            uint256 thisAdvance = gasBefore - gasleft();
            if (_rngWordByDay(day) != 0) {
                return thisAdvance;
            }
        }
        revert("non-vacuity: the fallback never committed within 5 advances");
    }

    function testHistoricalFallbackScanPerDayMarginal() public {
        _gameoverFallbackFixture();
        uint256 snap = vm.snapshotState();

        // Full scan: 29 iterations (searchDay 1..29), one non-zero word (day 2) found.
        uint256 gasFull = _measureFallbackCommitAdvance();

        vm.revertToState(snap);

        // Early-break scan: seed 4 more words so `found` reaches 5 at searchDay 6. Day 3 is
        // deliberately NOT seeded — it is dailyIdx + 1, which the advance stage routing reads
        // (the gap-branch precondition), and seeding it reroutes the resume stages.
        _storeRngWordByDay(1, uint256(keccak256("hist_1")));
        _storeRngWordByDay(4, uint256(keccak256("hist_4")));
        _storeRngWordByDay(5, uint256(keccak256("hist_5")));
        _storeRngWordByDay(6, uint256(keccak256("hist_6")));
        uint256 gasShort = _measureFallbackCommitAdvance();

        // 29-iteration scan vs 6-iteration scan → 23 extra cold SLOAD iterations. The two
        // runs differ in the committed word too (different downstream branch flavors), so
        // the marginal is asserted inside a wide sanity band, not to the gas.
        uint256 scanDelta = gasFull > gasShort ? gasFull - gasShort : 0;
        uint256 perDay = scanDelta / 23;

        emit log_named_uint("fallback_advance_full_scan_gas", gasFull);
        emit log_named_uint("fallback_advance_early_break_gas", gasShort);
        emit log_named_uint("scan_delta_gas_23_iterations", scanDelta);
        emit log_named_uint("per_scanned_day_marginal_gas", perDay);

        // A cold mapping SLOAD is ~2.1K; loop overhead adds ~100-200. Anything above 10K/day
        // means the loop body grew a new cost class — re-derive the bound.
        assertLt(perDay, 10_000, "per-scanned-day marginal above the cold-SLOAD band");
        // The scan's construct bound is 30 iterations; even at the band ceiling that is
        // 0.3M — structurally noise against 16.7M. Assert the whole fallback advance (scan +
        // gameover work it feeds) sits far under the 10M comfort target.
        assertLt(gasFull, GAS_TARGET, "fallback-committing advance under the 10M target");
    }
}
