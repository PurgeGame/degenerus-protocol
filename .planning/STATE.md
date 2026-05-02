---
gsd_state_version: 1.0
milestone: v32.0
milestone_name: Backfill Idempotency + purchaseLevel Underflow Audit
status: shipped
last_updated: "2026-05-02T11:30:00.000Z"
last_activity: 2026-05-02 -- v32.0 milestone shipped; Phase 253 plan-close
progress:
  total_phases: 7
  completed_phases: 7
  total_plans: 7
  completed_plans: 7
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-30 for v32.0 start)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** v32.0 milestone shipped 2026-05-02; awaiting v33.0+ kickoff.

## Current Position

Phase: complete (Phase 253 plan-close landed; v32.0 milestone shipped)
Plan: 1 of 1 — COMPLETE
Status: v32.0 milestone shipped; awaiting v33.0+ kickoff
Last activity: 2026-05-02 -- Phase 253 plan-close + v32.0 milestone closure
Resume file: (none — v32.0 closed; v33.0+ has not yet kicked off)

## Last Shipped Milestone

**v32.0 — Backfill Idempotency + purchaseLevel Underflow Audit** (shipped 2026-05-02)

- 7 phases (247-253), 7 plans, 32/32 requirements satisfied
- Audit baseline: v31.0 HEAD `cc68bfc7` → v32.0 HEAD `acd88512` (5 post-v31.0 contract-touching commits including the WIP-guard fix; SG-250-01 `98e78404` post-anchor MintModule presale-flag commit recorded as functionally orthogonal)
- Result: Two HIGH SUPERSEDED-at-HEAD F-32-NN disclosure blocks (F-32-01 productive-pause / turbo race + F-32-02 `_backfillGapDays` double-execution; both fixed by L173 turbo guard + L1174 backfill sentinel committed in `acd88512`). 134 V-rows across 25 REQs (Phase 247-252) all SAFE / NON-WIDENING / NON-INTERFERING with 0 FINDING_CANDIDATE rows surfaced.
- LEAN regression: 13 PASS REG-01 + zero-row REG-02 (F-32-NN supersession scope captured in §4 'At-HEAD resolution' subsections, not REG-02 entries)
- KI envelopes EXC-01..04 all RE_VERIFIED non-widening at HEAD (EXC-02 + EXC-03 dual-carrier via Phase 248 BFL-05; EXC-01 + EXC-04 NEGATIVE-scope via Phase 250 SIB-03)
- KNOWN-ISSUES.md UNMODIFIED per D-253-FIND03-01 default path (F-32-01 + F-32-02 fail D-09 sticky predicate — SUPERSEDED at HEAD, not ongoing protocol behavior)
- Deliverable: `audit/FINDINGS-v32.0.md` (9-section, FINAL READ-only at HEAD `acd88512`)
- Closure signal: `MILESTONE_V32_AT_HEAD_acd88512`
- Awaiting-approval test files (TST-FILE-01 + TST-FILE-02): `test/edge/LastPurchaseDayRace.test.js` + `test/edge/BackfillIdempotency.test.js` remain untracked permanently per D-253-FIND04-04; user commits via separate post-milestone commits per `feedback_manual_review_before_push.md`
- See `.planning/milestones/v32.0-ROADMAP.md` (post-archival) and `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

**v31.0 — Post-v30 Delta Audit + Gameover Edge-Case Re-Audit** (shipped 2026-04-24, tag `v31.0`)

- 4 phases (243-246), 11 plans, 33/33 requirements satisfied
- Audit baseline: v30.0 HEAD `7ab515fe` → v31.0 HEAD `cc68bfc7` (5 contract commits, 14 files, +187/-67 lines)
- Result: Zero on-chain vulnerabilities. Zero F-31-NN findings. 142 V-rows across 33 REQs all SAFE floor severity.
- LEAN regression: 6 PASS REG-01 + 1 SUPERSEDED REG-02 (orphan-redemption window structurally closed by 771893d1)
- KI envelopes EXC-01..04 all RE_VERIFIED non-widening at HEAD
- KNOWN-ISSUES.md UNMODIFIED per CONTEXT.md D-07 default path
- Deliverable: `audit/FINDINGS-v31.0.md` (403 lines, 9 sections, FINAL READ-only)
- Closure signal: `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`
- See `.planning/milestones/v31.0-ROADMAP.md` and `.planning/MILESTONES.md` for archive

## Active Milestone

**v32.0 SHIPPED 2026-05-02.** No active milestone — awaiting v33.0+ kickoff.

## Roadmap Overview

7 phases, 32 requirements, 100% coverage:

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 247 | Delta Extraction & Classification | DELTA-01..03 (3) | COMPLETE (1/1 plans; 3/3 REQs satisfied; audit/v32-247-DELTA-SURFACE.md FINAL READ-only at HEAD acd88512; closure signal PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512) |
| 248 | Backfill Idempotency Proof | BFL-01..06 (6) | COMPLETE (1/1 plans; 6/6 REQs satisfied; audit/v32-248-BFL.md FINAL READ-only at HEAD acd88512; closure signal PHASE_248_BFL_FINAL_AT_HEAD_acd88512) |
| 249 | purchaseLevel Correctness Proof | PLV-01..06 (6) | COMPLETE (1/1 plans; 6/6 REQs satisfied; audit/v32-249-PLV.md FINAL READ-only at HEAD acd88512) |
| 250 | Sibling-Pattern Sweep | SIB-01..05 (5) | COMPLETE (1/1 plans; 5/5 REQs satisfied; audit/v32-250-SIB.md FINAL READ-only at HEAD acd88512; closure signal PHASE_250_SIB_FINAL_AT_HEAD_acd88512) |
| 251 | Reproduction Tests | TST-01..04 (4) | COMPLETE (1/1 plans; 4/4 REQs satisfied; 8 V-rows SAFE; audit/v32-251-TST.md FINAL READ-only at HEAD c790ae45; closure signal PHASE_251_TST_FINAL_AT_HEAD_65b33299; 4 atomic commits c73c8add → 65b33299; awaiting-approval test files: test/edge/LastPurchaseDayRace.test.js + test/edge/BackfillIdempotency.test.js) |
| 252 | Post-v31.0 Landed-Commit Sanity | POST31-01..02 (2) | COMPLETE (1/1 plans; 2/2 REQs satisfied; 11 V-rows SAFE; audit/v32-252-POST31.md FINAL READ-only at HEAD `2ad456fa`; closure signal `PHASE_252_POST31_FINAL_AT_HEAD_4e5ce8b5`; 4 atomic commits dd8e0052 → `4e5ce8b5`; awaiting-approval test files preserved untracked) |
| 253 | Findings Consolidation + Lean Regression | FIND-01..04 (4) + REG-01..02 (2) | COMPLETE (1/1 plans; 6/6 REQs satisfied; audit/FINDINGS-v32.0.md FINAL READ-only at HEAD acd88512; closure signal MILESTONE_V32_AT_HEAD_acd88512; 6 atomic per-task commits) |

**Dependencies:** Phase 247 must precede every other phase (provides delta surface). Phases 248 / 249 / 250 / 251 / 252 are independent of each other once Phase 247 lands. Phase 253 is terminal (consumes every prior phase artifact).

**Committable changes (gated on user approval per `feedback_no_contract_commits.md`):**

- WIP turbo guard `!rngLockedFlag` at AdvanceModule:167 (proposed)
- WIP backfill guard `rngWordByDay[idx + 1] == 0` at AdvanceModule:1167 (proposed)
- New reproduction test `test/edge/LastPurchaseDayRace.test.js` (proposed)
- `contracts/ContractAddresses.sol` regen (proposed; no logic delta)
- Any additional contract / test changes surfaced by SIB-05 (proposed; per-finding approval)

## Deferred Items

Items acknowledged and deferred at v31.0 milestone close on 2026-04-24 (carry-forward from v30.0 close 2026-04-20):

| Category | Item | Status | Notes |
|----------|------|--------|-------|
| quick_task | 260327-n7h-run-full-test-suite-and-analyze-results- | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 close. |
| quick_task | 260327-q8y-test-boon-changes | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 close. |

## Accumulated Context

Decisions and completed milestones logged in `.planning/PROJECT.md`.
Detailed milestone retrospectives in `.planning/RETROSPECTIVE.md` (v31.0 section most recent).
Archived milestone artifacts:

- v31.0: `.planning/milestones/v31.0-ROADMAP.md`, `v31.0-REQUIREMENTS.md`, `v31.0-phases/`
- v30.0: `.planning/milestones/v30.0-ROADMAP.md`, `v30.0-REQUIREMENTS.md`, `v30.0-phases/`
- v29.0: `.planning/milestones/v29.0-ROADMAP.md`, `v29.0-REQUIREMENTS.md`, `v29.0-phases/`
- Earlier: `.planning/milestones/` (v2.1 onward)

Audit deliverables:

- `audit/v32-251-TST.md` (FINAL READ-only at HEAD `c790ae45`; closure signal `PHASE_251_TST_FINAL_AT_HEAD_65b33299`; 4 sections + §0 reproduction recipe + §5 commit-readiness register + §4.4 awaiting-approval block with full BackfillIdempotency.test.js content; 8 TST-NN-Vmm V-rows all SAFE; 2 hunk-revert patches + 6 hardhat run logs as supporting artifacts; zero FINDING_CANDIDATE rows; both `test/edge/LastPurchaseDayRace.test.js` (existing untracked WIP) and `test/edge/BackfillIdempotency.test.js` (newly authored Task 3) listed at status `awaiting-approval` per `feedback_no_contract_commits.md`)
- `audit/v32-250-SIB.md` (FINAL READ-only at HEAD `acd88512`; closure signal `PHASE_250_SIB_FINAL_AT_HEAD_acd88512`)
- `audit/v32-249-PLV.md` (FINAL READ-only at HEAD `acd88512`)
- `audit/v32-248-BFL.md` (FINAL READ-only at HEAD `acd88512`; closure signal `PHASE_248_BFL_FINAL_AT_HEAD_acd88512`; 6 per-REQ sections + Phase 251 TST-04 hand-off appendix; 44 BFL-NN-VMM V-rows + 3 BFL-01-MNN multiplier rows + 5 BFL-02-XNN out-of-scope rows; zero FINDING_CANDIDATE rows; KNOWN-ISSUES.md UNCHANGED — both BFL-05 EXC-02 + EXC-03 carriers NON-WIDENING)
- `audit/v32-247-DELTA-SURFACE.md` (FINAL READ-only at HEAD `acd88512`; 7 sections fully populated; closure signal `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512`; 16 D-247-C### + 11 D-247-F### + 1 D-247-S### + 30 D-247-X### + 29 D-247-I### rows; sole scope input for Phases 248-253 per ROADMAP Phase 247 Success Criterion 4)
- `audit/FINDINGS-v31.0.md` (403 lines, 9 sections; 0 CRITICAL/HIGH/MEDIUM/LOW/INFO; closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`)
- `audit/FINDINGS-v30.0.md` (729 lines, 10 sections; 17 INFO / 31-row regression PASS / 0 KI promotions)
- `audit/FINDINGS-v29.0.md`, `audit/FINDINGS-v28.0.md`, `audit/FINDINGS-v27.0.md`, `audit/FINDINGS-v25.0.md` (prior milestones)
- `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only) + `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only) + `audit/v31-245-SDR-GOE.md` (FINAL READ-only) + 6 v31 working-file appendices
- `audit/v30-*.md` — 16 upstream Phase 237-241 proof artifacts (byte-identical since Phase 242 plan-start)

## Global Project State

- Contract tree at HEAD `48554f8f` (4 post-v31.0 commits above v31.0 baseline `cc68bfc7`) plus WIP working-tree changes targeted by v32.0 audit.
- READ-only audit pattern carried forward v28.0–v31.0; **READ-only LIFTED for v32.0** — audit-then-commit with per-commit user approval per `feedback_no_contract_commits.md`. No agent commits contracts/ or test/ changes without explicit user review of the diff.
- KNOWN-ISSUES.md: 4 accepted RNG-determinism exceptions (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift) — all re-verified non-widening at HEAD `cc68bfc7` in v31.0 Phase 245. v32.0 BFL-05 RE_VERIFIES EXC-02 + EXC-03 envelopes against the new backfill guard.
