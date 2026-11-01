// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {AccountFixture} from "./AccountFixture.t.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title AccountRuleGame -- the Game side of the account rule (acting by wallet ID)
/// @notice Against the real protocol:
///         - `resolveAccount` answers (key, payee, authorized) for keys, operators approved on the
///           exact ID, strangers and acquired accounts, and reverts `E` only for 0/unallocated IDs;
///         - `setOperatorApproval` stores approvals by account ID, only the payee manages them, and
///           the event carries the ID; an acquired account's operators never authorize;
///         - acting for another account by ID: state follows the account, value out goes to its
///           payee, the caller's fresh ETH pays and its overpay credits the caller's ID, FLIP burns
///           from the payee;
///         - AFKing subscriptions by ID: the account rule authorizes the caller, the payee's seat
///           burns, nothing is bought at signup, and each day's buy is paid from the subscriber's
///           own bucket;
///         - the batch doors map an element 0 to the caller before their isolating self-calls.
contract AccountRuleGame is AccountFixture {
    /// @dev Coinflip.playerState root and flipsClaimableDay slot (scripts/layout/golden/Coinflip.json).
    uint256 private constant CF_PLAYER_STATE_ROOT = 2;
    uint256 private constant CF_CLAIMABLE_DAY_SLOT = 4;

    error E();
    error NotApproved();
    error ZeroAddress();
    error StaleBatch();

    event OperatorApproval(uint32 indexed id, address indexed operator, bool approved);
    event EntriesBought(uint32 indexed buyer, uint256 entryQuantityScaled, uint256 weiIn);
    event LootBoxBuy(uint32 indexed buyer, uint48 indexed index, uint32 position, uint256 amount);
    event WinningsClaimed(uint32 indexed player, uint256 amount, uint128 claimableAfter);
    event AfkingWithdrew(uint32 indexed player, uint256 amount);
    event SubscriptionUpdated(uint32 indexed player, uint8 dailyQuantity, bool useTickets);

    address private owner;
    address private operator;
    address private stranger;
    address private wallet; // an ordinary registered wallet unrelated to the owner
    uint32 private ownerId;
    uint32 private walletId;
    uint256 private price;

    function setUp() public {
        _setUpAccountFixture();
        owner = makeAddr("acct_owner");
        operator = makeAddr("acct_operator");
        stranger = makeAddr("acct_stranger");
        wallet = makeAddr("acct_wallet");
        vm.deal(owner, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(stranger, 100 ether);
        vm.deal(wallet, 100 ether);
        price = game.mintPrice();
        mockVRF.fundSubscription(1, 1_000 ether);

        _buyTicket(owner);
        _buyTicket(wallet);
        ownerId = game.walletIdOf_g3120(owner);
        walletId = game.walletIdOf_g3120(wallet);
        _finishSubscriptionWindow();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------



    function _buyTicket(address who) private {
        vm.prank(who);
        game.purchaseOrderFor{value: price}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
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

    function _lane(uint32 id) private view returns (uint256 lane, uint256 position1) {
        return GameSlotKeys.subLane(address(game), id);
    }

    function _flip(address who, uint256 amount) private {
        vm.prank(address(game));
        coin.mintForGame_g152734(who, amount);
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
        game.resolveAccount_g7029(0, owner);
        uint32 next = uint32(_walletsLength());
        vm.expectRevert(E.selector);
        game.resolveAccount_g7029(next, owner);
    }

    function test_ResolveAccount_KeyAsCaller() public view {
        (address key, address payee, bool ok) = game.resolveAccount_g7029(ownerId, owner);
        assertEq(key, owner);
        assertEq(payee, owner);
        assertTrue(ok);
    }

    function test_ResolveAccount_OperatorOnAccount_PayeeIsKey() public {
        _approve(owner, ownerId, operator);
        (address key, address payee, bool ok) = game.resolveAccount_g7029(ownerId, operator);
        assertEq(key, owner);
        assertEq(payee, owner, "an operator acts for the account, value still goes to its wallet");
        assertTrue(ok);
    }

    function test_ResolveAccount_OperatorOfAnotherAccountIsAStranger() public {
        _approve(wallet, 0, operator);
        (, , bool onWallet) = game.resolveAccount_g7029(walletId, operator);
        (address key, address payee, bool onOwner) = game.resolveAccount_g7029(ownerId, operator);
        assertTrue(onWallet, "authorized for the approving account");
        assertFalse(onOwner, "approvals are per account ID");
        assertEq(key, owner);
        assertEq(payee, owner);
    }

    function test_ResolveAccount_StrangerFalseNoRevert() public view {
        (address k1, address p1, bool ok1) = game.resolveAccount_g7029(ownerId, stranger);
        (, , bool ok2) = game.resolveAccount_g7029(ownerId, wallet);
        assertEq(k1, owner);
        assertEq(p1, owner);
        assertFalse(ok1);
        assertFalse(ok2, "another registered wallet is a stranger too");
    }

    /// @notice A seized account keeps its former wallet as key and pays its lender, which alone
    ///         acts for it; operator approvals never authorize, even ones the lender sets.
    function test_ResolveAccount_AcquiredAccount() public {
        _approve(owner, ownerId, operator);
        _acquire(owner, ownerId, SDGNRS_ID);
        (address key, address payee, bool sellerOk) = game.resolveAccount_g7029(ownerId, owner);
        assertEq(key, owner, "the key is the former wallet");
        assertEq(payee, address(sdgnrs), "the lender is the payee");
        assertFalse(sellerOk, "the seller is a stranger");
        (, , bool operatorOk) = game.resolveAccount_g7029(ownerId, operator);
        assertFalse(operatorOk, "the prior operator lapsed");
        (, , bool lenderOk) = game.resolveAccount_g7029(ownerId, address(sdgnrs));
        assertTrue(lenderOk, "the lender acts for it");

        vm.prank(owner);
        vm.expectRevert(NotApproved.selector);
        game.setOperatorApproval(ownerId, stranger, true);
        vm.prank(address(sdgnrs));
        game.setOperatorApproval(ownerId, stranger, true);
        (, , bool lenderOperatorOk) = game.resolveAccount_g7029(ownerId, stranger);
        assertFalse(lenderOperatorOk, "no operator authorizes for an acquired account");
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
        (, , bool ok) = game.resolveAccount_g7029(ownerId, operator);
        assertTrue(ok);

        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(ownerId, operator, false);
        vm.prank(owner);
        game.setOperatorApproval(0, operator, false);
        (, , ok) = game.resolveAccount_g7029(ownerId, operator);
        assertFalse(ok, "revoked");
    }

    function test_SetOperatorApproval_ExplicitIdStoresUnderThatId() public {
        vm.expectEmit(true, true, false, true, address(game));
        emit OperatorApproval(ownerId, operator, true);
        _approve(owner, ownerId, operator);
        assertEq(uint256(vm.load(address(game), _approvalSlot(ownerId, operator))), 1, "stored under the account ID");
        assertEq(uint256(vm.load(address(game), _approvalSlot(walletId, operator))), 0, "not under another ID");
        (, address payee, bool ok) = game.resolveAccount_g7029(ownerId, operator);
        assertTrue(ok);
        assertEq(payee, owner);

        vm.prank(owner);
        game.setOperatorApproval(ownerId, operator, false);
        (, , ok) = game.resolveAccount_g7029(ownerId, operator);
        assertFalse(ok);
    }

    function test_SetOperatorApproval_OperatorCannotApprove() public {
        _approve(owner, 0, operator);
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
        game.setOperatorApproval(ownerId, wallet, true);
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
        game.setOperatorApproval(ownerId, address(0), true);
    }

    // =====================================================================
    // 4. Acting on behalf of another account
    // =====================================================================

    /// @notice An operator with its own ID buys for the account: tickets and boxes are the
    ///         account's, the operator's fresh ETH pays, and the overpay credits the operator's ID.
    function test_OperatorPurchaseForAccount_EthAndOverpayToCaller() public {
        _approve(wallet, walletId, owner);
        uint256 box = 0.02 ether;
        uint256 extra = 0.3 ether;
        uint256 ethBefore = owner.balance;
        uint256 ownerAfk = _fixtureAfking(owner);
        uint32 walletOwed = _fixtureEntries(1, walletId);
        uint32 ownerOwed = _fixtureEntries(1, owner);

        vm.expectEmit(true, false, false, true, address(game));
        emit EntriesBought(walletId, 400, price);
        vm.expectEmit(true, false, false, false, address(game));
        emit LootBoxBuy(walletId, 0, 0, 0);
        vm.prank(owner);
        game.purchaseOrderFor{value: price + box + extra}(
            walletId, 400, BoxOrderLib.boCustom(box), bytes32(0), MintPaymentKind.DirectEth, false
        );

        assertEq(owner.balance, ethBefore - price - box - extra, "the operator's ETH paid");
        assertGt(_fixtureEntries(1, walletId), walletOwed, "tickets to the account");
        assertEq(_fixtureEntries(1, owner), ownerOwed, "none to the operator");
        assertEq(_fixtureAfking(owner), ownerAfk + extra, "overpay to the paying operator's ID");
        assertEq(_fixtureAfking(walletId), 0, "nothing to the account");
    }

    /// @notice A Claimable buy for the account spends the account's own ledger, not the caller's.
    function test_OperatorPurchaseForAccount_ClaimableFromAccountLedger() public {
        _approve(wallet, walletId, owner);
        _seedClaimable(walletId, 1 ether);
        _seedClaimable(ownerId, 1 ether);
        vm.prank(owner);
        game.purchaseOrderFor(walletId, 400, 0, bytes32(0), MintPaymentKind.Claimable, false);
        assertEq(_fixtureClaimable(walletId), 1 ether - price, "the account's claimable spent");
        assertEq(_fixtureClaimable(owner), 1 ether, "the operator's untouched");
    }

    function test_StrangerPurchaseForAccount_NotApproved() public {
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.purchaseOrderFor{value: price}(ownerId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        // An operator of another account is a stranger here.
        _approve(wallet, 0, operator);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.purchaseOrderFor{value: price}(ownerId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @notice An operator without an ID buys for the account with its own ETH. Overpay credits the
    ///         paying caller's ID, so an operator without an ID cannot overpay.
    function test_OperatorPurchaseForAccount_OverpayNeedsCallerId() public {
        _approve(owner, ownerId, operator);
        uint32 owed = _fixtureEntries(1, ownerId);
        uint256 opEth = operator.balance;
        vm.prank(operator);
        game.purchaseOrderFor{value: price}(ownerId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(operator.balance, opEth - price, "the operator's ETH paid");
        assertGt(_fixtureEntries(1, ownerId), owed, "tickets to the account");

        vm.prank(operator);
        vm.expectRevert(E.selector);
        game.purchaseOrderFor{value: price + 1 ether}(ownerId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);

        uint32 opId = _giveWalletId(operator);
        uint256 ownerAfk = _fixtureAfking(owner);
        vm.prank(operator);
        game.purchaseOrderFor{value: price + 1 ether}(ownerId, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_fixtureAfking(operator), 1 ether, "overpay to the paying operator's ID");
        assertEq(_fixtureAfking(owner), ownerAfk, "not the account's");
        assertTrue(opId != 0);
    }

    /// @notice redeemFlip by an operator burns the PAYEE's wallet FLIP; the account gets the tickets.
    function test_OperatorRedeemFlip_BurnsPayeeFlip() public {
        _openRedemptionWindow();
        _approve(owner, ownerId, operator);
        _flip(owner, 10_000);
        _flip(operator, 10_000);
        uint256 ownerFlip = coin.balanceOf(owner);
        uint32 owed = _fixtureEntries(1, ownerId);
        vm.prank(operator);
        game.redeemFlip(ownerId, 400);
        assertEq(ownerFlip - coin.balanceOf(owner), 1_000, "one ticket's FLIP burned from the payee");
        assertEq(coin.balanceOf(operator), 10_000, "the operator's FLIP is untouched");
        assertGt(_fixtureEntries(1, ownerId), owed, "tickets to the account");
    }

    /// @notice A wallet shortfall comes from the account's settled coinflip winnings, never the
    ///         operator's.
    function test_OperatorRedeemFlip_ShortfallFromAccountCoinflipClaimable() public {
        _openRedemptionWindow();
        _approve(owner, ownerId, wallet);
        _flip(owner, 400);
        bytes32 ownerState = keccak256(abi.encode(ownerId, CF_PLAYER_STATE_ROOT));
        bytes32 walletState = keccak256(abi.encode(walletId, CF_PLAYER_STATE_ROOT));
        uint256 latest = uint24(uint256(vm.load(address(coinflip), bytes32(CF_CLAIMABLE_DAY_SLOT))));
        // claimableStored = 5,000 whole FLIP, lastClaim = flipsClaimableDay (no walk to settle).
        vm.store(address(coinflip), ownerState, bytes32((latest << 128) | 5_000));
        vm.store(address(coinflip), walletState, bytes32((latest << 128) | 7_000));

        vm.prank(wallet);
        game.redeemFlip(ownerId, 400);

        assertEq(coin.balanceOf(owner), 0, "the payee's wallet FLIP burned first");
        assertEq(uint128(uint256(vm.load(address(coinflip), ownerState))), 5_000 - 600,
            "the account's coinflip winnings cover the shortfall");
        assertEq(uint128(uint256(vm.load(address(coinflip), walletState))), 7_000, "the operator's untouched");
    }

    function test_StrangerRedeemFlipForAccount_NotApproved() public {
        _openRedemptionWindow();
        _flip(stranger, 10_000);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.redeemFlip(ownerId, 400);
    }

    /// @notice claimWinnings by explicit ID, by the wallet or its operator, pays the wallet.
    function test_ClaimWinningsByOperator_PaysWallet() public {
        _seedClaimable(ownerId, 1 ether);
        uint256 ownerEth = owner.balance;
        vm.expectEmit(true, false, false, true, address(game));
        emit WinningsClaimed(ownerId, 1 ether - 1, 1);
        vm.prank(owner);
        game.claimClaimable(ownerId);
        assertEq(owner.balance, ownerEth + 1 ether - 1, "paid to the wallet");
        assertEq(_fixtureClaimable(ownerId), 1, "the ledger debited to the sentinel");

        _approve(owner, ownerId, operator);
        _seedClaimable(ownerId, 1 ether);
        ownerEth = owner.balance;
        uint256 opEth = operator.balance;
        vm.prank(operator);
        game.claimWinnings(ownerId, 0.2 ether);
        assertEq(owner.balance, ownerEth + 0.2 ether, "an operator's claim pays the wallet");
        assertEq(operator.balance, opEth, "never the operator");
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

    function test_StrangerClaimsForAccount_NotApproved() public {
        _seedClaimable(ownerId, 1 ether);
        _fundAfking(ownerId, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.claimClaimable(ownerId);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.withdrawAfkingFunding(ownerId, 1);
        _approve(wallet, 0, operator); // an operator of another account is a stranger here
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.claimClaimable(ownerId);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.withdrawAfkingFunding(ownerId, 1);
        // A zero withdraw returns before resolution: a no-op for anyone.
        vm.prank(stranger);
        game.withdrawAfkingFunding(ownerId, 0);
        assertEq(_fixtureAfking(ownerId), 1 ether);
    }

    // =====================================================================
    // 5. AFKing funding by ID
    // =====================================================================

    /// @dev Run the next day's advance to idle, so the day's subscriber pass has completed and a
    ///      new run can start.
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

    /// @notice A subscriber acting for its own ID: the event names the run, the seat burns, the run
    ///         is checkpointed today and nothing is bought or debited at signup.
    function test_Subscribe_OwnId_BuysNothingAtSignup() public {
        _advanceDay();
        _fundAfking(walletId, 1 ether);
        uint256 seat = _grantSeat(wallet);
        vm.expectEmit(true, false, false, true, address(game));
        emit SubscriptionUpdated(_fixtureId(wallet), 1, true);
        vm.prank(wallet);
        game.subscribe(0, true, 1, seat);
        (uint256 lane, uint256 position1) = _lane(walletId);
        assertGt(position1, 0, "the run is live");
        assertEq((lane >> 46) & 0x3fffff, game.currentDayView_g542950(), "checkpointed on the signup day");
        assertEq(_fixtureAfking(wallet), 1 ether, "no purchase at signup");
        assertEq(afkingSubToken.balanceOf(wallet), 0, "the seat burned");
    }

    /// @notice An operator with its own ID subscribes the account: the run is the account's, the
    ///         payee's seat burns, and each day's buy debits the account's own bucket.
    function test_Subscribe_OperatorRunsAccount_PaidFromAccountBucket() public {
        _advanceDay();
        _approve(owner, ownerId, wallet);
        _fundAfking(ownerId, 1 ether);
        _fundAfking(walletId, 1 ether);
        uint256 seat = _grantSeat(owner);
        vm.expectEmit(true, false, false, true, address(game));
        emit SubscriptionUpdated(ownerId, 1, true);
        vm.prank(wallet);
        game.subscribe(ownerId, true, 1, seat);
        (uint256 lane, uint256 position1) = _lane(ownerId);
        assertGt(position1, 0, "the account's run is live");
        assertEq(uint32(lane), ownerId);
        (, uint256 walletPosition) = _lane(walletId);
        assertEq(walletPosition, 0, "the operator has no run of its own");
        assertEq(afkingSubToken.balanceOf(owner), 0, "the payee's seat burned");
        assertEq(_fixtureAfking(ownerId), 1 ether, "no purchase at signup");

        _advanceDay();
        assertEq(_fixtureAfking(ownerId), 1 ether - price, "the account's bucket paid the day's buy");
        assertEq(_fixtureAfking(walletId), 1 ether, "the operator's bucket untouched");
    }

    /// @notice A stranger cannot subscribe for another account; an operator approved on the exact
    ///         ID can, and the run is the account's.
    function test_Subscribe_StrangerNeedsApproval() public {
        _advanceDay();
        uint256 seat = _grantSeat(wallet);
        vm.prank(stranger);
        vm.expectRevert(NotApproved.selector);
        game.subscribe(walletId, true, 1, seat);

        _approve(wallet, walletId, operator);
        vm.prank(operator);
        game.subscribe(walletId, true, 1, seat);
        (, uint256 position1) = _lane(walletId);
        assertGt(position1, 0, "the account's run is live");
        assertEq(afkingSubToken.balanceOf(wallet), 0, "the account payee's seat burned");
    }

    /// @notice An operator approved on another account cannot subscribe this one.
    function test_Subscribe_OperatorOfAnotherAccountNotApproved() public {
        _advanceDay();
        uint256 seat = _grantSeat(owner);
        _approve(wallet, walletId, operator);
        vm.prank(operator);
        vm.expectRevert(NotApproved.selector);
        game.subscribe(ownerId, true, 1, seat);
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
        // Past level 0, so the claim reaches its ID/score gate instead of stopping at NotStarted().
        bytes32 levelSlot = bytes32(GameSlots.LEVEL);
        uint256 slot0 = uint256(vm.load(address(game), levelSlot));
        uint256 levelMask = uint256(0xFFFFFF) << (GameSlots.LEVEL_OFFSET * 8);
        vm.store(address(game), levelSlot, bytes32((slot0 & ~levelMask) | (uint256(1) << (GameSlots.LEVEL_OFFSET * 8))));
        assertEq(game.currentLvl(), 1, "fixture: level 1");
        assertEq(game.walletIdOf_g3120(stranger), 0, "fixture: the caller holds no ID");
        vm.prank(stranger);
        vm.expectRevert(bytes4(keccak256("ScoreTooLow()")));
        game.claimAffiliateDgnrs(none);
    }

    /// @notice claimFoilMatchMany maps an element 0 to the caller's ID before its self-call.
    function test_ClaimFoilMatchMany_ZeroMapsToCaller() public {
        uint32[] memory ids = new uint32[](1);
        uint24[] memory dayList = new uint24[](1);
        uint8[] memory idx = new uint8[](1);
        uint24 day = game.currentDayView_g542950();
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

    /// @notice claimAfkingFlip takes 0, unallocated and other accounts' IDs in one batch without reverting,
    ///         for a caller with or without an ID.
    function test_ClaimAfkingFlip_MixedIdsNeverRevert() public {
        uint32[] memory ids = new uint32[](3);
        ids[1] = uint32(_walletsLength()) + 5;
        ids[2] = walletId;
        vm.prank(owner);
        game.claimAfkingFlip(ids);
        vm.prank(stranger);
        game.claimAfkingFlip(ids);
        vm.prank(operator);
        game.claimAfkingFlip(new uint32[](0));
    }
}
