// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {NativeSwapAdminHarness} from "./VrfNativeDonation.t.sol";
import {ClaimableSeed} from "../helpers/ClaimableSeed.sol";

contract SwapRefillAdminHarness is NativeSwapAdminHarness {
    function retireTo(address old) external { coordinator = old; }
}

/// @notice A swap while a request is pending: the old v2.5 cancel refuses, so Admin has no
///         refund to forward, and Game refills the replacement before its reissue.
contract VrfNativeSwapRefillTest is DeployProtocol {
    uint256 private constant TARGET = 0.49352 ether;
    uint32 private constant SDGNRS_ID = 2;
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes32 private constant CANCELLED = keccak256("SubscriptionCancelled(uint256,address)");
    SwapRefillAdminHarness private a;
    MockVRFCoordinator private replacement;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(admin), type(SwapRefillAdminHarness).runtimeCode);
        a = SwapRefillAdminHarness(payable(address(admin)));
        replacement = new MockVRFCoordinator();
        // The replacement refuses any request made before its subscription holds a balance.
        replacement.requireFundedRequests(true);
    }

    function _drive(MockVRFCoordinator c) private {
        for (uint256 i; i < 600; ++i) {
            uint256 id = c.lastRequestId();
            if (id != 0) {
                (,, bool done) = c.pendingRequests(id);
                if (!done) c.fulfillRandomWords(id, 0xC0FFEE + i);
            }
            try game.mineRun(0) {} catch (bytes memory err) {
                require(err.length >= 4 && bytes4(err) == NO_WORK, "unexpected revert");
                return;
            }
        }
    }

    function _pendingDaily() private {
        _drive(mockVRF);
        vm.warp(block.timestamp + 1 days);
        game.mineRun(0);
        assertTrue(game.rngLocked(), "daily request pending");
        assertGt(mockVRF.pendingCount(1), 0, "old subscription has a pending request");
    }

    function _newBalance() private view returns (uint256 bal) {
        (, bal,,,) = replacement.getSubscription(1);
    }

    function _swap() private returns (bool cancelledEvent) {
        vm.recordLogs();
        a.swapForTest(address(replacement), bytes32(uint256(9)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(admin) && logs[i].topics[0] == CANCELLED) cancelledEvent = true;
        }
    }

    function _finishOnReplacement() private {
        replacement.fulfillRandomWords(replacement.lastRequestId(), 0xBEEF);
        _drive(replacement);
        assertFalse(game.rngLocked(), "the day completes on the replacement");
    }

    function test_RefusedCancelStillFundsReplacementFromYield() public {
        _pendingDaily();
        vm.deal(address(game), address(game).balance + 5 ether);
        uint256 yieldBefore = game.yieldPoolView();
        uint256 sdgnrsBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = game.claimablePoolView();

        assertFalse(_swap(), "a refused cancel is not reported as cancelled");

        (,,, address owner,) = mockVRF.getSubscription(1);
        assertEq(owner, address(admin), "old subscription survives the refused cancel");
        assertEq(address(admin).balance, 0, "no refund reached Admin");
        assertEq(_newBalance(), TARGET, "replacement funded to target before the reissue");
        assertEq(replacement.lastRequestId(), 1, "reissued on the replacement");
        assertTrue(replacement.lastNativePayment());
        assertEq(game.yieldPoolView(), yieldBefore - TARGET, "funded from yield");
        assertEq(game.claimableWinningsOf(address(sdgnrs)), sdgnrsBefore, "sDGNRS untouched");
        assertEq(game.claimablePoolView(), poolBefore);
        _finishOnReplacement();
    }

    function test_RefusedCancelFundsReplacementFromSdgnrsWithoutYield() public {
        _pendingDaily();
        address payer = makeAddr("payer");
        vm.deal(payer, 10 ether);
        ClaimableSeed.fund(vm, address(game), payer, SDGNRS_ID, 1 ether);
        uint256 yield = game.yieldPoolView();
        vm.deal(address(game), address(game).balance - yield);
        assertEq(game.yieldPoolView(), 0);
        uint256 sdgnrsBefore = game.claimableWinningsOf(address(sdgnrs));
        uint256 poolBefore = game.claimablePoolView();

        _swap();

        assertEq(_newBalance(), TARGET);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), sdgnrsBefore - TARGET, "sDGNRS claimable debited");
        assertEq(game.claimablePoolView(), poolBefore - TARGET, "claimablePool paired");
        assertEq(replacement.lastRequestId(), 1);
        _finishOnReplacement();
    }

    function test_ForwardedRefundAboveLowWaterLeavesYieldUntouched() public {
        _drive(mockVRF);
        assertEq(mockVRF.pendingCount(1), 0, "nothing pending");
        mockVRF.fundSubscription(1, 1 ether);
        vm.deal(address(mockVRF), address(mockVRF).balance + 1 ether);
        vm.deal(address(game), address(game).balance + 5 ether);
        uint256 yieldBefore = game.yieldPoolView();
        (, uint96 refund,,,) = mockVRF.getSubscription(1);

        assertTrue(_swap(), "cancel succeeded");

        assertEq(_newBalance(), refund, "only the forwarded refund");
        assertEq(game.yieldPoolView(), yieldBefore, "no Game refill above low-water");
        assertEq(replacement.lastRequestId(), 0, "nothing in flight to reissue");
    }

    function test_NoCodeOldCoordinatorSkipsCancel() public {
        a.retireTo(makeAddr("codeless coordinator"));
        vm.deal(address(game), address(game).balance + 5 ether);
        assertFalse(_swap(), "no cancellation against an address without code");
        assertEq(_newBalance(), TARGET);
    }
}
