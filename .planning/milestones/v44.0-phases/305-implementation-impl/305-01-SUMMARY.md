---
phase: 305-implementation-impl
plan: 01
subsystem: sStonk per-day redemption refactor IMPL
tags: [IMPL, sStonk, per-day-keying, V-184-structural-elimination, v44.0, single-pool-invariant, INV-13, 1-slot-DayPending, gwei-snap, batched-contract-diff]

requires:
  - phase: 304-spec-invariant-model-spec
    provides: SPEC-01..05 design locks + INV-01..12 invariant model + EDGE-01..18 scenarios + §5 source-verified citation manifest (61 citations VERIFIED at v43.0 baseline HEAD 8111cfc5)

provides:
  - v44.0-storage-layout-break
  - per-day-keyed-redemption (composite-key pendingRedemptions + DayPending pool)
  - V-184-structural-elimination (per-day storage keying + single-pool sentinel)
  - HANDOFF-111..117-structural-closure (V-184 + 6 subsumed catalog rows)
  - single-pool-invariant-INV-13 (pendingResolveDay sentinel; at-most-one-unresolved-day)
  - exact-gwei-accounting (zero drift between pool aggregate, cumulative scalar, and per-claim payouts)
  - 1-slot-DayPending (4×uint64 with denomination conversion)
  - min-burn-floor (MIN_BURN_AMOUNT = 1e18, BurnTooSmall revert)
  - multi-day-rng-stall-correctness (sentinel-driven dayToResolve)
  - vault-1-arg-claim (sdgnrsClaimRedemption(uint32 day))

affects:
  - 306-tst (Foundry invariant + fuzz coverage; INV-01..13; EDGE-01..20; gas regression bench)
  - 307-sweep (3-skill adversarial sweep against v44 source)
  - 308-terminal (FINDINGS-v44.0.md 9-section deliverable)

tech-stack:
  added: []
  patterns:
    - "Writer-stamp sentinel with single-pool invariant (pendingResolveDay 32-bit slot, INV-13)"
    - "Mixed-denomination storage with arithmetic equivalence (gwei for ETH/BURNIE pool aggregates, whole-tokens for supply/burned, wei for cumulative scalar — exact equivalence via gcd(1e9, 100)=100)"
    - "Source-snap denomination alignment (ethValueOwed/burnieOwed snapped to gwei at computation point; downstream arithmetic structurally exact)"

key-files:
  created:
    - .planning/phases/305-implementation-impl/305-01-GREP-VERIFICATION.md
  modified:
    - contracts/StakedDegenerusStonk.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/interfaces/IStakedDegenerusStonk.sol
    - contracts/DegenerusVault.sol
    - test/fuzz/RedemptionGas.t.sol
    - test/fuzz/CoverageGap222.t.sol
    - test/fuzz/handlers/RedemptionHandler.sol
    - test/fuzz/RngLockDeterminism.t.sol

key-decisions:
  - "D-305-SENTINEL-01: pendingResolveDay sentinel slot enforces single-pool invariant (INV-13). Partially reverses SPEC §2.7 deletion 1 (redemptionPeriodIndex) — re-introduces a stamp slot but with stricter semantics (PriorDayUnresolved revert blocks cross-day pool accumulation). Surfaced during execution via user question about multi-day RNG stall behavior; the original SPEC-03 'dayToResolve = day - 1' derivation left burn-day pools permanently stuck post-stall (fund-loss bug)."
  - "D-305-STRUCT-TIGHTEN-01: DayPending 3-slot → 1-slot via 4×uint64 with denomination conversion (gwei for ETH/BURNIE, whole-tokens for supply/burned). Saves ~44k gas per first-burn-of-day, ~10k per subsequent same-day burn. Revises SPEC-01 field types."
  - "D-305-DUST-FLOOR-01: MIN_BURN_AMOUNT = 1e18 (1 whole sDGNRS) gambling-burn floor. Required by whole-token cap accounting; preserves INV-10 (per-day supply cap) via ceiling-divide on amount → amountWhole."
  - "D-305-GWEI-SNAP-01: ethValueOwed/burnieOwed snapped to gwei at computation source. Eliminates pool↔cumulative-scalar drift AND per-claim sub-roll floor-div dust. Result: zero accounting drift across the full lifecycle (proof: gcd(1e9, 100) = 100, so any multiple-of-1e9 wei value divides exactly by 100 for any integer roll)."
  - "D-305-DAYTORESOLVE-01: AdvanceModule reads sdgnrs.pendingResolveDay() instead of deriving dayToResolve = day - 1. Multi-day RNG stalls handled by construction — the sentinel always names the (at most one) stuck day exactly."
  - "Vault scope-expansion: contracts/DegenerusVault.sol added to the batched diff (local IStakedDegenerusStonkBurn interface + sdgnrsClaimRedemption(uint32 day) signature update). Compile-cascade from sStonk's 1-arg claimRedemption(uint32 day); planner missed this caller in the 'exactly 5 files' lock. User authorized scope expansion during execution."

patterns-established:
  - "Single-pool invariant via writer's-stamp sentinel: at-most-one-unresolved-day enforced by PriorDayUnresolved revert in the writer (_submitGamblingClaimFrom). Simplifies INV-09 (skipped-advance recovery) to trivial: at most one pool exists, so 'oldest-first ordering' collapses to 'the only ordering'."
  - "Denomination-aligned packing: pack 4 storage fields into 1 slot by choosing denominations that respect each field's realistic range. gwei (1e9 wei) for ETH/BURNIE aggregates; whole-tokens (1e18 raw) for supply/burned. uint64 holds ~11500× headroom over 10k-wallet-day scenarios."
  - "Source-snap for arithmetic exactness: snap derived wei values to gwei at the computation point (not at storage write). Downstream multiplication by roll ∈ [25, 175] divided by 100 is then EXACT (no floor-div dust) because gcd(1e9, 100) = 100."
  - "Ceiling-divide for conservative cap accounting: amount → amountWhole via (amount + 1e18 - 1) / 1e18 ensures burned-tracker is always ≥ actual cumulative burns, preserving INV-10 even when amount isn't an exact multiple of 1e18."

requirements-completed:
  - IMPL-01
  - IMPL-02
  - IMPL-03
  - IMPL-04

duration: ~3h (planning + execution + interactive amendment cycles)
completed: 2026-05-19
---

# Phase 305 Plan 01 — v44.0 sStonk per-day redemption refactor

**V-184 catastrophe + HANDOFF-111..117 close STRUCTURALLY via per-day storage keying + single-pool sentinel; multi-day RNG stalls handled by construction via the pendingResolveDay sentinel; full-lifecycle accounting drift is zero post-Mutation 26 (gwei-snap-at-source).**

## Performance

- **Started:** 2026-05-19 (planning + plan checker passed Phase 305 plan at commit 10cc60ad)
- **Completed:** 2026-05-19T12:41:49Z
- **Tasks:** 2 (grep-verification artifact + batched contract diff)
- **Files modified:** 8 (4 contracts + 4 test files)
- **Commits:** 2 (`c6f7045b` Task 1 artifact + `213f9184` Task 2 atomic contract diff)
- **Mutations applied:** 27 total (14 from plan + 13 from interactive amendment cycles)

## Accomplishments

1. **V-184 cross-day re-roll catastrophe closed structurally.** Per-day mapping keying (`redemptionPeriods[day]`) plus delete-at-resolve plus single-pool sentinel (INV-13) make the overwrite primitive physically unreachable. The 6 catalog rows subsumed by V-184 (V-186/V-188/V-190/V-191/V-192/V-193) close in the same shot.

2. **Multi-day RNG stall fund-loss bug closed.** Discovered during execution when the user asked "how does this all work if there is a multi day rng stall". The original SPEC-03 `dayToResolve = day - 1` derivation left burn-day pools permanently stuck under multi-day stalls. Fixed via the `pendingResolveDay` sentinel (D-305-SENTINEL-01) — AdvanceModule now reads the sentinel instead of computing `day - 1`, so the stuck pool is always named correctly regardless of stall duration.

3. **1-slot DayPending packing with exact accounting.** Reduced DayPending storage cost from SPEC-01-locked 3 slots → 1 slot via denomination conversion. Combined with gwei-snap-at-source (D-305-GWEI-SNAP-01), the full-lifecycle accounting drift is zero — the gwei snap aligns all eth values to multiples of 1e9, and `gcd(1e9, 100) = 100` means `value × roll / 100` is exact for any integer roll. Pool↔cumulative drift = 0; per-claim sub-roll floor-div dust = 0.

4. **All 4 IMPL requirements satisfied.** IMPL-01 (storage refactor), IMPL-02 (`_submitGamblingClaimFrom` rewrite), IMPL-03 (`resolveRedemptionPeriod` 3-arg + AdvanceModule call sites), IMPL-04 (`claimRedemption(uint32 day)` + composite read + delete-on-full-claim).

## Task Commits

1. **Task 1: Pre-patch grep-verification manifest** — `c6f7045b` (docs)
2. **Task 2: Batched contract diff (1-slot DayPending + INV-13 sentinel + gwei snap)** — `213f9184` (feat)

_NO `git push` executed per `feedback_manual_review_before_push.md` D-305-APPROVAL-04. Separate user approval required before push._

## Files Created/Modified

**Contracts (mainnet — USER-APPROVED):**
- `contracts/StakedDegenerusStonk.sol` — Primary refactor target. 10 SPEC-locked mutations + 5 augment mutations (sentinel + 1-slot struct + dust floor + gwei snap).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 3 call-site updates: sentinel-keyed resolves at `:1230` (rngGate primary), `:1293` (_gameOverEntropy stale-VRF), `:1323` (_gameOverEntropy fallback).
- `contracts/interfaces/IStakedDegenerusStonk.sol` — `hasPendingRedemptions(uint32)` + `resolveRedemptionPeriod(uint16, uint32, uint32)` signature updates + new `pendingResolveDay()` view.
- `contracts/DegenerusVault.sol` — [scope-expansion beyond plan's 5-file lock] Local `IStakedDegenerusStonkBurn.claimRedemption` updated to 1-arg; `sdgnrsClaimRedemption()` → `sdgnrsClaimRedemption(uint32 day)`.

**Test files (AGENT-COMMITTED in same atomic commit per `feedback_no_contract_commits.md` clarified policy):**
- `test/fuzz/RedemptionGas.t.sol` — 5 compile-break sites (resolveRedemptionPeriod 2→3-arg + claimRedemption 0→1-arg + hasPendingRedemptions 0→1-arg × 2).
- `test/fuzz/CoverageGap222.t.sol` — 2 selector-string updates (`:948` resolveRedemptionPeriod selector + `:955` claimRedemption selector).
- `test/fuzz/handlers/RedemptionHandler.sol` — 2 claim sites updated + fuzz bound floor raised to `1e18` (matches new MIN_BURN_AMOUNT).
- `test/fuzz/RngLockDeterminism.t.sol` — 1 site (sdgnrsClaimRedemption now passes `currentDayView() - 1` claim day).

**Planning artifact (Task 1):**
- `.planning/phases/305-implementation-impl/305-01-GREP-VERIFICATION.md` — 86-row citation re-verification table (66 sStonk + 11 AdvanceModule + 9 test-file sites). 86/86 VERIFIED-NO-DRIFT against v43.0 baseline HEAD `8111cfc5`.

## The 27 mutations (in execution order)

### Plan mutations 1-14 (SPEC §2 + §2.7 deletions + signature changes)

| # | Mutation | SPEC anchor |
|---|----------|-------------|
| 1 | DELETE `error UnresolvedClaim()` at sStonk:108 | §2.7 deletion 6 |
| 2 | REMOVE `uint32 periodIndex` from `PendingRedemption` struct | SPEC-02 |
| 3 | ADD `DayPending` struct declaration | SPEC-01 |
| 4 | RE-KEY `pendingRedemptions` to composite (player, day) | SPEC-02 |
| 5 | DELETE 5 storage slots (pendingRedemptionEthBase/BurnieBase, redemptionPeriodSupplySnapshot/Index/Burned) | §2.7 deletions 1-5 |
| 6 | ADD `mapping(uint32 => DayPending) pendingByDay` | SPEC-01 + D-305-STORAGE-01 |
| 7 | REWRITE `hasPendingRedemptions(uint32 day)` body | SPEC-03 |
| 8 | REWRITE `resolveRedemptionPeriod` 3-arg + delete-at-resolve | SPEC-03 + SPEC-04(c) |
| 9 | REWRITE `claimRedemption(uint32 day)` composite-key | SPEC-02 + SPEC-04(d) |
| 10 | REWRITE `_submitGamblingClaimFrom` lazy-init + per-day write | SPEC-01 + SPEC-02 + SPEC-04(b) + SPEC-05 |
| 11 | UPDATE `IStakedDegenerusStonk.sol` 2 signatures | SPEC-03 |
| 12 | UPDATE AdvanceModule 3 call sites (initial `day - 1` form) | D-305-DAYTORESOLVE-01 |
| 13 | FIX `test/fuzz/RedemptionGas.t.sol` 5 compile-break sites | D-305-TESTBREAK-01 |
| 14 | FIX `test/fuzz/CoverageGap222.t.sol` 2 selector strings | D-305-TESTBREAK-01 |

### Scope-expansion mutations 15-16 (Vault + handler — surfaced by `forge build` cascade failures)

| # | Mutation | Notes |
|---|----------|-------|
| 15 | UPDATE `contracts/DegenerusVault.sol` (local IStakedDegenerusStonkBurn + sdgnrsClaimRedemption signature) | Mainnet contract — user-authorized scope expansion |
| 16 | FIX `test/fuzz/handlers/RedemptionHandler.sol` 2 claim sites | Test compile-break |

### Sentinel mutations 17-19 (INV-13 single-pool — surfaced by user's multi-day stall question)

| # | Mutation | Notes |
|---|----------|-------|
| 17 | ADD `PriorDayUnresolved` error + `pendingResolveDay` slot + sentinel check/set in burn + sentinel clear in resolve | D-305-SENTINEL-01 |
| 18 | ADD `pendingResolveDay()` view to interface | D-305-SENTINEL-01 |
| 19 | REFACTOR AdvanceModule 3 sites: read `sdgnrs.pendingResolveDay()` instead of `day - 1` | D-305-DAYTORESOLVE-01 (revised) |

### Tightening mutations 20-25 (1-slot DayPending + dust floor — surfaced by user's gas optimization questions)

| # | Mutation | Notes |
|---|----------|-------|
| 20 | TIGHTEN `DayPending` struct from 3 slots → 1 slot (4×uint64 with denomination conversion) | D-305-STRUCT-TIGHTEN-01 |
| 21 | ADD `MIN_BURN_AMOUNT = 1e18` constant + `BurnTooSmall` error | D-305-DUST-FLOOR-01 |
| 22 | ADD `revert BurnTooSmall` guard + ceiling-divide on amount → amountWhole | D-305-DUST-FLOOR-01 |
| 23 | UPDATE supplySnapshot/burned to whole-token denomination | D-305-STRUCT-TIGHTEN-01 |
| 24 | UPDATE resolve to convert gwei → wei for cumulative scalar reconciliation | D-305-STRUCT-TIGHTEN-01 |
| 25 | UPDATE RedemptionHandler fuzz bound floor to 1e18 | D-305-DUST-FLOOR-01 |

### Gwei-snap mutation 26 (exact accounting — surfaced by user's drift question)

| # | Mutation | Notes |
|---|----------|-------|
| 26 | ADD gwei-snap on ethValueOwed/burnieOwed at computation source in `_submitGamblingClaimFrom` | D-305-GWEI-SNAP-01 — eliminates all drift; downstream `× roll / 100` is exact since `gcd(1e9, 100) = 100` |

### Cascade test-fix mutation 27 (RngLockDeterminism cascade)

| # | Mutation | Notes |
|---|----------|-------|
| 27 | FIX `test/fuzz/RngLockDeterminism.t.sol` site (vault.sdgnrsClaimRedemption now 1-arg) | Test compile-cascade from Mutation 15 |

## Citations Re-verified

Task 1 generated `.planning/phases/305-implementation-impl/305-01-GREP-VERIFICATION.md` re-verifying 86 cited file:line locations:
- 66 rows in `contracts/StakedDegenerusStonk.sol` (304-SPEC §5.1)
- 11 rows in `contracts/modules/DegenerusGameAdvanceModule.sol` (304-SPEC §5.2)
- 9 rows in test files (305-CONTEXT.md `<domain>` + 305-01-PLAN.md `<interfaces>`)

**§D verdict: 86/86 VERIFIED-NO-DRIFT** against v43.0 baseline HEAD `8111cfc5`. `git diff --stat 8111cfc5..HEAD` for the 5 contract+test target files returned empty — working tree was byte-identical to baseline at the start of Task 2.

## V-184 closure attestation

V-184 catastrophe + HANDOFF-111..117 (the 7-row sStonk catalog from `audit/FINDINGS-v43.0.md` §9d) close **STRUCTURALLY** at v44.0 closure by **absence of the overwrite primitive**:

1. **Per-day storage keying** — each day's `redemptionPeriods[D]` is a distinct mapping slot. No single-pool aliasing exists.
2. **Single-pool sentinel (INV-13)** — at most one day's pool may be unresolved at any time; same-day post-resolve re-burns are structurally impossible because the sentinel either matches the current day (re-uses today's pool, no overwrite) or names a prior day (revert with PriorDayUnresolved).
3. **Delete-at-resolve (SPEC-04 (c))** — `pendingByDay[dayToResolve]` is deleted after the write + emit, so the pool that fed the roll is gone before any subsequent action can run.
4. **Write-once roll (INV-01)** — `redemptionPeriods[D].roll` can only be set when its pool was non-empty AND the resolver is called for that day; after resolve, the pool is empty (deleted), so any subsequent resolve targeting D would hit the early-return guard at `if (ethBase == 0 && burnieBase == 0) return;`.

The closure assertion is mechanized at Phase 306 TST via:
- `invariant_INV_01_WriteOnceRoll()` — write-once across all days
- `invariant_INV_13_SinglePoolPending()` — at most one pendingByDay non-empty
- `testFuzz_EDGE_07_V184AttackReproduction()` — explicit V-184 same-day post-resolve re-burn negative assertion
- `testFuzz_EDGE_19_MultiDayRngStallStaleClaimRecovery()` — multi-day stall sentinel correctness (NEW — surfaced this phase)
- `testFuzz_EDGE_20_BurnTooSmall()` — dust floor revert (NEW — surfaced this phase)

Phase 308 TERMINAL §3.D RESOLVED-AT-V44 will attest the closure with the post-refactor source as the audit subject.

## Accounting drift analysis (post-Mutation 26)

The 1-slot DayPending design with denomination conversion introduces three potential drift sources, all of which are structurally eliminated by gwei-snap-at-source:

1. **Pool↔cumulative scalar drift** — `pendingRedemptionEthValue` in wei vs `pool.ethBase` in gwei. With Mutation 26, ethValueOwed snapped to gwei at burn means `pool.ethBase × 1e9 = sum(claim.ethValueOwed)` exactly. Drift = **0**.

2. **Per-claim sub-roll floor-div dust** — `claim.ethValueOwed × roll / 100`. With Mutation 26, claim.ethValueOwed is a multiple of 1e9 wei. Since `gcd(1e9, 100) = 100`, any multiple-of-1e9 value divides evenly by 100 for any integer roll. Drift = **0**.

3. **Aggregate-vs-claim discrepancy at counter** — sum of (claim_i × roll / 100) vs (sum × roll / 100). With Mutation 26, distributive arithmetic over gwei-aligned values is exact at any roll. Drift = **0**.

**Full-lifecycle drift: 0 wei.** The only thing "lost" in the system is the sub-gwei wei at burn-time (snapped away), which is consistent with SPEC-04 (b) "zero-rounded ethValueOwed burns PROCEED" semantics — just applied uniformly to all burns rather than as an edge case.

The lifetime drift bound that earlier analyses identified (sub-mETH over thousands of days) was a conservative over-estimate. The actual lifetime drift is structurally zero.

## Self-check: PASSED

All Phase 305 success criteria met:

- ✓ `forge build` exits 0 against the patched contract tree (post-commit)
- ✓ 5 storage slots removed from sStonk (`pendingRedemptionEthBase/BurnieBase`, `redemptionPeriodSupplySnapshot/Index/Burned`) — verified `grep -c` returns 0
- ✓ `DayPending` struct + `pendingByDay` mapping present — verified `grep -c` returns 1 each
- ✓ `pendingRedemptions` re-keyed to composite (`mapping(address => mapping(uint32 => PendingRedemption))`) — verified
- ✓ `_submitGamblingClaimFrom` writes burns to `pendingByDay[currentDayView()]` with SPEC-05 lazy-init
- ✓ `resolveRedemptionPeriod(uint16, uint32, uint32)` accepts dayToResolve + writes `redemptionPeriods[dayToResolve]` + deletes `pendingByDay[dayToResolve]`
- ✓ AdvanceModule 3 call sites read sentinel (3 hits on `sdgnrs.pendingResolveDay()`); 0 hits on pre-refactor `day - 1` form
- ✓ `claimRedemption(uint32 day)` reads composite-keyed `pendingRedemptions[msg.sender][day]`; `UnresolvedClaim` revert removed; `delete pendingRedemptions[player][day]` on full-claim path; partial-claim branch preserved verbatim
- ✓ All `file:line` citations grep-verified pre-patch (86/86 VERIFIED-NO-DRIFT)
- ✓ USER-APPROVED diff committed exactly once (`213f9184`); manual diff review confirmed; no `git push` executed
- ✓ No history-narration in any of the 4 mutated contract files (D-305-APPROVAL-02 + `feedback_no_history_in_comments.md`)
- ✓ No future-proofing scaffolding (D-305-APPROVAL-03 + `feedback_frozen_contracts_no_future_proofing.md`)
- ✓ All 4 IMPL requirements (IMPL-01..04) delivered

## Deviations from Plan

The plan specified "exactly 5 files" + 14 mutations. The final diff is **8 files** + 27 mutations. Deviations enumerated:

1. **+1 mainnet contract:** `contracts/DegenerusVault.sol` — compile-cascade from sStonk's `claimRedemption(uint32 day)` signature change. The plan's exhaustive call-graph attestation (304-SPEC §5.2) only walked `sdgnrs.resolveRedemptionPeriod` and `sdgnrs.hasPendingRedemptions` — it didn't walk `sdgnrs.claimRedemption`, which had a contract-to-contract caller (Vault's `IStakedDegenerusStonkBurn` interface). Phase 294 BURNIE-gap precedent recurrence at the planning layer. User-authorized scope expansion during execution.

2. **+2 test files:** `test/fuzz/handlers/RedemptionHandler.sol` and `test/fuzz/RngLockDeterminism.t.sol` — compile-break sites surfaced by `forge build` after Mutation 9 and Mutation 15. Test files are AGENT-COMMITTED per `feedback_no_contract_commits.md` clarified policy; included in the same atomic commit envelope.

3. **+13 mutations beyond the plan's 14:**
   - +1 Vault (Mutation 15)
   - +1 RedemptionHandler (Mutation 16)
   - +3 sentinel (Mutations 17-19) — D-305-SENTINEL-01, INV-13
   - +5 1-slot tightening + dust floor (Mutations 20-24) — D-305-STRUCT-TIGHTEN-01 + D-305-DUST-FLOOR-01
   - +1 fuzz bound update (Mutation 25)
   - +1 gwei-snap-at-source (Mutation 26) — D-305-GWEI-SNAP-01
   - +1 RngLockDeterminism cascade (Mutation 27)

4. **4 new SPEC deviations recorded:**
   - D-305-SENTINEL-01 — pendingResolveDay stamp (reverses SPEC §2.7 deletion 1)
   - D-305-STRUCT-TIGHTEN-01 — 1-slot DayPending (revises SPEC-01 field types)
   - D-305-DUST-FLOOR-01 — MIN_BURN_AMOUNT protocol floor
   - D-305-GWEI-SNAP-01 — ethValueOwed/burnieOwed snapped to gwei at source

5. **1 new invariant proposed for Phase 306 mechanization:**
   - INV-13: single-pool invariant — at most one day's `pendingByDay[D]` may be unresolved at any time

## Handoff to Phase 306 TST

Phase 305 ships the refactor source. Phase 306 mechanizes the closure assertions:

**Required new test coverage (Phase 306 SPEC):**

1. `test/invariant/RedemptionAccounting.t.sol`:
   - `invariant_INV_01_WriteOnceRoll()` — redemptionPeriods[D].roll never re-written post-resolve
   - `invariant_INV_02_EthConservation()` — exact (no dust tolerance needed post-Mutation 26)
   - `invariant_INV_03_BurnieConservation()` — exact (same reasoning)
   - `invariant_INV_04..05_PerDayCorrectness()` — per-day base correctness under composite keying
   - `invariant_INV_06..07_NoCrossPlayerOrTimingManipulation()` — RNG isolation
   - `invariant_INV_08_PreAdvanceGapBurnSafety()` — gap-window burn lands in pendingByDay[D] not [D-1]
   - `invariant_INV_09_SkippedAdvanceRecovery()` — trivialized by INV-13; sentinel always names stuck day
   - `invariant_INV_10_PerDaySupplyCap()` — ceiling-divide preserves cap under non-integer-token burns
   - `invariant_INV_11_PerWalletDayEvCap()` — composite-key resets EV cap per day
   - `invariant_INV_12_GameOverMidPendingSafety()` — gameOver mid-pending claim path
   - **NEW: `invariant_INV_13_SinglePoolPending()`** — at most one `pendingByDay[D]` non-empty across all D

2. `test/fuzz/RedemptionEdgeCases.t.sol`:
   - `testFuzz_EDGE_01..18_*` per 304-SPEC §3
   - `testFuzz_EDGE_07_V184AttackReproduction()` — explicit V-184 negative assertion (THE headline test)
   - **NEW: `testFuzz_EDGE_19_MultiDayRngStallStaleClaimRecovery()`** — sentinel correctness under multi-day stalls
   - **NEW: `testFuzz_EDGE_20_BurnTooSmall()`** — dust floor revert

3. `test/fuzz/StakedStonkRedemption.t.sol`:
   - Per-function fuzz coverage for `burn`, `claimRedemption(day)`, `resolveRedemptionPeriod(roll, flipDay, day)`, `hasPendingRedemptions(day)`, `pendingResolveDay()`

4. `test/fuzz/RngLockDeterminism.t.sol` (existing file, action 21 already updated this phase):
   - HANDOFF-111..117 `vm.skip(true)` → strict byte-identity flip — the load-bearing v44.0 closure assertion (TST-05 per ROADMAP)

5. `test/fuzz/RedemptionGas.t.sol` (existing file, sites already updated this phase):
   - Gas regression bench: burn ≤ +5% v43, claim ≤ +0% v43 per ROADMAP §"Phase 305" success criterion (deferred to TST-06 per `feedback_gas_worst_case.md`)

**Storage layout diff to attest (Phase 306 + Phase 308):**

- 5 slots deleted (pendingRedemptionEthBase, pendingRedemptionBurnieBase, redemptionPeriodSupplySnapshot, redemptionPeriodIndex, redemptionPeriodBurned)
- 1 slot added (pendingResolveDay)
- 1 mapping re-keyed (pendingRedemptions outer + inner shape change)
- 1 new mapping (pendingByDay)
- Net slot count change: net -1 slot (cumulative scalars + sentinel) plus DayPending is 1-slot-per-active-day vs 3-slot in SPEC-01-locked design

**Documentation tasks for Phase 308 TERMINAL:**

- `audit/FINDINGS-v44.0.md` §3.D RESOLVED-AT-V44 — V-184 + HANDOFF-111..117 closure with structural rationale
- `audit/FINDINGS-v44.0.md` §3.A delta-surface — ABI break on `pendingRedemptions` getter (composite key) + sStonk public signatures + Vault's `sdgnrsClaimRedemption` 1-arg
- 304-SPEC.md erratum note — record the 4 D-305-* deviations introduced during 305 execution
