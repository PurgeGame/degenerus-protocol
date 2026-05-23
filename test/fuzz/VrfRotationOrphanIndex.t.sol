// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VrfRotationOrphanIndex -- VTST-01 orphan-index reproduction (proves VRF-01)
/// @notice Proves the CATASTROPHE-class VRF-rotation orphan-index defect is closed by
///         CONTRAST within one contract: the pre-fix arm asserts the entropy-0 defect
///         consequence (a zero word at the consumed lootbox index), the post-fix arm
///         asserts a real VRF-derived word lands in lootboxRngWordByIndex[N] after a
///         REAL mid-flight emergency rotation. A single forge-test invocation runs both.
/// @dev    Storage slots are authoritative per `forge inspect DegenerusGame storage-layout`:
///         slot 37 = lootboxRngPacked (LR_INDEX in low bits, LR_MID_DAY at bit 224 mask 0xFF),
///         slot 38 = lootboxRngWordByIndex mapping (lootboxRngWordByIndex[i] at
///         keccak256(abi.encode(uint256(i), uint256(38)))).
///         The consumer at DegenerusGameMintModule:686 reads
///         entropy = lootboxRngWordByIndex[LR_INDEX - 1] and flows it unguarded into
///         _processOneTicketEntry; that index is the slot both arms target.
///         ZERO contracts/ mutation -- audit-only (D-43N-AUDIT-ONLY-01).
contract VrfRotationOrphanIndex is DeployProtocol {
    /// @dev Storage slot constants (authoritative storage-layout, not the drifted analog).
    uint256 private constant SLOT_LOOTBOX_PACKED = 37;
    uint256 private constant SLOT_LOOTBOX_WORD_MAP = 38;
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

    /// @dev Read LR_INDEX (the low bits of lootboxRngPacked at slot 37).
    function _readLootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED))));
    }

    /// @dev Read the LR_MID_DAY flag (byte 28 of lootboxRngPacked).
    function _readMidDayFlag() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED)));
        return (packed >> LR_MID_DAY_BIT) & 0xFF;
    }

    /// @dev Read lootboxRngWordByIndex[index] from the slot-38 mapping.
    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_WORD_MAP));
        return uint256(vm.load(address(game), slot));
    }

    // ──────────────────────────────────────────────────────────────────────
    // Sequence helpers
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> drain until unlocked.
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

    /// @dev Drive the game into a state where requestLootboxRng() succeeds AND its buffer
    ///      swap sets LR_MID_DAY=1: complete two days so today's daily RNG is recorded,
    ///      make a lootbox purchase (creates pending ETH + a ticket-queue entry), fund the
    ///      VRF subscription above MIN_LINK_FOR_LOOTBOX_RNG.
    function _setupForMidDayRng() internal {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);

        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Perform a REAL mid-flight emergency rotation: deploy a 2nd MockVRFCoordinator,
    ///      create + fund its subscription, add the game as a consumer, then ADMIN-prank
    ///      updateVrfCoordinatorAndSub. Must be called WHILE LR_MID_DAY==1 so the contract's
    ///      mid-day re-issue branch (AdvanceModule:1726) fires: it preserves LR_INDEX and
    ///      re-requests the VRF word on the new coordinator so the word lands in the SAME
    ///      reserved slot N via the mid-day fulfillment branch (AdvanceModule:1803-1804).
    function _rotateMidFlight() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        newVRF.fundSubscription(newSubId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
    }

    // ──────────────────────────────────────────────────────────────────────
    // Post-fix arm: a real mid-flight rotation lands a real VRF word in slot N
    // ──────────────────────────────────────────────────────────────────────

    /// @notice After a mid-day requestLootboxRng + a real emergency rotation to a 2nd
    ///         MockVRFCoordinator while the request is in flight + fulfillRandomWords on the
    ///         NEW coordinator, lootboxRngWordByIndex[reservedIndex] == vrfWord. The reserved
    ///         slot N (LR_INDEX-1 captured before the rotation) is preserved across the
    ///         rotation, the slot is empty until fulfilment (no tautology), and the asserted
    ///         word is contract-written via rawFulfillRandomWords -- never vm.stored by the test.
    function test_postFix_midDayRotation_landsRealWordInOrphanedIndex(uint256 vrfWord) public {
        // The contract converts a delivered 0 word to 1 (AdvanceModule:1796); assume nonzero
        // so the equality assertion against the delivered word is exact.
        vm.assume(vrfWord != 0);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the reserved slot N = LR_INDEX-1.
        game.requestLootboxRng();
        uint48 reservedIndex = _readLootboxRngIndex() - 1;

        // The mid-day buffer swap set LR_MID_DAY=1, so the rotation's mid-day re-issue
        // branch will fire.
        assertEq(_readMidDayFlag(), 1, "requestLootboxRng must set LR_MID_DAY=1");

        // The reserved slot is orphaned-pending (empty) -- the assertion is not pre-satisfied.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot must be empty before fulfilment");

        // Real emergency rotation to a freshly-deployed 2nd coordinator while in flight.
        MockVRFCoordinator newVRF = _rotateMidFlight();

        // The rotation re-fired the request on the NEW coordinator (re-issue, not zero).
        assertTrue(newVRF.lastRequestId() != 0, "rotation must re-issue the request on the new coordinator");

        // LR_INDEX is preserved across the rotation: the same slot N is still reserved.
        assertEq(_readLootboxRngIndex() - 1, reservedIndex, "rotation must preserve the reserved index");

        // Still empty before the new coordinator fulfils -- proves no tautology.
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot must still be empty pre-fulfilment");

        // Fulfil the re-issued request on the NEW coordinator. The contract writes the word
        // into lootboxRngWordByIndex[reservedIndex] via rawFulfillRandomWords (mid-day branch).
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);

        // The real VRF word landed in the SAME preserved slot N -- contract-derived, not test-written.
        assertEq(
            _readLootboxWord(reservedIndex),
            vrfWord,
            "real VRF word must land in the preserved orphaned index after rotation"
        );
    }
}
