---
phase: 380-foundation-test-fix-green-baseline
reviewed: 2026-06-07T00:00:00Z
depth: standard
files_reviewed: 42
files_reviewed_list:
  - test/edge/GameOver.test.js
  - test/edge/LootboxAutoResolveRegression.test.js
  - test/fuzz/ActivityScoreStreakGas.t.sol
  - test/fuzz/AffiliateDgnrsClaim.t.sol
  - test/fuzz/AfKingSubscription.t.sol
  - test/fuzz/CoverageGap222.t.sol
  - test/fuzz/DegeneretteFreezeResolution.t.sol
  - test/fuzz/DegeneretteResolveRepeg.t.sol
  - test/fuzz/GameOverPathIsolation.t.sol
  - test/fuzz/handlers/DegeneretteHandler.sol
  - test/fuzz/helpers/SolvencyObligations.sol
  - test/fuzz/invariant/DegeneretteBet.inv.t.sol
  - test/fuzz/KeeperFaucetResistance.t.sol
  - test/fuzz/KeeperNonBrick.t.sol
  - test/fuzz/KeeperRewardRoutingSameResults.t.sol
  - test/fuzz/KeeperRouterOneCategory.t.sol
  - test/fuzz/LootboxBoonCoexistence.t.sol
  - test/fuzz/PresaleBoxDrain.t.sol
  - test/fuzz/PrizePoolFreeze.t.sol
  - test/fuzz/QueueDoubleBuffer.t.sol
  - test/fuzz/RngIndexDrainBinding.t.sol
  - test/fuzz/RngLockDeterminism.t.sol
  - test/fuzz/StallResilience.t.sol
  - test/fuzz/TicketEdgeCases.t.sol
  - test/fuzz/TicketLifecycle.t.sol
  - test/fuzz/TicketRouting.t.sol
  - test/fuzz/V55FreezeDeterminism.t.sol
  - test/fuzz/V55RevertFreeEvCap.t.sol
  - test/fuzz/V56FreezeSolvency.t.sol
  - test/fuzz/V56SecUnmanipulable.t.sol
  - test/fuzz/V56SubHardening.t.sol
  - test/fuzz/VRFCore.t.sol
  - test/fuzz/VRFLifecycle.t.sol
  - test/fuzz/VRFPathCoverage.t.sol
  - test/fuzz/VRFStallEdgeCases.t.sol
  - test/gas/AdvanceStageWorstCaseGas.t.sol
  - test/gas/KeeperLeversAndPacking.t.sol
  - test/unit/EventSurfaceUnification.test.js
  - test/unit/LootboxAutoResolveSilentColdBust.test.js
  - test/unit/LootboxWholeBurnieFloor.test.js
  - test/unit/LootboxWholeTicket.test.js
  - test/unit/SecurityEconHardening.test.js
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 380: Code Review Report

**Reviewed:** 2026-06-07
**Depth:** standard
**Files Reviewed:** 42
**Status:** issues_found

## Summary

Phase 380 is a TEST-ONLY foundation phase that repaired stale test fixtures against the
FROZEN contract subject `c4d48008` (`contracts/` byte-untouched; verified clean before and
after this review). I reviewed the diff `33601f66..HEAD` for each of the 42 files, prioritizing
by the audit-oracle risk model: assertion-weakening that masks bugs, vacuous tests, over-broad
skips, suspect re-derived values, and test-quality.

**The overwhelming majority of the diff is sound.** I independently re-derived the authoritative
storage layout via `forge inspect DegenerusGame storageLayout` and confirmed EVERY slot/offset
recalibration is correct against the frozen subject (boonPacked 58, lootboxRngPacked 36,
lootboxRngWordByIndex 37, lootboxPurchasePacked 38, lootboxEthBase 22, presaleBoxDgnrsPoolStart 32,
degeneretteBets 43, degeneretteBetNonce 44, mintPacked_ 9, rngWordByDay 10, _subOf 62,
_subscribers 64, _subscriberIndex 65, prizePoolPendingPacked 11; slot-0 offsets rngLockedFlag 19/
bit 152, gameOver 21/bit 168, ticketsFullyProcessed 24, ticketWriteSlot 26, prizePoolFrozen 27/
bit 216). All event-signature recalibrations (CoinflipStakeUpdated / QuestStreakBonusAwarded /
SubscriptionExtendedFree uint32→uint24 day; LootBoxOpened 8→7 args with `day` dropped;
TraitsGenerated 6→3 args) were verified against the frozen contract source. All re-derived expected
values (VRFLifecycle 200→480 bootstrap buys, PrizePoolFreeze 1% freeze-seed, V56SubHardening churn
100→0, affiliate below-min zero-score, CoverageGap222 governance surface, gap-backfill uint24 day
preimage) are internally consistent and traceable to the frozen logic.

The two non-vacuity fixes (DegeneretteBet invariant + handler seeding; RngLockDeterminism sDGNRS
seed) genuinely STRENGTHEN their tests — the DegeneretteBet fix adds an `afterInvariant`
`assertGt(ghost_betsPlaced, 0)` guard that fails loudly if the seeding ever regresses to the old
vacuous pass. All six finding-candidate skips (FC1–FC6) are narrowly scoped to a single test each,
annotated with their DEF-FC id, and grounded in frozen-source behavior I verified (score-keyed DGNRS
award, _wwxrpBonusBucket uplift, drain-on-cancel affiliateBase, slimmed TraitsGenerated event,
mid-day buffer-freeze RngNotReady, mid-day-pending gap backfill). Routing them to the council rather
than aligning the test is the correct disposition.

Two issues warrant fixing: one genuinely vacuous test left un-skipped (its FC5 sibling WAS skipped),
and a deity-refund oracle weakened to a one-sided lower bound that can no longer catch an over-refund
of a solvency-relevant capped payout.

## Warnings

### WR-01: `testBindingConsistencyMidDayCrossDay` passes vacuously — stale event topic makes the binding assertion unreachable

**File:** `test/fuzz/RngIndexDrainBinding.t.sol:185` (vacuous early-return at `:216-220`; stale topic at `:24-25`)

**Issue:** This test's sibling `testBindingConsistencyDailyDrain` (`:139`) was correctly
vm.skip-routed under DEF-380-04-FC5 because the frozen `TraitsGenerated` event was slimmed to
3 args (`address indexed player, uint256 baseKey, uint32 take`) and no longer carries the `entropy`
field the RNG-binding assertion decodes. But `testBindingConsistencyMidDayCrossDay` was left
un-skipped and now passes **vacuously**:

- `TOPIC_TRAITS_GENERATED` (`:24-25`) is still the stale 6-arg topic
  `keccak256("TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)")` =
  `0x5e96bf2d...`. The frozen event's real topic0 is
  `keccak256("TraitsGenerated(address,uint256,uint32)")` = `0x279edf1c...` (verified — the two
  hashes differ completely).
- `_capturedEntropies` (`:86`) matches logs against the stale topic, so it ALWAYS returns a
  zero-length array (no real log can match the wrong topic0).
- `entropies.length == 0` is therefore always true, the function hits the early `return` at `:219`,
  and the binding assertions at `:222-235` (`idxAfterAdvance >= idxBeforeAdvance+1`, `slotWord != 0`,
  `entropies[i] == slotWord`) NEVER execute. The test is green while proving nothing.

The FC5 `@dev` block itself acknowledges this ("The sibling testBindingConsistencyMidDayCrossDay
passes only because it vacuously returns when entropies.length == 0") but takes no action — so a
test that exercises no assertion contributes a false green to the "0 failures" baseline, masking the
lost RNG-binding observability on the mid-day→cross-day edge.

**Fix:** Treat the sibling identically to its FC5 counterpart — add `vm.skip(true); // DEF-380-04-FC5`
at the top of `testBindingConsistencyMidDayCrossDay` (same removed-field root cause), OR, if it must
stay live, add a hard non-vacuity guard so a perpetually-empty capture FAILS instead of returning:
```solidity
function testBindingConsistencyMidDayCrossDay() public {
    vm.skip(true); // DEF-380-04-FC5 — same removed-entropy-field cause as the daily-drain sibling; council adjudicates
    ...
}
```
Either way, do NOT leave a test whose every assertion is gated behind an always-true
`entropies.length == 0` early-return counting toward the green baseline.

### WR-02: Deity early-gameover refund assertion weakened to a one-sided `gte(20 ETH)` — cannot catch an over-refund of the capped solvency-relevant payout

**File:** `test/edge/GameOver.test.js:260` and `:284-285`; `test/unit/SecurityEconHardening.test.js:240-241`

**Issue:** The deity early-gameover refund is `min(deityPassPricePaid[owner], 20 ETH)` per owner,
budget-capped FIFO (verified at `GameOverModule:111-118`). For a standard 24/25-ETH pass the cap
binds, so the refund is **deterministically exactly 20 ETH**. The recalibration replaced the prior
"flat 20 ETH" exact-value intent with a pure lower bound:
- `GameOver.test.js:260`: `expect(claimable).to.be.gte(eth(20))`
- `SecurityEconHardening.test.js:240-241`: `expect(aliceClaimAfter - aliceClaimBefore).to.be.gte(eth(20))`

The annotations justify the relaxation as "terminal jackpot may add more". But a one-sided `gte(20)`
can no longer distinguish "cap correctly applied → refund 20" from "cap BROKEN → refund 24/25 (the
full pricePaid) + jackpot". A regression that removed the `min(pricePaid, 20)` clamp at
`GameOverModule:113-114` would still satisfy `gte(20)` and pass silently. Because the deity refund
draws directly from `claimablePool` (`:120,:133`), an uncapped over-refund is a solvency / over-payout
concern, exactly the class an audit oracle should catch — and the exact expected value here is a
known constant (20 ETH), so an upper bound was feasible.

(Mitigating context, not a reason to skip the fix: per `deferred-items.md` DEF-380-02-01 both suites
are among the 117 carried JS failures whose `triggerGameOverAtLevel0` helper does not yet reach
`gameOver()==true` at c4d48008, and the forge by-name suite is the PRIMARY oracle, so these two are
not presently certifying a false green. The weakened oracle is still a real coverage defect to fix
when the JS gameover-drive harness is repaired.)

**Fix:** Isolate the refund-attributable delta from the jackpot and assert it exactly. E.g. capture
`claimableWinningsOf` immediately before and after the gameover-latch refund credit and assert the
refund portion `=== eth(20)` (the cap value), or bound it two-sided
(`expect(delta).to.be.gte(eth(20))` AND a tight upper bound that the jackpot share cannot legitimately
exceed). At minimum, add an upper-bound assertion that fails if the deity credit alone exceeds the
20-ETH cap, so a removed-clamp regression is caught:
```js
// deity refund is capped at 20 ETH; only the (separately-accounted) jackpot may add more
expect(deityRefundDelta).to.equal(eth(20)); // not gte — the cap is a known exact value
```

## Info

### IN-01: Stale slot/topic constants left in `RngIndexDrainBinding.t.sol` (latent, masked by the skip + vacuity)

**File:** `test/fuzz/RngIndexDrainBinding.t.sol:19-25`

**Issue:** Beyond the topic in WR-01, this file still carries pre-recalibration storage-slot
constants that were never updated to the frozen layout:
- `SLOT_LOOTBOX_MAPPING = 38` (`:19`) — `lootboxRngWordByIndex` is authoritatively slot **37** at
  c4d48008 (confirmed via `forge inspect`; the file's own FC5 `@dev` even cites slot 37).
- `SLOT_LR_INDEX = 37` (`:21`) — `lootboxRngPacked` is authoritatively slot **36**.

These are latent because the only consumers (`_lootboxWord`, `_lrIndex`) are reached solely from the
now-skipped `testBindingConsistencyDailyDrain` and the vacuously-returning sibling. They would
produce wrong reads if either test were re-activated.

**Fix:** When addressing WR-01, also correct `SLOT_LOOTBOX_MAPPING → 37` and `SLOT_LR_INDEX → 36`
(and the topic constant to the 3-arg form) so the file is layout-accurate even while skipped — or
delete the now-dead helpers if both tests stay skipped.

### IN-02: `AdvanceStageWorstCaseGas` couples a PASS/FAIL `assertEq` to a hardcoded cross-harness gas constant

**File:** `test/gas/AdvanceStageWorstCaseGas.t.sol:402` (used at `:421`)

**Issue:** `allEvictStageGas = 13_603_709` is a magic constant copied from a different harness
(`V56AfkingGasMarginal`, "NOT re-measured" per `:384,:401`). It is then used in a load-bearing
equality assertion at `:421` (`assertEq(binding, allEvictStageGas, "the BINDING stage is the
all-evict subscriber STAGE (2)")`). If the referenced value ever drifts from the real
V56AfkingGasMarginal measurement (compiler change, refactor), this test asserts a stale fiction; and
if the measured `jackpotGas`/`ticketGas` ever exceeded `13,603,709`, the `assertEq` would flip the
"binding stage" conclusion. (Out of v1 performance scope; flagged as a test-quality coupling, not a
correctness defect — the unconditional EIP-cap assertions at `:215,:302,:332,:419` are the
load-bearing safety checks and are sound.)

**Fix:** Either drop the cross-harness `assertEq` (`:421`) and keep only the `assertLt(binding, EIP_CAP)`
ceiling check, or annotate the constant with the exact source commit/test it was captured from and a
note that it must be re-synced when V56AfkingGasMarginal changes.

### IN-03: Gas probes contribute green with no / conditionally-skipped assertions

**File:** `test/fuzz/ActivityScoreStreakGas.t.sol:19-39`; `test/gas/AdvanceStageWorstCaseGas.t.sol:266-271,:364-374`

**Issue:** `ActivityScoreStreakGas::test_gas_streakReads` has NO assertions (only `emit
log_named_uint`) — it always passes and proves nothing, yet counts as a passing test in the baseline.
In `AdvanceStageWorstCaseGas`, the per-winner / per-trait marginal assertions are gated behind
`if (gasHi > gasLo)` (`:266,:364`); if that condition were ever false the marginal bound is silently
skipped. These are explicitly-labeled gas probes (not correctness oracles) and the primary EIP-cap
assertions are unconditional, so the impact is minor.

**Fix:** For the pure-probe, either mark it clearly as a non-asserting measurement (e.g. a name suffix
`_probe` and exclude it from the regression count), or add a trivial sanity assertion (e.g.
`assertGt(effGas, 0)`). For the marginal `if` guards, add an `else` that asserts the guard's
precondition held (so a degenerate measurement fails rather than silently passing).

---

_Reviewed: 2026-06-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
