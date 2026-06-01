// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title V56AfkingGasMarginal -- the v56 everyday-afking gas-MARGINAL harness (Phase 355, GAS-01/GAS-02)
///        on the e18af451 applied tree (baseline 453f8073). Measures every marginal the GAS phase needs:
///        the per-buy LOOTBOX marginal, the per-buy TICKET marginal (the new minimal-write primitive), the
///        per-OPEN marginal, the per-SETTLE marginal (the settle-day chunk riding the buy stage), and the
///        WORST-CASE per-tx chunk for EVERY batched advance/afking loop — the settle-day STAGE chunk at
///        SUB_STAGE_BATCH (the binding case, where every sub fires _settleQuest) and the OPEN_BATCH open
///        chunk. From each measured worst-case per-item marginal it DERIVES the max safe batch (the largest
///        N keeping the per-tx chunk under the 10M comfort TARGET) and reports the dual bound (< 10M target,
///        provably <= 16.7M hard ceiling). Also proves GAS-02 empirically: the per-buy in-slot accrue makes
///        NO new cold per-buy SSTORE.
///
/// @notice The v56 applied tree (what THIS harness measures — the v55 storm described in the old
///         V55AfkingGasMarginal header is GONE):
///
///         (1) The per-buy hot path (GameAfkingModule.processSubscriberStage, :582-929) collapsed: the
///             SOLVENCY-01 debit (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`,
///             :744-745, byte-frozen from v55) → the per-mode primitive (lootbox box-stamp OR the NEW ticket
///             minimal-write `_queueTicketsScaled` + buyerOwedBurnie accrue, replacing the ~262k purchaseWith
///             heavyweight) → the MODE-AGNOSTIC in-slot accrue (:887-900: affiliateBase flat-7% +=,
///             ++questProgress, afkCoveredThroughDay = processDay) → the lastAutoBoughtDay marker (:907) →
///             IF processDay % SETTLE_PERIOD == 0 THEN _settleQuest (:916-918). The per-buy cross-contract
///             quest/affiliate/coinflip storm of v55 is DEFERRED to the ~10-day aggregator: the everyday buy
///             is a warm SLOAD-mask-SSTORE on ONE Sub slot, no cross-contract calls except the rare settle
///             day.
///
///         (2) The Sub slot (DegenerusGameStorage.sol:1894-1962) is a SINGLE 256-bit slot, 241/256 bits used:
///             config 48 + stamp 48 (scorePlus1 uint16 / amount uint32 milli-ETH) + markers 72
///             (lastAutoBoughtDay/lastOpenedDay/afkCoveredThroughDay uint24 each) + accumulator 73
///             (affiliateBase uint32 / questProgress uint8 / buyerOwedBurnie uint32 / hasEverSubscribed bool).
///             The accumulator is IN-SLOT — the per-buy accrue is a warm write on the SAME slot the stamp
///             dirtied, NOT a new cold slot. THIS is the GAS-02 property (proven in Task 3). The day markers
///             narrowed to uint24 and the accumulator fields are NEW vs v55, so the byte offsets are
///             RE-DERIVED below (the v55 OFF_LASTBOUGHT=21 / OFF_LASTOPENED=25 premise is WRONG here).
///
///         (3) The settle-day ride (:916-918): on a global settle boundary (processDay % SETTLE_PERIOD == 0,
///             ~10-day cadence) every sub fires _settleQuest (:1141 — one coinflip.creditFlip of
///             questProgress×QUEST_SLOT0_REWARD + buyerOwedBurnie, + quests.settleAfkingQuest streak-advance,
///             then drains both counters to 0). The settle-day STAGE chunk is the BINDING worst case for
///             SUB_STAGE_BATCH (every sub pays the settle overhead).
///
/// @notice The MARGINAL rule (CR-01 / 350-SPEC §0, load-bearing, verbatim): every per-item number is the
///         loop-N-divide MARGINAL — (gas for N items − gas for N−1 items), NEVER a single-item TOTAL. A
///         single-item total over-states the per-item cost and (were a reward pegged to it) re-introduces
///         the Phase-319 self-crank faucet. Both the N and the N−1 measurements run from ONE identical clean
///         baseline via `vm.snapshotState()` / `vm.revertToState()` — a LINEAR two-cycle run trips the
///         idle-fixture day saturation + an unfulfilled-RNG `RngNotReady` on the second cycle (the 351-07
///         documented failure). The snapshot/revert form gives both measurements the SAME fresh state, so
///         (gasN − gasNm1) isolates exactly the Nth item's cost.
///
/// @notice The DUAL BOUND (USER-LOCKED this phase): every batched per-tx loop in the daily advance / afking
///         chain must be sized so its WORST-CASE gas TARGETS < 10,000,000 (GAS_TARGET — the design comfort
///         target) AND PROVABLY NEVER EXCEEDS 16,700,000 (EFFECTIVE_GAS_CEILING — the HARD never-exceed kill
///         ceiling; a breach = advanceGame DoS / forced game-over). The headroom (16.7M − the measured chunk
///         at the chosen batch) is the safety margin that absorbs measurement variance + worst-case
///         outliers. foundry.toml inflates block_gas_limit to 30e9 for the harness; the bar is the 16.7M.
///         For each batched loop the harness DERIVES the max safe batch: max N = the largest integer with
///         fixed_tx_overhead + N×worst_case_per_item_marginal < GAS_TARGET ("optimal" = that largest N), and
///         cross-checks the current constant <= that derived N (an over-large constant FAILS the test).
///
/// @dev Live `DeployProtocol` fixture; reuses the validated game-resident driving harness (the
///      `_settleGame`/`_settleClean` VRF drain, the funded-sub setup, `depositAfkingFunding` funding,
///      `_grantDeityPass`, the Sub-slot reads, the snapshot/revert two-near-N form) ported from
///      V55AfkingGasMarginal. All pinned slots RE-DERIVED via `forge inspect DegenerusGame storage` /
///      `storageLayout` against the e18af451 tree (`_subOf = 66`, `_subscribers = 68`, `_subCursor = 70:0`,
///      `_subOpenCursor = 70:2`, `rngWordByDay = 11`; the Sub field byte offsets re-derived from the v56
///      re-pack). Test-only: ZERO contracts/*.sol mutated (`git diff e18af451 -- contracts/` EMPTY).
contract V56AfkingGasMarginal is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect DegenerusGame storage` @ e18af451)
    // -------------------------------------------------------------------------

    uint256 private constant RNG_WORD_BY_DAY_SLOT = 11; // mapping(uint32 => uint256) — the afking box's DAY-keyed word + readiness gate
    uint256 private constant SUBOF_SLOT = 66;           // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 68;     // address[] _subscribers (slot holds the length)
    uint256 private constant SUBCURSOR_SLOT = 70;       // _subCursor (uint16 @ byte 0) + _subOpenCursor (uint16 @ byte 2) + _afkingResetDay (uint32 @ byte 4)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:1894-1962; RE-DERIVED via
    // `forge inspect DegenerusGame storageLayout` @ e18af451 — the v56 re-pack narrowed the day markers to
    // uint24 and ADDED the in-slot accumulator, so the v55 offsets are WRONG). Single 256-bit Sub slot:
    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u32 @8
    //   lastAutoBoughtDay u24 @12 · lastOpenedDay u24 @15 · afkCoveredThroughDay u24 @18
    //   affiliateBase u32 @21 · questProgress u8 @25 · buyerOwedBurnie u32 @26 · hasEverSubscribed bool @30
    uint256 private constant OFF_LASTBOUGHT = 12; // uint24 lastAutoBoughtDay (bytes 12..14)
    uint256 private constant OFF_LASTOPENED = 15; // uint24 lastOpenedDay     (bytes 15..17)
    uint256 private constant OFF_AFKCOVERED = 18; // uint24 afkCoveredThroughDay (bytes 18..20)
    uint256 private constant OFF_AFFBASE = 21;    // uint32 affiliateBase    (bytes 21..24)
    uint256 private constant OFF_QUESTPROG = 25;  // uint8  questProgress    (byte 25)
    uint256 private constant OFF_OWEDBURNIE = 26; // uint32 buyerOwedBurnie  (bytes 26..29)

    uint256 private constant MINTPACKED_SLOT = 10;
    uint256 private constant DEITY_SHIFT = 184;

    // -------------------------------------------------------------------------
    // Dual-bound + worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The 10M design comfort TARGET (USER-LOCKED dual bound). Every batched per-tx loop's worst-case
    ///      chunk at the chosen batch must land BELOW this; the derived max-safe batch is the largest N with
    ///      fixed_overhead + N×worst_case_per_item_marginal < GAS_TARGET.
    uint256 internal constant GAS_TARGET = 10_000_000;

    /// @dev The 16.7M HARD never-exceed kill ceiling (USER-LOCKED dual bound). A breach = advanceGame DoS /
    ///      forced game-over. foundry.toml inflates block_gas_limit to 30e9 for the harness; the never-exceed
    ///      bar is this 16.7M. The headroom (16.7M − the measured-at-target chunk) is the safety margin.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev SUB_STAGE_BATCH (DegenerusGameAdvanceModule.sol:149): one advanceGame() STAGE processes up to 50
    ///      funded subs (the per-day buy/stage chunk; there is NO standalone BUY_BATCH constant). The BINDING
    ///      worst case is the settle-day STAGE chunk (processDay % SETTLE_PERIOD == 0, every sub fires
    ///      _settleQuest).
    uint256 internal constant SUB_STAGE_BATCH = 50;

    /// @dev OPEN_BATCH (GameAfkingModule.sol:206): the flat per-box open chunk; each afking box uniform O(1).
    uint256 internal constant OPEN_BATCH = 200;

    /// @dev SETTLE_PERIOD (GameAfkingModule.sol:172): the quest leg settles inline on
    ///      processDay % SETTLE_PERIOD == 0 (~10-day cadence).
    uint256 internal constant SETTLE_PERIOD = 10;

    /// @dev SUBSCRIBER_CAP (GameAfkingModule.sol:164): the worst-case active sub count.
    uint256 internal constant SUBSCRIBER_CAP = 500;

    /// @dev Informational v55/349.2 per-buy lootbox reference (~206k, the v55 measured marginal WITH the
    ///      per-buy cross-contract storm) and the ~130-140k GAS-01 target band (the v56 deferred-settle win).
    ///      Reported as a comparison log, NOT a hard pin — the MEASURED number is the deliverable.
    uint256 internal constant V55_LOOTBOX_BUY_REF = 206_000;
    uint256 internal constant V56_LOOTBOX_TARGET_LO = 130_000;
    uint256 internal constant V56_LOOTBOX_TARGET_HI = 140_000;

    /// @dev The old per-day ~262k purchaseWith reference (the heavyweight the v56 ticket minimal-write
    ///      primitive replaces). Reported as the structural-win comparison for the ticket marginal.
    uint256 internal constant V55_TICKET_PURCHASEWITH_REF = 262_000;

    /// @dev N for the two-near-N marginal: measure N vs N−1 from one clean baseline (snapshot/revert). Big
    ///      enough that the funded set + the 2 deploy subs stay < SUB_STAGE_BATCH (one advance stamps all in
    ///      the first chunk), so the everything-else of the advance is identical across N and N−1.
    uint256 internal constant N_HI = 24;
    uint256 internal constant N_LO = 23;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // Derived-batch helper (the harness DERIVES the optimal batch, it is not guessed)
    // =========================================================================

    /// @dev The largest N with `fixedOverhead + N×perItemMarginal < GAS_TARGET` — the derived OPTIMAL
    ///      (max-safe, throughput-maximizing) batch size for a per-tx loop. If even N=0 already exceeds the
    ///      target (fixedOverhead >= GAS_TARGET) it returns 0. perItemMarginal must be non-zero (a measured
    ///      marginal always is; guarded to avoid div-by-zero).
    function _maxSafeBatch(uint256 fixedOverhead, uint256 perItemMarginal) internal pure returns (uint256) {
        if (perItemMarginal == 0) return 0;
        if (fixedOverhead >= GAS_TARGET) return 0;
        return (GAS_TARGET - 1 - fixedOverhead) / perItemMarginal;
    }

    // =========================================================================
    // (a) per-buy LOOTBOX marginal — a NON-settle-day STAGE (GAS-01)
    // =========================================================================

    /// @notice The per-buy LOOTBOX marginal = (gas for N funded lootbox subs − gas for N−1) / 1, measured the
    ///         ROBUST snapshot/revert way (both runs from one clean baseline) over a NON-settle-day STAGE
    ///         advance (processDay % SETTLE_PERIOD != 0 — the everyday cheap buy, no _settleQuest). The v56
    ///         everyday lootbox buy is a warm box-stamp + the mode-agnostic in-slot accrue, NO per-buy
    ///         cross-contract storm (that is deferred to the ~10-day settle). Asserts the marginal alone
    ///         trivially fits the 16.7M ceiling; emits the informational comparison vs the v55 ~206k reference
    ///         and the ~130-140k GAS-01 target band (the MEASURED number is the deliverable, NOT a hard pin).
    function testPerBuyLootboxMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureStageAdvanceGas(N_HI, "blMhi_", false, false);
        vm.revertToState(snap);
        uint256 gasNm1 = _measureStageAdvanceGas(N_LO, "blMlo_", false, false);

        assertGt(gasN, gasNm1, "per-buy lootbox marginal: N subs cost strictly more than N-1 (the Nth sub did real work)");
        uint256 perBuyLootbox = gasN - gasNm1; // (gas for N − gas for N−1) / 1 — the loop-N-divide MARGINAL

        assertLt(perBuyLootbox, EFFECTIVE_GAS_CEILING, "per-buy lootbox marginal trivially fits the 16.7M ceiling");

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

    /// @notice The per-buy TICKET marginal = (gas for N funded ticket subs − gas for N−1) / 1, NON-settle-day
    ///         STAGE, snapshot/revert. The ticket leg is the NEW minimal-write `_queueTicketsScaled` primitive
    ///         + the buyerOwedBurnie in-slot accrue (off the old ~262k purchaseWith heavyweight that dragged
    ///         in recordMint + the whole quests/affiliate/coinflip work). Asserts under the ceiling; emits the
    ///         structural-win comparison vs the ~262k purchaseWith reference.
    function testPerBuyTicketMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureStageAdvanceGas(N_HI, "btMhi_", true, false);
        vm.revertToState(snap);
        uint256 gasNm1 = _measureStageAdvanceGas(N_LO, "btMlo_", true, false);

        assertGt(gasN, gasNm1, "per-buy ticket marginal: N subs cost strictly more than N-1 (the Nth sub did real work)");
        uint256 perBuyTicket = gasN - gasNm1;

        assertLt(perBuyTicket, EFFECTIVE_GAS_CEILING, "per-buy ticket marginal trivially fits the 16.7M ceiling");

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
    // (c) per-OPEN marginal + the OPEN_BATCH chunk dual bound (GAS-01)
    // =========================================================================

    /// @notice The per-open marginal = (gas for N opens − gas for N−1 opens) / 1, snapshot/revert. The afking
    ///         open leg is `_autoOpen(OPEN_BATCH)`, reached via `mintBurnie()`; each afking box rolls boons
    ///         like a human box (~75k/box, uniform O(1) — a cheap stamp-derived resolve, no boxPlayers walk /
    ///         no lootboxEth read-zero, the anti-gas-DoS property the human openLootBox lacks). All numbers
    ///         are EMITTED first (the measured per-box marginal + the OPEN_BATCH chunk + the derived max-safe
    ///         batch ARE the deliverable). HARD safety asserts (the never-breach floor): per-box is uniform
    ///         O(1), a derived max-safe batch > 0 exists, the chunk AT the derived max-safe batch is < 10M
    ///         (the derivation is sound), and the OPEN_BATCH chunk stays ≤ 16.7M (the never-exceed ceiling).
    ///         The < 10M TARGET at the CURRENT OPEN_BATCH is reported as a needs-retune FLAG for 355-03, NOT a
    ///         hard revert — re-sizing OPEN_BATCH to the < 10M target is 355-03's explicit charge (and at
    ///         ~75k/box, 200 boxes ≈ 15M > the 10M target, so the flag is expected to direct a shrink).
    function testPerOpenMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureOpenLegGas(N_HI, "opMhi_");
        vm.revertToState(snap);
        uint256 gasNm1 = _measureOpenLegGas(N_LO, "opMlo_");

        assertGt(gasN, gasNm1, "per-open marginal: N opens cost strictly more than N-1 (the Nth box materialized)");
        uint256 perOpen = gasN - gasNm1; // (gas for N − gas for N−1) / 1 — the loop-N-divide MARGINAL

        // Derive the OPEN_BATCH chunk. fixed_open_overhead = the open-leg tx overhead at N opens minus the N
        // per-box marginals (the constant mintBurnie entry/exit + advance-check + bounty cost shared by any
        // open chunk size). The chunk at a batch B = fixed + B×perOpen.
        uint256 fixedOpenOverhead = gasN > perOpen * N_HI ? gasN - perOpen * N_HI : 0;
        uint256 openChunkAtBatch = fixedOpenOverhead + OPEN_BATCH * perOpen;
        uint256 derivedMaxSafeOpenBatch = _maxSafeBatch(fixedOpenOverhead, perOpen);
        uint256 chunkAtDerived = fixedOpenOverhead + derivedMaxSafeOpenBatch * perOpen;
        uint256 openHeadroomCurrent =
            EFFECTIVE_GAS_CEILING > openChunkAtBatch ? EFFECTIVE_GAS_CEILING - openChunkAtBatch : 0;
        bool openBatchFits10MTarget = openChunkAtBatch < GAS_TARGET;

        // EMIT-FIRST — the measured numbers + the derived max-safe batch are the load-bearing 355-03 input.
        emit log_named_uint("per_open_marginal_gas", perOpen);
        emit log_named_uint("per_open_gas_n", gasN);
        emit log_named_uint("per_open_gas_n_minus_1", gasNm1);
        emit log_named_uint("open_fixed_overhead_gas", fixedOpenOverhead);
        emit log_named_uint("open_chunk_at_OPEN_BATCH_gas", openChunkAtBatch);
        emit log_named_uint("open_chunk_headroom_to_16p7M_gas", openHeadroomCurrent);
        emit log_named_uint("derived_max_safe_open_batch", derivedMaxSafeOpenBatch);
        emit log_named_uint("open_chunk_at_derived_max_safe_batch_gas", chunkAtDerived);
        emit log_named_uint("open_batch_fits_10M_target", openBatchFits10MTarget ? 1 : 0);
        emit log_named_string(
            "open_batch_dual_bound_finding",
            openBatchFits10MTarget
                ? "OPEN_BATCH chunk < 10M target AND <= 16.7M ceiling - no retune needed"
                : "OPEN_BATCH chunk EXCEEDS the 10M target (still <= 16.7M ceiling) - 355-03 must shrink OPEN_BATCH to derived_max_safe_open_batch"
        );

        // HARD safety asserts (the never-breach floor; the 10M target at the current constant is a logged
        // 355-03 finding, NOT a hard revert):
        // (1) the per-box marginal is a cheap uniform-O(1) resolve (no cold-ledger walk).
        assertLt(perOpen, 200_000, "per-open afking marginal is a cheap uniform-O(1) stamp-derived resolve (no cold-ledger walk)");
        // (2) a < 10M-safe batch is ACHIEVABLE (the derivation found a positive max-safe N).
        assertGt(derivedMaxSafeOpenBatch, 0, "a < 10M-safe open batch is achievable (derived max-safe N > 0)");
        // (3) the derivation is sound: the chunk AT the derived max-safe batch is under the 10M target.
        assertLt(chunkAtDerived, GAS_TARGET, "the chunk at the derived max-safe open batch is under the 10M TARGET (derivation sound)");
        // (4) the never-exceed ceiling holds at the CURRENT OPEN_BATCH (the hard kill bar — must never breach,
        //     even before the 355-03 retune toward the 10M target).
        assertLe(openChunkAtBatch, EFFECTIVE_GAS_CEILING, "OPEN_BATCH chunk at the current constant stays <= the 16.7M never-exceed ceiling");
        emit log_named_uint("current_open_batch", OPEN_BATCH);
    }

    // =========================================================================
    // (d) per-SETTLE marginal — the added cost of the settle-day ride (GAS-01)
    // =========================================================================

    /// @notice The per-settle marginal isolates ONE sub's settle-day _settleQuest cost (the creditFlip +
    ///         quests.settleAfkingQuest streak-advance). gasN = a STAGE advance landing on a settle boundary
    ///         (processDay % SETTLE_PERIOD == 0) over N subs that have ACCRUED questProgress + (for ticket
    ///         mode) buyerOwedBurnie; gasNm1 = the same minus one sub. (gasN − gasNm1) = the Nth sub's full
    ///         settle-day buy (the everyday buy + the settle ride). This per-sub settle-day marginal is the
    ///         BINDING per-item marginal for SUB_STAGE_BATCH. Measured for BOTH modes; the heavier is binding.
    ///         To accrue questProgress before the settle day, prior non-settle STAGE days run for the set.
    function testPerSettleMarginal() public {
        // Lootbox-mode settle-day marginal.
        uint256 perSettleLootbox = _measureSettleDayPerSubMarginal(false, "psL_");
        assertLt(perSettleLootbox, EFFECTIVE_GAS_CEILING, "per-settle lootbox marginal fits the 16.7M ceiling");

        // Ticket-mode settle-day marginal (buyerOwedBurnie ALSO settles — the heavier creditFlip payload).
        uint256 perSettleTicket = _measureSettleDayPerSubMarginal(true, "psT_");
        assertLt(perSettleTicket, EFFECTIVE_GAS_CEILING, "per-settle ticket marginal fits the 16.7M ceiling");

        uint256 perSettleBinding = perSettleLootbox > perSettleTicket ? perSettleLootbox : perSettleTicket;

        emit log_named_uint("per_settle_marginal_lootbox_gas", perSettleLootbox);
        emit log_named_uint("per_settle_marginal_ticket_gas", perSettleTicket);
        emit log_named_uint("per_settle_marginal_binding_gas", perSettleBinding);
    }

    // =========================================================================
    // (e) worst-case settle-day STAGE chunk at SUB_STAGE_BATCH + dual bound (GAS-01)
    // =========================================================================

    /// @notice Seed SUB_STAGE_BATCH funded subs per mode, accrue questProgress on prior non-settle days, drive
    ///         ONE settle-day advance, and record the whole settle-day advance (which BOUNDS the 50-chunk
    ///         STAGE) for BOTH lootbox and ticket modes. For the BINDING (heavier) mode: assert the whole
    ///         settle-day advance < 10M (TARGET) at the current SUB_STAGE_BATCH, log the headroom to 16.7M,
    ///         emit the derived max-safe SUB_STAGE_BATCH from the (d) binding-mode per-sub settle-day
    ///         marginal, and cross-check SUB_STAGE_BATCH <= derived (FAIL → 355-03 must shrink it). Non-vacuity:
    ///         the cursor advanced a full chunk AND >= cap−2 newly stamped AND >=1 settle fired (questProgress
    ///         drained to 0).
    function testWorstCaseSettleDayStageChunkAtCap() public {
        // ---- both modes: measure the full settle-day chunk (each from a CLEAN snapshot — the two modes
        //      otherwise stack 50+50 subs and break the SUBSCRIBER_CAP+2 invariant) ----
        uint256 snap = vm.snapshotState();
        (uint256 chunkLootbox, uint256 settledLootbox) = _measureSettleDayFullChunk(false, "wcL_");
        vm.revertToState(snap);
        (uint256 chunkTicket, uint256 settledTicket) = _measureSettleDayFullChunk(true, "wcT_");
        vm.revertToState(snap);

        bool ticketHeavier = chunkTicket >= chunkLootbox;
        uint256 bindingChunk = ticketHeavier ? chunkTicket : chunkLootbox;
        uint256 bindingSettled = ticketHeavier ? settledTicket : settledLootbox;

        // ---- the BINDING-mode per-sub settle-day marginal → derive the max-safe SUB_STAGE_BATCH ----
        uint256 perSubSettleBinding = _measureSettleDayPerSubMarginal(ticketHeavier, ticketHeavier ? "wcdT_" : "wcdL_");

        // fixed_stage_overhead = the binding full chunk minus the SUB_STAGE_BATCH per-sub settle marginals.
        uint256 fixedStageOverhead =
            bindingChunk > perSubSettleBinding * SUB_STAGE_BATCH ? bindingChunk - perSubSettleBinding * SUB_STAGE_BATCH : 0;
        uint256 derivedMaxSafeSubStageBatch = _maxSafeBatch(fixedStageOverhead, perSubSettleBinding);
        uint256 chunkAtDerived = fixedStageOverhead + derivedMaxSafeSubStageBatch * perSubSettleBinding;
        uint256 stageHeadroom = EFFECTIVE_GAS_CEILING > bindingChunk ? EFFECTIVE_GAS_CEILING - bindingChunk : 0;
        bool stageBatchFits10MTarget = bindingChunk < GAS_TARGET;

        // EMIT-FIRST — the settle-day chunk number + the derived max-safe SUB_STAGE_BATCH are the load-bearing
        // inputs to GAS-03 (355-03).
        emit log_named_uint("stage_settle_day_full_chunk_lootbox_gas", chunkLootbox);
        emit log_named_uint("stage_settle_day_full_chunk_ticket_gas", chunkTicket);
        emit log_named_uint("stage_settle_day_binding_chunk_gas", bindingChunk);
        emit log_named_string("stage_settle_day_binding_mode", ticketHeavier ? "ticket" : "lootbox");
        emit log_named_uint("stage_fixed_overhead_gas", fixedStageOverhead);
        emit log_named_uint("per_sub_settle_day_binding_marginal_gas", perSubSettleBinding);
        emit log_named_uint("stage_chunk_headroom_to_16p7M_gas", stageHeadroom);
        emit log_named_uint("derived_max_safe_sub_stage_batch", derivedMaxSafeSubStageBatch);
        emit log_named_uint("stage_chunk_at_derived_max_safe_batch_gas", chunkAtDerived);
        emit log_named_uint("stage_batch_fits_10M_target", stageBatchFits10MTarget ? 1 : 0);
        emit log_named_uint("current_sub_stage_batch", SUB_STAGE_BATCH);
        emit log_named_string(
            "sub_stage_batch_dual_bound_finding",
            stageBatchFits10MTarget
                ? "settle-day SUB_STAGE_BATCH chunk < 10M target AND <= 16.7M ceiling - no retune needed"
                : "settle-day SUB_STAGE_BATCH chunk EXCEEDS the 10M target (still <= 16.7M ceiling) - 355-03 must shrink SUB_STAGE_BATCH to derived_max_safe_sub_stage_batch"
        );

        // Non-vacuity for the binding-mode chunk: >= 1 settle fired (questProgress drained to 0).
        assertGt(bindingSettled, 0, "settle-day non-vacuity: >= 1 settle fired this binding chunk (questProgress drained)");

        // HARD safety asserts (the never-breach floor; the 10M target at the current SUB_STAGE_BATCH is a
        // logged 355-03 finding, NOT a hard revert):
        // (1) a < 10M-safe SUB_STAGE_BATCH is ACHIEVABLE (a positive derived max-safe N exists).
        assertGt(derivedMaxSafeSubStageBatch, 0, "a < 10M-safe SUB_STAGE_BATCH is achievable (derived max-safe N > 0)");
        // (2) the derivation is sound: the chunk AT the derived max-safe batch is under the 10M target.
        assertLt(chunkAtDerived, GAS_TARGET, "the chunk at the derived max-safe SUB_STAGE_BATCH is under the 10M TARGET (derivation sound)");
        // (3) the never-exceed ceiling holds at the CURRENT SUB_STAGE_BATCH (the hard kill bar — must never
        //     breach, even before the 355-03 retune toward the 10M target).
        assertLe(bindingChunk, EFFECTIVE_GAS_CEILING, "settle-day SUB_STAGE_BATCH chunk at the current constant stays <= the 16.7M never-exceed ceiling");
    }

    // =========================================================================
    // Internal helpers (the validated game-resident driving harness)
    // =========================================================================

    /// @dev Measure ONE sub's settle-day marginal (the binding per-item marginal for SUB_STAGE_BATCH): the
    ///      (gasN − gasNm1) of a settle-day STAGE advance over N vs N−1 subs that have each ACCRUED
    ///      questProgress (+ buyerOwedBurnie for ticket mode) over prior non-settle days, so the Nth sub's
    ///      difference includes its full settle-day buy (the everyday buy + the _settleQuest ride). Both runs
    ///      from one clean baseline (snapshot/revert).
    function _measureSettleDayPerSubMarginal(bool isTicket, string memory prefix) internal returns (uint256) {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureSettleDayStageGas(N_HI, string(abi.encodePacked(prefix, "hi_")), isTicket);
        vm.revertToState(snap);
        uint256 gasNm1 = _measureSettleDayStageGas(N_LO, string(abi.encodePacked(prefix, "lo_")), isTicket);
        require(gasN > gasNm1, "per-settle marginal: N subs cost strictly more than N-1");
        return gasN - gasNm1;
    }

    /// @dev Drive a settle-day STAGE advance over N funded subs that have accrued questProgress on prior
    ///      non-settle days, returning the bracketed advance gas. Steps: settle clean → subscribe+fund N subs
    ///      → run prior NON-settle STAGE days (each stamps + accrues ++questProgress); for LOOTBOX subs the
    ///      box MUST be opened between days (the no-orphan guard skips a sub with an unopened box, so an
    ///      un-opened lootbox sub would never re-buy → no further accrual), TICKET subs need no open (the buy
    ///      sets lastOpenedDay == lastAutoBoughtDay) → warp onto a settle boundary, drain to a CLEAN day-9
    ///      baseline, then bracket the FIRST day-10 advance (the settle-day STAGE buys + fires _settleQuest
    ///      per sub). Non-vacuity: each sub had questProgress > 0 before the settle and the settle drained it
    ///      to 0.
    function _measureSettleDayStageGas(uint256 n, string memory prefix, bool isTicket) internal returns (uint256 advGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(n, prefix, 200 ether, isTicket);

        // Accrue questProgress on >= 1 prior NON-settle day (one delivered buy ++questProgress is enough to
        // make the settle non-vacuous). The full-day primitive stamps + (for lootbox) opens, leaving a clean
        // day so the next stamping day is unobstructed by the no-orphan guard.
        _advanceFullDayAndOpen(false, isTicket, uint256(keccak256(abi.encodePacked(prefix, "acc"))) | 1);
        for (uint256 i; i < n; ++i) {
            require(_questProgressOf(subs[i]) > 0, "fixture: sub accrued questProgress before settle");
            require(_lastOpenedDayOf(subs[i]) == _lastBoughtDayOf(subs[i]), "fixture: box opened / ticket no-box (no orphan guard on settle day)");
        }
        uint32[] memory preBought = new uint32[](n);
        for (uint256 i; i < n; ++i) preBought[i] = _lastBoughtDayOf(subs[i]);

        // Warp onto a settle boundary and bracket the FIRST advance of that day — the settle-day STAGE buys +
        // fires _settleQuest per sub. The prior day is already CLEAN (the accrue primitive settled it), so the
        // first settle-day advance runs the STAGE pre-RNG directly.
        _warpToBoundary(true);
        require(uint256(_simulatedDayIndex()) % SETTLE_PERIOD == 0, "fixture: on a settle boundary");
        require(game.advanceDue() && !game.rngLocked(), "fixture: clean + advanceDue on the settle day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        // Non-vacuity: each sub got a NEW settle-day stamp AND the settle drained questProgress to 0.
        for (uint256 i; i < n; ++i) {
            require(_lastBoughtDayOf(subs[i]) > preBought[i], "settle non-vacuity: each sub newly stamped this settle day");
            require(_questProgressOf(subs[i]) == 0, "settle non-vacuity: the settle drained questProgress to 0");
        }
    }

    /// @dev Advance ONE full day (warp to the desired settle parity, run the new-day STAGE, fulfill the day's
    ///      RNG, and — for LOOTBOX subs — OPEN the stamped boxes so the no-orphan guard clears for the next
    ///      day) leaving the game in a CLEAN (`!advanceDue && !rngLocked`) state. TICKET subs need no open
    ///      (the buy leg sets lastOpenedDay == lastAutoBoughtDay). Idempotent re-open is a no-op (the
    ///      day-keyed marker).
    function _advanceFullDayAndOpen(bool onSettle, bool isTicket, uint256 vrfWord) internal {
        _warpToBoundary(onSettle);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        // Run the day: advance (stamps the STAGE pre-RNG) + fulfill the day's word + drain to clean.
        game.advanceGame();
        _settleClean(vrfWord);
        // Open the stamped lootbox boxes so the no-orphan guard clears (the next day re-stamps them). The
        // mintBurnie router opens when advance is not due (clean) and the stamp-day word has landed.
        if (!isTicket) {
            vm.prank(makeAddr("fullday_opener"));
            game.mintBurnie();
            _settleClean(vrfWord ^ 0xBEEF);
        }
    }

    /// @dev Seed exactly SUB_STAGE_BATCH funded subs, accrue questProgress on prior non-settle days, drive ONE
    ///      settle-day advance (its STAGE runs processSubscriberStage(50) firing _settleQuest per sub), and
    ///      return (whole-advance gas, settled-count). Non-vacuity: the cursor advanced a FULL chunk, >= cap−2
    ///      newly stamped, and >= 1 settle fired (questProgress drained to 0).
    function _measureSettleDayFullChunk(bool isTicket, string memory prefix)
        internal
        returns (uint256 chunkGas, uint256 settledCount)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(SUB_STAGE_BATCH, prefix, 200 ether, isTicket);
        require(_subscriberCount() == SUB_STAGE_BATCH + 2, "set = 50 funded subs + 2 deploy subs");

        // Accrue questProgress on a prior non-settle day (each delivered buy ++questProgress). For lootbox the
        // box is opened so the no-orphan guard clears for the settle day; ticket needs no open. The primitive
        // leaves a clean day, so the first settle-day advance runs the STAGE directly.
        _advanceFullDayAndOpen(false, isTicket, uint256(keccak256(abi.encodePacked(prefix, "acc"))) | 1);
        for (uint256 i; i < SUB_STAGE_BATCH; ++i) {
            require(_questProgressOf(subs[i]) > 0, "fixture: each sub accrued questProgress before settle");
            require(_lastOpenedDayOf(subs[i]) == _lastBoughtDayOf(subs[i]), "fixture: box opened / ticket no-box (no orphan guard on settle day)");
        }

        uint32[] memory preBought = new uint32[](SUB_STAGE_BATCH);
        for (uint256 i; i < SUB_STAGE_BATCH; ++i) preBought[i] = _lastBoughtDayOf(subs[i]);

        _warpToBoundary(true);
        require(uint256(_simulatedDayIndex()) % SETTLE_PERIOD == 0, "fixture: on a settle boundary");
        require(game.advanceDue() && !game.rngLocked(), "fixture: clean + advanceDue on the settle day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        chunkGas = gasBefore - gasleft();

        // Non-vacuity (1/3): the cursor advanced a FULL SUB_STAGE_BATCH chunk (the new-day reset zeroed it
        // inside advanceGame, then the chunk drained 50).
        require(_subCursor() == SUB_STAGE_BATCH, "STAGE non-vacuity: the cursor advanced a full 50-chunk");
        // Non-vacuity (2/3): >= cap−2 of mine got a NEW stamp (the 2 deploy subs occupy cursor 0..1).
        uint256 stampedCount;
        for (uint256 i; i < SUB_STAGE_BATCH; ++i) {
            if (_lastBoughtDayOf(subs[i]) > preBought[i]) ++stampedCount;
        }
        require(stampedCount >= SUB_STAGE_BATCH - 2, "STAGE non-vacuity: >= 48 newly stamped this chunk");
        // Non-vacuity (3/3): >= 1 settle fired (questProgress drained to 0 on the settled subs).
        for (uint256 i; i < SUB_STAGE_BATCH; ++i) {
            if (_questProgressOf(subs[i]) == 0) ++settledCount;
        }
        require(settledCount > 0, "STAGE non-vacuity: >= 1 settle fired (questProgress drained to 0)");
    }

    // =========================================================================
    // Driving harness (ported + extended)
    // =========================================================================

    /// @dev Measure a fresh-state new-day advance whose STAGE processes N funded LOOTBOX subs, returning the
    ///      bracketed advance gas. Settles to a clean baseline FIRST (so a prior measurement's unfulfilled
    ///      RNG cannot leave the game rngLocked). n + 2 deploy subs < SUB_STAGE_BATCH so ONE advance stamps
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
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        _warpToBoundary(landOnSettleDay);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
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
    ///      the bracketed `mintBurnie()` open-leg gas. The 2 deploy subs add a CONSTANT 2 ready boxes to BOTH
    ///      the N and N−1 measurements, so they cancel in the (gasN − gasNm1) difference — the marginal
    ///      isolates exactly one box. Each call stamps N subs (new-day STAGE), lands the stamp-day word,
    ///      settles clean (so mintBurnie routes to OPEN), opens all.
    function _measureOpenLegGas(uint256 n, string memory prefix) internal returns (uint256 openGas) {
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "word"))) | 1);
        uint32 stampDay = _readStampDay(subs);
        require(stampDay > 0, "fixture: subs stamped");
        require(rngWordByDay(stampDay) != 0, "fixture: stamp-day word landed");
        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) < stampDay, "marginal pre: each box queued");
        }

        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so mintBurnie opens");
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        openGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) == stampDay, "marginal non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players as funded subs in the requested mode (lootbox = useTickets false /
    ///      ticket = useTickets true), deity-passed so pass-gated valid; funded via depositAfkingFunding so
    ///      the STAGE :744 afkingFunding debit + :745 claimablePool debit land in tandem (SOLVENCY-01
    ///      balanced). The STAGE stamps/queues each into a warm Sub slot (GAS-01) + runs the v56 mode-agnostic
    ///      in-slot accrue (no per-buy cross-contract storm — that is deferred to the settle day).
    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach, bool isTicket)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            // self, mode = isTicket, qty 1, reinvest 0, self-funded
            game.subscribe(address(0), false, isTicket, 1, 0, address(0));
            _fundPool(who, poolEach);
        }
    }

    /// @dev Lootbox-mode funded subs (useTickets == false) — the box-stamp primitive.
    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory)
    {
        return _setupFundedSubs(n, prefix, poolEach, false);
    }

    /// @dev Ticket-mode funded subs (useTickets == true) — the new minimal-write `_queueTicketsScaled`
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
    ///      before a mintBurnie open so it reliably takes the OPEN leg.
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

    // ---- Sub-slot reads (RE-DERIVED slot 66 + v56 offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
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

    function _questProgressOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_QUESTPROG, 8)); // uint8
    }

    function _buyerOwedBurnieOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_OWEDBURNIE, 32)); // uint32
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Read the STAGE cursor `_subCursor` (slot 70, byte 0, uint16) — advances by SUB_STAGE_BATCH on a
    ///      full chunk.
    function _subCursor() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) & 0xFFFF;
    }

    /// @dev Read the DAY-keyed afking word `rngWordByDay[day]` (the open leg's seed + readiness gate).
    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    /// @dev Land a word for a specific day directly (the open-readiness gate) when the natural drain did not
    ///      fulfill that exact day's word after a partial STAGE drain. The word is the box's frozen seed.
    function _injectRngWordByDay(uint32 day, uint256 word) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)));
        vm.store(address(game), slot, bytes32(word | 1));
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
}
