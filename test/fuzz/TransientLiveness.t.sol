// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title TransientLiveness — past the purchase deadline, liveness never reads true and then false.
///
/// @notice The purchase-deadline trigger freezes purchases, burns and afking subscriptions and routes
///         decimator and redemption claims terminally. It must read exactly what the advance's
///         game-over path will decide, or a day opens frozen and thaws again:
///           1  target met — distress buys after the deadline day's seal beat the target: the next
///                           day is not frozen (the advance will rescue the level).
///           2  unattended — nobody advances the first day past the deadline: the next day stays
///                           frozen and the next advance ends the level (no deadline credit).
///         Controls: a VRF stall straddling the deadline still waits for its credit, a worded day
///         is finished on its word, and a started ending stays triggered even if the pool recovers.
contract TransientLivenessHarness is DegenerusGameStorage {
    function seed(uint24 lvl, uint24 age, uint48 requestTime, uint24 sealedAge) external {
        level = lvl;
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - age;
        dailyIdx = day - sealedAge;
        rngRequestTime = requestTime;
        // The last daily word was applied on the last sealed day (an unattended gap since then).
        lastVrfProcessedTimestamp = uint48(block.timestamp - uint256(sealedAge) * 1 days);
    }

    function setPools(uint256 target, uint256 next) external {
        levelPrizePool[level] = target;
        _setPrizePools(uint128(next), 0);
    }

    function wordToday() external {
        rngWordByDay[_simulatedDayIndex()] = 1;
    }

    function latchEnding() external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 2);
    }

    function liveness() external view returns (bool) {
        return _livenessTriggered();
    }
}

contract TransientLivenessUnitTest is Test {
    TransientLivenessHarness private h;

    function setUp() public {
        vm.warp(1000 days + 12 hours);
        h = new TransientLivenessHarness();
    }

    function test_targetMetDayAfterDeadlineIsNotTriggered() public {
        h.seed(5, 31, 0, 1);
        h.setPools(10 ether, 9 ether);
        assertTrue(h.liveness(), "control: an unmet target past the deadline triggers");
        h.setPools(10 ether, 11 ether);
        assertFalse(h.liveness(), "a met target is rescued by the advance, so it must not trigger");
    }

    function test_unattendedGapPastDeadlineStaysTriggered() public {
        h.seed(5, 32, 0, 2);
        assertTrue(h.liveness(), "an unattended day earns no deadline credit");
    }

    function test_stallStraddlingDeadlineStillWaits() public {
        h.seed(5, 32, uint48(block.timestamp - 1 days), 2);
        assertFalse(h.liveness(), "a request in flight holds the deadline until its catch-up credit");
    }

    function test_wordedDayIsFinishedOnItsWord() public {
        h.seed(5, 31, 0, 1);
        h.wordToday();
        assertFalse(h.liveness(), "a day that holds its word is finished on it");
    }

    function test_startedEndingStaysTriggeredEvenIfTargetMet() public {
        h.seed(5, 31, 0, 1);
        h.setPools(10 ether, 11 ether);
        h.latchEnding();
        assertTrue(h.liveness(), "the drain latch makes the ending irreversible");
    }
}

contract TransientLivenessSeeder is DegenerusGame {
    function seed(uint24 age) external {
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        levelPrizePool[1] = 10 ether;
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }
}

contract TransientLivenessIntegrationTest is DeployProtocol {
    address private constant BUYER = address(0xB077);
    address private constant BUYER2 = address(0xB078);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(BUYER, 10 ether);
        vm.deal(BUYER2, 10 ether);
        vm.deal(address(game), 20 ether);
    }

    function _seed(uint24 age) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(TransientLivenessSeeder).runtimeCode);
        TransientLivenessSeeder(payable(address(game))).seed(age);
        vm.etch(address(game), original);
    }

    function _advanceWithVrf() private {
        game.advanceGame();
        uint256 id = mockVRF.lastRequestId();
        if (id != 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(id);
            if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(id))));
        }
    }

    /// @dev Run today's advance chain until the day seals (the lock releases on a new daily index).
    function _sealToday() private {
        uint24 day = game.currentDayView();
        for (uint256 i; i < 200; ++i) {
            _advanceWithVrf();
            if (!game.rngLocked() && game.rngWordForDay(day) != 0) return;
        }
        revert("fixture: the day never sealed");
    }

    function _lastPurchaseDay() private view returns (bool lpd) {
        (, , lpd, , ) = game.purchaseInfo();
    }

    function _buyBox(address who, uint256 value) private returns (bool ok) {
        vm.prank(who);
        (ok, ) = address(game).call{value: value}(
            abi.encodeWithSelector(
                game.purchase.selector, who, 0, BoxOrderLib.boCustom(value), bytes32(0), MintPaymentKind.DirectEth, false
            )
        );
    }

    /// @notice Window 1: the deadline day seals with the target unmet, then distress buys beat it.
    function test_distressAfterDeadlineSealKeepsNextDayOpen() public {
        _seed(30);
        _sealToday();
        assertFalse(game.gameOver(), "harness: the deadline day seals");
        assertFalse(_lastPurchaseDay(), "harness: the target was unmet at the seal");
        assertTrue(_buyBox(BUYER, 2 ether), "the deadline day is still a rescue day");

        vm.warp(block.timestamp + 1 days);
        assertFalse(game.livenessTriggered(), "a met target must not freeze the next day");
        assertTrue(_buyBox(BUYER2, 1 ether), "purchases stay open before that day's advance");

        _sealToday();
        assertFalse(game.gameOver(), "the advance rescues the level");
        assertTrue(_lastPurchaseDay() || game.jackpotPhase(), "the rescued level moves on");
        assertFalse(game.livenessTriggered(), "and liveness stays false");
    }

    /// @notice Window 2: nobody advances the first day past the deadline.
    function test_unattendedDayPastDeadlineStaysFrozenAndEnds() public {
        _seed(31);
        assertTrue(game.livenessTriggered(), "control: the first day past the deadline is frozen");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.livenessTriggered(), "an unattended day does not thaw the freeze");
        assertFalse(_buyBox(BUYER2, 1 ether), "purchases stay closed");
        for (uint256 i; i < 30 && !game.gameOver(); ++i) _advanceWithVrf();
        assertTrue(game.gameOver(), "the next advance ends the level");
    }
}
