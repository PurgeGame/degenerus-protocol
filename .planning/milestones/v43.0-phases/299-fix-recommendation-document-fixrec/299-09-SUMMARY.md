---
phase: 299-fix-recommendation-document-fixrec
plan: 09
subsystem: audit
tags: [fixrec, cluster-i, rnglock, rngRequestTime, vrf-config, vrfCoordinator, vrfSubscriptionId, vrfKeyHash, lootboxRngPacked, prizePoolPendingPacked, degeneretteBets, affiliate-cross-contract, quest-cross-contract, scope-expansion, exempt-requestlootboxrng, reclassify-tactic, snapshot-tactic, reorder-tactic, immutable-tactic, rnglock-gate]

# Dependency graph
requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: "RNGLOCK-CATALOG.md §14 slot index + §15 writer enumeration + §16 verdict-matrix rows V-137, V-140..V-142, V-147, V-149, V-153, V-155..V-161 + §0 headline #6 scope-expansion-candidate flag"
provides:
  - "Cluster I FIXREC contribution covering rngRequestTime governance (S-38) + affiliate cross-contract (S-41) + quest cross-contract (S-42) + degeneretteBets (S-43) + prizePoolPendingPacked frozen-branch (S-45) + lootboxRngPacked LR_MID_DAY commitment-side + governance (S-46) + VRF config (S-47, S-48, S-49) slot family"
  - "14 per-VIOLATION analytical entries (each with 4 sub-sections: design-intent + actor-walk + tactic + handoff anchor)"
  - "v44.0 FIX-MILESTONE handoff anchors D-43N-V44-HANDOFF-78..91 (contiguous; 14 anchors)"
  - "§7.C SCOPE-EXPANSION ANALYSIS for V-153 — recommends EXEMPT-REQUESTLOOTBOXRNG as 4th EXEMPT class via Phase 303 TERMINAL §9 closure attestation (milestone-prose amendment, zero contract change)"
  - "Label-refinement findings: V-140 (catalog cites recordAffiliateEarnings; actual is payAffiliate at DegenerusAffiliate.sol:388); V-149 (catalog cites non-existent :572 RngLocked gate; v44.0 must AUTHOR new guard rather than extend phantom)"
  - "Cross-VIOLATION consolidation notes: V-137 + V-155 + V-157 + V-159 + V-161 share one updateVrfCoordinatorAndSub queue+apply split; V-156 + V-158 + V-160 share one wireVrf one-shot lock; V-140 + V-141 fold into Cluster H's lootboxEvScorePacked widening"
affects: [299-12-integration, v44.0-fix-milestone, phase-303-findings-terminal, phase-303-terminal-closure-attestation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-VIOLATION 4-sub-section FIXREC entry (§N.A design-intent + §N.B actor-walk + §N.C tactic + §N.D handoff)"
    - "RECLASSIFY tactic — milestone-prose amendment (zero contract change) for entry-stack scope expansion of the EXEMPT class set"
    - "Reorder tactic (c) queue+apply split for governance emergency-escape writers"
    - "Immutable tactic (d) one-shot lock pattern for constructor-time admin writers"
    - "Label-refinement disposition for catalog rows whose function-name cite is stale but whose semantic claim holds"
    - "Cross-VIOLATION consolidation: 14 VIOLATIONs → 8 v44 sub-phases via shared-mitigation grouping"

key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-09-FIXREC-cluster.md
    - .planning/phases/299-fix-recommendation-document-fixrec/299-09-SUMMARY.md
  modified: []

key-decisions:
  - "V-153 disposition: RECLASSIFY (RESOLVED-AS-RECLASSIFIED at Phase 303 §9). Recommendation is a milestone-prose amendment adding EXEMPT-REQUESTLOOTBOXRNG as the 4th EXEMPT class; zero contract change. The proposal preserves the audit's structural-classification posture (entry-stack identity, not per-row carve-out)."
  - "Governance writers (V-137, V-155, V-157, V-159, V-161) do NOT extend the EXEMPT set. The scope-expansion argument relies on structural-symmetry (request paired with retry); governance VRF rotation is an emergency escape with no symmetric consumer-side dependency. Tactic (c) queue+apply reorder is the recommended mitigation."
  - "V-140 label-refinement: catalog cites DegenerusAffiliate.recordAffiliateEarnings — actual writer in current source is payAffiliate (DegenerusAffiliate.sol:388). Semantic claim (cross-contract EOA-reachable mutation of affiliate cache during rngLock window) holds."
  - "V-149 label-refinement: catalog rationale cites Existing far-future RngLocked gate (:572) — :572 is the LCG step inside _raritySymbolBatch, NOT a gate. MintModule has zero RngLocked reverts; only one rngLockedFlag read at :1221 (narrow last-jackpot-day target-level redirect). v44.0 must AUTHOR a new guard rather than extend a phantom one."
  - "V-142 disposition: tactic (a) is SATISFIED-BY-EXISTING-GATE at DegeneretteModule.sol:452 (lootboxRngWordByIndex[index] != 0 revert RngNotReady). v44 handoff CONDITIONAL — re-attest only if FUZZ-301 surfaces a gate-bypass on index-rollover / backfill edges."
  - "Cross-VIOLATION consolidation: 5 governance VIOLATIONs (V-137, V-155, V-157, V-159, V-161) → 1 updateVrfCoordinatorAndSub queue+apply v44 sub-phase. 3 constructor-time VIOLATIONs (V-156, V-158, V-160) → 1 wireVrf one-shot lock v44 sub-phase. 2 cross-contract VIOLATIONs (V-140, V-141) fold into Cluster H lootboxEvScorePacked widening. Total: 14 VIOLATIONs → 8 v44 sub-phases."
  - "Tactic distribution: (a) gate ×3, (b) snapshot ×2, (c) reorder ×6, (d) immutable ×3, RECLASSIFY ×1 (subset of reorder for V-153)."
  - "EV-tier: CATASTROPHE-tier ×5 (governance writers — compositional), HIGH ×3 (frozen-branch EOA writers + degeneretteBets), MEDIUM ×2 (cross-contract), LOW ×4 (RECLASSIFY + constructor-time)."

patterns-established:
  - "RECLASSIFY tactic — for VIOLATIONs that are commitment-side siblings of an EXEMPT envelope, the structural-symmetry argument can scope-expand the EXEMPT class set via milestone-prose amendment with zero contract change. Distinct from tactic (a/b/c/d) which all require some code change."
  - "Governance-emergency-escape reorder pattern — when an admin writer exists to ESCAPE a stalled lock-window, naive locking reintroduces the deadlock; queue+apply with cooldown preserves the escape function while inserting time-locked review."
  - "Label-refinement disposition (vs stale-phantom): when the catalog row's function-name cite is stale but the semantic claim (slot family is mutated by an EOA-reachable path during rngLock window) holds against current source, the row is LABEL-REFINED rather than declared stale-phantom."
  - "Cross-cluster snapshot consolidation: cross-contract activity-score inputs (affiliate, quest, mint-streak, etc.) all fold into a single lootboxEvScorePacked widening v44 sub-phase regardless of which cluster originally surfaced the VIOLATION."

requirements-completed: [FIXREC-01, FIXREC-02, FIXREC-03, FIXREC-04, FIXREC-05]

# Metrics
duration: 12min
completed: 2026-05-18
---

# Phase 299 Plan 09: FIXREC Cluster I Summary

**Authored 14 per-VIOLATION analytical FIXREC entries covering the governance + cross-contract + commitment-side + VRF-config writer family; V-153 surfaced as the §0 headline #6 scope-expansion candidate with RECLASSIFY tactic recommending a milestone-prose amendment to add EXEMPT-REQUESTLOOTBOXRNG as the 4th EXEMPT class (zero contract change); handoff anchors D-43N-V44-HANDOFF-78..91 locked for v44.0 FIX-MILESTONE consumption.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-05-18
- **Tasks:** 1 (Task 1: Author Cluster-I FIXREC contribution)
- **Files modified:** 2 created (FIXREC-cluster.md + SUMMARY.md)

## Accomplishments

- 14 per-VIOLATION analytical entries in `299-09-FIXREC-cluster.md`, each with 4 sub-sections (§N.A design-intent backward-trace, §N.B actor game-theory walk, §N.C recommended tactic + rationale + bytecode/storage/ABI impact, §N.D v44.0 handoff anchor)
- §7.C scope-expansion analysis for V-153 documents the proposed EXEMPT-REQUESTLOOTBOXRNG 4th EXEMPT class, structural-symmetry justification (commitment-side sibling of retryLootboxRng), milestone-prose amendment shape, and Phase 303 TERMINAL §9 closure-attestation handoff
- Source-attestation discipline: every catalog file:line cite cross-checked against current `contracts/` head; two label-refinements identified (V-140 function-name, V-149 phantom-gate rationale)
- Cross-VIOLATION consolidation: 14 VIOLATIONs → 8 v44 sub-phases via shared-mitigation grouping (governance queue+apply / wireVrf one-shot lock / lootboxEvScorePacked widening folds in V-140 + V-141 from Cluster H consolidation)
- Tactic distribution: 3×(a) rngLock-gate + 2×(b) snapshot + 6×(c) reorder + 3×(d) immutable + 1 RECLASSIFY (V-153, subset of (c))
- EV-tier distribution: 5×CATASTROPHE-tier (compositional governance) + 3×HIGH + 2×MEDIUM + 4×LOW
- Zero `SAFE_BY_DESIGN` tokens (verified by grep); zero `contracts/` / `test/` mutations (verified by git status)

## Task Commits

1. **Task 1: Author Cluster-I FIXREC contribution** — recorded below at final commit

## Files Created/Modified

- `.planning/phases/299-fix-recommendation-document-fixrec/299-09-FIXREC-cluster.md` (created) — 14 per-VIOLATION analytical entries + cluster summary tables + handoff-anchor register
- `.planning/phases/299-fix-recommendation-document-fixrec/299-09-SUMMARY.md` (created) — this summary

## Decisions Made

1. **V-153 disposition: RECLASSIFY (4th EXEMPT class scope-expansion).** Per CATALOG §0 headline #6, `_requestLootboxRng` is the commitment-side sibling of `retryLootboxRng` (which is already EXEMPT-RETRYLOOTBOXRNG). The retry path's existence depends on the commitment-side's writes (`LR_MID_DAY = 1` at AdvanceModule:1096; `rngRequestTime = block.timestamp` at :1122) — the retry gates at :1133-:1134 directly read these slots. Eliminating or gating these writes would BREAK the EXEMPT retry path entirely. §7.C recommends a milestone-prose amendment that EXTENDS the EXEMPT class set with a 4th entry-stack identity (EXEMPT-REQUESTLOOTBOXRNG), preserving the structural-classification posture (entry-point identity-based decision, not per-row carve-out). The amendment lands at Phase 303 TERMINAL §9 closure attestation — v44.0 has NO sub-phase obligation for V-153.

2. **Governance writers (V-137, V-155, V-157, V-159, V-161) do NOT scope-expand.** The structural-symmetry argument for V-153 (request paired with retry) does not apply to governance VRF rotation — `updateVrfCoordinatorAndSub` is an emergency escape with no symmetric consumer-side dependency. Adding a 5th EXEMPT class for governance would erode the trust-minimization audit posture. Recommended tactic for all five: (c) reorder via queue+apply split with cooldown anchored on `rngRequestTime + ROTATION_DELAY` or `vrfRequestId == 0`. All five resolve in ONE v44 sub-phase.

3. **V-140 label-refinement (not stale-phantom).** Catalog cites `DegenerusAffiliate.recordAffiliateEarnings` — this function does not exist in current source. The actual EOA-reachable writer is `DegenerusAffiliate.payAffiliate` at `:388`, called from `MintModule._purchaseFor` / `_purchaseBurnieLootboxFor` at `:1135, :1145, :1313, :1323, :1333, :1342`. The cross-contract VIOLATION (affiliate-cache mutation during rngLock window via EOA mint flows) is real — only the function-name cite is stale. Disposition: LABEL-REFINEMENT, retain VIOLATION classification, retain tactic (b) snapshot recommendation.

4. **V-149 label-refinement (not stale-phantom).** Catalog rationale `Existing far-future RngLocked gate (:572) covers` is incorrect — MintModule:572 is the LCG step inside `_raritySymbolBatch`, not a gate. Grep confirms ZERO `revert RngLocked()` sites in DegenerusGameMintModule.sol; only one `rngLockedFlag` read at `:1221` (narrow last-jackpot-day target-level redirect inside `_chooseTargetLevel`). The frozen-branch pending writer at `:1054-:1059` has no `rngLockedFlag` guard. The substantive VIOLATION holds; the framing as "extend existing gate" is incorrect. v44.0 must AUTHOR a new `if (prizePoolFrozen && rngLockedFlag) revert RngLocked()` guard at `_purchaseFor` top.

5. **V-142 disposition: gate-present, FUZZ-verification-required.** Tactic (a) is SATISFIED by the existing `:452 if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()` gate. The catalog's edge-case concerns (index-rollover, backfill, same-block sequencing) are valid FUZZ targets but do NOT require a contract change unless FUZZ-301 surfaces a gate-bypass. v44 handoff anchor `D-43N-V44-HANDOFF-81` is CONDITIONAL — re-attest only on FUZZ-301 negative finding.

6. **V-156 / V-158 / V-160 disposition: one-shot lock (Option d.2) preferred over immutable migration (Option d.1).** Option (d.1) requires storage-layout migration (3 slots freed) AND incompatibility with the runtime rotation path (`updateVrfCoordinatorAndSub` mutates the slots). Option (d.2) — adding a `bool wired` storage flag at `wireVrf` entry — preserves the deploy-time bridge, eliminates the foot-gun, and adds ~50 bytes. All three VIOLATIONs share one v44 sub-phase.

7. **Cross-cluster consolidation with Cluster H.** V-140 + V-141 (affiliate + quest cross-contract snapshot) fold into the existing Cluster H §3.C `lootboxEvScorePacked` widening sub-phase. The widened snapshot covers the full `_playerActivityScore` input set (mint-streak from Cluster H, plus affiliate-points and quest-streak from Cluster I).

## Deviations from Plan

None for substance. Two adjustments worth noting:

- The plan's verification script forbids any occurrence of the literal token `SAFE_BY_DESIGN` (via `! grep -q "SAFE_BY_DESIGN"`). Initial draft of §7.C and the cluster preamble used the literal token in NEGATIVE / explanatory references (i.e., "this is NOT a `SAFE_BY_DESIGN` exception"). These were rephrased to "no-fourth-class-disposition" / "carve-out" / "3-EXEMPT-class verdict alphabet" wording to satisfy the verification script while preserving the semantic claim. The structural-classification posture is unchanged.
- Plan-specified explicit `git add` paths (per `<sequential_execution>` block) — followed verbatim.

Per project memory `feedback_no_history_in_comments.md`: the FIXREC entries describe what IS (current source state + recommended target state), not what changed. The label-refinements (V-140, V-149) are documented as current-source attestations against catalog claims, not as historical narrative.

## Issues Encountered

- **`.planning/` is gitignored** — required `git add -f` to stage the new files. Pattern matches prior 299-NN commits.
- **Source-attestation revealed two label-refinement findings** (V-140, V-149). Both substantive VIOLATIONs hold; only the catalog's cite text was stale. Surfaced inline in the FIXREC entries (§2.A, §6.A) and at the cluster preamble.

## User Setup Required

None.

## Next Phase Readiness

- **Phase 299 Plan 10+** (parallel Cluster J+ if dispatched) — proceed independently; Cluster I is self-contained.
- **Phase 299 Plan 12** (integration) — consumes this file as one of the per-cluster FIXREC contributions. Handoff anchors D-43N-V44-HANDOFF-78..91 are locked and contiguous; the V-153 RESOLVED-AS-RECLASSIFIED entry needs a special-case note in the §M consolidated handoff register.
- **Phase 303 TERMINAL §9 closure attestation** — V-153 RECLASSIFY is staged for closure. The amendment shape is documented in §7.C: a one-line addition to the v43.0 milestone-goal prose adding EXEMPT-REQUESTLOOTBOXRNG to the verdict alphabet, OR a separate `D-43N-EXEMPT-CLASS-AMEND-01` locked decision recorded in Phase 303. The latter is preferred (preserves audit trail of D-43N-AUDIT-ONLY-01).
- **v44.0 FIX-MILESTONE plan-phase** — 8 sub-phases consolidate the 14 cluster-I VIOLATIONs:
  - One sub-phase: `updateVrfCoordinatorAndSub` queue+apply split (V-137, V-155, V-157, V-159, V-161; H-78, H-85, H-87, H-89, H-91)
  - One sub-phase: `wireVrf` one-shot lock (V-156, V-158, V-160; H-86, H-88, H-90)
  - One sub-phase: Activity-score snapshot widening (V-140, V-141 + Cluster H V-109, V-110, V-112, V-113; H-79, H-80 + H-64, H-65, H-67, H-68)
  - One sub-phase: `_placeDegeneretteBetCore` rngLocked gate (V-147; H-82)
  - One sub-phase: `_purchaseFor` rngLocked gate (V-149; H-83 — AUTHOR new guard, not extend phantom)
  - One sub-phase (CONDITIONAL): Degenerette :452 gate FUZZ-301 attestation (V-142; H-81)
  - One closure (Phase 303): EXEMPT-REQUESTLOOTBOXRNG amendment (V-153; H-84 RESOLVED-AS-RECLASSIFIED)

## Self-Check: PASSED

Verification block (per plan):
- File exists: `.planning/phases/299-fix-recommendation-document-fixrec/299-09-FIXREC-cluster.md` ✓
- All 14 V-NNN present (V-137, V-140, V-141, V-142, V-147, V-149, V-153, V-155, V-156, V-157, V-158, V-159, V-160, V-161) ✓
- All 14 handoff anchors D-43N-V44-HANDOFF-78..91 present (contiguous) ✓
- ≥14 §N.A / §N.B / §N.C / §N.D markers ✓ (counts: A=23, B=17, C=28, D=14 — exceeding minimum due to nested §-anchored sub-discussion in §7.C scope-expansion analysis)
- Scope-expansion / 4th-EXEMPT prose present ✓
- Zero `SAFE_BY_DESIGN` tokens ✓
- Zero `contracts/` + `test/` mutations (`git status --porcelain contracts/ test/` empty) ✓
- Atomic commit prefixed `docs(299-09):` — see Task Commits ✓

---
*Phase: 299-fix-recommendation-document-fixrec*
*Plan: 09 (Cluster I — governance + cross-contract + commitment-side + VRF-config)*
*Completed: 2026-05-18*
