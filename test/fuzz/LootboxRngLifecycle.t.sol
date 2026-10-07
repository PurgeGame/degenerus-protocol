// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title LootboxRngLifecycle -- Audit tests for lootbox RNG index lifecycle
/// @notice Covers LBOX-01 (index mutations), LBOX-02 (word writes), LBOX-03 (zero guards),
///         LBOX-04 (entropy uniqueness), LBOX-05 (full lifecycle).
contract LootboxRngLifecycle is DeployProtocol {
    VRFHandler public vrfHandler;

    /// @dev Storage slots for direct state inspection via vm.load (GameSlots, pinned by
    ///      StorageSlotPins).
    uint256 constant SLOT_PACKED_0 = GameSlots.RNG_REQUEST_TIME;
    uint256 constant SLOT_RNG_WORD_CURRENT = GameSlots.RNG_WORD_CURRENT;
    uint256 constant SLOT_VRF_REQUEST_ID = GameSlots.VRF_REQUEST_ID;

    /// @dev Seed domains (DegenerusGameLootboxModule): a queued entry's root is
    ///      hash4(QUEUED_ORDER_DOMAIN, word, buffer, position); box n seeds from
    ///      hash4(root, walletId, BOX_OPEN_TAG, n) and the boon draw from
    ///      hash4(root, walletId, BOX_BOON_TAG, buffer).
    uint256 constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572;
    uint256 constant BOX_OPEN_TAG = 0x426f784f70656e;
    uint256 constant BOX_BOON_TAG = 0x426f78426f6f6e;

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
        _finishReadBoxes();
        game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
        game.mineFlip(); // required publication; the callback stores only the final word
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
        _finishReadBoxes();
        _finishReadConsumers();
    }

    /// @dev Read vrfRequestId directly from storage slot 5.
    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    /// @dev Read rngWordCurrent directly from storage slot 4.
    function _readRngWordCurrent() internal view returns (uint256) {
        return RecyclingState.currentWord(address(game));
    }

    /// @dev Read rngRequestTime from packed slot 0 (uint48).
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> (GameSlots.RNG_REQUEST_TIME_OFFSET * 8));
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

        _finishReadBoxes();

        if (quietCraps) {
            mockVRF.fundSubscription(1, 100e18);
            _settleMiddayRequests();
        }

        // Purchase with lootbox amount to create pending ETH
        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        // Fund VRF subscription with LINK
        if (!quietCraps) mockVRF.fundSubscription(1, 100e18);

        ts = block.timestamp;
    }

    /// @dev Read lootboxRngIndex directly from storage slot 34 (low 48 bits of lootboxRngPacked)
    ///      (post V62 lootbox repack: was 35).
    function _readLootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Read _lootboxWord(index) from storage (mapping at slot 34, post V62 repack: was 36).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Read _lootboxWord(index) via storage.
    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        return _lootboxRngWord(index);
    }

    /// @dev Next unsettled position of the read buffer (left at the read count on completion).
    function _boxCursor() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8))
            & type(uint48).max;
    }

    /// @dev The stored entry at (`index`, `position`); a purchase never rewrites another's entry.
    function _entry(uint48 index, uint256 position) internal view returns (uint256) {
        return RecyclingState.boxEntry(address(game), index, position);
    }

    /// @dev Whether the entry at (`index`, `position`) has settled: the cursor alone marks it, and
    ///      only while `index` is the sealed read buffer (a later seal of the same physical buffer
    ///      starts a new cohort).
    function _settled(uint48 index, uint256 position) internal view returns (bool) {
        return RecyclingState.readBuffer(address(game)) == index && _boxCursor() > position;
    }

    function _rootWord(uint256 word, uint48 index, uint256 position) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(QUEUED_ORDER_DOMAIN, word, uint256(index), position)));
    }

    /// @dev Make a lootbox purchase for buyer with the given lootbox ETH amount. Returns the
    ///      position its one entry took in the write buffer.
    function _makePurchase(address buyer, uint256 lootboxAmount) internal returns (uint256 position) {
        uint48 index = _readLootboxRngIndex();
        position = RecyclingState.boxCount(address(game), index);
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        // numCoins = 400 (minimum for 1 ETH lootbox), total = purchase + lootbox
        game.purchase{value: lootboxAmount + 0.01 ether}(
            0, 400, BoxOrderLib.boCustomFloor(lootboxAmount), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertEq(RecyclingState.boxCount(address(game), index), position + 1, "one appended entry per purchase");
        uint256 entry = _entry(index, position);
        assertEq(BoxOrderLib.boId(entry), game.walletIdOf(buyer), "the entry holds the buyer's wallet ID");
        assertEq(BoxOrderLib.boCustomCount(entry), 1, "one custom box");
        assertEq(BoxOrderLib.boSizeWei(entry), lootboxAmount, "of the purchased size");
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-01: Index Mutation Correctness
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Fresh daily request increments lootboxRngIndex by exactly 1.
    function test_indexIncrementsOnFreshDaily() public {
        uint48 indexBefore = _readLootboxRngIndex();

        // mineFlip triggers daily VRF request -> _finalizeRngRequest(isRetry=false) -> index++
        game.mineFlip();

        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(indexAfter, indexBefore ^ 1, "Fresh daily request must toggle the physical tag");
    }

    /// @notice A mid-day request (mineFlip's RequestMidday stage) toggles the physical write tag.
    function test_indexIncrementsOnMidDay() public {
        _setupForMidDayRng();

        uint48 indexBefore = _readLootboxRngIndex();

        // Pending lootbox ETH at the threshold makes the mid-day request the engine's next work.
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday), "mid-day request is due");
        game.mineFlip();

        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(indexAfter, indexBefore ^ 1, "Mid-day request must toggle the physical tag");
    }

    /// @notice Retry after 20h timeout does NOT increment lootboxRngIndex.
    function test_indexNoIncrementOnRetry(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: warp to next day, trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");

        // Record index after initial request (already incremented)
        uint48 indexAfterRequest = _readLootboxRngIndex();

        // Do NOT fulfill -- wait past the 20h vault-owner retry window
        vm.warp(block.timestamp + 21 hours);

        // Retry fires through the Admin owner entry
        admin.retryGameRng();

        // lootboxRngIndex should NOT have changed (retry, not fresh)
        uint48 indexAfterRetry = _readLootboxRngIndex();
        assertEq(indexAfterRetry, indexAfterRequest, "Retry should NOT increment lootboxRngIndex");
    }

    /// @notice Coordinator swap does NOT change lootboxRngIndex.
    function test_indexNoIncrementOnCoordinatorSwap() public {
        // Complete day 1
        _completeDay(0xDEAD0001);

        // Day 2: trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");

        // Record index before swap
        uint48 indexBefore = _readLootboxRngIndex();

        // Coordinator swap
        _doCoordinatorSwap();

        // Index unchanged
        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(indexAfter, indexBefore, "Coordinator swap should NOT change lootboxRngIndex");
    }

    /// @notice Over N days (2-10), lootboxRngIndex increments exactly N times.
    function test_indexSequentialAcrossMultipleDays(uint8 numDays) public {
        numDays = uint8(bound(numDays, 2, 10));

        uint48 indexBefore = _readLootboxRngIndex();

        // Complete each day using absolute timestamps, starting from day 2 (setUp already warped there)
        for (uint8 d = 2; d <= numDays + 1; d++) {
            vm.warp(uint256(d) * 86400);
            _completeDay(uint256(0xDEAD0000 + d));
        }

        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(
            indexAfter,
            indexBefore ^ uint48(numDays & 1),
            "write tag must toggle exactly once per fresh day"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-02: Word-to-Index Correctness
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Daily VRF fulfillment writes fuzzed word to _lootboxWord(index-1).
    function test_wordWriteDaily(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        uint48 indexBefore = _readLootboxRngIndex();

        // mineFlip triggers VRF request -> index increments
        game.mineFlip();

        // Fulfill VRF
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        game.mineFlip(); // required publication; the callback stores only the final word

        // Complete processing
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }

        // Word should be stored at indexBefore (the index reserved by this request)
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, vrfWord, "daily and ticket words use the same normalized entropy");
    }

    /// @notice Mid-day VRF fulfillment writes fuzzed word to _lootboxWord(index-1).
    function test_wordWriteMidDay(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        // Closed Craps windows are settled first: publishing a window's word can arm the next
        // closed window and request it in the same call, recycling this word's buffer.
        _setupForMidDayRng(true);

        uint48 indexBefore = _readLootboxRngIndex();

        // The engine's mid-day request seals the write buffer
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday), "mid-day request is due");
        game.mineFlip();

        // Fulfill mid-day VRF
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        game.mineFlip(); // required publication; the callback stores only the final word

        // Word stored at indexBefore (the buffer the mid-day request sealed)
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, vrfWord, "Mid-day word should be stored at correct index");
    }

    /// @notice Stale daily word (requestDay < current day) redirected to lootbox index.
    ///         The stale word is stored at the reserved index. The stored value may be the
    ///         raw VRF word or a keccak256-derived word depending on the backfill path.
    function test_wordWriteStaleRedirect(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Next day (day 3 absolute): trigger VRF request
        uint256 day3Start = 3 * 86400;
        vm.warp(day3Start);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");
        uint256 reqId = mockVRF.lastRequestId();

        // Record the index that the day 3 request reserved
        // Index was incremented by mineFlip, so the reserved slot is (currentIndex - 1)
        uint48 reservedIndex = (_readLootboxRngIndex() ^ 1);

        // Fulfill the VRF (word stored in rngWordCurrent, NOT yet in lootboxRngWordByIndex)
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        game.mineFlip(); // required publication; the callback stores only the final word
        _lastFulfilledReqId = reqId;

        // Warp past day boundary to day 4 WITHOUT calling mineFlip
        uint256 day4Start = 4 * 86400;
        vm.warp(day4Start);

        // The stale word should be stored at the reserved index. It is read before day 4's
        // first call: the call that completes the stale day also issues day 4's request,
        // which recycles this buffer.
        // The stored value may be the raw VRF word or a derived (keccak256) word
        // depending on whether the stale redirect path or backfill path was taken.
        uint256 storedWord = _readLootboxWord(reservedIndex);
        assertTrue(storedWord != 0, "Stale redirect should store nonzero word at correct index");

        // mineFlip on day 4: rngGate sees requestDay < day, redirects stale word
        // to lootbox via _finalizeLootboxRng. The game processes both days inline.
        game.mineFlip();

        // Process the stale day until its request is retired (the completing call may issue
        // day 4's request); the stale word is still the published word until then.
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked() || _readVrfRequestId() != reqId) break;
            assertEq(_readLootboxWord(reservedIndex), storedWord, "stale word stays at the reserved index");
            game.mineFlip();
        }
        assertTrue(game.rngWordForDay(3) != 0, "Stale word completes its own day");
    }

    /// @notice A coordinator swap re-sends the stalled request for the same reserved index, and
    ///         its word (landing days late) finalizes that index: nothing is orphaned.
    function test_swapReissueFinalizesTheReservedIndex() public {
        // Complete the first post-deploy day (day 2) normally
        _completeDay(0xDEAD0001);

        // Next day (day 3 absolute): trigger VRF request
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");
        uint48 reservedIndex = (_readLootboxRngIndex() ^ 1);

        // Coordinator swap: the same request is re-sent on the new coordinator
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        mockVRF = newVRF;
        assertEq((_readLootboxRngIndex() ^ 1), reservedIndex, "the reserved index is kept");
        assertEq(_readLootboxWord(reservedIndex), 0, "no word yet");

        // The re-sent request is answered two days late and finishes day 3
        vm.warp(5 * 86400);
        newVRF.fundSubscription(1, 100e18);
        uint256 published = _fulfillAndDrain(newVRF, 0xDEAD0005, reservedIndex);
        assertTrue(published != 0, "the re-sent request's word finalizes the reserved index");
    }

    function _deliverCallback(uint256 request, uint256 word) private {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vm.prank(address(mockVRF));
        game.rawFulfillRandomWords(request, words);
    }

    function test_ZeroRequestIdCannotPublishUnrequestedEntropy() public {
        uint48 index = _readLootboxRngIndex();
        _deliverCallback(0, 42);
        assertEq(_readLootboxWord(index ^ 1), 0);
        assertEq(_readLootboxRngIndex(), index);
    }

    /// @notice Duplicate/stale callbacks cannot replace a fulfilled or newly reserved word.
    function test_wordWriteIdempotent(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        uint48 indexBefore = _readLootboxRngIndex();
        _completeDay(vrfWord);
        uint256 oldRequest = mockVRF.lastRequestId();
        _deliverCallback(oldRequest, vrfWord ^ 0xBEEF);
        assertEq(_readLootboxWord(indexBefore), vrfWord, "duplicate callback changed the read word");
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, oldRequest);
        assertEq(_readLootboxWord(indexBefore), 0, "completed normal words leave storage history");
        _deliverCallback(oldRequest, vrfWord);
        assertEq(_readLootboxWord(indexBefore ^ 1), 0, "stale callback cannot fulfill the new request");
        uint256 nextWord = (vrfWord ^ 0xBEEF) | 2;
        mockVRF.fulfillRandomWords(request, nextWord);
        for (uint256 i; i < 50 && game.rngLocked(); ++i) game.mineFlip();
        assertEq(_readLootboxWord(indexBefore ^ 1), nextWord);
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-03: Zero-State Guards
    // ──────────────────────────────────────────────────────────────────────

    /// @notice A daily word of 0 never records as 0 or as the request sentinel 1.
    function test_zeroGuardRawFulfill() public {
        uint48 buffer = _readLootboxRngIndex();
        uint24 day = game.currentDayView();
        game.mineFlip();
        uint256 request = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(request, 0);
        assertEq(_readRngWordCurrent(), 0, "reserved zero remains waiting");
        assertEq(_readLootboxWord(buffer), 0, "no word was published");
        assertEq(game.rngWordForDay(day), 0);
        assertTrue(game.rngLocked(), "unanswered session stays locked for retry");
        vm.warp(block.timestamp + 20 hours + 2);
        admin.retryGameRng();
        assertGt(mockVRF.lastRequestId(), request, "reserved zero requires a fresh retry");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 2);
        for (uint256 i; i < 100 && game.rngLocked(); ++i) game.mineFlip();
        assertEq(_readLootboxWord(buffer), 2, "retry uses the same read buffer");
    }

    /// @notice A reserved response after rotation cannot re-arm the retry already spent by that rotation.
    function test_reservedWordAfterCoordinatorSwapDoesNotRearmRetry() public {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        game.mineFlip();
        uint48 buffer = _readLootboxRngIndex() ^ 1;
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        mockVRF = newVRF;
        newVRF.fundSubscription(1, 100e18);
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), 0);
        assertEq(_readRngWordCurrent(), 0);
        assertEq(_readLootboxWord(buffer), 0);
        uint256 request = newVRF.lastRequestId();
        vm.warp(block.timestamp + 20 hours + 2);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        admin.retryGameRng();
        assertEq(newVRF.lastRequestId(), request, "rotation already consumed the retry allowance");
        assertEq(_readRngWordCurrent(), 0, "reserved response remains unanswered");
        assertEq(_readLootboxWord(buffer), 0, "reserved entropy cannot publish a word");
    }

    /// @dev Answer the live request and drain its session until its day completes. A late answer
    ///      can complete its day after the next boundary, and the completing call then issues
    ///      the next request, so the drain also stops once the request ID moves on. Returns the
    ///      word published at `index` while the answered request was still live (the next
    ///      request recycles that buffer).
    function _fulfillAndDrain(MockVRFCoordinator vrf, uint256 word, uint48 index)
        internal returns (uint256 published)
    {
        uint256 request = vrf.lastRequestId();
        assertEq(_readVrfRequestId(), request, "answering the live request");
        vrf.fulfillRandomWords(request, word);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked() || _readVrfRequestId() != request) break;
            game.mineFlip();
            if (_readVrfRequestId() == request && _readLootboxWord(index) != 0) published = _readLootboxWord(index);
        }
        assertTrue(!game.rngLocked() || _readVrfRequestId() != request, "answered request's day completes");
    }

    /// @notice Mid-day rawFulfillRandomWords with word=0 stores 1 at the lootbox index.
    function test_zeroGuardMidDay() public {
        _setupForMidDayRng();
        uint48 buffer = _readLootboxRngIndex();
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday), "mid-day request is due");
        game.mineFlip();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0);
        assertEq(_readRngWordCurrent(), 0, "reserved zero remains waiting");
        assertEq(_readLootboxWord(buffer), 0, "midday zero is never published");
        assertFalse(game.isRngFulfilled());
        assertEq(_readLootboxRngIndex(), buffer ^ 1, "the reservation remains unchanged");
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-04: Entropy Uniqueness
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Two different players purchasing at the same index produce different entropy.
    ///         First-roll entropy = H(root, walletId, BOX_OPEN_TAG, 1) with
    ///         root = H(QUEUED_ORDER_DOMAIN, word, buffer, position): two purchases hold different
    ///         positions and different wallet IDs, so their preimages differ.
    function test_entropyUniqueDifferentPlayers(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");

        uint48 purchaseIndex = _readLootboxRngIndex();

        // Both buyers purchase at the same index with identical amounts
        uint256 pos1 = _makePurchase(buyer1, 1 ether);
        uint256 pos2 = _makePurchase(buyer2, 1 ether);
        assertEq(pos2, pos1 + 1, "consecutive positions");
        uint256 entry1 = _entry(purchaseIndex, pos1);
        uint256 entry2 = _entry(purchaseIndex, pos2);
        // Complete and settle the cohort before another request can be admitted.
        _completeDay(vrfWord);

        uint256 storedWord = _readLootboxWord(purchaseIndex);
        assertTrue(storedWord != 0, "Word should be stored");

        assertTrue(_settled(purchaseIndex, pos1), "both entries settled on the cohort's word");
        assertTrue(_settled(purchaseIndex, pos2), "both entries settled on the cohort's word");
        assertEq(_entry(purchaseIndex, pos1), entry1, "settlement leaves the entry word untouched");
        assertEq(_entry(purchaseIndex, pos2), entry2, "settlement leaves the entry word untouched");

        uint256 entropy1 = uint256(keccak256(abi.encode(
            _rootWord(storedWord, purchaseIndex, pos1), uint256(game.walletIdOf(buyer1)), BOX_OPEN_TAG, uint256(1))));
        uint256 entropy2 = uint256(keccak256(abi.encode(
            _rootWord(storedWord, purchaseIndex, pos2), uint256(game.walletIdOf(buyer2)), BOX_OPEN_TAG, uint256(1))));

        assertTrue(entropy1 != entropy2, "Different players must produce different entropy");
    }

    /// @notice One wallet buying twice in one cohort holds two entries at two positions, and the
    ///         position keeps their roots (hence every box seed) apart.
    function test_entropyUniqueSamePlayerTwoPositions(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        address buyer = makeAddr("twiceBuyer");
        uint48 index = _readLootboxRngIndex();
        uint256 pos1 = _makePurchase(buyer, 0.5 ether);
        uint256 entry1 = _entry(index, pos1);
        uint256 pos2 = _makePurchase(buyer, 0.5 ether);
        assertEq(pos2, pos1 + 1, "the second purchase appends, it never merges");
        assertEq(_entry(index, pos1), entry1, "the first entry is unchanged by the second purchase");
        _completeDay(vrfWord);
        uint256 storedWord = _readLootboxWord(index);
        assertTrue(_settled(index, pos1) && _settled(index, pos2), "both entries settled");
        uint256 id = game.walletIdOf(buyer);
        uint256 seed1 = uint256(keccak256(abi.encode(_rootWord(storedWord, index, pos1), id, BOX_OPEN_TAG, uint256(1))));
        uint256 seed2 = uint256(keccak256(abi.encode(_rootWord(storedWord, index, pos2), id, BOX_OPEN_TAG, uint256(1))));
        assertTrue(seed1 != seed2, "same wallet, same cohort: the position separates the draws");
    }

    /// @notice Same player with different amounts at different indices produces different entropy.
    ///         Different committed words select different streams; amount does not select the seed.
    function test_entropyUniqueDifferentCommittedWords(uint256 vrfWord) public {
        // Words 0 and 1 are sentinels for both draws, including the derived second word.
        vm.assume(vrfWord > 1 && (vrfWord ^ 0xBEEF) > 1);

        address buyer = makeAddr("amountBuyer");
        uint48 index1 = _readLootboxRngIndex();

        // First purchase: 1 ether lootbox on day 2 (setUp already warped to day 2)
        uint256 pos1 = _makePurchase(buyer, 1 ether);
        _completeDay(vrfWord);

        uint256 word1 = _readLootboxWord(index1);

        // Warp to day 3: purchase 2 ether lootbox
        vm.warp(3 * 86400);
        uint48 index2 = _readLootboxRngIndex();
        uint256 pos2 = _makePurchase(buyer, 2 ether);
        uint256 word2Seed = vrfWord ^ 0xBEEF;
        if (word2Seed == 0) word2Seed = 1;
        _completeDay(word2Seed);

        uint256 word2 = _readLootboxWord(index2);

        // Compute entropy for each
        uint256 id = game.walletIdOf(buyer);
        uint256 entropy1 = uint256(keccak256(abi.encode(_rootWord(word1, index1, pos1), id, BOX_OPEN_TAG, uint256(1))));
        uint256 entropy2 = uint256(keccak256(abi.encode(_rootWord(word2, index2, pos2), id, BOX_OPEN_TAG, uint256(1))));

        // Different VRF words -> different entropy
        assertTrue(entropy1 != entropy2, "Different committed words must produce different entropy");
    }

    /// @notice Same player purchasing on different days produces different entropy.
    ///         Even if words repeat, the boon domain binds the recorded index.
    function test_boonEntropyUniqueDifferentIndices(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        address buyer = makeAddr("dayBuyer");
        uint48 index1 = _readLootboxRngIndex();

        // First purchase on day 2 (setUp already warped to day 2)
        uint256 pos1 = _makePurchase(buyer, 1 ether);
        _completeDay(vrfWord);

        uint256 word1 = _readLootboxWord(index1);

        // Warp to day 3: purchase same amount
        vm.warp(3 * 86400);
        uint48 index2 = _readLootboxRngIndex();
        uint256 pos2 = _makePurchase(buyer, 1 ether);
        // Use same VRF word to isolate the day variable
        _completeDay(vrfWord);

        uint256 word2 = _readLootboxWord(index2);

        // The boon root binds each stored order index.
        assertNotEq(index1, index2, "fixture must advance the order index");
        uint256 id = game.walletIdOf(buyer);
        uint256 entropy1 = uint256(keccak256(abi.encode(_rootWord(word1, index1, pos1), id, BOX_BOON_TAG, uint256(index1))));
        uint256 entropy2 = uint256(keccak256(abi.encode(_rootWord(word2, index2, pos2), id, BOX_BOON_TAG, uint256(index2))));

        // Different recorded indices -> different boon entropy
        assertTrue(entropy1 != entropy2, "Different indices must produce different boon entropy");
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-05: Full Purchase-to-Open Lifecycle
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Full daily lifecycle: purchase -> mineFlip -> VRF fulfill -> process -> the engine opens the box.
    function test_fullLifecycleDailyPath() public {
        address buyer = makeAddr("dailyBuyer");

        // Record index at purchase time
        uint48 purchaseIndex = _readLootboxRngIndex();

        // Purchase lootbox
        uint256 pos = _makePurchase(buyer, 1 ether);

        // mineFlip triggers VRF request
        game.mineFlip();
        assertTrue(game.rngLocked(), "Should be locked after VRF request");

        // VRF fulfills
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, 0xDEAD0001);

        // Process until unlocked
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "Should be unlocked after processing");

        // Verify word was stored before opening
        uint256 storedWord = _readLootboxWord(purchaseIndex);
        assertTrue(storedWord != 0, "Word should be stored at purchase index before open");

        // The engine's human-box stage opens the box on that word.
        vm.startPrank(buyer);
        _mineAll(16);
        vm.stopPrank();
        assertTrue(_settled(purchaseIndex, pos), "the engine opened the box on its word");
    }

    /// @notice Full mid-day lifecycle: purchase -> mid-day request -> VRF fulfill -> the engine opens the box.
    function test_fullLifecycleMidDayPath() public {
        // Setup: complete a day first so daily word exists for today. Closed Craps windows are
        // settled first so the publication below arms no further window and requests nothing.
        _setupForMidDayRng(true);

        address buyer = makeAddr("midDayBuyer");

        // Record the index at purchase time
        uint48 purchaseIndex = _readLootboxRngIndex();

        // Purchase lootbox (creates pending ETH for the mid-day request)
        uint256 pos = _makePurchase(buyer, 1 ether);

        // The engine's mid-day request seals the write buffer
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday), "mid-day request is due");
        game.mineFlip();

        // VRF fulfills mid-day (writes directly to lootboxRngWordByIndex)
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);
        game.mineFlip(); // mandatory midday publication

        // Verify word stored
        uint256 storedWord = _readLootboxWord(purchaseIndex);
        assertTrue(storedWord != 0, "Mid-day word should be stored at purchase index");

        // The engine's human-box stage opens the box on that word.
        vm.startPrank(buyer);
        _mineAll(16);
        vm.stopPrank();
        assertTrue(_settled(purchaseIndex, pos), "the engine opened the box on its word");
    }

    /// @notice Before VRF fulfillment the engine waits (RngNotReady) and the box is DEFERRED,
    ///         not dropped: it stays queued for the human-box stage of its word.
    function test_fullLifecycleRngNotReady() public {
        address buyer = makeAddr("notReadyBuyer");

        // Record index at purchase time
        uint48 purchaseIndex = _readLootboxRngIndex();

        // Purchase lootbox
        uint256 pos = _makePurchase(buyer, 1 ether);
        uint256 entry = _entry(purchaseIndex, pos);

        // mineFlip triggers VRF request (index increments)
        game.mineFlip();
        assertTrue(game.rngLocked(), "Should be locked after VRF request");

        // Do NOT fulfill VRF -- word at purchaseIndex is still 0

        // The engine's only action is to wait for the word; the box stays queued (deferred,
        // not dropped) for the human-box stage once the word lands.
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        assertEq(RecyclingState.readBuffer(address(game)), purchaseIndex, "the request sealed the purchase buffer");
        assertEq(RecyclingState.boxCount(address(game), purchaseIndex), pos + 1, "the seal latched the entry");
        assertEq(_entry(purchaseIndex, pos), entry, "the entry is intact");
        assertFalse(_settled(purchaseIndex, pos), "box still queued -- not consumed while the word is pending");
    }

    /// @notice Multiple indices: purchases at different indices each use their respective VRF word.
    function test_fullLifecycleMultipleIndices() public {
        address buyer = makeAddr("multiBuyer");

        // First index: purchase at index N on day 2 (setUp already warped to day 2)
        uint48 indexN = _readLootboxRngIndex();
        uint256 posN = _makePurchase(buyer, 1 ether);

        // Complete the first post-deploy day (stores word at indexN)
        _completeDay(0xDEAD0001);
        uint256 wordN = _readLootboxWord(indexN);
        assertGt(wordN, 0);
        assertTrue(game.boxIndexComplete(indexN), "first read settled before next request");
        assertTrue(_settled(indexN, posN), "the first day's box opened on its word");

        // Next day (day 3 absolute): purchase at index N+1
        vm.warp(3 * 86400);
        uint48 indexN1 = _readLootboxRngIndex();
        assertEq(indexN1, indexN ^ 1, "Index should have incremented after first day");

        uint256 posN1 = _makePurchase(buyer, 1 ether);

        // Complete the second day (stores word at indexN1)
        _completeDay(0xDEAD0002);

        // The previous cycle is settled and invalidated; its event is the replay source.
        assertEq(_readLootboxWord(indexN), 0);
        uint256 wordN1 = _readLootboxWord(indexN1);
        assertTrue(wordN != 0, "First cycle had a nonzero committed word");
        assertTrue(wordN1 != 0, "Word at indexN+1 should be nonzero");
        assertTrue(wordN != wordN1, "Different days should have different words");

        // Both boxes open in order: each day's human-box stage consumed its own cohort's entry.
        vm.startPrank(buyer);
        _mineAll(16);
        vm.stopPrank();
        assertTrue(_settled(indexN1, posN1), "the second day's box opened on its word");
    }
}
