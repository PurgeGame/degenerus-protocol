// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VrfRotationMidDayReRoll -- regression for finding C1 (VRF-rotation lootbox entropy re-roll).
///
/// @notice A mid-day lootbox VRF word lands in `lootboxRngWordByIndex[N]` (write-once), but the
///         `LR_MID_DAY` flag stays set until the swapped ticket batch drains. PRE-FIX,
///         `updateVrfCoordinatorAndSub` treated `LR_MID_DAY != 0` as "mid-day request in flight"
///         and re-issued a spurious VRF request on the new coordinator; fulfilling it OVERWROTE the
///         already-delivered write-once word `lootboxRngWordByIndex[N]` (an entropy re-roll) and
///         emitted a duplicate LootboxRngApplied. The fix keys the mid-day re-issue on
///         `vrfRequestId != 0` (cleared to 0 on fulfilment) instead of the sticky flag, so a
///         rotation after the word lands does NOT re-issue and the delivered word is preserved.
///
/// @dev TEST-ONLY. No contracts/*.sol touched. Storage-read helpers mirror VrfRotationOrphanIndex.
///      Run: forge test --match-path test/repro/VrfRotationMidDayReRoll.t.sol -vv
contract VrfRotationMidDayReRoll is DeployProtocol {
    uint256 private constant SLOT_LOOTBOX_PACKED = 33;
    uint256 private constant SLOT_LOOTBOX_WORD_MAP = 34;
    uint256 private constant LR_MID_DAY_BIT = 224;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _readLootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED))));
    }

    function _readMidDayFlag() internal view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_PACKED)));
        return (packed >> LR_MID_DAY_BIT) & 0xFF;
    }

    function _readLootboxWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_WORD_MAP));
        return uint256(vm.load(address(game), slot));
    }

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

    /// @dev Drive into a state where requestLootboxRng() succeeds and its buffer swap sets
    ///      LR_MID_DAY=1 (mirrors VrfRotationOrphanIndex._setupForMidDayRng).
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

    /// @notice After a mid-day word has ALREADY LANDED (vrfRequestId cleared, LR_MID_DAY still 1),
    ///         a governance coordinator rotation must NOT re-issue a request and must NOT overwrite
    ///         the delivered write-once lootbox word.
    function test_C1_rotationAfterMidDayWordLands_doesNotReRoll(uint256 midDayWord) public {
        vm.assume(midDayWord != 0);

        _setupForMidDayRng();

        // Fire the mid-day request; capture the reserved slot N = LR_INDEX - 1.
        game.requestLootboxRng();
        uint48 reservedIndex = _readLootboxRngIndex() - 1;
        assertEq(_readMidDayFlag(), 1, "precondition: requestLootboxRng set LR_MID_DAY=1");

        // Land the mid-day word on the CURRENT coordinator. rawFulfillRandomWords' mid-day branch
        // writes lootboxRngWordByIndex[N] and clears vrfRequestId + rngRequestTime, but LEAVES
        // LR_MID_DAY=1 (it clears only when the swapped ticket batch drains on a later advance).
        uint256 midReqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(midReqId, midDayWord);

        assertEq(_readLootboxWord(reservedIndex), midDayWord, "mid-day word landed in the reserved slot");
        assertEq(_readMidDayFlag(), 1, "LR_MID_DAY stays set after the word lands (batch not yet drained)");

        // Governance rotates the coordinator while LR_MID_DAY is still latched but no request is
        // genuinely in flight (vrfRequestId == 0). The FIX must not re-issue here.
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

    /// @notice Control: a GENUINELY in-flight mid-day request (word not yet landed, vrfRequestId != 0)
    ///         MUST still be re-issued on rotation so the reserved slot eventually fills — proving the
    ///         C1 fix does not over-suppress the legitimate re-issue path.
    function test_C1_rotationDuringGenuineMidDayFlight_stillReIssues(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        _setupForMidDayRng();
        game.requestLootboxRng();
        uint48 reservedIndex = _readLootboxRngIndex() - 1;
        assertEq(_readLootboxWord(reservedIndex), 0, "reserved slot empty before fulfilment");

        // Rotate WHILE the request is genuinely in flight (not yet fulfilled): vrfRequestId != 0.
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
