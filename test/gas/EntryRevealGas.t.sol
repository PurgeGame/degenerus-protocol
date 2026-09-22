// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract EntryRevealHarness is DegenerusGameStorage {
    function seed(uint32[] memory amounts, uint8 rem, uint256 ownerStart) external {
        EntryOwner[] storage owners = lvlEntryOwner[7];
        assembly ("memory-safe") { sstore(owners.slot, ownerStart) }
        for (uint256 i; i < amounts.length; ++i) {
            uint80 bits = _registerEntryOwner(address(uint160(0x123400 + i)), 7);
            uint32 pos = uint32(bits >> OWNER_IDX_SHIFT);
            _tqAppend(7, pos);
            _setEntryOwed(7, pos, bits | (uint80(amounts[i]) << 8) | rem);
        }
    }

    function owner(uint32 idx) external view returns (address) { return lvlEntryOwner[7][idx].owner; }

    function run(uint32 room, uint256 entropy) external returns (uint256 frontier, uint32 used) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_FOILPACK_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameFoilPackModule.drainRounds.selector,
                uint24(7), uint24(7), room, uint256(0), ticketQueue[7].length, entropy, uint8(0))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint256, uint32));
    }
}

/// @notice Measures only drain execution, from identical state, against the pinned pre-reveal
///         runtime. The large room isolates event cost from deliberately changed chunk limits;
///         production-budget gas is checked separately by RoundDrainChunkGas.
contract EntryRevealGas is Test {
    bytes32 private constant OLD_EVENT = keccak256("RoundTraitsGenerated(uint24,uint32,uint256,uint32,uint256)");
    EntryRevealHarness private h;
    bytes private beforeCode;
    bytes private afterCode;

    struct Observation { uint256 gasUsed; bytes32 writes; uint256 inventory; uint256 entries; uint256 reveals; }

    function setUp() public {
        h = new EntryRevealHarness();
        beforeCode = vm.parseBytes(vm.readFile("contracts/mocks/EntryRevealBaseline.hex"));
        assertEq(keccak256(beforeCode), 0xbc93ffbe68b1d942cd336e84ec4c3c1681d763bf33449383cf657189014e9ce5);
        afterCode = address(new DegenerusGameFoilPackModule()).code;
    }

    function _observe(bool candidate, uint256 entropy, uint32 room) private returns (Observation memory o) {
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, candidate ? afterCode : beforeCode);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint256 start = gasleft();
        h.run(room, entropy);
        o.gasUsed = start - gasleft();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accesses[i].storageAccesses[j];
                assertEq(a.account, address(h));
                if (a.isWrite) o.writes = keccak256(abi.encode(o.writes, a.slot, a.previousValue, a.newValue));
            }
        }
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            assertEq(l.emitter, address(h));
            uint256 traits;
            uint256 mask;
            uint256 owners;
            uint256 seats;
            if (candidate) {
                assertEq(l.topics.length, 4);
                assertEq(l.data.length, 32);
                uint144 packed = abi.decode(l.data, (uint144));
                traits = uint128(packed);
                mask = packed >> 128;
                seats = 4;
                ++o.reveals;
            } else {
                assertEq(l.topics[0], OLD_EVENT);
                (, traits, , owners) = abi.decode(l.data, (uint32, uint256, uint32, uint256));
                (, , uint32 oldMask, ) = abi.decode(l.data, (uint32, uint256, uint32, uint256));
                mask = oldMask;
                seats = 8;
            }
            for (uint256 j; j < seats; ++j) {
                address player;
                if (candidate) {
                    uint256 topic = uint256(l.topics[j]);
                    if ((mask >> (4 * j)) & 15 == 0) { assertEq(topic, 0, "unused seat topic"); continue; }
                    assertEq(topic >> 160, 7, "level prefix");
                    player = address(uint160(topic));
                } else {
                    uint32 pos = uint32(owners >> (32 * j));
                    if (pos == 0) continue;
                    player = h.owner(pos - 1);
                }
                for (uint256 q; q < 4; ++q) if (mask & (1 << (4 * j + q)) != 0) {
                    uint8 trait = uint8(traits >> (32 * j + 8 * q));
                    assertEq(trait >> 6, q, "quadrant encoded in trait");
                    unchecked { o.inventory += uint256(keccak256(abi.encode(player, trait))); }
                    ++o.entries;
                }
            }
        }
    }

    function _compare(uint32[] memory amounts, uint8 rem, uint256 entropy) private returns (Observation memory a, Observation memory b) {
        h.seed(amounts, rem, 1 << 24);
        uint256 snapshot = vm.snapshotState();
        a = _observe(false, entropy, 1_000_000);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        b = _observe(true, entropy, 1_000_000);
        assertEq(b.writes, a.writes, "identical ordered storage writes");
        assertEq(b.inventory, a.inventory, "same player/trait multiset");
        assertEq(b.entries, a.entries, "same entry count");
    }

    function _distribution(uint32 perBuyer) private {
        uint32[] memory amounts = new uint32[](4096 / perBuyer);
        for (uint256 i; i < amounts.length; ++i) amounts[i] = perBuyer;
        (Observation memory a, Observation memory b) = _compare(amounts, 0, uint256(keccak256("reveal-gas")));
        assertEq(b.entries, 4096);
        emit log_named_uint("entries_per_buyer", perBuyer);
        emit log_named_uint("entries", b.entries);
        emit log_named_uint("drain_before", a.gasUsed);
        emit log_named_uint("drain_after", b.gasUsed);
        emit log_named_uint("delta", b.gasUsed - a.gasUsed);
        emit log_named_uint("delta_per_entry_milli", (b.gasUsed - a.gasUsed) * 1000 / b.entries);
    }

    function test_Gas_4EntriesPerBuyer() public { _distribution(4); }
    function test_Gas_32EntriesPerBuyer() public { _distribution(32); }
    function test_Gas_128EntriesPerBuyer() public { _distribution(128); }

    function test_ChargedChunkThroughput() public {
        uint32[3] memory sizes = [uint32(4), uint32(32), uint32(128)];
        for (uint256 i; i < sizes.length; ++i) {
            for (uint256 cold; cold < 2; ++cold) {
                h = new EntryRevealHarness();
                uint32[] memory amounts = new uint32[](4096 / sizes[i]);
                for (uint256 j; j < amounts.length; ++j) amounts[j] = sizes[i];
                h.seed(amounts, 0, 1 << 24);
                uint256 snapshot = vm.snapshotState();
                uint32 room = cold == 0 ? 1000 : 650;
                Observation memory a = _observe(false, uint256(keccak256("reveal-gas")), room);
                assertTrue(vm.revertToStateAndDelete(snapshot));
                Observation memory b = _observe(true, uint256(keccak256("reveal-gas")), room);
                emit log_named_uint("chunk_entries_per_buyer", sizes[i]);
                emit log_named_uint("chunk_budget", room);
                emit log_named_uint("chunk_entries_before", a.entries);
                emit log_named_uint("chunk_entries_after", b.entries);
                emit log_named_uint("chunk_gas_before", a.gasUsed);
                emit log_named_uint("chunk_gas_after", b.gasUsed);
                assertLe(b.entries, a.entries, "increased charges cannot add rounds");
                assertLt(b.gasUsed, 10_000_000);
            }
        }
    }

    function testFuzz_RevealParity_PartialsAndTrailingTopics(uint256 entropy, uint8 countSeed, uint8 remSeed) public {
        uint32[] memory amounts = new uint32[](4 + countSeed % 13);
        for (uint256 i; i < amounts.length; ++i) amounts[i] = uint32(1 + uint256(keccak256(abi.encode(entropy, i))) % 13);
        _compare(amounts, remSeed % 100, entropy);
    }
}
