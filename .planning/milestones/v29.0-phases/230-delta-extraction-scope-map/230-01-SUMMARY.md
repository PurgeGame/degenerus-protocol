---
phase: 230-delta-extraction-scope-map
plan: 01
subsystem: audit
tags: [solidity, audit, delta-extraction, catalog, interface-drift, cross-module-interaction, scope-map]

# Dependency graph
requires:
  - phase: v27.0 Phase 223 (prior milestone finalization)
    provides: 14cb45e1 baseline commit; v27.0 FINDINGS + KNOWN-ISSUES anchors; check-interfaces / check-delegatecall / check-raw-selectors Makefile gates
provides:
  - 230-01-DELTA-MAP.md — authoritative v29.0 audit-surface catalog (function-level changelog, cross-module interaction map, interface drift catalog, consumer index)
  - 117 ID-NN interface-method PASS/FAIL rows (all PASS)
  - 22 IM-NN cross-module interaction rows spanning 6 consumer-phase subsections
  - 25/25 requirement-to-section mapping for phases 231-236
affects: [Phase 231, Phase 232, Phase 233, Phase 234, Phase 235, Phase 236]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-file consolidated catalog pattern (D-05) — matches v28.0 Phase 224 bounded-scope approach"
    - "READ-only after commit pattern (D-06) — downstream gaps recorded as scope-guard deferrals rather than in-place edits"
    - "Per-method ID-NN / IM-NN row numbering for downstream greppable cross-reference"
    - "Automated-gate corroboration embedded in the catalog (check-interfaces, check-delegatecall, check-raw-selectors, forge build)"

key-files:
  created:
    - .planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md
    - .planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md
  modified: []

key-decisions:
  - "Classify 2 AdvanceModule function reformats (_payDailyCoinJackpot, _emitDailyWinningTraits from 2471f8e7) as UNCHANGED per D-03 — multi-line parameter reformats with zero token changes have no runtime effect"
  - "Include BurnieCoin.decimatorBurn → DegenerusGame.level chain (IM-09) even though the call site itself is unchanged — the MODIFIED caller's reliance on the getter is load-bearing for the decimator-burn-key correctness story"
  - "Document boonPacked auto-generated getter as not-required rather than FAIL (§3.1 note) — UI reads the concrete deployed address directly; interface-completeness gap is a Phase 236 finding candidate, not a drift failure"
  - "Record 43→44 delegatecall-site bump vs. v27.0 Phase 220 baseline directly in §3.5 — attributable to the new claimTerminalDecimatorJackpot wrapper (858d83e4); transparent to downstream auditors"
  - "Cover all 25 requirement IDs in §4 Consumer Index (not just DELTA-01/02/03 per D-11) — saves 231-236 from re-deriving scope anchors"

patterns-established:
  - "D-03 comment-only classification worked via `git diff -w --ignore-blank-lines` per-file verification"
  - "Cross-module boundary explicitly includes DegenerusGameStorage — internal inherited calls to its helpers are catalogued as cross-module per task-3 definition"
  - "Out-of-scope cross-module chains (DGNRS, Vault) are explicitly documented in the §2 preamble rather than silently omitted"

requirements-completed:
  - DELTA-01
  - DELTA-02
  - DELTA-03

# Metrics
duration: 17min
completed: 2026-04-17
---

# Phase 230-01 Summary

Delta Extraction & Scope Map — v29.0 Post-v27 Contract Delta Audit

**Authoritative v29.0 audit-surface catalog: 12-file / 10-commit delta documented across a function-level changelog, cross-module interaction map, interface drift catalog with automated gate corroboration, and a 25-requirement consumer index that lets phases 231-236 enter scope discovery without additional delta work.**

## Goal

Produce the authoritative v29.0 audit-surface catalog covering the 10 contract-touching commits between the v27.0 phase-execution-complete baseline (`14cb45e1`, 2026-04-12 21:55) and HEAD (`e5b4f97478f70c5a0b266429f03f5109078679ca`). Deliver function-level changelog (DELTA-01), cross-module interaction map (DELTA-02), and interface drift catalog (DELTA-03) in a single READ-only document so phases 231-235 consume the catalog as their scope definition with zero additional discovery and Phase 236 uses the consumer index as its findings-sourcing map. READ-only milestone — no `contracts/` or `test/` writes permitted.

## What Was Done

- **Task 1 (scaffold):** Created `230-01-DELTA-MAP.md` with preamble citing all 11 locked decisions (D-01..D-11), verdict legend for functions / interfaces / interaction call types, and a 12-row Section 0 per-file delta baseline (`Status | Insertions | Deletions | Owning Commit SHAs | Change Category`).
- **Task 2 (§1 Function-Level Changelog — DELTA-01):** 12 file subsections in category order (5 modules → 3 core → 1 storage → 3 interfaces). Per-function rows with full signature, visibility (`external` / `public` / `internal` / `private` — D-04 inclusion), verdict, owning commit SHA(s), and one-line semantic description. All 10 in-scope SHAs cited. D-03 classification applied: 2 function rows marked UNCHANGED (AdvanceModule `_payDailyCoinJackpot`, `_emitDailyWinningTraits` — pure multi-line reformats from `2471f8e7`). Non-function contract surface items (events, constants, mapping visibility) documented separately per file. Totals: NEW=3, MODIFIED=21, DELETED=0, UNCHANGED=2.
- **Task 3 (§2 Cross-Module Interaction Map — DELTA-02):** 22 IM-NN numbered rows across 6 consumer-phase subsections (231:5, 232:4, 233:7, 234:4, 235:2, other:0). Five-column D-08 table layout. Out-of-scope cross-module chains (DGNRS external contract, DegenerusVault → BurnieCoin, DGNRS pool transfers) explicitly documented in the preamble so downstream auditors aren't surprised by their omission.
- **Task 4 (§3 Interface Drift Catalog — DELTA-03):** 117 ID-NN per-method PASS/FAIL rows across §3.1 (IDegenerusGame 59), §3.2 (IDegenerusQuests 12), §3.3 (IDegenerusGameModules 46 across 9 sub-interfaces). All 117 PASS at HEAD. §3.4 records `make check-interfaces` PASS (exit 0, "all interface functions have matching implementations") and `forge build` PASS (exit 0, warnings only). `boonPacked` auto-getter classified as not-required per D-10 (UI reads the concrete address).
- **Task 5 (remaining automated gates):** Ran `make check-delegatecall` (PASS, 44/44 sites aligned — +1 vs. v27.0 Phase 220 baseline of 43 due to IM-08 `claimTerminalDecimatorJackpot` wrapper, documented inline) and `make check-raw-selectors` (PASS, 2 pre-existing justified sites in DegenerusAdmin.sol). §3.5 added; "Automated gates at HEAD —" grep-greppable rollup line published.
- **Task 6 (§4 Consumer Index + SUMMARY):** Consumer Index covers all 25 v29.0 requirement IDs with specific section/row references for phases 231-236. §4.1 confirms all 4 ROADMAP Phase 230 success criteria with citations. This SUMMARY.md created per GSD template.

## Artifacts

- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md` — authoritative v29.0 audit-surface catalog (5 top-level sections in D-05 order: §0 per-file baseline, §1 changelog, §2 interaction map, §3 drift catalog, §4 consumer index). ~620 lines, 117 ID-NN rows, 22 IM-NN rows, all 10 SHAs cited, all 25 requirements mapped.
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md` — this file.

## Counts

| Metric | Value |
|---|---|
| Files in scope | 12 |
| Commits in scope | 10 (`14cb45e1..HEAD`) |
| §1 NEW functions | 3 |
| §1 MODIFIED functions | 21 |
| §1 DELETED functions | 0 |
| §1 UNCHANGED (comment/NatSpec-only) functions | 2 |
| §1 files with at least one non-UNCHANGED function | 12 |
| §2 IM-NN rows | 22 |
| §2 chains per consumer phase | 231:5, 232:4, 233:7, 234:4, 235:2, other:0 |
| §3 ID-NN rows | 117 |
| §3 PASS | 117 |
| §3 FAIL | 0 |
| §3.1 IDegenerusGame methods | 59 |
| §3.2 IDegenerusQuests methods | 12 |
| §3.3 IDegenerusGameModules methods | 46 (across 9 sub-interfaces) |
| §4 requirements covered | 25 / 25 |

## Automated Gate Outcomes

Taken verbatim from §3.4 and §3.5 of the catalog (all at HEAD `e5b4f974`; `git status --porcelain contracts/ test/` empty throughout):

| Gate | Command | Exit | Verdict |
|---|---|---|---|
| Interface signature drift | `make check-interfaces` | 0 | PASS — "all interface functions have matching implementations" across 17 interface/implementer pairs |
| Compile smoke test | `forge build` | 0 | PASS — "Compiler run successful with warnings" (warnings are pre-existing `unsafe-typecast` lints unrelated to the delta) |
| Delegatecall target alignment | `make check-delegatecall` | 0 | PASS — 44/44 sites aligned (up from 43 at v27.0 Phase 220 baseline, attributable to IM-08 `DegenerusGame.claimTerminalDecimatorJackpot` wrapper) |
| Raw selector / hand-rolled calldata | `make check-raw-selectors` | 0 | PASS — 2 justified sites acknowledged (both in `DegenerusAdmin.sol`, out-of-scope, pre-existing allowlist) |

## Handoff to Phases 231-236

Phases 231-236 enter scope discovery via the Consumer Index (§4 of `230-01-DELTA-MAP.md`). For each of the 25 v29.0 requirements, the index names the specific sections and row IDs this catalog provides plus a one-sentence consumer-intent description. No phase needs to re-run `git diff 14cb45e1..HEAD` or re-enumerate changed functions — the surface is locked.

- **Phase 231 (EBD-01/02/03):** Cite §1.2 + §1.4 + §1.5 + §1.6 + §1.9 + §1.1 function rows and §2.1 (IM-01..IM-05) + §2.3 (IM-16) interaction rows.
- **Phase 232 (DCM-01/02/03):** Cite §1.3 + §1.8 function rows, §2.2 (IM-06..IM-09) interaction rows, and §3.1 ID-30 / §3.3.d ID-93 interface rows for the new wrapper.
- **Phase 233 (JKP-01/02/03):** Cite §1.2 + §1.4 + §1.1 + §1.11 function rows, §2.3 (IM-10..IM-16) + §2.5 IM-22 interaction rows.
- **Phase 234 (QST-01/02/03):** Cite §1.7 + §1.4 + §1.12 (QST-01), §1.9 + §1.10 note (QST-02), §1.8 (QST-03); §2.4 interaction rows.
- **Phase 235 (CONS-01/02, RNG-01/02, TRNX-01):** Cite the full pool-mutation and RNG-consumer surface across §1 and §2.5 IM-21/IM-22.
- **Phase 236 (REG-01/02, FIND-01/02/03):** Use §1 as the regression-sweep surface and the entire document (especially §4) as the findings-sourcing and consolidation map.

Per D-06, `230-01-DELTA-MAP.md` is READ-only after this plan's final commit. Any downstream phase that discovers a gap records a scope-guard deferral in its own SUMMARY (following the D-227-10 → D-228-09 precedent) rather than editing this catalog in-place. No `F-29-NN` finding IDs have been emitted by Phase 230 — finding-ID assignment is Phase 236's job.

## Known Non-Issues

Documented in the catalog for transparency; downstream phases should not reopen these as findings without new evidence:

1. **`boonPacked` auto-generated getter on `DegenerusGame` is NOT declared on `IDegenerusGame.sol`.** (`e0a7f7bc`, §3.1 note.) UI / off-chain consumers read the concrete deployed address directly. Classification: interface-completeness gap, NOT drift. If Phase 234 decides the interface should declare it, that becomes a Phase 236 finding candidate; Phase 230 does not emit one.
2. **`_payDailyCoinJackpot` and `_emitDailyWinningTraits` show in `git diff 14cb45e1..HEAD` but are UNCHANGED per D-03.** (`2471f8e7`, §1.1.) Multi-line parameter reformats only — identical tokens, zero runtime effect. Auditors doing a manual `git blame` sweep will see them but should not re-audit the bodies.
3. **IM-09 (BurnieCoin.decimatorBurn → DegenerusGame.level getter) is catalogued despite the call site itself being unchanged.** The surrounding arithmetic (`+ 1`) is the 3ad0f8d3 change — Phase 232 DCM-01 auditors should inspect the caller's use of the returned value, not the call itself.
4. **The plan `<interfaces>` block referenced 43 delegatecall sites (v27.0 Phase 220 count); the HEAD count is 44.** Delta: +1 from `DegenerusGame.claimTerminalDecimatorJackpot` (858d83e4 = IM-08). Documented inline in §3.5. All 44 PASS the alignment gate.
5. **`forge build` produces `unsafe-typecast` warnings.** None are introduced by the 10-commit delta — they are pre-existing lints on `contracts/DegenerusTraitUtils.sol`, `contracts/modules/DegenerusGameBoonModule.sol`, `contracts/BurnieCoin.sol`, and test files. Out-of-scope for this milestone.

## Self-Check

All catalog claims verified by direct inspection (section presence, row counts, commit SHA coverage, requirement coverage, gate exit codes). `git status --porcelain contracts/ test/` empty throughout all 6 tasks.

## Self-Check: PASSED

- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md` — FOUND
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md` — FOUND (this file)
- Task commits verified via `git log --oneline` (Task 1 `6902168f`, Task 2 `ab5be3fe`, Task 3 `50dcbf0d`, Task 4 `0cde8a2d`, Task 5 `a53f0072`, Task 6 pending — committed at end of this plan).
- All 10 in-scope commit SHAs cited in §1.
- All 12 in-scope files have §1 subsections.
- All 25 v29.0 requirement IDs appear in §4.
- `Requirements covered: 25 / 25` literal line present.
- No `F-29-NN` strings in 230-01-DELTA-MAP.md (finding-ID assignment deferred to Phase 236).

---
*Phase: 230-delta-extraction-scope-map*
*Completed: 2026-04-17*
