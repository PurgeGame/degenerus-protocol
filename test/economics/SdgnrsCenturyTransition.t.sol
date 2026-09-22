// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BoundaryGasFixture, PhaseEndSeeder} from "../gas/Lvl100PhaseEndAdvanceGas.t.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract SdgnrsTransitionSeeder is DegenerusGameStorage {
    function seedFarFutureEntries() external {
        uint24 target = level + 5;
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
        compressedJackpotFlag = compression;
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
    function setUp() public {
        _deployProtocol();
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(sdgnrs), 100 ether);
        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(100, uint256(keccak256("century-transition-test")) | 1);
        _restore(realCode);
    }

    function testFarFutureDrainFinishesBeforeExactlyOneRefill() public {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(SdgnrsTransitionSeeder).runtimeCode);
        SdgnrsTransitionSeeder(address(game)).seedFarFutureEntries();
        vm.etch(address(game), realCode);
        uint256 beforeSupply = sdgnrs.totalSupply();

        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 0, "working FF chunk must not recycle");
        assertEq(sdgnrs.totalSupply(), beforeSupply);
        assertTrue(game.rngLocked(), "lock holds until transition close");
        for (uint256 i; i < 40 && sdgnrs.lastRecycledCentury() == 0; ++i) game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 1, "drain reaches real close");
        assertEq(sdgnrs.totalSupply(), beforeSupply + 50 ether);
        assertEq(sdgnrs.centurySupplyCheckpoint(), beforeSupply + 50 ether);
    }

    function testRecordedTransitionCanCloseAfterCalendarGapWithoutExtraRefill() public {
        vm.warp(block.timestamp + 3 days);
        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        assertEq(sdgnrs.totalSupply(), 1e30 - 50 ether);
        vm.prank(address(game));
        sdgnrs.recycleCentury(100);
        assertEq(sdgnrs.totalSupply(), 1e30 - 50 ether);
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

    function testCompressedCenturyRefillsOnlyOnCompletion() public {
        _prepareRequest(1);
        game.advanceGame();
        assertEq(sdgnrs.lastRecycledCentury(), 0);
        _driveToClose();
    }

    function testTurboCenturyRefillsOnlyOnCompletion() public {
        _prepareRequest(2);
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
