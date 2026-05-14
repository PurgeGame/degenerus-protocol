---
phase: 277-event-surface-unification-sentinel-retirement-evt-uni
plan: 02
subsystem: lootbox-jackpot-event-surface-tests
tags: [tests, events, sentinel-retirement, regression, source-structural]
status: complete
requirements-completed: [TST-EVT-UNI-01, TST-EVT-UNI-02, TST-EVT-UNI-03, TST-EVT-UNI-04, TST-EVT-UNI-05, TST-EVT-UNI-06]
requires:
  - Plan 277-01 contract wave (commits 02fb7085, 2ef93ec1) — the post-Wave-1 event surface
provides:
  - test/unit/EventSurfaceUnification.test.js — all six TST-EVT-UNI requirements
  - LootboxAutoResolveRegression TST-REG-03/04 retargeted off the retired sentinel
  - LootboxWholeTicket drift-grep + TST-WT-04..07 retargeted to the post-retirement source
  - JackpotTicketRollSilentColdBust JackpotTicketWin assertion updated for roundedUp
  - LootboxConsolation + LootboxAutoResolveSilentColdBust retargeted off the retired sentinel (folded-in beyond original scope)
affects:
  - CI gate for the Phase 277 contract change
tech-stack:
  added: []
  patterns:
    - source-structural assertions (fs.readFileSync + regex match counts + brace/paren-matched extraction)
    - compiled-ABI topic-hash work via ethers Interface / hre.artifacts.readArtifact
key-files:
  created:
    - test/unit/EventSurfaceUnification.test.js
  modified:
    - test/edge/LootboxAutoResolveRegression.test.js
    - test/unit/LootboxWholeTicket.test.js
    - test/unit/JackpotTicketRollSilentColdBust.test.js
    - test/unit/LootboxConsolation.test.js
    - test/unit/LootboxAutoResolveSilentColdBust.test.js
    - package.json
decisions:
  - New test file lives in test/unit/ (on-disk precedent — there is no test/regression/ dir)
  - package.json wires a dedicated test:evt-uni script (the test glob already covers test/unit/*; the explicit script makes registration unambiguous per the plan)
  - TST-WT-05 [05b] baseline-diff (vs 06623edb) replaced with a direct structural assertion — the v38 baseline is three phases stale and the diff-count test was no longer meaningful
  - LootboxConsolation / LootboxAutoResolveSilentColdBust were folded into scope with explicit user approval — 277-01's sentinel retirement invalidated their assertions, so the batched diff was expanded from the plan's original 4 files to 6 test files + package.json
metrics:
  duration: ~1h
  completed: 2026-05-14
---

# Phase 277 Plan 02: Event Surface Unification Test Wave Summary

Landed the Phase 277 test wave — a new `test/unit/EventSurfaceUnification.test.js`
covering all six TST-EVT-UNI requirements via the source-structural + compiled-ABI
precedent, plus targeted updates to **five** precedent test files whose Phase 274/275
assertions Wave 1 invalidated, plus `package.json` script wiring. The batched
6-test-file + `package.json` commit was reviewed and **USER-APPROVED**, committed as
`6fbee850`. Scope expanded from the plan's original 4 files to 6 — `LootboxConsolation`
and `LootboxAutoResolveSilentColdBust` were folded in with explicit user approval
because 277-01's sentinel retirement invalidated their assertions too. Final result:
**107 passing, 0 failing** across the 6 affected files. This is the FINAL plan of
Phase 277.

## What Was Built

### Task 1 — `test/unit/EventSurfaceUnification.test.js` (new, ~570 lines)

Six `describe` blocks, one per requirement, following the Phase 274/275/276
source-structural + tester-direct precedent (no end-to-end resolution fixture —
that gap is RE-DEFERRED, LBX-02). Helpers: brace-matched `extractBody`,
paren-matched `extractCallArgs` + `splitTopLevelArgs` (paren-depth-aware so
`uint32(index)` stays one arg), recursive `collectSolFiles`.

- **TST-EVT-UNI-01** — topic-hash changes. Loads the compiled `DegenerusGameLootboxModule`
  / `DegenerusGameJackpotModule` ABIs via `hre.artifacts.readArtifact`, builds an
  `ethers.Interface`, asserts `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin`
  resolve to the post-Wave-1 field lists (incl. exact indexed-topic counts: 2 / —/ 3),
  asserts each `topicHash` is a well-formed non-zero 32-byte hash, and asserts the OLD
  `LootboxTicketRoll(address,uint48,uint32,bool)` topic has zero `emit` sites across
  all of `contracts/` + is absent from the compiled ABI.
- **TST-EVT-UNI-02** — `LootboxTicketRoll` removal. `/LootboxTicketRoll/` matches zero
  times in `DegenerusGameLootboxModule.sol`, zero in `IDegenerusGameModules.sol`, and
  zero across every `.sol` under `contracts/`.
- **TST-EVT-UNI-03** — sentinel retirement. `/index != type\(uint48\)\.max/` and
  `/type\(uint48\)\.max/` both match zero times in the LootboxModule; auto-resolve
  callers pass `0` as the 3rd positional arg and `false` as the 11th positional arg to
  `_resolveLootboxCommon` (parsed positionally from the call arg list); the unified
  `_queueTickets(player, targetLevel, whole, false)` call appears exactly once with no
  `if (index ...)` branch in the function body.
- **TST-EVT-UNI-04** — manual-path field-consistency. Asserts no contract source
  references `preRollTickets` (D-277-NO-PREROLL-01); proves the off-chain derivation
  `whole = (futureTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)` is arithmetically
  identical to the on-chain collapse across a value sweep; asserts the `LootBoxOpened`
  emit threads `index`→`lootboxIndex` slot, `day`→`day` slot, scaled `futureTickets`,
  `roundedUp`; asserts the `BurnieLootOpen` destructure + emit thread the scaled
  `tickets` and `roundedUp`; asserts the WWXRP-consolation case is gated on
  `emitLootboxEvent && whole == 0` with a same-tx `LootBoxWwxrpReward`.
- **TST-EVT-UNI-05** — auto-resolve silence (EVT-UNI-06 resolved form). The single
  `emit LootBoxOpened` site sits inside an `if (emitLootboxEvent)` gate; neither
  auto-resolve caller emits `LootBoxOpened` directly; the manual cold-bust consolation
  (`wwxrp.mintPrize` + `LootBoxWwxrpReward` with `LOOTBOX_WWXRP_CONSOLATION`) is
  single-site and `emitLootboxEvent`-gated; auto-resolve ticket awards stay observable
  via the unified `_queueTickets` → `TicketsQueued`.
- **TST-EVT-UNI-06** — `JackpotTicketWin.roundedUp`. ABI fragment has a non-indexed
  final `bool roundedUp`; `_jackpotTicketRoll` declares `bool roundedUp = false;`
  before the `(uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)` predicate
  and sets `roundedUp = true;` inside it; the `_jackpotTicketRoll` emit threads the
  captured local; all 3 `emit JackpotTicketWin` sites supply a 7th arg (2 trait-matched
  pass literal `false`, the BAF path threads `roundedUp`); the Jackpot Bernoulli
  predicate mirrors the LootboxModule capture pattern (same math, `>> 200` vs `>> 152`).

### Task 1 — `package.json` wiring

Added a dedicated `test:evt-uni` script running the new file + the three updated
precedent files. (The existing `test` script already globs `test/unit/*.test.js` and
`test/edge/*.test.js`, so the new file is auto-collected by `npm test`; the explicit
script makes the registration unambiguous per the plan's acceptance criterion.)

### Task 2 — three precedent test files retargeted off stale Wave-1 assertions

- **`test/edge/LootboxAutoResolveRegression.test.js`** — TST-REG-03 retargeted:
  `[03a]/[03b]` now assert auto-resolve callers pass `index = 0` + `emitLootboxEvent =
  false` (positionally parsed) instead of the retired `type(uint48).max` sentinel;
  `[03c]` asserts the unified `_queueTickets` call appears **exactly once** (was
  `>= 2`, sentinel-branch duplication); `[03d]` rewritten to assert `LootboxTicketRoll`
  count `0`, the consolation gated on `emitLootboxEvent && whole == 0`, and both
  callers pass `false`; `[03e]` count `1 → 0`; `[03f]` retargeted to the
  `emitLootboxEvent`-gated single-site consolation. TST-REG-04 `[04d]/[04e]` rewritten:
  routing is now by `emitLootboxEvent`, not the `index` value; the `index !=
  type(uint48).max` gate assertion is gone, the sentinel-collision math (`[04e]`) is
  replaced with an `index = 0` assertion. Header + TEST STRATEGY prose updated to
  describe the post-Phase-277 invariants (no stale sentinel/`type(uint48).max` prose).
  Added a paren-depth-aware `extractResolveCommonArgs` helper.
- **`test/unit/LootboxWholeTicket.test.js`** — header + TST-WT-DRIFT + TST-WT-03
  updated: the drift-grep no longer pins the removed `scaledPre` local (the Bernoulli
  now reads `futureTickets` directly into `whole`); no pattern pins `index !=
  type(uint48).max` or `emit LootboxTicketRoll`; TST-WT-04 asserts the unified
  `_queueTickets` callsite appears exactly once (was `>= 2`, `} else {` ordering);
  TST-WT-05 `[05a]` updated for the new `LootBoxOpened(player, index, day, ...,
  roundedUp)` signature, `[05b]` baseline-diff replaced with a direct structural
  assertion that the Bernoulli collapse never reassigns function-scope `futureTickets`,
  `[05c]` updated to the 4-tuple destructure `(uint32 tickets, uint256 burnieReward, ,
  bool roundedUp)` + `roundedUp` emit threading; TST-WT-06 (was `LootboxTicketRoll`
  emit positioning) rewritten as `LootboxTicketRoll`-retired + sentinel-retirement
  proofs; TST-WT-07 (was `LootboxTicketRoll` field-consistency) rewritten as
  field-consistency for the unified path / `LootBoxOpened` emit wiring. Added a brace-
  matched `extractCommonBody` helper.
- **`test/unit/JackpotTicketRollSilentColdBust.test.js`** — header Phase 277 pickup
  note updated to describe the update as DONE; Part (c) `[03a]` extended to assert the
  `bool roundedUp = false;` declaration, the `roundedUp = true;` set inside the
  predicate, and that the `JackpotTicketWin` emit supplies 7 args with `roundedUp` as
  the trailing arg. The silent-cold-bust queue-surface scope is unchanged.

### Task 2 (folded-in) — two additional precedent test files retargeted

`LootboxConsolation.test.js` and `LootboxAutoResolveSilentColdBust.test.js` were
discovered during the Task 3 affected-suite run to assert the retired Wave-1 surface
(the `if (index != type(uint48).max)` sentinel branch, the `} else {` auto-resolve
arm, callers passing `type(uint48).max`, and the duplicated second `_queueTickets`
occurrence). They were initially surfaced to the user as a scope-creep boundary; the
user explicitly approved folding them into this plan's batched diff:

- **`test/unit/LootboxConsolation.test.js`** — `[01c]/[01d]/[02b]` retargeted off the
  retired sentinel branch and `} else {` auto-resolve arm; the `type(uint48).max`
  caller-arg assertion replaced with the post-retirement `index = 0` +
  `emitLootboxEvent = false` shape; the consolation-gating-location assertion
  retargeted to the `if (emitLootboxEvent)` block.
- **`test/unit/LootboxAutoResolveSilentColdBust.test.js`** — `[02a]/[02b]/[03b]/[03c]`
  retargeted: the second `_queueTickets` occurrence (sentinel-branch duplication)
  assertion replaced with the unified single-callsite assertion; the
  `type(uint48).max` sentinel and `emit LootboxTicketRoll` assertions removed/retargeted
  to the post-retirement source structure.

## Test Results (Task 3 — full affected-suite run, post-approval)

**All six batched files — ALL PASS:**

```
npx hardhat test test/unit/EventSurfaceUnification.test.js \
  test/edge/LootboxAutoResolveRegression.test.js \
  test/unit/JackpotTicketRollSilentColdBust.test.js \
  test/unit/LootboxWholeTicket.test.js \
  test/unit/LootboxConsolation.test.js \
  test/unit/LootboxAutoResolveSilentColdBust.test.js
→ 107 passing, 0 failing
```

(`EventSurfaceUnification.test.js` standalone: 26 passing. A harmless
`MODULE_NOT_FOUND` from mocha's file-unloader prints *after* all tests complete when a
relative path is passed on the CLI — it does not affect results and does not occur via
the `npm test` glob. Documented repo quirk, Phase 275/276 precedent.)

**Broader lootbox/jackpot suite — other files spot-checked, clean:**

| File | Result | Notes |
|------|--------|-------|
| `test/edge/LootboxAutoResolveBoundaries.test.js` | 7 passing | clean |
| `test/gas/LootboxOpenGas.test.js` | 0 passing, 3 pending | documented soft-skip (harness-gap precedent); asserts no stale signatures; not a regression |

The two files that initially failed against the retired Wave-1 surface
(`LootboxConsolation`, `LootboxAutoResolveSilentColdBust`) were folded into scope with
user approval and retargeted — see Task 2 (folded-in) above. They now pass and are
part of the 107-passing count.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TST-WT-05 [05b]/[05c] in `LootboxWholeTicket.test.js` asserted the stale Wave-1 source**
- **Found during:** Task 2 verification run.
- **Issue:** `[05c]` pinned the 3-tuple destructure `(uint32 tickets, uint256
  burnieReward, )` — Wave 1 extended `_resolveLootboxCommon` to a 4-tuple ending in
  `bool roundedUp`, so `openBurnieLootBox` now destructures 4 elements. `[05b]` did a
  `grep -c` reassignment-count diff against the v38 baseline `06623edb`; Wave 1 removed
  the `scaledPre` local (the Bernoulli reads `futureTickets` directly), drifting the
  count.
- **Fix:** `[05c]` updated to the 4-tuple destructure pattern + a `roundedUp` emit-
  threading assertion. `[05b]` baseline-diff replaced with a direct structural
  assertion against the current source (the Bernoulli collapse derives the separate
  `whole` local and never reassigns function-scope `futureTickets`; `futureTickets` is
  assigned exactly twice, both scaled values, before the collapse). Both are within
  Task 2's stated scope ("their assertions reflect the post-Wave-1 source"); the plan's
  `<read_first>` flagged only the drift-grep test explicitly, but TST-WT-05 had the
  same staleness root cause.
- **Files modified:** `test/unit/LootboxWholeTicket.test.js`
- **Commit:** `6fbee850`

**2. [Scope expansion - user-approved] LootboxConsolation + LootboxAutoResolveSilentColdBust folded into the batched diff**
- **Found during:** Task 3 affected-suite run.
- **Issue:** Both files asserted the retired Wave-1 surface (the `index != type(uint48).max` sentinel branch, `} else {` auto-resolve arm, `type(uint48).max` caller args, duplicated `_queueTickets`) and failed (8 failures total) — outside the plan's original 4-file `files_modified` scope.
- **Resolution:** Per the plan's Task 3 directive they were surfaced to the user rather than silently fixed. The user explicitly approved folding them into this plan's batched diff. Both retargeted to the post-retirement source and now pass.
- **Files modified:** `test/unit/LootboxConsolation.test.js`, `test/unit/LootboxAutoResolveSilentColdBust.test.js`
- **Commit:** `6fbee850`

## Threat Flags

None. This plan touches only `test/` + `package.json` — no `contracts/` surface is
modified or re-modified (T-277T-03: accept). The new + updated tests are the CI gate
that closes T-277T-01 (stale precedent assertions) and T-277T-02 (test passing against
the old topic hash) — TST-EVT-UNI-01 computes topic hashes from the freshly compiled
post-Wave-1 ABI.

## Known Stubs

None.

## Task Commits

- **Tasks 1 + 2 + 3 (batched)** — `6fbee850` `test(277): event surface unification
  test wave [TST-EVT-UNI-01..06]`. Per project policy
  (`feedback_no_contract_commits.md`, `feedback_batch_contract_approval.md`,
  `feedback_never_preapprove_contracts.md`) all `test/` + `package.json` changes were
  batched into one diff, presented to the user via the Task 3
  `checkpoint:human-verify gate="blocking"`, and committed only after the user's
  explicit approval of the expanded 6-test-file diff. Stages exactly 7 paths: the new
  `test/unit/EventSurfaceUnification.test.js` + 5 modified precedent test files +
  `package.json`. `contracts/ContractAddresses.sol` and `package-lock.json`
  (pre-existing unrelated working-tree changes) were deliberately NOT staged. Nothing
  pushed — push remains a separate user gate per `feedback_manual_review_before_push.md`.

## Checkpoint Status

**Task 3 — `checkpoint:human-verify gate="blocking"` — REACHED and RESOLVED.**
The batched diff was presented; the user reviewed it, approved folding in the two
additional stale precedent files (`LootboxConsolation`,
`LootboxAutoResolveSilentColdBust`), and explicitly approved the expanded 6-test-file +
`package.json` diff. Commit `6fbee850` created post-approval. Nothing pushed.

## Verification

- `npx hardhat test` on the six batched files: **107 passing, 0 failing**.
- `git diff --cached --stat` at commit time showed exactly 7 paths: `package.json` (M),
  `test/edge/LootboxAutoResolveRegression.test.js` (M),
  `test/unit/EventSurfaceUnification.test.js` (new),
  `test/unit/JackpotTicketRollSilentColdBust.test.js` (M),
  `test/unit/LootboxAutoResolveSilentColdBust.test.js` (M),
  `test/unit/LootboxConsolation.test.js` (M),
  `test/unit/LootboxWholeTicket.test.js` (M). No `contracts/` files staged;
  `package-lock.json` left unstaged.
- No test file references a `preRollTickets` event field (asserted by TST-EVT-UNI-04
  `[04a]` and confirmed by `grep`).
- The new file has six `describe` blocks labelled `TST-EVT-UNI-01` … `TST-EVT-UNI-06`.

## Self-Check: PASSED

- `277-02-SUMMARY.md` present at the plan directory path.
- `test/unit/EventSurfaceUnification.test.js` exists (verified on disk; committed in
  `6fbee850`).
- All 5 modified precedent files + `package.json` committed in `6fbee850`.
- Commit `6fbee850` verified present in `git log`.
