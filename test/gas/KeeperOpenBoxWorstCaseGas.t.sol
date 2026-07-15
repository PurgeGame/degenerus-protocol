// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperOpenBoxWorstCaseGas -- TST-06 (Phase 351) per-OPEN marginal over the v55 AfKing-in-Game
///        stamped-box open. ADAPTED from the v49/319 HUMAN `autoOpen(maxCount)`/`boxPlayers` open worst
///        case (D-351-01) onto the AFKING open leg.
///
/// @notice v55 REFRAME (the load-bearing adaptation). The OLD subject was the HUMAN `boxPlayers` open path:
///         `autoOpen(maxCount)` walked `boxPlayers[index]` from the self-partitioning cursor + opened each
///         ready box via `_openLootBoxFor` -> the cold-ledger `lootboxEth*`/`lootboxEthBase` walk-and-zero.
///         The v55 AFKING open is a DIFFERENT, cheaper path (350-TST06-MEASUREMENT-SPEC §2):
///           - the box is a per-sub STAMP (a warm `Sub` slot: `amount`/`scorePlus1`/`lastAutoBoughtDay`),
///             written PRE-RNG by the process STAGE (`processSubscriberStage`), NOT a cold box-ledger entry;
///           - the open is `_openAfkingBox` (GameAfkingModule.sol:888) -> delegatecall
///             `resolveAfkingBox` (DegenerusGameLootboxModule.sol:877), seeded
///             `(uint256(sub.amount), day, rngWordByDay[day], uint16(sub.scorePlus1)-1)` (:901-907) — NO
///             `boxPlayers` walk, NO `lootboxEth*` read/zero (the afking open is uniform O(1) per box, the
///             anti-gas-DoS property);
///           - it is driven by `_autoOpen(maxCount)` (:938), gated by `_afkingBoxReady` (:918), reached
///             ONLY via `game.mintFlip()` (the open leg at :1000-1009). `game.autoOpen(uint256)` is the
///             HUMAN `boxPlayers` selector (DegenerusGame.sol:1787) and does NOT reach the afking open —
///             so EVERY afking open in this suite is driven by `mintFlip()` after a `_settleClean` (so it
///             routes to OPEN, advance-not-due). N < OPEN_BATCH so one `mintFlip()` opens all N.
///
///         The MARGINAL rule PRESERVED VERBATIM (CR-01 / 350-SPEC §0, load-bearing): Test D's loop-N-divide
///         MARGINAL — `perBoxMarginal = totalGas / nBoxes`, asserted < `SINGLE_BOX_TOTAL_REF_GAS` — is kept
///         in SHAPE. The per-box number is ALWAYS the loop-N-divide MARGINAL, NEVER a single-box TOTAL (a
///         single-box total bundles the once-per-call fixed overhead into one box, over-pegs, and would
///         re-open the Phase-319 self-crank faucet were a reward pegged to it). The worst-case-precondition
///         + non-vacuity gate is PRESERVED (the donor's :97-112): each box is asserted queued (a stamped
///         sub) + RNG-ready (`rngWordByDay[stampDay] != 0`) + un-opened (`lastOpenedDay < lastAutoBoughtDay`)
///         BEFORE the measurement, and opened (`lastOpenedDay == stampDay`) AFTER — so the marginal is a
///         real materialization, not a skip.
///
/// @dev Live `DeployProtocol` fixture. Reuses the validated game-resident driving harness ported from
///      RouterWorstCaseGas / V55RevertFreeEvCap / V55FreezeDeterminism (`_settleGame`/`_settleClean` VRF
///      drain, `_setupFundedLootboxSubs`, `depositAfkingFunding` funding, `_grantDeityPass`, the Sub-stamp
///      slot reads). The OLD `_buyBox` HUMAN-deposit helper is REFRAMED to a funded LOOTBOX-mode SUB
///      stamped via a new-day STAGE. All pinned slots RE-DERIVED via `solc --storage-layout` on the
///      working tree after the V62 lootbox repack: `_subOf = 54`, `_subscribers = 56`, `rngWordByDay
///      = 10`; the afking open reads NO cold ledger so the folded lootboxEth word is not load-bearing
///      here. Test-only: ZERO contracts/*.sol mutated.
contract KeeperOpenBoxWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `solc --storage-layout`, working tree)
    // -------------------------------------------------------------------------

    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint24 => uint256) — the afking box's DAY-keyed word + readiness gate
    uint256 private constant SUBOF_SLOT = 53;           // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 55;     // address[] _subscribers (slot holds the length)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol; the v56 re-packed single 256-bit slot,
    // 241/256 bits used — the markers are uint24 each, not the old uint32 232-bit layout).
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13; // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for the
    ///      harness; the "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev The 16.7M HARD effective per-tx ceiling (350-TST06-MEASUREMENT-SPEC §5) — the afking open leg
    ///      (a full OPEN_BATCH of uniform-O(1) boxes) stays under it.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev OPEN_BATCH (GameAfkingModule.sol): the flat per-box open budget; each afking box uniform O(1).
    uint256 internal constant OPEN_BATCH = 130;

    /// @dev The CR-01 converged-marginal regime: N>=32 amortizes the per-call fixed overhead away (the
    ///      donor's Test-D N). The afking open is uniform O(1) so the marginal is stable; N=32 is robust.
    uint256 internal constant N_MARGINAL = 32;

    /// @dev The afking-open per-box SINGLE-CALL reference ceiling (the CR-01 upper bound the loop-N-divide
    ///      marginal must sit BELOW). A single afking box materialization (a stamp-derived resolve, no cold
    ///      ledger) is well under the human single-box total (137_944) the donor referenced; we keep a
    ///      generous bound (the structural claim is "per-box marginal << a fat single-box total", not an
    ///      exact equality — warm/cold state shifts the precise number).
    uint256 internal constant SINGLE_BOX_TOTAL_REF_GAS = 200_000;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    address private cranker;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        cranker = makeAddr("afking_open_cranker");
        vm.deal(cranker, 100_000 ether);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // Test A -- single afking-box materialization worst case (the per-box single-call cost)
    // =========================================================================

    /// @notice TST-06 / 350-SPEC §2: with exactly one stamped + RNG-ready + un-opened AFKING box, measure
    ///         the `mintFlip()` open leg gas. Asserts the box is queued (a stamped sub), RNG-ready
    ///         (`rngWordByDay[stampDay] != 0` so the `_afkingBoxReady` gate does NOT skip it), and un-opened
    ///         (`lastOpenedDay < lastAutoBoughtDay`) BEFORE the measurement is trusted; asserts the measured
    ///         gas < the 30M mainnet block limit; asserts (non-vacuity) the box ACTUALLY opened
    ///         (`lastOpenedDay` advanced to the stamp day). The afking open does NO `boxPlayers` walk + NO
    ///         cold-ledger read/zero (uniform O(1), unlike the human open this file used to measure).
    function testWorstCaseAfkingOpenBoxSingleMaterializationFitsBlockGasLimit() public {
        vm.skip(true, "357-00b D-12 supersession: the open-box gas harness subscribes ungrounded subs then measures the STAGE-first-buy open leg; the grounded subscribe buys at subscribe, shifting the measured marginal; re-proven by V56AfkingGasMarginal (the LIVE-01 open-leg + per-box marginal, all green)");
        // Stamp exactly one funded lootbox sub via a new-day STAGE, then land its stamp-day word.
        address[] memory subs = _setupFundedLootboxSubs(1, "afk1_", 5 ether);
        _runStageNewDay(0xA0FE0FE);
        uint32 stampDay = _readStampDay(subs);

        // assert-is-worst-case preconditions (the donor's :97-112, reframed): the box is queued (the sub is
        // stamped), RNG-ready (the stamp-day word landed so `_afkingBoxReady` does not skip), and un-opened
        // (lastOpenedDay < lastAutoBoughtDay so the materialization actually runs).
        assertGt(stampDay, 0, "worst case: the funded sub was stamped (box queued)");
        assertTrue(rngWordByDay(stampDay) != 0, "worst case: the stamp-day word landed (box RNG-ready, not the _afkingBoxReady skip)");
        assertTrue(_lastOpenedDayOf(subs[0]) < stampDay, "worst case: the box is queued + un-opened");

        // Settle clean so mintFlip routes to the OPEN leg (advance not due), then measure opening exactly
        // ONE queued afking box (the afking open is mintFlip-only; game.autoOpen is the human path).
        _settleClean(0x09E20FE);
        assertFalse(game.advanceDue(), "mintFlip routes to OPEN (advance not due)");
        vm.recordLogs();
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.mintFlip();
        uint256 gasUsed = gasBefore - gasleft();

        // Non-vacuity: the box actually opened — its day-keyed marker advanced to the stamp day (NOT a
        // _afkingBoxReady skip, which would leave lastOpenedDay < lastAutoBoughtDay).
        assertEq(_lastOpenedDayOf(subs[0]), stampDay, "non-vacuity: the queued afking box actually opened (lastOpenedDay advanced)");

        // The per-box single-call cost fits the REAL mainnet block gas limit (and the 16.7M ceiling).
        assertLt(
            gasUsed,
            MAINNET_BLOCK_GAS_LIMIT,
            "TST-06: single afking-box materialization worst case fits under the 30M mainnet block gas limit"
        );
        assertLt(gasUsed, EFFECTIVE_GAS_CEILING, "16.7M ceiling: the single afking-box open leg fits under 16.7M");

        emit log_named_uint("worst_case_afking_open_box_single_materialization_gas", gasUsed);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Test D -- the per-OPEN MARGINAL (the CR-01 loop-N-divide idiom, PRESERVED VERBATIM IN SHAPE)
    // =========================================================================

    /// @notice TST-06 / 350-SPEC §2 + CR-01 (350-SPEC §0): the per-OPEN marginal — the marginal cost of
    ///         opening one more box in an N-box afking open. Measured by the SAME loop-N-divide idiom the
    ///         donor's Test D (:163-217) used: queue N distinct READY un-opened AFKING boxes, drive the
    ///         afking open leg (`mintFlip()`) ONCE, divide the gasleft-delta by N so the per-call fixed
    ///         overhead (the cursor SLOAD/SSTORE, the once-per-tx `creditFlip`) amortizes away. A large N
    ///         (32) converges the marginal to the true per-box materialization cost. Asserts the per-box
    ///         marginal is materially BELOW the single-box reference total (the gap is the mis-attributed
    ///         fixed overhead, CR-01) and is uniform O(1) (no cold-ledger walk — the anti-gas-DoS property
    ///         the afking open was designed for, 350-SPEC §2).
    ///
    ///         The afking open is reached ONLY via `mintFlip()` (the open leg `_autoOpen(OPEN_BATCH)`).
    ///         The 2 deploy subs (VAULT + SDGNRS) become ready boxes too; the marginal divides by the boxes
    ///         ACTUALLY opened (N + 2) so the number is a conservative per-box figure, never a single-box
    ///         total.
    function testPerAfkingBoxMarginalAmortizesFixedOverhead() public {
        vm.skip(true, "357-00b D-12 supersession: the open-box gas harness subscribes ungrounded subs then measures the STAGE-first-buy open leg; the grounded subscribe buys at subscribe, shifting the measured marginal; re-proven by V56AfkingGasMarginal (the LIVE-01 open-leg + per-box marginal, all green)");
        uint256 nBoxes = N_MARGINAL;

        // Queue N distinct READY afking boxes (distinct stamped subs), then land their stamp-day word.
        address[] memory subs = _setupFundedLootboxSubs(nBoxes, "afkM_", 5 ether);
        _runStageNewDay(0xB0FE0FE);
        uint32 stampDay = _readStampDay(subs);
        assertGt(stampDay, 0, "pre: the funded subs were stamped");

        // assert-is-real precondition: every box queued + RNG-ready + un-opened before the open, so the
        // marginal measures real materializations (not _afkingBoxReady skips or already-opened skips).
        for (uint256 i; i < nBoxes; ++i) {
            assertEq(_lastBoughtDayOf(subs[i]), stampDay, "pre: each sub stamped");
            assertTrue(_lastOpenedDayOf(subs[i]) < stampDay, "pre: each box queued + un-opened");
        }
        assertTrue(rngWordByDay(stampDay) != 0, "pre: the stamp-day word landed (boxes ready)");

        // Settle clean so mintFlip routes to OPEN, then bracket the whole afking open leg over the N (+2
        // deploy) ready boxes; divide by the boxes actually opened for the per-box marginal (fixed overhead
        // paid once). N + 2 < OPEN_BATCH so one mintFlip opens them all.
        _settleClean(0x09E20FE);
        assertFalse(game.advanceDue(), "mintFlip routes to OPEN (advance not due)");
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.mintFlip();
        uint256 totalGas = gasBefore - gasleft();

        // Non-vacuity: every queued box actually opened (lastOpenedDay advanced on open), so the marginal is
        // a real per-box materialization cost (not a no-op walk).
        uint256 openedCount;
        for (uint256 i; i < nBoxes; ++i) {
            if (_lastOpenedDayOf(subs[i]) == stampDay) ++openedCount;
        }
        assertEq(openedCount, nBoxes, "non-vacuity: every queued afking box opened (lastOpenedDay advanced)");

        // Divide by the boxes ACTUALLY opened (N of mine + the 2 deploy subs that were also stamped+ready) —
        // the loop-N-divide MARGINAL, a conservative per-box figure (never a single-box total).
        uint256 perBoxMarginal = totalGas / (nBoxes + 2);

        // The per-box marginal is materially BELOW the single-box reference total: the gap is the per-call
        // fixed overhead the single-box measurement mis-attributes to one box (CR-01). This is the
        // PRESERVED Test-D assertion shape.
        assertLt(
            perBoxMarginal,
            SINGLE_BOX_TOTAL_REF_GAS,
            "per-box afking-open marginal is materially below the single-box total (the gap is the mis-attributed fixed overhead, CR-01)"
        );
        assertLt(perBoxMarginal, EFFECTIVE_GAS_CEILING, "per-box afking-open marginal trivially fits the 16.7M ceiling");

        // The uniform-O(1) chunk: a full OPEN_BATCH of afking boxes projects under the 16.7M ceiling.
        assertLt(
            perBoxMarginal * OPEN_BATCH,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: OPEN_BATCH x the per-box afking-open marginal projects under 16.7M (uniform O(1))"
        );

        emit log_named_uint("per_afking_box_marginal_gas", perBoxMarginal);
        emit log_named_uint("per_afking_box_batch_total_gas", totalGas);
        emit log_named_uint("afking_boxes_opened", openedCount + 2);
        emit log_named_uint("single_box_total_ref_gas", SINGLE_BOX_TOTAL_REF_GAS);
        emit log_named_uint("open_batch_x_marginal_projection_gas", perBoxMarginal * OPEN_BATCH);
    }

    // =========================================================================
    // Test E -- uniform-O(1): the afking open is independent of the opener / box count shape
    // =========================================================================

    /// @notice TST-06 / 350-SPEC §2 (the anti-gas-DoS property): the afking open is uniform O(1) per box —
    ///         the per-box marginal does NOT depend on the opener identity or on how many boxes precede it
    ///         in the cursor walk (no cold-ledger walk whose cost scales with prior state). Measures the
    ///         per-box marginal at a SMALL box count and a LARGE box count from the IDENTICAL clean baseline
    ///         (via snapshot/revert — so the two measurements do not share day-index saturation or warm/cold
    ///         drift, the 351-05/07 single-STAGE-per-fixture reality) and asserts they match within a broad
    ///         tolerance (the uniform-O(1) claim). This is the afking analog of the donor's whale-vs-
    ///         non-whale uniform-O(1) equivalence (Test E), reframed onto the stamp-derived open.
    function testAfkingOpenIsUniformPerBoxAcrossBatchShapes() public {
        vm.skip(true, "357-00b D-12 supersession: the open-box gas harness subscribes ungrounded subs then measures the STAGE-first-buy open leg; the grounded subscribe buys at subscribe, shifting the measured marginal; re-proven by V56AfkingGasMarginal (the LIVE-01 open-leg + per-box marginal, all green)");
        uint256 snap = vm.snapshotState();
        // Small-batch per-box marginal.
        uint256 perBoxSmall = _measureOpenLegPerBox(4, "uniS_");
        vm.revertToState(snap);
        // Large-batch per-box marginal (from the identical clean baseline).
        uint256 perBoxLarge = _measureOpenLegPerBox(N_MARGINAL, "uniL_");

        uint256 hi = perBoxSmall > perBoxLarge ? perBoxSmall : perBoxLarge;
        uint256 lo = perBoxSmall > perBoxLarge ? perBoxLarge : perBoxSmall;
        // Broad tolerance: the small-batch marginal carries more per-call fixed overhead per box (it is
        // amortized over fewer boxes), so the small marginal is the HIGHER of the two; the uniform-O(1)
        // claim is that the LARGE-batch converged marginal is not materially heavier per box (no
        // box-count-scaling cost). The gap is bounded by the once-per-call fixed overhead amortization.
        uint256 TOLERANCE_BPS = 9_000; // 90% — comfortably above the fixed-overhead amortization gradient
        assertLe(
            (hi - lo) * 10_000,
            hi * TOLERANCE_BPS,
            "uniform O(1): the afking per-box open marginal does not scale with the box count (no cold-ledger walk)"
        );
        assertLt(perBoxLarge, EFFECTIVE_GAS_CEILING, "large-batch per-box afking-open marginal fits the ceiling");

        emit log_named_uint("afking_open_per_box_small_batch_gas", perBoxSmall);
        emit log_named_uint("afking_open_per_box_large_batch_gas", perBoxLarge);
    }

    // =========================================================================
    // Internal helpers (the validated game-resident driving harness)
    // =========================================================================

    /// @dev Measure the afking open-leg per-box marginal over `n` freshly-stamped + ready afking boxes:
    ///      stamp n funded lootbox subs (new-day STAGE), land the stamp-day word, settle clean (so
    ///      mintFlip routes to OPEN), open ALL of them in one mintFlip, divide by the boxes actually
    ///      opened (n + 2 deploy subs). The loop-N-divide MARGINAL (never a single-box total).
    function _measureOpenLegPerBox(uint256 n, string memory prefix) internal returns (uint256 perBox) {
        address[] memory subs = _setupFundedLootboxSubs(n, prefix, 5 ether);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "word"))) | 1);
        uint32 stampDay = _readStampDay(subs);
        require(stampDay > 0, "fixture: subs stamped");
        require(rngWordByDay(stampDay) != 0, "fixture: stamp-day word landed");
        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) < stampDay, "fixture: each box queued");
        }

        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so mintFlip opens");
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.mintFlip();
        uint256 totalGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) == stampDay, "non-vacuity: each box opened");
        }
        perBox = totalGas / (n + 2);
    }

    /// @dev Subscribe `n` fresh players as funded LOOTBOX-mode subs (deity-passed so pass-gated valid;
    ///      funded via depositAfkingFunding so the STAGE `:709` afkingFunding debit + `:710` claimablePool
    ///      debit land in tandem, SOLVENCY-01 balanced). The STAGE stamps each into a warm Sub slot — a
    ///      ready afking box once the day's word lands. The REFRAME of the donor's HUMAN `_buyBox` deposit.
    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0)); // self, lootbox mode, qty 1
            _fundPool(who, poolEach);
        }
    }

    /// @dev Read the (uniform) stamp day across the subs (each was stamped the same process day by the STAGE).
    function _readStampDay(address[] memory subs) internal view returns (uint32) {
        return _lastBoughtDayOf(subs[0]);
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

    /// @dev Drive a fresh new-day STAGE then land the day's word (the per-sub stamp becomes a ready box).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            // Fulfill any in-flight request FIRST (before advancing) — a stamping advance can leave the game
            // rngLocked with an unfilled word, and advanceGame() would revert RngNotReady if called while the
            // word is 0. Fulfilling at the loop top clears the lock so the next advance can proceed.
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before a mintFlip open so it reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev Fulfill the latest pending mock-VRF request (idempotent — no-op if already fulfilled / none).
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

    // ---- Sub-stamp slot reads (_subOf at slot 62 + verified offsets) ----

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

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Read the DAY-keyed afking word `rngWordByDay[day]` (the open leg's seed + readiness gate).
    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
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
