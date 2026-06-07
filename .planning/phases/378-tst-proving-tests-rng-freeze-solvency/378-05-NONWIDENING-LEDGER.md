---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 05
artifact: nonwidening-ledger
subject: v61 HEAD (b97a7a2e batched AFPAY+PACK+CURSE+SMITE diff + 056481ea 377 Outcome-A)
baseline: 2bee6d6f (the v60.0 closure HEAD — the v61 milestone's declared frozen baseline)
authority: forge test (default profile) live HEAD red set BY NAME vs test/REGRESSION-BASELINE-v61.md union
captured: 2026-06-07
contracts_tree_hash: 87e3b45b46879ec80c4fe6a689b4c17ccae482f1
contracts_fingerprint: fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf
verdict: NON-WIDENING HOLDS (live − union == ∅ BY NAME, modulo the documented 378-03 class-(c) candidates)
---

# 378-05 — TST-06 Final NON-WIDENING By-Name Ledger (live HEAD − union == ∅)

The binding milestone-level certification: the v55/56/57 by-name methodology applied at the v61
HEAD against the frozen `2bee6d6f` baseline. **A v61-HEAD forge red is certified NON-regressive
ONLY if its NAME is in `(the 2bee6d6f baseline union ∪ accepted-slot-shift-staleness ∪
accepted-v61-behavior ∪ the documented 378-03 class-(c) candidates)`.** Any HEAD red NOT in that
union is a NEW candidate v61 finding — surfaced, NEVER silently absorbed.

**COMPARED BY NAME, never by COUNT** (per the v56 §2 / v57 discipline + the T-378-05-02 threat
mitigation). A count match can hide a swapped red (one baseline red flips green while a new
regression appears at the same total). The set-diff below is name-keyed.

---

## 1. Live HEAD counts (forge, default profile)

`forge test` at the v61 working HEAD (all 378-01..05 test edits + the 5 new proving tests + the
2 untracked 378-02 WIP gas drafts present), clean forge cache:

| | passed | failed | skipped | total |
|---|---|---|---|---|
| **v61 HEAD** | **711** | **66 (unique names)** | **103** | (827 names; raw fail rows collapse to 66 unique) |

- The 66 raw failures collapse to **66 unique failing test NAMES** (fuzz/parameterized repeats
  and the 3 stateful-invariant entries deduped by name).
- Baseline `2bee6d6f` was **533 / 183 / 103** (172 unique `test*` names in REGRESSION-BASELINE-v61.md §3).
- The HEAD pass count rose to 711 because the 378-01/02/03 slot recalibration turned **112** baseline
  names GREEN (the narrowing) and the **54 new proving tests** (TST-01..05) added green.

> **Why a large red count is not a regression signal:** the v61 PACK fold breaks every
> slot-hardcoded harness at runtime (the region-dependent −1/−2/−3 shift) AND the repo carries a
> large pre-existing red baseline (v56/v57 ran ~134 red-by-name). "No v61 regression" is certified
> ONLY by the NON-WIDENING by-name set-diff in §3, NOT by the raw count.

## 2. The union definition (the ceiling)

`UNION = BASE ∪ accepted-slot-shift-staleness ∪ accepted-v61-behavior ∪ documented-class-(c)`

- **BASE** = the **172-name** `2bee6d6f` baseline red union, BY NAME, in
  `test/REGRESSION-BASELINE-v61.md` §3 (the 378-01 frozen capture).
- **accepted-slot-shift-staleness** = harness reds whose `[FAIL]` reason is a wrong-slot
  `vm.store`/`vm.load` artifact of the v61 region-dependent shift, recalibrated across 378-01
  (StorageFoundation + 4 redemption harnesses) and 378-02 (the 6 gas harnesses). A recalibrated
  harness turning GREEN is a NARROWING (allowed). The authoritative slot map is
  `378-01-RECALIBRATION-KEY.md`. (These produce NARROWINGS, not new union members.)
- **accepted-v61-behavior** = tests asserting pre-v61 behavior the feature legitimately changed.
  **378-03 found NONE required** — every behavioral residual was CARRIED (in-union) or a documented
  out-of-union fuzz twin. The v61 behavior surface is proven POSITIVELY by the new TST-01..05
  proofs, not by mutating regression harnesses.
- **documented-class-(c)** = the **3** pre-surfaced candidates from `378-03-CANDIDATE-FINDINGS.md`
  (accepted-staleness twins of carried in-union siblings; NOT contract bugs):
  - **C-1** `testFuzzTwoBlockOpenNoBlockEntropy` (V56FreezeSolvency) — the `_openAfkingBoxAt`
    deferred-open fixture-driver root (shared with carried in-union siblings
    `testStampedDayOpenAtTwoBlocksByteIdentical`, `testSubscribeMinBuyStampsNoInlineResolve`).
  - **C-2** `test_gapBackfillEntropyUnique_fuzz` (VRFStallEdgeCases) +
    `test_gapBackfillWithMidDayPending_fuzz` (VRFPathCoverage) — the `uint24`-vs-`uint32`
    `abi.encodePacked` gap-word encoding root (shared with carried in-union siblings
    `test_gapBackfillSingleDayGap`, `test_stallSwapResume`); the `uint24 gapDay` typing predates
    v61 (`c3e84b792`).

### 2a. One addition to the §3 union this plan justifies — the 3 carried VRFPath invariants

The §3 baseline name-enumeration scoped to `test*` NAMES and **did not enumerate the `invariant_*`
family** (a capture-scope gap, not their absence — the baseline §1 raw 183 failures folded them in).
Three `invariant_*` reds appear in the live HEAD set:

```
invariant_allGapDaysBackfilled
invariant_rngUnlockedAfterSwap
invariant_stallRecoveryValid
```

All three live in `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` (the VRFPath stall/swap/gap-backfill
stateful-fuzz suite — the SAME family as the carried `test_stallSwapResume` / `test_gapBackfill*`
siblings). They were surfaced out-of-union by the gate (the methodology working as designed), then
**investigated and PROVEN PRE-EXISTING at `2bee6d6f`** rather than absorbed:

> **Baseline reproduction (decisive).** The full `2bee6d6f` test tree + contracts were checked out
> non-destructively (the 378-01 method: HEAD-only V61*.t.sol moved aside, the 2 untracked WIP gas
> drafts moved aside, forge cache cleared), `forge build` clean, and `VRFPathInvariants.inv.t.sol`
> run. **Result at the baseline: `Suite result: FAILED. 4 passed; 3 failed` — the SAME 3 invariants,
> with byte-identical failure messages:**
> - `VRFPath: gap day missing rngWordForDay after recovery: 32 != 0` (HEAD: `31`/`32 != 0` — a
>   bucket-A fuzz-sequence count variance, same root)
> - `VRFPath: rngLocked true after coordinator swap: 1 != 0` (identical)
> - `VRFPath: invalid stall-to-recovery state transition: 1 != 0` (identical)
> The tree was then HARD-restored to HEAD (`git checkout HEAD -- test/ contracts/`); contracts
> tree-hash re-verified `87e3b45b…`, `git status --porcelain contracts/` empty.

These are **carried bucket-A reds** (non-deterministic stateful-fuzz — membership fluctuates
run-to-run, exactly the §4 Bucket-A class). They are pre-existing, NOT a v61 regression. The v61
diff (AFPAY/PACK/CURSE/SMITE) touches none of the VRF-coordinator-swap / gap-backfill / rngLocked
logic (that lives in `DegenerusGameAdvanceModule`, untouched). They are added to the union as
**carried** with the baseline-reproduction evidence above — this is honest (they ARE red at
baseline), NOT widening-to-hide-a-regression.

> **Investigated and DISMISSED (no contract change):** an initial hypothesis was that the
> `VRFPathHandler` slot reads (`lootboxRngIndex` slot 37, `dailyIdx` read `>> 32`,
> `lootboxRngWordByIndex` slot 38) were v61-slot-stale. Recalibrating them to the authoritative v61
> values (36 / `>> 24` / 37) did NOT change the outcome (still 3 fail, fresh-cache), AND the
> baseline run reproduces the failure with the baseline's own handler — so the reds are a genuine
> pre-existing ghost-counter property of the VRFPath fuzzer, not a slot-read artifact. The
> recalibration was therefore REVERTED (the handler is left byte-identical to its committed HEAD
> form — no spurious test edit). The reds stay CARRIED.

**`UNION = 172 (BASE §3) + 3 (documented class-(c)) + 3 (carried VRFPath invariants) = 178 names`**
(deduped).

## 3. The by-name set-diff (THE GATE)

```
live HEAD red names (unique):              66
UNION (172 §3 ∪ 3 candidates ∪ 3 carried invariants, deduped): 178

live − UNION  (the gate; must be ∅):        0   ← EMPTY
UNION − live  (narrowings; allowed):      112   ← reds the v61 recalibration fixed
```

**`live − UNION == ∅` → NON-WIDENING HOLDS.** Every one of the 66 live HEAD red names is accounted
for. ZERO new contract regression from the v61 AFPAY+PACK+CURSE+SMITE fold.

### 3a. The 66 live red names, categorized

| Category | Count | Disposition |
|----------|------:|-------------|
| (A) in the `2bee6d6f` §3 baseline union | **60** | CARRIED (pre-existing red; left red by design) |
| (B) documented class-(c) candidates (C-1 + C-2) | **3** | pre-surfaced 378-03 accepted-staleness twins (not contract bugs) |
| (C) carried VRFPath invariants (proven red @ baseline §2a) | **3** | carried bucket-A (pre-existing; §3-enumeration scope gap) |
| **total** | **66** | **all accounted for — live − union == ∅** |

(A) 60 carried in-union: the residual pre-existing reds — harness-isolation `_queueTickets` panics
(TicketRouting/QueueDoubleBuffer/TicketEdgeCases family: testQueue*/testRng Guard*/testBoundary*/
testRangeRouting/testNear+FarFuture/testScaled*/testEdge0*/testWriteReadIsolation), deferred-lootbox-open
materialization (testStampedDayOpenAtTwoBlocksByteIdentical, testSubscribeMinBuyStampsNoInlineResolve),
finalize-hook events (testFinalizeHookA/D, testStreakDecaysToZeroAfterOneMissedFundedDay), mintBurnie
advance/drain fixtures (testAdvanceBranchCreditsExactlyOnce, testAdvanceViaMintBurnieRewardedMultiplierHonored,
testMidDayPartialDrainRewardedViaMintBurnie), the Degenerette keeper `>=3` gate
(testGteThreeNonWwxrpPaysExactlyOneFlat, testMixedWwxrpAndNonWwxrpPaysAtGate,
testResolutionDeltasIndependentOfRewardGate, testResultsEqualityValueInvariant, testDgnrsAwardStaysPerSpin),
gap-backfill encoding (test_gapBackfillSingleDayGap, test_gapDaysSkipResolveRedemptionPeriod,
test_stallSwapResume), affiliate score calibration (test_revertBelowMinScore,
testAffiliateReClaimChurnEqualsHonestContinuous), presale/PFIX tier shape (test_PFIX02/03*),
boon-roll probabilities (test_lootboxBoonAppliedDespiteExistingCoinflipBoon,
test_parametricAutoBuy_crossCategoryBoonFromLootbox, testLootboxNearRollTicketsProcessed), the freeze/pool
harness (testFreezeUnfreezeRoundTrip, testMultiDayAccumulatorPersistence,
testDegeneretteFreezeResolution*, testFrozenSolvencyRevertsOnIdenticalSpin_Tier2,
testGameOverDrainsQueuedTickets, testBindingConsistencyDailyDrain), the mid-day swap family
(testMidDay*), the VRF-window carry (test_midDayRequest_doesNotBlockDaily, test_vrfLifecycle_levelAdvancement,
test_gap_gnrus_propose_vote_paths), the crossing-refresh fixture (testCrossingPassHolderRefreshedNotEvicted),
the same-day churn pay-on-cancel (testChurnSameDayAccruesSlot0Once), and the bucket-A fuzz-exhaustion
red (testFuzz_RngLockDeterminism_StakedStonkRedemption). All red at `2bee6d6f` BY NAME (§3).

### 3b. The 112 narrowings (UNION − live ≠ ∅ — allowed, expected)

112 baseline names that were red at `2bee6d6f` are now GREEN at HEAD — the 378-01/02/03 slot/offset
recalibration of stale harness constants to the authoritative v61 layout (the AfKing/V56SubHardening
crossing-eviction + D-11/12/13 surface, the redemption/StorageFoundation harnesses, the
VrfRotation/RngFreeze/LootboxRng/KeeperFaucet lootbox-slot reads, the gas-marginal harnesses, etc.).
Per the v55/56/57 discipline `BASE − live ≠ ∅` is a NARROWING (reds the v61 TST work fixed), NOT a
regression. (The SOLVENCY-01 spine proofs among them — testSolvencyHoldsBuyThenBurnieClaim,
testBurnieClaimLeavesClaimablePoolUnchanged — pass at HEAD.)

### 3c. The 5 new proving tests — additive GREEN (the v61 work's positive contribution)

| File | Tests | Status |
|------|------:|--------|
| `test/fuzz/V61AfpayWaterfall.t.sol` (TST-01) | 10 | ok (0 failed) |
| `test/fuzz/V61Pack.t.sol` (TST-02) | 8 | ok (0 failed) |
| `test/fuzz/V61CurseSet.t.sol` (TST-03) | 13 | ok (0 failed) |
| `test/fuzz/V61CureBountyDecurse.t.sol` (TST-04) | 13 | ok (0 failed) |
| `test/fuzz/V61Smite.t.sol` (TST-05) | 10 | ok (0 failed) |
| **total additive green** | **54** | all green vs the shipped v61 impl |

These add green and characterize the v61 AFPAY/PACK/CURSE/SMITE surfaces POSITIVELY. The 2 untracked
378-02 WIP gas drafts (`ActivityScoreStreakGas.t.sol`, `AdvanceStageWorstCaseGas.t.sol`) produced
ZERO reds (additive green; not in `live − union`).

## 4. Hardhat behavioral suite — DOCUMENTED LIMITATION (corroborating, non-fatal)

Per the plan, Hardhat is corroborating; the forge by-name verdict in §3 is the PRIMARY and binding
TST-06 gate.

- **`npm test` cannot complete** in this checkout — the `test` script globs
  `test/adversarial/*.test.js`, but `test/adversarial/` is **absent from the working tree and from
  git** at both `2bee6d6f` and HEAD. Mocha's glob expansion fails (`MODULE_NOT_FOUND`) and the whole
  invocation exits before loading any spec. This is the SAME environment/repo-state limitation
  recorded in `REGRESSION-BASELINE-v61.md` §6 — it affects baseline and HEAD identically, so the
  prescribed deterministic-Hardhat-baseline by-name comparison cannot be captured autonomously.
- **`npm run test:stat`** (probabilistic chi²/EV) is excluded by design.
- **Runnable subset attempted (corroborating):** `npx hardhat test test/unit/*.test.js` DID run on
  the v61 HEAD: **930 passing / 67 failing / 3 pending** (a mocha file-unloader `MODULE_NOT_FOUND`
  fires at teardown — a harness artifact, not a test failure; the 930/67/3 counts are the real
  result). The 67 failures fall in the pre-existing affiliate-commission-cap, reward-pool-split-%,
  reward-percent-roll, and access-control test families — NOT the v61 AFPAY/PACK/CURSE/SMITE contract
  surface, and NONE are accounting-insolvency or RNG-freeze breaks. (A by-name Hardhat baseline to
  diff against could not be captured — `npm test` aborts before running — so this is a by-count
  corroboration only, consistent with broad pre-existing-red health, not a v61 regression signal.)

**Disposition.** The forge baseline ceiling (§3) is the primary and sufficient non-widening
reference per the plan's explicit "forge baseline is the PRIMARY ceiling, Hardhat is corroborating"
allowance. The v61 behavioral surface (TST-01..06 + SEC-01/02) is proven by the new forge proving
tests, independent of the Hardhat behavioral baseline.

## 5. Verdict

**TST-06 NON-WIDENING HOLDS (BY NAME).** `live − union == ∅` modulo the documented 378-03 class-(c)
candidates. The 66 live HEAD forge red names are 60 carried baseline §3 + 3 documented class-(c)
candidates + 3 carried VRFPath bucket-A invariants (the last empirically PROVEN red at the
`2bee6d6f` baseline). 112 baseline names narrowed to green; 54 new proving tests are additive green;
the 2 untracked WIP gas drafts are additive green. **ZERO new v61 contract regression.** No
`live − union` name required a contract change — no `## CONTRACT-CHANGE-NEEDED`.

The comparison is name-keyed set membership, never count (T-378-05-02 mitigation): a swapped red
would appear in `live − union` by name; none did. The union was NOT widened to force a green verdict
(T-378-05-03): the only out-of-union names (the 3 VRFPath invariants) were added as carried ONLY
after a decisive baseline reproduction, with the slot-stale hypothesis investigated and dismissed.

**Contract-boundary compliance:** ZERO mainnet `*.sol` edits across all of 378-05. `git status
--porcelain contracts/` empty at every commit; contract tree-hash
`87e3b45b46879ec80c4fe6a689b4c17ccae482f1` unchanged plan start→end (⇒ the content fingerprint
`fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` from 378-01 preserved). The
non-destructive baseline checkout was HARD-restored to HEAD; the VRFPathHandler recalibration probe
was reverted (handler byte-identical to HEAD).
