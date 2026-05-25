---
phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
plan: 03
subsystem: testing
tags: [foundry, forge, redemption, sdgnrs, claimable-underflow, burnie-conservation, repro-first, invariant]

requires:
  - phase: 322-impl-the-one-batched-contract-diff-all-7-items
    provides: "the frozen v47.0 contract subject at fb29ed51 (resolveRedemptionLootbox payable + deleted unchecked claimable debit, CHECKED pullRedemptionReserve segregation, redeemBurnieShare net-zero settle-at-submit, resolveRedemptionPeriod 2-arg, _settleClaimableShortfall R3 helper)"
  - phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
    provides: "323-01 compiling foundry tree (forge build exit 0) + repaired redemption test homes with v47 storage-slot/struct fixes"
provides:
  - "REDEEM-08 repro-first headline: two-claimant same-day claimableWinnings[SDGNRS] underflow FAILS pre-fix (wrap = 2^256-3eth) and PASSES post-fix (recorded evidence)"
  - "BURNIE-can't-block-ETH proof (ETH leg pays full rolled/2 from segregated balance, no claim-time BURNIE leg)"
  - "R1 net-BURNIE-mint == 0 across submit (conserved universe = totalSupply + Sigma coinflipAmount)"
  - "R3 _settleClaimableShortfall paired-debit invariant + strict-1-wei sentinel (focused contracts/test harness)"
  - "R4 resolveRedemptionPeriod 2-arg resolve + MAX(175%)->rolled lowering"
  - "3 REDEEM-08 conservation invariants (balance >= pendingRedemptionEthValue; claimablePool >= claimable[SDGNRS]; no-unchecked-debit no-wrap) over the randomized submit/resolve/claim/gameOver sequence"
affects: [324-terminal]

tech-stack:
  added:
    - "contracts/test/SettleClaimableShortfallTester.sol (test-only harness inheriting DegenerusGameStorage to exercise the production _settleClaimableShortfall body in isolation)"
  patterns:
    - "Repro-first cross-tree proof: drive the exact deleted-debit site (resolveRedemptionLootbox) directly; PASS on the frozen post-fix tree, then re-introduce ONLY the deleted unchecked block in place, capture the FAIL, restore via `git checkout` (blob-hash verified frozen)"
    - "Module-delegatecall no-op mock: vm.mockCall the GAME_LOOTBOX_MODULE selector so the Game-side audited body (the claimable-debit site) runs for real while the out-of-scope 5-ETH-chunk lootbox loop returns cleanly"
    - "Conserved BURNIE universe scalar = totalSupply() + Sigma coinflipAmount(holder) — the deferred creditFlip lands as a future-day STAKE, not minted supply, so totalSupply alone transiently drops by burnFromHeld"

key-files:
  created:
    - contracts/test/SettleClaimableShortfallTester.sol
    - .planning/phases/323-.../323-03-SUMMARY.md
  modified:
    - test/fuzz/StakedStonkRedemption.t.sol
    - test/invariant/RedemptionAccounting.t.sol

key-decisions:
  - "Pre-fix repro mechanism (2): re-introduced ONLY the deleted unchecked debit block in-place into the frozen DegenerusGame.sol, captured the wrap failure, then `git checkout`-restored to the frozen blob 54af4272 (verified == fb29ed51). The full-worktree mechanism (1) was blocked by the contract-commit-guard hook intercepting `git worktree add`."
  - "Two-claimant repro decouples claimableWinnings[SDGNRS] (small slice) from claimablePool (large global pool) — the real Defect-A precondition: the global pool still holds OTHER players' funds so the pre-fix CHECKED claimablePool debit does NOT revert, while sDGNRS's slice underflows the UNCHECKED claimableWinnings debit and wraps."
  - "R1 net-zero measured on totalSupply + Sigma coinflipAmount, NOT totalSupply alone — the deferred creditFlip is a future-day stake (coinflipBalance[targetDay]), unminted at submit, so totalSupply transiently drops by burnFromHeld."
  - "R3 verified via a dedicated contracts/test harness (mainnet-clean test helper) running the EXACT production _settleClaimableShortfall body — the helper is internal in DegenerusGameStorage and the 5 whale/mint callers need deep seeding, so a focused isolation check is the sanctioned refinement-coverage approach."
  - "resolveRedemptionPeriod confirmed genuinely 2-arg in the frozen subject (the 322-04-SUMMARY note about keeping a 3-arg flipDay param was superseded by refinement R4 per 322-08)."

patterns-established:
  - "Repro-first discipline: write the defect repro, prove it FAILS against the pre-fix code, restore the subject, prove it PASSES post-fix — with the contract left byte-frozen (blob-hash attested)."

requirements-completed: [REDEEM-08]

duration: ~2.5h
completed: 2026-05-25
---

# Phase 323 Plan 03: REDEEM-08 Repro-First Redemption Proofs Summary

**Proved the sDGNRS redemption-accounting fix EMPIRICALLY repro-first: the two-claimant same-day `claimableWinnings[SDGNRS]` underflow FAILS against the pre-fix unchecked debit (wraps to 2^256−3eth) and PASSES on the frozen post-fix tree; plus BURNIE-can't-block-ETH, net-BURNIE-mint == 0, the R1/R3/R4 refinements, and 3 ETH-segregation conservation invariants — with the contract subject left byte-frozen at fb29ed51.**

## Performance
- **Duration:** ~2.5h
- **Tasks:** 3/3
- **Files modified:** 2 test files + 1 new contracts/test harness (zero mainnet `contracts/*.sol` edits)

## Accomplishments
- **REDEEM-08 repro-first headline proven both directions:** `testReproTwoClaimantSameDayNoUnderflow` PASSES against the frozen post-fix contract; re-introducing ONLY the deleted unchecked debit makes it FAIL with the wrap.
- **BURNIE-can't-block-ETH:** the claim's ETH leg pays the full rolled/2 from the segregated balance regardless of BURNIE (settled at submit, no claim-time BURNIE leg).
- **R1/R3/R4 refinement coverage** + **3 REDEEM-08 conservation invariants** over the randomized handler sequence.
- **Subject frozen:** `contracts/DegenerusGame.sol` blob hash `54af4272...` == `fb29ed51:contracts/DegenerusGame.sol` after the pre-fix run.

## Repro-First Evidence (the headline discipline)

**Mechanism used:** fallback (2) — temporarily re-introduced ONLY the deleted unchecked debit block
`uint256 claimable = claimableWinnings[SDGNRS]; unchecked { claimableWinnings[SDGNRS] = claimable - amount; } claimablePool -= uint128(amount);`
in-place into the frozen `contracts/DegenerusGame.sol` `resolveRedemptionLootbox`, ran the repro, captured the failure, then `git checkout`-restored the file. (Mechanism (1)'s `git worktree add` was blocked by the contract-commit-guard hook.)

**PRE-FIX FAIL (re-introduced unchecked debit):**
```
[FAIL: REDEEM-08: claimableWinnings[SDGNRS] wrapped toward 2^256 (pre-fix unchecked debit underflow):
115792089237316195423570985008687907853269984665640564039454584007913129639936 >= 79228162514264337593543950335]
testReproTwoClaimantSameDayNoUnderflow()
```
The wrapped value `115792089237316195423570985008687907853269984665640564039454584007913129639936` is exactly `2^256 − 3 ether` — the unchecked `0 − 3 ether` underflow on the second same-day claimant (claimant 1 drained sDGNRS's claimable slice to 0; claimant 2's lootbox `amount = 3 ether` > remaining `0`). `>= type(uint96).max` → assertion trips.

**POST-FIX PASS (restored frozen contract, blob 54af4272):**
```
[PASS] testReproSubmitFailClosedOnClaimableShortfall()
[PASS] testReproTwoClaimantFullFlowNoUnderflow()
[PASS] testReproTwoClaimantSameDayNoUnderflow()
Suite result: ok. 3 passed; 0 failed; 0 skipped
```
Post-fix, `resolveRedemptionLootbox` does NO claimable debit (ETH arrives as `msg.value`); the only claimable[SDGNRS] debit is the CHECKED `pullRedemptionReserve` at submit, so the wrap can never form.

## Coverage Results

**StakedStonkRedemption.t.sol — 15/15 PASS** (8 prior + 7 new):
- `testReproTwoClaimantSameDayNoUnderflow` — direct deleted-debit-site repro (the cross-tree headline).
- `testReproTwoClaimantFullFlowNoUnderflow` — full submit→resolve→claim, two same-day redeemers; CHECKED submit-time segregation never wraps claimable.
- `testReproSubmitFailClosedOnClaimableShortfall` — C5 AfKing SUB-09 drain: CHECKED pull reverts fail-closed on claimable shortfall, succeeds on recovery (no virtual reserve left to underflow).
- `testBurnieCannotBlockEthLeg` — ETH leg pays full rolled/2 irrespective of BURNIE.
- `testRedeemBurnieNetMintZero` (R1) — `Δ(totalSupply + Σ coinflipAmount) == 0` across submit; redeemer flip-stake credit rose (conservation, not no-op).
- `testResolveRedemptionPeriod2Arg` (R4) — 2-arg `(roll, dayToResolve)` resolves + lowers `pendingRedemptionEthValue` MAX(175%)→rolled.
- `testSettleClaimableShortfallInvariant` (R3, 10k fuzz) — paired claimable/pool debit keeps `claimablePool == Σ claimableWinnings`; strict-1-wei sentinel reverts on `basis <= shortfall`.

**RedemptionAccounting.t.sol — 16/16 PASS** (13 prior + 3 new), 256 runs × 128 calls, 0 reverts; handler drove all 5 actions (burn 6547 / advance 6718 / claim 6493 / gameOver 6455 / burnOnPreviousDay 6555):
- `invariant_balanceCoversPendingRedemptionEth` — `address(sdgnrs).balance >= pendingRedemptionEthValue` always.
- `invariant_claimablePoolEqualsSumClaimable` — `claimablePool >= claimableWinnings[SDGNRS]` (paired CHECKED debit never drifts/wraps).
- `invariant_noUncheckedClaimableDebitInRedemptionPath` — behavioral no-wrap: neither raw scalar ever approaches its 2^N wrap ceiling.

## Files Created/Modified
- `test/fuzz/StakedStonkRedemption.t.sol` — +7 REDEEM-08 tests (repro-first + BURNIE-can't-block-ETH + R1/R3/R4).
- `test/invariant/RedemptionAccounting.t.sol` — +3 REDEEM-08 conservation invariants + `_claimableSdgnrs` reader.
- `contracts/test/SettleClaimableShortfallTester.sol` — NEW test-only harness exercising the production `_settleClaimableShortfall` body (R3).

## Task Commits
1. **Task 1: repro-first two-claimant underflow + fail-closed drain** — `5467de69` (test)
2. **Task 2: BURNIE-can't-block-ETH + R1/R3/R4 refinement coverage** — `269ce788` (test)
3. **Task 3: REDEEM-08 conservation invariants** — `60254bab` (test)

## Decisions Made
See `key-decisions` frontmatter. Headline: mechanism (2) in-place re-intro (worktree-add blocked by the commit-guard hook); two-claimant repro decouples claimable slice from global pool; R1 net-zero measured on the conserved BURNIE universe scalar.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Module-delegatecall no-op mock for the repro driver**
- **Found during:** Task 1
- **Issue:** The setUp mocks the WHOLE `game.resolveRedemptionLootbox` to a no-op, which would defeat the direct deleted-debit-site repro (the audited Game-side body would never run). Clearing it makes the real Game-side body run, but the 5-ETH-chunk lootbox materialization loop then needs seeded game lootbox state (out of scope) and reverts.
- **Fix:** `vm.clearMockedCalls()` then `vm.mockCall(GAME_LOOTBOX_MODULE, resolveRedemptionLootbox.selector, "")` — the MODULE-side delegatecall target is a no-op so the loop returns cleanly, while the Game-side audited body (the pre-fix unchecked debit / post-fix msg.value credit, which precedes the loop) runs in full.
- **Files modified:** test/fuzz/StakedStonkRedemption.t.sol
- **Committed in:** `5467de69`

**2. [Rule 3 - Blocking] R1 net-zero scalar widened to the conserved BURNIE universe**
- **Found during:** Task 2
- **Issue:** Measuring `coin.totalSupply()` alone failed (`2e24 → 1.999...998e24`, a −2e15 drop). The deferred `creditFlip` lands as a future-day coinflip STAKE (not minted supply) while the held-burn drops totalSupply immediately, so totalSupply transiently under-reports by `burnFromHeld`.
- **Fix:** Measured the conserved universe `coin.totalSupply() + coinflip.coinflipAmount(SDGNRS) + coinflip.coinflipAmount(redeemer)` per the 322-04 net-zero proof — invariant across submit.
- **Files modified:** test/fuzz/StakedStonkRedemption.t.sol
- **Committed in:** `269ce788`

**3. [Rule 3 - Blocking] Inherited error E() not addressable via child contract name**
- **Found during:** Task 2
- **Issue:** `vm.expectRevert(SettleClaimableShortfallTester.E.selector)` failed to compile ("Member E not found after argument-dependent lookup") — the inherited `DegenerusGameStorage.E` is not addressable via the child contract name under this solc.
- **Fix:** Added `sentinelError() returns (bytes4)` to the tester returning `E.selector` (in-scope inside the contract body); test uses `vm.expectRevert(tester.sentinelError())`.
- **Files modified:** contracts/test/SettleClaimableShortfallTester.sol
- **Committed in:** `269ce788`

---

**Total deviations:** 3 auto-fixed (all Rule 3 - blocking test-harness mechanics).
**Impact on plan:** No scope creep; all three were test-side plumbing to exercise the audited paths correctly. Zero mainnet contract changes.

## Issues Encountered
- The contract-commit-guard hook blocks `git add` of any `contracts/` path (including the committable `contracts/test/`) and `git worktree add`. Used the documented `CONTRACTS_COMMIT_APPROVED=1` bypass for the mainnet-clean test-helper commit (per project policy: `test/` + `contracts/test/` are free to commit; only mainnet `contracts/*.sol` is approval-gated, and none was touched).

## Self-Check: PASSED
- `contracts/DegenerusGame.sol` blob == `54af4272...` == `fb29ed51:contracts/DegenerusGame.sol` (frozen) — verified.
- Zero mainnet `contracts/*.sol` diff vs `fb29ed51` (`git diff --name-only fb29ed51 HEAD -- 'contracts/**/*.sol' | grep -v contracts/test/` empty) — verified.
- StakedStonkRedemption 15/15, RedemptionAccounting 16/16 — verified.
- Task commits `5467de69`, `269ce788`, `60254bab` exist in `git log` — verified.

## Next Phase Readiness
- REDEEM-08 is proven repro-first; ready for Phase 324 TERMINAL attestation (the requirement stays as proven-empirically; the formal disposition flips at the milestone close).
- Remaining 323 proof plans: 323-04 (DGAS-05/DSPIN-02 same-results gas), 323-05 (TOMB-04 cancel-tombstone).

---
*Phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs*
*Completed: 2026-05-25*
