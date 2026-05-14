# Phase 280: Delta Audit + Findings Consolidation (Terminal) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 280-Delta Audit + Findings Consolidation (Terminal)
**Areas discussed:** EXC-04 KI disposition, Plan shape + research skip

---

## Gray-area selection

Four candidate gray areas were presented; the user selected two for discussion. The other two were routed to planner discretion (captured in CONTEXT.md `<decisions>` → Claude's Discretion):
- **BUR-05 deviation handling** (not discussed) — how FINDINGS-v40.0 dispositions Phase 279's +114-byte NET-POSITIVE bytecode override.
- **§3.A commit scope** (not discussed) — whether the 2 remediation commits (`f7a6fccd`, `a91dac85`) get dedicated §3.A rows.

---

## EXC-04 KI disposition

Context surfaced during discussion: Phase 278 commit `8a81a87c` deleted `EntropyLib.entropyStep` entirely (not just narrowed its scope) and swapped `_jackpotTicketRoll` to `EntropyLib.hash2` keccak self-mix. The `KNOWN-ISSUES.md:31` EXC-04 entry now describes code that no longer exists.

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite as resolved breadcrumb | Rewrite line-31 to a brief "retired at v40.0 Phase 278" note so wardens cross-referencing FINDINGS-v25..v39 land on explicit resolution. §6b: KNOWN_ISSUES_MODIFIED. | |
| Full removal | Delete the line-31 entry entirely — xorshift structurally gone, no longer belongs in a pre-disclosure doc. §6b: KNOWN_ISSUES_MODIFIED. | ✓ |
| Hold as-is, document drift in FINDINGS only | Leave KNOWN-ISSUES.md untouched per D-40N-KI-01; note staleness only in §6b. §6b: KNOWN_ISSUES_UNMODIFIED. | |

**User's choice:** Full removal.
**Notes:** Captured as D-280-EXC04-01. The xorshift mechanism is structurally eliminated, so the entry should not survive in the warden-facing pre-disclosure doc. §6 KI walkthrough records EXC-04 as structurally eliminated (cite `8a81a87c`); §6b verdict line is `KNOWN_ISSUES_MODIFIED`.

---

## Plan shape

| Option | Description | Selected |
|--------|-------------|----------|
| Single plan, sequenced tasks | One PLAN.md with internal task ordering; adversarial pass is a sequential-after-§4-draft task dependency, not a plan boundary. Matches v37 P271 single-plan terminal precedent. | ✓ |
| Two plans: draft+adversarial / closure-flip | Split audit-deliverable authoring + adversarial pass into plan 01, closure attestation into plan 02 for a cleaner pre-flip checkpoint. | |

**User's choice:** Single plan, sequenced tasks.
**Notes:** Captured as D-280-PLANSHAPE-01. Phase 280 is source-tree frozen with no contract/test commit waves to serialize, so a single plan with internal task sequencing carries all necessary ordering.

## Research skip

| Option | Description | Selected |
|--------|-------------|----------|
| Skip research, plan directly | Terminal delta audit with strong v37/v39 precedent; feedback_skip_research_test_phases.md applies. | ✓ |
| Run research agent | Spawn gsd-phase-researcher for a pre-survey of the 12-commit delta surface / 11 §4 surfaces. | |

**User's choice:** Skip research, plan directly.
**Notes:** Captured as D-280-RESEARCH-01. The deliverable is fully specified by REQUIREMENTS.md §AUDIT/§REG + the D-40N-* anchors + CONTEXT.md.

---

## Claude's Discretion

- **BUR-05 deviation disposition** in FINDINGS-v40.0 — finding block vs INFO §3c note vs §3.A prose for Phase 279's +114-byte NET-POSITIVE bytecode (user-accepted override).
- **§3.A row granularity** for the 2 remediation commits (`f7a6fccd`, `a91dac85`) — dedicated rows vs fold into parent-phase rows.
- Adversarial-log filename/placement, §-section template mechanics, closure-HEAD placeholder-resolution task ordering.

## Deferred Ideas

- **Superseded-baseline SURF-block `it.skip` cleanup** (Phase 279 D-279-02-SURF-SUPERSEDED-01) — out of Phase 280 scope (source-tree frozen); carry as v41+ quick-task / backlog item.
- **LBX-02 fixture-coverage gap** — RE-DEFERRED-V41+ per D-40N-LBX02-OUT-01 (settled carry).
- **STATE.md frontmatter reconciliation** — the `status: completed` / `percent: 100` / `total_phases: 1` inconsistency to be corrected as part of the atomic closure-flip.

## Process Note

The ROADMAP.md regression caused by the `/gsd-plan-phase 279` run (commit `f032767c` clobbered ROADMAP.md from 185 lines to 19, dropping the Phase 280 entry + archives + Progress table) was discovered at the start of this discussion and repaired (commit `732c6814`, restored from `c3d2dfcb` and reconciled to current phase state). Without the repair, `init.phase-op 280` returned `phase_found: false` and discuss-phase could not start.
