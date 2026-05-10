# Phase 264 — Discussion Log

**Date:** 2026-05-09
**Mode:** default (interactive)

## Carrying forward from earlier phases

Locked, not asked:
- D-01 (Phase 261): tests under `test/stat/` and `test/gas/`; opt-in `npm run test:stat` script (already wired in `package.json:9`)
- D-03 (Phase 261): hybrid JS-replica + on-chain boundary cross-validation harness
- D-11 (Phase 261) + `feedback_gas_worst_case.md`: theoretical worst-case derivation FIRST, then HEAD-only measurement
- D-12 (Phase 261): batched test approval at phase close per `feedback_no_contract_commits.md`/`feedback_batch_contract_approval.md`
- D-13 (Phase 261): skip research-agent dispatch (per `feedback_skip_research_test_phases.md`)
- Sample sizes from REQUIREMENTS.md: STAT-01/02 N ≥ 10K aggregated; STAT-05 envelope 70K–110K
- All `contracts/*.sol` BYTE-IDENTICAL — Phase 264 is test-only, zero contract edits

## Gray Areas Presented

Question asked (multiSelect): "Which gray areas should we lock for Phase 264 before planning?"

Options presented:
1. **Sampling oracle for STAT-01/02** — JS replica vs end-to-end tester invocation per draw vs hybrid + on-chain boundary harness
2. **Gas methodology for SURF-05** — entry-point delta vs paired-empty-wrapper analog; cold-vs-warm SLOAD profile; theoretical worst-case derivation
3. **Empty-bucket skip rate threshold (STAT-03)** — analytical bound formula + test-failure threshold + AUDIT-06 INFO/upgrade gate
4. **SURF-01..04 harness shape** — per-surface test files vs single SurfaceRegression.test.js extension; git-diff grep-proof harness

User response: **"use your judgement"**

Decisions made by Claude on all four areas (full rationale in CONTEXT.md):

### 1. Sampling oracle (D-IMPL-01, D-IMPL-02, D-IMPL-03)
**Decision:** Hybrid JS-replica + on-chain boundary harness (Phase 261 D-03 reuse). NO new tester contract — entry-point event harvesting via `JackpotBurnieWin` emit suffices.
**Rationale:** Per-pull keccak is cheap to JS-replicate; bulk N ≥ 10K runs in seconds. Boundary harness at fixed seeds is the drift guard. A new `JackpotCoinPullTester.sol` would add a new `contracts/test/*.sol` surface requiring batched D-APPROVAL approval — unnecessary because everything observable per pull is already emitted.

### 2. Gas methodology for SURF-05 (D-IMPL-04, D-IMPL-05, D-IMPL-06)
**Decision:** Entry-point delta on `payDailyCoinJackpot` + `payDailyJackpotCoinAndTickets` via `GameLifecycle.test.js` fixture pattern. Reject paired-empty-wrapper. Theoretical worst-case derivation FIRST (~37K cold-warm length SLOADs + 75–110K per-pull body × 50). Asserted bound: ≤ 120K (10% headroom). Extend `AdvanceGameGas.test.js` with HEAD-only 1.99× margin assertion.
**Rationale:** PPL helper has 50 cold/warm SLOADs + emit + cross-contract `coinflip.creditFlip` per pull — paired-empty-wrapper noOp would distort. Phase 261's paired-empty-wrapper was right for `_pickSoloQuadrant` (pure stack, no state effects); not applicable here.

### 3. Empty-bucket skip rate (D-IMPL-07, D-IMPL-08, D-IMPL-09)
**Decision:** Analytical bound = realistic late-game holder fixture density. Test-failure threshold = skip rate > 10% per call (averaged across N ≥ 50 calls). Tier gates: ≤ 5% = plain INFO, 5%-10% = INFO with warning, > 10% = test fails / promote above INFO. Cumulative underspend bounded at < 1% of total `coinBudget`.
**Rationale:** D-09 gating in Phase 265 carries the disclosure forward — Phase 264 produces the empirical bound + disclosure prose for the test header comment.

### 4. SURF-01..04 harness shape (D-IMPL-10, D-IMPL-11)
**Decision:** Single `test/stat/SurfaceRegression.test.js` extension (Phase 261 D-09 pattern). Add new `describe` blocks for v35.0 protected ranges. `child_process.execSync('git diff 6b63f6d4 HEAD -- contracts/modules/DegenerusGameJackpotModule.sol')` parsed for hunk ranges; assert no intersection with protected ranges (Phase 263 SUMMARY.md byte-identity sweep is the source of truth).
**Rationale:** Single source of truth for the milestone; tagged describe blocks distinguish v35.0 from Phase 261's v34.0 SURF blocks. NO new tester contract per D-IMPL-02.

## Plan Slicing
**D-PLAN-01:** Defer to planner per Phase 261 D-14 + Phase 263 D-PLAN-01 precedent. Reference shape: 2-plan packing (P1 = STAT-01..04; P2 = SURF-01..05). Single-plan or 3-plan packing acceptable. Every plan ends at the same end-of-phase batched approval gate.

## Deferred Ideas (out of Phase 264)
See CONTEXT.md `<deferred>` section. Highlights:
- `audit/FINDINGS-v35.0.md` §3 disclosure prose — Phase 265
- KI EXC-04 EntropyLib XOR-shift re-verification — Phase 265 REG-03
- v34.0 + v33.0 closure-signal re-verification — Phase 265 REG-01..02
- Adversarial sweep + conservation re-proof + zero-new-state scan — Phase 265 AUDIT-02..04
- `JackpotCoinPullTester.sol` analog — explicitly NOT created
- A/B harness against pre-PPL baseline — out of scope per Phase 261 D-11 ("we don't resurrect the v34.0 binary")

---

*Phase: 264-statistical-validation-cross-surface-preservation*
*Context gathered: 2026-05-09*
