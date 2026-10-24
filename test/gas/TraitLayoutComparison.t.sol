// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {IDegenerusGameFoilWorkerModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

import {Test, Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ChunkHarness} from "./RoundDrainChunkGas.t.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {DeadTallyCheckpointHarness} from "../repro/DeadTallyGasCheckpoints.t.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";

contract TraitLayoutReadHarness is DegenerusGame, BucketSeed {
    function bufferBase(uint24 lvl) external pure returns (uint256) { return _traitBufferBase(lvl); }
    function seed(uint24 lvl) external { _seedBucketDistinct(lvl, 7, 64, 0x10000); }
    function bucketRead(uint24 lvl, uint8 trait, uint256 index) external view returns (uint256, uint32) {
        return (_bucketLength(lvl, trait), _bucketIdAtUnchecked(lvl, trait, index));
    }
}

contract TraitLayoutFoilSeeder is BucketSeed {
    function seed(uint24 lvl, bool reused) external {
        level = lvl;
        _setTicketBufferLevel(lvl);
        uint32 id = _seedWallet(address(0x12345));
        if (reused) {
            for (uint256 t; t < 256; ++t) _bucketAppendRun(_traitBufferBase(lvl), uint8(t), id, 64, lvl);
        }
        foilReadCount = 1;
        foilGenerationDay = _wallDay();
        foilFirstDrawDay = foilGenerationDay;
        rngWordCurrent = uint256(keccak256("trait-layout-foil")) | 1;
        _setRngSessionPublished(true);
        _setRngComplete(false);
        uint256 slot = _foilSlot(_foilReadKey(), 0);
        uint256 pack = (uint256(lvl) << 160) | (uint256(id) << 192);
        assembly ("memory-safe") { sstore(slot, pack) }
        // Suppress the unrelated grand prize path while retaining the terminal level's writes.
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
    }
}

/// @dev Each measurement is a nested call in a fresh isolated transaction. Warming happens
///      inside that transaction, before the measured frame; it never changes storage values.
contract TraitLayoutMeter is Test {
    function observe(address target, bytes calldata input) external returns (VmSafe.AccountAccess[] memory) {
        vm.startStateDiffRecording();
        (bool ok, bytes memory output) = target.call{gas: 12_000_000}(input);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
        return accesses;
    }
    function measure(address target, bytes calldata input, address[] calldata accounts, bytes32[][] calldata slots)
        external returns (uint256 used, bytes memory output)
    {
        for (uint256 i; i < accounts.length; ++i) {
            require(accounts[i].balance < type(uint256).max);
            for (uint256 j; j < slots[i].length; ++j) vm.warmSlot(accounts[i], slots[i][j]);
        }
        bool ok;
        (ok, output) = target.call{gas: 12_000_000}(input);
        used = vm.lastCallGas().gasTotalUsed;
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
    }
}

/// @dev FOUNDRY_ISOLATE=true. Gas excludes transaction intrinsic and the meter frame.
///      Cold/warm replay starts from identical state. Repricing uses a third, unmeasured replay.
contract TraitLayoutComparisonTest is Test {
    TraitLayoutMeter private meter;
    TraitLayoutReadHarness private reader;
    ChunkHarness private ticket;
    DeadTallyCheckpointHarness private tally;

    function setUp() public {
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1024);
        vm.warp(30 days);
        meter = new TraitLayoutMeter();
        reader = new TraitLayoutReadHarness();
        ticket = new ChunkHarness();
        tally = new DeadTallyCheckpointHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
    }

    function _measure(string memory name, address target, bytes memory input) private {
        address[] memory none = new address[](0);
        bytes32[][] memory noSlots = new bytes32[][](0);
        uint256 initial = vm.snapshotState();
        (uint256 cold, bytes memory expected) = meter.measure(target, input, none, noSlots);
        assertTrue(vm.revertToState(initial));
        // Record the exact slots touched, then warm them in the measured transaction.
        VmSafe.AccountAccess[] memory acc = meter.observe(target, input);
        assertTrue(vm.revertToState(initial));
        uint256 count = acc.length;
        for (uint256 i; i < acc.length; ++i) count += acc[i].storageAccesses.length;
        address[] memory accounts = new address[](count);
        bytes32[][] memory slots = new bytes32[][](count);
        uint256 k;
        for (uint256 i; i < acc.length; ++i) {
            accounts[k] = acc[i].account;
            slots[k++] = new bytes32[](0);
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                accounts[k] = acc[i].storageAccesses[j].account;
                slots[k] = new bytes32[](1);
                slots[k++][0] = acc[i].storageAccesses[j].slot;
            }
        }
        (uint256 warm, bytes memory actual) = meter.measure(target, input, accounts, slots);
        assertEq(actual, expected, "same cold/warm result");
        GlamsterdamReprice.Result memory price = GlamsterdamReprice.reprice(cold, acc, target);
        emit log_named_uint(string.concat(name, " cold"), cold);
        emit log_named_uint(string.concat(name, " warm"), warm);
        emit log_named_uint(string.concat(name, " glam_cold_exec"), price.glamsterdamExec);
        emit log_named_uint(string.concat(name, " glam_warm_exec"), uint256(int256(warm) + price.execDelta - int256(price.coldAccounts * 400)));
        emit log_named_uint(string.concat(name, " state_gas"), price.stateGas);
        emit log_named_uint(string.concat(name, " new_slots"), price.newSlots);
        emit log_named_uint(string.concat(name, " sstores"), price.sstores);
        assertTrue(vm.revertToStateAndDelete(initial));
    }

    function test_Layout_BaseEven() public {
        _measure("base_even", address(reader), abi.encodeCall(reader.bufferBase, (42)));
    }
    function test_Layout_BaseOdd() public {
        _measure("base_odd", address(reader), abi.encodeCall(reader.bufferBase, (43)));
    }
    function test_Layout_BucketEven() public {
        reader.seed(42);
        _measure("bucket_even", address(reader), abi.encodeCall(reader.bucketRead, (42, 7, 23)));
    }
    function test_Layout_BucketOdd() public {
        reader.seed(43);
        _measure("bucket_odd", address(reader), abi.encodeCall(reader.bucketRead, (43, 7, 23)));
    }
    function test_Layout_SampleEven() public {
        reader.seed(42);
        _measure("sample_even", address(reader), abi.encodeCall(reader.sampleTraitEntries, (false, 7, 23 << 40)));
    }
    function test_Layout_SampleOdd() public {
        reader.seed(43);
        _measure("sample_odd", address(reader), abi.encodeCall(reader.sampleTraitEntries, (true, 7, 23 << 40)));
    }
    function _ticket(uint24 lvl, bool reused) private {
        ticket.seedViaPurchase(lvl, 8, 800, 0x70000, false);
        if (reused) ticket.recycleBacking(lvl, 32);
        _measure(string.concat("ticket_", lvl == 42 ? "even" : "odd", reused ? "_reused" : "_fresh"),
            address(ticket), abi.encodeCall(ticket.runTicketWork_g1150, (lvl + 1, 10_000_000)));
    }
    function test_Layout_TicketEvenFresh() public { _ticket(42, false); }
    function test_Layout_TicketOddFresh() public { _ticket(43, false); }
    function test_Layout_TicketEvenReused() public { _ticket(42, true); }
    function test_Layout_TicketOddReused() public { _ticket(43, true); }
    function _foil(uint24 lvl, bool reused) private {
        vm.etch(ContractAddresses.GAME, type(TraitLayoutFoilSeeder).runtimeCode);
        TraitLayoutFoilSeeder(ContractAddresses.GAME).seed(lvl, reused);
        vm.etch(ContractAddresses.GAME, address(new DegenerusGameFoilPackModule()).code);
        _measure(string.concat("foil_", lvl == 42 ? "even" : "odd", reused ? "_reused" : "_fresh"),
            ContractAddresses.GAME, abi.encodeCall(IDegenerusGameFoilWorkerModule.runFoilWork, (10_000_000)));
    }
    function test_Layout_FoilEvenFresh() public { _foil(42, false); }
    function test_Layout_FoilOddFresh() public { _foil(43, false); }
    function test_Layout_FoilEvenReused() public { _foil(42, true); }
    function test_Layout_FoilOddReused() public { _foil(43, true); }
    function _tally(uint24 lvl) private {
        tally.latchDeadTally();
        tally.seedCreated(lvl, type(uint256).max, 123);
        _measure(lvl == 42 ? "tally_even" : "tally_odd", address(tally),
            abi.encodeCall(DegenerusGameGameOverModule.runGameOverAdvance, (0, lvl, 10_000_000)));
    }
    function test_Layout_TallyEven() public { _tally(42); }
    function test_Layout_TallyOdd() public { _tally(43); }
}
