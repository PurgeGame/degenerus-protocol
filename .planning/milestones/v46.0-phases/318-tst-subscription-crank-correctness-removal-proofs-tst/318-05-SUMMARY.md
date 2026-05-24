---
phase: 318-tst-subscription-crank-correctness-removal-proofs-tst
plan: 05
subsystem: testing
tags: [foundry, safe-04, vrf-freeze, rng-not-ready, crank, auto-rebuy-removal, flat-recycle-bps, grep-clean-attestation, byte-unmodified]

# Dependency graph
requires:
  - phase: 318-01
    provides: "AfKing-aware DeployProtocol fixture (AF_KING live at the predicted address) — DeployProtocol.setUp() no longer reverts; the post-deletion slot map (lootboxRngPacked=35, lootboxRngWordByIndex=36); the post-repair 44-fail no-new-failures baseline"
  - phase: 317-05
    provides: "RM-02 ETH-always-to-claimable (_addClaimableEth 2-arg, no entropy), JGAS-02 single-call jackpot, the J5 freeze-invariant re-confirmation (no _unlockRng pulled into the removed path)"
provides:
  - "SAFE-04 suite-level proof: a crank-driven bet/box resolution stays POST-unlock behind the RngNotReady guard (pre-word crank skips via the onlySelf try/catch + the cursor orphan gate; post-word the SAME crank resolves/opens) — the freeze window is unchanged under the permissionless crank"
  - "Placement-guard-untouched proof: a degenerette placement for a word-bearing index reverts RngNotReady (DegeneretteModule:452) — the crank relaxed RESOLVE not PLACEMENT"
  - "RM-02 behavioral: winning ETH bets credit claimable wholly (no auto-rebuy interception); the credit step is deterministic across two independent winners -> no VRF word threaded into the credit (freeze-obligation retirement)"
  - "RM-03 behavioral + structural: BURNIE recycle is flat 75bps unconditional across the deity and normal tiers; _recyclingBonus takes ONLY amount (no tier branch)"
  - "REMOVE grep-clean: the 18-symbol legacy kill set returns ZERO non-comment matches across 15 production sources (kept hasAnyLazyPass + the keeper AfKing.sol excluded)"
  - "UNMODIFIED attestation: processCoinflipPayouts + (rngWord & 1) byte-present; KNOWN-ISSUES.md byte-unmodified (sha256 anchor in-test + enforced live in the verify-step bash)"
affects: [318-06, vrf-freeze-invariant, 320]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Freeze-boundary fuzz: parametrize word-set timing (word-first vs crank-first) and assert resolution succeeds IFF the word has landed — the freeze boundary is the word, not the caller"
    - "Determinism-without-VRF proof: resolve two independent 8/8 winners on two FRESH indexes (sidestepping the :452 placement guard) and assert identical claimable credit — proves no entropy is mixed into the credit step"
    - "Comment-stripping source attestation: vm.readFile + a Solidity line/block-comment stripper so NatSpec prose mentioning a kill-set symbol cannot self-invalidate the grep gate"
    - "Repo-root byte-unmodified gate via a split anchor: pin the milestone-baseline sha256 in-test (fs_permissions only reaches ./contracts) + re-confirm the live file hash in the verify-step bash (which reads the repo root)"

key-files:
  created:
    - test/fuzz/RngFreezeAndRemovalProofs.t.sol
  modified: []

key-decisions:
  - "Proved SAFE-04 on the LIVE crank path (crankBets/crankBoxes) rather than via direct module calls — drives real degenerette bets + real lootbox purchases through the public mint API, mirroring the established CrankNonBrick / CrankFaucetResistance patterns, so the freeze guard is exercised in its actual permissionless reach"
  - "RM-02 freeze-obligation retirement proven as credit DETERMINISM (two independent 8/8 winners on two fresh indexes yield identical claimable credit) + a source-level attestation that _addClaimableEth is the 2-arg no-entropy form — not by counting VRF words, which is not directly observable from a unit test"
  - "RM-03 flat-75bps proven BOTH numerically (the contract formula amount*75/10000 is identical for a deity-pass holder VAULT and a normal player) AND structurally (the private _recyclingBonus takes ONLY amount; no _afKingDeityBonusHalfBpsWithLevel survives) — _recyclingBonus is private so a source attestation is the load-bearing flat-tier proof"
  - "KNOWN-ISSUES byte-unmodified split across an in-test sha256 anchor and the verify-step bash because foundry.toml fs_permissions grants read only on ./contracts (not the repo root); the bash gate (sha256sum KNOWN-ISSUES.md == baseline) is the actual byte-for-byte enforcement"
  - "Restored ContractAddresses.sol via `git checkout` (NOT the stale restore script) after each patch run; the committed-HEAD ContractAddresses.sol already carries the real predicted AF_KING address (318-01 decision), so the clean tree is the foundry-ready file"

patterns-established:
  - "When a verification suite places state-gated items (degenerette bets) under a freeze-window placement guard, place on a FRESH index per item (the :452 guard blocks placement once an index has a word) — a single shared index breaks multi-winner determinism tests"

requirements-completed: [SAFE-04]

# Metrics
duration: ~6min
completed: 2026-05-23
---

# Phase 318 Plan 05: SAFE-04 RNG-Freeze Intact + REMOVE Proofs Summary

**Proved the v45 RNG-freeze hard-floor (SAFE-04) survives the v46 permissionless crank — a crank-driven bet/box resolution stays POST-unlock behind the RngNotReady guard (pre-word skips, post-word the SAME crank resolves), the placement guard is untouched, and the ETH-auto-rebuy removal made the freeze surface strictly smaller (deterministic, no-VRF-word credit) — plus the REMOVE proofs: the legacy kill set is grep-clean, ETH winnings always land in claimable, BURNIE recycle is flat 75bps unconditional, and the win/loss RNG path + KNOWN-ISSUES are byte-unmodified. 13/13 green; zero contracts/ mutation.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-23T22:25:14Z
- **Tasks:** 3 of 3 completed
- **Files created:** 1 (`test/fuzz/RngFreezeAndRemovalProofs.t.sol`, 869 lines, 13 tests)
- **Suite:** `forge test --match-contract RngFreezeAndRemovalProofs` → **13 passed / 0 failed / 0 skipped**

## Accomplishments

### Task 1 — SAFE-04: RNG-freeze intact under the crank

- **`testCrankBetResolutionStaysPostUnlock`** — a `crankBets` over a not-ready bet (word at INDEX still 0) does NOT resolve it (the onlySelf `_crankResolveBet` sub-call hits DegeneretteModule:578 `RngNotReady`, caught by the per-item try/catch; the bet slot stays intact). After the word lands, the SAME crank resolves it (slot deleted). Proves the relaxation is WHO-can-call, not WHEN.
- **`testCrankBoxOpenStaysPostUnlock`** — a `crankBoxes(100)` over an enqueued box whose index word is 0 returns at the cursor orphan gate (`DegenerusGame:1603 lootboxRngWordByIndex[index] == 0 -> return`) AND would hit the LootboxModule:485 `RngNotReady` guard — no pre-word open (the first-deposit signal stays set). After the word lands the SAME crank opens it (signal cleared).
- **`testPlacementGuardUntouchedWhenIndexHasWord`** — a degenerette placement for an index that already has a word reverts `RngNotReady()` (DegeneretteModule:452). The crank relaxed RESOLVE, not PLACEMENT — placement stays frozen as before.
- **`testFuzz_CrankResolvesIffWordLanded`** (1000 runs) — for either word-set timing (word-first vs crank-first), a crank resolves a bet IFF the word has landed: pre-word always skips (slot intact), post-word always resolves (slot deleted). The freeze boundary is the word, not the caller.

### Task 2 — REMOVE behavioral: ETH always to claimable + flat 75bps + freeze-obligation retirement

- **`testEthWinningsAlwaysLandInClaimable`** — a winning degenerette ETH bet, resolved THROUGH the permissionless crank (proving the freeze-intact resolve + the always-to-claimable credit together), credits the winner's `claimableWinningsOf` — no auto-rebuy / ticket-conversion interception of winnings (RM-02).
- **`testEthCreditPathIsDeterministicNoVrfWord`** — two independent 8/8 winners on two FRESH indexes yield IDENTICAL claimable credit, proving the credit step is deterministic given the resolved outcome → no VRF word threaded into the credit (the auto-rebuy roll that previously consumed entropy is gone; `_addClaimableEth` is the 2-arg deterministic form). This is the freeze-obligation RETIREMENT.
- **`testBurnieRecycleIsFlat75BpsAcrossTiers`** (1000 runs) — the BURNIE recycle bonus `(amount * 75) / 10_000` is identical for a deity-pass holder (VAULT, `hasDeityPass == true`) and a normal player (`hasDeityPass == false`): flat, unconditional, no deity scaling, no under/over-credit (RM-03). Bounded below the 1000-BURNIE cap so the flat-bps relationship holds exactly.

### Task 3 — REMOVE grep-clean + UNMODIFIED-invariant structural attestation

- **`testLegacyKillSetIsGrepClean`** — the 18-symbol legacy kill set (setAutoRebuy / autoRebuyState / AutoRebuyState / _processAutoRebuy / _calcAutoRebuy / settleFlipModeChange / _afKingRecyclingBonus / _afKingDeityBonusHalfBpsWithLevel / resumeEthPool / SPLIT_CALL1 / SPLIT_CALL2 / SPLIT_NONE / _resumeDailyEth / STAGE_JACKPOT_ETH_RESUME / call1Bucket / setAfKingMode / deactivateAfKingFromCoin / syncAfKingLazyPassFromCoin) returns ZERO non-comment matches across 15 production sources (after a Solidity comment-stripper drops NatSpec prose). The keeper `AfKing.sol` and the `contracts/test`+`contracts/mocks` trees are not scanned, so the KEPT SUB-09 afKing handle + the keeper itself never false-positive.
- **`testKeptHasAnyLazyPassPresent`** — `hasAnyLazyPass` is exposed on the live contract (returns true for the deity-bit holder) and the identifier is KEPT in DegenerusGame.sol (RM-04 reconciliation; guards against an over-eager removal pass deleting the kept symbol).
- **`testWinLossRngPathByteUnmodified`** — `function processCoinflipPayouts(` and `bool win = (rngWord & 1) == 1;` are byte-present exactly once in BurnieCoinflip.sol (the rng-consuming win/loss path the removal must NOT touch).
- **`testRecycleIsStructurallyFlat75Bps`** — `RECYCLE_BONUS_BPS = 75` + the flat-bps formula `bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR);` are present and `_afKingDeityBonusHalfBpsWithLevel` is gone (the flat collapse).
- **`testAddClaimableEthIsTwoArgNoEntropy`** — `_addClaimableEth` is the 2-arg `(beneficiary, weiAmount)` deterministic form, and `_processAutoRebuy` / `autoRebuyState` are absent from the credit path (the freeze-obligation retirement, structurally).
- **`testKnownIssuesBaselineHashRecorded`** — pins the KNOWN-ISSUES.md milestone-baseline sha256 (`75b3b4bc…d8014`); the live byte-for-byte equality is enforced in the verify-step bash (`sha256sum KNOWN-ISSUES.md == baseline` → KNOWN_ISSUES_BYTE_UNMODIFIED_PASS).

## Task Commits

1. **All three tasks (single new test artifact):** `test(318-05): SAFE-04 RNG-freeze intact + REMOVE proofs` — `b9bc5206` (1 file, 869 insertions, 0 deletions)

The three plan tasks all author the same single file (`RngFreezeAndRemovalProofs.t.sol`); the brand-new file is committed as ONE cohesive test artifact rather than splitting one path across three artificial commits.

## Verification

- `forge test --match-contract RngFreezeAndRemovalProofs` → **Suite result: ok. 13 passed; 0 failed; 0 skipped.**
- All three plan verify gates return their required tokens (SAFE04_FREEZE_PASS / REMOVE_BEHAVIORAL_PASS / REMOVE_GREPCLEAN_PASS) under the patch → test → restore wrapper.
- KNOWN-ISSUES byte-unmodified gate: `KNOWN_ISSUES_BYTE_UNMODIFIED_PASS` (live sha256 == baseline anchor).
- `git diff --name-only -- contracts/` → **empty** (zero production-contract mutation). ContractAddresses.sol restored via `git checkout`.

## No-New-Failures Assessment

- My suite is fully green (13/13) in isolation.
- The 3 `DegeneretteFreezeResolution` failures observed alongside the sibling suites are the documented PRE-EXISTING baseline failures (`InvalidBet()`, part of the 318-01 post-repair 44-fail baseline; flagged in 317-VERIFICATION Anti-Patterns). They are independent of this plan: I never touched that file (clean git status), and they fail identically with my file absent from the match set.
- CrankNonBrick (12/12) and CrankFaucetResistance (10/10) — the sibling crank suites — stay green; my file introduces zero cross-contamination.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `testEthCreditPathIsDeterministicNoVrfWord` initially reverted `RngNotReady()` (test sequencing bug)**
- **Found during:** Task 2 first run.
- **Issue:** The determinism test resolved the first winner at INDEX (landing INDEX's word), then tried to place the second winner's bet — also at INDEX. But once INDEX has a word, the freeze-window placement guard (DegeneretteModule:452 `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()`) correctly rejects the second placement. The guard was working as designed; the test's shared-index sequencing was the bug.
- **Fix:** Replaced the two single-purpose helpers with one index-parameterized `_resolveWinningBetForPlayerAtIndex(who, atIndex)` that points the live daily index at a FRESH `atIndex` (word still 0) before placement, then resolves the second winner at `INDEX + 1`. An 8/8 jackpot win on a fixed bet maps to the same payout tier regardless of index/word, so the two credits remain comparable. This deviation actually re-confirms the placement guard is live (the same guard `testPlacementGuardUntouchedWhenIndexHasWord` asserts directly).
- **Files modified:** `test/fuzz/RngFreezeAndRemovalProofs.t.sol`
- **Commit:** `b9bc5206`

**2. [Rule 1 - Bug] Two `view`-mutability compiler warnings**
- **Found during:** Task 3 compile.
- **Issue:** `testBurnieRecycleIsFlat75BpsAcrossTiers` and `testKeptHasAnyLazyPassPresent` only read state, so solc flagged them as restrictable to `view`.
- **Fix:** Marked both `public view`.
- **Files modified:** `test/fuzz/RngFreezeAndRemovalProofs.t.sol`
- **Commit:** `b9bc5206`

## Known Stubs

None. Every assertion exercises live production state (real cranks, real placements, real source reads). No placeholder/empty-value/TODO stubs introduced.

## Threat Flags

None. This plan adds a test file only; it introduces no new network endpoint, auth path, file-access pattern, or schema change. The threat register dispositions (T-318-05-01..04) are all `mitigate` and are each covered by a passing test as planned.

## Self-Check: PASSED

- `test/fuzz/RngFreezeAndRemovalProofs.t.sol` exists on disk (869 lines, 13 tests).
- Commit `b9bc5206` exists in `git log` (verified below).
- `forge test --match-contract RngFreezeAndRemovalProofs` → 13/13 green.
- `git diff --name-only -- contracts/` empty; ContractAddresses.sol restored via `git checkout`.
- KNOWN-ISSUES byte-unmodified gate PASS.
