// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LegacyTicketOwnerReference} from "../helpers/LegacyTicketOwnerReference.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";

contract EntryRevealHarness is LegacyTicketOwnerReference {
    function seed(uint32[] memory amounts, uint8 rem, uint256 ownerStart) external {
        _setTicketBufferLevel(7);
        address[] storage owners = ticketOwners;
        assembly ("memory-safe") { sstore(owners.slot, ownerStart) }
        for (uint256 i; i < amounts.length; ++i) {
            uint80 bits = _registerEntryOwner(address(uint160(0x123400 + i)), 7);
            uint32 pos = uint32(bits >> OWNER_IDX_SHIFT);
            _tqAppend(7, pos);
            _setEntryOwed(7, pos, bits | (uint80(amounts[i]) << 8) | rem);
        }
    }

    function owner(uint32 idx) external view returns (address) { return ticketOwners[idx]; }

    /// @dev Owed entries left queued for `n` seeded buyers, and which buyers' fractional
    ///      remainder has been consumed (its stored remainder byte is zero).
    function remainingOwed(uint256 n) external view returns (uint256 owedSum, uint256 consumed) {
        for (uint256 i; i < n; ++i) {
            uint80 packed = _entryPacked(7, ticketOwnerId[address(uint160(0x123400 + i))]);
            owedSum += uint32(packed >> 8);
            if (uint8(packed) == 0) consumed |= uint256(1) << i;
        }
    }

    /// @dev Owed entries the pinned legacy runtime left in its owner records (installLegacyOwners layout).
    function legacyRemainingOwed(uint256 n) external view returns (uint256 owedSum) {
        uint256 base = uint256(keccak256(abi.encode(keccak256(abi.encode(uint24(7), uint256(67))))));
        for (uint256 i; i < n; ++i) {
            uint256 slot = base + ticketOwnerId[address(uint160(0x123400 + i))] - 1;
            uint256 record;
            assembly ("memory-safe") { record := sload(slot) }
            owedSum += uint32(record >> 168);
        }
    }

    /// @dev The stored (player, trait) multiset and entry count of the live level buffer.
    function storedInventory(uint24 lvl) external view returns (uint256 inventory, uint256 entries) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            entries += n;
            for (uint256 i; i < n; ++i) {
                unchecked { inventory += uint256(keccak256(abi.encode(_bucketOwnerAtUnchecked(lvl, uint8(t), i), uint8(t)))); }
            }
        }
    }

    /// @dev The pinned pre-reveal runtime reads its queue at the raw level key; queue roots now
    ///      recycle physical slots under a level tag. Copy the live queue words to the raw-key
    ///      array the legacy runtime addresses (a root the current layout never uses).
    function installLegacyQueue(uint24 key) external {
        uint256[] storage live = ticketQueue[_ticketQueueStorageKey(key)];
        uint256 rawRoot = uint256(keccak256(abi.encode(uint256(key), uint256(12))));
        uint256 rawData = uint256(keccak256(abi.encode(rawRoot)));
        uint256 n = _ticketQueueLength(key);
        assembly ("memory-safe") { sstore(rawRoot, n) }
        for (uint256 i; i < (n + 7) / 8; ++i) {
            uint256 word = live[i];
            uint256 slot = rawData + i;
            assembly ("memory-safe") { sstore(slot, word) }
        }
    }

    /// @dev The pinned pre-reveal runtime (etched at the foil module address) exposes its round
    ///      drain as drainRounds(rk, lvl, room, idx, total, entropy, shift).
    function runLegacy(uint32 room, uint256 entropy) external returns (uint256 frontier, uint32 used) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_FOILPACK_MODULE.delegatecall(
            abi.encodeWithSelector(bytes4(keccak256("drainRounds(uint24,uint24,uint32,uint256,uint256,uint256,uint8)")),
                uint24(7), uint24(7), room, uint256(0), _ticketQueueLength(7), entropy, uint8(0))
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (uint256, uint32));
    }

    /// @dev The state in which the ticket worker drains key 7 from its start: level 7 puts it in
    ///      the mint window, the write slot makes 7 the read key, and `entropy` is the published
    ///      read word.
    function primeCurrent(uint256 entropy) external {
        level = 7;
        ticketWriteSlot = true;
        rngWordCurrent = entropy;
        _setRngSessionPublished(true);
    }

    /// @dev The production ticket worker, delegatecalled as mineFlip's Tickets stage dispatches
    ///      it at anchor level + 1; the gas the call is sent bounds it.
    function runCurrent() external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameTicketModule.runTicketWork.selector, uint24(8), gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }
}

/// @notice Measures only drain execution, from identical state, against the pinned pre-reveal
///         runtime. The large room isolates event cost from deliberately changed chunk limits;
///         production-budget gas is checked separately by RoundDrainChunkGas. The current ticket
///         worker spends the gas it is given, so its bounded-allowance runs check progress, not a
///         ceiling; it finishes a short queue's sub-round tail on the per-entry path in the same
///         call, and those runs are revealed by TraitsGenerated, replayed here.
contract EntryRevealGas is Test {
    bytes32 private constant OLD_EVENT = keccak256("RoundTraitsGenerated(uint24,uint32,uint256,uint32,uint256)");
    bytes32 private constant TRAITS_GENERATED = keccak256("TraitsGenerated(address,uint256,uint32)");
    uint64 private constant TICKET_LCG_MULT = 6364136223846793005;
    EntryRevealHarness private h;
    bytes private beforeCode;
    bytes private afterCode;

    struct Observation { uint256 gasUsed; bytes32 writes; uint256 inventory; uint256 entries; uint256 reveals; bytes32 buckets; }

    function setUp() public {
        h = new EntryRevealHarness();
        beforeCode = vm.parseBytes(vm.readFile("contracts/mocks/EntryRevealBaseline.hex"));
        assertEq(keccak256(beforeCode), 0xbc93ffbe68b1d942cd336e84ec4c3c1681d763bf33449383cf657189014e9ce5);
        afterCode = address(new DegenerusGameFoilPackModule()).code;
        // The current drain is the ticket worker at its pinned address.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
    }

    function _observe(bool candidate, uint256 entropy, uint32 room) private returns (Observation memory o) {
        return _observe(candidate, entropy, room, 0);
    }

    /// @dev `supplied` != 0 bounds the call's gas. The current ticket worker has no write room: it
    ///      admits checkpoints while the supplied gas covers the next one.
    function _observe(bool candidate, uint256 entropy, uint32 room, uint256 supplied)
        private returns (Observation memory o)
    {
        if (!candidate) {
            h.installLegacyOwners(7, 7);
            h.installLegacyQueue(7);
        }
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, candidate ? afterCode : beforeCode);
        if (candidate) h.primeCurrent(entropy);
        vm.recordLogs();
        vm.startStateDiffRecording();
        uint256 start = gasleft();
        if (!candidate) h.runLegacy(room, entropy);
        else if (supplied == 0) h.runCurrent();
        else h.runCurrent{gas: supplied}();
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
        // Physical bucket addresses and level stamps intentionally changed. Compare
        // every stored logical bucket (including lane order), not raw slot identity.
        o.buckets = h.logicalBuckets(7, !candidate);
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            assertEq(l.emitter, address(h));
            uint256 traits;
            uint256 mask;
            uint256 owners;
            uint256 seats;
            if (candidate && l.topics.length == 2 && l.topics[0] == TRAITS_GENERATED) {
                // A per-entry run of the queue's tail: replay its traits from the event.
                (uint256 keyed, uint32 take) = abi.decode(l.data, (uint256, uint32));
                unchecked { o.inventory += this.soloInventory(address(uint160(uint256(l.topics[1]))), keyed, take, entropy); }
                o.entries += take;
                continue;
            }
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

    /// @dev The (player, trait) multiset of one per-entry run, replayed off-chain from its
    ///      TraitsGenerated fields: the stream identity carrying the run's start offset in its low
    ///      32 bits and, in bit 255, whether the gold six was already taken before the run.
    ///      External so the replay keeps its own stack frame outside `_observe`.
    function soloInventory(address player, uint256 keyed, uint32 take, uint256 entropy)
        external pure returns (uint256 inventory)
    {
        bool goldTaken = keyed & TicketEntropy.GOLD_SIX_TAKEN != 0;
        uint256 stream = keyed & ~TicketEntropy.GOLD_SIX_TAKEN & ~uint256(type(uint32).max);
        uint256 i = uint32(keyed);
        uint256 end = i + take;
        while (i < end) {
            uint64 s = uint64(uint256(keccak256(abi.encode(stream, entropy, i >> 4)))) | 1;
            uint64 offset = uint64(i & 15);
            unchecked { s = s * (TICKET_LCG_MULT + offset) + offset; }
            for (uint256 j = offset; j < 16 && i < end; ++j) {
                unchecked { s = s * TICKET_LCG_MULT + 1; }
                uint8 trait = DegenerusTraitUtils.traitFromWord(s) + uint8((i & 3) << 6);
                if (trait == GoldSixLib.TRAIT) {
                    if (goldTaken) trait = GoldSixLib.replacement(s);
                    else goldTaken = true;
                }
                unchecked { inventory += uint256(keccak256(abi.encode(player, trait))); }
                ++i;
            }
        }
    }

    function _compare(uint32[] memory amounts, uint8 rem, uint256 entropy) private returns (Observation memory a, Observation memory b) {
        h.seed(amounts, rem, 1 << 24);
        uint256 snapshot = vm.snapshotState();
        a = _observe(false, entropy, 1_000_000);
        uint256 legacyLeft = h.legacyRemainingOwed(amounts.length);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        b = _observe(true, entropy, 1_000_000);
        // Since 5214f7498 every frozen queue starts at a word-derived rotation
        // (docs/audit/RNG-DOMAINS.md, DEGENERUS_TICKET_ROTATION_V1), so the current drain seats
        // owners in a different order than the pinned pre-reveal runtime and the stored lanes and
        // player/trait pairs legitimately differ from it. What still holds: both drain the same
        // entries, and every current reveal reports exactly what the drain stored.
        // Entry conservation, computed exactly. A fractional remainder now resolves under the V2
        // identity (docs/audit/RNG-DOMAINS.md: one extra entry on a win), and a round needs four
        // seats, so a short queue's tail is finished by the per-entry path in the same call.
        (uint256 owedLeft, uint256 consumed) = h.remainingOwed(amounts.length);
        uint256 expected;
        for (uint256 i; i < amounts.length; ++i) {
            expected += amounts[i];
            if (rem != 0 && consumed & (uint256(1) << i) != 0 && TicketEntropy.remainder(
                TicketEntropy.identity(7, 7, i, address(uint160(0x123400 + i))), entropy, rem
            )) ++expected;
        }
        assertEq(b.entries + owedLeft, expected, "revealed plus still-owed entries equal whole entries plus winning fractions");
        if (rem == 0) assertEq(b.entries + owedLeft, a.entries + legacyLeft, "same entry count");
        (uint256 storedInv, uint256 storedEntries) = h.storedInventory(7);
        assertEq(storedEntries, b.entries, "every stored entry is revealed once");
        assertEq(b.inventory, storedInv, "reveals carry exactly the stored player/trait multiset");
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
        int256 delta = int256(b.gasUsed) - int256(a.gasUsed);
        emit log_named_int("delta", delta);
        emit log_named_int("delta_per_entry_milli", delta * 1000 / int256(b.entries));
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
                // The current worker spends the gas it is given (no write room): drive it with a
                // realistic 10M allowance and require progress.
                Observation memory b = _observe(true, uint256(keccak256("reveal-gas")), room, 10_000_000);
                emit log_named_uint("chunk_entries_per_buyer", sizes[i]);
                emit log_named_uint("chunk_budget", room);
                emit log_named_uint("chunk_entries_before", a.entries);
                emit log_named_uint("chunk_entries_after", b.entries);
                emit log_named_uint("chunk_gas_before", a.gasUsed);
                emit log_named_uint("chunk_gas_after", b.gasUsed);
                assertGt(b.entries, 0, "a realistic allowance must make progress");
                (uint256 storedInv, uint256 storedEntries) = h.storedInventory(7);
                assertEq(storedEntries, b.entries, "a bounded call reveals every entry it stored");
                assertEq(b.inventory, storedInv, "bounded-call reveals carry the stored multiset");
            }
        }
    }

    function testFuzz_RevealParity_PartialsAndTrailingTopics(uint256 entropy, uint8 countSeed, uint8 remSeed) public {
        // A published read word is never 0 or the waiting sentinel 1.
        if (entropy < 2) entropy += 2;
        uint32[] memory amounts = new uint32[](4 + countSeed % 13);
        for (uint256 i; i < amounts.length; ++i) amounts[i] = uint32(1 + uint256(keccak256(abi.encode(entropy, i))) % 13);
        _compare(amounts, remSeed % 100, entropy);
    }
}
