---
phase: 298-vrf-read-graph-catalog-catalog
plan: 04
subsystem: vrf-read-graph-catalog
tags: [audit-only, rng-lock, terminal-decimator, decimator-module, gameover, freshness-violation, F-41-02-class]
requires: []
provides:
  - "§4 catalog entry for runTerminalDecimatorJackpot"
  - "1 VIOLATION row for terminalDecBucketBurnTotal × recordTerminalDecBurn"
affects: []
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-04-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-04-SUMMARY.md
  modified: []
decisions:
  - "D-1 VIOLATION: terminalDecBucketBurnTotal writable post-RNG-publish, pre-gameOver-flip via BurnieCoin.terminalDecimatorBurn → recordTerminalDecBurn; multi-tx STAGE_TICKETS_WORKING window enables CREATE2/EOA address-grind into winning subbucket"
  - "E-1 remediation tactic (a): rngLockedFlag-gated revert mirroring Phase 290 MINTCLN pattern at DegenerusGameMintModule.sol:1221"
  - "Zero EXEMPT writers — single participating slot has a single non-EXEMPT writer-callsite"
metrics:
  duration_minutes: 18
  tasks: 1
  files_created: 2
  source_mutations: 0
  test_mutations: 0
completed: 2026-05-18
---

# Phase 298 Plan 04: VRF Read-Graph Catalog — DecimatorModule.runTerminalDecimatorJackpot Summary

VRF-derived-entropy backward-trace from `runTerminalDecimatorJackpot` (game-over terminal decimator jackpot) identified one participating SLOAD (`terminalDecBucketBurnTotal[bucketKey]`) and one VIOLATION writer-callsite (`recordTerminalDecBurn` ← `BurnieCoin.terminalDecimatorBurn`), enabling a post-RNG address-grind attack across the multi-tx game-over drain window; remediation recommends tactic (a) rngLockedFlag-gated revert.

## Outputs

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-04-CATALOG-section.md` — §A traced-fn set + §B SLOAD table + §C writer enumeration + §D verdict matrix + §E remediation row.

## Trace Result

- **Consumer:** `DegenerusGameDecimatorModule.runTerminalDecimatorJackpot` at `contracts/modules/DegenerusGameDecimatorModule.sol:755`.
- **Reach pattern:** delegatecalled from `DegenerusGame.runTerminalDecimatorJackpot` (`DegenerusGame.sol:1142`), which is self-called from `GameOverModule.handleGameOverDrain` (`GameOverModule.sol:168`) after `gameOver=true` is latched at line 139 in the same transaction. Upstream caller is `_handleGameOverPath` (`AdvanceModule.sol:522`), which publishes `rngWordByDay[day]` via `_applyDailyRng` (`AdvanceModule.sol:1841`) potentially several transactions earlier when `STAGE_TICKETS_WORKING` forces multi-tx re-entry.
- **Reachable SLOAD count:** 3 enumerated (`ContractAddresses.GAME` library constant; `lastTerminalDecClaimRound.lvl`; `terminalDecBucketBurnTotal[bucketKey]` in the 2..12 loop).
- **Participating SLOAD count:** 1 (`terminalDecBucketBurnTotal[bucketKey]`).
- **Non-participating attestations:** `ContractAddresses.GAME` is a `library` compile-time constant (no SLOAD); `lastTerminalDecClaimRound.lvl` is written only by the consumer itself (post-RNG snapshot at lines 798-800) — its read at line 763 short-circuits before any RNG-derived output is produced.

## Writer Enumeration

Single participating slot `terminalDecBucketBurnTotal[bucketKey]` has exactly one writer (`DegenerusGameDecimatorModule.sol:731`) reached from exactly one external entry point (`BurnieCoin.terminalDecimatorBurn` at `BurnieCoin.sol:634`). Confirmed via `grep -rn "terminalDecBucketBurnTotal" contracts/ --include="*.sol"` (2 total source hits: 1 declaration + 1 write site). Zero OZ-inherited writers (mapping owned by app-state contract, not a token). Zero admin/owner writers (no `onlyOwner` / `onlyAdmin` modifiers in DecimatorModule). Zero inline-assembly raw-sstore writers.

## Verdict

1 (slot × writer × callsite) tuple → 1 VIOLATION, 0 EXEMPT.

| Slot | Writer × Callsite | Classification |
| --- | --- | --- |
| `terminalDecBucketBurnTotal[bucketKey]` | `recordTerminalDecBurn` × `:731` via `BurnieCoin.terminalDecimatorBurn` external EOA entry | VIOLATION |

The writer reaches none of the three EXEMPT entry-point stacks (`advanceGame()` / VRF coordinator callback / `retryLootboxRng()`); it is a direct external EOA call gated only by `terminalDecWindow.open == (!gameOver && !lastPurchaseDay)` and `daysRemaining > 7`. Across the multi-tx STAGE_TICKETS_WORKING gap inside `_handleGameOverPath`, both gates can hold simultaneously with `rngWordByDay[day]` already published.

## Remediation Recommendation

**Tactic (a) — rngLockedFlag-gated revert.** Gate `recordTerminalDecBurn` (or the upstream BurnieCoin entry) on `rngWordByDay[day] == 0` once a game-over path is in progress, mirroring the Phase 290 MINTCLN pattern at `DegenerusGameMintModule.sol:1221`. Tactics (b) snapshot/anchor, (c) pre-lock reorder, and (d) immutable were considered and rejected on structural grounds (aggregate-mutability + unavoidable multi-tx STAGE_TICKETS_WORKING split); see §E rationale-expansion in the catalog section. Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline before final tactic selection.

## Methodology Discipline

- `feedback_rng_backward_trace.md` — traced backward from the consumer; verified word unknown at every prior writer commitment time (writer at `:731` runs in transactions PRIOR to the consumer; rngWord becomes known after the writer's last legitimate use case but BEFORE the consumer reads — the freshness violation window).
- `feedback_rng_window_storage_read_freshness.md` — enumerated ALL SLOADs in `runTerminalDecimatorJackpot`, not just VRF-derived seeds; identified `terminalDecBucketBurnTotal` as the F-41-02/03-class non-VRF-derived participating read.
- `feedback_rng_commitment_window.md` — confirmed RNG-publish ↔ consumer-read window spans MULTIPLE transactions (STAGE_TICKETS_WORKING early returns at `AdvanceModule.sol:596` and `:615`), creating an attacker-controllable mutation window.
- `feedback_verify_call_graph_against_source.md` — every claim grep-verified pre-write; consumer body fully inlined inside `runTerminalDecimatorJackpot` (no internal cross-call other than two `private pure` helpers); writer enumeration grep-confirmed exhaustive.
- `feedback_no_contract_commits.md` — zero `contracts/` + zero `test/` mutations (AUDIT-ONLY phase).

## Deviations from Plan

None — plan executed exactly as written. Single task (4.1) emitted the required §A..§E sections with no SAFE_BY_DESIGN dispositions and exactly one VIOLATION row carrying tactic + ≤80-char rationale.

## Threat Flags

None — this plan is pure analysis; no new contract surface introduced.

## Self-Check: PASSED

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-04-CATALOG-section.md` exists.
- `## CAT-01`, `## CAT-02`, `## CAT-03`, `## CAT-04`, `## CAT-06` sub-headings present.
- `SAFE_BY_DESIGN` absent from catalog section (confirmed via `grep -q SAFE_BY_DESIGN`).
- VIOLATION tactic `(a)` + rationale ≤80 chars (`Gate `recordTerminalDecBurn` on `rngWordByDay[day]==0` so window closes at RNG publish` — 79 chars in the table cell).
- Zero `contracts/` + zero `test/` modifications (`git diff --name-only HEAD~1 HEAD` → only `.planning/phases/298-*/298-04-CATALOG-section.md`).
- No `STATE.md` / `ROADMAP.md` edits in this plan's commit (parallel-dispatch session — STATE.md updates are out of scope).
- Catalog commit `3ed5648f` exists on `main`.
