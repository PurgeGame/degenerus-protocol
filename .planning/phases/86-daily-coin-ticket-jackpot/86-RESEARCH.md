# Phase 86: Daily Coin + Ticket Jackpot - Research

**Researched:** 2026-03-23
**Domain:** Solidity smart contract audit -- BURNIE (coin) jackpot winner selection and ticket jackpot distribution
**Confidence:** HIGH

## Summary

Phase 86 requires exhaustive tracing of three interrelated subsystems within the Degenerus Protocol's daily jackpot mechanics: (1) the BURNIE coin jackpot winner selection path, including both the near-future trait-matched path and the far-future ticketQueue-based path via `_awardFarFutureCoinJackpot`; (2) the ticket jackpot winner selection and distribution path via `_distributeTicketJackpot`; and (3) the `jackpotCounter` lifecycle that governs how many daily jackpots run per level.

All three subsystems live primarily in `DegenerusGameJackpotModule.sol` (2794 lines), with orchestration from `DegenerusGameAdvanceModule.sol` (1558 lines) and storage declarations in `DegenerusGameStorage.sol` (1622 lines). The coin jackpot has two entry points: `payDailyCoinJackpot` (purchase phase, JM:2360) and `payDailyJackpotCoinAndTickets` (jackpot phase, JM:681). Both split the coin budget 75% near-future / 25% far-future. The ticket jackpot distributes lootbox-equivalent ticket units to trait-matched winners and is embedded within `payDailyJackpotCoinAndTickets` (lines 730-753).

The v3.8 commitment window inventory contains **at least one stale claim** about the far-future coin jackpot path: it describes "readKey derived from level + write slot" at the winner selection point, but the current code at JM:2543 uses `_tqFarFutureKey(candidate)` -- the dedicated far-future key space introduced in v3.9 Phase 74. This discrepancy was partially noted by Phase 81 (DSC-01) but the specific v3.8 Category 3 backward trace has not been verified against current code. The audit must independently verify every claim with file:line citations from the current codebase.

**Primary recommendation:** Structure the audit into two plans -- Plan 01 covering coin jackpot winner selection (both near-future and far-future paths, including _awardFarFutureCoinJackpot) and jackpotCounter lifecycle; Plan 02 covering ticket jackpot distribution mechanics. Both plans must flag every discrepancy between prior audit prose and current code.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DCOIN-01 | Coin jackpot winner selection path documented with file:line (including _awardFarFutureCoinJackpot) | Two entry points identified: `payDailyCoinJackpot` (JM:2360, purchase phase) and `payDailyJackpotCoinAndTickets` (JM:681, jackpot phase). Both call `_awardFarFutureCoinJackpot` (JM:2521) for 25% far-future portion and `_awardDailyCoinToTraitWinners` (JM:2418) for 75% near-future portion. Winner selection uses `_randTraitTicketWithIndices` (JM:2283) for near-future and `ticketQueue[_tqFarFutureKey(candidate)]` (JM:2543) for far-future. |
| DCOIN-02 | Ticket jackpot winner selection path documented with file:line | Three call sites for `_distributeTicketJackpot` (JM:1105): daily tickets at JM:733, carryover tickets at JM:745, and early-bird lootbox at JM:1093. All select winners via `_randTraitTicket` (JM:2237) from `traitBurnTicket[lvl]`, distribute ticket units via `_queueTickets` (JM:1209). |
| DCOIN-03 | jackpotCounter lifecycle (initialization, increment, read, reset) fully traced | Storage at GS:245 (uint8, EVM slot 0, offset 22). Reset to 0 at `_endPhase` (AM:481). Incremented by counterStep at JM:757. Read at JM:349 (counterStep computation), AM:224 (bonusFlip), AM:364 (JACKPOT_LEVEL_CAP check), MM:971 (affiliate bonus timing). Cap is JACKPOT_LEVEL_CAP=5 (JM:108). |
| DCOIN-04 | Every discrepancy and new finding tagged | Key discrepancy identified: v3.8 commitment window inventory Category 3 backward trace (line 420-422) describes "readKey derived from level + write slot" but current code uses `_tqFarFutureKey`. Additional v3.8 claims at lines 406, 412, 2411, 2460 need file:line verification against current code. |
</phase_requirements>

## Architecture Patterns

### Coin Jackpot Call Graph

```
advanceGame() [AM:128]
  |
  |-- PURCHASE PHASE (inJackpot=false, !lastPurchaseDay):
  |   |-- payDailyJackpot(false, lvl, rngWord)   [AM:282, delegatecall to JM:323]
  |   |-- _payDailyCoinJackpot(lvl, rngWord)      [AM:283, delegatecall to JM:2360]
  |       |-- _calcDailyCoinBudget(lvl)            [JM:2361 -> JM:2647]
  |       |-- _awardFarFutureCoinJackpot(lvl, farBudget, rngWord)  [JM:2369 -> JM:2521]
  |       |   |-- ticketQueue[_tqFarFutureKey(candidate)]           [JM:2543]
  |       |   |-- coin.creditFlipBatch(winners, amounts)            [JM:2587/2604]
  |       |-- _selectDailyCoinTargetLevel(lvl, traits, entropy)     [JM:2388 -> JM:2405]
  |       |-- _awardDailyCoinToTraitWinners(targetLvl, traits, nearBudget, entropy) [JM:2395 -> JM:2418]
  |           |-- _computeBucketCounts(lvl, traitIds, cap, entropy) [JM:2431 -> JM:1222]
  |           |-- _randTraitTicketWithIndices(traitBurnTicket[lvl], ...) [JM:2458 -> JM:2283]
  |           |-- coin.creditFlipBatch(winners, amounts)             [JM:2488/2514]
  |
  |-- JACKPOT PHASE (inJackpot=true):
  |   |-- payDailyJackpot(true, lvl, rngWord)      [AM:379, delegatecall to JM:323]
  |   |   |-- (Phase 0 + Phase 1 ETH distribution)
  |   |   |-- _clearDailyEthState() sets dailyJackpotCoinTicketsPending=true [JM:2792]
  |   |
  |   |-- payDailyJackpotCoinAndTickets(rngWord)   [AM:363, delegatecall to JM:681]
  |       |-- _calcDailyCoinBudget(lvl)             [JM:703]
  |       |-- _awardFarFutureCoinJackpot(...)       [JM:707 -> JM:2521]
  |       |-- _awardDailyCoinToTraitWinners(...)    (via _selectDailyCoinTargetLevel) [JM:714-727]
  |       |-- _distributeTicketJackpot(lvl, ..., dailyTicketUnits)    [JM:733]
  |       |-- _distributeTicketJackpot(carryoverLvl, ..., carryoverTicketUnits)  [JM:745]
  |       |-- jackpotCounter += counterStep          [JM:757]
  |       |-- dailyJackpotCoinTicketsPending = false [JM:761]
```

### Ticket Jackpot Call Graph

```
payDailyJackpotCoinAndTickets(rngWord) [JM:681]
  |-- _distributeTicketJackpot(lvl, winningTraitsPacked, dailyTicketUnits, entropy, LOOTBOX_MAX_WINNERS, 241) [JM:733]
  |-- _distributeTicketJackpot(carryoverSourceLevel, winningTraitsPacked, carryoverTicketUnits, entropy, LOOTBOX_MAX_WINNERS, 240) [JM:745]
  |
  |   _distributeTicketJackpot(lvl, traits, units, entropy, maxWinners, saltBase) [JM:1105]
  |     |-- JackpotBucketLib.unpackWinningTraits(winningTraitsPacked) [JM:1115]
  |     |-- _computeBucketCounts(lvl, traitIds, cap, entropy)         [JM:1121 -> JM:1222]
  |     |-- _distributeTicketsToBuckets(lvl, traitIds, counts, units, entropy, cap, saltBase) [JM:1129 -> JM:1141]
  |         |-- _distributeTicketsToBucket(lvl, traitId, count, entropy, salt, baseUnits, distParams, cap, globalIdx) [JM:1159 -> JM:1178]
  |             |-- _randTraitTicket(traitBurnTicket[lvl], entropy, traitId, count, salt) [JM:1190 -> JM:2237]
  |             |-- _queueTickets(winner, lvl+1, units)               [JM:1209]
```

### jackpotCounter Lifecycle

```
INITIALIZATION:
  _endPhase()                       [AM:475]
    jackpotCounter = 0              [AM:481]

READ (determines behavior):
  advanceGame():
    bonusFlip = (inJackpot && jackpotCounter == 0)  [AM:224]
    jackpotCounter >= JACKPOT_LEVEL_CAP             [AM:364]

  payDailyJackpot() (in JM):
    counter = jackpotCounter                         [JM:349]
    counterStep = 1 (normal) | 2 (compressed) | 5 (turbo)  [JM:350-354]
    isFinalPhysicalDay = (counter + counterStep >= 5)       [JM:362]
    isFinalPhysicalDay_ = (jackpotCounter + counterStep_ >= 5) [JM:484]

  MintModule (affiliate bonus):
    _cnt = jackpotCounter                            [MM:971]
    _nextStep = compressed? 2 : 1                    [MM:972]
    if (_cnt + _nextStep >= JACKPOT_LEVEL_CAP)...    [MM:973]

INCREMENT:
  payDailyJackpotCoinAndTickets():
    jackpotCounter += counterStep                    [JM:757]
    (counterStep packed in dailyTicketBudgetsPacked, unpacked at JM:686-690)

RESET:
  _endPhase():
    jackpotCounter = 0                               [AM:481]
    (called when jackpotCounter >= JACKPOT_LEVEL_CAP at AM:364)
```

### Key Constants

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| JACKPOT_LEVEL_CAP | 5 | JM:108 | Max jackpots per level |
| FAR_FUTURE_COIN_BPS | 2500 | JM:206 | 25% of coin budget to FF holders |
| FAR_FUTURE_COIN_SAMPLES | 10 | JM:209 | Max FF levels sampled |
| DAILY_COIN_MAX_WINNERS | 50 | JM:200 | Cap on near-future coin winners |
| MAX_BUCKET_WINNERS | 250 | JM:183 | Per-trait bucket winner cap |
| LOOTBOX_MAX_WINNERS | 100 | JM:217 | Cap on ticket jackpot winners |
| DAILY_COIN_SALT_BASE | 252 | JM:203 | Entropy salt for coin winner selection |
| COIN_JACKPOT_TAG | keccak256("coin-jackpot") | JM:132 | Domain separator for near-future coin entropy |
| FAR_FUTURE_COIN_TAG | keccak256("far-future-coin") | JM:213 | Domain separator for FF coin entropy |
| PRICE_COIN_UNIT | 1000 ether | GS:125 | ETH-to-BURNIE conversion unit |

### Two Coin Jackpot Entry Points

**1. Purchase phase: `payDailyCoinJackpot` (JM:2360)**
- Called from AdvanceModule:283 via `_payDailyCoinJackpot` (delegatecall wrapper at AM:616)
- Rolls winning traits if not already stored for this day
- Does NOT increment jackpotCounter (purchase phase manages this differently)
- Only called when `!inJackpot && !lastPurchaseDay`

**2. Jackpot phase: `payDailyJackpotCoinAndTickets` (JM:681)**
- Called from AdvanceModule:363 when `dailyJackpotCoinTicketsPending` is true
- Uses stored values from Phase 1 (lastDailyJackpotLevel, lastDailyJackpotWinningTraits)
- Increments jackpotCounter by counterStep (JM:757)
- Also distributes ticket jackpot (daily + carryover)

### Winner Selection Mechanisms

**Near-future coin winners (75% of budget):**
- `_selectDailyCoinTargetLevel` picks one random level in [lvl, lvl+4] (JM:2410)
- Returns 0 (skip entire near-future portion) if chosen level has no trait tickets
- `_awardDailyCoinToTraitWinners` (JM:2418) distributes via 4-bucket trait system
- Winners selected from `traitBurnTicket[targetLevel][traitId]` via `_randTraitTicketWithIndices` (JM:2458)
- Up to DAILY_COIN_MAX_WINNERS (50) total, split across active buckets
- Awards via `coin.creditFlipBatch` (batches of 3)

**Far-future coin winners (25% of budget):**
- `_awardFarFutureCoinJackpot` (JM:2521) samples up to 10 random levels in [lvl+5, lvl+99]
- Reads from `ticketQueue[_tqFarFutureKey(candidate)]` (JM:2543)
- One winner per sampled level: `queue[(entropy >> 32) % len]` (JM:2547)
- Budget split evenly among found winners: `perWinner = farBudget / found` (JM:2565)
- Awards via `coin.creditFlipBatch` (batches of 3)

**Ticket jackpot winners:**
- `_distributeTicketJackpot` (JM:1105) uses same 4-bucket trait system as coin
- Winners selected from `traitBurnTicket[lvl][traitId]` via `_randTraitTicket` (JM:1190)
- Up to LOOTBOX_MAX_WINNERS (100) total across buckets
- Each winner receives tickets via `_queueTickets(winner, lvl+1, units)` (JM:1209)
- Ticket units computed from `_budgetToTicketUnits(budget, targetLevel)` using `PriceLookupLib.priceForLevel`

## Common Pitfalls

### Pitfall 1: Confusing the Two Coin Jackpot Entry Points
**What goes wrong:** Auditor traces only `payDailyCoinJackpot` and misses `payDailyJackpotCoinAndTickets` (or vice versa). The two share `_awardFarFutureCoinJackpot` and `_awardDailyCoinToTraitWinners` but have different trait derivation and counterStep logic.
**Why it happens:** Similar function names, both called from AdvanceModule in different game phases.
**How to avoid:** Document both entry points side by side with their caller context. Verify both call `_awardFarFutureCoinJackpot`.
**Warning signs:** Mentioning only one entry point in the coin jackpot trace.

### Pitfall 2: Stale Prior Audit References
**What goes wrong:** Trusting v3.8 commitment window inventory line numbers or claims without verification. The v3.8 doc references JM:2361-2402, JM:2411, JM:2460, JM:2651 which may have drifted due to code additions/removals since that audit.
**Why it happens:** Code has been modified multiple times since v3.8. The v3.9 FF key introduction added code, and the combined pool revert removed code, both shifting line numbers.
**How to avoid:** Every file:line citation must be verified against current code. Treat v3.8 line numbers as approximate.
**Warning signs:** Citing v3.8 line numbers without "[CONFIRMED]" or "[DRIFTED]" annotation.

### Pitfall 3: Missing the jackpotCounter Read in MintModule
**What goes wrong:** Auditor traces only the JackpotModule and AdvanceModule references to `jackpotCounter`, missing the MintModule read at MM:971.
**Why it happens:** `jackpotCounter` is primarily associated with jackpot logic, so MintModule is not the first place to look.
**How to avoid:** The grep results show 4 files reference `jackpotCounter`. All must be documented.
**Warning signs:** Only listing 3 files in the jackpotCounter lifecycle.

### Pitfall 4: Near-Future Coin Level Selection Can Return 0
**What goes wrong:** Assuming coin jackpot always awards coins. `_selectDailyCoinTargetLevel` (JM:2405) checks ONE random level in [lvl, lvl+4] and returns 0 if no trait tickets exist at that level. No fallback to other levels.
**Why it happens:** The 1-in-5 random selection is not obvious from the function name.
**How to avoid:** Document the 0-return case explicitly. Note that when targetLevel=0, the entire near-future coin budget is silently skipped (not rolled over).

### Pitfall 5: Ticket Jackpot Winners Receive Tickets for lvl+1 Not lvl
**What goes wrong:** Assuming tickets target the current jackpot level. `_distributeTicketsToBucket` calls `_queueTickets(winner, lvl + 1, units)` at JM:1209 -- tickets target the NEXT level.
**Why it happens:** Easy to overlook the `+ 1` offset.
**How to avoid:** Explicitly document the target level in the ticket distribution trace.

## Prior Audit Claims Requiring Verification

The following claims from prior audits must be independently verified with current file:line citations. Any discrepancy or drift must be tagged [DISCREPANCY] or [DRIFTED].

### v3.8 Commitment Window Inventory -- Category 3

| Claim | v3.8 Reference | What It Says | Verify Against |
|-------|----------------|--------------|----------------|
| Coin jackpot computation location | Line 406 | JM:2361-2402 and JM:681-766 | Current payDailyCoinJackpot at JM:2360 (1-line drift?) and payDailyJackpotCoinAndTickets at JM:681 |
| Near-future winner from traitBurnTicket | Line 412 | JM:2460 | Current _randTraitTicketWithIndices call (verify line) |
| Target level = lvl + (entropy % 5) | Line 413 | JM:2411 | Current _selectDailyCoinTargetLevel call (verify line) |
| FF winner from ticketQueue[readKey] | Line 420-422 | "readKey derived from level + write slot" | **KNOWN STALE**: Current code at JM:2543 uses `_tqFarFutureKey(candidate)`, not readKey. DSC-01 partially covers this but v3.8 Cat 3 trace is more specific. |
| Payout from levelPrizePool formula | Line 425 | JM:2651 | Current _calcDailyCoinBudget at JM:2647-2651 (verify line) |
| jackpotCounter increment | Line 395 | "Incremented by payDailyJackpotCoinAndTickets each day" | JM:757 -- verify increment mechanism matches |

### v3.8 Commitment Window Inventory -- Section 4 (Summary)

| Claim | v3.8 Line | What It Says | Status |
|-------|-----------|--------------|--------|
| jackpotCounter at slot 0 offset 22 | Line 3486 | "Incremented by payDailyJackpotCoinAndTickets (JM:757)" | Verify JM:757 in current code |
| jackpotCounter not writable by external/permissionless function | Line 3486 | "Not writable by any external/permissionless function" | Verify: only advanceGame flow writes it |

### v3.8 TQ-01 Fix Status

| Claim | v3.8 Context | Current Status |
|-------|--------------|----------------|
| _awardFarFutureCoinJackpot read from write buffer | v3.8 Section 5 (line 3528, 3954) | **FIXED**: Current code at JM:2543 uses `_tqFarFutureKey`, not `_tqWriteKey`. Fix applied in v3.9. |

### Phase 81 DSC-01 Cross-Reference

Phase 81 flagged that the v3.9 RNG commitment window proof describes a combined pool approach in `_awardFarFutureCoinJackpot`. Current code reads ONLY from `_tqFarFutureKey`. This is a known discrepancy (INFO severity). Phase 86 should confirm the current code path independently without relying on Phase 81's findings.

## Recommended Audit Plan Structure

### Plan 01: Coin Jackpot Winner Selection + jackpotCounter

**Scope:** DCOIN-01, DCOIN-03, DCOIN-04

**Tasks:**
1. Trace `payDailyCoinJackpot` (JM:2360) end-to-end with file:line
   - `_calcDailyCoinBudget` budget derivation
   - 75/25 near-future/far-future split
   - Near-future: `_selectDailyCoinTargetLevel` -> `_awardDailyCoinToTraitWinners` -> `_randTraitTicketWithIndices`
   - Far-future: `_awardFarFutureCoinJackpot` -> `ticketQueue[_tqFarFutureKey(candidate)]`
2. Trace `payDailyJackpotCoinAndTickets` (JM:681) coin portion with file:line
   - Unpacking stored values from Phase 1
   - Same 75/25 split as payDailyCoinJackpot
   - Entropy derivation differences from payDailyCoinJackpot
3. jackpotCounter full lifecycle
   - Storage: GS:245 (uint8, slot 0 offset 22)
   - Init: AM:481 (reset to 0 in _endPhase)
   - Read: JM:349, JM:484, AM:224, AM:364, MM:971-973
   - Write: JM:757 (counterStep increment)
   - counterStep computation: JM:349-363 (normal=1, compressed=2, turbo=5)
4. Verify v3.8 commitment window inventory Category 3 claims against current code
5. Flag all discrepancies and new findings

### Plan 02: Ticket Jackpot Distribution

**Scope:** DCOIN-02, DCOIN-04

**Tasks:**
1. Trace `_distributeTicketJackpot` (JM:1105) end-to-end with file:line
   - `_computeBucketCounts` (JM:1222) -- 4-bucket sizing logic
   - `_distributeTicketsToBuckets` (JM:1141) -> `_distributeTicketsToBucket` (JM:1178)
   - Winner selection via `_randTraitTicket` (JM:2237) from `traitBurnTicket[lvl]`
   - Ticket queuing via `_queueTickets(winner, lvl+1, units)` (JM:1209)
2. Enumerate all callers of `_distributeTicketJackpot`
   - Daily tickets: JM:733 (in payDailyJackpotCoinAndTickets, saltBase=241)
   - Carryover tickets: JM:745 (in payDailyJackpotCoinAndTickets, saltBase=240)
   - Early-bird lootbox: JM:1093 (in _distributeLootboxAndTickets, saltBase=242)
3. Budget computation chain
   - `_budgetToTicketUnits(budget, lvl)` at JM:1063-1070
   - `_packDailyTicketBudgets` / `_unpackDailyTicketBudgets` (JM:2753-2782)
4. Cross-reference ticket paths with Phase 81 findings
5. Flag all discrepancies and new findings

## Code Examples

### Near-Future Coin Budget Calculation (JM:2647-2651)

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2647-2651
function _calcDailyCoinBudget(uint24 lvl) private view returns (uint256) {
    uint256 priceWei = price;
    if (priceWei == 0) return 0;
    return (levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 200);
}
// Note: PRICE_COIN_UNIT = 1000 ether (GS:125)
// This yields 0.5% of prize pool target in BURNIE units
```

### Far-Future Winner Selection (JM:2537-2554)

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:2537-2554
for (uint8 s; s < FAR_FUTURE_COIN_SAMPLES; ) {
    entropy = EntropyLib.entropyStep(entropy ^ uint256(s));
    uint24 candidate = lvl + 5 + uint24(entropy % 95);  // [lvl+5, lvl+99]
    address[] storage queue = ticketQueue[_tqFarFutureKey(candidate)];  // FF key, NOT read/write key
    uint256 len = queue.length;
    if (len != 0) {
        address winner = queue[(entropy >> 32) % len];
        if (winner != address(0)) {
            winners[found] = winner;
            winnerLevels[found] = candidate;
            unchecked { ++found; }
        }
    }
    unchecked { ++s; }
}
```

### jackpotCounter Increment (JM:757)

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:757
unchecked {
    jackpotCounter += counterStep;
}
// counterStep is unpacked from dailyTicketBudgetsPacked (JM:686-690)
// Values: 1 (normal), 2 (compressed, flag=1, counter>0 && <4), 5 (turbo, flag=2, counter==0)
```

### Ticket Jackpot Winner Gets Next-Level Tickets (JM:1208-1209)

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1208-1209
if (winner != address(0) && units != 0) {
    _queueTickets(winner, lvl + 1, uint32(units));  // NOTE: lvl+1, not lvl
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-contract DegenerusGameJackpotModule -x` |
| Full suite command | `forge test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DCOIN-01 | Coin jackpot winner selection path | manual-only | N/A (audit documentation, no code changes) | N/A |
| DCOIN-02 | Ticket jackpot winner selection path | manual-only | N/A (audit documentation, no code changes) | N/A |
| DCOIN-03 | jackpotCounter lifecycle | manual-only | N/A (audit documentation, no code changes) | N/A |
| DCOIN-04 | Discrepancy detection | manual-only | N/A (audit documentation, no code changes) | N/A |

### Sampling Rate
- **Per task commit:** N/A -- pure audit phase, no code changes
- **Per wave merge:** N/A
- **Phase gate:** Audit document review by human before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. This is a pure documentation/audit phase with no code changes, so no new test files are needed.

## Open Questions

1. **counterStep stored vs computed**
   - What we know: counterStep is computed in `payDailyJackpot` (JM:349-363), packed into `dailyTicketBudgetsPacked` (JM:459), and unpacked in `payDailyJackpotCoinAndTickets` (JM:686-690) for the increment at JM:757.
   - What's unclear: Whether the compressed/turbo flag can change between the two calls (it should not, since both run within the same level, but needs verification).
   - Recommendation: Verify `compressedJackpotFlag` is not modified between `payDailyJackpot` and `payDailyJackpotCoinAndTickets`.

2. **Near-future coin target level = 0 behavior**
   - What we know: `_selectDailyCoinTargetLevel` returns 0 when the randomly chosen level has no trait tickets. The near-future budget is silently skipped.
   - What's unclear: Whether this is intentional design or a potential INFO finding (budget not redistributed).
   - Recommendation: Document the skip behavior. Likely intentional (random daily mechanic), but flag if budget accumulation concern exists.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- direct code reading, all line references verified
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- orchestration logic, delegatecall wrappers verified
- `contracts/storage/DegenerusGameStorage.sol` -- storage slot layout, jackpotCounter declaration verified
- `contracts/modules/DegenerusGameMintModule.sol` -- jackpotCounter read at MM:971 verified

### Secondary (MEDIUM confidence)
- `audit/v3.8-commitment-window-inventory.md` -- Category 3 claims identified for verification (line numbers may have drifted)
- `audit/v4.0-findings-consolidated.md` -- DSC-01 and DSC-02 context, Phase 81 results
- `audit/v4.0-ticket-creation-queue-mechanics.md` -- Phase 81 audit document, cross-reference for ticket paths

### Tertiary (LOW confidence)
- None -- all findings based on direct code reading

## Metadata

**Confidence breakdown:**
- Coin jackpot path: HIGH -- both entry points and all subroutines directly read from source
- Ticket jackpot path: HIGH -- _distributeTicketJackpot and all callers traced from source
- jackpotCounter lifecycle: HIGH -- all 4 files with references grep-identified and verified
- Prior audit discrepancies: MEDIUM -- stale v3.8 claims identified but exact line drift requires per-line verification during audit execution

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (stable -- contracts are pre-audit frozen)
