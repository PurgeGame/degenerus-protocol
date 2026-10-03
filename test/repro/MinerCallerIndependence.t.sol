// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";

/// @notice Automatic work depends on committed game state, never on caller privileges or credits.
contract MinerCallerIndependenceTest is DeployProtocol {
    using stdStorage for StdStorage;
    address private constant DONOR = address(0xD010);
    address private constant OUTSIDER = address(0xD011);
    address private constant OWNER = address(0xD012);
    bytes32 private constant CREDIT_SPENT = keccak256("MiddayRngCreditSpent(address,uint256,uint256)");
    uint256 private charge;

    modifier pricedBlock() {
        // Isolated Foundry test transactions reset their block base fee after setUp.
        vm.fee(1 gwei);
        _;
    }

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000 ether);
        vm.deal(address(game), 5000 ether);
        vm.deal(DONOR, 100 ether);
        vm.deal(OUTSIDER, 100 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _completeCurrentWork();
        assertTrue(game.rngComplete(), "real previous read cohort completed");
        assertFalse(game.advanceDue(), "real deployment reaches idle");
        assertFalse(game.boxesPending(), "no box can hide the empty-queue control");
        vm.fee(1 gwei);
        // The canonical local address file can leave the optional feed unpinned.
        stdstore.target(address(admin)).sig("linkEthPriceFeed()").checked_write(address(mockFeed));
        mockFeed.setUpdatedAt(vm.getBlockTimestamp());
        uint256 weiPerLink = admin.linkAmountToEth(1 ether);
        assertGt(weiPerLink, 0, "installed LINK feed makes the charge nonzero");
        charge = 201_000 * block.basefee * 6 * 1 ether / weiPerLink;
        assertGt(charge, 0);
        _grant(DONOR, charge * 3);
        _grant(address(game), charge * 5);
        _grant(address(0), charge * 7); // Automatic's sentinel must not act as a credit owner.
        vm.mockCall(address(vault), abi.encodeWithSignature("isVaultOwner(address)", OWNER), abi.encode(true));
    }

    function _completeCurrentWork() private {
        for (uint256 i; i < 500; ++i) {
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(id);
                if (!fulfilled) mockVRF.fulfillRandomWords(id, 0xC011AB1E);
            }
            if (game.rngComplete() && !game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip{gas: 15_000_000}();
        }
        revert("fixture: engine did not reach idle");
    }

    function _grant(address who, uint256 amount) private {
        vm.prank(address(admin));
        game.creditMiddayRng(who, amount);
    }

    function _buy(uint256 amount) private {
        vm.prank(OUTSIDER);
        game.purchase{value: amount}(
            OUTSIDER, 0, BoxOrderLib.boCustom(amount), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    function _selectionParity() private returns (uint8 action) {
        vm.prank(DONOR);
        action = game.nextMinerAction();
        vm.prank(OUTSIDER);
        assertEq(game.nextMinerAction(), action, "donor credit cannot select a different action");
        vm.prank(OWNER);
        assertEq(game.nextMinerAction(), action, "vault ownership cannot select a different action");
        vm.prank(DONOR);
        bool due = game.advanceDue();
        vm.prank(OUTSIDER);
        assertEq(game.advanceDue(), due, "public work discovery is caller independent");
        vm.prank(OWNER);
        assertEq(game.advanceDue(), due, "owner observes the same public work");
    }

    function _creditDigest() private view returns (bytes32) {
        return keccak256(abi.encode(game.middayRngCredits(DONOR), game.middayRngCredits(OUTSIDER),
            game.middayRngCredits(address(game)), game.middayRngCredits(address(0))));
    }

    function _commitmentDigest() private view returns (bytes32) {
        return keccak256(abi.encode(mockVRF.lastRequestId(), game.extsload(bytes32(0)),
            game.extsload(bytes32(uint256(3))), game.extsload(bytes32(uint256(4))),
            game.extsload(bytes32(uint256(5))), game.extsload(bytes32(uint256(33))),
            RecyclingState.readBuffer(address(game)), RecyclingState.writeBuffer(address(game)),
            game.rngComplete()));
    }

    function test_DonorCreditAloneCannotWakeAutomaticWork() public pricedBlock {
        assertEq(_selectionParity(), 0, "credit-only state remains Idle");
        bytes32 credits = _creditDigest();
        bytes32 state = _commitmentDigest();
        vm.prank(DONOR);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineFlip{gas: 15_000_000}();
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineFlip{gas: 15_000_000}();
        assertEq(_creditDigest(), credits);
        assertEq(_commitmentDigest(), state);
    }

    function test_ExplicitDonorRequestStillSupportsAnEmptyQueue() public pricedBlock {
        uint256 prior = mockVRF.lastRequestId();
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes4(keccak256("NoPendingLootbox()")));
        game.requestLootboxRng();
        vm.prank(DONOR);
        game.requestLootboxRng();
        assertGt(mockVRF.lastRequestId(), prior, "explicit donor request reaches the coordinator");
        _assertOnlyDonorCharged();
        assertFalse(game.rngLocked(), "explicit empty request remains a midday cohort");
        assertFalse(game.rngComplete(), "even an empty cohort must publish and complete");
    }

    function test_AutomaticBelowThresholdNeverSpendsCallerOrSentinelCredit() public pricedBlock {
        _buy(0.5 ether);
        assertEq(_selectionParity(), 0, "below-threshold value is not automatic work");
        bytes32 credits = _creditDigest();
        bytes32 state = _commitmentDigest();
        vm.prank(DONOR);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineFlip{gas: 15_000_000}();
        assertEq(_creditDigest(), credits, "automatic donor call cannot redeem credit");
        assertEq(_commitmentDigest(), state, "automatic call cannot waive the value threshold");
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineFlip{gas: 15_000_000}();
        assertEq(_creditDigest(), credits, "automatic sentinel has no spending authority");
        assertEq(_commitmentDigest(), state);
        vm.prank(DONOR);
        game.requestLootboxRng();
        _assertOnlyDonorCharged();
        assertGt(mockVRF.lastRequestId(), 0);
        assertNotEq(_commitmentDigest(), state, "explicit donation credit still waives the threshold");
    }

    function test_ThresholdRequestCommitsTheSameCohortForEveryCaller() public pricedBlock {
        _buy(1.1 ether);
        assertGt(_selectionParity(), 0);
        uint256 snap = vm.snapshotState();
        bytes32 expected = _automaticRequest(DONOR);
        assertTrue(vm.revertToStateAndDelete(snap));
        assertEq(_automaticRequest(OUTSIDER), expected, "caller identity cannot alter the commitment");
    }

    function _automaticRequest(address caller) private returns (bytes32) {
        bytes32 credits = _creditDigest();
        uint256 prior = mockVRF.lastRequestId();
        vm.recordLogs();
        vm.prank(caller);
        game.mineFlip{gas: 15_000_000}();
        assertGt(mockVRF.lastRequestId(), prior, "automatic path actually requested a word");
        assertEq(_creditDigest(), credits, "automatic request does not spend any credit");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0) {
                assertNotEq(logs[i].topics[0], CREDIT_SPENT, "no implicit credit redemption event");
            }
        }
        return _commitmentDigest();
    }

    function test_ExpiredTransportRequestDoesNotSelectOwnerSpecificMinerWork() public pricedBlock {
        vm.prank(DONOR);
        game.requestLootboxRng();
        uint256 id = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 20 hours + 2);
        assertTrue(vault.isVaultOwner(OWNER), "control: caller holds the retry role");
        assertEq(_selectionParity(), 2, "every miner waits for the same unanswered request");
        vm.prank(OWNER);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip{gas: 15_000_000}();
        vm.prank(DONOR);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip{gas: 15_000_000}();
        assertEq(mockVRF.lastRequestId(), id, "retry is a separate authorized transport action");
        _assertOnlyDonorCharged();
    }

    function _assertOnlyDonorCharged() private view {
        assertEq(game.middayRngCredits(DONOR), charge * 2, "one explicit priced charge");
        assertEq(game.middayRngCredits(OUTSIDER), 0);
        assertEq(game.middayRngCredits(address(game)), charge * 5);
        assertEq(game.middayRngCredits(address(0)), charge * 7);
    }
}
