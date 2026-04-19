# Phase 238: Backward & Forward Freeze Proofs (per consumer) — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 238-backward-forward-freeze-proofs
**Mode:** Auto-decided via Phase 235 / Phase 237 precedents (user directive: "run all the parallel shit you can")
**Areas discussed:** Plan split, Evidence shape, Actor taxonomy, Evidence reuse, KI/gameover handling, Gating taxonomy, Finding-ID emission, Output shape, Scope-guard handoff

---

## Plan Split & Wave Topology

| Option | Description | Selected |
|--------|-------------|----------|
| 6 plans, one per requirement | BWD-01, BWD-02, BWD-03, FWD-01, FWD-02, FWD-03 each gets its own plan | |
| 5 plans, per-consumer-family split | daily (91) / mid-day-lootbox (19) / gap-backfill (3) / gameover-entropy (7) / other (26) — each covers BWD+FWD exhaustively | |
| 4 plans, per-consumer-family (gap+other merged) | daily / mid-day-lootbox / gameover / gap+other — better family-size balance | |
| 3 plans, requirement-group split (Wave 1: BWD, FWD-01/02 parallel; Wave 2: FWD-03 + consolidate) | Matches Phase 237 Wave 1/Wave 2 pattern; floor of ROADMAP "3-5 plans" | ✓ |
| 2 plans, BWD + FWD bundled | Minimum split; sacrifices FWD-03 gating clarity | |

**Auto-decided choice:** 3 plans, requirement-group split, 2 waves
**Rationale:** Maximizes parallelism per user directive (238-01 BWD + 238-02 FWD-01/02 concurrent in Wave 1; 238-03 FWD-03+consolidation in Wave 2). Matches Phase 237 wave shape exactly (inverted: Phase 237 had 01 solo Wave 1, 02+03 Wave 2 parallel; Phase 238 has 01+02 Wave 1 parallel, 03 Wave 2). Family-split rejected because it would fragment BWD/FWD evidence across files and break Consumer Index `ALL` mapping.

---

## BWD Tabular Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Per-row narrative | Prose verdict per row | |
| Tabular with shared-prefix chain dedup | 146-row table, shared-prefix body text grouped via Chain sub-tables | ✓ |
| Tabular no dedup | Full body text per row (larger file, simpler grep) | |
| Mermaid diagrams per consumer | Visual call-graph per row | |

**Auto-decided choice:** Tabular with shared-prefix chain dedup (D-04)
**Rationale:** Matches Phase 235 D-07 precedent + Phase 237 Plan 03 6-chain dedup pattern (130 of 146 rows dedupeable). Grep-friendly per Phase 237 D-09. Mermaid rejected per 237 D-09 no-mermaid convention.

---

## FWD Tabular Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Same shape as BWD, inverted perspective | Forward-view mirror of D-04 table columns | ✓ |
| Per-consumer narrative | Prose enumeration per row | |
| Split FWD-01 (enumeration) from FWD-02 (adversarial closure) | Two tables, one per sub-requirement | |

**Auto-decided choice:** Same shape, inverted perspective (D-05)
**Rationale:** Matches Phase 235 D-08 commitment-window table shape; keeps FWD-01 and FWD-02 on the same row for per-consumer auditability. Splitting would fragment evidence.

---

## Actor Taxonomy (BWD-03 / FWD-02)

| Option | Description | Selected |
|--------|-------------|----------|
| 3 actors: player / admin / validator | REQUIREMENTS.md BWD-03 literal wording | |
| 4 actors: player / admin / validator / VRF oracle | Adds Chainlink VRF coordinator as explicit actor class | ✓ |
| 5 actors: + protocol contract (cross-function reentrancy) | Adds contract-self as explicit actor | |

**Auto-decided choice:** 4 actors (D-07)
**Rationale:** REQUIREMENTS.md BWD-03 lists "player, admin, or validator" but the accepted Chainlink VRF trust model (14-day prevrandao fallback KI EXC-02 as escape hatch for indefinite withholding) makes VRF oracle a material actor that belongs in the taxonomy. Protocol-self reentrancy is covered under the `player` class via msg.sender-controlled callback paths and does not need a separate row.

---

## Evidence Reuse (fresh vs reuse)

| Option | Description | Selected |
|--------|-------------|----------|
| Pure fresh-eyes, no cross-cite | Fully re-derive every verdict, ignore prior-milestone artifacts | |
| Fresh re-prove + cross-cite prior with re-verify-at-HEAD note | Every verdict re-derived at HEAD `7ab515fe`; prior verdicts corroborating-only with re-verification mark | ✓ |
| Reuse prior verdicts verbatim | Cite without re-derivation | |

**Auto-decided choice:** Fresh re-prove + cross-cite (D-09/D-10)
**Rationale:** Matches Phase 235 D-03/D-04 precedent exactly. ROADMAP's fresh-eyes mandate demands re-derivation; cross-cites catch regression without replacing first-principles proof. Contract tree unchanged since v29.0 `1646d5af` (all post-v29 commits docs-only), so re-verification is mechanical.

---

## KI-Exception & Gameover Scope Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude KI-exception rows from Phase 238 | Phase 241 EXC-01..04 handles exceptions; Phase 238 covers 124 non-exception rows | |
| Include KI-exception rows with EXCEPTION verdict, no re-litigation | Phase 238 audits all 146 rows; EXC rows get `EXCEPTION (KI: <header>)` verdict | ✓ |
| Include with full re-litigation | Phase 238 re-proves the 4 KI exceptions from first principles | |

**Auto-decided choice:** Include with EXCEPTION verdict, no re-litigation (D-11/D-12)
**Rationale:** Matches Phase 237 D-06 inventory inclusion pattern. Phase 238 owns the freeze-proof posture consistent with the KI envelope; Phase 241 owns the acceptance re-verification. Preserves "inventory is the scope definition" invariant — 146 rows in, 146 rows out. Gameover-flow rows (19) same pattern: Phase 238 per-consumer freeze, Phase 240 gameover-jackpot overlay.

---

## Gating Taxonomy (FWD-03 named gates)

| Option | Description | Selected |
|--------|-------------|----------|
| Open taxonomy | Gate cell is free-text | |
| 4-value closed taxonomy per ROADMAP | `rngLocked` / `lootbox-index-advance` / `phase-transition-gate` / `semantic-path-gate` | ✓ |
| 5+ values including library-level gates | Adds `library-pure-function-no-state` as a 5th value | |

**Auto-decided choice:** 4-value closed taxonomy (D-13)
**Rationale:** ROADMAP Phase 238 Success Criterion 4 names exactly these 4 gates; REQUIREMENTS.md FWD-03 matches. Rows outside the taxonomy are `CANDIDATE_FINDING` per D-14, which is the correct first-principles escape valve without opening the taxonomy.

---

## Finding-ID Emission

| Option | Description | Selected |
|--------|-------------|----------|
| Emit F-30-NN IDs in Phase 238 | Phase 238 assigns stable IDs with severity | |
| No F-30-NN emission; candidate pool for Phase 242 | Phase 238 produces verdicts + Finding Candidates; Phase 242 owns IDs | ✓ |

**Auto-decided choice:** No F-30-NN emission (D-15)
**Rationale:** Matches Phase 237 D-15 + Phase 235 D-14 + Phase 230 D-06 pattern across 3 prior phases. Consolidation phase (Phase 242 FIND-01/02/03) owns ID assignment and severity classification.

---

## Output Shape

| Option | Description | Selected |
|--------|-------------|----------|
| One consolidated file per plan (3 files total) | 238-01-BWD.md, 238-02-FWD.md, 238-03-GATING.md; no master file | |
| 3 plan files + final consolidated `audit/v30-FREEZE-PROOF.md` | Per-plan + master merge | ✓ |
| One master file only | No per-plan intermediate files | |

**Auto-decided choice:** 3 plan files + final consolidated (D-16)
**Rationale:** Matches Phase 237 D-08 single-consolidated-deliverable pattern. Per-plan files allow parallel execution + Wave 1/Wave 2 reviewability; master file gives downstream Phase 239/240/241/242 a single anchor for cross-cites.

---

## Scope-Guard Handoff

| Option | Description | Selected |
|--------|-------------|----------|
| Edit Phase 237 inventory in place on discovery | 238 edits 237 output if new consumer found | |
| Scope-guard deferral rule (Phase 237 READ-only) | 238 records deferrals in plan SUMMARY, Phase 242 intake | ✓ |

**Auto-decided choice:** Scope-guard deferral rule (D-18)
**Rationale:** Inherits Phase 237 D-16 / Phase 235 D-15 / Phase 230 D-06 deferral rule across the milestone. Prevents catalog drift and provides clean Phase 242 intake path.

---

## Claude's Discretion (not locked, planner's call)

- Shared-prefix chain grouping threshold (237-03 used ~6-chain / 130-row dedup; planner may tune)
- Row ordering within 238-01/02/03 deliverables (path-family-sorted vs Row-ID-sorted vs consumption-file-sorted)
- Whether 238-03 adds a "gate coverage heatmap" (gate × family) as a readability aid
- Whether Finding Candidates severities are pre-classified in 238 or left as `SEVERITY: TBD-242`
- Whether 238-03 cross-cites Phase 239's RNG state-machine proof explicitly (conditional on Phase 239 commit ordering)

---

## Deferred Ideas Noted For Later

- Phase 239 RNG-01/RNG-03 re-proof → cross-cite or audit-assumption fallback
- Phase 240 GO-01..05 gameover-jackpot overlay (distinct from Phase 238 per-consumer freeze)
- Phase 241 EXC-01..04 KI-acceptance re-verification (distinct from Phase 238 EXCEPTION verdicts)
- Phase 242 FIND-01/02/03 ID assignment + severity classification
- Automated invariant runner (Foundry/Halmos) — future milestone, out of v30.0 scope
- Row-count divergence investigation on shared-prefix chains
- Gate-taxonomy expansion if CANDIDATE_FINDING surfaces out-of-taxonomy gate
- Off-chain consumer drift → Phase 242 FIND-02 regression appendix route
