---
phase: 293-hrroll-regression-fixture-tst-hrroll
plan: 02
subsystem: testing
tags: [hrroll, jackpot, weighted-roll, chi-square, gas-regression, cross-attestation, dailyWinningTraits, blocking-escalation-resolved, relax-disposition]

# Dependency graph
requires:
  - phase: 293-hrroll-regression-fixture-tst-hrroll
    plan: 01
    provides: "test/helpers/rollHeroSymbolRef.mjs — JS-replay oracle (rollHeroSymbolRef + packDailyHeroWagers + ROLL_HERO_SYMBOL_CONSTANTS); ALGORITHM_VERIFIED via 16-sample production-path cross-attestation in this plan"
  - phase: 292-hero-override-weighted-roll-hrroll
    provides: "Live `_rollHeroSymbol` at contracts/modules/DegenerusGameJackpotModule.sol:1639-1700; D-42N-DETERMINISM-01 lock; D-42N-CACHE-01 flat uint32[32] cache; +431 gas theoretical anchor at 292-01-MEASUREMENT.md §3.c"
  - phase: 291-mintcln-regression-fixture-tst-mintcln
    provides: "Test-only-phase posture (zero contracts/ mutations by default; single USER-APPROVED batched test commit at phase close); D-291-GAS-01 SKIP-GAS posture template inherited for TST-HRROLL-06 RELAX disposition"
  - phase: 282-mint-batch-determinism
    provides: "test/edge/MintBatchDeterminism.test.js + pinDailyEntropy / advanceGame drain chain patterns reused via testUtils.js exports"
  - phase: 262-stat-04
    provides: "Inline chi² critical-value table + Wilson-Hilferty Z + per-bucket accumulation pattern at test/stat/PerPullLevelDistribution.test.js L88-L103 (copied verbatim, no helper-file extraction per 293-CONTEXT.md deferred decision)"
provides:
  - "test/edge/HeroOverrideWeightedRoll.test.js — TST-HRROLL-01..06 + setup-and-sanity + cross-attestation describe blocks (11 tests, all PASS)"
  - "Empirical evidence that the JS-replay oracle bit-mirrors the on-chain _rollHeroSymbol across 16 distinct (dailyHeroWagers, randWord) pairs via DailyWinningTraits event decode — D-293-INVOKE-01 ALGORITHM_VERIFIED established"
  - "Empirical confirmation of LOCKED TST-HRROLL-02 disposition: seed [500, 200, 200, 100] yields empirical leader pick-rate 0.6033 (target 0.60 = 750/1250); binomial chi² = 0.454 < 3.841"
  - "Empirical confirmation of TST-HRROLL-01 chi² weighted-distribution uniformity: seed [400, 300, 200, 100] yields chi² = 5.749 < 7.815 at N=10000 against bonus-adjusted expectation [600/1200, 300/1200, 200/1200, 100/1200]"
  - "Empirical confirmation of TST-HRROLL-03 RNG commitment-window invariance: dailyHeroWagers[D][0..3] slot bytes byte-identical across day-D→D+1 wall-clock advance under D-288-FIX-SHAPE-01 dailyIdx single-writer pattern"
  - "RELAX disposition for D-293-GAS-01 TST-HRROLL-06: log-only traceability + positive-path DailyWinningTraits event-firing assertion + theoretical-attestation cite to 292-01-MEASUREMENT.md §3.c — mirrors Phase 291 D-291-GAS-01 SKIP-GAS posture"
affects: [297-finding-blocks, v43-plus-test-maintenance]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Production-path cross-attestation of `private` Solidity selectors via event-emit decode (here: `DailyWinningTraits.mainTraitsPacked` byte at the oracle's predicted hero quadrant) — reusable pattern for any private function whose output is observable via an event byte field"
    - "RELAX-on-noise-floor: production-path delta measurement that cannot isolate a target function's body cost from downstream behavioural cascades falls back to log-only traceability + theoretical-attestation cite (Phase 291 D-291-GAS-01 SKIP-GAS lineage)"
    - "Inline chi² pattern reuse from test/stat/PerPullLevelDistribution.test.js — verbatim copy of Wilson-Hilferty Z + CHI2_CRIT_05 table + per-bucket accumulation; no helper-file extraction at this point (deferred to v43+ test-maintenance bundle)"
    - "forge inspect storageLayout at test runtime for storage-slot derivation — re-validates Phase 292 §2 EMPTY-diff attestation at every test boot (dailyHeroWagers BASE_SLOT = 53, confirmed live)"

key-files:
  created:
    - test/edge/HeroOverrideWeightedRoll.test.js
  modified: []

key-decisions:
  - "TST-HRROLL-06 RELAX disposition (resolving the first-execution [BLOCKING_ESCALATION] checkpoint): the production-path delta (worst-case-seeded gas − all-zero-seeded gas = 46,020 gas, stddev = 0.0) is DETERMINISTIC but dominated by downstream JackpotBurnieWin / coin-jackpot branch-cost cascades, not the _rollHeroSymbol body's ~+431 gas contribution. The trait-byte rewrite at _applyHeroOverride L1623 changes downstream bucket selection, producing a deterministic ~46K-gas cascade between the two seed states. Production-path granularity therefore cannot isolate the body cost; the strict +431 ± 100 soft / ≤ 750 hard window asserted in the original plan would never pass empirically. User selected option (i) RELAX — log-only traceability + theoretical-attestation cite to 292-01-MEASUREMENT.md §3.c (graceful fallback resembling Phase 291 D-291-GAS-01 SKIP-GAS posture). Option (ii) D-293-INVOKE-01 visibility-flip Phase-292 amendment was NOT invoked; contracts/ remains untouched."
  - "TST-HRROLL-06 positive-path coverage: even under RELAX, the test ASSERTS that DailyWinningTraits fires under BOTH the worst-case-seeded path AND the all-zero-seeded path across all 5 measurement samples. This structurally confirms the production path reaches _applyHeroOverride → _rollHeroSymbol on both seed states (worst-case state triggers the full pass-2 cursor walk at leaderIdx=31; all-zero state hits the HRROLL-01 early-bail at total == 0)."
  - "Cross-attestation byte-position correction: the original plan suggested reading byte 0 of mainTraitsPacked for the hero (quadrant, symbol) decode. Discovered at execute time that _applyHeroOverride L1623 writes the override byte ONLY at index `heroQuadrant` — the other 3 bytes carry JackpotBucketLib.getRandomTraits(r)'s random symbols. Cross-attestation therefore reads byte at oracle's predicted `winQuadrant` (not byte 0) and asserts symbol_bits == oracle's `winSymbol`. The invariant `byte_at_position_N.quadrant_bits == N` is verified inline as a sanity check (both random and override paths encode position into the top 2 bits of the byte at that position)."
  - "Cross-attestation entropy plumbing correction: the on-chain call chain for the natural advanceGame() drain path passes the raw `randWord` (the fulfilled VRF entropy) directly through to _rollHeroSymbol as `heroEntropy` (per _applyHeroOverride L1600/L1609 — `heroEntropy` is the third arg, threaded from `randWord` at _rollWinningTraits L1988). The oracle's internal keccak `pick = keccak256(abi.encode(entropy, day))` then mirrors the contract's same keccak at L1683-1685. NO outer keccak with `dailyIdx` is applied at _applyHeroOverride; the oracle receives the raw `randWord` as `entropy`."
  - "Inline chi² helper inlined (NOT extracted to test/helpers/chiSquare.mjs) per 293-CONTEXT.md `<deferred>` 'Chi² implementation pattern' entry — deferred to v43+ test-maintenance bundle once 3+ consumers exist."
  - "feedback_no_dead_guards.md applied to the [BLOCKING_ESCALATION] machinery: the throw + soft/hard-bound assertion code paths from the original Task 6 stub were removed cleanly under the RELAX disposition (not left as dead-guard branches). Two historical [BLOCKING_ESCALATION] tokens remain in the test file solely as prose anchors documenting the dispute resolution — not as active throw code."

patterns-established:
  - "Cross-attestation byte indexing: when an on-chain event packs N traits as N bytes and ONLY one byte is overridden by the function under test, the cross-attestation must read the byte at the function's PREDICTED output index, not a fixed position. Reading a fixed position aliases the random non-override bytes with the override byte and produces false mismatches."
  - "RELAX disposition documentation: the test file embeds the RELAX rationale inline at the describe-block header AND in the test-file JSDoc bullet (iii), making the deviation from the original strict-window plan auditable from the test source alone (no need to read the SUMMARY)."

requirements-completed: [TST-HRROLL-01, TST-HRROLL-02, TST-HRROLL-03, TST-HRROLL-04, TST-HRROLL-05, TST-HRROLL-06]

# Metrics
duration: ~50 minutes (continuation agent; first executor agent a598527c781d4287c completed Tasks 1-5 prior)
completed: 2026-05-17
---

# Phase 293 Plan 02: HRROLL Regression Fixture Summary

**`test/edge/HeroOverrideWeightedRoll.test.js` (1499 lines, 11 tests, all PASS) covers TST-HRROLL-01..06 + cross-attestation against the post-HRROLL audit subject (Phase 292 commit `a0218952`). User-approved RELAX disposition for TST-HRROLL-06 resolves the first-execution `[BLOCKING_ESCALATION]` checkpoint: log-only traceability + positive-path `DailyWinningTraits` event-firing assertion + theoretical-attestation cite to `292-01-MEASUREMENT.md §3.c` (mirrors Phase 291 D-291-GAS-01 SKIP-GAS posture). Zero contracts/ mutations; D-293-INVOKE-01 visibility-flip escalation NOT invoked.**

## Performance

- **Duration:** ~50 minutes (continuation agent; first-execution agent `a598527c781d4287c` completed Tasks 1-5 + Task 6 stub in strict-assertion form prior to the BLOCKING_ESCALATION resolution)
- **Tasks completed:** 7 of 8 (Task 8 = USER-APPROVED batched commit checkpoint, pending)
- **Files created:** 1 (`test/edge/HeroOverrideWeightedRoll.test.js`, 1499 lines)
- **Files modified:** 0
- **Test runtime:** ~24 seconds (full suite); chi² N=10000 tests ~0.4s each; production-path tests (TST-HRROLL-03 + TST-HRROLL-06 + cross-attestation) ~22s combined

## Accomplishments

- **TST-HRROLL-01 (chi² weighted distribution)** — PASS. Seed `[400, 300, 200, 100]`; N=10000 JS-oracle iterations; bonus-adjusted expectation `[600/1200, 300/1200, 200/1200, 100/1200]`. Empirical chi² = **5.749 < 7.815** (df=3); observed buckets `[4973, 2576, 1670, 781]`. Wilson-Hilferty Z = 1.162.
- **TST-HRROLL-02 (×1.5 leader-bonus binomial)** — PASS. LOCKED seed `[500, 200, 200, 100]`; N=10000; empirical leader pick-rate **0.6033** (target = 0.60 = 750/1250 exactly). Binomial chi² = **0.454 < 3.841** (df=1); leaderHits=6033, otherHits=3967.
- **TST-HRROLL-03 (RNG commitment-window proof)** — PASS. `dailyHeroWagers[1][0..3]` slot bytes captured pre-advance and post-advance via direct `getStorage` reads against the runtime-derived `BASE_SLOT = 53`. Slots = `[0x1388·10^25, 0x0, 0x1388·10^42, 0x0]` byte-identical across the wall-clock day advance; JS oracle replay produces identical `(hasWinner=true, q=0, s=3)` on both captures. `dailyIdx` confirmed frozen as the controlling day key per D-288-FIX-SHAPE-01 single-writer invariant.
- **TST-HRROLL-04 (single-bettor)** — PASS. Two sub-tests covering flat idx 0 and flat idx 17 (mid-cursor leader position). Each test runs 100 distinct entropy variations and asserts deterministic `(true, q, s)` return with probability 1.0.
- **TST-HRROLL-05 (zero-wager)** — PASS. 100 distinct entropy variations against `[0n, 0n, 0n, 0n]` dailyHeroWagers; all return `(false, 0, 0)` per HRROLL-01 early-bail at `total == 0`.
- **TST-HRROLL-06 (production-path gas regression — RELAXED)** — PASS. 5 measurement samples, each deploying a fresh fixture for both worst-case-seeded and all-zero-seeded paths. Per-sample `gasWorst = 713775`, `gasBaseline = 667755`, `delta = 46020`; mean delta = **46020.0 gas; stddev = 0.0 gas** (deterministic). DailyWinningTraits event firing asserted under both paths across all 5 samples. Production-path delta logged for traceability; NOT asserted against the +431 ± 100 soft / ≤ 750 hard window per the RELAX disposition. Theoretical acceptance evidence remains the analytical anchor at `292-01-MEASUREMENT.md §3.c`.
- **TST-HRROLL-01..05 cross-attestation** — PASS. 16 production-path replays via `DailyWinningTraits` event decode; on-chain symbol at oracle's predicted `winQuadrant` byte matches oracle's `winSymbol` exactly in all 16 cases. D-293-INVOKE-01 ALGORITHM_VERIFIED established at the production-path level (not just the unit-test level).
- **Setup-and-sanity (3 tests)** — PASS. `forge inspect storageLayout` returns `BASE_SLOT = 53` (re-validates Phase 292 §2 EMPTY-diff attestation at runtime); JS-replay oracle zero-wager smoke PASS; `packDailyHeroWagers` round-trip PASS.

## Task Commits

**No per-task commits.** Per the plan's frontmatter must-haves entry and `feedback_batch_contract_approval.md` + `feedback_manual_review_before_push.md`, both Plan 01's `test/helpers/rollHeroSymbolRef.mjs` and Plan 02's `test/edge/HeroOverrideWeightedRoll.test.js` are left as untracked files in the worktree for the user-approved batched commit at the Task 8 checkpoint.

**Plan metadata commit:** issued at the end of this plan (handled by the orchestrator per the continuation-agent deferred-commit protocol) and includes ONLY `.planning/phases/293-hrroll-regression-fixture-tst-hrroll/293-02-SUMMARY.md` + state-update files (`.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`) — no `test/` or `contracts/` paths.

## Files Created/Modified

- `test/edge/HeroOverrideWeightedRoll.test.js` — NEW. 1499 lines. SPDX header + JSDoc 5-bullet path-of-investigation header + per-test mapping + 11 module-level constants + 11 module-level helpers + 7 nested `describe` blocks (setup-and-sanity + TST-HRROLL-01..06 + cross-attestation). Untracked in the working tree pending Task 8 USER-APPROVED batched commit.

## Decisions Made

### D-293-GAS-01 disposition resolution — RELAX (option i) selected by user 2026-05-17

The first-execution agent (`a598527c781d4287c`) emitted a `[BLOCKING_ESCALATION]` token at the original Task 6 noise-floor gate. Discovered at execute time: the production-path delta is NOT noisy in the conventional sense (stddev = 0.0 across 5 samples). It is DETERMINISTIC at ~46,020 gas — far above the original +431 ± 100 / ≤ 750 window. Root cause: the trait-byte rewrite at `_applyHeroOverride` L1623 (which the hero override fires under worst-case seeding but skips under all-zero seeding) changes downstream `JackpotBurnieWin` / coin-jackpot bucket selection, producing a deterministic ~46K-gas cascade between the two seed states. Production-path granularity therefore cannot isolate the `_rollHeroSymbol` body's ~+431 gas contribution from these downstream cascades.

**User disposition (2026-05-17): option (i) RELAX.** TST-HRROLL-06 now:

1. Captures + logs per-sample gas-delta + mean + stddev as traceability output.
2. Asserts only that `DailyWinningTraits` fires under BOTH worst-case-seeded and all-zero-seeded paths (positive-path coverage; structural confirmation that the production path reaches `_applyHeroOverride` → `_rollHeroSymbol` on both seed states).
3. Cites `292-01-MEASUREMENT.md §3.c` as the theoretical-attestation source — the load-bearing acceptance evidence for the gas regression remains the analytical +431-gas anchor.
4. Does NOT assert against any soft/hard window on the delta.

Mirrors the Phase 291 D-291-GAS-01 SKIP-GAS posture.

**Option (ii) D-293-INVOKE-01 visibility-flip Phase-292 amendment was NOT invoked** — contracts/ remains untouched. Per `feedback_never_preapprove_contracts.md`, the user's explicit RELAX disposition closes the escalation path at the test-only side.

### Cross-attestation byte-indexing correction (Task 7)

The original plan suggested reading byte 0 of `mainTraitsPacked` for the hero `(quadrant, symbol)` decode. Discovered at execute time that `_applyHeroOverride` L1623 writes the override byte ONLY at index `heroQuadrant`; the other 3 bytes carry random symbols from `JackpotBucketLib.getRandomTraits(r)`. Reading byte 0 produces false mismatches when `heroQuadrant != 0`.

**Fix:** the cross-attestation reads the byte at the oracle's predicted `winQuadrant` position and asserts `symbol_bits == oracle.winSymbol`. The invariant `byte_at_position_N.quadrant_bits == N` is verified inline (both random and override paths encode position into the top 2 bits of the byte at that position).

### Cross-attestation entropy-plumbing correction (Task 7)

Initial implementation passed a pre-hashed `heroEntropy = keccak256(abi.encode(randWord, dailyIdx))` to the JS oracle, mistakenly assuming `_applyHeroOverride` hashed before calling `_rollHeroSymbol`. Re-reading the contract: `_applyHeroOverride(traits, r, randWord)` at L1600 receives `heroEntropy = randWord` (the THIRD arg, threaded raw from `_rollWinningTraits` L1988); `_rollHeroSymbol(dailyIdx, heroEntropy=randWord)` then does its OWN `keccak256(abi.encode(entropy, day))` at L1683-1685.

**Fix:** the oracle receives the raw `entropy` (the fulfilled VRF word) directly; its internal keccak chain then mirrors the contract's keccak exactly. 16/16 cross-attestation matches after the correction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Cross-attestation byte-indexing bug**

- **Found during:** Task 7 verify-gate execution (cross-attestation failed at i=0 with `oracle=0, onChain=7` mismatch).
- **Issue:** Plan suggested reading byte 0 of `mainTraitsPacked` for the hero decode, but `_applyHeroOverride` L1623 writes the override byte ONLY at index `heroQuadrant`; byte 0 carries the random non-override symbol when `heroQuadrant != 0`.
- **Fix:** Read byte at `oracleOut.winQuadrant` and assert `symbol_bits == oracleOut.winSymbol`. Added an inline sanity invariant `byte_at_position_N.quadrant_bits == N`.
- **Files modified:** `test/edge/HeroOverrideWeightedRoll.test.js` (Task 7 describe block — assertion logic).
- **Verification:** Cross-attestation now passes 16/16 production-path replays.
- **Committed in:** N/A — staged-only pending Task 8 USER-APPROVED batched commit.

**2. [Rule 1 — Bug] Cross-attestation entropy-plumbing bug**

- **Found during:** Task 7 verify-gate execution (after fix #1, cross-attestation failed at i=3 with quadrant mismatch).
- **Issue:** Initial implementation pre-hashed `heroEntropy = keccak256(abi.encode(randWord, dailyIdx))` before passing to the JS oracle, on the mistaken assumption that `_applyHeroOverride` hashes once before `_rollHeroSymbol`. Re-reading the contract source: `_applyHeroOverride(traits, r, randWord)` passes the raw `randWord` directly as `heroEntropy`; `_rollHeroSymbol(dailyIdx, heroEntropy)` performs its own keccak at L1683-1685.
- **Fix:** Pass the raw `entropy` (= fulfilled VRF word) directly to the oracle; the oracle's internal keccak then mirrors the contract's exactly.
- **Files modified:** `test/edge/HeroOverrideWeightedRoll.test.js` (Task 7 describe block — entropy-handling logic + JSDoc comment).
- **Verification:** Cross-attestation passes 16/16 after the correction.
- **Committed in:** N/A — staged-only pending Task 8 USER-APPROVED batched commit.

### USER-DIRECTED Disposition Resolution

**3. [USER DIRECTIVE - RELAX] TST-HRROLL-06 reformed from strict-assertion to log-only-traceability**

- **Trigger:** First-execution agent emitted `[BLOCKING_ESCALATION]` at Task 6 (mean delta = 46,020 gas > 2× hard bound = 1,500 gas).
- **Root cause:** Production-path delta is deterministically dominated by downstream `JackpotBurnieWin` / coin-jackpot branch-cost cascades (the trait-byte rewrite at `_applyHeroOverride` L1623 changes downstream bucket selection). Production-path granularity cannot isolate the `_rollHeroSymbol` body's ~+431 gas contribution.
- **User disposition (2026-05-17):** option (i) RELAX — log-only traceability + theoretical-attestation cite to `292-01-MEASUREMENT.md §3.c` (mirrors Phase 291 D-291-GAS-01 SKIP-GAS posture).
- **Fix applied:**
  - Rewrote the TST-HRROLL-06 describe block in RELAX form.
  - Removed the `BLOCKING_ESCALATION` throw + soft/hard-bound assertion machinery cleanly per `feedback_no_dead_guards.md` (the escalation policy is now historical).
  - Added a positive-path coverage assertion: `DailyWinningTraits` fires under BOTH worst-case-seeded and all-zero-seeded paths.
  - Removed `GAS_DELTA_SOFT_TOLERANCE` and `GAS_DELTA_HARD_BOUND` constants (unused under RELAX); preserved `GAS_DELTA_THEORETICAL = 431` for the theoretical-attestation cite.
  - Updated the test-file JSDoc bullet (iii) + the per-test mapping line for TST-HRROLL-06 to reflect the RELAX posture.
  - Two historical `[BLOCKING_ESCALATION]` tokens remain in the test file solely as prose anchors documenting the resolution; no active throw code.
- **Files modified:** `test/edge/HeroOverrideWeightedRoll.test.js` (constants block + JSDoc header + Task 6 describe block).
- **Verification:** TST-HRROLL-06 passes under `npx hardhat test --grep "TST-HRROLL-06"` (5/5 samples, both paths fire `DailyWinningTraits`, mean delta = 46020.0 gas / stddev = 0.0 gas logged for traceability).
- **Committed in:** N/A — staged-only pending Task 8 USER-APPROVED batched commit.

---

**Total deviations:** 3 (2 × Rule 1 bug-fixes during cross-attestation implementation + 1 × USER-DIRECTED RELAX disposition resolving the first-execution BLOCKING_ESCALATION).

**Impact on plan:** Tasks 1-5 executed plan-verbatim by the first-execution agent. Task 6 reformed under USER RELAX disposition. Task 7 cross-attestation implemented with two correctness-bug fixes during execution. Zero scope creep beyond the plan's TST-HRROLL-01..06 + cross-attestation perimeter; zero contracts/ touches; zero sister-test-file touches.

## Issues Encountered

- **Task 6 first-execution `[BLOCKING_ESCALATION]`:** the production-path delta methodology proposed in the original plan cannot isolate `_rollHeroSymbol` body cost from downstream branch-cost cascades. Resolved by user disposition option (i) RELAX (see Deviation #3).
- **Cross-attestation byte-indexing bug** (Deviation #1): initial assertion read byte 0 of `mainTraitsPacked`, but the hero override writes only one byte at index `heroQuadrant`. Resolved by reading the byte at the oracle's predicted `winQuadrant`.
- **Cross-attestation entropy-plumbing bug** (Deviation #2): initial implementation pre-hashed `heroEntropy` before passing to the oracle, but the contract passes `randWord` raw. Resolved by removing the pre-hash.

## User Setup Required

None — this plan ships a test-only file. No external service configuration, no environment variables, no dashboard changes.

The Task 8 USER-APPROVED batched commit is the next checkpoint: the user reviews the diff (1499 lines `test/edge/HeroOverrideWeightedRoll.test.js` + 189 lines `test/helpers/rollHeroSymbolRef.mjs` from Plan 01) and types `approved` to authorize the single batched test commit per `feedback_batch_contract_approval.md` + `feedback_manual_review_before_push.md`.

## Next Phase Readiness

- **Phase 293 close-out:** Pending Task 8 USER-APPROVED batched commit. All 6 TST-HRROLL-NN requirement IDs covered by passing tests.
- **D-293-INVOKE-01 escalation path:** NOT INVOKED. Default disposition (JS-replay oracle ALGORITHM_VERIFIED) holds; the production-path cross-attestation at Task 7 confirms the oracle bit-mirrors the contract across 16 production-path replays.
- **D-293-GAS-01 disposition:** RELAX (option i) selected by user. Test ships log-only traceability + positive-path coverage; theoretical-attestation cite to `292-01-MEASUREMENT.md §3.c` is the load-bearing acceptance evidence.
- **D-293-STALE-VIEW-01:** Honored. `contracts/DegenerusGame.sol:2545-2563 getDailyHeroWinner` is NOT used as an assertion vehicle in this fixture (cited once in the test file's JSDoc bullet (iv) as a path-of-investigation note only). Deferred to v43+ explicit cleanup phase per the 293-CONTEXT.md `<deferred>` register.
- **Phase 297 delta-surface:** `test/edge/HeroOverrideWeightedRoll.test.js` (this plan) + `test/helpers/rollHeroSymbolRef.mjs` (Plan 01) constitute the Phase 293 §3.A test-surface delta vs the post-292 tree. Phase 297 §3.A FINDINGS will cite these two files.

## Self-Check

**Files claimed:**
- `test/edge/HeroOverrideWeightedRoll.test.js` — FOUND (1499 lines, untracked per zero-commit policy pending Task 8 USER approval)
- `test/helpers/rollHeroSymbolRef.mjs` — FOUND (189 lines from Plan 01, untracked per zero-commit policy)

**Commits claimed:**
- N/A — no per-task commits in this plan. Single USER-APPROVED batched commit bundles both Plan 01 + Plan 02 files at Task 8.

**Verify gates (Task 1-7 + global):**
- Task 1 (file exists + JSDoc 5 bullets + setup-and-sanity 3 tests): PASS
- Task 2 (TST-HRROLL-01 chi² N=10000 against bonus-adjusted expectation): PASS (chi² = 5.749 < 7.815)
- Task 3 (TST-HRROLL-02 binomial under LOCKED seed [500, 200, 200, 100]): PASS (chi² = 0.454 < 3.841; empirical rate 0.6033)
- Task 4 (TST-HRROLL-03 commitment-window byte-identity across day advance + dailyIdx single-writer): PASS
- Task 5 (TST-HRROLL-04 single-bettor + TST-HRROLL-05 zero-wager across 100 entropy variations each): PASS
- Task 6 (TST-HRROLL-06 RELAX form: log-only traceability + DailyWinningTraits event-firing assertion + cite 292-01-MEASUREMENT.md §3.c): PASS
- Task 7 (cross-attestation 16 production-path replays via DailyWinningTraits event decode matches JS oracle): PASS (16/16 matches)
- Global (zero contracts/ mutations): PASS (`git diff --name-only contracts/` empty)
- Global (sister frozen test files byte-identical): PASS (`git diff --name-only test/edge/HeroOverrideDayIndex.test.js test/edge/MintBatchDeterminism.test.js test/edge/MintCleanupRegression.test.js test/helpers/raritySymbolBatchRef.mjs` empty)
- Global (full test file runs to completion with all 11 tests passing): PASS (`npx hardhat test test/edge/HeroOverrideWeightedRoll.test.js` — 11 passing, 0 failing, ~24s runtime)

## Self-Check: PASSED

---

## Phase 293 Close-Out Register (orchestrator-facing)

| Test | State | Evidence |
| --- | --- | --- |
| TST-HRROLL-01 (chi² weighted distribution) | PASS | chi² = 5.749 < 7.815 (df=3); observed=[4973, 2576, 1670, 781]; expected=[5000.0, 2500.0, 1666.7, 833.3]; Wilson-Hilferty Z=1.162; N=10000 |
| TST-HRROLL-02 (×1.5 leader-bonus binomial) | PASS | LOCKED seed [500, 200, 200, 100]; empirical leader pick-rate 0.6033 (target 0.60 = 750/1250); chi² = 0.454 < 3.841 (df=1); leaderHits=6033, otherHits=3967; N=10000 |
| TST-HRROLL-03 (RNG commitment-window proof) | PASS | dailyHeroWagers[1][0..3] slot bytes byte-identical across day-D→D+1 advance; JS oracle replay produces identical (true, 0, 3) on both captures; dailyIdx single-writer invariant D-288-FIX-SHAPE-01 verified |
| TST-HRROLL-04 (single-bettor) | PASS | 2 sub-tests × 100 entropy variations each (flat idx 0 + flat idx 17); probability 1.0 |
| TST-HRROLL-05 (zero-wager) | PASS | 100 entropy variations; (false, 0, 0) per HRROLL-01 early-bail |
| TST-HRROLL-06 (production-path gas regression — RELAX) | PASS | 5 samples × deterministic delta 46020 gas; stddev = 0.0; DailyWinningTraits fires under both seed paths; cite 292-01-MEASUREMENT.md §3.c (+431 gas theoretical anchor — load-bearing acceptance evidence). User RELAX disposition (option i) applied. |
| Cross-attestation (D-293-INVOKE-01 ALGORITHM_VERIFIED) | PASS | 16/16 production-path replays via DailyWinningTraits event decode match JS oracle output exactly |
| User RELAX outcome (D-293-GAS-01) | APPLIED | Option (i) selected 2026-05-17; option (ii) visibility-flip NOT invoked; contracts/ untouched |

**Gas-delta sample register (TST-HRROLL-06):** `[46020, 46020, 46020, 46020, 46020]` gas; mean=46020.0; stddev=0.0; theoretical anchor=+431 gas (logged for traceability only; NOT asserted under RELAX disposition).

**Cross-attestation match count:** 16/16 production-path replays matched JS oracle output exactly via `DailyWinningTraits.mainTraitsPacked` byte-position-`winQuadrant` decode.

**USER-APPROVED batched commit SHA (Task 8):** PENDING — awaiting user `approved` signal at the Task 8 checkpoint.

---
*Phase: 293-hrroll-regression-fixture-tst-hrroll*
*Completed: 2026-05-17*
