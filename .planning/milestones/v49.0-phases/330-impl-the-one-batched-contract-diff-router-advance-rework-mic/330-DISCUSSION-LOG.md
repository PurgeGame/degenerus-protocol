# Phase 330: IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-26
**Phase:** 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
**Areas discussed:** Placeholder constant strategy, Test scope riding the IMPL diff

---

## Placeholder constant strategy (GAS-deferred NEW constants)

The SPEC defers the gas/count/BURNIE constants to Phase 331, but the 330 diff must compile and run
tests now. For the NEW constants with no prior calibration (`RESOLVE_FLAT_BURNIE`, `GAS_BUDGET`,
`DEFAULT_AUTO_OPEN_COUNT`, `DEFAULT_AUTO_BUY_COUNT`): what placeholder values land in the 330 diff,
and how do we guarantee 331 actually recalibrates them?

| Option | Description | Selected |
|--------|-------------|----------|
| Best-guess + flagged constant | SPEC-derived realistic estimates (~1e18 BURNIE, ~10M budget, floor(10M/avg) counts) so tests run against meaningful values; group under a named marker as the 331 re-anchor; existing calibrated constants (66_528 etc.) stay as-is. | ✓ |
| Obvious sentinels | Deliberately-implausible sentinel values (1, max-uint) that can't be mistaken for calibrated; 330 tests only assert structure/compile. | |
| Best-guess + placeholder test | Best-guess values PLUS a dedicated test that fails loudly if placeholders survive to GAS unchanged (a structural tripwire). | |

**User's choice:** Best-guess + flagged constant.
**Notes:** Recalibration guarantee is procedural (the flagged marker + Phase 331's GAS scope + the
ROADMAP "tests must exercise calibrated constants" dependency note), NOT a code tripwire — option 3's
failing-placeholder test was not chosen. Existing calibrated constants (`AUTO_GAS_PRICE_REF`,
`AUTO_RESOLVE_BET_GAS_UNITS`, `AUTO_OPEN_BOX_GAS_UNITS`) stay as-is; 331 re-derives them. Marker
comment must describe what IS, not history (`feedback_no_history_in_comments`).

---

## Test scope riding the IMPL diff

The rename breaks 5 test files / 57 refs (incl. literal source-string assertions in
`CrankLeversAndPacking.t.sol`) that MUST update atomically with the contract. Beyond that mandatory
rename-fix, how much test work rides the 330 diff vs. deferred to the dedicated TST phase (332)?

| Option | Description | Selected |
|--------|-------------|----------|
| Rename-fixes + parity only | Only the mechanical rename-fixes (57 refs + 4 literal-string assertions) to keep the suite green at v48-baseline parity; all behavioral proofs (TST-01/02/03/05) at Phase 332. Mirrors v48 326→327. | ✓ |
| + minimal doWork smoke test | Rename-fixes + a thin smoke test that doWork(0) routes, returns after one category, and reverts NoWork() on an empty board, so the NEW entrypoint is self-validating inside the IMPL commit. | |

**User's choice:** Rename-fixes + parity only.
**Notes:** No `doWork` smoke test at 330. All behavioral proofs land at Phase 332 TST against the
calibrated constants — a clean IMPL→TST split mirroring v48 Phase 326→327. Consistent with the
no-extra-test-scaffolding-at-330 implication of the placeholder decision.

---

## Claude's Discretion

- **Verification / green bar before hand-review** — local compile + forge net-zero regression vs the
  v48 baseline (632/42) + Hardhat parity (21/0), "net-zero" measured after the mandatory rename-fixes.
  Established v46/v48 precedent.
- **Plan / wave decomposition** — the SPEC mandates ONE atomic batched commit in producer-before-
  consumer order; contract-touching plans excluded from worktrees → sequential in main, no cross-file
  parallelism; planner may split into per-work-area PLAN.md files funneling into the single held commit.
- **Exact ABI/encoding mechanics** — the `:275` wrapper `abi.decode`, the `rewardable`-flag mapping,
  the `EmptyAutoBuy` removal/repurpose — all resolved in 329-SPEC §1/§2; re-grep anchors at edit time.

## Deferred Ideas

- `degeneretteResolve` folded INTO the on-chain router — architecturally blocked (frontend concern);
  only the rename + flat re-peg are in scope (carried from 329-CONTEXT).
- A failing-placeholder tripwire test (option 3) — considered, not chosen; recorded so 331 knows no
  code tripwire enforces recalibration.
