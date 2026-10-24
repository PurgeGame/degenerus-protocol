// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture, DegenesisFixtureBase} from "./helpers/DegenesisFixture.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {CrapsSlots, GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Craps checks shared by the Degenesis and the late-deployed (legacy) timelines.
abstract contract DegenesisCrapsChecks is DegenesisFixtureBase {
    bytes32 internal constant LOCKED_SIG = keccak256("JackpotBattleLocked(uint64,uint24,uint256,uint256)");
    bytes4 internal constant DAY_NOT_RESERVABLE = bytes4(keccak256("DayNotReservable()"));
    uint256 internal constant BATTLE_PENDING = uint256(1) << 72;

    function _firstWindowDay() internal view returns (uint24) {
        uint256 w = uint256(vm.load(address(crapsBattle), bytes32(CrapsSlots.FIRST_WINDOW_DAY)));
        return uint24(w >> (CrapsSlots.FIRST_WINDOW_DAY_OFFSET * 8));
    }

    function _seedPasses() internal view returns (uint256 house, uint256 vaultPasses) {
        (house,) = crapsBattle.passCreditsOf(ContractAddresses.SDGNRS);
        (vaultPasses,) = crapsBattle.passCreditsOf(ContractAddresses.VAULT);
    }

    function _locksIn(Vm.Log[] memory logs) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(crapsBattle) && logs[i].topics[0] == LOCKED_SIG) ++n;
        }
    }

    function _battlePending() internal view returns (bool) {
        return _slot(GameSlots.DAILY_TICKET_BUDGETS_PACKED) & BATTLE_PENDING != 0;
    }

    /// @dev An automatic pass delivery (as a resolved box makes it) for a fresh account.
    function _deliver(string memory name) internal returns (uint32 id, uint24 day) {
        id = _giveWalletId(makeAddr(name));
        vm.prank(address(game));
        day = crapsBattle.deliverPasses(id, 1, 0);
    }
}

/// @title DegenesisCraps -- craps windows, battles and passes on the Degenesis timeline (check 16)
/// @notice Deploy on day index 1: the first window day is index 3 (Degenesis day 2). No pass is
///         reserved on a windowless day, player-chosen runs refuse day 2 or earlier, and the
///         protocol bodies' banked seed passes are spent one per opened day from day 3.
contract DegenesisCraps is DegenesisCrapsChecks, DegenesisFixture {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisFixture) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function test_FirstWindowDay_IsDayIndex3() public view {
        assertEq(_firstWindowDay(), GameTimeLib.DEGENESIS_START_DAY + 1, "first window on Degenesis day 2");
        assertEq(_firstWindowDay(), 3, "day index 3");
    }

    /// @notice A delivery on the deploy day (day 1) or on Degenesis day 1 (day 2) books the first
    ///         window day; from day 3 on it books tomorrow.
    function test_DeliverPasses_Day1AndDay2_BookDay3() public {
        (uint32 a, uint24 dayA) = _deliver("deliver-day1");
        assertEq(dayA, 0, "bootstrap has no published schedule: delivery banks");
        assertEq(crapsBattle.daySeatNumberOfId(3, a), 0, "no admission before published terms");
        (uint256 banked,) = crapsBattle.passCreditsOf(makeAddr("deliver-day1"));
        assertEq(banked, 1, "award remains spendable");
        assertEq(crapsBattle.daySeatNumberOfId(2, a), 0, "never on day 2");

        _driveDay(2);
        (uint32 b, uint24 dayB) = _deliver("deliver-day2");
        assertEq(dayB, 3, "day-2 delivery books day 3");
        assertGt(crapsBattle.daySeatNumberOfId(3, b), 0, "seated on day 3");

        _driveDay(3);
        (, uint24 dayC) = _deliver("deliver-day3");
        assertEq(dayC, 4, "from day 3, tomorrow");
    }

    /// @notice applyCrapsPasses refuses a run starting on day 2 or earlier; day 3 is accepted.
    function test_ApplyCrapsPasses_RefusesWindowlessDays() public {
        address p = makeAddr("passes-holder");
        uint32 id = _giveWalletId(p);
        vm.prank(address(game));
        crapsBattle.creditPasses(id, 3, 0);
        vm.startPrank(p);
        vm.expectRevert(DAY_NOT_RESERVABLE);
        crapsBattle.applyCrapsPasses(id, 2, 1, false, 0);
        vm.expectRevert(DAY_NOT_RESERVABLE);
        crapsBattle.applyCrapsPasses(id, 1, 2, false, 0);
        crapsBattle.applyCrapsPasses(id, 3, 1, false, 0);
        vm.stopPrank();
        assertGt(crapsBattle.daySeatNumberOfId(3, id), 0, "day 3 reserved");
    }

    /// @notice buyFutureCrapsDays refuses a run starting on day 2 or earlier (the burn unwinds
    ///         with the revert); day 3 is accepted.
    function test_BuyFutureCrapsDays_RefusesWindowlessDays() public {
        address p = makeAddr("future-buyer");
        uint32 id = _giveWalletId(p);
        vm.prank(address(game));
        coin.mintForGame(p, 1_000_000 ether);
        uint256 balance = coin.balanceOf(p);
        vm.startPrank(p);
        vm.expectRevert(DAY_NOT_RESERVABLE);
        crapsBattle.buyFutureCrapsDays(id, 2, 1, false, 0);
        assertEq(coin.balanceOf(p), balance, "refused run burned nothing");
        crapsBattle.buyFutureCrapsDays(id, 3, 1, false, 0);
        vm.stopPrank();
        assertGt(crapsBattle.daySeatNumberOfId(3, id), 0, "day 3 reserved");
        assertLt(coin.balanceOf(p), balance, "the accepted run paid");
    }

    /// @notice The two protocol bodies' 20 banked seed passes are untouched on days 1 and 2 and
    ///         spent one per opened day from day 3.
    function test_SeedPasses_SpentFromDay3() public {
        (uint256 h, uint256 v) = _seedPasses();
        assertEq(h, 20, "house seed");
        assertEq(v, 20, "vault seed");
        _drain();
        _driveDay(2);
        (h, v) = _seedPasses();
        assertEq(h, 20, "no window on days 1-2: house seed intact");
        assertEq(v, 20, "no window on days 1-2: vault seed intact");
        _driveDay(3);
        (h, v) = _seedPasses();
        assertEq(h, 19, "day 3 opened: one house pass");
        assertEq(v, 19, "day 3 opened: one vault pass");
        _driveDay(4);
        (h, v) = _seedPasses();
        assertEq(h, 18, "one per opened day");
        assertEq(v, 18, "one per opened day");
    }

    /// @notice The daily requests on days 2 and 3 lock no battle (window days 1 and 2 have no
    ///         windows; no detached round on the deploy day); the day-4 request locks day 3's.
    function test_NoBattleBeforeFirstWindowDay() public {
        _drain();
        for (uint256 d = 2; d <= 4; ++d) {
            _warpDay(d, 1 hours);
            vm.recordLogs();
            _drain(false, 400);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(_locksIn(logs), d < 4 ? 0 : 1, "lock only from window day 3");
            assertEq(_battlePending(), d >= 4, "pending bit only with a lock");
            _drain();
        }
    }
}

/// @title DegenesisCrapsLateDeploy -- the late-deployed (legacy) fixture
/// @notice Deployed on day index 9 (after the Degenesis window), the first window day is the day
///         after deployment, there is no detached round on the deploy day, and deliveries and
///         seed passes follow the first window day.
contract DegenesisCrapsLateDeploy is DegenesisCrapsChecks {
    function test_LateDeploy_FirstWindowIsDeployPlusOne() public view {
        assertEq(_deployDay(), GameTimeLib.MAIN_LAUNCH_DAY, "fixture: deployed on day 9");
        assertEq(_firstWindowDay(), 3, "logical first window is deployment-independent");
    }

    function test_LateDeploy_DeliveryOnDeployDayBooksDeployPlusOne() public {
        (uint32 id, uint24 day) = _deliver("late-deliver");
        assertEq(day, 0, "synthetic bootstrap has no published daily schedule");
        (uint256 banked,) = crapsBattle.passCreditsOf(makeAddr("late-deliver"));
        assertEq(banked, 1, "delivery banks until a schedule opens");
    }

    /// @notice The request on deploy + 1 would lock the deploy day's battle as a detached round;
    ///         the deploy day is before the first window day, so nothing locks and no pending bit
    ///         is set. The next request locks the first window day's battle. Seed passes start
    ///         on deploy + 1.
    function test_LateDeploy_NoDetachedRoundOnDeployDay() public {
        uint24 d0 = _deployDay();
        _drain();
        (uint256 h,) = _seedPasses();
        assertEq(h, 20, "deploy day opens no window");

        _warpDay(d0 + 1, 1 hours);
        vm.recordLogs();
        _drain(false, 400);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_locksIn(logs), 1, "logical day 9 is a scheduled day in this synthetic fixture");
        assertTrue(_battlePending(), "the prior logical battle is detached");
        _drain();
        (h,) = _seedPasses();
        assertEq(h, 19, "first window day spends the first seed pass");

        _warpDay(d0 + 2, 1 hours);
        vm.recordLogs();
        _drain(false, 400);
        logs = vm.getRecordedLogs();
        assertEq(_locksIn(logs), 1, "the first window day's battle locks");
        assertTrue(_battlePending(), "with its pending bit");
        _drain();
    }
}
