# Phase 356: TST — Unmanipulable (strategic sub/unsub) + Quest-Core Non-Perturbation + Two-Path-Open + Liveness Valve + Gap-Decouple + Gas Marginals + Non-Widening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
**Areas discussed:** SEC-01 sub/unsub scenarios, Gas-ceiling verification

---

## Area selection

| Area | Description | Selected |
|------|-------------|----------|
| Fuzz-offset migration scope | Migrate all ~10 stale-offset fuzz files vs migrate-relevant + enumerate | (default — D-10) |
| SEC-01 sub/unsub scenarios | Which churn/unmanipulable vectors become empirical tests; 356/357 split | ✓ |
| Framework + baseline anchoring | forge vs hardhat; REGRESSION-BASELINE-v56.md anchoring | (default — D-11) |
| Gas-ceiling verification | per-advance <16.7M, decouple regression, openBoxes valve, marginals | ✓ |

---

## SEC-01 sub/unsub scenarios

### Q1 — proof method
| Option | Description | Selected |
|--------|-------------|----------|
| Both: fuzz invariants + named repros | Stateful churn fuzz + one named repro per exploit class | ✓ |
| Named repro tests only | One concrete test per vector; misses unanticipated sequences | |
| Fuzz invariants only | Broad sequence coverage; less legible "which exploit" story | |

**User's choice:** Both: fuzz invariants + named repros.

### Q2 — named repro set (multiSelect)
| Option | Description | Selected |
|--------|-------------|----------|
| Affiliate re-claim churn | affiliateBase persists; churn = honest accrual (forfeit-nothing-gain-nothing) | ✓ |
| Streak decay / gap dodge | compute-on-read decay; funded-span bound; C3-a dodge closed | ✓ |
| pendingBurnie double-claim | CEI zero-before-credit idempotency | ✓ |
| 4 finalize hooks before delete | decay-applied write before slot-delete; funding-kill lastValidMintDay guard | ✓ |

**User's choice:** ALL FOUR.

### Q3 — quest-core non-perturbation (QST-04) 356 vs 357
| Option | Description | Selected |
|--------|-------------|----------|
| Full empirical non-perturbation in 356 | slot-1 streak-neutral + all callers byte-identical; 357 re-confirms | ✓ |
| Core paths in 356, breadth in 357 | slot-1 + manual only; bingo/degenerette/boon to 357 | |

**User's choice:** Full empirical non-perturbation in 356.

### Q4 — SEC-02 proof method
| Option | Description | Selected |
|--------|-------------|----------|
| Byte-diff assertion + freeze/solvency fuzz | ETH-path byte-unchanged anchor + solvency invariant fuzz + RNG-freeze determinism fuzz | ✓ |
| Freeze/solvency fuzz only | rely on fuzz; byte-unchanged to 357 delta-audit | |

**User's choice:** Byte-diff assertion + freeze/solvency fuzz.

---

## Gas-ceiling verification

### Q1 — per-advance ceiling proof
| Option | Description | Selected |
|--------|-------------|----------|
| Per-advance assertion harness + key residuals | per-tx <16.7M on gap-resume + pin the 4 proof residuals | ✓ |
| Per-advance assertion only | per-tx assertion; residuals stay documented assumptions | |
| Re-attest existing suite + ledger the proof | rely on 26/26 suite; per-tx gap-resume stays unmeasured | |

**User's choice:** Per-advance assertion harness + key residuals.

### Q2 — decouple regression depth (GAS-06)
| Option | Description | Selected |
|--------|-------------|----------|
| Full idempotent-resume invariants | defer/same-word/gapDays==0-reentry/dailyIdx-not-advanced/purchaseStartDay-once | ✓ |
| Defer-then-pay + same-word only | minimal; internals left to fuzz | |

**User's choice:** Full idempotent-resume invariants.

### Q3 — openBoxes valve + two-path coexistence (LIVE-01)
| Option | Description | Selected |
|--------|-------------|----------|
| Drain + bound + coexist + byte-unchanged | full: drain both cursors, <16.7M chunks, ordering, no shared-state hazard, individual paths byte-unchanged, no selector collision | ✓ |
| Drain + bound + coexist (skip byte-unchanged) | byte-unchanged + selector-collision to 357 | |

**User's choice:** Drain + bound + coexist + byte-unchanged.

### Q4 — marginal regression posture
| Option | Description | Selected |
|--------|-------------|----------|
| Regression-lock marginals, extend existing harness | assert per-buy/per-open vs loose bound; extend V56AfkingGasMarginal | ✓ |
| Ceiling-only, no marginal locks | only 16.7M ceiling; absolute numbers left as 355's deliverable | |

**User's choice:** Regression-lock marginals, extend existing harness.

---

## Claude's Discretion

- **Fuzz-offset migration (D-10):** MIGRATE ALL ~10 stale `OFF_LASTBOUGHT=21`/uint32 fuzz files to
  `11`/uint24 (mechanical, matches the `08e59a4a` gas-suite retarget; red→green narrowing; removes
  false-green risk).
- **Framework + baseline anchoring (D-11):** new proofs in Foundry forge; `REGRESSION-BASELINE-v56.md`
  anchored by empirical checkout of `453f8073`, by NAME, enumerating both the forge and hardhat
  suites; offset-migration deltas recorded as narrowing.

## Deferred Ideas

- 3-skill adversarial sweep + XMODEL close + delta-audit + FINDINGS-v56.0 + closure flip → Phase 357.
- v50/v51/v52 consolidated cross-model audit debt → the separate v52 track.
- O1 double-credit already FIXED in the v56 IMPL — its single-credit regression is covered by the
  non-perturbation + solvency fuzz, not a standalone 356 item.
