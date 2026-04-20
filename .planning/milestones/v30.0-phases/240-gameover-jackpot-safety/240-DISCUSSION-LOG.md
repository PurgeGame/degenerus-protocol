# Phase 240: Gameover Jackpot Safety - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 240-gameover-jackpot-safety
**Areas discussed:** GO-02 prevrandao + attacker model, GO-03 + GO-05 evidence shape, Phase 241 handshake

---

## Gray Area Selection (multiSelect)

| Option | Description | Selected |
|--------|-------------|----------|
| Plan split + file structure | How many plans (ROADMAP says 2-3), grouping of GO-01..05, deliverable shape (single consolidated `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` vs 237/238-style per-plan + consolidated vs 239-style multi-file). | |
| GO-02 prevrandao + attacker model | How the 8 prevrandao-fallback rows are handled on GO-02's VRF-available branch (EXCLUDED vs EXCEPTION vs forward-cite to 241 EXC-02) AND which actors are in GO-04 trigger-timing closure. | ✓ |
| GO-03 + GO-05 evidence shape | Granularity for GO-03 state-variable enumeration (per-variable vs per-consumer vs both) AND GO-05 F-29-04 containment proof approach (inventory-disjointness vs state-variable-disjointness vs both). | ✓ |
| Phase 241 handshake | How Phase 240 and Phase 241 coordinate on parallel execution overlap (prevrandao / F-29-04 acceptance): strict boundary with forward-cites, duplicate re-verification, or deferred-to-241. | ✓ |

**User selected:** GO-02 prevrandao + attacker model, GO-03 + GO-05 evidence shape, Phase 241 handshake.
**Plan split + file structure** NOT selected → Claude's Discretion default: 3 plans per ROADMAP literal grouping, 2-wave topology (240-01 + 240-02 parallel in Wave 1; 240-03 solo in Wave 2 with consolidation), single consolidated `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` deliverable per ROADMAP literal wording + 3 per-plan intermediate files (237/238 pattern).

---

## GO-02 Prevrandao

| Option | Description | Selected |
|--------|-------------|----------|
| EXCEPTION verdict (238 pattern) (Recommended) | All 19 gameover-flow rows in scope; 8 prevrandao-fallback rows carry `EXCEPTION (KI: EXC-02)`. Matches 238 FREEZE-PROOF 22-EXCEPTION pattern. | ✓ |
| Excluded from GO-02 (11 rows) | GO-02 scope = 11 rows (7 gameover-entropy + 4 F-29-04); 8 prevrandao rows explicitly out of Phase 240. | |
| Forward-cite to Phase 241 EXC-02 | GO-02 table includes 8 rows with verdict cell = `See Phase 241 EXC-02`; no proof emitted in Phase 240. | |

**User's choice:** EXCEPTION verdict (238 pattern).
**Notes:** Matches Phase 238 FREEZE-PROOF structural pattern exactly (22-EXCEPTION / 124-SAFE rhythm carried forward). Reviewer sees all 19 rows in GO-02 table with closed verdicts; no cross-reference to Phase 241 required for inventory completeness. Forward-cite per-row to Phase 241 EXC-02 is added anyway per Phase 241 handshake decision below (strict boundary).

---

## GO-04 Attacker Model

| Option | Description | Selected |
|--------|-------------|----------|
| 4-actor (238 pattern) (Recommended) | player / admin / validator / VRF-oracle — mirrors Phase 238 BWD-03 / FWD-02 closure. Gives complete adversarial closure. | |
| 3-actor (player/admin/validator) | Skip VRF-oracle since prevrandao fallback (KI EXC-02) is accepted. Matches ROADMAP literal wording. | |
| Player-only + narrative note on others | GO-04 focuses on ROADMAP's explicit threat model (attacker ≈ player). Admin/validator/VRF-oracle handled in narrative. | ✓ |

**User's choice:** Player-only + narrative note on others.
**Notes:** Tightest alignment with ROADMAP Success Criterion 4 wording ("an attacker"). Phase 240 GO-04 primary evidence is a player-centric Trigger Surface Table; non-player actors (admin / validator / VRF-oracle) covered in a follow-up narrative paragraph with CLOSED-VERDICT labels per actor (`NO_DIRECT_TRIGGER_SURFACE` / `BOUNDED_BY_14DAY_EXC02_FALLBACK` / `EXC-02_FALLBACK_ACCEPTED`). Divergence from Phase 238 4-actor BWD-03 pattern acknowledged in CONTEXT.md D-11. Planner MUST attest in 240-02-SUMMARY that the narrative delivers closed verdicts per actor (CONTEXT.md D-13). Coverage gap risk routes to Phase 242 FIND-01 pool, NOT a Phase 240 amendment (READ-only-after-commit per D-31).

---

## GO-03 + GO-05 Evidence Shape

| Option | Description | Selected |
|--------|-------------|----------|
| GO-03 dual + GO-05 dual (Recommended) | GO-03: per-variable table + per-consumer cross-walk. GO-05: inventory-disjointness + state-variable-disjointness. Airtight on both axes. | ✓ |
| Per-consumer only (slim) | GO-03: per-consumer 19-row table with aggregate verdict. GO-05: inventory-disjointness only. Leaner; reuses Phase 237/238 row IDs. | |
| Per-variable only (deep) | GO-03: per-variable enumeration exclusively. GO-05: state-variable-disjointness only. Most attack-surface-complete but loses row-ID cross-walk. | |

**User's choice:** GO-03 dual + GO-05 dual.
**Notes:** Dual-table GO-03 = `GOVAR-240-NNN` per-variable table + per-consumer cross-walk to `GO-240-NNN` row IDs. Dual-disjointness GO-05 = inventory-level (row-set disjoint) + state-variable-level (storage-slot disjoint). Combined verdict `BOTH_DISJOINT` iff both sub-proofs `DISJOINT`. This creates a Wave-2 data dependency: Plan 240-03's state-variable-disjointness proof reads Plan 240-02's `GOVAR-240-NNN` table — captured in D-02 wave topology.

---

## Phase 241 Handshake

| Option | Description | Selected |
|--------|-------------|----------|
| Strict boundary with forward-cites (Recommended) | Phase 240 owns VRF-available-branch determinism. Phase 241 owns KI-acceptance re-verification. Forward-cites `See Phase 241 EXC-02/-03` per row. Zero duplication. | ✓ |
| Phase 240 defers both to Phase 241 | Phase 240 skips prevrandao / F-29-04 entirely; defers to Phase 241. Tightest boundary but weakens Phase 240 self-containment. | |
| Both phases re-verify (duplicate) | Phase 240 emits its own prevrandao / F-29-04 verdicts; Phase 241 emits parallel acceptance re-verification. Most redundant but most audit-complete. | |

**User's choice:** Strict boundary with forward-cites.
**Notes:** GO-02's 8 prevrandao rows + 4 F-29-04 rows carry forward-cites to Phase 241 EXC-02 / EXC-03 by path. GO-05 forward-cites Phase 241 EXC-03 for F-29-04 acceptance (GO-05 proves scope containment only). Post-commit reconciliation erratum if Phase 241 structure diverges (no re-edit of Phase 240 files per D-31 READ-only-after-commit). Matches Phase 239-02 → Phase 239-03 forward-cite precedent.

---

## Claude's Discretion (captured in CONTEXT.md)

- Exact ordering of GO-01 table subsections (by row ID vs by path family vs by branch) — planner picks most readable.
- Whether the GO-03 Per-Variable table precedes or follows the Per-Consumer cross-walk — planner picks.
- Whether GO-04 Trigger Surface Table precedes or follows the Non-Player Actor Narrative — planner picks.
- Whether GO-05 Inventory Disjointness or State-Variable Disjointness appears first — planner picks.
- Whether Finding Candidate severities are pre-classified (INFO / LOW / MED / HIGH) or left as `SEVERITY: TBD-242` — planner matches 237/238/239 precedent.
- Whether the consolidated `v30-GAMEOVER-JACKPOT-SAFETY.md` mirrors the 238 FREEZE-PROOF 10-column Consolidated Table format or uses a GO-01..05 per-requirement section layout — planner picks.
- Row ID prefix variants (`GO-240-NNN` vs `GOJP-NNN` vs `GO240-NNN`) — planner picks.
- Whether the GO-04 narrative uses bulleted actor-verdict labels vs prose paragraphs — planner picks.
- Whether Plan 240-01 preserves the raw `grep` commands used for fresh-eyes GO-01 re-derivation — encouraged per 239-02 precedent.

## Deferred Ideas (captured in CONTEXT.md)

- Phase 241 KI-exception acceptance re-verification (EXC-01..04) — Phase 241 scope per strict boundary
- Phase 242 FIND-01/02/03 consolidation + F-30-NN ID assignment — Phase 242 scope
- Non-player-actor deep-dive for GO-04 — future-milestone candidate; any gap routes to Phase 242 FIND-01
- Cross-cycle gameover-VRF chaining audit — out of Phase 240 scope; Phase 242 REG-02 may surface
- Automated invariant runner against GO-01..05 tables — future-milestone candidate (READ-only policy)
- EntropyLib XOR-shift PRNG inside gameover-flow consumers — Phase 241 EXC-04 scope
- Gameover liveness-stall constant recalibration — out of v30.0 scope (constants frozen at HEAD)
- Post-v29 contract-tree divergence — scope addendum trigger per D-29
- Admin-actor gameover-trigger-state deep-dive — Phase 238 BWD-03 / FWD-02 already covers admin
- Gameover-jackpot UX / frontend / indexer determinism — out of v30.0 scope (v28.0 coverage)
