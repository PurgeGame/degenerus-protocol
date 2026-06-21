// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VrfRotationLiveness -- VTST-02 liveness-after-rotation (proves VRF-02)
/// @notice Proves the protocol stays LIVE after an emergency VRF coordinator/subscription
///         rotation. The Phase 312 fix re-issues an in-flight request on the new coordinator
///         (mid-day or daily) so the daily-drain advance gate, requestLootboxRng, and
///         retryLootboxRng all stay reachable -- no permanent revert / ~120-day freeze /
///         forced premature game-over.
///
///         Liveness is proven by a POSITIVE outcome (the drain loop reaches
///         rngLocked()==false, the day word / index word is set, a re-issue actually fires
///         on the NEW coordinator) -- never by a silent negative assertion. The OLD-bug
///         failure mode was a revert (RngNotReady at the :271/:213 drain gate); under the bug
///         these positive-outcome assertions fail naturally because the drain reverts.
///
///         Three rotation branches of updateVrfCoordinatorAndSub (AdvanceModule:1712) are
///         exercised, plus the retryLootboxRng failsafe (Task 2):
///           1. Mid-day in flight (LR_MID_DAY==1, :1726): re-issue lands in the reserved
///              slot N via the mid-day fulfillment branch (:1803-1804).
///           2. Daily in flight, rngWordCurrent==0 (:1733): re-issue fills rngWordCurrent
///              via the daily branch (:1800), the new-day drain gate (:269/:271) unblocks.
///           3. Daily already delivered (rngWordCurrent!=0, :1738) / nothing in flight
///              (:1741): NO re-issue -- delivered word preserved, advance proceeds.
///
/// @dev    Storage slots are authoritative per `forge inspect DegenerusGame storage-layout`:
///         slot 34 = lootboxRngPacked (LR_INDEX in low bits, LR_MID_DAY at bit 224 mask 0xFF),
///         slot 35 = lootboxRngWordByIndex mapping (lootboxRngWordByIndex[i] at
///         keccak256(abi.encode(uint256(i), uint256(35)))),
///         slot 3 = rngWordCurrent, slot 0 packed = rngRequestTime at bit offset 64.
///         ZERO contracts/ mutation -- audit-only (D-43N-AUDIT-ONLY-01).
contract VrfRotationLiveness is DeployProtocol {
    /// @dev Storage slot constants (authoritative storage-layout, not the drifted analog).
    uint256 private constant SLOT_PACKED_0 = 0;
    uint256 private constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 private constant SLOT_LOOTBOX_PACKED = 34;   // post Stage B Game pack: was 35
    uint256 private constant SLOT_LOOTBOX_WORD_MAP = 35;  // post Stage B Game pack: was 36
    /// @dev LR_MID_DAY occupies byte 28 of lootboxRngPacked (bit offset 224, mask 0xFF).
    uint256 private constant LR_MID_DAY_BIT = 224;

    /// @dev MIDDAY_RNG_RETRY_TIMEOUT (AdvanceModule:141) and MIN_LINK_FOR_LOOTBOX_RNG (:140).
    uint48 private constant MIDDAY_RNG_RETRY_TIMEOUT = 6 hours;
    uint96 private constant MIN_LINK_FOR_LOOTBOX_RNG = 40 ether;

    /// @dev Last VRF request id fulfilled on the active coordinator; avoids double-fulfil
    ///      when the game reuses a stale rngWordCurrent across day boundaries.
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Storage-read helpers (slots authoritative per forge inspect)
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Read LR_INDEX (the low bits of lootboxRngPacked at slot 34).
    function _readLootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED))));
    }

    /// @dev Read the LR_MID_DAY flag (byte 28 of lootboxRngPacked).
    function _readMidDayFlag() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED)));
        return (packed >> LR_MID_DAY_BIT) & 0xFF;
    }

    /// @dev Read lootboxRngWordByIndex[index] from the slot-35 mapping.
    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_WORD_MAP));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read rngWordCurrent directly from slot 3.
    function _readRngWordCurrent() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_RNG_WORD_CURRENT))));
    }

    /// @dev Read rngRequestTime from packed slot 0, bits [48:96] (uint48, bit offset 48).
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 48);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Sequence helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev The currently-active VRF coordinator. Starts as the deploy-time mockVRF and is
    ///      re-pointed by _rotateTo() so the drain/complete helpers fulfil on the live
    ///      coordinator after a rotation (the analogs that fulfil on the stale mockVRF are
    ///      the pre-fix regressions plan 313-05 migrates).
    MockVRFCoordinator private _activeVRF;

    /// @dev Resolve the active coordinator (defaults to deploy-time mockVRF before any rotation).
    function _coord() internal view returns (MockVRFCoordinator) {
        return address(_activeVRF) == address(0) ? mockVRF : _activeVRF;
    }

    /// @dev NotTimeYet() selector -- the same-day "no work available yet" signal (AdvanceModule:238).
    ///      RngNotReady() (the OLD-bug permanent-revert failure mode) is deliberately NOT caught:
    ///      it must propagate and fail the test, so liveness is never silently asserted.
    bytes4 private constant NOT_TIME_YET = bytes4(keccak256("NotTimeYet()"));

    /// @dev Advance one step, tolerating ONLY NotTimeYet() (keeper has done all work available
    ///      for this wall-clock instant). Any other revert -- including RngNotReady() -- is
    ///      re-thrown so the defect mode fails the test naturally.
    /// @return progressed False if NotTimeYet() halted progress for this wall-clock day.
    function _advanceTolerant() internal returns (bool progressed) {
        try game.advanceGame() {
            return true;
        } catch (bytes memory err) {
            if (err.length >= 4 && bytes4(err) == NOT_TIME_YET) {
                return false;
            }
            // Re-throw any other revert (RngNotReady, etc.) verbatim.
            assembly {
                revert(add(err, 0x20), mload(err))
            }
        }
    }

    /// @dev Complete a full day on the ACTIVE coordinator: advanceGame -> fulfil any pending
    ///      request -> drain until unlocked, fulfilling any request the drain fires. Stops on
    ///      NotTimeYet() -- the keeper has done all the work available for this wall-clock day.
    function _completeDay(uint256 vrfWord) internal {
        MockVRFCoordinator c = _coord();
        if (!_advanceTolerant()) return;
        uint256 reqId = c.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            c.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 600; i++) {
            if (!game.rngLocked()) break;
            if (!_advanceTolerant()) break;
            uint256 r = c.lastRequestId();
            if (r != _lastFulfilledReqId && r > 0) {
                c.fulfillRandomWords(r, vrfWord);
                _lastFulfilledReqId = r;
            }
        }
    }

    /// @dev Drive the game into a mid-day RNG state where requestLootboxRng() succeeds AND
    ///      its buffer swap sets LR_MID_DAY=1: complete two days so today's daily RNG is
    ///      recorded, make a lootbox purchase (pending ETH + a ticket-queue entry), fund the
    ///      VRF subscription above MIN_LINK_FOR_LOOTBOX_RNG.
    function _setupForMidDayRng() internal {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);

        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth, false);

        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Deploy a freshly-funded 2nd MockVRFCoordinator and ADMIN-prank
    ///      updateVrfCoordinatorAndSub to repoint the game at it. Resets _lastFulfilledReqId
    ///      since the new mock has its own request counter. Funds the new subscription above
    ///      MIN_LINK_FOR_LOOTBOX_RNG so retryLootboxRng's LINK precheck (:1139) passes.
    function _rotateTo() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        newVRF.fundSubscription(newSubId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
        _activeVRF = newVRF;
        _lastFulfilledReqId = 0;
    }

    /// @dev Drain the daily flow on the ACTIVE coordinator while rngLocked(): advanceGame and
    ///      fulfil any request the drain fires (e.g. a follow-on daily request for the next
    ///      level). Used after a re-issued daily word has been delivered on the new coordinator.
    function _drainUntilUnlocked(uint256 vrfWord) internal {
        MockVRFCoordinator c = _coord();
        for (uint256 i = 0; i < 600; i++) {
            if (!game.rngLocked()) break;
            if (!_advanceTolerant()) break;
            uint256 r = c.lastRequestId();
            if (r != _lastFulfilledReqId && r > 0) {
                c.fulfillRandomWords(r, vrfWord);
                _lastFulfilledReqId = r;
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Task 1: rotation-branch liveness -- advance/drain stays reachable
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Mid-day branch (LR_MID_DAY==1): after a mid-flight rotation + fulfilment on the
    ///         NEW coordinator, the re-issued word fills lootboxRngWordByIndex[reservedIndex]
    ///         (the :269 drain-gate input) and the daily flow drains to rngLocked()==false --
    ///         no RngNotReady() permanent revert.
    function test_midDayRotation_liveness(uint256 vrfWord) public {
        // The contract converts a delivered 0 word to 1 (AdvanceModule:1796), so assume nonzero
        // for the exact mid-day-word equality. Also exclude 1: rngGate uses rngWord==1 as the
        // "request new RNG" sentinel (AdvanceModule:298), so a daily word delivered as 1 in the
        // subsequent _completeDay drain would livelock the day. Real 256-bit VRF words collide
        // with {0,1} only with cryptographically negligible probability.
        vm.assume(vrfWord != 0 && vrfWord != 1);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the reserved slot N = LR_INDEX-1.
        game.requestLootboxRng();
        uint48 reservedIndex = _readLootboxRngIndex() - 1;

        // The buffer swap set LR_MID_DAY=1, so the rotation's mid-day re-issue branch fires.
        assertEq(_readMidDayFlag(), 1, "requestLootboxRng must set LR_MID_DAY=1");
        // Reserved slot is orphaned-pending (empty) -- the liveness assertion is not pre-satisfied.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot must be empty before fulfilment");

        // Real emergency rotation while in flight.
        MockVRFCoordinator newVRF = _rotateTo();

        // POSITIVE: the rotation re-issued the request on the NEW coordinator (re-issue, not zero).
        assertTrue(newVRF.lastRequestId() != 0, "rotation must re-issue on the new coordinator");
        // LR_INDEX preserved across the rotation: the same slot N is still reserved.
        assertEq(_readLootboxRngIndex() - 1, reservedIndex, "rotation must preserve the reserved index");
        // Still empty before the new coordinator fulfils -- proves no tautology.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot still empty pre-fulfilment");

        // Fulfil the re-issued request on the NEW coordinator (mid-day branch writes the slot).
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);

        // POSITIVE: the real VRF word landed in the SAME preserved slot N -- the :269 drain
        // gate input is now non-zero, so the gate no longer reverts RngNotReady().
        assertEq(
            _readLootboxWord(reservedIndex),
            vrfWord,
            "re-issued word must land in the preserved reserved index after rotation"
        );

        // POSITIVE liveness: the daily flow advances/drains without a permanent revert.
        // Mid-day fulfilment clears LR_MID_DAY consumption inline on the next advance; warp
        // to the next day and complete it to prove the protocol is not bricked.
        vm.warp(block.timestamp + 1 days);
        _completeDay(vrfWord);
        assertFalse(game.rngLocked(), "drain reaches rngLocked()==false after mid-day rotation");
    }

    /// @notice Daily branch (rngLockedFlag==true, rngWordCurrent==0): after a daily-in-flight
    ///         rotation + fulfilment on the NEW coordinator, the re-issued word fills
    ///         rngWordCurrent so the :271 new-day drain gate unblocks; the day completes
    ///         (rngWordForDay(currentDay) != 0) -- no RngNotReady() revert.
    function test_dailyRotation_liveness(uint256 vrfWord) public {
        // Exclude {0,1}: 0 is zero-guarded to 1, and rngWord==1 is the rngGate "request new RNG"
        // sentinel (AdvanceModule:298) -- a daily word delivered as 1 livelocks the drain.
        vm.assume(vrfWord != 0 && vrfWord != 1);

        // Complete the first post-deploy day so the game is in steady state.
        _completeDay(0xDEAD0001);

        // Warp to a new day and fire the daily request (locked, word not yet delivered).
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "daily VRF request must be in flight (locked)");
        assertEq(_readRngWordCurrent(), 0, "daily word not yet delivered before rotation");

        uint32 day = game.currentDayView();

        // Rotate while the daily request is in flight (rngWordCurrent==0 re-issue branch).
        MockVRFCoordinator newVRF = _rotateTo();

        // POSITIVE: a re-issued daily request exists on the NEW coordinator.
        assertTrue(newVRF.lastRequestId() != 0, "daily re-issue must fire on the new coordinator");
        // Still locked and undelivered until the new coordinator fulfils.
        assertTrue(game.rngLocked(), "still locked after daily rotation, pre-fulfilment");
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent still empty pre-fulfilment");

        // Fulfil on the NEW coordinator -> rngLockedFlag==true branch stores rngWordCurrent.
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);
        _lastFulfilledReqId = newVRF.lastRequestId();
        assertTrue(_readRngWordCurrent() != 0, "re-issued daily word delivered into rngWordCurrent");

        // POSITIVE liveness: drain the day to completion -- the :271 gate no longer reverts.
        _drainUntilUnlocked(vrfWord);
        assertFalse(game.rngLocked(), "drain reaches rngLocked()==false after daily rotation");
        assertTrue(game.rngWordForDay(uint24(day)) != 0, "day completes: rngWordForDay(currentDay) != 0");
    }

    /// @notice Daily-already-delivered short-circuit (rngWordCurrent!=0 at :1738): if the daily
    ///         word was delivered BEFORE the rotation, the rotation does NOT re-issue (new
    ///         coordinator lastRequestId()==0) and the delivered word is preserved; advance
    ///         proceeds and the day completes normally.
    function test_dailyAlreadyDelivered_shortCircuit(uint256 vrfWord) public {
        // Exclude {0,1}: 0 is zero-guarded to 1, and rngWord==1 is the rngGate sentinel
        // (AdvanceModule:298) -- a daily word delivered as 1 livelocks the drain.
        vm.assume(vrfWord != 0 && vrfWord != 1);

        _completeDay(0xDEAD0001);

        // Warp to a new day and fire the daily request.
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "daily VRF request must be in flight");

        uint32 day = game.currentDayView();

        // Deliver the daily word on the OLD coordinator BEFORE rotating -> rngWordCurrent != 0.
        uint256 oldReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(oldReqId, vrfWord);
        uint256 deliveredWord = _readRngWordCurrent();
        assertTrue(deliveredWord != 0, "daily word delivered on old coordinator pre-rotation");

        // Rotate: the rngWordCurrent!=0 short-circuit must NOT re-issue.
        MockVRFCoordinator newVRF = _rotateTo();

        // POSITIVE short-circuit assertions: no re-issue, delivered word preserved.
        assertEq(newVRF.lastRequestId(), 0, "no re-issue when rngWordCurrent!=0 (short-circuit)");
        assertEq(_readRngWordCurrent(), deliveredWord, "delivered daily word preserved across rotation");

        // POSITIVE liveness: the advance/drain still completes the day.
        _drainUntilUnlocked(vrfWord);
        assertFalse(game.rngLocked(), "drain completes after short-circuit rotation");
        assertTrue(game.rngWordForDay(uint24(day)) != 0, "day completes with the pre-rotation delivered word");
    }

    /// @notice Nothing-in-flight no-op (rngLocked()==false, LR_MID_DAY==0 at :1741): a rotation
    ///         from an unlocked steady state is a pure config repoint -- no re-issue on the new
    ///         coordinator -- and the next day advances without revert.
    function test_nothingInFlight_noOp() public {
        // Complete a day so the game is in an unlocked steady state with nothing in flight.
        _completeDay(0xDEAD0001);
        assertFalse(game.rngLocked(), "steady state must be unlocked");
        assertEq(_readMidDayFlag(), 0, "no mid-day request in flight");

        // Rotate from the idle state: pure config repoint, no re-issue.
        MockVRFCoordinator newVRF = _rotateTo();

        // POSITIVE no-op assertion: no request fired on the new coordinator.
        assertEq(newVRF.lastRequestId(), 0, "nothing-in-flight rotation must not re-issue");

        // POSITIVE liveness: the next day advances normally on the new coordinator.
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);
        assertFalse(game.rngLocked(), "advance proceeds normally after no-op rotation");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Task 2: retryLootboxRng failsafe + requestLootboxRng reachability
    // ══════════════════════════════════════════════════════════════════════

    /// @notice retryLootboxRng failsafe (RESEARCH §5 Open Risk 1): if the NEW coordinator also
    ///         stalls the re-issued mid-day request, retryLootboxRng reverts before
    ///         MIDDAY_RNG_RETRY_TIMEOUT and, at/after the timeout, re-fires a fresh request on
    ///         the new coordinator WITHOUT advancing lootboxRngIndex (no double-advance).
    ///         Fulfilling the retry request lands a real word in the reserved index; the daily
    ///         flow then proceeds -- recoverable, never a permanent freeze.
    function test_retryRescuesStalledReissueAfterRotation(uint256 vrfWord) public {
        // Exclude {0,1}: 0 is zero-guarded to 1; rngWord==1 is the rngGate sentinel
        // (AdvanceModule:298) -- the final _completeDay(vrfWord) drain would livelock if 1.
        vm.assume(vrfWord != 0 && vrfWord != 1);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the reserved slot N = LR_INDEX-1.
        game.requestLootboxRng();
        uint48 reservedIndex = _readLootboxRngIndex() - 1;
        assertEq(_readMidDayFlag(), 1, "requestLootboxRng must set LR_MID_DAY=1");

        // Rotate while in flight -- the mid-day re-issue fires on the new coordinator but the
        // NEW coordinator does NOT fulfil (simulating the new coordinator also stalling).
        MockVRFCoordinator newVRF = _rotateTo();
        uint256 reissueReqId = newVRF.lastRequestId();
        assertTrue(reissueReqId != 0, "rotation re-issued the request on the new coordinator");

        // The re-issue refreshed rngRequestTime; capture it for the timeout boundary.
        uint48 reissueTime = _readRngRequestTime();
        assertTrue(reissueTime != 0, "rngRequestTime set by the re-issue");
        uint48 indexBeforeRetry = _readLootboxRngIndex();

        // Retry must REVERT before MIDDAY_RNG_RETRY_TIMEOUT (the new coordinator just re-issued).
        vm.expectRevert();
        game.retryLootboxRng();

        // Still reverts one second before the timeout boundary.
        vm.warp(uint256(reissueTime) + MIDDAY_RNG_RETRY_TIMEOUT - 1);
        vm.expectRevert();
        game.retryLootboxRng();

        // At/after the timeout, retry succeeds and re-fires on the new coordinator.
        vm.warp(uint256(reissueTime) + MIDDAY_RNG_RETRY_TIMEOUT);
        game.retryLootboxRng();

        uint256 retryReqId = newVRF.lastRequestId();
        assertTrue(retryReqId != reissueReqId, "retry produced a new VRF request id");
        // POSITIVE: retry preserves lootboxRngIndex (no double-advance).
        assertEq(_readLootboxRngIndex(), indexBeforeRetry, "retry must NOT advance lootboxRngIndex");
        // LR_MID_DAY remains set (buffer swap still committed) and the slot is still empty.
        assertEq(_readMidDayFlag(), 1, "LR_MID_DAY preserved after retry");
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot empty until retry fulfils");

        // The stalled re-issue (original) request is auto-rejected on late arrival
        // (requestId mismatch -> rawFulfillRandomWords early-returns).
        newVRF.fulfillRandomWords(reissueReqId, 0x1111);
        assertEq(_readLootboxWord(reservedIndex), 0, "late stalled re-issue word rejected on id mismatch");

        // Fulfilling the retry request lands a real word in the reserved index.
        newVRF.fulfillRandomWords(retryReqId, vrfWord);
        assertEq(
            _readLootboxWord(reservedIndex),
            vrfWord,
            "retry word fills the reserved mid-day index"
        );

        // POSITIVE liveness: the daily flow proceeds to rngLocked()==false.
        vm.warp(block.timestamp + 1 days);
        _completeDay(vrfWord);
        assertFalse(game.rngLocked(), "drain reaches rngLocked()==false after retry rescue");
    }

    /// @notice requestLootboxRng stays reachable after a completed rotation: after a
    ///         daily-branch rotation (re-issue + fulfil + drain to unlocked), a fresh mid-day
    ///         requestLootboxRng on the new coordinator succeeds -- advances the index and
    ///         fires a request -- proving the request path is reachable post-rotation.
    function test_requestLootboxRngReachableAfterRotation(uint256 vrfWord) public {
        // Exclude {0,1}: 0 is zero-guarded to 1; rngWord==1 is the rngGate sentinel
        // (AdvanceModule:298). Also exclude the value whose ^0xBEEF next-day word would be 1.
        vm.assume(vrfWord != 0 && vrfWord != 1);
        vm.assume((vrfWord ^ 0xBEEF) != 1);

        // --- Complete a daily-branch rotation so the game is past the rotation, unlocked. ---
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "daily VRF request in flight");

        MockVRFCoordinator newVRF = _rotateTo();
        assertTrue(newVRF.lastRequestId() != 0, "daily re-issue fired on the new coordinator");
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);
        _lastFulfilledReqId = newVRF.lastRequestId();
        _drainUntilUnlocked(vrfWord);
        assertFalse(game.rngLocked(), "rotation completed, game unlocked");

        // --- Set up a fresh mid-day condition on the new coordinator. ---
        // Advance one more full day so today's daily RNG is recorded (requestLootboxRng's
        // rngWordByDay[currentDay]!=0 gate at :1054), then create pending lootbox ETH + a
        // ticket-queue entry and fund the new subscription above MIN_LINK_FOR_LOOTBOX_RNG.
        vm.warp(block.timestamp + 1 days);
        uint256 nextDayWord = vrfWord ^ 0xBEEF;
        // Map both forbidden words to a safe value: 0 (XOR cancellation when vrfWord==0xBEEF)
        // and 1 (the rngGate "request new RNG" sentinel at AdvanceModule:298) would stall the
        // _completeDay drain and leave the game rngLocked().
        if (nextDayWord <= 1) nextDayWord = 2;
        _completeDay(nextDayWord);

        address buyer = makeAddr("postRotationBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth, false);
        // Fresh coordinators assign subId 1 (first createSubscription on a new mock).
        newVRF.fundSubscription(1, 100e18);

        uint48 indexBefore = _readLootboxRngIndex();
        uint256 reqIdBefore = newVRF.lastRequestId();

        // POSITIVE: requestLootboxRng succeeds on the new coordinator post-rotation.
        game.requestLootboxRng();

        assertEq(_readLootboxRngIndex(), indexBefore + 1, "requestLootboxRng advances the index post-rotation");
        assertTrue(newVRF.lastRequestId() > reqIdBefore, "requestLootboxRng fired a request on the new coordinator");
    }
}
