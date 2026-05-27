---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
plan: 02
subsystem: testing
tags: [foundry, keeper-router, doWork, creditFlip-count, no-bounty-stacking, structural-reentrancy, grep-attestation, default-batch, unrewarded-escapes, recipient-isolation]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the v49 keeper-router source (AfKing.doWork one-category else-if + single CEI-last creditFlip, autoBuy/autoOpen escapes, BUY_BATCH/OPEN_BATCH/OPEN_KNEE defaults)"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "the GAS-calibrated BUY_BATCH=50 / OPEN_BATCH=100 / OPEN_KNEE=5 + the ADVANCE/BUY ratios the count-proofs exercise"
provides:
  - "TST-02 empirical proof: EXACTLY one COINFLIP.creditFlip per doWork() tx across all three category branches (buy / advance / open), proven by recipient-isolated COUNT (D-02), never by exact amounts"
  - "the bountyEarned==0 SKIP path runs the buy category but credits ZERO and does NOT revert (count==0); doWork with all 3 O(1) predicates empty reverts NoWork() and credits nothing"
  - "STRUCTURAL reentrancy attestation (D-01): comment-stripped grep over the doWork() body — single CEI-last creditFlip(msg.sender, bountyEarned), pinned ContractAddresses.GAME/COINFLIP targets only, zero ETH-push in any leg — NO synthetic attacker harness"
  - "parameterless doWork() runs the fixed BUY_BATCH default, no OOG, leaves a remainder for the next call; standalone autoBuy(count)/autoOpen(count) escapes run the leg but pay the CALLER zero router bounty"
affects: [333-terminal-delta-audit-3-skill-adversarial-sweep-closure, TST-04-non-widening-ledger, TST-05-degeneretteResolve-creditFlip-count]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Recipient-isolated creditFlip count (_countCoinflipStakeUpdatedFor(keeper), topics[1]==keeper) separates the router bounty from the buy's player-side flip-credit to the bought subscriber (the two deploy-time protocol subs do exactly this) — the count can't be inflated/masked"
    - "Brace-depth function-body extraction (_extractFunctionBody) to scope a comment-stripped grep gate to a SINGLE function body (doWork's router legs), excluding unrelated player paths (the CEI-correct withdraw self-send)"
    - "Buy-leg state forcing via the slot-4 packed (_autoBuyDay|_autoBuyCursor) write: _pinBuyLegWalkedForToday (cursor>=length, day==today => buy predicate FALSE) routes the router past buy into advance/open/NoWork; _resetCursorToZeroForToday re-enters the buy leg over already-bought subs to reach the bountyEarned==0 skip"
    - "VRF settle helper (_settleGame, mirrors RngLockDeterminism._completeDay) brings the game to advance-not-due + not-locked so boxesPending() can be TRUE (it is FALSE during rngLock) — the precondition for reaching the open leg / the clean NoWork state"

key-files:
  created:
    - "test/fuzz/KeeperRouterOneCategory.t.sol — 9 GREEN proofs (708 lines): the TST-02 one-category/no-stacking + structural-reentrancy-attest + default-batch/remainder + unrewarded-escapes proof file"
  modified: []

key-decisions:
  - "D-02 count-isolation: the standalone-autoBuy UNREWARDED proof keys on _countCoinflipStakeUpdatedFor(keeper)==0, NOT the unfiltered count — the buy itself routes flip-credit to the BOUGHT subscriber (the sDGNRS/VAULT protocol subs' reinvest/BURNIE-auto-rebuy config), which is the buy's player-side economic effect, not the caller's router bounty. The unrewarded claim is 'the caller gets no bounty'."
  - "D-01 attest scoped to the doWork() body via _extractFunctionBody: the file-wide `.call{value:` grep is NOT zero because withdraw() has a CEI-correct `msg.sender.call{value: amount}(\"\")` self-send (a subscriber pulling its OWN prepaid pool, pool zeroed BEFORE the send) — a separate player path, not a router leg. Pinned that sole ETH-push at count==1 so a future second push flips RED."
  - "Advance non-vacuity is observed as 'advance consumed OR rngLock engaged' rather than advanceDue()==false alone — doWork's single advanceGame() advances the day but the multi-stage day-advance engages rngLock mid-flight, so progress is the disjunction (only the advance leg can produce it; buy was pinned empty, no boxes pending)."
  - "Called the DeployProtocol-deployed afKing/game/coinflip instances directly (they land at the pinned ContractAddresses.* via CREATE nonce addressing) — no IAfKing/IGame interface declaration needed; box driving reuses the CrankOpenBoxWorstCaseGas first-deposit-enqueue + word-inject idiom."

patterns-established:
  - "Pattern 1: one-category creditFlip-COUNT oracle — vm.recordLogs(); doWork(); assertEq(_countCoinflipStakeUpdatedFor(keeper), 1) across buy/advance/open + ==0 on the bountyEarned==0 skip + ==0/NoWork-revert when empty. The 'exactly one across all 3 branches + zero on skip' set IS the proof the else-if chain can never credit two categories per tx."
  - "Pattern 2: structural reentrancy grep-attest WITHOUT an attacker harness — extract the doWork() body, assert the single CEI-last creditFlip + pinned-only external targets + zero ETH-push in the legs; reentrancy has no hook because there is no untrusted call to re-enter through (D-01)."

requirements-completed: [TST-02]

# Metrics
duration: 22min
completed: 2026-05-27
---

# Phase 332 Plan 02: TST-02 One-Category / No-Bounty-Stacking + Structural Reentrancy Attest + Default-Batch/Escapes Summary

**Proved the v49 `doWork()` one-rewarded-category-per-tx invariant EMPIRICALLY (exactly one `creditFlip` per tx across buy/advance/open, zero on the `bountyEarned==0` skip, zero + `NoWork()` revert when empty — all by recipient-isolated COUNT, never exact amounts) and the router→game→`creditFlip` double-pay disposition STRUCTURALLY (a comment-stripped grep over the `doWork()` body — single CEI-last `creditFlip`, pinned `ContractAddresses.GAME/COINFLIP` targets only, no ETH-push in any leg), with NO synthetic attacker harness, plus the parameterless default-batch/remainder and the unrewarded standalone escapes.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-05-27T17:02:00Z
- **Completed:** 2026-05-27T17:24:00Z
- **Tasks:** 2
- **Files created:** 1 (`test/fuzz/KeeperRouterOneCategory.t.sol`, 708 lines, 9 tests)

## Accomplishments
- **D-02 no-stacking (count, not amount):** `testBuyBranchCreditsExactlyOnce` / `testAdvanceBranchCreditsExactlyOnce` / `testOpenBranchCreditsExactlyOnce` each assert `_countCoinflipStakeUpdatedFor(keeper) == 1` — exactly one router bounty per `doWork()` across all three category branches. `testBountyEarnedZeroSkipCreditsNothing` proves the buy chunk that walks only already-bought subs ENTERS the buy category yet credits ZERO and does NOT revert (the `bountyEarned > 0` guard skips the single CEI-last creditFlip). `testNoWorkRevertsAndCreditsNothing` proves all-three-predicates-empty reverts `NoWork()` and credits nothing. The "exactly one across all three branches + zero on skip" set is the proof the else-if chain cannot credit two categories in one tx.
- **D-01 structural reentrancy (no attacker harness):** `testDoWorkReentrancyStructurallySafeSourceAttest` greps the comment-stripped `doWork()` body — the single `creditFlip(msg.sender, bountyEarned)` (CEI-last, the sole money edge per tx, also the only creditFlip site file-wide), the pinned `IGame(ContractAddresses.GAME)` / `ICoinflip(ContractAddresses.COINFLIP).creditFlip` as the only external-call targets, and ZERO `.call{value:` / `.transfer(` / `.send(` ETH-push in the legs. File-wide the sole ETH-push is pinned to the CEI-correct `withdraw` self-send (`msg.sender.call{value: amount}("")`, count==1). No reentrant mock / attacker contract exists.
- **D-03 default-batch + escapes:** `testParameterlessDoWorkDefaultBatchLeavesRemainder` (60-sub backlog > BUY_BATCH=50 → one `doWork()` runs the fixed default, no OOG, cursor < length remainder, a second `doWork()` advances further); `testStandaloneAutoBuyEscapeUnrewarded` + `testStandaloneAutoOpenEscapeUnrewarded` (the leg runs — a sub bought / a box opened — but the CALLER's router bounty count is 0).
- All 9 tests GREEN; zero `contracts/*.sol` mutation.

## Task Commits

Both TDD tasks landed in one tightly-coupled proof file (the count-oracle + the structural-attest share the file's helper surface), committed atomically as a single `test(...)` commit since both were authored and verified GREEN together:

1. **Task 1 (count oracle + skip + NoWork) + Task 2 (structural attest + default-batch + escapes)** — `c7c57376` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) — see the final docs commit.

## Files Created/Modified
- `test/fuzz/KeeperRouterOneCategory.t.sol` — TST-02 proof file. Ports the `_countCoinflipStakeUpdated` / `_countCoinflipStakeUpdatedFor` log-count oracle and the `_stripComments` / `_countOccurrences` source-grep helpers from `CrankLeversAndPacking.t.sol`; adds `_extractFunctionBody` (brace-depth function-body extraction to scope the attest to the `doWork()` legs), `_settleGame` (VRF drain to reach the open/NoWork preconditions), and the slot-forcing helpers (`_pinBuyLegWalkedForToday` / `_resetCursorToZeroForToday`) mirroring `AfKingConcurrency.t.sol`. Box driving reuses the `CrankOpenBoxWorstCaseGas` first-deposit-enqueue + `_injectLootboxRngWord` idiom.

## Verification

- `forge test --match-contract KeeperRouterOneCategory` → **9 passed / 0 failed**.
- `forge test --match-contract KeeperRouterOneCategory --match-test "Branch|Skip|NoWork"` → 5 passed (the D-02 count set).
- `git diff --name-only contracts/` → empty (ZERO mainnet mutation, FROZEN subject honored).
- No synthetic reentrant attacker / reentrant mock in the file — the only `contract` declaration is `KeeperRouterOneCategory is DeployProtocol` (D-01).

## Deviations from Plan

None affecting scope. Two execution refinements (no contract change, no scope change), both required to make the locked D-01/D-02 dispositions pass correctly:

1. **[Refinement — D-01 grep scoping] Scoped the structural attest to the `doWork()` body.** A naive file-wide `.call{value:` count is 1, not 0, because `AfKing.withdraw()` has a legitimate CEI-correct `msg.sender.call{value: amount}("")` self-send (a subscriber pulling its own prepaid pool, pool zeroed at `AfKing.sol:322` BEFORE the send at `:325`). That is a separate player path, NOT a `doWork` router leg and NOT a reentrancy hook the router exposes. Added `_extractFunctionBody` to grep the `doWork()` body for the no-ETH-push / pinned-target shape, and separately pinned the sole file-wide ETH-push at count==1 (so a future second push flips the gate RED). This is strictly stronger than a blanket file-wide gate and matches D-01's "no untrusted external call in any leg" wording precisely.
2. **[Refinement — D-02 recipient-isolation] Unrewarded-escape proof keys on the keeper recipient.** The standalone `autoBuy(count)` emits 3 `CoinflipStakeUpdated` events — but all 3 go to the deploy-time protocol subscribers (`StakedDegenerusStonk` / `DegenerusVault`), whose subscription config routes flip-credit on a buy as part of their own reinvest/BURNIE-auto-rebuy behavior. That is the buy's player-side economic effect, not the caller's router bounty. Per D-02's recipient-isolation principle, the UNREWARDED claim ("the caller gets no bounty") is proven with `_countCoinflipStakeUpdatedFor(keeper) == 0`, matching the already-correct `autoOpen` escape proof.

No CLAUDE.md present in the project root (global instructions only).

## Contract Defects Surfaced

None. Every proof passed against the FROZEN v49 source. The 3 protocol-sub flip-credits on a standalone buy are by-design (the v46 sDGNRS/VAULT subscription reinvest model), not a defect; they are correctly excluded from the router-bounty count by recipient isolation.

## Known Stubs

None — no hardcoded empty values, placeholders, or unwired data sources. Every assertion drives real protocol state (real subscribers via the public `subscribe()` API, real lootbox deposits via `purchase()`, a real `_settleGame` VRF drain) and reads it back via the contract's own views / authoritative storage slots.

## Self-Check: PASSED

- `test/fuzz/KeeperRouterOneCategory.t.sol` — FOUND
- commit `c7c57376` — FOUND
- `332-02-SUMMARY.md` — FOUND
- `forge test --match-contract KeeperRouterOneCategory` — 9 passed / 0 failed
- `git diff --name-only contracts/` — empty (zero mainnet mutation)
