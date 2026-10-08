// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title Craps account doors against the deployed protocol
/// @notice The parts of the account rule only the real Game, FLIP and Quests can vouch for: a
///         smurf made by `createSmurf` is resolved by the Game's key derivation, its bets and
///         passes are keyed by the smurf's ID, its FLIP burns come from the owner's balance, its
///         newcomer rate reads the smurf key's own mint word, and operator approvals are the
///         Game's per-ID approvals.
contract CrapsAccountsProtocolTest is DeployProtocol {
    uint32 internal constant BOARD = 3 | (3 << 12) | (1 << 15);
    uint32 internal constant BOARD_B = 2 | (1 << 3);
    uint256 internal constant ID_SHIFT = 85;
    uint256 internal constant DAY_HIGH_MASK = uint256(0x3F) << 65;
    bytes4 internal constant GAME_E = bytes4(keccak256("E()"));
    bytes4 internal constant BURN_FOR_CRAPS = bytes4(keccak256("burnCoinForCraps(address,uint32,uint256)"));
    bytes4 internal constant RECORD_CRAPS = bytes4(keccak256("recordCrapsAction(uint32,uint8)"));
    bytes4 internal constant RESOLVE_ACCOUNT = bytes4(keccak256("resolveAccount(uint32,address)"));
    bytes32 internal constant COMP_SPENT = keccak256("CrapsCompSpent(uint32,uint256)");

    address internal owner = makeAddr("pacct-owner");
    address internal wallet = makeAddr("pacct-wallet");
    address internal operator = makeAddr("pacct-operator");
    address internal smurfOp = makeAddr("pacct-smurf-operator");
    address internal ownerOp = makeAddr("pacct-owner-operator");
    address internal stranger = makeAddr("pacct-stranger");

    uint32 internal ownerId;
    uint32 internal walletId;
    uint32 internal smurfId;
    uint32 internal smurf;
    uint24 internal day;
    uint64 internal slot;

    function setUp() public {
        _deployProtocol();
        // Genesis is the Craps warm-up day; play from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        day = crapsBattle.currentDayIndex();
        ownerId = _giveWalletId(owner);
        walletId = _giveWalletId(wallet);
        _giveWalletId(stranger);
        for (uint256 i; i < 4; ++i) {
            _mint([owner, wallet, operator, stranger][i], 10_000_000);
        }
        (smurfId, smurf) = _createSmurf(owner);
        vm.prank(wallet);
        game.setOperatorApproval(0, operator, true);
        vm.prank(owner);
        game.setOperatorApproval(smurfId, smurfOp, true);
        vm.prank(owner);
        game.setOperatorApproval(0, ownerOp, true);

        uint16 goal = uint16(crapsBattle.MIN_BATTLE_GOAL_MULT());
        vm.prank(ContractAddresses.CREATOR);
        slot = crapsBattle.createBattle(600, 10, goal, 0, uint40(block.timestamp + 1 hours), true, 0);
        vm.prank(ContractAddresses.CRAPS);
        coin.creditCrapsComps(1e12);
    }

    // ── fixtures ─────────────────────────────────────────────────────────────

    function _mint(address who, uint256 amount) internal {
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    function _createSmurf(address o) internal returns (uint32 id, uint32 account) {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(o, o.balance + price);
        vm.prank(o);
        id = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        bool authorized;
        (,, authorized) = game.resolveAccount(id, o);
        account = id;
        assertTrue(authorized, "fixture: the owner may act for its smurf");
    }

    function _unallocated() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)))) + 5;
    }



    function _idWord(uint32 id) internal view returns (uint256) {
        return uint256(crapsBattle.extsload(keccak256(abi.encode(uint256(id), crapsBattle.passCreditsByIdSlot()))));
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
        assertEq(uint24(game.mintPackedOfId(who) >> 24), levelCount, "fixture: mint word slot");
    }

    // ── tests ────────────────────────────────────────────────────────────────

    function test_aSmurfOwnerBetsForTheSmurfFromTheOwnersFlip() public {
        uint256 ownerBefore = coin.balanceOf(owner);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(owner);
        uint256 betId = crapsBattle.enterBattle(smurfId, slot, BOARD, 1);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 resolveAt, bytes memory resolveArgs) = _call(acc, address(game), RESOLVE_ACCOUNT);
        assertTrue(resolveAt != type(uint256).max, "the Game resolved the account");
        (uint32 rid, address rcaller) = abi.decode(resolveArgs, (uint32, address));
        assertEq(rid, smurfId);
        assertEq(rcaller, owner);
        (uint256 burnAt, bytes memory burnArgs) = _call(acc, address(coin), BURN_FOR_CRAPS);
        assertTrue(burnAt != type(uint256).max, "FLIP burned");
        (address target, uint32 burnId, uint256 grossAndFlags) = abi.decode(burnArgs, (address, uint32, uint256));
        assertEq(target, owner, "the burn comes from the owner");
        assertEq(burnId, smurfId, "the burn carries the smurf's ID");
        assertEq(ownerBefore - coin.balanceOf(owner), grossAndFlags >> 8, "the owner's FLIP paid the entry");
        (uint256 questAt, bytes memory questArgs) = _call(acc, address(quests), RECORD_CRAPS);
        assertTrue(questAt != type(uint256).max, "Quests heard the action");
        (uint32 questId,) = abi.decode(questArgs, (uint32, uint8));
        assertEq(questId, smurfId, "the quest goes to the smurf");

        (uint32 slipId, uint256 slipBet) = _slipOwner(logs);
        assertEq(slipId, smurfId, "CrapsSlipPlaced names the smurf");
        assertEq(slipBet, betId);
        assertEq(uint32(crapsBattle.betWordOf(betId)), smurfId, "the bet is the smurf's");
        assertEq(crapsBattle.preferredBoardOf(smurfId), BOARD, "the board is the smurf's");
        assertEq(crapsBattle.preferredBoardOf(ownerId), 0);
    }

    function test_operatorsActForTheAccountTheyAreApprovedFor() public {
        uint256 walletBefore = coin.balanceOf(wallet);
        uint256 operatorBefore = coin.balanceOf(operator);
        vm.prank(operator);
        uint256 betId = crapsBattle.enterBattle(walletId, slot, BOARD, 1);
        assertEq(uint32(crapsBattle.betWordOf(betId)), walletId, "the bet is the wallet's");
        assertLt(coin.balanceOf(wallet), walletBefore, "the wallet's FLIP paid");
        assertEq(coin.balanceOf(operator), operatorBefore, "the operator paid nothing");

        uint256 ownerBefore = coin.balanceOf(owner);
        vm.prank(smurfOp);
        betId = crapsBattle.enterBattle(smurfId, slot, BOARD, 1);
        assertEq(uint32(crapsBattle.betWordOf(betId)), smurfId, "the smurf operator's bet is the smurf's");
        assertLt(coin.balanceOf(owner), ownerBefore, "a smurf's operator spends the owner's FLIP");
    }

    function test_unauthorizedAndUnallocatedAccountsRevert() public {
        address[3] memory refused = [stranger, ownerOp, operator];
        uint24 tomorrow = day + 1;
        for (uint256 i; i < refused.length; ++i) {
            address who = refused[i];
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.enterBattle(smurfId, slot, BOARD, 1);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.setPreferredBoard(smurfId, BOARD);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.buyFutureCrapsDays(smurfId, tomorrow, 1, false, BOARD);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.convertNormalToHigh(smurfId, 1);
            vm.prank(who);
            vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
            crapsBattle.upgradeReservedDay(smurfId, tomorrow);
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
        crapsBattle.convertNormalToHigh(unallocated, 1);
    }

    /// @dev The newcomer rate reads the ACCOUNT key's real mint word: a smurf's own history
    ///      prices the smurf's entries even though the owner pays them.
    function test_theNewcomerRateReadsTheSmurfKeysRealMintWord() public {
        // An established smurf key with a newcomer owner.
        _setMintHistory(smurf, 1, 3);
        _setMintHistory(ownerId, 0, 0);
        uint256 before = coin.balanceOf(owner);
        vm.prank(owner);
        crapsBattle.enterBattle(smurfId, slot, BOARD, 1);
        uint256 base = before - coin.balanceOf(owner);
        before = coin.balanceOf(owner);
        vm.prank(owner);
        crapsBattle.enterBattle(0, slot, BOARD, 1);
        assertEq(before - coin.balanceOf(owner), base + base / 20, "the newcomer owner's own entry pays the premium");

        // Swap: a newcomer smurf key with an established owner.
        _setMintHistory(smurf, 0, 0);
        _setMintHistory(ownerId, 1, 3);
        before = coin.balanceOf(owner);
        vm.prank(owner);
        crapsBattle.enterBattle(smurfId, slot, BOARD, 1);
        assertEq(before - coin.balanceOf(owner), base + base / 20, "the newcomer smurf's entry pays the premium");
        before = coin.balanceOf(owner);
        vm.prank(owner);
        crapsBattle.enterBattle(0, slot, BOARD, 1);
        assertEq(before - coin.balanceOf(owner), base, "the established owner's own entry pays the base");
    }

    function test_vaultCompByIdChargesTheLaneForTheSmurfKey() public {
        uint256 ownerBefore = coin.balanceOf(owner);
        uint256 normalsBefore = uint32(_idWord(smurfId));
        uint256 code = uint256(smurfId) | (uint256(4) << 160) | (uint256(2) << 200);
        vm.recordLogs();
        vm.prank(ContractAddresses.VAULT);
        uint256 charged = crapsBattle.vaultComp(code);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(charged, 0);
        assertEq(uint32(_idWord(smurfId)) - normalsBefore, 2, "two normal passes banked on the smurf's ID");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coin) || logs[i].topics.length != 2 || logs[i].topics[0] != COMP_SPENT) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), smurfId, "CrapsCompSpent names the smurf key");
            assertEq(abi.decode(logs[i].data, (uint256)), charged);
            ++seen;
        }
        assertEq(seen, 1, "one comp burn");

        // A future day comps a seat on the smurf's ID.
        uint24 tomorrow = day + 1;
        code = uint256(smurfId) | (uint256(2) << 160) | (uint256(tomorrow) << 176) | (uint256(1) << 200);
        vm.recordLogs();
        vm.prank(ContractAddresses.VAULT);
        crapsBattle.vaultComp(code);
        (uint32 slipId, uint256 betId) = _slipOwner(vm.getRecordedLogs());
        assertEq(slipId, smurfId);
        assertEq(uint32(crapsBattle.betWordOf(betId)), smurfId);
        assertEq(coin.balanceOf(owner), ownerBefore, "a comp spends no wallet's FLIP");

        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(GAME_E);
        crapsBattle.vaultComp(uint256(4) << 160 | (uint256(2) << 200));
        uint32 unallocated = _unallocated();
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(GAME_E);
        crapsBattle.vaultComp(uint256(unallocated) | (uint256(4) << 160) | (uint256(2) << 200));
    }

    function test_passDoorsBySmurfIdWriteNoAddressWord() public {
        uint24 tomorrow = day + 1;
        uint256 smurfBefore = _idWord(smurfId);
        vm.startPrank(ContractAddresses.GAME);
        crapsBattle.creditPasses(smurfId, uint32(CrapsPriceLib.HIGH_EV), 0);
        crapsBattle.deliverPasses(smurfId, 1, 0);
        vm.stopPrank();
        uint256 ownerIdWord = _idWord(ownerId);

        vm.prank(owner);
        crapsBattle.convertNormalToHigh(smurfId, 1);
        vm.prank(owner);
        crapsBattle.upgradeReservedDay(smurfId, tomorrow);
        uint256 w = _idWord(smurfId);
        assertEq(uint32(w >> 32), uint32(smurfBefore >> 32), "the converted high was spent on the upgrade");
        assertEq(uint32(w), uint32(smurfBefore) + 1, "the day's normal pass banked back to the smurf");
        assertEq(_idWord(ownerId), ownerIdWord, "the owner's credits did not move");
        uint256 seat = crapsBattle.daySeatNumberOfId(tomorrow, smurfId);
        assertGt(seat, 0);
        uint256 betId = ((uint256(tomorrow) * 8) << 64) | seat;
        assertEq(uint32(crapsBattle.betWordOf(betId)), smurfId, "upgrading preserves the ticket owner");
        assertEq(crapsBattle.betWordOf(betId) & DAY_HIGH_MASK, DAY_HIGH_MASK, "the smurf's day is high");
    }

    function test_boardSavesAndAmendmentsFollowTheAccount() public {
        vm.prank(owner);
        crapsBattle.setPreferredBoard(smurfId, BOARD);
        vm.prank(operator);
        crapsBattle.setPreferredBoard(walletId, BOARD_B);
        assertEq(crapsBattle.preferredBoardOf(smurfId), BOARD);
        assertEq(crapsBattle.preferredBoardOf(walletId), BOARD_B);

        vm.prank(owner);
        uint256 betId = crapsBattle.enterBattle(smurfId, slot, BOARD, 1);
        vm.prank(owner);
        vm.expectRevert(CrapsBattleStorage.NotYourBet.selector);
        crapsBattle.amendSlip(0, betId, BOARD_B);
        vm.prank(owner);
        vm.expectRevert(CrapsBattleStorage.NotYourBet.selector);
        crapsBattle.amendSlip(ownerId, betId, BOARD_B);
        vm.prank(smurfOp);
        crapsBattle.amendSlip(smurfId, betId, BOARD_B);
        assertEq(crapsBattle.betOf(betId).chips, BOARD_B, "the smurf's operator amended the smurf's slip");
        assertEq(crapsBattle.preferredBoardOf(smurfId), BOARD_B);
    }

    function test_aSmurfJoinsABonusWindowOnTheOwnersFlip() public {
        uint256 word = uint256(keccak256("pacct craps day"));
        RecyclingState.seedDailyWord(address(game), day, word);
        assertEq(crapsBattle.dailyWordAt(day), word, "fixture: the day word lands where the table reads it");
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        uint256 ownerBefore = coin.balanceOf(owner);
        vm.recordLogs();
        vm.prank(owner);
        uint256 betId = crapsBattle.enterBonusBattle(smurfId, 1, BOARD, 1);
        (uint32 slipId,) = _slipOwner(vm.getRecordedLogs());
        assertEq(slipId, smurfId);
        assertEq(uint32(crapsBattle.betWordOf(betId)), smurfId);
        assertLt(coin.balanceOf(owner), ownerBefore, "the owner paid");
        assertTrue(crapsBattle.seatedInId(uint64(uint256(day) * 8 + 2), smurfId), "the smurf holds the window seat");
        assertFalse(crapsBattle.seatedIn(uint64(uint256(day) * 8 + 2), owner), "the owner does not");
    }
}
