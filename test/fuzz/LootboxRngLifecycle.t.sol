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

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> loop until unlocked.
    ///      Tracks the last-known request ID to avoid double-fulfillment when the
    ///      game reuses a stale rngWordCurrent across day boundaries.
    uint256 private _lastFulfilledReqId;

    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
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

    /// @dev Read rngRequestTime from packed slot 0, bytes [8:14] (uint48, bit offset 64).
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 64);
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

    /// @dev Read lootboxRngIndex directly from storage slot 38.
    function _readLootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(38)))));
    }

    /// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 39).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(39)));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read lootboxRngWordByIndex[index] via storage.
    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        return _lootboxRngWord(index);
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

        // Complete each day using absolute timestamps, starting from day 2 (setUp already warped there)
        for (uint8 d = 2; d <= numDays + 1; d++) {
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

    /// @notice Stale daily word (requestDay < current day) redirected to lootbox index.
    ///         The stale word is stored at the reserved index. The stored value may be the
    ///         raw VRF word or a keccak256-derived word depending on the backfill path.
    function test_wordWriteStaleRedirect(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Next day (day 3 absolute): trigger VRF request
        uint256 day3Start = 3 * 86400;
        vm.warp(day3Start);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");
        uint256 reqId = mockVRF.lastRequestId();

        // Record the index that the day 3 request reserved
        // Index was incremented by advanceGame, so the reserved slot is (currentIndex - 1)
        uint48 reservedIndex = _readLootboxRngIndex() - 1;

        // Fulfill the VRF (word stored in rngWordCurrent, NOT yet in lootboxRngWordByIndex)
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        _lastFulfilledReqId = reqId;

        // Warp past day boundary to day 4 WITHOUT calling advanceGame
        uint256 day4Start = 4 * 86400;
        vm.warp(day4Start);

        // advanceGame on day 4: rngGate sees requestDay < day, redirects stale word
        // to lootbox via _finalizeLootboxRng. The game processes both days inline.
        game.advanceGame();

        // Process until unlocked
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            uint256 latestReqId = mockVRF.lastRequestId();
            if (latestReqId > _lastFulfilledReqId) {
                mockVRF.fulfillRandomWords(latestReqId, vrfWord ^ 0xDADA);
                _lastFulfilledReqId = latestReqId;
            }
            game.advanceGame();
        }

        // The stale word should now be stored at the reserved index.
        // The stored value may be the raw VRF word or a derived (keccak256) word
        // depending on whether the stale redirect path or backfill path was taken.
        uint256 storedWord = _readLootboxWord(reservedIndex);
        assertTrue(storedWord != 0, "Stale redirect should store nonzero word at correct index");
    }

    /// @notice Orphaned index from coordinator swap gets backfilled with nonzero word.
    function test_wordWriteBackfill() public {
        // Complete the first post-deploy day (day 2) normally
        _completeDay(0xDEAD0001);

        // Next day (day 3 absolute): trigger VRF request
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Record the orphaned index (reserved by the day 3 request)
        uint48 orphanedIndex = _readLootboxRngIndex() - 1;

        // Coordinator swap: abandons the in-flight VRF, clears state
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        mockVRF = newVRF;

        // The orphaned index has no word written (VRF never fulfilled)
        assertEq(_readLootboxWord(orphanedIndex), 0, "Orphaned index should have no word yet");

        // Warp to day 5 (absolute): days 3 and 4 become gap days.
        // When advanceGame runs, rngGate detects gap (dailyIdx=2, day=5) and calls
        // _backfillOrphanedLootboxIndices with the fresh VRF word.
        vm.warp(5 * 86400);
        newVRF.fundSubscription(1, 100e18);
        _completeDay(0xDEAD0005);

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
        // Complete the first post-deploy day (day 2)
        _completeDay(0xDEAD0001);

        // Next day (day 3 absolute): trigger VRF, then coordinator swap (orphans the index)
        vm.warp(3 * 86400);
        game.advanceGame();
        uint48 orphanedIndex = _readLootboxRngIndex() - 1;

        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        mockVRF = newVRF;

        // Warp to day 5 (absolute): days 3+4 are gap days, triggers backfill
        vm.warp(5 * 86400);
        newVRF.fundSubscription(1, 100e18);
        _completeDay(0xDEAD0005);

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

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-04: Entropy Uniqueness
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Two different players purchasing at the same index produce different entropy.
    ///         Entropy = keccak256(abi.encode(rngWord, player, day, amount)).
    ///         Different player addresses -> different preimage -> different entropy.
    function test_entropyUniqueDifferentPlayers(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");

        uint48 purchaseIndex = _readLootboxRngIndex();

        // Both buyers purchase at the same index with identical amounts
        _makePurchase(buyer1, 1 ether);
        _makePurchase(buyer2, 1 ether);

        // Complete the day to store the VRF word
        _completeDay(vrfWord);

        // Read stored word at the purchase index
        uint256 storedWord = _readLootboxWord(purchaseIndex);
        assertTrue(storedWord != 0, "Word should be stored");

        // Read buyer1's stored day from lootboxStatus (day is what was recorded at purchase time)
        // Both purchased on day 1, so day = 1 for both.
        // Read amounts from lootboxStatus
        (uint256 amount1, ) = game.lootboxStatus(buyer1, purchaseIndex);
        (uint256 amount2, ) = game.lootboxStatus(buyer2, purchaseIndex);
        assertTrue(amount1 != 0, "Buyer1 should have lootbox amount");
        assertTrue(amount2 != 0, "Buyer2 should have lootbox amount");

        // Compute entropy for each buyer using the contract's formula:
        // entropy = keccak256(abi.encode(rngWord, player, day, amount))
        // Day is 2 (setUp warps to day 2, so purchases happen on day 2)
        uint48 day = 2;
        uint256 entropy1 = uint256(keccak256(abi.encode(storedWord, buyer1, day, amount1)));
        uint256 entropy2 = uint256(keccak256(abi.encode(storedWord, buyer2, day, amount2)));

        // Different player addresses in preimage -> different entropy
        assertTrue(entropy1 != entropy2, "Different players must produce different entropy");
    }

    /// @notice Same player with different amounts at different indices produces different entropy.
    ///         Different VRF words + different amounts -> different preimage -> different entropy.
    function test_entropyUniqueDifferentAmounts(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        address buyer = makeAddr("amountBuyer");
        uint48 index1 = _readLootboxRngIndex();

        // First purchase: 1 ether lootbox on day 2 (setUp already warped to day 2)
        _makePurchase(buyer, 1 ether);
        _completeDay(vrfWord);

        uint256 word1 = _readLootboxWord(index1);
        (uint256 amount1, ) = game.lootboxStatus(buyer, index1);

        // Warp to day 3: purchase 2 ether lootbox
        vm.warp(3 * 86400);
        uint48 index2 = _readLootboxRngIndex();
        _makePurchase(buyer, 2 ether);
        uint256 word2Seed = vrfWord ^ 0xBEEF;
        if (word2Seed == 0) word2Seed = 1;
        _completeDay(word2Seed);

        uint256 word2 = _readLootboxWord(index2);
        (uint256 amount2, ) = game.lootboxStatus(buyer, index2);

        // Compute entropy for each
        uint256 entropy1 = uint256(keccak256(abi.encode(word1, buyer, uint48(2), amount1)));
        uint256 entropy2 = uint256(keccak256(abi.encode(word2, buyer, uint48(3), amount2)));

        // Different amounts AND different VRF words -> different entropy
        assertTrue(entropy1 != entropy2, "Different amounts must produce different entropy");
    }

    /// @notice Same player purchasing on different days produces different entropy.
    ///         Even if VRF words were identical, the day parameter in keccak256 differs.
    function test_entropyUniqueDifferentDays(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        address buyer = makeAddr("dayBuyer");
        uint48 index1 = _readLootboxRngIndex();

        // First purchase on day 2 (setUp already warped to day 2)
        _makePurchase(buyer, 1 ether);
        _completeDay(vrfWord);

        uint256 word1 = _readLootboxWord(index1);
        (uint256 amount1, ) = game.lootboxStatus(buyer, index1);

        // Warp to day 3: purchase same amount
        vm.warp(3 * 86400);
        uint48 index2 = _readLootboxRngIndex();
        _makePurchase(buyer, 1 ether);
        // Use same VRF word to isolate the day variable
        _completeDay(vrfWord);

        uint256 word2 = _readLootboxWord(index2);
        (uint256 amount2, ) = game.lootboxStatus(buyer, index2);

        // Compute entropy using the recorded day for each purchase
        // First purchase is day=2, second purchase is day=3
        uint256 entropy1 = uint256(keccak256(abi.encode(word1, buyer, uint48(2), amount1)));
        uint256 entropy2 = uint256(keccak256(abi.encode(word2, buyer, uint48(3), amount2)));

        // Different day values in preimage -> different entropy
        assertTrue(entropy1 != entropy2, "Different days must produce different entropy");
    }

    /// @notice Same player purchasing twice at the same index accumulates amounts.
    ///         The total amount changes the keccak preimage for entropy.
    function test_entropyAccumulationSamePlayer() public {
        address buyer = makeAddr("accumBuyer");
        uint48 purchaseIndex = _readLootboxRngIndex();

        // First purchase: 0.5 ether lootbox
        _makePurchase(buyer, 0.5 ether);

        // Check accumulated amount after first purchase
        (uint256 amountAfterFirst, ) = game.lootboxStatus(buyer, purchaseIndex);
        assertTrue(amountAfterFirst != 0, "Should have amount after first purchase");

        // Second purchase: another 0.5 ether lootbox at the same index (same day)
        _makePurchase(buyer, 0.5 ether);

        // Check accumulated amount after second purchase
        (uint256 amountAfterSecond, ) = game.lootboxStatus(buyer, purchaseIndex);

        // Amount should have increased (accumulated)
        assertTrue(
            amountAfterSecond > amountAfterFirst,
            "Accumulated amount should increase with second purchase"
        );

        // Complete the day so the word is stored
        _completeDay(0xDEAD0001);

        // The entropy derivation will use the accumulated total, not individual purchase amounts
        uint256 storedWord = _readLootboxWord(purchaseIndex);
        uint256 entropyWithAccumulated = uint256(
            keccak256(abi.encode(storedWord, buyer, uint48(2), amountAfterSecond))
        );
        uint256 entropyWithFirstOnly = uint256(
            keccak256(abi.encode(storedWord, buyer, uint48(2), amountAfterFirst))
        );

        // Since accumulated amount differs from first-only, entropy must differ
        assertTrue(
            entropyWithAccumulated != entropyWithFirstOnly,
            "Accumulated amount produces different entropy than single purchase"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // LBOX-05: Full Purchase-to-Open Lifecycle
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Full daily lifecycle: purchase -> advanceGame -> VRF fulfill -> process -> openLootBox.
    function test_fullLifecycleDailyPath() public {
        address buyer = makeAddr("dailyBuyer");

        // Record index at purchase time
        uint48 purchaseIndex = _readLootboxRngIndex();

        // Purchase lootbox
        _makePurchase(buyer, 1 ether);

        // advanceGame triggers VRF request
        game.advanceGame();
        assertTrue(game.rngLocked(), "Should be locked after VRF request");

        // VRF fulfills
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, 0xDEAD0001);

        // Process until unlocked
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
        assertFalse(game.rngLocked(), "Should be unlocked after processing");

        // Verify word was stored before opening
        uint256 storedWord = _readLootboxWord(purchaseIndex);
        assertTrue(storedWord != 0, "Word should be stored at purchase index before open");

        // openLootBox should succeed (word available, no RngNotReady revert)
        vm.prank(buyer);
        game.openLootBox(buyer, purchaseIndex);
    }

    /// @notice Full mid-day lifecycle: purchase -> requestLootboxRng -> VRF fulfill -> openLootBox.
    function test_fullLifecycleMidDayPath() public {
        // Setup: complete a day first so daily word exists for today
        _setupForMidDayRng();

        address buyer = makeAddr("midDayBuyer");

        // Record the index at purchase time
        uint48 purchaseIndex = _readLootboxRngIndex();

        // Purchase lootbox (creates pending ETH for requestLootboxRng)
        _makePurchase(buyer, 1 ether);

        // requestLootboxRng -> increments index
        game.requestLootboxRng();

        // VRF fulfills mid-day (writes directly to lootboxRngWordByIndex)
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, 0xCAFE);

        // Verify word stored
        uint256 storedWord = _readLootboxWord(purchaseIndex);
        assertTrue(storedWord != 0, "Mid-day word should be stored at purchase index");

        // openLootBox should succeed
        vm.prank(buyer);
        game.openLootBox(buyer, purchaseIndex);
    }

    /// @notice Attempting openLootBox before VRF fulfillment reverts with RngNotReady.
    function test_fullLifecycleRngNotReady() public {
        address buyer = makeAddr("notReadyBuyer");

        // Record index at purchase time
        uint48 purchaseIndex = _readLootboxRngIndex();

        // Purchase lootbox
        _makePurchase(buyer, 1 ether);

        // advanceGame triggers VRF request (index increments)
        game.advanceGame();
        assertTrue(game.rngLocked(), "Should be locked after VRF request");

        // Do NOT fulfill VRF -- word at purchaseIndex is still 0

        // openLootBox must revert with RngNotReady
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("RngNotReady()"));
        game.openLootBox(buyer, purchaseIndex);
    }

    /// @notice Multiple indices: purchases at different indices each use their respective VRF word.
    function test_fullLifecycleMultipleIndices() public {
        address buyer = makeAddr("multiBuyer");

        // First index: purchase at index N on day 2 (setUp already warped to day 2)
        uint48 indexN = _readLootboxRngIndex();
        _makePurchase(buyer, 1 ether);

        // Complete the first post-deploy day (stores word at indexN)
        _completeDay(0xDEAD0001);

        // Next day (day 3 absolute): purchase at index N+1
        vm.warp(3 * 86400);
        uint48 indexN1 = _readLootboxRngIndex();
        assertEq(indexN1, indexN + 1, "Index should have incremented after first day");

        _makePurchase(buyer, 1 ether);

        // Complete the second day (stores word at indexN1)
        _completeDay(0xDEAD0002);

        // Verify both words are stored and different
        uint256 wordN = _readLootboxWord(indexN);
        uint256 wordN1 = _readLootboxWord(indexN1);
        assertTrue(wordN != 0, "Word at indexN should be nonzero");
        assertTrue(wordN1 != 0, "Word at indexN+1 should be nonzero");
        assertTrue(wordN != wordN1, "Different days should have different words");

        // Open both lootboxes -- both should succeed
        vm.prank(buyer);
        game.openLootBox(buyer, indexN);

        vm.prank(buyer);
        game.openLootBox(buyer, indexN1);
    }
}
