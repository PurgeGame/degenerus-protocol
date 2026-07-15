// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {AdvanceGasCeilingBase} from "./AdvanceGasCeiling.sol";

/// @title AdvanceGasCeilingFuzz — FUZZ-03 GAS-CEILING: the durable EIP-7825 advanceGame property
/// @notice Exercises the REUSABLE AdvanceGasCeilingBase (test/gas/AdvanceGasCeiling.sol) over MANY
///         reachable worst-case advanceGame pre-states, asserting EVERY single advanceGame tx in the
///         game-over drain consumes <= 16,777,216 gas (EIP-7825). advanceGame is the mandatory
///         permissionless heartbeat — a single tx above the cap can never complete -> permanent,
///         unrecoverable game-over (the protocol bricks).
///
///         Two complementary cases drive the SAME extracted component (SC3 — reusability):
///           - testFuzz_advanceGame_everyTxUnderCap  : fuzzes the bucket geometry (rngWord), the
///                                                     level (bucket depth), and the per-round owed
///                                                     sizes over reachable worst-case pre-states.
///           - test_gameOverComposition_regression_underCap : drives the EXACT v60 game-over
///                                                     composition (the gasceil shape, fixed
///                                                     6d2c8d0c) through the component as the named
///                                                     regression — game-over completes, every tx <
///                                                     cap, max < the 10M soft target.
/// @dev TEST-ONLY. NO contracts/*.sol is mutated. Phase 384 / COMPO-02 will consume the SAME base
///      against its own fuzzed states without re-authoring the etch-seed-measure mechanism.
contract AdvanceGasCeilingFuzz is AdvanceGasCeilingBase {
    // Per-round owed sizes the seeder writes. WRITES_BUDGET_SAFE = 550, scaled 65% on the cold first
    // batch -> ~357 write units. Bounding owed into [HEAVY_OWED_MIN, HEAVY_OWED_MAX] keeps each round
    // HEAVY (a deep single-player drain) yet FINISHING within one cold batch — exactly the worst-case
    // branch where round 1 + round 2 + the terminal jackpot can fall through into one tx pre-fix (the
    // composition under measurement, per the worst-case-branch discipline). A larger owed would split
    // the batch across txs (a LIGHTER per-tx shape — not the composition worst case).
    uint256 internal constant HEAVY_OWED_MIN = 120;
    uint256 internal constant HEAVY_OWED_MAX = 175;

    // Reachable level band: >= 10 so the bounded deity-refund loop is skipped; a deeper level also
    // means deeper trait buckets (a heavier terminal-jackpot resolve). Capped well under uint24 so the
    // seeded (lvl+1) purchase level and the bucket address-space arithmetic stay in range.
    uint24 internal constant LVL_MIN = 10;
    uint24 internal constant LVL_MAX = 4000;

    // Disjoint synthetic-holder base per fuzz run so seeded queues/buckets never alias across states.
    uint160 internal constant FUZZ_BASE = uint160(0x6_0000_0000);

    // Bound the drain loop so a long run never lands mid-tx (pacing): the game-over double-drain +
    // terminal jackpot post-fix splits across a handful of txs, far under this ceiling.
    uint256 internal constant MAX_DRAIN_TX = 16;

    function setUp() public {
        _deployProtocol();
    }

    /// @notice The headline durable property: across reachable worst-case advanceGame pre-states
    ///         (fuzzed bucket geometry / level / owed sizes), EVERY single advanceGame tx in the
    ///         game-over drain stays <= EIP7825_TX_GAS_CAP (asserted per-tx inside the base) and the
    ///         heavy branch is actually reached (non-vacuity), with the per-tx max surfaced for the
    ///         < GAS_TARGET soft check.
    function testFuzz_advanceGame_everyTxUnderCap(
        uint256 readOwed,
        uint256 writeOwed,
        uint256 geomSeed,
        uint256 lvlSeed
    ) public {
        // Heavy-but-finishing per-round owed sizes (the worst-case fall-through branch).
        readOwed = bound(readOwed, HEAVY_OWED_MIN, HEAVY_OWED_MAX);
        writeOwed = bound(writeOwed, HEAVY_OWED_MIN, HEAVY_OWED_MAX);

        // Reachable deep level (deeper buckets -> heavier terminal-jackpot resolve).
        uint24 lvl = uint24(bound(lvlSeed, LVL_MIN, LVL_MAX));

        // The rngWord drives BOTH the winning-trait selection and (via effEntropy) the bucket-count
        // geometry inside _deriveJackpot — so fuzzing it fuzzes the 305-winner geometry the terminal
        // jackpot rolls. Force non-zero so the entropy/VRF block is bypassed (the base also ORs 1).
        uint256 rngWord = uint256(keccak256(abi.encodePacked("gasceil_fuzz", geomSeed))) | 1;

        // (a) etch the GameSeeder, write the worst-case pre-state from these params, restore the real
        //     production code, fund + warp. (b) drive the REAL advanceGame to game-over, asserting
        //     every tx <= the EIP-7825 cap inside the base.
        _etchSeedRestore(lvl, rngWord, readOwed, writeOwed, FUZZ_BASE);
        (uint256 maxTxGas, bool reachedHeavy) = _driveAndAssertUnderCap(MAX_DRAIN_TX);

        // Non-vacuity: the heavy branch (game-over latch -> ticket double-drain + terminal jackpot)
        // MUST have run, else the per-tx assertion measured nothing meaningful.
        assertTrue(
            reachedHeavy,
            "VACUOUS: game-over heavy branch never reached -> the per-tx cap assertion is meaningless"
        );

        // The per-tx <= cap assertion already fired inside _driveAndAssertUnderCap on EACH tx. Surface
        // the max for the 10M soft target (kept as a non-fatal observation in the fuzz so a single
        // unusually-heavy reachable geometry does not red the durable cap property — the HARD floor is
        // the EIP-7825 cap, asserted per-tx in the base).
        emit log_named_uint("fuzz_max_advance_tx_gas", maxTxGas);
        assertLe(maxTxGas, EIP7825_TX_GAS_CAP, "GAS-CEIL: fuzzed max advanceGame tx exceeded the EIP-7825 cap");
    }

    /// @notice The named v60 game-over composition regression (the gasceil shape, fixed 6d2c8d0c),
    ///         driven through the SAME reusable component. Pre-fix the first advanceGame ran
    ///         round1 + round2 + terminal-jackpot in ONE ~20M tx; post-fix the drain splits across
    ///         several txs each < cap, game-over still completes, and every tx clears the 10M soft
    ///         target. Mirrors the one-shot's assertions via the extracted base.
    function test_gameOverComposition_regression_underCap() public {
        // The EXACT historical worst case from GameOverCompositionAdvanceGas.t.sol.
        uint24 lvl = 110; // >= 10 (no deity-refund loop) + a deep-bucket level
        uint256 rngWord = uint256(keccak256("gasceil_gameover_word")) | 1;
        uint256 readOwed = 170; // heavy yet finishing in one cold batch
        uint256 writeOwed = 170;
        uint160 base = uint160(0x5_0000_0000);

        _etchSeedRestore(lvl, rngWord, readOwed, writeOwed, base);
        (uint256 maxTxGas, bool reachedHeavy) = _driveAndAssertUnderCap(MAX_DRAIN_TX);

        // Game-over must complete (funds drained, not stranded) — the heavy branch ran.
        assertTrue(reachedHeavy, "game-over must complete (funds drained, not stranded)");
        assertTrue(game.gameOver(), "game-over flag must latch");

        // The breach assertion: pre-fix this FAILS on the ~20M composed tx; post-fix every tx < cap
        // (already asserted per-tx in the base) AND the max clears the 10M soft target.
        emit log_named_uint("regression_max_advance_tx_gas", maxTxGas);
        assertLt(maxTxGas, GAS_TARGET, "every game-over advanceGame tx clears the 10M soft target");
    }
}
