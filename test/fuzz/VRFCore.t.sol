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

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-03: rngLockedFlag Mutual Exclusion
    // ──────────────────────────────────────────────────────────────────────

    /// @notice During daily RNG (rngLockedFlag==true), requestLootboxRng must revert.
    function test_rngLocked_blocksMidDayRequest() public {
        // Complete day 1 so daily word exists
        _completeDay(0xDEAD0001);

        // Warp to day 2
        vm.warp(block.timestamp + 1 days);

        // Trigger daily VRF request -> rngLockedFlag = true
        game.advanceGame();
        assertTrue(game.rngLocked(), "Daily RNG should lock");

        // Mid-day request must revert with RngLocked
        vm.expectRevert();
        game.requestLootboxRng();
    }

    /// @notice After requestLootboxRng (rngLockedFlag stays false), daily flow proceeds.
    ///         Tests that a mid-day request does NOT block the next day's daily RNG.
    function test_midDayRequest_doesNotBlockDaily() public {
        _setupForMidDayRng();

        // Fire mid-day request (does NOT set rngLockedFlag)
        game.requestLootboxRng();
        assertFalse(game.rngLocked(), "Mid-day request should not lock rngLockedFlag");

        // Do NOT fulfill mid-day VRF
        // Warp to day 3 + 13 hours so we're past the 12h timeout
        // (rngRequestTime != 0, so rngGate enters waiting path)
        vm.warp(block.timestamp + 1 days + 13 hours);

        // advanceGame on day 3 should trigger timeout retry path
        // (rngRequestTime was set by requestLootboxRng, elapsed > 12h)
        // This overwrites vrfRequestId and sets rngLockedFlag = true
        game.advanceGame();
        assertTrue(game.rngLocked(), "Daily RNG should lock after timeout retry");
    }

    /// @notice After mid-day VRF fulfills, vrfRequestId and rngRequestTime are cleared,
    ///         allowing daily flow to proceed cleanly.
    function test_midDayFulfillment_clearsState() public {
        _setupForMidDayRng();

        // Fire mid-day request
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // Verify state is set
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId should be set");
        assertTrue(_readRngRequestTime() != 0, "rngRequestTime should be set");

        // Fulfill mid-day
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);

        // Both should be cleared
        assertEq(_readVrfRequestId(), 0, "vrfRequestId cleared after mid-day fulfillment");
        assertEq(_readRngRequestTime(), 0, "rngRequestTime cleared after mid-day fulfillment");
    }

    /// @notice requestLootboxRng within 15 minutes of day boundary must revert.
    function test_preResetWindow_blocksMidDay() public {
        _setupForMidDayRng();

        // Current day is day 2 (after completing days 1 and 2).
        // Day 3 boundary = (current day index + 1) * 86400.
        // We need to warp to 15 minutes before the day 3 boundary.
        uint48 currentDay = game.currentDayView();
        uint256 nextDayBoundary = uint256(currentDay + 1) * 86400;
        uint256 preResetTime = nextDayBoundary - 15 minutes;

        // Warp to 15 minutes before next day boundary
        vm.warp(preResetTime);

        // requestLootboxRng should revert (15-minute pre-reset guard)
        vm.expectRevert();
        game.requestLootboxRng();
    }

    /// @notice After updateVrfCoordinatorAndSub, rngLockedFlag is false and VRF state is cleared.
    function test_coordinatorSwap_clearsRngLocked() public {
        // Complete day 1
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger daily VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Daily RNG should lock");
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId should be set");
        assertTrue(_readRngRequestTime() != 0, "rngRequestTime should be set");

        // Coordinator swap
        _doCoordinatorSwap();

        // All RNG state should be cleared
        assertFalse(game.rngLocked(), "rngLocked should be false after swap");
        assertEq(_readVrfRequestId(), 0, "vrfRequestId cleared after swap");
        assertEq(_readRngRequestTime(), 0, "rngRequestTime cleared after swap");
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent cleared after swap");
    }

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-04: 12h Timeout Retry
    // ──────────────────────────────────────────────────────────────────────

    /// @notice After exactly 12 hours, advanceGame triggers retry (not RngNotReady revert).
    function test_timeoutRetry_12h() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");
        uint48 requestTime = _readRngRequestTime();
        uint256 oldReqId = _readVrfRequestId();

        // Warp to exactly rngRequestTime + 12 hours
        vm.warp(uint256(requestTime) + 12 hours);

        // Record lootboxRngIndex before retry
        uint48 indexBefore = game.lootboxRngIndexView();

        // advanceGame should trigger retry (not revert)
        game.advanceGame();

        // After retry: rngLocked still true (new request in flight)
        assertTrue(game.rngLocked(), "Should still be locked after retry");

        // vrfRequestId should have changed (new request)
        uint256 newReqId = _readVrfRequestId();
        assertTrue(newReqId != oldReqId, "vrfRequestId should change on retry");

        // lootboxRngIndex should be unchanged (retry detection)
        assertEq(game.lootboxRngIndexView(), indexBefore, "Index unchanged on retry");
    }

    /// @notice Before 12 hours, advanceGame reverts with RngNotReady.
    function test_noRetry_before12h() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");
        uint48 requestTime = _readRngRequestTime();

        // Warp to 11h59m (just under 12h)
        vm.warp(uint256(requestTime) + 12 hours - 1 minutes);

        // advanceGame should revert with RngNotReady
        vm.expectRevert();
        game.advanceGame();
    }

    /// @notice After retry overwrites vrfRequestId, old fulfillment is silently discarded.
    ///         New fulfillment (with new requestId) succeeds.
    function test_timeoutRetry_staleWordDiscarded(uint256 word1, uint256 word2) public {
        vm.assume(word1 != 0 && word2 != 0);

        // Day 1: complete normally
        _completeDay(0xBEEF0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        uint256 oldReqId = mockVRF.lastRequestId();

        // Timeout + retry
        vm.warp(block.timestamp + 13 hours);
        game.advanceGame();
        uint256 newReqId = mockVRF.lastRequestId();
        assertTrue(newReqId != oldReqId, "New request ID after retry");

        // Old fulfillment via raw call: silently discarded (requestId mismatch)
        mockVRF.fulfillRandomWordsRaw(oldReqId, address(game), word1);
        assertEq(_readRngWordCurrent(), 0, "Old fulfillment should be discarded (word still 0)");

        // New fulfillment: succeeds
        mockVRF.fulfillRandomWordsRaw(newReqId, address(game), word2);
        uint256 stored = _readRngWordCurrent();
        if (word2 == 0) {
            assertEq(stored, 1, "Zero-guarded word stored as 1");
        } else {
            assertEq(stored, word2, "New fulfillment should store word");
        }
    }

    /// @notice Fuzz: timeout retry never double-increments lootboxRngIndex.
    function test_timeoutRetry_lootboxIndexPreserved_fuzz(uint256 word) public {
        vm.assume(word != 0);

        // Day 1: complete normally
        _completeDay(0xFEED0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        uint48 indexAfterRequest = game.lootboxRngIndexView();

        // Timeout + retry
        vm.warp(block.timestamp + 13 hours);
        game.advanceGame();
        assertEq(game.lootboxRngIndexView(), indexAfterRequest, "Index unchanged after retry");

        // Fulfill new request and complete day
        uint256 newReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(newReqId, word);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }

        // Index should remain the same (retry path, no double increment)
        assertEq(game.lootboxRngIndexView(), indexAfterRequest, "Index unchanged after retry+fulfill");
    }

    /// @notice VRF word from previous day's request: rngGate detects requestDay < day,
    ///         redirects word to lootbox via _finalizeLootboxRng, requests fresh daily RNG.
    ///         The rngGate returns 1 as a sentinel word and advanceGame processes the day
    ///         with this value, eventually unlocking via _unlockRng.
    function test_crossDayStaleWord() public {
        // Day 1: complete normally (at deploy ts=86400)
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request using absolute timestamp
        uint256 day2Start = 2 * 86400; // 172800
        vm.warp(day2Start);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");
        uint256 reqId = mockVRF.lastRequestId();
        uint256 reqIdBefore = reqId;

        // Fulfill the VRF (word stored in rngWordCurrent)
        mockVRF.fulfillRandomWords(reqId, 0xC0FFEE);
        assertEq(_readRngWordCurrent(), 0xC0FFEE, "Word should be stored");

        // Warp PAST day boundary to day 3 using absolute timestamp
        uint256 day3Start = 3 * 86400; // 259200
        vm.warp(day3Start);

        // advanceGame on day 3: rngGate sees rngWordCurrent != 0 but requestDay (day 2) < current day (day 3)
        // It should: (1) redirect stale word to lootbox, (2) request fresh daily RNG,
        // (3) return 1 as sentinel -- advanceGame breaks with STAGE_RNG_REQUESTED.
        game.advanceGame();

        // A new VRF request should have been made (fresh daily for day 3)
        uint256 newReqId = mockVRF.lastRequestId();
        assertTrue(newReqId > reqIdBefore, "New VRF request should have been made");

        // The game should be locked (new daily RNG request pending)
        assertTrue(game.rngLocked(), "Should be locked from new daily request");

        // Fulfill the new request and complete day 3
        mockVRF.fulfillRandomWords(newReqId, 0xDA300003);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
        assertFalse(game.rngLocked(), "Should be unlocked after completing day 3");

        // Day 3 should have an RNG word recorded
        assertTrue(game.rngWordForDay(3) != 0, "Day 3 should have RNG word");
    }
}
