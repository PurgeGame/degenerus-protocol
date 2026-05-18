---
phase: 299-fix-recommendation-document-fixrec
plan: 05
subsystem: audit-fixrec
tags: [rnglock, claimablepool, game-over, drain-window, liveness-gate, fixrec]

requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: RNGLOCK-CATALOG.md §14 S-16, §15 writer enumeration rows 178-189, §16 verdict-matrix rows 388-400 (V-054, V-055, V-057, V-058, V-063, V-064, V-065)
provides:
  - Per-VIOLATION analytical FIXREC entries for Cluster E — claimablePool game-over family
  - 7 §N entries × 4 sub-sections = 28+ sub-section anchors
  - 7 v44.0 FIX-MILESTONE handoff anchors D-43N-V44-HANDOFF-27..33
  - 4 catalog-label-inaccuracy refinements queued for Phase 303 TERMINAL acknowledgment (V-054, V-057, V-058, V-065 writer-name labels)
affects: [v44.0-fix-milestone, phase-303-findings, phase-301-fuzz, cluster-b-prizepool-family, cluster-f-balance-family]

tech-stack:
  added: []
  patterns: [tactic-a-livenesstriggered-gate, gameover-carveout-for-withdraw-paths, multi-tx-game-over-window-discipline, per-callsite-eoa-vs-vrfcallback-split]

key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-05-FIXREC-cluster.md
  modified: []

key-decisions:
  - "V-054: gate claimDecimatorJackpot:321 on !_livenessTriggered() && !gameOver — closes _creditDecJackpotClaimCore:388 EOA reach (catalog mislabel: writer is in _creditDecJackpotClaimCore not _awardDecimatorLootbox)"
  - "V-055: existing MintModule._purchaseFor/_purchaseCoinFor/_purchaseBurnieLootboxFor _livenessTriggered() gate at MintModule:877/:906/:1215 already covers; FUZZ-301 branch-coverage attestation only — no source change"
  - "V-057: gate placeDegeneretteBet:367 on !_livenessTriggered() — closes _collectBetFunds:547 EOA reach (catalog mislabel: writer is in _collectBetFunds not _creditCheckedFromClaimable)"
  - "V-058: gate resolveBets:389 on !_livenessTriggered() — closes _addClaimableEth:1131 EOA reach; preserves EXEMPT-VRFCALLBACK branch via VRF-callback reach (catalog mislabel: writer is in _addClaimableEth not _resolveLootboxDirect)"
  - "V-063: gate _claimWinningsInternal:1399 on !_livenessTriggered() && !gameOver — closes BOTH external entries (claimWinnings + claimWinningsStethFirst); CATASTROPHE-tier; same gate closes V-073 address(this).balance outflow in Cluster F"
  - "V-064: existing MintModule._purchaseFor/_purchaseCoinFor/_purchaseBurnieLootboxFor _livenessTriggered() gate at MintModule:877/:906/:1215 already covers; FUZZ-301 branch-coverage attestation only — no source change"
  - "V-065: gate resolveRedemptionLootbox:1721 on !_livenessTriggered() && !gameOver — mirror of V-063; sDGNRS-callback reach (catalog mislabel: function is resolveRedemptionLootbox not sweepSdgnrsClaim)"
  - "Tactic mix: 7/7 select tactic (a) gated-revert. Zero tactic (b) snapshot, zero tactic (c) reorder, zero tactic (d) immutable. Rationale: consumer handleGameOverDrain has one-shot SLOAD chain with no recurring axis to snapshot against; (a) is structurally minimal"
  - "EV distribution: 1 CATASTROPHE-tier (V-063), 2 HIGH-tier (V-058, V-065), 2 MEDIUM-tier (V-057, V-054), 2 ZERO-tier (V-055, V-064 structurally unreachable by existing gate)"
  - "Catalog-label-inaccuracy summary: 4 catalog rows have writer-function-name mislabels (V-054, V-057, V-058, V-065); all are LABEL-only — writer-site file:line, verdict-matrix disposition, and recommended tactic are correctly captured. NONE are stale-phantoms. Phase 303 TERMINAL should update the 4 row labels"

patterns-established:
  - "Tactic (a) gated-revert with !_livenessTriggered() && !gameOver discipline: gate=close-window-pre-gameOver, carveout=permanent-reopen-post-gameOver"
  - "Tactic (a) gated-revert with !_livenessTriggered() only (no gameOver carve-out): for gameplay-action functions where post-gameOver behavior is not required (V-057 placeDegeneretteBet, V-058 resolveBets)"
  - "Internal-function gating discipline (V-063 at _claimWinningsInternal:1399) covers both external entry points via shared private path"
  - "Catalog-label-inaccuracy classification: writer-function-name mislabels are NOT stale-phantoms when the underlying writer-site file:line and verdict-matrix disposition are correctly captured. Mark for Phase 303 TERMINAL label-refinement, not for stale-phantom acknowledgment"

requirements-completed: [FIXREC-01, FIXREC-02, FIXREC-03, FIXREC-04, FIXREC-05]

duration: ~25min
completed: 2026-05-18
---

# Phase 299 Plan 05: FIXREC Cluster E (claimablePool game-over family) Summary

**Per-VIOLATION analytical FIXREC entries for the claimablePool (S-16) writer-race class during the multi-tx game-over drain window — 7 logical VIOLATIONs covered with tactic (a) gated-revert across 5 new-gate writers + 2 already-gated writers (FUZZ-301 verification-only).**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-18 (Phase 299 wave-1 parallel dispatch, agent 4 of 4)
- **Completed:** 2026-05-18
- **Tasks:** 1 (Task 1: Author Cluster-E FIXREC contribution)
- **Files modified:** 1 (the new Cluster-E FIXREC file)

## Accomplishments

- Authored `.planning/phases/299-fix-recommendation-document-fixrec/299-05-FIXREC-cluster.md` covering V-054, V-055, V-057, V-058, V-063, V-064, V-065 — 7 VIOLATION rows on slot S-16 (`claimablePool`).
- 7 v44.0 FIX-MILESTONE handoff anchors emitted: `D-43N-V44-HANDOFF-27` through `D-43N-V44-HANDOFF-33`.
- Each entry includes 4 sub-sections (§N.A design-intent backward-trace, §N.B actor game-theory walk, §N.C recommended tactic + rationale + impact estimate, §N.D v44.0 handoff anchor).
- All 4 sub-section markers present: A=15, B=10, C=15, D=7 (≥7 each per verification threshold; counts exceed 7 due to multiple sub-section references within entries).
- Source-of-truth verification: every writer-site file:line in the 7 catalog rows verified against current `contracts/` source via grep per `feedback_verify_call_graph_against_source.md`. 4 catalog rows carry writer-function-name labels that DO NOT match current source function names (V-054, V-057, V-058, V-065); all 4 are LABEL-only inaccuracies (writer-site file:line + verdict + tactic remain correct). Documented as `CATALOG-LABEL-INACCURACY` in each §N section + summary table. NONE are stale-phantoms.
- Cluster preamble (~80 lines) establishes the `claimablePool` dual-role architecture (post-credit reserve aggregate + post-withdraw debit aggregate), the `handleGameOverDrain` SLOAD chain (`:84/:91/:99/:110/:134/:139/:154/:156/:166/:182`), the multi-tx game-over window discipline (between `rngWordByDay[day]` write and `handleGameOverDrain` consumer execution), and the `_livenessTriggered()` source-of-truth verbatim (from `DegenerusGameStorage.sol:1243-:1252`).
- Tactic-(a) gate discipline documented per writer class: `_livenessTriggered() && !gameOver` for withdraw/claim paths that must permanently re-open post-gameOver (V-054, V-063, V-065); `_livenessTriggered()` only for gameplay-action paths with no post-gameOver requirement (V-057, V-058); no source change for already-gated paths (V-055, V-064 — covered by existing in-source `MintModule:877/:906/:1215/:1381` gates).

## Verification Run

```
test -f .planning/phases/299-fix-recommendation-document-fixrec/299-05-FIXREC-cluster.md  → OK
V-054, V-055, V-057, V-058, V-063, V-064, V-065 all present                              → OK
D-43N-V44-HANDOFF-27..33 all present                                                     → OK
§N.A markers: 15 (≥7)                                                                    → OK
§N.B markers: 10 (≥7)                                                                    → OK
§N.C markers: 15 (≥7)                                                                    → OK
§N.D markers: 7 (≥7)                                                                     → OK
SAFE_BY_DESIGN tokens: 0                                                                 → OK
contracts/ + test/ mutations: 0                                                          → OK
```

Final result: **OK**.

## Self-Check: PASSED

- File `.planning/phases/299-fix-recommendation-document-fixrec/299-05-FIXREC-cluster.md` exists with all 7 §N entries + 4 sub-sections each.
- All 7 handoff anchors `D-43N-V44-HANDOFF-27` through `D-43N-V44-HANDOFF-33` present.
- Zero `contracts/` mutations, zero `test/` mutations.
- Zero `SAFE_BY_DESIGN` upper-case-underscore tokens.
- Zero stale-phantom catalog rows (all 7 writer-site file:line verified against current source); 4 catalog-label-inaccuracy refinements documented for Phase 303 TERMINAL acknowledgment.

## Deviations from Plan

None — plan executed exactly as written. The plan's "stale-phantom" provision was exercised but yielded zero stale-phantoms (all 7 rows are source-of-truth-accurate at the file:line level); 4 catalog-label-inaccuracy refinements were instead documented per `feedback_verify_call_graph_against_source.md`.
