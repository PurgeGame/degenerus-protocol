# Phase 57: Gas Ceiling Analysis - Research

**Researched:** 2026-03-21
**Domain:** Solidity gas profiling, worst-case analysis, block gas limit safety
**Confidence:** HIGH

## Summary

This phase performs worst-case gas ceiling analysis for the two most complex public-facing transaction paths in the Degenerus Protocol: `advanceGame()` and `purchase()`. The protocol uses a conservative 14M gas ceiling (Ethereum mainnet block limit is 30M, but the protocol targets half to ensure reliable inclusion).

The architecture is a delegatecall-module pattern: `DegenerusGame.sol` is the entry point, which delegatecalls into specialized modules (AdvanceModule, JackpotModule, MintModule, EndgameModule, GameOverModule). All modules share `DegenerusGameStorage` slot layout. The key gas concern is that `advanceGame()` has multiple code paths (jackpot daily, transition, purchase-phase daily, gameover), each of which contains loops bounded by different constants (DAILY_ETH_MAX_WINNERS=321, JACKPOT_MAX_WINNERS=300, WRITES_BUDGET_SAFE=550, etc.). The protocol already applies gas budgeting (the `_processDailyEthChunk` function uses a `unitsBudget` of 1000 to chunk winner distribution across multiple calls), but the question is whether ALL paths stay safely under 14M in their absolute worst case.

For `purchase()`, the primary gas consumers are: the ticket queuing path (which is O(1) per call -- just appends to a queue), the lootbox purchase path (multiple storage writes, external calls to affiliate contract, BURNIE credit), and the `recordMint` self-call (prize pool splitting, earlybird DGNRS). The question is: what is the maximum batch size a single purchase call can handle under 14M?

**Primary recommendation:** Perform static gas analysis by identifying every loop, external call, and storage operation in each path, compute per-iteration gas costs from EVM opcode costs, and derive maximum safe iteration counts at the 14M ceiling. Cross-validate with Foundry gas snapshots where a full-deploy test harness exists.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CEIL-01 | advanceGame worst-case gas profiled across every code path (jackpot, transition, daily, gameover) | Full call graph mapped for all 4+ code paths with loop bounds and external calls identified |
| CEIL-02 | Maximum jackpot payouts per path computed such that no path exceeds 14M gas | Winner count constants (321, 300, 250, 100, 50, 107) and chunking budgets (UNITS_SAFE=1000, WRITES_BUDGET=550) documented |
| CEIL-03 | Ticket minting (purchase) worst-case gas profiled | purchase() call graph mapped: _purchaseFor -> _callTicketPurchase -> recordMint self-call chain |
| CEIL-04 | Maximum ticket batch size computed such that purchase never exceeds 14M gas | purchase() is O(1) per call (queue append), but lootbox+ticket combined paths have multiple external calls |
| CEIL-05 | Current headroom documented (how far below 14M each worst-case path sits today) | All constants and bounds identified for headroom computation |
</phase_requirements>

## Architecture Patterns

### advanceGame() Call Graph

The `advanceGame()` function in `DegenerusGame.sol` (line 316) delegatecalls to `DegenerusGameAdvanceModule.advanceGame()` (line 126). This function has a single `do {} while(false)` block that branches into one of several terminal stages per call:

```
advanceGame() [DegenerusGame.sol:316]
  -> delegatecall AdvanceModule.advanceGame() [AdvanceModule:126]
     |
     +-- _handleGameOverPath() [AdvanceModule:419]
     |   -> delegatecall GameOverModule.handleGameOverDrain()
     |   OR -> delegatecall GameOverModule.handleFinalSweep()
     |
     +-- Mid-day path (day == dailyIdx) [AdvanceModule:162]
     |   -> _runProcessTicketBatch() -> delegatecall JackpotModule.processTicketBatch()
     |   -> _swapTicketSlot() (jackpot phase only)
     |
     +-- New-day path (day != dailyIdx) [AdvanceModule:231]
         |
         +-- RNG request path [AdvanceModule:234-239]
         |   -> _swapAndFreeze(), rngGate() -> VRF request
         |
         +-- Phase transition [AdvanceModule:242-254]
         |   -> _processPhaseTransition() (queues 32 tickets + stETH stake)
         |
         +-- Future tickets [AdvanceModule:258-269]
         |   -> _prepareFutureTickets() -> _processFutureTicketBatch() x5 levels
         |
         +-- Ticket processing [AdvanceModule:272-278]
         |   -> _runProcessTicketBatch() -> JackpotModule.processTicketBatch()
         |
         +-- PURCHASE PHASE (!inJackpot) [AdvanceModule:282-341]
         |   +-- Pre-target: payDailyJackpot(false) + _payDailyCoinJackpot()
         |   +-- Post-target (lastPurchaseDay): consolidation + enter jackpot
         |       -> _applyTimeBasedFutureTake(), _consolidatePrizePools()
         |       -> _drawDownFuturePrizePool(), _runEarlyBirdLootboxJackpot()
         |
         +-- JACKPOT PHASE (inJackpot) [AdvanceModule:344-379]
             +-- Resume: payDailyJackpot(true, ...) [resuming ETH distribution]
             +-- Coin+tickets: payDailyJackpotCoinAndTickets()
             |   -> if counter >= 5: _awardFinalDayDgnrsReward() + _rewardTopAffiliate()
             |   -> _runRewardJackpots() -> EndgameModule.runRewardJackpots()
             |   -> _endPhase()
             +-- Fresh daily: payDailyJackpot(true, ...)
```

### advanceGame() Code Path Classification

Each call to `advanceGame()` executes exactly ONE stage and returns. The stages are:

| Stage | Constant | Description | Key Gas Consumers |
|-------|----------|-------------|-------------------|
| GAMEOVER (0) | `STAGE_GAMEOVER` | Liveness guard triggered | handleGameOverDrain: deity loop (unbounded!), decimator, terminal jackpot |
| RNG_REQUESTED (1) | `STAGE_RNG_REQUESTED` | VRF word requested | _swapAndFreeze, VRF external call |
| TRANSITION_WORKING (2) | `STAGE_TRANSITION_WORKING` | Phase transition in progress | _processPhaseTransition (light: 2 queue ops + stETH) |
| TRANSITION_DONE (3) | `STAGE_TRANSITION_DONE` | Phase transition complete | Same as above (single call) |
| FUTURE_TICKETS_WORKING (4) | `STAGE_FUTURE_TICKETS_WORKING` | Processing near-future ticket queues | processTicketBatch (WRITES_BUDGET_SAFE=550) |
| TICKETS_WORKING (5) | `STAGE_TICKETS_WORKING` | Processing current level tickets | processTicketBatch (WRITES_BUDGET_SAFE=550) |
| PURCHASE_DAILY (6) | `STAGE_PURCHASE_DAILY` | Daily jackpot during purchase phase | payDailyJackpot(false) + _payDailyCoinJackpot |
| ENTERED_JACKPOT (7) | `STAGE_ENTERED_JACKPOT` | Transition from purchase to jackpot phase | consolidation + earlybird lootbox (100 winners loop) |
| JACKPOT_ETH_RESUME (8) | `STAGE_JACKPOT_ETH_RESUME` | Resuming daily ETH distribution | payDailyJackpot chunked (UNITS_SAFE=1000) |
| JACKPOT_COIN_TICKETS (9) | `STAGE_JACKPOT_COIN_TICKETS` | Coin+ticket distribution | payDailyJackpotCoinAndTickets |
| JACKPOT_PHASE_ENDED (10) | `STAGE_JACKPOT_PHASE_ENDED` | Level transition complete | coin+tickets + rewardJackpots + endPhase |
| JACKPOT_DAILY_STARTED (11) | `STAGE_JACKPOT_DAILY_STARTED` | Fresh daily jackpot started | payDailyJackpot(true) -- full daily init + Phase 0 chunk |

### purchase() Call Graph

```
purchase() [DegenerusGame.sol:542]
  -> _resolvePlayer()
  -> _purchaseFor() -> delegatecall MintModule.purchase() [MintModule:551]
     -> _purchaseFor() [MintModule:619]
        |
        +-- Ticket purchase (if ticketQuantity != 0)
        |   -> _callTicketPurchase() [MintModule:831]
        |      -> consumePurchaseBoost() [self-call]
        |      -> recordMint{value}() [self-call, not delegatecall]
        |      |   -> _processMintPayment()
        |      |   -> _recordMintDataModule() -> delegatecall MintModule
        |      |   -> _awardEarlybirdDgnrs()
        |      -> affiliate.payAffiliate() [external call]
        |      -> coin.creditFlip() [external call]
        |      -> _queueTicketsScaled() [O(1) storage append]
        |
        +-- Lootbox purchase (if lootBoxAmount != 0)
        |   -> lootboxEth storage writes
        |   -> _applyLootboxBoostOnPurchase()
        |   -> _maybeRequestLootboxRng() [potential VRF external call]
        |   -> prize pool split writes
        |   -> affiliate.payAffiliate() [external call x2 if combined payment]
        |   -> coin.creditFlip() + coin.notifyQuestMint() + coin.notifyQuestLootBox()
        |   -> _awardEarlybirdDgnrs()
        |
        +-- Bonus credit (if spent all claimable)
            -> coin.creditFlip()
```

### Key Gas Constants and Bounds

| Constant | Value | Used By | Gas Implication |
|----------|-------|---------|-----------------|
| `WRITES_BUDGET_SAFE` | 550 | processTicketBatch | Max SSTORE operations per batch (first batch: 357 at 65%) |
| `DAILY_JACKPOT_UNITS_SAFE` | 1000 | _processDailyEthChunk | Winner unit budget per chunk (auto-rebuy=3 units, normal=1) |
| `DAILY_ETH_MAX_WINNERS` | 321 | payDailyJackpot | Max ETH winners across daily+carryover (Phase 0 + Phase 1) |
| `JACKPOT_MAX_WINNERS` | 300 | _executeJackpot (early-burn) | Max winners for non-daily (early-burn) jackpots |
| `MAX_BUCKET_WINNERS` | 250 | _resolveTraitWinners | Per-bucket cap (fits uint8) |
| `DAILY_COIN_MAX_WINNERS` | 50 | payDailyCoinJackpot | Max BURNIE jackpot winners |
| `LOOTBOX_MAX_WINNERS` | 100 | lootbox distributions | Max winners for lootbox jackpots |
| `DAILY_CARRYOVER_MIN_WINNERS` | 20 | carryover ETH | Minimum carryover winners |
| `FAR_FUTURE_COIN_SAMPLES` | 10 | _awardFarFutureCoinJackpot | Fixed loop bound |
| `JACKPOT_LEVEL_CAP` | 5 | Jackpot phase counter | 5 daily jackpots per level |
| `DAILY_JACKPOT_UNITS_AUTOREBUY` | 3 | _winnerUnits | Auto-rebuy costs 3x budget |

### Gas Cost Per Operation (EVM Reference)

| Operation | Gas Cost | Notes |
|-----------|----------|-------|
| SSTORE (cold, zero->nonzero) | 22,100 | First write to a slot |
| SSTORE (cold, nonzero->nonzero) | 5,000 | Overwrite existing |
| SSTORE (warm) | 100 | Already accessed this tx |
| SLOAD (cold) | 2,100 | First read of slot |
| SLOAD (warm) | 100 | Already accessed |
| External CALL (cold) | 2,600 + exec | First call to address |
| External CALL (warm) | 100 + exec | Already called address |
| DELEGATECALL | 2,600 (cold) | Module invocations |
| LOG (per topic) | 375 + 8/byte | Event emission |
| Memory expansion | Quadratic | Large arrays cost more |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gas measurement | Manual opcode counting alone | Foundry `forge test --gas-report` + `forge snapshot` | Manual counts miss compiler optimizations, memory expansion, and cross-contract interaction costs |
| Worst-case construction | Guessing worst case | Systematic enumeration of each branch with maximum loop iterations | Missing a single code path could leave a DoS vector |
| Cross-validation | Single methodology | Static analysis + Foundry gas measurement | Static analysis catches structural maximums; Foundry catches real compiler output costs |

## Common Pitfalls

### Pitfall 1: Ignoring Delegatecall Chain Gas
**What goes wrong:** Counting gas for only the top-level function, missing that delegatecall adds ~2,600 gas per module invocation, and the called module may itself contain loops.
**Why it happens:** The call graph spans 6+ contracts via delegatecall. A single advanceGame call can touch AdvanceModule -> JackpotModule -> EndgameModule.
**How to avoid:** Trace the FULL call graph for each stage. Count all delegatecall hops (typically 2-3 per advanceGame call).
**Warning signs:** Gas estimate that seems too low for a path with known loops.

### Pitfall 2: Confusing Per-Call vs Per-Level Gas
**What goes wrong:** Reporting gas for the entire level transition (which spans multiple advanceGame calls) instead of per-call worst case.
**Why it happens:** The chunking system deliberately splits work across calls. The daily jackpot ETH distribution (Phase 0 + Phase 1) can span 2+ advanceGame calls due to unitsBudget=1000.
**How to avoid:** Analyze each STAGE independently. A single advanceGame() call exits after completing exactly one stage.
**Warning signs:** Gas estimates above 14M that assume multiple stages execute in one call.

### Pitfall 3: Missing the Gameover Path
**What goes wrong:** The gameover path has an unbounded deity pass owner loop (`deityPassOwners.length` in GameOverModule:82). If many deity passes were purchased, this loop could exceed 14M.
**Why it happens:** This is a one-time event with a loop over a dynamic array.
**How to avoid:** Compute maximum deity pass count from the protocol's purchase mechanics (each deity pass costs ETH, so there's an economic bound). Check if this loop is the actual worst case.
**Warning signs:** No cap on `deityPassOwners.length` in the code.

### Pitfall 4: Auto-Rebuy Multiplier on Daily Jackpot Units
**What goes wrong:** With auto-rebuy enabled, each winner costs 3 units instead of 1 from the unitsBudget. This means the chunking is 3x more aggressive but each winner does more work (ticket queuing + pool updates).
**Why it happens:** Auto-rebuy converts ETH winnings into tickets, adding _queueTickets and pool update operations per winner.
**How to avoid:** Model worst case as all winners having auto-rebuy enabled (3 units each), giving max ~333 winners per chunk.
**Warning signs:** Gas model assumes 1 unit per winner.

### Pitfall 5: Cold Storage Amplification
**What goes wrong:** The first call in a sequence hits cold storage slots (2,100 gas vs 100 for warm). The 65% scaling in processTicketBatch (line 1912: `writesBudget -= (writesBudget * 35) / 100`) accounts for this, but other paths may not.
**Why it happens:** Each new advanceGame call starts with cold storage for all game state slots.
**How to avoid:** Account for cold storage costs at the START of each stage. The AdvanceModule reads ~15-20 storage slots in the preamble (level, jackpotPhaseFlag, lastPurchaseDay, rngLockedFlag, dailyIdx, etc.).
**Warning signs:** Gas estimate based only on warm storage costs.

### Pitfall 6: The ENTERED_JACKPOT Stage Combines Multiple Operations
**What goes wrong:** Stage 7 (ENTERED_JACKPOT) does consolidation, earlybird lootbox jackpot (100 winners), future pool drawdown, and phase flag updates all in one call. This is potentially the heaviest single-stage path.
**Why it happens:** The transition from purchase phase to jackpot phase bundles several operations that each involve loops and storage writes.
**How to avoid:** Carefully tally: consolidatePrizePools (x00 special case), _applyTimeBasedFutureTake, _runEarlyBirdLootboxJackpot (100 iterations), _drawDownFuturePrizePool, plus all the flag updates.
**Warning signs:** Treating ENTERED_JACKPOT as a lightweight path.

## Analysis Framework

### Methodology for Each Code Path

For each advanceGame stage:

1. **Identify entry conditions**: What state triggers this stage
2. **Trace full call graph**: Every function call, delegatecall, and external call
3. **Count loops with bounds**: Maximum iterations, per-iteration cost
4. **Count storage operations**: Cold SLOADs, cold SSTOREs, warm operations
5. **Count external calls**: Address cold/warm, calldata size, return size
6. **Count events**: Topic count, data size
7. **Sum worst case**: All maximums simultaneously active
8. **Compute headroom**: 14,000,000 - worst_case_gas

### Critical Paths to Profile (Priority Order)

1. **STAGE_JACKPOT_PHASE_ENDED (10)**: coin+tickets + rewardJackpots (BAF up to 107 winners + Decimator) + endPhase
2. **STAGE_ENTERED_JACKPOT (7)**: consolidation + earlybird (100 winners) + pool ops
3. **STAGE_JACKPOT_DAILY_STARTED (11)**: Full daily init + Phase 0 chunk (up to ~1000 units of winners)
4. **STAGE_PURCHASE_DAILY (6)**: Early-burn jackpot (JACKPOT_MAX_WINNERS=300) + coin jackpot (50 winners)
5. **STAGE_GAMEOVER (0)**: Deity refund loop + decimator + terminal jackpot
6. **STAGE_TICKETS_WORKING (5)**: processTicketBatch (WRITES_BUDGET_SAFE=550)
7. **STAGE_JACKPOT_ETH_RESUME (8)**: Daily ETH chunk (UNITS_SAFE=1000)
8. **STAGE_JACKPOT_COIN_TICKETS (9)**: payDailyJackpotCoinAndTickets
9. **STAGE_TRANSITION_DONE (3)**: 2 queue ops + stETH stake

### Purchase Paths to Profile

1. **Tickets + Lootbox + Combined payment**: Maximum external calls and storage writes
2. **Tickets only (ETH)**: recordMint self-call + affiliate + queue
3. **Lootbox only (ETH)**: Multiple storage writes, affiliate calls, pool splits
4. **purchaseCoin (BURNIE tickets)**: _coinReceive + queue
5. **purchaseWhaleBundle**: Different module, whale-specific logic
6. **purchaseBurnieLootbox**: BURNIE-funded lootbox path

### Per-Winner Gas Cost Estimation

For `_addClaimableEth` (the hot inner loop in jackpot distribution):

```
_addClaimableEth(winner, amount, entropy):
  - autoRebuyState[winner] SLOAD: 2,100 (cold) or 100 (warm)
  - If auto-rebuy:
    - _calcAutoRebuy: ~5 SLOADs + arithmetic
    - _queueTickets: 1-2 SSTOREs + potential array push
    - _setFuturePrizePool or _setNextPrizePool: 1 SSTORE
    - Event emission: ~1,500
    Total per auto-rebuy winner: ~15,000-25,000 gas
  - If normal:
    - claimableWinnings[winner] SLOAD + SSTORE: ~7,200 (cold)
    Total per normal winner: ~10,000-12,000 gas
  - Event (JackpotTicketWinner): 4 topics = 375*4 + data ~2,000
```

For `_processDailyEthChunk` with `unitsBudget=1000`:
- At 1 unit/winner (no auto-rebuy): up to 1000 winners, ~12M gas
- At 3 units/winner (all auto-rebuy): up to 333 winners, ~8M gas
- Mix: variable

### Key External Calls in advanceGame

| Call | Target | Cold Cost | Description |
|------|--------|-----------|-------------|
| `coin.creditFlip()` | BURNIE contract | ~5,000 | SSTORE on caller balance |
| `coin.rollDailyQuest()` | BURNIE contract | ~10,000 | Quest state update |
| `steth.submit{value}()` | Lido stETH | ~30,000 | External staking call |
| `affiliate.payAffiliate()` | Affiliate contract | ~15,000 | Score + credit |
| `dgnrs.transferFromPool()` | sDGNRS | ~10,000 | Token transfer |
| `jackpots.runBafJackpot()` | Jackpots contract | ~50,000+ | 107 winner selection |
| VRF `requestRandomWords()` | Chainlink | ~50,000 | External oracle call |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) 0.8.34 via solc, via_ir=true, optimizer_runs=2 |
| Config file | foundry.toml |
| Quick run command | `forge test --match-path "test/fuzz/RedemptionGas.t.sol" -vv` |
| Full suite command | `forge test -vv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CEIL-01 | advanceGame worst-case gas per path | manual + gas-report | `forge test --gas-report --match-contract AdvanceGas` | No -- Wave 0 |
| CEIL-02 | Max jackpot payouts under 14M | manual analysis | N/A -- static analysis, not automated test | N/A |
| CEIL-03 | purchase worst-case gas | manual + gas-report | `forge test --gas-report --match-contract PurchaseGas` | No -- Wave 0 |
| CEIL-04 | Max ticket batch under 14M | manual analysis | N/A -- static analysis | N/A |
| CEIL-05 | Headroom documentation | manual analysis | N/A -- document output | N/A |

### Sampling Rate
- **Per task commit:** N/A (this is an analysis phase, not a code-change phase)
- **Per wave merge:** Review gas numbers against 14M ceiling
- **Phase gate:** All 5 CEIL requirements documented with evidence

### Wave 0 Gaps
This phase is a pure analysis phase (audit-style). It does NOT modify code. The existing RedemptionGas.t.sol demonstrates the gas benchmarking pattern used in this project. New gas benchmark tests are NOT required for CEIL-01 through CEIL-05 (requirements specify "profiled" and "computed" not "tested"), but Foundry gas reports can be used to validate static analysis conclusions.

- If gas benchmark tests are desired for validation: create `test/fuzz/AdvanceGameGas.t.sol` using `DeployProtocol` helper
- Existing `test/fuzz/RedemptionGas.t.sol` provides the pattern

## Code Examples

### advanceGame Stage Exit Pattern
```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:231-379
// Each path through the do-while exits with a stage constant:
do {
    // ... branching logic ...
    stage = STAGE_PURCHASE_DAILY;
    break;  // <-- exits after ONE stage
} while (false);

emit Advance(stage, lvl);
coin.creditFlip(caller, advanceBounty);  // Always paid
```

### processTicketBatch Gas Budgeting
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1910-1913
uint32 writesBudget = WRITES_BUDGET_SAFE;  // 550
if (idx == 0) {
    writesBudget -= (writesBudget * 35) / 100; // 65% = 357 for cold storage
}
```

### Daily Jackpot Chunking
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1467-1477
// Inner loop checks unit budget before each winner
for (uint256 i = startWinnerIdx; i < len; ) {
    address w = winners[i];
    uint8 cost = _winnerUnits(w);  // 1 or 3 (auto-rebuy)
    if (cost != 0 && unitsUsed + cost > unitsBudget) {
        // Save cursor and exit -- resume next call
        dailyEthBucketCursor = j;
        dailyEthWinnerCursor = uint16(i);
        return (paidEth, false);  // incomplete
    }
    // ... process winner ...
}
```

## Open Questions

1. **Deity Pass Owner Count Bound**
   - What we know: `deityPassOwners` is a dynamic array; each deity pass purchase adds the buyer. The loop in `handleGameOverDrain` iterates all owners.
   - What's unclear: What is the economic maximum number of distinct deity pass owners? (Each pass costs ETH, so there is a natural cap, but the array stores owners not passes.)
   - Recommendation: Compute maximum from deity pass price and total ETH that could flow to deity purchases. If unbounded, flag as a potential finding.

2. **BAF Jackpot External Call Gas**
   - What we know: `jackpots.runBafJackpot()` is an external call (not delegatecall) to `DegenerusJackpots.sol`. It creates memory arrays of up to 107 entries and iterates them.
   - What's unclear: The full gas cost of this external call under worst case (all 107 winners found).
   - Recommendation: Include in the ENTERED_JACKPOT + JACKPOT_PHASE_ENDED analysis.

3. **Compiler Optimization Impact**
   - What we know: The project uses `via_ir = true` with `optimizer_runs = 2` (heavily optimized for deployment size, not runtime).
   - What's unclear: `optimizer_runs = 2` optimizes for small code size at the expense of runtime gas. This could make gas costs higher than typical contracts.
   - Recommendation: Note this in headroom analysis. Foundry gas reports will reflect actual compiled costs.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Full advanceGame flow, all stage constants, call graph
- `contracts/modules/DegenerusGameJackpotModule.sol` - All gas budgeting constants, chunking logic, winner distribution
- `contracts/modules/DegenerusGameMintModule.sol` - purchase() full path
- `contracts/modules/DegenerusGameEndgameModule.sol` - runRewardJackpots, BAF distribution
- `contracts/modules/DegenerusGameGameOverModule.sol` - handleGameOverDrain, deity refund loop
- `contracts/DegenerusGame.sol` - Entry points, delegatecall dispatch, recordMint
- `contracts/DegenerusJackpots.sol` - External BAF jackpot (107 max winners)
- `contracts/storage/DegenerusGameStorage.sol` - _queueTickets, shared storage layout
- `contracts/modules/DegenerusGamePayoutUtils.sol` - _addClaimableEth, auto-rebuy logic
- `foundry.toml` - Compiler settings (via_ir, optimizer_runs=2)

### Secondary (MEDIUM confidence)
- EVM gas costs are based on the Shanghai/Cancun execution specification. Gas costs for SSTORE/SLOAD/CALL are well-established and stable.

## Metadata

**Confidence breakdown:**
- Architecture patterns: HIGH - Direct code analysis of all contracts involved
- Gas constants and bounds: HIGH - Constants extracted directly from source code
- Per-operation gas costs: MEDIUM - EVM spec costs are accurate, but compiler optimization (via_ir, runs=2) can shift actual costs
- Headroom estimates: MEDIUM - Will need to be validated against Foundry gas reports in the actual plan execution

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (gas costs are stable; code changes would invalidate)
