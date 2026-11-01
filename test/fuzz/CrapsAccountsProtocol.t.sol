// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";

import {JackpotBattle} from "../../contracts/JackpotBattle.sol";

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title Craps account doors against the deployed protocol
/// @notice The parts of the account rule only the real Game, FLIP and Quests can vouch for: a
///         wallet's account is resolved by the Game, its bets and passes are keyed by its ID, an
///         operator acting for it burns the account key's FLIP, its newcomer rate reads the
///         account's own mint word, and operator approvals are the Game's per-ID approvals.
contract CrapsAccountsProtocolTest is DeployProtocol {
    uint32 internal constant BOARD = 5 << 27;
    uint32 internal constant BOARD_B = 2 | (1 << 3);
    uint256 internal constant ID_SHIFT = CrapsPreferenceLib.ID_SHIFT;
    uint256 internal constant DAY_HIGH_MASK = uint256(0x3F) << 65;
    bytes4 internal constant GAME_E = bytes4(keccak256("E()"));
    bytes4 internal constant BURN_FOR_CRAPS = bytes4(keccak256("burnCoinForCraps_g292454(address,uint32,uint256)"));
    bytes4 internal constant RECORD_CRAPS = bytes4(keccak256("recordCrapsAction_g14623(uint32,uint8)"));
    bytes4 internal constant RESOLVE_ACCOUNT = bytes4(keccak256("resolveAccount_g7029(uint32,address)"));
    bytes32 internal constant COMP_SPENT = keccak256("CrapsCompSpent(uint32,uint256)");

    address internal owner = makeAddr("pacct-owner");
    address internal wallet = makeAddr("pacct-wallet");
    address internal operator = makeAddr("pacct-operator");
    address internal other = makeAddr("pacct-other");
    address internal otherOp = makeAddr("pacct-other-operator");
    address internal ownerOp = makeAddr("pacct-owner-operator");
    address internal stranger = makeAddr("pacct-stranger");

    uint32 internal ownerId;
    uint32 internal walletId;
    uint32 internal otherId;
    uint24 internal day;
    uint64 internal slot;

    function setUp() public {
        _deployProtocol();
        // Genesis is the Craps warm-up day; play from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        _seedLogicalFixtureDay(game.currentDayView_g542950() + 1);
        _primeCurrentDayRng();
        day = crapsBattle.currentDayIndex();
        ownerId = _giveWalletId(owner);
        walletId = _giveWalletId(wallet);
        _giveWalletId(stranger);
        otherId = _giveWalletId(other);
        for (uint256 i; i < 5; ++i) {
            _mint([owner, wallet, operator, stranger, other][i], 10_000_000);
        }
        vm.prank(wallet);
        game.setOperatorApproval(0, operator, true);
        vm.prank(other);
        game.setOperatorApproval(otherId, otherOp, true);
        vm.prank(owner);
        game.setOperatorApproval(0, ownerOp, true);

        uint16 goal = uint16(crapsBattle.MIN_BATTLE_GOAL_MULT());
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        slot = JackpotBattle(address(crapsBattle)).createBattle(600, 10, goal, 0, uint40(block.timestamp + 1 hours), true, 0);
        vm.prank(ContractAddresses.CRAPS);
        coin.creditCrapsComps_g37225(1e12);
    }

    // ── fixtures ─────────────────────────────────────────────────────────────

    function _mint(address who, uint256 amount) internal {
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame_g152734(who, amount);
    }

    function _unallocated() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)))) + 5;
    }



    function _idWord(uint32 id) internal view returns (uint256) {
        return uint256(crapsBattle.extsload_g2807007(keccak256(abi.encode(uint256(id), crapsBattle.passCreditsByIdSlot()))));
    }



    function _call(Vm.AccountAccess[] memory a, address target, bytes4 sel)
        internal
        pure
        returns (uint256 at, bytes memory args)
    {
        for (uint256 i; i < a.length; ++i) {
            if (a[i].account != target || a[i].data.length < 4 || bytes4(a[i].data) != sel) continue;
            if (a[i].kind != VmSafe.AccountAccessKind.Call && a[i].kind != VmSafe.AccountAccessKind.StaticCall) continue;
            bytes memory d = a[i].data;
            args = new bytes(d.length - 4);
            for (uint256 j; j < args.length; ++j) args[j] = d[j + 4];
            return (i, args);
        }
        return (type(uint256).max, args);
    }

    function _slipOwner(Vm.Log[] memory logs) internal view returns (uint32 id, uint256 betId) {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(crapsBattle) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != CrapsBattleStorage.CrapsSlipPlaced.selector) continue;
            id = uint32(uint256(logs[i].topics[1]));
            betId = (abi.decode(logs[i].data, (uint256)) >> 32) & type(uint128).max;
            ++seen;
        }
        assertEq(seen, 1, "one slip");
    }

    /// @dev Set the lifetime level count and last mint level of `who`'s real mint word, keeping
    ///      its wallet ID and flags.
    function _setMintHistory(uint32 who, uint256 lastLevel, uint256 levelCount) internal {
        bytes32 s = GameSlotKeys.mintPacked(who);
        uint256 w = uint256(vm.load(address(game), s));
        vm.store(address(game), s, bytes32((w & ~uint256(type(uint48).max)) | lastLevel | (levelCount << 24)));
        assertEq(uint24(game.mintPackedOfId_g5372(who) >> 24), levelCount, "fixture: mint word slot");
    }

    // ── tests ────────────────────────────────────────────────────────────────

    function test_anOperatorBetsForTheAccountFromTheAccountsFlip() public {
        uint256 otherBefore = coin.balanceOf(other);
        uint256 opBefore = coin.balanceOf(otherOp);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(otherOp);
        uint256 betId = crapsBattle.enterBattle(otherId, slot, BOARD, 1);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 resolveAt, bytes memory resolveArgs) = _call(acc, address(game), RESOLVE_ACCOUNT);
        assertTrue(resolveAt != type(uint256).max, "the Game resolved the account");
        (uint32 rid, address rcaller) = abi.decode(resolveArgs, (uint32, address));
        assertEq(rid, otherId);
        assertEq(rcaller, otherOp);
        (uint256 burnAt, bytes memory burnArgs) = _call(acc, address(coin), BURN_FOR_CRAPS);
        assertTrue(burnAt != type(uint256).max, "FLIP burned");
        (address target, uint32 burnId, uint256 grossAndFlags) = abi.decode(burnArgs, (address, uint32, uint256));
        assertEq(target, other, "the burn comes from the account's key");
        assertEq(burnId, otherId, "the burn carries the account's ID");
        assertEq(otherBefore - coin.balanceOf(other), grossAndFlags >> 8, "the account's FLIP paid the entry");
        assertEq(coin.balanceOf(otherOp), opBefore, "the operator paid nothing");
        (uint256 questAt, bytes memory questArgs) = _call(acc, address(quests), RECORD_CRAPS);
        assertTrue(questAt != type(uint256).max, "Quests heard the action");
        (uint32 questId,) = abi.decode(questArgs, (uint32, uint8));
        assertEq(questId, otherId, "the quest goes to the account");

        (uint32 slipId, uint256 slipBet) = _slipOwner(logs);
        assertEq(slipId, otherId, "CrapsSlipPlaced names the account");
        assertEq(slipBet, betId);
        assertEq(uint32(crapsBattle.betWordOf(betId)), otherId, "the bet is the account's");
        assertEq(crapsBattle.preferredBoardOf(otherId), BOARD, "the board is the account's");
        assertEq(crapsBattle.preferredBoardOf(ownerId), 0);
        assertEq(crapsBattle.preferredBoardOf(0), 0);
    }

    function test_operatorsActForTheAccountTheyAreApprovedFor() public {
        uint256 walletBefore = coin.balanceOf(wallet);
        uint256 operatorBefore = coin.balanceOf(operator);
        vm.prank(operator);
        uint256 betId = crapsBattle.enterBattle(walletId, slot, BOARD, 1);
        assertEq(uint32(crapsBattle.betWordOf(betId)), walletId, "the bet is the wallet's");
        assertLt(coin.balanceOf(wallet), walletBefore, "the wallet's FLIP paid");
        assertEq(coin.balanceOf(operator), operatorBefore, "the operator paid nothing");

        uint256 otherBefore = coin.balanceOf(other);
        vm.prank(otherOp);
        betId = crapsBattle.enterBattle(otherId, slot, BOARD, 1);
        assertEq(uint32(crapsBattle.betWordOf(betId)), otherId, "the other operator's bet is its account's");
        assertLt(coin.balanceOf(other), otherBefore, "an operator spends the account's FLIP");
    }

    function test_unauthorizedAndUnallocatedAccountsRevert() public {
        address[4] memory refused = [stranger, ownerOp, operator, owner];
        uint24 tomorrow = day + 1;
        for (uint256 i; i < refused.length; ++i) {
            address who = refused[i];
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.enterBattle(otherId, slot, BOARD, 1);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.setPreferredBoard(otherId, BOARD);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.buyFutureCrapsDays(otherId, tomorrow, 1, false, BOARD);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            JackpotBattle(address(crapsBattle)).convertNormalToHigh(otherId, 1);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            JackpotBattle(address(crapsBattle)).upgradeReservedDay(otherId, tomorrow);
        }
        uint32 unallocated = _unallocated();
        vm.prank(owner);
        vm.expectRevert(GAME_E);
        crapsBattle.enterBattle(unallocated, slot, BOARD, 1);
        vm.prank(owner);
        vm.expectRevert(GAME_E);
        crapsBattle.applyCrapsPasses(unallocated, tomorrow, 1, false, BOARD);
        vm.prank(owner);
        vm.expectRevert(GAME_E);
        JackpotBattle(address(crapsBattle)).convertNormalToHigh(unallocated, 1);
    }

    /// @dev The newcomer rate reads the ACCOUNT key's real mint word: an account's own history
    ///      prices its entries even though an operator places them.
    function test_theNewcomerRateReadsTheAccountKeysRealMintWord() public {
        // An established account acted for by its operator, beside a newcomer wallet.
        _setMintHistory(otherId, 1, 3);
        _setMintHistory(ownerId, 0, 0);
        uint256 before = coin.balanceOf(other);
        vm.prank(otherOp);
        crapsBattle.enterBattle(otherId, slot, BOARD, 1);
        uint256 base = before - coin.balanceOf(other);
        before = coin.balanceOf(owner);
        vm.prank(owner);
        crapsBattle.enterBattle(0, slot, BOARD, 1);
        assertEq(before - coin.balanceOf(owner), base + base / 20, "the newcomer wallet's own entry pays the premium");

        // Swap: a newcomer account acted for by its operator, beside an established wallet.
        _setMintHistory(otherId, 0, 0);
        _setMintHistory(ownerId, 1, 3);
        before = coin.balanceOf(other);
        vm.prank(otherOp);
        crapsBattle.enterBattle(otherId, slot, BOARD, 1);
        assertEq(before - coin.balanceOf(other), base + base / 20, "the newcomer account's entry pays the premium");
        before = coin.balanceOf(owner);
        vm.prank(owner);
        crapsBattle.enterBattle(0, slot, BOARD, 1);
        assertEq(before - coin.balanceOf(owner), base, "the established wallet's own entry pays the base");
    }

    function test_vaultCompByIdChargesTheLaneForTheAccountKey() public {
        uint256 otherBefore = coin.balanceOf(other);
        uint256 normalsBefore = uint32(_idWord(otherId));
        uint256 code = uint256(otherId) | (uint256(4) << 160) | (uint256(2) << 200);
        vm.recordLogs();
        vm.prank(ContractAddresses.VAULT);
        uint256 charged = crapsBattle.vaultComp(code);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(charged, 0);
        assertEq(uint32(_idWord(otherId)) - normalsBefore, 2, "two normal passes banked on the account's ID");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coin) || logs[i].topics.length != 2 || logs[i].topics[0] != COMP_SPENT) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), otherId, "CrapsCompSpent names the account key");
            assertEq(abi.decode(logs[i].data, (uint256)), charged);
            ++seen;
        }
        assertEq(seen, 1, "one comp burn");

        // A future day comps a seat on the account's ID.
        uint24 tomorrow = day + 1;
        code = uint256(otherId) | (uint256(2) << 160) | (uint256(tomorrow) << 176) | (uint256(1) << 200);
        vm.recordLogs();
        vm.prank(ContractAddresses.VAULT);
        crapsBattle.vaultComp(code);
        (uint32 slipId, uint256 betId) = _slipOwner(vm.getRecordedLogs());
        assertEq(slipId, otherId);
        assertEq(uint32(crapsBattle.betWordOf(betId)), otherId);
        assertEq(coin.balanceOf(other), otherBefore, "a comp spends no wallet's FLIP");

        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(GAME_E);
        crapsBattle.vaultComp(uint256(4) << 160 | (uint256(2) << 200));
        uint32 unallocated = _unallocated();
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(GAME_E);
        crapsBattle.vaultComp(uint256(unallocated) | (uint256(4) << 160) | (uint256(2) << 200));
    }

    function test_passDoorsByIdWriteNoAddressWord() public {
        uint24 tomorrow = day + 1;
        uint256 otherWordBefore = _idWord(otherId);
        vm.startPrank(ContractAddresses.GAME);
        crapsBattle.creditPasses(otherId, uint32(CrapsPriceLib.HIGH_EV), 0);
        crapsBattle.deliverPasses(otherId, 1, 0);
        vm.stopPrank();
        uint256 ownerIdWord = _idWord(ownerId);

        vm.prank(otherOp);
        JackpotBattle(address(crapsBattle)).convertNormalToHigh(otherId, 1);
        vm.prank(otherOp);
        JackpotBattle(address(crapsBattle)).upgradeReservedDay(otherId, tomorrow);
        uint256 w = _idWord(otherId);
        assertEq(uint32(w >> 32), uint32(otherWordBefore >> 32), "the converted high was spent on the upgrade");
        assertEq(uint32(w), uint32(otherWordBefore) + 1, "the day's normal pass banked back to the account");
        assertEq(_idWord(ownerId), ownerIdWord, "the other account's credits did not move");
        uint256 seat = crapsBattle.daySeatNumberOfId(tomorrow, otherId);
        assertGt(seat, 0);
        uint256 betId = ((uint256(tomorrow) * 8) << 64) | seat;
        assertEq(uint32(crapsBattle.betWordOf(betId)), otherId, "upgrading preserves the ticket owner");
        assertEq(crapsBattle.betWordOf(betId) & DAY_HIGH_MASK, DAY_HIGH_MASK, "the account's day is high");
    }

    function test_boardSavesAndAmendmentsFollowTheAccount() public {
        vm.prank(otherOp);
        crapsBattle.setPreferredBoard(otherId, BOARD);
        vm.prank(operator);
        crapsBattle.setPreferredBoard(walletId, BOARD_B);
        assertEq(crapsBattle.preferredBoardOf(otherId), BOARD);
        assertEq(crapsBattle.preferredBoardOf(walletId), BOARD_B);

        vm.prank(otherOp);
        uint256 betId = crapsBattle.enterBattle(otherId, slot, BOARD, 1);
        vm.prank(owner);
        vm.expectRevert(CrapsBattleStorage.NotYourBet.selector);
        crapsBattle.amendSlip(0, betId, BOARD_B);
        vm.prank(owner);
        vm.expectRevert(CrapsBattleStorage.NotYourBet.selector);
        crapsBattle.amendSlip(ownerId, betId, BOARD_B);
        vm.prank(otherOp);
        crapsBattle.amendSlip(otherId, betId, BOARD_B);
        assertEq(crapsBattle.betOf(betId).chips, BOARD_B, "the operator amended the account's slip");
        assertEq(crapsBattle.preferredBoardOf(otherId), BOARD_B);
    }

    function test_anAccountJoinsABonusWindowOnItsOwnFlip() public {
        uint256 word = uint256(keccak256("pacct craps day"));
        RecyclingState.seedDailyWord(address(game), day, word);
        assertEq(crapsBattle.dailyWordAt(day), word, "fixture: the day word lands where the table reads it");
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        uint256 otherBefore = coin.balanceOf(other);
        vm.recordLogs();
        vm.prank(otherOp);
        uint256 betId = crapsBattle.throwCraps(otherId, 1, BOARD, 1);
        (uint32 slipId,) = _slipOwner(vm.getRecordedLogs());
        assertEq(slipId, otherId);
        assertEq(uint32(crapsBattle.betWordOf(betId)), otherId);
        assertLt(coin.balanceOf(other), otherBefore, "the account paid");
        assertTrue(crapsBattle.seatedInId(uint64(uint256(day) * 8 + 2), otherId), "the account holds the window seat");
        assertFalse(crapsBattle.seatedIn(uint64(uint256(day) * 8 + 2), owner), "another wallet does not");
    }
}
