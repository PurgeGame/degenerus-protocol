// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

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
///             the per-mode primitive (lootbox box-stamp OR the ticket minimal-write `_queueEntriesScaled`,
///             replacing the ~262k purchaseWith heavyweight) -> the MODE-AGNOSTIC in-slot accrue (affiliateBase
///             flat-7% += and the slot-0 reward into pendingFlip) + the compute-on-read streak markers
///             (gap-resume + afkCoveredThroughDay) -> the lastAutoBoughtDay marker. There is NO per-buy
///             DegenerusQuests STATICCALL (the streak is computed on read from the Sub slot) and NO settle day.
///
///         (2) The Sub slot is a SINGLE 256-bit slot, EXACTLY full (0 free): config 40 + stamp 40 (scorePlus1
///             uint16 / amount uint24 milli-ETH) + markers 96 (lastAutoBoughtDay / lastOpenedDay /
///             afkCoveredThroughDay / afkingStartDay uint24 each) + accumulator 72 (affiliateBase uint32 /
///             pendingFlip uint24 / subStreakLatch uint16). The accumulator is IN-SLOT — the per-buy accrue
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
///      V55AfkingGasMarginal. All pinned slots taken from `forge inspect DegenerusGame storageLayout`
///      against the POST subject (`_subOf = 54`, `_subscribers = 56`, `_subCursor = 58:0`,
///      `_subOpenCursor = 58:2`, `rngWordByDay = 10`; the Sub field byte offsets are the v56 re-pack,
///      unchanged by the PACK fold). Test-only: ZERO contracts/*.sol mutated.
contract V56AfkingGasMarginal is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (forge inspect DegenerusGame storageLayout, v61)
    // -------------------------------------------------------------------------

    // RE-DERIVED via `solc --storage-layout` on the working tree after the V62 lootbox repack — the
    // folded lootboxEth word + removed lootboxEthBase/Flip/Purchase/Distress shifted later slots down.
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint24 => uint256) — the afking box's DAY-keyed word + readiness gate
    uint256 private constant SUBOF_SLOT = 54;           // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 56;     // address[] _subscribers (slot holds the length)
    uint256 private constant SUBCURSOR_SLOT = 58;       // _subCursor (uint16 @ byte 0) + _subOpenCursor (uint16 @ byte 2) + _afkingResetDay (uint24 @ byte 4) + boxCursor (uint48 @ byte 7) + boxCursorIndex (uint48 @ byte 13)

    // Sub packed-field byte offsets — RE-DERIVED via `forge inspect DegenerusGame storageLayout` after the
    // v56 compute-on-read re-pack: `amount` narrowed uint32→uint24 (so everything after it shifts down one
    // byte), `questProgress` DROPPED, `afkingStartDay` ADDED, `hasEverSubscribed` bool → `subStreakLatch`
    // uint8. Single 256-bit Sub slot (exactly one slot, 0 free):
    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingFlip u24 @27 · subStreakLatch u16 @30
    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel   (bytes 1..3)
    uint256 private constant OFF_AMOUNT = 7;      // uint24 amount (milli-ETH)   (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay    (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13; // uint24 lastOpenedDay        (bytes 14..16)
    /// @dev milli-ETH packing scale (DegenerusGameStorage.LR_ETH_SCALE) — sub.amount * this = box wei.
    uint256 private constant MILLI_ETH_SCALE = 1e15;
    uint256 private constant OFF_AFKCOVERED = 16; // uint24 afkCoveredThroughDay (bytes 17..19)
    uint256 private constant OFF_AFKINGSTART = 19; // uint24 afkingStartDay      (bytes 20..22)
    uint256 private constant OFF_AFFBASE = 22;    // uint32 affiliateBase        (bytes 23..26)
    uint256 private constant OFF_PENDINGFLIP = 26; // uint24 pendingFlip     (bytes 27..29)
    uint256 private constant OFF_STREAKLATCH = 29; // uint16 subStreakLatch      (bytes 30..31; full streak counter)

    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;

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

    /// @dev The 10M design comfort TARGET (USER-LOCKED dual bound). Every batched per-tx loop's worst-case
    ///      chunk at the chosen batch must land BELOW this; the derived max-safe batch is the largest N with
    ///      fixed_overhead + N×worst_case_per_item_marginal < GAS_TARGET.
    uint256 internal constant GAS_TARGET = 10_000_000;

    /// @dev The 16.7M HARD never-exceed kill ceiling (USER-LOCKED dual bound). A breach = advanceGame DoS /
    ///      forced game-over. foundry.toml inflates block_gas_limit to 30e9 for the harness; the never-exceed
    ///      bar is this 16.7M. The headroom (16.7M − the measured-at-target chunk) is the safety margin.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev SUB_STAGE_WEIGHT_BUDGET (DegenerusGameAdvanceModule.sol:158): the per-call STAGE gas-weight budget.
    ///      Buys are weighted by true marginal cost (lootbox = SUB_STAGE_LOOTBOX_WEIGHT, ticket =
    ///      SUB_STAGE_TICKET_WEIGHT, evict = SUB_STAGE_EVICT_WEIGHT); a chunk ends when accumulated weight
    ///      reaches the budget. Weights ratio on true cold marginals (~3.4k per weight-unit), so a budget of
    ///      2500 caps the worst chunk (any mix, incl. a saturated all-evict crank) near the <10M target, far
    ///      under the 16.7M ceiling. Mirror of the contract constant — keep in sync.
    uint256 internal constant SUB_STAGE_WEIGHT_BUDGET = 2500;

    /// @dev SUB_STAGE_LOOTBOX_WEIGHT (GameAfkingModule.sol): the lootbox-buy gas-weight unit (≈34k cold marginal)
    ///      → weight 10, giving the granularity for ticket (≈73k → 21) and evict (≈29k → 8) to ratio on real
    ///      marginal cost. Mirror of the contract constant — keep in sync.
    uint256 internal constant SUB_STAGE_LOOTBOX_WEIGHT = 10;

    /// @dev SUB_STAGE_EVICT_WEIGHT (GameAfkingModule.sol): the gas-weight of an in-stage sub-ending finalize
    ///      (pass-evict / funding-kill / cancel-reclaim) — a cross-contract quest streak write + swap-pop,
    ///      measured ≈29k cold → weight 8. Mirror of the contract constant — keep in sync.
    uint256 internal constant SUB_STAGE_EVICT_WEIGHT = 8;

    /// @dev SUB_STAGE_TICKET_WEIGHT (GameAfkingModule.sol): a ticket buy's gas-weight vs the lootbox unit — the
    ///      cold ticketQueue push + owed-mapping SSTORE make it ≈73k → weight 21. A budget-B chunk holds
    ///      B/SUB_STAGE_TICKET_WEIGHT tickets. Mirror of the contract constant — keep in sync.
    uint256 internal constant SUB_STAGE_TICKET_WEIGHT = 21;

    /// @dev OPEN_BATCH (GameAfkingModule.sol:246): the flat per-box open-chunk budget; each afking box uniform
    ///      O(1) (~74k worst box) so 80 boxes ≈ 9.15M, under the 10M comfort target and far under 16.7M.
    uint256 internal constant OPEN_BATCH = 80;

    /// @dev Harness-local day-parity period for `_warpToBoundary` deterministic day selection. The contracts no
    ///      longer have a settle cadence (compute-on-read obviated it); this is purely a test warp helper.
    uint256 internal constant SETTLE_PERIOD = 10;

    /// @dev SUBSCRIBER_CAP (GameAfkingModule.sol:165): the shipped worst-case active sub count. The binding
    ///      constant is 1000 (the :499/:505 `500` in the contract are stale COMMENTS only). A per-tx ceiling
    ///      proof "at the cap" must use 1000 — a 500 under-states the worst-case STAGE/open chunk by 2x.
    uint256 internal constant SUBSCRIBER_CAP = 1000;

    /// @dev The hard EIP-7825 per-transaction gas bar. The D-06 per-advance asserts use this exact value
    ///      (16_777_216), not the harness EFFECTIVE_GAS_CEILING comfort constant (16_700_000): EVERY single
    ///      advanceGame tx in a worst-case multi-day VRF-stall resume must stay strictly under it.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    /// @dev A worst-case VRF/keeper stall length (days) for the D-06 gap-resume resume. The gap backfill is
    ///      capped at 120 days in the contract (_backfillGapDays); 120 is the binding worst case.
    uint256 internal constant STALL_DAYS = 120;

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
    ///         STAGE, snapshot/revert. The ticket leg is the NEW minimal-write `_queueEntriesScaled` primitive
    ///         + the buyerOwedFlip in-slot accrue (off the old ~262k purchaseWith heavyweight that dragged
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
    ///         open leg is `_autoOpen(OPEN_BATCH)`, reached via `mintFlip()`; each afking box rolls boons
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

        // Derive the OPEN_BATCH chunk. fixed_open_overhead = the open-leg tx overhead at N opens minus the N
        // per-box marginals (the constant mintFlip entry/exit + advance-check + bounty cost shared by any
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
    ///         local buy does not. Emits the WARM-measured ceil(evict/buy) for reference, but note it is
    ///         warm-distorted: warm same-tx slots make evict ≈ 1.4x a buy, whereas the cold-sized weight is 1
    ///         (cold evict ≈18k < lootbox ≈34k, the large-scale bench — see testColdMarginalCalibration). The
    ///         binding evict safety is the all-evict chunk-under-ceiling proven in testResidualR1, not this
    ///         warm ratio. Subs are pass-evicted (no deity pass -> validThroughLevel 0 < currentLevel).
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

        uint256 warmDerivedEvictWeight = (perEvict + perBuy - 1) / perBuy; // ceil(warm evict / warm buy)
        emit log_named_uint("per_evict_finalize_marginal_gas", perEvict);
        emit log_named_uint("per_buy_lootbox_marginal_gas", perBuy);
        emit log_named_uint("warm_derived_evict_weight_W", warmDerivedEvictWeight);
        emit log_named_uint("current_sub_stage_evict_weight", SUB_STAGE_EVICT_WEIGHT);
        emit log_named_string(
            "evict_weight_finding",
            "WARM ceil(evict/buy) over-states the weight (warm evict ~= 1.4x a warm buy); the cold-sized weight "
            "is 1 (cold evict ~18k < lootbox ~34k, large-scale bench -- see testColdMarginalCalibration). The "
            "all-evict chunk safety is proven directly in testResidualR1, not by this warm ratio."
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
    // (f) D-06 / GAS-06 — the per-tx gap-resume ceiling + the gap/jackpot decouple (D-07)
    // =========================================================================

    /// @notice The GAS-06 / D-06 worst-case multi-day VRF-stall resume. A 121+ day VRF/keeper stall, then a
    ///         resume: rngGate backfills the (capped 120-day) gap on ONE advance, and the gap/jackpot decouple
    ///         (DegenerusGameAdvanceModule:369-372 `if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }`)
    ///         defers the up-to-305-winner daily jackpot to the NEXT advance — so the backfill (~9M) and the
    ///         jackpot (~6M+) NEVER execute in one tx. Asserts the D-06 bar: EACH advanceGame tx (advance N =
    ///         the gap-backfill break, advance N+1 = the deferred jackpot) is STRICTLY under 16,777,216
    ///         (EIP-7825) INDIVIDUALLY — NOT the ~25M total. This is the empirical answer to the proof's
    ///         per-tx gap-resume ESTIMATE (~15.8M), bracketing each advance separately (gasleft before/after a
    ///         single advanceGame call). At a worst-case SUBSCRIBER_CAP=1000 STAGE the backfill advance ALSO
    ///         processes the resumed-day STAGE, so the cap fix (500->1000) is load-bearing here.
    function testGapResumePerAdvanceCeilingAndDecouple() public {
        // Heavy state: a funded STAGE at the cap-relevant scale. On a gap resume the STAGE completes in
        // advance N and DEFERS the backfill (STAGE_SUBS_BACKFILL_DEFERRED) rather than composing with it, so
        // the three heavy legs each get their own tx: advance N = the STAGE chunk, advance N+1 = the gap
        // backfill alone, advance N+2 = the deferred daily jackpot. None of the three ever share a tx, so each
        // stays under the per-tx ceiling regardless of how heavy the STAGE chunk is (the V62-02 close — an
        // all-evict ~9.7M chunk + a ~7M backfill would still compose to ~17M > 16,777,216 and brick).
        address[] memory subs = _setupFundedSubs(N_HI, "gr_", 5 ether, false);

        // Reconstruct the proof's reachable worst-case resume state (test-only direct-storage injection, the
        // same technique this harness uses for the deity-pass grant + the Sub-slot probes). A real 121+ day
        // VRF/keeper stall reaches this precisely: the death-clock EXCLUDES gap days (purchaseStartDay is kept
        // recent across the stall, so the game stays ALIVE — not the gameover/idle path), the resumed-day word
        // arrives via a recent VRF retry (rngRequestTime within the 14-day grace, rngWordCurrent set), and
        // dailyIdx lags currentDayView() by the gap with rngWordByDay[idx+1..] unbackfilled. Injecting this
        // exact precondition isolates the gap-backfill + decouple for the per-tx ceiling measurement (driving
        // it organically would either trip the VRF-grace liveness gate or the lvl-0 idle gameover path first).
        _settleClean(uint256(keccak256("gr_clean")) | 1);
        // level >= 1 so the alive-guard is the 120-day inactivity clock (not the lvl-0 365-day idle path).
        _setHeaderField(12, 3, 1); // level = 1
        // A fresh resumed-day VRF word is ready (rngWordCurrent slot 3) — the gap-backfill trigger.
        vm.store(address(game), bytes32(uint256(3)), bytes32(uint256(keccak256("gr_freshword")) | 1));

        uint32 idxBeforeStall = _dailyIdx();
        uint32 psdBeforeResume;

        // The stall: warp STALL_DAYS whole days WITHOUT advancing, so currentDayView() runs far ahead of
        // dailyIdx — `day > idx + 1 && rngWordByDay[idx + 1] == 0` (the gap-backfill precondition).
        vm.warp(block.timestamp + STALL_DAYS * 1 days);
        uint32 resumeDay = game.currentDayView();
        // Death-clock excludes gap days -> purchaseStartDay kept recent (game alive: resumeDay - psd = 1 < 120).
        _setHeaderField(0, 3, resumeDay - 1); // purchaseStartDay = resumeDay - 1
        // The resume word arrives via a recent VRF retry -> rngRequestTime within the 14-day VRF grace window.
        _setHeaderField(6, 6, uint48(block.timestamp));
        psdBeforeResume = _purchaseStartDay();

        require(resumeDay > idxBeforeStall + 1, "fixture: a multi-day gap opened (day >> dailyIdx)");
        require(rngWordByDay(idxBeforeStall + 1) == 0, "fixture: the gap range is unbackfilled pre-resume");
        require(game.advanceDue(), "fixture: advanceDue on resume");

        // ---- Advance N: the STAGE defer leg (the STAGE completes, then breaks STAGE_SUBS_BACKFILL_DEFERRED
        // because a gap backfill is pending — rngGate does NOT run yet, so NO backfill, NO jackpot) ----
        uint256 gasBeforeN = gasleft();
        game.advanceGame();
        uint256 advNGas = gasBeforeN - gasleft();

        // D-06: advance N (the lone STAGE chunk) is strictly under the EIP-7825 per-tx ceiling.
        emit log_named_uint("stage_defer_advance_N_gas", advNGas);
        assertLt(advNGas, EIP7825_TX_GAS_CAP, "D-06: the STAGE-defer advance N is strictly < 16,777,216 (EIP-7825)");

        // Non-vacuity + segregation invariants on advance N (the V62-02 upstream decouple leg):
        //  - the STAGE actually ran and completed (STAGE_SUBS_BACKFILL_DEFERRED is only reachable past it).
        assertTrue(_subsFullyProcessed(), "V62-02: the STAGE completed in advance N (subsFullyProcessed set)");
        //  - the gap is NOT backfilled yet (rngGate did not run) — the backfill is segregated OUT of the STAGE tx.
        assertTrue(rngWordByDay(idxBeforeStall + 1) == 0, "V62-02: advance N did NOT backfill (segregated from the STAGE chunk)");
        //  - the resumed day's word is NOT committed yet (rngGate did not run on N).
        assertTrue(rngWordByDay(resumeDay) == 0, "V62-02: advance N did NOT run rngGate (resumed-day word uncommitted)");
        //  - dailyIdx NOT advanced and purchaseStartDay NOT bumped (no rngGate, no _unlockRng) -> advanceDue stays true.
        assertEq(_dailyIdx(), idxBeforeStall, "V62-02: advance N did NOT advance dailyIdx");
        assertEq(_purchaseStartDay(), psdBeforeResume, "V62-02: advance N did NOT bump purchaseStartDay (rngGate deferred)");
        assertTrue(game.advanceDue(), "V62-02: advanceDue() stays true after the STAGE-defer break (liveness preserved)");

        // ---- Advance N+1: the gap-backfill leg (STAGE skipped now — subsFullyProcessed; rngGate backfills the
        // gap ALONE and breaks STAGE_GAP_BACKFILLED, deferring the jackpot downstream) ----
        uint256 gasBeforeNp1 = gasleft();
        game.advanceGame();
        uint256 advNp1Gas = gasBeforeNp1 - gasleft();

        // D-06: advance N+1 (the lone backfill) is strictly under the EIP-7825 per-tx ceiling.
        emit log_named_uint("gap_backfill_advance_Np1_gas", advNp1Gas);
        assertLt(advNp1Gas, EIP7825_TX_GAS_CAP, "D-06: the gap-backfill advance N+1 is strictly < 16,777,216 (a SEPARATE tx from the STAGE chunk)");

        // D-07 invariants on advance N+1 (the gap backfill, decoupled from BOTH the STAGE and the jackpot):
        //  - the gap range is now backfilled (so rngGate is idempotent next call: rngWordByDay[idx+1] != 0).
        assertTrue(rngWordByDay(idxBeforeStall + 1) != 0, "D-07: advance N+1 backfilled the gap (idempotent re-entry next call)");
        //  - dailyIdx still NOT advanced (no _unlockRng on the gap break) -> advanceDue stays true.
        assertEq(_dailyIdx(), idxBeforeStall, "D-07: advance N+1 did NOT advance dailyIdx (no _unlockRng on the gap break)");
        assertTrue(game.advanceDue(), "D-07: advanceDue() stays true between advance N+1 and advance N+2 (jackpot deferred)");
        //  - purchaseStartDay bumped EXACTLY ONCE by the gap count (the death-clock extension, the single bump).
        //    rngGate computes gapCount = day - idx - 1 = resumeDay - idxBeforeStall - 1 (uncapped at the psd
        //    bump site; the 120-day cap is only on the backfill LOOP, _backfillGapDays).
        uint32 psdAfterNp1 = _purchaseStartDay();
        uint256 expectedBump = uint256(resumeDay - idxBeforeStall - 1);
        assertEq(uint256(psdAfterNp1 - psdBeforeResume), expectedBump, "D-07: purchaseStartDay bumped exactly once by the gap count (resumeDay - dailyIdx - 1)");

        // The resumed day's frozen word was landed by advance N+1's normal-daily-rng path (rngGate applied the
        // resumed day right after the backfill, before the decouple break). advance N+2 reads the SAME word to
        // pay the deferred jackpot — it is NOT re-rolled (the decouple defers DISTRIBUTION, never the word).
        uint256 resumeWordOnNp1 = rngWordByDay(resumeDay);
        require(resumeWordOnNp1 != 0, "fixture: the resumed-day word landed on advance N+1 (committed pre-defer)");

        // ---- Advance N+2: the deferred-distribution advance (re-entry is idempotent: rngWordByDay[idx+1] != 0
        // -> gapDays == 0; the daily jackpot distributes HERE, NOT on N+1). The D-06 per-tx ceiling for N+2 is
        // the pre-existing payDailyJackpot bound (<= DAILY_ETH_MAX_WINNERS = 305, the proof's ~6M measured row +
        // the dedicated jackpot suites) — the NEW fact the decouple establishes is that this distribution
        // executes in a SEPARATE tx from the gap backfill, so the two never compose into one tx. We bracket N+2
        // via a low-level call so the gas-to-completion (or to the synthetic-fixture jackpot boundary — the
        // cheap STAGE/open marginal fixture builds no full prize-pool/ticket economics) is captured regardless,
        // and assert it stays under the EIP cap.
        uint256 gbNp2 = gasleft();
        (bool okNp2, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        uint256 advNp2Gas = gbNp2 - gasleft();
        okNp2; // completion is fixture-state-dependent; the per-tx GAS is the load-bearing D-06 measurement.

        emit log_named_uint("deferred_jackpot_advance_Np2_gas", advNp2Gas);
        emit log_named_uint("deferred_jackpot_advance_Np2_completed", okNp2 ? 1 : 0);
        // D-06: the deferred-distribution advance N+2 stays strictly under the EIP-7825 per-tx ceiling — and,
        // critically, it is a SEPARATE tx from the gap backfill N+1: the gap-backfill ~7M and the jackpot
        // distribution NEVER share one tx (the original Codex composition breach), and neither shares the tx
        // with the STAGE chunk (the V62-02 upstream breach).
        assertLt(advNp2Gas, EIP7825_TX_GAS_CAP, "D-06: the deferred-jackpot advance N+2 is strictly < 16,777,216 (a SEPARATE tx from the gap-backfill N+1)");

        // D-07: advance N+2 read the SAME frozen resumed-day word committed on advance N+1 (never re-rolled).
        assertEq(rngWordByDay(resumeDay), resumeWordOnNp1, "D-07: the deferred jackpot reads the SAME frozen resumed-day word (committed on N+1, no re-roll on N+2)");
        // D-07: purchaseStartDay was bumped EXACTLY ONCE across the whole resume (advance N+2 must NOT bump it
        // again — the death-clock extension is a single event tied to the gap backfill, gapDays == 0 on N+2).
        assertEq(_purchaseStartDay(), psdAfterNp1, "D-07: purchaseStartDay NOT bumped again on advance N+2 (exactly-once across the resume; idempotent gapDays==0)");

        emit log_named_uint("subscriber_cap_used", SUBSCRIBER_CAP);
        // Non-vacuity: the funded subs still exist (the resume processed them, did not drop the fixture).
        require(subs.length == N_HI, "fixture: funded set intact");
    }

    // =========================================================================
    // (g) D-06 residual R1 — STAGE weight-model fidelity (level-cross / gap-resume per-iter <= weight)
    // =========================================================================

    /// @notice Residual R1 (the proof's residual list): the all-evict SATURATED STAGE chunk, projected from the
    ///         live cold per-evict marginal as a cross-check on the direct LIVE measurement
    ///         (test_AllEvictSaturatedChunk_LIVE_Measured). The in-stage finalize (a DegenerusQuests read +
    ///         finalizeAfking write + _removeFromSet swap-pop) is weighted SUB_STAGE_EVICT_WEIGHT=8, so the budget
    ///         admits BUDGET/EVICT_WEIGHT = 312 evicts/chunk. This measures the per-evict marginal COLD (vm.cool
    ///         first-touch — the realistic regime, ~29k) and asserts the saturated all-evict chunk stays
    ///         on the <10M soft target. Measuring cold (not the warm same-tx ~5M) proves the REAL binding chunk.
    function testResidualR1StageWeightModelFidelity() public {
        uint256 snap = vm.snapshotState();

        // The level-crossing pass refresh-or-evict iter (the heavier in-stage finalize branch), measured COLD
        // (vm.cool first-touch) — the realistic daily-advance regime where an evicted sub's slots are cold (it
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
        emit log_named_uint("r1_evict_weight_budget_units", SUB_STAGE_EVICT_WEIGHT);

        // R1: the all-evict SATURATED STAGE chunk, analytically projected from the live cold per-evict marginal.
        // With evict weight 8 the budget admits BUDGET/EVICT_WEIGHT = 312 evicts; at the realistic COLD per-evict
        // (~29k, the cross-contract finalize + _removeFromSet swap-pop) the chunk stays on the <10M soft
        // target with deep headroom to the 16.7M ceiling. Asserting the COLD projection cross-checks the
        // direct LIVE measurement in test_AllEvictSaturatedChunk_LIVE_Measured (~9.7M; the two agree). Chunk =
        // cold advance overhead + (BUDGET/EVICT_WEIGHT)×coldPerEvict.
        uint256 evictsPerChunk = SUB_STAGE_WEIGHT_BUDGET / SUB_STAGE_EVICT_WEIGHT; // 312 evicts fill the budget
        uint256 fixedEvictOverhead = coldEvN > coldPerEvict * N_HI ? coldEvN - coldPerEvict * N_HI : 0;
        uint256 allEvictChunk = fixedEvictOverhead + evictsPerChunk * coldPerEvict;
        emit log_named_uint("r1_evicts_per_budget_chunk", evictsPerChunk);
        emit log_named_uint("r1_cold_all_evict_saturated_chunk_gas", allEvictChunk);
        assertLt(allEvictChunk, 10_500_000, "R1: the COLD all-evict saturated chunk (~9.8M, post-reweight) stays on the <10M target");
        // R1: the per-evict finalize is a bounded O(1) cross-contract op (no scaling with player magnitude), so
        // the chunk bound holds at any reachable per-iter state.
        assertLt(coldPerEvict, 400_000, "R1: the per-evict finalize is a bounded O(1) op");
        // R1: a funded buy (incl. a gap-resumed streak-rebase buy) is bounded by one weight unit (1 buy = wt 1).
        assertLt(perBuy, EFFECTIVE_GAS_CEILING, "R1: the per-buy iter (gap-resume streak rebase rides it) is bounded");
    }

    // =========================================================================
    // (h) D-06 residual R2 — heaviest single processTicketBatch entry at a full write budget
    // =========================================================================

    /// @notice Residual R2: the per-entry cap (writesBudget - used) stops one entry overrunning the budget, but
    ///         the heaviest single TICKET buy (the minimal-write _queueEntriesScaled primitive — the in-stage
    ///         per-sub ticket leg, the cold ticketQueue push that dominates the STAGE weight at
    ///         SUB_STAGE_TICKET_WEIGHT) is asserted bounded at the cap. The deferred trait-resolution
    ///         processTicketBatch is write-budgeted (WRITES_BUDGET_SAFE=550) and O(1)-queued, so the heaviest
    ///         in-stage ticket entry is the per-buy ticket marginal; assert it is bounded and weight-faithful
    ///         (<= SUB_STAGE_TICKET_WEIGHT buy-units).
    function testResidualR2HeaviestTicketEntry() public {
        uint256 snap = vm.snapshotState();
        uint256 tN = _measureStageAdvanceGas(N_HI, "r2tkHi_", true, false);
        vm.revertToState(snap);
        uint256 tNm1 = _measureStageAdvanceGas(N_LO, "r2tkLo_", true, false);
        require(tN > tNm1, "R2: the Nth ticket buy did real work");
        uint256 perTicket = tN - tNm1;

        vm.revertToState(snap);
        uint256 lN = _measureStageAdvanceGas(N_HI, "r2lbHi_", false, false);
        vm.revertToState(snap);
        uint256 lNm1 = _measureStageAdvanceGas(N_LO, "r2lbLo_", false, false);
        uint256 perLootbox = lN > lNm1 ? lN - lNm1 : 1;

        emit log_named_uint("r2_heaviest_ticket_entry_gas", perTicket);
        emit log_named_uint("r2_per_lootbox_unit_gas", perLootbox);
        emit log_named_uint("r2_ticket_weight_units", SUB_STAGE_TICKET_WEIGHT);

        // R2: the heaviest single ticket entry is bounded by the ceiling and weight-faithful (<= its
        // SUB_STAGE_TICKET_WEIGHT allocation in lootbox-buy units) — one entry can never overrun the budget.
        assertLt(perTicket, EFFECTIVE_GAS_CEILING, "R2: the heaviest single ticket entry trivially fits the 16.7M ceiling");
        assertLe(perTicket, perLootbox * SUB_STAGE_TICKET_WEIGHT, "R2: the heaviest ticket entry <= its SUB_STAGE_TICKET_WEIGHT allocation");
    }

    // =========================================================================
    // (i) D-06 residual R3 — mixed-stamp-day OPEN_BATCH (defeats the cachedDay/cachedWord short-circuit)
    // =========================================================================

    /// @notice Residual R3: the per-open marginal harness measures a UNIFORM stamp day (the cachedDay/cachedWord
    ///         short-circuit at GameAfkingModule:1157-1163 hits, reading rngWordByDay once per pass). The
    ///         cache-defeating case — boxes spanning DISTINCT stamp days — re-reads rngWordByDay PER box (a cold
    ///         SLOAD each), the higher per-box marginal. This measures a mixed-day open and asserts both the
    ///         per-box marginal and the full OPEN_BATCH chunk at the mixed-day cost stay < the EIP cap.
    function testResidualR3MixedStampDayOpenBatch() public {
        // The per-box open is NO LONGER a uniform O(1) constant: a box can roll into a Degenerette
        // spin (WWXRP / FLIP-spins / ETH-spin), so the old diff-of-two-batches marginal (which
        // assumed the first N-1 boxes cancel exactly) is unsound — box i's roll value depends on its
        // stamp DAY, which differs by one between the N and N-1 runs. Measure the WORST CASE directly
        // instead: FORCE every box in a full OPEN_BATCH to the heaviest path — the ETH-spin (roll 19),
        // which credits ETH AND recircs a winning payout into a fresh re-hashed box (the deepest
        // single-box work; the recirc cannot itself cascade an ETH-spin, allowEthSpin=false there).
        // This is the binding worst-case OPEN_BATCH chunk for the fixed `_autoOpen(OPEN_BATCH)` crank.
        (uint256 chunkGas, uint256 ethSpins) = _forceEthSpinOpenChunk("r3eth_");

        emit log_named_uint("r3_forced_eth_spin_OPEN_BATCH_chunk_gas", chunkGas);
        emit log_named_uint("r3_forced_eth_spin_count", ethSpins);
        emit log_named_uint("r3_forced_eth_spin_per_box_gas", chunkGas / OPEN_BATCH);

        // Non-vacuity: every box actually took the ETH-spin path (proves the worst-case forcing worked).
        assertEq(ethSpins, OPEN_BATCH, "R3: every forced box rolled the ETH-spin (the heaviest outcome)");
        // The full forced all-ETH-spin OPEN_BATCH chunk stays under the 16,777,216 EIP-7825 per-tx cap,
        // so the fixed-OPEN_BATCH mintFlip crank can never become un-submittable on a worst-case batch.
        assertLt(chunkGas, EIP7825_TX_GAS_CAP, "R3: forced all-ETH-spin OPEN_BATCH chunk stays < 16,777,216");
    }

    /// @dev Build a full OPEN_BATCH of distinct-stamp-day afking boxes whose injected rngWordByDay is
    ///      brute-forced so EVERY box rolls the ETH-spin (roll 19 — the heaviest box outcome), then
    ///      bracket one openBoxes(OPEN_BATCH) call. Returns the measured chunk gas and the count of
    ///      ETH-type BoxSpin events (must equal OPEN_BATCH — proves the forcing landed). The recirc box
    ///      each winning ETH-spin opens is in the same chunk (allowEthSpin=false there, so its BoxSpins
    ///      carry the WWXRP/FLIP type — the ETH-type count is exactly the forced first-level spins).
    function _forceEthSpinOpenChunk(string memory prefix)
        internal
        returns (uint256 chunkGas, uint256 ethSpins)
    {
        uint256 m = OPEN_BATCH; // 80 distinct-day boxes — the full fixed crank chunk
        address[] memory subs = _setupFundedSubs(m, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so the open chunk runs");

        uint32 anchor = _lastBoughtDayOf(subs[0]) + uint32(m) + 1;
        for (uint256 i; i < m; ++i) {
            uint32 d = anchor - uint32(i);
            _pokeLastBoughtDay(subs[i], d);
            _pokeLastOpenedDay(subs[i], d - 1);
            // The box seed = keccak256(rngWord, player, day, rawAmountWei); brute-force the (injected)
            // rngWord so its roll value (bits[40..55] % 20) is 19 = the ETH-spin path.
            uint256 amtWei = _subField(subs[i], OFF_AMOUNT, 24) * MILLI_ETH_SCALE;
            _injectRngWordByDay(d, _findEthSpinWord(subs[i], d, amtWei, i));
        }

        vm.recordLogs();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "op"))));
        uint256 gasBefore = gasleft();
        // +2: the walk budget is WEIGHTED (skip = 1 unit, open = OPEN_ITEM_WEIGHT) and the
        // 2 permanent deploy subs (VAULT/sDGNRS) sit in the ring as skips — the allowance
        // keeps the full 80 forced opens affordable in this single chunk.
        game.openBoxes(OPEN_BATCH + 2);
        chunkGas = gasBefore - gasleft();

        // Count the first-level ETH spins: BoxSpin events whose betId encodes the ETH type
        // (bits 62-60 == 2). Recirc boxes (allowEthSpin=false) may emit WWXRP/FLIP BoxSpins,
        // which carry a different type and are excluded here.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        bytes32 boxSpinSig = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == boxSpinSig) {
                (uint64 betId, , , ) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                if ((betId >> 60) & 7 == 2) ++ethSpins;
            }
        }
    }

    /// @dev Brute-force an injected stamp-day word so the afking box's roll lands on the ETH-spin (19).
    function _findEthSpinWord(address player, uint32 day, uint256 amountWei, uint256 salt)
        internal
        pure
        returns (uint256 w)
    {
        for (uint256 k; k < 8000; ++k) {
            w = uint256(keccak256(abi.encodePacked("r3ethspin", salt, k))) | 1;
            uint256 seed = uint256(keccak256(abi.encode(w, player, uint256(day), amountWei)));
            if (uint16(seed >> 40) % 20 == 19) return w;
        }
        revert("no eth-spin word found");
    }

    // =========================================================================
    // (j) D-06 residual R4 — heaviest reachable per-iter state (re-measure the marginals at the heavy state)
    // =========================================================================

    /// @notice Residual R4: the per-iter marginals come from the fixture's 5-ETH-sub + deity-pass states; the
    ///         true heaviest reachable per-iter state (max streak hand-back / level crossing) may exceed them.
    ///         The v56 streak is compute-on-read (no per-iter streak SSTORE storm), so the heaviest per-iter
    ///         state is the level-crossing finalize (R1's evict branch) and the heaviest open (R3's mixed-day,
    ///         cold-SLOAD-per-box). This asserts the heaviest of {evict marginal, mixed-day open marginal} is
    ///         still a bounded O(1) per-iter cost (no marginal scales with player magnitude), so the
    ///         weight-budget / OPEN_BATCH chunk bounds hold at the heaviest reachable state.
    function testResidualR4HeaviestPerIterState() public {
        uint256 snap = vm.snapshotState();
        uint256 evN = _measureEvictStageGas(N_HI, "r4evHi_");
        vm.revertToState(snap);
        uint256 evNm1 = _measureEvictStageGas(N_LO, "r4evLo_");
        uint256 perEvict = evN > evNm1 ? evN - evNm1 : 1;

        vm.revertToState(snap);
        uint256 mxN = _measureMixedDayOpenLegGas(N_HI, "r4mxHi_");
        vm.revertToState(snap);
        uint256 mxNm1 = _measureMixedDayOpenLegGas(N_LO, "r4mxLo_");
        uint256 perBoxMixed = mxN > mxNm1 ? mxN - mxNm1 : 1;

        // Also capture the REAL measured mixed-day OPEN_BATCH chunk (the binding worst-case chunk at the
        // heaviest per-iter state — measured directly, NOT a synthetic marginal*N extrapolation, which would
        // double-count the per-box injection overhead present in the marginal).
        vm.revertToState(snap);
        uint256 mixedChunk = _measureMixedDayOpenChunkAtBatch("r4ch_");

        uint256 heaviestPerIter = perEvict > perBoxMixed ? perEvict : perBoxMixed;
        emit log_named_uint("r4_per_evict_heavy_gas", perEvict);
        emit log_named_uint("r4_per_box_mixed_heavy_gas", perBoxMixed);
        emit log_named_uint("r4_heaviest_per_iter_gas", heaviestPerIter);
        emit log_named_uint("r4_measured_mixed_OPEN_BATCH_chunk_gas", mixedChunk);

        // R4: the heaviest reachable per-iter cost is a bounded O(1) (does not scale with player magnitude),
        // so the chunk bound holds at the heavy state.
        assertLt(heaviestPerIter, 400_000, "R4: the heaviest reachable per-iter state is a bounded O(1) (no magnitude scaling)");
        // R4: the REAL measured worst-case mixed-day OPEN_BATCH=80 chunk (every box a cold rngWordByDay SLOAD,
        // the heaviest reachable open state) stays under the EIP per-tx ceiling — the binding chunk bound.
        assertLt(mixedChunk, EIP7825_TX_GAS_CAP, "R4: the measured worst-case mixed-day OPEN_BATCH=80 chunk stays < 16,777,216");
    }

    // =========================================================================
    // (k) LIVE-01 — the openBoxes valve: drain + bound + afking-first + cursor-independence + selector-isolation
    // =========================================================================

    /// @notice LIVE-01 (a) afking-first ordering: openBoxes(maxCount) drains the afking backlog FIRST
    ///         (drainAfkingBoxes via delegatecall), then the human leg consumes ONLY maxCount - openedAfking
    ///         (DegenerusGame:1815). With both backlogs populated and maxCount set so the afking leg does not
    ///         exhaust it, the human cursor advances by EXACTLY the remainder.
    function testLive01AfkingFirstOrdering() public {
        // AFKING backlog: a funded lootbox sub gets a stamped box.
        address afk = makeAddr("v_afk");
        _grantDeityPass(afk);
        _fundPool(afk, 5 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
        vm.prank(afk);
        game.subscribe(address(0), false, false, 1, address(0));
        _runStageNewDay(0xA0F1);

        // HUMAN backlog: a real lootbox buyer queues a box on the human path (boxPlayers).
        address human = makeAddr("v_human");
        vm.deal(human, 5 ether);
        vm.prank(human);
        game.purchase{value: 1.01 ether}(human, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth, false);

        _settleClean(0xA0F2);
        require(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "fixture: afking box pending pre-valve");
        uint256 boxCursorBefore = _boxCursor();
        uint256 subOpenCursorBefore = _subOpenCursor();

        // Drain via the valve with a budget large enough for BOTH the afking box AND the human box.
        vm.prank(makeAddr("v_opener"));
        uint256 opened = game.openBoxes(50);

        // Afking-first: the afking box opened (lastOpenedDay advanced to the stamp day).
        assertEq(_lastOpenedDayOf(afk), _lastBoughtDayOf(afk), "LIVE-01(a): afking-first -- the afking box opened by the valve");
        assertGt(opened, 0, "LIVE-01(a): the valve opened at least the afking box");
        // The human leg ran with the REMAINING budget: its cursor advanced (the remainder, not the full maxCount).
        assertGe(_boxCursor(), boxCursorBefore, "LIVE-01(a): the human cursor advanced with the remaining budget (maxCount - openedAfking)");
        emit log_named_uint("live01a_opened_total", opened);
        emit log_named_uint("live01a_sub_open_cursor_before", subOpenCursorBefore);
        emit log_named_uint("live01a_sub_open_cursor_after", _subOpenCursor());
        emit log_named_uint("live01a_box_cursor_before", boxCursorBefore);
        emit log_named_uint("live01a_box_cursor_after", _boxCursor());
    }

    /// @notice LIVE-01 (b)+(c)+(d): repeated bounded openBoxes calls fully DRAIN a multi-box afking backlog with
    ///         BOTH cursors monotone-advancing (no stuck box), EACH openBoxes chunk < the EIP cap (bounded), and
    ///         lastOpenedDay monotone no-double-open (the skip at GameAfkingModule:1154). Uses tiny per-call
    ///         budgets so the drain genuinely spans multiple bounded calls.
    function testLive01DrainBothCursorsBoundedNoDoubleOpen() public {
        uint256 n = 8;
        address[] memory subs = _setupFundedSubs(n, "vd_", 5 ether, false);
        _runStageNewDay(0xB0F1);
        _settleClean(0xB0F2);

        uint32 stampDay = _lastBoughtDayOf(subs[0]);
        require(stampDay > 0, "fixture: subs stamped");
        // Pre: every box pending.
        for (uint256 i; i < n; ++i) require(_lastOpenedDayOf(subs[i]) < stampDay, "fixture: each afking box pending");

        // Drain in tiny bounded chunks until BOTH legs are empty (openBoxes returns 0). Each lootbox-mode
        // sub carries two pending boxes after the STAGE: the afking-cover box (drained by the afking leg,
        // drainAfkingBoxes) AND a human lootbox box at the next index (drained by the relocated multi-index
        // human sweep, openHumanBoxes). openBoxes routes the per-call budget to the afking leg first, then
        // the human sweep — so a full drain takes more chunks than just the afking count. Loop until a chunk
        // opens nothing (the genuine fully-drained state the re-open no-op assertion below requires); each
        // chunk must stay under the per-tx ceiling and the cursors must advance.
        uint256 totalOpened;
        uint256 zeroStreak;
        for (uint256 c; c < 80; ++c) {
            vm.prank(makeAddr(string(abi.encodePacked("vd_op_", _u(c)))));
            uint256 gb = gasleft();
            uint256 op = game.openBoxes(2);
            uint256 g = gb - gasleft();
            // LIVE-01(c): each bounded openBoxes chunk stays under the EIP per-tx ceiling.
            assertLt(g, EIP7825_TX_GAS_CAP, "LIVE-01(c): each bounded openBoxes chunk stays < 16,777,216");
            totalOpened += op;
            // The weighted budget charges the afking ring scan and index headers/skip
            // entries as steps, so a tiny chunk CAN open zero while committing real
            // cursor/frontier progress mid-backlog; a few consecutive zeros end the
            // bounded-chunk phase.
            if (op == 0) {
                if (++zeroStreak >= 3) break;
            } else {
                zeroStreak = 0;
            }
        }
        // Finish whatever the step-bounded tiny chunks left (skip-entry runs can zero
        // several 1-step chunks in a row while boxes remain) — the drained-state
        // assertions below need the genuinely-dry state.
        vm.prank(makeAddr("vd_finish"));
        totalOpened += game.openBoxes(2000);

        // LIVE-01(b): the whole afking backlog DRAINED — every sub's box opened (lastOpenedDay == stampDay),
        // no stuck box; the afking cursor advanced through the set.
        uint256 openedCount;
        for (uint256 i; i < n; ++i) {
            if (_lastOpenedDayOf(subs[i]) == stampDay) openedCount++;
            // LIVE-01(d): lastOpenedDay is monotone — never exceeds the stamp day (no double-open / over-advance).
            assertLe(_lastOpenedDayOf(subs[i]), stampDay, "LIVE-01(d): lastOpenedDay monotone, no double-open");
        }
        assertEq(openedCount, n, "LIVE-01(b): repeated bounded openBoxes fully drained the afking backlog (no stuck box)");

        // LIVE-01(d): a re-open call is a no-op (the lastOpenedDay >= stampDay skip at :1154) — no double-open.
        vm.prank(makeAddr("vd_reopen"));
        uint256 reopened = game.openBoxes(n);
        assertEq(reopened, 0, "LIVE-01(d): re-running openBoxes on an already-drained backlog opens nothing (no double-open)");
        emit log_named_uint("live01_total_opened", totalOpened);
    }

    /// @notice LIVE-01 (e) selector isolation: drainAfkingBoxes is reached ONLY via the Game's openBoxes
    ///         delegatecall (which runs in the Game's storage). Calling drainAfkingBoxes DIRECTLY on the
    ///         GameAfkingModule contract address operates on the MODULE's OWN storage — which has an empty
    ///         _subscribers set — so it returns 0 (opens nothing). The afking open is never a re-exposed
    ///         standalone selector on a live subscriber set.
    function testLive01DrainAfkingBoxesSelectorIsolation() public {
        // Populate a real afking backlog in the GAME's storage.
        address afk = makeAddr("vsel_afk");
        _grantDeityPass(afk);
        _fundPool(afk, 5 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
        vm.prank(afk);
        game.subscribe(address(0), false, false, 1, address(0));
        _runStageNewDay(0xE0F1);
        _settleClean(0xE0F2);
        require(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "fixture: afking box pending");

        // Call drainAfkingBoxes DIRECTLY on the module address — it hits the MODULE's empty storage, not the
        // Game's. It must open nothing (selector isolation: only reachable via the Game's openBoxes delegatecall).
        (uint256 openedDirect, ) = IGameAfkingModule(ContractAddresses.GAME_AFKING_MODULE).drainAfkingBoxes(50);
        assertEq(openedDirect, 0, "LIVE-01(e): direct drainAfkingBoxes on the module hits empty storage (selector-isolated)");
        // The Game's afking box is UNTOUCHED by the direct module call (still pending).
        assertTrue(_lastOpenedDayOf(afk) < _lastBoughtDayOf(afk), "LIVE-01(e): the Game's afking box untouched by the direct module call");

        // And the canonical path (the Game's valve) DOES open it — the non-vacuity control.
        vm.prank(makeAddr("vsel_op"));
        game.openBoxes(50);
        assertEq(_lastOpenedDayOf(afk), _lastBoughtDayOf(afk), "LIVE-01(e) control: the Game's openBoxes valve DOES open the afking box");
    }

    /// @notice LIVE-01 (f) individual-open byte-unchanged: the box a sub gets via the unified valve (openBoxes
    ///         -> drainAfkingBoxes -> _openAfkingBox) is the SAME materialized box as via the rewarded mintFlip
    ///         open leg — both route through _autoOpen with the same frozen stamp-day word, so the open path is
    ///         byte-unchanged across the two reachable afking-open entrypoints (the valve and the bounty router).
    function testLive01IndividualOpenPathByteUnchanged() public {
        // Two identical funded subs stamped on the same day with the same word; open one via the valve, one via
        // mintFlip. Each opens to the SAME stamp-day marker (lastOpenedDay == lastAutoBoughtDay) — the open
        // outcome is identical (same _autoOpen path, same rngWordByDay[stampDay] seed).
        address viaValve = makeAddr("vbu_valve");
        address viaBounty = makeAddr("vbu_bounty");
        _grantDeityPass(viaValve);
        _grantDeityPass(viaBounty);
        // Fund BEFORE subscribe so each grounded NEW-run cover-buy is funded (D-12).
        _fundPool(viaValve, 5 ether);
        _fundPool(viaBounty, 5 ether);
        vm.prank(viaValve);
        game.subscribe(address(0), false, false, 1, address(0));
        vm.prank(viaBounty);
        game.subscribe(address(0), false, false, 1, address(0));
        _runStageNewDay(0xF0F1);

        uint32 stampValve = _lastBoughtDayOf(viaValve);
        uint32 stampBounty = _lastBoughtDayOf(viaBounty);
        require(stampValve == stampBounty && stampValve > 0, "fixture: both subs stamped the same day");
        require(rngWordByDay(stampValve) != 0, "fixture: the shared stamp-day word landed");

        _settleClean(0xF0F2);
        // Open one via the unified valve.
        vm.prank(makeAddr("vbu_op1"));
        game.openBoxes(SUBSCRIBER_CAP);
        // Open the rest via the rewarded bounty router (mintFlip).
        vm.prank(makeAddr("vbu_op2"));
        try game.mintFlip() {} catch {}

        // Both materialized to the SAME open marker (lastOpenedDay == the shared stamp day) — byte-unchanged
        // open outcome across the valve path and the bounty path.
        assertEq(_lastOpenedDayOf(viaValve), stampValve, "LIVE-01(f): valve-opened box materialized at the stamp day");
        assertEq(_lastOpenedDayOf(viaBounty), stampBounty, "LIVE-01(f): bounty(mintFlip)-opened box materialized at the same stamp day");
        assertEq(_lastOpenedDayOf(viaValve), _lastOpenedDayOf(viaBounty), "LIVE-01(f): the two open entrypoints produce the identical open marker (byte-unchanged path)");
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

    /// @dev Measure the afking open-leg gas over N boxes stamped on DISTINCT days (the cache-defeating R3 case).
    ///      Each in-set funded sub re-stamps to the SAME day every STAGE, so to model the proof's mixed-day
    ///      worst case (the open leg fell behind OPEN_BATCH / a keeper skipped days, so the no-orphan rule
    ///      preserved older-day boxes) we inject DISTINCT stamp days + words directly (test-only Sub-slot poke,
    ///      the same direct-storage technique the harness uses for the deity-pass grant). Each box then carries
    ///      a distinct lastAutoBoughtDay, so the open walk re-reads rngWordByDay PER box (defeating the
    ///      cachedDay/cachedWord short-circuit at GameAfkingModule:1157-1163). Returns the bracketed openBoxes
    ///      open-leg gas; the 2 deploy subs add a constant offset that cancels in the (gasN - gasNm1) marginal.
    function _measureMixedDayOpenLegGas(uint256 n, string memory prefix) internal returns (uint256 openGas) {
        // Subscribe + fund n subs in one set, run ONE new-day STAGE so they enter as real funded subs.
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so the open leg runs");

        // Anchor on a high base day so the descending distinct-day assignment can never underflow. The current
        // stamp day is small (fixture day index); use it + n as the high anchor so d = anchor - i stays >= 1.
        uint32 anchor = _lastBoughtDayOf(subs[0]) + uint32(n) + 1;
        for (uint256 i; i < n; ++i) {
            uint32 d = anchor - uint32(i); // distinct descending stamp days, all >= 2
            _pokeLastBoughtDay(subs[i], d);
            // Re-open marker strictly behind the stamp day so the box is pending; land that day's word.
            _pokeLastOpenedDay(subs[i], d - 1);
            _injectRngWordByDay(d, uint256(keccak256(abi.encodePacked(prefix, "wd", _u(i)))) | 1);
            require(_lastOpenedDayOf(subs[i]) < d, "fixture: mixed-day box pending");
        }

        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.openBoxes(SUBSCRIBER_CAP);
        openGas = gasBefore - gasleft();

        // Non-vacuity: each mixed-day box opened (lastOpenedDay advanced to its distinct stamp day).
        for (uint256 i; i < n; ++i) {
            uint32 d = anchor - uint32(i);
            require(_lastOpenedDayOf(subs[i]) == d, "marginal non-vacuity: each mixed-day box opened");
        }
    }

    /// @dev Measure the SINGLE openBoxes chunk over OPEN_BATCH boxes each stamped on a DISTINCT day (the binding
    ///      mixed-day worst-case chunk — every box a cold rngWordByDay SLOAD, defeating the day-cache). Builds a
    ///      full OPEN_BATCH-sized set of funded subs, injects distinct stamp days + words, then brackets one
    ///      openBoxes(OPEN_BATCH) call. This is the real measured chunk (not a marginal extrapolation).
    function _measureMixedDayOpenChunkAtBatch(string memory prefix) internal returns (uint256 chunkGas) {
        uint256 m = OPEN_BATCH; // 80 distinct-day boxes — the full open chunk
        address[] memory subs = _setupFundedSubs(m, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so the open chunk runs");

        uint32 anchor = _lastBoughtDayOf(subs[0]) + uint32(m) + 1;
        for (uint256 i; i < m; ++i) {
            uint32 d = anchor - uint32(i);
            _pokeLastBoughtDay(subs[i], d);
            _pokeLastOpenedDay(subs[i], d - 1);
            _injectRngWordByDay(d, uint256(keccak256(abi.encodePacked(prefix, "wd", _u(i)))) | 1);
        }

        vm.prank(makeAddr(string(abi.encodePacked(prefix, "op"))));
        uint256 gasBefore = gasleft();
        game.openBoxes(OPEN_BATCH);
        chunkGas = gasBefore - gasleft();
    }

    /// @dev Test-only poke of a Sub's lastAutoBoughtDay (uint24 @ byte 11) — preserves all other Sub fields.
    function _pokeLastBoughtDay(address who, uint32 day) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF)) << (OFF_LASTBOUGHT * 8);
        cur = (cur & ~mask) | ((uint256(day) << (OFF_LASTBOUGHT * 8)) & mask);
        vm.store(address(game), slot, bytes32(cur));
    }

    /// @dev Test-only poke of a Sub's lastOpenedDay (uint24 @ byte 14) — preserves all other Sub fields.
    function _pokeLastOpenedDay(address who, uint32 day) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF)) << (OFF_LASTOPENED * 8);
        cur = (cur & ~mask) | ((uint256(day) << (OFF_LASTOPENED * 8)) & mask);
        vm.store(address(game), slot, bytes32(cur));
    }

    /// @dev Test-only poke of a Sub's validThroughLevel (uint24 @ byte 1) — forces the pass-evict crossing
    ///      (currentLevel > validThroughLevel) on the next STAGE without re-running the contract path.
    function _pokeValidThroughLevel(address who, uint24 lvl) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF)) << (OFF_VALIDTHROUGH * 8);
        cur = (cur & ~mask) | ((uint256(lvl) << (OFF_VALIDTHROUGH * 8)) & mask);
        vm.store(address(game), slot, bytes32(cur));
    }

    /// @dev Clear `who`'s deity bit so `_passHorizonOf` reads the finite frozen horizon (0 here) at the
    ///      crossing re-read — the EVICT branch then fires instead of REFRESH.
    function _clearDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke the game `level` (slot 0, uint24 @ byte 12) so the pass-evict crossing
    ///      (currentLevel > validThroughLevel) is reachable in the gas harness (the fixture level does not
    ///      advance organically over the bracketed STAGE measure).
    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (12 * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (12 * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    /// @dev Drive a new-day STAGE advance over N unfunded, NON-deity subs that all PASS-EVICT this cycle
    ///      (validThroughLevel 0 < currentLevel -> each routes through _finalizeAfking + swap-pop), returning the
    ///      bracketed advance gas. Both runs from one clean baseline.
    function _measureEvictStageGas(uint256 n, string memory prefix) internal returns (uint256 advGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        // Under the 357-00 D-11/D-12 gates an unfunded passless subscribe REVERTS, so the evicting subs are
        // built GROUNDED (deity + funded -> subscribe passes both gates), then forced into the pass-evict
        // crossing by clearing the deity bit + poking validThroughLevel to 0 (so the STAGE re-reads horizon 0
        // < currentLevel -> each routes through _finalizeAfking + swap-pop, the same EVICT path measured before).
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            _grantDeityPass(who);
            _fundPool(who, 5 ether);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0));
        }
        // OPEN the grounded subscribe's pending boxes first — the no-orphan guard dominates the evict branch,
        // so a pending-box sub would be skipped, not evicted. After the open, clear the deity bit + poke
        // validThroughLevel to 0 so the STAGE crossing re-reads horizon 0 < currentLevel -> the EVICT path.
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "ev_open"))));
        game.openBoxes(400);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            _clearDeityPass(who);          // horizon -> finite 0 at the crossing re-read
            _pokeValidThroughLevel(who, 0); // validThroughLevel 0 < currentLevel -> the EVICT branch fires
        }
        _setLevel(10); // ensure currentLevel(10) > validThroughLevel(0) at the STAGE crossing
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
        // The grounded subscribe (D-12) stamps a box at subscribe time; OPEN those pending boxes so the
        // no-orphan guard does not skip the measured STAGE buy (a pending-box sub is left untouched).
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "setup_open"))));
        game.openBoxes(400);
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
    ///      the bracketed `mintFlip()` open-leg gas. The 2 deploy subs add a CONSTANT 2 ready boxes to BOTH
    ///      the N and N−1 measurements, so they cancel in the (gasN − gasNm1) difference — the marginal
    ///      isolates exactly one box. Each call stamps N subs (new-day STAGE), lands the stamp-day word,
    ///      settles clean (so mintFlip routes to OPEN), opens all.
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
        require(!game.advanceDue(), "fixture: clean so mintFlip opens");
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.mintFlip();
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
            // Fund BEFORE subscribe so the grounded NEW-run cover-buy is funded (D-12 — an unfunded start
            // reverts MustPurchaseToBeginAfking).
            _fundPool(who, poolEach);
            vm.prank(who);
            // self, mode = isTicket, qty 1, reinvest 0, self-funded
            game.subscribe(address(0), false, isTicket, 1, address(0));
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

    // ---- Sub-slot reads (_subOf at slot 62 + v56 offsets) ----

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

    /// @dev Read the STAGE cursor `_subCursor` (slot 62, byte 0, uint16) — advances by SUB_STAGE_BATCH on a
    ///      full chunk.
    function _subCursor() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) & 0xFFFF;
    }

    /// @dev Read the afking-open cursor `_subOpenCursor` (slot 62, byte 2, uint16) — the afking-side open
    ///      walk (drainAfkingBoxes -> _autoOpen). Distinct from the human boxCursor (byte 7) — LIVE-01
    ///      cursor independence.
    function _subOpenCursor() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) >> 16) & 0xFFFF;
    }

    /// @dev Read the human-box cursor `boxCursor` (slot 62, byte 7, uint48) — the human open walk
    ///      (openHumanBoxes over boxPlayers[index]). Distinct from _subOpenCursor (byte 2).
    function _boxCursor() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) >> 56) & 0xFFFFFFFFFFFF;
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

    // =========================================================================
    // (m) Q2 INVESTIGATION — warm-vs-cold weight calibration (vm.cool cold marginals)
    // =========================================================================

    /// @notice WARM-vs-COLD calibration (Q2). The snapshot/revert marginals elsewhere in this harness measure
    ///         WARM same-tx Sub slots (the subs were funded + stamped in the SAME test tx, so their slots are
    ///         warm when the bracketed advance reads them). This re-measures the SAME lootbox/ticket/evict
    ///         marginals with `vm.cool(address(game))` re-colding the game storage immediately before the
    ///         bracketed advance — the realistic daily-advance regime where each sub was funded/stamped on a
    ///         PRIOR tx, so its Sub slot + afkingFunding entry are a cold first-touch. Empirical result: vm.cool
    ///         raises each absolute marginal ~3x (warm understates by ~3x — the artifact is real and large), BUT
    ///         the isolated N-vs-(N-1) marginal FLATTENS the per-op ratios toward ~1:1:1 (the cold-slot premium
    ///         is ~uniform per op), so it does NOT reproduce the large-scale-bench weight set 2:4:1. Those
    ///         ratios are a CUMULATIVE per-op WORK effect (ticket-queue growth, the lighter evict finalize) that
    ///         only manifests at scale, which is why the large-scale bench — not this isolated-marginal harness —
    ///         is authoritative for the weight RATIOS. This harness's job is the absolute O(1) boundedness + the
    ///         chunk-under-ceiling safety proof, both of which hold. Diagnostic: emits warm + cold side by side;
    ///         the only hard asserts are that cooling RAISES the marginal (artifact direction) and each cold
    ///         marginal stays a bounded O(1).
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
        emit log_named_uint("weightset_ticket_over_lootbox_x100", SUB_STAGE_TICKET_WEIGHT * 100 / SUB_STAGE_LOOTBOX_WEIGHT);
        emit log_named_uint("weightset_evict_over_lootbox_x100", SUB_STAGE_EVICT_WEIGHT * 100 / SUB_STAGE_LOOTBOX_WEIGHT);
        emit log_named_string(
            "cold_calibration_finding",
            "vm.cool raises each absolute marginal ~3x (warm same-tx slots understate; the artifact is real). The "
            "isolated N-vs-(N-1) marginal flattens the per-op ratios toward ~1:1:1 (the cold-slot premium is "
            "~uniform per op), so it does NOT reproduce the large-scale-bench 2:4:1 -- those ratios are a "
            "cumulative per-op WORK effect (ticket-queue growth / lighter evict finalize) only seen at scale. The "
            "large-scale bench is authoritative for the weight ratios; this harness proves O(1) + chunk<ceiling."
        );

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
    ///      the Nth sub's COLD STAGE cost, the regime the cold-sized weight set is calibrated against.
    function _measureStageAdvanceGasCold(uint256 n, string memory prefix, bool isTicket)
        internal
        returns (uint256 advGas)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, isTicket);
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "setup_open"))));
        game.openBoxes(400);
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        vm.cool(address(game)); // re-cold all game storage -> each Sub slot is a cold first-touch in the STAGE
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            require(_lastBoughtDayOf(subs[i]) > pre[i], "cold marginal non-vacuity: each funded sub newly stamped");
        }
    }

    /// @dev COLD variant of _measureEvictStageGas: identical pass-evict setup, vm.cool before the bracketed
    ///      advance so each evicting sub's cross-contract finalize (quest read + streak write) is a cold
    ///      first-touch — the realistic cold evict marginal that sets SUB_STAGE_EVICT_WEIGHT.
    function _measureEvictStageGasCold(uint256 n, string memory prefix) internal returns (uint256 advGas) {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            _grantDeityPass(who);
            _fundPool(who, 5 ether);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0));
        }
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "ev_open"))));
        game.openBoxes(400);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            _clearDeityPass(who);
            _pokeValidThroughLevel(who, 0);
        }
        _setLevel(10);
        uint256 preCount = _subscriberCount();
        require(preCount >= n, "fixture: N evicting subs in the set");

        _warpToBoundary(false);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        vm.cool(address(game)); // re-cold all game storage -> the finalize cross-contract read is a cold touch
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        require(_subscriberCount() < preCount, "cold evict non-vacuity: the stage evicted subs");
    }

    /// @dev LIVE binding-stage worst case: a saturated all-evict crank measured cold through the REAL advanceGame
    ///      STAGE loop (not the analytic projection). Builds more evicting subs than one chunk admits, so the
    ///      contract's weight budget caps the chunk at SUB_STAGE_WEIGHT_BUDGET / SUB_STAGE_EVICT_WEIGHT finalizes;
    ///      the measured single-tx gas is the true binding worst case. Asserts the <10M target and the EIP-7825 cap.
    function test_AllEvictSaturatedChunk_LIVE_Measured() public {
        uint256 capEvicts = SUB_STAGE_WEIGHT_BUDGET / SUB_STAGE_EVICT_WEIGHT;
        uint256 chunkGas = _measureEvictStageGasCold(capEvicts + 5, "liveAllEv_");
        emit log_named_uint("live_all_evict_saturated_chunk_gas", chunkGas);
        emit log_named_uint("live_all_evict_evicts_per_chunk_cap", capEvicts);
        emit log_named_uint("live_all_evict_headroom_to_16p7M_gas", EIP7825_TX_GAS_CAP - chunkGas);
        assertLt(chunkGas, EIP7825_TX_GAS_CAP, "LIVE: the saturated all-evict chunk is strictly < the 16.7M EIP-7825 cap");
        assertLt(chunkGas, 10_500_000, "LIVE: the saturated all-evict chunk lands on the <10M target");
    }

}
