---
phase: 479-conv-value-fix-gated-contract-diff-1-behavior-change
plan: 01
subsystem: contracts
tags: [tickets, entries, jackpot, lootbox, bernoulli, conversion, natspec]

# Dependency graph
requires:
  - phase: v75.0 grounding (6047e3e2)
    provides: ticket/entry unit map + bug-site classification (the two under-issue prize legs)
provides:
  - "wholeTicketsToEntries(uint32)=w<<2 canonical whole->entries converter in DegenerusGameStorage"
  - "Both prize legs (Jackpot BAF roll :2144, Lootbox roll :1383) queue entries via the converter — full value restored (~4x pre-fix)"
  - "Jackpot JackpotTicketWin emit==queue on the entries basis"
  - "CONV-02 convention NatSpec: owed is ENTRIES (price/4), 4 entries per whole ticket"
affects: [479-02, 480-rename-sweep, 481-event-surface, 482-verify]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single canonical whole->entries converter both prize modules route through (anti-recurrence for open-coded conversion)"

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol

key-decisions:
  - "Helper kept (not inlined <<2): it is the designed canonical converter per the v75 grounding rename map; internal pure => optimizer-inlined, gas-neutral, layout byte-stable; distinct primitive from _budgetToTicketUnits (whole-count input vs budget input)"
  - "Identifier renames (_queueTickets->_queueEntries, ticketsOwedPacked->entriesOwedPacked, locals) deferred to Phase 480; NatSpec in 479 is the one-phase bridge keeping current names accurate"
  - "LootBoxOpened still emits scaledTickets — emit-unit normalization to entries deferred to the event-surface phase (481); [03c] integration emit==queue assertion reads only the Jackpot file, so this is safe"
  - "The <<2 lives ONLY inside wholeTicketsToEntries (post-Bernoulli); Bernoulli collapse blocks byte-identical so the three EV testers stay green unchanged"

patterns-established:
  - "wholeTicketsToEntries: convert a post-Bernoulli whole-ticket count to entries at the single canonical site before queueing into ticketsOwedPacked"

requirements-completed: [CONV-01, CONV-02, FIX-01, FIX-02, FIX-03, FIX-05]

# Metrics
duration: ~35min
completed: 2026-06-29
---

# Phase 479 / Plan 01: CONV + Value-Fix Summary

**Both prize legs now route their post-Bernoulli whole-ticket count through one canonical `wholeTicketsToEntries(w)=w<<2` before queueing into the entries-denominated `ticketsOwedPacked` sink — restoring full (≈4×) value delivery while the Bernoulli round-up stays byte-identical.**

## Accomplishments
- Added `internal pure wholeTicketsToEntries(uint32 wholeTickets) returns (uint32) => wholeTickets << 2` to `DegenerusGameStorage` (reachable by both modules via inheritance; no storage slot; layout byte-stable).
- FIX-01 (Jackpot `_jackpotTicketRoll`, :2144): `_queueTickets(winner, targetLevel, wholeTicketsToEntries(whole), true)`; emit 4th arg (:2152) also routed through the helper → emit==queue on the entries basis.
- FIX-02 (Lootbox roll resolve, :1383): `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)` — single site also covers the decimator-recirc path (`resolveLootboxDirect`); `DegenerusGameDecimatorModule.sol` untouched (no double-apply).
- CONV-02 NatSpec (entries basis) at the helper, `ticketsOwedPacked` (:522), `_queueTickets`, and `_queueTicketsScaled`; the two now-false Jackpot call-site comments (:2146-2148 and :889-890) corrected to entries — comment-only, the `uint32(units)` logic line at :888 unchanged.
- FIX-03 tripwire honored: the `<<2` is applied only to the post-Bernoulli `whole`, never inside the Bernoulli expression; the collapse blocks (Jackpot :2133-2142 / Lootbox :1375-1380) are byte-identical.

## Task Commits

This plan ships ONE batched `.sol` diff behind the contract-commit gate (not per-task atomic, per the plan's autonomous:false checkpoint design):

1. **Tasks 1+2: helper + both prize-leg queue/emit routing + CONV-02 NatSpec + call-site comment corrections** — `b2ab3e9f` (fix)
2. **Task 3: USER approval gate** — USER reviewed `git diff contracts/` and typed "approved"; committed as `b2ab3e9f` (3 files, +36/−17).

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` — `wholeTicketsToEntries` pure helper + CONV-02 NatSpec at the helper, `ticketsOwedPacked`, `_queueTickets`, `_queueTicketsScaled`.
- `contracts/modules/DegenerusGameJackpotModule.sol` — BAF roll queue + `JackpotTicketWin` emit routed through the helper (emit==queue); :2146-2148 + :889-890 comments corrected to entries; `uint32(units)` logic line untouched.
- `contracts/modules/DegenerusGameLootboxModule.sol` — roll-resolve queue routed through the helper; `LootBoxOpened` emit + :1374 comment unchanged.

## Verification
- `npx hardhat compile` — green (pre-existing unrelated mutability warning in `DegenerusGameMintStreakUtils.sol`).
- Bernoulli EV tripwires GREEN UNCHANGED: `JackpotTicketRollBernoulliEv` 16 passing, `LootboxBernoulliEv` 8 passing, `LootboxAutoResolveBernoulliEv` 13 passing (37 total). (A harness teardown unloader stack trace prints after `N passing` — cosmetic, not a failure.)
- `forge test --match-contract JackpotSingleCallCorrectness` — 10/10 passing (already-correct leg unbroken).
- Source asserts: both prize legs route via `wholeTicketsToEntries(whole)`; no bare-`whole` `_queueTickets` form remains; `git diff --stat contracts/` shows only the three expected files; no contract comment names a phase/plan ID; Bernoulli collapse lines not in the diff.

## Deferrals (carry-forward)
- **LootBoxOpened emit unit** still emits `scaledTickets` (scaled-whole), NOT entries. Normalizing it to entries is the event-surface job of **Phase 481** (EVT-01). No 479 test asserts emit==queue on the LootBoxOpened path. The existing :1374 comment already documents what the code IS; no new contract comment added.
- **Identifier renames** (`_queueTickets`→`_queueEntries`, `ticketsOwedPacked`→`entriesOwedPacked`, bug-site locals, `WHALE_*_TICKETS_PER_LEVEL` constants) deferred to **Phase 480** (rename sweep, gated diff #2).

## Self-Check: PASSED
- All other `_queueTickets`/`_queueTicketsScaled` call sites (10) re-verified against the v75 grounding map: all already pass entries. The under-issue is exactly the two prize legs — the fix is not missing any sibling site.
- Wave-2 behavioral proof (FIX-04 forge regression + CrossSurfaceTicketMixing reconciliation) lands in 479-02.

## Notes for Next Plan (479-02)
- Post-fix call/emit strings to assert against: Jackpot `_queueTickets(winner, targetLevel, wholeTicketsToEntries(whole), true)` + emit 4th arg `wholeTicketsToEntries(whole)`; Lootbox `_queueTickets(player, rollLevel, wholeTicketsToEntries(whole), false)`.
- `[CROSS-01d]` embedded source strings must be updated to the `wholeTicketsToEntries(whole)` helper form.
- `[03a]` 3→2 emit sites; `[03b]` fourthArgs → `["uint32(units)","wholeTicketsToEntries(whole)"]`; `[03c]` stays green as the emit==queue assertion.
