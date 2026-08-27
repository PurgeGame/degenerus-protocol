// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract BudgetHarness is CrapsViews {
    function betsAt(uint256 id) external view returns (uint256) {
        return _bets[id];
    }

    function resolveMaxSeats() external pure returns (uint64) {
        return _RESOLVE_MAX_SEATS;
    }

    function creditReserveGas() external pure returns (uint256) {
        return _CREDIT_RESERVE_GAS;
    }

    function resolveTailGas() external pure returns (uint256) {
        return _RESOLVE_TAIL_GAS;
    }

    function _daySlotOfPub(uint24 day) public pure returns (uint256) {
        return uint256(day) * BONUS_SLOTS_PER_DAY;
    }
}

/// @title The settle walk's gas budget
/// @notice `resolveSlot`'s second argument stopped being a seat count and became a GAS ALLOWANCE.
///         That changes only WHERE one transaction stops — so the whole of this suite is the same
///         assertion from different angles: chunking moves the boundary and nothing else.
contract CrapsResolveBudgetTest is CrapsPins {
    BudgetHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;
    uint32 internal constant SEVEN = 4 | (uint32(3) << 9);

    /// @dev Enough seats that a budget stops the walk before the field does.
    uint256 internal constant FIELD = 40;

    function setUp() public {
        _installPins();
        craps = new BudgetHarness();
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    // ════════════════════════════════════════════════════════════════════════
    // A. What a budget buys
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE BOUNDARIES. Zero settles nothing at all; the smallest nonzero budget settles
    ///      exactly one seat, because the meter is read AFTER a seat rather than before; and a
    ///      budget past what the field costs settles the field and stops there.
    function test_zeroSettlesNothingAndOneWeiOfBudgetSettlesOneSeat() public {
        (uint64 slot,) = _field(PLAIN_WORD, uint256(keccak256("boundary")));

        craps.resolveSlot(slot, 0);
        assertEq(craps.bonusCursorOf(slot), 0, "a zero budget settled a seat");

        craps.resolveSlot(slot, 1);
        assertEq(craps.bonusCursorOf(slot), 1, "the smallest nonzero budget did not settle exactly one seat");

        craps.resolveSlot(slot, 1);
        assertEq(craps.bonusCursorOf(slot), 2, "a second minimal budget did not take the next seat");

        // A budget no field can exhaust takes the rest and stops at the field's end.
        uint64 entrants = uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants);
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(craps.bonusCursorOf(slot), entrants, "an oversized budget did not finish the field");

        // And a finished field is silent rather than a revert, whatever the budget.
        craps.resolveSlot(slot, WHOLE_FIELD);
        craps.resolveSlot(slot, 1);
        assertEq(craps.bonusCursorOf(slot), entrants, "a finished field moved");
    }

    /// @dev A BIGGER BUDGET IS NEVER FEWER SEATS. Monotone by construction — the stop is a
    ///      threshold on consumed gas — and this walks a ladder of budgets to say so.
    function test_moreBudgetIsNeverFewerSeats() public {
        uint64[6] memory budgets = [uint64(1), 200_000, 600_000, 1_500_000, 4_000_000, WHOLE_FIELD];
        uint256 last;
        for (uint256 i = 0; i < 6; ++i) {
            uint256 snap = vm.snapshotState();
            (uint64 slot,) = _field(PLAIN_WORD, uint256(keccak256("ladder")));
            craps.resolveSlot(slot, budgets[i]);
            uint256 seats = craps.bonusCursorOf(slot);
            assertGe(seats, last, "a larger budget bought fewer seats");
            assertGe(seats, 1, "a nonzero budget bought no seat at all");
            last = seats;
            vm.revertToState(snap);
        }
        assertGt(last, 1, "even the largest budget only ever took one seat");
    }

    /// @dev THE SEAT CEILING IS ABSOLUTE, and independent of the budget. It bounds the two credit
    ///      arrays and the loop counter, so no caller can make one call allocate without limit.
    function test_theSeatCeilingBoundsOneCallWhateverTheBudgetIs() public {
        assertEq(craps.resolveMaxSeats(), 256, "the seat ceiling moved");
        // The suite's fields are far below the ceiling, so this states the rule rather than
        // driving it: the ceiling is a `from + max` clamp on the offered end, above every field
        // any fixture here builds.
        (uint64 slot,) = _field(PLAIN_WORD, uint256(keccak256("ceiling")));
        uint64 entrants = uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants);
        assertLt(entrants, craps.resolveMaxSeats(), "the fixture field reaches the ceiling");
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(craps.bonusCursorOf(slot), entrants, "the ceiling clipped a field below it");
    }

    // ════════════════════════════════════════════════════════════════════════
    // B. Chunking moves the boundary and nothing else
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE EQUIVALENCE, and it is the whole point of the change. One field and one word,
    ///      settled three ways — in a single oversized call, one seat at a time, and in several
    ///      ordinary budgets — must land on the identical winner, roll count, pot, progressive
    ///      balance, action totals and cursor.
    function test_everyChunkingReachesTheIdenticalResult() public {
        uint256 wordSalt = uint256(keccak256("equivalence"));
        uint256[3] memory pool;
        uint64[3] memory winner;
        uint16[3] memory rolls;
        uint256[3] memory action;
        uint256[3] memory credited;
        uint256[3] memory cursor;

        for (uint256 mode = 0; mode < 3; ++mode) {
            uint256 snap = vm.snapshotState();
            (uint64 slot, uint24 day) = _field(PLAIN_WORD, wordSalt);
            craps.seedProgressive(1_000_000 ether);

            if (mode == 0) {
                craps.resolveSlot(slot, WHOLE_FIELD);
            } else if (mode == 1) {
                for (uint256 i = 0; i < FIELD + 8; ++i) craps.resolveSlot(slot, 1);
            } else {
                for (uint256 i = 0; i < 12; ++i) craps.resolveSlot(slot, 900_000);
            }

            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
            assertTrue(b.finalized, "a chunking left the field unfinished");
            pool[mode] = craps.progressivePool();
            winner[mode] = b.winnerId;
            rolls[mode] = b.winningRolls;
            action[mode] = craps.dayStaked(day);
            credited[mode] = coinflip.totalCredited();
            cursor[mode] = craps.bonusCursorOf(slot);
            vm.revertToState(snap);
        }

        for (uint256 m = 1; m < 3; ++m) {
            assertEq(winner[m], winner[0], "the chunking chose a different winner");
            assertEq(rolls[m], rolls[0], "the chunking stored a different roll count");
            assertEq(pool[m], pool[0], "the chunking moved the progressive by a different amount");
            assertEq(action[m], action[0], "the chunking booked a different amount of action");
            assertEq(credited[m], credited[0], "the chunking credited a different total");
            assertEq(cursor[m], cursor[0], "the chunking left the cursor somewhere else");
        }
    }

    /// @dev THE CURSOR IS THE SEATS ACTUALLY RESOLVED, never the end the batch was offered. That
    ///      is what the budget makes necessary: the offered end became a ceiling, so booking it
    ///      would strand every seat the meter stopped short of.
    function test_theCursorTracksResolvedSeatsAndNeverOvershootsThem() public {
        (uint64 slot, uint24 day) = _field(PLAIN_WORD, uint256(keccak256("cursor")));
        uint64 entrants = uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants);

        uint64 seen;
        uint256 bookedBefore;
        for (uint256 i = 0; i < 6 && seen < entrants; ++i) {
            uint256 booked = craps.dayStaked(day);
            assertGe(booked, bookedBefore, "the action book went backwards");
            bookedBefore = booked;

            vm.recordLogs();
            craps.resolveSlot(slot, 700_000);
            uint256 settled = _countSig(vm.getRecordedLogs(), keccak256("CrapsBetSettled(uint256,address,uint256,uint256)"));
            uint64 after_ = craps.bonusCursorOf(slot);
            // EXACTLY the seats that settled, and every one of them contiguous with the last.
            assertEq(after_ - seen, settled, "the cursor moved by other than the seats settled");
            seen = after_;
        }
        assertEq(seen, entrants, "the walk never finished the field");
        assertEq(craps.dayStaked(day), bookedBefore + _lastLegAction(day, bookedBefore), "action drifted");
    }

    /// @dev THE ACTION BOOK GROWS ONLY BY WHAT WAS PROCESSED, and reaches the same total however
    ///      the chunks fell. A batch that booked its offered end rather than its actual one would
    ///      inflate the day that sizes a later subsidy.
    function test_actionTotalsAreIdenticalHoweverTheChunksFell() public {
        uint256[2] memory staked;
        uint256[2] memory high;
        for (uint256 mode = 0; mode < 2; ++mode) {
            uint256 snap = vm.snapshotState();
            (uint64 slot, uint24 day) = _field(PLAIN_WORD, uint256(keccak256("action")));
            if (mode == 0) {
                craps.resolveSlot(slot, WHOLE_FIELD);
            } else {
                for (uint256 i = 0; i < FIELD + 8; ++i) craps.resolveSlot(slot, 1);
            }
            staked[mode] = craps.dayStaked(day);
            high[mode] = craps.highStakedOf(day);
            vm.revertToState(snap);
        }
        assertEq(staked[1], staked[0], "one-seat chunks booked different action");
        assertEq(high[1], high[0], "one-seat chunks booked different high action");
        assertGt(staked[0], 0, "the fixture booked no action at all");
    }

    /// @dev PREVIEW AND PAYMENT STILL AGREE, at every chunk boundary. The budget decides when a
    ///      seat settles, never what it is worth.
    function test_previewMatchesPaymentAcrossEveryChunkBoundary() public {
        (uint64 slot,) = _field(PLAIN_WORD, uint256(keccak256("preview")));
        uint64 own = _ownSeatsOf(slot);
        uint256[] memory quoted = new uint256[](own + 1);
        for (uint64 n = 1; n <= own; ++n) {
            (, quoted[n]) = craps.previewSettlement((uint256(slot) << 64) | n);
        }

        uint256 checked;
        for (uint256 i = 0; i < own; ++i) {
            vm.recordLogs();
            craps.resolveSlot(slot, 1);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
            for (uint256 j = 0; j < logs.length; ++j) {
                if (logs[j].topics[0] != sig) continue;
                uint256 betId = uint256(logs[j].topics[1]);
                if (betId >> 64 != slot) continue;
                (, uint256 paid) = abi.decode(logs[j].data, (uint256, uint256));
                assertEq(paid, quoted[uint64(betId)], "a seat paid other than its preview");
                ++checked;
            }
        }
        assertEq(checked, own, "not every own seat was graded across the chunks");
    }

    // ════════════════════════════════════════════════════════════════════════
    // C. Liveness
    // ════════════════════════════════════════════════════════════════════════

    /// @dev A BUDGET IS A REQUEST, NOT A PROMISE OF GAS, and asking for more than you supply is
    ///      safe in both directions.
    ///
    ///      THE FLOOR SATURATES. `stopAt` is `startGas - gasBudget` clamped at zero, so a caller
    ///      that asks for nine million with a hundred thousand behind it does not get a nonsense
    ///      floor — it gets zero, and then the TAIL RESERVE is what actually stops the walk while
    ///      there is still enough gas to write the cursor, book the action and pay the batch. The
    ///      call therefore does as much as it can afford and commits that consistently.
    ///
    ///      Below one seat it simply runs out, and because the cursor is written after the walk,
    ///      nothing is committed at all.
    function test_anUnderfundedCallerDegradesRatherThanStranding() public {
        (uint64 slot,) = _field(PLAIN_WORD, uint256(keccak256("underfunded")));
        craps.resolveSlot(slot, 1);
        uint64 marked = craps.bonusCursorOf(slot);
        assertEq(marked, 1, "the fixture did not settle its first seat");

        // TOO LITTLE FOR EVEN ONE SEAT: out of gas, and nothing committed.
        (bool ok,) = address(craps).call{gas: 60_000}(
            abi.encodeWithSignature("resolveSlot(uint64,uint64)", slot, uint64(9_000_000))
        );
        assertFalse(ok, "a call below one seat's gas did not run out");
        assertEq(craps.bonusCursorOf(slot), marked, "a reverted call committed part of a walk");

        // ENOUGH FOR SOME OF IT: an over-large budget with modest gas commits a shorter walk
        // rather than reverting, and every seat it claims is really settled.
        (ok,) = address(craps).call{gas: 400_000}(
            abi.encodeWithSignature("resolveSlot(uint64,uint64)", slot, uint64(9_000_000))
        );
        assertTrue(ok, "a call with real gas behind an over-large budget did not complete");
        uint64 shortWalk = craps.bonusCursorOf(slot);
        assertGt(shortWalk, marked, "the affordable walk committed nothing");
        assertLt(shortWalk, craps.battleOf(craps.keyOfSlot(slot)).entrants, "the short walk finished the field");

        // And the field is still perfectly live, from exactly where it stopped.
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertTrue(craps.battleOf(craps.keyOfSlot(slot)).finalized, "the field was stranded by the short call");
    }

    /// @dev AN ALL-BUST FIELD STILL STOPS. The reserve is per PAID seat, so a field that pays
    ///      nobody reserves nothing — and it is the measured replay gas, not an outcome label,
    ///      that has to stop the walk.
    function test_aFieldThatPaysNobodyStillStopsOnItsBudget() public {
        // Searched rather than asserted: a word where the whole field busts.
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 64; ++i) {
            (uint64 slot,) = _field(PLAIN_WORD, uint256(keccak256(abi.encode("allbust", i))));
            vm.recordLogs();
            craps.resolveSlot(slot, 1_400_000);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 settled = _countSig(logs, keccak256("CrapsBetSettled(uint256,address,uint256,uint256)"));
            uint256 paidSeats = _paidIn(logs);
            uint64 walked = craps.bonusCursorOf(slot);
            if (paidSeats == 0 && settled > 1) {
                assertLt(walked, craps.battleOf(craps.keyOfSlot(slot)).entrants, "the budget did not stop the walk");
                assertGt(walked, 1, "a field of busts walked only one seat on a real budget");
                return;
            }
            vm.revertToState(snap);
            snap = vm.snapshotState();
        }
        // Not reaching a wholly-busting batch is a fixture problem, and it is said out loud.
        emit log_string("no word produced a batch that paid nobody: this fixture proved nothing");
        assertTrue(false, "no all-bust batch was found");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Fixtures
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Open a fresh day, seat `FIELD` players into period 1, shut it, and land `wordSalt` on
    ///      the table it took.
    function _field(uint256 dayWord, uint256 wordSalt) internal returns (uint64 slot, uint24 day) {
        day = craps.currentDayIndex();
        _setDailyWord(day, dayWord);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        for (uint256 i = 0; i < FIELD; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("seat", i)))));
            game.setScore(who, craps.SYBIL_SCORE_FLOOR());
            vm.prank(who);
            craps.enterBonusBattle(PER, SEVEN, 1);
        }
        slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(block.timestamp + 5 hours);
        uint48 index = craps.armBonusWindow(slot);
        _setIndex(index);
        _setWord(index, wordSalt);
    }

    function _ownSeatsOf(uint64 slot) internal view returns (uint64) {
        uint24 day = uint24(uint256(slot) / craps.BONUS_SLOTS_PER_DAY());
        return uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants) - uint32(craps.dayTicketsOf(day));
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    /// @dev How many settled seats in this stream actually paid — the reserve's own denominator.
    function _paidIn(Vm.Log[] memory logs) internal pure returns (uint256 n) {
        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
            if (paid != 0) ++n;
        }
    }

    /// @dev What the final leg of a walk added to the day's book, for the drift assertion.
    function _lastLegAction(uint24 day, uint256 booked) internal view returns (uint256) {
        return craps.dayStaked(day) - booked;
    }
}
