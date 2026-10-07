// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {TicketQueueStorage as RingStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

import {BoundaryGasFixture, PhaseEndSeeder} from "../gas/Lvl100PhaseEndAdvanceGas.t.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract SdgnrsTransitionSeeder is DegenerusGameStorage, WalletSeed {
    /// @dev 150 owners on the NEAREST unminted level: at the transition close of level L the
    ///      purchase level is L + 1 (minted on L's last-purchase word) and L + 2 is the first
    ///      level above _mintCeiling(). Its pool mints only as the frozen pool of L + 1's last
    ///      purchase day, so the transition must leave it untouched.
    function seedFarFutureEntries() external {
        uint24 target = level + 2;
        uint24 key = _tqFarFutureKey(target);
        for (uint160 i; i < 150; ++i) {
            address who = address(0xF0200000 + i);
            uint80 packed = (uint80(_seedWallet(who)) << OWNER_IDX_SHIFT);
            uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
            _tqAppend(key, pos);
            _setEntryOwed(key, pos, packed | (uint80(4) << 8));
        }
    }

    /// @dev The seeded transition day is the daily phase of a delivered, published request (the
    ///      engine selects DailyPhase only for an active, published, not-yet-complete session),
    ///      and every queue through level 100 drained before its phase ended.
    function openTransitionDailyPhase() external {
        rngRequestDay = _simulatedDayIndex();
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        TQ.retireCompleted(address(this), 100);
    }

    function prepareCenturyRequest(uint8 compression) external {
        uint24 day = _simulatedDayIndex();
        // The level-99 last-purchase state already materialized the constructor's
        // far-future allocations through purchase level 100. Retire those stale genesis
        // queues before a real whale award can reuse their physical roots.
        TQ.retireCompleted(address(this), 100);
        level = 99;
        phaseTransitionActive = false;
        jackpotPhaseFlag = false;
        lastPurchaseDay = true;
        jackpotFlags = compression;
        jackpotCounter = 0;
        rngLockedFlag = false;
        rngWordCurrent = RNG_WORD_WAITING;
        _recordDailyRng(day, 0);
        rngRequestTime = 1;
        vrfRequestId = 1;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        humanReadComplete = true;
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
        sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(sdgnrs), 100e12);
        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(100, RNG_WORD);
        vm.etch(address(game), type(SdgnrsTransitionSeeder).runtimeCode);
        SdgnrsTransitionSeeder(address(game)).openTransitionDailyPhase();
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
        bytes32 ffLenSlot = keccak256(abi.encode(uint256(RingStorage.queueKey(uint24(ffKey))), uint256(12)));
        assertEq(uint32(uint256(vm.load(address(game), ffLenSlot))), 150, "fixture: unminted queue seeded");

        game.mineFlip();
        assertEq(sdgnrs.lastRecycledCentury(), 1, "transition closes and refills in one advance");
        assertEq(sdgnrs.totalSupply(), beforeSupply + REFILL_PERCENT * 1e12);
        assertEq(sdgnrs.centurySupplyCheckpoint(), beforeSupply + REFILL_PERCENT * 1e12);
        assertFalse(game.rngLocked(), "lock released at transition close");
        // The unminted level is not touched by the transition: every owner still owes its entries
        // on the far-future key, and the queue is not released.
        assertEq(uint32(uint256(vm.load(address(game), ffLenSlot))), 150, "transition must not drain an unminted queue");
        for (uint160 i; i < 150; ++i) {
            assertEq(uint32(TQ.owed(address(game), ffKey, address(0xF0200000 + i)) >> 8), 4);
        }
        // The close cannot re-run: cranking the rest of the same day's work (the day-400 fixture's
        // scheduled Craps maintenance catch-up, one lapsed day per checkpoint) reaches an idle
        // engine (NoWork; was NotTimeYet) without a second refill.
        bool idle;
        for (uint256 i; i < 1000 && !idle; ++i) {
            try game.mineFlip() {} catch (bytes memory err) {
                assertEq(bytes4(err), bytes4(keccak256("NoWork()")), "same day ends idle");
                idle = true;
            }
        }
        assertTrue(idle, "the same day runs out of work");
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        assertEq(sdgnrs.totalSupply(), beforeSupply + REFILL_PERCENT * 1e12, "exactly one refill");
    }

    function testRecordedTransitionCanCloseAfterCalendarGapWithoutExtraRefill() public {
        vm.warp(block.timestamp + 3 days);
        game.mineFlip();
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        assertEq(sdgnrs.totalSupply(), 1e24 - 100e12 + REFILL_PERCENT * 1e12);
        vm.prank(address(game));
        sdgnrs.recycleCentury(100, RNG_WORD + 1);
        assertEq(sdgnrs.totalSupply(), 1e24 - 100e12 + REFILL_PERCENT * 1e12);
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
            if (game.advanceDue() || game.rngLocked()) game.mineFlip();
            else if (game.boxesPending()) _finishReadConsumers();
            else vm.warp(block.timestamp + 1 days + 1);
        }
        assertFalse(game.gameOver());
        assertEq(sdgnrs.lastRecycledCentury(), 1, "century completed through actual jackpot path");
        assertLe(sdgnrs.totalSupply(), sdgnrs.centurySupplyCheckpoint());
        assertLt(sdgnrs.centurySupplyCheckpoint(), 1e24);
    }

    function testRequestAndRetryDoNotRecycleBeforeCompletion() public {
        // Completion also drains scheduled table cohorts, whose midday requests need LINK.
        mockVRF.fundSubscription(1, 1_000 ether);
        _prepareRequest(0);
        // The day-400 fixture must catch up scheduled table maintenance before requesting.
        for (uint256 i; i < 512 && !game.rngLocked(); ++i) game.mineFlip();
        assertEq(game.level(), 100, "fresh request promoted level");
        assertTrue(game.rngLocked());
        assertEq(sdgnrs.lastRecycledCentury(), 0, "request is too early to refill");
        uint256 req = mockVRF.lastRequestId();
        vm.warp(block.timestamp + 20 hours + 2);
        admin.retryGameRng(); // the vault owner's retry (this test contract holds the DGVE majority)
        assertGt(mockVRF.lastRequestId(), req, "real VRF retry fired");
        assertEq(game.level(), 100);
        assertEq(sdgnrs.lastRecycledCentury(), 0, "retry cannot mint");
        _driveToClose();
    }

    function testThreeDayCenturyRefillsOnlyOnCompletion() public {
        _prepareRequest(0);
        game.mineFlip();
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        _driveToClose();
    }

    function testTurboCenturyRefillsOnlyOnCompletion() public {
        _prepareRequest(1);
        game.mineFlip();
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        _driveToClose();
    }

    function testDeadmanDuringTransitionClosesWithoutRefill() public {
        vm.warp(block.timestamp + 400 days);
        for (uint256 i; i < 240 && !game.gameOver(); ++i) {
            _fulfillPending();
            game.mineFlip();
        }
        assertTrue(game.gameOver());
        assertTrue(sdgnrs.recyclingClosed());
        assertEq(sdgnrs.lastRecycledCentury(), 0, "terminal path does not complete live century");
    }
}
