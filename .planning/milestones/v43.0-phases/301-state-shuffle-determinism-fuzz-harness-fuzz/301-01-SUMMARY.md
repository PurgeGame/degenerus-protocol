---
phase: 301-state-shuffle-determinism-fuzz-harness-fuzz
plan: 01
subsystem: testing
tags: [foundry, fuzz, rng-lock, vrf, scaffold, contribution]

# Dependency graph
requires:
  - phase: 298-vrf-read-graph-catalog-catalog
    provides: CAT-01 13-consumer list (D-298-CONSUMER-LIST-01) + RNGLOCK-CATALOG.md §1 (PayDailyJackpot) + §3 (RunTerminalJackpot) consumer surfaces with SLOAD tables
  - phase: 299-fix-recommendation-document-fixrec
    provides: RNGLOCK-FIXREC.md §N entries for v44.0 vm.skip cross-references (consumed at Wave-2 aggregation, not at this scaffold plan)
  - phase: 300-admin-path-enumeration-audit-adma
    provides: ADMA-01 admin function enumeration (Action 7 admin-path class in `_perturb` library)
provides:
  - Canonical contract header (SPDX + pragma + imports + `contract RngLockDeterminism is DeployProtocol` open) for Wave 2 aggregator paste
  - Shared helpers used by all 18 sibling fuzz functions (`_advanceToVrfRequestBoundary`, `_deliverMockVrf`, `_snapshotPreLock`, `_revertToPreLock`, `_assertVrfOutputByteIdentity`, `_completeDay`, `_readRngWordCurrent`, `_readVrfRequestId`)
  - Perturbation action library `_perturb(seed)` with N_PERTURB_ACTIONS = 9 covering FUZZ-02 + ADMA-01 surface
  - 2 of 13 reference fuzz functions (`testFuzz_RngLockDeterminism_PayDailyJackpot` + `testFuzz_RngLockDeterminism_RunTerminalJackpot`) as LOCKED REFERENCE TEMPLATE for the 6-phase per-function structure
  - Per-consumer event+storage digest helpers (`_digestPayDailyJackpotOutputs`, `_digestRunTerminalJackpotOutputs`) demonstrating VRF-output capture pattern
affects: [301-02 cluster-A contribution, 301-03 cluster-B contribution, 301-04 cluster-C contribution, 301-05 edge-case contribution, 301-06 Wave-2 aggregator]

# Tech tracking
tech-stack:
  added: [vm.recordLogs + vm.getRecordedLogs event-digest pattern for VRF-output capture]
  patterns:
    - "6-phase per-function template: setup → lock → perturb → resolve → baseline → assert (D-301-HARNESS-ARCH-01)"
    - "Anchor-bracketed contribution file (// ANCHOR: XYZ) for mechanical aggregator paste regions"
    - "keccak256-collapsed event+storage digest as single bytes32 byte-identity probe"
    - "try/catch-wrapped perturbation action classes so unsatisfiable iterations silently no-op"

key-files:
  created:
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-01-SCAFFOLD-contribution.sol
    - .planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-01-SUMMARY.md
  modified: []

key-decisions:
  - "Contribution file omits closing `}` (non-compilable in isolation; Wave 2 aggregator appends close + cluster functions)"
  - "VRF-output capture via vm.recordLogs() + keccak256 digest of all address(game)-emitted events plus post-resolve storage state (rngWordCurrent, vrfRequestId)"
  - "Perturbation action library count N_PERTURB_ACTIONS = 9 (one extra above the 7-base + admin + retry envelope per the plan's ≥9 minimum)"
  - "Reference function VRF-derived output digest helpers (`_digestPayDailyJackpotOutputs`, `_digestRunTerminalJackpotOutputs`) collapse all event logs + storage SLOADs into a single bytes32 so the `_assertVrfOutputByteIdentity` shim is the canonical assertion site for vm.skip wrapping at Wave 2"
  - "Cluster plans 02/03/04 author per-consumer digest helpers by replicating the reference helpers' shape (filter to address(game), pack topics+data, append post-resolve storage SLOADs)"
  - "vm.skip blocks NOT attached here per D-301-VMSKIP-MECHANISM-01 — Wave 2 aggregator runs un-skipped first, attaches skip blocks with FIXREC §N references after"

patterns-established:
  - "Anchor-based contribution file: each major paste region prefixed by `// ANCHOR: <NAME>` so Wave 2 mechanical concatenation works without semantic re-derivation"
  - "Per-consumer digest helper: keccak256(abi.encodePacked(<all logs from address(game)>, <post-resolve storage SLOAD bundle>)) collapses VRF-derived outputs into single bytes32"
  - "Sandbox-build verification: temporarily append closing `}` and run `forge build` against a `test/fuzz/_Sandbox<Name>.t.sol` file, then DELETE the sandbox; the production contribution file lives only in .planning/"

requirements-completed: [FUZZ-01, FUZZ-03, FUZZ-04]

# Metrics
duration: ~18min
completed: 2026-05-18
---

# Phase 301 Plan 01: State-Shuffle Determinism Fuzz Harness Scaffold Contribution Summary

**Canonical scaffold contribution for `test/fuzz/RngLockDeterminism.t.sol` — locks the 6-phase per-function template (setup/lock/perturb/resolve/baseline/assert) and authors shared helpers + 2 reference fuzz functions (PayDailyJackpot + RunTerminalJackpot) that cluster plans 02/03/04 replicate verbatim.**

## Performance

- **Duration:** ~18 min
- **Tasks:** 2
- **Files modified:** 0 in `contracts/`; 0 in `test/`; 2 in `.planning/`

## Accomplishments

- Authored `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-01-SCAFFOLD-contribution.sol` (~430 LOC) with 9 anchor regions for mechanical Wave-2 aggregation
- Locked the 6-phase per-function template (D-301-HARNESS-ARCH-01) into 2 reference fuzz functions that cluster plans 02/03/04 replicate verbatim
- Shipped 7 shared helpers (`_completeDay`, `_advanceToVrfRequestBoundary`, `_deliverMockVrf`, `_snapshotPreLock`, `_revertToPreLock`, `_assertVrfOutputByteIdentity`, plus 2 storage-slot readers) used by all 18 sibling fuzz functions
- Shipped perturbation action library `_perturb(seed)` covering 9 action classes (FUZZ-02 + ADMA-01 surface)
- Sandbox `forge build` confirmed zero compile errors (0 errors; only pre-existing `contracts/`-side unsafe-typecast lint warnings)

## Task Commits

Per phase policy (`D-301-WAVE-SHAPE-01` + `D-43N-TEST-COMMITS-AUTO-01` + `feedback_no_contract_commits.md` clarified policy): scaffold contribution lives entirely in `.planning/` at this plan (zero test/ tree commits; Wave 2 aggregator owns the test/ commit). Task-1 and Task-2 changes will be wrapped into the AGENT-COMMITTED plan-completion commit by the executor's final-commit step.

1. **Task 1:** Author scaffold contribution file with canonical contract header + shared helpers + 2 reference fuzz functions — verification PASS (all 8 plan-required anchors present + 2 reference function names match D-301-COVERAGE-01 spec verbatim; sandbox `forge build` returns 0 errors; git tree shows zero `contracts/` + zero `test/` mutations)
2. **Task 2:** Write SUMMARY (this file)

## Files Created/Modified

- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-01-SCAFFOLD-contribution.sol` — Wave-2 paste source: header + 7 shared helpers + 9-class perturbation action library + 2 reference fuzz functions + per-consumer digest helpers
- `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-01-SUMMARY.md` — this file

## Anchor Inventory (Wave 2 aggregator paste regions)

| # | Anchor | Region content |
|---|--------|----------------|
| 1 | `// ANCHOR: HEADER` | SPDX + pragma + 5 imports (DeployProtocol, VRFHandler, MockVRFCoordinator, MintPaymentKind, Vm) |
| 2 | `// ANCHOR: CONTRACT_OPEN` | `contract RngLockDeterminism is DeployProtocol {` + NatSpec describing the 6-phase template + D-301-HARNESS-ARCH-01 / D-301-COVERAGE-01 / D-301-VMSKIP-MECHANISM-01 cross-references |
| 3 | `// ANCHOR: STATE` | `vrfHandler` + slot constants (SLOT_PACKED_0 = 0, SLOT_RNG_WORD_CURRENT = 3, SLOT_VRF_REQUEST_ID = 4) + `_lastFulfilledReqId` + `DRAIN_MAX_ITERATIONS = 50` |
| 4 | `// ANCHOR: SETUP` | `setUp()`: `_deployProtocol() + vm.warp(+1 day) + vrfHandler = new VRFHandler(...) + mockVRF.fundSubscription(1, 100e18)` |
| 5 | `// ANCHOR: SHARED_HELPERS` | `_completeDay` + `_readRngWordCurrent` + `_readVrfRequestId` + `_advanceToVrfRequestBoundary` + `_deliverMockVrf` + `_snapshotPreLock` + `_revertToPreLock` + `_assertVrfOutputByteIdentity` |
| 6 | `// ANCHOR: ACTION_LIBRARY` | `_perturb(uint256 seed)` with N_PERTURB_ACTIONS = 9 classes (degenerette bet / mint / claim / ERC20 transfer / ERC721 transferFrom / ERC20 approve / affiliate createAffiliateCode / admin path / retryLootboxRng) |
| 7 | `// ANCHOR: FUNC_PayDailyJackpot` | `testFuzz_RngLockDeterminism_PayDailyJackpot(uint256 vrfWord, uint256 perturbSeed)` + `_digestPayDailyJackpotOutputs(Vm.Log[])` helper |
| 8 | `// ANCHOR: FUNC_RunTerminalJackpot` | `testFuzz_RngLockDeterminism_RunTerminalJackpot(uint256 vrfWord, uint256 perturbSeed)` + `_digestRunTerminalJackpotOutputs(Vm.Log[])` helper |
| 9 | `// ANCHOR: SCAFFOLD_END` | Trailing marker enumerating Wave-2 append targets (cluster contributions 02/03/04/05 + closing `}` + vm.skip blocks) |

## Shared Helpers Inventory

| Helper | Purpose | Source |
|--------|---------|--------|
| `_completeDay(uint256 vrfWord)` | advanceGame → fulfillRandomWords → drain loop with `_lastFulfilledReqId` sentinel | Ported verbatim from `test/fuzz/LootboxRngLifecycle.t.sol` |
| `_readRngWordCurrent()` | SLOAD slot 3 (rngWordCurrent) via `vm.load` | Ported verbatim from `test/fuzz/LootboxRngLifecycle.t.sol` |
| `_readVrfRequestId()` | SLOAD slot 4 (vrfRequestId) via `vm.load` | Ported verbatim from `test/fuzz/LootboxRngLifecycle.t.sol` |
| `_advanceToVrfRequestBoundary()` | warp 1 day → advanceGame → assert lock+reqId→return reqId | New; standardizes VRF-arming sequence for all 18 fuzz functions |
| `_deliverMockVrf(uint256 reqId, uint256 word)` | fulfillRandomWords + post-fulfill drain loop | New; abstracts the Phase-4 Resolution mechanic |
| `_snapshotPreLock()` / `_revertToPreLock(snapshotId)` | `vm.snapshot` / `vm.revertTo` wrappers for symmetry | New |
| `_assertVrfOutputByteIdentity(bytes32, bytes32, string)` | Canonical equality assertion site | New; Wave-2 wraps THIS line with `vm.skip` per VIOLATION |

## Perturbation Action Library Class Count

`N_PERTURB_ACTIONS = 9` distributed via `seed % 9`:

| Class | Action | FUZZ-02 / ADMA-01 mapping |
|-------|--------|---------------------------|
| 0 | Degenerette bet (ETH currency) | FUZZ-02 player bet |
| 1 | `game.purchase` with `MintPaymentKind.DirectEth` | FUZZ-02 mint |
| 2 | `game.claimWinnings(address player)` | FUZZ-02 claim |
| 3 | `coin.transfer(recipient, amount)` (BURNIE ERC20) | FUZZ-02 ERC20 transfer |
| 4 | `dgnrs.transferFrom(actor, recipient, tokenId)` (DGNRS ERC721) | FUZZ-02 ERC721 transfer |
| 5 | `coin.approve(spender, amount)` (BURNIE) | FUZZ-02 approval |
| 6 | `affiliate.createAffiliateCode(code_, kickbackPct)` | FUZZ-02 affiliate |
| 7 | Admin path call (`vm.prank(admin)` + benign admin-context call) | ADMA-01 R-01..R-22 envelope (sibling plans may specialize) |
| 8 | `retryLootboxRng()` (warp +6h + 1 cooldown elapsed) | Phase 296 failsafe surface (`D-43N-RETRY-RNG-DOMAIN-SEP-01` deferred) |

Every class is wrapped in `try ... catch { return; }` so unsatisfiable iteration preconditions silently no-op without failing the iteration (no-op MUST still pass byte-identity trivially since `perturbed == baseline` when `_perturb` is a no-op).

## Locked 6-Phase Template

Sibling cluster plans 02/03/04 author each remaining per-consumer fuzz function by replicating this structure verbatim and substituting ONLY the per-consumer setup (Phase 1) + assertion-target digest helper (Phase 4/5):

| Phase | Step | What it does |
|-------|------|--------------|
| 1 | Setup | `vm.assume(vrfWord != 0)` + `_completeDay(<bootstrap-seed>)` + per-consumer state arming + `preLockSnap = _snapshotPreLock()` |
| 2 | Lock | `reqId = _advanceToVrfRequestBoundary()` (asserts lock engaged + reqId != 0 internally) |
| 3 | Perturbation | `_perturb(perturbSeed)` + `assertTrue(game.rngLocked())` (lock MUST NOT lift during perturbation) |
| 4 | Resolution under perturbation | `vm.recordLogs()` → `_deliverMockVrf(reqId, vrfWord)` → `perturbedOutputs = _digest<Consumer>Outputs(vm.getRecordedLogs())` |
| 5 | Baseline | `_revertToPreLock(preLockSnap)` → re-run lock + `_deliverMockVrf` WITHOUT `_perturb` → `baselineOutputs = _digest<Consumer>Outputs(...)` |
| 6 | Assert | `_assertVrfOutputByteIdentity(perturbedOutputs, baselineOutputs, "<consumer>: VRF-derived outputs must be byte-identical under perturbation")` |

## Decisions Made

- **Anchor-bracketed contribution shape:** Used `// ANCHOR: <NAME>` comments at every paste region so the Wave-2 aggregator can find regions mechanically without parsing Solidity. Mirrors Phase 299 Wave-1 cluster-contribution shape per the plan's explicit "Mirrors Phase 299 Wave-1 cluster-contribution shape" call-out.
- **VRF-output digest via event-log capture:** Used `vm.recordLogs()` → `vm.getRecordedLogs()` → keccak256-collapse rather than per-getter SLOADs because (a) the consumer surfaces emit recipient/amount via events not necessarily exposed as public getters, and (b) event-digest captures the FULL VRF-derived observable set (hero-byte, recipient, amount, trait-burn-ticket selection) in one digest. Restricts to `address(game)`-emitted logs so cross-contract emissions (sDGNRS reward-pool transfers) don't pollute the digest beyond the consumer's VRF-derived scope per RNGLOCK-CATALOG.md §1 attestation.
- **Storage-bind in digest:** Appended `keccak256(rngWordCurrent, vrfRequestId)` to the event digest so any storage-side determinism drift is caught even if events somehow agree.
- **Reference function template only:** Authored ONLY 2 of 13 per-consumer fuzz functions at this plan. Cluster plans 02/03/04 author the remaining 11 (§2, §4, §5, §6, §7, §8, §9, §10, §11, §12, §13) by copying the reference template's 6-phase structure verbatim and substituting per-consumer Phase-1 setup + per-consumer digest helper. This eliminates inconsistency across the 18 functions and is the central purpose of the scaffold plan.
- **No vm.skip blocks attached:** Per D-301-VMSKIP-MECHANISM-01, vm.skip blocks land at the Wave-2 aggregator AFTER running the un-skipped test set, so each skip block can carry a precise FIXREC §N cross-reference for v44.0 flip discipline. Adding them prematurely would require speculation about which assertions fail at v43 contract state.
- **Sandbox-build verification approach:** Confirmed syntactic validity via temporary `test/fuzz/_SandboxRngLockDeterminism.t.sol` with closing `}` appended; `forge build` returned 0 errors; the sandbox was deleted before commit, preserving the `D-43N-AUDIT-ONLY-01` zero-test-tree-mutation invariant at this plan.

## Deviations from Plan

None - plan executed exactly as written. Two minor sandbox-build fixes adjusted action-library function signatures to match production contracts (not deviations from the plan's stated requirements, which mandated `claimWinnings()` + `affiliate.register(...)` with the explicit "consult contracts/DegenerusAffiliate.sol if needed" guidance):

- `game.claimWinnings()` → `game.claimWinnings(address player)` (production signature requires explicit player arg per `DegenerusGame.sol:1387`)
- `affiliate.register(...)` → `affiliate.createAffiliateCode(bytes32 code_, uint8 kickbackPct)` (production-actual player-callable affiliate entry per `DegenerusAffiliate.sol:303`; the plan explicitly authorized signature substitution with "signature per actual function; consult `contracts/DegenerusAffiliate.sol` if needed")

Both substitutions were anticipated by the plan's `<action>` wording and do not constitute Rule-N deviations.

## Issues Encountered

None blocking. Sandbox `forge build` initially reported 2 compile errors (the two signature mismatches above); both fixed inline before committing the contribution; final sandbox build returned 0 errors.

## User Setup Required

None - scaffold contribution is internal `.planning/` content; no environment configuration needed.

## Next Phase Readiness

- **301-02 (Cluster A) ready:** Has reference template + shared helpers + action library available for replication into per-consumer functions §2, §4, §5, §6 (per D-301-COVERAGE-01)
- **301-03 (Cluster B) ready:** Same. Covers §7, §8, §9, §10
- **301-04 (Cluster C) ready:** Same. Covers §11, §12, §13
- **301-05 (Edge Cases) ready:** Has shared helpers + action library for replication into 5 edge-case functions per D-301-EDGE-CASES-01
- **301-06 (Wave 2 Aggregator) blocked by 02/03/04/05:** Cannot run until cluster + edge-case contributions exist; aggregator concatenates this scaffold + all sibling contributions + closing `}` + vm.skip blocks into `test/fuzz/RngLockDeterminism.t.sol`

No blockers or concerns. Sandbox-build attestation confirms the scaffold compiles cleanly when wrapped with a closing `}`.

## Self-Check: PASSED

- File exists: `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-01-SCAFFOLD-contribution.sol` — FOUND
- All 8 plan-required anchors present (HEADER + CONTRACT_OPEN + SETUP + SHARED_HELPERS + ACTION_LIBRARY + FUNC_PayDailyJackpot + FUNC_RunTerminalJackpot + SCAFFOLD_END) — FOUND (verified via plan's `<verify>` block grep checks)
- 2 reference fuzz function names match D-301-COVERAGE-01 spec verbatim (`testFuzz_RngLockDeterminism_PayDailyJackpot` + `testFuzz_RngLockDeterminism_RunTerminalJackpot`) — FOUND
- Sandbox `forge build` returned 0 errors — VERIFIED
- `git status --porcelain contracts/` empty — VERIFIED
- `git status --porcelain test/` empty (sandbox deleted after build) — VERIFIED

---

*Phase: 301-state-shuffle-determinism-fuzz-harness-fuzz*
*Completed: 2026-05-18*
