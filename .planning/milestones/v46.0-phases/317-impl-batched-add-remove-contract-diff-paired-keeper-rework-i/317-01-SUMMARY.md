---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 01
subsystem: testing
tags: [audit, call-graph-verification, forge-inspect, storage-slot-shift, foundry-baseline, rng-freeze, keeper]

# Dependency graph
requires:
  - phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
    provides: "316-SPEC.md locked design (RM-01..06, PROTO-01..05, JGAS-02, SUB-09) + Call-Graph Attestation file:line substrate"
provides:
  - "317-LEDGER.md — confirmed pre-patch file:line ledger (RM+PROTO+Crank, JGAS-02 Footprint, Pre-Deletion Test Baseline) re-grep-verified vs current source HEAD"
  - "Live keeper transitional-state table (sweepCursor/reinvestPct/windowPaid=0; pull19/mint5; RM+JGAS cross-check=0)"
  - "D-01b single-source/deploy reconciliation path (canonical AfKing.sol, AF_KING pinned-address alignment)"
  - "Pre-deletion Foundry baseline: 446 passed / 71 failed / 16 skipped — the no-NEW-failures anchor for Phase 318"
  - "forge-inspect canonical slot-≥34 −2 family + LootboxBoonCoexistence stale-baseline hazard flagged"
affects: [317-02, 317-03, 317-04, 317-05, 317-06, 317-07, 318-tst, 319-gas, 320-audit]

# Tech tracking
tech-stack:
  added: []
  patterns: ["read-first dependency ledger: every downstream edit task reads 317-LEDGER.md, not the SPEC anchors directly (T-317-01 mitigation)"]

key-files:
  created:
    - ".planning/phases/317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i/317-LEDGER.md"
  modified: []

key-decisions:
  - "_budgetToTicketUnits (JackpotModule :861) is NOT orphaned by RM-02 — 3 live callers (:400/:435/:889) outside the auto-rebuy path → KEEP, do NOT delete (corrects the SPEC's 'verify-orphaned' instruction to NOT-ORPHANED)"
  - "Pre-deletion Foundry baseline locked at 71 failing / 446 passing / 16 skipped — Phase 318 measures 'no NEW failures' against this exact count"
  - "Slot-≥34 family confirmed −2 (not −1) via forge inspect: vrfCoordinator 34→32, lootboxRngPacked 37→35, lootboxRngWordByIndex 38→36, lootboxDay 39→37, degeneretteBets 45→43, boonPacked 61→59"

patterns-established:
  - "Read-first ledger dependency: 317-02..07 edit tasks consume 317-LEDGER.md as the single source of truth for file:line, not stale SPEC anchors"

requirements-completed: [RM-04, RM-06, JGAS-02]

# Metrics
duration: 21min
completed: 2026-05-23
---

# Phase 317 Plan 01: Confirmed Pre-Patch File:Line Ledger + Baseline Snapshot Summary

**Re-grep-verified every 316-SPEC-cited file:line across the 13 protocol files + the keeper against current source HEAD (all MATCH, 3 cosmetic DRIFTs + 1 MISSING re-confirmed), captured the 71-failing pre-deletion Foundry baseline, and locked the slot-≥34 −2 shift family — the single source of truth all downstream 317 edit plans read first.**

## Performance

- **Duration:** 21 min
- **Started:** 2026-05-23T17:43:02Z
- **Completed:** 2026-05-23T18:04:04Z
- **Tasks:** 3
- **Files modified:** 1 created (`317-LEDGER.md`); ZERO `contracts/`/`test/` mutation

## Accomplishments
- **RM + PROTO + Crank Ledger** — re-grep-verified RM-01 (DegenerusGame afKing surface, 24 anchors), RM-02 (storage/jackpot/payout auto-rebuy + 8 `_addClaimableEth` consume sites), RM-03 (BurnieCoinflip recycle, incl. the `RECYCLE_BONUS_BPS=75` KEEP vs `AFKING_RECYCLE_BONUS_BPS=100` DELETE value distinction), RM-05 (interfaces/Vault/sStonk cascade), all PROTO target sites + crank reuse sites. Every cited anchor MATCH at live HEAD. `_hasAnyLazyPass :1610` body + ctor Deity grants `:222`/`:223` confirmed byte-unmodified (RM-04 / SUB-09 PRESERVE targets).
- **Zero-orphan greps** — `_budgetToTicketUnits` found NOT orphaned (3 live callers → KEEP, correcting a potential misdelete); `AutoRebuyCalc` orphaned only post-`_calcAutoRebuy` deletion (DELETE).
- **JGAS-02 Footprint Ledger** — full two-module deletion set (Jackpot + Advance) + storage `resumeEthPool :994` re-verified; both cosmetic `+1` resume-check DRIFTs re-confirmed; `JACKPOT_MAX_WINNERS=160` confirmed split-routing-threshold-only (DEAD on removal, NOT a winner cap); PRESERVE set (305 ceiling, 63_600 scale, 159/95/50/1 buckets) recorded out-of-deletion; `_unlockRng` confirmed NOT inside the resume branch `:453-457` (J5 freeze-SAFE re-confirmed).
- **Live keeper transitional-state table** — `sweepCursor`/`reinvestPct`/`windowPaid` = 0 (genuinely unbuilt), `pullForKeeper`=19/`mintForKeeper`=5 still present, live `subscribe`/`sweep` pre-rework signatures recorded; keeper RM-symbol + JGAS-symbol cross-checks = 0 matches (dependency CLEAN; only game coupling = `hasAnyLazyPass :671/:974`).
- **D-01b reconciliation** — canonical `contracts/AfKing.sol` single-source path + `AF_KING` pinned-address alignment via the utilities deploy-predict+patch pipeline recorded.
- **Pre-Deletion Test Baseline** — Foundry default-profile run: 446 passed / 71 failed / 16 skipped (533 total, 61 suites); named the SPEC-flagged `test_lootboxBoonAppliedDespiteExistingCoinflipBoon` failure + pre-existing failure clusters; `forge inspect` canonical slots captured + the slot-≥34 −2 family + the `LootboxBoonCoexistence` stale-baseline hazard flagged so the post-deletion delta stays attributable.

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-grep-verify RM + PROTO + crank file:line set** - `f389e3c2` (docs)
2. **Task 2: Re-grep JGAS-02 two-module footprint + keeper transitional state + D-01b** - `bdaa3129` (docs)
3. **Task 3: Capture pre-deletion test baseline-failure ledger** - `c7b5cc94` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately as the final metadata commit.

## Files Created/Modified
- `.planning/phases/317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i/317-LEDGER.md` - The confirmed pre-patch file:line ledger + baseline snapshot; the read-first single source of truth for all 317-02..07 edit plans.

## Decisions Made
- **`_budgetToTicketUnits` is KEPT, not deleted.** The SPEC's "verify-orphaned … confirm no surviving caller post-cut" instruction resolves to NOT-ORPHANED at HEAD — it has 3 live callers (`:400`/`:435`/`:889`) in the daily-ticket budget path, outside the auto-rebuy chain. Recorded so the downstream RM-02 edit does not misdelete it.
- **Baseline failure count locked at 71.** This is the v45-closure inherited baseline (consistent with MEMORY's "suite has unrelated pre-existing baseline failures"). Phase 318's "no NEW failures" gate is measured against this number; the slot re-derivation must not be blamed for any of the 71 pre-existing failures.
- **Fork tests excluded from the baseline run** (`--no-match-path "test/**/*.fork.t.sol"`) — they require a live RPC and are not part of the `SLOT_*` slot-re-derivation surface. The fast default profile (fuzz=1000) was used per the plan's "snapshot not coverage" directive.

## Deviations from Plan

None - plan executed exactly as written. All three tasks read + grep + forge-inspect + write-markdown only; zero source mutation throughout. The one substantive finding (the `_budgetToTicketUnits` NOT-orphaned correction) is a verification result recorded in the ledger, not a deviation in execution — it is precisely the kind of stale-anchor correction this re-verification plan exists to catch (`feedback_verify_call_graph_against_source`).

## Issues Encountered
- `forge build` emits forge-lint advisory hints (`unsafe-typecast` next-line-disable suggestions) but compiles cleanly; these are pre-existing lint notes, not errors, and out of scope (no source touched).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **317-02..07 (the edit plans) are unblocked** — they read `317-LEDGER.md` first for confirmed file:line, the keeper transitional end-state, the D-01b deploy path, and the −2 slot family.
- **318 TST is anchored** — the 71-failing pre-deletion baseline is captured for the "no NEW failures vs baseline" proof; the `LootboxBoonCoexistence` stale-baseline hazard is flagged so the slot re-derivation delta stays attributable.
- **One downstream caution surfaced:** `_budgetToTicketUnits` must be KEPT (3 live callers) — the RM-02 edit plan must not treat it as orphaned.
- No blockers. The single batched USER-APPROVED `contracts/` diff is authored downstream (W5, `autonomous: false`); this plan touched no source.

## Self-Check: PASSED

- `317-LEDGER.md` exists (FOUND).
- Commits `f389e3c2`, `bdaa3129`, `c7b5cc94` exist (FOUND).
- `git diff --stat -- contracts/` empty across all 3 task commits (CONFIRMED — zero source mutation).
- All three required ledger sections present (RM + PROTO + Crank, JGAS-02 Footprint, Pre-Deletion Test Baseline) + keeper transitional-state table + D-01b reconciliation (CONFIRMED).

---
*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Completed: 2026-05-23*
