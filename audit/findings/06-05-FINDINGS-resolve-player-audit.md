# AUTH-05: _resolvePlayer Call Site Value-Flow Audit

**Date:** 2026-03-01
**Auditor:** Automated security audit
**Scope:** All 3 independent `_resolvePlayer` implementations and every call site that invokes them
**Requirement:** AUTH-05 -- Prove that `_resolvePlayer` correctly routes value flows to the resolved player address across all call sites

---

## 1. Implementation Comparison

### 1.1 DegenerusGame._resolvePlayer (lines 497-503)

```solidity
function _resolvePlayer(address player) private view returns (address resolved) {
    if (player == address(0)) return msg.sender;
    if (player != msg.sender) _requireApproved(player);
    return player;
}

function _requireApproved(address player) private view {
    if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
        revert NotApproved();
    }
}
```

- **Storage access:** Reads `operatorApprovals[player][msg.sender]` directly from Game storage.
- **Error:** Reverts with `NotApproved()`.

### 1.2 BurnieCoinflip._resolvePlayer (lines 1187-1195)

```solidity
function _resolvePlayer(address player) private view returns (address resolved) {
    if (player == address(0)) return msg.sender;
    if (player != msg.sender) {
        if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
            revert OnlyBurnieCoin(); // Reusing error
        }
    }
    return player;
}
```

- **Storage access:** Cross-contract call to `degenerusGame.isOperatorApproved(player, msg.sender)`, which returns `operatorApprovals[owner][operator]` from Game storage.
- **Error:** Reverts with `OnlyBurnieCoin()` (reused error -- cosmetic difference only).
- **Functional difference:** The error type differs from Game's `NotApproved()`. This is a cosmetic difference with no security impact -- both revert the transaction when the operator is not approved.

### 1.3 DegeneretteModule._resolvePlayer (lines 160-166)

```solidity
function _resolvePlayer(address player) private view returns (address resolved) {
    if (player == address(0)) return msg.sender;
    if (player != msg.sender) {
        _requireApproved(player);
    }
    return player;
}

function _requireApproved(address player) private view {
    if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
        revert NotApproved();
    }
}
```

- **Storage access:** Reads `operatorApprovals[player][msg.sender]` directly. Since this module runs via delegatecall from DegenerusGame, it reads Game's storage, identical to Game's own implementation.
- **Error:** Reverts with `NotApproved()` (identical to Game).

### 1.4 Equivalence Verdict

| Aspect | DegenerusGame | BurnieCoinflip | DegeneretteModule |
|--------|---------------|----------------|-------------------|
| address(0) handling | returns msg.sender | returns msg.sender | returns msg.sender |
| player == msg.sender | returns player | returns player | returns player |
| player != msg.sender | checks operatorApprovals directly | checks via isOperatorApproved() cross-call | checks operatorApprovals directly (delegatecall) |
| Storage source | Game storage (direct) | Game storage (via external call) | Game storage (via delegatecall) |
| Revert error | NotApproved() | OnlyBurnieCoin() | NotApproved() |

**Verdict: Functionally equivalent.** All three implementations read the same `operatorApprovals` mapping from DegenerusGame storage. The only difference is the revert error in BurnieCoinflip (`OnlyBurnieCoin` vs `NotApproved`), which is cosmetic -- both prevent unauthorized operator actions. The edge case paths (address(0), player == msg.sender, unapproved operator) are handled identically across all three.

---

## 2. DegenerusGame Call Sites (22 call sites)

### 2.1 purchase() -- line 547

```
Call Site: DegenerusGame.purchase (line 547)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Line 548-554: buyer passed to _purchaseFor(buyer, ...) -> delegatecall MintModule.purchase(buyer, ...)
    - MintModule handles ticket attribution and ETH accounting using the buyer address
    - msg.value ETH is consumed by the Game contract; ticket ownership attributed to buyer
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.2 purchaseCoin() -- line 590

```
Call Site: DegenerusGame.purchaseCoin (line 590)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Lines 591-601: buyer passed to MintModule.purchaseCoin(buyer, ...) via delegatecall
    - BURNIE is burned from buyer; tickets attributed to buyer
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.3 purchaseBurnieLootbox() -- line 611

```
Call Site: DegenerusGame.purchaseBurnieLootbox (line 611)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Lines 612-621: buyer passed to MintModule.purchaseBurnieLootbox(buyer, ...) via delegatecall
    - BURNIE lootbox attributed to buyer
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.4 purchaseWhaleBundle() -- line 644

```
Call Site: DegenerusGame.purchaseWhaleBundle (line 644)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Line 645: buyer passed to _purchaseWhaleBundleFor(buyer, quantity)
    - Lines 649-658: delegatecall WhaleModule.purchaseWhaleBundle(buyer, quantity)
    - Bundle rewards (tickets, streak, lootbox) attributed to buyer
    - msg.value ETH consumed by contract; value attributed to buyer
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.5 purchaseLazyPass() -- line 666

```
Call Site: DegenerusGame.purchaseLazyPass (line 666)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Line 667: buyer passed to _purchaseLazyPassFor(buyer)
    - Lines 671-679: delegatecall WhaleModule.purchaseLazyPass(buyer)
    - Lazy pass ownership attributed to buyer
    - msg.value ETH consumed by contract; value attributed to buyer
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.6 purchaseDeityPass() -- line 689

```
Call Site: DegenerusGame.purchaseDeityPass (line 689)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Line 690: buyer passed to _purchaseDeityPassFor(buyer, symbolId)
    - Deity pass minted to buyer; refund tracking stored against buyer
    - msg.value ETH consumed by contract; value attributed to buyer
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.7 refundDeityPass() -- line 700

> **POST-AUDIT UPDATE:** The `refundDeityPass()` function was removed entirely from the codebase. This call site no longer exists. The analysis below is retained for historical reference only.

```
Call Site: DegenerusGame.refundDeityPass (line 700)
  Resolution: buyer = _resolvePlayer(buyer)
  Value Operations After Resolution:
    - Line 705: refundAmount = deityPassRefundable[buyer]
    - Lines 708-711: state cleared for buyer (deityPassRefundable, deityPassPaidTotal, deityPassPurchasedCount)
    - Line 714: symbolId read from deityPassSymbol[buyer]
    - Line 730: emit DeityPassRefunded(buyer, ...)
    - Line 731: _payoutWithStethFallback(buyer, refundAmount) -- ETH/stETH sent to buyer
  Verdict: PASS -- all value reads and transfers target the resolved buyer address
```

### 2.8 openLootBox() -- line 768

```
Call Site: DegenerusGame.openLootBox (line 768)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 769: player passed to _openLootBoxFor(player, lootboxIndex)
    - Lines 780-790: delegatecall LootboxModule.openLootBox(player, lootboxIndex)
    - Lootbox rewards (ETH credits, tickets, tokens) attributed to player
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.9 openBurnieLootBox() -- line 776

```
Call Site: DegenerusGame.openBurnieLootBox (line 776)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 777: player passed to _openBurnieLootBoxFor(player, lootboxIndex)
    - Lines 793-806: delegatecall LootboxModule.openBurnieLootBox(player, lootboxIndex)
    - BURNIE lootbox rewards attributed to player
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.10 placeFullTicketBets() -- line 831

```
Call Site: DegenerusGame.placeFullTicketBets (line 831)
  Resolution: _resolvePlayer(player) passed inline as first argument to delegatecall
  Value Operations After Resolution:
    - Lines 824-839: resolved player passed to DegeneretteModule.placeFullTicketBets(resolved, ...)
    - Bets recorded against the resolved player address
    - ETH/token collection from the resolved player
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.11 placeFullTicketBetsFromAffiliateCredit() -- line 862

```
Call Site: DegenerusGame.placeFullTicketBetsFromAffiliateCredit (line 862)
  Resolution: _resolvePlayer(player) passed inline as first argument to delegatecall
  Value Operations After Resolution:
    - Lines 855-869: resolved player passed to DegeneretteModule.placeFullTicketBetsFromAffiliateCredit(resolved, ...)
    - Affiliate credit consumed from the resolved player
    - Bets recorded against the resolved player
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.12 resolveDegeneretteBets() -- line 884

```
Call Site: DegenerusGame.resolveDegeneretteBets (line 884)
  Resolution: _resolvePlayer(player) passed inline as first argument to delegatecall
  Value Operations After Resolution:
    - Lines 879-888: resolved player passed to DegeneretteModule.resolveBets(resolved, betIds)
    - Bet payouts (ETH credits, BURNIE mints, WWXRP mints) go to the resolved player
  Verdict: PASS -- resolved address used for all value attribution
```

### 2.13 issueDeityBoon() -- line 1005

```
Call Site: DegenerusGame.issueDeityBoon (line 1005)
  Resolution: deity = _resolvePlayer(deity)
  Value Operations After Resolution:
    - Line 1006: check recipient != deity (prevents self-boon)
    - Lines 1007-1017: delegatecall LootboxModule.issueDeityBoon(deity, recipient, slot)
    - The boon is issued FROM the deity (resolved) TO the recipient
    - No ETH/token transfer on the deity side (boon consumption, not value transfer)
  Verdict: PASS -- resolved deity address used for boon issuance tracking
```

### 2.14 claimWinnings() -- line 1429

```
Call Site: DegenerusGame.claimWinnings (line 1429)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1430: _claimWinningsInternal(player, false)
    - Line 1445: amount = claimableWinnings[player] -- reads from resolved player
    - Line 1449: claimableWinnings[player] = 1 -- writes to resolved player
    - Line 1453: emit WinningsClaimed(player, msg.sender, payout)
      * msg.sender used in EVENT ONLY as "operator" field -- ACCEPTABLE (logging who triggered)
    - Line 1457: _payoutWithStethFallback(player, payout) -- ETH/stETH sent to resolved player
  Verdict: PASS -- all value operations target the resolved player; msg.sender only in event (non-value)
```

### 2.15 claimAffiliateDgnrs() -- line 1468

```
Call Site: DegenerusGame.claimAffiliateDgnrs (line 1468)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1474: affiliateDgnrsClaimedBy[prevLevel][player] -- reads from resolved player
    - Line 1476: affiliate.affiliateScore(prevLevel, player) -- score for resolved player
    - Line 1477: deityPassCount[player] -- reads from resolved player
    - Lines 1491-1494: dgnrs.transferFromPool(Pool.Affiliate, player, reward) -- DGNRS tokens sent to resolved player
    - Line 1502: coin.creditFlip(player, bonus) -- BURNIE credited to resolved player
    - Line 1506: affiliateDgnrsClaimedBy[prevLevel][player] = true -- writes to resolved player
    - Line 1507: emit AffiliateDgnrsClaimed(player, prevLevel, msg.sender, score, paid)
      * msg.sender used in EVENT ONLY as "operator" field -- ACCEPTABLE (logging who triggered)
  Verdict: PASS -- all value operations target the resolved player; msg.sender only in event (non-value)
```

### 2.16 setAutoRebuy() -- line 1541

```
Call Site: DegenerusGame.setAutoRebuy (line 1541)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1542: _setAutoRebuy(player, enabled)
    - Lines 1572-1581: autoRebuyState[player] read/written
    - No ETH/token transfer in this function -- configuration only
  Verdict: PASS -- configuration stored against resolved player (no value transfer)
```

### 2.17 setDecimatorAutoRebuy() -- line 1550

```
Call Site: DegenerusGame.setDecimatorAutoRebuy (line 1550)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1551: check player != DGNRS contract
    - Lines 1554-1556: decimatorAutoRebuyDisabled[player] read/written
    - No ETH/token transfer -- configuration only
  Verdict: PASS -- configuration stored against resolved player (no value transfer)
```

### 2.18 setAutoRebuyTakeProfit() -- line 1568

```
Call Site: DegenerusGame.setAutoRebuyTakeProfit (line 1568)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1569: _setAutoRebuyTakeProfit(player, takeProfit)
    - Lines 1584-1597: autoRebuyState[player] read/written
    - No ETH/token transfer -- configuration only
  Verdict: PASS -- configuration stored against resolved player (no value transfer)
```

### 2.19 setAfKingMode() -- line 1643

```
Call Site: DegenerusGame.setAfKingMode (line 1643)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1644: _setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit)
    - Lines 1647-1685: autoRebuyState[player] read/written, coinflip configuration set for player
    - Line 1678: coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep) -- configures coinflip for player
    - Line 1681: coinflip.settleFlipModeChange(player) -- settles for player
    - No ETH/token transfer -- configuration only (coinflip auto-rebuy setup)
  Verdict: PASS -- all configuration targets resolved player
```

### 2.20 claimWhalePass() -- line 1782

```
Call Site: DegenerusGame.claimWhalePass (line 1782)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Line 1783: _claimWhalePassFor(player)
    - Lines 1786-1795: delegatecall EndgameModule.claimWhalePass(player)
    - Whale pass rewards (tickets, streak bonuses) attributed to player
  Verdict: PASS -- resolved address used for all value attribution
```

### Summary: Additional msg.sender Usages in DegenerusGame

After `_resolvePlayer` is called, `msg.sender` appears in only two contexts:
1. **Event emissions** (lines 1453, 1507): Used as the "operator" field to log who triggered the claim. No value is routed to msg.sender. ACCEPTABLE.
2. **Access control checks** (e.g., contract-only modifiers): These are unrelated to _resolvePlayer and occur in different functions.

**No value-bearing operation uses msg.sender after _resolvePlayer in any DegenerusGame function.**

---

## 3. BurnieCoinflip Call Sites (4 call sites + 1 inline resolution)

### 3.1 claimCoinflips() -- line 335

```
Call Site: BurnieCoinflip.claimCoinflips (line 335)
  Resolution: _resolvePlayer(player) passed inline to _claimCoinflipsAmount()
  Value Operations After Resolution:
    - _claimCoinflipsAmount(resolvedPlayer, amount, true)
    - Line 408: playerState[player] storage read
    - Line 423: burnie.mintForCoinflip(player, toClaim) -- BURNIE minted to resolved player
  Verdict: PASS -- BURNIE minted to resolved player
```

### 3.2 claimCoinflipsTakeProfit() -- line 345

```
Call Site: BurnieCoinflip.claimCoinflipsTakeProfit (line 345)
  Resolution: _resolvePlayer(player) passed inline to _claimCoinflipsTakeProfit()
  Value Operations After Resolution:
    - _claimCoinflipsTakeProfit(resolvedPlayer, multiples)
    - Line 373: playerState[player] storage read
    - Line 398: burnie.mintForCoinflip(player, toClaim) -- BURNIE minted to resolved player
  Verdict: PASS -- BURNIE minted to resolved player
```

### 3.3 setCoinflipAutoRebuyTakeProfit() -- line 711

```
Call Site: BurnieCoinflip.setCoinflipAutoRebuyTakeProfit (line 711)
  Resolution: _resolvePlayer(player) passed to _setCoinflipAutoRebuyTakeProfit()
  Value Operations After Resolution:
    - Lines 772-786: playerState[player] storage read/written
    - Line 781: burnie.mintForCoinflip(player, mintable) -- BURNIE minted to resolved player
    - No ETH transfer -- configuration + pending claim settlement
  Verdict: PASS -- any pending claims minted to resolved player; config stored against resolved player
```

### 3.4 depositCoinflip() -- line 231 (inline resolution, not using _resolvePlayer)

```
Call Site: BurnieCoinflip.depositCoinflip (line 231)
  Resolution: Inline resolution (NOT using _resolvePlayer):
    - if (player == address(0) || player == msg.sender) -> caller = msg.sender
    - else -> check isOperatorApproved(player, msg.sender), caller = player
  Value Operations After Resolution:
    - Line 244: _depositCoinflip(caller, amount, directDeposit)
    - Line 271: burnie.burnForCoinflip(caller, amount) -- BURNIE burned FROM resolved caller
    - Lines 280-286: quest handling for resolved caller
    - Lines 314-319: _addDailyFlip(caller, ...) -- flip credited to resolved caller
  Verdict: PASS -- functionally equivalent to _resolvePlayer; value correctly attributed to resolved caller
```

### 3.5 setCoinflipAutoRebuy() -- line 692 (inline resolution, not using _resolvePlayer)

```
Call Site: BurnieCoinflip.setCoinflipAutoRebuy (line 692)
  Resolution: Inline resolution (NOT using _resolvePlayer):
    - if (player == address(0)) -> player = msg.sender
    - else if (!fromGame && player != msg.sender) -> _requireApproved(player)
    - Special case: if fromGame (msg.sender == GAME), no approval check needed
  Value Operations After Resolution:
    - Line 703: _setCoinflipAutoRebuy(player, enabled, takeProfit, !fromGame)
    - Lines 726-763: playerState[player] read/written; mintable claimed for player
    - Line 763: burnie.mintForCoinflip(player, mintable) -- BURNIE minted to resolved player
  Verdict: PASS -- value attributed to resolved player; Game contract bypass for cross-contract calls is correct
```

### Summary: BurnieCoinflip msg.sender Usage After Resolution

After player resolution, `msg.sender` is never used for value-bearing operations. All BURNIE mints, burns, and flip credits target the resolved player address.

---

## 4. DegeneretteModule Call Sites (3 call sites)

### 4.1 placeFullTicketBets() -- line 391

```
Call Site: DegeneretteModule.placeFullTicketBets (line 391)
  Resolution: _resolvePlayer(player) passed inline to _placeFullTicketBets()
  Value Operations After Resolution:
    - Lines 454-485: _placeFullTicketBets(resolved, currency, ...)
    - Line 471-477: _collectBetFunds(player, currency, totalBet, msg.value, ...)
      * ETH/BURNIE/WWXRP collected FROM player (line 583: claimableWinnings[player]; line 594: coin.burnCoin(player, ...))
    - Line 517-521: degeneretteBetNonce[player], degeneretteBets[player][nonce] -- bet stored for player
    - Line 544-545: playerDegeneretteEthWagered[player][lvl] -- stats tracked for player
  Verdict: PASS -- all value operations (fund collection, bet storage, stats) target resolved player
```

### 4.2 placeFullTicketBetsFromAffiliateCredit() -- line 414

```
Call Site: DegeneretteModule.placeFullTicketBetsFromAffiliateCredit (line 414)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Lines 415-421: _placeFullTicketBetsCore(player, CURRENCY_BURNIE, ...) -- bet recorded for player
    - Line 424: affiliate.consumeDegeneretteCredit(player, totalBet) -- credit consumed FROM player
    - Line 428: coin.notifyQuestDegenerette(player, totalBet, false) -- quest progress for player
  Verdict: PASS -- all value operations target resolved player
```

### 4.3 resolveBets() -- line 439

```
Call Site: DegeneretteModule.resolveBets (line 439)
  Resolution: player = _resolvePlayer(player)
  Value Operations After Resolution:
    - Lines 440-446: loop calling _resolveBet(player, betIds[i])
    - Line 602-607: _resolveBet reads degeneretteBets[player][betId] -- reads FROM player
    - Line 625: delete degeneretteBets[player][betId] -- clears FOR player
    - Line 678: _distributePayout(player, currency, payout, ...) -- payout TO player
      * Line 719: _addClaimableEth(player, ethPortion) -- ETH credited to player
      * Line 723: _resolveLootboxDirect(player, lootboxPortion, ...) -- lootbox credited to player
      * Line 726: coin.mintForGame(player, payout) -- BURNIE minted to player
      * Line 728: wwxrp.mintPrize(player, payout) -- WWXRP minted to player
    - Line 690: _maybeAwardConsolation(player, ...)
      * Line 749: wwxrp.mintPrize(player, CONSOLATION_PRIZE_WWXRP) -- consolation to player
  Verdict: PASS -- all payouts (ETH, BURNIE, WWXRP, lootbox) target resolved player
```

### Summary: DegeneretteModule msg.sender Usage After Resolution

After `_resolvePlayer`, `msg.sender` is never referenced in any value-bearing context. All value operations (bet placement, fund collection, payouts) exclusively use the resolved `player` address.

---

## 5. Cross-Contract Operator Function Audit

### 5.1 DegenerusVault._requireApproved (line 402)

```solidity
function _requireApproved(address player) private view {
    if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {
        revert NotApproved();
    }
}
```

**Call sites:**

#### 5.1a burnCoin() -- line 755-762

```
Resolution: Inline (if player == address(0) -> player = msg.sender; else if player != msg.sender -> _requireApproved)
Value Operations:
  - _burnCoinFor(player, amount) -- burns DGVB shares FROM player
  - Line 781: share.vaultBurn(player, amount) -- burns FROM player
  - Lines 792, 799, 805: BURNIE transferred/minted TO player
Verdict: PASS -- shares burned from player, BURNIE sent to player
```

#### 5.1b burnEth() -- line 822-832

```
Resolution: Inline (if player == address(0) -> player = msg.sender; else if player != msg.sender -> _requireApproved)
Value Operations:
  - _burnEthFor(player, amount) -- burns DGVE shares FROM player
  - Line 873: share.vaultBurn(player, amount) -- burns FROM player
  - Line 880: _payEth(player, ethOut) -- ETH sent TO player
  - Line 881: _paySteth(player, stEthOut) -- stETH sent TO player
Verdict: PASS -- shares burned from player, ETH/stETH sent to player
```

### 5.2 BurnieCoin.decimatorBurn() -- line 859

```solidity
// Inline resolution:
if (player == address(0) || player == msg.sender) {
    caller = msg.sender;
} else {
    if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
        revert NotApproved();
    }
    caller = player;
}
```

**Value Operations:**
- Line 875: `_consumeCoinflipShortfall(caller, amount)` -- coinflip consumed FROM caller
- Line 877: `_burn(caller, amount - consumed)` -- BURNIE burned FROM caller
- Lines 887-892: quest rewards applied to caller
- Line 896: `coinflip.creditFlip(caller, questReward)` -- credited TO caller

**Note:** This function burns tokens FROM the resolved player (caller) and credits quest rewards TO the resolved player. No value flows to msg.sender.

```
Verdict: PASS -- all burns and credits target the resolved caller (player)
```

### 5.3 BurnieCoinflip.depositCoinflip() -- line 231

Already audited in Section 3.4. Uses inline resolution equivalent to `_resolvePlayer`. PASS.

### 5.4 DegenerusStonk._requireApproved (line 347)

```solidity
function _requireApproved(address player) private view {
    if (msg.sender != player && !game.isOperatorApproved(player, msg.sender)) {
        revert NotApproved();
    }
}
```

**Call site:**

#### 5.4a burn() -- line 818-828

```
Resolution: Inline (if player == address(0) -> player = msg.sender; else if player != msg.sender -> _requireApproved)
Value Operations:
  - _burnFor(player, amount)
  - Line 858: _burnWithBalance(player, amount, bal) -- burns DGNRS FROM player
  - Lines 879, 883: coin.transfer(player, ...) -- BURNIE sent TO player
  - Line 888: player.call{value: ethOut}("") -- ETH sent TO player
  - Line 892: steth.transfer(player, stethOut) -- stETH sent TO player
  - Line 896: wwxrp.transfer(player, wwxrpOut) -- WWXRP sent TO player
Verdict: PASS -- DGNRS burned from player; all assets (ETH, stETH, BURNIE, WWXRP) sent to player
```

### Summary: Cross-Contract Value Flow

All 4 cross-contract operator consumers correctly resolve the player address and route all value (ETH, stETH, BURNIE, DGNRS, WWXRP) to the resolved player. No value flows to `msg.sender` in any cross-contract operator function.

---

## 6. msg.sender Usage After _resolvePlayer -- Comprehensive Check

### 6.1 DegenerusGame

After `_resolvePlayer` is called, `msg.sender` appears in exactly 2 locations:
- **Line 1453:** `emit WinningsClaimed(player, msg.sender, payout)` -- EVENT ONLY (logs operator)
- **Line 1507:** `emit AffiliateDgnrsClaimed(player, prevLevel, msg.sender, score, paid)` -- EVENT ONLY (logs operator)

Both are non-value-bearing event emissions used for off-chain tracking of which address triggered the claim. **No security impact.**

### 6.2 BurnieCoinflip

After `_resolvePlayer` or inline resolution, `msg.sender` is not used for any value-bearing operation. All BURNIE mints, burns, and flip credits go to the resolved player.

### 6.3 DegeneretteModule

After `_resolvePlayer`, `msg.sender` is never referenced. All bets, payouts, and credits target the resolved player.

---

## 7. Edge Case Analysis

### 7.1 player == address(0)

All 3 implementations return `msg.sender`. This is the "act for yourself" path. Value correctly flows to msg.sender because they ARE the player. No operator delegation occurs.

**Verdict: PASS** -- Consistent across all 3 implementations.

### 7.2 player == msg.sender

All 3 implementations return `player` (which equals msg.sender). `_requireApproved` is skipped because `player != msg.sender` is false. Value flows to player/msg.sender (same address).

**Verdict: PASS** -- Consistent across all 3 implementations.

### 7.3 player != msg.sender AND approved

All 3 implementations return `player` (the principal, not the operator). This is the critical case for value extraction attacks. All subsequent value operations target `player`, not `msg.sender`.

**Verdict: PASS** -- Value correctly flows to the principal, not the operator.

### 7.4 player != msg.sender AND NOT approved

All 3 implementations revert (Game/DegeneretteModule: `NotApproved()`, BurnieCoinflip: `OnlyBurnieCoin()`). No value flow occurs.

**Verdict: PASS** -- Unauthorized operator is blocked.

---

## 8. Summary Table -- All Call Sites

| # | Contract | Function | Line | Resolution Type | Value Operation | msg.sender Used for Value? | Verdict |
|---|----------|----------|------|-----------------|-----------------|---------------------------|---------|
| 1 | DegenerusGame | purchase() | 547 | buyer = _resolvePlayer(buyer) | Tickets + ETH attribution | No | PASS |
| 2 | DegenerusGame | purchaseCoin() | 590 | buyer = _resolvePlayer(buyer) | BURNIE burn + tickets | No | PASS |
| 3 | DegenerusGame | purchaseBurnieLootbox() | 611 | buyer = _resolvePlayer(buyer) | BURNIE lootbox | No | PASS |
| 4 | DegenerusGame | purchaseWhaleBundle() | 644 | buyer = _resolvePlayer(buyer) | Whale bundle attribution | No | PASS |
| 5 | DegenerusGame | purchaseLazyPass() | 666 | buyer = _resolvePlayer(buyer) | Lazy pass ownership | No | PASS |
| 6 | DegenerusGame | purchaseDeityPass() | 689 | buyer = _resolvePlayer(buyer) | Deity pass + refund tracking | No | PASS |
| 7 | DegenerusGame | refundDeityPass() | 700 | buyer = _resolvePlayer(buyer) | ETH/stETH refund payout | No | PASS |
| 8 | DegenerusGame | openLootBox() | 768 | player = _resolvePlayer(player) | Lootbox rewards | No | PASS |
| 9 | DegenerusGame | openBurnieLootBox() | 776 | player = _resolvePlayer(player) | BURNIE lootbox rewards | No | PASS |
| 10 | DegenerusGame | placeFullTicketBets() | 831 | inline _resolvePlayer(player) | Bet placement + fund collection | No | PASS |
| 11 | DegenerusGame | placeFullTicketBetsFromAffiliateCredit() | 862 | inline _resolvePlayer(player) | Affiliate credit consumption | No | PASS |
| 12 | DegenerusGame | resolveDegeneretteBets() | 884 | inline _resolvePlayer(player) | ETH/BURNIE/WWXRP payouts | No | PASS |
| 13 | DegenerusGame | issueDeityBoon() | 1005 | deity = _resolvePlayer(deity) | Boon issuance tracking | No | PASS |
| 14 | DegenerusGame | claimWinnings() | 1429 | player = _resolvePlayer(player) | ETH/stETH withdrawal (CRITICAL) | Event only | PASS |
| 15 | DegenerusGame | claimAffiliateDgnrs() | 1468 | player = _resolvePlayer(player) | DGNRS + BURNIE rewards | Event only | PASS |
| 16 | DegenerusGame | setAutoRebuy() | 1541 | player = _resolvePlayer(player) | Configuration (no transfer) | No | PASS |
| 17 | DegenerusGame | setDecimatorAutoRebuy() | 1550 | player = _resolvePlayer(player) | Configuration (no transfer) | No | PASS |
| 18 | DegenerusGame | setAutoRebuyTakeProfit() | 1568 | player = _resolvePlayer(player) | Configuration (no transfer) | No | PASS |
| 19 | DegenerusGame | setAfKingMode() | 1643 | player = _resolvePlayer(player) | Configuration + coinflip setup | No | PASS |
| 20 | DegenerusGame | claimWhalePass() | 1782 | player = _resolvePlayer(player) | Whale pass rewards | No | PASS |
| 21 | BurnieCoinflip | claimCoinflips() | 335 | inline _resolvePlayer(player) | BURNIE mint | No | PASS |
| 22 | BurnieCoinflip | claimCoinflipsTakeProfit() | 345 | inline _resolvePlayer(player) | BURNIE mint | No | PASS |
| 23 | BurnieCoinflip | setCoinflipAutoRebuyTakeProfit() | 711 | _resolvePlayer(player) | BURNIE mint (pending) + config | No | PASS |
| 24 | BurnieCoinflip | depositCoinflip() | 231 | inline equiv. to _resolvePlayer | BURNIE burn + flip credit | No | PASS |
| 25 | BurnieCoinflip | setCoinflipAutoRebuy() | 692 | inline equiv. (Game bypass) | BURNIE mint (pending) + config | No | PASS |
| 26 | DegeneretteModule | placeFullTicketBets() | 391 | inline _resolvePlayer(player) | Bet + fund collection | No | PASS |
| 27 | DegeneretteModule | placeFullTicketBetsFromAffiliateCredit() | 414 | player = _resolvePlayer(player) | Affiliate credit + bet | No | PASS |
| 28 | DegeneretteModule | resolveBets() | 439 | player = _resolvePlayer(player) | ETH/BURNIE/WWXRP payouts | No | PASS |
| 29 | DegenerusVault | burnCoin() | 755 | inline + _requireApproved | DGVB burn + BURNIE payout | No | PASS |
| 30 | DegenerusVault | burnEth() | 822 | inline + _requireApproved | DGVE burn + ETH/stETH payout | No | PASS |
| 31 | BurnieCoin | decimatorBurn() | 859 | inline + isOperatorApproved | BURNIE burn + quest credit | No | PASS |
| 32 | DegenerusStonk | burn() | 818 | inline + _requireApproved | DGNRS burn + all assets payout | No | PASS |

---

## 9. AUTH-05 Verdict

### Requirement

> Prove that `_resolvePlayer` correctly routes value flows to the resolved player address across all call sites. If any call site uses `msg.sender` for ETH transfer, token minting, or game credit after resolving player to a different address, an operator could steal the player's value.

### Findings

1. **All 3 `_resolvePlayer` implementations are functionally equivalent.** They read the same `operatorApprovals` mapping from DegenerusGame storage (directly for Game and DegeneretteModule via delegatecall, cross-contract call for BurnieCoinflip). The only difference is the revert error in BurnieCoinflip (`OnlyBurnieCoin` vs `NotApproved`), which is cosmetic.

2. **20 DegenerusGame call sites** all route value to the resolved player. The only post-resolution `msg.sender` usage is in event emissions (lines 1453, 1507) to log the operator address -- no value is directed to msg.sender.

3. **5 BurnieCoinflip call sites** (3 using `_resolvePlayer`, 2 using functionally equivalent inline resolution) all route BURNIE mints and flip credits to the resolved player.

4. **3 DegeneretteModule call sites** all route bets, fund collections, and payouts (ETH, BURNIE, WWXRP) to the resolved player.

5. **4 cross-contract operator consumers** (DegenerusVault burnCoin/burnEth, BurnieCoin decimatorBurn, DegenerusStonk burn) all use `game.isOperatorApproved()` for authorization and route all value (ETH, stETH, BURNIE, DGNRS, WWXRP, DGVB, DGVE) to the resolved player.

6. **Zero instances** of msg.sender being used for value-bearing operations after player resolution.

7. **All 4 edge cases** (address(0), player == msg.sender, approved operator, unapproved operator) are handled correctly and consistently.

### Informational Notes

- **BurnieCoinflip error reuse (OnlyBurnieCoin):** The `_resolvePlayer` in BurnieCoinflip reuses the `OnlyBurnieCoin` error for unapproved operators instead of `NotApproved`. This is cosmetic and does not affect security, but could cause confusion in error handling on the client side. Severity: INFORMATIONAL.

- **setOperatorApproval() does not use _resolvePlayer:** This is correct by design. Players can only set approvals for themselves (`operatorApprovals[msg.sender][operator]`). An operator cannot modify the principal's approval settings.

- **reverseFlip() does not use _resolvePlayer:** This function is not operator-delegatable by design. It uses `msg.sender` directly (via the AdvanceModule). The `player` parameter passed from Game to the module is unused due to ABI mismatch (module's `reverseFlip()` takes no parameters). This is a separate design choice, not a vulnerability.

---

**AUTH-05: PASS**

All 32 audited call sites across 6 contracts correctly route value to the resolved player address. No operator can extract value by acting on behalf of a player -- all ETH, stETH, BURNIE, DGNRS, DGVB, DGVE, and WWXRP flows target the principal, not the operator. The `_resolvePlayer` pattern is implemented consistently and correctly across the entire protocol.
