// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {BattleConstructionGameSeed} from "./JackpotBattleConstructionGas.t.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsLensReader} from "../../contracts/CrapsLens.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract ContinuationTableSeed is CrapsBattleStorage {
    function paid(uint24 day, uint32[] calldata ids) external {
        _bonus = uint256(day) + 1;
        _storeBudget(day, 1);
        uint64 slot = uint64(uint256(day) * 8 + 6);
        _storeDayTickets(uint256(day) * 8, 0);
        uint256 high;
        for (uint256 i; i < ids.length; ++i) {
            bool isHigh = i % 3 == 0;
            if (isHigh) ++high;
            _appendBetOnDay((uint256(slot) << 64) | (i + 1),
                uint256(ids[i]) | (isHigh ? _BET_HIGH_BIT : 0), day);
        }
        _storeBattle(bytes32(uint256(slot)), ids.length
            | ((_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT)
            | (_BG_TERMS_FROZEN << _BG_TERM_TIER_SHIFT));
        _storeHighField(bytes32(uint256(slot)), high);
    }
}

/// @notice Real Game -> Miner -> Daily -> Draw -> table routing, with committed paid
/// Degenesis fields. Only fixture storage is seeded; all measured execution is production code.
contract MinerloopContinuationTest is DeployProtocol {
    bytes private gameCode;
    uint64 private slot;
    uint32[] private ids;
    uint256 private constant WORD = 0xD1CEB00C;
    bytes32 private constant START = keccak256("JackpotBattleStarted(uint64,uint24,uint256,uint256,uint256)");
    bytes32 private constant SETTLED = keccak256("CrapsBetSettled(uint256,uint32,uint256,uint256)");
    bytes32 private constant RESERVE = keccak256("HighRollerReserveDrawn(uint64,uint32,uint32,uint256,uint256)");

    function setUp() public { _deployProtocol(false); gameCode = address(game).code; }

    function _seed(uint256 seats) private {
        // Day 4 settles window day 3, whose award target is legitimately zero.
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + 3) * 1 days + 82_620 + 3600);
        for (uint256 i; i < seats; ++i) {
            address player = address(uint160(0xCA0000 + i));
            _giveWalletId(player);
            ids.push(game.walletIdOf_g3120(player));
        }
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
        BattleConstructionGameSeed(address(game)).seedSession(2, 4, WORD);
        vm.etch(address(crapsBattle), type(ContinuationTableSeed).runtimeCode);
        ContinuationTableSeed(address(crapsBattle)).paid(3, ids);
        vm.etch(address(crapsBattle), type(CrapsBattle).runtimeCode);
        vm.etch(address(game), gameCode);
        vm.prank(address(game));
        JackpotBattle(address(crapsBattle)).lockJackpotBattle(4, 1 ether, 2);
        (slot,,,) = JackpotBattle(address(crapsBattle)).jackpotProgress();
    }

    function _state() private view returns (bytes32 digest) {
        (CrapsBattleStorage.JackpotRound memory r, uint256 board, uint64 cursor) =
            CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        digest = keccak256(abi.encode(r, board, cursor,
            CrapsLensReader.highRollerReserve(address(crapsBattle)),
            CrapsLensReader.highRollerDrawOf(address(crapsBattle), slot),
            CrapsLensReader.read(address(crapsBattle), CrapsLensReader.PROGRESSIVE_SLOT),
            coin.crapsCompAllowance(), game.currentPrizePoolView(), game.nextPrizePoolView(),
            game.futurePrizePoolView(), game.claimablePoolView()));
        for (uint256 i; i < ids.length; ++i) {
            address player = address(uint160(0xCA0000 + i));
            digest = keccak256(abi.encode(digest, coinflip.coinflipAmount(player), game.claimableWinningsOf(player)));
        }
    }

    function _events(bytes32 digest, Vm.Log[] memory logs) private view returns (bytes32) {
        // Coinflip batch logs have schedule-dependent grouping. Compare the table's
        // individual settlement and payout events byte-for-byte in canonical order.
        for (uint256 i; i < logs.length; ++i) if (logs[i].emitter == address(crapsBattle)) {
            digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
        }
        return digest;
    }

    function _pending() private view returns (bool) {
        return uint256(vm.load(address(game), bytes32(GameSlots.DAILY_TICKET_BUDGETS_PACKED))) & (1 << 72) != 0;
    }

    function _drive(bool split, uint32 multiplier) private returns (bytes32 digest, uint256 calls) {
        JackpotBattle api = JackpotBattle(address(crapsBattle));
        bool complete;
        while (_pending()) {
            (CrapsBattleStorage.JackpotRound memory beforeRound,, uint64 beforeCursor) =
                CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
            vm.recordLogs();
            // Extreme calibration spends exactly the mandatory first unit. Actual gas
            // still covers construction/one atomic seat and the return/payment tail.
            game.mineRun{gas: split ? 5_000_000 : 100_000_000}(split ? type(uint32).max : multiplier);
            digest = _events(digest, vm.getRecordedLogs());
            (CrapsBattleStorage.JackpotRound memory afterRound,, uint64 afterCursor) =
                CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
            assertTrue(!beforeRound.started && afterRound.started || afterCursor > beforeCursor || !_pending(),
                "each successful mining call commits a construction or settlement unit");
            (,,,complete) = api.jackpotProgress();
            assertLt(++calls, 110);
        }
        assertTrue(complete);
        assertFalse(_pending(), "completion must clear the pending latch");
        // Completion must have cleared the pending latch: a no-gas result probe
        // against the daily draw reports done, with no repeat table payout.
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
        vm.recordLogs();
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw(2, WORD, 0);
        assertTrue(result.done);
        assertEq(vm.getRecordedLogs().length, 0);
        vm.etch(address(game), gameCode);
    }

    function test_ProductionMiningSchedulesPreserveAllBattleOutcomes() public {
        uint256[6] memory sizes = [uint256(0), 1, 32, 33, 64, 101];
        uint256 pristine = vm.snapshotState();
        for (uint256 i; i < sizes.length; ++i) {
            _seed(sizes[i]);
            uint256 committed = vm.snapshotState();
            (bytes32 eventsLarge,) = _drive(false, 0);
            bytes32 expected = _state();
            assertTrue(vm.revertToState(committed));
            (bytes32 eventsSplit, uint256 calls) = _drive(true, 0);
            assertEq(calls, sizes[i] == 0 ? 2 : sizes[i] + 1,
                "one seal then one seat per call; an empty field has a separate latch-clear unit");
            assertEq(_state(), expected, "boards/cursors/each wallet/pools/reserve differ");
            assertEq(eventsSplit, eventsLarge, "ordered table payouts differ");
            assertTrue(vm.revertToState(pristine));
        }
    }

    function test_AmpleGasSealsAndSettles64SeatsInOneTransaction() public {
        _seed(64);
        vm.recordLogs();
        game.mineRun{gas: 16_700_000}(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 starts; uint256 settlements; uint256 reserves;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics.length != 0) {
            if (logs[i].topics[0] == START) ++starts;
            if (logs[i].topics[0] == SETTLED) { assertEq(starts, 1); ++settlements; }
            if (logs[i].topics[0] == RESERVE) ++reserves;
        }
        assertEq(starts, 1); assertEq(settlements, 64); assertEq(reserves, 1);
        (,,,bool complete) = JackpotBattle(address(crapsBattle)).jackpotProgress();
        assertTrue(complete);
    }

    function test_FirstPermissionCannotLeakFromConstructionIntoSettlement() public {
        _seed(64);
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
        MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: 5_000_000}(
            2, WORD, MineFlipGas.budget(0, type(uint32).max, true));
        assertTrue(result.progressed); assertFalse(result.done); assertEq(result.rewardBasis, 1);
        (CrapsBattleStorage.JackpotRound memory r,, uint64 cursor) =
            CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
        assertTrue(r.started); assertEq(cursor, 0);
        vm.etch(address(game), gameCode);
        _drive(true, 0);
    }

    function test_MinimumAndLargeMultipliersPreserveOutcomes() public {
        _seed(33);
        uint256 committed = vm.snapshotState();
        _drive(false, 2_500);
        bytes32 expected = _state();
        assertTrue(vm.revertToState(committed));
        _drive(false, 50_000);
        assertEq(_state(), expected);
        assertTrue(vm.revertToState(committed));
        _drive(true, 0);
        assertEq(_state(), expected);
    }
    function test_MinimumMultiplierAtTightContinuationFloors() public {
        _seed(64);
        vm.etch(address(game), type(BattleConstructionGameSeed).runtimeCode);
        uint256 committed = vm.snapshotState();
        uint256[6] memory allowances = [uint256(0), 500_000, 1_000_000, 2_000_000, 4_000_000, 6_000_000];
        for (uint256 i; i < allowances.length; ++i) {
            MineFlipGas.Result memory result = BattleConstructionGameSeed(address(game)).runDraw{gas: 10_000_000}(
                2, WORD, MineFlipGas.budget(allowances[i], 2_500, true));
            assertTrue(result.progressed, "first construction unit must survive optional continuation");
            (CrapsBattleStorage.JackpotRound memory r,, uint64 cursor) =
                CrapsLensReader.jackpotBattleOf(address(crapsBattle), slot);
            assertTrue(r.started);
            if (allowances[i] == 0) assertEq(cursor, 0, "no first-unit permission reaches settlement");
            assertTrue(vm.revertToState(committed));
        }
    }

}
