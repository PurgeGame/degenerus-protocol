// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DegenesisDeployProtocol} from "./DeployProtocol.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

abstract contract LogicalDaysFixture is DegenesisDeployProtocol {
    function setUp() public virtual {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
    }
    function _requestLogical() internal returns (uint256 id) {
        for (uint256 i; i < 200; ++i) {
            if (game.rngLocked()) return mockVRF.lastRequestId();
            uint256 pending = mockVRF.lastRequestId();
            if (pending != 0) {
                (,,bool delivered) = mockVRF.pendingRequests(pending);
                if (!delivered) mockVRF.fulfillRandomWords(pending, 777);
            }
            game.mineRun(0);
        }
        revert("daily request did not commit");
    }
    function _finishLogical() internal {
        uint24 requested = game.currentDayView_g542950();
        for (uint256 i; i < 500; ++i) {
            (bool complete,,) = game.dailySessionState();
            if (complete || game.currentDayView_g542950() > requested) return;
            game.mineRun(0);
        }
        revert("daily certificate not reached");
    }
    function _nextLogical(uint256 word) internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fulfillRandomWords(_requestLogical(), word);
        _finishLogical();
    }
    function _nextRequestAfter(uint256 oldId) internal {
        for (uint256 i; i < 500 && mockVRF.lastRequestId() == oldId; ++i) game.mineRun(0);
        assertGt(mockVRF.lastRequestId(), oldId);
    }
    function _rotateLogical() internal returns (MockVRFCoordinator vrf) {
        vrf = new MockVRFCoordinator();
        uint256 sub = vrf.createSubscription();
        vrf.addConsumer(sub, address(game));
        vrf.fundSubscription(sub, 1_000 ether);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(vrf), sub, bytes32(uint256(1)), 300_000);
    }
}
