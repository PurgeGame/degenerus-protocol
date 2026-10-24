// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CrapsSlots} from "../helpers/GameSlots.sol";
import {PeripheralSlots} from "../helpers/PeripheralSlots.sol";
import {CrapsLensReader} from "../../contracts/CrapsLens.sol";

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

contract CrapsReuseHarness is CrapsViews {
    function ringWrite(uint24 day) external {
        uint256 slot = uint256(day) * 8 + 6;
        bytes32 key = bytes32(slot);
        _storeBattle(key, _loadBattle(key) + 9);
        _setSlotIndex(slot, 2);
        _storeHighField(key, _loadHighField(key) + 5);
        _storeDayTickets(uint256(day) * 8, _loadDayTickets(uint256(day) * 8) + 7);
        _storeDayStaked(day, _loadDayStaked(day) + 11);
        _storeBudget(day, 13 | (uint256(17) << 112) | (uint256(5) << 224));
    }
    function ringRead(uint24 day) external view returns (uint256[6] memory v) {
        uint256 slot = uint256(day) * 8 + 6;
        v[0] = _loadBattle(bytes32(slot));
        v[1] = _loadSlotState(slot);
        v[2] = _loadHighField(bytes32(slot));
        v[3] = _loadDayTickets(uint256(day) * 8);
        v[4] = _loadDayStaked(day);
        v[5] = _loadBudget(day);
    }
    function boardAt(uint256 slot) external view returns (uint256) { return _loadBattle(bytes32(slot)); }
    function putSeat(uint24 day, uint32 owner, uint256 word) external { _storeDaySeat(uint256(day) * 8, owner, word); }
    function getSeat(uint24 day, uint32 owner) external view returns (uint256) { return _loadDaySeat(uint256(day) * 8, owner); }
    function putDraw(uint64 slot, HighRollerDraw memory draw) external { _storeHighDraw(slot, draw); }
    function putCursor(uint64 slot, uint64 cursor) external { _setBonusCursor(slot, cursor); }
    function rawState(uint64 slot) external view returns (uint256) { return _slotState[slot & 511]; }
    function rawSentinels() external view returns (uint256, uint64, uint64, uint64[4] memory) {
        return (_highRollerReserve, _rngSlotCursor[0], _rngSlotCursor[1], _fundedCustomSlots);
    }
    function rawBet(uint256 id) external view returns (uint256) { return _bets[_betStorageKey(id)]; }
    function physicalKey(uint256 id) external pure returns (uint256) { return _betStorageKey(id); }
    function pending(uint48 index) external view returns (uint256) { return _rngSlots[index].length - _rngCursor(index); }
    function put(uint256 id, uint256 word) external {
        uint256 slot = id >> 64;
        require(slot & 7 == 0, "day fixture");
        _storeDayTickets(slot, uint64(id));
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
        game.registerWallet_g9539(alice, true);
        game.registerWallet_g9539(bob, true);
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
        vm.expectRevert(bytes4(keccak256("NotYourBet()"))); vm.prank(alice); table.amendSlip(oldId, uint32(1));
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
        MineFlipGas.Result memory r = table.resolveRngSlot_g1079(slot, 9_000_000);
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
        vm.prank(address(table)); table.resolveRngSlot_g1079(slot, 9_000_000);
        uint256 paid = coinflip.totalCredited();
        uint256 comps = flip.compAccruals();
        assertGt(paid, 0);
        assertTrue(vm.revertToState(snap));
        snap = vm.snapshotState();
        _warp(day + 30);
        vm.prank(address(table)); table.resolveRngSlot_g1079(slot, 9_000_000);
        assertEq(coinflip.totalCredited(), paid);
        assertEq(flip.compAccruals(), comps);
        assertTrue(vm.revertToState(snap));
        _warp(day + 31);
        vm.prank(address(table));
        MineFlipGas.Result memory r = table.resolveRngSlot_g1079(slot, 9_000_000);
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

    function test_ProductionCallerCannotSkipHeadBeforeExpiry() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1); _open(day);
        (uint64 slot, uint48 index) = _arm(day);
        vm.warp(block.timestamp + 6 hours); table.armWindow(slot + 1);
        _setWord(index, WORD + 1); game.setRngConsumerStage(6);
        vm.expectRevert(abi.encodeWithSignature("OnlyGame()"));
        vm.prank(alice); table.resolveRngSlot_g1079(slot + 1, 9_000_000);
        assertEq(table.pending(index), 2);
        vm.prank(ContractAddresses.GAME);
        JackpotBattle(address(table)).runCrapsReadWork(index, 9_000_000);
        assertEq(table.pending(index), 1);
        assertGt(table.bonusCursorOf(slot), 0);
        assertEq(table.bonusCursorOf(slot + 1), 0);
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
            vm.prank(ContractAddresses.GAME); api.runCrapsMaintenance_g10712(9_000_000);
        }
        (uint256 a,) = table.passCreditsOf(alice);
        (uint256 b,) = table.passCreditsOf(bob);
        assertEq(a, 0); assertEq(b, 0);
        assertEq(coinflip.totalCredited(), 0);
        assertGe(table.minerSlot() / 8, _today() - 30);
        assertEq(uint32(table.betWordOf(_id(day + 64, 1))), game.walletIdOf_g3120(bob));
    }

    function test_ExpiredJackpotCannotAppendOverNewSeatsOrPayReserve() public {
        uint24 day = _today() + 1;
        _buy(alice, day, 1); _open(day);
        JackpotBattle api = JackpotBattle(address(table));
        vm.prank(ContractAddresses.GAME); api.lockJackpotBattle(day + 1, 1 ether, 2);
        (uint64 slot,,,) = api.jackpotProgress();
        uint256 reserve = CrapsLensReader.highRollerReserve(address(api));
        _warp(day + 34); _buy(bob, day + 64, 1);
        uint256 newWord = table.betWordOf(_id(day + 64, 1));
        uint256[] memory field = new uint256[](1);
        field[0] = uint256(game.walletIdOf_g3120(alice)) | (uint256(1) << 160);
        vm.startPrank(ContractAddresses.GAME);
        (,, uint256 remaining) = api.prepareJackpotBattle(2, WORD);
        assertEq(remaining, 0);
        api.appendJackpotBattle(field, 1, true);
        MineFlipGas.Result memory r = api.runDailyBattleWork(9_000_000);
        vm.stopPrank();
        assertTrue(r.done);
        vm.prank(address(table)); api.settleHighRollerReserve(slot);
        assertEq(CrapsLensReader.highRollerReserve(address(api)), reserve);
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
        uint256 dark = uint256(5) << 59;
        uint256 a = uint256(1) | dark | (uint256(4) << 62);
        uint256 b = uint256(2) | dark | (uint256(2) << 62);
        uint256 c = uint256(3) | dark | (uint256(0x3f) << 65);
        table.put(_id(day, 1), a);
        table.put(_id(day, 2), b);
        table.put(_id(day, 3), c);
        assertEq(table.physicalKey(_id(day, 1)), table.physicalKey(_id(day, 3)));
        uint256[3] memory originals = [a, b, c];
        for (uint256 lane; lane < 3; ++lane) {
            uint256 changed = (originals[lane] & ~(uint256(7) << 59)) | (uint256(3) << 59);
            table.setBetWord(_id(day, uint64(lane + 1)), changed);
            for (uint256 other; other < 3; ++other) {
                assertEq(table.betWordOf(_id(day, uint64(other + 1))), other == lane ? changed : originals[other]);
            }
            assertEq(uint24(table.rawBet(_id(day, 1)) >> 216), day, "day tag changed");
            table.setBetWord(_id(day, uint64(lane + 1)), originals[lane]);
        }
        assertEq(table.betWordOf(_id(day, 1)), a);
        assertEq(table.betWordOf(_id(day, 2)), b);
        assertEq(table.betWordOf(_id(day, 3)), c);
        assertEq(table.betWordOf(_id(day, 4)), 0);
        _warp(day + 64);
        table.put(_id(day + 64, 1), a);
        assertEq(table.betWordOf(_id(day, 1)), 0);
        assertEq(table.betWordOf(_id(day + 64, 2)), 0);
        assertEq(table.betWordOf(_id(day + 64, 3)), 0);
    }

    function _mapped(uint256 root, uint256 key) private pure returns (bytes32) {
        if (root == PeripheralSlots.CR_DAY_TICKETS || root == PeripheralSlots.CR_DAY_STAKED || root == PeripheralSlots.CR_BOOST_BUDGET || root == CrapsLensReader.BATTLE_DAYS_SLOT) return bytes32(root + key);
        if (root == CrapsLensReader.JACKPOT_ROUNDS_SLOT) return bytes32(root + key * 5);
        return keccak256(abi.encode(key, root));
    }

    function testFuzz_AllRingsRejectOldTagsAndReplacePoisonedWords(uint24 oldDay) public {
        oldDay = uint24(bound(oldDay, 1, type(uint24).max - 64));
        uint24 fresh = oldDay + 64;
        uint256 physical = (uint256(oldDay) * 8 + 6) & 511;
        uint256 poison = (uint256(oldDay) << 232) | ((uint256(1) << 232) - 1);
        vm.store(address(table), _mapped(CrapsLensReader.BATTLES_SLOT, physical), bytes32(type(uint256).max));
        vm.store(address(table), _mapped(CrapsLensReader.BATTLES_SLOT, physical - 1), bytes32(type(uint256).max));
        vm.store(address(table), _mapped(CrapsLensReader.BATTLE_DAYS_SLOT, oldDay & 63), bytes32(poison));
        vm.store(address(table), _mapped(CrapsLensReader.SLOT_STATE_SLOT, physical), bytes32(poison));
        vm.store(address(table), _mapped(CrapsSlots.HIGH_FIELD, physical), bytes32(poison));
        uint256[3] memory dayRoots = [PeripheralSlots.CR_DAY_TICKETS, PeripheralSlots.CR_DAY_STAKED, PeripheralSlots.CR_BOOST_BUDGET];
        for (uint256 i; i < dayRoots.length; ++i) {
            vm.store(address(table), _mapped(dayRoots[i], oldDay & 63), bytes32(poison));
        }
        uint256[6] memory beforeWrite = table.ringRead(fresh);
        for (uint256 i; i < 6; ++i) assertEq(beforeWrite[i], 0, "mismatched tag exposed stale state");
        table.ringWrite(fresh);
        uint256[6] memory got = table.ringRead(fresh);
        uint256[6] memory expected = [uint256(9), 2, 5, 7, 11, 13 | (uint256(17) << 112) | (uint256(5) << 224)];
        for (uint256 i; i < 6; ++i) assertEq(got[i], expected[i], "stale state survived replacement");
        got = table.ringRead(oldDay);
        for (uint256 i; i < 6; ++i) assertEq(got[i], 0, "old logical day reads replacement");
        assertEq(table.boardAt(uint256(fresh) * 8 + 5), 0, "initialized sibling resurrected old board");
        assertEq(uint256(vm.load(address(table), _mapped(CrapsLensReader.BATTLE_DAYS_SLOT, oldDay & 63))), (uint256(fresh) << 232) | 64);
        assertEq(table.rawState(uint64(uint256(fresh) * 8 + 6)), (uint256(fresh) << 232) | 2, "padding survived");
    }

    function testFuzz_FourSeatLanesPreserveNeighborsAndReplaceWholeStaleLane(uint24 day, uint32 owner) public {
        day = uint24(bound(day, 4, type(uint24).max - 68)) & ~uint24(3);
        uint256 outer = PeripheralSlots.CR_DAY_SEATED + (uint256(day & 63) >> 2);
        bytes32 at = keccak256(abi.encode(owner, outer));
        vm.store(address(table), at, bytes32(type(uint256).max));
        for (uint24 i; i < 4; ++i) table.putSeat(day + i, owner, 11 + i | (uint256(3) << 33));
        uint256 beforeWrite = uint256(vm.load(address(table), at));
        for (uint24 i; i < 4; ++i) {
            assertEq(table.getSeat(day + i, owner), 11 + i | (uint256(3) << 33));
            assertEq(table.getSeat(day + i + 64, owner), 0);
        }
        table.putSeat(day + 65, owner, 23);
        uint256 afterWrite = uint256(vm.load(address(table), at));
        uint256 mask = uint256(type(uint64).max) << 64;
        assertEq(afterWrite & ~mask, beforeWrite & ~mask, "neighbor overwritten");
        assertEq(uint64(afterWrite >> 64), 23 | (uint256(day + 65) << 40), "padding survived");
        assertEq(table.getSeat(day + 1, owner), 0);
        assertEq(table.getSeat(day + 65, owner), 23);
    }

    function test_HighDrawSharesCursorWordAndWrapClearsAllDrawFlags() public {
        uint24 day = _today();
        uint64 slot = uint64(uint256(day) * 8 + 6);
        table.ringWrite(day);
        table.putCursor(slot, 19);
        CrapsBattleStorage.HighRollerDraw memory draw = CrapsBattleStorage.HighRollerDraw(21, 22, 23, true, true);
        table.putDraw(slot, draw);
        table.putCursor(slot, 20);
        assertEq(table.bonusCursorOf(slot), 20);
        assertEq(keccak256(abi.encode(CrapsLensReader.highRollerDrawOf(address(table), slot))), keccak256(abi.encode(draw)));
        uint64 fresh = slot + 512;
        table.ringWrite(day + 64);
        draw = CrapsLensReader.highRollerDrawOf(address(table), fresh);
        assertEq(keccak256(abi.encode(draw)), keccak256(abi.encode(CrapsBattleStorage.HighRollerDraw(0, 0, 0, false, false))));
        assertEq(table.bonusCursorOf(fresh), 0);
        assertEq(table.rawState(fresh), (uint256(day + 64) << 232) | 2);
    }

    function test_JackpotWrapReplacesPoisonedCountsButHidesRetainedEntropyUntilPrepare() public {
        uint24 day = _today();
        JackpotBattle api = JackpotBattle(address(table));
        vm.prank(ContractAddresses.GAME); api.lockJackpotBattle(day + 1, 1 ether, 2);
        (uint64 oldSlot,,,) = api.jackpotProgress();
        assertEq(oldSlot & 7, 7);
        uint256 base = uint256(_mapped(CrapsLensReader.JACKPOT_ROUNDS_SLOT, oldSlot & 511));
        for (uint256 i; i < 5; ++i) vm.store(address(table), bytes32(base + i), bytes32(type(uint256).max));
        _warp(day + 64);
        vm.prank(ContractAddresses.GAME); api.lockJackpotBattle(day + 65, 1 ether, 2);
        (uint64 fresh,,,) = api.jackpotProgress();
        assertEq(fresh, oldSlot + 512);
        (CrapsBattleStorage.JackpotRound memory r,,) = CrapsLensReader.jackpotBattleOf(address(table), fresh);
        assertEq(r.day, day + 64);
        assertEq(r.requestDay, day + 65);
        assertEq(r.drawWord, 0);
        assertEq(r.drawCursor, 0);
        assertEq(r.paidCount, 0);
        assertEq(r.paidUnits, 0);
        assertEq(r.drawnCount, 0);
        assertEq(r.drawnUnits, 0);
        assertEq(r.totalPool, 0);
        assertEq(r.potRemainder, 0);
        assertEq(r.bankroll, 0);
        assertEq(r.bountyUnits, 0);
        assertEq(r.multiplierBps, 0);
        assertEq(r.subsidyMultiplierBps, 0);
        assertEq(r.level, 0);
        assertFalse(r.started);
        assertEq(uint256(vm.load(address(table), bytes32(base))), type(uint256).max, "entropy cleared");
        assertEq(uint256(vm.load(address(table), bytes32(base + 2))), uint256(1) << 192, "bankroll sentinel");
        vm.prank(ContractAddresses.GAME);
        (uint256 word, uint256 cursor,) = api.prepareJackpotBattle(2, WORD);
        assertEq(word, WORD);
        assertEq(cursor, 0);
        (r,,) = CrapsLensReader.jackpotBattleOf(address(table), oldSlot);
        assertEq(r.requestDay, 0, "old round reads new request");
    }

    function test_SentinelsAreNonzeroAtConstruction() public view {
        (uint256 reserve, uint64 a, uint64 b, uint64[4] memory slots) = table.rawSentinels();
        assertEq(reserve, 1);
        assertEq(a, 1); assertEq(b, 1);
        for (uint256 i; i < 4; ++i) assertEq(slots[i], 1);
        assertEq(CrapsLensReader.highRollerReserve(address(table)), 0);
    }

    function _checkFamily(uint256 family) private {
        uint24 oldDay = 100;
        uint24 fresh = oldDay + 64;
        uint256 physical = (uint256(oldDay) * 8 + 6) & 511;
        uint256 poison = (uint256(oldDay) << 232) | ((uint256(1) << 232) - 1);
        uint256[6] memory roots = [CrapsLensReader.BATTLES_SLOT, CrapsLensReader.SLOT_STATE_SLOT, CrapsSlots.HIGH_FIELD, PeripheralSlots.CR_DAY_TICKETS, PeripheralSlots.CR_DAY_STAKED, PeripheralSlots.CR_BOOST_BUDGET];
        uint256 key = family < 3 ? physical : oldDay & 63;
        vm.store(address(table), _mapped(roots[family], key), bytes32(poison));
        if (family == 0) vm.store(address(table), _mapped(CrapsLensReader.BATTLE_DAYS_SLOT, oldDay & 63), bytes32(poison));
        uint256[6] memory got = table.ringRead(fresh);
        assertEq(got[family], 0, "tag check");
        table.ringWrite(fresh);
        got = table.ringRead(fresh);
        uint256[6] memory expected = [uint256(9), 2, 5, 7, 11, 13 | (uint256(17) << 112) | (uint256(5) << 224)];
        assertEq(got[family], expected[family], "reset");
        uint256 encoded = expected[family] | (family == 0 ? 0 : uint256(fresh) << 232);
        assertEq(uint256(vm.load(address(table), _mapped(roots[family], key))), encoded, "whole-word overwrite");
        got = table.ringRead(oldDay);
        assertEq(got[family], 0, "old tag");
    }
    function test_MutationFamily_Scoreboard() public { _checkFamily(0); }
    function test_MutationFamily_SlotStateAndHighDraw() public { _checkFamily(1); }
    function test_MutationFamily_HighField() public { _checkFamily(2); }
    function test_MutationFamily_DayTickets() public { _checkFamily(3); }
    function test_MutationFamily_DayAction() public { _checkFamily(4); }
    function test_MutationFamily_MergedBudgets() public { _checkFamily(5); }

}
