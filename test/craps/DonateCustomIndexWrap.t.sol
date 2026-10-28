// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {stdError} from "forge-std/StdError.sol";
import {BattleHarness} from "./CrapsBattle.t.sol";

/// @notice Regression: donate(custom = true, index) computed `_CUSTOM_SLOT_BASE + index` unchecked, so
///         index = slot - 2^40 (mod 2^256) landed on scheduled slot `slot` and skipped the scheduled
///         period gate (a closed but unarmed window took a donation the normal door refuses). The
///         addition is now checked: the wrapping index reverts, and the window settles exactly as
///         the control run with no donation.
contract DonateCustomIndexWrap is CrapsPins {
    BattleHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        _installPins();
        _warpToTableGenesis();
        craps = new BattleHarness();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setIndex(0);
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
        return craps.throwCraps(period, _seven(), 1);
    }

    /// @dev Open, seat two, shut PER's entry. Returns the slot and its key; not armed yet.
    function _closedUnarmedWindow() internal returns (uint64 slot, bytes32 key) {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        slot = _slotAt(PER);
        key = craps.keyOfSlot(slot);
        _seat(alice, PER);
        _seat(bob, PER);
        vm.warp(_dayStart() + _closeOf(PER));
        assertEq(craps.slotIndexOf(slot), 0, "entry closed, window not armed");
    }

    function _armAndSettle(uint64 slot, bytes32 key)
        internal returns (uint256 credited, uint64 winnerSeat, uint256 alicePaid, uint256 bobPaid)
    {
        uint256 before = coinflip.totalCredited();
        uint256 a0 = coinflip.staked(alice);
        uint256 b0 = coinflip.staked(bob);
        uint48 index = craps.armWindow(slot);
        _setWord(index, uint256(keccak256("donate-wrap-word")));
        craps.settleSlot(slot, WHOLE_FIELD);
        CrapsViews.Battle memory done = craps.battleOf(key);
        assertTrue(done.finalized, "fixture: field finalized");
        credited = coinflip.totalCredited() - before;
        winnerSeat = done.winnerId;
        alicePaid = coinflip.staked(alice) - a0;
        bobPaid = coinflip.staked(bob) - b0;
    }

    function test_WrappedCustomIndexReverts() public {
        (uint64 slot, bytes32 key) = _closedUnarmedWindow();
        uint256 base = craps.customSlotBase();

        // The normal scheduled door refuses a window whose entry period has passed.
        vm.prank(carol);
        vm.expectRevert(CrapsBattleStorage.BonusPeriodSpent.selector);
        craps.donate(false, PER, 5);

        uint256 snap = vm.snapshotState();
        (uint256 cCredited, uint64 cWinner, uint256 cAlice, uint256 cBob) = _armAndSettle(slot, key);
        assertTrue(vm.revertToState(snap));

        // The wrapping custom index no longer reaches the scheduled slot.
        uint256 index;
        unchecked { index = uint256(slot) - base; }
        vm.prank(carol);
        vm.expectRevert(stdError.arithmeticError);
        craps.donate(true, index, 5);
        assertEq(flip.burned(carol), 0, "no FLIP burned");
        assertEq(craps.battleOf(key).seed, 0, "no seed on the closed scheduled window");

        (uint256 dCredited, uint64 dWinner, uint256 dAlice, uint256 dBob) = _armAndSettle(slot, key);
        assertEq(dWinner, cWinner, "same winner as the control");
        assertEq(dCredited, cCredited, "same pot as the control");
        assertEq(dAlice + dBob, cAlice + cBob, "same payees' credit as the control");
    }
}
