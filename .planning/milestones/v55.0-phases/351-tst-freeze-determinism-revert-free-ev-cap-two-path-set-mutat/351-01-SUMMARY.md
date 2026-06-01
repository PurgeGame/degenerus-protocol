---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 01
subsystem: testing
tags: [foundry, fixture, deploy-order, create-nonce, predictAddresses, patchForFoundry, afking, game-resident, delegatecall-module]

# Dependency graph
requires:
  - phase: 349.1
    provides: "AfKing.sol dissolved into DegenerusGame (GameAfkingModule); ContractAddresses.sol gained GAME_BINGO_MODULE + GAME_AFKING_MODULE, dropped AF_KING"
  - phase: 349.2
    provides: "the frozen 453f8073 contract subject (game-resident afking surface + restored LOOTBOX quest/affiliate)"
provides:
  - "A compiling shared Foundry fixture (DeployProtocol.sol) that deploys the game-resident GameAfkingModule + DegenerusGameBingoModule at their ContractAddresses constants"
  - "A reconciled predictAddresses.js DEPLOY_ORDER + KEY_TO_CONTRACT (GAME_BINGO_MODULE N+10 / GAME_AFKING_MODULE N+11, AF_KING dropped) consumed by BOTH the Foundry fixture and the Hardhat deployFixture"
  - "A repaired DeployCanary.t.sol deploy-order alignment guard (asserts both new modules land at their constants; SUB-09 self-subscribe runs against live module code)"
  - "deferred-items.md enumerating the 13 still-broken AfKing/keeper corpus files owned by downstream 351 plans"
affects: [351-02, 351-03, 351-04, 351-05, 351-06, 351-07, 351-08, 351-09, "all downstream AfKing/keeper corpus adaptation", "TST-06 gas harness", "REGRESSION-BASELINE-v55.md"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fixture-first un-bricking (Wave 0): repair the shared deploy helper + deploy-order script before per-file corpus adaptation (v46 Phase 318 precedent)"
    - "Source-order == DEPLOY_ORDER == patched ContractAddresses.sol constant order: the CREATE-nonce alignment invariant the fixture relies on under patchForFoundry"
    - "patch -> test -> restore(.bak) -> cleanup round-trip keeps contracts/ContractAddresses.sol frozen while running address-dependent Foundry tests"

key-files:
  created:
    - ".planning/phases/351-.../deferred-items.md"
    - ".planning/phases/351-.../351-01-SUMMARY.md"
  modified:
    - "scripts/lib/predictAddresses.js"
    - "test/fuzz/helpers/DeployProtocol.sol"
    - "test/fuzz/DeployCanary.t.sol"

key-decisions:
  - "Wave-0 scope held to the SHARED fixture + deploy-order script (+ the in-idiom deploy canary); the 13 AfKing/keeper corpus files' full property adaptation stays with their downstream 351 plans (351-PATTERNS.md §2-13)"
  - "DeployCanary.t.sol is the Task-3 alignment vehicle (the existing in-repo address-assertion idiom) — repaired its 2 stale AF_KING lines to assert address(afkingModule)==GAME_AFKING_MODULE + address(bingoModule)==GAME_BINGO_MODULE"
  - "Added GAME_BINGO_MODULE + GAME_AFKING_MODULE to KEY_TO_CONTRACT (not just DEPLOY_ORDER) — both patchContractAddresses and the Hardhat deployFixture resolve the Solidity contract name by key; an orphan DEPLOY_ORDER key would break the Hardhat sanity fixture (Rule 2)"
  - "TST-05 left Pending — this Wave-0 plan does NOT author REGRESSION-BASELINE-v55.md (a downstream deliverable); the plan-frontmatter requirements:[TST-05] is a mismatch (this plan ENABLES the regression run, it does not produce the BY-NAME ledger)"

patterns-established:
  - "Deploy-order drift fails LOUD: DeployCanary asserts every module == its ContractAddresses constant, so a wrong CREATE nonce surfaces as an assertEq failure, never a silent delegatecall mis-dispatch"

requirements-completed: []  # TST-05 NOT completed here — see key-decisions (downstream ledger deliverable)

# Metrics
duration: 13min
completed: 2026-05-31
---

# Phase 351 Plan 01: DeployProtocol Fixture Repair (Wave 0) Summary

**Un-bricked the shared Foundry fixture by deploying the game-resident `GameAfkingModule` + `DegenerusGameBingoModule` at their `ContractAddresses` nonce slots (dropping the dissolved standalone `AfKing`), reconciling `predictAddresses.js` `DEPLOY_ORDER`/`KEY_TO_CONTRACT`, and proving the deploy-order alignment + SUB-09 self-subscribe via the `DeployCanary` guard — ZERO contract mutation.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-05-31T17:20:29Z
- **Completed:** 2026-05-31T17:32:58Z
- **Tasks:** 3
- **Files modified:** 4 (3 source/script/test + 1 deferred-items doc)

## Accomplishments
- **The AfKing.sol compile cascade *through the fixture* is cleared** — `DeployProtocol.sol` no longer imports the deleted `contracts/AfKing.sol`; `forge build` (skipping the 13 still-broken downstream-charge corpus files) exits 0, and the fixture's own compile closure compiles cleanly.
- **`new GameAfkingModule()` lands at `ContractAddresses.GAME_AFKING_MODULE`** and `new DegenerusGameBingoModule()` lands at `GAME_BINGO_MODULE` — PROVEN by `DeployCanary.test_allAddressesMatch()` PASS after `patchForFoundry`.
- **The VAULT/SDGNRS constructor SUB-09 self-subscribe hits live game-resident module code** — `DeployCanary.test_protocolWired()` PASS means `_deployProtocol()` ran the VAULT + SDGNRS constructors (which call `game.subscribe(...)`) without reverting, because GAME + the afking module are deployed first.
- **The deploy-order script is reconciled for BOTH runners** — `predictAddresses.js` `DEPLOY_ORDER` + `KEY_TO_CONTRACT` now list `GAME_BINGO_MODULE` (N+10) + `GAME_AFKING_MODULE` (N+11) before VAULT/SDGNRS and drop `AF_KING`; the shared array is consumed by the Foundry fixture AND the Hardhat `deployFixture.js`.
- **ZERO `contracts/*.sol` mutation** — `git diff 453f8073 HEAD -- contracts/` is EMPTY; `ContractAddresses.sol` restored byte-identical (sha256 match) after the patch round-trip.

## Task Commits

Each task was committed atomically (test/script/docs only — no contracts/):

1. **Task 1: Reconcile predictAddresses.js DEPLOY_ORDER** - `8ce35690` (test)
2. **Task 2 + 3: Repair DeployProtocol.sol fixture + DeployCanary alignment guard** - `7978fdc2` (test)
3. **deferred-items.md (downstream-charge corpus log)** - `7e85877c` (docs)

_Tasks 2 and 3 were committed together: the fixture repair (Task 2) and its deploy-order alignment canary (Task 3, `DeployCanary.t.sol`) are tightly coupled — the canary's `assertEq` proves the Task-2 deploy order._

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Created/Modified
- `scripts/lib/predictAddresses.js` — DEPLOY_ORDER: insert `GAME_BINGO_MODULE` (N+10) + `GAME_AFKING_MODULE` (N+11) in the game-module block before VAULT/SDGNRS; drop the dissolved `AF_KING`; renumber the N+ constraint comments. KEY_TO_CONTRACT: add `DegenerusGameBingoModule` + `GameAfkingModule`, drop `AfKing`.
- `test/fuzz/helpers/DeployProtocol.sol` — drop the `AfKing` import + `afKing` state var + `new AfKing(...)` deploy; import + deploy `DegenerusGameBingoModule` + `GameAfkingModule` (no ctor args, mirroring the 10 sibling module deploys) at the matching DEPLOY_ORDER nonce positions; correct the stale SUB-09 comments (`AfKing.subscribe` → `game.subscribe`); document the manual `patchForFoundry` prerequisite.
- `test/fuzz/DeployCanary.t.sol` — replace the 2 stale `AF_KING` assertions (`:35` address + `:62` code-length) with `address(bingoModule)==GAME_BINGO_MODULE` + `address(afkingModule)==GAME_AFKING_MODULE` (and code-length asserts), so a deploy-order drift fails LOUD.
- `.planning/phases/351-.../deferred-items.md` — enumerate the 13 still-broken AfKing/keeper corpus files + their downstream 351-plan owners.

## Decisions Made
- **Wave-0 scope discipline.** Held the plan to its `files_modified` frontmatter (the shared fixture + the deploy-order script), plus the in-idiom deploy canary for the Task-3 alignment guard. The 13 AfKing/keeper corpus files' full property adaptation (29–68 `afKing.` rewrites each, slot re-derivation, the differential oracle) is the explicit charge of the downstream 351 plans per `351-PATTERNS.md` §2–§13. Rewriting them here would steal downstream scope and risk colliding with later waves.
- **`DeployCanary.t.sol` as the Task-3 vehicle.** The plan's Task-3 `read_first` pointed at "any existing fixture address-assertion idiom" — `DeployCanary` IS that idiom (it asserts every module == its `ContractAddresses` constant). It was in the broken set ONLY because of 2 stale `afKing`/`AF_KING` lines; fixing them is a deploy-alignment fix (Task-3's exact charge), not a property adaptation, so it legitimately belongs to 351-01.
- **`KEY_TO_CONTRACT` kept in sync (Rule 2 — see Deviations).** Not just `DEPLOY_ORDER`.
- **TST-05 left Pending.** The plan frontmatter lists `requirements: [TST-05]`, but TST-05 = the NON-WIDENING `REGRESSION-BASELINE-v55.md` BY-NAME ledger, a downstream deliverable that does not exist yet. This Wave-0 fixture-repair *enables* the regression run; it does not produce the ledger. Marking TST-05 complete would be a false claim — left Pending for the downstream plan that authors the baseline.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Synced `KEY_TO_CONTRACT` + the Hardhat `deployFixture.js` consumer with the `DEPLOY_ORDER` change**
- **Found during:** Task 1 (predictAddresses.js DEPLOY_ORDER reconciliation)
- **Issue:** The plan's Task 1 action centered on `DEPLOY_ORDER`, but the same module — `scripts/lib/predictAddresses.js` `KEY_TO_CONTRACT` — maps each DEPLOY_ORDER key to a Solidity contract name, and BOTH `patchContractAddresses.js` AND the Hardhat `test/helpers/deployFixture.js` (`KEY_TO_CONTRACT[key]` → `deploy(contractName)`) read it. Adding the two new module keys to `DEPLOY_ORDER` without adding them to `KEY_TO_CONTRACT` would leave an orphan key → the Hardhat fixture would call `deploy(undefined)` and break the cross-runner sanity check (CONTEXT keeps the Hardhat suite compiling/passing as a sanity check).
- **Fix:** Added `GAME_BINGO_MODULE: "DegenerusGameBingoModule"` + `GAME_AFKING_MODULE: "GameAfkingModule"` to `KEY_TO_CONTRACT` and removed the `AF_KING: "AfKing"` entry. (The now-dead `if (key === "AF_KING")` constructor-args branch in `deployFixture.js` is harmless — the key no longer appears in DEPLOY_ORDER — and is left for the downstream Hardhat-sanity touch to avoid widening this plan's blast radius.)
- **Files modified:** scripts/lib/predictAddresses.js
- **Verification:** node integrity check — every DEPLOY_ORDER key maps to a KEY_TO_CONTRACT entry AND a live ContractAddresses.sol constant (`ALL-KEYS-MAP-OK: true`); the DeployCanary build (which exercises the predicted-address map via patchForFoundry) compiled + passed.
- **Committed in:** 8ce35690 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing-critical).
**Impact on plan:** The fix is necessary for the cross-runner deploy-order correctness the CONTEXT requires (Hardhat sanity check). No scope creep — it is the same file + the same reconciliation the task already touched.

## Issues Encountered
- **The full-tree `forge build` does NOT pass after this plan** — and cannot, by design. Beyond the fixture, **13** AfKing/keeper corpus test files independently reference the dissolved standalone AfKing (the deleted `contracts/AfKing.sol` import, the removed `ContractAddresses.AF_KING` constant, or the removed `afKing` fixture var). These breaks are pre-existing (the 349.1 `AfKing.sol` deletion), not caused by the fixture edit, and each file's adaptation is the explicit charge of a downstream 351 plan (`351-PATTERNS.md` §2–§13). Logged in `deferred-items.md`. The Wave-0 contract — un-brick the shared fixture so downstream can compile incrementally — IS met (DeployProtocol.sol compiles + DeployCanary PASSES).
- **No pretest patch hook** — `patchForFoundry.js` is NOT auto-invoked by `forge build`/`forge test` (verified: no hook in `foundry.toml` or `package.json`). To run address-dependent Foundry tests one must `node scripts/lib/patchForFoundry.js` first, then restore `ContractAddresses.sol` via `restoreContractAddresses()` + `cleanupBackup()` (the `.bak` round-trip) to keep `contracts/` frozen. Documented in the fixture comment + `deferred-items.md` for downstream plans.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The shared fixture compiles against the game-resident model; the deploy-order script + the patched constants are reconciled; the deploy alignment is guarded by `DeployCanary`. Downstream 351 plans (corpus adaptation, the v55 freeze/revert-free/EV-cap/set-mutation proofs, the TST-06 gas harness, the `REGRESSION-BASELINE-v55.md` ledger) can now compile + run their individual files against `GameAfkingModule`.
- **Blocker for a green full-tree run:** the 13 corpus files in `deferred-items.md` must be adapted by their downstream plans before `forge test` runs clean tree-wide. That is the phase's collective charge, not this Wave-0 plan's.
- **TST-05 (NON-WIDENING ledger) remains Pending** — its downstream plan authors `REGRESSION-BASELINE-v55.md`.

## Self-Check: PASSED

Created/modified files exist:
- FOUND: `scripts/lib/predictAddresses.js`
- FOUND: `test/fuzz/helpers/DeployProtocol.sol`
- FOUND: `test/fuzz/DeployCanary.t.sol`
- FOUND: `.planning/phases/351-.../deferred-items.md`
- FOUND: `.planning/phases/351-.../351-01-SUMMARY.md`

Task commits exist:
- FOUND: `8ce35690` (Task 1 — predictAddresses DEPLOY_ORDER)
- FOUND: `7978fdc2` (Task 2+3 — fixture + DeployCanary)
- FOUND: `7e85877c` (deferred-items log)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); `ContractAddresses.sol` sha256 == frozen baseline `80fe0dac…`.

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
