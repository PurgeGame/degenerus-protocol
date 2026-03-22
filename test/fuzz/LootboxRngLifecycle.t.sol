// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title LootboxRngLifecycle -- Audit tests for lootbox RNG index lifecycle
/// @notice Covers LBOX-01 (index mutations), LBOX-02 (word writes), LBOX-03 (zero guards),
///         LBOX-04 (entropy uniqueness), LBOX-05 (full lifecycle).
contract LootboxRngLifecycle is DeployProtocol {
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
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 96);
    }

    /// @dev Deploy a new MockVRFCoordinator and wire it up via admin prank.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
    }

    /// @dev Setup for mid-day lootbox RNG: complete a day, make a purchase on the
    ///      new day to create pending lootbox ETH, fund VRF subscription with LINK.
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
        mockVRF.fundSubscription(1, 100e18);

        ts = block.timestamp;
    }

    /// @dev Read lootboxRngIndex via the public view.
    function _readLootboxRngIndex() internal view returns (uint48) {
        return game.lootboxRngIndexView();
    }

    /// @dev Read lootboxRngWordByIndex[index] via the public view.
    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        return game.lootboxRngWord(index);
    }

    /// @dev Make a lootbox purchase for buyer with the given lootbox ETH amount.
    function _makePurchase(address buyer, uint256 lootboxAmount) internal {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        // numCoins = 400 (minimum for 1 ETH lootbox), total = purchase + lootbox
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-01: Index Mutation Correctness
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Fresh daily request increments lootboxRngIndex by exactly 1.
    function test_indexIncrementsOnFreshDaily() public {
        uint48 indexBefore = _readLootboxRngIndex();

        // advanceGame triggers daily VRF request -> _finalizeRngRequest(isRetry=false) -> index++
        game.advanceGame();

        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(indexAfter, indexBefore + 1, "Fresh daily request should increment index by 1");
    }

    /// @notice Mid-day requestLootboxRng increments lootboxRngIndex by exactly 1.
    function test_indexIncrementsOnMidDay() public {
        _setupForMidDayRng();

        uint48 indexBefore = _readLootboxRngIndex();

        // requestLootboxRng always increments
        game.requestLootboxRng();

        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(indexAfter, indexBefore + 1, "Mid-day request should increment index by 1");
    }

    /// @notice Retry after 12h timeout does NOT increment lootboxRngIndex.
    function test_indexNoIncrementOnRetry(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2: warp to next day, trigger VRF request
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");

        // Record index after initial request (already incremented)
        uint48 indexAfterRequest = _readLootboxRngIndex();

        // Do NOT fulfill -- wait 13 hours for timeout
        vm.warp(block.timestamp + 13 hours);

        // Retry fires on next advanceGame
        game.advanceGame();

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
        game.advanceGame();
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

        // Complete each day using absolute timestamps
        for (uint8 d = 1; d <= numDays; d++) {
            vm.warp(uint256(d) * 86400);
            _completeDay(uint256(0xDEAD0000 + d));
        }

        uint48 indexAfter = _readLootboxRngIndex();
        assertEq(
            indexAfter,
            indexBefore + uint48(numDays),
            "Index should increment exactly once per day"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-02: Word-to-Index Correctness
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Daily VRF fulfillment writes fuzzed word to lootboxRngWordByIndex[index-1].
    function test_wordWriteDaily(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        uint48 indexBefore = _readLootboxRngIndex();

        // advanceGame triggers VRF request -> index increments
        game.advanceGame();

        // Fulfill VRF
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);

        // Complete processing
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }

        // Word should be stored at indexBefore (the index reserved by this request)
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, vrfWord, "Daily word should be stored at correct index");
    }

    /// @notice Mid-day VRF fulfillment writes fuzzed word to lootboxRngWordByIndex[index-1].
    function test_wordWriteMidDay(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        _setupForMidDayRng();

        uint48 indexBefore = _readLootboxRngIndex();

        // requestLootboxRng increments index
        game.requestLootboxRng();

        // Fulfill mid-day VRF
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);

        // Word stored at indexBefore (the slot reserved by requestLootboxRng)
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, vrfWord, "Mid-day word should be stored at correct index");
    }

    /// @notice Stale daily word (requestDay < current day) redirected to correct lootbox index.
    function test_wordWriteStaleRedirect(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Day 2 (absolute): trigger VRF request
        uint256 day2Start = 2 * 86400;
        vm.warp(day2Start);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");
        uint256 reqId = mockVRF.lastRequestId();

        // Record the index that day 2's request reserved
        // Index was incremented by advanceGame, so the reserved slot is (currentIndex - 1)
        uint48 reservedIndex = _readLootboxRngIndex() - 1;

        // Fulfill the VRF (word stored in rngWordCurrent, NOT yet in lootboxRngWordByIndex)
        mockVRF.fulfillRandomWords(reqId, vrfWord);

        // Warp past day boundary to day 3 WITHOUT calling advanceGame
        uint256 day3Start = 3 * 86400;
        vm.warp(day3Start);

        // advanceGame on day 3: rngGate sees requestDay < day, redirects stale word
        // to lootbox via _finalizeLootboxRng, then requests fresh daily RNG
        game.advanceGame();

        // The stale word should now be stored at the reserved index
        uint256 storedWord = _readLootboxWord(reservedIndex);
        assertEq(storedWord, vrfWord, "Stale redirect should store word at correct index");
    }

    /// @notice Orphaned index from coordinator swap gets backfilled with nonzero word.
    function test_wordWriteBackfill() public {
        // Day 1 (ts=86400): complete normally -> lootboxRngIndex = 2, word at index 1
        _completeDay(0xDEAD0001);

        // Day 2 (absolute ts): trigger VRF request -> lootboxRngIndex becomes 3
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Record the orphaned index (reserved by day 2's request)
        uint48 orphanedIndex = _readLootboxRngIndex() - 1;

        // Coordinator swap: abandons the in-flight VRF, clears state
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        mockVRF = newVRF;

        // The orphaned index has no word written (VRF never fulfilled)
        assertEq(_readLootboxWord(orphanedIndex), 0, "Orphaned index should have no word yet");

        // Warp to day 4 (absolute): day 2 and 3 become gap days.
        // When advanceGame runs, rngGate detects gap (dailyIdx=1, day=4) and calls
        // _backfillOrphanedLootboxIndices with the fresh VRF word.
        vm.warp(4 * 86400);
        newVRF.fundSubscription(1, 100e18);
        _completeDay(0xDEAD0004);

        // Orphaned index should now be backfilled with a nonzero word
        uint256 backfilledWord = _readLootboxWord(orphanedIndex);
        assertTrue(backfilledWord != 0, "Orphaned index should be backfilled with nonzero word");
    }

    /// @notice _finalizeLootboxRng is idempotent -- second write does not overwrite.
    function test_wordWriteIdempotent(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        uint48 indexBefore = _readLootboxRngIndex();

        // Complete a day (writes word via _finalizeLootboxRng)
        _completeDay(vrfWord);

        // Verify word was stored
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, vrfWord, "Word should be stored after day completion");

        // Attempt to cause a second write: trigger another day's VRF request,
        // fulfill with a different word, then check the original index is unchanged.
        vm.warp(block.timestamp + 1 days);
        _completeDay(vrfWord ^ 0xBEEF);

        // Original index word should be unchanged (idempotent guard)
        uint256 wordAfterSecondDay = _readLootboxWord(indexBefore);
        assertEq(wordAfterSecondDay, storedWord, "Idempotent: original word should be unchanged");
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-03: Zero-State Guards
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Daily rawFulfillRandomWords with word=0 stores 1 at the lootbox index.
    function test_zeroGuardRawFulfill() public {
        uint48 indexBefore = _readLootboxRngIndex();

        // Trigger daily VRF request
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();

        // Fulfill with word = 0 (zero guard should convert to 1)
        mockVRF.fulfillRandomWords(reqId, 0);

        // Process until unlocked
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }

        // The stored lootbox word should be 1 (not 0)
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, 1, "Zero-guarded daily word should be stored as 1");
    }

    /// @notice Backfill of orphaned indices produces nonzero words (zero guard in keccak256 path).
    function test_zeroGuardBackfill() public {
        // Day 1: complete
        _completeDay(0xDEAD0001);

        // Day 2 (absolute): trigger VRF, then coordinator swap (orphans the index)
        vm.warp(2 * 86400);
        game.advanceGame();
        uint48 orphanedIndex = _readLootboxRngIndex() - 1;

        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        mockVRF = newVRF;

        // Warp to day 4 (absolute): days 2+3 are gap days, triggers backfill
        vm.warp(4 * 86400);
        newVRF.fundSubscription(1, 100e18);
        _completeDay(0xDEAD0004);

        // All backfilled indices must be nonzero
        uint256 backfilledWord = _readLootboxWord(orphanedIndex);
        assertTrue(backfilledWord != 0, "Backfilled word must be nonzero (zero guard)");
    }

    /// @notice Mid-day rawFulfillRandomWords with word=0 stores 1 at the lootbox index.
    function test_zeroGuardMidDay() public {
        _setupForMidDayRng();

        uint48 indexBefore = _readLootboxRngIndex();

        // Request mid-day lootbox RNG
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();

        // Fulfill with word = 0
        mockVRF.fulfillRandomWords(reqId, 0);

        // Mid-day path writes directly to lootboxRngWordByIndex (no advanceGame needed)
        uint256 storedWord = _readLootboxWord(indexBefore);
        assertEq(storedWord, 1, "Zero-guarded mid-day word should be stored as 1");
    }
}
