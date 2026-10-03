// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Etched over the game: writes the read-cohort flags directly (StallCreditSeeder pattern).
contract AfkingForfeitSeeder is DegenerusGame {
    /// @notice Stage 2 with a pending-box count no stamp in the ring can satisfy.
    function seedStageTwoPhantomCount(uint256 word, uint16 count) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = today;
        _afkingResetDay = today;
        purchaseStartDay = today;
        subsFullyProcessed = true;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngLockedFlag = false;
        prizePoolFrozen = false;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = word;
        rngFlagsAndNudges &= ~(uint16(1) << 13);
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
        if (_recordedDailyWord(today) == 0) _recordDailyRng(today, word);
        degeneretteCursor = uint48(degeneretteQueue[_rngReadBuffer() & 1].length);
        decBattleQueue = 0;
        lootboxRngPacked &= ~(uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer()));
        // Every ring member is box-clean, so the count has no openable stamp behind it.
        uint256 len = _subscribers.length;
        for (uint256 i; i < len; ++i) {
            Sub storage sub = _subOf[_subscribers[i]];
            sub.lastOpenedDay = sub.lastAutoBoughtDay;
        }
        _pendingBoxCount = count;
    }

    /// @notice Drop every ring member (the index mapping is left stale; nothing reads it here).
    function forceEmptySubscriberSet() external {
        assembly ("memory-safe") { sstore(_subscribers.slot, 0) }
    }

    function pendingBoxCount() external view returns (uint16) { return _pendingBoxCount; }
    function subscribersLength() external view returns (uint256) { return _subscribers.length; }
    function subscriberAt(uint256 i) external view returns (address) { return _subscribers[i]; }
    function markers(address who) external view returns (uint24 bought, uint24 opened) {
        Sub storage sub = _subOf[who];
        return (sub.lastAutoBoughtDay, sub.lastOpenedDay);
    }
}

/// @title DegradeAfkingForfeit — stage 2 forfeits a pending-box count no stamp can satisfy
/// @notice `_pendingBoxCount` equals the number of openable stamps in the ring on every reachable
///         state (test/repro/PendingBoxCountInvariant.t.sol). This test breaks that invariant on
///         purpose, in both shapes the lane named (a non-empty ring with no openable stamp, and
///         an empty ring), and shows one `mineFlip` clears the count, certifies the session and
///         moves no ETH: the stamps' ETH reached the prize pools when they were stamped and
///         stays there, no box opens and no marker is written.
contract DegradeAfkingForfeitTest is DeployProtocol {
    bytes internal realCode;
    bytes32 private constant FORFEIT = keccak256("AfkingBoxCountForfeited(uint16)");
    bytes32 private constant LOOTBOX_OPENED =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    uint8 private constant AFKING = 9;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        realCode = address(game).code;
    }

    function _seeder() internal returns (AfkingForfeitSeeder s) {
        vm.etch(address(game), type(AfkingForfeitSeeder).runtimeCode);
        s = AfkingForfeitSeeder(payable(address(game)));
    }

    function _restore() internal { vm.etch(address(game), realCode); }

    function testPhantomCountWithBoxCleanRingIsForfeited() public {
        AfkingForfeitSeeder s = _seeder();
        s.seedStageTwoPhantomCount(uint256(keccak256("degrade-afking-ring")) | 2, 3);
        uint256 len = s.subscribersLength();
        address[] memory ring = new address[](len);
        uint24[] memory bought = new uint24[](len);
        uint24[] memory opened = new uint24[](len);
        for (uint256 i; i < len; ++i) {
            ring[i] = s.subscriberAt(i);
            (bought[i], opened[i]) = s.markers(ring[i]);
        }
        _restore();

        _runAndAssertForfeit(3);

        s = _seeder();
        for (uint256 i; i < len; ++i) {
            (uint24 b, uint24 o) = s.markers(ring[i]);
            assertEq(uint256(b), uint256(bought[i]), "stamp day untouched");
            assertEq(uint256(o), uint256(opened[i]), "open marker untouched");
        }
        _restore();
    }

    function testPhantomCountWithEmptyRingIsForfeited() public {
        AfkingForfeitSeeder s = _seeder();
        s.seedStageTwoPhantomCount(uint256(keccak256("degrade-afking-empty")) | 2, 5);
        s.forceEmptySubscriberSet();
        assertEq(s.subscribersLength(), 0, "fixture: empty ring");
        _restore();

        _runAndAssertForfeit(5);
    }

    function _runAndAssertForfeit(uint16 seededCount) internal {
        assertEq(game.rngConsumerStage(), 2, "fixture: stage 2");
        assertFalse(game.rngComplete(), "fixture: no certificate");
        assertEq(game.minerAction(), AFKING, "fixture: selector picks Afking");

        uint256 nextBefore = game.nextPrizePoolView();
        uint256 futureBefore = game.futurePrizePoolView();
        uint256 claimableBefore = game.claimablePoolView();
        uint256 balanceBefore = address(game).balance;

        vm.recordLogs();
        vm.prank(makeAddr("afking-miner"));
        game.mineFlip();

        bool forfeited;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == FORFEIT) {
                forfeited = true;
                assertEq(uint256(abi.decode(logs[i].data, (uint16))), uint256(seededCount), "forfeited count is the whole phantom count");
            }
            assertTrue(logs[i].topics[0] != LOOTBOX_OPENED, "no box was opened");
        }
        assertTrue(forfeited, "the forfeit was recorded");

        AfkingForfeitSeeder s = _seeder();
        assertEq(uint256(s.pendingBoxCount()), 0, "the phantom count is cleared");
        _restore();
        assertTrue(game.rngComplete(), "the session certified in the same call");
        assertTrue(game.rngConsumerStage() != 2, "stage 2 is not reselected");
        assertEq(game.nextPrizePoolView(), nextBefore, "next pool untouched");
        assertEq(game.futurePrizePoolView(), futureBefore, "future pool untouched");
        assertEq(game.claimablePoolView(), claimableBefore, "claimable pool untouched");
        assertEq(address(game).balance, balanceBefore, "no ETH left the game");
    }
}
