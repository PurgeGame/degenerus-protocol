// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

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
///         The fix drains only the entropy-committed read snapshot, returns after its finishing
///         batch, and leaves the later write buffer outside the terminal outcome. The terminal
///         jackpot therefore runs in its OWN tx and every measured transaction stays under the cap.
/// @dev Test-only. NO contracts/*.sol is mutated. A GameSeeder (DegenerusGame subclass with seeders)
///      is etched onto the live game via type().runtimeCode (no constructor side effects), used to
///      write the worst-case pre-state into the real game storage, then the real code is restored so
///      the measured tx runs the exact production `advanceGame()` bytecode.

/// @dev Seeder overlay: writes the worst-case game-over pre-state directly into the live game storage.
contract GameSeeder is DegenerusGame {
    /// @param lvl          current game level (>=10 so the bounded deity-refund loop is skipped)
    /// @param rngWord      the (pre-seeded) day word; non-zero so `_gameOverEntropy` is bypassed
    /// @param readOwed     traits owed by the committed read-slot player (one cold finishing batch)
    /// @param writeOwed    traits owed by the later write-slot player (excluded from terminal draw)
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

        // Preserve the historical two-slot fixture: the committed read slot is a heavy finishing
        // batch, while the populated write slot proves that later work is not promoted into this
        // entropy outcome. Before the fix both finished and composed with the terminal jackpot.
        _seedSlot(_tqReadKey(pl), base, readOwed);
        _seedSlot(_tqWriteKey(pl), base + 0x1000, writeOwed);
        ticketCursor = 0;
        ticketLevel = 0;

        // Terminal jackpot buckets: seed the 4 winning-trait buckets so runTerminalJackpot resolves
        // the full 305-winner geometry (every selected winner is a real, non-zero holder).
        for (uint8 q; q < 4; ++q) {
            address[] storage holders = lvlTraitEntry[pl][winTraits[q]];
            uint256 n = uint256(bucketCounts[q]) + 8; // a few extra so selection never hits address(0)
            uint160 b = base + uint160(0x100000) + uint160(q) * 0x40000;
            for (uint256 i; i < n; ++i) holders.push(address(b + uint160(i + 1)));
        }
    }

    function _seedSlot(uint24 key, uint160 base, uint256 owed) private {
        address p = address(base + 1);
        ticketQueue[key].push(p);
        // packed layout: owed in bits [8:], remainder in bits [0:8].
        entriesOwedPacked[key][p] = uint40(uint40(owed) << 8);
    }
}

contract GameOverCompositionAdvanceGas is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this = permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    /// @dev USER soft comfort target.
    uint256 internal constant GAS_TARGET = 10_000_000;

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
    function _deriveJackpot()
        internal
        pure
        returns (uint8[4] memory traitIds, uint16[4] memory bucketCounts)
    {
        uint256 rngWord = _word();
        traitIds = JackpotBucketLib.getRandomTraits(rngWord);
        uint256 effEntropy = EntropyLib.hash2(rngWord, LVL + 1);
        bucketCounts = JackpotBucketLib.bucketCountsForPool(
            GAME_FUNDS, effEntropy, DAILY_JACKPOT_SCALE_MAX_BPS
        );
    }

    /// @dev Etch the seeder, write the worst-case pre-state into live game storage, restore real code.
    function _seedWorstCase(uint256 readOwed, uint256 writeOwed) internal {
        (uint8[4] memory traitIds, uint16[4] memory bucketCounts) = _deriveJackpot();

        bytes memory realGameCode = address(game).code;
        vm.etch(address(game), type(GameSeeder).runtimeCode);
        GameSeeder(payable(address(game))).seedGameOverWorstCase(
            LVL, _word(), readOwed, writeOwed, traitIds, bucketCounts, uint160(0x5_0000_0000)
        );
        vm.etch(address(game), realGameCode);

        // Fund the contract so the terminal jackpot pool reaches the 305-winner geometry.
        vm.deal(address(game), GAME_FUNDS);

        // Warp past the 120-day liveness threshold (psd was seeded to 0).
        vm.warp(block.timestamp + 200 days);
    }

    // =========================================================================
    // The headline assertion: EVERY game-over advanceGame tx stays under the EIP cap.
    // =========================================================================

    /// @notice Drive the seeded worst-case game-over through the REAL advanceGame() and assert that
    ///         no single tx exceeds the EIP-7825 cap, while game-over still completes.
    ///
    ///         PRE-FIX  : the first advanceGame() runs round1+round2+terminal-jackpot in ONE tx
    ///                    (~20M). The per-tx assertion below FAILS — that failure (with the logged
    ///                    ~20M) is the demonstration of the composition DoS.
    ///         POST-FIX : the committed read batch and terminal jackpot run in separate txs; the
    ///                    later write buffer stays excluded, every tx < 16.7M -> PASSES.
    function test_GameOverDrain_EveryAdvanceTxUnderEipCap() public {
        // Keep both historical slots near the cold write budget. Only the committed read slot is
        // processed post-fix; pre-fix both finishing batches composed with the terminal jackpot.
        _seedWorstCase(170, 170);

        uint256 maxTxGas;
        uint256 firstTxGas;
        bool over;

        for (uint256 i = 0; i < 12; i++) {
            uint256 g0 = gasleft();
            game.advanceGame();
            uint256 used = g0 - gasleft();
            emit log_named_uint("advance_tx_gas[i]", used);
            if (i == 0) firstTxGas = used;
            if (used > maxTxGas) maxTxGas = used;
            if (used > EIP7825_TX_GAS_CAP) over = true;
            if (game.gameOver()) break;
        }

        emit log_named_uint("first_advance_tx_gas", firstTxGas);
        emit log_named_uint("max_advance_tx_gas", maxTxGas);
        emit log_named_uint("eip7825_tx_gas_cap", EIP7825_TX_GAS_CAP);

        assertTrue(game.gameOver(), "game-over must complete (funds drained, not stranded)");

        // The breach assertion. Pre-fix this FAILS on the ~20M composed tx; post-fix it PASSES.
        assertFalse(
            over,
            "GAS-CEIL DoS: a single game-over advanceGame tx exceeded 16,777,216 (EIP-7825 brick)"
        );
        // Stronger: post-fix every game-over tx should also clear the 10M soft target.
        assertLt(maxTxGas, GAS_TARGET, "every game-over advanceGame tx clears the 10M soft target");
    }
}
