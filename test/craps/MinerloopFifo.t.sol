// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Vm} from "forge-std/Vm.sol";

contract FifoContinuationHarness is CrapsViews {
    function expiredHead(uint48 index, uint64 slot) external {
        _storeBattle(bytes32(uint256(slot)), 1);
        _rngSlots[index].push(slot);
        _setSlotIndex(slot, index + 1);
    }
    function head(uint48 index) external view returns (uint64) { return _rngCursor(index); }
}

contract MinerloopFifoTest is CrapsPins {
    FifoContinuationHarness private table;
    uint64 private first;
    uint64 private second;
    uint48 private index;

    function setUp() public {
        _installPins(); _warpToAwardGenesis();
        table = new FifoContinuationHarness();
        vm.prank(vaultOwner); table.setBattleCreator(address(this), true);
        first = table.createBattle(300, 2, 5, 3, uint40(block.timestamp + 60), true, 10);
        second = table.createBattle(300, 2, 5, 3, uint40(block.timestamp + 60), true, 10);
        for (uint256 i; i < 35; ++i) {
            vm.prank(address(uint160(0xFA0000 + i)));
            table.enterBattle(i < 33 ? first : second, 0, i % 3 == 0 ? 10 : 1);
        }
        uint64 expired = uint64(uint256(table.currentDayIndex()) * 8 + 1);
        vm.warp(block.timestamp + 35 days);
        // A scheduled field committed before a long pause precedes the still-live custom fields.
        // The fixtures publish buffer zero below; closeBattle uses the current write buffer.
        index = 0;
        _setIndex(index);
        table.expiredHead(index, expired);
        assertEq(table.closeBattle(first), index);
        assertEq(table.closeBattle(second), index);
        _setWord(index, 0xC0FFEE);
        game.setRngConsumerStage(6);
    }

    function _run(bool split) private returns (bytes32 events, uint256 calls) {
        bool done;
        uint256 basis;
        while (!done) {
            uint64 previous = table.head(index);
            vm.recordLogs();
            vm.prank(ContractAddresses.GAME);
            MineFlipGas.Result memory result = JackpotBattle(address(table)).runCrapsReadWork{
                gas: split ? 5_000_000 : 100_000_000
            }(index, split ? MineFlipGas.budget(0, type(uint32).max, true) : 99_000_000);
            assertTrue(result.progressed, "every admitted call moves");
            basis += result.rewardBasis;
            assertGe(table.head(index), previous);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) if (logs[i].emitter == address(table)) {
                events = keccak256(abi.encode(events, logs[i].topics, logs[i].data));
            }
            if (table.bonusCursorOf(second) != 0) assertEq(table.bonusCursorOf(first), 33);
            done = result.done;
            assertLt(++calls, 40);
        }
        assertEq(basis, 35, "expiry has no seat reward basis; every seat counted once");
        assertEq(table.head(index), 3);
        assertTrue(table.rngCohortComplete(index));
        vm.prank(ContractAddresses.GAME);
        MineFlipGas.Result memory again = JackpotBattle(address(table)).runCrapsReadWork(index, 99_000_000);
        assertTrue(again.done); assertFalse(again.progressed); assertEq(again.rewardBasis, 0);
    }

    function _state() private view returns (bytes32 digest) {
        digest = keccak256(abi.encode(table.battleOf(table.keyOfSlot(first)),
            table.battleOf(table.keyOfSlot(second)), table.bonusCursorOf(first), table.bonusCursorOf(second),
            table.head(index), table.progressivePool(), coinflip.totalCredited(), flip.compAccruals()));
        for (uint256 i; i < 35; ++i) digest = keccak256(abi.encode(digest,
            coinflip.staked(address(uint160(0xFA0000 + i)))));
    }

    function test_ExpiredHeadAndThreeFieldsHaveIdenticalPayoutsAcrossSchedules() public {
        // Foundry call expectations are not snapshot state: two replays must issue
        // exactly two drain callbacks in total, and each replay must drain all heads.
        vm.expectCall(ContractAddresses.GAME,
            abi.encodeWithSignature("setCrapsRngPending_g1406(uint48,bool)", index, false), uint64(2));
        uint256 committed = vm.snapshotState();
        (bytes32 eventsLarge, uint256 callsLarge) = _run(false);
        assertEq(callsLarge, 1, "ample gas crosses expiry, 32-seat boundary and field boundary");
        bytes32 expected = _state();
        assertTrue(vm.revertToState(committed));
        (bytes32 eventsSplit, uint256 callsSplit) = _run(true);
        assertEq(callsSplit, 36, "one expiry checkpoint plus 35 individual seats");
        assertEq(eventsSplit, eventsLarge);
        assertEq(_state(), expected);
    }
}
