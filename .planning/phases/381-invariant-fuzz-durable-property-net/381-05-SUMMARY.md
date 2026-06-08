---
phase: 381-invariant-fuzz-durable-property-net
plan: 05
subsystem: testing
tags: [foundry, invariant-fuzz, pool-conservation, solvency, prize-pools, ghost-ledger]

# Dependency graph
requires:
  - phase: 380-foundation
    provides: green REGRESSION-BASELINE-v62 + DeployProtocol fixture + frozen subject c4d48008
  - phase: 381-invariant-fuzz-durable-property-net
    provides: the FUZZ-01..04 invariant exemplars (V61SolvencyAfpay/BoxEnqueue targetContract wiring, afterInvariant non-vacuity gate, falsifiability-test pattern)
provides:
  - PoolConservation.inv.t.sol — the canonical FUZZ-05 pool-conservation invariant (total-backed + no-unbacked-credit-vs-real-inflow) surpassing the weak MultiLevel/Composition checks
  - PoolFlowHandler — an action handler driving buy/advance/claim through real entrypoints with a ghost real-inflow/outflow ledger + advance counter (non-vacuity witness)
affects: [383-asymmetry-sweep, 384-advancegame-composition, 387-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "case (c) BUILD invariant: assert the actual conservation property the existing weak checks (balance>=claimablePool / sum>balance after-the-fact) miss"
    - "ghost real-inflow ledger as the conservation bound RHS: sum(4 pools) <= startingBacking + Σ(buy msg.value); internal transfers reshape the split, never inflate the RHS"
    - "two-sided non-vacuity: an afterInvariant ghost_advances>0 gate over the campaign PLUS a focused directly-driven test asserting real transfers ran (ghost_advances=6, sum4pools==realInflow exactly)"
    - "falsifiability via field-isolated vm.store into the authoritative pool slot (slot 2 high half = futurePrizePool) inflating a pool with no backing → trips BOTH bounds, restored to green"

key-files:
  created:
    - test/fuzz/invariant/PoolConservation.inv.t.sol
  modified:
    - test/fuzz/handlers/PoolFlowHandler.sol

key-decisions:
  - "Reused the pre-existing untracked PoolFlowHandler (verified its surface against live source — gameOver()/purchase/purchaseInfo/advanceGame/claimWinnings + the VRF mock pendingRequests struct order — all correct; never vm.stores a pool) rather than rewriting"
  - "Backed the game with 5M ETH in setUp BEFORE capturing startingBacking, so every wei that later enters via a buy is counted in ghost_realInflow and an internal transfer adds nothing to the conservation RHS"
  - "Falsifiability injects unbacked credit into futurePrizePool (slot 2 high half, forge-inspect authoritative) rather than reducing balance, matching the T-381-05-01 threat (a transfer minting credit out of thin air)"

patterns-established:
  - "Conservation oracle (sum(4 pools) <= startingBacking + realInflow) as the durable form the council's 383 ASYM-06 pool-mutation-pairing sweep gets checked against"

requirements-completed: [FUZZ-05]

# Metrics
duration: ~35min
completed: 2026-06-08
---

# Phase 381 Plan 05: POOL-CONSERVATION Invariant Summary

**A durable always-on pool-conservation invariant (PoolConservation.inv.t.sol) that asserts the four prize pools sum within ETH+stETH backing AND that internal future→next→current / skim / jackpot transfers conserve the total (sum(4 pools) <= startingBacking + real ETH inflow — no unbacked credit minted), surpassing the weak balance>=claimablePool check the existing harnesses settle for.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-06-08T05:45:00Z (approx)
- **Completed:** 2026-06-08T06:20:00Z (approx)
- **Tasks:** 2 (handler refine/verify + invariant authoring)
- **Files modified:** 2 (1 created, 1 reused/verified)

## Accomplishments
- Built the genuine GAP (case (c)): `invariant_noUnbackedCreditMinted` — the conservation oracle the existing checks miss. `sum(currentPrizePool + nextPrizePool + futurePrizePool + claimablePool) <= startingBacking + ghost_realInflow`, so an internal pool-to-pool transfer can only RESHAPE the split, never mint credit out of thin air.
- Strengthened the backing bound: `invariant_totalPoolsFullyBacked` widens MultiLevel's `balance >= claimablePool` (one pool) to `sum(4 pools) <= balance + stETH` (all four).
- Verified the pre-existing PoolFlowHandler's surface against live source and confirmed it drives buy (real inflow) / advance (advanceGame×3 + VRF-fulfill → `_consolidatePoolsAndRewardJackpots`) / claim (real outflow) through real entrypoints with a ghost in/out ledger, never `vm.store`-ing a pool.
- Proved non-vacuity two ways: the `afterInvariant` `ghost_advances > 0` campaign gate + a focused directly-driven test showing `ghost_advances=6` and `sum4pools == ghost_realInflow` EXACTLY (0.175 ETH) — every wei in a pool is backed by real ETH that entered.
- Proved falsifiability: a seeded unbacked futurePrizePool inflation (slot 2 high half) trips BOTH bounds; restoring returns both to green.
- ZERO contracts/*.sol mutation throughout.

## Task Commits

Each task was committed atomically:

1. **Task 1+2: PoolFlowHandler (verified/reused) + PoolConservation.inv.t.sol (authored)** - the single atomic `test(381-05)` commit at this plan's HEAD (test)

_The handler was pre-existing untracked from a prior crashed session; this plan verified its surface against live source and authored the new invariant, committed together as the FUZZ-05 deliverable. RED→GREEN was exercised via the falsifiability test (the invariant CAN fail on a seeded unbacked-credit mint) before the full 256/128 GREEN run._

**Plan metadata:** included in the same atomic commit (SUMMARY + STATE + ROADMAP + REQUIREMENTS) per the test-only single-commit instruction.

## Files Created/Modified
- `test/fuzz/invariant/PoolConservation.inv.t.sol` (created, 262 lines) - The FUZZ-05 invariant: `invariant_totalPoolsFullyBacked` (sum(4)<=balance+stETH) + `invariant_noUnbackedCreditMinted` (sum(4)<=startingBacking+realInflow) + `invariant_outflowNeverExceedsInflowPlusStart` (diagnostic) + `afterInvariant` non-vacuity gate (ghost_advances>0) + `test_poolTransfersExercised_nonVacuous` (directly-driven transfers, conservation holds) + `test_invariantIsFalsifiable_unbackedCreditMint` (seeded unbacked futurePrizePool inflation trips both bounds).
- `test/fuzz/handlers/PoolFlowHandler.sol` (reused/verified, 169 lines) - Drives buy (ghost_realInflow += msg.value), advance (advanceGame×3 + VRF fulfill; ghost_advances++), claim (ghost_realOutflow += payout delta) through real entrypoints; exposes ghost_realInflow/ghost_realOutflow/ghost_advances/actorCount; disjoint actor base 0x90010; never vm.stores a pool.

## Decisions Made
- Reused the pre-existing untracked PoolFlowHandler after verifying its full surface against live source (`gameOver()` is a public-getter callable as a fn, `purchase`/`purchaseInfo`/`advanceGame`/`claimWinnings` signatures match, the VRF mock `pendingRequests` struct order `(subId, consumer, fulfilled)` matches the handler's `(, , bool fulfilled)` destructure). No bug found that masked non-vacuity — `ghost_advances` increments correctly (6 in the focused run) and real ETH moves between pools.
- Captured `startingBacking` AFTER the 5M-ETH setUp deal but BEFORE any handler action, so the conservation RHS (`startingBacking + ghost_realInflow`) accounts for every wei and an internal transfer adds nothing to it.
- Falsifiability injects into `futurePrizePool` (forge-inspect authoritative slot 2 high half) — the T-381-05-01 "transfer mints unbacked credit" shape — rather than reducing balance, so the test exercises the exact threat the invariant guards.

## Deviations from Plan

None - plan executed exactly as written. The handler from the prior crashed session was sound (surface verified, non-vacuity intact), so no Rule 1/2/3 fixes were needed.

## Issues Encountered
- The forge invariant call-summary table renders empty in this foundry nightly (cosmetic — `reverts: 0` and the per-invariant run/call counts [256 runs / 32768 calls] are reported correctly). Confirmed the campaign genuinely exercises the handler via the `afterInvariant` ghost_advances>0 gate passing AND the focused test surfacing ghost_advances=6 / realInflow=0.175 ETH numerically.

## Verification

Targeted command (build cache warm):
```
forge test --match-contract "PoolConservation"
```
Result: **5 passed / 0 failed / 0 skipped**, 256 runs / 32768 calls / **0 reverts** per invariant.
- `invariant_noUnbackedCreditMinted()` (runs: 256, calls: 32768, reverts: 0)
- `invariant_totalPoolsFullyBacked()` (runs: 256, calls: 32768, reverts: 0)
- `invariant_outflowNeverExceedsInflowPlusStart()` (runs: 256, calls: 32768, reverts: 0)
- `test_invariantIsFalsifiable_unbackedCreditMint()` (gas: 102679)
- `test_poolTransfersExercised_nonVacuous()` (gas: 12325556)

Non-vacuity ghost magnitudes (from the focused directly-driven run): `ghost_advances=6`, `ghost_realInflow=0.175 ETH`, `ghost_realOutflow=0`, `sum4pools=0.175 ETH` (== realInflow EXACTLY — every pool wei is backed by real ETH that entered; internal transfers reshaped the split without minting credit).

`git status --short -- contracts/`: EMPTY (zero contract mutation).

## Next Phase Readiness
- FUZZ-05 (POOL-CONSERVATION) is a durable always-on invariant; Wave 1 of Phase 381 (FUZZ-01..05) is now complete and GREEN.
- The conservation oracle is the durable form Phase 383 ASYM-06 (every pool mutation paired and conserved) gets checked against.
- Remaining in Phase 381: 381-06 (FUZZ-06 council property-completeness review, `autonomous: false` — a USER hard-stop). NO advance to Phase 382 from this plan.

## Self-Check: PASSED

- FOUND: test/fuzz/invariant/PoolConservation.inv.t.sol
- FOUND: test/fuzz/handlers/PoolFlowHandler.sol
- FOUND: .planning/phases/381-invariant-fuzz-durable-property-net/381-05-SUMMARY.md
- `git status --short -- contracts/`: EMPTY (zero contract mutation)
- `forge test --match-contract "PoolConservation"`: 5 passed / 0 failed, 0 reverts over 256/128

---
*Phase: 381-invariant-fuzz-durable-property-net*
*Completed: 2026-06-08*
