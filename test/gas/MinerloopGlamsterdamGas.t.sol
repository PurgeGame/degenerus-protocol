// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {JackpotBattleConstructionMaximumGasTest} from "./JackpotBattleConstructionMaximumGas.t.sol";
import {BattleConstructionGameSeed} from "./JackpotBattleConstructionGas.t.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsLensReader} from "../../contracts/CrapsLens.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {VaultSealChunkGasSlowRebuy, VaultSettleSeeder, VaultSettleHost} from "./VaultBafSettleGas.t.sol";

contract GlamsterdamMinerGameSeed is BattleConstructionGameSeed {
    function readSession(uint24 day) external {
        level = 1;
        dailyIdx = day;
        purchaseStartDay = day;
        rngLockedFlag = false;
        _clearRngRequest();
        _setRngComplete(false);
        _setRngSessionPublished(true);
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        humanReadComplete = true;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
        lootboxRngPacked |= uint256(1) << LR_CRAPS_PENDING_SHIFT;
    }
}

contract GlamsterdamMinerTableSeed is CrapsBattleStorage {
    /// @dev Forced scoreboard/pool witness, following CrapsFinalSeatNativeGas. The last
    /// seat still uses the real engine; all award destinations are production contracts.
    function scheduledFinal(uint32[] calldata ids) external {
        uint64 s = 801;
        uint256 best = (uint256(1) << 104) | (uint256(1_000_000_000) << 60)
            | (uint256(1_000_000_000) << 16);
        for (uint256 i; i < ids.length; ++i) _appendBetOnDay((uint256(s) << 64) | (i + 1),
            uint256(ids[i]) | _BET_HIGH_BIT, 100);
        _storeBattle(bytes32(uint256(s)), ids.length | ((ids.length - 1) << _BG_RESOLVED_SHIFT)
            | (best << _BG_BEST_SHIFT) | (uint256(1) << _BG_WINNER_SHIFT)
            | (uint256(3) << _BG_STAKE_SHIFT) | ((_BG_TERMS_FROZEN | 1) << _BG_TERM_TIER_SHIFT));
        _storeHighField(bytes32(uint256(s)), ids.length | (best << _HF_SCORE_SHIFT)
            | (uint256(2) << _HF_WINNER_SHIFT) | (uint256(100 << 9) << _HF_HOTTEST_SHIFT));
        // Both bonus lanes and a nonzero sum of window weights are necessary to
        // exercise hottest/main/high pass conversions as well as the progressive split.
        _storeBudget(100, uint256(400_000_000) | (uint256(400_000_000) << 112)
            | (uint256(6) << _BUDGET_W_SHIFT));
        _progressive = 50_000_000;
        _setBonusCursor(s, uint64(ids.length - 1));
        _setSlotIndex(s, 1);
        _rngSlotCursor[0] = 1;
        _rngSlots[0].push(s);
    }

    function replaceDaily(uint64 slot, uint32[] calldata ids, uint32[] calldata boards) external {
        for (uint256 i; i < ids.length; ++i) _storeBet((uint256(slot) << 64) | (i + 1),
            uint256(ids[i]) | _BET_HIGH_BIT | (uint256(boards[i]) << _BET_CHIPS_SHIFT));
    }
    function daily(uint32[] calldata ids) external {
        uint24 day = 3;
        _bonus = day + 1;
        _storeBudget(day, 1);
        uint64 slot = uint64(uint256(day) * 8 + 6);
        for (uint256 i; i < ids.length; ++i) {
            _appendBetOnDay((uint256(slot) << 64) | (i + 1), uint256(ids[i]) | _BET_HIGH_BIT
                | (uint256((3 << 9) | (3 << 12) | (1 << 27)) << _BET_CHIPS_SHIFT), day);
        }
        _storeBattle(bytes32(uint256(slot)), ids.length
            | ((_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT)
            | (_BG_TERMS_FROZEN << _BG_TERM_TIER_SHIFT));
        _storeHighField(bytes32(uint256(slot)), ids.length);
    }

    function fifo(uint32[] calldata ids, bool expired) external {
        _rngSlotCursor[0] = 1;
        if (expired) {
            uint64 slot = 20 * 8 + 1;
            _storeBattle(bytes32(uint256(slot)), 1);
            _rngSlots[0].push(slot);
            _setSlotIndex(slot, 1);
        }
        for (uint256 f; f < 2; ++f) {
            uint64 slot = uint64(_CUSTOM_SLOT_BASE + f + 1);
            // Legal custom terms: 300 played, 2x bankroll, 5x goal, bounty 3, high 10.
            _customBattle[slot] = 300 | (2 << 28) | (5 << 33) | (3 << 43)
                | (uint256(block.timestamp - 1) << 61) | (1 << 101) | (10 << 102);
            uint256 from = f == 0 ? 0 : ids.length - 1;
            uint256 end = f == 0 ? ids.length - 1 : ids.length;
            for (uint256 i = from; i < end; ++i) {
                _appendBetOnDay((uint256(slot) << 64) | (i - from + 1), uint256(ids[i]) | _BET_HIGH_BIT
                    | (uint256((3 << 9) | (3 << 12) | (1 << 27)) << _BET_CHIPS_SHIFT), 100);
            }
            bytes32 key = keccak256(abi.encode(BATTLE_TAG, uint48(slot), uint256(600),
                uint256(3000), uint256(300), uint256(3 | (10 << 18))));
            _storeBattle(key, end - from | (3 << _BG_STAKE_SHIFT));
            _storeHighField(key, end - from);
            _fundedCustomSlots[2 + f] = slot;
            _setSlotIndex(slot, 1);
            _rngSlots[0].push(slot);
        }
    }
}

contract MinerloopGlamsterdamSettlementGasTest is DeployProtocol, MinerloopGasProbe {
    bytes private gameCode;
    address[] private paidOwners;
    uint64 private slot;
    uint256 private constant WORD = 0xD1CEB00C;
    uint256 private constant TX_LIMIT = 1 << 24;
    uint256 private constant MINE_INTRINSIC = 21_192;
    uint256 private constant CAP = TX_LIMIT - MINE_INTRINSIC;

    function setUp() public { _deployProtocol(false); gameCode = address(game).code; }

    function _ids(uint256 n) private returns (uint32[] memory ids) {
        ids = new uint32[](n);
        for (uint256 i; i < n; ++i) ids[i] = _giveWalletId(address(uint160(0xCE0000 + i)));
    }

    function _daily(uint256 n, bool seal) private {
        _dailyWord(n, seal, WORD);
    }

    function _dailyWord(uint256 n, bool seal, uint256 word) private {
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + 3) * 1 days + 82_620 + 3600);
        uint32[] memory ids = _ids(n);
        vm.etch(address(game), type(GlamsterdamMinerGameSeed).runtimeCode);
        GlamsterdamMinerGameSeed(address(game)).seedSession(2, 4, word);
        vm.etch(address(crapsBattle), type(GlamsterdamMinerTableSeed).runtimeCode);
        GlamsterdamMinerTableSeed(address(crapsBattle)).daily(ids);
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.etch(address(game), gameCode);
        vm.prank(address(game));
        JackpotBattle(address(crapsBattle)).lockJackpotBattle(4, 1 ether, 2);
        (slot,,,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        if (seal) game.mineRun{gas: 5_000_000}(type(uint32).max);
    }

    function _fifo(uint256 n, bool expired) private {
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + 99) * 1 days + 82_620 + 3600);
        uint32[] memory ids = _ids(n);
        vm.etch(address(crapsBattle), type(GlamsterdamMinerTableSeed).runtimeCode);
        GlamsterdamMinerTableSeed(address(crapsBattle)).fifo(ids, expired);
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        RecyclingState.seedWord(address(game), 0, bytes32(WORD));
        vm.etch(address(game), type(GlamsterdamMinerGameSeed).runtimeCode);
        GlamsterdamMinerGameSeed(address(game)).readSession(100);
        vm.etch(address(game), gameCode);
        assertEq(game.rngConsumerStage_g379(), 6);
    }

    /// @dev Select the most expensive paying board in a fixed legal-board search for each
    /// distinct owner. These are committed inputs, not mocked dice/results. This makes all
    /// 32 credit-array entries live and their stake slots first-touch writes. It is a bounded
    /// adversarial search, not an exhaustive maximum over every legal board and RNG word.
    function _payingDaily(uint256 count) private {
        (CrapsBattleStorage.JackpotRound memory round,,) =
            CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        uint32[] memory selected = new uint32[](count);
        uint32[] memory boards = new uint32[](count);
        uint256 candidate;
        for (uint256 seat; seat < count; ++seat) {
            uint256 best;
            for (uint256 attempt; attempt < 32 && best == 0; ++attempt) {
                uint32 id = _giveWalletId(address(uint160(0xDF0000 + candidate++)));
                (best, boards[seat]) = this.bestPayingBoard(slot, round, uint64(seat + 1), id);
                if (best != 0) selected[seat] = id;
            }
            assertGt(best, 0, "bounded search must find a genuinely paying seat");
            paidOwners.push(address(uint160(0xDF0000 + candidate - 1)));
        }
        vm.etch(address(crapsBattle), type(GlamsterdamMinerTableSeed).runtimeCode);
        GlamsterdamMinerTableSeed(address(crapsBattle)).replaceDaily(slot, selected, boards);
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
    }

    /// @dev Separate frame avoids compiler stack pressure from inlining the board search.
    function bestPayingBoard(uint64 s, CrapsBattleStorage.JackpotRound calldata round, uint64 seat, uint32 id)
        external view returns (uint256 best, uint32 board)
    {
        uint32[9] memory choices = [uint32(0), 3, (3 << 9) | (3 << 12) | (1 << 27),
            5 << 27, (4 << 27) | (3 << 9), (5 << 27) | (2 << 24),
            (3 << 9) | (3 << 12), (3 << 6) | (3 << 15), (3 << 18) | (3 << 21)];
        for (uint256 b; b < choices.length; ++b) {
            uint256 before = gasleft();
            Craps.SlipResult memory result = crapsEngine.settleBattle(
                (uint256(s) << 64) | seat, uint256(id) | (uint256(choices[b]) << 32) | (1 << 65),
                uint256(round.bankroll) * 2 / 50, round.bankroll, uint256(round.bankroll) * 5,
                uint48(s), (uint256(round.paidCount) << 64) | seat, round.drawWord);
            uint256 used = before - gasleft();
            if (result.bankrollIn != 0 && used > best) { best = used; board = choices[b]; }
        }
    }

    function _resolve(uint64 s, uint256 budget) private returns (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory progress) {
        bytes memory returned;
        (r, returned) = _probe(address(crapsBattle), address(crapsBattle),
            abi.encodeWithSignature("resolveRngSlot_g1079(uint64,uint256)", s, budget), 100_000_000);
        progress = abi.decode(returned, (MineFlipGas.Result));
        assertTrue(progress.progressed);
    }

    function test_GlamsterdamDailyResolve32FirstTouchAndReserveWalk() public {
        _daily(101, true);
        _payingDaily(32);
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) = _resolve(slot, 99_000_000);
        assertEq(p.rewardBasis, 32);
        assertFalse(p.done);
        assertEq(CrapsLensReader.highRollerDrawOf(address(crapsBattle), slot).eligible, 32);
        assertGe(r.newSlots, 32, "all 32 credits must hit new stake slots");
        uint256 bound = 32 * (GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_CREDIT_GAS_MAX)
            + GasBounds.CRAPS_SETTLE_TAIL_GAS;
        _report("daily_32_first_touch", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
        assertLt(r.glamsterdamExec, 10_000_000);
    }

    function _dailyGap(uint256 prefix) private {
        _daily(101, true);
        _payingDaily(101);
        for (uint256 i; i < prefix; i += 32) {
            vm.prank(address(crapsBattle));
            CrapsBattle(address(crapsBattle)).resolveRngSlot_g1079(slot, 99_000_000);
        }
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) = _resolve(slot, 99_000_000);
        assertEq(p.rewardBasis, prefix == 96 ? 5 : 32);
        assertEq(p.done, prefix == 96);
        // Each measured segment includes its entire batch, cursor persistence, credit flush,
        // reserve scan and (for the last segment) finalization. It bounds every smaller seat
        // checkpoint within that segment. Parent dispatch is measured in the whole-call test.
        uint256 bound = p.rewardBasis * (GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_CREDIT_GAS_MAX)
            + GasBounds.CRAPS_SETTLE_TAIL_GAS;
        _report(string.concat("daily_gap_after_", vm.toString(prefix)), r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
        assertLt(r.osakaExec, 10_000_000);
        assertLt(r.glamsterdamExec, 10_000_000);
    }

    function test_GlamsterdamDailySecondBatchGap() public { _dailyGap(32); }
    function test_GlamsterdamDailyThirdBatchGap() public { _dailyGap(64); }
    function test_GlamsterdamDailyFinalBatchGap() public { _dailyGap(96); }

    function test_GlamsterdamPayingSingleSeatBound() public {
        _daily(101, true);
        _payingDaily(1);
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) =
            _resolve(slot, MineFlipGas.budget(0, type(uint32).max, true));
        assertEq(p.rewardBasis, 1);
        uint256 bound = GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_CREDIT_GAS_MAX
            + GasBounds.CRAPS_SETTLE_TAIL_GAS;
        _report("paying_single_seat", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
    }

    function test_GlamsterdamFinalSeatFlushFinalizeAndFifoDrain() public {
        _fifo(2, false);
        uint64 first = uint64((1 << 40) + 1);
        vm.prank(address(crapsBattle));
        CrapsBattle(address(crapsBattle)).resolveRngSlot_g1079(first, 99_000_000);
        vm.expectCall(address(game), abi.encodeCall(game.setCrapsRngPending_g1406, (uint48(0), false)), uint64(2));
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) = _resolve(first + 1, 99_000_000);
        assertTrue(p.done);
        assertEq(p.rewardBasis, 1);
        assertEq(game.rngConsumerStage_g379(), 7);
        uint256 bound = GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_CREDIT_GAS_MAX
            + GasBounds.CRAPS_SETTLE_TAIL_GAS + GasBounds.CRAPS_WORK_TAIL_GAS;
        _report("final_seat_flush_finalize_fifo_drain", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
        assertLt(r.glamsterdamExec, 10_000_000);
    }

    function test_GlamsterdamFinalSeatAllAwardsAndFifoDrain() public {
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + 99) * 1 days + 82_620 + 3600);
        uint32[] memory ids = _ids(8);
        vm.etch(address(crapsBattle), type(GlamsterdamMinerTableSeed).runtimeCode);
        GlamsterdamMinerTableSeed(address(crapsBattle)).scheduledFinal(ids);
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        RecyclingState.seedWord(address(game), 0, bytes32(WORD));
        vm.etch(address(game), type(GlamsterdamMinerGameSeed).runtimeCode);
        GlamsterdamMinerGameSeed(address(game)).readSession(100);
        vm.etch(address(game), gameCode);
        vm.prank(address(game)); coinflip.fundRecordPool(1_000_000);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        vm.prank(address(crapsBattle));
        CrapsBattle(address(crapsBattle)).resolveRngSlot_g1079(801, 99_000_000);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 splits;
        for (uint256 i; i < entries.length; ++i) if (entries[i].topics.length != 0
            && entries[i].topics[0] == keccak256("CrapsProtocolAwardSplit(bytes32,uint32,uint8,uint256,uint256)")) ++splits;
        assertEq(splits, 4, "hottest, main, high and progressive must all convert passes");
        assertTrue(vm.revertToState(snap));
        vm.deleteStateSnapshot(snap);
        vm.expectCall(address(game), abi.encodeCall(game.setCrapsRngPending_g1406, (uint48(0), false)), uint64(2));
        vm.expectCall(address(coinflip), abi.encodeWithSignature("armDiceRunRecord(uint32,uint256)", ids[0], uint256(1_000_000_000) * 10_000 / 600), uint64(2));
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) = _resolve(801, 99_000_000);
        assertTrue(p.done); assertEq(p.rewardBasis, 1);
        assertEq(game.rngConsumerStage_g379(), 7);
        assertGt(coinflip.biggestDiceRunEver(), 0);
        uint256 bound = GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_CREDIT_GAS_MAX
            + GasBounds.CRAPS_SETTLE_TAIL_GAS + GasBounds.CRAPS_WORK_TAIL_GAS;
        _report("final_seat_all_awards_fifo_drain", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
        assertLt(r.glamsterdamExec, 10_000_000);
    }

    function test_GlamsterdamReserveWinningFinalSeat() public {
        uint256 word = 1;
        // Genuine keccak-derived one-in-ten reserve outcome, not an engine mock.
        while (uint256(keccak256(abi.encode(uint256(34),
            uint256(keccak256(abi.encode(uint256(66), word))), uint256(30)))) % 10 != 0) ++word;
        _dailyWord(33, true, word);
        // This fixture targets the reserve's separate winner credit. The 32-credit
        // saturation fixture independently requires every ordinary seat to pay.
        vm.prank(address(crapsBattle));
        CrapsBattle(address(crapsBattle)).resolveRngSlot_g1079(slot, 99_000_000);
        assertGt(CrapsLensReader.highRollerReserve(address(crapsBattle)), 0);
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) = _resolve(slot, 99_000_000);
        assertTrue(p.done); assertEq(p.rewardBasis, 1);
        CrapsBattleStorage.HighRollerDraw memory draw = CrapsLensReader.highRollerDrawOf(address(crapsBattle), slot);
        assertTrue(draw.won); assertTrue(draw.resolved); assertEq(draw.eligible, 33);
        assertEq(CrapsLensReader.highRollerReserve(address(crapsBattle)), 0);
        uint256 bound = GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_CREDIT_GAS_MAX
            + GasBounds.CRAPS_SETTLE_TAIL_GAS + GasBounds.CRAPS_WORK_TAIL_GAS;
        _report("final_seat_reserve_winner_credit", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
    }

    function test_GlamsterdamLastSeatWithFull32CreditFlush() public {
        _daily(128, true);
        _payingDaily(128);
        for (uint256 i; i < 3; ++i) {
            vm.prank(address(crapsBattle));
            CrapsBattle(address(crapsBattle)).resolveRngSlot_g1079(slot, 99_000_000);
        }
        (GlamsterdamReprice.Result memory r, MineFlipGas.Result memory p) = _resolve(slot, 99_000_000);
        assertTrue(p.done); assertEq(p.rewardBasis, 32);
        assertGe(r.newSlots, 32);
        uint256 bound = GasBounds.CRAPS_SEAT_GAS_MAX + 32 * GasBounds.CRAPS_CREDIT_GAS_MAX
            + GasBounds.CRAPS_SETTLE_TAIL_GAS;
        _report("last_seat_full_32_flush_including_prior_31_seats", r, bound);
        // Stronger than the last-seat-plus-flush obligation: include all prior seat bodies.
        assertLe(r.glamsterdamExec + r.stateGas, bound);
        assertLt(r.osakaExec, 10_000_000);
        assertLt(r.glamsterdamExec, 10_000_000);
    }

    function test_GlamsterdamExpiredFifoHeadCheckpoint() public {
        _fifo(102, true);
        (GlamsterdamReprice.Result memory r, bytes memory returned) = _probe(address(crapsBattle), address(game),
            abi.encodeCall(JackpotBattle.runCrapsReadWork, (uint48(0), MineFlipGas.budget(0, type(uint32).max, true))), CAP);
        MineFlipGas.Result memory p = abi.decode(returned, (MineFlipGas.Result));
        assertTrue(p.progressed); assertFalse(p.done); assertEq(p.rewardBasis, 0);
        uint256 bound = GasBounds.CRAPS_MAINTENANCE_GAS_MAX + GasBounds.CRAPS_WORK_TAIL_GAS;
        _report("expired_fifo_head", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
    }

    function test_GlamsterdamMineRun101SeatsCap24() public {
        _daily(101, true);
        _payingDaily(101);
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), address(this), abi.encodeCall(game.mineRun, (uint32(0))), CAP);
        _report("mineRun_101_cap24", r, CAP);
        (, , uint64 cursor) = CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        assertGt(cursor, 0);
        assertLt(r.osakaExec, CAP);
        // Total is reported separately: admission must stop earlier on the repriced schedule.
        emit log_named_uint("committed_seats", cursor);
    }

    function test_GlamsterdamMineRun101AmpleGas() public {
        _daily(101, true);
        _payingDaily(101);
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), address(this),
            abi.encodeCall(game.mineRun, (uint32(0))), 100_000_000);
        _report("mineRun_101_ample", r, 100_000_000);
        (,,,bool complete) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        assertTrue(complete);
        (,,uint64 cursor) = CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        assertEq(cursor, 101);
    }

    function _battleState() private view returns (bytes32 digest) {
        (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 cursor) =
            CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        digest = keccak256(abi.encode(round, board, cursor,
            CrapsLensReader.highRollerDrawOf(address(crapsBattle), slot),
            CrapsLensReader.highRollerReserve(address(crapsBattle)), coin.crapsCompAllowance()));
        for (uint256 i; i < paidOwners.length; ++i)
            digest = keccak256(abi.encode(digest, coinflip.coinflipAmount(paidOwners[i])));
    }

    function test_GlamsterdamCap24StopsAtCheckpointAndResumesSameOutcome() public {
        _daily(256, true);
        _payingDaily(256);
        uint256 snap = vm.snapshotState();
        this.minerloopMeasured(address(game), address(this), abi.encodeCall(game.mineRun, (uint32(0))), 100_000_000);
        bytes32 expected = _battleState();
        assertTrue(vm.revertToState(snap));
        uint64 cursor;
        uint256 calls;
        bool done;
        while (!done) {
            (uint256 used,) = this.minerloopMeasured(address(game), address(this), abi.encodeCall(game.mineRun, (uint32(0))), CAP);
            (,,uint64 next) = CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
            assertGt(next, cursor, "every cap-limited call commits progress");
            assertLt(used, CAP);
            emit log_named_uint("cap24_call_osaka_exec", used);
            emit log_named_uint("cap24_checkpoint_cursor", next);
            if (calls == 0) assertLt(next, 256, "fixture must exhaust continuation gas before completing");
            cursor = next;
            (,,,done) = JackpotBattle(address(crapsBattle)).jackpotProgress();
            assertLt(++calls, 10);
        }
        assertGt(calls, 1);
        assertEq(_battleState(), expected, "cap-limited splits preserve every payout and battle result");
    }

    function test_GlamsterdamConstructionSealsAndStartsSettlement() public {
        _daily(101, false);
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), address(this),
            abi.encodeCall(game.mineRun, (uint32(0))), CAP);
        (,,uint64 cursor) = CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        assertEq(cursor, 101, "sealing call must continue into settlement");
        _report("construction_then_settlement_101", r, CAP);
        assertLt(r.glamsterdamExec, 10_000_000);
        assertLt(r.glamsterdamExec + r.stateGas, CAP);
    }

    function test_GlamsterdamFifoHopIncludingExpiryAndFinalization() public {
        _fifo(2, true);
        (GlamsterdamReprice.Result memory r, bytes memory returned) = _probe(address(crapsBattle), address(game),
            abi.encodeCall(JackpotBattle.runCrapsReadWork, (uint48(0), uint256(99_000_000))), 100_000_000);
        MineFlipGas.Result memory p = abi.decode(returned, (MineFlipGas.Result));
        assertTrue(p.done); assertTrue(p.progressed); assertEq(p.rewardBasis, 2);
        assertEq(game.rngConsumerStage_g379(), 7);
        // This intentionally includes both one-seat fields around the hops. Their full cost
        // supplies a conservative observed ceiling on the transition overhead alone.
        uint256 bound = GasBounds.CRAPS_MAINTENANCE_GAS_MAX + 2 * (GasBounds.CRAPS_SEAT_GAS_MAX
            + GasBounds.CRAPS_CREDIT_GAS_MAX + GasBounds.CRAPS_SETTLE_TAIL_GAS) + GasBounds.CRAPS_WORK_TAIL_GAS;
        _report("fifo_expiry_two_fields_and_drain", r, bound);
        assertLe(r.glamsterdamExec + r.stateGas, bound);
        assertLt(r.osakaExec, 10_000_000);
        assertLt(r.glamsterdamExec, 10_000_000);
    }

    function test_GlamsterdamMineRunThreeFieldFifoCap24() public {
        _fifo(102, true);
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), address(this), abi.encodeCall(game.mineRun, (uint32(0))), CAP);
        _report("mineRun_three_field_fifo_cap24", r, CAP);
        assertLt(r.osakaExec, CAP);
        assertEq(game.rngConsumerStage_g379(), 7, "all three FIFO fields must finish");
    }
}

/// @notice The real x0 Vault-only seal, with a maximum-carry 90-day walk and a final loss.
contract MinerloopGlamsterdamProtocolSealGasTest is VaultSealChunkGasSlowRebuy, MinerloopGasProbe {
    function test_GlamsterdamProtocol90DaySeal() public {
        assertEq(game.walletIdOf_g3120(ContractAddresses.VAULT), 1);
        assertEq(game.walletIdOf_g3120(ContractAddresses.GNRUS), 3);
        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(VaultSettleSeeder).runtimeCode);
        VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(1, latchDay, 2);
        VaultSettleSeeder(address(coinflip)).seedUnlimitedHistory(3, latchDay, 2);
        vm.etch(address(coinflip), original);
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), address(this),
            abi.encodeCall(VaultSettleHost.dailyWith, (ALLOWANCE)), CHUNK_CAP);
        assertTrue(_latched());
        assertEq(_lastClaim(ContractAddresses.VAULT), latchDay);
        assertEq(_lastClaim(ContractAddresses.GNRUS), latchDay - 90, "GNRUS waits for the closing request");
        _report("x0_seal_vault_90day_walk", r, CHUNK_CAP);
        assertLt(r.osakaExec, CHUNK_CAP);
        assertLt(r.glamsterdamExec + r.stateGas, CHUNK_CAP);
    }
}

/// @notice Reprice production construction checkpoints with the existing adversarial
/// unique-wallet/colliding-fingerprint fixture. No outcome injection or production edits.
contract MinerloopGlamsterdamConstructionGasTest is JackpotBattleConstructionMaximumGasTest {
    function measuredConstruction(uint256 word) external returns (uint256 used) {
        require(msg.sender == address(this));
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: 6_000_000}(
            40, word, MineFlipGas.budget(0, type(uint32).max, true));
        used = vm.lastCallGas().gasTotalUsed;
        assertTrue(result.progressed);
        assertFalse(result.done);
    }

    function _construction(uint256 word, uint8 width) private {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires cold isolated calls");
        _seed(Case(word, 50, width, 0, true, true, true, true, false));
        uint256 snap = vm.snapshotState();
        uint256 used = this.measuredConstruction(word);
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        this.measuredConstruction(word);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(used, acc, address(game));
        (uint64 slot,, bool started,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        (CrapsBattleStorage.JackpotRound memory round,, uint64 cursor) =
            CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        assertTrue(started, "measured checkpoint includes seal");
        assertEq(round.drawnCount, 50);
        assertEq(cursor, 0, "mandatory first construction does not inherit settlement permission");
        emit log_named_uint("word", word);
        emit log_named_uint("queue_width", width);
        emit log_named_uint("osaka_exec", used);
        emit log_named_uint("glamsterdam_exec", r.glamsterdamExec);
        emit log_named_uint("glamsterdam_state", r.stateGas);
        emit log_named_uint("new_slots", r.newSlots);
        emit log_named_uint("glamsterdam_total", r.glamsterdamExec + r.stateGas);
        emit log_named_uint("admission_bound", GasBounds.JACKPOT_BATTLE_DRAW);
        emit log_named_int("margin", int256(GasBounds.JACKPOT_BATTLE_DRAW) - int256(r.glamsterdamExec + r.stateGas));
        assertLt(used, 10_000_000, "Osaka checkpoint execution");
        assertLt(r.glamsterdamExec, 10_000_000, "Glamsterdam checkpoint execution");
        assertLe(r.glamsterdamExec + r.stateGas, GasBounds.JACKPOT_BATTLE_DRAW,
            "Glamsterdam construction exceeds its admission bound");
    }

    function test_GlamsterdamConstructionLongPrefix() public { _construction(375906, 1); }
    function test_GlamsterdamConstructionWidePrefix() public { _construction(402703, 7); }
    function test_GlamsterdamConstructionCircularPrefix() public { _construction(683165, 3); }
}
