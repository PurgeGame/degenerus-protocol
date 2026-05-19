# Phase 299: Fix Recommendation Document (FIXREC) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning
**Posture:** AUDIT-ONLY repurpose per `D-43N-AUDIT-ONLY-01` (user-authorization 2026-05-18). Pre-pivot structural-elimination contract changes deferred to v44.0 FIX-MILESTONE.

<domain>
## Phase Boundary

Pure-analysis phase that consumes Phase 298 `.planning/RNGLOCK-CATALOG.md` §16 verdict-matrix VIOLATION rows and produces `.planning/RNGLOCK-FIXREC.md` with one analytical entry per VIOLATION tuple. Each entry covers: (a) design-intent backward-trace per `feedback_design_intent_before_deletion.md` citing the original phase that introduced the slot/writer; (b) actor game-theory walk (who exploits, how, EV magnitude); (c) recommended remediation tactic from the (a/b/c/d) menu with full rationale + bytecode/storage-layout/public-ABI impact estimate; (d) v44.0 FIX-MILESTONE handoff anchor `D-43N-V44-HANDOFF-NN` (one per VIOLATION) + cross-reference to RNGLOCK-CATALOG.md verdict-matrix row. Single AGENT-COMMITTED artifact bundle. **Zero `contracts/` + `test/` mutations** per audit-only posture. Replaces the pre-pivot Structural Fix Wave (FIX-01..05 contract changes deferred to v44.0). Requirements FIXREC-01..05 (5).

</domain>

<decisions>
## Implementation Decisions

### FIXREC Artifact Structure

- **D-299-FIXREC-LAYOUT-01:** **Per-VIOLATION analytical entry table** in `.planning/RNGLOCK-FIXREC.md`. Sections:
  - §0 — Executive Summary (VIOLATION count by recommended tactic; design-intent-trace coverage; v44.0 handoff anchor count)
  - §1..§N — One section per CATALOG VIOLATION (numbered per RNGLOCK-CATALOG.md §16 verdict-matrix row order). Each section contains 4 sub-sections:
    - **§N.A — Design-intent backward-trace** (FIXREC-02): cite original phase that introduced the slot/writer with file:line; document why the slot exists + what behavior would break if naively gated
    - **§N.B — Actor game-theory walk** (FIXREC-03): exploit-actor class (player / MEV bot / admin / external contract); specific action sequence during rngLock window; EV magnitude estimate (LOW / MEDIUM / HIGH / CATASTROPHE-tier); economic-likelihood disposition
    - **§N.C — Recommended tactic + rationale** (FIXREC-01 + FIXREC-04): selected tactic from (a/b/c/d) menu + full rationale + bytecode/storage-layout/public-ABI impact estimate per `D-298-RECOMMEND-DEPTH-01` extended to per-VIOLATION depth
    - **§N.D — v44.0 handoff anchor** (FIXREC-05): locked-decision ID `D-43N-V44-HANDOFF-NN` + file:line cite + cross-reference to RNGLOCK-CATALOG.md verdict-matrix row
  - §M — v44.0 FIX-MILESTONE consolidated handoff register (deduplicated `D-43N-V44-HANDOFF-NN` ID list + per-ID summary line for v44 plan-phase consumption)

  **Why:** Per-VIOLATION depth (vs Phase 298 catalog's 1-line rationale) is the load-bearing differentiator of FIXREC — v44.0 FIX-MILESTONE consumes these entries directly as plan-phase input. Design-intent + actor-walk + impact-estimate per VIOLATION matches `feedback_design_intent_before_deletion.md` discipline (Phase 281 owed-salt + Phase 288 dailyIdx + Phase 294 DPNERF + Phase 296 RETRY_LOOTBOX_RNG design-intent traces are the precedents). **How to apply:** Plan-phase 299 authors a sub-agent prompt template that iterates over `RNGLOCK-CATALOG.md` §16 VIOLATION rows + produces one §N entry per row. N parallel sub-agents (N = VIOLATION row count from CATALOG output) per `D-299-EXEC-SHAPE-01`.

- **D-299-EXEC-SHAPE-01:** **N parallel sub-agents per VIOLATION + main-context integration** (N = CATALOG §16 VIOLATION row count). Each sub-agent: reads its assigned VIOLATION row from RNGLOCK-CATALOG.md + walks the design-intent backward-trace by reading the prior-phase CONTEXT/DESIGN-INTENT-TRACE artifacts cited in the catalog's `Recommended tactic | Rationale` columns + authors the 4-sub-section §N entry. Main-context: integrates per-VIOLATION outputs into FIXREC.md §1..§N + authors §0 summary + §M consolidated handoff register. **Why:** Mirrors `D-298-EXEC-SHAPE-01` parallel-sub-agents discipline; per-VIOLATION isolation keeps per-agent context tractable. If N is small (≤ 5), main-context may absorb the work end-to-end at plan-phase discretion.

### Claude's Discretion (planner & executor latitude)

- **D-299-WAVE-SHAPE-01 — Single AGENT-COMMITTED FIXREC artifact bundle.** Audit-only posture per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + `test/` mutations. Bundle includes `.planning/RNGLOCK-FIXREC.md` + per-VIOLATION sub-agent outputs at `.planning/phases/299-*/299-violation-NN-{slug}.md` + planning artifacts.

- **D-299-RESEARCH-AGENT-01 — Plan-phase skips research-agent dispatch.** Methodology fully locked by this CONTEXT.md + REQUIREMENTS FIXREC-01..05 + Phase 298 catalog output. No research needed.

- **D-299-KI-01 — KNOWN-ISSUES.md UNMODIFIED.** Phase 303 TERMINAL handles per `D-43N-KI-01`.

- **D-299-SUB-AGENT-PROMPT-01 — Per-VIOLATION sub-agent prompt template (planner finalizes):**
  ```
  Task: Author FIXREC entry §N for VIOLATION row at .planning/RNGLOCK-CATALOG.md §16 row {NN} — (slot={SLOT}, writer={WRITER_FN}, callsite={CALLSITE_FILE_LINE}).
  Output: 4 sub-sections (§N.A design-intent backward-trace + §N.B actor game-theory walk + §N.C recommended tactic + rationale + impact estimate + §N.D v44.0 handoff anchor).
  Read-only: do NOT modify contracts/ or test/. Output to .planning/phases/299-*/299-violation-{NN}-{slug}.md.
  Design-intent backward-trace MUST cite the original phase that introduced the slot/writer (grep .planning/milestones/ for prior CONTEXT/DESIGN-INTENT-TRACE artifacts).
  ```

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 299 Anchors
- `.planning/ROADMAP.md` — Phase 299 entry (FIXREC analysis-only repurpose); v43.0 milestone goal + `D-43N-AUDIT-ONLY-01` pivot prose
- `.planning/REQUIREMENTS.md` — FIXREC-01..05 verbatim (lines updated post-pivot); v44.0 FIX-MILESTONE handoff register reference
- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md` — Phase 298 CATALOG context + 8 locked decisions D-298-* (consumed by FIXREC)
- `.planning/RNGLOCK-CATALOG.md` (TO BE PRODUCED by Phase 298) — load-bearing input; §16 verdict-matrix VIOLATION rows drive FIXREC §N count

### Methodology Feedback Memory
- `feedback_design_intent_before_deletion.md` — trace original design intent + actor game-theory BEFORE recommending tactic. Load-bearing discipline for §N.A backward-trace.
- `feedback_no_history_in_comments.md` — FIXREC entries describe what IS (recommended state + current VIOLATION state), not what changed.

### Design-Intent Backward-Trace Source Anchors (per-VIOLATION cite candidates)
- `.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md` — owed-salt 4th-keccak-input invariant (tactic-b snapshot precedent)
- `.planning/milestones/v41.0-phases/288-*/` — `dailyIdx` structural anchor (tactic-b snapshot precedent)
- `.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` — owed-in-baseKey collapse design rationale
- `.planning/milestones/v42.0-phases/292-hero-override-weighted-roll-hrroll/292-01-DESIGN-INTENT-TRACE.md` — leader-bonus + rngLocked window design
- `.planning/milestones/v42.0-phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md` — DPNERF caller-uniform discipline
- `.planning/milestones/v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md` — RETRY_LOOTBOX_RNG domain separation (`D-42N-RETRY-RNG-DOMAIN-SEP-01`)

### v44.0 FIX-MILESTONE Forward Handoff
- v44.0 plan-phase consumes `.planning/RNGLOCK-FIXREC.md` §M consolidated handoff register + per-VIOLATION §N.D anchors. One v44.0 sub-phase per FIXREC entry OR per-slot grouping per v44 plan-phase discretion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 287 JPSURF §0 R2-snapshot 1-line rationale pattern** — extended to per-VIOLATION depth at FIXREC §N.C
- **Phase 281 + Phase 288 + Phase 294 design-intent-trace artifact format** — per-VIOLATION §N.A inherits this shape
- **`RngLocked` custom error pattern** (MintModule:1221 / BurnieCoinflip:730 / sStonk:492) — tactic-(a) gated-revert recommendations cite this implementation pattern

### Established Patterns
- **Per-VIOLATION analytical entry depth** — exceeds Phase 287 JPSURF 1-line rationale; matches Phase 281/288/294 design-intent-trace artifact density
- **AGENT-COMMITTED analysis bundle** — Phase 287 + Phase 296 + Phase 298 precedent

### Integration Points
- **Phase 298 → Phase 299**: RNGLOCK-CATALOG.md §16 VIOLATION row count drives FIXREC §N count
- **Phase 299 → Phase 303**: §3.D Phase 299 FIXREC summary roll-up in FINDINGS-v43.0.md
- **Phase 299 → v44.0**: §M consolidated handoff register is v44.0 plan-phase input

</code_context>

<specifics>
## Specific Ideas

- **Per-VIOLATION sub-agent prompt template** — explicit `Read RNGLOCK-CATALOG.md §16 row NN` anchor; explicit `grep .planning/milestones/` instruction for design-intent backward-trace; explicit output file path convention
- **v44.0 handoff anchor ID convention** — `D-43N-V44-HANDOFF-NN` where NN matches the FIXREC §N section number; consolidated in §M register

</specifics>

<deferred>
## Deferred Ideas

- **Per-VIOLATION verification proofs (replay test that VIOLATION reproduces)** — defer to v44.0 FIX-MILESTONE plan-phase; v44.0 sub-phase tests assert VIOLATION reproduces pre-fix + freeze invariant holds post-fix
- **Cross-VIOLATION pattern aggregation** (e.g., "8 VIOLATIONs all resolve via tactic-b snapshot") — note in §0 summary but don't restructure §N entries; v44.0 plan-phase may group by tactic at sub-phase planning

</deferred>

---

*Phase: 299-Fix-Recommendation-Document-FIXREC*
*Context gathered: 2026-05-18*
