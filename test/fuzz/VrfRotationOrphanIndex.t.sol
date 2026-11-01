// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title VrfRotationOrphanIndex -- emergency rotation keeps the reserved lootbox index
/// @notice A mid-day request reserves lootbox index N. A real emergency rotation to a second
///         coordinator while that request is in flight, then fulfilment on the new coordinator,
///         writes the delivered word into _lootboxWord(N).
/// @dev    The ticket drain (DegenerusGameTicketModule `_runTicketWork`) reads
///         entropy = _lootboxWord(_rngReadBuffer()) and passes it to `_drainQueue`; that is
///         the index this test targets.
contract VrfRotationOrphanIndex is DeployProtocol {
    /// @dev Storage slot constants (authoritative storage-layout, not the drifted analog).
    uint256 private constant SLOT_LOOTBOX_PACKED = GameSlots.LOOTBOX_RNG_PACKED;
    uint256 private constant SLOT_LOOTBOX_WORD_MAP = GameSlots.RNG_DAY_TAGS;
    /// @dev LR_MID_DAY occupies byte 28 of lootboxRngPacked (bit offset 224, mask 0xFF).
    uint256 private constant LR_MID_DAY_BIT = 224;

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
        assertEq(index, RecyclingState.readBuffer(address(game)), "current committed read buffer");
        uint256 payload = uint256(vm.load(address(game), bytes32(uint256(3))));
        return payload > 1 ? payload : 0;

    }

    // ──────────────────────────────────────────────────────────────────────
    // Sequence helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Drain every request created while completing the day. Craps now requests
    /// at zero subscription balance, so a composed mineFlip can issue another word
    /// after unlocking the daily request; that word must be answered before mining again.
    function _completeDay(uint256 vrfWord) internal {
        for (uint256 i; i < 200; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
            try game.mineRun(0) {} catch (bytes memory reason) {
                if (reason.length >= 4 && bytes4(reason) == bytes4(keccak256("NoWork()"))) {
                    assertFalse(game.rngLocked(), "daily work drained");
                    assertTrue(game.rngComplete(), "read consumers drained");
                    return;
                }
                assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            }
        }
        fail("fixture did not finish daily and scheduled requests");
    }

    /// @dev The mid-day request through mineFlip, its only door, as the engine's next action.
    function _mineMiddayRequest() internal {
        uint256 prior = mockVRF.lastRequestId();
        game.mineRun(0);
        assertGt(mockVRF.lastRequestId(), prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
    }

    /// @dev Drive the game into a state where the mid-day request succeeds AND its buffer
    ///      swap sets LR_MID_DAY=1: complete two days so today's daily RNG is recorded,
    ///      make a lootbox purchase (creates pending ETH + a ticket-queue entry), fund the
    ///      native VRF subscription above the lootbox floor.
    function _setupForMidDayRng() internal {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);

        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchaseOrderFor{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Perform a REAL mid-flight emergency rotation: deploy a 2nd MockVRFCoordinator,
    ///      create + fund its subscription, add the game as a consumer, then ADMIN-prank
    ///      updateVrfCoordinatorAndSub. Must be called WHILE LR_MID_DAY==1 so the contract's
    ///      mid-day re-issue branch fires: it preserves LR_INDEX and
    ///      re-requests the VRF word on the new coordinator so the word lands in the SAME
    ///      reserved slot N via the mid-day fulfillment branch.
    function _rotateMidFlight() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        newVRF.fundSubscription(newSubId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)), 300_000);
    }

    // ──────────────────────────────────────────────────────────────────────
    // A real mid-flight rotation lands a real VRF word in slot N
    // ──────────────────────────────────────────────────────────────────────

    /// @notice After a mid-day request (through mineFlip) + a real emergency rotation to a 2nd
    ///         MockVRFCoordinator while the request is in flight + fulfillRandomWords on the
    ///         NEW coordinator, _lootboxWord(reservedIndex) == vrfWord. The reserved
    ///         slot N (LR_INDEX-1 captured before the rotation) is preserved across the
    ///         rotation, the slot is empty until fulfilment (no tautology), and the asserted
    ///         word is contract-written via rawFulfillRandomWords -- never vm.stored by the test.
    function test_midDayRotation_landsRealWordInReservedIndex(uint256 vrfWord) public {
        // rawFulfillRandomWords ignores words below 2; assume vrfWord > 1
        // so the equality assertion against the delivered word is exact.
        vm.assume(vrfWord > 1);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the reserved slot N = LR_INDEX-1.
        _mineMiddayRequest();
        uint48 reservedIndex = _readLootboxRngIndex() ^ 1;

        // The mid-day buffer swap set LR_MID_DAY=1, so the rotation's mid-day re-issue
        // branch will fire.
        assertEq(_readMidDayFlag(), 1, "the mid-day request must set LR_MID_DAY=1");

        // The reserved slot is orphaned-pending (empty) -- the assertion is not pre-satisfied.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot must be empty before fulfilment");

        // Real emergency rotation to a freshly-deployed 2nd coordinator while in flight.
        MockVRFCoordinator newVRF = _rotateMidFlight();

        // The rotation re-fired the request on the NEW coordinator (re-issue, not zero).
        assertTrue(newVRF.lastRequestId() != 0, "rotation must re-issue the request on the new coordinator");
        assertTrue(newVRF.lastNativePayment(), "replacement mid-day request pays native");

        // LR_INDEX is preserved across the rotation: the same slot N is still reserved.
        assertEq(_readLootboxRngIndex() ^ 1, reservedIndex, "rotation must preserve the reserved index");

        // Still empty before the new coordinator fulfils -- proves no tautology.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot must still be empty pre-fulfilment");

        // Fulfil the re-issued request on the NEW coordinator. The contract writes the word
        // into _lootboxWord(reservedIndex) via rawFulfillRandomWords (mid-day branch).
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);

        // The real VRF word landed in the SAME preserved slot N -- contract-derived, not test-written.
        assertEq(
            _readLootboxWord(reservedIndex),
            vrfWord,
            "real VRF word must land in the preserved orphaned index after rotation"
        );
    }
}
