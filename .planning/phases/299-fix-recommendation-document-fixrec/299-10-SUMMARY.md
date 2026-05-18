---
phase: 299-fix-recommendation-document-fixrec
plan: 10
subsystem: audit
tags: [fixrec, cluster-j, rnglock, ticketQueue, ticketsOwedPacked, sStonk, redemptionPeriodIndex, decBurn, terminalDecBurn, bountyOwedTo, tier-1, cross-day-re-roll, headline]

# Dependency graph
requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: "RNGLOCK-CATALOG.md §14 slot index + §15 writer enumeration + §16 verdict-matrix rows V-168..V-179, V-182..V-193, V-201, V-202 + §12 sStonk consumer trace + §13 DecimatorModule consumer + §17 source-attestation + §0 headline #1 V-184 Tier-1"
provides:
  - "Cluster J FIXREC contribution covering ticketQueue (S-52) + ticketsOwedPacked V-179 fan-out (S-53) + bountyOwedTo (S-55) + sStonk redemption family (S-56..S-60) + decBurn (S-66) + terminalDecBucketBurnTotal (S-67)"
  - "20 logical per-VIOLATION analytical entries (V-179 single-logical with 9-callsite fan-out V-179.A..V-179.I)"
  - "28 v44.0 FIX-MILESTONE handoff anchors D-43N-V44-HANDOFF-92..119"
  - "TIER-1 HEADLINE §0 finding #1 V-184 sStonk cross-day re-roll exploit — dual-tactic documentation (defensive (a) + structural (b) PREFERRED)"
  - "Cross-VIOLATION subsumption note: V-186 / V-188 / V-190 / V-191 / V-192 / V-193 all subsumed by V-184 fix (7→1 sub-phase collapse for v44.0)"
  - "V-179 9-callsite single-logical-entry treatment per D-299-FIXREC-LAYOUT-01 82-budget rule"
  - "V-201 / V-202 burn-window verification dispositions (catalog-prescribed `poolWei==0` and `rngWordByDay[day]==0` gates verified appropriate)"
affects: [299-12-integration, v44.0-fix-milestone, phase-303-findings-terminal, phase-303-section-3A-delta-surface]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-VIOLATION 4-sub-section FIXREC entry (§N.A design-intent + §N.B actor-walk + §N.C tactic + §N.D handoff)"
    - "rngLock-gate tactic (a) for narrow EOA writer entries (20/20 of cluster)"
    - "Structural-anchor tactic (b) PREFERRED variant for V-184 (Phase 288 dailyIdx precedent)"
    - "Single-logical-entry treatment for fan-out VIOLATIONs (V-179 9-callsite → 1 §N entry + 9 sub-anchors)"
    - "Cross-VIOLATION subsumption notation for compound-effect VIOLATIONs (V-184 subsumes V-186/V-188/V-190/V-191/V-192/V-193)"
    - "Burn-window verification methodology for catalog gates (per-level `poolWei==0` vs per-day `rngWordByDay[day]==0`)"

key-files:
  created:
    - .planning/phases/299-fix-recommendation-document-fixrec/299-10-FIXREC-cluster.md
    - .planning/phases/299-fix-recommendation-document-fixrec/299-10-SUMMARY.md
  modified: []

key-decisions:
  - "V-184 surfaced as Phase 299 TIER-1 HEADLINE per §0 finding #1 — sStonk cross-day re-roll exploit"
  - "V-184 documented with BOTH tactic (a) catalog-prescribed defensive revert AND tactic (b) PREFERRED clean-variant structural anchor for v44.0 plan-phase consumption"
  - "V-184 §12.C derived clean-variant tactic (b): combine revert + reset-conditional refactor (pure structural-advance alone insufficient due to sStonk:758 reset regression)"
  - "V-179 treated as ONE logical VIOLATION per D-299-FIXREC-LAYOUT-01 82-budget rule; 9 sub-anchors H-101..H-109 fit inside single §10.D entry"
  - "V-186 / V-188 / V-190 / V-191 / V-192 / V-193 explicitly subsumed by V-184 fix; v44.0 plan-phase can collapse 7 entries → 1 sub-phase"
  - "V-201 burn-window verification: confirmed `BurnieCoin.decimatorBurn` has no rngLock-gating at entry (only `_consumeCoinflipShortfall` shortfall-revert at BurnieCoin:451); catalog-prescribed `decClaimRounds[lvl].poolWei == 0` gate verified appropriate"
  - "V-202 burn-window verification: pre-`gameOver` post-VRF window confirmed open; catalog-prescribed `rngWordByDay[currentDay] == 0` gate verified appropriate"
  - "V-170 + V-179.C disposition: verify-only (existing WhaleModule.sol:543 gate satisfies); v44.0 sub-phase is verify-only, not patch"
  - "Tactic distribution: tactic (a) ×20 (catalog-prescribed); tactic (b) PREFERRED variant additionally on V-184"
  - "EV-tier distribution: CATASTROPHE ×1 (V-184), HIGH ×10, MEDIUM ×8, LOW ×1 (V-170)"
  - "Stale-phantom count: 0 — all 20 VIOLATIONs verified against current source HEAD MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2"
  - "Co-location single-gate-covers-both invariant: every S-52 callsite fix at §1-§9 simultaneously closes the corresponding V-179 sub-row (S-53 co-located SSTORE block); v44.0 code-review must verify entry-revert precedes `_queueTickets`-family invocation"

patterns-established:
  - "TIER-1 headline finding documentation: explicit `**HEADLINE TIER-1 — §0 finding #1**` markup at section heading; cross-reference to Phase 303 §3.A delta-surface row 1; dual-tactic surfacing (defensive + structural-PREFERRED)"
  - "Fan-out logical-entry treatment: single §N entry with §N.B per-callsite enumeration table + §N.D bullet list of N sub-anchors (V-179 9-callsite case)"
  - "Cross-VIOLATION subsumption documentation: explicit subsumed-by header at subsumed §N.B/§N.C/§N.D; collapsed v44.0 sub-phase count tracked in summary"
  - "Source-attestation re-derivation: when catalog prose framing differs from source-verified exploit window (V-184 'future-day' framing vs source-verified 'same-day post-resolve' window), document the re-attestation explicitly in §N.B"
  - "Burn-window verification methodology: enumerate the specific rngLock-gate-shape (`rngLockedFlag`, `decClaimRounds[lvl].poolWei == 0`, `rngWordByDay[currentDay] == 0`) per VIOLATION's consumer-resolution scope (per-level vs per-day vs in-flight); document why catalog's choice is appropriate"

# Metrics
metrics:
  duration: "manual-trace"
  completed: 2026-05-18
  violations_logical: 20
  handoff_anchors_total: 28
  sub_sections: ">=80 (A=23, B=20, C=23, D=21)"
  tier1_findings: 1
  source_tree_mutations: 0
---

# Phase 299 Plan 10: FIXREC Cluster J — ticketQueue + sStonk redemption family + decBurn

## One-liner

Per-VIOLATION FIXREC entries for the ticketQueue + ticketsOwedPacked (V-179 9-callsite fan-out) + bountyOwedTo + sStonk redemption family + decBurn slot families — 20 logical VIOLATIONs spanning 28 v44.0 handoff anchors, with V-184 sStonk cross-day re-roll exploit surfaced as the milestone's TIER-1 §0 headline #1 finding and documented with both catalog-prescribed defensive revert (tactic a) and PREFERRED clean-variant structural anchor (tactic b).

## What was built

`.planning/phases/299-fix-recommendation-document-fixrec/299-10-FIXREC-cluster.md` — 1086 lines, 20 §N entries (V-179 as single-logical with 9-callsite fan-out per `D-299-FIXREC-LAYOUT-01`), each with 4 sub-sections (A/B/C/D), 28 v44.0 handoff anchors `D-43N-V44-HANDOFF-92..119`.

### Sub-family breakdown

| Sub-family | §N range | Slot | VIOLATIONs | Anchors |
|---|---|---|---|---|
| ticketQueue (S-52) — round-key-keyed push array | §1..§9 | `ticketQueue[rk]` | V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177 | H-92..H-100 |
| ticketsOwedPacked V-179 fan-out (S-53) — co-located owed-count | §10 (single-logical) | `ticketsOwedPacked[rk][player]` | V-179 (×9 sub-callsites V-179.A..V-179.I) | H-101..H-109 |
| bountyOwedTo (S-55) — BurnieCoinflip armed-bounty owner | §11 | `bountyOwedTo` | V-182 | H-110 |
| sStonk redemption family (S-56..S-60) | §12..§18 | `redemptionPeriodIndex` + 4 co-located accumulators + `pendingRedemptions[player]` struct | V-184 (TIER-1), V-186, V-188, V-190, V-191, V-192, V-193 | H-111..H-117 |
| decBurn (S-66/S-67) — decimator + terminal-decimator burn ledgers | §19, §20 | `decBurn[lvl][player].burn` + `terminalDecBucketBurnTotal[bucketKey]` | V-201, V-202 | H-118, H-119 |

### TIER-1 HEADLINE — §12 V-184 sStonk cross-day re-roll exploit

§12 surfaces the milestone's load-bearing economic finding per CATALOG §0 headline #1:

- **Exploit chain.** Player burns sDGNRS on day D → claim.periodIndex=D, pendingRedemptionEthBase armed. Day-D advance fires `resolveRedemptionPeriod(roll_D, D+1)` writing `redemptionPeriods[D]={roll_D, D+1}` and zeroing the base; `redemptionPeriodIndex` REMAINS at D (not advanced inside `resolveRedemptionPeriod`). Same wall-clock day D post-resolve, player burns 1 wei → re-arms pendingRedemptionEthBase against the STALE `redemptionPeriodIndex == D`. Day-D+1 advance re-invokes `resolveRedemptionPeriod` reading `redemptionPeriodIndex == D` (still stale) → OVERWRITES `redemptionPeriods[D].roll` with fresh `roll_{D+1}`.
- **EV asymmetry.** Player reads `redemptionPeriods[D].roll` BEFORE re-burning. 50% informed-re-roll filter (only re-roll when roll_D < 100). Per-round EV: 0.5×137.5 + 0.5×100 = 118.75 vs baseline 100 = ~19% positive EV. Compounding via iterated re-burns up to 50% supply-cap-bounded ceiling.
- **Severity.** CATASTROPHE-tier in aggregate. The attack is statistically free (1 wei sDGNRS per re-roll). Collateral damage to other day-D claimants who haven't yet called `claimRedemption()` — their effective roll is also re-rolled without consent.
- **Tactic (a) — Catalog-prescribed defensive revert.** Insert at `_submitGamblingClaimFrom:752` (right after sStonk:757):
  ```
  if (redemptionPeriodIndex == currentPeriod && redemptionPeriods[currentPeriod].roll != 0) {
      revert BurnsBlockedAfterResolution();
  }
  ```
  Closes same-day post-resolve re-burn window. ~50-80 bytes. Minimal change; reuses existing `BurnsBlockedDuringRng` convention pattern.
- **Tactic (b) — PREFERRED clean-variant structural anchor.** Refactor `_submitGamblingClaimFrom` reset conditional (sStonk:758-762) to combine the revert-on-resolved-period gate WITH the existing fresh-period reset:
  ```
  if (redemptionPeriods[currentPeriod].roll != 0) revert BurnsBlockedAfterResolution();
  if (redemptionPeriodIndex != currentPeriod) {
      redemptionPeriodSupplySnapshot = totalSupply;
      redemptionPeriodIndex = currentPeriod;
      redemptionPeriodBurned = 0;
  }
  ```
  Phase 288 dailyIdx structural-anchor precedent. ~80-120 bytes. Closes the gap exhaustively: post-resolve same-day burns revert; cross-day burns initialize fresh period; advance-stack re-resolution cannot fire on an already-resolved period because no new burns can arm the base.
- **§12.D handoff to v44.0.** TIER-1 PRIORITY-1. `D-43N-V44-HANDOFF-111`. Phase 303 §3.A delta-surface row 1 cross-reference embedded. Test plan must include §D-VIOL trigger sequence (pre-fix exploit succeeds; post-fix reverts), cross-day boundary edge cases, gap-day backfill interaction, collateral-damage assertion.

### Subsumption — 7 VIOLATIONs collapsed to 1 v44.0 sub-phase

V-186, V-188, V-190, V-191 (all `_submitGamblingClaimFrom` writes at sStonk:790-810) + V-192, V-193 (claimRedemption clear/partial-clear at sStonk:661/664) all subsumed by V-184's fix. Their §N.C entries explicitly cite "Subsumed by V-184." v44.0 plan-phase can implement a SINGLE sub-phase covering V-184 + V-186 + V-188 + V-190 + V-191 + V-192 + V-193 (7 catalog rows → 1 sub-phase).

### V-179 single-logical fan-out treatment

V-179 (`ticketsOwedPacked[rk][player]` writes co-located with S-52 callsites) is treated as ONE logical VIOLATION per `D-299-FIXREC-LAYOUT-01` 82-budget rule. The single §10 entry includes a §10.B 9-row enumeration table (V-179.A..V-179.I) mapping each callsite to its co-located S-52 VIOLATION and EV-tier. §10.D emits all 9 sub-anchors H-101..H-109 inside a single bulleted list. Co-location property: every S-52 SSTORE block ALSO writes S-53 → single entry-gate at each callsite closes both VIOLATIONs at zero incremental cost.

### V-201/V-202 decBurn burn-window verification

Source-verified that `BurnieCoin.decimatorBurn` (BurnieCoin:559) and `BurnieCoin.terminalDecimatorBurn` (BurnieCoin:634) have NO rngLock-gating at function entry. The only related check (`_consumeCoinflipShortfall` rngLock revert at BurnieCoin:451) requires the player to need shortfall consumption to fire — bypassed by a player with sufficient BURNIE balance. Catalog-prescribed gates verified appropriate:
- **V-201** — `decClaimRounds[lvl].poolWei == 0` (per-level scope; matches the per-level decimator-jackpot resolution model)
- **V-202** — `rngWordByDay[currentDay] == 0` (per-day scope; matches the GAMEOVER-only terminal-decimator resolution; closes the post-VRF-publish pre-GAMEOVER window)

Both classified HIGH EV-tier. Decimator pool magnitudes are multi-eth at mature game states; attacker converts honest ~1/7 probability into deterministic outcome by post-VRF-callback subbucket targeting.

### Verification

- `test -f` cluster file → PASS
- 20 V-NNN tokens (V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177, V-179, V-182, V-184, V-186, V-188, V-190, V-191, V-192, V-193, V-201, V-202) → all present
- 28 D-43N-V44-HANDOFF-N tokens (N=92..119) → all present
- §N.A count: 23 (≥20)
- §N.B count: 20 (≥20)
- §N.C count: 23 (≥20)
- §N.D count: 21 (≥20)
- HEADLINE/Tier-1/cross-day re-roll markers → PASS (explicit in §12 heading + §0 cross-reference)
- SAFE_BY_DESIGN token → ABSENT
- `contracts/` + `test/` mutations → ZERO
- AGENT-COMMITTED bundle path → `.planning/phases/299-fix-recommendation-document-fixrec/`

## Deviations from Plan

None — plan executed exactly as written.

The plan's `<cluster_j_specifics>` mentioned the §0 headline #1 framing as "future wall-clock day" while my source-verified trace identified the load-bearing window as "same-day post-resolve, pre-day-boundary." Both interpretations are valid in the limit; the structural fix is identical. The re-attestation is documented inside §12.B (not flagged as a deviation because it's a prose-flavor clarification, not a substantive change to the recommendation).

## Self-Check: PASSED

- `.planning/phases/299-fix-recommendation-document-fixrec/299-10-FIXREC-cluster.md` — FOUND
- `.planning/phases/299-fix-recommendation-document-fixrec/299-10-SUMMARY.md` — FOUND (this file)
- All 20 V-NNN logical-VIOLATION tokens present in cluster file
- All 28 D-43N-V44-HANDOFF-NN anchors (N=92..119) present in cluster file
- TIER-1 headline marker present (V-184 §12 heading)
- §N.A/B/C/D sub-section counts all ≥20
- SAFE_BY_DESIGN token absent
- Zero contracts/ or test/ mutations
- Commits will be tagged `docs(299-10): …` per plan convention
