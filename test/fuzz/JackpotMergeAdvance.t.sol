// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract JackpotMergeSeeder is DegenerusGame, WalletSeed {
    function seed(bool phase, bool transition, bool last, uint256 holders) external {
        // The synthetic jump to level 6 models levels 1..6 as drained: free their recycled roots.
        TQ.retireCompleted(address(this), 6);
        uint24 day = _simulatedDayIndex();
        level = 6;
        purchaseStartDay = day - 2;
        dailyIdx = day - 1;
        jackpotPhaseFlag = phase;
        phaseTransitionActive = transition;
        lastPurchaseDay = last;
        jackpotFlags = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngLockedFlag = false;
        rngRequestTime = 0;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 0;
        dailyTicketBudgetsPacked = 0;
        dailyJackpotCoinTicketsPending = false;
        jackpotCounter = 0;
        levelPrizePool[5] = 1_000 ether;
        levelPrizePool[6] = 1_000 ether;
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = uint128(200 ether);
        _recordDailyRng(day - 1, 123456);
        // The battle draws levels mintCeiling + 1 .. + 99 = 8..106. Level 107 is outside it, and
        // its recycled root is held by level 7's live far-future queue.
        for (uint24 lv = 9; lv < 107; ++lv) {
            for (uint256 i; i < holders; ++i) {
                address player = address(uint160(0x1000000 + uint256(lv) * 256 + i));
                _tqAppend(_tqFarFutureKey(lv), _seedWallet(player));
            }
        }
    }
    function shrinkPools(uint256 amount) external {
        levelPrizePool[5] = amount;
        levelPrizePool[6] = amount;
    }
    /// @dev More holders on every level, all distinct wallets on one low byte, so each draw chunk's
    ///      dedupe takes its exact scan.
    function widen(uint256 holders, uint256 pool) external {
        levelPrizePool[5] = pool;
        levelPrizePool[6] = pool;
        for (uint24 lv = 9; lv < 107; ++lv) {
            for (uint256 i; i < holders; ++i) {
                address player = address(uint160((0x2000000 + uint256(lv) * 256 + i) << 8));
                _tqAppend(_tqFarFutureKey(lv), _seedWallet(player));
            }
        }
    }
}

/// @dev Real request, VRF callback, Game delegates, table, engine, and payouts. Only initial
///      balances/queues are seeded. Run with FOUNDRY_ISOLATE=true for cold transaction gas.
///      The engine composes every admitted checkpoint into one call, so each call is given a
///      realistic allowance chosen for the step under test: the smallest ladder rung that admits
///      work (so the indivisible word application runs without a following battle group), a 5M
///      draw-call allowance admitting whole 50-entry groups, and 10.5M for metered settle calls.
contract JackpotMergeAdvanceTest is DeployProtocol {
    IJackpotBattle private api;
    JackpotBattle private reader;
    uint256 private start;
    uint64 private slot;
    uint256 private requestId;
    bytes32 private constant ADVANCE = keccak256("Advance(uint8,uint24)");
    /// @dev Admits bounded 50-entry checkpoints; cheaper storage can fit multiple groups.
    uint256 private constant DRAW_GAS = 5_000_000;
    uint256 private constant SETTLE_GAS = 10_500_000 - 21_192;

    function setUp() public {
        _deployProtocol();
        api = IJackpotBattle(address(crapsBattle));
        reader = JackpotBattle(address(crapsBattle));
        start = (399 + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;
        vm.deal(address(game), 10_000 ether);
    }
    function _prepare(bool phase, bool transition, bool last, uint256 paid, uint256 holders) private {
        vm.warp(start);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(JackpotMergeSeeder).runtimeCode);
        JackpotMergeSeeder(payable(address(game))).seed(phase, transition, last, holders);
        vm.etch(address(game), code);
        vm.warp(start - 1 days);
        vm.prank(address(game)); crapsBattle.openBonusDay();
        uint24 day = crapsBattle.currentDayIndex();
        slot = uint64(uint256(day) * 8 + 6);
        for (uint256 i; i < paid; ++i) {
            address player = address(uint160(0x900000 + i));
            vm.prank(address(game)); coin.mintForGame(player, 100_000 ether);
            vm.prank(player); crapsBattle.enterBonusBattle(5, 1 | (1 << 9) | (1 << 12), 1);
        }
        vm.warp(start);
    }
    /// @dev One call at `gas`; every progress marker of the call, in order, and its gas.
    function _step(uint256 gas) private returns (uint8[] memory stages, uint256 gasUsed) {
        vm.recordLogs();
        game.mineFlip{gas: gas}(0);
        gasUsed = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE) ++n;
        stages = new uint8[](n);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE) (stages[n++],) = abi.decode(logs[i].data, (uint8,uint24));
        }
    }
    /// @dev The smallest rung of a realistic ladder that admits work.
    function _minimalStep() private returns (uint8[] memory stages, uint256 gasUsed) {
        uint256[7] memory ladder = [uint256(1_500_000), 2_500_000, 3_000_000, 3_500_000, 4_000_000, 4_500_000, 10_500_000];
        for (uint256 r; r < ladder.length; ++r) {
            try this.stepAt(ladder[r]) returns (uint8[] memory s, uint256 g) {
                return (s, g);
            } catch (bytes memory err) {
                assertEq(bytes4(err), MineFlipGas.InsufficientExecutionGas.selector, "only an allowance refusal retries");
            }
        }
        revert("a realistic allowance must make progress");
    }
    function stepAt(uint256 gas) external returns (uint8[] memory, uint256) {
        require(msg.sender == address(this));
        return _step(gas);
    }
    function _requestAndApply() private {
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSelector(IJackpotBattle.lockJackpotBattle.selector));
        // The synthetic day-400 jump leaves expired Craps maintenance (one checkpoint per call)
        // ahead of the daily request.
        uint256 before = mockVRF.lastRequestId();
        uint8[] memory stages;
        for (uint256 i; i < 1000 && mockVRF.lastRequestId() == before; ++i) {
            assertFalse(game.rngLocked(), "no lock before the request");
            (stages,) = _step(SETTLE_GAS);
        }
        assertEq(stages.length, 1, "request");
        assertEq(stages[0], 1, "request");
        assertTrue(game.rngLocked());
        (uint64 locked,,bool started,) = api.jackpotProgress();
        assertEq(locked, slot); assertFalse(started);
        requestId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(requestId, 3456789);
        bool applied;
        for (uint256 i; i < 20 && !applied; ++i) {
            (stages,) = _minimalStep();
            for (uint256 k; k < stages.length; ++k) {
                if (stages[k] == 18) {
                    applied = true;
                    assertEq(k, stages.length - 1, "RNG apply must stand alone");
                } else {
                    assertEq(stages[k], 5, "already committed ticket work may drain before RNG apply");
                }
            }
        }
        assertTrue(applied, "the word applied");
        (,,started,) = api.jackpotProgress(); assertFalse(started);
    }
    function _drain(bool phase, bool delay) private {
        if (delay) vm.warp(start + 2 days);
        uint8 battleStage = phase ? 16 : 17;
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSelector(IJackpotBattle.appendJackpotBattle.selector));
        // Settlement runs through the metered daily battle worker.
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSignature("runDailyBattleWork(uint256)"));
        uint256 maxGas;
        uint256 count;
        for (; count < 400; ++count) {
            (uint64 active,,bool sealedField, bool complete) = api.jackpotProgress();
            // A completing call may compose the rest of the day and, past midnight, the next
            // day's request, which locks the next battle.
            if (complete || active != slot) break;
            assertTrue(game.rngLocked()); assertTrue(game.advanceDue());
            (uint8[] memory stages, uint256 gasUsed) = _step(sealedField ? SETTLE_GAS : DRAW_GAS);
            if (gasUsed > maxGas) maxGas = gasUsed;
            assertGt(stages.length, 0, "every battle call progresses");
            assertEq(stages[0], battleStage, "the battle runs from its own stage");
            (active,,,complete) = api.jackpotProgress();
            // Only the call that completes the field may go on to the day's later stages.
            if (!complete && active == slot) for (uint256 k; k < stages.length; ++k) assertEq(stages[k], battleStage);
        }
        assertLt(count, 400, "battle stalled");
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertGt(r.word, 0, "the field sealed with its word");
        emit log_named_uint("largest jackpot battle call (incl intrinsic under isolate)", maxGas);
        emit log_named_uint("battle calls", count);
        for (uint256 i; i < 60 && game.rngLocked() && mockVRF.lastRequestId() == requestId; ++i) _step(SETTLE_GAS);
        // Released: unlocked, or (past midnight) the next day's fresh request already took the lock.
        assertTrue(!game.rngLocked() || mockVRF.lastRequestId() != requestId, "daily chain never released");
        if (delay) assertEq(game.rngWordForDay(401), 0, "reused known word");
    }
    function test_PurchasePaidAndAwardedBatchesThenUnlock() public {
        _prepare(false,false,false,40,8); _requestAndApply(); _drain(false,false);
    }
    function test_JackpotPhasePaidAndAwardedBatchesThenUnlock() public {
        _prepare(true,false,false,40,8); _requestAndApply(); _drain(true,false);
    }
    function test_LastPurchasePromotionKeepsFrozenField() public {
        _prepare(false,false,true,3,8); _requestAndApply(); _drain(false,false);
    }
    function test_TransitionDoesNotSkipBattle() public {
        _prepare(true,true,false,3,8); _requestAndApply(); _drain(true,false);
    }
    function test_MidnightProcessingKeepsLockAndRequestWord() public {
        _prepare(false,false,false,3,8); _requestAndApply(); _drain(false,true);
    }
    function test_SmallPoolIsRaisedToTheFloor() public {
        _prepare(false,false,false,3,8);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(JackpotMergeSeeder).runtimeCode);
        JackpotMergeSeeder(payable(address(game))).shrinkPools(1 ether);
        vm.etch(address(game), code);
        _requestAndApply();
        (, uint256 added,,) = api.jackpotProgress();
        assertEq(added, 50_000 * reader.jackpotEntryPriceOf(slot) / 8_000, "scaled level-6 floor");
        _drain(false,false);
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertEq(r.awardTarget, 5);
        assertEq(r.drawnUnits, 5);
    }
    /// @dev 42 paid seats and a large award field drawn over one low byte, driven to completion:
    ///      whole 50-entry groups per draw call, metered settle calls. Each call succeeds and makes
    ///      progress; the field never settles before it seals, and the sealing call settles nothing.
    function _driveChunks(uint256 pool) private returns (uint256 maxDraw, uint256 draws, uint256 settles, uint64 sealCursor) {
        _prepare(false,false,false,40,8);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(JackpotMergeSeeder).runtimeCode);
        JackpotMergeSeeder(payable(address(game))).widen(20, pool);
        vm.etch(address(game), code);
        _requestAndApply();
        uint256 maxSettle;
        for (uint256 i; i < 400; ++i) {
            (,, bool started, bool complete) = api.jackpotProgress();
            if (complete) break;
            (CrapsBattleStorage.JackpotRound memory beforeRound,,) = reader.jackpotBattleOf(slot);
            (uint8[] memory stages, uint256 gasUsed) = _step(started ? SETTLE_GAS : DRAW_GAS);
            assertEq(stages[0], 17);
            if (started) {
                if (gasUsed > maxSettle) maxSettle = gasUsed;
                ++settles;
                continue;
            }
            if (gasUsed > maxDraw) maxDraw = gasUsed;
            ++draws;
            (,,uint64 cursor) = reader.jackpotBattleOf(slot);
            (,,bool sealedNow,) = api.jackpotProgress();
            (CrapsBattleStorage.JackpotRound memory afterRound,,) = reader.jackpotBattleOf(slot);
            uint256 appended = afterRound.drawnUnits - beforeRound.drawnUnits;
            assertGt(appended, 0, "every draw transaction appends awards");
            assertLe(afterRound.drawnUnits, afterRound.awardTarget, "draw cannot overfill its target");
            if (sealedNow) sealCursor = cursor;
            else {
                assertEq(appended % 50, 0, "an unsealed call commits whole draw groups");
                assertEq(cursor, 0, "an unsealed field settled");
            }
        }
        (,,, bool done) = api.jackpotProgress();
        assertTrue(done, "battle completed");
        // Retain the measured whole-call gas guard even when improved packing admits multiple
        // checkpoints. The production worker independently reserves every group's full bound.
        uint256 envelope = GasBounds.JACKPOT_BATTLE_DRAW + GasBounds.DAILY_PHASE_TAIL
            + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN;
        emit log_named_uint("declared draw admission envelope", envelope);
        assertLe(maxDraw, envelope, "draw transaction stays inside the retained gas guard");
        emit log_named_uint("largest draw call (incl intrinsic under isolate)", maxDraw);
        emit log_named_uint("largest settle call at 10.5M (incl intrinsic under isolate)", maxSettle);
        emit log_named_uint("draw transactions", draws);
        emit log_named_uint("settlement transactions", settles);
        for (uint256 i; i < 60 && game.rngLocked() && mockVRF.lastRequestId() == requestId; ++i) _step(SETTLE_GAS);
        assertTrue(!game.rngLocked() || mockVRF.lastRequestId() != requestId, "daily chain never released");
    }
    function test_FullDrawChunksAndSettleCallsStayUnderTenMillion() public {
        (, uint256 draws, uint256 settles, uint64 sealCursor) = _driveChunks(30_000 ether);
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertEq(r.drawnUnits, 500, "award cap");
        assertGt(draws, 0, "the field was drawn");
        assertLe(draws, 10, "500 awards finish within ten 50-entry checkpoints");
        assertGt(settles, 0, "metered settle calls");
        assertLe(settles, 10, "metered settle calls at 10.5M");
        // The sealing draw returns before settlement; metered calls settle afterwards
        // (was: the sealing call settled on its unused 1,500-unit budget).
        assertEq(sealCursor, 0, "the sealing call settles nothing");
    }
    /// @dev Was test_SealingCallSettlesExactlyWhatItsDrawLeft (1,500-unit settle budget, gone with
    ///      the metered engine). Settlement is now a pure function of the allowance: the sealing
    ///      call settles nothing, and replaying the first settle call at the same allowance from
    ///      the same state settles the same prefix.
    function test_SealingCallSettlesExactlyWhatItsDrawLeft() public {
        _prepare(false,false,false,40,8);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(JackpotMergeSeeder).runtimeCode);
        JackpotMergeSeeder(payable(address(game))).widen(20, 30_000 ether);
        vm.etch(address(game), code);
        _requestAndApply();
        for (uint256 i; i < 10; ++i) {
            (,, bool sealedField,) = api.jackpotProgress();
            if (sealedField) break;
            _step(DRAW_GAS);
        }
        (,, bool started,) = api.jackpotProgress();
        (,,uint64 cursor) = reader.jackpotBattleOf(slot);
        assertTrue(started, "the draw calls seal within ten checkpoints");
        assertEq(cursor, 0, "the sealing call settles nothing");
        uint256 snap = vm.snapshotState();
        _step(SETTLE_GAS);
        (,,uint64 first) = reader.jackpotBattleOf(slot);
        assertGt(first, 0, "the first metered call settles");
        assertTrue(vm.revertToState(snap));
        _step(SETTLE_GAS);
        (,,cursor) = reader.jackpotBattleOf(slot);
        assertEq(cursor, first, "the settled prefix depends only on the allowance");
    }
    function test_FullSealingChunkLeavesNoSettleBudget() public {
        (, uint256 draws,, uint64 sealCursor) = _driveChunks(17_900 ether);
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertGe(r.drawnUnits, 439, "sealing chunk of at least 139 entries");
        assertLe(r.drawnUnits, 450);
        assertGt(draws, 0);
        assertLe(draws, 9, "at most nine 50-entry checkpoints fill this field");
        assertEq(sealCursor, 0, "the sealing call settled past its draw charge");
    }
    function test_EmptyAwardQueuesStillClosePaidField() public {
        _prepare(false,false,false,3,0); _requestAndApply(); _drain(false,false);
    }
    function test_InitRevertPreservesLockAndRetries() public {
        _prepare(false,false,false,3,8); _requestAndApply();
        vm.mockCallRevert(ContractAddresses.JACKPOT_BATTLE,
            abi.encodeWithSelector(JackpotBattle.prepareJackpotBattle.selector), hex"deadbeef");
        vm.expectRevert(bytes4(0xdeadbeef)); game.mineFlip{gas: DRAW_GAS}(0);
        assertTrue(game.rngLocked());
        vm.clearMockedCalls(); _drain(false,false);
    }
}
