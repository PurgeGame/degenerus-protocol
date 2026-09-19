// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract QueueWordCacheHarness is DegenerusGameStorage {
    function seed(uint24 key, uint24 lvl, uint256 n, uint32 ownerStart, uint256 entropy, uint8 shape) external {
        EntryOwner[] storage owners = lvlEntryOwner[lvl];
        assembly ("memory-safe") { sstore(owners.slot, ownerStart) }
        for (uint256 i; i < n; ++i) {
            uint80 bits = _registerEntryOwner(address(uint160(0x123400 + i)), lvl);
            uint32 pos = uint32(bits >> OWNER_IDX_SHIFT);
            _tqAppend(key, pos);
            uint256 random = uint256(keccak256(abi.encode(entropy, i)));
            uint32 owed = shape == 1 ? 400 : shape == 2 ? 0 : uint32(random % 65);
            uint8 rem = shape == 1 ? 0 : uint8((random >> 32) % 100);
            uint80 packed = bits | (uint80(owed) << 8) | uint80(rem);
            if (shape == 0 && i % 7 == 0) packed = 0;
            _setEntryOwed(lvl, pos, packed);
        }
    }

    function resume(uint256 seats) external { ticketSeats = seats; }

    function run(uint24 key, uint24 lvl, uint32 room, uint256 idx, uint256 total, uint256 entropy, uint8 shift)
        external returns (uint256 nextIdx, uint32 used)
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_FOILPACK_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameFoilPackModule.drainRounds.selector, key, lvl, room, idx, total, entropy, shift)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint256, uint32));
    }
}

contract QueueWordCacheTest is Test {
    QueueWordCacheHarness internal h;
    bytes internal referenceCode;
    bytes internal candidateCode;

    struct Observation {
        bytes32 writes;
        bytes32 logs;
        uint256 nextIdx;
        uint32 used;
        uint256 queueReads;
        uint256 distinctWords;
    }

    function setUp() public {
        h = new QueueWordCacheHarness();
        referenceCode = vm.parseBytes(vm.readFile("contracts/mocks/QueueWordCacheReference.hex"));
        assertEq(keccak256(referenceCode), 0x2392545ce73d2150008289f7384976ab4a3fc35164df362dae578383fcb22917, "pinned uncached reference runtime");
        candidateCode = address(new DegenerusGameFoilPackModule()).code;
    }

    function _observe(uint24 key, uint24 lvl, uint32 room, uint256 idx, uint256 n, uint256 entropy, uint8 shift)
        private returns (Observation memory o)
    {
        vm.recordLogs();
        vm.startStateDiffRecording();
        (o.nextIdx, o.used) = h.run(key, lvl, room, idx, n, entropy, shift);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        o.logs = keccak256(abi.encode(logs));
        uint256 base = uint256(keccak256(abi.encode(keccak256(abi.encode(key, uint256(12))))));
        uint256 seen;
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accesses[i].storageAccesses[j];
                assertEq(a.account, address(h), "drain writes only the caller's storage");
                if (a.isWrite) o.writes = keccak256(abi.encode(o.writes, a.slot, a.previousValue, a.newValue, a.reverted));
                else if (uint256(a.slot) >= base && uint256(a.slot) - base < (n + 7) / 8) {
                    ++o.queueReads;
                    uint256 bit = uint256(1) << (uint256(a.slot) - base);
                    if (seen & bit == 0) { ++o.distinctWords; seen |= bit; }
                }
            }
        }
    }

    function _compare(uint24 key, uint24 lvl, uint32 room, uint256 idx, uint256 n, uint256 entropy, uint8 shift)
        private returns (Observation memory beforeObs, Observation memory afterObs)
    {
        uint256 snapshot = vm.snapshotState();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, referenceCode);
        beforeObs = _observe(key, lvl, room, idx, n, entropy, shift);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, candidateCode);
        afterObs = _observe(key, lvl, room, idx, n, entropy, shift);
        assertEq(afterObs.nextIdx, beforeObs.nextIdx, "same frontier");
        assertEq(afterObs.used, beforeObs.used, "same deterministic work charge");
        assertEq(afterObs.logs, beforeObs.logs, "identical event bytes and order");
        assertEq(afterObs.writes, beforeObs.writes, "identical storage writes and order");
        assertEq(afterObs.distinctWords, beforeObs.distinctWords, "same queue words visited");
        assertEq(afterObs.queueReads, afterObs.distinctWords, "each queue word loaded exactly once per call");
    }

    function test_AlignedEightOwners_OneQueueRead() public {
        h.seed(3, 3, 8, 1 << 24, 99, 1);
        (Observation memory beforeObs, Observation memory afterObs) = _compare(3, 3, 165, 0, 8, 99, 0);
        assertEq(beforeObs.queueReads, 8);
        assertEq(afterObs.queueReads, 1);
        emit log_named_uint("UNCACHED_QUEUE_READS", beforeObs.queueReads);
        emit log_named_uint("CACHED_QUEUE_READS", afterObs.queueReads);
    }

    function test_UnalignedEightOwners_TwoQueueReads() public {
        h.seed(3, 3, 16, 0xffffff00, 99, 1);
        (Observation memory beforeObs, Observation memory afterObs) = _compare(3, 3, 165, 5, 16, 99, 0);
        assertEq(beforeObs.queueReads, 8);
        assertEq(afterObs.queueReads, 2);
    }

    function test_ScatteredResumedSeats_AndFrontier() public {
        h.seed(3, 3, 40, 0xf0000000, 99, 1);
        h.resume(uint256(1) | (uint256(8) << 32) | (uint256(18) << 64) | (uint256(24) << 96));
        _compare(3, 3, 1000, 24, 40, 99, 0);
    }

    function test_ReservedZeroLaneMatchesRevert() public {
        h.seed(3, 3, 8, 1 << 24, 99, 1);
        bytes32 base = keccak256(abi.encode(keccak256(abi.encode(uint24(3), uint256(12)))));
        vm.store(address(h), base, bytes32(0));
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, referenceCode);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.run(3, 3, 1000, 0, 8, 99, 0);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, candidateCode);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.run(3, 3, 1000, 0, 8, 99, 0);
    }

    function testFuzz_EquivalentAcrossChunks(uint256 seed, uint8 shapeSeed, uint16 budgetSeed, uint8 shiftSeed, uint8 cohort)
        public
    {
        uint256 n = 8 + seed % 41;
        uint256 idx = (seed >> 16) % 8;
        uint24 lvl = 3;
        uint24 key = lvl | uint24(uint256(cohort % 3) << 22);
        uint32 ownerStart = uint32((seed >> 32) % 0xffffff00) + 1;
        uint32 room = uint32(bound(uint256(budgetSeed), 1, 1000));
        uint8 shift = shiftSeed % 5;
        h.seed(key, lvl, n, ownerStart, seed, shapeSeed % 3);
        for (uint256 chunk; chunk < 3; ++chunk) {
            (, Observation memory o) = _compare(key, lvl, room, idx, n, seed, shift);
            idx = o.nextIdx;
        }
    }
}

abstract contract QueueWordCacheColdFixture is Test {
    QueueWordCacheHarness internal h;
    function _frontier() internal pure virtual returns (uint256);
    function _seats() internal pure virtual returns (uint256) { return 0; }
    function setUp() public {
        h = new QueueWordCacheHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        h.seed(3, 3, 64, 0xf0000000, 99, 1);
        h.resume(_seats());
    }
    function test_ColdRoundCache() public {
        uint256 idx = _frontier();
        uint256 start = gasleft();
        (uint256 nextIdx, uint32 used) = h.run(3, 3, 1000, idx, 64, 99, 0);
        uint256 consumed = start - gasleft();
        emit log_named_uint("COLD_ROUND_CACHE_GAS", consumed);
        emit log_named_uint("COLD_ROUND_CACHE_UNITS", used);
        emit log_named_uint("COLD_ROUND_CACHE_FRONTIER", nextIdx);
        assertGe(used, 800);
        assertLe(nextIdx, 64);
        assertLt(consumed, 11_000_000);
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
