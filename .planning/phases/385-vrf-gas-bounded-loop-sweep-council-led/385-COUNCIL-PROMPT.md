# Council Sweep 385 — VRF / GAS-BOUNDED-LOOP

You are an external auditor on a cross-model council auditing the **Degenerus Protocol** before a Code4rena
audit. Read the EXACT frozen source at `c4d48008` via `git show c4d48008:contracts/<File>.sol` (ignore the
working tree). Concrete + reachable only.

**Threat priority:** DOMINANT = RNG/freeze manipulability; HIGH = an unbounded loop / a loop whose bound
rests on an UNENFORCED invariant (these become gas-DoS bricks in the `advanceGame` chain).

**ALREADY FOUND (do NOT re-report):** V62-01 (lootbox auto-open off-by-one). Also REFUTED already (do not
re-raise): `_backfillOrphanedLootboxIndices` is NOT unbounded — it breaks on the first filled index and
`LR_INDEX` is structurally ≤1 ahead of the last filled index (mid-day `requestLootboxRng` gated on
`rngRequestTime==0`; `retryLootboxRng` and coordinator rotation never increment the index).

**KNOWN BY-DESIGN (do NOT flag):** as in the other sweeps.

## Focus (LOOP-01..03 + VRF freshness + carried FC1/FC5/FC6)

1. **Bounded-loop re-verification (LOOP-02).** Confirm each CLOSED loop stays bounded under its WORST case:
   `_backfillOrphanedLootboxIndices` (max ~1, gated `rngRequestTime==0`), `_backfillGapDays` (cap 120),
   deity-refund (cap `DEITY_PASS_MAX_TOTAL=32`), the subscriber stage (`SUBSCRIBER_CAP=1000`,
   weight-chunked). Is any cap actually reachable-and-too-large, or enforced only by an UNENFORCED
   assumption rather than a numeric cap?
2. **New unbounded loop (LOOP-03).** Hunt any NEW unbounded iteration (especially v61 code) or a loop whose
   bound is an unenforced invariant (the shape the orphan-index loop had before it was bounded).
3. **VRF window freshness (the v45 north-star).** Enumerate ALL SLOADs consumed inside the VRF
   request→fulfill→unlock window — not just VRF-derived seeds. For each consumer of `rngWordByDay` /
   `rngWordCurrent` / `lootboxRngWordByIndex` / `_applyDailyRng`, verify the value (and every co-read
   non-VRF slot) was frozen / unknown at input-commitment time. Can any player action between VRF request
   and fulfillment change a slot the consumption reads?
4. **Carried candidates:** **FC1** mid-day request blocks the next advance (does a pending mid-day request
   stall `advanceGame` progression in a reachable way?); **FC5** entropy-binding is no longer observable in
   the slimmed `TraitsGenerated` event — is the binding still ENFORCED on-chain even if not emitted?;
   **FC6** a mid-day-pending stall + coordinator swap backfills zero gap days — does that strand days or
   mis-seed?

## Output (per finding)
PROPERTY · reachable sequence · the loop / RNG-consumer + `file:line` at `c4d48008` · the bound or
freshness mechanism that fails · SEVERITY. State explicitly any loop/consumer you verified bounded/frozen
and the argument.
