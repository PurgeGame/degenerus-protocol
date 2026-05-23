---
phase: 311-spec-vrf-rotation-liveness-fix-spec
plan: 01
subsystem: audit
tags: [vrf-rotation, call-graph-manifest, grep-verification, spec, freeze-invariant, lootbox-rng]

# Dependency graph
requires:
  - phase: v44.0 closure (audit/FINDINGS-v44.0.md §9d)
    provides: the HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02 VRF-cluster source rows the §0.X mapping cross-references
provides:
  - "311-SPEC.md skeleton (header + §1–§6 placeholder headings) for Plan 02 to append into one file"
  - "§0 Call-Graph Manifest — every 311-CONTEXT.md <canonical_refs> anchor grep-verified VERIFIED-or-DRIFTED against HEAD 3153149a, with colon-joined File.sol:NNN citations"
  - "§0.X §9d-anchor → closing-change mapping (all 10 cluster anchors → D-01..D-05 → VRF-01..05)"
  - "§0.Y vault/admin-routed reach trace — the actual DegenerusAdmin + DegenerusGame dispatch sites (CONTEXT 'DegenerusVault' naming drift reconciled)"
affects: [311-02 (design narrative cites §0 rows), 312-IMPL (re-grep-verify pre-patch baseline), 313-TST]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "§0 grep-verified call-graph manifest as a discrete checkable pass before any design prose (mirrors 309-SPEC §0)"
    - "Colon-joined File.sol:NNN citations so anchors are machine-greppable (key_links pattern + verify)"
    - "DRIFTED status recorded with delta, never silently rewritten (feedback_verify_call_graph_against_source)"

key-files:
  created:
    - .planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md
  modified: []

key-decisions:
  - "Recorded _setVrfConfig as TO-BE-CREATED (D-04), not an existing call-graph node — grep returns zero matches at HEAD"
  - "Reconciled CONTEXT 'DegenerusVault' dispatch naming drift: DegenerusVault.sol does NOT dispatch either VRF admin fn; real reach is DegenerusAdmin.sol (vault-owner-gated) + DegenerusGame.sol delegatecall selectors"
  - "Recorded ADMA-02 line drift: §9d cites AdvanceModule.sol:1677, HEAD is :1688 (+11); verified HEAD line governs"
  - "Refined drain-gate revert anchors to precise statements: :213 + :238 (same-day) and :271 (new-day) vs CONTEXT's :238/:269"

patterns-established:
  - "Manifest-first: no §1–§6 design assertion may state a call path without a §0 row"
  - "Maximalist-catalog framing per project_rnglock_audit_disposition applied to the §9d mapping (rows are a catalog, not live player vectors)"

requirements-completed: [VRF-01, VRF-02, VRF-03, VRF-04, VRF-05]

# Metrics
duration: 18min
completed: 2026-05-22
---

# Phase 311 Plan 01: VRF-Rotation Liveness Fix SPEC Skeleton + §0 Call-Graph Manifest Summary

**Grep-verified §0 call-graph manifest for the VRF-rotation fix — every 311-CONTEXT anchor confirmed against HEAD 3153149a (incl. the orphan-causing `updateVrfCoordinatorAndSub:1701-1704/:1709` blanket reset, the `MintModule:686` no-zero-guard Scenario-A consumer, and the drain-gate Scenario-B reverts), plus the 10-anchor §9d→D-01..D-05 closing-change map and the corrected DegenerusAdmin/DegenerusGame vault-reach trace.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-05-22T19:44:51Z (approx — execution start)
- **Completed:** 2026-05-22
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments
- Authored `311-SPEC.md` header + §1–§6 placeholder headings so Plan 02 appends design prose to one file.
- Authored §0 IN FULL: a grep-verified call-graph manifest covering every `311-CONTEXT.md` `<canonical_refs>` / `<manifest_targets>` anchor — 23 AdvanceModule sites + the MintModule:686 consumer + 7 Storage VRF slots — each recorded VERIFIED with its matched source text against HEAD `3153149a75d0dfced1d9496d9cec348f47f6e630`.
- Confirmed the root cause at source: `updateVrfCoordinatorAndSub` force-resets at `:1701-1704` + clears `LR_MID_DAY=0` at `:1709` but never re-issues/backfills `lootboxRngWordByIndex[N]`; `MintModule:686` reads that index with NO zero-guard (Scenario A); the drain gate reverts at `:213`/`:238`/`:271` (Scenario B).
- Built the §0.X §9d-anchor → closing-change mapping for all 10 cluster anchors (HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02) → decision IDs D-01..D-05 → requirements VRF-01..05, each cross-referenced to its FINDINGS-v44.0.md §9d.2/§9d.4 source row.
- Built the §0.Y vault/admin-routed reach trace recording the ACTUAL dispatch (DegenerusAdmin.sol:458 constructor wireVrf + :901 `_executeSwap` updateVrf, both via DegenerusGame.sol delegatecall selectors at :308/:1874 → AdvanceModule impls at :498/:1688).

## Task Commits

Each task was committed atomically:

1. **Task 1: Skeleton 311-SPEC.md + §0 grep-verified call-graph manifest** - `d43dc8b2` (docs)
2. **Task 2: §0.X §9d-anchor→closing-change mapping + §0.Y vault/admin-routed reach trace** - `d2826eb6` (docs)

_No separate plan-metadata commit yet — STATE/ROADMAP/REQUIREMENTS flip lands in the final metadata commit below._

## Files Created/Modified
- `.planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` - SPEC skeleton (§1–§6 placeholders) + complete §0 manifest (§0.A AdvanceModule, §0.B MintModule consumer, §0.C Storage slots, §0.D `_setVrfConfig` to-be-created, §0.E requestRandomWords sub-block, §0.F daily-vs-mid-day branch boundary, §0.G VRF-01/02 requirement coverage, §0.H attestation, §0.X §9d mapping, §0.Y vault reach trace).

## Decisions Made
- **`_setVrfConfig` TO-BE-CREATED:** `grep -rn "_setVrfConfig" contracts/` returns zero matches; recorded as the D-04 helper to be created at Phase 312, NOT as an existing symbol, so no §1–§6 assertion treats it as an existing call-graph node.
- **"DegenerusVault" naming drift reconciled:** `contracts/DegenerusVault.sol` exists but contains zero `wireVrf`/`updateVrfCoordinatorAndSub`/`gameAdmin` references — it is the vault-ownership oracle (`vault.isVaultOwner` gate at `DegenerusAdmin.sol:437`), not a dispatch site. The real routed reach is DegenerusAdmin (vault-owner-gated wrappers) + DegenerusGame (selector `delegatecall`), both terminating at the same two AdvanceModule implementations — so the D-03 lock + D-01/D-02 safe-rotation, sitting at the delegatecall target, cover every wrapper (VRF-05 evidence).
- **ADMA-02 line drift:** §9d.4 cites `AdvanceModule.sol:1677`; HEAD has `:1688` (+11). Recorded as DRIFTED with the delta, verified HEAD line governs.
- **Drain-gate revert anchors refined:** CONTEXT cited `:209-238`/`:269`; the precise `revert` statements are `:213` (RngNotReady, same-day mid-day-pending) + `:238` (NotTimeYet, same-day tail) and `:271` (RngNotReady, new-day). Recorded both the CONTEXT span and the exact revert lines.

## Deviations from Plan

None - plan executed exactly as written. (No deviation rules fired: no bugs, no missing critical functionality, no blocking issues, no architectural changes — this is a read-only design-evidence phase.)

One in-flight correction was made to satisfy the plan's own `<verify>` automated check, not a deviation from plan intent: the §0 manifest was initially authored with line citations in a table-column format (`| :498 | 498 |`); the plan's `verify` regex and `key_links` pattern require colon-joined `File.sol:NNN` tokens (matching the 309-SPEC precedent's `File:Line` prose style). The manifest was updated to use colon-joined citations (`DegenerusGameAdvanceModule.sol:498`, etc.) before the Task 1 commit. No source facts changed — only the citation format.

## Issues Encountered
- The Task 1 `<verify>` block initially returned FAIL on the two `grep` line-citation checks because the manifest used a table-column line format rather than colon-joined `File.sol:NNN` tokens. Resolved by converting the VERIFIED-line column + key confirmations to colon-joined form; re-ran verify → PASS. Caught and fixed before committing Task 1.

## User Setup Required
None - no external service configuration required. This is a design-document (SPEC) phase: zero `contracts/` and zero `test/` mutations.

## Next Phase Readiness
- §0 is the complete, self-contained evidence base for Plan 311-02 (the design narrative). Plan 02 fills §1–§6 (Scenario A/B backward-trace, locked re-issue-in-flight fix shape, freeze-invariant disposition, wireVrf one-shot lock + `_setVrfConfig` dedup + vault reach, D-05 reachability, rejected options) and may cite any §0 row.
- `_setVrfConfig` is flagged TO-BE-CREATED — Plan 02 §4 + Phase 312 IMPL create it.
- The ADMA-02 `:1677`→`:1688` drift and the DegenerusVault naming drift are documented so the IMPL phase re-grep-verifies against `:1688` (not the stale §9d citation) and does not chase a non-existent DegenerusVault dispatch.
- No blockers. Tree is clean (`git diff --quiet -- contracts/ test/` returns no output).

## Self-Check: PASSED

- **Created file exists:** `FOUND: .planning/phases/311-spec-vrf-rotation-liveness-fix-spec/311-SPEC.md` (276 lines).
- **Task commits exist:** `FOUND: d43dc8b2` · `FOUND: d2826eb6`.
- **Clean-tree invariant:** `git diff --quiet -- contracts/ test/` returns no output (zero source/test mutations).
- **Anchor completeness:** every `manifest_targets` anchor present (AdvanceModule :498/:1044/:1048/:1097/:1133/:1134/:1688/:1701/:1709/:1711/:1756/:1761/:1768/:1772/:1208/:1817/:213/:238/:271 + requestRandomWords :1102/:1143/:1587/:1605; MintModule:686; Storage :244/:373/:1287/:1291/:1295/:1328/:1431); all 10 §9d anchors (HANDOFF-78/85/86/87/88/89/90/91 + ADMA-01/02); HEAD sha recorded; by-construction attestation present; `_setVrfConfig` TO-BE-CREATED recorded.

---
*Phase: 311-spec-vrf-rotation-liveness-fix-spec*
*Completed: 2026-05-22*
