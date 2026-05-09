---
gsd_state_version: 1.0
milestone: v34.0
milestone_name: Trait Rarity Rework + Gold Solo Priority
status: Awaiting next milestone
last_updated: "2026-05-09T09:55:26.251Z"
last_activity: 2026-05-09 — Milestone v34.0 completed and archived
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-09 after v34.0 milestone close)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Current focus:** v34.0 SHIPPED 2026-05-09; next milestone TBD

## Current Position

Phase: Milestone v34.0 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-05-09 — Milestone v34.0 completed and archived

## Last Shipped Milestone

**v34.0 — Trait Rarity Rework + Gold Solo Priority** (shipped 2026-05-09)

- 4 phases (259-262), 10 plans, 36/36 requirements satisfied (TRAIT-01..06 + SOLO-01..09 + STAT-01..07 + SURF-01..05 + AUDIT-01..05 + REG-01..04)
- Audit baseline: v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399` → v34.0 source-tree HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555` (Phase 262 emits zero source-tree mutations per CONTEXT.md hard constraint #1; source-tree HEAD stable across Phase 262's docs-only commits per D-262-CLOSURE-01)
- 5 source-tree commits since baseline (`301f7fad` rewrite TraitUtils, `031a8cbc` TraitUtilsTester, `2fa7fb6e` gold-solo + tests, `1574d533` noOp companion, `a6c4f18a` perf refactor) + 8 test-tree commits (Phase 259/260/261 test files)
- Result: 6 of 6 §4 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE (a entropy-bit collision, b split-call coherence, c gold-trait population manipulation, d gas-griefing 4-iter loop, e overflow / signed-vs-unsigned XOR mask, f hero × gold composition added per Task 7 user disposition as intended skill-expression channel for high-engagement Degenerette wagerers); zero F-34-NN finding blocks emitted
- LEAN regression: 1 PASS REG-01 (v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` re-verified non-widening; charity governance / GNRUS.sol byte-identical) + 1 PASS REG-02 (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening; L173 turbo guard + L1174 backfill sentinel + GameStorage `_livenessTriggered` body byte-identical between v32 baseline and v34 HEAD) + 4 PASS REG-04 (v25/v27/v29/v30 prior-finding spot-check rows)
- KI envelopes EXC-01..03 RE_VERIFIED NEGATIVE-scope at v34 (trait/solo path has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction); EXC-04 RE_VERIFIED with STAT-05 chi² empirical cross-cite (`test/stat/GoldSoloCoverage.test.js:159-209`, 100K samples per goldCount ∈ {2,3,4})
- KNOWN-ISSUES.md UNMODIFIED per D-262-KI-01 default zero-promotion path
- Deliverable: `audit/FINDINGS-v34.0.md` (FINAL READ-only at HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`, 9 sections, ~700 lines)
- Closure signal: `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`
- Process notes: Task 7 user disposition Option B default-path approved by user; Surface (a) bits 24-25 doc gap + Surface (c) two-channel tightening + NEW Surface (f) hero × gold composition all surfaced via /contract-auditor + /zero-day-hunter parallel spawn (D-262-ADVERSARIAL-02 sequential-after-draft pattern) + folded into §4 prose via Task 7b atomic-commit prose-amendment per user disposition
- Phase 261 deferred items (carried forward as INFO-tier): (a) STAT-07 ROADMAP cites informational headline targets vs canonical analytical values (test asserts canonical-within-Wilson-99%-CI-of-measured); (b) ROADMAP Phase 261 success criterion #5 cites `_pickSoloQuadrant per-call < 500 gas` while REQUIREMENTS.md SURF-05 amendment `73d533d8` supersedes with `≤ 1500 gas paired-empty-wrapper delta` — both surfaced INFO-only in §3c per D-262-FIND-01 default path; REQUIREMENTS.md amendment commit `73d533d8` is load-bearing
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

**v33.0 — Charity Allowlist Governance (post-closure patch)** (re-shipped 2026-05-06 via Phase 258)

- 5 phases (254-258), 15 plans, 28/28 requirements satisfied (ALW + VOTE + RES + CLEAN + TST + AUDIT + FIX-01 + FIX-02 + AUDIT-05)
- Audit baseline: v32.0 HEAD `acd88512` → v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399` (Phase 258-01 added a single contract+test commit pair on top of `dcb70941`; closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `MILESTONE_V33_AT_HEAD_dcb70941`)
- Result: 9 of 9 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY (a, b, c, d, e, f, g, h, i — surface (i) consecutive-recipient capture added post-258 with FIX-02 closure; surface (a) re-tagged with post-258 reinforcement note for FIX-01 queue-branch closure); zero F-33-NN finding blocks emitted; trust-asymmetry items (e) + (g) routed to §4 sub-row prose disclosures.
- LEAN regression: 1 PASS REG-01 (v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` re-verified non-widening; L173 + L1174 + GameStorage `_livenessTriggered` body byte-identical between baseline and HEAD `4ce3703d740d3707c88a1af595618120a8168399`)
- KI envelopes EXC-01..04 all RE_VERIFIED NEGATIVE-scope (charity governance has zero RNG interaction)
- KNOWN-ISSUES.md UNMODIFIED per D-257-KI-01 default zero-promotion path (carries forward through Phase 258)
- Deliverable: `audit/FINDINGS-v33.0.md` (FINAL READ-only at HEAD `4ce3703d740d3707c88a1af595618120a8168399`, ~750 lines, 9 sections + Phase 258 §3a + §4 + §5 + §9 updates)
- Closure signal: `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (supersedes `MILESTONE_V33_AT_HEAD_dcb70941`)
- See `.planning/MILESTONES.md` for archive

### Prior Shipped Milestone

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

_(none — v34.0 SHIPPED 2026-05-09; next milestone TBD)_

## Roadmap Overview

_(none — v34.0 SHIPPED 2026-05-09; next milestone TBD. See `.planning/ROADMAP.md` once `/gsd-new-milestone` runs.)_

## Next-Milestone Backlog (v35.0)

Seeds captured for promotion via `/gsd-review-backlog` once v34.0 closes. Do NOT pull into v34.0.

| Seed | Subsystem | Target | Notes |
|------|-----------|--------|-------|
| [burnie-near-future-per-pull-level-resample](notes/2026-05-08-burnie-near-future-per-pull-level.md) | jackpot-distribution | v35.0 | Per-pull random level for near-future BURNIE coin jackpot. Locked decisions: empty-bucket-skip, flat 50-pull loop with `trait_idx = i % 4`, deity caching, `lvl` in salt. Cross-milestone dep: Phase 261's chi-squared infra (reusable vs one-shot decides whether v35.0 needs new statistical-validation phase). Off-chain indexer flag: `JackpotBurnieWin.lvl` semantic shifts from "shared call level" to "per-pull sampled level". |

## Deferred Items

Items acknowledged and deferred at v34.0 milestone close on 2026-05-09 (carry-forward chain v32.0 → v33.0 → v34.0):

| Category | Item | Status | Notes |
|----------|------|--------|-------|
| quick_task | 260327-n7h-run-full-test-suite-and-analyze-results- | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 → v32.0 → v33.0 close. |
| quick_task | 260327-q8y-test-boon-changes | missing (tracker frontmatter) | Stale pre-v30.0 entry dated 2026-03-27. PLAN.md + SUMMARY.md present on disk; audit tool flags on frontmatter status mismatch only. Carried forward from v29.0 → v30.0 → v31.0 → v32.0 → v33.0 close. |
| verification_gap | Phase 257 (257-VERIFICATION.md) | human_needed | Gate resolved by Phase 258 supersedence (HUMAN-UAT marked `resolved`, resolved_by: phase-258), but VERIFICATION.md frontmatter `status: human_needed` field was not flipped to `resolved`. Bookkeeping defect; tracker out of date with reality. See `.planning/v33.0-MILESTONE-AUDIT.md`. |
| verification_gap | Phase 258 (258-VERIFICATION.md) | human_needed | Gate resolved by Phase 258-03 stale-reference sweep, but VERIFICATION.md frontmatter `status: human_needed` was not flipped to `resolved`. Bookkeeping defect. See `.planning/v33.0-MILESTONE-AUDIT.md`. |
| process_gap | Phases 254/255/256 missing VERIFICATION.md | not_run | Formal verification gate did not run when those phases closed (pre-session). Phase 257 delta-audit independently re-validated all that work (`audit/FINDINGS-v33.0.md`); functional risk: low. See `.planning/v33.0-MILESTONE-AUDIT.md` for the full per-phase analysis. |
| schema_drift | Phase 255 SUMMARY frontmatter key | requirements:_not_requirements-completed: | All three Phase 255 SUMMARYs (255-01/02/03) use `requirements:` instead of the canonical `requirements-completed:`. Tooling that parses the canonical key misses 10 Phase 255 reqs. Bookkeeping defect; the work itself is complete. See `.planning/v33.0-MILESTONE-AUDIT.md`. |
| schema_drift | Phase 256 SUMMARY req-completion fields | provides:_not_requirements-completed: | 256-03b uses `provides: [TST-03]`; 256-03c uses `provides: [TST-04, TST-06, D-256-GAS-01]`. Both should use `requirements-completed:`. Bookkeeping defect; tests for TST-03/04/06 pass and are part of the v33 governance suite. |
| documentation | ROADMAP.md Phase 257 plan checkbox | unchecked | `- [ ] 257-01-PLAN.md` on line ~196 not ticked despite phase being marked complete. All authoritative completion records (Progress table, MILESTONES.md, STATE.md) confirm completion. Cosmetic. |
| documentation | MILESTONES.md Phase 257 paragraph | "8 of 8 §4 surfaces" | Reads as if Phase 258 didn't add surface (i). The Phase 258 bullet in MILESTONES.md is correct; two paragraphs within the same document are mutually inconsistent. Cosmetic. |
| documentation | audit/FINDINGS-v33.0.md §3.4 commit-count | not extended | §3.4 enumerates 7 post-anchor non-GNRUS commits; post-Phase-258 contract tree has 9 (added `636f60ea` GNRUS-only + `4ce3703d` test-only). Phase 258-03 explicitly deferred this as `D-258-03-§34-COMMIT-COUNT-NOT-EXTENDED` since the new commits are covered elsewhere (`636f60ea` in §3a Part A; `4ce3703d` is test-only). Annotated, not extended. |
| audit_process | Phase 257 Task 7 manual-fallback record | resolved at v34 | The original Phase 257 Task 7 adversarial validation fell back to executor-manual when `/contract-auditor` and `/zero-day-hunter` skills failed to spawn. RESOLVED at v34.0 Phase 262 Task 6 — both skills successfully spawned in parallel with real captured output (see `.planning/milestones/v34.0-phases/262-delta-audit-findings-consolidation/262-01-ADVERSARIAL-LOG.md`). The C4A-warden-contest independence-claim hardening is satisfied at v34 closure HEAD `6b63f6d4`. Concurrent v33.0 close concern (queue-branch redirect bug) was already structurally closed in Phase 258 FIX-01 + FIX-02 prior to the v34 re-run. |

## Accumulated Context

Decisions and completed milestones logged in `.planning/PROJECT.md`.
Detailed milestone retrospectives in `.planning/RETROSPECTIVE.md` (v34.0 section most recent).
Archived milestone artifacts:

- v34.0: `.planning/milestones/v34.0-ROADMAP.md`, `v34.0-REQUIREMENTS.md`, `v34.0-phases/`
- v33.0: `.planning/milestones/v33.0-ROADMAP.md`, `v33.0-REQUIREMENTS.md`, `v33.0-phases/`
- v32.0: `.planning/milestones/v32.0-ROADMAP.md`, `v32.0-REQUIREMENTS.md`, `v32.0-phases/`
- v31.0: `.planning/milestones/v31.0-ROADMAP.md`, `v31.0-REQUIREMENTS.md`, `v31.0-phases/`
- v30.0: `.planning/milestones/v30.0-ROADMAP.md`, `v30.0-REQUIREMENTS.md`, `v30.0-phases/`
- v29.0: `.planning/milestones/v29.0-ROADMAP.md`, `v29.0-REQUIREMENTS.md`, `v29.0-phases/`
- Earlier: `.planning/milestones/` (v2.1 onward)

Audit deliverables:

- `audit/FINDINGS-v34.0.md` (FINAL READ-only at HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`, ~700 lines, 9 sections; 6 of 6 §4 adversarial surfaces SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; zero F-34-NN findings; 1 PASS REG-01 + 1 PASS REG-02 + 4 PASS REG-04; 4 NEGATIVE-scope/RE_VERIFIED KI envelope re-verifications; KNOWN-ISSUES.md UNMODIFIED; closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555`)
- `audit/FINDINGS-v33.0.md` (FINAL READ-only at HEAD `4ce3703d740d3707c88a1af595618120a8168399`, ~750 lines, 9 sections + Phase 258 §3a/§4/§5/§9 updates; 9 of 9 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY; zero F-33-NN findings; closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `MILESTONE_V33_AT_HEAD_dcb70941`)
- `audit/FINDINGS-v32.0.md` (548 lines, 9 sections, FINAL READ-only at HEAD `acd88512`; 2 HIGH SUPERSEDED-at-HEAD F-32-NN disclosure blocks; closure signal `MILESTONE_V32_AT_HEAD_acd88512`)
- `audit/v32-247-DELTA-SURFACE.md` through `audit/v32-252-POST31.md` (FINAL READ-only at HEAD `acd88512`; 6 v32 supporting working-file appendices)
- `audit/FINDINGS-v31.0.md` (403 lines, 9 sections; 0 CRITICAL/HIGH/MEDIUM/LOW/INFO; closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`)
- `audit/FINDINGS-v30.0.md` (729 lines, 10 sections; 17 INFO / 31-row regression PASS / 0 KI promotions)
- `audit/FINDINGS-v29.0.md`, `audit/FINDINGS-v28.0.md`, `audit/FINDINGS-v27.0.md`, `audit/FINDINGS-v25.0.md` (prior milestones)
- `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only) + `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only) + `audit/v31-245-SDR-GOE.md` (FINAL READ-only) + 6 v31 working-file appendices
- `audit/v30-*.md` — 16 upstream Phase 237-241 proof artifacts (byte-identical since Phase 242 plan-start)

## Global Project State

- Contract tree at v33.0 HEAD `4ce3703d740d3707c88a1af595618120a8168399` (v34.0 audit anchor / baseline) — pre-v34.0 working tree.
- READ-only audit pattern carried forward v28.0–v31.0; **READ-only LIFTED for v32.0 + v33.0 + v34.0** — audit-then-commit (or impl-then-audit) with per-commit user approval per `feedback_no_contract_commits.md`. No agent commits contracts/ or test/ changes without explicit user review of the diff. v34.0 phases that batch multiple contract edits use the batched approval pattern per `feedback_batch_contract_approval.md`.
- KNOWN-ISSUES.md: 4 accepted RNG-determinism exceptions (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift) — all re-verified non-widening at HEAD `acd88512` in v32.0 Phase 248 + Phase 250; v33.0 Phase 257 re-verified all four NEGATIVE-scope at HEAD `4ce3703d`. v34.0 Phase 262 expects EXC-01..03 NEGATIVE-scope (no RNG touched besides `_pickSoloQuadrant` and the unchanged `_rollWinningTraits` / `traitFromWord` flow); EXC-04 (EntropyLib XOR-shift) requires extra attention because `_pickSoloQuadrant` tie-break consumes `entropy >> 4` bits which may be XOR-shift-derived in some upstream paths — empirical chi-squared evidence at STAT-05 covers the uniformity claim.

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
