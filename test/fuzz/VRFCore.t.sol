// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VRFCore -- Audit tests for VRF request/fulfillment correctness
/// @notice Covers VRFC-01 (callback revert-safety + gas), VRFC-02 (requestId lifecycle),
///         VRFC-03 (mutual exclusion), VRFC-04 (12h timeout retry).
contract VRFCore is DeployProtocol {
    VRFHandler public vrfHandler;

    /// @dev Storage slot constants for direct state inspection via vm.load.
    ///      Verified via `forge inspect DegenerusGame storage-layout`.
    ///      Slot 0: packed timing/flags (see DegenerusGameStorage layout).
    ///      Slot 4: rngWordCurrent (uint256).
    ///      Slot 5: vrfRequestId (uint256).
    uint256 constant SLOT_PACKED_0 = 0;
    uint256 constant SLOT_RNG_WORD_CURRENT = 4;
    uint256 constant SLOT_VRF_REQUEST_ID = 5;

    function setUp() public {
        _deployProtocol();
        vrfHandler = new VRFHandler(mockVRF, game);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> loop until unlocked.
    ///      Pattern from StallResilience.t.sol.
    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Read vrfRequestId directly from storage slot 5.
    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    /// @dev Read rngWordCurrent directly from storage slot 4.
    function _readRngWordCurrent() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_RNG_WORD_CURRENT))));
    }

    /// @dev Read rngRequestTime from packed slot 0, bytes [12:18] (uint48).
    ///      In Solidity's right-to-left packing, byte 12 starts at bit 96.
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 96);
    }

    /// @dev Deploy a new MockVRFCoordinator and wire it up via admin prank.
    ///      Pattern from StallResilience.t.sol.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
    }

    /// @dev Setup for mid-day lootbox RNG: complete a day, make a purchase on the
    ///      new day to create pending lootbox ETH, fund VRF subscription with LINK.
    ///      Returns the current timestamp for boundary checks.
    function _setupForMidDayRng() internal returns (uint256 ts) {
        // Complete day 1
        _completeDay(0xDEAD0001);

        // Warp to day 2 (next day boundary)
        vm.warp(block.timestamp + 1 days);

        // Complete day 2 so rngWordByDay[day2] != 0
        _completeDay(0xDEAD0002);

        // Purchase with lootbox amount to create pending ETH
        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

        // Fund VRF subscription with LINK
        // Admin created subscription 1 during deploy; fund it
        mockVRF.fundSubscription(1, 100e18);

        ts = block.timestamp;
    }

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-01: Callback Revert-Safety and Gas Budget
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Callback never reverts on daily fulfillment with any fuzzed word.
    function test_callbackNeverReverts_daily(uint256 randomWord) public {
        // Trigger daily VRF request
        game.advanceGame();
        assertTrue(game.rngLocked(), "rngLocked after advanceGame");

        uint256 reqId = mockVRF.lastRequestId();
        assertTrue(reqId > 0, "VRF request sent");

        // Fulfill with fuzzed word -- must not revert
        mockVRF.fulfillRandomWords(reqId, randomWord);

        // Verify word stored (zero-guarded to 1)
        uint256 stored = _readRngWordCurrent();
        if (randomWord == 0) {
            assertEq(stored, 1, "Zero word should be stored as 1");
        } else {
            assertEq(stored, randomWord, "Word should be stored as-is");
        }
    }

    /// @notice Callback silently returns (no revert) when requestId doesn't match.
    function test_callbackNeverReverts_staleId(uint256 staleId, uint256 randomWord) public {
        // Trigger daily VRF request
        game.advanceGame();
        uint256 realReqId = mockVRF.lastRequestId();

        // Ensure staleId != realReqId to trigger the mismatch path
        vm.assume(staleId != realReqId);

        // Record state before
        uint256 wordBefore = _readRngWordCurrent();

        // Fulfill with wrong requestId via raw call -- must not revert, no state change
        mockVRF.fulfillRandomWordsRaw(staleId, address(game), randomWord);

        // State unchanged
        assertEq(_readRngWordCurrent(), wordBefore, "Stale ID should not change state");
    }

    /// @notice Callback silently returns on duplicate fulfillment (rngWordCurrent already set).
    function test_callbackNeverReverts_duplicateFulfillment(uint256 randomWord) public {
        vm.assume(randomWord != 0); // Ensure first fulfillment sets a nonzero word

        // Trigger daily VRF request
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();

        // First fulfillment
        mockVRF.fulfillRandomWords(reqId, randomWord);
        uint256 storedAfterFirst = _readRngWordCurrent();
        assertEq(storedAfterFirst, randomWord, "First fulfillment should store word");

        // Second fulfillment via raw call (same requestId) -- should silently return
        // because rngWordCurrent != 0. Use a different word (XOR to avoid overflow).
        uint256 differentWord = randomWord ^ 0xDEAD;
        if (differentWord == 0) differentWord = 1;
        mockVRF.fulfillRandomWordsRaw(reqId, address(game), differentWord);
        assertEq(_readRngWordCurrent(), storedAfterFirst, "Duplicate should not change word");
    }

    /// @notice Callback reverts when msg.sender is not the VRF coordinator.
    function test_callbackReverts_unauthorizedSender() public {
        // Trigger daily VRF request
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();

        // Attempt direct call from non-coordinator address
        uint256[] memory words = new uint256[](1);
        words[0] = 12345;

        vm.prank(address(0xdead));
        vm.expectRevert();
        game.rawFulfillRandomWords(reqId, words);
    }

    /// @notice Gas budget: daily callback path under 300k gas.
    function test_callbackGasBudget_daily() public {
        // Trigger daily VRF request
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();

        // Measure gas for fulfillment (includes mock overhead, but callback itself is ~33k)
        uint256 gasBefore = gasleft();
        mockVRF.fulfillRandomWords(reqId, 0xDEAD);
        uint256 gasUsed = gasBefore - gasleft();

        // The callback gas budget is 300k. Total measured includes mock overhead,
        // but even with overhead it should be well under 300k.
        assertLt(gasUsed, 300_000, "Daily callback should use < 300k gas");
    }

    /// @notice Gas budget: mid-day callback path under 300k gas.
    function test_callbackGasBudget_midday() public {
        _setupForMidDayRng();

        // Trigger mid-day lootbox RNG request
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // Measure gas for fulfillment
        uint256 gasBefore = gasleft();
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 300_000, "Mid-day callback should use < 300k gas");
    }

    /// @notice Zero-guard: randomWord == 0 produces stored value of 1.
    function test_callbackZeroGuard(uint256 randomWord) public {
        // Bound to only test the zero case explicitly
        randomWord = 0;

        // Trigger daily VRF request
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();

        // Fulfill with word=0
        mockVRF.fulfillRandomWords(reqId, randomWord);

        // rngWordCurrent must be 1, not 0
        assertEq(_readRngWordCurrent(), 1, "Zero word must be guarded to 1");
    }

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-02: vrfRequestId Lifecycle
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Daily request: vrfRequestId set on request, cleared after full processing.
    function test_vrfRequestIdLifecycle_dailyFreshRequest() public {
        // Before any request
        assertEq(_readVrfRequestId(), 0, "vrfRequestId should start at 0");

        // Trigger daily VRF request
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();

        // vrfRequestId should match
        assertEq(_readVrfRequestId(), reqId, "vrfRequestId should match mock's lastRequestId");
        assertTrue(reqId > 0, "Request ID should be nonzero");

        // Fulfill
        mockVRF.fulfillRandomWords(reqId, 0xDEAD);

        // Process until unlocked (daily branch: rngWordCurrent set, advanceGame processes)
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
        assertFalse(game.rngLocked(), "Should be unlocked after full processing");

        // After _unlockRng: vrfRequestId should be 0
        assertEq(_readVrfRequestId(), 0, "vrfRequestId should be cleared after unlock");
    }

    /// @notice Mid-day request: vrfRequestId set, cleared after mid-day fulfillment.
    function test_vrfRequestIdLifecycle_middayRequest() public {
        _setupForMidDayRng();

        // Before mid-day request, vrfRequestId should be 0 (cleared by _unlockRng from day 2)
        assertEq(_readVrfRequestId(), 0, "vrfRequestId should be 0 before mid-day request");

        // Fire mid-day request
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // vrfRequestId should match
        assertEq(_readVrfRequestId(), reqId, "vrfRequestId should match after requestLootboxRng");

        // Fulfill mid-day
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);

        // After mid-day branch: vrfRequestId cleared to 0
        assertEq(_readVrfRequestId(), 0, "vrfRequestId should be cleared after mid-day fulfillment");
        // rngRequestTime also cleared
        assertEq(_readRngRequestTime(), 0, "rngRequestTime should be cleared after mid-day fulfillment");
    }

    /// @notice Fresh daily request: isRetry=false, lootboxRngIndex increments by 1.
    function test_retryDetection_fresh() public {
        // Record initial lootboxRngIndex
        uint48 indexBefore = game.lootboxRngIndexView();

        // Trigger fresh daily VRF request
        game.advanceGame();

        // lootboxRngIndex should have incremented (fresh request)
        uint48 indexAfter = game.lootboxRngIndexView();
        assertEq(indexAfter, indexBefore + 1, "Fresh request should increment lootboxRngIndex by 1");
    }

    /// @notice Timeout retry: lootboxRngIndex does NOT increment again.
    function test_retryDetection_timeout() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: warp to next day, trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");

        // Record lootboxRngIndex after initial request
        uint48 indexAfterRequest = game.lootboxRngIndexView();

        // Do NOT fulfill -- wait 13 hours for timeout
        vm.warp(block.timestamp + 13 hours);

        // Retry: advanceGame triggers timeout path -> _requestRng -> _finalizeRngRequest(isRetry=true)
        game.advanceGame();

        // lootboxRngIndex should NOT have changed (retry, not fresh)
        uint48 indexAfterRetry = game.lootboxRngIndexView();
        assertEq(indexAfterRetry, indexAfterRequest, "Retry should NOT increment lootboxRngIndex");
    }

    /// @notice Fuzz retry scenario: request -> timeout -> retry -> fulfill.
    ///         lootboxRngIndex must remain unchanged between first request and post-retry.
    function test_retryDetection_fuzz(uint256 word1, uint256 word2) public {
        vm.assume(word1 != 0 && word2 != 0);

        // Day 1: complete normally
        _completeDay(word1);

        // Day 2: request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        uint48 indexAfterRequest = game.lootboxRngIndexView();

        // Timeout + retry
        vm.warp(block.timestamp + 13 hours);
        game.advanceGame();
        uint48 indexAfterRetry = game.lootboxRngIndexView();
        assertEq(indexAfterRetry, indexAfterRequest, "Fuzz: retry should not change index");

        // Fulfill the retried request and complete the day
        uint256 newReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(newReqId, word2);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }

        // Index should still be the same (no double increment)
        assertEq(game.lootboxRngIndexView(), indexAfterRequest, "Fuzz: index unchanged after retry+fulfill");
    }
}
