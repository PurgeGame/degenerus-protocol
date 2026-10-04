// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @dev Run unchanged on the production sentinel and a same-source zero-sentinel
/// control. Isolated snapshots include intrinsic gas and refunds; do not subtract
/// refunds again. Calls fulfill Game directly as the actual coordinator, leaving
/// mock bookkeeping outside the callback measurement.
contract RngCurrentSentinelGasTest is DeployProtocol {
    function setUp() public { _deployProtocol(); vm.warp(vm.getBlockTimestamp() + 1 days); }
    function _sealed(uint24 day) private view returns (bool) {
        return uint24(uint256(game.extsload(bytes32(uint256(0)))) >> 24) == day && !game.rngLocked();
    }
    function _coldDailyNudgeCallback(uint256 nudges) private {
        RecyclingState.seedNudges(address(game), nudges);
        game.mineFlip();
        uint256 id = mockVRF.lastRequestId();
        assertGt(id, 0); assertTrue(game.rngLocked());
        uint256[] memory words = new uint256[](1); words[0] = 1_000_000;
        bytes32 state = game.extsload(bytes32(0));
        vm.prank(address(mockVRF));
        game.rawFulfillRandomWords(id, words);
        uint256 used = vm.snapshotGasLastCall("cold-nudge-callback");
        assertEq(game.extsload(bytes32(0)), state, "nudge and flags are never written in fulfillment");
        assertEq(RecyclingState.currentWord(address(game)), 1_000_000 + nudges);
        emit log_named_uint("daily nudges", nudges);
        emit log_named_uint("cold daily callback transaction gas", used);
    }
    function test_ColdDailyCallbackWithZeroNudges() public { _coldDailyNudgeCallback(0); }
    function test_ColdDailyCallbackWith255Nudges() public { _coldDailyNudgeCallback(255); }

    function test_ColdCallbackAndRequestCrankCostsThroughFourRealDays() public {
        uint256 callbacks; uint256 requests; uint256 cranks; uint256 fulfilled;
        for (uint256 cycle; cycle < 4; ++cycle) {
            uint24 day = game.currentDayView();
            uint256 word = uint256(keccak256(abi.encode("sentinel-callback", cycle)));
            uint256 callback; uint256 request; uint256 crank;
            for (uint256 i; i < 5000 && !_sealed(day); ++i) {
                uint256 beforeId = mockVRF.lastRequestId();
                game.mineFlip();
                uint256 used = vm.snapshotGasLastCall("sentinel-keeper");
                uint256 id = mockVRF.lastRequestId();
                if (id != beforeId) request += used;
                else crank += used;
                if (id != 0 && id != fulfilled && game.rngLocked() && !game.isRngFulfilled()) {
                    uint256[] memory words = new uint256[](1); words[0] = word;
                    vm.prank(address(mockVRF));
                    game.rawFulfillRandomWords(id, words);
                    callback += vm.snapshotGasLastCall("sentinel-callback");
                    fulfilled = id;
                }
            }
            assertTrue(_sealed(day), "bounded real day completed");
            assertEq(game.rngWordForDay(day), word);
            assertFalse(game.isRngFulfilled(), "day returned to waiting");
            assertGt(callback, 0, "non-vacuous callback");
            assertGt(request, 0, "fresh real request");
            callbacks += callback; requests += request; cranks += crank;
            emit log_named_uint("cycle", cycle);
            emit log_named_uint("cold callback transaction gas", callback);
            emit log_named_uint("cold request transaction gas", request);
            emit log_named_uint("cold crank transaction gas", crank);
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        emit log_named_uint("four-day callback transaction gas", callbacks);
        emit log_named_uint("four-day request transaction gas", requests);
        emit log_named_uint("four-day crank transaction gas", cranks);
        emit log_named_uint("four-day all-payer transaction gas", callbacks + requests + cranks);
    }
}
