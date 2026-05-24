---
phase: 318-tst-subscription-crank-correctness-removal-proofs-tst
plan: 01
subsystem: testing
tags: [deploy-fixture, deterministic-create-nonce, afking-subscribe, sub-09, slot-rederivation, contractaddresses-patch, deploycanary]

# Dependency graph
requires:
  - phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i (plan 08)
    provides: "Authoritative post-deletion slot map (lootboxRngPacked=35, lootboxRngWordByIndex=36); diagnosis that AF_KING=address(0) makes DeployProtocol.setUp() revert 'call to non-contract 0x0' (197/533 runnable); the 10 slot-fixed VRF/lootbox suites whose re-derivation was proven-by-derivation-only and deferred here for empirical exercise"
  - phase: 317 (contract diff)
    provides: "SUB-09 self-subscribe wiring at DegenerusVault.sol:473 + StakedDegenerusStonk.sol:379 (afKing.subscribe on IAfKingSubscribe(ContractAddresses.AF_KING))"
provides:
  - "AfKing-aware Foundry deploy fixture: AfKing deployed at N+18 (nonce 23) before VAULT/SDGNRS, public afKing handle for downstream Wave-2+ plans"
  - "AF_KING pinned to its predicted keeper address (0x3Cff...) via patchForFoundry.js; VAULT/SDGNRS/DGNRS/ADMIN/GNRUS nonce addresses shifted +1 and re-patched"
  - "DeployProtocol.setUp() no longer reverts — suite recovers from 197 runnable to 532 (472 pass / 44 fail / 16 skip)"
  - "Empirical validation of the 317-08 slot re-derivation: the 10 slot-fixed suites reach their bodies; slot-read tests pass (no slot-index drift) — RM-06 empirically confirmed"
  - "Post-repair full-suite baseline (named failing-test set) as the no-new-failures anchor for Waves 2+"
affects: [318-02, 318-03, 318-04, 318-05, 318-06, vrf-freeze-invariant, slot-re-derivation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Insert a constructor-call-free keeper into DEPLOY_ORDER immediately before its first caller (AFKING before VAULT/SDGNRS) — minimizes the downstream CREATE-nonce/address shift; patchForFoundry.js + DeployProtocol.sol nonce order must move in lockstep"
    - "Validate AfKing alignment in DeployCanary (address-equals-constant + code-length>0) so a future nonce drift fails the canary deterministically rather than silently mis-pinning the keeper gate"
    - "Disambiguate 'pre-existing vs newly-introduced' failures by grepping the failing suites for the changed surface (afKing/subscribe/AF_KING) — zero hits proves the fixture fix is failure-neutral even where the full suite still has out-of-scope behavioral failures"

key-files:
  created:
    - ".planning/phases/318-tst-subscription-crank-correctness-removal-proofs-tst/318-01-SUMMARY.md"
  modified:
    - "scripts/lib/predictAddresses.js"
    - "test/fuzz/helpers/DeployProtocol.sol"
    - "test/fuzz/DeployCanary.t.sol"
    - "contracts/ContractAddresses.sol"

key-decisions:
  - "Committed the patched ContractAddresses.sol (AF_KING populated + VAULT/SDGNRS/DGNRS/ADMIN/GNRUS +1 shift) as the deliverable — did NOT run restoreContractAddresses(). Rationale: the committed HEAD ContractAddresses.sol is ALREADY in the foundry-patched state (every constant has its real predicted address; only AF_KING was address(0)), and the stale Apr-12 .bak held a WRONG, older DEPLOY_ORDER (its ICONS_32 == current GAME_MINT_MODULE) — restoring from it would have corrupted the file. The correct clean tree IS the re-patched file. Deleted the stale .bak before re-patch so any future restore backs up from the correct HEAD-patched state."
  - "AfKing economic ctor args (5_000_000_000, 885_000_000, 10_000_000_000) mirror the degenerus-utilities AfKing smoke test — all non-zero so the 3 sanity reverts pass; AfKing's constructor makes no cross-contract calls so before-VAULT is the only ordering constraint."
  - "Added an AF_KING address assertion + code-length check to DeployCanary (the canary previously asserted 23 protocol addresses but not AfKing) so AfKing nonce-alignment is empirically gated."
  - "The 44 remaining full-suite failures are ALL pre-existing behavioral/protocol failures in the 317-08-documented families (panic 0x11 ticket-routing, RngLocked-vs-panic guard mismatch, InvalidBet, freeze assertions) plus invariant solvency/VRF-path counterexamples now reachable since setUp works — ZERO touch afKing/subscribe/AF_KING. Not chased per plan scope guard."

patterns-established:
  - "DEPLOY_ORDER (predictAddresses.js) and DeployProtocol._deployProtocol() nonce order are a single coupled unit; any insertion shifts every downstream predicted address by +1 and must be re-patched + canary-verified."

requirements-completed: [SAFE-04]

# Metrics
duration: ~10min
completed: 2026-05-23
---

# Phase 318 Plan 01: Deploy-Fixture Repair (AfKing SUB-09 Self-Subscribe) Summary

**Repaired the Foundry deploy fixture by inserting a live `AfKing` keeper at CREATE-nonce N+18 (before VAULT/SDGNRS) and re-pinning `AF_KING` off `address(0)` — `DeployProtocol.setUp()` no longer reverts "call to non-contract 0x0", recovering the runnable suite from 197 to 532 tests (472 pass / 44 fail / 16 skip) and empirically confirming the 317-08 slot re-derivation (lootboxRngPacked=35, lootboxRngWordByIndex=36) against the running EVM.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-23T21:23:46Z
- **Completed:** 2026-05-23T21:33:48Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Inserted `AF_KING` into `predictAddresses.js` `DEPLOY_ORDER` at N+18 (index 18, strictly before VAULT at 19) + `KEY_TO_CONTRACT.AF_KING = "AfKing"`; updated the constraint-comment block.
- Deployed `new AfKing(5_000_000_000, 885_000_000, 10_000_000_000)` in `DeployProtocol._deployProtocol()` at nonce 23, ahead of `new DegenerusVault()`; added a public `afKing` handle; re-numbered all downstream inline nonce comments (+1).
- Re-patched `ContractAddresses.sol` via `node scripts/lib/patchForFoundry.js`: `AF_KING` → `0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E`; VAULT/SDGNRS/DGNRS/ADMIN/GNRUS each shifted +1 (each took its old +1-nonce neighbour's address; GNRUS → new `0x886D...`).
- Extended `DeployCanary` to assert `address(afKing) == ContractAddresses.AF_KING` and `afKing.code.length > 0`; **DeployCanary 2/2 PASS**.
- Empirically exercised the 10 slot-fixed VRF/lootbox suites — they reach their bodies (zero setUp reverts) and their slot-read assertions pass; RM-06 re-derivation confirmed against the live EVM, not just `forge inspect`.
- Captured the post-repair full-suite baseline for Wave-2+ no-new-failures gating.

## Task Commits

1. **Task 1: Insert AfKing into the deterministic deploy order (JS)** - `c5ec05a4` (test)
2. **Task 2: Deploy AfKing in the fixture at the matching nonce + re-patch** - `745cd63d` (test; ContractAddresses.sol committed via CONTRACTS_COMMIT_APPROVED=1 — sole permitted contracts/ file, freely modifiable per project policy)
3. **Task 3: Empirically validate 317-08 slots + capture baseline** - no new code commit (validation/baseline-capture task; fixture from Task 2 is the artifact). Findings recorded here.

**Plan metadata:** (this commit)

## Files Created/Modified
- `scripts/lib/predictAddresses.js` - AF_KING added to DEPLOY_ORDER (N+18, before VAULT) + KEY_TO_CONTRACT; constraint comment updated.
- `test/fuzz/helpers/DeployProtocol.sol` - AfKing import + public handle + `new AfKing(...)` deploy at nonce 23; re-numbered downstream nonce comments.
- `test/fuzz/DeployCanary.t.sol` - AF_KING address assertion + AfKing code-length check.
- `contracts/ContractAddresses.sol` - re-patched: AF_KING pinned to predicted keeper; VAULT/SDGNRS/DGNRS/ADMIN/GNRUS +1 shift.

## Address Shift Table (post-AfKing-insert)

| Constant | Nonce | Before | After |
|----------|------:|--------|-------|
| AF_KING | 23 (N+18) | `address(0)` | `0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E` |
| VAULT | 24 (N+19) | `0x3Cff...854E` | `0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da` |
| SDGNRS | 25 (N+20) | `0x27cc...C4da` | `0x796f2974e3C1af763252512dd6d521E9E984726C` |
| DGNRS | 26 (N+21) | `0x796f...726C` | `0x92a6649Fdcc044DA968d94202465578a9371C7b1` |
| ADMIN | 27 (N+22) | `0x92a6...C7b1` | `0xDA5A5ADC64C8013d334A0DA9e711B364Af7A4C2d` |
| GNRUS | 28 (N+23) | `0xDA5A...4C2d` | `0x886D6d1eB8D415b00052828CD6d5B321f072073d` |

Each downstream contract inherited its old +1-nonce neighbour's address — a clean unit cascade. DeployCanary `test_allAddressesMatch` validated every constant against the freshly-deployed address.

## Empirical Slot Validation (RM-06) — the 10 317-08 slot-fixed suites

All ten reach their bodies (no "call to non-contract" setUp revert). Slot literals confirmed correct in-tree (e.g. `DegeneretteFreezeResolution.t.sol` `LOOTBOX_RNG_PACKED_SLOT=35`, `LOOTBOX_RNG_WORD_SLOT=36`; `VRFPathCoverage.t.sol` `vm.load(slot 35)` + `keccak256(abi.encode(index, 36))`). Slot-read tests pass — a wrong slot would cause wholesale wrong reads and mass failure, not the isolated behavioral failures observed.

| Suite | Result |
|-------|--------|
| LootboxRngLifecycle | 21/21 PASS (incl. `test_wordWrite*`, `test_index*`, `test_zeroGuard*` slot reads) |
| VRFStallEdgeCases | 18/18 PASS |
| VrfRotationLiveness | 6/6 PASS |
| VrfRotationOrphanIndex | 2/2 PASS |
| StallResilience | 3/3 PASS |
| VRFCore | 21/22 (1 pre-existing fail: `test_midDayRequest_doesNotBlockDaily` → `RngNotReady()`, behavioral) |
| VRFPathCoverage | 5/6 (1 pre-existing fail: `test_gapBackfillWithMidDayPending_fuzz`, mid-day-pending recovery edge; slot-read helper feeds the passing tests) |
| TicketLifecycle | 33/34 (1 pre-existing fail: `testLootboxNearRollTicketsProcessed`, ticket-routing) |
| RngIndexDrainBinding | 1/2 (1 pre-existing fail: `testBindingConsistencyDailyDrain`, drain emission) |
| DegeneretteFreezeResolution | 0/3 — all 3 fail `InvalidBet()` from `DegenerusGameDegeneretteModule.placeDegeneretteBet` (production bet-validation revert), NOT a slot error |

**DegeneretteFreezeResolution disposition:** The 317-VERIFICATION carried a WARNING that this file had wrong slots (39/38) and a pre-existing `InvalidBet()` failure. 317-08 DID re-derive its slots to 36/35 (current in-tree). With setUp now working, the 3 tests still fail `InvalidBet()` — exactly the 317-VERIFICATION prediction ("still fail with InvalidBet() not a slot-error"). The revert originates in the production `placeDegeneretteBet` module path (verified by trace), confirming the failure mode is unchanged and behavioral, not slot-driven. Out of scope for this fixture-repair plan.

## Post-Repair Full-Suite Baseline (Wave-2+ no-new-failures anchor)

**Command:** `FOUNDRY_PROFILE=default forge test --no-match-path "test/**/*.fork.t.sol"`
**Result:** `Ran 61 test suites: 472 passed, 44 failed, 16 skipped (532 total)`
(317-08 HEAD baseline was 131 pass / 66 fail / 0 skip across 197 runnable — the 197→532 recovery is this plan's effect.)

**Named failing-test set (44), grouped by pre-existing family — ZERO touch afKing/subscribe/AF_KING:**

- **panic 0x11 (ticket-routing/queue) — TicketRouting, QueueDoubleBuffer (MidDaySwap+QueueDoubleBuffer), TicketEdgeCases, CoverageGap222:** `testWriteReadIsolation`, `testFarFutureRoutesToFFKey`, `testNearFutureRoutesToWriteKey`, `testScaledFarFutureRoutesToFFKey`, `testScaledNearFutureRoutesToWriteKey`, `testRangeRoutingSplitsCorrectly`, `testQueueTicketsUsesWriteKey`, `testQueueTicketRangeUsesWriteKey`, `testQueueTicketsScaledUsesWriteKey`, `testQueueAfterSwapUsesNewWriteKey`, `testBoundaryLevel5RoutesToWriteKey`, `testBoundaryLevel6RoutesToFFKey`, `testEdge01NoDoubleCount_FFThenWriteKey`, `testEdge02RoutingPreventsNewFFDeposits`, `testMidDayProcessesReadSlotFirst`, `testMidDayRevertsNotTimeYet`, `testMidDaySwapAtThreshold`, `testMidDaySwapJackpotPhase`, `testRngGuardAllowsWithBypass`, `testRngGuardIgnoresNearFuture`
- **RngLocked()-vs-panic guard mismatch — TicketRouting:** `testRngGuardRevertsOnFFKey`, `testRngGuardScaledRevertsOnFFKey`, `testRngGuardRangeRevertsOnFirstFFLevel`
- **InvalidBet() — DegeneretteFreezeResolution:** `testDegeneretteFreezeResolutionEthConserved`, `testDegeneretteFreezeResolutionZeroPendingReverts`, `testDegeneretteUnfrozenPathRegression`
- **freeze assertions — PrizePoolFreeze:** `testFreezeUnfreezeRoundTrip` (88 != 0), `testMultiDayAccumulatorPersistence` (400 != 200)
- **VRF behavioral — VRFCore / VRFPathCoverage:** `test_midDayRequest_doesNotBlockDaily` (RngNotReady), `test_gapBackfillWithMidDayPending_fuzz`
- **lootbox/boon/drain behavioral — TicketLifecycle, RngIndexDrainBinding, GameOverPathIsolation, LootboxBoonCoexistence:** `testLootboxNearRollTicketsProcessed`, `testBindingConsistencyDailyDrain`, `testGameOverDrainsQueuedTickets`, `test_lootboxBoonAppliedDespiteExistingCoinflipBoon`, `test_parametricSweep_crossCategoryBoonFromLootbox`
- **GNRUS charity-proposal — CoverageGap222:** `test_gap_gnrus_propose_vote_paths` (note: the AfKing test in the same suite, `test_gap_afKing_coin_paths`, PASSES)
- **invariant counterexamples (now reachable since setUp works) — 8:** `invariant_ethSolvency`, `invariant_solvencyUnderDegenerette`, `invariant_allGapDaysBackfilled`, `invariant_rngUnlockedAfterSwap`, `invariant_stallRecoveryValid`, `invariant_gameSolvencyUnderVaultOps`, `invariant_solvencyUnderPressure`, `invariant_solvencyAcrossLevels`

**Failure-neutrality proof:** grepping all 19 failing suites for `afKing|\.subscribe|AF_KING` returned exactly one suite (CoverageGap222), whose *only* failing test is the unrelated GNRUS charity-proposal test — its AfKing test passes. No failure is attributable to the AfKing fixture insertion.

## Decisions Made
See `key-decisions` frontmatter. Headline: committed the re-patched `ContractAddresses.sol` (not restored) because HEAD is already the foundry-patched state and the on-disk `.bak` was a stale wrong-order leftover; the clean tree IS the re-patched file.

## Deviations from Plan

### Boundary clarifications (no Rule 1-4 auto-fixes; no architectural changes)

**1. [Restore-vs-commit ambiguity resolved toward COMMIT]**
- **Found during:** Task 2 pre-commit.
- **Issue:** The orchestrator brief preferred "restore ContractAddresses.sol to HEAD placeholder, prefer restore-to-clean." But inspection showed HEAD's ContractAddresses.sol is ALREADY the fully-patched foundry state (only AF_KING was address(0)), and the on-disk `.bak` was a stale Apr-12 wrong-order snapshot. `restoreContractAddresses()` would have corrupted the file (and dropped the real addresses). The PLAN's Task 2 explicitly directs committing the patched file (ContractAddresses freely modifiable).
- **Resolution:** Followed the PLAN — committed the re-patched file via `CONTRACTS_COMMIT_APPROVED=1` (policy-allowed for the sole permitted contracts/ file). Deleted the stale `.bak` first so the regenerated backup reflects correct HEAD state. No other contracts/*.sol touched (verified `git diff --name-only -- contracts/` == only ContractAddresses.sol).

**2. [Added AfKing assertions to DeployCanary — must-have alignment]**
- **Found during:** Task 2.
- **Issue:** The must-have requires "the AfKing address assertion pass," but DeployCanary asserted the 23 protocol addresses and omitted AfKing.
- **Fix:** Added `assertEq(address(afKing), ContractAddresses.AF_KING)` + `afKing.code.length > 0` so AfKing nonce-alignment is empirically gated. Verified PASS.

---

**Total deviations:** 0 auto-fixes; 2 boundary clarifications (both within plan/policy).
**Impact on plan:** None negative. The restore-vs-commit decision is the correct one for this repo's already-patched HEAD; the DeployCanary addition strengthens the must-have gate.

## Issues Encountered
- The 8 invariant "Replayed invariant failure from ... file" warnings are this-run counterexamples written to `cache/invariant/failures/` (16:31-16:32 today), surfaced now that setUp works and the invariant handlers execute. They are genuine protocol-level solvency/VRF-path findings, not AfKing-related and not slot-related — recorded as pre-existing in the baseline above; out of scope for this fixture-repair plan.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None introduced. (The AfKing keeper deployed in the fixture is a real `contracts/AfKing.sol` instance, not a mock or stub.)

## Threat Flags
None - this plan introduces no new network endpoint, auth path, file-access pattern, or schema change. The threat register's T-318-01-01 (DEPLOY_ORDER↔nonce alignment) and T-318-01-02 (AF_KING identity) are both mitigated and validated by the passing DeployCanary.

## Next Phase Readiness
- Fixture is green: every Wave-2+ SAFE-01..04 / JGAS-03 coverage plan can now reach test bodies.
- The named 44-failure post-repair baseline is the no-new-failures anchor; Waves 2+ must not add to it.
- Recommendation for a later plan (out of scope here): the 8 invariant solvency/VRF-path counterexamples and the panic-0x11 ticket-routing family are pre-existing behavioral findings worth triaging once the SAFE coverage suites land.

## Self-Check: PASSED

- All 4 modified files present on disk (predictAddresses.js, DeployProtocol.sol, DeployCanary.t.sol, ContractAddresses.sol) — FOUND.
- 318-01-SUMMARY.md present — FOUND.
- Task commits `c5ec05a4` + `745cd63d` exist in git log — FOUND.
- Artifact `contains` checks: `new AfKing` in DeployProtocol.sol (1), `AF_KING` in predictAddresses.js (4 — DEPLOY_ORDER + KEY_TO_CONTRACT + comment), `AF_KING` pinned in ContractAddresses.sol (1).
- DeployCanary 2/2 PASS (incl. AF_KING address + code-length assertions); setUp no longer reverts.
- `git diff --name-only -- contracts/` == only ContractAddresses.sol (no other production contract mutated); working tree clean post-commit.

---
*Phase: 318-tst-subscription-crank-correctness-removal-proofs-tst*
*Plan: 01*
*Completed: 2026-05-23*
