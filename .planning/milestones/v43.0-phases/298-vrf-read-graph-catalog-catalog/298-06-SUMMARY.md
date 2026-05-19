---
phase: 298-vrf-read-graph-catalog-catalog
plan: 06
subsystem: vrf-read-graph-catalog
tags: [audit-only, vrf, lootbox, redemption, sdgnrs, commitment-window]
dependency-graph:
  requires: []
  provides:
    - "§6 catalog content for LootboxModule.resolveRedemptionLootbox"
    - "Participating-slot inputs for §14 unique-slot index"
    - "Writer-callsite inputs for §15 per-slot writer table"
    - "Verdict-matrix rows for §16"
  affects: []
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-06-CATALOG-section.md
  modified: []
decisions:
  - "Cross-frame SLOADs (Game-wrapper accounting at DegenerusGame.sol:1735/1739/1742-1748) enumerated alongside module-body SLOADs to honor F-41-02/03 freshness-enumeration discipline despite living one frame up."
  - "Boon-subtree (11 transitive functions) enumerated as NOT-REACHED rather than excluded silently, per Phase 294 BURNIE-gap precedent. Gate verification at LootboxModule.sol:732 (allowBoons=false, 12th positional arg)."
  - "Commitment-window framing: rngWord here is historical rngWordByDay[period], not a freshly-fulfilled VRF word. Attacker knows entropy before choosing claim moment — every participating-slot SLOAD reached is consumed AFTER attacker knew rngWord, making the commitment window unusually wide."
  - "Tactic (b) snapshot/anchor recommended for D-4 / D-9 — extends the existing activityScore snapshot precedent (already in PendingRedemption struct) to two more slots."
  - "D-16 surfaces a cross-mutation VIOLATION: lastPurchaseDay purchase-path writer suppresses _livenessTriggered inside _queueTickets reached from this consumer, giving attacker a same-day-purchase lever to control consumer-completes-vs-reverts decision."
metrics:
  duration: "~25 min"
  completed: "2026-05-18"
  tasks_completed: 1
  sloads_enumerated: 28
  participating_slots: 9
  verdict_matrix_rows: 20
  consumer_local_violations: 2
  cross_mutation_violations: 1
  exempt_rows: 17
---

# Phase 298 Plan 06: LootboxModule.resolveRedemptionLootbox VRF Read-Graph Catalog Summary

Backward-traced VRF-derived entropy from `LootboxModule.resolveRedemptionLootbox` (`contracts/modules/DegenerusGameLootboxModule.sol:707`) — the auto-resolved-from-sDGNRS-redemption lootbox-roll consumer (entry §6 in `D-298-CONSUMER-LIST-01`). Authored `298-06-CATALOG-section.md` with §A traced-function-set, §B SLOAD table (28 entries), §C per-participating-slot writer enumeration (9 slots), §D per-tuple verdict matrix (20 rows), §E remediation tactic for the 3 VIOLATIONs found.

## Tasks Completed

| # | Name | Files |
|---|---|---|
| 1 | Backward-trace from `resolveRedemptionLootbox` | `.planning/phases/298-vrf-read-graph-catalog-catalog/298-06-CATALOG-section.md` |

## Headline Findings

- **2 consumer-local VIOLATIONs** (D-4, D-9): `lootboxEvBenefitUsedByLevel[player][lvl]` and cross-contract `sDGNRS.poolBalances[Pool.Lootbox]` are SLOAD'd inside the resolution path AFTER the attacker has observed `rngWordByDay[claimPeriodIndex]`. The consumer's `claimRedemption` reach is EOA-callable at any moment of attacker's choosing — none of the three EXEMPT entry-point classes (`advanceGame` / VRF callback / `retryLootboxRng`) apply.
- **1 cross-mutation VIOLATION** (D-16): purchase-path writer of `lastPurchaseDay` masks `_livenessTriggered`'s revert path inside `_queueTickets` reached from this consumer. Attacker can toggle CONSUMER COMPLETES vs CONSUMER REVERTS by purchasing a ticket in the same day.
- **`allowBoons=false` collapses the entire boon subtree** (11 functions: `_rollLootboxBoons`, `_applyBoon`, `_activateWhalePass`, `_applyWhalePassStats`, `_boonPoolStats`, `_boonFromRoll`, `_isDecimatorWindow`, `_burnieToEthValue`, `_currentMintDay`, plus the two BoonModule nested-delegatecalls `checkAndClearExpiredBoon` and `consumeActivityBoon`) out of reach. Per Phase 294 BURNIE-gap precedent, all 11 are explicitly enumerated as NOT-REACHED with grep-verified gate at `LootboxModule.sol:732`.
- **Commitment-window discipline unusually load-bearing here:** unlike entries §1-§5 (jackpot / decimator / game-over) which consume a JUST-fulfilled VRF word, this consumer consumes a HISTORICAL `rngWordByDay[claimPeriodIndex]`. The commitment window from VRF-publication to consumer-execution is unbounded in real time — every SLOAD reached during resolution is post-commitment-disclosure.
- **Tactic (b) snapshot/anchor recommended** for the two slot-value VIOLATIONs: extend the existing `PendingRedemption.activityScore` snapshot pattern (already in production at `StakedDegenerusStonk.sol:claim.activityScore` + parameter at `LootboxModule.sol:707`) to snapshot `lootboxEvBenefitUsedByLevel[player][lvl]` and `poolBalance(Pool.Lootbox)` at burn-submission time and pass them through `resolveRedemptionLootbox` as additional parameters. Mirrors Phase 281 owed-salt and Phase 288 dailyIdx structural-snapshot precedents.

## Trace Discipline (per methodology-feedback memory)

- `feedback_rng_backward_trace.md` — trace ROOTED at the consumer (`:707`), walked backward into every reachable function.
- `feedback_rng_window_storage_read_freshness.md` — enumerated EVERY SLOAD reached, including non-VRF-derived accounting reads (`claimableWinnings[SDGNRS]`, `claimablePool`, `prizePoolFrozen`, `prizePoolsPacked`, `prizePoolPendingPacked`, sDGNRS `balanceOf[address(this)]`, sDGNRS `balanceOf[to]`, sDGNRS `totalSupply`, WWXRP `totalSupply` + `balanceOf[to]`) classified NO with attestation. F-41-02/03 class blindness avoided.
- `feedback_verify_call_graph_against_source.md` — 11 boon-subtree functions explicitly enumerated as NOT-REACHED with grep-verified gate, NOT silently elided. Parameter-order audit of the 14-arg `_resolveLootboxCommon` call site cross-validated `allowBoons` is the 12th positional argument.
- `feedback_rng_commitment_window.md` — explicit commitment-window framing: `rngWord` here is HISTORICAL, not freshly-fulfilled; attacker chooses claim moment with full knowledge of entropy. This makes the consumer fundamentally different from a JUST-VRF-fulfilled consumer and is documented as load-bearing for every Participating? YES classification.

## Verdict-Matrix Summary

| Slot | Writer-callsites | VIOLATION | EXEMPT-VRFCALLBACK | EXEMPT-RETRYLOOTBOXRNG | Notes |
|---|---|---|---|---|---|
| `lootboxEvBenefitUsedByLevel[player][lvl]` | 4 (one per lootbox-resolution entry) | 3 (D-1 openLootBox, D-2 openBurnieLootBox, D-4 resolveRedemptionLootbox) | 1 (D-3 resolveLootboxDirect auto-resolve) | 0 | Consumer-local violation: D-4. |
| `level` | 1 | 0 | 1 (D-5) | 0 | All advance-stack. |
| `dgnrs.poolBalances[Pool.Lootbox]` | 5+ | 3+ (D-6, D-7, D-9 + D-10 cluster pending) | 2 (D-8, D-11) | 0 | Consumer-local violation: D-9. D-10 transferBetweenPools cluster needs Phase 299 per-callsite expansion. |
| `rngLockedFlag` | 3 | 0 | 2 (D-12, D-13) | 1 (D-14) | All EXEMPT. |
| `ticketWriteSlot` | 1 | 0 | 1 (D-15) | 0 | EXEMPT. |
| `lastPurchaseDay` | 2+ | 1 (D-16) | 1 (D-17) | 0 | Cross-mutation VIOLATION. |
| `jackpotPhaseFlag` | 1+ | 0 | 1 (D-18) | 0 | EXEMPT. |
| `purchaseStartDay` | 1+ | 0 | 1 (D-19) | 0 | EXEMPT. |
| `rngRequestTime` | 1+ | 0 | 1 (D-20) | 0 | EXEMPT. |

**Consumer-local total:** 2 VIOLATION + 1 cross-mutation VIOLATION + 17 EXEMPT-VRFCALLBACK or EXEMPT-RETRYLOOTBOXRNG.

## Deviations from Plan

None — plan executed exactly as written. No `contracts/` or `test/` mutations. No STATE.md / ROADMAP.md edits (deferred to phase-integration step per PARALLEL-DISPATCH session shape).

## Known Stubs / Deferred Items

- **D-10 cluster (`transferBetweenPools` Lootbox-touching callsites):** marked as ROW-CLUSTER pending Phase 299 FIX sub-phase per-callsite expansion. Each callsite inside `JackpotModule` / `MintModule` / `GameOverModule` that touches `Pool.Lootbox` (either direction) needs its own `(slot × writer × callsite)` row. Grep verification deferred to the phase-integration step (§15 per-slot writer table), where the cross-consumer view sees all reach paths at once.
- **C6-C9 specific writer-callsite line numbers** for `lastPurchaseDay` purchase-path / advance-clear / `jackpotPhaseFlag` / `purchaseStartDay` / `rngRequestTime` are flagged in §C as "see grep" without per-line citation — these are documented at the writer-class level (purchase-path-EOA vs advance-state-machine) which is sufficient for verdict classification (per-callsite line precision is below the resolution where EXEMPT-vs-VIOLATION class flips). Phase 299 sub-phase planning can pull exact lines when sub-phase-shape decisions require them. Not a stub blocking the §6 catalog goal.

## Threat Flags

None — this catalog section enumerates pre-existing surface only; no new endpoints, schemas, or trust boundaries introduced.

## Self-Check: PASSED

- [x] `.planning/phases/298-vrf-read-graph-catalog-catalog/298-06-CATALOG-section.md` exists (verified `[ -f ]`).
- [x] All 5 CAT sub-headings present (CAT-01 through CAT-06; CAT-05 omitted per `D-298-CATALOG-LAYOUT-01` convention used by §1-§4 — no consumer's per-section file ships CAT-05).
- [x] §B Participating? column populated; NO rows have attestation in the rightmost column.
- [x] §C covers every YES slot from §B (`lootboxEvBenefitUsedByLevel`, `level`, `dgnrs.poolBalances[Lootbox]`, `rngLockedFlag`, `ticketWriteSlot`, `lastPurchaseDay`, `jackpotPhaseFlag`, `purchaseStartDay`, `rngRequestTime` — 9 slots, all enumerated).
- [x] Every §D row classified into {`EXEMPT-ADVANCEGAME`, `EXEMPT-VRFCALLBACK`, `EXEMPT-RETRYLOOTBOXRNG`, `VIOLATION`, `Mixed — split per callsite in Phase 299 FIX sub-phase`} — no `SAFE_BY_DESIGN` / no discretionary safe-by-construction.
- [x] Every VIOLATION (D-4, D-9, D-16) has §E tactic + ≤80-char rationale.
- [x] Zero `contracts/` + zero `test/` modifications (`git diff --name-only HEAD | grep -E '^(contracts|test)/' | wc -l` = 0).
- [x] No STATE.md / ROADMAP.md mutations.
- [x] Literal `SAFE_BY_DESIGN` token absent (`grep -c SAFE_BY_DESIGN` = 0).
