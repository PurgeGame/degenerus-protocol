// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @title DegenesisDailyEngine -- the daily phase through and just after the Degenesis week
/// @notice Spec checks 12, 15, 17 and 19 on the Degenesis timeline (deploy on day index 1, sale
///         on 2..8, main launch on 9), driven by real purchases and the real miner engine with
///         mock VRF. The next pool is filled past the 50 ETH level-1 target with real ticket
///         buys on the deploy day; only the at/below-target boundary cases write the next pool
///         directly (a real buy cannot land on an exact wei target).
contract DegenesisDailyEngine is DegenesisFixture {
    uint8 internal constant STAGE_RNG_REQUESTED = 1;
    uint8 internal constant STAGE_PURCHASE_DAILY = 6;
    uint8 internal constant STAGE_ENTERED_JACKPOT = 7;
    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint8 internal constant STAGE_DAILY_WORD_APPLIED = 18;
    uint8 internal constant STAGE_DEGENESIS_DAY = 21;
    uint8 internal constant JACKPOT_TURBO = 1;
    uint8 internal constant TURBO_BONUS_PENDING = 2;
    uint256 internal constant BATTLE_PENDING = uint256(1) << 72;

    bytes32 internal constant LOCKED_SIG = keccak256("JackpotBattleLocked(uint64,uint24,uint256,uint256)");
    bytes32 internal constant STARTED_SIG = keccak256("JackpotBattleStarted(uint64,uint24,uint256,uint256,uint256)");
    bytes32 internal constant WINNING_TRAITS_SIG = keccak256("DailyWinningTraits(uint24,uint32)");

    address internal alice;

    function setUp() public override {
        super.setUp();
        alice = _player("alice", 0);
    }

    /// @dev Fill the next pool past 50 ETH with real level-0 ticket buys (90% of a ticket buy).
    function _fillNextPoolPastTarget() internal {
        vm.deal(alice, 70 ether);
        _buyTickets(alice, 6700);
        assertGt(_nextPool(), 50 ether, "fixture: next pool past the level-1 target");
    }

    /// @dev Warp into day `d` and run the engine up to its daily request, which stays unanswered.
    function _requestDay(uint256 d) internal {
        _warpDay(d, 1 hours);
        _drain(false, 400);
        assertTrue(game.rngLocked(), "fixture: the day's request is out");
    }

    /// @dev Log positions of the Degenesis-day stage and of the next RNG request after it.
    function _day8PhaseThenRequest(Vm.Log[] memory logs) internal view returns (uint256 phase, uint256 request) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length != 1 || logs[i].topics[0] != ADVANCE_SIG) continue;
            (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
            if (s == STAGE_DEGENESIS_DAY) phase = i;
            if (s == STAGE_RNG_REQUESTED && phase != 0) return (phase, i);
        }
        revert("no day-9 request after a Degenesis-day phase");
    }

    function _stageCountUpTo(Vm.Log[] memory logs, uint8 stage, uint256 end) internal view returns (uint256 n) {
        for (uint256 i; i < end; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 1 && logs[i].topics[0] == ADVANCE_SIG) {
                (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
                if (s == stage) ++n;
            }
        }
    }

    function _battlePending() internal view returns (bool) {
        return _slot(GameSlots.DAILY_TICKET_BUDGETS_PACKED) & BATTLE_PENDING != 0;
    }

    function _stageCount(Vm.Log[] memory logs, uint8 stage) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 1 && logs[i].topics[0] == ADVANCE_SIG) {
                (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
                if (s == stage) ++n;
            }
        }
    }

    // ------------------------------------------------------------------ check 12/15/17/19: the week

    /// @notice Every Degenesis day (indices 2..8) runs the Degenesis daily branch: no level-1
    ///         FLIP draw, no foil draw record, no purchase ticket leg, no last-purchase latch, so
    ///         the level stays 0 even with the next pool far past its target. Randomness still
    ///         unlocks each day, and side-game settlement (the cohort pricing and settlement)
    ///         runs. Each cohort is priced only from the request after its own day, so its
    ///         randomness is requested after it is sealed.
    function test_DegenesisWeek_SkipsJackpotsAndLatch_LevelFrozenThroughIndex8() public {
        _fillNextPoolPastTarget();
        _drain();
        for (uint256 d = 2; d <= 8; ++d) {
            _warpDay(d, 1 hours);
            _buyDegenesis(alice, 0.01 ether);
            vm.recordLogs();
            _drain();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(_stageCount(logs, STAGE_DEGENESIS_DAY), 1, "the Degenesis daily branch ran");
            assertEq(_stageCount(logs, STAGE_PURCHASE_DAILY), 0, "no level-0 daily draw path");
            assertEq(_stageCount(logs, STAGE_PURCHASE_DAILY_TICKETS), 0, "no purchase ticket leg");
            assertEq(_countSig(logs, WINNING_TRAITS_SIG), 0, "no daily winning traits (no foil draw record)");
            assertEq(_level(), 0, "level frozen");
            assertFalse(_lastPurchaseDay(), "no last-purchase latch");
            assertFalse(_jackpotPhase(), "no jackpot phase");
            assertEq(_jackpotFlags() & JACKPOT_TURBO, 0, "no turbo");
            assertFalse(game.rngLocked(), "randomness unlocked");
            assertEq(_dailyIdx(), d, "the day sealed");
            // The cohort of day d - 1 (Degenesis day d - 2) is priced on this day's request only.
            if (d >= 3) {
                (bool found, uint8 c, uint24 boundDay) = _pricedIn(logs);
                assertTrue(found, "the sealed cohort was priced");
                assertEq(c, d - 2, "the cohort before today");
                assertEq(boundDay, d, "bound to the request after its day ended");
                assertGt(boundDay, GameTimeLib.DEGENESIS_START_DAY + c - 1, "priced after it sealed");
            }
        }
        assertGt(_nextPool(), 50 ether, "the target stayed met throughout");
    }

    function _pricedIn(Vm.Log[] memory logs) internal view returns (bool found, uint8 c, uint24 boundDay) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 2 && logs[i].topics[0] == PRICED_SIG) {
                c = uint8(uint256(logs[i].topics[1]));
                (,, boundDay) = abi.decode(logs[i].data, (uint256, uint256, uint24));
                found = true;
            }
        }
    }

    /// @notice The first Degenesis request (day index 2) is within a day of level 0's purchase
    ///         start (the deploy day), so the early-turbo condition would hold there; its main
    ///         launch gate keeps it from latching.
    function test_EarlyTurbo_NotOnFirstDegenesisRequest() public {
        _fillNextPoolPastTarget();
        _drain();
        _requestDay(2);
        assertFalse(_lastPurchaseDay(), "no early-turbo latch on the first Degenesis request");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, 0, "no turbo flag");
        assertEq(_level(), 0, "level stays 0 at the request");
    }

    // ------------------------------------------------------------------ check 17: late crank

    /// @notice Day 8's word is requested on day 8 but lands and is processed after wall time has
    ///         reached day 9 (MAIN_LAUNCH_DAY). The pause keys on the processed day, so day 8
    ///         still takes the Degenesis branch: no level-1 draw, no latch. Only the day-9 request
    ///         that follows applies the level-advance rule.
    function test_LateCrankedDegenesisDay_StillSkipsTicketLegsAndLatch() public {
        _fillNextPoolPastTarget();
        _drain();
        _driveThrough(7);
        _requestDay(8);
        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY, 2 hours);
        vm.recordLogs();
        assertTrue(_fulfillPending(), "day 8's word lands on day 9");
        // One engine run processes day 8 and then sends day 9's request.
        _drain(false, 400);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 phase8End, uint256 request9) = _day8PhaseThenRequest(logs);
        assertGt(request9, phase8End, "day 8's phase ran before day 9's request");
        assertEq(_stageCountUpTo(logs, STAGE_DEGENESIS_DAY, request9), 1, "day 8 took the Degenesis branch late");
        assertEq(_stageCountUpTo(logs, STAGE_PURCHASE_DAILY, request9), 0, "no level-1 draw for a late Degenesis day");
        assertEq(_countSig(logs, WINNING_TRAITS_SIG), 0, "no winning traits for a late Degenesis day");

        // The day-9 request is the first after main launch: it latches the turbo.
        assertTrue(game.rngLocked(), "day 9's request is out");
        assertEq(_dailyIdx(), 8, "day 8 sealed");
        assertEq(_level(), 1, "the day-9 request advanced the level");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "turbo latched at the day-9 request");
    }

    // ------------------------------------------------------------------ check 19: day-9 request

    /// @notice At the day-9 request the next pool exceeds _levelPrizePool(0) (50 ETH): it latches
    ///         lastPurchaseDay with JACKPOT_TURBO, the level becomes 1 at that request, and level
    ///         1's jackpot phase enters and ends within day 9, leaving the turbo bonus owed.
    function test_Day9Request_AboveTarget_TurboLevelOneJackpotInOneDay() public {
        assertEq(game.prizePoolTargetView(), 50 ether, "level-1 target is the 50 ETH bootstrap");
        _fillNextPoolPastTarget();
        _drain();
        _driveThrough(8);
        assertEq(_level(), 0, "level 0 through day 8");

        _requestDay(GameTimeLib.MAIN_LAUNCH_DAY);
        assertEq(_level(), 1, "the level becomes 1 at the day-9 request");
        assertTrue(_lastPurchaseDay(), "lastPurchaseDay latched");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "with JACKPOT_TURBO");

        vm.recordLogs();
        _drain();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_stageCount(logs, STAGE_ENTERED_JACKPOT), 1, "level 1's jackpot phase entered on day 9");
        assertEq(_stageCount(logs, STAGE_JACKPOT_PHASE_ENDED), 1, "and ended on day 9");
        assertEq(_stageCount(logs, STAGE_DEGENESIS_DAY), 0, "day 9 is not a Degenesis day");
        assertFalse(_jackpotPhase(), "one-day jackpot phase complete");
        assertEq(_level(), 1, "level 1");
        assertEq(_dailyIdx(), GameTimeLib.MAIN_LAUNCH_DAY, "day 9 sealed");
        assertEq(_jackpotFlags() & TURBO_BONUS_PENDING, TURBO_BONUS_PENDING, "turbo bonus owed");
    }

    /// @notice The day-9 request whose subscriptions were stamped on day 9 (pinning the request
    ///         day to 9) executes only after wall time reaches day 10. It is still the first request
    ///         after Degenesis, so with the next pool above 50 ETH it latches lastPurchaseDay with
    ///         JACKPOT_TURBO, the level becomes 1, and level 1's jackpot phase enters and ends in
    ///         day 9's processing, before day 10's request.
    function test_Day9Request_PinnedOnDay9_ExecutedOnWallDay10_StillTurbos() public {
        _fillNextPoolPastTarget();
        _drain();
        _driveThrough(8);
        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        _stepTo(ACTION_REQUEST_DAILY);
        uint24 resetDay = uint24(_slot(GameSlots.AFKING_RESET_DAY) >> (GameSlots.AFKING_RESET_DAY_OFFSET * 8));
        assertEq(resetDay, GameTimeLib.MAIN_LAUNCH_DAY, "fixture: subscriptions pinned on day 9");
        assertFalse(game.rngLocked(), "fixture: day 9's request not yet sent");

        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY + 1, 1 hours);
        vm.recordLogs();
        game.mineFlip(0);
        assertTrue(game.rngLocked(), "the request went out on wall day 10");
        assertEq(_dailyIdx(), 8, "for day 9: day 8 is the last sealed day");
        assertTrue(_lastPurchaseDay(), "lastPurchaseDay latched");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "with JACKPOT_TURBO");
        assertEq(_level(), 1, "the level becomes 1 at that request");

        assertTrue(_fulfillPending(), "answer day 9's request");
        _drain(false, 400); // day 9's processing, then day 10's request
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 request10 = _secondRequest(logs);
        assertEq(_stageCountUpTo(logs, STAGE_ENTERED_JACKPOT, request10), 1, "level 1's jackpot entered on day 9");
        assertEq(_stageCountUpTo(logs, STAGE_JACKPOT_PHASE_ENDED, request10), 1, "and ended on day 9");
        assertEq(_dailyIdx(), GameTimeLib.MAIN_LAUNCH_DAY, "day 9 sealed");
        assertFalse(_jackpotPhase(), "one-day jackpot phase complete before day 10");
        assertEq(_level(), 1, "level 1");
    }

    /// @dev Log index of the second RNG request stage in `logs`.
    function _secondRequest(Vm.Log[] memory logs) internal view returns (uint256) {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length != 1 || logs[i].topics[0] != ADVANCE_SIG) continue;
            (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
            if (s == STAGE_RNG_REQUESTED && ++seen == 2) return i;
        }
        revert("no second request");
    }

    /// @notice One wei over the target at the day-9 request is enough to latch the turbo.
    function test_Day9Request_OneWeiAboveTarget_Turbo() public {
        _driveThrough(8);
        _setNextPool(50 ether + 1);
        _requestDay(GameTimeLib.MAIN_LAUNCH_DAY);
        assertTrue(_lastPurchaseDay(), "latched one wei above the target");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "turbo");
        assertEq(_level(), 1, "level 1");
    }

    /// @notice Exactly at the target the day-9 request latches nothing: level 0 continues.
    function test_Day9Request_AtTarget_NoLatch() public {
        _driveThrough(8);
        _setNextPool(50 ether);
        _requestDay(GameTimeLib.MAIN_LAUNCH_DAY);
        assertFalse(_lastPurchaseDay(), "no latch at exactly the target");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, 0, "no turbo");
        assertEq(_level(), 0, "level 0 continues");
    }

    /// @notice Below the target at day 9, level 0's purchase phase continues under its normal
    ///         rules: day 9 runs the normal level-0 daily path (the level-1 FLIP draw and the
    ///         winning traits), not the Degenesis branch.
    function test_Day9Request_BelowTarget_LevelZeroContinuesNormally() public {
        vm.deal(alice, 30 ether);
        _buyTickets(alice, 3000);
        assertLt(_nextPool(), 50 ether, "fixture: below the target");
        _drain();
        _driveThrough(8);
        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        vm.recordLogs();
        _drain();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_level(), 0, "level 0 continues");
        assertFalse(_lastPurchaseDay(), "no latch below the target");
        assertEq(_stageCount(logs, STAGE_DEGENESIS_DAY), 0, "not a Degenesis day");
        assertEq(_stageCount(logs, STAGE_PURCHASE_DAILY), 1, "the normal level-0 daily path ran");
        assertEq(_countSig(logs, WINNING_TRAITS_SIG), 1, "with its daily draw record");
    }

    /// @notice A stall that skips day 9 entirely: the first post-Degenesis request lands on day
    ///         10, more than a day after level 0's purchase start, and still qualifies for the
    ///         early turbo because dailyIdx is still a Degenesis day.
    function test_FirstPostDegenesisRequestAfterStall_StillTurbos() public {
        _fillNextPoolPastTarget();
        _drain();
        _driveThrough(8);
        _requestDay(GameTimeLib.MAIN_LAUNCH_DAY + 1);
        assertTrue(_lastPurchaseDay(), "latched at the delayed first post-Degenesis request");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "turbo");
        assertEq(_level(), 1, "level 1");
    }

    // ------------------------------------------------------------------ check 15/17: battles

    /// @notice No jackpot battle locks, and no _JACKPOT_BATTLE_PENDING bit is set, for any window
    ///         day before the first window day (index 3): the requests on days 2 and 3 lock
    ///         nothing; the day-4 request locks day 3's battle and sets the bit.
    function test_NoBattleLockOrPendingBitBeforeFirstWindowDay() public {
        _drain();
        for (uint256 d = 2; d <= 4; ++d) {
            vm.recordLogs();
            _requestDay(d);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 locks;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter == address(crapsBattle) && logs[i].topics[0] == LOCKED_SIG) ++locks;
            }
            if (d < 4) {
                assertEq(locks, 0, "no battle locked before the first window day");
                assertFalse(_battlePending(), "no pending bit before the first window day");
            } else {
                assertEq(locks, 1, "day 3's battle locks at the day-4 request");
                assertTrue(_battlePending(), "pending bit set with the lock");
            }
            assertTrue(_fulfillPending(), "answer");
            _drain();
            assertFalse(_battlePending(), "the battle (if any) finished with the day");
        }
    }

    /// @notice Every battle whose window day is a Degenesis day (3..8) seals with zero awarded
    ///         seats through the zero-award shortcut, including day 8's battle, which locks and
    ///         draws during the first post-Degenesis phase (the day-9 request). The day-9 window,
    ///         locked by the day-10 request, draws awarded seats again.
    function test_DegenesisWindowBattles_ZeroAwards_IncludingDay8() public {
        _fillNextPoolPastTarget();
        _drain();
        uint256 lockedThroughDay9;
        for (uint256 d = 2; d <= 10; ++d) {
            _warpDay(d, 1 hours);
            vm.recordLogs();
            _drain();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            (bool locked, uint24 requestDay) = _lockIn(logs);
            (bool started, uint256 drawn) = _startIn(logs);
            if (!locked) {
                assertLt(d, 4, "every request from day 4 locks a battle");
                continue;
            }
            assertEq(requestDay, d, "locked by this day's request");
            assertTrue(started, "the locked battle sealed and started the same day");
            assertFalse(_battlePending(), "pending bit cleared by the seal");
            if (d <= GameTimeLib.MAIN_LAUNCH_DAY) {
                // Window day d - 1 is a Degenesis day.
                assertEq(drawn, 0, "Degenesis window: zero awarded seats");
                ++lockedThroughDay9;
            } else {
                assertGt(drawn, 0, "post-Degenesis window: awarded seats return");
            }
        }
        assertEq(lockedThroughDay9, 6, "window days 3..8 each locked one battle");
    }

    function _lockIn(Vm.Log[] memory logs) internal view returns (bool found, uint24 requestDay) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(crapsBattle) && logs[i].topics[0] == LOCKED_SIG) {
                (requestDay,,) = abi.decode(logs[i].data, (uint24, uint256, uint256));
                found = true;
            }
        }
    }

    function _startIn(Vm.Log[] memory logs) internal view returns (bool found, uint256 drawn) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(crapsBattle) && logs[i].topics[0] == STARTED_SIG) {
                (, drawn,,) = abi.decode(logs[i].data, (uint24, uint256, uint256, uint256));
                found = true;
            }
        }
    }
}
