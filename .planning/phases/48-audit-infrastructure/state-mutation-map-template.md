# State Mutation Map Template

**Purpose:** Track every storage variable and which modules/functions can read or write it via delegatecall. This template formalizes the format used in the Phase 57 state mutation matrix analysis.

**How to fill out:** For each storage variable defined in the central contract's storage layout, identify every delegatecall module that accesses it. Mark each cell with the R/W/RW annotation. Then analyze all cross-module write conflicts for safety.

---

## Section A: Mutation Matrix

The mutation matrix shows which delegatecall modules access which storage variables. Since modules execute via delegatecall, they share the central contract's storage, making this matrix essential for identifying unintended state interference.

### A.1 Storage Variable Inventory

First, enumerate all storage variables with their types, slot assignments, and purposes.

| Slot/Group | Variable | Type | Purpose |
|-----------|----------|------|---------|
| Slot 0 | `levelStartTime` | uint48 | Timestamp when current level opened |
| Slot 0 | `level` | uint24 | Current jackpot level |
| Slot 0 | `jackpotPhaseFlag` | bool | Phase: false=PURCHASE, true=JACKPOT |
| Slot 3 | `currentPrizePool` | uint256 | Active prize pool for current level |
| Slot 4 | `nextPrizePool` | uint256 | Pre-funded pool for next level |
| Single | `futurePrizePool` | uint256 | Unified reserve pool |
| Mapping | `claimableWinnings[addr]` | mapping(address=>uint256) | ETH claimable per player |
| Mapping | `claimablePool` | uint256 | Aggregate ETH liability |
| ... | ... | ... | ... |

**Fill-in instructions:**
- **Slot/Group:** The storage slot number for packed variables, "Mapping" for mappings, "Single" for standalone variables, "Array" for dynamic arrays, "Struct" for struct types.
- **Variable:** The Solidity variable name as declared in the storage contract.
- **Type:** The Solidity type.
- **Purpose:** Brief description of what this variable tracks.

### A.2 Module Write Matrix

Which modules write which storage variables. List every delegatecall module as a column.

**Cell values:**
- `W` = write only (variable is assigned but not read by this module)
- `R` = read only (variable is read but never assigned by this module)
- `RW` = read and write (variable is both read and assigned)
- `-` = no access (module does not reference this variable)
- `R*` / `W*` = conditional access (explain in Notes column -- e.g., "only during presale")

| # | Storage Variable | Type | AdvanceModule | MintModule | JackpotModule | EndgameModule | LootboxModule | GameOverModule | WhaleModule | DegeneretteModule | BoonModule | DecimatorModule | Notes |
|---|-----------------|------|---------------|------------|---------------|---------------|---------------|----------------|-------------|-------------------|------------|-----------------|-------|
| 1 | `level` | uint24 | W | | | | | | | | | | Set during level transition |
| 2 | `rngLockedFlag` | bool | W | | | | | | | | | | Latched on VRF request, cleared on fulfill |
| 3 | `currentPrizePool` | uint256 | W | | W | | | W | | | | | Advance: consolidation; Jackpot: daily payout; GameOver: drain |
| 4 | `nextPrizePool` | uint256 | W | | W | W | | | W | | | | Multiple additive writers during purchase phase |
| 5 | `futurePrizePool` | uint256 | W | | W | W | | W | W | | | | Central reserve pool, many writers |
| 6 | `claimableWinnings` | mapping | | | W | W | W | W | W | W | | W | Additive credit pattern only |
| 7 | `claimablePool` | uint256 | | | W | W | W | W | W | W | | W | Aggregate liability tracking |
| 8 | `mintPacked_` | mapping | | W | | | | | W | | | | Bit-packed; Mint/Whale write different bit ranges |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

**Fill-in instructions:**
- One row per storage variable (or variable group for related mappings).
- One column per delegatecall module, plus a Notes column.
- Include the central contract itself as a column if it has direct writes (not via delegatecall).
- For packed variables where multiple modules write different bit ranges, note "different bit fields" in Notes.

---

## Section B: Per-Module Write Summary

For each delegatecall module, list all storage variables it writes along with the context of when and why the write occurs.

### AdvanceModule

**Storage writes:**
- `level` -- incremented during level transition
- `rngLockedFlag` -- latched on VRF request, cleared on fulfillment
- `currentPrizePool` -- set during pool consolidation at J->P transition
- `futurePrizePool` -- drawdown during jackpot phase entry, time-based skim
- `rngWordCurrent` -- set on VRF fulfillment
- ...

**Write count:** N variables

### MintModule

**Storage writes:**
- `mintPacked_` -- records mint history (level count, day, streak) via BitPackingLib
- `ticketQueue` -- pushes ticket queue entries for future levels
- `lootboxEth` -- records ETH allocated to lootbox at purchase time
- `lootboxEthTotal` -- increments total lootbox ETH counter
- ...

**Write count:** N variables

### [ModuleName]

**Storage writes:**
- `variable1` -- context of when/why written
- `variable2` -- context of when/why written

**Write count:** N variables

**Fill-in instructions:**
- Create one subsection per module.
- List every variable the module writes (W or RW in the matrix).
- Provide context: when does the write happen (which function, which phase), why (what triggers it), and any conditions that gate the write.

---

## Section C: Cross-Module Write Conflicts

Cases where multiple modules write the same storage variable. Each conflict must be analyzed for safety.

| Storage Variable | Writers | Conflict Safe? | Reason |
|-----------------|---------|---------------|--------|
| `claimableWinnings` | Jackpot, Endgame, Lootbox, GameOver, Whale, Degenerette, Decimator | Yes | All writes are additive (credit pattern: `+= amount`). No module zeroes or decrements another module's credits. Decrements only in Game's own `_claimWinningsInternal`. |
| `currentPrizePool` | Advance, Jackpot, GameOver | Yes | Sequential: Advance sets during pool consolidation (J->P transition). Jackpot deducts during daily distribution. GameOver reads/deducts at terminal. Lifecycle phases are mutually exclusive. |
| `nextPrizePool` | Advance, Jackpot, Endgame, Whale | Yes | All additive during purchase phase. Consolidation happens at phase boundary only. |
| `mintPacked_` | Mint, Whale | Yes | Bit-range isolation: Mint writes mint history fields, Whale writes freeze level and bundle type. Different bit ranges via BitPackingLib. |
| `lootboxRngPendingEth` | Advance, Mint, Whale | Yes | Sequential flow: Mint and Whale increment at purchase. Advance resets to 0 when RNG index advances. Accumulate -> threshold -> request -> reset. |
| ... | ... | ... | ... |

**Fill-in instructions:**
- Extract all variables from the mutation matrix where 2+ modules have a W or RW marking.
- For each conflict, determine if it is safe. Common safety patterns:
  1. **Phase gating** -- writes occur in mutually exclusive lifecycle phases (purchase vs. jackpot vs. transition)
  2. **Additive-only pattern** -- all writes increment; only the central contract decrements
  3. **Bit-range isolation** -- different modules write different bit fields in packed variables
  4. **Sequential flow** -- award-then-consume pattern ensures no concurrent writes
  5. **Temporal separation** -- purchase-time writes vs. open-time reads separated by VRF fulfillment
- If a conflict is NOT safe, mark `No` and document the risk in detail.

---

## Section D: Storage Partitioning Rules

Document the conventions that govern which modules "own" which storage variables.

### D.1 Module-Owned Variables

Variables that are exclusively written by a single module. These are effectively "owned" by that module.

```
| Module | Owned Variables | Count |
|--------|----------------|-------|
| AdvanceModule | level, rngLockedFlag, rngWordCurrent, vrfRequestId, levelStartTime, ... | N |
| MintModule | ticketQueue, ticketsOwedPacked, ticketLevel, traitBurnTicket, ... | N |
| JackpotModule | dailyJackpotCoinTicketsPending, dailyEthBucketCursor, dailyEthPhase, ... | N |
| DecimatorModule | decBurn, decBucketBurnTotal, lastDecClaimRound, decBucketOffsetPacked | 4 |
| DegeneretteModule | degeneretteBets, degeneretteBetNonce, dailyHeroWagers, ... | N |
| ...
```

### D.2 Shared State Variables

Variables that are legitimately written by multiple modules. These require cross-module coordination.

```
| Variable | Writers | Coordination Mechanism |
|----------|---------|----------------------|
| claimableWinnings | 7 modules | Additive-only credit pattern |
| claimablePool | 7 modules | Additive-only aggregate tracking |
| futurePrizePool | 5 modules | Phase-gated lifecycle |
| nextPrizePool | 4 modules | Phase-gated lifecycle |
| currentPrizePool | 3 modules | Phase-gated lifecycle |
```

### D.3 Ordering Guarantees

Document the lifecycle ordering that prevents conflicts between modules.

```
PURCHASE PHASE:
  - MintModule, WhaleModule write lootbox/purchase state
  - BoonModule consumes boon state (set by LootboxModule)

TRANSITION:
  - AdvanceModule consolidates pools, advances level
  - No other module writes during transition (phaseTransitionActive guard)

JACKPOT PHASE:
  - JackpotModule distributes currentPrizePool
  - EndgameModule runs BAF/decimator jackpots at level boundaries

TERMINAL:
  - GameOverModule runs final drain after gameOver=true
  - No other module writes after terminal state
```

---

## Section E: Undocumented Write Check

Verify that every storage write found in module source code is accounted for in the audit documentation.

| Module | Documented Writes (audit) | Source-Verified Writes | Undocumented? |
|--------|--------------------------|----------------------|---------------|
| AdvanceModule | [list from audit] | [list from source grep] | None / [list] |
| MintModule | [list from audit] | [list from source grep] | None / [list] |
| ... | ... | ... | ... |

**Fill-in instructions:**
- For each module, extract documented storage writes from the audit reports.
- Separately, grep/search the module source for all storage variable assignments.
- Compare the two lists. Any variable found in source but not in the audit is "undocumented" and must be investigated.

---

## Section F: Summary

| Metric | Count |
|--------|-------|
| Total storage variables/groups | N |
| Modules with write access | N |
| Total module-write cells in matrix | N |
| Variables written by 1 module only | N |
| Variables written by 2+ modules | N |
| Undocumented writes found | N |
| Write conflict concerns | N |

**Safety assessment patterns used:**
1. Phase gating -- purchase vs. jackpot vs. transition phases are mutually exclusive
2. Additive-only pattern -- all writes increment; only the central contract decrements
3. Bit-range isolation -- different modules write different bit fields in packed variables
4. Sequential flow -- award-then-consume pattern ensures no concurrent writes
5. Temporal separation -- purchase-time writes vs. open-time reads separated by external events (e.g., VRF fulfillment)
