// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {LiquidationQuote} from "../../contracts/interfaces/ILiquidation.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {Vm} from "forge-std/Vm.sol";

contract RngReviewRejectEther {
    receive() external payable { revert("reject payment"); }
}

/// @dev Real purchases, requests, callbacks and mineFlip. Only initial funds/VRF are mocked;
/// no queue, cursor, ownership, word or completion state is forged.
contract RngStructuralLivenessReviewTest is DeployProtocol {
    bytes32 private constant BOX = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant BET = keccak256("DegeneretteResolved(uint32,uint32,uint64,uint256,uint32,bytes)");
    bytes32 private constant SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    address private owner;
    uint32 private root;
    uint32 private child;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _idle();
        owner = address(new RngReviewRejectEther());
        root = _giveWalletId(owner);
        vm.deal(owner, 100 ether);
        uint256 price = game.mintPrice();
        vm.prank(owner);
        child = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        vm.prank(address(game));
        coin.mintForGame(owner, 100_000);
    }

    function _idle() private {
        for (uint256 i; i < 200; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) mockVRF.fulfillRandomWords(request, 0xA11D17);
            }
            if (game.rngComplete() && !game.advanceDue()) return;
            game.mineFlip{gas: 15_000_000}();
        }
        fail("engine failed to reach idle");
    }

    function _queue(address payer, uint32 id, uint256 boxes) private {
        vm.startPrank(payer);
        game.purchase{value: boxes * 0.01 ether}(
            id, 0, BoxOrderLib.boCustoms(boxes, 0.01 ether), 0, MintPaymentKind.DirectEth, false
        );
        game.placeDegeneretteBet{value: 0.125 ether}(id, 0, 0.005 ether, 25, 3);
        game.placeDegeneretteBet(id, 1, 100, 15, 7);
        vm.stopPrank();
    }

    function _requestMidday(uint256 word) private returns (uint48 read) {
        uint256 previous = mockVRF.lastRequestId();
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == previous; ++i) {
            game.mineFlip{gas: 15_000_000}();
        }
        assertGt(mockVRF.lastRequestId(), previous, "fresh request actually issued");
        assertFalse(game.rngLocked(), "test exercises unlocked midday window");
        assertFalse(game.rngComplete());
        read = RecyclingState.readBuffer(address(game));
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), word | 2);
    }

    function _drain(uint256 gasBudget, address keeper) private returns (bytes32 transcript, uint256 bets, uint256 calls) {
        vm.recordLogs();
        for (uint256 i; i < 200 && !game.rngComplete(); ++i) {
            vm.prank(keeper);
            game.mineFlip{gas: gasBudget}();
            ++calls;
        }
        assertTrue(game.rngComplete(), "sealed cohort drains without a permanent revert");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 boxes;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 topic = logs[i].topics[0];
            if (topic == BOX || topic == BET || topic == SPIN) {
                transcript = keccak256(abi.encode(transcript, logs[i].topics, logs[i].data));
                if (topic == BOX || topic == SPIN) ++boxes;
                if (topic == BET) ++bets;
            }
        }
        assertGt(boxes, 0, "nonvacuous reward resolution");
        assertGt(bets, 0, "nonvacuous bet resolution");
    }

    function _balances(uint32 id) private view returns (bytes32) {
        return keccak256(abi.encode(game.extsload(GameSlotKeys.balances(id)),
            coinflip.coinflipAmountById(id), wwxrp.claimable(id), coin.balanceOf(owner), sdgnrs.balanceOf(owner)));
    }

    function testFuzz_RejectingSmurfPayeeAndGasPartitionKeepTheSameResults(uint256 word) public {
        _queue(owner, child, 100);
        _queue(owner, child, 100);
        _requestMidday(word);
        uint256 snapshot = vm.snapshotState();
        (bytes32 transcript, uint256 bets, uint256 fullCalls) = _drain(15_000_000, address(0xCA11));
        assertEq(bets, 4);
        bytes32 balances = _balances(child);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        (bytes32 splitTranscript, uint256 splitBets, uint256 splitCalls) = _drain(4_600_000, address(0xCA12));
        assertEq(splitBets, 4);
        assertGt(splitCalls, fullCalls, "the comparison must actually partition work differently");
        assertEq(splitTranscript, transcript, "caller and gas partition cannot choose outcomes");
        assertEq(_balances(child), balances, "same account and token rewards");
    }

    function test_ShorterReusedCohortDoesNotReplayRetainedEntries() public {
        for (uint256 cycle; cycle < 3; ++cycle) {
            uint256 count = cycle == 0 ? 100 : 1;
            _queue(owner, child, count);
            if (cycle == 0) _queue(owner, child, count);
            // Keep the request above the threshold without enlarging the tested order.
            vm.prank(owner);
            game.purchase{value: 1.1 ether}(root, 0, BoxOrderLib.boCustom(1.1 ether), 0, MintPaymentKind.DirectEth, false);
            uint48 write = RecyclingState.writeBuffer(address(game));
            uint256 expected = cycle == 0 ? 4 : 2;
            assertEq(RecyclingState.betCount(address(game), write), expected);
            _requestMidday(0xBEEF + cycle);
            (, uint256 bets,) = _drain(6_000_000, address(0xCA11));
            assertEq(bets, expected, "stale packed bet lanes cannot replay");
        }
    }

    function test_MiddayLiquidationPreservesQueuedFamilyAndLaterRequests() public {
        address seller = makeAddr("rng-review-seller");
        vm.deal(seller, 100 ether);
        uint32 sellerRoot = _giveWalletId(seller);
        uint256 price = game.mintPrice();
        vm.prank(seller);
        uint32 sellerChild = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        vm.prank(address(game)); coin.mintForGame(seller, 100_000);
        // A real whale purchase gives the root far-future inventory and a positive sale quote.
        vm.prank(seller); game.purchaseWhalePass{value: 2.4 ether}(sellerRoot, 1, 0);
        _queue(seller, sellerChild, 100);
        vm.deal(address(sdgnrs), 100 ether);
        vm.prank(address(sdgnrs)); game.creditRedemptionDirect{value: 100 ether}(2, 100 ether);
        _requestMidday(0x5101D);
        uint256 snapshot = vm.snapshotState();
        (bytes32 beforeSale,,) = _drain(6_000_000, address(0xCA11));
        assertTrue(vm.revertToStateAndDelete(snapshot));
        LiquidationQuote memory q = game.previewLiquidateAccount(sellerRoot);
        assertTrue(q.eligible);
        assertGt(q.price, 0);
        vm.prank(seller); game.liquidateAccount(sellerRoot, q.price);
        (, address payee, bool authorized) = game.resolveAccount(sellerChild, seller);
        assertEq(payee, address(sdgnrs));
        assertFalse(authorized);
        assertEq(game.walletIdOf(seller), 0);
        // Allocate a different ID after delivery: queued seeds and credits must retain the old ID.
        uint32 replacement = _giveWalletId(seller);
        assertNotEq(replacement, sellerRoot);
        (bytes32 afterSale, uint256 bets,) = _drain(6_000_000, address(0xCA11));
        assertEq(bets, 2);
        assertEq(afterSale, beforeSale, "ownership and re-registration preserve committed outcomes");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _idle();
        assertTrue(game.rngComplete(), "ownership change cannot brick the following daily chain");
    }
}
