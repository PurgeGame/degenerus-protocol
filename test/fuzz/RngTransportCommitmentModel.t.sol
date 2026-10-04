// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameRngModule} from "../../contracts/modules/DegenerusGameRngModule.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Exposes production transport transitions. Seeding isolates the transition model;
/// it does not claim that every generated combination is a reachable whole-game state.
contract RngTransportModelHarness is DegenerusGameRngModule {
    function seed(address coordinator, uint256 id, bool daily, uint16 nudges, bool write,
        uint24 logicalDay, uint48 originalTime) external {
        vrfCoordinator = IVRFCoordinator(coordinator);
        vrfSubscriptionId = 1;
        vrfRequestId = id;
        rngLockedFlag = daily;
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
        rngRequestDay = logicalDay;
        rngRequestTime = originalTime & ~uint48(1);
        rngWordCurrent = RNG_WORD_WAITING;
        rngFlagsAndNudges = (uint16(1) << 14) | (write ? uint16(1) << 12 : 0);
        _setNudgeCount(nudges);
        lootboxRngPacked = 0;
    }

    function transport() external view returns (uint256 id, uint48 stamp, uint24 day, bool daily,
        uint48 write, uint256 nudges, uint256 word, bool active, bool published) {
        return (vrfRequestId, rngRequestTime, rngRequestDay, rngLockedFlag,
            _rngWriteBuffer(), _nudgeCount(), _currentRngWord(), _rngRequestActive(), _rngSessionPublished());
    }

    function commitment() external view returns (bytes32) {
        return keccak256(abi.encode(rngRequestDay, rngLockedFlag, _rngWriteBuffer(), _nudgeCount()));
    }
    function visible(uint48 buffer) external view returns (uint256) { return _lootboxWord(buffer); }
    function dead() external view returns (bool) { return _vrfDead(); }
    function markRetrySpent() external { rngRequestTime |= 1; }
    function deactivate() external { _setRngRequestActive(false); }

    /// @dev Mirror of DegenerusGame.rawFulfillRandomWords (the callback lives in the facade,
    ///      not the module, so the LINK-paid call carries no delegatecall overhead).
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) revert OnlyCoordinator();
        uint16 flags;
        bool daily;
        assembly ("memory-safe") {
            let state := sload(rngFlagsAndNudges.slot)
            flags := shr(mul(rngFlagsAndNudges.offset, 8), state)
            daily := and(shr(mul(rngLockedFlag.offset, 8), state), 1)
        }
        if (flags & (uint16(1) << 14) == 0 || requestId != vrfRequestId || rngWordCurrent != RNG_WORD_WAITING) return;
        uint256 word = randomWords[0];
        if (daily) {
            unchecked { word += flags & 0xFF; }
        }
        if (word < 2) return;
        rngWordCurrent = word;
    }
}

contract RngTransportCommitmentModelTest is Test {
    RngTransportModelHarness private game;
    MockVRFCoordinator private coordinator;
    uint48 private constant ORIGIN = 100 days;

    function setUp() public {
        vm.warp(ORIGIN);
        coordinator = new MockVRFCoordinator();
        RngTransportModelHarness implementation = new RngTransportModelHarness();
        vm.etch(ContractAddresses.GAME, address(implementation).code);
        game = RngTransportModelHarness(ContractAddresses.GAME);
    }

    function _deliver(address sender, uint256 id, uint256 raw) private {
        uint256[] memory words = new uint256[](1);
        words[0] = raw;
        vm.prank(sender);
        game.rawFulfillRandomWords(id, words);
    }

    function _word() private view returns (uint256 word) { (,,,,,,word,,) = game.transport(); }

    function testFuzz_TransportMatchesIndependentAcceptanceModel(
        uint256 raw, uint16 count, bool daily, bool write, uint32 logicalDay, uint64 id
    ) public {
        count = uint16(bound(count, 0, 255));
        id = uint64(bound(id, 1, type(uint64).max - 1));
        uint24 day = uint24(bound(logicalDay, 1, type(uint24).max));
        game.seed(address(coordinator), id, daily, count, write, day, ORIGIN);
        bytes32 fixedInputs = game.commitment();
        uint48 read = write ? 0 : 1;
        _deliver(address(coordinator), uint256(id) + 1, raw);
        assertEq(_word(), 0, "wrong request cannot accept a word");
        vm.expectRevert(bytes4(keccak256("OnlyCoordinator()")));
        _deliver(address(0xBAD), id, raw);
        _deliver(address(coordinator), id, raw);
        uint256 expected;
        unchecked { expected = raw + (daily ? count : 0); }
        if (expected < 2) expected = 0;
        assertEq(_word(), expected, "independent modular-add/reserved model");
        assertEq(game.commitment(), fixedInputs, "callback preserves frozen inputs");
        assertEq(game.visible(read), 0, "accepted is distinct from published");
        if (expected != 0) {
            _deliver(address(coordinator), id, expected == 42 ? 43 : 42);
            assertEq(_word(), expected, "duplicate cannot selectively replace entropy");
            game.publishRng();
            assertEq(game.visible(read), expected, "publication makes exactly the committed buffer readable");
            assertEq(game.visible(write ? 1 : 0), 0, "future write buffer never sees this word");
            assertEq(game.commitment(), fixedInputs, "publication preserves frozen inputs");
        }
    }

    function testFuzz_RetryPreservesCommitmentAndRejectsStaleResponse(bool daily, bool write, uint16 count) public {
        count = uint16(bound(count, 0, 255));
        // The coordinator allocates replacement id 1. The old transport ID is deliberately 99.
        game.seed(address(coordinator), 99, daily, count, write, 123, ORIGIN);
        bytes32 fixedInputs = game.commitment();
        vm.warp(ORIGIN + 20 hours - 1);
        vm.prank(ContractAddresses.ADMIN);
        vm.expectRevert(DegenerusGameRngModule.RngNotReady.selector);
        game.retryRng();
        vm.warp(ORIGIN + 20 hours);
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        (uint256 id, uint48 stamp,,,,,,,) = game.transport();
        assertEq(id, 1, "replacement request actually reached coordinator");
        assertEq(stamp & ~uint48(1), ORIGIN, "same original timeout origin");
        assertEq(stamp & 1, 1, "retry is one-shot");
        assertEq(game.commitment(), fixedInputs, "same day/kind/nudges/cohort");
        _deliver(address(coordinator), 99, 0xBAD);
        assertEq(_word(), 0, "superseded transport response is stale");
        _deliver(address(coordinator), id, 0xC0FFEE);
        assertEq(_word(), uint256(0xC0FFEE) + (daily ? count : 0));
        vm.prank(ContractAddresses.ADMIN);
        vm.expectRevert(DegenerusGameRngModule.RngNotReady.selector);
        game.retryRng();
    }

    function test_InactiveRetainedIdentityCannotAcceptCallback() public {
        game.seed(address(coordinator), 7, false, 0, false, 0, ORIGIN);
        game.deactivate();
        _deliver(address(coordinator), 7, 42);
        assertEq(_word(), 0, "retained id alone grants no callback authority");
    }

    function test_RetryBitCanShiftDeadVrfBoundaryByAtMostOneSecond() public {
        game.seed(address(coordinator), 7, false, 0, false, 0, ORIGIN);
        vm.warp(ORIGIN + 14 days - 1);
        assertFalse(game.dead(), "one second before original deadline");
        vm.warp(ORIGIN + 14 days);
        assertTrue(game.dead(), "original deadline is inclusive");
        game.markRetrySpent();
        // Owner-approved tolerance: a packed retry flag may move the boundary by
        // one second. Repeating it must never restart or further extend the timer.
        game.markRetrySpent();
        vm.warp(ORIGIN + 14 days + 1);
        assertTrue(game.dead(), "retry delay is bounded to one second");
        game.markRetrySpent();
        assertTrue(game.dead(), "repeated retry marking never refreshes the timer");
    }

    function test_ReservedAndModularBoundaryCases() public {
        uint256[6] memory raw = [uint256(0), 1, type(uint256).max, type(uint256).max, type(uint256).max, uint256(0)];
        uint16[6] memory nudge = [uint16(0), 0, 1, 2, 3, 255];
        uint256[6] memory expected = [uint256(0), 0, 0, 0, 2, 255];
        for (uint256 i; i < raw.length; ++i) {
            game.seed(address(coordinator), i + 1, true, nudge[i], false, 1, ORIGIN);
            _deliver(address(coordinator), i + 1, raw[i]);
            assertEq(_word(), expected[i]);
        }
    }
}
