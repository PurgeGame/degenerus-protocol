// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

// Integration tests for the time-based future-take / skim block inside
// DegenerusGameAdvanceModule._consolidatePoolsAndRewardJackpots.
//
// Design:
//  - The skim is not an independently addressable function; it is inlined
//    into consolidation.
//  - Tests exercise the full pipeline in a single test file (no splitting).
//    Full-pipeline tests drive game.mineRun(0) through DeployProtocol so the
//    consolidation flow runs end-to-end.
//  - SkimHarness serves the pure-math fuzz tests that exercise the
//    _nextToFutureBps pure function and the packed-slot pool helpers. These
//    are NOT full-pipeline tests; they sit in-file alongside the
//    full-pipeline test so everything relevant to the skim is in one file.
//
// NOTE on coverage reachability: _consolidatePoolsAndRewardJackpots is
// declared `private` on DegenerusGameAdvanceModule; a SkimHarness cannot
// invoke it directly. The only production entry is game.mineRun(0)
// which has deep state preconditions (ticket processing, VRF, level
// counters, purchaseStartDay offsets). This file drives mineFlip()
// through DeployProtocol to exercise the consolidation flow from the
// outside; direct consolidation invocation is not possible without a
// contract visibility change.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

contract SkimTransitionSeeder is DegenerusGame {
    function seed(uint24 age, uint24 incomingLevel) external {
        uint24 day = _wallDay();
        level = incomingLevel - 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = _wallDay() - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        _setPrizePools(100 ether, 200 ether);
        currentPrizePool = 0;
        yieldAccumulator = 0;
        _setLevelPrizePool(incomingLevel - 1, 100 ether);
    }
}

/// @title SkimHarness -- Exposes _nextToFutureBps pure helper and pool
///        packed-slot getters for pure-math tests.
///        There is no time-based-future-take wrapper because the underlying
///        function is inlined into _consolidatePoolsAndRewardJackpots.
contract SkimHarness is DegenerusGameAdvanceModule {
    function exposed_setPrizePools(uint128 next, uint128 future) external {
        _setPrizePools(next, future);
    }

    function exposed_getPrizePools() external view returns (uint128 next, uint128 future) {
        return _getPrizePools();
    }

    function exposed_nextToFutureBps(
        uint32 purchaseAge,
        uint24 lvl
    ) external pure returns (uint16) {
        return _nextToFutureBps(purchaseAge, lvl);
    }
}

/// @title FuturepoolSkimTest -- Full-pipeline integration + pure-math
///        coverage of the time-based future-take skim. Inherits
///        DeployProtocol so integration tests drive the real consolidation
///        flow via game.mineRun(0). Full-pipeline invariants relevant
///        to the skim (conservation, insurance, bps curve shape) live in
///        this one file.
contract FuturepoolSkimTest is DeployProtocol {
    SkimHarness internal harness;
    address internal buyer;

    function setUp() public {
        _deployProtocol();
        harness = new SkimHarness();
        buyer = makeAddr("futurepool_skim_buyer");
        vm.deal(buyer, 10_000 ether);
        vm.deal(address(game), 2_000 ether);
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    //  Integration: production mineFlip requests real mock VRF and emits
    //  the actual skim. Literal expected base rates catch caller-side age offsets.
    //  The seeded age is the consolidation age; above 1 the skim reads one day less
    //  (the funding age of a seal-latched closure).
    // =========================================================================
    function test_fullPipeline_day8Trough() public { _checkTransitionSkim(9, 5, 1500); }
    function test_fullPipeline_day30EndpointWithBonus() public { _checkTransitionSkim(31, 15, 4600); }
    function test_fullPipeline_day3PlateauWithBonus() public { _checkTransitionSkim(4, 15, 3100); }
    function test_fullPipeline_day2ShelfWithBonus() public { _checkTransitionSkim(3, 15, 3600); }
    function test_fullPipeline_day1SealShelfWithBonus() public { _checkTransitionSkim(2, 15, 4600); }
    function test_fullPipeline_day1FillShelfWithBonus() public { _checkTransitionSkim(1, 15, 4600); }
    function test_fullPipeline_day0FillShelfWithBonus() public { _checkTransitionSkim(0, 15, 4600); }
    function test_fullPipeline_genesisKeepsOffset() public { _checkTransitionSkim(22, 1, 1300); }

    function _checkTransitionSkim(uint24 age, uint24 incomingLevel, uint256 expectedBase) private {
        vm.warp(block.timestamp + 500 days);
        // The raw level jump models completed ticket work. Retire its genesis queues too,
        // so perpetual renewal can reuse the incoming level's century-ring slot.
        TicketQueueStorage.retireCompleted(address(game), incomingLevel);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(SkimTransitionSeeder).runtimeCode);
        SkimTransitionSeeder(payable(address(game))).seed(age, incomingLevel);
        vm.etch(address(game), original);
        _syncCoinflipFixtureDay(game.currentDayView_g542950());
        vm.deal(address(game), 300 ether); // no yield surplus to perturb the pools
        uint256 word = 0xA77E1;
        bytes32 skimSig = keccak256("PoolSkimApplied(uint24,uint256,uint256)");
        // The synthetic 500-day jump leaves one expired Craps maintenance checkpoint per call
        // ahead of the daily request, so the real pipeline needs hundreds of calls here.
        for (uint256 step; step < 2000; ++step) {
            uint256 nextBefore = game.nextPrizePoolView();
            uint256 futureBefore = game.futurePrizePoolView();
            vm.recordLogs();
            game.mineRun(0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != skimSig) continue;
                (uint256 take, uint256 insurance) = abi.decode(logs[i].data, (uint256, uint256));
                // Freeze reserves 1% of future in pending. Use the live pool ratio at the
                // actual consolidation call, while independently pinning the time curve.
                uint256 ratio = futureBefore * 100 / nextBefore;
                uint256 bps = expectedBase + (200 - ratio) * 2;
                bps += uint256(keccak256(abi.encode(uint256(78), word))) % 1001;
                uint256 nominal = nextBefore * bps / 10_000;
                uint256 halfWidth = nominal / 4;
                if (halfWidth < nextBefore / 10) halfWidth = nextBefore / 10;
                if (halfWidth > nominal) halfWidth = nominal;
                uint256 variance = uint256(keccak256(abi.encode(uint256(79), word)));
                uint256 range = halfWidth * 2 + 1;
                uint256 draw = (variance % range + uint256(keccak256(abi.encode(uint256(80), word))) % range) / 2;
                uint256 expected = nominal + draw - halfWidth;
                if (expected > nextBefore * 80 / 100) expected = nextBefore * 80 / 100;
                assertEq(take, expected, "live consolidation uses the funding age");
                assertEq(insurance, nextBefore / 100, "transition insurance stays at 1%");
                return;
            }
            uint256 id = mockVRF.lastRequestId();
            if (id != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(id);
                if (!fulfilled) mockVRF.fulfillRandomWords(id, word);
            }
        }
        fail("production consolidation never emitted its skim");
    }

    // =========================================================================
    //  PURE-MATH _nextToFutureBps tests via SkimHarness.
    //  Inputs are funding ages, as the production consolidation call passes them,
    //  including for the level-0 exception.
    // =========================================================================

    function test_nextToFutureBps_acceleratedBreakpoints() public view {
        // Fast fills bank more: 45% at ages 0-1 and 35% at age 2 (previously 30% through age 3).
        uint32[13] memory ages = [uint32(0), 1, 2, 3, 4, 7, 8, 9, 19, 29, 30, 31, 100];
        uint16[13] memory expected =
            [uint16(4500), 4500, 3500, 3000, 2700, 1800, 1500, 1636, 3000, 4363, 4500, 4636, 10000];
        for (uint256 i; i < ages.length; ++i) {
            assertEq(harness.exposed_nextToFutureBps(ages[i], 2), expected[i], "first accelerated level");
            assertEq(harness.exposed_nextToFutureBps(ages[i], 101), expected[i], "x01 is not genesis");
        }
    }

    function test_nextToFutureBps_retainsCenturyBonus() public view {
        assertEq(harness.exposed_nextToFutureBps(1, 99), 5400, "day-1 shelf includes nine-point bonus");
        assertEq(harness.exposed_nextToFutureBps(2, 99), 4400, "day-2 shelf includes nine-point bonus");
        assertEq(harness.exposed_nextToFutureBps(2, 15), 3600, "day-2 shelf includes one-point bonus");
        assertEq(harness.exposed_nextToFutureBps(3, 99), 3900, "fast rate includes nine-point bonus");
        assertEq(harness.exposed_nextToFutureBps(4, 99), 3420, "bonus decays toward fixed trough");
        assertEq(harness.exposed_nextToFutureBps(8, 99), 1500, "trough stays fixed");
        assertEq(harness.exposed_nextToFutureBps(19, 99), 3450, "bonus returns along the rising leg");
        assertEq(harness.exposed_nextToFutureBps(30, 99), 5400, "endpoint includes nine-point bonus");
        assertEq(harness.exposed_nextToFutureBps(30, 100), 4500, "century rollover resets bonus");
        assertEq(harness.exposed_nextToFutureBps(30, 15), 4600, "one-point bonus");
    }

    function test_nextToFutureBps_genesisUnchanged() public view {
        uint32[9] memory ages = [uint32(0), 8, 9, 20, 21, 22, 35, 120, 365];
        uint16[9] memory expected = [uint16(3000), 3000, 2870, 1431, 1300, 1421, 3000, 4190, 7620];
        for (uint256 i; i < ages.length; ++i) {
            assertEq(harness.exposed_nextToFutureBps(ages[i], 1), expected[i], "original genesis curve");
        }
    }

    function testFuzz_nextToFutureBps_fastFillShelves(uint24 lvl) public view {
        lvl = uint24(bound(lvl, 2, type(uint24).max));
        uint256 bonus = (uint256(lvl % 100) / 10) * 100;
        assertEq(harness.exposed_nextToFutureBps(0, lvl), 4500 + bonus, "age 0 takes the day-1 shelf");
        assertEq(harness.exposed_nextToFutureBps(1, lvl), 4500 + bonus, "first-day fill settles at age 1");
        assertEq(harness.exposed_nextToFutureBps(2, lvl), 3500 + bonus, "second-day fill");
        assertEq(harness.exposed_nextToFutureBps(3, lvl), 3000 + bonus, "third-day fill");
        for (uint32 age; age <= 3; ++age) {
            assertEq(harness.exposed_nextToFutureBps(age, 1), 3000, "genesis keeps its own curve");
        }
    }

    function testFuzz_nextToFutureBps_risingSlope(uint32 age) public view {
        age = uint32(bound(age, 9, 30));
        uint16 beforeBps = harness.exposed_nextToFutureBps(age - 1, 5);
        uint16 afterBps = harness.exposed_nextToFutureBps(age, 5);
        // 30 percentage points / 22 days = 136 or 137 bps per integer day.
        assertGe(afterBps - beforeBps, 136);
        assertLe(afterBps - beforeBps, 137);
    }

    function testFuzz_nextToFutureBps_cap10k(uint32 age, uint24 lvl) public view {
        assertLe(harness.exposed_nextToFutureBps(age, lvl), 10_000, "cap holds across full input range");
        assertLe(harness.exposed_nextToFutureBps(age, 1), 10_000, "genesis cap across full input range");
    }

    function testFuzz_nextToFutureBps_earlyDecay(uint32 age, uint24 lvl) public view {
        age = uint32(bound(age, 4, 8));
        lvl = uint24(bound(lvl, 2, type(uint24).max));
        uint16 beforeBps = harness.exposed_nextToFutureBps(age - 1, lvl);
        uint16 afterBps = harness.exposed_nextToFutureBps(age, lvl);
        uint256 bonus = (uint256(lvl % 100) / 10) * 100;
        assertEq(beforeBps - afterBps, 300 + bonus / 5, "falls evenly to the fixed trough");
    }

    // =========================================================================
    //  Harness state-seed and packed-slot helpers: verify the retained
    //  SkimHarness accessors still read/write the pool slot correctly after
    //  removal of the removed future-take wrapper.
    // =========================================================================

    function test_skimHarness_prizePoolSlot_roundTrip() public {
        // Deploy a fresh harness and round-trip pool values through the slot.
        harness.exposed_setPrizePools(100 ether, 200 ether);
        (uint128 nextOut, uint128 futureOut) = harness.exposed_getPrizePools();
        assertEq(nextOut, 100 ether, "next round-trip");
        assertEq(futureOut, 200 ether, "future round-trip");
    }

}
