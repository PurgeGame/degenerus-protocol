// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title GameOverCompositionAdvanceGas — v60 GASCEIL: the historical game-over composition
/// @notice END-TO-END regression driving the REAL `advanceGame()` from the historical two-slot
///         liveness-game-over pre-state. Before the fix, `_handleGameOverPath` composed both ticket
///         slots and the terminal jackpot in one transaction; the per-stage harness was blind to it.
///
///         The breach (pre-fix): one liveness game-over `advanceGame()` tx runs
///           round-1 ticket batch (read slot, ~6.5M, finishes) +
///           round-2 ticket batch (write slot, ~6.5M, finishes) +
///           handleGameOverDrain -> runTerminalJackpot (305 winners, ~7.3M)
///         => ~20M > 16,777,216 (EIP-7825). advanceGame is the mandatory heartbeat; a single tx
///         over the cap = a permanent, unrecoverable game-over (the tx can never complete).
///
///         Now every step is its own transaction: the committed read snapshot drains on its own
///         word, the write cohort is swapped in once (liveness has frozen purchases) before the
///         ending requests its terminal word, that word is applied (deriving the skipped days),
///         the write cohort drains on the word, and the terminal jackpot pays. Every measured
///         transaction stays under the cap.
/// @dev Test-only. NO contracts/*.sol is mutated. A GameSeeder (DegenerusGame subclass with seeders)
///      is etched onto the live game via type().runtimeCode (no constructor side effects), used to
///      write the worst-case pre-state into the real game storage, then the real code is restored so
///      the measured tx runs the exact production `advanceGame()` bytecode.

/// @dev Seeder overlay: writes the worst-case game-over pre-state directly into the live game storage.
contract GameSeeder is DegenerusGame, BucketSeed {
    /// @param lvl          current game level (>=10 so the bounded deity-refund loop is skipped)
    /// @param rngWord      the word the winning buckets are seeded for; it answers the terminal request
    /// @param readOwed     traits owed by the committed read-slot player (one cold finishing batch)
    /// @param writeOwed    traits owed by the write-slot player (swapped in before the terminal request)
    /// @param winTraits    the 4 winning trait ids `runTerminalJackpot` rolls for `rngWord`
    /// @param bucketCounts the 305-winner bucket geometry for the seeded pool
    /// @param base         disjoint address-space base for synthetic holders
    function seedGameOverWorstCase(
        uint24 lvl,
        uint256 rngWord,
        uint256 readOwed,
        uint256 writeOwed,
        uint8[4] calldata winTraits,
        uint16[4] calldata bucketCounts,
        uint160 base
    ) external {
        uint24 day = _simulatedDayIndex();

        // --- Liveness game-over pre-state ---
        // lvl != 0 + target never met; the 200-day warp after seeding also fires the no-seal
        // deadman, so the ending's terminal word derives the capped 31 skipped days as well.
        level = lvl;
        purchaseStartDay = 0;
        dailyIdx = day - 1;
        // A reachable large pool keeps the target unmet (_getNextPrizePool() is zero).
        levelPrizePool[lvl] = 100_000 ether;
        _recordDailyRng(day, rngWord); // the last sealed day's word; the ending requests its own

        // lootbox entropy word the ticket batch reads at _lootboxWord(LR_INDEX-1).
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = rngWord | 1; _setRngSessionPublished(true); _setRngComplete(false);

        uint24 pl = lvl + 1; // purchaseLevel the drain processes (drain calls processTicketBatch(lvl+1))

        // The historical two-slot fixture: both slots are heavy finishing batches. Before the
        // fix both finished and composed with the terminal jackpot in one transaction.
        _seedSlot(_tqReadKey(pl), base, readOwed);
        _seedSlot(_tqWriteKey(pl), base + 0x1000, writeOwed);
        ticketCursor = 0;
        ticketLevel = 0;

        // Terminal jackpot buckets: seed the 4 winning-trait buckets so runTerminalJackpot resolves
        // the full 305-winner geometry (every selected winner is a real, non-zero holder).
        for (uint8 q; q < 4; ++q) {
            uint256 n = uint256(bucketCounts[q]) + 8; // a few extra so selection never hits address(0)
            uint160 b = base + uint160(0x100000) + uint160(q) * 0x40000;
            _seedBucketDistinct(pl, winTraits[q], n, b);
        }
    }

    function _seedSlot(uint24 key, uint160 base, uint256 owed) private {
        address p = address(base + 1);
        uint80 ownerBits = _registerEntryOwner(p, uint24(key & ((uint24(1) << 22) - 1)));
        _tqAppend(key, uint32(ownerBits >> OWNER_IDX_SHIFT));
        // packed layout: owed in bits [8:], remainder in bits [0:8].
        _seedOwedAt(key, p, ownerBits | (uint80(owed) << 8));
    }
}

contract GameOverCompositionAdvanceGas is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this = permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev Review ceiling and stronger fixture-specific comfort target.
    uint256 internal constant REVIEW_GAS_CAP = 11_500_000;
    uint256 internal constant GAS_TARGET = 10_000_000;
    uint256 internal constant TX_INTRINSIC = 21_064;
    uint256 internal constant MAX_TERMINAL_ADVANCES = 16;

    // Production caps mirrored from DegenerusGameJackpotModule.
    uint16 internal constant DAILY_ETH_MAX_WINNERS = 305;
    uint32 internal constant DAILY_JACKPOT_SCALE_MAX_BPS = 63_600;

    uint24 internal constant LVL = 110; // >=10 (no deity-refund loop) + a deep-bucket level
    uint256 internal constant GAME_FUNDS = 1000 ether; // terminal pool >> 200 ETH floor -> 305 geometry

    function setUp() public {
        _deployProtocol();
    }

    function _word() internal pure returns (uint256) {
        return uint256(keccak256("gasceil_gameover_word")) | 1;
    }

    /// @dev Mirror `runTerminalJackpot`'s winning-trait + geometry derivation so the seeded buckets
    ///      match the traits the live jackpot will actually roll for `rngWord` at the seeded pool.
    function _deriveJackpot() internal pure returns (uint8[4] memory traitIds, uint16[4] memory bucketCounts) {
        uint256 rngWord = _word();
        traitIds = JackpotBucketLib.getRandomTraits(rngWord);
        uint256 effEntropy = EntropyLib.hash2(rngWord, LVL + 1);
        bucketCounts = JackpotBucketLib.bucketCountsForPool(GAME_FUNDS, effEntropy, DAILY_JACKPOT_SCALE_MAX_BPS);
    }

    /// @dev Etch the seeder, write the worst-case pre-state into live game storage, restore real code.
    function _seedWorstCase(uint256 readOwed, uint256 writeOwed) internal {
        (uint8[4] memory traitIds, uint16[4] memory bucketCounts) = _deriveJackpot();

        bytes memory realGameCode = address(game).code;
        vm.etch(address(game), type(GameSeeder).runtimeCode);
        GameSeeder(payable(address(game)))
            .seedGameOverWorstCase(LVL, _word(), readOwed, writeOwed, traitIds, bucketCounts, uint160(0x500000000));
        vm.etch(address(game), realGameCode);

        // Fund the contract so the terminal jackpot pool reaches the 305-winner geometry.
        vm.deal(address(game), GAME_FUNDS);

        // Warp past the 120-day liveness threshold (psd was seeded to 0).
        vm.warp(block.timestamp + 200 days);
    }

    // =========================================================================
    // The headline assertion: EVERY game-over advanceGame tx stays under 11.5M.
    // =========================================================================

    /// @notice Drive the seeded worst-case game-over through the REAL advanceGame() and assert that
    ///         no single tx exceeds the 11.5M hard cap, while game-over still completes.
    ///
    ///         PRE-FIX  : the first advanceGame() runs round1+round2+terminal-jackpot in ONE tx
    ///                    (~20M). The per-tx assertion below FAILS — that failure (with the logged
    ///                    ~20M) is the demonstration of the composition DoS.
    ///         POST-FIX : each batch, the terminal request, its application and the terminal
    ///                    jackpot run in separate txs; every tx must remain below 11.5M.
    function test_GameOverDrain_EveryAdvanceTxUnderHardCap() public {
        // Keep both historical slots near the cold write budget. They drain in separate calls,
        // followed by the terminal ETH payout.
        // FOUNDRY_ISOLATE=true makes every production invocation a cold transaction.
        _seedWorstCase(170, 170);

        uint256 maxTxGas;
        uint256 firstTxGas;
        bool over;
        uint256 winners;

        for (uint256 i = 0; i < MAX_TERMINAL_ADVANCES; i++) {
            vm.recordLogs();
            uint256 g0 = gasleft();
            game.advanceGame{gas: REVIEW_GAS_CAP - TX_INTRINSIC}();
            uint256 used = g0 - gasleft() + TX_INTRINSIC;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].topics[0] == keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)")) ++winners;
            }
            emit log_named_uint("advance_tx_gas[i]", used);
            assertLt(used, REVIEW_GAS_CAP, "terminal stage exceeds 11.5M review cap");
            if (i == 0) firstTxGas = used;
            if (used > maxTxGas) maxTxGas = used;
            if (used > EIP7825_TX_GAS_CAP) over = true;
            if (game.gameOver()) break;
            // The ending requests its own terminal word once the read cohort has drained and
            // the write cohort is swapped in; answer it with the word the buckets were seeded for.
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (,, bool done) = mockVRF.pendingRequests(id);
                if (!done) mockVRF.fulfillRandomWords(id, _word());
            }
        }

        emit log_named_uint("first_advance_tx_gas", firstTxGas);
        emit log_named_uint("max_advance_tx_gas", maxTxGas);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);

        assertTrue(game.gameOver(), "game-over must complete (funds drained, not stranded)");
        assertEq(winners, DAILY_ETH_MAX_WINNERS, "all 305 terminal award slots must execute");

        // The breach assertion. Pre-fix this FAILS on the ~20M composed tx; post-fix it PASSES.
        assertFalse(over, "GAS-CEIL DoS: a single game-over advanceGame tx exceeded 16,777,216 (EIP-7825 brick)");
        // Stronger: post-fix every game-over tx should also clear the 10M soft target.
        assertLt(maxTxGas, GAS_TARGET, "every game-over advanceGame tx clears the 10M soft target");
    }
}
