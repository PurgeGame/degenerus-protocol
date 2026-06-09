---
phase: 381-invariant-fuzz-durable-property-net
plan: 04
subsystem: testing
tags: [foundry, invariant, box-enqueue, whale-01, boxPlayers, lootbox, presale-box, fuzz, etch-overlay, promote]

# Dependency graph
requires:
  - phase: 380-foundation
    provides: green REGRESSION-BASELINE-v62, subject-locked contracts (c4d48008), authoritative storage layout (380-01-LAYOUT-KEY)
  - phase: 381-01
    provides: DeployProtocol invariant scaffolding + the disjoint-actor-band / field-isolated deity-score-bit handler conventions (SolvencyActionHandler exemplar)
  - test/fuzz/PassBoxAutoOpenEnqueue.t.sol
    provides: the WHALE-01 one-shot + the reusable BoxQueueViewer etch overlay (boxPlayersContains / lootboxAmountFor)
provides:
  - test/fuzz/handlers/BoxCreationHandler.sol — the box-creating action handler driving every enqueue site (mint-with-lootbox, whale/lazy/deity pass, coin-presale box) through REAL entrypoints + an openBoxes/advance+VRF drain, tracking every created (index, owner) with per-path non-vacuity ghost counters (excludable falsifiability seams)
  - test/fuzz/invariant/BoxEnqueue.inv.t.sol — the always-on invariant_everyPersistedBoxIsEnqueued (the WHALE-01 invariant as a fuzz property) reusing the one-shot's BoxQueueViewer (extended with presaleBoxBaseFor)
affects: [383-asym, council-sweeps]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Case (b) PROMOTE a one-shot to a durable invariant: REUSE the one-shot's etch overlay (BoxQueueViewer) instead of re-deriving the internal box maps; generalize the single one-shot assertion to every tracked (index, owner) the campaign creates"
    - "Per-path non-vacuity counter DECOUPLED from the tracked-list dedup: a lootbox record ACCUMULATES across deposits at one (index, owner), so the per-path counter bumps per successful creating-call (the path-fired signal) while the invariant's iteration list is deduped to one entry per box record"
    - "Field-isolated actor seeding split: HAS_DEITY_PASS score bit on EVEN actors only (grants the subscribe gate for presale) — a deity HOLDER cannot buy a lazy NOR a fresh deity pass, so the un-seeded ODD actors keep those two surfaces reachable (mirrors SolvencyActionHandler)"
    - "Falsifiability seams excluded from the fuzz campaign via excludeSelector (StdInvariant.FuzzSelector): the debug vm.store hooks prove the invariant CAN fail but must never be part of the always-on action mix (mirrors RngWindowFreeze 381-02)"

key-files:
  created:
    - test/fuzz/handlers/BoxCreationHandler.sol
    - test/fuzz/invariant/BoxEnqueue.inv.t.sol
  modified: []

key-decisions:
  - "Case (b) PROMOTE, do NOT duplicate: BoxEnqueue.inv.t.sol reuses the one-shot's BoxQueueViewer (copied into the invariant file and EXTENDED with presaleBoxBaseFor for the presale-box base) and generalizes its single boxPlayersContains assertion to the full BoxCreationHandler-tracked (index, owner) set across mint-lootbox + whale/lazy/deity pass + presale box"
  - "Persisted-vs-resolved distinction: the invariant checks ONLY entries with base != 0 (lootboxAmountFor OR presaleBoxBaseFor); a base==0 entry is an already-opened box (drained on open) and is correctly skipped — no false positive on resolved boxes (T-381-04-02)"
  - "Per-path counter decoupled from the dedup: the original handler gated the per-path counter on the dedup _track return, so a pass box landing at the SAME (index, owner) as a prior mint-lootbox box counted ZERO — masking real path coverage; fixed to bump the counter on each successful creating-call while _track only dedups the invariant's iteration list"
  - "Actor seeding split EVEN/ODD: the prior session's blanket HAS_DEITY_PASS seed BLOCKED both lazy and fresh-deity-pass buys (a deity holder reverts on both); seed EVEN actors only so the un-seeded ODD actors keep lazy + deity-pass reachable, with whale working for either band"
  - "Falsifiability seams excluded from the campaign: debugSeedUnenqueuedBox / debugClearBox are excludeSelector'd so the always-on invariant only ever sees boxes created through the REAL entrypoints (which always enqueue at c4d48008); the seams exist solely for the focused falsifiability test"

patterns-established:
  - "Promote-a-one-shot-to-an-invariant by reusing its etch viewer + generalizing its one assertion over a handler-tracked set"
  - "Decouple the non-vacuity per-path counter from an accumulating-record dedup so path coverage is measured by creating-calls, not distinct (index, owner) slots"

requirements-completed: [FUZZ-04]

# Metrics
duration: ~50min
completed: 2026-06-08
---

# Phase 381 Plan 04: FUZZ-04 BOX-ENQUEUE Durable Enqueue Invariant Summary

**The WHALE-01 one-shot promoted into the always-on `invariant_everyPersistedBoxIsEnqueued`: across any fuzzed sequence of box-creating actions (mint-with-lootbox, whale/lazy/deity pass, coin-presale box, plus an openBoxes/advance+VRF drain) every persisted box (`lootboxEth`/`presaleBoxEth` base != 0) for a tracked (index, owner) is present in `boxPlayers[index]` until opened — reusing the one-shot's BoxQueueViewer etch overlay (extended with a presale base reader), distinguishing persisted-but-unenqueued (a BUG) from already-resolved (base==0), green over 256 runs / 32768 calls / 0 reverts, non-vacuous across 4 distinct creation paths and proven falsifiable.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-06-08
- **Completed:** 2026-06-08
- **Tasks:** 2 (Task 1 — verify/refine the BoxCreationHandler that pre-existed from a crashed session against live c4d48008 source; Task 2 — author BoxEnqueue.inv.t.sol)
- **Files modified:** 2 (both new/untracked — BoxCreationHandler.sol from the prior session [refined this session], BoxEnqueue.inv.t.sol new this session)

## Accomplishments
- `test/fuzz/handlers/BoxCreationHandler.sol` drives EVERY box-creating entrypoint through REAL calls — `purchase` with a non-zero lootboxAmt (mint-with-lootbox), `purchaseWhaleBundle` / `purchaseLazyPass` / `purchaseDeityPass` (the pass-bundled 10% lootbox), `buyPresaleBox` (the credit-gated coin-presale box) — plus an `openSome` action (`openBoxes` + advance + VRF-fulfill) that drains boxes to base==0 over the campaign. Each successful creating-call bumps a per-path ghost counter (non-vacuity) and records the (index, owner) into a deduped `created` list the invariant iterates. Actor band `0x70000` (disjoint from WhaleHandler 0xB0000 / V61AfkingSpendHandler 0xAF000); HAS_DEITY_PASS field-isolated-seeded on EVEN actors only so the ODD un-seeded actors keep the lazy-pass and deity-pass surfaces reachable.
- `test/fuzz/invariant/BoxEnqueue.inv.t.sol` reuses the WHALE-01 one-shot's `BoxQueueViewer` etch overlay (copied into the invariant file and EXTENDED with `presaleBoxBaseFor(index, who)` for the presale-box applied-ETH base) and generalizes the one-shot's single assertion: for each tracked (index, owner), if its lootbox amount OR presale base != 0 (persisted, not yet opened), `assertTrue(boxPlayersContains(index, owner))`; base==0 entries (opened/resolved) are skipped. The viewer is etched once, all reads batched under it, real code restored at the end.
- `invariant_everyPersistedBoxIsEnqueued` GREEN over the default [invariant] profile (256 runs / 32768 calls / 0 reverts); the metrics table shows all six surfaces firing (mintWithLootbox / buyWhaleBundle / buyLazyPass / buyDeityPass / buyPresaleBox / openSome ~5400+ calls each, 0 reverts).
- Non-vacuity: `afterInvariant` gates the campaign on `pathsExercised >= 2` AND `totalBoxesCreated > 0`; the focused `test_boxesCreatedAcrossPaths_nonVacuous` deterministically creates boxes across 4 distinct paths (mintLootbox 5 / whale 5 / deity 1 / presale 5 = 16 boxes, tracked into 5 deduped (index, owner) entries).
- Falsifiability: `test_invariantIsFalsifiable_persistedButUnenqueued` seeds the exact WHALE-01 bug shape — a persisted `lootboxEth` amount (base != 0) NOT pushed into `boxPlayers[index]` (via the `debugSeedUnenqueuedBox` seam) — and asserts the invariant's underlying condition (base != 0 AND boxPlayersContains == false) registers the break; clearing the slot returns it to green. The seam is `excludeSelector`'d so it never enters the fuzz action mix.
- The WHALE-01 one-shot (`PassBoxAutoOpenEnqueue`) remains GREEN (no regression from reusing/extending its viewer).
- ZERO contracts/*.sol mutation (`git status --short -- contracts/` empty; `git diff c4d48008 -- contracts/` empty).

## Task Commits

1. **RED — `aab37985`** `test(381-04): add RED falsifiability hook for BoxEnqueue invariant` — authored BoxEnqueue.inv.t.sol referencing handler seams (`debugSeedUnenqueuedBox` / `debugClearBox`) not yet exposed → compile fails → RED (mirrors the 381-02 RED-hook idiom).
2. **GREEN — `85295b43`** `test(381-04): FUZZ-04 BOX-ENQUEUE durable enqueue invariant GREEN` — refined BoxCreationHandler (EVEN/ODD deity-seed split, per-path counter decoupled from the dedup, the two falsifiability seams) + the invariant authored green with the seams excluded from the campaign. All 3 tests pass.

## Files Created/Modified
- `test/fuzz/handlers/BoxCreationHandler.sol` (created prior session, refined this session) — the box-creating action handler: 6 actions through real entrypoints, per-path ghost counters, deduped tracked (index, owner) list, EVEN/ODD HAS_DEITY_PASS seeding split, `debugSeedUnenqueuedBox` / `debugClearBox` falsifiability seams + `_lootboxEthSlot` helper.
- `test/fuzz/invariant/BoxEnqueue.inv.t.sol` (created, ~245 lines) — the BoxQueueViewer (reused from the one-shot, +presaleBoxBaseFor) + `invariant_everyPersistedBoxIsEnqueued` + `afterInvariant` non-vacuity gate + `test_boxesCreatedAcrossPaths_nonVacuous` + `test_invariantIsFalsifiable_persistedButUnenqueued`; `excludeSelector` for the two debug seams.

## Decisions Made
- **Promote (case b), not duplicate:** the one-shot's `BoxQueueViewer` is reused (copied + extended with `presaleBoxBaseFor`) and its single `boxPlayersContains` assertion generalized to the full tracked set across all box-creating paths; the one-shot file stays as the named WHALE-01 regression.
- **Persisted-vs-resolved:** only base != 0 entries are checked (lootbox amount OR presale base); base==0 = an opened/resolved box, correctly excluded (no false positive — T-381-04-02).
- **Per-path counter decoupled from the dedup (bug fixed in the inherited handler):** lootbox records accumulate at one (index, owner), so gating the counter on `_track`'s first-insert masked real path coverage (a pass box at a mint-lootbox-occupied slot counted zero). The counter now bumps per successful creating-call; `_track` only dedups the invariant's iteration list.
- **Actor seeding split EVEN/ODD (bug fixed in the inherited handler):** the prior blanket HAS_DEITY_PASS seed blocked both lazy and fresh-deity-pass buys (a deity holder reverts on both). Seeding EVEN actors only keeps lazy + deity-pass reachable on the un-seeded ODD actors; whale works for either band.
- **Falsifiability seams excluded:** `debugSeedUnenqueuedBox` / `debugClearBox` are `excludeSelector`'d (StdInvariant.FuzzSelector) so the always-on invariant only ever sees boxes created through the REAL enqueueing entrypoints — the campaign reflects genuine contract behaviour, not a seeded bug shape (mirrors RngWindowFreeze 381-02).

## Deviations from Plan

Plan executed as written, with TWO auto-fixed correctness bugs in the inherited (crashed-session) handler — both Rule 1 (the handler did not actually exercise the pass paths it claimed):

### Auto-fixed Issues

**1. [Rule 1 - Bug] Per-path non-vacuity counter masked by the accumulating-record dedup**
- **Found during:** Task 1 (verifying the handler exercised ≥2 paths)
- **Issue:** each action gated its per-path counter on `if (_track(idx, currentActor)) boxesCreated_X++`. A lootbox record accumulates across deposits at one (index, owner), so when a pass box landed at the SAME (index, owner) as a prior mint-lootbox box, `_track` returned false and the pass counter stayed 0 — the non-vacuity gate saw only 1 path despite multiple paths firing.
- **Fix:** bump the per-path counter unconditionally on each successful creating-call; call `_track` independently (it still dedups the invariant's iteration list). Updated `_track`'s doc to reflect the decoupling.
- **Files modified:** test/fuzz/handlers/BoxCreationHandler.sol
- **Commit:** 85295b43

**2. [Rule 1 - Bug] Blanket HAS_DEITY_PASS seed blocked the lazy-pass AND fresh-deity-pass surfaces**
- **Found during:** Task 1 (diagnosing 0 boxes on the pass paths)
- **Issue:** the constructor seeded the HAS_DEITY_PASS score bit on ALL actors; a deity-pass HOLDER cannot buy a lazy pass NOR a fresh deity pass (both revert `E()`), so the lazy and deity-pass surfaces created 0 boxes.
- **Fix:** seed the bit on EVEN actors only (the subscribe gate the presale path needs) — the un-seeded ODD actors keep lazy + deity-pass reachable; whale works for either band. Mirrors the established SolvencyActionHandler split.
- **Files modified:** test/fuzz/handlers/BoxCreationHandler.sol
- **Commit:** 85295b43

Plus a hardening add (Rule 2): `excludeSelector` the two falsifiability seams so the fuzzer cannot seed an un-enqueued box into the always-on campaign (which would either spuriously trip the invariant or mask the real action mix). Mirrors RngWindowFreeze (381-02).

## Issues Encountered
- `forge inspect ... storageLayout` initially returned empty (cached artifact without the layout); resolved by `FOUNDRY_EXTRA_OUTPUT='["storageLayout"]' forge build --force contracts/DegenerusGame.sol`. Confirmed the handler's hardcoded slots against the authoritative layout: mintPacked_ @9, presaleBoxCredit @17, lootboxRngPacked @36, lootboxEth @15 (used by the falsifiability seam). `boxPlayers` is accessed SYMBOLICALLY via the etched viewer (`boxPlayers[index]`), not by raw slot, so its slot number is not load-bearing.

## User Setup Required
None.

## Verification
- `forge test --match-contract "BoxEnqueue"` — 3 passed / 0 failed: `invariant_everyPersistedBoxIsEnqueued` (256 runs / 32768 calls / 0 reverts), `test_boxesCreatedAcrossPaths_nonVacuous`, `test_invariantIsFalsifiable_persistedButUnenqueued`.
- All six box-creating/opening surfaces fire in the campaign (metrics table, ~5400+ calls each, 0 reverts); the two debug seams are absent from the campaign (excluded).
- Non-vacuity: 4 distinct creation paths / 16 boxes deterministically; `afterInvariant` gates `pathsExercised >= 2` && `totalBoxesCreated > 0`.
- `git diff c4d48008 -- contracts/` EMPTY; `git status --short -- contracts/` EMPTY.
- The WHALE-01 one-shot `PassBoxAutoOpenEnqueue` remains GREEN (no regression from the viewer reuse/extension).

## Self-Check: PASSED
- FOUND: test/fuzz/handlers/BoxCreationHandler.sol
- FOUND: test/fuzz/invariant/BoxEnqueue.inv.t.sol
- FOUND: commit aab37985 (RED)
- FOUND: commit 85295b43 (GREEN)
