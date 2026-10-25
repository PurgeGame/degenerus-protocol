// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGamePassModule} from "../../contracts/modules/DegenerusGamePassModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract TicketCheckpointHarness is DegenerusGameTicketModule, WalletSeed {
    function initialize(uint24 lvl) external { level = lvl; dailyIdx = 10; }
    function credit(address player, uint24 lvl, uint32 scaled) external { _queueEntriesScaled(_seedWallet(player), lvl, scaled); }
    function commit(uint256 word, bool future) external {
        rngWordCurrent = word < 2 ? 2 : word;
        _setRngSessionPublished(true);
        rngLockedFlag = true;
        if (future) {
            earlyTicketLevel = level + 2;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, MID_DAY_FUTURE_POOL);
        } else {
            // The daily request swaps both cohorts; foil keys follow foilWriteSlot (017ac4cdf).
            ticketWriteSlot = !ticketWriteSlot;
            foilWriteSlot = !foilWriteSlot;
            (foilWriteCount, foilReadCount) = (foilReadCount, foilWriteCount);
        }
    }
    function frozenFuture(uint24 lvl) external { earlyTicketLevel = lvl; lastPurchaseDay = true; }
    function flipSlot() external { ticketWriteSlot = !ticketWriteSlot; }
    function seedBuffer(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function setSnap(uint8 shift) external { snapShift = shift; }
    function seedFoil(address buyer, uint24 lvl) external {
        uint80 owner = (uint80(_seedWallet(buyer)) << OWNER_IDX_SHIFT);
        foilRecord[lvl & 3][_seedWallet(buyer)] = (uint256(lvl) << _FOIL_LEVEL_SHIFT) | (uint256(10_000) << _FOIL_MULT_SHIFT);
        _foilAppend(_foilWriteKey(), (uint256(owner >> OWNER_IDX_SHIFT) << 192) | (uint256(lvl) << 160));
    }
    function _foilAppend(uint24 key, uint256 pack) internal {
        uint256 i = _foilCount(key);
        uint256 s = _foilSlot(key, i);
        assembly ("memory-safe") { sstore(s, pack) }
        if (key == _foilWriteKey()) foilWriteCount = uint32(i + 1);
        else foilReadCount = uint32(i + 1);
    }
    function terminal(uint24 drain) external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, drain == level ? 1 : 2);
        _setRngTerminal();
    }
    function nearMaximum(address player, uint24 lvl, uint32 offset, uint32 owed, uint8 rem) external {
        uint24 rk = _tqReadKey(lvl);
        uint32 pos = _walletIdOf(player);
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
        return (foilReadCount, foilCursor, foilGenerationDay);
    }
    function owed(address player, uint24 lvl, bool future) external view returns (uint80) {
        return _owedOf(future ? _tqFarFutureKey(lvl) : _tqReadKey(lvl), player);
    }
    function digest(uint24 lvl) external view returns (bytes32 out, uint256 count) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            count += n;
            out = keccak256(abi.encode(out, t, n));
            for (uint256 i; i < n; ++i) out = keccak256(abi.encode(out, _bucketOwnerAt(lvl, uint8(t), i)));
        }
    }
    function idOf(address who) external view returns (uint32) { return _walletIdOf(who); }
    function stream(uint24 lvl, uint256 qi, address player) external view returns (uint256) {
        return TicketEntropy.identity(_tqReadKey(lvl), lvl, qi, _walletIdOf(player));
    }
}

contract TicketCheckpointDeterminismTest is Test {
    TicketCheckpointHarness private h;
    uint256 private constant FULL = 9_000_000;
    uint256 private constant WORD = 0x12902fc2cb1a37;
    // Independent assertions of the protocol limits (MineFlipGasBounds).
    uint256 private constant EXPECTED_TICKET_TAIL = 260_000;
    uint256 private constant EXPECTED_SOLO_BASE = 250_000;
    uint256 private constant EXPECTED_ENTRY_MAX = 150_000;
    uint256 private constant EXPECTED_SOLO_MAX_ENTRIES = 32;
    uint256 private constant EXPECTED_FOIL_CALL_MAX = 3_200_000;
    uint256 private constant ENGINE_MARGIN = 2_000;
    // The worker's own entry spend (state reads, frame) comes off the allowance before a step is admitted.
    uint256 private constant ENTRY_HEADROOM = 250_000;
    uint256 private constant ALIGNED_SOLO_ENTRIES = 16;
    /// @dev Smallest realistic plain allowance that admits one aligned 16-entry solo chunk
    ///      (a 32-entry chunk needs 2.4M more), so a split run uses 16-entry chunks against the full run's 32.
    uint256 private constant SOLO_CHUNK_ALLOWANCE = EXPECTED_SOLO_BASE + ALIGNED_SOLO_ENTRIES * EXPECTED_ENTRY_MAX
        + EXPECTED_TICKET_TAIL + ENGINE_MARGIN + ENTRY_HEADROOM;
    /// @dev Smallest realistic plain allowance that admits one foil pack (and so the solo chunk too).
    uint256 private constant FOIL_STEP_ALLOWANCE =
        EXPECTED_FOIL_CALL_MAX + EXPECTED_TICKET_TAIL + ENGINE_MARGIN + ENTRY_HEADROOM;
    uint256 private constant EXPECTED_ROUND_MAX = 5_100_000;
    uint256 private constant EXPECTED_ROUND_MIN_SEATS = 4;
    /// @dev Smallest realistic plain allowance that admits one seated round.
    uint256 private constant ROUND_ALLOWANCE =
        EXPECTED_ROUND_MAX + EXPECTED_TICKET_TAIL + ENGINE_MARGIN + ENTRY_HEADROOM;
    uint256 private constant SEAT_ONLY_ALLOWANCE = 650_000; // seats and skips only; below every round, solo and foil bound
    uint256 private lowCalls;
    uint256 private lowProgressed;
    function setUp() public {
        vm.warp(10 days);
        vm.etch(ContractAddresses.GAME, address(new TicketCheckpointHarness()).code);
        h = TicketCheckpointHarness(ContractAddresses.GAME);
        h.initialize(1);
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGamePassModule()).code);
    }
    function player(uint256 i) private pure returns (address) { return address(uint160(0x10000 + i)); }

    function finish(uint24 anchor, uint256 low, bool alternating) private returns (uint256 calls) {
        lowCalls = 0;
        lowProgressed = 0;
        for (; calls < 600; ++calls) {
            bool isLow = !(alternating && calls % 2 == 1);
            uint256 budget = isLow ? low : FULL;
            MineFlipGas.Result memory r = h.runTicketWork_g1150(anchor, budget);
            if (isLow) {
                ++lowCalls;
                if (r.progressed) ++lowProgressed;
            }
            if (r.done) return calls + 1;
            // Isolated future completion intentionally leaves the daily lock to its owner.
            (uint32 cursor, uint256 seats) = h.frontier();
            if (h.owed(player(0), 3, true) == 0 && cursor == 0 && seats == 0 && anchor == 0) return calls + 1;
        }
        fail("bounded schedule must complete");
    }

    function compare(uint24 target, uint24 anchor, uint256 low, bool alternating) private {
        uint256 snap = vm.snapshotState();
        uint256 fullCalls = finish(anchor, FULL, false);
        (bytes32 full, uint256 count) = h.digest(target);
        bytes32 control = h.control();
        assertTrue(vm.revertToStateAndDelete(snap));
        emit log_named_uint("full-allowance calls", fullCalls);
        uint256 splitCalls = finish(anchor, low, alternating);
        emit log_named_uint("split calls", splitCalls);
        emit log_named_uint("low-budget calls", lowCalls);
        emit log_named_uint("low-budget calls that progressed", lowProgressed);
        assertGt(lowProgressed, 0, "the low budget itself admits work");
        (bytes32 split, uint256 splitCount) = h.digest(target);
        assertEq(splitCount, count, "exact fractional quantity");
        assertEq(split, full, "exact ordered owner lanes across checkpoints");
        assertEq(h.control(), control, "same cleared progress and global round");
    }

    function test_soloGroupsAndFractionalTailAcrossBudgets() public {
        h.credit(player(0), 1, 300_075);
        h.commit(WORD, false);
        compare(1, 2, SOLO_CHUNK_ALLOWANCE, true);
    }
    function test_ExtremeCalibrationPreservesSeatedRoundAndNestedFoil() public {
        for (uint256 i; i < 9; ++i) h.credit(player(i), 1, uint32(4_075 + i * 100));
        h.seedFoil(player(0), 1);
        h.commit(WORD, false);
        compare(1, 2, MineFlipGas.budget(FULL, type(uint32).max, true), false);
    }
    function test_ExtremeCalibrationPreservesOrderedSoloTicketsAndFraction() public {
        h.credit(player(0), 1, 16_075);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        finish(2, FULL, false);
        (bytes32 expected, uint256 count) = h.digest(1);
        bytes32 control = h.control();
        vm.revertToStateAndDelete(snap);
        uint256 budget = MineFlipGas.budget(9_000_000, type(uint32).max, true);
        for (uint256 calls; calls < 100; ++calls) {
            MineFlipGas.Result memory result = h.runTicketWork_g1150{gas: 10_000_000}(2, budget);
            assertTrue(result.progressed || result.done, "mandatory ticket progress");
            if (result.done) {
                (bytes32 actual, uint256 actualCount) = h.digest(1);
                assertEq(actual, expected);
                assertEq(actualCount, count);
                assertEq(h.control(), control);
                assertGt(calls, 1, "calibration partitions the work");
                return;
            }
        }
        fail("conservative calls must finish");
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
        MineFlipGas.Result memory result = h.runTicketWork_g1150{gas: 30_000_000}(2, 30_000_000);
        uint256 used = beforeGas - gasleft();
        assertTrue(result.done && result.progressed);
        assertLt(used, 30_000_000, "execution fits the supplied gas");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 chunks;
        uint256 entries;
        uint256 largestBound;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0]
                != keccak256("TraitsGenerated(uint32,uint256,uint32)")) continue;
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
    function test_soloScratchReuseAcrossOwnersAndShortTails() public {
        // Fewer than four owners selects the solo path. Each owner has several
        // groups and a different final tail, so reused memory contains counters
        // from both earlier chunks of this stream and unrelated owner streams.
        h.credit(player(0), 1, 32_175);
        h.credit(player(1), 1, 17_750);
        h.credit(player(2), 1, 16_399);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        MineFlipGas.Result memory result = h.runTicketWork_g1150{gas: 30_000_000}(2, 30_000_000);
        assertTrue(result.done && result.progressed);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 chunks;
        uint256 emitted;
        uint256 owners;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].topics[0]
                != keccak256("TraitsGenerated(uint32,uint256,uint32)")) continue;
            (, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
            uint32 owner = uint32(uint256(logs[i].topics[1]));
            for (uint256 j; j < 3; ++j) if (owner == h.idOf(player(j))) owners |= 1 << j;
            assertLe(take, EXPECTED_SOLO_MAX_ENTRIES, "a solo run never exceeds the admitted maximum");
            emitted += take;
            ++chunks;
        }
        assertGe(chunks, (emitted + EXPECTED_SOLO_MAX_ENTRIES - 1) / EXPECTED_SOLO_MAX_ENTRIES,
            "scratch memory is reused within one worker invocation");
        assertGe(chunks, 21, "scratch memory is reused across 32-entry solo runs");
        assertEq(owners, 7, "all three distinct owner streams ran");
        (bytes32 expected, uint256 count) = h.digest(1);
        assertEq(count, emitted, "no stale counter creates or drops occurrences");
        assertGe(count, 661);
        assertLe(count, 664);
        bytes32 control = h.control();
        assertTrue(vm.revertToStateAndDelete(snap));
        vm.recordLogs();
        uint256 refCalls = finish(2, SOLO_CHUNK_ALLOWANCE, false);
        emit log_named_uint("fresh-frame reference calls", refCalls);
        assertGt(refCalls, 1, "reference uses fresh worker frames");
        logs = vm.getRecordedLogs();
        uint256 refChunks;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].topics[0]
                != keccak256("TraitsGenerated(uint32,uint256,uint32)")) continue;
            ++refChunks;
        }
        emit log_named_uint("single-call solo runs", chunks);
        emit log_named_uint("reference solo runs", refChunks);
        assertGt(refChunks, chunks, "reference partitions the streams into more, smaller runs");
        (bytes32 actual, uint256 actualCount) = h.digest(1);
        assertEq(actualCount, count, "same whole entries and fractional results");
        assertEq(actual, expected, "same ordered owner lanes after dirty scratch reuse");
        assertEq(h.control(), control, "caller meter and checkpoint state remain intact");
    }
    /// @dev The terminal swap can bring a new read queue to the level of a part-drained
    ///      cohort. Its checkpoint must not resume on that queue.
    function test_terminalSwapNeverResumesStaleCheckpointOnNewQueue() public {
        h.credit(player(0), 1, 600_075);
        h.commit(WORD, false);
        h.runTicketWork_g1150(1, SOLO_CHUNK_ALLOWANCE);
        assertEq(h.offset(), ALIGNED_SOLO_ENTRIES, "fixture: solo run left part-drained after one aligned chunk");
        for (uint256 i = 1; i <= 6; ++i) h.credit(player(i), 1, 400);
        h.flipSlot();
        h.terminal(1);
        uint24 anchor = uint24(1 | (1 << 23));
        for (uint256 calls; calls < 50; ++calls) {
            MineFlipGas.Result memory r = h.runTicketWork_g1150(anchor, FULL);
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
        for (uint256 i; i < 11; ++i) h.credit(player(i), 3, uint32(30_000 + i * 400));
        h.commit(WORD, true);
        compare(3, 0, 900_000, true);
    }
    function test_wholeFutureSnapAcrossBudgets() public {
        for (uint256 i; i < 11; ++i) h.credit(player(i), 3, uint32(400_000 + i * 400));
        h.setSnap(3);
        h.commit(WORD, true);
        compare(3, 0, ROUND_ALLOWANCE, true);
    }
    function testFuzz_wholeFutureSnapCheckpointParity(uint32 seed, uint8 exponent) public {
        for (uint256 i; i < 9; ++i) {
            uint32 entries = 4 * (1 + uint32((uint256(seed) + i * 7) % 32));
            h.credit(player(i), 3, entries * 100);
        }
        h.setSnap(1 + exponent % 8);
        h.commit(uint256(keccak256(abi.encode(seed))), true);
        compare(3, 0, 750_000, true);
    }
    function test_isolationDigestForWholeFuturePool() public {
        uint256 entries;
        for (uint256 i; i < 73; ++i) {
            h.credit(player(i), 3, uint32(4_000 + i * 400));
            entries += 40 + i * 4;
        }
        h.commit(WORD, true);
        compare(3, 0, ROUND_ALLOWANCE, true);
        (bytes32 result, uint256 count) = h.digest(3);
        assertEq(count, entries, "every whole credited entry is generated exactly once");
        emit log_named_bytes32("OWED8_FUTURE_DIGEST", result);
    }
    function test_snapIsAppliedOnceAcrossSoloCheckpoints() public {
        h.credit(player(0), 1, 600_075);
        h.setSnap(3);
        h.commit(WORD, false);
        compare(1, 2, SOLO_CHUNK_ALLOWANCE, true);
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
        compare(3, 3, FOIL_STEP_ALLOWANCE, false);
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
        finish(4, FOIL_STEP_ALLOWANCE, true);
        assertGt(lowProgressed, 0, "the low budget itself admits work");
        (bytes32 c,) = h.digest(3);
        (bytes32 d,) = h.digest(4);
        assertEq(a, c);
        assertEq(b, d);
    }
    function test_ordinaryFutureAndFoilShareOneCanonicalProducerOrder() public {
        h.credit(player(0), 3, 100_000); // Frozen-future domain before activation.
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
        finish(2, FOIL_STEP_ALLOWANCE, true);
        assertGt(lowProgressed, 0, "the low budget itself admits work");
        (bytes32 c,) = h.digest(2);
        (bytes32 d,) = h.digest(3);
        assertEq(a, c);
        assertEq(b, d);
    }
    function test_foilHeadServicesItsExactOlderQueueBeforeParityTakeover() public {
        h.initialize(2);
        h.seedBuffer(1);
        h.credit(player(0), 1, 40_000);
        h.credit(player(1), 2, 120_025);
        for (uint256 i; i < 8; ++i) h.seedFoil(player(i + 100), 3);
        h.commit(WORD, false);
        compare(3, 3, FOIL_STEP_ALLOWANCE, true);
        assertEq(h.owed(player(0), 1, false), 0, "parity blocker fully consumed");
    }
    function test_sufficientTransactionGasCannotChooseAnotherCheckpoint() public {
        h.credit(player(0), 1, 1_000_075);
        h.commit(WORD, false);
        uint256 snap = vm.snapshotState();
        (bool ok, bytes memory first) = address(h).call{gas: 10_000_000}(
            abi.encodeCall(h.runTicketWork_g1150, (uint24(2), FULL))
        );
        assertTrue(ok);
        bytes32 control = h.control();
        (bytes32 inventory,) = h.digest(1);
        uint80 pending = h.owed(player(0), 1, false);
        assertTrue(vm.revertToStateAndDelete(snap));
        (ok, first) = address(h).call{gas: 20_000_000}(abi.encodeCall(h.runTicketWork_g1150, (uint24(2), FULL)));
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
        h.runTicketWork_g1150(1, SOLO_CHUNK_ALLOWANCE);
        assertEq(h.offset(), ALIGNED_SOLO_ENTRIES, "actual partial owner after one aligned chunk");
        uint256 snap = vm.snapshotState();
        finish(1, FULL, false);
        (bytes32 normal, uint256 count) = h.digest(1);
        assertTrue(vm.revertToStateAndDelete(snap));
        h.terminal(1);
        finish(uint24(1 | (1 << 23)), SOLO_CHUNK_ALLOWANCE, true);
        assertGt(lowProgressed, 0, "the low budget itself admits work");
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
            (bool ok, bytes memory data) = address(h).call{gas: SOLO_CHUNK_ALLOWANCE}(
                abi.encodeCall(h.runTicketWork_g1150, (uint24(2), FULL))
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
            (bool ok, bytes memory data) = address(h).call{gas: FOIL_STEP_ALLOWANCE}(
                abi.encodeCall(h.runTicketWork_g1150, (uint24(3), FULL))
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
        // Fewer than four owners drain solo and need a whole aligned solo chunk; four or more seat.
        uint256 base = n < EXPECTED_ROUND_MIN_SEATS ? SOLO_CHUNK_ALLOWANCE : SEAT_ONLY_ALLOWANCE;
        compare(1, 2, base + uint256(low) * 10_000, true);
    }
}
