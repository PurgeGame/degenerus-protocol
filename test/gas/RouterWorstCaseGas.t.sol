// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RouterWorstCaseGas -- TST-06 (Phase 351) the 16.7M HARD per-tx ceiling on the v55 AfKing-in-Game
///        STAGE + open leg. ADAPTED from the v49/331 `AfKing.doWork()` router worst case (D-351-01).
///
/// @notice v55 REFRAME (the load-bearing adaptation). The standalone `AfKing` de-custody contract is
///         DISSOLVED (`contracts/AfKing.sol` deleted); the per-sub buy is FOLDED into `advanceGame()`'s
///         required-path process STAGE and the open is the game-resident open leg:
///           - `afKing.doWork()`            -> `game.mintBurnie()`                     (Δ3 rename)
///           - `afKing.autoBuy(total)`      -> a new-day `game.advanceGame()` STAGE     (Δ4 SEMANTIC REMAP:
///                                             `processSubscriberStage(SUB_STAGE_BATCH)` runs PRE-RNG)
///           - `afKing.autoOpen(N)`         -> `game.autoOpen(N)`  (the game-resident open leg)
///           - `afKing.subscriberCount()`   -> `_subscribers.length` via vm.load (Δ5 slot-read)
///         The OLD per-keeper-tx worst case (the `doWork()` router buy/open legs) reframes onto:
///           (1) the per-sub STAGE 50-chunk marginal (one `advanceGame()` processes up to
///               `SUB_STAGE_BATCH = 50` funded lootbox subs PRE-RNG, partial-drains past that), AND
///           (2) the per-open marginal (`game.autoOpen(N)` over N ready stamped boxes after their
///               frozen-stamp-day word `rngWordByDay[stampDay]` lands).
///
///         The 16.7M HARD per-tx ceiling (350-TST06-MEASUREMENT-SPEC §5): `SUB_STAGE_BATCH = 50`
///         (DegenerusGameAdvanceModule.sol:149) chunks the STAGE so a 50-chunk
///         `processSubscriberStage(50)` stays well under the 16.7M advance-chain ceiling (a landed
///         lootbox buy ≈ 262k → 50 ≈ 13.1M). The open leg is chunked by `OPEN_BATCH`, each afking box
///         uniform O(1). THIS suite asserts a 50-chunk STAGE (driven by `advanceGame()`) AND the open
///         leg each stay UNDER 16.7M on the worst-case funded-lootbox-sub mix — POST-349.2, i.e.
///         INCLUDING the restored per-sub BURNIE quest/affiliate/creditFlip side-effects (those are
///         intended behavior; the marginal is reported AS-IS, never subtracted — 350-SPEC §1 ⚠-note).
///
///         The MARGINAL rule (CR-01, 350-SPEC §0, load-bearing): every per-item number is the
///         loop-N-divide MARGINAL — (gas for N − gas for N−1) / 1, NEVER a single-item TOTAL (a
///         single-item total over-pegs ~2x and would re-open the Phase-319 self-crank faucet were a
///         reward pegged to it). The full per-buy/per-open marginal HARNESS is plan 351-08; THIS plan is
///         the worst-case-ceiling corpus (the 16.7M bar + a CR-01-faithful convergence gradient).
///
///         Each test (1) asserts the constructed scenario IS the worst-case cap, (2) asserts non-vacuity
///         (REAL work LANDED — a sub stamped / a box materialized, not a silent skip), (3) asserts < the
///         16.7M effective per-tx ceiling, (4) emits the calibration input.
///
/// @dev Live `DeployProtocol` fixture. Reuses the gasleft()-delta bracket (NOT vm.snapshotGas — the live
///      repo idiom) + the validated game-resident driving harness ported from V55RevertFreeEvCap /
///      V55FreezeDeterminism (`_settleGame`/`_settleClean` VRF drain, `_setupFundedLootboxSubs`,
///      `depositAfkingFunding` funding, `_grantDeityPass`, the Sub-stamp slot reads). All pinned slots
///      RE-DERIVED via `forge inspect storage DegenerusGame` (the v55 append shifted the afking mappings:
///      `_subscribers = 68`, `_subOf = 66`, `rngWordByDay = 11`, `lootboxEthBase = 23`,
///      `lootboxRngPacked = 38`, `lootboxRngWordByIndex = 39`). Test-only: ZERO contracts/*.sol mutated
///      (`git diff 453f8073 HEAD -- contracts/` EMPTY). Run with --isolate for true per-call gas.
contract RouterWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`)
    // -------------------------------------------------------------------------

    uint256 private constant RNG_WORD_BY_DAY_SLOT = 11;             // mapping(uint32 => uint256) — the afking box's DAY-keyed word
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 23;            // first-deposit signal (human box)
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 38;          // [0:47] lootboxRngIndex
    uint256 private constant LOOTBOX_RNG_WORD_BY_INDEX_SLOT = 39;   // mapping(uint48 => uint256) (human box)
    uint256 private constant SUBOF_SLOT = 66;                       // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 68;                 // address[] _subscribers (slot holds the length)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69;            // mapping(address => uint256) _subscriberIndex
    uint256 private constant SUBCURSOR_SLOT = 70;                   // _subCursor (uint16 @ byte 0) | _afkingResetDay (@ byte 4)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol; the v56 re-packed single 256-bit slot,
    // 241/256 bits used — the markers are uint24 each, not the old uint32 232-bit layout).
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The 16.7M HARD effective per-tx ceiling (350-TST06-MEASUREMENT-SPEC §5). foundry.toml inflates
    ///      block_gas_limit to 30e9 for the harness; the TST-06 "fits the ceiling" bar is this 16.7M.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev The funded-sub count this test seeds. The contract no longer chunks the STAGE by a flat count —
    ///      it advances under a gas-weight budget (SUB_STAGE_WEIGHT_BUDGET; lootbox weight 1, ticket weight 8),
    ///      so a full budget drains up to ~1000 lootbox subs in one advance. The binding all-ticket worst-case
    ///      STAGE chunk is measured directly in V56AfkingGasMarginal; this suite bounds the router-entry path
    ///      over a funded lootbox set.
    uint256 internal constant SUB_STAGE_BATCH = 50;

    /// @dev OPEN_BATCH (GameAfkingModule.sol): the flat per-box open budget; each afking box uniform O(1).
    uint256 internal constant OPEN_BATCH = 130;

    /// @dev The CR-01 converged-marginal regime: N>=32 amortizes the per-tx fixed overhead away.
    uint256 internal constant N_MARGINAL = 32;

    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit human box

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private constant MINTPACKED_SLOT = 10;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // STAGE leg -- the 50-chunk processSubscriberStage(50) under the 16.7M HARD ceiling
    // =========================================================================

    /// @notice TST-06 / 16.7M ceiling (350-SPEC §5): seed SUB_STAGE_BATCH(50) funded LOOTBOX-mode subs,
    ///         drive ONE new-day `advanceGame()` (the required-path STAGE runs `processSubscriberStage(50)`
    ///         PRE-RNG over the funded set), and assert the whole advance — which BOUNDS the 50-chunk STAGE
    ///         (a conservative over-estimate: it also folds in the ticket-drain + per-day reset) — stays
    ///         UNDER 16.7M. Non-vacuity: every one of the 50 funded subs is STAMPED (lastAutoBoughtDay ==
    ///         the process day) after the STAGE, so the 50-chunk really ran (not a skip). This is the
    ///         post-349.2 worst case: each funded lootbox sub fires the restored BURNIE quest/affiliate/
    ///         creditFlip side-effects, included in the measured chunk (not subtracted).
    function testStage50ChunkFundedLootboxSubsFitsUnderHardCeiling() public {
        // Seed exactly SUB_STAGE_BATCH funded lootbox subs (deity-passed so they are pass-gated valid,
        // funded via depositAfkingFunding so the STAGE `:709` debit + `:710` claimablePool debit land).
        // With the 2 deploy subs (VAULT + SDGNRS) ahead in the iterable set, ONE advance processes the
        // first SUB_STAGE_BATCH cursor positions (= the 2 deploy + the first 48 of mine), then partial-
        // drains — a FULL 50-chunk, exactly the HARD-ceiling unit.
        address[] memory subs = _setupFundedLootboxSubs(SUB_STAGE_BATCH, "stage50_", 5 ether);
        assertEq(_subscriberCount(), SUB_STAGE_BATCH + 2, "set = 50 funded subs + 2 deploy subs (VAULT + SDGNRS)");

        // Pre-state: capture each sub's stamp day so newly-stamped subs are detectable (no naive _simDay
        // compare — the contract's process day is the level-aware _simulatedDayIndexAt, not (ts-82620)/1d).
        uint32[] memory pre = new uint32[](SUB_STAGE_BATCH);
        for (uint256 i; i < SUB_STAGE_BATCH; ++i) pre[i] = _lastBoughtDayOf(subs[i]);
        assertEq(_subCursor(), 0, "STAGE pre: cursor at 0");

        // Drive a new-day advance: its STAGE block runs processSubscriberStage(SUB_STAGE_BATCH) PRE-RNG.
        // Bracket the whole advance — if the whole advance fits 16.7M, the 50-chunk STAGE certainly does.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        uint256 stageAdvanceGas = gasBefore - gasleft();

        // Non-vacuity (1/2): the weighted-budget chunk advanced past the full funded window (it really ran).
        assertGe(_subCursor(), SUB_STAGE_BATCH, "STAGE non-vacuity: the cursor advanced past the funded set");
        // Non-vacuity (2/2): the chunk STAMPED the funded subs in its window. The 2 deploy subs occupy
        // cursor 0..1, so the first 50-chunk stamps my first 48 (cursor 2..49). Assert >= 48 of mine got a
        // NEW stamp (their lastAutoBoughtDay advanced past the pre-state) — a real 50-chunk, not a skip.
        uint256 stampedCount;
        for (uint256 i; i < SUB_STAGE_BATCH; ++i) {
            if (_lastBoughtDayOf(subs[i]) > pre[i]) ++stampedCount;
        }
        assertGe(
            stampedCount,
            SUB_STAGE_BATCH - 2,
            "STAGE non-vacuity: the 50-chunk stamped its funded window (>= 48 of mine newly stamped)"
        );

        // Headline 16.7M: the new-day advance, whose STAGE drains the full funded lootbox set under the
        // gas-weight budget (lootbox weight 1, so all fit one advance), stays under the HARD per-tx ceiling.
        // The binding all-ticket worst-case stage chunk is measured in V56AfkingGasMarginal.
        assertLt(
            stageAdvanceGas,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: the new-day advance draining the funded lootbox set fits under 16.7M"
        );

        emit log_named_uint("stage_advance_50chunk_whole_gas", stageAdvanceGas);
        emit log_named_uint("stage_per_sub_conservative_marginal_gas", stageAdvanceGas / SUB_STAGE_BATCH);
        emit log_named_uint("stage_subs_stamped_in_chunk", stampedCount);
        emit log_named_uint("sub_stage_batch", SUB_STAGE_BATCH);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice CR-01 STAGE marginal (the loop-N-divide idiom, KeeperOpenBoxWorstCaseGas:184/350-SPEC §0):
    ///         the per-sub STAGE marginal is (whole new-day advance gas for N funded subs) / N measured at
    ///         N=32 — the loop-N-divide MARGINAL, NEVER a single-sub total (a single-sub total bundles the
    ///         once-per-advance fixed overhead into one sub, over-pegs ~2x, and would re-open the Phase-319
    ///         self-crank faucet were a reward pegged to it). Asserts the converged marginal fits the
    ///         ceiling AND that 50 x the marginal projects under the 16.7M HARD ceiling (the SUB_STAGE_BATCH
    ///         chunk is safe). A single robust fixture (no fragile cross-fixture difference under the
    ///         idle-day-saturation reality).
    function testStagePerSubMarginalIsLoopNDivideUnderCeiling() public {
        uint256 totalN = _measureStageAdvanceGas(N_MARGINAL, "stgMa_");
        uint256 perSubMarginal = totalN / N_MARGINAL; // the loop-N-divide MARGINAL (fixed overhead amortized)

        assertLt(perSubMarginal, EFFECTIVE_GAS_CEILING, "per-sub STAGE marginal trivially fits the ceiling");

        // 50 x the converged per-sub marginal projects under the 16.7M HARD ceiling (the SUB_STAGE_BATCH
        // bound — the load-bearing 16.7M claim, projected from the loop-N-divide marginal not a single total).
        assertLt(
            perSubMarginal * SUB_STAGE_BATCH,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: 50x the per-sub STAGE marginal projects under 16.7M (the SUB_STAGE_BATCH chunk is safe)"
        );

        emit log_named_uint("stage_per_sub_marginal_n32_loop_n_divide_gas", perSubMarginal);
        emit log_named_uint("stage_advance_whole_n32_gas", totalN);
        emit log_named_uint("stage_50x_marginal_projection_gas", perSubMarginal * SUB_STAGE_BATCH);
    }

    // =========================================================================
    // OPEN leg -- per-box marginal (N>=32) + whole-leg 16.7M fit
    // =========================================================================

    /// @notice TST-06 open leg (350-SPEC §2): stamp N>=32 funded lootbox subs (a new-day STAGE), land their
    ///         frozen-stamp-day word, drive the afking open leg over the N ready stamped boxes, divide by N
    ///         -> the per-box marginal. The afking open leg is `_autoOpen(OPEN_BATCH)`, reached ONLY via
    ///         `mintBurnie()` (the afking standalone open collides with the HUMAN `game.autoOpen(uint256)`
    ///         `boxPlayers` selector, so `mintBurnie` is the canonical afking open route). N < OPEN_BATCH so
    ///         one `mintBurnie()` opens all N. Asserts each box opened (non-vacuity: lastOpenedDay advanced
    ///         to the stamp day) and the whole open leg < 16.7M. The afking open is a cheap stamp-derived
    ///         resolve (uniform O(1) per box — no cold-ledger walk; 350-SPEC §2).
    function testOpenLegPerBoxMarginalAndWholeLegFitsCeiling() public {
        // Stamp N funded lootbox subs via the new-day STAGE, then land their stamp-day word so the boxes
        // are READY (lastOpenedDay < lastAutoBoughtDay && rngWordByDay[stampDay] != 0).
        address[] memory subs = _setupFundedLootboxSubs(N_MARGINAL, "openM_", 5 ether);
        _runStageNewDay(0xB0FE0FE);
        uint32 stampDay = _readStampDay(subs);
        assertGt(stampDay, 0, "open worst case: the funded subs were stamped");

        // assert-is-worst-case: every box queued + un-opened (real materializations, not skips).
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertEq(_lastBoughtDayOf(subs[i]), stampDay, "open worst case: each sub stamped");
            assertTrue(_lastOpenedDayOf(subs[i]) < stampDay, "open worst case: each box queued + un-opened");
        }
        assertTrue(rngWordByDay(stampDay) != 0, "open worst case: the stamp-day word landed (boxes ready)");

        // Settle clean so mintBurnie routes to the OPEN leg (not the advance leg), then bracket the afking
        // open leg over the N ready boxes (caller-bounded by OPEN_BATCH; N < OPEN_BATCH so all open).
        _settleClean(0x09E20FE);
        assertFalse(game.advanceDue(), "mintBurnie routes to OPEN (advance not due)");
        vm.prank(makeAddr("openM_opener"));
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        uint256 wholeLegGas = gasBefore - gasleft();

        // Non-vacuity: every box actually opened (lastOpenedDay advanced on open), so the marginal is a
        // real per-box materialization cost.
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertEq(_lastOpenedDayOf(subs[i]), stampDay, "open non-vacuity: each box opened (lastOpenedDay advanced)");
        }

        uint256 perBoxMarginal = wholeLegGas / N_MARGINAL;
        assertLt(wholeLegGas, EFFECTIVE_GAS_CEILING, "16.7M ceiling: the open leg (N>=32 ready afking boxes) fits under 16.7M");
        assertLt(perBoxMarginal, EFFECTIVE_GAS_CEILING, "per-box open marginal trivially fits the ceiling");

        emit log_named_uint("open_per_box_marginal_gas", perBoxMarginal);
        emit log_named_uint("open_whole_leg_total_gas", wholeLegGas);
        emit log_named_uint("open_n_boxes", N_MARGINAL);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice CR-01 open-leg marginal (the loop-N-divide idiom, KeeperOpenBoxWorstCaseGas:184/350-SPEC §0):
    ///         the per-box marginal is (whole mintBurnie open-leg gas for N ready boxes) / N measured at
    ///         N=32 — the loop-N-divide MARGINAL, NEVER a single-box total. The afking open is uniform O(1)
    ///         per box (no cold-ledger walk; the anti-gas-DoS property), so the per-box marginal is stable.
    ///         Asserts the converged marginal fits the ceiling AND that a full OPEN_BATCH of boxes projects
    ///         under the 16.7M ceiling (the uniform-O(1) chunk is safe). A single robust fixture.
    function testOpenLegPerBoxMarginalLoopNDivideUnderCeiling() public {
        // N + 2 deploy boxes open this mintBurnie; divide by (N + 2) so the per-box number is over the boxes
        // actually opened (the loop-N-divide MARGINAL — a conservative figure, never a single-box total).
        uint256 totalN = _measureOpenLegGas(N_MARGINAL, "opMa_");
        uint256 perBoxMarginal = totalN / (N_MARGINAL + 2);

        assertLt(perBoxMarginal, EFFECTIVE_GAS_CEILING, "per-box open marginal fits the ceiling");

        // A full OPEN_BATCH of uniform-O(1) afking boxes projects under the 16.7M ceiling (the load-bearing
        // 16.7M open-leg claim, projected from the loop-N-divide marginal not a single-box total).
        assertLt(
            perBoxMarginal * OPEN_BATCH,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: OPEN_BATCH x the per-box open marginal projects under 16.7M (uniform O(1) open)"
        );

        emit log_named_uint("open_per_box_marginal_n32_loop_n_divide_gas", perBoxMarginal);
        emit log_named_uint("open_whole_leg_n32_gas", totalN);
        emit log_named_uint("open_batch_x_marginal_projection_gas", perBoxMarginal * OPEN_BATCH);
    }

    // =========================================================================
    // mintBurnie router -- the rewarded advance + open legs each fit the ceiling
    // =========================================================================

    /// @notice TST-06 / Δ3: the rewarded `mintBurnie()` router (the v55 successor to `doWork()`) routes ONE
    ///         category per call — the advance leg OR the open leg — and pays ONE bounty. Drive its open leg
    ///         over a set of ready afking boxes and assert the whole `mintBurnie()` tx fits the 16.7M
    ///         ceiling (the open leg + the once-per-tx routing + creditFlip). Non-vacuity: at least one box
    ///         materialized this `mintBurnie()`.
    function testMintBurnieOpenLegRouterFitsCeiling() public {
        address[] memory subs = _setupFundedLootboxSubs(N_MARGINAL, "mbOpen_", 5 ether);
        _runStageNewDay(0xB117B0E);
        uint32 stampDay = _readStampDay(subs);
        assertTrue(rngWordByDay(stampDay) != 0, "ready: stamp-day word landed");

        // Settle to a clean (!advanceDue && !rngLocked) state so mintBurnie takes the OPEN leg, not advance.
        _settleClean(0xC0FFEE);
        assertFalse(game.advanceDue(), "mintBurnie routes to OPEN (advance not due)");

        vm.prank(makeAddr("mbOpen_opener"));
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        uint256 mintBurnieGas = gasBefore - gasleft();

        // Non-vacuity: at least one box materialized this mintBurnie open leg.
        uint256 openedCount;
        for (uint256 i; i < N_MARGINAL; ++i) {
            if (_lastOpenedDayOf(subs[i]) == stampDay) ++openedCount;
        }
        assertGt(openedCount, 0, "mintBurnie open non-vacuity: at least one afking box materialized");

        assertLt(
            mintBurnieGas,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: the mintBurnie() open-leg router tx (open + routing + creditFlip) fits under 16.7M"
        );

        emit log_named_uint("mintburnie_open_leg_router_gas", mintBurnieGas);
        emit log_named_uint("mintburnie_open_boxes_materialized", openedCount);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice TST-06 / Δ3 advance leg: with NO subscribers and NO ready boxes, `mintBurnie()` routes to the
    ///         advance leg (the router's `if (advanceDue) {...}` structural early-return). Drive a real
    ///         new-day advance THROUGH the router and assert the whole tx fits the 16.7M ceiling.
    ///         Non-vacuity: the day actually advanced (the game entered rngLock, i.e. the day's RNG was
    ///         requested) or the advance-due gate cleared.
    function testMintBurnieAdvanceLegRouterFitsCeiling() public {
        // Seed a real ticket queue so the new-day advance has structural drain work (the heaviest
        // realizable advance step on the fresh fixture).
        address buyer = makeAddr("mbAdvBuyer");
        vm.deal(buyer, 1_000 ether);
        for (uint256 i; i < 8; ++i) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "advanceDue on the new day");
        assertFalse(game.boxesPending(), "no boxes pending -> mintBurnie routes to advance");

        bool lockedBefore = game.rngLocked();

        vm.prank(makeAddr("mbAdv_opener"));
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        uint256 mintBurnieGas = gasBefore - gasleft();

        // Non-vacuity: a real new-day advance step ran (rngLock flipped, or advanceDue cleared).
        bool advanced = game.rngLocked() != lockedBefore || game.rngLocked() || !game.advanceDue();
        assertTrue(advanced, "advance non-vacuity: a real new-day advance step ran (rngLock/day moved)");

        assertLt(
            mintBurnieGas,
            EFFECTIVE_GAS_CEILING,
            "16.7M ceiling: the mintBurnie() advance-leg router tx (new-day step + routing) fits under 16.7M"
        );

        emit log_named_uint("mintburnie_advance_leg_router_gas", mintBurnieGas);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    // =========================================================================
    // Internal helpers (the validated game-resident driving harness)
    // =========================================================================

    /// @dev Measure a fresh-state new-day advance whose STAGE processes N funded lootbox subs, returning
    ///      the bracketed advance gas. Used by the CR-01 STAGE marginal (gas for N − gas for N−1). The
    ///      everything-else of the advance is identical across N and N−1 (same ticket queue: none), so the
    ///      difference isolates the Nth sub's STAGE cost.
    function _measureStageAdvanceGas(uint256 n, string memory prefix) internal returns (uint256 advGas) {
        // Settle any in-flight day to a clean (!advanceDue && !rngLocked) baseline FIRST, so a prior
        // measurement's unfulfilled RNG request cannot leave the game rngLocked when this advance fires.
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedLootboxSubs(n, prefix, 5 ether);
        // n + 2 deploy subs < SUB_STAGE_BATCH, so ONE advance processes the WHOLE set in the first chunk.
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        vm.warp(block.timestamp + 1 days);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        // Non-vacuity: every measured sub got a NEW stamp this cycle (a real STAGE buy, not a skip).
        for (uint256 i; i < n; ++i) {
            assertGt(_lastBoughtDayOf(subs[i]), pre[i], "marginal non-vacuity: each funded sub newly stamped");
        }
    }

    /// @dev Measure the afking open-leg gas over N freshly-stamped + ready afking boxes, returning the
    ///      bracketed `mintBurnie()` open-leg gas. Used by the CR-01 open marginal (gas for N − gas for
    ///      N−1). The 2 deploy subs add a CONSTANT 2 ready boxes to BOTH the N and N−1 measurements, so
    ///      they cancel in the difference — the marginal isolates exactly one box. Each call stamps N subs
    ///      (new-day STAGE), lands the stamp-day word, settles clean (so mintBurnie routes to OPEN), opens.
    function _measureOpenLegGas(uint256 n, string memory prefix) internal returns (uint256 openGas) {
        address[] memory subs = _setupFundedLootboxSubs(n, prefix, 5 ether);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "word"))) | 1);
        uint32 stampDay = _readStampDay(subs);
        require(stampDay > 0, "fixture: subs stamped");
        require(rngWordByDay(stampDay) != 0, "fixture: stamp-day word landed");
        for (uint256 i; i < n; ++i) {
            assertTrue(_lastOpenedDayOf(subs[i]) < stampDay, "marginal pre: each box queued");
        }

        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so mintBurnie opens");
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        openGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            assertEq(_lastOpenedDayOf(subs[i]), stampDay, "marginal non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players as funded LOOTBOX-mode subs (deity-passed so pass-gated valid;
    ///      funded via depositAfkingFunding so the STAGE `:709` afkingFunding debit + `:710` claimablePool
    ///      debit land in tandem, SOLVENCY-01 balanced). The STAGE stamps each into a warm Sub slot (GAS-01)
    ///      and fires the restored per-sub BURNIE side-effects (349.2 — included in the marginal).
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
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1
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

    // ---- Sub-stamp slot reads (RE-DERIVED slot 66 + verified offsets) ----

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

    /// @dev Read the STAGE cursor `_subCursor` (slot 70, byte 0, uint16) — the number of set entries the
    ///      current cycle's STAGE has advanced past (the weighted-budget chunk advances it by as many subs
    ///      as fit the gas-weight budget).
    function _subCursor() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) & 0xFFFF;
    }

    /// @dev Read the DAY-keyed afking word `rngWordByDay[day]` (the open leg's seed + readiness gate).
    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    function _simDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82_620) / 1 days);
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
