---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
reviewed: 2026-05-26T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - test/fuzz/BurnieTombstone.t.sol
  - test/fuzz/DegeneretteHeroScore.t.sol
  - test/fuzz/FarFutureSalvageSwap.t.sol
  - test/fuzz/PresaleBoxDrain.t.sol
  - test/fuzz/RedemptionStethFallback.t.sol
  - test/fuzz/handlers/RedemptionHandler.sol
  - test/invariant/RedemptionAccounting.t.sol
  - test/stat/DegeneretteBonusEv.test.js
  - test/stat/DegenerettePerNEvExactness.test.js
findings:
  critical: 0
  warning: 7
  info: 6
  total: 13
status: issues_found
---

# Phase 327: Code Review Report

**Reviewed:** 2026-05-26
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

These are test-authoring artifacts for a FROZEN Solidity subject (zero `contracts/*.sol` edits).
The review focused on TEST QUALITY and FALSE-CONFIDENCE risk: vacuous/tautological assertions,
reach-guards on the branch each test claims to exercise, byte-reproduce gate integrity,
determinism of batched-vs-per-bet comparisons, and correctly-oriented no-arb/solvency inequalities.

I cross-checked every load-bearing assertion against the actual contract source:

- **Byte-reproduce gate (`DegenerettePerNEvExactness.test.js`) is genuine.** It `spawnSync`s
  `derive_5_tables.py`, status-checks before parsing, parses the `FINAL PASTE-READY CONSTANTS`
  block by regex (never hand-types), reads the contract source, and diffs all 20 constants.
  I ran the generator and confirmed the output format matches the regex and that the S9 values
  the gate treats as FINAL (`10756411`, `12583037`, ...) are the same ones hardcoded in the
  `.sol` HERO test. The RED-with-diff against the intentional Phase-326 placeholders is the
  expected, in-scope outcome — the gate is NOT weakened to hide it. Both stat files are wired
  into the `test:stat` npm script, so the gate actually runs.
- **No-arb / solvency inequalities are correctly oriented.** `_jitterMult`, `_farFutureFractionBps`,
  the `previewSellFarFutureTickets` return tuple, the `len > 32` array bound, the
  `claimable[SDGNRS] >= totalBudget + 1 ether` ETH floor, and the swap-pop `q[idx] == player`
  full-sell-out verify all match source. The d6 ceiling = 1500 × 11000/10000 = 1650 bps = 16.5%
  arithmetic is correct, and the `assertLt(fracBps, ACQUISITION_FLOOR_BPS)` direction is right.
- **Reward / score formulas mirror source exactly.** The presale-box reward divisor (400), the
  Degenerette `_score` (S = A + 2H, max 9), the `_roiBpsFromScore` curve mirror, the BURNIE
  no-bonus isolation for the S9 anchor, and the `_awardDegeneretteDgnrs` pool-source isolation
  (Reward vs Lootbox/Dgnrs) all check out.

No BLOCKER-class defects (assertions that would pass against a broken contract in a way that
masks a real bug) were found. The findings below are false-confidence and robustness issues that
weaken the *strength* of several proofs without producing wrong PASS/FAIL on the current subject.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Tautological clamp assertion in PFIX-03 clamp test

**File:** `test/fuzz/PresaleBoxDrain.t.sol:260`
**Issue:** `assertLe(drew, poolBefore, "no per-box draw exceeds live pool (clamp)")` where
`drew = poolBefore - _poolBal()`. Because `_poolBal()` is a non-negative balance, `drew <= poolBefore`
is true *by construction of the subtraction* — it can never fail. If the contract clamp were broken,
the failure mode would be a revert (underflow inside `transferFromPool`'s `unchecked` block can't
happen because it pre-clamps; the real break would be an over-draw that reverts elsewhere), not a
`drew > poolBefore` reading this assertion could catch. The assertion adds no signal.
**Fix:** Assert against the FROZEN `poolStart` and the formula instead, e.g. capture the
contract's intended per-box reward and assert `drew == min(perBoxReward, poolBefore)`:
```solidity
uint256 expectClamped = perBoxReward < poolBefore ? perBoxReward : poolBefore;
assertEq(drew, expectClamped, "per-box draw == min(formula, live pool) (clamp engaged)");
```
The load-bearing assertions in this test (no-revert on close, `poolAfterClose <= 1`) do carry weight;
this one line should be made non-vacuous so the clamp itself is positively proven.

### WR-02: Bare `vm.expectRevert()` cannot distinguish the gate under test from an unrelated revert

**File:** `test/fuzz/FarFutureSalvageSwap.t.sol:424, 455, 485, 495, 589`; `test/fuzz/RedemptionStethFallback.t.sol:363`
**Issue:** Several reverts are asserted with a selector-less `vm.expectRevert()`. The swap path
reverts everything with a single generic `error E()`, so a typed expect is not fully expressible —
but a bare expect passes on ANY revert, including the test reverting for the WRONG reason (e.g. the
ticket-floor test at :424 expects a `totalBudget < oneTicketWei` revert, but would equally pass if
the call reverted earlier on the ETH-floor gate, an array OOB, or OOG). The ETH-floor (:455) and
ticket-floor (:424) tests are the most exposed because a too-small/under-funded bundle can revert at
multiple `E()` gates, so the test could be green while exercising a different gate than intended.
**Fix:** Pin the revert to the specific error and, where the gate is `E()`-generic, add a positive
pre-assert that *only* the intended gate can fire (the test for :424 already asserts
`budgetSmall < oneTicketWei` AND should additionally assert `claimable[SDGNRS] >= budgetSmall + 1 ether`
so the ETH-floor gate is provably satisfied and only the ticket-floor gate can revert):
```solidity
vm.expectRevert(DegenerusGame.E.selector); // pin the generic error explicitly
// and assert the OTHER gates are satisfied so only the intended one can fire
assertGe(game.claimableWinningsOf(ContractAddresses.SDGNRS), budgetSmall + 1 ether,
    "fixture: ETH floor must be satisfied so ONLY the ticket floor can revert");
```

### WR-03: `test_RFALL05_FailClosed_NeitherLegCovers` bare expectRevert can be satisfied by the wrong gate

**File:** `test/fuzz/RedemptionStethFallback.t.sol:362-364`
**Issue:** This is the load-bearing fail-closed proof (T-327-02-FC3). It seeds `claimable[SDGNRS] = 100 ether`
purely to push `maxIncrement > 0`, drains game ETH to 0, and leaves sDGNRS stETH = 0, then
`vm.expectRevert()` (no selector). Because `burn()` traverses a long call chain (supply-cap clamp,
per-player EV cap, single-pool sentinel, then `pullRedemptionReserve`), a bare expect would pass if
the burn reverted for any of those *other* reasons before reaching the
"neither pure leg covers" branch — masking a fail-closed that never actually fired. The post-revert
no-leak assertions (pool/claimable/pending/supply unchanged) do not distinguish *which* revert occurred.
**Fix:** Pin the specific revert selector that `pullRedemptionReserve` raises on the neither-leg path
(the contract uses `E()` — pin it: `vm.expectRevert(DegenerusGame.E.selector)`), and add a positive
guard that the *other* burn-path gates are all satisfied for this fixture (supply cap, per-player EV
cap, sentinel == 0) so the only reachable revert is the coverage gate.

### WR-04: stETH-leg "branch proof" reach-guards are necessary but not sufficient

**File:** `test/fuzz/RedemptionStethFallback.t.sol:236-259, 324-327, 418-420`
**Issue:** The stETH-leg tests prove the ETH leg did NOT run (claimable[SDGNRS]/claimablePool/game-ETH
UNCHANGED) and that `pendingRedemptionEthValue` incremented. That correctly excludes the ETH leg, but
it does not positively prove the *stETH* leg ran versus some third path that also leaves the ledger
untouched while bumping `pending` (e.g. a future code path that reserves with no asset move). Today
the contract has exactly two legs so "not ETH ⇒ stETH" holds, but the proof is coupled to that
two-leg assumption rather than asserting a stETH-specific side effect at submit. The claim-time
`assertGt(stethPaid, 0)` in (b) is the only positive stETH evidence and it is downstream of the claim,
not the submit.
**Fix:** Add a submit-time positive assertion keyed to the stETH leg specifically — e.g. assert the
contract recorded the reserved-asset selector (if exposed) or that sDGNRS's stETH balance is the only
backing term that moved across the eventual claim. At minimum, document the two-leg exclusivity as an
explicit assumption the test depends on (so a future third leg invalidates the inference loudly).

### WR-05: HERO score/payout proofs depend on a hand-maintained ROI-curve mirror that can silently drift

**File:** `test/fuzz/DegeneretteHeroScore.t.sol:657-695`
**Issue:** `test_HERO_S9EqualsOldM8Jackpot` anchors the FINAL S9 constants by recovering `basePayout`
from the observed payout, which requires the exact `roiBps`. That `roiBps` is recovered by re-reading
the packed activity score from storage and re-implementing `_roiBpsFromScore` in the test
(`_roiBpsFromScore`, lines 677-695) plus seven hardcoded curve constants
(`ACTIVITY_SCORE_*_BPS`, `ROI_*_BPS`). I verified these are byte-identical to the contract today, but
this is a duplicated-logic mirror: if the contract's ROI curve is ever recalibrated, the test mirror
will silently diverge and either falsely PASS (if the divergence cancels) or falsely FAIL. The same
applies to the storage shift `FT_ACTIVITY_SHIFT = 220` and `DEGENERETTE_BETS_SLOT = 45` hardcodes.
**Fix:** Prefer reading `roiBps` from an observable contract surface rather than re-deriving it, or
add a guard test that asserts the mirror against a known (score → roiBps) pair the contract also
exposes, so a curve change forces a mirror update instead of silent drift. At minimum, pin the
storage slot via `forge inspect`-derived constants with a comment tying them to the layout dump.

### WR-06: HERO no-leak non-vacuity guard re-derives the score off-chain instead of reading the contract

**File:** `test/fuzz/DegeneretteHeroScore.t.sol:446-448, 498-512`
**Issue:** `test_HERO06_DailyHeroJackpotUnaffected_NoLeak` asserts the two runs produced DIFFERENT
resolution scores (the differential that makes the no-leak proof meaningful) via `_scoreOfTicketUnder`,
which re-implements `_score` (S = A + 2H) entirely in the test. If the off-chain mirror is wrong (or
drifts from the contract), the non-vacuity guard `assertTrue(sLow != sHigh)` could pass while the
on-chain scores were actually identical, hollowing out the no-leak differential without any test
failing. The proof's strength rests on a mirror the test never cross-checks against the contract's
emitted score.
**Fix:** Capture the actual on-chain scores from the `FullTicketResult.matches` field emitted during
each run (the file already has `_firstSpinScoreAndPayout` for exactly this) and assert THOSE differ,
rather than recomputing the score off-chain:
```solidity
// during each run, read the emitted matches for spin 0 and assert run-LOW != run-HIGH
assertTrue(onChainScoreLow != onChainScoreHigh, "non-vacuity: on-chain scores must differ");
```

### WR-07: RedemptionHandler `action_burnOnPreviousDay` documents an unreachable success path but never asserts it stays unreachable

**File:** `test/fuzz/handlers/RedemptionHandler.sol:574-579`
**Issue:** The sentinel exerciser calls `try sdgnrs.burn(1e18) { /* should be unreachable */ } catch {}`
and the comment states "If reached, the invariant fn will see ... change unexpectedly." But the
handler does NOT record that the success branch was hit (no ghost flag), and there is no invariant
that specifically fails if `burn` *succeeds* on a stuck prior day. The negative-coverage claim
(INV-08/INV-13 reachability) is therefore only indirectly enforced — if `PriorDayUnresolved` stopped
firing, the burn would succeed, ghosts would be left intentionally unupdated, and INV-04/INV-07 might
or might not catch the resulting drift depending on which day's slot moved. The "the invariant catches
it" assumption is not pinned by a dedicated assertion.
**Fix:** Set a ghost flag in the success branch (`ghost_priorDaySucceeded++`) and add an invariant
`assertEq(handler.ghost_priorDaySucceeded(), 0, "stuck-day burn must always revert")` so the
unreachability is asserted directly rather than inferred from downstream conservation invariants.

## Info

### IN-01: Dead cap in HERO score mirror

**File:** `test/fuzz/DegeneretteHeroScore.t.sol:511`
**Issue:** `_scoreOfTicketUnder` ends with `if (s > 9) s = 9;`. The contract `_score` never caps
(max achievable is exactly 9: 4 colors + 3 ordinary symbols + 2 hero), so this branch is dead and
slightly misrepresents the contract (which has no cap). Harmless but misleading.
**Fix:** Remove the dead cap, or comment that the contract relies on the structural max of 9 rather
than an explicit clamp.

### IN-02: Unused local / silenced-warning pattern

**File:** `test/fuzz/FarFutureSalvageSwap.t.sol:434, 440`
**Issue:** `uint32 nearBefore = game.getPlayerPurchases(seller);` is captured then discarded with
`nearBefore; // silence unused`. The variable contributes nothing to the proof (the comment admits
"presence proven by no-revert"). Dead scaffolding.
**Fix:** Either assert on the near-routing delta (`getPlayerPurchases` after > before by the minted
ticket count) to actually prove the ticket leg landed, or drop the capture entirely.

### IN-03: `_withN` helper is dead code

**File:** `test/fuzz/DegeneretteHeroScore.t.sol:821-829`
**Issue:** `_withN` is documented as "kept for API symmetry" and is not called anywhere in the file.
Dead helper.
**Fix:** Remove it; the file already has `_countGoldQuadrants` for the read-back path.

### IN-04: Magic VRF-derived seed-search bounds are unexplained

**File:** `test/fuzz/FarFutureSalvageSwap.t.sol:152, 233, 260`; `test/fuzz/PresaleBoxDrain.t.sol:109, 291`
**Issue:** Several brute-force loops use bare magic bounds (`200_000`, `50_000`, `5000`, `20000`) for
seed searches. If a future jitter/outcome domain change makes the target unreachable within the bound,
the search returns `found == false` and the `assertTrue(found, ...)` fails with a confusing message
rather than a clear "search band too small." Most call sites do assert `found`, which is good; the
`PresaleBoxDrain._wordForDgnrs/_wordForBand` use `revert("no ... found")` which is fine. Just opaque.
**Fix:** Hoist the bounds to named constants with a comment on the expected hit probability
(jitter ceiling is 1/4001 per draw, so 200k iterations ⇒ ~1−(4000/4001)^200000 ≈ certain).

### IN-05: `test_SWAP09_SolvencyAcrossSwap` solvency assertion is loose relative to its own narrative

**File:** `test/fuzz/FarFutureSalvageSwap.t.sol:391-397`
**Issue:** The NatSpec claims claimablePool "must be UNCHANGED or DECREASED ... never increased above
backing," but the test only asserts `assertLe(poolAfter, backingAfter)` and `sellerClaimAfter >
sellerClaimBefore`. It never asserts the pool actually stayed flat/decreased relative to `poolBefore`,
so a (hypothetical) bug that increased the pool while still keeping it under backing would pass.
**Fix:** Add `assertLe(poolAfter, poolBefore, "swap must not increase claimablePool")` to match the
stated invariant.

### IN-06: INV-03 is an intentional documented no-op (acceptable, noting for completeness)

**File:** `test/invariant/RedemptionAccounting.t.sol:158-162`
**Issue:** `invariant_INV_03_BurnieConservationExact` asserts only `assertTrue(address(sdgnrs) != address(0))`
— a vacuous always-true. This is *intentional and documented* (the BURNIE reserve apparatus was deleted
in v47; the row is retained for the attestation matrix). Flagging only so the structural-findings
substrate and downstream consumers do not mistake it for an accidental vacuous invariant. No change
required beyond the existing NatSpec; consider renaming to `invariant_INV_03_BurnieReserveRemoved_NoOp`
to make the intent unmistakable at the call site.

---

_Reviewed: 2026-05-26_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
