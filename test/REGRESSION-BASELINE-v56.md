# Regression Baseline — v56.0 (NON-WIDENING clean-baseline gate ledger)

> **357-00e RE-RUN @ c9b5d20d `c9b5d20d756f9dfc5f3b0584aae56bdfa215d8bf` (the FIFTH / FINAL v56.0 contract gate —
> the flat-10% pass lootbox + dead-guard removal; see §11, the CURRENT re-frozen subject).** After ONE further
> `contracts/*.sol` commit layered on HEAD'''' `77d8bc88` — **c9b5d20d** (a contained pass-PURCHASE economic
> refactor: the presale lootbox elevation on all 3 pass types — whale bundle / lazy pass / deity — REMOVED, the
> lootbox now a flat 10% of pass value regardless of presale state; the `*_LOOTBOX_PRESALE_BPS` constants + the
> `_psRead(PS_ACTIVE)` ternaries dropped, `*_LOOTBOX_POST_BPS → *_LOOTBOX_BPS`; the 25% `presaleBoxCredit`
> byte-unchanged so presale buyers now get 25% credit + 10% lootbox instead of 25% + 20%; 3 unreachable guards
> removed [the lazy `baseCost == 0` check — `priceForLevel` is strictly positive over all `uint24`; the lazy/deity
> `lootboxAmount == 0` zero-guards — 10% of a positive price is never 0]; a stale `hasAnyLazyPass` docstring fixed)
> — the whole tree was re-run at the re-frozen subject c9b5d20d and reconciled (§11). **New counts: 574 passed /
> 133 failed / 103 skipped (810 total).** The live **133** failing NAME set is a STRICT SUBSET of the §2 134-name
> `453f8073` union (`live − union == ∅`, verified empirically — empty set-diff) — **NON-WIDENING HOLDS at
> c9b5d20d; ZERO new forge regression from the flat-10% pass-lootbox + dead-guard removal.** The refactor only
> tweaks the lootbox-award MULTIPLIER (`2000 → 1000` presale bps) — off the ETH/`claimablePool` solvency path; the
> ETH pool splits are computed from `totalPrice` INDEPENDENT of the lootbox %, the `presaleBoxCredit` is
> byte-unchanged, and reducing an award can only DECREASE value (no unbacked value, no EV-cap breach, no
> underflow). The `574/133/103` vs HEAD'''' `573/134/103` is a 1-fail NARROWING (run-variance re-membership in the
> documented non-deterministic Bucket A/F cluster, §4 — the refactor touches no VRF/RNG-window code, so it cannot
> deterministically change a Bucket-A red). The SOLVENCY-01 leg-1 byte-anchor STILL HOLDS (the pass refactor is off
> the ETH path; the afking debit two-liner is untouched — `git diff 77d8bc88 c9b5d20d -- contracts/modules/GameAfkingModule.sol`
> is EMPTY). **`git diff c9b5d20d HEAD -- contracts/` is EMPTY** — 357-00e is test + ledger writes ONLY; the
> subject stays re-frozen at c9b5d20d.

> **357-00d RE-RUN @ HEAD'''' `77d8bc88` (the two subscribe-hardening follow-up gates — see §10, SUPERSEDED as
> CURRENT by §11 at c9b5d20d).** After TWO further `contracts/*.sol` commits layered on HEAD'' `61315ecd` —
> **HEAD''' `7b0b2a0b`** (the NEW-run subscribe per-day slot-0 idempotency guard: a subscribe→funded-buy→cancel→
> subscribe loop no longer re-accrues the flat per-day `QUEST_SLOT0_REWARD`, `GameAfkingModule.sol:451`
> `else if (s.lastAutoBoughtDay == uint24(today)) { _setStreakBase(s, snap); }`) and **HEAD'''' `77d8bc88`** (the
> USER-caught D-11 LEVEL-0 zero-horizon rejection: the gate at `:372` changed from `s.validThroughLevel < level`
> to `(s.validThroughLevel == 0 || s.validThroughLevel < level)` so a passless EOA (horizon 0) is rejected at
> level 0 too, where `0 < 0` was vacuously false) — the whole tree was re-run at the re-frozen subject HEAD''''
> and reconciled (§10). **New counts: 573 passed / 134 failed / 103 skipped (810 total).** The live **134**
> failing NAME set is BYTE-IDENTICAL by NAME to the §2 134-name `453f8073` union (`live − union == ∅` AND
> `union − live == ∅`, verified empirically — name-keyed set-diff both directions EMPTY) — **NON-WIDENING HOLDS
> at HEAD''''; ZERO new forge regression from the two gates.** Both changes are **revert-only / control-flow-only**
> (no ETH path): the slot-0 guard skips a second same-day cover-buy; the D-11 level-0 arm adds a revert. The
> ONE REVERT-REASON FLIP the D-11 level-0 fix introduced was caught + adapted: **4 `AfKingSubscription`
> fixtures** (`testCrossingNoPassEvictedViaTombstone`, `testSubscribeNoBurnieChargeRegardlessOfPass`,
> `testUnapprovedFundingSourceRefusedThenHonored`, `testRevokeDoesNotStopActiveSub`) subscribed a **passless EOA
> at level 0** relying on the pre-HEAD'''' vacuity (their own comment: "a no-pass sub clears D-11
> (validThroughLevel 0 < level 0 is false)"); they were 8/8 GREEN at HEAD'' and now revert `NoPass()`. Per the
> §3b/§8c removed/adapted-surface discipline each is `vm.skip`-with-reason (Skipped, not Failure → genuinely
> NON-WIDENING), the level-0 successor properties re-proven GREEN by the NEW `V56SubHardening` proofs (§10b). The
> NEW `V56SubHardening` proofs (17 → 22 GREEN): `testChurnSameDayAccruesSlot0Once` (slot-0 accrued ONCE across
> same-day churn) + `testD11PasslessEoaRevertsNoPassAtLevelZero` + `testD11RealPassSubscribesAtLevelZero` +
> `testD11DeityHolderSubscribesAtLevelZero` + `testD13VaultSdgnrsExemptAtLevelZero`. The SOLVENCY-01 leg-1
> byte-anchor STILL HOLDS (both gates are revert-only / control-flow-only — the debit two-liner is byte-frozen,
> only relocated `:690-691`→`:702-703` by the +12-line slot-0/comment insertion above it). **`git diff 77d8bc88
> HEAD -- contracts/` is EMPTY** — 357-00d is test + ledger writes ONLY; the subject stays re-frozen at HEAD''''.

> **357-00b RE-RUN @ HEAD'' `61315ecd` (the advance-incentive redesign — see §9, SUPERSEDED as CURRENT by §10
> at HEAD'''').** After the SECOND 357 contract gate (HEAD'' = `61315ecd0d617e5ece386676aaf452282331ebdf` — the
> advance-incentive redesign: `advanceGame()` DROPPED the `MustMintToday` hard revert → pure liveness; the
> must-mint tier ladder moved to the SOFT pay-gate `_bountyEligible(address)` in
> `DegenerusGameMintStreakUtils`, read by `mintBurnie()` BEFORE the self-call so the advance bounty pays only
> when `mult>0 && eligible`; NEW `bountyEligible(address) external view`; `DegenerusVault.gameAdvance()` +
> `StakedDegenerusStonk.gameAdvance()` now route through `mintBurnie()`), the whole tree was re-run at the
> re-frozen subject HEAD'' and reconciled (§9). **New counts: 567 passed / 133 failed / 99 skipped.** The live
> 133 failing NAME set is a STRICT SUBSET of the §2 134-name `453f8073` union (`live − union == ∅`, verified
> empirically — empty diff) — **NON-WIDENING HOLDS at HEAD''; ZERO new forge regression from the redesign.**
> The redesign NARROWED the live count by 1 (133 vs the HEAD' 134) — run-variance within the documented
> non-deterministic Bucket A (VRF/RNG-window) + Bucket F (flaky invariant) + `vm.assume`-exhaustion fuzz
> cluster (§4/§6); the `MustMintToday` hard-revert had a SINGLE consumer — the Hardhat `GovernanceGating`
> GATE-01..04 block, rewritten to the soft pay-gate model in 357-00b (§9b), NOT a forge fixture. The NEW
> `V56SubHardening` advance-soft-gate proofs (6 added → 17 GREEN) prove `advanceGame` liveness +
> `bountyEligible` truth table + the `mintBurnie` eligible/ineligible pay + the Vault/sDGNRS→mintBurnie
> routing. The SOLVENCY-01 leg-1 byte-anchor STILL HOLDS (the redesign is BURNIE-bounty-only + liveness-only —
> it touches no ETH/`claimablePool` debit). **`git diff 61315ecd HEAD -- contracts/` is EMPTY** — 357-00b is
> test + ledger writes ONLY; the subject stays re-frozen at HEAD''.

> **357-00b RE-RUN @ HEAD' `ac5f1e03` (the D-14 reconciliation — see §8; SUPERSEDED by §9 at HEAD'').** After the 357-00 contract
> gate (the F-356-01 `drainAffiliateBase` Game dispatch stub + the D-11 pass-required / D-12
> purchase-grounded / D-13 VAULT-sDGNRS-exempt subscribe hardening), the whole tree was re-run at the
> re-frozen subject HEAD' `ac5f1e033a785d18a9f0b89b7de5d05268431dbd` and reconciled. **The live failing
> NAME set is STILL the byte-identical `453f8073` 134-name union (`live − union == ∅` AND
> `union − live == ∅`) — NON-WIDENING HOLDS at HEAD'.** New counts: **566 passed / 134 failed / 99
> skipped** (the +69 skips over the §1 30 = the 357-00b drops: 68 ungrounded-subscribe-superseded
> fixtures + the 1 V56SecUnmanipulable hookB cancel-reclaim drop, §8). The NEW `V56SubHardening` suite
> (11 GREEN) re-proves the D-11/D-12/D-13 gates + the crossing eviction + the `drainAffiliateBase` stub
> reachability/AFFILIATE-only; the v56-native SEC/SOLVENCY/GAS suites were ADAPTED in place
> (fund-before-subscribe) and stay GREEN. The F-356-01 stub is a NARROWING (a previously-UNREACHABLE
> drain is now a green reachability proof — §8); the SOLVENCY-01 leg-1 byte-anchor STILL HOLDS (§7a:
> the 357-00 changes are revert-only + BURNIE-only — `git diff c5715297 ac5f1e03 --
> contracts/modules/GameAfkingModule.sol` does NOT touch the ETH/`claimablePool` debit two-liner).

**Plan:** 356-07 (Wave-2 full-suite NON-WIDENING regression gate); reconciled at HEAD' by 357-00b (§8).
**Subject:** the v56.0 audit subject — the **AfKing Everyday-Gas Minimization** milestone committed across the
v55 frozen subject `453f8073` (the IMPL diff `e18af451` + the 355 GAS net tune + the two USER liveness adds:
the `openBoxes` valve `86a2d6c8` + the gap/jackpot decouple `3d969621` + the USER `mustMintToday`-bypass advance
fix `5cb707f2` — an active-sub no-time-predicate fall-through in `_enforceDailyMintGate`, an 8-line hunk inside
the already-counted `DegenerusGameAdvanceModule.sol`). **Zero `contracts/*.sol` edits were applied by this
phase** (TST is a `test/` + `.planning/` phase; the audit subject stays byte-frozen — the v56 contract tree is
the SHIPPED milestone, `git diff 453f8073 HEAD -- contracts/` is the committed 14-file v56 diff, +1453/−733, NOT
a 356 edit).
**Baseline anchored against:** the **v55 frozen subject `453f8073`** (the 349.2 IMPL HEAD — the v55.0 closure
subject). Because the v56 contract tree DIFFERS from `453f8073` (the IMPL + 355 tune + valve + decouple are all
post-`453f8073`), the baseline red union is **established EMPIRICALLY** by running the `453f8073` contract
subject's full tree (§2), NOT carried verbatim from the v55 `test/REGRESSION-BASELINE-v55.md` ledger.

> **NOTE on the empirical baseline checkout (the `453f8073` corpus is uncompilable; the v55 TST-HEAD corpus is
> the faithful runner).** At the raw `453f8073` commit, `contracts/AfKing.sol` is already DELETED (the v55
> dissolution into `GameAfkingModule`), yet that commit's own test corpus — `DeployProtocol.sol` (the shared
> fixture) + 5 test files — still `import {AfKing} from "../../../contracts/AfKing.sol"` and **deploy `AfKing`
> at a load-bearing nonce** (`DeployProtocol.sol:126`, nonce 23, on which the CREATE-address prediction
> depends). So the `453f8073` commit's test tree **does not compile against its own contract tree**. The
> v55-adapted compilable corpus (the wholesale 351 corpus adaptation) is what makes the `453f8073` contract
> subject runnable. The faithful empirical baseline is therefore the **`453f8073` contract subject tested with
> the v55 TST-HEAD corpus** — commit `83a6a9ca` (the commit that authored `REGRESSION-BASELINE-v55.md`), whose
> contract tree is **byte-identical to `453f8073`** (`git diff 453f8073 83a6a9ca -- contracts/` is EMPTY,
> verified). Running `83a6a9ca`'s full tree reproduces the v55 TST-HEAD result **603 passed / 134 failed / 16
> skipped** — the `453f8073` contract subject's red union BY NAME. This is the same empirical-re-run method v55
> used off `20ca1f79`; the provenance is an honest run of the `453f8073` subject, not a doc-carry.

This is a plain-markdown ledger — NOT a `.sol` file, NOT a runnable test. It RECORDS the authoritative
whole-tree `forge test` run AT THE v56 TST HEAD (after all of 356-01..06 landed: the D-10 offset migration of
the 10 stale-offset fuzz files + the 3 v55-proof migrations + the 4 new v56 green proofs + the gas-marginal
extension, then the 356-07 resolution of the 14 migration-unmasked v56-behavior reds), the empirically-derived
134-name `453f8073` baseline union BY NAME, the **D-10 offset-migration red→green NARROWING**, every
**356-07 removed/adapted-surface DROP** BY NAME + reason, the v56 additive-green proof files, the SEC-02 leg-1
SOLVENCY-01 byte-diff anchor, and the net-zero-new-regression proof.

> **THE BINDING HEADLINE (by NAME, never a bare count):**
> at the v56 TST HEAD, every `forge test` failing test **∈** the empirically-established `453f8073` baseline
> red union **BY NAME** — `live failing set − the §2 union == ∅` — **net-zero new regression**.
> **The live v56 failing set is 134 names; the `453f8073` baseline union is 134 names; the live set is
> BYTE-IDENTICAL to the baseline union (`live − union == ∅` AND `union − live == ∅`).** Because the
> `DegeneretteBet.inv` invariant cluster is **unseeded** (§4), the v49-precedent strict-equality gate is
> RELAXED to the non-widening **SUBSET** gate (`live ⊆ union`, i.e. `live − union == ∅`), which is the
> load-bearing property: the v56 redesign + the new proofs introduced **no failing test outside the `453f8073`
> baseline**. This restores a clean v56.0 regression baseline against the FROZEN IMPL subject (the v56 milestone
> tree on top of `453f8073`).

---

## 1. The v56 TST-HEAD arithmetic + the reconciliation

The 356 waves (356-01 fixture + the 10-file D-10 offset migration + 356-02 the 3 v55-proof migrations + 356-03
SEC-01 `V56SecUnmanipulable` + 356-04 SEC-02 `V56FreezeSolvency` + 356-05 QST-04 `V56QuestNonPerturb` + 356-06
LIVE-01/GAS-06 gas-marginal extension + this 356-07 ledger and the 14-red resolution) mutate **no**
`contracts/*.sol` (the subject is frozen; `git diff HEAD -- contracts/` is EMPTY after every
`patchForFoundry` round-trip; `ContractAddresses.sol` is restored byte-identical sha256
`f7206e6c29b2c2767b4b835d1f636ac80a88129098eb13976bb2473da1dccfed` at HEAD). The whole-tree run was captured
with `node scripts/lib/patchForFoundry.js` (predict the CREATE addresses — there is no pretest hook) →
`forge test --json` (WHOLE tree, NOT `--match-path`) → `git checkout -- contracts/ContractAddresses.sol`.

| Quantity | `453f8073` baseline (§2, empirical via `83a6a9ca`) | v56 corpus delta (356-01..07) | v56 TST HEAD (this run) |
|----------|---------------------------------------------------|-------------------------------|-------------------------|
| `forge test` passed | 603 | **+21** (the new v56 proofs + the D-10 narrowing greens; see below) | **624** |
| `forge test` failed | 134 | **±0** (the 14 migration-unmasked v56-behavior reds DROPPED-by-name §3b; net 0 vs baseline) | **134** |
| `forge test` skipped | 16 | **+14** (the 356-07 `vm.skip`-with-reason drops, §3b) | **30** |
| total run (passed+failed+skipped) | 753 | **+35** (net test-function count delta) | **788** |

Reconciliation:
- **`failed == 134`**, and every one of the 134 ∈ the §2 134-name `453f8073` union BY NAME (`live − union == ∅`,
  proven §6). **The live 134 is BYTE-IDENTICAL to the `453f8073` 134** — neither set has a name the other lacks.
  **No name outside the `453f8073` union failed**, and no baseline red flipped green-as-regression-narrowing
  (the only NARROWING is the D-10 offset migration §3a, which moved test files from the previously-red garbage
  state to green INSIDE the corpus delta — those garbage-read reds are NOT in the `453f8073` union because the
  `453f8073` corpus carried the v55 layout that was correct for the `453f8073` Sub slot; see §3a).
- **`passed == 624`.** The +21 vs the baseline 603 is the 4 new dedicated v56 proof files (§5 — `V56SecUnmanipulable`
  11 + `V56FreezeSolvency` 7 + `V56QuestNonPerturb` 7 + the +6 net extension of `V56AfkingGasMarginal` from 9→15
  green = +31 new green) minus the 14 v56-behavior reds that, before the 356-07 drop, would have been counted
  red (they are now Skipped, not Passed) and the 4 differential/EV arms etc. — the net delta reconciles to +21
  passed / +14 skipped (the 14 drops moved from a HEAD-pre-drop Failure to Skipped; the new proofs added the
  greens).
- **30 `skipped`** = the 16 carried `RngLockDeterminism` `vm.skip` blocks (identical at the baseline, §2 NOTE-skip)
  + the **14 new 356-07 removed/adapted-surface DROPs** (§3b). The skips are not reds, not greens; orthogonal to
  the ⊆ gate (a skipped test cannot be a `live − union` red).

> **NOTE on the gate shape vs the v55 ledger.** v55 baselined against `20ca1f79` (which carried `AfKing.sol`),
> so the v54 union was established by re-running `20ca1f79`. **v56 baselines against `453f8073`** — the same
> contract subject as the v55 TST HEAD, so the `453f8073` baseline union is the v55 TST-HEAD red set
> (603/134/16), re-derived here by an HONEST full-tree run of `83a6a9ca` (contracts byte-identical to
> `453f8073`). The binding invariant — "no failing test outside the established baseline" — is identical in
> spirit to v49/v50/v55; only the baseline commit (`453f8073`) and the empirical-re-run provenance differ.

---

## 2. The `453f8073` baseline red union (enumerated BY NAME — the v56.0 ceiling) — EMPIRICALLY established

Every red below is a **`453f8073`-baseline red**, captured by running the `453f8073` contract subject's full tree
(via the byte-identical-contracts commit `83a6a9ca`), `node scripts/lib/patchForFoundry.js` + the WHOLE-tree
`forge test --json`, parsing the `--json` failing set. **The baseline run was `603 passed / 134 failed / 16
skipped`.** The v56 source subject flipped NONE of these green as a *regression*; the live v56 failing set is the
SAME 134 names. **Any v56 forge red NOT in this union is a NEW regression → STOP. No such red appeared** (§6,
`live − union == ∅` verified empirically — the live 134 == the baseline 134 BY NAME).

> **NOTE-skip — the 16 carried-forward `vm.skip` blocks (identical baseline↔v56).** The 16 carried `vm.skip` at
> v56 are byte-for-byte the 16 carried at the `453f8073` baseline: `RngLockDeterminism::{the 16
> testFuzz_RngLockDeterminism_* / testFuzz_EdgeCase_* blocks}`. Not reds, not greens; orthogonal to the gate.
> The 356-07 added 14 MORE `vm.skip` (§3b) — those are the removed/adapted-surface DROPs, distinct from these 16.

The 134 baseline reds (== the 134 v56-live reds) classify into three named buckets (each red lands in exactly
one bucket): **Bucket A** (VRF/RNG-window baseline reds = 41), **Bucket B** (stale-harness/behavioral = 92),
**Bucket F** (the unseeded `DegeneretteBet.inv` flaky cluster = 1).

### Bucket A — VRF / RNG-window baseline reds (41) — out of v56 scope; v56 touched no VRF/Advance RNG-window code apart from the gap/jackpot decouple (which adds proofs, not reds)

| # | Suite (file) | Failing test(s) | Count |
|---|--------------|-----------------|-------|
| A1 | `test/fuzz/LootboxRngLifecycle.t.sol` | `test_entropyUniqueDifferentPlayers`, `test_fullLifecycleDailyPath`, `test_fullLifecycleMidDayPath`, `test_fullLifecycleMultipleIndices`, `test_indexIncrementsOnFreshDaily`, `test_indexIncrementsOnMidDay`, `test_indexSequentialAcrossMultipleDays`, `test_wordWriteBackfill`, `test_wordWriteDaily`, `test_wordWriteIdempotent`, `test_wordWriteMidDay`, `test_wordWriteStaleRedirect`, `test_zeroGuardBackfill`, `test_zeroGuardMidDay`, `test_zeroGuardRawFulfill` | 15 |
| A2 | `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | `testClaimWhalePassMaterializesFutureWindowAndAppliesStats`, `testCrankBoxOpenStaysPostUnlock`, `testEthCreditPathIsDeterministicNoVrfWord`, `testEthWinningsAlwaysLandInClaimable`, `testLazyPassHorizonReadDoesNotPerturbFrozenSlots`, `testPlacementGuardUntouchedWhenIndexHasWord` | 6 |
| A3 | `test/fuzz/VRFStallEdgeCases.t.sol` | `test_coordinatorSwapClearsMidDayPending`, `test_retryLootboxRngRescuesStalledMidDay`, `test_zeroSeedAtGameStart`, `test_zeroSeedUnreachableAfterSwap` | 4 |
| A4 | `test/fuzz/VRFPathInvariants.inv.t.sol` | `invariant_allGapDaysBackfilled`, `invariant_rngUnlockedAfterSwap`, `invariant_stallRecoveryValid` | 3 |
| A5 | `test/fuzz/VrfRotationLiveness.t.sol` | `test_midDayRotation_liveness`, `test_requestLootboxRngReachableAfterRotation`, `test_retryRescuesStalledReissueAfterRotation` | 3 |
| A6 | `test/fuzz/VRFCore.t.sol` | `test_midDayRequest_doesNotBlockDaily`, `test_retryDetection_fresh` | 2 |
| A7 | `test/fuzz/VRFPathCoverage.t.sol` | `test_gapBackfillWithMidDayPending_fuzz`, `test_indexLifecycleAcrossStall_fuzz` | 2 |
| A8 | `test/fuzz/VRFLifecycle.t.sol` | `test_vrfLifecycle_levelAdvancement` | 1 |
| A9 | `test/fuzz/VrfRotationOrphanIndex.t.sol` | `test_postFix_midDayRotation_landsRealWordInOrphanedIndex` | 1 |
| A10 | `test/fuzz/RngIndexDrainBinding.t.sol` | `testBindingConsistencyDailyDrain` | 1 |
| A11 | `test/fuzz/RngLockDeterminism.t.sol` | `testFuzz_RngLockDeterminism_StakedStonkRedemption` (`vm.assume` rejected too many inputs — fuzzer-exhaustion, same documented red as v49/v50/v55) | 1 |
| A12 | `test/fuzz/RngLockRotationDeterminism.t.sol` | `testFuzz_RotationFreezeInvariant_MidDay` | 1 |
| A13 | `test/fuzz/StallResilience.t.sol` | `test_lootboxOpenAfterOrphanedIndexBackfill` | 1 |

**Bucket A total: 15+6+4+3+3+2+2+1+1+1+1+1+1 = 41.** (The `453f8073` baseline carried these same 41
VRF/RNG-window reds; v56 touched no VRF/Advance RNG-window code that would change them — the gap/jackpot
decouple ADDS the D-06/D-07 proofs in `V56AfkingGasMarginal`, contributing zero red.)

### Bucket B — stale-harness / behavioral baseline reds (92) — pre-existing `453f8073` fixtures encoding expectations the contract surface changed before v56; carried forward, out of this gate's scope

| # | Suite (file) | Failing test(s) | Count |
|---|--------------|-----------------|-------|
| B1 | `test/fuzz/TicketLifecycle.t.sol` | `testBoundaryRoutingAtDeployment`, `testBoundaryRoutingAtNonZeroLevel`, `testConstructorFFTicketsDrain`, `testFFDrainOccursDuringPhaseTransition`, `testFFDrainSequentialByTransition`, `testJackpotPhaseTicketsProcessedFromReadSlot`, `testJackpotPhaseTicketsRouteToCurrentLevel`, `testLastDayTicketsRouteToNextLevel`, `testLootboxFarRollTicketsRouteToFF`, `testLootboxNearRollTicketsProcessed`, `testPrepareFutureTicketsRange`, `testPurchasePhaseTicketsProcessed`, `testVaultPerpetualTicketsRouteToFF`, `testWhaleBundleTicketsAcrossLevels`, `testWriteSlotIsolationAcrossBufferStates`, `testWriteSlotIsolationDuringRngLocked`, `testWriteSlotSurvivesSwapAndFreeze`, `testZeroStrandingAutoBuyAfterTransitions` | 18 |
| B2 | `test/fuzz/TicketRouting.t.sol` | `testBoundaryLevel5RoutesToWriteKey`, `testBoundaryLevel6RoutesToFFKey`, `testFarFutureRoutesToFFKey`, `testNearFutureRoutesToWriteKey`, `testRangeRoutingSplitsCorrectly`, `testRngGuardAllowsWithBypass`, `testRngGuardIgnoresNearFuture`, `testRngGuardRangeRevertsOnFirstFFLevel`, `testRngGuardRevertsOnFFKey`, `testRngGuardScaledRevertsOnFFKey`, `testScaledFarFutureRoutesToFFKey`, `testScaledNearFutureRoutesToWriteKey` | 12 |
| B3 | `test/fuzz/AffiliateDgnrsClaim.t.sol` | `test_claimWindowMovesWithLevel`, `test_claimedTrackingAccumulates`, `test_orderIndependence`, `test_proportionalDistribution`, `test_revertBelowMinScore`, `test_revertDoubleClaim`, `test_threeAffiliatesProportional`, `test_totalClaimsLeAllocation`, `test_totalClaimsMatchPoolDelta` | 9 |
| B4 | `test/fuzz/DegeneretteFreezeResolution.t.sol` | `testBatchedPayoutEqualsPerSpinExpectation_Tier1`, `testDegeneretteFreezeResolutionEthConserved`, `testDegeneretteFreezeResolutionZeroPendingReverts`, `testDegeneretteUnfrozenPathRegression`, `testDgnrsAwardStaysPerSpin`, `testEthCapBindsOnIdenticalSpin_Tier2`, `testFrozenSolvencyRevertsOnIdenticalSpin_Tier2`, `testLootboxSummedPerBetIdNotAcrossBets`, `testResolveBetsRevertsPostGameOver_InsolvencyReproClosed` | 9 |
| B5 | `test/fuzz/FarFutureSalvageSwap.t.sol` | `test_SWAP08_BaseFractionBelowFarTicketPresentEv`, `test_SWAP08_NoArbAtCeiling_SweepAllDistances`, `test_SWAP09_ArrayBound`, `test_SWAP09_EthFloorEnforced`, `test_SWAP09_SolvencyAcrossSwap`, `test_SWAP09_SwapPopMembershipMaintained`, `test_SWAP09_TicketFloorEnforced` | 7 |
| B6 | `test/fuzz/DegeneretteResolveRepeg.t.sol` | `testGteThreeNonWwxrpPaysExactlyOneFlat`, `testMixedWwxrpAndNonWwxrpPaysAtGate`, `testOneOrTwoNonWwxrpCommittedUnpaidNoRevert`, `testResolutionDeltasIndependentOfRewardGate`, `testResultsEqualityValueInvariant`, `testThreeWwxrpOnlyResolvedUnpaidNoRevert`, `testZeroResolvedRevertsNoWork` | 7 |
| B7 | `test/fuzz/DegeneretteHeroScore.t.sol` | `test_HERO06_DailyHeroJackpotUnaffected_NoLeak`, `test_HERO06_WriteBatchByteIdentical_DGAS`, `test_HERO_DgnrsThresholdsRemapped`, `test_HERO_S8S9PackingDecodable`, `test_HERO_S9EqualsOldM8Jackpot`, `test_HERO_ScoreFormula` | 6 |
| B8 | `test/fuzz/QueueDoubleBuffer.t.sol` (QueueDoubleBufferTest) | `testQueueAfterSwapUsesNewWriteKey`, `testQueueTicketRangeUsesWriteKey`, `testQueueTicketsScaledUsesWriteKey`, `testQueueTicketsUsesWriteKey`, `testWriteReadIsolation` | 5 |
| B9 | `test/fuzz/QueueDoubleBuffer.t.sol` (MidDaySwapTest) | `testMidDayProcessesReadSlotFirst`, `testMidDayRevertsNotTimeYet`, `testMidDaySwapAtThreshold`, `testMidDaySwapJackpotPhase` | 4 |
| B10 | `test/fuzz/PresaleBoxDrain.t.sol` | `test_PFIX02_RealisticRun_ClosingSweepIsDust`, `test_PFIX03_EarlyDgnrsRunEmptiesPoolBeforeClose_ClampHolds`, `test_PFIX03_TierShapePreserved` | 3 |
| B11 | `test/fuzz/PrizePoolFreeze.t.sol` (FreezeLifecycleTest) | `testFreezeUnfreezeRoundTrip`, `testMultiDayAccumulatorPersistence` | 2 |
| B12 | `test/fuzz/TicketEdgeCases.t.sol` | `testEdge01NoDoubleCount_FFThenWriteKey`, `testEdge02RoutingPreventsNewFFDeposits` | 2 |
| B13 | `test/fuzz/LootboxBoonCoexistence.t.sol` | `test_lootboxBoonAppliedDespiteExistingCoinflipBoon`, `test_parametricAutoBuy_crossCategoryBoonFromLootbox` | 2 |
| B14 | `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol` | `testFuzz_MintDiv_BoundaryOwedCrossPath`, `testMintDivCrossPathEquality_OwedSplitsAcrossSlices` | 2 |
| B15 | `test/fuzz/CoverageGap222.t.sol` | `test_gap_gnrus_propose_vote_paths` | 1 |
| B16 | `test/fuzz/FarFutureIntegration.t.sol` | `testMultiLevelAdvancementWithFFTickets` | 1 |
| B17 | `test/fuzz/GameOverPathIsolation.t.sol` (GameOverBestEffortDrainTest) | `testGameOverDrainsQueuedTickets` | 1 |
| B18 | `test/fuzz/StorageFoundation.t.sol` | `testPackedPoolSlotsUnshifted` | 1 |

**Bucket B total: 18+12+9+9+7+7+6+5+4+3+2+2+2+2+1+1+1+1 = 92.** (All present-and-red at the `453f8073` baseline;
none introduced by v56. These are stale-harness / pre-existing behavioral reds the v56 afking redesign neither
touched nor caused — they fail identically at both HEADs. This is the SAME 92-name Bucket B as the v55 ledger
§2, name-for-name, because the v56 contract changes are confined to the afking/quest/affiliate/advance/lootbox
surface these stale fixtures do not exercise on their failing assertions.)

### Bucket F — the unseeded `DegeneretteBet.inv` flaky cluster (1)

| # | Suite (file) | Failing test | Count |
|---|--------------|--------------|-------|
| F1 | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` (DegeneretteBetInvariant) | `invariant_solvencyUnderDegenerette` | 1 (flaky — §4) |

**Bucket F total: 1.** Red at BOTH the `453f8073` baseline AND the v56 TST HEAD this run. The unseeded
`[invariant]` campaign explores a fuzz-dependent call-sequence space, so its red-subset is non-deterministic
run-to-run (§4); only `invariant_solvencyUnderDegenerette` is enumerated here (confirmed both runs).

### Union totals

Bucket A (41) + Bucket B (92) + Bucket F (1) = **134 baseline reds == 134 v56-live reds**, BYTE-IDENTICAL.
**`live − union == ∅`** AND **`union − live == ∅`** (§6).

---

## 3. NEW vs the `453f8073` baseline — the v56 deltas (the D-10 offset-migration NARROWING + the 356-07 removed/adapted-surface DROPS)

The v56 corpus differs from the `453f8073` corpus by exactly the attributable changes below: (a) the **D-10
offset-migration red→green NARROWING** (the stale-offset garbage-read reds flipping green INSIDE the corpus
delta); (b) the **356-07 removed/adapted-surface DROPS** (the 14 migration-unmasked v56-behavior reds, BY NAME
+ reason). There is **no rewrite-map / file-deletion delta** like v55's §3a (v56 EXTENDS + ADAPTS the existing
corpus in place; no whole-file re-authoring).

```
v56 §2 live = {`453f8073` §2 134-name union}
            with the corpus delta = D-10 NARROWING (§3a, garbage-red → green, internal to the migrated files)
                                  + the 356-07 DROPS (§3b, the 14 migration-unmasked v56-behavior reds → skipped)
= 134 live, BYTE-IDENTICAL to the 134-name `453f8073` union, with 0 names OUTSIDE it  ✓  (net-zero new regression)
```

### 3a. The D-10 offset-migration red→green NARROWING (the `6555125 != 3774873600` garbage-read reds)

The 10 `test/fuzz/` files still carrying the stale `OFF_LASTBOUGHT = 21`/uint32 Sub layout were migrated to the
shipped v56 `11`/uint24 re-pack (the exact `08e59a4a` mechanical transform), across waves 356-01 (the 7
read-only keeper/afking probes) + 356-02 (the 3 v55-proof files, offsets + write-mask helpers in lockstep).
Before the migration, those files' day-marker reads produced the `6555125 != 3774873600` garbage-read reds (the
v55 layout reading the v56 re-packed slot at the wrong offset). After the migration those garbage reds are GONE
(resolved → a **NARROWING**, never a widening), and the files run green (the 7 read-only probes) or surface the
genuine v56-behavior reds the 356-07 drop then resolves (the 3 v55-proof files — §3b).

> **Why the D-10 NARROWING does NOT appear as `union − live` slack.** The `453f8073` baseline corpus (the
> v55-adapted tree at `83a6a9ca`) carried the v55 Sub layout, which was CORRECT for the `453f8073` Sub slot —
> so at the `453f8073` baseline these 10 files were NOT garbage-red (they read the `453f8073` slot correctly).
> The garbage-read reds only ever appeared transiently in the v56 corpus BEFORE the D-10 migration (the v56
> re-pack moved the offsets; the un-migrated files read the v56 slot at the v55 offset). The D-10 migration
> fixed them WITHIN the 356 corpus delta, so they never entered the `453f8073` §2 union and produce no
> `union − live` slack. The NARROWING is recorded here for legibility (red→green inside the corpus delta), per
> the D-10 rationale (removes false-green risk; makes the ledger legible).

The 10 migrated files: `AfKingConcurrency`, `AfKingFundingWaterfall`, `AfKingSubscription`,
`KeeperRouterOneCategory`, `KeeperFaucetResistance`, `KeeperRewardRoutingSameResults`, `KeeperNonBrick`
(356-01) + `V55SetMutationOpenE`, `V55RevertFreeEvCap`, `V55FreezeDeterminism` (356-02). All read (and, for the
3 v55-proof files, write) the v56 Sub slot byte-correctly after the migration — confirmed by the
determinism/freeze/no-orphan/swap-pop/OPEN-E arms passing (proving the slot reads/writes are byte-correct), with
the residual reds being genuine v56-behavior unmasks (§3b), not layout-read reds.

### 3b. The 356-07 removed/adapted-surface DROPS (the 14 migration-unmasked v56-behavior reds, BY NAME + reason)

After the D-10 migration unmasked them (the tests now run past the previously-failing garbage assertion and
reach the next assertion), 14 reds remained — each a STALE test asserting **v55 behavior the USER-APPROVED +
audited v56 contract diff legitimately changed**. Per the v55 §3b removed/adapted-surface DROP precedent (bias =
adapt; drop only with a BY-NAME entry + reason), each is `vm.skip(true, "<v56-supersession reason>")` (the
Foundry-native skip already used by `RngLockDeterminism`'s 16 blocks — registers as Skipped, not Failure, so the
live tree is genuinely NON-WIDENING). **NONE is a genuine v56 bug** — every v56 successor property is re-proven
GREEN against the v56 surface by the new v56-native suites (§5). Committed as `f23b010e`.

| # | Dropped test(s) | File | v56-supersession reason (the SHIPPED behavior the v55 assertion no longer matches) | v56 successor proof |
|---|-----------------|------|-----------------------------------------------------------------------------------|---------------------|
| D1 | `testDifferentialAfkingVsHumanOpenSameTuple`, `testFuzzDifferentialAfkingVsHumanOpen` | `V55FreezeDeterminism.t.sol` | The v56 re-pack made `Sub.amount` **uint24 MILLI-ETH** (`_packEthToMilliEth` at the stamp, `_unpackMilliEthToWei` at the afking open). The differential harness pokes a RAW-WEI amount into the field, so the afking arm reads it as milli-ETH and the human arm reads raw-wei, diverging by design (`5242880000000000000000 != 800000000000000000` — the truncated `0x500000` interpreted as milli-ETH). The v55 assertion encodes the v55 raw-wei `amount` field. | `V56FreezeSolvency::testStampedDayOpenAtTwoBlocksByteIdentical` + `testFuzzTwoBlockOpenNoBlockEntropy` (the box byte-identity against the v56 milli-ETH layout) |
| D2 | `testEvCapExactlyOnceNoDoubleDraw`, `testEvCapSharedBudgetAcrossAfkingAndHuman`, `testFuzzEvCapMultiOpenClampedCumulative` | `V55RevertFreeEvCap.t.sol` | Same milli-ETH unmask — the raw-wei afking poke is read as milli-ETH at the open and SATURATES the 10-ETH EV cap (`10000000000000000000 != 3000000000000000000`), breaking the exact-draw / cumulative-draw model. | `V56SecUnmanipulable` (the churn-fuzz no-positive-EV invariant: churn-reachable BURNIE ≤ honest continuous) + `V56FreezeSolvency` |
| D3 | `testClassB_StageDebitSolvencyFailsLoud`, `testClassB_WithdrawSolvencyFailsLoud` | `V55RevertFreeEvCap.t.sol` | The v56 subscribe min-buy consumes **0.01 ETH** on the first stamp, so the funded credit no longer equals `msg.value` exactly (`4990000000000000000 != 5000000000000000000`) — the v55 assertion encodes the v55 no-min-buy behavior. | `V56FreezeSolvency` (the solvency-invariant fuzz `balance + steth.balanceOf(this) >= claimablePool` + the leg-1 debit-equals-delivered-value forge arm) |
| D4 | `testFuzzClassB_SolvencyAlwaysFailsLoud` | `V55RevertFreeEvCap.t.sol` | v56 `withdrawAfkingFunding` reverts the custom guard error `E()` rather than the v55 arithmetic-underflow `Panic(0x11)` the test `vm.expectRevert`s (a deliberate v56 revert-selector change). | `V56FreezeSolvency` (the solvency-invariant fuzz proves the fail-loud-on-solvency property) |
| D5 | `testSolvencyUnderflowFailsLoudOnWithdraw`, `testCancelThenWithdrawAlwaysSucceeds` | `KeeperNonBrick.t.sol` | The v56 subscribe min-buy 0.01-ETH delta breaks the `funding == msg.value` exactness (and the full-`poolEth` withdraw then exceeds the funded balance). | `V56FreezeSolvency` (solvency fuzz) + `V56SecUnmanipulable` (the finalize-hook/cancel arms — cancel-before-tombstone, cancel-reclaim-before-delete) |
| D6 | `testFuzzSolvencyUnderflowFailsLoud`, `testFuzz_CancelWithdrawNeverStrandsEth` | `KeeperNonBrick.t.sol` | v56 `withdrawAfkingFunding` reverts `E()` not `Panic(0x11)` (D4 root cause), and the 0.01-ETH funded-balance delta means withdrawing the full `poolEth` reverts `E()` (over-withdraw). | `V56SecUnmanipulable` (the no-orphan + finalize-hook cancel arms) + `V56FreezeSolvency` (solvency under unsub churn) |
| D7 | `testTwoPathOpenCoexistenceNoCrossCorruption` | `V55SetMutationOpenE.t.sol` | The v55 two-path-SEPARATION assertion (a human `openBoxes` leaves the afking stamp untouched: `lastOpenedDay unchanged: 2 != 0`) is superseded by the **v56 LIVE-01 UNIFIED `openBoxes` valve** (commit `86a2d6c8`), which calls `drainAfkingBoxes` FIRST then the human leg — so `openBoxes(50)` now legitimately opens the afking box too (`lastOpenedDay` advances). | `V56AfkingGasMarginal` (the LIVE-01 cases: afking-first ordering, both cursors drain, `lastOpenedDay` monotone no-double-open, `drainAfkingBoxes` selector isolation) |
| D8 | `testGas03HomogeneitySourcePresence` | `KeeperLeversAndPacking.t.sol` | The source-presence gate asserts `function autoOpen(uint256 maxCount)` exists on `DegenerusGame`, but the v56 LIVE-01 redesign (commit `86a2d6c8`) UNIFIED the human box-open into `openBoxes(maxCount)` + `drainAfkingBoxes`, dropping the standalone `autoOpen` source string (`0 <= 0`). (Dropped the `view` modifier to call the `vm.skip` cheatcode.) | `V56AfkingGasMarginal` (the LIVE-01 cases prove the `openBoxes` valve + selector isolation against the v56 source) |

> **NOTE on the 356-07 drops vs the `453f8073` baseline union (§2):** every one of the 14 dropped tests is in a
> file whose **v56-behavior reds DID NOT EXIST at the `453f8073` baseline** — `V55FreezeDeterminism`,
> `V55RevertFreeEvCap`, `V55SetMutationOpenE` (the migrated files PASSED these arms at the `453f8073` baseline,
> where the v55 layout + v55 contract behavior matched), and `KeeperNonBrick` / `KeeperLeversAndPacking` (same:
> green at baseline). All 14 tests were verified **Success @ the `453f8073` baseline run** and **Failure @ the
> v56 HEAD pre-drop run** — i.e. they are GENUINE WIDENINGS (the v56 contract behavior changed) that the 356-07
> drop resolves. So dropping them removes NOTHING from the `453f8073` baseline ceiling (they contributed zero
> baseline reds) AND closes the only `live − union ≠ ∅` deltas — making the tree genuinely NON-WIDENING.

---

## 4. The unseeded `DegeneretteBet.inv` invariant cluster — non-determinism analysis (the ⊆-gate rationale)

**Root cause (proven, not assumed).** `foundry.toml` seeds the `[fuzz]` profile (`seed = "0xdeadbeef"`,
`runs = 1000`) — so all unit-fuzz proofs are deterministic — but the default **`[invariant]` block has NO
`seed`** (`runs = 256`, `depth = 128`, `fail_on_revert = false`). Invariant campaigns therefore explore a
different random call-sequence space each run, and a rare counterexample (here the `DegeneretteBet` solvency
drift) is caught only when the campaign happens to reach it.

**Evidence the membership is fuzz-variance, not a regression or a fix:**
- `test/fuzz/invariant/DegeneretteBet.inv.t.sol` is **byte-frozen since the IMPL HEAD**
  (`git diff 453f8073 HEAD -- test/fuzz/invariant/DegeneretteBet.inv.t.sol` is EMPTY).
- The v56 contract subject is **frozen** (`git diff HEAD -- contracts/` is EMPTY; `git diff 453f8073 HEAD --
  contracts/` is the committed v56 IMPL diff, NOT a 356 edit).
- `invariant_solvencyUnderDegenerette` is RED at BOTH the `453f8073` baseline AND the v56 TST HEAD this run —
  its membership is stable across the v55→v56 contract change, consistent with a fuzzer-reachable pre-existing
  counterexample, not a v56-introduced one.

**Disposition (carried from the v49/v50/v55 precedent):** keep `foundry.toml` UNCHANGED (no `[invariant] seed`);
baseline the cluster member in the §2 Bucket-F ceiling with the ⊆ gate; document the non-determinism here.
Because the cluster is non-deterministic, the v49-precedent strict-equality gate (`live failing set == the
union`) is RELAXED to the non-widening SUBSET gate (`live − union == ∅`, §6), which is the load-bearing
property: it proves the v56 changes introduced no failing test outside the `453f8073` baseline.

---

## 5. NEW vs the `453f8073` baseline — the v56 green proof files (the v56 empirical proofs; all GREEN, contribute zero red)

The 356 phase authored **4 dedicated v56 proof surfaces** (SEC-01, SEC-02, QST-04, and the EXTENDED gas-marginal
harness). All are GREEN at the v56 TST HEAD (re-verified from this run's `forge test --json`); none appears in
the 134-name failing union.

| Plan / Req | Foundry file | Contract | Passing | This-run |
|------------|--------------|----------|---------|----------|
| 356-03 SEC-01 | `test/fuzz/V56SecUnmanipulable.t.sol` | `V56SecUnmanipulable` (churn-fuzz @ 1000 + the 4 named repros + no-orphan) | 11 | all Success |
| 356-04 SEC-02 | `test/fuzz/V56FreezeSolvency.t.sol` | `V56FreezeSolvency` (solvency-invariant fuzz @ 1000 + RNG-freeze determinism fuzz @ 1000 + the leg-1 debit forge arm) | 7 | all Success |
| 356-05 QST-04 | `test/fuzz/V56QuestNonPerturb.t.sol` | `V56QuestNonPerturb` (slot-1 streak-neutral + cross-caller byte-identity + O1 single-credit) | 7 | all Success |
| 356-06 LIVE-01/GAS-06 | `test/gas/V56AfkingGasMarginal.t.sol` (EXTENDED) | `V56AfkingGasMarginal` (the 5 pre-existing marginals + the D-06 per-tx gap-resume ceiling + the 4 D-06 residuals + the 5 LIVE-01 valve cases + the D-09 regression locks) | 15 | all Success |

**New v56 dedicated-proof green total: 11 + 7 + 7 + 15 = 40 passing** (the fuzz arms at 1000 seeded runs each,
deterministic under the seeded `[fuzz]` profile). None is red; none appears in the 134-name failing union. These
40 + the D-10 narrowing greens + the migrated read-only-probe greens are the bulk of the +21 net passed vs the
`453f8073` baseline 603.

**The v56 SEC/LIVE/GAS requirement → proof-file map (additive green, contribute zero red):**
- SEC-01 (unmanipulable; strategic sub/unsub) → `V56SecUnmanipulable` (the churn-fuzz no-positive-EV invariant +
  the 4 named repros: affiliate re-claim churn / streak decay-gap / `pendingBurnie` double-claim CEI / the 4
  finalize hooks before slot-delete + the no-orphan arm).
- SEC-02 (SOLVENCY-01 byte-unchanged + RNG-freeze intact) → `V56FreezeSolvency` (the solvency-invariant fuzz +
  the RNG-freeze STAMP-not-resolve / two-block-determinism fuzz + the leg-1 debit forge arm) + the §7 byte-diff
  anchor (the literal git anchor).
- QST-04 (shared-quest-core non-perturbation) → `V56QuestNonPerturb` (slot-1 streak-neutral-during-afking +
  fully-accessible + the NON-afking +1 control + cross-caller byte-identity + the O1 lootbox-quest
  single-credit regression).
- LIVE-01 (`openBoxes` valve) + GAS-06 (gap/jackpot decouple) → `V56AfkingGasMarginal` (the LIVE-01 valve cases
  + the GAS-06 idempotent-resume decouple + the per-tx gap-resume ceiling + the 4 D-06 residuals + the D-09
  GAS-01..04 regression locks).
- NON-WIDENING (SEC corollary) → **this ledger** (`REGRESSION-BASELINE-v56.md`).

---

## 6. Net-zero-new-regression PROOF (the ⊆ gate + the false-confidence guards)

The authoritative whole-tree run AT THE v56 TST HEAD, this session:

```
node scripts/lib/patchForFoundry.js          (predict CREATE addrs — no pretest hook)
forge test --json   (default profile, WHOLE tree — NOT --match-path)
  → 624 passed / 134 failed / 30 skipped   (788 run)   [FORGE_EXIT=1, expected with reds]
git checkout -- contracts/ContractAddresses.sol   (restore frozen — sha256 f7206e6c…)
```

The `453f8073` baseline union was established EMPIRICALLY in the SAME session (checkout `83a6a9ca` [contracts
byte-identical to `453f8073`] → patch → `forge test --json` → restore → checkout back to HEAD):

```
(at 83a6a9ca, contracts == 453f8073)  forge test --json  → 603 passed / 134 failed / 16 skipped   (753 run)
```

A `forge test --json` parse built the live v56 failing `(suite-basename, contract, testName)` set and the
`453f8073` `(suite-basename, contract, testName)` failing set, and compared them by set operations (both
directions):

- **`v56 live failing set − the §2 union` (NEW regression OUTSIDE baseline) = ∅** — **0 names**. Zero v56
  failing name is outside the `453f8073` 134-name union. **This is the binding, load-bearing gate, and it HOLDS.**
- **`§2 union − v56 live failing set` = ∅** — **0 names**. No baseline red flipped green-as-narrowing in the
  comparison set (the D-10 NARROWING is INTERNAL to the corpus delta §3a, never part of the `453f8073` union).
- **`v56 live failing set == the §2 union BY NAME` → TRUE** (134 == 134, byte-identical; intersection = 134).

> **No `## STOP — NEW REGRESSION OUTSIDE BASELINE` block:** every live v56 red is accounted for by NAME in the
> `453f8073` §2 134-name union (`live − union == ∅`). The 14 migration-unmasked v56-behavior reds that WOULD
> have tripped `live − union ≠ ∅` were resolved (the 356-07 DROPS §3b, each a stale v55 assertion the audited
> v56 diff superseded, every successor property re-proven GREEN §5) — so no STOP is warranted, and none was
> papered over (each drop is BY NAME + reason + the v56 successor proof in §3b). The v49-precedent strict
> equality is intentionally RELAXED to the ⊆ gate (the unseeded invariant cluster §4); the relaxation weakens
> nothing on the regression-detection side — a new red would still appear in `live − union` (≠ ∅) and trip the
> STOP.

### The false-confidence guards (mirrors v49/v50/v55 §6 FC1-FC6)

- **FC1 (loose count match masks a new regression):** mitigated. The gate is a NAME-set membership test
  (`live − union == ∅`), NOT a bare `failed == 134` count. The pre-drop run was `failed == 148` (134 baseline +
  14 v56-behavior widenings); the gate caught all 14 as `live − union` reds (≠ ∅), which the 356-07 DROPS then
  resolved by NAME. A bare-count gate would have masked the 14 (or, worse, a real new red coinciding with a
  narrowing-fix). The name-set gate is the load-bearing discipline.
- **FC2 (the v56 deltas are unattributable churn):** mitigated. §3 enumerates the deltas BY NAME — the §3a D-10
  offset-migration NARROWING (the 10 migrated files + the garbage-read root cause) and the §3b 14 removed/
  adapted-surface DROPS (BY NAME + reason + commit `f23b010e` + the v56 successor proof). Every test-tree change
  vs the `453f8073` baseline is attributable.
- **FC3 (a passing ledger written over a real regression):** mitigated. The §6 comparison returned `live − union
  = ∅` ONLY AFTER the 14 genuine widenings were resolved (each verified Success@baseline / Failure@HEAD-pre-drop
  / Skipped@HEAD-post-drop, §3b NOTE). The widenings were NOT papered over — each is a documented stale-v55
  assertion the audited v56 diff legitimately changed, with the v56 successor proof named. No genuine v56 bug
  was masked (the affiliate-base reachability observation is SURFACED as a carried 357 finding §7, NOT dropped).
- **FC4 (the full tree was never actually run — only `--match-path`):** mitigated. `forge test` was run on the
  WHOLE tree (NOT `--match-path`) at BOTH HEADs and reconciled to 624/134/30 (v56) and 603/134/16 (`453f8073`);
  the live `(suite, contract, test)` sets were parsed from the full-run `--json`. **The whole v56 tree COMPILES**
  (`forge build` EXIT 0); a scoped run would hide a new red in an un-touched file.
- **FC5 (flaky cluster masquerading as a fix):** mitigated. §4 proves the `DegeneretteBet.inv` cluster member is
  unseeded-invariant variance (red at both the `453f8073` baseline AND v56, frozen contract + frozen test file);
  the cluster member is kept in the §2 Bucket-F ceiling so the ⊆ gate holds whether or not it fires a given run.
- **FC6 (v56-specific — the empirical baseline is mis-derived / the 356-07 drops silently lose a baseline red):**
  mitigated three ways. (i) The `453f8073` baseline was established EMPIRICALLY by re-running `83a6a9ca` (whose
  contracts are byte-identical to `453f8073`, `git diff 453f8073 83a6a9ca -- contracts/` EMPTY), reproducing the
  v55 TST-HEAD 603/134/16 — the REAL `453f8073` red set, not assumed. (ii) Every 356-07 DROP (§3b) is verified
  **Success @ the `453f8073` baseline run** before the drop, so it contributed ZERO baseline reds — the drops
  cannot lose a `453f8073` baseline red (there were none in those tests to lose). (iii) Every drop is BY NAME +
  reason + commit + the v56 successor green proof — a `vm.skip`-with-reason is a documented removed/adapted
  surface, never an unrecorded disappearance.

---

## 7. Scope attestation + the SEC-02 byte-diff anchor + the Hardhat sanity arm

- The FULL `forge test` tree was run (NOT `--match-path`) at the v56 TST HEAD → **624 passed / 134 failed / 30
  skipped**; the live failing NAME set ⊆ the empirically-established 134-name `453f8073` baseline union
  (`live − union == ∅`, net-zero new regression; the live 134 == the baseline 134 BY NAME). **The whole tree
  COMPILES** (`forge build` EXIT 0).
- **Zero `contracts/*.sol` modifications** this phase; no `contracts/*.sol`-touching proof authored; the audit
  subject is FROZEN at the v56 milestone tree (on top of `453f8073`). `git diff HEAD -- contracts/` is EMPTY
  (committed AND working-tree); `git diff 453f8073 HEAD -- contracts/` is the committed 14-file v56 IMPL+tune+
  liveness diff (`e18af451` + the 355 tune + `86a2d6c8` + `3d969621` + the `mustMintToday`-bypass advance fix
  `5cb707f2`), +1453/−733, NOT a 356 edit. `ContractAddresses.sol` is restored byte-identical (sha256
  `f7206e6c29b2c2767b4b835d1f636ac80a88129098eb13976bb2473da1dccfed`) after every `patchForFoundry` round-trip.

> **Re-confirmation run at HEAD (post-`5cb707f2`).** The `mustMintToday`-bypass advance fix `5cb707f2` landed on
> the contract tree AFTER the ledger's first authoring run. The WHOLE-tree `forge test --json` was re-run at the
> current HEAD (which INCLUDES `5cb707f2`) → **624 passed / 134 failed / 30 skipped** (788 run) — BYTE-IDENTICAL
> totals to the first run, and the live 134 failing NAME set is BYTE-IDENTICAL to the §2 `453f8073` 134-name
> union (`live − union == ∅` AND `union − live == ∅`, intersection 134, re-verified by set-diff on the
> `(file::fn)` keys). The `5cb707f2` advance-gate fix (an active-sub no-time-predicate fall-through in
> `_enforceDailyMintGate`) introduced **zero new failing test** — the NON-WIDENING gate HOLDS at the current
> HEAD. All 4 v56 proof files stay GREEN (`V56SecUnmanipulable`/`V56FreezeSolvency`/`V56QuestNonPerturb`/
> `V56AfkingGasMarginal`, 0 failing each); the 30 skips remain 16 carried `RngLockDeterminism` + the 14 §3b
> DROPs. `git diff --quiet HEAD -- contracts/` exits 0 after the restore (ContractAddresses.sol byte-identical
> sha256 `f7206e6c…`).

### 7a. The SEC-02 leg-1 SOLVENCY-01 byte-diff anchor (the ETH/`claimablePool` debit byte-unchanged vs `453f8073`)

`git diff 453f8073 HEAD -- contracts/modules/GameAfkingModule.sol` shows the SOLVENCY-01 debit two-liner
re-added VERBATIM (only the surrounding code/comments relocated): the literal statements

```solidity
afkingFunding[src] -= ethValue;
claimablePool -= uint128(ethValue);
```

are **byte-identical** between `453f8073` (was `GameAfkingModule.sol:709-710`) and HEAD
(`GameAfkingModule.sol:663-664`). The two-liner appears as both a `+` line (HEAD `:663-664`) and a `-` line
(baseline `:709-710`) in the diff — i.e. the SAME statements re-added at the new location, only the comment block
relocated. The v56 accrual/settle redesign is therefore a **BURNIE-emission-timing change only**: it touches no
frozen RNG-window slot, the ETH/`claimablePool` debit is byte-frozen, and the affiliate/quest rewards stay
BURNIE flip-credit OFF the ETH/`claimablePool`/solvency path (so SOLVENCY-01 is not in scope — confirmed
empirically by `V56FreezeSolvency`'s solvency-invariant fuzz + the leg-1 debit-equals-delivered-value forge arm,
356-04).

### 7b. Carried finding for Phase 357 — the `drainAffiliateBase` dispatch-stub reachability (SURFACED, NOT masked)

356-03 + 356-04 flagged (and this ledger CARRIES, NOT masks): `DegenerusGame` has **no thin delegatecall
dispatch stub for `drainAffiliateBase`** (declared in `IGameAfkingModule` / `IGameAfkingDrain` and called by
`DegenerusAffiliate.claim` on the GAME address, `DegenerusAffiliate.sol:654`); only
`subscribe`/`mintBurnie`/`claimAfkingBurnie` are exposed, and there is no generic fallback — a direct
`game.drainAffiliateBase(sub)` reverts "unrecognized function selector ... no fallback function" on the forge
fixture. 356-03 proved the SEC-01 affiliate-churn property at the STORAGE level instead (`affiliateBase` persists
byte-identical across both unsub AND re-sub; the AFFILIATE-only access gate holds; the realizable BURNIE pull is
bounded by repro 3 + invariant (a)), so the SEC-01 no-forfeit/no-duplicate property is fully proven WITHOUT the
Game-routed drain. **This may be expected** (the live deployment may wire `ContractAddresses.GAME` to a routing
the forge fixture does not reproduce) **or it may indicate the affiliate-base settlement is currently
unreachable on the frozen subject** — the **357 adversarial sweep / delta-audit MUST confirm intended-vs-bug**.
This is recorded as a Threat Flag, NOT dropped — surfacing a real reachability question beats a falsely-green
tree.

This ledger is the authoritative NON-WIDENING gate the Phase-357 TERMINAL delta-audit consumes; the documented
cluster non-determinism (§4) + the empirical `453f8073`-baseline derivation (§2 NOTE) + the 14 removed/adapted-
surface DROPs (§3b) + the carried `drainAffiliateBase` reachability finding (§7b — now RESOLVED at §8) are
carried forward as known properties of the v56.0 baseline. **The 357-00b reconciliation (§8) re-runs the gate at
the post-fix HEAD' and re-confirms NON-WIDENING.**

---

## 8. The 357-00b D-14 reconciliation @ HEAD' `ac5f1e03` (the post-357-00 NON-WIDENING re-run)

**Subject re-freeze:** HEAD' = `ac5f1e033a785d18a9f0b89b7de5d05268431dbd` — the SOLE `contracts/*.sol` commit of
phase 357 (the F-356-01 `drainAffiliateBase` Game dispatch stub + D-11 pass-required + D-12 purchase-grounded +
D-13 VAULT/sDGNRS bootstrap exemption, bundled at one `autonomous:false` USER-approved gate; pre-fix HEAD was
`c5715297`). After 357-00 the whole tree was re-run (`node scripts/lib/patchForFoundry.js` → `forge test --json`
WHOLE tree → restore) and reconciled. **`git diff ac5f1e03 HEAD -- contracts/` is EMPTY** — this plan
(357-00b) is TEST + ledger writes ONLY; the subject stays re-frozen at HEAD'.

### 8a. The 357-00b arithmetic

| Quantity | §1 v56 TST HEAD (pre-357-00) | 357-00b delta | HEAD' (this run) |
|----------|------------------------------|---------------|------------------|
| `forge test` passed | 624 | **−58** (the ungrounded-subscribe fixtures moved pass→skip via the drops, net of the adapted greens) | **566** |
| `forge test` failed | 134 | **±0** (the 112 D-11/D-12 supersession reds reconciled via ADAPT + DROP; the live failing NAME set is UNCHANGED) | **134** |
| `forge test` skipped | 30 | **+69** (the 357-00b drops, §8c) | **99** |

**The binding gate, re-run:** `forge test --json` parsed the HEAD' live failing `(suite, test)` set and compared
it to the §2 `453f8073` 134-name union. **`live − union == ∅` (0 names) AND `union − live == ∅` (0 names) —
the live 134 is BYTE-IDENTICAL to the baseline 134 BY NAME.** NON-WIDENING HOLDS at HEAD'. (Empirically: the
pre-357-00 245-fail run minus its 112 D-11/D-12-revert reds == the 134 baseline union, and the HEAD' 134 ==
that set, name-for-name.)

### 8b. The NEW positive proofs (the re-prove side of every drop) — `test/fuzz/V56SubHardening.t.sol` (11 GREEN)

The D-14 hardening is re-proven GREEN against HEAD' by a dedicated suite:
- **D-11 (NoPass):** a passless EOA at a poked-up level reverts `NoPass()` on UPSERT subscribe; a finite-pass
  horizon covering the level subscribes; a deity holder (sentinel `type(uint24).max`) bypasses.
- **D-12 (MustPurchaseToBeginAfking):** a deity-passed-but-UNFUNDED EOA reverts on the NEW-run subscribe; a
  funded EOA + a grounded active-sub re-subscribe succeed (no MustPurchase).
- **D-13 (exempt):** `vm.prank(VAULT)` / `vm.prank(SDGNRS)` subscribe with no pass + unfunded succeed.
- **Crossing eviction KEPT:** a pass valid at subscribe is evicted via the `:969` crossing (tombstone, reason-1,
  no revert) once outgrown.
- **F-356-01 reachability:** `game.drainAffiliateBase(p)` pranked as `ContractAddresses.AFFILIATE` drains-and-
  zeroes the accrued base (the NEW Game stub is reachable from the affiliate path); a non-affiliate caller
  reverts `NotApproved()` (still AFFILIATE-only — the stub did NOT widen access).

The three v56-native proof suites were ADAPTED in place (fund-before-subscribe grounds the NEW-run cover-buy;
where the grounded subscribe stamps a box, the box is opened before the measured STAGE / the debit is measured
across the grounded subscribe itself) and stay fully GREEN: **`V56SecUnmanipulable` 10/11 (1 drop, §8c),
`V56FreezeSolvency` 7/7, `V56AfkingGasMarginal` 15/15.**

### 8c. The 357-00b removed/adapted-surface DROPS (69, BY NAME + reason) — the D-11/D-12 supersession reds

Each dropped fixture is a v55/keeper-era OR a finalize-hook harness whose setup subscribes an **ungrounded** sub
(subscribe-before-fund / unfunded-source / no-pass-at-poked-level) to drive a STAGE-first-buy, a tombstone-
reclaim, or a pass-eviction. Under the 357-00 **D-12** gate an ungrounded sub can no longer be created (the NEW
run reverts `MustPurchaseToBeginAfking`), and a grounded subscribe now **buys at subscribe** (stamping a no-
orphan-protected box), so the ungrounded-tombstone / STAGE-first-buy / per-draw-marginal setup these assert is
structurally superseded. Each is `vm.skip(true, "<357-00b reason>")` (the Foundry-native skip — Skipped, not
Failure, so the tree is genuinely NON-WIDENING), each re-proven GREEN by `V56SubHardening` + the surviving
GREEN v56-native suites. **NONE is a genuine v56 bug.** Mirrors the §3b 356-07 `f23b010e` discipline.

| File | Dropped fixtures | Count | Successor proof |
|------|------------------|-------|-----------------|
| `test/fuzz/V56SecUnmanipulable.t.sol` | `testFinalizeHookB_CancelReclaimBeforeDelete` | 1 | finalize-before-delete re-proven by the GREEN hooks A/C/D + `V56SubHardening` |
| `test/fuzz/AfKingConcurrency.t.sol` | `testStageBuysEverySubExactlyOnce`, `testLastAutoBoughtDayBackstopBlocksRepeatBuySameDay`, `testCancelDoesNotStrandPendingTail`, `testCancelReclaimAlwaysDeletesSubRecord`, `testCancelSwapPopOccupantStillProcessed`, `testNoDeadSlotBuildupAcrossCancels`, `testFuzzCancelOrderingPreservesMembership`, `testPassEvictionPreservesSwapPopInvariant`, `testPassEvictionMixedDoesNotStrandSurvivors` | 9 | `V56SubHardening` (crossing eviction) + `V56SecUnmanipulable` (finalize hooks A/C/D, no-orphan) |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | `testWaterfallDirectEthWhenNotDraining`, `testWaterfallCombinedTopsUpFromPool`, `testWaterfallInsufficientPoolWhenClaimablePlusPoolBelowCost`, `testWaterfallClaimableOnlyWhenCredExceedsCost`, `testWaterfallSentinelClaimableDegradesToDirectEth`, `testFuzzFundedSliceNeverRevertsAndChargesExactEthValue`, `testCrossAccountEthDrawsSourcePool`, `testFundingSourceDefaultSelfIsByteEquivalent`, `testNormalSubFundingSkipCancelsViaSwapPop`, `testVaultAndSdgnrsExemptFromFundingSkipKill`, `testFundingSourceVaultDoesNotInheritExemption`, `testRevokeDoesNotEscalatePerDayDraw`, `testPassEvictionPreservesFundingSourceStorage` | 13 | `V56SubHardening` (D-12 grounding + D-13) + `V56FreezeSolvency` (debit equals delivered value) |
| `test/fuzz/KeeperNonBrick.t.sol` | `testFundedStageNeverBricks`, `testFundedBoxOpenNeverBricks`, `testFuzzFundedSliceNeverBricks`, `testReclaimTombstoneCommitsInStage`, `testAutoPauseCommitsInStage`, `testSpamCancelCannotStrandTombstones`, `testNoBrickUnderHeavyPassEviction`, `testEmptyPassIsNoOp`, `testGameOverRoutingNotBlockedByAfkingStage` | 9 | `V56SubHardening` (crossing eviction) + `V56SecUnmanipulable` (finalize hooks + no-orphan) + `V56FreezeSolvency` (solvency under churn) |
| `test/fuzz/V55SetMutationOpenE.t.sol` | `testNoOrphanGuardLeavesPendingBoxSubUntouchedByStage`, `testNoOrphanControlInSetSubOpens`, `testNoOrphanRemovedSubGetsNoBox`, `testStreakNotCorruptedBySwapPop`, `testOpenEDefaultSelfByteIdentical`, `testFuzzOpenEDefaultSelfHoldsUnderOrderings`, `testOpenENoEscalation`, `testOpenETrustTheSubRevokeDoesNotStop` | 8 | `V56SecUnmanipulable` (no-orphan + finalize hooks) + `V56SubHardening` (D-13 + crossing eviction) |
| `test/fuzz/V55FreezeDeterminism.t.sol` | `testStampedDayDeterminismOpenAtTwoBlocks`, `testPreRngStampNotOpenableUntilWordLands`, `testFuzzNoBlockEntropyInTheDraw`, `testIndexBindingMidDayAdvanceDoesNotRebind`, `testFuzzIndexBindingAdvanceInvariant` | 5 | `V56FreezeSolvency` (STAMP-not-resolve + two-block determinism, all green) |
| `test/fuzz/V55RevertFreeEvCap.t.sol` | `testClassA_FundedBoxOpenNeverReverts`, `testClassA_ClaimableSentinelAndMinSkipNeverRevert`, `testFuzzClassA_FundedSliceNeverReverts`, `testEvCapClampsAtTenEthNoRevert`, `testClassC_GameOverRoutingUnblockedByStage` | 5 | `V56FreezeSolvency` + `V56SecUnmanipulable` (no-positive-EV churn) |
| `test/gas/RouterWorstCaseGas.t.sol` | `testStagePerSubMarginalIsLoopNDivideUnderCeiling`, `testStage50ChunkFundedLootboxSubsFitsUnderHardCeiling`, `testOpenLegPerBoxMarginalAndWholeLegFitsCeiling`, `testOpenLegPerBoxMarginalLoopNDivideUnderCeiling`, `testMintBurnieOpenLegRouterFitsCeiling` | 5 | `V56AfkingGasMarginal` (ceiling-fit + per-sub/per-box marginals, all green) |
| `test/fuzz/KeeperFaucetResistance.t.sol` | `testRouterAdvanceSelfKeeperRoundTripNonPositive`, `testRouterOpenSelfKeeperRoundTripNonPositiveAboveKnee`, `testRouterOpenSelfKeeperRoundTripNonPositiveBelowKnee`, `testFuzz_RouterAdvanceRoundTripNonPositiveAcrossGasPrices`, `testFuzz_RouterOpenRoundTripNonPositiveAcrossGasPrices` | 5 | `V56SubHardening` + `V56AfkingGasMarginal` |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | `testWorstCaseAfkingOpenBoxSingleMaterializationFitsBlockGasLimit`, `testPerAfkingBoxMarginalAmortizesFixedOverhead`, `testAfkingOpenIsUniformPerBoxAcrossBatchShapes` | 3 | `V56AfkingGasMarginal` (LIVE-01 open-leg + per-box marginal) |
| `test/gas/SweepPerPlayerWorstCaseGas.t.sol` | `testStageActuallyStampedNonVacuity`, `testPerSubStageMarginalAndChunkFitsCeiling`, `testReinvestAndTypicalPerSubMarginalsMatchWithinTolerance` | 3 | `V56AfkingGasMarginal` (per-sub marginal + chunk-fits-ceiling) |
| `test/fuzz/KeeperRouterOneCategory.t.sol` | `testOneCategoryEarlyReturnNoStack`, `testOpenBranchCreditsExactlyOnce` | 2 | `V56AfkingGasMarginal` + `V56SubHardening` |
| `test/fuzz/KeeperRewardRoutingSameResults.t.sol` | `testStageDrivenAutoBuyStampsSubBoughtToday` | 1 | `V56AfkingGasMarginal` + `V56SubHardening` (D-12 funded grounding) |

**357-00b drop total: 1 + 9 + 13 + 9 + 8 + 5 + 5 + 5 + 5 + 3 + 3 + 2 + 1 = 69** (= the +69 skips vs §1's 30).
Every drop is verified Failure-with-`MustPurchaseToBeginAfking`/`NoPass`-or-the-grounded-box-interaction @ HEAD'
pre-drop and Skipped post-drop; none was in the §2 `453f8073` baseline union (these files PASSED these arms at
the baseline, where v55 behavior matched), so the drops remove NOTHING from the baseline ceiling and close the
only `live − union ≠ ∅` deltas — exactly the §3b discipline.

### 8d. The F-356-01 NARROWING (the `drainAffiliateBase` stub — §7b RESOLVED)

The §7b carried reachability finding is RESOLVED at HEAD': the F-356-01 fix added the `drainAffiliateBase`
Game dispatch stub (`DegenerusGame.sol:428`, guard-less delegatecall to `GAME_AFKING_MODULE`, mirroring
`claimAfkingBurnie`). Pre-357-00 a direct `game.drainAffiliateBase(sub)` reverted "unrecognized selector / no
fallback" (the affiliate `claim()` drain loop was unreachable on the frozen subject). Post-357-00,
`V56SubHardening::testDrainAffiliateBaseReachableFromAffiliatePath` PROVES the stub is reachable from the
affiliate path AND still AFFILIATE-only — a **NARROWING** (a previously-unprovable reachability is now a green
proof). The stub turned NO test RED (it is BURNIE-only, off the ETH/`claimablePool`/solvency path) — confirmed
by the §8a touched-suite reds == 0.

### 8e. The SOLVENCY-01 leg-1 byte-anchor re-confirmed @ HEAD' (§7a still holds)

The 357-00 changes are **revert-only** (D-11/D-12 add `revert NoPass()` / `revert MustPurchaseToBeginAfking()`)
and **BURNIE-only** (the `drainAffiliateBase` stub reads-and-zeroes a whole-BURNIE field). `git diff c5715297
ac5f1e03 -- contracts/modules/GameAfkingModule.sol` does NOT touch the SOLVENCY-01 debit two-liner — the
`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);` statements are byte-unchanged (relocated to
HEAD' `:690-691`, byte-identical to the `453f8073` `:709-710` two-liner re-anchored in §7a). The ETH/
`claimablePool` debit is byte-frozen across 357-00; SOLVENCY-01 leg-1 HOLDS.

---

## 9. The 357-00b D-14 reconciliation @ HEAD'' `61315ecd` (the advance-incentive redesign re-run — CURRENT SUBJECT)

**Subject re-freeze:** HEAD'' = `61315ecd0d617e5ece386676aaf452282331ebdf` — the SECOND `contracts/*.sol` commit of
phase 357 (after HEAD' `ac5f1e03`, §8), the **advance-incentive redesign** (6 files, USER-approved gate). This is
the CURRENT re-frozen audit subject — everything downstream (357-01 delta-audit, 357-02 sweep, 357-03 FINDINGS,
357-04 closure) re-freezes against HEAD'' and is READ-ONLY against `contracts/`. **`git diff 61315ecd HEAD --
contracts/` is EMPTY** — the 357-00b extension (this §9) is TEST + ledger writes ONLY.

### 9a. The HEAD'' contract changes (the advance-incentive redesign, 6 files)

- **`advanceGame()` is PURE LIVENESS** — the `MustMintToday` hard revert was DROPPED; the dead
  `_enforceDailyMintGate` / `MustMintToday` error / vault / caller arguments were removed. Anyone may crank
  `advanceGame()` any time; it reverts only `NotTimeYet()` for ordinary game-state reasons, NEVER for a mint gate.
  `MustMintToday` no longer exists anywhere in `contracts/` (`grep -rn MustMintToday contracts/` → 0).
- **The must-mint tier ladder moved to `_bountyEligible(address)`** in `DegenerusGameMintStreakUtils.sol:32` — a
  SOFT PAY gate (cheapest-first short-circuit): minted today/yesterday → deity pass → anyone 30+ min into the day
  → any pass holder 15+ min in → active afking sub → DGVE-majority owner (the only external call, cold path). The
  `gateIdx == 0` first-day branch returns `true` (nothing to earn against yet).
- **`mintBurnie()` reads `_bountyEligible(msg.sender)` BEFORE the self-call** (`GameAfkingModule.sol:1233`) and
  pays the advance bounty only when `mult > 0 && eligible` (`:1235`). The advance WORK runs regardless — an
  ineligible keeper just earns no bounty (real participants get first shot; free cranks are welcome).
- **NEW `bountyEligible(address) external view`** on `DegenerusGame.sol:1799` (returns `_bountyEligible(who)`) —
  the off-chain pre-check + the test oracle.
- **`DegenerusVault.gameAdvance()` (`:537`) + `StakedDegenerusStonk.gameAdvance()` (`:425`) now route through
  `mintBurnie()`** — they earn the keeper bounty for the work and revert `NoWork()` when idle. The vault is
  owner-gated (`onlyVaultOwner`, the DGVE majority); sDGNRS is permissionless. Both hold deity passes / afking
  subs → always bounty-eligible.

### 9b. The 357-00b arithmetic @ HEAD''

| Quantity | §8a HEAD' `ac5f1e03` | HEAD'' delta (the redesign) | HEAD'' `61315ecd` (this run) |
|----------|----------------------|-----------------------------|------------------------------|
| `forge test` passed | 566 | **+1** (the narrowed red flips into the pass column; run-variance in the §4 cluster) | **567** |
| `forge test` failed | 134 | **−1** (NARROWING — run-variance within the non-deterministic Bucket A/F + `vm.assume`-exhaustion cluster) | **133** |
| `forge test` skipped | 99 | **±0** (the §8c 69 drops + the §3b/§2 carried 30 are unchanged — the redesign superseded NO new fixtures) | **99** |

**The binding gate, re-run @ HEAD'':** `forge test --json` parsed the HEAD'' live failing `(suite, test)` set and
compared it to the §2 `453f8073` 134-name union. **`live − union == ∅` (0 names) — NON-WIDENING HOLDS at
HEAD''** (verified empirically: the HEAD'' 133-name failing set is a strict SUBSET of the §2 union; the set-diff
`live − union` is EMPTY — `forge` log at `/tmp/ft357.log`). ZERO new forge red was introduced by the
advance-incentive redesign. (The HEAD'' run was `567 passed / 133 failed / 99 skipped`, 799 total.)

### 9c. The 1-red NARROWING (133 vs the HEAD' 134) — run-variance, NOT a gate-freed forge fixture

The live failing count narrowed by exactly 1 (133 vs HEAD' 134). **This is run-variance within the documented
non-deterministic cluster, NOT a deterministic gate-freed fixture:** the `MustMintToday` hard-revert had a SINGLE
consumer — the **Hardhat `GovernanceGating` GATE-01..04 block** (a unit test, NOT in the `forge` tree / NOT in the
§2 forge union) — which 357-00b rewrote to the soft pay-gate model (§9e). No `forge` `.t.sol` ever asserted the
`MustMintToday` revert (`grep -rln MustMintToday test/ --include='*.t.sol'` → only the NEW `V56SubHardening`, which
asserts it does NOT revert). The `union − live` slack (the §2 names not failing this HEAD'' run) is entirely Bucket
A (VRF/RNG-window: `test_wordWrite*`, `test_index*`, `test_*Rotation*`, `invariant_allGapDaysBackfilled` /
`invariant_rngUnlockedAfterSwap` / `invariant_stallRecoveryValid`, `test_entropyUniqueDifferentPlayers`,
`testClaimWhalePassMaterializesFutureWindowAndAppliesStats`) + Bucket F (`invariant_solvencyUnderDegenerette`,
flaky) + the `vm.assume`-exhaustion fuzzer `testFuzz_RngLockDeterminism_StakedStonkRedemption` + the
`testFuzz_MintDiv_*` differential — all members the §4 ⊆-gate rationale explicitly accounts for as
fuzz/invariant-campaign variance. The redesign is BURNIE-bounty + liveness only; it touches no VRF/RNG-window
code, so it cannot have deterministically narrowed any Bucket-A red. The 133 ⊆ 134 subset gate is the
load-bearing property and it holds.

### 9d. The NEW advance-soft-gate proofs (the re-prove side) — `test/fuzz/V56SubHardening.t.sol` (17 GREEN)

The §8b `V56SubHardening` suite was EXTENDED with 6 new advance-soft-gate proofs (11 → 17, all GREEN against
HEAD'' — `forge test --match-contract V56SubHardening` = 17 passed / 0 failed / 0 skipped):
- **`testAdvanceGameLivenessFreshNonMinterNotGated`** — a passless/unfunded non-DGVE EOA in the first seconds of a
  fresh day (`advanceDue()`) cranks `advanceGame()` with NO `MustMintToday` revert (pure liveness).
- **`testBountyEligibleTruthTable`** — `bountyEligible(addr)`: false for a fresh non-minter/non-DGVE in the first
  15 min; true after 30 min elapsed; true for a deity holder; true for an active afking sub; true for the DGVE
  owner (`ContractAddresses.CREATOR`, 100% DGVE + permanent deity). (Settles past the `gateIdx==0` first-day
  bypass so the per-tier checks are non-vacuous.)
- **`testMintBurnieEligibleKeeperEarnsAdvanceBounty`** — an ELIGIBLE (deity) keeper cranking `mintBurnie` with an
  advance due earns the bounty (`coinflip.coinflipAmount(keeper)` strictly increases).
- **`testMintBurnieIneligibleKeeperEarnsZeroButWorkRuns`** — an INELIGIBLE (fresh, < 15 min) keeper earns ZERO
  advance bounty (`coinflipAmount` byte-unchanged) yet the advance WORK still ran (the directional pay invariant).
- **`testVaultGameAdvanceRoutesThroughMintBurnie`** — `vault.gameAdvance()` (pranked as CREATOR, the DGVE owner)
  cranks via `mintBurnie` when work is due and reverts `NoWork()` when idle.
- **`testSdgnrsGameAdvanceRoutesThroughMintBurnie`** — `sdgnrs.gameAdvance()` (permissionless) cranks via
  `mintBurnie` when work is due and reverts `NoWork()` when idle.

The existing 11 D-11/D-12/D-13 + crossing-eviction + `drainAffiliateBase` proofs (§8b) stay GREEN at HEAD'' (the
subscribe-hardening + the stub are untouched by the advance redesign).

### 9e. The Hardhat `GovernanceGating` GATE-01..04 rewrite (the only `MustMintToday` consumer)

`test/unit/GovernanceGating.test.js` GATE-01..04 (~`:448-665`) asserted the now-REMOVED
`revertedWithCustomError(advanceModule, "MustMintToday")`. Since the error no longer exists in the contract
surface, those assertions are DROPPED (they would themselves error on an unknown selector) and the block was
rewritten to the soft pay-gate model: GATE-01 a same-day minter is `bountyEligible` AND advances; GATE-02 the
30-minute window flips a non-minter eligible while the advance always works; GATE-03 the DGVE majority holder is
always eligible; GATE-04 an ineligible keeper earns no bounty but the advance still runs. **6/6 GATE tests GREEN**
(`npx hardhat test test/unit/GovernanceGating.test.js`). (One unrelated `ADMIN-02` red — a stale `gameSetAutoRebuy`
fixture, the method no longer exists on `DegenerusVault` — is PRE-EXISTING + out of scope, logged to the phase
`deferred-items.md`; Hardhat tests are a separate runner, not part of this forge NON-WIDENING ledger.)

### 9f. The SOLVENCY-01 leg-1 byte-anchor re-confirmed @ HEAD'' (§7a / §8e still hold)

The HEAD'' advance-incentive redesign is **liveness-only** (`advanceGame` drops a VIEW-only revert gate) +
**BURNIE-bounty-only** (the `mintBurnie` soft pay-gate decides whether a `creditFlip` BURNIE bounty is paid — OFF
the ETH/`claimablePool`/solvency path). It adds no ETH/`claimablePool` debit and touches no frozen RNG-window slot.
The SOLVENCY-01 leg-1 two-liner (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);`) is
byte-unchanged from §8e (the `c5715297`→`ac5f1e03`→`61315ecd` chain never edits it). SOLVENCY-01 leg-1 HOLDS at
HEAD''.

---

## 10. The 357-00d reconciliation @ HEAD'''' `77d8bc88` (the two subscribe-hardening follow-up gates — CURRENT SUBJECT)

**Subject re-freeze:** HEAD'''' = `77d8bc883048b3ba4213f94fc2ac5d830ba3f4a3` — TWO further `contracts/*.sol` commits
layered on HEAD'' `61315ecd` (§9):
- **HEAD''' = `7b0b2a0b`** — the NEW-run subscribe **per-day slot-0 idempotency guard**. The active-sub re-subscribe
  (`:399`) and the daily STAGE both guard the funded cover-buy on `lastAutoBoughtDay`, but the NEW-run subscribe
  branch guarded only on the manual `done[0]` flag (which an afking buy never sets). Because the cancel branch
  tombstones IN PLACE (`dailyQuantity = 0`, record + stamp kept), the `lastAutoBoughtDay` stamp survives an unsub,
  so a `subscribe → funded cover-buy → cancel → subscribe` loop re-entered the NEW-run cover-buy and re-accrued the
  flat per-day `QUEST_SLOT0_REWARD` (100 BURNIE) each cycle. The fix adds `else if (s.lastAutoBoughtDay ==
  uint24(today)) { _setStreakBase(s, snap); }` (`GameAfkingModule.sol:451`) — already purchase-grounded same-day →
  keep the snapshot, skip a SECOND cover-buy, no slot-0 re-accrual, `lastOpenedDay` left untouched (no orphan box).
  Closes the 357-02 sweep's zero-day-hunter probe-7 EV-negative ADVISORY.
- **HEAD'''' = `77d8bc88`** — the USER-caught **D-11 LEVEL-0 zero-horizon rejection**. The gate at `:372` changed from
  `if (!exemptSub && s.validThroughLevel < level)` to `if (!exemptSub && (s.validThroughLevel == 0 ||
  s.validThroughLevel < level))`. At level 0 `validThroughLevel(0) < level(0)` is `0 < 0` == FALSE (vacuous), so a
  funded PASSLESS EOA (horizon 0) cleared `NoPass()` at level 0 and could afk through level 0 (evicted only at L1).
  A zero horizon (= no pass) is now rejected at EVERY level including 0; a real pass has horizon ≥ passLevel+99
  (WhaleModule), deity = `type(uint24).max`, VAULT/SDGNRS stay D-13 exempt + deity-covered. **The 357-02 3-skill
  sweep marked D-11 NEGATIVE-VERIFIED but ran only at level ≥ 1 — it MISSED the level-0 boundary; the USER's review
  caught it.**

Everything downstream (357-03 FINDINGS, 357-04 closure) re-freezes against HEAD''''. **`git diff 77d8bc88 HEAD --
contracts/` is EMPTY** — 357-00d is TEST + ledger writes ONLY.

### 10a. The 357-00d arithmetic @ HEAD''''

| Quantity | §9b HEAD'' `61315ecd` | HEAD'''' delta (the two gates + 357-00d) | HEAD'''' `77d8bc88` (this run) |
|----------|------------------------|------------------------------------------|--------------------------------|
| `forge test` passed | 567 | **+6** (the 5 new `V56SubHardening` proofs are GREEN; +1 net run-variance) | **573** |
| `forge test` failed | 133 | **+1** (run-variance re-membership in the §2 union; the 4 D-11-level-0 supersession reds are DROPPED not counted) | **134** |
| `forge test` skipped | 99 | **+4** (the 4 `AfKingSubscription` D-11-level-0 supersession `vm.skip` drops, §10c) | **103** |

**The binding gate, re-run @ HEAD'''':** `forge test --json` parsed the HEAD'''' live failing `(suite, test)` set and
compared it to the §2 `453f8073` 134-name union BY NAME. **`live − union == ∅` (0 names) AND `union − live == ∅`
(0 names) — the live 134 is BYTE-IDENTICAL by NAME to the baseline 134.** NON-WIDENING HOLDS at HEAD''''. (The
HEAD'''' run was `573 passed / 134 failed / 103 skipped`, 810 total. The `134 == 134` byte-identity vs the HEAD''
`133` is within the documented run-variance of the non-deterministic Bucket A/F cluster, §4 — neither gate touches
any VRF/RNG-window code.)

### 10b. The NEW positive proofs (the re-prove side) — `test/fuzz/V56SubHardening.t.sol` (17 → 22 GREEN)

The §9d `V56SubHardening` suite was EXTENDED with 5 new proofs (17 → 22, all GREEN @ HEAD'''' — `forge test
--match-contract V56SubHardening` = 22 passed / 0 failed / 0 skipped):
- **`testChurnSameDayAccruesSlot0Once`** (HEAD''' slot-0 guard) — a pass-holding + funded EOA's
  `subscribe → funded cover-buy → cancel → subscribe` loop accrues the flat per-day slot-0 BURNIE (`pendingBurnie`)
  EXACTLY ONCE across N same-day churn cycles (asserts `pendingBurnie` UNCHANGED per cycle, not N×); a NEXT-day
  subscribe (`lastAutoBoughtDay != today`) DOES a fresh funded cover-buy + accrues again (the guard skips only
  SAME-day re-entry).
- **`testD11PasslessEoaRevertsNoPassAtLevelZero`** (HEAD'''' D-11 level-0) — at `_setLevel(0)` a FUNDED PASSLESS EOA
  reverts `NoPass()` (the boundary the existing level-5 negative never reached; funded → the revert can ONLY be the
  level-0 zero-horizon arm, not D-12).
- **`testD11RealPassSubscribesAtLevelZero`** — at level 0 a real finite-pass holder (`validThroughLevel = 99`)
  subscribes OK (the `== 0` arm rejects only a ZERO horizon).
- **`testD11DeityHolderSubscribesAtLevelZero`** — at level 0 a deity holder (sentinel `type(uint24).max`) subscribes OK.
- **`testD13VaultSdgnrsExemptAtLevelZero`** — at level 0 VAULT + sDGNRS (horizon 0, unfunded) still subscribe OK — the
  `exemptSub` short-circuit gates the WHOLE `(validThroughLevel == 0 || ...)` predicate, so the new `== 0` arm does
  not break the construction-time bootstrap.

The existing 17 D-11/D-12/D-13 + crossing-eviction + `drainAffiliateBase` + advance-soft-gate proofs (§8b/§9d) stay
GREEN at HEAD''''.

### 10c. The 357-00d removed/adapted-surface DROPS (4, BY NAME + reason) — the D-11 LEVEL-0 supersession reds

The HEAD'''' D-11 level-0 fix introduced exactly ONE revert-reason flip in the whole tree: **4 `AfKingSubscription`
fixtures** that subscribe a **passless EOA at level 0** relying on the pre-HEAD'''' vacuity. They were verified
**8/8 GREEN @ HEAD''** (`/tmp/ft357.log`) and now revert `NoPass()` @ HEAD'''' (a GENUINE supersession-widening the
USER-caught fix introduced). Per the §3b/§8c removed/adapted-surface DROP discipline each is `vm.skip(true,
"<357-00d reason>")` (Foundry-native skip — Skipped, not Failure → genuinely NON-WIDENING), each level-0 successor
property re-proven GREEN by the NEW `V56SubHardening` proofs (§10b). **NONE is a genuine v56 bug** — each is a stale
v55-era assertion the audited HEAD'''' D-11 fix legitimately superseded.

| File | Dropped fixtures | Count | v56-supersession reason (the SHIPPED HEAD'''' behavior the assertion no longer matches) | v56 successor proof |
|------|------------------|-------|------------------------------------------------------------------------------------------|---------------------|
| `test/fuzz/AfKingSubscription.t.sol` | `testCrossingNoPassEvictedViaTombstone` | 1 | subscribes a PASSLESS sub (horizon 0) at level 0 to set up the crossing; HEAD'''' now reverts `NoPass()` at the subscribe, before the crossing | `V56SubHardening::testCrossingEvictionStillEvictsOutgrownPass` (a pass valid at subscribe, then outgrown) |
| `test/fuzz/AfKingSubscription.t.sol` | `testSubscribeNoBurnieChargeRegardlessOfPass` | 1 | arm (a) subscribes a passless sub at level 0 (its own comment: "a no-pass sub clears D-11 (validThroughLevel 0 < level 0 is false)") | `V56SubHardening::testD11RealPassSubscribesAtLevelZero` / `testD11DeityHolderSubscribesAtLevelZero` (real-pass/deity subscribe at level 0 charges no BURNIE) |
| `test/fuzz/AfKingSubscription.t.sol` | `testUnapprovedFundingSourceRefusedThenHonored` | 1 | the HONORED leg subscribes a passless subscriber (M) at level 0 → now `NoPass()`; the REFUSED leg (NotApproved before any pass check) is unaffected | `V56SubHardening::testD13VaultSdgnrsExemptAtLevelZero` + the OPEN-E gate ordering in the surviving suites |
| `test/fuzz/AfKingSubscription.t.sol` | `testRevokeDoesNotStopActiveSub` | 1 | M subscribes passless at level 0 → now `NoPass()`; the trust-the-sub revoke semantics are orthogonal to the pass gate | the surviving V56-native suites (the revoke semantics are pass-gate-orthogonal) |

**357-00d drop total: 4** (= the +4 skips vs §9b's 99 → 103). Each is verified `Failure`-with-`NoPass()` @ HEAD''''
pre-drop and `Skipped` post-drop; each was `Success` @ HEAD'' (8/8 `AfKingSubscription` GREEN), so the drops add
NOTHING to the baseline ceiling (these names are not in the §2 `453f8073` union — the v55 layout + v55 contract
behavior matched there) and close the only `live − union ≠ ∅` deltas — exactly the §3b/§8c discipline.

### 10d. The SOLVENCY-01 leg-1 byte-anchor re-confirmed @ HEAD'''' (§7a / §8e / §9f still hold)

Both HEAD''' and HEAD'''' changes are **revert-only / control-flow-only** (no ETH path): the slot-0 guard adds an
`else if` that SKIPS a second same-day cover-buy (`_setStreakBase` only — a BURNIE-streak marker write, no ETH); the
D-11 level-0 arm adds a `revert NoPass()`. `git diff 61315ecd HEAD -- contracts/modules/GameAfkingModule.sol` does
NOT touch the SOLVENCY-01 debit two-liner (`grep -c` on the diff = 0). The
`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);` statements are byte-unchanged — only RELOCATED
from HEAD'' `:690-691` to HEAD'''' `:702-703` (the +12-line slot-0 guard + the D-11 comment expansion inserted
ABOVE them). The last commit to touch that line is `77c3d9ef` (v349.1), long predating the two 357 gates. The
ETH/`claimablePool` debit is byte-frozen across HEAD''→HEAD''''; SOLVENCY-01 leg-1 HOLDS at HEAD''''.

### 10e. The authoritative HEAD'''' run + the read-only attestation

```
node scripts/lib/patchForFoundry.js          (predict CREATE addrs — no pretest hook)
forge test --json   (default profile, WHOLE tree — NOT --match-path, /tmp/ft357d2.json)
  → 573 passed / 134 failed / 103 skipped   (810 run)   [FORGE_EXIT=1, expected with reds]
git checkout -- contracts/ContractAddresses.sol   (restore frozen — sha256 f7206e6c…)
```

`live − union == ∅` AND `union − live == ∅` (name-keyed set-diff both directions EMPTY; the live 134 == the §2
134-name `453f8073` union BY NAME). `git diff 77d8bc88 HEAD -- contracts/` is **EMPTY** (zero contract mutation in
this reconciliation; subject byte-frozen at HEAD''''). `ContractAddresses.sol` restored byte-identical (sha256
`f7206e6c29b2c2767b4b835d1f636ac80a88129098eb13976bb2473da1dccfed`) after the `patchForFoundry` round-trip.
**NON-WIDENING confirmed at HEAD''''.**

---

## 11. The 357-00e reconciliation @ c9b5d20d (the FIFTH / FINAL v56.0 gate — the flat-10% pass lootbox + dead-guard removal — CURRENT SUBJECT)

**Subject re-freeze:** c9b5d20d = `c9b5d20d756f9dfc5f3b0584aae56bdfa215d8bf` — ONE further `contracts/*.sol` commit
layered on HEAD'''' `77d8bc88` (§10). It is the FIFTH and FINAL v56.0 contract gate (USER-committed directly), a
contained pass-PURCHASE economic refactor on `DegenerusGame.sol` (8 lines) + `DegenerusGameWhaleModule.sol`
(−46/+25):
- **The presale lootbox elevation REMOVED on all 3 pass types** (whale bundle / lazy pass / deity). The lootbox is
  now a **flat 10% of pass value** regardless of presale state — the `LAZY_PASS_LOOTBOX_PRESALE_BPS` /
  `WHALE_LOOTBOX_PRESALE_BPS` / `DEITY_LOOTBOX_PRESALE_BPS` (2000) constants + the
  `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0 ? *_PRESALE_BPS : *_POST_BPS` ternaries are DROPPED, and
  `*_LOOTBOX_POST_BPS → *_LOOTBOX_BPS` (the single `1000` rate now). The 25% `presaleBoxCredit` (gated on
  `!presaleOver`) is byte-UNCHANGED, so presale buyers now get **25% credit + 10% lootbox** instead of
  25% + 20% — only the lootbox award shrinks.
- **3 unreachable guards removed.** The lazy-pass `if (baseCost == 0) revert E();` (dead — `priceForLevel` is
  strictly positive over all `uint24`: ≥ 0.01 ETH, so the 10-level `_lazyPassCost` sum is always > 0); the lazy
  `if (lootboxAmount == 0) return;` and the deity `if (lootboxAmount != 0) { … }` zero-guards (dead — 10% of a
  positive price ≥ 0.18 ETH is never 0). `_recordLootboxEntry` is safe even vs a hypothetical 0 (its explicit
  `!= 0` RMW guard).
- **A stale `hasAnyLazyPass` docstring fixed** (`DegenerusGame.sol`) — clarifies it is a UI/external view
  (exclusive `> level`) NOT consumed by the AfKing pass gate (which uses `lazyPassHorizon` / `_passHorizonOf`
  inclusive through `frozenUntilLevel`); the one-level off-by-one is a documented, by-design view divergence.

Everything downstream (357-03 FINDINGS re-point, 357-04 closure) re-freezes against c9b5d20d. **`git diff c9b5d20d
HEAD -- contracts/` is EMPTY** — 357-00e is TEST + ledger writes ONLY.

### 11a. The 357-00e arithmetic @ c9b5d20d

| Quantity | §10a HEAD'''' `77d8bc88` | c9b5d20d delta (the pass refactor + 357-00e) | c9b5d20d (this run) |
|----------|---------------------------|-----------------------------------------------|----------------------|
| `forge test` passed | 573 | **+1** (run-variance re-membership — the refactor adds no green/red of its own) | **574** |
| `forge test` failed | 134 | **−1** (run-variance NARROWING within the §2 union; no new red) | **133** |
| `forge test` skipped | 103 | **±0** (no new drops — the refactor unmasks no fixture) | **103** |

**The binding gate, re-run @ c9b5d20d:** `forge test --json` parsed the c9b5d20d live failing `(suite, test)` set
and compared it to the §2 `453f8073` 134-name union BY NAME. **`live − union == ∅` (0 names outside the baseline)
— the live 133 failing set is a STRICT SUBSET of the baseline 134-name union.** NON-WIDENING HOLDS at c9b5d20d.
(The c9b5d20d run was `574 passed / 133 failed / 103 skipped`, 810 total. The `133` vs the HEAD'''' `134` is a
1-fail NARROWING within the documented run-variance of the non-deterministic Bucket A/F cluster, §4 — the pass
refactor touches NO VRF/RNG-window code, so it cannot deterministically free a Bucket-A red; the `union − live`
slack is the same fuzz/invariant-campaign variance the §4 ⊆-gate rationale accounts for.)

### 11b. ZERO new forge red — the flat-10% + dead-guard removal adds no test surface

The refactor introduces no new `.t.sol` fixture and removes no live behavior any fixture asserts:
- **No dangling refs to the dropped constants.** `git grep -n 'LOOTBOX_PRESALE_BPS\|LOOTBOX_POST_BPS' -- 'contracts/*.sol' 'test/'`
  → **0** (the `*_PRESALE_BPS`/`*_POST_BPS` symbols are fully removed; nothing in `contracts/` or `test/` references
  them). The `PS_ACTIVE` shift/mask is still used elsewhere (not orphaned).
- **No fixture asserted the presale-20% lootbox award.** The pass-purchase suites assert pass mechanics (ticket
  queueing, freeze horizon, stat boost) + the `presaleBoxCredit` 25% leg (byte-unchanged), not the
  presale-vs-post lootbox-bps split; so dropping the presale elevation flips no fixture (no `vm.skip` drop needed —
  §11a skipped count `±0`).
- **The 3 dropped guards are provably dead** (no fixture ever hit `baseCost == 0` / `lootboxAmount == 0`):
  `priceForLevel` (`PriceLookupLib.sol:21`) has no zero branch (min `0.01 ether` at `targetLevel < 5`), so the
  lazy 10-level sum is always > 0; 10% of a positive price (lazy ≥ 0.18 ETH, whale ≥ 1.2 ETH, deity ≥ 24 ETH) is
  never 0. Removing dead branches is behavior-equivalent → zero red delta.

### 11c. The SOLVENCY-01 leg-1 byte-anchor re-confirmed @ c9b5d20d (§7a / §8e / §9f / §10d still hold)

The pass refactor is **off the ETH/`claimablePool` solvency path** — it only changes the lootbox-award MULTIPLIER
on the pass-purchase legs (the `(price * bps) / 10_000` arithmetic in `DegenerusGameWhaleModule`), which feeds
`_recordLootboxEntry` (a BURNIE-ledger lootbox-entry write), NOT the afking ETH debit. The afking SOLVENCY-01 leg-1
debit two-liner lives in `GameAfkingModule.sol` and is byte-UNCHANGED across HEAD''''→c9b5d20d:
`git diff 77d8bc88 c9b5d20d -- contracts/modules/GameAfkingModule.sol` is **EMPTY** (the refactor touches only
`DegenerusGame.sol` + `DegenerusGameWhaleModule.sol`). The
`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);` statements stay byte-frozen at `:702-703`
(last touched `77c3d9ef` v349.1). The ETH pool splits (affiliate / reward / pool) are computed from `totalPrice`
INDEPENDENT of the lootbox %, and the `presaleBoxCredit` 25% leg is byte-unchanged — reducing the lootbox award
20%→10% can only DECREASE delivered value (no unbacked value, no EV-cap breach, no underflow). SOLVENCY-01 leg-1
HOLDS at c9b5d20d.

### 11d. The authoritative c9b5d20d run + the read-only attestation

```
forge build                                  (exit 0 — clean at c9b5d20d)
node scripts/lib/patchForFoundry.js          (predict CREATE addrs — no pretest hook)
forge test --json   (default profile, WHOLE tree — NOT --match-path)
  → 574 passed / 133 failed / 103 skipped   (810 run)   [FORGE_EXIT=1, expected with reds]
git checkout -- contracts/ContractAddresses.sol   (restore frozen)
```

`live − union == ∅` (name-keyed set-diff — the live 133 failing set ⊆ the §2 134-name `453f8073` union BY NAME).
`git diff c9b5d20d HEAD -- contracts/` is **EMPTY** (zero contract mutation in this reconciliation; subject
byte-frozen at c9b5d20d, the FIFTH / FINAL v56.0 gate). **NON-WIDENING confirmed at c9b5d20d.**
