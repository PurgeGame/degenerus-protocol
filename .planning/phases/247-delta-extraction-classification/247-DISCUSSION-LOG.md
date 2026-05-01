# Phase 247: Delta Extraction & Classification — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-30
**Phase:** 247-delta-extraction-classification
**Areas discussed:** WIP anchoring, test/ catalog scope, plan topology, ContractAddresses regen handling

---

## WIP Anchoring

| Option | Description | Selected |
|--------|-------------|----------|
| A — Virtual SHA placeholder | Treat WIP as `Commit C5: WIP-pre-audit` synthetic SHA inline with the 4 landed commits. Single chronological table. Cleanest narrative but blends uncommitted code with committed code in citations. | |
| B — Commit WIP first | User reviews + approves WIP NOW, then Phase 247 anchors at the new SHA. Means approving WIP changes BEFORE audit completes — violates audit-then-commit posture. | ✓ |
| C — Two-anchor catalog | HEAD `48554f8f` for the 4 landed commits + explicit WIP overlay sub-section (`WIP:path:line` cites). Reviewers see audit-target WIP separately from already-landed code. Phase 253 addendum back-references rows to final SHA after WIP commits. | |

**User's choice:** B — Commit WIP first.

**Notes:** User noted the AdvanceModule WIP only contained one real fix (turbo guard at L173) — the backfill guard at L1167 was just a comment block describing intent without the actual `&& rngWordByDay[idx + 1] == 0` conditional update. ContractAddresses.sol was deploy-regen artifact and shouldn't be committed; tests "idgaf about" (defer to Phase 251). Final action: applied the missing L1174 backfill conditional with explicit user approval, then committed AdvanceModule alone as `acd88512 fix(advance): guard turbo block + make _backfillGapDays idempotent`. ContractAddresses + untracked test stayed in working tree.

### Re-stability follow-up question

| Option | Description | Selected |
|--------|-------------|----------|
| Sealed + back-ref | Phase 247 stays READ-only after plan-close per D-21 precedent. Phase 253 produces a small SHA-back-reference table mapping WIP catalog rows to final commit SHAs. | ✓ |
| Re-open for addendum | If WIP commits, Phase 247 re-opens like it did in v31.0 when `cc68bfc7` landed mid-Phase-243. | |

**User's choice:** Sealed + back-ref.

**Notes:** Largely moot after Option B was selected for the primary anchor question — the WIP committed before Phase 247 runs, so there's no future addendum work needed. Carry-forward of Phase 243 D-21 scope-guard deferral pattern still applies to any catalog gaps Phases 248-252 surface.

---

## test/ Catalog Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Contracts-only (Phase 243 carry-forward) | Same scope as v31.0 Phase 243 D-14. Phase 251 (Reproduction Tests) handles all test/ inventory + repro-ness verdicts. Cleanest separation: Phase 247 stays narrowly focused on contract surface. | ✓ |
| test/edge/* only (targeted inclusion) | Catalog the 2 new edge tests (LivenessMidJackpot + LivenessProductivePause) since TST-03 explicitly RE_VERIFIES them. Other test/ changes route to Phase 251. Hybrid. | |
| All test/ changes | Full enumeration of the 5 changed test/ files alongside contracts/. Most thorough but bloats Phase 247 deliverable and creates overlap with Phase 251. | |

**User's choice:** Contracts-only (Phase 243 carry-forward).

**Notes:** Phase 251 owns all test/ inventory (5 delta-touched + 1 untracked). Captured as D-247-02, D-247-17 in CONTEXT.md.

---

## Plan Topology

| Option | Description | Selected |
|--------|-------------|----------|
| Single-plan | One plan `247-01-DELTA-SURFACE.md` does DELTA-01 + DELTA-02 + DELTA-03 in sequence within a single plan. Surface is small enough (5 commits, 4 files) that orchestration overhead of a 3-plan split outweighs the parallelism benefit. | ✓ |
| 2-plan split | Plan 1: DELTA-01 + DELTA-02 combined. Plan 2: DELTA-03. Wave 1 commits Plan 1; Wave 2 runs Plan 2 on the committed row list. | |
| 3-plan split (Phase 243 mirror) | Direct mirror of Phase 243 D-10: Plan 1 DELTA-01, Plan 2 DELTA-02, Plan 3 DELTA-03. 2-wave topology. | |

**User's choice:** Single-plan.

**Notes:** Captured as D-247-12, D-247-13, D-247-14 in CONTEXT.md. Single plan with 5 tasks (Task 1 enumeration, Task 2 classification, Task 3 call-site catalog, Task 4 Consumer Index + reproduction recipe + final assembly, Task 5 READ-only flip). Each task lands its own commit per v31 Phase 246 atomic-commit pattern.

---

## ContractAddresses Regen Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Out of scope — not in catalog | Phase 247 anchors at HEAD `acd88512` and ignores the working tree entirely. ContractAddresses.sol is by definition deploy-regenerated and never part of audit-target commits. | ✓ |
| Single REGEN_ONLY row | Catalog includes one line entry mirroring Phase 243 D-13 NO_CHANGE pattern. Every modified file appears once in catalog even if zero classification rows. | |
| Document-only acknowledgment | Section 0 Scope Boundaries notes "ContractAddresses.sol working-tree changes acknowledged as deploy regeneration; not audited" without giving it a row. | |

**User's choice:** Out of scope — not in catalog.

**Notes:** Captured as D-247-03 in CONTEXT.md. Distinct from Phase 243 D-13 pattern because that commit (`ffced9ef`) was a real commit in scope; here ContractAddresses.sol is dirty in working tree against `acd88512` and never enters the audit-target commit history.

---

## Claude's Discretion

The following items were handed to Claude per D-247-09 / D-247-11 / D-247-12 / D-247-15 closing notes:

- Exact section ordering within `audit/v32-247-DELTA-SURFACE.md` (planner picks readability)
- Whether to produce a per-source change count card one-line summary per commit
- Final Row ID prefix scheme (D-247-11 suggests `D-247-C/F/S/X/I-NNN`; planner may flatten if cleaner)
- Whether to preserve raw `git diff` output inline vs companion files when a single commit's diff exceeds ~200 lines (likely only `48554f8f` Vault refactor approaches this)
- Whether DELTA-03 call-site grep separates direct calls from delegatecall selectors
- How to handle `DegenerusVault.sol` REFACTOR_ONLY-vs-MODIFIED_LOGIC borderline rows (per-row planner call)
- Whether GameStorage `+12 lines` lands as one consolidated entry or row-per-variable

---

## Deferred Ideas

- **Automated CI gate on deltas** — wiring the catalog shape into a CI check that regenerates the classification table per PR. Future-milestone candidate.
- **Cross-milestone delta chain audit** — tracing a function's change history across v28/v29/v30/v31/v32 catalogs. Not needed for Phase 248-252 scope.
- **Row-count bounds enforcement** — no hard floor/ceiling for Task 1's enumeration; reconciliation via D-247-18 surfaces wildly unexpected counts.
- **ContractAddresses.sol audit dimension** — whether deploy-time address regeneration is itself a security surface (CREATE nonce predictability) is out of v32.0 scope.
- **test/ catalog enumeration in Phase 251** — Phase 251 will need its own catalog-shape decisions for the 5 delta-touched test/ files plus the untracked `LastPurchaseDayRace.test.js`.
