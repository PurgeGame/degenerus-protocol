// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract EntryRevealHarness is DegenerusGameStorage, WalletSeed {
    function seed(uint32[] memory amounts, uint8 rem, uint256 ownerStart) external {
        _setTicketBufferLevel(7);
        uint256[] storage owners = wallets;
        assembly ("memory-safe") { sstore(owners.slot, add(ownerStart, 1)) }
        for (uint256 i; i < amounts.length; ++i) {
            uint80 bits = (uint80(_seedWallet(address(uint160(0x123400 + i)))) << OWNER_IDX_SHIFT);
            uint32 pos = uint32(bits >> OWNER_IDX_SHIFT);
            _tqAppend(7, pos);
            _setEntryOwed(7, pos, bits | (uint80(amounts[i]) << 8) | rem);
        }
    }

    function walletIdOf(address owner) external view returns (uint32) { return _walletIdOf(owner); }

    /// @dev Owed entries left queued for `n` seeded buyers, and which buyers' fractional
    ///      remainder has been consumed (its stored remainder byte is zero).
    function remainingOwed(uint256 n) external view returns (uint256 owedSum, uint256 consumed) {
        for (uint256 i; i < n; ++i) {
            uint80 packed = _entryPacked(7, _walletIdOf(address(uint160(0x123400 + i))));
            owedSum += uint32(packed >> 8);
            if (uint8(packed) == 0) consumed |= uint256(1) << i;
        }
    }

    /// @dev The stored (wallet ID, trait) multiset and entry count of the live level buffer.
    function storedInventory(uint24 lvl) external view returns (uint256 inventory, uint256 entries) {
        for (uint256 t; t < 256; ++t) {
            uint256 n = _bucketLength(lvl, t);
            entries += n;
            for (uint256 i; i < n; ++i) {
                unchecked { inventory += uint256(keccak256(abi.encode(_bucketIdAtUnchecked(lvl, uint8(t), i), uint8(t)))); }
            }
        }
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

/// @notice Drain gas of the ticket worker by buyer size, and reveal parity: every stored entry is
///         revealed exactly once, by wallet ID, either in a seated `EntryTraitsRevealed` topic or
///         by replaying a per-entry run from its `TraitsGenerated` key. The worker finishes a
///         short queue's sub-round tail on the per-entry path in the same call.
contract EntryRevealGas is Test {
    bytes32 private constant TRAITS_GENERATED = keccak256("TraitsGenerated(uint32,uint256,uint32)");
    uint64 private constant TICKET_LCG_MULT = 6364136223846793005;
    EntryRevealHarness private h;

    struct Observation { uint256 gasUsed; uint256 inventory; uint256 entries; uint256 reveals; }

    function setUp() public {
        h = new EntryRevealHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
    }

    /// @dev `supplied` != 0 bounds the call's gas; the worker admits checkpoints while the
    ///      supplied gas covers the next one.
    function _observe(uint256 entropy, uint256 supplied) private returns (Observation memory o) {
        h.primeCurrent(entropy);
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
        vm.recordLogs();
        uint256 start = gasleft();
        if (supplied == 0) h.runCurrent();
        else h.runCurrent{gas: supplied}();
        o.gasUsed = start - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            assertEq(l.emitter, address(h));
            if (l.topics.length == 2 && l.topics[0] == TRAITS_GENERATED) {
                // A per-entry run of the queue's tail: replay its traits from the event.
                (uint256 keyed, uint32 take) = abi.decode(l.data, (uint256, uint32));
                uint32 id = uint32(uint256(l.topics[1]));
                assertEq(uint256(l.topics[1]) >> 32, 0, "wallet ID topic");
                unchecked { o.inventory += this.soloInventory(id, keyed, take, entropy); }
                o.entries += take;
                continue;
            }
            assertEq(l.topics.length, 4);
            assertEq(l.data.length, 32);
            uint144 packed = abi.decode(l.data, (uint144));
            uint256 traits = uint128(packed);
            uint256 mask = packed >> 128;
            ++o.reveals;
            for (uint256 j; j < 4; ++j) {
                uint256 topic = uint256(l.topics[j]);
                if ((mask >> (4 * j)) & 15 == 0) { assertEq(topic, 0, "unused seat topic"); continue; }
                assertEq(topic >> 160, 7, "level prefix");
                assertEq(uint160(topic) >> 32, 0, "wallet ID in the low 32 bits");
                uint32 id = uint32(topic);
                assertTrue(id != 0, "seated wallet ID");
                for (uint256 q; q < 4; ++q) if (mask & (1 << (4 * j + q)) != 0) {
                    uint8 trait = uint8(traits >> (32 * j + 8 * q));
                    assertEq(trait >> 6, q, "quadrant encoded in trait");
                    unchecked { o.inventory += uint256(keccak256(abi.encode(id, trait))); }
                    ++o.entries;
                }
            }
        }
    }

    /// @dev The (wallet ID, trait) multiset of one per-entry run, replayed off-chain from its
    ///      TraitsGenerated fields: the stream identity carrying the wallet ID in bits 32..63, the
    ///      run's start offset in its low 32 bits and, in bit 255, whether the gold six was
    ///      already taken before the run. External so the replay keeps its own stack frame.
    function soloInventory(uint32 id, uint256 keyed, uint32 take, uint256 entropy)
        external pure returns (uint256 inventory)
    {
        bool goldTaken = keyed & TicketEntropy.GOLD_SIX_TAKEN != 0;
        uint256 stream = keyed & ~TicketEntropy.GOLD_SIX_TAKEN & ~uint256(type(uint32).max);
        require(uint32(stream >> TicketEntropy.ID_SHIFT) == id, "key carries the topic's wallet ID");
        require((stream >> 64) & type(uint128).max == 0, "bits 64..191 are zero");
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
                unchecked { inventory += uint256(keccak256(abi.encode(id, trait))); }
                ++i;
            }
        }
    }

    function _check(uint32[] memory amounts, uint8 rem, uint256 entropy, uint256 supplied)
        private returns (Observation memory b)
    {
        h.seed(amounts, rem, 1 << 24);
        b = _observe(entropy, supplied);
        // Entry conservation, computed exactly. A fractional remainder resolves under the
        // wallet-ID identity (one extra entry on a win).
        (uint256 owedLeft, uint256 consumed) = h.remainingOwed(amounts.length);
        uint256 expected;
        for (uint256 i; i < amounts.length; ++i) {
            expected += amounts[i];
            if (rem != 0 && consumed & (uint256(1) << i) != 0 && TicketEntropy.remainder(
                TicketEntropy.identity(7, 7, i, h.walletIdOf(address(uint160(0x123400 + i)))), entropy, rem
            )) ++expected;
        }
        assertEq(b.entries + owedLeft, expected, "revealed plus still-owed entries equal whole entries plus winning fractions");
        (uint256 storedInv, uint256 storedEntries) = h.storedInventory(7);
        assertEq(storedEntries, b.entries, "every stored entry is revealed once");
        assertEq(b.inventory, storedInv, "reveals carry exactly the stored wallet/trait multiset");
    }

    function _distribution(uint32 perBuyer) private {
        uint32[] memory amounts = new uint32[](4096 / perBuyer);
        for (uint256 i; i < amounts.length; ++i) amounts[i] = perBuyer;
        Observation memory b = _check(amounts, 0, uint256(keccak256("reveal-gas")), 0);
        assertEq(b.entries, 4096);
        emit log_named_uint("entries_per_buyer", perBuyer);
        emit log_named_uint("entries", b.entries);
        emit log_named_uint("drain_gas", b.gasUsed);
        emit log_named_uint("drain_gas_per_entry_milli", b.gasUsed * 1000 / b.entries);
    }

    function test_Gas_4EntriesPerBuyer() public { _distribution(4); }
    function test_Gas_32EntriesPerBuyer() public { _distribution(32); }
    function test_Gas_128EntriesPerBuyer() public { _distribution(128); }

    /// @dev A realistic 10M allowance makes progress on every buyer size, and a bounded call
    ///      reveals exactly what it stored.
    function test_ChargedChunkThroughput() public {
        uint32[3] memory sizes = [uint32(4), uint32(32), uint32(128)];
        for (uint256 i; i < sizes.length; ++i) {
            h = new EntryRevealHarness();
            uint32[] memory amounts = new uint32[](4096 / sizes[i]);
            for (uint256 j; j < amounts.length; ++j) amounts[j] = sizes[i];
            h.seed(amounts, 0, 1 << 24);
            Observation memory b = _observe(uint256(keccak256("reveal-gas")), 10_000_000);
            emit log_named_uint("chunk_entries_per_buyer", sizes[i]);
            emit log_named_uint("chunk_entries", b.entries);
            emit log_named_uint("chunk_gas", b.gasUsed);
            assertGt(b.entries, 0, "a realistic allowance must make progress");
            (uint256 storedInv, uint256 storedEntries) = h.storedInventory(7);
            assertEq(storedEntries, b.entries, "a bounded call reveals every entry it stored");
            assertEq(b.inventory, storedInv, "bounded-call reveals carry the stored multiset");
        }
    }

    function testFuzz_RevealParity_PartialsAndTrailingTopics(uint256 entropy, uint8 countSeed, uint8 remSeed) public {
        // A published read word is never 0 or the waiting sentinel 1.
        if (entropy < 2) entropy += 2;
        uint32[] memory amounts = new uint32[](4 + countSeed % 13);
        for (uint256 i; i < amounts.length; ++i) amounts[i] = uint32(1 + uint256(keccak256(abi.encode(entropy, i))) % 13);
        _check(amounts, remSeed % 100, entropy, 0);
    }
}
