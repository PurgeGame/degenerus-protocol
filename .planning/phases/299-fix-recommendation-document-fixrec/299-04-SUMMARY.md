---
phase: 299-fix-recommendation-document-fixrec
plan: 04
subsystem: audit-fixrec
tags: [rnglock, sdgnrs, pool-balances, cross-contract, oz-carveout, snapshot, fixrec]

requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: RNGLOCK-CATALOG.md §14 S-14/S-15, §15 writer enumeration rows 170-177, §16 verdict-matrix rows 376-387 (V-043, V-045..V-048, V-050, V-051)
provides:
  - Per-VIOLATION analytical FIXREC entries for Cluster D — sDGNRS poolBalances Reward + Lootbox cross-contract slot family
  - 7 §N entries × 4 sub-sections = 28 sub-section anchors
  - 7 v44.0 FIX-MILESTONE handoff anchors D-43N-V44-HANDOFF-20..26
  - V-046 OZ-inherited writer carve-out attestation per D-298-OZ-CARVEOUT-01 (fix lands in contracts/, not node_modules/)
affects: [v44.0-fix-milestone, phase-303-findings, phase-301-fuzz]

tech-stack:
  added: []
  patterns: [snapshot-at-commitment-moment-tactic-b, per-callsite-violation-split, oz-carveout-fix-in-contracts]

key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-04-FIXREC-cluster.md
  modified: []

key-decisions:
  - "V-043: snapshot Reward pool at _swapAndFreeze; consumer JackpotModule._handleSoloBucketWinner:1493 reads snapshot"
  - "V-045: shares the V-043 snapshot field (sDGNRS-internal admin/initial-distribution writer class is structurally empty post-deploy; row preserved for catalog-discipline)"
  - "V-046: OZ-inherited ERC20 writer carve-out — fix lands inside contracts/ (snapshot consumer read), never inside node_modules/. Source-of-truth refinement: sDGNRS itself does not actually inherit OZ ERC20; row captures the OZ writer class generically per D-298-OZ-CARVEOUT-01"
  - "V-047: snapshot Lootbox pool at _finalizeLootboxRng (per-index, paired with lootboxRngWordByIndex[index])"
  - "V-048: shares the V-047 per-index snapshot mapping"
  - "V-050: snapshot Lootbox pool at burn submission inside _submitGamblingClaim, extends PendingRedemption struct alongside the existing activityScore snapshot, passed as new param to resolveRedemptionLootbox"
  - "V-051: per-callsite split — AdvanceStack=EXEMPT (no fix), MintPath=subsumed by catalog row 22 gate on MintModule.purchase/purchaseCoin/purchaseBurnieLootbox, AdminPath=forward-attestation only (no writer exists in current source)"

patterns-established:
  - "Tactic (b) snapshot-at-commitment moment for cross-contract pool-balance race classes"
  - "Snapshot fields can be unified across writer-classes when the consumer-read site is the same (V-043/V-045/V-046 share dgnrsRewardPoolSnapshot; V-047/V-048 share lootboxPoolSnapshotByIndex[index])"
  - "OZ-inherited writer carve-out resolved by snapshotting consumer read inside contracts/, leaving OZ source untouched"
  - "Per-callsite VIOLATION split derives sub-class tokens (EXEMPT vs subsumed-by-other-fix vs forward-attestation) from grep-verified writer enumeration"

requirements-completed: [FIXREC-01, FIXREC-02, FIXREC-03, FIXREC-04, FIXREC-05]

duration: ~20min
completed: 2026-05-18
---

# Phase 299 Plan 04: FIXREC Cluster D (sDGNRS poolBalances Reward + Lootbox) Summary

**Per-VIOLATION analytical FIXREC entries for the sDGNRS cross-contract pool-balance race class (S-14 + S-15) — 7 logical VIOLATIONs covered with tactic (b) snapshot-at-commitment-moment across three distinct commitment surfaces (_swapAndFreeze, _finalizeLootboxRng, _submitGamblingClaim) plus a per-callsite split for V-051.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-05-18 (Phase 299 wave-1 parallel dispatch)
- **Completed:** 2026-05-18
- **Tasks:** 1 (Task 1: Author Cluster-D FIXREC contribution)
- **Files modified:** 1 (the new Cluster-D FIXREC file)

## Accomplishments

- Authored `299-04-FIXREC-cluster.md` with 7 §N analytical entries (one per VIOLATION row in scope) and 28 sub-section anchors (§N.A design-intent backward-trace × 7, §N.B actor game-theory walk × 7, §N.C tactic + rationale + impact estimate × 7, §N.D v44.0 handoff anchor × 7).
- 7 v44.0 FIX-MILESTONE handoff anchors `D-43N-V44-HANDOFF-20`..`D-43N-V44-HANDOFF-26` populated with concrete file:line cites for SSTORE / SLOAD landing sites.
- Tactic distribution: all 7 VIOLATIONs use tactic (b) snapshot/anchor as their primary mechanism (with V-051 carrying a per-callsite mix that subsumes the MintPath sub-class under catalog row 22's tactic (a) gate).
- V-046 OZ-inherited writer carve-out attestation explicitly authored per the plan's V-046-specific requirement: fix lands IN `contracts/` (snapshots the consumer's read), never in `node_modules/`. Source-of-truth refinement included: sDGNRS itself does NOT actually inherit OZ ERC20 (custom in-contract ERC20 implementation); the row captures the OZ writer class generically per `D-298-OZ-CARVEOUT-01`.
- EV-tier distribution: HIGH/CATASTROPHE in 4 entries (V-043 final-day, V-047, V-048, V-050 mega-tier); LOW/catalog-discipline in 3 entries (V-045 inactive writer, V-046 consumer-disambiguated, V-051 per-callsite splits).

## Task Commits

1. **Task 1: Author Cluster-D FIXREC contribution (sDGNRS cross-contract pool balances)** — committed atomically in the per-task commit below (see Plan Metadata commit).

## Files Created/Modified

- `.planning/phases/299-fix-recommendation-document-fixrec/299-04-FIXREC-cluster.md` — Per-VIOLATION analytical entries for Cluster D (V-043, V-045, V-046, V-047, V-048, V-050, V-051) with full 4-sub-section depth per `D-299-FIXREC-LAYOUT-01` and 7 v44.0 handoff anchors.

## Decisions Made

- **Unified Reward-pool snapshot field across V-043/V-045/V-046:** A single `dgnrsRewardPoolSnapshot` field at `_swapAndFreeze` covers all three Reward-pool VIOLATIONs (non-advanceGame GAME writers, sDGNRS-internal admin/initial-distribution writers, OZ-inherited ERC20 writers). Storage delta is amortized; v44 plan-phase implements one snapshot for three rows.
- **Per-index Lootbox-pool snapshot mapping across V-047/V-048:** A single `lootboxPoolSnapshotByIndex[index]` mapping at `_finalizeLootboxRng:1253` covers both `openLootBox` and `openBurnieLootBox` manual-path entries. They share the same `index` keying and the same VRF-fulfillment write site.
- **V-050 in-struct snapshot extends `PendingRedemption`:** Adding `uint128 lootboxPoolSnapshot` to the struct mirrors the existing `activityScore` snapshot precedent (the in-source snapshot pattern already used by `claimRedemption` at `:628`). Interface signature of `IDegenerusGame.resolveRedemptionLootbox` gains a new parameter (locally contained since the sole caller is `StakedDegenerusStonk.claimRedemption`).
- **V-051 per-callsite split into three sub-classes:** AdvanceStack (EXEMPT, no fix), MintPath (subsumed by catalog row 22 tactic (a) gate on `MintModule.purchase`), AdminPath (forward-attestation only since no admin writer of `transferBetweenPools(*, Pool.Lootbox)` exists in the current source per `feedback_frozen_contracts_no_future_proofing.md`).
- **V-046 OZ-carveout source-of-truth refinement:** explicit attestation that sDGNRS does NOT inherit `@openzeppelin/contracts/token/ERC20/ERC20.sol` (custom in-contract ERC20 implementation; grep verified no `@openzeppelin` import). The V-046 row therefore captures the OZ-inherited writer CLASS generically across the contract suite per `D-298-OZ-CARVEOUT-01` carve-out rule. The lone-non-`contracts/`-VIOLATION framing from the planner is preserved by noting that the OZ writer source-of-record (`node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol`) lives outside `contracts/` and the fix must land inside `contracts/`.

## Deviations from Plan

None — plan executed exactly as written. Tactic selections match catalog `§16 row 378-386` recommended-tactic columns verbatim; per-callsite split for V-051 follows the catalog's explicit "(b) Per-callsite Phase 299 split: admin paths tactic (a); advance-stack EXEMPT" directive (row 386 §E E-2-equivalent). Source citations match the §15 writer enumeration and the §6/§7/§11 consumer-trace metadata.

The V-046 entry includes an additional source-of-truth refinement note (sDGNRS does not actually inherit OZ ERC20; custom in-contract implementation) that goes BEYOND the plan's literal instruction. This is consistent with `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE-gap precedent — verify call-graph claims against source pre-fix) and `feedback_no_history_in_comments.md` (the entry describes what IS in the deployed source, not what was historically assumed). This refinement strengthens the V-046 disposition rather than weakening it: the OZ-carveout fix-in-`contracts/` pattern still applies generically across the contract suite.

## Issues Encountered

None — all required source files (`contracts/StakedDegenerusStonk.sol`, `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`, `contracts/modules/DegenerusGameLootboxModule.sol`) were grep-verified for cited line numbers. The catalog §16 row 378 cite for V-043 (`DegenerusGame.sol:1735, :1739`) was verified to point to `resolveRedemptionLootbox` body lines (`claimableWinnings`/`claimablePool` writes, NOT direct `poolBalances[Reward]` writes); V-043's true writer is `transferFromPool(Pool.Reward, ...)` from the `payCoinflipBountyDgnrs` `msg.sender == COIN` arm at `DegenerusGame.sol:420` and similar non-advanceGame GAME-internal callsites — this is documented in §1.B with the V-042 EXEMPT-VRFCALLBACK boundary note.

## User Setup Required

None — analysis-only artifact; zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.

## Next Phase Readiness

- Cluster D FIXREC entries ready for Phase 299 main-context integration (Phase 299 §M consolidated handoff register) and for v44.0 FIX-MILESTONE plan-phase consumption.
- Cross-references to sibling Phase 299 cluster outputs: V-051-MintPath sub-class points to Cluster B (`prizePoolsPacked` row-22 handoff anchor). Cluster B output must exist for the V-051 cross-reference to resolve.
- All 7 handoff anchors `D-43N-V44-HANDOFF-20`..`D-43N-V44-HANDOFF-26` populated with concrete WRITE-site + READ-site cites for v44.0 plan-phase decomposition.

## Self-Check: PASSED

- `299-04-FIXREC-cluster.md` exists (write confirmed).
- All 7 V-NNN tokens present (grep-verified): V-043, V-045, V-046, V-047, V-048, V-050, V-051.
- All 7 handoff anchors present (grep-verified): `D-43N-V44-HANDOFF-20` through `D-43N-V44-HANDOFF-26`.
- 28 sub-section anchors present (grep-verified by `grep -E "^### §[1-7]\.[ABCD]"`): exactly 7 §N.A + 7 §N.B + 7 §N.C + 7 §N.D headers.
- Zero `SAFE_BY_DESIGN` tokens (grep-verified).
- Zero `contracts/` mutations (verified by `git status --porcelain contracts/`: empty).
- Zero `test/` mutations (verified by `git status --porcelain test/`: empty).

---
*Phase: 299-fix-recommendation-document-fixrec, Plan 04*
*Completed: 2026-05-18*
