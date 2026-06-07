---
phase: 378-tst-proving-tests-rng-freeze-solvency
plan: 04
subsystem: testing
tags: [foundry, forge, afpay-waterfall, slot-packing, cashout-curse, proving-tests, expectemit, raw-slot, seeded-fuzz]

# Dependency graph
requires:
  - phase: 376-impl-the-one-batched-contract-diff
    provides: "the shipped v61 impl (b97a7a2e) — _settleShortfall, _processMintPayment, balancesPacked accessors, maybeCurse, the curse APPLY"
  - phase: 378-01-tst-foundation
    provides: "the authoritative v61 storage layout + slot recalibration key (balancesPacked root slot 7, claimablePool slot 1 byte 16, mintPacked_ slot 9, _subOf slot 62)"
provides:
  - "V61AfpayWaterfall.t.sol — TST-01: the AFPAY waterfall (msg.value -> claimable -> afking) across all 3 pay-kinds + the shared _settleShortfall sink, AfkingSpent emitted at exact amounts, both-short revert, DirectEth-lootbox shortfall covered by afking (AFPAY-03), no-double-draw"
  - "V61Pack.t.sol — TST-02: the balancesPacked accessor round-trip + raw-slot half-isolation, claimablePool == Sigma identity under a seeded sequence, gameOver infra-afking-half preservation, no cross-half carry, two-mapping value-equivalence"
  - "V61CurseSet.t.sol — TST-03: the cashout-curse +2 SET, every exemption by contrast, the curse*100-bps penalty (floored 0) across the public view + a frozen snapshot, min(2N, cap) saturation with no uint8 wrap, same-day-second-claim revert"
affects: [378-05-non-widening-gate, 378-06-sec-rng-freeze-solvency, 379-terminal-delta-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Direct-accessor proving via SettleClaimableShortfallTester (inherits the canonical storage layout; runs the EXACT production _settleShortfall / accessor bodies — no re-implementation)"
    - "Raw-slot half-isolation: read balancesPacked (slot 7), split low/high in-test to prove the OTHER half byte-identical (not just trusting the read accessor)"
    - "Live-path _processMintPayment proof via the public purchase() entrypoint with seeded claimable/afking + vm.expectEmit AfkingSpent at exact amounts"
    - "Exemption-by-contrast: assert exempt curseCountOf==0 AND an equivalent non-exempt actor==2 so a removed bail flips the contrast"
    - "Frozen-snapshot consumer proof: the afking lootbox sub scorePlus1 (frozen at delivery) read from the Sub slot, cursed vs un-cursed twin"

key-files:
  created:
    - "test/fuzz/V61AfpayWaterfall.t.sol"
    - "test/fuzz/V61Pack.t.sol"
    - "test/fuzz/V61CurseSet.t.sol"
  modified: []

key-decisions:
  - "All three proving tests PASS against the shipped v61 impl — NO contract change needed; the v61 behavior matches the design-lock spec for AFPAY / PACK / CURSE SET"
  - "maybeCurse staleness basis is _currentMintDay() == dailyIdx (the monotonic advance counter), NOT the wall clock — TST-03 seeds dailyIdx=100 via a field-isolated slot-0 RMW so a lastEthDay-0 claimant is stale by construction"
  - "Curse penalty APPLY (CURSE-02) tested independently of the SET (CURSE-03) by seeding the curse field directly — the active-afker exemption blocks the SET, never the APPLY"
  - "prizeContribution composition proven via the prize-pool delta == cost (msg.value + claimableUsed + afkingUsed == cost), reading prizePoolsPacked slot 2 + prizePoolPendingPacked slot 11"

patterns-established:
  - "Falsifiability spot-check per surface: invert one expected value in a scratch run, confirm the test FAILS, restore — documented per the T-378-04-01/02/03 threat-register mitigations"

requirements-completed: [TST-01, TST-02, TST-03]

# Metrics
duration: 95min
completed: 2026-06-07
---

# Phase 378 Plan 04: TST-01/02/03 Proving Tests (AFPAY waterfall · PACK · CURSE SET) Summary

**Three new forge proving tests (31 tests, all green against the shipped v61 impl) certify the AfKing-as-payment waterfall, the claimable/afking slot-packing accessors, and the cashout-curse SET — with falsifiable assertions (exact expectEmit amounts, raw-slot half-isolation, exemption-by-contrast, exact penalty bps), and ZERO contract edits (fingerprint `fcdd999c…` preserved).**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-06-07T07:55:00Z (approx)
- **Completed:** 2026-06-07T09:28:36Z
- **Tasks:** 3
- **Files created:** 3 (test-only)

## Accomplishments

- **TST-01 (V61AfpayWaterfall.t.sol, 10 tests):** Proves the `msg.value -> claimable -> afking` waterfall two ways: (ARM A) the canonical shared `_settleShortfall` sink (lootbox/presale/3-whale paths all call it) via the `SettleClaimableShortfallTester` — claimable-to-strict-1-wei-sentinel then afking-to-0, `AfkingSpent(buyer, afkingUsed)` at the exact amount, the DirectEth leg (`allowClaimable=false`) skips claimable entirely, both-short reverts `E()`, the `claimablePool == Sigma(claimable + afking)` paired-debit identity, seeded fuzz over shortfall sizes; (ARM B) `_processMintPayment`'s 3 pay-kinds via the live `purchase()` path — DirectEth (afking, claimable untouched), Claimable (claimable->sentinel->afking), Combined (msg.value->claimable->afking), each with the `AfkingSpent` emit + `prizeContribution == cost`, plus the DirectEth-lootbox shortfall covered by afking (AFPAY-03, the pre-v61 revert lifted) and the no-double-draw property (the afking auto-buy never re-enters `_processMintPayment`).
- **TST-02 (V61Pack.t.sol, 8 tests):** Proves the `balancesPacked` (slot 7, `[afking:hi128 | claimable:lo128]`) accessor layer: per-half round-trip non-interference read from the RAW packed slot (a claimable credit leaves the afking high half byte-identical and vice versa — storage-level, not just accessor-level), correct-half debit + `_debitClaimable` sentinel-short revert, the `claimablePool == Sigma` identity under a seeded credit/debit sequence, the gameOver final-sweep `_debitClaimable` on VAULT/SDGNRS/GNRUS preserving their prepaid afking high half, no 127->128 cross-half carry at supply-bound magnitudes (~1.2e26 wei), and two-mapping value-equivalence vs plain counters.
- **TST-03 (V61CurseSet.t.sol, 13 tests):** Proves the cashout-curse +2 SET on a stale ghost-cashout via the public `claimWinnings`, EVERY exemption by contrast (infra / non-stale / deity-pass / whale-lazy-pass / active-afker / gameOver — exempt==0 vs equivalent non-exempt==2), `claimWinningsStethFirst` (vault-only) never cursing, the `curse*100`-bps penalty floored at 0 across the public `playerActivityScore` view AND a frozen snapshot (the afking lootbox sub `scorePlus1`) both vs un-cursed twins, the `min(2N, CURSE_COUNT_CAP=20)` stacking with cap saturation (no uint8 wrap), and the same-day-second-claim sentinel revert (no in-day stacking).
- **All three pass against the shipped v61 impl** — the v61 contract behavior matches the design-lock spec; no contract change required.

## Task Commits

Each task was committed atomically (test-only, hooks run, not pushed):

1. **Task 1: TST-01 AFPAY waterfall** — `82067d8a` (test)
2. **Task 2: TST-02 PACK accessor round-trip + solvency identity** — `df0fb002` (test)
3. **Task 3: TST-03 cashout-curse SET + exemptions + saturation** — `91a6a4f1` (test)

**Plan metadata:** (this commit) `docs(378-04): complete proving-tests plan`

## Files Created/Modified

- `test/fuzz/V61AfpayWaterfall.t.sol` (487 lines, 10 tests) — TST-01 AFPAY waterfall proof
- `test/fuzz/V61Pack.t.sol` (291 lines, 8 tests) — TST-02 PACK accessor round-trip + solvency-identity proof
- `test/fuzz/V61CurseSet.t.sol` (503 lines, 13 tests) — TST-03 cashout-curse SET + exemptions + saturation proof

No `contracts/*.sol` modified (test-only phase; fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` preserved throughout).

## Decisions Made

- **No CONTRACT-CHANGE-NEEDED.** All 31 assertions pass against the shipped v61 impl. The PROVING_TEST escalation path (a provably-correct failing test contradicting the spec → a real v61 finding) was NOT triggered — the v61 behavior is correct per the design-lock spec.
- **Staleness basis = `dailyIdx`, not the wall clock.** Discovered during TST-03 debug: `_currentMintDay()` returns `dailyIdx` (the monotonic advance counter, == 1 at fresh deploy) when non-zero, NOT `_simulatedDayIndex()`. Warping the wall clock did not move it, so a `lastEthDay=0` claimant read as non-stale (`0 + 5 > 1`). Fix: seed `dailyIdx = 100` via a field-isolated slot-0 RMW (preserving `level`/`gameOver`/the FSM flags) so a `lastEthDay=0` claimant is stale by construction. This is a TEST-setup correction, not a contract issue.
- **Curse APPLY tested independently of the SET** by seeding the curse counter directly via `vm.store` — the active-afker exemption suppresses the SET (CURSE-03) but never the penalty APPLY (CURSE-02), so a cursed active afker still has a lowered score everywhere (including the frozen afking snapshot).
- **`_processMintPayment` driven via the live public `purchase()`** (it is `private`, sole call site `recordMint` line 498) — a scratch probe confirmed the path works at a fresh game (level 0, price 0.01 ETH, targetLevel 1) and that an underpaid DirectEth ticket draws the shortfall from afking with no upfront full-payment guard.

## Deviations from Plan

None affecting scope — the plan was executed exactly as written (3 TDD test tasks, each authored + verified + committed atomically). Two TEST-side corrections were applied during authoring (not contract deviations):

### Test-side corrections (within Task 2 / Task 3 authoring)

**1. [Test-setup] TST-02 non-vacuity guard relaxed for the all-debit seed**
- **Found during:** Task 2 (the `claimablePool == Sigma` seeded-sequence fuzz)
- **Issue:** With `seed = 2^256-1`, all 9 ops selected the debit branch, which no-ops on an empty pool, leaving the non-vacuity counter at 0 (the identity itself never failed).
- **Fix:** Force the first two ops to be credits (seed a non-empty pool) so the sequence is non-vacuous for every seed; the remaining 7 ops stay seed-driven.
- **Verification:** 1000 fuzz runs green.

**2. [Test-setup] TST-03 staleness via seeded `dailyIdx`**
- **Found during:** Task 3 (the SET + all exemption contrasts)
- **Issue:** The wall-clock warp did not make claimants stale (the staleness basis is `dailyIdx`, not the simulated day).
- **Fix:** `_seedDailyIdx(100)` in `setUp` (field-isolated slot-0 RMW); `_currentDay()` reads `dailyIdx` for the non-stale contrast.
- **Verification:** 13/13 green, incl. the stale SET, all exemption contrasts, and the stacking saturation fuzz.

---

**Total deviations:** 0 contract deviations; 2 test-setup corrections (both within the test authoring, no scope change).
**Impact on plan:** None — all three surfaces proved exactly as specified.

## Falsifiability Verification (T-378-04-01/02/03 mitigations)

Each surface had at least one assertion confirmed falsifiable by a temporary inversion (then restored; contracts re-verified clean):

- **TST-01:** Inverting the DirectEth claimable-untouched expectation (`claimableBefore - 1`) FAILED (`7e18 != 6.999…e18`) — the real claimable was genuinely untouched, proving the assertion catches a waterfall-ordering violation.
- **TST-02:** Inverting the high-half-untouched raw-slot assertion (`afkingSeed + 1`) FAILED (`123e18 != 123e18+1`) — the raw afking high half stayed byte-identical after a claimable credit, proving the non-interference assertion catches a cross-half bleed.
- **TST-03:** Inverting the deity exemption (assert cursed==2) FAILED (`0 != 2`) — the deity was genuinely not cursed; and asserting the public-view penalty as `base - 800` underflowed (`600 - 800`) — proving the exact `curse*100 = 400` penalty (not 800).

## Issues Encountered

- **`_currentMintDay()` vs wall clock (TST-03):** resolved by seeding `dailyIdx` directly (see Decisions).
- **`_processMintPayment` is private (TST-01):** resolved by driving the live `purchase()` entrypoint (verified with a scratch probe that was deleted before any commit).
- **No public `prizePools()` view (TST-01):** read `prizePoolsPacked` (slot 2) + `prizePoolPendingPacked` (slot 11) directly and summed both (a contribution lands in exactly one depending on the freeze state).

## User Setup Required

None — test-only phase, no external service configuration.

## Next Phase Readiness

- TST-01/02/03 are the first three of the six TST proofs. Ready for **378-05** (the final NON-WIDENING regression gate vs the frozen baseline `2bee6d6f`) and **378-06** (SEC-01 RNG-freeze + SEC-02 SOLVENCY-01 re-attestation). The remaining TST-04 (CURE + bounty + decurse), TST-05 (SMITE), and TST-06 (non-widening) proofs are owned by later 378 plans per the roadmap.
- The contract subject remains byte-frozen (`fcdd999c…`); these tests add green and characterize the v61 AFPAY/PACK/CURSE surfaces positively (the carried-red regression set is unaffected — these are NEW files).
- No blockers.

## Self-Check: PASSED

- Files: V61AfpayWaterfall.t.sol, V61Pack.t.sol, V61CurseSet.t.sol, 378-04-SUMMARY.md — all FOUND.
- Commits: `82067d8a`, `df0fb002`, `91a6a4f1` — all FOUND in git history.
- Contract fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` — preserved; `git status --porcelain contracts/` empty.
- All 31 tests green (10 + 8 + 13); falsifiability spot-checked per surface.

---
*Phase: 378-tst-proving-tests-rng-freeze-solvency*
*Completed: 2026-06-07*
