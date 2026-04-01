# Phase 107: Mint + Purchase Flow - Research

**Date:** 2026-03-25
**Contracts:** DegenerusGameMintModule.sol (~1,167 lines), DegenerusGameMintStreakUtils.sol (62 lines)

---

## Complete Function Inventory

### Category B: External/Public State-Changing (5 functions)

| # | Function | Lines | Access | Risk Tier | Subsystem |
|---|----------|-------|--------|-----------|-----------|
| B1 | `recordMintData(address,uint24,uint32)` | 175-284 | external payable | Tier 2 | MINT-DATA |
| B2 | `processFutureTicketBatch(uint24)` | 295-434 | external | Tier 1 | TICKET-DRAIN |
| B3 | `purchase(address,uint256,uint256,bytes32,MintPaymentKind)` | 560-574 | external payable | Tier 1 | ETH-PURCHASE |
| B4 | `purchaseCoin(address,uint256,uint256)` | 581-591 | external | Tier 2 | COIN-PURCHASE |
| B5 | `purchaseBurnieLootbox(address,uint256)` | 595-598 | external | Tier 3 | BURNIE-LOOT |

**Risk Tier Justification:**
- **Tier 1 (B2, B3):** `processFutureTicketBatch` has inline Yul assembly, complex batch state machine with cursor/level tracking, remainder rolling. `purchase` is the primary ETH inflow path with complex lootbox pool splits, claimable payment paths, affiliate integration, boost application, and earlybird DGNRS rewards. Both have deep call trees (6+ levels).
- **Tier 2 (B1, B4):** `recordMintData` has complex bit-packing logic with whale bundle frozen state and level transition edge cases. `purchaseCoin` has BURNIE cutoff timing and delegates to shared helpers.
- **Tier 3 (B5):** `purchaseBurnieLootbox` is a thin wrapper that delegates to `_purchaseBurnieLootboxFor`.

### Category C: Internal/Private State-Changing Helpers (11 functions)

| # | Function | Lines | Contract | Called By | Key Storage Writes | Flags |
|---|----------|-------|----------|-----------|-------------------|-------|
| C1 | `_purchaseFor()` | 628-829 | MintModule | B3 | claimableWinnings, claimablePool, lootboxEth, lootboxDay, lootboxBaseLevelPacked, lootboxEvScorePacked, lootboxEthBase, lootboxDistressEth, prizePoolsPacked/prizePoolPendingPacked, lootboxPresaleMintEth, lootboxRngPendingEth, boonPacked, earlybirdDgnrsPoolStart, earlybirdEthIn | |
| C2 | `_purchaseCoinFor()` | 600-626 | MintModule | B4 | (delegates to C4, C7) | |
| C3 | `_callTicketPurchase()` | 831-1024 | MintModule | C1, C2 | centuryBonusLevel, centuryBonusUsed, ticketQueue, ticketsOwedPacked | [MULTI-PARENT] |
| C4 | `_coinReceive()` | 1026-1031 | MintModule | C2 (via C3 payInCoin path) | (external: coin.burnCoin) | |
| C5 | `_purchaseBurnieLootboxFor()` | 1039-1071 | MintModule | B5, C2 | lootboxBurnie, lootboxDay, lootboxRngPendingBurnie, lootboxRngPendingEth | [MULTI-PARENT] |
| C6 | `_maybeRequestLootboxRng()` | 1073-1075 | MintModule | C1, C5 | lootboxRngPendingEth | [MULTI-PARENT] |
| C7 | `_applyLootboxBoostOnPurchase()` | 1085-1112 | MintModule | C1 | boonPacked[player].slot0 | |
| C8 | `_raritySymbolBatch()` | 443-537 | MintModule | B2 | traitBurnTicket[level][trait] (via assembly) | [ASSEMBLY] |
| C9 | `_recordMintStreakForLevel()` | 17-46 | MintStreakUtils | (called from GameStorage helpers, not directly from MintModule) | mintPacked_[player] | |
| C10 | `_queueTicketsScaled()` | 556-594 | GameStorage | C3 | ticketQueue[key], ticketsOwedPacked[key][player] | [INHERITED] |
| C11 | `_awardEarlybirdDgnrs()` | 914-974 | GameStorage | C1 | earlybirdDgnrsPoolStart, earlybirdEthIn, (external: sDGNRS.transferFromPool, transferBetweenPools) | [INHERITED] |

**Notes:**
- C3 `_callTicketPurchase` is MULTI-PARENT: called from `_purchaseFor` (ETH path) and `_purchaseCoinFor` (BURNIE path) with different payment kinds and value parameters.
- C5 `_purchaseBurnieLootboxFor` is MULTI-PARENT: called from B5 directly and from C2 when `lootBoxBurnieAmount != 0`.
- C6 `_maybeRequestLootboxRng` is MULTI-PARENT: called from C1 (ETH lootbox) and C5 (BURNIE lootbox).
- C8 `_raritySymbolBatch` uses inline Yul assembly for storage slot calculation and bulk writes.
- C9, C10, C11 are inherited from parent contracts but called within MintModule's execution context.

### Category D: View/Pure Functions (4 functions)

| # | Function | Lines | Reads/Computes | Security Note |
|---|----------|-------|---------------|---------------|
| D1 | `_rollRemainder()` | 540-547 | EntropyLib.entropyStep, modulo TICKET_SCALE | Fractional ticket probability. Modulo bias check needed (TICKET_SCALE=100). |
| D2 | `_ethToBurnieValue()` | 1034-1037 | Pure arithmetic: amountWei * PRICE_COIN_UNIT / priceWei | Division by zero guarded by `priceWei == 0` check. |
| D3 | `_calculateBoost()` | 1078-1083 | Pure arithmetic: cappedAmount * bonusBps / 10_000 | Overflow safe in unchecked block due to LOOTBOX_BOOST_MAX_VALUE cap (10 ETH). |
| D4 | `_mintStreakEffective()` | 49-61 | MintStreakUtils view: reads mintPacked_[player] | Returns 0 if level missed. No state change. |

---

## Ticket Lifecycle Analysis (Write Side)

### Queue Write Paths

All ticket writes ultimately flow through `_queueTicketsScaled()` (GameStorage L556-594):

```
B3: purchase()
  -> C1: _purchaseFor()
    -> C3: _callTicketPurchase()
      -> C10: _queueTicketsScaled(buyer, ticketLevel, adjustedQty32)

B4: purchaseCoin()
  -> C2: _purchaseCoinFor()
    -> C3: _callTicketPurchase()  [payInCoin=true]
      -> C10: _queueTicketsScaled(buyer, ticketLevel, adjustedQty32)
```

### Ticket Level Routing (Critical Logic at C3 Lines 842-851)

```solidity
uint24 targetLevel = jackpotPhaseFlag ? level : level + 1;
// Last jackpot day fix: route to level+1 to prevent stranded tickets
if (jackpotPhaseFlag && rngLockedFlag) {
    uint8 cnt = jackpotCounter;
    uint8 comp = compressedJackpotFlag;
    uint8 step = comp == 2 ? JACKPOT_LEVEL_CAP
        : (comp == 1 && cnt > 0 && cnt < JACKPOT_LEVEL_CAP - 1) ? 2 : 1;
    if (cnt + step >= JACKPOT_LEVEL_CAP) targetLevel = level + 1;
}
```

This routing logic determines which level tickets target. If this is wrong, tickets could be stranded (queued for a level that never gets processed).

### Queue Read/Drain Path (Reference)

```
B2: processFutureTicketBatch(lvl)
  -> reads ticketQueue[readKey], ticketsOwedPacked[readKey][player]
  -> C8: _raritySymbolBatch() -- generates traits, writes traitBurnTicket via assembly
  -> D1: _rollRemainder() -- fractional ticket probability
  -> updates ticketCursor, ticketLevel, ticketsOwedPacked
```

Phase 104 audited the drain side and declared it PROVEN SAFE. This phase focuses on verifying the write side writes correctly and the batch processing logic is sound.

---

## Cross-Module Delegatecall Map

MintModule is delegatecalled from DegenerusGame. All storage reads/writes operate on Game's storage context.

### External Calls Made by MintModule

| Call | From | Target | State Impact | Direction |
|------|------|--------|-------------|-----------|
| `coin.creditFlip(buyer, amount)` | C1, C3 | BurnieCoin | BURNIE minting | Out |
| `coin.burnCoin(payer, amount)` | C4, C5 | BurnieCoin | BURNIE burning | Out |
| `coin.notifyQuestMint(buyer, qty, isEth)` | C1, C2, C3, C5 | BurnieCoin | Quest progress | Out |
| `coin.notifyQuestLootBox(buyer, amount)` | C1 | BurnieCoin | Lootbox quest | Out |
| `affiliate.payAffiliate(...)` | C1, C3 | DegenerusAffiliate | Affiliate payments (BURNIE) | Out |
| `IDegenerusGame(address(this)).recordMint{value}(...)` | C3 | DegenerusGame (self) | Mint recording (re-enters via delegatecall) | Self-call |
| `IDegenerusGame(address(this)).consumePurchaseBoost(payer)` | C3 | DegenerusGame (self) | Boost consumption | Self-call |
| `IDegenerusGame(address(this)).playerActivityScore(buyer)` | C1, C3 | DegenerusGame (self) | View: activity score | Self-call (view) |
| `payable(VAULT).call{value}("")` | C1 | DegenerusVault | ETH transfer (presale split) | Out |
| `sDGNRS.transferFromPool(...)` | C11 | StakedDegenerusStonk | DGNRS transfer | Out (inherited) |
| `sDGNRS.poolBalance(...)` | C11 | StakedDegenerusStonk | View: pool balance | Out (inherited, view) |
| `sDGNRS.transferBetweenPools(...)` | C11 | StakedDegenerusStonk | Pool rebalance | Out (inherited) |

### Self-Call Pattern (IMPORTANT)

`_callTicketPurchase` at line 918 does:
```solidity
IDegenerusGame(address(this)).recordMint{value: value}(payer, targetLevel, costWei, mintUnits, payKind);
```

This is a self-call (not delegatecall) back into DegenerusGame, which then dispatches to `recordMintData` via delegatecall. The ETH value is forwarded. This creates a re-entry pattern where the MintModule -> Game -> MintModule chain must be verified for state coherence.

---

## Risk Tiers for Category B Functions

### Tier 1 (Complex, Deep Call Trees, Assembly)

**B2: processFutureTicketBatch** -- Complex batch state machine with:
- Inline Yul assembly (_raritySymbolBatch)
- Cursor/level/far-future tracking across calls
- Write budget management with cold storage scaling
- Remainder rolling probability
- Queue cleanup and deletion

**B3: purchase** -- Primary ETH inflow with:
- Dual-path payment (ETH + claimable)
- Lootbox pool splits (normal vs presale vs distress)
- Affiliate payment integration
- Boost application + earlybird DGNRS rewards
- Century bonus calculation with per-player cap
- Complex ticket level routing (jackpotPhaseFlag, rngLockedFlag, compressedJackpotFlag)

### Tier 2 (Significant Flows)

**B1: recordMintData** -- Bit-packed storage manipulation with:
- Whale bundle frozen state tracking
- Level transition logic (same level vs new level with <4 units vs >=4 units)
- Century boundary handling

**B4: purchaseCoin** -- BURNIE ticket + lootbox purchase with:
- Coin purchase cutoff timing (90 days / 335 days)
- BURNIE burn via external call

### Tier 3 (Simpler)

**B5: purchaseBurnieLootbox** -- Thin wrapper: zero-address check, delegates to `_purchaseBurnieLootboxFor`.

---

## Key Pitfalls

1. **Cached-local-vs-storage in _purchaseFor (C1):** Caches `priceWei = price` (L637), `purchaseLevel = level + 1` (L636), `initialClaimable = claimableWinnings[buyer]` (L650). Then calls `_callTicketPurchase` which calls back into DegenerusGame via `recordMint{value}`. If `recordMint` writes to `price` or `level`, the cached values in `_purchaseFor` would be stale. Need to verify `recordMintData` does NOT write to `price` or `level`.

2. **Self-call re-entry pattern (C3 L918):** `IDegenerusGame(address(this)).recordMint{value}()` creates a call chain MintModule -> Game -> MintModule.recordMintData. The `msg.value` forwarding and storage state must be coherent across this chain.

3. **Inline assembly storage slot calculation (_raritySymbolBatch):** Uses `keccak256(lvl, traitBurnTicket.slot)` for level slot and `keccak256(elem)` for array data slot. Must verify this matches Solidity's standard storage layout for `mapping(uint24 => address[256])`.

4. **Ticket level routing edge cases (C3 L842-851):** The `jackpotPhaseFlag && rngLockedFlag` check with `compressedJackpotFlag` and `jackpotCounter` determines whether tickets route to `level` or `level + 1`. Wrong routing = tickets stranded at a level that never processes them.

5. **claimableWinnings deduction in _purchaseFor (C1 L669-677):** When `payKind != DirectEth`, the function deducts from `claimableWinnings[buyer]` and `claimablePool`. The 1-wei sentinel preservation (`claimable <= shortfall` reverts) must be verified to prevent underflow.

6. **Century bonus unchecked arithmetic (C3 L880-900):** `bonusQty` calculation uses `adjustedQty32 * score / 30_500` and caps at 20 ETH equivalent. Must verify `maxBonus` calculation `(20 ether) / (priceWei >> 2)` handles edge cases (priceWei == 0, very small priceWei).

7. **LCG bias in _raritySymbolBatch:** The LCG `s = s * TICKET_LCG_MULT + 1` has full period 2^64 (TICKET_LCG_MULT is a known good multiplier). But `traitFromWord(s)` uses weighted distribution -- bias analysis needed for the modulo/rejection path.

8. **Lootbox boost expiry (C7):** `stampDay + LOOTBOX_BOOST_EXPIRY_DAYS` could overflow uint24 if stampDay is near max. Verify stampDay is bounded.

---

## Validation Architecture

### Payment Flow Validation
- ETH purchase: `msg.value >= totalCost` (or combined with claimable)
- BURNIE purchase: `coin.burnCoin` handles balance check and reverts on insufficient funds
- Claimable path: deducts from `claimableWinnings[buyer]` with 1-wei sentinel preservation
- Lootbox minimum: ETH >= 0.01 ether, BURNIE >= 1000 ether (scaled)
- Ticket minimum: `costWei >= TICKET_MIN_BUYIN_WEI` (0.0025 ether)

### State Machine Guards
- `gameOver` check in all purchase paths (C1, C2, C5)
- `lootboxRngIndex == 0` check in BURNIE lootbox (C5 L1043)
- `rngLockedFlag` check in `_queueTicketsScaled` for far-future tickets
- `CoinPurchaseCutoff` timing guard in `_purchaseCoinFor`

### Invariants to Verify
1. `claimablePool` always decreases by exactly what `claimableWinnings[buyer]` decreased by (no leak)
2. `prizePoolsPacked` updates via helper functions only (no direct writes)
3. Ticket queue writes use correct key space (write slot vs far-future)
4. `processFutureTicketBatch` cannot process the same ticket twice (cursor tracking)
5. `_raritySymbolBatch` array length accounting: `sstore(elem, newLen)` matches actual writes
