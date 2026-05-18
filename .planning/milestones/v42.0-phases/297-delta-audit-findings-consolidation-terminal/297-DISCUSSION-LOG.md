# Phase 297: Delta Audit + Findings Consolidation (Terminal) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 297-delta-audit-findings-consolidation-terminal
**Areas discussed:** Task structure + draft path + commit orchestration (user-selected from 4 candidate gray areas)
**Areas auto-locked under default precedent (user-accepted defaults):** retryLootboxRng audit-subject integration shape; §9 verdict math for Phase 296 (xiv) ACCEPT_AS_DOCUMENTED; §9 Deferred-to-Future register additions

---

## Gray-Area Triage (initial AskUserQuestion)

| Option | Description | Selected |
|--------|-------------|----------|
| retryLootboxRng audit-subject integration | How `123f2dac` enters §3.A/§3.B/§3.C: separate 4th surface row group vs. addendum to Phase 296 row; how to handle the NEW public/external entry point exception in the 5-row zero-new-state roll-up; whether the VRFStallEdgeCases.t.sol slot-drift fix gets its own §3.A row or folds in. | |
| §9 verdict math for (xiv) ACCEPT_AS_DOCUMENTED | Phase 296 closed ZERO_FINDING but a Tier-1 FINDING_CANDIDATE on (xiv) was user-resolved as 'intended design.' Does §9 read '0 of 0 F-42-NN' (strict) or '0 of 0 F-42-NN; 1 Tier-1 ACCEPTED_AS_DOCUMENTED' (explicit), and where does the (xiv) prose live — §4 dedicated subsection vs. §4.2 adversarial-disposition citation only? | |
| §9 Deferred-to-Future register additions | Does Phase 296 generate new D-42N-* deferred-decision handoffs for v43+: domain-separation policy decision for the documented entropy-correlation, retryLootboxRng docstring/scope-boundary observation (contract-auditor MEDIUM note), launch-FAQ entries from /economic-analyst's INFO observations on permissionless retry / governance recovery path. Plus carries D-42N-MINTCLN-SCOPE-01, D-42N-EVT-BREAK-01, D-40N-LBX02-OUT-01, D-40N-MINTBOOST-OUT-01, game-over hardening (locked). | |
| Task structure + draft path + commit orchestration | Phase 297 is simpler than v41 P284 (no in-phase adversarial pass to run). Task split (likely 4 tasks: DRAFT author / VERIFY against git log + Phase 296 LOG / atomic closure-flip across 5 docs / commit + chmod 444). Draft location: planner-private `.planning/phases/297-*/297-FINDINGS-DRAFT.md` then promote to `audit/FINDINGS-v42.0.md` (v41 P284 precedent) vs. write directly to `audit/`. Closure SHA orchestration: single bundled commit vs. sequential audit-deliverable-first-then-closure-flips. | ✓ |

**User's choice:** Task structure + draft path + commit orchestration only.
**Notes:** User accepted defaults on the other three gray areas (retryLootboxRng integration; §9 verdict math; §9 deferred register). Auto-locked decisions applied per v40/v41 precedent + Phase 296 carry-forward and captured in CONTEXT.md as D-297-RETRY-INTEGRATION-01 + D-297-VERDICT-01 + D-297-DEFER-01.

---

## Closure SHA Orchestration (sub-question 1)

| Option | Description | Selected |
|--------|-------------|----------|
| 2-commit sequential | Commit 1: write `audit/FINDINGS-v42.0.md` with closure-signal SHA placeholder. Commit 2: resolve `MILESTONE_V42_AT_HEAD_<commit-1-sha>`, propagate verbatim to 5 FINDINGS locations + 3 cross-document targets, chmod 444, atomic closure-flip across ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS. Matches v41 P284 D-284-CLOSURE-01 pattern. | ✓ |
| Single bundled commit | One commit containing the audit deliverable + chmod 444 + 5-doc closure flip. Closure signal SHA self-references the commit itself — doable via post-commit `git filter-repo` SHA-substitution or via a 'SHA emitted at this commit' convention; both are operationally fragile and break the verbatim-presence-in-5-locations attestation. Used at v34 P262 but abandoned by v37 P271 onward. | |
| N-commit per-document split | One commit per closure-flip document. Cleaner per-doc audit trail but loses atomicity — a mid-sequence interrupt leaves the closure-flip half-applied. Not used at any prior milestone. | |

**User's choice:** 2-commit sequential.
**Notes:** Matches v41 P284 D-284-CLOSURE-01 precedent; closure signal MUST cite the audit-deliverable commit SHA (which is unknowable until Commit 1 lands); single-bundled commit requires SHA-self-reference convention that's operationally fragile. Recorded as D-297-CLOSURE-01.

---

## Draft Path (sub-question 2)

| Option | Description | Selected |
|--------|-------------|----------|
| Planner-private draft → promote | Author `.planning/phases/297-*/297-FINDINGS-DRAFT.md` first (planner-private; reviewable; iterable). At Commit 1, copy to `audit/FINDINGS-v42.0.md` (force-added per audit/* gitignore exception). v41 P284 precedent (`284-FINDINGS-DRAFT.md` + `284-FINDINGS-FINAL.md`). | ✓ |
| Write directly to `audit/FINDINGS-v42.0.md` | Skip the planner-private draft. Author the deliverable in-place at `audit/`. Saves one file copy but loses the planner-private review surface and the iterate-before-public-add discipline. v40 P280 + v39 P274 used direct-write; v41 P284 reverted to draft-first. | |
| Draft at planner-private + DO NOT promote | Keep the deliverable planner-private only; do not force-add to `audit/`. Breaks the audit-deliverable contract (audit/FINDINGS-v42.0.md is the canonical public deliverable per AUDIT-01). Not a viable option — listed for completeness. | |

**User's choice:** Planner-private draft → promote.
**Notes:** Preserves the planner-private review surface for T2 verification; matches v41 P284 precedent. Recorded as D-297-DRAFT-PATH-01.

---

## Task Split (sub-question 3)

| Option | Description | Selected |
|--------|-------------|----------|
| 4 tasks | T1 author `297-FINDINGS-DRAFT.md` (full 9 sections; closure-signal placeholder). T2 verify against git log v41 close..HEAD + Phase 296 LOG + REG-01..04 grep proofs. T3 promote to `audit/FINDINGS-v42.0.md` + Commit 1 (audit deliverable). T4 resolve closure signal SHA, propagate verbatim to 5+3 targets, chmod 444, atomic 5-doc closure flip + Commit 2. Mirrors v41 P284 mechanics without the in-phase adversarial pass. | ✓ |
| 5 tasks (with explicit verification phase) | Splits T2 into separate VERIFY-LOG.md task (delta-surface verification) + VERIFY-REG.md task (regression appendix verification). Heavier paper trail; matches v41 P284 verification artifact pattern but doubles the audit-side artifact count for a phase that already has lower complexity than P284. | |
| 3 tasks (compact) | T1 author + verify inline. T2 promote + Commit 1. T3 closure flip + Commit 2. Saves an artifact but loses the explicit verification checkpoint — risks shipping unverified §3.A delta-surface or REG-01..04 claims. | |

**User's choice:** 4 tasks.
**Notes:** Right balance between rigor and paper-trail weight. Phase 297 is simpler than v41 P284 (no in-phase adversarial pass to dispatch), so 5-task split is overkill; 3-task compact loses verification checkpoint. Recorded as D-297-TASK-SPLIT-01.

---

## Continue? (closing sub-question)

| Option | Description | Selected |
|--------|-------------|----------|
| No, write CONTEXT.md now | Lock the 3 user-confirmed decisions (2-commit sequential closure-SHA + planner-private draft → promote + 4-task split) plus auto-locked defaults on the 3 unselected gray areas (retryLootboxRng integration shape; §9 verdict math for (xiv) ACCEPT_AS_DOCUMENTED; §9 deferred-to-future register additions) per v40/v41 precedent + Phase 296 carry-forward. | ✓ |
| Discuss retryLootboxRng integration shape | Reopen the deferred gray area on how §3.A/§3.B/§3.C accommodate the 4th audit-subject surface + new public/external entry point exception in the 5-row roll-up + VRFStallEdgeCases.t.sol slot-drift fix row classification. | |
| Discuss §9 verdict math for (xiv) | Reopen the deferred gray area on §9 closure-verdict wording: '0 of 0 F-42-NN' (strict) vs '0 of 0 F-42-NN; 1 Tier-1 ACCEPTED_AS_DOCUMENTED' (explicit) + where the (xiv) prose lives (§4 dedicated subsection vs §4.2 citation only). | |
| Discuss §9 Deferred-to-Future register additions | Reopen the deferred gray area on which new D-42N-* deferred-decision handoffs Phase 296 generates (domain-separation policy; docstring/scope-boundary; launch-FAQ from /economic-analyst INFO observations). | |

**User's choice:** No, write CONTEXT.md now.
**Notes:** Defaults accepted on retryLootboxRng integration, §9 verdict math, and §9 deferred register.

---

## Claude's Discretion

The following gray areas were auto-locked per v40/v41/Phase 296 precedent (no user input requested; defaults applied):

- **D-297-RETRY-INTEGRATION-01** — retryLootboxRng integrated as 4th audit-subject surface row group in §3.A + 4th attestation row in §3.B (with explicit "ONE new public/external entry point" exception annotation) + 4th conservation invariant re-proof in §3.C ("entropy-correlation under daily-flow-takeover composition is INTENDED design per Phase 296 (xiv) ACCEPT_AS_DOCUMENTED").
- **D-297-VERDICT-01** — §9 verdict math stays strict `0 of 0 F-42-NN RESOLVED_AT_V42; 0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_UNMODIFIED`. Phase 296 (xiv) Tier-1 ACCEPT_AS_DOCUMENTED documented via §4.2 dedicated adversarial-disposition citation subsection + §9.NN commit-readiness register entry `ADVERSARIAL_TIER_1_RESOLVED`.
- **D-297-DEFER-01** — §9 Deferred-to-Future register carries 9 entries: 4 baseline carries (D-42N-MINTCLN-SCOPE-01, D-42N-EVT-BREAK-01, D-40N-LBX02-OUT-01, D-40N-MINTBOOST-OUT-01, game-over hardening) + 3 NEW retryLootboxRng-specific (D-42N-RETRY-RNG-DOMAIN-SEP-01, D-42N-RETRY-RNG-SCOPE-DOC-01, D-42N-RETRY-RNG-LAUNCH-FAQ-01) + 2 v42-baseline carries (superseded SURF cleanup, indexer-side update handoff, launch-posture KI policy).

The following plan-phase-discretion locks were applied per v40/v41 precedent:

- **D-297-RESEARCH-AGENT-01** — Plan-phase skips research-agent dispatch per `feedback_skip_research_test_phases.md` + Phase 284 + Phase 296 precedent.
- **D-297-ARTIFACT-SET-01** — Full v41 P284-precedent artifact shape at planner-private location: CONTEXT.md + DISCUSSION-LOG.md + 01-PLAN.md + FINDINGS-DRAFT.md + FINDINGS-VERIFY.md + promoted audit/FINDINGS-v42.0.md.
- **D-297-FINDINGS-FRONTMATTER-01** — `audit/FINDINGS-v42.0.md` frontmatter follows v41 P284 schema exactly with v42-substituted values.
- **D-297-SECTION-PROSE-01** — §3 + §4 + §5 prose copy-forward source matrix locked per phase-specific MEASUREMENT.md + DESIGN-INTENT-TRACE.md + SUMMARY.md artifacts + Phase 296 LOG.
- **D-297-COMMIT-MESSAGE-01** — Commit message shape per v41 P284 precedent (Commit 1: docs(297) publish FINAL READ-only; Commit 2: docs(297) v42.0 closure flip + propagate signal + chmod 444).
- **D-297-KI-01** — KNOWN-ISSUES.md UNMODIFIED at v42 close (default).

## Deferred Ideas

(Captured in CONTEXT.md `<deferred>` section. Highlights:)

- Domain-separation policy revisit for retryLootboxRng entropy-correlation (D-42N-RETRY-RNG-DOMAIN-SEP-01 Option B behavioral remediation) — v43+ planner-handoff.
- retryLootboxRng NatSpec/scope-boundary documentation tightening — v43+ if user wants to explicitly call out the daily-flow-takeover composition.
- Launch-comms FAQ entries on permissionless retry + governance recovery path — v43+ launch-posture review (out-of-repo, user-owned).
- LBX-02 fixture-coverage gap — RE-DEFERRED-V43+.
- Mint-boost path retention — out-of-scope register carry.
- Superseded-baseline SURF `it.skip` cleanup — RE-DEFERRED-V43+.
- Indexer-side update handoff for `TraitsGenerated` topic-hash break — out-of-repo, user-owned.
- Launch-posture KI policy — deferred per D-281-KI-01 rationale.
- Game-over hardening — descriptive label carry.
- Helper extraction for terminal-phase 2-commit SHA-orchestration pattern — post-v42 launch consideration.
- Public-citability of planner-private 296 artifacts — future-phase decision.
- Multi-finding milestone audit deliverable shape (zero F-42-NN baseline at v42 returns to default).
