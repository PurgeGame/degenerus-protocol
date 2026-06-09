---
phase: 380-foundation-test-fix-green-baseline
plan: 02
subsystem: testing
tags: [forge, hardhat, event-schema, lootbox, deity-pass, gameover, c4d48008, test-fix]

# Dependency graph
requires:
  - phase: 380-foundation-test-fix-green-baseline (Plan 01)
    provides: "authoritative c4d48008 storage-layout key + carried-red discipline (a red whose code path is byte-identical baseline->subject is documented, not forced green)"
provides:
  - "LootBoxOpened event-schema-delta suites refreshed to the current 7-arg signature (no `day` arg) — 3 forge fuzz files + 5 JS source-parser suites"
  - "deity-refund tests realigned to the c4d48008 deityPassPricePaid + min(pricePaid, 20e18) model — removed deityPassPurchasedCount / deityPassPaidTotal references"
  - "root-caused + deferred the gameover-VRF drive harness drift (fixed-2-step never latches gameOver() at c4d48008) -> .planning/.../deferred-items.md for the 380-04 gate"
affects: [380-04 full-suite green gate, council sweeps 382-386 (need a green test net)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Schema-delta refresh: derive the canonical type-list + positional order from the FROZEN contract event/emit-site, then realign every topic-hash string, struct decoder, and arg-count assertion to it (tests follow the contract, never the reverse)."
    - "Same-commit collateral drift: the 4cb9ccbf 'lootbox event day cleanup' dropped `day` from BOTH the LootBoxOpened event (8->7 args) AND the _resolveLootboxCommon helper (12->11 args); a schema-delta plan must realign both the event AND the helper-arg-position assertions."

key-files:
  created:
    - ".planning/phases/380-foundation-test-fix-green-baseline/deferred-items.md"
  modified:
    - "test/fuzz/V55FreezeDeterminism.t.sol"
    - "test/fuzz/V55RevertFreeEvCap.t.sol"
    - "test/fuzz/V56FreezeSolvency.t.sol"
    - "test/unit/EventSurfaceUnification.test.js"
    - "test/unit/LootboxWholeBurnieFloor.test.js"
    - "test/unit/LootboxWholeTicket.test.js"
    - "test/unit/LootboxAutoResolveSilentColdBust.test.js"
    - "test/edge/LootboxAutoResolveRegression.test.js"
    - "test/edge/GameOver.test.js"
    - "test/unit/SecurityEconHardening.test.js"

key-decisions:
  - "Re-expressed the box.day freeze assertions via the lastOpenedDay storage observable (the event no longer carries `day`); the freeze property is unchanged."
  - "The _resolveLootboxCommon 12->11 arg-position drift is the SAME 4cb9ccbf cleanup the plan names — realigned in-scope (index=2nd, emitLootboxEvent=7th, payColdBustConsolation=8th positional)."
  - "Did NOT broadly force GameOver.test.js / SecurityEconHardening.test.js green: their dynamic gameover-VRF reds are a pre-existing, suite-wide harness-drive drift (not deity-schema), deferred to the 380-04 full-suite gate per the SCOPE BOUNDARY rule and Plan 380-01's carried-red precedent."

patterns-established:
  - "Carried/deferred harness drift: a red with identical baseline counts + byte-frozen contract code path is documented (deferred-items.md) with a root-caused fix recipe, not forced green inside an out-of-scope plan."

requirements-completed: [FOUND-02, FOUND-03]

# Metrics
duration: 22min
completed: 2026-06-07
---

# Phase 380 Plan 02: Event-Schema-Delta & Deity Storage-Collapse Test Refresh Summary

**Refreshed the LootBoxOpened 7-arg event-schema (day-dropped, commit 4cb9ccbf) across 3 forge fuzz + 5 JS source-parser suites — plus the same-commit _resolveLootboxCommon 12->11 arg-position collateral — and realigned the deity-refund tests to the c4d48008 deityPassPricePaid + min(pricePaid, 20e18) model; module tree byte-frozen at bbffe99e.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-06-07T18:45:00Z
- **Completed:** 2026-06-07T19:08:00Z
- **Tasks:** 2
- **Files modified:** 10 (+1 deferred-items.md created)

## Accomplishments
- **FOUND-02 (event-schema-delta):** dropped the removed `day` arg from every LootBoxOpened topic-hash string, Box struct decoder, and arg-count assertion. Forge canonical sig -> `LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)`. JS ABI/emit assertions -> 7 positional args (amount=3rd .. roundedUp=7th). The LIVE freeze/solvency suite **V56FreezeSolvency passes 7/7** (it decodes the real 7-arg event at runtime — the schema fix is functionally validated, not just compile-only).
- **FOUND-02 collateral (same 4cb9ccbf commit):** the cleanup also threaded `day` out of the `_resolveLootboxCommon` helper (12->11 args). Realigned the auto-resolve arg-position assertions in 3 JS suites (index=2nd, emitLootboxEvent=7th, payColdBustConsolation=8th). All 5 named JS suites green.
- **FOUND-03 (deity storage-collapse):** rewrote the SecurityEconHardening FIX-05 describe + comments and the GameOver header + level-0 describe to the c4d48008 model: `min(deityPassPricePaid[owner], 20e18)` per owner at early gameover (levels 0-9), FIFO + budget-capped. Removed every reference to the deleted `deityPassPurchasedCount` / `deityPassPaidTotal` fields and the old "refund clears the count" behavior. Grep-clean in both files.
- **Contracts byte-untouched** throughout: tree hash stayed `bbffe99e...` (== the required frozen `c4d48008` subject); ContractAddresses.sol restored after each hardhat run (landmine guard).

## Task Commits

Each task was committed atomically:

1. **Task 1: Refresh the LootBoxOpened event-schema-delta tests (FOUND-02)** - `ce8c25fa` (test) - 8 files
2. **Task 2: Update the v60 whale/pass deity storage-collapse tests (FOUND-03)** - `4cc3becf` (test) - 2 files

_Plan metadata commit follows this SUMMARY._

## Files Created/Modified
- `test/fuzz/V55FreezeDeterminism.t.sol` - 7-arg sig + Box (day dropped) + decoder; box.day asserts -> lastOpenedDay observable (all decoding tests already vm.skip'd; compile-only impact)
- `test/fuzz/V55RevertFreeEvCap.t.sol` - 7-arg sig + Box + decoder (decoding tests vm.skip'd; compile-only)
- `test/fuzz/V56FreezeSolvency.t.sol` - 7-arg sig + Box + decoder + the two-block determinism box.day assertion -> lastOpenedDay (LIVE suite, 7/7 pass)
- `test/unit/EventSurfaceUnification.test.js` - [01a] ABI 7-input list (day removed); [03c] _resolveLootboxCommon 11-arg positions; [04c] emit 7-arg positions
- `test/unit/LootboxWholeBurnieFloor.test.js` - [02a] emit 7 positional args, burnieAmount = 6th
- `test/unit/LootboxWholeTicket.test.js` - [05a]/[07b] emit regexes -> 7-arg (day dropped)
- `test/unit/LootboxAutoResolveSilentColdBust.test.js` - [02b] _resolveLootboxCommon 11-arg positions
- `test/edge/LootboxAutoResolveRegression.test.js` - [03a]/[03b]/[03d]/[04e] _resolveLootboxCommon 11-arg positions (index=2nd, emit=7th, consolation=8th)
- `test/edge/GameOver.test.js` - header + level-0 describe -> deityPassPricePaid + min(pricePaid, 20e) model
- `test/unit/SecurityEconHardening.test.js` - FIX-05 describe + comments -> deityPassPricePaid model; removed-field references dropped
- `.planning/phases/380-foundation-test-fix-green-baseline/deferred-items.md` - the gameover-VRF harness-drive drift, root-caused + fix recipe, for the 380-04 gate

## Decisions Made
- **box.day -> lastOpenedDay observable.** The dropped `day` event field can no longer be read from the log; the freeze-determinism property ("the box resolved against the frozen stamp day") is re-expressed via the `_lastOpenedDayOf(afk) == stampDay` storage observable the tests already track. Equivalent assertion, no coverage lost.
- **_resolveLootboxCommon realignment is in-scope.** Commit 4cb9ccbf ("lootbox event day cleanup", named in the plan objective) dropped `day` from BOTH the events AND the resolve helpers in one change; the helper-arg-position assertions are collateral of the exact drift FOUND-02 targets, so realigning them (12->11 args) is within the plan's intent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Realigned the _resolveLootboxCommon helper arg-position assertions (12->11 args)**
- **Found during:** Task 1 (FOUND-02 JS suites)
- **Issue:** The plan's `read_first` enumerated the LootBoxOpened event drift but not the `_resolveLootboxCommon` helper drift. The SAME commit 4cb9ccbf threaded `day` out of the helper (12->11 args), so the auto-resolve callers' `args[2]/args[7]/args[8]` index/emit/consolation assertions in EventSurfaceUnification [03c], LootboxAutoResolveSilentColdBust [02b], and LootboxAutoResolveRegression [03a/03b/03d/04e] mismatched the frozen 11-arg helper and failed.
- **Fix:** Realigned to the frozen positions — index=args[1] (2nd), emitLootboxEvent=args[6] (7th), payColdBustConsolation=args[7] (8th); arg count 12->11; comments updated to cite 4cb9ccbf.
- **Files modified:** test/unit/EventSurfaceUnification.test.js, test/unit/LootboxAutoResolveSilentColdBust.test.js, test/edge/LootboxAutoResolveRegression.test.js
- **Verification:** EventSurfaceUnification 26/26, LootboxAutoResolveSilentColdBust 8/8, LootboxAutoResolveRegression 15/15 (+1 pre-existing pending) — all green.
- **Committed in:** ce8c25fa (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking, in-scope same-commit collateral).
**Impact on plan:** Necessary to meet Task 1's "5 named JS suites pass" AC. Same-commit drift, squarely within FOUND-02's named scope (4cb9ccbf). No contract change. No scope creep beyond the event-cleanup commit.

## Issues Encountered

**Pre-existing gameover-VRF harness drive drift (DEFERRED, out of FOUND-03 scope).** The two FOUND-03 deity-refund tests share a `triggerGameOverAtLevel0(game, caller, mockVRF)` helper that drives a FIXED two-step VRF sequence (advanceGame -> fulfill -> advanceGame). At `c4d48008` that is insufficient — a throwaway probe showed the gameover latch needs MORE advance+fulfill cycles (advance#2 leaves `rngLocked=true`; `gameOver()` only flips true after ~2 further advance+fulfill iterations). The failure is suite-wide (GameOver.test.js 9 pass / 7 fail; SecurityEconHardening.test.js 23 pass / 16 fail) and spans many tests this plan never touched (FIX-01..04, FIX-06/07, pre/post-game timeout, advanceGame-path).
- **Proven pre-existing:** the pass/fail counts are byte-identical with vs without this plan's edits (GameOver 9/7 == 9/7; SEH 23/16 == 23/16). This plan's edits to those two files are comment / describe-title / field-name only and change no executable assertion's outcome.
- **Why not fixed here:** out of FOUND-03's named scope (deity field-name/semantics realignment, which IS complete). The harness-drive repair is a suite-wide, test-only fix (a fulfill-loop) that turns ~23 untouched tests green — exactly the broad out-of-named-scope harness repair the SCOPE BOUNDARY rule reserves for the dedicated full-suite gate. Mirrors Plan 380-01's carried-red discipline (byte-frozen contract code path -> documented, not forced green).
- **Routed to:** `deferred-items.md` (DEF-380-02-01) with the full probe trace + a copy-paste fix recipe for Plan 380-04. No contract change implicated.

## Contract-change-needed (NOT applied)
None. Neither requirement needs a contract change. The deity-refund SEMANTICS asserted are the already-shipped c4d48008 behavior; the event signature is the already-shipped 4cb9ccbf cleanup. The gameover-harness drift is a test-harness issue against a byte-frozen contract path. Per the hard constraint, the EXPECTED behavior was derived from the frozen source (event decl/emit site at LootboxModule:63/1189; refund `min(deityPassPricePaid[owner], 20e18)` at GameOverModule:111-115; `deityPassPricePaid[buyer]=uint96(totalPrice)` at WhaleModule:605) and the TESTS were updated to match — the contracts tree stayed `bbffe99e` throughout.

## Known Stubs
None. No stub/placeholder data introduced — these are test-assertion realignments to the frozen source.

## Threat Flags
None. Test-only changes; no `contracts/*.sol` modification, no new attack surface, no production behavior change (per the plan's `<threat_model>`).

## Next Phase Readiness
- **FOUND-02 + FOUND-03 satisfied for their named scope.** The event-schema-delta net is green (forge LIVE suite 7/7 + 5 JS suites); the deity storage-collapse framing matches the frozen source (grep-clean).
- **One precise hand-off to Plan 380-04:** the gameover-VRF drive harness fulfill-loop fix (DEF-380-02-01) — turning the GameOver/SecurityEconHardening dynamic gameover tests green belongs to the full-suite gate, with the root cause + recipe already documented.

## Self-Check: PASSED

- Created files exist: `380-02-SUMMARY.md`, `deferred-items.md` — both FOUND.
- Task commits exist: `ce8c25fa` (Task 1), `4cc3becf` (Task 2), `2c7342c3` (docs) — all FOUND.
- Frozen-tree assertion: `HEAD:contracts` == `bbffe99ede11adadcabcc9b81295566176575d47` — OK (byte-untouched throughout).
- Verification gates: forge schema suites 7 passed / 0 failed (V56FreezeSolvency LIVE 7/7); 5 JS suites green; no 8-arg LootBoxOpened sig in test/; no removed deity fields in the 2 files; ContractAddresses.sol clean after every hardhat run.

---
*Phase: 380-foundation-test-fix-green-baseline*
*Completed: 2026-06-07*
