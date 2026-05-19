---
phase: 301-state-shuffle-determinism-fuzz-harness-fuzz
plan: 05
subsystem: testing
tags: [foundry, fuzz, rng-lock, admin-audit, determinism]

# Dependency graph
requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: RNGLOCK-CATALOG.md §1 PayDailyJackpot consumer surface + §9 retryLootboxRng failsafe SLOAD table
  - phase: 300-admin-path-enumeration-audit-adma
    provides: ADMIN-AUDIT.md §3.01..§3.22 per-admin-function recommendation table (R-01..R-22 admin function set)
provides:
  - 5 edge-case fuzz functions per D-301-EDGE-CASES-01 (FUZZ-05 satisfied)
  - _perturbAdminOnly admin-only perturbation helper (FUZZ-02 admin-action-set satisfied)
  - _hashLogs cluster-local digest helper for uniform VRF-output capture across heterogeneous consumer surfaces
affects:
  - 301-06 Wave 2 aggregator (concatenates this contribution into test/fuzz/RngLockDeterminism.t.sol)
  - v44.0 FIX-MILESTONE plan-phase (consumes edge-case assertions as regression-oracle inputs)

# Tech tracking
tech-stack:
  added: []  # zero new dependencies; uses existing Foundry forge-std + DeployProtocol scaffold
  patterns:
    - "Contribution-only paste source (no contract header, no closing brace) — Wave 2 aggregator concatenates"
    - "Anchor comment markers (// ANCHOR: NAME ... // ANCHOR: NAME_END) for mechanical aggregator paste"
    - "6-phase template (setup → lock → perturb → resolve → baseline → assert) extended per edge-case-specific perturbation pattern"
    - "vm.recordLogs + _hashLogs uniform digest capture across heterogeneous consumer surfaces"
    - "try/catch absorbs perturbations where structural preconditions aren't satisfied (no-op rather than fail the iteration)"

key-files:
  created:
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-EDGECASE-CLUSTER-contribution.sol
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-SUMMARY.md
  modified: []  # zero contracts/ + zero test/ mutations per D-43N-AUDIT-ONLY-01

key-decisions:
  - "Inline _hashLogs helper as cluster-local rather than referencing a (yet-unauthored) plan 01 generic packer — heterogeneous consumer surfaces across the 5 edge-case functions argue for uniform digest capture via vm.recordLogs vs per-consumer getter wiring."
  - "Role-holder routing in _perturbAdminOnly: ContractAddresses.CREATOR for vault-owner-gated entries (16 functions), DegenerusAdmin contract address for ADMIN-gated entries (R-01 wireVrf + R-02 updateVrfCoordinatorAndSub + R-03 adminSwapEthForStEth). Matches ADMIN-AUDIT.md §1 role-gate-type table."
  - "Used Solidity try/catch to absorb perturbations + retry invocations where structural preconditions aren't satisfied (e.g., R-01 wireVrf is constructor-one-shot per docstring; retryLootboxRng requires LR_MID_DAY=1 which only holds on lootbox-RNG path). Failing iteration would be incorrect — the precondition simply isn't met for that fuzz state."
  - "MultiBlock warp coherency: vm.warp(startTime + delta * 12) to keep block.timestamp roughly coherent with block.number progression at 12 s/block; bounded delta to [1, 100] (max 20 min) to stay well within the 12 h daily-RNG timeout."
  - "RetryLootboxRngDuringLock baseline replay matches the (warp + retry + deliver) sequence WITHOUT the pre-retry perturbation, isolating the perturbation as the only delta — exact invariant from D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A 'no pre-lock-state manipulation'."

patterns-established:
  - "ADMA admin-action helper (_perturbAdminOnly): structured 22-case dispatch via seed%22, per-case NatSpec cross-reference to ADMIN-AUDIT.md §3.NN, try/catch graceful no-op for unsatisfied preconditions."
  - "_hashLogs(Vm.Log[]) digest: keccak256(packed(emitter, keccak256(abi.encode(topics)), keccak256(data))) — order-sensitive, suitable for byte-identity assertions on event-emitting VRF-derived outputs."
  - "Edge-case 6-phase template variations: AdminDuringLock (admin perturbation), NearEndOfWindow (warp to 12h-1s then perturb), MultiTxBatch (3 perturbations same block), MultiBlock (perturb + vm.roll + perturb), RetryLootboxRngDuringLock (perturb + 6h+1 warp + retryLootboxRng + deliver fresh VRF)."

requirements-completed: [FUZZ-02, FUZZ-05]

# Metrics
duration: 9min
completed: 2026-05-18
---

# Phase 301 Plan 05: EDGECASE-CLUSTER Contribution Summary

**5 edge-case fuzz functions (AdminDuringLock + NearEndOfWindow + MultiTxBatch + MultiBlock + RetryLootboxRngDuringLock) + 22-entry admin-only perturbation helper covering ADMA R-01..R-22 + cluster-local _hashLogs digest helper — zero contracts/ and zero test/ mutations per D-43N-AUDIT-ONLY-01.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-05-18T20:18:44Z
- **Completed:** 2026-05-18T20:28:07Z
- **Tasks:** 2 (Task 1 authored 3 edge-case functions + helper; Task 2 appended 2 edge-case functions + SUMMARY)
- **Files created:** 2 (contribution .sol + SUMMARY .md)
- **Files modified:** 0 (zero contracts/, zero test/ — paste-source only)

## Accomplishments

- All 5 edge-case fuzz functions authored per D-301-EDGE-CASES-01 enumeration (FUZZ-05 satisfied)
- `_perturbAdminOnly(uint256 seed)` admin-action-only perturbation helper covering all 22 ADMA R-NN entries (FUZZ-02 admin action set satisfied at the edge-case-helper level)
- `_hashLogs(Vm.Log[])` cluster-local digest helper for uniform VRF-output capture across heterogeneous consumer surfaces
- 18 anchor markers laid down for Wave 2 mechanical concatenation (`CLUSTER_EDGECASE_OPEN`/`_END`, 2 helper anchor pairs, 5 function anchor pairs, `CLUSTER_EDGECASE_END`/`_END`)

## Anchor Inventory

| Anchor | Purpose |
| --- | --- |
| `CLUSTER_EDGECASE_OPEN` / `_OPEN_END` | Cluster open + scope NatSpec |
| `HELPER_hashLogs` / `_END` | Cluster-local digest helper |
| `HELPER_perturbAdminOnly` / `_END` | 22-case admin perturbation helper |
| `FUNC_EdgeCase_AdminDuringLock` / `_END` | Edge case 1 — admin-only perturbation; PayDailyJackpot consumer surface |
| `FUNC_EdgeCase_NearEndOfWindow` / `_END` | Edge case 2 — perturbation at `rngRequestTime + 12 h - 1 s` (last lock-window second) |
| `FUNC_EdgeCase_MultiTxBatch` / `_END` | Edge case 3 — three perturbations stacked in one block |
| `FUNC_EdgeCase_MultiBlock` / `_END` | Edge case 4 — perturbation + `vm.roll` + perturbation across distinct blocks |
| `FUNC_EdgeCase_RetryLootboxRngDuringLock` / `_END` | Edge case 5 — perturb + 6 h + 1 warp + `retryLootboxRng()` + fresh VRF; tests D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A invariant |
| `CLUSTER_EDGECASE_END` / `_END_END` | Cluster close |

## Files Created/Modified

- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-EDGECASE-CLUSTER-contribution.sol` — 776 lines; 5 edge-case fuzz functions + 2 helpers; paste-source for Wave 2 aggregator (plan 06); intentionally non-compilable in isolation per plan 01 scaffold convention.
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-SUMMARY.md` — this file.

## Decisions Made

- **Cluster-local `_hashLogs` helper.** Plan 01's scaffold authors `_assertVrfOutputByteIdentity(bytes32, bytes32, string)` per the locked 6-phase template, but the precise upstream packing pattern (`keccak256(abi.encode(recipient, amount, heroByte))` for PayDailyJackpot) is per-consumer-specific. The 5 edge-case functions hit heterogeneous surfaces (PayDailyJackpot for AdminDuringLock; whichever-consumer-the-perturbation-reaches for NearEndOfWindow / MultiTxBatch / MultiBlock; lootbox-RNG callback for RetryLootboxRngDuringLock). Authoring a uniform `_hashLogs(Vm.Log[])` event-stream digest gives consistent capture across all 5 functions without re-deriving per-consumer getter logic. The helper is order-sensitive (events emit in consumer-execution order, which IS the byte-identity invariant under test).
- **Role-holder routing in `_perturbAdminOnly`.** ADMIN-AUDIT.md §1 enumerates three role-gate types: `onlyVaultOwner` modifier (Vault, 23 entries), hand-rolled `vault.isVaultOwner(msg.sender)` checks (5 entries on Game/Stonk/GNRUS), and hand-rolled `msg.sender == ContractAddresses.ADMIN` (3 entries on Game + AdvanceModule). The helper uses `vm.prank(ContractAddresses.CREATOR)` for vault-owner-gated entries (CREATOR holds 100% of DGVE at deploy per `DegenerusVault.sol:235`) and `vm.prank(address(admin))` for ADMIN-gated entries (the DegenerusAdmin contract IS the ADMIN address per ContractAddresses).
- **`try/catch` graceful no-op for unsatisfied preconditions.** Many admin entries require state preconditions that are not satisfied in every fuzz iteration (e.g., R-01 `wireVrf` is structurally one-shot per docstring; R-10 `gameOpenLootBox` requires the vault to own a lootbox at the supplied index; R-11 deity-pass purchase requires active boon + sufficient ETH). Wrapping each call in `try ... catch { return; }` matches the plan 01 general `_perturb` convention: unsatisfied iterations no-op silently rather than failing the iteration.
- **Pre-fix vs post-fix v44.0 compatibility.** Several admin entries already have an existing runtime `RngLocked` gate (e.g., `_setAutoRebuy:1513`); others are subjects of v44.0 FIX-MILESTONE handoffs (`D-43N-V44-HANDOFF-NN`) that will add gates. The `try/catch` pattern is forward-compatible: pre-fix the call succeeds and may produce a divergent VRF output (asserting catches the violation); post-fix the call reverts at the rngLocked gate and the perturbation no-ops (asserting confirms the gate works structurally). The harness is therefore valid both before and after v44.0 fixes land — exactly the regression-oracle shape v44.0 plan-phase consumes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected `createSubscription` return type from `uint64` to `uint256`**
- **Found during:** Task 1 (R-02 `updateVrfCoordinatorAndSub` admin case in `_perturbAdminOnly`)
- **Issue:** Initial draft used `uint64 s` as the return-receiver type for `newVrf.createSubscription()`. Source verification (`MockVRFCoordinator.sol:29`) shows the function returns `uint256 subId`; the precedent in `test/fuzz/LootboxRngLifecycle.t.sol:70` (`_doCoordinatorSwap`) uses `uint256 newSubId = newVRF.createSubscription();`.
- **Fix:** Changed receiver type to `uint256 s`, dropped the redundant `uint256(s)` cast, and dropped the `uint64(newSub)` casts on `addConsumer` / `fundSubscription` (which take `uint256 subId`).
- **Files modified:** `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-EDGECASE-CLUSTER-contribution.sol`
- **Verification:** Visual diff matches the precedent `_doCoordinatorSwap` pattern; types unify across the 4 calls in the R-02 case.
- **Committed in:** (no commit — `.planning/` artifact, no per-task commit per `D-43N-TEST-COMMITS-AUTO-01`; whole-plan AGENT-COMMITTED at Wave 1 close)

---

**Total deviations:** 1 auto-fixed (Rule 1 type-correctness bug)
**Impact on plan:** Type-correctness fix; zero scope creep; no plan reframing required.

## Issues Encountered

- **Pre-existing untracked file `test/fuzz/_SandboxRngLockDeterminism.t.sol`** in the worktree at plan start. Verification scripts in the plan use `[ -z "$(git status --porcelain test/)" ]` to confirm zero test-tree mutations; this pre-existing untracked file fails the check. SCOPE BOUNDARY (per `<deviation_rules>` SCOPE BOUNDARY) instructs the executor to NOT touch out-of-scope dirty state. The file appears to be sandbox debris from a parallel agent's compile-check sequence (e.g., plan 01's "Author the file. THEN temporarily concatenate it into a sandbox copy …" pattern, with the post-check `rm` not yet executed by the parallel agent). The file is left untouched; verification scripts re-run with `grep -v '_SandboxRngLockDeterminism.t.sol'` confirm zero mutations from THIS plan. v44.0 / cluster-aggregation cleanup will handle the sandbox file.

## Deferred Items

- **Per-consumer extraction wiring** (e.g., `game.lastJackpotRecipient()` getter calls) — the 5 edge-case functions use the uniform `_hashLogs` digest instead of per-consumer extraction. If Wave 2 aggregator plan 06 needs to compare an edge-case function's digest against a per-consumer cluster function's digest (which uses the explicit pack form per plan 01 reference template), the two digest schemes are incompatible — but the comparison is intra-function (perturbation vs baseline) not cross-function, so no incompatibility manifests. Documented here for visibility.

## User Setup Required

None — `.planning/` artifact only; no contract or test-tree mutations require approval per `feedback_no_contract_commits.md` and `D-43N-TEST-COMMITS-AUTO-01`.

## Next Phase Readiness

- **Wave 2 (plan 06 aggregator):** Edge-case cluster contribution ready for mechanical concatenation. Anchors (`CLUSTER_EDGECASE_OPEN` through `CLUSTER_EDGECASE_END`) provide paste boundaries; no semantic re-derivation needed.
- **Sibling Wave-1 plans (02 / 03 / 04):** No coupling to this plan beyond shared helper dependencies (`_perturb`, `_advanceToVrfRequestBoundary`, `_deliverMockVrf`, `_snapshotPreLock`, `_revertToPreLock`, `_assertVrfOutputByteIdentity`, `_completeDay`) which plan 01 authors.
- **v44.0 FIX-MILESTONE:** All 5 edge-case assertions stay valid both pre-fix (perturbation produces divergent output → assertion fails → vm.skip block added by aggregator per `D-43N-FUZZ-VMSKIP-01` Option C) and post-fix (perturbation reverts at the new gate → no-op → assertion passes). Regression-oracle shape preserved across the fix transition.

## Self-Check: PASSED

Verified at SUMMARY-write time:
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-EDGECASE-CLUSTER-contribution.sol` exists (776 lines, 18 anchors)
- 5 `testFuzz_EdgeCase_*` function declarations present (grep `^function testFuzz_EdgeCase_` → 5 hits)
- `_perturbAdminOnly` helper present with 22 ADMA-cross-referenced cases
- `_hashLogs` helper present
- `CLUSTER_EDGECASE_END` marker present
- `git status --porcelain contracts/` returns empty
- `git status --porcelain test/` returns only the pre-existing untracked `_SandboxRngLockDeterminism.t.sol` (out-of-scope per SCOPE BOUNDARY)
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-05-SUMMARY.md` exists

---
*Phase: 301-state-shuffle-determinism-fuzz-harness-fuzz*
*Plan: 05 EDGECASE-CLUSTER*
*Completed: 2026-05-18*
