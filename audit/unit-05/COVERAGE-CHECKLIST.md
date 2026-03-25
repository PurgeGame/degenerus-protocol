# Unit 5: Mint + Purchase Flow -- Coverage Checklist

**Agent:** Taskmaster (Coverage Enforcer)
**Contracts:**
- `contracts/modules/DegenerusGameMintModule.sol` (~1,167 lines)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` (62 lines)
**Date:** 2026-03-25

---

## Methodology

- **D-01:** Categories B/C/D only (no Category A -- these are modules, not router)
- **D-02:** Category B functions get full Mad Genius treatment (call tree, storage map, cache check, 10-angle attack)
- **D-03:** Category C functions traced via parent call trees; standalone for [MULTI-PARENT]
- **D-06:** Fresh adversarial analysis (no trusting prior findings)
- **D-08/D-09:** Cross-module calls traced for state coherence; subordinate writes to cached storage IS a finding
- **D-10:** ULTIMATE-AUDIT-DESIGN.md report format

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 5 | Full Mad Genius (per D-02) |
| C: Internal Helpers | 11 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 4 | Minimal; RNG/entropy functions get extra scrutiny |
| **TOTAL** | **20** | |

---

## Category B: External State-Changing Functions

| # | Function | Lines | Access Control | Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|---------------|----------------|-----------|-----------|-----------|-----------|-------------|-------------|
| B1 | `recordMintData(address,uint24,uint32)` | 175-284 | external payable (delegatecall from Game) | `mintPacked_[player]` | None | Tier 2 | MINT-DATA | pending | pending | pending | pending |
| B2 | `processFutureTicketBatch(uint24)` | 295-434 | external (delegatecall from Game) | `ticketCursor`, `ticketLevel`, `ticketsOwedPacked[rk][player]`, `ticketQueue[rk]`, `traitBurnTicket[lvl][trait]` (via assembly) | None | Tier 1 | TICKET-DRAIN | pending | pending | pending | pending |
| B3 | `purchase(address,uint256,uint256,bytes32,MintPaymentKind)` | 560-574 | external payable (delegatecall from Game) | Via C1: see _purchaseFor storage writes | Via C1: affiliate.payAffiliate, coin.creditFlip, coin.notifyQuestMint, coin.notifyQuestLootBox, IDegenerusGame.recordMint, IDegenerusGame.consumePurchaseBoost, IDegenerusGame.playerActivityScore, Vault.call, sDGNRS.transferFromPool | Tier 1 | ETH-PURCHASE | pending | pending | pending | pending |
| B4 | `purchaseCoin(address,uint256,uint256)` | 581-591 | external (delegatecall from Game) | Via C2: see _purchaseCoinFor storage writes | Via C2/C3: coin.burnCoin, coin.notifyQuestMint, affiliate.payAffiliate, IDegenerusGame.recordMint | Tier 2 | COIN-PURCHASE | pending | pending | pending | pending |
| B5 | `purchaseBurnieLootbox(address,uint256)` | 595-598 | external (delegatecall from Game) | Via C5: lootboxBurnie, lootboxDay, lootboxRngPendingBurnie, lootboxRngPendingEth | coin.burnCoin, coin.notifyQuestMint | Tier 3 | BURNIE-LOOT | pending | pending | pending | pending |

---

## Category C: Internal Helpers (State-Changing)

| # | Function | Lines | Contract | Called By | Key Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|----------|-----------|-------------------|-------|-----------|-----------|-------------|-------------|
| C1 | `_purchaseFor()` | 628-829 | MintModule | B3 | `claimableWinnings[buyer]`, `claimablePool`, `lootboxEth[idx][buyer]`, `lootboxDay[idx][buyer]`, `lootboxBaseLevelPacked[idx][buyer]`, `lootboxEvScorePacked[idx][buyer]`, `lootboxEthBase[idx][buyer]`, `lootboxDistressEth[idx][buyer]`, `prizePoolsPacked`/`prizePoolPendingPacked`, `lootboxPresaleMintEth`, `lootboxRngPendingEth`, `boonPacked[player].slot0`, `earlybirdDgnrsPoolStart`, `earlybirdEthIn` | | pending | pending | pending | pending |
| C2 | `_purchaseCoinFor()` | 600-626 | MintModule | B4 | (delegates to C3, C5) | | pending | pending | pending | pending |
| C3 | `_callTicketPurchase()` | 831-1024 | MintModule | C1, C2 | `centuryBonusLevel`, `centuryBonusUsed[buyer]`, `ticketQueue[wk]`, `ticketsOwedPacked[wk][buyer]` (via C10) | [MULTI-PARENT] | pending | pending | pending | pending |
| C4 | `_coinReceive()` | 1026-1031 | MintModule | C3 (payInCoin path) | None (external: `coin.burnCoin`) | | pending | pending | pending | pending |
| C5 | `_purchaseBurnieLootboxFor()` | 1039-1071 | MintModule | B5, C2 | `lootboxBurnie[idx][buyer]`, `lootboxDay[idx][buyer]`, `lootboxRngPendingBurnie`, `lootboxRngPendingEth` (via C6) | [MULTI-PARENT] | pending | pending | pending | pending |
| C6 | `_maybeRequestLootboxRng()` | 1073-1075 | MintModule | C1, C5 | `lootboxRngPendingEth` | [MULTI-PARENT] | pending | pending | pending | pending |
| C7 | `_applyLootboxBoostOnPurchase()` | 1085-1112 | MintModule | C1 | `boonPacked[player].slot0` | | pending | pending | pending | pending |
| C8 | `_raritySymbolBatch()` | 443-537 | MintModule | B2 | `traitBurnTicket[lvl][traitId]` (via inline Yul assembly) | [ASSEMBLY] | pending | pending | pending | pending |
| C9 | `_recordMintStreakForLevel()` | 17-46 | MintStreakUtils | (called from GameStorage helpers, part of recordMint chain) | `mintPacked_[player]` | [INHERITED] | pending | pending | pending | pending |
| C10 | `_queueTicketsScaled()` | 556-594 | GameStorage | C3 | `ticketQueue[wk]`, `ticketsOwedPacked[wk][buyer]` | [INHERITED] | pending | pending | pending | pending |
| C11 | `_awardEarlybirdDgnrs()` | 914-974 | GameStorage | C1 | `earlybirdDgnrsPoolStart`, `earlybirdEthIn` (external: `sDGNRS.transferFromPool`, `sDGNRS.transferBetweenPools`) | [INHERITED] | pending | pending | pending | pending |

---

## Category D: View/Pure Functions

| # | Function | Lines | Contract | Reads/Computes | Security Note | Reviewed? |
|---|----------|-------|----------|---------------|---------------|-----------|
| D1 | `_rollRemainder()` | 540-547 | MintModule | `EntropyLib.entropyStep(entropy ^ rollSalt) % TICKET_SCALE` | Modulo bias: TICKET_SCALE=100 divides 2^256 evenly (no bias). EntropyLib.entropyStep is keccak256-based. | pending |
| D2 | `_ethToBurnieValue()` | 1034-1037 | MintModule | `amountWei * PRICE_COIN_UNIT / priceWei` | Division by zero: guarded by `priceWei == 0 -> return 0`. Overflow: amountWei * 1000e18 fits in uint256 for any realistic ETH amount. | pending |
| D3 | `_calculateBoost()` | 1078-1083 | MintModule | `cappedAmount * bonusBps / 10_000` in unchecked block | Safe: cappedAmount <= 10 ether (LOOTBOX_BOOST_MAX_VALUE), bonusBps <= 2500. Product fits in uint256. | pending |
| D4 | `_mintStreakEffective()` | 49-61 | MintStreakUtils | Reads `mintPacked_[player]`, returns streak or 0 | View function. Returns 0 if `currentMintLevel > lastCompleted + 1` (reset on missed level). | pending |

---

## Ticket Queue Write Paths

Every path from a Category B entry point to `_queueTicketsScaled`:

```
B3: purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)
  -> C1: _purchaseFor(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)
    -> C3: _callTicketPurchase(buyer, buyer, quantity, payKind, false, affiliateCode, remainingEth)
      -> C10: _queueTicketsScaled(buyer, ticketLevel, adjustedQty32)
         Storage: ticketQueue[wk].push(buyer), ticketsOwedPacked[wk][buyer] = newPacked

B4: purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount)
  -> C2: _purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount)
    -> C3: _callTicketPurchase(buyer, payer, ticketQuantity, DirectEth, true, bytes32(0), 0)
      -> C10: _queueTicketsScaled(buyer, ticketLevel, adjustedQty32)
         Storage: ticketQueue[wk].push(buyer), ticketsOwedPacked[wk][buyer] = newPacked
```

### Ticket Level Routing (C3 lines 842-851)

```solidity
uint24 targetLevel = jackpotPhaseFlag ? level : level + 1;
// Last jackpot day fix: route to level+1
if (jackpotPhaseFlag && rngLockedFlag) {
    uint8 cnt = jackpotCounter;
    uint8 comp = compressedJackpotFlag;
    uint8 step = comp == 2 ? JACKPOT_LEVEL_CAP
        : (comp == 1 && cnt > 0 && cnt < JACKPOT_LEVEL_CAP - 1) ? 2 : 1;
    if (cnt + step >= JACKPOT_LEVEL_CAP) targetLevel = level + 1;
}
```

**Critical question for Mad Genius:** Can tickets be routed to a level that never gets processed? Specifically: if `jackpotPhaseFlag == true` and `rngLockedFlag == false`, tickets go to `level` (current). If this level's jackpot phase completes before tickets are drained, are they stranded?

---

## Cross-Module External Calls

| # | Call | From Functions | Target Contract | State Impact | Notes |
|---|------|---------------|----------------|-------------|-------|
| X1 | `coin.creditFlip(buyer, amount)` | C1, C3 | BurnieCoin | BURNIE minting | Affiliate kickback + bonus credit |
| X2 | `coin.burnCoin(payer, amount)` | C4, C5 | BurnieCoin | BURNIE burning | BURNIE ticket/lootbox payment |
| X3 | `coin.notifyQuestMint(buyer, qty, isEth)` | C1, C2, C3, C5 | BurnieCoin | Quest progress tracking | Multiple call sites |
| X4 | `coin.notifyQuestLootBox(buyer, amount)` | C1 | BurnieCoin | Lootbox quest tracking | |
| X5 | `affiliate.payAffiliate(...)` | C1, C3 | DegenerusAffiliate | BURNIE affiliate payment | Returns kickback amount |
| X6 | `IDegenerusGame(address(this)).recordMint{value}(...)` | C3 | DegenerusGame (self-call) | Mint recording + ETH forwarding | **SELF-CALL RE-ENTRY** |
| X7 | `IDegenerusGame(address(this)).consumePurchaseBoost(payer)` | C3 | DegenerusGame (self-call) | Boost consumption | Self-call |
| X8 | `IDegenerusGame(address(this)).playerActivityScore(buyer)` | C1, C3 | DegenerusGame (self-call) | View: activity score | Self-call (view only) |
| X9 | `payable(VAULT).call{value}("")` | C1 | DegenerusVault | ETH transfer (presale split) | Raw ETH transfer |
| X10 | `sDGNRS.transferFromPool(...)` | C11 | StakedDegenerusStonk | DGNRS earlybird reward | Inherited helper |
| X11 | `sDGNRS.transferBetweenPools(...)` | C11 | StakedDegenerusStonk | Pool rebalance (earlybird -> lootbox) | Inherited helper |
| X12 | `sDGNRS.poolBalance(...)` | C11 | StakedDegenerusStonk | View: pool balance | Inherited helper (view) |

---

## Self-Call Re-Entry Map

### recordMint Pattern (C3 line 918)

```
MintModule._callTicketPurchase() [executing in Game's context via delegatecall]
  -> IDegenerusGame(address(this)).recordMint{value: value}(payer, targetLevel, costWei, mintUnits, payKind)
     [This is a regular CALL (not delegatecall) to DegenerusGame]
     -> DegenerusGame.recordMint()
       -> delegatecall MintModule.recordMintData(payer, targetLevel, mintUnits)
          [Now executing recordMintData in Game's storage context]
          -> writes mintPacked_[payer]
       -> Game handles ETH routing (splits between pools, affiliate, etc.)
```

**Critical for Mad Genius:** The self-call forwards `value` ETH. Between the time `_callTicketPurchase` reads `price` (line 856) and the self-call returns, `recordMintData` writes to `mintPacked_[payer]`. Since `_callTicketPurchase` does NOT cache `mintPacked_[payer]`, this is safe. But verify that `recordMint` in DegenerusGame does not write to `price`, `level`, `claimableWinnings`, or any other value cached by the caller chain.

### consumePurchaseBoost Pattern (C3 line 863)

```
MintModule._callTicketPurchase() [delegatecall context]
  -> IDegenerusGame(address(this)).consumePurchaseBoost(payer)
     [Regular CALL to DegenerusGame]
     -> Reads/writes boonPacked[payer].slot0 (purchase boost fields)
     -> Returns boostBps
```

**Note:** This self-call happens BEFORE the main ticket logic. The returned `boostBps` is used to adjust `adjustedQuantity`. Verify the boost cannot be consumed twice in the same transaction.

---

## Risk Tier Summary

| Tier | Functions | Rationale |
|------|-----------|-----------|
| Tier 1 | B2 (processFutureTicketBatch), B3 (purchase) | Deep call trees, inline assembly, complex payment routing, self-call re-entry, lootbox pool splits |
| Tier 2 | B1 (recordMintData), B4 (purchaseCoin) | Bit-packing logic, BURNIE cutoff timing |
| Tier 3 | B5 (purchaseBurnieLootbox) | Thin wrapper with delegation |
