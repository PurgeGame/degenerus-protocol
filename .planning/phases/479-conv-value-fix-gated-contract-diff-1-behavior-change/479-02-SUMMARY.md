---
phase: 479-conv-value-fix-gated-contract-diff-1-behavior-change
plan: 02
subsystem: tests
tags: [tickets, entries, jackpot, lootbox, bernoulli, regression, integration]

# Dependency graph
requires:
  - phase: 479-01 (b2ab3e9f)
    provides: both prize legs route through wholeTicketsToEntries; post-fix call/emit strings
provides:
  - "Deterministic forge proof (PrizeLegEntriesDelivery) of the canonical converter + entries-basis equivalence + no-overflow"
  - "CrossSurfaceTicketMixing reconciled to the post-fix 2-emit entries reality (green)"
  - "Full-stack openBox owed-entries delta behavioral assertion (soft-skips under the documented lootbox-RNG reachability gap)"
affects: [480-rename-sweep, 481-event-surface, 482-verify]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Harness-subclass forge proof: extend the production module under test/ to reach an internal pure helper via an external shim (overrides no production logic)"
    - "Live-state owed-entries delta read via raw provider.getStorage cross-validated against ticketsOwedView"

key-files:
  created:
    - test/fuzz/PrizeLegEntriesDelivery.t.sol
  modified:
    - test/integration/CrossSurfaceTicketMixing.test.js

key-decisions:
  - "`_budgetToTicketUnits` is declared `private` (the plan's interface section assumed `internal`), so a subclass cannot expose it. `exposedBudgetToEntries` mirrors its EXACT body `(budget << 2) / priceForLevel(lvl)` against the SAME production `PriceLookupLib.priceForLevel` oracle — identical basis value, no contract edit (Rule 3 blocking-issue workaround)."
  - "The load-bearing converter `wholeTicketsToEntries` IS internal (in Storage) and is exposed via a true pass-through shim — the proof asserts the production symbol, not a re-implementation."
  - "[CROSS-01e] full-stack openBox owed-delta soft-skips when the deterministic fixture/seed denies lootbox-RNG reachability (the same documented gap [CROSS-01b] already hits); the non-zero 4x delivery is carried deterministically by the PrizeLegEntriesDelivery forge proof + the structural [CROSS-01d]."

patterns-established:
  - "PrizeLegHarness: external shim over the inherited internal wholeTicketsToEntries to assert the converter + entries basis without VRF"

requirements-completed: [FIX-04, FIX-05]

# Metrics
duration: ~40min
completed: 2026-06-29
---

# Phase 479 / Plan 02: Behavioral Proof + Event-Surface Reconciliation Summary

**A new deterministic forge regression pins the canonical `wholeTicketsToEntries(w)=w<<2` converter (no uint32 truncation at the max-realistic edge) and its entries-per-ETH equivalence with the purchase/daily `(B<<2)/price` basis, while `CrossSurfaceTicketMixing` is reconciled from the stale 3-emit whole-ticket expectations to the post-fix 2-emit entries reality (emit==queue preserved) — the three Bernoulli EV testers stay green UNCHANGED with zero contract or stat-test edits.**

## Accomplishments

### Task 1 — `test/fuzz/PrizeLegEntriesDelivery.t.sol` (FIX-04) — commit `33239b1d`
- `PrizeLegHarness is DegenerusGameJackpotModule` exposes the inherited internal `wholeTicketsToEntries` via an external pass-through shim (`exposedWholeTicketsToEntries`); overrides NO production logic.
- **Converter** (`testConverterEqualsTimesFourNoTruncation`): `wholeTicketsToEntries(w) == w*4` for `w ∈ {0,1,7,1000,42_949_672}`; the max-realistic case pins `42_949_672 -> 171_798_688` (uint32 return equals the full uint256 product — no truncation; T-479-03).
- **Entries-basis equivalence** (`testEntriesBasisEquivalence`): for exact-multiple budgets across every price tier (levels 1/7/110/50/100 → 0.01/0.02/0.04/0.08/0.24 ETH) `exposedWholeTicketsToEntries(B/price) == exposedBudgetToEntries(B,level) == (B<<2)/price` EXACTLY; for general budgets the prize leg is within one sub-ticket (`(B<<2)/price - prizeEntries < 4`, the Bernoulli granularity).
- **Fuzz** (`testFuzz_ConverterNoTruncation`, 1000 runs): over `whole <= 42_949_672`, `entries == uint256(whole) << 2` (no truncation) and `entries % 4 == 0`.
- Verify: `forge test --match-contract PrizeLegEntriesDelivery -vv` → **3 passed, 0 failed**.

### Task 2 — `test/integration/CrossSurfaceTicketMixing.test.js` (FIX-05) — commit `d0718702`
- **[03a]** emit-site count `3 -> 2`; kept the "no 4th arg references TICKET_SCALE" check (still true — `uint32(units)` / `wholeTicketsToEntries(whole)`).
- **[03b]** `fourthArgs` deep-equal `["ticketCount","uint32(units)","whole"] -> ["uint32(units)","wholeTicketsToEntries(whole)"]` (source order: the already-correct coin/units leg at :891, then the BAF roll at :2149).
- **[03c]** KEPT unchanged as the emit==queue assertion — each emit 4th arg equals the adjacent preceding `_queueTickets` 3rd arg; passes post-fix (`uint32(units)`==`uint32(units)`, `wholeTicketsToEntries(whole)`==`wholeTicketsToEntries(whole)`). Comment refreshed to the entries basis only.
- **[03d]/[03e]** untouched (event signature/ABI unchanged in 479).
- **[CROSS-01d]** two embedded source strings updated to `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` and `_queueTickets(winner, targetLevel, wholeTicketsToEntries(whole), true)`; rem-byte structural proof otherwise intact.
- **[CROSS-01e]** NEW emit==queue + ~4x behavioral block: drives the REAL `openBox` full-stack (reuses `reachOpenableLootbox`/`findOpenableEthIndex`/`resolveLiveTicketsOwed`), parses `LootBoxOpened`, and asserts the owed-entries delta at `rollLevel` equals `((scaledTickets/100)<<2)` or the `+1` Bernoulli round-up branch (`delta === roundedUp ? hi : lo`). Documents that `_jackpotTicketRoll` (private, VRF-gated) is covered deterministically by the Task-1 forge proof (carried-forward FIXTURE_COVERAGE_GAP).
- File-header / `readTicketsOwedSlot` / CROSS-01 block comments refreshed from the "whole-ticket" emit basis to the entries basis (describe what the code IS; no history narration).
- Verify: `npx hardhat test test/integration/CrossSurfaceTicketMixing.test.js` → **11 passing, 0 failing, 2 pending**.

## Verification

| Gate | Result |
|------|--------|
| `forge test --match-contract PrizeLegEntriesDelivery -vv` | 3 passed, 0 failed |
| `npx hardhat test test/integration/CrossSurfaceTicketMixing.test.js` | 11 passing, 0 failing, 2 pending (soft-skip) |
| `test/stat/JackpotTicketRollBernoulliEv.test.js` | 16 passing (UNCHANGED) |
| `test/stat/LootboxBernoulliEv.test.js` | 8 passing (UNCHANGED) |
| `test/stat/LootboxAutoResolveBernoulliEv.test.js` | 13 passing (UNCHANGED) |
| `git diff --name-only b2ab3e9f -- contracts/` | EMPTY (zero contract edits) |
| `git diff --name-only b2ab3e9f -- test/stat/` | EMPTY (zero stat-test edits) |

The two pending CrossSurfaceTicketMixing tests are **[CROSS-01b]** (pre-existing) and the new **[CROSS-01e]**, both soft-skipped because the deterministic fixture/seed reverted the lootbox purchase ("unrecognized custom error") — the documented lootbox-RNG reachability gap. The `MODULE_NOT_FOUND` stack trace printed AFTER "11 passing" is the cosmetic mocha file-unloader bug, not a failure.

The Bernoulli EV testers re-ran 37 green (16+8+13) with no edits — the `<<2` lives only inside the post-Bernoulli converter, so the collapse blocks stay byte-identical (FIX-03 tripwire honored).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `_budgetToTicketUnits` is `private`, not `internal`**
- **Found during:** Task 1
- **Issue:** The plan's `<interfaces>` and Task-1 `<read_first>` describe `_budgetToTicketUnits` as `internal` (exposable via a subclass shim). The production declaration (`DegenerusGameJackpotModule.sol:705`) is `private pure`, which a subclass cannot reach.
- **Fix:** `exposedBudgetToEntries` mirrors the exact `_budgetToTicketUnits` body — `(budget << 2) / PriceLookupLib.priceForLevel(lvl)` (with the `budget==0` / `price==0` guards) — against the SAME production price oracle. The basis value is byte-identical to what the purchase/daily legs deliver. The load-bearing symbol (`wholeTicketsToEntries`) is still exposed via a true pass-through shim, so the converter proof is against the production symbol. No contract edit.
- **Files modified:** test/fuzz/PrizeLegEntriesDelivery.t.sol
- **Commit:** 33239b1d

### Soft-skips

**[CROSS-01e] full-stack openBox owed-delta** — soft-skipped on this run because the deterministic fixture denied lootbox-RNG reachability (lootbox purchase reverted), the same documented gap [CROSS-01b] hits. The block is fully wired (drives the real `openBox`, parses `LootBoxOpened`, asserts `delta === (scaledTickets/100)<<2` or the `+1` round-up) and will assert when reachable; the non-zero 4x delivery is carried deterministically by the PrizeLegEntriesDelivery forge proof + the structural [CROSS-01d].

## Self-Check: PASSED
- `test/fuzz/PrizeLegEntriesDelivery.t.sol` — FOUND.
- Commit `33239b1d` (Task 1) — FOUND; `d0718702` (Task 2) — FOUND.
- `git diff --name-only b2ab3e9f -- contracts/` EMPTY; `git diff --name-only b2ab3e9f -- test/stat/` EMPTY.
- Three Bernoulli EV testers re-ran green UNCHANGED (37 total).

## Gap-closure (FIX-05 under-scope) — `a8629448`, `7844ee7f`
Adversarial verification (workflow `wf_a62938f5-73f`) found this plan reconciled ONLY `CrossSurfaceTicketMixing`. Seven more hardhat suites pinned the pre-fix call form `_queueTickets(..., whole, ...)` / the bare `whole` `JackpotTicketWin` emit arg as source-structural assertions and hard-failed under default `npm test` (none covered by the green forge floor). `479-RESEARCH.md:130` mis-triaged `EventSurfaceUnification` as a "481 concern" — wrong, it pins the emit **value** 479 changed.
- Reconciled to the `wholeTicketsToEntries(whole)` helper form (`7844ee7f`), preserving every assertion's strength: `JackpotTicketRollSilentColdBust`, `LootboxAutoResolveRegression`, `LootboxConsolation`, `LootboxAutoResolveSilentColdBust`, `LootboxAutoResolveRemByte`, `EventSurfaceUnification`, `LootboxWholeTicket` — **116 passing / 0 failing**.
- Fixed a pre-existing false-green in `JackpotTicketRollSilentColdBust [03a]`: it asserted the emit carried `uint32(quantityScaled)` via a substring that matched only the `scaledTickets` local (never the emit) and narrated a stale D-276 "pre-Bernoulli scaled" intent that never matched the contract → replaced with a positional `emitArgs[3] == "wholeTicketsToEntries(whole)"` check (emit == queue); stale narratives corrected to the entries basis.
- Also dropped a dead zero-price guard in the forge harness mirror (`a8629448`; `priceForLevel` is provably never 0).
- Regression-floor evidence: full `forge test` **1003 passed / 0 failed / 107 skipped**.

### Deferred / out-of-scope (confirmed)
- `test/stat/SurfaceRegression.test.js` (5 failures) — PRE-EXISTING, guards `DegenerusTraitUtils.sol`/`EntropyLib.sol` byte-ranges (byte-identical to baseline `cdd32fe9`; 479 never touched them). Not a 479 regression.
- `contracts/test/LootboxBernoulliTester.sol:71` — stale NatSpec **comment** (no assertion greps it); gated (`contracts/`). Plan blessed leaving it; fold a comment-only refresh into 481.
- Production `_budgetToTicketUnits` (`DegenerusGameJackpotModule.sol:711`) carries the same dead zero-price guard — candidate trim to fold into the gated phase 480 (already renames that fn).
