// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {Vm} from "forge-std/Vm.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";

/// @dev Each repricing replay gets fresh memory; the large scratch tables must not accumulate
///      across a many-word sweep inside the test contract's single call frame.
contract HumanOrderRepricer {
    function quote(uint256 measured, VmSafe.AccountAccess[] calldata accesses, address target)
        external pure returns (GlamsterdamReprice.Result memory)
    {
        return GlamsterdamReprice.reprice(measured, accesses, target);
    }
}

contract HumanOrderGasSeed is DegenerusGame {
    /// @dev Seed the sealed read buffer with ONE entry for `player`: the `input` purchase priced at
    ///      level 100 (none when zero).
    function seedOrder(address player, uint256 input, uint256 entropy) external {
        _registerWallet(player, type(uint256).max);
        level = 99;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        _afkingResetDay = dailyIdx;
        subsFullyProcessed = true;
        _setRngRequestActive(false);
        _setRngComplete(false);
        _setRngSessionPublished(true);
        rngLockedFlag = false;
        rngWordCurrent = entropy;
        ticketsFullyProcessed = true;
        humanReadComplete = false;
        _pendingBoxCount = 0;
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 0);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        uint48 idx = _rngReadBuffer();
        uint256 word;
        if (input != 0) (word,) = _decodeBoxOrder(input, 100);
        word |= uint256(_walletIdOf(player))
            | BoxOrderLib.scoreCode(ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) << LB_SCORE_SHIFT;
        uint256[] storage q = boxQueue[idx];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            sstore(keccak256(0x00, 0x20), word)
        }
        boxReadCount = 1;
        boxCursor = 0;
        _setCurrentPrizePool(10_000 ether);
        _setPrizePools(10_000 ether, 10_000 ether);
    }

    /// @dev The worker's per-entry step: store the advanced cursor, then settle the entry.
    function rawAtomic() external returns (uint256 boxes) {
        uint48 idx = _rngReadBuffer();
        uint256 entry = _boxEntryAt(idx, 0);
        boxes = _boxEntryCount(entry);
        boxCursor = 1;
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature("resolveHumanBoxOrder(uint48,uint256,uint256,uint256,uint24)",
                idx, uint256(0), entry, _lootboxWord(idx), level + 1)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    /// @dev Gross gas of the production human-box worker over the seeded queue (one entry).
    function measuredWork(uint256 allowance) external returns (bool done, uint256 grossGas) {
        bytes memory data = abi.encodeWithSignature("runHumanBoxWork_g315(uint256)", allowance);
        uint256 beforeGas = gasleft();
        (bool ok, bytes memory returned) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(data);
        grossGas = beforeGas - gasleft();
        if (!ok) assembly ("memory-safe") { revert(add(returned, 32), mload(returned)) }
        (, done,) = abi.decode(returned, (bool, bool, uint256));
    }

    function entry() external view returns (uint256) {
        return _boxEntryAt(_rngReadBuffer(), 0);
    }

    /// @dev Entries of the read buffer the cursor has not yet passed.
    function entriesLeft() external view returns (uint256) {
        return boxReadCount - boxCursor;
    }

    function outcome(address player) external view returns (bytes32 digest) {
        digest = keccak256(abi.encode(_claimableOf(_walletIdOf(player)), boonPacked[_walletIdOf(player)], mintPacked_[_walletIdOf(player)],
            _getCurrentPrizePool(), _getNextPrizePool(), _getFuturePrizePool(),
            humanReadComplete, boxCursor, boxReadCount));
        for (uint24 lvl = 100; lvl <= 150; ++lvl) {
            digest = keccak256(abi.encode(digest, _entriesOwedTotal(lvl, _walletIdOf(player))));
        }
    }
}

contract HumanOrderNativeGasTest is DeployProtocol, NativeGasExport {
    uint256 private constant NO_RESERVOIR_GAS_LIMIT = 1 << 24;

    address private constant PLAYER = address(0xB0A100);
    address private constant MINER = address(0xB0A200);
    bytes private gameCode;
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant MINER_BOUNTY = keccak256("MinerBounty(uint8,address,uint256)");
    bytes32 private constant BOX_SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");

    function setUp() public {
        _deployProtocol(false);
        gameCode = address(game).code;
        vm.deal(address(game), 50_000 ether);
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
    }

    function _cool() private {
        vm.cool(address(game)); vm.cool(address(coin)); vm.cool(address(coinflip));
        vm.cool(address(sdgnrs)); vm.cool(address(wwxrp)); vm.cool(address(crapsBattle));
        vm.cool(ContractAddresses.GAME_MINER_MODULE); vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE); vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE); vm.cool(ContractAddresses.GAME_WHALE_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
    }

    function test_RepricedFreshCapEntryBounds() public {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolated transactions");
        uint256[5] memory orders = [BoxOrderLib.boSmalls(1), BoxOrderLib.boSmalls(100),
            BoxOrderLib.boLarges(100),
            BoxOrderLib.boCustoms(100, 10 ether),
            BoxOrderLib.boCustoms(100, 2_000 ether)];
        uint256 peakExec;
        uint256 peakTotal;
        uint256 minimumHeadroom = type(uint256).max;
        for (uint256 i; i < orders.length; ++i) {
            for (uint256 w = 1; w <= 16; ++w) {
                uint256 fixture = vm.snapshotState();
                (uint256 execution, uint256 total, uint256 headroom) = this.freshCapCase(
                    orders[i], uint256(keccak256(abi.encode("ev-open", w))),
                    string.concat("human_fresh_", vm.toString(i), "_", vm.toString(w)));
                if (execution > peakExec) peakExec = execution;
                if (total > peakTotal) peakTotal = total;
                if (headroom < minimumHeadroom) minimumHeadroom = headroom;
                assertTrue(vm.revertToStateAndDelete(fixture));
            }
        }
        emit log_named_uint("repriced fresh-cap peak execution", peakExec);
        emit log_named_uint("repriced fresh-cap peak including state", peakTotal);
        emit log_named_uint("repriced fresh-cap minimum entry headroom", minimumHeadroom);
    }

    /// @dev Each sweep case owns its temporary log and state-diff allocations.
    function freshCapCase(uint256 input, uint256 word, string calldata label)
        external returns (uint256 execution, uint256 total, uint256 headroom)
    {
        require(msg.sender == address(this), "fresh-cap self-call");
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        HumanOrderRepricer repricer = new HumanOrderRepricer();
        host.seedOrder(PLAYER, input, word);
        uint256 bound = _entryBound(BoxOrderLib.boCount(host.entry()));
        uint256 snap = vm.snapshotState();
        _cool();
        host.rawAtomic();
        uint256 measured = vm.lastCallGas().gasTotalUsed;
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        host.rawAtomic();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory r = repricer.quote(measured, accesses, address(host));
        execution = r.glamsterdamExec;
        total = execution + r.stateGas;
        assertLe(measured, bound, "fresh-cap Osaka admission");
        assertLe(total, bound, "fresh-cap state-inclusive admission");
        headroom = bound - total;
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snap));
            this.exportAtomic(label);
        }
        assertTrue(vm.deleteStateSnapshot(snap));
    }

    function _probe(uint256 input, uint256 word) private {
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        host.seedOrder(PLAYER, input, word);
        uint256 snapshot = vm.snapshotState();
        uint256 count = BoxOrderLib.boCount(host.entry());
        uint256 bound = GasBounds.HUMAN_ENTRY_GAS + count * GasBounds.HUMAN_BOX_GAS;
        _cool();
        uint256 beforeGas = gasleft();
        uint256 resolved = host.rawAtomic{gas: 25_000_000}();
        uint256 atomicGas = beforeGas - gasleft();
        emit log_named_uint("human boxes", resolved);
        emit log_named_uint("cold full atomic human order gas", atomicGas);
        emit log_named_uint("configured atomic human allowance", bound);
        assertEq(resolved, count);
        assertEq(host.entriesLeft(), 0);
        assertLe(atomicGas, bound, "cold entry exceeds its declared atomic bound");
        assertLe(bound + GasBounds.HUMAN_TAIL_GAS + MineFlipGas.CHECK_RESERVE, NO_RESERVOIR_GAS_LIMIT,
            "accepted atomic human order fits the no-reservoir transaction envelope");
        assertTrue(vm.revertToState(snapshot));
        vm.etch(address(game), gameCode);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.HumanBoxes), "real engine must select human FIFO");
        snapshot = vm.snapshotState();
        bytes32 full = _mineAndReadOutcome();
        assertTrue(vm.revertToState(snapshot));
        _cool();
        // An allowance that cannot admit the indivisible order makes no progress, and the engine
        // rejects a zero-progress call outright (be793ed7c) instead of returning without work.
        vm.prank(MINER);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        game.mineFlip{gas: 2_000_000}(0);
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
        assertGt(host.entriesLeft(), 0, "gas shortage must preserve the unfinished atomic order");
        vm.etch(address(game), gameCode);
        assertEq(_mineAndReadOutcome(), full, "low-gas checkpoint changed player awards or their order");
    }

    function _mineAndReadOutcome() private returns (bytes32 digest) {
        _cool();
        vm.recordLogs();
        vm.prank(MINER);
        uint256 start = gasleft();
        game.mineFlip{gas: 25_000_000}(0);
        emit log_named_uint("cold complete mineFlip human gas (no transaction cap)", start - gasleft() + 21_192);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].emitter != address(game) || entries[i].topics[0] == MINER_WORK
                || entries[i].topics[0] == MINER_BOUNTY) continue;
            digest = keccak256(abi.encode(digest, entries[i].topics, entries[i].data));
        }
        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(PLAYER);
        digest = keccak256(abi.encode(digest, coinflip.coinflipAmount(PLAYER), sdgnrs.balanceOf(PLAYER),
            wwxrp.claimable(game.walletIdOf_g3120(PLAYER)), normal, high));
        vm.etch(address(game), type(HumanOrderGasSeed).runtimeCode);
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        assertEq(host.entriesLeft(), 0, "engine admitted and completed the order");
        digest = keccak256(abi.encode(digest, host.outcome(PLAYER)));
    }

    /// @dev Declared atomic bound of one entry (no tail).
    function _entryBound(uint256 count) private pure returns (uint256) {
        return GasBounds.HUMAN_ENTRY_GAS + count * GasBounds.HUMAN_BOX_GAS;
    }

    /// @dev Cold atomic gas of one seeded entry, plus the number of winning ETH spins it ran.
    function coldAtomic(uint256 input, uint256 word)
        external returns (uint256 used, uint256 ethWins)
    {
        require(msg.sender == address(this), "cold-atomic self-call");
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        host.seedOrder(PLAYER, input, word);
        uint256 snapshot = vm.snapshotState();
        _cool();
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        host.rawAtomic{gas: 25_000_000}();
        used = beforeGas - gasleft();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].topics[0] != BOX_SPIN) continue;
            (,,, uint256 ethShare) = abi.decode(entries[i].data, (uint64, uint256, uint256, uint256));
            if (ethShare != 0) ++ethWins;
        }
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportAtomic(string.concat("human-", vm.toString(input), "-", vm.toString(word)));
        }
        assertTrue(vm.deleteStateSnapshot(snapshot));
    }

    function exportAtomic(string calldata label) external {
        require(msg.sender == address(this), "atomic export self-call");
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        this.exportNativeFixture(label, address(this), address(host), abi.encodeCall(host.rawAtomic, ()));
        host.rawAtomic{gas: 25_000_000}();
    }

    /// @dev Cold atomic gas of the same entry over `runs` independent committed words. Every
    ///      run starts from the same committed fixture, so each measurement is a cold first touch.
    function _sweep(string memory label, uint256 input, uint256 runs)
        private returns (uint256 peak)
    {
        uint256 base = vm.snapshotState();
        uint256 total;
        uint256 peakWins;
        uint256 mostWins;
        for (uint256 i; i < runs; ++i) {
            (uint256 used, uint256 wins) = this.coldAtomic(input, uint256(keccak256(abi.encode(label, i))));
            total += used;
            if (used > peak) (peak, peakWins) = (used, wins);
            if (wins > mostWins) mostWins = wins;
            assertTrue(vm.revertToState(base));
        }
        assertTrue(vm.deleteStateSnapshot(base));
        uint256 count = BoxOrderLib.boCount(_seededWord(input));
        emit log_named_uint(string.concat(label, ": boxes"), count);
        emit log_named_uint(string.concat(label, ": cold atomic mean"), total / runs);
        emit log_named_uint(string.concat(label, ": cold atomic peak"), peak);
        emit log_named_uint(string.concat(label, ": winning ETH spins at peak"), peakWins);
        emit log_named_uint(string.concat(label, ": most winning ETH spins in one run"), mostWins);
        emit log_named_uint(string.concat(label, ": declared entry bound"), _entryBound(count));
        assertLe(peak, _entryBound(count), "cold entry exceeds its declared atomic bound");
        assertLe(_entryBound(count) + GasBounds.HUMAN_TAIL_GAS + MineFlipGas.CHECK_RESERVE, NO_RESERVOIR_GAS_LIMIT,
            "accepted atomic human order fits the no-reservoir transaction envelope");
    }

    function _seededWord(uint256 input) private returns (uint256 word) {
        uint256 snapshot = vm.snapshotState();
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        host.seedOrder(PLAYER, input, 1);
        word = host.entry();
        assertTrue(vm.revertToStateAndDelete(snapshot));
    }

    /// @dev One 10 ETH box over many words: the per-entry peak includes the heaviest single box
    ///      (a winning ETH spin whose lootbox share recirculates into a nested box).
    function test_ColdSingleBoxSweep() public {
        _sweep("single 10 ETH box", BoxOrderLib.boCustoms(1, 10 ether), 256);
    }

    function test_ColdTenBoxSweep() public {
        _sweep("10 x 10 ETH boxes", BoxOrderLib.boCustoms(10, 10 ether), 96);
    }

    /// @dev Entry cost is concave in its box count (first-touch and per-level writes saturate),
    ///      so the linear declared bound is checked at intermediate counts too.
    function test_ColdBoxCountTable() public {
        uint8[7] memory counts = [2, 3, 5, 20, 35, 50, 70];
        for (uint256 i; i < counts.length; ++i) {
            _sweep(string.concat(vm.toString(uint256(counts[i])), " x 10 ETH boxes"),
                BoxOrderLib.boCustoms(counts[i], 10 ether), 48);
        }
    }

    /// @dev The maximum entry: 100 saturated boxes over many words, every run cold.
    function test_ColdHundredBoxSweep() public {
        _sweep("100 x 10 ETH boxes", BoxOrderLib.boCustoms(100, 10 ether), 64);
    }

    /// @dev 100 large presets (25 ticket prices each at level 100).
    function test_ColdHundredLargePresetSweep() public {
        _sweep("100 large presets", BoxOrderLib.boLarges(100), 48);
    }

    /// @dev The whole production worker over one maximum entry
    ///      fits the entry's declared bound plus HUMAN_TAIL_GAS.
    function test_ColdWorkerEntryAndTailFitDeclaredEnvelope() public {
        HumanOrderGasSeed host = HumanOrderGasSeed(payable(address(game)));
        uint256 base = vm.snapshotState();
        uint256 peakTail;
        for (uint256 i; i < 16; ++i) {
            uint256 word = uint256(keccak256(abi.encode("worker envelope", i)));
            (uint256 atomic,) = this.coldAtomic(BoxOrderLib.boCustoms(100, 10 ether), word);
            assertTrue(vm.revertToState(base));
            host.seedOrder(PLAYER, BoxOrderLib.boCustoms(100, 10 ether), word);
            _cool();
            (bool done, uint256 worker) = host.measuredWork{gas: 25_000_000}(20_000_000);
            assertTrue(done, "single-entry queue completes");
            assertLe(worker, _entryBound(100) + GasBounds.HUMAN_TAIL_GAS, "worker exceeds entry plus tail");
            // The consolidated worker can save an external atomic-call frame.
            // Measure only positive overhead; the envelope remains an upper bound.
            uint256 tail = worker > atomic ? worker - atomic : 0;
            if (tail > peakTail) peakTail = tail;
            assertTrue(vm.revertToState(base));
        }
        emit log_named_uint("worker gas outside the atomic entry (loop, completion) peak", peakTail);
        emit log_named_uint("declared HUMAN_TAIL_GAS", GasBounds.HUMAN_TAIL_GAS);
        assertLe(peakTail, GasBounds.HUMAN_TAIL_GAS, "worker tail exceeds its declared reserve");
    }

    function test_Cold100SaturatedCustomBoxes() public {
        _probe(BoxOrderLib.boCustoms(100, 10 ether), 0xBEEF1234);
    }
    function test_Cold100LargePresets() public {
        _probe(BoxOrderLib.boLarges(100), 0xBEEF1234);
    }
}
