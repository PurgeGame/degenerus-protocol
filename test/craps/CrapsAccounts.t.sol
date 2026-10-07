// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {CrapsPins, MockGame, MockFlip, MockQuests} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The table plus raw readers of the two pass words and one fixture writer.
contract AccountsTable is CrapsViews {


    function idWord(uint32 id) external view returns (uint256) {
        return _passCreditsById[id];
    }



    function daySeatOfId(uint24 day, uint32 id) external view returns (uint256) {
        return _loadDaySeat(uint256(day) * _BONUS_SLOTS_PER_DAY, id) & _MASK32;
    }
}

/// @title Craps account doors
/// @notice Every Craps player door takes the account ID first (0 = the caller). A nonzero ID is
///         resolved by the Game: an unallocated ID reverts `E`, and the caller must be the
///         account's key, a smurf's owner or an operator approved for that ID (`NotApproved`).
///         Game state follows the account (bet owner, passes, board, newcomer rate, events);
///         FLIP burns come from the payee (a smurf's owner, otherwise the key).
contract CrapsAccountsTest is CrapsPins {
    AccountsTable internal c;
    uint24 internal day;
    uint64 internal custom;

    uint32 internal constant BOARD = 3 | (3 << 12) | (1 << 15);
    uint32 internal constant BOARD_B = 2 | (1 << 3);
    uint8 internal constant UPGRADE_MASK = 1 << 1;
    uint256 internal constant ID_SHIFT = 85;
    uint256 internal constant INIT = 1 << 84;
    uint256 internal constant DAY_HIGH_MASK = uint256(0x3F) << 65;

    uint8 internal constant SET_BOARD = 0;
    uint8 internal constant AMEND = 1;
    uint8 internal constant BATTLE = 2;
    uint8 internal constant WINDOW = 3;
    uint8 internal constant DAY = 4;
    uint8 internal constant PASSES = 5;
    uint8 internal constant FUTURE = 6;
    uint8 internal constant UPGRADE = 7;
    uint8 internal constant CONVERT = 8;
    uint8 internal constant RESERVED = 9;

    address internal owner = makeAddr("acct-owner");
    address internal wallet = makeAddr("acct-wallet");
    address internal self = makeAddr("acct-self");
    address internal stranger = makeAddr("acct-stranger");
    address internal operator = makeAddr("acct-operator");
    address internal smurfOp = makeAddr("acct-smurf-operator");
    address internal ownerOp = makeAddr("acct-owner-operator");
    address internal fresh = makeAddr("acct-fresh");
    uint32 internal ownerId;
    uint32 internal walletId;
    uint32 internal selfId;
    uint32 internal smurfId;
    uint32 internal smurfBId;

    function setUp() public {
        _installPins();
        c = new AccountsTable();
        flip.setCompLane(1e30);
        // Genesis is a warm-up day with no windows; play from the start of a later day, period 0.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        if (elapsed != 0) vm.warp(vm.getBlockTimestamp() + (1 days - elapsed));
        day = c.currentDayIndex();
        _setIndex(0);
        _setDailyWord(day, _wordFor(10));
        vm.prank(ContractAddresses.GAME);
        c.openBonusDay();

        ownerId = game.registerWallet(owner, true);
        walletId = game.registerWallet(wallet, true);
        selfId = game.registerWallet(self, true);
        game.registerWallet(stranger, true);
        smurfId = game.registerSmurf(ownerId);
        smurfBId = game.registerSmurf(ownerId);
        game.setOperatorApproval(walletId, operator, true);
        game.setOperatorApproval(smurfBId, smurfOp, true);
        game.setOperatorApproval(ownerId, ownerOp, true);
        // The Game's rule from here on: a paying contact allocates, any other contact needs an ID.
        game.setStrictWalletIds(true);

        uint16 goal = uint16(c.MIN_BATTLE_GOAL_MULT());
        vm.prank(vaultOwner);
        custom = c.createBattle(600, 10, goal, 0, uint40(vm.getBlockTimestamp() + 1 hours), true, 0);
    }

    // ── fixtures ─────────────────────────────────────────────────────────────



    function _newSmurf() internal returns (uint32 id) { return game.registerSmurf(ownerId); }

    function _wordFor(uint256 mult) internal view returns (uint256) {
        for (uint256 i = 1; i < 500; ++i) {
            uint256 w = uint256(keccak256(abi.encode("acct-up", i)));
            if (c.highMultOfWord(w) == mult) return w;
        }
        revert("no word draws that multiple");
    }

    function _unallocated() internal view returns (uint32) {
        return game.walletCount() + 7;
    }

    function _dayBet(uint24 d, uint256 seat) internal pure returns (uint256) {
        return ((uint256(d) * 8) << 64) | seat;
    }



    function _idSlot(uint32 id) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(id), c.passCreditsByIdSlot()));
    }

    function _normal(uint256 word) internal pure returns (uint256) {
        return uint32(word);
    }

    function _high(uint256 word) internal pure returns (uint256) {
        return uint32(word >> 32);
    }

    function _boardOf(uint256 word) internal pure returns (uint32 chips) {
        (chips,) = CrapsPreferenceLib.decode(word);
    }

    function _comp(uint256 kind, uint32 to, bool high, uint256 arg, uint256 count) internal pure returns (uint256) {
        return uint256(to) | (kind << 160) | (high ? (uint256(1) << 168) : 0) | (arg << 176) | (count << 200);
    }

    function _paying(uint8 door) internal pure returns (bool) {
        return door == BATTLE || door == WINDOW || door == DAY || door == FUTURE || door == UPGRADE;
    }

    function _boardDoor(uint8 door) internal pure returns (bool) {
        return door <= FUTURE;
    }

    function _slipDoor(uint8 door) internal pure returns (bool) {
        return door >= BATTLE && door <= FUTURE;
    }

    function _chipsFor(uint8 door) internal pure returns (uint32) {
        return door == AMEND ? BOARD_B : BOARD;
    }

    /// @dev What a door needs on account `id` before it can succeed; returns the slip an
    ///      amendment targets.
    function _prep(uint8 door, uint32 id) internal returns (uint256 arg) {
        if (door == AMEND) {
            vm.prank(ContractAddresses.GAME);
            uint24 d = c.deliverPasses(id, 1, 0);
            arg = _dayBet(d, c.daySeatOfId(d, id));
        } else if (door == PASSES) {
            vm.prank(ContractAddresses.GAME);
            c.creditPasses(id, 1, 0);
        } else if (door == UPGRADE) {
            vm.prank(ContractAddresses.VAULT);
            c.vaultComp(_comp(1, id, false, 0, 0));
        } else if (door == CONVERT) {
            vm.prank(ContractAddresses.GAME);
            c.creditPasses(id, uint32(CrapsPriceLib.HIGH_EV), 0);
        } else if (door == RESERVED) {
            vm.startPrank(ContractAddresses.GAME);
            c.deliverPasses(id, 1, 0);
            c.creditPasses(id, 0, 1);
            vm.stopPrank();
        }
    }

    function _doorData(uint8 door, uint32 id, uint256 arg) internal view returns (bytes memory) {
        if (door == SET_BOARD) return abi.encodeCall(CrapsBattle.setPreferredBoard, (id, BOARD));
        if (door == AMEND) return abi.encodeCall(CrapsBattle.amendSlip, (id, arg, BOARD_B));
        if (door == BATTLE) return abi.encodeCall(CrapsBattle.enterBattle, (id, custom, BOARD, 1));
        if (door == WINDOW) return abi.encodeCall(CrapsBattle.enterBonusBattle, (id, 1, BOARD, 1));
        if (door == DAY) return abi.encodeCall(CrapsBattle.enterBonusDay, (id, BOARD, 1));
        if (door == PASSES) return abi.encodeCall(CrapsBattle.applyCrapsPasses, (id, day + 1, 1, false, BOARD));
        if (door == FUTURE) return abi.encodeCall(CrapsBattle.buyFutureCrapsDays, (id, day + 1, 1, false, BOARD));
        if (door == UPGRADE) return abi.encodeCall(CrapsBattle.upgradeDayWindows, (id, day, UPGRADE_MASK));
        if (door == CONVERT) return abi.encodeCall(CrapsBattle.convertNormalToHigh, (id, 1));
        return abi.encodeCall(CrapsBattle.upgradeReservedDay, (id, day + 1));
    }

    function _call(uint8 door, address caller, uint32 id, uint256 arg) internal returns (bool ok, bytes memory ret) {
        bytes memory data = _doorData(door, id, arg);
        vm.prank(caller);
        (ok, ret) = address(c).call(data);
    }

    function _reverts(uint8 door, address caller, uint32 id, bytes4 err, string memory why) internal {
        (bool ok, bytes memory ret) = _call(door, caller, id, 0);
        assertFalse(ok, why);
        assertEq(ret.length, 4, why);
        assertEq(bytes4(ret), err, why);
    }

    function _betIdOf(Vm.Log memory l) internal pure returns (uint256) {
        return (abi.decode(l.data, (uint256)) >> 32) & type(uint128).max;
    }

    struct Before {
        uint256 callerIdWord;
        uint256 accountWord;
        uint256 payeeBurned;
        uint256 callerBurned;
    }

    /// @dev One authorized call: the account's state moves, the payee burns, the caller's own
    ///      Craps words do not change.
    function _succeeds(uint8 door, address caller, uint32 idArg, uint32 id, address payee, uint256 arg)
        internal
    {
        uint32 callerId = game.walletIdOf(caller);
        Before memory b = Before({
            callerIdWord: callerId == 0 ? 0 : c.idWord(callerId),
            accountWord: c.idWord(id),
            payeeBurned: flip.burned(payee),
            callerBurned: flip.burned(caller)
        });
        if (_paying(door) && door != UPGRADE) {
            vm.expectCall(address(flip), abi.encodeWithSelector(MockFlip.burnCoinForCraps.selector, payee, id));
            vm.expectCall(address(quests), abi.encodeWithSelector(MockQuests.recordCrapsAction.selector, id));
        }
        if (door == UPGRADE) {
            vm.expectCall(address(flip), abi.encodeWithSelector(MockFlip.burnCoin.selector, payee));
        }
        vm.recordLogs();
        (bool ok, bytes memory ret) = _call(door, caller, idArg, arg);
        if (!ok) {
            assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The caller's own words are untouched when it acts for another account.
        if (callerId != id) {
            if (callerId != 0 && callerId != id) assertEq(c.idWord(callerId), b.callerIdWord, "caller's ID word untouched");
        }
        // Burns: the payee pays; the caller and a smurf key never do.
        if (_paying(door)) {
            assertGt(flip.burned(payee), b.payeeBurned, "the payee burned");
            if (door != UPGRADE) assertEq(flip.lastCrapsId(), id, "FLIP got the account ID");
            if (caller != payee) assertEq(flip.burned(caller), b.callerBurned, "the caller burned nothing");
        }
        if (_boardDoor(door)) _assertBoard(door, id, logs);
        if (_slipDoor(door)) _assertSlips(id, logs);
        _assertDoorState(door, id, arg, b, logs);
    }

    function _assertBoard(uint8 door, uint32 id, Vm.Log[] memory logs) internal view {
        uint32 chips = _chipsFor(door);
        uint256 byId = c.idWord(id);
        assertTrue(byId & INIT != 0, "ID word initialized");
        assertEq(_boardOf(byId), chips, "the board landed in the account's ID word");
        assertEq(c.preferredBoardOf(id), chips);
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length < 2 || logs[i].topics[0] != CrapsBattleStorage.CrapsPreferredBoardSet.selector) continue;
            assertEq(uint256(logs[i].topics[1]), id, "CrapsPreferredBoardSet carries the account ID");
            assertEq(abi.decode(logs[i].data, (uint256)), chips);
            ++seen;
        }
        assertEq(seen, 1, "one board save");
    }

    function _assertSlips(uint32 id, Vm.Log[] memory logs) internal view {
        uint256 slips;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length < 2 || logs[i].topics[0] != CrapsBattleStorage.CrapsSlipPlaced.selector) continue;
            assertEq(uint256(logs[i].topics[1]), id, "CrapsSlipPlaced carries the account ID");
            uint256 w = c.betWordOf(_betIdOf(logs[i]));
            assertEq(uint32(w), id, "bet word bits 0..31 are the account ID");
            assertEq(w >> 73, 0, "bet word reserved bits are zero");
            ++slips;
        }
        assertEq(slips, 1, "one slip per door");
    }

    function _countReserved(uint32 id, uint24 d, Vm.Log[] memory logs) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length < 3 || logs[i].topics[0] != CrapsBattleStorage.CrapsDayReserved.selector) continue;
            if (uint256(logs[i].topics[1]) == id && uint256(logs[i].topics[2]) == d) ++n;
        }
    }

    function _assertDoorState(uint8 door, uint32 id, uint256 arg, Before memory b, Vm.Log[] memory logs)
        internal
        view
    {
        uint256 w = c.idWord(id);
        if (door == AMEND) {
            assertEq(c.betOf(arg).chips, BOARD_B, "the account's slip was amended");
            assertEq(uint32(c.betWordOf(arg)), id);
        } else if (door == PASSES || door == FUTURE) {
            assertEq(_countReserved(id, day + 1, logs), 1, "CrapsDayReserved carries the account ID");
            if (door == PASSES) assertEq(_normal(w), _normal(b.accountWord) - 1, "the pass came off the account's ID word");
        } else if (door == UPGRADE) {
            uint256 seat = c.daySeatOfId(day, id);
            assertTrue(c.betWordOf(_dayBet(day, seat)) & (uint256(UPGRADE_MASK) << 65) != 0, "the account's ticket upgraded");
            uint256 seen;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length < 2 || logs[i].topics[0] != CrapsBattleStorage.CrapsDayWindowsUpgraded.selector) continue;
                assertEq(uint256(logs[i].topics[1]), id, "CrapsDayWindowsUpgraded carries the account ID");
                ++seen;
            }
            assertEq(seen, 1);
        } else if (door == CONVERT) {
            assertEq(_normal(w), _normal(b.accountWord) - CrapsPriceLib.HIGH_EV, "normals debited from the account");
            assertEq(_high(w), _high(b.accountWord) + 1, "one high credited to the account");
        } else if (door == RESERVED) {
            assertEq(_high(w), _high(b.accountWord) - 1, "the high pass came off the account");
            assertEq(_normal(w), _normal(b.accountWord) + 1, "the normal pass was banked back to the account");
            uint256 seat = c.daySeatOfId(day + 1, id);
            assertEq(c.betWordOf(_dayBet(day + 1, seat)) & DAY_HIGH_MASK, DAY_HIGH_MASK, "the account's day turned high");
        }
    }

    /// @dev ID truth: every nonzero ID cached in an address word is the Game's ID of that key,
    ///      smurf keys and operator-written keys included.


    // ── 1–3. The ten doors ───────────────────────────────────────────────────

    /// @dev Every row of the account rule for one door.
    function _matrix(uint8 door) internal {
        // A smurf's owner acts for the smurf; the owner pays.
        _succeeds(door, owner, smurfId, smurfId, owner, _prep(door, smurfId));
        // An operator approved for an ordinary wallet acts for it; the wallet pays.
        _succeeds(door, operator, walletId, walletId, wallet, _prep(door, walletId));
        // An operator approved on a smurf's ID acts for it; the owner pays.
        _succeeds(door, smurfOp, smurfBId, smurfBId, owner, _prep(door, smurfBId));
        // id = 0 is the self path.
        _succeeds(door, self, 0, selfId, self, _prep(door, selfId));

        bytes4 notApproved = CrapsBattleStorage.NotApproved.selector;
        _reverts(door, stranger, smurfId, notApproved, "stranger for a smurf");
        _reverts(door, stranger, walletId, notApproved, "stranger for a wallet");
        _reverts(door, ownerOp, smurfId, notApproved, "the owner's operator is not the smurf's");
        _reverts(door, operator, smurfId, notApproved, "a wallet's operator is not the smurf's");
        _reverts(door, smurfOp, ownerId, notApproved, "a smurf's operator is not the owner's");
        _reverts(door, owner, _unallocated(), MockGame.E.selector, "unallocated ID");
        _reverts(door, operator, _unallocated(), MockGame.E.selector, "unallocated ID (operator)");

        // An unregistered caller on the self path: non-paying doors need an ID; paying doors
        // register it (the upgrade then finds no ticket and unwinds the registration).
        if (!_paying(door)) {
            _reverts(door, fresh, 0, CrapsBattleStorage.NoWalletId.selector, "unregistered self on a non-paying door");
            assertEq(game.walletIdOf(fresh), 0, "no ID allocated");
        } else if (door == UPGRADE) {
            _reverts(door, fresh, 0, CrapsBattleStorage.NoSuchBet.selector, "unregistered self has no ticket");
            assertEq(game.walletIdOf(fresh), 0, "the failed upgrade allocated nothing");
        } else {
            (bool ok,) = _call(door, fresh, 0, 0);
            assertTrue(ok, "a paying self door registers the caller");
            assertGt(game.walletIdOf(fresh), 0);
        }
    }

    function test_setPreferredBoardByAccount() public {
        _matrix(SET_BOARD);
    }

    function test_amendSlipByAccount() public {
        _matrix(AMEND);
    }

    function test_enterBattleByAccount() public {
        _matrix(BATTLE);
    }

    function test_enterBonusBattleByAccount() public {
        _matrix(WINDOW);
    }

    function test_enterBonusDayByAccount() public {
        _matrix(DAY);
    }

    function test_applyCrapsPassesByAccount() public {
        _matrix(PASSES);
    }

    function test_buyFutureCrapsDaysByAccount() public {
        _matrix(FUTURE);
    }

    function test_upgradeDayWindowsByAccount() public {
        _matrix(UPGRADE);
    }

    function test_convertNormalToHighByAccount() public {
        _matrix(CONVERT);
    }

    function test_upgradeReservedDayByAccount() public {
        _matrix(RESERVED);
    }

    /// @dev A slip belongs to the account that placed it, not to whoever may act for it.
    function test_amendSlipOwnershipIsTheAccounts() public {
        vm.prank(ContractAddresses.GAME);
        uint24 d = c.deliverPasses(smurfId, 1, 0);
        uint256 betId = _dayBet(d, c.daySeatOfId(d, smurfId));
        assertEq(uint32(c.betWordOf(betId)), smurfId);

        vm.prank(owner);
        vm.expectRevert(CrapsBattleStorage.NotYourBet.selector);
        c.amendSlip(0, betId, BOARD_B);
        vm.prank(owner);
        vm.expectRevert(CrapsBattleStorage.NotYourBet.selector);
        c.amendSlip(ownerId, betId, BOARD_B);

        vm.prank(owner);
        c.amendSlip(smurfId, betId, BOARD_B);
        assertEq(c.betOf(betId).chips, BOARD_B, "the owner amended the smurf's slip through the smurf's ID");
        assertEq(uint32(c.betWordOf(betId)), smurfId, "the owner stays the smurf");
    }

    /// @dev `donate` acts for nobody: it burns the caller's FLIP whoever the caller may act for.
    function test_donateStillBurnsTheCaller() public {
        vm.expectCall(address(flip), abi.encodeWithSelector(MockFlip.burnCoin.selector, operator));
        vm.prank(operator);
        uint256 amount = c.donate(false, 1, 1);
        assertGt(amount, 0);
        assertEq(flip.burned(operator), amount, "the donor burned");
        assertEq(flip.burned(wallet), 0, "the account the donor operates was not charged");
    }

    // ── 4. Newcomer rate follows the account key ─────────────────────────────

    function test_newcomerRateFollowsTheAccountKey() public {
        vm.prank(wallet);
        c.enterBonusBattle(0, 1, BOARD, 1);
        uint256 base = flip.burned(wallet);
        assertGt(base, 0, "fixture: an established wallet's price");

        // A newcomer smurf key with an established owner pays the five percent, from the owner.
        game.setMintHistoryById(smurfId, 0);
        uint256 before = flip.burned(owner);
        vm.prank(owner);
        c.enterBonusBattle(smurfId, 1, BOARD, 1);
        assertEq(flip.burned(owner) - before, base + base / 20, "newcomer smurf pays the premium");

        // An established smurf key with a newcomer owner pays the base price.
        game.setMintHistoryById(smurfBId, uint256(3) << BitPackingLib.LEVEL_COUNT_SHIFT);
        game.setMintHistory(owner, 0);
        before = flip.burned(owner);
        vm.prank(owner);
        c.enterBonusBattle(smurfBId, 1, BOARD, 1);
        assertEq(flip.burned(owner) - before, base, "established smurf pays the base price");

        // The owner's own entry still prices on the owner's key.
        before = flip.burned(owner);
        vm.prank(owner);
        c.enterBonusBattle(0, 1, BOARD, 1);
        assertEq(flip.burned(owner) - before, base + base / 20, "newcomer owner's own entry pays the premium");

        // The deity bit on a key with no level history exempts it.
        uint32 smurfCId = _newSmurf();
        game.setMintHistoryById(smurfCId, uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT);
        before = flip.burned(owner);
        vm.prank(owner);
        c.enterBonusBattle(smurfCId, 1, BOARD, 1);
        assertEq(flip.burned(owner) - before, base, "a deity key is exempt");
    }

    function test_newcomerUpgradeBurnFollowsTheAccountKey() public {
        vm.startPrank(ContractAddresses.VAULT);
        c.vaultComp(_comp(1, walletId, false, 0, 0));
        c.vaultComp(_comp(1, smurfId, false, 0, 0));
        c.vaultComp(_comp(1, smurfBId, false, 0, 0));
        vm.stopPrank();
        vm.prank(wallet);
        uint256 baseDelta = c.upgradeDayWindows(0, day, UPGRADE_MASK);
        assertGt(baseDelta, 0, "fixture: the upgrade costs something");

        game.setMintHistoryById(smurfId, 0);
        uint256 before = flip.burned(owner);
        vm.expectCall(address(flip), abi.encodeCall(MockFlip.burnCoin, (owner, baseDelta + baseDelta / 20)));
        vm.prank(owner);
        uint256 burned = c.upgradeDayWindows(smurfId, day, UPGRADE_MASK);
        assertEq(burned, baseDelta + baseDelta / 20, "a newcomer smurf's upgrade carries the premium");
        assertEq(flip.burned(owner) - before, burned, "burned from the owner");

        // A newcomer owner does not change an established smurf's upgrade price.
        game.setMintHistory(owner, 0);
        vm.prank(owner);
        assertEq(c.upgradeDayWindows(smurfBId, day, UPGRADE_MASK), baseDelta, "established smurf, base upgrade");
    }

    // ── 5. vaultComp by ID ───────────────────────────────────────────────────

    function test_vaultCompSeatsAndBanksOnTheRecipientIdAndChargesTheLaneForItsKey() public {
        uint256[5] memory kinds = [uint256(0), 1, 2, 4, 5];
        for (uint256 i; i < kinds.length; ++i) {
            uint32 id = _newSmurf();
            uint256 code;
            if (kinds[i] == 0) code = _comp(0, id, false, 1, 0);
            else if (kinds[i] == 1) code = _comp(1, id, false, 0, 0);
            else if (kinds[i] == 2) code = _comp(2, id, false, day + 1, 1);
            else if (kinds[i] == 4) code = _comp(4, id, false, 0, 2);
            else code = _comp(5, id, false, day + 1, 1) | (uint256(2) << 208);

            uint256 beforeComp = flip.compFor(owner);
            vm.expectCall(address(flip), abi.encodeWithSelector(MockFlip.burnCoinForCraps.selector, owner, id));
            vm.recordLogs();
            vm.prank(ContractAddresses.VAULT);
            uint256 charged = c.vaultComp(code);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            assertGt(charged, 0);
            assertEq(flip.compFor(owner) - beforeComp, charged, "the comp lane paid for the recipient key");
            assertTrue(flip.lastCrapsFlags() & 0x10 != 0, "the comp flag is set");
            if (kinds[i] == 4) {
                assertEq(_normal(c.idWord(id)), 2, "kind 4 banks into the recipient's ID word");
            } else {
                _assertSlips(id, logs);
            }
        }
        assertEq(flip.burned(owner), 0, "no wallet pays for a comp");
    }



    function test_vaultCompUpgradesAnExistingSeatForTheRecipientKey() public {
        vm.startPrank(ContractAddresses.VAULT);
        c.vaultComp(_comp(1, smurfId, false, 0, 0));
        uint256 seated = flip.compFor(owner);
        vm.expectCall(address(flip), abi.encodeWithSelector(MockFlip.burnCoinForCraps.selector, owner, smurfId));
        uint256 charged = c.vaultComp(_comp(3, smurfId, false, day, UPGRADE_MASK));
        vm.stopPrank();
        assertGt(charged, 0);
        assertEq(flip.compFor(owner) - seated, charged, "the upgrade comp charged the lane for the smurf key");
        uint256 seat = c.daySeatOfId(day, smurfId);
        assertTrue(c.betWordOf(_dayBet(day, seat)) & (uint256(UPGRADE_MASK) << 65) != 0, "the smurf's seat upgraded");
        assertEq(flip.burned(owner), 0);
    }

    function test_vaultCompRevertsForAZeroOrUnallocatedRecipient() public {
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(MockGame.E.selector);
        c.vaultComp(_comp(4, 0, false, 0, 2));
        uint32 unallocated = _unallocated();
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(MockGame.E.selector);
        c.vaultComp(_comp(4, unallocated, false, 0, 2));
    }

    /// @dev Only bits 0..31 name the recipient; the table does not vet bits 32..159 (the vault
    ///      writes them zero).
    function test_vaultCompRecipientIsTheLowThirtyTwoBits() public {
        vm.prank(ContractAddresses.VAULT);
        c.vaultComp(_comp(4, smurfId, false, 0, 2) | (uint256(0xDEAD) << 40));
        assertEq(_normal(c.idWord(smurfId)), 2);
    }

    // ── 6. Pass doors by ID (JackpotBattle) ──────────────────────────────────

    function test_passDoorsBySmurfIdMoveOnlyThatIdAndWriteNoAddressWord() public {
        vm.startPrank(ContractAddresses.GAME);
        c.creditPasses(smurfId, uint32(CrapsPriceLib.HIGH_EV), 0);
        c.creditPasses(ownerId, 50, 3);
        uint24 d = c.deliverPasses(smurfId, 1, 0);
        c.deliverPasses(ownerId, 1, 0);
        vm.stopPrank();
        uint256 ownerWord = c.idWord(ownerId);

        vm.record();
        vm.prank(owner);
        c.convertNormalToHigh(smurfId, 1);
        vm.prank(owner);
        c.upgradeReservedDay(smurfId, d);
        (, bytes32[] memory writes) = vm.accesses(address(c));
        for (uint256 i; i < writes.length; ++i) {
            assertTrue(writes[i] != _idSlot(ownerId), "no write to the owner's ID word");
        }
        uint256 w = c.idWord(smurfId);
        assertEq(_high(w), 0, "converted high spent on the upgrade");
        assertEq(_normal(w), 1, "the day's normal pass banked back to the smurf");
        assertEq(c.idWord(ownerId), ownerWord, "the owner's credits did not move");
        assertEq(c.betWordOf(_dayBet(d, c.daySeatOfId(d, smurfId))) & DAY_HIGH_MASK, DAY_HIGH_MASK, "the smurf's day is high");
        assertEq(c.betWordOf(_dayBet(d, c.daySeatOfId(d, ownerId))) & DAY_HIGH_MASK, 0, "the owner's day is not");

        vm.prank(ContractAddresses.GAME);
        c.creditPasses(smurfId, uint32(CrapsPriceLib.HIGH_EV), 0);
        vm.prank(stranger);
        vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
        c.convertNormalToHigh(smurfId, 1);
        vm.prank(ownerOp);
        vm.expectRevert(CrapsBattleStorage.NotApproved.selector);
        c.upgradeReservedDay(smurfId, d + 1);
    }

    // ── 7. The fast path on the account path ─────────────────────────────────







    // ── 8. Stub/body alignment ───────────────────────────────────────────────

    function test_stubSelectorsMatchTheJackpotBattleBodies() public pure {
        assertEq(CrapsBattle.convertNormalToHigh.selector, JackpotBattle.convertNormalToHigh.selector);
        assertEq(CrapsBattle.convertNormalToHigh.selector, bytes4(keccak256("convertNormalToHigh(uint32,uint32)")));
        assertEq(CrapsBattle.upgradeReservedDay.selector, JackpotBattle.upgradeReservedDay.selector);
        assertEq(CrapsBattle.upgradeReservedDay.selector, bytes4(keccak256("upgradeReservedDay(uint32,uint24)")));
        assertEq(CrapsBattle.createBattle.selector, JackpotBattle.createBattle.selector);
        assertEq(
            CrapsBattle.createBattle.selector,
            bytes4(keccak256("createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)"))
        );
    }

    function _created(Vm.Log[] memory logs) internal view returns (uint64 slot, address creator, uint256 terms) {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 3 || logs[i].topics[0] != CrapsBattleStorage.CrapsBattleCreated.selector) continue;
            assertEq(logs[i].emitter, address(c), "emitted from the table's address");
            slot = uint64(uint256(logs[i].topics[1]));
            creator = address(uint160(uint256(logs[i].topics[2])));
            terms = abi.decode(logs[i].data, (uint256));
            ++seen;
        }
        assertEq(seen, 1, "one CrapsBattleCreated");
    }

    function test_createBattleThroughTheStub() public {
        address creator = makeAddr("acct-creator");
        uint16 goal = uint16(c.MIN_BATTLE_GOAL_MULT());
        uint40 closeAt = uint40(vm.getBlockTimestamp() + 2 hours);

        vm.prank(creator);
        vm.expectRevert(CrapsBattleStorage.NotBattleCreator.selector);
        c.createBattle(600, 10, goal, 0, closeAt, false, 0);

        vm.prank(vaultOwner);
        c.setBattleCreator(creator, true);
        uint64 count = c.customBattleCount();
        vm.recordLogs();
        vm.prank(creator);
        uint64 slot = c.createBattle(600, 10, goal, 0, closeAt, false, 0);
        (uint64 evSlot, address evCreator, uint256 terms) = _created(vm.getRecordedLogs());
        assertEq(slot, uint64((uint256(1) << 40) + count + 1), "the stub returns the new slot");
        assertEq(evSlot, slot);
        assertEq(evCreator, creator, "the creator is the original caller");
        assertEq(c.customBattleCount(), count + 1);
        (,, uint256 stored) = c.customBattleOf(slot);
        assertEq(stored, terms, "the logged terms are the stored terms");

        // The vault's majority holder qualifies without a grant.
        vm.recordLogs();
        vm.prank(vaultOwner);
        uint64 slot2 = c.createBattle(600, 10, goal, 0, closeAt, true, 0);
        (uint64 evSlot2, address evCreator2,) = _created(vm.getRecordedLogs());
        assertEq(slot2, slot + 1);
        assertEq(evSlot2, slot2);
        assertEq(evCreator2, vaultOwner);

        // A revoked creator is refused again.
        vm.prank(vaultOwner);
        c.setBattleCreator(creator, false);
        vm.prank(creator);
        vm.expectRevert(CrapsBattleStorage.NotBattleCreator.selector);
        c.createBattle(600, 10, goal, 0, closeAt, false, 0);
    }

    // ── 9–10. F6 and ID truth over account doors and comps ───────────────────

    function _fuzzComp(uint256 kind, uint32 id) internal view returns (uint256) {
        if (kind == 0) return _comp(0, id, false, 1, 0);
        if (kind == 1) return _comp(1, id, false, 0, 0);
        if (kind == 2) return _comp(2, id, false, day + 1, 1);
        if (kind == 3) return _comp(3, id, false, day, UPGRADE_MASK);
        if (kind == 4) return _comp(4, id, false, 0, 2);
        return _comp(5, id, false, day + 1, 1) | (uint256(2) << 208);
    }

    function _assertNoOwnerZero(Vm.Log[] memory logs) internal view {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(c) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != CrapsBattleStorage.CrapsSlipPlaced.selector) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            assertTrue(id != 0, "CrapsSlipPlaced with owner 0");
            assertEq(uint32(c.betWordOf(_betIdOf(logs[i]))), id, "stored bet owner is the logged owner");
        }
    }

    function testFuzz_accountDoorsAndCompsNeverStoreOwnerZero(
        uint8 doorSeed,
        uint8 actorSeed,
        uint8 idSeed,
        uint32 rawId,
        uint8 kindSeed
    ) public {
        address[7] memory actors = [owner, operator, ownerOp, stranger, smurfOp, self, fresh];
        address caller = actors[actorSeed % 7];
        uint32[7] memory ids =
            [uint32(0), smurfId, walletId, ownerId, smurfBId, game.walletCount() + 1 + (rawId % 1000), rawId];
        uint32 id = ids[idSeed % 7];
        uint8 door = doorSeed % 11;
        uint32 account = door == 10 ? id : (id != 0 ? id : game.walletIdOf(caller));
        uint256 arg;
        // Protocol IDs 1..3 hold the house and vault seats the day opened with; prep only players.
        if (account > 3 && account <= game.walletCount() && door < 10) arg = _prep(door, account);

        vm.recordLogs();
        if (door == 10) {
            vm.prank(ContractAddresses.VAULT);
            (bool ok,) = address(c).call(abi.encodeCall(CrapsBattle.vaultComp, (_fuzzComp(kindSeed % 6, id))));
            ok;
        } else {
            _call(door, caller, id, arg);
        }
        _assertNoOwnerZero(vm.getRecordedLogs());
    }
}
