# Phase 261: Statistical Validation + Cross-Surface Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 261-statistical-validation-cross-surface-verification
**Areas discussed:** STAT-06 EV-uplift simulation modeling

---

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Test directory layout + CI integration | test/stat/ separate dir w/ opt-in npm script vs interleave in test/unit/ + test/gas/ | |
| Sample generation oracle (on-chain vs JS replica) | 1M tester calls (slow, byte-true) vs JS replica (fast, trust gap) vs hybrid | |
| Cross-surface preservation method (SURF-01..04) | Behavioral vs structural vs hybrid | |
| EV uplift simulation modeling (STAT-06) | Owns-the-gold-quadrant-ticket vs synthetic player population vs closed-form | ✓ |

**User's choice:** Discuss STAT-06 only. The other 3 areas: defaults applied per CONTEXT.md (D-01/D-02 separate test/stat/ dir + opt-in npm script; D-03 hybrid oracle with boundary cross-validation; D-09 mostly-structural SURF preservation with targeted behavioral spot-checks). Gas regression baseline strategy (SURF-05) carried forward from `feedback_gas_worst_case.md` memory — theoretical worst case derived FIRST, then HEAD-only measured (D-11).

**Notes:** Phase is well-specified at the requirement level (STAT-01..07 + SURF-01..05 fully enumerated in REQUIREMENTS.md). Per `feedback_skip_research_test_phases.md`, this is a mechanical test phase — most methodology choices have natural defaults derived from Phase 259 / Phase 260 precedent. STAT-06 is the one place where the spec wording ("~3.3× uplift", "realistic player-trait distributions") was loose enough to need explicit interpretation.

---

## STAT-06 — Gold-trait holder model

| Option | Description | Selected |
|--------|-------------|----------|
| Owns the gold-quadrant ticket (single perspective) | For each MC draw with ≥1 gold winning trait, the gold-trait holder is whoever holds the trait at the gold-color winning quadrant. Compute their bucket payout under uniform-rotation baseline vs gold-priority. Closed-form expectation ~4× conditional, ~3.3× averaged with goldCount distribution. | ✓ |
| Aggregate over a synthetic player population | Model N players holding random trait portfolios; simulate jackpot draws; compute aggregate ETH-share each player receives; report population-wide uplift for gold-holders. Introduces holding-distribution assumptions. | |
| Closed-form analytical, MC just confirms | Derive 3.3× analytically from share BPS + bucket counts + gold-priority rule + gold-color probability. 100K MC validates analytical formula matches simulated outcome within MC tolerance. | |

**User's choice:** Owns-the-gold-quadrant-ticket (Recommended). Cleanest reading of "solo-bucket EV uplift" — measures what a holder of a gold-color winning trait gains from the priority rule.

**Notes:** No additional notes from user. Recorded as D-07 in CONTEXT.md.

---

## STAT-06 — Surface coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Per-surface assertion (3 separate sims) | Run 100K each for final-day / daily / purchase; assert each surface's measured uplift matches its analytical expectation ± tolerance. Cleanest evidence — regression in any one surface is pinpointed. | ✓ |
| Single combined sim across all 3 surfaces | 100K random-trait draws cycling round-robin across the 3 surfaces; assert overall mean uplift ≈ 3.3× ± tolerance. Closer to spec wording but masks per-surface drift. | |
| Final-day only (highest-stake surface) | Simulate just runTerminalJackpot; assert ~3.78× ± tolerance over 100K draws. Daily / purchase get analytical-only checks. Tightest test, less coverage. | |

**User's choice:** Per-surface assertion (Recommended). Per-surface uplifts: final-day ~3.78×, daily ~3.21×, purchase ~3.21× (single-gold) — captured in CONTEXT.md D-04 + Specific Ideas section. REQUIREMENTS.md STAT-06 amendment under D-08.

**Notes:** Bucket-count differential (base [25, 15, 8, 1]) is the dominant uplift driver in the daily / purchase surfaces; BPS gradient adds the additional uplift in final-day. Per-surface assertion catches drift in either driver.

---

## STAT-06 — Pool-size assumption

| Option | Description | Selected |
|--------|-------------|----------|
| Base counts [25, 15, 8, 1] (low-pool, no scaling) | All 3 surface sims set ethPool below JACKPOT_SCALE_MIN_WEI so traitBucketCounts returns base unchanged. Cleanest test — no pool-scaling confound. | ✓ |
| Sweep pool sizes (3 reference points each) | 3 representative pool sizes per surface (5 / 50 / 200 ETH) to capture pre-scale, mid-scale, max-scale regimes. ~3× runtime. | |
| Per-surface realistic pool (typical caller pool) | One realistic pool size per surface based on production deployment context. | |

**User's choice:** Base counts (Recommended). Anchors STAT-06 to the canonical analytical reference. Pool-scaling regimes deferred (see Deferred Ideas in CONTEXT.md).

**Notes:** PROJECT.md mention of `[20, 12, 6, 1]` for purchase-phase counts is a post-cap approximation at moderate pool — the contract-pinned base is `[25, 15, 8, 1]` for all three surfaces. Anchoring at base avoids the pool-scaling moving target.

---

## Claude's Discretion

- Test-file consolidation within `test/stat/` (one file per success-criterion family vs single mega-file). Default: per-family file; planner may consolidate.
- Exact JS chi² critical-value table extension to df 1..7.
- Seeded keccak PRNG seed values per test (reproducibility = exact-replay on failure).
- Reverse-mapping helper `rndForScaled(scaled)` extracted to `test/helpers/` or kept inline.
- Hardhat fixture composition for SURF-01 hero-override spot-check.
- Whether SURF-04 grep proof is a Hardhat JS test or shell script invoked via npm `prestat` hook.

## Deferred Ideas

- Mid-pool / max-cap regime EV-uplift simulation (STAT-06 extension).
- Foundry fuzz alternative for STAT-01..03.
- Live A/B gas-comparison harness for SURF-05 (resurrect v33.0 binary + dual-deploy fixture).
- Run-N-take-majority statistical false-positive mitigation (deterministic seeds make this moot for green CI).
- Deeper deity-pass token-economy verification (SURF-02 extension).
- Phase 262 work: delta audit, findings consolidation (`audit/FINDINGS-v34.0.md`), REG-01..04 KI envelope re-verification.
