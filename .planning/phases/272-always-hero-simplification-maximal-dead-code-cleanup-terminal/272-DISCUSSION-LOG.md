# Phase 272: Discussion Log

**Session:** 2026-05-11
**Workflow:** `/gsd-discuss-phase 272` (default mode, no flags)
**Output:** `272-CONTEXT.md` (canonical record for downstream agents)

This file is for human reference (audits, retrospectives). Downstream agents (researcher, planner, executor) read `272-CONTEXT.md`, not this file.

---

## Pre-Discussion Analysis

### Inputs Loaded

- `.planning/PROJECT.md` (558 LOC) — milestone history, accumulated context
- `.planning/REQUIREMENTS.md` (116 LOC) — v38.0 30-requirement schedule
- `.planning/STATE.md` (187 LOC) — milestone v38.0 status; v37.0 closure signal `MILESTONE_V37_AT_HEAD_2654fcc2` last-shipped reference
- `.planning/ROADMAP.md` (lines 21, 26, 30-51) — Phase 272 success criteria + plan list
- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-CONTEXT.md` — single-phase patch precedent (primary template)
- Memory files: `feedback_design_intent_before_deletion.md`, `feedback_no_history_in_comments.md`, `feedback_batch_contract_approval.md`, `feedback_no_contract_commits.md`, `feedback_never_preapprove_contracts.md`
- Live contract state: `contracts/modules/DegenerusGameDegeneretteModule.sol` L321, L347, L578-594, L823-847, L944-994, L1007+ (HERO + cleanup surface)

### Gray Areas Identified

4 gray areas surfaced, with locked-carry items pre-filtered out (single-phase shape / single-file deliverable / §9 TWO-subsection / forward-cite zero-emission / 3-skill PARALLEL adversarial-pass / KNOWN-ISSUES.md default zero-promotion / closure-signal SHA / per-commit approval discipline / bit-allocation lock all carried from v36.0 → v37.0 chain).

- **(a)** CLEAN sweep scope ceiling — sweep breadth + discovery method
- **(b)** CLEAN commit shape — single combined vs split HERO + CLEAN
- **(c)** GASPIN-02 path — (a) hardhat_reset retry / (a-alt) test:gas split / (c) widened tolerance
- **(d)** LBX-02 + STAT-03-v35-carry resolution — attempt vs re-defer for each

### Design-Intent + Actor Game-Theory Trace (proactive, per `feedback_design_intent_before_deletion.md`)

Surfaced inline before any AskUserQuestion about deletion shape. Captured verbatim in `272-CONTEXT.md` D-272-DESIGN-INTENT-01 for inline use in:
- Wave 1 commit message
- `272-01-PLAN.md` Task-1 description
- `audit/FINDINGS-v38.0.md` §3.A delta-surface table HERO-01..05 row(s)
- §4 surface attestation prose

Trace covers: (1) original `heroEnabled` opt-out intent (variance-reduction tool, EV-neutral by construction); (2) actor walk-through across (player risk-profile × game state) — EV-rational players unaffected, variance-averse players lose variance-reduction tool with bounded downside (0.95 × basePayout worst-case), whales/casual/admin/adversarial zero differential impact; (3) forward-looking risk (3-bit allocation preserved for re-introduction); (4) why now (pre-launch UI simplification + ~30 byte / ~30 gas savings + bounded acceptable variance impact).

---

## Discussion Turns

### Turn 1 — Gray-area selection

**Q:** Which areas do you want to discuss for Phase 272?

**Options presented:**
- ☐ CLEAN sweep scope ceiling
- ☐ CLEAN commit shape (single vs split)
- ☐ GASPIN-02 path
- ☐ LBX-02 + STAT-03-v35-carry resolution

**User selected:** CLEAN sweep scope ceiling, CLEAN commit shape (single vs split)

**Implications:** GASPIN-02 / LBX-02 / STAT-03-v35-carry deferred to planner discretion with REQUIREMENTS.md-enumerated option sets. Captured in CONTEXT.md `<deferred_to_planner>` section.

### Turn 2 — CLEAN sweep breadth

**Q:** How wide should the /gas-audit sweep go across `contracts/`?

**Options presented:**
- ☐ Maximal — all `contracts/` (modules + libraries + main + top-level) — 14,663 LOC
- ☐ Modules + libraries only (skip top-level) — 8,062 LOC
- ☐ Degenerette + adjacent modules only — ~7,000 LOC
- ☐ Degenerette module only + immediate spillover (MASK_3 etc.) — 1,158 LOC

**User selected:** Degenerette module only + immediate spillover (MASK_3 etc.)

**Locks:** D-272-CLEAN-SCOPE-01 — sweep narrows from ROADMAP.md "maximal across contracts/" to "Degenerette module only" at v38. AUDIT-01 §3.A delta-surface table must note this as a v38-design choice, not a coverage gap.

### Turn 3 — CLEAN discovery method

**Q:** Within Degenerette-module-only scope, how should cleanup candidates be discovered?

**Options presented:**
- ☐ Manual grep-walk by planner (no /gas-audit spawn)
- ☐ /gas-audit orchestrator scoped to one file
- ☐ /gas-audit full-sweep but only apply Degenerette removals (defer cross-module to v39+)

**User selected:** Manual grep-walk by planner (no /gas-audit spawn)

**Locks:** D-272-CLEAN-DISCOVERY-01 — manual grep-walk replaces orchestrator spawn at v38. AUDIT-02 §4 surface (c) attestation prose must cite manual grep-walk as discovery method. REQUIREMENTS.md CLEAN-01 wording is SOFTENED at v38.

### Turn 4 — CLEAN commit shape

**Q:** How should the Wave 1 contract commit(s) be shaped, given the now-narrowed Degenerette-only cleanup scope?

**Options presented:**
- ☐ Single combined commit — `feat(272): always-on hero default 0 + degenerette dead-code cleanup [HERO-01..05, CLEAN-01..05]`
- ☐ Split into 2 commits — HERO commit, then CLEAN commit
- ☐ Split into 2 commits, HERO USER-APPROVED + CLEAN deferred to follow-up

**User selected:** Single combined commit

**Locks:** D-272-COMMIT-SHAPE-01 — one USER-APPROVED batched commit covers HERO-01..05 + CLEAN-01..05. Commit message includes per-requirement attribution, bytecode delta, gas-per-spin delta, storage-layout grep proof.

### Turn 5 — Close-out

**Q:** Anything else before I write 272-CONTEXT.md?

**Options presented:**
- ☐ Write CONTEXT.md now — defer GASPIN-02 / LBX-02 / STAT-03-v35-carry to planner discretion
- ☐ Quickly lock GASPIN-02 path now
- ☐ Quickly lock LBX-02 + STAT-03-v35-carry resolution now

**User selected:** Write CONTEXT.md now — defer to planner discretion

**Implications:** Planner picks GASPIN-02 / LBX-02 / STAT-03-v35-carry paths at plan-phase with REQUIREMENTS.md-enumerated options as the constraint set.

---

## Summary of Locked Decisions

| Decision ID | Subject | Resolution |
|-------------|---------|------------|
| D-272-CLEAN-SCOPE-01 | CLEAN sweep breadth | Degenerette-module-only (narrows ROADMAP "maximal") |
| D-272-CLEAN-DISCOVERY-01 | CLEAN discovery method | Manual grep-walk; no `/gas-audit` orchestrator |
| D-272-COMMIT-SHAPE-01 | Wave 1 contract commit shape | Single combined HERO + CLEAN commit |
| D-272-DESIGN-INTENT-01 | Always-hero trace surfacing | Inline in commit msg + plan + §3.A + §4 |
| D-272-NATSPEC-DISCIPLINE-01 | HERO-04 NatSpec | Describe what IS; zero historical/comparative language |

**Plus locked carry-forward from v36.0 Phase 266 → v37.0 Phase 271 chain (not re-discussed):**

| Decision ID | Subject |
|-------------|---------|
| D-272-FILES-01 | Single-file `audit/FINDINGS-v38.0.md` |
| D-272-CLOSURE-01 | Closure signal SHA at audit-pass-close HEAD |
| D-272-CLOSURE-02 | §9 TWO-subsection format |
| D-272-FCITE-01 | Forward-cite zero-emission terminal invariant |
| D-272-ADVERSARIAL-01 | 3-skill PARALLEL adversarial pass (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) |
| D-272-KI-01 | KNOWN-ISSUES.md default zero-promotion |
| D-272-SEV-01 | D-08 5-bucket severity rubric |
| D-272-APPROVAL-01 | Per-commit user approval (2 batched contract+test commits) |

---

## Deferred to Planner Discretion

- **GASPIN-02 path** — REQUIREMENTS.md options: (a) refined hardhat_reset / (a-alt) `npm run test:gas` script split / (c) widened tolerance.
- **LBX-02 attempt vs re-defer** — REQUIREMENTS.md options: empirical pin attempt vs formal re-defer with path-of-investigation prose.
- **STAT-03-v35-carry resolution** — REQUIREMENTS.md options: populate dense fixture vs ACCEPTED-DESIGN ledger entry per v35.0 D-265-STAT03-01 reframe.

---

## Deferred Ideas (out of v38 scope, captured for future phases)

- Maximal cleanup sweep across non-Degenerette `contracts/` (modules + libraries + main; ~13,500 non-Degenerette LOC).
- `/gas-audit` orchestrator integration (for future phases with broader cleanup scope).
- BAF jackpot `_jackpotTicketRoll` xorshift refactor (v36.0 ENT-05 carry).
- `runrewardjackpots` module-misplacement (stale 2026-04-02 backlog).
- Game-over thorough hardening (dedicated game-over hardening milestone).
- `/degen-skeptic` adversarial-skill addition (requires new explicit user opt-in).
- v37.0 milestone archive rotation (planner-discretion inline at closure).

---

*Discussion held in default mode; 4 single-question turns + 1 selection turn + 1 close-out turn = 6 total interaction rounds.*
*Compliance: design-intent + actor game-theory trace surfaced proactively per `feedback_design_intent_before_deletion.md` BEFORE any deletion-shape AskUserQuestion.*
