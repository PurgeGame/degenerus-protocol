// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";

contract PinHarness is CrapsViews {
    function isHighOf(uint256 betId) external view returns (bool) {
        return _bets[betId] & _BET_HIGH_BIT != 0;
    }

    function customSlotBase() external pure returns (uint256) {
        return _CUSTOM_SLOT_BASE;
    }

    /// @dev The one reader of a slot's terms every settler and preview goes through.
    function termsKeyOf(uint256 slot) external view returns (bytes32) {
        return _slotWindow(slot).key;
    }
}

/// @title CrapsMutationPins -- the v78 mutation survivors, each pinned by the behaviour it changed
/// @notice Three relational mutants of CrapsBattle outlived the oracle: the gap slot between two
///         days resolving to a window instead of refusing, and a custom battle whose high lane is
///         the smallest legal multiple (2) reading it as "below two". Each is a real branch with
///         no test on it, pinned here.
contract CrapsMutationPins is CrapsPins {
    PinHarness internal craps;
    uint128 internal constant LW = 600e18;
    uint24 internal constant SU = 0;
    uint256 internal constant PLAIN_WORD = 40 << 8;

    address internal alice = makeAddr("alice");

    function setUp() public {
        _installPins();
        craps = new PinHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());
    }

    function _boardA() internal pure returns (Craps.Bets memory b) {
        b.passLine = 3;
        b.place6 = 3;
        b.place8 = 1;
    }

    /// @notice `_slotOf(day, period)` is `day * 8 + period + 1`, so every multiple of eight is the
    ///         reserved gap between two days. Naming one as a window is refused wherever a slot's
    ///         terms are read, not resolved as some neighbouring period.
    function test_gapSlotBetweenDaysIsNoBattle() public {
        uint64 gap = uint64(uint256(craps.currentDayIndex()) * 8);
        vm.expectRevert(CrapsBattle.NoSuchBattle.selector);
        craps.termsKeyOf(gap);
        vm.expectRevert(CrapsBattle.NoSuchBattle.selector);
        craps.termsKeyOf(0);
        // And through the permissionless door: the gap sits below the window taking bets, so the
        // only thing that refuses it is the terms read.
        vm.expectRevert(CrapsBattle.NoSuchBattle.selector);
        craps.armBonusWindow(gap);
        // The period right after the gap is a real window.
        assertTrue(craps.termsKeyOf(gap + 1) != bytes32(0), "period zero of the day is a window");
    }

    /// @notice The custom slot base is not a battle: custom slots start one above it.
    function test_customSlotBaseIsNoBattle() public {
        uint256 base = craps.customSlotBase();
        vm.expectRevert(CrapsBattle.NoSuchBattle.selector);
        craps.termsKeyOf(base);
    }

    /// @notice A custom battle whose slot number is a multiple of eight (the eighth one opened sits
    ///         at base + 8) is still a custom battle: its amendment door is the custom close time,
    ///         never the day-ticket rule that keys on `slot % 8 == 0` for scheduled slots.
    function test_eighthCustomBattleAmendsUnderTheCustomClose() public {
        uint40 close = uint40(vm.getBlockTimestamp() + 1 hours);
        uint32 played = uint32(LW / 1 ether);
        uint64 slot;
        for (uint256 i; i < 8; ++i) {
            vm.prank(vaultOwner);
            slot = craps.createBattle(played, 2, 5, SU, 0, close, true, 0);
        }
        assertEq(slot, uint64(craps.customSlotBase() + 8), "the eighth custom sits at base + 8");
        assertEq(slot % 8, 0, "and its number is a multiple of eight");

        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, _boardA(), 1);
        // Before the close the holder may re-spread freely.
        vm.prank(alice);
        craps.amendSlip(betId, _boardB());
        // Past the close the field is frozen, whatever the slot number looks like.
        vm.warp(close);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.amendSlip(betId, _boardA());
    }

    function _boardB() internal pure returns (Craps.Bets memory b) {
        b.place6 = 3;
        b.place8 = 3;
        b.place9 = 1;
    }

    /// @notice A custom battle may name two as its high multiple, the smallest legal lane. A seat
    ///         at two is then a high seat, one is the ordinary seat, and anything else is refused.
    function test_customBattleHighLaneOfTwoIsAHighSeat() public {
        uint40 close = uint40(vm.getBlockTimestamp() + 1 hours);
        uint32 played = uint32(LW / 1 ether);
        vm.prank(vaultOwner);
        uint64 slot = craps.createBattle(played, 2, 5, SU, 0, close, true, 2);

        vm.prank(alice);
        uint256 high = craps.enterBattle(slot, _boardA(), 2);
        assertTrue(craps.isHighOf(high), "a seat at the named multiple is the high seat");

        vm.prank(alice);
        uint256 normal = craps.enterBattle(slot, _boardA(), 1);
        assertFalse(craps.isHighOf(normal), "a seat at one is the ordinary seat");

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), 3);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), 0);
    }
}
