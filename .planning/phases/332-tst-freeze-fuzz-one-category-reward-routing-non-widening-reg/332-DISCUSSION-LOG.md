# Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-27
**Phase:** 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
**Areas discussed:** Reentrancy shape (TST-02), Deferred-red ledger (TST-04)

> Gray areas offered: Freeze-fuzz depth · Same-results method · Reentrancy shape · Deferred-red
> ledger. User selected **Reentrancy shape + Deferred-red ledger**; the other two were delegated to
> precedent ("the rest I'll resolve by precedent") and captured under Claude's Discretion in CONTEXT.

---

## Reentrancy shape (TST-02)

### Q1 — What should TST-02's router→game→`creditFlip` double-pay regression actually exercise?

| Option | Description | Selected |
|--------|-------------|----------|
| Live attacker + structural | Reentrant actor harness + grep-attested no-untrusted-call structural proof (the D-01b "backstop" framing) | |
| Structural + behavioral | Grep-attest no untrusted call + single `creditFlip` CEI-last, plus a one-credit-per-tx assertion; no synthetic attacker | (effectively chosen) |
| Live attacker only | Build the attacker harness as the centerpiece, no separate structural attestation | |

**User's choice:** Free text — *"reentrancy is not an issue, nothing here pays eth and this only
interacts with trusted contracts."*
**Notes:** Decisive structural disposition. `doWork` pays only minted FLIP CREDIT, makes no ETH push,
and touches only pinned trusted contracts (GAME/COINFLIP) → no re-entry hook → no attacker harness.
TST-02's roadmap SC is satisfied by the structural attestation (no untrusted call in any leg + the
single `creditFlip` CEI-last at `AfKing.sol:913-918`).

### Q2 — How to assert the one-category / no-bounty-stacking invariant?

| Option | Description | Selected |
|--------|-------------|----------|
| Count `creditFlip` calls | `vm.recordLogs` / `expectCall` — exactly one `creditFlip` per `doWork()` tx across all branches + the `bountyEarned==0` skip path | ✓ |
| Assert exact amount | Credited amount equals exactly one category's formula, never a sum | |
| Both | Count == 1 AND amount matches the single active category's formula | |

**User's choice:** Count `creditFlip` calls.
**Notes:** Directly proves the `else-if` chain can never credit two categories in one tx, including the
zero-credit skip path (a buy chunk over already-bought subs runs the category but credits nothing).

---

## Deferred-red ledger (TST-04)

### Q3 — How should the 16 reward-rehoming reds be dispositioned?

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid (per sub-class) | Oracle-migration reds repaired in place; reward-shape reds net-deleted + re-expressed in the new proof files | |
| Repair all in place | Rewrite all 16 assertions in their current files to the new shape; suite returns toward 632/42-equivalent | |
| Delete + re-author fresh | Net-delete all 16 stale cases, author the v49 invariants entirely fresh in new proof files | ✓ |

**User's choice:** Delete + re-author fresh.
**Notes:** Cleanest separation. No-double-buy invariant re-expressed in storage-oracle terms
(`lastAutoBoughtDay` / pool-balance-delta), preserving SAFE-03 / H-CANCEL-SWAP. TST-04 ledger target:
failing returns to exactly the 42 v48.0-baseline reds (net-zero new regression).

### Q4 — Where should the fresh v49 proofs live?

| Option | Description | Selected |
|--------|-------------|----------|
| New file per TST req | One dedicated file per requirement (RouterBountyComposition / AdvanceRouting / DegeneretteResolveRepeg; TST-01 extends RngLockDeterminism) | |
| Repurpose existing files | Re-author inside the existing keeper test files, keeping the file set stable | |
| You decide | Planner picks closest-analog homes per the pattern-mapper | ✓ |

**User's choice:** You decide → Claude's Discretion (planner picks homes via pattern-mapper).

### Q5 — Record a v49 ledger doc, and de-crank the `Crank*` test files?

| Option | Description | Selected |
|--------|-------------|----------|
| v49 ledger + de-crank | Author `REGRESSION-BASELINE-v49.md` (42-red union + 16 deletions + new green proofs + renames) AND rename the `Crank*` files to keeper-* | ✓ |
| v49 ledger only | Author the ledger but leave `Crank*` names as-is | |
| No ledger doc | Capture the proof inline in the TST-04 plan/SUMMARY; decide naming later | |

**User's choice:** v49 ledger + de-crank.
**Notes:** Pure file/symbol rename (zero behavioral change), recorded in the ledger so file-path churn
stays attributable. Completes the v48 contract-rename ("crank" purged) into `test/`; aligns with the
user's stated dislike of "crank". 5 targets: `CrankFaucetResistance`, `CrankNonBrick`,
`CrankLeversAndPacking`, `CrankOpenBoxWorstCaseGas`, `CrankResolveBetWorstCaseGas`.

---

## Claude's Discretion

- **Proof-file homes (TST-02/03/05)** — planner picks closest-analog homes (Q4 "You decide").
- **Freeze-fuzz depth (TST-01)** — default profile for routine CI; deep proof gated under
  `FOUNDRY_PROFILE=deep` (v44 INV precedent). [Delegated to precedent.]
- **Same-results method (TST-03/05)** — GASOPT via Foundry behavioral-equality; `degeneretteResolve`
  via Foundry RESULTS-equality + the existing Hardhat Degenerette stat tests stay green. [Delegated to
  precedent; mirrors v48 Phase 327.]

## Deferred Ideas

None — discussion stayed within phase scope.
