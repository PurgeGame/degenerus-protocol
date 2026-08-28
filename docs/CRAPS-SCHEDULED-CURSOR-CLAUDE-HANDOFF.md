# Scheduled Craps cursor and integration repairs: Contract Claude handoff

> Status: implementation brief approved in discussion on 2026-08-27.
>
> Primary goal: replace the latest-slot-only Craps keeper with a monotonic, persistent scheduled
> cursor so every protocol day and every one of its seven windows is eventually opened, armed,
> and completely resolved—even across partial batches, day rollover, and multi-day protocol stalls.
>
> Explicit product decisions:
>
> - **There are no skipped Craps days.** A historical day missed during a Game/VRF stall remains
>   owed work and must be replayed and resolved. Its prepaid/pass seats do not expire, move, or
>   receive refunds.
> - **Terminal game-over Craps is out of scope.** Once the main game is terminal, no effort is
>   required to finish Craps fields or manufacture later Craps entropy.

<agent_identity>

You are Contract Claude, the senior Solidity engineer responsible for implementing and
adversarially verifying the scheduled Craps liveness repair in the Degenerus Protocol. Treat the
following as simultaneous requirements:

- no scheduled slot can be forgotten;
- no player may choose or amend an input after learning the entropy that settles it;
- replayed historical days preserve the intended Craps economics and accounting;
- every keeper transaction remains gas-bounded;
- storage layout and EIP-170 deployability remain valid; and
- the main Game cannot be made dependent on an unbounded catch-up loop.

Work from the live repository and current dirty working tree. Existing changes belong to other
work. Do not reset, restore, discard, or broadly rewrite them. The contracts are authoritative for
current behavior; this brief is authoritative for the product decisions above. When an older doc
conflicts—most notably the missed-reservation expiry rule—update that doc rather than preserving
the conflict silently.

</agent_identity>

<domain_knowledge>

## Relevant implementation

- [`contracts/CrapsBattle.sol`](../contracts/CrapsBattle.sol) owns scheduled-day opening,
  `_slotIndex`, `_bonusCursor`, `_dayTickets`, day action, progressive funding, arming, and
  settlement.
- [`contracts/modules/GameAfkingModule.sol`](../contracts/modules/GameAfkingModule.sol) owns the
  rewarded `mineFlip()` router and currently implements `_crapsKeep` by calculating only
  `openSlot - 1`.
- [`contracts/modules/DegenerusGameAdvanceModule.sol`](../contracts/modules/DegenerusGameAdvanceModule.sol)
  backfills daily RNG words after a stall and calls `CrapsBattle.openBonusDay()` only for the
  current wall day.
- [`contracts/modules/DegenerusGameLootboxModule.sol`](../contracts/modules/DegenerusGameLootboxModule.sol)
  delivers rolled Craps passes using a bounded external call.
- [`contracts/LootboxCraps.sol`](../contracts/LootboxCraps.sol) reads the pinned Game storage
  layout for daily words and lootbox-index words.
- [`contracts/Coinflip.sol`](../contracts/Coinflip.sol) receives Craps payouts through
  `creditFlip`/`creditFlipBatch`.
- [`test/fuzz/CrapsProtocolWiring.t.sol`](../test/fuzz/CrapsProtocolWiring.t.sol) and
  [`test/fuzz/CrapsKeeperBudgetGas.t.sol`](../test/fuzz/CrapsKeeperBudgetGas.t.sol) exercise the
  production keeper route.
- [`docs/CRAPS-BATTLE-SYSTEM-OVERVIEW.md`](CRAPS-BATTLE-SYSTEM-OVERVIEW.md) is the player/system
  overview that must describe the final lifecycle accurately.
- [`docs/LOOTBOX-CRAPS-DAY-PASS-SPEC.md`](LOOTBOX-CRAPS-DAY-PASS-SPEC.md) currently says a missed
  reservation expires. That requirement is superseded by this brief and must be revised.

## Current scheduled-slot model

A scheduled slot is:

```text
slot = day * 8 + period + 1
period = 0..6
```

Remainder zero (`day * 8`) is the day-ticket storage slot and is not a battle. The seven other
slots are time-ordered windows.

There are already two useful pieces of state:

- `_slotIndex[slot]`: zero while unarmed, otherwise the lootbox RNG index plus one; and
- `_bonusCursor[slot]`: the last contiguous seat completely resolved in that field.

What is missing is the first coordinate: a persistent pointer naming the oldest scheduled slot
the protocol still owes. The effective keeper position should be:

```text
(scheduledKeeperSlot, _bonusCursor[scheduledKeeperSlot])
```

## Confirmed failure in the current keeper

`GameAfkingModule._crapsKeep` derives the clock's currently open slot and touches only
`openSlot - 1`. At rollover, that calculation lands on the next day's reserved remainder-zero
slot. A prior event or partially settled window then falls permanently behind the protocol's
rewarded keeper. Permissionless direct calls remain possible, but the protocol keeper no longer
provides the liveness guarantee claimed by the overview.

The Craps leg also runs only on a `mineFlip()` call that opened no boxes. A persistent cursor fixes
forgetting, but not necessarily starvation under an infinite stream of box work. Do not conflate
those properties: preserve the current shared gas ceiling, and state precisely what scheduling
guarantee the final router provides.

## RNG constraint for historical days

The daily word draws public window terms. It is not automatically safe to reuse an already-public
daily/backfill word as settlement entropy when a house/vault seat, vault board, standing snapshot,
or any other participant-controlled input is added afterward.

A replayed day's fields must be fully materialized and frozen before their settlement word can be
known. Prefer the existing future lootbox-VRF lane. It is acceptable for all seven already-frozen
windows of one replayed day to bind the same future, currently unworded index because settlement
already domain-separates the shared word by window, owner, and bet. Prove that the chosen index has
no word and that no entry/amendment/funding choice remains open before committing it.

Do not use `blockhash`, `block.prevrandao`, timestamps, caller data, or a hash of entropy already
known while any input remains mutable.

## Baseline evidence

Before this repair, the current dirty tree produced:

- 306 passing Craps unit/oracle/economic/progressive/shooter tests;
- 22 passing targeted protocol-wiring, pass-delivery, and keeper-gas tests;
- approximately 9.37M gas for the measured hard Craps keeper sample;
- approximately 11.74M gas for the measured level-100 phase-end `advanceGame(0)` path;
- `CrapsBattle` runtime size of 23,059 bytes (1,517 bytes below EIP-170); and
- `DegenerusGame` runtime size of 24,487 bytes (only 89 bytes below EIP-170).

Treat those as regression evidence, not permanent constants. Avoid adding main-Game runtime code;
its remaining size margin is effectively exhausted.

</domain_knowledge>

<task_definition>

## Deliverables

Implement, test, and document all four repairs below:

1. the monotonic scheduled-slot keeper cursor;
2. replay and resolution of every historical day missed during a protocol stall;
3. lossless lootbox pass delivery; and
4. saturation of the 44-bit winnings tiebreak.

Do not implement terminal-game Craps recovery. Do not redesign the pure Craps engine, progressive
schedule, shooter boost, or custom-battle economics.

## 1. Move scheduled liveness into `CrapsBattle`

Add append-only Craps storage for a persistent `scheduledKeeperSlot` and any explicit day/open or
replay markers genuinely required. Update the storage-layout golden file and oracle. Do not insert
state between existing fields.

The core invariant is:

> Every scheduled slot strictly below `scheduledKeeperSlot` is either completely finalized or is
> the reserved remainder-zero separator. No playable scheduled slot is skipped for being old,
> unopened, empty at first inspection, unarmed, waiting for RNG, or partially settled.

`CrapsBattle` should expose one narrow permissionless keeper entry point, conceptually:

```solidity
function keepScheduled(uint64 gasBudget)
    external
    returns (bool progressed, uint64 slot);
```

The exact name and return shape may differ if a compact enum gives tests/indexers a materially
better result. The table—not `GameAfkingModule`—must own slot arithmetic, historical-day state,
completion detection, and cursor advancement.

For the cursor's current slot, the state machine must be:

1. Advance across a remainder-zero separator without treating it as a battle.
2. If its day has not yet been materialized, materialize the owed day safely; never mark it
   expired or jump to a newer wall day.
3. If the window is not closed yet, stop without advancing.
4. If it is closed and unarmed, freeze its complete field, bind safe unknown settlement entropy,
   and leave the cursor on that slot.
5. If armed but the word is not ready, stop without advancing.
6. If ready, call the existing gas-budgeted settlement path.
7. If only part of the field settled, retain the same slot and its existing seat cursor.
8. Advance to the next scheduled slot only after detecting complete finalization.

Advancement must also work when an external caller already armed or completely resolved the slot.
No externally helpful action may wedge the cursor.

Retain `armBonusWindow` and `resolveSlot` as permissionless public surfaces unless removing one is
proven necessary. Custom battles are sparse and are not part of the sequential daily cursor; leave
them permissionless or design a separate explicit queue, but never try to reach them by incrementing
the scheduled cursor.

## 2. Replace the main-game `open - 1` coupling

Replace `ICrapsKeeper`'s three-call probe (`bonusCursorOf`, `armBonusWindow`, `resolveSlot`) with the
single table-owned keeper operation. Delete `_crapsOpenSlot` and duplicate schedule constants from
`GameAfkingModule` if they have no remaining production purpose. The Game must not independently
calculate which Craps slot is owed.

Preserve these existing router properties:

- Craps remains the final `mineFlip()` category.
- Box work and Craps settlement cannot stack past the calibrated transaction ceiling.
- A zero settlement budget may still perform cheap clock/lifecycle work if doing so remains within
  the existing envelope.
- The flat Craps keeper bounty is paid only for real, one-time progress—not for polling an armed
  field whose word is absent or a finalized cursor already observed.
- Cursor-only progress across a bounded run of separator/state slots must commit rather than be
  reverted as `NoWork`.

Bound all cheap scanning by a slot count, a gas floor, or both. A 120-day recovery must take
multiple bounded transactions, not create one unbounded loop. At most one flat keeper bounty is
paid per `mineFlip()` call regardless of how many cheap slots were advanced.

## 3. Replay every missed protocol day

Generalize today's one-shot opening logic into an internal day materializer that can safely open an
owed historical day. `openBonusDay()` must remain a bounded, nonreverting Game hook. It may record
the newest owed/current day and let the cursor catch up rather than opening an unbounded range
inside `advanceGame()`.

Requirements:

- A call for current day `D` makes every protocol day between the prior owed high-water mark and
  `D` owed. Backfilled days are not invisible merely because the Game did not call Craps once per
  historical day.
- Days are materialized and finalized oldest-first so `_dayStaked`/`_highStaked` feed later
  seven-day budgets in chronological order.
- A historical day uses its genuine `rngWordByDay[day]` to draw terms.
- Existing prepaid/pass day-ticket holders join all seven windows exactly once.
- Progressive funding, main/high budgets, day action, events, house/vault policy, and ticket counts
  execute exactly once per owed day. If current house/vault funding or board state cannot safely
  reproduce a historical seat, make and document the smallest deterministic policy that prevents
  post-reveal choice; do not silently let a controlled body opt in after seeing its dice.
- Historical windows are closed immediately. They accept no new direct entry, donation, or
  amendment.
- Their settlement entropy is unknown when the final field and every participating input become
  immutable.
- All seven windows may share one safe future word, but their existing per-slot domain separation
  must remain intact.
- A day is not considered complete until all seven windows are finalized. No reservation expires,
  moves, refunds, or becomes a pass credit merely because wall time advanced.
- Opening/replaying is idempotent: repeated keeper and Game calls cannot double-seat, double-arm,
  double-fund the progressive, double-book action, or double-credit a payout.

If exact chronological budget semantics require delaying the currently live Craps day behind the
backlog, do that rather than opening it with knowingly incomplete trailing action. Document the
temporary catch-up UX clearly. Do not sacrifice accounting correctness merely to make today's
window appear immediately.

## 4. Make lootbox pass delivery lossless

`DegenerusGameLootboxModule._deliverPasses` currently catches a failed bounded call to
`CrapsBattle.deliverPasses`, emits the rolled counts, and records no obligation. That contradicts
the “passes are never lost” invariant.

Implement a durable failure path with these properties:

- Successful delivery retains the current one-call automatic-tomorrow behavior.
- If automatic reservation fails or exhausts its stipend, the complete normal/high award becomes
  durable credit or durable pending delivery; none is silently discarded.
- Prefer a minimal `OnlyGame` credit-only fallback on `CrapsBattle` with no external calls. If both
  automatic delivery and that minimal fallback fail, reverting the lootbox entry is safer than
  consuming it and lying about the award: the existing queue can retry later.
- Events distinguish reserved, credited, deferred, and failed/reverted dispositions sufficiently
  for an indexer to reconcile every rolled pass.
- Saturation behavior remains explicit and tested.
- Do not add a broad new main-Game entry point solely for this repair; Game runtime has only about
  89 bytes of measured EIP-170 headroom.

Update the day-pass specification, including its old AC-11 and AC-18 language, to match the final
lossless/no-skipped-day behavior.

## 5. Saturate the winnings tiebreak

Replace the modulo-style mask in the composite score:

```solidity
(s.won / 1 ether) & _SC_WON_MASK
```

with an explicit saturation at `_SC_WON_MASK`. Preserve every score bit and comparison priority.
Add a focused harness test proving values at the boundary and above it never wrap to a worse score.

## Acceptance tests

At minimum, add tests proving all of the following:

1. A large field partially settled before midnight resumes the same slot afterward.
2. Yesterday's event remains ahead of today's opener until it is fully finalized.
3. The cursor crosses remainder-zero separator slots without probing them as battles.
4. A slot externally armed before the cursor arrives is settled normally.
5. A slot externally completed before the cursor arrives causes one legitimate cursor advance and
   no duplicate payout.
6. `RngNotReady` never advances the cursor and never earns a repeated bounty.
7. A zero settlement budget does not resolve a seat but may perform one-time bounded lifecycle
   progress.
8. A long multi-day backlog advances over repeated calls with a deterministic per-call gas bound.
9. A multi-day Game/VRF stall followed by backfill creates and resolves every missing day and all
   seven windows per day.
10. Normal and high prepaid/pass holders on those historical days settle exactly once; their
    reservations do not expire, move, refund, or become credits.
11. No historical entry, donation, vault-board change, or amendment can be chosen after its
    settlement word is knowable.
12. Historical terms use the correct daily word while dice use an independently safe unknown word.
13. Historical days fund the progressive and book main/high action exactly once and in chronological
    order; later seven-day budgets include the correct prior action.
14. The ordinary no-backlog current-day path remains behaviorally equivalent.
15. Custom battles remain unaffected by the scheduled cursor.
16. Continuous or very large box work does not corrupt or reset the Craps cursor; document whether
    it can delay service and show that service resumes from the exact saved slot.
17. A forced primary pass-delivery revert and a forced stipend exhaustion preserve the complete
    award through the fallback/retry path.
18. Pass-delivery success still reserves at most one tomorrow seat and credits every remainder.
19. Score values below, at, and above `2^44 - 1` order monotonically and saturate rather than wrap.
20. Storage-layout oracle/parity checks pass after append-only state changes.
21. `CrapsBattle`, `DegenerusGame`, and all production modules remain deployable under EIP-170.
22. The complete production `game.mineFlip()` Craps path retains the existing approximately 9.5M
    p95 target and a deterministic hard bound below 16.7M gas.
23. Relevant `advanceGame(0)` worst paths remain below 15M gas.

Run the full `test/craps/*.t.sol` group, targeted protocol-wiring/keeper/pass tests, storage-layout
checks, progressive parity script, relevant stall/backfill tests, contract-size build, and
`git diff --check`. Report any unrelated pre-existing failure separately; do not weaken assertions
to manufacture a green result.

## Completion report

Return:

1. a concise architecture summary;
2. the exact cursor invariant and historical-day entropy argument;
3. every file changed;
4. tests run with pass/fail counts;
5. measured keeper/advance gas and runtime sizes;
6. documentation/spec conflicts corrected; and
7. any remaining liveness dependency or product decision.

</task_definition>

<interaction_patterns>

- Inspect the live diff and storage layout before editing. Preserve unrelated dirty-tree work.
- Prefer the smallest design that makes the invariant mechanically true. Explain any deviation
  from the recommended API before implementing it.
- When code and an older document conflict, identify which one reflects the explicit decisions in
  this brief and update the stale artifact.
- If a proposed shortcut would change emissions, house/vault participation, seven-day budget
  chronology, pass value, or RNG trust assumptions, stop and surface the exact tradeoff rather
  than choosing silently.
- Treat gas and code size as implementation constraints, not post-hoc observations. Measure them
  before declaring completion.
- Keep comments focused on invariants and failure modes. Remove obsolete claims that any older
  window is safe merely because direct settlement is permissionless.

</interaction_patterns>

<guardrails>

- Do not add terminal-game Craps settlement, entropy generation, or Game-over gating.
- Do not retain or recreate `openSlot - 1` as the source of keeper truth.
- Do not advance the scheduled cursor past an unfinalized playable slot.
- Do not classify an unopened historical day as empty, expired, or skippable.
- Do not use an unbounded day/slot loop in `openBonusDay`, `mineFlip`, `advanceGame`, or the new
  keeper operation.
- Do not use already-public entropy when any participant-controlled input can still change.
- Do not allow historical entries, donations, or amendments after their original windows elapsed.
- Do not append day-ticket entrants to a window more than once.
- Do not double-fund the progressive or book offered/unresolved action.
- Do not silently lose a pass to preserve fail-open behavior.
- Do not repurpose existing storage bits or reorder fields without updating and proving the layout.
- Do not add an owner/admin escape hatch for cursor advancement, settlement, refunds, or RNG.
- Do not make custom battles depend on the sequential scheduled cursor.
- Do not weaken roll, hand, seat, or gas ceilings.
- Do not reset deployment constants, discard the dirty worktree, or rewrite unrelated contracts.

</guardrails>

<examples>

### Correct: partial field crosses rollover

The cursor points at day 40 event slot 327. A bounded call resolves seats 1 through 61 and stops.
Midnight moves the wall clock to day 41. The next keeper call still begins at slot 327, resolves
seat 62 onward, finalizes it, then advances across day 41's remainder-zero separator. It never
jumps directly to day 41's most recently closed window.

### Correct: three historical days were missed

The Game resumes on day 44 after backfilling words for days 41–43. The current-day hook records
that day 44 is owed but performs no unbounded catch-up. Repeated keeper calls materialize day 41,
freeze its seven historical fields, bind settlement entropy that is still unknown, arm and settle
all seven, then do the same for days 42 and 43 before allowing the cursor to pass them. A player
who prepaid day 42 appears in all seven fields and receives exactly the resulting settlements.

### Correct: automatic pass delivery fails

The bounded automatic-tomorrow call reverts after rolling three normal passes and one high pass.
A minimal fallback records all four as Craps credits and emits their credited disposition. If even
that fallback cannot commit, the lootbox entry reverts and remains retryable; no successful event
claims that unrecorded passes were awarded.

### Failure mode to avoid

On day 44, the keeper calculates `openSlot - 1`, notices day 43's battle mapping is zero, and moves
on—or creates the historical vault seat and resolves it from day 43's already-public daily word.
The first variant permanently discards owed windows and reservations. The second lets a mutable
post-reveal input influence a known result. Both violate this brief.

</examples>

