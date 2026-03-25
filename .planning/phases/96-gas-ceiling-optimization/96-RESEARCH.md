# Phase 96: Gas Ceiling + Optimization - Research

**Researched:** 2026-03-24
**Domain:** Solidity gas profiling, worst-case analysis, SLOAD optimization, loop hoisting
**Confidence:** HIGH

## Summary

Phase 96 performs worst-case gas profiling and optimization of the daily jackpot code path after Phase 95's chunk removal refactor. The chunk removal eliminated `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `_skipEntropyToBucket`, `_winnerUnits`, `DAILY_JACKPOT_UNITS_SAFE`, and `DAILY_JACKPOT_UNITS_AUTOREBUY` -- all proven dead code because 321 winners x 3 units = 963 < 1000 budget. The resulting `_processDailyEthChunk` is now a straightforward single-pass function over 4 buckets with up to 321 total winners.

The prior Phase 57 (v3.5) already profiled all 12 advanceGame stages. This phase focuses specifically on re-profiling the daily jackpot stages (Stages 6, 8, 11) that were classified as TIGHT or AT_RISK, now that the chunking overhead has been removed. The critical question is: does removing the dead chunking code reduce gas enough to improve headroom on the AT_RISK stages, or does the compiler optimization (via_ir=true, optimizer_runs=2) make this negligible?

The scope also includes an SLOAD audit and loop hoisting audit of the daily jackpot code path. The function `_processDailyEthChunk` calls `_addClaimableEth` per winner, which branches into either `_processAutoRebuy` (3 SLOADs + conditional writes) or `_creditClaimable` (1 SSTORE). Identifying unnecessary SLOADs in this hot path could yield meaningful gas savings at 321 winners.

**Primary recommendation:** Use a combination of static analysis (continuing Phase 57's methodology) and empirical Foundry gas measurement to profile the post-chunk-removal `_processDailyEthChunk` and `payDailyJackpot`. The existing Hardhat gas test (`test/gas/AdvanceGameGas.test.js`) can provide empirical measurements. For SLOAD/loop optimization, perform code-level audit of `_processDailyEthChunk`, `_addClaimableEth`, `_processAutoRebuy`, and `payDailyJackpot` init block.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CEIL-01 | Worst-case gas for _processDailyEthChunk profiled (321 winners, all auto-rebuy, 4 populated buckets) | Post-chunk-removal function at JackpotModule:1329-1424 is a direct single-pass 4-bucket loop; Phase 57 estimated ~8.3M for 333 auto-rebuy winners, but now max is 321 (no unit budget); per-winner cost breakdown documented |
| CEIL-02 | Worst-case gas for payDailyJackpot profiled (Phase 0 + Phase 1 combined, final physical day) | payDailyJackpot at JackpotModule:313-638 has Phase 0 (dailyEthPhase==0) and Phase 1 (dailyEthPhase==1) split; on final physical day dailyBps=10000 (100% pool); Phase 0 and Phase 1 execute in separate advanceGame calls; the combined worst case is the heavier of the two calls |
| CEIL-03 | All profiled paths SAFE under 14M gas ceiling with headroom documented | Phase 57 found Stages 8, 11 AT_RISK and Stage 6 TIGHT; chunk removal should reduce overhead; re-profile to determine updated risk levels |
| GOPT-01 | Daily jackpot code path audited for unnecessary SLOADs | _addClaimableEth reads autoRebuyState[beneficiary] per winner (cold SLOAD); _processAutoRebuy reads level, _getFuturePrizePool/_getNextPrizePool; payDailyJackpot init reads ~20 storage slots |
| GOPT-02 | Loop bodies audited for redundant computation that can be hoisted | _processDailyEthChunk inner loop: traitBurnTicket[lvl] SLOAD per bucket (4x), PriceLookupLib.priceForLevel called once before loop (already hoisted); _addClaimableEth: gameOver check per winner (storage read); _processAutoRebuy: level read per winner |
| GOPT-03 | Any identified optimizations implemented and verified | Depends on findings from GOPT-01 and GOPT-02; implementation must not change behavior |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- NEVER commit contracts/ or test/ changes without explicit user approval
- Present fix and wait for explicit approval before editing code
- Remove unreachable safety caps; do not waste gas on dead branches
- Every RNG audit must trace backward from each consumer
- Solidity 0.8.34, Foundry + Hardhat dual test infrastructure

## Architecture Patterns

### Post-Chunk-Removal Daily Jackpot Flow

After Phase 95's chunk removal, the daily jackpot ETH distribution follows this flow:

```
advanceGame() -> payDailyJackpot(true, lvl, rngWord)
  |
  +-- Fresh start (not resuming):
  |   1. Roll winning traits, sync daily traits
  |   2. Compute dailyBps (final day = 10000 = 100%)
  |   3. Early bird lootbox jackpot (day 1 only, 100 winners)
  |   4. Compute daily/carryover lootbox budgets
  |   5. Store: dailyEthPoolBudget, dailyTicketBudgetsPacked, dailyCarryoverEthPool
  |   6. dailyEthPhase = 0
  |
  +-- Phase 0 (dailyEthPhase == 0): Current level daily ETH
  |   -> _processDailyEthChunk(lvl, budget, ...) [SINGLE PASS, NO CHUNKING]
  |   -> All 321 max winners processed in one call
  |   -> Compute dailyCarryoverWinnerCap from remaining
  |   -> If no carryover: _clearDailyEthState(), return
  |   -> Else: dailyEthPhase = 1, return
  |
  +-- Phase 1 (dailyEthPhase == 1): Carryover ETH [SEPARATE advanceGame call]
  |   -> _processDailyEthChunk(carryoverLevel, carryPool, ...) [SINGLE PASS]
  |   -> _clearDailyEthState()
  |   -> return
  |
  +-- Then: coin+tickets in NEXT advanceGame call (Stage 9 or 10)
```

Key structural change from Phase 95: `_processDailyEthChunk` no longer has `unitsBudget`, `_winnerUnits`, cursor save/restore, or `_skipEntropyToBucket`. It processes ALL winners in a single pass. The maximum winners is now bounded purely by `DAILY_ETH_MAX_WINNERS = 321` and `MAX_BUCKET_WINNERS = 250` per bucket.

### advanceGame Stage Mapping for Daily Jackpot

| Stage | When | What Runs |
|-------|------|-----------|
| 11 (JACKPOT_DAILY_STARTED) | Fresh daily jackpot (no resume state) | payDailyJackpot(true, lvl) -- full init + Phase 0 chunk |
| 8 (JACKPOT_ETH_RESUME) | dailyEthPhase != 0 OR dailyEthPoolBudget != 0 | payDailyJackpot(true, ...) -- resumes Phase 1 carryover |
| 6 (PURCHASE_DAILY) | Purchase phase, not lastPurchaseDay | payDailyJackpot(false, ...) -- early-burn non-chunked path (300 max) |
| 9 (JACKPOT_COIN_TICKETS) | dailyJackpotCoinTicketsPending, counter < 5 | payDailyJackpotCoinAndTickets -- coin + ticket phase |
| 10 (JACKPOT_PHASE_ENDED) | dailyJackpotCoinTicketsPending, counter >= 5 | payDailyJackpotCoinAndTickets + BAF + decimator + endPhase |

### Phase 0 + Phase 1 Split Mechanics

The daily jackpot splits across TWO advanceGame calls when carryover is active:

**Call 1 (Stage 11 JACKPOT_DAILY_STARTED):**
- Fresh init: trait roll, budget computation, earlybird (day 1 only)
- Phase 0: `_processDailyEthChunk` for current-level winners (up to 321)
- If carryover exists: sets `dailyEthPhase = 1`, returns

**Call 2 (Stage 8 JACKPOT_ETH_RESUME):**
- Phase 1: `_processDailyEthChunk` for carryover winners (up to `dailyCarryoverWinnerCap`)
- `_clearDailyEthState()`, returns

**Final physical day:** `dailyBps = 10000` (100% of pool). This maximizes the budget, which maximizes winner counts from `bucketCountsForPoolCap`. This is the worst case for gas.

### _processDailyEthChunk Hot Path (Post-Chunk-Removal)

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1329-1424
function _processDailyEthChunk(lvl, ethPool, entropy, traitIds, shareBps, bucketCounts) private returns (uint256 paidEth) {
    // Setup: 1 library call (PriceLookupLib), 2 library calls (BucketLib)
    // No unit budget, no cursor restore

    for (uint8 j; j < 4; ++j) {           // 4 buckets
        // Per bucket:
        //   - EntropyLib.entropyStep (pure, ~200 gas)
        //   - _randTraitTicketWithIndices: traitBurnTicket[lvl] SLOAD + memory allocation
        //   - share / totalCount arithmetic

        for (uint256 i; i < winners.length; ) {  // up to 250 per bucket, 321 total
            // Per winner:
            //   - _addClaimableEth(w, perWinner, entropyState)
            //   - emit JackpotTicketWinner (4 indexed + 1 data = ~3500 gas)
            //   - paidEth += perWinner
            //   - liabilityDelta += claimableDelta
        }
    }

    if (liabilityDelta != 0) {
        claimablePool += liabilityDelta;    // 1 warm SSTORE (accumulated)
    }
}
```

### _addClaimableEth Per-Winner Cost Breakdown

```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:928-949
function _addClaimableEth(beneficiary, weiAmount, entropy) private returns (uint256 claimableDelta) {
    // Path A: Normal winner
    //   gameOver check: 1 SLOAD (warm after first check, same slot as Slot 0)
    //   autoRebuyState[beneficiary]: 1 cold SLOAD (2100 gas, unique per winner)
    //   autoRebuyEnabled == false
    //   _creditClaimable(beneficiary, weiAmount): claimableWinnings[beneficiary] += weiAmount
    //     -> 1 cold SLOAD (2100) + 1 cold SSTORE (5000 nonzero->nonzero OR 22100 zero->nonzero)
    //   Total: ~9,300 (existing balance) or ~26,400 (first credit)

    // Path B: Auto-rebuy winner
    //   gameOver check + autoRebuyState SLOAD (same as above)
    //   autoRebuyEnabled == true
    //   _processAutoRebuy -> _calcAutoRebuy:
    //     -> level SLOAD (warm, Slot 0)
    //     -> PriceLookupLib.priceForLevel (pure library, ~200 gas)
    //     -> arithmetic for ticket count, ethSpent, reserved
    //   _queueTickets(player, targetLevel, ticketCount):
    //     -> ticketsOwedPacked[player][targetLevel] SLOAD + SSTORE (~7,200 cold)
    //   _setFuturePrizePool OR _setNextPrizePool:
    //     -> prizePoolsPacked SLOAD + SSTORE (warm after first, ~200 gas)
    //   _creditClaimable (if reserved != 0): SLOAD + SSTORE (~7,200)
    //   emit AutoRebuyProcessed: ~3,500 gas
    //   Total: ~23,000-25,000 gas
}
```

### Storage Layout Relevant to Daily Jackpot (SLOAD Audit Targets)

```
EVM Slot 0 (packed, 30 bytes used):
  level, jackpotPhaseFlag, jackpotCounter, poolConsolidationDone,
  lastPurchaseDay, decWindowOpen, rngLockedFlag, phaseTransitionActive,
  gameOver, dailyJackpotCoinTicketsPending

EVM Slot 1 (packed, 27 bytes used):
  dailyEthPhase, compressedJackpotFlag, purchaseStartDay, price,
  ticketWriteSlot, ticketsFullyProcessed, prizePoolFrozen

Slot 2: currentPrizePool (uint256)
Slot 3: prizePoolsPacked (uint256) -- [128:256] future | [0:128] next
Slot N: dailyEthPoolBudget (uint256)
Slot N+M: dailyCarryoverEthPool (uint256)
Slot N+M+1: dailyCarryoverWinnerCap (uint16)

Mappings:
  claimableWinnings[address] -- per-winner, cold per unique address
  autoRebuyState[address] -- per-winner, cold per unique address
  traitBurnTicket[level][traitId] -- per-bucket, cold per level+trait combo
  ticketsOwedPacked[player][level] -- per-winner auto-rebuy, cold
```

### Identified SLOAD Patterns in Hot Path

| SLOAD | Location | Per-Call Count | Cold/Warm | Notes |
|-------|----------|----------------|-----------|-------|
| `gameOver` | _addClaimableEth:937 | 1 per winner (up to 321) | Warm after first (Slot 0 read in preamble) | Packed in Slot 0 |
| `autoRebuyState[beneficiary]` | _addClaimableEth:938 | 1 per winner | Cold (unique address) | Unavoidable -- unique per winner |
| `claimableWinnings[beneficiary]` | _creditClaimable | 1 per winner (normal path) | Cold (unique address) | Unavoidable -- unique per winner |
| `traitBurnTicket[lvl]` | _randTraitTicketWithIndices | 4 (once per bucket) | Cold first, warm after | Mapping root access |
| `level` | _processAutoRebuy:970 | 1 per auto-rebuy winner | Warm (Slot 0, already read) | Already optimized |
| `prizePoolsPacked` | _setFuturePrizePool/_setNextPrizePool | Up to 321 (auto-rebuy) | Warm after first | Already optimized (packed) |
| `currentPrizePool` | payDailyJackpot:353 | 1 per call | Cold | Read once for budget |
| `dailyEthPoolBudget` | payDailyJackpot:474 | 1 per call | Cold | Read once for Phase 0 |

### Loop-Hoistable Computation Candidates

| Computation | Current Location | Per-Iteration? | Hoistable? | Impact |
|-------------|-----------------|----------------|------------|--------|
| `PriceLookupLib.priceForLevel(lvl+1)` | _processDailyEthChunk:1341 | No -- before loop | Already hoisted | None |
| `JackpotBucketLib.soloBucketIndex(entropy)` | _processDailyEthChunk:1342 | No -- before loop | Already hoisted | None |
| `JackpotBucketLib.bucketShares(...)` | _processDailyEthChunk:1343 | No -- before loop | Already hoisted | None |
| `JackpotBucketLib.bucketOrderLargestFirst(...)` | _processDailyEthChunk:1351 | No -- before loop | Already hoisted | None |
| `gameOver` check | _addClaimableEth:937 | Yes (per winner) | Potentially -- could pass as param | Warm SLOAD (100 gas) x 321 = ~32K total; marginal |
| `_processAutoRebuy` `level` read | _processAutoRebuy:970 | Yes (per auto-rebuy) | Potentially -- could pass as param | Warm SLOAD (Slot 0), marginal |

**Key finding:** The hot path's computations that precede the loops (`priceForLevel`, `soloBucketIndex`, `bucketShares`, `bucketOrderLargestFirst`) are already hoisted above the bucket iteration. The remaining per-iteration costs are dominated by unavoidable per-address cold SLOADs (`autoRebuyState`, `claimableWinnings`), not by redundant computation.

## Gas Cost Changes from Chunk Removal

### What Was Removed (Phase 95)

| Removed Element | Gas Saved Per Call | Notes |
|-----------------|-------------------|-------|
| `_winnerUnits(w)` call per winner | ~200-300 gas x N winners | Was a view function reading autoRebuyState -- redundant since _addClaimableEth reads it too |
| `unitsUsed + cost > unitsBudget` check per winner | ~100 gas x N winners | Branch comparison |
| Cursor save (dailyEthBucketCursor, dailyEthWinnerCursor) | ~10,000 gas (2 SSTOREs) | Never executed (dead path), but code existed |
| `_skipEntropyToBucket` call | ~500 gas | Zero-iteration loop when cursor was 0, but function call overhead existed |
| `DAILY_JACKPOT_UNITS_SAFE` constant usage | 0 | Constant eliminated |

**Estimated gas reduction from chunk removal:** Negligible in practice. The removed code was dead -- the early-return path never executed, so only function call overhead and the `_winnerUnits` per-winner check contribute to savings. Rough estimate: ~200 gas per winner x 321 = ~64,000 gas total reduction. This improves headroom by ~64K on AT_RISK stages.

**However**, the removal of `_winnerUnits` is significant for the SLOAD audit: it previously performed a redundant SLOAD of `autoRebuyState[winner]` that `_addClaimableEth` also performs. If the compiler did not optimize this away (likely not with `optimizer_runs=2`), removing it saves one cold SLOAD (2,100 gas) per winner = **~674,000 gas** for 321 winners. This is the major improvement and must be verified empirically.

### Updated Worst-Case Estimates (Post-Chunk-Removal)

**Stage 11 (JACKPOT_DAILY_STARTED) -- Day 1 with earlybird:**

Phase 57 estimated: ~14,162,000 gas (BREACH by 162K).

The `_winnerUnits` SLOAD removal saves ~674K for 321 auto-rebuy winners. However, the chunk removal also means the function no longer has a `unitsBudget` of 1000 limiting to 333 auto-rebuy winners per call -- it now processes ALL winners (up to 321) in one call. Since 321 < 333, this is actually a tighter bound.

Post-removal estimate: ~14,162,000 - ~674,000 (SLOAD savings) - ~64,000 (overhead) = ~13,424,000.
Headroom: 14,000,000 - 13,424,000 = ~576,000. Still AT_RISK but no longer BREACH.

**Stage 8 (JACKPOT_ETH_RESUME) -- Phase 1 carryover:**

This now processes up to `dailyCarryoverWinnerCap` winners (max 321, typically 20+ via `DAILY_CARRYOVER_MIN_WINNERS`). With 321 total in Phase 0 + Phase 1 split, the carryover portion is typically much smaller.

Phase 57 estimate was based on 333 winners per chunk (unitsBudget=1000/3). Now the carryover cap is dynamically computed:
- If Phase 0 used all 321 winners: carryover cap = 0, no Phase 1
- If Phase 0 used 300 winners: carryover cap = max(321-300, 20) = 21 winners
- Worst case for Phase 1 alone: 321 winners (all carryover, no Phase 0 winners)

The realistic worst case for Stage 8 is much lower than before because the carryover is bounded by `DAILY_ETH_MAX_WINNERS - Phase0Winners`.

**Stage 6 (PURCHASE_DAILY) -- early-burn:**

Unchanged by chunk removal. Uses `_executeJackpot` -> `_distributeJackpotEth`, not `_processDailyEthChunk`. Remains TIGHT at ~12,952,000 gas (300 auto-rebuy winners).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gas measurement | Manual opcode counting alone | Foundry `forge test --gas-report` + `forge snapshot` combined with static analysis | Compiler optimization (via_ir, runs=2) changes actual costs unpredictably |
| Worst-case test setup | Manual state construction | Existing Hardhat gas test pattern (`test/gas/AdvanceGameGas.test.js`) with `vm.store` for direct state injection | Full protocol deploy + state driving is the proven pattern |
| SLOAD optimization validation | Trusting static analysis | Before/after `forge snapshot --diff` comparison | Only empirical measurement confirms compiler behavior |

## Common Pitfalls

### Pitfall 1: Confusing Phase 0 and Phase 1 Gas Budgets
**What goes wrong:** Treating the combined Phase 0 + Phase 1 winner count as executing in a single advanceGame call.
**Why it happens:** `payDailyJackpot` handles both phases, but Phase 0 and Phase 1 execute in SEPARATE advanceGame calls (Phase 0 returns after setting `dailyEthPhase = 1`; Phase 1 runs on the next call as Stage 8).
**How to avoid:** Profile each phase separately. The worst-case gas ceiling applies PER advanceGame call, not per daily jackpot total.
**Warning signs:** Gas estimate combining Phase 0 + Phase 1 winners into one number.

### Pitfall 2: Assuming All 321 Winners Go to Phase 0
**What goes wrong:** Setting up a worst-case test with 321 winners all in Phase 0, ignoring the carryover split.
**Why it happens:** `bucketCountsForPoolCap` allocates winners based on pool size. With a large pool (final day, 100% budget), Phase 0 could get most/all winners, leaving few for Phase 1.
**How to avoid:** Profile the case where Phase 0 gets maximum winners (321) AND the case where carryover exists with maximum carryover winners.
**Warning signs:** Carryover path not profiled separately.

### Pitfall 3: _winnerUnits SLOAD Double-Count Uncertainty
**What goes wrong:** Assuming the removed `_winnerUnits` call saved a cold SLOAD, when the compiler may have optimized it away via CSE (common subexpression elimination).
**Why it happens:** With `via_ir=true`, the Solidity compiler performs more aggressive optimization passes. It might have recognized that `autoRebuyState[winner]` was read twice and cached it.
**How to avoid:** Verify with empirical gas measurement (forge snapshot before/after chunk removal). If possible, compare gas reports.
**Warning signs:** Static analysis claiming large savings without empirical validation.

### Pitfall 4: Forgetting Cold Storage Preamble
**What goes wrong:** Profiling `_processDailyEthChunk` in isolation, forgetting the cold storage reads in the advanceGame preamble and payDailyJackpot init.
**Why it happens:** The function-level gas cost misses the ~42,000 gas cold preamble and ~60,000 gas init overhead.
**How to avoid:** Always include the full advanceGame call overhead: 21,000 tx base + ~42,000 cold preamble + ~5,000 delegatecall + ~60,000 payDailyJackpot init.
**Warning signs:** Gas estimates starting from `_processDailyEthChunk` entry point without full call context.

### Pitfall 5: ContractAddresses.sol Stash Required
**What goes wrong:** Foundry compilation fails with address mismatches because `ContractAddresses.sol` has unstaged changes for a different deploy environment.
**Why it happens:** STATE.md documents this: "ContractAddresses.sol has unstaged changes (different deploy addresses)."
**How to avoid:** Run `git stash` before any `forge test` or `forge snapshot` commands. Restore with `git stash pop` after.
**Warning signs:** Foundry test failures with "address mismatch" or "deployment failed" errors.

## Gas Profiling Methodology

### Approach 1: Empirical Measurement via Hardhat

The existing `test/gas/AdvanceGameGas.test.js` provides a proven pattern for empirical gas measurement. It:
1. Deploys full protocol via `deployFullProtocol` fixture
2. Drives game state to specific stages
3. Measures `receipt.gasUsed` per advanceGame call
4. Reports sorted gas results in a summary table

This can be extended to create worst-case scenarios for the daily jackpot path. However, constructing a 321-winner all-auto-rebuy scenario requires:
- Enough unique players with tickets in the right trait pools
- All players having auto-rebuy enabled
- A large enough prize pool to trigger maximum bucket counts
- Final physical day (`jackpotCounter + counterStep >= 5`) for 100% pool budget

### Approach 2: Empirical Measurement via Foundry

Create a Foundry gas test inheriting `DeployProtocol`:
1. Deploy protocol via `_deployProtocol()`
2. Use `vm.store` to inject state directly (storage slots)
3. Use `vm.prank` for delegatecall targets
4. Call `payDailyJackpot` and measure gas with `gasleft()` wrapping

Foundry advantages: direct `vm.store` for state injection, `forge snapshot` for regression tracking, `forge test --gas-report` for function-level breakdown.

### Approach 3: Static Analysis (Phase 57 Methodology)

Continue Phase 57's per-operation gas accounting:
1. Count cold SLOADs, cold SSTOREs per path
2. Count events (topics x 375 + 8/byte data)
3. Count external/delegatecall costs
4. Sum worst-case totals
5. Compare against 14M ceiling

This is the most reliable for worst-case analysis because empirical tests may not achieve the true worst case.

### Recommended Combined Approach

1. **Static analysis first** (CEIL-01, CEIL-02): Update Phase 57's estimates to account for chunk removal changes
2. **Empirical validation** (CEIL-03): Run Hardhat gas tests to validate static analysis
3. **SLOAD audit** (GOPT-01): Code review of hot path with per-operation annotation
4. **Loop hoisting audit** (GOPT-02): Code review of inner loops
5. **Implementation** (GOPT-03): If optimizations found, implement and verify with before/after gas comparison

## Key Constants After Chunk Removal

| Constant | Value | Location | Gas Implication |
|----------|-------|----------|-----------------|
| `DAILY_ETH_MAX_WINNERS` | 321 | JackpotModule:183 | Max total winners across Phase 0 + Phase 1 |
| `MAX_BUCKET_WINNERS` | 250 | JackpotModule:173 | Per-bucket cap |
| `DAILY_CARRYOVER_MIN_WINNERS` | 20 | JackpotModule:187 | Minimum carryover winners when Phase 0 < 321 |
| `DAILY_COIN_MAX_WINNERS` | 50 | JackpotModule:190 | Coin jackpot cap (Stage 9/10) |
| `LOOTBOX_MAX_WINNERS` | 100 | JackpotModule:207 | Earlybird and ticket distribution cap |
| `JACKPOT_MAX_WINNERS` | 300 | Used by early-burn _executeJackpot | Stage 6 cap |
| `JACKPOT_LEVEL_CAP` | 5 | Counter threshold for Stage 10 vs 9 | 5 physical days per level |

**Removed constants:** `DAILY_JACKPOT_UNITS_SAFE` (was 1000), `DAILY_JACKPOT_UNITS_AUTOREBUY` (was 3). These no longer exist in the codebase.

## Worst-Case Input Construction

### "321 winners, all auto-rebuy, 4 populated buckets"

To achieve the absolute worst case for `_processDailyEthChunk`:

1. **4 populated buckets**: `JackpotBucketLib.bucketCountsForPoolCap` must return non-zero counts for all 4 trait buckets. This requires the pool budget to be large enough relative to the ticket price that all 4 buckets get populated.

2. **321 total winners**: `bucketCountsForPoolCap` allocates winners based on pool size / ticket unit. With `DAILY_JACKPOT_SCALE_MAX_BPS = 66667` (6.6667x), the scaling allows up to 321 winners when the pool is large enough. At 250 per bucket cap, 4 buckets could yield up to 1000 theoretical winners, but `DAILY_ETH_MAX_WINNERS = 321` caps the total.

3. **All auto-rebuy**: Every winner address must have `autoRebuyState[winner].autoRebuyEnabled = true`. This means every winner takes the expensive `_processAutoRebuy` path (~25,000 gas) instead of `_creditClaimable` (~9,300 gas).

4. **Final physical day**: `dailyBps = 10000` (100% of pool). Maximizes budget, maximizes winner counts.

### "payDailyJackpot Phase 0 + Phase 1 combined, final physical day"

The CEIL-02 requirement asks to measure both phases combined. Since they execute in separate advanceGame calls, the profiling must:

1. **Phase 0 (Stage 11)**: Full init + `_processDailyEthChunk` with maximum current-level winners
2. **Phase 1 (Stage 8)**: Resume + `_processDailyEthChunk` with maximum carryover winners
3. **Report each separately** with per-call gas
4. **Document the maximum**: Which call is heavier? Phase 0 has init overhead + earlybird (day 1) but may have fewer winners if carryover is large. Phase 1 has no init but has its own winners.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) 1.5.1-stable, Solidity 0.8.34, via_ir=true, optimizer_runs=2 |
| Config file | foundry.toml |
| Quick run command | `forge test --match-path "test/fuzz/RedemptionGas.t.sol" -vv` |
| Full suite command | `forge test -vv` |
| Hardhat gas test | `npx hardhat test test/gas/AdvanceGameGas.test.js` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CEIL-01 | _processDailyEthChunk worst-case gas | static analysis + empirical | `npx hardhat test test/gas/AdvanceGameGas.test.js` | Yes (existing) |
| CEIL-02 | payDailyJackpot Phase 0+1 worst-case gas | static analysis + empirical | `npx hardhat test test/gas/AdvanceGameGas.test.js` | Yes (existing) |
| CEIL-03 | All paths under 14M with headroom | static analysis + empirical | N/A (analysis output) | N/A |
| GOPT-01 | SLOAD audit of daily jackpot path | manual code review | N/A (audit document) | N/A |
| GOPT-02 | Loop hoisting audit | manual code review | N/A (audit document) | N/A |
| GOPT-03 | Optimization implementation | code change + regression | `forge test -vv && npx hardhat test` | Depends on findings |

### Sampling Rate
- **Per task commit:** `forge test -vv` (if code changes)
- **Per wave merge:** Full Hardhat + Foundry suite
- **Phase gate:** All CEIL/GOPT requirements documented with evidence

### Wave 0 Gaps
- If code changes are needed (GOPT-03), run full test suite to verify no regressions
- No new test infrastructure needed -- existing `test/gas/AdvanceGameGas.test.js` provides the measurement pattern
- Gas snapshot baseline can be captured via `forge snapshot` if desired

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Foundry (forge) | Gas profiling, snapshot | Yes | 1.5.1-stable | Use Hardhat gas reports |
| Node.js | Hardhat gas tests | Yes | v22.22.0 | -- |
| Hardhat | Empirical gas measurement | Yes | 2.28.6 | Foundry-only |
| Solidity compiler | Contract compilation | Yes | 0.8.34 (via forge) | -- |

**Missing dependencies with no fallback:** None.

## Code Examples

### Per-Winner Gas Accounting Pattern
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:1394-1417
// Hot inner loop in _processDailyEthChunk
for (uint256 i; i < len; ) {
    address w = winners[i];
    if (w != address(0)) {
        // _addClaimableEth: 1 cold SLOAD (autoRebuyState) + branch
        //   Normal: 1 cold SLOAD + 1 cold SSTORE (claimableWinnings) = ~9,300
        //   AutoRebuy: _calcAutoRebuy + _queueTickets + pool update + event = ~25,000
        uint256 claimableDelta = _addClaimableEth(w, perWinner, entropyState);
        // Event: 4 indexed topics + 1 data word = ~3,500
        emit JackpotTicketWinner(w, lvl, traitIds[traitIdx], perWinner, ticketIndexes[i]);
        paidEth += perWinner;
        liabilityDelta += claimableDelta;
    }
    unchecked { ++i; }
}
```

### Empirical Gas Measurement Pattern (Hardhat)
```javascript
// Source: test/gas/AdvanceGameGas.test.js:116-120
function recordGas(name, receipt) {
    const gasUsed = receipt.gasUsed;
    gasResults.push({ name, gasUsed });
    console.log(`      Gas: ${gasUsed.toLocaleString()}`);
}
```

### Phase 0/Phase 1 Return Pattern
```solidity
// Source: contracts/modules/DegenerusGameJackpotModule.sol:522-531
// Phase 0 -> Phase 1 transition
if (dailyCarryoverEthPool == 0 || dailyCarryoverWinnerCap == 0) {
    _clearDailyEthState();
    return;  // No Phase 1 needed
}
dailyEthPhase = 1;
return;  // Phase 1 will run in next advanceGame call (Stage 8)
```

## State of the Art

| Old Approach (Pre-Phase 95) | Current Approach (Post-Phase 95) | When Changed | Impact |
|------|------|------|------|
| Chunked `_processDailyEthChunk` with unitsBudget=1000, cursor resume, `_winnerUnits` per-winner cost | Single-pass `_processDailyEthChunk`, no budget, no cursors | Phase 95 (2026-03-24) | Removed dead code; ~64K-674K gas savings per call depending on compiler CSE |
| 333 max auto-rebuy winners per chunk (1000/3) | 321 max winners total (DAILY_ETH_MAX_WINNERS) | Phase 95 | Tighter bound (321 < 333), fewer winners per call |
| Phase 57 gas analysis: Stages 8,11 AT_RISK, Stage 6 TIGHT | Needs re-profiling | This phase (96) | Updated risk levels expected |

## Open Questions

1. **Compiler CSE for autoRebuyState**
   - What we know: The old code read `autoRebuyState[winner]` in `_winnerUnits` AND again in `_addClaimableEth`. The removal of `_winnerUnits` eliminates the first read.
   - What's unclear: Did `via_ir=true` already optimize away the duplicate SLOAD? If so, the gas savings from chunk removal are smaller than estimated.
   - Recommendation: Empirical measurement with `forge snapshot --diff` comparing before/after chunk removal. Compare a commit before Phase 95 vs current.

2. **claimablePool Accumulation Pattern**
   - What we know: `_processDailyEthChunk` accumulates `liabilityDelta` in memory and does ONE `claimablePool += liabilityDelta` at the end. This avoids per-winner SSTORE.
   - What's unclear: Is this already the optimal pattern? Alternative: could the compiler inline this differently?
   - Recommendation: This is already optimal -- no change needed. Document as "already optimized."

3. **Realistic Maximum Winner Count on Final Day**
   - What we know: `bucketCountsForPoolCap` scales winners based on pool size / ticket unit. Final day uses 100% of pool.
   - What's unclear: What pool size is needed to trigger 321 winners? With typical ticket prices, is 321 achievable in practice?
   - Recommendation: Compute the minimum pool size needed for 321 winners using `PriceLookupLib.priceForLevel` at various levels. This establishes whether the 321-winner worst case is realistic or purely theoretical.

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameJackpotModule.sol` - Post-chunk-removal `_processDailyEthChunk` (lines 1329-1424), `payDailyJackpot` (lines 313-638), `_addClaimableEth` (lines 928-949), `_processAutoRebuy` (lines 959-999), `_clearDailyEthState` (lines 2699-2705)
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Stage dispatch (lines 340-397), resume detection (lines 364-371)
- `contracts/storage/DegenerusGameStorage.sol` - Storage layout documentation (Slot 0 and Slot 1 packed layouts), daily ETH state variables
- `.planning/milestones/v3.5-phases/57-gas-ceiling-analysis/57-01-advancegame-gas-analysis.md` - Prior Phase 57 gas analysis with per-stage breakdowns, risk classifications, per-winner gas costs
- `.planning/phases/95-delta-verification/95-BEHAVIORAL-TRACE.md` - Proof that chunk removal is behaviorally equivalent (321 x 3 = 963 < 1000)
- `foundry.toml` - Compiler settings: via_ir=true, optimizer_runs=2, evm_version=paris

### Secondary (MEDIUM confidence)
- `test/gas/AdvanceGameGas.test.js` - Existing Hardhat gas benchmark test pattern
- `test/fuzz/RedemptionGas.t.sol` - Existing Foundry gas benchmark pattern with DeployProtocol
- EVM gas costs: SLOAD cold 2,100, warm 100; SSTORE cold 5,000-22,100; event 375/topic + 8/byte

## Metadata

**Confidence breakdown:**
- Standard stack/architecture: HIGH - Direct code analysis of all post-chunk-removal functions, cross-referenced with Phase 57 analysis
- Gas estimates: MEDIUM - Static analysis estimates are sound but need empirical validation; compiler behavior with via_ir/runs=2 introduces uncertainty
- SLOAD audit: HIGH - Direct storage layout analysis with per-slot documentation
- Pitfalls: HIGH - Based on Phase 57 experience and Phase 95 chunk removal context
- Optimization opportunities: MEDIUM - Identified candidates but magnitude depends on compiler behavior

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (code-stable; gas costs stable; invalidated by any changes to _processDailyEthChunk or _addClaimableEth)
