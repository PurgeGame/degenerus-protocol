// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PurchaseDailyFixture, PurchaseDailySeeder} from "../gas/PurchaseDailyWorstCase.t.sol";

contract PurchaseBattleStagesTest is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(128, 0, FF_HOLDERS, NEXT_POOL_QUIET, PREV_POOL_OPEN25));
    }

    function _startDaily() private {
        (, Tally memory t) = _measure();
        assertEq(t.stage, STAGE_PURCHASE_DAILY);
        assertEq(t.ethWins, PURCHASE_ETH_WINNERS);
        assertEq(t.battleRuns + t.ticketWins, 0);
        assertTrue(game.rngLocked());
        assertTrue(game.advanceDue());
    }

    function _battleDigest() private view returns (bytes32 digest) {
        for (uint256 i; i < lastLogs.length; ++i) {
            Vm.Log storage l = lastLogs[i];
            if (l.topics[0] == BATTLE_RUN_SIG || l.topics[0] == BATTLE_POT_SIG
                || l.topics[0] == keccak256("JackpotBattleMultiplier(uint24,uint256,uint256)")) {
                digest = keccak256(abi.encode(digest, l.topics, l.data));
            }
        }
    }

    function _assertNoFreshRng() private view {
        for (uint256 i; i < lastLogs.length; ++i) {
            bytes32 sig = lastLogs[i].topics[0];
            assertTrue(sig != keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)"));
            assertTrue(sig != keccak256("DailyWinningTraits(uint24,uint32)"));
        }
    }

    function test_SeparateStagesHoldLockAndDoNotReplayBattle() public {
        _startDaily();
        _measureBattleStage(50);
        _assertNoFreshRng();
        assertTrue(game.rngLocked(), "tickets still pending");
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
        assertGt(tickets.ticketWins, 0);
        assertEq(tickets.ethWins + tickets.battleRuns + tickets.flipWins, 0);
        assertFalse(game.rngLocked());
        vm.recordLogs();
        (bool ok,) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        // A same-day no-work call may revert; either outcome must not replay the draw.
        ok;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) assertTrue(logs[i].topics[0] != BATTLE_RUN_SIG);
    }

    function test_MidnightUsesSameFieldBoardsAndWord() public {
        _startDaily();
        uint24 day = game.currentDayView();
        uint256 word = game.rngWordForDay(day);
        uint256 snap = vm.snapshotState();
        _measureBattleStage(50);
        bytes32 sameDay = _battleDigest();
        vm.revertToState(snap);
        vm.warp(block.timestamp + 2 days);
        vm.prank(address(0xBEEF));
        vm.expectRevert(CrapsBattle.BetLocked.selector);
        crapsBattle.setPreferredBoard(3);
        _measureBattleStage(50);
        _assertNoFreshRng();
        assertEq(_battleDigest(), sameDay, "deferred fill changed its result");
        assertEq(game.rngWordForDay(day), word);
        assertEq(game.rngWordForDay(day + 1), 0, "revealed word must not resolve a later day");
        assertTrue(game.rngLocked());
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
        assertFalse(game.rngLocked());
        vm.prank(address(0xBEEF)); crapsBattle.setPreferredBoard(3);
        assertEq(crapsBattle.preferredBoardOf(address(0xBEEF)), 3);
    }

    function test_FailedBattleRetainsPendingStageForRetry() public {
        _startDaily();
        vm.mockCallRevert(ContractAddresses.JACKPOT_BATTLE, abi.encodeWithSelector(JackpotBattle.resolve.selector), hex"deadbeef");
        vm.expectRevert(bytes4(0xdeadbeef));
        game.advanceGame();
        assertTrue(game.rngLocked());
        vm.clearMockedCalls();
        _measureBattleStage(50);
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
    }
}

contract PurchaseBattleWithoutTicketsTest is PurchaseDailyFixture {
    function setUp() public {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(PREV_POOL_L1_MAX, false);
        s.traitHolders = 4;
        _seed(s);
    }

    function test_BattleSealsDayWhenThereIsNoTicketLeg() public {
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertGt(daily.flipWins, 0);
        assertEq(daily.battleRuns, 0);
        assertTrue(game.rngLocked());
        uint256 salted = uint256(keccak256(abi.encodePacked(
            game.rngWordForDay(game.currentDayView()), keccak256("BONUS_TRAITS")
        )));
        vm.expectCall(ContractAddresses.GAME_JACKPOT_MODULE,
            abi.encodeWithSignature("payPurchaseJackpotBattle(uint24,uint256)", uint24(1), salted));
        _measureBattleStage(50);
        assertFalse(game.rngLocked());
    }
}

contract PurchaseZeroBattleBudgetTest is PurchaseDailyFixture {
    function setUp() public {
        PurchaseDailySeeder.Shape memory s = _shapeLevelOne(0, false);
        s.traitHolders = 4;
        _seed(s);
    }

    function test_ZeroBudgetSkipsBattleStageAndSealsImmediately() public {
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertEq(daily.flipWins + daily.battleRuns, 0);
        assertFalse(game.rngLocked());
    }
}

contract PurchaseZeroBattleWithTicketsTest is PurchaseDailyFixture {
    function setUp() public {
        _seed(_shape(128, 0, FF_HOLDERS, NEXT_POOL_QUIET, 0));
    }

    function test_ZeroBattleBudgetStillPaysTicketsBeforeSeal() public {
        (, Tally memory daily) = _measure();
        assertEq(daily.stage, STAGE_PURCHASE_DAILY);
        assertTrue(game.rngLocked());
        (, Tally memory tickets) = _measure();
        assertEq(tickets.stage, STAGE_PURCHASE_DAILY_TICKETS);
        assertGt(tickets.ticketWins, 0);
        assertEq(tickets.battleRuns, 0);
        assertFalse(game.rngLocked());
    }
}
