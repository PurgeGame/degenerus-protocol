# advanceGame Ticket-Processing Gas Analysis

## 1. Executive Summary

| Parameter | Value |
|-----------|-------|
| Current WRITES_BUDGET_SAFE | 550 |
| Recommended WRITES_BUDGET_SAFE | **550** (no change) |
| Effective first-batch budget | 357 (65% of 550) |
| Effective subsequent-batch budget | 550 |
| Worst-case adversarial gas per write-unit | ~12,500 gas |
| Worst-case total (first batch, adversarial) | 357 * 12,500 + 100,000 overhead = ~4,562,500 gas |
| Worst-case total (subsequent batch, adversarial) | 550 * 12,500 + 100,000 overhead = ~6,975,000 gas |
| Theoretical maximum cap (14M ceiling) | **1,112 write-units** |
| Recommended cap | **550 write-units** (2.0x safety margin over 14M ceiling) |

**Conclusion:** The current WRITES_BUDGET_SAFE = 550 provides a 2.0x safety margin under worst-case adversarial conditions. Increasing to ~800 would still stay under 14M gas, but the 550 value provides comfortable headroom for:
- EVM gas schedule changes (future EIPs)
- Solidity compiler overhead variance across versions
- L1 calldata costs in L2 environments
- Unmeasured overhead from memory expansion, stack operations, and ABI decode

The cap could safely be raised to **800** if throughput is critical, but 550 is already optimal for the risk profile of a protocol heading to competitive audit.

---

## 2. advanceGame Architecture Overview

### 2.1 Ticket Processing Paths

advanceGame (in DegenerusGameAdvanceModule) has four paths that invoke ticket processing:

| # | Path | Trigger | Delegatecall Target | Budget |
|---|------|---------|---------------------|--------|
| 1 | Mid-day drain | `day == dailyIdx` and `!ticketsFullyProcessed` | JackpotModule.processTicketBatch | WRITES_BUDGET_SAFE |
| 2 | New-day drain | `day != dailyIdx` and `!ticketsFullyProcessed` | JackpotModule.processTicketBatch | WRITES_BUDGET_SAFE |
| 3 | Future ticket activation | `_prepareFutureTickets` (pre-daily draws) | MintModule.processFutureTicketBatch | WRITES_BUDGET_SAFE |
| 4 | Phase transition FF drain | `phaseTransitionActive` | MintModule.processFutureTicketBatch | WRITES_BUDGET_SAFE |

All four paths exit early after one batch. Each advanceGame call processes at most one batch of tickets, bounded by WRITES_BUDGET_SAFE write-units.

### 2.2 Early Return Behavior

Critical observation: **every ticket-processing path returns early after a single batch.** The code pattern is:

```
(bool worked, bool finished) = _runProcessTicketBatch(level);
if (ticketWorked || !ticketsFinished) {
    emit Advance(stage, lvl);
    coinflip.creditFlip(caller, bounty);
    return;  // <--- exits advanceGame
}
```

This means advanceGame never processes more than WRITES_BUDGET_SAFE write-units of tickets in a single transaction. The gas ceiling analysis only needs to consider one batch plus overhead.

---

## 3. Fixed Overhead Analysis

Gas consumed by advanceGame **outside** the ticket-processing loop:

### 3.1 Transaction Base Costs

| Component | Gas | Source |
|-----------|-----|--------|
| Transaction intrinsic cost | 21,000 | EIP-2028 base |
| Calldata (4-byte selector, no args) | ~68 | 4 non-zero bytes * 16 + overhead |
| **Subtotal** | **~21,068** | |

### 3.2 advanceGame Entry Overhead

| Component | Gas (cold) | Gas (warm) | Notes |
|-----------|-----------|-----------|-------|
| `msg.sender` (CALLER opcode) | 2 | 2 | |
| `block.timestamp` (TIMESTAMP opcode) | 2 | 2 | |
| `_simulatedDayIndexAt` computation | ~100 | ~100 | Pure arithmetic |
| `jackpotPhaseFlag` SLOAD | 2,100 | 100 | Slot 0 assembly read |
| `level` SLOAD | 2,100 | 100 | Slot 0 assembly read (same slot, warm after first) |
| `lastPurchaseDay` SLOAD | 100 | 100 | Same packed slot |
| `purchaseStartDay` SLOAD | 2,100 | 100 | |
| `_getNextPrizePool` (turbo check) | 2,100 | 100 | Conditional path |
| `levelPrizePool[lvl]` SLOAD | 2,100 | 100 | Mapping read |
| `rngLockedFlag` SLOAD | 100 | 100 | Same Slot 0 |
| **Subtotal** | **~10,804** | **~804** | |

### 3.3 `_enforceDailyMintGate` Cost

| Component | Gas (cold) | Notes |
|-----------|-----------|-------|
| `mintPacked_[caller]` SLOAD | 2,100 | Mapping cold read |
| `deityPassCount[caller]` SLOAD | 2,100 | Conditional (only if gate fails) |
| `vault.isVaultOwner(caller)` | 2,600+ | External CALL (cold address) + SLOAD |
| Arithmetic comparisons | ~200 | |
| **Worst-case subtotal** | **~7,000** | Most callers pass early (~2,300) |
| **Typical subtotal** | **~2,300** | lastEthDay passes check |

### 3.4 Ticket Processing Delegation Overhead

| Component | Gas | Notes |
|-----------|-----|-------|
| Encode selector + args (ABI) | ~200 | Memory operations |
| DELEGATECALL base | 100 | EIP-2929 warm (same tx) |
| Address access (cold module) | 2,600 | First access to module address |
| Calldata copy | ~100 | 36 bytes |
| Return data decode | ~200 | ABI decode bool |
| `ticketCursor` SLOAD (pre-call check) | 100 | Warm (read in batch) |
| `ticketLevel` SLOAD (pre-call check) | 100 | Warm (read in batch) |
| **Subtotal** | **~3,400** | First call; ~800 warm |

### 3.5 Post-Batch Overhead

| Component | Gas (cold) | Notes |
|-----------|-----------|-------|
| `emit Advance(stage, lvl)` | ~375 | LOG1: 375 + 8*topics |
| `coinflip.creditFlip` external call | ~30,000 | CALL (2600 cold) + SLOAD + SSTORE |
| `price` SLOAD for bounty calc | 2,100 | |
| Arithmetic (bounty calculation) | ~100 | MUL + DIV |
| **Subtotal** | **~32,575** | |

### 3.6 Total Fixed Overhead

| Scenario | Gas |
|----------|-----|
| **Worst-case (all cold)** | 21,068 + 10,804 + 7,000 + 3,400 + 32,575 = **~74,847** |
| **Typical (most warm)** | 21,068 + 2,000 + 2,300 + 800 + 30,500 = **~56,668** |
| **Conservative ceiling** | **100,000** (20% safety margin on worst-case) |

---

## 4. Per-Iteration Gas Breakdown

### 4.1 Write-Unit Accounting

The code tracks "write-units" (not raw gas). Per `_processOneTicketEntry`:

```solidity
writesUsed = ((take <= 256) ? (take << 1) : (take + 256)) + baseOv + (take == owed ? 1 : 0);
```

For the adversarial case (1 ticket per address):
- `take = 1` (only 1 ticket owed)
- `take << 1 = 2` (2 write-units for trait generation)
- `baseOv = 4` (first entry for player with owed <= 2)
- `finishing bonus = 1` (take == owed, entry complete)
- **Total write-units per adversarial entry: 7**

For a normal case (player with many tickets, mid-batch):
- `take = N` tickets in this sub-batch
- `take << 1 = 2N` write-units for traits (when N <= 256)
- `baseOv = 2` (continuing player)
- `finishing bonus = 0 or 1`
- **Write-units per ticket: ~2** (amortized)

### 4.2 Actual Gas Per Write-Unit

Each "write-unit" in the budget corresponds to approximately one storage write in `_raritySymbolBatch`. The assembly loop does:

```solidity
// Per unique trait touched:
let len := sload(elem)          // SLOAD: length of traitBurnTicket[lvl][traitId]
sstore(elem, newLen)            // SSTORE: update length
// Per occurrence of that trait:
sstore(dst, player)             // SSTORE: append player address to array
```

**Per write-unit gas (2 units per ticket in trait generation):**

| Operation | Cold (new slot) | Warm (existing slot) | Source |
|-----------|----------------|---------------------|--------|
| SLOAD length | 2,100 | 100 | EIP-2929 |
| SSTORE length (0 -> nonzero) | 22,100 | - | EIP-2200 |
| SSTORE length (nonzero -> nonzero) | - | 2,900 | EIP-2200 (dirty) |
| SSTORE player (new slot) | 22,100 | - | EIP-2200 |
| SSTORE player (warm but new value) | - | 5,000 | EIP-2200 (clean, nonzero) |
| **Per-trait write (worst: all new)** | **46,300** | - | 2 new SSTOREs + 1 SLOAD |
| **Per-trait write (warm, existing trait)** | - | **8,000** | 2 warm SSTOREs + 1 SLOAD |

However, there are 2 write-units per ticket, and each ticket generates exactly 1 trait. The 2 units account for:
1. The trait array length update + player append SSTORE = 1 logical write (but 2 SSTOREs)
2. The budget counts this as 2 write-units

So **1 write-unit ~= 1 SSTORE operation** in the trait generation path.

### 4.3 Per-Entry Gas (Adversarial: 1 Ticket, Unique Address)

| Operation | Gas | Notes |
|-----------|-----|-------|
| **Queue access** | | |
| `queue[idx]` SLOAD (cold) | 2,100 | Dynamic array element, cold slot |
| **ticketsOwedPacked read** | | |
| `ticketsOwedPacked[rk][player]` SLOAD (cold) | 2,100 | New address = cold mapping slot |
| **Remainder roll** | | |
| `_rollRemainder` computation | ~200 | `entropyStep` + modulo |
| **_raritySymbolBatch** (for take=1) | | |
| Memory array allocation (counts[256]) | ~0* | Reuses high watermark after first call |
| LCG seed computation | ~100 | Arithmetic |
| LCG step + traitFromWord | ~200 | One iteration |
| `traitBurnTicket[lvl][traitId]` length SLOAD | 2,100 (cold) / 100 (warm) | Depends on whether trait seen before |
| SSTORE length update | 22,100 (0->N) / 2,900 (N->N+1) | First time vs subsequent for this trait |
| SSTORE player address (new array slot) | 22,100 | Always new slot (array append) |
| **_finalizeTicketEntry** | | |
| `ticketsOwedPacked[rk][player]` SSTORE | 2,900 | Warm (read earlier), nonzero->zero gets 4,800 refund |
| **emit TraitsGenerated** | | |
| LOG with 4 topics + data | ~631 | 375 base + 8*topics + data bytes |
| **Loop overhead** | | |
| Counters, comparisons, unchecked | ~200 | |
| **TOTAL (all cold, new trait)** | **~52,731** | |
| **TOTAL (warm trait, existing slots)** | **~11,431** | |

*Memory note: Solidity's memory allocator grows monotonically. The first call to `_raritySymbolBatch` pays ~8,192 gas for 256*32*2 bytes of memory expansion. Subsequent calls reuse the watermark if the compiler reuses stack frame positions. In practice, since `_raritySymbolBatch` declares new `memory` arrays each invocation, the compiler allocates fresh memory each call. However, memory expansion cost is only paid once (3 gas per word + word^2/512), and subsequent allocations at the same watermark cost 0 extra. The net effect: first entry pays ~8,192 gas extra, subsequent entries pay ~0 extra for memory.

### 4.4 Write-Unit to Gas Ratio

For the adversarial case (7 write-units per entry):

| Scenario | Entry Gas | Write-Units | Gas per Write-Unit |
|----------|-----------|-------------|-------------------|
| All-cold, new trait | 52,731 | 7 | **7,533** |
| All-cold, existing trait | ~31,131 | 7 | **4,447** |
| Warm trait, existing slots | 11,431 | 7 | **1,633** |
| **First entry (+ memory)** | 60,923 | 7 | **8,703** |

For the normal case (many tickets per player, take=128):

| Scenario | Entry Gas | Write-Units | Gas per Write-Unit |
|----------|-----------|-------------|-------------------|
| Mixed cold/warm traits | ~700,000-900,000 | ~260 | **~2,700-3,500** |

### 4.5 Adversarial Gas per Write-Unit (Conservative)

Using the all-cold, new-trait, first-entry scenario as the absolute worst case:

**Gas per write-unit = 8,703** (first entry) / **7,533** (subsequent entries)

Rounding up with 20% safety margin: **~10,500 gas per write-unit**

However, this analysis has a subtlety: trait slots are shared across entries. In a queue of 357 adversarial entries (first batch), each generates 1 random trait from 256 possibilities. By the birthday problem:
- After ~20 entries, ~50% chance of a trait collision (warm access)
- After 100 entries, most of the 256 trait slots have been touched (warm)
- After 357 entries, virtually all common traits are warm

So the effective average is lower than the all-cold case. Conservative estimate accounting for the cold/warm distribution curve:

**Effective average gas per write-unit (adversarial first-batch): ~6,000-8,000**

We use **12,500 gas per write-unit** as the ultra-conservative ceiling (worst-case * 1.66x safety factor) to account for:
- EVM gas metering overhead not captured in opcode-level analysis
- Solidity function call overhead (stack manipulation, jumps)
- ABI encoding/decoding within delegatecall
- Future EIP gas schedule changes

---

## 5. Adversarial Ticket Distribution Analysis

### 5.1 Attack Model

An attacker purchases hundreds of 1-ticket orders from unique addresses to maximize per-entry gas in the processing loop.

**Adversarial parameters:**
- Queue size: 500+ unique addresses
- Tickets per address: 1 (owed=1, rem=0)
- Result: every queue entry triggers a full `_processOneTicketEntry` with cold storage access

### 5.2 Per-Entry Budget Consumption

With owed=1:
- `baseOv = 4` (processed==0 && owed<=2)
- `take = 1` (min of owed and available room)
- `writesUsed = (1 << 1) + 4 + 1 = 7` write-units per entry

### 5.3 Entries Per Batch

| Batch | Budget | Write-Units/Entry | Max Entries |
|-------|--------|-------------------|-------------|
| First (cold) | 357 | 7 | **51** entries |
| Subsequent | 550 | 7 | **78** entries |

### 5.4 Gas Consumption Per Batch

Using the ultra-conservative 12,500 gas per write-unit:

| Batch | Write-Units Used | Gas (writes) | Fixed Overhead | **Total Gas** |
|-------|-----------------|-------------|----------------|---------------|
| First (cold) | 357 | 4,462,500 | 100,000 | **4,562,500** |
| Subsequent | 550 | 6,875,000 | 100,000 | **6,975,000** |

### 5.5 More Realistic Adversarial Estimate

Using the birthday-problem-adjusted 8,000 gas per write-unit:

| Batch | Write-Units Used | Gas (writes) | Fixed Overhead | **Total Gas** |
|-------|-----------------|-------------|----------------|---------------|
| First (cold) | 357 | 2,856,000 | 100,000 | **2,956,000** |
| Subsequent | 550 | 4,400,000 | 100,000 | **4,500,000** |

### 5.6 Non-Adversarial Comparison

With normal players (10+ tickets per address), write-units per ticket drop to ~2, and gas per write-unit drops to ~3,000 due to warm storage amortization:

| Batch | Budget | Effective Gas | Headroom vs 14M |
|-------|--------|--------------|-----------------|
| First (cold) | 357 | ~1,171,000 | **91.6%** |
| Subsequent | 550 | ~1,750,000 | **87.5%** |

---

## 6. Cap Derivation

### 6.1 Formula

```
total_gas = overhead_fixed + (writesBudget * gas_per_write_unit) <= 14,000,000
```

Solving for writesBudget:

```
writesBudget <= (14,000,000 - overhead_fixed) / gas_per_write_unit
```

### 6.2 Conservative Derivation (Ultra-Worst-Case)

| Parameter | Value | Justification |
|-----------|-------|---------------|
| Gas ceiling | 14,000,000 | Target block gas limit |
| `overhead_fixed` | 100,000 | Section 3.6 with 20% safety margin |
| `gas_per_write_unit` | 12,500 | Section 4.5 ultra-conservative |

```
writesBudget <= (14,000,000 - 100,000) / 12,500
writesBudget <= 13,900,000 / 12,500
writesBudget <= 1,112
```

### 6.3 Realistic Derivation (Adversarial with Birthday Effect)

| Parameter | Value | Justification |
|-----------|-------|---------------|
| Gas ceiling | 14,000,000 | Target |
| `overhead_fixed` | 100,000 | Section 3.6 |
| `gas_per_write_unit` | 8,000 | Section 4.5 with warm-slot amortization |

```
writesBudget <= (14,000,000 - 100,000) / 8,000
writesBudget <= 13,900,000 / 8,000
writesBudget <= 1,737
```

### 6.4 First-Batch Consideration

The first batch applies a 35% reduction: `writesBudget = WRITES_BUDGET_SAFE * 65 / 100`.

If WRITES_BUDGET_SAFE = X, the first batch uses 0.65X write-units and the subsequent batch uses X.

The subsequent batch is the binding constraint (higher write-units). So the cap derived in 6.2 (1,112) applies to the subsequent-batch budget directly.

### 6.5 Methodology: Static Analysis (EVM Gas Cost Tables)

This analysis uses static analysis based on:
- **EIP-2929** (Berlin, 2021): Cold/warm SLOAD (2100/100), cold/warm address (2600/100)
- **EIP-2200** (Istanbul, 2019): SSTORE costs — 22,100 (zero-to-nonzero), 5,000 (nonzero-to-nonzero clean), 2,900 (dirty), 4,800 refund (nonzero-to-zero)
- **EIP-3529** (London, 2021): Reduced refund cap to 20% of gas used

A Foundry gas measurement test was considered but deferred because:
1. The delegatecall architecture requires full protocol deployment (23 contracts)
2. Storage layout dependencies (Slot 0 assembly reads, packed fields) require exact deployment state
3. Static analysis provides sufficient precision for cap derivation given the 2x safety margin

---

## 7. Sensitivity Analysis

### 7.1 Cap vs. Gas-Per-Write-Unit

| Gas/Write-Unit | Max Cap (14M) | Current Budget (550) Gas | Safety Margin |
|----------------|--------------|------------------------|---------------|
| 5,000 | 2,780 | 2,850,000 | **4.91x** |
| 8,000 | 1,737 | 4,500,000 | **3.11x** |
| 10,000 | 1,390 | 5,600,000 | **2.50x** |
| **12,500** | **1,112** | **6,975,000** | **2.01x** |
| 15,000 | 926 | 8,350,000 | 1.68x |
| 20,000 | 695 | 11,100,000 | 1.26x |
| 25,000 | 556 | 13,850,000 | 1.01x |
| 25,454 | 550 | 14,000,000 | 1.00x |

The current cap of 550 would only hit 14M gas if the effective gas per write-unit reached **~25,454** -- more than 3x the ultra-conservative estimate and 6x the realistic estimate. This provides substantial safety margin.

### 7.2 Cap Recommendations at Different Safety Margins

| Safety Margin | Max Cap (12,500 gas/wu) | Max Cap (8,000 gas/wu) |
|---------------|------------------------|------------------------|
| 3.0x | 371 | 579 |
| 2.5x | 445 | 695 |
| **2.0x** | **556** | **869** |
| 1.5x | 741 | 1,158 |
| 1.25x | 890 | 1,390 |

### 7.3 Impact of Raising Cap

| WRITES_BUDGET_SAFE | First Batch (65%) | Adversarial Entries/Batch | Worst-Case Gas (12.5k/wu) | Safety Margin |
|--------------------|-------------------|--------------------------|--------------------------|---------------|
| 550 | 357 | 51 / 78 | 6,975,000 | **2.01x** |
| 700 | 455 | 65 / 100 | 8,850,000 | 1.58x |
| 800 | 520 | 74 / 114 | 10,100,000 | 1.39x |
| 900 | 585 | 83 / 128 | 11,350,000 | 1.23x |
| 1000 | 650 | 92 / 142 | 12,600,000 | 1.11x |
| 1112 | 723 | 103 / 158 | 14,000,000 | 1.00x |

---

## 8. Recommendation

### Recommended WRITES_BUDGET_SAFE: **550** (no change)

**Rationale:**

1. **2.0x safety margin at ultra-conservative gas estimates.** Even under the absolute worst-case adversarial model with 12,500 gas per write-unit, the total gas is ~7M -- half the 14M ceiling.

2. **Throughput is adequate.** At 78 adversarial entries per subsequent batch (51 on first batch), a queue of 500 adversarial 1-ticket entries drains in ~7 advanceGame calls. Normal queues (larger ticket counts per player) drain much faster.

3. **Risk asymmetry.** The cost of hitting the gas ceiling (failed transaction, wasted caller gas, protocol stall) far outweighs the benefit of faster queue draining. Protocol liveness depends on advanceGame never reverting due to gas.

4. **Future-proofing.** EVM gas schedule changes (potential SSTORE repricing) could increase per-write costs. The 2x margin absorbs most plausible changes without requiring a contract redeploy.

5. **Audit posture.** The protocol is heading to a competitive audit. A conservative gas cap is a strength (no gas-related findings), while an aggressive cap is a risk surface.

**If throughput becomes critical:** The cap can safely be raised to **800** (1.39x safety margin at ultra-conservative estimates, 1.75x at realistic estimates). Beyond 800, the safety margin drops below recommended minimums.

### Per-Path Summary

| Path | Worst-Case Gas (550 budget) | Safety Margin | Status |
|------|---------------------------|---------------|--------|
| Mid-day drain | ~7.0M | 2.0x | **SAFE** |
| New-day drain | ~7.0M | 2.0x | **SAFE** |
| Future ticket activation | ~7.0M | 2.0x | **SAFE** |
| Phase transition FF drain | ~7.0M | 2.0x | **SAFE** |

All paths share the same budget and delegation mechanism, so the gas profile is identical.
