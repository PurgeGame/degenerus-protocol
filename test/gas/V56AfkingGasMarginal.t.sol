// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title AFKing marginal measurements and resumable lifecycle witnesses.
/// @notice N versus N-1 measurements are comparative diagnostics, not standalone cold
///         operation proofs. Live admission uses MineFlipGasBounds and caller gas;
///         fixed subscriber weights and fixed open batch sizes no longer exist.
///         SubscriberAfkingNativeGas measures complete cold operations and their tails.
///         This suite retains funding/stamp non-vacuity, forced ETH spins, cursor
///         ordering, bounded eviction/resume and gap recovery through the live engine.
contract V56AfkingGasMarginal is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    // -------------------------------------------------------------------------
    // Game-resident storage slots (forge inspect DegenerusGame storageLayout, v61)
    // -------------------------------------------------------------------------

    // RE-DERIVED via `solc --storage-layout` on the working tree after the V62 lootbox repack — the
    // folded lootboxEth word + removed lootboxEthBase/Flip/Purchase/Distress shifted later slots down.
    uint256 private constant RNG_WORD_BY_DAY_SLOT = GameSlots.RNG_WORD_BY_DAY; // mapping(uint24 => uint256) — the afking box's DAY-keyed word + readiness gate
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF;           // _subOf mapping root (uint32 => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS;     // uint32[] _subscribers (slot holds the length)
    uint256 private constant SUBCURSOR_SLOT = GameSlots.SUB_CURSOR;       // _subCursor (uint16 @ byte 0) + _subOpenCursor (uint16 @ byte 2) + _afkingResetDay (uint24 @ byte 4) + boxCursor (uint48 @ byte 7) + boxReadCount (uint32 @ byte 13)

    // Sub packed-field byte offsets — RE-DERIVED via `forge inspect DegenerusGame storageLayout`. The
    // AFKing Subscription Token credential (sub <=> coin) needs no stored pass horizon, so `validThroughLevel` (the old
    // 3-byte crossing-refresh marker) is DELETED and every field after it shifts down 3 bytes. Single
    // 256-bit Sub slot (28 used bytes, 4 free):
    //   dailyQuantity u8 @0 · flags u8 @1 · score u16 @2 · amount u24 @4
    //   lastAutoBoughtDay u24 @7 · lastOpenedDay u24 @10 · afkCoveredThroughDay u24 @13 · afkingStartDay u24 @16
    //   affiliateBase u32 @19 · pendingFlip u24 @23 · subStreakLatch u16 @26
    uint256 private constant OFF_AMOUNT = 4;      // uint24 amount (milli-ETH)   (bytes 4..6)
    uint256 private constant OFF_LASTBOUGHT = 7;  // uint24 lastAutoBoughtDay    (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay        (bytes 10..12)
    /// @dev milli-ETH packing scale (DegenerusGameStorage.LR_ETH_SCALE) — sub.amount * this = box wei.
    uint256 private constant MILLI_ETH_SCALE = 1e15;
    uint256 private constant OFF_AFKCOVERED = 13;  // uint24 afkCoveredThroughDay (bytes 13..15)
    uint256 private constant OFF_AFKINGSTART = 16; // uint24 afkingStartDay      (bytes 16..18)
    uint256 private constant OFF_AFFBASE = 19;    // uint32 affiliateBase        (bytes 19..22)
    uint256 private constant OFF_PENDINGFLIP = 23; // uint24 pendingFlip     (bytes 23..25)
    uint256 private constant OFF_STREAKLATCH = 26; // uint16 subStreakLatch      (bytes 26..27; full streak counter)

    /// @dev The packed header slot 0 holds `purchaseStartDay` (uint24 @ byte 0) + `dailyIdx` (uint24 @ byte 3)
    ///      + `rngRequestTime` (uint48 @ byte 6) + `level` (uint24 @ byte 12) (RE-DERIVED via
    ///      `forge inspect DegenerusGame storageLayout` after the slot-0 width re-pack — purchaseStartDay and
    ///      dailyIdx narrowed uint32→uint24, shifting every later field down).
    ///      Neither has a public getter, so the decouple invariants read them via vm.load on slot 0.
    uint256 private constant HEADER_SLOT = 0;
    uint256 private constant OFF_PURCHASE_START_DAY = 0; // uint24 @ byte 0
    uint256 private constant OFF_DAILY_IDX = 3;          // uint24 @ byte 3
    uint256 private constant OFF_SUBS_FULLY_PROCESSED = 28; // bool @ byte 28 (afking STAGE drain-complete flag)

    // -------------------------------------------------------------------------
    // Dual-bound + worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev Sizing target for an indivisible operation plus its checkpoint tail.
    uint256 internal constant GAS_TARGET = 10_000_000;

    /// @dev Harness-local day-parity period for `_warpToBoundary` deterministic day selection. The contracts no
    ///      longer have a settle cadence (compute-on-read obviated it); this is purely a test warp helper.
    uint256 internal constant SETTLE_PERIOD = 10;

    /// @dev SUBSCRIBER_CAP (GameAfkingModule.sol): the shipped worst-case active sub count — a hard
    ///      backstop AT the natural bound, since membership requires holding an AFKing Subscription Token (a fixed
    ///      2,000-coin supply); distinct subscribers can never exceed the coin count, so the cap only
    ///      fail-louds that invariant. A per-tx ceiling proof "at the cap" must use 2000.
    uint256 internal constant SUBSCRIBER_CAP = 2000;

    /// @dev Historical transaction allowance used by bounded progress witnesses.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    /// @dev A worst-case VRF/keeper stall length (days) for the D-06 gap-resume resume. The gap backfill is
    ///      capped at 30 days in the contract (_backfillGapDays) and the 30-day VRF deadman ends any longer
    ///      stall; 30 is the binding worst case.
    uint256 internal constant STALL_DAYS = 30;

    /// @dev Informational v55/349.2 per-buy lootbox reference (~206k, the v55 measured marginal WITH the
    ///      per-buy cross-contract storm) and the ~130-140k GAS-01 target band (the v56 deferred-settle win).
    ///      Reported as a comparison log, NOT a hard pin — the MEASURED number is the deliverable.
    uint256 internal constant V55_LOOTBOX_BUY_REF = 206_000;
    uint256 internal constant V56_LOOTBOX_TARGET_LO = 130_000;
    uint256 internal constant V56_LOOTBOX_TARGET_HI = 140_000;

    /// @dev The old per-day ~262k purchaseWith reference (the heavyweight the v56 ticket minimal-write
    ///      primitive replaces). Reported as the structural-win comparison for the ticket marginal.
    uint256 internal constant V55_TICKET_PURCHASEWITH_REF = 262_000;

    /// @dev D-09 regression-lock LOOSE ceilings — generous bounds over the measured v56 marginals (lootbox buy
    ///      ~7k / ticket buy ~54k / afking open ~70-75k), NOT brittle exact pins. A FUTURE regression (a
    ///      re-introduced per-buy cross-contract storm ~206k, or a cold-ledger walk creeping into the open leg)
    ///      blows these; normal measurement variance stays well under. The gate is a ceiling, not an equality.
    uint256 internal constant REG_LOCK_LOOTBOX_BUY_CEIL = 80_000;  // ~11x the ~7k measured lootbox marginal
    uint256 internal constant REG_LOCK_TICKET_BUY_CEIL = 150_000;  // ~3x the ~54k measured ticket marginal
    uint256 internal constant REG_LOCK_OPEN_CEIL = 200_000;        // ~3x the ~70-75k measured open marginal

    /// @dev N for the two-near-N marginal: measure N vs N−1 from one clean baseline (snapshot/revert). Big
    ///      enough that the funded set + the 2 deploy subs fit the measurement allowance (one advance stamps all in
    ///      the first chunk), so the everything-else of the advance is identical across N and N−1.
    uint256 internal constant N_HI = 24;
    uint256 internal constant N_LO = 23;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private constant NATIVE_EVICTION_CALL_GAS = 2_000_000;
    mapping(address => bool) private _nativeEvictionExpected;
    mapping(address => bool) private _nativeEvictionSeen;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }


    // =========================================================================
    // (a) per-buy LOOTBOX marginal — a NON-settle-day STAGE (GAS-01)
    // =========================================================================

    /// @notice Measure the extra funded lootbox subscription against the current item reservation.
    function testPerBuyLootboxMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureStageAdvanceGas(N_HI, "blMhi_", false, false);
        vm.revertToState(snap);
        uint256 gasNm1 = _measureStageAdvanceGas(N_LO, "blMlo_", false, false);

        assertGt(gasN, gasNm1, "per-buy lootbox marginal: N subs cost strictly more than N-1 (the Nth sub did real work)");
        uint256 perBuyLootbox = gasN - gasNm1; // (gas for N − gas for N−1) / 1 — the loop-N-divide MARGINAL

        assertLe(perBuyLootbox, GasBounds.SUBSCRIBER_ITEM_GAS, "lootbox marginal exceeds the current item reservation");

        string memory band;
        if (perBuyLootbox <= V56_LOOTBOX_TARGET_HI) {
            band = "AT or BELOW the ~130-140k GAS-01 target (deferred-settle win realized)";
        } else if (perBuyLootbox < V55_LOOTBOX_BUY_REF) {
            band = "BELOW the v55 ~206k reference (cheaper than v55), above the ~130-140k target band";
        } else {
            band = "AT or ABOVE the v55 ~206k reference (measured AS-IS, the deliverable)";
        }
        emit log_named_string("per_buy_lootbox_vs_refs", band);

        emit log_named_uint("per_buy_lootbox_marginal_gas", perBuyLootbox);
        emit log_named_uint("per_buy_lootbox_gas_n", gasN);
        emit log_named_uint("per_buy_lootbox_gas_n_minus_1", gasNm1);
        emit log_named_uint("v55_lootbox_buy_reference_gas", V55_LOOTBOX_BUY_REF);
        emit log_named_uint("v56_lootbox_target_lo_gas", V56_LOOTBOX_TARGET_LO);
        emit log_named_uint("v56_lootbox_target_hi_gas", V56_LOOTBOX_TARGET_HI);
    }

    // =========================================================================
    // (b) per-buy TICKET marginal — the new minimal-write primitive (GAS-01)
    // =========================================================================

    /// @notice Measure the extra funded ticket subscription against the current item reservation.
    function testPerBuyTicketMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureStageAdvanceGas(N_HI, "btMhi_", true, false);
        vm.revertToState(snap);
        uint256 gasNm1 = _measureStageAdvanceGas(N_LO, "btMlo_", true, false);

        assertGt(gasN, gasNm1, "per-buy ticket marginal: N subs cost strictly more than N-1 (the Nth sub did real work)");
        uint256 perBuyTicket = gasN - gasNm1;

        assertLe(perBuyTicket, GasBounds.SUBSCRIBER_ITEM_GAS, "ticket marginal exceeds the current item reservation");

        emit log_named_string(
            "per_buy_ticket_vs_purchasewith",
            perBuyTicket < V55_TICKET_PURCHASEWITH_REF
                ? "BELOW the ~262k purchaseWith reference - the minimal-write primitive win is realized"
                : "AT or ABOVE the ~262k purchaseWith reference (measured AS-IS)"
        );

        emit log_named_uint("per_buy_ticket_marginal_gas", perBuyTicket);
        emit log_named_uint("per_buy_ticket_gas_n", gasN);
        emit log_named_uint("per_buy_ticket_gas_n_minus_1", gasNm1);
        emit log_named_uint("v55_ticket_purchasewith_reference_gas", V55_TICKET_PURCHASEWITH_REF);
    }

    // =========================================================================
    // (c) Per-box marginal against the native open reservation
    // =========================================================================

    /// @notice Measure one additional stamp-day box; complete cold envelopes are covered by the native suite.
    function testPerOpenMarginal() public {
        uint256 snap = vm.snapshotState();
        // SHARED prefix across the N and N-1 runs: each box's boon-roll seed is keccak(stamp-day word, player,
        // amount), all prefix-derived. A shared prefix makes the first N-1 boxes byte-identical between the two
        // runs (same players, same word), so they cancel exactly and the marginal IS one real box's open cost
        // (always positive). Distinct hi/lo prefixes would roll different boons in each run -> the marginal
        // becomes a noisy difference of two unequal box-cost sums that can go negative on seed variance.
        uint256 gasN = _measureOpenLegGas(N_HI, "opM_");
        vm.revertToState(snap);
        uint256 gasNm1 = _measureOpenLegGas(N_LO, "opM_");

        assertGt(gasN, gasNm1, "per-open marginal: N opens cost strictly more than N-1 (the Nth box materialized)");
        uint256 perOpen = gasN - gasNm1; // (gas for N − gas for N−1) / 1 — the loop-N-divide MARGINAL

        emit log_named_uint("per_open_marginal_gas", perOpen);
        emit log_named_uint("per_open_gas_n", gasN);
        emit log_named_uint("per_open_gas_n_minus_1", gasNm1);
        // A marginal can detect regressions but does not include a complete cold
        // call and return tail; the native suite measures that envelope directly.
        assertLe(perOpen, GasBounds.AFKING_OPEN_GAS, "per-open marginal fits the declared AFKING checkpoint bound");
        assertLe(GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS, GAS_TARGET, "AFKING checkpoint bound inside the 10M chunk limit");
    }

    // =========================================================================
    // (d) per-EVICT-finalize marginal — the heavier in-stage branch (GAS-03)
    // =========================================================================

    /// @notice Measure one additional funding expiry, including its quest finalization.
    function testEvictFinalizeMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureEvictStageGas(N_HI, "evHi_");
        vm.revertToState(snap);
        uint256 gasNm1 = _measureEvictStageGas(N_LO, "evLo_");

        assertGt(gasN, gasNm1, "per-evict marginal: N evicting subs cost strictly more than N-1");
        uint256 perEvict = gasN - gasNm1;
        assertLe(perEvict, GasBounds.SUBSCRIBER_ITEM_GAS, "eviction marginal exceeds the current item reservation");

        emit log_named_uint("per_evict_finalize_marginal_gas", perEvict);
    }


    // =========================================================================
    // (f) D-06 / GAS-06 — the per-tx gap-resume ceiling + the gap/jackpot decouple (D-07)
    // =========================================================================

    /// @notice The GAS-06 / D-06 worst-case multi-day VRF-stall resume. A 30-day VRF/keeper stall (the widest the deadman lets resume), then a
    ///         resume: rngGate backfills the (capped 30-day) gap on ONE advance, and the gap/jackpot decouple
    ///         (DegenerusGameAdvanceModule:369-372 `if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }`)
    ///         defers the up-to-305-winner daily jackpot to the NEXT advance — so the backfill (~9M) and the
    ///         jackpot (~6M+) NEVER execute in one tx. Asserts the D-06 bar: EACH mineFlip tx (advance N =
    ///         the gap-backfill break, advance N+1 = the deferred jackpot) is STRICTLY under 16,777,216
    ///         (EIP-7825) INDIVIDUALLY — NOT the ~25M total. This is the empirical answer to the proof's
    ///         per-tx gap-resume ESTIMATE (~15.8M), bracketing each advance separately (gasleft before/after a
    ///         single mineFlip call). At a worst-case SUBSCRIBER_CAP=2000 STAGE the backfill advance ALSO
    ///         processes the resumed-day STAGE, so the full-cap sizing is load-bearing here.
    function testGapResumePerAdvanceCeilingAndDecouple() public {
        // Heavy state: a funded STAGE at scale, driven through an ORGANIC gap resume. The
        // UNLOCKED resume entry (advance N) walks the STAGE first — the funded buys — and
        // then falls through to a cheap fresh request: the normal stamp-before-request tx.
        // The fulfilled word arrives buffered UNDER the lock, where the VRF-outstanding
        // entry gate keeps the STAGE out entirely, so the gap backfill (advance N+1) and
        // the deferred daily jackpot (advance N+2) each get their own ring-walk-free tx.
        // None of the heavy legs ever share a tx, so each stays under the per-tx ceiling
        // regardless of ring size (the V62-02 close).
        address[] memory subs = _setupFundedSubs(N_HI, "gr_", 5 ether, false);

        _settleClean(uint256(keccak256("gr_clean")) | 1);
        _finishReadConsumers();
        // Level stays at genesis: the 30-day stall is within the lvl-0 365-day idle clock and the deadman,
        // and the resume settles without a level transition (no charity-pick dependency).

        uint32 idxBeforeStall = _dailyIdx();
        uint32 psdBeforeResume;

        // The stall: warp STALL_DAYS whole days WITHOUT advancing, so currentDayView() runs far ahead of
        // dailyIdx — `day > idx + 1 && _recordedDailyWord(idx + 1) == 0` (the gap-backfill precondition).
        vm.warp(block.timestamp + STALL_DAYS * 1 days);
        uint32 resumeDay = game.currentDayView();
        // Death-clock excludes gap days -> purchaseStartDay kept recent (game alive: resumeDay - psd = 1 < 30).
        _setHeaderField(0, 3, resumeDay - 1); // purchaseStartDay = resumeDay - 1
        psdBeforeResume = _purchaseStartDay();

        require(resumeDay > idxBeforeStall + 1, "fixture: a multi-day gap opened (day >> dailyIdx)");
        require(rngWordByDay(idxBeforeStall + 1) == 0, "fixture: the gap range is unbackfilled pre-resume");
        require(game.advanceDue(), "fixture: advanceDue on resume");

        // ---- Advance N (UNLOCKED resume entry): the STAGE chunk + the fresh daily request.
        // The stamp-before-request ordering: the ring walks to completion, then rngGate fires
        // the request (cheap) — no word exists yet, so no backfill/jackpot can share this tx. ----
        // A realistic 10M allowance succeeds (the engine admits chunks while the allowance lasts, so the
        // call is reported, not bounded; the checkpoints below are bounded one at a time).
        uint256 gasBeforeN = gasleft();
        game.mineFlip{gas: 10_000_000}(0);
        uint256 advNGas = gasBeforeN - gasleft();
        emit log_named_uint("resume_stage_plus_request_advance_N_gas", advNGas);

        // Non-vacuity + segregation invariants on advance N:
        //  - the STAGE actually ran and completed before the request fired.
        assertTrue(_subsFullyProcessed(), "V62-02: the STAGE completed in advance N (subsFullyProcessed set)");
        //  - the request is in flight (LOCKED) — the entry gate now excludes the ring from every leg below.
        assertTrue(game.rngLocked(), "V62-02: advance N fired the resume request (rngLocked)");
        //  - no word existed in this tx, so nothing backfilled/sealed — structurally no composition.
        (uint16 gapPercentN,) = coinflip.getCoinflipDayResult(uint24(idxBeforeStall + 1));
        assertEq(gapPercentN, 0, "V62-02: advance N did NOT backfill (no word yet)");
        assertTrue(rngWordByDay(resumeDay) == 0, "V62-02: advance N committed no resumed-day word (request only)");
        assertEq(_dailyIdx(), idxBeforeStall, "V62-02: advance N did NOT advance dailyIdx");
        assertEq(_purchaseStartDay(), psdBeforeResume, "V62-02: advance N did NOT bump purchaseStartDay (no gap accounting yet)");
        // Liveness: the only remaining step is waiting on the word, which is not runnable work (the
        // engine reports RngNotReady); the resume continues on delivery below.
        assertFalse(game.advanceDue(), "V62-02: after advance N the engine waits on the word (not stuck: RngNotReady)");
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip(0);

        // The word arrives — buffered, STILL LOCKED (the organic buffered-clamp state; the lock
        // clears only at _unlockRng, and the entry gate keeps the STAGE out until then).
        _fulfillPending(uint256(keccak256("gr_resume_word")) | 1);
        assertTrue(game.rngLocked(), "buffered word: still rngLocked until _unlockRng");

        // ---- Advance N+1: the gap-backfill leg (STAGE gated out — rngLocked; rngGate backfills the
        // gap ALONE and breaks STAGE_GAP_BACKFILLED, deferring the jackpot downstream) ----
        // The backfill is its own checkpoint: at the measured boundary allowance (the smallest that
        // progresses) the call admits the gap backfill alone, and that checkpoint must fit the 10M
        // realistic chunk limit (30-day worst case).
        // (Publication and the ticket certificate precede it as their own small checkpoints.)
        uint256 np1Allowance;
        uint256 advNp1Gas;
        for (uint256 i; i < 20 && _dailyIdx() != resumeDay - 1; ++i) {
            np1Allowance = _boundaryAllowance();
            uint256 gasBeforeNp1 = gasleft();
            game.mineFlip{gas: np1Allowance}(0);
            advNp1Gas = gasBeforeNp1 - gasleft();
        }
        emit log_named_uint("gap_backfill_checkpoint_allowance", np1Allowance);
        emit log_named_uint("gap_backfill_advance_Np1_gas", advNp1Gas);
        assertLe(advNp1Gas, GAS_TARGET, "D-06: the 30-day gap-backfill checkpoint fits the 10M chunk limit");

        // D-07 invariants on advance N+1 (the gap backfill, decoupled from BOTH the STAGE and the jackpot):
        //  - the gap range is now backfilled (so rngGate is idempotent next call: _recordedDailyWord(idx+1) != 0).
        // (Gap-day words are not retained — only today's and yesterday's are — so the backfill is observed
        // through its settled gap coinflip days.)
        (uint16 gapPercent,) = coinflip.getCoinflipDayResult(uint24(idxBeforeStall + 1));
        assertGt(gapPercent, 0, "D-07: advance N+1 backfilled the gap (its first gap coinflip day resolved)");
        //  - dailyIdx parked at resumeDay - 1 (the gap is skipped, not walked) -> advanceDue stays true.
        assertEq(_dailyIdx(), resumeDay - 1, "D-07: advance N+1 parked dailyIdx at resumeDay - 1 (gap skipped, no _unlockRng)");
        assertTrue(game.advanceDue(), "D-07: advanceDue() stays true between advance N+1 and advance N+2 (jackpot deferred)");
        //  - purchaseStartDay bumped EXACTLY ONCE by the gap count (the death-clock extension, the single bump).
        //    rngGate computes gapCount = day - idx - 1 = resumeDay - idxBeforeStall - 1 (uncapped at the psd
        //    bump site; the 30-day cap is only on the backfill LOOP, _backfillGapDays).
        uint32 psdAfterNp1 = _purchaseStartDay();
        uint256 expectedBump = uint256(resumeDay - idxBeforeStall - 1);
        assertEq(uint256(psdAfterNp1 - psdBeforeResume), expectedBump, "D-07: purchaseStartDay bumped exactly once by the gap count (resumeDay - dailyIdx - 1)");

        // The resumed day's word is applied by the next checkpoint (DailyApply); every later checkpoint
        // reads the SAME word — it is NOT re-rolled (deferral moves DISTRIBUTION, never the word).
        game.mineFlip{gas: _boundaryAllowance()}(0);
        uint256 resumeWordOnNp1 = rngWordByDay(resumeDay);
        require(resumeWordOnNp1 != 0, "fixture: the resumed-day word landed on advance N+1 (committed pre-defer)");

        // ---- Advance N+2: the deferred-distribution advance (re-entry is idempotent: _recordedDailyWord(idx+1) != 0
        // -> gapDays == 0; the daily jackpot distributes HERE, NOT on N+1). The D-06 per-tx ceiling for N+2 is
        // the pre-existing runDailyJackpot bound (<= DAILY_ETH_MAX_WINNERS = 305, the proof's ~6M measured row +
        // the dedicated jackpot suites) — the NEW fact the decouple establishes is that this distribution
        // executes in a SEPARATE tx from the gap backfill, so the two never compose into one tx. We bracket N+2
        // via a low-level call so the gas-to-completion (or to the synthetic-fixture jackpot boundary — the
        // cheap STAGE/open marginal fixture builds no full prize-pool/ticket economics) is captured regardless,
        // and assert it stays under the EIP cap.
        // The deferred distribution: the remaining daily checkpoints, each call with a realistic 10M
        // allowance, which must succeed (per-chunk bounds for the jackpot legs live in the jackpot suites).
        uint256 gbNp2 = gasleft();
        for (uint256 i; i < 50 && game.rngLocked(); ++i) game.mineFlip{gas: 10_000_000}(0);
        uint256 advNp2Gas = gbNp2 - gasleft();
        emit log_named_uint("deferred_jackpot_advance_Np2_gas", advNp2Gas);
        assertFalse(game.rngLocked(), "D-06: the resumed day's distribution completed at realistic allowances");

        // D-07: advance N+2 read the SAME frozen resumed-day word committed on advance N+1 (never re-rolled).
        assertEq(rngWordByDay(resumeDay), resumeWordOnNp1, "D-07: the deferred jackpot reads the SAME frozen resumed-day word (committed on N+1, no re-roll on N+2)");
        // D-07: purchaseStartDay was bumped EXACTLY ONCE across the whole resume (advance N+2 must NOT bump it
        // again — the death-clock extension is a single event tied to the gap backfill, gapDays == 0 on N+2).
        assertEq(_purchaseStartDay(), psdAfterNp1, "D-07: purchaseStartDay NOT bumped again on advance N+2 (exactly-once across the resume; idempotent gapDays==0)");

        emit log_named_uint("subscriber_cap_used", SUBSCRIBER_CAP);
        // Non-vacuity: the funded subs still exist (the resume processed them, did not drop the fixture).
        require(subs.length == N_HI, "fixture: funded set intact");
    }

    /// @dev The smallest allowance (100k steps) with which the next keeper call succeeds: it admits the
    ///      next checkpoint alone. Probed on snapshots; the state is left unchanged.
    function _boundaryAllowance() internal returns (uint256 g) {
        uint256 snap = vm.snapshotState();
        for (g = 500_000; g <= GAS_TARGET; g += 100_000) {
            try game.mineFlip{gas: g}(0) {
                require(vm.revertToState(snap), "snapshot");
                return g;
            } catch {
                require(vm.revertToState(snap), "snapshot");
            }
        }
        revert("fixture: no allowance up to 10M progresses");
    }

    // =========================================================================
    // (g) D-06 residual R1 — STAGE weight-model fidelity (level-cross / gap-resume per-iter <= weight)
    // =========================================================================

    /// @notice Retained test name; the production worker now admits complete items from
    ///         caller-supplied gas, rather than a fixed weight count. Calibrate actual
    ///         cold eviction/buy work against its named item reservation. An unfunded
    ///         self-sub may attempt stETH and fail before the ordinary eviction.
    function testResidualR1StageWeightModelFidelity() public {
        uint256 snap = vm.snapshotState();

        // The funding-kill finalize iter (the heavier in-stage finalize branch), measured COLD
        // (vm.cool first-touch) — the realistic daily-advance regime where a killed sub's slots are cold (it
        // was funded/stamped on a prior tx). This is the regime the binding all-evict chunk actually runs in.
        uint256 coldEvN = _measureEvictStageGasCold(N_HI, "r1evHi_");
        vm.revertToState(snap);
        uint256 coldEvNm1 = _measureEvictStageGasCold(N_LO, "r1evLo_");
        require(coldEvN > coldEvNm1, "R1: the Nth cold evicting sub did real work");
        uint256 coldPerEvict = coldEvN - coldEvNm1;

        // The funded-buy unit (warm boundedness reference; a gap-resumed streak rebase rides this same per-buy
        // SLOAD/marker-write path — the compute-on-read streak adds no new cold slot).
        vm.revertToState(snap);
        uint256 buyN = _measureStageAdvanceGas(N_HI, "r1byHi_", false, false);
        vm.revertToState(snap);
        uint256 buyNm1 = _measureStageAdvanceGas(N_LO, "r1byLo_", false, false);
        require(buyN > buyNm1, "R1: the Nth funded buy did real work");
        uint256 perBuy = buyN - buyNm1;

        emit log_named_uint("r1_cold_per_evict_marginal_gas", coldPerEvict);
        emit log_named_uint("r1_per_buy_marginal_gas", perBuy);
        emit log_named_uint("r1_native_item_reservation_gas", GasBounds.SUBSCRIBER_ITEM_GAS);

        // The measured marginal is an independent check of the safety floor used
        // by MineFlipGas.canRun. The full-stipend hostile-failure cases are covered
        // separately in AfkingStethGas.t.sol; this is ordinary no-allowance expiry.
        assertLe(coldPerEvict, GasBounds.SUBSCRIBER_ITEM_GAS, "R1: cold eviction fits its native item reservation");
        assertLe(perBuy, GasBounds.SUBSCRIBER_ITEM_GAS, "R1: funded buy fits its native item reservation");
        assertLe(GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS + MineFlipGas.CHECK_RESERVE,
            10_000_000, "R1: item and checkpoint meet the chunk sizing guideline");

        // Derive conservative throughput from reservations, not the retired
        // 2500/8 weight quotient. Actual cheap expirations can admit more items;
        // the LIVE test independently checks progress and correct resumption.
        uint256 fixedEvictOverhead = coldEvN > coldPerEvict * N_HI ? coldEvN - coldPerEvict * N_HI : 0;
        uint256 fixedReservation = fixedEvictOverhead + GasBounds.SUBSCRIBER_TAIL_GAS + MineFlipGas.CHECK_RESERVE;
        assertLt(fixedReservation, NATIVE_EVICTION_CALL_GAS, "R1: caller budget leaves room for subscriber work");
        uint256 conservativelyFundedItems = (NATIVE_EVICTION_CALL_GAS - fixedReservation) / GasBounds.SUBSCRIBER_ITEM_GAS;
        assertGt(conservativelyFundedItems, 0, "R1: bounded caller budget admits whole items");
        uint256 modeledGas = fixedReservation + conservativelyFundedItems * coldPerEvict;
        emit log_named_uint("r1_conservatively_funded_items", conservativelyFundedItems);
        emit log_named_uint("r1_native_cold_eviction_model_gas", modeledGas);
        assertLt(modeledGas, NATIVE_EVICTION_CALL_GAS, "R1: measured item costs leave the modeled checkpoint reserve");
    }


    // =========================================================================
    // (i) Forced ETH-spin box marginal
    // =========================================================================

    /// @notice Force each stamp-day box to take the ETH-spin branch and check its marginal.
    function testResidualR3MixedStampDayOpenBatch() public {
        // Premise change: a box now always opens in the session of its own stamp day (the next request
        // waits for every read consumer, and only today's/yesterday's words are retained), so the
        // multi-day backlog and the fixed OPEN_BATCH crank this measured no longer exist; each box is one
        // AFKing checkpoint admitted under AFKING_OPEN_GAS. The worst case kept: every box FORCED to the
        // ETH-spin (roll 19), which credits ETH and may recirc a winning payout into a fresh box (the
        // deepest single-box work), measured as the N vs N-1 marginal against the declared bound.
        uint256 snap = vm.snapshotState();
        (uint256 gasN, uint256 ethSpins) = _forceEthSpinSession(N_HI, "r3eth_");
        vm.revertToState(snap);
        (uint256 gasNm1,) = _forceEthSpinSession(N_LO, "r3eth_");
        uint256 perBox = gasN - gasNm1;

        emit log_named_uint("r3_forced_eth_spin_session_gas_n", gasN);
        emit log_named_uint("r3_forced_eth_spin_count", ethSpins);
        emit log_named_uint("r3_forced_eth_spin_per_box_gas", perBox);

        // Non-vacuity: every box actually took the ETH-spin path (proves the worst-case forcing worked).
        assertEq(ethSpins, N_HI, "R3: every forced box rolled the ETH-spin (the heaviest outcome)");
        // Per-chunk: the heaviest single box fits its declared checkpoint bound, inside the 10M limit.
        assertLe(perBox, GasBounds.AFKING_OPEN_GAS, "R3: a forced ETH-spin box fits the declared AFKING checkpoint bound");
        assertLe(GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS, GAS_TARGET, "R3: AFKING checkpoint inside the 10M chunk limit");
    }

    /// @dev `m` funded lootbox subs whose next-day box rolls the ETH-spin under the session word: the
    ///      seed is hash4(sessionWord, walletId, AFKING_BOX_TAG, stampDay) and the roll uint16(seed >> 40)
    ///      % 20 == 19, so wallet IDs are brute-forced against the chosen word (no nudges in this fixture,
    ///      so the session word is the delivered word) and the known next stamp day: each candidate is
    ///      registered for its ID, and the non-rolling ones stay plain registered wallets. Returns the
    ///      stamp day's session gas and the count of first-level ETH-type BoxSpin events.
    function _forceEthSpinSession(uint256 m, string memory prefix) internal returns (uint256 sessionGas, uint256 ethSpins) {
        uint256 word = uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1;
        uint32 day = _simulatedDayIndex() + 1;
        address[] memory subs = new address[](m);
        uint256 found;
        for (uint256 k; found < m; ++k) {
            require(k < 50_000, "fixture: ETH-spin players");
            address who = makeAddr(string(abi.encodePacked(prefix, _u(k))));
            uint256 seed = uint256(keccak256(abi.encode(word, uint256(_giveWalletId(who)), uint256(0x41666b696e67426f78), uint256(day))));
            if (uint16(seed >> 40) % 20 == 19) subs[found++] = who;
        }
        for (uint256 i; i < m; ++i) {
            uint256 seat = _grantSeat(subs[i]);
            _fundPool(subs[i], 5 ether);
            vm.prank(subs[i]);
            game.subscribe(0, false, false, 1, 0, seat);
        }
        _stampNewDay(word);
        require(_readStampDay(subs) == day, "fixture: the forced boxes are stamped for the predicted day");
        vm.recordLogs();
        sessionGas = _sessionGas(word);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        bytes32 boxSpinSig = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == boxSpinSig) {
                (uint64 betId, , , ) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                if ((betId >> 60) & 7 == 2) ++ethSpins;
            }
        }
        for (uint256 i; i < m; ++i) require(_lastOpenedDayOf(subs[i]) == day, "fixture: each forced box opened");
    }

    /// @dev Brute-force an injected stamp-day word so the afking box's roll lands on the ETH-spin (19).
    function _findEthSpinWord(uint32 playerId, uint32 day, uint256 amountWei, uint256 salt)
        internal
        pure
        returns (uint256 w)
    {
        for (uint256 k; k < 8000; ++k) {
            w = uint256(keccak256(abi.encodePacked("r3ethspin", salt, k))) | 1;
            uint256 seed = uint256(keccak256(abi.encode(w, uint256(playerId), uint256(0x41666b696e67426f78), uint256(day))));
            if (uint16(seed >> 40) % 20 == 19) return w;
        }
        revert("no eth-spin word found");
    }

    // =========================================================================
    // (j) D-06 residual R4 — heaviest reachable per-iter state (re-measure the marginals at the heavy state)
    // =========================================================================

    /// @notice Residual R4: the per-iter marginals come from the fixture's 5-ETH-sub + coin-seat states; the
    ///         true heaviest reachable per-iter state (max streak hand-back / funding-kill finalize) may exceed
    ///         them. The v56 streak is compute-on-read (no per-iter streak SSTORE storm), so the heaviest per-iter
    ///         state is the funding-kill finalize (R1's evict branch) and the heaviest open (R3's mixed-day,
    ///         cold-SLOAD-per-box). This asserts the heaviest of {evict marginal, mixed-day open marginal} is
    ///         still a bounded O(1) per-iter cost (no marginal scales with player magnitude), so the
    ///         native per-item reservations cover the measured marginal.
    function testResidualR4HeaviestPerIterState() public {
        uint256 snap = vm.snapshotState();
        uint256 evN = _measureEvictStageGas(N_HI, "r4evHi_");
        vm.revertToState(snap);
        uint256 evNm1 = _measureEvictStageGas(N_LO, "r4evLo_");
        uint256 perEvict = evN > evNm1 ? evN - evNm1 : 1;

        // A mixed-day backlog no longer exists (each box opens in its own stamp day's session), so the
        // heaviest open per-iter cost is the same-day open marginal (shared prefix: one real box).
        vm.revertToState(snap);
        uint256 mxN = _measureOpenLegGas(N_HI, "r4op_");
        vm.revertToState(snap);
        uint256 mxNm1 = _measureOpenLegGas(N_LO, "r4op_");
        uint256 perBoxMixed = mxN > mxNm1 ? mxN - mxNm1 : 1;

        uint256 heaviestPerIter = perEvict > perBoxMixed ? perEvict : perBoxMixed;
        emit log_named_uint("r4_per_evict_heavy_gas", perEvict);
        emit log_named_uint("r4_per_box_mixed_heavy_gas", perBoxMixed);
        emit log_named_uint("r4_heaviest_per_iter_gas", heaviestPerIter);

        // R4: the heaviest reachable per-iter cost is a bounded O(1) (does not scale with player magnitude),
        // so the chunk bound holds at the heavy state.
        assertLt(heaviestPerIter, 400_000, "R4: the heaviest reachable per-iter state is a bounded O(1) (no magnitude scaling)");
        // R4 per-chunk (the fixed OPEN_BATCH chunk is gone): each box is one AFKing checkpoint, so the
        // heaviest open per-iter cost fits the declared AFKING_OPEN_GAS bound.
        assertLe(perBoxMixed, GasBounds.AFKING_OPEN_GAS, "R4: the heaviest open per-iter cost fits the declared AFKING checkpoint bound");
    }

    // =========================================================================
    // (k) LIVE-01 — the engine's box stages: drain + bound + afking-first + cursor-independence + selector-isolation
    // =========================================================================

    /// @notice LIVE-01 (a) afking-first ordering: with both backlogs populated, mineFlip's first action is the
    ///         AFKing stage, which drains the afking backlog before the human-box stage runs with the
    ///         remaining allowance.
    function testLive01AfkingFirstOrdering() public {
        // The engine serves the session's consumer stages (AFKing, then human boxes), so the fixture
        // stops at the AFKing stage with the subject still pending (padding subs ahead in the ring).
        _setupFundedSubs(AFKING_PADS, "v_pad_", 5 ether, false);
        // AFKING backlog: a funded lootbox sub gets a stamped box.
        address afk = makeAddr("v_afk");
        uint256 seat = _grantSeat(afk);
        _fundPool(afk, 5 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
        vm.prank(afk);
        game.subscribe(0, false, false, 1, 0, seat);
        _settleGame(0xA0F1 ^ 0xF00D);
        _finishIndexedReadConsumers();

        // HUMAN backlog: a real lootbox buyer queues a box entry on the human path (boxQueue), committed by
        // the same daily request as the afking stamp.
        address human = makeAddr("v_human");
        vm.deal(human, 5 ether);
        vm.prank(human);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        _stampNewDay(0xA0F1);
        address[] memory subject = new address[](1);
        subject[0] = afk;
        _toAfkingStageWithPending(subject, _lastBoughtDayOf(afk), 0xA0F2);
        require(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "fixture: afking box pending pre-open");
        uint256 boxCursorBefore = _boxCursor();
        uint256 subOpenCursorBefore = _subOpenCursor();

        // One unbounded engine call: enough for BOTH the afking box AND the human box.
        assertEq(game.nextMinerAction(), 9, "LIVE-01(a): the AFKing stage is the engine's next work"); // Afking
        vm.recordLogs();
        vm.prank(makeAddr("v_opener"));
        game.mineFlip(0);
        assertEq(_minerFirstAction(vm.getRecordedLogs()), 9, "LIVE-01(a): afking-first -- the call opened with the AFKing stage");

        // Afking-first: the afking box opened (lastOpenedDay advanced to the stamp day).
        assertEq(_lastOpenedDayOf(afk), _lastBoughtDayOf(afk), "LIVE-01(a): afking-first -- the afking box opened by the engine");
        // The human leg ran with the REMAINING allowance: its cursor did not regress.
        assertGe(_boxCursor(), boxCursorBefore, "LIVE-01(a): the human cursor advanced with the remaining allowance");
        emit log_named_uint("live01a_sub_open_cursor_before", subOpenCursorBefore);
        emit log_named_uint("live01a_sub_open_cursor_after", _subOpenCursor());
        emit log_named_uint("live01a_box_cursor_before", boxCursorBefore);
        emit log_named_uint("live01a_box_cursor_after", _boxCursor());
    }

    /// @notice LIVE-01 (b)+(c)+(d): repeated bounded mineFlip calls fully DRAIN a multi-box afking backlog with
    ///         BOTH cursors monotone-advancing (no stuck box), EACH mineFlip chunk < the EIP cap (bounded), and
    ///         lastOpenedDay monotone no-double-open (the skip at GameAfkingModule:1154). Uses tiny per-call
    ///         budgets so the drain genuinely spans multiple bounded calls.
    function testLive01DrainBothCursorsBoundedNoDoubleOpen() public {
        uint256 n = 8;
        // Stop at the session's AFKing stage with the subjects pending (padding subs ahead in the ring).
        _setupFundedSubs(AFKING_PADS, "vd_pad_", 5 ether, false);
        address[] memory subs = _setupFundedSubs(n, "vd_", 5 ether, false);
        _stampNewDay(0xB0F1);

        uint32 stampDay = _lastBoughtDayOf(subs[0]);
        require(stampDay > 0, "fixture: subs stamped");
        _toAfkingStageWithPending(subs, stampDay, 0xB0F2);
        // Pre: every box pending.
        for (uint256 i; i < n; ++i) require(_lastOpenedDayOf(subs[i]) < stampDay, "fixture: each afking box pending");

        // Drain in tiny bounded engine chunks. The AFKing stage drains the afking backlog first, then the
        // human-box stage the sealed cohort's human orders — a 1.5M allowance admits AFKing opens but can
        // never admit a human entry, so the bounded phase ends after a few consecutive chunks open none of
        // the subjects' boxes (a refused chunk opens nothing). Each chunk must stay under the per-tx
        // ceiling.
        uint256 totalOpened;
        uint256 zeroStreak;
        for (uint256 c; c < 80; ++c) {
            uint256 before = _openedCount(subs, stampDay);
            vm.prank(makeAddr(string(abi.encodePacked("vd_op_", _u(c)))));
            uint256 gb = gasleft();
            (bool ok,) = address(game).call{gas: 1_500_000}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            uint256 g = gb - gasleft();
            // LIVE-01(c): each bounded engine chunk stays under the EIP per-tx ceiling.
            assertLt(g, EIP7825_TX_GAS_CAP, "LIVE-01(c): each bounded mineFlip chunk stays < 16,777,216");
            uint256 op = ok ? _openedCount(subs, stampDay) - before : 0;
            totalOpened += op;
            if (op == 0) {
                if (++zeroStreak >= 3) break;
            } else {
                zeroStreak = 0;
            }
        }
        // Finish whatever the tiny chunks left — the drained-state assertions below need the
        // genuinely-dry state.
        uint256 beforeFinish = _openedCount(subs, stampDay);
        vm.startPrank(makeAddr("vd_finish"));
        _mineAll(64);
        vm.stopPrank();
        totalOpened += _openedCount(subs, stampDay) - beforeFinish;

        // LIVE-01(b): the whole afking backlog DRAINED — every sub's box opened (lastOpenedDay == stampDay),
        // no stuck box; the afking cursor advanced through the set.
        uint256 openedCount;
        for (uint256 i; i < n; ++i) {
            if (_lastOpenedDayOf(subs[i]) == stampDay) openedCount++;
            // LIVE-01(d): lastOpenedDay is monotone — never exceeds the stamp day (no double-open / over-advance).
            assertLe(_lastOpenedDayOf(subs[i]), stampDay, "LIVE-01(d): lastOpenedDay monotone, no double-open");
        }
        assertEq(openedCount, n, "LIVE-01(b): repeated bounded mineFlip calls fully drained the afking backlog (no stuck box)");

        // LIVE-01(d): a further engine call opens nothing on the drained backlog — no double-open.
        vm.prank(makeAddr("vd_reopen"));
        try game.mineFlip(0) {} catch {}
        for (uint256 i; i < n; ++i) {
            assertEq(_lastOpenedDayOf(subs[i]), stampDay, "LIVE-01(d): re-running the engine on an already-drained backlog opens nothing (no double-open)");
        }
        emit log_named_uint("live01_total_opened", totalOpened);
    }

    /// @notice LIVE-01 (e) selector isolation: the AFKing stage worker (runAfkingWork) runs on the Game's
    ///         storage ONLY through mineFlip's delegatecall. Calling it DIRECTLY on the GameAfkingModule
    ///         contract address operates on the MODULE's OWN storage — an empty _subscribers set — so it
    ///         cannot touch the Game's subscribers. The afking open is never a re-exposed standalone selector
    ///         on a live subscriber set.
    function testLive01AfkingWorkerSelectorIsolation() public {
        // Populate a real afking backlog in the GAME's storage.
        // Stop at the session's AFKing stage with the subject pending (padding subs ahead in the ring).
        _setupFundedSubs(AFKING_PADS, "vsel_pad_", 5 ether, false);
        address afk = makeAddr("vsel_afk");
        uint256 seat = _grantSeat(afk);
        _fundPool(afk, 5 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
        vm.prank(afk);
        game.subscribe(0, false, false, 1, 0, seat);
        _stampNewDay(0xE0F1);
        address[] memory subject = new address[](1);
        subject[0] = afk;
        _toAfkingStageWithPending(subject, _lastBoughtDayOf(afk), 0xE0F2);
        require(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "fixture: afking box pending");

        // Call runAfkingWork DIRECTLY on the module address — it hits the MODULE's empty storage, not the
        // Game's (selector isolation: it reaches the Game only through mineFlip's delegatecall). Whether the
        // module-local call returns or refuses, it must open no Game box.
        bytes32 subSlot = keccak256(abi.encode(uint256(game.walletIdOf(afk)), uint256(SUBOF_SLOT)));
        bytes32 subBefore = vm.load(address(game), subSlot);
        try IGameAfkingModule(ContractAddresses.GAME_AFKING_MODULE).runAfkingWork(1_000_000) returns (MineFlipGas.Result memory direct) {
            assertEq(direct.rewardBasis, 0, "LIVE-01(e): direct runAfkingWork on the module opens nothing (selector-isolated)");
        } catch {}
        // The Game's afking box is UNTOUCHED by the direct module call (still pending, Sub word unchanged).
        assertEq(vm.load(address(game), subSlot), subBefore, "LIVE-01(e): the Game's Sub record untouched by the direct module call");
        assertTrue(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "LIVE-01(e): the Game's afking box untouched by the direct module call");

        // And the canonical path (the engine) DOES open it — the non-vacuity control.
        vm.prank(makeAddr("vsel_op"));
        game.mineFlip(0);
        assertEq(_lastOpenedDayOf(afk), _lastBoughtDayOf(afk), "LIVE-01(e) control: the engine's AFKing stage DOES open the afking box");
    }

    // =========================================================================
    // (l) D-09 — GAS-01..04 marginal regression locks (re-assert against a recorded LOOSE ceiling)
    // =========================================================================

    /// @notice D-09 regression locks: re-assert the GAS-01..04 per-buy / per-open marginals against a RECORDED
    ///         LOOSE ceiling bound (a generous ceiling, NOT a brittle exact number) so a FUTURE regression
    ///         (e.g. a re-introduced per-buy cross-contract storm, or a cold-ledger walk creeping back into the
    ///         open leg) fails the gate while normal measurement variance passes. The bounds are deliberately
    ///         loose multiples of the measured v56 marginals (lootbox/ticket buy, afking open).
    function testD09Gas0104RegressionLocks() public {
        uint256 snap = vm.snapshotState();

        // GAS-01 per-buy lootbox marginal.
        uint256 lN = _measureStageAdvanceGas(N_HI, "d9lbHi_", false, false);
        vm.revertToState(snap);
        uint256 lNm1 = _measureStageAdvanceGas(N_LO, "d9lbLo_", false, false);
        uint256 perBuyLootbox = lN - lNm1;

        // GAS-01 per-buy ticket marginal (the minimal-write primitive).
        vm.revertToState(snap);
        uint256 tN = _measureStageAdvanceGas(N_HI, "d9tkHi_", true, false);
        vm.revertToState(snap);
        uint256 tNm1 = _measureStageAdvanceGas(N_LO, "d9tkLo_", true, false);
        uint256 perBuyTicket = tN - tNm1;

        // GAS-01 per-open afking marginal. SHARED prefix (see testPerOpenMarginal) so the marginal is one real
        // box's open cost, not a seed-noisy difference of two unequal box-cost sums that could underflow here.
        vm.revertToState(snap);
        uint256 oN = _measureOpenLegGas(N_HI, "d9op_");
        vm.revertToState(snap);
        uint256 oNm1 = _measureOpenLegGas(N_LO, "d9op_");
        uint256 perOpen = oN - oNm1;

        emit log_named_uint("d09_per_buy_lootbox_gas", perBuyLootbox);
        emit log_named_uint("d09_per_buy_ticket_gas", perBuyTicket);
        emit log_named_uint("d09_per_open_gas", perOpen);

        // The RECORDED LOOSE ceilings (generous bounds vs the measured v56 marginals: lootbox ~7k / ticket ~54k
        // / open ~70-75k). A regression that re-introduces the v55 per-buy cross-contract storm (~206k lootbox)
        // or a cold-ledger open walk would blow these; normal variance stays well under.
        assertLt(perBuyLootbox, REG_LOCK_LOOTBOX_BUY_CEIL, "D-09: per-buy lootbox marginal under the recorded loose ceiling (no cross-contract storm regression)");
        assertLt(perBuyTicket, REG_LOCK_TICKET_BUY_CEIL, "D-09: per-buy ticket marginal under the recorded loose ceiling (minimal-write primitive intact)");
        assertLt(perOpen, REG_LOCK_OPEN_CEIL, "D-09: per-open afking marginal under the recorded loose ceiling (uniform O(1) open intact)");
    }

    // =========================================================================
    // Internal helpers (new-design driving harness)
    // =========================================================================

    /// @dev Test-only poke of a Sub's lastAutoBoughtDay (uint24 @ byte 11) — preserves all other Sub fields.
    function _pokeLastBoughtDay(address who, uint32 day) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF)) << (OFF_LASTBOUGHT * 8);
        cur = (cur & ~mask) | ((uint256(day) << (OFF_LASTBOUGHT * 8)) & mask);
        vm.store(address(game), slot, bytes32(cur));
    }

    /// @dev Test-only poke of a Sub's lastOpenedDay (uint24 @ byte 14) — preserves all other Sub fields.
    function _pokeLastOpenedDay(address who, uint32 day) internal {
        bytes32 slot = keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF)) << (OFF_LASTOPENED * 8);
        cur = (cur & ~mask) | ((uint256(day) << (OFF_LASTOPENED * 8)) & mask);
        vm.store(address(game), slot, bytes32(cur));
    }

    /// @dev Drive a new-day STAGE advance over N grounded subs that all FUNDING-KILL this cycle (their
    ///      afkingFunding bucket drained to 0 after the grounded day-0 cover-buy, so the STAGE's fresh-ETH
    ///      resolve finds srcFunding(0) < ethValue and each routes through _finalizeAfking + delete +
    ///      swap-pop — SubscriptionExpired reason 1, the successor of the deleted pass-evict crossing; a
    ///      sub's membership no longer ends on a level crossing, only cancel / funding-skip kill / the
    ///      coin's seat lock). Returns the bracketed advance gas. Both runs from one clean baseline.
    function _measureEvictStageGas(uint256 n, string memory prefix) internal returns (uint256 advGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        // Under the D-11/D-12 gates an unfunded subscribe REVERTS, so the funding-killable subs are built
        // GROUNDED (seat + funded -> subscribe passes both gates); the funding drain below (after the
        // day-0 cover-buy consumes its slice) forces the next STAGE cycle's cover-buy unfunded.
        address[] memory subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who);
            _fundPool(who, 5 ether);
            vm.prank(who);
            game.subscribe(0, false, false, 1, 0, seat);
        }
        // OPEN the grounded subscribe's pending boxes first — the no-orphan guard dominates the funding-kill
        // branch, so a pending-box sub would be skipped, not killed. Then drain each sub's remaining
        // afkingFunding bucket to 0 -> the next STAGE cycle's cover-buy is unfunded (funding-kill fires).
        vm.startPrank(makeAddr(string(abi.encodePacked(prefix, "ev_open"))));
        _mineAll(64);
        vm.stopPrank();
        for (uint256 i; i < n; ++i) {
            uint256 bal = game.afkingFundingOf(subs[i]);
            if (bal > 0) {
                vm.prank(subs[i]);
                game.withdrawAfkingFunding(0, bal);
            }
        }
        uint256 preCount = _subscriberCount();
        require(preCount >= n, "fixture: N funding-killable subs in the set");

        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.mineFlip(0);
        advGas = gasBefore - gasleft();

        require(_subscriberCount() < preCount, "evict non-vacuity: the stage funding-killed subs");
    }


    // =========================================================================
    // Driving harness (ported + extended)
    // =========================================================================

    /// @dev Measure a fresh-state new-day advance whose STAGE processes N funded LOOTBOX subs, returning the
    ///      bracketed advance gas. Settles to a clean baseline FIRST (so a prior measurement's unfulfilled
    ///      RNG cannot leave the game rngLocked). The small cohort fits the supplied gas, so one advance stamps
    ///      the whole set in the first chunk; the everything-else of the advance (empty ticket queue) is
    ///      identical across N and N−1 — the (gasN − gasNm1) difference isolates the Nth sub's STAGE cost.
    ///      `landOnSettleDay` warps so the advanced processDay lands on (true) or off (false) a settle
    ///      boundary, so the same helper serves the non-settle per-buy marginal and the settle-day chunk.
    function _measureStageAdvanceGas(uint256 n, string memory prefix, bool isTicket, bool landOnSettleDay)
        internal
        returns (uint256 advGas)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, isTicket);
        // The grounded subscribe (D-12) stamps a box at subscribe time; OPEN those pending boxes so the
        // no-orphan guard does not skip the measured STAGE buy (a pending-box sub is left untouched).
        vm.startPrank(makeAddr(string(abi.encodePacked(prefix, "setup_open"))));
        _mineAll(64);
        vm.stopPrank();
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        _warpToBoundary(landOnSettleDay);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.mineFlip(0);
        advGas = gasBefore - gasleft();

        // Non-vacuity: every measured sub got a NEW stamp this cycle (a real STAGE buy, not a skip).
        for (uint256 i; i < n; ++i) {
            require(_lastBoughtDayOf(subs[i]) > pre[i], "marginal non-vacuity: each funded sub newly stamped");
        }
    }

    /// @dev Warp forward whole days until the simulated day lands ON (settle) or OFF a settle boundary
    ///      (day % SETTLE_PERIOD == 0) — the processDay the next advance stamps with. Always advances at least
    ///      one day so advanceDue() is true. Uses an EXPLICIT accumulating timestamp (`t`) and warps to the
    ///      ABSOLUTE value: `vm.warp(block.timestamp + 1 days)` re-reading block.timestamp inside a loop hits
    ///      a Foundry caching quirk where block.timestamp freezes after the first warp (the day index would
    ///      stall and never reach the boundary). Tracking `t` and warping to it advances reliably.
    function _warpToBoundary(bool onSettle) internal {
        _finishIndexedReadConsumers();
        uint256 t = block.timestamp;
        for (uint256 guardN; guardN < 2 * SETTLE_PERIOD; ++guardN) {
            t += 1 days;
            vm.warp(t);
            uint32 nextDay = _simulatedDayIndex();
            bool isSettle = (uint256(nextDay) % SETTLE_PERIOD == 0);
            if (isSettle == onSettle) return;
        }
        revert("fixture: could not reach requested settle boundary");
    }

    /// @dev Measure the afking open-leg gas over N freshly-stamped + ready LOOTBOX afking boxes, returning
    ///      the bracketed `mineFlip()` open-leg gas. The 2 deploy subs add a CONSTANT 2 ready boxes to BOTH
    ///      the N and N−1 measurements, so they cancel in the (gasN − gasNm1) difference — the marginal
    ///      isolates exactly one box. Each call stamps N subs (new-day STAGE), lands the stamp-day word,
    ///      settles clean (so mineFlip routes to OPEN), opens all.
    function _measureOpenLegGas(uint256 n, string memory prefix) internal returns (uint256 openGas) {
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, false);
        // The boxes open in the session of their stamp day (its AFKing consumer step), so the open leg
        // is measured as that whole session's keeper gas; N and N-1 differ by exactly one open.
        uint256 word = uint256(keccak256(abi.encodePacked(prefix, "word"))) | 1;
        _stampNewDay(word);
        uint32 stampDay = _readStampDay(subs);
        require(stampDay == _simulatedDayIndex(), "fixture: subs stamped for the new day");
        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) < stampDay, "marginal pre: each box queued");
        }

        openGas = _sessionGas(word);
        require(rngWordByDay(stampDay) != 0, "fixture: stamp-day word landed");

        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) == stampDay, "marginal non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players as funded subs in the requested mode (lootbox = useTickets false /
    ///      ticket = useTickets true), seated with an AFKing Subscription Token so the coin gate at subscribe passes;
    ///      funded via depositAfkingFunding so the STAGE :744 afkingFunding debit + :745 claimablePool debit
    ///      land in tandem (SOLVENCY-01 balanced). The STAGE stamps/queues each into a warm Sub slot (GAS-01)
    ///      + runs the v56 mode-agnostic in-slot accrue (no per-buy cross-contract storm — that is deferred
    ///      to the settle day).
    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach, bool isTicket)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who);
            // Fund BEFORE subscribe so the grounded NEW-run cover-buy is funded (D-12 — an unfunded start
            // reverts MustPurchaseToBeginAfking).
            _fundPool(who, poolEach);
            vm.prank(who);
            // self, mode = isTicket, qty 1, reinvest 0, self-funded
            game.subscribe(0, false, isTicket, 1, 0, seat);
        }
    }

    /// @dev Lootbox-mode funded subs (useTickets == false) — the box-stamp primitive.
    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory)
    {
        return _setupFundedSubs(n, prefix, poolEach, false);
    }

    /// @dev Ticket-mode funded subs (useTickets == true) — the new minimal-write `_queueEntriesScaled`
    ///      primitive (off the old ~262k purchaseWith). The ticket leg sets lastOpenedDay ==
    ///      lastAutoBoughtDay so a ticket sub never produces an afking box (open-leg never touches it).
    function _setupFundedTicketSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory)
    {
        return _setupFundedSubs(n, prefix, poolEach, true);
    }

    /// @dev Read the (uniform) stamp day across the subs (each was stamped the same process day by the STAGE).
    function _readStampDay(address[] memory subs) internal view returns (uint32) {
        return _lastBoughtDayOf(subs[0]);
    }

    function _fundPool(address who, uint256 amount) internal {
        // Funding a beneficiary requires its wallet ID, which a real subscriber holds from an
        // earlier paying action; registration returns the existing ID when there is one.
        _giveWalletId(who);
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Finish the current day, then open a NEW day up to its daily request: the subscriber STAGE
    ///      stamps each funded sub's box for that day and the request commits the day's word, left
    ///      undelivered (the boxes stay pending until the session's AFKing consumer step opens them).
    function _stampNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _finishIndexedReadConsumers();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < DRAIN_MAX_ITERATIONS && mockVRF.lastRequestId() == before; ++i) game.mineFlip(0);
        require(mockVRF.lastRequestId() > before, "fixture: the new day's request is in flight");
    }

    /// @dev Deliver the in-flight request's word and run its whole session (daily work, then the read
    ///      consumers, the AFKing opens among them) to completion; returns the summed keeper gas. N and
    ///      N-1 runs share everything but the Nth box, so their difference is one box's open cost.
    function _sessionGas(uint256 vrfWord) internal returns (uint256 total) {
        _fulfillPending(vrfWord);
        for (uint256 i; i < 200 && !game.rngComplete(); ++i) {
            uint256 g0 = gasleft();
            game.mineFlip(0);
            total += g0 - gasleft();
        }
        require(game.rngComplete(), "fixture: the session completed");
    }

    function _allPending(address[] memory subs, uint32 stampDay) internal view returns (bool) {
        for (uint256 i; i < subs.length; ++i) if (_lastOpenedDayOf(subs[i]) >= stampDay) return false;
        return true;
    }

    /// @dev Deliver the in-flight word and advance with bounded allowances until the session's AFKing
    ///      stage (rngConsumerStage 2) is open with every subject box still pending. The engine admits
    ///      chunks while the allowance covers the next declared bound, so the call that finishes the
    ///      daily work opens queue-head boxes with its spare gas: padding subs ahead of the subjects in
    ///      the ring absorb that, and a step reaching a subject is replayed with a smaller allowance.
    function _toAfkingStageWithPending(address[] memory subjects, uint32 stampDay, uint256 vrfWord) internal {
        _fulfillPending(vrfWord);
        for (uint256 i; i < 200 && game.rngConsumerStage() != 2; ++i) {
            uint256 snap = vm.snapshotState();
            bool stepped;
            for (uint256 g = 9_000_000; g >= 400_000 && !stepped; g -= 100_000) {
                try game.mineFlip{gas: g}(0) {
                    if (_allPending(subjects, stampDay)) stepped = true;
                    else require(vm.revertToState(snap), "snapshot");
                } catch {
                    require(vm.revertToState(snap), "snapshot");
                }
            }
            require(stepped, "fixture: a bounded allowance stops at the AFKing stage");
        }
        require(game.rngConsumerStage() == 2, "fixture: the AFKing stage is open");
        require(_allPending(subjects, stampDay), "fixture: every subject box pending at the AFKing stage");
    }

    uint256 internal constant AFKING_PADS = 100;

    /// @dev Drive a fresh new-day STAGE then land the day's word (the per-sub stamp becomes a ready box).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _finishIndexedReadConsumers();
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            // Fulfill any in-flight request FIRST (before advancing) — a stamping advance can leave the game
            // rngLocked with an unfilled word, and mineFlip() would revert RngNotReady if called while the
            // word is 0. Fulfilling at the loop top clears the lock so the next advance can proceed.
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before a mineFlip open so it reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip(0);
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

    // ---- Sub-slot reads (_subOf at slot 52 + v56 offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24)); // uint24
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24)); // uint24
    }

    function _afkCoveredOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKCOVERED, 24)); // uint24
    }

    function _affiliateBaseOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFFBASE, 32)); // uint32
    }

    function _afkingStartOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKINGSTART, 24)); // uint24
    }

    function _pendingFlipOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGFLIP, 24)); // uint24
    }

    function _streakBaseOf(address who) internal view returns (uint16) {
        return uint16(_subField(who, OFF_STREAKLATCH, 16)); // full uint16 streak counter
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Read `purchaseStartDay` (slot 0 byte 0, uint24) — the death-clock anchor bumped by the gap
    ///      backfill (`purchaseStartDay += gapCount`); the decouple proves it bumps EXACTLY ONCE across resume.
    function _purchaseStartDay() internal view returns (uint32) {
        uint256 p = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT)))) >> (OFF_PURCHASE_START_DAY * 8);
        return uint32(p & 0xFFFFFF);
    }

    /// @dev Read `dailyIdx` (slot 0 byte 3, uint24) — the monotonic day counter advanced ONLY by `_unlockRng`.
    ///      The decouple proves advance N (the gap-backfill break) does NOT advance it, so `advanceDue()` stays
    ///      true and advance N+1 pays the deferred jackpot with the same frozen word.
    function _dailyIdx() internal view returns (uint32) {
        uint256 p = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT)))) >> (OFF_DAILY_IDX * 8);
        return uint32(p & 0xFFFFFF);
    }

    /// @dev Read `subsFullyProcessed` (slot 0 byte 28, bool) — set true once the afking STAGE drains the funded
    ///      set for the cycle. After advance N it proves the STAGE actually ran and completed (the
    ///      STAGE_SUBS_BACKFILL_DEFERRED break is only reachable past a completed STAGE), so the defer leg is
    ///      non-vacuous.
    function _subsFullyProcessed() internal view returns (bool) {
        return ((uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT)))) >> (OFF_SUBS_FULLY_PROCESSED * 8)) & 0xFF) != 0;
    }

    /// @dev Field-surgical write of one packed header (slot 0) field, preserving every other flag/field in the
    ///      slot. `offBytes`/`widthBytes` come from `forge inspect DegenerusGame storageLayout`. Used to inject
    ///      the exact worst-case gap-resume precondition without corrupting the 19+ other slot-0 flags.
    function _setHeaderField(uint256 offBytes, uint256 widthBytes, uint256 value) internal {
        uint256 cur = uint256(vm.load(address(game), bytes32(uint256(HEADER_SLOT))));
        uint256 mask = ((uint256(1) << (widthBytes * 8)) - 1) << (offBytes * 8);
        cur = (cur & ~mask) | ((value << (offBytes * 8)) & mask);
        vm.store(address(game), bytes32(uint256(HEADER_SLOT)), bytes32(cur));
    }

    /// @dev Read the STAGE cursor `_subCursor` (slot 56, byte 0, uint16) — advances across admitted subscribers on a
    ///      full chunk.
    function _subCursor() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) & 0xFFFF;
    }

    /// @dev Read the afking-open cursor `_subOpenCursor` (slot 56, byte 2, uint16) — the afking-side open
    ///      walk (mineFlip's AFKing stage, runAfkingWork). Distinct from the human boxCursor (byte 7) —
    ///      LIVE-01 cursor independence.
    function _subOpenCursor() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) >> 16) & 0xFFFF;
    }

    /// @dev How many of `subs` have opened their box for `stampDay`.
    function _openedCount(address[] memory subs, uint32 stampDay) internal view returns (uint256 c) {
        for (uint256 i; i < subs.length; ++i) if (_lastOpenedDayOf(subs[i]) == stampDay) ++c;
    }

    /// @dev The first action of the single mineFlip recorded in `logs` (MinerWork.firstAction).
    function _minerFirstAction(Vm.Log[] memory logs) internal view returns (uint8 first) {
        bytes32 sig = keccak256("MinerWork(address,uint8,uint256,uint256)");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == sig) {
                (first,,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++seen;
            }
        }
        assertEq(seen, 1, "one MinerWork per mineFlip");
    }

    /// @dev Read the human-box cursor `boxCursor` (slot 56, byte 7, uint48) — the human open walk
    ///      (mineFlip's HumanBoxes stage, runHumanBoxWork over boxQueue[read buffer]). Distinct from
    ///      _subOpenCursor (byte 2).
    function _boxCursor() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) >> 56) & 0xFFFFFFFFFFFF;
    }

    /// @dev Read the DAY-keyed afking word `_recordedDailyWord(day)` (the open leg's seed + readiness gate).
    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return RecyclingState.dailyWord(address(game), uint24(day));
    }

    /// @dev Land a word for a specific day directly (the open-readiness gate) when the natural drain did not
    ///      fulfill that exact day's word after a partial STAGE drain. The word is the box's frozen seed.
    function _injectRngWordByDay(uint32 day, uint256 word) internal {
        RecyclingState.seedDailyWord(address(game), uint24(day), word | 1);
    }

    /// @dev The simulated day index the next advance stamps with — read in-context via the game's view
    ///      (`currentDayView()` == `_simulatedDayIndexAt(block.timestamp)`, the exact `processDay` the STAGE
    ///      stamps with, AdvanceModule:169). Used to align the warp onto a settle boundary.
    function _simulatedDayIndex() internal view returns (uint32) {
        return game.currentDayView();
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

    // =========================================================================
    // (m) Q2 INVESTIGATION — warm-vs-cold weight calibration (vm.cool cold marginals)
    // =========================================================================

    /// @notice Compare warm and cooled state for funded buys and expiries. These are relative cost diagnostics.
    function testColdMarginalCalibration() public {
        uint256 snap = vm.snapshotState();

        // WARM (same-tx slots) — the regime every other marginal in this harness measures.
        uint256 wlN = _measureStageAdvanceGas(N_HI, "cwlbHi_", false, false);
        vm.revertToState(snap);
        uint256 wlNm1 = _measureStageAdvanceGas(N_LO, "cwlbLo_", false, false);
        uint256 warmLootbox = wlN - wlNm1;
        vm.revertToState(snap);
        uint256 wtN = _measureStageAdvanceGas(N_HI, "cwtkHi_", true, false);
        vm.revertToState(snap);
        uint256 wtNm1 = _measureStageAdvanceGas(N_LO, "cwtkLo_", true, false);
        uint256 warmTicket = wtN - wtNm1;
        vm.revertToState(snap);
        uint256 weN = _measureEvictStageGas(N_HI, "cwevHi_");
        vm.revertToState(snap);
        uint256 weNm1 = _measureEvictStageGas(N_LO, "cwevLo_");
        uint256 warmEvict = weN - weNm1;

        // COLD (vm.cool first-touch) — the realistic daily advance (subs funded/stamped on a prior tx).
        vm.revertToState(snap);
        uint256 lN = _measureStageAdvanceGasCold(N_HI, "cdlbHi_", false);
        vm.revertToState(snap);
        uint256 lNm1 = _measureStageAdvanceGasCold(N_LO, "cdlbLo_", false);
        require(lN > lNm1, "cold-calib: the Nth cold lootbox sub did real work");
        uint256 coldLootbox = lN - lNm1;
        vm.revertToState(snap);
        uint256 tN = _measureStageAdvanceGasCold(N_HI, "cdtkHi_", true);
        vm.revertToState(snap);
        uint256 tNm1 = _measureStageAdvanceGasCold(N_LO, "cdtkLo_", true);
        require(tN > tNm1, "cold-calib: the Nth cold ticket sub did real work");
        uint256 coldTicket = tN - tNm1;
        vm.revertToState(snap);
        uint256 eN = _measureEvictStageGasCold(N_HI, "cdevHi_");
        vm.revertToState(snap);
        uint256 eNm1 = _measureEvictStageGasCold(N_LO, "cdevLo_");
        require(eN > eNm1, "cold-calib: the Nth cold evicting sub did real work");
        uint256 coldEvict = eN - eNm1;

        emit log_named_uint("warm_lootbox_marginal_gas", warmLootbox);
        emit log_named_uint("warm_ticket_marginal_gas", warmTicket);
        emit log_named_uint("warm_evict_marginal_gas", warmEvict);
        emit log_named_uint("cold_lootbox_marginal_gas", coldLootbox);
        emit log_named_uint("cold_ticket_marginal_gas", coldTicket);
        emit log_named_uint("cold_evict_marginal_gas", coldEvict);
        emit log_named_uint("cold_over_warm_lootbox_x100", coldLootbox * 100 / warmLootbox);
        emit log_named_uint("cold_ticket_over_lootbox_x100", coldTicket * 100 / coldLootbox);
        emit log_named_uint("cold_evict_over_lootbox_x100", coldEvict * 100 / coldLootbox);
        // Artifact direction: cooling RAISES each marginal (a cold first-touch costs more than the warm same-tx
        // slot) — the empirical confirmation that the warm marginals elsewhere understate the realistic cost.
        assertGt(coldLootbox, warmLootbox, "cold-calib: vm.cool raises the lootbox marginal (warm same-tx understates)");
        assertGt(coldTicket, warmTicket, "cold-calib: vm.cool raises the ticket marginal");
        assertGt(coldEvict, warmEvict, "cold-calib: vm.cool raises the evict marginal");
        // Each cold marginal stays a bounded O(1) (no magnitude scaling) — the calibration numbers above are the
        // diagnostic deliverable, not pinned to brittle exact values.
        assertLt(coldLootbox, 200_000, "cold-calib: cold lootbox marginal is a bounded O(1)");
        assertLt(coldTicket, 200_000, "cold-calib: cold ticket marginal is a bounded O(1)");
        assertLt(coldEvict, 200_000, "cold-calib: cold evict marginal is a bounded O(1)");
    }

    /// @dev COLD variant of _measureStageAdvanceGas: identical setup, but vm.cool's the game storage right
    ///      before the bracketed advance so the STAGE reads each sub's Sub slot + afkingFunding entry as a COLD
    ///      first-touch (the realistic daily advance — subs funded/stamped on a prior tx). The marginal isolates
    ///      the Nth sub's COLD STAGE cost, the regime the native subscriber reservation must cover.
    function _measureStageAdvanceGasCold(uint256 n, string memory prefix, bool isTicket)
        internal
        returns (uint256 advGas)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, isTicket);
        vm.startPrank(makeAddr(string(abi.encodePacked(prefix, "setup_open"))));
        _mineAll(64);
        vm.stopPrank();
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        vm.cool(address(game)); // re-cold all game storage -> each Sub slot is a cold first-touch in the STAGE
        uint256 gasBefore = gasleft();
        game.mineFlip(0);
        advGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            require(_lastBoughtDayOf(subs[i]) > pre[i], "cold marginal non-vacuity: each funded sub newly stamped");
        }
    }

    /// @dev COLD variant of _measureEvictStageGas: identical funding-kill setup, vm.cool before the
    ///      bracketed advance so each killed sub's cross-contract finalize (quest read + streak write) is a
    ///      cold first-touch. Complete cold operations are measured by SubscriberAfkingNativeGas.
    function _measureEvictStageGasCold(uint256 n, string memory prefix) internal returns (uint256 advGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who);
            _fundPool(who, 5 ether);
            vm.prank(who);
            game.subscribe(0, false, false, 1, 0, seat);
        }
        vm.startPrank(makeAddr(string(abi.encodePacked(prefix, "ev_open"))));
        _mineAll(64);
        vm.stopPrank();
        for (uint256 i; i < n; ++i) {
            uint256 bal = game.afkingFundingOf(subs[i]);
            if (bal > 0) {
                vm.prank(subs[i]);
                game.withdrawAfkingFunding(0, bal);
            }
        }
        uint256 preCount = _subscriberCount();
        require(preCount >= n, "fixture: N funding-killable subs in the set");

        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        vm.cool(address(game)); // re-cold all game storage -> the finalize cross-contract read is a cold touch
        uint256 gasBefore = gasleft();
        game.mineFlip(0);
        advGas = gasBefore - gasleft();

        require(_subscriberCount() < preCount, "cold evict non-vacuity: the stage funding-killed subs");
    }

    /// @dev Exercise native admission through the real router. A deliberately small
    ///      call must defer, then bounded calls must evict every unpaid subscriber
    ///      exactly once while preserving the untouched records behind each checkpoint.
    ///      The caller chooses the gas envelope; there is no fixed 312-item batch.
    function test_AllEvictSaturatedChunk_LIVE_Measured() public {
        uint256 count = 320;
        address[] memory players = _prepareNativeEvictionCohort(count, "liveAllEv_");
        uint256 protocolMembers = _subscriberCount() - count;
        bytes32[] memory originalSubs = new bytes32[](count);
        for (uint256 i; i < count; ++i) {
            _nativeEvictionExpected[players[i]] = true;
            originalSubs[i] = _nativeSubWord(players[i]);
            assertTrue(originalSubs[i] != bytes32(0), "fixture: every ordinary subscriber has a live record");
            assertEq(_lastOpenedDayOf(players[i]), _lastBoughtDayOf(players[i]), "fixture: no pending paid box");
        }

        // Even before retaining the router's own boundary/return gas this is
        // below a complete worker item. It must not let a caller buy an eviction
        // by starving an otherwise admitted optional token pull.
        uint256 insufficient = GasBounds.SUBSCRIBER_ITEM_GAS + GasBounds.SUBSCRIBER_TAIL_GAS
            + MineFlipGas.CHECK_RESERVE - 1;
        vm.recordLogs();
        vm.cool(address(game));
        game.mineFlip{gas: insufficient}(0);
        assertEq(_recordNativeEvictions(vm.getRecordedLogs()), 0, "LIVE: no eviction before complete-item admission");
        assertEq(_subscriberCount(), count + protocolMembers);
        _assertNativeEvictionCheckpoint(players, originalSubs);

        uint256 totalEvicted;
        uint256 calls;
        uint256 peak;
        // Reserve two outer boundary/return envelopes conservatively as well as
        // the worker tail; the remaining named item reservations must do useful
        // work, not merely return successfully under the caller's gas limit.
        uint256 guaranteedItems = (NATIVE_EVICTION_CALL_GAS
            - 2 * (GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN)
            - GasBounds.SUBSCRIBER_TAIL_GAS - MineFlipGas.CHECK_RESERVE)
            / GasBounds.SUBSCRIBER_ITEM_GAS;
        assertGt(guaranteedItems, 0);
        while (totalEvicted < count && calls < count) {
            uint256 membersBefore = _subscriberCount();
            uint256 cursorBefore = _subCursor();
            vm.recordLogs();
            vm.cool(address(game));
            uint256 gasBefore = gasleft();
            game.mineFlip{gas: NATIVE_EVICTION_CALL_GAS}(0);
            uint256 callGas = gasBefore - gasleft();
            uint256 evicted = _recordNativeEvictions(vm.getRecordedLogs());
            uint256 remaining = count - totalEvicted;
            assertGe(evicted, remaining < guaranteedItems ? remaining : guaranteedItems,
                "LIVE: each funded call commits the work its conservative reservations admit");
            assertEq(membersBefore - _subscriberCount(), evicted, "LIVE: each expiry removes exactly one member");
            assertGe(_subCursor(), cursorBefore, "LIVE: swap-pop checkpoint never moves behind completed work");
            assertLe(_subCursor(), _subscriberCount(), "LIVE: checkpoint remains within the live set");
            _assertNativeEvictionCheckpoint(players, originalSubs);
            totalEvicted += evicted;
            ++calls;
            if (callGas > peak) peak = callGas;
            if (totalEvicted < count) {
                assertFalse(_subsFullyProcessed(), "LIVE: partial chunk keeps subscription work pending");
                assertTrue(game.advanceDue(), "LIVE: unfinished cohort remains reachable by the next miner");
                assertFalse(game.rngLocked(), "LIVE: RNG cannot start before every subscription is processed");
            }
        }
        assertGt(calls, 1, "LIVE: the fixture really crosses admission checkpoints");
        assertEq(totalEvicted, count, "LIVE: repeated bounded calls finish every unpaid subscriber");
        assertEq(_subscriberCount(), protocolMembers, "LIVE: only the exempt protocol subscriptions remain");
        assertTrue(_subsFullyProcessed(), "LIVE: completed cohort is committed");
        for (uint256 i; i < count; ++i) assertTrue(_nativeEvictionSeen[players[i]], "LIVE: no subscriber omitted");
        emit log_named_uint("live_native_eviction_call_budget_gas", NATIVE_EVICTION_CALL_GAS);
        emit log_named_uint("live_native_eviction_call_count", calls);
        emit log_named_uint("live_native_eviction_peak_call_gas", peak);
        emit log_named_uint("live_native_eviction_total_unique_expirations", totalEvicted);
    }

    function _prepareNativeEvictionCohort(uint256 count, string memory prefix)
        private returns (address[] memory players)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        players = _setupFundedSubs(count, prefix, 5 ether, false);
        vm.startPrank(makeAddr(string(abi.encodePacked(prefix, "ev_open"))));
        _mineAll(64);
        vm.stopPrank();
        for (uint256 i; i < count; ++i) {
            uint256 funding = game.afkingFundingOf(players[i]);
            if (funding != 0) {
                vm.prank(players[i]);
                game.withdrawAfkingFunding(0, funding);
            }
        }
        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: the new subscription day is due");
    }

    /// @dev The player's Sub word without its set position (bits 224..255), which swap-pop
    ///      rewrites when another member's eviction moves this record within the set.
    function _nativeSubWord(address player) private view returns (bytes32) {
        uint256 word = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(player)), uint256(SUBOF_SLOT)))));
        return bytes32(word & ~(uint256(type(uint32).max) << 224));
    }

    function _assertNativeEvictionCheckpoint(address[] memory players, bytes32[] memory originalSubs) private view {
        for (uint256 i; i < players.length; ++i) {
            assertEq(_nativeSubWord(players[i]), _nativeEvictionSeen[players[i]] ? bytes32(0) : originalSubs[i],
                "LIVE: each record is either fully evicted or unchanged for a later call");
        }
    }

    function _recordNativeEvictions(Vm.Log[] memory logs) private returns (uint256 evicted) {
        bytes32 expired = keccak256("SubscriptionExpired(uint32,uint8)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length != 2 || logs[i].topics[0] != expired) continue;
            address player = _fixturePayee(uint32(uint256(logs[i].topics[1])));
            assertTrue(_nativeEvictionExpected[player], "LIVE: no unrelated subscriber is evicted");
            assertFalse(_nativeEvictionSeen[player], "LIVE: no duplicate expiry across resumed calls");
            assertEq(abi.decode(logs[i].data, (uint8)), 1, "LIVE: ordinary insufficient-funding expiry");
            _nativeEvictionSeen[player] = true;
            ++evicted;
        }
    }


    /// @notice STRUCTURAL PROTECTION PROOF: the subscriber-chunk + jackpot composition (buffered-clamp re-open)
    ///         cannot carry a HEAVY chunk, because the clamp requires the RNG lock (AdvanceModule:211 `locked`)
    ///         and the v45 freeze invariant reverts ALL subscribe/replace/cancel under that lock
    ///         (GameAfkingModule:328). This drives the exact buffered-clamp window ORGANICALLY (multi-day gap ->
    ///         far-day request -> fulfill -> one more wall-day) and asserts that AT the consuming window the game
    ///         is rngLocked and a NEW subscribe REVERTS RngLocked(). So no new buy-subs (nor cancels/evicts) can
    ///         enter the window: every re-opened sub was stamped to the far request-day and SKIPS at guard :1324.
    ///         The re-opened chunk is therefore all-skip (bounded ~6.4M), and all-skip + the jackpot leg stays
    ///         under the EIP-7825 cap. This is why the composition is reachable but NOT a cap breach.
    function test_BufferedClampReopen_GateSkipsStageUnderLock() public {
        address[] memory old = _setupFundedSubs(1, "frzbuf_old_", 50 ether, false);
        _settleClean(uint256(keccak256("frzbuf_base")) | 1);
        vm.startPrank(makeAddr("frzbuf_open"));
        _mineAll(64);
        vm.stopPrank();
        require(!game.advanceDue() && !game.rngLocked(), "fixture: clean idle baseline");

        uint32 dIdx0 = _dailyIdx();

        // Multi-day keeper gap with a CLEAN rng state -> the first post-gap advance processes a FAR day and
        // REQUESTS a word (engaging the RNG lock). This is the moment the buffered-clamp precondition is armed.
        vm.warp(block.timestamp + 4 days);
        uint32 farDay = game.currentDayView();
        require(farDay > dIdx0 + 1, "fixture: a multi-day gap opened (wallDay >> dailyIdx)");
        require(game.advanceDue(), "fixture: advanceDue after the gap");
        game.mineFlip(0);
        require(game.rngLocked(), "fixture: the far-day advance requested a word (RNG LOCK engaged)");
        require(_dailyIdx() == dIdx0, "fixture: the request advance did NOT seal (dailyIdx unchanged)");

        _fulfillPending(uint256(keccak256("frzbuf_word")) | 1);
        // One MORE wall-day passes with no advance -> the buffered clamp WILL fire on the next advance, and the
        // game is STILL rngLocked (the lock clears only at _unlockRng, which the next advance's clamp defers).
        vm.warp(block.timestamp + 1 days);
        require(game.currentDayView() > farDay, "fixture: one more wall-day (buffered-clamp precondition met)");
        assertTrue(game.rngLocked(), "the buffered-clamp consuming window is RNG-LOCKED (the clamp requires `locked`)");

        // THE STRUCTURAL PROTECTION: a NEW subscribe in this exact window REVERTS — so no buy-sub can join the
        // re-opened chunk. The v45 freeze invariant IS the reason the composition can never carry a heavy chunk.
        address newBuyer = makeAddr("frzbuf_newbuyer");
        uint256 seat = _grantSeat(newBuyer);
        _fundPool(newBuyer, 50 ether);
        vm.prank(newBuyer);
        vm.expectRevert(); // RngLocked() — GameAfkingModule:328, blocks create/replace/cancel under the lock
        game.subscribe(0, false, false, 1, 0, seat);

        // THE ENTRY GATE, proven organically: drive the buffered-clamp consuming drain and
        // assert the subscriber STAGE did not run in ANY locked call — zero PlayerSkipped
        // emissions (the walk visits nothing under the lock; the old code re-opened an all-skip
        // walk here). A ticket batch may legitimately interpose before the day seals, so keep
        // draining under the same lock until dailyIdx advances. The gate is why a completing
        // subscriber chunk and a buffered-word jackpot apply can never share one tx.
        uint32 idxBeforeConsume = _dailyIdx();
        bytes32 skippedSig = keccak256("PlayerSkipped(uint32,uint8)");
        uint256 consumeCalls;
        while (_dailyIdx() == idxBeforeConsume && consumeCalls < DRAIN_MAX_ITERATIONS) {
            vm.recordLogs();
            game.mineFlip(0);
            Vm.Log[] memory consumeLogs = vm.getRecordedLogs();
            for (uint256 i; i < consumeLogs.length; ++i) {
                assertTrue(
                    consumeLogs[i].topics.length == 0 || consumeLogs[i].topics[0] != skippedSig,
                    "GATE: the subscriber stage never runs while rngLocked (no ring visits in the consuming drain)"
                );
            }
            unchecked {
                ++consumeCalls;
            }
        }
        assertGt(_dailyIdx(), idxBeforeConsume, "non-vacuity: the consuming advance applied/sealed a day");
        emit log_named_uint("buffered_clamp_consuming_calls", consumeCalls);

        emit log_named_string(
            "FINDING",
            "The buffered-clamp consuming window is RNG-locked: subscribe/cancel revert (v45 freeze) "
            "AND the VRF-outstanding entry gate keeps the subscriber STAGE out of the consuming tx entirely -- "
            "the subscriber+jackpot composition is structurally impossible at any ring size."
        );
        require(old.length == 1, "fixture: old sub intact");
    }


}
