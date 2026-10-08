// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title VrfRotationLiveness -- VTST-02 liveness-after-rotation (proves VRF-02)
/// @notice Proves the protocol stays LIVE after an emergency VRF coordinator/subscription
///         rotation. The Phase 312 fix re-issues an in-flight request on the new coordinator
///         (mid-day or daily) so the daily-drain advance gate, the mid-day request, and the
///         daily-takeover failsafe all stay reachable -- no permanent revert / ~120-day freeze /
///         forced premature game-over.
///
///         Liveness is proven by a POSITIVE outcome (the drain loop reaches
///         rngLocked()==false, the day word / index word is set, a re-issue actually fires
///         on the NEW coordinator) -- never by a silent negative assertion. The OLD-bug
///         failure mode was a revert (RngNotReady at the :271/:213 drain gate); under the bug
///         these positive-outcome assertions fail naturally because the drain reverts.
///
///         Three rotation branches of updateVrfCoordinatorAndSub (GameOverModule) are
///         exercised, plus the daily-takeover failsafe (a stalled mid-day re-issue folded into
///         the daily word after MIDDAY_RNG_STALL_TIMEOUT):
///           1. Mid-day in flight (LR_MID_DAY==1, :1726): re-issue lands in the reserved
///              slot N via the mid-day fulfillment branch (:1803-1804).
///           2. Daily in flight, rngWordCurrent==0 (:1733): re-issue fills rngWordCurrent
///              via the daily branch (:1800), the new-day drain gate (:269/:271) unblocks.
///           3. Daily already delivered (rngWordCurrent!=0, :1738) / nothing in flight
///              (:1741): NO re-issue -- delivered word preserved, advance proceeds.
///
/// @dev    Storage slots are authoritative per `forge inspect DegenerusGame storage-layout`:
///         slot 34 = lootboxRngPacked (LR_INDEX in low bits, LR_MID_DAY at bit 224 mask 0xFF),
///         slot 35 = lootboxRngWordByIndex mapping (_lootboxWord(i) at
///         keccak256(abi.encode(uint256(i), uint256(34)))),
///         slot 3 = rngWordCurrent, slot 0 packed = rngRequestTime at bit offset 64.
///         ZERO contracts/ mutation -- audit-only (D-43N-AUDIT-ONLY-01).
contract VrfRotationLiveness is DeployProtocol {
    /// @dev Storage slot constants (authoritative storage-layout, not the drifted analog).
    uint256 private constant SLOT_PACKED_0 = 0;
    uint256 private constant SLOT_RNG_WORD_CURRENT = GameSlots.RNG_WORD_CURRENT;
    uint256 private constant SLOT_LOOTBOX_PACKED = GameSlots.LOOTBOX_RNG_PACKED;   // post Stage B Game pack: was 35
    uint256 private constant SLOT_LOOTBOX_WORD_MAP = GameSlots.RNG_DAY_TAGS;  // post Stage B Game pack: was 36
    /// @dev LR_MID_DAY occupies byte 28 of lootboxRngPacked (bit offset 224, mask 0xFF).
    uint256 private constant LR_MID_DAY_BIT = 224;

    /// @dev MIDDAY_RNG_STALL_TIMEOUT (AdvanceModule) and MIN_LINK_FOR_LOOTBOX_RNG.
    uint48 private constant MIDDAY_RNG_STALL_TIMEOUT = 4 hours;
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
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Read the LR_MID_DAY flag (byte 28 of lootboxRngPacked).
    function _readMidDayFlag() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED)));
        return (packed >> LR_MID_DAY_BIT) & 0xFF;
    }

    /// @dev Read _lootboxWord(index) from the slot-35 mapping.
    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_WORD_MAP));
        return uint256(bytes32(RecyclingState.word(address(game), uint48(index))));
    }

    /// @dev Read rngWordCurrent directly from slot 3.
    function _readRngWordCurrent() internal view returns (uint256) {
        return RecyclingState.currentWord(address(game));
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

    /// @dev NoWork() selector -- the engine's "no work available yet" signal (MinerModule; the
    ///      old NotTimeYet() advance error no longer exists after 60d31f775).
    ///      RngNotReady() is deliberately NOT caught: the drive loops below answer every request
    ///      before cranking, so a RngNotReady() there is a real stuck state and must fail the test.
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));

    /// @dev Advance one step, tolerating ONLY NoWork() (keeper has done all work available
    ///      for this wall-clock instant). Any other revert -- including RngNotReady() -- is
    ///      re-thrown so the defect mode fails the test naturally.
    /// @return progressed False if NoWork() halted progress for this wall-clock day.
    function _advanceTolerant() internal returns (bool progressed) {
        try game.mineFlip(0) {
            return true;
        } catch (bytes memory err) {
            if (err.length >= 4 && bytes4(err) == NO_WORK) {
                return false;
            }
            // Re-throw any other revert (RngNotReady, etc.) verbatim.
            assembly {
                revert(add(err, 0x20), mload(err))
            }
        }
    }

    /// @dev Answer the active coordinator's latest request if it is still pending.
    function _answer(uint256 vrfWord) internal {
        MockVRFCoordinator c = _coord();
        uint256 r = c.lastRequestId();
        if (r == 0) return;
        (,, bool done) = c.pendingRequests(r);
        if (!done) {
            c.fulfillRandomWords(r, vrfWord);
            _lastFulfilledReqId = r;
        }
    }

    /// @dev Complete a full day on the ACTIVE coordinator: answer every request the engine
    ///      makes (the daily one, and any mid-day request the state engine issues for a closed
    ///      Craps window or pending boxes) and crank until today is sealed, unlocked and the
    ///      engine reports NoWork() -- the keeper has done all the work available for this
    ///      wall-clock day.
    function _completeDay(uint256 vrfWord) internal {
        uint24 today = game.currentDayView();
        for (uint256 i = 0; i < 600; i++) {
            _answer(vrfWord);
            if (!_advanceTolerant()) break;
        }
        assertFalse(game.rngLocked(), "the day completes and unlocks");
        assertTrue(game.rngWordForDay(today) != 0, "today is sealed on its own word");
    }

    /// @dev Drive the game into a mid-day RNG state where the mid-day request (mineFlip's
    ///      RequestMidday stage) succeeds AND its buffer swap sets LR_MID_DAY=1: complete two days so today's daily RNG is
    ///      recorded, make a lootbox purchase (pending ETH + a ticket-queue entry), fund the
    ///      VRF subscription above MIN_LINK_FOR_LOOTBOX_RNG.
    function _setupForMidDayRng() internal {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);

        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev The mid-day request through mineFlip, its only door, as the engine's next action,
    ///      on whichever coordinator is wired.
    function _mineMiddayRequest(MockVRFCoordinator vrf) internal {
        uint256 prior = vrf.lastRequestId();
        game.mineFlip(0);
        assertGt(vrf.lastRequestId(), prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
    }

    /// @dev Deploy a freshly-funded 2nd MockVRFCoordinator and ADMIN-prank
    ///      updateVrfCoordinatorAndSub to repoint the game at it. Resets _lastFulfilledReqId
    ///      since the new mock has its own request counter. Funds the new subscription above
    ///      MIN_LINK_FOR_LOOTBOX_RNG so a re-issued mid-day request's LINK precheck passes.
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

    /// @dev Drain the daily flow on the ACTIVE coordinator while rngLocked(): mineFlip and
    ///      fulfil any request the drain fires (e.g. a follow-on daily request for the next
    ///      level). Used after a re-issued daily word has been delivered on the new coordinator.
    function _drainUntilUnlocked(uint256 vrfWord) internal {
        for (uint256 i = 0; i < 600; i++) {
            if (!game.rngLocked()) break;
            _answer(vrfWord);
            if (!_advanceTolerant()) break;
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Task 1: rotation-branch liveness -- advance/drain stays reachable
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Mid-day branch (LR_MID_DAY==1): after a mid-flight rotation + fulfilment on the
    ///         NEW coordinator, the re-issued word fills _lootboxWord(reservedIndex)
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
        _mineMiddayRequest(mockVRF);
        uint48 reservedIndex = (_readLootboxRngIndex() ^ 1);

        // The buffer swap set LR_MID_DAY=1, so the rotation's mid-day re-issue branch fires.
        assertEq(_readMidDayFlag(), 1, "the mid-day request must set LR_MID_DAY=1");
        // Reserved slot is orphaned-pending (empty) -- the liveness assertion is not pre-satisfied.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot must be empty before fulfilment");

        // Real emergency rotation while in flight.
        MockVRFCoordinator newVRF = _rotateTo();

        // POSITIVE: the rotation re-issued the request on the NEW coordinator (re-issue, not zero).
        assertTrue(newVRF.lastRequestId() != 0, "rotation must re-issue on the new coordinator");
        // LR_INDEX preserved across the rotation: the same slot N is still reserved.
        assertEq((_readLootboxRngIndex() ^ 1), reservedIndex, "rotation must preserve the reserved index");
        // Still empty before the new coordinator fulfils -- proves no tautology.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot still empty pre-fulfilment");

        // Fulfil the re-issued request on the NEW coordinator (mid-day branch writes the slot).
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);
        // Record this manual fulfilment so the `_completeDay` drain below does not re-fulfil the
        // same request id. The daily drain now breaks after the ticket batch and requests its RNG
        // on the NEXT advance (the gas-compose split), so `_completeDay`'s first advance leaves
        // `lastRequestId()` at this already-fulfilled mid-day id until the fresh daily request fires.
        _lastFulfilledReqId = newVRF.lastRequestId();

        // POSITIVE: the real VRF word landed in the SAME preserved slot N -- the callback
        // stores it and the next keeper call publishes it on that buffer first (60d31f775),
        // before the drained cohort lets the engine move on.
        uint256 reissued = newVRF.lastRequestId();
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 landed;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (uint48 index, uint256 word, uint256 requestId) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                if (index == reservedIndex && requestId == reissued) landed = word;
            }
        }
        assertEq(
            landed,
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
        game.mineFlip(0);
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
        game.mineFlip(0);
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
    // Task 2: daily-takeover failsafe + mid-day request reachability
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Stalled re-issue failsafe after rotation: if the NEW coordinator also stalls the
    ///         re-issued mid-day request, the next day's daily advance waits on it (the old
    ///         "promote to the daily request" takeover was removed, 60d31f775/6d0e64b09; a
    ///         mid-day request that bleeds past midnight blocks the daily request until it
    ///         lands). The Admin retry re-sends it on the new coordinator WITHOUT advancing
    ///         lootboxRngIndex (no double-advance), the late stalled re-issue is rejected, the
    ///         retried word lands in the reserved index, and the day's daily flow then proceeds
    ///         -- recoverable, never a freeze.
    function test_retryRescuesStalledReissueAfterRotation(uint256 vrfWord) public {
        // Final words 0 and 1 leave a request waiting for its retry (RngModule); exclude them.
        vm.assume(vrfWord > 1);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the reserved slot N = LR_INDEX-1.
        _mineMiddayRequest(mockVRF);
        uint48 reservedIndex = (_readLootboxRngIndex() ^ 1);
        uint48 indexAfterRequest = _readLootboxRngIndex();
        assertEq(_readMidDayFlag(), 1, "the mid-day request must set LR_MID_DAY=1");

        // Rotate while in flight -- the mid-day re-issue fires on the new coordinator but the
        // NEW coordinator does NOT fulfil (simulating the new coordinator also stalling).
        MockVRFCoordinator newVRF = _rotateTo();
        uint256 reissueReqId = newVRF.lastRequestId();
        assertTrue(reissueReqId != 0, "rotation re-issued the request on the new coordinator");
        assertFalse(game.rngLocked(), "re-issued mid-day request leaves the daily lock clear");

        // The re-issue stalls across the next-day boundary: the daily advance waits on it.
        vm.warp(block.timestamp + 1 days + MIDDAY_RNG_STALL_TIMEOUT + 1);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip(0);
        assertEq(newVRF.lastRequestId(), reissueReqId, "no daily request while the mid-day word is outstanding");
        assertFalse(game.rngLocked(), "the daily lock is not taken over the stalled re-issue");

        // The vault owner's single Admin retry (20h after the original stamp) re-sends it.
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng();
        uint256 retryReqId = newVRF.lastRequestId();
        assertTrue(retryReqId != reissueReqId, "the retry issued a replacement request on the new coordinator");
        assertFalse(game.rngLocked(), "the retry keeps the mid-day mode");
        // POSITIVE: the retry preserves lootboxRngIndex (no double-advance).
        assertEq(_readLootboxRngIndex(), indexAfterRequest, "retry must NOT advance lootboxRngIndex");
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot empty until the retried word lands");

        // The stalled re-issue is auto-rejected on late arrival
        // (requestId mismatch -> rawFulfillRandomWords early-returns).
        newVRF.fulfillRandomWords(reissueReqId, 0x1111);
        assertEq(_readRngWordCurrent(), 0, "late stalled re-issue word rejected on id mismatch");

        // POSITIVE liveness: the retried word lands in the reserved bucket, then the day's
        // daily flow drains to rngLocked()==false.
        newVRF.fulfillRandomWords(retryReqId, vrfWord);
        _lastFulfilledReqId = retryReqId;
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool landed;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (uint48 index, uint256 word, uint256 requestId) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                if (index == reservedIndex && word == vrfWord && requestId == retryReqId) landed = true;
            }
        }
        assertTrue(landed, "retried word finalized the reserved mid-day bucket");
        _completeDay(vrfWord);
        assertFalse(game.rngLocked(), "drain reaches rngLocked()==false after the retry");
    }

    /// @notice The mid-day request stays reachable after a completed rotation: after a
    ///         daily-branch rotation (re-issue + fulfil + drain to unlocked), a fresh mid-day
    ///         request through mineFlip on the new coordinator succeeds -- advances the index and
    ///         fires a request -- proving the request path is reachable post-rotation.
    function test_middayRequestReachableAfterRotation(uint256 vrfWord) public {
        // Exclude {0,1}: 0 is zero-guarded to 1; rngWord==1 is the rngGate sentinel
        // (AdvanceModule:298). Also exclude the value whose ^0xBEEF next-day word would be 1.
        vm.assume(vrfWord != 0 && vrfWord != 1);
        vm.assume((vrfWord ^ 0xBEEF) != 1);

        // --- Complete a daily-branch rotation so the game is past the rotation, unlocked. ---
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
        assertTrue(game.rngLocked(), "daily VRF request in flight");

        MockVRFCoordinator newVRF = _rotateTo();
        assertTrue(newVRF.lastRequestId() != 0, "daily re-issue fired on the new coordinator");
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);
        _lastFulfilledReqId = newVRF.lastRequestId();
        _drainUntilUnlocked(vrfWord);
        assertFalse(game.rngLocked(), "rotation completed, game unlocked");

        // --- Set up a fresh mid-day condition on the new coordinator. ---
        // Advance one more full day so today's daily RNG is recorded (the mid-day request's
        // _recordedDailyWord(currentDay)!=0 gate), then create pending lootbox ETH + a
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
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        // Fresh coordinators assign subId 1 (first createSubscription on a new mock).
        newVRF.fundSubscription(1, 100e18);

        uint48 indexBefore = _readLootboxRngIndex();
        uint256 reqIdBefore = newVRF.lastRequestId();

        // POSITIVE: the mid-day request succeeds on the new coordinator post-rotation.
        _mineMiddayRequest(newVRF);

        assertEq(_readLootboxRngIndex(), (indexBefore ^ 1), "the mid-day request advances the index post-rotation");
        assertTrue(newVRF.lastRequestId() > reqIdBefore, "the mid-day request fired on the new coordinator");
    }
}
