---
phase: 236-regression-findings-consolidation
plan: 01
subsystem: audit-findings-consolidation
tags: [consolidation, findings, audit, v29.0, known-issues]
requires: [.planning/phases/233-jackpot-baf-entropy-audit/233-01-AUDIT.md, .planning/phases/234-quests-boons-misc-audit/234-01-AUDIT.md, .planning/phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-AUDIT.md, audit/FINDINGS-v27.0.md, KNOWN-ISSUES.md]
provides: [audit/FINDINGS-v29.0.md, "updated KNOWN-ISSUES.md with 2 new KI entries + 3 v29.0 back-refs"]
affects: [audit/FINDINGS-v29.0.md, KNOWN-ISSUES.md]
key-files-created: [audit/FINDINGS-v29.0.md]
key-files-modified: [KNOWN-ISSUES.md]
decisions:
  - "F-29-01 + F-29-02 kept as two separate FINDINGS blocks for narrative clarity; KI consolidation into a single entry happens at the KNOWN-ISSUES.md layer per 236-CONTEXT.md D-05"
  - "Resolution field values chosen: OFF-CHAIN-INDEXER-REGEN for F-29-01/02 (event ABI regeneration required), INFO-ACCEPTED for F-29-03 (test-coverage gap), DESIGN-ACCEPTED for F-29-04 (Gameover RNG substitution)"
  - "KI file target confirmed as repo-root KNOWN-ISSUES.md (ROADMAP typo cited audit/KNOWN-ISSUES.md; confirmed no such file exists)"
  - "D-09 suppression honored: 232.1 RNG-index ordering invariant NOT promoted to KI (hardening, not new architecture)"
  - "D-10 suppression honored: F-29-03 NOT promoted to KI (test-tooling observation, not a design decision)"
metrics:
  tasks: 2
  commits: 2
  files_created: 1
  files_modified: 1
  lines_added_findings: 166
  lines_net_known_issues: "+7/-3"
  duration_minutes: 8
  completed: 2026-04-18
---

# Phase 236 Plan 01: Findings Consolidation + KNOWN-ISSUES Updates Summary

One-liner: Authored `audit/FINDINGS-v29.0.md` (new v27.0-style consolidated report with 4 F-29-NN INFO blocks, 0/0/0/0/4 severity, per-phase sections 231→232→232.1→233→234→235) and updated root `KNOWN-ISSUES.md` with 2 new design-decision entries (BAF event-widening + `BAF_TRAIT_SENTINEL=420` pattern; Gameover RNG substitution codifying the "RNG-consumer determinism" invariant) plus 3 targeted v29.0 back-refs on existing entries.

## What Shipped

### Files Modified

| File | Change | Commit |
|------|--------|--------|
| `audit/FINDINGS-v29.0.md` | Created (166 lines) — v27.0-style consolidated findings report with exec summary (0/0/0/0/4), six per-phase subsections, four F-29-NN INFO blocks, Summary Statistics + Audit Trail. No Regression Appendix (Plan 02 scope). | `519b57e8` |
| `KNOWN-ISSUES.md` | +7/-3 lines — two new Design-Decisions entries inserted between the Decimator-over-reserves entry and the VRF_KEY_HASH entry; three existing entries gained appended v29.0 back-refs. | `5de8ad0c` |

### Canonical F-29-NN Range Used

Range: **F-29-01 .. F-29-04** (contiguous; no gaps; no F-29-05+)

| ID | Phase | Title | Resolution |
|----|-------|-------|------------|
| F-29-01 | 233 | `JackpotEthWin` event signature widened uint8→uint16 traitId for `BAF_TRAIT_SENTINEL=420` carry | OFF-CHAIN-INDEXER-REGEN |
| F-29-02 | 233 | `JackpotTicketWin` event signature widened uint8→uint16 traitId for `BAF_TRAIT_SENTINEL=420` carry | OFF-CHAIN-INDEXER-REGEN |
| F-29-03 | 234 | QST-01 `d5284be5` companion test-file update contains no positive coverage for the new wei-direct `mint_ETH` quest-credit path | INFO-ACCEPTED |
| F-29-04 | 235 | Gameover RNG substitution for mid-cycle write-buffer tickets (RNG-consumer-determinism invariant violation at terminal state) | DESIGN-ACCEPTED |

### F-29-01 vs F-29-02 Consolidation Decision

Per 236-01-PLAN.md Task 1 guidance and 236-CONTEXT.md D-Claude's Discretion: the two 233-01 event-widening observations are kept as **two separate F-29-NN blocks** in `audit/FINDINGS-v29.0.md` for narrative clarity (each has distinct event-decl line numbers and a distinct canonical-signature change). Consolidation happens at the `KNOWN-ISSUES.md` layer per D-05 — a single KI entry covers both events as one design pattern expressed across two event declarations.

### KNOWN-ISSUES.md Edits

**Sub-edit A — NEW entry per D-05:** "BAF event-widening and `BAF_TRAIT_SENTINEL=420` pattern." — inserted after the Decimator-over-reserves entry, before the VRF_KEY_HASH entry. References F-29-01 and F-29-02.

**Sub-edit B — NEW entry per D-06/D-07:** "Gameover RNG substitution for mid-cycle write-buffer tickets." — inserted immediately after Sub-edit A's entry. Codifies the "RNG-consumer determinism" invariant name; documents the terminal-state violation with player-reachability and acceptance rationale. References F-29-04.

**Sub-edit C — APPEND v29.0 back-refs to three existing KI entries per D-08:**
- `Gameover prevrandao fallback` → appended `; re-verified v29.0 Phase 235 RNG-01 at HEAD 1646d5af — see audit/FINDINGS-v29.0.md regression appendix`
- `Lootbox RNG uses index advance isolation instead of rngLockedFlag` → appended `; re-verified v29.0 Phase 235 RNG-01 + RNG-02 at HEAD 1646d5af`
- `Decimator settlement temporarily over-reserves claimablePool` → appended `; re-verified v29.0 Phase 235 CONS-01 at HEAD 1646d5af`

### Suppressions Honored

- **D-09:** 232.1 RNG-index ticket drain-ordering invariant NOT promoted to KI (hardening that makes an implicit invariant explicit; not a new architectural design decision). Zero mention in KNOWN-ISSUES.md.
- **D-10:** F-29-03 NOT promoted to KI (test-tooling observation, not a design decision). Zero KI cite for F-29-03.
- **D-11:** v28.0's D-229-10 KI-promotion-suppression directive does NOT apply to v29.0 — v29.0 is a contract-side delta audit with normal v25/v27 KI promotion semantics.

### DO-NOT-TOUCH Verification

All 12 existing KI design-decisions entries outside the D-08 back-ref list remain **byte-unchanged**:
- `All rounding favors solvency`, `Daily advance assumption`, `Non-VRF entropy for affiliate winner roll`, `VRF swap governance`, `Price feed swap governance`, `Chainlink VRF V2.5 dependency`, `Backfill cap at 120 gap days`, `Lido stETH dependency`, `EntropyLib XOR-shift PRNG for lootbox outcome rolls`, `Deploy-pipeline VRF_KEY_HASH regex is single-line only`, ``Parallel `make -j test` mutates `ContractAddresses.sol` concurrently``, `v27.0 Phase 222 VERIFICATION gap closures (in-cycle)`

Entire "## Automated Tool Findings (Pre-disclosed)", "## ERC-20 Deviations", and "## Event Design Decisions" sections unmodified.

## Scope Boundary Gates Held

- **Zero `contracts/` writes:** `git diff --name-only HEAD~2 HEAD -- contracts/` returns empty across both commits (519b57e8 + 5de8ad0c).
- **Zero `test/` writes:** `git diff --name-only HEAD~2 HEAD -- test/` returns empty across both commits.
- **No stray `audit/KNOWN-ISSUES.md` created:** ROADMAP §Phase 236 Success Criterion #4 path typo confirmed; only repo-root `KNOWN-ISSUES.md` exists and was edited.
- **No Regression Appendix:** `grep -q "^## Regression Appendix" audit/FINDINGS-v29.0.md` returns no match — Plan 236-02 owns that section.

## Deviations from Plan

None — plan executed exactly as written. Both tasks landed on their first attempt; every acceptance criterion gate in Task 1 (27 gates) and Task 2 (19 gates) passed.

## Hand-off Note for Plan 236-02

`audit/FINDINGS-v29.0.md` ends at a cross-reference placeholder paragraph:

> *Regression verification of all 16 v27.0 INFO findings (F-27-01..16) + 3 v27.0 KNOWN-ISSUES entries + 13 v25.0 INFO findings (F-25-01..13) + v26.0 design-only milestone conclusions is provided in the Regression Appendix below (to be authored by Plan 236-02).*

Plan 236-02 should append `## Regression Appendix` + `## Regression Summary` sections directly after this paragraph, mirroring the `audit/FINDINGS-v27.0.md` Regression Appendix structure (per-item table with columns `ID | Severity-at-origin | Current verdict (PASS/REGRESSED/SUPERSEDED) | Evidence`). 32 regression rows expected (16 v27.0 INFO + 3 v27.0 KI + 13 v25.0 INFO + 0 v26.0 since v26.0 is design-only).

## Commits

| Task | Commit | Subject |
|------|--------|---------|
| Task 1 | `519b57e8` | `docs(236-01): create audit/FINDINGS-v29.0.md with 4 F-29-NN INFO blocks` |
| Task 2 | `5de8ad0c` | `docs(236-01): update KNOWN-ISSUES.md with 2 new KI entries + 3 v29.0 back-refs` |

## Self-Check: PASSED

- `audit/FINDINGS-v29.0.md` exists and contains all required structural markers (title, Executive Summary, Findings root, six `### Phase ...` subsections in phase order, four `#### F-29-NN:` blocks, Summary Statistics, Audit Trail, cross-reference note).
- `KNOWN-ISSUES.md` contains `BAF_TRAIT_SENTINEL`, `RNG-consumer determinism`, `F-29-01 and F-29-02`, `F-29-04`, and the three v29.0 Phase 235 back-ref phrases.
- Commits `519b57e8` and `5de8ad0c` both reachable from HEAD.
- `audit/KNOWN-ISSUES.md` does not exist.
- `git diff --name-only HEAD~2 HEAD -- contracts/ test/` empty.
