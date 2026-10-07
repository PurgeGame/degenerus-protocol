// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The deployed table plus two fixture doors, etched over `ContractAddresses.CRAPS`
///      (same storage layout, no immutables): a one-seat scheduled field finalized at a chosen
///      score, and a one-seat high-roller reserve draw on a chosen word.
contract ProtocolCrapsTable is CrapsViews {
    function standField(bytes32 key, uint64 slot, uint32 id, uint256 score, uint256 bankrollFlip) external {
        _battles[key] = 1;
        _storeBet((uint256(slot) << 64) | 1, uint256(id));
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

    function goalScore(uint256 peakFlip) external pure returns (uint256) {
        Settlement memory s;
        s.stop = Craps.SlipStop.Goal;
        s.peak = peakFlip;
        s.won = peakFlip;
        return _compositeOf(s);
    }

    function standReserve(uint64 slot, uint256 word, uint32 id, uint256 reserve) external {
        JackpotRound storage r = _jackpotRounds[slot];
        r.word = word;
        r.paidCount = 1;
        _storeBet((uint256(slot) << 64) | 1, uint256(id) | _BET_HIGH_BIT);
        _setBonusCursor(slot, 1);
        _highRollerReserve = reserve;
        (bool ok, bytes memory ret) = address(this).call(abi.encodeWithSignature("settleHighRollerReserve(uint64)", slot));
        if (!ok) {
            assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        }
    }
}

/// @title Craps wallet IDs against the deployed protocol
/// @notice The parts of the Craps wallet-ID contract that only the real Game, FLIP, Quests and
///         Coinflip can vouch for: first-contact registration through the Game's allocator
///         ahead of the burn, the dice-run trophy following the Game's payee, and the
///         high-roller reserve credited to the nominee's ID on the real Coinflip.
contract CrapsWalletIdsProtocolTest is DeployProtocol {
    uint32 internal constant BOARD = 3 | (3 << 12) | (1 << 15);
    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant TRANSFER = keccak256("Transfer(address,address,uint256)");
    uint256 internal constant MID_MASK = ((uint256(1) << 160) - 1) & ~uint256(type(uint32).max);
    uint256 internal constant DRAW_TAG = uint256(keccak256("CrapsHighReserveDraw"));

    address internal alice = makeAddr("proto-wid-alice");
    address internal bob = makeAddr("proto-wid-bob");
    address internal carol = makeAddr("proto-wid-carol");

    function setUp() public {
        _deployProtocol();
    }

    function _mint(address who, uint256 amount) internal {
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    function _cachedId(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, crapsBattle.passCreditsSlot()));
        return uint32(uint256(crapsBattle.extsload(slot)) >> 85);
    }

    function _call(Vm.AccountAccess[] memory a, address target, bytes4 sel) internal pure returns (uint256 at, bytes memory args) {
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

    function _logIndex(Vm.Log[] memory logs, address emitter, bytes32 sig) internal pure returns (uint256) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length != 0 && logs[i].topics[0] == sig) return i;
        }
        return type(uint256).max;
    }

    /// @dev Grade one first contact: the Game allocated before FLIP burned, FLIP and Quests saw
    ///      the new ID, the bet word owns it, and the address word caches it.
    function _gradeFirstContact(address who, uint256 betId, Vm.AccountAccess[] memory acc, Vm.Log[] memory logs, uint8 flags)
        internal
        view
    {
        uint32 id = game.walletIdOf(who);
        assertTrue(id > 3, "a fresh player wallet ID");
        uint256 reg = _logIndex(logs, address(game), WALLET_REGISTERED);
        uint256 burn = _logIndex(logs, address(coin), TRANSFER);
        assertTrue(reg != type(uint256).max, "WalletRegistered emitted");
        assertEq(uint256(logs[reg].topics[1]), id);
        assertEq(address(uint160(uint256(logs[reg].topics[2]))), who);
        assertTrue(burn != type(uint256).max, "FLIP burned");
        assertLt(reg, burn, "registration precedes the burn");

        (uint256 regCall,) = _call(acc, address(game), bytes4(keccak256("registerWallet(address,bool)")));
        (uint256 burnCall, bytes memory burnArgs) = _call(acc, address(coin), bytes4(keccak256("burnCoinForCraps(address,uint32,uint256)")));
        assertLt(regCall, burnCall, "registerWallet is called before burnCoinForCraps");
        (address burner, uint32 burnId,) = abi.decode(burnArgs, (address, uint32, uint256));
        assertEq(burner, who, "FLIP burns from the address");
        assertEq(burnId, id, "FLIP receives the wallet ID");
        (uint256 questCall, bytes memory questArgs) = _call(acc, address(quests), bytes4(keccak256("recordCrapsAction(uint32,uint8)")));
        assertTrue(questCall != type(uint256).max, "Quests heard the action");
        (uint32 questId, uint8 questFlags) = abi.decode(questArgs, (uint32, uint8));
        assertEq(questId, id, "Quests keyed by the wallet ID");
        assertEq(questFlags, flags);

        uint256 w = crapsBattle.betWordOf(betId);
        assertEq(uint32(w), id, "bet word bits 0..31 are the ID");
        assertEq(w & MID_MASK, 0, "bet word bits 32..159 are zero");
        assertEq(_cachedId(who), id, "the address word caches the ID");
    }

    function test_firstContactOnACustomBattleRegistersBeforeTheBurn() public {
        _mint(alice, 10_000);
        uint16 goal = uint16(crapsBattle.MIN_BATTLE_GOAL_MULT());
        vm.prank(ContractAddresses.CREATOR);
        uint64 slot = crapsBattle.createBattle(600, 10, goal, 0, uint40(block.timestamp + 1 hours), true, 0);
        assertEq(game.walletIdOf(alice), 0, "fixture: fresh wallet");
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(alice);
        uint256 betId = crapsBattle.enterBattle(slot, BOARD, 1);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        _gradeFirstContact(alice, betId, acc, vm.getRecordedLogs(), 0x1);
    }

    function test_firstContactOnFutureDaysRegistersBeforeTheBurn() public {
        _mint(bob, 30_000);
        uint24 day = crapsBattle.currentDayIndex() + 1;
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(bob);
        crapsBattle.buyFutureCrapsDays(day, 1, false, BOARD);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        uint256 betId = ((uint256(day) * 8) << 64) | crapsBattle.daySeatNumberOf(day, bob);
        _gradeFirstContact(bob, betId, acc, vm.getRecordedLogs(), 0x2);
    }

    function test_aBoardSaveNeedsAGameWalletIdAndThenCachesIt() public {
        vm.prank(carol);
        vm.expectRevert(CrapsBattleStorage.NoWalletId.selector);
        crapsBattle.setPreferredBoard(0, BOARD);
        assertEq(game.walletIdOf(carol), 0, "a non-paying door allocates nothing");
        uint32 id = _giveWalletId(carol);
        vm.prank(carol);
        crapsBattle.setPreferredBoard(0, BOARD);
        assertEq(_cachedId(carol), id);
        assertEq(crapsBattle.preferredBoardOf(id), BOARD);
    }

    function _etchTable() internal returns (ProtocolCrapsTable t) {
        vm.etch(ContractAddresses.CRAPS, deployCode("CrapsWalletIdsProtocol.t.sol:ProtocolCrapsTable").code);
        t = ProtocolCrapsTable(ContractAddresses.CRAPS);
    }

    function _standDiceRun(ProtocolCrapsTable t, uint32 id, uint256 multiple) internal returns (uint256 score) {
        uint256 bank = 3000;
        score = multiple * 10_000;
        uint64 slot = uint64(uint256(t.currentDayIndex()) * 8 + 2);
        vm.expectCall(address(game), abi.encodeWithSignature("payRecordSdgnrs(uint32,uint256)", id), 1);
        t.standField(keccak256(abi.encode("dice-run", id)), slot, id, t.goalScore(bank * multiple), bank);
    }

    function test_theDiceRunTrophyGoesToTheWinnersAddressThroughThePayee() public {
        ProtocolCrapsTable t = _etchTable();
        uint32 id = _giveWalletId(alice);
        uint256 stakeBefore = coinflip.coinflipAmount(alice);
        uint256 score = _standDiceRun(t, id, 130);
        assertEq(coinflip.biggestDiceRunEver(), score, "the record moved to the winner's score");
        (address holder, uint128 mark,,) = recordBounty.recordInfo(4);
        assertEq(holder, alice, "the trophy is the winner's address");
        assertEq(recordBounty.ownerOf(4), alice);
        assertEq(uint256(mark), score);
        assertGt(coinflip.coinflipAmount(alice), stakeBefore, "the claim credited the winner's ID");
    }

    /// @dev The trophy follows the Game's payee for the ID, not anything Craps holds: a wallet
    ///      element naming an owner hands the trophy to that owner.
    function test_theDiceRunTrophyFollowsTheGamesPayeeForTheId() public {
        ProtocolCrapsTable t = _etchTable();
        uint32 ownerId = _giveWalletId(carol);
        uint32 id = _giveWalletId(alice);
        bytes32 element = GameSlotKeys.walletElement(id);
        uint256 raw = uint256(vm.load(address(game), element));
        vm.store(address(game), element, bytes32(raw | (uint256(ownerId) << 160)));
        _standDiceRun(t, id, 140);
        assertEq(recordBounty.ownerOf(4), carol, "the trophy went to the payee the Game resolved");
    }

    function test_theHighRollerReserveCreditsTheNomineeIdOnTheRealCoinflip() public {
        ProtocolCrapsTable t = _etchTable();
        uint32 id = _giveWalletId(alice);
        uint64 slot = uint64(uint256(t.currentDayIndex()) * 8 + 6);
        uint256 word = 1;
        while (uint256(keccak256(abi.encode(word, DRAW_TAG, uint256(slot)))) % 10 != 0) ++word;
        uint256 reserve = 4_200;
        uint256 stakeBefore = coinflip.coinflipAmount(alice);
        vm.expectCall(address(coinflip), abi.encodeWithSignature("creditFlip(uint32,uint256)", id, reserve), 1);
        vm.recordLogs();
        t.standReserve(slot, word, id, reserve);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        CrapsBattleStorage.HighRollerDraw memory d = JackpotBattle(address(t)).highRollerDrawOf(slot);
        assertTrue(d.won && d.resolved);
        assertEq(d.nominee, id, "the nominee is the wallet ID");
        uint256 i = _logIndex(logs, address(t), CrapsBattleStorage.HighRollerReserveDrawn.selector);
        assertTrue(i != type(uint256).max);
        assertEq(uint256(logs[i].topics[2]), id, "winnerId is the wallet ID");
        assertEq(coinflip.coinflipAmount(alice) - stakeBefore, reserve, "the reserve landed on the ID's stake");
    }
}

/// @title Craps wallet-ID gas, informational
/// @notice One measured call per scenario, read with `vm.lastCallGas()`; run under
///         `FOUNDRY_ISOLATE=true` so each call is an independent transaction.
contract CrapsWalletIdsGasTest is DeployProtocol {
    uint32 internal constant BOARD = 3 | (3 << 12) | (1 << 15);
    uint24 internal day;
    uint64 internal slot;

    function setUp() public {
        _deployProtocol();
        day = crapsBattle.currentDayIndex();
        uint16 goal = uint16(crapsBattle.MIN_BATTLE_GOAL_MULT());
        vm.prank(ContractAddresses.CREATOR);
        slot = crapsBattle.createBattle(600, 10, goal, 0, uint40(block.timestamp + 1 hours), true, 0);
        vm.prank(ContractAddresses.CRAPS);
        coin.creditCrapsComps(1e12);
    }

    function _who(string memory label) internal returns (address who) {
        who = makeAddr(label);
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, 1_000_000);
    }

    function _gas(string memory label) internal {
        emit log_named_uint(label, vm.lastCallGas().gasTotalUsed);
    }

    function test_gasDoors() public {
        address a = _who("gas-alice");
        vm.prank(a);
        crapsBattle.enterBattle(slot, BOARD, 1);
        _gas("enterBattle first contact (registers, saves board)");
        vm.prank(a);
        crapsBattle.enterBattle(slot, BOARD, 1);
        _gas("enterBattle cached, same board");
        uint32 aId = game.walletIdOf(a);
        vm.prank(ContractAddresses.GAME);
        crapsBattle.creditPasses(aId, 1, 0);
        vm.prank(a);
        crapsBattle.applyCrapsPasses(day + 1, 1, false, BOARD);
        _gas("applyCrapsPasses cached, same board");
    }

    function test_gasConvertNormalToHigh() public {
        address u = _who("gas-convert-uncached");
        uint32 uId = _giveWalletId(u);
        address k = _who("gas-convert-cached");
        uint32 kId = _giveWalletId(k);
        vm.prank(k);
        crapsBattle.setPreferredBoard(0, BOARD);
        vm.startPrank(ContractAddresses.GAME);
        crapsBattle.creditPasses(uId, 21, 0);
        crapsBattle.creditPasses(kId, 21, 0);
        vm.stopPrank();
        vm.prank(u);
        crapsBattle.convertNormalToHigh(0, 1);
        _gas("convertNormalToHigh uncached");
        vm.prank(k);
        crapsBattle.convertNormalToHigh(0, 1);
        _gas("convertNormalToHigh cached");
    }

    function test_gasUpgradeReservedDay() public {
        address u = _who("gas-upgrade-uncached");
        uint32 uId = _giveWalletId(u);
        address k = _who("gas-upgrade-cached");
        uint32 kId = _giveWalletId(k);
        vm.prank(k);
        crapsBattle.setPreferredBoard(0, BOARD);
        vm.startPrank(ContractAddresses.GAME);
        crapsBattle.deliverPasses(uId, 1, 0);
        crapsBattle.deliverPasses(kId, 1, 0);
        crapsBattle.creditPasses(uId, 0, 1);
        crapsBattle.creditPasses(kId, 0, 1);
        vm.stopPrank();
        vm.prank(u);
        crapsBattle.upgradeReservedDay(0, day + 1);
        _gas("upgradeReservedDay uncached");
        vm.prank(k);
        crapsBattle.upgradeReservedDay(0, day + 1);
        _gas("upgradeReservedDay cached");
    }

    function test_gasVaultComp() public {
        address u = _who("gas-comp-uncached");
        _giveWalletId(u);
        address k = _who("gas-comp-cached");
        _giveWalletId(k);
        vm.prank(k);
        crapsBattle.setPreferredBoard(0, BOARD);
        uint256 uCode = uint256(game.walletIdOf(u)) | (uint256(4) << 160) | (uint256(1) << 200);
        uint256 kCode = uint256(game.walletIdOf(k)) | (uint256(4) << 160) | (uint256(1) << 200);
        vm.prank(ContractAddresses.VAULT);
        crapsBattle.vaultComp(uCode);
        _gas("vaultComp kind 4 uncached recipient");
        vm.prank(ContractAddresses.VAULT);
        crapsBattle.vaultComp(kCode);
        _gas("vaultComp kind 4 cached recipient");
    }

    function test_gasSettleBatch() public {
        for (uint256 i; i < 6; ++i) {
            address p = _who(string.concat("gas-settle-", vm.toString(i)));
            vm.prank(p);
            crapsBattle.enterBattle(slot, BOARD, 1);
        }
        vm.warp(block.timestamp + 1 hours);
        uint48 index = crapsBattle.closeBattle(slot);
        RecyclingState.seedWord(address(game), index, bytes32(uint256(keccak256("gas-settle-word"))));
        crapsBattle.settleSlot(slot, 0);
        _gas("settle a six-seat custom field");
    }
}
