---
phase: 381-invariant-fuzz-durable-property-net
plan: 01
subsystem: testing
tags: [foundry, invariant-fuzz, solvency, balancesPacked, claimablePool, FUZZ-01, SOLVENCY-01]

# Dependency graph
requires:
  - phase: 380-foundation
    provides: green v62 regression baseline + DeployProtocol fixture + the canonical V61SolvencyAfpay invariant (slot-7 balancesPacked read)
  - phase: 378
    provides: the post-v61 packed-balance layout [afking:hi128 | claimable:lo128] @ slot 7 (378-01 recalibration key)
provides:
  - SolvencyActionHandler — a multi-surface action handler (whale/lazy/deity pass buys + presale-box + lootbox-bearing buy + afking funding + claim + advance) over a disjoint 0x5A000 actor band with a complete trackedAddrs() cover
  - V61SolvencyAfpay now targets BOTH handlers — the packed-balance Σ identity + the bal+stETH backing bound assert over the de-duplicated UNION of the afking-only and the wider-buyer tracked sets
  - a non-vacuity gate (afterInvariant asserts pass/presale/claim successes > 0) and a falsifiability test (a seeded dropped-pairing breaks the Σ identity)
affects: [382, 383, FUZZ-02, FUZZ-03, FUZZ-04, FUZZ-05, FUZZ-06, solvency-spine-attacks]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "case (b) PROMOTE/EXTEND: a SECOND targetContract widens an EXISTING invariant's action space rather than duplicating the assertion in a new invariant"
    - "de-duplicated tracked-set UNION: both handlers append [VAULT, SDGNRS, GNRUS]; the union helper drops the trailing 3 from the second set so the protocol addrs are summed exactly once (else triple-counting inflates Σ)"
    - "afterInvariant non-vacuity gate: success counters must end > 0 so a 'passes because every action reverted' green is impossible"
    - "field-isolated falsifiability: vm.store a claimable low-half increment WITHOUT the paired claimablePool += to prove the wired equality genuinely breaks, then restore"

key-files:
  created:
    - test/fuzz/handlers/SolvencyActionHandler.sol
  modified:
    - test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol

key-decisions:
  - "PROMOTE/EXTEND not duplicate: wired SolvencyActionHandler as a second targetContract into the existing canonical invariant; the Σ identity and backing bound now cover the union of both handlers' actors"
  - "invariant_v61PoolNeverExceedsBacking needs NO address-set change — it is a global bound (claimablePool <= bal + stETH) that automatically covers the widened action space because both handlers drive the same game instance"
  - "Seeded the HAS_DEITY_PASS score bit on EVEN actors only so ODD actors keep the lazy-pass surface reachable (a deity holder cannot buy a lazy pass) — both pass surfaces stay live in one handler"
  - "Kept the [invariant] profile at the default 256/128 (no run inflation per pacing) — the widened target adds coverage within the existing budget"

patterns-established:
  - "Pattern 1: widen an invariant's action space by adding a second targetContract + a de-duplicated trackedAddrs union, never a parallel duplicate assertion"
  - "Pattern 2: every fuzz-handler ETH balance is created ONLY through a real paired entrypoint; the sole vm.store is a field-isolated score bit that touches no balancesPacked entry"

requirements-completed: [FUZZ-01]

# Metrics
duration: ~20min
completed: 2026-06-08
---

# Phase 381 Plan 01: SOLVENCY-01 widened to the pass + presale-box + claim surfaces Summary

**FUZZ-01 is now a durable always-on invariant: the post-v61 packed-balance Σ identity (claimablePool == Σ claimable-low + afking-high over the tracked union) AND the bal+stETH backing bound assert across afking spends AND whale/lazy/deity pass buys + presale-box/lootbox buys + claims — non-vacuous (success counters > 0) and falsifiable (a seeded dropped-pairing breaks it).**

## Performance

- **Duration:** ~20 min (continuation of a crashed session; RED already committed at 4e0cb132)
- **Started:** 2026-06-08T02:55:00Z (approx)
- **Completed:** 2026-06-08T03:15:02Z
- **Tasks:** 2 (Task 1 handler — pre-existing/refined; Task 2 GREEN wiring — completed)
- **Files modified:** 1 tracked (V61SolvencyAfpay.inv.t.sol) + 1 created handler (SolvencyActionHandler.sol)

## Accomplishments
- Wired `SolvencyActionHandler` as a SECOND `targetContract` into the canonical `V61SolvencyAfpay.inv.t.sol` (case (b) PROMOTE/EXTEND — no duplicated assertion).
- `invariant_v61PoolEqualsSumOfHalves` now sums the packed halves over the de-duplicated UNION of both handlers' tracked sets (actors from both bands + the 3 protocol addrs counted once).
- Added `afterInvariant()` non-vacuity gate: the widened handler's pass-buy + presale-box + claim successes must end > 0 (else the campaign fails as vacuous).
- Added `testSolvencyIdentityIsFalsifiable_droppedPairing`: a field-isolated seeded claimable increment WITHOUT the paired `claimablePool +=` breaks the Σ equality by exactly the un-paired amount, then restores — proving the wired identity is genuinely breakable over the widened set.
- Confirmed the pre-existing handler satisfies the shape test and exercises all 7 surfaces (whale/lazy/deity pass, presale-box, fund-afking, claim, advance) with thousands of 0-revert successful calls in the campaign.

## Task Commits

1. **Task 1: SolvencyActionHandler over pass + presale-box + claim surfaces** — RED at `4e0cb132` (prior session: `test(381-01)`); handler reused/refined this session, committed in the GREEN commit below.
2. **Task 2: Wire into the canonical invariant + non-vacuity + falsifiability** — GREEN at `0a1689d8` (`test(381-01)`)

**Plan metadata:** included in the GREEN commit (test-only plan; SUMMARY force-added).

## Files Created/Modified
- `test/fuzz/handlers/SolvencyActionHandler.sol` (275 lines) — multi-surface action handler; disjoint 0x5A000 actor band; complete `trackedAddrs()` cover; 7 bounded actions, each `try game.X{value:..}() catch {}`; per-surface success ghosts; the only vm.store is a field-isolated HAS_DEITY_PASS score bit (no balancesPacked entry touched).
- `test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol` (421 lines) — added the second handler import + field + `targetContract`; `_unionTrackedAddrs()` / `_sumUnionHalves()` / `_identityHoldsOverUnion()` helpers; `afterInvariant()` non-vacuity gate; `testSolvencyIdentityIsFalsifiable_droppedPairing`; widened the Σ identity to the union.

## Decisions Made
- **PROMOTE/EXTEND, not a new invariant.** The canonical assertion already reads the real slot-7 balancesPacked halves; the gap was action-space breadth, so a second target + a union of tracked sets is the correct shape.
- **`invariant_v61PoolNeverExceedsBacking` left unchanged.** It is a global bound (`claimablePool <= bal + stETH`) that iterates no address set, so it automatically covers the widened action space once both handlers drive the same `game`.
- **Even/odd deity-bit seeding.** Even actors get the HAS_DEITY_PASS bit (subscribe gate + advance bypass); odd actors stay un-seeded so the lazy-pass surface (which a deity holder cannot buy) remains reachable.
- **No run-count inflation.** Kept the default [invariant] profile (256/128) per the pacing rule.

## Deviations from Plan

None — plan executed as written. The Task 1 handler already existed from the crashed session and satisfied the shape test; it was reused (verified against the live contract signatures via grep) rather than rewritten. `invariant_v61PoolNeverExceedsBacking` correctly required no per-address change (it is a global bound), which the plan's "update both" wording anticipated only insofar as both must hold over the wider space — confirmed.

## Issues Encountered
- `forge inspect ... storageLayout` errored ("storage layout missing from artifact") under the default build profile, so the slot could not be re-derived from the artifact. Resolved by relying on the authoritative `BALANCES_PACKED_SLOT = 7` already used by the green canonical invariant and the existing handler (and locked by the task constraints + the 378-01 recalibration). Slot math was not touched.

## Verification

Targeted runs (NOT the full suite):

```
forge test --match-contract "V61SolvencyAfpay"
  -> 8 passed; 0 failed; 0 skipped (12.71s)
     invariant_v61PoolEqualsSumOfHalves  (runs 256, calls 32768, reverts 0) PASS
     invariant_v61PoolNeverExceedsBacking (runs 256, calls 32768, reverts 0) PASS
     invariant_v61AfkingDepositsGeDraws   (runs 256, calls 32768, reverts 0) PASS
     testScenarioAfkingFundedBuyPreservesIdentity PASS
     testScenarioPackedCreditDebitKeepsIdentity   PASS
     testScenarioSmiteIsPoolNeutral               PASS
     testScenarioStaleCashoutKeepsIdentity        PASS
     testSolvencyIdentityIsFalsifiable_droppedPairing PASS
   Campaign metrics: SolvencyActionHandler buyPresaleBox 2613 / claim 2430 / buyWhaleBundle 2506 /
   buyDeityPass 2511 / buyLazyPass 2518 / fundAfking 2520 / advance 2486 — all 0 reverts (non-vacuity met).

forge test --match-path "test/fuzz/handlers/SolvencyActionHandler.t.sol"
  -> 3 passed; 0 failed; 0 skipped (shape: complete cover, disjoint range, ghosts start zero)
```

Contract cleanliness: `git status --short -- 'contracts/*.sol'` is EMPTY; `git diff --stat c4d48008 -- contracts/` is EMPTY (test-infra only, ZERO contracts/*.sol mutation). The default [invariant] profile (256/128) is unchanged.

## Next Phase Readiness
- FUZZ-01 (SOLVENCY-01) is a durable always-on invariant over the wide buyer action space — ready as the solvency spine for the 382/383 council sweeps.
- Plans 381-02..06 (BoxCreationHandler, PoolFlowHandler, RngWindowFreezeHandler, etc.) have untracked handler stubs already on disk but are OUT OF SCOPE for this plan; not committed here.

## Self-Check: PASSED

- FOUND: test/fuzz/handlers/SolvencyActionHandler.sol
- FOUND: test/fuzz/invariant/V61SolvencyAfpay.inv.t.sol
- FOUND: .planning/phases/381-invariant-fuzz-durable-property-net/381-01-SUMMARY.md
- FOUND: 4e0cb132 (RED commit)
- CLEAN: zero contracts/*.sol modified or added

---
*Phase: 381-invariant-fuzz-durable-property-net*
*Completed: 2026-06-08*
