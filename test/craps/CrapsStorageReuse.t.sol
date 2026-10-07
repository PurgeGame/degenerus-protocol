// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

contract CrapsReuseHarness is CrapsViews {
    function rawBet(uint256 id) external view returns (uint256) { return _bets[_betStorageKey(id)]; }
    function physicalKey(uint256 id) external pure returns (uint256) { return _betStorageKey(id); }
    function pending(uint48 index) external view returns (uint256) { return _rngPending[index]; }
    function put(uint256 id, uint256 word) external {
        uint256 slot = id >> 64;
        require(slot & 7 == 0, "day fixture");
        _dayTickets[slot] = uint64(id);
        _appendBet(id, word);
    }
    function resolveOne(uint64 slot) external returns (MineFlipGas.Result memory) {
        return _resolveSlotRange(slot, 9_000_000, 1);
    }
}

contract CrapsStorageReuseTest is CrapsPins {
    CrapsReuseHarness table;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant WORD = 123456789;

    function setUp() public {
        _installPins();
        game.registerWallet(alice, true);
        game.registerWallet(bob, true);
        // Start beyond bank 63, so even the first round exercises physical/logical separation.
        vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + 100) * 1 days + 82_620);
        table = new CrapsReuseHarness();
        vm.warp(block.timestamp + 1 days);
        game.setScore(alice, table.SYBIL_SCORE_FLOOR());
        game.setScore(bob, table.SYBIL_SCORE_FLOOR());
    }

    function _today() private view returns (uint24) { return GameTimeLib.currentDayIndex(); }
    function _warp(uint24 day) private { vm.warp((ContractAddresses.DEPLOY_DAY_BOUNDARY + uint256(day) - 1) * 1 days + 82_620); }
    function _id(uint24 day, uint64 seat) private pure returns (uint256) { return (uint256(day) << 67) | seat; }
    function _buy(address player, uint24 day, uint8 count) private {
        vm.prank(player); table.buyFutureCrapsDays(day, count, false, uint32(0));
    }
    function _open(uint24 day) private {
        _warp(day); _setDailyWord(day, WORD);
        vm.prank(ContractAddresses.GAME); table.openBonusDay();
    }
    function _arm(uint24 day) private returns (uint64 slot, uint48 index) {
        slot = uint64(uint256(day) * 8 + 1);
        vm.warp(block.timestamp + 21 minutes);
        index = table.armWindow(slot);
    }

    function test_ThirtyDayBookingLimitIsAtomicForBothPurchaseAndPasses() public {
        uint24 today = _today();
        uint256 burned = flip.totalBurned();
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        _buy(alice, today + 30, 2);
        assertEq(flip.totalBurned(), burned);
        assertEq(table.dayTicketsOf(today + 30), 0);
        _buy(alice, today + 30, 1);
        assertEq(table.daySeatNumberOf(today + 30, alice), 1);
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        _buy(bob, today + 31, 1);
        vm.prank(ContractAddresses.GAME); table.creditPasses(_idFor(bob), 2, 0);
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        vm.prank(bob); table.applyCrapsPasses(today + 30, 2, false, uint32(0));
        (uint256 credits,) = table.passCreditsOf(bob);
        assertEq(credits, 2);
        vm.prank(bob); table.applyCrapsPasses(today + 30, 1, false, uint32(0));
        assertEq(table.daySeatNumberOf(today + 30, bob), 2);
    }

    function test_ReusedBetAndMembershipRejectOldIdsAndUnwrittenTail() public {
        uint24 oldDay = _today() + 1;
        _buy(alice, oldDay, 1); _buy(bob, oldDay, 1);
        uint256 oldId = _id(oldDay, 1);
        uint256 original = table.betWordOf(oldId);
        uint24 newDay = oldDay + 64;
        _warp(newDay - 30);
        _buy(alice, newDay, 1);
        uint256 newId = _id(newDay, 1);
        assertEq(table.physicalKey(oldId), table.physicalKey(newId));
        assertEq(table.betWordOf(newId), original, "tag altered game fields");
        assertEq(table.betWordOf(oldId), 0, "old ID read a new bet");
        assertEq(table.betWordOf(_id(newDay, 2)), 0, "new tail read an old bet");
        assertEq(table.daySeatNumberOf(oldDay, alice), 0);
        assertEq(table.daySeatNumberOf(newDay, alice), 1);
        vm.expectRevert(); vm.prank(alice); table.amendSlip(oldId, uint32(1));
        assertEq(table.betWordOf(newId), original);
        vm.prank(alice); table.amendSlip(newId, uint32(1));
        assertEq((table.betWordOf(newId) >> 32) & 3, 1);
    }

    function test_ExpiredReadCohortCannotPayReusedBetsAndDrainsOnce() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1);
        _open(day);
        (uint64 slot, uint48 index) = _arm(day);
        vm.warp(block.timestamp + 6 hours);
        assertEq(table.armWindow(slot + 1), index);
        assertEq(table.pending(index), 2);
        _warp(day + 34);
        _buy(bob, day + 64, 1);
        uint256 newWord = table.betWordOf(_id(day + 64, 1));
        uint256 beforeCredits = coinflip.totalCredited();
        uint256 beforeComps = flip.compAccruals();
        _setWord(index, WORD + 17);
        game.setRngConsumerStage(6);
        JackpotBattle api = JackpotBattle(address(table));
        vm.prank(ContractAddresses.GAME); api.runCrapsReadWork(index, 9_000_000);
        assertEq(table.pending(index), 0);
        vm.prank(ContractAddresses.GAME); api.runCrapsReadWork(index, 9_000_000);
        vm.prank(address(table));
        MineFlipGas.Result memory r = table.resolveRngSlot(slot, 9_000_000);
        assertTrue(r.done);
        assertEq(coinflip.totalCredited(), beforeCredits);
        assertEq(flip.compAccruals(), beforeComps);
        assertEq(table.betWordOf(_id(day + 64, 1)), newWord);
    }

    function test_DayThirtyStillPaysIdenticallyAndDayThirtyOneExpires() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1); _open(day);
        (uint64 slot, uint48 index) = _arm(day);
        _setWord(index, WORD + 1);
        uint256 snap = vm.snapshotState();
        vm.prank(address(table)); table.resolveRngSlot(slot, 9_000_000);
        uint256 paid = coinflip.totalCredited();
        uint256 comps = flip.compAccruals();
        assertGt(paid, 0);
        assertTrue(vm.revertToState(snap));
        snap = vm.snapshotState();
        _warp(day + 30);
        vm.prank(address(table)); table.resolveRngSlot(slot, 9_000_000);
        assertEq(coinflip.totalCredited(), paid);
        assertEq(flip.compAccruals(), comps);
        assertTrue(vm.revertToState(snap));
        _warp(day + 31);
        vm.prank(address(table));
        MineFlipGas.Result memory r = table.resolveRngSlot(slot, 9_000_000);
        assertTrue(r.done);
        assertEq(coinflip.totalCredited(), 0);
        assertEq(flip.compAccruals(), 0);
    }

    function test_PartialSettlementThenExpirationCannotPayAgain() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1); _buy(bob, day, 1); _open(day);
        (uint64 slot, uint48 index) = _arm(day);
        _setWord(index, WORD + 1); game.setRngConsumerStage(6);
        MineFlipGas.Result memory r = table.resolveOne(slot);
        assertTrue(r.progressed && !r.done);
        uint256 paid = coinflip.totalCredited();
        uint256 comps = flip.compAccruals();
        _warp(day + 34); _buy(bob, day + 64, 1);
        uint256 newWord = table.betWordOf(_id(day + 64, 1));
        for (uint256 i; i < 2; ++i) {
            vm.prank(ContractAddresses.GAME);
            r = JackpotBattle(address(table)).runCrapsReadWork(index, 9_000_000);
            assertTrue(r.done);
        }
        assertEq(table.pending(index), 0);
        assertEq(coinflip.totalCredited(), paid);
        assertEq(flip.compAccruals(), comps);
        assertEq(table.betWordOf(_id(day + 64, 1)), newWord);
    }

    function test_ExpirationSkipsAlreadyCompletedLaterQueueSlot() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1); _open(day);
        (uint64 slot, uint48 index) = _arm(day);
        vm.warp(block.timestamp + 6 hours); table.armWindow(slot + 1);
        _setWord(index, WORD + 1); game.setRngConsumerStage(6);
        vm.prank(address(table)); table.resolveRngSlot(slot + 1, 9_000_000);
        assertEq(table.pending(index), 1);
        uint256 paid = coinflip.totalCredited();
        _warp(day + 34); _buy(bob, day + 64, 1);
        vm.prank(ContractAddresses.GAME);
        MineFlipGas.Result memory r = JackpotBattle(address(table)).runCrapsReadWork(index, 9_000_000);
        assertTrue(r.done);
        assertEq(table.pending(index), 0);
        assertEq(coinflip.totalCredited(), paid);
    }

    function test_ExpiredLapsedDayCannotRefundTheNewReservation() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1);
        _warp(day + 34);
        _buy(bob, day + 64, 1);
        game.setRngConsumerStage(7);
        JackpotBattle api = JackpotBattle(address(table));
        for (uint256 i; i < 3; ++i) {
            vm.prank(ContractAddresses.GAME); api.runCrapsMaintenance(9_000_000);
        }
        (uint256 a,) = table.passCreditsOf(alice);
        (uint256 b,) = table.passCreditsOf(bob);
        assertEq(a, 0); assertEq(b, 0);
        assertEq(coinflip.totalCredited(), 0);
        assertGe(table.keeperSlot() / 8, _today() - 30);
        assertEq(uint32(table.betWordOf(_id(day + 64, 1))), game.walletIdOf(bob));
    }

    function test_ExpiredJackpotCannotAppendOverNewSeatsOrPayReserve() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1); _open(day);
        JackpotBattle api = JackpotBattle(address(table));
        vm.prank(ContractAddresses.GAME); api.lockJackpotBattle(day + 1, 1 ether, 2);
        (uint64 slot,,,) = api.jackpotProgress();
        uint256 reserve = api.highRollerReserve();
        _warp(day + 34); _buy(bob, day + 64, 1);
        uint256 newWord = table.betWordOf(_id(day + 64, 1));
        uint256[] memory field = new uint256[](1);
        field[0] = uint256(game.walletIdOf(alice)) | (uint256(1) << 160);
        vm.startPrank(ContractAddresses.GAME);
        (,, uint256 remaining) = api.prepareJackpotBattle(2, WORD);
        assertEq(remaining, 0);
        api.appendJackpotBattle(field, 1, true);
        MineFlipGas.Result memory r = api.runDailyBattleWork(9_000_000);
        vm.stopPrank();
        assertTrue(r.done);
        vm.prank(address(table)); api.settleHighRollerReserve(slot);
        assertEq(api.highRollerReserve(), reserve);
        assertEq(coinflip.totalCredited(), 0);
        assertEq(table.betWordOf(_id(day + 64, 1)), newWord);
        (,, bool started, bool complete) = api.jackpotProgress();
        assertTrue(started && complete);
    }

    function testFuzz_TagPreservesMoneyFlagsAndRejectsForgedDay(uint24 day, uint32 seat, uint256 word) public {
        day = uint24(bound(day, 1, type(uint24).max - 64));
        seat = uint32(bound(seat, 1, type(uint32).max));
        _warp(day);
        uint256 id = _id(day, seat);
        table.put(id, word);
        uint256 fields = uint256(type(uint72).max);
        assertEq(table.betWordOf(id), word & fields);
        assertEq(table.betWordOf(_id(day + 64, seat)), 0);
        assertEq(table.betWordOf(id + (uint256(1) << 91)), 0, "uint24 truncation accepted forged day");
        uint256 raw = table.rawBet(id);
        assertEq(uint24(raw >> 216), day, "shared word day");
        assertEq(table.betWordOf(id) >> 72, 0, "day tickets are paid entries");
    }
    function test_ThreeLanesShareWordAndAmendPreservesBothNeighbors() public {
        uint24 day = _today();
        uint256 a = uint256(1) | (uint256(3) << 32);
        uint256 b = uint256(2) | (uint256(5) << 62);
        uint256 c = uint256(3) | (uint256(0x7f) << 65);
        table.put(_id(day, 1), a);
        table.put(_id(day, 2), b);
        table.put(_id(day, 3), c);
        assertEq(table.physicalKey(_id(day, 1)), table.physicalKey(_id(day, 3)));
        table.setBetWord(_id(day, 2), b | (uint256(7) << 32));
        assertEq(table.betWordOf(_id(day, 1)), a);
        assertEq(table.betWordOf(_id(day, 2)), b | (uint256(7) << 32));
        assertEq(table.betWordOf(_id(day, 3)), c);
        assertEq(table.betWordOf(_id(day, 4)), 0);
        _warp(day + 64);
        table.put(_id(day + 64, 1), a);
        assertEq(table.betWordOf(_id(day, 1)), 0);
        assertEq(table.betWordOf(_id(day + 64, 2)), 0);
        assertEq(table.betWordOf(_id(day + 64, 3)), 0);
    }

}
