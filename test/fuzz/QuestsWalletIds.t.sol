// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PlayerQuestView} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @notice DegenerusQuests by wallet ID: every handler keys by the ID its caller holds, the
///         level-quest completion check resolves the address once through the wallet table, and
///         every handler is revert-free for its authorized caller whatever the ID.
contract QuestsWalletIdsTest is DeployProtocol {
    // DegenerusQuests roots (scripts/layout/golden/DegenerusQuests.json).
    uint256 private constant ACTIVE_ROOT = 0;
    uint256 private constant STATE_ROOT = 1;
    uint256 private constant LEVEL_ROOT = 2;
    uint256 private constant BITMAP_ROOT = 3;
    // PlayerQuestState byte offsets.
    uint256 private constant OFF_LAST_SYNC = 6;
    uint256 private constant OFF_STREAK = 9;
    uint256 private constant OFF_AFKING = 13;
    uint256 private constant OFF_SHIELD = 25;

    uint8 private constant QT_MINT_ETH = 1;
    uint8 private constant QT_FLIP = 2;
    uint8 private constant QT_AFFILIATE = 3;
    uint8 private constant QT_FOIL = 4;
    uint8 private constant QT_DECIMATOR = 5;
    uint8 private constant QT_DEG_ETH = 7;
    uint8 private constant QT_CRAPS_JOIN = 10;

    bytes32 private constant ROLL_TAG = keccak256("affiliate-payout-roll-v1");
    bytes32 private constant E_PROGRESS = keccak256("QuestProgressUpdated(uint32,uint24,uint8,uint8,uint128,uint256)");
    bytes32 private constant E_COMPLETED = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");
    bytes32 private constant E_SHIELD_USED = keccak256("QuestStreakShieldUsed(uint32,uint16,uint16,uint24)");
    bytes32 private constant E_STALL = keccak256("QuestStreakStallForgiven(uint32,uint32,uint24)");
    bytes32 private constant E_SHIELD_GRANTED = keccak256("QuestStreakShieldGranted(uint32,uint16,uint8)");
    bytes32 private constant E_BONUS = keccak256("QuestStreakBonusAwarded(uint32,uint16,uint24,uint24)");
    bytes32 private constant E_RESET = keccak256("QuestStreakReset(uint32,uint24,uint24)");
    bytes32 private constant E_LEVEL = keccak256("LevelQuestCompleted(uint32,uint24,uint8,uint256)");
    bytes32 private constant E_GROWTH = keccak256("GrowthBetQuestCompleted(uint32,uint24,uint256)");

    uint256 private price;

    function setUp() public {
        _deployProtocol();
        (,,,, price) = game.purchaseInfo();
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _stateSlot(uint32 id) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), STATE_ROOT));
    }

    function _levelSlot(uint32 id) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), LEVEL_ROOT));
    }

    function _qs(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(quests), _stateSlot(id)));
    }

    function _lq(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(quests), _levelSlot(id)));
    }

    function _field(uint32 id, uint256 offset, uint256 width) private view returns (uint256) {
        return (_qs(id) >> (offset * 8)) & ((uint256(1) << width) - 1);
    }

    function _active() private view returns (uint256) {
        return uint256(vm.load(address(quests), bytes32(ACTIVE_ROOT)));
    }

    function _questDay() private view returns (uint24) {
        return uint24(_active());
    }

    /// @dev Switch the level quest type and bump its version, as a roll does.
    function _setLevelQuest(uint8 qt) private {
        uint256 w = _active();
        uint256 version = uint8(w >> 136) + 1;
        w = (w & ~(uint256(0xffff) << 128)) | (uint256(qt) << 128) | ((version & 0xff) << 136);
        vm.store(address(quests), bytes32(ACTIVE_ROOT), bytes32(w));
    }

    /// @dev Publish `day` with slot 0 MINT_ETH and slot 1 `slot1Type`, and mark it rolled.
    function _setDaily(uint24 day, uint8 slot1Type) private {
        uint256 w = _active();
        uint256 rec0 = uint256(day) | (uint256(QT_MINT_ETH) << 24);
        uint256 rec1 = uint256(day) | (uint256(slot1Type) << 24);
        w = (w & ~uint256(type(uint128).max)) | rec0 | (rec1 << 64);
        vm.store(address(quests), bytes32(ACTIVE_ROOT), bytes32(w));
        bytes32 b = keccak256(abi.encode(uint256(day >> 8), BITMAP_ROOT));
        vm.store(address(quests), b, bytes32(uint256(vm.load(address(quests), b)) | (uint256(1) << uint8(day))));
    }

    /// @dev A mint word passing the level-quest gates at the current level (400 units at
    ///      level + 1), with `streak` and optionally the deity bit; the ID bits are kept.
    function _eligible(address key, bool deity, uint24 streak) private {
        bytes32 slot = GameSlotKeys.mintPacked(key);
        uint256 w = uint256(vm.load(address(game), slot)) & (uint256(type(uint32).max) << BitPackingLib.WALLET_ID_SHIFT);
        w |= (uint256(game.level() + 1) << BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT)
            | (uint256(400) << BitPackingLib.LEVEL_UNITS_SHIFT)
            | (uint256(streak) << BitPackingLib.LEVEL_STREAK_SHIFT);
        if (deity) w |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
        vm.store(address(game), slot, bytes32(w));
    }

    function _nextId() private view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.WALLETS))));
    }

    /// @dev Call Quests as `caller`, bubbling any revert.
    function _as(address caller, bytes memory data) private returns (bytes memory ret) {
        vm.prank(caller);
        bool ok;
        (ok, ret) = address(quests).call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    function _primary(uint32 id) private {
        _as(address(game), abi.encodeCall(quests.handlePurchase, (id, price, 0, 0, price, price)));
    }

    function _buy(address buyer) private returns (uint32) {
        vm.deal(buyer, buyer.balance + price);
        vm.prank(buyer);
        game.purchase{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        return game.walletIdOf(buyer);
    }

    function _senderFor(bytes32 code, uint8 cls, uint32 from) private view returns (uint32 id) {
        for (id = from; ; ++id) {
            uint24 day = GameTimeLib.currentDayIndexAt(vm.getBlockTimestamp());
            uint256 r = uint256(keccak256(abi.encodePacked(ROLL_TAG, day, id, code))) % 20;
            if ((r < 15 ? 0 : (r < 19 ? 1 : 2)) == cls) return id;
        }
    }

    function _match(Vm.AccountAccess memory a, address from, address to, bytes4 sel) private pure returns (bool) {
        if (a.reverted) return false;
        if (a.kind != VmSafe.AccountAccessKind.Call && a.kind != VmSafe.AccountAccessKind.StaticCall) return false;
        if (a.account != to || a.accessor != from) return false;
        return a.data.length >= 4 && bytes4(a.data) == sel;
    }

    function _args(bytes memory data) private pure returns (bytes memory out) {
        out = new bytes(data.length - 4);
        for (uint256 i; i < out.length; ++i) out[i] = data[i + 4];
    }

    function _calls(Vm.AccountAccess[] memory acc, address from, address to, bytes4 sel)
        private
        pure
        returns (bytes[] memory found)
    {
        uint256 n;
        for (uint256 i; i < acc.length; ++i) if (_match(acc[i], from, to, sel)) ++n;
        found = new bytes[](n);
        n = 0;
        for (uint256 i; i < acc.length; ++i) if (_match(acc[i], from, to, sel)) found[n++] = _args(acc[i].data);
    }

    function _firstIndex(Vm.AccountAccess[] memory acc, address from, address to, bytes4 sel)
        private
        pure
        returns (uint256)
    {
        for (uint256 i; i < acc.length; ++i) if (_match(acc[i], from, to, sel)) return i;
        return type(uint256).max;
    }

    /// @dev Every Quests write landed in wallet `id`'s two ID-keyed records.
    function _assertWritesUnder(bytes32[] memory writes, uint32 id) private pure {
        assertGt(writes.length, 0, "the handler wrote state");
        for (uint256 i; i < writes.length; ++i) {
            assertTrue(writes[i] == _stateSlot(id) || writes[i] == _levelSlot(id), "write outside the wallet's records");
        }
    }

    /// @dev The first argument of the only matching call.
    function _onlyId(Vm.AccountAccess[] memory acc, address from, bytes4 sel) private view returns (uint32 id) {
        bytes[] memory c = _calls(acc, from, address(quests), sel);
        assertEq(c.length, 1, "one handler call");
        id = uint32(uint256(bytes32(c[0])));
    }

    /// @dev Quests credited `amount` to `id`, and every Quests credit in the window went to `id`.
    function _assertQuestCredit(Vm.AccountAccess[] memory acc, uint32 id, uint256 amount) private view {
        bytes[] memory c = _calls(acc, address(quests), address(coinflip), coinflip.creditFlip.selector);
        bool found;
        for (uint256 i; i < c.length; ++i) {
            (uint32 cid, uint256 amt) = abi.decode(c[i], (uint32, uint256));
            assertEq(cid, id, "credit by ID");
            if (amt == amount) found = true;
        }
        assertTrue(found, "expected credit");
    }

    function _bytes32Of(bytes memory b) private pure returns (bytes32 v) {
        assembly ("memory-safe") {
            v := mload(add(b, 32))
        }
    }

    // =====================================================================
    // 18. Handlers by ID from every caller
    // =====================================================================

    function test_HandleFlipFromSelfDepositKeysDepositorId() public {
        address p = makeAddr("flipSelf");
        vm.prank(address(game));
        coin.mintForGame(p, 10_000);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(p);
        coinflip.depositCoinflip(0, 1_000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        uint32 id = game.walletIdOf(p);
        assertGt(id, 0, "the deposit registers the depositor");
        assertEq(_onlyId(acc, address(coinflip), quests.handleFlip.selector), id);
        _assertWritesUnder(writes, id);
        assertEq(uint256(vm.load(address(quests), keccak256(abi.encode(p, STATE_ROOT)))), 0, "nothing keyed by address");
    }

    function test_HandleFlipFromGiftDepositKeysFunderId() public {
        address r = makeAddr("giftRecipient");
        address g = makeAddr("giftFunder");
        uint32 rid = _giveWalletId(r);
        vm.prank(address(game));
        coin.mintForGame(g, 10_000);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(g);
        coinflip.depositCoinflip(rid, 1_000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        uint32 gid = game.walletIdOf(g);
        assertGt(gid, 0, "the paying funder registers");
        assertEq(_onlyId(acc, address(coinflip), quests.handleFlip.selector), gid, "quest goes to the funder");
        _assertWritesUnder(writes, gid);
        assertEq(_qs(rid), 0, "the recipient's quest state is untouched");
    }

    function test_HandleDecimatorFromFlipBurnKeysRegisteredId() public {
        address p = makeAddr("decBurner");
        vm.prank(address(game));
        coin.mintForGame(p, 10_000);
        vm.mockCall(address(game), abi.encodeWithSelector(game.decWindow.selector), abi.encode(true));
        vm.mockCall(address(game), abi.encodeWithSelector(game.recordDecBurn.selector), abi.encode(uint64(1)));
        _setLevelQuest(QT_DECIMATOR);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(p);
        coin.decimatorBurn(0, 2_000, 0);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        uint32 id = game.walletIdOf(p);
        assertGt(id, 0, "the burn registers the burner");
        assertEq(_onlyId(acc, address(coin), quests.handleDecimator.selector), id);
        assertLt(
            _firstIndex(acc, address(coin), address(game), game.registerWallet.selector),
            _firstIndex(acc, address(coin), address(quests), quests.handleDecimator.selector),
            "registration precedes the quest"
        );
        _assertWritesUnder(writes, id);
    }

    function test_HandleDecimatorFromSdgnrsAutoBurnUsesProtocolId() public {
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(coinflip.previewSalvageFlipBacking.selector, ContractAddresses.SDGNRS),
            abi.encode(uint256(5_000))
        );
        vm.mockCall(address(coinflip), abi.encodeWithSelector(coinflip.consumeFlipForSalvage.selector), abi.encode(uint256(5_000)));
        vm.mockCall(address(game), abi.encodeWithSelector(game.recordDecBurn.selector), abi.encode(uint64(1)));
        // sDGNRS's daily state already synced at deploy; the level-quest leg writes its record.
        _setLevelQuest(QT_DECIMATOR);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(address(game));
        uint256 spent = coin.autoDecimatorBurn(1, 5_000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        assertEq(spent, 5_000);
        assertEq(_onlyId(acc, address(coin), quests.handleDecimator.selector), 2, "sDGNRS burns as ID 2");
        _assertWritesUnder(writes, 2);
    }

    function test_HandleFoilPurchaseFromFoilBuyKeysBuyerId() public {
        address b = makeAddr("foilBuyer");
        vm.deal(b, 10 ether);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(b);
        game.purchase{value: 1 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        uint32 id = game.walletIdOf(b);
        assertGt(id, 0);
        assertEq(_onlyId(acc, address(game), quests.handleFoilPurchase.selector), id);
        _assertWritesUnder(writes, id);
    }

    function test_HandleAffiliateFromAffiliateKeysOwnerAndUplineIds() public {
        address up = makeAddr("qaUp");
        address o = makeAddr("qaOwner");
        address b = makeAddr("qaBuyer");
        uint32 upid = _giveWalletId(up);
        vm.prank(address(game));
        affiliate.payAffiliate(0, bytes32(0), up, 0, 1, true, 0); // locks the upline to VAULT
        vm.prank(o);
        affiliate.referPlayer(bytes32(uint256(uint160(up))));
        vm.prank(o);
        affiliate.createAffiliateCode(bytes32("QA_CODE"), 0);
        vm.prank(b);
        affiliate.referPlayer(bytes32("QA_CODE"));
        uint32[2] memory expected = [game.walletIdOf(o), upid];
        for (uint8 cls; cls < 2; ++cls) {
            uint32 sid = _senderFor(bytes32("QA_CODE"), cls, 40_000_000);
            vm.record();
            vm.startStateDiffRecording();
            vm.prank(address(game));
            affiliate.payAffiliate(4000, bytes32(0), b, sid, 1, true, 0);
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            (, bytes32[] memory writes) = vm.accesses(address(quests));
            assertEq(_onlyId(acc, address(affiliate), quests.handleAffiliate.selector), expected[cls]);
            _assertWritesUnder(writes, expected[cls]);
        }
    }

    function test_HandleDegeneretteFromBetKeysFunderId() public {
        address p = makeAddr("degSelf");
        vm.deal(p, 1 ether);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(p);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, 0.01 ether, 1, 9);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        uint32 pid = game.walletIdOf(p);
        assertGt(pid, 0);
        assertEq(_onlyId(acc, address(game), quests.handleDegenerette.selector), pid);
        _assertWritesUnder(writes, pid);

        address r = makeAddr("degRecipient");
        address g = makeAddr("degFunder");
        uint32 rid = _giveWalletId(r);
        vm.deal(g, 1 ether);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(g);
        game.placeDegeneretteBet{value: 0.01 ether}(rid, 0, 0.01 ether, 1, 9);
        acc = vm.stopAndReturnStateDiff();
        (, writes) = vm.accesses(address(quests));
        uint32 gid = game.walletIdOf(g);
        assertGt(gid, 0, "the paying funder registers");
        assertEq(_onlyId(acc, address(game), quests.handleDegenerette.selector), gid, "quest goes to the funder");
        _assertWritesUnder(writes, gid);
        assertEq(_qs(rid), 0, "the bet owner's quest state is untouched");
    }

    function test_HandlePurchaseFromPurchaseKeysBuyerId() public {
        address b = makeAddr("buyQuest");
        vm.record();
        vm.startStateDiffRecording();
        uint32 id = _buy(b);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        assertEq(_onlyId(acc, address(game), quests.handlePurchase.selector), id);
        _assertWritesUnder(writes, id);
        (,,, bool[2] memory done) = quests.playerQuestStates(id);
        assertTrue(done[0], "primary completed under the buyer's ID");
    }

    function test_StreakBonusAndShieldKeyById() public {
        uint32 id = 5_000_001;
        vm.record();
        _as(address(game), abi.encodeCall(quests.awardQuestStreakBonus, (id, 3, 1)));
        _as(address(game), abi.encodeCall(quests.awardQuestStreakShield, (id, 2)));
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        _assertWritesUnder(writes, id);
        assertEq(_field(id, OFF_STREAK, 16), 3);
        assertEq(_field(id, OFF_SHIELD, 8), 2);
        (uint8 shields,) = quests.shieldsOf(id);
        assertEq(shields, 2);
    }

    function test_RecordCrapsActionFromFlipCrapsBurnKeysId() public {
        address p = makeAddr("crapsBuyer");
        uint32 id = _giveWalletId(p);
        vm.prank(address(game));
        coin.mintForGame(p, 10_000);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(ContractAddresses.CRAPS);
        coin.burnCoinForCraps(p, id, (uint256(100) << 8) | 0x1 | 0x4);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        bytes[] memory c = _calls(acc, address(coin), address(quests), quests.recordCrapsAction.selector);
        assertEq(c.length, 1);
        (uint32 cid, uint8 flags) = abi.decode(c[0], (uint32, uint8));
        assertEq(cid, id);
        assertEq(flags, 0x5);
        _assertWritesUnder(writes, id);
        assertEq(_field(id, OFF_STREAK, 16), 1, "whole-day streak credit by ID");
    }

    function test_BeginAndFinalizeAfkingFromSubscriptionKeySubId() public {
        address p = makeAddr("afkSub");
        uint32 id = _giveWalletId(p); // funding is credited by wallet ID
        uint256 seat = _grantSeat(p);
        vm.deal(address(this), 50 ether);
        game.depositAfkingFunding{value: 50 ether}(id);
        vm.record();
        vm.startStateDiffRecording();
        vm.prank(p);
        game.subscribe(0, false, false, 1, 0, seat);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        (, bytes32[] memory writes) = vm.accesses(address(quests));
        assertEq(_onlyId(acc, address(game), quests.beginAfking.selector), id);
        _assertWritesUnder(writes, id);
        assertEq(_field(id, OFF_AFKING, 8), 1, "afking flag under the sub ID");

        vm.startStateDiffRecording();
        vm.prank(p);
        game.subscribe(0, false, false, 0, 0, 0);
        acc = vm.stopAndReturnStateDiff();
        assertEq(_onlyId(acc, address(game), quests.finalizeAfking.selector), id);
        assertEq(_field(id, OFF_AFKING, 8), 0, "finalized under the sub ID");
    }

    // =====================================================================
    // 19. Level-quest completion resolves the address once
    // =====================================================================

    function test_LevelQuestCompletionResolvesKeyOnce() public {
        address o = makeAddr("lqOwner");
        uint32 id = _giveWalletId(o);
        _eligible(o, false, 5);
        _setLevelQuest(QT_AFFILIATE);
        vm.recordLogs();
        vm.startStateDiffRecording();
        _as(address(affiliate), abi.encodeCall(quests.handleAffiliate, (id, 6_000)));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes[] memory ext = _calls(acc, address(quests), address(game), game.extsload.selector);
        assertEq(ext.length, 1, "one wallet-table read");
        assertEq(_bytes32Of(ext[0]), GameSlotKeys.walletElement(id), "the wallet's own element");
        bytes[] memory mp = _calls(acc, address(quests), address(game), game.mintPackedFor.selector);
        assertEq(mp.length, 1, "one mint-word read");
        assertEq(abi.decode(mp[0], (address)), o);
        assertEq(_calls(acc, address(quests), address(game), game.hasDeityPass.selector).length, 0, "no hasDeityPass");
        _assertQuestCredit(acc, id, 800);
        assertEq((_lq(id) >> 136) & 1, 1, "completed");
        assertEq(_countTopic(logs, E_LEVEL, id), 1, "LevelQuestCompleted by ID");
    }

    function test_LevelQuestCompletionForProtocolIdsReadsNoTable() public {
        _setLevelQuest(QT_AFFILIATE);
        address[2] memory keys = [ContractAddresses.VAULT, ContractAddresses.SDGNRS];
        for (uint32 id = 1; id <= 2; ++id) {
            vm.startStateDiffRecording();
            _as(address(affiliate), abi.encodeCall(quests.handleAffiliate, (id, 6_000)));
            Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
            assertEq(_calls(acc, address(quests), address(game), game.extsload.selector).length, 0, "no extsload");
            bytes[] memory mp = _calls(acc, address(quests), address(game), game.mintPackedFor.selector);
            assertEq(mp.length, 1);
            assertEq(abi.decode(mp[0], (address)), keys[id - 1], "protocol key by constant");
        }
    }

    function test_IneligibleCompletionCheckKeepsProgressThenCompletes() public {
        address o = makeAddr("lqLate");
        uint32 id = _giveWalletId(o);
        _setLevelQuest(QT_AFFILIATE);
        vm.startStateDiffRecording();
        _as(address(affiliate), abi.encodeCall(quests.handleAffiliate, (id, 6_000)));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        assertEq(_calls(acc, address(quests), address(game), game.extsload.selector).length, 1);
        assertEq(_calls(acc, address(quests), address(coinflip), coinflip.creditFlip.selector).length, 0, "no credit");
        assertEq((_lq(id) >> 136) & 1, 0, "not completed");
        assertEq(uint128(_lq(id) >> 8), 6_000, "progress kept");
        _eligible(o, false, 5);
        vm.startStateDiffRecording();
        _as(address(affiliate), abi.encodeCall(quests.handleAffiliate, (id, 1)));
        acc = vm.stopAndReturnStateDiff();
        _assertQuestCredit(acc, id, 800);
    }

    function test_UplineCompletingLevelQuestThroughAffiliateIsCreditedById() public {
        address up = makeAddr("lqUp");
        address o = makeAddr("lqCodeOwner");
        address b = makeAddr("lqBuyer");
        uint32 upid = _giveWalletId(up);
        vm.prank(address(game));
        affiliate.payAffiliate(0, bytes32(0), up, 0, 1, true, 0);
        vm.prank(o);
        affiliate.referPlayer(bytes32(uint256(uint160(up))));
        vm.prank(o);
        affiliate.createAffiliateCode(bytes32("LQ_CODE"), 0);
        vm.prank(b);
        affiliate.referPlayer(bytes32("LQ_CODE"));
        _eligible(up, false, 5);
        _setLevelQuest(QT_AFFILIATE);
        uint32 sid = _senderFor(bytes32("LQ_CODE"), 1, 50_000_000);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(address(game));
        affiliate.payAffiliate(24_000, bytes32(0), b, sid, 1, true, 0);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertQuestCredit(acc, upid, 800);
        assertEq(_countTopic(logs, E_LEVEL, upid), 1);
        bytes[] memory aff = _calls(acc, address(affiliate), address(coinflip), coinflip.creditFlip.selector);
        assertEq(aff.length, 1);
        (uint32 cid, uint256 amt) = abi.decode(aff[0], (uint32, uint256));
        assertEq(cid, upid, "the affiliate share goes to the upline's ID");
        assertGe(amt, 6_000);
    }

    // =====================================================================
    // 20. Deity bit
    // =====================================================================

    function test_DeityBitSatisfiesTheLoyaltyGate() public {
        address d = makeAddr("deityBit");
        uint32 id = _giveWalletId(d);
        _eligible(d, false, 4);
        (,,,, bool eligible) = quests.getPlayerLevelQuestView(id);
        assertFalse(eligible, "units and streak 4 with no pass");
        _eligible(d, true, 4);
        (,,,, eligible) = quests.getPlayerLevelQuestView(id);
        assertTrue(eligible, "the deity bit of the same word");
        _setLevelQuest(QT_FLIP);
        vm.recordLogs();
        vm.startStateDiffRecording();
        _as(address(coinflip), abi.encodeCall(quests.handleFlip, (id, 20_000)));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_calls(acc, address(quests), address(game), game.hasDeityPass.selector).length, 0);
        assertEq(_countTopic(logs, E_LEVEL, id), 1, "completes on the deity bit");
    }

    // =====================================================================
    // 21. Credits and events by ID
    // =====================================================================

    function test_QuestCreditsLandOnIds() public {
        address p = makeAddr("credits");
        uint32 id = _giveWalletId(p);

        _setDaily(10, QT_DECIMATOR);
        _primary(id);
        vm.startStateDiffRecording();
        _as(address(coin), abi.encodeCall(quests.handleDecimator, (id, 2_000)));
        _assertQuestCredit(vm.stopAndReturnStateDiff(), id, 100);

        _setDaily(11, QT_CRAPS_JOIN);
        _primary(id);
        vm.startStateDiffRecording();
        _as(address(coin), abi.encodeCall(quests.recordCrapsAction, (id, 0x1)));
        _assertQuestCredit(vm.stopAndReturnStateDiff(), id, 100);

        _setDaily(12, QT_FOIL);
        vm.startStateDiffRecording();
        _as(address(game), abi.encodeCall(quests.handleFoilPurchase, (id, price, 0, 0, price, price)));
        _assertQuestCredit(vm.stopAndReturnStateDiff(), id, 100);

        _setDaily(13, QT_DEG_ETH);
        _primary(id);
        vm.startStateDiffRecording();
        _as(address(game), abi.encodeCall(quests.handleDegenerette, (id, price * 2, true, price)));
        _assertQuestCredit(vm.stopAndReturnStateDiff(), id, 100);

        _eligible(p, false, 5);
        _setLevelQuest(QT_FLIP);
        vm.startStateDiffRecording();
        _as(address(coinflip), abi.encodeCall(quests.handleFlip, (id, 20_000)));
        _assertQuestCredit(vm.stopAndReturnStateDiff(), id, 800);

        vm.startStateDiffRecording();
        _as(address(parimutuel), abi.encodeCall(quests.recordGrowthBet, (id, p, game.level(), 55)));
        _assertQuestCredit(vm.stopAndReturnStateDiff(), id, 55);
    }

    function _countTopic(Vm.Log[] memory logs, bytes32 t0, uint32 id) private view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(quests) || l.topics.length < 2 || l.topics[0] != t0) continue;
            assertEq(uint256(l.topics[1]), uint256(id), "event subject is the wallet ID");
            ++n;
        }
    }

    function test_AllNineEventsCarryTheWalletId() public {
        address p = makeAddr("events");
        uint32 id = _giveWalletId(p);
        vm.recordLogs();
        _as(address(game), abi.encodeCall(quests.awardQuestStreakShield, (id, 2)));
        _setDaily(20, QT_DEG_ETH);
        _primary(id);
        _as(address(game), abi.encodeCall(quests.awardQuestStreakBonus, (id, 3, 20)));
        _setDaily(21, QT_DEG_ETH); // rolled and missed: one shield
        _setDaily(23, QT_DEG_ETH); // 22 never rolled: forgiven
        _primary(id);
        for (uint24 d = 24; d <= 27; ++d) _setDaily(d, QT_DEG_ETH); // 24..26 missed past the last shield
        _primary(id);
        _eligible(p, false, 5);
        _setLevelQuest(QT_FLIP);
        _as(address(coinflip), abi.encodeCall(quests.handleFlip, (id, 20_000)));
        _as(address(parimutuel), abi.encodeCall(quests.recordGrowthBet, (id, p, game.level(), 10)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32[9] memory sigs =
            [E_PROGRESS, E_COMPLETED, E_SHIELD_USED, E_STALL, E_SHIELD_GRANTED, E_BONUS, E_RESET, E_LEVEL, E_GROWTH];
        for (uint256 i; i < 9; ++i) assertGt(_countTopic(logs, sigs[i], id), 0, "event emitted by ID");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(quests)) continue;
            bytes32 t0 = logs[i].topics[0];
            assertTrue(
                t0 != keccak256("QuestCompleted(address,uint24,uint8,uint8,uint32,uint256)")
                    && t0 != keccak256("QuestProgressUpdated(address,uint24,uint8,uint8,uint128,uint256)")
                    && t0 != keccak256("LevelQuestCompleted(address,uint24,uint8,uint256)"),
                "address-keyed signature"
            );
        }
    }

    // =====================================================================
    // 22. marketBetGates
    // =====================================================================

    function test_MarketBetGatesReturnsTheMintWordId() public {
        address p = makeAddr("mbgBuyer");
        uint32 id = _buy(p);
        (bool may,, uint32 gid) = quests.marketBetGates(p, game.level() + 1);
        assertTrue(may);
        assertEq(gid, id);
        assertEq(gid, uint32(game.mintPackedFor(p) >> BitPackingLib.WALLET_ID_SHIFT));
    }

    function _smite(address target, uint8 symbol) private {
        address d = makeAddr(string(abi.encodePacked("mbgDeity", symbol)));
        uint32 targetId = game.walletIdOf(target);
        vm.deal(d, 200 ether);
        vm.prank(d);
        game.purchaseDeityPass{value: 100 ether}(0, symbol, bytes32(0));
        vm.prank(address(game));
        coin.mintForGame(d, 1_000);
        vm.prank(d);
        game.smite(symbol, targetId);
    }

    function test_RegistrationOnlyAndSmiteOnlyWordsCannotBet() public {
        address r = makeAddr("mbgReg");
        uint32 rid = _giveWalletId(r);
        (bool may, bool earns, uint32 id) = quests.marketBetGates(r, 1);
        assertFalse(may, "registration alone");
        assertFalse(earns);
        assertEq(id, rid);

        // A smite names an allocated account (ID 0 is the caller), so the curse lands on a
        // wallet that already holds an ID.
        address s = makeAddr("mbgSmitten");
        uint32 sid = _giveWalletId(s);
        _smite(s, 1);
        uint256 w = game.mintPackedFor(s);
        assertGt(w, 0, "the smite wrote the word");
        assertEq(w >> BitPackingLib.WALLET_ID_SHIFT, sid, "the word carries the ID");
        (may,, id) = quests.marketBetGates(s, 1);
        assertFalse(may, "curse plus registration");
        assertEq(id, sid);
    }

    /// forge-config: default.fuzz.runs = 64
    function testFuzz_MayBetImpliesWalletId(uint8 door, uint64 salt) public {
        address p = address(uint160(uint256(keccak256(abi.encode("mbgDoor", salt)))));
        _door(door % 9, p);
        uint24 lvl = game.level();
        for (uint24 l = lvl; l <= lvl + 1; ++l) {
            (bool may,, uint32 id) = quests.marketBetGates(p, l);
            assertEq(id, game.walletIdOf(p), "the gate's ID is the canonical ID");
            if (may) assertGt(id, 0, "mayBet implies a wallet ID");
        }
    }

    function _door(uint8 door, address p) private {
        vm.deal(p, 300 ether);
        if (door == 0) {
            vm.prank(p);
            game.purchase{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        } else if (door == 1) {
            vm.prank(p);
            game.purchase{value: 1 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        } else if (door == 2) {
            vm.prank(p);
            game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
        } else if (door == 3) {
            vm.prank(p);
            game.purchaseWhalePass{value: 20 ether}(0, 1, bytes32(0));
        } else if (door == 4) {
            vm.prank(p);
            game.purchaseDeityPass{value: 100 ether}(0, 7, bytes32(0));
        } else if (door == 5) {
            vm.prank(p);
            game.placeDegeneretteBet{value: 0.01 ether}(0, 0, 0.01 ether, 1, 9);
        } else if (door == 6) {
            vm.prank(address(game));
            coin.mintForGame(p, 10_000);
            vm.prank(p);
            coinflip.depositCoinflip(0, 1_000);
        } else if (door == 7) {
            vm.prank(makeAddr("mbgReferrer"));
            affiliate.referPlayer(bytes32(uint256(uint160(p))));
        } else {
            _giveWalletId(p);
            _smite(p, 8);
        }
    }

    // =====================================================================
    // 23. recordGrowthBet
    // =====================================================================

    function test_RecordGrowthBetReadsPlayerWordAndKeysById() public {
        address p = makeAddr("growth");
        uint32 pid = _giveWalletId(p);
        _eligible(p, false, 5);
        uint24 lvl = game.level();
        vm.recordLogs();
        vm.startStateDiffRecording();
        bytes memory ret = _as(address(parimutuel), abi.encodeCall(quests.recordGrowthBet, (pid, p, lvl, 50)));
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(abi.decode(ret, (uint256)), 50);
        assertEq((_lq(pid) >> 137) & 1, 1, "recorded under the ID");
        _assertQuestCredit(acc, pid, 50);
        assertEq(_countTopic(logs, E_GROWTH, pid), 1);
        bytes[] memory mp = _calls(acc, address(quests), address(game), game.mintPackedFor.selector);
        assertEq(mp.length, 1);
        assertEq(abi.decode(mp[0], (address)), p, "eligibility from the player's word");
        assertEq(_calls(acc, address(quests), address(game), game.extsload.selector).length, 0, "no table read");

        // Eligibility follows `player`; record, credit and event follow `id`.
        uint32 other = 7_777_777;
        vm.recordLogs();
        vm.startStateDiffRecording();
        ret = _as(address(parimutuel), abi.encodeCall(quests.recordGrowthBet, (other, p, lvl, 40)));
        acc = vm.stopAndReturnStateDiff();
        logs = vm.getRecordedLogs();
        assertEq(abi.decode(ret, (uint256)), 40);
        assertEq((_lq(other) >> 137) & 1, 1);
        _assertQuestCredit(acc, other, 40);
        assertEq(_countTopic(logs, E_GROWTH, other), 1);

        address q = makeAddr("growthNo");
        uint32 qid = _giveWalletId(q);
        ret = _as(address(parimutuel), abi.encodeCall(quests.recordGrowthBet, (qid, q, lvl, 40)));
        assertEq(abi.decode(ret, (uint256)), 0, "ineligible word pays nothing");
        assertEq(_lq(qid), 0, "and writes nothing");
    }

    function test_ParimutuelBetPassesTheGateIdToRecordGrowthBet() public {
        address p = makeAddr("pariBettor");
        uint32 id = _buy(p);
        _eligible(p, false, 5);
        vm.prank(address(game));
        coin.mintForGame(p, 1_000_000);
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(game.growthState.selector),
            abi.encode(uint256(0), uint256(0), uint256(0), uint24(1), true, uint8(1))
        );
        vm.startStateDiffRecording();
        vm.prank(p);
        parimutuel.placeBet(0, true);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        bytes[] memory r = _calls(acc, address(parimutuel), address(quests), quests.recordGrowthBet.selector);
        assertEq(r.length, 1);
        (uint32 rid, address rp,,) = abi.decode(r[0], (uint32, address, uint24, uint256));
        assertEq(rid, id, "the gate's ID");
        assertEq(rp, p);
        assertEq((_lq(id) >> 137) & 1, 1);
    }

    // =====================================================================
    // 24. Views by ID
    // =====================================================================

    function test_ViewsReadByIdAndDefaultForEmptyIds() public {
        address p = makeAddr("viewer");
        uint32 id = _buy(p);
        (uint32 streak, uint24 lastDay, uint128[2] memory progress, bool[2] memory done) = quests.playerQuestStates(id);
        assertEq(streak, 1);
        assertEq(lastDay, _questDay());
        assertGt(progress[0], 0);
        assertTrue(done[0]);
        (bool s0, bool s1) = quests.questCompletionToday(id);
        assertTrue(s0);
        assertFalse(s1);
        assertEq(bytes4(keccak256("questCompletionToday(uint32)")), quests.questCompletionToday.selector);
        PlayerQuestView memory v = quests.getPlayerQuestView(id);
        assertTrue(v.completed[0]);
        assertEq(v.baseStreak, quests.effectiveBaseStreak(id));
        (uint32 eff, bool afk) = quests.effectiveBaseStreakAndAfking(id);
        assertEq(eff, quests.effectiveBaseStreak(id));
        assertFalse(afk);
        _as(address(game), abi.encodeCall(quests.awardQuestStreakShield, (id, 1)));
        (uint8 shields,) = quests.shieldsOf(id);
        assertEq(shields, 1);
        _eligible(p, false, 5);
        (,,,, bool eligible) = quests.getPlayerLevelQuestView(id);
        assertTrue(eligible, "eligibility through the wallet table");

        uint32[4] memory empty = [uint32(0), _nextId(), _nextId() + 1000, type(uint32).max];
        for (uint256 i; i < 4; ++i) _assertEmptyViews(empty[i]);
    }

    function _assertEmptyViews(uint32 id) private view {
        (uint32 streak, uint24 lastDay, uint128[2] memory progress, bool[2] memory done) = quests.playerQuestStates(id);
        assertEq(streak, 0);
        assertEq(lastDay, 0);
        assertEq(progress[0] + progress[1], 0);
        assertFalse(done[0] || done[1]);
        (bool s0, bool s1) = quests.questCompletionToday(id);
        assertFalse(s0 || s1);
        PlayerQuestView memory v = quests.getPlayerQuestView(id);
        assertEq(v.baseStreak, 0);
        assertEq(v.progress[0] + v.progress[1], 0);
        assertEq(quests.effectiveBaseStreak(id), 0);
        (uint32 eff, bool afk) = quests.effectiveBaseStreakAndAfking(id);
        assertEq(eff, 0);
        assertFalse(afk);
        (uint8 shields, uint8 high) = quests.shieldsOf(id);
        assertEq(uint256(shields) + high, 0);
        (, uint128 lp,, bool lc, bool le) = quests.getPlayerLevelQuestView(id);
        assertEq(lp, 0);
        assertFalse(lc || le);
    }

    function test_GameActivityScoreReadsTheQuestStreakById() public {
        address p = makeAddr("activityStreak");
        uint32 id = _buy(p);
        (uint256 before, uint32 wid) = game.playerActivityScore(p);
        assertEq(wid, id);
        _as(address(game), abi.encodeCall(quests.awardQuestStreakBonus, (id, 40, game.currentDayView())));
        // The reward streak is the start-of-day snapshot, so the bonus shows from the next quest day.
        vm.prank(address(game));
        quests.rollDailyQuest(_questDay() + 1, 11, false, false, false);
        (uint256 afterBonus,) = game.playerActivityScore(p);
        assertGt(afterBonus, before, "the streak awarded to the ID raises the address's score");
    }

    // =====================================================================
    // Storage roots keyed by uint32
    // =====================================================================

    function test_StorageRootsAreKeyedByUint32Id() public {
        uint32 id = 4_000_000_001;
        _setLevelQuest(QT_FLIP);
        _as(address(coinflip), abi.encodeCall(quests.handleFlip, (id, 100)));
        assertEq(_field(id, OFF_LAST_SYNC, 24), _questDay(), "questPlayerState at slot 1 keyed uint256(id)");
        uint256 lq = _lq(id);
        assertEq(uint8(lq), uint8(_active() >> 136), "levelQuestPlayerState at slot 2: version");
        assertEq(uint128(lq >> 8), 100, "levelQuestPlayerState at slot 2: progress");
        uint24 day = 300;
        vm.prank(address(game));
        quests.rollDailyQuest(day, 7, false, false, false);
        bytes32 b = keccak256(abi.encode(uint256(day >> 8), BITMAP_ROOT));
        assertEq((uint256(vm.load(address(quests), b)) >> uint8(day)) & 1, 1, "questRolledDayBitmap at slot 3");
        (uint32 streak,,,) = quests.playerQuestStates(id);
        assertEq(streak, _field(id, OFF_STREAK, 16));
    }

    // =====================================================================
    // 26. Revert-freedom for every handler and caller, whatever the ID
    // =====================================================================

    function _pickId(uint8 pick, uint32 raw) private view returns (uint32) {
        uint256 k = pick % 5;
        if (k == 0) return 0;
        if (k == 1) return type(uint32).max;
        if (k == 2) return _nextId() + (raw % 1000);
        if (k == 3) return 1 + (raw % 3);
        return raw;
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_HandlersNeverRevertForTheirCallers(
        uint32 raw,
        uint8 pick,
        uint256 amount,
        uint8 levelType,
        uint8 dailyType,
        bool afk
    ) public {
        uint32 id = _pickId(pick, raw);
        amount = bound(amount, 0, 1e24);
        uint24 wallDay = uint24(game.currentDayView());
        _setLevelQuest(uint8(bound(levelType, 1, 11)));
        _setDaily(_questDay(), uint8(bound(dailyType, 2, 10)));
        if (afk) _as(address(game), abi.encodeCall(quests.beginAfking, (id, wallDay)));
        _as(address(coinflip), abi.encodeCall(quests.handleFlip, (id, amount)));
        _as(address(coin), abi.encodeCall(quests.handleDecimator, (id, amount)));
        _as(address(affiliate), abi.encodeCall(quests.handleAffiliate, (id, amount)));
        _as(address(game), abi.encodeCall(quests.handleDegenerette, (id, amount, amount & 1 == 0, price)));
        _as(
            address(game),
            abi.encodeCall(quests.handlePurchase, (id, amount % 10 ether, uint32(amount % 50), amount % 5 ether, price, price))
        );
        _as(
            address(game),
            abi.encodeCall(
                quests.handleFoilPurchase, (id, amount % 10 ether, uint32(amount % 50), amount % 5 ether, price, price)
            )
        );
        _as(address(game), abi.encodeCall(quests.awardQuestStreakBonus, (id, uint16(amount), wallDay)));
        _as(address(coin), abi.encodeCall(quests.recordCrapsAction, (id, uint8(amount) & 0x1F)));
        _as(address(game), abi.encodeCall(quests.awardQuestStreakShield, (id, uint16(amount >> 16))));
        _as(
            address(parimutuel),
            abi.encodeCall(quests.recordGrowthBet, (id, address(uint160(raw)), game.level(), amount % 1e6))
        );
        _as(address(game), abi.encodeCall(quests.finalizeAfking, (id, uint24(amount), wallDay - 1, wallDay)));
        _as(address(game), abi.encodeCall(quests.beginAfking, (id, wallDay)));
        _as(address(game), abi.encodeCall(quests.finalizeAfking, (id, uint24(amount >> 24), wallDay, wallDay + 1)));
    }
}
