# Unit 5: Mint + Purchase Flow -- Coverage Review

**Agent:** Taskmaster (Coverage Enforcer)
**Date:** 2026-03-25

---

## Function Checklist Verification

I verified every checklist function against the ATTACK-REPORT.md sections:

### Category B

| # | Function | Attack Report Section? | Call Tree Complete? | Storage Writes Complete? | Cache Check Done? |
|---|----------|----------------------|--------------------|-----------------------|------------------|
| B1 | `recordMintData` | YES (lines 175-284) | YES | YES (1 variable) | YES |
| B2 | `processFutureTicketBatch` | YES (lines 295-434) | YES (full loop expansion) | YES (5 variables) | YES |
| B3 | `purchase` via `_purchaseFor` | YES (lines 560-829) | YES (full tree with 19 storage writes) | YES (19 variables) | YES (3 cache pairs checked) |
| B4 | `purchaseCoin` via `_purchaseCoinFor` | YES (lines 581-626) | YES | YES (via C3/C5) | YES |
| B5 | `purchaseBurnieLootbox` via `_purchaseBurnieLootboxFor` | YES (lines 595-1071) | YES | YES (4 variables) | YES |

### Category C

| # | Function | Attack Report Section? | Analyzed In Context? | Flags Verified? |
|---|----------|----------------------|--------------------|----------------|
| C1 | `_purchaseFor` | YES (Part 1, B3 section) | Full standalone analysis | N/A |
| C2 | `_purchaseCoinFor` | YES (Part 1, B4 section) | In B4 call tree | N/A |
| C3 | `_callTicketPurchase` | YES (Part 2, MULTI-PARENT) | Cross-parent analysis done | [MULTI-PARENT] verified |
| C4 | `_coinReceive` | YES (in C3 call tree) | In payInCoin path | N/A |
| C5 | `_purchaseBurnieLootboxFor` | YES (Part 2, MULTI-PARENT) | Cross-parent analysis done | [MULTI-PARENT] verified |
| C6 | `_maybeRequestLootboxRng` | YES (Part 2, MULTI-PARENT) | Cross-parent analysis done | [MULTI-PARENT] verified |
| C7 | `_applyLootboxBoostOnPurchase` | YES (in C1 call tree) | In B3 lootbox path | N/A |
| C8 | `_raritySymbolBatch` | YES (Part 3, Assembly) | Full Yul verification | [ASSEMBLY] verified |
| C9 | `_recordMintStreakForLevel` | YES (Part 5, Inherited) | Streak logic analyzed | [INHERITED] verified |
| C10 | `_queueTicketsScaled` | YES (Part 5, Inherited) | Full analysis in C3 context | [INHERITED] verified |
| C11 | `_awardEarlybirdDgnrs` | YES (Part 5, Inherited) | Full analysis in C1 context | [INHERITED] verified |

### Category D

| # | Function | Attack Report Section? | Reviewed? |
|---|----------|----------------------|-----------|
| D1 | `_rollRemainder` | YES (Part 6) | Modulo bias checked |
| D2 | `_ethToBurnieValue` | YES (Part 6) | Div-by-zero checked |
| D3 | `_calculateBoost` | YES (Part 6) | Unchecked overflow checked |
| D4 | `_mintStreakEffective` | YES (Part 6) | View correctness verified |

---

## Spot-Check Interrogation Questions

### Q1: _callTicketPurchase caches `priceWei = price` at line 856, then calls `recordMint` at line 918 which routes ETH to prize pools. Does `recordMint` write to `price`?

**Answer:** Verified. DegenerusGame.recordMint() handles ETH routing (currentPrizePool, prizePoolsPacked, claimableWinnings deductions) and delegates to recordMintData (mintPacked_ only). `price` is only written in AdvanceModule during level transitions. SAFE.

### Q2: The lootbox pool split at lines 752-763 writes to `prizePoolsPacked` or `prizePoolPendingPacked`. Does any ancestor cache these values?

**Answer:** Verified. `_purchaseFor` does NOT cache `prizePoolsPacked` or `prizePoolPendingPacked` in local variables. All reads go through `_getPrizePools()` / `_getPendingPools()` helpers, and writes go through `_setPrizePools()` / `_setPendingPools()` helpers. No stale-cache risk.

### Q3: In `processFutureTicketBatch`, the assembly at line 518 updates array length BEFORE writing data (lines 524-531). If the transaction reverts mid-write, could length be updated without corresponding data?

**Answer:** Verified. EVM reverts roll back ALL state changes atomically (including both the length SSTORE and the data SSTOREs). The ordering within the assembly block does not matter for revert safety. Within a successful execution, the length is correct because `newLen = len + occurrences` is computed before any writes, and exactly `occurrences` data entries are written in the for loop. SAFE.

### Q4: `_purchaseCoinFor` passes `MintPaymentKind.DirectEth` to `_callTicketPurchase` at line 616, but this is a BURNIE purchase. Is this correct?

**Answer:** Verified. When `payInCoin=true` (line 617 `true`), `_callTicketPurchase` takes the `payInCoin` path at line 903 which calls `_coinReceive(payer, coinCost)` (burns BURNIE). The `payKind` parameter is unused in the BURNIE path -- it only matters for the ETH path (line 927+). Passing `DirectEth` is harmless because the BURNIE path never reads it. SAFE.

### Q5: Century bonus at line 880 checks `targetLevel % 100 == 0`. Can this be triggered by both ETH and BURNIE paths?

**Answer:** Verified. `_callTicketPurchase` is called from both C1 (ETH, payInCoin=false) and C2 (BURNIE, payInCoin=true). The century bonus logic at lines 880-900 is OUTSIDE the `if (!payInCoin)` boost block and OUTSIDE the `if (payInCoin)` / `else` ETH block. It applies to BOTH paths. The century bonus uses `IDegenerusGame(address(this)).playerActivityScore(buyer)` which is a view self-call. The bonus tickets are added to `adjustedQty32` regardless of payment method. CONFIRMED: both ETH and BURNIE purchases can trigger century bonus. This appears intentional (reward engagement regardless of payment method).

---

## Gaps Found

None. Every function on the checklist has a corresponding analysis section in ATTACK-REPORT.md. All call trees are fully expanded with line numbers. All storage writes are mapped. All cached-local-vs-storage checks are present. No "similar to above" shortcuts detected.

---

## Verdict: PASS

All 20 functions (5B + 11C + 4D) analyzed with full call trees, storage-write maps, and cached-local-vs-storage checks. All 3 MULTI-PARENT helpers received cross-parent scrutiny. Assembly verification complete. Self-call re-entry analysis complete. 100% coverage achieved.
