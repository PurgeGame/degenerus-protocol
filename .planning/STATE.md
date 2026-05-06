---
gsd_state_version: 1.0
milestone: v33.0
milestone_name: Charity Allowlist Governance
status: executing
last_updated: "2026-05-06T05:12:52.119Z"
last_activity: 2026-05-06 -- Phase 254 planning complete
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 3
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-05 for v33.0 start)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** v33.0 Charity Allowlist Governance — replace open `propose(address)` / approve-reject flow on `GNRUS.sol` with vault-owner-curated allowlist (≤20 active slots, address-only, empty at deploy); slot edits queue and apply at level boundary; `vote(uint8 slot)` direct slate voting (approve-only); vault-owner +5% vote bonus removed; lowest active slot wins on tie. Foundational slots 0/1/2 are permanently immutable once filled.

## Current Position

Phase: 254 (Context gathered — awaiting plan-phase)
Plan: —
Status: Ready to execute
Last activity: 2026-05-06 -- Phase 254 planning complete
Resume file: .planning/phases/254-gnrus-allowlist-storage-admin-op-storage-repack/254-CONTEXT.md

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

**v33.0 Charity Allowlist Governance** — kicked off 2026-05-05; roadmap drafted 2026-05-05.

- Audit baseline: v32.0 HEAD `acd88512` (closure signal `MILESTONE_V32_AT_HEAD_acd88512`)
- Posture: **mixed shape** — Phases 254-256 modify `contracts/GNRUS.sol` + add tests under `test/governance/`; Phase 257 delta-audits the result. READ-only LIFTED per v32.0 precedent — agents do NOT commit `contracts/` or `test/` changes without explicit user approval per `feedback_no_contract_commits.md`.
- Deliverable: `audit/FINDINGS-v33.0.md` with regression appendix verifying v32.0 closure signal still holds, conservation re-proof of GNRUS unallocated pool flow, KI EXC-01..04 RE_VERIFIED NEGATIVE-scope.

## Roadmap Overview

4 phases, 25 requirements, 100% coverage:

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 254 | GNRUS Allowlist Storage, Admin Op & Storage Repack | ALW-01, ALW-02, ALW-03, ALW-04, CLEAN-01 (5) | Not started |
| 255 | Vote Rewrite, Resolve Flush & Event/Error Cleanup | VOTE-01, VOTE-02, VOTE-03, VOTE-04, RES-01, RES-02, RES-03, RES-04, CLEAN-02, CLEAN-03 (10) | Not started |
| 256 | Charity Allowlist Test Coverage | TST-01, TST-02, TST-03, TST-04, TST-05, TST-06 (6) | Not started |
| 257 | Delta Audit & Findings Consolidation | AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04 (4) | Not started |

**Dependencies:** Phase 254 must precede Phase 255 (vote rejects empty slots, so the slate storage + setCharity must exist before vote/pickCharity can be rewritten against it). Phase 256 depends on Phases 254 + 255 (tests exercise the full surface). Phase 257 is terminal — depends on 254 + 255 + 256 (audit baseline is the post-test HEAD with all impl + tests landed).

**Committable changes (gated on per-commit user approval per `feedback_no_contract_commits.md`):**

- Phase 254: `contracts/GNRUS.sol` — allowlist storage layout, `setCharity(uint8, address)` admin entry point, view helpers, dead-state removal (proposals/levelVaultOwner/levelSdgnrsSnapshot/etc), storage repack
- Phase 255: `contracts/GNRUS.sol` — `vote(uint8 slot)` rewrite, `pickCharity(uint24 level)` flush + winner-selection rewrite, `Voted` + `LevelResolved` event signature rewrites, error rename/cleanup
- Phase 256: `test/governance/CharityAllowlist.test.js` (or similar) — Hardhat coverage for setCharity branches, vote, pickCharity, conservation, post-gameover inertness
- Phase 257: `audit/FINDINGS-v33.0.md` + supporting `audit/v33-*.md` working files (writeable freely per write policy)

## Deferred Items

Items acknowledged and deferred at v32.0 milestone close on 2026-05-02 (carry-forward from v31.0 close 2026-04-24):

| Category | Item | Status | Notes |
|----------|------|--------|-------|
| quick_task | 260327-n7h-run-full-test-suite-and-analyze-results- | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 → v32.0 close. |
| quick_task | 260327-q8y-test-boon-changes | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 → v32.0 close. |

## Accumulated Context

Decisions and completed milestones logged in `.planning/PROJECT.md`.
Detailed milestone retrospectives in `.planning/RETROSPECTIVE.md` (v31.0 section most recent).
Archived milestone artifacts:

- v32.0: `.planning/milestones/v32.0-ROADMAP.md`, `v32.0-REQUIREMENTS.md`, `v32.0-phases/`
- v31.0: `.planning/milestones/v31.0-ROADMAP.md`, `v31.0-REQUIREMENTS.md`, `v31.0-phases/`
- v30.0: `.planning/milestones/v30.0-ROADMAP.md`, `v30.0-REQUIREMENTS.md`, `v30.0-phases/`
- v29.0: `.planning/milestones/v29.0-ROADMAP.md`, `v29.0-REQUIREMENTS.md`, `v29.0-phases/`
- Earlier: `.planning/milestones/` (v2.1 onward)

Audit deliverables:

- `audit/FINDINGS-v32.0.md` (548 lines, 9 sections, FINAL READ-only at HEAD `acd88512`; 2 HIGH SUPERSEDED-at-HEAD F-32-NN disclosure blocks; closure signal `MILESTONE_V32_AT_HEAD_acd88512`)
- `audit/v32-247-DELTA-SURFACE.md` through `audit/v32-252-POST31.md` (FINAL READ-only at HEAD `acd88512`; 6 v32 supporting working-file appendices)
- `audit/FINDINGS-v31.0.md` (403 lines, 9 sections; 0 CRITICAL/HIGH/MEDIUM/LOW/INFO; closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`)
- `audit/FINDINGS-v30.0.md` (729 lines, 10 sections; 17 INFO / 31-row regression PASS / 0 KI promotions)
- `audit/FINDINGS-v29.0.md`, `audit/FINDINGS-v28.0.md`, `audit/FINDINGS-v27.0.md`, `audit/FINDINGS-v25.0.md` (prior milestones)
- `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only) + `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only) + `audit/v31-245-SDR-GOE.md` (FINAL READ-only) + 6 v31 working-file appendices
- `audit/v30-*.md` — 16 upstream Phase 237-241 proof artifacts (byte-identical since Phase 242 plan-start)

## Global Project State

- Contract tree at HEAD `acd88512` (v32.0 audit anchor) plus working-tree changes targeted by v33.0 charity allowlist work.
- READ-only audit pattern carried forward v28.0–v31.0; **READ-only LIFTED for v32.0 + v33.0** — audit-then-commit (or impl-then-audit) with per-commit user approval per `feedback_no_contract_commits.md`. No agent commits contracts/ or test/ changes without explicit user review of the diff.
- KNOWN-ISSUES.md: 4 accepted RNG-determinism exceptions (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift) — all re-verified non-widening at HEAD `acd88512` in v32.0 Phase 248 + Phase 250. v33.0 Phase 257 expects all four NEGATIVE-scope (charity governance does not touch any RNG-consuming path).
