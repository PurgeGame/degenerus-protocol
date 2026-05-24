---
phase: 318-tst-subscription-crank-correctness-removal-proofs-tst
plan: 03
subsystem: testing
tags: [safe-02, non-brick, crank, batchpurchase, slice-refund, reentrancy, sub-01, proto-02, sub-08, rew-02, burnforkeeper, all-or-nothing, sweep-bounty, pass-or-pay]

# Dependency graph
requires:
  - phase: 318-tst-subscription-crank-correctness-removal-proofs-tst (plan 01)
    provides: "Repaired DeployProtocol fixture (AfKing live at AF_KING via the N+18 insert; VAULT/SDGNRS SUB-09 self-subscribes present; HEAD ContractAddresses.sol is the correct foundry-patched state)"
  - phase: 318 (plan 02)
    provides: "CrankFaucetResistance bet-drive + RNG-word-injection + losing-ticket-isolation patterns reused verbatim here for the crankBets non-brick proofs"
  - phase: 317 (plans 03/04)
    provides: "Live batchPurchase per-slice try/catch + slice-refund + batch-level rngLocked/gameOver pre-check (DegenerusGame:1687); the AfKing sweep renewal pass-OR-pay + all-or-nothing burn auto-pause + single gas-pegged creditFlip bounty (AfKing:522)"
provides:
  - "SAFE-02 non-brick coverage: one poisoned (not-ready / reverting / sub-floor) item is isolated via onlySelf+try/catch and skipped across crankBets, crankBoxes, AND batchPurchase; the batch completes rewarding/buying only the successes"
  - "batchPurchase slice-refund proof (one batch value transfer in, the failed slice refunded to the keeper in the single post-loop refund) + the batch-level rngLocked/gameOver pre-check firing once at entry + the keeper-only gate"
  - "Reentrancy rollback proof (a bubbled re-entrant withdraw reverts the whole call; a swallowed re-entry yields a single payout) — no replayable batch-debit / double-spend"
  - "Cancel un-brickable proof: setDailyQuantity(0) tombstone then full _poolOf withdrawable (CEI withdraw cannot be blocked)"
  - "SUB/PROTO acceptance: SUB-01 pass-OR-pay renewal gate, PROTO-02/SUB-08 burnForKeeper all-or-nothing (shortfall burns nothing/auto-pauses, exactly-at-cost full burn), REW-02 single gas-pegged stall-scaled sweep bounty + NoSubscribersSwept/EmptySweep tail guards"
affects: [318-04, 318-05, 318-06, vrf-freeze-invariant]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Forge the caught-revert poison entry for crankBoxes by zeroing lootboxEth[index][player] (slot 15) while LEAVING lootboxEthBase != 0 — this dodges the cheap `continue`-skip (lootboxEthBase==0) so the per-item open actually executes and reverts E() (amount==0), proving the try/catch isolation distinct from the continue-skip"
    - "Poison a single batchPurchase per-player unit with a sub-LOOTBOX_MIN slice (mint module reverts E() at the 0.01 ETH floor) — a deterministic, in-context per-player revert that the per-slice try/catch isolates and refunds"
    - "Read the crank reward stake delta on the CALLER (cranker / sweeper), not the bet/box owner — the reward credits msg.sender; winnings credit the owner. A non-owning caller's stake delta is the pure crank/bounty reward, isolating it from owner winnings"
    - "Drive the AfKing day-31 renewal branch deterministically by writing the packed Sub's paidThroughDay <= today (and clearing lastSweptDay) via one slot write on _subOf (slot 1) — avoids a 31-day warp that would shift the keeper-local day + stall multiplier for every concurrent sub"
    - "Mirror the sweep's stall multiplier (1x/2x/4x/6x off day-start = today*1days+82620) in-test rather than hardcoding 1x — the fixture's day-1 timestamp lands at 63 min elapsed -> 4x"

key-files:
  created:
    - "test/fuzz/CrankNonBrick.t.sol"
    - "test/fuzz/AfKingSubscription.t.sol"
    - ".planning/phases/318-tst-subscription-crank-correctness-removal-proofs-tst/318-03-SUMMARY.md"
  modified: []

key-decisions:
  - "crankBoxes poison = lootboxEth-zeroed (slot 15) WITH lootboxEthBase intact: this is the ONLY shape that exercises the per-item try/catch isolation (a lootboxEthBase==0 entry is the cheaper continue-skip, which proves a different, weaker property). Drove three real lootbox purchases at one index for the healthy entries via the public mint API."
  - "Asserted the crank/box reward via the CALLER's coinflip stake delta priced at PriceLookupLib.priceForLevel(level()+1), not an event-count==1, because a WINNING box emits an extra winnings creditFlip to the box owner (2 emissions) that would break a naive count==1; the caller owns no box so its stake delta is the pure crank reward."
  - "Reentrancy proven with TWO variants from one mock: a BUBBLING re-entry (inner InsufficientBalance bubbles -> outer EthSendFailed -> whole call reverts, attacker extracts nothing) AND a SWALLOWING re-entry (outer completes a single payout, the re-entry adds nothing). Together they prove the at-most-once / no-double-spend property under both attacker strategies."
  - "Reached the sweep renewal branch by slot-writing paidThroughDay<=today on _subOf rather than warping 31 days — keeps `today` (and thus the stall multiplier and the other subs' state) stable so the renewal assertions are not entangled with day-advance side effects."
  - "Two BURNIE-funding paths used by design: mintForGame (GAME-gated, keeps totalSupply consistent) for the renewal-charge funding, and a direct balanceOf slot write (_setBurnieBalance) ONLY for the shortfall/at-cost BOUNDARY tests where an exact spendable total is required. The slot write leaves totalSupply unchanged (a benign harness-only invariant break); the deploy's 2M BURNIE supply guarantees the at-cost _burn cannot underflow."

patterns-established:
  - "Non-brick test triad: for any permissionless mass-do-work entry, prove skip-and-continue across EVERY entry point (here crankBets/crankBoxes/batchPurchase) with a fuzzed poison POSITION, plus the batch-level pre-check and the slice-refund accounting, plus a reentrancy-rollback + cancel-un-brickable liveness floor."

requirements-completed: [SAFE-02]

# Metrics
duration: ~12min
completed: 2026-05-23
---

# Phase 318 Plan 03: SAFE-02 Non-Brick + SUB/PROTO Acceptance Summary

**Built two Foundry suites proving the permissionless do-work cranks (crankBets / crankBoxes), the keeper-gated batchPurchase, and the AfKing subscription keeper are non-brick and behaviorally correct: one poisoned item is isolated via onlySelf+try/catch and skipped (the batch completes rewarding/buying only successes), a failed batchPurchase slice is refunded to the keeper, a re-entrant sweep/cancel cannot double-spend, cancel is un-brickable, and the subscription renewal is a faithful pass-OR-pay / all-or-nothing-burn / one-gas-pegged-bounty machine — 19 tests green (12 + 7), zero contracts/ mutation.**

## Performance
- **Duration:** ~12 min
- **Tasks:** 3
- **Files created:** 2 test suites (1083 LoC)
- **Tests:** 19 (12 CrankNonBrick + 7 AfKingSubscription), all green in isolation

## Accomplishments

### Task 1 — skip-and-continue + slice-refund + batch-level pre-check (CrankNonBrick.t.sol)
- `testCrankBetsSkipsPoisonedMiddleItem` + `testFuzz_CrankBetsPoisonPositionNeverBricks` — a length-3 crankBets with a live probe at index 0 and a not-ready (word-less) poison at a fuzzed position resolves the two healthy bets and SKIPS the poison (RngNotReady caught by `try this._crankResolveBet catch {}`); reward sums over the 2 successes only (`2 * 120000 * 0.5 gwei` at peg). The poison slot stays intact (re-crankable).
- `testCrankBoxesSkipsPoisonedEntryViaTryCatch` — three real lootboxes at one index whose word landed; the poisoned entry (lootboxEth zeroed, lootboxEthBase intact → module reverts E() inside `_crankOpenBox`) is caught by the per-item try/catch; a and c open, b is skipped, reward sums over the 2 opens only.
- `testBatchPurchaseIsolatesFailingPlayerAndRefundsSlice` + `testFuzz_BatchPurchaseFailPositionRefundsAndCompletes` — a length-3 batchPurchase as the AF_KING keeper with a sub-LOOTBOX_MIN failing slice at a fuzzed position: the two healthy players' lootboxes land, the failing player buys nothing, exactly the failed slice is refunded to the keeper (net outflow == the good slices), the call does NOT revert.
- `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` + `testBatchPurchaseGameOverRejectsWholeBatchAtEntry` + `testBatchPurchaseRejectsNonKeeperCaller` — the batch-level rngLocked (RngLocked) and gameOver (E) pre-checks fire ONCE at entry (single revert, nothing purchased), and a non-AF_KING caller is rejected (E).

### Task 2 — reentrancy rollback + cancel un-brickable (CrankNonBrick.t.sol)
- `testReentrantWithdrawCannotDoubleSpend` — a malicious pool-holder whose receive() re-enters withdraw and BUBBLES the inner InsufficientBalance: the outer `.call` sees failure → EthSendFailed → the whole withdraw reverts and unwinds; the attacker extracts NOTHING (pool fully restored).
- `testReentrantWithdrawSwallowedYieldsSinglePayout` — the SWALLOWING variant: the outer withdraw completes exactly ONE payout; the re-entry adds nothing (the per-frame CEI debit can never be replayed for a second payout).
- `testCancelThenWithdrawAlwaysSucceeds` + `testFuzz_CancelWithdrawNeverStrandsEth` — setDailyQuantity(0) tombstones the sub un-brickably, and afterward the full _poolOf ETH is withdrawable (CEI withdraw, partial-then-remainder fuzz drains the whole pool with no stranded ETH).

### Task 3 — SUB/PROTO acceptance (AfKingSubscription.t.sol)
- `testRenewalPassHolderFreeExtendNoCharge` vs `testRenewalNoPassChargedViaBurnForKeeper` — SUB-01 pass-OR-pay: a deity-pass holder free-extends at the day-31 renewal (SubscriptionExtendedFree, no burn, windowPaid cleared); a no-pass sub is charged via burnForKeeper (BurnieAutoExtracted, exactly `cost` burned, windowPaid set).
- `testRenewalShortfallBurnsNothingAndAutoPauses` + `testRenewalExactlyAtCostFullBurn` — PROTO-02 / SUB-08 all-or-nothing: spendable < cost burns NOTHING, returns 0, auto-pauses the sub (dailyQuantity 0, removed from set, SubscriptionExpired) WITHOUT reverting the sweep (a co-running healthy sub still renews); spendable == cost is a full burn (the `>=` predicate boundary).
- `testSweepEmitsExactlyOneGasPeggedBounty` — REW-02: a 2-buy sweep emits EXACTLY ONE creditFlip to the sweeper, equal to `batchLen * (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * stallMult) / mp` (per-player flat, never per-item measured gas).
- `testZeroBuySweepRevertsNoSubscribersSwept` + `testSweepZeroMaxCountRevertsEmptySweep` — the zero-buy tail revert and the maxCount==0 pre-loop guard.

## Task Commits
1. **Tasks 1 + 2: SAFE-02 non-brick (CrankNonBrick.t.sol)** — `47b9d031` (test)
2. **Task 3: SUB/PROTO acceptance (AfKingSubscription.t.sol)** — `15ebe778` (test)

**Plan metadata:** (this commit)

## Files Created
- `test/fuzz/CrankNonBrick.t.sol` (707 LoC, 12 tests) — SAFE-02 non-brick for crankBets/crankBoxes/batchPurchase (skip-and-continue, slice-refund, batch-level pre-check, reentrancy rollback, cancel un-brickable). Contains `batchPurchase`.
- `test/fuzz/AfKingSubscription.t.sol` (376 LoC, 7 tests) — SUB-01 pass-OR-pay, PROTO-02/SUB-08 burnForKeeper all-or-nothing, REW-02 gas-pegged bounty. Contains `burnForKeeper`.

## Key Empirical Findings
- The crank/bounty reward credits `msg.sender` (the caller/sweeper), NOT the work owner — owner winnings credit the owner separately. Non-owning callers isolate the pure reward in their stake delta.
- `mintPrice()` in the fixture state == 0.01 ETH (level 1); `_subCost()` == 5e14 BURNIE wei; per-player bounty (1x) == 8.85e13 BURNIE wei.
- The fixture's day-1 timestamp lands 63 min into the keeper-local day → the sweep stall multiplier is **4x** (≥ 1 hour), not 1x; the test mirrors the contract's elapsed-time formula rather than hardcoding.
- VAULT/SDGNRS carry the permanent deity bit (game ctor :213-214) and the SUB-09 self-subscribe, but do NOT approve AfKing as operator at deploy — so a deploy-time sweep would skip them at the NotApproved gate (reason 5). The bounty/renewal tests use fresh keeper-approved subs.

## Deviations from Plan

### Boundary clarifications (no Rule 1-4 auto-fixes; no architectural changes)

**1. [crankBoxes "one creditFlip" assertion reframed to a caller-stake-delta assertion]**
- **Found during:** Task 1.
- **Issue:** The PLAN's box behavior implies a single crank-reward creditFlip, but a WINNING lootbox emits an additional winnings creditFlip to the box OWNER, so a naive `count == 1` fails (2 emissions).
- **Resolution:** Asserted the crank reward via the CALLER's coinflip stake delta (the caller owns no box, so its delta is the pure crank reward) — strictly more faithful to "reward over successes only" than an emission count. crankBets keeps the count==1 assertion (losing bets pay no winnings, so the sole emission is the crank reward).

**2. [Reentrancy modeled with two attacker strategies instead of one]**
- **Found during:** Task 2.
- **Issue:** The initial single-variant attacker swallowed the inner revert, so the outer withdraw legitimately completed one payout — which is correct behavior, not a double-spend, making the "pool fully restored" assertion wrong for that strategy.
- **Resolution:** Split into a BUBBLING variant (whole call reverts, attacker gets nothing) and a SWALLOWING variant (single payout, no second). Both prove the at-most-once property under either attacker choice — a stronger proof of "no replayable batch-debit."

**3. [Sweep bounty expected-value uses the live stall multiplier]**
- **Found during:** Task 3.
- **Issue:** Hardcoded a 1x multiplier; the fixture's timestamp yields 4x.
- **Resolution:** Mirrored the sweep's exact stall-multiplier formula (day-start = today*1days+82620) in-test. The assertion now tracks the contract's pegging at any fixture timestamp.

---
**Total deviations:** 0 auto-fixes (no Rule 1-4); 3 boundary clarifications (all test-harness, none touch production contracts).
**Impact on plan:** None negative. All five must-have truths (non-brick triad, slice-refund, cancel un-brickable, reentrancy no-double-buy, subscription correctness) are proven; the reframed assertions are more faithful to the requirements than the literal first drafts.

## Issues Encountered
- A first-pass crankBets/crankBoxes assertion read the reward on the work OWNER and reported 0 — root-caused to the reward crediting the CALLER. Fixed by reading the caller's stake delta. No production issue: the call-graph (reward → msg.sender) is correct and intended (REW-04 no-caller-restriction).

## User Setup Required
None — no external service configuration required.

## Known Stubs
None introduced. Both suites exercise the live frozen surface (real AfKing keeper, real DegenerusGame crank/batchPurchase, real BurnieCoin.burnForKeeper, real BurnieCoinflip.creditFlip). Slot writes are limited to the established RNG-word injection, the lootboxEth poison, the _subOf renewal/swept-day forcing, the deity-bit grant, and the boundary-precise BURNIE balance — standard state-seeding, not stubbed behavior. The `_setBurnieBalance` direct write leaves BurnieCoin.totalSupply unsynced from the seeded balance (a harness-only invariant break used solely for the shortfall/at-cost boundary tests); the deploy's 2M BURNIE supply guarantees no _burn underflow.

## Threat Flags
None — this plan introduces no new network endpoint, auth path, file-access pattern, or schema change. The threat register's T-318-03-01 (one poisoned item bricks the batch), T-318-03-02 (double-buy via reentrant sweep/cancel), T-318-03-03 (partial burnForKeeper half-paid sub), and T-318-03-04 (cancel blocked by a reverting downstream) are all `mitigate` dispositions and now empirically asserted; T-318-03-SC (no package installs) holds — zero installs.

## Next Phase Readiness
- SAFE-02 is empirically proven across all three permissionless entries plus the reentrancy/cancel liveness floor; SUB-01/PROTO-02/SUB-08/REW-02 acceptance is covered.
- The non-brick poison-construction patterns (lootboxEth-zeroed box, sub-floor batchPurchase slice, slot-forced renewal) and the caller-stake-delta reward isolation are reusable by the remaining Wave-2+ plans (318-04..06).

## Self-Check: PASSED
- `test/fuzz/CrankNonBrick.t.sol` present on disk — FOUND.
- `test/fuzz/AfKingSubscription.t.sol` present on disk — FOUND.
- Task commits `47b9d031` + `15ebe778` exist in git log — FOUND.
- Artifact `contains` checks: `batchPurchase` present in CrankNonBrick.t.sol — FOUND; `burnForKeeper` present in AfKingSubscription.t.sol — FOUND.
- Both suites green under the default profile (patch → forge → git-restore): CrankNonBrick 12/12, AfKingSubscription 7/7 (19 total, 0 failed).
- `git diff --name-only -- contracts/` empty after the patch/restore cycle — no production-contract mutation.

---
*Phase: 318-tst-subscription-crank-correctness-removal-proofs-tst*
*Plan: 03*
*Completed: 2026-05-23*
