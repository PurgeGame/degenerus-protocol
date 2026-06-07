---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 03
artifact: candidate-findings
subject: v61 HEAD (b97a7a2e batched diff + 056481ea 377 Outcome-A)
authority: forge inspect DegenerusGame storageLayout + test/REGRESSION-BASELINE-v61.md (the 2bee6d6f by-name union)
captured: 2026-06-07
contracts_fingerprint: fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf
contracts_tree_hash: 87e3b45b46879ec80c4fe6a689b4c17ccae482f1
---

# 378-03 — Triage Ledger + Candidate v61 Findings

Per-file disposition of the ~32-file failing tail (after 378-01/02 cleared the slot-hardcoded
StorageFoundation/redemption/gas harnesses). Each remaining failing test is classified:

- **(a) slot-stale** → recalibrated to the authoritative v61 slots (378-01 §2/§3 key). A recalibrated
  test turning green is a NON-WIDENING narrowing (allowed by the TST-06 gate).
- **(b) v61-behavior** → the test asserted pre-v61 behavior the AFPAY/PACK/CURSE/SMITE feature
  legitimately changed; the EXPECTATION was updated to the correct v61 behavior (assertions
  strengthened/corrected, never weakened to a tautology).
- **carried** → the failing test NAME is in the `test/REGRESSION-BASELINE-v61.md` 2bee6d6f union ⇒
  PRE-EXISTING red. Left red, NOT fixed, NOT a candidate finding. (Recalibrating its slot layer may
  change the `[FAIL]` reason from `NoPass()`/`panic`/`InvalidBet()` to the underlying behavioral
  assertion that was always red — that is still the SAME carried red, just un-masked.)
- **(c) candidate** → a failure NOT explained by (a)/(b)/carried. DOCUMENTED here; NEVER contract-fixed
  (TEST-ONLY phase). A class-(c) item where the test is correct and a contract fix is the sole
  resolution is additionally flagged `## CONTRACT-CHANGE-NEEDED` in the executor return.

> **Authoritative v61 slot deltas applied (378-01 key, re-confirmed live via forge inspect):**
> `_subOf` 65→**62** · `_fundingSourceOf` 66→**63** · `_subscribers` 67→**64** ·
> `_subscriberIndex` 68→**65** · `_subCursor` 69→**66** · `mintPacked_` 10→**9** ·
> `rngWordByDay` 11→**10** · `lootboxRngPacked` 38→**36** · `lootboxRngWordByIndex` 39→**37** ·
> `degeneretteBets` 45→**43** · `degeneretteBetNonce` 46→**44** ·
> `levelDgnrsAllocation` 26→**27** · `levelDgnrsClaimed` 27→**28** ·
> **slot-0 bit offsets** (the v61 fold added `presaleOver`@28 + `subsFullyProcessed`@29, shifting the
> slot-0 fields DOWN 2 bytes): `level` 14→**12** · `subsFullyProcessed` 31→**29**.
> Unshifted (confirmed): `claimablePool`=1, `prizePoolsPacked`=2, `prizePoolPendingPacked`=11,
> `balancesPacked` root=7 (semantic-only). sDGNRS-resident slots untouched.

---

## Pre-378-03 baseline (the TRUE starting point, post-378-01/02)

The plan §C cited 525/396 — that was measured on raw v61 HEAD BEFORE 378-01/02 landed. The actual
pre-378-03 full-suite baseline (378-01/02 recalibrations already committed) was
**546 passed / 177 failed / 103 skipped (826 total)** — captured `forge test` at the start of 378-03.

---

## Task 1 cluster — AfKing / Degenerette / Affiliate / V56

### test/fuzz/AfKingConcurrency.t.sol — RECALIBRATED (3/3 carried-red names → GREEN)

| Test | Class | Disposition |
|------|-------|-------------|
| testCancelledSubFundingWithdrawable | (a) slot-stale | `NoPass()`: stale deity-grant `mintPacked_` 10→9 (+ `_subOf`/`_subscribers`/`_subscriberIndex` 65/67/68→62/64/65, `_subCursor`/slot69→66, `subsFullyProcessed` off31→29, `_subscribers` len/data slot). GREEN. (name in-union — a narrowing.) |
| testReactivateTombstonedSubNoDoubleAdd | (a) slot-stale | same recalibration. GREEN. (name in-union — narrowing.) |
| testStageResetGateReopensProcessingPerDay | (a) slot-stale | same; the `_subCursorVal`/`_openAfkingResetGate` slot-69→66 + `subsFullyProcessed` off-31→29 were the load-bearing fix. GREEN. (name in-union — narrowing.) |

Suite now 3 passed / 0 failed / 9 skipped (the 9 skips are pre-existing 357-00b D-12 supersessions).

### test/fuzz/AfKingSubscription.t.sol — RECALIBRATED (2 → GREEN; 1 carried)

| Test | Class | Disposition |
|------|-------|-------------|
| testMintBurnieEmitsAtMostOneBuyBounty | (a) slot-stale | `NoPass()`: stale `mintPacked_` 10→9 deity grant (+ `_subOf` 65→62 etc.). GREEN. (name OUT-of-union — narrowing, an extra green vs baseline; allowed.) |
| testNonCrossingPassHolderProcessedWithoutRefresh | (a) slot-stale | same. GREEN. (name in-union — narrowing.) |
| testCrossingPassHolderRefreshedNotEvicted | **carried** | in-union. After the slot fix (`mintPacked_`→9, `_fundingSourceOf`→63, level off14→12) the `NoPass()`/wrong-level layer is gone; residual `refresh count 0 != 1` is a fixture-driver inadequacy: `_runStageOnce()` is a SINGLE bare `advanceGame()` that does not walk the subscriber-processing STAGE on the idle poked fixture, so the crossing-REFRESH branch never fires. Present at baseline for the same driver reason (the deity slot 10 + level off-14 were BOTH authoritative at 2bee6d6f, so the baseline red was NOT slot-stale). The crossing-REFRESH/EVICT property is positively proven GREEN by the sibling `V56SubHardening::testCrossingEvictionStillEvictsOutgrownPass` (full `_settleGame` driver). Left red as carried. |

### test/fuzz/V56SubHardening.t.sol — RECALIBRATED (14 → GREEN; 1 carried + 1 carried-behavioral)

20 → 2 failing. 14 `NoPass()` reds were the stale deity-grant `mintPacked_` 10→9 (+ `_subOf` 65→62,
`_subscriberIndex` 68→65) and the stale `LEVEL_OFF` 14→12 (the slot-0 fold shift). All recalibrated GREEN
— notably `testCrossingEvictionStillEvictsOutgrownPass`, `testD11*`, `testD12*`, `testD13*`,
`testBountyEligibleTruthTable`, `testDrainAffiliateBase*` (all in-union narrowings).

| Test | Class | Disposition |
|------|-------|-------------|
| testD11FinitePassCoveringCurrentLevelSubscribes | (a) slot-stale | in-union. `NoPass()`: the deity sibling passed after the `mintPacked_`→9 fix, but the finite-pass arm ALSO needed `LEVEL_OFF` 14→12 — the test poked `level` at the stale byte-14, leaving the real `level` (byte 12) unchanged, so `_passHorizonOf(9) < level` mis-evaluated. After both fixes: GREEN. (narrowing.) |
| testChurnSameDayAccruesSlot0Once | **carried** | in-union. After the slot fix the `NoPass()` is gone; residual `pendingBurnie 0 != 100` is a TEST EXPECTATION that contradicts a PRE-v61 contract behavior: `subscribe(_,0)` (cancel) PAYS OUT the sub's `pendingBurnie` and zeros it (GameAfkingModule.sol:351-355, introduced commit `980865e8` 2026-06-04, BEFORE v61 `b97a7a2e`). The test asserts pendingBurnie STAYS at 100 across same-day churn; the contract pays-on-cancel. Pre-v61 behavior ⇒ carried (NOT a class-(b) v61 change, NOT a candidate). Left red. |

### test/fuzz/AffiliateDgnrsClaim.t.sol — RECALIBRATED (8 → GREEN; 1 carried)

9 → 1 failing. 8 `E()` reds were stale storage pokes: `levelDgnrsAllocation` 26→**27**,
`levelDgnrsClaimed` 27→**28** (these mapping roots were stale-LOW even pre-v61 — the in-code constants
predated the layout), and `level` slot-0 offset 14→**12** (shift `<<112`→`<<96`, the fold's slot-0
shift). With the bet/allocation set at the correct slots, the claim path no longer reverts `E()`.

| Test | Class | Disposition |
|------|-------|-------------|
| test_claimedTrackingAccumulates / test_claimWindowMovesWithLevel / test_orderIndependence / test_proportionalDistribution / test_revertDoubleClaim / test_threeAffiliatesProportional / test_totalClaimsLeAllocation / test_totalClaimsMatchPoolDelta | (a) slot-stale | all `E()` from the stale `levelDgnrsAllocation/Claimed` + `level` offset. Recalibrated GREEN. (all in-union — narrowings.) |
| test_revertBelowMinScore | **carried** | in-union. Reads the score via the public `affiliate.affiliateScore` view (no slot poke). `assertTrue(bobScore < 10 ether)` fails because one buyer's score is ≥ 10 ETH — an affiliate score-magnitude CALIBRATION assumption that predates v61 (AFPAY/PACK/CURSE/SMITE do not touch the affiliate score formula). Left red as carried. |

### test/fuzz/V56FreezeSolvency.t.sol — RECALIBRATED (4 → GREEN; 2 carried + 1 documented-(c))

7 → 3 failing. 4 `NoPass()` reds: stale `mintPacked_` 10→9 deity grant (+ `_subOf` 65→62,
`_subscriberIndex` 68→65, `rngWordByDay` 11→10, `lootboxRngPacked` 38→36, `lootboxRngWordByIndex` 39→37).
`testBurnieClaimLeavesClaimablePoolUnchanged`, `testDebitEqualsDeliveredEthValueExactly`,
`testSolvencyHoldsBuyThenBurnieClaim` → GREEN (in-union narrowings; the SOLVENCY-01 spine proofs pass).

| Test | Class | Disposition |
|------|-------|-------------|
| testStampedDayOpenAtTwoBlocksByteIdentical | **carried** | in-union. After the slot fix the residual is `open#1 emitted LootBoxOpened (non-vacuous)` false — the deferred afking-box does not materialize an open event under the `_openAfkingBoxAt` fixture driver (the box is stamped — `_rngWordByDay(stampDay) != 0` passes — but the open leg does not fire). Pre-existing harness materialization limitation; lootbox queue-then-materialize is intentional UX. Left red as carried. |
| testSubscribeMinBuyStampsNoInlineResolve | **carried** | in-union. Same `_openAfkingBoxAt` materialization root: `deferred open materialized the box` — the open does not fire in the fixture. Carried. |
| testFuzzTwoBlockOpenNoBlockEntropy | **(c) documented (accepted-staleness)** | OUT-of-union (a fuzz test — at 2bee6d6f it was bucket-A fuzz run-variance, name not stably captured). Fails `boxA.present` false at runs:0 — the IDENTICAL `_openAfkingBoxAt` materialization root as its two in-union siblings above. NOT a v61 regression (shares the carried siblings' pre-existing fixture-driver root; RNG-freeze is otherwise proven by the green seed-freeze proofs and 378-04/05's TST suite), NOT a confirmed contract bug. Documented as a candidate (out-of-union) per the conservative rule; NOT `## CONTRACT-CHANGE-NEEDED` — see §Candidate Findings. |

### test/fuzz/V56SecUnmanipulable.t.sol — RECALIBRATED (6 → GREEN; 4 carried)

10 → 4 failing. 6 `NoPass()` reds: stale `mintPacked_` 10→9 deity grant (+ `_subOf` 65→62,
`_subscriberIndex` 68→65, `LEVEL_OFF` 14→12). `testAffiliateBaseDrainAffiliateOnly`,
`testDoubleClaimPaysExactlyOnceCEI`, `testFinalizeHookC_PassEvictBeforeRemove`,
`testGapResetOnResumeRebasesTheRun`, `testNoOrphanPendingBoxSubUntouchedByStage`,
`testFuzzChurnNeverBeatsHonestContinuous` → GREEN (in-union narrowings).

| Test | Class | Disposition |
|------|-------|-------------|
| testFinalizeHookA_ExplicitCancelBeforeTombstone | **carried** | in-union. After the slot fix the residual is `no finalize event for who` — `_lastFinalizeStreakFor` reverts because the explicit-cancel finalize event does not fire in the fixture flow. Pre-existing finalize-hook harness behavior. Carried. |
| testFinalizeHookD_FundingKillBoundaryKeptAndZeroed | **carried** | in-union. Same `no finalize event for who` finalize-hook root. Carried. |
| testStreakDecaysToZeroAfterOneMissedFundedDay | **carried** | in-union. Same `no finalize event for who` root (the streak-decay assertion rides the finalize event). Carried. |
| testAffiliateReClaimChurnEqualsHonestContinuous | **carried** | in-union. `unsub did NOT flush affiliateBase (persists across unsub): 0 != 140` — a behavioral assertion on the affiliateBase unsub-flush; read via the recalibrated `_subOf` slot (so the slot layer is correct). Pre-existing behavioral red. Carried. |

---

## Task 2 cluster — VRF / Rng / Lootbox / Ticket / Keeper / pool tail

Authoritative slot deltas applied across this tail: `lootboxRngPacked` 37/38→**36**, `lootboxRngWordByIndex`
38/39→**37**, `degeneretteBets` 45→**43**, `degeneretteBetNonce` 46→**44**, `lootboxEthBase` 23→**22**,
`ticketQueue` 13→**12**, `ticketsOwedPacked` 14→**13**, sub region 65/67/68/69→**62/64/65/66**,
`mintPacked_` 10→**9**; and the slot-0 packed-field bit-offset shifts (the v61 fold added two bools at
offsets 28/29, shifting the fields above DOWN 2 bytes AND the low time fields' widths narrowed):
`dailyIdx` read 32→**24** (uint24 @ byte 3), `rngRequestTime` read 64→**48** (uint48 @ byte 6),
`level` 14→**12**, `gameOver` 23→**21**.

### FULLY GREEN after recalibration (slot-stale class cleared)

| File | Before | After | Class | Notes |
|------|-------:|------:|-------|-------|
| VrfRotationLiveness | 3 | 0 | (a) | `SLOT_LOOTBOX_PACKED` 37→36, `SLOT_LOOTBOX_WORD_MAP` 38→37, `rngRequestTime` read 64→48. The 2 `panic` + the index-advance red GREEN. |
| VrfRotationOrphanIndex | 2 | 0 | (a) | same lootbox-slot + offset recalibration. Both `panic` reds GREEN. |
| RngFreezeAndRemovalProofs | 4 | 0 | (a) | `lootboxRngPacked` 37→36, `lootboxRngWordByIndex` 38→37, `degeneretteBets` 45→43, `degeneretteBetNonce` 46→44. The `BatchAlreadyTaken()` + placement-guard + crank-box reds GREEN. |
| LootboxRngLifecycle | 17 | 0 | (a) | lootbox slot 37/38→36/37 + `rngRequestTime` 64→48. The index-read-0 + word-store class GREEN. |
| KeeperFaucetResistance | 7 | 0 | (a) | `degeneretteBets`/`degeneretteBetNonce` 45/46→43/44, lootbox 38/39→36/37, sub 65→62, `mintPacked_` 10→9. The `BatchAlreadyTaken()` class GREEN. |

### RECALIBRATED with carried residual(s)

| File | Before | After | Recalibrated (a) | Carried residual(s) (in-union) |
|------|-------:|------:|------------------|--------------------------------|
| VRFCore | 3 | 1 | `lootboxRngIndex` 37→36, `rngRequestTime` read 64→48 (fixed `test_retryDetection_fresh` + the `test_timeoutRetry_12h` panic) | `test_midDayRequest_doesNotBlockDaily` (`RngNotReady()` — VRF-window flow, carried) |
| VRFPathCoverage | 2 | 1 | `lootboxRngIndex`/word 37/38→36/37 (fixed `test_indexLifecycleAcrossStall_fuzz`) | `test_gapBackfillWithMidDayPending_fuzz` (OUT-of-union — see C-2) |
| VRFStallEdgeCases | 8 | 3 | lootbox 37/38→36/37, `SLOT_LOOTBOX_RNG_PACKED` 37→36, `rngRequestTime` 64→48, `dailyIdx` 32→24 (fixed 3 `panic` + wallClock + retryRescue) | `test_gapBackfillSingleDayGap`, `test_gapDaysSkipResolveRedemptionPeriod` (carried gap-backfill/skip behavior); `test_gapBackfillEntropyUnique_fuzz` (OUT-of-union — see C-2) |
| RngLockDeterminism | 5 | 1 | `SLOT_LOOTBOX_RNG_INDEX` 38→36, word map 39→37, `lootboxEthBase` 23→22 (fixed the no-maroon + ClaimWhalePass/AutoBuy per-index-word reds + the RetryLootboxRng vm.assume) | `testFuzz_RngLockDeterminism_StakedStonkRedemption` (`vm.assume rejected` — bucket-A fuzz exhaustion, carried) |
| StallResilience | 2 | 1 | `lootboxRngIndex`/word 37/38→36/37 (fixed `test_lootboxOpenAfterOrphanedIndexBackfill`) | `test_stallSwapResume` (gap-backfill word mismatch — carried, see §gap-backfill) |
| TicketLifecycle | 9 | 1 | slot-0 offsets (level/jackpot/rngLocked/writeSlot/compressed shift −2), `lootboxRngIndex`/word 37/38→36/37, `LOOTBOX_RNG_WORD_SLOT` 38→37 (fixed the `rngLockedFlag`-poke + lootbox-FF reds) | `testLootboxNearRollTicketsProcessed` (probabilistic near/far roll — carried) |
| KeeperRouterOneCategory | 3 | 1 | sub 65/67→62/64, `mintPacked_` 10→9, lootbox 38/39→36/37, `lootboxEthBase` 23→22, `ticketQueue`/owed 13/14→12/13, gameOver byte 23→21 (fixed the gameOver-latch + box reds) | `testAdvanceBranchCreditsExactlyOnce` (mintBurnie advance-bounty fixture — carried) |
| KeeperRewardRoutingSameResults | 4 | 2 | sub 65/67→62/64, `mintPacked_` 10→9, `ticketQueue`/owed 13/14→12/13, gameOver byte 23→21, balancesPacked low-128 semantic seed | `testMidDayPartialDrainRewardedViaMintBurnie`, `testAdvanceViaMintBurnieRewardedMultiplierHonored` (mintBurnie advance/drain fixture — carried) |

### NO recalibration — entirely carried (all in-union, no slot-stale layer introduced by this triage)

| File | Failing | Class | Reason |
|------|--------:|-------|--------|
| TicketRouting | 12 | carried | ALL 12 names in-union. `panic: arithmetic underflow` from `_queueTickets`→`_livenessTriggered` called in ISOLATION on a bare `DegenerusGameStorage` harness (uninitialized `purchaseStartDay`/timestamp arithmetic). The queue logic is unchanged by v61 (all commits pre-`b97a7a2e`). Harness-isolation artifact, red at baseline. |
| QueueDoubleBuffer | 9 | carried | 9 in-union `panic: arithmetic underflow` — same `_queueTickets` harness-isolation root as TicketRouting. (`testSwapResetsFullyProcessed`, out-of-union, PASSES.) |
| TicketEdgeCases | 2 | carried | 2 in-union `panic: arithmetic underflow` — same `_queueTickets` harness-isolation root. |
| PresaleBoxDrain | 3 | carried | 3 in-union presale tier-shape/closing-box behavioral assertions (`tier5 soldBefore >= 40 ETH`, closing-box identity). Pre-existing, unchanged by v61. |
| LootboxBoonCoexistence | 2 | carried | 2 in-union probabilistic boon-roll assertions ("at least one lootbox should have rolled a non-coinflip boon" / cross-category exclusivity over 100 opens). Pre-existing. |
| PrizePoolFreeze | 2 | carried | 2 in-union harness pool-accumulation assertions (`88 != 0`, `400 != 200`) via the `_swapAndFreeze` harness (direct field access, no vm.store offset). Pre-existing. |

> **Gap-backfill word-derivation reds (shared root):** `test_gapBackfillSingleDayGap`,
> `test_stallSwapResume`, `test_gapBackfillEntropyUnique_fuzz`, `test_gapBackfillWithMidDayPending_fuzz`
> all compute the expected gap word as `keccak256(abi.encodePacked(resumeWord, uint32(day)))` but the
> contract derives `keccak256(abi.encodePacked(vrfWord, uint24(gapDay)))` (`DegenerusGameAdvanceModule.sol:1844`)
> — the `uint24` vs `uint32` `abi.encodePacked` width differs (3 vs 4 bytes), so the keccak differs.
> The `uint24 gapDay` typing predates v61 (`c3e84b792`, 2026-06-04, before `b97a7a2e`), and the two
> in-union names were red at `2bee6d6f` ⇒ a PRE-EXISTING test-vs-contract encoding mismatch, NOT a v61
> change. The two in-union names are carried; the two out-of-union fuzz variants are documented (C-2).

---

---

## Candidate Findings (class-(c))

### C-1 — testFuzzTwoBlockOpenNoBlockEntropy (V56FreezeSolvency) — accepted-staleness, NOT a contract bug

- **File / test:** `test/fuzz/V56FreezeSolvency.t.sol :: testFuzzTwoBlockOpenNoBlockEntropy`
- **FAIL reason:** `fuzz open A materialized (non-vacuous)` — `boxA.present == false` at runs:0 (the
  afking box does not materialize a `LootBoxOpened` event via the `_openAfkingBoxAt` driver).
- **Why not (a):** slots are correct post-recalibration — the stamp lands (`_rngWordByDay(stampDay) != 0`
  passes); the failure is the open leg not firing, not a wrong-slot read.
- **Why not (b):** it does not assert a pre-v61 behavior that the feature changed; it asserts box
  materialization, which is unchanged by AFPAY/PACK/CURSE/SMITE.
- **Why not cleanly carried:** the NAME is out-of-union (a fuzz test — at 2bee6d6f it was bucket-A
  fuzz run-variance, not stably captured by name). So per the conservative triage rule it is
  documented rather than silently called carried.
- **Shared root / disposition:** IDENTICAL `_openAfkingBoxAt` materialization root as its two in-union
  carried siblings (`testStampedDayOpenAtTwoBlocksByteIdentical`,
  `testSubscribeMinBuyStampsNoInlineResolve`), which prove the deferred-lootbox-open fixture flow was
  already red at baseline. **Not a confirmed contract bug** (lootbox queue-then-materialize is
  intentional UX; RNG-freeze is proven by the green seed-freeze proofs + 378-04/05 TST suite). A
  contract fix is NOT the resolution — the resolution would be a fixture-driver upgrade (out of
  scope for a non-widening TST triage). NOT flagged `## CONTRACT-CHANGE-NEEDED`.

### C-2 — gap-backfill word-derivation fuzz variants (out-of-union) — accepted-staleness, NOT a contract bug

- **Files / tests:** `test/fuzz/VRFStallEdgeCases.t.sol :: test_gapBackfillEntropyUnique_fuzz` and
  `test/fuzz/VRFPathCoverage.t.sol :: test_gapBackfillWithMidDayPending_fuzz`.
- **FAIL reason:** the gap-day word read from `rngWordByDay[day]` does not equal the test's expected
  `keccak256(abi.encodePacked(resumeWord, uint32(day)))` (and the mid-day-pending variant: the gap day
  has a zero word under the fuzz seed).
- **Why not (a):** post-recalibration the lootbox/slot reads are correct (the two files' other reds went
  green); the residual is a word-VALUE/derivation mismatch, not a wrong-slot artifact.
- **Why not (b):** the contract's gap-backfill derivation (`keccak256(abi.encodePacked(vrfWord, uint24(gapDay)))`,
  `DegenerusGameAdvanceModule.sol:1844`) is UNCHANGED by v61 (the `uint24 gapDay` typing landed `c3e84b792`,
  2026-06-04, before `b97a7a2e`). The test asserts a `uint32(day)` encoding — a pre-existing test-side
  encoding mismatch, not a v61 behavior change.
- **Why not cleanly carried:** both NAMES are out-of-union (fuzz tests — bucket-A run-variance at 2bee6d6f).
- **Shared root / disposition:** IDENTICAL `uint24`-vs-`uint32` `abi.encodePacked` gap-word encoding root as
  their in-union carried siblings `test_gapBackfillSingleDayGap` (VRFStallEdgeCases) + `test_stallSwapResume`
  (StallResilience), which were red at baseline for the same mismatch. **Not a confirmed contract bug** — a
  contract fix is NOT the resolution; the correct fix is test-side (align the expected encoding to `uint24`),
  but the two in-union siblings are carried-red by the non-widening discipline (carried reds are left red,
  not fixed), so their out-of-union fuzz twins are documented here rather than force-fixed. NOT flagged
  `## CONTRACT-CHANGE-NEEDED`.
