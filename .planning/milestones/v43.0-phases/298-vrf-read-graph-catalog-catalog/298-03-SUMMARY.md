---
phase: 298-vrf-read-graph-catalog-catalog
plan: 03
subsystem: VRF read-graph catalog (consumer §3 — runTerminalJackpot)
tags: [audit, vrf, rng-lock, catalog, jackpot-module, game-over]
requires: []
provides: [298-03-CATALOG-section.md]
affects: []
tech-stack:
  added: []
  patterns: [vrf-backward-trace, sload-enumeration, writer-set-cataloging, per-callsite-classification]
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-03-CATALOG-section.md
  modified: []
decisions:
  - "Verified runTerminalJackpot reaches §3 with (isJackpotPhase=false, isFinalDay=false, splitMode=SPLIT_NONE, gameOver=true). Confirmed gameOver is latched TRUE in handleGameOverDrain:139 BEFORE runTerminalJackpot is invoked — autoRebuyState SLOAD + solo-bucket whale-pass branch are unreachable from §3."
  - "Identified 6 participating slots (dailyIdx, dailyHeroWagers[day][q], traitBurnTicket length, traitBurnTicket per-index, deityBySymbol, gameOver as control-flow gate); 7 non-participating SLOAD entries attested (claimablePool RMW, currentPrizePool not reached, prizePoolsPacked not reached, autoRebuyState not reached, claimableWinnings is SSTORE-only, resumeEthPool not reached, whalePassClaims not reached)."
  - "5 VIOLATION rows surfaced: dailyHeroWagers via placeDegeneretteBet, traitBurnTicket × 3 admin/helper writers in DegenerusGame.sol, deityBySymbol via purchaseDeityPass. 3 EXEMPT-ADVANCEGAME rows: dailyIdx writer, traitBurnTicket via MintModule processTicketBatch, gameOver writer itself."
  - "Recommended tactics: (b) snapshot-anchor for dailyHeroWagers (Phase 288 dailyIdx precedent); (a) rngLockedFlag/gameOver-gated revert for traitBurnTicket admin writers + deityBySymbol writer."
metrics:
  duration: 1
  completed: 2026-05-18
  tasks: 1
  files: 1
---

# Phase 298 Plan 03: VRF Read-Graph Catalog §3 (runTerminalJackpot) Summary

Backward-traced VRF-derived entropy from `JackpotModule.runTerminalJackpot` (`contracts/modules/DegenerusGameJackpotModule.sol:278`) — game-over ETH terminal jackpot consumer §3 — producing the per-consumer catalog section (§A traced function set; §B SLOAD table; §C per-participating-slot writer enumeration; §D verdict matrix; §E remediation tactics) per CAT-01..CAT-06 of REQUIREMENTS, the v43.0 milestone goal `Every VRF Input Frozen at Commitment`, and methodology feedback `feedback_rng_backward_trace.md` / `feedback_rng_window_storage_read_freshness.md` / `feedback_rng_commitment_window.md` / `feedback_verify_call_graph_against_source.md`.

## One-liner

Cataloged 13 SLOAD entries (6 participating, 7 attested non-participating) and 9 (slot × writer × callsite) verdict rows (3 EXEMPT-ADVANCEGAME, 5 VIOLATION) for the game-over terminal-jackpot resolution path, including 4 unreached-branch attestations and tactic recommendations for each VIOLATION.

## What Was Built

A single per-consumer catalog section file at `.planning/phases/298-vrf-read-graph-catalog-catalog/298-03-CATALOG-section.md` with five required sub-sections:

- **§A (CAT-01)** — 25 traced functions (pure-library calls flagged `[pure]` for SLOAD-free attestation); 4 unreached-branch attestations inside `_processDailyEth` (`SPLIT_CALL2` block, mask-builder, solo-bucket branch, `resumeEthPool` SSTORE) and 1 inside `_addClaimableEth` (`!gameOver` auto-rebuy block).
- **§B (CAT-02)** — 13-row SLOAD table with explicit `Participating? (YES/NO)` column and per-row attestation for NO rows per `D-298-SLOT-CLASSIFICATION-01`. ALL SLOADs reached inside the rng-window resolution path enumerated per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent).
- **§C (CAT-03)** — Per-participating-slot writer enumeration for each YES row, with grep-verified writer counts cited inline.
- **§D (CAT-04)** — (slot × writer × callsite) verdict matrix, 8 rows, classifications ∈ {EXEMPT-ADVANCEGAME, VIOLATION}; explicit negative-space attestation for the absence of `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` rows on this consumer.
- **§E (CAT-06)** — 5 VIOLATION rows with single tactic (a|b|c|d) + ≤80-char rationale.

## Key Decisions

1. **gameOver pre-call latch identified as a load-bearing reachability gate.** `handleGameOverDrain` writes `gameOver = true` at `GameOverModule.sol:139` BEFORE invoking `runTerminalJackpot`. This eliminates the auto-rebuy stack (`autoRebuyState[beneficiary]` SLOAD + `_processAutoRebuy` + `_calcAutoRebuy`) from §3's reachable set per `feedback_verify_call_graph_against_source.md` discipline. Explicitly attested as a NOT-REACHED entry in §B row #10 rather than silently omitted.
2. **`isJackpotPhase = false` parameter eliminates solo-bucket branch.** `_processDailyEth` is invoked with `isJackpotPhase=false`, making the `traitIdx == remainderIdx && isJackpotPhase` branch at `:1308` unreachable. `_handleSoloBucketWinner`, `_processSoloBucketWinner`, `whalePassClaims` SSTORE, `dgnrs.poolBalance`/`transferFromPool`, and `_setFuturePrizePool` from the whale-pass path are all unreachable from §3. Attested in §A "Unreached branches" block.
3. **`gameOver` SLOAD classified as participating (control-flow gate).** Even though the value is forced TRUE for §3, the SLOAD at `_addClaimableEth:792` gates an entire branch (auto-rebuy → autoRebuyState SLOAD → ticket queueing). A stale or wrong read could re-enable the autoRebuy branch and pull `autoRebuyState[beneficiary]` into participation. Marked YES + dedicated row in §C.6 and §D.
4. **`claimablePool += uint128(liabilityDelta)` classified NON-PARTICIPATING.** The `+=` triggers an SLOAD-MODIFY-SSTORE, but the prior value is not consumed in any branch/comparison/hash that influences VRF-derived output. Attested in §B row #7 — pure aggregate-liability accumulator update.
5. **`traitBurnTicket` length + per-index slot listed as two §B rows but one §C writer group.** The Solidity layout means both slots are written by the same SSTORE block in `MintModule._storeTraits` (`:616` + `:627`). Per-callsite verdict-matrix granularity preserved in §D (each admin writer in `DegenerusGame.sol` is a separate row).

## Deviations from Plan

None — plan executed exactly as written.

## Verification Performed

- `test -f` on the CATALOG section file: **PASS**.
- `grep -q "## CAT-01" .. "## CAT-06"`: all 5 sub-headings present.
- `grep -q "SAFE_BY_DESIGN"`: **0 occurrences** (verified via `if ! grep -q ...`).
- `git diff --name-only HEAD | grep -E '^(contracts|test)/'`: **0 files** — zero source-tree mutations.
- Cross-checked SLOAD enumeration against `feedback_rng_window_storage_read_freshness.md` F-41-02/03 precedent — all non-VRF storage reads inside the rng-window resolution stack are enumerated (gameOver, claimablePool, claimableWinnings RMW path) and attested.
- Verified `runTerminalJackpot` callers via `grep -rn "runTerminalJackpot" contracts/`: only the `_handleGameOverPath` self-call route at `GameOverModule.sol:182` reaches the JackpotModule entry — confirming EXEMPT-ADVANCEGAME is the only EXEMPT class relevant to this consumer.
- Verified each §C writer claim via per-slot grep (e.g., `grep -rn "dailyIdx *=" contracts/` returns 1 hit; `grep -rn "dailyHeroWagers\[" contracts/` returns 1 SSTORE-class hit; etc.) — citations embedded in §C inline.

## Self-Check: PASSED

- File created: `.planning/phases/298-vrf-read-graph-catalog-catalog/298-03-CATALOG-section.md` — FOUND.
- All 5 CAT sub-headings (`## CAT-01`, `## CAT-02`, `## CAT-03`, `## CAT-04`, `## CAT-06`) present.
- Zero SAFE_BY_DESIGN occurrences.
- Zero `contracts/` + zero `test/` mutations.
- Every YES slot in §B has a §C writer enumeration entry.
- Every §D row carries a classification (no blanks, no SAFE_BY_DESIGN).
- Every VIOLATION row in §D has a corresponding §E tactic + rationale entry (5 VIOLATIONs → 5 §E rows).
