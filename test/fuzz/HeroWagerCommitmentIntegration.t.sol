// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Full deployment, real wagers, mineFlip requests, Admin retry and VRF
///      callbacks. No hero storage or request metadata is injected by this test.
contract HeroWagerCommitmentIntegrationTest is RedemptionFixture {
    uint256 private constant HERO_MASK = ((uint256(1) << 30) - 1) | (uint256(1) << 38);

    function _bet(uint8 symbol, uint128 amount) private {
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        game.placeDegeneretteBet{value: amount}(0, 0, amount, 1, symbol);
    }
    function _metadata() private view returns (uint256) {
        return uint256(game.extsload(bytes32(GameSlots.LOOTBOX_RNG_PACKED))) & HERO_MASK;
    }
    function _retry() private {
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        admin.retryGameRng();
    }

    function test_LateWagersAcrossSeveralDaysAllEnterNextCommitment() public {
        _bet(13, 0.01 ether);
        uint24 originalDay = game.currentDayView();
        assertEq(game.getDailyHeroWager(originalDay, 1, 5), 100);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertTrue(_runUntilNewRequestOrIdle(), "fresh daily request");
        assertTrue(game.rngLocked());
        uint256 originalRequest = mockVRF.lastRequestId();
        uint256 committed = _metadata();
        assertEq(uint24(committed), originalDay + 1);
        assertEq(game.getDailyHeroWager(originalDay, 1, 5), 100);

        _bet(15, 0.02 ether);
        vm.warp(vm.getBlockTimestamp() + 20 hours);
        uint256 beforeRetry = _metadata();
        _retry();
        assertGt(mockVRF.lastRequestId(), originalRequest);
        assertEq(_metadata(), beforeRetry, "daily retry cannot rotate or clear either pool");
        for (uint256 i; i < 3; ++i) {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            _bet(15, 0.02 ether);
            assertEq(game.getDailyHeroWager(originalDay, 1, 5), 100, "frozen pool survives stalled days");
            assertEq(game.getDailyHeroWager(game.currentDayView(), 1, 7), (i + 2) * 200);
        }
        uint24 nextDay = game.currentDayView();
        uint256 delayed = mockVRF.lastRequestId();
        assertTrue(_fulfillPending(0xBEEF));
        assertEq(_metadata(), beforeRetry, "callback does not rotate hero buffers");
        assertTrue(_runUntilNewRequestOrIdle(), "settle delayed session and commit accumulated wagers");
        assertGt(mockVRF.lastRequestId(), delayed);
        assertTrue(game.rngLocked(), "next commitment is daily");
        assertEq(uint24(_metadata()), nextDay);
        assertEq(game.getDailyHeroWager(nextDay - 1, 1, 7), 800, "all four late bets enter next frozen draw");
        assertEq(game.getDailyHeroWager(nextDay, 1, 7), 0, "new accumulator is logically empty");
        assertEq(game.getDailyHeroWager(originalDay, 1, 5), 0, "retired commitment is inaccessible");
    }

    function test_MiddayRequestRetryAndCallbackDoNotRotateHeroPools() public {
        _bet(13, 0.01 ether);
        uint256 beforeRequest = _metadata();
        _sendMiddayRequest();
        assertEq(_metadata(), beforeRequest, "midday request leaves hero pools intact");
        uint256 request = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 20 hours);
        _retry();
        assertGt(mockVRF.lastRequestId(), request);
        assertFalse(game.rngLocked(), "retry retains midday kind");
        assertEq(_metadata(), beforeRequest, "midday retry leaves hero pools intact");
        assertTrue(_fulfillPending(0xCAFE));
        assertEq(_metadata(), beforeRequest, "midday callback leaves hero pools intact");
        assertEq(game.getDailyHeroWager(game.currentDayView(), 1, 5), 100);
    }
}
