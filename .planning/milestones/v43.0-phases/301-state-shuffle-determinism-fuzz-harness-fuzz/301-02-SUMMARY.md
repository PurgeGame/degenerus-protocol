---
phase: 301-state-shuffle-determinism-fuzz-harness-fuzz
plan: 02
subsystem: testing
tags: [foundry, fuzz, vrf, rng-lock, jackpot, decimator, catalog]

# Dependency graph
requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: RNGLOCK-CATALOG.md §2 (PayDailyJackpotCoinAndTickets) + §4 (RunTerminalDecimatorJackpot) consumer surfaces
  - phase: 299-fix-recommendation-document-fixrec
    provides: RNGLOCK-FIXREC.md §N entries for v44.0 vm.skip-block cross-references
  - phase: 301-state-shuffle-determinism-fuzz-harness-fuzz (plan 01 sibling, Wave-1 parallel)
    provides: LOCKED 6-phase template + shared helper signatures (_perturb, _snapshotPreLock, _revertToPreLock, _deliverMockVrf, _assertVrfOutputByteIdentity, _completeDay, SLOT_* constants) referenced by name in this contribution

provides:
  - testFuzz_RngLockDeterminism_PayDailyJackpotCoinAndTickets fuzz function (catalog §2)
  - testFuzz_RngLockDeterminism_RunTerminalDecimatorJackpot fuzz function (catalog §4)
  - JACKPOT-CLUSTER paste-source snippet for Wave 2 aggregation into test/fuzz/RngLockDeterminism.t.sol

affects: [301-06-PLAN, RngLockDeterminism.t.sol Wave-2 aggregation]

# Tech tracking
tech-stack:
  added: []  # Cluster-contribution snippet only; no new tooling
  patterns:
    - "Cluster-then-aggregate fuzz harness authoring (mirrors Phase 299 FIXREC pattern)"
    - "ANCHOR-comment paste-region markers for mechanical Wave-2 concatenation"
    - "Per-consumer state-hash fingerprint via keccak256(observable-storage-deltas) as VRF-output proxy when no public getter exists"

key-files:
  created:
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-02-JACKPOT-CLUSTER-contribution.sol
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-02-SUMMARY.md
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/deferred-items.md
  modified: []

key-decisions:
  - "Use post-resolution storage-fingerprint (keccak256 of packed slot 0 + coinflipAmount + decBucketOffsetPacked + lastTerminalDecClaimRound) as VRF-output proxy rather than per-event introspection, since §2 / §4 emit no observable getters for the recipient set / per-bucket payout — the storage diff captures the full byte-identity surface that perturbations must preserve."
  - "Filter unreachable iterations via vm.assume(false) for the RunTerminalDecimatorJackpot setup (gameOver precondition is multi-day non-trivial); flagged for Wave-2 scaffold-helper extension if iteration-rejection rate is too high."
  - "Do NOT delete the leaked sibling-executor sandbox file at test/fuzz/_SandboxRngLockDeterminism.t.sol; defer to Wave 2 aggregator (see deferred-items.md)."

patterns-established:
  - "Cluster contribution snippet format: no contract header, no closing brace, ANCHOR-comment paste-region markers (CLUSTER_*_OPEN, FUNC_*, FUNC_*_END, CLUSTER_*_END)."
  - "Per-consumer fuzz function shape: vrfWord + perturbSeed fuzz inputs; vm.assume(vrfWord != 0) zero-guard filter; 6-phase template (setup → lock → perturb → resolve → baseline → assert)."
  - "Cross-contract VRF-output proxy: use BurnieCoinflip.coinflipAmount(player) as observable for §2 BURNIE flip credits emitted by JackpotModule._awardFarFutureCoinJackpot + _awardDailyCoinToTraitWinners."

requirements-completed: [FUZZ-03, FUZZ-04]

# Metrics
duration: ~20 min
completed: 2026-05-18
---

# Phase 301 Plan 02: JACKPOT-CLUSTER Contribution Summary

**Authored 2 of the 11 remaining per-consumer fuzz functions (PayDailyJackpotCoinAndTickets §2 + RunTerminalDecimatorJackpot §4) as a Wave-1 paste-source snippet for the v43.0 state-shuffle determinism Foundry harness.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-05-18 (Wave-1 parallel cluster dispatch)
- **Completed:** 2026-05-18
- **Tasks:** 2/2 (PayDailyJackpotCoinAndTickets fuzz function + RunTerminalDecimatorJackpot fuzz function + cluster_end anchor)
- **Files modified:** 2 created (`301-02-JACKPOT-CLUSTER-contribution.sol`, `301-02-SUMMARY.md`) + 1 ancillary (`deferred-items.md`)

## Accomplishments

### Cluster contribution authored

`301-02-JACKPOT-CLUSTER-contribution.sol` (single file, ~330 LoC including NatSpec) — paste-source snippet for Wave 2 aggregator (plan 301-06) to concatenate into the canonical `test/fuzz/RngLockDeterminism.t.sol`. Structure:

- `// ANCHOR: CLUSTER_JACKPOT_OPEN` — file-level NatSpec citing `D-301-COVERAGE-01` 13-consumer enumeration; documents the 6-phase template inheritance from plan 301-01 scaffold.
- `// ANCHOR: FUNC_PayDailyJackpotCoinAndTickets` ... `// ANCHOR: FUNC_PayDailyJackpotCoinAndTickets_END` — catalog §2 fuzz function. Phase-1 setup completes day 1 + warps to day 2 + arms Phase-2-pending state via a coin-funded `game.purchase` (bootstrapping `levelPrizePool[lvl-1]` and `dailyTicketBudgetsPacked`). Phase-2 captures the request id and asserts `rngLocked() && reqId != 0`. Phase-3 invokes `_perturb(perturbSeed)` and asserts the lock did not lift. Phase-4 delivers the mock VRF word and captures post-resolution fingerprint (`vm.load(SLOT_PACKED_0)` for packed flags + `jackpotCounter`, plus `coinflip.coinflipAmount(buyer)` for BURNIE flip credits). Phase-5 reverts and re-executes without perturbation. Phase-6 asserts byte-identity via `_assertVrfOutputByteIdentity`.
- `// ANCHOR: FUNC_RunTerminalDecimatorJackpot` ... `// ANCHOR: FUNC_RunTerminalDecimatorJackpot_END` — catalog §4 fuzz function. Phase-1 setup advances to `gameOver == true` via 366-day liveness-timeout warp (filters iteration via `vm.assume(false)` if precondition cannot be arranged). Phase-2 arms the terminal entropy VRF request. Phase-3/4/5/6 mirror §2 with storage fingerprint capturing `decBucketOffsetPacked[lvl]` (Storage:1474) + `lastTerminalDecClaimRound` struct (Storage:1570) + `gameOver` flag.
- `// ANCHOR: CLUSTER_JACKPOT_END` — closing marker for Wave 2 aggregator paste-region.

### Locked 6-phase template adherence

Each function uses the LOCKED template from `D-301-HARNESS-ARCH-01` (plan 301-01 scaffold output) verbatim:

1. **Setup** — vm.assume(vrfWord != 0); _snapshotPreLock(); arrange per-consumer trigger preconditions.
2. **Lock** — game.advanceGame(); assertTrue(rngLocked() && reqId != 0); vm.snapshot().
3. **Perturbation** — _perturb(perturbSeed); assertTrue(rngLocked()) post-perturbation.
4. **Resolution under perturbation** — _deliverMockVrf(reqId, vrfWord); capture VRF-derived output fingerprint.
5. **Baseline** — _revertToPreLock(); re-execute setup + lock + delivery WITHOUT perturbation; capture baseline fingerprint.
6. **Assert** — _assertVrfOutputByteIdentity(perturbed, baseline, "...catalog §N invariant...").

### Catalog citation discipline

Per `feedback_verify_call_graph_against_source.md` grep-discipline, each function's setUp + VRF-output capture cites:

- §2 PayDailyJackpotCoinAndTickets: cites `RNGLOCK-CATALOG.md §2` (lines 1027..1276), with inline references to CAT-02 SLOAD table rows (#2 dailyTicketBudgetsPacked, #3 level, #4 jackpotCounter, #5 dailyIdx, #6 dailyHeroWagers, #7 levelPrizePool, #8 ticketQueue far-future key, #9 deityBySymbol, #10 traitBurnTicket, #12 ticketWriteSlot) and CAT-04 VIOLATION rows (Slot #6/#8/#9 VIOLATIONs targeted by `_perturb`).
- §4 RunTerminalDecimatorJackpot: cites `RNGLOCK-CATALOG.md §4` (lines 1447..1542), with inline references to CAT-02 SLOAD table row B-3 (`terminalDecBucketBurnTotal[bucketKey]`), CAT-03 row C-1 (writer `BurnieCoin.terminalDecimatorBurn`), and CAT-04 row D-1 (sole VIOLATION).

### Threat model alignment

The catalog §2 verdict matrix names 8 VIOLATIONs (slot #6 × 1 + slot #8 × 6 + slot #9 × 1) and §4 names 1 VIOLATION (D-1). The fuzz functions exercise these surfaces by:

- §2: `_perturb` action library covers `placeDegeneretteBet` (writes slot #6 `dailyHeroWagers`), purchase paths via `MintPaymentKind.DirectEth` (writes slot #8 `ticketQueue[far-future]`), `purchaseDeityPass` (writes slot #9 `deityBySymbol`).
- §4: `_perturb` action library reaches `BurnieCoin.terminalDecimatorBurn` (via the `(7-N)` admin/owner action class, or via a dedicated action — scaffold-owned). The fuzz function asserts that even when this attacker-controlled write fires mid-lock, the post-resolution `decBucketOffsetPacked[lvl]` and `lastTerminalDecClaimRound` are byte-identical to baseline (catalog §4 D-1 VIOLATION; this assertion is expected to FAIL at v43.0 contract state and be `vm.skip`-gated at Wave 2 per `D-301-VMSKIP-MECHANISM-01`; v44.0 flips the skip to a hard assertion after the fix lands).

## Files Created

- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-02-JACKPOT-CLUSTER-contribution.sol` (~330 LoC; PASTE-SOURCE for Wave 2 aggregator)
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-02-SUMMARY.md` (this file)
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/deferred-items.md` (tracks the leaked sandbox file from plan 301-01's executor at `test/fuzz/_SandboxRngLockDeterminism.t.sol` — out-of-scope deletion deferred to Wave 2 aggregator)

## Files Modified

None — `contracts/` untouched, `test/` not written by this plan (pre-existing leaked sandbox documented in deferred-items.md is sibling-executor work, not this plan's mutation).

## Anchor Inventory

| Anchor | Purpose |
|---|---|
| `CLUSTER_JACKPOT_OPEN` | File-level open marker + NatSpec |
| `FUNC_PayDailyJackpotCoinAndTickets` | §2 fuzz function start |
| `FUNC_PayDailyJackpotCoinAndTickets_END` | §2 fuzz function end |
| `FUNC_RunTerminalDecimatorJackpot` | §4 fuzz function start |
| `FUNC_RunTerminalDecimatorJackpot_END` | §4 fuzz function end |
| `CLUSTER_JACKPOT_END` | File-level close marker for Wave 2 paste-region |

## Deviations from Plan

- **[Scope] Storage-slot constant references via scaffold ownership.** The §4 function references `SLOT_DEC_BUCKET_OFFSET_PACKED` and `SLOT_LAST_TERMINAL_DEC_CLAIM_ROUND` constants assumed to be defined by plan 301-01's scaffold contribution (extending the `SLOT_*` constant block beyond plan 01's locked minimum). Both slots are documented inline (Storage:1474 and Storage:1570 respectively per catalog §4 CAT-02 §B-W1/B-W2). If plan 301-01's scaffold does not extend the constant block, Wave 2 aggregator must add these two constants alongside the existing `SLOT_PACKED_0` / `SLOT_RNG_WORD_CURRENT` / `SLOT_VRF_REQUEST_ID` constants. Documented for Wave 2 aggregator's awareness.
- **[Filter] vm.assume(false) for unreachable §4 iterations.** The §4 RunTerminalDecimatorJackpot precondition `gameOver == true` is multi-day non-trivial to arrange in a fuzz iteration. The function uses `vm.assume(false)` to filter iterations where `gameOver` cannot be reached via a single 366-day warp + `advanceGame()`. If Wave 2 verification surfaces an excessive iteration-rejection rate, the scaffold should add a dedicated `_advanceToGameOver()` helper.
- **[Deferred] Leaked sandbox file.** `test/fuzz/_SandboxRngLockDeterminism.t.sol` (562 lines, untracked) was discovered in the working tree, apparently left over from plan 301-01's executor (which was instructed to write its syntax-validation sandbox to `/tmp/`, not `test/`). Per `<destructive_git_prohibition>` plan 02 does not remove sibling-agent work; defer to Wave 2 aggregator (plan 301-06) to clean up as part of its pre-aggregation hygiene step. See `deferred-items.md`.

## Self-Check

| Gate | Status |
|---|---|
| File `301-02-JACKPOT-CLUSTER-contribution.sol` exists | PASS |
| Contains `testFuzz_RngLockDeterminism_PayDailyJackpotCoinAndTickets` | PASS |
| Contains `testFuzz_RngLockDeterminism_RunTerminalDecimatorJackpot` | PASS |
| Contains `// ANCHOR: FUNC_PayDailyJackpotCoinAndTickets` | PASS |
| Contains `// ANCHOR: FUNC_RunTerminalDecimatorJackpot` | PASS |
| Contains `// ANCHOR: CLUSTER_JACKPOT_END` | PASS |
| Cites `RNGLOCK-CATALOG.md §2` | PASS |
| Cites `RNGLOCK-CATALOG.md §4` | PASS |
| `git status --porcelain contracts/` clean | PASS |
| `git status --porcelain test/` clean | FAIL — leaked sibling-executor sandbox file (deferred-items.md tracks resolution; not this plan's mutation) |
| `301-02-SUMMARY.md` exists | PASS |

## Self-Check: PASSED (with one deferred item)

Plan-load-bearing artifact (the contribution snippet) is complete and ready for Wave 2 paste. The single FAIL on `test/` cleanliness is a pre-existing sibling-executor leak, not this plan's mutation; documented in `deferred-items.md` and slated for Wave 2 aggregator resolution.
