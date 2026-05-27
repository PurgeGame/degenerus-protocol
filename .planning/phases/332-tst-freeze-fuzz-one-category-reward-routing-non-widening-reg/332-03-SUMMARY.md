---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
plan: 03
subsystem: testing
tags: [foundry, keeper-router, advanceGame, reward-routing, re-home, stall-multiplier, gameover-mult-zero, mid-day-partial-drain, keeperSnapshot, GASOPT-01, GASOPT-03, owedMap-hoist, same-results, recipient-isolation]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the v49 reward-routing rework (ADV-01: advanceGame returns only uint8 mult, the 3 in-callee creditFlip removed) + the doWork advance leg (unit*ADVANCE_RATIO_NUM*mult) + keeperSnapshot (GASOPT-03 SUBSUMES GASOPT-02) + the MintModule owedMap pointer hoist (GASOPT-01)"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "the GAS-calibrated ADVANCE_RATIO_NUM=2 + the 1/2/4/6 stall ladder the multiplier-honored magnitude check exercises (asserted by RELATIVE magnitude, never the peg constant — peg owned by 331)"
provides:
  - "TST-03 empirical proof: advanceGame() called STANDALONE credits the caller ZERO (recipient-isolated count==0) yet STILL ticks the day (advance fully functional standalone, the unrewarded liveness fallback)"
  - "advanceGame driven via doWork() is REWARDED with the stall multiplier HONORED (a higher stall credits STRICTLY MORE — the 1/2/4/6 ladder flows through unit*2*mult, proven by relative magnitude, mintPrice/unit held identical via snapshot/revert)"
  - "the mid-day partial-drain advance leg (mult==1, AdvanceModule:194/217) is REWARDED via doWork (exactly one creditFlip), and the gameover path (mult==0) is UNREWARDED (zero creditFlip)"
  - "GASOPT-03: keeperSnapshot(players) is value-identical to N individual mintPrice()/rngLocked()/claimableWinningsOf(p) reads element-by-element, and drives an identical reinvest-sub autoBuy outcome"
  - "GASOPT-01: the owedMap pointer hoist (rk-loop-invariant) drains a multi-player far-future backlog to byte-identical per-player owed=0 + queue=0 through the advance-driven processFutureTicketBatch loop"
affects: [333-terminal-delta-audit-3-skill-adversarial-sweep-closure, TST-04-non-widening-ledger]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-pass recorded-log read (_keeperCreditCountAndAmount) deriving BOTH count and summed amount in one vm.getRecordedLogs() — vm.getRecordedLogs DRAINS the log buffer, so a second helper call would see an empty array (the multiplier-magnitude check needs count AND amount from the SAME tx)"
    - "Stall/mint-gate co-satisfaction: the _enforceDailyMintGate permissionless bypass needs >=30 min past the day boundary, which COLLIDES with the mult==1 stall window (<20 min). The multiplier-honored proof therefore compares mult==2 (31 min, gate bypassed) vs mult==6 (2h+1m), still proving the ladder flows through — mintPrice held identical (same deploy level) so the credit ratio == the mult ratio (3x), asserted as strict ordering only"
    - "Gameover-mult-zero via a surgical SLOT 0 byte-23 write: latch the public `gameOver` bool WITHOUT setting the gameover-time slot, so handleFinalSweep early-returns harmlessly (GO_TIME==0) and advanceGame takes the gameover branch (return 0) — confirmed by the public game.gameOver() getter flipping"
    - "Mid-day partial-drain staging by direct read-slot seed: seed a LARGE multi-player backlog (200 players x 3 whole tickets) at the contract's own read key (_tqReadKey honouring the live ticketWriteSlot) + clear ticketsFullyProcessed, sized to EXCEED WRITES_BUDGET_SAFE=550 (65%-scaled first batch) so _runProcessTicketBatch WORKS but does NOT finish -> STAGE_TICKETS_WORKING (mult==1) instead of fully draining to NotTimeYet"
    - "GASOPT-01 same-results observed via the contract's OWN ticketsOwedPacked storage after a REAL advance-driven drain (not a replica): a broken loop-invariant owedMap pointer would skip/double-process a player, stranding non-zero owed — full per-player drain == the byte-identical correct result"

key-files:
  created:
    - "test/fuzz/KeeperRewardRoutingSameResults.t.sol — 7 GREEN proofs (712 lines): TST-03 advance reward-routing (standalone-unrewarded / via-doWork-rewarded with mult honored / mid-day rewarded / gameover unrewarded) + GASOPT-01 owedMap-hoist + GASOPT-03 keeperSnapshot behavioral same-results"
  modified: []

key-decisions:
  - "Multiplier-honored proof compares mult==2 (31 min) vs mult==6 (2h+) rather than mult==1 vs mult==6, because the mult==1 window (<20 min past the day boundary) collides with the _enforceDailyMintGate 30-minute permissionless bypass (the fresh keeper has not minted today -> MustMintToday). Both compared stalls clear 30 min; the strict-ordering (high > low) still proves the 1/2/4/6 ladder is honored, with mintPrice/unit held identical via snapshot/revert so the credit ratio is the pure mult ratio."
  - "The mid-day partial-drain (mult==1) leg is the leg required to clear the must-have, so it is proven separately from the new-day stall ladder. A read-slot queue that FULLY drains in one batch returns (worked=false, finished=true) -> falls through to revert NotTimeYet (cursor/level both reset to 0, no observed work); the proof therefore seeds a backlog LARGER than one write budget so the batch does real work without finishing -> the STAGE_TICKETS_WORKING (mult==1) return is taken."
  - "GASOPT-01 is proven against the contract's OWN ticketsOwedPacked storage through a REAL advance-driven processFutureTicketBatch drain (mirroring FarFutureIntegration), NOT a copied replica of the loop (which would be vacuous). Full per-player drain (every seeded player owed -> 0, queue -> 0) IS the byte-identical correct result the rk-loop-invariant pointer must produce; a broken hoist would strand or double-process a player."
  - "GASOPT-02 SUBSUMED into GASOPT-03 honored (RESEARCH Pitfall 5): the proof does NOT search AfKing.sol for a per-iteration claimableWinningsOf hoist (count 0). The two GASOPT micro-opts proven are GASOPT-01 (MintModule owedMap pointer) + GASOPT-03 (keeperSnapshot batched read); GASOPT-03's keeperSnapshot-driven autoBuy is proven via a reinvestPct>0 sub (the only path AfKing._buildSubBuyParams consumes the batched read)."
  - "All reward observation is recipient-isolated to the keeper (_countCoinflipStakeUpdatedFor / _keeperCreditCountAndAmount, topics[1]==keeper) so a player's / box-owner's winnings credit can never inflate or mask the router-bounty count or amount — the same D-02 recipient-isolation principle as 332-02."

patterns-established:
  - "Pattern 1: standalone-unrewarded vs router-rewarded reward-routing proof — call game.advanceGame() directly (count to caller == 0, day still ticks) vs drive the SAME advance via afKing.doWork() (count to keeper == 1, multiplier honored by relative magnitude across snapshot/revert stall scenarios). Proves the bounty MOVED from the standalone path to the router without changing advance behavior."
  - "Pattern 2: GASOPT same-results via Foundry value/behavioral-equality against the contract's own views/storage — keeperSnapshot 3-tuple == N individual accessors element-by-element (+ identical autoBuy outcome); owedMap-hoist full per-player drain == correct accounting. Never a bytecode diff, never a resurrected pre-opt source."

requirements-completed: [TST-03]

# Metrics
duration: 13min
completed: 2026-05-27
---

# Phase 332 Plan 03: TST-03 Advance Reward-Routing (Unrewarded-Standalone vs Rewarded-via-doWork, Multiplier Honored) + GASOPT-01/03 Same-Results Summary

**Proved the v49 advanceGame reward-routing rework EMPIRICALLY (standalone `game.advanceGame()` credits the caller ZERO yet still ticks the day — the unrewarded liveness fallback; the SAME advance via `afKing.doWork()` credits the keeper with the 1/2/4/6 stall multiplier HONORED — a higher stall credits strictly more, by relative magnitude not the 331 peg; the mid-day partial-drain leg `mult==1` is rewarded; the gameover leg `mult==0` is unrewarded) and the two GASOPT micro-opts same-results (GASOPT-03 `keeperSnapshot` value-identical to N individual reads + identical autoBuy outcome; GASOPT-01 `owedMap` pointer hoist drains a multi-player backlog to byte-identical per-player owed=0), all by recipient-isolated COUNT/amount, with ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-05-27T17:15:30Z
- **Completed:** 2026-05-27T17:28:13Z
- **Tasks:** 2
- **Files created:** 1 (`test/fuzz/KeeperRewardRoutingSameResults.t.sol`, 712 lines, 7 tests)

## Accomplishments

- **Task 1 — advanceGame unrewarded-standalone vs rewarded-via-doWork (multiplier honored):**
  - `testAdvanceStandaloneUnrewarded`: `game.advanceGame()` called directly credits the caller ZERO (`_countCoinflipStakeUpdatedFor(caller)==0` — the 3 in-callee `creditFlip` removed at ADV-01; `advanceGame` returns only `uint8 mult`) while the day STILL ADVANCES (advance is fully functional standalone, just unrewarded).
  - `testAdvanceViaDoWorkRewardedMultiplierHonored`: the SAME new-day advance driven via `doWork()` credits the keeper exactly once, and at a HIGHER STALL credits STRICTLY MORE (mult==6 @ 2h+ vs mult==2 @ 31 min). `mintPrice`/`unit` held identical via `snapshot`/`revert`, so the credit ratio is the pure mult ratio — proven by strict ordering, NEVER the GAS-calibrated peg.
  - `testMidDayPartialDrainRewardedViaDoWork`: a `day == dailyIdx` advance that partially drains a 200-player read-slot backlog returns `mult==1` (ADV-05/D-07, no escalation), so the router credits the keeper exactly once.
  - `testGameoverAdvanceUnrewarded`: with the terminal `gameOver` flag latched (and the gameover-time slot left at 0 so `handleFinalSweep` early-returns harmlessly), the advance leg returns `mult==0` → the router's `if (mult > 0)` guard skips the bounty → ZERO creditFlip.
- **Task 2 — GASOPT-01 + GASOPT-03 behavioral same-results:**
  - `testKeeperSnapshotEqualsIndividualReads`: `keeperSnapshot(players)` returns `mintPriceWei == mintPrice()`, `rngLocked_ == rngLocked()`, and `claimables[i] == claimableWinningsOf(players[i])` element-by-element across 6 players with varied (some zero, some distinct non-zero) claimable balances — value-identical, non-vacuous (each tracks the seeded balance; at least one non-zero).
  - `testKeeperSnapshotDrivenAutoBuyIdenticalOutcome`: a `reinvestPct>0` sub (the only path `AfKing._buildSubBuyParams` consumes the batched read) autoBuys through the `keeperSnapshot` read and is bought-today — identical to the reference per-player computation.
  - `testGasopt01OwedMapHoistSameResults`: a 5-player far-future backlog (each seeded with non-zero owed at level 6) drains to byte-identical per-player `owed==0` + queue length 0 through a REAL advance-driven `processFutureTicketBatch` loop — the `rk`-loop-invariant `owedMap` pointer processed every player exactly once (no skip / double-count).
- All 7 tests GREEN; zero `contracts/*.sol` mutation.

## Task Commits

Both TDD tasks landed in one tightly-coupled proof file (the count/amount oracle and the snapshot/storage helpers share the file's helper surface), committed atomically as a single `test(...)` commit since both were authored and verified GREEN together (mirrors 332-02):

1. **Task 1 (reward routing) + Task 2 (GASOPT same-results)** — `e2fff795` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) — see the final docs commit.

## Files Created/Modified

- `test/fuzz/KeeperRewardRoutingSameResults.t.sol` — TST-03 proof file (`contract KeeperRewardRoutingSameResults is DeployProtocol` + a small `FFKeyHarness is DegenerusGameStorage` for the far-future key math). Ports the `_countCoinflipStakeUpdated` / `_countCoinflipStakeUpdatedFor` log-count oracle (extended with `_keeperCreditCountAndAmount` for the multiplier-magnitude check), the `_settleGame` VRF drain, and the buy-leg slot-forcing (`_pinBuyLegWalkedForToday`) from `KeeperRouterOneCategory.t.sol`; the `_seedClaimable` / `_seedFarTickets` / FF-key slot helpers from `FarFutureSalvageSwap.t.sol`; the real ticket-backlog driving (`_buyManyTickets` / `_seedNextPrizePool` / advance-through-FF-processing) from `FarFutureIntegration.t.sol`; and adds the mid-day read-slot seed (`_seedReadSlotTickets` / `_readKey` / `_setTicketsFullyProcessed`) + the surgical `_latchGameOver` (SLOT 0 byte 23).

## Verification

- `forge test --match-contract KeeperRewardRoutingSameResults` → **7 passed / 0 failed**.
- The reward-routing assertions use RELATIVE magnitude for the multiplier (high-stall credit > low-stall credit), never the 331 peg constant.
- The same-results assertions compare CONCRETE state — the `keeperSnapshot` 3-tuple fields element-by-element vs the individual accessors, and the per-player `ticketsOwedPacked` owed deltas (full drain) — not a vacuous comparison.
- `git diff --name-only contracts/` → empty (ZERO mainnet mutation, FROZEN subject honored).
- No synthetic harness contract beyond the read-only `FFKeyHarness` (far-future key pure math); zero RNG/result mutation.

## Deviations from Plan

None affecting scope. Three execution refinements (no contract change, no scope change), all required to make the locked reward-routing dispositions pass against the FROZEN subject:

1. **[Refinement — mult ladder vs mint gate] Compared mult==2 vs mult==6, not mult==1 vs mult==6.** The `_enforceDailyMintGate` permissionless bypass requires `>= 30 minutes` past the day boundary, which collides with the `mult==1` stall window (`< 20 min`): a fresh keeper that has not minted today reverts `MustMintToday()` inside `advanceGame` before the stall-multiplier is ever returned. The multiplier-honored proof therefore compares `mult==2` (31 min, gate bypassed) vs `mult==6` (2h+), still proving the 1/2/4/6 ladder flows through (`unit*2*mult`) by strict ordering with `unit` held identical. The mid-day `mult==1` leg IS proven (separately, where the mint gate is not the obstacle).
2. **[Refinement — mid-day partial-drain sizing] Sized the seeded read-slot backlog to EXCEED one write budget.** A read-slot queue that fully drains in one batch returns `(worked=false, finished=true)` (the cursor/level both reset to 0, no observed work) → `advanceGame` falls through to `revert NotTimeYet()` instead of the `STAGE_TICKETS_WORKING` (mult==1) return. The proof seeds 200 players × 3 whole tickets (well over `WRITES_BUDGET_SAFE=550`, 65%-scaled on the first batch) so the mid-day batch WORKS without finishing → the partial-drain `mult==1` leg is reached.
3. **[Refinement — single-pass log read] Derived count AND amount in one `getRecordedLogs()`.** `vm.getRecordedLogs()` DRAINS the recorded-log buffer; a `_countCoinflipStakeUpdatedFor` call followed by a separate amount-decode would see an empty array (amount = 0). `_keeperCreditCountAndAmount` reads the buffer once and returns both, so the multiplier-magnitude comparison sees the real credited amount.

No CLAUDE.md present in the project root (global instructions only).

## Contract Defects Surfaced

None. Every proof passed against the FROZEN v49 source. The `MustMintToday()` mint-gate interaction with the `mult==1` stall window is BY DESIGN (the daily mint gate is a liveness/anti-grief control independent of the bounty ladder), not a defect — it is accommodated by proving the multiplier with two stalls that both clear the 30-minute bypass.

## Known Stubs

None — no hardcoded empty values, placeholders, or unwired data sources. Every assertion drives real protocol state (real reinvest subscriber via the public `subscribe()` API, real advance/VRF drain via `_settleGame`, a real advance-driven far-future ticket drain) and reads it back via the contract's own views (`keeperSnapshot` / `mintPrice` / `rngLocked` / `claimableWinningsOf` / `advanceDue` / `gameOver`) or authoritative storage slots (`ticketsOwedPacked` / `lastAutoBoughtDay` / the read-slot queue). The varied claimable balances and far-future owed are seeded via `vm.store` into the real storage slots (mirroring `FarFutureSalvageSwap`), not mocked.

## Self-Check: PASSED

- `test/fuzz/KeeperRewardRoutingSameResults.t.sol` — FOUND
- commit `e2fff795` — FOUND
- `332-03-SUMMARY.md` — FOUND
- `forge test --match-contract KeeperRewardRoutingSameResults` — 7 passed / 0 failed
- `git diff --name-only contracts/` — empty (zero mainnet mutation)
