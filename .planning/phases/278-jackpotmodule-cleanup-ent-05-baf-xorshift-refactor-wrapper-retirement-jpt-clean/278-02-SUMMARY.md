---
phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean
plan: 02
subsystem: jackpot
tags: [solidity, hardhat, testing, keccak, entropy, chi-square, regression, cross-surface, event-surface]

# Dependency graph
requires:
  - phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean
    plan: 01
    provides: "_jackpotTicketRoll keccak self-mix (hash2(entropy, entropy)), 3 whole-ticket JackpotTicketWin emits, EntropyLib.entropyStep + _queueLootboxTickets deletions — the contract surface this test wave validates"
provides:
  - "test/stat/Ent05KeccakRefactorInvariant.test.js — TST-CLEAN-01 post-keccak-refactor statistical invariant: chi-square uniformity of the 30/65/5 path roll + near/far offsets, 2-roll per-roll seed-uniqueness, bits[200..215] Bernoulli sub-roll independence, all under the keccak word, plus a production drift-gate"
  - "test/integration/CrossSurfaceTicketMixing.test.js — TST-CROSS-01 full-stack cross-surface shared-slot rem-byte regression + TST-CLEAN-02 _queueLootboxTickets wrapper-removal regression + TST-CLEAN-03 whole-ticket JackpotTicketWin emit regression"
  - "Every test-tree + contracts/test entropyStep replica/drift-gate updated to the keccak evolution — zero EntropyLib.entropyStep live references, zero JS xorshift replicas"
  - "test/stat/SurfaceRegression.test.js v40.0 SURF block re-baselining the drift gate onto the keccak swap site; 8 stale v36/v37/v38 assertions superseded via it.skip"
  - "test/unit/EventSurfaceUnification.test.js Phase 277 jackpot-event assertions re-targeted from scaled ticketCount to whole-ticket"
affects: [280 terminal audit, EXC-04 KI envelope demotion]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "JS keccak rollEvolve replica: BigInt(solidityPackedKeccak256(['uint256','uint256'], [state, state])) mirroring the on-chain hash2(entropy, entropy) scratch-slot self-mix — replaces the xorshift entropyStep JS replica across the stat suite"
    - "Production drift-gate on a JS statistical replica: grep the production module for the canonical evolution line and assert it before running the stat assertions, so replica/production second-arg drift fails fast"
    - "FIXTURE_COVERAGE_GAP soft-skip: a live-state integration leg that cannot reach its fixture precondition soft-skips (it.skip-equivalent pending) while a structural cross-check still covers the invariant — Phase 274/275/277 precedent"

key-files:
  created:
    - test/stat/Ent05KeccakRefactorInvariant.test.js
    - test/integration/CrossSurfaceTicketMixing.test.js
  modified:
    - test/stat/SurfaceRegression.test.js
    - test/stat/JackpotTicketRollSeedUniqueness.test.js
    - test/stat/JackpotTicketRollBernoulliEv.test.js
    - test/fuzz/RollRemainderGas.t.sol
    - test/fuzz/TicketLifecycle.t.sol
    - test/unit/EventSurfaceUnification.test.js
    - contracts/test/JackpotBernoulliTester.sol
    - package.json

key-decisions:
  - "D-278-ENT05-TEST-01 honored: TST-CLEAN-01 asserts the NEW post-refactor invariant (uniformity + 2-roll uniqueness + bits[200..215] independence under the keccak word), NOT byte-equivalence to v39 — v39->v40 BAF roll outputs differ by design"
  - "TST-CROSS-01 placement is test/integration/CrossSurfaceTicketMixing.test.js — already directory-globbed by both the `test` and `test:integration` scripts, so it is CI-wired with zero package.json edit; only the new stat test needed a test:stat script-list append"
  - "TST-CROSS-01 live-state manual-open leg (CROSS-01b) soft-skips when the integration fixture cannot reach an openable lootbox — user-accepted FIXTURE_COVERAGE_GAP, consistent with Phase 274/275/277 precedent; the structural cross-check CROSS-01d still covers the rem-byte invariant and CROSS-01a/c exercise live-state on the reachable baseline path"

requirements-completed: [TST-CLEAN-01, TST-CLEAN-02, TST-CLEAN-03, TST-CROSS-01]

# Metrics
duration: ~40min
completed: 2026-05-14
---

# Phase 278 Plan 02: JackpotModule Cleanup Test Wave Summary

**Two new test files (`Ent05KeccakRefactorInvariant.test.js` proving the post-keccak-refactor statistical invariant at N=20,000, `CrossSurfaceTicketMixing.test.js` proving cross-surface ticket-award independence via a live-state `ticketsOwedPacked` rem-byte read + the `_queueLootboxTickets` removal + whole-ticket `JackpotTicketWin` emit regressions), plus every `entropyStep` JS/Solidity replica and drift-gate across the test tree re-baselined onto the keccak `hash2(entropy, entropy)` evolution — landed in one user-approved batched test commit `c3baf694`.**

## Performance

- **Duration:** ~40 min total (Tasks 1-2 by prior executor agent; Task 3 commit + this summary by continuation agent post-approval)
- **Completed:** 2026-05-14
- **Tasks:** 3 (Tasks 1-2 by prior executor agent; Task 3 = the blocking human-verify checkpoint, batched-diff review, commit, and this summary)
- **Files modified:** 8 (2 new test files + 6 modified) + 1 contracts/test helper (NatSpec-only) + package.json

## Accomplishments
- **TST-CLEAN-01 — ENT-05 post-keccak-refactor statistical invariant:** `test/stat/Ent05KeccakRefactorInvariant.test.js` (377 LOC) asserts the NEW invariant per D-278-ENT05-TEST-01 (not v39 byte-equivalence): chi-square goodness-of-fit uniformity of the 30/65/5 path-branch split + the near (`{0,1,2,3}`) and far (`{0..45}`) offset distributions under the keccak word (Wilson-Hilferty Z < 4 at N=20,000); per-roll seed-uniqueness across the 2-roll pattern via a JS `rollEvolve` keccak replica mirroring the on-chain `hash2(entropy, entropy)` self-mix (roll 1 = `rollEvolve(E)`, roll 2 = `rollEvolve(rollEvolve(E))`, distinct for every base E, pairs independent at Z < 3.5); bits[200..215] Bernoulli sub-roll independence (pairwise chi-square vs pathRoll/nearOffset/farOffset, Z < 3.5). Carries a drift-gate asserting the production line reads `entropy = EntropyLib.hash2(entropy, entropy);` so replica/production drift fails before the stat assertions. **10/10 passing.**
- **TST-CROSS-01 — cross-surface rem-byte regression:** `test/integration/CrossSurfaceTicketMixing.test.js` (755 LOC) reads the genuinely-shared `ticketsOwedPacked[wk][player]` slot via raw `provider.getStorage` — baseline `rem == 0` (CROSS-01a), slot-math self-validation round-tripping `owed` against the public `ticketsOwedView` accessor (CROSS-01c), and a structural cross-check (CROSS-01d) proving the 3 RNG-driven surfaces route through `_queueTickets` (whole, no rem write) while `_queueTicketsScaled` is the sole rem-byte writer. The live-state manual-open leg (CROSS-01b) soft-skips — see Deviations. **11 passing / 1 pending.**
- **TST-CLEAN-02 — `_queueLootboxTickets` wrapper-removal regression:** asserts zero `_queueLootboxTickets` references in `DegenerusGameStorage.sol`, zero declarations/invocations across all `contracts/` `.sol` files, and that the 3 sibling helpers (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) are still present.
- **TST-CLEAN-03 — whole-ticket `JackpotTicketWin` emit regression:** asserts exactly 3 `emit JackpotTicketWin` sites, none multiplying the 4th arg by `TICKET_SCALE`, emitting in source order the whole counts `ticketCount` / `uint32(units)` / `whole`, each matching its adjacent `_queueTickets` storage-write argument; asserts the `JackpotTicketWin` event definition (field types + indexed markers) is unchanged across the Phase 278 wave and the compiled ABI fragment carries the 7-field post-Phase-277 signature with exactly 3 indexed params.
- **entropyStep replica/drift-gate re-baseline:** `JackpotTicketRollSeedUniqueness.test.js` JS xorshift `entropyStep` replica replaced with the keccak `rollEvolve` self-mix and its 2-roll block rethreaded; `SurfaceRegression.test.js` gains a v40.0 SURF block re-pinning the drift gate onto the keccak swap site (8 stale v36/v37/v38 assertions superseded via `it.skip`); `JackpotTicketRollBernoulliEv.test.js` + `TicketLifecycle.t.sol` comment-only rewords off the deleted name; `RollRemainderGas.t.sol` `EntropyLib.entropyStep` → `EntropyLib.hash2(entropy, rollSalt)` (fixes the Wave-1 compile break + aligns the gas harness with the real `_rollRemainder`); `JackpotBernoulliTester.sol` NatSpec re-worded off the deleted name (arithmetic byte-unchanged).
- **Phase 277 jackpot-event assertions:** `test/unit/EventSurfaceUnification.test.js` `JackpotTicketWin` arg assertions re-targeted from `× TICKET_SCALE` scaled `ticketCount` to whole-ticket counts; `roundedUp` (7th arg) assertions unchanged.

## Task Commits

1. **Task 1: TST-CLEAN-01 ENT-05 invariant + entropyStep replica/drift-gate updates** — part of `c3baf694` (test) — applied in working tree by prior executor agent
2. **Task 2: TST-CROSS-01 cross-surface regression + TST-CLEAN-02/03 + Phase 277 jackpot-event assertion update** — part of `c3baf694` (test) — applied in working tree by prior executor agent
3. **Task 3: full affected-suite run + batched-diff approval + commit** — `c3baf694` (test) — the single batched USER-APPROVED test commit carrying all of Tasks 1-3

**Plan metadata:** committed alongside this SUMMARY + `deferred-items.md` as a separate docs commit.

_Note: Phase 278 follows the project's batched-test-approval discipline — all test-wave edits from Tasks 1-2 land in ONE user-approved commit (`c3baf694`), not per-task commits. The commit includes `contracts/test/JackpotBernoulliTester.sol` (a test-helper NatSpec-only touch, batched per `feedback_batch_contract_approval.md`); the repo's contract-commit guard required `CONTRACTS_COMMIT_APPROVED=1` to stage it — set after explicit user approval of the batched diff, consistent with plan 278-01's commit `8a81a87c`._

## Files Created/Modified
- `test/stat/Ent05KeccakRefactorInvariant.test.js` (new, 377 LOC) — TST-CLEAN-01 post-keccak-refactor statistical invariant
- `test/integration/CrossSurfaceTicketMixing.test.js` (new, 755 LOC) — TST-CROSS-01 cross-surface rem-byte regression + TST-CLEAN-02/03 wrapper-removal & whole-ticket-event regression
- `test/stat/SurfaceRegression.test.js` — v40.0 SURF block re-baselining the drift gate onto the keccak swap site; 8 stale v36/v37/v38 assertions superseded via `it.skip`
- `test/stat/JackpotTicketRollSeedUniqueness.test.js` — JS xorshift `entropyStep` replica replaced with the keccak `rollEvolve`; 2-roll uniqueness block rethreaded onto `rollEvolve(rollEvolve(E))`
- `test/stat/JackpotTicketRollBernoulliEv.test.js` — comment re-worded off the deleted `entropyStep` name (EV-neutrality math + Bernoulli-predicate drift-grep unchanged)
- `test/fuzz/RollRemainderGas.t.sol` — `EntropyLib.entropyStep` → `EntropyLib.hash2(entropy, rollSalt)` (fixes the Wave-1 compile break; aligns the gas harness with the real `_rollRemainder`)
- `test/fuzz/TicketLifecycle.t.sol` — comment-only reword off the deleted `entropyStep` name
- `test/unit/EventSurfaceUnification.test.js` — Phase 277 `JackpotTicketWin` arg assertions re-targeted from scaled `ticketCount` to whole-ticket
- `contracts/test/JackpotBernoulliTester.sol` — NatSpec re-worded off the deleted `entropyStep` name; `bernoulliWhole`/`bernoulliSlice`/`bernoulliRaw16` arithmetic byte-unchanged
- `package.json` — single `test:stat` script-list append for `test/stat/Ent05KeccakRefactorInvariant.test.js` (the new integration test is wired by the existing `test/integration/` directory glob — no script edit)

## Decisions Made
- **D-278-ENT05-TEST-01 honored** — TST-CLEAN-01 asserts the NEW post-refactor invariant under the keccak word (uniformity + 2-roll uniqueness + bits[200..215] independence), NOT byte-equivalence to v39: the keccak swap intentionally changes BAF roll output for a given seed, so a byte-equivalence test would be wrong.
- **TST-CROSS-01 placement = `test/integration/`** — `test/integration/` is directory-globbed by both the `test` and `test:integration` `package.json` scripts, so `CrossSurfaceTicketMixing.test.js` is CI-wired with zero `package.json` edit. Only `Ent05KeccakRefactorInvariant.test.js` (in `test/stat/`, an explicit file-list script) needed a `test:stat` append. No `test:regression` script was invented.
- **TST-CROSS-01 FIXTURE_COVERAGE_GAP accepted by user** — the live-state manual-open leg (CROSS-01b) soft-skips when the integration fixture cannot reach an openable lootbox; the full-stack auto-resolve + jackpot-roll surfaces are covered structurally (CROSS-01d) and the live-state rem-byte read is exercised on the reachable baseline path (CROSS-01a/c). The user explicitly accepted this gap as consistent with the Phase 274/275/277 soft-skip precedent (`LootboxOpenGas.test.js` `reachOpenableLootbox`).

## Deviations from Plan

### Auto-fixed Issues

None requiring an auto-fix beyond what was already scoped — the `RollRemainderGas.t.sol` `EntropyLib.entropyStep` → `hash2` rewrite was an explicit Task 1 (e) action (it both fixes the Wave-1 compile break and aligns the gas harness with the real `_rollRemainder`), not an unplanned deviation.

### Documented Coverage Gap (user-accepted)

**TST-CROSS-01 CROSS-01b live-state manual-open leg soft-skips (FIXTURE_COVERAGE_GAP)**
- **Found during:** Task 1/3 affected-suite run.
- **Symptom:** the manual lootbox-open leg reverts with custom error `E()` when the `test/integration/` fixture cannot reach an openable lootbox state, matching the `LootboxOpenGas.test.js` `reachOpenableLootbox` soft-skip precedent.
- **Disposition:** CROSS-01b soft-skips (test runs as `pending`); CROSS-01d structural cross-check still covers the rem-byte invariant and CROSS-01a/c exercise the live-state `ticketsOwedPacked` read on the reachable baseline path. The user explicitly accepted this gap as consistent with Phase 274/275/277 precedent. Logged in `deferred-items.md`.

## Issues Encountered
- **`test/fuzz/TicketLifecycle.t.sol` `setUp()` reverts (PRE-EXISTING):** the forge suite's `setUp()` reverts before any fuzz test runs. Verified PRE-EXISTING by stashing Plan 02's comment-only edit and re-running against committed HEAD — `setUp()` reverts identically; a comment change cannot cause an EVM revert. Out of scope per the executor scope boundary, logged in `deferred-items.md`, candidate for a future fixture-maintenance phase.
- **`SurfaceRegression.test.js` 2 pre-existing failing assertions:** the broader `SurfaceRegression` run shows 2 failing checks (LootboxModule SURF-02/03) caused by Phase 277, NOT Phase 278 — confirmed out of scope, not touched.
- **`entropyStep` inventory dispositions:** the remaining `entropyStep` grep hits are all inventory-classified "NO ACTION REQUIRED" — `JackpotCombinedPool.t.sol`'s private `_entropyStep` helper (own implementation, not `EntropyLib.entropyStep`), the comment-only references in `LootboxOpenGas.test.js` / `LootboxEntropyDistribution.test.js` (LootboxModule-scoped), and the `SurfaceRegression.test.js` drift-gate `name` strings + Phase 278 Wave 1 explanatory comments (legitimate references in the v40.0 SURF block). Zero `EntropyLib.entropyStep` live references and zero JS xorshift replicas remain.
- **Contract-commit guard hook:** the repo pre-commit guard blocks `git add` of `contracts/` files unless `CONTRACTS_COMMIT_APPROVED=1` is set. `contracts/test/JackpotBernoulliTester.sol` is in this commit (a test-helper NatSpec-only touch); the user explicitly reviewed and approved the batched test-wave diff, so the env var was set to satisfy the guard — consistent with `feedback_batch_contract_approval.md` and plan 278-01's commit `8a81a87c`.
- **Mocha file-unloader teardown error:** `npx hardhat test` emits a `Cannot find module` error from `mocha/lib/nodejs/file-unloader.js` during teardown — a known mocha quirk that fires AFTER all tests pass (the `N passing` line is printed first). Not a test failure; all suites pass.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Phase 278 is COMPLETE** — both waves landed: Plan 01 contract wave (`8a81a87c`), Plan 02 test wave (`c3baf694`). This was the final plan in the phase.
- **Phase 279 (Whole-BURNIE Floor)** is the next phase — independent of Phases 275-278 content-wise; sequences after 278 for clean linear contract-mutation history.
- **EXC-04 KI envelope** remains a candidate for demotion from `NARROWS` to `NEGATIVE` at v40 close (Phase 280 terminal audit) — the ENT-05 BAF xorshift refactor (Plan 01) plus its post-refactor statistical invariant (Plan 02 TST-CLEAN-01) have now both landed.
- The `c3baf694` test commit is local-only; **not pushed** — future push is a separate user gate per `feedback_manual_review_before_push.md`.

## Self-Check: PASSED

- `test/stat/Ent05KeccakRefactorInvariant.test.js`, `test/integration/CrossSurfaceTicketMixing.test.js` — both present in commit `c3baf694`
- `test/stat/SurfaceRegression.test.js`, `test/stat/JackpotTicketRollSeedUniqueness.test.js`, `test/stat/JackpotTicketRollBernoulliEv.test.js`, `test/fuzz/RollRemainderGas.t.sol`, `test/fuzz/TicketLifecycle.t.sol`, `test/unit/EventSurfaceUnification.test.js`, `contracts/test/JackpotBernoulliTester.sol`, `package.json` — all present in commit `c3baf694`
- Commit `c3baf694` — present in git history
- `278-02-SUMMARY.md`, `deferred-items.md` — present on disk

---
*Phase: 278-jackpotmodule-cleanup-ent-05-baf-xorshift-refactor-wrapper-retirement-jpt-clean*
*Completed: 2026-05-14*
