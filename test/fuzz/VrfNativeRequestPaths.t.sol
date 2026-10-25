// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";

/// @notice Real Game transport paths must request native payment even without funding.
contract VrfNativeRequestPathsTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.deal(address(game), 0);
        vm.warp(block.timestamp + 1 days);
    }

    function _daily() private returns (uint256 requestId) {
        for (uint256 i; i < 30 && mockVRF.lastRequestId() == 0; ++i) {
            game.mineRun{gas: 15_000_000}(0);
        }
        requestId = mockVRF.lastRequestId();
        assertGt(requestId, 0, "daily request issued");
        assertTrue(game.rngLocked(), "daily request remains pending");
        assertTrue(mockVRF.lastNativePayment(), "native ExtraArgs");
        (, uint96 balance,,,) = mockVRF.getSubscription(admin.subscriptionId());
        assertEq(balance, 0, "no subscription balance gate");
    }

    function testDailyNativeAtZeroBalance() public {
        uint256 requestId = _daily();
        mockVRF.fulfillRandomWords(requestId, 123);
        assertTrue(game.isRngFulfilled());
    }

    function testRetryNativeAtZeroBalance() public {
        uint256 original = _daily();
        vm.warp(block.timestamp + 21 hours);
        vm.prank(address(admin));
        game.retryRng();
        assertGt(mockVRF.lastRequestId(), original, "retry issued");
        assertTrue(mockVRF.lastNativePayment());
        (, uint96 balance,,,) = mockVRF.getSubscription(admin.subscriptionId());
        assertEq(balance, 0);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 456);
        assertTrue(game.isRngFulfilled());
    }

    function testReplacementReissueNativeAtZeroBalance() public {
        _daily();
        MockVRFCoordinator replacement = new MockVRFCoordinator();
        uint256 subId = replacement.createSubscription();
        replacement.addConsumer(subId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(replacement), subId, bytes32(uint256(9)), 150_000);
        assertGt(replacement.lastRequestId(), 0, "replacement reissued");
        assertTrue(replacement.lastNativePayment());
        (, uint96 balance,,,) = replacement.getSubscription(subId);
        assertEq(balance, 0);
        replacement.fulfillRandomWords(replacement.lastRequestId(), 789);
        assertTrue(game.isRngFulfilled());
    }
}
