// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

contract DegenesisPaidFieldTable is CrapsViews {}

/// @title DegenesisJackpotPaidField -- the main battle on a Degenesis window day plays its paid field
/// @notice The ruling: during Degenesis the main (jackpot) battle runs without its ticket portion. On a
///         Degenesis window day (index 5, Degenesis day 4) two paid entrants enter, the round locks with
///         the pool's subsidy but zero awarded seats, the draw owes nothing, and the paid field plays to
///         a finalized verdict and pays. The same field on the first post-sale window day (index 9)
///         carries awarded seats again (control).
contract DegenesisJackpotPaidField is CrapsPins {
    DegenesisPaidFieldTable internal table;
    IJackpotBattle internal api;
    JackpotBattle internal cold;
    uint24 internal day;
    uint64 internal slot;
    uint256 internal dayStart;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function _openTableOn(uint24 windowDay) internal {
        _installPins();
        _warpToDay(windowDay - 1);
        table = DegenesisPaidFieldTable(deployCode("DegenesisJackpotPaidField.t.sol:DegenesisPaidFieldTable"));
        api = IJackpotBattle(address(table));
        cold = JackpotBattle(address(table));
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        dayStart = vm.getBlockTimestamp() + 1 days - elapsed;
        vm.warp(dayStart);
        day = table.currentDayIndex();
        require(day == windowDay, "fixture: window day");
        slot = uint64(uint256(day) * 8 + 6);
        _setIndex(1);
        _setDailyWord(day, 123456);
        vm.prank(ContractAddresses.GAME);
        table.openBonusDay();
        game.setScore(alice, 100);
        game.setScore(bob, 100);
    }

    /// @dev Two paid entrants (an own-battle seat and a whole-day seat), the round locked by the
    ///      next day's request, the draw prepared and appended, then the daily worker to completion.
    function _playPaidField() internal returns (CrapsBattleStorage.JackpotRound memory r, uint256 remaining) {
        vm.prank(alice);
        table.enterBonusBattle(5, 0, 1);
        vm.prank(bob);
        table.enterBonusDay(0, 1);

        vm.warp(dayStart + 1 days);
        game.setRngLocked(true);
        vm.prank(ContractAddresses.GAME);
        assertTrue(api.lockJackpotBattle(day + 1, 400_000 ether / 500, 2), "the window day locks a round");
        (r,,) = cold.jackpotBattleOf(slot);

        vm.startPrank(ContractAddresses.GAME);
        uint256 cursor;
        (, cursor, remaining) = api.prepareJackpotBattle(7, 0xD6E);
        uint256[] memory field = new uint256[](remaining > 3 ? 3 : remaining);
        for (uint256 i; i < field.length; ++i) field[i] = uint160(address(0xD1000)) + i | (uint256(1) << 180);
        api.appendJackpotBattle(field, cursor, true);
        for (uint256 i; i < 200; ++i) {
            (,,, bool done) = api.jackpotProgress();
            if (done) break;
            cold.runDailyBattleWork(gasleft());
        }
        vm.stopPrank();
    }

    function test_DegenesisWindowDay_PaidFieldPlaysToAVerdictWithoutAwardedSeats() public {
        _openTableOn(5);
        assertLt(day, GameTimeLib.MAIN_LAUNCH_DAY, "fixture: a Degenesis window day");
        uint256 credited0 = coinflip.totalCredited();
        (CrapsBattleStorage.JackpotRound memory r, uint256 remaining) = _playPaidField();
        assertEq(r.awardTarget, 0, "a Degenesis battle carries no awarded seats");
        assertGt(r.added, 0, "the paid field keeps the pool's subsidy");
        assertGt(r.paidCount, 0, "the paid entrants are in the field");
        assertGt(r.paidUnits, 0, "with paid units");
        assertEq(remaining, 0, "nothing owed to the ticket draw");
        (,, bool started, bool complete) = api.jackpotProgress();
        assertTrue(started && complete, "the paid field played to completion");
        (CrapsBattleStorage.JackpotRound memory after_,,) = cold.jackpotBattleOf(slot);
        assertEq(after_.drawnCount, 0, "no seat came from the draw");
        assertGt(coinflip.totalCredited(), credited0, "the paid field paid out");
    }

    function test_PostSaleWindowDay_SameFieldCarriesAwardedSeats() public {
        _openTableOn(GameTimeLib.MAIN_LAUNCH_DAY);
        (CrapsBattleStorage.JackpotRound memory r, uint256 remaining) = _playPaidField();
        assertGt(r.awardTarget, 0, "control: after the sale the round awards seats");
        assertGt(remaining, 0, "control: the draw owes awarded seats");
        assertGt(r.paidCount, 0, "control: a paid field");
    }
}
