# Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents. Decisions are captured in `235-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 235-conservation-rng-commitment-re-proof-phase-transition
**Areas discussed:** Plan shape, Evidence reuse, Addendum (c2e5e0a9 + 314443af) treatment, TRNX-01 audit depth

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Plan shape (3 vs 5 vs merge) | 3 plans (ROADMAP default) vs 5 plans (strict per-req) vs merged shapes | ✓ |
| Fresh-from-scratch vs cite prior | How to treat evidence already emitted by Phases 231/232/233 | ✓ |
| Addendum (c2e5e0a9) treatment | 17 new EntropyLib.hash2 / keccak256 entropy-mixing sites | ✓ |
| TRNX-01 audit depth | Depth of `_unlockRng` removal audit | ✓ |

Dropped as smaller-impact (noted in `<deferred>`): CONS-02 BurnieCoin scope breadth, Conservation-proof format.

**User's choice:** All four areas selected for discussion.

---

## Plan shape

### Plan count

| Option | Description | Selected |
|--------|-------------|----------|
| 3 plans (ROADMAP default) | 235-01 CONS, 235-02 RNG, 235-03 TRNX. Fewer files, more sections per file. | |
| 5 plans (strict per-req, Recommended) | One plan per requirement. Matches 231/232/233 precedent. | ✓ |
| 4 plans (balanced split) | Separate CONS-01/02 but merge RNG. | |
| 2 plans (minimal) | CONS (both) + RNG+TRNX (all rest). | |

**User's choice:** 5 plans (strict per-req, Recommended).
**Notes:** None beyond acceptance.

### Dependency

| Option | Description | Selected |
|--------|-------------|----------|
| All parallel (Wave 1, Recommended) | No cross-plan dependencies; each audits a different surface. | ✓ |
| 2-wave (CONS+TRNX Wave 1, RNG Wave 2) | RNG depends on finalized SSTORE catalog. | |
| 3-wave (serialized) | TRNX first, then RNG, then CONS. | |

**User's choice:** All parallel (Wave 1, Recommended).

---

## Evidence reuse / prior phase citations

### Evidence reuse

| Option | Description | Selected |
|--------|-------------|----------|
| Cite prior verdicts; audit only gaps | Reuse 233 JKP-02 + 231 EBD-02 + 232 DCM-01 evidence; audit only uncovered sites. | |
| Re-prove fresh, cross-cite prior (Recommended) | Fresh re-run at HEAD; cross-cite (don't reuse) prior verdicts. | (user's free-text steered scope toward this option with explicit 232.1 inclusion) |
| Hybrid by requirement | CONS fresh; RNG cite where covered; TRNX fresh. | |

**User's free-text response (selected "Other"):** "we need to take into account the changes that have been made since this milestone started, especially for ticket processing"

**Captured decision:** Re-prove fresh + cross-cite + re-verify at HEAD, with 232.1 fix series and 230-02 addendum commits explicitly in scope. Ticket processing surface moved under three phases (230 baseline → 232.1 fix series → HEAD) and Phase 235 proofs MUST reflect the final shape.

### Cross-cite format

| Option | Description | Selected |
|--------|-------------|----------|
| Cite file:line of prior verdict | Anchor prior evidence but re-read HEAD source. | |
| Cite + re-verify at HEAD (Recommended) | Add a one-line "re-verified at HEAD <SHA>" note per cited row. | ✓ |
| Inline full restatement | Restate the prior evidence in full inside Phase 235 plans. | |

**User's choice:** Cite + re-verify at HEAD (Recommended).

### Ticket scope

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated plan sub-section per-requirement (Recommended) | Every plan gets a "232.1 ticket-processing impact" sub-section. | ✓ |
| Dedicated plan (235-06 Ticket-Processing Re-Proof) | 6th plan covering only 232.1 surface. Breaks 5-plan shape. | |
| Sub-section in RNG-01/02 + TRNX-01 only | Only RNG + TRNX treat ticket processing explicitly. | |

**User's choice:** Dedicated plan sub-section per-requirement (Recommended).

### HEAD anchor

| Option | Description | Selected |
|--------|-------------|----------|
| Current HEAD at phase start (Recommended) | Resolve SHA when planning starts, lock in every plan's frontmatter. | ✓ |
| Per-plan HEAD | Each plan resolves HEAD at its own execution time. | |
| Pre-232.1 HEAD baseline | Anchor to pre-232.1 HEAD. Would exclude 232.1 fixes — contradicted by user intent. | |

**User's choice:** Current HEAD at phase start (Recommended).

---

## Addendum (c2e5e0a9 + 314443af) treatment

### Addendum RNG-01 (backward-trace)

| Option | Description | Selected |
|--------|-------------|----------|
| Full per-site backward-trace (Recommended) | Each of the 17 sites is a new RNG CONSUMER. | ✓ |
| Equivalence-class proof | Prove cryptographic equivalence at representative site, cite for others. | |
| Hardening-only equivalence + spot-check | Treat all 17 as hardening of existing consumers. | |

**User's choice:** Full per-site backward-trace (Recommended).

### Addendum RNG-02 (commitment-window)

| Option | Description | Selected |
|--------|-------------|----------|
| Full enumeration per site (Recommended) | For each addendum site, enumerate player-controllable state reads. | ✓ |
| Inherit from old XOR sites | Cite v25.0 Phase 215 proofs for the XOR-equivalent sites. | |
| Sample + generalize | Enumerate 3-5 representative sites, generalize. | |

**User's choice:** Full enumeration per site (Recommended).

### 314443af _raritySymbolBatch keccak-seed fix

| Option | Description | Selected |
|--------|-------------|----------|
| Included in RNG-01/02 + cross-cite 232.1 (Recommended) | Diffusion audited fresh; non-zero-entropy cross-cited from 232.1-03. | ✓ |
| Dedicated audit slice in RNG-01 | Full independent re-audit including availability + diffusion. | |
| Cited as 230-02 addendum verdict | Rely on Phase 230's self-audit only. | |

**User's choice:** Included in RNG-01/02 + cross-cite 232.1 (Recommended).

---

## TRNX-01 audit depth

### Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Medium: invariant + state-path enumeration (Recommended) | rngLocked invariant + enumerate state mutations in the packed window. | ✓ |
| Narrow: IM-21 deletion + end-state equivalence | Verify catalog row + next downstream _unlockRng reaches same end state. | |
| Broad: full housekeeping-window re-audit | Re-audit every function inside the packed window on all paths. | |

**User's choice:** Medium: invariant + state-path enumeration (Recommended).

### rngLocked invariant (the REAL invariant)

| Option | Description | Selected |
|--------|-------------|----------|
| rngLocked gate at every ticket-producing site (Recommended) | Every ticket-producing entry must be blocked during the rngLocked window. | (presented; user corrected) |
| Entry-point gate only (advanceGame) | Only verify advanceGame entry gates. | |
| Cite 232.1 Plan 02 invariant test + augment | Cite forge test + audit only new invariant. | |

**User's free-text response (selected "Other"):** "rnglocked doesn't need to block ticket queues, there is a read and write bufffer. it needs to block far future ticket queues only and to never write to the active buffer"

**Captured decision:** rngLocked does NOT block ticket queueing in general. There are TWO ticket buffers (read-side / active, write-side / future). rngLocked blocks (a) far-future ticket queue writes, and (b) any write to the active (read-side) buffer. Normal writes to the write-side buffer at the current level are permitted during the rngLocked window — they drain next round.

### Invariant confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Exactly as reflected (Recommended) | D-11 statement as presented. | ✓ |
| With one addition | User specifies additional clause. | |
| Different framing needed | Free-text rewrite. | |

**User's choice:** Exactly as reflected (Recommended).

### Active buffer mapping

| Option | Description | Selected |
|--------|-------------|----------|
| lootboxRngWordByIndex[LR_INDEX] / read-side at current LR_INDEX (Recommended) | Bound via the in-flight VRF word at LR_INDEX. | (presented; user provided corrected mapping) |
| Different mapping | Free-text mapping. | |

**User's free-text response (selected "Other"):** "there is a read buffer and a write bufffer for actually producing the final tickets. it swaps when an rng is requested"

**Captured decision (D-12):** Read buffer + write buffer for final ticket production. Swap fires at RNG REQUEST TIME (not at fulfillment). TRNX-01 plan cites the swap site concretely.

### Paths traced end-to-end (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Normal path (Recommended) | jackpot-phase day N → packed housekeeping → purchase-phase day 1 next level. | ✓ |
| Gameover path (Recommended) | Game-over during jackpot phase; housekeeping runs or is skipped correctly. | ✓ |
| Skip-split path (Recommended) | Jackpot-phase skip-split variant; no missed / double unlock. | ✓ |
| Phase-transition freeze (Recommended) | phaseTransitionActive branch at AdvanceModule:283; no _unlockRng inside. | ✓ |

**User's choice:** All four paths selected.

---

## Claude's Discretion

- Exact per-plan file-naming convention for evidence files (if any plan needs a dedicated sub-artifact like `215-02-BACKWARD-TRACE.md` or `216-01-ETH-CONSERVATION.md`) — defer to planner judgment based on scope size at plan time.
- Whether Plan 235-01 CONS-01 should use an algebraic-per-pool proof vs a global invariant vs both (Phase 216 D-03 used algebraic; planner may pick the format that fits the DELTA scope best).
- How to structure the 232.1 ticket-processing impact sub-section (prose / table / per-revision-entry) — defer to planner.

## Deferred Ideas

- Regression sweep of v25.0 / v26.0 / v27.0 findings → Phase 236 REG-01/REG-02.
- Findings severity classification + F-29-NN ID assignment → Phase 236 FIND-01/02/03.
- Test-coverage gap remediation (READ-only phase per D-17).
- Off-chain ABI regeneration routing → Phase 236 if surfaced.
- Standalone gas-only phase (out of scope per PROJECT.md).
- Contracts unchanged since v27.0 (out of scope — no delta).
- CONS-02 BurnieCoin scope breadth — not discussed in detail; planner surfaces at plan review if scope needs adjustment.
- Conservation-proof format (algebraic vs change-set table) — not discussed in detail; defaulting to Phase 216 precedent.
