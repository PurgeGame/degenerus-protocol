// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BoundaryGasFixture, PhaseEndSeeder} from "../gas/Lvl100PhaseEndAdvanceGas.t.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";

contract SdgnrsTransitionSeeder is DegenerusGameStorage {
    /// @dev 150 owners on the NEAREST unminted level: at the transition close of level L the
    ///      purchase level is L + 1 (minted on L's last-purchase word) and L + 2 is the first
    ///      level above _mintCeiling(). Its pool mints only as the frozen pool of L + 1's last
    ///      purchase day, so the transition must leave it untouched.
    function seedFarFutureEntries() external {
        uint24 target = level + 2;
        uint24 key = _tqFarFutureKey(target);
        for (uint160 i; i < 150; ++i) {
            address who = address(0xF0200000 + i);
            uint80 packed = _registerEntryOwner(who, target);
            uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
            entryOwnerPosition[key][who] = pos;
            _tqAppend(key, pos);
            _setEntryOwed(target, pos, packed | (uint80(4) << 8));
        }
    }

    function prepareCenturyRequest(uint8 compression) external {
        uint24 day = _simulatedDayIndex();
        level = 99;
        phaseTransitionActive = false;
        jackpotPhaseFlag = false;
        lastPurchaseDay = true;
        jackpotFlags = compression;
        jackpotCounter = 0;
        rngLockedFlag = false;
        rngWordCurrent = 0;
        rngWordByDay[day] = 0;
        rngRequestTime = 0;
        vrfRequestId = 0;
        dailyIdx = day - 1;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        levelPrizePool[99] = 1000 ether;
    }
}

contract SdgnrsCenturyTransitionTest is BoundaryGasFixture {
    uint256 private constant RNG_WORD = uint256(keccak256("century-transition-test")) | 1;
    uint256 private constant REFILL_PERCENT = 25 + uint256(keccak256(abi.encode(
        RNG_WORD, uint256(keccak256("sdgnrs.century.refill")) ^ uint256(100)
    ))) % 51;
    function setUp() public {
        _deployProtocol();
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(sdgnrs), 100 ether);
        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(100, RNG_WORD);
        _restore(realCode);
    }

    /// @dev Formerly testFarFutureDrainFinishesBeforeExactlyOneRefill: the transition used to drain
    ///      the far-future level crossing into the +5 mint window over several chunked advances
    ///      (STAGE_TRANSITION_WORKING), and the refill had to wait for the last chunk. That stage is
    ///      retired: nothing crosses a far-future boundary at the transition any more, so it closes
    ///      in ONE advance. The property kept is the same — the century refills exactly once, at the
    ///      real close — plus the new one it now rests on: an unminted queue is not drained there.
    function testTransitionClosesInOneAdvanceWithExactlyOneRefillLeavingFarFutureUnminted() public {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(SdgnrsTransitionSeeder).runtimeCode);
        SdgnrsTransitionSeeder(address(game)).seedFarFutureEntries();
        vm.etch(address(game), realCode);
        uint256 beforeSupply = sdgnrs.totalSupply();
        uint24 ffKey = (uint24(1) << 22) | (game.level() + 2);
        bytes32 ffLenSlot = keccak256(abi.encode(uint256(ffKey), uint256(12)));
        assertEq(uint256(vm.load(address(game), ffLenSlot)), 150, "fixture: unminted queue seeded");

        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 1, "transition closes and refills in one advance");
        assertEq(sdgnrs.totalSupply(), beforeSupply + REFILL_PERCENT * 1 ether);
        assertEq(sdgnrs.centurySupplyCheckpoint(), beforeSupply + REFILL_PERCENT * 1 ether);
        assertFalse(game.rngLocked(), "lock released at transition close");
        // The unminted level is not touched by the transition: every owner still owes its entries
        // on the far-future key, and the queue is not released.
        assertEq(uint256(vm.load(address(game), ffLenSlot)), 150, "transition must not drain an unminted queue");
        for (uint160 i; i < 150; ++i) {
            assertEq(uint32(TQ.owed(address(game), ffKey, address(0xF0200000 + i)) >> 8), 4);
        }
        // The close cannot re-run: the same day's next advance has nothing to do.
        vm.expectRevert(bytes4(keccak256("NotTimeYet()")));
        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        assertEq(sdgnrs.totalSupply(), beforeSupply + REFILL_PERCENT * 1 ether, "exactly one refill");
    }

    function testRecordedTransitionCanCloseAfterCalendarGapWithoutExtraRefill() public {
        vm.warp(block.timestamp + 3 days);
        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        assertEq(sdgnrs.totalSupply(), 1e30 - 100 ether + REFILL_PERCENT * 1 ether);
        vm.prank(address(game));
        sdgnrs.recycleCentury(100, RNG_WORD + 1);
        assertEq(sdgnrs.totalSupply(), 1e30 - 100 ether + REFILL_PERCENT * 1 ether);
    }

    function _prepareRequest(uint8 compression) private {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(SdgnrsTransitionSeeder).runtimeCode);
        SdgnrsTransitionSeeder(address(game)).prepareCenturyRequest(compression);
        vm.etch(address(game), realCode);
    }

    function _fulfillPending() private {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(req);
        if (!fulfilled) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode(req, "century"))) | 1);
    }

    function _driveToClose() private {
        for (uint256 i; i < 1000 && sdgnrs.lastRecycledCentury() == 0; ++i) {
            _fulfillPending();
            if (game.advanceDue() || game.rngLocked()) game.advanceGame();
            else vm.warp(block.timestamp + 1 days + 1);
        }
        assertFalse(game.gameOver());
        assertEq(sdgnrs.lastRecycledCentury(), 1, "century completed through actual jackpot path");
        assertLe(sdgnrs.totalSupply(), sdgnrs.centurySupplyCheckpoint());
        assertLt(sdgnrs.centurySupplyCheckpoint(), 1e30);
    }

    function testRequestAndRetryDoNotRecycleBeforeCompletion() public {
        _prepareRequest(0);
        game.advanceGame();
        assertEq(game.level(), 100, "fresh request promoted level");
        assertTrue(game.rngLocked());
        assertEq(sdgnrs.lastRecycledCentury(), 0, "request is too early to refill");
        uint256 req = mockVRF.lastRequestId();
        vm.warp(block.timestamp + 12 hours + 2);
        game.advanceGame();
        assertGt(mockVRF.lastRequestId(), req, "real VRF retry fired");
        assertEq(game.level(), 100);
        assertEq(sdgnrs.lastRecycledCentury(), 0, "retry cannot mint");
        _driveToClose();
    }

    function testThreeDayCenturyRefillsOnlyOnCompletion() public {
        _prepareRequest(0);
        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        _driveToClose();
    }

    function testTurboCenturyRefillsOnlyOnCompletion() public {
        _prepareRequest(1);
        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        _driveToClose();
    }

    function testDeadmanDuringTransitionClosesWithoutRefill() public {
        vm.warp(block.timestamp + 400 days);
        for (uint256 i; i < 240 && !game.gameOver(); ++i) {
            _fulfillPending();
            game.advanceGame();
        }
        assertTrue(game.gameOver());
        assertTrue(sdgnrs.recyclingClosed());
        assertEq(sdgnrs.lastRecycledCentury(), 0, "terminal path does not complete live century");
    }
}
