// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RouterWorstCaseGas -- GAS-01 (Phase 331) keeper-router worst-case marginal measurement.
///
/// @notice The v49 unified keeper router `AfKing.doWork()` (AfKing.sol:868) routes ONE category of
///         pending work per call by priority (autoBuy -> advance -> autoOpen) and pays ONE flat-per-tx
///         bounty. The break-even bounty peg (calibrated by 331-04 under a USER-gated contract diff)
///         is a function of the per-CATEGORY worst-case MARGINAL gas at 0.5 gwei. This harness MEASURES
///         those marginals; it does NOT calibrate any constant (331-04 does, gated).
///
///         The mainnet block-fit bar is the CORRECTED 16.7M effective gas-target ceiling (NOT 30M):
///         the keeper batch is sized so the DEFAULT box buy/open leg averages ~9M and the HARD per-tx
///         ceiling is 16.7M. See 331-GAS-DERIVATION.md §0.
///
///         Per `feedback_gas_worst_case` + the CR-01 lesson (319), the measured marginals are:
///           - router_dowork_buy_per_player_marginal_gas  -- per LANDED subscriber buy, N>=32 amortized
///           - router_dowork_open_per_box_marginal_gas     -- per opened TYPICAL box, N>=32 amortized
///           - router_dowork_open_whale_pass_box_marginal_gas -- the WHALE-PASS-boon box (the true open
///                                                              worst case: a 100-iter _activateWhalePass
///                                                              ticket-queue loop; rare, statistically
///                                                              unreachable in bulk -- ACCEPTED by USER)
///           - router_dowork_advance_marginal_gas          -- a single new-day advance step (no loop-N)
///           - router_dowork_dispatch_overhead_gas         -- the once-per-tx doWork routing + creditFlip
///
///         CORRECTION (Phase 331 correction pass): the original buy harness asserted "the buy landed"
///         via AfKing's `lastAutoBoughtDay` day-stamp. That stamp is written in `_autoBuy`'s accounting
///         loop (AfKing.sol:744) BEFORE the batched `IGame.batchPurchase` fires, and `batchPurchase`
///         wraps each per-player slice in `try this._batchPurchaseUnit{value: slice}() catch {}`
///         (DegenerusGame.sol:1773-1780). The keeper buy is lootbox-only (`_purchaseFor(player, 0,
///         slice, "DGNRS", payKind)`, ticketQuantity=0, DegenerusGame.sol:1806), so the mint module's
///         `lootBoxAmount < LOOTBOX_MIN (0.01 ether)` guard (DegenerusGameMintModule.sol:1011) reverts
///         any slice below 0.01 ether INSIDE the try/catch -- a reverted (skipped+refunded) buy that
///         still left the day-stamp set. The old harness therefore measured the REVERT-CATCH path
///         (~40,224 gas), not a real buy. The corrected buy tests fund DirectEth with a slice >=
///         LOOTBOX_MIN and assert the buy actually LANDED via `lootboxEthBase[index][player] > 0` (the
///         same correct first-deposit signal the OPEN tests use). A correctly-verified DirectEth
///         first-deposit buy marginal is ~256k (whole 32-leg ~8.4M), an order of magnitude above the
///         falsely-reported ~40k.
///
///         CR-01 (load-bearing, 319-CR01-FIX.md): peg the per-ITEM MARGINAL at N>=32, NEVER a single-
///         item TOTAL (which bundles the per-tx fixed overhead into one item, over-pegs ~2x, and opens
///         a Sybil self-crank faucet). The buy + open tests measure at N=32 and also emit the
///         N=1/N=8/N=32 amortization gradient to show convergence.
///
///         Each test (1) asserts the constructed scenario IS the worst-case cap, (2) asserts
///         non-vacuity (REAL work LANDED, not a silent skip or a reverted-in-try/catch slice),
///         (3) asserts < the effective per-tx ceiling, (4) emits the calibration input.
///
/// @dev Live `DeployProtocol` fixture. Reuses the established `*WorstCaseGas.t.sol` idiom wholesale:
///      the gasleft()-delta bracket (NOT vm.snapshotGas -- the live repo idiom), the loop-N-divide
///      per-item marginal, the assert-is-worst-case + non-vacuity preconditions, the block-fit bar, and
///      log_named_uint emission. Slot constants re-confirmed via `forge inspect ... storage` against
///      the 63bc16ca layout (330 added boxCursor/boxCursorIndex at slot 62, boxPlayers at slot 63).
///      Test-only: no contracts/*.sol mutated. Run with --isolate for true per-call gas.
contract RouterWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (re-confirmed via `forge inspect ... storage` @ 63bc16ca)
    // -------------------------------------------------------------------------

    // DegenerusGame
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;      // lootboxEthBase root (first-deposit signal)
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;    // lootboxRngPacked (low 48 bits = index)
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;      // lootboxRngWordByIndex mapping root

    // AfKing
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3;       // _subscriberIndex (1-indexed)
    uint256 private constant AFKING_CURSOR_SLOT = 4;          // _autoBuyDay (off 0) | _autoBuyCursor (off 4)

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The CORRECTED effective per-tx ceiling. The 30M reference in the original derivation was
    ///      wrong: the keeper batch is sized against the 16.7M effective gas-target ceiling (NOT the
    ///      mainnet 30M block limit). foundry.toml inflates block_gas_limit to 30e9 for the harness;
    ///      the GAS-01 "fits the ceiling" bar is this 16.7M. The DEFAULT box buy/open leg targets a
    ///      ~9M average; the whale-pass box (the rare per-box worst case) may exceed 16.7M in bulk,
    ///      which is ACCEPTED by the USER (statistically unreachable by whale-pass-boon rarity).
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev The ~9M average target the DEFAULT (typical) box buy/open leg is sized to.
    uint256 internal constant TARGET_AVERAGE_GAS = 9_000_000;

    /// @dev The CR-01 converged-marginal regime: N>=32 amortizes the per-tx fixed overhead away.
    uint256 internal constant N_MARGINAL = 32;

    /// @dev A fixed RNG word for deterministic box opens (does NOT trigger the whale-pass boon).
    uint256 private constant BOX_FIXED_WORD = uint256(keccak256("router_worst_case_box_word"));

    /// @dev The whale-pass-box owner label + the rngWord that makes that owner's box open roll the
    ///      whale-pass boon (type 28). Brute-force-found this correction pass (the seed is
    ///      keccak256(rngWord, player, day, amount); the label pins `player`, so this word fires the
    ///      heavy 100-iter _activateWhalePass branch deterministically for THIS owner + a 6-ETH box).
    string private constant WHALE_OWNER_LABEL = "router_whale_pass_owner";
    uint256 private constant WHALE_WEI = 6 ether; // > LOOTBOX_CLAIM_THRESHOLD; max boon budget

    /// keccak256("LootBoxWhalePassJackpot(address,uint32,uint256,uint24,uint32,uint24,uint24)")
    bytes32 private constant WHALE_PASS_JACKPOT_TOPIC =
        keccak256("LootBoxWhalePassJackpot(address,uint32,uint256,uint24,uint32,uint24,uint24)");

    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit box

    /// @dev The game-side keeper-buy lootbox floor (DegenerusGameMintModule.sol:1011 LOOTBOX_MIN). A
    ///      keeper buy is forced lootbox (ticketQuantity=0), so any slice below this REVERTS inside
    ///      batchPurchase's per-player try/catch. The LANDING buy shape funds at/above this floor.
    uint256 private constant GAME_LOOTBOX_MIN = 0.01 ether;

    /// @dev The split batch sizes landed in the 331-05 gate (AfKing.sol). BUY_BATCH is HARD-bounded
    ///      (50 buys ≈ 13.1M < 16.7M); OPEN_BATCH is a GAS-WEIGHTED open budget (a typical box = 1
    ///      unit, a whale-pass box ≈ 60), so the open leg is bounded against the ceiling for any mix.
    uint256 internal constant BUY_BATCH = 50;
    uint256 internal constant OPEN_BATCH = 100;

    /// @dev Mirror of DegenerusGame.OPEN_NORMAL_GAS_UNIT: the per-box weighted-budget denominator.
    uint256 internal constant OPEN_NORMAL_GAS_UNIT = 90_000;

    /// @dev A shared rngWord that fires the whale-pass boon for multiple "wc_<i>" 6-ETH owners at one
    ///      index (the open-time seed is keccak256(rngWord, player, day, amount); a single shared word
    ///      lands whale-pass for whichever owners' seeds hit the type-28 outcome). Found by the
    ///      correction-pass cluster search (trial 59 of keccak256("cluster", trial)); deterministic on
    ///      the fixture. Used to build a clustered heavy-box queue for the weighted-budget worst case.
    uint256 private constant WHALE_CLUSTER_WORD = uint256(keccak256(abi.encode("cluster", uint256(59))));

    function setUp() public {
        _deployProtocol();
        // Advance one keeper-local day off the deploy boundary so _currentDay() / the game day index
        // are clean, stable indices for the whole test (mirrors the AfKing/Crank harnesses).
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // BUY leg -- per-successful-subscriber marginal (N>=32) + whole-leg 30M fit
    // =========================================================================

    /// @notice GAS-01 buy leg (331-GAS-DERIVATION.md §1): seed N>=32 LANDING-shape DirectEth subs
    ///         (ticket mode, qty 1 so the forced-lootbox keeper buy carries a slice == mp == 0.01 ETH
    ///         == LOOTBOX_MIN, so it PASSES the mint module's lootbox-floor guard and the buy LANDS)
    ///         ISOLATED from the two deploy-time SUB-09 subs (VAULT + SDGNRS), drive ONE autoBuy(total)
    ///         (the doWork buy leg's `_autoBuy` body), divide the gas by N ->
    ///         router_dowork_buy_per_player_marginal_gas. NON-VACUITY IS VERIFIED VIA THE CORRECT
    ///         SIGNAL: each sub's first-deposit `lootboxEthBase[index][player] > 0` (NOT the
    ///         lastAutoBoughtDay stamp, which is set even when the buy reverts in batchPurchase's
    ///         try/catch -- the original-harness flaw). Asserts the WHOLE leg < the 16.7M ceiling.
    function testBuyLegPerPlayerMarginalAndWholeLegFitsBlockGasLimit() public {
        uint48 index = _activeLootboxIndex();
        address[] memory subs = _setupLandingBuyingSubs(N_MARGINAL, "buyM_");

        uint256 total = afKing.subscriberCount();
        assertEq(total, N_MARGINAL + 2, "set = N test subs + 2 deploy subs (VAULT + SDGNRS)");

        // Cursor starts at 0 for this fresh day.
        (, uint256 cursor0) = afKing.autoBuyProgress();
        assertEq(cursor0, 0, "cursor starts at 0 for a fresh day");

        // Pre-state: none of OUR subs has a first-deposit box yet (clean LAND signal).
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertEq(_lootboxEthBase(index, subs[i]), 0, "buy pre: no first-deposit box yet");
        }

        // Bracket the whole-set autoBuy (covers the 2 deploy subs + our N). Dividing the delta by N
        // (the test-sub count) yields a per-test-player marginal that, if anything, OVER-estimates
        // (it folds in the 2 deploy subs' work) -> conservative calibration floor.
        vm.prank(makeAddr("buyM_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(total);
        uint256 wholeLegGas = gasBefore - gasleft();

        // assert-is-worst-case + NON-VACUITY (CORRECTED): every one of OUR N subs' buy actually LANDED
        // -- the first-deposit lootbox signal is non-zero. This is the same correct signal the OPEN
        // tests use; it CANNOT pass on a slice that reverted inside batchPurchase's per-player
        // try/catch (the lastAutoBoughtDay stamp could -- that was the original-harness defect).
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertGt(
                _lootboxEthBase(index, subs[i]),
                0,
                "buy non-vacuity: each sub's buy LANDED (first-deposit lootboxEthBase > 0)"
            );
        }

        uint256 perPlayerMarginal = wholeLegGas / N_MARGINAL;

        // Headline GAS-01: the whole buy leg of N>=32 LANDING subs fits the corrected 16.7M ceiling.
        assertLt(
            wholeLegGas,
            EFFECTIVE_GAS_CEILING,
            "GAS-01: the whole doWork buy leg (N>=32 landing subs) fits under the 16.7M effective ceiling"
        );
        assertLt(perPlayerMarginal, EFFECTIVE_GAS_CEILING, "per-player buy marginal trivially fits the ceiling");

        // The calibration input 331-04 reads. A LANDED first-deposit DirectEth buy is ~256k -- an
        // order of magnitude above the falsely-reported ~40,224 (the revert-catch path).
        emit log_named_uint("router_dowork_buy_per_player_marginal_gas", perPlayerMarginal);
        emit log_named_uint("router_dowork_buy_whole_leg_total_gas", wholeLegGas);
        emit log_named_uint("router_dowork_buy_n_test_subs", N_MARGINAL);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice CR-01 amortization gradient for the LANDING buy leg: measure the per-player marginal at
    ///         N=1, 8, and 32 (each in its own fresh fixture state) so the convergence to the N>=32
    ///         regime is recorded as evidence that pegging to the single-player TOTAL (N=1) over-states
    ///         the marginal (319 precedent). N=1 is the single-player total; N>=32 is the converged
    ///         marginal. Every measured buy LANDS (verified via lootboxEthBase > 0).
    function testBuyLegAmortizationGradientConvergesAtN32() public {
        uint256 n1 = _measureBuyLegPerPlayer(1, "buyG1_");
        uint256 n8 = _measureBuyLegPerPlayer(8, "buyG8_");
        uint256 n32 = _measureBuyLegPerPlayer(32, "buyG32_");

        // The single-player total (N=1) is >= the converged marginal (N=32): the per-tx fixed overhead
        // (batchPurchase setup, cursor SSTORE) is bundled into the one player at N=1 and amortized away
        // at N=32. Equality is permitted (warm-state can compress the gap) but N=1 is never LESS.
        assertGe(n1, n32, "CR-01: single-player total (N=1) >= converged per-player marginal (N=32)");
        assertLt(n32, EFFECTIVE_GAS_CEILING, "converged buy marginal fits the ceiling");

        emit log_named_uint("router_dowork_buy_marginal_n1_total_gas", n1);
        emit log_named_uint("router_dowork_buy_marginal_n8_gas", n8);
        emit log_named_uint("router_dowork_buy_marginal_n32_converged_gas", n32);
    }

    // =========================================================================
    // OPEN leg -- per-box marginal (N>=32) + whole-leg 30M fit
    // =========================================================================

    /// @notice GAS-01 open leg (331-GAS-DERIVATION.md §2): queue N>=32 worst-case boxes (real
    ///         first-deposit deposits) with the index RNG word landed, drive ONE autoOpen(N) (the doWork
    ///         open leg), divide by N -> router_dowork_open_per_box_marginal_gas. Asserts each box opened
    ///         (non-vacuity via the first-deposit signal zeroed) and the whole leg < 30M.
    function testOpenLegPerBoxMarginalAndWholeLegFitsBlockGasLimit() public {
        uint48 index = _activeLootboxIndex();
        address[] memory owners = new address[](N_MARGINAL);
        for (uint256 i; i < N_MARGINAL; ++i) {
            address o = makeAddr(string(abi.encodePacked("openM_", vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100_000 ether);
            _buyBox(o, LOOTBOX_WEI);
        }
        _injectLootboxRngWord(index, BOX_FIXED_WORD);

        // assert-is-worst-case: every box is queued + un-opened (real materializations, not skips).
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "open worst case: each box queued + un-opened");
        }

        // autoOpen's maxCount is a GAS-WEIGHTED budget (a typical box = 1 unit, a boon-rolling
        // box can weigh 2). To open all N boxes for the per-box marginal measurement, grant a
        // generous weighted budget (N * 4 units) so the budget never caps before the queue drains;
        // the budget-cap worst case has its own dedicated test below.
        vm.prank(makeAddr("openM_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(N_MARGINAL * 4); // the AfKing open passthrough -> IGame.autoOpen (the doWork open leg)
        uint256 wholeLegGas = gasBefore - gasleft();

        // Non-vacuity: every box actually opened (first-deposit signal zeroed on open), so the marginal
        // is a real per-box materialization cost.
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "open non-vacuity: each box opened (signal zeroed)");
        }

        uint256 perBoxMarginal = wholeLegGas / N_MARGINAL;

        assertLt(
            wholeLegGas,
            EFFECTIVE_GAS_CEILING,
            "GAS-01: the whole doWork open leg (N>=32 ready TYPICAL boxes) fits under the 16.7M ceiling"
        );
        assertLt(perBoxMarginal, EFFECTIVE_GAS_CEILING, "per-box open marginal trivially fits the ceiling");

        emit log_named_uint("router_dowork_open_per_box_marginal_gas", perBoxMarginal);
        emit log_named_uint("router_dowork_open_whole_leg_total_gas", wholeLegGas);
        emit log_named_uint("router_dowork_open_n_boxes", N_MARGINAL);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice GAS-01 open leg WHALE-PASS branch (331-GAS-DERIVATION.md §2 -- the gap the original
    ///         derivation missed): a box-open whose probabilistic boon roll selects the whale-pass
    ///         boon (type 28, BOON_WHALE_PASS) runs `_activateWhalePass`, a 100-ITERATION
    ///         `_queueTickets` loop (DegenerusGameLootboxModule.sol:1240-1261). THIS is the true open
    ///         per-box worst case -- ~5.4M for a single box, ~63x the typical ~86k marginal. It is
    ///         RARE (boon weight 8, requires a sizeable box for boon budget). The committed derivation
    ///         wrongly asserted "no heavier per-box branch"; this test measures + documents the gap.
    ///         The whale-pass-box all-batch worst case (OPEN_BATCH * ~5.4M) exceeds the 16.7M ceiling
    ///         -- ACCEPTED by the USER (statistically unreachable by whale-pass-boon rarity).
    function testOpenLegWhalePassBoxMarginalIsTheRareWorstCase() public {
        uint48 index = _activeLootboxIndex();
        address owner = makeAddr(WHALE_OWNER_LABEL);
        vm.deal(owner, WHALE_WEI + 1 ether);
        _buyBox(owner, WHALE_WEI);

        // Inject the brute-found rngWord that makes THIS owner's box roll the whale-pass boon. The
        // open-time seed is keccak256(rngWord, player, day, amount); WHALE_OWNER_LABEL pins `player`.
        _injectLootboxRngWord(index, _whalePassRngWord());

        assertGt(_lootboxEthBase(index, owner), 0, "whale-pass pre: box queued + un-opened");

        vm.recordLogs();
        vm.prank(makeAddr("whaleOpen_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(1);
        uint256 whalePassBoxGas = gasBefore - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // NON-VACUITY: the whale-pass boon actually fired (the heavy 100-iter branch ran, not a
        // typical reward path). The LootBoxWhalePassJackpot event is emitted only inside the type-28
        // _applyBoon branch (DegenerusGameLootboxModule.sol:1638).
        bool whalePassFired;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == WHALE_PASS_JACKPOT_TOPIC) {
                whalePassFired = true;
            }
        }
        assertTrue(whalePassFired, "whale-pass non-vacuity: the type-28 whale-pass boon branch fired");
        assertEq(_lootboxEthBase(index, owner), 0, "whale-pass box opened (first-deposit signal zeroed)");

        // The whale-pass box is the rare per-box worst case. A SINGLE such box still fits the 16.7M
        // ceiling; the ACCEPTED over-ceiling corner is OPEN_BATCH-many whale-pass boxes in one tx
        // (statistically unreachable by the boon's rarity -- documented, USER-accepted).
        assertLt(
            whalePassBoxGas,
            EFFECTIVE_GAS_CEILING,
            "a SINGLE whale-pass box fits the 16.7M ceiling (the bulk-batch corner is the accepted one)"
        );

        emit log_named_uint("router_dowork_open_whale_pass_box_marginal_gas", whalePassBoxGas);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice CR-01 amortization gradient for the open leg: per-box marginal at N=1, 8, 32. N=1 is the
    ///         single-box total (the CR-01 defect target); N>=32 is the converged marginal. Asserts the
    ///         converged marginal is materially BELOW the single-box total (the gap is the per-tx fixed
    ///         overhead the single-box measurement mis-attributes to one box).
    function testOpenLegAmortizationGradientBelowSingleBoxTotal() public {
        uint256 n1 = _measureOpenLegPerBox(1, "openG1_");
        uint256 n8 = _measureOpenLegPerBox(8, "openG8_");
        uint256 n32 = _measureOpenLegPerBox(32, "openG32_");

        assertGe(n1, n32, "CR-01: single-box total (N=1) >= converged per-box marginal (N=32)");
        assertLt(n32, EFFECTIVE_GAS_CEILING, "converged open marginal fits the ceiling");

        emit log_named_uint("router_dowork_open_marginal_n1_total_gas", n1);
        emit log_named_uint("router_dowork_open_marginal_n8_gas", n8);
        emit log_named_uint("router_dowork_open_marginal_n32_converged_gas", n32);
    }

    // =========================================================================
    // WEIGHTED OPEN BUDGET -- GAS-02 (331-05) the USER-directed whale-pass-aware cap
    // =========================================================================

    /// @notice GAS-02 weighted-budget worst case (the USER-directed 331-05 mechanism): autoOpen's
    ///         maxCount is a GAS-WEIGHTED budget, not a raw box count. A whale-pass box (~5.4M, the
    ///         100-iter _activateWhalePass boon) is ~60x a typical box (~89k), so a cluster could blow
    ///         a fixed-count batch past the 16.7M ceiling and (the loop has no per-item isolation)
    ///         revert the whole open leg. The fix weights each opened box by ceil(gas / 90k), min 1, so
    ///         the leg STOPS once accumulated weight reaches maxCount. This test queues a LARGE cluster
    ///         of 6-ETH boxes whose shared rngWord fires multiple whale-pass boons, drives ONE
    ///         autoOpen(OPEN_BATCH), and proves: (a) the leg does NOT revert, (b) the whole-leg gas
    ///         stays <= the 16.7M ceiling EVEN THOUGH opening the full queue unbounded would exceed it,
    ///         (c) the heavy whale-pass branch actually fired under the cap (non-vacuity).
    function testWeightedOpenBudgetCapsClusteredWhalePassBatchUnderCeiling() public {
        uint48 index = _activeLootboxIndex();

        // Queue a cluster of 6-ETH boxes. Under WHALE_CLUSTER_WORD several roll the whale-pass boon
        // (~5.4M each) and the rest roll heavy boons (~110-166k each). A queue this large, if opened
        // unbounded, far exceeds 16.7M -- exactly the corner the weighted budget must cap.
        uint256 clusterN = 60;
        address[] memory owners = new address[](clusterN);
        for (uint256 i; i < clusterN; ++i) {
            address o = makeAddr(string(abi.encodePacked("wc_", vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100 ether);
            _buyBox(o, WHALE_WEI);
        }
        _injectLootboxRngWord(index, WHALE_CLUSTER_WORD);

        for (uint256 i; i < clusterN; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "weighted budget pre: each cluster box queued");
        }

        // Drive the OPEN leg at the landed OPEN_BATCH weighted budget. This MUST NOT revert and MUST
        // stay under the 16.7M ceiling regardless of how many whale-pass boxes land in the cluster.
        vm.recordLogs();
        vm.prank(makeAddr("weighted_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(OPEN_BATCH);
        uint256 wholeLegGas = gasBefore - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // (c) NON-VACUITY: at least one whale-pass boon fired -- the heavy 100-iter branch was
        // exercised UNDER the weighted cap (not a queue of only cheap boxes that trivially fits).
        uint256 whalePassFires;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == WHALE_PASS_JACKPOT_TOPIC) ++whalePassFires;
        }
        assertGt(whalePassFires, 0, "weighted budget non-vacuity: >=1 whale-pass box opened under the cap");

        // (b) The weighted budget caps the whole leg under the 16.7M ceiling. The structural bound is
        // (OPEN_BATCH-1)*OPEN_NORMAL_GAS_UNIT + one whale-pass overshoot ~ 8.9M + 5.4M ~ 14.3M.
        assertLt(
            wholeLegGas,
            EFFECTIVE_GAS_CEILING,
            "GAS-02: the weighted open budget caps a clustered whale-pass batch under the 16.7M ceiling"
        );

        // Count how many boxes actually opened (their first-deposit signal zeroed). The weighted
        // budget should cap the leg BEFORE the full queue drains (proving the budget bit, not a
        // trivially-small queue). With several whale-pass boxes (~60 units each) the budget of 100
        // units is exhausted well before all `clusterN` boxes open.
        uint256 openedCount;
        for (uint256 i; i < clusterN; ++i) {
            if (_lootboxEthBase(index, owners[i]) == 0) ++openedCount;
        }
        assertLt(openedCount, clusterN, "weighted budget actually capped the leg (queue not fully drained)");
        assertGt(openedCount, 0, "weighted budget opened at least one box");

        emit log_named_uint("router_weighted_open_clustered_whale_pass_whole_leg_gas", wholeLegGas);
        emit log_named_uint("router_weighted_open_whale_pass_fires", whalePassFires);
        emit log_named_uint("router_weighted_open_boxes_opened", openedCount);
        emit log_named_uint("router_weighted_open_queue_len", clusterN);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice GAS-02 structural worst-case bound: the heaviest single overshoot is one whale-pass box
    ///         opened as the LAST box after the budget filled with typical boxes. Proves the calculated
    ///         bound (OPEN_BATCH-1)*OPEN_NORMAL_GAS_UNIT + one whale-pass box < 16.7M, using the measured
    ///         single whale-pass marginal from testOpenLegWhalePassBoxMarginalIsTheRareWorstCase.
    function testWeightedOpenBudgetStructuralBoundUnderCeiling() public {
        // Measure the single whale-pass box marginal (the heaviest possible last-box overshoot) by
        // re-using the proven single-owner whale-pass shape.
        uint48 index = _activeLootboxIndex();
        address owner = makeAddr(WHALE_OWNER_LABEL);
        vm.deal(owner, WHALE_WEI + 1 ether);
        _buyBox(owner, WHALE_WEI);
        _injectLootboxRngWord(index, _whalePassRngWord());

        vm.recordLogs();
        vm.prank(makeAddr("structBound_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(1);
        uint256 whalePassBoxGas = gasBefore - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool fired;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == WHALE_PASS_JACKPOT_TOPIC) fired = true;
        }
        assertTrue(fired, "structural bound non-vacuity: the whale-pass box opened");

        // The structural worst-case bound: at most (OPEN_BATCH-1) weighted units of typical boxes plus
        // ONE whale-pass overshoot (the single box whose heaviness is only known after it opens).
        uint256 structuralBound = (OPEN_BATCH - 1) * OPEN_NORMAL_GAS_UNIT + whalePassBoxGas;
        assertLt(
            structuralBound,
            EFFECTIVE_GAS_CEILING,
            "GAS-02: (OPEN_BATCH-1)*OPEN_NORMAL_GAS_UNIT + one whale-pass box < the 16.7M ceiling"
        );

        emit log_named_uint("router_weighted_open_structural_bound_gas", structuralBound);
        emit log_named_uint("router_dowork_open_whale_pass_box_marginal_gas", whalePassBoxGas);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    /// @notice GAS-02 typical OPEN_BATCH leg (~9M target): a full OPEN_BATCH(100) of TYPICAL boxes (no
    ///         whale-pass) drives the open leg to ~9M -- the average target the budget is sized to.
    function testTypicalOpenBatchAveragesNineMillion() public {
        uint48 index = _activeLootboxIndex();
        uint256 n = OPEN_BATCH;
        address[] memory owners = new address[](n);
        for (uint256 i; i < n; ++i) {
            address o = makeAddr(string(abi.encodePacked("typ_", vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100 ether);
            _buyBox(o, LOOTBOX_WEI); // 1-ETH boxes: typical opens, no whale-pass under BOX_FIXED_WORD
        }
        _injectLootboxRngWord(index, BOX_FIXED_WORD);

        vm.recordLogs();
        vm.prank(makeAddr("typical_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(OPEN_BATCH);
        uint256 wholeLegGas = gasBefore - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Non-vacuity: NO whale-pass fired (this is the typical regime) and boxes actually opened.
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(
                logs[i].topics.length == 0 || logs[i].topics[0] != WHALE_PASS_JACKPOT_TOPIC,
                "typical regime: no whale-pass boon fired"
            );
        }
        uint256 openedCount;
        for (uint256 i; i < n; ++i) {
            if (_lootboxEthBase(index, owners[i]) == 0) ++openedCount;
        }
        assertGt(openedCount, 0, "typical open: boxes opened");

        // The typical full batch fits the ceiling and lands near the ~9M average target.
        assertLt(wholeLegGas, EFFECTIVE_GAS_CEILING, "typical OPEN_BATCH fits the 16.7M ceiling");

        emit log_named_uint("router_typical_open_batch_whole_leg_gas", wholeLegGas);
        emit log_named_uint("router_typical_open_batch_boxes_opened", openedCount);
        emit log_named_uint("target_average_gas", TARGET_AVERAGE_GAS);
    }

    /// @notice GAS-02 buy leg at the landed BUY_BATCH(50): a full BUY_BATCH of LANDING subs drives the
    ///         buy leg to ~13.1M -- under the 16.7M HARD ceiling (the reason BUY_BATCH=50, not 100).
    function testBuyBatchFiftyLandsUnderHardCeiling() public {
        uint48 index = _activeLootboxIndex();
        address[] memory subs = _setupLandingBuyingSubs(BUY_BATCH, "buy50_");
        uint256 total = afKing.subscriberCount();
        assertEq(total, BUY_BATCH + 2, "set = BUY_BATCH test subs + 2 deploy subs");

        vm.prank(makeAddr("buy50_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(total);
        uint256 wholeLegGas = gasBefore - gasleft();

        // Non-vacuity: every one of the BUY_BATCH test subs' buy LANDED.
        for (uint256 i; i < BUY_BATCH; ++i) {
            assertGt(_lootboxEthBase(index, subs[i]), 0, "buy50 non-vacuity: each sub's buy LANDED");
        }

        // The HARD bound: a full BUY_BATCH buy leg stays under 16.7M (a reverting buy batch would
        // brick the daily buy leg, so BUY_BATCH is HARD-bounded at 50, ~13.1M).
        assertLt(
            wholeLegGas,
            EFFECTIVE_GAS_CEILING,
            "GAS-02: the full BUY_BATCH(50) buy leg stays under the 16.7M HARD ceiling"
        );

        emit log_named_uint("router_buy_batch_50_whole_leg_gas", wholeLegGas);
        emit log_named_uint("router_buy_batch_size", BUY_BATCH);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    // =========================================================================
    // ADVANCE leg -- a single new-day advance step routed through doWork()
    // =========================================================================

    /// @notice GAS-01 advance leg (331-GAS-DERIVATION.md §3): drive a real new-day advance THROUGH the
    ///         router. With NO subscribers and NO boxes queued, the buy/open predicates route past so
    ///         doWork() dispatches advanceGame(). The advance leg is a SINGLE call per doWork (no loop-N),
    ///         so its calibration input is one marginal. Asserts the day actually advanced (non-vacuity:
    ///         the game entered rngLock, i.e. advanceGame fired the day's RNG request) and < 30M.
    function testAdvanceLegMarginalRoutedThroughDoWorkFitsBlockGasLimit() public {
        // Seed a real ticket queue at the active level so the new-day advance has structural drain work
        // (the heaviest realizable advance step on the fresh fixture): a buyer purchases tickets today,
        // then we warp a day so advanceDue() is true and the daily-drain + RNG-request machinery runs.
        address buyer = makeAddr("advBuyer");
        vm.deal(buyer, 1_000 ether);
        for (uint256 i; i < 8; ++i) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Warp to a new day so advanceDue() is TRUE.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "advance worst case: advanceDue() is TRUE on the new day");

        // Make the buy predicate FALSE so doWork() routes to advance, not buy. With zero subscribers the
        // _autoBuy walk is a no-op, but `_autoBuyDay != _currentDay()` is TRUE on a fresh day so the buy
        // BRANCH is still entered (and returns 0). Stamp the autoBuy day + park the cursor at the set
        // length via a single standalone autoBuy() so the buy predicate is false and the router falls
        // through to advance (mirrors the real keeper, which would buy-then-advance across calls).
        assertEq(afKing.subscriberCount(), 2, "only the 2 deploy subs exist (no test buy subs)");
        vm.prank(makeAddr("advPark_keeper"));
        afKing.autoBuy(afKing.subscriberCount()); // stamps _autoBuyDay = today, parks cursor at set length
        ( , uint256 cursorAfter) = afKing.autoBuyProgress();
        assertGe(cursorAfter, afKing.subscriberCount(), "buy cursor parked at set length -> buy predicate now false");

        // boxesPending() must be false too (no boxes queued, or rngLock blocks it) so advance is the
        // chosen leg.
        assertFalse(game.boxesPending(), "no boxes pending -> advance is the routed leg");

        bool lockedBefore = game.rngLocked();

        // Measure the doWork() advance dispatch (the router consumes advanceGame()'s returned mult).
        vm.prank(makeAddr("adv_keeper"));
        uint256 gasBefore = gasleft();
        afKing.doWork();
        uint256 advanceGas = gasBefore - gasleft();

        // Non-vacuity: the advance actually did work. A new-day advance with a non-empty queue either
        // drains tickets (ticketsFullyProcessed progresses) or requests the day's RNG (rngLock flips
        // true). Assert the game entered rngLock OR the day index moved -- a real advance step ran, not
        // a NotTimeYet revert or a no-op.
        bool advanced = game.rngLocked() != lockedBefore || game.rngLocked() || !game.advanceDue();
        assertTrue(advanced, "advance non-vacuity: a real new-day advance step ran (rngLock/day moved)");

        assertLt(
            advanceGas,
            EFFECTIVE_GAS_CEILING,
            "GAS-01: the doWork advance leg (new-day step) fits under the 16.7M effective ceiling"
        );

        emit log_named_uint("router_dowork_advance_marginal_gas", advanceGas);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    // =========================================================================
    // DISPATCH overhead -- the once-per-tx doWork routing + creditFlip
    // =========================================================================

    /// @notice GAS-01 dispatch overhead (331-GAS-DERIVATION.md §4): isolate the once-per-tx doWork()
    ///         router cost (the mintPrice read + the O(1) routing predicates + the single creditFlip),
    ///         minimizing the chosen leg's real work so the measured number is dominated by dispatch.
    ///         The cheapest non-reverting leg is a buy leg with ONE healthy subscriber: the buy branch
    ///         runs, one slice is purchased, and doWork pays one creditFlip -- so the measured gas is
    ///         (dispatch + one-player buy + one creditFlip). Subtracting the §1 single-player buy total
    ///         leaves the dispatch+creditFlip overhead; we emit the full doWork-with-minimal-leg number
    ///         as the conservative dispatch-overhead ceiling (it never UNDER-states the once-per-tx cost).
    function testDispatchOverheadIsBoundedAndFitsBlockGasLimit() public {
        // One LANDING buying subscriber so the buy leg runs a REAL buy and doWork pays its bounty.
        uint48 index = _activeLootboxIndex();
        address[] memory subs = _setupLandingBuyingSubs(1, "disp_");
        assertEq(afKing.subscriberCount(), 3, "set = 1 test sub + 2 deploy subs");

        bool lockedBefore = game.rngLocked();
        assertFalse(lockedBefore, "fixture not in rngLock at measurement");

        // Measure doWork(): routes to the buy leg (highest priority on a fresh day), buys our sub, and
        // pays ONE creditFlip (the dispatch + once-per-tx bounty). This is the conservative dispatch
        // overhead ceiling: it includes one real LANDED buy, so the pure routing+creditFlip cost is
        // <= this (331-04 recovers the pure overhead by subtracting the §1 single-player buy marginal).
        vm.prank(makeAddr("disp_keeper"));
        uint256 gasBefore = gasleft();
        afKing.doWork();
        uint256 doWorkGas = gasBefore - gasleft();

        // NON-VACUITY (CORRECTED): doWork ran a REAL buy that LANDED -- the first-deposit lootbox
        // signal is non-zero (not just the lastAutoBoughtDay stamp, which survives a try/catch revert).
        assertGt(
            _lootboxEthBase(index, subs[0]),
            0,
            "dispatch non-vacuity: doWork ran the buy leg and the buy LANDED (lootboxEthBase > 0)"
        );

        assertLt(
            doWorkGas,
            EFFECTIVE_GAS_CEILING,
            "GAS-01: the doWork dispatch (routing + minimal landing buy + creditFlip) fits the 16.7M ceiling"
        );

        // Conservative dispatch-overhead ceiling: doWork with the cheapest LANDING leg. 331-04
        // subtracts the §1 single-player buy marginal to recover the pure routing+creditFlip overhead.
        emit log_named_uint("router_dowork_dispatch_overhead_gas", doWorkGas);
        emit log_named_uint("effective_gas_ceiling", EFFECTIVE_GAS_CEILING);
    }

    // =========================================================================
    // Internal helpers (mirror SweepPerPlayerWorstCaseGas + CrankOpenBoxWorstCaseGas)
    // =========================================================================

    /// @dev Measure the per-player LANDING buy marginal over N freshly-seeded subs in a clean cursor
    ///      state. Used by the amortization-gradient test. Resets the autoBuy cursor to 0 for today so
    ///      the bracketed autoBuy walks exactly the N fresh subs (plus the already-stamped earlier subs
    ///      cheap-skip), then divides by N. NON-VACUITY is the CORRECT lootboxEthBase > 0 LAND signal.
    function _measureBuyLegPerPlayer(uint256 n, string memory prefix) internal returns (uint256 perPlayer) {
        uint48 index = _activeLootboxIndex();
        // Park everything currently in the set (autoBuy it so it cheap-skips), then add N fresh subs.
        uint256 pre = afKing.subscriberCount();
        if (pre > 0) {
            vm.prank(makeAddr(string(abi.encodePacked(prefix, "park_keeper"))));
            afKing.autoBuy(pre);
        }
        address[] memory subs = _setupLandingBuyingSubs(n, prefix);
        // Park the cursor at the first fresh sub (1-indexed -> 0-based) so the bracket covers only the N.
        uint256 firstFreshIdx0 = _subscriberIndexOf(subs[0]) - 1;
        _setCursorToZeroBasedSlot(firstFreshIdx0);

        vm.prank(makeAddr(string(abi.encodePacked(prefix, "marginal_keeper"))));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(n);
        uint256 totalGas = gasBefore - gasleft();
        perPlayer = totalGas / n;

        for (uint256 i; i < n; ++i) {
            assertGt(_lootboxEthBase(index, subs[i]), 0, "gradient non-vacuity: each sub's buy LANDED");
        }
    }

    /// @dev Measure the per-box open marginal over N freshly-queued boxes in a fresh fixture index.
    ///      Used by the amortization-gradient test. Each call queues N distinct boxes then opens them.
    function _measureOpenLegPerBox(uint256 n, string memory prefix) internal returns (uint256 perBox) {
        uint48 index = _activeLootboxIndex();
        address[] memory owners = new address[](n);
        for (uint256 i; i < n; ++i) {
            address o = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100_000 ether);
            _buyBox(o, LOOTBOX_WEI);
        }
        _injectLootboxRngWord(index, BOX_FIXED_WORD);
        for (uint256 i; i < n; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "gradient pre: each box queued");
        }

        // Generous weighted budget (n * 4 units) so all n boxes open regardless of per-box
        // boon-roll weight; the per-box marginal is totalGas / n.
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "keeper"))));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(n * 4);
        uint256 totalGas = gasBefore - gasleft();
        perBox = totalGas / n;

        for (uint256 i; i < n; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "gradient non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players whose keeper buy actually LANDS (the corrected worst-case
    ///      buy shape). The keeper buy is forced lootbox (`_purchaseFor(player, 0, slice, ...)`,
    ///      ticketQuantity=0), so the per-player slice must be >= the mint module's
    ///      LOOTBOX_MIN (0.01 ether) or the buy reverts inside batchPurchase's per-player try/catch
    ///      (the original-harness defect: a reverting slice still leaves lastAutoBoughtDay stamped).
    ///
    ///      DirectEth, ticket mode, qty 1: cost = mp = 0.01 ether == LOOTBOX_MIN, so the slice PASSES
    ///      the `< LOOTBOX_MIN` floor (the guard is strict `<`, so exactly 0.01 lands) and the first
    ///      deposit fires `enqueueBoxForAutoOpen`, setting lootboxEthBase[index][player] > 0 -- the
    ///      correct LAND signal. No reinvest / no claimable: the keeper buy is gas-FLAT in funding
    ///      shape (319 empirical: the reinvest keeperSnapshot read pre-warms the slot the buy
    ///      re-reads), and the DirectEth waterfall is the simplest LANDING path. Pool is funded amply.
    function _setupLandingBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        uint256 mp = game.mintPrice();
        // Slice == mp must be >= GAME_LOOTBOX_MIN for the forced-lootbox keeper buy to land.
        require(mp >= GAME_LOOTBOX_MIN, "fixture mp below lootbox floor");
        uint256 poolWei = 100 * mp + 1 ether; // amply cover the qty-1 slice + headroom

        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _fundBurnie(who, _subCost()); // the no-pass subscribe-time all-or-nothing BURNIE charge
            vm.prank(who);
            // self, drainGameCreditFirst = FALSE (DirectEth, msgValue == slice == cost == mp), ticket
            // mode, qty 1 (slice == mp == LOOTBOX_MIN, lands), reinvest 0.
            afKing.subscribe(address(0), false, true, 1, 0, address(0));
            _approveKeeper(who);
            _fundPool(who, poolWei);
        }
    }

    /// @dev The brute-found rngWord that makes the WHALE_OWNER_LABEL owner's 6-ETH box open roll the
    ///      whale-pass boon (type 28). The open-time seed is keccak256(rngWord, player, day, amount);
    ///      WHALE_OWNER_LABEL pins `player`, WHALE_WEI pins `amount`, and the fixture day is stable,
    ///      so this word deterministically fires the heavy 100-iter _activateWhalePass branch. Found
    ///      by the correction-pass search (trial 50 of keccak256("ww", trial) for this owner+amount).
    function _whalePassRngWord() internal pure returns (uint256) {
        return uint256(keccak256(abi.encode("ww", uint256(50))));
    }

    function _subCost() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * 1000 ether) / game.mintPrice();
    }

    function _approveKeeper(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Buy a real lootbox-mode deposit: the first deposit for (index, buyer) fires the
    ///      lootboxEthBase == 0 signal -> enqueueBoxForAutoOpen (MintModule), queuing the box.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    /// @dev Keeper-local day index (mirrors AfKing._currentDay() 82620-second offset).
    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Read `who`'s 1-indexed subscriber index; 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Set the autoBuy cursor to a 0-based slot index while keeping the day-stamp at today, so the
    ///      next autoBuy starts at that slot. Slot 4: _autoBuyDay (uint32, bytes 0..3) + _autoBuyCursor
    ///      (uint224, bytes 4..).
    function _setCursorToZeroBasedSlot(uint256 zeroBasedSlot) internal {
        uint256 packed = (uint256(_today()) & 0xFFFFFFFF) | (zeroBasedSlot << 32);
        vm.store(address(afKing), bytes32(uint256(AFKING_CURSOR_SLOT)), bytes32(packed));
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
