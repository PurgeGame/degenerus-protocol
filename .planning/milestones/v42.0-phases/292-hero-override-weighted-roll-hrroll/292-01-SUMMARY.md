---
phase: 292-hero-override-weighted-roll-hrroll
plan: 01
subsystem: audit-planning
tags: [audit, hero-override, weighted-roll, design-intent-trace, gas-attestation, rng-backward-trace, v42.0]

# Dependency graph
requires:
  - phase: v41.0 closure
    provides: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4 audit baseline + D-288-FIX-SHAPE-01 dailyIdx invariant + D-271-ADVERSARIAL-01..03 carry-forward
  - phase: 292-CONTEXT
    provides: 7 locked decision anchors (D-42N-LEADER-BONUS-01, D-42N-FLOOR-01, D-42N-BONUS-ENTROPY-01 user-locked 2026-05-17; D-42N-CACHE-01, D-42N-COLOR-ENTROPY-01, D-42N-DETERMINISM-01, D-42N-GAS-01 planner-discretion)
provides:
  - 292-01-DESIGN-INTENT-TRACE.md (HRROLL-10 5-section trace + 7 decision anchors + carry-forward anchors + out-of-scope register + SWEEP-02(ii) adversarial pre-emptive answers + HRROLL-05 backward-trace + Plan-02 Pre-Patch Gate + Sister-Plan Coverage Map)
  - 292-01-MEASUREMENT.md (6-section attestation scaffold; §1 + §3 + §5 FINAL at Plan 01 time; §2 + §4 + §6 carry FILL-IN-Plan-02 placeholders)
  - D-42N-CACHE-01 LOCKED to flat uint32[32] indexed q*8+s
  - D-42N-GAS-01 acceptance threshold: soft +500 / hard +750 gas vs v41 baseline
  - ESCALATION-CHECKPOINT status: NOT TRIGGERED (theoretical worst case ~+431 gas << +10K bound)
affects:
  - 292-02-PLAN.md (Plan 02 reads both artifacts; cannot begin contract-edit until both exist)
  - 293-tst-hrroll (Phase 293 TST-HRROLL-06 asserts D-42N-GAS-01 empirical regression against soft +500 / hard +750 threshold)
  - 296-sweep (Phase 296 SWEEP-02(ii) HRROLL adversarial pass tests against the 4 pre-emptive answers in trace §SWEEP-02)
  - audit/FINDINGS-v42.0.md §9 (Phase 297 terminal — anchor handoff for D-42N-CACHE-01 + D-42N-GAS-01 + D-42N-BONUS-ENTROPY-01)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "design-intent-before-deletion gate per feedback_design_intent_before_deletion.md (5-section trace per HRROLL-10 mirrors Phase 290 3-section MINTCLN-10 pattern)"
    - "theoretical-first gas attestation per feedback_gas_worst_case.md (three-shape cache comparison at plan-phase; empirical regression deferred to sister test phase per D-291-GAS-01 mirror)"
    - "RNG commitment-window backward-trace per feedback_rng_commitment_window.md + feedback_rng_backward_trace.md (consumer → wager-time write site; verify randomness unknowable at commitment time)"
    - "ESCALATION-CHECKPOINT branch in measurement scaffold (TRIGGERED iff theoretical worst case > +10K vs baseline; NOT TRIGGERED at Phase 292)"
    - "single-site degeneration of B2-symmetric callsite-diff pattern (Phase 290 multi-site → Phase 292 single L1941 site)"

key-files:
  created:
    - .planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md
    - .planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md
    - .planning/phases/292-hero-override-weighted-roll-hrroll/292-01-SUMMARY.md
  modified: []

key-decisions:
  - "D-42N-CACHE-01 LOCKED: flat uint32[32] indexed q*8+s — lowest theoretical worst case (~+431 gas) among the three candidate shapes; clearest audit story; pass-2 retains conditional leader-bonus add"
  - "D-42N-GAS-01 acceptance threshold: soft +500 gas / hard +750 gas vs v41 _topHeroSymbol baseline (~9494 gas); Phase 293 TST-HRROLL-06 asserts empirically per D-291-GAS-01 mirror"
  - "ESCALATION-CHECKPOINT NOT TRIGGERED — theoretical worst case ~+431 gas is well under the +10K threshold from CONTEXT.md; Plan 02 may proceed without user-checkpoint"
  - "D-42N-COLOR-ENTROPY-01 non-collision attestation: structural-not-probabilistic (keccak output domain is independent of raw randWord bit-slices by hash-function design)"
  - "Rejected cache shapes: uint64[32] pre-bonus-applied (+14 net), packed uint256[4] re-extract (+588 in pass-2), re-SLOAD-without-cache (+8400, anti-pattern)"
  - "Divergent-entropy alternative for bonus rolls REJECTED at D-42N-BONUS-ENTROPY-01 (preserves per-jackpot-day hero (q,s) lock-in)"
  - "Planner has NOT pre-approved the contract diff per feedback_never_preapprove_contracts.md — Plan 02 presents the full diff to user before commit"

patterns-established:
  - "Trace doc planning-doc exemption note at top: feedback_no_history_in_comments.md applies to NatSpec/contract source comments only, NOT to planning docs (mirror Phase 290 pattern)"
  - "Measurement scaffold §1 + §3 + §5 FINAL at Plan 01 time, §2 + §4 + §6 FILL-IN-Plan-02 placeholders post-patch"
  - "5-section HRROLL-10 trace (vs Phase 290 3-section MINTCLN-10 trace) — section count adapts to phase scope"
  - "Single-site callsite-diff degeneration documented as a structural distinction vs the Phase 290 B2-symmetric multi-site pattern"

requirements-completed:
  - HRROLL-05
  - HRROLL-09
  - HRROLL-10

# Metrics
duration: ~9 min
completed: 2026-05-17
---

# Phase 292 Plan 01: HRROLL Design-Intent Trace + Measurement Scaffold Summary

**HRROLL-10 design-intent-before-deletion gate satisfied via two AGENT-COMMITTED planning artifacts: 5-section trace (`292-01-DESIGN-INTENT-TRACE.md`) recording all 7 Phase 292-scope decision anchors + carry-forward anchors + out-of-scope register + SWEEP-02(ii) adversarial pre-emptive answers + HRROLL-05 backward-trace from `_rollHeroSymbol` consumer back to `placeDegeneretteBet` wager-write at `DegenerusGameDegeneretteModule.sol:484-501`; 6-section measurement scaffold (`292-01-MEASUREMENT.md`) with D-42N-CACHE-01 LOCKED to flat `uint32[32]` (lowest worst case at ~+431 gas across three candidate shapes), D-42N-GAS-01 threshold set at soft +500 / hard +750 gas, D-42N-COLOR-ENTROPY-01 structural non-collision attestation recorded, and ESCALATION-CHECKPOINT NOT TRIGGERED.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-05-17T14:27:51Z
- **Completed:** 2026-05-17T14:36:13Z
- **Tasks:** 2
- **Files created:** 2 (DESIGN-INTENT-TRACE.md 205 lines; MEASUREMENT.md 181 lines)
- **Files modified:** 0 (planning-artifact authoring only; zero contracts/ or test/ edits)

## Accomplishments

- **Trace doc anchor coverage:** ALL 7 Phase 292-scope decision anchors recorded (D-42N-LEADER-BONUS-01, D-42N-FLOOR-01, D-42N-COLOR-ENTROPY-01, D-42N-DETERMINISM-01, D-42N-GAS-01, D-42N-BONUS-ENTROPY-01, D-42N-CACHE-01); carry-forward anchors recorded (D-288-FIX-SHAPE-01, v41 Phase 281 owed-salt pattern, D-40N-MINTBOOST-OUT-01, D-271-ADVERSARIAL-01/02/03).
- **Trace doc section coverage:** ALL 5 HRROLL-10 sections present — (i) original `_topHeroSymbol` single-leader rationale; (ii) leader-bonus magnitude trade-offs (×2 / ×1.5 locked / no-bonus); (iii) sybil exposure / no-floor trade-offs with capital-cost analysis (0.032 ETH for 32-slot dilution payload); (iv) HRROLL-05 RNG commitment-window backward-trace (6-step verification structure); (v) gas headroom + D-42N-CACHE-01 cache-shape decision + D-42N-DETERMINISM-01 exact algorithm lock.
- **Out-of-scope register:** 8 items enumerated per REQUIREMENTS.md `## Out of Scope`; rejected alternatives (×2 leader bonus, divergent-entropy bonus rolls) marked REJECTED-not-DEFERRED to preserve v41 forward-cite zero-emission discipline.
- **SWEEP-02(ii) pre-emptive answers:** ALL 4 HRROLL adversarial hypotheses pre-answered with expected Phase 296 dispositions (whale-coordination MEV → SAFE_BY_DESIGN; no-floor sybil → SAFE_BY_STRUCTURAL_CLOSURE; RNG-consumer bit-slice collision → SAFE_BY_DESIGN; gas DOS → SAFE_BY_BOUNDED_COMPUTATION).
- **Scaffold doc section coverage:** ALL 6 attestation headers present — §1 audit baseline (FINAL), §2 storage byte-identity (FILL-IN-Plan-02), §3 worst-case gas (FINAL with three-shape table + threshold + ESCALATION branch + color-entropy attestation), §4 selector attestations (FILL-IN-Plan-02), §5 events — NONE touched (FINAL), §6 callsite diff — single-site (FILL-IN-Plan-02).
- **D-42N-CACHE-01 chosen shape:** flat `uint32[32]` indexed `q*8 + s` — total worst case ~9925 gas (vs v41 baseline ~9494 gas) = ~+431 gas regression. Reason: lowest of the three candidate shapes (`uint64[32]` ~+445; packed `uint256[4]` ~+1019); clearest audit story; pass-2 retains conditional leader-bonus add (`if (idx == leaderIdx) cumulative += leaderBonus`).
- **D-42N-GAS-01 numeric threshold:** soft +500 gas / hard +750 gas vs v41 baseline; theoretical ~+431 gas fits with ~70 gas headroom; Phase 293 TST-HRROLL-06 asserts empirically per the D-291-GAS-01 mirror pattern.
- **D-42N-COLOR-ENTROPY-01 non-collision attestation:** Recorded as one-liner in `292-01-MEASUREMENT.md` §3.e — color path consumes bits `quadrant*3` of `r`; symbol-roll consumes `keccak256(abi.encode(heroEntropy, day))` output; structurally orthogonal by keccak hash-function design; non-collision is structural-NOT-probabilistic; cross-RNG-consumer bit-slice register table included.
- **ESCALATION-CHECKPOINT state:** NOT TRIGGERED — theoretical worst case ~+431 gas is well under +10K bound; Plan 02 proceeds to its contract-edit task without user-checkpoint.

## Task Commits

Each task was committed atomically:

1. **Task 1: Author `292-01-DESIGN-INTENT-TRACE.md` (HRROLL-10 5-section trace + 7 anchors + carry-forwards + out-of-scope + SWEEP-02 pre-answers)** — `bd3fbdf4` (docs)
2. **Task 2: Author `292-01-MEASUREMENT.md` scaffold + D-42N-CACHE-01 three-shape lock + D-42N-GAS-01 threshold + D-42N-COLOR-ENTROPY-01 attestation** — `b934deb8` (docs)

**Plan metadata commit:** (this SUMMARY + STATE.md + ROADMAP.md update) — final commit at end of plan.

## Files Created/Modified

- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md` (205 lines) — HRROLL-10 design-intent trace; AGENT-COMMITTED pre-patch gate; 7 Phase 292-scope decision anchors + 4 carry-forward anchors + 5 trace sections + out-of-scope register + SWEEP-02(ii) pre-emptive answers + HRROLL-05 backward-trace + Plan-02 Pre-Patch Gate statement + Sister-Plan Coverage Map + source citations.
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md` (181 lines) — HRROLL-06 + HRROLL-07 + HRROLL-08 attestation scaffold; 6 sections (§1 baseline FINAL, §2 storage FILL-IN, §3 gas FINAL with three-shape table, §4 selector FILL-IN, §5 events FINAL no-surface, §6 callsite FILL-IN single-site); D-42N-CACHE-01 LOCKED to flat `uint32[32]`; D-42N-GAS-01 soft +500 / hard +750 gas threshold; ESCALATION-CHECKPOINT NOT TRIGGERED.
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-SUMMARY.md` (this file).

## Decisions Made

- **D-42N-CACHE-01: flat `uint32[32]` indexed `q*8 + s`** — chosen over `uint64[32]` pre-bonus-applied (+14 net gas) and packed `uint256[4]` re-extract (+588 in pass-2 alone). Re-SLOAD-without-cache REJECTED as anti-pattern (~+8400 gas waste per call; `feedback_no_dead_guards.md` violation). Plan 02 implements verbatim; pass-2 cursor walk retains the conditional `if (idx == leaderIdx) cumulative += leaderBonus` branch.
- **D-42N-GAS-01: soft +500 / hard +750 gas** — derived from chosen shape's theoretical ~+431 gas worst case with ~70 gas headroom for second-order effects. Phase 293 TST-HRROLL-06 asserts the empirical regression against this threshold per the D-291-GAS-01 mirror pattern.
- **D-42N-COLOR-ENTROPY-01: structural non-collision** — color path bits `quadrant*3` of `r` vs symbol-roll keccak output — orthogonal entropy domains by construction (keccak avalanche property; output independent of input bit-slices). Non-collision is structural-NOT-probabilistic.
- **D-42N-DETERMINISM-01: locked algorithm** — `abi.encode(heroEntropy, day)` (NOT `abi.encodePacked`); `pick = uint64(uint256(keccak256(...)) % effectiveTotal)`; pass-2 walks flat idx ascending (q ascending → s ascending); leader-bonus added at `idx == leaderIdx`; pass-1 strict-`>` tie-break = first-seen wins matching v41 `_topHeroSymbol` scan order.
- **ESCALATION-CHECKPOINT: NOT TRIGGERED** — theoretical worst case ~+431 gas << +10K bound; Plan 02 proceeds to contract patch without user-checkpoint.
- **Plan 02 contract diff is NOT pre-approved** per `feedback_never_preapprove_contracts.md` — Plan 02's executor presents the full diff to the user for explicit review BEFORE staging or committing.

## Deviations from Plan

None — plan executed exactly as written. All Task 1 + Task 2 acceptance criteria + automated verify gates pass on first authoring pass. Zero auto-fixes invoked.

## Issues Encountered

- **Minor (mechanical):** `.planning/` is `.gitignore`'d at the repo level (line 22). Prior planning commits (e.g., `7260e2b7 docs(290-01)`) use `git add -f` to bypass; same approach used here (no policy deviation). The gitignore + `-f` pattern is the established workflow precedent for `.planning/` commits in this repo. STATE.md was already pre-modified by the orchestrator at execution start (timestamp + status fields); this is expected (the orchestrator records execution-start state before spawning the executor).

## User Setup Required

None — no external service configuration required. Plan 01 is planning-artifact authoring only; zero contract / test / KNOWN-ISSUES.md edits; zero user approval gates triggered (per `feedback_no_contract_commits.md`, only contract / test edits need explicit approval).

## Verification Self-Check

**Files created:**
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md` (205 lines; 192 non-comment lines ≥ 110 required)
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md` (181 lines; 119 non-blank lines ≥ 60 required)

**Task commits exist in `git log`:**
- `bd3fbdf4` — docs(292-01): author HRROLL-10 design-intent trace (7 anchors, 5 sections)
- `b934deb8` — docs(292-01): author HRROLL measurement scaffold + D-42N-CACHE-01 lock

**Plan-level verification (all 11 checks PASS):**
1. ✓ Trace file exists
2. ✓ Scaffold file exists
3. ✓ All 7 anchors present in trace (35 mentions total — anchors referenced repeatedly across sections)
4. ✓ All 5 HRROLL-10 sections present in trace
5. ✓ All 6 measurement headers present in scaffold
6. ✓ All 3 cache shapes named in §3.b (flat `uint32[32]`, `uint64[32]`, packed `uint256[4]`)
7. ✓ `git diff` HEAD~2..HEAD on contracts/ test/ KNOWN-ISSUES.md returns EMPTY
8. ✓ `git status` clean on phase directory (both new files committed)
9. ✓ Both artifacts AGENT-COMMITTED (no user approval — planning-only)
10. ✓ `292-01-MEASUREMENT.md` §3.b explicitly LOCKS flat `uint32[32]` as Plan 02 reference
11. ✓ `292-01-DESIGN-INTENT-TRACE.md` §(iv) explicitly names `placeDegeneretteBet` at `contracts/modules/DegenerusGameDegeneretteModule.sol:484-501`

## Self-Check: PASSED

## Next Phase Readiness

**Plan 02 may now begin its contract-patch task** per the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md` and the NOT-TRIGGERED state of `292-01-MEASUREMENT.md` §3.d ESCALATION-CHECKPOINT.

Plan 02's first task reads `292-01-DESIGN-INTENT-TRACE.md` + `292-01-MEASUREMENT.md`, copies forward the locked decision anchors + measurement framework into the batched contract commit message body (per `feedback_no_history_in_comments.md`), implements the D-42N-DETERMINISM-01 algorithm against the D-42N-CACHE-01-locked flat `uint32[32]` cache shape, deletes `_topHeroSymbol` outright (no stub, no marker per `feedback_no_dead_guards.md`), updates the L1941 callsite to the 3-arg `_applyHeroOverride(traits, r, randWord)` form, populates the `<FILL-IN-Plan-02>` placeholders in `292-01-MEASUREMENT.md` §2 + §4 + §6 post-patch, and presents the full diff to the user for explicit review BEFORE staging or committing (per `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md` + `feedback_batch_contract_approval.md`).

Phase 293 TST-HRROLL fixture work and Phase 296 SWEEP-02(ii) HRROLL adversarial pass both have a baseline disposition record to test against. No blockers.

---
*Phase: 292-hero-override-weighted-roll-hrroll*
*Plan: 01*
*Completed: 2026-05-17*
