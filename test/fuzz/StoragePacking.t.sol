// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract ClaimPackingHarness is DegenerusGameStorage, WalletSeed {
    function bingo(uint24 lvl, address player) external { _markBingoClaimed(lvl, _seedWallet(player)); }
    function markAffiliate(uint24 lvl, address player) external { _markAffiliateDgnrsClaimed(lvl, _seedWallet(player)); }
    function bingoClaimed(uint24 lvl, address player) external view returns (bool) { return _bingoClaimed(lvl, _walletIdOf(player)); }
    function affiliateClaimed(uint24 lvl, address player) external view returns (bool) { return _affiliateDgnrsClaimed(lvl, _walletIdOf(player)); }
}

contract CrapsPackingHarness is CrapsBattleStorage {
    function index(uint256 slot, uint48 value) external { _setSlotIndex(slot, value); }
    function cursor(uint256 slot, uint64 value) external { _setBonusCursor(slot, value); }
    function state(uint256 slot) external view returns (uint48, uint64) { return (_slotIndexOf(slot), _bonusCursorOf(slot)); }
    function reserve(uint24 day, uint8 period, uint32 player) external { _claimScheduledSeat(uint256(day) * 8 + period + 1, player); }
    function seated(uint24 day, uint8 period, uint32 player) external view returns (bool) { return _loadDaySeat(uint256(day) * 8, player) & (uint256(1) << (33 + period)) != 0; }
    function daySeat(uint24 day, uint32 player, uint32 seat) external { _storeDaySeat(uint256(day) * 8, player, seat); }
    function customSeat(bytes32 battleKey, uint32 player) external { _bonusSeated[battleKey][player] = true; }
    function customSeated(bytes32 battleKey, uint32 player) external view returns (bool) { return _bonusSeated[battleKey][player]; }
}

contract StoragePackingTest is Test {
    uint32 private constant SEAT_ID = 5;

    function testFuzz_ClaimSiblingStampsAndRollover(uint24 a, uint24 b, uint24 c, address player) public {
        ClaimPackingHarness h = new ClaimPackingHarness();
        a &= ~uint24(1);
        b |= 1;
        if (c == 0) c = 1;
        assertFalse(h.bingoClaimed(0, player));
        h.bingo(a, player);
        h.markAffiliate(c, player);
        h.bingo(b, player);
        assertTrue(h.bingoClaimed(a, player));
        assertTrue(h.bingoClaimed(b, player));
        assertTrue(h.affiliateClaimed(c, player));
        uint24 next = a < type(uint24).max - 1 ? a + 2 : 0;
        h.bingo(next, player);
        assertFalse(h.bingoClaimed(a, player));
        assertTrue(h.bingoClaimed(next, player));
        assertTrue(h.bingoClaimed(b, player));
        assertTrue(h.affiliateClaimed(c, player));
        h.markAffiliate(c == type(uint24).max ? 1 : c + 1, player);
        assertFalse(h.affiliateClaimed(c, player));
        assertTrue(h.bingoClaimed(next, player));
        assertTrue(h.bingoClaimed(b, player));
    }

    function testFuzz_CrapsIndexAndCursorPreserveEachOther(uint256 slot, uint48 index, uint64 cursor) public {
        CrapsPackingHarness h = new CrapsPackingHarness();
        h.index(slot, index);
        h.cursor(slot, cursor);
        (uint48 i, uint64 c) = h.state(slot);
        assertEq(i, index); assertEq(c, cursor);
        h.index(slot, type(uint48).max);
        (i, c) = h.state(slot);
        assertEq(i, type(uint48).max); assertEq(c, cursor);
        h.cursor(slot, type(uint64).max);
        (i, c) = h.state(slot);
        assertEq(i, type(uint48).max); assertEq(c, type(uint64).max);
        h.index(slot, 0);
        (i, c) = h.state(slot);
        assertEq(i, 0); assertEq(c, type(uint64).max);
    }

    function test_FarFutureWindowFlagsDaySeatAndCustomMembership() public {
        CrapsPackingHarness h = new CrapsPackingHarness();
        uint24 day = type(uint24).max;
        for (uint8 p; p < 6; ++p) {
            assertFalse(h.seated(day, p, SEAT_ID));
            h.reserve(day, p, SEAT_ID);
            for (uint8 q; q < 6; ++q) assertEq(h.seated(day, q, SEAT_ID), q <= p);
            vm.expectRevert(CrapsBattleStorage.AlreadyInBonus.selector);
            h.reserve(day, p, SEAT_ID);
        }
        h.daySeat(day - 1, SEAT_ID, type(uint32).max);
        for (uint8 p; p < 6; ++p) {
            vm.expectRevert(CrapsBattleStorage.AlreadyInBonus.selector);
            h.reserve(day - 1, p, SEAT_ID);
        }
        bytes32 custom = keccak256("custom battle key");
        assertFalse(h.customSeated(custom, SEAT_ID));
        h.customSeat(custom, SEAT_ID);
        assertTrue(h.customSeated(custom, SEAT_ID));
        assertFalse(h.customSeated(keccak256("another custom battle key"), SEAT_ID));
    }
}
