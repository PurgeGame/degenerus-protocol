---
phase: 396-terminal
plan: 01
subsystem: audit-adjudication
tags: [v63, terminal, consolidation, council-on-refuted, skeptic-gate]
requires:
  - all 389-395 per-phase FINDINGS (both nets on record)
  - the council script (.planning/audit-v52/cross-model/bin/council.sh, gemini + codex available)
provides:
  - 396-CONSOLIDATED-LEDGER.md (deduped master ledger across 389-395)
  - 396-COUNCIL-ON-REFUTED.md (council re-run record + adjudications)
  - 396-SKEPTIC-GATE.md (skeptic clearance, no severity above MED)
affects:
  - 396-02 (FINDINGS-v63.0.md deliverable) and 396-03 (closure flip) consume this ledger
tech-stack:
  added: []
  patterns: [council-on-refuted, dual-net-on-record, skeptic-gate, frozen-source-adjudication]
key-files:
  created:
    - .planning/phases/396-terminal/396-CONSOLIDATED-LEDGER.md
    - .planning/phases/396-terminal/396-COUNCIL-ON-REFUTED.md
    - .planning/phases/396-terminal/396-SKEPTIC-GATE.md
    - .planning/audit-v52/cross-model/396-terminal/PROMPT-refuted.txt
    - .planning/audit-v52/cross-model/396-terminal/PROMPT-secondsource.txt
    - .planning/audit-v52/cross-model/396-terminal/council/ (raw gemini + codex outputs, both charge sets)
  modified: []
decisions:
  - "RNG-04 codex BREAKS adjudicated REFUTED at frozen source — the reverseFlip nudge is a documented by-design PRE-reveal blind offset gated by rngLockedFlag; the base word is unknown at commitment (predictability-without-control), not after-reveal steering. codex's own answer records the gating fact."
  - "All 4 refuted-HIGH candidates remain REFUTED after the fresh council pass (3 confirmed by both models; RNG-04 adjudicated)."
  - "Every pending second-source resolved — both council models now on record for every sweep area; all converge with the prior verdicts."
  - "Sole CONFIRMED finding = BURNIE-04 (MED, routed gated fix). No CATASTROPHE/HIGH."
metrics:
  tasks: 3
  files: 6
  duration: ~40m
  completed: 2026-06-15
---

# Phase 396 Plan 01: TERM-01 Consolidation + Council-on-Refuted + Skeptic Gate Summary

Consolidated both v63.0 finding nets (council + Claude) across the seven sweep phases (389-395) into one
deduped master ledger, re-ran the cross-model council on the 4 Claude-REFUTED HIGH candidates plus every
pending second-source, adjudicated the one council contradiction (codex RNG-04 "BREAKS") against frozen
source, and cleared the skeptic gate — the FINDINGS document carries no severity above MED, with BURNIE-04
(MED, routed gated fix) the sole CONFIRMED finding.

## What was built

- **Task 1 — `396-CONSOLIDATED-LEDGER.md`** (273 lines): one deduped row per lead/finding across 389-395
  (89 deduped rows), each with ID, sweep phase, dimension, severity, net-of-origin (council/Claude/both/
  mutation), description, final verdict, and second-source status. Convergent council+Claude leads collapsed
  to one "both"-tagged row. Count-summary block: **CONFIRMED count = 1 (BURNIE-04)**. The 4 refuted-HIGH
  candidates flagged `[396-RERUN]`; the 7 mutation survivors recorded KILLED-by-regression; R-389-01 recorded
  as a LOW test-only oracle item. Committed `7b78d36d`.

- **Task 2 — `396-COUNCIL-ON-REFUTED.md`** (139 lines) + raw council outputs under
  `.planning/audit-v52/cross-model/396-terminal/`: re-dispatched the council (gemini-3-pro + codex, both
  read-only) for two charge sets. **Charge set A** (4 refuted HIGH): ECON-04 / ECON-06 / SOLV-07 confirmed
  HOLDS by BOTH models; RNG-04 drew gemini HOLDS + a codex "BREAKS (ACTIONABLE)" that was traced and
  REFUTED at frozen source. **Charge set B** (pending second-sources — 392/393 codex usage-cap, 394 v51
  gemini non-response): every area now has both models on record, all CONVERGE with the prior verdicts
  (BURNIE-04 DEFECT/conservative-under-credit; BURNIE-05 DEFECT/protocol-owned-op-risk; ACCESS-02/04 SOUND;
  LEGACY-03/04 SOUND). Subject byte-frozen verified after the fan-out. Committed.

- **Task 3 — `396-SKEPTIC-GATE.md`** (96 lines): two-lens skeptic check (structural-protection + 3-condition
  EV) on every MED-or-above entry. BURNIE-04 confirmed at MED (conservative, off ETH spine, no attacker
  profit, no insolvency — NOT HIGH/CATASTROPHE); BURNIE-05 BY-DESIGN/WONTFIX survives; the 4 refuted
  candidates recorded as remaining refuted. **Clearance: no severity above MED.**

## The one council contradiction — adjudicated, not auto-accepted

codex flagged RNG-04 as "BREAKS (ACTIONABLE)" claiming `reverseFlip()`'s +1 nudge is a player-controllable
input into the decimator word. Traced at `a8b702a7`:

- `reverseFlip` reverts when `rngLockedFlag` is true (DegenerusGame.sol:1817) — a nudge can only be queued
  while RNG is UNLOCKED.
- The lock is set at VRF REQUEST time with `rngWordCurrent = 0` (AdvanceModule:1697-1699), before the base
  word lands; `_applyDailyRng` folds `totalFlipReversals` into the freshly-delivered word and then ZEROES it
  (:1882-1889).
- Net: the nudge is committed strictly BEFORE the base word is known on-chain → predictability-WITHOUT-control
  (a blind additive offset, no targeted steer), the contract's own documented invariant ("Players cannot
  predict the base word, only influence it", :1814-1816). codex's own answer records the gating fact ("I do
  not find after-reveal steering: `reverseFlip` reverts once `rngLockedFlag` is true").

**Verdict: REFUTED at frozen source.** RNG-04 remains benign INFO/LOW. gemini independently ruled RNG-04
HOLDS in the same charge set.

## Deviations from Plan

None — the plan executed as written. The expected outcome ("the council CONFIRMS the refutations") held: 3
of 4 candidates confirmed by both models, the 4th adjudicated to the same refuted verdict; charge set B
converged on every prior verdict; no genuine new CONFIRMED HIGH/CATASTROPHE surfaced.

## Threat-model mitigations applied

- **T-396-01 (council fan-out mutating contracts/):** mitigated — `git diff a8b702a7 -- contracts/` EMPTY
  after the fan-out; both contracts tree-hashes == `2934d3d8987a09c5f073549a0cb499f6c5f28620`; council ran
  read-only; no stray file outside the council dir (only the pre-existing `PLAYER-PURCHASE-REWARDS.html`).
- **T-396-02 (refuted HIGH dismissed without council on record):** mitigated — the council-on-refuted re-run
  is on record for all 4 candidates; the one contradiction adjudicated vs frozen source, not auto-accepted.
- **T-396-03 (over-stated severity):** mitigated — the skeptic gate caps severity at MED before the FINDINGS
  document is authored.

## Known Stubs

None — these are adjudication/ledger artifacts, not code.

## Verification

- All three artifacts exist with the required content; automated verify PASS for Tasks 1/2/3; line counts
  273/139/96 exceed the 60/30/20 minimums.
- BURNIE-04 is the single CONFIRMED finding (MED); the 4 refuted-HIGH candidates carry a fresh council
  verdict on record (each remaining refuted).
- `git diff a8b702a7 -- contracts/` EMPTY; contracts tree-hash matches after the council fan-out.
- No severity above MED asserts after the skeptic gate.

## Self-Check: PASSED
