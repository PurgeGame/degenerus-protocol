// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameAdvanceModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {NewSlotCensus} from "../helpers/NewSlotCensus.sol";

/// @dev The seeded transition day is the daily phase of a delivered, published request: the
///      engine selects DailyPhase only for an active, published, not-yet-complete session.
contract RecycleSessionSeeder is DegenerusGame, WalletSeed {
    function openDailyPhase() external {
        rngRequestDay = _wallDay();
        _setRngRequest(vrfRequestId == 0 ? 1 : vrfRequestId);
        _setRngSessionPublished(true);
        _setRngComplete(false);
    }

    /// @dev Gross gas of one production daily-phase checkpoint (the century close) in isolation.
    function measuredDailyPhase(uint256 allowance) external returns (bool done, uint256 grossGas) {
        bytes memory data = abi.encodeWithSelector(IDegenerusGameAdvanceModule.runDailyPhase_g2582.selector, allowance);
        uint256 beforeGas = gasleft();
        (bool ok, bytes memory returned) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(data);
        grossGas = beforeGas - gasleft();
        if (!ok) assembly ("memory-safe") { revert(add(returned, 32), mload(returned)) }
        (, done,) = abi.decode(returned, (bool, bool, uint256));
    }

    /// @dev The day's subscriber seat draw pays a wallet with no coinflip stake: its credit
    ///      creates a slot.
    function forceSeatDraw() external {
        while (_subscribers.length < 2) {
            _seedSubscriber(_seedWallet(address(uint160(0x5EA70000 + _subscribers.length))), false);
        }
        uint256 len = _subscribers.length;
        uint256 boxes = _subBoxCount;
        uint256 idx = 1 + EntropyLib.hash2(RngTags.SUBSCRIBER_DRAW, _recordedDailyWord(rngRequestDay)) % (len - 1);
        uint256 position = idx < boxes ? idx : SUBSCRIBER_CAP - (idx - boxes);
        uint32 winner = _seedWallet(address(uint160(0x5EA7F000)));
        _setSubLaneAt(position, uint256(winner));
        _setSubMetaLane(winner, (position + 1) | (uint256(1) << SUB_META_RUN_START_SHIFT));
        if (_afkingEndpointDay < 2) _afkingEndpointDay = 200;
    }

    /// @dev Every deity's lanes for levels 97-100, drained. Any pass grant or perpetual
    ///      extension before the century close writes the word the close extends at level 200.
    function drainDeityLanes() external {
        uint256 drained = 0x40000000;
        drained |= (drained << 32) | (drained << 64) | (drained << 96);
        for (uint256 i; i < _deityCount(); ++i) farFutureOwed[_deityIdAt(i)][12] = drained;
    }
}

abstract contract SdgnrsRecycleGasFixture is BoundaryGasFixture {
    uint256 private constant RNG_WORD = uint256(keccak256("century-recycle-cold-close")) | 1;
    uint256 private constant REFILL_PERCENT = 25 + uint256(keccak256(abi.encode(
        uint256(26), RNG_WORD
    ))) % 51;
    uint256 internal expectedBurns;
    uint256 internal expectedSupply;

    function _setupRecycle(bool empty) internal {
        _deployProtocol();
        vm.startPrank(address(game));
        if (empty) {
            for (uint8 i; i < 4; ++i) {
                expectedBurns += sdgnrs.transferFromPool_g106128(sDGNRS.Pool(i), address(sdgnrs), type(uint256).max);
            }
            sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Degenesis, address(0xA11CE), type(uint256).max);
        } else {
            expectedBurns = sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Whale, address(sdgnrs), 7_000e12 + 1);
        }
        vm.stopPrank();
        expectedSupply = sdgnrs.totalSupply() + expectedBurns * REFILL_PERCENT / 100;

        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(LVL, RNG_WORD);
        vm.etch(address(game), type(RecycleSessionSeeder).runtimeCode);
        RecycleSessionSeeder(payable(address(game))).openDailyPhase();
        _restore(realCode);
        // At the level-100 close every queue through level 100 has drained; the recycled far-future
        // roots (e.g. root 100 for the level-200 perpetual grants) are free to bind.
        TQ.retireCompleted(address(game), LVL);
    }

    /// @dev Per-chunk: the century close (transition close + refill + 32 deity grants) is one daily-phase checkpoint; cold, in isolation, it stays inside the 10M
    ///      realistic chunk limit. Its declared admission bound is logged beside the measurement.
    function _checkColdCloseChunk() internal {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(RecycleSessionSeeder).runtimeCode);
        (bool done, uint256 chunk) = RecycleSessionSeeder(payable(address(game))).measuredDailyPhase(10_000_000);
        vm.etch(address(game), realCode);
        emit log_named_uint("century close checkpoint, cold gross gas", chunk);
        emit log_named_uint("declared TRANSITION_CLOSE + DAILY_PHASE_TAIL", GasBounds.TRANSITION_CLOSE + GasBounds.DAILY_PHASE_TAIL);
        assertTrue(done, "the close completed in one checkpoint");
        assertEq(sdgnrs.lastRecycledCentury(), 1, "the refill ran inside the measured checkpoint");
        assertLe(chunk, 10_000_000, "century close checkpoint inside the realistic chunk limit");
    }

    /// @dev Every account the close can touch, re-colded between snapshot measurements.
    function _coolProtocol() private {
        address[23] memory accounts = [
            address(game), address(sdgnrs), address(dgnrs), address(coinflip), address(coin), address(wwxrp),
            address(quests), address(jackpots), address(affiliate), address(vault), address(deityPass),
            address(crapsBattle), address(crapsEngine), address(jackpotBattle), address(parimutuel),
            address(recordBounty), address(mockStETH), address(afkingSubToken), address(gnrus),
            ContractAddresses.GAME_ADVANCE_MODULE, ContractAddresses.GAME_JACKPOT_MODULE,
            ContractAddresses.GAME_TICKET_MODULE, ContractAddresses.GAME_WHALE_MODULE
        ];
        for (uint256 i; i < accounts.length; ++i) vm.cool(accounts[i]);
    }

    /// @dev The century-close branch alone: the cold checkpoint admitted to the branch, minus the
    ///      same cold checkpoint declined at the branch's admission check (delegatecall frame,
    ///      entry reads and return). The branch must fit TRANSITION_CLOSE, and the smallest
    ///      allowance that admits the close must complete it inside its own meter.
    function _checkColdCloseBranch() internal {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(RecycleSessionSeeder).runtimeCode);
        RecycleSessionSeeder host = RecycleSessionSeeder(payable(address(game)));
        uint256 base = vm.snapshotState();
        _coolProtocol();
        (bool admittedLow, uint256 declined) = host.measuredDailyPhase(1_000_000);
        assertFalse(admittedLow, "a 1M allowance cannot admit the close");
        assertTrue(vm.revertToState(base));
        _coolProtocol();
        (bool done, uint256 full) = host.measuredDailyPhase(10_000_000);
        assertTrue(done, "the close completed in one checkpoint");
        uint256 branch = full - declined;

        uint256 lo = 1_000_000;
        uint256 hi = 10_000_000;
        while (lo + 1 < hi) {
            uint256 mid = (lo + hi) / 2;
            assertTrue(vm.revertToState(base));
            _coolProtocol();
            try host.measuredDailyPhase(mid) returns (bool closed, uint256) {
                if (closed) hi = mid;
                else lo = mid;
            } catch {
                hi = mid;
            }
        }
        assertTrue(vm.revertToState(base));
        _coolProtocol();
        (bool closedAtMinimum,) = host.measuredDailyPhase(hi);
        vm.etch(address(game), realCode);
        emit log_named_uint("century close branch alone, cold", branch);
        emit log_named_uint("declined checkpoint (frame, entry reads, return), cold", declined);
        emit log_named_uint("smallest admitting allowance", hi);
        emit log_named_uint("declared TRANSITION_CLOSE", GasBounds.TRANSITION_CLOSE);
        assertTrue(closedAtMinimum, "the smallest admitting allowance completes the close");
        assertLe(branch, GasBounds.TRANSITION_CLOSE, "century close branch exceeds TRANSITION_CLOSE");
        assertLe(GasBounds.TRANSITION_CLOSE + GasBounds.DAILY_PHASE_TAIL + MineFlipGas.CHECK_RESERVE, 10_000_000,
            "declared close plus tail exceeds the 10M chunk limit");
    }

    struct RepricedPhase {
        bool done;
        bool seatDraw;
        uint256 osaka;
        GlamsterdamReprice.Result r;
        NewSlotCensus.Census census;
    }

    /// @dev The century-close branch under Glamsterdam (EIP-8037 / EIP-8038, no reservoir): the
    ///      admitted and declined cold checkpoints of `_checkColdCloseBranch`, each re-priced from
    ///      its recorded accesses; their difference is the branch TRANSITION_CLOSE admits. The
    ///      day's seat draw pays a fresh wallet. `drained` gives every deity the lanes any real
    ///      deity holds at the close; otherwise each deity's level-200 lane word is created here,
    ///      32 slots no reachable close creates. The mock stETH's first stake creates three slots
    ///      (the real token creates one).
    function _checkColdCloseBranchGlamsterdam(bool drained) internal {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(RecycleSessionSeeder).runtimeCode);
        RecycleSessionSeeder host = RecycleSessionSeeder(payable(address(game)));
        host.forceSeatDraw();
        if (drained) host.drainDeityLanes();
        // Both cold runs precede the first recording: once state-diff recording has started, later
        // calls in the test no longer start cold.
        RepricedPhase memory declined = _coldDailyPhase(host, 1_000_000);
        RepricedPhase memory full = _coldDailyPhase(host, 10_000_000);
        _recordDailyPhase(host, 1_000_000, declined);
        _recordDailyPhase(host, 10_000_000, full);
        vm.etch(address(game), realCode);
        assertFalse(declined.done, "a 1M allowance cannot admit the close");
        assertEq(declined.r.stateGas, 0, "the declined checkpoint writes nothing");
        assertTrue(full.done, "the close completed in one checkpoint");
        assertTrue(full.seatDraw, "the seat draw paid its fresh winner");

        uint256 osaka = full.osaka - declined.osaka;
        uint256 exec = full.r.glamsterdamExec - declined.r.glamsterdamExec;
        uint256 total = exec + full.r.stateGas;
        emit log_named_uint("declined checkpoint, cold osaka", declined.osaka);
        emit log_named_uint("admitted checkpoint, cold osaka", full.osaka);
        emit log_named_uint("century close branch, osaka", osaka);
        emit log_named_uint("century close branch, glamsterdam exec", exec);
        emit log_named_uint("century close branch, glamsterdam state (peak)", full.r.stateGas);
        emit log_named_uint("century close branch, glamsterdam total", total);
        emit log_named_uint("new slots", full.r.newSlots);
        emit log_named_uint("value calls", full.r.valueCalls);
        emit log_named_uint("TRANSITION_CLOSE", GasBounds.TRANSITION_CLOSE);
        emit log_named_int("margin", int256(GasBounds.TRANSITION_CLOSE) - int256(total));
        _logCensus(full.census);
        uint256 gameSlots = NewSlotCensus.countOf(full.census, address(game));
        if (drained) assertLe(gameSlots, 4, "with drained lanes the close creates only ticket-queue words");
        else assertGe(gameSlots, 32, "every deity's level-200 lane word is created");
        assertLe(total, GasBounds.TRANSITION_CLOSE, "century close branch exceeds TRANSITION_CLOSE under Glamsterdam");
    }

    /// @dev One cold daily-phase checkpoint, uninstrumented: its Osaka gross gas and outcome.
    function _coldDailyPhase(RecycleSessionSeeder host, uint256 allowance) private returns (RepricedPhase memory m) {
        uint256 base = vm.snapshotState();
        _coolProtocol();
        vm.recordLogs();
        (m.done, m.osaka) = host.measuredDailyPhase(allowance);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == keccak256("SubDrawWon(uint32,uint24,uint24,uint256)")) {
                m.seatDraw = true;
            }
        }
        assertTrue(vm.revertToState(base));
    }

    /// @dev A recorded replay of the same checkpoint from the same pre-state: the Glamsterdam
    ///      re-price of the cold figure and the slots the checkpoint creates.
    function _recordDailyPhase(RecycleSessionSeeder host, uint256 allowance, RepricedPhase memory m) private {
        uint256 base = vm.snapshotState();
        _coolProtocol();
        vm.startStateDiffRecording();
        (bool replayDone,) = host.measuredDailyPhase(allowance);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        assertTrue(vm.revertToState(base));
        assertEq(replayDone, m.done, "the recorded replay takes the same branch");
        uint256 count;
        for (uint256 i; i < acc.length; ++i) if (acc[i].account != address(vm)) acc[count++] = acc[i];
        assembly ("memory-safe") { mstore(acc, count) }
        m.r = GlamsterdamReprice.reprice(m.osaka, acc, address(game));
        m.census = NewSlotCensus.created(acc);
    }

    function _logCensus(NewSlotCensus.Census memory c) private {
        for (uint256 k; k < c.n; ++k) {
            bool seen;
            for (uint256 j; j < k; ++j) if (c.account[j] == c.account[k]) seen = true;
            if (seen) continue;
            emit log_named_address("  new slots in", c.account[k]);
            emit log_named_uint("    count", NewSlotCensus.countOf(c, c.account[k]));
        }
    }

    function _checkColdClose() internal {
        // setUp was a separate transaction. No production storage is read before measurement.
        // A realistic 10M allowance must succeed and complete the close; the engine keeps admitting
        // chunks while the allowance covers the next declared bound, so the call is reported, not
        // bounded (the per-chunk bound is _checkColdCloseChunk).
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineRun{gas: 10_000_000}(0);
        uint256 used = beforeGas - gasleft() + 21_192;
        emit log_named_uint("century refill + 32 deity grants, cold gas including intrinsic", used);
        bool recycled;
        bool seeded;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(sdgnrs) && logs[i].topics[0] == sDGNRS.CenturyRecycled.selector) {
                assertFalse(recycled, "one event per boundary");
                recycled = true;
                assertEq(uint256(logs[i].topics[1]), 100);
                (uint256 percent, uint256 burned, uint256 minted,,,,) = abi.decode(logs[i].data, (uint256,uint256,uint256,uint256,uint256,uint256,uint256));
                assertEq(percent, REFILL_PERCENT);
                assertEq(burned, expectedBurns);
                assertEq(minted, expectedBurns * REFILL_PERCENT / 100);
            }
            if (logs[i].topics[0] == SEED_ARMED_SIG) seeded = true;
        }
        assertTrue(recycled, "nonzero recycle executed in measured transaction");
        assertFalse(seeded, "no century seed at the close");
        assertEq(sdgnrs.totalSupply(), expectedSupply);
        assertEq(sdgnrs.centurySupplyCheckpoint(), expectedSupply);
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        (, bool inJackpot,,,) = game.purchaseInfo_g1027();
        assertFalse(inJackpot, "next purchase phase opened");
        assertFalse(game.rngLocked());
        assertEq(wwxrp.totalSupply(), wwxrpBefore);

        vm.prank(address(game));
        sdgnrs.recycleCentury(100, RNG_WORD + 1);
        assertEq(sdgnrs.totalSupply(), expectedSupply, "repeat is inert");
    }
}

contract SdgnrsRecycleNonemptyPoolsGasTest is SdgnrsRecycleGasFixture {
    function setUp() public { _setupRecycle(false); }
    function testColdCloseWithNonemptyPools() public { _checkColdClose(); }
    function testColdCloseChunkWithNonemptyPools() public { _checkColdCloseChunk(); }
    function testColdCloseBranchWithNonemptyPools() public { _checkColdCloseBranch(); }
    function testColdCloseBranchGlamsterdamWithNonemptyPools() public { _checkColdCloseBranchGlamsterdam(false); }
}

contract SdgnrsRecycleEmptyPoolsGasTest is SdgnrsRecycleGasFixture {
    function setUp() public { _setupRecycle(true); }
    function testColdCloseWithEmptyPoolsAndInventory() public { _checkColdClose(); }
    function testColdCloseChunkWithEmptyPoolsAndInventory() public { _checkColdCloseChunk(); }
    function testColdCloseBranchWithEmptyPoolsAndInventory() public { _checkColdCloseBranch(); }
    function testColdCloseBranchGlamsterdamWithEmptyPoolsAndInventory() public { _checkColdCloseBranchGlamsterdam(false); }
    function testColdCloseBranchGlamsterdamDrainedLanesWithEmptyPoolsAndInventory() public {
        _checkColdCloseBranchGlamsterdam(true);
    }
}
