---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
plan: 01
subsystem: testing
tags: [foundry, fuzz, vrf-freeze, keeper-router, rnglock, totalFlipReversals, autoBuy, autoOpen, non-vacuity]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the v49 keeper-router source (AfKing.doWork/autoBuy/autoOpen, DegenerusGame.boxesPending/autoOpen entry-gate, AdvanceModule cw += totalFlipReversals consume)"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "the GAS-calibrated constants (BUY_BATCH/OPEN_BATCH/OPEN_KNEE) the router perturbation exercises"
provides:
  - "TST-01 empirical proof: the router advance-consume reads only FROZEN totalFlipReversals even when doWork/autoBuy fire same-tx in the locked window (ADV-04 / v45-vrf-freeze-invariant), proven NON-VACUOUS"
  - "autoBuy-during-rngLock SAFE (queues pre-entropy, never aborts the freeze)"
  - "autoOpen-during-rngLock NO-OP (boxesPending()==false, autoOpen(N)==0, never reverts) + no-marooned-boxes (the deferred box materializes post-unlock via the cursor)"
  - "2 new _perturb classes (cls 9 doWork / cls 10 autoBuy) wired into the v43 6-phase byte-identity harness; N_PERTURB_ACTIONS 9 -> 11"
affects: [333-terminal-delta-audit-3-skill-adversarial-sweep-closure, TST-04-non-widening-ledger]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Differential non-vacuity: a zero-reversals CONTROL run must produce a DIFFERENT consumed VRF-derived word than the nudged run, proving the captured output genuinely incorporates the frozen read (the byte-identity proof cannot pass vacuously)"
    - "Per-index lootbox word (_lootboxRngWord, slot 38) as the VRF-derived output capture for the cw += totalFlipReversals consume — _finalizeLootboxRng writes exactly (rngWordCurrent + totalFlipReversals) into that slot"
    - "Active-index + word-inject idiom (CrankOpenBoxWorstCaseGas) to exercise the autoOpen cursor on a word-ready box"

key-files:
  created: []
  modified:
    - "test/fuzz/RngLockDeterminism.t.sol — +292 lines: 2 router _perturb classes + 3 TST-01 fuzz/test functions + slot/helper additions"

key-decisions:
  - "Called the DeployProtocol-deployed afKing instance directly (it lands at the pinned ContractAddresses.AF_KING via CREATE nonce addressing, so it IS the canonical keeper) — no IAfKing interface declaration needed (plan's 'use existing import surface if present')"
  - "Non-vacuity realized BOTH ways: (A) assertGt(totalFlipReversals, 0) after the pre-lock reverseFlip nudges, AND (B) a zero-reversals control digest that must differ from the baseline word — (B) proves the moved value actually flows into the consumed output, not merely that the slot changed"
  - "totalFlipReversals read via vm.load slot 5 (verified via forge inspect per VRFStallEdgeCases.t.sol:346); reverseFlip is RngLocked-gated so the nudge must move it PRE-lock"
  - "No-maroon proven WITHOUT forging the lock state: a genuine daily rngLock for the locked-no-op + deferred-box assertion; the gas-test word-inject idiom only for the post-unlock autoOpen-cursor demonstration on the active index"

patterns-established:
  - "Pattern 1: router same-tx freeze perturbation — fire afKing.doWork()/autoBuy(0) as a _perturb class inside the locked window; assert the lock does not lift and totalFlipReversals does not move (frozen request->consume)"
  - "Pattern 2: autoOpen no-op + no-maroon — boxesPending()==false / autoOpen(N)==0 during lock (no revert), then the deferred box materializes post-unlock (lootboxEthBase first-deposit signal zeroed)"

requirements-completed: [TST-01]

# Metrics
duration: 16min
completed: 2026-05-27
---

# Phase 332 Plan 01: TST-01 Freeze-Invariant Fuzz (Router Same-Tx + autoBuy-Safe + autoOpen-No-Maroon) Summary

**Extended the v43 RngLockDeterminism 6-phase byte-identity harness with the v49 keeper-router same-tx perturbation: proven NON-VACUOUSLY that the advance-consume `cw += totalFlipReversals` reads only frozen state even when `doWork`/`autoBuy(0)` fire in the same locked window, plus autoBuy-during-lock SAFE and autoOpen-blocked-no-maroon.**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-05-27T16:42:21Z
- **Completed:** 2026-05-27T16:58:18Z
- **Tasks:** 2
- **Files modified:** 1 (`test/fuzz/RngLockDeterminism.t.sol`, +292 lines)

## Accomplishments
- **TST-01 freeze proof (non-vacuous):** `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` — snapshot → nudge `totalFlipReversals` nonzero pre-lock → advance to the VRF boundary (rngLock engaged) → fire `afKing.doWork()`/`afKing.autoBuy(0)` same-tx in the locked window → deliver the SAME word → byte-identity of the advance-consumed per-index word. Two non-vacuity guards: (A) `assertGt(totalFlipReversals, 0)` confirms the perturbation moved the value; (B) a zero-reversals CONTROL run yields a DIFFERENT consumed word, proving the freeze proof cannot pass vacuously.
- **autoBuy-during-rngLock SAFE:** the same proof asserts the lock does not lift and `totalFlipReversals` does not move across the in-lock `doWork`/`autoBuy` perturbation (frozen request→consume, ADV-04).
- **autoOpen-blocked NO-OP:** `testAutoOpenBlockedDuringRngLockNoOps` — `boxesPending()==false` + `autoOpen(N)==0` during lock, no revert; the standalone `afKing.autoOpen` escape is likewise non-reverting (RD-3/RD-5 entry-gate).
- **no-marooned-boxes:** `testAutoOpenNoMaroonedBoxesAfterUnlock` — the locked `autoOpen` no-op leaves the queued box deferred (not consumed), then post-unlock the box's per-index word lands (not orphaned) and the SAME box materializes; the autoOpen cursor opens a word-ready box on the active index (the SAME-boxes-open guarantee, cursor intact).
- **2 new perturbation classes** (cls 9 `doWork()`, cls 10 `autoBuy(0)`) wired into the existing `_perturb` library; `N_PERTURB_ACTIONS` bumped 9 → 11 so all classes 0..10 are reachable via `seed % N`.

## Task Commits

Each task was committed atomically (test/ files are agent-committable):

1. **Task 1: Add router perturbation classes to the _perturb library** — `a8b93040` (test)
2. **Task 2: Add the autoBuy-safe / autoOpen-blocked-no-maroon / non-vacuity fuzz functions** — `41a49223` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) — committed separately.

## Files Created/Modified
- `test/fuzz/RngLockDeterminism.t.sol` — extended in place (locked as the TST-01 home by the roadmap):
  - `N_PERTURB_ACTIONS` 9 → 11; cls 9 = `vm.prank(actor); try afKing.doWork() {} catch`, cls 10 = `vm.prank(actor); try afKing.autoBuy(0) {} catch`.
  - `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe(uint256 seed)` — the non-vacuous router same-tx freeze byte-identity proof.
  - `testAutoOpenBlockedDuringRngLockNoOps()` — locked autoOpen no-op (no revert).
  - `testAutoOpenNoMaroonedBoxesAfterUnlock()` — deferred-box materialization + autoOpen cursor open.
  - Helpers added: `SLOT_TOTAL_FLIP_REVERSALS` (slot 5) + `_readTotalFlipReversals`, `_fundBurnie` (GAME-gated mintForGame), `SLOT_LOOTBOX_ETH_BASE` (slot 22) + `_lootboxEthBase`, `_injectActiveLootboxWord`.

## Verification

- `forge test --match-contract RngLockDeterminism` (default profile): **4 pass / 1 fail / 16 skip** — the 4 pass = `RetryLootboxRng` (pre-existing) + the 3 new TST-01 functions; the 1 fail = `testFuzz_RngLockDeterminism_StakedStonkRedemption` (the documented A7 `vm.assume` over-rejection v48-baseline red, carried forward UNCHANGED per Pitfall 2); 16 skip unchanged. The red-set did NOT widen — A7 is the only red, exactly as before the extension.
- `FOUNDRY_PROFILE=deep forge test --match-contract RngLockDeterminism --match-test "AutoBuyDuringLockSafe|AutoOpen"`: **3 pass / 0 fail** at 10000 runs.
- Non-vacuity is structurally present: the byte-identity proof asserts `controlWord != baselineWord` (the zero-reversals control), which can only hold if the consume genuinely reads `totalFlipReversals` — a no-op perturbation would make control == baseline and FAIL the test.
- `git diff --name-only contracts/` returns nothing — **ZERO `contracts/*.sol` modifications**.
- `forge build` succeeds (no errors); the sibling `RngLockRotationDeterminism` harness is unaffected (2 pass).

## Decisions Made
- See `key-decisions` frontmatter. Summary: called the deployed `afKing` directly (canonical keeper at the pinned address); dual non-vacuity (slot-read + differential control); no-maroon proven with a genuine daily lock for the no-op assertion and the gas-test word-inject idiom only for the cursor-open demonstration.

## Deviations from Plan

None affecting scope — the plan executed as written. Minor implementation-shaping choices necessary to make the proofs run GREEN against the real contract semantics (all within Task scope, no new functionality, no contract changes):

### Implementation-shaping (within plan scope)

**1. [Rule 3 - Blocking] Day-roll before the post-bootstrap advance**
- **Found during:** Task 2 (initial run failed `NotTimeYet()`)
- **Issue:** After `_completeDay`, a fresh `advanceGame()` reverts `NotTimeYet()` until the wall day rolls (AdvanceModule:223).
- **Fix:** Added `vm.warp(block.timestamp + 1 days)` after `_completeDay` in all three functions (mirrors the existing `MintTraitGeneration` template).
- **Verification:** all three functions advance to the VRF boundary cleanly.
- **Committed in:** `41a49223`

**2. [Rule 1 - Bug] Corrected lootboxEthBase storage slot + nested-mapping key encoding**
- **Found during:** Task 2 (`_lootboxEthBase` read 0 → first assertion failed)
- **Issue:** Initial helper used slot 19 and `keccak256(abi.encode(who, inner))`; the verified layout is slot 22 with the leaf encoded `keccak256(abi.encode(who, uint256(inner)))` (per `CrankOpenBoxWorstCaseGas.t.sol:251-256`).
- **Fix:** `SLOT_LOOTBOX_ETH_BASE = 22` + `uint256(inner)` leaf encoding.
- **Verification:** the first-deposit signal reads nonzero pre-open / zero post-open.
- **Committed in:** `41a49223`

**3. [Rule 1 - Bug] Restructured no-maroon to the contract's real index lifecycle**
- **Found during:** Task 2 (the daily advance bumps the active lootbox index off the queued box, so `boxesPending()`/`autoOpen` on the active index do not see a box deposited in the prior round)
- **Issue:** The first draft asserted `boxesPending()` true on the queued index post-daily-drain, but `_finalizeLootboxRng` writes the word at `LR_INDEX-1` while the active index advances to the next round — the box is NOT marooned (it is openable at its index), it is simply at a non-active cursor index.
- **Fix:** Split into two faithful sub-proofs — (1) genuine daily lock → autoOpen no-op + box deferred (not consumed), then the deferred box materializes post-unlock at its index; (2) the autoOpen cursor + boxesPending exercised on a word-ready ACTIVE index via the gas-test word-inject idiom. No lock-state forging.
- **Verification:** `testAutoOpenNoMaroonedBoxesAfterUnlock` passes; the box materializes (first-deposit signal zeroed) both via the explicit open and the cursor open.
- **Committed in:** `41a49223`

**4. [Rule 1 - Bug] ASCII string literal**
- **Found during:** Task 2 (compile error 8936 — em-dash in a non-`unicode` string literal)
- **Fix:** Replaced the em-dash with a hyphen in one assertion message.
- **Committed in:** `41a49223`

---

**Total deviations:** 4 implementation-shaping fixes (1 blocking, 3 bug), all inside Task 2's authoring scope. No scope creep, no contract changes, no new functions beyond the three the plan specifies.
**Impact on plan:** All necessary to make the proofs run GREEN against the real frozen contract semantics. The freeze invariant, non-vacuity, and no-maroon guarantees are all proven as specified.

## Issues Encountered
- The lootbox index lifecycle (word lands at `LR_INDEX-1`, active index advances to the next round) initially made a naive "queued box becomes pending on the active index after a daily drain" assertion false. Resolved by understanding the real semantics (deviation #3) — this surfaced no contract defect; it is the intended `autoOpen`-walks-the-current-round design.

## CONTEXT-Locked Constraints — Honored
- **NON-VACUOUS freeze-fuzz:** the perturbation moves `totalFlipReversals` (assertGt) AND the zero-reversals control yields a different consumed word — the proof fails if the perturbation is a no-op (T-332-01-VAC mitigated).
- **autoOpen during rngLock = NO-OP, not a revert** (Pitfall 3): no `expectRevert` on `autoOpen` during lock.
- **A7 StakedStonkRedemption carried forward UNCHANGED** (Pitfall 2): its `vm.assume` filters were not touched; it remains the same documented v48-baseline red.
- **TST-01 coupled to VRF-derived OUTPUT byte-identity, never to bounty/reward amounts** (anti-pattern avoided).
- **ZERO `contracts/*.sol` (mainnet) mutation** — the audit subject stays frozen at the committed v49 source.

## Next Phase Readiness
- TST-01 is one of the two load-bearing SECURITY proofs of Phase 332 (the other is TST-02 no-stacking). It is complete and green under both profiles.
- The 2 new `_perturb` classes + `N_PERTURB_ACTIONS=11` are available to the rest of the freeze harness (the 16 skipped functions and the edge-case multi-class functions now also exercise the router classes when un-skipped).
- No blockers. TST-02/03/04/05 (separate plans) build on the same DeployProtocol + creditFlip-count + ledger patterns.

## Self-Check: PASSED

- `test/fuzz/RngLockDeterminism.t.sol` modified (verified: 4 pass / 1 carried-forward A7 red / 16 skip; zero `contracts/` diff).
- `.planning/phases/332-.../332-01-SUMMARY.md` created (FOUND).
- Task commits `a8b93040` (cls 9/10 perturbation classes) + `41a49223` (3 TST-01 functions) FOUND in git log.

---
*Phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg*
*Completed: 2026-05-27*
