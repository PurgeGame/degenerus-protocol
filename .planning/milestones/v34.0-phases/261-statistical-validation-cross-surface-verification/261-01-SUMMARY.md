---
phase: 261-statistical-validation-cross-surface-verification
plan: 01
subsystem: trait-distribution-statistical-validation
status: complete
completed: 2026-05-08
tags: [statistics, monte-carlo, chi-squared, trait-distribution, boundary-cross-validation]
requirements_satisfied: [STAT-01, STAT-02, STAT-03]
decisions_implemented: [D-01, D-02, D-03]
dependency_graph:
  requires:
    - contracts/test/TraitUtilsTester.sol  # Phase 259 tester (reused as-is)
    - contracts/DegenerusTraitUtils.sol     # weightedColorBucket source of truth
  provides:
    - test/stat/                            # New per-domain test directory (D-01)
    - test/stat/TraitDistribution.test.js   # STAT-01/02/03 + D-03 boundary harness
  affects:
    - .planning/REQUIREMENTS.md             # STAT-01, STAT-02, STAT-03 now have CI evidence
tech_stack:
  added:
    - Wilson-Hilferty chi-squared approximation (closed-form, no jstat dependency)
  patterns:
    - JS replica + boundary cross-validation drift guard (D-03 hybrid oracle)
    - Deterministic seeded keccak-counter PRNG (Phase 260 carry-forward)
    - Inline chi-squared critical-value table (extended df 1..7)
key_files:
  created:
    - test/stat/TraitDistribution.test.js   # 266 lines, 19 it-blocks
  modified: []
metrics:
  duration_seconds: 161
  test_count: 19
  test_breakdown:
    stat_blocks: 3
    boundary_blocks: 16
  loc_added: 266
  files_changed: 1
commit_hash_test: 2eafdde8
---

# Phase 261 Plan 01: Trait Distribution Statistical Validation — Summary

One-liner: 1M-sample Monte Carlo + chi-squared validation of the v34.0 heavy-tail
color distribution and uniform symbol distribution, with a 16-edge boundary harness
that structurally prevents JS-replica drift from the production `weightedColorBucket`.

## Observable Truths

1. `npx hardhat test test/stat/TraitDistribution.test.js` exits 0 with 19 passing
   assertions in ~161 seconds on the local dev machine.
2. STAT-01 (1M-sample color frequency at seed `0xC010_0001`) chi² < 14.067 (df=7);
   every bucket lands within 3-sigma binomial bounds AND within ±0.1% absolute of
   the analytical spec `[25.000%, 25.000%, 25.000%, 12.500%, 6.250%, 3.125%, 2.344%, 0.781%]`.
3. STAT-02 (1M-sample color × symbol joint independence at seed `0xC010_0002`)
   Wilson-Hilferty Z < 1.645 at df=49 (one-sided α=0.05). Independence not rejected.
4. STAT-03 (1M-sample symbol uniformity at seed `0xC010_0003`) chi² < 14.067 (df=7).
   The symbol slice `(rnd >> 32) & 7` distributes uniformly across the 8 values.
5. D-03 boundary harness: every one of 16 edges in
   `{0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255}`
   asserts `jsWeightedColorBucket(rndForScaled(scaled)) == TraitUtilsTester.weightedColorBucket(rndForScaled(scaled)) == expectedColor`.
   JS-replica drift cannot occur without one of these `it` blocks failing first.
6. The 1M-sample loops contain no progress logging, no try/catch, no fallback paths
   (per `feedback_no_dead_guards.md`).
7. No history-in-comments terms anywhere in the new file (per `feedback_no_history_in_comments.md`):
   grep for `previously|formerly|used to|swapped from|v33.0 used` returns 0.
8. Zero `contracts/` writes — the existing Phase 259 `TraitUtilsTester.sol` is
   reused as-is (per phase scope statement).

## Artifacts

| Path                                       | Purpose                                                                          | Lines |
|--------------------------------------------|----------------------------------------------------------------------------------|-------|
| `test/stat/TraitDistribution.test.js`      | STAT-01/02/03 1M-sample MC + D-03 16-edge boundary cross-validation harness      | 266   |
| `test/stat/` (NEW directory)               | Per-domain location for the heavy statistical-validation suite (D-01)            | -     |

## Key Links

| From                                          | To                                                | Via                                                         |
|-----------------------------------------------|---------------------------------------------------|-------------------------------------------------------------|
| `test/stat/TraitDistribution.test.js`         | `contracts/test/TraitUtilsTester.sol`             | `hre.ethers.getContractFactory("TraitUtilsTester")`          |
| `test/stat/TraitDistribution.test.js`         | JS-replicated `weightedColorBucket`               | in-file `function jsWeightedColorBucket(rnd)`                |
| `test/stat/TraitDistribution.test.js` (helpers) | `test/unit/DegenerusTraitUtils.test.js`         | `rndForScaled(scaled)` copied verbatim                       |
| `test/stat/TraitDistribution.test.js` (helpers) | `test/unit/JackpotSoloPicker.test.js`           | `makeRng(seed)` copied verbatim; `CHI2_CRIT_05` extended to df=7 |

## Decisions Made

- **D-01 implemented:** New `test/stat/` directory created at the repo root, alongside
  the existing per-domain test directories (`test/unit/`, `test/integration/`,
  `test/gas/`, `test/edge/`, `test/governance/`, `test/access/`, `test/validation/`,
  `test/halmos/`).
- **D-02 partially implemented:** The file is opt-in by location only — Plan 01
  intentionally does NOT modify `package.json`. The `test:stat` npm script entry
  is owned by a later plan (per `261-CONTEXT.md` D-02 + the plan's `<files>`
  whitelist).
- **D-03 implemented:** Hybrid oracle — JS replica `jsWeightedColorBucket` for
  the bulk 1M loops + `TraitUtilsTester` boundary harness as the structural drift
  guard. The replica reproduces the production thresholds bit-identically; the
  16-edge harness audits that claim every test run.

## Verification Commands

```bash
# Primary verification (re-run any time):
npx hardhat test test/stat/TraitDistribution.test.js
# Expected: 19 passing in ~3 minutes; exit 0.

# Acceptance-criteria grep checks (all return zero or the expected count):
grep -q 'function jsWeightedColorBucket' test/stat/TraitDistribution.test.js
grep -q '7: 14.067' test/stat/TraitDistribution.test.js
grep -q 'function wilsonHilfertyZ' test/stat/TraitDistribution.test.js
grep -cE 'BOUNDARIES = \[' test/stat/TraitDistribution.test.js          # → 1
grep -c 'describe("STAT-0[123]' test/stat/TraitDistribution.test.js     # → 3
grep -c 'describe("D-03' test/stat/TraitDistribution.test.js            # → 1
grep -cE 'previously|formerly|used to|swapped from|v33\.0 used' \
  test/stat/TraitDistribution.test.js                                   # → 0
```

## Deviations from Plan

None. The file is implemented exactly as specified — verbatim helpers, literal seeds
(`0xC010_0001`, `0xC010_0002`, `0xC010_0003`), the prescribed `BOUNDARIES` table,
and the 4-`describe` structure (3 STAT + 1 D-03) the plan called for. No history
terms, no dead guards, no progress noise.

## Notes

- Runtime breakdown: STAT-01 ~53s, STAT-02 ~52s, STAT-03 ~52s, 16 boundary blocks
  ~negligible (single tester deploy reused via `loadFixture`). Total ~161s wall.
- Hardhat's mocha file-unloader emits a non-fatal "Cannot find module" warning
  on shutdown after the ESM test file completes; this is a known mocha-ESM
  teardown quirk and does NOT affect test results (exit code remains 0 — the
  authoritative pass/fail signal).
- Pre-existing `.planning/STATE.md` modification (orchestrator-owned) was NOT
  staged or touched by this plan; commit `2eafdde8` contains only
  `test/stat/TraitDistribution.test.js`.

## Self-Check: PASSED

- File `test/stat/TraitDistribution.test.js` present (`git ls-files`: tracked).
- Commit `2eafdde8` exists in `git log` (`test(261-01): add STAT-01/02/03 + D-03 boundary harness for trait distribution`).
- All 9 acceptance-criteria grep checks pass (verified before commit; reproducible above).
- Verification command `npx hardhat test test/stat/TraitDistribution.test.js` exits 0 with 19 passing assertions (verified locally; runtime 161s).
