---
phase: 306-test-tst
plan: 04
subsystem: RngLockDeterminism vm.skip → strict-assertion flip (HANDOFF-111 / V-184)
tags: [TST, vmskip-flip, V-184, HANDOFF-111, REG-01, v44.0, structural-closure]

requires:
  - phase: 304-spec-invariant-model-spec
    provides: SPEC-01..05 design locks + INV-01..13 invariant model + EDGE-01..18 scenarios + §3 EDGE-07 V-184 attack-vector specification
  - phase: 305-implementation-impl
    plan: 01
    provides: v44.0 per-day-keyed redemption source (D-305-STORAGE-01) + single-pool sentinel INV-13 (D-305-SENTINEL-01) + zero-drift accounting (D-305-GWEI-SNAP-01) + MIN_BURN_AMOUNT=1e18 floor (D-305-DUST-FLOOR-01)

provides:
  - V-184-cross-day-re-roll-strict-assertion-attestation
  - HANDOFF-111-explicit-closure (load-bearing strict-assertion flip)
  - HANDOFF-112..117-structural-closure (6 subsumed catalog rows close via FIXREC §0.6 subsumption — no vm.skip blocks existed)
  - REG-01-NON-WIDENING-minimal-diff-surface
  - load-bearing-input-for-FINDINGS-v44.0.md-§3.D-RESOLVED-AT-V44

affects:
  - 308-terminal (FINDINGS-v44.0.md §3.D RESOLVED-AT-V44 cites the 7-row attribution table verbatim)

tech-stack:
  added: []
  patterns:
    - "Strict byte-identity assertion (`_assertVrfOutputByteIdentity`) against mid-rngLock-window state perturbation — the per-day storage keying makes the V-184 overwrite primitive structurally unreachable, so the test PASSES against v44 source for the same reason it FAILED at v43.0 close"
    - "Minimal-diff regression-test edit envelope (1 deletion + 4 in-place edits + 2 new natspec lines) — REG-01 NON-WIDENING posture preserved"
    - "v44 MIN_BURN_AMOUNT compatibility bounds — fuzz inputs forced into the legal-burn range [1e18, 100e18] so the test exercises the V-184 attack vector legitimately (instead of vacuous-pass via `BurnTooSmall` filter-out)"

key-files:
  modified:
    - test/fuzz/RngLockDeterminism.t.sol

key-decisions:
  - "D-306-04-MINBURN-BOUND-01: bound(burnAmountSeed, 1, 1_000) → bound(burnAmountSeed, 1e18, 100e18). v43.0-era bound produces sub-MIN_BURN_AMOUNT (1e18) values; at v44 those revert BurnTooSmall and the try/catch{vm.assume(false);} filters out 100% of fuzz inputs (vacuous-pass). The [1e18, 100e18] bound exercises the V-184 attack vector with non-trivial pool sizes."
  - "D-306-04-PERTURB-MIN-01: sdgnrs.burn(1) → sdgnrs.burn(1e18) in the perturbation branch (perturbSeed % 7 == 0). Same MIN_BURN_AMOUNT compatibility rationale — 1 wei reverts BurnTooSmall under v44, leaving the perturbation branch a no-op; 1e18 is the minimum legal v44 burn and successfully mutates state mid-rngLock-window."
  - "D-306-04-NATSPEC-FLIP-01: line-1277 natspec rewritten SKIP → FLIPPED. Per feedback_no_history_in_comments.md, the comment describes the CURRENT state (FLIPPED) — not narration of 'what changed' or 'used to be SKIP'. The natspec is the load-bearing cross-reference anchor for FINDINGS-v44.0.md §3.D V-184 RESOLVED-AT-V44."

requirements-completed:
  - TST-05
  - REG-01

duration: ~10min (single-line flip + bound adjustments + verification + SUMMARY)
completed: 2026-05-19
---

# Phase 306 Plan 04 — V-184 / HANDOFF-111 vm.skip → Strict Assertion Flip

**The load-bearing v44.0 closure assertion for FINDINGS-v44.0.md §3.D V-184 RESOLVED-AT-V44 is now mechanized: `testFuzz_RngLockDeterminism_StakedStonkRedemption` PASSES at FOUNDRY_PROFILE=deep × 10,000 fuzz runs, asserting byte-identical VRF-derived sStonk redemption outputs across mid-rngLock-window state perturbation against the v44 per-day-keyed source.**

## Performance

- **Started:** 2026-05-19
- **Completed:** 2026-05-19
- **Tasks:** 2 (single-file edit + SUMMARY + atomic commit envelope)
- **Files modified:** 1 (test/fuzz/RngLockDeterminism.t.sol)
- **Commits:** 1 atomic AGENT-COMMITTED test-tree envelope (handler + SUMMARY) per `D-43N-TEST-COMMITS-AUTO-01`
- **Fuzz runs (deep profile):** 10,000 × testFuzz_RngLockDeterminism_StakedStonkRedemption = 10,000 byte-identity assertions PASSED; mean gas ~10.88M; median ~10.85M; wall time 2.31s

## The single-line flip + edits

### Before (v43.0 closure HEAD)

```solidity
function testFuzz_RngLockDeterminism_StakedStonkRedemption(
    uint256 vrfWord,
    uint256 perturbSeed,
    uint256 burnAmountSeed
) public {
    // SKIP: RNGLOCK-FIXREC.md sec103 -- V-184 sStonk cross-day re-roll CATASTROPHE -- v44.0 D-43N-V44-HANDOFF-111 flips this to strict assertion
    vm.skip(true);
    vm.assume(vrfWord != 0);
    ...
    uint256 burnAmount = bound(burnAmountSeed, 1, 1_000);
    ...
    if (perturbSeed % 7 == 0) {
        vm.prank(holder);
        try sdgnrs.burn(1) returns (uint256, uint256, uint256) {} catch {}
    }
    ...
}
```

### After (v44.0 close — this plan)

```solidity
function testFuzz_RngLockDeterminism_StakedStonkRedemption(
    uint256 vrfWord,
    uint256 perturbSeed,
    uint256 burnAmountSeed
) public {
    // FLIPPED at v44.0: RNGLOCK-FIXREC.md sec103 -- V-184 sStonk cross-day re-roll CATASTROPHE -- D-43N-V44-HANDOFF-111 strict-assertion attestation; structural closure via per-day storage keying (304-SPEC §3 EDGE-07)
    vm.assume(vrfWord != 0);
    ...
    // v44 MIN_BURN_AMOUNT floor: bound legal-burn range to [1e18, 100e18]
    uint256 burnAmount = bound(burnAmountSeed, 1e18, 100e18);
    ...
    if (perturbSeed % 7 == 0) {
        vm.prank(holder);
        // v44 MIN_BURN_AMOUNT: minimum legal perturbation burn
        try sdgnrs.burn(1e18) returns (uint256, uint256, uint256) {} catch {}
    }
    ...
}
```

## HANDOFF-111..117 7-row closure attribution table

The planner prompt + ROADMAP §306 Success Criterion 4 claim "HANDOFF-111..117 7 vm.skip(true) blocks REMOVED + strict byte-identity assertion in place; all 7 previously-skipped fuzz cases PASS". Reality per pre-flip `grep "vm.skip(true)" test/fuzz/RngLockDeterminism.t.sol` against v43.0 baseline `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`: 17 total vm.skip(true) blocks in the file, but only ONE is anchored to the V-184 / HANDOFF-111 cluster (line 1278; explicitly tagged with "RNGLOCK-FIXREC.md sec103 -- V-184" + "D-43N-V44-HANDOFF-111"). The other 16 anchor to UNRELATED HANDOFF-NN entries (HANDOFF-01 jackpot day-roll, HANDOFF-13 prizePoolsPacked, HANDOFF-43 Cluster G lootbox commitment, HANDOFF-77 lastPurchaseDay phantom, HANDOFF-99 decimator-claim, HANDOFF-110 bountyOwedTo, HANDOFF-31 claimablePool gameover) which defer to v45.0+ FIX-MILESTONEs per their own per-line natspec — they are NOT in v44.0's narrow scope per ROADMAP "narrow scope" guarantee.

The 6 catalog rows V-186/V-188/V-190/V-191/V-192/V-193 subsumed by V-184 per FIXREC §0.6 fan-out do NOT have distinct vm.skip blocks — they collapse into HANDOFF-111 structurally:

| HANDOFF-NN | Catalog Row | Closure Path                                                                                              | Anchor                                                                                                            |
|------------|-------------|-----------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| HANDOFF-111 | V-184      | **EXPLICIT** — this plan's strict-assertion flip (TST-05) + Plan 02 EDGE-07 V-184 reproduction (TST-04) | `testFuzz_RngLockDeterminism_StakedStonkRedemption` line 1278 (flipped) + `testFuzz_EDGE_07_V184AttackReproduction` |
| HANDOFF-112 | V-186      | **SUBSUMED** by V-184 per FIXREC §0.6; closes structurally via per-day storage keying                    | No vm.skip block existed at v43.0; structural closure via 304-SPEC §3 EDGE-07 + Plan 305-01 D-305-STORAGE-01     |
| HANDOFF-113 | V-188      | **SUBSUMED** by V-184 per FIXREC §0.6; structural closure                                                | Same — per-day storage keying makes the overwrite primitive unreachable                                          |
| HANDOFF-114 | V-190      | **SUBSUMED** by V-184 per FIXREC §0.6; structural closure                                                | Same                                                                                                              |
| HANDOFF-115 | V-191      | **SUBSUMED** by V-184 per FIXREC §0.6; structural closure                                                | Same                                                                                                              |
| HANDOFF-116 | V-192      | **SUBSUMED** by V-184 per FIXREC §0.6; structural closure                                                | Same                                                                                                              |
| HANDOFF-117 | V-193      | **SUBSUMED** by V-184 per FIXREC §0.6; structural closure                                                | Same                                                                                                              |

**Closure accounting:** 1 vm.skip block flipped (HANDOFF-111 — load-bearing strict-assertion anchor) + 6 catalog rows close structurally (no vm.skip blocks existed for them at v43.0) = 7 of 7 HANDOFF-111..117 closed at v44.0 per Phase 308 FINDINGS-v44.0.md §3.D RESOLVED-AT-V44 attestation matrix.

Phase 308 §3.D RESOLVED-AT-V44 will attest the 7-row closure via:
1. **TST-05** (this plan's strict-assertion flip — 1 explicit anchor at line 1278)
2. **TST-04** (Plan 02 EDGE-07 V-184 attack-reproduction negative assertion — `testFuzz_EDGE_07_V184AttackReproduction` in `test/fuzz/RedemptionEdgeCases.t.sol`)
3. **304-SPEC §3 EDGE-07 cross-reference** to FIXREC §0.6 subsumption map (the 6 subsumed rows close because the underlying overwrite primitive is gone — no per-row test needed)
4. **Phase 306 Plan 01 INV-13** (single-pool invariant — `invariant_INV_13_SinglePoolPending` — PROVEN at FOUNDRY_PROFILE=deep × 256000 calls; mechanizes the structural property that backs the closure)

## REG-01 v43.0 NON-WIDENING attestation

`git diff MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2 -- test/fuzz/RngLockDeterminism.t.sol` shows the cumulative v43.0 → v44.0-closure diff for this file. Diff scope enumeration (verified at SUMMARY write-time):

| # | Source         | Lines touched | Description                                                                                                                |
|---|----------------|---------------|----------------------------------------------------------------------------------------------------------------------------|
| a | Phase 305 IMPL (commit `213f9184`) | 3 lines (line 376 surrounding context) | Phase 305 Mutation 27 — `vault.sdgnrsClaimRedemption()` → `vault.sdgnrsClaimRedemption(claimDay)` 1-arg cascade fix; surfaced by `forge build` after sStonk's 1-arg `claimRedemption(uint32 day)` shipped |
| b | Plan 04 (this plan) — Task 1 step 1 | 2 lines (line 1277-1278) | natspec rewrite (SKIP → FLIPPED) + vm.skip(true) line REMOVED |
| c | Plan 04 (this plan) — Task 1 step 2 | 2 lines (line 1295-1296) | new natspec comment + `bound(burnAmountSeed, 1, 1_000)` → `bound(burnAmountSeed, 1e18, 100e18)` |
| d | Plan 04 (this plan) — Task 1 step 3 | 2 lines (line 1314-1315) | new natspec comment + `sdgnrs.burn(1)` → `sdgnrs.burn(1e18)` |

**NO OTHER LINES touched.** All 16 v45.0+ deferred vm.skip(true) blocks PRESERVED VERBATIM (verified: `grep -c "vm.skip(true);" test/fuzz/RngLockDeterminism.t.sol` = 16 at HEAD; one fewer than the 17 v43.0 baseline). The 9 other natspec markers anchoring those blocks (lines 403, 474, 546, 630, 734, 823, 950, 1036, 1152, 1211, 1350, 1561, 1597, 1641, 1685, 1736) are untouched.

Plan 04 contributes (b)+(c)+(d); Phase 305 contributed (a) at commit `213f9184`. REG-01 NON-WIDENING attestation: SATISFIED.

## v45.0+ deferred coverage roster

The 16 OTHER vm.skip(true) blocks remaining in the file (preserved verbatim at v44.0 close, deferred to v45.0+ FIX-MILESTONES per their own per-line natspec markers):

| File line | HANDOFF-NN anchor (per per-line natspec)                  | Cluster                          |
|-----------|-----------------------------------------------------------|----------------------------------|
| 403       | HANDOFF-01 / sec1 — jackpot day-roll                      | Jackpot RNG-window               |
| 474       | HANDOFF-13 / sec2 — prizePoolsPacked                      | Jackpot RNG-window               |
| 546       | HANDOFF-43 / sec3 — Cluster G lootbox commitment          | Lootbox commitment-window        |
| 630       | HANDOFF-77 / sec4 — lastPurchaseDay phantom               | Mint accounting                  |
| 734       | HANDOFF-99 / sec6 — decimator-claim                       | Decimator                        |
| 823       | HANDOFF-110 / sec7 — bountyOwedTo                         | Bounty                           |
| 950       | HANDOFF-31 / sec8 — claimablePool gameover                | Gameover                         |
| 1036      | HANDOFF-NN / sec9                                          | Cross-day rngLock                |
| 1152      | HANDOFF-NN / sec10                                         | Cross-day rngLock                |
| 1211      | HANDOFF-NN / sec11                                         | Cross-day rngLock                |
| 1350      | HANDOFF-NN / sec5 — GameOverRngSubstitution                | RNG substitution                 |
| 1561      | HANDOFF-NN / sec13                                         | Cross-day rngLock                |
| 1597      | HANDOFF-NN / sec14                                         | Cross-day rngLock                |
| 1641      | HANDOFF-NN / sec15                                         | Cross-day rngLock                |
| 1685      | HANDOFF-NN / sec16                                         | Cross-day rngLock                |
| 1736      | HANDOFF-NN / sec17                                         | Cross-day rngLock                |

(per-line natspec authoritative; the table above is for orientation — the canonical anchor is the in-file natspec)

These 16 blocks defer to v45.0+ as deliberate scoping decisions per ROADMAP narrow-scope guarantee — v44.0 closes ONLY the sStonk cluster (V-184 + 6 subsumed = HANDOFF-111..117). Each remaining block has its own per-line FIXREC sec-NN anchor that the v45.0+ plan-phase will consume as load-bearing input.

## Verification

```
$ cd /home/zak/Dev/PurgeGame/degenerus-audit
$ forge build --quiet 2>&1 ; echo "EXIT=$?"
EXIT=0

$ FOUNDRY_PROFILE=deep forge test --match-path "test/fuzz/RngLockDeterminism.t.sol" --match-test "testFuzz_RngLockDeterminism_StakedStonkRedemption"

Ran 1 test for test/fuzz/RngLockDeterminism.t.sol:RngLockDeterminism
[PASS] testFuzz_RngLockDeterminism_StakedStonkRedemption(uint256,uint256,uint256) (runs: 10000, μ: 10879427, ~: 10851474)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 2.31s (2.30s CPU time)

Ran 1 test suite in 2.31s (2.31s CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)

$ grep -c "vm.skip(true);" test/fuzz/RngLockDeterminism.t.sol
16

$ grep -c "FLIPPED at v44.0: RNGLOCK-FIXREC.md sec103" test/fuzz/RngLockDeterminism.t.sol
1
```

All 4 acceptance criteria PASS.

## Deviations from Plan

None — plan executed exactly as written. The 3 prescribed edits (vm.skip removal + bound adjustment + perturbation-burn adjustment) + 2 inline natspec additions + 1 natspec rewrite landed verbatim per the `<action>` block. Total diff surface: 1 deletion + 4 in-place edits + 2 new natspec lines = MINIMAL DIFF per REG-01 NON-WIDENING posture, matching the plan's acceptance criteria gate. No incidental whitespace edits; no other vm.skip blocks touched.

## Self-Check: PASSED

All Phase 306 Plan 04 success criteria met:

- ✓ 1 `vm.skip(true)` line removed from `test/fuzz/RngLockDeterminism.t.sol` at original line 1278 (the V-184 / HANDOFF-111 block; explicit tag `RNGLOCK-FIXREC.md sec103 -- V-184` + `D-43N-V44-HANDOFF-111`)
- ✓ 2 burn-amount expressions rebounded to v44 MIN_BURN_AMOUNT-compatible values (line 1295 `bound(burnAmountSeed, 1, 1_000)` → `bound(burnAmountSeed, 1e18, 100e18)`; line 1314 `sdgnrs.burn(1)` → `sdgnrs.burn(1e18)`)
- ✓ Natspec at line 1277 rewritten from SKIP to FLIPPED at v44.0 — describes the CURRENT state per `feedback_no_history_in_comments.md`
- ✓ `forge build` exits 0
- ✓ `testFuzz_RngLockDeterminism_StakedStonkRedemption` PASSES at FOUNDRY_PROFILE=deep × 10,000 fuzz runs (zero failures across 10k mid-window perturbation samples)
- ✓ `grep -c "vm.skip(true);" test/fuzz/RngLockDeterminism.t.sol` returns 16 (one fewer than v43.0 baseline's 17 — verified via `git show 8111cfc5:test/fuzz/RngLockDeterminism.t.sol | grep -c "vm.skip(true);"` returns 17)
- ✓ `grep -c "FLIPPED at v44.0: RNGLOCK-FIXREC.md sec103" test/fuzz/RngLockDeterminism.t.sol` returns 1
- ✓ `git diff test/fuzz/RngLockDeterminism.t.sol` shows EXACTLY the 6 prescribed line-level changes (1 deletion + 4 in-place edits + 2 new natspec lines) — no incidental edits
- ✓ Zero `contracts/*.sol` mutations in this commit envelope
- ✓ All 16 v45.0+ deferred vm.skip(true) blocks PRESERVED VERBATIM (their per-line natspec anchors untouched)
- ✓ Phase-305-applied compile-cascade fix at line 376 (`vault.sdgnrsClaimRedemption(claimDay)` 1-arg form, shipped at commit `213f9184`) PRESERVED — not touched in this plan
- ✓ REG-01 NON-WIDENING attested: `git diff 8111cfc5 -- test/fuzz/RngLockDeterminism.t.sol` consists ONLY of (a) Phase 305 line-376 cascade fix + (b)+(c)+(d) Plan 04's 3 prescribed edits

## Handoff to Phase 308 TERMINAL

Phase 308's `audit/FINDINGS-v44.0.md` §3.D RESOLVED-AT-V44 attestation can grep this SUMMARY for the 7-row HANDOFF-111..117 closure attribution table (verbatim citation). The closure path resolves to:

- **HANDOFF-111 (V-184)** explicit via `testFuzz_RngLockDeterminism_StakedStonkRedemption` strict byte-identity assertion (PROVEN at FOUNDRY_PROFILE=deep × 10,000 runs)
- **HANDOFF-112..117 (V-186/V-188/V-190/V-191/V-192/V-193)** structural via FIXREC §0.6 subsumption — per-day storage keying makes the overwrite primitive unreachable; INV-13 single-pool invariant mechanizes the property at Plan 01 PROVEN at 256,000 calls
- **REG-01 NON-WIDENING** attested via the minimal-diff envelope (4 line-level changes total in this file across the v43.0→v44.0 closure delta, plus Phase 305's 3-line cascade fix at line 376)

The 7-row closure attribution + REG-01 attestation are load-bearing inputs for the v44.0 FINAL READ-only audit deliverable at Phase 308 closure HEAD.
