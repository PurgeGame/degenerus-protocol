// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {LogicalDaysFixture} from "../fuzz/helpers/LogicalDaysFixture.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice A scheduled window stops taking entries the moment its period ends by the clock, even
///         while it is still opened, unarmed and inside an open schedule. Every state here is
///         reached through the real daily chain and then left without a maintenance step, so
///         the window's table has not been taken and only the period clock can refuse it.
contract LateCrapsWindowAdmissionTest is LogicalDaysFixture {
    bytes4 internal constant PERIOD_SPENT = bytes4(keccak256("BonusPeriodSpent()"));
    uint256 internal constant RESET_OFFSET = 82_620;

    /// @dev An entry into a window whose period ended hours ago is refused, and so is a re-spread
    ///      of a slip already in it, while the live window still takes the same entry.
    function test_ElapsedWindowRefusesNewEntryAndAmendWhileStillUnarmed() public {
        uint24 day = _openDayAt(1 hours);
        assertEq(_period(), 1, "fixture opens during period 1");

        (address alice, uint32 aliceId) = _fundedPlayer(address(0xA11CE), day);
        vm.prank(alice);
        uint256 betId = crapsBattle.throwCraps(aliceId, 1, 0, 1);
        vm.prank(alice);
        crapsBattle.amendSlip(aliceId, betId, 0);

        _warpToResetOffset(10 hours);
        _assertOnlyTheClockShut(day, 1, 2);

        (address bob, uint32 bobId) = _fundedPlayer(address(0xB0B), day);
        vm.prank(bob);
        vm.expectRevert(PERIOD_SPENT);
        crapsBattle.throwCraps(bobId, 1, 0, 1);

        vm.prank(alice);
        vm.expectRevert(PERIOD_SPENT);
        crapsBattle.amendSlip(aliceId, betId, 0);

        vm.prank(bob);
        uint256 liveBet = crapsBattle.throwCraps(bobId, 2, 0, 1);
        assertEq(liveBet >> 64, _slotAt(day, 2), "the live window took the entry");
    }

    /// @dev The window whose period has just ended (`live - 1`) is refused from its first second,
    ///      and the window that has just become live admits in the same block.
    function test_WindowStopsTakingEntriesAtTheSecondItsPeriodEnds() public {
        uint24 day = _openDayAt(1 hours);

        // Period 2 starts at 6h03m past the reset; one second earlier period 1 is still live.
        _warpToResetOffset(6 hours + 3 minutes - 1);
        assertEq(_period(), 1, "period 1 is live one second before its close");
        (address alice, uint32 aliceId) = _fundedPlayer(address(0xA11CE), day);
        vm.prank(alice);
        crapsBattle.throwCraps(aliceId, 1, 0, 1);

        vm.warp(vm.getBlockTimestamp() + 1);
        _assertOnlyTheClockShut(day, 1, 2);

        (address bob, uint32 bobId) = _fundedPlayer(address(0xB0B), day);
        vm.prank(bob);
        vm.expectRevert(PERIOD_SPENT);
        crapsBattle.throwCraps(bobId, 1, 0, 1);

        vm.prank(bob);
        uint256 liveBet = crapsBattle.throwCraps(bobId, 2, 0, 1);
        assertEq(liveBet >> 64, _slotAt(day, 2), "the live window took the entry");
    }

    /// @dev A day ticket cannot be upgraded in the window whose period has just ended, while the
    ///      window that has just become live upgrades in the same block.
    function test_DayTicketUpgradeRefusesTheJustElapsedWindowAndTakesTheLiveOne() public {
        uint24 day = _openDayAt(1 minutes);
        assertEq(_period(), 0, "fixture opens during period 0");

        (address alice, uint32 aliceId) = _fundedPlayer(address(0xA11CE), day);
        vm.prank(alice);
        crapsBattle.playCraps(aliceId, 0, 1);

        // Period 1 starts 20 minutes past the reset.
        _warpToResetOffset(20 minutes);
        _assertOnlyTheClockShut(day, 0, 1);

        vm.prank(alice);
        vm.expectRevert(PERIOD_SPENT);
        crapsBattle.upgradeDayWindows(aliceId, day, uint8(1 << 0));

        vm.prank(alice);
        crapsBattle.upgradeDayWindows(aliceId, day, uint8(1 << 1));
        assertEq(crapsBattle.daySeatHighMaskOf(day, alice), 1 << 1, "only the live window upgraded");
    }

    /// @dev After an opening hours late, the daily chain's own maintenance shuts the first elapsed
    ///      window at once: its table is taken while the schedule stays open.
    function test_LateOpeningChainShutsTheFirstElapsedWindow() public {
        uint24 day = _openDayAt(9 hours);
        assertEq(_period(), 2, "two periods elapsed before the opening");
        assertGt(crapsBattle.slotIndexOf(_slotAt(day, 0)), 0, "the first elapsed window is armed");
    }

    /// @dev Run one ordinary day, then the next day's daily chain at `offset` past that day's
    ///      wall-clock reset, and check that all six windows opened.
    function _openDayAt(uint256 offset) internal returns (uint24 day) {
        _nextLogical(777);
        uint256 elapsed = (vm.getBlockTimestamp() - RESET_OFFSET) % 1 days;
        vm.warp(vm.getBlockTimestamp() + (1 days - elapsed) + offset);
        uint256 request = _requestLogical();
        mockVRF.fulfillRandomWords(request, 779);
        vm.recordLogs();
        _finishLogical();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("CrapsBonusOpened(bytes32,uint48,uint256,uint128,uint128,uint256,uint256)");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(crapsBattle) || logs[i].topics[0] != topic) continue;
            seen |= 1 << (uint256(logs[i].topics[2]) % crapsBattle.BONUS_SLOTS_PER_DAY());
        }
        assertEq(seen, 0x7E, "all six windows open");
        day = crapsBattle.currentDayIndex();
        assertTrue(game.dailyScheduleOpen_g214(), "scheduled admissions open");
    }

    /// @dev The refused window's period has ended, yet its schedule is open and neither it nor the
    ///      live window has had its table taken.
    function _assertOnlyTheClockShut(uint24 day, uint256 elapsedPeriod, uint256 livePeriod) internal view {
        assertEq(_period(), livePeriod, "the next period is live");
        assertTrue(game.dailyScheduleOpen_g214(), "scheduled admissions still open");
        assertEq(crapsBattle.slotIndexOf(_slotAt(day, elapsedPeriod)), 0, "the elapsed window is unarmed");
        assertEq(crapsBattle.slotIndexOf(_slotAt(day, livePeriod)), 0, "the live window is unarmed");
    }

    function _period() internal view returns (uint256 period) {
        (, period,) = crapsBattle.currentBonusSlot();
    }

    function _slotAt(uint24 day, uint256 period) internal view returns (uint64) {
        return uint64(uint256(day) * crapsBattle.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    /// @dev Move forward to `offset` past the current wall day's reset.
    function _warpToResetOffset(uint256 offset) internal {
        uint256 elapsed = (vm.getBlockTimestamp() - RESET_OFFSET) % 1 days;
        require(offset >= elapsed, "offset already passed");
        vm.warp(vm.getBlockTimestamp() + (offset - elapsed));
    }

    /// @dev A registered player holding enough FLIP for a whole day and a high upgrade of any window.
    function _fundedPlayer(address who, uint24 day) internal returns (address, uint32 id) {
        id = _giveWalletId(who);
        uint256 units;
        for (uint256 p; p < 6; ++p) {
            (uint128 bankroll,,, uint256 bounty,,) = crapsBattle.bonusTermsFor(day, p);
            units += uint256(bankroll) + bounty;
        }
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame_g152734(who, units * 250);
        return (who, id);
    }
}
