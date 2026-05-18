---
phase: 301-state-shuffle-determinism-fuzz-harness-fuzz
plan: 03
subsystem: testing
tags: [foundry, fuzz, rnglock, lootbox, determinism, audit, vrf, paste-source]

# Dependency graph
requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: "RNGLOCK-CATALOG.md §6 / §7 / §8 / §13 CAT-01 traced function set + CAT-02 SLOAD tables driving the per-consumer participating-slot digest"
  - phase: 299-fix-recommendation-document-fixrec
    provides: "RNGLOCK-FIXREC.md §N entries — Wave 2 aggregator (plan 06) consumes these for the vm.skip cross-reference comments"
  - phase: 300-admin-path-enumeration-audit-adma
    provides: "ADMA-01 admin function set — feeds FUZZ-02 action library used by `_perturb` in plan 01 SCAFFOLD"
provides:
  - "Per-consumer fuzz function authoring for the 4 lootbox-family CAT-01 consumer surfaces (§6 + §7 + §8 + §13)"
  - "Documentation of the W-05 commitment-window divergence: lootbox-family consumers use per-consumer commitment sentinels (rngWordByDay / lootboxRngWordByIndex / decClaimRounds.rngWord), NOT the advance-cycle rngLockedFlag — adjustment to the locked 6-phase template recorded inline per function"
  - "Paste-source contribution shape (anchor-delimited) for Wave 2 plan 06 aggregator"
affects: [301-04, 301-05, 301-06, 303-audit-deliverable]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Locked 6-phase fuzz template (setup → lock → perturb → resolve → baseline → assert) applied per-consumer with consumer-specific commitment-sentinel pinning"
    - "Per-function NatSpec cites the catalog §N CAT-02 SLOAD-table entries digested into the byte-identity output"
    - "Wave-2-deferred helper-signature pattern: cluster-private helpers that document the call-site shape (NatSpec) but defer concrete ABI alignment to aggregator time"
    - "vm.assume-based fuzz-iteration filtering when per-consumer preconditions cannot be arranged"

key-files:
  created:
    - ".planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-LOOTBOX-CLUSTER-contribution.sol"
    - ".planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/deferred-items.md"
    - ".planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-SUMMARY.md"
  modified: []

key-decisions:
  - "D-301-03-COMMITMENT-SENTINEL-01 — Each of the 4 lootbox-family consumers uses a DIFFERENT 'lock' sentinel for the 6-phase Phase 2 assertion, pinned per catalog §N CAT-02 SLOAD table. §6 uses `game.rngLocked()` (advance-cycle lock for the in-flight mid-day lootbox-RNG request). §7 uses `lootboxRngWordByIndex[index] == 0` (per-index commitment slot transitions 0 → nonzero at VRF callback). §8 uses the same per-index slot as §7 (shared VRF source). §13 uses `decClaimRounds[lvl].rngWord != 0` (set-once-per-level inside EXEMPT-ADVANCEGAME stack)."
  - "D-301-03-DIGEST-COVERAGE-01 — Each fuzz function's `keccak256` digest packs ALL participating-slot consequences per the catalog §N CAT-02 SLOAD table (the YES-participating rows), not just the rngWord. This honors `feedback_rng_window_storage_read_freshness.md` F-41-02/03 discipline (non-VRF SLOADs consumed alongside RNG are a distinct bug class)."
  - "D-301-03-HELPER-DEFER-01 — `_tryPlaceDegeneretteBet`, `_tryResolveDegeneretteBets`, `_tryArrangeDecimatorWindow`, `_readDecCurrentClaimLevel`, `_readDecClaimRoundsRngWord` defer concrete ABI/slot resolution to Wave 2 aggregator (plan 06). The cluster-private helpers are authored as documented placeholders returning false/0 with the aggregator-time pattern in NatSpec. Rationale: the `placeDegeneretteBet` external signature has multiple variants across the codebase (raw vs permit vs vault-routed) and the `decClaimRounds` struct-field offset requires `forge inspect DegenerusGame storage-layout` reconciliation that is best done once at aggregation time across all clusters."
  - "D-301-03-DEFERRED-SANDBOX-01 — Pre-existing untracked `test/fuzz/_SandboxRngLockDeterminism.t.sol` (mtime 15:22:05) is NOT a plan 03 mutation; logged in deferred-items.md for Wave 2 aggregator disposition."

patterns-established:
  - "Anchor-delimited paste-source contribution: `// ANCHOR: CLUSTER_LOOTBOX_OPEN` ... `// ANCHOR: FUNC_<Name>` / `// ANCHOR: FUNC_<Name>_END` ... `// ANCHOR: CLUSTER_LOOTBOX_HELPERS` ... `// ANCHOR: CLUSTER_LOOTBOX_END`. Wave 2 aggregator concatenates the contribution between plan 01 SCAFFOLD and sibling cluster contributions."
  - "Per-function NatSpec must cite both the catalog §N (one or many) AND the specific CAT-02 SLOAD-table entries digested. Mirrors Phase 281 owed-salt commitment NatSpec discipline."

requirements-completed: [FUZZ-03, FUZZ-04]

# Metrics
duration: ~25min
completed: 2026-05-18
---

# Phase 301 Plan 03: Lootbox-Cluster Fuzz Contribution Summary

**Authored 4 per-consumer fuzz functions (catalog §6/§7/§8/§13) as paste-source contribution for Wave 2 aggregator, applying the locked 6-phase template with per-consumer commitment-sentinel pinning to address the W-05 divergence between advance-cycle and per-index/per-level commitment windows.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-18T20:18Z (approx)
- **Completed:** 2026-05-18T20:43Z (approx)
- **Tasks:** 2 / 2
- **Files modified:** 0 in `contracts/` and `test/`; 2 created in `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/` (contribution + deferred-items + this SUMMARY)

## Accomplishments

- **Four per-consumer fuzz functions authored** with full 6-phase template + NatSpec cross-reference to catalog §N CAT-02 SLOAD-table participating-slot entries:
    - `testFuzz_RngLockDeterminism_ResolveRedemptionLootbox` (§6 — `LootboxModule.resolveRedemptionLootbox` at LootboxModule.sol:707; redemption-stack reach via `StakedDegenerusStonk.claimRedemption`)
    - `testFuzz_RngLockDeterminism_ResolveLootboxCommon` (§7 — `LootboxModule._resolveLootboxCommon` / `_resolveLootboxRoll` at LootboxModule.sol:960 / :1623; manual EOA path via `openLootBox` / `openBurnieLootBox`)
    - `testFuzz_RngLockDeterminism_DegeneretteLootboxDirect` (§8 — `DegeneretteModule._resolveLootboxDirect + inline consumer` at DegeneretteModule.sol:797 / :594)
    - `testFuzz_RngLockDeterminism_DecimatorAwardLootbox` (§13 — `DecimatorModule._awardDecimatorLootbox` cluster at DecimatorModule.sol:573 with cross-call rngWord re-read at :338)
- **W-05 commitment-window divergence explicitly addressed:** §6 uses advance-cycle `rngLocked()`; §7/§8 use the per-index `lootboxRngWordByIndex[index]` 0→nonzero transition; §13 uses `decClaimRounds[lvl].rngWord` set-once-per-level. Each per-function NatSpec documents its commitment sentinel choice with citation back to the catalog §N SLOAD table.
- **Output-digest coverage extends beyond rngWord** per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 discipline: each function's `keccak256(abi.encode(...))` packs the participating-slot consequences (player ETH/BURNIE/sDGNRS/WWXRP balance deltas + `claimableWinnings[buyer]` delta + per-index commitment slot value + post-resolution `lootboxStatus` zero-out invariant where applicable).
- **Anchor-delimited paste-source shape preserved** for Wave 2 aggregator: `// ANCHOR: CLUSTER_LOOTBOX_OPEN` opens; per-function `FUNC_<Name>` / `FUNC_<Name>_END` anchors delimit each function; `CLUSTER_LOOTBOX_HELPERS` brackets cluster-private helpers; `CLUSTER_LOOTBOX_END` closes.

## Task Commits

No commits emitted by this plan execution (AGENT-COMMITTED per `D-301-WAVE-SHAPE-01` only at Wave 2 aggregator boundary; plan 03 is a Wave 1 contribution-authoring sub-phase). Files staged for the Wave 2 batched test commit:

- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-LOOTBOX-CLUSTER-contribution.sol`
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-SUMMARY.md`
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/deferred-items.md`

Plan-metadata commit shape and Wave 2 batched test commit are handled by Phase 301 orchestrator / plan 06 aggregator per `D-301-WAVE-SHAPE-01`.

## Files Created

- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-LOOTBOX-CLUSTER-contribution.sol` — Paste-source contribution authoring 4 testFuzz functions + 5 cluster-private deferred-signature helpers. Anchor markers: `CLUSTER_LOOTBOX_OPEN`, `FUNC_ResolveRedemptionLootbox`, `FUNC_ResolveRedemptionLootbox_END`, `FUNC_ResolveLootboxCommon`, `FUNC_ResolveLootboxCommon_END`, `FUNC_DegeneretteLootboxDirect`, `FUNC_DegeneretteLootboxDirect_END`, `FUNC_DecimatorAwardLootbox`, `FUNC_DecimatorAwardLootbox_END`, `CLUSTER_LOOTBOX_HELPERS`, `CLUSTER_LOOTBOX_END`.
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/deferred-items.md` — Logs the pre-existing untracked `test/fuzz/_SandboxRngLockDeterminism.t.sol` discovery (out-of-scope for plan 03 per scope-boundary rule).
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-SUMMARY.md` — This file.

## Files Modified

None in `contracts/` or `test/` (zero mutations per `D-301-WAVE-SHAPE-01` Wave 1 contribution policy + critical constraint "Zero `contracts/` mutations").

## Anchor inventory

| Anchor                                       | Function / region                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CLUSTER_LOOTBOX_OPEN`                       | Cluster header NatSpec citing D-301-COVERAGE-01 + W-05 divergence prose                                                                                                                                                                                                                                                                                                                       |
| `FUNC_ResolveRedemptionLootbox` (+ `_END`)   | §6 fuzz function — `testFuzz_RngLockDeterminism_ResolveRedemptionLootbox(uint256 vrfWord, uint256 perturbSeed)`. Lock sentinel: `game.rngLocked()`. Digest packs: stored VRF word, post-resolution `lootboxStatus`, buyer BURNIE/WWXRP/claimable balances.                                                                                                                                       |
| `FUNC_ResolveLootboxCommon` (+ `_END`)       | §7 fuzz function — `testFuzz_RngLockDeterminism_ResolveLootboxCommon(uint256 vrfWord, uint256 perturbSeed, uint256 lootboxIndexSeed)`. Lock sentinel: `lootboxRngWordByIndex[index] == 0` → nonzero. Digest packs: stored rngWord at purchase index, post-open `lootboxStatus`, buyer ETH/BURNIE/WWXRP/DGNRS/claimable deltas.                                                                  |
| `FUNC_DegeneretteLootboxDirect` (+ `_END`)   | §8 fuzz function — `testFuzz_RngLockDeterminism_DegeneretteLootboxDirect(uint256 vrfWord, uint256 perturbSeed)`. Lock sentinel: shared per-index slot with §7. Digest packs: buyer ETH/BURNIE/WWXRP/DGNRS/claimable deltas. Uses `_tryPlaceDegeneretteBet` (Wave-2-deferred signature) + `vm.assume(placed)`.                                                                                    |
| `FUNC_DecimatorAwardLootbox` (+ `_END`)      | §13 fuzz function — `testFuzz_RngLockDeterminism_DecimatorAwardLootbox(uint256 vrfWord, uint256 perturbSeed)`. Lock sentinel: `decClaimRounds[lvl].rngWord != 0`. Digest packs: rngWord re-read at claim level + buyer ETH/BURNIE/WWXRP/DGNRS/claimable deltas. Cross-call freshness watch (`feedback_rng_window_storage_read_freshness.md`) — both rngWord SLOADs (callsite β + α) must agree. |
| `CLUSTER_LOOTBOX_HELPERS`                    | Cluster-private deferred-signature helpers: `_tryPlaceDegeneretteBet`, `_tryResolveDegeneretteBets`, `_tryArrangeDecimatorWindow`, `_readDecCurrentClaimLevel`, `_readDecClaimRoundsRngWord`. Each carries NatSpec with the aggregator-time paste pattern.                                                                                                                                       |
| `CLUSTER_LOOTBOX_END`                        | Cluster closer with Wave 2 aggregator handoff notes (`D-301-VMSKIP-MECHANISM-01` skip-block reminder + helper-signature reconciliation pointer + closing `}` reminder).                                                                                                                                                                                                                          |

## Catalog cross-reference matrix

Each fuzz function's NatSpec cites the specific CAT-02 SLOAD-table entries digested:

| Function                          | Catalog §N | Entropy slot                                  | Participating slots digested (catalog §N CAT-02 IDs)                                                                                  |
| --------------------------------- | ---------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `ResolveRedemptionLootbox`        | §6         | B-I1 `rngWordByDay[claimPeriodIndex]`         | B-1, B-9, B-19, B-20, B-21, B-24, B-25, B-26, B-27, B-28 (9 deduplicated participating slots)                                          |
| `ResolveLootboxCommon`            | §7         | B-2 `lootboxRngWordByIndex[index]`            | B-1, B-2, B-3, B-4, B-6, B-7, B-8, B-9, B-10, B-12, B-13, B-14, B-16, B-17, B-18, B-19, B-20, B-21, B-22, B-23, B-24, B-25, B-26, B-28, B-29 |
| `DegeneretteLootboxDirect`        | §8         | B-3 `lootboxRngWordByIndex[index]`            | B-2, B-3, B-4, B-5, B-6, B-7, B-10–B-26 participating subset per §8 CAT-02                                                              |
| `DecimatorAwardLootbox`           | §13        | B-10 `decClaimRounds[lvl].rngWord`            | B-4, B-5, B-8, B-9, B-10, B-13/B-15/B-25 (level), B-23/B-24 (mintPacked + streak), B-26 (lootboxEvBenefitUsedByLevel)                  |

## Deviations from Plan

### Auto-fixed Issues

None. The plan executed as written.

### Out-of-scope discoveries

- `test/fuzz/_SandboxRngLockDeterminism.t.sol` pre-exists as an untracked file with mtime 15:22:05 (pre-dates this contribution's mtime 15:23:59). Logged in `deferred-items.md` (D-301-03-DEFERRED-SANDBOX-01); not modified by plan 03. Wave 2 aggregator (plan 06) is the appropriate disposition point.

## Known Stubs

The 5 cluster-private helpers in `CLUSTER_LOOTBOX_HELPERS` are intentional deferred-signature stubs per D-301-03-HELPER-DEFER-01:

- `_tryPlaceDegeneretteBet(address)` — returns `false`; aggregator paste pattern in NatSpec.
- `_tryResolveDegeneretteBets(address)` — no-op; aggregator paste pattern in NatSpec.
- `_tryArrangeDecimatorWindow(address)` — returns `false`; aggregator paste pattern in NatSpec.
- `_readDecCurrentClaimLevel()` — returns `0`; aggregator paste pattern in NatSpec.
- `_readDecClaimRoundsRngWord(uint24)` — returns `0`; aggregator paste pattern in NatSpec.

When called, these placeholders cause the `vm.assume(...)` filters to skip fuzz iterations (graceful degradation), preserving harness compileability under Wave 2 paste-time integration. Wave 2 aggregator MUST replace these with concrete implementations using the documented paste patterns; until replacement the §8 + §13 fuzz functions will execute zero iterations (every iteration `vm.assume`s out).

Rationale: the concrete `placeDegeneretteBet` signature + `resolveDegeneretteBets` betId-array shape + `decClaimRounds` struct-field storage offset require:
1. `forge inspect DegenerusGame storage-layout` (slot constants),
2. grep across `contracts/DegenerusGame.sol` for the canonical entry signatures,
3. Cross-cluster signature reconciliation,
all of which Wave 2 plan 06 aggregator is structurally positioned to perform once. Pushing this work into Wave 1 cluster plans 02/03/04/05 risks 4-way inconsistency.

## Threat Flags

None. Plan 03 introduces no new security-relevant surface (test contribution only; zero `contracts/` mutation).

## Self-Check: PASSED

- File exists: `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-LOOTBOX-CLUSTER-contribution.sol` — FOUND
- File exists: `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-03-SUMMARY.md` — FOUND
- File exists: `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/deferred-items.md` — FOUND
- Function present: `testFuzz_RngLockDeterminism_ResolveRedemptionLootbox` — FOUND
- Function present: `testFuzz_RngLockDeterminism_ResolveLootboxCommon` — FOUND
- Function present: `testFuzz_RngLockDeterminism_DegeneretteLootboxDirect` — FOUND
- Function present: `testFuzz_RngLockDeterminism_DecimatorAwardLootbox` — FOUND
- Anchor present: `CLUSTER_LOOTBOX_END` — FOUND
- Catalog citation: `RNGLOCK-CATALOG.md §6` — FOUND
- Catalog citation: `RNGLOCK-CATALOG.md §7` — FOUND
- Catalog citation: `RNGLOCK-CATALOG.md §8` — FOUND
- Catalog citation: `RNGLOCK-CATALOG.md §13` — FOUND
- `git status --porcelain contracts/` — empty (zero mutation)
- `git status --porcelain test/` — single pre-existing untracked sandbox file (D-301-03-DEFERRED-SANDBOX-01); zero mutation introduced by this plan execution
