// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title OpenWalkCompositionGas -- baseline gas measurements for the permissionless box-open
///        path (`game.mintFlip()`'s box-open leg, `GameAfkingModule._autoOpen` + the human
///        `openHumanBoxes` sweep), calibrating how the subscriber-RING SCAN cost composes with
///        the human box sweep. These are neutral engineering measurements for a planned
///        refactor's work-budget weights -- NOT a regression gate; loose assertions only.
///
/// @notice The subject under measurement (`GameAfkingModule._autoOpen`, GameAfkingModule.sol:1562):
///         `mintFlip()`'s OPEN branch first calls `_autoOpen(OPEN_BATCH)` (the afking leg), which
///         does a FULL-RING SCAN: `while (scanned < len && opened < maxCount)` visits up to `len`
///         (the WHOLE `_subscribers` set) even when every box is already opened -- a 0-open result
///         means the whole ring was walked, not just `[cursor, len)` (GameAfkingModule.sol:1583-1588
///         "Full-ring scan" comment). Each visited-but-already-opened sub costs one skip: an
///         `_subscribers[cursor]` SLOAD + the packed `Sub` slot's `lastOpenedDay`/`lastAutoBoughtDay`
///         SLOAD + compare, `continue`. If the afking leg opens fewer than `OPEN_BATCH` (mintFlip.sol
///         GameAfkingModule.sol:1675-1707) the human sweep (`openHumanBoxes`, delegatecalled into
///         `DegenerusGameLootboxModule`) runs with the REMAINING budget (`OPEN_BATCH - opened`),
///         consuming its own opens+skips+index-header steps. If NEITHER leg does real work (no
///         afking open, no human open, no human-frontier skip-advance) `mintFlip()` reverts
///         `NoWork()` (GameAfkingModule.sol:1716-1719) -- so a caller still PAYS for the whole
///         ring scan even on a "nothing to do" call.
///
/// @notice Measurements (loose asserts only -- this is a baseline RECORDER, not a tight gate):
///         (1) per-skip marginal: the ring-scan cost per ALREADY-OPENED subscriber, derived from
///             three independently-built fully-drained rings at N = 100 / 500 / 998 new subs
///             (+2 permanent deploy subs [VAULT, sDGNRS] = ring sizes 102 / 502 / 1000) via
///             (gas(N2) - gas(N1)) / (N2 - N1). Measured by a LOW-LEVEL call that reverts NoWork()
///             (no human backlog exists in this fixture), bracketing gasleft before/after -- the
///             call still pays the full ring-scan cost before reverting, so this isolates the pure
///             scan-and-skip cost per subscriber (Approach chosen per the task brief's first option:
///             "measure via ... a low-level call recording gasleft before/after").
///         (2) drained-scan + human-sweep composition: a 1000-subscriber fully-drained ring PLUS
///             a queue of 90 pending human lootboxes (>= the OPEN_BATCH=80 remaining budget once
///             the afking leg opens 0), so the human sweep consumes its full 80-step budget in the
///             SAME `mintFlip()` call as the drained-ring scan. Measures the total call gas
///             (a SUCCESSFUL mintFlip(), not a revert).
///         (3) NoWork probe cost: 1000 drained subscribers, ZERO human work -- the caller-paid cost
///             to discover there is nothing to do (`mintFlip()` reverts `NoWork()`). Measured via a
///             low-level call recording gasleft before/after (same technique as (1), and in fact the
///             SAME fixture shape as (1)'s N=1000 case, rebuilt standalone here as its own labeled
///             measurement per the task brief).
///         (4) afking open marginal: gas per afking box actually materialized (a READY, un-opened,
///             dense ring) -- reuses the `V56AfkingGasMarginal._measureOpenLegGas` N-vs-(N-1)
///             snapshot/revert idiom verbatim (ported, not imported -- test contracts do not share
///             state).
///
/// @notice 21,064 intrinsic-gas context: Foundry's `gasBefore - gasleft()` delta EXCLUDES the
///         21,064 base intrinsic-transaction gas (21,000 base + ~64 for the 4-byte selector
///         calldata, all non-zero bytes) that a REAL top-level `eth_sendRawTransaction` pays on
///         top of every measured number in this file. Add 21,064 to any number here before
///         comparing it to a full-transaction ceiling (e.g. a wallet's simulated gas estimate).
///
/// @dev Live `DeployProtocol` fixture. Ports the GROUNDED-subscribe harness pattern from
///      `V56AfkingGasMarginal.t.sol` (fund BEFORE subscribe, so the D-12 mandatory NEW-run
///      cover-buy is grounded and the subscribe-time stamp is real) -- NOT the superseded
///      `KeeperOpenBoxWorstCaseGas.t.sol` fixture (its `vm.skip` reasons at :116/:175/:251
///      document why: it subscribes UNGROUNDED then measures the STAGE-first-buy open leg,
///      and the grounded subscribe buys AT subscribe time, shifting the measured marginal).
///      All pinned slots match `V56AfkingGasMarginal.t.sol` (`forge inspect DegenerusGame
///      storageLayout`): `_subOf = 54`, `_subscribers = 56`, `_subCursor/_subOpenCursor = 58`,
///      `rngWordByDay = 10`. Test-only: ZERO contracts/*.sol mutated.
contract OpenWalkCompositionGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (ported verbatim from V56AfkingGasMarginal.t.sol)
    // -------------------------------------------------------------------------

    uint256 private constant RNG_WORD_BY_DAY_SLOT = 10; // mapping(uint24 => uint256) — afking box's DAY-keyed word + readiness gate
    uint256 private constant SUBOF_SLOT = 53;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant CURSOR_SLOT = 57;           // packed: _subCursor/_subOpenCursor/.../_pendingBoxCount
    uint256 private constant SUBSCRIBERS_SLOT = 55;      // address[] _subscribers (slot holds the length; elements at keccak256(slot)+i)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol struct Sub, post `validThroughLevel` deletion).
    uint256 private constant OFF_LASTBOUGHT = 7;  // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)

    // -------------------------------------------------------------------------
    // Measurement constants
    // -------------------------------------------------------------------------

    /// @dev The 16.7M HARD never-exceed kill ceiling (same USER-LOCKED dual-bound constant used
    ///      throughout test/gas/*.t.sol). Every measurement here asserts LOOSELY under it — this
    ///      suite is a baseline recorder, not a tight regression gate.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev OPEN_BATCH (GameAfkingModule.sol:263): the flat per-call open-leg budget. `mintFlip()`
    ///      spends up to this many afking opens, then (if any budget remains) up to the remainder
    ///      on the human sweep.
    uint256 internal constant OPEN_BATCH = 80;

    /// @dev Foundry's bracketed `gasBefore - gasleft()` delta excludes the real-transaction
    ///      21,000-base + ~64-calldata intrinsic cost every measurement in this file would ALSO
    ///      pay on-chain. Informational only (see the file header note) — added to context logs,
    ///      never subtracted from an assertion.
    uint256 internal constant INTRINSIC_TX_GAS = 21_064;

    /// @dev SUBSCRIBER_CAP (GameAfkingModule.sol) is 2000 active subs, including the 2 permanent
    ///      deploy subs (VAULT + sDGNRS, self-subscribed in their constructors). This suite
    ///      measures a representative 1000-subscriber ring (998 new subs + the 2 always-present
    ///      deploy subs), not the full cap — these are loose baseline recorders, not a cap-sized
    ///      regression gate.
    uint256 internal constant RING_1000_NEW_SUBS = 998;
    uint256 internal constant RING_500_NEW_SUBS = 500;
    uint256 internal constant RING_100_NEW_SUBS = 100;

    /// @dev Human lootbox buyer count for the composition measurement — set above OPEN_BATCH=80
    ///      so the human sweep's remaining budget (80, once the afking leg opens 0) is fully
    ///      consumed by real opens (not a short queue that under-runs the budget), with a 10-buyer
    ///      margin so word-landing / ordering variance can never leave the sweep budget-starved.
    uint256 internal constant HUMAN_BUYERS_FOR_FULL_SWEEP = 90;

    /// @dev LOOTBOX_MIN (DegenerusGameMintModule.sol:103) — the minimum lootBoxAmount purchase()
    ///      accepts; used verbatim as each human buyer's spend (entryQuantityScaled=0, no ticket
    ///      leg, to keep each human buy a minimal, uniform, isolated lootbox-only entry).
    uint256 internal constant LOOTBOX_MIN = 0.01 ether;

    /// @dev N for the afking-open-marginal two-near-N snapshot/revert measurement (ported from
    ///      V56AfkingGasMarginal's N_HI/N_LO — big enough that both N and N-1 stamp in one STAGE
    ///      chunk, small enough to keep the harness fast).
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
    // (1) Per-skip marginal across ring sizes (N = 100 / 500 / 1000)
    // =========================================================================

    /// @notice Builds THREE independent fully-drained rings (100, 500, 998 new subs => ring
    ///         sizes 102/502/1000 incl. the 2 deploy subs) from the SAME clean baseline
    ///         (snapshot/revert between each), and at each size probes the ring-scan cost via a
    ///         reverting `mintFlip()` (NoWork — the ring is fully drained and no human backlog
    ///         exists). Derives the per-subscriber ring-scan-skip marginal from the deltas
    ///         between adjacent ring sizes. Loose assert only: each probe stays under the 16.7M
    ///         ceiling.
    function testPerSkipMarginalAcrossRingSizes() public {
        uint256 snap = vm.snapshotState();

        uint256 g100 = _buildDrainedRingAndProbeNoWork(RING_100_NEW_SUBS, "sk100_");
        vm.revertToState(snap);
        uint256 g500 = _buildDrainedRingAndProbeNoWork(RING_500_NEW_SUBS, "sk500_");
        vm.revertToState(snap);
        uint256 g1000 = _buildDrainedRingAndProbeNoWork(RING_1000_NEW_SUBS, "sk1000_");

        emit log_named_uint("nowork_probe_gas_at_ring_size_102", g100);
        emit log_named_uint("nowork_probe_gas_at_ring_size_502", g500);
        emit log_named_uint("nowork_probe_gas_at_ring_size_1000", g1000);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        // The `_pendingBoxCount` O(1) drained gate: a fully-drained ring's NoWork probe never
        // walks the ring, so the probe cost is (a) small and (b) INDEPENDENT of ring size —
        // pre-gate this scaled ~4.7k gas per subscriber (≈4.9M at the 1000 cap, cold).
        assertLt(g1000, 200_000, "drained-ring NoWork probe is O(1), not a ring scan");
        uint256 spread = g1000 > g100 ? g1000 - g100 : g100 - g1000;
        assertLt(spread, 25_000, "drained-ring NoWork probe cost is ring-size independent (the counter gate, not a scan)");
    }

    // =========================================================================
    // (2) Drained-scan + human-sweep composition
    // =========================================================================

    /// @notice A 1000-subscriber fully-drained ring (998 new + 2 deploy subs) PLUS 90 pending
    ///         human lootboxes (>= the 80-step remaining budget once the afking leg opens 0) —
    ///         one `mintFlip()` call pays BOTH the full drained-ring scan AND a full-budget human
    ///         sweep. This is the composition an external review measured heavy human entries at
    ///         ~15.06M for; this fixture uses ORDINARY (LOOTBOX_MIN, single-leg) human entries, so
    ///         the measured number here is expected to sit BELOW that heavy-entry reference — the
    ///         gap is exactly the per-entry human-sweep cost variance the task calibration targets.
    function testDrainedScanPlusHumanSweepComposition() public {
        string memory prefix = "comp_";
        // Generous per-sub funding (50 ether) so BOTH the initial cover-buy STAGE and the
        // second-day re-stamp STAGE (below) are funded — afkingFunding exhaustion between the two
        // day cycles would leave some subs un-restamped, which would desync the "exact pending
        // count" drain trick used below.
        _setupFundedSubs(RING_1000_NEW_SUBS, prefix, 50 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w1"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "c1"))) | 1);
        require(!game.advanceDue(), "fixture: clean after the first stage");

        uint256 ringSize = _subscriberCount();
        require(ringSize == RING_1000_NEW_SUBS + 2, "fixture: ring is the 998-new + 2-deploy 1000 set");

        // Drain the initial subscribe-time cover-buy boxes. No human backlog exists yet, so any
        // leftover budget in the human-sweep leg is harmless (it no-ops on an empty backlog).
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "drain1"))));
        game.openBoxes(ringSize + 5);
        require(_countPendingAfking() == 0, "fixture: ring fully drained pre-human-buys");

        // 90 distinct human buyers queue a minimal lootbox (LOOTBOX_MIN, no ticket leg) at the
        // CURRENT (not-yet-finalized) lootbox RNG index — each is a fresh boxPlayers[idx] entry.
        for (uint256 i; i < HUMAN_BUYERS_FOR_FULL_SWEEP; ++i) {
            address buyer = makeAddr(string(abi.encodePacked(prefix, "human_", _u(i))));
            vm.deal(buyer, 1 ether);
            vm.prank(buyer);
            game.purchase{value: LOOTBOX_MIN}(buyer, 0, LOOTBOX_MIN, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // One more day cycle: re-stamps the afking ring's daily boxes AND finalizes (lands the
        // word for) the human buyers' lootbox RNG index in lockstep — both ride the same daily
        // VRF request/fulfill flow this harness drives via _runStageNewDay/_settleClean.
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w2"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "c2"))) | 1);
        require(!game.advanceDue(), "fixture: clean after the second stage");

        // Re-drain ONLY the newly re-stamped afking boxes: pass the EXACT currently-pending count
        // as maxCount, so `_autoOpen` stops the moment `opened == maxCount` (== every pending
        // afking box) — the Game's `openBoxes` only falls through to the human sweep leg when
        // `openedAfking < maxCount` (DegenerusGame.sol:1633), so an exact-match drain never
        // touches the freshly-queued, still-pending human backlog.
        uint256 pendingAfterRestamp = _countPendingAfking();
        require(pendingAfterRestamp > 0, "fixture: the afking ring was re-stamped for the new day");
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "drain2"))));
        // +2 skip allowance: the walk budget is WEIGHTED (skip = 1 unit) and the 2 unfunded
        // deploy subs sit in the ring as skips; the allowance keeps every pending open
        // affordable. The human-sweep leg may leak <= 2 steps (opens <= 2 of the 90 queued
        // human boxes), leaving >= 88 — still past the full 80-step measured sweep.
        uint256 openedDrain2 = game.openBoxes(pendingAfterRestamp + 2);
        require(openedDrain2 >= pendingAfterRestamp, "fixture: the drain call opened every pending afking box");
        require(_countPendingAfking() == 0, "fixture: ring fully drained again pre-measurement");

        // MEASURE: one mintFlip() call. The afking leg does a full-ring-scan (every subscriber
        // already opened -> 0 afking opens), so `opened(0) < OPEN_BATCH(80)` routes into the human
        // sweep with the full 80-step remaining budget; 90 queued human entries (>= 80) means the
        // sweep consumes its ENTIRE budget on real opens.
        _coolProtocol();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "measure"))));
        uint256 gasBefore = gasleft();
        game.mintFlip();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("composition_drained_ring_plus_full_human_sweep_gas", gasUsed);
        emit log_named_uint("composition_ring_size", ringSize);
        emit log_named_uint("composition_human_buyers_queued", HUMAN_BUYERS_FOR_FULL_SWEEP);
        emit log_named_uint("composition_open_batch_budget", OPEN_BATCH);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        // The `_pendingBoxCount` gate makes a drained ring free to cross: this call pays for
        // the human sweep ONLY, never a ring scan — so the 10M normal-path target holds where
        // the pre-gate composition (full-ring scan + full sweep) organically breached it.
        assertLt(gasUsed + INTRINSIC_TX_GAS, 10_000_000, "gate + full-budget human sweep stays under the 10M normal-path target");
    }

    // =========================================================================
    // (3) NoWork probe cost at a 1000-subscriber drained ring, zero human work
    // =========================================================================

    /// @notice The caller-paid cost of a `mintFlip()` call that discovers there is NOTHING to do:
    ///         1000 fully-drained subscribers (998 new + 2 deploy), zero human backlog. The
    ///         `_pendingBoxCount` gate answers "any afking work?" in O(1) (no ring scan), and the
    ///         human-sweep leg's zero-work no-frontier-advance short-circuits into
    ///         `revert NoWork()` — measured via a low-level call bracketing gasleft before/after.
    function testNoWorkProbeCostAtThousandSubscribers() public {
        uint256 gasUsed = _buildDrainedRingAndProbeNoWork(RING_1000_NEW_SUBS, "nowork1k_");

        emit log_named_uint("nowork_probe_gas_at_1000_subscribers", gasUsed);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        // Pre-gate this probe cost ~4.9M cold (a full 1000-subscriber scan just to revert).
        assertLt(gasUsed, 200_000, "the drained-ring NoWork probe is O(1) (the counter gate, not a ring scan)");
    }

    // =========================================================================
    // (5) Worst surviving mix: pending box behind a full skip wall + human backlog
    // =========================================================================

    /// @notice The post-fix WORST composition one rewarded crank can pay: `_pendingBoxCount`
    ///         != 0 (one pending box parked at ring index 0), the open cursor just PAST it
    ///         (index 1), so the weighted walk crosses ~999 skips (1 unit each), wraps, opens
    ///         the box (OPEN_ITEM_WEIGHT units), and hands the remaining units to the human
    ///         sweep over a deep backlog. Pre-fix this shape stacked a FREE full-ring scan on
    ///         a FULL 80-step human sweep (~9.4M ordinary / ~15.1M heavy); the shared weighted
    ///         budget caps the mix structurally at ≈ OPEN_WEIGHT_BUDGET × ~4.7k/unit.
    function testWorstMixSkipWallPlusHumanSweepComposition() public {
        string memory prefix = "wmix_";
        _setupFundedSubs(RING_1000_NEW_SUBS, prefix, 50 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w1"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "c1"))) | 1);
        uint256 ringSize = _subscriberCount();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "drain1"))));
        game.openBoxes(ringSize + 1000);
        require(_countPendingAfking() == 0, "fixture: ring fully drained pre-human-buys");

        for (uint256 i; i < HUMAN_BUYERS_FOR_FULL_SWEEP; ++i) {
            address buyer = makeAddr(string(abi.encodePacked(prefix, "human_", _u(i))));
            vm.deal(buyer, 1 ether);
            vm.prank(buyer);
            game.purchase{value: LOOTBOX_MIN}(buyer, 0, LOOTBOX_MIN, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w2"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "c2"))) | 1);
        require(!game.advanceDue(), "fixture: clean after the second stage");
        uint256 pendingAfterRestamp = _countPendingAfking();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "drain2"))));
        game.openBoxes(pendingAfterRestamp + 2);
        require(_countPendingAfking() == 0, "fixture: ring fully drained again");

        // Park ONE pending box behind a full skip wall: re-arm the day markers of the first
        // FUNDED sub (ring indices 0-1 are the unfunded deploy subs, never stamped; index 2
        // is the first grounded fixture sub), point the open cursor just past it, and set
        // the pending counter to 1 so the gate opens — the walk must cross ~997 skips and
        // wrap before it can afford the open.
        address wallBox = _subscriberAt(2);
        uint32 stampDay = _lastBoughtDayOf(wallBox);
        require(rngWordByDay(stampDay) != 0, "fixture: the wall box's stamp-day word landed");
        _pokeSubOpenedDay(wallBox, stampDay - 1);
        _pokeOpenCursorAndPendingCount(3, 1);

        _coolProtocol();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "measure"))));
        uint256 gasBefore = gasleft();
        game.mintFlip();
        uint256 gasUsed = gasBefore - gasleft();

        // Non-vacuity: the walk really crossed the wall and materialized the parked box.
        assertEq(_lastOpenedDayOf(wallBox), stampDay, "the skip-walled box was opened");

        emit log_named_uint("worst_mix_skip_wall_plus_human_sweep_gas", gasUsed);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        assertLt(gasUsed + INTRINSIC_TX_GAS, 10_000_000, "the worst weighted mix stays under the 10M normal-path target");
    }

    // =========================================================================
    // (4) Afking open marginal (dense ring, ready boxes)
    // =========================================================================

    /// @notice The per-open marginal = (gas for N opens - gas for N-1 opens) / 1, snapshot/revert
    ///         (ported verbatim from V56AfkingGasMarginal.testPerOpenMarginal's shape). Each
    ///         afking box open is a stamp-derived resolve (no cold-ledger walk) via
    ///         `_openAfkingBox` — this is the OTHER half of the composition: the per-box cost when
    ///         a box IS materialized, as opposed to the per-subscriber SKIP cost measured above.
    function testAfkingOpenMarginalDenseRing() public {
        uint256 snap = vm.snapshotState();
        // SHARED prefix across the N and N-1 runs so the first N-1 boxes are byte-identical
        // between the two runs (same players, same word) and cancel exactly in the delta — see
        // V56AfkingGasMarginal.testPerOpenMarginal's identical rationale.
        uint256 gasN = _measureOpenLegGas(N_HI, "openM_");
        vm.revertToState(snap);
        uint256 gasNm1 = _measureOpenLegGas(N_LO, "openM_");

        assertGt(gasN, gasNm1, "per-open marginal: N opens cost strictly more than N-1 (the Nth box materialized)");
        uint256 perOpen = gasN - gasNm1;

        emit log_named_uint("per_afking_open_marginal_gas", perOpen);
        emit log_named_uint("per_open_gas_n", gasN);
        emit log_named_uint("per_open_gas_n_minus_1", gasNm1);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        assertLt(perOpen, EFFECTIVE_GAS_CEILING, "per-afking-open marginal trivially fits the 16.7M ceiling");
    }

    // =========================================================================
    // Internal helpers (ported + adapted from V56AfkingGasMarginal.t.sol)
    // =========================================================================

    /// @dev Re-cool every storage-bearing account on the measured path plus the module code
    ///      accounts the delegatecalls touch, so a bracketed measurement inside this test tx
    ///      pays COLD access costs — what a fresh keeper transaction pays on mainnet. The
    ///      fixture's own drain/setup calls run in the SAME test transaction and pre-warm
    ///      every subscriber slot; without this reset the measurement understates the real
    ///      per-visit cost ~5-9x (warm 100-gas vs cold 2,100-gas SLOADs).
    function _coolProtocol() internal {
        vm.cool(address(game));
        vm.cool(ContractAddresses.COINFLIP);
        vm.cool(ContractAddresses.COIN);
        vm.cool(ContractAddresses.QUESTS);
        vm.cool(ContractAddresses.AFFILIATE);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
    }

    /// @dev Builds `n` fresh GROUNDED lootbox-mode subs (+ the 2 permanent deploy subs already in
    ///      the ring), stamps + lands their first day's word, settles clean, then fully drains
    ///      every pending afking box (no human backlog exists in this fixture, so the drain call's
    ///      leftover budget is harmless). Returns the gas of the immediately-following `mintFlip()`
    ///      probe call, which must revert `NoWork()` (fully-drained ring, zero human work) —
    ///      measured via a low-level call bracketing gasleft before/after.
    function _buildDrainedRingAndProbeNoWork(uint256 n, string memory prefix) internal returns (uint256 gasUsed) {
        _setupFundedSubs(n, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean before the drain");

        uint256 ringSize = _subscriberCount();
        // maxCount = ringSize + a generous pad: the afking leg opens every pending box well
        // before exhausting maxCount, so the LEFTOVER budget flows to the human-sweep leg, which
        // must walk (and commit) past every EMPTY finalized lootbox index accumulated by the
        // day-advances above (each index-header visit costs a step regardless of content,
        // openHumanBoxes:688-691) — otherwise the probe below sees an un-caught-up frontier and
        // `mintFlip()` treats that frontier advance as real (non-reverting) work, not NoWork.
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "drain"))));
        game.openBoxes(ringSize + 1000);
        require(_countPendingAfking() == 0, "fixture: ring fully drained pre-probe");

        _coolProtocol();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "probe"))));
        uint256 gasBefore = gasleft();
        (bool ok, ) = address(game).call(abi.encodeWithSignature("mintFlip()"));
        gasUsed = gasBefore - gasleft();
        require(!ok, "fixture: the NoWork probe reverted as expected (drained ring, zero human work)");
    }

    /// @dev Measure the afking open-leg gas over N freshly-stamped + ready LOOTBOX afking boxes
    ///      (ported verbatim from V56AfkingGasMarginal._measureOpenLegGas). The 2 deploy subs add
    ///      a CONSTANT 2 ready boxes to both the N and N-1 measurements, so they cancel in the
    ///      (gasN - gasNm1) difference.
    function _measureOpenLegGas(uint256 n, string memory prefix) internal returns (uint256 openGas) {
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "word"))) | 1);
        uint32 stampDay = _lastBoughtDayOf(subs[0]);
        require(stampDay > 0, "fixture: subs stamped");
        require(rngWordByDay(stampDay) != 0, "fixture: stamp-day word landed");
        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) < stampDay, "marginal pre: each box queued");
        }

        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so mintFlip opens");
        _coolProtocol();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.mintFlip();
        openGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) == stampDay, "marginal non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players as funded lootbox-mode subs (ported from
    ///      V56AfkingGasMarginal._setupFundedSubs — GROUNDED: funded BEFORE subscribe so the D-12
    ///      mandatory NEW-run cover-buy is funded, matching the shipped grounded-subscribe
    ///      behavior the superseded KeeperOpenBoxWorstCaseGas fixture got wrong).
    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach, bool isTicket)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantSeat(who); // the AFKing Subscription Token is the subscribe credential (NoCoin without it)
            _fundPool(who, poolEach);
            vm.prank(who);
            game.subscribe(address(0), false, isTicket, 1, address(0));
        }
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Drive a fresh new-day STAGE then land the day's word (the per-sub stamp becomes a
    ///      ready box). Ported verbatim from V56AfkingGasMarginal.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before
    ///      returning — used before a mintFlip open so it reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev Fulfill the latest pending mock-VRF request (idempotent — no-op if already
    ///      fulfilled / none).
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

    // ---- Sub-slot reads (_subOf at slot 54 + v56 offsets) ----

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

    /// @dev Read `_subscribers[i]` — the dynamic array's elements live at keccak256(slot) + i.
    function _subscriberAt(uint256 i) internal view returns (address) {
        bytes32 base = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        return address(uint160(uint256(vm.load(address(game), bytes32(uint256(base) + i)))));
    }

    /// @dev Walk the WHOLE live `_subscribers` set (not just a caller-known subset — the ring
    ///      also carries the 2 permanent deploy subs) and count subs with a pending
    ///      (un-opened) afking box. Used to compute the EXACT maxCount for a leak-free
    ///      afking-only drain (see testDrainedScanPlusHumanSweepComposition).
    function _countPendingAfking() internal view returns (uint256 pending) {
        uint256 len = _subscriberCount();
        for (uint256 i; i < len; ++i) {
            address who = _subscriberAt(i);
            if (_lastOpenedDayOf(who) < _lastBoughtDayOf(who)) {
                unchecked {
                    ++pending;
                }
            }
        }
    }

    /// @dev Read the DAY-keyed afking word `rngWordByDay[day]` (the open leg's seed + readiness
    ///      gate).
    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    /// @dev RMW a sub's packed `lastOpenedDay` (uint24 at byte OFF_LASTOPENED) — used to re-arm
    ///      a drained box as pending for the worst-mix fixture.
    function _pokeSubOpenedDay(address who, uint32 d) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 w = uint256(vm.load(address(game), slot));
        uint256 shift = OFF_LASTOPENED * 8;
        w = (w & ~(uint256(0xFFFFFF) << shift)) | (uint256(d & 0xFFFFFF) << shift);
        vm.store(address(game), slot, bytes32(w));
    }

    /// @dev RMW the packed cursor slot (58): `_subOpenCursor` (uint16 at bit 16) and
    ///      `_pendingBoxCount` (uint16 at bit 224), leaving the other six packed fields intact.
    function _pokeOpenCursorAndPendingCount(uint16 cursor, uint16 pendingCount) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(CURSOR_SLOT)));
        w = (w & ~(uint256(0xFFFF) << 16)) | (uint256(cursor) << 16);
        w = (w & ~(uint256(0xFFFF) << 224)) | (uint256(pendingCount) << 224);
        vm.store(address(game), bytes32(CURSOR_SLOT), bytes32(w));
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
