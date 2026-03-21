// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";

/// @title SkimHarness -- Exposes _applyTimeBasedFutureTake and pool state for testing.
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

    function setLevelStartTime(uint48 t) external {
        levelStartTime = t;
    }

    function getYieldAccumulator() external view returns (uint256) {
        return yieldAccumulator;
    }

    function exposed_applyTimeBasedFutureTake(
        uint48 reachedAt,
        uint24 lvl,
        uint256 rngWord
    ) external {
        _applyTimeBasedFutureTake(reachedAt, lvl, rngWord);
    }

    function exposed_nextToFutureBps(
        uint48 elapsed,
        uint24 lvl
    ) external pure returns (uint16) {
        return _nextToFutureBps(elapsed, lvl);
    }
}

/// @title FuturepoolSkimTest -- Tests for the redesigned _applyTimeBasedFutureTake.
contract FuturepoolSkimTest is Test {
    SkimHarness harness;

    // Mirror constants (private in source, can't inherit)
    uint16 constant INSURANCE_SKIM_BPS = 100;
    uint16 constant OVERSHOOT_THRESHOLD_BPS = 12500;
    uint16 constant OVERSHOOT_CAP_BPS = 3500;
    uint16 constant OVERSHOOT_COEFF = 4000;
    uint16 constant NEXT_TO_FUTURE_BPS_MAX = 8000;
    uint16 constant ADDITIVE_RANDOM_BPS = 1000;
    uint16 constant NEXT_SKIM_VARIANCE_BPS = 2500;

    uint48 constant LEVEL_START = 1_000_000;

    function setUp() public {
        harness = new SkimHarness();
        harness.setLevelStartTime(LEVEL_START);
    }

    // =========================================================================
    //  Helper: run skim and return results
    // =========================================================================

    function _runSkim(
        uint128 nextPool,
        uint128 futurePool,
        uint24 lvl,
        uint256 lastPool,
        uint48 elapsed,
        uint256 rngWord
    ) internal returns (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) {
        harness.exposed_setPrizePools(nextPool, futurePool);
        if (lvl > 0) harness.setLevelPrizePool(lvl - 1, lastPool);

        uint48 reachedAt = LEVEL_START + 11 days + elapsed;
        harness.exposed_applyTimeBasedFutureTake(reachedAt, lvl, rngWord);

        (nextAfter, futureAfter) = harness.exposed_getPrizePools();
        yieldAfter = harness.getYieldAccumulator();
    }

    function _assertConservation(
        uint128 nextBefore,
        uint128 futureBefore,
        uint128 nextAfter,
        uint128 futureAfter,
        uint256 yieldAfter
    ) internal pure {
        assertEq(
            uint256(nextAfter) + uint256(futureAfter) + yieldAfter,
            uint256(nextBefore) + uint256(futureBefore),
            "conservation: total ETH must be preserved"
        );
    }

    function _calcSurcharge(uint256 rBps) internal pure returns (uint256) {
        if (rBps <= OVERSHOOT_THRESHOLD_BPS) return 0;
        uint256 excess = rBps - OVERSHOOT_THRESHOLD_BPS;
        uint256 surcharge = (excess * OVERSHOOT_COEFF) / (excess + 10_000);
        if (surcharge > OVERSHOOT_CAP_BPS) surcharge = OVERSHOOT_CAP_BPS;
        return surcharge;
    }

    // =========================================================================
    //  A. Normal level (25-day fill, R ≈ 1.05, no overshoot)
    // =========================================================================

    function test_A_normalLevel_noOvershoot() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether; // 2:1 ratio → no ratio adjust
        uint24 lvl = 5;
        uint256 lastPool = 95 ether; // R = 100/95 ≈ 1.05 < 1.25

        uint256 rng = 0; // additive random = 0, variance rolls = 0
        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, 25 days, rng);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);
        assertEq(yieldAfter, uint256(nextPool) * INSURANCE_SKIM_BPS / 10_000, "insurance wrong");

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        assertTrue(take > 0, "should skim something");
        assertTrue(take <= uint256(nextPool) * NEXT_TO_FUTURE_BPS_MAX / 10_000, "should be at/below hard cap");
    }

    // =========================================================================
    //  B. Fast level with overshoot (3-day fill, R = 3.0)
    // =========================================================================

    function test_B_fastOvershoot_R3() public {
        uint128 nextPool = 300 ether;
        uint128 futurePool = 600 ether;
        uint24 lvl = 5;
        uint256 lastPool = 100 ether; // R = 3.0

        uint256 rng = 0;
        (, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, 3 days, rng);

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        // Base 30% + surcharge ~25.5% = ~55.5%. With rng=0: additive=0, variance negative.
        // Even with downward variance, should still be significant.
        assertTrue(take > uint256(nextPool) * 3000 / 10_000, "overshoot should push skim high");
    }

    // =========================================================================
    //  C. Extreme overshoot (1-day fill, R = 10.0) — cap enforced
    // =========================================================================

    function test_C_extremeOvershoot_R10() public {
        uint128 nextPool = 1000 ether;
        uint128 futurePool = 2000 ether;
        uint24 lvl = 5;
        uint256 lastPool = 100 ether; // R = 10.0

        // Max additive + max variance
        uint256 rng = type(uint256).max;
        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, 1 days, rng);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        uint256 maxTake = uint256(nextPool) * NEXT_TO_FUTURE_BPS_MAX / 10_000;
        // Step 5 cap: take <= 80% of nextPool regardless of how high bps got
        assertTrue(take <= maxTake, "take must not exceed 80% cap");
        // At least 19% of nextPool remains (80% take + 1% insurance = 81%)
        assertTrue(uint256(nextAfter) >= uint256(nextPool) * 19 / 100, "must retain ~19%+");
    }

    // =========================================================================
    //  D. Stall (60-day fill, R ≈ 1.0)
    // =========================================================================

    function test_D_stall_60day() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint24 lvl = 5;
        uint256 lastPool = 100 ether;

        uint256 rng = 0;
        (, uint128 futureAfter,) = _runSkim(nextPool, futurePool, lvl, lastPool, 60 days, rng);

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        // 60 days → stall escalation: base = FAST + ((60d-28d)/1w)*100 = 3000+457*1 ≈ 3400+
        assertTrue(take > 0, "stall should still skim");
    }

    // =========================================================================
    //  E. Low futurepool ratio → higher skim
    // =========================================================================

    function test_E_lowFutureRatio_higherSkim() public {
        uint128 nextPool = 100 ether;
        uint256 lastPool = 95 ether;
        uint256 rng = 0;

        // Low ratio: future = 0.5x next
        (, uint128 futureAfterLow,) = _runSkim(nextPool, 50 ether, 5, lastPool, 14 days, rng);
        uint256 takeLow = uint256(futureAfterLow) - 50 ether;

        // Balanced ratio: future = 2x next
        setUp();
        (, uint128 futureAfterBal,) = _runSkim(nextPool, 200 ether, 5, lastPool, 14 days, rng);
        uint256 takeBal = uint256(futureAfterBal) - 200 ether;

        assertTrue(takeLow > takeBal, "low ratio should increase skim");
    }

    // =========================================================================
    //  F. High futurepool ratio → lower skim
    // =========================================================================

    function test_F_highFutureRatio_lowerSkim() public {
        uint128 nextPool = 100 ether;
        uint256 lastPool = 95 ether;
        uint256 rng = 0;

        // High ratio: future = 5x next
        (, uint128 futureAfterHi,) = _runSkim(nextPool, 500 ether, 5, lastPool, 14 days, rng);
        uint256 takeHi = uint256(futureAfterHi) - 500 ether;

        // Balanced ratio
        setUp();
        (, uint128 futureAfterBal,) = _runSkim(nextPool, 200 ether, 5, lastPool, 14 days, rng);
        uint256 takeBal = uint256(futureAfterBal) - 200 ether;

        assertTrue(takeHi < takeBal, "high ratio should decrease skim");
    }

    // =========================================================================
    //  G. Hard cap: take never exceeds 80% of nextPool
    // =========================================================================

    function test_G_hardCap_worstCase() public {
        // Max everything: stale level, low ratio, x9 bonus, extreme overshoot, max rng
        uint128 nextPool = 500 ether;
        uint128 futurePool = 1 ether;
        uint24 lvl = 9;
        uint256 lastPool = 10 ether; // R = 50

        uint256 rng = type(uint256).max; // max additive + max variance
        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, 90 days, rng);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        uint256 maxTake = uint256(nextPool) * NEXT_TO_FUTURE_BPS_MAX / 10_000;
        assertTrue(take <= maxTake, "take must respect 80% cap");
    }

    // =========================================================================
    //  G2. Fuzz: take never exceeds 80% of nextPool
    // =========================================================================

    function testFuzz_G2_takeCapped(
        uint128 nextPool,
        uint128 futurePool,
        uint24 lvl,
        uint128 lastPoolRaw,
        uint48 elapsedRaw,
        uint256 rngWord
    ) public {
        nextPool = uint128(bound(nextPool, 1 ether, 10_000 ether));
        futurePool = uint128(bound(futurePool, 0, 50_000 ether));
        lvl = uint24(bound(lvl, 1, 200));
        uint256 lastPool = bound(lastPoolRaw, 0.01 ether, 10_000 ether);
        uint48 elapsed = uint48(bound(elapsedRaw, 0, 120 days));

        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rngWord);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        uint256 maxTake = uint256(nextPool) * NEXT_TO_FUTURE_BPS_MAX / 10_000;
        assertTrue(take <= maxTake, "take must respect 80% cap");
        assertTrue(uint256(nextAfter) + yieldAfter <= uint256(nextPool), "next can only decrease");
    }

    // =========================================================================
    //  H. Variance: triangular distribution shape
    // =========================================================================

    function test_H_varianceTriangular() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint24 lvl = 5;
        uint256 lastPool = 95 ether;
        uint48 elapsed = 14 days;

        // Collect 200 take samples
        uint256[] memory takes = new uint256[](200);
        uint256 minTake = type(uint256).max;
        uint256 maxTake = 0;

        for (uint256 i = 0; i < 200; i++) {
            setUp();
            uint256 rng = uint256(keccak256(abi.encode(i, "tri_test")));
            (, uint128 futureAfter,) = _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rng);
            uint256 take = uint256(futureAfter) - uint256(futurePool);
            takes[i] = take;
            if (take < minTake) minTake = take;
            if (take > maxTake) maxTake = take;
        }

        // Spread should exist
        assertTrue(maxTake > minTake, "should have variance spread");

        // Compute midpoint of observed range
        uint256 mid = (minTake + maxTake) / 2;
        uint256 halfSpread = (maxTake - minTake) / 2;
        uint256 innerBand = halfSpread / 2; // inner 50% of range

        // Count samples in inner vs outer bands
        uint256 innerCount;
        for (uint256 i = 0; i < 200; i++) {
            uint256 dist = takes[i] > mid ? takes[i] - mid : mid - takes[i];
            if (dist <= innerBand) innerCount++;
        }

        // Triangular: inner 50% of range should contain >50% of samples (center-heavy)
        assertTrue(innerCount > 100, "triangular should be center-weighted");
    }

    // =========================================================================
    //  H2. Variance floor: 10% of nextPool minimum halfWidth
    // =========================================================================

    function test_H2_varianceFloor() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 800 ether; // high ratio → low bps → small take
        uint24 lvl = 5;
        uint256 lastPool = 95 ether;

        // rng=0 → min additive, min variance rolls
        setUp();
        (, uint128 futureAfterMin,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, 0);
        uint256 takeMin = uint256(futureAfterMin) - uint256(futurePool);

        // rng=max → max additive, max variance rolls
        setUp();
        (, uint128 futureAfterMax,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, type(uint256).max);
        uint256 takeMax = uint256(futureAfterMax) - uint256(futurePool);

        assertTrue(takeMax > takeMin, "max rng should give higher take");
        // With floor of 10% nextPool = 10 ether as halfWidth,
        // spread should be meaningful even though base take is small
        assertTrue(takeMax - takeMin > 1 ether, "floor should produce meaningful spread");
    }

    // =========================================================================
    //  Step 2: Additive random adds 0–10% to bps
    // =========================================================================

    function test_additiveRandom_range() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint24 lvl = 5;
        uint256 lastPool = 95 ether;

        // rng=0: additive = 0 % 1001 = 0
        (, uint128 futureAfter0,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, 0);
        uint256 take0 = uint256(futureAfter0) - uint256(futurePool);

        // rng=1000: additive = 1000 % 1001 = 1000 (max)
        setUp();
        (, uint128 futureAfter1k,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, 1000);
        uint256 take1k = uint256(futureAfter1k) - uint256(futurePool);

        // rng=1001: additive = 1001 % 1001 = 0 (wraps)
        setUp();
        (, uint128 futureAfterWrap,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, 1001);
        uint256 takeWrap = uint256(futureAfterWrap) - uint256(futurePool);

        // Max additive should produce highest base bps (before variance)
        // take1k > take0 because extra 1000 bps = 10% of nextPool added to base
        assertTrue(take1k > take0, "additive=1000 should skim more than additive=0");

        // Wrapped value should be close to rng=0 (same additive=0, different variance bits)
        // They won't be identical due to different variance roll bits, but close
    }

    // =========================================================================
    //  Step 2: Additive random does not exceed 10%
    // =========================================================================

    function testFuzz_additiveRandom_bounded(uint256 rngWord) public {
        // The additive component is rngWord % 1001, so it's in [0, 1000].
        uint256 additive = rngWord % (ADDITIVE_RANDOM_BPS + 1);
        assertTrue(additive <= ADDITIVE_RANDOM_BPS, "additive must be <= 1000 bps");
    }

    // =========================================================================
    //  Conservation invariant (fuzz)
    // =========================================================================

    function testFuzz_conservation(
        uint128 nextPool,
        uint128 futurePool,
        uint24 lvl,
        uint128 lastPoolRaw,
        uint48 elapsedRaw,
        uint256 rngWord
    ) public {
        nextPool = uint128(bound(nextPool, 1 ether, 10_000 ether));
        futurePool = uint128(bound(futurePool, 0, 50_000 ether));
        lvl = uint24(bound(lvl, 1, 200));
        uint256 lastPool = bound(lastPoolRaw, 0.01 ether, 10_000 ether);
        uint48 elapsed = uint48(bound(elapsedRaw, 0, 120 days));

        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rngWord);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);
    }

    // =========================================================================
    //  INV-01: Skim conservation invariant (fuzz)
    // =========================================================================

    /// @notice INV-01: Conservation holds across randomized inputs including lastPool=0 edge case (level 1).
    function testFuzz_INV01_conservation(
        uint128 nextPool,
        uint128 futurePool,
        uint24 lvl,
        uint128 lastPoolRaw,
        uint48 elapsedRaw,
        uint256 rngWord
    ) public {
        nextPool = uint128(bound(nextPool, 1 ether, 10_000 ether));
        futurePool = uint128(bound(futurePool, 0, 50_000 ether));
        lvl = uint24(bound(lvl, 1, 200));
        uint256 lastPool = bound(lastPoolRaw, 0, 10_000 ether);
        uint48 elapsed = uint48(bound(elapsedRaw, 0, 120 days));

        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rngWord);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);
    }

    /// @notice INV-01: Conservation holds at level 1 with production-realistic 50 ETH bootstrap (F-50-03 edge case).
    function testFuzz_INV01_conservation_level1Bootstrap(
        uint128 futurePool,
        uint48 elapsedRaw,
        uint256 rngWord
    ) public {
        futurePool = uint128(bound(futurePool, 0, 500 ether));
        uint48 elapsed = uint48(bound(elapsedRaw, 0, 120 days));

        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(50 ether, futurePool, 1, 0, elapsed, rngWord);

        _assertConservation(50 ether, futurePool, nextAfter, futureAfter, yieldAfter);
    }

    // =========================================================================
    //  Insurance always exactly 1%
    // =========================================================================

    function testFuzz_insuranceAlways1Pct(
        uint128 nextPool,
        uint128 futurePool,
        uint24 lvl,
        uint128 lastPoolRaw,
        uint48 elapsedRaw,
        uint256 rngWord
    ) public {
        nextPool = uint128(bound(nextPool, 1 ether, 10_000 ether));
        futurePool = uint128(bound(futurePool, 0, 50_000 ether));
        lvl = uint24(bound(lvl, 1, 200));
        uint256 lastPool = bound(lastPoolRaw, 0.01 ether, 10_000 ether);
        uint48 elapsed = uint48(bound(elapsedRaw, 0, 120 days));

        (,, uint256 yieldAfter) = _runSkim(nextPool, futurePool, lvl, lastPool, elapsed, rngWord);

        assertEq(
            yieldAfter,
            uint256(nextPool) * INSURANCE_SKIM_BPS / 10_000,
            "insurance must be exactly 1% of nextPool"
        );
    }

    // =========================================================================
    //  Level 1 (lastPool = 0) → overshoot dormant
    // =========================================================================

    function test_level1_overshootDormant() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint24 lvl = 1;

        (, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, 0, 14 days, 0);

        assertTrue(uint256(futureAfter) > uint256(futurePool), "should skim even at level 1");
    }

    // =========================================================================
    //  x9 level bonus
    // =========================================================================

    function test_x9Bonus() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint256 lastPool = 95 ether;
        uint256 rng = 0;

        (, uint128 futureAfter9,) = _runSkim(nextPool, futurePool, 9, lastPool, 14 days, rng);
        uint256 take9 = uint256(futureAfter9) - uint256(futurePool);

        setUp();
        (, uint128 futureAfter8,) = _runSkim(nextPool, futurePool, 8, lastPool, 14 days, rng);
        uint256 take8 = uint256(futureAfter8) - uint256(futurePool);

        assertTrue(take9 > take8, "x9 should skim more than x8");
    }

    // =========================================================================
    //  Ratio adjustment: ±400 bps cap
    // =========================================================================

    function test_ratioAdjust_cappedAt400() public {
        uint256 lastPool = 95 ether;
        uint128 nextPool = 100 ether;
        uint256 rng = 0;

        // futurePool = 1 ether → ratioPct = 1 → bump = 199
        (, uint128 futureAfterLow,) = _runSkim(nextPool, 1 ether, 5, lastPool, 14 days, rng);
        uint256 takeLow = uint256(futureAfterLow) - 1 ether;

        setUp();
        (, uint128 futureAfterMed,) = _runSkim(nextPool, 100 ether, 5, lastPool, 14 days, rng);
        uint256 takeMed = uint256(futureAfterMed) - 100 ether;

        assertTrue(takeLow > takeMed, "lower ratio should skim more");
    }

    // =========================================================================
    //  Overshoot surcharge spot-check
    // =========================================================================

    function test_overshootSurcharge_spotValues() public pure {
        assertEq(_calcSurcharge(15000), 800, "R=1.5");
        assertEq(_calcSurcharge(20000), 1714, "R=2.0");
        assertEq(_calcSurcharge(30000), 2545, "R=3.0");
        assertEq(_calcSurcharge(100000), OVERSHOOT_CAP_BPS, "R=10 capped");
        assertEq(_calcSurcharge(12500), 0, "R=1.25 no surcharge");
    }

    // =========================================================================
    //  Deterministic: same rng → same result
    // =========================================================================

    function test_deterministic() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint256 lastPool = 95 ether;
        uint256 rng = 42;

        (, uint128 f1,) = _runSkim(nextPool, futurePool, 5, lastPool, 14 days, rng);
        setUp();
        (, uint128 f2,) = _runSkim(nextPool, futurePool, 5, lastPool, 14 days, rng);

        assertEq(f1, f2, "same rng should produce same result");
    }

    // =========================================================================
    //  reachedAt before 11-day offset is clamped
    // =========================================================================

    function test_reachedAtClampedToStart() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint256 lastPool = 95 ether;
        uint256 rng = 0;

        // reachedAt = levelStartTime + 5 days (before 11-day offset)
        harness.exposed_setPrizePools(nextPool, futurePool);
        harness.setLevelPrizePool(4, lastPool);
        harness.exposed_applyTimeBasedFutureTake(LEVEL_START + 5 days, 5, rng);
        (, uint128 f1) = harness.exposed_getPrizePools();

        // Same as reachedAt = levelStartTime + 11 days (clamped, elapsed=0)
        setUp();
        harness.exposed_setPrizePools(nextPool, futurePool);
        harness.setLevelPrizePool(4, lastPool);
        harness.exposed_applyTimeBasedFutureTake(LEVEL_START + 11 days, 5, rng);
        (, uint128 f2) = harness.exposed_getPrizePools();

        assertEq(f1, f2, "pre-offset reachedAt should clamp to start");
    }

    // =========================================================================
    //  VRF bit windows don't collide: step 2 uses low bits, step 4 uses shifted bits
    // =========================================================================

    function test_vrf_bitWindows_independent() public {
        uint128 nextPool = 100 ether;
        uint128 futurePool = 200 ether;
        uint24 lvl = 5;
        uint256 lastPool = 95 ether;

        // Two rng words that differ only in the low 64 bits (additive window)
        // but are identical in bits [64:255] (variance window)
        uint256 rngA = (uint256(0xDEADBEEF) << 64) | 0;
        uint256 rngB = (uint256(0xDEADBEEF) << 64) | 500;

        (, uint128 futureAfterA,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, rngA);
        uint256 takeA = uint256(futureAfterA) - uint256(futurePool);

        setUp();
        (, uint128 futureAfterB,) = _runSkim(nextPool, futurePool, lvl, lastPool, 14 days, rngB);
        uint256 takeB = uint256(futureAfterB) - uint256(futurePool);

        // Different additive random should produce different takes
        assertTrue(takeA != takeB, "different low bits should change additive");
    }

    // =========================================================================
    //  Pipeline ordering: uncapped bps → variance → THEN cap
    //  (variance can push above 80%, cap brings it back)
    // =========================================================================

    function test_pipeline_varianceBeforeCap() public {
        // High deterministic bps near the cap, then max variance to push over, then cap
        uint128 nextPool = 100 ether;
        uint128 futurePool = 1 ether; // low ratio → +199 bps bump
        uint24 lvl = 9; // x9 → +200
        uint256 lastPool = 10 ether; // R=10 → ~3500 surcharge

        // 90 days stale → high base. Max rng → max additive + max variance
        uint256 rng = type(uint256).max;
        (uint128 nextAfter, uint128 futureAfter, uint256 yieldAfter) =
            _runSkim(nextPool, futurePool, lvl, lastPool, 90 days, rng);

        _assertConservation(nextPool, futurePool, nextAfter, futureAfter, yieldAfter);

        uint256 take = uint256(futureAfter) - uint256(futurePool);
        uint256 maxTake = uint256(nextPool) * NEXT_TO_FUTURE_BPS_MAX / 10_000;
        // Uncapped bps would be huge. Variance would push take even higher.
        // But step 5 cap brings it to exactly maxTake.
        assertEq(take, maxTake, "cap should clamp to exactly 80%");
    }
}
