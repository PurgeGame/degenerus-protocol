# Phase 82: Ticket Processing Mechanics - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- ticket batch processing, RNG word derivation for trait generation, cursor lifecycle, traitBurnTicket storage
**Confidence:** HIGH

## Summary

Phase 82 traces the ticket processing pipeline end-to-end: how queued tickets become trait entries in `traitBurnTicket`. There are two processing functions -- `processTicketBatch` in JackpotModule (current-level tickets, uses `lastLootboxRngWord` entropy) and `processFutureTicketBatch` in MintModule (near-future and far-future tickets, uses `rngWordCurrent` entropy). Both share identical `_raritySymbolBatch` and `_rollRemainder` implementations (duplicated across modules for delegatecall isolation) and write to the same `traitBurnTicket` storage mapping via inline assembly.

The cursor lifecycle involves three state variables: `ticketLevel` (uint24, which level is being processed -- uses bit 22 as an FF marker), `ticketCursor` (uint32, index into ticketQueue for that level), and `ticketsFullyProcessed` (bool, set when the read slot is fully drained for the current purchase level). These variables are shared across both processing paths and across mid-day/daily/new-day advanceGame calls, creating a complex state machine that must be traced carefully.

The RNG derivation chain for trait generation is: (1) VRF callback stores raw word via `rawFulfillRandomWords`, (2) `rngGate` applies nudges and stores as `rngWordCurrent` plus calls `_finalizeLootboxRng` which sets `lastLootboxRngWord`, (3) processing functions read these entropy sources, (4) per-ticket entropy is derived via LCG PRNG seeded from `(baseKey + groupIdx) ^ entropyWord`, (5) each LCG step produces a 64-bit value fed to `DegenerusTraitUtils.traitFromWord` for trait ID generation. The v3.8 commitment window inventory (Section 1.13) documents `processTicketBatch` but several line numbers have drifted and the section does not cover `processFutureTicketBatch` at all (added in v3.9).

**Primary recommendation:** Trace both processing functions with file:line citations, document the two distinct entropy sources, map the complete cursor state machine across all advanceGame paths, enumerate all traitBurnTicket writers and readers, and cross-reference against v3.8/v3.9 prior audit claims.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TPROC-01 | processTicketBatch entry point, all callers, and trigger conditions identified with file:line | Function at JM:1889; called via `_runProcessTicketBatch` (AM:1198) which delegatecalls JackpotModule; triggered from 3 advanceGame paths (mid-day AM:170, daily drain AM:211, new-day post-RNG AM:269) |
| TPROC-02 | processFutureTicketBatch entry point, dual-queue drain logic, FF key processing documented with file:line | Function at MM:298; called via `_processFutureTicketBatch` (AM:1134) which delegatecalls MintModule; triggered from `_prepareFutureTickets` (AM:1156, levels lvl+2..lvl+6) and direct call at AM:305 (nextLevel activation at last-purchase-day); dual-queue: read-side first, then FF transition when read empty |
| TPROC-03 | RNG word derivation chain for ticket trait generation documented | Two entropy sources: `lastLootboxRngWord` (JM:1915 for processTicketBatch) and `rngWordCurrent` (MM:301 for processFutureTicketBatch); both flow from rawFulfillRandomWords -> rngGate -> _applyDailyRng / _finalizeLootboxRng; trait derivation via LCG PRNG -> DegenerusTraitUtils.traitFromWord |
| TPROC-04 | Cursor management (ticketLevel, ticketCursor, ticketsFullyProcessed) full lifecycle traced with file:line | ticketLevel at GS:477, ticketCursor at GS:474, ticketsFullyProcessed at GS:332; written by both processTicketBatch (JM:1895-1946) and processFutureTicketBatch (MM:302-451); read by advanceGame at AM:156/205/276/719/1159/1201; _swapTicketSlot resets ticketsFullyProcessed at GS:713 |
| TPROC-05 | traitBurnTicket storage layout and all write/read paths documented | Storage at GS:417 `mapping(uint24 => address[][256])`; writes via assembly in `_raritySymbolBatch` (JM:2187-2221 and MM:521-555); reads by jackpot winner selection functions (JM:2244, JM:2294), view functions (DG:2618, DG:2647, DG:2730), and `_hasTraitTickets` (JM:1040) |
| TPROC-06 | Every discrepancy between prior audit prose and actual code flagged | v3.8 inventory Section 1.13 line numbers need verification against current code; v3.8 does not document processFutureTicketBatch at all; two different entropy sources for the two processing functions must be reconciled with prior claims |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

From global CLAUDE.md:
- **Self-check before delivering results** -- after completing any substantial task, internally review for gaps, stale references, cascading changes

From project memory:
- **Only read contracts from `contracts/` directory** -- stale copies exist elsewhere
- **Present fix and wait for explicit approval before editing code** -- audit-only phase, no code changes
- **NEVER commit contracts/ or test/ changes without explicit user approval** -- N/A for audit-only phase
- **Every RNG audit must trace BACKWARD from each consumer** -- applicable to verifying trait generation entropy sources
- **Every RNG audit must check what player-controllable state can change between VRF request and fulfillment** -- applicable to verifying neither entropy source is manipulable

From STATE.md:
- **v3.8 commitment window inventory has CONFIRMED ERRORS** -- all prior audit prose must be treated as unverified
- **DSC-01/DSC-02 from Phase 81 are cross-cutting** -- continue flagging stale v3.9 claims

## Architecture Patterns

### Delegatecall Module Architecture

Both processing functions execute via delegatecall from the game contract's storage context:

| Function | Module | Called From | Selector |
|----------|--------|-------------|----------|
| `processTicketBatch(lvl)` | JackpotModule (JM:1889) | `_runProcessTicketBatch` (AM:1198) | `IDegenerusGameJackpotModule.processTicketBatch.selector` |
| `processFutureTicketBatch(lvl)` | MintModule (MM:298) | `_processFutureTicketBatch` (AM:1134) | `IDegenerusGameMintModule.processFutureTicketBatch.selector` |

Both modules write to the same shared storage (DegenerusGameStorage) via delegatecall. The `_raritySymbolBatch` function is duplicated in both modules (JM:2127-2221 and MM:462-555) because each module needs its own copy for delegatecall isolation. The implementations are identical.

### Two Distinct Entropy Sources

This is a critical architectural detail for the audit:

| Processing Function | Entropy Variable | Set By | Timing |
|--------------------|------------------|--------|--------|
| `processTicketBatch` (JM:1889) | `lastLootboxRngWord` (JM:1915) | `_finalizeLootboxRng` (AM:843-848) and mid-day path (AM:162) | Set during daily rngGate and mid-day lootbox RNG |
| `processFutureTicketBatch` (MM:298) | `rngWordCurrent` (MM:301) | `_applyDailyRng` (AM:1535) | Set during daily rngGate processing |

Both are ultimately VRF-derived. `rngWordCurrent` is the daily VRF word (possibly nudged). `lastLootboxRngWord` is the same VRF word passed through `_finalizeLootboxRng`, or the mid-day lootbox RNG word.

### Cursor State Machine

Three variables form a shared cursor state:

```
ticketLevel    (GS:477, uint24)  -- which level is being processed
ticketCursor   (GS:474, uint32)  -- index into ticketQueue[key] for that level
ticketsFullyProcessed (GS:332, bool) -- read slot is fully drained for current purchase level
```

State transitions:

```
IDLE:          ticketLevel=0, ticketCursor=0
PROCESSING:    ticketLevel=lvl, ticketCursor=idx (advancing through queue)
FF_PROCESSING: ticketLevel=lvl|TICKET_FAR_FUTURE_BIT, ticketCursor=idx
DONE:          ticketLevel=0, ticketCursor=0 (returned to IDLE)
```

The FF bit (bit 22) on `ticketLevel` is the marker for far-future processing within `processFutureTicketBatch`. When the read-side queue is exhausted and an FF queue exists, ticketLevel is set to `lvl | TICKET_FAR_FUTURE_BIT` to signal the transition.

### advanceGame Trigger Points for Processing

| Path | Location | When | Processing Function |
|------|----------|------|-------------------|
| Mid-day (same day) | AM:156-181 | `day == dailyIdx`, read slot not drained | `_runProcessTicketBatch(purchaseLevel)` |
| Daily drain gate | AM:205-219 | `day > dailyIdx`, read slot not drained | `_runProcessTicketBatch(purchaseLevel)` |
| New-day post-RNG current-level | AM:269-276 | After RNG received, before jackpots | `_runProcessTicketBatch(purchaseLevel)` |
| New-day near-future (lvl+2..lvl+6) | AM:262 | After RNG, before daily draws | `_prepareFutureTickets(lvl)` -> `_processFutureTicketBatch` per level |
| Last-purchase-day next-level | AM:305 | After current-level done, before pool consolidation | `_processFutureTicketBatch(nextLevel)` |

### processTicketBatch Flow (JM:1889-1950)

```
processTicketBatch(lvl):
  1. rk = _tqReadKey(lvl)                    -- JM:1890
  2. queue = ticketQueue[rk]                  -- JM:1891
  3. If ticketLevel != lvl: reset cursor      -- JM:1895-1898
  4. If idx >= total: delete queue, return     -- JM:1901-1907
  5. Set writesBudget (550, -35% if cold)      -- JM:1909-1912
  6. entropy = lastLootboxRngWord              -- JM:1915
  7. Loop: _processOneTicketEntry per player   -- JM:1918-1937
  8. Save ticketCursor                         -- JM:1940
  9. If all done: delete queue, reset cursor   -- JM:1942-1948
```

### processFutureTicketBatch Flow (MM:298-453)

```
processFutureTicketBatch(lvl):
  1. entropy = rngWordCurrent                  -- MM:301
  2. Determine if in FF phase: ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT)  -- MM:302
  3. rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl)              -- MM:303
  4. If queue empty and NOT in FF phase:
     a. Check FF queue exists -> transition to FF (set ticketLevel with FF bit)  -- MM:307-313
     b. Else: done, reset cursor                                                  -- MM:315-317
  5. If queue empty but idx >= total (read-side exhausted):
     a. Delete read-side queue                                                    -- MM:327
     b. Check FF queue -> transition if exists                                    -- MM:328-335
     c. Else: done, reset cursor                                                  -- MM:336-338
  6. Budget setup (550, -35% cold)                                                -- MM:342-345
  7. Inline processing loop (no _processOneTicketEntry delegation):
     a. Load player, packed, owed/rem                                             -- MM:351-357
     b. Handle zero-owed: skip or roll remainder                                  -- MM:358-382
     c. Calculate batch size                                                      -- MM:383-390
     d. Call _raritySymbolBatch                                                   -- MM:392
     e. Finalize entry: update packed, roll remainder if done                     -- MM:407-429
  8. Save cursor, check finished                                                  -- MM:434-452
  9. On finish: delete queue, check FF transition                                 -- MM:436-452
```

### traitBurnTicket Storage Layout

```solidity
// GS:417
mapping(uint24 => address[][256]) internal traitBurnTicket;
```

Storage derivation (used by assembly in _raritySymbolBatch):
```
levelSlot = keccak256(lvl . traitBurnTicket.slot)    -- root for this level
elemSlot  = levelSlot + traitId                       -- length slot for trait array
dataSlot  = keccak256(elemSlot)                       -- first data element
```

Each `traitBurnTicket[level][traitId]` is a dynamic `address[]` array. The assembly writes `player` address `occurrences` times starting at `dataSlot + currentLength`, then updates length to `currentLength + occurrences`.

### _raritySymbolBatch Algorithm (JM:2127-2221 / MM:462-555)

```
Input: player, baseKey, startIndex, count, entropyWord
  baseKey = (lvl << 224) | (queueIdx << 192) | (player << 32)

For tickets in [startIndex, startIndex+count):
  groupIdx = i >> 4                              -- group of 16
  seed = (baseKey + groupIdx) ^ entropyWord      -- per-group seed
  s = uint64(seed) | 1                           -- ensure odd for full LCG period
  s = s * (LCG_MULT + offset) + offset           -- advance to start position
  For each position in group:
    s = s * LCG_MULT + 1                         -- LCG step
    traitId = traitFromWord(s) + (quadrant << 6) -- 8-bit trait ID
    Track in counts[256] and touchedTraits[]

Assembly batch write:
  For each touched trait:
    elemSlot = levelSlot + traitId
    oldLen = sload(elemSlot)
    sstore(elemSlot, oldLen + occurrences)        -- update length
    dataSlot = keccak256(elemSlot)
    For k in [0, occurrences):
      sstore(dataSlot + oldLen + k, player)       -- write player address
```

### LCG Constants (Identical in Both Modules)

```solidity
// JM:170 (hex)
uint64 private constant TICKET_LCG_MULT = 0x5851F42D4C957F2D;

// MM:83 (decimal)
uint64 private constant TICKET_LCG_MULT = 6364136223846793005;
```

Both are the same value (verified: `0x5851F42D4C957F2D == 6364136223846793005`). This is a well-known LCG multiplier from the PCG family.

### Trait Generation: traitFromWord (DegenerusTraitUtils.sol:143-150)

```solidity
function traitFromWord(uint64 rnd) internal pure returns (uint8) {
    uint8 category = weightedBucket(uint32(rnd));      // low 32 bits
    uint8 sub = weightedBucket(uint32(rnd >> 32));     // high 32 bits
    return (category << 3) | sub;                       // 6-bit trait ID
}
```

Caller adds quadrant offset: `traitId = traitFromWord(s) + (uint8(i & 3) << 6)`. Final trait ID is 8 bits: `[QQ][CCC][SSS]` (quadrant, category, sub-bucket).

### _rollRemainder (JM:2101-2108 / MM:559-565)

```solidity
function _rollRemainder(
    uint256 entropy,
    uint256 rollSalt,
    uint8 rem
) private pure returns (bool win) {
    uint256 rollEntropy = EntropyLib.entropyStep(entropy ^ rollSalt);
    return (rollEntropy % TICKET_SCALE) < rem;   // TICKET_SCALE = 100
}
```

Fractional tickets (0-99 remainder) get a probabilistic roll. Identical implementation in both modules.

### EntropyLib.entropyStep (EntropyLib.sol:16-23)

```solidity
function entropyStep(uint256 state) internal pure returns (uint256) {
    unchecked {
        state ^= state << 7;
        state ^= state >> 9;
        state ^= state << 8;
    }
    return state;
}
```

XOR-shift PRNG step. Used for remainder rolls and various entropy derivation throughout the protocol.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ticket processing tracing | Custom static analysis | Systematic line-by-line code reading with file:line citations | Delegatecall + inline assembly + shared state across modules defeats automated tools |
| Storage slot verification | Manual slot counting | `forge inspect DegenerusGame storage-layout` | Compiler-authoritative; assembly references traitBurnTicket.slot which must match |
| LCG verification | Manual computation | Python/calculator confirmation of `0x5851F42D4C957F2D == 6364136223846793005` | Already verified during research -- both modules use the same value |
| Discrepancy detection | Trusting prior audit docs | Independent code trace, then cross-reference | v3.8 has confirmed errors; every claim needs current-code verification |

## Common Pitfalls

### Pitfall 1: Conflating the Two Entropy Sources
**What goes wrong:** Claiming both processing functions use the same entropy source
**Why it happens:** They have similar names and both derive from VRF words
**How to avoid:** `processTicketBatch` reads `lastLootboxRngWord` (JM:1915); `processFutureTicketBatch` reads `rngWordCurrent` (MM:301). Document each explicitly.
**Warning signs:** Any claim that "ticket processing uses rngWordCurrent" without distinguishing which function

### Pitfall 2: Missing the FF Bit on ticketLevel
**What goes wrong:** Treating ticketLevel as always a raw level number
**Why it happens:** ticketLevel is uint24, same as level, so it looks like a plain level
**How to avoid:** When `ticketLevel` has bit 22 set (TICKET_FAR_FUTURE_BIT), it signals that `processFutureTicketBatch` is mid-way through processing the FF queue for that base level. The base level is `ticketLevel & ~TICKET_FAR_FUTURE_BIT`. This is checked at MM:302 and AM:1161-1162.
**Warning signs:** ticketLevel values like 0x400005 (which means "processing FF queue for level 5")

### Pitfall 3: Assuming _processOneTicketEntry Exists in MintModule
**What goes wrong:** Claiming both functions delegate to `_processOneTicketEntry`
**Why it happens:** `processTicketBatch` in JackpotModule uses `_processOneTicketEntry` (JM:1984), but `processFutureTicketBatch` in MintModule has the processing logic inline
**How to avoid:** Note the structural difference: JM delegates to helper functions (_processOneTicketEntry -> _generateTicketBatch -> _raritySymbolBatch -> _finalizeTicketEntry); MM has the loop body inline with direct calls to _raritySymbolBatch and _rollRemainder. The result is functionally equivalent but structurally different.

### Pitfall 4: Incomplete Cursor Reset Analysis
**What goes wrong:** Missing a cursor reset path, leading to incorrect state machine documentation
**Why it happens:** Cursor is reset in many places: both processing functions, _swapTicketSlot, and _prepareFutureTickets
**How to avoid:** Enumerate every write to ticketLevel, ticketCursor, and ticketsFullyProcessed with file:line. Key reset points:
- `_swapTicketSlot` (GS:713): `ticketsFullyProcessed = false`
- `processTicketBatch` done (JM:1904-1905, JM:1945-1946): `ticketCursor = 0, ticketLevel = 0`
- `processFutureTicketBatch` done (MM:315-316, MM:336-337, MM:445-446, MM:449-450): `ticketCursor = 0, ticketLevel = 0`
- `processFutureTicketBatch` FF transition (MM:310-311, MM:331-332, MM:441-442): `ticketLevel = lvl | TICKET_FAR_FUTURE_BIT, ticketCursor = 0`
- `advanceGame` (AM:173, AM:218, AM:276): `ticketsFullyProcessed = true`

### Pitfall 5: Stale v3.8 Line Numbers
**What goes wrong:** Citing v3.8 commitment window inventory line numbers as current
**Why it happens:** v3.9 changes shifted line numbers throughout the codebase
**How to avoid:** Every line number must be verified against current code. Known drifts from Phase 81: AM:230->AM:233, GS:713-718->GS:709-714, AM:717->AM:720, AM:718->AM:721. The v3.8 inventory Section 1.13 cites JackpotModule:1890-1951 for processTicketBatch which appears to still be accurate (JM:1889-1950 in current code -- 1-line shift).

### Pitfall 6: Overlooking the Assembly Storage Write Pattern
**What goes wrong:** Assuming `traitBurnTicket` is written via normal Solidity push operations
**Why it happens:** The mapping declaration looks standard: `mapping(uint24 => address[][256])`
**How to avoid:** The actual writes use inline assembly for gas efficiency. The assembly computes storage slots manually: `levelSlot = keccak256(lvl . traitBurnTicket.slot)`, then `elemSlot = levelSlot + traitId`, then `dataSlot = keccak256(elemSlot)`. Verify this matches the Solidity storage layout for `mapping(uint24 => address[][256])`.

## Key Research Findings

### Finding 1: processFutureTicketBatch NOT Documented in v3.8
**Confidence:** HIGH
**Details:** The v3.8 commitment window inventory (Section 1.13) documents `processTicketBatch` but does not mention `processFutureTicketBatch` at all. This function was added in v3.9 Phase 76 as part of the far-future ticket fix. Any prior audit prose about "ticket processing" implicitly refers only to `processTicketBatch`. The Phase 82 audit must document `processFutureTicketBatch` as a new code path not covered by v3.8.

### Finding 2: Two Different Entropy Sources for Two Processing Functions
**Confidence:** HIGH
**Details:** `processTicketBatch` (JM:1915) uses `lastLootboxRngWord`. `processFutureTicketBatch` (MM:301) uses `rngWordCurrent`. Both are VRF-derived but set at different points in the rngGate flow. `rngWordCurrent` is the nudge-adjusted daily VRF word. `lastLootboxRngWord` is set by `_finalizeLootboxRng` (same daily VRF word stored to the lootbox index) or by the mid-day path (AM:162, from lootboxRngWordByIndex). This means the two functions may use different entropy values in the mid-day path scenario.

### Finding 3: Duplicated _raritySymbolBatch Across Modules
**Confidence:** HIGH
**Details:** `_raritySymbolBatch` exists in both JackpotModule (JM:2127-2221) and MintModule (MM:462-555). Both use the same LCG constant (`0x5851F42D4C957F2D`), the same seeding formula, the same trait generation via `DegenerusTraitUtils.traitFromWord`, and the same assembly write pattern to `traitBurnTicket`. The duplication is necessary because delegatecall modules cannot call private functions across module boundaries.

### Finding 4: v3.8 Inventory processTicketBatch Line Numbers Need Verification
**Confidence:** HIGH
**Details:** v3.8 cites `processTicketBatch` at JackpotModule:1890-1951. Current code: JM:1889-1950 (1-line shift). v3.8 cites entropy source at `lastLootboxRngWord` at slot 70 -- need to verify against current `forge inspect`. v3.8 cites `traitBurnTicket` at slot 11 -- also needs verification.

### Finding 5: ticketsFullyProcessed Has Multiple Setters
**Confidence:** HIGH
**Details:** `ticketsFullyProcessed` is set to `true` at three different advanceGame locations:
- AM:173 (mid-day path, after `_runProcessTicketBatch` returns finished)
- AM:218 (daily drain gate, when read slot empty or just finished)
- AM:276 (new-day post-RNG path, marked as "ADV-03: set before jackpot/phase logic")
It is set to `false` by `_swapTicketSlot` (GS:713) and by `_swapAndFreeze` (which calls `_swapTicketSlot`).

### Finding 6: processTicketBatch Budget Calculation Detail
**Confidence:** HIGH
**Details:** Both processing functions use `WRITES_BUDGET_SAFE = 550` (JM:157 and MM:80). First batch (idx == 0) gets 65% scaling: `writesBudget -= (writesBudget * 35) / 100` = 357. Write cost per ticket: 2 SSTOREs (trait array push + length update). Additional overhead: 2-4 per player entry (baseOv depends on whether first entry and owed count). This means roughly 90-178 tickets per advanceGame call.

## Prior Audit Cross-Reference Targets

The following v3.8 claims must be verified against current code:

| v3.8 Claim | Location in v3.8 Inventory | Verify Against |
|------------|---------------------------|----------------|
| processTicketBatch at JM:1890-1951 | Section 1.13 line 171 | Current: JM:1889-1950 |
| lastLootboxRngWord at slot 70 | Section 1.13 line 178 | `forge inspect` or GS storage comments |
| traitBurnTicket at slot 11 | Section 1.13 line 180 | `forge inspect` or GS storage comments |
| ticketLevel at slot 17 offset 4 | Section 1.13 line 175 | GS storage comment at GS:477 |
| ticketCursor at slot 17 offset 0 | Section 1.13 line 176 | GS storage comment at GS:474 |
| "No permissionless external function directly writes traitBurnTicket outside of processTicketBatch" | Section line 766 | Must now include processFutureTicketBatch too |

The last claim is stale: `processFutureTicketBatch` also writes to `traitBurnTicket` via `_raritySymbolBatch`. The statement should say "No permissionless external function directly writes traitBurnTicket outside of processTicketBatch and processFutureTicketBatch."

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract <TestName> -vvv` |
| Full suite command | `forge test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TPROC-01 | processTicketBatch callers and triggers | manual audit | N/A (code trace) | N/A |
| TPROC-02 | processFutureTicketBatch dual-queue drain | manual audit | N/A (code trace) | N/A |
| TPROC-03 | RNG word derivation chain | manual audit | N/A (code trace) | N/A |
| TPROC-04 | Cursor lifecycle | manual audit | N/A (code trace) | N/A |
| TPROC-05 | traitBurnTicket storage layout and paths | manual audit + forge inspect | `forge inspect DegenerusGame storage-layout` | N/A |
| TPROC-06 | Discrepancy detection | manual audit | N/A (cross-reference) | N/A |

### Sampling Rate
- **Per task commit:** `forge test --match-contract QueueDoubleBuffer -vvv` (verify no regression)
- **Per wave merge:** `forge test` (full suite)
- **Phase gate:** All existing Foundry tests pass before /gsd:verify-work

### Wave 0 Gaps
None -- this is an audit-only phase (no code changes). Existing test infrastructure covers ticket processing and double-buffer mechanics. The deliverable is an audit document, not code.

## Code Examples

### processTicketBatch Entry (JM:1889-1916)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1889-1916
function processTicketBatch(uint24 lvl) external returns (bool finished) {
    uint24 rk = _tqReadKey(lvl);
    address[] storage queue = ticketQueue[rk];
    uint256 total = queue.length;

    if (ticketLevel != lvl) {
        ticketLevel = lvl;
        ticketCursor = 0;
    }

    uint256 idx = ticketCursor;
    if (idx >= total) {
        delete ticketQueue[rk];
        ticketCursor = 0;
        ticketLevel = 0;
        return true;
    }

    uint32 writesBudget = WRITES_BUDGET_SAFE;
    if (idx == 0) {
        writesBudget -= (writesBudget * 35) / 100;
    }

    uint32 used;
    uint256 entropy = lastLootboxRngWord;   // <-- ENTROPY SOURCE
    uint32 processed;
    // ... processing loop
```

### processFutureTicketBatch Entry (MM:298-312)
```solidity
// Source: contracts/modules/DegenerusGameMintModule.sol:298-312
function processFutureTicketBatch(
    uint24 lvl
) external returns (bool worked, bool finished, uint32 writesUsed) {
    uint256 entropy = rngWordCurrent;      // <-- DIFFERENT ENTROPY SOURCE
    bool inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT));
    uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);
    address[] storage queue = ticketQueue[rk];
    uint256 total = queue.length;
    if (total == 0) {
        if (!inFarFuture) {
            uint24 ffk = _tqFarFutureKey(lvl);
            if (ticketQueue[ffk].length > 0) {
                ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
                ticketCursor = 0;
                return (false, false, 0);    // Signal: transition to FF phase
            }
        }
        // ...
```

### _prepareFutureTickets Loop (AM:1156-1184)
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1156-1184
function _prepareFutureTickets(uint24 lvl) private returns (bool finished) {
    uint24 startLevel = lvl + 2;
    uint24 endLevel = lvl + 6;
    uint24 resumeLevel = ticketLevel;
    uint24 baseResume = resumeLevel & ~uint24(TICKET_FAR_FUTURE_BIT);

    // Continue an in-flight future level first to preserve progress.
    if (baseResume >= startLevel && baseResume <= endLevel) {
        (bool worked, bool levelFinished, ) = _processFutureTicketBatch(baseResume);
        if (worked || !levelFinished) return false;
    }

    // Then probe remaining target levels in order.
    for (uint24 target = startLevel; target <= endLevel; ) {
        if (target != baseResume) {
            (bool worked, bool levelFinished, ) = _processFutureTicketBatch(target);
            if (worked || !levelFinished) return false;
        }
        unchecked { ++target; }
    }
    return true;
}
```

### Assembly traitBurnTicket Write (JM:2187-2221)
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2187-2221
uint256 levelSlot;
assembly ("memory-safe") {
    mstore(0x00, lvl)
    mstore(0x20, traitBurnTicket.slot)
    levelSlot := keccak256(0x00, 0x40)
}

for (uint16 u; u < touchedLen; ) {
    uint8 traitId = touchedTraits[u];
    uint32 occurrences = counts[traitId];

    assembly ("memory-safe") {
        let elem := add(levelSlot, traitId)
        let len := sload(elem)
        let newLen := add(len, occurrences)
        sstore(elem, newLen)                    // Update array length

        mstore(0x00, elem)
        let data := keccak256(0x00, 0x20)
        let dst := add(data, len)
        for { let k := 0 } lt(k, occurrences) { k := add(k, 1) } {
            sstore(dst, player)                 // Push player address
            dst := add(dst, 1)
        }
    }
    unchecked { ++u; }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single processTicketBatch only | processTicketBatch (current-level) + processFutureTicketBatch (near-future + FF) | v3.9 Phase 76 | Future tickets now properly processed from both read-side and FF key space |
| No FF processing | Dual-queue drain in processFutureTicketBatch (read-side first, then FF key) | v3.9 Phase 76 | Far-future tickets no longer stranded |
| _awardFarFutureCoinJackpot reads _tqWriteKey | Reads _tqFarFutureKey only | v3.9 Phase 77 + commit 2bf830a2 | TQ-01 fixed (but v3.9 proof is stale per Phase 81 DSC-01) |

## Open Questions

1. **Are `lastLootboxRngWord` and `rngWordCurrent` always the same value during processTicketBatch?**
   - What we know: In the daily path, `_finalizeLootboxRng` (AM:843-848) sets `lastLootboxRngWord = rngWord` where `rngWord` is the nudge-adjusted `rngWordCurrent` from `_applyDailyRng`. So in the daily path, they should be the same value. In the mid-day path, `lastLootboxRngWord` may be set from `lootboxRngWordByIndex[lootboxRngIndex - 1]` (AM:162), which is a different VRF word from a mid-day lootbox RNG request.
   - What's unclear: Whether mid-day ticket processing ever runs `processTicketBatch` with a `lastLootboxRngWord` that differs from the daily word.
   - Recommendation: Trace the mid-day path explicitly to determine if the entropy source for `processTicketBatch` is ever the mid-day lootbox word rather than the daily word. This is important for RNG derivation documentation.

2. **Does `processFutureTicketBatch` correctly handle the case where ticketLevel has the FF bit set from a prior interrupted run, but the caller passes a different level?**
   - What we know: At MM:302, `inFarFuture = (ticketLevel == (lvl | TICKET_FAR_FUTURE_BIT))`. If ticketLevel has the FF bit set for level X but the caller asks for level Y, `inFarFuture` is false, and the function processes level Y's read-side queue. The prior level X's FF processing is abandoned.
   - What's unclear: Whether `_prepareFutureTickets` guarantees levels are processed in order such that this abandonment cannot happen.
   - Recommendation: Verify that `_prepareFutureTickets` (AM:1156-1184) handles the resume correctly by checking `baseResume` first before iterating other levels.

3. **Is the v3.8 claim that traitBurnTicket is at slot 11 still correct?**
   - What we know: GS:417 declares `mapping(uint24 => address[][256]) internal traitBurnTicket`. The v3.8 inventory claims slot 11. GS:104 in the header comments says "traitBurnTicket nested mapping" and the assembly uses `traitBurnTicket.slot` (resolved by compiler).
   - What's unclear: Whether v3.9 storage additions shifted the slot number.
   - Recommendation: Run `forge inspect DegenerusGame storage-layout` during plan execution to confirm the current slot number.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- processTicketBatch (JM:1889-1950), _processOneTicketEntry (JM:1984-2047), _generateTicketBatch (JM:2050-2070), _finalizeTicketEntry (JM:2073-2098), _rollRemainder (JM:2101-2108), _raritySymbolBatch (JM:2127-2221), _randTraitTicket (JM:2237-2280), WRITES_BUDGET_SAFE (JM:157), TICKET_LCG_MULT (JM:170)
- `contracts/modules/DegenerusGameMintModule.sol` -- processFutureTicketBatch (MM:298-453), _raritySymbolBatch (MM:462-555), _rollRemainder (MM:559-565), WRITES_BUDGET_SAFE (MM:80), TICKET_LCG_MULT (MM:83)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- advanceGame ticket processing paths (AM:156-276), _prepareFutureTickets (AM:1156-1184), _processFutureTicketBatch delegatecall (AM:1134-1148), _runProcessTicketBatch delegatecall (AM:1198-1215), rawFulfillRandomWords (AM:1442-1463), rngGate (AM:768-841), _applyDailyRng (AM:1523-1539), _finalizeLootboxRng (AM:843-848)
- `contracts/storage/DegenerusGameStorage.sol` -- ticketCursor (GS:474), ticketLevel (GS:477), ticketsFullyProcessed (GS:332), ticketQueue (GS:463), ticketsOwedPacked (GS:467), traitBurnTicket (GS:417), lastLootboxRngWord (GS:1240), rngWordCurrent (GS:362), _swapTicketSlot (GS:709-714)
- `contracts/DegenerusGame.sol` -- traitBurnTicket read paths (DG:2618, DG:2647, DG:2730)
- `contracts/DegenerusTraitUtils.sol` -- traitFromWord (line 143-150)
- `contracts/libraries/EntropyLib.sol` -- entropyStep (line 16-23)

### Secondary (MEDIUM confidence)
- `audit/v3.8-commitment-window-inventory.md` -- Section 1.13 (processTicketBatch), line 766 (traitBurnTicket writer claim), Section 4 variable catalog
- `audit/v4.0-ticket-queue-double-buffer.md` -- ticketQueue key consumer enumeration (Phase 81 Plan 02)
- `audit/v4.0-ticket-creation-queue-mechanics.md` -- ticket creation paths (Phase 81 Plan 01)
- `audit/v4.0-findings-consolidated.md` -- DSC-01, DSC-02, DSC-03 findings

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- processTicketBatch flow: HIGH -- function read line-by-line, all paths traced
- processFutureTicketBatch flow: HIGH -- function read line-by-line, dual-queue logic verified
- RNG derivation chain: HIGH -- both entropy sources traced from rawFulfillRandomWords through to trait generation
- Cursor lifecycle: HIGH -- all reads and writes of ticketLevel/ticketCursor/ticketsFullyProcessed enumerated via grep
- traitBurnTicket storage: HIGH -- assembly write pattern read directly, read paths enumerated via grep
- Prior audit discrepancies: HIGH -- v3.8 Section 1.13 compared against current code; gap (missing processFutureTicketBatch) identified

**Research date:** 2026-03-23
**Valid until:** Indefinite (audit of immutable contract code)
