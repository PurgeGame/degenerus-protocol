// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {BattleHarness} from "./CrapsBattle.t.sol";

/// @title Aliased bonus-slot entry -- regression
/// @notice `_slotWindow` now round-trips: after decoding a slot into a window it checks
///         `w.bound == slot`, so a slot offset from a real window's slot by a multiple of 2^27
///         (which names the same day/period and so the same battle key) no longer decodes to that
///         window. These pin the fix shut: the aliased door reverts, a settled field cannot be
///         paid twice through it, the scheduled keeper is unaffected, and neither an ordinary
///         real-slot entry nor a custom battle (a slot that never goes through the round-trip
///         check at all) lost anything to the tighter door.
contract CrapsAliasedSlotTest is CrapsPins {
    BattleHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;
    uint256 internal constant ALIAS_STRIDE = 1 << 27;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    function setUp() public {
        _installPins();
        craps = new BattleHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    function _seven() internal pure returns (Craps.Bets memory c) {
        c.passLine = 3;
        c.place8 = 3;
        c.place9 = 1;
    }

    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    function _closeOf(uint256 period) internal view returns (uint256) {
        return period * craps.BONUS_PERIOD() + craps.BONUS_CLOCK_ALIGN();
    }

    function _slotAt(uint256 period) internal view returns (uint64) {
        (uint24 day,,) = craps.currentBonusSlot();
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    function _seat(address who, uint256 period) internal returns (uint256) {
        game.setScore(who, craps.SYBIL_SCORE_FLOOR());
        vm.prank(who);
        return craps.enterBonusBattle(period, _seven(), 1);
    }

    function _idAt(uint64 slot, uint64 n) internal view returns (uint256) {
        uint24 day = uint24(uint256(slot) / craps.BONUS_SLOTS_PER_DAY());
        uint64 dayN = craps.dayTicketsOf(day);
        uint64 ownN = uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants) - dayN;
        return n <= ownN ? (uint256(slot) << 64) | n : (craps._daySlotOfPub(day) << 64) | (n - ownN);
    }

    function _paidLogs(Vm.Log[] memory logs) internal pure returns (uint256 n) {
        bytes32 sig = keccak256("CrapsBattlePaid(uint256,bytes32,address,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    /// @dev A window is opened and seated. A legitimate direct entry on the REAL slot still works
    ///      right up to the arm -- the round-trip check binds only the caller's own slot number,
    ///      never an ordinary join. Once armed, a slot offset by 2^27 names the same battle key
    ///      but fails `w.bound == slot` and every door built on `_slotWindow` -- `enterBattle`
    ///      included -- now refuses it outright instead of folding the entry into the real field.
    function test_aliasedSlotIsNotAWindow() public {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        uint64 slot = _slotAt(PER);
        bytes32 key = craps.keyOfSlot(slot);

        _seat(alice, PER);
        _seat(bob, PER);

        // A legitimate entry on the real slot, before the arm, still lands normally.
        game.setScore(carol, craps.SYBIL_SCORE_FLOOR());
        uint64 entrantsBeforeCarol = craps.battleOf(key).entrants;
        vm.prank(carol);
        uint256 carolId = craps.enterBattle(slot, _seven(), 1);
        assertEq(carolId >> 64, uint256(slot), "a legitimate real-slot entry must key to that slot");
        assertEq(
            craps.battleOf(key).entrants,
            entrantsBeforeCarol + 1,
            "a legitimate real-slot entry must still join the field"
        );
        assertGt(flip.burned(carol), 0, "carol's legitimate entry was not charged");

        vm.warp(_dayStart() + _closeOf(PER));
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, uint256(keccak256("aliased-slot-word")));

        uint64 entrantsArmed = craps.battleOf(key).entrants;

        // ---- the aliased slot ------------------------------------------------------------------
        uint64 alias_ = uint64(uint256(slot) + ALIAS_STRIDE);
        assertLt(uint256(alias_), craps.customSlotBase(), "alias must stay in the bonus lane");

        game.setScore(dave, craps.SYBIL_SCORE_FLOOR());
        vm.prank(dave);
        vm.expectRevert(CrapsBattle.NoSuchBattle.selector);
        craps.enterBattle(alias_, _seven(), 1);

        assertEq(craps.battleOf(key).entrants, entrantsArmed, "entrants moved despite the revert");
        assertEq(flip.burned(dave), 0, "dave was charged despite the revert");
    }

    /// @dev The same field, settled once and then walked a second time through the real slot. With
    ///      the alias door shut, nothing outside the finalized field's own cursor can ever hand it
    ///      a fresh seat, so a repeat `resolveSlot` finds nothing left owing and pays nobody. The
    ///      scheduled keeper, which walks the same slot lane, is unaffected by the fix and still
    ///      crosses the finalized window.
    function test_settledWindowPaysOnce() public {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        uint64 slot = _slotAt(PER);
        bytes32 key = craps.keyOfSlot(slot);
        uint24 day = craps.currentDayIndex();

        _seat(alice, PER);
        _seat(bob, PER);

        vm.warp(_dayStart() + _closeOf(PER));
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, uint256(keccak256("settled-window-word")));

        craps.resolveSlot(slot, WHOLE_FIELD);
        CrapsBattle.Battle memory done = craps.battleOf(key);
        assertTrue(done.finalized, "fixture: the window did not finalize");
        uint64 entrants0 = done.entrants;
        uint64 dayN = craps.dayTicketsOf(day);
        assertEq(done.resolved, entrants0, "fixture: cursor short of the field");

        uint256 lastDayId = (craps._daySlotOfPub(day) << 64) | dayN;
        address lastDayOwner = dayN == 0 ? address(0) : craps.betOf(lastDayId).player;
        address winner = craps.betOf(_idAt(slot, done.winnerId)).player;

        uint256 aliceBefore = coinflip.staked(alice);
        uint256 bobBefore = coinflip.staked(bob);
        uint256 winnerBefore = coinflip.staked(winner);
        uint256 lastDayBefore = coinflip.staked(lastDayOwner);
        uint256 creditedBefore = coinflip.totalCredited();
        uint256 compsBefore = flip.compAccruals();
        uint256 progressiveBefore = craps.progressiveOf();

        // ---- settle the real slot a second time ---------------------------------------------
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        CrapsBattle.Battle memory again = craps.battleOf(key);

        assertEq(again.resolved, entrants0, "the second walk moved the cursor past a finalized field");
        assertEq(_paidLogs(logs), 0, "a settled window paid a pot a second time");
        assertEq(coinflip.staked(alice), aliceBefore, "alice was credited on the second settle");
        assertEq(coinflip.staked(bob), bobBefore, "bob was credited on the second settle");
        assertEq(coinflip.staked(winner), winnerBefore, "the winner was credited on the second settle");
        assertEq(coinflip.staked(lastDayOwner), lastDayBefore, "the day ticket was credited on the second settle");
        assertEq(coinflip.totalCredited(), creditedBefore, "total credited moved on the second settle");
        assertEq(flip.compAccruals(), compsBefore, "comps accrued on the second settle");
        assertEq(craps.progressiveOf(), progressiveBefore, "the progressive pool moved on the second settle");

        // ---- the scheduled keeper is unaffected: it still crosses the finalized window ----------
        (bool progressed,) = craps.keepScheduled(WHOLE_FIELD);
        assertTrue(progressed, "the keeper did not progress past a finalized window");
    }

    /// @dev A custom battle's slot is its own dictionary key -- `_customTerms` never decodes a
    ///      slot into a day/period pair, so it has no round-trip to fail. The fix leaves entry on
    ///      a real custom slot untouched.
    function test_customBattleSlotUnaffected() public {
        uint40 close = uint40(vm.getBlockTimestamp() + 1 hours);
        vm.prank(vaultOwner);
        uint64 slot = craps.createBattle(60, 5, 5, 0, 0, close, true, 0);
        assertGe(uint256(slot), craps.customSlotBase(), "a custom battle slot must sit above the custom base");

        game.setScore(carol, craps.SYBIL_SCORE_FLOOR());
        vm.prank(carol);
        uint256 betId = craps.enterBattle(slot, _seven(), 1);
        assertEq(betId >> 64, uint256(slot), "the custom entry must key to its own slot");
        assertGt(flip.burned(carol), 0, "the custom entry was not charged");
    }
}
