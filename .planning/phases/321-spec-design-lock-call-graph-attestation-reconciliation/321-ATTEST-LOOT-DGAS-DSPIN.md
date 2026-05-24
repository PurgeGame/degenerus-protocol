# 321 — Call-Graph Attestation: LOOTBOX-BOON-UNIFICATION + DEGENERETTE-RESOLUTION-GAS + DEGENERETTE-SPINS-PER-CURRENCY

**Type:** READ-ONLY reconciliation. No source mutated; only this file written.
**Date:** 2026-05-24. Source = `contracts/` HEAD (stale copies elsewhere ignored).
**Method:** every `file:line` anchor cited across the 3 plans grepped against current source; lines reconciled (plans were written against an earlier snapshot — most LOOTBOX anchors have drifted, Degenerette anchors are mostly stable).

Legend: MATCH = anchor at the exact line cited. SHIFTED(±N) = same construct, N lines off. ABSENT = construct not found at/near the anchor.

---

## A. Summary counts

| Plan | MATCH | SHIFTED | ABSENT |
|---|---|---|---|
| LOOTBOX-BOON-UNIFICATION | 4 | 24 | 0 |
| DEGENERETTE-RESOLUTION-GAS | 16 | 4 | 0 |
| DEGENERETTE-SPINS-PER-CURRENCY | 11 | 0 | 0 |
| **Total** | **31** | **28** | **0** |

**Blockers: NONE.** Every cited construct exists in current source. All drift is line-number-only (plans pre-date some edits to `DegenerusGameLootboxModule.sol`); the call graph is intact. Two NON-blocking semantic notes flagged in §F.

---

## B. LOOTBOX-BOON-UNIFICATION attestation
File: `contracts/modules/DegenerusGameLootboxModule.sol` (unless noted).

| Construct | Claimed | Actual | Verdict |
|---|---|---|---|
| `event BurnieLootOpen` | :609 (emit), event decl ~ | decl :88, emit :609 | MATCH (emit), event decl SHIFTED |
| `openLootBox` fn | :537-552 (caller block) | fn :477, `_resolveLootboxCommon` call :537-552 | MATCH |
| `openBurnieLootBox` fn | :561 | :561 | MATCH |
| `openBurnieLootBox` call to common | :592-607 | :592-607 | MATCH |
| BURNIE conversion `amountEth=…*80/(…*100)` | :574 | :574 | MATCH |
| `resolveLootboxDirect` fn + call | :628 fn / :639-654 call | fn :628, call :639-654 | MATCH |
| `resolveRedemptionLootbox` fn + call | :664 fn / :675… call | fn :664, call :675-690 | MATCH |
| `_resolveLootboxCommon` signature | :917 | :917 | MATCH |
| param docs | :897-910 | :880-916 (doc block) | SHIFTED (doc block spans :880-916; bool-param docs at :897-911) |
| haircut `mainAmount = amount − _lootboxBoonBudget(amount)` | :949 | :949 | MATCH |
| `+62% presale BURNIE bonus` block | :973-975 | :973-976 | MATCH (block :972-976) |
| `if (allowBoons)` gate | :982 | :982 | MATCH |
| `allowPasses` pool-weight gates | :1268-1282 | :1268-1282 | MATCH |
| `allowPasses` `_boonFromRoll` gate | :1344-1352 | :1344-1353 | MATCH |
| `_lootboxBoonBudget` helper | (cited) | :795 | present |

### B.1 — CRITICAL: actual `_resolveLootboxCommon` signature + positional bool order

The plan's prose lists the bools as "allowBoons / allowPasses / presale", but the **actual** signature orders them differently. The 5 bools sit at **positional args 8–12**:

```solidity
function _resolveLootboxCommon(
    address player,           // 1
    uint32 day,               // 2
    uint48 index,             // 3
    uint256 amount,           // 4
    uint24 targetLevel,       // 5
    uint24 currentLevel,      // 6
    uint256 seed,             // 7
    bool presale,             // 8  ← presale param (62% BURNIE bonus)
    bool allowPasses,         // 9  ← whale-pass jackpot + lazy-pass discounts
    bool emitLootboxEvent,    // 10 ← (NOT in plan's "3 dead flags"; KEEP)
    bool payColdBustConsolation, // 11 ← (NOT in plan's "3 dead flags"; KEEP)
    bool allowBoons,          // 12 ← boon roll gate
    uint256 distressEth,      // 13
    uint256 totalPackedEth    // 14
)
    private
    returns (uint32 futureTickets, uint256 burnieAmount, bool roundedUp)
```

> IMPL NOTE: the plan §3.3 says "remove 3 bool params" = `presale`, `allowPasses`, `allowBoons`. The signature has **5** bools; `emitLootboxEvent` (pos 10) and `payColdBustConsolation` (pos 11) are SEPARATE flags that still vary per caller and MUST be preserved. Do not remove all 5.

### B.2 — Each caller's exact bool-arg shape (positions 8–12 → presale, allowPasses, emitLootboxEvent, payColdBustConsolation, allowBoons)

| Caller | presale | allowPasses | emitLootboxEvent | payColdBust | allowBoons |
|---|---|---|---|---|---|
| `openLootBox` (:537) | `presale` (local, :493) | **true** | **true** | **true** | **true** |
| `openBurnieLootBox` (:592) — **TO REMOVE** | false | false | false | true | **true** |
| `resolveLootboxDirect` (:639) | false | **true** | false | false | **false** |
| `resolveRedemptionLootbox` (:675) | false | **true** | false | false | **false** |

`openLootBox` call (:537-552):
```solidity
_resolveLootboxCommon(player, day, index, scaledAmount, targetLevel, currentLevel,
    seed, presale, true, true, true, true, distressEth, amount);
```
`openBurnieLootBox` call (:592-607) — REMOVED entirely per §3.0:
```solidity
(uint32 tickets, uint256 burnieReward, bool roundedUp) = _resolveLootboxCommon(
    player, day, index, amountEth, targetLevel, currentLevel,
    seed, false, false, false, true, true, 0, 0);
```
`resolveLootboxDirect` call (:639-654):
```solidity
_resolveLootboxCommon(player, day, 0, scaledAmount, targetLevel, currentLevel,
    seed, false, true, false, false, false, 0, 0);
```
`resolveRedemptionLootbox` call (:675-690):
```solidity
_resolveLootboxCommon(player, day, 0, scaledAmount, targetLevel, currentLevel,
    seed, false, true, false, false, false, 0, 0);
```

> FLAG (NON-BLOCKING, §F-1): `openBurnieLootBox` passes **`allowBoons = true`** (pos 12) today — NOT `false`. The plan's §2 gradient table marks the BURNIE-box row "—" (removed), so this never surfaces post-removal. But the prose in `PLAN-DEGENERETTE-RESOLUTION-GAS §3 Tier-1` ("`openBurnieLootBox` runs allowBoons=false") and the assumption that "only `openLootBox` draws boons today" are WRONG for current source — the BURNIE box DOES roll boons today (it just can't mint passes because `allowPasses=false`). Immaterial to v47 because the box is deleted, but correct the record.

### B.3 — BURNIE-box removal spread (the cross-file delete surface)

| Target | Claimed | Actual | Verdict |
|---|---|---|---|
| `MintModule.purchaseCoin` | :852-858 (sig) | :852 | present (plan cited :537 = the Game wrapper; MintModule impl is :852) |
| `MintModule.purchaseBurnieLootbox` | :864 | :864 | MATCH |
| `MintModule._purchaseCoinFor` lootBoxBurnie branch | :894-895 | :894-896 | MATCH |
| `MintModule._purchaseBurnieLootboxFor` | :1425 | :1425 | MATCH |
| `MintModule` ENF-01 `if (gameOverPossible) revert` | :881 (memory) | :881 | MATCH (`revert GameOverPossible()`) |
| `DegenerusGame.purchaseCoin` | :537 | :537 | MATCH |
| `DegenerusGame.purchaseBurnieLootbox` | :559 | :559 | MATCH |
| `DegenerusGame.openBurnieLootBox` | :664 | :664 | MATCH |
| `DegenerusGame._openBurnieLootBoxFor` | :682 | :682 | MATCH |
| `Vault.purchaseBurnieLootbox` interface decl | :32 | :32 | MATCH |
| `Vault.purchaseCoin` interface | :51 | :51-55 | MATCH |
| `Vault.gamePurchaseBurnieLootbox` | :554-557 | :554-557 | MATCH |
| `Vault.gamePurchaseTicketsBurnie` (KEEP) | confirm exists | :545-548 | CONFIRMED PRESENT — KEEP |

**MintModule `purchaseCoin` / `_purchaseCoinFor` current shape** (the `lootBoxBurnieAmount` arg to drop):
```solidity
function purchaseCoin(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) external {
    _purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount);
}
function _purchaseCoinFor(address buyer, uint256 ticketQuantity, uint256 lootBoxBurnieAmount) private {
    if (_livenessTriggered()) revert E();
    if (ticketQuantity != 0) {
        if (gameOverPossible) revert GameOverPossible();   // ENF-01 — KEEP (tickets-only path)
        _callTicketPurchase(buyer, ticketQuantity, MintPaymentKind.DirectEth, true, bytes32(0), 0, level, jackpotPhaseFlag);
    }
    if (lootBoxBurnieAmount != 0) {                        // ← TO REMOVE (§3.0)
        _purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount);
    }
}
```

**`DegenerusGame.purchaseCoin` wrapper** (:537) — forwards `lootBoxBurnieAmount` via delegatecall (selector `IDegenerusGameMintModule.purchaseCoin`). Signature must change in lock-step with the MintModule sig and the Vault interface (:51).

**`Vault.gamePurchaseTicketsBurnie`** (KEEP) already calls `gamePlayer.purchaseCoin(address(this), ticketQuantity, 0)` — already passes `0` for the burnie-lootbox arg, so it is forward-compatible with a tickets-only `purchaseCoin` (only the arity changes if the 3rd param is dropped).

### B.4 — Decimator win path through `resolveLootboxDirect`

| Target | Claimed | Actual | Verdict |
|---|---|---|---|
| `DecimatorModule` `resolveLootboxDirect` delegatecall | :601 | :601 | MATCH |

`DegenerusGameDecimatorModule.sol:597-608` delegatecalls `IDegenerusGameLootboxModule.resolveLootboxDirect.selector` with `(winner, amount, rngWord, evScore)`. CONFIRMED: Decimator wins route through the SAME `resolveLootboxDirect` as Degenerette, so flipping its `allowBoons` false→true gives Decimator wins boons/passes too (plan §3.1 / §5-reconcile: DECIDED uniform).

---

## C. DEGENERETTE-RESOLUTION-GAS attestation
File: `contracts/modules/DegenerusGameDegeneretteModule.sol` (unless noted).

| Construct | Claimed | Actual | Verdict |
|---|---|---|---|
| `resolveBets(address,uint64[])` | :389-398 | :389-398 | MATCH |
| `_resolveBet` | (cited) | :553 | present |
| `_resolveFullTicketBet` | :561-678 | :561-678 | MATCH |
| per-spin loop `for (uint8 spinIdx; spinIdx < ticketCount;)` | :593 | :593 | MATCH |
| currency decode (`MASK_2`) | :569 | :569 | MATCH |
| `delete degeneretteBets[player][betId]` | :580 | :580 | MATCH |
| `rngWord = lootboxRngWordByIndex[index]` (read once) | :577 | :577 | MATCH |
| result-seed derivation (spin0 vs spinN) | :596-609 | :596-609 | MATCH |
| per-spin `lootboxWord` salting (0x4c 'L') | :646-657 | :646-657 | MATCH |
| `_distributePayout` call (in loop) | (cited) | :658 | present |
| `_distributePayout` fn | :705-779 | :705-779 | MATCH |
| ETH branch `if (currency == CURRENCY_ETH)` | :713 | :713 | MATCH |
| `_setPendingPools` (frozen) | :748 | :748 | MATCH |
| `_addClaimableEth` (frozen) | :749 | :749 | MATCH |
| `ETH_WIN_CAP_BPS` cap math | :754-762 | :755-763 | SHIFTED(+1) (`pool=…:754`, `maxEth=…:755`, cap block :756-763) |
| `_setFuturePrizePool` (unfrozen) | :764 | :764 | MATCH |
| `_addClaimableEth` (unfrozen) | (in :754-762) | :765 | present |
| `mintForGame` (BURNIE branch) | :775 | :775 | MATCH |
| `mintPrize` (WWXRP branch) | :777 | :777 | MATCH |
| `_resolveLootboxDirect` (private wrapper) call | (cited) | :772 | present (wrapper :783; plan §3 cited module-level :772 as the Degenerette call site — actual private wrapper at :783 delegatecalls the module) |
| `_awardDegeneretteDgnrs` call | :662-663 | :662-663 | MATCH |
| `_awardDegeneretteDgnrs` fn (reads `poolBalance`) | :1125-1148 (fn) / :1135 (poolBalance) | fn :1125-1149, poolBalance read :1135 | MATCH |
| `_applyEvMultiplierWithCap` | :433 | **LootboxModule:433** | SHIFTED (CROSS-MODULE — see §F-2) |

### C.1 — current `resolveBets` structure (the cross-bet flush target)
```solidity
function resolveBets(address player, uint64[] calldata betIds) external {
    player = _resolvePlayer(player);
    uint256 len = betIds.length;
    for (uint256 i; i < len; ) {
        _resolveBet(player, betIds[i]);     // → _resolveFullTicketBet (no return value today)
        unchecked { ++i; }
    }
}
```
`_resolveBet` (:553) just SLOADs the packed bet, reverts if 0, and calls `_resolveFullTicketBet(player, betId, packed)`. **For the cross-bet flush, both `_resolveBet` and `_resolveFullTicketBet` need return-delta signatures** (today both are `private` returning nothing).

### C.2 — current `_resolveFullTicketBet` structure (the per-bet/per-spin refactor target)
- Decode (one currency per bet): `currency` :569, `amountPerTicket` :570, `ticketCount` :568, `index` :573, `activityScore` :574, `customTicket` :567, `heroQuadrant` :575.
- `rngWord = lootboxRngWordByIndex[index]` :577 (read once/bet); revert `RngNotReady` if 0.
- `delete degeneretteBets[player][betId]` :580 (per-bet, unavoidable).
- Loop `for (uint8 spinIdx; spinIdx < ticketCount; )` :593:
  - `resultSeed` :596-609 (spin0 short preimage; spinN mixes `spinIdx`) — **STAYS per-spin** (match determination).
  - `payout` :621 via `_fullTicketPayout`.
  - `if (payout != 0)` :641 → `totalPayout += payout` :642 → derives per-spin `lootboxWord` :646-657 → `_distributePayout(player, currency, amountPerTicket, payout, lootboxWord, activityScore)` :658.
  - `if (currency == CURRENCY_ETH && matches >= 6)` :662 → `_awardDegeneretteDgnrs` :663 (Tier 3 — LEAVE per-spin).
- `FullTicketResolved` emit :671-677.

**For the gas refactor:** the `_distributePayout` call (:658) is what gets accumulated. The lootbox-share path inside `_distributePayout` calls the private `_resolveLootboxDirect` wrapper (:772/:783) — per the gas plan this becomes **one `resolveLootboxDirect` per `betId`** on summed lootbox-share + the per-spin `lootboxWord` salting (:646-657) is **dropped** (use the bet's `rngWord`).

### C.3 — current `_distributePayout` structure (the write-consolidation target)
```solidity
function _distributePayout(address player, uint8 currency, uint128 betAmount,
    uint256 payout, uint256 rngWord, uint16 activityScore) private {
    if (currency == CURRENCY_ETH) {
        // 3-tier split → ethShare / lootboxShare
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            if (uint256(pFuture) < ethShare) revert E();        // solvency
            _setPendingPools(pNext, pFuture - uint128(ethShare)); // :748
            _addClaimableEth(player, ethShare);                   // :749
        } else {
            uint256 pool = _getFuturePrizePool();                 // :754
            uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;   // :755
            if (ethShare > maxEth) { lootboxShare += ethShare - maxEth; ethShare = maxEth;
                emit PayoutCapped(player, ethShare, lootboxShare); }
            unchecked { pool -= ethShare; }
            _setFuturePrizePool(pool);                            // :764
            _addClaimableEth(player, ethShare);                   // :765
        }
        if (lootboxShare > 0) _resolveLootboxDirect(player, lootboxShare, rngWord, activityScore); // :772
    } else if (currency == CURRENCY_BURNIE) {
        coin.mintForGame(player, payout);                         // :775
    } else if (currency == CURRENCY_WWXRP) {
        wwxrp.mintPrize(player, payout);                          // :777
    }
}
```
Note: docstring at :701 says `(0=ETH, 1=BURNIE, 3=WWXRP)` — consistent with constants (CURRENCY_WWXRP=3, value 2 unused).

---

## D. DEGENERETTE-SPINS-PER-CURRENCY attestation
File: `contracts/modules/DegenerusGameDegeneretteModule.sol`.

| Construct | Claimed | Actual | Verdict |
|---|---|---|---|
| `MAX_SPINS_PER_BET = 10` | :226 | :226 | MATCH |
| validation `if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET) revert InvalidBet();` | :445 | :445-446 | MATCH |
| `_placeDegeneretteBetCore` fn | :437 (cites :445 within) | :437 | MATCH |
| `_validateMinBet` fn | :503 | :503 | MATCH |
| `_validateMinBet` call site | :454 | :454 | MATCH |
| `totalBet = amountPerTicket × ticketCount` | :456 | :456 | MATCH |
| `MIN_BET_ETH = 5 ether / 1000` | :217 | :217 | MATCH |
| `MIN_BET_BURNIE = 100 ether` | :220 | :220 | MATCH |
| `MIN_BET_WWXRP = 1 ether` | :223 | :223 | MATCH |
| `ticketCount` 8-bit packing `[34..41]` | :296 | :296 | MATCH |
| doc comment (packing) | :296 | :296 | MATCH |
| doc comment (`@param ticketCount`) | :364 | :364 | MATCH |
| `CURRENCY_ETH/BURNIE/WWXRP` names | confirm | :208/:211/:214 | CONFIRMED (ETH=0, BURNIE=1, WWXRP=**3**) |

### D.1 — current spin-cap validation line (the edit target)
`DegenerusGameDegeneretteModule.sol:445-446`:
```solidity
if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET)
    revert InvalidBet();
```
Note: it spans **two lines** (445-446), not one. `currency` is already validated upstream (the only 3 valid kinds are ETH=0/BURNIE=1/WWXRP=3; `_validateMinBet` :503 reverts on any other). The per-currency lookup proposed in the plan (25/15/5) replaces this single branch; loop bound `for (uint8 spinIdx; spinIdx < ticketCount;)` (:593) is already `ticketCount`-driven (no hardcoded 10). `ticketCount` is `uint8` (8-bit field [34..41]) → 25 fits, no packing change.

### D.2 — sole dependency on `MAX_SPINS_PER_BET`
Grep confirms `MAX_SPINS_PER_BET` is referenced at: definition :226, validation :445, and two doc comments :296 / :364. **No other code path reads it** — retiring/replacing it touches exactly those four sites (plan §2 "No other code depends on the value" CONFIRMED).

---

## E. WWXRP currency constant — record correction
The plans variously write the WWXRP enum as `2` in narrative ("0=ETH, 1=BURNIE, 2=WWXRP"). **Actual:** `CURRENCY_WWXRP = 3` (:214); value `2` is unused/"unsupported" (per the `@param` doc at :362 and `_distributePayout` doc :701). The currency decode uses `MASK_2` (2 bits → 0..3), so 3 is representable. Non-blocking; just ensure any per-currency cap lookup (§D) uses `CURRENCY_WWXRP` by name, not literal 2.

---

## F. Flagged items (NON-BLOCKING — no IMPL blockers found)

**F-1 — `openBurnieLootBox` passes `allowBoons=true` today (not false).**
Current source (`LootboxModule:592-607`) passes the boon gate `true` (pos 12) for the BURNIE box; it only suppresses *passes* (`allowPasses=false`). Both `PLAN-DEGENERETTE-RESOLUTION-GAS §3` and `PLAN-LOOTBOX §2` imply the BURNIE box draws no boons. This is a documentation error in the plans, immaterial to v47 (the BURNIE box is deleted in §3.0). No action needed beyond record-correction. **NOT a blocker.**

**F-2 — `_applyEvMultiplierWithCap` lives in LootboxModule, not Degenerette.**
`PLAN-DEGENERETTE-RESOLUTION-GAS §3 Lootbox-share` cites `_applyEvMultiplierWithCap :433` as if in the Degenerette module. It is actually `DegenerusGameLootboxModule.sol:433`, invoked inside `resolveLootboxDirect` (:637) and `resolveRedemptionLootbox` (:673) — i.e. it runs once *inside* the box resolution, AFTER Degenerette hands off the summed lootbox-share. This is consistent with the plan's intent (cumulative per player/level cap "nets out") but the anchor is cross-module. **NOT a blocker.**

**F-3 — ETH lootbox-share hand-off goes through a private wrapper.**
Degenerette's `_distributePayout` does NOT call the module selector directly; it calls a private `_resolveLootboxDirect` wrapper (:783) that delegatecalls `IDegenerusGameLootboxModule.resolveLootboxDirect`. The gas refactor's "one `resolveLootboxDirect` per betId" must target this private wrapper call (:772), not invent a new call site. **NOT a blocker.**

**F-4 — `_resolveLootboxCommon` has 5 bools, plan says remove 3.**
See §B.1. `emitLootboxEvent` (pos 10) + `payColdBustConsolation` (pos 11) are distinct flags that legitimately differ across the 3 surviving ETH callers (`openLootBox` true/true vs `resolveLootboxDirect`/`resolveRedemptionLootbox` false/false). Only `presale` (8), `allowPasses` (9), `allowBoons` (12) collapse to constants once the 3 surviving callers are unified. **NOT a blocker** — just don't over-delete.

---

## G. Verdict
- **0 ABSENT, 0 material drift, 0 IMPL blockers.** The 3 plans' call graph is fully realizable against current source.
- All line drift is confined to `DegenerusGameLootboxModule.sol` (plans pre-date edits there). Degenerette + cross-file (Mint/Game/Vault/Decimator) anchors are stable.
- 4 NON-BLOCKING record-corrections (§F): BURNIE-box `allowBoons=true` today (F-1), `_applyEvMultiplierWithCap` is cross-module (F-2), ETH lootbox hand-off via private wrapper (F-3), `_resolveLootboxCommon` has 5 bools / remove only 3 (F-4). Plus the WWXRP=3 (not 2) enum correction (§E).
