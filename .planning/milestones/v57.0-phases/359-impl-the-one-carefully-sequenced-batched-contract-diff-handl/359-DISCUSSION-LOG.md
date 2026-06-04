# Phase 359: IMPL — The ONE Carefully-Sequenced Batched Contract Diff - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl
**Areas discussed:** Diff edit-ordering

> All v57.0 design is locked in `358-SPEC.md` (D-01..D-33 + UDVT discipline + Handoff Invariants). The gray-area menu offered four execution-strategy areas (Diff edit-ordering · Hand-review structuring · Calibration lock-vs-defer · Plan-split + compile gate); the USER selected **Diff edit-ordering** only.

---

## Diff Edit-Ordering — top-level order

| Option | Description | Selected |
|--------|-------------|----------|
| Features-first, UDVT last | Author + verify all 7 features against the frozen audited 1e7a646d tree first, then one mechanical UDVT sweep over everything | ✓ |
| UDVT-first, features on top | Establish `type Day` across the surface first, then author features in `Day` form | |
| Hybrid: freeze-core first | Land the freeze-critical UDVT core (type def + 3 encodePacked uint32 casts + rngWordByDay key + packed Sub types), then features, then the bulk mechanical churn | |

**User's choice:** Features-first, UDVT last.
**Notes:** Behavior correctness reasoned against the sacred audited baseline; the UDVT is a single isolated final transformation. Accepted trade: the sweep re-touches feature hunks (the 3 freeze-critical encodePacked sites are all pre-existing, so UDVT-02's byte-diff gate stays well-defined).

---

## Diff Edit-Ordering — intra-features order

| Option | Description | Selected |
|--------|-------------|----------|
| By severity, then by file | BATCH-01/02 → BURNIE-01/02 (Critical, isolated) → SALVAGE (same MintModule) → WWXRP + TDEC + CANCEL (clean) | ✓ |
| By file, minimize re-opens | Group strictly by file (all MintModule, all Storage, then per-module) | |
| By risk tier | The 2 functional-solvency exceptions first (BATCH→BURNIE, SALVAGE), then the 3 clean items | |

**User's choice:** By severity, then by file.
**Notes:** Highest-risk behavior reviewed first; producer-before-consumer (BATCH-01 → BURNIE-02) preserved; MintModule opened once for BURNIE+SALVAGE.

---

## Diff Edit-Ordering — compile cadence

| Option | Description | Selected |
|--------|-------------|----------|
| Compile per feature-cluster | `forge build` after BATCH→BURNIE, after SALVAGE, after each clean item, then after the UDVT sweep | |
| Compile after every feature | `forge build` after each REQ-ID | |
| Two checkpoints only | `forge build` once after all 7 features, once after the UDVT sweep | ✓ |

**User's choice:** Two checkpoints only.
**Notes:** Fewest cycles. Coupling recorded (CONTEXT D-05): Foundry compiles `test/*.t.sol`, so the forge-test day-signature updates land with the UDVT sweep to reach the green build; Hardhat JS updates are separate agent commits (SPEC D-20).

---

## Diff Edit-Ordering — UDVT-last sweep scope over new feature code

| Option | Description | Selected |
|--------|-------------|----------|
| Sweep retypes new code too | The final UDVT pass converts day-handling in the new feature code as well — whole tree consistent `type Day`, no raw-int islands | ✓ |
| Leave new feature code raw-int | UDVT converts only the pre-existing surface; new feature code stays raw uint | |

**User's choice:** Sweep retypes new code too.
**Notes:** The new features' day surface is minimal (WWXRP keys on level/10; TDEC/SALVAGE use existing helpers), so the added churn is small.

---

## Wrap-up gate

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context | Write CONTEXT.md now | ✓ |
| Decide the compile-gate coupling | One more turn on the forge `.t.sol` timing | |
| Explore more gray areas | Open hand-review structuring / calibration lock-vs-defer | |

**User's choice:** Ready for context.

## Claude's Discretion

Delegated by 358-SPEC (calibrate at IMPL within the locked shapes; final tuning at 360 GAS): the `boostFactor` curve constants (D-08), the last-day `daysRemaining` threshold (D-04), the SALVAGE within-day variability granularity (D-27), the final operator-overload set + per-site UDVT count (D-19 items 5/6), and the plan/wave decomposition granularity (USER declined a dedicated turn).

## Deferred Ideas

- Hand-review structuring (logical commit grouping / review map) — not opened; the by-severity/by-file authoring order already gives a natural review grouping.
- Generalized operator-spend of `claimableWinnings` — out of scope (Future Requirements).
- The v52 consolidated cross-model audit — separate future track; v57 runs its own in-milestone close at 362.
