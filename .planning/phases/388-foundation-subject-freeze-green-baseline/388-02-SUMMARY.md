---
phase: 388-foundation-subject-freeze-green-baseline
plan: 02
subsystem: testing
tags: [oracle-hole, invariant-vacuity, forge-inspect, slot-validation, finding-candidate-intake, surface-map, redemption, rng-freeze, decimator]

# Dependency graph
requires:
  - phase: 388-01
    provides: the authoritative a8b702a7 storage layout key (the per-harness slot reconciliation ledger) used to slot-validate every changed-surface invariant/proof test
  - phase: v62.0-380-foundation
    provides: the c4d48008 invariant harnesses (RngWindowFreeze, PoolConservation) whose non-vacuity/falsifiability scaffolding is the EXERCISED gold standard re-confirmed here
provides:
  - 388-02-ORACLE-HOLES.md — per-test EXERCISED/HOLE/N-A audit of the 9 invariant/proof tests targeting a post-v62 changed surface, with forge-inspect slot evidence + non-vacuity/falsifiability/branch-proof run evidence
  - 388-02-FINDING-CANDIDATES.md — the consolidated 45-lead intake ledger (all 7 surface-maps), each row routed to its owning sweep phase 389-394 with source citation + severity hint + per-phase rollup
  - 1 confirmed oracle HOLE (legacy RedemptionInvariants 7-INV) routed to 390; 1 missing distribution property (decimator uint32) routed to 391
affects: [388-03, 389, 390, 391, 392, 393, 394]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Oracle-hole audit method: slot-validate every hardcoded vm.store/vm.load harness constant against forge inspect AT THE SUBJECT (a stale slot reads the wrong field at runtime while compile stays green) + confirm a non-vacuity gate / falsifiability seam / branch-was-taken precondition exists, else classify HOLE"
    - "Vacuity probe: a short invariant campaign (8x24) reading the harness call-summary (calls_claim, ghost_periodsResolved, ghost_stethLegBurns) surfaces an un-wired target path that a green campaign would otherwise hide"
    - "Exhaustive intake cross-check: count the candidate-focus rows in each map (FA/CF/F-/lead) and reconcile against the ledger row count per map so no lead is dropped between FOUNDATION and the sweeps"

key-files:
  created:
    - .planning/phases/388-foundation-subject-freeze-green-baseline/388-02-ORACLE-HOLES.md
    - .planning/phases/388-foundation-subject-freeze-green-baseline/388-02-FINDING-CANDIDATES.md
  modified: []

key-decisions:
  - "Slot-validate at the SUBJECT, not the comment era: several harness slot constants cite 'v61 PACK'/'RT-PACKING-12' but the v63 subject has further Stage A/B packing — forge inspect at a8b702a7 confirmed the sDGNRS mappings (5/6/7) and Game RNG slots (10/34/35/44/49) MATCH the post-pack comments, so only the legacy RedemptionInvariants flat slots (10/13/14/15) are stale → the single HOLE"
  - "Classify the legacy RedemptionInvariants 7-INV as a HOLE (not just stale slots): its setUp never wires setCoinflip/setStethMock, so calls_claim:0 / ghost_periodsResolved:0 after 192 calls and INV-08 split-conservation is a 0==0 tautology — the redemption rework is robustly covered by RedemptionStethFallback (10/10 branch-proofs) + RedemptionAccounting instead; closure routed to 390, NOT fixed here"
  - "Separate a false-green oracle hole from a missing property: the decimator uint32 narrowing is reached (DecimatorOffsetIsolation PASS) but NO oracle asserts the per-bucket distribution is unbiased — that is a MISSING property, routed to 391 (RNG-02), not a vacuity hole"
  - "Route, do not adjudicate: every one of the 45 leads is intaken verbatim with its map's severity hint; design-intent leads tagged VERIFY-claim per the PAPER anchor; no lead refuted/fixed in this plan"

patterns-established:
  - "Per-phase rollup count in the intake ledger (389:9 390:7 391:5 392:20 393:4 394:0) so each sweep planner knows its intake size before planning"
  - "Cross-ref tagging for leads that straddle two dimensions (e.g. box ETH-spin FC-392-08 cross-ref 390/393; decimator entropy FC-391-04 + gas-half FC-389-05) — one owning phase, explicit cross-references"

requirements-completed: [FND-04]

# Metrics
duration: 34min
completed: 2026-06-14
---

# Phase 388 Plan 02: Close Verifier Oracle Holes + Intake the 7 Surface-Maps Summary

**Audited the 9 invariant/proof tests targeting a post-v62 changed surface against the byte-frozen subject — 7 EXERCISED, 1 game-side/gap-routed, 1 HOLE (legacy redemption 7-INV: un-wired claim/stETH leg + stale slots) — and intaken all 45 leads from the 7 surface-maps into one routed finding-candidate ledger (389:9 / 390:7 / 391:5 / 392:20 / 393:4) with zero leads dropped.**

## Performance

- **Duration:** ~34 min
- **Completed:** 2026-06-14
- **Tasks:** 2/2
- **Files created:** 2 (both `.planning/` audit docs)
- **Source edits:** 0 (subject byte-frozen at `a8b702a7` throughout)

## Accomplishments

### Task 1 — Oracle-hole audit (`388-02-ORACLE-HOLES.md`, commit `1e5fd2f7`)
- Re-derived the authoritative slot key at the subject via `forge inspect` (sDGNRS: `pendingRedemptions`@5, `redemptionPeriods`@6, `pendingByDay`@7, scalars packed in slot 0; Game: `rngWordByDay`@10, `lootboxRngPacked`@34, `lootboxRngWordByIndex`@35, `decBucketOffsetPacked`@44, `terminalDecBucketBurnTotal`@49, `prizePoolsPacked`@2, `balancesPacked`@7).
- Classified each of the 9 tests with run + slot evidence:
  - **EXERCISED (7):** RngWindowFreeze (non-vacuity `afterInvariant` + falsifiability test both PASS), RedemptionAccounting (v44 per-day ghosts, slots 5/7 match), RedemptionStethFallback (10/10 deterministic branch-proofs PASS, each asserts the branch-was-taken), PoolConservation (live `*View()` getters + falsifiability), BurnieEmissionSeeds (5/5 PASS, explicit non-vacuity assert), DecimatorOffsetIsolation (PASS, self-validating `[X]`-untouched / `[X+1]`-populated), StakedStonkRedemption (per-function fuzz, slots match).
  - **EXERCISED game-side / gap routed (1):** EthSolvency — real getter-based solvency assert, but the sDGNRS redemption-credit legs are not in its action set → routed to 390.
  - **HOLE (1):** legacy RedemptionInvariants 7-INV — `setUp` never wires `setCoinflip`/`setStethMock` (short campaign: `calls_claim:0`, `ghost_periodsResolved:0`); INV-05/07 read stale slots 13/10; INV-08 is a `0==0` tautology → routed to 390 (superseded by RedemptionStethFallback + RedemptionAccounting).
  - **MISSING property (1, not false-green):** decimator uint32 distribution oracle → routed to 391 (RNG-02).

### Task 2 — Finding-candidate intake ledger (`388-02-FINDING-CANDIDATES.md`, commit `ccf620f1`)
- Walked all 7 maps' candidate-focus sections row by row and intaken **45 leads** as `FC-389..393` rows, each with CANDIDATE-ID, source map + original id, one-line restatement, severity hint, source location, and owning sweep phase.
- Exhaustiveness cross-check: storage 4/4 · gas-identity 5/5 · solvency 7/7 · rng-freeze 5/5 · reward-econ 15/15 · coinflip-burnie 5/5 · permissionless 4/4 = **45/45, no lead dropped**.
- All 9 AUDIT-V63-PLAN §6 cross-map leads present and routed to the §6-assigned phase; named-by-name: the two top BURNIE leads (auto-rebuy carry backing FC-392-16, VAULT seed window-aging FC-392-17), the EV-cap two-window eviction (FC-389-01), the decimator-uint32 distribution lead (FC-391-04).
- Design-intent leads tagged VERIFY-claim per the PAPER anchor; per-phase rollup (389:9 / 390:7 / 391:5 / 392:20 / 393:4 / 394:0).

## Deviations from Plan

None — plan executed exactly as written. Both deliverables built audit-only over the byte-frozen
subject; no contract source edit was required or made.

## Subject-freeze attestation

- `git diff a8b702a7 -- contracts/` empty throughout (re-checked after every `forge inspect` / `forge test`; `contracts/ContractAddresses.sol` restored each time).
- `git status --porcelain contracts/` empty.
- No `hardhat compile --force` run.

## Self-Check: PASSED

- `388-02-ORACLE-HOLES.md` exists (91 lines), classifies EXERCISED/HOLE, names RngWindowFreeze + Redemption.
- `388-02-FINDING-CANDIDATES.md` exists (164 lines, 45 FC rows), routes to 389-393, names auto-rebuy carry + VAULT seed window-aging.
- Commits `1e5fd2f7` (Task 1) + `ccf620f1` (Task 2) present in `git log`.
