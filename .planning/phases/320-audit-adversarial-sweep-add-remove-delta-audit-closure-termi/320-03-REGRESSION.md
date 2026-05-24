# Phase 320 — Regression + SOURCE-TREE FROZEN Attestation (v46.0)

**Phase:** 320 / Plan 03 · **Authored:** 2026-05-24
**Baseline:** v45.0 closure HEAD `62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` · **Phase-start HEAD (FROZEN ref):** `30b5c89c`
**Posture:** LEAN regression (v44 §5 style); read-only; zero `contracts/` + zero `test/` mutation. Every cited file:line re-grep-verified at HEAD on the OPEN-E-bearing main tree.

---

## §1 Regression Frame
Baseline 62fb514b… → subject HEAD (current). The v46.0 milestone is a feature milestone (new `AfKing.sol` keeper + OPEN-E funding-source) + a legacy removal (AFKing mode + free ETH auto-rebuy) + the JGAS jackpot-split removal. This appendix proves the change set is NON-WIDENING (no v46 contract change broke a previously-passing test), RNG-freeze is intact (and its obligations RETIRED by the removal), the faucet is bounded, KNOWN-ISSUES + the BURNIE win/loss RNG path are byte-unmodified, and the source tree is frozen for the terminal.

---

## §2 REG-01 — NON-WIDENING

`git diff --stat 62fb514b..HEAD -- contracts/ test/` — every changed file attributable to a known v46-scope commit (`df4ef365` 317 batch · `e4014f91`/`795e679d` GAS · `42140ceb`/`e1baa978` OPEN-E · `745cd63d` fixture · the 318-TST test additions):

**contracts/ (14 files, all v46-scope):**

| File | Δ | Attributed to |
| --- | --- | --- |
| `AfKing.sol` (+845, new) | new keeper | `df4ef365` (CRANK/SUB/REW) + `42140ceb`/`e1baa978` (OPEN-E) |
| `BurnieCoinflip.sol` (−93/+13) | RM auto-rebuy/afKing-mode removal + flat-75bps collapse | `df4ef365` (RM/REW) |
| `DegenerusGame.sol` (467) | crank entrypoints + keeper gate + legacy removal | `df4ef365` |
| `modules/DegenerusGameJackpotModule.sol` (376, net −) | JGAS two-call split removal + single-call daily-ETH | `df4ef365` (JGAS-01/02) |
| `DegenerusVault.sol` (60) / `StakedDegenerusStonk.sol` (41) | SUB-09 self-subscribe + subscribe-sig ripple | `df4ef365` + `42140ceb` |
| `BurnieCoin.sol` (48) | `burnForKeeper` keeper integration | `df4ef365` |
| `ContractAddresses.sol` (12) | AF_KING wiring | `df4ef365`/fixture |
| `interfaces/IBurnieCoinflip.sol` (−7) / `IDegenerusGame.sol` (32) | interface ripple | `df4ef365` + OPEN-E |
| `modules/DegenerusGameAdvanceModule.sol` (16) | JGAS single-call + crank | `df4ef365` |
| `modules/DegenerusGameMintModule.sol` (5) | crank/keeper wiring | `df4ef365` |
| `modules/DegenerusGamePayoutUtils.sol` (−58) / `storage/DegenerusGameStorage.sol` (−34) | legacy auto-rebuy state removal | `df4ef365` (RM) |

**test/ (36 files):** all v46-phase additions/updates — `CrankFaucetResistance` (SAFE-01), `CrankNonBrick`, `JackpotSingleCallCorrectness` (318-06), `RngFreezeAndRemovalProofs` (318-05), the gas suites (`CrankLeversAndPacking`, `Crank*WorstCaseGas`, `SweepPerPlayerWorstCaseGas`), the OPEN-E test-mirror sync, the fixture `DeployProtocol.sol` AfKing insertion — all attributable to 317/318/319/319.1.

**Verdict: NON-WIDENING.** Zero unattributable hunks. The v44.0 audit surfaces NOT in v46 scope (the sStonk per-day redemption accounting core; the v45 VRF-rotation `updateVrfCoordinatorAndSub` re-issue logic) are byte-unchanged — the v46 edits to `StakedDegenerusStonk.sol`/`AdvanceModule.sol` are confined to the SUB-09 self-subscribe wiring + the JGAS single-call, not the v44/v45 closure logic.

---

## §3 RNG-freeze intact under permissionless resolve
The do-work crank relaxes WHO resolves (permissionless), NOT WHEN (still post-unlock, behind the freeze guard). Re-grepped guards at HEAD:
- `DegenerusGameDegeneretteModule.sol:578` `if (rngWord == 0) revert RngNotReady();` (bet resolve freeze guard);
- `DegenerusGameDegeneretteModule.sol:452` `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();` (placement mirror);
- `DegenerusGameLootboxModule.sol:485` + `:567` `if (rngWord == 0) revert RngNotReady();` (open-box guards).

Re-attests 318-05 `RngFreezeAndRemovalProofs.t.sol` (13/13): crank bet/box resolution stays post-unlock behind `RngNotReady`; ETH winnings always land in claimable; flat 75bps unconditional. NEGATIVE-VERIFIED.

## §4 Freeze-obligation RETIREMENT (RM-02)
The ETH-auto-rebuy removal RETIRES freeze obligations (removes, does not weaken). Confirmed by the `BurnieCoinflip.sol` diff — the legacy auto-rebuy machinery is DELETED: `AFKING_RECYCLE_BONUS_BPS`, `AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS`, `DEITY_RECYCLE_CAP`, `AFKING_KEEP_MIN_COIN`, `settleFlipModeChange`, `_afKingRecyclingBonus`, `syncAfKingLazyPassFromCoin`, the deity-bonus path. The ETH auto-rebuy was a VRF consumer + 3 player-mutable in-window inputs; its removal retires those obligations. Re-attests 318-05 SAFE-04 (deterministic no-VRF-word-credit). One fewer VRF consumer; three fewer in-window player-mutable inputs. NEGATIVE-VERIFIED.

## §5 Faucet bounded
Re-attests SAFE-01 (`CrankFaucetResistance.t.sol`, present in the v46 test set): self-crank/Sybil round-trip ≤ 0 (purchase-gate + gas-peg + coinflip-credit illiquidity), WWXRP currency==3 earns zero, one-reward-per-item, no pre-RNG-word resolution. The CR-01 box-peg fix (`795e679d`, 71_203 per-box marginal) + the WR-01 multi-box round-trip guard keep the round-trip ≤ 0. Cross-ref 320-01 SWP-GRIEF.faucet-roundtrip (NEGATIVE-VERIFIED). NEGATIVE-VERIFIED.

---

## §6 Suite baseline check (vs the named 44-failure v45-derived baseline)

**HEAD full suite (`forge test`, default profile): `565 passed, 45 failed, 16 skipped (626 total)`.**

The documented post-318-repair baseline (318-01-SUMMARY §"Post-Repair Full-Suite Baseline") was a **named 44-failure set**, and it held at **44** through Phase 319 (319-03: 549/44). At HEAD the suite has grown to 626 total (601→626, +25 tests from the 319/319.1 additions) and the fail count is **45**.

**Classification — 44 of 45 failures are BYTE-IDENTICAL to the named v45-derived baseline:**

| Baseline family (318-01:128-135) | HEAD failures (match) |
| --- | --- |
| panic 0x11 ticket-routing/queue (20) | TicketRouting ×9 + QueueDoubleBuffer ×9 + TicketEdgeCases ×2 — ALL present |
| RngLocked()-guard (TicketRouting, 3) | testRngGuardRevertsOnFFKey / ScaledRevertsOnFFKey / RangeRevertsOnFirstFFLevel — present |
| InvalidBet (DegeneretteFreezeResolution, 3) | all 3 present |
| freeze (PrizePoolFreeze, 2) | testFreezeUnfreezeRoundTrip + testMultiDayAccumulatorPersistence — present |
| VRF behavioral (2) | test_midDayRequest_doesNotBlockDaily + test_gapBackfillWithMidDayPending_fuzz — present |
| lootbox/boon/drain (5) | testLootboxNearRollTicketsProcessed, testBindingConsistencyDailyDrain, testGameOverDrainsQueuedTickets, test_lootboxBoonAppliedDespiteExistingCoinflipBoon, test_parametricSweep_crossCategoryBoonFromLootbox — present |
| GNRUS charity (1) | test_gap_gnrus_propose_vote_paths — present |
| solvency/VRF invariants (8) | ethSolvency, solvencyUnderDegenerette, allGapDaysBackfilled, rngUnlockedAfterSwap, stallRecoveryValid, gameSolvencyUnderVaultOps, solvencyUnderPressure, solvencyAcrossLevels — present |

**The 45th failure (the only delta vs the named 44):** `test/gas/CrankLeversAndPacking.t.sol::testGas04PackingAndNoNewHotPathStorageSourcePresence` — `panic: arithmetic underflow (0x11)`.

**This is a STALE v46-internal TEST assertion, NOT a contract regression.** `testGas04` is a source-STRING test that asserts the **pre-OPEN-E `Sub` struct layout** — it looks for `bool drainGameCreditFirst;` and `bool useTickets;` as standalone struct fields and asserts a 7-field/13-byte sum. But **OPENE-01 (319.1, USER-APPROVED) deliberately collapsed those two bools into the `flags` byte and added `address fundingSource`** — the HEAD `Sub` is `{uint8 dailyQuantity; uint32 lastSweptDay; uint32 paidThroughDay; uint8 reinvestPct; uint8 flags; address fundingSource;}` (`AfKing.sol:79-86`, one slot, 31 used bytes). The field-lookup helper underflows when the dead bool fields are absent. **The contract is correct (the repack is the intended, audited OPENE-01 design — 320-01 SWP-OPENE NEGATIVE-VERIFIED + 319.1 VERIFICATION 13/13); only the gas test's source-presence assertion was not updated when 319.1 repacked `Sub`.**

**Verdict: ZERO v46 CONTRACT regressions.** No test of previously-passing contract behavior broke due to a v46 contract change. The single delta vs the named 44-baseline is a test-only staleness (`testGas04`) introduced by 319.1's OPEN-E repack failing to update the gas source-presence assertion. **Test-only fix deferred to v47.0** (bundles with the AfKing test work in `PLAN-V47-AFKING-CANCEL-TOMBSTONE.md`; the v46.0 TERMINAL is SOURCE-TREE FROZEN incl. test/, so no in-phase test mutation). The closure verdict's regression clause is amended to record "44 pre-existing baseline + 1 stale-test (testGas04, test-only, deferred v47.0); 0 contract regressions."

---

## §7 KNOWN-ISSUES.md byte-unmodified
`git diff 62fb514b..HEAD -- KNOWN-ISSUES.md` → **empty** (byte-unmodified vs the v45 baseline). sha256 anchor (current): `75b3b4bc79a96c7e…`. NEGATIVE-VERIFIED.

## §8 BURNIE win/loss RNG path byte-unmodified
`processCoinflipPayouts` (`BurnieCoinflip.sol:756`) + `bool win = (rngWord & 1) == 1;` (`:788`) are **byte-UNMODIFIED** vs v45: the diff `62fb514b..HEAD -- contracts/BurnieCoinflip.sol` touches ZERO of the win/loss-resolution lines (`processCoinflipPayouts` / `rngWord & 1` / `bool win` / `_resolveDay`). The 106-line BurnieCoinflip.sol delta is entirely the RM-scope auto-rebuy/afKing-mode removal (the deleted `AFKING_*` constants, `settleFlipModeChange`, `_afKingRecyclingBonus`, `syncAfKingLazyPassFromCoin`, deity-bonus path). The win/loss entropy consumption (`rngWord & 1`) is unchanged. NEGATIVE-VERIFIED.

## §9 SOURCE-TREE FROZEN attestation
`git diff 30b5c89c -- contracts/ test/` → **empty** (zero in-phase `contracts/` + `test/` mutation across Phase 320). No RE-PASS was triggered in v46.0 (the one Tier-1 finding, H-CANCEL-SWAP-MISS, was USER-adjudicated DEFER-to-v47.0 per 320-01 §8; the testGas04 staleness is likewise test-only deferred). SOURCE-TREE FROZEN HELD. (Commits since `30b5c89c` are planning-only `.planning/` docs.)

## §10 Forward-cite for FINDINGS-v46.0.md §5 + §6 (Plan 04)
`<FINDINGS-v46.0-§5/§6-CROSS-CITE-PLACEHOLDER>` — Plan 04 consolidates §2 REG-01 NON-WIDENING + §6 suite baseline (565/45, 44 baseline + 1 stale-test) into the FINDINGS §5 LEAN regression appendix, and §7/§8 (KNOWN-ISSUES + BURNIE-RNG byte-unmodified) into the FINDINGS §6 KI walkthrough.

---

*Regression authored 2026-05-24 on the OPEN-E-bearing main tree. NON-WIDENING (zero v46 contract regressions); RNG-freeze intact + obligations retired; faucet bounded; KNOWN-ISSUES + BURNIE-RNG path byte-unmodified; suite 565/45 (44 named-baseline + 1 stale testGas04, test-only deferred v47.0); SOURCE-TREE FROZEN held (git diff 30b5c89c -- contracts/ test/ empty).*
