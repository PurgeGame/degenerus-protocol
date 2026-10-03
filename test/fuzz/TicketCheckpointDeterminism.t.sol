// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";

contract TicketCheckpointHarness is DegenerusGameTicketModule {
    function initialize(uint24 lvl) external { level = lvl; }
    function credit(address player, uint24 lvl, uint32 scaled) external { _queueEntriesScaled(player, lvl, scaled, false); }
    function commit(uint256 word, bool future) external {
        rngWordCurrent = word < 2 ? 2 : word;
        _setRngSessionPublished(true);
        rngLockedFlag = true;
        if (future) {
            earlyTicketLevel = level + 2;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, MID_DAY_FUTURE_POOL);
        } else ticketWriteSlot = !ticketWriteSlot;
    }
    function frozenFuture(uint24 lvl) external { earlyTicketLevel = lvl; lastPurchaseDay = true; }
    function flipSlot() external { ticketWriteSlot = !ticketWriteSlot; }
    function seedBuffer(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function setSnap(uint8 shift) external { snapShift = shift; }
    function seedFoil(address buyer, uint24 lvl) external {
        uint80 owner = _registerEntryOwner(buyer, lvl);
        foilRecord[lvl & 3][buyer] = (uint256(lvl) << _FOIL_LEVEL_SHIFT) | (uint256(10_000) << _FOIL_MULT_SHIFT);
        foilQueue[_foilWriteKey()].push((uint256(owner >> OWNER_IDX_SHIFT) << 192) | (uint256(lvl) << 160) | uint160(buyer));
    }
    function terminal(uint24 drain) external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, drain == level ? 1 : 2);
        _setRngTerminal();
    }
    function nearMaximum(address player, uint24 lvl, uint32 offset, uint32 owed, uint8 rem) external {
        uint24 rk = _tqReadKey(lvl);
        uint32 pos = ticketOwnerId[player];
        uint80 packed = (uint80(pos) << OWNER_IDX_SHIFT) | (uint80(owed) << 8) | rem;
        _setEntryOwed(rk, pos, packed);
        ticketLevel = lvl;
        ticketSoloOffset = offset;
    }
    function control() external view returns (bytes32) {
        return keccak256(abi.encode(ticketCursor, ticketLevel, ticketRound, ticketSeats, ticketSoloOffset));
    }
    function offset() external view returns (uint32) { return ticketSoloOffset; }
    function frontier() external view returns (uint32, uint256) { return (ticketCursor, ticketSeats); }
    function foilState() external view returns (uint256, uint32, uint24) {
        return (foilQueue[_foilReadKey()].length, foilCursor, foilGenerationDay);
    }
    function owed(address player, uint24 lvl, bool future) external view returns (uint80) {
        return _entriesOwed(future ? _tqFarFutureKey(lvl) : _tqReadKey(lvl), player);
    }
    function digest(uint24 lvl) external view returns (bytes32 out, uint256 count) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            count += n;
            out = keccak256(abi.encode(out, t, n));
            for (uint256 i; i < n; ++i) out = keccak256(abi.encode(out, _bucketOwnerAtUnchecked(lvl, uint8(t), i)));
        }
    }
    function stream(uint24 lvl, uint256 qi, address player) external view returns (uint256) {
        return TicketEntropy.identity(_tqReadKey(lvl), lvl, qi, player);
    }
}

contract TicketCheckpointDeterminismTest is Test {
    TicketCheckpointHarness private h;
    uint256 private constant FULL = 9_000_000;
    uint256 private constant WORD = 0x12902fc2cb1a37;
    function setUp() public {
        vm.warp(10 days);
        vm.etch(ContractAddresses.GAME, address(new TicketCheckpointHarness()).code);
        h = TicketCheckpointHarness(ContractAddresses.GAME);
        h.initialize(1);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
    }
    function player(uint256 i) private pure returns (address) { return address(uint160(0x10000 + i)); }

    function finish(uint24 anchor, uint256 low, bool alternating) private returns (uint256 calls) {
        for (; calls < 600; ++calls) {
            uint256 budget = alternating && calls % 2 == 1 ? FULL : low;
            MineFlipGas.Result memory r = h.runTicketWork(anchor, budget);
            if (r.done) return calls + 1;
            // Isolated future completion intentionally leaves the daily lock to its owner.
            (uint32 cursor, uint256 seats) = h.frontier();
            if (h.owed(player(0), 3, true) == 0 && cursor == 0 && seats == 0 && anchor == 0) return calls + 1;
        }
        fail("bounded schedule must complete");
    }

    function compare(uint24 target, uint24 anchor, uint256 low, bool alternating) private {
        uint256 snap = vm.snapshotState();
        finish(anchor, FULL, false);
        (bytes32 full, uint256 count) = h.digest(target);
        bytes32 control = h.control();
        assertTrue(vm.revertToStateAndDelete(snap));
        finish(anchor, low, alternating);
        (bytes32 split, uint256 splitCount) = h.digest(target);
        assertEq(splitCount, count, "exact fractional quantity");
        assertEq(split, full, "exact ordered owner lanes across checkpoints");
        assertEq(h.control(), control, "same cleared progress and global round");
    }

    function test_soloGroupsAndFractionalTailAcrossBudgets() public {
        h.credit(player(0), 1, 300_075);
        h.commit(WORD, false);
        compare(1, 2, 1_300_000, true);
    }
    function test_largerAllowanceRunsMoreBoundedSoloChunksAndPreservesInventory() public {
        h.credit(player(0), 1, 300_075);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        finish(2, FULL, false);
        (bytes32 expected, uint256 count) = h.digest(1);
        bytes32 control = h.control();
        assertTrue(vm.revertToStateAndDelete(snap));
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        MineFlipGas.Result memory result = h.runTicketWork{gas: 30_000_000}(2, 30_000_000);
        uint256 used = beforeGas - gasleft();
        assertTrue(result.done && result.progressed);
        assertLt(used, 30_000_000, "execution fits the supplied gas");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 chunks;
        uint256 entries;
        uint256 largestBound;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0]
                != keccak256("TraitsGenerated(address,uint256,uint32)")) continue;
            (, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
            uint256 bound = GasBounds.TICKET_SOLO_BASE + uint256(take) * GasBounds.TICKET_ENTRY_MAX
                + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE;
            assertLe(bound, 30_000_000, "chunk and complete checkpoint fit the supplied allowance");
            if (bound > largestBound) largestBound = bound;
            entries += take;
            ++chunks;
        }
        assertGt(chunks, 1);
        assertLe(largestBound, 10_000_000, "every solo chunk stays within 10M");
        assertEq(entries, count);
        (bytes32 actual, uint256 actualCount) = h.digest(1);
        assertEq(actualCount, count);
        assertEq(actual, expected);
        assertEq(h.control(), control);
    }
    /// @dev The terminal swap can bring a new read queue to the level of a part-drained
    ///      cohort. Its checkpoint must not resume on that queue.
    function test_terminalSwapNeverResumesStaleCheckpointOnNewQueue() public {
        h.credit(player(0), 1, 600_075);
        h.commit(WORD, false);
        h.runTicketWork(1, 1_500_000);
        assertGt(h.offset(), 0, "fixture: solo run left part-drained");
        for (uint256 i = 1; i <= 6; ++i) h.credit(player(i), 1, 400);
        h.flipSlot();
        h.terminal(1);
        uint24 anchor = uint24(1 | (1 << 23));
        for (uint256 calls; calls < 50; ++calls) {
            MineFlipGas.Result memory r = h.runTicketWork(anchor, FULL);
            assertTrue(r.progressed || r.done, "terminal drain made no progress");
            if (r.done) return;
        }
        fail("terminal drain must finish the swapped-in queue");
    }

    function test_canonicalSeatsDustAndSurvivors() public {
        uint32[11] memory quantities = [uint32(125), 250, 375, 499, 501, 799, 850, 900, 12025, 40150, 180075];
        for (uint256 i; i < quantities.length; ++i) h.credit(player(i), 1, quantities[i]);
        h.commit(WORD, false);
        compare(1, 2, 950_000, true);
    }
    function test_fractionOnlySeatsAreCanonical() public {
        for (uint256 i; i < 73; ++i) h.credit(player(i), 1, uint32(i * 37 % 99 + 1));
        h.commit(WORD, false);
        compare(1, 2, 650_000, true);
    }
    function test_futurePoolSameStreamAcrossBudgets() public {
        for (uint256 i; i < 11; ++i) h.credit(player(i), 3, uint32(30_025 + i * 331));
        h.commit(WORD, true);
        compare(3, 0, 900_000, true);
    }
    function test_snapIsAppliedOnceAcrossSoloCheckpoints() public {
        h.credit(player(0), 1, 600_075);
        h.setSnap(3);
        h.commit(WORD, false);
        compare(1, 2, 1_300_000, true);
        (, uint256 entries) = h.digest(1);
        assertGe(entries, 750);
        assertLe(entries, 751);
    }
    function test_foilPrerequisiteCannotBeOvertakenAfterFirstPackPreparesBuffer() public {
        h.initialize(2);
        h.seedBuffer(1);
        h.credit(player(0), 3, 160_025);
        for (uint256 i; i < 20; ++i) h.seedFoil(player(i + 100), 3);
        h.commit(WORD, false);
        compare(3, 3, 2_000_000, false);
    }
    function test_nonmonotonicFoilLevelsAndOrdinaryDependencies() public {
        h.initialize(3);
        h.seedBuffer(1);
        h.seedBuffer(2);
        h.credit(player(0), 3, 80_025);
        h.credit(player(1), 4, 80_050);
        for (uint256 i; i < 14; ++i) h.seedFoil(player(i + 100), i % 2 == 0 ? 4 : 3);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        finish(4, FULL, false);
        (bytes32 a,) = h.digest(3);
        (bytes32 b,) = h.digest(4);
        assertTrue(vm.revertToStateAndDelete(snap));
        finish(4, 2_000_000, true);
        (bytes32 c,) = h.digest(3);
        (bytes32 d,) = h.digest(4);
        assertEq(a, c);
        assertEq(b, d);
    }
    function test_ordinaryFutureAndFoilShareOneCanonicalProducerOrder() public {
        h.credit(player(0), 3, 100_050); // Frozen-future domain before activation.
        h.frozenFuture(3);
        h.credit(player(1), 3, 100_025); // Ordinary domain after activation.
        h.credit(player(2), 2, 80_075);
        for (uint256 i; i < 12; ++i) h.seedFoil(player(i + 100), 2);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        finish(2, FULL, false);
        (bytes32 a,) = h.digest(2);
        (bytes32 b,) = h.digest(3);
        assertTrue(vm.revertToStateAndDelete(snap));
        finish(2, 2_000_000, true);
        (bytes32 c,) = h.digest(2);
        (bytes32 d,) = h.digest(3);
        assertEq(a, c);
        assertEq(b, d);
    }
    function test_foilHeadServicesItsExactOlderQueueBeforeParityTakeover() public {
        h.initialize(2);
        h.seedBuffer(1);
        h.credit(player(0), 1, 40_000);
        h.credit(player(1), 3, 120_025);
        for (uint256 i; i < 8; ++i) h.seedFoil(player(i + 100), 3);
        h.commit(WORD, false);
        compare(3, 3, 2_000_000, true);
        assertEq(h.owed(player(0), 1, false), 0, "parity blocker fully consumed");
    }
    function test_sufficientTransactionGasCannotChooseAnotherCheckpoint() public {
        h.credit(player(0), 1, 1_000_075);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        (bool ok, bytes memory first) = address(h).call{gas: 10_000_000}(
            abi.encodeCall(h.runTicketWork, (uint24(2), FULL))
        );
        assertTrue(ok);
        bytes32 control = h.control();
        (bytes32 inventory,) = h.digest(1);
        uint80 pending = h.owed(player(0), 1, false);
        assertTrue(vm.revertToStateAndDelete(snap));
        (ok, first) = address(h).call{gas: 20_000_000}(abi.encodeCall(h.runTicketWork, (uint24(2), FULL)));
        assertTrue(ok);
        assertEq(h.control(), control, "tx gas only must not select a different prefix");
        (bytes32 other,) = h.digest(1);
        assertEq(other, inventory);
        assertEq(h.owed(player(0), 1, false), pending);
    }
    function test_terminalContinuesSameOldWordOffset() public {
        h.initialize(0);
        h.credit(player(0), 1, 600_075);
        h.commit(WORD, false);
        h.runTicketWork(1, 1_500_000);
        assertGt(h.offset(), 0, "actual partial owner");
        uint256 snap = vm.snapshotState();
        finish(1, FULL, false);
        (bytes32 normal, uint256 count) = h.digest(1);
        assertTrue(vm.revertToStateAndDelete(snap));
        h.terminal(1);
        finish(uint24(1 | (1 << 23)), 1_500_000, true);
        (bytes32 terminal, uint256 terminalCount) = h.digest(1);
        assertEq(terminalCount, count);
        assertEq(terminal, normal, "terminal takeover must not restart surviving stream");
    }
    function test_lastGroupCanEndAtTwoTo32() public {
        h.credit(player(0), 1, 1600);
        h.commit(WORD, false);
        uint256 identity = h.stream(1, 0, player(0));
        uint256 winning;
        for (uint256 word = 2; word < 1000; ++word) {
            if (TicketEntropy.remainder(identity, word, 99)) { winning = word; break; }
        }
        // Keep the same queue half while replacing the test's synthetic entropy.
        h.commit(winning, false);
        h.commit(winning, false);
        h.nearMaximum(player(0), 1, type(uint32).max - 15, 15, 99);
        finish(2, FULL, false);
        (, uint256 count) = h.digest(1);
        assertEq(count, 16, "15 remaining wholes plus winning fraction end at 2^32");
        assertEq(h.offset(), 0);
    }
    function test_successfulLowGasCheckpointsPreserveTheEntireTranscript() public {
        h.credit(player(0), 1, 300_075);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        finish(2, FULL, false);
        (bytes32 expected, uint256 count) = h.digest(1);
        bytes32 control = h.control();
        assertTrue(vm.revertToStateAndDelete(snap));
        bool done;
        uint256 calls;
        for (; calls < 600 && !done; ++calls) {
            (bool ok, bytes memory data) = address(h).call{gas: 2_000_000}(
                abi.encodeCall(h.runTicketWork, (uint24(2), FULL))
            );
            assertTrue(ok, "low-gas transaction returns at an admitted checkpoint");
            MineFlipGas.Result memory result = abi.decode(data, (MineFlipGas.Result));
            assertTrue(result.progressed || result.done);
            done = result.done;
        }
        assertTrue(done);
        assertGt(calls, 1);
        (bytes32 actual, uint256 actualCount) = h.digest(1);
        assertEq(actualCount, count);
        assertEq(actual, expected);
        assertEq(h.control(), control);
    }
    function test_successfulLowGasFoilCheckpointsKeepProducerOrder() public {
        h.initialize(2);
        h.seedBuffer(1);
        h.credit(player(0), 3, 80_025);
        for (uint256 i; i < 12; ++i) h.seedFoil(player(i + 100), 3);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        finish(3, FULL, false);
        (bytes32 expected,) = h.digest(3);
        assertTrue(vm.revertToStateAndDelete(snap));
        bool done;
        for (uint256 calls; calls < 300 && !done; ++calls) {
            (bool ok, bytes memory data) = address(h).call{gas: 2_200_000}(
                abi.encodeCall(h.runTicketWork, (uint24(3), FULL))
            );
            assertTrue(ok, "foil checkpoint must reserve the return tail");
            MineFlipGas.Result memory result = abi.decode(data, (MineFlipGas.Result));
            assertTrue(result.progressed || result.done);
            done = result.done;
        }
        assertTrue(done);
        (bytes32 actual,) = h.digest(3);
        assertEq(actual, expected);
    }
    function testFuzz_orderedLanesIgnoreStopSchedule(uint256 word, uint16 amount, uint8 low) public {
        uint256 n = 1 + uint256(low) % 11;
        for (uint256 i; i < n; ++i) h.credit(player(i), 1, uint32(1 + uint256(amount) % 500) * 100 + uint32(i * 29 % 100));
        h.commit(word, false);
        compare(1, 2, 650_000 + uint256(low) * 10_000, true);
    }
}
