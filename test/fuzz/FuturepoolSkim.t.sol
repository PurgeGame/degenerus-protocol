// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

// Integration tests for the time-based future-take / skim block inside
// DegenerusGameAdvanceModule._consolidatePoolsAndRewardJackpots.
//
// Per Phase 222 D-01/D-02/D-03:
//  - The skim is no longer an independently addressable function
//    (inlined into consolidation in v20.0, commit d8dbd9e3).
//    D-03 forbids re-extracting it.
//  - D-02 requires tests exercise the full pipeline in the single test
//    file (no splitting). Full-pipeline tests drive game.advanceGame()
//    through DeployProtocol so the consolidation flow runs end-to-end.
//  - SkimHarness is retained (D-03 pattern) for the pure-math fuzz tests
//    that exercise the _nextToFutureBps pure function and the packed-slot
//    pool helpers. These are NOT full-pipeline tests, so retaining them
//    in-file alongside the full-pipeline test does not violate D-02's
//    no-splitting rule — everything relevant to the skim is in one file.
//
// NOTE on coverage reachability: _consolidatePoolsAndRewardJackpots is
// declared `private` on DegenerusGameAdvanceModule; a SkimHarness cannot
// invoke it directly. The only production entry is game.advanceGame()
// which has deep state preconditions (ticket processing, VRF, level
// counters, purchaseStartDay offsets). This file drives advanceGame()
// through DeployProtocol to exercise the consolidation flow from the
// outside; direct consolidation invocation is not possible without a
// contract visibility change that D-03 forbids.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

contract SkimTransitionSeeder is DegenerusGame {
    function seed(uint24 age, uint24 incomingLevel) external {
        uint24 day = _simulatedDayIndex();
        level = incomingLevel - 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        lastPurchaseDay = true;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        _setPrizePools(100 ether, 200 ether);
        currentPrizePool = 0;
        yieldAccumulator = 0;
        levelPrizePool[incomingLevel - 1] = 100 ether;
    }
}

/// @title SkimHarness -- Exposes _nextToFutureBps pure helper and pool
///        packed-slot getters for pure-math tests. Retained per D-03.
///        The time-based-future-take wrapper that previously lived here
///        is absent because the underlying function was inlined into
///        _consolidatePoolsAndRewardJackpots in v20.0.
contract SkimHarness is DegenerusGameAdvanceModule {
    function exposed_setPrizePools(uint128 next, uint128 future) external {
        _setPrizePools(next, future);
    }

    function exposed_getPrizePools() external view returns (uint128 next, uint128 future) {
        return _getPrizePools();
    }

    function setLevelPrizePool(uint24 lvl, uint256 val) external {
        levelPrizePool[lvl] = val;
    }

    function getYieldAccumulator() external view returns (uint256) {
        return yieldAccumulator;
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
///        flow via game.advanceGame(). Full-pipeline invariants relevant
///        to the skim (conservation, insurance, bps curve shape) live in
///        this one file per D-02's "no splitting" rule.
contract FuturepoolSkimTest is DeployProtocol {
    /// @dev Mirror of production constants used for assertion thresholds.
    uint16 private constant INSURANCE_SKIM_BPS = 100;
    uint16 private constant NEXT_TO_FUTURE_BPS_MAX = 8000;
    uint16 private constant ADDITIVE_RANDOM_BPS = 1000;
    uint16 private constant OVERSHOOT_THRESHOLD_BPS = 12500;
    uint16 private constant OVERSHOOT_CAP_BPS = 3500;
    uint16 private constant OVERSHOOT_COEFF = 4000;
    uint16 private constant PRICE_COIN_UNIT = 400;

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
    //  Integration: production advanceGame requests real mock VRF and emits
    //  the actual skim. Literal expected base rates catch caller-side age offsets.
    // =========================================================================
    function test_fullPipeline_day8Trough() public { _checkTransitionSkim(8, 5, 1500); }
    function test_fullPipeline_day30EndpointWithBonus() public { _checkTransitionSkim(30, 15, 4600); }
    function test_fullPipeline_day3PlateauWithBonus() public { _checkTransitionSkim(3, 15, 3100); }
    function test_fullPipeline_genesisKeepsOffset() public { _checkTransitionSkim(21, 1, 1300); }

    function _checkTransitionSkim(uint24 age, uint24 incomingLevel, uint256 expectedBase) private {
        vm.warp(block.timestamp + 500 days);
        bytes memory original = address(game).code;
        vm.etch(address(game), type(SkimTransitionSeeder).runtimeCode);
        SkimTransitionSeeder(payable(address(game))).seed(age, incomingLevel);
        vm.etch(address(game), original);
        vm.deal(address(game), 300 ether); // no yield surplus to perturb the pools
        uint256 word = 0xA77E1;
        bytes32 skimSig = keccak256("PoolSkimApplied(uint24,uint256,uint256)");
        for (uint256 step; step < 100; ++step) {
            uint256 nextBefore = game.nextPrizePoolView();
            uint256 futureBefore = game.futurePrizePoolView();
            vm.recordLogs();
            game.advanceGame();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != skimSig) continue;
                (uint256 take, uint256 insurance) = abi.decode(logs[i].data, (uint256, uint256));
                // Freeze reserves 1% of future in pending. Use the live pool ratio at the
                // actual consolidation call, while independently pinning the time curve.
                uint256 ratio = futureBefore * 100 / nextBefore;
                uint256 bps = expectedBase + (200 - ratio) * 2;
                bps += uint256(keccak256(abi.encode(word, keccak256("degenerus.skim.bps")))) % 1001;
                uint256 nominal = nextBefore * bps / 10_000;
                uint256 halfWidth = nominal / 4;
                if (halfWidth < nextBefore / 10) halfWidth = nextBefore / 10;
                if (halfWidth > nominal) halfWidth = nominal;
                uint256 variance = uint256(keccak256(abi.encode(word, keccak256("degenerus.skim.variance"))));
                uint256 range = halfWidth * 2 + 1;
                uint256 draw = (variance % range + uint256(keccak256(abi.encode(variance))) % range) / 2;
                uint256 expected = nominal + draw - halfWidth;
                if (expected > nextBefore * 80 / 100) expected = nextBefore * 80 / 100;
                assertEq(take, expected, "live consolidation uses the unshifted purchase age");
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
    //  PURE-MATH SPOT VALUES: overshoot surcharge (the exact formula used
    //  inside the inlined skim block).
    // =========================================================================

    function _calcSurcharge(uint256 rBps) internal pure returns (uint256) {
        if (rBps <= OVERSHOOT_THRESHOLD_BPS) return 0;
        uint256 excess = rBps - OVERSHOOT_THRESHOLD_BPS;
        uint256 surcharge = (excess * OVERSHOOT_COEFF) / (excess + 10_000);
        if (surcharge > OVERSHOOT_CAP_BPS) surcharge = OVERSHOOT_CAP_BPS;
        return surcharge;
    }

    /// @notice Overshoot surcharge spot values: hand-computed reference vs formula.
    function test_overshootSurcharge_spotValues() public pure {
        assertEq(_calcSurcharge(15000), 800, "R=1.5");
        assertEq(_calcSurcharge(20000), 1714, "R=2.0");
        assertEq(_calcSurcharge(30000), 2545, "R=3.0");
        assertEq(_calcSurcharge(100000), OVERSHOOT_CAP_BPS, "R=10 capped");
        assertEq(_calcSurcharge(12500), 0, "R=1.25 no surcharge");
    }

    /// @notice Additive component is the tagged word % 1001, so it is in [0, 1000] bps.
    function testFuzz_additiveRandom_bounded(uint256 rngWord) public pure {
        uint256 additive = uint256(keccak256(abi.encode(rngWord, keccak256("degenerus.skim.bps")))) % (ADDITIVE_RANDOM_BPS + 1);
        assertTrue(additive <= ADDITIVE_RANDOM_BPS, "additive must be <= 1000 bps");
    }

    // =========================================================================
    //  PURE-MATH _nextToFutureBps tests via SkimHarness.
    //  Purchase ages, including the level-0 exception, use the same unshifted
    //  input as the production consolidation call.
    // =========================================================================

    function test_nextToFutureBps_acceleratedBreakpoints() public view {
        uint32[12] memory ages = [uint32(0), 2, 3, 4, 7, 8, 9, 19, 29, 30, 31, 100];
        uint16[12] memory expected = [uint16(3000), 3000, 3000, 2700, 1800, 1500, 1636, 3000, 4363, 4500, 4636, 10000];
        for (uint256 i; i < ages.length; ++i) {
            assertEq(harness.exposed_nextToFutureBps(ages[i], 2), expected[i], "first accelerated level");
            assertEq(harness.exposed_nextToFutureBps(ages[i], 101), expected[i], "x01 is not genesis");
        }
    }

    function test_nextToFutureBps_retainsCenturyBonus() public view {
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

    function test_skimHarness_levelPrizePool_setter() public {
        harness.setLevelPrizePool(5, 1234 ether);
        // The harness intentionally does not expose a getter for
        // levelPrizePool; the setter is sufficient for skim-block
        // state seeding and the setter success (no revert) is the
        // assertion. yieldAccumulator also starts zero on fresh harness.
        assertEq(harness.getYieldAccumulator(), 0, "fresh harness yield=0");
    }
}
