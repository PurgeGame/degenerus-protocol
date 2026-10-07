// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {AdvanceGasCeilingBase} from "./AdvanceGasCeiling.sol";

/// @notice Fuzz terminal bucket geometry, level and queued work while requiring
///         completion at 10M execution gas per mineFlip call. Keep the historical
///         queued-state regression seeds; live native workers now checkpoint the
///         work. Run with FOUNDRY_ISOLATE=true for fresh transaction state.
contract AdvanceGasCeilingFuzz is AdvanceGasCeilingBase {
    // Historical regression cohort sizes; no production write-budget constant is
    // implied. Live worker admission decides how much each call can complete.
    uint256 internal constant HEAVY_OWED_MIN = 120;
    uint256 internal constant HEAVY_OWED_MAX = 175;

    // Reachable level band: >= 10 so the bounded deity-refund loop is skipped; a deeper level also
    // means deeper trait buckets (a heavier terminal-jackpot resolve). Capped well under uint24 so the
    // seeded (lvl+1) purchase level and the bucket address-space arithmetic stay in range.
    uint24 internal constant LVL_MIN = 10;
    uint24 internal constant LVL_MAX = 4000;

    // Disjoint synthetic-holder base per fuzz run so seeded queues/buckets never alias across states.
    uint160 internal constant FUZZ_BASE = uint160(0x600000000);

    // Two ticket cohorts, terminal RNG request/application and ETH payout are bounded
    // by the original driver allowance. Terminal FLIP games do not gate withdrawals.
    uint256 internal constant MAX_DRAIN_TX = 16;

    function setUp() public {
        _deployProtocol();
    }

    /// @notice Every bounded call progresses and the full terminal payout finishes.
    function testFuzz_advanceGame_everyTxUnderCap(
        uint256 readOwed,
        uint256 writeOwed,
        uint256 geomSeed,
        uint256 lvlSeed
    ) public {
        // Preserve the historically heavy cohort range across resumable calls.
        readOwed = bound(readOwed, HEAVY_OWED_MIN, HEAVY_OWED_MAX);
        writeOwed = bound(writeOwed, HEAVY_OWED_MIN, HEAVY_OWED_MAX);

        // Reachable deep level (deeper buckets -> heavier terminal-jackpot resolve).
        uint24 lvl = uint24(bound(lvlSeed, LVL_MIN, LVL_MAX));

        // The rngWord drives BOTH the winning-trait selection and (via effEntropy) the bucket-count
        // geometry inside _deriveJackpot — so fuzzing it fuzzes the 305-winner geometry the terminal
        // jackpot rolls; it also answers the terminal request (the base ORs 1).
        uint256 rngWord = uint256(keccak256(abi.encodePacked("gasceil_fuzz", geomSeed))) | 1;

        // (a) etch the GameSeeder, write the worst-case pre-state from these params, restore the real
        //     production code, fund + warp. (b) drive the REAL mineFlip to game-over, asserting
        //     progress and terminal completion at the supplied allowance.
        _etchSeedRestore(lvl, rngWord, readOwed, writeOwed, FUZZ_BASE);
        (uint256 maxTxGas, bool reachedHeavy) = _driveAndAssertUnderCap(MAX_DRAIN_TX);

        // Non-vacuity: the committed drain and complete terminal payout must run.
        assertTrue(
            reachedHeavy, "VACUOUS: terminal payout never completed at the bounded allowance"
        );

        // Every call already succeeded at the realistic allowance inside _driveAndAssertUnderCap.
        emit log_named_uint("fuzz_max_advance_tx_gas", maxTxGas);
    }

    /// @dev Preserve the level-51 queued-state seed as an additional reachable gas witness.
    function test_gameOverComposition_regression_level51QueuedGeometry() public {
        testFuzz_advanceGame_everyTxUnderCap(
            48_050_435_518_851_947_680_601_579_244_949_740_512_520_746_866_289_049_644_703_091_396_167_600_032,
            10_373_189_839_209_939_029_463_935_049_339_729_502_126_815_281_991_995_894_760_766,
            19_572_411_320_327_791_426_347_801_128_719,
            4_059_533_221_497_168_973
        );
    }

    /// @notice The named v60 game-over composition regression (the gasceil shape, fixed 6d2c8d0c),
    ///         driven through the SAME reusable component. Pre-fix the first mineFlip ran
    ///         round1 + round2 + terminal-jackpot in ONE ~20M tx; the engine now splits the drain into
    ///         checkpoints, so every call at a realistic 10M allowance succeeds and game-over completes.
    function test_gameOverComposition_regression_underCap() public {
        // The EXACT historical worst case from GameOverCompositionAdvanceGas.t.sol.
        uint24 lvl = 110; // >= 10 (no deity-refund loop) + a deep-bucket level
        uint256 rngWord = uint256(keccak256("gasceil_gameover_word")) | 1;
        uint256 readOwed = 170; // heavy yet finishing in one cold batch
        uint256 writeOwed = 170;
        uint160 base = uint160(0x500000000);

        _etchSeedRestore(lvl, rngWord, readOwed, writeOwed, base);
        (uint256 maxTxGas, bool reachedHeavy) = _driveAndAssertUnderCap(MAX_DRAIN_TX);

        // Game-over must complete (funds drained, not stranded) — the heavy branch ran.
        assertTrue(reachedHeavy, "game-over must complete (funds drained, not stranded)");
        assertTrue(game.gameOver(), "game-over flag must latch");

        // The breach assertion: pre-fix the ~20M composed drain could not run at a realistic
        // allowance; every call now succeeds at 10M (asserted per call in the base).
        emit log_named_uint("regression_max_advance_tx_gas", maxTxGas);
    }
}
