// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsPins} from "./CrapsPins.sol";

contract CrapsMaintenanceDueHarness is CrapsBattle {
    function head(uint24 day, uint8 remainder) external {
        _keeperSlot = uint64(uint256(day) * 8 + remainder);
    }

    function opened(uint24 day) external { _boostBudget[day] = 1; }

    function field(uint24 day, uint8 remainder, uint32 count, uint64 cursor) external {
        uint256 slot = uint256(day) * 8 + remainder;
        if (remainder == 0) _dayTickets[slot] = count;
        else _battles[bytes32(slot)] = count;
        _setBonusCursor(slot, cursor);
    }

    function armed(uint24 day, uint8 remainder, uint32 resolved) external {
        uint256 slot = uint256(day) * 8 + remainder;
        _setSlotIndex(slot, 1);
        _battles[bytes32(slot)] |= uint256(resolved) << _BG_RESOLVED_SHIFT;
    }
}

contract CrapsMaintenanceDueAtTest is CrapsPins {
    CrapsMaintenanceDueHarness private table;
    uint24 private constant DAY = 10;
    uint256 private start;

    function setUp() public {
        _installPins();
        table = new CrapsMaintenanceDueHarness();
        start = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + DAY - 1) * 1 days + 82_620;
        vm.warp(start);
    }

    function test_AllOrdinaryWindowsBecomeDueAtTheirExactClose() public {
        uint256[5] memory closes = [uint256(20 minutes), 6 hours + 3 minutes,
            12 hours + 3 minutes, 18 hours + 3 minutes, 1 days - 20 minutes];
        table.opened(DAY);
        for (uint8 i; i < 5; ++i) {
            table.head(DAY, i + 1);
            table.field(DAY, i + 1, 1, 0);
            vm.warp(start + closes[i] - 1);
            assertEq(table.minerMaintenanceDueAt(), 0, "not due while entries remain open");
            vm.warp(start + closes[i]);
            assertEq(table.minerMaintenanceDueAt(), start + closes[i], "exact scheduled close");
            vm.warp(start + closes[i] + 2 hours);
            assertEq(table.minerMaintenanceDueAt(), start + closes[i], "waiting does not reset age");
        }
    }

    function test_DaySeatsCountButEmptyClosedWindowHasNoAge() public {
        table.head(DAY, 1);
        table.opened(DAY);
        vm.warp(start + 1 hours);
        assertTrue(table.minerMaintenancePending(), "empty head still needs cheap cursor maintenance");
        assertEq(table.minerMaintenanceDueAt(), 0, "empty bookkeeping has no aged work");
        table.field(DAY, 0, 2, 0);
        assertEq(table.minerMaintenanceDueAt(), start + 20 minutes, "day field is substantive membership");
    }

    function test_ArmedAndResolvedHeadsDoNotBorrowHistoricalAge() public {
        table.head(DAY, 1);
        table.opened(DAY);
        table.field(DAY, 1, 3, 0);
        vm.warp(start + 3 days);
        assertEq(table.minerMaintenanceDueAt(), start + 20 minutes);
        table.armed(DAY, 1, 1);
        assertFalse(table.minerMaintenancePending(), "unfinished armed field is read-settlement work");
        assertEq(table.minerMaintenanceDueAt(), 0);
        table.armed(DAY, 1, 3);
        table.field(DAY, 2, 4, 0);
        assertTrue(table.minerMaintenancePending(), "resolved head owes cursor cleanup");
        assertEq(table.minerMaintenanceDueAt(), 0, "do not look ahead or resurrect resolved age");
        table.head(DAY, 2);
        assertEq(table.minerMaintenanceDueAt(), start + 6 hours + 3 minutes, "new actual head has its own due time");
    }

    function test_LapsedDayAgeSurvivesPartialDayAndWindowRefunds() public {
        table.head(DAY, 0);
        table.field(DAY, 0, 3, 0);
        table.field(DAY, 6, 2, 0);
        vm.warp(start + 1 days - 1);
        assertEq(table.minerMaintenanceDueAt(), 0, "unopened current day is not lapsed yet");
        vm.warp(start + 1 days);
        uint256 due = start + 1 days;
        assertEq(table.minerMaintenanceDueAt(), due);
        table.field(DAY, 0, 3, 2);
        vm.warp(start + 2 days);
        assertEq(table.minerMaintenanceDueAt(), due, "partial day refunds preserve original age");
        table.field(DAY, 0, 3, 3);
        assertEq(table.minerMaintenanceDueAt(), due, "last reservation field remains refundable");
        table.field(DAY, 6, 2, 1);
        assertEq(table.minerMaintenanceDueAt(), due, "partial window refunds preserve original age");
        table.field(DAY, 6, 2, 2);
        assertEq(table.minerMaintenanceDueAt(), 0, "finished refunds leave only cheap separator cleanup");
    }

    function test_EmptyOpenedFutureAndJackpotBookkeepingHasNoAge() public {
        vm.warp(start + 2 days);
        table.head(DAY, 0);
        assertEq(table.minerMaintenanceDueAt(), 0, "empty lapsed day");
        table.field(DAY, 0, 1, 0);
        table.opened(DAY);
        assertEq(table.minerMaintenanceDueAt(), 0, "opened separator is cursor bookkeeping");
        table.head(DAY, 6);
        table.field(DAY, 6, 4, 0);
        assertEq(table.minerMaintenanceDueAt(), 0, "daily jackpot belongs to its dedicated action");
        table.head(DAY, 7);
        assertEq(table.minerMaintenanceDueAt(), 0, "detached jackpot separator");
        table.head(DAY + 3, 0);
        table.field(DAY + 3, 0, 4, 0);
        assertEq(table.minerMaintenanceDueAt(), 0, "future reservations are not overdue");
        table.head(DAY + 3, 1);
        table.field(DAY + 3, 1, 4, 0);
        assertEq(table.minerMaintenanceDueAt(), 0, "future window is not closed");
    }
}
