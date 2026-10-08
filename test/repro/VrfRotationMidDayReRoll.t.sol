// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title VrfRotationMidDayReRoll -- regression for finding C1 (VRF-rotation lootbox entropy re-roll).
///
/// @notice A delivered session word is immutable even while the ticket latch remains set.
///         Rotation may reissue an active unanswered request, preserving its physical buffer;
///         it must never reissue one whose usable word has already arrived. Request metadata
///         remains nonzero, so the active flag and waiting payload decide authority.
/// @dev TEST-ONLY. Callback landing is observed before mandatory keeper publication.
contract VrfRotationMidDayReRoll is DeployProtocol {
    uint256 private constant SLOT_LOOTBOX_PACKED = GameSlots.LOOTBOX_RNG_PACKED;
    uint256 private constant LR_MID_DAY_BIT = 224;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _readLootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _readMidDayFlag() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED)));
        return (packed >> LR_MID_DAY_BIT) & 0xFF;
    }

    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        assertEq(index, RecyclingState.readBuffer(address(game)), "current committed read buffer");
        uint256 payload = uint256(vm.load(address(game), bytes32(uint256(3))));
        return payload > 1 ? payload : 0; // Callback landing before keeper publication.

    }

    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 i; i < 512 && !game.rngLocked(); ++i) game.mineFlip(0);
        assertTrue(game.rngLocked(), "daily request starts after prior consumers finish");
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
    }

    /// @dev The mid-day request through mineFlip, its only door, as the engine's next action.
    function _mineMiddayRequest() internal {
        uint256 prior = mockVRF.lastRequestId();
        game.mineFlip(0);
        assertGt(mockVRF.lastRequestId(), prior, "mineFlip issued the mid-day request");
        assertFalse(game.rngLocked(), "a mid-day request, not the daily one");
    }

    /// @dev Drive into a state where the mid-day request succeeds and its buffer swap sets
    ///      LR_MID_DAY=1 (mirrors VrfRotationOrphanIndex._setupForMidDayRng).
    function _setupForMidDayRng() internal {
        _completeDay(0xDEAD0001);
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xDEAD0002);
        _finishReadConsumers();
        address buyer = makeAddr("lootboxBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @notice After a mid-day word has ALREADY LANDED (metadata retained, LR_MID_DAY still 1),
    ///         a governance coordinator rotation must NOT re-issue a request and must NOT overwrite
    ///         the delivered write-once lootbox word.
    function test_C1_rotationAfterMidDayWordLands_doesNotReRoll(uint256 midDayWord) public {
        vm.assume(midDayWord > 1);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the sealed physical read buffer.
        _mineMiddayRequest();
        uint48 reservedIndex = _readLootboxRngIndex() ^ 1;
        assertEq(_readMidDayFlag(), 1, "precondition: the mid-day request set LR_MID_DAY=1");

        // The callback stores only the finalized payload. Metadata and the ticket
        // latch are retained until their required keeper stages run.
        uint256 midReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(midReqId, midDayWord);

        assertEq(_readLootboxWord(reservedIndex), midDayWord, "mid-day word landed in the reserved slot");
        assertEq(_readMidDayFlag(), 1, "LR_MID_DAY stays set after the word lands (batch not yet drained)");

        // Governance rotates the coordinator while LR_MID_DAY is still latched but no request is
        // genuinely unanswered (a usable payload has arrived). The FIX must not re-issue here.
        MockVRFCoordinator newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        newVRF.fundSubscription(newSubId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));

        // POST-FIX: no spurious re-issue on the new coordinator.
        assertEq(
            newVRF.lastRequestId(),
            0,
            "C1: rotation must NOT re-issue a mid-day request after the word already landed"
        );

        // The delivered write-once word is preserved (pre-fix, a re-issue + fulfil would overwrite it).
        assertEq(
            _readLootboxWord(reservedIndex),
            midDayWord,
            "C1: the delivered lootbox word must not be re-rolled by the rotation"
        );

        // Defensive: even if a stray request existed, fulfilling it must not change the landed word.
        if (newVRF.lastRequestId() != 0) {
            newVRF.fulfillRandomWords(newVRF.lastRequestId(), midDayWord ^ 0xFFFF);
            assertEq(_readLootboxWord(reservedIndex), midDayWord, "C1: word overwritten by a re-issued request");
        }
    }

    /// @notice Control: a GENUINELY in-flight mid-day request (active request with waiting payload)
    ///         MUST still be re-issued on rotation so the reserved slot eventually fills — proving the
    ///         C1 fix does not over-suppress the legitimate re-issue path.
    function test_C1_rotationDuringGenuineMidDayFlight_stillReIssues(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);

        _setupForMidDayRng();
        _mineMiddayRequest();
        uint48 reservedIndex = _readLootboxRngIndex() ^ 1;
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot empty before fulfilment");

        // Rotate WHILE the request is genuinely in flight (not yet fulfilled): its active flag and waiting payload remain.
        MockVRFCoordinator newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        newVRF.fundSubscription(newSubId, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));

        assertTrue(newVRF.lastRequestId() != 0, "C1: genuine in-flight mid-day request must re-issue on rotation");
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);
        assertEq(_readLootboxWord(reservedIndex), vrfWord, "re-issued request fills the reserved slot");
    }
}
