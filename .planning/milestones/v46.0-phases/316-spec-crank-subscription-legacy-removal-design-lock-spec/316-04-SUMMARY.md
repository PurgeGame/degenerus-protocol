---
phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
plan: 04
subsystem: spec-design-lock
tags: [spec, call-graph-attestation, requirement-coverage, sc5, jgas, vrf-freeze, design-lock]
requires:
  - "316-01-SUMMARY.md (ADD-half design sections)"
  - "316-02-SUMMARY.md (REMOVE footprint + slot-shift + VRF-freeze retirement)"
  - "316-03-SUMMARY.md (open-item resolution + SUB-09)"
  - "316-05-SUMMARY.md (JGAS-01 Decision Gate)"
provides:
  - "316-SPEC.md ## Call-Graph Attestation (SC#5 deliverable — every cited file:line grep-verified against HEAD)"
  - "316-SPEC.md ## Requirement Design Coverage (42/42, four SPEC-owned)"
  - "316-SPEC.md ## Success Criteria Coverage (5/5 COVERED)"
  - "Assembled, self-consistent 316-SPEC.md — the load-bearing input for Phases 317/318/319/320"
affects:
  - "Phase 317 IMPL (consumes the attested footprint + the keeper-dependency-safe lock)"
  - "Phase 318 TST / Phase 319 GAS / Phase 320 TERMINAL (re-attest the coverage map)"
tech-stack:
  added: []
  patterns: [grep-verify-against-source-HEAD, requirement-design-coverage-map, success-criteria-coverage-map]
key-files:
  created:
    - ".planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-04-SUMMARY.md"
  modified:
    - ".planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md"
decisions:
  - "SC#5 attestation embeds RESEARCH §1 + §J1 as substrate; records every DRIFT/MISSING explicitly so the SPEC carries zero unverified call-graph claim"
  - "Intro reconciled: the JGAS jackpot-split-removal decision gate is SPEC-owned and lives in `## JGAS-01 Decision Gate` (316-05), NOT attributed to 316-02 (stale attribution fixed)"
  - "SPEC-owned primary set is FOUR: PROTO-01 / SUB-09 / RM-04 / JGAS-01"
metrics:
  duration: ~8m
  completed: 2026-05-23
  tasks: 2
  files_modified: 1
  files_created: 1
---

# Phase 316 Plan 04: Call-Graph Attestation + 42-Requirement Coverage Map + Final Assembly Summary

The SC#5 attestation backbone for the v46.0 design-lock SPEC: every `file:line` the SPEC's design sections cite (including the JGAS two-module footprint) re-grep-verified against contract HEAD with a MATCH/DRIFT/MISSING verdict per row, the keeper-dependency clean result + the J5 VRF freeze-SAFE verdict recorded, plus the 42-requirement design-coverage map (four SPEC-owned) and the 5/5 ROADMAP success-criteria map — assembled into one self-consistent design-lock document.

## What Was Built

**Task 1 — `## Call-Graph Attestation` section (SC#5 deliverable).** Appended at the end of `316-SPEC.md`:
- A per-file verdict roll-up table covering every source surface the SPEC cites: `DegenerusGame` + modules + `BurnieCoin`/`BurnieCoinflip`/`DegenerusVault`/`StakedDegenerusStonk`/`ContractAddresses`/libraries + the `StreakKeeperV2`→`AfKing` keeper — referencing `316-RESEARCH.md §1` (RM) + `§J1` (JGAS) as the verified substrate.
- **RM drift items recorded:** JackpotModule auto-rebuy block `798→800-808` (+2 cosmetic), `_distributePayout` decl `:705`/check `~738`, and the `IDegenerusGame` `setAutoRebuy/TakeProfit/AfKingMode`-NOT-present MISSING resolution.
- **JGAS footprint sub-table (embedding §J1):** `SPLIT_* :197/199/201`, `JACKPOT_MAX_WINNERS=160 :219` (dead on removal), `resumeEthPool :994` slot 33 + reads `:349/1201/1252-1253/1348`, `_resumeDailyEth :1186`, `splitMode :1248`, `call1Bucket :1270-1278/1287-1288`, threshold `:476-483`; AdvanceModule `STAGE_JACKPOT_ETH_RESUME=8 :70` + assign `:455` + resume-check `:453-456`. Each MATCH-by-value, with the **two cosmetic +1 resume-check DRIFTs** (jackpot `:348→349`, advance `:452-455→453-456`). Records `DAILY_ETH_MAX_WINNERS=305`/`DAILY_JACKPOT_SCALE_MAX_BPS=63_600`/buckets PRESERVED and stage numbers NOT load-bearing (§J2).
- **J5 VRF/freeze-SAFE verdict (HEADLINE):** resume branch never calls `_unlockRng`; single-call collapses two same-word consumptions to one; `_unlockRng` placement unmoved (`:467`); no new in-window player-mutable input; removes a cross-tx `resumeEthPool` carry = rotation-robustness improvement; only residual risk = gas-fits gated on JGAS-04; AUDIT-320 re-attests under rotation.
- **Keeper-dependency CLEAN result:** zero-match grep over the full RM-symbol set AND the JGAS symbols (re-run at HEAD — both clean); only game coupling = `hasAnyLazyPass` at keeper `:671`/`:974`; dependency-safe IFF PROTO-01 ships same diff; PROTO-side `pullForKeeper`→`burnForKeeper` interface obligation recorded.
- **Keeper transitional-state caveat (Pitfall 1):** PLAN-CRANK §9 "done this session" FALSE vs live source — SPEC locks against the intended end-state.
- **Box-cursor VRF-rotation landmine (Pitfall 3):** box cursor follows the v45 `a303ae18` re-issue path; single biggest ADD-side design risk.

**Task 2 — `## Requirement Design Coverage` + `## Success Criteria Coverage` maps + self-consistency pass.** Prepended after the intro:
- A 42-row coverage map (PROTO-01..05 · CRANK-01..04 · REW-01..04 · SUB-01..09 · RM-01..06 · SAFE-01..04 · GAS-01..06 · JGAS-01..04), each → its locking SPEC section + primary owner phase. FOUR SPEC-owned (PROTO-01/SUB-09/RM-04/JGAS-01); 26 at 317; 5 at 318; 7 at 319; 320 re-attests all 42.
- A 5-row success-criteria map; all 5 ROADMAP SCs marked COVERED (SC#4 maps to BOTH the REMOVE + Storage + VRF-Freeze sections AND `## JGAS-01 Decision Gate`).
- Self-consistency: all 13 `## ` headers referenced by the maps verified present; the document reads as one coherent design-lock spec.

## Reconciliation (the stale-attribution fix)

The SPEC intro previously attributed "the JGAS jackpot-split-removal decision gate" to **316-02**, but JGAS-01 is owned by **316-05's `## JGAS-01 Decision Gate`** section. Reconciled the intro/plan-ownership list so the JGAS gate is correctly attributed as SPEC-owned in `## JGAS-01 Decision Gate`, and added an intro paragraph stating the SPEC locks the full v46.0 add+remove+JGAS design across all 42 reqs and is the load-bearing input for Phases 317/318/319/320, with the SPEC-owned set reading as FOUR. The coverage-map header names were authored to match the actual section headers (no design section was renamed).

## Deviations from Plan

None — plan executed exactly as written. The reconcile note (stale 316-02→316-05 JGAS attribution) was applied as part of the Task-2 self-consistency pass per the plan's instruction to fix intro/attribution mismatches by editing the coverage map / intro (not by renaming design sections).

## Authentication Gates

None.

## Known Stubs

None — this is a markdown design-lock document; no code, no data-wiring stubs.

## Verification

- `## Call-Graph Attestation`, `## Requirement Design Coverage`, `## Success Criteria Coverage` headers all present.
- Task 1 automated verify: PASS (`## Call-Graph Attestation` + `hasAnyLazyPass` + DRIFT/✗ + `671` + `974` + `STAGE_JACKPOT_ETH_RESUME` + `_unlockRng` + `resumeEthPool` all present).
- Task 2 automated verify: PASS (both new headers + PROTO-01 + GAS-06 + SUB-09 + SAFE-04 + JGAS-01 + JGAS-04 present; COVERED count = 7 ≥ 5; `git diff --name-only -- contracts/ test/` empty).
- All 42 requirement IDs present in the coverage map; SPEC-owned set = exactly FOUR (`Phase 316 (SPEC-owned)` rows = 4).
- Zero fenced solidity blocks anywhere in the document (0 code fences) — no implementation bodies.
- The bare phrase "by construction" / "single fn reaches all paths" appears only inside explicit negation statements (lines 15/82/545) plus one pre-existing 316-03 flag-spoofability sentence (line 457) that is NOT a call-graph attestation claim.
- **Whole-phase source-tree freeze:** `git diff --name-only -- contracts/ test/` empty at HEAD; `git diff --name-only 9c644f94 HEAD -- contracts/ test/` empty; `git status --porcelain -- contracts/ test/` empty — ZERO `contracts/` and ZERO `test/` mutations across the entire Phase 316.
- Re-grep freshness pass at HEAD confirmed the §1 + §J1 anchors hold: JGAS (`SPLIT_NONE :197`, `STAGE_JACKPOT_ETH_RESUME=8 :70`, `resumeEthPool :994`, jackpot `:349`, advance `:453-456`), RM (`_hasAnyLazyPass :1610` + readers `:1580/:1660`, `AutoRebuyState :910`/`autoRebuyState :926`, `_processAutoRebuy :822`, `RECYCLE_BONUS_BPS=75 :129`/`AFKING_RECYCLE_BONUS_BPS=100 :130`), and keeper-dependency ZERO-match over both the RM and JGAS symbol sets.

## Self-Check: PASSED

- FOUND: `316-SPEC.md` (619 lines; both new sections + reconciled intro present)
- FOUND: `316-04-SUMMARY.md`
- FOUND: commit `ed5ea47a` (`docs(316-04): call-graph attestation (SC#5) + 42-req coverage map + final SPEC assembly`)
- No files deleted by the commit (the 5 deletions were intro-line replacements, not file removals)
- Zero `contracts/`/`test/` mutations confirmed at HEAD and across the whole phase
