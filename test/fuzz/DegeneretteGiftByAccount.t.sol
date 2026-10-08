// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {SmurfFixture} from "./SmurfFixture.t.sol";
import {IDegenerusQuests} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegeneretteGiftByAccount -- the Degenerette door's gift and acting-for-an-account split
/// @notice `placeDegeneretteBet(id, ...)` resolves account `id` against the caller (F-game spec item
///         6). A caller not authorized for the account makes a gift: the caller's fresh ETH,
///         claimable and FLIP fund it, the caller earns the quest, the bet belongs to `id`, and the
///         recipient's stake boon is never read. A gift to an unallocated ID reverts `E`. A caller
///         authorized for the account (a smurf's owner, an approved operator) acts for it: the
///         account's claimable funds the shortfall, FLIP burns from the account's payee (the
///         owner), the account earns the quest, and the account's boon is spent.
/// @dev Boons are written straight into `boonPacked[id].slot1` (the DegeneretteBoonStake layout:
///      per-currency 24-bit lanes at 184 + 24 * currency, [day:21 | deity:1 | tier:2]).
contract DegeneretteGiftByAccountTest is SmurfFixture {
    uint8 private constant CURRENCY_ETH = 0;
    uint8 private constant CURRENCY_FLIP = 1;
    uint8 private constant HERO = 3;
    uint256 private constant BP_DEGEN_LANE0_SHIFT = 184;
    uint256 private constant BP_LANE_MASK = 0xFFFFFF;
    uint256 private constant BET_STAKE_SHIFT = 60;

    address private owner;
    uint32 private ownerId;
    uint32 private smurfId;
    address private recipient;
    uint32 private recipientId;
    address private giver;
    uint32 private giverId;
    address private operator;

    function setUp() public {
        _setUpSmurfFixture();
        (owner, ownerId) = _wallet("gift_owner");
        _grantSmurfBase(owner, 1);
        smurfId = _createSmurf(owner);
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
        uint256 lane = (uint256(game.currentDayView() & 0x1FFFFF) << 3) | tier;
        s1 = (s1 & ~(BP_LANE_MASK << shift)) | (lane << shift);
        vm.store(address(game), _boonSlot1(id), bytes32(s1));
        assertEq(_lane(id, currency) & 3, tier, "fixture: boon written");
    }

    function _fundFlip(address who, uint256 amount) private {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _expectQuest(uint32 earner, uint32 notEarner) private {
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette.selector, earner), 1);
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette.selector, notEarner), 0);
    }

    /// @dev Place a bet as `caller` for account `id`; returns the stored bet word.
    function _bet(address caller, uint32 id, uint8 currency, uint128 perSpin, uint8 spins, uint256 value)
        private
        returns (uint256 bet, uint32 betOwner)
    {
        vm.recordLogs();
        vm.prank(caller);
        game.placeDegeneretteBet{value: value}(id, currency, perSpin, spins, HERO);
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

    /// @dev A stranger's FLIP bet for a smurf: the stranger's FLIP burns, the owner's does not; the
    ///      smurf's boon is untouched; the stranger earns the quest; the bet is the smurf's.
    function test_StrangerFlipBetForSmurf_IsAGiftFundedByTheCaller() public {
        _grantBoon(smurfId, CURRENCY_FLIP, 3);
        uint256 boonLane = _lane(smurfId, CURRENCY_FLIP);
        _fundFlip(giver, 10_000);
        _fundFlip(owner, 10_000);

        _expectQuest(giverId, smurfId);
        (uint256 bet, uint32 betOwner) = _bet(giver, smurfId, CURRENCY_FLIP, 1_000, 3, 0);

        assertEq(uint32(bet), smurfId, "the bet belongs to the smurf's ID");
        assertEq(betOwner, _fixtureId(smurfId), "the placement event names the smurf key");
        assertEq(coin.balanceOf(giver), 7_000, "the giver's FLIP burned");
        assertEq(coin.balanceOf(owner), 10_000, "the owner's FLIP is untouched");
        assertEq(_lane(smurfId, CURRENCY_FLIP), boonLane, "the smurf's boon is untouched");
        assertEq(_stakeUnits(bet), 1_000, "no boon boost on a gift");
    }

    /// @dev A gift caller with no ID yet registers as the paying funder and earns the quest.
    function test_UnregisteredGiverRegistersAndEarnsTheQuest() public {
        address fresh = makeAddr("gift_fresh_giver");
        vm.deal(fresh, 1 ether);
        assertEq(game.walletIdOf(fresh), 0, "fixture: unregistered giver");
        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette.selector, recipientId), 0);
        (uint256 bet,) = _bet(fresh, recipientId, CURRENCY_ETH, 0.01 ether, 2, 0.02 ether);
        uint32 freshId = game.walletIdOf(fresh);
        assertGt(freshId, 0, "the paying funder registered");
        assertEq(uint32(bet), recipientId, "the bet belongs to the recipient");
    }

    function test_GiftToUnallocatedId_RevertsE() public {
        uint32 unallocated = 1_000_000;
        vm.prank(giver);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.placeDegeneretteBet{value: 0.01 ether}(unallocated, CURRENCY_ETH, 0.01 ether, 1, HERO);
    }

    // ---------------------------------------------------------------------
    // Acting for an account (not a gift)
    // ---------------------------------------------------------------------

    /// @dev The owner's FLIP bet for its smurf: the owner's FLIP burns (payee), the smurf earns the
    ///      quest, and the smurf's boon is spent on the bet.
    function test_OwnerFlipBetForSmurf_BurnsOwnerFlipAndSpendsSmurfBoon() public {
        _grantBoon(smurfId, CURRENCY_FLIP, 3);
        _fundFlip(owner, 10_000);

        _expectQuest(smurfId, ownerId);
        (uint256 bet, uint32 betOwner) = _bet(owner, smurfId, CURRENCY_FLIP, 1_000, 3, 0);

        assertEq(uint32(bet), smurfId, "the bet belongs to the smurf's ID");
        assertEq(betOwner, _fixtureId(smurfId), "the placement event names the smurf key");
        assertEq(coin.balanceOf(owner), 7_000, "the owner's FLIP burned");
        assertEq(_lane(smurfId, CURRENCY_FLIP) & 3, 0, "the smurf's boon was spent");
        assertGt(_stakeUnits(bet), 1_000, "the boon boosted the packed stake");
    }

    /// @dev The owner's ETH bet for its smurf with no fresh ETH: the smurf's claimable funds it,
    ///      the owner's ledger does not; the smurf earns the quest; the smurf's ETH boon is spent.
    function test_OwnerEthBetForSmurf_SmurfClaimableFundsIt() public {
        _grantBoon(smurfId, CURRENCY_ETH, 1);
        ext.x_creditClaimable(smurfId, 1 ether);
        ext.x_creditClaimable(ownerId, 1 ether);
        uint256 smurfClaimable = _fixtureClaimable(smurfId);
        uint256 ownerClaimable = _fixtureClaimable(owner);
        uint256 ownerEth = owner.balance;

        _expectQuest(smurfId, ownerId);
        (uint256 bet,) = _bet(owner, smurfId, CURRENCY_ETH, 0.01 ether, 4, 0);

        assertEq(uint32(bet), smurfId, "the bet belongs to the smurf's ID");
        assertEq(smurfClaimable - _fixtureClaimable(smurfId), 0.04 ether, "the smurf's claimable funded it");
        assertEq(_fixtureClaimable(owner), ownerClaimable, "the owner's claimable is untouched");
        assertEq(owner.balance, ownerEth, "no fresh ETH moved");
        assertEq(_lane(smurfId, CURRENCY_ETH) & 3, 0, "the smurf's boon was spent");
        assertGt(_stakeUnits(bet), 0.01 ether / 1 gwei, "the boon boosted the packed stake");
    }

    /// @dev An operator approved for the smurf acts for it: FLIP burns from the owner (the
    ///      payee), never from the operator, and the smurf earns the quest.
    function test_OperatorFlipBetForSmurf_BurnsFromThePayee() public {
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
        _fundFlip(owner, 10_000);
        _fundFlip(operator, 10_000);

        vm.expectCall(address(quests), abi.encodeWithSelector(IDegenerusQuests.handleDegenerette.selector, smurfId), 1);
        (uint256 bet,) = _bet(operator, smurfId, CURRENCY_FLIP, 500, 2, 0);

        assertEq(uint32(bet), smurfId, "the bet belongs to the smurf's ID");
        assertEq(coin.balanceOf(owner), 9_000, "the owner's FLIP burned");
        assertEq(coin.balanceOf(operator), 10_000, "the operator's FLIP is untouched");
    }

    /// @dev An operator approved on the OWNER's ID is a stranger to the smurf: its bet for the
    ///      smurf is a gift it funds itself.
    function test_OwnerIdOperatorBetForSmurf_IsAGift() public {
        vm.prank(owner);
        game.setOperatorApproval(0, operator, true);
        _fundFlip(owner, 10_000);
        _fundFlip(operator, 10_000);
        _grantBoon(smurfId, CURRENCY_FLIP, 2);
        uint256 boonLane = _lane(smurfId, CURRENCY_FLIP);

        (uint256 bet,) = _bet(operator, smurfId, CURRENCY_FLIP, 500, 2, 0);

        assertEq(uint32(bet), smurfId, "the bet belongs to the smurf's ID");
        assertEq(coin.balanceOf(operator), 9_000, "the gifting operator's FLIP burned");
        assertEq(coin.balanceOf(owner), 10_000, "the owner's FLIP is untouched");
        assertEq(_lane(smurfId, CURRENCY_FLIP), boonLane, "the smurf's boon is untouched");
        assertGt(game.walletIdOf(operator), 0, "the gifting operator registered as the funder");
    }
}
