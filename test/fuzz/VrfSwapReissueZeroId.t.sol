// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";

/// @title VrfSwapReissueZeroId
/// @notice The coordinator swap re-issues an in-flight daily request. A replacement coordinator
///         answering with a request ID whose low 64 bits are zero is refused like every other
///         request site: the swap reverts whole, and a later swap re-issues normally.
contract VrfSwapReissueZeroId is DeployProtocol {
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    /// @dev Complete the first day, then leave the next day's daily request in flight.
    function _armDailyRequest() private {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        game.mineRun(0);
        assertTrue(game.rngLocked(), "fixture: daily request in flight");
    }

    function _completeDay(uint256 vrfWord) private {
        for (uint256 i; i < 200; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
            try game.mineRun(0) {} catch (bytes memory reason) {
                if (reason.length >= 4 && bytes4(reason) == bytes4(keccak256("NoWork()"))) return;
                assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            }
        }
        fail("fixture did not finish the day");
    }

    function _newCoordinator() private returns (MockVRFCoordinator vrf, uint256 subId) {
        vrf = new MockVRFCoordinator();
        subId = vrf.createSubscription();
        vrf.addConsumer(subId, address(game));
        vrf.fundSubscription(subId, 100e18);
    }

    function _swap(MockVRFCoordinator vrf, uint256 subId) private {
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(vrf), subId, bytes32(uint256(1)), 300_000);
    }

    function test_zeroLow64Id_refusesTheSwap_thenRetrySucceeds() public {
        _armDailyRequest();
        (MockVRFCoordinator vrf, uint256 subId) = _newCoordinator();
        vm.mockCall(address(vrf), IVRFCoordinator.requestRandomWords.selector, abi.encode(uint256(1) << 64));
        vm.expectRevert(abi.encodeWithSignature("ExternalRequestRefused()"));
        _swap(vrf, subId);
        assertTrue(game.rngLocked(), "the refused swap changed nothing");

        vm.clearMockedCalls();
        _swap(vrf, subId);
        assertTrue(vrf.lastRequestId() != 0, "the retry re-issued on the new coordinator");
    }

    function test_nonzeroLow64Id_isAccepted() public {
        _armDailyRequest();
        (MockVRFCoordinator vrf, uint256 subId) = _newCoordinator();
        vm.mockCall(address(vrf), IVRFCoordinator.requestRandomWords.selector, abi.encode((uint256(1) << 64) | 7));
        _swap(vrf, subId);
        assertTrue(game.rngLocked(), "daily request still in flight on the new coordinator");
    }
}
