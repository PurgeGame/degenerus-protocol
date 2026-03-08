# 06-06 Findings: Operator Delegation Non-Escalation and Revocation Audit

**Requirement:** AUTH-04
**Date:** 2026-03-01
**Scope:** operatorApprovals mapping, setOperatorApproval, isOperatorApproved, _resolvePlayer, _requireApproved across DegenerusGame, DegenerusVault, BurnieCoin, BurnieCoinflip, DegenerusStonk
**Contracts modified:** None (READ-ONLY audit)

---

## 1. setOperatorApproval Audit

**Location:** `DegenerusGame.sol` lines 474-478

```solidity
function setOperatorApproval(address operator, bool approved) external {
    if (operator == address(0)) revert E();
    operatorApprovals[msg.sender][operator] = approved;
    emit OperatorApproval(msg.sender, operator, approved);
}
```

### Findings

| Check | Result | Evidence |
|-------|--------|----------|
| Only msg.sender can set own approvals | PASS | `operatorApprovals[msg.sender][operator]` -- the first key is always msg.sender, no admin override path exists |
| Approval is a simple boolean | PASS | `mapping(address => mapping(address => bool)) public operatorApprovals` -- single bool per (player, operator) pair |
| No batch approval mechanism | PASS | No `setOperatorApprovalBatch` or similar function exists in DegenerusGame |
| Operator cannot approve themselves for another player | PASS | Only msg.sender can write to `operatorApprovals[msg.sender][*]` -- an operator cannot call `setOperatorApproval` and have it affect any mapping key other than their own address |
| Zero-address guard | PASS | `if (operator == address(0)) revert E()` prevents approving address(0) as operator |
| Self-approval (player approves themselves) | NEUTRAL | Not blocked, but harmless -- `_requireApproved` already passes when `msg.sender == player` |

**Verdict:** setOperatorApproval is correctly implemented with no admin override, no batch mechanism, and a zero-address guard.

---

## 2. isOperatorApproved Audit

**Location:** `DegenerusGame.sol` lines 484-489

```solidity
function isOperatorApproved(
    address owner,
    address operator
) external view returns (bool approved) {
    return operatorApprovals[owner][operator];
}
```

### Findings

| Check | Result | Evidence |
|-------|--------|----------|
| Simply reads mapping | PASS | Direct storage read, no transformation or side effects |
| Is view/pure | PASS | Declared `external view` -- no state modifications |
| Callable by anyone | PASS | No access modifier -- read-only, harmless |
| No caching or stale reads | PASS | Direct SLOAD from current state |

**Verdict:** isOperatorApproved is a pure storage read with no side effects.

---

## 3. Immediate Revocation Proof

When `setOperatorApproval(operator, false)` is called:

### Storage Update

The mapping `operatorApprovals[msg.sender][operator]` is written to `false` in the same transaction via a direct SSTORE. There is:

- **No pending period:** No `pendingApproval`, no timelock struct, no delay variable
- **No cooldown:** No `lastRevocationTime` or minimum approval duration
- **No two-step process:** No `requestRevocation` + `confirmRevocation` pattern

### Same-Block Effectiveness

The approval check in `_requireApproved` reads `operatorApprovals[player][msg.sender]` at call time:

```solidity
function _requireApproved(address player) private view {
    if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
        revert NotApproved();
    }
}
```

If the player calls `setOperatorApproval(operator, false)` in transaction T1 of block B, and the operator calls an operator-gated function in transaction T2 of the same block B (where T2 comes after T1 in ordering), the operator's transaction reads the **updated** mapping value (`false`) because Ethereum state transitions are applied sequentially within a block. The operator's call will revert with `NotApproved()`.

### Cross-Contract Revocation

All cross-contract consumers call `game.isOperatorApproved()` as an external call at invocation time. There is no local caching of approval status in any consumer contract:

- `DegenerusVault._requireApproved` -- calls `game.isOperatorApproved()` at function entry
- `BurnieCoin.decimatorBurn` -- calls `degenerusGame.isOperatorApproved()` at function entry
- `BurnieCoinflip.depositCoinflip` -- calls `degenerusGame.isOperatorApproved()` at function entry
- `BurnieCoinflip._resolvePlayer` -- calls `degenerusGame.isOperatorApproved()` at function entry
- `BurnieCoinflip._requireApproved` -- calls `degenerusGame.isOperatorApproved()` at function entry
- `DegenerusStonk._requireApproved` -- calls `game.isOperatorApproved()` at function entry

No contract stores operator approval in local storage or caches it across transactions.

**Verdict:** Revocation is immediate and effective within the same block. No delay, no pending state, no caching.

---

## 4. Non-Escalation Proof for DegenerusGame

Every function in DegenerusGame that uses `_resolvePlayer` allows an operator to act on behalf of the player. The key question: can the operator do anything the player cannot?

### Functions Using _resolvePlayer

| Function | What Operator Can Do | Player Can Do Same? | Value Flows To |
|----------|---------------------|---------------------|----------------|
| `purchase()` | Buy tickets/lootboxes for player | Yes | Tickets/lootboxes credited to player; ETH comes from msg.value (operator pays) |
| `purchaseCoin()` | Buy tickets/lootboxes with BURNIE for player | Yes | BURNIE burned from player (via delegatecall to MintModule); tickets credited to player |
| `purchaseBurnieLootbox()` | Purchase BURNIE lootbox for player | Yes | BURNIE burned from player; lootbox credited to player |
| `purchaseWhaleBundle()` | Buy whale bundle for player | Yes | ETH from msg.value (operator pays); bundle credited to player |
| `purchaseLazyPass()` | Buy lazy pass for player | Yes | ETH from msg.value (operator pays); pass credited to player |
| `purchaseDeityPass()` | Buy deity pass for player | Yes | ETH from msg.value (operator pays); pass and symbol assigned to player |
| `refundDeityPass()` | Refund player's deity pass | Yes | ETH refund sent to player via `_payoutWithStethFallback(buyer, refundAmount)` | **(POST-AUDIT: function removed)** |
| `openLootBox()` | Open player's lootbox | Yes | Lootbox rewards credited to player |
| `openBurnieLootBox()` | Open player's BURNIE lootbox | Yes | Lootbox rewards credited to player |
| `claimWinnings()` | Claim player's ETH winnings | Yes | ETH sent to player via `_payoutWithStethFallback(player, payout)` |
| `claimWhalePass()` | Claim player's whale pass rewards | Yes | Rewards credited to player |
| `claimAffiliateDgnrs()` | Claim player's DGNRS affiliate rewards | Yes | DGNRS transferred to player; flip credit to player |
| `setAutoRebuy()` | Toggle player's auto-rebuy | Yes | Configuration only, no value transfer |
| `setDecimatorAutoRebuy()` | Toggle player's decimator auto-rebuy | Yes | Configuration only, no value transfer |
| `setAutoRebuyTakeProfit()` | Set player's take profit threshold | Yes | Configuration only, no value transfer |
| `setAfKingMode()` | Toggle player's afKing mode | Yes | Configuration only, no value transfer |
| `issueDeityBoon()` | Issue a deity boon on behalf of deity player | Yes | Boon issued from deity to recipient |
| `placeFullTicketBets()` | Place degenerette bets for player | Yes | ETH from msg.value (operator pays); bets placed for player |
| `placeFullTicketBetsFromAffiliateCredit()` | Place bets using player's affiliate credit | Yes | Affiliate credit consumed from player; bets placed for player |
| `resolveDegeneretteBets()` | Resolve player's pending bets | Yes | Payouts credited to player |
| `reverseFlip()` | Nudge RNG (burns operator's BURNIE) | Yes | BURNIE burned from msg.sender (operator) in the AdvanceModule; no _resolvePlayer used in module |

### Critical Checks

**Can operator set player's operator approvals?**
NO. `setOperatorApproval` uses `msg.sender` directly, not `_resolvePlayer`. An operator cannot call `setOperatorApproval` and affect the player's approval mapping. The operator can only set approvals for themselves.

**Can operator claim winnings to their own address?**
NO. `_claimWinningsInternal(player, false)` sends ETH to `player` via `_payoutWithStethFallback(player, payout)`. The `player` variable comes from `_resolvePlayer(player)` which resolves to the actual player address, not msg.sender.

**Can operator modify game state harmfully?**
PARTIALLY -- an operator can toggle configuration settings (auto-rebuy, afKing mode, take profit). These are settings the player could also toggle. The afKing lock prevents rapid toggling (5-level lock period). An operator toggling auto-rebuy off during a critical moment could cause the player to miss auto-rebuy opportunities, but this is within the delegation trust model (the player approved this operator).

**Can operator spend player's claimable winnings?**
YES, indirectly -- `purchase()` with `payKind=Claimable` or `payKind=Combined` can spend the player's claimable winnings on tickets. However, the player could do the same. Tickets are credited to the player. The operator cannot extract the claimable balance to themselves.

**Verdict:** No privilege escalation. Every action an operator can perform is also available to the player. No operator action sends value to the operator's address.

---

## 5. Non-Escalation Proof for Cross-Contract Consumers

### 5a. DegenerusVault

**Operator check:** `_requireApproved(player)` calls `game.isOperatorApproved(player, msg.sender)` (line 403)

| Function | Operator Can Do | Value Flows To | Escalation? |
|----------|----------------|----------------|-------------|
| `burnCoin(player, amount)` | Burn player's DGVB shares for BURNIE | BURNIE transferred to `player` (line 792: `coinToken.transfer(player, payBal)`) | NO |
| `burnEth(player, amount)` | Burn player's DGVE shares for ETH/stETH | ETH sent to `player` (line 880: `_payEth(player, ethOut)`), stETH to `player` (line 881: `_paySteth(player, stEthOut)`) | NO |

**Key observations:**
- `burnCoin` burns the player's shares and sends BURNIE to `player`, not msg.sender
- `burnEth` burns the player's shares and sends ETH/stETH to `player`, not msg.sender
- Vault-owner-only functions (`gameSetOperatorApproval`, `setAfKingMode`, `depositCoinflipForVault`, `claimDecimatorJackpotForVault`) use `onlyVaultOwner` modifier, not operator approval -- these are separate from the player operator system
- An operator cannot deposit into the vault on behalf of the player (no operator-gated deposit function exists)

**Verdict:** Non-escalating. All value flows to player.

### 5b. BurnieCoin

**Operator check:** Direct `degenerusGame.isOperatorApproved(player, msg.sender)` call (line 864)

| Function | Operator Can Do | Value Flows To | Escalation? |
|----------|----------------|----------------|-------------|
| `decimatorBurn(player, amount)` | Burn player's BURNIE for decimator jackpot eligibility | Burns from `caller` (which is set to `player` when operator acts, line 867); jackpot eligibility recorded for `caller` (player) | NO |

**Key observations:**
- When operator acts: `caller = player` (line 867). The BURNIE is burned from `player`, not from the operator
- This means the operator can burn the player's BURNIE tokens. This IS an action the player could also do
- Decimator jackpot eligibility is recorded for `player`, not operator
- The operator spends the player's BURNIE -- this is within the trust model (player approved this operator)

**Potential concern:** An operator could maliciously burn a player's BURNIE via `decimatorBurn`. However:
1. The player approved this operator
2. The player could do the same action
3. Decimator entries give the player jackpot eligibility (potential upside)
4. Revocation is immediate

**Verdict:** Non-escalating. Operator can burn player's BURNIE but only in ways the player could also do, and value (jackpot eligibility) accrues to the player.

### 5c. BurnieCoinflip

**Operator check:** `degenerusGame.isOperatorApproved(player, msg.sender)` (lines 238, 1190, 1199)

| Function | Operator Can Do | Value Flows To | Escalation? |
|----------|----------------|----------------|-------------|
| `depositCoinflip(player, amount)` | Deposit BURNIE into coinflip for player | BURNIE burned from `caller` (set to `player`, line 241); flip credited to `caller` (player) | NO |
| `claimCoinflips(player, amount)` | Claim player's coinflip winnings | BURNIE minted to `player` via `burnie.mintForCoinflip(player, toClaim)` (line 423) | NO |
| `claimCoinflipsTakeProfit(player, multiples)` | Claim player's take profit | BURNIE minted to `player` via `burnie.mintForCoinflip(player, toClaim)` (line 398) | NO |
| `setCoinflipAutoRebuy(player, enabled, takeProfit)` | Toggle player's coinflip auto-rebuy | Configuration only; minted BURNIE goes to `player` (line 763) | NO |
| `setCoinflipAutoRebuyTakeProfit(player, takeProfit)` | Set player's coinflip take profit | Configuration only; minted BURNIE goes to `player` (line 781) | NO |

**Key observations:**
- `depositCoinflip` with operator: burns BURNIE from `caller` (which is player), deposits flip credit for `caller` (player). The `directDeposit` flag is set to `false` when operator acts (line 242), which may affect quest notifications
- All claim functions mint BURNIE to `player`, never to msg.sender
- WWXRP loss rewards go to `player` (line 615: `wwxrp.mintPrize(player, ...)`)

**Verdict:** Non-escalating. All value flows (BURNIE mints, WWXRP prizes) go to the player.

### 5d. DegenerusStonk

**Operator check:** `_requireApproved(player)` calls `game.isOperatorApproved(player, msg.sender)` (line 348)

| Function | Operator Can Do | Value Flows To | Escalation? |
|----------|----------------|----------------|-------------|
| `burn(player, amount)` | Burn player's DGNRS tokens for ETH/stETH/BURNIE | ETH to `player` (line 888), stETH to `player` (line 892), BURNIE to `player` (lines 879, 883), WWXRP to `player` (line 896) | NO |

**Key observations:**
- `_burnFor(player, amount)` burns tokens from `player` (`balanceOf[player]` checked at line 840)
- All asset transfers go to `player`: `coin.transfer(player, ...)`, `player.call{value: ethOut}`, `steth.transfer(player, ...)`, `wwxrp.transfer(player, ...)`
- No path sends any asset to msg.sender

**Verdict:** Non-escalating. All value flows to player.

---

## 6. Operator Value Extraction Analysis

The critical question: **Can an operator extract value to their own address?**

### Systematic Trace

For every operator-enabled function across all five contracts, I traced whether any code path sends ETH, tokens, or credits to `msg.sender` (the operator) instead of the resolved player:

| Contract | Function | msg.sender Receives | player Receives | Verdict |
|----------|----------|---------------------|-----------------|---------|
| DegenerusGame | purchase() | Nothing | Tickets, lootboxes | SAFE |
| DegenerusGame | purchaseCoin() | Nothing | Tickets, lootboxes | SAFE |
| DegenerusGame | purchaseBurnieLootbox() | Nothing | Lootbox | SAFE |
| DegenerusGame | purchaseWhaleBundle() | Nothing | Bundle | SAFE |
| DegenerusGame | purchaseLazyPass() | Nothing | Lazy pass | SAFE |
| DegenerusGame | purchaseDeityPass() | Nothing | Deity pass | SAFE |
| DegenerusGame | refundDeityPass() | Nothing | ETH refund | SAFE | **(POST-AUDIT: function removed)** |
| DegenerusGame | openLootBox() | Nothing | Lootbox rewards | SAFE |
| DegenerusGame | openBurnieLootBox() | Nothing | Lootbox rewards | SAFE |
| DegenerusGame | claimWinnings() | Nothing | ETH payout | SAFE |
| DegenerusGame | claimWhalePass() | Nothing | Whale pass rewards | SAFE |
| DegenerusGame | claimAffiliateDgnrs() | Nothing | DGNRS + flip credit | SAFE |
| DegenerusGame | placeFullTicketBets() | Nothing | Bet resolution | SAFE |
| DegenerusGame | placeFullTicketBetsFromAffiliateCredit() | Nothing | Bet resolution | SAFE |
| DegenerusGame | resolveDegeneretteBets() | Nothing | Bet payouts | SAFE |
| DegenerusGame | reverseFlip() | Nothing (BURNIE burned from msg.sender) | N/A (module uses msg.sender directly) | SAFE |
| DegenerusVault | burnCoin() | Nothing | BURNIE | SAFE |
| DegenerusVault | burnEth() | Nothing | ETH + stETH | SAFE |
| BurnieCoin | decimatorBurn() | Nothing | Jackpot eligibility | SAFE |
| BurnieCoinflip | depositCoinflip() | Nothing | Flip credit | SAFE |
| BurnieCoinflip | claimCoinflips() | Nothing | BURNIE | SAFE |
| BurnieCoinflip | claimCoinflipsTakeProfit() | Nothing | BURNIE | SAFE |
| BurnieCoinflip | setCoinflipAutoRebuy() | Nothing | Configuration | SAFE |
| BurnieCoinflip | setCoinflipAutoRebuyTakeProfit() | Nothing | Configuration | SAFE |
| DegenerusStonk | burn() | Nothing | ETH + stETH + BURNIE + WWXRP | SAFE |

### Special Case: reverseFlip()

`DegenerusGame.reverseFlip(player)` passes `player` to the AdvanceModule via delegatecall, but the module's `reverseFlip()` function takes no parameters and uses `msg.sender` directly:

```solidity
// AdvanceModule (runs via delegatecall, msg.sender = original caller)
function reverseFlip() external {
    if (rngLockedFlag) revert RngLocked();
    uint256 cost = _currentNudgeCost(totalFlipReversals);
    coin.burnCoin(msg.sender, cost);  // Burns from operator, not player
    ...
}
```

The `player` parameter encoded in DegenerusGame's delegatecall selector encoding is simply ignored by the module (the module's function signature has no parameters). The operator pays the BURNIE cost themselves. This is **operator-favorable** (operator voluntarily spends their own BURNIE), not extractive.

### Special Case: Operator purchasing with ETH (msg.value)

When an operator calls `purchase(player, ...)` with `payKind=DirectEth`, the ETH comes from `msg.value` (operator's ETH). Tickets go to `player`. The operator voluntarily spends ETH on behalf of the player. This is a gift, not extraction.

When an operator calls `purchase(player, ...)` with `payKind=Claimable`, the player's claimable winnings are spent on tickets for the player. The operator spends zero ETH. The player's claimable balance decreases, but the player gets tickets. This could be seen as the operator spending the player's savings, but:
1. The player approved this operator
2. The player receives tickets of equivalent value
3. The player could revoke immediately

**Verdict:** No operator value extraction path exists. Zero functions send value to msg.sender when acting on behalf of a player.

---

## 7. Full Delegation Scope Table

An approved operator for a player can perform the following actions across the entire protocol:

| Contract | Function | What Operator Can Do | Value Recipient | Risk Level |
|----------|----------|---------------------|-----------------|------------|
| DegenerusGame | purchase | Buy tickets/lootboxes (ETH from operator or player's claimable) | Player | LOW |
| DegenerusGame | purchaseCoin | Buy tickets/lootboxes with player's BURNIE | Player | LOW |
| DegenerusGame | purchaseBurnieLootbox | Buy BURNIE lootbox with player's BURNIE | Player | LOW |
| DegenerusGame | purchaseWhaleBundle | Buy whale bundle (ETH from operator) | Player | LOW |
| DegenerusGame | purchaseLazyPass | Buy lazy pass (ETH from operator) | Player | LOW |
| DegenerusGame | purchaseDeityPass | Buy deity pass (ETH from operator) | Player | LOW |
| DegenerusGame | refundDeityPass | Refund player's deity pass | Player (ETH) | LOW | **(POST-AUDIT: function removed)** |
| DegenerusGame | openLootBox | Open player's pending lootbox | Player (rewards) | LOW |
| DegenerusGame | openBurnieLootBox | Open player's BURNIE lootbox | Player (rewards) | LOW |
| DegenerusGame | claimWinnings | Claim player's accrued ETH | Player (ETH) | LOW |
| DegenerusGame | claimWhalePass | Claim player's whale pass rewards | Player (rewards) | LOW |
| DegenerusGame | claimAffiliateDgnrs | Claim player's affiliate DGNRS | Player (DGNRS) | LOW |
| DegenerusGame | setAutoRebuy | Toggle player's auto-rebuy | N/A (config) | LOW |
| DegenerusGame | setDecimatorAutoRebuy | Toggle player's decimator auto-rebuy | N/A (config) | LOW |
| DegenerusGame | setAutoRebuyTakeProfit | Set player's take profit threshold | N/A (config) | LOW |
| DegenerusGame | setAfKingMode | Toggle player's afKing mode | N/A (config) | MEDIUM |
| DegenerusGame | issueDeityBoon | Issue boon on behalf of deity player | Recipient (boon) | LOW |
| DegenerusGame | placeFullTicketBets | Place degenerette bets (ETH from operator) | Player (bet results) | LOW |
| DegenerusGame | placeFullTicketBetsFromAffiliateCredit | Place bets using player's affiliate credit | Player (bet results) | LOW |
| DegenerusGame | resolveDegeneretteBets | Resolve player's pending bets | Player (payouts) | LOW |
| DegenerusVault | burnCoin | Burn player's DGVB for BURNIE | Player (BURNIE) | MEDIUM |
| DegenerusVault | burnEth | Burn player's DGVE for ETH/stETH | Player (ETH/stETH) | MEDIUM |
| BurnieCoin | decimatorBurn | Burn player's BURNIE for decimator entry | Player (jackpot eligibility) | MEDIUM |
| BurnieCoinflip | depositCoinflip | Deposit player's BURNIE into coinflip | Player (flip credit) | MEDIUM |
| BurnieCoinflip | claimCoinflips | Claim player's coinflip winnings | Player (BURNIE) | LOW |
| BurnieCoinflip | claimCoinflipsTakeProfit | Claim player's take profit multiples | Player (BURNIE) | LOW |
| BurnieCoinflip | setCoinflipAutoRebuy | Toggle player's coinflip auto-rebuy | N/A (config) | LOW |
| BurnieCoinflip | setCoinflipAutoRebuyTakeProfit | Set player's coinflip take profit | N/A (config) | LOW |
| DegenerusStonk | burn | Burn player's DGNRS for backing assets | Player (ETH/stETH/BURNIE/WWXRP) | MEDIUM |

### Blast Radius Assessment

The "blast radius" of a single operator approval is **broad**: 29 functions across 5 contracts. This is by design -- the protocol uses a single shared boolean for UX simplification.

**MEDIUM risk functions:** These allow an operator to spend or burn the player's tokens:
- `DegenerusVault.burnCoin/burnEth` -- operator can liquidate player's vault shares
- `BurnieCoin.decimatorBurn` -- operator can burn player's BURNIE
- `BurnieCoinflip.depositCoinflip` -- operator can deposit (lock up) player's BURNIE
- `DegenerusStonk.burn` -- operator can liquidate player's DGNRS
- `DegenerusGame.setAfKingMode` -- operator can lock player into afKing for 5 levels

All MEDIUM risk functions send value back to the player, not the operator. The risk is that a malicious operator could act against the player's interests (e.g., burning vault shares at a bad time) within the trust model.

**Mitigations:**
1. Revocation is immediate -- player can revoke at any time
2. All value flows to the player, never to the operator
3. The player explicitly chose to trust this operator

---

## 8. AUTH-04 Verdict

### Summary

| Criterion | Result |
|-----------|--------|
| Approval system simple and correctly implemented | PASS |
| Only msg.sender can set own approvals | PASS |
| Zero-address guard on operator | PASS |
| No admin can force approvals | PASS |
| Revocation is immediate (no delay, no pending state) | PASS |
| Revocation effective same-block | PASS |
| No cross-contract caching of approval status | PASS |
| Operator cannot escalate beyond player permissions | PASS |
| Operator cannot extract value to own address | PASS |
| All 5 cross-contract consumers correctly gate via game.isOperatorApproved() | PASS |
| All value flows route to player, not operator | PASS |

### Broad Delegation Scope Assessment

The protocol uses a single boolean approval covering 29 functions across 5 contracts. This is an intentional design decision documented in the research:

> "Per-contract operator approvals -> Single shared operator mapping in DegenerusGame. One approval covers all protocol contracts. Simpler UX but broader delegation scope."

**Is this a security concern?**

No, for three reasons:
1. **Non-escalating:** No operator action exceeds what the player can do
2. **Non-extractive:** No operator action sends value to the operator
3. **Immediately revocable:** Player can revoke in the same block

The broad scope means a player must fully trust their operator. This is appropriate for the use case (automated bot acting on behalf of player, game companion app, etc.) and consistent with ERC-721's `setApprovalForAll` pattern which similarly grants broad delegation.

### AUTH-04 VERDICT: PASS

The operatorApprovals delegation system is correctly implemented with:
- Self-sovereign approval (only msg.sender controls own approvals)
- Immediate revocation (no delay, no pending state, same-block effective)
- Non-escalation guarantee (operator cannot do anything player cannot)
- Non-extraction guarantee (all value flows to player, never to operator)
- Correct cross-contract delegation (all 4 external consumers + DegenerusGame itself correctly gate via isOperatorApproved with no local override or caching)

No findings. No recommendations. The system works as designed.
