// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

contract JackpotMergeSeeder is DegenerusGame {
    function seed(bool phase, bool transition, bool last, uint256 holders) external {
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
        for (uint24 lv = 9; lv < 108; ++lv) {
            for (uint256 i; i < holders; ++i) {
                address player = address(uint160(0x1000000 + uint256(lv) * 256 + i));
                _tqAppend(_tqFarFutureKey(lv), uint32(_registerEntryOwner(player, lv) >> OWNER_IDX_SHIFT));
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
        for (uint24 lv = 9; lv < 108; ++lv) {
            for (uint256 i; i < holders; ++i) {
                address player = address(uint160((0x2000000 + uint256(lv) * 256 + i) << 8));
                _tqAppend(_tqFarFutureKey(lv), uint32(_registerEntryOwner(player, lv) >> OWNER_IDX_SHIFT));
            }
        }
    }
}

/// @dev Real request, VRF callback, Game delegates, table, engine, and payouts. Only initial
///      balances/queues are seeded. Run with FOUNDRY_ISOLATE=true for cold transaction gas.
contract JackpotMergeAdvanceTest is DeployProtocol {
    IJackpotBattle private api;
    JackpotBattle private reader;
    uint256 private start;
    uint64 private slot;
    bytes32 private constant ADVANCE = keccak256("Advance(uint8,uint24)");

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
    function _step() private returns (uint8 stage, uint256 gasUsed) {
        vm.recordLogs();
        game.advanceGame{gas: 10_500_000 - 21_064}();
        gasUsed = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        stage = 255;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == ADVANCE) (stage,) = abi.decode(logs[i].data, (uint8,uint24));
        }
    }
    function _requestAndApply() private {
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSelector(IJackpotBattle.lockJackpotBattle.selector));
        (uint8 stage,) = _step(); assertEq(stage, 1, "request");
        assertTrue(game.rngLocked());
        (uint64 locked,,bool started,) = api.jackpotProgress();
        assertEq(locked, slot); assertFalse(started);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 3456789);
        for (uint256 i; i < 20; ++i) {
            (stage,) = _step();
            if (stage != 5) break; // already committed ticket work may drain before RNG apply
        }
        assertEq(stage, 18, "RNG apply must stand alone");
        (,,started,) = api.jackpotProgress(); assertFalse(started);
    }
    function _drain(bool phase, bool delay) private {
        if (delay) vm.warp(start + 2 days);
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSelector(IJackpotBattle.appendJackpotBattle.selector));
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSelector(IJackpotBattle.advanceJackpotBattle.selector));
        (uint8 stage,uint256 maxGas) = _step(); assertEq(stage, phase ? 16 : 17);
        (CrapsBattleStorage.JackpotRound memory r,,uint64 cursor) = reader.jackpotBattleOf(slot);
        assertGt(r.word, 0); assertGt(cursor, 0, "the sealing call settles on what its draw left");
        uint256 count;
        for (; count < 200; ++count) {
            (,,,bool complete) = api.jackpotProgress();
            if (complete) break;
            assertTrue(game.rngLocked()); assertTrue(game.advanceDue());
            uint256 gasUsed;
            (stage,gasUsed) = _step();
            if (gasUsed > maxGas) maxGas = gasUsed;
            assertEq(stage, phase ? 16 : 17);
        }
        assertLt(count, 200, "battle stalled");
        emit log_named_uint("largest jackpot tx (incl intrinsic under isolate)", maxGas);
        emit log_named_uint("settlement transactions", count);
        for (uint256 i; i < 30 && game.rngLocked(); ++i) _step();
        assertFalse(game.rngLocked(), "daily chain never released");
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
        assertEq(added, 50_000 ether, "level-6 floor");
        _drain(false,false);
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertEq(r.awardTarget, 5);
        assertEq(r.drawnUnits, 5);
    }
    /// @dev 42 paid seats and a large award field drawn over one low byte, driven to completion.
    ///      Every jackpot transaction must fit 10M; only the sealing chunk may settle.
    function _driveChunks(uint256 pool) private returns (uint256 maxGas, uint256 draws, uint256 settles, uint64 sealCursor) {
        _prepare(false,false,false,40,8);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(JackpotMergeSeeder).runtimeCode);
        JackpotMergeSeeder(payable(address(game))).widen(20, pool);
        vm.etch(address(game), code);
        _requestAndApply();
        for (uint256 i; i < 100; ++i) {
            (,, bool started, bool complete) = api.jackpotProgress();
            if (complete) break;
            (uint8 stage, uint256 gasUsed) = _step();
            assertEq(stage, 17);
            if (gasUsed > maxGas) maxGas = gasUsed;
            if (started) {
                ++settles;
                continue;
            }
            ++draws;
            (,,uint64 cursor) = reader.jackpotBattleOf(slot);
            (,,bool sealedNow,) = api.jackpotProgress();
            if (sealedNow) sealCursor = cursor;
            else assertEq(cursor, 0, "an unsealed field settled");
        }
        assertLe(maxGas, 10_000_000, "a jackpot transaction crossed 10M");
        emit log_named_uint("largest jackpot tx (incl intrinsic under isolate)", maxGas);
        emit log_named_uint("draw transactions", draws);
        emit log_named_uint("settlement transactions", settles);
        for (uint256 i; i < 30 && game.rngLocked(); ++i) _step();
        assertFalse(game.rngLocked(), "daily chain never released");
    }
    function test_FullDrawChunksAndSettleCallsStayUnderTenMillion() public {
        (, uint256 draws, uint256 settles, uint64 sealCursor) = _driveChunks(30_000 ether);
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertEq(r.drawnUnits, 500, "award cap");
        assertEq(draws, 4, "150-entry draw chunks");
        assertLe(settles, 10, "1,500-unit settle calls");
        // The 50-entry sealing chunk is charged 110 + 500 units and settles on the other 890.
        assertGt(sealCursor, 0, "the sealing call left its budget unused");
    }
    function test_SealingCallSettlesExactlyWhatItsDrawLeft() public {
        uint256 snap = vm.snapshotState();
        (,,, uint64 sealCursor) = _driveChunks(30_000 ether);
        assertTrue(vm.revertToState(snap));
        _prepare(false,false,false,40,8);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(JackpotMergeSeeder).runtimeCode);
        JackpotMergeSeeder(payable(address(game))).widen(20, 30_000 ether);
        vm.etch(address(game), code);
        _requestAndApply();
        for (uint256 i; i < 3; ++i) _step();
        vm.mockCall(address(crapsBattle), abi.encodeWithSelector(IJackpotBattle.advanceJackpotBattle.selector),
            abi.encode(false));
        _step();
        vm.clearMockedCalls();
        (,, bool started,) = api.jackpotProgress();
        (,,uint64 cursor) = reader.jackpotBattleOf(slot);
        assertTrue(started, "the fourth chunk seals");
        assertEq(cursor, 0);
        // 1,500 less the 50-entry chunk's 110 + 10 * 50.
        vm.prank(address(game)); api.advanceJackpotBattle(890);
        (,,cursor) = reader.jackpotBattleOf(slot);
        assertEq(cursor, sealCursor, "the sealing call's settle budget");
    }
    function test_FullSealingChunkLeavesNoSettleBudget() public {
        (, uint256 draws,, uint64 sealCursor) = _driveChunks(17_900 ether);
        (CrapsBattleStorage.JackpotRound memory r,,) = reader.jackpotBattleOf(slot);
        assertGe(r.drawnUnits, 439, "sealing chunk of at least 139 entries");
        assertLe(r.drawnUnits, 450);
        assertEq(draws, 3);
        // 110 + 10 per entry reaches 1,500 at 139 entries: a ~7M draw leaves nothing to settle.
        assertEq(sealCursor, 0, "the sealing call settled past its draw charge");
    }
    function test_EmptyAwardQueuesStillClosePaidField() public {
        _prepare(false,false,false,3,0); _requestAndApply(); _drain(false,false);
    }
    function test_InitRevertPreservesLockAndRetries() public {
        _prepare(false,false,false,3,8); _requestAndApply();
        vm.mockCallRevert(ContractAddresses.JACKPOT_BATTLE,
            abi.encodeWithSelector(JackpotBattle.prepareJackpotBattle.selector), hex"deadbeef");
        vm.expectRevert(bytes4(0xdeadbeef)); game.advanceGame();
        assertTrue(game.rngLocked());
        vm.clearMockedCalls(); _drain(false,false);
    }
}
