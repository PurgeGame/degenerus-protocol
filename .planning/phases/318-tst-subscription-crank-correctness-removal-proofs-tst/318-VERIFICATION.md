---
phase: 318-tst-subscription-crank-correctness-removal-proofs-tst
verified: 2026-05-23T23:15:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 318: TST — Subscription + Crank Correctness + Removal Proofs Verification Report

**Phase Goal:** Ship Foundry coverage proving BOTH halves of the v46 add+remove diff against the Phase-317 IMPL. Primary requirements: SAFE-01 (faucet bounded), SAFE-02 (non-brick: crankBets/crankBoxes/batchPurchase), SAFE-03 (concurrency self-partition), SAFE-04 (RNG-freeze intact + freeze obligations retired), JGAS-03 (305-winner single-call daily-ETH jackpot). Plus the deploy-fixture repair (318-01) that un-bricked the suite.
**Verified:** 2026-05-23T23:15:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SAFE-01: Faucet-resistance PASSES — self-crank/Sybil round-trip <= 0; WWXRP earns 0; one-reward-per-item enforced; no resolve before RNG word lands | VERIFIED | `CrankFaucetResistance` suite: 10/10 PASS (incl. 1000-run fuzz over gas prices). Assertions: fixed peg `CRANK_RESOLVE_BET_GAS_UNITS*0.5 gwei` is structurally below real cost at any realistic price (>=1 gwei); credit lands as illiquid coinflip stake (liquid BURNIE balance unchanged); WWXRP currency==3 reverts with zero creditFlip; BatchAlreadyTaken on re-crank; RngNotReady caught by try/catch on pre-word crank. Run verified live: `Suite result: ok. 10 passed; 0 failed`. |
| 2 | SAFE-02: Non-brick PASSES — one reverting/stale/not-ready player skipped across BOTH cranks AND batchPurchase; cancel un-brickable; reentrant sweep/cancel cannot double-buy | VERIFIED | `CrankNonBrick` 12/12 + `AfKingSubscription` 7/7 PASS. CrankNonBrick proves: poisoned middle-item isolated across crankBets (fuzz 1000 runs over poison position), crankBoxes (lootboxEth-zeroed entry caught by try/catch), and batchPurchase (sub-LOOTBOX_MIN slice refunded to keeper, fuzz 1000 runs). Reentrancy: bubbling re-entry reverts whole call (attacker gets nothing); swallowing variant yields single payout. Cancel: setDailyQuantity(0) always succeeds, full _poolOf withdrawable (fuzz). AfKingSubscription: pass-OR-pay (deity free-extend vs no-pass burnForKeeper), all-or-nothing burn (shortfall auto-pauses, at-cost full burn). Run verified live. |
| 3 | SAFE-03: Concurrency + every-entry-every-day PASS — two same-block sweeps self-partition; no double-buy; tombstone no dead-slot buildup; subscription correctness proven | VERIFIED | `AfKingConcurrency` 10/10 (incl. 1000-run fuzz: sum==N, max-per<=1 across any split) + `AfKingFundingWaterfall` 9/9. Key assertions: sweepProgress cursor advances monotonically; lastSweptDay backstop blocks repeat-buy independent of cursor position; swap-pop occupant still processed; subscriberCount shrinks by exactly the cancels; SUB-05 waterfall (DirectEth/Claimable/Combined/sentinel) asserted from Swept.msgValue; SUB-06 VAULT/SDGNRS exempt by pinned identity (NORMAL control in identical state IS cancelled; renewal-lapse still cancels exempts; grep-clean of any settable exemption flag). Run verified live. |
| 4 | SAFE-04: RNG-freeze intact — resolution stays post-unlock behind RngNotReady guard; placement guard untouched; ETH-auto-rebuy removal retires freeze obligations | VERIFIED | `RngFreezeAndRemovalProofs` 13/13 PASS. Assertions: crankBets on pre-word bet: slot intact (RngNotReady caught); post-word same crank resolves (slot deleted); placement on word-bearing index reverts RngNotReady(:452); 1000-run fuzz: resolves IFF word landed. RM-02: ETH winnings always land in claimable (no auto-rebuy interception); two independent 8/8 winners at fresh indexes yield identical claimable credit (no VRF word in credit path). RM-03: flat 75bps unconditional across deity/normal tiers (1000-run fuzz). 18-symbol kill set grep-clean across 15 production sources. processCoinflipPayouts / (rngWord & 1) byte-present. KNOWN-ISSUES sha256 gate passed. Run verified live. |
| 5 | JGAS-03 + SC-5: 305-winner single-call jackpot correct + gas fits; split gone; forge build green; slot constants derived with no drift; KNOWN_ISSUES unmodified | VERIFIED | `JackpotSingleCallCorrectness` 8/8 PASS. Assertions: exactly 305 JackpotEthWin emissions at max scale (buckets 159/95/50/1); each non-solo bucket pays perWinner*count exactly; conservation sum(claimable)+whale-pass-spend==paidWei<=pool; worst-case gas measured 7,503,715 < 30M mainnet limit (~75% headroom); single call fully resolves (paidWei+rounding-dust==pool, no resume carry); 8-symbol split kill set grep-clean; STAGE_JACKPOT_ETH_RESUME absent; 305 ceiling and 63_600 max-scale preserved. 318-01 + 317-08: RM-06 slot re-derivation (lootboxRngPacked=35, lootboxRngWordByIndex=36) empirically confirmed — 10 slot-fixed suites reach bodies, slot-read assertions pass. forge build: exit 0. DeployCanary 2/2 PASS. Run verified live. |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/fuzz/helpers/DeployProtocol.sol` | AfKing deployed at N+18 before VAULT; public `afKing` handle | VERIFIED | Contains `import {AfKing}`, `AfKing public afKing`, `new AfKing(5_000_000_000, 885_000_000, 10_000_000_000)` at nonce 23 before DegenerusVault |
| `scripts/lib/predictAddresses.js` | AF_KING in DEPLOY_ORDER before VAULT; KEY_TO_CONTRACT.AF_KING="AfKing" | VERIFIED | `AF_KING index: 18 VAULT index: 19 Before VAULT: true KEY_TO_CONTRACT.AF_KING: AfKing` (node-verified live) |
| `contracts/ContractAddresses.sol` | AF_KING pinned to predicted keeper address | VERIFIED | Committed in 745cd63d; only contracts/ file changed in Phase 318; AF_KING=0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E |
| `test/fuzz/CrankFaucetResistance.t.sol` | SAFE-01 suite, contains `creditFlip` | VERIFIED | 618-line suite, 10 tests, contains creditFlip event counters and reward path assertions. Run: 10/10 PASS |
| `test/fuzz/CrankNonBrick.t.sol` | SAFE-02 non-brick, contains `batchPurchase` | VERIFIED | 707-line suite, 12 tests, contains batchPurchase slice-refund + skip-and-continue. Run: 12/12 PASS |
| `test/fuzz/AfKingSubscription.t.sol` | SAFE-02 SUB/PROTO, contains `burnForKeeper` | VERIFIED | 376-line suite, 7 tests, contains burnForKeeper all-or-nothing assertions. Run: 7/7 PASS |
| `test/fuzz/AfKingConcurrency.t.sol` | SAFE-03 concurrency + tombstone | VERIFIED | 10 tests including 1000-run exactly-once fuzz. Run: 10/10 PASS |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | SAFE-03 waterfall + two-tier skip-kill | VERIFIED | 9 tests including grep-clean of settable exemption flag. Run: 9/9 PASS |
| `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | SAFE-04 RNG-freeze + REMOVE proofs | VERIFIED | 869-line suite, 13 tests, includes grep-clean of 18-symbol kill set + KNOWN-ISSUES sha256 gate. Run: 13/13 PASS |
| `test/fuzz/JackpotSingleCallCorrectness.t.sol` | JGAS-03 305-winner jackpot | VERIFIED | 561-line suite, 8 tests, module-extending harness, worst-case-first gas. Run: 8/8 PASS |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `predictAddresses.js` DEPLOY_ORDER[18] | `DeployProtocol.sol` nonce 23 | matching AF_KING position before VAULT | WIRED | AF_KING at index 18, VAULT at 19; DeployProtocol deploys `afKing = new AfKing(...)` immediately before `vault = new DegenerusVault()`. DeployCanary validates every address constant matches deploy. |
| `DegenerusVault/StakedDegenerusStonk` constructors | `ContractAddresses.AF_KING` (live keeper code) | `afKing.subscribe(address(this),...)` at deploy | WIRED | SUB-09 self-subscribe calls reach live AfKing (not address(0)); setUp no longer reverts. Suite recovered from 197 to 532 runnable tests. |
| `crankBets`/`crankBoxes` reward path | `BurnieCoinflip.creditFlip` (one per tx) | `_ethToBurnieValue(gasUnits * CRANK_GAS_PRICE_REF)` | WIRED | CrankFaucetResistance asserts a single CoinflipStakeUpdated emission for a 3-item batch; zero emission for all-skipped batch; exact sum for N items. |
| crank reward formula | fixed `CRANK_*_GAS_UNITS` constants | never gasleft()/tx.gasprice | WIRED | Tests mirror the contract constants directly (REW-03); the fuzz asserts the fixed peg is sub-gas at any realistic price (>=1 gwei). |

---

## Data-Flow Trace (Level 4)

Not applicable to test-phase artifacts — this phase produces test files only, not components that render dynamic data. The underlying production contracts (DegenerusGame, AfKing, BurnieCoinflip) have their data flows exercised by the new suites running against live production storage, which constitutes the empirical data-flow validation.

---

## Behavioral Spot-Checks

All 6 new suites were run live during verification. Results match SUMMARY claims to the test:

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| SAFE-01 faucet suite | `forge test --match-contract CrankFaucetResistance` | 10 passed / 0 failed | PASS |
| DeployCanary | `forge test --match-contract DeployCanary` | 2 passed / 0 failed | PASS |
| SAFE-02 non-brick + SUB/PROTO | `forge test --match-contract "CrankNonBrick\|AfKingSubscription"` | 19 passed / 0 failed | PASS |
| SAFE-03 concurrency + waterfall | `forge test --match-contract "AfKingConcurrency\|AfKingFundingWaterfall"` | 19 passed / 0 failed | PASS |
| SAFE-04 RNG-freeze + REMOVE proofs | `forge test --match-contract RngFreezeAndRemovalProofs` | 13 passed / 0 failed | PASS |
| JGAS-03 jackpot single-call | `forge test --match-contract JackpotSingleCallCorrectness` | 8 passed / 0 failed | PASS |

---

## Critical Regression Check: No-New-Failures Proof

This is the load-bearing verification for Phase 320 closure ("0 NEW_FINDINGS").

### Full-suite run (current HEAD, post-Phase-318)

**Command:** `FOUNDRY_PROFILE=default forge test --no-match-path "test/**/*.fork.t.sol"`
**Result:** `68 test suites: 541 passed, 44 failed, 16 skipped (601 total)`

### Baseline comparison chain

| Snapshot | Result | Notes |
|----------|--------|-------|
| 317-01 v45 pre-deletion baseline | 71 failing / 446 passing / 16 skipped (533 total) | Authoritative v45 baseline captured BEFORE any v46 contract changes. Named known failures documented in 317-LEDGER.md including "various invariant/ suites: EthSolvency, VaultShareMath, VRFPath, MultiLevel, DegeneretteBet, WhaleSybil, ..." as "pre-existing v45 baseline invariant failures." |
| 317-08 post-contract-diff baseline (AF_KING=0) | 66 failing / 131 passing (197 total) | Stale: setUp reverts blocked 336 tests. Not a valid regression reference. |
| 318-01 post-fixture-repair baseline | 44 failing / 472 passing / 16 skipped (532 total) | Authoritative Phase 318 anchor. Named 44 failures documented explicitly in 318-01-SUMMARY.md. |
| Current HEAD (post-Phase-318) | 44 failing / 541 passing / 16 skipped (601 total) | 69 more passing = the 69 new Phase 318 tests (10+12+7+10+9+13+8). Failing count unchanged. |

### Named diff: current 44 vs 318-01 documented 44

A symmetric diff of the two sets was performed by name. **Result: EXACT MATCH. Zero divergence.**

Every test in the current 44 appears in the 318-01 documented baseline. No test in the 318-01 documented baseline is absent from the current 44.

### Disposition of the 8 invariant "replay failures"

The 8 invariant tests (`invariant_ethSolvency`, `invariant_solvencyUnderDegenerette`, `invariant_allGapDaysBackfilled`, `invariant_rngUnlockedAfterSwap`, `invariant_stallRecoveryValid`, `invariant_gameSolvencyUnderVaultOps`, `invariant_solvencyUnderPressure`, `invariant_solvencyAcrossLevels`) appear as "replay failure" in forge output — they are replaying counterexamples from `cache/invariant/failures/` directories (timestamp 16:31 May 23, during the 318-01 run, not during this verification run).

These are **pre-existing v45 baseline failures**. The 317-LEDGER explicitly lists "EthSolvency, CoinSupply, VaultShareMath, RngIndexDrainOrdering, GameFSM, VaultShare, VRFPath, MultiLevel, DegeneretteBet, WhaleSybil, Composition, RedemptionInvariants, TicketQueue" as "pre-existing v45 baseline invariant failures." None of these invariant suites reference v46 afKing/crank/batchPurchase/burnForKeeper surfaces. They were inaccessible in the 317-08 intermediate baseline only because setUp was reverting (AF_KING=address(0)). The 318-01 SUMMARY explicitly documented all 8 as "invariant counterexamples now reachable since setUp works" and confirmed "ZERO touch afKing/subscribe/AF_KING" via grep.

**Classification: All 44 current failures are pre-existing. Zero category-(b) regressions. No v46 contract bug implicated.**

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SAFE-01 | 318-02 | Faucet bounded; self-crank round-trip <= 0; WWXRP 0; one-reward-per-item; no pre-word resolve | SATISFIED | CrankFaucetResistance.t.sol 10/10; all four properties empirically proven |
| SAFE-02 | 318-03 | Non-brick: both cranks and batchPurchase skip-and-continue; cancel un-brickable; no double-buy reentrancy | SATISFIED | CrankNonBrick.t.sol 12/12 + AfKingSubscription.t.sol 7/7 |
| SAFE-03 | 318-04 | Concurrency: same-block sweeps self-partition; no double-buy; tombstone no dead-slot; subscription correctness | SATISFIED | AfKingConcurrency.t.sol 10/10 (1000-run fuzz) + AfKingFundingWaterfall.t.sol 9/9 |
| SAFE-04 | 318-05 | RNG-freeze intact: post-unlock resolve; placement guard untouched; freeze obligations retired | SATISFIED | RngFreezeAndRemovalProofs.t.sol 13/13; all facets proven including REMOVE grep-clean + KNOWN-ISSUES sha256 |
| JGAS-03 | 318-06 | 305-winner single-call jackpot: 305 emissions, exact amounts, conservation, gas fits, split gone | SATISFIED | JackpotSingleCallCorrectness.t.sol 8/8; 7,503,715 gas < 30M; split grep-clean |

---

## No Production Mutation in Wave 2 (SC-5)

**Verified:** `git log --oneline c5ec05a4^..34062626 -- contracts/` shows exactly ONE commit: `745cd63d` (318-01 deploy-fixture repair). That commit changed only `contracts/ContractAddresses.sol` (confirmed via `git show 745cd63d --name-only | grep "^contracts/"`). No other `contracts/*.sol` was modified in Phase 318. `git diff --name-only -- contracts/` is empty at current HEAD (ContractAddresses.sol committed in its patched Foundry state).

---

## Anti-Patterns Found

None identified. All 7 new test files drive real production state. The suites use `vm.store` only for established state-seeding patterns (RNG word injection, slot-writing subscription state to reach renewal branch, lootboxEth-zeroed poison construction). No placeholders, no TBD/FIXME/XXX, no empty return stubs, no TODO logic.

One known test family with pre-existing unrelated failures: `DegeneretteFreezeResolution.t.sol` (3 InvalidBet() failures) — these predate Phase 318 and originate in `DegenerusGameDegeneretteModule.placeDegeneretteBet` production validation, not slot errors or Phase 318 changes.

---

### Human Verification Required

None. All must-have truths are verifiable programmatically and have been verified by running the suites directly.

---

## Gaps Summary

No gaps. All 5 must-have truths verified, all 10 artifacts verified at all three levels, all key links wired, zero new failures introduced, zero production contract mutation (ContractAddresses.sol excepted per policy).

---

_Verified: 2026-05-23T23:15:00Z_
_Verifier: Claude (gsd-verifier)_
