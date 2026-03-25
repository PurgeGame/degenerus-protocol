# Phase 99: Callsite Audit - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Inventory every `_processAutoRebuy` callsite and every `prizePoolsPacked` write within the daily ETH jackpot paths that award ETH in large winner batches. This is a read-only investigation phase — no code changes.

**In scope:** Any daily jackpot path in `DegenerusGameJackpotModule.sol` that awards ETH to large batches of winners via `_processAutoRebuy`:
- `_processDailyEth` (up to 321 winners per call) — the main daily ETH jackpot loop
- `_runEarlyBirdLootboxJackpot` (up to 100 winners on Day 1) — earlybird ETH distribution

**Out of scope:**
- `DegenerusGameDecimatorModule._processAutoRebuy` — separate implementation, different call pattern
- `DegenerusGameEndgameModule` auto-rebuy-like loops — endgame-specific
- Non-auto-rebuy `_setFuturePrizePool`/`_setNextPrizePool` calls (26 total across 7 modules) — these are one-shot writes, not loop-iterated
- `payDailyCoinJackpot` / `payDailyJackpotCoinAndTickets` — these distribute coins/tickets, not ETH

</domain>

<decisions>
## Implementation Decisions

### Scope
- **D-01:** Optimization scope is limited to daily ETH jackpot paths in JackpotModule only — specifically `_processDailyEth` and `_runEarlyBirdLootboxJackpot`. DecimatorModule, EndgameModule, and other modules are excluded.
- **D-02:** The audit catalogs all `_setFuturePrizePool`/`_setNextPrizePool` calls within the two in-scope functions and their call trees, but does NOT catalog the 20+ other pool write sites across the protocol.

### Deliverable
- **D-03:** The audit should quantify the current SSTORE count per daily jackpot execution as a gas baseline for the implementation phase.

### Claude's Discretion
- Audit deliverable format (table structure, level of detail)
- Whether to include a call-graph diagram or just a flat callsite table
- How to handle the earlybird path (100 winners) vs main path (321 winners) in the gas baseline

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 96 Gas Analysis (v4.2)
- `.planning/phases/96-gas-ceiling-optimization/96-OPTIMIZATION-AUDIT.md` — SLOAD inventory with 24 entries, SSTORE gas summary, prizePoolsPacked batching analysis (H14), optimization disposition table
- `.planning/phases/96-gas-ceiling-optimization/96-GAS-ANALYSIS.md` — Gas ceiling profiles for all 3 daily jackpot stages with worst-case inputs

### Contract Source
- `contracts/modules/DegenerusGameJackpotModule.sol` — Contains both `_processDailyEth` (line 1338) and `_processAutoRebuy` (line 959) and `_runEarlyBirdLootboxJackpot` (line 772)
- `contracts/storage/DegenerusGameStorage.sol` — Contains `_setFuturePrizePool` (line 752) and `_setNextPrizePool` (line 740) and `prizePoolsPacked` storage layout

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions
- `_processAutoRebuy` (JM:959) — Takes beneficiary, weiAmount, entropy, state. Calls `_calcAutoRebuy` then writes `_setFuturePrizePool` (JM:982) and `_setNextPrizePool` (JM:984) with `calc.ethSpent`
- `_processDailyEth` (JM:1338) — Main daily ETH winner loop. Iterates up to 321 winners across 4 buckets, calls `_processAutoRebuy` per winner
- `_runEarlyBirdLootboxJackpot` (JM:772) — Earlybird loop, up to 100 winners on Day 1. Also calls `_processAutoRebuy`

### Storage Pattern
- `prizePoolsPacked` is a single storage slot containing both future and next prize pool values packed together
- `_setFuturePrizePool` / `_setNextPrizePool` do a full read-modify-write on the packed slot each call
- Per winner: 2 SSTOREs (future + next) if `calc.ethSpent > 0` — the dominant gas cost identified in v4.2 Phase 96

### Two Implementations
- JackpotModule `_processAutoRebuy` (JM:959) — takes 4 params including `AutoRebuyState`
- DecimatorModule `_processAutoRebuy` (DM:362) — separate implementation with different signature (returns bool)
- These are NOT the same function — they share a name but have different logic and callers

</code_context>

<specifics>
## Specific Ideas

User directive: "lets do this carefully" — audit-first approach, complete callsite inventory before any code changes.

The v4.2 Phase 96 OPTIMIZATION-AUDIT.md already has H14 analysis with ~1.6M gas savings estimate. This audit should validate and refine that estimate with precise SSTORE counts.

</specifics>

<deferred>
## Deferred Ideas

- DecimatorModule `_processAutoRebuy` batching — same pattern but separate implementation, lower iteration count
- EndgameModule auto-rebuy batching — endgame-specific loop
- Full protocol-wide `prizePoolsPacked` write map — 26 callsites across 7 modules

</deferred>

---

*Phase: 99-callsite-audit*
*Context gathered: 2026-03-25*
