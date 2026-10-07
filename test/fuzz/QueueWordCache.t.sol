// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev The round drain's queue-word cache: adjacent seats share one loaded queue word, so each
///      queue word is loaded at most once per call. The uncached differential reference
///      (contracts/mocks/QueueWordCacheReference.hex) was compiled against the pre-ring storage
///      layout (unrecycled queue keys, level-keyed trait buffers, no queue rotation, unit
///      budgets) and cannot run against current storage, so these tests check the cache against
///      an uncached oracle computed here from raw queue lanes and the canonical queue rotation.
contract QueueWordCacheHarness is DegenerusGameStorage, WalletSeed {
    uint24 private constant FAR_FUTURE_BIT = uint24(1) << 22;

    /// @dev Far-future lanes hold whole entries only (no remainder field), so far-future seeds
    ///      carry no remainder.
    function idOf(address who) external view returns (uint32) { return _walletIdOf(who); }

    function seed(uint24 key, uint24 lvl, uint256 n, uint32 ownerStart, uint256 entropy, uint8 shape) external {
        uint256[] storage owners = wallets;
        assembly ("memory-safe") { sstore(owners.slot, add(ownerStart, 1)) }
        bool farFuture = key & FAR_FUTURE_BIT != 0;
        for (uint256 i; i < n; ++i) {
            uint80 bits = (uint80(_seedWallet(address(uint160(0x123400 + i)))) << OWNER_IDX_SHIFT);
            uint32 pos = uint32(bits >> OWNER_IDX_SHIFT);
            _tqAppend(key, pos);
            uint256 random = uint256(keccak256(abi.encode(entropy, i)));
            uint32 owed = shape == 1 ? 400 : shape == 2 ? 0 : uint32(random % 65);
            uint8 rem = shape == 1 || farFuture ? 0 : uint8((random >> 32) % 100);
            uint80 packed = bits | (uint80(owed) << 8) | uint80(rem);
            if (shape == 0 && i % 7 == 0) packed = 0;
            _setEntryOwed(key, pos, packed);
        }
    }

    /// @dev Append `count` entries owing far more than any test's gas can drain after the seeded
    ///      ones, so the walk never exhausts the queue and the worker never leaves the round phase.
    function seedPadding(uint24 key, uint24 lvl, uint256 count) external {
        for (uint256 i; i < count; ++i) {
            uint80 bits = (uint80(_seedWallet(address(uint160(0x567800 + i)))) << OWNER_IDX_SHIFT);
            uint32 pos = uint32(bits >> OWNER_IDX_SHIFT);
            _tqAppend(key, pos);
            _setEntryOwed(key, pos, bits | (uint80(60_000) << 8));
        }
    }

    function resume(uint256 word) external { ticketSeats = word; }

    function seats() external view returns (uint256) { return ticketSeats; }

    function cursor() external view returns (uint256) { return ticketCursor; }

    function marker() external view returns (uint24) { return ticketLevel; }

    function round() external view returns (uint32) { return ticketRound; }

    function physicalKey(uint24 key) external pure returns (uint24) { return _ticketQueueStorageKey(key); }

    /// @dev Uncached oracle: the owner of one physical queue position, read lane by lane.
    function ownerAtPhysical(uint24 key, uint256 physical) external view returns (address) {
        return _walletKey(_tqPositionAt(ticketQueue[_ticketQueueStorageKey(key)], physical));
    }

    /// @dev Put the game in the state where the ticket worker drains `key` from logical `idx`:
    ///      `key` is the read key the worker selects (a near read key inside the mint window, or
    ///      the far-future key as the due frozen pool), `entropy` is the published read word,
    ///      `shift` the snap shift, and the checkpoint marker is `key` so the persisted cursor and
    ///      seats are resumed, not reset. Returns the anchor mineFlip passes in that state.
    function prime(uint24 key, uint24 lvl, uint256 idx, uint256 entropy, uint8 shift) external returns (uint24 anchor) {
        if (key & FAR_FUTURE_BIT != 0) {
            // The last-purchase request holds the lock: the frozen pool of lvl is due.
            level = lvl - 1;
            lastPurchaseDay = true;
            rngLockedFlag = true;
            anchor = lvl - 1;
        } else {
            level = lvl;
            ticketWriteSlot = key & TICKET_SLOT_BIT == 0;
            anchor = lvl + 1;
        }
        rngWordCurrent = entropy;
        _setRngSessionPublished(true);
        snapShift = shift;
        ticketLevel = key;
        ticketCursor = uint32(idx);
    }

    /// @dev The production ticket worker, delegatecalled as mineFlip's Tickets stage dispatches
    ///      it; the gas the call is sent bounds it.
    function run(uint24 anchor) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameTicketModule.runTicketWork.selector, anchor, gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
}

abstract contract QueueWordCacheBase is Test {
    uint256 internal constant REALISTIC_GAS = 10_000_000;
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    QueueWordCacheHarness internal h;

    struct Observation {
        uint256 nextIdx;
        uint256 gasUsed;
        uint256 queueReads;
        uint256 distinctWords;
        uint256 wordsSeen;
        Vm.Log[] logs;
    }

    function _deploy() internal {
        h = new QueueWordCacheHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
    }

    function _observe(uint24 key, uint24 lvl, uint256 idx, uint256 n, uint256 entropy, uint8 shift, uint256 gasLimit)
        internal returns (Observation memory o)
    {
        QueueWordCacheHarness hh = h;
        uint256 base = uint256(keccak256(abi.encode(keccak256(abi.encode(hh.physicalKey(key), uint256(12))))));
        uint24 anchor = hh.prime(key, lvl, idx, entropy, shift);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = hh.run{gas: gasLimit}(anchor);
        o.gasUsed = g0 - gasleft();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        o.logs = vm.getRecordedLogs();
        // The call stopped inside the round phase on this queue: its checkpoint persists, so the
        // walk's frontier is the stored cursor and no other phase read the queue.
        assertFalse(r.done, "the queue is not exhausted");
        assertEq(hh.marker(), key, "the call checkpoints on the drained queue");
        o.nextIdx = hh.cursor();
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accesses[i].storageAccesses[j];
                assertEq(a.account, address(hh), "drain writes only the caller's storage");
                if (a.isWrite || uint256(a.slot) < base || uint256(a.slot) - base >= (n + 7) / 8) continue;
                ++o.queueReads;
                uint256 bit = uint256(1) << (uint256(a.slot) - base);
                if (o.wordsSeen & bit == 0) { ++o.distinctWords; o.wordsSeen |= bit; }
            }
        }
    }

    /// @dev Uncached replay of the walk's visiting order (reloaded seats in lane order, then the
    ///      newly walked logical range, each mapped through the canonical rotation): the queue
    ///      words it touches, and the loads a one-word cache needs, one per change of word.
    function _expectedWords(uint24 key, uint256 n, uint256 entropy, uint256 seatsBefore, uint256 idx, uint256 nextIdx)
        internal pure returns (uint256 bitmap, uint256 loads)
    {
        uint256 start = TicketEntropy.queueStart(key, n, entropy);
        uint256 last = type(uint256).max;
        for (uint256 s = seatsBefore; s != 0; s >>= 32) {
            uint256 w = TicketEntropy.queueIndex((s & 0xffffffff) - 1, start, n) >> 3;
            bitmap |= uint256(1) << w;
            if (w != last) { ++loads; last = w; }
        }
        for (uint256 q = idx; q < nextIdx; ++q) {
            uint256 w = TicketEntropy.queueIndex(q, start, n) >> 3;
            bitmap |= uint256(1) << w;
            if (w != last) { ++loads; last = w; }
        }
    }

    /// @dev Every revealed seat owner is the owner at one of the call's visited positions,
    ///      looked up lane by lane without the cache.
    function _assertRevealsMatchOracle(Observation memory o, uint24 key, uint24 lvl, uint256 n, uint256 entropy,
        uint256 seatsBefore, uint256 idx) internal view returns (uint256 reveals)
    {
        uint256 start = TicketEntropy.queueStart(key, n, entropy);
        uint256 visitedCount;
        for (uint256 s = seatsBefore; s != 0; s >>= 32) ++visitedCount;
        visitedCount += o.nextIdx - idx;
        address[] memory visited = new address[](visitedCount);
        uint256 k;
        for (uint256 s = seatsBefore; s != 0; s >>= 32) {
            visited[k++] = h.ownerAtPhysical(key, TicketEntropy.queueIndex((s & 0xffffffff) - 1, start, n));
        }
        for (uint256 q = idx; q < o.nextIdx; ++q) visited[k++] = h.ownerAtPhysical(key, TicketEntropy.queueIndex(q, start, n));
        for (uint256 i; i < o.logs.length; ++i) {
            Vm.Log memory l = o.logs[i];
            // EntryTraitsRevealed is anonymous: four seat topics and one data word.
            if (l.emitter != address(h) || l.topics.length != 4 || l.data.length != 32) continue;
            ++reveals;
            for (uint256 t; t < 4; ++t) {
                uint256 topic = uint256(l.topics[t]);
                if (topic == 0) continue;
                assertEq(topic >> 160, lvl, "reveal names the drained level");
                uint32 seatId = uint32(topic);
                bool found;
                for (uint256 v; v < visited.length && !found; ++v) found = h.idOf(visited[v]) == seatId;
                assertTrue(found, "revealed seat owner matches the uncached queue lane");
            }
        }
    }

    /// @dev The cache invariants of one call. The walk visits physical positions in rotated
    ///      queue order, so it reads each word once per contiguous run of seats in it: once per
    ///      call unless the rotation wraps back into a word it already left.
    function _assertCache(Observation memory o, uint24 key, uint24 lvl, uint256 n, uint256 entropy,
        uint256 seatsBefore, uint256 idx) internal view returns (uint256 reveals)
    {
        (uint256 words, uint256 loads) = _expectedWords(key, n, entropy, seatsBefore, idx, o.nextIdx);
        assertEq(o.wordsSeen, words, "loaded exactly the words of the reloaded seats and the newly walked entries");
        assertEq(o.queueReads, loads, "a queue word is loaded only when the walk moves into a different word");
        reveals = _assertRevealsMatchOracle(o, key, lvl, n, entropy, seatsBefore, idx);
    }
}

contract QueueWordCacheTest is QueueWordCacheBase {
    function setUp() public {
        _deploy();
    }

    function test_AlignedEightOwners_OneQueueRead() public {
        h.seed(3, 3, 8, 1 << 24, 99, 1);
        Observation memory o = _observe(3, 3, 0, 8, 99, 0, REALISTIC_GAS);
        uint256 reveals = _assertCache(o, 3, 3, 8, 99, 0, 0);
        assertEq(o.nextIdx, 8, "all eight owners seated");
        assertGt(reveals, 0, "the seated owners rolled");
        // Eight lanes resolved from one load: the uncached walk loaded the word once per seat.
        assertEq(o.queueReads, 1);
        assertEq(o.distinctWords, 1);
        emit log_named_uint("CACHED_QUEUE_READS", o.queueReads);
        emit log_named_uint("SEATS_FROM_CACHED_WORD", o.nextIdx);
    }

    function test_UnalignedEightOwners_TwoQueueReads() public {
        h.seed(3, 3, 16, 0xffffff00, 99, 1);
        // Rotation start 13 of 16: logical 5..12 sit at physical 2..9, straddling two words.
        assertEq(TicketEntropy.queueStart(3, 16, 99), 13, "fixture: canonical rotation");
        Observation memory o = _observe(3, 3, 5, 16, 99, 0, REALISTIC_GAS);
        _assertCache(o, 3, 3, 16, 99, 0, 5);
        assertEq(o.nextIdx, 13, "eight seats taken from the frontier");
        assertEq(o.queueReads, 2);
        assertEq(o.distinctWords, 2, "each word loaded exactly once");
    }

    function test_ScatteredResumedSeats_AndFrontier() public {
        h.seed(3, 3, 40, 0xf0000000, 99, 1);
        uint256 resumed = uint256(1) | (uint256(8) << 32) | (uint256(18) << 64) | (uint256(24) << 96);
        h.resume(resumed);
        Observation memory o = _observe(3, 3, 24, 40, 99, 0, REALISTIC_GAS);
        _assertCache(o, 3, 3, 40, 99, resumed, 24);
        // Four resumed seats keep their queue order; four more join from the frontier.
        assertEq(o.nextIdx, 28, "frontier advances by the four free seats");
        uint256 expectedSeats = resumed | (uint256(25) << 128) | (uint256(26) << 160) | (uint256(27) << 192)
            | (uint256(28) << 224);
        assertEq(h.seats(), expectedSeats, "seats persist in canonical queue order");
        // Rotation start 6 of 40: physical 6, 13, 23, 29 (reloaded) and 30..33 (new) span 5 words.
        assertEq(o.queueReads, 5);
        assertEq(o.distinctWords, 5, "each word loaded exactly once");
    }

    /// @dev Three consecutive checkpoints of the round phase at a fuzzed gas limit (the gas
    ///      selects the checkpoint): every call keeps the cache invariants against the uncached
    ///      oracle and the frontier never regresses. Twelve never-exhausted entries follow the
    ///      fuzzed ones; at least five of them lie past the starting frontier (below 8), so the
    ///      walk never reaches the queue end with fewer than four seats and every chunk stays in
    ///      the round phase the cache belongs to (an exhausted queue hands its last seats to the
    ///      per-entry path in the same call).
    function testFuzz_EquivalentAcrossChunks(uint256 seed, uint8 shapeSeed, uint16 budgetSeed, uint8 shiftSeed, uint8 cohort)
        public
    {
        uint256 n = 8 + seed % 41;
        uint256 idx = (seed >> 16) % 8;
        uint24 lvl = 3;
        uint24 key = lvl | uint24(uint256(cohort % 3) << 22);
        uint32 ownerStart = uint32((seed >> 32) % 0xffffff00) + 1;
        uint256 gasLimit = bound(uint256(budgetSeed), 1_000_000, REALISTIC_GAS);
        uint8 shift = shiftSeed % 5;
        // A published read word is never 0 or the waiting sentinel 1.
        uint256 entropy = seed < 2 ? seed + 2 : seed;
        h.seed(key, lvl, n, ownerStart, seed, shapeSeed % 3);
        h.seedPadding(key, lvl, 12);
        n += 12;
        for (uint256 chunk; chunk < 3; ++chunk) {
            uint256 seatsBefore = h.seats();
            Observation memory o = _observe(key, lvl, idx, n, entropy, shift, gasLimit);
            _assertCache(o, key, lvl, n, entropy, seatsBefore, idx);
            assertGe(o.nextIdx, idx, "frontier never regresses");
            assertLe(o.nextIdx, n, "frontier stays inside the queue");
            idx = o.nextIdx;
        }
    }
}

/// @dev Cold round-phase calls with the cache. The worker spends what it is given, so each call
///      is driven with a realistic 10M and, separately, the 16.7M EIP-7825 cap: it must not run
///      out of gas, must complete at least one round and must stop on the supplied gas with live
///      seats. One round's admission bound is measured per shape in RoundDrainChunkGas.
abstract contract QueueWordCacheColdFixture is QueueWordCacheBase {
    function _frontier() internal pure virtual returns (uint256);
    function _seats() internal pure virtual returns (uint256) { return 0; }
    function setUp() public {
        _deploy();
        h.seed(3, 3, 64, 0xf0000000, 99, 1);
        h.resume(_seats());
    }

    function _coldRun(uint256 gasLimit, string memory tag) internal {
        uint256 idx = _frontier();
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
        uint256 seatsBefore = h.seats();
        uint32 roundBefore = h.round();
        Observation memory o = _observe(3, 3, idx, 64, 99, 0, gasLimit);
        uint256 rounds = h.round() - roundBefore;
        emit log_named_uint(string.concat(tag, "_GAS"), o.gasUsed);
        emit log_named_uint(string.concat(tag, "_ROUNDS"), rounds);
        emit log_named_uint(string.concat(tag, "_FRONTIER"), o.nextIdx);
        emit log_named_uint(string.concat(tag, "_QUEUE_READS"), o.queueReads);
        _assertCache(o, 3, 3, 64, 99, seatsBefore, idx);
        // These seats never wrap the rotation back into a word already left.
        assertEq(o.queueReads, o.distinctWords, "each queue word loaded exactly once per call");
        assertGe(rounds, 1, "the cold call completes at least one round");
        assertLe(o.nextIdx, 64);
        assertTrue(h.seats() != 0, "the supplied gas, not the seats' entries, ends the call");
    }

    function test_ColdRoundCache() public {
        uint256 snap = vm.snapshotState();
        _coldRun(REALISTIC_GAS, "COLD_ROUND_CACHE");
        assertTrue(vm.revertToState(snap));
        _coldRun(EIP7825_TX_GAS_CAP, "COLD_ROUND_CACHE_16P7M");
        assertTrue(vm.revertToStateAndDelete(snap));
    }
}

contract QueueWordCacheColdAligned is QueueWordCacheColdFixture {
    function _frontier() internal pure override returns (uint256) { return 0; }
}
contract QueueWordCacheColdUnaligned is QueueWordCacheColdFixture {
    function _frontier() internal pure override returns (uint256) { return 5; }
}
contract QueueWordCacheColdScattered is QueueWordCacheColdFixture {
    function _frontier() internal pure override returns (uint256) { return 64; }
    function _seats() internal pure override returns (uint256 word) {
        for (uint256 i; i < 8; ++i) word |= (8 * i + 1) << (32 * i);
    }
}
