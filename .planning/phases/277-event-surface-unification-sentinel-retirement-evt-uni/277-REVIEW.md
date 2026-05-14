---
phase: 277-event-surface-unification-sentinel-retirement-evt-uni
reviewed: 2026-05-14T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - contracts/modules/DegenerusGameLootboxModule.sol
  - contracts/modules/DegenerusGameJackpotModule.sol
  - contracts/interfaces/IDegenerusGameModules.sol
  - test/unit/EventSurfaceUnification.test.js
  - test/edge/LootboxAutoResolveRegression.test.js
  - test/unit/LootboxWholeTicket.test.js
  - test/unit/JackpotTicketRollSilentColdBust.test.js
  - test/unit/LootboxConsolation.test.js
  - test/unit/LootboxAutoResolveSilentColdBust.test.js
findings:
  blocker: 1
  warning: 4
  info: 2
  total: 7
status: resolved
resolution:
  commit: f7a6fccd
  resolved: [CR-01, WR-01, WR-02]
  deferred: [WR-03, WR-04]
  info_only: [IN-01, IN-02]
---

# Phase 277: Code Review Report

**Reviewed:** 2026-05-14
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 277 (commit `02fb7085`) deletes the `LootboxTicketRoll` event, adds a trailing
non-indexed `bool roundedUp` to `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`,
fixes the `LootBoxOpened` index/day mislabel, retires the `index != type(uint48).max`
behavior-gating sentinel in `_resolveLootboxCommon`, and extracts two private helpers
(`_lootboxBoonBudget`, `_accumulateLootboxRolls`) to clear a viaIR stack-too-deep error.

The helper extraction is behavior-equivalent, the `roundedUp` threading is correct on
all paths, the event ABI changes are internally consistent (events live only in the
module contracts, not the interface, so no interface drift), and `_jackpotTicketRoll`
threads the captured Bernoulli outcome correctly.

**However, the sentinel retirement is NOT behavior-equivalent.** The old manual/auto
split was gated by `index != type(uint48).max`; `openBurnieLootBox` passed a *real*
index and therefore took the manual branch — which paid the WWXRP cold-bust
consolation. Post-277 the consolation is gated by `emitLootboxEvent`, and
`openBurnieLootBox` passes `emitLootboxEvent = false`. The BURNIE-lootbox cold-bust
consolation payout has been silently dropped. The phase brief explicitly asked for
behavior-equivalence of the sentinel retirement; this is a regression. The submitted
test changes assert the new (silent) behavior as if it were always intended and never
flag the divergence — so the test suite actively masks the regression rather than
catching it.

## Blocker Issues

### CR-01: `openBurnieLootBox` cold-bust silently loses the WWXRP consolation payout

**File:** `contracts/modules/DegenerusGameLootboxModule.sol:652-667` and `1067-1076`

**Issue:**
Pre-277, the manual-vs-auto behavior split inside `_resolveLootboxCommon` was gated by
`if (index != type(uint48).max)`. `openBurnieLootBox` passes a *real* `index`
(`lootboxBurnie[index][player]` storage index), so it took the **manual branch**: on a
ticket-path cold-bust (`futureTickets != 0` but Bernoulli collapse yields `whole == 0`)
it paid `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` and emitted
`LootBoxWwxrpReward`.

Post-277 the consolation is gated by `if (emitLootboxEvent && whole == 0)`.
`openBurnieLootBox` calls `_resolveLootboxCommon` with `emitLootboxEvent = false`
(11th positional arg — confirmed at L660-664: `seed, false, false, false, false, true, 0, 0`).
Therefore the BURNIE-lootbox cold-bust **no longer pays the consolation and no longer
emits `LootBoxWwxrpReward`** — it is now fully silent, identical to the auto-resolve
paths.

This path is reachable: `openBurnieLootBox` -> `_resolveLootboxCommon` ->
`_accumulateLootboxRolls` -> `_resolveLootboxRoll` can return a non-zero scaled
`ticketsOut`, and the Bernoulli collapse at L1057-1062 can produce `whole == 0` for any
scaled count in `(0, 100)`.

The phase brief states the sentinel retirement should be behavior-equivalent ("the
manual cold-bust WWXRP consolation moved under the `emitLootboxEvent` gate"). Moving it
under `emitLootboxEvent` is only equivalent if every pre-277 manual caller also passed
`emitLootboxEvent = true`. `openBurnieLootBox` did not — it passed `emitLootboxEvent =
false` while still being on the manual branch via a real `index`. The old code coupled
two concerns into the sentinel (manual-branch routing AND event emission); the new code
collapsed them onto `emitLootboxEvent` alone, which is the wrong axis for
`openBurnieLootBox`.

**Fix:** Decide explicitly whether the BURNIE-lootbox cold-bust consolation is meant to
survive. Two options:

1. If the consolation must still be paid for BURNIE lootboxes (behavior-equivalence),
   gate it on a dedicated flag rather than reusing `emitLootboxEvent`. E.g. add a
   `bool payConsolation` param to `_resolveLootboxCommon` (true for `openLootBox` AND
   `openBurnieLootBox`, false for the two auto-resolve callers), and gate the
   consolation on `if (payConsolation && whole == 0)`:
   ```solidity
   _queueTickets(player, targetLevel, whole, false);
   if (payConsolation && whole == 0) {
       wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
       emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
   }
   ```
2. If dropping the BURNIE-lootbox consolation is an intentional design change, it must
   be called out as a deliberate behavior change in the phase plan/summary (not folded
   silently into a "sentinel retirement" refactor), and a regression test must assert
   the *old* behavior is gone *on purpose*.

Either way, this requires explicit design sign-off — it is currently an undocumented,
untested behavior regression shipped under a "behavior-equivalent refactor" banner.

## Warnings

### WR-01: Test suite asserts the regression as intended behavior, masking CR-01

**File:** `test/unit/LootboxConsolation.test.js:18-21`, `test/edge/LootboxAutoResolveRegression.test.js:280-344`, `test/unit/LootboxAutoResolveSilentColdBust.test.js:110-142`

**Issue:**
`LootboxConsolation.test.js` header comment states "The two auto-resolve callers
(`resolveLootboxDirect`, `resolveRedemptionLootbox`) and `openBurnieLootBox` all pass
`emitLootboxEvent = false`, so cold-bust is silent for them." This bundles
`openBurnieLootBox` in with the auto-resolve callers as if its silent cold-bust were
always the intended behavior. It is not — pre-277 `openBurnieLootBox` paid the
consolation. No test in the submitted set asserts the *pre-277* behavior to detect the
change, and `LootboxAutoResolveRegression.test.js` TST-REG-03 (a "status-quo
preservation" test) was edited to bless the new silent behavior rather than flag the
divergence. The tests therefore actively conceal CR-01 instead of catching it.

**Fix:** After CR-01 is resolved, add an explicit test that pins the
`openBurnieLootBox` cold-bust outcome (consolation paid, or deliberately not paid) and
documents the decision. Remove the comment language that conflates `openBurnieLootBox`
with the auto-resolve callers.

### WR-02: Phase 277 tests are entirely source-grep / ABI-shape structural — zero end-to-end coverage of the changed resolution path

**File:** `test/unit/EventSurfaceUnification.test.js:18-24`, `test/unit/LootboxWholeTicket.test.js` (TST-WT-04..07), `test/unit/LootboxAutoResolveSilentColdBust.test.js` (Source-level proof block)

**Issue:**
Every Phase 277 assertion that touches the *behavior* of `_resolveLootboxCommon` is a
`fs.readFileSync` + regex match or a compiled-ABI shape check. The actual restructured
control flow (unconditional `_queueTickets` + `emitLootboxEvent`-gated consolation +
`emitLootboxEvent`-gated `LootBoxOpened` with the new arg order) is never exercised
against a deployed contract with a real lootbox fixture. `EventSurfaceUnification.test.js`
explicitly documents this as a "fixture-coverage gap (LBX-02, RE-DEFERRED)". The
consequence is concrete: CR-01 (a real behavior regression) is invisible to a test
suite that only greps source structure — a structural test cannot tell that
`emitLootboxEvent` is the *wrong gate* for the `openBurnieLootBox` consolation, because
the source structure is internally self-consistent.

**Fix:** Add at least one integration fixture that drives `openLootBox` and
`openBurnieLootBox` through to a Bernoulli cold-bust and asserts the emitted events
(`LootBoxOpened` field values incl. the fixed `lootboxIndex`/`day` slots and
`roundedUp`; `LootBoxWwxrpReward` presence/absence). The structural greps are fine as a
drift detector but cannot stand in for behavior coverage of a path this phase
restructured.

### WR-03: `_lootboxBoonBudget(amount)` is recomputed instead of cached

**File:** `contracts/modules/DegenerusGameLootboxModule.sol:1013` and `1029`

**Issue:**
The helper extraction replaced a single `boonBudget` local with two separate calls to
`_lootboxBoonBudget(amount)` — once inside the `mainAmount` block (L1013) and again as
the `_rollLootboxBoons` argument (L1029). The function is `private pure` and
deterministic, so the result is identical, but it is now executed twice per resolution
(two multiplications + two branch comparisons). Pre-277 it was computed once. Per
project guidance on not wasting gas (`feedback_no_dead_guards.md`), cache the value:
```solidity
uint256 boonBudget = _lootboxBoonBudget(amount);
uint256 mainAmount = amount - boonBudget;
...
_rollLootboxBoons(player, day, amount, boonBudget, seed, allowWhalePass, allowLazyPass);
```
This keeps the helper (which exists to satisfy the stack-too-deep constraint) while
restoring the single-evaluation behavior.

### WR-04: `BurnieLootOpen.index` truncates the `uint48` lootbox index to `uint32`

**File:** `contracts/modules/DegenerusGameLootboxModule.sol:671`

**Issue:**
`openBurnieLootBox` receives `uint48 index` and emits `BurnieLootOpen` with
`uint32(index)`. The `BurnieLootOpen` event still declares `uint32 indexed index`
(unchanged by Phase 277). Phase 277 explicitly fixed exactly this class of problem on
`LootBoxOpened` (widened the index slot to `uint48 indexed lootboxIndex`) but left
`BurnieLootOpen` with the narrower `uint32` slot and a silent truncating cast. If lootbox
indices ever exceed `type(uint32).max`, the emitted `BurnieLootOpen.index` will be wrong
(and could alias a different lootbox). This is pre-existing, but Phase 277 touched this
exact emit site (added `roundedUp`) and restructured the sibling event for precisely
this reason — leaving the inconsistency in place is a missed correctness fix.

**Fix:** Widen `BurnieLootOpen.index` to `uint48 indexed index` and emit `index`
directly without the cast, mirroring the `LootBoxOpened` fix. If `uint48` lootbox
indices are provably unreachable, document that bound at the event declaration instead
of relying on a silent cast.

## Info

### IN-01: `_resolveLootboxCommon` `index` param is now dead weight on the auto-resolve paths

**File:** `contracts/modules/DegenerusGameLootboxModule.sol:971`, `696`, `732`

**Issue:**
After the sentinel retirement, `index` is used only as the `lootboxIndex` value on the
`emitLootboxEvent`-gated `LootBoxOpened` emit. Auto-resolve callers pass `index = 0` and
`emitLootboxEvent = false`, so the param is genuinely unused on those two call paths.
This is acceptable (a shared signature), but a one-line NatSpec note that `index` is
ignored when `emitLootboxEvent == false` would prevent future readers from assuming it
still gates anything. The NatSpec was updated for `index` but does not state this
coupling explicitly.

### IN-02: `JackpotTicketWin` ABI break is unavoidable but worth a consumer note

**File:** `contracts/modules/DegenerusGameJackpotModule.sol:90-97`

**Issue:**
Adding the trailing non-indexed `bool roundedUp` changes the `JackpotTicketWin`
topic-0 hash, breaking any existing indexer subscription. The commit message documents
this under EVT-UNI-08 / D-40N-EVT-BREAK-01 (pre-launch, accepted). No code change
needed — flagged only so the indexer-rebuild requirement is captured in the review
trail alongside the `LootBoxOpened` / `BurnieLootOpen` breaks.

---

## Resolution

Addressed in commit `f7a6fccd` (user-approved gap-closure batch).

- **CR-01 — RESOLVED.** Added a dedicated `bool payColdBustConsolation` param to
  `_resolveLootboxCommon`; the cold-bust consolation is now gated on
  `payColdBustConsolation && whole == 0`. The manual callers (`openLootBox`,
  `openBurnieLootBox`) pass `true` — `openBurnieLootBox` pays the consolation again.
  The auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`) pass
  `false` and stay silent on cold-bust, per D-277-AR-SILENT-01 (user-confirmed: the
  consolation fires on the manual paths only, on final `whole == 0`).
- **WR-01 — RESOLVED.** `LootboxConsolation.test.js` retargeted: it no longer conflates
  `openBurnieLootBox` with the auto-resolve callers, and now asserts the BURNIE-lootbox
  cold-bust pays. New `TST-WX-04` behavioral block pins all four callers' outcomes.
- **WR-02 — ADDRESSED.** Added `LootboxBernoulliTester.coldBustConsolationFires`, a
  deployed-contract mirror of the production gate decision, driven with each caller's
  real flag values (`TST-WX-04`, incl. a drift detector tying the tester to the
  production gate string). A pure end-to-end `openBurnieLootBox` fixture remains
  infeasible with the current harness (VRF-rigging to force the seed slice) — the
  documented LBX-02 fixture-coverage gap; the mirror test is the closest the harness
  supports and exercises exactly the `openBurnieLootBox` cold-bust case CR-01 dropped.
- **WR-03 — DEFERRED** (user decision): `_lootboxBoonBudget` double-compute left as-is.
- **WR-04 — DEFERRED** (user decision): `BurnieLootOpen.index` `uint32` truncation left
  as-is.
- **IN-01 / IN-02 — info only**, no change required.

Additional user-approved event-surface trims landed in the same commit (out of scope of
the original review, folded in on user request): `bonusBurnie` removed from
`LootBoxOpened` + `_resolveLootboxCommon` returns; `LootBoxWwxrpReward` event deleted
(payouts retained, observable via the WWXRP ERC-20 `Transfer` event); `allowWhalePass` /
`allowLazyPass` collapsed into a single `allowPasses` param.

---

_Reviewed: 2026-05-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
