// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {BattlePaidMinerProbe, BattleConstructionGameSeed,
    BattleConstructionTableSeed} from "./JackpotBattleConstructionGas.t.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {Vm} from "forge-std/Vm.sol";

contract BattleMaximumTableSeed is BattleConstructionTableSeed {
    function configurePaid(uint24 day, uint8 mode) external {
        uint256 daySlot = uint256(day) * _BONUS_SLOTS_PER_DAY;
        bytes32 key = bytes32(daySlot + _BONUS_PERIODS_PER_DAY);
        if (mode == 1) { // Ordinary paid seats, no high extras.
            _dayTickets[daySlot] = 50;
            _highField[key] = 0;
        } else if (mode == 2) { // Detached, free-only jackpot after a skipped paid day.
            _boostBudget[day] = 0;
        } else if (mode == 3) { // Sole high seat takes the alternative fee-booking branch.
            _dayTickets[daySlot] = 50;
            _highField[key] = 1;
        }
    }

    function configureBoards(uint32[] calldata players, bool fullBoard) external {
        uint32 chips = uint32((3 << 9) | (3 << 12) | (1 << 27));
        // The inexpensive comparison is the default zero preference, not a malformed board.
        uint256 preference = fullBoard
            ? (CrapsPreferenceLib.compress(chips) << CrapsPreferenceLib.SHIFT) | CrapsPreferenceLib.INITIALIZED
            : 0;
        for (uint256 i; i < players.length; ++i) _passCreditsById[players[i]] = preference;
    }
}

/// @notice Adversarial maximum search using production construction and full mineFlip calls.
/// Gas comes from physically cold isolated calls; all seeding/search/assertions are outside
/// the measured call. Run with FOUNDRY_ISOLATE=true. A search maximum is not a universal proof.
contract JackpotBattleConstructionMaximumGasTest is DeployProtocol {
    uint24 private constant CEILING = 40;
    address private constant MINER = address(0xA11CE888);
    bytes private gameCode;
    bytes private tableCode;
    uint64 private activeSlot;
    bool private isolated;
    BattlePaidMinerProbe private paidProbe;

    struct Case {
        uint256 word;
        uint16 target;
        uint8 smallQueue;
        uint8 paidMode;
        bool prefix;
        bool collide;
        bool fullBoard;
        bool depletedComps;
        bool sameWallet;
    }

    function setUp() public {
        _deployProtocol(false);
        gameCode = address(game).code;
        tableCode = type(CrapsBattle).runtimeCode;
        vm.warp(100 days + 82_620 + 1 hours);
        vm.fee(1 gwei);
        isolated = vm.envOr("FOUNDRY_ISOLATE", false);
        paidProbe = new BattlePaidMinerProbe();
    }

    function _battleWord(uint256 word) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(word, CEILING, keccak256("far-future-coin"))));
    }

    /// @dev Before the first repeated level, fill small queues with distinct wallets, then
    /// finish in one large queue. This combines unique-wallet quadratic deduplication with
    /// many cold queue words and circular wraps. Every draw uses the genuine keccak stream.
    function _lengths(Case memory c) private pure returns (uint16[99] memory lengths) {
        for (uint256 i; i < 99; ++i) lengths[i] = c.prefix ? 1 : c.smallQueue;
        if (!c.prefix) return lengths;
        uint256 word = _battleWord(c.word);
        uint256 seen;
        uint256[99] memory order;
        uint256 count;
        while (count < 99) {
            uint256 offset = uint256(keccak256(abi.encode(word, count))) % 99;
            uint256 bit = uint256(1) << offset;
            if (seen & bit != 0) break;
            order[count++] = offset;
            seen |= bit;
        }
        for (uint256 i; i < count; ++i) lengths[order[i]] = c.smallQueue;
        lengths[order[count - 1]] = 500;
    }

    function _seed(Case memory c) private {
        uint24 day = GameTimeLib.currentDayIndex();
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
        vm.etch(address(crapsBattle), type(BattleMaximumTableSeed).runtimeCode);
        BattleConstructionGameSeed gs = BattleConstructionGameSeed(address(game));
        BattleMaximumTableSeed ts = BattleMaximumTableSeed(address(crapsBattle));
        gs.seedSession(CEILING, day, c.word);
        ts.seedPaidField(day - 1);
        ts.configurePaid(day - 1, c.paidMode);
        uint16[99] memory lengths = _lengths(c);
        for (uint24 offset; offset < 99; ++offset) {
            uint32[] memory players = new uint32[](lengths[offset]);
            for (uint256 i; i < players.length; ++i) {
                uint256 identity = c.sameWallet ? 0x100000 : 0x100000 + uint256(offset) * 1000 + i;
                players[i] = uint32(c.collide ? identity << 8 : identity);
            }
            gs.seedQueue(CEILING + 1 + offset, players);
            ts.configureBoards(players, c.fullBoard);
        }
        vm.etch(address(crapsBattle), tableCode);
        // Lock reads the previous daily word through the real Game facade.
        vm.etch(address(game), gameCode);
        uint256 added = uint256(c.target) * 10_000 ether;
        uint256 pool = added * PriceLookupLib.priceForLevel(CEILING) * 200 / 1000 ether;
        vm.prank(address(game));
        JackpotBattle(address(crapsBattle)).lockJackpotBattle(day, pool, CEILING);
        (activeSlot,,,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        if (c.depletedComps) {
            bytes32 lane = bytes32(uint256(1));
            vm.store(address(coin), lane, bytes32(uint256(vm.load(address(coin), lane))
                & ~(uint256(type(uint128).max) << 8)));
        }
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
    }

    function _cool() private {
        vm.cool(address(game)); vm.cool(address(crapsBattle)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(ContractAddresses.GAME_MINER_MODULE); vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE); vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        vm.cool(ContractAddresses.JACKPOT_BATTLE);
    }

    function _intrinsic(bytes memory data) private pure returns (uint256 gas) {
        gas = 21_000;
        for (uint256 i; i < data.length; ++i) gas += data[i] == 0 ? 4 : 16;
    }

    function _worker(Case memory c, uint256 allowance, uint256 supplied)
        private returns (uint256 executionGas, bool progressed)
    {
        bytes memory data = abi.encodeCall(BattleConstructionGameSeed.runDraw, (CEILING, c.word, allowance));
        _cool();
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: supplied}(
            CEILING, c.word, allowance);
        Vm.Gas memory used = vm.lastCallGas();
        executionGas = used.gasTotalUsed - (isolated ? _intrinsic(data) : 0);
        assertEq(used.gasRefunded, 0, "construction gas must not be masked by refunds");
        progressed = result.progressed;
        assertFalse(result.done, "construction must remain separate from simulation");
    }

    function _observe(Case memory c) private returns (uint256 used) {
        _seed(c);
        bool progressed;
        vm.recordLogs();
        (used, progressed) = _worker(c, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 100_000, 5_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(progressed);
        (CrapsBattleStorage.JackpotRound memory r,, uint64 settled) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
        assertEq(r.drawnCount, c.target < 50 ? c.target : 50);
        assertEq(r.drawnUnits, r.drawnCount);
        assertEq(r.word != 0, c.target <= 50);
        assertEq(settled, 0);
        if (c.prefix) {
            uint32[] memory winners = new uint32[](r.drawnCount);
            uint256 n;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length == 0 || logs[i].topics[0]
                    != keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)")) continue;
                uint32 player = uint32(uint256(logs[i].topics[3]));
                for (uint256 j; j < n; ++j) require(winners[j] != player, "prefix must preserve unique winners");
                if (c.collide) assertEq(player & 255, 0, "all dedup fingerprints collide");
                winners[n++] = player;
            }
            assertEq(n, r.drawnCount);
        }
        emit log_named_uint("case_word", c.word);
        emit log_named_uint("case_small_queue", c.smallQueue);
        emit log_named_uint("worker_execution_gas", used);
        assertLt(used, GasBounds.JACKPOT_BATTLE_DRAW, "cold construction exceeds configured bound");
    }

    function _case(uint256 word, uint8 smallQueue) private pure returns (Case memory) {
        return Case(word, 50, smallQueue, 0, true, true, true, true, false);
    }

    function test_MaxSearchDistinctPrefixesAndQueueWidths() public {
        // Long-prefix witnesses plus the best seed for all four multiplier branches,
        // from search-jackpot-battle-gas.py, seeds 1..1,000,000.
        uint256[8] memory words = [uint256(151899), 662565, 817362, 174625, 295278, 40394, 420953, 301129];
        uint8[11] memory widths = [uint8(1), 2, 3, 4, 7, 8, 9, 15, 16, 17, 31];
        uint256 pristine = vm.snapshotState();
        uint256 maximum;
        uint256 winner;
        uint256 width;
        for (uint256 i; i < words.length; ++i) {
            for (uint256 j; j < widths.length; ++j) {
                uint256 used = _observe(_case(words[i], widths[j]));
                if (used > maximum) { maximum = used; winner = words[i]; width = widths[j]; }
                assertTrue(vm.revertToState(pristine));
            }
        }
        emit log_named_uint("search_max_worker_execution_gas", maximum);
        emit log_named_uint("search_max_word", winner);
        emit log_named_uint("search_max_queue_width", width);
    }

    function _mine(uint256 supplied) private returns (bool ok, uint256 transactionGas) {
        _cool();
        bytes memory reason;
        Vm.Gas memory used;
        (ok, used, reason) = paidProbe.run(address(game), MINER, supplied);
        transactionGas = used.gasTotalUsed + 21_064;
        if (ok) assertEq(used.gasRefunded, 0, "gross transaction measurement");
        else assertEq(bytes4(reason), MineFlipGas.InsufficientExecutionGas.selector,
            "low-gas call must refuse before work, not exhaust gas midway");
    }

    function test_MaxProductionTransactionsPayMinerAndStopBeforeSimulation() public {
        uint256[4] memory words = [uint256(151899), 662565, 817362, 40394];
        uint256 pristine = vm.snapshotState();
        uint256 largest;
        for (uint256 i; i < words.length; ++i) {
            Case memory c = _case(words[i], 2);
            c.target = 150;
            _seed(c);
            vm.etch(address(game), gameCode);
            assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.DailyPhase));
            (bool ok, uint256 used) = _mine(12_000_000);
            assertTrue(ok);
            assertLt(used, 10_000_000);
            (CrapsBattleStorage.JackpotRound memory r,, uint64 settled) =
                JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
            assertEq(r.drawnCount, 150);
            assertGt(r.word, 0);
            assertEq(settled, 0, "must stop at construction checkpoint");
            assertGt(coinflip.coinflipAmount(MINER), 0, "include actual miner reward");
            emit log_named_uint("production_word", words[i]);
            emit log_named_uint("production_transaction_gas_including_intrinsic", used);
            if (used > largest) largest = used;
            assertTrue(vm.revertToState(pristine));
        }
        emit log_named_uint("maximum_production_transaction_gas", largest);
    }

    function test_MaxPhysicalAdmissionBoundaryPreservesThenCommitsOneCheckpoint() public {
        Case memory c = _case(662565, 2);
        c.target = 150;
        _seed(c);
        vm.etch(address(game), gameCode);
        uint256 initial = vm.snapshotState();
        uint256 low = 1_000_000;
        uint256 high = 8_000_000;
        while (high - low > 1) {
            uint256 supplied = (high + low) / 2;
            (bool ok,) = _mine(supplied);
            if (ok) high = supplied;
            else low = supplied;
            assertTrue(vm.revertToState(initial));
        }
        (bool refused,) = _mine(low);
        assertFalse(refused);
        (CrapsBattleStorage.JackpotRound memory beforeRound,,) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
        assertEq(beforeRound.drawWord, 0);
        assertEq(beforeRound.drawnCount, 0);
        assertEq(coinflip.coinflipAmount(MINER), 0);
        assertTrue(vm.revertToState(initial));
        (bool accepted, uint256 used) = _mine(high);
        assertTrue(accepted);
        (CrapsBattleStorage.JackpotRound memory afterRound,,) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
        assertEq(afterRound.drawnCount, 50);
        assertEq(afterRound.word, 0, "checkpoint must leave the partial field unsealed");
        assertGt(afterRound.drawCursor, 0);
        emit log_named_uint("minimum_successful_supplied_gas", high);
        emit log_named_uint("boundary_transaction_gas_used", used);
    }

    function test_MaxProductionMinerPassBranches() public {
        uint256 pristine = vm.snapshotState();
        for (uint256 mode; mode < 5; ++mode) {
            Case memory c = _case(662565, 2);
            c.target = 150;
            _seed(c);
            uint256 packed;
            if (mode == 1) packed = uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
            if (mode >= 2) {
                uint256 passType = mode == 2 ? 1 : 3;
                uint256 end = mode == 4 ? CEILING - 2 : CEILING;
                packed = (passType << BitPackingLib.WHALE_PASS_TYPE_SHIFT)
                    | (end << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT);
            }
            BattleConstructionGameSeed(address(game)).seedMinerPass(MINER, packed);
            vm.etch(address(game), gameCode);
            (bool ok, uint256 used) = _mine(12_000_000);
            assertTrue(ok);
            assertGt(coinflip.coinflipAmount(MINER), 0);
            emit log_named_uint("miner_pass_mode", mode);
            emit log_named_uint("miner_pass_transaction_gas", used);
            assertTrue(vm.revertToState(pristine));
        }
    }

    function test_MaxSearchUniformQueues() public {
        uint8[12] memory widths = [uint8(1), 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 150];
        uint256 pristine = vm.snapshotState();
        for (uint256 j; j < widths.length; ++j) {
            Case memory c = _case(0xD1CEB00C, widths[j]);
            c.prefix = false;
            _observe(c);
            assertTrue(vm.revertToState(pristine));
        }
    }

    function test_MaxSealAndPreferenceBranches() public {
        uint256 pristine = vm.snapshotState();
        for (uint8 mode; mode < 7; ++mode) {
            Case memory c = _case(40394, 2);
            if (mode < 4) c.paidMode = mode;
            if (mode == 4) c.fullBoard = false;
            if (mode == 5) c.collide = false;
            if (mode == 6) c.depletedComps = false;
            emit log_named_uint("branch_mode", mode);
            _observe(c);
            assertTrue(vm.revertToState(pristine));
        }
    }

    function test_MaxResumedAndFinal50EntryChunks() public {
        uint16[4] memory targets = [uint16(51), 100, 150, 500];
        uint256 pristine = vm.snapshotState();
        for (uint256 t; t < targets.length; ++t) {
            Case memory c = _case(40394, 2);
            c.target = targets[t];
            _seed(c);
            for (uint256 n; n < c.target; n += 50) {
                (uint256 used, bool progressed) = _worker(c, GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL + 100_000, 5_000_000);
                assertTrue(progressed);
                emit log_named_uint("resume_target", c.target);
                emit log_named_uint("resume_prior_entries", n);
                emit log_named_uint("resume_execution_gas", used);
                assertLt(used, GasBounds.JACKPOT_BATTLE_DRAW);
            }
            (CrapsBattleStorage.JackpotRound memory r,,) =
                JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
            assertEq(r.drawnCount, c.target);
            assertGt(r.word, 0);
            assertTrue(vm.revertToState(pristine));
        }
    }
    function _round() private view returns (CrapsBattleStorage.JackpotRound memory r) {
        (r,,) = JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
    }

    function _entryHash(bytes32 previous, Vm.Log[] memory logs) private pure returns (bytes32 digest) {
        digest = previous;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0]
                == keccak256("JackpotBattleEntry(uint64,uint256,uint32,uint256,uint32)")) {
                digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
            }
        }
    }

    function _roundHash() private view returns (bytes32) {
        (CrapsBattleStorage.JackpotRound memory r, uint256 board, uint64 settled) =
            JackpotBattle(address(crapsBattle)).jackpotBattleOf(activeSlot);
        assertEq(settled, 0, "field construction must leave simulation for the next call");
        return keccak256(abi.encode(r, board, settled, vm.load(address(coin), bytes32(uint256(1)))));
    }

    function _checkpointCase(uint256 shape, uint16 target) private pure returns (Case memory c) {
        c = _case(662565, 2);
        c.target = target;
        if (shape == 1) c.collide = false;
        if (shape == 2) { c.prefix = false; c.smallQueue = 1; c.fullBoard = false; }
        if (shape == 3) { c.prefix = false; c.smallQueue = 150; c.collide = false; }
        if (shape == 4) { c.prefix = false; c.smallQueue = 1; c.sameWallet = true; }
    }

    function _drainField(uint256 schedule)
        private returns (bytes32 field, bytes32 state, uint256 totalGas, uint256 calls)
    {
        uint256[3] memory budgets = [uint256(4_100_000), 6_000_000, 12_000_000];
        vm.etch(address(game), gameCode);
        do {
            uint256 prior = _round().drawnCount;
            vm.recordLogs();
            uint256 supplied = schedule == 0 ? budgets[2] : schedule == 1 ? budgets[0] : budgets[calls % 3];
            (bool ok, uint256 used) = _mine(supplied);
            assertTrue(ok);
            field = _entryHash(field, vm.getRecordedLogs());
            totalGas += used;
            assertLt(++calls, 20, "field must finish across checkpoints");
            if (_round().word == 0) {
                assertGt(_round().drawnCount, prior, "each unfinished call must commit entrants");
                assertEq((_round().drawnCount - prior) % 50, 0, "only complete groups may persist");
            }
        } while (_round().word == 0);
        state = _roundHash();
    }

    function test_CheckpointGasSchedulesPreserveFieldsAndTerms() public {
        uint256 pristine = vm.snapshotState();
        for (uint256 t; t < 2; ++t) {
            uint16 target = t == 0 ? 150 : 500;
            for (uint256 shape; shape < 5; ++shape) {
                _seed(_checkpointCase(shape, target));
                uint256 seeded = vm.snapshotState();
                (bytes32 field, bytes32 state, uint256 highGas, uint256 highCalls) = _drainField(0);
                if (target == 150) assertEq(highCalls, 1, "enough gas must process all three groups in one call");
                assertEq(_round().drawnCount, target);
                assertGt(coinflip.coinflipAmount(MINER), 0, "include real miner compensation");
                emit log_named_uint("checkpoint_target", target);
                emit log_named_uint("checkpoint_shape", shape);
                emit log_named_uint("checkpoint_high_gas_total", highGas);
                emit log_named_uint("checkpoint_high_gas_calls", highCalls);
                for (uint256 schedule = 1; schedule <= 2; ++schedule) {
                    assertTrue(vm.revertToState(seeded));
                    (bytes32 actualField, bytes32 actualState,, uint256 calls) = _drainField(schedule);
                    assertEq(actualField, field, "entrants, IDs, order and boards must match across gas schedules");
                    assertEq(actualState, state, "cursor, sealed terms, scoreboard and fees must match");
                    if (schedule == 1) assertEq(calls, (uint256(target) + 49) / 50, "low gas must yield after each group");
                }
                assertTrue(vm.revertToState(pristine));
            }
        }
    }

    function test_CheckpointSmallAndEmptyFields() public {
        uint16[8] memory targets = [uint16(0), 1, 24, 25, 49, 50, 51, 151];
        uint256 pristine = vm.snapshotState();
        for (uint256 i; i <= targets.length; ++i) {
            Case memory c = _checkpointCase(0, i < targets.length ? targets[i] : 150);
            if (i == targets.length) { c.prefix = false; c.smallQueue = 0; }
            _seed(c);
            uint256 seeded = vm.snapshotState();
            (bytes32 field, bytes32 state,,) = _drainField(0);
            assertTrue(vm.revertToState(seeded));
            (bytes32 splitField, bytes32 splitState,,) = _drainField(1);
            assertEq(splitField, field);
            assertEq(splitState, state);
            assertTrue(vm.revertToState(pristine));
        }
    }

    function test_CheckpointKeepsPreferencesLockedUntilFieldSeals() public {
        _seed(_checkpointCase(0, 150));
        vm.etch(address(game), gameCode);
        (bool ok,) = _mine(4_100_000);
        assertTrue(ok);
        assertEq(_round().drawnCount, 50);
        assertEq(_round().word, 0);
        address locked = address(0x10000000);
        _giveWalletId(locked);
        vm.prank(locked);
        vm.expectRevert(bytes4(keccak256("BetLocked()")));
        CrapsBattle(address(crapsBattle)).setPreferredBoard(0, 0);
        assertTrue(game.rngLocked());
        (ok,) = _mine(12_000_000);
        assertTrue(ok);
        assertEq(_round().drawnCount, 150);
        assertGt(_round().word, 0);
        _roundHash();
    }

}
