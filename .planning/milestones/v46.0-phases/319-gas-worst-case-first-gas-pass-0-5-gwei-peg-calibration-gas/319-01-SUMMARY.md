---
phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas
plan: 01
subsystem: gas-derivation
tags: [gas, worst-case-first, derivation-doc, gas-snapshot, placement-baseline, gas-01, gas-06, jgas-04, paper-first]

# Dependency graph
requires:
  - phase: 318-06
    provides: "the JGAS-03 305-winner single-call worst-case derivation precedent (7,503,715 gas) + the module-extending JackpotSingleCallCorrectness harness the JGAS-04 cross-reference cites"
  - phase: 317-05
    provides: "the v46 crank surface under derivation — crankBets/crankBoxes/_crankResolveBet/_crankOpenBox + the *_GAS_UNITS placeholders (DegenerusGame.sol:1501-1502) + the 2-arg _addClaimableEth"
provides:
  - "GAS-01 paper-first worst-case derivation doc (319-GAS-DERIVATION.md): three work-type structural cost derivations (resolve-bet 10-spin all-match / open-box single materialization / sweep-per-player reinvest), each with the cost-center file:line chain, structural SLOAD/SSTORE/delegatecall-depth/loop-bound count, the assert-is-worst-case precondition, and the named Wave-2 harness"
  - "the load-bearing CALIBRATION-TARGET distinction: the 10-spin all-match is the GAS-01 worst case to MEASURE; CRANK_RESOLVE_BET_GAS_UNITS pegs to the per-1-spin-item MARGINAL (REW-03 / A4 / SAFE-01 faucet floor), NOT the worst case — Plan 05 calibrates against the marginal"
  - "the JGAS-04 cross-reference: 305-winner single call already structurally derived (theory 9-12M, measured 7.5M), with the ~1.3M RM-02 freed-autoRebuyState-SLOAD delta Plan 02 attributes"
  - "GAS-06 placement +0% reference: a regenerated, documented .gas-snapshot baseline whose green deterministic placement-path subset (StorageFoundationTest packing/slot/ticket-slot + LockRemovalTest purchase rows) is the Plan-05 +0% diff target"
affects: [319-02, 319-03, 319-05, 320, jgas-04, gas-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Paper-first worst-case derivation (feedback_gas_worst_case): enumerate the source cost-center file:line chain + structural SLOAD/SSTORE/delegatecall-depth/loop-bound BEFORE measuring; the derivation fixes the SCENARIO and writes the harness's assert-is-worst-case precondition, and the structural count is a lower-bound floor (measured > structural is expected — codegen/memory/event bytes uncounted)"
    - ".gas-snapshot placement baseline: regenerate the snapshot via plain `forge snapshot` (deterministic gas: rows + seed-pinned 0xdeadbeef fuzz rows), then designate the GREEN deterministic placement-path subset as the GAS-06 +0% reference and EXCLUDE any row that sits in the pre-existing 44-failure baseline (a failing test's recorded gas is execution-to-revert, not a valid placement reference)"

key-files:
  created:
    - .planning/phases/319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas/319-GAS-DERIVATION.md
  modified:
    - .gas-snapshot

key-decisions:
  - "Mirrored the JGAS-03 318-06 derivation structure (cost-center chain -> structural count -> why-it-IS-the-max + precondition -> named harness) per the 306-05-GAS-BASELINE.md precedent cited in 319-PATTERNS; the doc is prose+tables (no fenced code per the Task-1 action constraint)"
  - "Wrote the per-1-spin-item-marginal calibration target INTO the resolve-bet section as the load-bearing distinction (the contract pays a FLAT per-item reward at DegenerusGame.sol:1567-1570, so a 10-spin all-match under-reimburses; pegging to the worst case would over-reimburse and risk the SAFE-01 self-crank faucet) — Plan 05 calibrates against the marginal, not the worst case"
  - "Regenerated .gas-snapshot with plain `forge snapshot` (NOT --match-path of a Wave-2 suite, which does not exist until Plans 02/03) — the existing 12-contract unit/invariant snapshot IS the placement reference scope; no crank/sweep/jackpot work-type rows added"
  - "Force-added BOTH the gitignored planning doc and the gitignored .gas-snapshot (.gitignore:10 ignores .gas-snapshot, and .gas-snapshot was NOT previously tracked) — same force-add discipline as the .planning/ docs per feedback_contract_commit_guard_hook"
  - "Excluded the 7 placement-adjacent FAILing rows (FreezeLifecycleTest testFreezeUnfreezeRoundTrip + testMultiDayAccumulatorPersistence; QueueDoubleBufferTest 5 rows) from the GAS-06 +0% reference set — they are part of the pre-existing 44-failure baseline (zero AfKing/crank involvement) and a failing test's snapshot gas is execution-to-revert, not a valid placement reference"

requirements-completed: [GAS-01, GAS-06]

# Metrics
duration: ~5min
started: 2026-05-24T07:54:28Z
completed: 2026-05-24T07:59:12Z
tasks: 2
files-created: 1
files-modified: 1
---

# Phase 319 Plan 01: GAS-01 Worst-Case-First Derivation + GAS-06 Placement Baseline Summary

**Produced the GAS-01 paper-first worst-case derivation document (the project HARD rule `feedback_gas_worst_case`: derive the theoretical worst case from SOURCE before measuring) — three work-type structural derivations, each constraining its Wave-2 measurement harness via a written-in assert-is-worst-case precondition — and captured the regenerated `.gas-snapshot` placement baseline that Plan 05 (GAS-06) diffs to prove placement gas is +0%. Zero `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~5 min
- **Tasks:** 2 of 2 completed
- **Files created:** 1 (`319-GAS-DERIVATION.md`, 193 lines)
- **Files modified:** 1 (`.gas-snapshot`, regenerated — 108 rows, byte-identical content to the prior on-disk copy)

## Accomplishments

### Task 1 — GAS-01 worst-case derivation doc (paper-first)

Authored `319-GAS-DERIVATION.md` with three work-type derivation sections + a JGAS-04 cross-reference, every cited line source-verified at HEAD `0d9d321f`:

- **§1 RESOLVE-BET (the headline cost center).** Cost-center chain `crankBets:1543 → _crankResolveBet:1562 (onlySelf:1641) → delegatecall resolveBets:389 → _resolveFullTicketBet:561` spin loop `0..ticketCount-1` capped at `MAX_SPINS_PER_BET = 10` (DegeneretteModule:226). Worst case = one bet, `ticketCount == 10`, EVERY spin wins ETH above the lootbox-conversion threshold → 10 lootbox materializations (each `_distributePayout:705 → _resolveLootboxDirect:783 → 2-level delegatecall → LootboxModule:628 → _resolveLootboxCommon:917 → nested BoonModule delegatecall:992 + _queueTickets SSTORE:1024`) + 10× ETH-credit SSTOREs (2-arg `_addClaimableEth:1117`) + the G3 bet-delete + ONE `creditFlip:1578`. Structural cost tabulated (loop bound, SSTORE counts, delegatecall depth, events). Precondition the harness asserts: `ticketCount == 10` + all-match.
- **§2 OPEN-BOX.** Cost-center chain `crankBoxes:1592 → G2 orphan-index skip:1603 → _crankOpenBox:1620 (onlySelf:1662) → _openLootBoxFor → the SAME _resolveLootboxCommon body`. Worst case = one ready, un-opened box = ONE materialization (≈ a single resolve-bet spin, so resolve-bet ≈ 10× a box). Flat reward per box. Precondition: box queued + `lootboxRngWordByIndex[index] != 0` + `lootboxEthBase[index][player] != 0`.
- **§3 SWEEP-PER-PLAYER (AfKing).** Cost-center chain `AfKing.sweep:522 → G13 rngLocked abort:523 → mintPrice read-once:527 → G11 cursor self-partition:532 → per-player {hasAnyLazyPass / isOperatorApproved:610 / claimableWinningsOf ×2} + the per-player batchPurchase._batchPurchaseUnit → _purchaseFor slice → ONE batchPurchase + ONE creditFlip`. Worst case = a reinvest sub whose effective buy triggers multiple lootbox materializations. The per-successful-player marginal calibrates `BOUNTY_ETH_TARGET` — an AfKing constructor immutable (AfKing.sol:252/268), so a DEPLOY-SCRIPT param, AGENT-editable, NOT a frozen-contract gate.
- **§4 JGAS-04 cross-reference.** The 305-winner daily-ETH single call is already structurally derived (theory 9-12M, 318-06 measured 7,503,715 gas < the MAINNET 30M, ~22.5M margin). The one NEW JGAS-04 piece is attributing the ~1.3M RM-02 freed `autoRebuyState` cold-SLOAD delta (1 cold SLOAD ≈ 4.2k × 305 ≈ 1.28M); structural attribution (RESEARCH option (a)) — no dead code re-introduced.

The doc also locks the **calibration-target distinction** (§1(e)): the 10-spin all-match is the GAS-01 worst case to MEASURE; `CRANK_RESOLVE_BET_GAS_UNITS` pegs to the per-1-spin-item MARGINAL per REW-03 / A4 / the SAFE-01 faucet floor (self-crank round-trip ≤ 0). It carries the structural-floor caveat (measured > structural is expected) and names every Wave-2 harness (`CrankResolveBetWorstCaseGas` / `CrankOpenBoxWorstCaseGas` / `SweepPerPlayerWorstCaseGas` / the EXTENDED `JackpotSingleCallCorrectness`).

### Task 2 — placement-hot-path `.gas-snapshot` baseline (GAS-06 +0% reference)

- **Invocation:** `forge snapshot` (plain, no `--match-path`) at HEAD `5895c78d`, after `forge build`. The whole suite ran: **541 tests succeeded, 44 failing** (the EXACT pre-existing v45 baseline — zero AfKing/crank involvement per the 318 notes). `forge snapshot` exits 0 and writes the snapshot regardless of the unrelated baseline failures.
- **Scope:** the snapshot covers the existing 12 unit/invariant test contracts (108 rows: 73 deterministic `gas:` rows + 36 seed-pinned `0xdeadbeef` fuzz `μ:/~:` rows). Per the Task-2 constraint, NO Wave-2 crank/sweep/jackpot work-type rows were added — those suites do not exist until Plans 02/03. The existing snapshot IS the placement reference scope.
- **`contracts/` clean:** `git diff --name-only -- contracts/` is EMPTY (zero production-contract mutation). The regenerated content is byte-identical to the prior on-disk `.gas-snapshot`, confirming determinism.

#### GAS-06 +0% placement reference subset (what Plan 05 diffs against)

The placement hot path is the bet/box DEPOSIT + storage-packing machinery (distinct from the resolve/crank path the crank relaxes). The GREEN, deterministic reference rows for the +0% check:

| Reference rows | Contract | Why these |
|----------------|----------|-----------|
| `testPendingPoolPacking*` (5) + `testPrizePoolPacking*` (5) + `testSlot1FieldOffsets` + `testTicketSlotKey*` / `testTicketSlotKeysDiffer*` (5) | `StorageFoundationTest` (24/24 GREEN) | the placement-path storage packing + ticket-slot keying (GAS-04 no-new-hot-path-storage); deterministic `gas:` rows |
| `test_LOCK01_purchaseDuringRngLock` + `test_LOCK01_purchaseStillRevertsOnGameOver` + `test_LOCK01_purchaseStillRevertsOnZeroQuantity` | `LockRemovalTest` (24/24 GREEN) | the deposit/purchase guard path — the placement-side gas |
| `testFuzz_costCalculation` / `testFuzz_priceBounded` / etc. (price lookup) | `PriceLookupInvariantsTest` (13/13 GREEN, seed-pinned) | the placement cost computation (supportive; seed-pinned reproducible) |

#### EXCLUDED from the reference set (one-line reasons)

These placement-adjacent snapshot rows are part of the pre-existing 44-failure baseline and MUST NOT anchor the +0% claim (a failing test's recorded snapshot gas is execution-to-revert, not a valid placement reference):

- `FreezeLifecycleTest:testFreezeUnfreezeRoundTrip` + `testMultiDayAccumulatorPersistence` — pre-existing baseline FAILs (`88 != 0`, `400 != 200`); excluded.
- `QueueDoubleBufferTest:testQueueAfterSwapUsesNewWriteKey` + `testQueueTicketRangeUsesWriteKey` + `testQueueTicketsScaledUsesWriteKey` + `testQueueTicketsUsesWriteKey` + `testWriteReadIsolation` — pre-existing baseline FAILs (arithmetic overflow panic); excluded.

Plan 05 runs `forge snapshot --check` against this committed baseline and asserts +0% on the GREEN placement reference subset only.

## GAS-01 / GAS-06 Acceptance (the proof set)

| Acceptance criterion | Where satisfied |
|----------------------|-----------------|
| Three work-type derivation sections, each with cost-center file:line chain + structural count + assert-is-worst-case precondition + named harness | `319-GAS-DERIVATION.md` §1/§2/§3 |
| Resolve-bet distinguishes the 10-spin MEASUREMENT worst case from the per-1-spin-item peg CALIBRATION target (REW-03/A4) | `319-GAS-DERIVATION.md` §1(e) |
| JGAS-04 cross-reference cites the 305-winner single call (7.5M measured, theory 9-12M) + the ~1.3M RM-02 freed-SLOAD delta | `319-GAS-DERIVATION.md` §4 |
| Every cited line matches the read_first source set (no invented citations) | verified against `contracts/` at HEAD `0d9d321f` (DegenerusGame / DegeneretteModule / LootboxModule / AfKing all confirmed this session) |
| `.gas-snapshot` regenerated via a documented `forge snapshot` invocation | Task 2 — `forge snapshot`, 541 pass / 44 pre-existing baseline fail |
| `git diff --name-only -- contracts/` EMPTY | Task 2 verify gate PASS |
| SUMMARY records the exact GAS-06 +0% placement reference rows | this section + the reference-subset table above |
| Failing-baseline placement rows excluded with a one-line reason | the EXCLUDED table above |

## Worst-Case-First Compliance (feedback_gas_worst_case)

The derivation precedes (and constrains) all Wave-2 measurement: the doc is committed at `5895c78d` BEFORE any Plan-02/03 harness runs, and each derivation section names its harness + writes the assert-is-worst-case precondition the harness must check before bracketing the call. The structural counts are the lower-bound floor; the harnesses measure the actual worst case the floor identifies.

## Deviations from Plan

None affecting scope — plan executed as written. One environment note documented as a Rule-3 blocking-issue resolution (no contract impact):

**1. [Rule 3 - Blocking] `.gas-snapshot` is gitignored AND was untracked**
- **Found during:** Task 2 commit prep.
- **Issue:** `.gitignore:10` ignores `.gas-snapshot`, and `git ls-files` showed it was NOT previously tracked. A plain `git add .gas-snapshot` would silently no-op, leaving the GAS-06 baseline uncommitted.
- **Fix:** Force-added it (`git add -f .gas-snapshot`), the same discipline the project uses for the gitignored `.planning/` docs per `feedback_contract_commit_guard_hook`. No contract impact.
- **Files modified:** `.gas-snapshot` (now committed).

## Known Stubs

None. The derivation doc is a complete source-traced artifact (no TODO/placeholder/empty-value stubs); the `.gas-snapshot` is the live regenerated baseline. The two `120_000` `*_GAS_UNITS` PLACEHOLDER constants in `DegenerusGame.sol:1501-1502` are NOT a stub of this plan — they are the calibration TARGET that Plan 05 resolves under the USER-APPROVED contract gate; this plan only derives the framing that constrains that calibration.

## Threat Flags

None. This plan introduces no new network endpoint, auth path, file-access pattern, or schema change. The derivation explicitly preserves every GAS-05 guard (G1 RngNotReady freeze, G2 orphan-index skip, G3/G4 one-reward, G7/G9 isolation+authority, G8/G10/G11/G13 sweep guards) as load-bearing and never as an optimization target (`feedback_security_over_gas`).

## Contract-Cleanliness Note

`git diff --name-only -- contracts/` is EMPTY across both task commits. The only working-tree changes are the new `.planning/` derivation doc, this SUMMARY, the regenerated (gitignored, force-added) `.gas-snapshot`, and the standard `.planning/` state/roadmap/requirements updates.

## Self-Check: PASSED

- `319-GAS-DERIVATION.md` exists on disk (193 lines; three derivation sections + JGAS-04 cross-reference; `MAX_SPINS_PER_BET`, `CrankResolveBetWorstCaseGas`, and the per-1-spin-item-marginal text all present — Task-1 verify gate PASS).
- `.gas-snapshot` exists on disk (108 rows), regenerated via the documented `forge snapshot` invocation; `git diff --name-only -- contracts/` empty (Task-2 verify gate PASS).
- Task 1 committed at `5895c78d` (`git log --oneline` confirms).
- This SUMMARY exists on disk at the plan directory.
