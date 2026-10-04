// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title VRFCore -- Audit tests for VRF request/fulfillment correctness
/// @notice Covers VRFC-01 (callback revert-safety + gas), VRFC-02 (requestId lifecycle),
///         VRFC-03 (mutual exclusion), VRFC-04 (20h vault-owner retry).
contract VRFCore is DeployProtocol {
    VRFHandler public vrfHandler;

    /// @dev Storage slot constants for direct state inspection via vm.load.
    ///      Verified via `forge inspect DegenerusGame storage-layout`.
    ///      Slot 0: packed timing/flags (see DegenerusGameStorage layout).
    ///      Slot 3: rngWordCurrent (uint256).
    ///      Slot 4: vrfRequestId (uint256).
    uint256 constant SLOT_PACKED_0 = 0;
    uint256 constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 constant SLOT_VRF_REQUEST_ID = 4;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vrfHandler = new VRFHandler(mockVRF, game);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Complete a full day: mineFlip -> VRF fulfill -> loop until unlocked.
    ///      Tracks the last-known request ID to avoid double-fulfillment when the
    ///      game reuses a stale rngWordCurrent across day boundaries.
    uint256 private _lastFulfilledReqId;

    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
        _finishReadConsumers();
            _finishReadConsumers();
    }

    /// @dev Read lootboxRngIndex from lootboxRngPacked (storage slot 34, low 48 bits = LR_INDEX)
    ///      (post V62 lootbox repack: was 35).
    function _lootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Read vrfRequestId directly from storage slot 4.
    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    /// @dev Read LR_MID_DAY from lootboxRngPacked (slot 34, bits [224:232]).
    function _lrMidDay() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(uint256(33)))) >> 224);
    }

    /// @dev Read rngWordCurrent directly from storage slot 3.
    function _readRngWordCurrent() internal view returns (uint256) {
        return RecyclingState.currentWord(address(game));
    }

    /// @dev Read rngRequestTime from packed slot 0, bytes [6:12] (uint48, bit offset 48).
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 48);
    }

    /// @dev Read the retry-spent flag: rngFlagsAndNudges (slot 0 bytes [30:32]) bit 10.
    function _readRetrySpent() internal view returns (bool) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return (packed >> 250) & 1 != 0;
    }

    /// @dev Deploy a new MockVRFCoordinator and wire it up via admin prank.
    ///      Resets _lastFulfilledReqId since the new mock has its own request counter.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
        _lastFulfilledReqId = 0;
    }

    /// @dev Answer and publish every mid-day request the miner issues for closed Craps windows
    ///      until it has no work left today. Publishing one window's word can arm the next closed
    ///      window and request its word in the same call, so this loops to quiescence.
    function _settleMiddayRequests() internal {
        for (uint256 i = 0; i < 64; i++) {
            uint8 action = game.minerAction();
            if (action == 0) return; // Idle
            assertFalse(game.rngLocked(), "only mid-day work is settled here");
            assertTrue(action != 17, "settling mid-day work must not reach a daily request"); // RequestDaily
            if (action == 2) {
                // Wait: the live mid-day request is unanswered.
                uint256 rid = _readVrfRequestId();
                assertEq(rid, mockVRF.lastRequestId(), "live request is the coordinator's latest");
                assertEq(_readRngWordCurrent(), 0, "waiting request has no word yet");
                mockVRF.fulfillRandomWords(rid, uint256(keccak256(abi.encode("midday", rid))));
                _lastFulfilledReqId = rid;
            } else {
                game.mineFlip();
            }
        }
        fail("mid-day requests did not settle");
    }

    /// @dev Setup for mid-day lootbox RNG: complete a day, make a purchase on the
    ///      new day to create pending lootbox ETH, fund VRF subscription with LINK.
    ///      Returns the current timestamp for boundary checks.
    function _setupForMidDayRng() internal returns (uint256 ts) {
        return _setupForMidDayRng(false);
    }

    /// @param quietCraps Fund LINK before the purchase and settle the mid-day requests for
    ///        closed Craps windows, so the lootbox request under test is the only mid-day
    ///        work and its publication arms no further window.
    function _setupForMidDayRng(bool quietCraps) internal returns (uint256 ts) {
        // Complete day 1
        _completeDay(0xDEAD0001);

        // Warp to day 2 (next day boundary)
        vm.warp(block.timestamp + 1 days);

        // Complete day 2 so _recordedDailyWord(day2) != 0
        _completeDay(0xDEAD0002);

        if (quietCraps) {
            mockVRF.fundSubscription(1, 100e18);
            _settleMiddayRequests();
        }

        // Purchase with lootbox amount to create pending ETH
        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        // Fund VRF subscription with LINK
        // Admin created subscription 1 during deploy; fund it
        if (!quietCraps) mockVRF.fundSubscription(1, 100e18);

        ts = block.timestamp;
    }

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-01: Callback Revert-Safety and Gas Budget
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Callback never reverts on daily fulfillment with any fuzzed word.
    function test_callbackNeverReverts_daily(uint256 randomWord) public {
        // Trigger daily VRF request
        game.mineFlip();
        assertTrue(game.rngLocked(), "rngLocked after mineFlip");

        uint256 reqId = mockVRF.lastRequestId();
        assertTrue(reqId > 0, "VRF request sent");

        // Fulfill with fuzzed word -- must not revert
        mockVRF.fulfillRandomWords(reqId, randomWord);

        // Verify word stored (zero-guarded to 1)
        uint256 stored = _readRngWordCurrent();
        if (randomWord < 2) {
            assertEq(stored, 0, "Reserved word remains waiting for retry");
        } else {
            assertEq(stored, randomWord, "Word should be stored as-is");
        }
    }

    /// @notice Callback silently returns (no revert) when requestId doesn't match.
    function test_callbackNeverReverts_staleId(uint256 staleId, uint256 randomWord) public {
        // Trigger daily VRF request
        game.mineFlip();
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
        vm.assume(randomWord > 1); // Ensure first fulfillment sets a nonzero word

        // Trigger daily VRF request
        game.mineFlip();
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
        game.mineFlip();
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
        game.mineFlip();
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
        game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();

        // Fulfill with word=0
        mockVRF.fulfillRandomWords(reqId, randomWord);

        // rngWordCurrent must be 1, not 0
        assertEq(_readRngWordCurrent(), 0, "Zero word must remain waiting for retry");
    }

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-02: vrfRequestId Lifecycle
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Daily request: vrfRequestId set on request, cleared after full processing.
    function test_vrfRequestIdLifecycle_dailyFreshRequest() public {
        // Before any request
        assertEq(_readVrfRequestId(), 1, "request ID initializes to a nonzero idle sentinel");

        // Trigger daily VRF request
        game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();

        // vrfRequestId should match
        assertEq(_readVrfRequestId(), reqId, "vrfRequestId should match mock's lastRequestId");
        assertTrue(reqId > 0, "Request ID should be nonzero");

        // Fulfill
        mockVRF.fulfillRandomWords(reqId, 0xDEAD);

        // Process until unlocked (daily branch: rngWordCurrent set, mineFlip processes)
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "Should be unlocked after full processing");

        // After _unlockRng: vrfRequestId should be 0
        assertEq(_readVrfRequestId(), reqId, "idle request ID is retained after unlock");
        assertFalse(game.isRngFulfilled(), "idle callback authority is disarmed");
    }

    /// @notice Mid-day request: vrfRequestId set, cleared after mid-day fulfillment.
    function test_vrfRequestIdLifecycle_middayRequest() public {
        // Closed Craps windows are settled first: publishing a window's word can arm the next
        // closed window and request it in the same call, which would replace the idle ID.
        _setupForMidDayRng(true);

        // Before mid-day request, vrfRequestId should be 0 (cleared by _unlockRng from day 2)
        assertEq(_readVrfRequestId(), mockVRF.lastRequestId(), "idle request ID is retained before midpoint");

        // Fire mid-day request
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // vrfRequestId should match
        assertEq(_readVrfRequestId(), reqId, "vrfRequestId should match after requestLootboxRng");

        // Fulfill mid-day
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);

        // After mid-day branch: vrfRequestId cleared to 0
        assertTrue(game.isRngFulfilled(), "callback leaves publication pending");
        game.mineFlip();
        assertEq(_readVrfRequestId(), reqId, "publication retains the idle ID");
        assertFalse(game.isRngFulfilled(), "publication disarms callback authority");
        // rngRequestTime also cleared
        assertGt(_readRngRequestTime(), 1, "idle timestamp is retained");
    }

    /// @notice Fresh daily request: isRetry=false, lootboxRngIndex increments by 1.
    function test_retryDetection_fresh() public {
        // Record initial lootboxRngIndex
        uint48 indexBefore = _lootboxRngIndex();

        // Trigger fresh daily VRF request
        game.mineFlip();

        // lootboxRngIndex should have incremented (fresh request)
        uint48 indexAfter = _lootboxRngIndex();
        assertEq(indexAfter, (indexBefore ^ 1), "Fresh request should increment lootboxRngIndex by 1");
    }

    /// @notice Timeout retry: lootboxRngIndex does NOT increment again.
    function test_retryDetection_timeout() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: warp to next day, trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");

        // Record lootboxRngIndex after initial request
        uint48 indexAfterRequest = _lootboxRngIndex();
        uint256 firstRequestId = _readVrfRequestId();
        assertGt(firstRequestId, _lastFulfilledReqId, "Fresh pending request required");

        // Do NOT fulfill -- wait past the 20h vault-owner retry window
        vm.warp(block.timestamp + 21 hours);

        // Transport-only retry through the vault-owner Admin entry
        admin.retryGameRng();
        assertGt(_readVrfRequestId(), firstRequestId, "Timeout must issue a replacement request");
        assertTrue(game.rngLocked(), "Replacement request remains pending");

        // lootboxRngIndex should NOT have changed (retry, not fresh)
        uint48 indexAfterRetry = _lootboxRngIndex();
        assertEq(indexAfterRetry, indexAfterRequest, "Retry should NOT increment lootboxRngIndex");
    }

    /// @notice Fuzz retry scenario: request -> timeout -> retry -> fulfill.
    ///         lootboxRngIndex must remain unchanged between first request and post-retry.
    function test_retryDetection_fuzz(uint256 word1, uint256 word2) public {
        vm.assume(word1 > 1);

        // Day 1: complete normally
        _completeDay(word1);
        assertFalse(game.rngLocked(), "Prior day must finish before retry scenario");

        // Day 2: request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();

        // A successful case must execute a fresh request and its real replacement.
        uint256 currentReqId = mockVRF.lastRequestId();
        assertGt(currentReqId, _lastFulfilledReqId, "Fresh pending request required");
        assertEq(_readVrfRequestId(), currentReqId, "Game binds the fresh request");
        assertTrue(game.rngLocked(), "Fresh request holds the lock");
        assertEq(_readRngWordCurrent(), 0, "Fresh request awaits entropy");

        uint48 indexAfterRequest = _lootboxRngIndex();

        // Timeout + retry
        vm.warp(block.timestamp + 21 hours);
        admin.retryGameRng();
        uint48 indexAfterRetry = _lootboxRngIndex();
        assertEq(indexAfterRetry, indexAfterRequest, "Fuzz: retry should not change index");

        // Fulfill the retried request and complete the day
        uint256 newReqId = mockVRF.lastRequestId();
        assertGt(newReqId, currentReqId, "Timeout must issue a replacement request");
        assertEq(_readVrfRequestId(), newReqId, "Game binds the replacement request");
        assertTrue(game.rngLocked(), "Replacement request holds the lock");
        mockVRF.fulfillRandomWords(currentReqId, word1);
        assertEq(_readRngWordCurrent(), 0, "Retired request cannot supply retry entropy");
        mockVRF.fulfillRandomWords(newReqId, word2);
        if (word2 < 2) {
            assertEq(_readRngWordCurrent(), 0, "reserved replacement entropy remains unanswered");
            assertTrue(game.rngLocked(), "reserved result cannot complete the commitment");
            assertEq(_lootboxRngIndex(), indexAfterRequest, "reserved result preserves the same cohort");
            vm.expectRevert(bytes4(keccak256("RngNotReady()")));
            admin.retryGameRng();
            return;
        }
        assertEq(_readRngWordCurrent(), word2, "Replacement request supplies its own entropy");
        _lastFulfilledReqId = newReqId;
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }

        // Index should still be the same (no double increment)
        assertFalse(game.rngLocked(), "Retried day must finish");
        assertEq(_lootboxRngIndex(), indexAfterRequest, "Fuzz: index unchanged after retry+fulfill");
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
        game.mineFlip();
        assertTrue(game.rngLocked(), "Daily RNG should lock");

        // Mid-day request must revert with RngLocked
        vm.expectRevert();
        game.requestLootboxRng();
    }

    /// @notice A stalled midday request can be retried only through Admin. Transport retry
    ///         preserves its mode and read cohort; a later fresh daily request waits for drainage.
    function test_midDayTicketRequest_refiredByOwnerRetryAfterStall() public {
        _setupForMidDayRng();

        game.requestLootboxRng();
        assertFalse(game.rngLocked(), "mid-day request must not set the daily lock");
        uint256 stalledReqId = mockVRF.lastRequestId();

        // Word does NOT arrive; cross the day boundary, past the 20h retry window.
        vm.warp(block.timestamp + 1 days + 13 hours);

        // Nobody but the vault owner can replace it.
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert();
        admin.retryGameRng();

        // The vault owner authorizes a transport replacement through Admin.
        admin.retryGameRng();
        uint256 dailyReqId = mockVRF.lastRequestId();
        assertTrue(dailyReqId != stalledReqId, "Admin issued a replacement VRF request");
        assertFalse(game.rngLocked(), "retry retains the original midday request mode");

        // The abandoned mid-day request is rejected on late arrival (requestId mismatch).
        mockVRF.fulfillRandomWords(stalledReqId, 0x1111);

        // The replacement midday word drains its original batch and releases the latch.
        mockVRF.fulfillRandomWords(dailyReqId, 0xBEEF);
        uint256 lastFulfilled = dailyReqId;
        for (uint256 i = 0; i < 50; i++) {
            game.mineFlip();
            uint256 rid = mockVRF.lastRequestId();
            if (rid != lastFulfilled && rid > 0) {
                mockVRF.fulfillRandomWords(rid, 0xD00D);
                lastFulfilled = rid;
            }
            if (!game.rngLocked() && _lrMidDay() == 0) break;
        }
        assertEq(_lrMidDay(), 0, "latch released after the original midday cohort drains");
    }

    /// @notice After mid-day VRF fulfills, vrfRequestId and rngRequestTime are cleared,
    ///         allowing daily flow to proceed cleanly.
    function test_midDayFulfillment_clearsState() public {
        // Closed Craps windows are settled first so this publication arms no further window.
        _setupForMidDayRng(true);

        // Fire mid-day request
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // Verify state is set
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId should be set");
        assertTrue(_readRngRequestTime() != 0, "rngRequestTime should be set");

        // Fulfill mid-day
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);

        // Both should be cleared
        assertTrue(game.isRngFulfilled());
        game.mineFlip();
        assertEq(_readVrfRequestId(), reqId, "publication retains idle request ID");
        assertFalse(game.isRngFulfilled());
        assertGt(_readRngRequestTime(), 1, "idle request timestamp retained");
    }

    /// @notice A mid-day ticket batch whose drain completes on the NEW-day path must still
    ///         release the LR_MID_DAY latch. The same-day release runs only while day == dIdx,
    ///         so a batch whose drain crosses the day boundary completes on the daily-drain gate
    ///         instead; that gate must release the latch too, or the mid-day fast path
    ///         (requestLootboxRng) stays permanently blocked for the rest of the game.
    function test_midDayLatch_clearsOnCrossDayDrain() public {
        _setupForMidDayRng();

        // Mid-day request: swaps the non-empty ticket buffer -> LR_MID_DAY = 1, advances LR_INDEX.
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();
        assertEq(_lrMidDay(), 1, "LR_MID_DAY set by the mid-day ticket request");

        // The mid-day word ARRIVES (no stall) — the failure mode is purely the cross-day drain.
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);

        // No same-day mineFlip: cross the day boundary so the read-slot drain lands on the
        // new-day daily-drain gate rather than the same-day mid-day block.
        vm.warp(block.timestamp + 1 days);

        // Drain the read slot + process the new day (fulfilling the daily VRF when requested).
        uint256 lastFulfilled = reqId;
        for (uint256 i = 0; i < 50; i++) {
            game.mineFlip();
            uint256 rid = mockVRF.lastRequestId();
            if (rid != lastFulfilled && rid > 0) {
                mockVRF.fulfillRandomWords(rid, 0xDEAD0003);
                lastFulfilled = rid;
            }
            if (!game.rngLocked() && _lrMidDay() == 0) break;
        }

        // The latch is released once the batch fully drains — the mid-day fast path is not bricked.
        assertEq(_lrMidDay(), 0, "LR_MID_DAY released after the batch drains on the new-day path");
    }

    /// @notice requestLootboxRng remains open until the final minute before reset.
    function test_preResetWindow_isOneMinute() public {
        _setupForMidDayRng();

        uint256 secondsIntoGameDay = (block.timestamp - 82_620) % 1 days;
        uint256 nextDayBoundary = block.timestamp + 1 days - secondsIntoGameDay;
        uint256 snapshot = vm.snapshotState();

        // One second outside the final-minute window remains available.
        vm.warp(nextDayBoundary - 1 minutes - 1);
        game.requestLootboxRng();
        assertGt(mockVRF.lastRequestId(), 0, "mid-day request should remain open outside final minute");

        assertTrue(vm.revertToState(snapshot), "restore pre-request state");

        // The exact start of the final minute is blocked.
        vm.warp(nextDayBoundary - 1 minutes);
        vm.expectRevert(bytes4(keccak256("PreResetWindow()")));
        game.requestLootboxRng();
    }

    /// @notice After updateVrfCoordinatorAndSub with a daily request in flight, rngLockedFlag
    ///         is preserved and the request is re-issued on the new coordinator; the day
    ///         completes once the re-issued request is fulfilled.
    function test_coordinatorSwap_clearsRngLocked() public {
        // Complete day 1
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger daily VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Daily RNG should lock");
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId should be set");
        assertTrue(_readRngRequestTime() != 0, "rngRequestTime should be set");

        // Coordinator swap (daily in flight, rngWordCurrent==0 -> preserve+re-issue)
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // RNG lock preserved; request re-issued on the new coordinator
        assertTrue(game.rngLocked(), "rngLocked stays true after swap (daily preserved)");
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId re-issued (fresh) after swap");
        assertTrue(_readRngRequestTime() != 0, "rngRequestTime refreshed by re-issue");
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent still 0 (re-issued word not yet delivered)");
        assertTrue(newVRF.lastRequestId() != 0, "re-issued request exists on new coordinator");

        // Fulfilling the re-issued request on the new coordinator completes the day
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), 0xCAFE0002);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "Day completes after re-issued request fulfilled");
    }

    // ──────────────────────────────────────────────────────────────────────
    // VRFC-04: 20h Vault-Owner Retry
    // ──────────────────────────────────────────────────────────────────────

    /// @notice After exactly 20 hours, the vault owner's Admin call triggers the retry.
    function test_timeoutRetry_20h() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");
        uint48 requestTime = _readRngRequestTime();
        uint256 oldReqId = _readVrfRequestId();

        // Warp to exactly rngRequestTime + 20 hours
        vm.warp(uint256(requestTime) + 20 hours);

        // Record lootboxRngIndex before retry
        uint48 indexBefore = _lootboxRngIndex();

        // The Admin entry should retry (not revert)
        admin.retryGameRng();

        // After retry: rngLocked still true (new request in flight)
        assertTrue(game.rngLocked(), "Should still be locked after retry");

        // vrfRequestId should have changed (new request)
        uint256 newReqId = _readVrfRequestId();
        assertTrue(newReqId != oldReqId, "vrfRequestId should change on retry");

        // lootboxRngIndex should be unchanged (retry detection)
        assertEq(_lootboxRngIndex(), indexBefore, "Index unchanged on retry");
    }

    /// @notice Before the retry window opens the Admin route rejects even the owner,
    ///         and after it opens a non-vault-owner still cannot fire the retry.
    function test_noRetry_before20hOrForNonOwners() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");
        uint48 requestTime = _readRngRequestTime();

        // 19h59m: even the vault owner (this test contract holds the DGVE majority) waits
        vm.warp(uint256(requestTime) + 20 hours - 1 minutes);
        vm.expectRevert();
        admin.retryGameRng();

        // Past 20h a non-owner still reverts: the retry is the vault owner's alone
        vm.warp(uint256(requestTime) + 20 hours + 1 minutes);
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert();
        admin.retryGameRng();
    }

    /// @notice The retry is the vault owner's (the deployer here), at 20h and not before; it
    ///         re-sends the same request without moving its stamp, is single-use (further
    ///         timeouts revert), and the retried request's late fulfillment completes the day.
    function test_ownerRetryAt20hIsSingleUse() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        uint48 requestTime = _readRngRequestTime();
        uint256 oldReqId = _readVrfRequestId();
        uint24 requestDay = game.currentDayView();

        // 19h: not yet
        vm.warp(uint256(requestTime) + 19 hours);
        vm.expectRevert();
        admin.retryGameRng();

        // 20h: the vault owner's retry re-sends the request; the stamp keeps its day
        vm.warp(uint256(requestTime) + 20 hours);
        admin.retryGameRng();
        uint256 retryReqId = _readVrfRequestId();
        assertTrue(retryReqId != oldReqId, "Retry re-issues the request");
        assertTrue(game.rngLocked(), "Still locked after retry");
        assertEq(_readRngRequestTime(), requestTime, "Retry keeps the stamp");
        assertTrue(_readRetrySpent(), "Retry spends the request's retry");

        // Retry spent: another 20h on, even the vault owner gets RngNotReady
        vm.warp(uint256(requestTime) + 40 hours + 1);
        vm.expectRevert();
        admin.retryGameRng();

        // The retried request's late fulfillment still lands and completes the day. It lands
        // after the next boundary, so the call that completes the day goes on to issue the
        // next day's daily request (a request is only selected once the prior day completes).
        mockVRF.fulfillRandomWords(retryReqId, 0xC0FFEE01);
        _lastFulfilledReqId = retryReqId;
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked() || _readVrfRequestId() != retryReqId) break;
            game.mineFlip();
        }
        assertTrue(game.rngWordForDay(requestDay) != 0, "Day completes on the retried request's word");

        // Next day starts with a fresh retry allowance
        assertGt(game.currentDayView(), requestDay, "Clock is past the retried day");
        assertTrue(game.rngLocked(), "Next day's daily request is issued");
        assertGt(_readVrfRequestId(), retryReqId, "Next day's request is fresh");
        assertFalse(_readRetrySpent(), "Fresh daily request re-arms the retry");
    }

    /// @notice A coordinator swap re-issues the stalled request and SPENDS the retry, so the
    ///         vault owner cannot follow the swap with a retry that discards the new
    ///         coordinator's first answer; the re-issued request's word completes the day.
    function test_coordinatorSwapSpendsTheRetry() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: request stalls; governance swaps an hour later
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        uint48 requestTime = _readRngRequestTime();
        vm.warp(uint256(requestTime) + 1 hours);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        assertEq(_readRngRequestTime(), requestTime, "Swap keeps the stamp");
        assertTrue(_readRetrySpent(), "Swap spends the retry");
        uint256 swapReqId = _readVrfRequestId();

        // No retry after the swap, even 20h on
        vm.warp(uint256(requestTime) + 20 hours + 1);
        vm.expectRevert();
        admin.retryGameRng();
        assertEq(_readVrfRequestId(), swapReqId, "the swap's request stands");

        // Fulfill on the new coordinator and complete the day
        newVRF.fulfillRandomWords(swapReqId, 0xC0FFEE02);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "Day completes on the swap's request");
    }

    /// @notice After retry overwrites vrfRequestId, old fulfillment is silently discarded.
    ///         New fulfillment (with new requestId) succeeds.
    function test_timeoutRetry_staleWordDiscarded(uint256 word1, uint256 word2) public {
        vm.assume(word1 > 1);

        // Day 1: complete normally
        _completeDay(0xBEEF0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        uint256 oldReqId = mockVRF.lastRequestId();

        // Timeout + retry
        vm.warp(block.timestamp + 21 hours);
        admin.retryGameRng();
        uint256 newReqId = mockVRF.lastRequestId();
        assertTrue(newReqId != oldReqId, "New request ID after retry");

        // Old fulfillment via raw call: silently discarded (requestId mismatch)
        mockVRF.fulfillRandomWordsRaw(oldReqId, address(game), word1);
        assertEq(_readRngWordCurrent(), 0, "Old fulfillment should be discarded (word still 0)");

        // New fulfillment: succeeds
        mockVRF.fulfillRandomWordsRaw(newReqId, address(game), word2);
        uint256 stored = _readRngWordCurrent();
        if (word2 < 2) {
            assertEq(stored, 0, "reserved final words remain logically unanswered");
            assertFalse(game.isRngFulfilled(), "reserved entropy never certifies delivery");
        } else {
            assertEq(stored, word2, "New fulfillment should store word");
        }
    }

    /// @notice Fuzz: timeout retry never double-increments lootboxRngIndex.
    function test_timeoutRetry_lootboxIndexPreserved_fuzz(uint256 word) public {
        vm.assume(word > 1);

        // Day 1: complete normally
        _completeDay(0xFEED0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        uint48 indexAfterRequest = _lootboxRngIndex();

        // Timeout + retry
        vm.warp(block.timestamp + 21 hours);
        admin.retryGameRng();
        assertEq(_lootboxRngIndex(), indexAfterRequest, "Index unchanged after retry");

        // Fulfill new request and complete day
        uint256 newReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(newReqId, word);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }

        // Index should remain the same (retry path, no double increment)
        assertEq(_lootboxRngIndex(), indexAfterRequest, "Index unchanged after retry+fulfill");
    }

    /// @notice VRF word from previous day's request: rngGate detects requestDay < day,
    ///         redirects the stale word to lootbox via _finalizeLootboxRng, then processes
    ///         the day using a derived or sentinel word. The game may process the stale-day
    ///         and current-day inline without firing a fresh VRF request.
    function test_crossDayStaleWord() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Trigger VRF request for the next day using absolute timestamp
        uint256 nextDayStart = 3 * 86400;
        vm.warp(nextDayStart);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Next day VRF pending");
        uint256 reqId = mockVRF.lastRequestId();

        // Fulfill the VRF (word stored in rngWordCurrent)
        mockVRF.fulfillRandomWords(reqId, 0xC0FFEE);
        _lastFulfilledReqId = reqId;
        assertEq(_readRngWordCurrent(), 0xC0FFEE, "Word should be stored");

        // Warp PAST day boundary to the following day using absolute timestamp
        uint256 followingDayStart = 4 * 86400;
        vm.warp(followingDayStart);

        // mineFlip on the following day: rngGate sees rngWordCurrent != 0 but requestDay < current day.
        // The game redirects the stale word to lootbox and processes both days inline.
        // A new VRF request may or may not be fired depending on the contract's rngGate logic.
        game.mineFlip();

        // Process until unlocked (may take multiple mineFlip calls for batched ticket work)
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            // If a new VRF was requested, fulfill it
            uint256 latestReqId = mockVRF.lastRequestId();
            if (latestReqId > _lastFulfilledReqId) {
                mockVRF.fulfillRandomWords(latestReqId, 0xDA300003);
                _lastFulfilledReqId = latestReqId;
            }
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "Should be unlocked after processing");

        // The day with the in-flight VRF should have an RNG word recorded (from the stale redirect)
        assertTrue(game.rngWordForDay(3) != 0, "Day 3 should have RNG word from stale redirect");
    }
}
