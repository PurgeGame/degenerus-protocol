// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {AccountFixture} from "./AccountFixture.t.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegeneretteGiftByAccount -- the Degenerette door's gift and acting-for-an-account split
/// @notice `betDegenerette(id, ...)` resolves account `id` against the caller. A caller not authorized for the account makes a gift: the caller's fresh ETH,
///         claimable and FLIP fund it, the caller earns the quest, the bet belongs to `id`, and the
///         recipient's stake boon is never read. A gift to an unallocated ID reverts `E`. A caller
///         authorized for the account (its wallet, or an operator approved for that ID) acts for
///         it: the account's claimable funds the shortfall, FLIP burns from the account's payee,
///         the account earns the quest, and the account's boon is spent. After a seizure the
///         former wallet is a stranger to the account: its bet is a gift.
/// @dev Boons are written straight into `boonPacked[id].slot1` (the DegeneretteBoonStake layout:
///      per-currency 24-bit lanes at 184 + 24 * currency, [day:21 | deity:1 | tier:2]).
contract DegeneretteGiftByAccountTest is AccountFixture {
    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant HERO = 3;
    uint256 private constant BP_DEGEN_LANE0_SHIFT = 184;
    uint256 private constant BP_LANE_MASK = 0xFFFFFF;
    uint256 private constant BET_STAKE_SHIFT = 60;

    address private owner;
    uint32 private ownerId;
    address private recipient;
    uint32 private recipientId;
    address private giver;
    uint32 private giverId;
    address private operator;

    function setUp() public {
        _setUpAccountFixture();
        (owner, ownerId) = _wallet("gift_owner");
        (recipient, recipientId) = _wallet("gift_recipient");
        (giver, giverId) = _wallet("gift_giver");
        operator = makeAddr("gift_operator");
        vm.deal(operator, 10 ether);
        _openBetBuffer();
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _boonSlot1(uint32 id) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(uint256(id), GameSlots.BOON_PACKED))) + 1);
    }

    function _lane(uint32 id, uint8 currency) private view returns (uint256) {
        return (uint256(vm.load(address(game), _boonSlot1(id))) >> (BP_DEGEN_LANE0_SHIFT + 24 * uint256(currency)))
            & BP_LANE_MASK;
    }

    /// @dev A lootbox-rolled stake boon of `tier` stamped today in `currency`'s lane of `id`.
    function _grantBoon(uint32 id, uint8 currency, uint8 tier) private {
        uint256 shift = BP_DEGEN_LANE0_SHIFT + 24 * uint256(currency);
        uint256 s1 = uint256(vm.load(address(game), _boonSlot1(id)));
        uint256 lane = (uint256(game.currentDayView_g542950() & 0x1FFFFF) << 3) | tier;
        s1 = (s1 & ~(BP_LANE_MASK << shift)) | (lane << shift);
        vm.store(address(game), _boonSlot1(id), bytes32(s1));
        assertEq(_lane(id, currency) & 3, tier, "fixture: boon written");
    }

    function _fundFlip(address who, uint256 amount) private {
        vm.prank(address(game));
        coin.mintForGame_g152734(who, amount);
    }

    function _expectQuest(uint32 earner, uint32 notEarner) private {
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette_g3.selector, earner), 1);
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette_g3.selector, notEarner), 0);
    }

    /// @dev Place a bet as `caller` for account `id`; returns the stored bet word.
    function _bet(address caller, uint32 id, uint8 currency, uint128 perSpin, uint8 spins, uint256 value)
        private
        returns (uint256 bet, uint32 betOwner)
    {
        vm.recordLogs();
        vm.prank(caller);
        game.betDegenerette{value: value}(id, currency, perSpin, spins, HERO);
        uint64 betId;
        (betId, betOwner) = _placedBetId(vm.getRecordedLogs());
        bet = game.degeneretteBetInfo(BET_INDEX, betId);
    }

    function _stakeUnits(uint256 bet) private pure returns (uint256) {
        return (bet >> BET_STAKE_SHIFT) & type(uint64).max;
    }

    // ---------------------------------------------------------------------
    // Gifts
    // ---------------------------------------------------------------------

    /// @dev A stranger's ETH bet for an ordinary wallet: fresh ETH and the claimable shortfall come
    ///      from the stranger, who earns the quest; the bet is the recipient's; its boon is untouched.
    function test_StrangerEthBetForWallet_IsAGiftFundedByTheCaller() public {
        _grantBoon(recipientId, CURRENCY_ETH, 2);
        uint256 boonLane = _lane(recipientId, CURRENCY_ETH);
        ext.x_creditClaimable(giverId, 1 ether);
        uint256 giverClaimable = _fixtureClaimable(giver);
        uint256 recipientClaimable = _fixtureClaimable(recipient);
        uint256 giverEth = giver.balance;
        uint256 recipientEth = recipient.balance;

        _expectQuest(giverId, recipientId);
        (uint256 bet, uint32 betOwner) = _bet(giver, recipientId, CURRENCY_ETH, 0.01 ether, 5, 0.02 ether);

        assertEq(uint32(bet), recipientId, "the bet belongs to the recipient's ID");
        assertEq(betOwner, _fixtureId(recipient), "the placement event names the recipient");
        assertEq(giverEth - giver.balance, 0.02 ether, "the giver's fresh ETH paid");
        assertEq(giverClaimable - _fixtureClaimable(giver), 0.03 ether, "the giver's claimable covered the rest");
        assertEq(_fixtureClaimable(recipient), recipientClaimable, "the recipient's claimable is untouched");
        assertEq(recipient.balance, recipientEth, "the recipient's ETH is untouched");
        assertEq(_lane(recipientId, CURRENCY_ETH), boonLane, "the recipient's boon is untouched");
        assertEq(_stakeUnits(bet), 0.01 ether / 1 gwei, "no boon boost on a gift");
    }

    /// @dev A stranger's FLIP bet for an account: the stranger's FLIP burns, the account wallet's
    ///      does not; the account's boon is untouched; the stranger earns the quest.
    function test_StrangerFlipBetForAccount_IsAGiftFundedByTheCaller() public {
        _grantBoon(ownerId, CURRENCY_FLIP, 3);
        uint256 boonLane = _lane(ownerId, CURRENCY_FLIP);
        _fundFlip(giver, 10_000);
        _fundFlip(owner, 10_000);

        _expectQuest(giverId, ownerId);
        (uint256 bet, uint32 betOwner) = _bet(giver, ownerId, CURRENCY_FLIP, 1_000, 3, 0);

        assertEq(uint32(bet), ownerId, "the bet belongs to the account's ID");
        assertEq(betOwner, ownerId, "the placement event names the account");
        assertEq(coin.balanceOf(giver), 7_000, "the giver's FLIP burned");
        assertEq(coin.balanceOf(owner), 10_000, "the account wallet's FLIP is untouched");
        assertEq(_lane(ownerId, CURRENCY_FLIP), boonLane, "the account's boon is untouched");
        assertEq(_stakeUnits(bet), 1_000, "no boon boost on a gift");
    }

    /// @dev A gift caller with no ID yet registers as the paying funder and earns the quest.
    function test_UnregisteredGiverRegistersAndEarnsTheQuest() public {
        address fresh = makeAddr("gift_fresh_giver");
        vm.deal(fresh, 1 ether);
        assertEq(game.walletIdOf_g3120(fresh), 0, "fixture: unregistered giver");
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette_g3.selector, recipientId), 0);
        (uint256 bet,) = _bet(fresh, recipientId, CURRENCY_ETH, 0.01 ether, 2, 0.02 ether);
        uint32 freshId = game.walletIdOf_g3120(fresh);
        assertGt(freshId, 0, "the paying funder registered");
        assertEq(uint32(bet), recipientId, "the bet belongs to the recipient");
    }

    function test_GiftToUnallocatedId_RevertsE() public {
        uint32 unallocated = 1_000_000;
        vm.prank(giver);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.betDegenerette{value: 0.01 ether}(unallocated, CURRENCY_ETH, 0.01 ether, 1, HERO);
    }

    // ---------------------------------------------------------------------
    // Acting for an account (not a gift)
    // ---------------------------------------------------------------------

    /// @dev The wallet's FLIP bet naming its own ID: its FLIP burns, it earns the quest, and its
    ///      boon is spent on the bet.
    function test_WalletFlipBetForOwnId_BurnsItsFlipAndSpendsItsBoon() public {
        _grantBoon(ownerId, CURRENCY_FLIP, 3);
        _fundFlip(owner, 10_000);

        _expectQuest(ownerId, giverId);
        (uint256 bet, uint32 betOwner) = _bet(owner, ownerId, CURRENCY_FLIP, 1_000, 3, 0);

        assertEq(uint32(bet), ownerId, "the bet belongs to the account's ID");
        assertEq(betOwner, ownerId, "the placement event names the account");
        assertEq(coin.balanceOf(owner), 7_000, "the wallet's FLIP burned");
        assertEq(_lane(ownerId, CURRENCY_FLIP) & 3, 0, "the account's boon was spent");
        assertGt(_stakeUnits(bet), 1_000, "the boon boosted the packed stake");
    }

    /// @dev An operator's ETH bet for the account with no fresh ETH: the account's claimable funds
    ///      it, the operator's ledger does not; the account earns the quest; its ETH boon is spent.
    function test_OperatorEthBetForAccount_AccountClaimableFundsIt() public {
        _giveWalletId(operator);
        uint32 operatorId = game.walletIdOf_g3120(operator);
        vm.prank(owner);
        game.setOperatorApproval(ownerId, operator, true);
        _grantBoon(ownerId, CURRENCY_ETH, 1);
        ext.x_creditClaimable(ownerId, 1 ether);
        ext.x_creditClaimable(operatorId, 1 ether);
        uint256 accountClaimable = _fixtureClaimable(ownerId);
        uint256 operatorClaimable = _fixtureClaimable(operatorId);
        uint256 operatorEth = operator.balance;

        _expectQuest(ownerId, operatorId);
        (uint256 bet,) = _bet(operator, ownerId, CURRENCY_ETH, 0.01 ether, 4, 0);

        assertEq(uint32(bet), ownerId, "the bet belongs to the account's ID");
        assertEq(accountClaimable - _fixtureClaimable(ownerId), 0.04 ether, "the account's claimable funded it");
        assertEq(_fixtureClaimable(operatorId), operatorClaimable, "the operator's claimable is untouched");
        assertEq(operator.balance, operatorEth, "no fresh ETH moved");
        assertEq(_lane(ownerId, CURRENCY_ETH) & 3, 0, "the account's boon was spent");
        assertGt(_stakeUnits(bet), 0.01 ether / 1 gwei, "the boon boosted the packed stake");
    }

    /// @dev An operator approved for the account acts for it: FLIP burns from the payee, never
    ///      from the operator, and the account earns the quest.
    function test_OperatorFlipBetForAccount_BurnsFromThePayee() public {
        vm.prank(owner);
        game.setOperatorApproval(ownerId, operator, true);
        _fundFlip(owner, 10_000);
        _fundFlip(operator, 10_000);

        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette_g3.selector, ownerId), 1);
        (uint256 bet,) = _bet(operator, ownerId, CURRENCY_FLIP, 500, 2, 0);

        assertEq(uint32(bet), ownerId, "the bet belongs to the account's ID");
        assertEq(coin.balanceOf(owner), 9_000, "the payee's FLIP burned");
        assertEq(coin.balanceOf(operator), 10_000, "the operator's FLIP is untouched");
    }

    /// @dev Approvals are per account ID: an operator of one account betting for another makes a
    ///      gift it funds itself.
    function test_OperatorOfAnotherAccount_BetIsAGift() public {
        vm.prank(owner);
        game.setOperatorApproval(0, operator, true);
        _fundFlip(recipient, 10_000);
        _fundFlip(operator, 10_000);
        _grantBoon(recipientId, CURRENCY_FLIP, 2);
        uint256 boonLane = _lane(recipientId, CURRENCY_FLIP);

        (uint256 bet,) = _bet(operator, recipientId, CURRENCY_FLIP, 500, 2, 0);

        assertEq(uint32(bet), recipientId, "the bet belongs to the recipient's ID");
        assertEq(coin.balanceOf(operator), 9_000, "the gifting operator's FLIP burned");
        assertEq(coin.balanceOf(recipient), 10_000, "the recipient's FLIP is untouched");
        assertEq(_lane(recipientId, CURRENCY_FLIP), boonLane, "the recipient's boon is untouched");
        assertGt(game.walletIdOf_g3120(operator), 0, "the gifting operator registered as the funder");
    }

    // ---------------------------------------------------------------------
    // After seizure
    // ---------------------------------------------------------------------

    function test_SellerBetAfterVaultSeizure_IsAGift() public { _sellerGift(VAULT_ID); }

    function test_SellerBetAfterSdgnrsSeizure_IsAGift() public { _sellerGift(SDGNRS_ID); }

    /// @dev The former wallet's bet for the seized account is a gift funded by the seller; the
    ///      lender's FLIP and the account's boon are untouched.
    function _sellerGift(uint32 lender) private {
        _acquire(owner, ownerId, lender);
        _openBetBuffer();
        address lenderAddr = _lenderAddress(lender);
        _grantBoon(ownerId, CURRENCY_FLIP, 2);
        uint256 boonLane = _lane(ownerId, CURRENCY_FLIP);
        _fundFlip(owner, 10_000);
        uint256 lenderFlip = coin.balanceOf(lenderAddr);

        (uint256 bet,) = _bet(owner, ownerId, CURRENCY_FLIP, 500, 2, 0);

        assertEq(uint32(bet), ownerId, "the bet belongs to the acquired account");
        assertEq(coin.balanceOf(owner), 9_000, "the seller funded the gift");
        assertEq(coin.balanceOf(lenderAddr), lenderFlip, "the lender's FLIP is untouched");
        assertEq(_lane(ownerId, CURRENCY_FLIP), boonLane, "the account's boon is untouched");
        assertTrue(game.walletIdOf_g3120(owner) != ownerId, "the seller funds from a fresh account");
    }
}
