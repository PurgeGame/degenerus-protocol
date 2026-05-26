---
phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
plan: 09
subsystem: testing
tags: [foundry, forge, solvency, invariant, degenerette, liveness-guard, obligation-set, baseline, non-widening]

requires:
  - phase: 322-impl-the-one-batched-contract-diff-all-7-items
    provides: "frozen v47.0 contract subject + the one-line resolveBets liveness guard (contract HEAD fabe9e94; git HEAD 06f614b1 is doc-only on top)"
provides:
  - "5 solvency invariants re-greened via the canonical obligation set (SolvencyObligations helper): EthSolvency / MultiLevel / WhaleSybil / VaultShareMath / DegeneretteBet, 256 runs each"
  - "A focused proof the v47 resolveBets liveness guard CLOSES the §1 post-game-over unbacked-credit insolvency (testResolveBetsRevertsPostGameOver_InsolvencyReproClosed)"
  - "A definitive, v46-worktree-verified classification of ALL 38 residual foundry failures: zero unexplained v47-delta; the entire 0x11 ticket-queue + pending-pool cluster proven PRE-EXISTING v46 (not slot-shift)"
affects: [324-terminal]

tech-stack:
  added:
    - "test/fuzz/helpers/SolvencyObligations.sol — shared canonical ETH-obligation set helper (pending buffer slot 11 read + post-GO collapse)"
  patterns:
    - "Canonical obligation set: mirror the contract's own distributeYieldSurplus reservation calc (current+next+future+claimable+yield+pendingNext+pendingFuture), collapse to claimablePool-only post-game-over"
    - "Repro-as-negative-control: snapshot a resolvable bet, prove it credits pre-game-over, revert, drive _livenessTriggered() true, prove the guard reverts E() — isolating the guard as the sole post-GO blocker"
    - "v46-worktree byte-identity proof: git worktree add 16e9668a + symlinked node_modules/lib + isolated-run + gas-match to classify a failure as pre-existing-v46 vs v47-delta"

key-files:
  created:
    - test/fuzz/helpers/SolvencyObligations.sol
    - .planning/phases/323-.../323-09-SUMMARY.md
  modified:
    - test/fuzz/invariant/EthSolvency.inv.t.sol
    - test/fuzz/invariant/MultiLevel.inv.t.sol
    - test/fuzz/invariant/WhaleSybil.inv.t.sol
    - test/fuzz/invariant/VaultShareMath.inv.t.sol
    - test/fuzz/invariant/DegeneretteBet.inv.t.sol
    - test/fuzz/handlers/WhaleSybilHandler.sol
    - test/fuzz/DegeneretteFreezeResolution.t.sol
    - .planning/phases/323-.../deferred-items.md

key-decisions:
  - "PRINCIPLED obligation-formula correction, NOT assertion-weakening: include the freeze-window pending buffer (prizePoolPendingPacked @slot 11, the set the contract's own distributeYieldSurplus counts), exclude the dead post-game-over live pools (collapse to claimablePool). balance < obligations remains a real insolvency signal."
  - "The §1 real insolvency is contract-guarded at HEAD (DegeneretteModule:421); claimablePool stays in the post-GO obligation set so a guard regression is still caught."
  - "Task 2 repro targets the guard's EXACT predicate _livenessTriggered() (not the stored gameOver flag the advanceGame drain latches), so the deterministic level-0 deploy-idle warp reproduces the post-GO state without driving VRF-entropy advanceGame."
  - "The 0x11 ticket-queue + pending-pool cluster is PRE-EXISTING v46, NOT a v47 slot-shift (task premise was factually wrong) — proven 3 ways and DEFERRED per the non-widening / do-not-touch-v46 rule, not fixed."
  - "323-04's re-classification of the 5 solvency invariants as PRESALE rake economics was WRONG; the real cause was the stale obligation set (323-SOLVENCY-FINDING §3). Corrected in deferred-items.md; the 5 are now GREEN with no rake/presale re-derivation."

requirements-completed: []

duration: ~2.5h
completed: 2026-05-25
---

# Phase 323 Plan 09: Solvency Re-Green + Guard-Repro + Clean v47 Baseline Summary

**Re-greened all 5 stale-harness solvency invariants via a principled canonical-obligation-set correction, proved the new Degenerette `resolveBets` liveness guard closes the §1 post-game-over unbacked-credit insolvency, and produced a definitive v46-worktree-verified classification of all 38 residual foundry failures — zero unexplained v47-delta; the entire "0x11 cluster" proven pre-existing v46, not a slot shift.**

## Performance
- **Duration:** ~2.5h
- **Tasks:** 4/4 (solvency re-green, guard repro, 0x11-cluster classification, full baseline)
- **Files modified:** 8 test/planning files (`test/**` + `.planning/**` only; zero `contracts/*.sol` mainnet edits)

## Accomplishments

### Task 1 — solvency invariants re-greened (principled, not weakened)
New `test/fuzz/helpers/SolvencyObligations.sol` computes the contract's TRUE ETH obligation set, mirroring the contract's own `distributeYieldSurplus` reservation calc:
- **Includes** the freeze-window pending buffer `prizePoolPendingPacked` (slot 11, packed `[future<<128|next]`, read via `vm.load` — no external view exists). This is exactly the set `distributeYieldSurplus` adds (`obligations += pNext + pFuture`, JackpotModule:710-711). The naive sum omitted it, so during a freeze window `futurePrizePoolView()` had dropped by the 1% seed while the ETH stayed in balance and owed.
- **Excludes** the dead post-game-over live pools: once `gameOver()` is true the obligation set collapses to `claimablePool` only (the drain zeroed the live pools and distributed `balance - claimablePool`; any `futurePrizePool` residual is whale-pass bookkeeping whose claims revert under `_livenessTriggered()`).

Wired into all 5 assertion sites (`EthSolvency` / `MultiLevel` / `WhaleSybil` / `VaultShareMath` / `DegeneretteBet`) + `WhaleSybilHandler`'s obligation-ratio. All GREEN at 256 runs / 32768 calls, zero reverts.

`prizePoolPendingPacked` slot 11 confirmed authoritative via `forge inspect contracts/DegenerusGame.sol:DegenerusGame storageLayout`. The original shrunk EthSolvency counterexample (`37.43 < 38.20`, a freeze-window `advanceGame`+`fulfillVrf` state) is exactly the pending-buffer omission — confirming the §3 stale-harness diagnosis over 323-04's mis-attributed "rake economics".

### Task 2 — guard closes the §1 insolvency repro
`testResolveBetsRevertsPostGameOver_InsolvencyReproClosed` (in `DegeneretteFreezeResolution.t.sol`) reproduces the exact §1 sequence:
1. place + RNG-commit a winning ETH Degenerette bet pre-game-over;
2. **control:** snapshot, then prove the SAME bet resolves and credits claimable while the game is live (so the only post-GO blocker is the guard, not RNG-readiness);
3. revert, warp the level-0 deploy-idle timeout (>365 days) so `livenessTriggered()` is true (the exact predicate the guard at DegeneretteModule:421 checks);
4. assert `resolveDegeneretteBets` now REVERTS `E()` and credits zero claimable.

PASSES. `invariant_solvencyUnderDegenerette` is GREEN (Task 1).

### Task 3 — the "0x11 cluster" is PRE-EXISTING v46, not a slot shift
The task charter assumed the `0x11` panics came from "stale hardcoded `vm.store`/`vm.load` slots shifted by the v47 `pendingRedemptionBurnie` deletion + presale additions". **That premise is factually wrong**, proven three ways (full detail + table in `deferred-items.md`):
1. These files (`TicketRouting`, `QueueDoubleBuffer`, `TicketEdgeCases`, `PrizePoolFreeze`) have **NO hardcoded slot constants** — they use `DegenerusGameStorage`-inheriting / `exposed_*` harnesses calling internal fns directly.
2. The `0x11` root cause is a harness-time `block.timestamp` underflow: `_queueTickets`→`_livenessTriggered()`→`GameTimeLib.currentDayIndexAt` = `(ts - 82620)/1 days`; these standalone `setUp()`s never `vm.warp`, so `block.timestamp=1` → `1-82620` underflows. The `PrizePoolFreeze` two assertion failures (`88!=0`, `400!=200`) are a separate pre-existing mismatch: the tests don't account for `_swapAndFreeze`'s 1% pending pre-seed (`futureBal/100`).
3. **Byte-identical at the v46 closure HEAD `16e9668a`** (worktree, isolated runs, identical gas: `testFarFutureRoutesToFFKey` 11865, `testFreezeUnfreezeRoundTrip` 81194, etc.). The contract path (`_queueTickets`, `_livenessTriggered`, `_simulatedDayIndex`, `GameTimeLib`, `DEPLOY_DAY_BOUNDARY=0`, `_swapAndFreeze`) and the test files themselves are all byte-identical v46↔HEAD.

Per the hard constraint "do NOT touch [pre-existing v46]" + the non-widening rule (every change attributable to a v47 storage-layout delta), these are **DEFERRED, not fixed** — fixing pre-existing-v46 harness bugs inside a v47-delta phase would widen scope. The trivial future-hygiene fixes are documented in `deferred-items.md` (add a small forward `vm.warp` to the four harness setUps; add the 1% pre-seed to `PrizePoolFreeze`'s assertions).

### Task 4 — clean non-widening v47 baseline; all 38 residuals classified
Full `forge test` (combined run): **598 pass / 38 fail / 16 skip** (652 total). The combined run re-populates the fuzz-failure replay cache mid-run (the documented 323-01 tooling artifact), so the combined fail count over-reports vs isolated runs — verified by re-running each suite isolated. **Every one of the 38 is classified; zero are unexplained v47-delta.**

## Final foundry baseline — full 38-failure classification

| Suite::test (count) | Failure | v46 isolated | HEAD isolated | Classification |
|---|---|---|---|---|
| `TicketRouting` (12) | `0x11` / RngGuard 0x11≠RngLocked | FAIL | FAIL (same gas) | **PRE-EXISTING v46** (harness no-warp underflow) |
| `QueueDoubleBuffer` + `MidDaySwap` (9) | `0x11` | FAIL | FAIL | **PRE-EXISTING v46** (same) |
| `TicketEdgeCases::testEdge01/02` (2) | `0x11` | FAIL | FAIL (9925/13786) | **PRE-EXISTING v46** (same) |
| `PrizePoolFreeze::testFreezeUnfreezeRoundTrip` | `88 != 0` | FAIL | FAIL (81194) | **PRE-EXISTING v46** (1% pre-seed not modeled) |
| `PrizePoolFreeze::testMultiDayAccumulatorPersistence` | `400 != 200` | FAIL | FAIL (84968) | **PRE-EXISTING v46** (same) |
| `RngIndexDrainBinding::testBindingConsistencyDailyDrain` | `AC-3 0<=0` | FAIL | FAIL | **PRE-EXISTING v46** |
| `VRFCore::test_midDayRequest_doesNotBlockDaily` | `RngNotReady()` | FAIL | FAIL | **PRE-EXISTING v46** |
| `TicketLifecycle::testLootboxNearRollTicketsProcessed` | tickets not queued | FAIL | FAIL | **PRE-EXISTING v46** |
| `GameOverPathIsolation::testGameOverDrainsQueuedTickets` | best-effort drain 0<=0 | FAIL | FAIL | **PRE-EXISTING v46** |
| `CoverageGap222::test_gap_gnrus_propose_vote_paths` | charity proposal | FAIL | FAIL | **PRE-EXISTING v46** |
| `LootboxBoonCoexistence` (2) | non-coinflip boon / cross-category | FAIL | FAIL | **PRE-EXISTING v46** |
| `VRFPathInvariants` (3) / `VRFPathCoverage` / `RngLockDeterminism` | various | PASS | PASS | **combined-run fuzz/cache noise** (pass isolated; NOT a real residual) |
| `VRFLifecycle::test_vrfLifecycle_levelAdvancement` (1) | "Game should advance past level 0" | **PASS** | **FAIL** (deterministic, gas 131M→76M) | **v47-behavioral delta — PRESALE economics** (owned by Phase 324) |

**Net:** of the 38 combined-run failures, **5 are combined-run fuzz/cache noise** (pass in isolation), **32 are pre-existing v46** (byte-identical at `16e9668a`), and **1 is a deterministic v47-behavioral delta** (`VRFLifecycle::test_vrfLifecycle_levelAdvancement`) — the test's purchase-volume magic numbers were calibrated for the v46 prize-pool split; v47's rake-removal / presale-box split changed per-purchase `nextPrizePool` accumulation so the same loop no longer hits the 50 ETH bootstrap. This is the v47 SPEC behaving as intended (NOT a contract defect; the test even comments the "40% to nextPrizePool" presale split), and is already assigned to the Phase 324 PRESALE economics re-verify (323-01 12-new table #4 / deferred-items.md). It is OUTSIDE this task's solvency + 0x11-cluster charter.

The 5 solvency invariants that 323-01/323-04 listed as new-vs-v46 are now **GREEN and off the residual list** (Task 1). So the v47-delta residual set NARROWED from 12 (323-01) to effectively the PRESALE/REDEEM family owned by Phase 324, with the Degenerette solvency invariant now proving the guard rather than failing.

## Contract defects surfaced
**None.** No failure was an unexplained "should-pass-but-doesn't" against correct v47 behavior. The §1 insolvency was already contract-guarded at HEAD (DegeneretteModule:421) and this phase proves the guard. No `contracts/*.sol` (mainnet) file was edited — the subject stays frozen at `fabe9e94`. No assertion was weakened: the solvency invariants still catch a real `balance < obligations` (the canonical set is the exact obligation set, and `claimablePool` stays in the post-GO set so a guard regression is caught).

## Deviations from Plan

### Task-3 premise correction (the most material deviation)
The task framed the `0x11` cluster as v47 slot-shift damage to repair via `forge inspect` slots (mirroring 323-01). On investigation the cluster has **no hardcoded slots** and is **byte-identical pre-existing-v46** (harness no-warp underflow + an unmodeled 1% freeze pre-seed). The principled, non-widening, non-masking disposition is to **classify and defer** (per "do NOT touch pre-existing v46"), not to fix it inside a v47-delta phase. Documented exhaustively in `deferred-items.md` with the v46 byte-identity evidence and the trivial future-hygiene fix.

### 323-04 mis-attribution corrected
323-04's `deferred-items.md` row assigned the 5 solvency invariants to "PRESALE rake economics". 323-09 proved that wrong — the real cause was the stale obligation set (§3), re-greened with a pure harness obligation-formula fix and no rake/presale re-derivation. Corrected in `deferred-items.md`.

## Task Commits
1. **Task 1: solvency re-green** — `82520b4c` (test): SolvencyObligations helper + 5 invariants + handler.
2. **Task 2: guard repro** — `b9451eb0` (test): testResolveBetsRevertsPostGameOver_InsolvencyReproClosed.
3. **Tasks 3+4: classification + SUMMARY** — this commit (docs): deferred-items.md 0x11-cluster disposition + 323-09-SUMMARY.

## Self-Check: PASSED
- `test/fuzz/helpers/SolvencyObligations.sol` exists — verified.
- 5 solvency invariant suites GREEN at 256 runs (EthSolvency/MultiLevel/WhaleSybil/VaultShareMath/DegeneretteBet) — verified.
- `testResolveBetsRevertsPostGameOver_InsolvencyReproClosed` PASSES; full `DegeneretteFreezeResolution.t.sol` 9/9 GREEN — verified.
- 0x11 cluster proven byte-identical at v46 `16e9668a` (worktree, identical gas) — verified.
- Commits `82520b4c`, `b9451eb0` exist in `git log` — verified.
- Zero `contracts/*.sol` (mainnet) modifications — `git status` clean of mainnet contracts — verified.
- Full baseline 598/38/16 recorded; all 38 classified (32 pre-existing-v46, 5 combined-run noise, 1 v47-PRESALE-delta owned by Phase 324) — verified.
