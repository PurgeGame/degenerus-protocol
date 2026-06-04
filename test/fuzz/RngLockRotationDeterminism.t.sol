// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// ============================================================================
// RngLockRotationDeterminism.t.sol -- Phase 313 VTST-03 (proves VRF-03)
// ----------------------------------------------------------------------------
// Freeze-invariant fuzz UNDER ROTATION. Extends the v43 canonical harness
// test/fuzz/RngLockDeterminism.t.sol (Phase 301): it reuses that harness'
// snapshot/revert + byte-identity-digest comparison shape
// (_snapshotPreLock / _revertToPreLock / _assertVrfOutputByteIdentity) and the
// perturbation discipline, applied here to the ROTATION perturbation.
//
// Invariant proven: an emergency VRF coordinator/subscription rotation injected
// BETWEEN a VRF request and its fulfilment cannot break the rngLock freeze
// invariant -- given the SAME delivered VRF word, the rotation-perturbed run
// produces a VRF-derived output byte-identical to the no-rotation baseline.
//   Run A (perturbed): rotate the coordinator mid-window via
//     updateVrfCoordinatorAndSub, then deliver the word on the NEW coordinator
//     via the RE-ISSUED request (newVRF.lastRequestId(), NOT the abandoned old
//     request -- that one is rejected by the rawFulfillRandomWords:1793 guard
//     `requestId != vrfRequestId`).
//   Run B (baseline): deliver the SAME word on the ORIGINAL coordinator, no
//     rotation.
//   assertEq(digestA, digestB).
//
// Admin rotation is EXEMPT-class vs PLAYERS per v45-vrf-freeze-invariant
// (311-SPEC section 3): the abandoned old word never enters any digest; the
// re-issued word is the only word consumed this cycle. rotSeed fuzzes the
// rotation newKeyHash/newSubId, which the freeze invariant requires NOT to
// affect the VRF-derived output -- so any digest drift is a real violation.
//
// This is an ADDITIVE new file. It does NOT modify the v43 harness
// test/fuzz/RngLockDeterminism.t.sol (plan 313-06 confirms that file PASSES).
//
// AGENT-COMMITTED test-tree commit per D-43N-TEST-COMMITS-AUTO-01.
// ZERO contracts/ mutation per D-43N-AUDIT-ONLY-01.
// ============================================================================

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RngLockRotationDeterminism -- VTST-03 freeze-invariant fuzz under rotation.
/// @notice Asserts byte-identical VRF-derived outputs between a rotation-perturbed
///         run and a no-rotation baseline given the SAME delivered VRF word.
contract RngLockRotationDeterminism is DeployProtocol {

    // ────────────────────────────────────────────────────────────────────
    // Storage-slot constants (authoritative per `forge inspect DegenerusGame
    // storage-layout` -- slots 37/38, NOT the drifted 38/39 analog in
    // LootboxRngLifecycle.t.sol). Mirrors the v43 RngLockDeterminism.t.sol
    // header + VrfRotationLiveness.t.sol (313-02) slot constants.
    // ────────────────────────────────────────────────────────────────────
    uint256 private constant SLOT_PACKED_0 = 0;
    uint256 private constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 private constant SLOT_VRF_REQUEST_ID = 4;
    uint256 private constant SLOT_LOOTBOX_RNG_INDEX = 37;
    uint256 private constant SLOT_LOOTBOX_RNG_WORD_BY_INDEX = 38;

    /// @dev Last VRF request id fulfilled on the ACTIVE coordinator; avoids
    ///      double-fulfil when the game reuses a stale rngWordCurrent across
    ///      day boundaries.
    uint256 private _lastFulfilledReqId;
    uint256 private constant DRAIN_MAX_ITERATIONS = 600;

    /// @dev The currently-active VRF coordinator. Starts as the deploy-time
    ///      mockVRF and is re-pointed by _rotateMidWindow() so the drain/complete
    ///      helpers fulfil on the live coordinator after a rotation.
    MockVRFCoordinator private _activeVRF;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
    }

    // ────────────────────────────────────────────────────────────────────
    // Shared helpers -- ported VERBATIM (semantics) from the v43 harness
    // RngLockDeterminism.t.sol (they are file-local there, so they cannot be
    // imported) plus the 313-02 active-coordinator + NotTimeYet discipline.
    // ────────────────────────────────────────────────────────────────────

    /// @dev Resolve the active coordinator (deploy-time mockVRF before any rotation).
    function _coord() internal view returns (MockVRFCoordinator) {
        return address(_activeVRF) == address(0) ? mockVRF : _activeVRF;
    }

    /// @dev NotTimeYet() selector -- the same-day "no work available yet" signal
    ///      (AdvanceModule:238). RngNotReady() (the OLD-bug permanent-revert
    ///      failure mode) is deliberately NOT caught: it must propagate.
    bytes4 private constant NOT_TIME_YET = bytes4(keccak256("NotTimeYet()"));

    /// @dev Advance one step, tolerating ONLY NotTimeYet(). Any other revert --
    ///      including RngNotReady() -- is re-thrown verbatim so a defect mode
    ///      fails the test naturally.
    function _advanceTolerant() internal returns (bool progressed) {
        try game.advanceGame() {
            return true;
        } catch (bytes memory err) {
            if (err.length >= 4 && bytes4(err) == NOT_TIME_YET) {
                return false;
            }
            assembly {
                revert(add(err, 0x20), mload(err))
            }
        }
    }

    /// @dev Complete a full day on the ACTIVE coordinator: advanceGame -> fulfil
    ///      any pending request -> drain until unlocked, fulfilling any request
    ///      the drain fires. Stops on NotTimeYet().
    function _completeDay(uint256 vrfWord) internal {
        MockVRFCoordinator c = _coord();
        if (!_advanceTolerant()) return;
        uint256 reqId = c.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            c.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < DRAIN_MAX_ITERATIONS; i++) {
            if (!game.rngLocked()) break;
            if (!_advanceTolerant()) break;
            uint256 r = c.lastRequestId();
            if (r != _lastFulfilledReqId && r > 0) {
                c.fulfillRandomWords(r, vrfWord);
                _lastFulfilledReqId = r;
            }
        }
    }

    /// @dev Drain the daily flow on the ACTIVE coordinator while rngLocked():
    ///      advanceGame and fulfil any request the drain fires.
    function _drainUntilUnlocked(uint256 vrfWord) internal {
        MockVRFCoordinator c = _coord();
        for (uint256 i = 0; i < DRAIN_MAX_ITERATIONS; i++) {
            if (!game.rngLocked()) break;
            if (!_advanceTolerant()) break;
            uint256 r = c.lastRequestId();
            if (r != _lastFulfilledReqId && r > 0) {
                c.fulfillRandomWords(r, vrfWord);
                _lastFulfilledReqId = r;
            }
        }
    }

    function _readRngWordCurrent() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_RNG_WORD_CURRENT))));
    }

    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    function _readLootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(SLOT_LOOTBOX_RNG_INDEX)))));
    }

    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(SLOT_LOOTBOX_RNG_WORD_BY_INDEX)));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Advance state to a daily VRF-request boundary on the ACTIVE
    ///      coordinator. Mirrors the v43 _advanceToVrfRequestBoundary, but uses
    ///      _advanceTolerant + _coord so it works pre- and post-rotation.
    function _advanceToVrfRequestBoundary() internal returns (uint256 reqId) {
        vm.warp(block.timestamp + 1 days);
        _advanceTolerant();
        reqId = _coord().lastRequestId();
        require(reqId != 0, "harness: VRF request must be pending");
        require(game.rngLocked(), "harness: rngLock must engage");
        (, , bool fulfilled) = _coord().pendingRequests(reqId);
        require(!fulfilled, "harness: VRF request already fulfilled");
    }

    /// @dev Fulfil `word` on the ACTIVE coordinator's `reqId` (if not already
    ///      fulfilled), then drain the lock window. Mirrors the v43 _deliverMockVrf.
    function _deliverMockVrf(uint256 reqId, uint256 word) internal {
        MockVRFCoordinator c = _coord();
        (, , bool fulfilled) = c.pendingRequests(reqId);
        if (!fulfilled) {
            c.fulfillRandomWords(reqId, word);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < DRAIN_MAX_ITERATIONS; i++) {
            if (!game.rngLocked()) break;
            if (!_advanceTolerant()) break;
            uint256 r = c.lastRequestId();
            if (r != _lastFulfilledReqId && r > 0) {
                c.fulfillRandomWords(r, word);
                _lastFulfilledReqId = r;
            }
        }
    }

    function _snapshotPreLock() internal returns (uint256 snapshotId) {
        return vm.snapshot();
    }

    function _revertToPreLock(uint256 snapshotId) internal {
        vm.revertTo(snapshotId);
        // After a revert the active coordinator returns to the deploy-time
        // mockVRF and the per-coordinator fulfilment counter resets.
        _activeVRF = MockVRFCoordinator(payable(address(0)));
        _lastFulfilledReqId = 0;
    }

    function _assertVrfOutputByteIdentity(
        bytes32 perturbed,
        bytes32 baseline,
        string memory label
    ) internal pure {
        assertEq(perturbed, baseline, label);
    }

    // ────────────────────────────────────────────────────────────────────
    // Rotation-perturbation helpers (this file's specialization of the v43
    // perturbation library: the perturbation IS the emergency rotation).
    // ────────────────────────────────────────────────────────────────────

    /// @dev Deploy + fund a 2nd MockVRFCoordinator and ADMIN-prank
    ///      updateVrfCoordinatorAndSub(newCoord, newSub, bytes32(seed)). Repoints
    ///      the active coordinator and resets the per-coordinator fulfilment
    ///      counter. `seed` fuzzes the rotation newKeyHash/newSubId (which the
    ///      freeze invariant requires NOT to influence the VRF-derived output).
    function _rotateMidWindow(uint256 seed) internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        // Burn a fuzzed number of subscription ids so the new subId varies with
        // the seed -- the freeze invariant must hold regardless of which subId
        // the rotation targets.
        uint256 burn = seed % 4;
        for (uint256 i = 0; i < burn; i++) {
            newVRF.createSubscription();
        }
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        newVRF.fundSubscription(newSubId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(seed));
        _activeVRF = newVRF;
        _lastFulfilledReqId = 0;
    }

    /// @dev Digest of the VRF-derived DAILY state after the drain: the day word
    ///      recorded for the current day, the current day index, and
    ///      rngWordCurrent. Identical inputs (same delivered word) must yield an
    ///      identical digest whether or not a rotation occurred mid-window.
    function _captureDailyVrfDigest() internal view returns (bytes32) {
        uint32 today = game.currentDayView();
        uint256 dayWord = game.rngWordForDay(uint24(today));
        uint256 rngWordCurrent = _readRngWordCurrent();
        return keccak256(abi.encode(today, dayWord, rngWordCurrent));
    }

    /// @dev LR_MID_DAY occupies byte 28 of lootboxRngPacked (bit offset 224,
    ///      mask 0xFF) -- the mid-day-in-flight flag updateVrfCoordinatorAndSub
    ///      reads at :1726 to take the mid-day re-issue branch.
    uint256 private constant LR_MID_DAY_BIT = 224;

    function _readMidDayFlag() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_LOOTBOX_RNG_INDEX))));
        return (packed >> LR_MID_DAY_BIT) & 0xFF;
    }

    /// @dev Drive the game into a mid-day RNG-eligible state where
    ///      requestLootboxRng() succeeds AND its buffer swap sets LR_MID_DAY=1:
    ///      complete two days so today's daily RNG is recorded, make a lootbox
    ///      purchase (pending ETH + a ticket-queue entry), fund the VRF
    ///      subscription. Mirrors VrfRotationLiveness.t.sol (313-02) +
    ///      LootboxRngLifecycle.t.sol _setupForMidDayRng.
    function _setupForMidDayRng() internal {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);

        address buyer = makeAddr("midDayRotationBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

        mockVRF.fundSubscription(1, 100e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Task 1: daily-branch rotation byte-identity (VTST-03 / VRF-03)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Daily branch: a coordinator rotation injected between a daily VRF
    ///         request and its fulfilment must not change the VRF-derived daily
    ///         output. Run A rotates mid-window and delivers vrfWord on the NEW
    ///         coordinator (the re-issued request); Run B delivers the SAME
    ///         vrfWord on the ORIGINAL coordinator with no rotation. The two
    ///         VRF-derived daily digests are byte-identical.
    function testFuzz_RotationFreezeInvariant_Daily(
        uint256 vrfWord,
        uint256 rotSeed
    ) public {
        // The contract zero-guards a delivered 0 word to 1 (AdvanceModule:1796),
        // and rngWord==1 is the rngGate "request new RNG" sentinel
        // (AdvanceModule:298) which livelocks the subsequent drain. Exclude both;
        // a real 256-bit VRF word collides with {0,1} only negligibly.
        vm.assume(vrfWord != 0 && vrfWord != 1);

        // Common pre-request steady state: complete the first post-deploy day.
        _completeDay(0xDEAD0001);

        // Snapshot the shared pre-request state so both runs start identically.
        uint256 preLockSnap = _snapshotPreLock();

        // ---- Run A: perturbed (rotation mid-window) ----
        // Warp to a new day and fire the daily request (locked, word undelivered).
        vm.warp(block.timestamp + 1 days);
        _advanceTolerant();
        // Filter iterations where the daily request did not engage (e.g. the day
        // boundary produced no VRF request). Keeps the byte-identity assertion on
        // the reachable common case (matches the v43 harness vm.assume filters).
        if (!game.rngLocked() || mockVRF.lastRequestId() == 0) {
            vm.assume(false);
        }
        if (_readRngWordCurrent() != 0) {
            // Daily word already delivered: the rngWordCurrent!=0 short-circuit
            // would skip re-issue (covered by 313-02 liveness); not this digest's case.
            vm.assume(false);
        }

        // Rotate the coordinator while the daily request is in flight. The
        // rngWordCurrent==0 re-issue branch fires a fresh request on the new coord.
        MockVRFCoordinator newVRF = _rotateMidWindow(rotSeed);
        uint256 reissueReqId = newVRF.lastRequestId();
        // The re-issue must exist on the NEW coordinator -- deliver on it, NOT the
        // abandoned old request (which the :1793 requestId guard rejects).
        if (reissueReqId == 0) {
            vm.assume(false);
        }

        _deliverMockVrf(reissueReqId, vrfWord);
        bytes32 digestA = _captureDailyVrfDigest();

        // ---- Run B: baseline (no rotation) ----
        _revertToPreLock(preLockSnap);
        vm.warp(block.timestamp + 1 days);
        _advanceTolerant();
        uint256 baselineReqId = mockVRF.lastRequestId();
        if (!game.rngLocked() || baselineReqId == 0) {
            vm.assume(false);
        }
        _deliverMockVrf(baselineReqId, vrfWord);
        bytes32 digestB = _captureDailyVrfDigest();

        _assertVrfOutputByteIdentity(
            digestA,
            digestB,
            "Rotation daily byte-identity VTST-03 VRF-03"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // Task 2: mid-day-branch rotation byte-identity (LR_INDEX frozen)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Mid-day branch (LR_MID_DAY==1): a coordinator rotation injected
    ///         between a mid-day lootbox-RNG request and its fulfilment must not
    ///         change the VRF-derived per-index output, AND must preserve the
    ///         reserved index N (LR_INDEX frozen across the window). Run A fires
    ///         requestLootboxRng, rotates mid-flight, and delivers vrfWord on the
    ///         NEW coordinator (the re-issued mid-day request lands in the
    ///         preserved slot N via the :1804 mid-day write); Run B fires
    ///         requestLootboxRng and delivers the SAME vrfWord on the ORIGINAL
    ///         coordinator with no rotation. The reserved index N is identical
    ///         across runs and lootboxRngWordByIndex[N] (== vrfWord) is
    ///         byte-identical across runs.
    function testFuzz_RotationFreezeInvariant_MidDay(
        uint256 vrfWord,
        uint256 rotSeed
    ) public {
        // The contract zero-guards a delivered 0 word to 1 (AdvanceModule:1796):
        // a delivered 0 would be stored as 1, breaking the exact == vrfWord
        // equality and the byte-identity of the per-index word. Exclude 0; a real
        // 256-bit VRF word is 0 only with negligible probability. (1 is a legal
        // mid-day word here -- the mid-day branch writes the index directly and is
        // not subject to the daily rngGate==1 sentinel.)
        vm.assume(vrfWord != 0);

        // Setup runs BEFORE the snapshot so both runs share identical pre-request
        // state (the mid-day-eligible day-2 state + pending lootbox + funded VRF).
        _setupForMidDayRng();

        uint256 preLockSnap = _snapshotPreLock();

        // ---- Run A: perturbed (rotation mid-flight) ----
        // Fire the mid-day request; the buffer swap sets LR_MID_DAY=1 and reserves
        // slot N = LR_INDEX-1.
        try game.requestLootboxRng() {} catch {
            vm.assume(false);
        }
        if (_readMidDayFlag() != 1) {
            // requestLootboxRng did not set the mid-day flag (preconditions not
            // met for this iteration) -- filter, mirroring the v43 harness filters.
            vm.assume(false);
        }
        uint48 reservedIndexA = _readLootboxRngIndex() - 1;
        // Reserved slot is orphaned-pending (empty) -- not a pre-satisfied tautology.
        if (_lootboxRngWord(reservedIndexA) != 0) {
            vm.assume(false);
        }

        // Rotate while the mid-day request is in flight: the LR_MID_DAY==1 branch
        // (:1726) re-issues on the new coordinator and PRESERVES LR_INDEX so the
        // new word lands in the SAME reserved slot N (:1804).
        MockVRFCoordinator newVRF = _rotateMidWindow(rotSeed);
        uint256 reissueReqId = newVRF.lastRequestId();
        if (reissueReqId == 0) {
            vm.assume(false);
        }
        // LR_INDEX preserved across the rotation: the same slot N is still reserved.
        assertEq(
            _readLootboxRngIndex() - 1,
            reservedIndexA,
            "rotation must preserve the reserved mid-day index (LR_INDEX frozen)"
        );

        // Deliver the SAME vrfWord on the NEW coordinator's re-issued request
        // (NOT the abandoned old request, which the :1793 requestId guard rejects).
        newVRF.fulfillRandomWords(reissueReqId, vrfWord);
        // The mid-day branch wrote the word directly into the preserved slot N.
        assertEq(
            _lootboxRngWord(reservedIndexA),
            vrfWord,
            "re-issued word must land in the preserved reserved index after rotation"
        );
        bytes32 digestA = keccak256(abi.encode(reservedIndexA, _lootboxRngWord(reservedIndexA)));

        // ---- Run B: baseline (no rotation) ----
        _revertToPreLock(preLockSnap);

        try game.requestLootboxRng() {} catch {
            vm.assume(false);
        }
        if (_readMidDayFlag() != 1) {
            vm.assume(false);
        }
        uint48 reservedIndexB = _readLootboxRngIndex() - 1;
        if (_lootboxRngWord(reservedIndexB) != 0) {
            vm.assume(false);
        }

        // Deliver the SAME vrfWord on the ORIGINAL coordinator -- no rotation.
        uint256 baselineReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(baselineReqId, vrfWord);
        assertEq(
            _lootboxRngWord(reservedIndexB),
            vrfWord,
            "baseline word must land in the reserved index"
        );
        bytes32 digestB = keccak256(abi.encode(reservedIndexB, _lootboxRngWord(reservedIndexB)));

        // The reserved index is identical across runs: rotation froze LR_INDEX.
        assertEq(
            reservedIndexA,
            reservedIndexB,
            "reserved index identical across rotation-perturbed and baseline runs (LR_INDEX frozen)"
        );
        _assertVrfOutputByteIdentity(
            digestA,
            digestB,
            "Rotation mid-day byte-identity VTST-03 VRF-03"
        );
    }
}
