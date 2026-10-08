// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusQuests} from "../../contracts/DegenerusQuests.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title CoinflipAccounts -- Coinflip doors acting for an account by wallet ID (smurfs, operators, gifts)
/// @notice O owns subaccount S; P is an operator O approved for S; X is a stranger.
///         Coinflip state and stakes follow S's ID. FLIP burns and withdrawals use O's wallet;
///         loss WWXRP credits stay claimable under S's ID. A deposit is
///         direct (flip record, BAF draw entry, coinflip boon) only when the caller is the payee: a
///         self deposit or a smurf's owner. An operator deposit and a gift are not direct; a gift
///         burns the funder's FLIP, never spends the account's winnings and earns the funder's quest.
///         Self actions make no Game `resolveAccount` call; an ID-addressed action makes one, and a
///         subaccount actions use the supplied ID with no registration.
contract CoinflipAccountsTest is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant QUEST_COMPLETED = keccak256("QuestCompleted(uint32,uint8,uint32,uint256)");
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

    address internal owner;
    uint32 internal ownerId;
    uint32 internal smurfId;
    address internal stranger;
    address internal operator;

    function setUp() public {
        _deployProtocol();
        owner = makeAddr("cfa_owner");
        ownerId = _giveWalletId(owner);
        _grantSmurfBase(owner, 1);
        (smurfId,) = _createSmurf(owner);
        stranger = makeAddr("cfa_stranger");
        operator = makeAddr("cfa_operator");
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
    }

    // =====================================================================
    //                              helpers
    // =====================================================================



    /// @dev `o` (which holds an ID) creates a smurf, paying the ticket in fresh ETH.
    function _createSmurf(address o) internal returns (uint32 sid, uint32 skey) {
        (,,,, uint256 price) = game.purchaseInfo();
        vm.deal(o, price);
        vm.prank(o);
        sid = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        skey = sid;
        (address key, address payee, bool authorized) = game.resolveAccount(sid, o);
        require(key == address(0) && payee == o && authorized, "fixture: no key, owner payee and authority");
        vm.deal(o, 0);
    }

    function _today() internal view returns (uint24) {
        return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }

    function _warpToDay(uint24 d) internal {
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
        coin.mintForGame(p, amount);
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
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(day >> 3), STAKE_ROOT))));
        return uint32(uint256(vm.load(address(coinflip), slot)) >> ((uint256(day) & 7) * 32));
    }

    /// @dev A live, non-deity coinflip boon of `tier` stamped today for wallet `id`.
    function _seedCoinflipBoon(uint32 id, uint8 tier) internal {
        bytes32 s = GameSlotKeys.byId(id, GameSlots.BOON_PACKED);
        uint256 v = uint256(vm.load(address(game), s));
        v &= ~((uint256(0xFF) << COINFLIP_TIER_SHIFT) | uint256(0xFFFFFFFFFFFF));
        v |= (uint256(tier) << COINFLIP_TIER_SHIFT) | uint256(game.currentDayView());
        vm.store(address(game), s, bytes32(v));
        require(_coinflipBoonTier(id) == tier, "fixture: coinflip boon lane");
    }

    function _coinflipBoonTier(uint32 id) internal view returns (uint256) {
        (uint256 slot0,) = game.boonPacked(id);
        return (slot0 >> COINFLIP_TIER_SHIFT) & 0xFF;
    }

    /// @dev Give S settled winnings in its own Coinflip state: a credited stake wins and the owner's
    ///      zero-amount settle banks it into `claimableStored`. Returns the banked amount.
    function _bankSmurfWinnings(uint256 credit) internal returns (uint256 bank) {
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip(smurfId, credit);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, 0);
        bank = _claimableStored(smurfId);
        require(bank > 0, "fixture: smurf winnings banked");
    }

    /// @dev Leave S an unsettled losing day (stake credited, then resolved as a loss).
    function _pendingSmurfLoss() internal {
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip(smurfId, 300);
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
    //                 1. owner deposits for its smurf (direct)
    // =====================================================================

    /// @notice O's deposit for S spends S's settled winnings first and burns O's wallet FLIP for the
    ///         rest; the stake is S's, the quest is S's, and the deposit is direct: S's coinflip boon
    ///         is spent and, on the armed day, the BAF draw entry carries S. Events name S's key.
    function test_OwnerDepositForSmurf_ClaimableFirstThenOwnerWallet_Direct() public {
        uint256 bank = _bankSmurfWinnings(400);
        uint256 amount = bank + 1_000;
        _fundFlip(owner, 5_000);
        _seedCoinflipBoon(smurfId, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);
        uint256 laneBefore = _lane(target, smurfId);
        uint256 ownerLaneBefore = _lane(target, ownerId);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, owner)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (smurfId, amount)), 1);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.consumeCoinflipBoon, (smurfId)), 1);
        vm.expectCall(address(coin), abi.encodeWithSignature("burnForCoinflip(address,uint256)", owner, 1_000), 1);
        vm.recordLogs();
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_claimableStored(smurfId), 0, "the smurf's winnings funded the stake first");
        assertEq(coin.balanceOf(owner), 4_000, "the owner's wallet paid only the remainder");
        assertGe(_lane(target, smurfId) - laneBefore, amount + amount / 4, "stake on S with the 25% boon");
        assertEq(_lane(target, ownerId), ownerLaneBefore, "nothing staked on the owner's lane");
        assertEq(_coinflipBoonTier(smurfId), 0, "the smurf's coinflip boon was spent");

        (uint24 day, uint96 total, uint32 count) = coinflip.bafDrawInfo();
        assertEq(day, target);
        assertEq(count, 1, "the direct deposit entered the BAF draw");
        assertEq(total, amount, "draw weight is the raw principal");
        (uint32 eid,) = coinflip.bafDrawEntryAt(target, 0);
        assertEq(eid, smurfId, "the draw entry carries S");
        assertEq(_countFor(logs, address(coinflip), BAF_DRAW_ENTERED, bytes32(uint256(target))), 1);
        assertEq(_countFor(logs, address(coinflip), DEPOSIT, bytes32(uint256(_fixtureId(smurfId)))), 1, "CoinflipDeposit names S's key");
        assertEq(_countFor(logs, address(coinflip), CLAIM_STATE, bytes32(uint256(smurfId))), 1, "claim state names S's key");
        assertEq(_countFor(logs, address(coinflip), DEPOSIT, bytes32(uint256(_fixtureId(owner)))), 0);
    }

    /// @notice O's deposit for S can set the flip record: the record and its claim accrue to S, the
    ///         trophy and the sDGNRS leg go to O (the payee), never to S's key.
    function test_OwnerDepositForSmurf_ArmsFlipRecord_TrophyToOwner() public {
        _fundFlip(owner, 300_000);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.payRecordSdgnrs.selector, smurfId), 1);
        vm.recordLogs();
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, 200_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coinflip.biggestFlipEver(), 200_000, "the direct deposit set the record");
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != BIG_RECORD) continue;
            assertEq(uint8(uint256(logs[i].topics[1])), RECORD_KIND_FLIP);
            assertEq(uint32(uint256(logs[i].topics[2])), smurfId, "the record accrues to S");
            seen = true;
        }
        assertTrue(seen, "BigRecordUpdated emitted");
        assertEq(recordBounty.ownerOf(RECORD_KIND_FLIP), owner, "trophy to the payee");
    }

    /// @notice A completed quest on an authorized deposit names the account key and its reward joins
    ///         the account's stake; on a gift it names the funding caller.
    function test_QuestCompleted_NamesAccountKey_OrGiftFunder() public {
        uint24 target = _today() + 1;
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(DegenerusQuests.handleFlip.selector, smurfId),
            abi.encode(uint256(50), uint8(2), uint32(1), true)
        );
        _fundFlip(owner, 10_000);
        uint256 before = _lane(target, smurfId);
        vm.recordLogs();
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, 1_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(coinflip), QUEST_COMPLETED, bytes32(uint256(_fixtureId(smurfId)))), 1, "quest names S's key");
        assertEq(_countFor(logs, address(coinflip), QUEST_COMPLETED, bytes32(uint256(_fixtureId(owner)))), 0);
        assertEq(_lane(target, smurfId) - before, 1_050, "quest reward joins S's stake");

        uint32 funderId = uint32(_walletCount());
        vm.mockCall(
            address(quests),
            abi.encodeWithSelector(DegenerusQuests.handleFlip.selector, funderId),
            abi.encode(uint256(70), uint8(2), uint32(1), true)
        );
        _fundFlip(stranger, 10_000);
        before = _lane(target, smurfId);
        vm.recordLogs();
        vm.prank(stranger);
        coinflip.depositCoinflip(smurfId, 1_000);
        logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(coinflip), QUEST_COMPLETED, bytes32(uint256(_fixtureId(stranger)))), 1, "a gift's quest names the funder");
        assertEq(_countFor(logs, address(coinflip), QUEST_COMPLETED, bytes32(uint256(_fixtureId(smurfId)))), 0);
        assertEq(_lane(target, smurfId) - before, 1_070, "the funder's quest reward joins S's stake");
        assertEq(_gameId(stranger), funderId);
    }

    // =====================================================================
    //                       2. a stranger's gift to S
    // =====================================================================

    /// @notice X's deposit for S is a gift: X's FLIP pays the whole principal, S's banked winnings
    ///         stay put, X registers and earns the quest, the stake is S's, and nothing direct
    ///         happens (no boon, no draw entry, no record). S's pending loss mints WWXRP to O.
    function test_StrangerGiftToSmurf_FunderPays_NotDirect_LossWwxrpToOwner() public {
        uint256 bank = _bankSmurfWinnings(400);
        _pendingSmurfLoss();
        _seedCoinflipBoon(smurfId, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);
        _fundFlip(stranger, 300_000);
        uint32 funderId = uint32(_walletCount());
        uint256 laneBefore = _lane(target, smurfId);
        uint256 ownerFlip = coin.balanceOf(owner);
        uint256 ownerWwxrp = wwxrp.claimable(smurfId);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, stranger)), 1);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.registerWallet, (stranger, true)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (funderId, 250_000)), 1);
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.handleFlip.selector, smurfId), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.consumeCoinflipBoon.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.payRecordSdgnrs.selector), 0);
        vm.prank(stranger);
        coinflip.depositCoinflip(smurfId, 250_000);

        assertEq(coin.balanceOf(stranger), 50_000, "the funder paid the whole principal");
        assertEq(coin.balanceOf(owner), ownerFlip, "the owner's wallet is untouched");
        assertEq(_claimableStored(smurfId), bank, "a gift never spends the account's winnings");
        assertEq(_lane(target, smurfId) - laneBefore, 250_000, "stake on S, no boon, no bonus");
        assertEq(_coinflipBoonTier(smurfId), 3, "S's coinflip boon kept");
        (,, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0, "a gift carries no draw weight");
        assertEq(coinflip.biggestFlipEver(), 0, "a gift cannot set the record");
        assertGt(wwxrp.claimable(smurfId), ownerWwxrp, "S's loss consolation went to O");
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

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (aid, operator)), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (aid, 250_000)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.consumeCoinflipBoon.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.payRecordSdgnrs.selector), 0);
        vm.prank(operator);
        coinflip.depositCoinflip(aid, 250_000);

        assertEq(coin.balanceOf(a), 50_000, "the account's FLIP paid");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_gameId(operator), 0, "the operator never registers");
        assertEq(_lane(target, aid), 250_000, "stake on A, no boon");
        assertEq(_coinflipBoonTier(aid), 3);
        (,, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0, "an operator deposit carries no draw weight");
        assertEq(coinflip.biggestFlipEver(), 0, "an operator deposit cannot set the record");
    }

    /// @notice P's deposit for S burns O's FLIP (the payee), quests as S, and is not direct.
    function test_OperatorDepositForSmurf_BurnsOwnerFlip_NotDirect() public {
        _fundFlip(owner, 300_000);
        _seedCoinflipBoon(smurfId, 3);
        uint24 target = _today() + 1;
        vm.prank(GAME);
        coinflip.armBafDraw(target);
        uint256 laneBefore = _lane(target, smurfId);

        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, operator)), 1);
        vm.expectCall(address(coin), abi.encodeWithSignature("burnForCoinflip(address,uint256)", owner, 250_000), 1);
        vm.expectCall(address(quests), abi.encodeCall(DegenerusQuests.handleFlip, (smurfId, 250_000)), 1);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.consumeCoinflipBoon.selector), 0);
        vm.prank(operator);
        coinflip.depositCoinflip(smurfId, 250_000);

        assertEq(coin.balanceOf(owner), 50_000, "the smurf's payee paid");
        assertEq(coin.balanceOf(operator), 0);
        assertEq(_lane(target, smurfId) - laneBefore, 250_000);
        assertEq(_coinflipBoonTier(smurfId), 3);
        (,, uint32 count) = coinflip.bafDrawInfo();
        assertEq(count, 0);
        assertEq(coinflip.biggestFlipEver(), 0);
    }

    // =====================================================================
    //                            4. edge reverts
    // =====================================================================

    /// @notice An unallocated ID reverts the Game's E for any caller; a new wallet's self deposit
    ///         allocates, and past paid admission it reverts E; deposits for S still work there.
    function test_UnallocatedId_E_SelfAllocates_PastAdmissionE() public {
        _fundFlip(stranger, 10_000);
        _fundFlip(owner, 10_000);
        uint32 unallocated = uint32(_walletCount());
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(stranger);
        coinflip.depositCoinflip(unallocated, 1_000);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(owner);
        coinflip.depositCoinflip(unallocated, 1_000);
        assertEq(coin.balanceOf(stranger), 10_000);

        address fresh = makeAddr("cfa_fresh");
        _fundFlip(fresh, 10_000);
        uint32 expected = uint32(_walletCount());
        vm.prank(fresh);
        coinflip.depositCoinflip(0, 1_000);
        assertEq(_gameId(fresh), expected, "a paid self deposit allocates");

        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(PAST_PAID_ADMISSION));
        address late = makeAddr("cfa_late");
        _fundFlip(late, 10_000);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(late);
        coinflip.depositCoinflip(0, 1_000);
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, 1_000);
        assertEq(coin.balanceOf(owner), 9_000, "the owner still deposits for S past admission");
    }

    /// @notice A zero-amount gift by X settles S's resolved days into S's state, mints nothing to X,
    ///         registers nobody, and S's loss consolation goes to O.
    function test_ZeroAmountGift_SettlesSmurf_MintsNothingToCaller() public {
        uint24 d = _today();
        vm.prank(GAME);
        coinflip.creditFlip(smurfId, 400);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        uint256 payout = coinflip.previewClaimCoinflipsById(_fixtureId(smurfId));
        assertGt(payout, 0);
        vm.prank(GAME);
        coinflip.creditFlip(smurfId, 300);
        _warpToDay(d + 2);
        _resolveDay(d + 2, false);
        uint256 ownerWwxrp = wwxrp.claimable(smurfId);

        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.handleFlip.selector), 0);
        vm.prank(stranger);
        coinflip.depositCoinflip(smurfId, 0);

        assertEq(_claimableStored(smurfId), payout, "S's win settled into S's state");
        assertEq(_lastClaim(smurfId), d + 2, "both days walked");
        assertEq(coin.balanceOf(stranger), 0, "nothing minted to the caller");
        assertEq(wwxrp.balanceOf(stranger), 0);
        assertGt(wwxrp.claimable(smurfId), ownerWwxrp, "the loss consolation went to O");
        assertEq(_gameId(stranger), 0, "a zero-amount gift registers nobody");
    }

    // =====================================================================
    //                 5. the Game's zero-amount vault settle
    // =====================================================================

    function _gameSettlesVault() internal {
        uint24 d = _today();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (uint32(1), GAME)), 1);
        vm.expectCall(address(coin), abi.encodeWithSignature("burnForCoinflip(address,uint256)"), 0);
        vm.expectCall(address(quests), abi.encodeWithSelector(DegenerusQuests.handleFlip.selector), 0);
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.registerWallet.selector), 0);
        vm.prank(GAME);
        coinflip.depositCoinflip(1, 0);
        assertEq(_lastClaim(VAULT), d + 1, "the vault's days settled");
        assertGt(_claimableStored(VAULT), 0, "the vault's seed win banked in its own state");
    }

    /// @notice `depositCoinflip(1, 0)` from GAME with no approval is a zero-amount gift: it settles
    ///         the vault's days with no burn and no quest call, and never reverts.
    function test_GameSettlesVault_WithoutApproval() public {
        (address key, address payee, bool authorized) = game.resolveAccount(1, GAME);
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
        (,, bool authorized) = game.resolveAccount(1, GAME);
        assertTrue(authorized, "the vault approved GAME");
        _gameSettlesVault();
    }

    /// @notice Pinned through the real advance: the x0 seal arms the BAF draw and settles the vault
    ///         with `depositCoinflip(1, 0)` in one frame, and the game passes level 10.
    function test_X0Seal_SettlesVault_RealAdvance_WithoutApproval() public {
        _driveThroughX0Seal();
    }

    function test_X0Seal_SettlesVault_RealAdvance_WithApproval() public {
        vm.prank(VAULT);
        game.setOperatorApproval(0, GAME, true);
        _driveThroughX0Seal();
    }

    function _driveThroughX0Seal() internal {
        vm.expectCall(address(coinflip), abi.encodeCall(Coinflip.depositCoinflip, (uint32(1), uint256(0))));
        address buyer = makeAddr("cfa_x0_buyer");
        vm.deal(buyer, 100_000 ether);
        vm.deal(address(game), 2_000 ether);
        uint256 t = block.timestamp;
        for (uint256 day; day < 600 && game.level() < 10; ++day) {
            t += 1 days + 1;
            vm.warp(t);
            _seedPools(49.9 ether, 100 ether);
            _buyTickets(buyer, 4_000);
            for (uint256 j; j < 80; ++j) {
                _fulfillVrf();
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip()"));
                if (!ok) break;
            }
        }
        assertGe(game.level(), 10, "the game passed the x0 seal");
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
        (,,, bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        vm.prank(who);
        try game.purchase{value: cost}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrf() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(keccak256(abi.encode("cfa_x0_word", block.timestamp, game.level(), reqId)));
        if (word == 0) word = 2;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    // =====================================================================
    //                    6. claims and settings for S
    // =====================================================================

    /// @notice X may not claim or configure S (`NotApproved`); O's and P's claims for S mint to O and
    ///         the claim state is S's (event names S's key).
    function test_SmurfClaims_OwnerAndOperatorMintToOwner_StrangerNotApproved() public {
        uint24 d = _today();
        _fundFlip(owner, 10_000);
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, 1_000);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);

        vm.startPrank(stranger);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.claimCoinflips(smurfId, type(uint256).max);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.claimCoinflipCarry(smurfId, 1);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(smurfId, true, 0);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(smurfId, false, 0);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.setCoinflipAutoRebuyTakeProfit(smurfId, 0);
        vm.stopPrank();

        uint256 preview = coinflip.previewClaimCoinflipsById(_fixtureId(smurfId));
        assertGt(preview, 0);
        uint256 ownerBefore = coin.balanceOf(owner);
        vm.expectCall(GAME, abi.encodeCall(DegenerusGame.resolveAccount, (smurfId, owner)), 1);
        vm.recordLogs();
        vm.prank(owner);
        uint256 got = coinflip.claimCoinflips(smurfId, type(uint256).max);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(got, preview);
        assertEq(coin.balanceOf(owner) - ownerBefore, got, "O's claim for S minted to O");
        assertEq(_countFor(logs, address(coinflip), CLAIM_STATE, bytes32(uint256(smurfId))), 1, "claim state names S's key");
        assertEq(_countFor(logs, address(coinflip), CLAIM_STATE, bytes32(uint256(_gameId(owner)))), 0);

        vm.prank(operator);
        coinflip.depositCoinflip(smurfId, 1_000);
        _warpToDay(d + 2);
        _resolveDay(d + 2, true);
        preview = coinflip.previewClaimCoinflipsById(_fixtureId(smurfId));
        assertGt(preview, 0);
        ownerBefore = coin.balanceOf(owner);
        vm.prank(operator);
        got = coinflip.claimCoinflips(smurfId, type(uint256).max);
        assertEq(got, preview);
        assertEq(coin.balanceOf(owner) - ownerBefore, got, "P's claim for S minted to O");
        assertEq(coin.balanceOf(operator), 0, "nothing to the operator");
    }

    /// @notice Auto-rebuy and the carry live in S's own Coinflip state; P's carry claim, P's
    ///         take-profit and O's disable all act on S's key and every mint goes to O.
    function test_SmurfAutoRebuyAndCarry_StateOnSmurfKey_PaysOwner() public {
        vm.recordLogs();
        vm.prank(owner);
        coinflip.setCoinflipAutoRebuy(smurfId, true, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(coinflip), TOGGLED, bytes32(uint256(smurfId))), 1, "toggle names the subaccount ID");
        assertEq(_countFor(logs, address(coinflip), STOP_SET, bytes32(uint256(_fixtureId(smurfId)))), 1);
        (bool enabled,,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(smurfId));
        assertTrue(enabled, "S's state armed");
        (enabled,,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(owner));
        assertFalse(enabled, "O's own state untouched");

        uint24 d = _today();
        _fundFlip(owner, 10_000);
        vm.prank(owner);
        coinflip.depositCoinflip(smurfId, 1_000);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);

        uint256 ownerBefore = coin.balanceOf(owner);
        vm.prank(operator);
        uint256 claimed = coinflip.claimCoinflipCarry(smurfId, type(uint256).max);
        assertGt(claimed, 1_000, "the winning carry paid out");
        assertEq(coin.balanceOf(owner) - ownerBefore, claimed, "carry minted to O");
        assertEq(coin.balanceOf(operator), 0);
        (,, uint256 carry,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(smurfId));
        assertEq(carry, 0);

        vm.prank(operator);
        coinflip.setCoinflipAutoRebuyTakeProfit(smurfId, 500);
        (, uint256 stop,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(smurfId));
        assertEq(stop, 500, "take profit on S's state");

        vm.recordLogs();
        vm.prank(owner);
        coinflip.setCoinflipAutoRebuy(smurfId, false, 0);
        logs = vm.getRecordedLogs();
        assertEq(_countFor(logs, address(coinflip), TOGGLED, bytes32(uint256(_fixtureId(smurfId)))), 1);
        (enabled,,,) = coinflip.coinflipAutoRebuyInfoById(_fixtureId(smurfId));
        assertFalse(enabled);
    }

    // =====================================================================
    //                    7. no GAME branch; enable precedence
    // =====================================================================

    /// @notice GAME has no auto-rebuy branch: with a nonzero ID it is an unauthorized caller.
    ///         Re-enabling reverts AutoRebuyAlreadyEnabled; once the flip is frozen RngLocked wins.
    function test_SetAutoRebuy_NoGameBranch_AlreadyEnabled_RngLockedFirst() public {
        vm.startPrank(GAME);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(1, true, 0);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(smurfId, true, 0);
        vm.expectRevert(Coinflip.NotApproved.selector);
        coinflip.setCoinflipAutoRebuy(ownerId, false, 0);
        vm.stopPrank();

        uint24 d = _today();
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.prank(owner);
        coinflip.setCoinflipAutoRebuy(smurfId, true, 0);
        vm.expectRevert(Coinflip.AutoRebuyAlreadyEnabled.selector);
        vm.prank(owner);
        coinflip.setCoinflipAutoRebuy(smurfId, true, 0);

        _warpToDay(d + 2);
        assertFalse(coinflip.flipResolvedToday(), "today's flip unresolved");
        vm.expectRevert(Coinflip.RngLocked.selector);
        vm.prank(owner);
        coinflip.setCoinflipAutoRebuy(smurfId, true, 0);
        vm.expectRevert(Coinflip.RngLocked.selector);
        vm.prank(operator);
        coinflip.setCoinflipAutoRebuy(smurfId, false, 0);
    }

    // =====================================================================
    //                       8. self paths
    // =====================================================================




    /// @notice Self actions (`id == 0`) on every Coinflip door make no Game `resolveAccount` call.
    function test_SelfPaths_MakeNoResolveAccountCall() public {
        address p = makeAddr("cfa_self");
        _fundFlip(p, 10_000);
        uint24 d = _today();
        vm.expectCall(GAME, abi.encodeWithSelector(DegenerusGame.resolveAccount.selector), 0);
        vm.prank(p);
        coinflip.depositCoinflip(0, 1_000);
        _warpToDay(d + 1);
        _resolveDay(d + 1, true);
        vm.startPrank(p);
        coinflip.claimCoinflips(0, type(uint256).max);
        coinflip.setCoinflipAutoRebuy(0, true, 0);
        coinflip.setCoinflipAutoRebuyTakeProfit(0, 5);
        coinflip.claimCoinflipCarry(0, 1);
        coinflip.setCoinflipAutoRebuy(0, false, 0);
        coinflip.depositCoinflip(0, 0);
        vm.stopPrank();
        assertGt(coin.balanceOf(p), 9_000, "the self win paid the caller");
    }
}
