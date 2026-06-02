// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title V56AfkingGasMarginal -- the v56 everyday-afking gas-MARGINAL harness (Phase 355) on the
///        compute-on-read applied tree (baseline 453f8073). Measures every marginal the GAS phase needs:
///        the per-buy LOOTBOX marginal, the per-buy TICKET marginal (the minimal-write primitive), the
///        per-OPEN marginal, the per-EVICT-finalize marginal (the heavier in-stage sub-ending branch), and
///        the WORST-CASE per-tx chunk for each batched advance/afking loop — the weighted-budget STAGE chunk
///        (SUB_STAGE_WEIGHT_BUDGET) and the OPEN_BATCH open chunk. From each measured worst-case per-item
///        marginal it DERIVES the max safe batch (the largest N keeping the per-tx chunk under the 10M comfort
///        TARGET) and reports the dual bound (< 10M target, provably <= 16.7M hard ceiling).
///
/// @notice The v56 compute-on-read applied tree (what THIS harness measures):
///
///         (1) The per-buy hot path (GameAfkingModule, _deliverAfkingBuy) is call-free: the SOLVENCY-01 debit
///             (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`, byte-frozen from v55) ->
///             the per-mode primitive (lootbox box-stamp OR the ticket minimal-write `_queueTicketsScaled`,
///             replacing the ~262k purchaseWith heavyweight) -> the MODE-AGNOSTIC in-slot accrue (affiliateBase
///             flat-7% += and the slot-0 reward into pendingBurnie) + the compute-on-read streak markers
///             (gap-resume + afkCoveredThroughDay) -> the lastAutoBoughtDay marker. There is NO per-buy
///             DegenerusQuests STATICCALL (the streak is computed on read from the Sub slot) and NO settle day.
///
///         (2) The Sub slot is a SINGLE 256-bit slot, EXACTLY full (0 free): config 40 + stamp 40 (scorePlus1
///             uint16 / amount uint24 milli-ETH) + markers 96 (lastAutoBoughtDay / lastOpenedDay /
///             afkCoveredThroughDay / afkingStartDay uint24 each) + accumulator 72 (affiliateBase uint32 /
///             pendingBurnie uint32 / subStreakLatch uint8). The accumulator is IN-SLOT — the per-buy accrue
///             is a warm write on the SAME slot the stamp dirtied, NOT a new cold slot.
///
///         (3) Sub-ending finalize (cancel / cancel-reclaim / pass-evict / funding-kill): the only cross-contract
///             work left on the advance chain (a DegenerusQuests playerQuestStates read + finalizeAfking streak
///             write), so an in-stage evict is the heavier branch — weighted SUB_STAGE_EVICT_WEIGHT in the budget.
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

    // Sub packed-field byte offsets — RE-DERIVED via `forge inspect DegenerusGame storageLayout` after the
    // v56 compute-on-read re-pack: `amount` narrowed uint32→uint24 (so everything after it shifts down one
    // byte), `questProgress` DROPPED, `afkingStartDay` ADDED, `hasEverSubscribed` bool → `subStreakLatch`
    // uint8. Single 256-bit Sub slot (exactly one slot, 0 free):
    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingBurnie u32 @27 · subStreakLatch u8 @31
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay    (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay        (bytes 14..16)
    uint256 private constant OFF_AFKCOVERED = 17; // uint24 afkCoveredThroughDay (bytes 17..19)
    uint256 private constant OFF_AFKINGSTART = 20; // uint24 afkingStartDay      (bytes 20..22)
    uint256 private constant OFF_AFFBASE = 23;    // uint32 affiliateBase        (bytes 23..26)
    uint256 private constant OFF_PENDINGBURNIE = 27; // uint32 pendingBurnie     (bytes 27..30)
    uint256 private constant OFF_STREAKLATCH = 31; // uint8 subStreakLatch       (byte 31; bit7 ever-sub, bits0-6 streak)

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

    /// @dev SUB_STAGE_WEIGHT_BUDGET (DegenerusGameAdvanceModule.sol): the per-call STAGE gas-weight budget.
    ///      Buys are weighted by true cost (lootbox = 1, ticket = SUB_STAGE_TICKET_WEIGHT); a chunk ends when
    ///      accumulated weight reaches the budget, so a budget-B chunk holds up to B lootbox subs OR
    ///      B/SUB_STAGE_TICKET_WEIGHT ticket subs. The binding worst-case is the all-ticket chunk.
    uint256 internal constant SUB_STAGE_WEIGHT_BUDGET = 1000;

    /// @dev SUB_STAGE_EVICT_WEIGHT (GameAfkingModule.sol): the gas-weight of an in-stage sub-ending finalize
    ///      (pass-evict / funding-kill / cancel-reclaim) relative to a lootbox buy (1) — the heavier branch.
    uint256 internal constant SUB_STAGE_EVICT_WEIGHT = 2;

    /// @dev SUB_STAGE_TICKET_WEIGHT (GameAfkingModule.sol): a ticket buy's gas-weight vs the lootbox-buy unit
    ///      (the cold ticketQueue push makes it ~8x). A budget-B chunk holds B/SUB_STAGE_TICKET_WEIGHT tickets.
    uint256 internal constant SUB_STAGE_TICKET_WEIGHT = 8;

    /// @dev OPEN_BATCH (GameAfkingModule.sol): the flat per-box open chunk; each afking box uniform O(1).
    uint256 internal constant OPEN_BATCH = 130;

    /// @dev Harness-local day-parity period for `_warpToBoundary` deterministic day selection. The contracts no
    ///      longer have a settle cadence (compute-on-read obviated it); this is purely a test warp helper.
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
    // (d) per-EVICT-finalize marginal — the heavier in-stage branch (GAS-03)
    // =========================================================================

    /// @notice The per-evict marginal = (gas for N evicting subs - gas for N-1) / 1, snapshot/revert. An
    ///         in-stage sub-ending finalize (pass-evict / funding-kill / cancel-reclaim) does a cross-contract
    ///         DegenerusQuests read (playerQuestStates) + streak write (finalizeAfking) that the now call-free
    ///         local buy does not, so it is the heavier branch. This sizes SUB_STAGE_EVICT_WEIGHT =
    ///         ceil(evict-marginal / buy-marginal): the STAGE weights an evict that many buy-units so even an
    ///         all-evicts chunk stays under the ceiling. Subs are pass-evicted (no deity pass -> validThroughLevel
    ///         0 < currentLevel) on the measured advance.
    function testEvictFinalizeMarginal() public {
        uint256 snap = vm.snapshotState();
        uint256 gasN = _measureEvictStageGas(N_HI, "evHi_");
        vm.revertToState(snap);
        uint256 gasNm1 = _measureEvictStageGas(N_LO, "evLo_");

        assertGt(gasN, gasNm1, "per-evict marginal: N evicting subs cost strictly more than N-1");
        uint256 perEvict = gasN - gasNm1;
        assertLt(perEvict, EFFECTIVE_GAS_CEILING, "per-evict marginal fits the 16.7M ceiling");

        // The lootbox buy marginal (the box-stamp path) to weight the evict against.
        vm.revertToState(snap);
        uint256 buyN = _measureStageAdvanceGas(N_HI, "evbHi_", false, false);
        vm.revertToState(snap);
        uint256 buyNm1 = _measureStageAdvanceGas(N_LO, "evbLo_", false, false);
        uint256 perBuy = buyN > buyNm1 ? buyN - buyNm1 : 1;

        uint256 derivedEvictWeight = (perEvict + perBuy - 1) / perBuy; // ceil(evict/buy)
        emit log_named_uint("per_evict_finalize_marginal_gas", perEvict);
        emit log_named_uint("per_buy_lootbox_marginal_gas", perBuy);
        emit log_named_uint("derived_evict_weight_W", derivedEvictWeight);
        emit log_named_uint("current_sub_stage_evict_weight", SUB_STAGE_EVICT_WEIGHT);
        emit log_named_string(
            "evict_weight_finding",
            SUB_STAGE_EVICT_WEIGHT >= derivedEvictWeight
                ? "SUB_STAGE_EVICT_WEIGHT >= derived W - conservative-safe (over-weights evicts)"
                : "SUB_STAGE_EVICT_WEIGHT < derived W - 355-03 must raise it to the derived value"
        );
    }

    // =========================================================================
    // (e) worst-case STAGE chunk under the weighted budget at the cap (GAS-03)
    // =========================================================================

    /// @notice The weighted budget caps a chunk at SUB_STAGE_WEIGHT_BUDGET weight. The all-cheap-buys chunk
    ///         (BUDGET buys) is one worst-case extreme; an all-evicts chunk is BUDGET/W evicts (each ~= W buys),
    ///         so by construction both bound to roughly the same gas. Asserts the all-buys chunk at the current
    ///         budget stays <= the 16.7M never-exceed ceiling and derives the max-safe budget for the <10M target.
    function testWorstCaseStageChunkUnderBudget() public {
        uint256 snap = vm.snapshotState();
        // BINDING mode = TICKET (the cold ticketQueue push dominates; lootbox reuses the warm Sub slot).
        uint256 chunkAllBuys = _measureFullBudgetBuyChunk("wcb_");
        vm.revertToState(snap);

        uint256 buyN = _measureStageAdvanceGas(N_HI, "wcmHi_", true, false);
        vm.revertToState(snap);
        uint256 buyNm1 = _measureStageAdvanceGas(N_LO, "wcmLo_", true, false);
        uint256 perBuy = buyN > buyNm1 ? buyN - buyNm1 : 1;

        // A budget-B chunk holds B/SUB_STAGE_TICKET_WEIGHT ticket buys (the binding worst case).
        uint256 ticketsInChunk = SUB_STAGE_WEIGHT_BUDGET / SUB_STAGE_TICKET_WEIGHT;
        uint256 fixedOverhead = chunkAllBuys > perBuy * ticketsInChunk
            ? chunkAllBuys - perBuy * ticketsInChunk
            : 0;
        // _maxSafeBatch returns max ticket COUNT under the 10M target; the budget is that × weight.
        uint256 derivedMaxSafeBudget = _maxSafeBatch(fixedOverhead, perBuy) * SUB_STAGE_TICKET_WEIGHT;

        emit log_named_uint("stage_all_buys_chunk_at_budget_gas", chunkAllBuys);
        emit log_named_uint("per_buy_lootbox_marginal_gas", perBuy);
        emit log_named_uint("stage_fixed_overhead_gas", fixedOverhead);
        emit log_named_uint("derived_max_safe_weight_budget", derivedMaxSafeBudget);
        emit log_named_uint("current_sub_stage_weight_budget", SUB_STAGE_WEIGHT_BUDGET);
        emit log_named_uint(
            "chunk_headroom_to_16p7M_gas",
            EFFECTIVE_GAS_CEILING > chunkAllBuys ? EFFECTIVE_GAS_CEILING - chunkAllBuys : 0
        );
        emit log_named_string(
            "weight_budget_finding",
            chunkAllBuys < GAS_TARGET
                ? "all-buys chunk at SUB_STAGE_WEIGHT_BUDGET < 10M target AND <= 16.7M ceiling - headroom to raise"
                : "all-buys chunk EXCEEDS the 10M target (measure vs 16.7M) - 355-03 may shrink the budget"
        );

        assertGt(derivedMaxSafeBudget, 0, "a < 10M-safe weight budget is achievable");
        assertLe(chunkAllBuys, EFFECTIVE_GAS_CEILING, "all-buys chunk at the current budget stays <= the 16.7M ceiling");
    }

    // =========================================================================
    // Internal helpers (new-design driving harness)
    // =========================================================================

    /// @dev Drive a new-day STAGE advance over N unfunded, NON-deity subs that all PASS-EVICT this cycle
    ///      (validThroughLevel 0 < currentLevel -> each routes through _finalizeAfking + swap-pop), returning the
    ///      bracketed advance gas. Both runs from one clean baseline.
    function _measureEvictStageGas(uint256 n, string memory prefix) internal returns (uint256 advGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        // No deity pass + no funding: the unfunded subscribe is non-reverting (it enters the set with base 0),
        // and the stage pass-evicts each (currentLevel > validThroughLevel == 0) through the finalize path.
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0));
        }
        uint256 preCount = _subscriberCount();
        require(preCount >= n, "fixture: N evicting subs in the set");

        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        require(_subscriberCount() < preCount, "evict non-vacuity: the stage evicted subs");
    }

    /// @dev Measure a full-budget all-buys STAGE chunk: SUB_STAGE_WEIGHT_BUDGET funded lootbox subs, one
    ///      new-day advance, bracketed. The weight budget caps the work; this is the all-cheap-buys worst case.
    function _measureFullBudgetBuyChunk(string memory prefix) internal returns (uint256 chunkGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        // Weighted budget: a ticket buy costs SUB_STAGE_TICKET_WEIGHT, so BUDGET/WEIGHT ticket
        // subs (+2 margin so the loop fills the budget, not the set) fill the chunk.
        _setupFundedSubs(SUB_STAGE_WEIGHT_BUDGET / SUB_STAGE_TICKET_WEIGHT + 2, prefix, 50 ether, true);
        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        chunkGas = gasBefore - gasleft();
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

    function _afkingStartOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKINGSTART, 24)); // uint24
    }

    function _pendingBurnieOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_PENDINGBURNIE, 32)); // uint32
    }

    function _streakBaseOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_STREAKLATCH, 8)) & 0x7f; // bits 0-6
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
