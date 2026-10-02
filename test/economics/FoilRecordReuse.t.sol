// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @dev Exposes production record authentication and retirement rules without running
///      unrelated purchases, jackpots, or token payouts.
contract FoilRecordReuseHarness is DegenerusGameStorage {
    function setLevel(uint24 lvl) external { level = lvl; }

    function storeRecord(address player, uint24 lvl, uint24 generationDay, bool ready)
        external returns (uint256 record)
    {
        record = uint256(generationDay) | (uint256(20_000) << _FOIL_MULT_SHIFT)
            | (uint256(0xC0804000) << _FOIL_LINES_SHIFT)
            | (uint256(generationDay) << _FOIL_GENERATED_DAY_SHIFT)
            | (uint256(lvl) << _FOIL_LEVEL_SHIFT) | (ready ? _FOIL_READY : 0);
        foilRecord[lvl & 3][player] = record;
    }

    function recordFor(address player, uint24 lvl) external view returns (uint256) {
        return _foilRecordWord(player, lvl);
    }

    function bought(address player, uint24 lvl) external view returns (bool) {
        return _foilBoughtThisLevel(player, lvl);
    }

    function lines(address player, uint24 lvl) external view returns (uint32[4] memory) {
        return _foilStoredLines(player, lvl);
    }

    function reusable(uint256 record) external view returns (bool) {
        return _foilRecordReusable(record);
    }

    function storeDraw(uint24 day, uint24 lvl) external returns (uint256 draw) {
        draw = _packFoilDraw(0xC0804000, lvl, day, 0xBEEF);
        dailyFoilDraw[day & 1] = draw;
    }

    function drawFor(uint256 day) external view returns (uint256) { return _foilDrawWord(day); }

    function mark(address player, uint24 day, uint256 index) external {
        _markFoilMatchClaimed(player, day, index);
    }

    function claimed(address player, uint24 day, uint256 index) external view returns (bool) {
        return _foilMatchAlreadyClaimed(player, day, index);
    }

    function markers(address player) external view returns (uint256) { return foilMatchClaimed[player]; }
}

contract FoilRecordReuseTest is Test {
    FoilRecordReuseHarness private h;
    address private constant PLAYER = address(0xF011);
    uint24 private day;

    function setUp() public {
        vm.warp(10 days);
        day = GameTimeLib.currentDayIndex();
        h = new FoilRecordReuseHarness();
        h.setLevel(5);
    }

    function test_reuseRequiresGenerationAndCompletedLevel() public {
        assertTrue(h.reusable(0), "empty slot is available");
        uint256 pending = h.storeRecord(PLAYER, 1, 0, false);
        assertFalse(h.reusable(pending), "unfulfilled purchase survives arbitrary age");
        uint256 current = h.storeRecord(PLAYER, 5, day - 3, true);
        assertFalse(h.reusable(current), "same level may seal another draw");
        uint256 future = h.storeRecord(PLAYER, 6, day - 3, true);
        assertFalse(h.reusable(future), "future inventory is not retired");
        uint256 retired = h.storeRecord(PLAYER, 1, day - 3, true);
        assertTrue(h.reusable(retired), "retired and expired pack is reusable");
    }

    function test_lateGenerationKeepsGoldWindowAfterLevelRetirement() public {
        uint256 record = h.storeRecord(PLAYER, 1, day, true);
        assertFalse(h.reusable(record), "gold generation day remains open");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertFalse(h.reusable(record), "following gold day remains open");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(h.reusable(record), "gold deadline expires on second following day");
    }

    function test_retiredPackSurvivesBothLiveDrawDays() public {
        uint256 record = h.storeRecord(PLAYER, 1, day - 3, true);
        h.storeDraw(day, 1);
        assertFalse(h.reusable(record), "today's match still needs its lines");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertFalse(h.reusable(record), "yesterday's match still needs its lines");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(h.reusable(record), "old retained board cannot extend expired rights");
    }

    function test_otherLevelDrawsDoNotPreventReuse() public {
        uint256 record = h.storeRecord(PLAYER, 1, day - 3, true);
        h.storeDraw(day - 1, 2);
        h.storeDraw(day, 3);
        assertTrue(h.reusable(record));
    }

    function test_fourLevelRecordSlotsAuthenticateExactLevelAndCap() public {
        uint256 oldRecord = h.storeRecord(PLAYER, 1, day - 3, true);
        assertEq(h.recordFor(PLAYER, 1), oldRecord);
        assertTrue(h.bought(PLAYER, 1), "old cycle purchase counted");
        assertFalse(h.bought(PLAYER, 5), "shared slot is not purchase in new cycle");
        assertEq(h.recordFor(PLAYER, 5), 0);
        uint32[4] memory absent = h.lines(PLAYER, 5);
        for (uint256 i; i < 4; ++i) assertEq(absent[i], 0);

        assertTrue(h.reusable(oldRecord));
        uint256 newRecord = h.storeRecord(PLAYER, 5, day, false);
        assertEq(h.recordFor(PLAYER, 1), 0, "stale level cannot read a replacement pack");
        assertEq(h.recordFor(PLAYER, 5), newRecord);
        assertTrue(h.bought(PLAYER, 5), "new cycle still allows only one pack");
        assertFalse(h.reusable(newRecord), "replacement cannot overwrite before generation");
    }

    function test_twoDrawSlotsRejectStaleAndWideAliases() public {
        uint256 oldDraw = h.storeDraw(day, 1);
        assertEq(h.drawFor(day), oldDraw);
        assertEq(h.drawFor(uint256(day) + (1 << 24)), 0, "uint24 truncation cannot alias");
        assertEq(h.drawFor(day + 2), 0, "unwritten parity alias is absent");
        uint256 nextDraw = h.storeDraw(day + 2, 2);
        assertEq(h.drawFor(day), 0, "recycled draw rejects old exact day");
        assertEq(h.drawFor(day + 2), nextDraw);
    }

    function test_claimBitmapRolloverPreservesAdjacentDayAndIndependentTickets() public {
        h.mark(PLAYER, day, 0);
        h.mark(PLAYER, day, 2);
        h.mark(PLAYER, day + 1, 3);
        assertTrue(h.claimed(PLAYER, day, 0));
        assertTrue(h.claimed(PLAYER, day, 2));
        assertFalse(h.claimed(PLAYER, day, 1));
        assertFalse(h.claimed(PLAYER, day, 3));
        assertFalse(h.claimed(PLAYER, day + 2, 0));
        assertFalse(h.claimed(address(0xB0B), day, 0));

        h.mark(PLAYER, day + 2, 1);
        assertFalse(h.claimed(PLAYER, day, 0), "new exact day resets recycled bank");
        assertFalse(h.claimed(PLAYER, day + 2, 0));
        assertTrue(h.claimed(PLAYER, day + 2, 1));
        assertTrue(h.claimed(PLAYER, day + 1, 3), "other parity retains yesterday's marker");
        assertEq(h.markers(PLAYER) >> 64, 0, "history remains in two compact banks");
    }
}
