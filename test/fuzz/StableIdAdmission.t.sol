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

/// @dev The shared hard cap supersedes the former 0.04-ETH admission threshold above 3b.
contract StableIdAdmissionTest is DeployProtocol {
    uint256 private constant CAP = 3_000_000_000;
    uint256 private constant SMALL_BUY = 0.0025 ether;
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
        vm.deal(alice, 100 ether); vm.deal(bob, 100 ether); vm.deal(operator, 100 ether);
        // Capacity tests exercise ticket admission with an already-known default affiliate.
        vm.prank(address(affiliate)); game.registerAffiliateOwner(address(vault), true);
    }
    function _seed(bytes memory data) private {
        bytes memory productionCode = address(game).code;
        vm.etch(address(game), type(StableIdAdmissionSeeder).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), productionCode);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }
    function _setCount(uint256 n) private { _seed(abi.encodeCall(StableIdAdmissionSeeder.setRegistryLength, (n))); }
    function _id(address who) private view returns (uint32) { return lens.walletIdOf(address(game), who); }
    function _claimable(address who, uint256 amount) private {
        _seed(abi.encodeCall(StableIdAdmissionSeeder.creditClaimable, (who, amount)));
        vm.deal(address(game), address(game).balance + amount);
    }
    function _buy(address who, uint256 qty, uint256 fresh, MintPaymentKind kind) private {
        vm.prank(who); game.purchase{value: fresh}(who, qty, 0, bytes32(0), kind, false);
    }

    function test_LastTwoIdsThenAtomicRejectionAtAnyPaidSize() public {
        _setCount(CAP - 2);
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        assertEq(_id(alice), CAP - 1);
        _buy(bob, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        assertEq(_id(bob), CAP);
        uint256 balance = operator.balance;
        vm.expectRevert(E_SELECTOR); _buy(operator, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        vm.expectRevert(E_SELECTOR); _buy(operator, 1600, 0.04 ether, MintPaymentKind.DirectEth);
        assertEq(_id(operator), 0); assertEq(operator.balance, balance);
        assertEq(game.entriesOwedView(1, operator), 0);
        // Previously registered IDs keep working at the same ordinary minimum.
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        assertEq(game.entriesOwedView(1, alice), 2);
    }

    function test_ClaimableCombinedAndAfkingFundingArePreservedOnFailure() public {
        _setCount(CAP);
        _claimable(alice, 0.04 ether + 1);
        vm.expectRevert(E_SELECTOR); _buy(alice, 1600, 0, MintPaymentKind.Claimable);
        assertEq(game.claimableWinningsOf(alice), 0.04 ether + 1);
        _claimable(bob, 0.0375 ether + 1);
        vm.expectRevert(E_SELECTOR); _buy(bob, 1600, SMALL_BUY, MintPaymentKind.Combined);
        assertEq(game.claimableWinningsOf(bob), 0.0375 ether + 1);
        vm.prank(operator); game.depositAfkingFunding{value: 0.04 ether}(operator);
        vm.expectRevert(E_SELECTOR); _buy(operator, 1600, 0, MintPaymentKind.DirectEth);
        assertEq(game.afkingFundingOf(operator), 0.04 ether);
        assertEq(_id(alice), 0); assertEq(_id(bob), 0); assertEq(_id(operator), 0);
    }

    function test_FlipPaymentCannotBypassCapAndBurnRollsBack() public {
        _setCount(CAP);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.openFlipWindow, ()));
        vm.prank(address(game)); coin.mintForGame(alice, 10000);
        vm.expectRevert(E_SELECTOR); vm.prank(alice); game.redeemFlip(alice, 1600);
        assertEq(coin.balanceOf(alice), 10000); assertEq(_id(alice), 0);
    }

    function test_OperatorIdentityDoesNotExemptNewBeneficiary() public {
        _buy(operator, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        _setCount(CAP);
        vm.prank(alice); game.setOperatorApproval(operator, true);
        vm.expectRevert(E_SELECTOR); vm.prank(operator);
        game.purchase{value: 0.04 ether}(alice, 1600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), 0);
    }

    function test_NewOperatorCanFundExistingBeneficiary() public {
        _buy(alice, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        uint32 id = _id(alice);
        _setCount(CAP);
        vm.prank(alice); game.setOperatorApproval(operator, true);
        vm.prank(operator); game.purchase{value: SMALL_BUY}(alice, 100, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), id); assertEq(_id(operator), 0);
        assertEq(game.entriesOwedView(1, alice), 2);
    }

    function test_OverpaymentSideBoxesAndBoonsCannotBypassCap() public {
        _setCount(CAP);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.grantPurchaseBoon, (alice)));
        vm.expectRevert(E_SELECTOR); _buy(alice, 100, 1 ether, MintPaymentKind.DirectEth);
        uint256 boxOrder = BoxOrderLib.boCustom(0.04 ether);
        vm.expectRevert(E_SELECTOR); vm.prank(alice);
        game.purchase{value: SMALL_BUY + 0.04 ether}(alice, 100, boxOrder, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), 0); assertEq(game.afkingFundingOf(alice), 0);
        // Box commitments remain lazy with respect to the buyer's ticket identity.
        vm.prank(alice); game.purchase{value: 0.04 ether}(alice, 0, boxOrder, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(_id(alice), 0);
    }

    function test_ClaimedPassCannotBypassCap() public {
        _setCount(CAP);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.awardHalfPasses, (alice, 4)));
        vm.expectRevert(E_SELECTOR); game.claimWhalePass(alice);
        assertEq(_id(alice), 0); assertEq(game.entriesOwedView(1, alice), 0);
        // Failed claim preserved the award; after capacity is available in the fixture it succeeds.
        _setCount(CAP - 1);
        game.claimWhalePass(alice);
        assertEq(_id(alice), CAP); assertEq(game.entriesOwedView(1, alice), 4);
    }

    function test_ForcedPrizeFailsSoftForNewOwnerAndStillPaysExistingOwner() public {
        _buy(bob, 100, SMALL_BUY, MintPaymentKind.DirectEth);
        _setCount(CAP);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.forcedPrizeDuringRng, (alice, 7, 4)));
        assertEq(_id(alice), 0); assertEq(game.entriesOwedView(7, alice), 0);
        _seed(abi.encodeCall(StableIdAdmissionSeeder.forcedPrizeDuringRng, (bob, 7, 4)));
        assertEq(game.entriesOwedView(7, bob), 4);
        assertTrue(game.rngLocked());
    }
}
