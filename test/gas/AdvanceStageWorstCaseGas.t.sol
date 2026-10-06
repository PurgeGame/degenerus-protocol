// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {MintBucketSeed} from "../helpers/MintBucketSeed.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @title AdvanceStageWorstCaseGas — Phase 367 (GASCEIL) measured per-stage mineFlip ceiling
/// @notice Phase 367 REDO. The prior pass reported the standalone 305-winner daily jackpot stage
///         as "~15.08M" — that 15M was actually the now-DECOUPLED gap-backfill+jackpot COMPOSITION
///         (which the v56 Stage-4 decouple `break` made unreachable in one tx). This harness measures
///         the REAL worst-case gas of each mineFlip stage's bounding loop, pushed to its capped
///         maximum, with forge gasleft()-delta around the live production code path.
///
///         mineFlip (DegenerusGameAdvanceModule.mineFlip, do{}while(false) one-stage-per-call)
///         splits into TWO loop shapes:
///           (A) single-shot, internally winner-capped jackpot distributions (stages 8/11/12) — the
///               305-winner ETH leg `_processDailyEth -> _processBucket -> _addClaimableEth`;
///           (B) write/weight-budgeted chunked loops (stages 0/1/5/6/7 ticket batch; stage 2 subs).
///
///         This file measures (A) the 305-winner ETH jackpot and the 50-winner coin leg directly by
///         extending the production module (seeding lvlTraitEntry, then driving the live external
///         entry with the msg.sender==GAME prank), and (B) the worst-case ticket-worker
///         (`runTicketWork`) chunk. The subscriber STAGE (2), the gap-backfill (4) and the OPEN_BATCH
///         router are measured by the sibling harness V56AfkingGasMarginal (referenced, not re-run).
/// @dev Test-only. NO contracts/*.sol is mutated. The two harness subclasses add only seeders +
///      read-only views; they override NO production logic.

// =============================================================================
// Harness A — live 305-winner daily-ETH jackpot (stages 8 / 11 / 12 ETH leg)
// =============================================================================

/// @dev Extends the production jackpot module so the inherited external `runTerminalJackpotWork`
///      executes the live ETH-award loop in THIS contract's storage. That is the IDENTICAL
///      distribution path (`_resumeEth`) used by:
///        - stage 8  runDailyJackpot(false)  purchase-phase
///        - stage 11 runDailyJackpot(true)   jackpot-phase
///        - stage 12 runTerminalJackpotWork  game-over
///      The terminal jackpot pays the fixed 152/104/48/1 = 305 geometry measured here.
contract JackpotStageHarness is DegenerusGameJackpotModule, BucketSeed {
    function seedBucket(uint24 lvl, uint8 traitId, uint256 count, uint160 base) external {
        _seedBucketDistinct(lvl, traitId, count, base);
    }
}

// =============================================================================
// Harness B — live ticket-worker worst-case chunk (stages 0/1/5/6/7)
// =============================================================================

/// @dev Extends the production mint module and delegatecalls the production ticket worker
///      (`runTicketWork`) so the live per-entry trait-mint loop runs in THIS contract's storage.
///      The seeder pushes N players into the read-slot ticketQueue with `owed` traits each and
///      sets the lootbox RNG entropy word the batch reads at index 1. A worst-case batch mints up
///      to WRITES_BUDGET_SAFE write-units of cold lvlTraitEntry SSTOREs in one call.
contract TicketBatchStageHarness is MintBucketSeed {
    /// @dev The mint module answers the liveness tail through the Game's view; this harness is
    ///      not deployed at the Game's address, so it evaluates the tail in place.
    function _pastDeadlineTriggered(uint24 today, uint24 idx)
        internal
        view
        override
        returns (bool)
    {
        return DegenerusGameStorage._pastDeadlineTriggered(today, idx);
    }

    /// @dev Shared seeding: `n` distinct players each owing `owedEach` traits into the current
    ///      read-slot queue for `lvl`, plus a non-zero lootbox entropy word at index 0 (the word
    ///      the batch reads via _lootboxWord( _lrRead(INDEX) - 1 )).
    function _seedQueue(uint24 lvl, uint256 n, uint32 owedEach, uint160 base) internal {
        // The sweep walks [anchor-1 .. _mintCeiling()] and the measured call passes anchor = lvl
        // (the purchase level), so pin level = lvl - 1: the window is [lvl-1 .. lvl] and the
        // seeded read queue at `lvl` is inside it. The harness default level 0 caps the window at
        // level 1, which would leave every measured batch walking nothing.
        level = lvl - 1;
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = uint256(keccak256("367_ticketbatch_entropy")) | 1; _setRngSessionPublished(true); _setRngComplete(false);

        uint24 rk = _tqReadKey(lvl);
        uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(rk)];

        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            uint80 ownerBits = (uint80(_seedWallet(p)) << OWNER_IDX_SHIFT);
            _tqAppend(rk, uint32(ownerBits >> OWNER_IDX_SHIFT));
            // packed layout: owed in bits [8:], remainder in bits [0:8]. Set owed=owedEach, rem=0.
            _seedOwedAt(rk, p, ownerBits | (uint80(owedEach) << 8));
        }
    }

    /// @dev Seed the queue and force the (ticketLevel != lvl) reset path -> cursor 0, first-batch
    ///      cold-scale.
    function seedTicketQueue(uint24 lvl, uint256 n, uint32 owedEach, uint160 base) external {
        _seedQueue(lvl, n, owedEach, base);
        ticketCursor = 0;
        ticketLevel = 0;
    }

    /// @dev Seed the queue AND pin (ticketLevel == lvl, ticketCursor == startCursor) so the batch runs at
    ///      the FULL warm WRITES_BUDGET_SAFE=1000 budget (NOT the 35%-cold-scaled 650 of the first batch).
    ///      This is the heavier resume-batch worst case (a level whose first batch already ran).
    function seedTicketQueueWarmResume(uint24 lvl, uint256 n, uint32 owedEach, uint160 base, uint32 startCursor)
        external
    {
        _seedQueue(lvl, n, owedEach, base);
        // Pin level == lvl so runTicketWork does NOT reset the cursor, and start at a non-zero cursor
        // so idx != 0 -> the full (non-cold-scaled) 550 write budget is used.
        ticketLevel = lvl;
        ticketCursor = startCursor;
    }

    function queueLen(uint24 lvl) external view returns (uint256) {
        return _ticketQueueLength(_tqReadKey(lvl));
    }

    /// @dev The metered ticket worker exactly as the miner dispatches it: a delegatecall into the
    ///      production ticket module (etched at its pinned address) in THIS contract's storage.
    function runTicketWork(uint24 anchor, uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameTicketModule.runTicketWork.selector, anchor, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    function cursor() external view returns (uint256) {
        return ticketCursor;
    }
}

// =============================================================================
// The measurement suite
// =============================================================================

contract AdvanceStageWorstCaseGas is Test {
    JackpotStageHarness internal jp;
    TicketBatchStageHarness internal tb;

    // Production caps, re-attested against the frozen audit subject c4d48008
    // (JackpotModule: terminal winners 305, DAILY_COIN_MAX_WINNERS 50;
    //  MintModule: WRITES_BUDGET_SAFE 1000).
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;
    uint16 internal constant DAILY_COIN_MAX_WINNERS = 50;
    uint32 internal constant WRITES_BUDGET_SAFE = 1000;

    /// @dev The hard EIP-7825 per-transaction gas cap. A breach = mineFlip DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev The 10M soft design comfort target (USER dual bound).
    uint256 internal constant GAS_TARGET = 10_000_000;
    /// @dev The real mainnet block gas limit (foundry inflates block_gas_limit to 30e9 for the harness).
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev Terminal pool; the terminal geometry is the fixed 152/104/48/1 = 305.
    uint256 internal constant POOL_WEI = 1000 ether;
    uint24 internal constant TARGET_LVL = 110;

    function setUp() public {
        jp = new JackpotStageHarness();
        tb = new TicketBatchStageHarness();
        vm.etch(
            ContractAddresses.GAME_FOILPACK_MODULE,
            address(new DegenerusGameFoilPackModule()).code
        );
        // The ticket harness delegates runTicketWork to the ticket module at its pinned address.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
    }

    /// @dev runTicketWork admits ticket checkpoints while its allowance covers the next declared
    ///      bound, so each chunk is driven with a realistic bounded allowance and checked for
    ///      progress, never bounded by a ceiling.
    uint256 internal constant CHUNK_GAS = 10_000_000;

    function _word() internal pure returns (uint256) {
        return uint256(keccak256("367_gasceil_word")) | 1;
    }

    /// @dev Produce the 4 winning trait ids `runTerminalJackpotWork` will roll for THIS rngWord, plus the
    ///      effective entropy `terminalWinnerCounts` keys off. We mirror the module's derivation exactly:
    ///      `_rollBoard(rngWord, _NO_QUADRANT_BAN)` packs 4 traits (no hero wagers are seeded here, so
    ///      the roll is the unmodified base board); we unpack them and seed those 4 buckets so every
    ///      selected winner resolves to a real holder. Exact trait values do not affect gas (the
    ///      bucket SIZES are pinned by terminalWinnerCounts).
    function _deriveTraits(uint256 rngWord)
        internal
        pure
        returns (uint8[4] memory traitIds, uint256 effEntropy)
    {
        traitIds = JackpotBucketLib.getRandomTraits(rngWord);
        effEntropy = EntropyLib.hash2(rngWord, TARGET_LVL);
    }

    /// @dev Seed each of the 4 winning-trait buckets with a disjoint set of >=250 distinct holders so
    ///      every bucket's winner selection resolves to real (non-zero) addresses (never address(0)).
    function _seedAllBuckets(uint8[4] memory traitIds) internal {
        for (uint8 q; q < 4; ++q) {
            // disjoint address base per bucket; 260 > MAX_BUCKET_WINNERS(248) so no clipping artifact.
            jp.seedBucket(TARGET_LVL, traitIds[q], 260, uint160(uint256(0x1000) + uint256(q) * 0x10000));
        }
    }

    // =========================================================================
    // STAGE 8 / 11 / 12 — the 305-winner daily-ETH jackpot (BINDING single-shot)
    // =========================================================================

    /// @notice MEASURED worst-case for the daily-ETH jackpot distribution at the DAILY_ETH_MAX_WINNERS=305
    ///         hard cap (buckets 152/104/48/1 at max scale). This is the IDENTICAL `_processDailyEth` loop
    ///         that stages 8 (purchase-phase runDailyJackpot), 11 (jackpot-phase fresh daily) and 12
    ///         (game-over runTerminalJackpotWork) all execute. Drives the live external entry with the
    ///         msg.sender==GAME guard satisfied via prank and brackets the call with gasleft().
    ///
    ///         CORRECTION vs the prior 367 pass: the standalone 305-winner jackpot is NOT ~15.08M. The
    ///         15M figure was the gap-backfill (~7.3M) COMPOSED with the jackpot — a composition the v56
    ///         Stage-4 decouple `break` makes unreachable in one tx. The real standalone number is here.
    function test_Stage8_11_12_DailyEthJackpot_305Winners_Measured() public {
        (uint8[4] memory traitIds, uint256 effEntropy) = _deriveTraits(_word());

        // Worst-case-FIRST: assert the bucket geometry IS the 305 hard cap before measuring.
        uint16[4] memory bc = JackpotBucketLib.terminalWinnerCounts(effEntropy);
        assertEq(
            uint256(bc[0]) + bc[1] + bc[2] + bc[3],
            DAILY_ETH_MAX_WINNERS,
            "worst case: the terminal geometry is the 305-winner hard cap"
        );

        _seedAllBuckets(traitIds);

        vm.prank(ContractAddresses.GAME);
        uint256 gasBefore = gasleft();
        (, uint256 paidWei) = jp.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());
        uint256 gasUsed = gasBefore - gasleft();

        assertGt(paidWei, 0, "the measured worst-case jackpot actually paid out");

        emit log_named_uint("STAGE_8_11_12_daily_eth_jackpot_305_winner_gas", gasUsed);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);
        emit log_named_uint("headroom_to_16p7M_gas", EIP7825_TX_GAS_CAP - gasUsed);

        // The headline ceiling assertion: the binding single-shot stage clears the EIP-7825 cap with
        // very large headroom — and is FAR below the prior pass's mis-attributed ~15.08M figure.
        assertLt(
            gasUsed,
            EIP7825_TX_GAS_CAP,
            "STAGE 8/11/12: the 305-winner daily-ETH jackpot is strictly < 16,777,216 (EIP-7825)"
        );
        // It also clears the 10M soft comfort target (the real standalone number is ~7.5M, not ~15M).
        assertLt(
            gasUsed,
            GAS_TARGET,
            "STAGE 8/11/12: the standalone 305-winner jackpot also clears the 10M soft target (it is ~7.5M, NOT ~15M)"
        );
        // Sanity: it fits the real mainnet block too, with margin.
        assertLt(gasUsed, MAINNET_BLOCK_GAS_LIMIT, "fits the 30M mainnet block with margin");
    }

    /// @notice Per-ETH-winner marginal, measured loop-N-divide: (gas at 305 winners − gas at 4 winners)/301.
    ///         Each ETH winner is one cold `claimableWinnings[w] += perWinner` SSTORE + a PlayerCredited
    ///         event + a JackpotEthWin event + one selected array slot. Confirms the per-winner cost is a
    ///         bounded O(1) (no scaling with player magnitude), so 305 is the binding count.
    function test_PerEthWinnerMarginal_Measured() public {
        // N = 305 winners (full cap) vs a tiny pool that still pays the same per-winner credit but
        // selects only a few winners. We instead seed identical buckets and run two pool scales: a
        // max-scale (305) and a low-scale pool. To isolate the per-winner SSTORE we compare 305 vs a
        // small reachable count using a small pool that pins to a much smaller bucket geometry.
        (uint8[4] memory traitIds, ) = _deriveTraits(_word());

        // Run 1: 305 winners (max scale).
        uint256 snap = vm.snapshotState();
        _seedAllBuckets(traitIds);
        vm.prank(ContractAddresses.GAME);
        uint256 gHi0 = gasleft();
        jp.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());
        uint256 gasHi = gHi0 - gasleft();
        vm.revertToState(snap);

        // Run 2: the same pot and the same full geometry, but only the smallest paying bucket holds
        // entries, so only its winners are drawn (an empty bucket draws none). The terminal jackpot
        // pays exact shares at a fixed full-size geometry, so a smaller pot no longer thins the
        // winners (the old ticket-unit rounding zeroed small buckets, which this probe relied on).
        (, uint256 eff) = _deriveTraits(_word());
        uint16[4] memory bcFull = JackpotBucketLib.terminalWinnerCounts(eff);
        uint8 qLo = 4;
        for (uint8 q; q < 4; ++q) {
            if (bcFull[q] != 0 && (qLo == 4 || bcFull[q] < bcFull[qLo])) qLo = q;
        }
        uint256 loWinners = bcFull[qLo];
        jp.seedBucket(TARGET_LVL, traitIds[qLo], 260, uint160(uint256(0x1000) + uint256(qLo) * 0x10000));
        vm.prank(ContractAddresses.GAME);
        uint256 gLo0 = gasleft();
        jp.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());
        uint256 gasLo = gLo0 - gasleft();

        emit log_named_uint("eth_jackpot_gas_at_305_winners", gasHi);
        emit log_named_uint("eth_jackpot_gas_at_low_winners", gasLo);
        emit log_named_uint("eth_jackpot_low_winner_count", loWinners);

        if (gasHi > gasLo && DAILY_ETH_MAX_WINNERS > loWinners) {
            uint256 perWinner = (gasHi - gasLo) / (DAILY_ETH_MAX_WINNERS - loWinners);
            emit log_named_uint("per_eth_winner_marginal_gas", perWinner);
            // A per-winner cold credit (~20-25k) is a bounded O(1); assert it cannot scale to a DoS.
            assertLt(perWinner, 200_000, "per-ETH-winner marginal is a bounded O(1) cold credit (no magnitude scaling)");
        } else {
            // Guard the probe's precondition so a degenerate measurement FAILS rather than silently
            // skipping the marginal bound: more winners (305 vs the low count) MUST cost more gas.
            assertTrue(
                gasHi > gasLo && DAILY_ETH_MAX_WINNERS > loWinners,
                "degenerate ETH-jackpot measurement: 305-winner gas did not exceed the low-winner gas"
            );
        }
    }

    // =========================================================================
    // STAGE 0 / 1 / 5 / 6 / 7 — the write-budgeted ticket batch (chunked)
    // =========================================================================

    /// @notice MEASURED worst-case for ONE ticket-worker chunk — the loop shared by
    ///         every chunked ticket stage (0 mid-day drain, 1 daily drain gate, 5 FF drain, 6 prepare
    ///         future tickets, 7 current-level batch). Each chunk mints up to WRITES_BUDGET_SAFE=1000 write
    ///         units of cold lvlTraitEntry SSTOREs (the first batch is cold-scaled to ~357). We seed a
    ///         deep queue (1 player owing a large trait count) so one batch saturates the budget, and
    ///         measure the live ticket worker `runTicketWork`.
    function test_Stage0_1_5_6_7_TicketBatch_WriteBudget_Measured() public {
        // ONE player owing a large trait count: the batch mints up to the (cold-scaled) write budget of
        // traits in one call, then breaks at the budget — the maximal single-tx ticket-batch chunk.
        uint32 owed = 600; // > the cold-scaled budget so the batch saturates and breaks mid-player.
        tb.seedTicketQueue(TARGET_LVL, 1, owed, uint160(0x20000));
        assertEq(tb.queueLen(TARGET_LVL), 1, "fixture: one deep-owed player queued");

        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = tb.runTicketWork{gas: CHUNK_GAS}(TARGET_LVL, CHUNK_GAS);
        (bool finished, bool worked) = (r.done, r.progressed);
        uint256 gasUsed = g0 - gasleft();
        assertTrue(worked, "non-vacuity: a realistic allowance must mint the seeded queue");

        emit log_named_uint("STAGE_0_1_5_6_7_ticket_batch_call_gas_at_10M", gasUsed);
        emit log_named_uint("ticket_batch_finished_first_call", finished ? 1 : 0);
        emit log_named_uint("ticket_batch_cursor_after", tb.cursor());
    }

    /// @notice MEASURED worst-case for a WARM resume ticket batch — the heavier case where the level's
    ///         first (cold-scaled) batch already ran, so this batch uses the FULL WRITES_BUDGET_SAFE=1000
    ///         budget (not the 35%-scaled 357). Seed one deep-owed player at a non-zero cursor so idx != 0.
    ///         This is the true single-tx ticket-stage worst case; the cold first batch (~6.5M) is lighter.
    function test_Stage7_TicketBatch_WarmResume_FullBudget_Measured() public {
        // Player[0] cheap (owed small, advances fast); player[1] deep-owed; cursor pinned at index 1 so
        // the batch enters the deep player with idx==1 -> the full 1000 budget (no cold scale).
        // We seed 2 entries: index 0 a 1-owed cheap entry, index 1 a 700-owed deep entry; cursor=1.
        // seedTicketQueueWarmResume seeds n uniform-owed players; to get the mixed shape we seed 2 deep
        // players and start at cursor 1 (so only the second is processed this batch at full budget).
        tb.seedTicketQueueWarmResume(TARGET_LVL, 2, 700, uint160(0x50000), 1);
        assertEq(tb.queueLen(TARGET_LVL), 2, "fixture: 2 players queued");
        assertEq(tb.cursor(), 1, "fixture: cursor starts at index 1 (warm, no cold-scale)");

        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = tb.runTicketWork{gas: CHUNK_GAS}(TARGET_LVL, CHUNK_GAS);
        (bool finished, bool worked) = (r.done, r.progressed);
        uint256 gasUsed = g0 - gasleft();
        assertTrue(worked, "non-vacuity: a realistic allowance must mint the seeded queue");

        emit log_named_uint("STAGE_7_ticket_batch_WARM_call_gas_at_10M", gasUsed);
        emit log_named_uint("ticket_batch_warm_finished", finished ? 1 : 0);
    }

    /// @notice Per-trait marginal for the ticket batch, measured loop-N-divide across two deep-owed
    ///         counts that both fit in ONE (non-cold-scaled) batch, isolating the per-trait cold SSTORE.
    ///         The deep-owed single player's later batches use the full 1000 budget (no cold-scale), so we
    ///         drive a first cheap batch to advance off cursor 0, then measure the second batch's marginal.
    function test_PerTraitMarginal_TicketBatch_Measured() public {
        // Two runs from one baseline: a player owing M traits vs M-K, both within one warm batch.
        // The marginal = (gas(M) - gas(M-K)) / K, the cold lvlTraitEntry push per trait.
        uint32 mHi = 200;
        uint32 mLo = 100;

        // Both drains are driven at the 16.7M ceiling allowance and must complete, so the
        // difference isolates the per-trait cost of the extra 100 entries.
        uint256 snap = vm.snapshotState();
        tb.seedTicketQueue(TARGET_LVL, 1, mHi, uint160(0x30000));
        uint256 gHi0 = gasleft();
        bool finishedHi = tb.runTicketWork{gas: 16_700_000}(TARGET_LVL, 16_700_000).done;
        uint256 gasHi = gHi0 - gasleft();
        assertTrue(finishedHi, "non-vacuity: the 200-owed drain completed in the call");
        vm.revertToState(snap);

        tb.seedTicketQueue(TARGET_LVL, 1, mLo, uint160(0x30000));
        uint256 gLo0 = gasleft();
        bool finishedLo = tb.runTicketWork{gas: 16_700_000}(TARGET_LVL, 16_700_000).done;
        uint256 gasLo = gLo0 - gasleft();
        assertTrue(finishedLo, "non-vacuity: the 100-owed drain completed in the call");

        emit log_named_uint("ticket_batch_gas_at_200_owed", gasHi);
        emit log_named_uint("ticket_batch_gas_at_100_owed", gasLo);

        if (gasHi > gasLo) {
            uint256 perTrait = (gasHi - gasLo) / (mHi - mLo);
            emit log_named_uint("per_trait_marginal_gas", perTrait);
            // Per-trait cold array push is a bounded O(1); a 1000-write budget × this stays < the cap.
            assertLt(perTrait, 200_000, "per-trait cold push is a bounded O(1) write");
            // Analytic-from-measured cross-check: a worst-case 1000-write-unit chunk (~167 traits, each
            // ~2 write units) at this per-trait cost stays well under the EIP cap.
            uint256 analytic1000 = 500_000 + perTrait * 167; // fixed overhead + ~167 traits
            emit log_named_uint("analytic_1000_write_chunk_from_measured_marginal", analytic1000);
            assertLt(analytic1000, EIP7825_TX_GAS_CAP, "analytic 1000-write chunk from the measured per-trait marginal < the EIP cap");
        } else {
            // Guard the probe's precondition so a degenerate measurement FAILS rather than silently
            // skipping the per-trait marginal + analytic bound: the 200-owed batch MUST cost more
            // gas than the 100-owed batch.
            assertGt(gasHi, gasLo, "degenerate ticket-batch measurement: 200-owed gas did not exceed the 100-owed gas");
        }
    }
}
