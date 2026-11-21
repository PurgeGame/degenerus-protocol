// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {ActivityCurveLib} from "../../contracts/libraries/ActivityCurveLib.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";

/// @dev Three sealed 100-box orders ensure work exceeds the unpaid million-gas floor.
///      Removed before execution/export: the benchmark runs only production bytecode.
contract XaNativeMinerSeed is DegenerusGame {
    function seed(address player, address miner) external {
        _registerWallet(player, type(uint256).max);
        _registerWallet(miner, type(uint256).max);
        level = 99;
        dailyIdx = _wallDay();
        dailyComplete = false;
        rngRequestDay = dailyIdx;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
        purchaseStartDay = dailyIdx;
        _afkingResetDay = dailyIdx;
        subsFullyProcessed = true;
        _clearRngRequest();
        _setRngComplete(false);
        _setRngSessionPublished(true);
        rngLockedFlag = false;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 12345;
        ticketsFullyProcessed = true;
        humanReadComplete = false;
        _pendingBoxCount = 0;
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, 0);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 0);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        (uint256 word,) = _decodeBoxOrder(BoxOrderLib.boSmalls(100), 100);
        word |= uint256(_walletIdOf(player))
            | BoxOrderLib.scoreCode(ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) << LB_SCORE_SHIFT;
        word |= word << LB_ENTRY_BITS | word << (2 * LB_ENTRY_BITS);
        uint256[] storage queue = boxQueue[_rngReadBuffer()];
        assembly ("memory-safe") {
            mstore(0, queue.slot)
            sstore(keccak256(0, 32), word)
        }
        boxReadCount = 3;
        boxCursor = 0;
        _setCurrentPrizePool(10_000 ether);
        _setPrizePools(10_000 ether, 10_000 ether);
    }
}

/// @dev The same day with an undrained ticket cohort and a mid-day latch instead of the box
///      orders: the ticket checkpoint writes both, then the read cohort certifies.
contract XaEngineBoundarySeed is XaNativeMinerSeed {
    function seedBoundary(address player, address miner) external {
        this.seed(player, miner);
        ticketsFullyProcessed = false;
        humanReadComplete = true;
        boxReadCount = 0;
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
    }
}

/// @dev Delegatecalled in place of a worker module: no storage, a fixed execution burn.
contract EngineStubWorker {
    uint256 private immutable burn;

    constructor(uint256 burn_) { burn = burn_; }

    function runHumanBoxWork_g315(uint256) external view returns (bool, bool, uint256) {
        uint256 stop = gasleft() - burn;
        while (gasleft() > stop) {}
        return (true, false, 0);
    }

    function runTicketWork_g1150(uint24, uint256) external pure returns (bool, bool, uint256) {
        return (true, true, 0);
    }
}

/// @dev Occupies a wallet's ring word for the next credit's page with a live later page, so the
///      next credit spills into a fresh overflow word and re-flags the ring word.
contract XaStakeSpillSeed is Coinflip {
    function occupy(uint32 id) external {
        uint24 page = (requestedDailyIdx + 1) / 7;
        coinflipStakeRing[id][page % 15] = (uint256(page + 16) << 224) | 1;
    }
}

contract XaNativeMinerTest is DeployProtocol {
    address private constant PLAYER = address(0xB0A100);
    address private constant MINER = address(0xB0A200);
    uint256 private constant CAP = 6_000_000;
    // Burned by the stub worker so the call earns a reward above the unpaid million.
    uint256 private constant STUB_BURN = 1_500_000;
    bytes4 private constant CREDIT = bytes4(keccak256("creditFlip_g317(uint32,uint256)"));
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    uint8 private constant ACTION_TICKETS = 4;
    uint8 private constant ACTION_HUMAN_BOXES = 9;

    function test_NativePositiveMinerReward() public {
        _deployProtocol(false);
        vm.warp(21_000 days + 82_621);
        vm.deal(address(game), 50_000 ether);
        bytes memory production = address(game).code;
        vm.etch(address(game), type(XaNativeMinerSeed).runtimeCode);
        XaNativeMinerSeed(payable(address(game))).seed(PLAYER, MINER);
        vm.etch(address(game), production);
        _syncCoinflipFixtureDay(game.currentDayView_g542950());
        this.mineAsMiner();
    }

    /// @dev Isolation resets basefee at an external transaction boundary; set it inside
    /// this adapter before the nested production call.
    function mineAsMiner() external {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei);
        vm.prank(MINER);
        game.mineRun(0);
        assertGt(coinflip.coinflipAmount(MINER), 0, "fixture must earn a positive miner stake");
    }

    /// @dev The mining call's own frame gas, priced like mineAsMiner.
    function mineMeasured() external returns (uint256 frame) {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei);
        vm.prank(MINER);
        game.mineRun{gas: CAP}(0);
        VmSafe.Gas memory g = vm.lastCallGas();
        frame = uint256(g.gasLimit) - uint256(g.gasRemaining);
    }

    function _engineFixture(bool boundary) private {
        _deployProtocol(false);
        vm.warp(21_000 days + 82_621);
        vm.deal(address(game), 50_000 ether);
        bytes memory production = address(game).code;
        if (boundary) {
            vm.etch(address(game), type(XaEngineBoundarySeed).runtimeCode);
            XaEngineBoundarySeed(payable(address(game))).seedBoundary(PLAYER, MINER);
        } else {
            vm.etch(address(game), type(XaNativeMinerSeed).runtimeCode);
            XaNativeMinerSeed(payable(address(game))).seed(PLAYER, MINER);
        }
        vm.etch(address(game), production);
        _syncCoinflipFixtureDay(game.currentDayView_g542950());
    }

    /// @dev Cold mining call, then a recorded replay from the same pre-state; leaves the cold
    ///      call's post-state. `used` is the engine's own MinerWork measurement, taken before
    ///      its return and reward.
    function _engineRun() private
        returns (uint256 frame, uint8 first, uint256 used, uint256 reward, VmSafe.AccountAccess[] memory acc)
    {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "requires isolation");
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        frame = this.mineMeasured();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == MINER_WORK) {
                (first, used, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
            }
        }
        assertGt(used, 0, "MinerWork reported");
        uint256 coldPost = vm.snapshotState();
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        this.mineMeasured();
        acc = vm.stopAndReturnStateDiff();
        vm.stopMappingRecording();
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(vm)) continue;
            if (acc[i].account == address(this) && acc[i].kind != VmSafe.AccountAccessKind.Resume) continue;
            assertFalse(acc[i].reverted, "repricing assumes successful frames");
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        assertTrue(vm.revertToState(coldPost));
        vm.deleteStateSnapshot(coldPost);
        vm.deleteStateSnapshot(snap);
    }

    /// @notice ENGINE_RETURN: everything after the engine's MinerWork measurement, the reward
    ///         reads, the one caller credit into Coinflip and both events, plus the call's
    ///         dispatch into the miner module. A stub worker burns gas without touching storage,
    ///         so the credit reaches Coinflip cold.
    function _engineReturn(bool spill, string memory label) private {
        _engineFixture(false);
        vm.etch(ContractAddresses.GAME_AFKING_MODULE, address(new EngineStubWorker(STUB_BURN)).code);
        if (spill) {
            bytes memory code = address(coinflip).code;
            vm.etch(address(coinflip), type(XaStakeSpillSeed).runtimeCode);
            XaStakeSpillSeed(address(coinflip)).occupy(game.walletIdOf_g3120(MINER));
            vm.etch(address(coinflip), code);
        }
        (uint256 frame, uint8 first, uint256 used, uint256 reward, VmSafe.AccountAccess[] memory acc) = _engineRun();
        assertEq(first, ACTION_HUMAN_BOXES, "one box checkpoint ran");
        assertGt(reward, 0, "the miner is paid");
        assertGt(coinflip.coinflipAmount(MINER), 0, "the reward is staked");
        uint256 credit = acc.length;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].kind == VmSafe.AccountAccessKind.Call && acc[i].account == ContractAddresses.COINFLIP
                && acc[i].data.length >= 4 && bytes4(acc[i].data) == CREDIT) credit = i;
        }
        assertLt(credit, acc.length, "the reward credit is recorded");
        // The credit starts at the call's code-size check: Coinflip is untouched before it.
        uint256 k;
        while (acc[k].account != ContractAddresses.COINFLIP) ++k;
        assertTrue(k == credit || (k + 1 == credit && acc[k].kind == VmSafe.AccountAccessKind.Extcodesize),
            "Coinflip is cold at the credit");
        for (uint256 i; i < k; ++i) {
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                assertTrue(acc[i].storageAccesses[j].account != ContractAddresses.COINFLIP, "Coinflip storage is cold");
            }
        }
        VmSafe.AccountAccess[] memory head = new VmSafe.AccountAccess[](k);
        for (uint256 i; i < k; ++i) head[i] = acc[i];
        GlamsterdamReprice.Result memory all = GlamsterdamReprice.reprice(frame, acc, address(game));
        GlamsterdamReprice.Result memory pre = GlamsterdamReprice.reprice(frame, head, address(game));
        uint256 osaka = frame - used;
        // The mining call's cold dispatch into the miner module is in `osaka`, its 400 in `pre`.
        uint256 exec = uint256(int256(osaka) + all.execDelta - pre.execDelta) + 400;
        uint256 state = all.finalStateGas - pre.finalStateGas;
        emit log_named_string("unit", label);
        emit log_named_uint("osaka", osaka);
        emit log_named_uint("glamsterdam_exec", exec);
        emit log_named_uint("glamsterdam_state", state);
        emit log_named_uint("glamsterdam_total", exec + state);
        emit log_named_uint("new_slots", all.newSlots - pre.newSlots);
        emit log_named_uint("bound", Bounds.ENGINE_RETURN);
        assertLe(osaka, Bounds.ENGINE_RETURN, "Osaka return and credit fit ENGINE_RETURN");
        assertLe(exec + state, Bounds.ENGINE_RETURN, "Glamsterdam return and credit fit ENGINE_RETURN");
    }

    function test_GlamsterdamEngineReturnFreshCredit() public { _engineReturn(false, "engine_return_fresh_credit"); }

    function test_GlamsterdamEngineReturnSpillCredit() public { _engineReturn(true, "engine_return_spill_credit"); }

    /// @notice ENGINE_BOUNDARY: the engine's whole metered loop with a no-op ticket worker, so
    ///         everything in MinerWork's figure is engine code: three selections, the ticket
    ///         dispatch with its checkpoint writes (cohort certificate and mid-day latch) and the
    ///         read-cohort certification. One worker boundary is a part of it.
    function test_GlamsterdamEngineBoundaries() public {
        _engineFixture(true);
        // Craps maintenance is current, so the last selection is Idle.
        _seedCrapsFixtureCursor(uint24(uint256(vm.load(address(game), bytes32(0))) >> 24));
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new EngineStubWorker(0)).code);
        (uint256 frame, uint8 first, uint256 used, uint256 reward, VmSafe.AccountAccess[] memory acc) = _engineRun();
        assertEq(first, ACTION_TICKETS, "the ticket checkpoint ran first");
        assertEq(reward, 0, "below the unpaid million");
        assertTrue(game.rngComplete(), "the read cohort certified");
        GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(frame, acc, address(game));
        uint256 exec = uint256(int256(used) + r.execDelta);
        emit log_named_string("unit", "engine_loop_three_selections_two_boundaries");
        emit log_named_uint("osaka", used);
        emit log_named_uint("glamsterdam_exec", exec);
        emit log_named_uint("glamsterdam_state", r.stateGas);
        emit log_named_uint("glamsterdam_total", exec + r.stateGas);
        emit log_named_uint("first_changes", r.firstChanges);
        emit log_named_uint("bound", Bounds.ENGINE_BOUNDARY);
        assertLe(used, Bounds.ENGINE_BOUNDARY, "Osaka engine loop fits ENGINE_BOUNDARY");
        assertLe(exec + r.stateGas, Bounds.ENGINE_BOUNDARY, "Glamsterdam engine loop fits ENGINE_BOUNDARY");
    }
}
