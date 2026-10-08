// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title AccountRuleGame -- the Game side of the account rule (acting by wallet ID, smurfs)
/// @notice Decisions G0-G3, G8 and hazard H-F3 against the real protocol:
///         - `resolveAccount` answers (key, payee, authorized) for keys, smurf owners, operators
///           approved on the exact ID, and strangers, and reverts `E` only for 0/unallocated IDs;
///         - `setOperatorApproval` stores approvals by account ID, only the key (or a smurf's owner)
///           manages them, and the event carries the ID;
///         - acting for a smurf: state follows the smurf, value out goes to the owner, the caller's
///           fresh ETH pays and its overpay credits the caller's ID, FLIP burns from the owner;
///         - AFKing funding by ID: an own-ID source is self-funding, accounts sharing a main
///           wallet fund each other without approval, an unrelated source must approve the
///           subscriber's key;
///         - the batch doors map an element 0 to the caller before their isolating self-calls.
contract AccountRuleGame is DeployProtocol {
    /// @dev Coinflip.playerState root and flipsClaimableDay slot (scripts/layout/golden/Coinflip.json).
    uint256 private constant CF_PLAYER_STATE_ROOT = 2;
    uint256 private constant CF_CLAIMABLE_DAY_SLOT = 4;
    uint8 private constant FLAG_EXTERNAL_FUNDING = 1;

    error E();
    error NotApproved();
    error ZeroAddress();
    error StaleBatch();

    event OperatorApproval(uint32 indexed id, address indexed operator, bool approved);
    event EntriesBought(uint32 indexed buyer, uint256 entryQuantityScaled, uint256 weiIn);
    event LootBoxBuy(uint32 indexed buyer, uint48 indexed index, uint32 position, uint256 amount);
    event WinningsClaimed(uint32 indexed player, uint256 amount, uint128 claimableAfter);
    event AfkingWithdrew(uint32 indexed player, uint256 amount);
    event SubscriptionUpdated(
        uint32 indexed player, uint8 dailyQuantity, bool drainGameCreditFirst, bool useTickets,
        uint32 indexed fundingSource
    );

    address private owner;
    address private operator;
    address private stranger;
    address private wallet; // an ordinary registered wallet unrelated to the owner
    address private source; // an unrelated funding source
    uint32 private ownerId;
    uint32 private walletId;
    uint32 private sourceId;
    uint32 private smurfId;
    uint256 private price;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 1_000 ether);
        owner = makeAddr("acct_owner");
        operator = makeAddr("acct_operator");
        stranger = makeAddr("acct_stranger");
        wallet = makeAddr("acct_wallet");
        source = makeAddr("acct_source");
        vm.deal(owner, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(stranger, 100 ether);
        vm.deal(wallet, 100 ether);
        vm.deal(source, 100 ether);
        price = game.mintPrice();
        mockVRF.fundSubscription(1, 1_000 ether);

        _buyTicket(owner);
        _buyTicket(wallet);
        ownerId = game.walletIdOf(owner);
        walletId = game.walletIdOf(wallet);
        sourceId = _giveWalletId(source);
        _grantSmurfBase(owner, 2);
        (smurfId,) = _createSmurf();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------



    function _buyTicket(address who) private {
        vm.prank(who);
        game.purchase{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _createSmurf() private returns (uint32 id, uint32 key) {
        vm.prank(owner);
        id = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        key = id;
    }

    function _walletsLength() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _approvalSlot(uint32 id, address op) private pure returns (bytes32) {
        return keccak256(abi.encode(op, keccak256(abi.encode(uint256(id), GameSlots.OPERATOR_APPROVALS))));
    }

    function _approve(address by, uint32 id, address op) private {
        vm.prank(by);
        game.setOperatorApproval(id, op, true);
    }

    function _seedClaimable(uint32 id, uint256 amount) private {
        bytes32 slot = GameSlotKeys.balances(id);
        uint256 w = uint256(vm.load(address(game), slot));
        uint256 old = uint128(w);
        vm.store(address(game), slot, bytes32(((w >> 128) << 128) | amount));
        bytes32 poolSlot = bytes32(GameSlots.CLAIMABLE_POOL);
        uint256 p = uint256(vm.load(address(game), poolSlot));
        uint256 pool = (p >> 128) + amount - old;
        vm.store(address(game), poolSlot, bytes32((pool << 128) | uint128(p)));
    }

    function _fundAfking(uint32 id, uint256 amount) private {
        vm.deal(address(this), address(this).balance + amount);
        game.depositAfkingFunding{value: amount}(id);
    }

    function _subWord(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.byId(id, GameSlots.SUB_OF)));
    }

    function _fundingSourceWord(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.byId(id, GameSlots.FUNDING_SOURCE_OF)));
    }

    function _flip(address who, uint256 amount) private {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    /// @dev Open the FLIP redemption window: the next pool clears the level-1 target.
    function _openRedemptionWindow() private {
        bytes32 slot = bytes32(GameSlots.PRIZE_POOLS_PACKED);
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(((packed >> 128) << 128) | 1_000 ether));
    }

    // =====================================================================
    // 1. resolveAccount
    // =====================================================================

    function test_ResolveAccount_ZeroAndUnallocatedRevertE() public {
        vm.expectRevert(E.selector);
        game.resolveAccount(0, owner);
        uint32 next = uint32(_walletsLength());
        vm.expectRevert(E.selector);
        game.resolveAccount(next, owner);
    }

    function test_ResolveAccount_KeyAsCaller() public view {
        (address key, address payee, bool ok) = game.resolveAccount(ownerId, owner);
        assertEq(key, owner);
        assertEq(payee, owner);
        assertTrue(ok);
    }

    function test_ResolveAccount_SmurfOwner() public view {
        (address key, address payee, bool ok) = game.resolveAccount(smurfId, owner);
        assertEq(key, address(0));
        assertEq(payee, owner);
        assertTrue(ok);
    }

    function test_ResolveAccount_OperatorOnSmurf_PayeeIsOwner() public {
        _approve(owner, smurfId, operator);
        (address key, address payee, bool ok) = game.resolveAccount(smurfId, operator);
        assertEq(key, address(0));
        assertEq(payee, owner, "an operator acts for the smurf, value still goes to the owner");
        assertTrue(ok);
    }

    function test_ResolveAccount_OwnerIdOperatorNotForSmurf() public {
        _approve(owner, 0, operator); // approved on the OWNER's ID
        (, , bool onOwner) = game.resolveAccount(ownerId, operator);
        (address key, address payee, bool onSmurf) = game.resolveAccount(smurfId, operator);
        assertTrue(onOwner, "authorized for the owner's account");
        assertFalse(onSmurf, "not for the smurf: approvals are per account ID");
        assertEq(key, address(0));
        assertEq(payee, owner);
    }

    function test_ResolveAccount_StrangerFalseNoRevert() public view {
        (address k1, address p1, bool ok1) = game.resolveAccount(ownerId, stranger);
        (address k2, address p2, bool ok2) = game.resolveAccount(smurfId, stranger);
        (, , bool ok3) = game.resolveAccount(smurfId, wallet);
        assertEq(k1, owner);
        assertEq(p1, owner);
        assertFalse(ok1);
        assertEq(k2, address(0));
        assertEq(p2, owner);
        assertFalse(ok2);
        assertFalse(ok3, "another registered wallet is a stranger too");
    }

    // =====================================================================
    // 2. setOperatorApproval
    // =====================================================================

    function test_SetOperatorApproval_ZeroIdWithoutIdRevertsE() public {
        vm.prank(stranger);
        vm.expectRevert(E.selector);
        game.setOperatorApproval(0, operator, true);
    }

    function test_SetOperatorApproval_ZeroIdStoresForOwnId() public {
        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(ownerId, operator, true);
        _approve(owner, 0, operator);
        assertEq(uint256(vm.load(address(game), _approvalSlot(ownerId, operator))), 1, "operatorApprovals[ownId][op]");
        (, , bool ok) = game.resolveAccount(ownerId, operator);
        assertTrue(ok);

        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(ownerId, operator, false);
        vm.prank(owner);
        game.setOperatorApproval(0, operator, false);
        (, , ok) = game.resolveAccount(ownerId, operator);
        assertFalse(ok, "revoked");
    }

    function test_SetOperatorApproval_OwnerManagesSmurf() public {
        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(smurfId, operator, true);
        _approve(owner, smurfId, operator);
        assertEq(uint256(vm.load(address(game), _approvalSlot(smurfId, operator))), 1, "stored under the smurf ID");
        assertEq(uint256(vm.load(address(game), _approvalSlot(ownerId, operator))), 0, "not under the owner's");
        (, address payee, bool ok) = game.resolveAccount(smurfId, operator);
        assertTrue(ok);
        assertEq(payee, owner);

        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, false);
        (, , ok) = game.resolveAccount(smurfId, operator);
        assertFalse(ok);
    }

    function test_SetOperatorApproval_OperatorCannotApprove() public {
        _approve(owner, smurfId, operator);
        _approve(owner, 0, operator);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.setOperatorApproval(smurfId, stranger, true);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.setOperatorApproval(ownerId, stranger, true);
    }

    function test_SetOperatorApproval_NonOwnerNotApproved() public {
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.setOperatorApproval(ownerId, stranger, true);
        vm.prank(wallet);
        vm.expectRevert(NotApproved.selector);
        game.setOperatorApproval(smurfId, wallet, true);
        uint32 next = uint32(_walletsLength());
        vm.prank(owner);
        vm.expectRevert(E.selector);
        game.setOperatorApproval(next, operator, true);
    }

    function test_SetOperatorApproval_ZeroOperatorRevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        game.setOperatorApproval(0, address(0), true);
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        game.setOperatorApproval(smurfId, address(0), true);
    }

    // =====================================================================
    // 4. Acting on behalf of a smurf
    // =====================================================================

    /// @notice The owner buys for its smurf: tickets and boxes are the smurf's, the owner's fresh ETH
    ///         pays, and the overpay credits the caller's (owner's) ID.
    function test_OwnerPurchaseForSmurf_ToSmurf_EthAndOverpayOwner() public {
        uint256 box = 0.02 ether;
        uint256 extra = 0.3 ether;
        uint256 ethBefore = owner.balance;
        uint256 ownerAfk = _fixtureAfking(owner);
        uint32 smurfOwed = _fixtureEntries(1, smurfId);
        uint32 ownerOwed = _fixtureEntries(1, owner);

        vm.expectEmit(true, false, false, true, address(game));
        emit EntriesBought(_fixtureId(smurfId), 400, price);
        vm.expectEmit(true, false, false, false, address(game));
        emit LootBoxBuy(_fixtureId(smurfId), 0, 0, 0);
        vm.prank(owner);
        game.purchase{value: price + box + extra}(
            smurfId, 400, BoxOrderLib.boCustom(box), bytes32(0), MintPaymentKind.DirectEth, false
        );

        assertEq(owner.balance, ethBefore - price - box - extra, "the owner's ETH paid");
        assertGt(_fixtureEntries(1, smurfId), smurfOwed, "tickets to the smurf");
        assertEq(_fixtureEntries(1, owner), ownerOwed, "none to the owner");
        assertEq(_fixtureAfking(owner), ownerAfk + extra, "overpay to the paying owner's ID");
        assertEq(_fixtureAfking(smurfId), 0, "nothing to the smurf");
    }

    /// @notice A Claimable buy for the smurf spends the smurf's own ledger, not the owner's.
    function test_OwnerPurchaseForSmurf_ClaimableFromSmurfLedger() public {
        _seedClaimable(smurfId, 1 ether);
        _seedClaimable(ownerId, 1 ether);
        vm.prank(owner);
        game.purchase(smurfId, 400, 0, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(_fixtureClaimable(smurfId), 1 ether - price, "the smurf's claimable spent");
        assertEq(_fixtureClaimable(owner), 1 ether, "the owner's untouched");
    }

    function test_StrangerPurchaseForSmurf_NotApproved() public {
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.purchase{value: price}(smurfId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.purchase{value: price}(ownerId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        // An operator of the owner's ID is a stranger to the smurf.
        _approve(owner, 0, operator);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.purchase{value: price}(smurfId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @notice An operator approved on the smurf buys for it with its own ETH. Overpay credits the
    ///         paying caller's ID (`_payerId`), so an operator without an ID cannot overpay.
    function test_OperatorPurchaseForSmurf() public {
        _approve(owner, smurfId, operator);
        uint32 smurfOwed = _fixtureEntries(1, smurfId);
        uint256 opEth = operator.balance;
        vm.prank(operator);
        game.purchase{value: price}(smurfId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(operator.balance, opEth - price, "the operator's ETH paid");
        assertGt(_fixtureEntries(1, smurfId), smurfOwed, "tickets to the smurf");

        vm.prank(operator);
        vm.expectRevert(E.selector);
        game.purchase{value: price + 1 ether}(smurfId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        uint32 opId = _giveWalletId(operator);
        uint256 ownerAfk = _fixtureAfking(owner);
        vm.prank(operator);
        game.purchase{value: price + 1 ether}(smurfId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_fixtureAfking(operator), 1 ether, "overpay to the paying operator's ID");
        assertEq(_fixtureAfking(owner), ownerAfk, "not the owner's");
        assertEq(_fixtureAfking(smurfId), 0, "not the smurf's");
        assertTrue(opId != 0);
    }

    /// @notice redeemFlip for the smurf burns the OWNER's wallet FLIP; the smurf gets the tickets.
    function test_RedeemFlipForSmurf_BurnsOwnerFlip() public {
        _openRedemptionWindow();
        _flip(owner, 10_000);
        uint256 ownerFlip = coin.balanceOf(owner);
        uint32 smurfOwed = _fixtureEntries(1, smurfId);
        vm.prank(owner);
        game.redeemFlip(smurfId, 400);
        assertEq(ownerFlip - coin.balanceOf(owner), 1_000, "one ticket's FLIP burned from the owner");
        assertGt(_fixtureEntries(1, smurfId), smurfOwed, "tickets to the smurf");
    }

    /// @notice A wallet shortfall comes from the OWNER's settled coinflip winnings, never the smurf's.
    function test_RedeemFlipForSmurf_ShortfallFromOwnerCoinflipClaimable() public {
        _openRedemptionWindow();
        _flip(owner, 400);
        bytes32 ownerState = keccak256(abi.encode(ownerId, CF_PLAYER_STATE_ROOT));
        bytes32 smurfState = keccak256(abi.encode(smurfId, CF_PLAYER_STATE_ROOT));
        uint256 latest = uint24(uint256(vm.load(address(coinflip), bytes32(CF_CLAIMABLE_DAY_SLOT))));
        // claimableStored = 5,000 whole FLIP, lastClaim = flipsClaimableDay (no walk to settle).
        vm.store(address(coinflip), ownerState, bytes32((latest << 128) | 5_000));
        vm.store(address(coinflip), smurfState, bytes32((latest << 128) | 7_000));

        vm.prank(owner);
        game.redeemFlip(smurfId, 400);

        assertEq(coin.balanceOf(owner), 0, "the owner's wallet FLIP burned first");
        assertEq(uint128(uint256(vm.load(address(coinflip), ownerState))), 5_000 - 600,
            "the owner's coinflip winnings cover the shortfall");
        assertEq(uint128(uint256(vm.load(address(coinflip), smurfState))), 7_000, "the smurf's untouched");
    }

    function test_StrangerRedeemFlipForSmurf_NotApproved() public {
        _openRedemptionWindow();
        _flip(stranger, 10_000);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.redeemFlip(smurfId, 400);
    }

    /// @notice claimWinnings for the smurf, by the owner or its operator, pays the owner.
    function test_ClaimWinningsForSmurf_PaysOwner() public {
        _seedClaimable(smurfId, 1 ether);
        uint256 ownerEth = owner.balance;
        vm.expectEmit(true, false, false, true, address(game));
        emit WinningsClaimed(_fixtureId(smurfId), 1 ether - 1, 1);
        vm.prank(owner);
        game.claimWinnings(smurfId);
        assertEq(owner.balance, ownerEth + 1 ether - 1, "paid to the owner");
        assertEq(_fixtureClaimable(smurfId), 1, "the smurf's ledger debited to the sentinel");

        _approve(owner, smurfId, operator);
        _seedClaimable(smurfId, 1 ether);
        ownerEth = owner.balance;
        uint256 opEth = operator.balance;
        vm.prank(operator);
        game.claimWinnings(smurfId, 0.2 ether);
        assertEq(owner.balance, ownerEth + 0.2 ether, "an operator's claim pays the owner");
        assertEq(operator.balance, opEth, "never the operator");
    }

    /// @notice withdrawAfkingFunding for the smurf, by the owner or its operator, pays the owner.
    function test_WithdrawAfkingForSmurf_PaysOwner() public {
        _fundAfking(smurfId, 1 ether);
        uint256 ownerEth = owner.balance;
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingWithdrew(_fixtureId(smurfId), 0.4 ether);
        vm.prank(owner);
        game.withdrawAfkingFunding(smurfId, 0.4 ether);
        assertEq(owner.balance, ownerEth + 0.4 ether);

        _approve(owner, smurfId, operator);
        uint256 opEth = operator.balance;
        vm.prank(operator);
        game.withdrawAfkingFunding(smurfId, 0.3 ether);
        assertEq(owner.balance, ownerEth + 0.7 ether, "an operator's withdraw pays the owner");
        assertEq(operator.balance, opEth);
        assertEq(_fixtureAfking(smurfId), 0.3 ether, "the smurf's bucket debited");
    }

    /// @notice An operator's withdraw for an ordinary wallet pays that wallet.
    function test_OperatorWithdrawForWallet_PaysWallet() public {
        _fundAfking(walletId, 1 ether);
        _approve(wallet, 0, operator);
        uint256 walletEth = wallet.balance;
        uint256 opEth = operator.balance;
        vm.prank(operator);
        game.withdrawAfkingFunding(walletId, 0.5 ether);
        assertEq(wallet.balance, walletEth + 0.5 ether, "paid to the wallet");
        assertEq(operator.balance, opEth);
        assertEq(_fixtureAfking(wallet), 0.5 ether);
    }

    function test_StrangerClaimsForSmurf_NotApproved() public {
        _seedClaimable(smurfId, 1 ether);
        _fundAfking(smurfId, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.claimWinnings(smurfId);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.withdrawAfkingFunding(smurfId, 1);
        _approve(owner, 0, operator); // the owner's-ID operator is a stranger to the smurf
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.claimWinnings(smurfId);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.withdrawAfkingFunding(smurfId, 1);
        // A zero withdraw returns before resolution: a no-op for anyone (notes J10).
        vm.prank(stranger);
        game.withdrawAfkingFunding(smurfId, 0);
        assertEq(_fixtureAfking(smurfId), 1 ether);
    }

    // =====================================================================
    // 5. AFKing funding by ID
    // =====================================================================

    /// @dev Run the next day's advance to idle, so the day's quests re-roll and no account has
    ///      completed slot 0: a new run then grounds itself on a funded day-0 cover buy.
    function _advanceDay() private {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 50; ++i) {
            _mineAll(200);
            uint256 req = mockVRF.lastRequestId();
            if (req == 0) break;
            (, , bool fulfilled) = mockVRF.pendingRequests(req);
            if (fulfilled) break;
            mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("acct-rule", req))));
        }
        _mineAll(200);
        assertFalse(game.rngLocked(), "fixture: day settled");
    }

    function _requireCoverBuyDue(uint32 id) private view {
        (bool done0, ) = quests.questCompletionToday(id);
        require(!done0, "fixture: a completed slot-0 quest would ground the run without a cover buy");
    }

    /// @notice An explicit own-ID source is self-funding: no external flag, the sparse map is
    ///         cleared, the event names no source, and the own bucket pays the day-0 buy.
    function test_Subscribe_OwnIdSourceIsSelf() public {
        _advanceDay();
        _fundAfking(walletId, 1 ether);
        // A stale sparse entry: a fresh run must clear it.
        vm.store(address(game), GameSlotKeys.byId(walletId, GameSlots.FUNDING_SOURCE_OF), bytes32(uint256(0xdead)));
        _requireCoverBuyDue(walletId);
        uint256 seat = _grantSeat(wallet);
        vm.expectEmit(true, true, false, true, address(game));
        emit SubscriptionUpdated(_fixtureId(wallet), 1, false, true, 0);
        vm.prank(wallet);
        game.subscribe(0, false, true, 1, walletId, seat);
        assertEq(uint8(_subWord(walletId) >> 8) & FLAG_EXTERNAL_FUNDING, 0, "no external-funding flag");
        assertEq(_fundingSourceWord(walletId), 0, "sparse map cleared");
        assertEq(_fixtureAfking(wallet), 1 ether - price, "the own bucket paid");
        assertEq(afkingSubToken.balanceOf(wallet), 0, "the seat burned");
    }

    /// @notice The owner funds its smurf's subscription without any approval; draws debit the
    ///         owner's bucket and the owner's seat burns.
    function test_Subscribe_OwnerFundsSmurf_NoApproval() public {
        _advanceDay();
        _fundAfking(ownerId, 1 ether);
        _requireCoverBuyDue(smurfId);
        uint256 seat = _grantSeat(owner);
        vm.expectEmit(true, true, false, true, address(game));
        emit SubscriptionUpdated(_fixtureId(smurfId), 1, false, true, ownerId);
        vm.prank(owner);
        game.subscribe(smurfId, false, true, 1, ownerId, seat);
        assertEq(uint8(_subWord(smurfId) >> 8) & FLAG_EXTERNAL_FUNDING, FLAG_EXTERNAL_FUNDING);
        assertEq(_fundingSourceWord(smurfId), ownerId);
        assertEq(_fixtureAfking(owner), 1 ether - price, "the owner's bucket paid");
        assertEq(_fixtureAfking(smurfId), 0);
        assertEq(afkingSubToken.balanceOf(owner), 0, "the payee's seat burned");
        assertEq(uint8(_subWord(smurfId)), 1, "the smurf's run is live");
    }

    /// @notice A smurf funds its owner's subscription without approval.
    function test_Subscribe_SmurfFundsOwner_NoApproval() public {
        _advanceDay();
        _fundAfking(smurfId, 1 ether);
        _requireCoverBuyDue(ownerId);
        uint256 seat = _grantSeat(owner);
        vm.prank(owner);
        game.subscribe(0, false, true, 1, smurfId, seat);
        assertEq(_fundingSourceWord(ownerId), smurfId);
        assertEq(_fixtureAfking(smurfId), 1 ether - price, "the smurf's bucket paid");
        assertEq(_fixtureAfking(owner), 0);
    }

    /// @notice One smurf funds a sibling smurf without approval.
    function test_Subscribe_SiblingSmurfFunds_NoApproval() public {
        _advanceDay();
        vm.prank(owner);
        uint32 siblingId = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        uint32 siblingKey = siblingId;
        _fundAfking(siblingId, 1 ether);
        _requireCoverBuyDue(smurfId);
        uint256 seat = _grantSeat(owner);
        vm.prank(owner);
        game.subscribe(smurfId, false, true, 1, siblingId, seat);
        assertEq(_fundingSourceWord(smurfId), siblingId);
        assertEq(_fixtureAfking(siblingKey), 1 ether - price, "the sibling's bucket paid");
        assertEq(_fixtureAfking(smurfId), 0);
    }

    /// @notice An unrelated source must approve the subscriber's key on its own ID.
    function test_Subscribe_UnrelatedSourceNeedsApproval() public {
        _advanceDay();
        _fundAfking(sourceId, 1 ether);
        _requireCoverBuyDue(walletId);
        uint256 seat = _grantSeat(wallet);
        vm.prank(wallet);
        vm.expectRevert(NotApproved.selector);
        game.subscribe(0, false, true, 1, sourceId, seat);

        vm.prank(source);
        game.setAfkingFundingApproval(sourceId, walletId, true);
        vm.prank(wallet);
        game.subscribe(0, false, true, 1, sourceId, seat);
        assertEq(_fixtureAfking(source), 1 ether - price, "the approving source paid");
        assertEq(_fundingSourceWord(walletId), sourceId);
    }

    /// @notice For a smurf subscriber the consent is to the smurf's KEY: approving its owner is not
    ///         enough, approving the smurf key is.
    function test_Subscribe_UnrelatedSourceForSmurf_ApprovesSmurfKey() public {
        _advanceDay();
        _fundAfking(sourceId, 1 ether);
        _requireCoverBuyDue(smurfId);
        uint256 seat = _grantSeat(owner);
        vm.prank(source);
        game.setOperatorApproval(0, owner, true);
        vm.prank(owner);
        vm.expectRevert(NotApproved.selector);
        game.subscribe(smurfId, false, true, 1, sourceId, seat);

        vm.prank(source);
        game.setAfkingFundingApproval(sourceId, smurfId, true);
        vm.prank(owner);
        game.subscribe(smurfId, false, true, 1, sourceId, seat);
        assertEq(_fixtureAfking(source), 1 ether - price, "the source paid");
    }

    function test_DepositAfkingFunding_ZeroOrUnallocatedRevertsE() public {
        vm.prank(owner);
        vm.expectRevert(E.selector);
        game.depositAfkingFunding{value: 1 ether}(0);
        uint32 next = uint32(_walletsLength());
        vm.prank(owner);
        vm.expectRevert(E.selector);
        game.depositAfkingFunding{value: 1 ether}(next);
    }

    // =====================================================================
    // 6. Batches and the isolating self-calls (H-F3)
    // =====================================================================

    /// @notice An element 0 reaches the isolating self-call as the caller's ID, never as 0.
    function test_ClaimAffiliateDgnrsBatch_ZeroMapsToCaller() public {
        uint32[] memory ids = new uint32[](2);
        ids[1] = walletId;
        vm.expectCall(address(game), abi.encodeWithSignature("claimAffiliateDgnrs(uint32)", ownerId), 1);
        vm.expectCall(address(game), abi.encodeWithSignature("claimAffiliateDgnrs(uint32)", walletId), 1);
        vm.expectCall(address(game), abi.encodeWithSignature("claimAffiliateDgnrs(uint32)", uint32(0)), 0);
        vm.prank(owner);
        game.claimAffiliateDgnrs(ids); // ineligible items are skipped, never reverting the batch
    }

    function test_ClaimAffiliateDgnrsBlank_CallerWithoutIdReverts() public {
        uint32[] memory none = new uint32[](0);
        vm.prank(stranger);
        vm.expectRevert();
        game.claimAffiliateDgnrs(none);
    }

    /// @notice claimFoilMatchMany maps an element 0 to the caller's ID before its self-call.
    function test_ClaimFoilMatchMany_ZeroMapsToCaller() public {
        uint32[] memory ids = new uint32[](1);
        uint24[] memory dayList = new uint24[](1);
        uint8[] memory idx = new uint8[](1);
        uint24 day = game.currentDayView();
        dayList[0] = day;
        vm.expectCall(
            address(game),
            abi.encodeWithSignature("claimFoilMatch(uint32,uint256,uint256)", ownerId, uint256(day), uint256(0)),
            1
        );
        vm.expectCall(
            address(game),
            abi.encodeWithSignature("claimFoilMatch(uint32,uint256,uint256)", uint32(0), uint256(day), uint256(0)),
            0
        );
        // Nothing is claimable, so the dead opener reverts the batch (the spent-list probe).
        vm.prank(owner);
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(ids, dayList, idx);
    }

    /// @notice claimAfkingFlip takes 0, unallocated and smurf IDs in one batch without reverting,
    ///         for a caller with or without an ID.
    function test_ClaimAfkingFlip_MixedIdsNeverRevert() public {
        uint32[] memory ids = new uint32[](3);
        ids[1] = uint32(_walletsLength()) + 5;
        ids[2] = smurfId;
        vm.prank(owner);
        game.claimAfkingFlip(ids);
        vm.prank(stranger);
        game.claimAfkingFlip(ids);
        vm.prank(operator);
        game.claimAfkingFlip(new uint32[](0));
    }
}
