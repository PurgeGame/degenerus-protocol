// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test, Vm} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {QueuedJackpotReference} from "../helpers/QueuedJackpotReference.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

abstract contract DirectTicketFixture is BucketSeed {
    function seed(uint256 word, uint256 tickets, uint256 holders, bool repeated, bool prepared) external {
        level = 41;
        jackpotPhaseFlag = true;
        dailyIdx = 100;
        rngLockedFlag = true;
        // Keep zero-valued owner lanes out of the cold-write gas fixture.
        _registerEntryOwner(address(1), 41);
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        for (uint8 q; q < 4; ++q) {
            if (repeated) _seedBucket(41, traits[q], address(0xBEEF), holders);
            else _seedBucketDistinct(41, traits[q], holders, uint160(0x10000 + uint256(q) * 0x10000));
        }
        if (prepared) _setTicketBufferLevel(42);
        dailyJackpotCoinTicketsPending = true;
        dailyTicketBudgetsPacked = 1 | ((tickets * 4) << 8);
    }
    function addDeities() external {
        // Real deity purchases always register a permanent ID in their initial grant.
        for (uint8 i; i < 32; ++i) {
            address player = address(uint160(0xD000 + i));
            _registerEntryOwner(player, 42);
            deityBySymbol[i] = player;
        }
    }
    function setSnap(uint8 shift, bool pending) external {
        if (pending) { snapLevel = 42; snapPendingShift = shift; }
        else snapShift = shift;
    }
    function addExistingOwed(address player, uint32 entries) external { _queueEntries(player, 42, entries, true); }
    function prefillTarget() external {
        for (uint256 t; t < 256; ++t) {
            // Existing partial tails exercise appending across word boundaries.
            _seedBucket(42, uint8(t), address(0xAA), t == GoldSixLib.TRAIT ? 1 : 3);
        }
    }
    function commit(uint256 word) external {
        rngWordCurrent = word;
        _setRngSessionPublished(true);
        ticketWriteSlot = !ticketWriteSlot;
    }
    function drain(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameTicketModule.runTicketWork.selector, uint24(42), allowance));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
    function state() external view returns (uint8, uint16, uint32, bool, uint8, uint256) {
        return (jackpotWork.quadrant, jackpotWork.winner, jackpotWork.directTicketRound,
            jackpotWork.directTickets, jackpotCounter, dailyTicketBudgetsPacked);
    }
    function queueLength() external view returns (uint256) { return _ticketQueueLength(_tqWriteKey(42)); }
    function owed(address player) external view returns (uint80) { return _entriesOwed(_tqWriteKey(42), player); }
    function ownerAt(uint32 idx) external view returns (address) { return _ticketOwnerAt(idx + 1); }
    function bucket(uint24 lvl, uint8 trait) external view returns (address[] memory owners) {
        owners = new address[](_bucketLength(lvl, trait));
        for (uint256 i; i < owners.length; ++i) owners[i] = _bucketOwnerAtUnchecked(lvl, trait, i);
    }
    function digest(uint24 lvl) external view returns (bytes32 out, uint256 count) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            count += n;
            out = keccak256(abi.encode(out, t, n));
            for (uint256 i; i < n; ++i) out = keccak256(abi.encode(out, _bucketOwnerAtUnchecked(lvl, uint8(t), i)));
        }
    }
}
contract DirectJackpotHarness is DegenerusGameJackpotModule, DirectTicketFixture {}
contract QueuedJackpotHarness is QueuedJackpotReference, DirectTicketFixture {}

contract DirectJackpotTicketsTest is Test {
    bytes32 private constant WIN = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 private constant BATCH = keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    DirectJackpotHarness private h;
    QueuedJackpotHarness private queued;
    mapping(address => uint256[4]) private expected;
    bytes32 private allEvents;

    function setUp() public {
        h = new DirectJackpotHarness();
        queued = new QueuedJackpotHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
    }
    function _wins(bytes32 digest, Vm.Log[] memory logs) private view returns (bytes32, uint256 entries) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == WIN) {
                digest = keccak256(abi.encode(digest, logs[i].topics, logs[i].data));
                (uint32 awarded,,,) = abi.decode(logs[i].data, (uint32,uint24,uint256,bool));
                entries += awarded;
            } else if (logs[i].topics[0] == BATCH) {
                (,uint8 count,uint32 awarded,uint256[4] memory owners,uint256[4] memory indices) =
                    abi.decode(logs[i].data, (uint16,uint8,uint32,uint256[4],uint256[4]));
                for (uint256 j; j < count; ++j) {
                    bytes32[] memory topics = new bytes32[](4);
                    topics[0] = WIN;
                    topics[1] = bytes32(uint256(uint160(h.ownerAt(uint32(owners[j >> 3] >> (32 * (j & 7)))))));
                    topics[2] = logs[i].topics[2];
                    topics[3] = logs[i].topics[3];
                    uint256 index = uint32(indices[j >> 3] >> (32 * (j & 7)));
                    if (index == type(uint32).max) index = type(uint256).max;
                    bytes memory data = abi.encode(awarded, uint24(uint256(logs[i].topics[1])), index, false);
                    digest = keccak256(abi.encode(digest, topics, data));
                    entries += awarded;
                }
            }
        }
        return (digest, entries);
    }
    function _finish(uint256 allowance) private returns (bytes32 transcript, uint256 entries, uint256 calls, uint256 used) {
        bool done;
        allEvents = 0;
        while (!done && calls < 500) {
            vm.cool(address(h));
            vm.cool(ContractAddresses.GAME_TICKET_MODULE);
            vm.recordLogs();
            uint256 before = gasleft();
            MineFlipGas.Result memory r = h.runDailyJackpotTickets{gas: allowance + 400_000}(WORD, allowance);
            used += before - gasleft();
            uint256 awarded;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            (transcript, awarded) = _wins(transcript, logs);
            for (uint256 j; j < logs.length; ++j) {
                allEvents = keccak256(abi.encode(allEvents, logs[j].topics, logs[j].data));
            }
            entries += awarded;
            assertTrue(r.progressed || r.done, "admitted work must progress");
            done = r.done;
            ++calls;
        }
        assertTrue(done, "direct leg finished");
    }
    function _compare(uint256 word, uint256 tickets, uint256 holders, bool repeated, bool deity) private {
        h.seed(word, tickets, holders, repeated, true);
        queued.seed(word, tickets, holders, repeated, true);
        if (deity) { h.addDeities(); queued.addDeities(); }
        (bytes32 sourceBefore,) = h.digest(41);
        vm.recordLogs();
        queued.payDailyJackpotCoinAndTickets(word);
        Vm.Log[] memory referenceLogs = vm.getRecordedLogs();
        (bytes32 want, uint256 entries) = _wins(0, referenceLogs);
        vm.recordLogs();
        bool done;
        for (uint256 calls; !done && calls < 100; ++calls) {
            MineFlipGas.Result memory r = h.runDailyJackpotTickets(word, 9_000_000);
            assertTrue(r.progressed || r.done);
            done = r.done;
        }
        assertTrue(done);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bytes32 got, uint256 gotEntries) = _wins(0, logs);
        assertEq(got, want, "same winners, order, source indices and awards");
        assertEq(gotEntries, entries);
        assertEq(h.queueLength(), 0, "direct winners create no queue entries");
        (bytes32 sourceAfter,) = h.digest(41);
        assertEq(sourceAfter, sourceBefore, "source bucket frozen");
        (,uint256 minted) = h.digest(42);
        assertEq(minted, entries, "whole tickets conserve all four entries");
        // Check exact ownership and one entry per quadrant per whole ticket,
        // including repeated winners, virtual entries and partial source words.
        for (uint256 i; i < referenceLogs.length; ++i) {
            if (referenceLogs[i].topics[0] != WIN) continue;
            address player = address(uint160(uint256(referenceLogs[i].topics[1])));
            (uint32 awarded,,,) = abi.decode(referenceLogs[i].data, (uint32,uint24,uint256,bool));
            for (uint8 q; q < 4; ++q) expected[player][q] += awarded / 4;
        }
        for (uint256 t; t < 256; ++t) {
            address[] memory owners = h.bucket(42, uint8(t));
            if (t == GoldSixLib.TRAIT) assertLe(owners.length, 1, "unique gold six");
            for (uint256 j; j < owners.length; ++j) {
                assertGt(expected[owners[j]][t >> 6], 0, "only funded owners receive entries");
                --expected[owners[j]][t >> 6];
            }
        }
    }
    function testFuzz_DirectOwnershipAndWinnerParity(uint256 word, uint16 budget, uint8 holders, bool repeated, bool deity) public {
        _compare(word, uint256(budget) % 501 + 1, uint256(holders) % 65 + 1, repeated, deity);
    }
    function test_PartialSourceAndVirtualDeityWords() public { _compare(WORD, 96, 9, false, true); }
    function test_TinyPrize() public { _compare(WORD, 1, 1, false, true); }
    function test_ResumptionPreservesEveryRevealAndCompletedAward() public {
        h.seed(WORD, 480, 256, false, true);
        h.prefillTarget();
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _finish(30_000_000);
        bytes32 full = allEvents;
        (bytes32 inventory, uint256 count) = h.digest(42);
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        (, , uint256 calls,) = _finish(6_500_000);
        assertGt(calls, 1);
        assertEq(allEvents, full, "all events identical across partitions");
        (bytes32 got, uint256 gotCount) = h.digest(42);
        assertEq(got, inventory);
        assertEq(gotCount, count);
        assertEq(h.bucket(42, GoldSixLib.TRAIT).length, 1);
    }
    function test_BelowRoundAllowanceDoesNotAwardOrChangeTarget() public {
        h.seed(WORD, 480, 64, false, true);
        (bytes32 before,) = h.digest(42);
        MineFlipGas.Result memory r = h.runDailyJackpotTickets(WORD, 1_500_000);
        assertTrue(r.progressed, "setup latches route");
        assertEq(r.rewardBasis, 0);
        (bytes32 afterDigest,) = h.digest(42);
        assertEq(afterDigest, before);
        r = h.runDailyJackpotTickets(WORD, 1_500_000);
        assertFalse(r.progressed);
        _finish(9_000_000);
    }
    function test_ExistingOwedBalanceRemainsIntact() public {
        h.seed(WORD, 96, 8, true, true);
        h.addExistingOwed(address(0xBEEF), 23);
        uint80 before = h.owed(address(0xBEEF));
        _finish(9_000_000);
        assertEq(h.owed(address(0xBEEF)), before);
        assertEq(h.queueLength(), 1);
        (,uint256 count) = h.digest(42);
        assertEq(count, 96 * 4);
    }
    function test_UnpreparedTargetFallsBackToQueue() public {
        h.seed(WORD, 96, 64, false, false);
        _finish(9_000_000);
        assertGt(h.queueLength(), 0);
        (,uint256 count) = h.digest(42);
        assertEq(count, 0);
    }
    function testFuzz_ThanosFallsBackToQueue(bool pending) public {
        h.seed(WORD, 96, 8, true, true);
        h.setSnap(2, pending);
        _finish(9_000_000);
        assertEq(h.queueLength(), 1);
        h.commit(WORD + 123);
        assertTrue(h.drain(9_000_000).done);
        (,uint256 count) = h.digest(42);
        assertEq(count, 96, "queue applies quarter-size scaling once");
    }

    function _benchmark(uint256 tickets, bool repeated, bool populated) private {
        h.seed(WORD, tickets, 512, repeated, true);
        queued.seed(WORD, tickets, 512, repeated, true);
        if (populated) { h.prefillTarget(); queued.prefillTarget(); }
        uint256 before;
        uint256 awardGas;
        uint256 awardCalls;
        bool awarded;
        while (!awarded && awardCalls < 50) {
            vm.cool(address(queued));
            before = gasleft();
            MineFlipGas.Result memory r = queued.runDailyJackpotTickets(WORD, 9_000_000);
            awardGas += before - gasleft();
            awarded = r.done;
            ++awardCalls;
        }
        assertTrue(awarded);
        queued.commit(WORD + 123);
        uint256 drainGas;
        bool done;
        uint256 drainCalls;
        while (!done && drainCalls < 500) {
            vm.cool(address(queued));
            vm.cool(ContractAddresses.GAME_TICKET_MODULE);
            before = gasleft();
            MineFlipGas.Result memory r = queued.drain(9_000_000);
            drainGas += before - gasleft();
            done = r.done;
            ++drainCalls;
        }
        assertTrue(done);
        (,,uint256 calls,uint256 directGas) = _finish(9_000_000);
        (,uint256 expectedCount) = queued.digest(42);
        (,uint256 directCount) = h.digest(42);
        assertEq(directCount, expectedCount);
        emit log_named_uint("tickets budget", tickets);
        emit log_named_uint("queued award gas", awardGas);
        emit log_named_uint("queued drain gas", drainGas);
        emit log_named_uint("queued total gas", awardGas + drainGas);
        emit log_named_uint("direct total gas", directGas);
        emit log_named_uint("direct calls", calls);
        emit log_named_uint("queued drain calls", drainCalls);
        emit log_named_uint("queued award calls", awardCalls);
    }
    function test_Gas_480TicketsPopulatedTarget() public { _benchmark(480, false, true); }
    function test_Gas_9600TicketsPopulatedTarget() public { _benchmark(9600, false, true); }
    function test_LargePrizeWithPassSurplus() public { _compare(WORD, 15000, 128, false, false); }
    function test_Gas_96TicketsDistinct() public { _benchmark(96, false, false); }
    function test_Gas_480TicketsDistinct() public { _benchmark(480, false, false); }
    function test_Gas_9600TicketsDistinct() public { _benchmark(9600, false, false); }
    function test_Gas_96TicketsSameOwner() public { _benchmark(96, true, false); }
    function test_Gas_480TicketsSameOwner() public { _benchmark(480, true, false); }
}

/// @dev Exposes one direct round over a target level whose common-colour headers are empty
///      (an eight-lane append writes a fresh header and a fresh word) and whose rare-colour
///      headers hold seven lanes with a zero next word (every split append completes a word).
contract DirectRoundGasHarness is DegenerusGameTicketModule {
    function prepare(uint24 lvl, uint256 owners) external {
        _setTicketBufferLevel(lvl);
        traitBucketLive[lvl & 1] = type(uint256).max;
        _registerEntryOwner(address(1), lvl);
        for (uint256 i; i < owners; ++i) _registerEntryOwner(address(uint160(0x10000 + i + 1)), lvl);
        uint256 base = _traitBufferBase(lvl);
        uint256 head = 7 | (uint256(0x00000001000000010000000100000001000000010000000100000001) << 32);
        for (uint256 t; t < 256; ++t) {
            if (((t >> 3) & 7) < ROUND_SPLIT_COLOR) continue;
            uint256 elem = base + t;
            assembly ("memory-safe") { sstore(elem, head) }
        }
    }
    function materialize(uint24 lvl, uint256[4] calldata lanes, uint256 count, uint256 seed) external {
        _materializeJackpotRound(lvl, lanes, count, seed);
    }
    function roundMax() external pure returns (uint256) { return DIRECT_ROUND_GAS_MAX; }
    function groupGas() external pure returns (uint256) { return DIRECT_GROUP_GAS; }
}

/// @dev Cold cost of one full direct round (32 winners, 16 eight-lane groups).
///      Common seed: all sixteen groups common with distinct traits per quadrant, each a fresh
///      header plus a fresh word. Rare seed: five rare groups, two quadrants with both rare
///      colours (sixteen split appends each) and one with one rare group.
///      The theoretical round has two rare groups of distinct colours in every quadrant:
///      common + 8 x (rare group - common group), extrapolated from the two measurements.
contract DirectRoundGasTest is Test {
    DirectRoundGasHarness private h;
    uint24 private constant TARGET = 42;
    uint256 private constant COMMON_SEED = 1;
    uint256 private constant RARE_SEED = 35607;
    uint256 private constant RARE_GROUPS = 5;
    uint256 private constant MAX_RARE_GROUPS = 8;

    function setUp() public {
        h = new DirectRoundGasHarness();
        h.prepare(TARGET, 32);
    }

    function _lanes() private pure returns (uint256[4] memory lanes) {
        for (uint256 j; j < 32; ++j) lanes[j >> 3] |= (j + 1) << (32 * (j & 7));
    }

    function _round(uint256 seed) private returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        uint256[4] memory lanes = _lanes();
        vm.cool(address(h));
        uint256 g0 = gasleft();
        h.materialize(TARGET, lanes, 32, seed);
        used = g0 - gasleft();
        assertTrue(vm.revertToStateAndDelete(snap));
    }

    function test_DirectRoundColdWorstFitsItsBound() public {
        uint256 common = _round(COMMON_SEED);
        uint256 rare = _round(RARE_SEED);
        uint256 perRareGroup = (rare - common) / RARE_GROUPS;
        uint256 worst = common + MAX_RARE_GROUPS * perRareGroup;
        emit log_named_uint("direct round, 16 fresh common groups (realistic heavy)", common);
        emit log_named_uint("direct round, 5 rare groups over cold split buckets", rare);
        emit log_named_uint("  extra per rare group", perRareGroup);
        emit log_named_uint("direct round, theoretical 8 rare groups", worst);
        uint256 declared = h.roundMax();
        emit log_named_uint("DIRECT_ROUND_GAS_MAX", declared);
        assertLe(worst, declared, "the theoretical cold round fits its admission");
        assertLe(declared, 2 * worst, "round admission stays within 2x of its cold worst");
        assertLe(declared + 4 * h.groupGas() + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE,
            10_000_000, "a full direct round and its tail stay within 10M");
    }
}
