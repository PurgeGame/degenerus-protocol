// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {ProfileModules} from "../helpers/ProfileModules.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";

import {Test, Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGamePassModule} from "../../contracts/modules/DegenerusGamePassModule.sol";
import {QueuedJackpotReference} from "../helpers/QueuedJackpotReference.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

abstract contract DirectTicketFixture is BucketSeed {
    function seed(uint256 word, uint256 tickets, uint256 holders, bool repeated, bool prepared) external {
        level = 41;
        jackpotPhaseFlag = true;
        dailyIdx = 101;
        rngRequestDay = 101;
        rngLockedFlag = true;
        // Keep zero-valued owner lanes out of the cold-write gas fixture.
        _seedWallet(address(1));
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        dailyFoilDraw[rngRequestDay & 1] = _packFoilDraw(
            JackpotBucketLib.packWinningTraits(traits), level, rngRequestDay, word);
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
            _seedWallet(player);
            deityBySymbol[i] = _seedWallet(player);
        }
    }
    function setSnap(uint8 shift, bool pending) external {
        if (pending) { snapLevel = 42; snapPendingShift = shift; }
        else snapShift = shift;
    }
    function addExistingOwed(address player, uint32 entries) external { _queueEntries(_seedWallet(player), 42, entries, true); }
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
            abi.encodeWithSelector(DegenerusGameTicketModule.runTicketWork_g1150.selector, uint24(42), allowance));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
    function state() external view returns (uint8, uint16, uint32, bool, uint8, uint256) {
        return (jackpotWork.quadrant, jackpotWork.winner, jackpotWork.directTicketRound,
            jackpotWork.directTickets, jackpotCounter, dailyTicketBudgetsPacked);
    }
    function queueLength() external view returns (uint256) { return _ticketQueueLength(_tqWriteKey(42)); }
    function owed(address player) external view returns (uint80) { return _owedOf(_tqWriteKey(42), player); }
    function ownerAt(uint32 id) external view returns (address) { return _walletKey(id); }
    function bucket(uint24 lvl, uint8 trait) external view returns (address[] memory owners) {
        owners = new address[](_bucketLength(lvl, trait));
        for (uint256 i; i < owners.length; ++i) owners[i] = _bucketOwnerAt(lvl, trait, i);
    }
    function digest(uint24 lvl) external view returns (bytes32 out, uint256 count) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            count += n;
            out = keccak256(abi.encode(out, t, n));
            for (uint256 i; i < n; ++i) out = keccak256(abi.encode(out, _bucketOwnerAt(lvl, uint8(t), i)));
        }
    }
}
contract DirectJackpotHarness is DegenerusGameJackpotModule, DirectTicketFixture {}
contract QueuedJackpotHarness is QueuedJackpotReference, DirectTicketFixture {}

contract DirectJackpotTicketsTest is Test {
    uint256 private constant FULL_WORK_ALLOWANCE = 16_000_000;
    uint256 private constant PARTITIONED_WORK_ALLOWANCE = 6_000_000;

    bytes32 private constant WIN = keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 private constant BATCH = keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    DirectJackpotHarness private h;
    QueuedJackpotHarness private queued;
    mapping(address => uint256[4]) private expected;
    bytes32 private allEvents;

    function setUp() public {
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1024);
        ProfileModules.installGame(vm);
        ProfileModules.installCraps(vm);
        h = new DirectJackpotHarness();
        queued = new QueuedJackpotHarness();
        // Worker placement follows the selected deployment profile.
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
                    topics[1] = bytes32(uint256(uint32(owners[j >> 3] >> (32 * (j & 7)))));
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
        queued.runDailyJackpotTickets(word, gasleft());
        Vm.Log[] memory referenceLogs = vm.getRecordedLogs();
        (bytes32 want, uint256 entries) = _wins(0, referenceLogs);
        vm.recordLogs();
        bool done;
        for (uint256 calls; !done && calls < 100; ++calls) {
            MineFlipGas.Result memory r = h.runDailyJackpotTickets(word, FULL_WORK_ALLOWANCE);
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
            address player = h.ownerAt(uint32(uint256(referenceLogs[i].topics[1])));
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
        (, , uint256 calls,) = _finish(PARTITIONED_WORK_ALLOWANCE);
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
        _finish(FULL_WORK_ALLOWANCE);
    }
    function test_ExistingOwedBalanceRemainsIntact() public {
        h.seed(WORD, 96, 8, true, true);
        h.addExistingOwed(address(0xBEEF), 23);
        uint80 before = h.owed(address(0xBEEF));
        _finish(FULL_WORK_ALLOWANCE);
        assertEq(h.owed(address(0xBEEF)), before);
        assertEq(h.queueLength(), 1);
        (,uint256 count) = h.digest(42);
        assertEq(count, 96 * 4);
    }
    function test_UnpreparedTargetFallsBackToQueue() public {
        h.seed(WORD, 96, 64, false, false);
        _finish(FULL_WORK_ALLOWANCE);
        assertGt(h.queueLength(), 0);
        (,uint256 count) = h.digest(42);
        assertEq(count, 0);
    }
    function testFuzz_ThanosFallsBackToQueue(bool pending) public {
        h.seed(WORD, 96, 8, true, true);
        h.setSnap(2, pending);
        _finish(FULL_WORK_ALLOWANCE);
        assertEq(h.queueLength(), 1);
        h.commit(WORD + 123);
        assertTrue(h.drain(FULL_WORK_ALLOWANCE).done);
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
            MineFlipGas.Result memory r = queued.runDailyJackpotTickets(WORD, FULL_WORK_ALLOWANCE);
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
            MineFlipGas.Result memory r = queued.drain(FULL_WORK_ALLOWANCE);
            drainGas += before - gasleft();
            done = r.done;
            ++drainCalls;
        }
        assertTrue(done);
        (,,uint256 calls,uint256 directGas) = _finish(FULL_WORK_ALLOWANCE);
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
contract DirectRoundGasHarness is DegenerusGameTicketModule, WalletSeed {
    function prepare(uint24 lvl, uint256 owners) external {
        _setTicketBufferLevel(lvl);
        traitBucketLive[lvl & 1] = type(uint256).max;
        traitBucketStale &= ~uint8(1 << (lvl & 1));
        _seedWallet(address(1));
        for (uint256 i; i < owners; ++i) (uint80(_seedWallet(address(uint160(0x10000 + i + 1)))) << OWNER_IDX_SHIFT);
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

contract DirectRoundRepricer {
    function quote(uint256 measured, VmSafe.AccountAccess[] calldata accesses, address target)
        external pure returns (GlamsterdamReprice.Result memory)
    {
        return GlamsterdamReprice.reprice(measured, accesses, target);
    }
}

/// @dev Cold cost of one full direct round (32 winners, 16 eight-lane groups).
///      Common seed: all sixteen groups common with distinct traits per quadrant, each a fresh
///      header plus a fresh word. Rare seed: five rare groups, two quadrants with both rare
///      colours (sixteen split appends each) and one with one rare group.
///      The theoretical round has two rare groups of distinct colours in every quadrant:
///      common + 8 x (rare group - common group), extrapolated from the two measurements.
contract DirectRoundGasTest is NativeGasExport {
    uint256 private constant ROUND_WINNERS = 32;
    uint256 private constant CHECKPOINT_TARGET_GAS = 10_000_000;
    uint256 private constant NO_RESERVOIR_GAS_LIMIT = 1 << 24;

    DirectRoundGasHarness private h;
    DirectRoundRepricer private repricer;
    uint24 private constant TARGET = 42;
    uint256 private constant COMMON_SEED = 1;
    uint256 private constant RARE_SEED = 2_510_510;
    uint256 private constant RARE_GROUPS = 5;
    uint256 private constant MAX_RARE_GROUPS = 8;

    function setUp() public {
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1024);
        ProfileModules.installGame(vm);
        ProfileModules.installCraps(vm);
        h = new DirectRoundGasHarness();
        repricer = new DirectRoundRepricer();
        h.prepare(TARGET, ROUND_WINNERS);
    }

    function _lanes() private pure returns (uint256[4] memory lanes) {
        for (uint256 j; j < ROUND_WINNERS; ++j) lanes[j >> 3] |= (j + 1) << (ROUND_WINNERS * (j & 7));
    }

    function _round(uint256 seed) private returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        uint256[4] memory lanes = _lanes();
        vm.cool(address(h));
        uint256 g0 = gasleft();
        h.materialize(TARGET, lanes, ROUND_WINNERS, seed);
        used = g0 - gasleft();
        assertTrue(vm.revertToStateAndDelete(snap));
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            string memory label = string.concat("direct-round-", vm.toString(seed));
            vm.serializeUint(label, "osakaFrameGas", used);
            vm.serializeUint(label, "rareGroups", seed == COMMON_SEED ? 0 : RARE_GROUPS);
            vm.serializeUint(label, "maximumRareGroups", MAX_RARE_GROUPS);
            vm.serializeUint(label, "declaredRoundBound", h.roundMax());
            this.exportNativeFixture(label, address(this), address(h), abi.encodeCall(h.materialize, (TARGET, lanes, ROUND_WINNERS, seed)));
        }
    }

    function _repricedRound(uint256 seed, uint256 measured) private returns (uint256 glam, uint256 exec) {
        uint256 snap = vm.snapshotState();
        vm.startStateDiffRecording();
        h.materialize(TARGET, _lanes(), ROUND_WINNERS, seed);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory r = repricer.quote(measured, accesses, address(h));
        glam = r.glamsterdamExec + r.stateGas;
        exec = r.glamsterdamExec;
        assertTrue(vm.revertToStateAndDelete(snap));
    }

    /// @dev Independent domain/trait decoder keeps the marginal-cost fixtures
    /// non-vacuous when protocol RNG encodings change.
    function _assertShape(uint256 seed, uint256 expectedRare, uint256 expectedDoubles) private pure {
        uint256 rare;
        uint256 doubled;
        for (uint256 q; q < 4; ++q) {
            uint256 seen;
            uint256 rareColors;
            for (uint256 group; group < 4; ++group) {
                uint256 word = uint256(keccak256(abi.encode(uint256(99), seed, group))) >> (64 * q);
                uint256 scaled = (word >> 24) & 255;
                uint256 color = scaled < 64 ? 0 : scaled < 128 ? 1 : scaled < 192 ? 2 : scaled < 224 ? 3 : scaled < 240 ? 4 : scaled < 248 ? 5 : scaled < 254 ? 6 : 7;
                uint256 trait = color * 8 + ((word >> 32) & 7);
                assertEq(seen & (uint256(1) << trait), 0, "four distinct traits in each quadrant");
                seen |= uint256(1) << trait;
                if (color >= 6) {
                    assertEq(rareColors & (uint256(1) << color), 0, "split groups have distinct rare colors");
                    rareColors |= uint256(1) << color;
                    ++rare;
                }
            }
            if (rareColors == (uint256(3) << 6)) ++doubled;
        }
        assertEq(rare, expectedRare, "priced number of rare groups");
        assertEq(doubled, expectedDoubles, "priced number of double-rare quadrants");
    }

    function test_DirectRoundColdWorstFitsItsBound() public {
        _assertShape(COMMON_SEED, 0, 0);
        _assertShape(RARE_SEED, RARE_GROUPS, 2);
        uint256 common = _round(COMMON_SEED);
        uint256 rare = _round(RARE_SEED);
        // Neither recording pass may warm the other seed's cold measurement.
        (uint256 commonGlam, uint256 commonExec) = _repricedRound(COMMON_SEED, common);
        (uint256 rareGlam, uint256 rareExec) = _repricedRound(RARE_SEED, rare);
        uint256 perRareGroup = (rare - common) / RARE_GROUPS;
        uint256 worst = common + MAX_RARE_GROUPS * perRareGroup;
        emit log_named_uint("direct round, 16 fresh common groups (realistic heavy)", common);
        emit log_named_uint("direct round, 5 rare groups over cold split buckets", rare);
        emit log_named_uint("  extra per rare group", perRareGroup);
        emit log_named_uint("direct round, theoretical 8 rare groups", worst);
        uint256 glamWorst = commonGlam + MAX_RARE_GROUPS * ((rareGlam - commonGlam) / RARE_GROUPS);
        emit log_named_uint("direct round, theoretical 8 rare groups including Glamsterdam state", glamWorst);
        uint256 glamExecWorst = commonExec + MAX_RARE_GROUPS * ((rareExec - commonExec) / RARE_GROUPS);
        emit log_named_uint("  of which Glamsterdam execution gas", glamExecWorst);
        uint256 declared = h.roundMax();
        emit log_named_uint("DIRECT_ROUND_GAS_MAX", declared);
        emit log_named_uint("direct round, 16 fresh common groups including Glamsterdam state", commonGlam);
        // Without a reservoir, state gas is paid from execution gas. The common round over a
        // never-used buffer (fresh header and word per group) is admitted; rarer fresh-slot
        // outliers up to glamWorst need a reservoir, a multiplier or a smaller call.
        assertLe(worst, declared, "the theoretical Osaka cold round fits its admission");
        assertLe(glamExecWorst, declared, "the Glamsterdam execution share fits the same admission");
        assertLe(commonGlam, declared, "the fresh common round fits without a reservoir");
        assertLe(declared, 2 * worst, "round admission stays within 2x of the Osaka worst");
        assertLe(worst, CHECKPOINT_TARGET_GAS, "direct materialization stays below the checkpoint target");
        assertLe(glamWorst, CHECKPOINT_TARGET_GAS, "the Glamsterdam round stays below the checkpoint target");
        assertLe(declared + 4 * h.groupGas() + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE,
            NO_RESERVOIR_GAS_LIMIT, "state-inclusive admission and tails fit without a reservoir");
    }
}
