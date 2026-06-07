---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 03
subsystem: testing
tags: [forge, storage-layout, slot-recalibration, triage, non-widening, vm.store, vm.load, rng-window, degenerette, afking, keeper, lootbox]

# Dependency graph
requires:
  - phase: 378-01
    provides: the authoritative v61 storage layout (forge inspect) + the slot-shift recalibration key (§2/§3) + the frozen 2bee6d6f by-name red union (test/REGRESSION-BASELINE-v61.md)
  - phase: 378-02
    provides: the 6 gas harnesses already recalibrated (the slot-stale class partly cleared); the ~32-file behavior/non-gas tail handed to 378-03
  - phase: 376-impl
    provides: the v61 PACK fold (balancesPacked) + the slot-0 two-new-bool shift that broke the slot-hardcoded harnesses at runtime
provides:
  - "The ~32-file failing tail triaged (a)/(b)/carried/(c); class-(a) slot-stale recalibrated GREEN (177->66 failed, 111 tests red->green) — ZERO contract edits"
  - "378-03-CANDIDATE-FINDINGS.md: the complete per-file triage ledger + 3 documented out-of-union class-(c) accepted-staleness candidates (no confirmed contract bug)"
  - "Interim non-widening check PASSED: live - (2bee6d6f union ∪ documented-c) == ∅ (63 HEAD reds = 60 carried + 3 documented)"
affects: [378-04-tst-proofs, 378-05-tst06-non-widening-gate, 379-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Triage protocol: run -> read each [FAIL] reason -> classify (a)/(b)/carried/(c) against the 2bee6d6f by-name union -> recalibrate (a), update (b) expectation, leave carried red, document (c)"
    - "Authoritative-value recalibration (not a uniform delta): every slot/offset set to the live forge-inspect value; the v61 fold shifts are region-dependent (sub -3, lootbox/degenerette -2, mint/rng -1, slot-0 fields -2, time-field widths narrowed)"
    - "Interim non-widening guardrail: capture every HEAD red NAME, reconcile against (baseline union ∪ accepted-staleness ∪ accepted-behavior ∪ documented-c); any out-of-union red is investigated (slot-stale -> recalibrate; else document)"

key-files:
  created:
    - .planning/phases/378-tst-proving-tests-rng-freeze-solvency/378-03-CANDIDATE-FINDINGS.md
    - .planning/phases/378-tst-proving-tests-rng-freeze-solvency/378-03-SUMMARY.md
  modified:
    - test/fuzz/AfKingConcurrency.t.sol
    - test/fuzz/AfKingSubscription.t.sol
    - test/fuzz/V56SubHardening.t.sol
    - test/fuzz/V56FreezeSolvency.t.sol
    - test/fuzz/V56SecUnmanipulable.t.sol
    - test/fuzz/DegeneretteFreezeResolution.t.sol
    - test/fuzz/DegeneretteHeroScore.t.sol
    - test/fuzz/DegeneretteResolveRepeg.t.sol
    - test/fuzz/AffiliateDgnrsClaim.t.sol
    - test/fuzz/VRFCore.t.sol
    - test/fuzz/VRFPathCoverage.t.sol
    - test/fuzz/VRFStallEdgeCases.t.sol
    - test/fuzz/VrfRotationLiveness.t.sol
    - test/fuzz/VrfRotationOrphanIndex.t.sol
    - test/fuzz/RngFreezeAndRemovalProofs.t.sol
    - test/fuzz/RngLockDeterminism.t.sol
    - test/fuzz/RngLockRotationDeterminism.t.sol
    - test/fuzz/StallResilience.t.sol
    - test/fuzz/LootboxRngLifecycle.t.sol
    - test/fuzz/TicketLifecycle.t.sol
    - test/fuzz/KeeperFaucetResistance.t.sol
    - test/fuzz/KeeperRewardRoutingSameResults.t.sol
    - test/fuzz/KeeperRouterOneCategory.t.sol

key-decisions:
  - "class-(b) v61-behavior updates: NONE were required. Every behavioral residual was either CARRIED (in 2bee6d6f union, pre-existing) or a documented out-of-union fuzz twin of a carried sibling. The v61 behavior surface is proven POSITIVELY by the new TST-01..06 proofs (378-04/05), not by mutating regression harnesses — so no regression-harness expectation was rewritten."
  - "InvalidBet() preserved: the 24-InvalidBet Degenerette bucket was 100% slot-stale (bets seeded at the wrong degeneretteBets slot 45 instead of 43); recalibrating the slot made the bets resolve. NO InvalidBet assertion was touched/weakened — the only assertion change in all of 378-03 is a single Rule-2 hardening guard (require amt <= uint128) on a balancesPacked claimable seed."
  - "Carried baseline reds left red: 60 in-union HEAD reds (harness-isolation _queueTickets panics, deferred-lootbox-open materialization, finalize-hook events, mintBurnie advance-bounty fixtures, gap-backfill uint24/uint32 encoding, affiliate score calibration, presale tier shape, boon-roll probabilities, fuzz exhaustion). NOT fixed (non-widening discipline)."
  - "3 documented class-(c) candidates are all accepted-staleness (shared root with carried in-union siblings; no v61 contract change; NOT confirmed bugs) -> NO ## CONTRACT-CHANGE-NEEDED."

patterns-established:
  - "The interim non-widening check is load-bearing: it surfaced testFuzz_RotationFreezeInvariant_MidDay (out-of-union, vm.assume-rejected) which turned out to be slot-stale (_readMidDayFlag on stale slot 37) -> recalibrated GREEN, not an unexplained regression."
  - "Slot-0 packed-field reads need BOTH the index shift AND the bit-offset/width shift: the v61 fold added presaleOver@28 + subsFullyProcessed@29 (fields above shift -2: level 14->12, gameOver 23->21) AND narrowed the low time fields (dailyIdx uint24 @ byte 3 read >>24 not >>32; rngRequestTime uint48 @ byte 6 read >>48 not >>64)."

requirements-completed: [TST-06]

# Metrics
duration: ~3h
completed: 2026-06-07
---

# Phase 378 Plan 03: v61 Behavior/Slot Triage of the ~32-File Failing Tail Summary

**The ~32-file failing tail (plus one interim-surfaced file) triaged into (a)/(b)/carried/(c): the slot-stale class recalibrated to the authoritative v61 layout brought the full suite from 177 to 66 failed (111 tests red->green), every remaining HEAD red is explained (60 carried baseline reds + 3 documented out-of-union accepted-staleness candidates), the interim non-widening check passes (live - union == documented-only), zero class-(b) expectation rewrites were needed, and ZERO mainnet .sol bytes changed (tree-hash 87e3b45b / fingerprint fcdd999c preserved).**

## Performance

- **Duration:** ~3 h
- **Started:** 2026-06-07
- **Completed:** 2026-06-07
- **Tasks:** 3
- **Files modified:** 25 (2 created, 23 test files)

## Accomplishments

- **Triaged the full ~32-file tail** (AfKing/Degenerette/affiliate/V56 cluster + VRF/Rng/Lootbox/Ticket/Keeper/pool tail) plus `RngLockRotationDeterminism` (surfaced by the interim check). Every failing test classified (a) slot-stale / (b) v61-behavior / carried-baseline / (c) candidate in `378-03-CANDIDATE-FINDINGS.md`.
- **Recalibrated the class-(a) slot-stale reds to the authoritative v61 layout** — the dominant class. Full suite: pre-378-03 **546/177/103** -> post-378-03 **657/66/103** (111 tests red->green, ALL via slot/offset/comment recalibration).
- **Files brought FULLY GREEN:** AfKingConcurrency, V56SubHardening (crossing-eviction + D-11/12/13 surface), DegeneretteHeroScore, VrfRotationLiveness, VrfRotationOrphanIndex, RngFreezeAndRemovalProofs, LootboxRngLifecycle, KeeperFaucetResistance, RngLockRotationDeterminism.
- **Interim non-widening check PASSED:** 63 unique HEAD red names = 60 in the 2bee6d6f by-name union (CARRIED) + 3 out-of-union DOCUMENTED class-(c) candidates. `live − (union ∪ documented) == ∅`. ~111 of the 172 baseline names are now GREEN (the recalibration narrowing).
- **`InvalidBet()` preserved:** the 24-InvalidBet Degenerette bucket was 100% slot-stale (bets seeded at `degeneretteBets` slot 45 instead of 43) — recalibrating made the bets resolve. No `InvalidBet()` assertion was edited or weakened.
- **ZERO contract edits:** `git status --porcelain` on the contract tree empty at every commit; contract tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` unchanged plan start->end.

## Task Commits

Each task committed atomically (test-only — zero contract edits):

1. **Task 1: AfKing/Degenerette/affiliate/V56 cluster** — `3c04615c` (test) — 9 test files + the new CANDIDATE-FINDINGS.md
2. **Task 2: VRF/Rng/Lootbox/Ticket/Keeper tail** — `631b5c85` (test) — 13 test files + findings update
3. **Task 3 (interim-check finding): RngLockRotationDeterminism slot recalibration** — `ff4b0e9b` (test) — surfaced by the non-widening guardrail

**Plan metadata:** (this SUMMARY + STATE/ROADMAP + final findings consolidation) committed separately.

## The v61 slot/offset recalibration applied (authoritative, re-confirmed via forge inspect)

- **Mappings (region-dependent shift):** `_subOf` 65→62 · `_fundingSourceOf` 66→63 · `_subscribers` 67→64 · `_subscriberIndex` 68→65 · `_subCursor` 69→66 · `mintPacked_` 10→9 · `rngWordByDay` 11→10 · `lootboxRngPacked` 37/38→36 · `lootboxRngWordByIndex` 38/39→37 · `lootboxEthBase` 23→22 · `degeneretteBets` 45→43 · `degeneretteBetNonce` 46→44 · `levelDgnrsAllocation` 26→27 · `levelDgnrsClaimed` 27→28 · `ticketQueue` 13→12 · `ticketsOwedPacked` 14→13 (the last two were stale-HIGH even pre-v61).
- **Slot-0 packed fields (the v61 fold added `presaleOver`@28 + `subsFullyProcessed`@29, shifting the fields above DOWN 2 bytes):** `level` 14→12 · `gameOver` 23→21 · `subsFullyProcessed` 31→29 · `jackpotPhaseFlag` 17→15 · `jackpotCounter` 18→16 · `rngLockedFlag` 21→19 · `compressedJackpotFlag` 25→23 · `ticketWriteSlot` 28→26.
- **Slot-0 LOW time fields (widths narrowed):** `dailyIdx` read `>>32`→`>>24` (uint24 @ byte 3) · `rngRequestTime` read `>>64`→`>>48` (uint48 @ byte 6).
- **Unshifted (confirmed):** `claimablePool`=1, `prizePoolsPacked`=2, `prizePoolPendingPacked`=11, `balancesPacked` root=7 (semantic-only: low-128 = claimable). sDGNRS-resident slots untouched.

## Decisions Made

- **No class-(b) expectation rewrites were needed.** The plan anticipated updating expectations for `AfkingSpent` emits, curse-penalized scores, afking-covered shortfalls, the Degenerette afking tier, and the affiliate fresh/recycled split. In practice every HEAD red traced to either a slot-stale artifact (recalibrated) or a CARRIED pre-existing behavioral red (in the 2bee6d6f union). The legitimately-changed v61 behavior surface is proven POSITIVELY by the new TST-01..06 proofs authored in 378-04/05 — mutating these regression harnesses to assert the new behavior was neither necessary nor in-scope. This keeps the non-widening comparison honest (no expectation was rewritten to mask a regression).
- **The `_seedClaimable` low-128 semantic fix (Rule 2) in KeeperRewardRoutingSameResults** mirrors the 378-02 SweepPerPlayer handling: `balancesPacked` root stayed at slot 7, but writing the full word as claimable would corrupt the afking high half. Converted to read-mask-write the low 128 bits with a `require(amt <= uint128)` guard. This STRENGTHENS the harness (preserves SOLVENCY-01's afking half); it is the only assertion/require change in all of 378-03.
- **Carried-vs-candidate is decided by the 2bee6d6f by-name union, not by the [FAIL] reason.** Recalibrating a slot-stale harness frequently changes its reason (NoPass()/panic/InvalidBet() -> the underlying behavioral assertion); the in-union NAME is the ceiling, so an in-union red whose reason changed post-recalibration is still the same CARRIED red, left red.
- **3 out-of-union reds are documented (not force-fixed).** All are accepted-staleness fuzz twins of in-union carried siblings (C-1 the deferred-lootbox-open materialization; C-2 the gap-backfill uint24/uint32 encoding mismatch). Since their in-union siblings are carried-red by the non-widening discipline, force-fixing only the out-of-union twins would be inconsistent — they are documented as candidates, with the explicit note that none is a confirmed contract bug.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] KeeperRewardRoutingSameResults `_seedClaimable` wrote the full word at the balancesPacked root (afking-half corruption risk)**
- **Found during:** Task 2 (Keeper recalibration)
- **Issue:** Post-fold slot 7 is `balancesPacked` `[afking:high128 | claimable:low128]`; the existing `_seedClaimable` wrote `bytes32(amt)` as the full 256-bit word, which would zero the afking half for any seeded account.
- **Fix:** Read-mask-write the low 128 bits only (preserve the afking high half) with a `require(amt <= type(uint128).max)` guard. Mirrors the 378-02 SweepPerPlayer / 378-01 redemption semantic handling.
- **Files modified:** test/fuzz/KeeperRewardRoutingSameResults.t.sol
- **Commit:** `631b5c85`

**2. [Rule 3 - Blocking] RngLockRotationDeterminism slot-stale `vm.assume` exhaustion (surfaced by the interim non-widening check)**
- **Found during:** Task 3 (interim non-widening reconciliation)
- **Issue:** `testFuzz_RotationFreezeInvariant_MidDay` was out-of-union with `vm.assume rejected too many inputs`. Root: `_readMidDayFlag` read the stale `SLOT_LOOTBOX_RNG_INDEX=37`; the wrong-slot value never satisfied the `== 1` predicate, so `vm.assume(false)` fired on every fuzz input (a slot-stale red masquerading as fuzz exhaustion). The file was NOT in the plan's ~32-file list.
- **Fix:** Recalibrated `SLOT_LOOTBOX_RNG_INDEX` 37→36, `SLOT_LOOTBOX_RNG_WORD_BY_INDEX` 38→37 → GREEN (2/2).
- **Files modified:** test/fuzz/RngLockRotationDeterminism.t.sol
- **Commit:** `ff4b0e9b`

**Total deviations:** 2 auto-fixed (1 Rule-2 correctness hardening, 1 Rule-3 blocking slot-stale surfaced by the guardrail).
**Impact on plan:** Within scope — both are slot-recalibration/semantic-preservation consistent with the 378-01 key; zero contract edits; no scope creep.

## Carried baseline reds (left red by design — the non-widening discipline)

60 in-union HEAD reds across: TicketRouting (12), QueueDoubleBuffer (9), TicketEdgeCases (2) — `_queueTickets` harness-isolation `panic` (unchanged-by-v61 code, bare-storage harness); the Degenerette behavioral residuals (reward-gate counting, ETH conservation, per-spin draining) (8); V56 finalize-hook + deferred-lootbox-open + churn-pendingBurnie + affiliate-base-flush (≈8); mintBurnie advance-bounty fixtures (Keeper) (5); gap-backfill encoding + RngNotReady + fuzz-exhaustion (VRF/Rng) (≈7); affiliate score calibration (1); presale tier shape (3); boon-roll probabilities (2); plus the long tail. None is a v61 regression (all in the 2bee6d6f union).

## Known Stubs

None — no stub/placeholder values introduced. All edits are slot-constant/bit-offset/comment recalibrations plus one Rule-2 read-mask-write hardening.

## Candidate Findings (class-(c))

3 documented in `378-03-CANDIDATE-FINDINGS.md`, all accepted-staleness, NONE a confirmed contract bug:
- **C-1** `testFuzzTwoBlockOpenNoBlockEntropy` (V56FreezeSolvency) — deferred-lootbox-open `_openAfkingBoxAt` materialization root, shared with carried in-union siblings.
- **C-2** `test_gapBackfillEntropyUnique_fuzz` (VRFStallEdgeCases) + `test_gapBackfillWithMidDayPending_fuzz` (VRFPathCoverage) — gap-backfill `uint24`-vs-`uint32` `abi.encodePacked` encoding mismatch, shared with carried in-union siblings; the `uint24 gapDay` typing predates v61.

**No `## CONTRACT-CHANGE-NEEDED`:** every HEAD red is (a) recalibrated / carried / a documented accepted-staleness twin. No class-(c) candidate is a confirmed-real contract bug where the test is correct and a contract fix is the sole resolution.

## Contract Boundary Compliance

- **ZERO mainnet `*.sol` edits.** `git status --porcelain` on the contract tree empty at every commit; contract tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1` unchanged plan start->end (⇒ the content fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` from 378-01 is preserved).
- The two untracked WIP gas drafts (`test/fuzz/ActivityScoreStreakGas.t.sol`, `test/gas/AdvanceStageWorstCaseGas.t.sol`) left untouched as found.

## User Setup Required
None.

## Next Phase Readiness

- **378-04/05 (TST-01..06 proofs + the binding TST-06 non-widening gate):** the regression-harness slot-stale class is now cleared repo-wide; the 378-05 by-name gate runs against a HEAD whose red set is already proven a subset of (the 2bee6d6f union ∪ the 3 documented accepted-staleness candidates). The positive v61-behavior proofs are 378-04/05's charge (this plan intentionally rewrote no regression expectation).
- **379 TERMINAL:** the 3 documented class-(c) accepted-staleness candidates carry forward as known-non-bugs (fixture-driver / test-encoding limitations), not contract-fix gates.

## Self-Check: PASSED

- Created files verified present: `378-03-CANDIDATE-FINDINGS.md`, `378-03-SUMMARY.md`.
- Task commits verified in git log: `3c04615c` (Task 1), `631b5c85` (Task 2), `ff4b0e9b` (Task 3 interim-check finding).
- 23 test files modified across the three commits; all triaged/recalibrated.
- Full suite re-run: 657 passed / 66 failed / 103 skipped (826 total).
- Interim non-widening check: 63 HEAD red names = 60 in-union (carried) + 3 documented out-of-union candidates; `live − (union ∪ documented) == ∅`.
- contract tree-hash `87e3b45b` unchanged; `git status --porcelain` on the contract tree empty.

---
*Phase: 378-tst-proving-tests-rng-freeze-solvency*
*Completed: 2026-06-07*
