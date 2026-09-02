// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {Craps} from "../../contracts/Craps.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

contract BoonPayoutHarness is CrapsViews {}

/// @title CrapsBoonPayout -- the craps boon as a BANKROLL-PAYOUT boost
/// @notice The boon buys no discount and pays no entry-time credit. It rides the slip as a one-hot
///         mask in bet-word bits 206..208 and lifts ONLY that slip's bankroll return when it
///         settles. Four things this owns:
///
///         1. THE SLICE. 206..208 was free space between the standing field and the day-span byte.
///            A writer that spills into a neighbour would corrupt a standing or a high-lane flag
///            silently, so the surrounding word is graded, not just the mask.
///         2. THE FORMULA. `min(basePaid, 60,000) * bps`, so the tiers top out at 3,000 / 6,000 /
///            9,000 FLIP PER SETTLEMENT. A SHARED base ceiling rather than three separate caps:
///            capping each tier at the top figure would flatten all three on a big enough return.
///         3. FAIL CLOSED. Only 1, 2 and 4 mean anything. 3, 5, 6 and 7 are unreachable through
///            the trusted writer and must pay nothing if they ever reach storage another way,
///            where a two-bit index would silently mean something.
///         4. EVERY WINDOW. A day ticket's burn paid for seven windows, so its boon lifts all
///            seven bankroll payments. Settlement order still cannot reach it -- settlement is
///            permissionless once the words are public, and each window's lift is a function of
///            that window's run and the mask alone, so every answer is fixed before any window is
///            cranked.
contract CrapsBoonPayoutTest is CrapsPins {
    BoonPayoutHarness internal craps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint24 internal constant PLAYED = 600;
    uint128 internal constant BANK = 600e18;
    uint128 internal constant GOAL = 6000e18;
    uint256 internal constant PER = 1;

    uint256 internal constant MASK_5 = 1;
    uint256 internal constant MASK_10 = 2;
    uint256 internal constant MASK_15 = 4;

    function setUp() public {
        _installPins();
        craps = new BoonPayoutHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
    }

    function _seven() internal pure returns (Craps.Bets memory c) {
        c.passLine = 2;
        c.place4 = 1;
        c.place5 = 1;
        c.place6 = 1;
        c.place8 = 1;
        c.place9 = 1;
    }

    function _customSlot() internal returns (uint64 slot) {
        vm.prank(vaultOwner);
        slot = craps.createBattle(PLAYED, 4, 10, 0, 0, uint40(block.timestamp + 1 days), true, 0);
    }

    // ---------------------------------------------------------------------
    // 1. The slice
    // ---------------------------------------------------------------------

    function test_theMaskRoundTripsThroughStorageAtItsOwnSlice() public {
        uint64 slot = _customSlot();
        uint256[3] memory masks = [MASK_5, MASK_10, MASK_15];
        for (uint256 i; i < 3; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("mask", i)))));
            game.setScore(who, craps.SYBIL_SCORE_FLOOR());
            flip.setNextBoonMask(uint8(masks[i]));
            vm.prank(who);
            uint256 betId = craps.enterBattle(slot, _seven(), 1);
            assertEq(craps.boonMaskOf(betId), masks[i], "the mask did not reach its slice");
        }
    }

    function test_anUnboonedEntryLeavesTheSliceClear() public {
        uint64 slot = _customSlot();
        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, _seven(), 1);
        assertEq(craps.boonMaskOf(betId), 0, "an unbooned slip carries a mask");
    }

    // ---------------------------------------------------------------------
    // 4. Entry paths: who may carry a boon at all
    // ---------------------------------------------------------------------

    function test_aFutureRunMarksOnlyItsFirstReservedDay() public {
        uint24 today = craps.currentDayIndex();
        flip.setNextBoonMask(uint8(MASK_15));
        vm.prank(alice);
        craps.buyFutureCrapsDays(today + 1, 3, false);

        uint256 slotsPerDay = craps.BONUS_SLOTS_PER_DAY();
        for (uint256 i; i < 3; ++i) {
            uint24 day = uint24(uint256(today) + 1 + i);
            uint256 seat = craps.daySeatNumberOf(day, alice);
            assertGt(seat, 0, "the run did not reserve its day");
            uint256 betId = ((uint256(day) * slotsPerDay) << 64) | seat;
            assertEq(craps.boonMaskOf(betId), i == 0 ? MASK_15 : 0, "the run spread one boon over many days");
        }
    }

    function test_redemptionAndDeliveryCarryNoBoon() public {
        uint24 today = craps.currentDayIndex();
        uint256 slotsPerDay = craps.BONUS_SLOTS_PER_DAY();

        // A DELIVERED pass is not a purchase.
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(bob, 1, 0);
        uint256 seat = craps.daySeatNumberOf(today + 1, bob);
        assertGt(seat, 0, "the delivery did not seat tomorrow");
        uint256 betId = ((uint256(today + 1) * slotsPerDay) << 64) | seat;
        assertEq(craps.boonMaskOf(betId), 0, "a delivered pass carried a boon");

        // Nor is SPENDING a banked credit, even with a boon armed.
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 2, 0);
        flip.setNextBoonMask(uint8(MASK_15));
        vm.prank(alice);
        craps.applyCrapsPasses(today + 5, 1, false);
        uint256 aSeat = craps.daySeatNumberOf(today + 5, alice);
        uint256 aBet = ((uint256(today + 5) * slotsPerDay) << 64) | aSeat;
        assertEq(craps.boonMaskOf(aBet), 0, "a redeemed pass carried a boon");
    }

    // ---------------------------------------------------------------------
    // 5. The seam: `_resolve` joining the mask to the payment
    // ---------------------------------------------------------------------

    /// @dev The formula and the plumbing are graded above; this grades the JOIN. The same run is
    ///      previewed with and without a boon — the only way to do that is to rewrite the stored
    ///      word, because seats are seeded individually and two slips would be two different runs.
    ///      Sweeps seeds until it has both a paying run and a busted one, so the pair covers the
    ///      credit case and the "a bust stays a bust" case on real settlements. The sweep is WIDE
    ///      because the escalator doubles every three shooters: busts are the common outcome and
    ///      a paying run at this depth takes a search.
    function test_theBoonLiftsPaidByExactlyItsBonusAndNeverTouchesWon() public {
        uint256 shift = craps.BET_BOON_SHIFT();
        bool sawPaying;
        bool sawBust;

        for (uint256 i; i < 400 && !(sawPaying && sawBust); ++i) {
            uint64 slot = _openBattle(craps, PLAYED, 4, uint16(craps.MIN_BATTLE_GOAL_MULT()), 0);
            vm.prank(alice);
            uint256 betId = craps.enterBattle(slot, _seven(), 1);
            _closeOn(craps, slot, uint48(9_000 + i), uint256(keccak256(abi.encode("seam", i))));

            (uint256 wonPlain, uint256 paidPlain) = craps.previewSettlement(betId);
            uint256 word = craps.betWordOf(betId);
            craps.setBetWord(betId, word | (MASK_15 << shift));
            (uint256 wonBooned, uint256 paidBooned) = craps.previewSettlement(betId);

            assertEq(wonBooned, wonPlain, "the boon moved the run's own result");
            assertEq(
                paidBooned - paidPlain,
                craps.boonBonusOf(MASK_15, paidPlain),
                "paid did not move by exactly the bonus"
            );

            if (paidPlain == 0) {
                assertEq(paidBooned, 0, "a boon turned a bust into a credit");
                sawBust = true;
            } else {
                assertGt(paidBooned, paidPlain, "a paying run drew no bonus");
                sawPaying = true;
            }
        }
        assertTrue(sawPaying, "the sweep never found a paying run");
        assertTrue(sawBust, "the sweep never found a busted run");
    }

    /// @dev An unreachable mask reaching storage another way must pay nothing rather than mean
    ///      something — the whole reason the field is one-hot instead of a two-bit index.
    function test_anInvalidStoredMaskPaysNothingAtSettlement() public {
        uint256 shift = craps.BET_BOON_SHIFT();
        uint64 slot = _openBattle(craps, PLAYED, 4, uint16(craps.MIN_BATTLE_GOAL_MULT()), 0);
        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, _seven(), 1);
        _closeOn(craps, slot, 9_500, uint256(keccak256("invalid-mask")));

        (, uint256 paidPlain) = craps.previewSettlement(betId);
        uint256 word = craps.betWordOf(betId);
        uint256[4] memory bad = [uint256(3), 5, 6, 7];
        for (uint256 i; i < 4; ++i) {
            craps.setBetWord(betId, word | (bad[i] << shift));
            (, uint256 paidBad) = craps.previewSettlement(betId);
            assertEq(paidBad, paidPlain, "an invalid mask paid at settlement");
        }
    }

    // ---------------------------------------------------------------------
    // 6. The high lane: the base is the SCALED payment
    // ---------------------------------------------------------------------

    /// @dev A high seat buys H copies of ONE run, so the percentage must run on the SCALED
    ///      payment and the 60,000 ceiling must bite on that. Taking the base pre-scale and
    ///      multiplying after would pay `H x boonBonus(s.paid)` -- at H = 256 that is hundreds of
    ///      thousands of FLIP instead of the 9,000 ceiling, so the two readings are nowhere near
    ///      each other and this pins the right one.
    ///
    ///      The lane is CONTESTED on purpose: a sole high rider's return is added after the boon,
    ///      and with two high seats there is no rider, so `paid` is the scaled payment exactly and
    ///      the delta is readable without unpicking a rider.
    function test_aHighSeatTakesItsBonusOffTheScaledPaymentAndTheCeilingBitesThere() public {
        uint256 shift = craps.BET_BOON_SHIFT();
        uint256 cap = craps.BOON_PAYOUT_BASE_CAP();
        uint16 h = uint16(craps.MAX_HIGH_MULT());
        bool sawCapped;

        for (uint256 i; i < 400 && !sawCapped; ++i) {
            uint64 slot = _openHigh(craps, PLAYED, 4, uint16(craps.MIN_BATTLE_GOAL_MULT()), 0, h);
            vm.prank(alice);
            uint256 betId = craps.enterBattle(slot, _seven(), h);
            vm.prank(bob);
            craps.enterBattle(slot, _seven(), h); // contest the lane, so neither seat rides
            _closeOn(craps, slot, uint48(11_000 + i), uint256(keccak256(abi.encode("high", i))));

            (, uint256 paidPlain) = craps.previewSettlement(betId);
            if (paidPlain == 0) continue;

            uint256 word = craps.betWordOf(betId);
            craps.setBetWord(betId, word | (MASK_15 << shift));
            (, uint256 paidBooned) = craps.previewSettlement(betId);

            assertEq(
                paidBooned - paidPlain,
                craps.boonBonusOf(MASK_15, paidPlain),
                "the bonus was not taken off the scaled payment"
            );
            if (paidPlain > cap) {
                assertEq(paidBooned - paidPlain, 9_000 ether, "the ceiling did not bite on the scaled base");
                sawCapped = true;
            }
        }
        assertTrue(sawCapped, "no high run large enough to test the ceiling");
    }

    /// @dev THE BOON MATH IS WRITTEN TWICE — once in `_resolve`, once in `previewSettlement` —
    ///      so a divergence between them is invisible to any test that reads only one, and a
    ///      quote that over-promises is worse than no quote. Hold the two to the same number, on
    ///      an ordinary seat and on a high one, since only the high path exercises the scale.
    function test_thePreviewQuotesExactlyWhatSettlementPays() public {
        uint16 h = uint16(craps.MAX_HIGH_MULT());
        bool sawPlainPay;
        bool sawHighPay;

        for (uint256 i; i < 24 && !(sawPlainPay && sawHighPay); ++i) {
            uint64 slot = _openHigh(craps, PLAYED, 4, uint16(craps.MIN_BATTLE_GOAL_MULT()), 0, h);

            flip.setNextBoonMask(uint8(MASK_15));
            vm.prank(alice);
            uint256 ordinary = craps.enterBattle(slot, _seven(), 1);
            flip.setNextBoonMask(uint8(MASK_15));
            vm.prank(bob);
            uint256 high = craps.enterBattle(slot, _seven(), h);
            // A second high seat, so neither rides and the quote is the scaled payment alone.
            address third = address(uint160(uint256(keccak256(abi.encode("third", i)))));
            game.setScore(third, craps.SYBIL_SCORE_FLOOR());
            vm.prank(third);
            craps.enterBattle(slot, _seven(), h);

            _closeOn(craps, slot, uint48(13_000 + i), uint256(keccak256(abi.encode("parity", i))));

            (, uint256 quotedOrdinary) = craps.previewSettlement(ordinary);
            (, uint256 quotedHigh) = craps.previewSettlement(high);

            vm.recordLogs();
            craps.resolveSlot(slot, WHOLE_FIELD);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            assertEq(_settledPaidOf(logs, ordinary), quotedOrdinary, "the quote missed an ordinary settlement");
            assertEq(_settledPaidOf(logs, high), quotedHigh, "the quote missed a high settlement");
            if (quotedOrdinary != 0) sawPlainPay = true;
            if (quotedHigh != 0) sawHighPay = true;
        }
        assertTrue(sawPlainPay, "no ordinary run paid");
        assertTrue(sawHighPay, "no high run paid");
    }

    function _settledPaidOf(Vm.Log[] memory logs, uint256 betId) internal pure returns (uint256) {
        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == sig && uint256(logs[i].topics[1]) == betId) {
                (, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                return paid;
            }
        }
        revert("that bet never settled");
    }

    // ---------------------------------------------------------------------
    // 7. The day ticket: one boon, every window it plays
    // ---------------------------------------------------------------------

    /// @dev Walk the clock onto PERIOD ZERO, the only window in which the day lane is sold. Steps
    ///      rather than computing the boundary, so it stays right if the schedule is ever retuned.
    function _warpToPeriodZero() internal {
        for (uint256 i; i < 1500; ++i) {
            (, uint256 period,) = craps.currentBonusSlot();
            if (period == 0) return;
            vm.warp(vm.getBlockTimestamp() + 1 minutes);
        }
        revert("no period-zero window found within a day");
    }

    function _dayTicketWithBoon(uint256 mask) internal returns (uint24 day, uint256 betId) {
        _warpToPeriodZero();
        day = craps.currentDayIndex();
        _setDailyWord(day, uint256(keccak256("day-anchor-word")));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        Craps.Bets memory blank;
        flip.setNextBoonMask(uint8(mask));
        vm.prank(alice);
        craps.enterBonusDay(blank, 1);

        uint256 seat = craps.daySeatNumberOf(day, alice);
        betId = ((uint256(day) * craps.BONUS_SLOTS_PER_DAY()) << 64) | seat;
        assertEq(craps.boonMaskOf(betId), mask, "the day ticket did not carry the boon");
    }

    /// @dev A window is armed only once it has STOPPED taking bets, so step the clock past its
    ///      close first. Stepping rather than computing the boundary keeps this right if the
    ///      schedule is retuned.
    function _warpPastPeriod(uint256 period) internal {
        for (uint256 i; i < 200; ++i) {
            (, uint256 p,) = craps.currentBonusSlot();
            if (p > period) return;
            vm.warp(vm.getBlockTimestamp() + 10 minutes);
        }
        revert("window never closed");
    }

    function _paidAt(uint24 day, uint256 period, uint256 betId, uint256 salt) internal returns (uint256) {
        _warpPastPeriod(period);
        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, uint256(keccak256(abi.encode("settle", period, salt))));
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == sig && uint256(logs[i].topics[1]) == betId) {
                (, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                return paid;
            }
        }
        revert("the day ticket did not settle in that window");
    }

    /// @dev THE BOON RIDES EVERY WINDOW THE TICKET PLAYS. A whole-day ticket is one stored slip
    ///      settled in all seven of its day's fields, and its burn paid for all seven — so its
    ///      boon lifts every one of those bankroll payments rather than a single anchored one.
    ///
    ///      Settlement ORDER still cannot reach it, which is what the old period-0 anchor was
    ///      protecting: the lift is a function of the run and the mask alone, so every window's
    ///      answer is fixed before any of them is cranked and a permissionless caller has no
    ///      outcome to choose between.
    ///
    ///      Each leg runs twice off one snapshot: once with the boon and once with the slice
    ///      cleared, so the comparison is the SAME run rather than two different ones.
    ///
    ///      THE DICE ARE SEARCHED, NOT THE TICKET. The escalator doubles every three shooters, so
    ///      most words bust every window of the day and a day that busts everywhere proves nothing
    ///      about a lift. The ticket and its terms are held fixed and the settlement word is swept
    ///      until TWO DISTINCT windows have been caught paying — which is the whole claim, because
    ///      the retired anchor paid period 0 and nothing else, so any second window separates the
    ///      two rules. Demanding both in the SAME word would only be demanding one lucky pair of
    ///      dice. The per-window equality is the real assertion and holds on EVERY word the sweep
    ///      touches, paying or not.
    ///
    ///      Three windows rather than seven: the rule is uniform, and the day's last window closes
    ///      on the day boundary where a stepping fixture cannot follow it.
    function test_aDayTicketIsBoostedInEveryWindowItPlays() public {
        uint256 shift = craps.BET_BOON_SHIFT();
        (uint24 day, uint256 betId) = _dayTicketWithBoon(MASK_15);
        uint256 cleared = craps.betWordOf(betId) & ~(craps.BET_BOON_MASK() << shift);
        uint256 snap = vm.snapshotState();

        uint256 seen; // which periods have been caught paying, one bit each
        uint256 distinct;
        for (uint256 salt; salt < 128 && distinct < 2; ++salt) {
            for (uint256 p = 0; p < 3; ++p) {
                vm.revertToState(snap);
                uint256 booned = _paidAt(day, p, betId, salt);
                vm.revertToState(snap);
                craps.setBetWord(betId, cleared);
                uint256 plain = _paidAt(day, p, betId, salt);
                assertEq(booned - plain, craps.boonBonusOf(MASK_15, plain), "a window was not lifted by its bonus");
                if (plain != 0 && (seen & (1 << p)) == 0) {
                    seen |= 1 << p;
                    ++distinct;
                }
            }
        }
        assertGt(distinct, 1, "fewer than two of the ticket's windows were ever caught paying");
    }

    /// @dev Upgrading windows to the high lane rewrites the high-flag byte of the same word the
    ///      boon sits under. It must not disturb the slice.
    function test_upgradingDayWindowsPreservesTheMask() public {
        (uint24 day, uint256 betId) = _dayTicketWithBoon(MASK_10);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 2));
        assertEq(craps.boonMaskOf(betId), MASK_10, "an upgrade dropped the boon");
    }

    /// @dev The burn lane is the only door a boon comes through, so a purchase that reverts must
    ///      leave nothing behind -- no seat, and no spent boon on the mock's side either.
    function test_aRevertedPurchaseLeavesNoSeatAndNoSpentBoon() public {
        uint24 today = craps.currentDayIndex();
        flip.setNextBoonMask(uint8(MASK_15));
        // A run that reaches into the past cannot be reserved; the whole call unwinds.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.buyFutureCrapsDays(today, 2, false);

        assertEq(craps.daySeatNumberOf(today, alice), 0, "a refused run still seated a day");
        assertEq(flip.nextBoonMask(), MASK_15, "a refused run still spent the boon");
    }
}
