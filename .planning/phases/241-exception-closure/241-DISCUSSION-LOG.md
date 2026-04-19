# Phase 241: Exception Closure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 241-exception-closure
**Areas discussed:** EXC-01 ONLY-ness proof methodology

---

## Gray Area Selection

Six gray areas were surfaced for Phase 241; user selected 1 for discussion.

| Gray Area | Description | Selected |
|-----------|-------------|----------|
| Plan split, waves & output shape | 1 consolidated plan vs. 2 paired plans vs. 4 plans + output file shape | |
| EXC-01 ONLY-ness proof methodology | Universal-claim proof strategy for the sole-non-VRF-consumer claim | ✓ |
| EXC-02/03/04 re-verification depth | Cite Phase 240 vs. fresh re-derive vs. hybrid | |
| Forward-cite discharge + residuals | Line-item discharge per Phase 239 D-29 vs. no-discharge per Phase 240 D-32 vs. bidirectional | |

**User's choice:** Only "EXC-01 ONLY-ness proof methodology". Others defaulted to Claude's Discretion (resolved in CONTEXT.md D-01..D-03, D-10, D-11, D-22, D-23).

---

## EXC-01 ONLY-ness Proof Methodology

### Q1 — Proof Methodology

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid (Recommended) | Exhaustive 146-row Phase 237 Consumer Index walk + independent negative-space grep over contract tree, both as co-equal warrants | |
| Inventory-walk only (lighter) | Walk Phase 237 146-row Consumer Index with per-row seed verdict; grep not required as warrant | ✓ |
| Negative-space grep only | Source-centric — grep every non-VRF surface and classify each match | |

**User's choice:** Inventory-walk only (lighter).
**Notes:** Signals lighter proof effort; Phase 237 inventory is authoritative. Reconciled with Q4 via follow-up: grep runs as sanity backstop, not co-equal warrant.

### Q2 — Non-VRF Entropy Surfaces Universe

| Option | Description | Selected |
|--------|-------------|----------|
| Full block-context + derived (Recommended) | Exhaustive theoretical surface (block.*/blockhash/tx.origin/packed counters/keccak-over-non-VRF) | |
| ROADMAP-literal set | Only surfaces ROADMAP SC-1 names (block.timestamp, block.number, packed counters, etc.) | |
| KNOWN-ISSUES-aligned set | Only surfaces KI EXC-01 names specifically | |

**User's choice:** "Other" free-form — *"I know we aren't using shitty randomness. not worried about that. just worried about exploitability"*.
**Notes:** Reframes the ENTIRE Phase 241 scope: distribution quality / randomness theory is NOT re-litigated. Player-reachable exploitability paths are the focus. This decision scopes the grep backstop surface universe (D-07) to player-reachable non-VRF reads and scopes all 4 EXC re-verifications to exploitability predicates (D-05).

### Q3 — Scope Treatment of Other 3 KIs

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit exclude + cite (Recommended) | EXC-01 claim excludes EXC-02/03/04 with explicit citations | |
| Narrow scope per ROADMAP wording | Treat EXC-02/03/04 as out-of-scope for EXC-01 | |
| Fold all 4 KIs into one ONLY-ness claim | Single consolidated universal claim covers all 4 KI exceptions in one table | ✓ |

**User's choice:** Fold all 4 KIs into one ONLY-ness claim.
**Notes:** Drives D-06 — single 22-row consolidated ONLY-ness table covering 2 EXC-01 + 8 EXC-02 + 4 EXC-03 + 8 EXC-04. Set-equal with Phase 238 22-EXCEPTION count (Gate A verification target).

### Q4 — Closure Gate Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Dual-gate: set-equality + grep-closure (Recommended) | Gate A Phase 237 inventory set-equality + Gate B grep-closure on non-VRF surfaces | ✓ |
| Set-equality gate only | Gate A only (Phase 237 inventory) | |
| Grep-closure gate only | Gate B only (source-centric) | |

**User's choice:** Dual-gate.
**Notes:** Apparent tension with Q1 (inventory-walk only). Resolved via follow-up — grep is sanity backstop, inventory-walk carries primary warrant. See D-04, D-08.

---

## Follow-up Clarifications

### Follow-up 1 — Exploitability Frame

| Option | Description | Selected |
|--------|-------------|----------|
| Player-reachable only (Recommended) | Focus on seed reads with player-reachable manipulation paths | ✓ |
| Any-actor reachable | Include player + admin + validator + VRF-oracle | |
| Source-centric (no actor model) | Pure source enumeration regardless of reachability | |

**User's choice:** Player-reachable only.
**Notes:** Confirms Q2 free-form — admin/validator/VRF-oracle surfaces land with verdict `NOT_PLAYER_REACHABLE_OUT_OF_SCOPE`. Matches Phase 240 D-13 player-centric + non-player-narrative pattern.

### Follow-up 2 — Backstop Grep Role

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — grep as sanity backstop (Recommended) | Inventory walk is warrant; grep runs as cheap cross-check | ✓ |
| No — grep and inventory are co-equal warrants | Either gate surfacing a mismatch blocks ONLY-ness closure | |

**User's choice:** Yes — grep as sanity backstop.
**Notes:** Reconciles Q1 (inventory-walk only) + Q4 (dual-gate). Grep surfacing an unknown seed routes to scope-guard deferral + Phase 242 FIND-01, does NOT retroactively amend Phase 237. Matches Phase 240 D-31 scope-guard-deferral precedent.

### Follow-up 3 — Proceed to Context

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context | Close EXC-01 discussion; other areas default to Claude's Discretion | ✓ |
| More questions on EXC-01 | Continue drilling into EXC-01 details | |
| Explore more gray areas | Open plan split / re-verification depth / forward-cite discharge discussions | |

**User's choice:** Ready for context.
**Notes:** Plan split, re-verification depth, output shape, and forward-cite discharge defaulted to Claude's Discretion with precedent-based defaults:
- Plan split → single consolidated plan (ROADMAP option)
- Output shape → single `audit/v30-EXCEPTION-CLOSURE.md` (237/238/240 pattern)
- EXC-02/03/04 re-verification depth → hybrid (cite Phase 240 + re-derive predicates fresh at HEAD)
- Forward-cite discharge → explicit line-item per Phase 239 D-29 precedent (29 discharge entries for Phase 240's 17 EXC-02 + 12 EXC-03 forward-cites)
- Row-ID prefix → `EXC-241-NNN` single-prefix convention

---

## Claude's Discretion (defaulted per precedent)

- Plan split, waves & output shape (D-01 / D-02 / D-03 / D-22 / D-24)
- EXC-02/03/04 re-verification depth (D-10)
- Forward-cite discharge structure (D-11)
- Row-ID taxonomy + closed-verdict sets (D-23 / D-09 / D-10)
- Fresh-eyes + cross-cite discipline inheritance (D-12 / D-13)
- Scope boundary inheritance from Phase 240 D-29/D-30/D-31 (D-25 / D-26 / D-27)

## Deferred Ideas

- Fresh XOR-shift distribution analysis (user explicitly out-of-scope per Q2)
- Admin/validator/VRF-oracle-reachable non-VRF seed enumeration (player-only per Follow-up 1)
- Regression verdicts against prior-milestone findings (Phase 242 REG-01/02)
- F-30-NN finding ID emission (Phase 242 FIND-01/02/03)
- KNOWN-ISSUES.md edits (Phase 242 FIND-03)
