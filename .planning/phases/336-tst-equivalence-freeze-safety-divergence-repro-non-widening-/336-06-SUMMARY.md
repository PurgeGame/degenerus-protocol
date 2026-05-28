---
phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
plan: 06
subsystem: testing

tags:
  - non-widening-regression
  - regression-baseline
  - subset-gate
  - unseeded-invariant-flakiness
  - tst-04
  - user-gated
  - v50.0

# Dependency graph
requires:
  - phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
    provides: |
      The FROZEN v50.0 audit subject — BATCH-02 commit `e756a6f3` (5 contracts +
      8 tests, WHALE-01..03 + AFSUB-01..05 + MINTDIV-02). 335-LOCAL-VERIFICATION
      supplied the IMPL-HEAD baseline (666/42/17) + the v49→v50 §2 deltas
      (B9 OUT, B10 OUT, B14 + B15 IN).
  - plan: 336-01..05
    provides: |
      The 6 new green proof functions (claim freeze-fuzz, claim equivalence,
      uniform-O(1) gas, no-pass-SLOAD oracle, MINTDIV deterministic + boundary
      fuzz) that land in §5 of the v50 ledger as net contributors to the passed
      count.
provides:
  - |
    `test/REGRESSION-BASELINE-v50.md` — the authoritative v50.0 NON-WIDENING
    regression gate ledger (301 lines). The binding gate is the non-widening
    SUBSET direction `live failing set − the 42-name §2 union == ∅` (no red
    outside the known baseline), the load-bearing property Phase 338 TERMINAL
    consumes.
  - |
    The empirical TST-HEAD baseline: 674 passed / 40 failed / 17 skipped, with
    `live − union == ∅` verified both-directions via `forge test --json` parse.
affects:
  - 338-terminal (the v50.0 delta-audit + closure re-attests TST-04 against this ledger)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - |
      "Non-widening SUBSET gate for unseeded invariant families" — when an
      invariant cluster is non-deterministic (no `[invariant] seed` in
      foundry.toml), the regression gate is `live − union == ∅` (no new red),
      NOT strict `live == union`. The full cluster membership is kept in the
      union as a ceiling; the `union − live` slack is documented as flaky-cluster
      variance, never asserted away. Generalizes the v49 strict-equality ledger
      to flaky-invariant suites.
    - |
      "forge test --json set-equality parse" — build the live
      `(suite-basename, testName)` failing set with jq and `comm` it against the
      enumerated union both directions; `live − union` is the binding STOP
      trigger, `union − live` is the documented narrowing.

key-files:
  created:
    - test/REGRESSION-BASELINE-v50.md
  modified: []

key-decisions:
  - |
    ⊆ gate over strict equality (USER-approved at the D-CC-03 hand-review gate):
    the live run was 674/40/17, not the plan-anticipated 672/42/17, because the
    UNSEEDED `DegeneretteBet.inv` invariant cluster (B12 + B14 + B15) caught only
    1 of its 3-member counterexample family this run (v49:1, 335-IMPL:3, TST:1).
    Strict equality is the wrong gate for a non-deterministic family; the binding
    invariant is the non-widening subset direction `live − union == ∅`. USER chose
    this over (a) seeding `[invariant]` + re-running and (b) cherry-picking a
    re-run that hits 42 (rejected as a passing-ledger-over-reality anti-pattern).
  - |
    foundry.toml left UNCHANGED (no `[invariant] seed` added). The cluster
    non-determinism is DOCUMENTED in ledger §4 (with the frozen-contract +
    frozen-test-file proof that the 2 greens are fuzz variance, not a v50 fix);
    seeding `[invariant]` for reproducibility is recorded as a candidate
    test-infra follow-up, OUT of the 336-06 markdown-only scope.

patterns-established:
  - |
    "Document-the-flake, gate-on-no-new-red": an audit-grade pattern for
    non-deterministic invariant suites — record the full union as a ceiling,
    prove the subset direction empirically, and prove (frozen subject + frozen
    test file ⇒ variance, not fix) rather than hide the narrowing.

requirements-completed:
  - TST-04

# Metrics
duration: 40min
completed: 2026-05-28
---

# Phase 336 Plan 06: TST-04 v50.0 NON-WIDENING baseline ledger Summary

**Authored `test/REGRESSION-BASELINE-v50.md` — the v50.0 NON-WIDENING regression gate. The full-suite `forge test` ran 674 passed / 40 failed / 17 skipped; the binding gate `live failing set − the 42-name §2 union == ∅` HOLDS (zero new regression). 40 of 42 union names were red this run; the 2 not red (`invariant_solvencyUnderDegenerette`, `invariant_ghostAccountingNetPositive`) are both in the UNSEEDED `DegeneretteBet.inv` cluster that flakes 0–3 reds/run — so the v49-precedent strict equality is relaxed to the non-widening ⊆ gate per USER hand-review (D-CC-03).**

## Performance

- **Duration:** ~40 min (incl. the full-suite `forge test --json` run + the set-equality parse)
- **Completed:** 2026-05-28
- **Tasks:** 2 (Task 1 USER gate + Task 2 author ledger)
- **Files created:** 1 (NEW markdown ledger; zero `.sol`)

## Accomplishments

- Full whole-tree `forge test --json` at the TST HEAD → **674 passed / 40 failed / 17 skipped** (731 run).
- Built the live `(suite-basename, testName)` failing set and `comm`-diffed it against the pre-derived 42-name v50 union both directions:
  - **`live − union == ∅`** — zero failing test outside the baseline. **The load-bearing NON-WIDENING property HOLDS.**
  - **`union − live == { invariant_solvencyUnderDegenerette, invariant_ghostAccountingNetPositive }`** — exactly the 2 unseeded-invariant flaky-greens.
- Authored `test/REGRESSION-BASELINE-v50.md` (301 lines) mirroring the v49 §1/§2/§6/§7 structure with v50 substitutions + a NEW §4 documenting the unseeded `DegeneretteBet.inv` cluster non-determinism.
- §2 fully re-enumerates the 42-name union (Bucket A 8 + Bucket B 34 + Bucket C 0) with B9 + B10 struck OUT and NEW B14 + B15 IN, plus a per-row this-run observed-status column.
- Delta math `42 − 2 + 2 = 42` (Pitfall 4) + the 6-arg `TraitsGenerated` absence (Pitfall 3) both present.
- Zero `contracts/*.sol` mutation (D-TST04-04): `git diff e756a6f3 HEAD -- contracts/` EMPTY.

## The empirical finding (why the binding headline is ⊆, not strict ==)

The plan anticipated a strict `live == 42 union` headline (the v49 precedent). The live run instead produced 674/40/17. Root cause (proven in ledger §4):

- `foundry.toml` seeds `[fuzz]` (`seed = "0xdeadbeef"`) — unit-fuzz proofs are deterministic — but the `[invariant]` block has **NO seed** (runs=256, depth=128). Invariant campaigns are non-deterministic run-to-run.
- `DegeneretteBet.inv.t.sol` is byte-frozen since `e756a6f3`, the contracts are frozen, and 336 touched no invariant suite — yet the cluster's red-subset varies (v49:1, 335-IMPL:3, TST:1). Identical inputs + different result = non-determinism, NOT a regression and NOT a fix.
- Arithmetic reconciles exactly: 666→674 passed = +6 new green (336) + 2 flaky-flip (B12, B15); 42→40 failed = −2 flaky-flip.

USER adjudicated at the D-CC-03 gate: baseline the full 42-name union as a ceiling, gate on the subset direction (`live − union == ∅`), document the cluster, leave foundry.toml unchanged.

## Files Created/Modified

- `test/REGRESSION-BASELINE-v50.md` (NEW; 301 lines) — §1 arithmetic (674/40/17 reconciliation); §2 the 42-name union ceiling with per-row this-run status; §3 the v50 deltas vs v49 §2 (B9/B10 OUT, B14/B15 IN, with provenance + `42 − 2 + 2 = 42`); §4 the unseeded `DegeneretteBet.inv` cluster non-determinism analysis (the ⊆-gate rationale + cross-run table); §5 the 6 new green proof functions; §6 the `live − union == ∅` proof + FC1-FC5 false-confidence guards; §7 scope attestation.

## Deviations from Plan

### Decision deviations (USER-approved at the D-CC-03 gate)

**1. Binding gate is ⊆ (`live − union == ∅`), NOT strict equality (`live == union`)**

- **Found during:** Task 2 (the full-suite run produced 40 failed, not the anticipated 42)
- **Issue:** The plan's binding headline + several acceptance criteria assumed a stable 42-name failing set matching the v49-precedent strict equality. The live run was 40/42 because the unseeded `DegeneretteBet.inv` cluster caught 1 (not 3) of its counterexample family.
- **Resolution:** Surfaced the empirical result + the proven flakiness root-cause at the D-CC-03 USER gate. USER selected "document the flaky family, ⊆ gate" over seeding `[invariant]` or cherry-picking a 42-run. The ledger uses the non-widening subset gate; the strict-equality phrase appears only in the context of explaining the relaxation.
- **Impact:** The load-bearing regression-detection property is UNCHANGED (a new red still surfaces in `live − union` and trips STOP). The relaxation only documents the flaky-cluster's `union − live` slack rather than asserting it.

**2. §1 reads 674/40/17, not the plan's anticipated 672/42/17**

- The −2 on the failing side and +2 on the passing side are exactly the 2 flaky-cluster greens (B12, B15), not a regression. Fully reconciled in §1.

**3. foundry.toml left UNCHANGED**

- The candidate fix (add `[invariant] seed`) was considered and recorded as an out-of-scope test-infra follow-up; not applied this phase (markdown-only scope).

**Total deviations:** 3, all flowing from the single USER-approved baseline-methodology decision. No scope creep; all locked constraints (D-TST04-01 full re-enumeration, D-TST04-04 zero contracts, D-CC-01..04) honored.

## Self-Check Verification (acceptance criteria from PLAN.md, adapted for the ⊆ gate)

```
test -f test/REGRESSION-BASELINE-v50.md                                    : OK (301 lines, >= 200)
forge test (WHOLE tree, --json)                                            : 674 passed / 40 failed / 17 skipped
live − union (jq + comm)                                                   : ∅  (no new red — binding gate HOLDS)
union − live                                                               : {invariant_solvencyUnderDegenerette, invariant_ghostAccountingNetPositive} (flaky cluster, documented §4)
git diff e756a6f3 HEAD -- contracts/                                       : empty (zero contracts mutation, D-TST04-04)

grep -c "BY NAME"                                                          : 6  (>= 3, PASS)
grep -c "invariant_noEthCreation"                                          : 6  (>= 1, PASS — NEW B14)
grep -c "invariant_ghostAccountingNetPositive"                             : 7  (>= 1, PASS — NEW B15)
grep -c "testRenewalExactlyAtCostFullBurn"                                 : 3  (>= 1, PASS — B9 OUT in §3)
grep -c "testFundingSourceVaultDoesNotInheritExemption"                    : 3  (>= 1, PASS — B10 OUT in §3)
grep -c "42 − 2 + 2 = 42"                                                  : 3  (>= 1, PASS — Pitfall 4)
grep -c "e756a6f3"                                                         : 15 (>= 1, PASS — frozen subject SHA)
grep -c "TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)"     : 0  (== 0, PASS — Pitfall 3 wrong-sig absence)
grep -c "live failing set == the 42 v50.0 §2 enumerated union"             : 2  (>= 1, PASS — present in the relaxation context)
```

## Next Phase Readiness

- **Phase 336 TST is COMPLETE** — all 6 plans (336-01..06) executed + committed. TST-01 (freeze + equivalence + uniform-O(1)), TST-02 (no-SLOAD oracle), TST-03 (MINTDIV cross-path), TST-04 (NON-WIDENING ⊆ baseline) all closed.
- The v50.0 clean regression baseline is recorded; **Phase 338 TERMINAL** can re-attest its delta-audit against this ledger (the ⊆ gate + the documented `DegeneretteBet.inv` cluster non-determinism carry forward as a known property).
- **Next: Phase 337 AUDIT-PROTOCOL** (author the model-agnostic multi-round external-LLM RNG-audit kit against the frozen post-v50 tree — package-only, zero contracts).
- Candidate test-infra follow-up (NOT a blocker): add `seed` to foundry.toml `[invariant]` for reproducible invariant campaigns.

---
*Phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-*
*Plan: 06*
*Completed: 2026-05-28*
