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

/// @title Fixed-work gas diagnostics for terminal awards and ticket drains.
/// @notice These fixtures measure live worker code at explicit cohort sizes. They
///         do not describe a fixed stage per mineFlip call or a fixed write budget.
///         RoundDrainChunkGas and the native worker suites test admission envelopes;
///         AdvanceGasCeilingFuzz tests resumable terminal completion at bounded gas.

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

/// @dev Queue seeder and delegatecall host for the live metered ticket worker.
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

    /// @notice Seed the queue and force the ticket-level reset path at cursor zero.
    function seedTicketQueue(uint24 lvl, uint256 n, uint32 owedEach, uint160 base) external {
        _seedQueue(lvl, n, owedEach, base);
        ticketCursor = 0;
        ticketLevel = 0;
    }

    /// @notice Seed a resumed queue with earlier entries already retired.
    function seedTicketQueueWarmResume(uint24 lvl, uint256 n, uint32 owedEach, uint160 base, uint32 startCursor)
        external
    {
        _seedQueue(lvl, n, owedEach, base);
        // Pin level == lvl so runTicketWork does NOT reset the cursor, and start at a non-zero cursor
        // so the worker resumes after earlier retired entries.
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

    // Current terminal geometry; historical test/log names preserve baseline comparison.
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;

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
    // Fixed-work terminal distribution measurement
    // =========================================================================

    /// @notice Measure the complete live 305-winner distribution at a fixed work size.
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
        (MineFlipGas.Result memory result, uint256 paidWei) = jp.runTerminalJackpotWork(POOL_WEI, TARGET_LVL, _word(), gasleft());
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(result.done, "fixed-work measurement covers the whole terminal distribution");
        assertGt(paidWei, 0, "the measured worst-case jackpot actually paid out");

        emit log_named_uint("STAGE_8_11_12_daily_eth_jackpot_305_winner_gas", gasUsed);
        // Total fixed-work cost is diagnostic. This worker may checkpoint its
        // winners; admission safety is checked per award/group in native suites.

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

    /// @notice Measure ticket progress at a 10M caller allowance for one deep queue entry.
    function test_Stage0_1_5_6_7_TicketBatch_WriteBudget_Measured() public {
        uint32 owed = 600;
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

    /// @notice Measure ticket progress from a nonzero cursor at the same 10M caller allowance.
    function test_Stage7_TicketBatch_WarmResume_FullBudget_Measured() public {
        // Two deep entries, with the first already retired.
        tb.seedTicketQueueWarmResume(TARGET_LVL, 2, 700, uint160(0x50000), 1);
        assertEq(tb.queueLen(TARGET_LVL), 2, "fixture: 2 players queued");
        assertEq(tb.cursor(), 1, "fixture: cursor starts at index 1");

        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = tb.runTicketWork{gas: CHUNK_GAS}(TARGET_LVL, CHUNK_GAS);
        (bool finished, bool worked) = (r.done, r.progressed);
        uint256 gasUsed = g0 - gasleft();
        assertTrue(worked, "non-vacuity: a realistic allowance must mint the seeded queue");

        emit log_named_uint("STAGE_7_ticket_batch_WARM_call_gas_at_10M", gasUsed);
        emit log_named_uint("ticket_batch_warm_finished", finished ? 1 : 0);
    }

    /// @notice Compare completed 200-entry and 100-entry drains at the same caller allowance. The difference is diagnostic, not a proof for an extrapolated batch size.
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
            // Comparative marginal only; RoundDrainChunkGas tests the live operation envelopes.
            assertLt(perTrait, 200_000, "per-trait cold push is a bounded O(1) write");
        } else {
            // Guard the probe's precondition so a degenerate measurement FAILS rather than silently
            // skipping the per-trait marginal + analytic bound: the 200-owed batch MUST cost more
            // gas than the 100-owed batch.
            assertGt(gasHi, gasLo, "degenerate ticket-batch measurement: 200-owed gas did not exceed the 100-owed gas");
        }
    }
}
