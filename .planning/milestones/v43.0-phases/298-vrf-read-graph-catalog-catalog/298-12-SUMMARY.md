---
phase: 298-vrf-read-graph-catalog-catalog
plan: 12
subsystem: vrf-read-graph-catalog
tags: [audit-only, rng-lock, sdgnrs, redemption-period, gambling-burn, F-41-02-class, cross-call-sload, freshness-violation]
requires: []
provides:
  - "§12 catalog entry for StakedDegenerusStonk.resolveRedemptionPeriod + rngWordForDay re-read"
  - "8 VIOLATION rows (D-1, D-3, D-5, D-7, D-8, D-10, D-11, D-12) collapsed into 1 root-cause cluster (E-1)"
  - "Attestation that rngWordByDay[claimPeriodIndex] cross-call SLOAD at sStonk:670 is write-once → not the violation surface"
  - "Identification of redemptionPeriodIndex stale-pointer re-roll pattern as the actionable F-41-02/03-class issue for §12"
affects: []
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-12-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-12-SUMMARY.md
  modified: []
decisions:
  - "D-1 VIOLATION root: redemptionPeriodIndex is NOT advanced inside resolveRedemptionPeriod, leaving it stale-pointing at the just-resolved period; post-resolution _submitGamblingClaimFrom on the same wall-clock day grows pendingRedemptionEthBase, forcing the NEXT advance to overwrite redemptionPeriods[D].roll with a fresh roll — strategic re-roll exploit with ~19% free EV per round (more with multi-shot)"
  - "Cross-call rngWordByDay[claimPeriodIndex] SLOAD at sStonk:670 IS safe: §C-10 enumerates 2 write sites (AdvanceModule:1841 _applyDailyRng + AdvanceModule:1793 _backfillGapDays), both EXEMPT-ADVANCEGAME; slot is write-once-per-day (gate at AdvanceModule:1187/:1201/:1271 short-circuits non-zero)"
  - "E-1 remediation tactic (a): rngLockedFlag-gated revert pattern extended to gate against post-resolution intra-period re-writes; insert at _submitGamblingClaimFrom (sStonk:752) checking `redemptionPeriods[redemptionPeriodIndex].roll != 0 && currentPeriod == redemptionPeriodIndex` → revert. Subsumes E-2..E-8 (all same writer fn)"
  - "Existing rngLockedFlag gate at sStonk:492 (the convention-precedent site cited in the methodology note) is STRUCTURALLY INSUFFICIENT for this consumer: it covers only the in-flight-VRF window, not the post-resolution / pre-next-advance intra-day window"
metrics:
  duration_minutes: 22
  tasks: 1
  files_created: 2
  source_mutations: 0
  test_mutations: 0
completed: 2026-05-18
---

# Phase 298 Plan 12: VRF Read-Graph Catalog — StakedDegenerusStonk.resolveRedemptionPeriod + rngWordForDay re-read Summary

VRF-derived-entropy backward-trace from sStonk's gambling-burn resolution lifecycle (advance-stack `resolveRedemptionPeriod` at sStonk:585 + EOA-stack cross-call `rngWordForDay(claimPeriodIndex)` re-read at sStonk:670) identified 15 participating SLOADs across 7 unique slots and 11 distinct writer-callsite tuples; the cross-call rngWord re-read itself is benign (write-once slot, EXEMPT writers) but a distinct-class freshness violation exists on sStonk-side accounting: `redemptionPeriodIndex` is left stale-pointing at a resolved period, letting an EOA grow `pendingRedemptionEthBase` via `burn()` post-resolution and FORCE a re-roll of `redemptionPeriods[D]` on the next advance — 8 VIOLATION rows collapse into one root-cause cluster with single remediation E-1 (tactic (a) rngLockedFlag-gated revert).

## Outputs

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-12-CATALOG-section.md` — §A traced-fn set + §B SLOAD table (split §B-A advance-side / §B-B claim-side) + §C writer enumeration (10 sub-sections C-1..C-10) + §D verdict matrix (17 rows + cross-cutting §D-VIOL exploit narrative) + §E remediation row collapsing E-1..E-8 into single tactic-(a) recommendation.

## Trace Result

- **Consumer (advance-side):** `StakedDegenerusStonk.resolveRedemptionPeriod` at `contracts/StakedDegenerusStonk.sol:585`. Access-guarded to `msg.sender == ContractAddresses.GAME`. Three reaching callsites all under `advanceGame()` stack: `AdvanceModule.sol:1230` (rngGate normal), `:1293` (gameOver-fresh VRF), `:1323` (gameOver-historical-fallback).
- **Consumer (EOA-side):** `StakedDegenerusStonk.claimRedemption` at `contracts/StakedDegenerusStonk.sol:618`. NO access guard — any holder with `pendingRedemptions[msg.sender].periodIndex != 0` may call. Cross-call re-read of `game.rngWordForDay(claimPeriodIndex)` at sStonk:670 hashed with `player` produces `entropy` passed to `game.resolveRedemptionLootbox` (§6 trace-stop boundary).
- **Reachable SLOAD count:** 15 participating + 5 non-participating attestations (B-B10/B-B11/B-B12/B-B13/B-B14/B-B15 — payout-sourcing reads + intrinsic balance ops + cleared/non-VRF-influencing slots).
- **Unique participating storage slots:** 7 — `redemptionPeriodIndex`, `pendingRedemptionEthBase`, `pendingRedemptionBurnieBase`, `pendingRedemptionEthValue`, `pendingRedemptionBurnie`, `pendingRedemptions[player].*` (struct), `redemptionPeriods[period].*` (struct), plus 3 cross-contract participating slots: `gameOver` (DegenerusGameStorage:290), `coinflipDayResult[flipDay]` (BurnieCoinflip:162), `rngWordByDay[day]` (DegenerusGameStorage:435).

## Writer Enumeration Highlights

All 10 §C sub-sections grep-verified per `feedback_verify_call_graph_against_source.md`. Key results:

- `rngWordByDay[claimPeriodIndex]` (§C-10) — sole writers `_applyDailyRng` (AdvanceModule:1841) + `_backfillGapDays` (AdvanceModule:1793), BOTH EXEMPT-ADVANCEGAME. Slot is write-once-per-day (gate at AdvanceModule:1187/:1201/:1271 short-circuits non-zero). **Cross-call re-read at sStonk:670 reads a permanently-frozen value once non-zero.**
- `redemptionPeriods[period]` (§C-7) — sole writer `resolveRedemptionPeriod` itself (sStonk:604), advance-stack only. **HOWEVER:** the keying SLOAD `redemptionPeriodIndex` (§C-1) can be stale-pointing at a closed period via the §D-VIOL flow, causing this advance-stack write to OVERWRITE prior resolutions.
- `redemptionPeriodIndex` (§C-1) — sole writer `_submitGamblingClaimFrom` (sStonk:760) via `burn()` / `burnWrapped()` EOA entries. Gated by `!gameOver`, `!livenessTriggered`, `!rngLocked` — none cover the post-resolution intra-day window.
- `pendingRedemptionEthBase` / `pendingRedemptionBurnieBase` (§C-2 / §C-3) — dual writers: `resolveRedemptionPeriod` zeroes (EXEMPT-ADVANCEGAME); `_submitGamblingClaimFrom` increments (EOA — VIOLATION).
- `gameOver` (§C-8) — sole writer `GameOverModule.handleGameOverDrain` at `:139`, reached only via `advanceGame() → _handleGameOverPath → handleGameOverDrain`. EXEMPT-ADVANCEGAME.
- `coinflipDayResult[flipDay]` (§C-9) — sole writer `BurnieCoinflip._resolveDay` (inside `processCoinflipPayouts:805`); 4 callers all in AdvanceModule (lines 1217, 1277, 1307, 1794), all advance-stack. EXEMPT-ADVANCEGAME.

## Verdict

17 (slot × writer × callsite) tuples → **8 VIOLATION**, **9 EXEMPT-ADVANCEGAME**, 0 EXEMPT-VRFCALLBACK, 0 EXEMPT-RETRYLOOTBOXRNG, 0 discretionary-disposition (milestone-goal prohibition honored).

| # | Slot | Writer × Callsite | Classification |
| --- | --- | --- | --- |
| D-1 | `redemptionPeriodIndex` (sStonk) | `_submitGamblingClaimFrom` × sStonk:760 (via `burn()` / `burnWrapped()`) | VIOLATION |
| D-2 | `pendingRedemptionEthBase` | `resolveRedemptionPeriod` × sStonk:594 | EXEMPT-ADVANCEGAME |
| D-3 | `pendingRedemptionEthBase` | `_submitGamblingClaimFrom` × sStonk:790 | VIOLATION |
| D-4 | `pendingRedemptionBurnieBase` | `resolveRedemptionPeriod` × sStonk:601 | EXEMPT-ADVANCEGAME |
| D-5 | `pendingRedemptionBurnieBase` | `_submitGamblingClaimFrom` × sStonk:792 | VIOLATION |
| D-6 | `pendingRedemptionEthValue` | `resolveRedemptionPeriod` × sStonk:593 | EXEMPT-ADVANCEGAME |
| D-7 | `pendingRedemptionEthValue` | `claimRedemption` × sStonk:657 | VIOLATION (severity downgraded; subsumed by E-1) |
| D-8 | `pendingRedemptionEthValue` | `_submitGamblingClaimFrom` × sStonk:789 | VIOLATION |
| D-9 | `pendingRedemptionBurnie` | `resolveRedemptionPeriod` × sStonk:600 | EXEMPT-ADVANCEGAME |
| D-10 | `pendingRedemptionBurnie` | `_submitGamblingClaimFrom` × sStonk:791 | VIOLATION |
| D-11 | `pendingRedemptions[player].*` | `_submitGamblingClaimFrom` × sStonk:803/805/806/810 | VIOLATION |
| D-12 | `pendingRedemptions[player]` (delete / partial clear) | `claimRedemption` × sStonk:661 / sStonk:664 | VIOLATION (severity downgraded) |
| D-13 | `redemptionPeriods[period]` (`{roll, flipDay}`) | `resolveRedemptionPeriod` × sStonk:604 | EXEMPT-ADVANCEGAME (overwrite risk arises via D-1) |
| D-14 | `gameOver` | `GameOverModule.handleGameOverDrain` × GameOverModule.sol:139 | EXEMPT-ADVANCEGAME |
| D-15 | `coinflipDayResult[flipDay]` | `BurnieCoinflip._resolveDay` × BurnieCoinflip.sol:840 | EXEMPT-ADVANCEGAME |
| D-16 | `rngWordByDay[day]` | `_applyDailyRng` × AdvanceModule.sol:1841 | EXEMPT-ADVANCEGAME |
| D-17 | `rngWordByDay[gapDay]` | `_backfillGapDays` × AdvanceModule.sol:1793 | EXEMPT-ADVANCEGAME |

## §D-VIOL — Cross-cutting Exploit Pattern

The 8 VIOLATION rows collapse into a single root-cause cluster: post-resolution intra-day re-burn forces re-roll of a closed period. Concretely:

1. Day D: Player A `burn()` → `redemptionPeriodIndex = D`, `pendingRedemptionEthBase != 0`.
2. Day D advance → `resolveRedemptionPeriod` writes `redemptionPeriods[D].roll = roll_D`, zeroes `pendingRedemptionEthBase`. `redemptionPeriodIndex` is NOT advanced (remains D). `_unlockRng(D)` clears `rngLockedFlag`.
3. Day D (same wall-clock): Player B reads `redemptionPeriods[D].roll` (public mapping). If unfavorable, calls `burn(1 wei)` → `pendingRedemptionEthBase != 0` (re-armed). All gates (sStonk:487/491/492) pass.
4. Day D+1 advance → `period = redemptionPeriodIndex = D`. `resolveRedemptionPeriod` OVERWRITES `redemptionPeriods[D] = {roll: roll_{D+1}, flipDay: D+2}`.
5. Asymmetric payoff: claim if good, re-roll if bad. Free EV ~19% per round; collateral damage to OTHER unclaimed Player C's whose `claim.periodIndex == D` (their stored roll gets overwritten too).

The methodology note's "first-time audit of this consumer's storage-write surface for rngLockedFlag freeze coverage" is corroborated: the existing rngLockedFlag gate at sStonk:492 covers only in-flight-VRF; the post-resolution intra-day window is **uncovered**.

## Remediation Recommendation

**Tactic (a) — rngLockedFlag-gated revert.** Single E-1 remediation subsumes E-2..E-8. Insert at `_submitGamblingClaimFrom` (sStonk:752, immediately after `currentPeriod = game.currentDayView();` at sStonk:757):

```solidity
if (redemptionPeriods[redemptionPeriodIndex].roll != 0 && currentPeriod == redemptionPeriodIndex) revert BurnsBlockedAfterResolution();
```

(Or reuse `BurnsBlockedDuringRng` — see Phase 299 plan-phase for naming.)

Mirrors the convention precedent at sStonk:492 (`if (game.rngLocked()) revert BurnsBlockedDuringRng();`) cited in the methodology note. Phase 290 MINTCLN's `cachedJpFlag && rngLockedFlag` pattern at `DegenerusGameMintModule.sol:1221` is the structural analogue.

Tactics (b) snapshot/anchor, (c) pre-lock reorder, and (d) immutable were considered and rejected on structural grounds (see §E rationale-expansion in the catalog section). Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline before final tactic selection.

## Methodology Discipline

- `feedback_rng_backward_trace.md` — traced BACKWARD from both consumer entries (sStonk:585 + sStonk:670) to every writer of every participating slot.
- `feedback_rng_window_storage_read_freshness.md` — enumerated ALL SLOADs in both `resolveRedemptionPeriod` and `claimRedemption` (15 participating + 5 non-participating attested). Identified `redemptionPeriodIndex` + sStonk-side accounting slots as the F-41-02/03-class non-VRF-derived participating reads; confirmed `rngWordByDay[claimPeriodIndex]` at sStonk:670 is write-once → not the violation surface.
- `feedback_rng_commitment_window.md` — confirmed RNG-publish (advance tx end) ↔ next-advance window is multi-tx (1+ wall-clock day apart). Attacker-controllable state mutations (post-resolution `_submitGamblingClaimFrom`) inside this window enable re-roll.
- `feedback_verify_call_graph_against_source.md` — every writer-enumeration claim grep-verified; consumer bodies fully inlined inside `resolveRedemptionPeriod` (sStonk:585-610) and `claimRedemption` (sStonk:618-684); cross-contract writers walked at storage-slot level (§C-8 `gameOver` / §C-9 `coinflipDayResult` / §C-10 `rngWordByDay`).
- `feedback_no_contract_commits.md` — zero `contracts/` + zero `test/` mutations (AUDIT-ONLY phase per D-43N-AUDIT-ONLY-01).

## Deviations from Plan

None — plan executed exactly as written. Single task (12.1) emitted the required §A..§E sections with zero discretionary-disposition rows and 8 VIOLATION rows each carrying tactic + ≤80-char rationale (with cross-cutting §D-VIOL exploit narrative collapsing the 8 rows into 1 root-cause cluster + 1 remediation E-1 subsuming E-2..E-8).

## Threat Flags

None — this plan is pure analysis; no new contract surface introduced.

## Self-Check: PASSED

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-12-CATALOG-section.md` exists.
- `## CAT-01`, `## CAT-02`, `## CAT-03`, `## CAT-04`, `## CAT-06` sub-headings present.
- Discretionary fifth-class disposition absent from catalog section (confirmed via `! grep -q SAFE_BY_DESIGN`).
- 8 VIOLATION rows each carry §E tactic ∈ {(a), (b), (c), (d)} + ≤80-char rationale; all 8 select tactic (a) per root-cause cluster collapse.
- Zero `contracts/` + zero `test/` modifications (`git diff --name-only HEAD` filtered to `contracts/|test/` → 0 lines).
- No `STATE.md` / `ROADMAP.md` edits in this plan's commit (parallel-dispatch session — STATE.md updates are out of scope per the plan's parallel-dispatch constraint).
