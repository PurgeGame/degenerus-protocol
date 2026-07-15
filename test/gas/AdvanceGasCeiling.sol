// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @title AdvanceGasCeiling — the REUSABLE EIP-7825 gas-ceiling property component
/// @notice advanceGame() is the mandatory permissionless heartbeat. A single advanceGame tx that
///         exceeds the EIP-7825 per-tx gas cap (16,777,216) can never complete -> permanent,
///         unrecoverable game-over (the protocol bricks). This file factors the v60 one-shot
///         (test/gas/GameOverCompositionAdvanceGas.t.sol) into a shared, parameterized component so
///         FUZZ-03 can exercise it over many reachable pre-states AND Phase 384 / COMPO-02 can drive
///         the SAME seeder + measure loop against the real advanceGame over its own fuzzed states
///         without re-authoring the etch-seed-measure mechanism.
///
///         The three reusable seams (FUZZ-03 SC3):
///           (a) _etchSeedRestore(...)        — etch the GameSeeder overlay, write a worst-case
///                                              advanceGame pre-state from PARAMETERS, restore the
///                                              real production code so the measured tx runs the exact
///                                              production advanceGame() bytecode, fund + warp.
///           (b) _driveAndAssertUnderCap(...) — drive the real game.advanceGame() in a bounded loop,
///                                              measure gasleft() per tx, assertLe(txGas, cap) on EACH
///                                              tx, track the max (for the 10M soft target), and report
///                                              whether the heavy branch (gameOver()/terminal jackpot)
///                                              was actually reached (non-vacuity).
///           (c) the EIP7825_TX_GAS_CAP / GAS_TARGET constants the assertions key off.
///
/// @dev TEST-INFRA ONLY. NO contracts/*.sol is mutated. The GameSeeder is a clean DegenerusGame
///      subclass — etch-safe because type().runtimeCode carries no constructor side effects, so
///      vm.etch'ing it onto the live game then restoring the real code leaves the measured tx running
///      production bytecode against storage the overlay seeded. Storage symbol names (level,
///      purchaseStartDay, dailyIdx, levelPrizePool, rngWordByDay, ticketQueue, entriesOwedPacked,
///      ticketCursor, ticketLevel, lvlTraitEntry, lootboxRngWordByIndex, _lrWrite/LR_INDEX_*) are
///      the live c4d48008 names (confirmed against 380-01-LAYOUT-KEY.md / forge inspect storageLayout).

/// @dev Seeder overlay: writes a worst-case advanceGame pre-state directly into the live game storage.
///      Both entrypoints share one body so the named v60 game-over regression keeps the EXACT pre-state
///      while Phase 384 / the fuzz can drive arbitrary reachable geometries through the same writes.
contract GameSeeder is DegenerusGame {
    /// @notice Parameterized worst-case advanceGame seeder (the general seam Phase 384 calls).
    /// @param lvl          current game level (>=10 so the bounded deity-refund loop is skipped; a
    ///                     deeper level also means deeper trait buckets)
    /// @param rngWord      the (pre-seeded) day word; non-zero so `_gameOverEntropy` is bypassed
    /// @param readOwed     traits owed by the committed read-slot player (one cold finishing batch)
    /// @param writeOwed    traits owed by the later write-slot player (excluded from terminal draw)
    /// @param winTraits    the 4 winning trait ids `runTerminalJackpot` rolls for `rngWord`
    /// @param bucketCounts the bucket geometry for the seeded pool (305-winner geometry for the cap)
    /// @param base         disjoint address-space base for synthetic holders
    function seedAdvanceWorstCase(
        uint24 lvl,
        uint256 rngWord,
        uint256 readOwed,
        uint256 writeOwed,
        uint8[4] calldata winTraits,
        uint16[4] calldata bucketCounts,
        uint160 base
    ) external {
        _seedAdvanceWorstCase(lvl, rngWord, readOwed, writeOwed, winTraits, bucketCounts, base);
    }

    /// @dev Shared seeder body. Both external entrypoints route here so the named game-over regression
    ///      and the parameterized fuzz write the identical pre-state shape from their own args.
    function _seedAdvanceWorstCase(
        uint24 lvl,
        uint256 rngWord,
        uint256 readOwed,
        uint256 writeOwed,
        uint8[4] memory winTraits,
        uint16[4] memory bucketCounts,
        uint160 base
    ) private {
        uint24 day = _simulatedDayIndex();

        // --- Liveness game-over pre-state ---
        // lvl != 0 + (currentDay - psd > 120) + target-never-met => _livenessTriggered() == true.
        level = lvl;
        purchaseStartDay = 0;
        dailyIdx = day - 1; // day == dailyIdx+1: no day-clamp, no mid-day branch -> _handleGameOverPath
        levelPrizePool[lvl] = type(uint256).max; // _getNextPrizePool() (0) < target => liveness fires
        rngWordByDay[day] = rngWord; // != 0 => skip the entropy/VRF block, go straight to ticket drain

        // lootbox entropy word the ticket batch reads at lootboxRngWordByIndex[LR_INDEX-1].
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = rngWord | 1;

        uint24 pl = lvl + 1; // purchaseLevel the drain processes (drain calls processTicketBatch(lvl+1))

        // Historical two-slot fixture: the read slot is the committed heavy batch. The populated
        // write slot is later work that the terminal path must not promote into this entropy outcome.
        _seedSlot(_tqReadKey(pl), base, readOwed);
        _seedSlot(_tqWriteKey(pl), base + 0x1000, writeOwed);
        ticketCursor = 0;
        ticketLevel = 0;

        // Terminal jackpot buckets: seed the winning-trait buckets so runTerminalJackpot resolves the
        // full geometry (every selected winner is a real, non-zero holder).
        for (uint8 q; q < 4; ++q) {
            address[] storage holders = lvlTraitEntry[pl][winTraits[q]];
            uint256 n = uint256(bucketCounts[q]) + 8; // a few extra so selection never hits address(0)
            uint160 b = base + uint160(0x100000) + uint160(q) * 0x40000;
            for (uint256 i; i < n; ++i) holders.push(address(b + uint160(i + 1)));
        }
    }

    /// @notice The v60 game-over composition pre-state (fixed 6d2c8d0c) — kept verbatim-equivalent so
    ///         the named regression drives the EXACT historical worst case through the reusable loop.
    function seedGameOverWorstCase(
        uint24 lvl,
        uint256 rngWord,
        uint256 readOwed,
        uint256 writeOwed,
        uint8[4] calldata winTraits,
        uint16[4] calldata bucketCounts,
        uint160 base
    ) external {
        _seedAdvanceWorstCase(lvl, rngWord, readOwed, writeOwed, winTraits, bucketCounts, base);
    }

    function _seedSlot(uint24 key, uint160 base, uint256 owed) private {
        address p = address(base + 1);
        ticketQueue[key].push(p);
        // packed layout: owed in bits [8:], remainder in bits [0:8].
        entriesOwedPacked[key][p] = uint40(uint40(owed) << 8);
    }
}

/// @dev Reusable property base. Inherit it, call _etchSeedRestore(...) with a worst-case pre-state,
///      then _driveAndAssertUnderCap(...) to assert every advanceGame tx clears the EIP-7825 cap and
///      to learn the per-tx max + whether the heavy branch was exercised. Phase 384 / COMPO-02 import
///      THIS — they do not re-author the seeder or the measure loop.
abstract contract AdvanceGasCeilingBase is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this = permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev USER soft comfort target.
    uint256 internal constant GAS_TARGET = 10_000_000;

    // Production caps mirrored from DegenerusGameJackpotModule (the 305-winner geometry).
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;
    uint32 internal constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

    /// @dev Pool funded into the game so the terminal jackpot reaches the full geometry. >> 200 ETH
    ///      floor so bucketCountsForPoolCap saturates to the 305-winner cap.
    uint256 internal constant GAME_FUNDS = 1000 ether;

    /// @notice Derive the winning traits + bucket geometry runTerminalJackpot will actually roll for
    ///         `rngWord` at `lvl` and `GAME_FUNDS`, so the seeded buckets match the live jackpot's roll.
    /// @dev Mirrors runTerminalJackpot's getRandomTraits + bucketCountsForPoolCap derivation.
    function _deriveJackpot(uint24 lvl, uint256 rngWord)
        internal
        pure
        returns (uint8[4] memory traitIds, uint16[4] memory bucketCounts)
    {
        traitIds = JackpotBucketLib.getRandomTraits(rngWord);
        uint256 effEntropy = EntropyLib.hash2(rngWord, uint256(lvl) + 1);
        bucketCounts = JackpotBucketLib.bucketCountsForPoolCap(
            GAME_FUNDS, effEntropy, DAILY_ETH_MAX_WINNERS, DAILY_JACKPOT_SCALE_MAX_BPS
        );
    }

    /// @notice (a) Etch the GameSeeder overlay, write a worst-case advanceGame pre-state from the given
    ///         parameters, restore the REAL production code (so the measured tx runs production
    ///         advanceGame bytecode), fund the pool, and warp past the 120-day liveness threshold.
    /// @param lvl       game level for the seeded pre-state (>=10)
    /// @param rngWord   the pre-seeded day word (forced non-zero so the VRF/entropy block is skipped)
    /// @param readOwed  committed read-slot owed size — bound near the cold write budget by the caller
    /// @param writeOwed excluded later write-slot owed size — retained from the historical fixture
    /// @param base      disjoint synthetic-holder address base
    function _etchSeedRestore(
        uint24 lvl,
        uint256 rngWord,
        uint256 readOwed,
        uint256 writeOwed,
        uint160 base
    ) internal {
        uint256 word = rngWord | 1; // force non-zero so _gameOverEntropy is bypassed
        (uint8[4] memory traitIds, uint16[4] memory bucketCounts) = _deriveJackpot(lvl, word);

        bytes memory realGameCode = address(game).code;
        vm.etch(address(game), type(GameSeeder).runtimeCode);
        GameSeeder(payable(address(game))).seedAdvanceWorstCase(
            lvl, word, readOwed, writeOwed, traitIds, bucketCounts, base
        );
        vm.etch(address(game), realGameCode);

        // Fund the contract so the terminal jackpot pool reaches the 305-winner geometry.
        vm.deal(address(game), GAME_FUNDS);

        // Warp past the 120-day liveness threshold (psd was seeded to 0).
        vm.warp(block.timestamp + 200 days);
    }

    /// @notice (b) Drive the REAL game.advanceGame() in a bounded loop, asserting EVERY single tx
    ///         consumes <= EIP7825_TX_GAS_CAP. Stops when game-over latches or the iteration budget is
    ///         spent.
    /// @param maxTxIters cap on advanceGame txs to drive (bound so a long run never lands mid-tx).
    /// @return maxTxGas     the largest single-tx gas observed (surface for the < GAS_TARGET soft check)
    /// @return reachedHeavy whether the heavy branch was exercised — true once game-over latches after
    ///                      the committed ticket batch and isolated terminal jackpot. If false, the
    ///                      measurement is vacuous and the caller MUST fail acceptance.
    function _driveAndAssertUnderCap(uint256 maxTxIters)
        internal
        returns (uint256 maxTxGas, bool reachedHeavy)
    {
        for (uint256 i = 0; i < maxTxIters; ++i) {
            uint256 g0 = gasleft();
            game.advanceGame();
            uint256 used = g0 - gasleft();
            emit log_named_uint("advance_tx_gas[i]", used);
            if (used > maxTxGas) maxTxGas = used;
            // The per-tx EIP-7825 assertion — fires on EACH advanceGame tx in the drain.
            assertLe(
                used,
                EIP7825_TX_GAS_CAP,
                "GAS-CEIL DoS: a single advanceGame tx exceeded 16,777,216 (EIP-7825 brick)"
            );
            if (game.gameOver()) {
                reachedHeavy = true; // terminal jackpot ran -> the heavy branch was exercised
                break;
            }
        }
        emit log_named_uint("max_advance_tx_gas", maxTxGas);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);
    }
}
