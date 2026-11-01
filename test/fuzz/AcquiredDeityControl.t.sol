// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {AccountFixture} from "./AccountFixture.t.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title AcquiredDeityControl -- one deity per payee wallet, giveBoon by account ID, and deity
///        control following an account through seizure
/// @notice A deity purchase scans the existing deities (at most 32, the VAULT and SDGNRS protocol
///         deities among them) and reverts `AlreadyOwnsDeityPass` when any shares the buyer's payee.
///         The buying account keeps `HAS_DEITY_PASS` and every deity behaviour (tickets, boons,
///         the refundable price paid) under its own ID; the NFT mints to the payee, which smites.
///         `giveBoon(deityId, recipientId, slot)` resolves the deity account against the caller,
///         requires an allocated recipient (`E` for 0 or unallocated) and rejects
///         `deityId == recipientId` (0 resolving to the caller) with `SelfBoon`. A seized deity
///         account's pass moves to the lender; the seller can no longer boon or smite with it, and
///         the seller's fresh account may buy a new deity.
contract AcquiredDeityControlTest is AccountFixture {
    bytes32 private constant DEITY_BOON_ISSUED = keccak256("DeityBoonIssued(uint32,uint32,uint24,uint8,uint8)");
    uint256 private constant DEITY_PRICE_CAP = 30 ether;

    address private owner;
    uint32 private ownerId;
    address private other;
    uint32 private otherId;
    address private stranger;
    uint32 private strangerId;
    address private operator;

    function setUp() public {
        _setUpAccountFixture();
        (owner, ownerId) = _wallet("deity_owner");
        (other, otherId) = _wallet("deity_other");
        (stranger, strangerId) = _wallet("deity_stranger");
        operator = makeAddr("deity_operator");
        vm.deal(operator, 100 ether);
        // giveBoon reads the preceding day's recorded word.
        RecyclingState.seedDailyWord(address(game), game.currentDayView_g542950() - 1, uint256(keccak256("deity_prev_word")));
    }

    function _buyDeity(address caller, uint32 id, uint8 symbol) private {
        vm.prank(caller);
        game.purchaseDeityPass{value: DEITY_PRICE_CAP}(id, symbol, bytes32(0));
    }

    function _expectAlreadyOwns(address caller, uint32 id, uint8 symbol) private {
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSignature("AlreadyOwnsDeityPass()"));
        game.purchaseDeityPass{value: DEITY_PRICE_CAP}(id, symbol, bytes32(0));
    }

    function _pricePaidSlot(uint32 id) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), GameSlots.DEITY_PASS_PRICE_PAID));
    }

    // ---------------------------------------------------------------------
    // One deity per payee wallet
    // ---------------------------------------------------------------------

    function test_ProtocolDeitiesAreInTheScan() public view {
        assertEq(ext.x_deityCount(), 2, "VAULT and SDGNRS hold the protocol deities");
        assertEq(ext.x_deityIdAt(0), 1, "VAULT's deity ID");
        assertEq(ext.x_deityIdAt(1), 2, "SDGNRS's deity ID");
    }

    function test_WalletDeityBlocksASecondPurchase() public {
        _buyDeity(owner, 0, 3);
        assertEq(ext.x_deityCount(), 3, "the wallet's deity is the third deity");
        _expectAlreadyOwns(owner, 0, 4);
        _expectAlreadyOwns(owner, ownerId, 4);
        // An operator approved for the account hits the same payee.
        vm.prank(owner);
        game.setOperatorApproval(ownerId, operator, true);
        _expectAlreadyOwns(operator, ownerId, 4);
        // An unrelated wallet still buys.
        _buyDeity(other, 0, 4);
        assertEq(deityPass.ownerOf(4), other, "the unrelated wallet holds its pass");
        assertEq(ext.x_deityCount(), 4, "four deities");
    }

    function test_OperatorBuysForAccount_NftMintsToItsWallet() public {
        // The operator's overpay refunds to its own ID, so it holds one.
        _giveWalletId(operator);
        vm.prank(owner);
        game.setOperatorApproval(ownerId, operator, true);
        _buyDeity(operator, ownerId, 3);
        assertEq(deityPass.ownerOf(3), owner, "the NFT mints to the account's wallet");
        assertEq(deityPass.balanceOf(operator), 0, "the operator holds no pass");
        assertTrue(_fixtureHasDeity(ownerId), "HAS_DEITY_PASS on the account");
        // The operator's own payee is separate.
        _buyDeity(operator, 0, 4);
        assertEq(deityPass.ownerOf(4), operator, "the operator's own pass");
    }

    // ---------------------------------------------------------------------
    // Deity behaviour follows the deity account's ID
    // ---------------------------------------------------------------------

    function test_DeityStateFollowsItsId() public {
        uint24 passLevel = game.currentLvl() + 1;
        uint32 entries = _fixtureEntries(passLevel, ownerId);

        _buyDeity(owner, 0, 3);

        assertEq(deityPass.ownerOf(3), owner, "the NFT mints to the wallet");
        assertTrue(_fixtureHasDeity(ownerId), "HAS_DEITY_PASS sits on the buying account's word");
        assertEq(ext.x_deityIdAt(2), ownerId, "the deity lane holds the account's ID");
        assertGt(_fixtureEntries(passLevel, ownerId), entries, "the perpetual tickets queue for the account");
        assertGt(ext.x_deityPricePaid(ownerId), 0, "the refundable price is held under the account's ID");
        assertEq(
            uint256(vm.load(address(game), _pricePaidSlot(ownerId))) & type(uint96).max,
            ext.x_deityPricePaid(ownerId),
            "layout: deityPassPricePaid slot"
        );
    }

    function test_DeityIssuesBoonsAndOnlyTheHolderSmites() public {
        _buyDeity(owner, 0, 3);
        uint24 day = game.currentDayView_g542950();

        vm.recordLogs();
        vm.prank(owner);
        game.giveBoon(ownerId, strangerId, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != DEITY_BOON_ISSUED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), ownerId, "the deity account");
            assertEq(uint32(uint256(logs[i].topics[2])), strangerId, "the recipient");
            assertEq(uint256(logs[i].topics[3]), day, "today");
            issued = true;
        }
        assertTrue(issued, "the boon was issued");
        (,, uint8 mask,,) = game.deityBoonDataById(ownerId);
        assertEq(mask, 1, "slot 0 used on the deity's ID");

        // A wallet without a deity cannot issue as itself; a stranger cannot issue as the deity.
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        game.giveBoon(0, strangerId, 1);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.giveBoon(ownerId, otherId, 1);

        vm.prank(address(game));
        coin.mintForGame_g152734(owner, 1_000);
        uint8 curse = game.curseCountOf(stranger);
        vm.prank(owner);
        game.smite(3, strangerId);
        assertEq(game.curseCountOf(stranger), curse + 2, "the smite added a stack");
        assertEq(coin.balanceOf(owner), 800, "the holder paid the smite FLIP");

        vm.prank(address(game));
        coin.mintForGame_g152734(stranger, 1_000);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        game.smite(3, otherId);
    }

    // ---------------------------------------------------------------------
    // giveBoon: recipient and self-boon rules
    // ---------------------------------------------------------------------

    function test_IssueDeityBoon_RecipientZeroOrUnallocatedRevertsE() public {
        _buyDeity(owner, 0, 3);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.giveBoon(ownerId, 0, 0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.giveBoon(ownerId, 1_000_000, 0);
    }

    function test_IssueDeityBoon_SelfBoonRejected() public {
        _buyDeity(other, 0, 4);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("SelfBoon()"));
        game.giveBoon(0, otherId, 0);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("SelfBoon()"));
        game.giveBoon(otherId, otherId, 0);
    }

    // ---------------------------------------------------------------------
    // Acquired deity control
    // ---------------------------------------------------------------------

    function test_AcquiredDeity_Vault() public { _acquiredDeity(VAULT_ID); }

    function test_AcquiredDeity_Sdgnrs() public { _acquiredDeity(SDGNRS_ID); }

    function _acquiredDeity(uint32 lender) private {
        address lenderAddr = _lenderAddress(lender);
        _buyDeity(owner, 0, 3);
        uint256 pricePaid = ext.x_deityPricePaid(ownerId);
        ext.x_setBalances(ownerId, 1, 0); // the purchase's change would otherwise repay
        _acquire(owner, ownerId, lender);

        assertEq(deityPass.ownerOf(3), lenderAddr, "the pass follows its account to the lender");
        assertEq(deityPass.balanceOf(owner), 0);
        assertTrue(_fixtureHasDeity(ownerId), "the deity stays on the account's ID");
        assertEq(ext.x_deityPricePaid(ownerId), pricePaid, "the refundable price stays with the account");
        assertEq(ext.x_deityIdAt(2), ownerId, "the deity lane keeps the account");

        // The seller and its former operator lost control.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.giveBoon(ownerId, strangerId, 0);
        vm.prank(address(game));
        coin.mintForGame_g152734(owner, 1_000);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        game.smite(3, strangerId);

        // The lender already holds a protocol deity, so the acquired account cannot buy another.
        vm.deal(lenderAddr, lenderAddr.balance + DEITY_PRICE_CAP);
        _expectAlreadyOwns(lenderAddr, ownerId, 5);

        // The seller's fresh account inherits no deity and may buy one.
        uint32 fresh = _giveWalletId(owner);
        assertTrue(fresh != ownerId);
        assertFalse(_fixtureHasDeity(fresh), "no deity inherited");
        _buyDeity(owner, 0, 7);
        assertEq(deityPass.ownerOf(7), owner, "the seller's new pass");
        assertEq(game.walletIdOf_g3120(owner), fresh);
        assertTrue(_fixtureHasDeity(fresh));
    }
}
