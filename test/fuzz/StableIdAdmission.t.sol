// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev Setup uses declared storage rather than hand-computed slots. Every purchase
///      and pass claim runs the restored production Game and delegatecall modules.
contract StableIdAdmissionSeeder is DegenerusGameStorage {
    function setRegistryLength(uint256 count) external {
        assembly ("memory-safe") { sstore(ticketOwners.slot, count) }
    }

    function creditClaimable(address who, uint256 amount) external {
        _creditClaimable(who, amount);
        claimablePool += uint128(amount);
    }

    function openFlipWindow() external { _setTicketRedemptionOpen(true); }

    function awardHalfPasses(address who, uint256 count) external { whalePassClaims[who] += count; }

    function grantPurchaseBoon(address who) external {
        boonPacked[who].slot0 |= (uint256(3) << BP_PURCHASE_TIER_SHIFT)
            | (uint256(_simulatedDayIndex()) << BP_PURCHASE_DAY_SHIFT);
    }

    function forcedPrizeDuringRng(address who, uint24 target, uint32 entries) external {
        rngLockedFlag = true;
        _queueEntries(who, target, entries, true);
    }
}

contract StableIdAdmissionTest is DeployProtocol {
    uint256 private constant CUTOFF = 3_000_000_000;
    uint256 private constant SMALL_BUY = 0.0025 ether;
    uint256 private constant TICKET_PRICE = 0.01 ether;
    uint256 private constant FIRST_BUY = 0.04 ether;
    uint256 private constant FIRST_QTY = 1600;
    uint256 private constant FIRST_ENTRIES = 16;
    bytes4 private constant E_SELECTOR = bytes4(keccak256("E()"));

    DegenerusGameLens private lens;
    address private alice;
    address private bob;
    address private operator;

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        alice = makeAddr("stable-admission-alice");
        bob = makeAddr("stable-admission-bob");
        operator = makeAddr("stable-admission-operator");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(operator, 100 ether);
        assertEq(game.mintPrice(), TICKET_PRICE, "fixture ticket price");
    }

    function _seed(bytes memory data) private {
        bytes memory productionCode = address(game).code;
        vm.etch(address(game), type(StableIdAdmissionSeeder).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), productionCode);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function _setCount(uint256 count) private {
        _seed(abi.encodeCall(StableIdAdmissionSeeder.setRegistryLength, (count)));
    }

    function _id(address who) private view returns (uint32) {
        return lens.walletIdOf(address(game), who);
    }

    function _claimable(address who, uint256 amount) private {
        _seed(abi.encodeCall(StableIdAdmissionSeeder.creditClaimable, (who, amount)));
        vm.deal(address(game), address(game).balance + amount);
    }

    function _buy(address who, uint256 qty, uint256 fresh, MintPaymentKind kind) private {
        vm.prank(who);
        game.purchase{value: fresh}(who, qty, 0, bytes32(0), kind, false);
    }

    function test_LastAutomaticSmallBuyIsIdThreeBillion() public {
        _setCount(CUTOFF - 1);
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        assertEq(_id(alice), CUTOFF, "the boundary ID keeps the ordinary minimum");
        assertEq(game.entriesOwedView(1, alice), 1);

        vm.expectRevert(E_SELECTOR);
        _buy(bob, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        assertEq(_id(bob), 0, "a rejected ticket leg allocated no ID");
        assertEq(game.entriesOwedView(1, bob), 0);
    }

    function test_ExactFourHundredthsTicketLegCreatesNextId() public {
        _setCount(CUTOFF);
        vm.expectRevert(E_SELECTOR);
        _buy(alice, FIRST_QTY - 1, FIRST_BUY - TICKET_PRICE / 400, MintPaymentKind.DirectEth);
        assertEq(_id(alice), 0, "one unit under the floor allocates no ID");
        uint256 beforeBalance = alice.balance;
        _buy(alice, FIRST_QTY, FIRST_BUY, MintPaymentKind.DirectEth);
        assertEq(_id(alice), CUTOFF + 1);
        assertEq(alice.balance, beforeBalance - FIRST_BUY, "ordinary purchase only; no extra registration fee");
        assertEq(game.entriesOwedView(1, alice), FIRST_ENTRIES);
        assertEq(game.afkingFundingOf(alice), 0, "all payment priced as tickets");
    }

    function test_ExistingOwnerKeepsSmallBuyEvenAtNamespaceCeiling() public {
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        uint32 originalId = _id(alice);
        _setCount(type(uint32).max);
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        assertEq(_id(alice), originalId);
        assertEq(game.entriesOwedView(1, alice), 2);
    }

    function test_ClaimablePaymentUsesTicketValueNotFreshEth() public {
        _setCount(CUTOFF);
        _claimable(alice, FIRST_BUY + 1);
        vm.expectRevert(E_SELECTOR);
        _buy(alice, 100, 0, MintPaymentKind.Claimable);
        assertEq(game.claimableWinningsOf(alice), FIRST_BUY + 1, "rejected buy preserves all winnings");
        _buy(alice, FIRST_QTY, 0, MintPaymentKind.Claimable);
        assertEq(_id(alice), CUTOFF + 1);
        assertEq(game.claimableWinningsOf(alice), 1, "normal claimable sentinel remains");
        assertEq(game.entriesOwedView(1, alice), FIRST_ENTRIES);
    }

    function test_CombinedPaymentUsesEntireTicketValue() public {
        _setCount(CUTOFF);
        _claimable(alice, 0.0375 ether + 1);
        vm.expectRevert(E_SELECTOR);
        _buy(alice, 100, 0.001 ether, MintPaymentKind.Combined);
        assertEq(_id(alice), 0);
        assertEq(game.claimableWinningsOf(alice), 0.0375 ether + 1);
        _buy(alice, FIRST_QTY, SMALL_BUY, MintPaymentKind.Combined);
        assertEq(_id(alice), CUTOFF + 1);
        assertEq(game.claimableWinningsOf(alice), 1);
        assertEq(game.entriesOwedView(1, alice), FIRST_ENTRIES);
    }

    function test_PrepaidAfkingCanFundFirstTicketPurchase() public {
        _setCount(CUTOFF);
        vm.prank(alice);
        game.depositAfkingFunding{value: FIRST_BUY}(alice);
        assertEq(_id(alice), 0, "prepayment alone remains lazy");
        _buy(alice, FIRST_QTY, 0, MintPaymentKind.DirectEth);
        assertEq(_id(alice), CUTOFF + 1);
        assertEq(game.afkingFundingOf(alice), 0);
        assertEq(game.entriesOwedView(1, alice), FIRST_ENTRIES);
    }

    function test_FlipPaymentUsesTheSameEthEquivalentFloor() public {
        _setCount(CUTOFF);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.openFlipWindow, ()));
        vm.prank(address(game));
        coin.mintForGame(alice, 10_000 ether);
        uint256 beforeBalance = coin.balanceOf(alice);
        vm.expectRevert(E_SELECTOR);
        vm.prank(alice);
        game.redeemFlip(alice, 100);
        assertEq(coin.balanceOf(alice), beforeBalance, "rejected redeem burns nothing");
        assertEq(_id(alice), 0);
        vm.prank(alice);
        game.redeemFlip(alice, FIRST_QTY);
        assertEq(_id(alice), CUTOFF + 1);
        assertEq(coin.balanceOf(alice), beforeBalance - 4_000 ether);
        assertEq(game.entriesOwedView(1, alice), FIRST_ENTRIES);
    }

    function test_RegisteredOperatorDoesNotExemptUnregisteredBeneficiary() public {
        _buy(operator, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        _setCount(CUTOFF);
        vm.prank(alice);
        game.setOperatorApproval(operator, true);
        vm.expectRevert(E_SELECTOR);
        vm.prank(operator);
        game.purchase{value: SMALL_BUY}(alice, 100, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), 0);
        vm.prank(operator);
        game.purchase{value: FIRST_BUY}(alice, FIRST_QTY, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), CUTOFF + 1, "ID belongs to the beneficiary");
    }

    function test_UnregisteredOperatorCanFundRegisteredBeneficiarySmallBuy() public {
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        uint32 originalId = _id(alice);
        _setCount(CUTOFF);
        vm.prank(alice);
        game.setOperatorApproval(operator, true);
        vm.prank(operator);
        game.purchase{value: SMALL_BUY}(alice, 100, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), originalId);
        assertEq(_id(operator), 0, "payer is not assigned an ID");
        assertEq(game.entriesOwedView(1, alice), 2);
    }

    function test_ExcessEthDoesNotQualifyAnUndersizedTicketLeg() public {
        _setCount(CUTOFF);
        uint256 beforeBalance = alice.balance;
        vm.expectRevert(E_SELECTOR);
        _buy(alice, 100, 1 ether, MintPaymentKind.DirectEth);
        assertEq(_id(alice), 0);
        assertEq(alice.balance, beforeBalance);
        assertEq(game.afkingFundingOf(alice), 0);
    }

    function test_SideBoxSpendDoesNotQualifyAnUndersizedTicketLeg() public {
        _setCount(CUTOFF);
        uint256 boxOrder = BoxOrderLib.boCustom(FIRST_BUY);
        vm.expectRevert(E_SELECTOR);
        vm.prank(alice);
        game.purchase{value: SMALL_BUY + FIRST_BUY}(
            alice, 100, boxOrder, bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertEq(_id(alice), 0);
        assertEq(game.entriesOwedView(1, alice), 0);
        // A box-only buy remains allowed and does not eagerly allocate an owner ID.
        vm.prank(alice);
        game.purchase{value: FIRST_BUY}(alice, 0, boxOrder, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), 0, "box commitments remain lazy above the cutoff");
    }

    function test_BoonDoesNotInflateTicketValueToAdmissionFloor() public {
        _setCount(CUTOFF);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.grantPurchaseBoon, (alice)));
        // 0.032 ETH plus a 25% boon would award the entries of 0.04 ETH, but its
        // priced ticket leg is still below the first-purchase floor.
        vm.expectRevert(E_SELECTOR);
        _buy(alice, 1280, 0.032 ether, MintPaymentKind.DirectEth);
        assertEq(_id(alice), 0);
        _buy(alice, FIRST_QTY, FIRST_BUY, MintPaymentKind.DirectEth);
        assertEq(game.entriesOwedView(1, alice), 20, "failed buy did not consume the 25% boon");
    }

    function test_DeferredPassClaimStillRegistersFreelyAboveCutoff() public {
        _seed(abi.encodeCall(StableIdAdmissionSeeder.awardHalfPasses, (alice, 4)));
        _setCount(CUTOFF);
        uint256 beforeBalance = alice.balance;
        game.claimWhalePass(alice);
        assertEq(_id(alice), CUTOFF + 1);
        assertEq(alice.balance, beforeBalance, "earned pass has no added fee");
        assertEq(game.entriesOwedView(1, alice), 4);
        assertEq(game.entriesOwedView(100, alice), 4);
    }

    function test_ForcedTicketPrizeDoesNotBlockRngAfterCutoff() public {
        _setCount(CUTOFF);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.forcedPrizeDuringRng, (alice, 7, 4)));
        assertEq(_id(alice), CUTOFF + 1, "forced reward freely assigns its first ID");
        assertEq(game.entriesOwedView(7, alice), 4, "all awarded entries are owed");
        assertTrue(game.rngLocked(), "award succeeded within the locked settlement");
    }
}
