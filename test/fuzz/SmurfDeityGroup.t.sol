// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {SmurfFixture} from "./SmurfFixture.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title SmurfDeityGroup -- one deity per main wallet, and issueDeityBoon by account ID
/// @notice A deity purchase scans the existing deities (at most 32, the VAULT and SDGNRS protocol
///         deities among them) and reverts `AlreadyOwnsDeityPass` when any shares the buyer's
///         main wallet (its payee: the owner for a smurf) (G5, F-game spec item 7). The buying
///         account keeps `HAS_DEITY_PASS` and every deity behaviour — tickets, boons, the price
///         paid that an early game over refunds — under its own ID; the NFT mints to the main
///         wallet, which therefore smites. `issueDeityBoon(deityId, recipientId, slot)` resolves
///         the deity account against the caller, requires an allocated recipient (`E` for 0 or
///         unallocated) and rejects `deityId == recipientId` (0 resolving to the caller) with
///         `SelfBoon` (item 8).
/// @dev The early-game-over refund loop credits `deityPassPricePaid[_deityIdAt(i)]` by deity ID
///      (GameOverModule); the suite checks that the price lands under the deity account's ID
///      rather than driving a game over.
contract SmurfDeityGroupTest is SmurfFixture {
    bytes32 private constant DEITY_BOON_ISSUED = keccak256("DeityBoonIssued(uint32,uint32,uint24,uint8,uint8)");
    uint256 private constant DEITY_PRICE_CAP = 30 ether;

    address private owner;
    uint32 private ownerId;
    uint32 private smurfId;
    uint32 private siblingId;
    address private other;
    uint32 private otherId;
    address private stranger;
    uint32 private strangerId;

    function setUp() public {
        _setUpSmurfFixture();
        (owner, ownerId) = _wallet("deity_owner");
        _grantSmurfBase(owner, 3);
        smurfId = _createSmurf(owner);
        siblingId = _createSmurf(owner);
        (other, otherId) = _wallet("deity_other");
        (stranger, strangerId) = _wallet("deity_stranger");
        // issueDeityBoon reads the preceding day's recorded word.
        RecyclingState.seedDailyWord(address(game), game.currentDayView() - 1, uint256(keccak256("deity_prev_word")));
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
    // One deity per main wallet
    // ---------------------------------------------------------------------

    function test_ProtocolDeitiesAreInTheScan() public view {
        assertEq(ext.x_deityCount(), 2, "VAULT and SDGNRS hold the protocol deities");
        assertEq(ext.x_deityIdAt(0), 1, "VAULT's deity ID");
        assertEq(ext.x_deityIdAt(1), 2, "SDGNRS's deity ID");
    }

    function test_SmurfDeityBlocksOwnerAndSiblings() public {
        _buyDeity(owner, smurfId, 3);
        assertEq(ext.x_deityCount(), 3, "the smurf deity is the third deity");

        _expectAlreadyOwns(owner, 0, 4); // the owner itself
        _expectAlreadyOwns(owner, siblingId, 4); // the owner's other smurf
        _expectAlreadyOwns(owner, smurfId, 4); // the deity account itself

        // A smurf created after the deity is in the same group.
        uint32 lateId = _createSmurf(owner);
        _expectAlreadyOwns(owner, lateId, 4);

        // An unrelated wallet still buys.
        _buyDeity(other, 0, 4);
        assertEq(deityPass.ownerOf(4), other, "the unrelated wallet holds its pass");
        assertEq(ext.x_deityCount(), 4, "four deities");
    }

    function test_OwnerDeityBlocksItsSmurfs() public {
        _buyDeity(owner, 0, 3);
        _expectAlreadyOwns(owner, smurfId, 4);
        _expectAlreadyOwns(owner, siblingId, 4);
        // An operator approved for the smurf hits the same group.
        address operator = makeAddr("deity_operator");
        vm.deal(operator, 100 ether);
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
        _expectAlreadyOwns(operator, smurfId, 4);
        // An unrelated wallet still buys.
        _buyDeity(other, 0, 4);
        assertEq(deityPass.ownerOf(4), other, "the unrelated wallet holds its pass");
    }

    function test_OperatorBuysForSmurf_GroupIsTheOwners() public {
        address operator = makeAddr("deity_operator");
        vm.deal(operator, 100 ether);
        // The operator's overpay refunds to its own ID, so it holds one.
        _giveWalletId(operator);
        vm.prank(owner);
        game.setOperatorApproval(smurfId, operator, true);
        _buyDeity(operator, smurfId, 3);
        assertEq(deityPass.ownerOf(3), owner, "the NFT mints to the smurf's main wallet");
        assertEq(deityPass.balanceOf(operator), 0, "the operator holds no pass");
        assertTrue(_fixtureHasDeity(smurfId), "HAS_DEITY_PASS on the smurf");
        _expectAlreadyOwns(owner, 0, 4);
        // The operator's own group is separate.
        _buyDeity(operator, 0, 4);
        assertEq(deityPass.ownerOf(4), operator, "the operator's own pass");
    }

    // ---------------------------------------------------------------------
    // Deity behaviour follows the deity account's ID
    // ---------------------------------------------------------------------

    function test_SmurfDeityStateFollowsItsId() public {
        uint24 passLevel = game.level() + 1;
        uint32 smurfEntries = _fixtureEntries(passLevel, smurfId);
        uint32 ownerEntries = _fixtureEntries(passLevel, owner);

        _buyDeity(owner, smurfId, 3);

        assertEq(deityPass.ownerOf(3), owner, "the NFT mints to the owner");
        assertTrue(_fixtureHasDeity(smurfId), "HAS_DEITY_PASS sits on the buying account's word");
        assertFalse(_fixtureHasDeity(owner), "the owner's word carries no deity bit");
        assertEq(ext.x_deityIdAt(2), smurfId, "the deity lane holds the smurf's ID");
        assertGt(_fixtureEntries(passLevel, smurfId), smurfEntries, "the perpetual tickets queue for the smurf");
        assertEq(_fixtureEntries(passLevel, owner), ownerEntries + 20, "main receives the conferred affiliate whale-pass entries");
        assertGt(ext.x_deityPricePaid(smurfId), 0, "the refundable price is held under the smurf's ID");
        assertEq(ext.x_deityPricePaid(ownerId), 0, "nothing under the owner's ID");
        assertEq(
            uint256(vm.load(address(game), _pricePaidSlot(smurfId))) & type(uint96).max,
            ext.x_deityPricePaid(smurfId),
            "layout: deityPassPricePaid slot"
        );
    }

    function test_OwnerIssuesBoonsAsTheSmurfDeity() public {
        _buyDeity(owner, smurfId, 3);
        uint24 day = game.currentDayView();

        vm.recordLogs();
        vm.prank(owner);
        game.issueDeityBoon(smurfId, strangerId, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != DEITY_BOON_ISSUED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), _fixtureId(smurfId), "the deity is the smurf account");
            assertEq(uint32(uint256(logs[i].topics[2])), game.walletIdOf(stranger), "the recipient");
            assertEq(uint256(logs[i].topics[3]), day, "today");
            issued = true;
        }
        assertTrue(issued, "the boon was issued");

        (,, uint8 smurfMask,,) = game.deityBoonDataById(smurfId);
        (,, uint8 ownerMask,,) = game.deityBoonData(owner);
        assertEq(smurfMask, 1, "slot 0 used on the smurf deity's ID");
        assertEq(ownerMask, 0, "the owner's own boon slots are untouched");

        // The owner's own account holds no deity bit, so it cannot issue as itself.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        game.issueDeityBoon(0, otherId, 1);

        // A stranger cannot issue as the smurf deity.
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.issueDeityBoon(smurfId, otherId, 1);
    }

    function test_OwnerSmitesWithTheSmurfsPass() public {
        _buyDeity(owner, smurfId, 3);
        vm.prank(address(game));
        coin.mintForGame(owner, 1_000);
        uint8 curse = game.curseCountOf(stranger);

        vm.prank(owner);
        game.smite(3, strangerId);
        assertEq(game.curseCountOf(stranger), curse + 2, "the smite added a stack");
        assertEq(coin.balanceOf(owner), 800, "the owner paid the smite FLIP");

        // Only the NFT holder smites.
        vm.prank(address(game));
        coin.mintForGame(stranger, 1_000);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        game.smite(3, otherId);
    }

    // ---------------------------------------------------------------------
    // issueDeityBoon: recipient and self-boon rules
    // ---------------------------------------------------------------------

    function test_IssueDeityBoon_RecipientZeroOrUnallocatedRevertsE() public {
        _buyDeity(owner, smurfId, 3);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.issueDeityBoon(smurfId, 0, 0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.issueDeityBoon(smurfId, 1_000_000, 0);
    }

    function test_IssueDeityBoon_SelfBoonBySmurfDeityId() public {
        _buyDeity(owner, smurfId, 3);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("SelfBoon()"));
        game.issueDeityBoon(smurfId, smurfId, 0);
    }

    function test_IssueDeityBoon_SelfBoonWhenZeroResolvesToCaller() public {
        _buyDeity(other, 0, 4);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("SelfBoon()"));
        game.issueDeityBoon(0, otherId, 0);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("SelfBoon()"));
        game.issueDeityBoon(otherId, otherId, 0);
    }

    function test_IssueDeityBoon_SmurfDeityMayBoonItsOwner() public {
        _buyDeity(owner, smurfId, 3);
        vm.recordLogs();
        vm.prank(owner);
        game.issueDeityBoon(smurfId, ownerId, 2);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != DEITY_BOON_ISSUED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), _fixtureId(smurfId), "the deity is the smurf account");
            assertEq(uint32(uint256(logs[i].topics[2])), game.walletIdOf(owner), "the owner receives the boon");
            issued = true;
        }
        assertTrue(issued, "the smurf deity boons its owner");
    }

    function test_IssueDeityBoon_SmurfDeityMayBoonASibling() public {
        _buyDeity(owner, smurfId, 3);
        vm.prank(owner);
        game.issueDeityBoon(smurfId, siblingId, 1);
        (,, uint8 mask,,) = game.deityBoonDataById(smurfId);
        assertEq(mask, 2, "slot 1 used");
    }
}
