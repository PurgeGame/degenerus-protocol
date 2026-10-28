# Phase 2 storage review

> **Historical evidence.** This file records storage-reuse phase 2, committed in `eaf98da75` (2026-10-20; baseline `c4c1effe5`, audit identity `dfe5fb03f`). Its bit positions and slot references are those of that revision: the current pass-credit word uses initialized bit 85, memory-only ID bits 86–117 and retained bit 118 (`CrapsPreferenceLib`). It is not a description of the current
> source. Current layouts and behavior: [Storage reuse](../../../docs/STORAGE-REUSE.md) and
> `scripts/layout/golden/`.

Baseline: Phase 1 feature `c4c1effe5`, audit identity `dfe5fb03f`. Scope follows the
requested order: boon slot 1, pass credits, sDGNRS counts, five-slot jackpot rounds.
No deployment, migration or push is performed. Full release battery remains due.

## Retained boon and pass words

Boon bit 24 lies between the low 24-bit lane and the next field at bit 72. Every
slot-1 production write sets it and every lane mask excludes it. Readers extract
only their fields. Empty-word detection masks it, so an empty retained word does
not cause perpetual expiry sweeps. ID-zero and absent-lane no-op paths still do not
write. Whale slot 0 is unchanged.

Pass bit 117 lies above both balances, the board/initialized fields and the
memory-only ID85..116. All debit, conversion and board masks preserve it. A raw
unmasked ID shift in `_paidDoor` would have moved this bit into newcomer flag192;
the explicit uint32 conversion removes that risk. All other ID readers already
truncate, and Game award construction masks only the saved-board bits.

## sDGNRS queue lifetime

There is at most one open batch and one settling batch, on opposite parities.
An ID has one locator per parity and appends at most once per batch. Nonzero IDs
are uint32, so the queue count is at most uint32.max and its last valid index is
at most uint32.max-1. The two counts occupy formerly unused bytes of slot 7;
updating either preserves the other count, escrow and settlement pointers.

Each entry is replaced as a complete 128-bit lane; its neighbor survives. Old
payload outside the active count is unreachable through a current-batch locator.
A processed prefix is excluded by the committed settlement cursor before any
external call. Finished batches cease to be open/settling; parked claims retain
their separate entry and session word. Terminal manual claims clear only their
lane before payout. No new loop, expiry or capacity guard is added.

## Five-slot jackpot record

The layout check pins every field, both delegate layouts, the 160-byte record and
unchanged roots. `word` had exactly one writer, copying `drawWord` at seal.
`drawWord` is nonzero and frozen before seal; `started` replaces readiness checks.
Both reserve hashes and the table's settlement word therefore retain their exact
inputs in started states. No randomness source, tag, draw order or eligibility
rule changes. Cursor storage moves before the append loop, which has no external
calls; any later revert rolls back the complete append.

Conservative range proof in whole FLIP (integer divisions rounded downward):

- Prize pool P <= 2^128-1; ticket price >= 0.01 ETH; coin unit = 1000.
- Encoded fee F <= (2^18-1)*100; base jackpot fee = 8000.
- Added <= max(150000, P*1000/(0.01 ETH*200))*F/8000 < 2^89.
- Paid units <= 2^64-1, subsidy <= 10x and pool roll <= 100x.
- Total <= ((2^64-1)*F + Added*10)*100 < 2^99; remainder <= total.
- Bankroll is capped at floor((2^24-1)*5/2/300)*300 = 41,943,000 < 2^32.
- The Game draw cursor uses bits 0..201 (ordinal32, eligibility99, offset7,
  position32, remaining32); uint208 retains all bits.

Narrowing therefore preserves reachable values without introducing defensive
reverts. The existing authenticated-call/input checks remain unchanged. Tests
cover cap arithmetic, all cursor bits, resumptions, frozen entropy, field sealing,
reserve payouts, packed counts, stale claims, neighboring lanes and sentinel fees.

## Limits

The ABI tuple and raw queue element keys change for new deployments. External
sim/website/database schema coordination remains a release obligation. Phase 1
native measurements do not measure these Phase 2 changes. The documented gas
savings are Glamsterdam state-creation bounds, not a native runtime claim.
