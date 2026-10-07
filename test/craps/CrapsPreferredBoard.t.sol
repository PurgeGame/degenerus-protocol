// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {Vm} from "forge-std/Vm.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";

contract CrapsPreferredBoardTest is CrapsPins {
    CrapsViews private c;
    address private alice = makeAddr("preferred-alice");
    address private bob = makeAddr("preferred-bob");
    uint32 private aliceId;
    uint32 private bobId;
    uint256 private constant INIT = 1 << 84;
    uint32 private constant BOARD = 3 | (3 << 12) | (1 << 15);
    bytes32 private constant EVENT = keccak256("CrapsPreferredBoardSet(uint32,uint32)");

    function setUp() public {
        _installPins();
        c = new CrapsViews();
        flip.setCompLane(type(uint128).max);
        vm.warp(block.timestamp + 1 days);
        _setIndex(0);
        _setDailyWord(c.currentDayIndex(), 40 << 8);
        game.setScore(alice, c.SYBIL_SCORE_FLOOR());
        game.setScore(bob, c.SYBIL_SCORE_FLOOR());
        aliceId = game.registerWallet(alice, true);
        bobId = game.registerWallet(bob, true);
    }

    /// @dev Pass balances and preference share the sole ID-keyed word.
    function _key(address p) private view returns (bytes32) { return _idKey(p); }
    function _idKey(address p) private view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(p)), CrapsPreferenceLib.PASS_SLOT));
    }
    function _word(address p) private view returns (uint256) { return uint256(c.extsload(_idKey(p))); }
    function _raw(address p) private view returns (uint256) { return _word(p); }
    function _save(address p, uint32 b) private { vm.prank(p); c.setPreferredBoard(0, b); }
    function _dayChips(uint24 day, address p) private view returns (uint256) {
        return c.betOf((uint256(day) * 8 << 64) | c.daySeatNumberOf(day, p)).chips;
    }
    function _events() private returns (uint256 n) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) if (logs[i].emitter == address(c) && logs[i].topics[0] == EVENT) ++n;
    }
    function _openToday() private {
        vm.prank(ContractAddresses.GAME);
        c.openBonusDay();
    }

    function test_SlotSentinelOwnershipAndNoop() public {
        assertEq(c.passCreditsByIdSlot(), CrapsPreferenceLib.PASS_SLOT, "raw reader slot drift");
        assertEq(c.preferredBoardOf(game.walletIdOf(alice)), 0);
        vm.recordLogs();
        _save(alice, 0);
        assertEq(_word(alice), INIT);

        assertEq(_events(), 1);
        assertEq(_raw(bob), 0);
        // No RNG read is allowed on an initialized equal board.
        vm.mockCallRevert(ContractAddresses.GAME, abi.encodeWithSignature("rngLocked()"), "unexpected lock read");
        vm.record();
        vm.recordLogs();
        _save(alice, 0);
        (, bytes32[] memory writes) = vm.accesses(address(c));
        assertEq(writes.length, 0);
        assertEq(_events(), 0);
        vm.clearMockedCalls();
        _save(alice, BOARD);
        _save(alice, 0);
        assertEq(_word(alice), INIT, "clearing must retain sentinel");
    }

    function testFuzz_CodecAndReservedBits(uint256 entropy, uint64 balances, uint256 reserved) public {
        uint32 board;
        uint256 compact;
        uint256 left = 7;
        bool dark = entropy & 1 != 0;
        for (uint256 i; i < 10; ++i) {
            uint256 count = (entropy >> (i * 6)) & 3;
            if ((dark && i == 0) || (!dark && i == 9)) count = 0;
            if (count > left) count = left;
            left -= count;
            board |= uint32(count << (i * 3));
            compact |= count << (i * 2);
        }
        // All bits above the preference sentinel are reserved and preserved.
        uint256 base = reserved & ~((uint256(1) << CrapsPreferenceLib.ID_SHIFT) - 1);
        vm.store(address(c), _idKey(alice), bytes32(base | uint256(balances)));
        _save(alice, board);
        assertEq(_word(alice), base | uint256(balances) | INIT | compact << 64);
        assertEq(c.preferredBoardOf(game.walletIdOf(alice)), board);
        (uint256 n, uint256 h) = c.passCreditsOf(alice);
        assertEq(n, uint32(balances)); assertEq(h, balances >> 32);
    }

    function testFuzz_BatchedRawReadsPreserveOrderAndFullWords(bytes32 a, bytes32 b) public {
        bytes32[] memory slots = new bytes32[](4);
        slots[0] = _key(alice); slots[1] = _key(bob); slots[2] = slots[0]; slots[3] = _key(address(0));
        vm.store(address(c), slots[0], a);
        vm.store(address(c), slots[1], b);
        bytes32[] memory values = c.extsload(slots);
        assertEq(values.length, slots.length);
        assertEq(values[0], a); assertEq(values[1], b); assertEq(values[2], a); assertEq(values[3], bytes32(0));
        assertEq(c.extsload(new bytes32[](0)).length, 0);
    }

    function test_InvalidBoardsCannotInitialize() public {
        uint32[4] memory bad = [uint32(1 << 30), uint32(4 << 12), uint32(1 | (1 << 27)), uint32(3 | (3 << 3) | (2 << 6))];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(alice); vm.expectRevert(); c.setPreferredBoard(0, bad[i]);
            assertEq(_word(alice), 0);
        }
    }

    function test_LockBlocksFirstChangeClearButAllowsEqualAndRead() public {
        _save(alice, BOARD);
        game.setRngLocked(true);
        _save(alice, BOARD);
        assertEq(c.preferredBoardOf(game.walletIdOf(alice)), BOARD);
        vm.prank(alice); vm.expectRevert(CrapsBattleStorage.BetLocked.selector); c.setPreferredBoard(0, 0);
        vm.prank(alice); vm.expectRevert(CrapsBattleStorage.BetLocked.selector); c.setPreferredBoard(0, 2);
        vm.prank(bob); vm.expectRevert(CrapsBattleStorage.BetLocked.selector); c.setPreferredBoard(0, 0);
        assertEq(_word(bob), 0);
    }

    function test_CreditsConversionSpendingAndCapsPreservePreference() public {
        _save(alice, BOARD);
        uint256 saved = _word(alice);
        // 21 normals per high credit, plus one spare so a normal reservation still has one to spend.
        vm.prank(ContractAddresses.GAME); c.creditPasses(aliceId, 22, 0);
        vm.prank(alice); c.convertNormalToHigh(0, 1);
        (uint256 n, uint256 h) = c.passCreditsOf(alice); assertEq(n, 1); assertEq(h, 1);
        uint24 day = c.currentDayIndex() + 1;
        game.setRngLocked(true);
        vm.startPrank(alice);
        c.applyCrapsPasses(day, 1, false, BOARD);
        c.applyCrapsPasses(day + 1, 1, true, BOARD);
        vm.stopPrank();
        assertEq(_word(alice), saved);
        c.setPassCredits(alice, type(uint32).max, type(uint32).max);
        vm.prank(ContractAddresses.GAME); c.creditPasses(aliceId, 3, 3);
        assertEq(_word(alice) >> 64, saved >> 64);
        c.setPassCredits(alice, 0, 0);
        assertEq(_word(alice), saved);
    }

    function test_DeliverySnapshotsAndNeverInitializes() public {
        _save(alice, BOARD);
        uint256 saved = _word(alice);
        vm.prank(ContractAddresses.GAME); uint24 day = c.deliverPasses(aliceId, 2, 0);
        assertEq(_dayChips(day, alice), BOARD);
        assertEq(_word(alice), saved | 1);
        _save(alice, 0);
        assertEq(_dayChips(day, alice), BOARD, "old ticket changed");
        vm.prank(ContractAddresses.GAME); c.deliverPasses(bobId, 1, 0);
        assertEq(_word(bob), 0, "award initialized preference");
        vm.prank(ContractAddresses.GAME); c.deliverPasses(bobId, 2, 0);
        assertEq(_word(bob), 2, "bank-only award initialized preference");
    }

    function test_AutoSaveBatchExplicitZeroAndLockedSkip() public {
        uint24 day = c.currentDayIndex() + 1;
        vm.recordLogs();
        vm.prank(alice); c.buyFutureCrapsDays(day, 3, false, BOARD);
        assertEq(_events(), 1, "batch must save once");
        assertEq(c.preferredBoardOf(game.walletIdOf(alice)), BOARD);
        vm.prank(alice); c.buyFutureCrapsDays(day + 3, 1, false, 0);
        assertEq(_dayChips(day + 3, alice), 0);
        assertEq(_word(alice), INIT);
        game.setRngLocked(true);
        vm.prank(alice); c.buyFutureCrapsDays(day + 4, 1, false, BOARD);
        assertEq(_dayChips(day + 4, alice), BOARD);
        assertEq(_word(alice), INIT);
        vm.prank(bob); c.buyFutureCrapsDays(day, 1, false, 0);
        assertEq(_word(bob), 0, "locked first zero initialized");
        game.setRngLocked(false);
        uint256 bet = (uint256(day) * 8 << 64) | c.daySeatNumberOf(day, bob);
        vm.prank(bob); c.amendSlip(bet, BOARD);
        assertEq(c.preferredBoardOf(game.walletIdOf(bob)), BOARD);
        vm.prank(bob); vm.expectRevert(); c.buyFutureCrapsDays(day, 1, false, 0);
        assertEq(c.preferredBoardOf(game.walletIdOf(bob)), BOARD, "failed entry saved");
    }

    function test_CompKindsSnapshotAndUpgradeRetainsBoard() public {
        _save(alice, BOARD); _save(bob, BOARD);
        _openToday();
        // Current period is past zero; current window comp uses a later period.
        vm.prank(ContractAddresses.VAULT); c.vaultComp(uint256(aliceId) | (uint256(5) << 176));
        uint256 slot = uint256(c.currentDayIndex()) * 8 + 6;
        assertEq(c.betOf((slot << 64) | 1).chips, BOARD);
        uint24 day = c.currentDayIndex() + 1;
        vm.prank(ContractAddresses.VAULT); c.vaultComp(uint256(bobId) | (uint256(2) << 160) | (uint256(day) << 176) | (uint256(2) << 200));
        assertEq(_dayChips(day, bob), BOARD); assertEq(_dayChips(day + 1, bob), BOARD);
        uint256 saved = _word(bob);
        vm.prank(ContractAddresses.VAULT); c.vaultComp(uint256(bobId) | (uint256(4) << 160) | (uint256(2) << 200));
        assertEq(_word(bob), saved | 2);
        _save(bob, 0); assertEq(_dayChips(day, bob), BOARD);
    }

    function test_PaidWindowAndCustomSaveExplicitBoard() public {
        _openToday();
        vm.prank(alice); c.enterBonusBattle(5, BOARD, 1);
        assertEq(c.preferredBoardOf(game.walletIdOf(alice)), BOARD);
        uint64 slot = _openFar(c, 300, 5, 1);
        vm.prank(alice); uint256 bet = c.enterBattle(slot, uint32(0), 1);
        assertEq(c.betOf(bet).chips, 0);
        assertEq(_word(alice), INIT);
    }

    function test_WholeDayPaidCompUpgradeAndWindowAhead() public {
        vm.warp(block.timestamp + 1 days - ((block.timestamp - 82_620) % 1 days));
        uint24 day = c.currentDayIndex();
        _setDailyWord(day, 40 << 8);
        _save(alice, BOARD);
        _openToday();
        vm.prank(ContractAddresses.VAULT); c.vaultComp(uint256(aliceId) | (uint256(1) << 160));
        assertEq(_dayChips(day, alice), BOARD);
        _save(alice, 0);
        vm.prank(ContractAddresses.VAULT);
        c.vaultComp(uint256(aliceId) | (uint256(3) << 160) | (uint256(day) << 176) | (uint256(1) << 200));
        assertEq(_dayChips(day, alice), BOARD, "upgrade moved board");
        assertEq(_word(alice), INIT);
        vm.prank(bob); c.enterBonusDay(BOARD, 1);
        assertEq(_dayChips(day, bob), BOARD);
        assertEq(c.preferredBoardOf(game.walletIdOf(bob)), BOARD);
        vm.prank(ContractAddresses.VAULT);
        c.vaultComp(uint256(bobId) | (uint256(5) << 160) | (uint256(day + 1) << 176) | (uint256(2) << 200));
        _save(bob, 0);
        for (uint256 i = 1; i <= 2; ++i) {
            uint256 slot = (uint256(day) + i) * 8 + 1;
            assertEq((c.betWordOf((slot << 64) | 1) >> 32) & 0x3FFFFFFF, BOARD, "window-ahead snapshot changed");
        }
    }

    function test_FirstAutomaticZeroInitializesAndLockedPassesUseExplicitBoard() public {
        uint24 day = c.currentDayIndex() + 1;
        vm.prank(alice); c.buyFutureCrapsDays(day, 1, false, 0);
        assertEq(_word(alice), INIT);
        _save(bob, BOARD);
        vm.prank(ContractAddresses.GAME); c.creditPasses(bobId, 1, 0);
        game.setRngLocked(true);
        vm.prank(bob); c.applyCrapsPasses(day, 1, false, 0);
        assertEq(_dayChips(day, bob), 0);
        assertEq(c.preferredBoardOf(game.walletIdOf(bob)), BOARD);
        uint256 bet = (uint256(day) * 8 << 64) | c.daySeatNumberOf(day, bob);
        vm.prank(bob); c.amendSlip(bet, uint32(2));
        assertEq(_dayChips(day, bob), 2);
        assertEq(c.preferredBoardOf(game.walletIdOf(bob)), BOARD);
    }

    function test_EqualPaidBoardHasNoPreferenceWriteEventOrLockRead() public {
        uint64 slot = _openFar(c, 300, 5, 1);
        _save(alice, BOARD);
        vm.mockCallRevert(ContractAddresses.GAME, abi.encodeWithSignature("rngLocked()"), "unexpected lock read");
        vm.record(); vm.recordLogs();
        vm.prank(alice); c.enterBattle(slot, BOARD, 1);
        (, bytes32[] memory writes) = vm.accesses(address(c));
        for (uint256 i; i < writes.length; ++i) {
            assertNotEq(writes[i], _key(alice));
            assertNotEq(writes[i], _idKey(alice));
        }
        assertEq(_events(), 0);
    }

    function test_GasAutomaticSaveStates() public {
        uint64 slot = _openFar(c, 300, 5, 1);
        uint256 snap = vm.snapshotState();
        uint256[6] memory used;
        string[6] memory labels = ["unchanged", "first zero", "first named", "changed", "cleared", "locked skipped"];
        for (uint256 i; i < 6; ++i) {
            assertTrue(vm.revertToState(snap));
            uint256 stored = i == 1 || i == 2 ? 0 : INIT;
            if (i == 4) stored |= uint256(3) << 64;
            vm.store(address(c), _idKey(alice), bytes32(stored));
            game.setRngLocked(i == 5);
            vm.coolSlot(address(c), _idKey(alice));
            vm.cool(ContractAddresses.GAME);
            uint32 board = i == 2 || i == 3 || i == 5 ? BOARD : 0;
            vm.prank(alice);
            uint256 gasBefore = gasleft();
            c.enterBattle(slot, board, 1);
            used[i] = gasBefore - gasleft();
            emit log_named_uint(labels[i], used[i]);
        }
        assertGt(used[1], used[0] + 19_000);
        assertGt(used[2], used[0] + 19_000);
        assertGt(used[3], used[0]);
        assertGt(used[4], used[0]);
    }

    function test_ProtocolSeatingUsesVaultPreferenceWithoutSpendingPreferenceBits() public {
        c.setPassCredits(ContractAddresses.VAULT, 1, 0);
        c.setPassCredits(ContractAddresses.SDGNRS, 0, 0);
        _save(ContractAddresses.VAULT, BOARD);
        _save(ContractAddresses.SDGNRS, 0);
        _openToday();
        assertFalse(c.daySeatIsHigh(c.currentDayIndex(), ContractAddresses.VAULT));
        assertEq(_dayChips(c.currentDayIndex(), ContractAddresses.VAULT), BOARD);
        assertEq(c.preferredBoardOf(game.walletIdOf(ContractAddresses.VAULT)), BOARD);
        assertEq(_word(ContractAddresses.VAULT) & type(uint64).max, 0);
        assertEq(_word(ContractAddresses.SDGNRS), INIT);
    }
    function test_BoardAndPassesShareOneIdWord() public {
        _save(alice, BOARD);
        vm.prank(ContractAddresses.GAME); c.creditPasses(aliceId, 3, 2);
        assertGt(_word(alice) & CrapsPreferenceLib.MASK, 0);
        assertEq(_word(alice) & type(uint64).max, 3 | (uint256(2) << 32));
        assertTrue(_word(alice) & INIT != 0);

    }

    function test_FreeDoorWithoutGameIdReverts() public {
        game.setStrictWalletIds(true);
        address carol = makeAddr("preferred-carol");
        uint32 count = game.walletCount();
        vm.prank(carol); vm.expectRevert(CrapsBattleStorage.NoWalletId.selector); c.setPreferredBoard(0, BOARD);
        assertEq(game.walletCount(), count, "free door must not allocate");
        assertEq(_raw(carol), 0);
    }

    function test_FreeDoorFillsExistingIdWithoutAllocating() public {
        game.setStrictWalletIds(true);
        address dave = makeAddr("preferred-dave");
        uint32 id = game.registerWallet(dave, true);
        uint32 count = game.walletCount();
        _save(dave, BOARD);
        assertEq(game.walletCount(), count, "fill must not allocate");

        assertEq(c.preferredBoardOf(id), BOARD);
        // A later change updates the same account word without duplicating its ID.
        _save(dave, 0);

        assertEq(c.preferredBoardOf(id), 0);
    }

    function test_PaidDoorAllocatesOnFirstChange() public {
        game.setStrictWalletIds(true);
        address erin = makeAddr("preferred-erin");
        game.setScore(erin, c.SYBIL_SCORE_FLOOR());
        _openToday();
        assertEq(game.walletIdOf(erin), 0);
        vm.prank(erin); c.enterBonusBattle(5, BOARD, 1);
        uint32 id = game.walletIdOf(erin);
        assertGt(id, 0, "paid door allocates");

        assertEq(c.preferredBoardOf(id), BOARD);
    }
}
