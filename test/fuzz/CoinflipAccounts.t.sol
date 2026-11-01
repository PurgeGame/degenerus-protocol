// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CoinflipCore} from "../../contracts/modules/CoinflipCore.sol";
import {GameFacade} from "../../contracts/modules/GameFacade.sol";
import {QaTrace} from "../helpers/QaTrace.sol";

import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title CoinflipAccounts -- Coinflip doors acting for an account by wallet ID (keys, operators, gifts)
/// @notice A is an ordinary account; P is an operator A approved on its ID; X is a stranger.
///         Coinflip state and stakes follow A's ID. FLIP burns and withdrawals use A's wallet;
///         loss WWXRP credits stay claimable under A's ID. A deposit is direct (flip record, BAF
///         draw entry, coinflip boon) only when the caller is the payee: a self deposit or the
///         key naming its own ID. An operator deposit and a gift are not direct; a gift burns the
///         funder's FLIP, never spends the account's winnings and earns the funder's quest.
///         Self actions make no Game `resolveAccount` call; an ID-addressed action makes one, and
///         account actions use the supplied ID with no registration.
contract CoinflipAccountsTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant QUEST_COMPLETED = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");
    bytes32 internal constant CLAIM_STATE = keccak256("CoinflipClaimState(uint32,uint128,uint128,uint24)");
    bytes32 internal constant DEPOSIT = keccak256("CoinflipDeposit(uint32,uint256)");
    bytes32 internal constant TOGGLED = keccak256("CoinflipAutoRebuyToggled(uint32,bool)");
    bytes32 internal constant STOP_SET = keccak256("CoinflipAutoRebuyStopSet(uint32,uint256)");
    bytes32 internal constant BAF_DRAW_ENTERED = keccak256("BafDrawEntered(uint24,uint32,uint32,uint96,uint96)");
    bytes32 internal constant BIG_RECORD = keccak256("BigRecordUpdated(uint8,uint32,uint256,uint128,uint256)");

    /// @dev Coinflip storage roots (scripts/layout/golden/Coinflip.json).
    uint256 internal constant STAKE_ROOT = 0;
    uint256 internal constant PLAYER_STATE_ROOT = 2;
    /// @dev Game boonPacked slot0: coinflip tier at bits 48..55, stamp day at bits 0..23.
    uint256 internal constant COINFLIP_TIER_SHIFT = 48;
    uint256 internal constant PAST_PAID_ADMISSION = 3_000_000_001;
    uint8 internal constant RECORD_KIND_FLIP = 0;

    address internal account;
    uint32 internal accountId;
    address internal other;
    uint32 internal otherId;
    address internal stranger;
    address internal operator;

    uint32 private _expectedQuestId;
    function _checkExpectedQuest() private {
        if (_expectedQuestId==0) return;
        bytes32 slot=keccak256(abi.encode(uint256(_expectedQuestId),QaTrace.QUESTS+1));
        uint256 word=uint256(vm.load(address(quests),slot));
        assertEq(uint24(word>>48),uint24(uint256(vm.load(address(quests),bytes32(QaTrace.QUESTS)))),"correct quest wallet synchronized");
        _expectedQuestId=0;
    }
    function _readyFlipQuest(uint32 id) private {
        uint256 day=_today();
        vm.store(address(quests),bytes32(QaTrace.QUESTS),bytes32((day|(1<<24))|((day|(2<<24))<<64)));
        vm.store(address(quests),keccak256(abi.encode(uint256(id),QaTrace.QUESTS+1)),bytes32(day|(day<<24)|(day<<48)|(uint256(1)<<192)));
    }

    function setUp() public {
        _deployProtocol();
        account = makeAddr("cfa_account_main");
        accountId = _giveWalletId(account);
        other = makeAddr("cfa_other");
        otherId = _giveWalletId(other);
        stranger = makeAddr("cfa_stranger");
        operator = makeAddr("cfa_operator");
        vm.prank(account);
        game.setOperatorApproval(accountId, operator, true);
    }

    // =====================================================================
    //                              helpers
    // =====================================================================



    function _today() internal view returns (uint24) {
        return game.currentDayView_g542950();
    }

    function _warpToDay(uint24 d) internal {
        _setRequestedFixtureDay(d);
        // Direct settlement fixtures also roll the active quest day, preserving quest types.
        bytes32 root = bytes32(QaTrace.QUESTS);
        uint256 pair = uint256(vm.load(address(quests), root));
        uint256 mask = uint256(0xffffff) | (uint256(0xffffff) << 64);
        vm.store(address(quests), root, bytes32((pair & ~mask) | d | (uint256(d) << 64)));
        vm.warp((uint256(d - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
    }

    function _resolveDay(uint24 d, bool win) internal {
        uint256 word = uint256(keccak256(abi.encodePacked("coinflip_accounts", d)));
        word = win ? word | 1 : word & ~uint256(1);
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, d);
    }

    function _fundFlip(address p, uint256 amount) internal {
        vm.prank(GAME);
        coin.mintForGame_g152734(p, amount);
    }

    function _slotA(address p) internal view returns (uint256) {
        return uint256(vm.load(address(coinflip), keccak256(abi.encode(_gameId(p), PLAYER_STATE_ROOT))));
    }
    function _slotA(uint32 p) internal view returns (uint256) {
        return uint256(vm.load(address(coinflip), keccak256(abi.encode(_gameId(p), PLAYER_STATE_ROOT))));
    }

    function _claimableStored(address p) internal view returns (uint256) {
        return uint128(_slotA(p));
    }
    function _claimableStored(uint32 p) internal view returns (uint256) {
        return uint128(_slotA(p));
    }

    function _lastClaim(address p) internal view returns (uint24) {
        return uint24(_slotA(p) >> 128);
    }
    function _lastClaim(uint32 p) internal view returns (uint24) {
        return uint24(_slotA(p) >> 128);
    }




    function _gameId(address p) internal view returns (uint32) {
        return _fixtureId(p);
    }
    function _gameId(uint32 p) internal view returns (uint32) {
        return _fixtureId(p);
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _lane(uint24 day, uint32 id) internal view returns (uint256) {
        return CoinflipStorage.read(address(coinflip), id, day);
    }

    /// @dev A live, non-deity coinflip boon of `tier` stamped today for wallet `id`.
    function _seedCoinflipBoon(uint32 id, uint8 tier) internal {
        bytes32 s = GameSlotKeys.byId(id, GameSlots.BOON_PACKED);
        uint256 v = uint256(vm.load(address(game), s));
        v &= ~((uint256(0xFF) << COINFLIP_TIER_SHIFT) | uint256(0xFFFFFFFFFFFF));
        v |= (uint256(tier) << COINFLIP_TIER_SHIFT) | uint256(game.currentDayView_g542950());
        vm.store(address(game), s, bytes32(v));
        require(_coinflipBoonTier(id) == tier, "fixture: coinflip boon lane");
    }

    function _coinflipBoonTier(uint32 id) internal view returns (uint256) {
        (uint256 slot0,) = game.boonPacked(id);
        return (slot0 >> COINFLIP_TIER_SHIFT) & 0xFF;
    }

    /// @dev Give A settled winnings in its own Coinflip state: a credited stake wins and the account's
    ///      zero-amount settle banks it into `claimableStored`. Returns the banked amount.
    function _bankWinnings(uint256 credit) internal returns (uint256 bank) {
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip_g317(accountId, credit);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.prank(account);
        coinflip.playCoinflip(accountId, 0);
        _checkExpectedQuest();
        bank = _claimableStored(accountId);
        require(bank > 0, "fixture: winnings banked");
    }

    /// @dev Leave A an unsettled losing day (stake credited, then resolved as a loss).
    function _pendingLoss() internal {
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip_g317(accountId, 300);
        _warpToDay(d + 1);
        _resolveDay(d + 1, false);
    }

    function _count(Vm.Log[] memory logs, address emitter, bytes32 topic) internal pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == topic) ++n;
        }
    }

    function _countFor(Vm.Log[] memory logs, address emitter, bytes32 topic, bytes32 topic1)
        internal pure returns (uint256 n)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != emitter || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] == topic && logs[i].topics[1] == topic1) ++n;
        }
    }

    function _t(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }



    // =====================================================================
    //                 1. a key deposits through its own ID (direct)
    // =====================================================================

    /// @notice A's deposit through its own ID spends A's settled winnings first and burns A's wallet
    ///         FLIP for the rest; the stake and quest are A's, and the deposit is direct: A's
    ///         coinflip boon is spent and, on the armed day, the BAF draw entry carries A.
    function test_KeyDepositWithOwnId_ClaimableFirstThenWallet_Direct() public {
        uint256 bank = _bankWinnings(400);
        uint256 amount = bank + 1_000;
        _fundFlip(account, 5_000);
        _seedCoinflipBoon(accountId, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);
        uint256 laneBefore = _lane(target, accountId);
        uint256 otherLaneBefore = _lane(target, otherId);

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, account)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.registerWallet_g9539.selector), 0);
        _expectedQuestId = accountId;
        vm.expectCall(GAME, abi.encodeCall(GameFacade.consumeCoinflipBoon_g2902, (accountId)), 1);
        vm.expectCall(address(coin), abi.encodeWithSignature("burnForCoinflip(address,uint256)", account, 1_000), 1);
        vm.recordLogs();
        vm.prank(account);
        coinflip.playCoinflip(accountId, amount);
        _checkExpectedQuest();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_claimableStored(accountId), 0, "the account's winnings funded the stake first");
        assertEq(coin.balanceOf(account), 4_000, "the account's wallet paid only the remainder");
        assertGe(_lane(target, accountId) - laneBefore, amount + amount / 4, "stake on A with the 25% boon");
        assertEq(_lane(target, otherId), otherLaneBefore, "nothing staked on another account's lane");
        assertEq(_coinflipBoonTier(accountId), 0, "the account's coinflip boon was spent");

        (uint24 day, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(day, target);
        assertEq(count, 1, "the direct deposit entered the BAF draw");
        assertEq(total, amount, "draw weight is the raw principal");
        (uint32 eid,) = coinflip.bafDrawEntryAt(target, 0);
        assertEq(eid, accountId, "the draw entry carries A");
        assertEq(_countFor(logs, address(coinflip), BAF_DRAW_ENTERED, bytes32(uint256(target))), 1);
        assertEq(_countFor(logs, address(coinflip), DEPOSIT, bytes32(uint256(_fixtureId(accountId)))), 1, "CoinflipDeposit names A's key");
        assertEq(_countFor(logs, address(coinflip), CLAIM_STATE, bytes32(uint256(accountId))), 1, "claim state names A's key");
        assertEq(_countFor(logs, address(coinflip), DEPOSIT, bytes32(uint256(_fixtureId(other)))), 0);
    }

    /// @notice A's deposit through its own ID can set the flip record: the record and its claim
    ///         accrue to A, and the trophy and the sDGNRS leg go to A's wallet (the payee).
    function test_KeyDepositWithOwnId_ArmsFlipRecord_TrophyToPayee() public {
        _fundFlip(account, 300_000);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.payRecordSdgnrs.selector, accountId), 1);
        vm.recordLogs();
        vm.prank(account);
        coinflip.playCoinflip(accountId, 200_000);
        _checkExpectedQuest();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coinflip.biggestFlipEver(), 200_000, "the direct deposit set the record");
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != BIG_RECORD) continue;
            assertEq(uint8(uint256(logs[i].topics[1])), RECORD_KIND_FLIP);
            assertEq(uint32(uint256(logs[i].topics[2])), accountId, "the record accrues to A");
            seen = true;
        }
        assertTrue(seen, "BigRecordUpdated emitted");
        assertEq(recordBounty.ownerOf(RECORD_KIND_FLIP), account, "trophy to the payee");
    }

    /// @notice A completed quest on an authorized deposit names the account key and its reward joins
    ///         the account's stake; on a gift it names the funding caller.
    function test_QuestCompleted_NamesAccountKey_OrGiftFunder() public {
        uint24 target = _today() + 1;
        _readyFlipQuest(accountId);
        _fundFlip(account, 10_000);
        uint256 before = _lane(target, accountId);
        vm.recordLogs();
        vm.prank(account);
        coinflip.playCoinflip(accountId, 2_000);
        _checkExpectedQuest();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(quests), QUEST_COMPLETED, bytes32(uint256(_fixtureId(accountId)))), 1, "quest names A's key");
        assertEq(_countFor(logs, address(quests), QUEST_COMPLETED, bytes32(uint256(_fixtureId(other)))), 0);
        assertEq(_lane(target, accountId) - before, 2_100, "quest reward joins A's stake");

        vm.prank(address(coinflip));
        uint32 funderId=game.registerWallet_g9539(stranger,true);
        _readyFlipQuest(funderId);
        _fundFlip(stranger, 10_000);
        before = _lane(target, accountId);
        vm.recordLogs();
        vm.prank(stranger);
        coinflip.playCoinflip(accountId, 2_000);
        _checkExpectedQuest();
        logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(quests), QUEST_COMPLETED, bytes32(uint256(_fixtureId(stranger)))), 1, "a gift's quest names the funder");
        assertEq(_countFor(logs, address(quests), QUEST_COMPLETED, bytes32(uint256(_fixtureId(accountId)))), 0);
        assertEq(_lane(target, accountId) - before, 2_100, "the funder's quest reward joins A's stake");
        assertEq(_gameId(stranger), funderId);
    }

    // =====================================================================
    //                       2. a stranger's gift to A
    // =====================================================================

    /// @notice X's deposit for A is a gift: X's FLIP pays the whole principal, A's banked winnings
    ///         stay put, X registers and earns the quest, the stake is A's, and nothing direct
    ///         happens (no boon, no draw entry, no record). A's pending loss mints WWXRP to A.
    function test_StrangerGiftToAccount_FunderPays_NotDirect_LossWwxrpToAccount() public {
        uint256 bank = _bankWinnings(400);
        _pendingLoss();
        _seedCoinflipBoon(accountId, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);
        _fundFlip(stranger, 300_000);
        uint32 funderId = uint32(_walletCount());
        uint256 laneBefore = _lane(target, accountId);
        uint256 accountFlip = coin.balanceOf(account);
        uint256 accountWwxrp = wwxrp.claimable(accountId);

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, stranger)), 1);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.registerWallet_g9539, (stranger, true)), 1);
        _expectedQuestId = funderId;
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.handleFlip_g217.selector, accountId), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.consumeCoinflipBoon_g2902.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.payRecordSdgnrs.selector), 0);
        vm.prank(stranger);
        coinflip.playCoinflip(accountId, 250_000);
        _checkExpectedQuest();

        assertEq(coin.balanceOf(stranger), 50_000, "the funder paid the whole principal");
        assertEq(coin.balanceOf(account), accountFlip, "the account's wallet is untouched");
        assertEq(_claimableStored(accountId), bank, "a gift never spends the account's winnings");
        assertEq(_lane(target, accountId) - laneBefore, 250_000, "stake on A, no boon, no bonus");
        assertEq(_coinflipBoonTier(accountId), 3, "A's coinflip boon kept");
        (,, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0, "a gift carries no draw weight");
        assertEq(coinflip.biggestFlipEver(), 0, "a gift cannot set the record");
        assertGt(wwxrp.claimable(accountId), accountWwxrp, "A's loss consolation stayed under A's ID");
        assertEq(wwxrp.balanceOf(stranger), 0, "nothing to the funder");
        assertEq(_gameId(stranger), funderId, "the paying funder registered");
    }

    // =====================================================================
    //                          3. operator deposits
    // =====================================================================

    /// @notice P's deposit for an ordinary account A burns A's FLIP and quests as A, but is not
    ///         direct (no boon, no draw entry, no record), as for any operator.
    function test_OperatorDeposit_OrdinaryAccount_BurnsAccountFlip_NotDirect() public {
        address a = makeAddr("cfa_account");
        uint32 aid = _giveWalletId(a);
        vm.prank(a);
        game.setOperatorApproval(0, operator, true);
        _fundFlip(a, 300_000);
        _seedCoinflipBoon(aid, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (aid, operator)), 1);
        _expectedQuestId = aid;
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.registerWallet_g9539.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.consumeCoinflipBoon_g2902.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.payRecordSdgnrs.selector), 0);
        vm.prank(operator);
        coinflip.playCoinflip(aid, 250_000);
        _checkExpectedQuest();

        assertEq(coin.balanceOf(a), 50_000, "the account's FLIP paid");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_gameId(operator), 0, "the operator never registers");
        assertEq(_lane(target, aid), 250_000, "stake on A, no boon");
        assertEq(_coinflipBoonTier(aid), 3);
        (,, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0, "an operator deposit carries no draw weight");
        assertEq(coinflip.biggestFlipEver(), 0, "an operator deposit cannot set the record");
    }

    /// @notice P's deposit for A burns A's FLIP (the payee), quests as A, and is not direct.
    function test_OperatorDepositApprovedOnId_BurnsAccountFlip_NotDirect() public {
        _fundFlip(account, 300_000);
        _seedCoinflipBoon(accountId, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);
        uint256 laneBefore = _lane(target, accountId);

        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, operator)), 1);
        vm.expectCall(address(coin), abi.encodeWithSignature("burnForCoinflip(address,uint256)", account, 250_000), 1);
        _expectedQuestId = accountId;
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.consumeCoinflipBoon_g2902.selector), 0);
        vm.prank(operator);
        coinflip.playCoinflip(accountId, 250_000);
        _checkExpectedQuest();

        assertEq(coin.balanceOf(account), 50_000, "the account's payee paid");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_lane(target, accountId) - laneBefore, 250_000);
        assertEq(_coinflipBoonTier(accountId), 3);
        (,, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0);
        assertEq(coinflip.biggestFlipEver(), 0);
    }

    // =====================================================================
    //                            4. edge reverts
    // =====================================================================

    /// @notice An unallocated ID reverts the Game's E for any caller; a new wallet's self deposit
    ///         allocates, and past paid admission it reverts E; deposits for A still work there.
    function test_UnallocatedId_E_SelfAllocates_PastAdmissionE() public {
        _fundFlip(stranger, 10_000);
        _fundFlip(account, 10_000);
        uint32 unallocated = uint32(_walletCount());
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        coinflip.playCoinflip(unallocated, 1_000);
        _checkExpectedQuest();
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(account);
        coinflip.playCoinflip(unallocated, 1_000);
        _checkExpectedQuest();
        assertEq(coin.balanceOf(stranger), 10_000);

        address fresh = makeAddr("cfa_fresh");
        _fundFlip(fresh, 10_000);
        uint32 expected = uint32(_walletCount());
        vm.prank(fresh);
        coinflip.playCoinflip(0, 1_000);
        _checkExpectedQuest();
        assertEq(_gameId(fresh), expected, "a paid self deposit allocates");

        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAST_PAID_ADMISSION));
        address late = makeAddr("cfa_late");
        _fundFlip(late, 10_000);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(late);
        coinflip.playCoinflip(0, 1_000);
        _checkExpectedQuest();
        vm.prank(account);
        coinflip.playCoinflip(accountId, 1_000);
        _checkExpectedQuest();
        assertEq(coin.balanceOf(account), 9_000, "the account still deposits for A past admission");
    }

    /// @notice A zero-amount gift by X settles A's resolved days into A's state, mints nothing to X,
    ///         registers nobody, and A's loss consolation stays under A's ID.
    function test_ZeroAmountGift_SettlesAccount_MintsNothingToCaller() public {
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip_g317(accountId, 400);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        uint256 payout = coinflip.previewClaimCoinflipsById(_fixtureId(accountId));
        assertGt(payout, 0);
        vm.prank(GAME);
        coinflip.creditFlip_g317(accountId, 300);
        _warpToDay(d + 2);
        _resolveDay(d + 2, false);
        uint256 accountWwxrp = wwxrp.claimable(accountId);

        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.registerWallet_g9539.selector), 0);
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.handleFlip_g217.selector), 0);
        vm.prank(stranger);
        coinflip.playCoinflip(accountId, 0);
        _checkExpectedQuest();

        assertEq(_claimableStored(accountId), payout, "A's win settled into A's state");
        assertEq(_lastClaim(accountId), d + 2, "both days walked");
        assertEq(coin.balanceOf(stranger), 0, "nothing minted to the caller");
        assertEq(wwxrp.balanceOf(stranger), 0);
        assertGt(wwxrp.claimable(accountId), accountWwxrp, "the loss consolation stayed under A's ID");
        assertEq(_gameId(stranger), 0, "a zero-amount gift registers nobody");
    }

    // =====================================================================
    //                 5. the Game's zero-amount vault settle
    // =====================================================================

    function _gameSettlesVault() internal {
        uint24 d = _today();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (uint32(1), GAME)), 1);
        vm.expectCall(address(coin), abi.encodeWithSignature("burnForCoinflip(address,uint256)"), 0);
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.handleFlip_g217.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.registerWallet_g9539.selector), 0);
        vm.prank(GAME);
        coinflip.playCoinflip(1, 0);
        _checkExpectedQuest();
        assertEq(_lastClaim(VAULT), d + 1, "the vault's days settled");
        assertGt(_claimableStored(VAULT), 0, "the vault's seed win banked in its own state");
    }

    /// @notice `playCoinflip(1, 0)` from GAME with no approval is a zero-amount gift: it settles
    ///         the vault's days with no burn and no quest call, and never reverts.
    function test_GameSettlesVault_WithoutApproval() public {
        (address key, address payee, bool authorized) = game.resolveAccount_g7029(1, GAME);
        assertEq(key, VAULT);
        assertEq(payee, VAULT);
        assertFalse(authorized, "GAME is not the vault's operator");
        _gameSettlesVault();
    }

    /// @notice The same call with `operatorApprovals[1][GAME]` set takes the authorized branch and
    ///         behaves identically for a zero amount.
    function test_GameSettlesVault_WithApproval() public {
        vm.prank(VAULT);
        game.setOperatorApproval(0, GAME, true);
        (,, bool authorized) = game.resolveAccount_g7029(1, GAME);
        assertTrue(authorized, "the vault approved GAME");
        _gameSettlesVault();
    }

    /// @notice Pinned through the real advance: the x0 seal arms the BAF draw and settles the vault
    ///         with `playCoinflip(1, 0)` in one frame, and the game passes level 10.
    function test_X0Seal_SettlesVault_RealAdvance_WithoutApproval() public {
        _driveThroughX0Seal();
    }

    function test_X0Seal_SettlesVault_RealAdvance_WithApproval() public {
        vm.prank(VAULT);
        game.setOperatorApproval(0, GAME, true);
        _driveThroughX0Seal();
    }

    function _driveThroughX0Seal() internal {
        vm.expectCall(address(coinflip), abi.encodeCall(CoinflipCore.playCoinflip, (uint32(1), uint256(0))));
        address buyer = makeAddr("cfa_x0_buyer");
        vm.deal(buyer, 100_000 ether);
        vm.deal(address(game), 2_000 ether);
        uint256 t = block.timestamp;
        for (uint256 day; day < 600 && game.currentLvl() < 10; ++day) {
            t += 1 days + 1;
            vm.warp(t);
            _seedPools(49.9 ether, 100 ether);
            _buyTickets(buyer, 4_000);
            for (uint256 j; j < 80; ++j) {
                _fulfillVrf();
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
                if (!ok) break;
            }
        }
        assertGe(game.currentLvl(), 10, "the game passed the x0 seal");
        (uint24 armed,,) = coinflip.bafDrawInfo();
        assertTrue(armed != 0, "the x0 branch ran (BAF draw armed in the same frame as the vault settle)");
        assertGe(_lastClaim(VAULT), armed - 1, "the vault's days settled at the seal");
    }

    function _seedPools(uint256 targetNext, uint256 targetFuture) internal {
        bytes32 slot = bytes32(uint256(GameSlots.PRIZE_POOLS_PACKED));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 next = uint128(packed);
        uint256 future = packed >> 128;
        if (next < targetNext) next = targetNext;
        if (future < targetFuture) future = targetFuture;
        vm.store(address(game), slot, bytes32((future << 128) | next));
    }

    function _buyTickets(address who, uint256 qty) internal {
        (,,, bool rngLocked_, uint256 priceWei) = game.purchaseInfo_g1027();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        vm.prank(who);
        try game.purchaseOrderFor{value: cost}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrf() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode("cfa_x0_word", block.timestamp, game.currentLvl(), reqId)));
        if (word == 0) word = 2;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    // =====================================================================
    //                    6. claims and settings for A
    // =====================================================================

    /// @notice X may not claim or configure A (`NotApproved`); A's and P's claims for A mint to A's
    ///         wallet and the claim state is A's (event names A's ID).
    function test_AccountClaims_KeyAndOperatorMintToKey_StrangerNotApproved() public {
        uint24 d = _today();
        _fundFlip(account, 10_000);
        vm.prank(account);
        coinflip.playCoinflip(accountId, 1_000);
        _checkExpectedQuest();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);

        vm.startPrank(stranger);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.claimCoinflips(accountId, type(uint256).max);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.claimCoinflipCarry(accountId, 1);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(accountId, true, 0);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(accountId, false, 0);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(accountId, 0);
        vm.stopPrank();

        uint256 preview = coinflip.previewClaimCoinflipsById(_fixtureId(accountId));
        assertGt(preview, 0);
        uint256 accountBefore = coin.balanceOf(account);
        vm.expectCall(GAME, abi.encodeCall(GameFacade.resolveAccount_g7029, (accountId, account)), 1);
        vm.recordLogs();
        vm.prank(account);
        uint256 got = coinflip.claimCoinflips(accountId, type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(got, preview);
        assertEq(coin.balanceOf(account) - accountBefore, got, "the key's claim minted to the key");
        assertEq(_countFor(logs, address(coinflip), CLAIM_STATE, bytes32(uint256(accountId))), 1, "claim state names A's key");
        assertEq(_countFor(logs, address(coinflip), CLAIM_STATE, bytes32(uint256(_gameId(other)))), 0);

        vm.prank(operator);
        coinflip.playCoinflip(accountId, 1_000);
        _checkExpectedQuest();
        _warpToDay(d + 2);
        _resolveDay(d + 2, true);
        preview = coinflip.previewClaimCoinflipsById(_fixtureId(accountId));
        assertGt(preview, 0);
        accountBefore = coin.balanceOf(account);
        vm.prank(operator);
        got = coinflip.claimCoinflips(accountId, type(uint256).max);
        assertEq(got, preview);
        assertEq(coin.balanceOf(account) - accountBefore, got, "P's claim for A minted to A");
        assertEq(coin.balanceOf(operator), 0, "nothing to the operator");
    }

    /// @notice Auto-rebuy and the carry live in A's own Coinflip state; P's carry claim, P's
    ///         take-profit and A's disable all act on A's ID and every mint goes to A's wallet.
    function test_AccountAutoRebuyAndCarry_StateOnAccountId_PaysKey() public {
        // The deploy day opens with the previous flip day settled, as the daily engine leaves it.
        _resolveDay(_today() - 1, false);
        vm.recordLogs();
        vm.prank(account);
        coinflip.setCoinflipAutoRebuy(accountId, true, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(coinflip), TOGGLED, bytes32(uint256(accountId))), 1, "toggle names the account ID");
        assertEq(_countFor(logs, address(coinflip), STOP_SET, bytes32(uint256(_fixtureId(accountId)))), 1);
        (bool enabled,,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(accountId));
        assertTrue(enabled, "A's state armed");
        (enabled,,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(other));
        assertFalse(enabled, "another account's state untouched");

        uint24 d = _today();
        _fundFlip(account, 10_000);
        vm.prank(account);
        coinflip.playCoinflip(accountId, 1_000);
        _checkExpectedQuest();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);

        uint256 accountBefore = coin.balanceOf(account);
        vm.prank(operator);
        uint256 claimed = coinflip.claimCoinflipCarry(accountId, type(uint256).max);
        assertGt(claimed, 1_000, "the winning carry paid out");
        assertEq(coin.balanceOf(account) - accountBefore, claimed, "carry minted to A");
        assertEq(coin.balanceOf(operator), 0);
        (,, uint256 carry,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(accountId));
        assertEq(carry, 0);

        vm.prank(operator);
        coinflip.setCoinflipAutoRebuyTakeProfit(accountId, 500);
        (, uint256 stop,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(accountId));
        assertEq(stop, 500, "take profit on A's state");

        vm.recordLogs();
        vm.prank(account);
        coinflip.setCoinflipAutoRebuy(accountId, false, 0);
        logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(coinflip), TOGGLED, bytes32(uint256(_fixtureId(accountId)))), 1);
        (enabled,,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(accountId));
        assertFalse(enabled);
    }

    // =====================================================================
    //                    7. no GAME branch; enable precedence
    // =====================================================================

    /// @notice GAME has no auto-rebuy branch: with a nonzero ID it is an unauthorized caller.
    ///         Re-enabling reverts AutoRebuyAlreadyEnabled; once the flip is frozen RngLocked wins.
    function test_SetAutoRebuy_NoGameBranch_AlreadyEnabled_RngLockedFirst() public {
        vm.startPrank(GAME);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(1, true, 0);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(accountId, true, 0);
        vm.expectRevert(CoinflipCore.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(otherId, false, 0);
        vm.stopPrank();

        uint24 d = _today();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.prank(account);
        coinflip.setCoinflipAutoRebuy(accountId, true, 0);
        vm.expectRevert(CoinflipCore.AutoRebuyAlreadyEnabled.selector);
        vm.prank(account);
        coinflip.setCoinflipAutoRebuy(accountId, true, 0);

        _warpToDay(d + 2);
        assertFalse(coinflip.flipResolvedToday(), "today's flip unresolved");
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        vm.prank(account);
        coinflip.setCoinflipAutoRebuy(accountId, true, 0);
        vm.expectRevert(CoinflipCore.RngLocked.selector);
        vm.prank(operator);
        coinflip.setCoinflipAutoRebuy(accountId, false, 0);
    }

    // =====================================================================
    //                       8. self paths
    // =====================================================================




    /// @notice Self actions (`id == 0`) on every Coinflip door make no Game `resolveAccount` call.
    function test_SelfPaths_MakeNoResolveAccountCall() public {
        address p = makeAddr("cfa_self");
        _fundFlip(p, 10_000);
        uint24 d = _today();
        vm.expectCall(GAME, abi.encodeWithSelector(GameFacade.resolveAccount_g7029.selector), 0);
        vm.prank(p);
        coinflip.playCoinflip(0, 1_000);
        _checkExpectedQuest();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.startPrank(p);
        coinflip.claimCoinflips(0, type(uint256).max);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, 5);
        coinflip.claimCoinflipCarry(0, 1);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        coinflip.playCoinflip(0, 0);
        _checkExpectedQuest();
        vm.stopPrank();
        assertGt(coin.balanceOf(p), 9_000, "the self win paid the caller");
    }
}
