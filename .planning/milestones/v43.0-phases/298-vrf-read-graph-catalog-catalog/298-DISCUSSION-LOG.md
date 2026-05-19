# Phase 298: VRF Read-Graph Catalog (CATALOG) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 298-VRF-Read-Graph-Catalog-CATALOG
**Areas discussed:** Consumer enumeration scope, EXEMPT-ADVANCEGAME reach, Catalog artifact structure, Agent execution shape

---

## Consumer Enumeration Scope

### Question 1 — Is the draft 13-entry VRF-consumer list the locked CAT-01 trace-root scope?

| Option | Description | Selected |
|--------|-------------|----------|
| Take the draft as-is (13 entries) | Lock the 13-entry list verbatim. Includes terminal-jackpot + game-over substitution + BURNIE coinflip + sStonk redemption + decimator. | ✓ |
| Trim game-over surfaces | Carve out entries 3, 4, 5 under EXC-01..03 KI-envelope NEGATIVE-scope carry. | |
| I'll adjust — let me describe | User describes additions/removals/collapses. | |
| You decide | Claude picks default. | |

**User's choice:** Take the draft as-is (13 entries).
**Notes:** Locked verbatim. Terminal-jackpot + game-over substitution paths IN SCOPE despite EXC-01..03 KI-envelope NEGATIVE-scope carry — milestone goal explicitly precludes SAFE_BY_DESIGN dispositions for participating slots.

---

### Question 2 — Trace depth at contract boundaries

| Option | Description | Selected |
|--------|-------------|----------|
| All-source contracts in scope | Trace walks into every contract under contracts/; stops only at external interfaces with no source available. | ✓ |
| Module-boundary stop | Stops at module call boundaries; risks missing cross-module read/write races. | |
| All-source + interface-callback handling | All-source + external EOA-controlled callback writes flagged as VIOLATION-CANDIDATE. | |
| You decide | Claude picks default. | |

**User's choice:** All-source contracts in scope.
**Notes:** SLOADs inside vault / coinflip / sStonk / BURNIE / token contracts during resolution flow are enumerated. Matches v43 milestone goal `Every VRF Input Frozen` literal reading.

---

### Question 3 — Slot classification for non-participating SLOADs

| Option | Description | Selected |
|--------|-------------|----------|
| Two-tier: enumerate all, classify by participation | CAT-02 enumerates every SLOAD (F-41-02/03 precedent). CAT-04 verdict classifies only the subset deriving VRF output. NON-PARTICIPATING rows attested. | ✓ |
| Participating-only | CAT-02 enumerates only SLOADs affecting VRF output; smaller artifact but risks missing F-41-02/03 class. | |
| All-SLOAD strict | Every SLOAD treated as participating until proven otherwise; bigger artifact. | |
| You decide | Claude picks default. | |

**User's choice:** Two-tier: enumerate all, classify by participation.
**Notes:** Preserves both `feedback_rng_window_storage_read_freshness.md` discipline and milestone-goal scope alignment. Phase 287 JPSURF format precedent (`Load-bearing for winner-selection?` column).

---

## EXEMPT-ADVANCEGAME Reach

### Question 1 — Call-graph membership rule for EXEMPT-ADVANCEGAME classification

| Option | Description | Selected |
|--------|-------------|----------|
| Stack-rooted strict | Per-call-site classification: same F can be EXEMPT-ADVANCEGAME at one callsite + VIOLATION at another. | ✓ |
| Per-(slot × writer-function) coarse | Function-level classification; external writers always VIOLATION regardless of value-side effect. | |
| Stack-rooted strict + per-callsite | Same as option 1 with explicit per-callsite row granularity. | |
| You decide | Claude picks default. | |

**User's choice:** Stack-rooted strict.
**Notes:** Captures the Phase 287 JPSURF `_creditClaimable` (advanceGame-stack) vs `claimWinnings()` (EOA-reached) dual-entry-point case. Verdict-matrix keyed on (slot, writer-function, callsite-file-line) tuples.

---

### Question 2 — Cross-contract write classification

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-contract EXEMPT preserved | EXEMPT preserved when callsite traces to EXEMPT stack with source in contracts/. | ✓ |
| Cross-contract VIOLATION | All cross-contract writes VIOLATION regardless of calling stack. | |
| Cross-contract dual-row | Each cross-contract callsite gets EXEMPT + VIOLATION dual rows. | |
| You decide | Claude picks default. | |

**User's choice:** Cross-contract EXEMPT preserved.
**Notes:** EXEMPT classification follows the static call-graph descendancy across contract boundaries provided callee source is under contracts/. Dual-entry-point risk captured via per-callsite from prior question.

---

## Catalog Artifact Structure

### Question 1 — Layout of .planning/RNGLOCK-CATALOG.md

| Option | Description | Selected |
|--------|-------------|----------|
| Per-consumer + per-slot + verdict matrix | §0 summary + §1..§13 per-consumer + §14 unique-slot index + §15 per-slot writer + §16 verdict matrix + §17 CAT-06 attestation. | (Claude default) |
| Single mega verdict matrix | One mega-table sorted by consumer then slot; compact but harder to read per-slot/per-consumer. | |
| Per-module + per-slot organization | Sections by source module; cross-module dedup index. | |
| You decide | Claude picks default. | ✓ |

**User's choice:** You decide → Claude default = option 1 (per-consumer + per-slot + verdict matrix).
**Notes:** Mirrors Phase 287 JPSURF precedent at scaled-up granularity; per-consumer sections preserve trace-context per VRF output surface; unique-slot index + verdict matrix enable Phase 299 FIX sub-phase planning to iterate VIOLATIONs directly.

---

### Question 2 — Remediation tactic recommendation depth per VIOLATION row

| Option | Description | Selected |
|--------|-------------|----------|
| ONE recommended + 1-line rationale | Phase 287 JPSURF §0 R2-snapshot precedent. User has final call at FIX sub-phase approval. | ✓ |
| Ranked menu A>B>C>D + rationale | All 4 tactics ranked with per-tactic 1-line trade-off; richer but heavier authoring lift. | |
| ONE recommended + design-intent backward-cite | Option 1 + cross-cite to Phase 281/288/294/296 etc. per `feedback_design_intent_before_deletion.md` discipline. | |
| You decide | Claude picks default. | |

**User's choice:** ONE recommended + 1-line rationale.
**Notes:** Slimmer artifact; matches Phase 287 §0 precedent. Design-intent backward-cite NOT required at catalog authoring — Phase 299 FIX sub-phase planning re-discovers per `feedback_design_intent_before_deletion.md` at plan-phase time.

---

## Agent Execution Shape

### Question 1 — Decomposition of catalog work across agents

| Option | Description | Selected |
|--------|-------------|----------|
| Main-context end-to-end | Single main-context agent walks all 13 consumers; Phase 287 precedent at larger scale; slowest wall-clock. | |
| Parallel sub-agents per consumer + main integration | 13 parallel sub-agents (one per VRF consumer); main integrates + authors verdict matrix + runs CAT-06 grep gate. | ✓ |
| Parallel sub-agents per module + main integration | ~10 per-module sub-agents; risks cross-module-call coverage gaps. | |
| You decide | Claude picks default. | |

**User's choice:** Parallel sub-agents per consumer + main integration.
**Notes:** ~13× wall-clock speedup vs main-context end-to-end. Per-agent context isolated to one consumer's resolution path; `feedback_verify_call_graph_against_source.md` explicit-enumeration discipline preserved per-agent. Main-context owns cross-consumer slot deduplication + verdict-matrix authoring + CAT-06 grep gate.

---

### Question 2 — CAT-06 grep gate execution

| Option | Description | Selected |
|--------|-------------|----------|
| Main-context self-attestation | Main-context runs the 5 CAT-06 grep patterns as a fresh sweep; same agent that integrates the catalog. | ✓ |
| Independent verification sub-agent | 14th sub-agent runs grep gate + cross-references hits to catalog rows. | |
| Both — main + independent sub-agent | Two-layer attestation; ~2× grep-gate cost. | |
| You decide | Claude picks default. | |

**User's choice:** Main-context self-attestation.
**Notes:** Same-agent grep is `independent` in the sense that it's a fresh sweep with literal CAT-06 patterns, NOT relying on the per-consumer sub-agent enumeration. Per-consumer decomposition already provides one independence layer; main-context self-attestation provides the second.

---

## Claude's Discretion

The user said "You decide" on the following:

- **Catalog artifact structure (D-298-CATALOG-LAYOUT-01):** Claude selected the per-consumer + per-slot + verdict matrix layout (option 1) per Phase 287 JPSURF precedent + downstream Phase 299 sub-phase planning consumption needs.

Additional discretion areas inherited from prior-phase defaults (NOT user-asked):

- **Wave shape (D-298-WAVE-SHAPE-01):** 1 AGENT-COMMITTED catalog artifact bundle; zero contracts/ + test/ mutations. Per ROADMAP + REQUIREMENTS lock.
- **Research-agent dispatch (D-298-RESEARCH-AGENT-01):** Skipped per `feedback_skip_research_test_phases.md` lineage. Methodology locked by feedback memory + REQUIREMENTS.
- **KNOWN-ISSUES.md disposition (D-298-KI-01):** UNMODIFIED at Phase 298; Phase 303 TERMINAL handles per `D-43N-KI-NN` lock at plan-phase 303 time.
- **Per-consumer sub-agent prompt template (D-298-SUB-AGENT-PROMPT-01):** Plan-phase 298 finalizes wording + sub-agent-type selection (Explore vs general-purpose vs Plan).

## Deferred Ideas

- **Independent-verification sub-agent for CAT-06 grep gate** — considered + rejected per cost-vs-coverage trade-off. Revisit if future milestone surfaces a CAT-06 false-negative.
- **Ranked-menu A>B>C>D remediation recommendation** — considered + rejected per slimmer-artifact preference. Revisit if Phase 299 sub-phase planning struggles with tactic-selection.
- **Per-module organization for catalog layout** — considered + rejected. Cross-module dependency visibility favors per-consumer + per-slot.
- **Pre-existing snapshotted slots (Phase 281 owed-salt, Phase 288 dailyIdx) catalog treatment** — NOT explicitly locked at CONTEXT.md authoring. Default = include in catalog + writer enumeration shows snapshot/anchor pattern + verdict classified per standard rules. Plan-phase may surface for explicit attestation.
- **Pre-deployment writers (constructor / initializer)** — NOT explicitly locked. Default = included in CAT-03 if reachable from non-internal entry points. Plan-phase may surface for explicit attestation.
- **OZ-inherited writer row granularity (transfer / transferFrom / approve / _mint / _burn)** — NOT explicitly locked. REQUIREMENTS CAT-03 lists these as in-scope `where applicable`. Default = per-function rows (not collapsed by family) when those functions are reached as writers of participating slots.
