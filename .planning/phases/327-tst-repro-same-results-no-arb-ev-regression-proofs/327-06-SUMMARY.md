---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
plan: 06
subsystem: testing
tags: [regression-gate, forge, full-suite, net-zero, hero-byte-reproduce, conditional-delta, v48-baseline]

# Dependency graph
requires:
  - phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
    provides: "All five wave-1 test files committed (327-01 PresaleBoxDrain, 327-02 RedemptionStethFallback+RedemptionAccounting+RedemptionHandler, 327-03 BurnieTombstone, 327-04 DegeneretteHeroScore+stat-gate, 327-05 FarFutureSalvageSwap)"
  - phase: 326-impl-the-one-batched-contract-diff-all-7-items
    provides: "The 594/42 baseline (326-08-SUMMARY) the net-zero-new-regression arithmetic is computed against"
provides:
  - "test/REGRESSION-BASELINE-v48.md — the named expected-red enumeration + the exact 326-08 arithmetic + the conditional post-landing HERO delta (the clean-v48.0-baseline gate ledger)"
  - "Proof: net new regression from the 5 wave-1 test files == 0 (full forge tree 632 passed / 42 failed vs 594/42 + 38 NEW_PASSING; every red named in the baseline+HERO-deferred union; all 18 failing suites predate wave-1)"
  - "HERO byte-reproduce gate recorded as EXPECTED-RED (Hardhat-only, 15/20 placeholders diverge) with a numerically-documented conditional post-landing delta — not forced green, no contract edit applied"
affects: [328-terminal-delta-audit, FINDINGS-v48, v48-closure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Net-zero-new-regression proof by NAME-SET subset + last-touching-commit membership (not a bare failure count): every red is enumerated by name and every failing suite is shown last-touched at/before the Phase-326 contract diff f50cc634, NOT by any wave-1 commit"
    - "Runner separation: the FOUNDRY HERO-deferred set is re-grepped by name (= 0, DegeneretteHeroScore.t.sol is GREEN) while the HARDHAT byte-reproduce gate is isolated as the single HERO-deferred red"
    - "Conditional documented delta (not executed): the post-landing forge/stat-gate deltas are stated numerically without applying the out-of-phase constant-only contract diff"

key-files:
  created:
    - "test/REGRESSION-BASELINE-v48.md"
  modified: []

key-decisions:
  - "Net-zero proven via the red NAME SET being a strict subset of the enumerated union (T-327-06-FC1) PLUS a last-touching-commit table showing all 18 failing suites predate wave-1 — the 5 new wave-1 files contributed only PASSING tests (38 NEW_PASSING)"
  - "FOUNDRY-side HERO-deferred count = 0: DegeneretteHeroScore.t.sol asserts scoring SHAPE/dispatch (reads FullTicketResult.matches), so it is GREEN regardless of placeholder VALUES; the QUICK_PLAY/_countMatches hits in other Foundry files are local test-helper constants, not contract-constant assertions (T-327-06-FC2)"
  - "HERO byte-reproduce RED lives ENTIRELY in the Hardhat stat tree (1 red: PASS_ALL 15/20 diverge); therefore the forge failure count does NOT drop on the constant landing (HERO forge count = 0) — only the Hardhat stat gate flips 1-failing -> 0-failing"
  - "DegeneretteFreezeResolution::testDgnrsAwardStaysPerSpin (DGAS-04 per-spin, last touched at the 323 commit b9451eb0) is a stale v48-behavioral baseline red (bucket B13), part of the 42-baseline, NOT a wave-1 regression"

patterns-established:
  - "v48.0 clean-regression-baseline gate shape: full-tree run + named-red enumeration in 3 buckets (VRF/RNG, stale-harness/v48-behavioral, HERO-deferred) + last-touching-commit membership proof + a conditional HERO post-landing delta"

requirements-completed: []

# Metrics
duration: ~10min
completed: 2026-05-26
---

# Phase 327 Plan 06: v48.0 Clean Regression Baseline Gate Summary

**The full `forge test` tree (NOT --match-path) runs at 632 passed / 42 failed (674 total) against the frozen Phase-326 diff; reconciled exactly to the 326-08 594/42 baseline + 38 NEW_PASSING from the five wave-1 test files; net new regression from those files == 0 (every red named in the VRF/RNG + stale-harness + HERO-deferred union, and all 18 failing suites are last-touched at/before f50cc634 — none by a wave-1 commit); and the HERO byte-reproduce gate is recorded as the EXPECTED-RED Hardhat-only conditional closure path with a numerically-documented post-landing delta — without forcing it green and without applying any contracts/*.sol edit.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-26T09:46:39Z
- **Completed:** 2026-05-26T09:57:09Z
- **Tasks:** 2 (both autonomous; both author the single ledger artifact `test/REGRESSION-BASELINE-v48.md`)
- **Files modified:** 1 (created)

## Accomplishments

### Task 1 — Full-tree run + named expected-red enumeration + net-zero assertion (commit `208859e8`)

- **Ran the FULL `forge test` tree (NOT `--match-path`)**: **632 passed / 42 failed** of 674.
- **NEW_PASSING reconciliation:** `632 == 594 + 38`; `42 == 42 + 0 net-new`. The 38 NEW_PASSING are
  exactly the five wave-1 plans' contributions, all PASSING: PresaleBoxDrain 3 + RedemptionStethFallback 10 +
  RedemptionAccounting invariant extension +2 + BurnieTombstone 8 + DegeneretteHeroScore 6 + FarFutureSalvageSwap 9
  = 38. Each wave-1 file confirmed GREEN in the whole-tree run (3 / 10 / 8 / 6 / 9; redemption invariant 18).
- **Enumerated the expected-red union BY NAME** (false-confidence guard, never a bare count) into
  `test/REGRESSION-BASELINE-v48.md`, in three named buckets, every red landing in exactly one:
  - **Bucket A — VRF/RNG baseline (8):** the 3 `VRFPathInvariants` reds (gap-day/coordinator-swap/stall-recovery)
    + VRFCore + VRFLifecycle + VRFPathCoverage + RngLockDeterminism + RngIndexDrainBinding.
  - **Bucket B — stale-harness / v48-behavioral baseline (34):** TicketRouting 12, QueueDoubleBuffer 9,
    TicketEdgeCases 2, PrizePoolFreeze 2, TicketLifecycle 1, GameOverPathIsolation 1, LootboxBoonCoexistence 2,
    AfKingSubscription 1, AfKingFundingWaterfall 1, CoverageGap222 1, DegeneretteBet.inv 1,
    DegeneretteFreezeResolution (DGAS-04 per-spin) 1.
  - **Bucket C — FOUNDRY HERO-deferred (0):** re-grepped for placeholder-sensitive payout-magnitude assertions;
    the only Foundry HERO file (DegeneretteHeroScore.t.sol) is GREEN.
  - A(8) + B(34) + C(0) = **42** ✓ (per-suite re-count also = 42).
- **Net-zero PROOF:** a last-touching-commit table shows **all 18 failing suites were last touched at/before the
  Phase-326 contract diff `f50cc634` (or earlier: 323/211/210/03 commits) — NONE by a 327-01..05 wave-1 commit.**
  The actual red NAME set is a strict subset of the enumerated union. **No `## STOP — NEW REGRESSION OUTSIDE
  BASELINE` block** — net new regression from the 5 wave-1 test files == 0.

### Task 2 — HERO byte-reproduce gate recorded as the expected-red conditional closure path (commit `208859e8`)

- **Ran the Hardhat HERO byte-reproduce gate** (`npx hardhat test test/stat/DegenerettePerNEvExactness.test.js
  test/stat/DegeneretteBonusEv.test.js`) and captured its CURRENT (pre-landing, expected-RED) state:
  **15 passing / 1 failing**, the 1 failure being `HERO-04 PASS_ALL: 15/20 constants diverge from the canonical
  generator` (`:246`). All EV/relabel checks GREEN (per-N basePayoutEV 100 ± 0.5 centi-x; ETH bonus EV ≈ 5.000%,
  rel-err < 0.001%; S9 == old M=8 relabel; WWXRP B=6..9). Confirmed 327-04's `## STOP` handoff + ready-to-apply
  finals. The trailing `Cannot find module` line is the known cosmetic Hardhat+mocha teardown quirk (fires after
  the verdict).
- **Documented the CONDITIONAL post-landing delta numerically (not executed):** once the single hand-reviewed,
  `CONTRACTS_COMMIT_APPROVED=1`-gated, constant-ONLY diff lands the 15 finals into
  `DegenerusGameDegeneretteModule.sol` (OUT OF THIS no-contract phase), re-running this sweep MUST show — with NO
  other delta — the Hardhat stat gate flip from 1-failing → **0-failing** (PASS_ALL 0-diff GREEN), while the forge
  failure count stays **42** (the byte-reproduce red is Hardhat-only; FOUNDRY HERO-deferred count = 0). Recorded
  HERO count = **1** (Hardhat) + **0** (Foundry) = **1**, living entirely in the Hardhat stat tree.
- **Explicit non-action:** no `contracts/*.sol` edit applied, required, or staged; the RED HERO gate is the
  expected in-scope outcome of the no-contract phase. The satisfied acceptance is the documented conditional
  delta, not a green HERO gate.

## Net-Zero-New-Regression Arithmetic

| Quantity | 326-08 baseline | Wave-1 delta | This run |
|----------|-----------------|--------------|----------|
| `forge test` passed | 594 | + 38 NEW_PASSING | **632** |
| `forge test` failed | 42 | + 0 net-new | **42** |
| total | 636 | + 38 | 674 |

## Recorded HERO count + conditional post-landing delta

| Runner | Pre-landing (this run) | Post-landing (expected) | HERO delta |
|--------|------------------------|-------------------------|------------|
| Hardhat stat gate | 15 passing / 1 failing (PASS_ALL RED, 15/20 diverge) | 16 passing / 0 failing (PASS_ALL 0-diff GREEN) | 1 → 0 (flips) |
| `forge test` whole tree | 632 passed / 42 failed | 632 passed / 42 failed | 0 (forge HERO count = 0) |

## False-Confidence Guards (threat register dispositions)

- **T-327-06-FC1** (loose count masks a regression): mitigated — red NAME SET asserted a strict subset of the
  enumerated union, not a count.
- **T-327-06-FC2** (HERO conflated with a real regression): mitigated — FOUNDRY HERO-deferred reds grepped by
  name (= 0), Hardhat HERO gate isolated; every red in exactly one named bucket.
- **T-327-06-FC3** (gate "passes" by forcing HERO green / applying the contract edit): mitigated — recorded the
  expected-RED state + the conditional documented delta; no contract edit applied.
- **T-327-06-FC4** (full tree never run, only `--match-path`): mitigated — `forge test` ran on the WHOLE tree and
  reconciled to 594/42 + 38 NEW_PASSING.

## Task Commits

Both tasks author the single ledger artifact `test/REGRESSION-BASELINE-v48.md` (Task 2 appends §3 to the file
Task 1 created), committed atomically:

1. **Task 1 (full-tree run + named-red union + net-zero) + Task 2 (HERO conditional delta)** — `208859e8` (test)

Plan metadata (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified

- `test/REGRESSION-BASELINE-v48.md` — the v48.0 clean-baseline gate ledger: the 326-08 arithmetic + NEW_PASSING
  reconciliation (§1), the named expected-red union in 3 buckets + reconciliation to 42 (§2), the HERO
  byte-reproduce expected-RED state + conditional post-landing delta (§3), the net-zero proof with the
  last-touching-commit membership table (§4), and the scope attestation (§5).

## Deviations from Plan

None — plan executed exactly as written. Both tasks author the single artifact; the file is authored as one
unit (Task 1 creates §1–§2/§4–§5, Task 2 adds §3), so it landed in one atomic commit. The RED HERO byte-reproduce
gate is the planned, in-scope outcome of the no-contract phase, not a deviation.

## STOP blocks

- **`## STOP — NEW REGRESSION OUTSIDE BASELINE`: NOT EMITTED.** Net new regression == 0; every red is named in the
  enumerated baseline + HERO-deferred union; all 18 failing suites predate wave-1.

## Known Stubs

None — this plan authors a plain-markdown ledger and RUNS the suite; no production code, no test stubs, no
placeholder data. The contract's INTENTIONAL Phase-326 HERO placeholders (15/20 constants) are NOT this plan's
stubs — they are the documented cross-phase handoff (327-04 `## STOP`), and this plan records the conditional
closure delta for them without applying any contract edit.

## Issues Encountered

None. The Hardhat stat gate's trailing `Cannot find module 'test/stat/…'` is the known cosmetic mocha ESM
file-unloader teardown quirk (fires after the 15-passing/1-failing verdict is reported); it does not affect the
result.

## Threat Flags

None — no new security-relevant surface introduced (this plan RUNS the suite and writes a markdown ledger;
subject FROZEN at the Phase-326 diff, zero `contracts/*.sol` edits).

## Next Phase Readiness

- The clean v48.0 regression baseline is proven and recorded; Phase 327 (TST) is COMPLETE (all 6 plans).
- Feeds the Phase-328 TERMINAL delta-audit + 3-skill adversarial sweep + closure. The 34 stale-harness /
  v48-behavioral baseline reds (bucket B) and the 8 VRF/RNG reds (bucket A) carry forward as the documented
  42-failure baseline; re-syncing the stale fixtures is owned by TERMINAL / a future fixture-repair plan, not
  this regression gate (SCOPE BOUNDARY).
- ⚠ HERO-04 contract-constant landing remains PENDING USER DECISION (out of this no-contract phase): the 15
  ready-to-apply finals are in 327-04-SUMMARY; landing them under the hand-review `CONTRACTS_COMMIT_APPROVED=1`
  gate flips the Hardhat PASS_ALL gate GREEN (forge count unchanged), per the §3 conditional delta.

## Self-Check: PASSED

- FOUND: `test/REGRESSION-BASELINE-v48.md`
- FOUND: `.planning/phases/327-tst-repro-same-results-no-arb-ev-regression-proofs/327-06-SUMMARY.md`
- FOUND commit: `208859e8` (Task 1 + Task 2)
- Full `forge test` tree ran (NOT --match-path): 632 passed / 42 failed; net new regression == 0
- Hardhat HERO gate ran: 15 passing / 1 failing (expected-RED), recorded with conditional post-landing delta
- Zero `contracts/*.sol` (mainnet) modifications; no new `contracts/*.sol`-touching test authored

---
*Phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs*
*Completed: 2026-05-26*
