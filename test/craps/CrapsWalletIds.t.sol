// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {CrapsPins, MockGame, MockFlip, MockQuests, MockCoinflip} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LegacyCrapsEngine} from "../helpers/LegacyCrapsEngine.sol";
import {CrapsEngine} from "../../contracts/CrapsEngine.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The table plus the raw readers and fixture writers the wallet-ID suite grades through.
contract WalletIdTable is CrapsViews {




    function idWord(uint32 id) external view returns (uint256) {
        return _passCreditsById[id];
    }

    function setIdWord(uint32 id, uint256 word) external {
        _passCreditsById[id] = word;
    }

    function windowOf(uint64 slot) external view returns (Window memory) {
        return _slotWindow(slot);
    }

    function daySeatOfId(uint24 day, uint32 id) external view returns (uint256) {
        return _loadDaySeat(uint256(day) * _BONUS_SLOTS_PER_DAY, id) & _MASK32;
    }

    function bonusSeatedOf(bytes32 key, uint32 id) external view returns (bool) {
        return _bonusSeated[key][id];
    }

    /// @dev A one-seat scheduled field owned by wallet `id`, finalized at `score` through the
    ///      shipped fold and payout.
    function standField(bytes32 key, uint64 slot, uint32 id, uint256 score, uint256 bankrollFlip) external {
        _battles[key] = 1;
        _appendBet((uint256(slot) << 64) | 1, uint256(id));
        Window memory w;
        w.key = key;
        w.bound = uint48(slot);
        w.bankroll = uint128(bankrollFlip);
        w.goal = uint128(bankrollFlip * _SCHED_GOAL);
        w.played = bankrollFlip / _SCHED_BANK_MULT;
        w.tier = 1;
        _setSlotIndex(slot, 1);
        (bool ok,) = address(this).call(
            abi.encodeWithSignature("registerRngSlot(uint48,uint64,bytes32)", uint48(0), slot, key)
        );
        require(ok, "synthetic field registration");
        _scoreBattle(w, score, 1, 0);
    }

    /// @dev The composite a scheduled goal at `peakFlip` folds.
    function goalScore(uint256 peakFlip) external pure returns (uint256) {
        Settlement memory s;
        s.stop = Craps.SlipStop.Goal;
        s.peak = peakFlip;
        s.won = peakFlip;
        return _compositeOf(s);
    }
}

/// @title Craps under wallet IDs
/// @notice Every Craps per-player key is the Game wallet ID: doors fetch it first (paying doors
///         register, the rest require one), bets store it in bits 0..31, passes live in the
///         ID-keyed word, and every payout credits by ID.
contract CrapsWalletIdsTest is CrapsPins {
    WalletIdTable internal c;
    LegacyCrapsEngine private legacyEngine;
    uint256 internal dayStart;
    uint24 internal day;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint32 internal constant BOARD = 3 | (3 << 12) | (1 << 15);
    uint32 internal constant BOARD_B = 2 | (1 << 3);
    uint256 internal constant ADDRESS_SLOT = 14;
    uint256 internal constant ID_SLOT = 14;
    uint256 internal constant INIT = 1 << 84;
    uint256 internal constant ID_SHIFT = 85;
    uint256 internal constant HIGH_BIT = 1 << 65;
    uint256 internal constant DAY_HIGH_MASK = 0x3F << 65;
    uint256 internal constant AWARD_UNIT_BIT = 1 << 72;
    uint256 internal constant MID_MASK = ~((uint256(1) << 73) - 1);

    address internal alice = makeAddr("wid-alice");
    address internal bob = makeAddr("wid-bob");
    address internal carol = makeAddr("wid-carol");
    address internal dave = makeAddr("wid-dave");
    address internal stranger = makeAddr("wid-stranger");

    function setUp() public {
        _installPins();
        legacyEngine = new LegacyCrapsEngine();
        c = WalletIdTable(deployCode("CrapsWalletIds.t.sol:WalletIdTable"));
        flip.setCompLane(1e30);
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        dayStart = vm.getBlockTimestamp() + 1 days - elapsed;
        vm.warp(dayStart);
        day = c.currentDayIndex();
        _setIndex(0);
        _setDailyWord(day, PLAIN_WORD);
        // The Game's rule from here on: a paying contact allocates, any other contact needs an ID.
        game.setStrictWalletIds(true);
    }

    // ── fixtures ─────────────────────────────────────────────────────────────

    function _open() internal {
        vm.prank(ContractAddresses.GAME);
        c.openBonusDay();
    }

    function _register(address who) internal returns (uint32) {
        return game.registerWallet(who, true);
    }




    function _boardOf(uint256 word) internal pure returns (uint32 chips) {
        (chips,) = CrapsPreferenceLib.decode(word);
    }

    function _normal(uint256 word) internal pure returns (uint256) {
        return uint32(word);
    }

    function _high(uint256 word) internal pure returns (uint256) {
        return uint32(word >> 32);
    }




    function _idSlot(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), ID_SLOT));
    }

    function _daySlot(uint24 d) internal pure returns (uint256) {
        return uint256(d) * 8;
    }

    function _dayBet(uint24 d, uint256 seat) internal pure returns (uint256) {
        return (_daySlot(d) << 64) | seat;
    }

    function _assertOwnerWord(uint256 betId, uint32 id) internal view {
        uint256 w = c.betWordOf(betId);
        assertEq(uint32(w), id, "bet word bits 0..31 are the owner's wallet ID");
        assertEq(w & MID_MASK, 0, "bet word reserved bits are zero");
    }

    function _code(uint256 kind, address to, bool high, uint256 arg, uint256 count) internal view returns (uint256) {
        return uint256(game.walletIdOf(to)) | (kind << 160) | (high ? (uint256(1) << 168) : 0) | (arg << 176) | (count << 200);
    }

    function _customSlot(bool multiEntry) internal returns (uint64 slot) {
        uint16 goal = uint16(c.MIN_BATTLE_GOAL_MULT());
        uint40 closeAt = uint40(vm.getBlockTimestamp() + 1 hours);
        vm.prank(vaultOwner);
        slot = c.createBattle(600, 10, goal, 0, closeAt, multiEntry, 0);
    }

    /// @dev The stored chip slice, read off the raw bet word (no window terms needed).
    function _chipsOf(uint256 betId) internal view returns (uint256) {
        return (c.betWordOf(betId) >> 32) & ((uint256(1) << 30) - 1);
    }

    function _t0(Vm.Log memory l) internal pure returns (bytes32) {
        return l.topics.length == 0 ? bytes32(0) : l.topics[0];
    }

    function _idx(Vm.AccountAccess[] memory a, address target, bytes4 sel) internal pure returns (uint256) {
        for (uint256 i; i < a.length; ++i) {
            if (a[i].account != target || a[i].data.length < 4 || bytes4(a[i].data) != sel) continue;
            if (a[i].kind == VmSafe.AccountAccessKind.Call || a[i].kind == VmSafe.AccountAccessKind.StaticCall) return i;
        }
        return type(uint256).max;
    }

    // ── 1. First contact on the four paying doors ────────────────────────────

    /// @dev Door 0 enterBonusBattle, 1 enterBattle, 2 enterBonusDay, 3 buyFutureCrapsDays.
    function _payingDoor(address p, uint256 door, uint64 customSlot) internal returns (uint256 betId) {
        vm.prank(p);
        if (door == 0) {
            betId = c.enterBonusBattle(1, BOARD, 1);
        } else if (door == 1) {
            betId = c.enterBattle(customSlot, BOARD, 1);
        } else if (door == 2) {
            c.enterBonusDay(BOARD, 1);
            betId = _dayBet(day, c.daySeatNumberOf(day, p));
        } else {
            c.buyFutureCrapsDays(day + 1, 1, false, BOARD);
            betId = _dayBet(day + 1, c.daySeatNumberOf(day + 1, p));
        }
    }

    function test_firstContactRegistersBeforeTheBurnOnEveryPayingDoor() public {
        _open();
        uint64 custom = _customSlot(true);
        uint8[4] memory flags = [uint8(0x1), 0x1, 0x7, 0x2];
        for (uint256 door; door < 4; ++door) {
            address p = makeAddr(string.concat("first-contact-", vm.toString(door)));
            assertEq(game.walletIdOf(p), 0, "fixture: fresh wallet");
            uint32 expected = game.walletCount() + 1;
            vm.expectCall(address(game), abi.encodeCall(MockGame.registerWallet, (p, true)), 1);
            vm.expectCall(address(flip), abi.encodeWithSelector(MockFlip.burnCoinForCraps.selector, p, expected));
            vm.expectCall(address(quests), abi.encodeCall(MockQuests.recordCrapsAction, (expected, flags[door])));
            vm.recordLogs();
            vm.startStateDiffRecording();
            uint256 betId = _payingDoor(p, door, custom);
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            Vm.Log[] memory logs = vm.getRecordedLogs();

            uint32 id = game.walletIdOf(p);
            assertEq(id, expected, "the door allocated the next wallet ID");
            uint256 reg = _idx(acc, address(game), MockGame.registerWallet.selector);
            uint256 burn = _idx(acc, address(flip), MockFlip.burnCoinForCraps.selector);
            assertTrue(reg != type(uint256).max && burn != type(uint256).max, "registration and burn both ran");
            assertLt(reg, burn, "registration precedes the burn");
            assertEq(flip.lastCrapsId(), id, "FLIP received the wallet ID");
            _assertOwnerWord(betId, id);
            assertEq(_boardOf(c.idWord(id)), BOARD, "the board is saved in the ID word");
            uint256 slips;
            for (uint256 i; i < logs.length; ++i) {
                if (_t0(logs[i]) != CrapsBattleStorage.CrapsSlipPlaced.selector) continue;
                assertEq(uint256(logs[i].topics[1]), id, "CrapsSlipPlaced topic1 is the ID");
                ++slips;
            }
            assertEq(slips, 1, "one slip per door");
        }
    }

    // ── 2. Non-paying doors ──────────────────────────────────────────────────

    function test_nonPayingDoorsRevertNoWalletIdForAnUnregisteredWallet() public {
        _open();
        uint256 someBet = _payingDoor(alice, 0, 0);

        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NoWalletId.selector);
        c.setPreferredBoard(0, BOARD);

        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NoWalletId.selector);
        c.amendSlip(someBet, BOARD);

        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NoWalletId.selector);
        c.applyCrapsPasses(day + 1, 1, false, BOARD);

        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NoWalletId.selector);
        c.convertNormalToHigh(0, 1);

        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NoWalletId.selector);
        c.upgradeReservedDay(0, day + 1);

        assertEq(game.walletIdOf(stranger), 0, "no ID was allocated");
    }

    /// @dev The paying upgrade registers first; a wallet with no ticket then reverts and the
    ///      registration unwinds with it.
    function test_upgradeDayWindowsByAFirstContactUnwindsItsRegistration() public {
        _open();
        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NoSuchBet.selector);
        c.upgradeDayWindows(0, day, 1);
        assertEq(game.walletIdOf(stranger), 0, "the failed upgrade left no wallet ID");
    }




    function test_convertAndUpgradeReservedDayLeaveTheAddressWordUntouched() public {
        uint32 id = _register(alice);
        vm.startPrank(ContractAddresses.GAME);
        uint24 reserved = c.deliverPasses(id, 1, 0);
        c.creditPasses(id, 21, 0);
        vm.stopPrank();
        vm.expectCall(address(game), abi.encodeCall(MockGame.registerWallet, (alice, false)), 2);
        vm.prank(alice);
        c.convertNormalToHigh(0, 1);
        uint256 w = c.idWord(id);
        assertEq(_normal(w), 0, "21 normals debited from the ID word");
        assertEq(_high(w), 1, "one high credited to the ID word");

        vm.prank(alice);
        c.upgradeReservedDay(0, reserved);
        w = c.idWord(id);
        assertEq(_high(w), 0, "the high pass was debited from the ID word");
        assertEq(_normal(w), 1, "the normal pass was banked back into the ID word");
        assertEq(c.betWordOf(_dayBet(reserved, c.daySeatOfId(reserved, id))) & DAY_HIGH_MASK, DAY_HIGH_MASK);
    }

    // ── 3. Fast path ─────────────────────────────────────────────────────────




    // ── 4. Locked save ───────────────────────────────────────────────────────




    // ── 5. vaultComp ─────────────────────────────────────────────────────────

    function test_vaultCompRefusesAnUnallocatedRecipientId() public {
        _open();
        uint256 code = _code(4, stranger, false, 0, 2);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        c.vaultComp(code);
        assertEq(game.walletIdOf(stranger), 0);
    }

    function test_vaultCompSeatsAnUncachedRecipientByIdOnBoardZero() public {
        _open();
        address[5] memory to = [makeAddr("comp-0"), makeAddr("comp-1"), makeAddr("comp-2"), makeAddr("comp-4"), makeAddr("comp-5")];
        uint32[5] memory ids;
        for (uint256 i; i < 5; ++i) ids[i] = _register(to[i]);

        vm.startPrank(ContractAddresses.VAULT);
        c.vaultComp(_code(0, to[0], false, 1, 0));
        c.vaultComp(_code(1, to[1], false, 0, 0));
        c.vaultComp(_code(2, to[2], false, day + 1, 1));
        c.vaultComp(_code(4, to[3], false, 0, 2));
        c.vaultComp(_code(5, to[4], false, day + 1, 1) | (uint256(1) << 208));
        vm.stopPrank();

        uint256 k0 = (uint256(_daySlot(day) + 2) << 64) | 1;
        _assertOwnerWord(k0, ids[0]);
        assertEq(_chipsOf(k0), 0, "kind 0 on board zero");
        uint256 k1 = _dayBet(day, c.daySeatOfId(day, ids[1]));
        _assertOwnerWord(k1, ids[1]);
        assertEq(_chipsOf(k1), 0, "kind 1 on board zero");
        uint256 k2 = _dayBet(day + 1, c.daySeatOfId(day + 1, ids[2]));
        _assertOwnerWord(k2, ids[2]);
        assertEq(_chipsOf(k2), 0, "kind 2 on board zero");
        assertEq(_normal(c.idWord(ids[3])), 2, "kind 4 banks into the ID word");
        uint256 k5 = (uint256(_daySlot(day + 1) + 2) << 64) | 1;
        _assertOwnerWord(k5, ids[4]);
        assertEq(_chipsOf(k5), 0, "kind 5 on board zero");
    }

    function test_vaultCompHonoursTheRecipientsSavedBoard() public {
        _open();
        uint32 id = _register(alice);
        vm.prank(alice);
        c.setPreferredBoard(0, BOARD);
        uint256 code = _code(0, alice, false, 1, 0);
        vm.prank(ContractAddresses.VAULT);
        c.vaultComp(code);
        uint256 betId = (uint256(_daySlot(day) + 2) << 64) | 1;
        _assertOwnerWord(betId, id);
        assertEq(c.betOf(betId).chips, BOARD, "the comp seat plays the saved board");
    }

    // ── 6. Pass ledger by ID ─────────────────────────────────────────────────

    function test_passCreditsAndDeliveriesBankInTheIdWordAlone() public {
        uint32 id = _register(alice);
        vm.prank(ContractAddresses.GAME);
        c.creditPasses(id, 3, 2);
        assertEq(_normal(c.idWord(id)), 3);
        assertEq(_high(c.idWord(id)), 2);
        vm.prank(ContractAddresses.GAME);
        uint24 reserved = c.deliverPasses(id, 2, 0);
        assertEq(reserved, day + 1);
        assertEq(_normal(c.idWord(id)), 4, "one delivered pass seated, one banked by ID");
    }

    function test_boardSavesAndPassMovesPreserveEachOthersLanes() public {
        uint32 id = _register(alice);
        vm.prank(ContractAddresses.GAME);
        c.creditPasses(id, 5, 1);
        vm.prank(alice);
        c.setPreferredBoard(0, BOARD);
        uint256 w = c.idWord(id);
        assertEq(_normal(w), 5, "a board save keeps the normal lane");
        assertEq(_high(w), 1, "a board save keeps the high lane");
        assertEq(_boardOf(w), BOARD);
        vm.prank(ContractAddresses.GAME);
        c.creditPasses(id, 2, 0);
        assertEq(_boardOf(c.idWord(id)), BOARD, "a credit keeps the board");
        vm.prank(alice);
        c.applyCrapsPasses(day + 1, 1, true, BOARD);
        w = c.idWord(id);
        assertEq(_boardOf(w), BOARD, "a debit keeps the board");
        assertTrue(w & INIT != 0);
        assertEq(_high(w), 0);
        assertEq(_normal(w), 7);
        vm.prank(alice);
        c.setPreferredBoard(0, BOARD_B);
        w = c.idWord(id);
        assertEq(_normal(w), 7, "a board change keeps the passes");
        assertEq(_boardOf(w), BOARD_B);
    }

    // ── 7. Protocol bodies ───────────────────────────────────────────────────

    function test_constructorSeedsTwentyNormalPassesAtIdsTwoAndOne() public {
        vm.recordLogs();
        WalletIdTable fresh = WalletIdTable(vm.deployCode("CrapsWalletIds.t.sol:WalletIdTable"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(fresh.idWord(2), 20, "sDGNRS ID word: twenty normal passes");
        assertEq(fresh.idWord(1), 20, "Vault ID word: twenty normal passes");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (_t0(logs[i]) != CrapsBattleStorage.CrapsPassesCredited.selector) continue;
            uint256 who = uint256(logs[i].topics[1]);
            assertTrue(who == 2 || who == 1, "seed credit keyed by protocol ID");
            (bool high, uint256 count) = abi.decode(logs[i].data, (bool, uint256));
            assertFalse(high);
            assertEq(count, 20);
            ++seen;
        }
        assertEq(seen, 2);
    }

    function test_openBonusDaySeatsTheBodiesByIdOnTheirIdWordPasses() public {
        vm.prank(ContractAddresses.VAULT);
        c.setPreferredBoard(0, BOARD);
        assertEq(_boardOf(c.idWord(1)), BOARD, "the Vault's board sits in ID word 1");
        uint256 house = _normal(c.idWord(2));
        uint256 vaultPasses = _normal(c.idWord(1));
        _open();
        assertEq(_normal(c.idWord(2)), house - 1, "sDGNRS spent one ID-word pass");
        assertEq(_normal(c.idWord(1)), vaultPasses - 1, "the Vault spent one ID-word pass");
        uint256 hSeat = c.daySeatOfId(day, 2);
        uint256 vSeat = c.daySeatOfId(day, 1);
        assertEq(hSeat, 1, "sDGNRS takes the first day seat");
        assertEq(vSeat, 2, "the Vault takes the second");
        _assertOwnerWord(_dayBet(day, hSeat), 2);
        _assertOwnerWord(_dayBet(day, vSeat), 1);
        assertEq(c.betOf(_dayBet(day, vSeat)).chips, BOARD, "the Vault plays its saved board");
        assertEq(c.betOf(_dayBet(day, hSeat)).chips, 0, "sDGNRS plays random");
    }

    function test_theUnfundedHouseStillSeatsIdTwo() public {
        c.setIdWord(2, 0);
        c.setIdWord(1, 0);
        flip.setBurnRefused(ContractAddresses.SDGNRS, true);
        flip.setBurnRefused(ContractAddresses.VAULT, true);
        _open();
        uint256 hSeat = c.daySeatOfId(day, 2);
        assertEq(hSeat, 1, "the house sat anyway");
        _assertOwnerWord(_dayBet(day, hSeat), 2);
        assertEq(c.daySeatOfId(day, 1), 0, "the unfunded Vault sat out");
        assertEq(c.dayTicketsOf(day), 1);
    }

    // ── 8. Seat uniqueness by ID ─────────────────────────────────────────────

    function test_aSingleEntryBattleSeatsAWalletIdOnce() public {
        uint64 slot = _customSlot(false);
        vm.prank(alice);
        c.enterBattle(slot, BOARD, 1);
        uint32 id = game.walletIdOf(alice);
        assertTrue(c.bonusSeatedOf(c.keyOfSlot(slot), id), "the seat latch is keyed by ID");
        vm.prank(alice);
        vm.expectRevert(CrapsBattleStorage.AlreadyInBonus.selector);
        c.enterBattle(slot, BOARD, 1);
    }

    function test_aDayTicketBlocksAWindowSeatTheSameDay() public {
        _open();
        vm.prank(alice);
        c.enterBonusDay(0, 1);
        vm.prank(alice);
        vm.expectRevert(CrapsBattleStorage.AlreadyInBonus.selector);
        c.enterBonusBattle(1, 0, 1);
    }

    function test_aDeliveryOntoATakenDayBanksInstead() public {
        vm.prank(alice);
        c.buyFutureCrapsDays(day + 1, 1, false, 0);
        uint32 id = game.walletIdOf(alice);
        uint256 before = _normal(c.idWord(id));
        vm.prank(ContractAddresses.GAME);
        uint24 reserved = c.deliverPasses(id, 1, 0);
        assertEq(reserved, 0, "no second seat on a taken day");
        assertEq(_normal(c.idWord(id)), before + 1, "the pass banked by ID");
        assertEq(c.dayTicketsOf(day + 1), 1);
    }

    // ── 10. _append ──────────────────────────────────────────────────────────

    function _lock(uint256 added) internal {
        vm.warp(dayStart + 1 days);
        game.setRngLocked(true);
        vm.prank(ContractAddresses.GAME);
        JackpotBattle(address(c)).lockJackpotBattle(day + 1, added * 1 ether / 500, 2);
    }

    function _start(uint256 word, uint256[] memory field) internal {
        vm.startPrank(ContractAddresses.GAME);
        JackpotBattle(address(c)).prepareJackpotBattle(2, word);
        JackpotBattle(address(c)).appendJackpotBattle(field, 0, true);
        vm.stopPrank();
    }

    function _entry(uint32 id, uint32 chips) internal pure returns (uint256) {
        return uint256(id) | (CrapsPreferenceLib.compress(chips) << 160) | (uint256(1) << 180);
    }

    function test_appendStoresTheIdWithAnAwardUnitAndSkipsZeroIds() public {
        _open();
        uint32 aId = _register(alice);
        uint32 bId = _register(bob);
        _lock(150_000);
        uint256[] memory field = new uint256[](4);
        field[0] = _entry(aId, BOARD);
        field[1] = uint256(1) << 180;
        field[2] = _entry(bId, 0);
        field[3] = uint256(aId) | (uint256(2) << 180);
        vm.recordLogs();
        _start(uint256(keccak256("append-ids")), field);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32[2] memory want = [aId, bId];
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (_t0(logs[i]) != JackpotBattle.JackpotBattleEntry.selector) continue;
            assertLt(n, 2, "only the two well-formed nonzero entries are appended");
            assertEq(uint256(logs[i].topics[3]), want[n], "JackpotBattleEntry topic3 is the ID");
            uint256 betId = uint256(logs[i].topics[2]);
            uint256 w = c.betWordOf(betId);
            assertEq(uint32(w), want[n], "stored owner is the ID");
            assertEq(w & MID_MASK, 0);
            assertTrue(w & AWARD_UNIT_BIT != 0, "award unit set");
            assertEq(c.betOf(betId).chips, n == 0 ? BOARD : 0, "board carried from the field");
            ++n;
        }
        assertEq(n, 2);
        (CrapsBattleStorage.JackpotRound memory r,,) = JackpotBattle(address(c)).jackpotBattleOf(uint64(_daySlot(day) + 6));
        assertEq(r.drawnCount, 2, "the zero-ID and malformed entries were forfeited");
    }

    // ── 11. Payouts by ID ────────────────────────────────────────────────────

    struct Credit {
        uint32 id;
        uint256 amount;
    }

    /// @dev Every single and batched Coinflip credit in an access stream, in call order.
    function _credits(Vm.AccountAccess[] memory acc) internal pure returns (Credit[] memory out, uint256 n, Credit[] memory batch, uint256 nb) {
        out = new Credit[](256);
        batch = new Credit[](256);
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account != ContractAddresses.COINFLIP || acc[i].kind != VmSafe.AccountAccessKind.Call) continue;
            bytes memory d = acc[i].data;
            bytes4 sel = bytes4(d);
            bytes memory args = new bytes(d.length - 4);
            for (uint256 j; j < args.length; ++j) args[j] = d[j + 4];
            if (sel == MockCoinflip.creditFlip.selector) {
                (uint32 id, uint256 amount) = abi.decode(args, (uint32, uint256));
                out[n++] = Credit(id, amount);
            } else if (sel == MockCoinflip.creditFlipBatch.selector) {
                (uint32[] memory ids, uint256[] memory amounts) = abi.decode(args, (uint32[], uint256[]));
                _requireSameLength(ids.length, amounts.length);
                for (uint256 k; k < ids.length; ++k) batch[nb++] = Credit(ids[k], amounts[k]);
            }
        }
    }

    function _requireSameLength(uint256 a, uint256 b) internal pure {
        require(a == b, "batch arrays differ in length");
    }

    function _hasCredit(Credit[] memory list, uint256 n, uint32 id, uint256 amount) internal pure returns (bool) {
        for (uint256 i; i < n; ++i) if (list[i].id == id && list[i].amount == amount) return true;
        return false;
    }

    function _passValue(uint256 word) internal view returns (uint256) {
        return _normal(word) * c.NORMAL_PASS_VALUE() + _high(word) * c.HIGH_PASS_VALUE();
    }

    /// @dev Grade one settlement's logs and Coinflip calls: every payment names the bet owner's
    ///      ID, the batch IDs are the paying bet owners in order, every single credit is the
    ///      event's liquid figure, and each split's banked value landed in that ID's word.
    function _gradePayouts(Vm.Log[] memory logs, Vm.AccountAccess[] memory acc, uint32[] memory ids, uint256[] memory passBefore)
        internal
        view
        returns (uint256 pots, uint256 hottest, uint256 contested, uint256 riders, uint256 splits)
    {
        (Credit[] memory single, uint256 ns, Credit[] memory batch, uint256 nb) = _credits(acc);
        uint256 k;
        uint256[] memory banked = new uint256[](ids.length);
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = _t0(logs[i]);
            if (t0 == CrapsBattleStorage.CrapsBetSettled.selector) {
                uint256 betId = uint256(logs[i].topics[1]);
                uint32 owner = uint32(uint256(logs[i].topics[2]));
                assertEq(owner, uint32(c.betWordOf(betId)), "settled event names the bet owner ID");
                assertTrue(owner != 0);
                (, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                if (paid == 0) continue;
                assertLt(k, nb, "a paying seat missing from the batch");
                assertEq(batch[k].id, owner, "batch ID is the bet owner");
                assertEq(batch[k].amount, paid, "batch amount is the seat's payment");
                ++k;
            } else if (t0 == CrapsBattleStorage.CrapsBattlePaid.selector) {
                uint32 owner = uint32(uint256(logs[i].topics[3]));
                assertEq(owner, uint32(c.betWordOf(uint256(logs[i].topics[1]))), "pot winner is the bet owner ID");
                uint256 amount = abi.decode(logs[i].data, (uint256));
                assertTrue(_hasCredit(single, ns, owner, amount), "pot credited by ID");
                ++pots;
            } else if (t0 == CrapsBattleStorage.CrapsHottestShooterPaid.selector) {
                uint32 owner = uint32(uint256(logs[i].topics[3]));
                assertEq(owner, uint32(c.betWordOf(uint256(logs[i].topics[1]))), "hottest shooter is the bet owner ID");
                (, uint256 amount) = abi.decode(logs[i].data, (uint16, uint256));
                if (amount != 0) assertTrue(_hasCredit(single, ns, owner, amount), "hottest share credited by ID");
                ++hottest;
            } else if (t0 == CrapsBattleStorage.CrapsHighRollerPaid.selector) {
                uint32 owner = uint32(uint256(logs[i].topics[3]));
                assertEq(owner, uint32(c.betWordOf(uint256(logs[i].topics[1]))), "lane payee is the bet owner ID");
                (uint256 amount, bool rider) = abi.decode(logs[i].data, (uint256, bool));
                if (rider) {
                    ++riders;
                } else {
                    assertTrue(_hasCredit(single, ns, owner, amount), "contested lane credited by ID");
                    ++contested;
                }
            } else if (t0 == CrapsBattleStorage.CrapsProtocolAwardSplit.selector) {
                uint32 owner = uint32(uint256(logs[i].topics[2]));
                (uint256 gross, uint256 liquid) = abi.decode(logs[i].data, (uint256, uint256));
                for (uint256 j; j < ids.length; ++j) if (ids[j] == owner) banked[j] += gross - liquid;
                ++splits;
            }
        }
        assertEq(k, nb, "the batch credited exactly the paying seats");
        for (uint256 j; j < ids.length; ++j) {
            assertEq(_passValue(c.idWord(ids[j])) - passBefore[j], banked[j], "split banked into the winner's ID word");
        }
        for (uint256 i; i < ns; ++i) assertTrue(single[i].id != 0, "no credit to ID 0");
    }

    function _settleScheduled(uint64 slot, uint48 index, uint256 word, uint32[] memory ids)
        internal
        returns (uint256 pots, uint256 hottest, uint256 contested, uint256 riders, uint256 splits)
    {
        uint256[] memory before = new uint256[](ids.length);
        for (uint256 j; j < ids.length; ++j) before[j] = _passValue(c.idWord(ids[j]));
        _setWord(index, word);
        vm.recordLogs();
        vm.startStateDiffRecording();
        c.settleSlot(slot, WHOLE_FIELD);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        return _gradePayouts(logs, acc, ids, before);
    }

    function test_aContestedScheduledFieldPaysEveryLaneById() public {
        _open();
        uint256 h = c.highMultForDay(day);
        address[4] memory ps = [alice, bob, carol, dave];
        uint32[] memory ids = new uint32[](6);
        for (uint256 i; i < 4; ++i) {
            vm.prank(ps[i]);
            c.enterBonusBattle(1, i % 2 == 0 ? BOARD : 0, uint16(i < 2 ? h : 1));
            ids[i] = game.walletIdOf(ps[i]);
        }
        ids[4] = 1;
        ids[5] = 2;
        uint64 slot = uint64(_daySlot(day) + 2);
        vm.warp(dayStart + 6 hours + 3 minutes);
        uint48 index = c.armWindow(slot);
        uint256 snap = vm.snapshotState();
        for (uint256 nonce = 1; nonce <= 24; ++nonce) {
            (uint256 pots, uint256 hottest, uint256 contested,,) =
                _settleScheduled(slot, index, uint256(keccak256(abi.encode("contested-ids", nonce))), ids);
            assertEq(pots, 1, "one pot");
            assertEq(contested, 1, "one contested lane payment");
            if (hottest == 1) return;
            vm.revertToState(snap);
        }
        revert("no word paid a hottest shooter");
    }

    function test_aSoleHighRiderRidesHomeOnItsOwnIdCredit() public {
        _open();
        uint256 h = c.highMultForDay(day);
        uint32[] memory ids = new uint32[](4);
        vm.prank(alice);
        c.enterBonusBattle(1, BOARD, uint16(h));
        vm.prank(bob);
        c.enterBonusBattle(1, 0, 1);
        ids[0] = game.walletIdOf(alice);
        ids[1] = game.walletIdOf(bob);
        ids[2] = 1;
        ids[3] = 2;
        uint64 slot = uint64(_daySlot(day) + 2);
        vm.warp(dayStart + 6 hours + 3 minutes);
        uint48 index = c.armWindow(slot);
        (,, uint256 contested, uint256 riders,) = _settleScheduled(slot, index, uint256(keccak256("sole-rider-ids")), ids);
        assertEq(contested, 0);
        assertEq(riders, 1, "the sole rider's disposition names its ID");
    }

    function test_progressiveAndDiceRunRecordPayTheWinnerIdAndBankItsPasses() public {
        uint32 id = _register(alice);
        c.seedProgressive(10_000_000);
        uint256 bank = 3000;
        uint256 score = c.goalScore(bank * 130);
        uint64 slot = uint64(_daySlot(day) + 2);
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        uint256[] memory before = new uint256[](1);
        before[0] = _passValue(c.idWord(id));
        vm.expectCall(address(coinflip), abi.encodeCall(MockCoinflip.armDiceRunRecord, (id, 1_300_000)), 1);
        vm.recordLogs();
        vm.startStateDiffRecording();
        c.standField(keccak256("progressive-ids"), slot, id, score, bank);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (,,,, uint256 splits) = _gradePayouts(logs, acc, ids, before);
        assertGe(splits, 1, "the progressive banked passes");
        (Credit[] memory single, uint256 ns,,) = _credits(acc);
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (_t0(logs[i]) != CrapsBattleStorage.CrapsProgressivePaid.selector) continue;
            assertEq(uint256(logs[i].topics[3]), id, "progressive winner is the ID");
            (,,,,, uint256 paid,) = abi.decode(logs[i].data, (bool, uint16, uint256, uint256, uint256, uint256, uint256));
            uint256 bankedValue;
            for (uint256 j; j < logs.length; ++j) {
                if (_t0(logs[j]) != CrapsBattleStorage.CrapsProtocolAwardSplit.selector || uint256(logs[j].topics[3]) != 4) continue;
                assertEq(uint256(logs[j].topics[2]), id);
                (uint256 gross, uint256 liquid) = abi.decode(logs[j].data, (uint256, uint256));
                assertEq(gross, paid);
                bankedValue = gross - liquid;
            }
            assertGt(bankedValue, 0);
            assertTrue(_hasCredit(single, ns, id, paid - bankedValue), "progressive liquid credited by ID");
            ++seen;
        }
        assertEq(seen, 1);
        assertGt(coinflip.stakedById(id), 0);
    }

    // ── 12. High-roller reserve ──────────────────────────────────────────────

    function _openNextDay(uint256 word) internal {
        dayStart += 1 days;
        vm.warp(dayStart);
        game.setRngLocked(false);
        day = c.currentDayIndex();
        _setDailyWord(day, word);
        _open();
    }

    function _finishJackpot(uint64 slot) internal {
        for (uint256 i; i < 50; ++i) {
            (,,, bool complete) = JackpotBattle(address(c)).jackpotProgress();
            if (complete) return;
            c.settleSlot(slot, WHOLE_FIELD);
        }
        revert("jackpot settlement stalled");
    }

    function test_highRollerReserveNominatesByIdNeverIdTwoAndCreditsTheId() public {
        // sDGNRS arrives with a banked HIGH pass, so its automatic day seat is high.
        c.setIdWord(2, c.idWord(2) | (uint256(1) << 32));
        _openNextDay(PLAIN_WORD);
        uint64 slot = uint64(_daySlot(day) + 6);
        assertTrue(c.daySeatIsHigh(day, ContractAddresses.SDGNRS), "fixture: the house sits high");
        uint16 h = uint16(c.highMultForDay(day));
        vm.prank(alice);
        c.enterBonusBattle(5, 0, h);
        vm.prank(bob);
        c.enterBonusBattle(5, 0, 1);
        vm.prank(carol);
        c.enterBonusDay(0, h);
        uint32 aId = game.walletIdOf(alice);
        uint32 cId = game.walletIdOf(carol);
        vm.warp(dayStart + 1 days);
        game.setRngLocked(true);
        vm.prank(ContractAddresses.GAME);
        JackpotBattle(address(c)).lockJackpotBattle(day + 1, 50_000 ether / 500, 2);
        uint256 reserve = JackpotBattle(address(c)).highRollerReserve();
        assertGt(reserve, 0);

        uint256[] memory field = new uint256[](2);
        field[0] = _entry(aId, 0);
        field[1] = _entry(game.walletIdOf(bob), 0);
        uint256 snap = vm.snapshotState();
        bool sawWin;
        bool sawMiss;
        for (uint256 nonce = 1; nonce <= 60 && !(sawWin && sawMiss); ++nonce) {
            vm.revertToState(snap);
            uint256 stakeA = coinflip.stakedById(aId);
            uint256 stakeC = coinflip.stakedById(cId);
            vm.startPrank(ContractAddresses.GAME);
            JackpotBattle(address(c)).prepareJackpotBattle(2, uint256(keccak256(abi.encode("reserve-ids", nonce))));
            JackpotBattle(address(c)).appendJackpotBattle(field, 0, true);
            vm.stopPrank();
            vm.recordLogs();
            vm.startStateDiffRecording();
            _finishJackpot(slot);
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            CrapsBattleStorage.HighRollerDraw memory d = JackpotBattle(address(c)).highRollerDrawOf(slot);
            assertTrue(d.resolved);
            assertEq(d.eligible, 2, "alice and carol only: ID 2 never enters");
            assertTrue(d.nominee == aId || d.nominee == cId, "the nominee is a wallet ID");
            assertTrue(d.nominee != 2);
            uint256 drawn;
            for (uint256 i; i < logs.length; ++i) {
                if (_t0(logs[i]) != CrapsBattleStorage.HighRollerReserveDrawn.selector) continue;
                (, uint256 amount,) = abi.decode(logs[i].data, (uint32, uint256, uint256));
                assertEq(uint256(logs[i].topics[2]), d.won ? d.nominee : 0, "winnerId is the ID or zero");
                assertEq(amount, d.won ? reserve : 0);
                ++drawn;
            }
            assertEq(drawn, 1);
            (Credit[] memory single, uint256 ns,,) = _credits(acc);
            if (d.won) {
                assertTrue(_hasCredit(single, ns, d.nominee, reserve), "creditFlip(nomineeId, reserve)");
                uint256 gained = d.nominee == aId ? coinflip.stakedById(aId) - stakeA : coinflip.stakedById(cId) - stakeC;
                assertGe(gained, reserve);
                sawWin = true;
            } else {
                assertFalse(_hasCredit(single, ns, d.nominee, reserve), "a miss credits nothing");
                sawMiss = true;
            }
        }
        assertTrue(sawWin && sawMiss, "both outcomes graded");
    }

    // ── 13. F6: no bet owner is zero ─────────────────────────────────────────

    function _actor(uint256 r) internal view returns (address) {
        uint256 k = r % 6;
        if (k == 0) return alice;
        if (k == 1) return bob;
        if (k == 2) return carol;
        if (k == 3) return dave;
        if (k == 4) return stranger;
        return address(0);
    }

    /// @return ok Whether the action's calls all succeeded. Foundry keeps logs emitted inside a
    ///         frame that later reverted, so a failed action's logs are discarded by the caller.
    function _step(uint256 r, uint64 custom) internal returns (bool ok) {
        address who = _actor(r >> 8);
        uint256 action = r % 7;
        ok = true;
        if (action == 0) {
            uint256 kind = (r >> 16) % 7;
            uint256 arg = kind == 0 ? (r >> 24) % 6 : day + 1 + (r >> 24) % 3;
            uint256 code = _code(kind, who, (r >> 40) & 1 == 1, arg, 1 + (r >> 48) % 3);
            if (kind == 3) code = _code(3, who, true, day, 1 + (r >> 48) % 63);
            if (kind == 5) code |= ((r >> 56) % 6) << 208;
            vm.prank(ContractAddresses.VAULT);
            try c.vaultComp(code) {} catch { ok = false; }
        } else if (action == 1) {
            uint32 id = game.walletIdOf(who);
            if (id == 0) return true;
            vm.prank(ContractAddresses.GAME);
            c.deliverPasses(id, uint32((r >> 16) % 3), uint32((r >> 24) % 2));
        } else if (action == 2 && who != address(0)) {
            uint256 door = (r >> 16) % 4;
            vm.prank(who);
            if (door == 0) {
                try c.enterBonusBattle((r >> 24) % 5, BOARD, 1) {} catch { ok = false; }
            } else if (door == 1) {
                try c.enterBattle(custom, BOARD, 1) {} catch { ok = false; }
            } else if (door == 2) {
                try c.enterBonusDay(0, 1) {} catch { ok = false; }
            } else {
                try c.buyFutureCrapsDays(day + 1 + uint24((r >> 24) % 3), 1, (r >> 32) & 1 == 1, 0) {} catch { ok = false; }
            }
        } else if (action == 3) {
            vm.prank(who);
            try c.setPreferredBoard(0, BOARD_B) {} catch { ok = false; }
        } else if (action == 4) {
            uint32 id = game.walletIdOf(who);
            if (id == 0) return true;
            vm.prank(ContractAddresses.GAME);
            c.creditPasses(id, 1, 0);
            vm.prank(who);
            try c.applyCrapsPasses(day + 1 + uint24((r >> 24) % 3), 1, false, 0) {} catch { ok = false; }
        } else if (action == 5 && who != address(0)) {
            game.registerWallet(who, true);
        }
    }

    function _assertNoZeroOwner(Vm.Log[] memory logs) internal view {
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = _t0(logs[i]);
            if (t0 == CrapsBattleStorage.CrapsSlipPlaced.selector) {
                uint32 owner = uint32(uint256(logs[i].topics[1]));
                assertTrue(owner != 0, "CrapsSlipPlaced with owner 0");
                uint256 bet = abi.decode(logs[i].data, (uint256));
                uint256 betId = (bet >> 32) & ((uint256(1) << 128) - 1);
                assertEq(uint32(c.betWordOf(betId)), owner, "stored owner matches the slip echo");
            } else if (t0 == JackpotBattle.JackpotBattleEntry.selector) {
                uint32 owner = uint32(uint256(logs[i].topics[3]));
                assertTrue(owner != 0, "JackpotBattleEntry with owner 0");
                assertEq(uint32(c.betWordOf(uint256(logs[i].topics[2]))), owner);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 192
    function testFuzz_noStoredBetOrSlipEchoHasOwnerZero(uint256 seed) public {
        _register(alice);
        _register(bob);
        _open();
        uint64 custom = _customSlot(true);
        for (uint256 s; s < 12; ++s) {
            vm.recordLogs();
            bool ok = _step(uint256(keccak256(abi.encode(seed, s))), custom);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            if (ok) _assertNoZeroOwner(logs);
        }

        _lock(150_000);
        uint256[] memory field = new uint256[](6);
        for (uint256 i; i < field.length; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, "field", i)));
            uint32 id = r % 3 == 0 ? 0 : (r % 3 == 1 ? game.walletIdOf(_actor(r >> 8)) : uint32(r >> 32));
            field[i] = uint256(id) | (uint256((r >> 64) % 4 == 0 ? 2 : 1) << 180);
        }
        vm.recordLogs();
        _start(seed | 1, field);
        _assertNoZeroOwner(vm.getRecordedLogs());
    }

    /// @dev A comp that reverts part-way: its partial slip echoes are not state.
    function test_f6CounterexampleWithARevertedMultiDayComp() public {
        testFuzz_noStoredBetOrSlipEchoHasOwnerZero(7685620880822199466244301129381330);
    }

    // ── 14. Replay golden ────────────────────────────────────────────────────

    uint256 internal constant GOLDEN_NONCE = 10;
    uint256 internal constant GOLDEN_PAID = 36_000;
    uint256 internal constant GOLDEN_WON = 35_970;

    function _engineRun(uint256 betId, uint256 owner, CrapsBattleStorage.Window memory w, uint256 word)
        internal
        view
        returns (Craps.SlipResult memory)
    {
        if (owner > type(uint32).max) return legacyEngine.settleBattle(
            betId, owner | (uint256(BOARD) << 160), w.played / 10, w.bankroll, w.goal, w.bound,
            (uint256(1) << 64) | 1, word);
        return CrapsEngine(ContractAddresses.CRAPS_ENGINE).settleBattle(
            betId, owner | (uint256(BOARD) << 32), w.played / 10, w.bankroll, w.goal, w.bound, (uint256(1) << 64) | 1, word
        );
    }

    function test_goldenPaidEntrySaltIsTheWalletId() public {
        // Three filler wallets after the protocol's 1..3, so the golden wallet holds ID 7.
        for (uint256 i; i < 3; ++i) _register(makeAddr(string.concat("filler-", vm.toString(i))));
        uint32 n = _register(alice);
        assertEq(n, 7, "fixture: golden wallet ID");
        uint64 slot = _customSlot(true);
        vm.prank(alice);
        uint256 betId = c.enterBattle(slot, BOARD, 1);
        CrapsBattleStorage.Window memory w = c.windowOf(slot);
        uint256 word = uint256(keccak256(abi.encode("wallet-id-golden", GOLDEN_NONCE)));
        _closeOn(c, slot, 0, word);
        vm.recordLogs();
        c.settleSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 won;
        uint256 paid;
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (_t0(logs[i]) != CrapsBattleStorage.CrapsBetSettled.selector) continue;
            assertEq(uint256(logs[i].topics[1]), betId);
            assertEq(uint256(logs[i].topics[2]), n, "CrapsBetSettled names wallet ID 7");
            (won, paid) = abi.decode(logs[i].data, (uint256, uint256));
            ++seen;
        }
        assertEq(seen, 1);
        Craps.SlipResult memory byId = _engineRun(betId, n, w, word);
        Craps.SlipResult memory byAddress = _engineRun(betId, uint160(alice), w, word);
        assertEq(paid, byId.bankrollIn, "table paid == engine(betId, N | chips << 32)");
        assertEq(won, byId.bankrollOut, "table won == engine(betId, N | chips << 32)");
        assertEq(byAddress.bankrollIn, 32_900, "golden: the same header salted with the address");
        assertTrue(byAddress.bankrollIn != paid, "the address-salted header pays differently");
        assertEq(paid, GOLDEN_PAID, "golden paid");
        assertEq(won, GOLDEN_WON, "golden won");
    }

    // ── 15. Lapsed-day sweep ─────────────────────────────────────────────────

    function test_lapsedDayRefundsLandInEachSeatsIdWord() public {
        uint24 g = day + 1;
        vm.prank(alice);
        c.buyFutureCrapsDays(g, 1, false, 0);
        vm.prank(bob);
        c.buyFutureCrapsDays(g, 1, true, 0);
        uint32 cId = _register(carol);
        vm.prank(ContractAddresses.GAME);
        assertEq(c.deliverPasses(cId, 1, 0), g, "carol's delivery reserved G");
        uint32 aId = game.walletIdOf(alice);
        uint32 bId = game.walletIdOf(bob);
        uint256 a0 = c.idWord(aId);
        uint256 b0 = c.idWord(bId);
        uint256 c0 = c.idWord(cId);

        vm.warp(dayStart + 2 days);
        _setDailyWord(g, uint256(keccak256("gap-day")));
        _setDailyWord(g + 1, PLAIN_WORD);
        _open();
        uint64 gSlot = uint64(_daySlot(g));
        vm.recordLogs();
        for (uint256 i; i < 8 && c.keeperSlot() < gSlot + 8; ++i) _crank(c);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGe(c.keeperSlot(), gSlot + 8, "the keeper crossed G");

        assertEq(_normal(c.idWord(aId)), _normal(a0) + 1, "alice's normal refund by ID");
        assertEq(_high(c.idWord(bId)), _high(b0) + 1, "bob's high refund by ID");
        assertEq(_normal(c.idWord(cId)), _normal(c0) + 1, "carol's refund by ID");
        uint256 refunds;
        uint256 lapsedSeats;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = _t0(logs[i]);
            if (t0 == CrapsBattleStorage.CrapsPassesCredited.selector) {
                uint256 who = uint256(logs[i].topics[1]);
                assertTrue(who == aId || who == bId || who == cId, "refund keyed by a seat's ID");
                (, uint256 count) = abi.decode(logs[i].data, (bool, uint256));
                refunds += count;
            } else if (t0 == CrapsBattleStorage.CrapsDayLapsed.selector && uint256(logs[i].topics[1]) == g) {
                lapsedSeats = abi.decode(logs[i].data, (uint64));
            }
        }
        assertEq(refunds, 3, "one pass per lapsed seat");
        assertEq(lapsedSeats, 3);
    }
}
