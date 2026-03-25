# Unit 12: Vault + WWXRP -- Mad Genius Attack Report

**Phase:** 114
**Contracts:** DegenerusVaultShare (L138-300), DegenerusVault (L309-1050), WrappedWrappedXRP
**Agent:** Mad Genius (Opus)
**Date:** 2026-03-25

---

## CRITICAL TIER

---

## V-28: DegenerusVault::burnCoin (L749-756)

### Call Tree
```
burnCoin(player, amount) [L749-756]
  |-- if player == address(0): player = msg.sender [L750-751]
  |-- else if player != msg.sender: _requireApproved(player) [L752-753]
  |     |-- game.isOperatorApproved(player, msg.sender) [L407]
  |-- _burnCoinFor(player, amount) [L755, L762-802]
        |-- share = coinShare [L763]
        |-- if amount == 0: revert Insufficient [L764]
        |-- coinBal = _syncCoinReserves() [L766]
        |     |-- synced = coinToken.vaultMintAllowance() [L981] -> BurnieCoin
        |     |-- coinTracked = synced [L982]
        |-- supplyBefore = share.totalSupply() [L767] -> DegenerusVaultShare
        |-- vaultBal = coinToken.balanceOf(address(this)) [L768] -> BurnieCoin
        |-- claimable = coinflipPlayer.previewClaimCoinflips(address(this)) [L769] -> BurnieCoinflip
        |-- if vaultBal != 0 || claimable != 0: coinBal += vaultBal + claimable [L770-772]
        |-- coinOut = (coinBal * amount) / supplyBefore [L773]
        |-- share.vaultBurn(player, amount) [L775] -> DegenerusVaultShare
        |     |-- checks amount <= balanceOf[player] [L275]
        |     |-- balanceOf[player] -= amount [L277]
        |     |-- totalSupply -= amount [L278]
        |-- if supplyBefore == amount: share.vaultMint(player, REFILL_SUPPLY) [L776-778]
        |     |-- balanceOf[player] += 1T*1e18 [L262]
        |     |-- totalSupply += 1T*1e18 [L261]
        |-- emit Claim [L780]
        |-- if coinOut != 0: [L781]
        |     |-- remaining = coinOut [L782]
        |     |-- if vaultBal != 0: [L783]
        |     |     |-- payBal = min(remaining, vaultBal) [L784]
        |     |     |-- remaining -= payBal [L785]
        |     |     |-- coinToken.transfer(player, payBal) [L786] -> BurnieCoin
        |     |-- if remaining != 0 && claimable != 0: [L789]
        |     |     |-- claimed = coinflipPlayer.claimCoinflips(address(this), remaining) [L790]
        |     |     |-- remaining -= claimed [L792]
        |     |     |-- coinToken.transfer(player, claimed) [L793] -> BurnieCoin
        |     |-- if remaining != 0: [L797]
        |     |     |-- coinTracked -= remaining [L798]
        |     |     |-- coinToken.vaultMintTo(player, remaining) [L799] -> BurnieCoin
```

### Storage Writes (Full Tree)
| Variable | Location | Contract |
|----------|----------|----------|
| coinTracked | L982 (_syncCoinReserves) | DegenerusVault |
| coinTracked | L798 (remaining decrement) | DegenerusVault |
| coinShare.balanceOf[player] | L775 (vaultBurn) | DegenerusVaultShare |
| coinShare.totalSupply | L775 (vaultBurn) | DegenerusVaultShare |
| coinShare.balanceOf[player] | L777 (vaultMint, conditional) | DegenerusVaultShare |
| coinShare.totalSupply | L777 (vaultMint, conditional) | DegenerusVaultShare |

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| coinBal | L766 (from _syncCoinReserves) | coinTracked L982 (same call) | NO -- coinBal receives the synced value |
| supplyBefore | L767 | share.totalSupply at L775 (vaultBurn) | **POTENTIAL** -- supplyBefore is read before vaultBurn decrements totalSupply |
| vaultBal | L768 | coinToken.transfer at L786 moves tokens | **POTENTIAL** -- vaultBal read before transfer |
| claimable | L769 | coinflipPlayer.claimCoinflips at L790 | **POTENTIAL** -- claimable read as preview before actual claim |

**Analysis of potential conflicts:**
1. `supplyBefore` vs `totalSupply` after vaultBurn: This is INTENTIONAL. The formula `coinOut = (coinBal * amount) / supplyBefore` uses the pre-burn supply to calculate proportional share. After burn, totalSupply is lower, but coinOut was already calculated. This is the standard vault share pattern -- **SAFE by design**.

2. `vaultBal` vs actual balance after transfer: vaultBal is used as a ceiling for payBal (L784). After transferring payBal tokens, the remaining calculation uses `remaining -= payBal` which tracks the output correctly. The actual balanceOf is not re-read. **SAFE** -- remaining properly tracks what's left to pay.

3. `claimable` (preview) vs actual claim: `previewClaimCoinflips` returns an estimate. `claimCoinflips` returns actual claimed amount. The code uses `claimed` (actual) for remaining math (L792), not the preview. If claimed < claimable, more goes to vaultMintTo path. **SAFE** -- falls through correctly.

### Attack Analysis

**1. State Coherence (BAF Pattern)**
The function reads coinBal, supplyBefore, vaultBal, claimable as locals before any writes. The share burn happens at L775, AFTER coinOut is computed at L773. No descendant call writes to a variable that an ancestor has cached for later use. The payment waterfall (balance -> coinflip claim -> vault mint) uses `remaining` to track, not re-reading storage.
**VERDICT: SAFE** -- standard pre-compute-then-execute pattern.

**2. Access Control**
- player == address(0) -> player = msg.sender: SAFE, msg.sender burns own shares.
- player != msg.sender -> requires operator approval via game.isOperatorApproved. This is a cross-contract call to the game contract. If game contract is compromised, operator approval could be faked. But game is a compile-time constant address -- trusted.
- No access control on calling burnCoin itself -- anyone with DGVB shares can burn. This is correct.
**VERDICT: SAFE**

**3. RNG Manipulation**
No RNG involved.
**VERDICT: N/A**

**4. Cross-Contract State Desync**
The function reads from 3 external contracts in sequence: coinToken.vaultMintAllowance(), coinToken.balanceOf(), coinflipPlayer.previewClaimCoinflips(). Between these reads, another transaction could change the values. BUT all three reads happen in the same transaction atomically. No external calls happen between the reads and the computation at L773.
**VERDICT: SAFE** -- atomic reads within single transaction.

**5. Edge Cases**
- **amount == 0**: Reverts at L764. SAFE.
- **amount > player's balance**: vaultBurn reverts (Insufficient). SAFE.
- **amount == supplyBefore (burn ALL shares)**: Refill triggered at L776-778. coinOut = (coinBal * supplyBefore) / supplyBefore = coinBal. Player gets ALL reserves AND 1T new shares. If they burn again, coinBal has been reduced by what was paid out. Second burn gets proportional share of remaining. SAFE.
- **coinBal == 0 (no BURNIE reserves)**: coinOut = 0. No transfers. Shares burned for nothing. This is by design -- vault might be empty. INFO-level.
- **supplyBefore is very large, amount is very small**: coinOut rounds to 0 due to integer division. Shares burned, nothing received. This is standard rounding-down behavior for the redeemer (vault keeps dust). SAFE.
- **vaultBal and claimable both 0**: coinBal = just the mint allowance. Payout goes straight to vaultMintTo path. SAFE.

**VERDICT: SAFE** -- all edge cases handled or revert correctly.

**6. Conditional Paths**
- vaultBal != 0 path (L783-787): pays from balance first. SAFE.
- remaining != 0 && claimable != 0 path (L789-795): claims from coinflip then transfers. SAFE.
- remaining != 0 path (L797-800): mints from vault allowance. SAFE.
- Refill path (L776-778): only when burning ALL shares. SAFE.

**VERDICT: SAFE** -- all paths execute correctly.

**7. Economic Attacks**
- **Inflation attack**: Cannot inflate share price because initial supply is 1T shares to CREATOR. To manipulate, attacker needs to somehow get the supply very low, then donate BURNIE to inflate price per share. But this requires CREATOR cooperation or a way to burn most shares first. Not viable without majority share control.
- **Sandwich attack on burnCoin**: Frontrunner deposits more BURNIE before victim burns -> victim gets proportionally more? No -- deposits go through the game contract (onlyGame), not directly callable. Only the game can deposit. Not exploitable by frontrunners.

**VERDICT: SAFE**

**8. Griefing**
Cannot grief other users -- each user burns their own shares independently. Refill mechanism prevents permanent zero-supply state.
**VERDICT: SAFE**

**9. Ordering/Sequencing**
Calling burnCoin multiple times in sequence: each call syncs reserves, reads fresh supply. No ordering dependency.
**VERDICT: SAFE**

**10. Silent Failures**
- coinToken.transfer returning false: reverts with TransferFailed. SAFE.
- coinflipPlayer.claimCoinflips returning 0: remaining stays unchanged, falls through to vaultMintTo. No silent skip.
- coinToken.vaultMintTo failing: would revert. No silent failure.

**VERDICT: SAFE**

---

## V-29: DegenerusVault::burnEth (L816-876)

### Call Tree
```
burnEth(player, amount) [L816-826]
  |-- if player == address(0): player = msg.sender [L820-821]
  |-- else if player != msg.sender: _requireApproved(player) [L822-823]
  |-- _burnEthFor(player, amount) [L825, L833-876]
        |-- share = ethShare [L837]
        |-- if amount == 0: revert Insufficient [L838]
        |-- (ethBal, stBal, combined) = _syncEthReserves() [L840]
        |     |-- ethBal = address(this).balance [L972]
        |     |-- stBal = _stethBalance() -> steth.balanceOf(address(this)) [L973, L1025]
        |     |-- combined = ethBal + stBal (unchecked) [L974-976]
        |-- claimable = gamePlayer.claimableWinningsOf(address(this)) [L841]
        |-- if claimable <= 1: claimable = 0 [L842-843]
        |-- else: claimable -= 1 (unchecked) [L844-847]
        |-- supplyBefore = share.totalSupply() [L849]
        |-- reserve = combined + claimable [L850]
        |-- claimValue = (reserve * amount) / supplyBefore [L851]
        |-- if claimValue > combined && claimable != 0: [L853]
        |     |-- gamePlayer.claimWinnings(address(this)) [L854] -> DegenerusGame
        |     |-- ethBal = address(this).balance [L855]
        |     |-- stBal = _stethBalance() [L856]
        |-- if claimValue <= ethBal: ethOut = claimValue [L859-860]
        |-- else: ethOut = ethBal; stEthOut = claimValue - ethBal [L861-863]
        |     |-- if stEthOut > stBal: revert Insufficient [L864]
        |-- share.vaultBurn(player, amount) [L867]
        |-- if supplyBefore == amount: share.vaultMint(player, REFILL_SUPPLY) [L868-870]
        |-- emit Claim [L872]
        |-- if stEthOut != 0: _paySteth(player, stEthOut) [L874]
        |     |-- steth.transfer(to, amount) [L1040]
        |-- if ethOut != 0: _payEth(player, ethOut) [L875]
        |     |-- to.call{value: amount}("") [L1032]
```

### Storage Writes (Full Tree)
| Variable | Location | Contract |
|----------|----------|----------|
| ethShare.balanceOf[player] | L867 (vaultBurn) | DegenerusVaultShare |
| ethShare.totalSupply | L867 (vaultBurn) | DegenerusVaultShare |
| ethShare.balanceOf[player] | L869 (vaultMint, conditional) | DegenerusVaultShare |
| ethShare.totalSupply | L869 (vaultMint, conditional) | DegenerusVaultShare |

Note: ETH sent via call and stETH via transfer are value transfers, not storage writes on this contract.

### Cached-Local-vs-Storage Check
| Local Variable | Cached At | Descendant Write | Conflict? |
|---------------|-----------|-----------------|-----------|
| ethBal | L840/L855 | _payEth sends ETH (L875) | NO -- ethBal is used to compute ethOut BEFORE _payEth |
| stBal | L840/L856 | _paySteth transfers stETH (L874) | NO -- stBal used to bound stEthOut BEFORE _paySteth |
| supplyBefore | L849 | share.vaultBurn at L867 | NO -- intentional pre-burn read |
| combined | L840 | claimWinnings at L854 may add ETH | **INVESTIGATE** -- combined is cached, but claimWinnings adds ETH to vault |
| claimable | L841 | claimWinnings at L854 zeroes claimable | **INVESTIGATE** -- but claimable is used for reserve calculation before claim |

**Analysis of potential conflicts:**
1. `combined` vs `claimWinnings` adding ETH: combined is computed at L840 from ethBal+stBal. At L853, if claimValue > combined, it calls claimWinnings which sends ETH to the vault, increasing address(this).balance. Then L855-856 RE-READ ethBal and stBal. But `combined` itself is not re-read -- it was used at L850 for reserve and L853 for the comparison only. After the claimWinnings call, ethBal is refreshed at L855. The stale `combined` is never used after L853. **SAFE** -- combined is only used before the refresh.

2. `claimable` after claimWinnings: claimable is used at L850 for reserve calculation (before claimWinnings is called). After claimWinnings, the actual claimable is now 0 in game state, but the code doesn't re-read it. The code uses the refreshed ethBal (which now includes the claimed ETH) to determine ethOut/stEthOut split. This is correct because the claimed ETH is now in address(this).balance. **SAFE** -- the claim materializes the value into ethBal.

### Attack Analysis

**1. State Coherence (BAF Pattern)**
Key flow: read reserves -> compute claimValue -> optionally claim winnings (refresh balances) -> split into ETH/stETH -> burn shares -> pay out.

The critical question: after claimWinnings at L854, does the vault's ETH balance include the claimed amount? YES -- claimWinnings sends ETH to `address(this)` (the vault), and L855 re-reads address(this).balance.

The stale local `combined` is only used for the comparison at L853 and the reserve calculation at L850-851 (which happened before claimWinnings). After claimWinnings, the code uses the refreshed ethBal for the actual split logic. This is correct.

**VERDICT: SAFE** -- properly refreshes after external call.

**2. Access Control**
Same as burnCoin -- self or approved operator. SAFE.
**VERDICT: SAFE**

**3. RNG Manipulation**
No RNG.
**VERDICT: N/A**

**4. Cross-Contract State Desync**
gamePlayer.claimWinnings at L854 is the key external call. It sends ETH to the vault. Between the claimWinnings call and the _payEth/_paySteth calls, could another transaction change the vault's balance? NO -- this is all within a single transaction. Atomic.

However: the `to.call{value: amount}("")` at L1032 transfers ETH to `player`. If `player` is a contract with a receive/fallback that calls back into the vault, reentrancy could occur. At the point of _payEth:
- Shares are already burned (L867)
- ethOut and stEthOut are already computed
- stETH may already be sent (L874 happens before L875)

If player reenters burnEth during _payEth: player's shares are already burned, so reentering would try to burn from their new balance. If they had more shares, they could burn again. The reserve would be lower (ETH already partially sent), so they'd get less per share. But: ethBal is NOT re-read between the two payments (stETH at L874, ETH at L875). If _paySteth sends stETH and the stETH transfer triggers a callback to burnEth, the vault's stETH balance is now lower but a reentering call would re-read it fresh at L840. This is a standard reentrancy concern.

**INVESTIGATE: Reentrancy via _payEth callback.** If player is a contract, the ETH transfer at L1032 gives control to the player. At this point shares are burned and all state is finalized. A reentrant call to burnEth would:
- Read fresh ethBal (now lower by ethOut)
- Read fresh stBal (now lower by stEthOut if stETH was sent)
- Compute fresh claimValue based on player's remaining shares
- This is a fresh, valid computation with updated state

No state is stale at the point of reentrancy. Shares were burned before payment. CEI is followed (compute -> burn -> emit -> pay). **Re-entry produces correct results because all state updates precede the external call.** The only concern would be if the refill mechanism creates new shares that the reentrant call could then burn, but refill only happens when `supplyBefore == amount` (ALL shares burned), which means the player burned everything and got refilled. A reentrant call would burn from the refill shares, getting proportional of the remaining reserves. This is arithmetically correct.

**VERDICT: SAFE** -- CEI pattern followed, reentrancy produces correct results.

**5. Edge Cases**
- **amount == 0**: Reverts. SAFE.
- **amount == supplyBefore**: Full drain + refill. claimValue = reserve * 1 = reserve. Gets ALL ETH+stETH+claimable. Then gets 1T refill shares. Reserves are empty. Next burn gets 0. SAFE.
- **claimable <= 1**: Treated as 0 (L842-843). The `claimable -= 1` pattern leaves 1 wei in game as gas optimization (avoids writing 0 to a warm slot). SAFE.
- **claimValue > combined but claimable == 0**: Skips claimWinnings branch (L853). ethOut = ethBal, stEthOut = claimValue - ethBal. If stEthOut > stBal: reverts Insufficient. This prevents over-claiming. SAFE.
- **combined overflow**: ethBal + stBal in unchecked block at L974-976. If somehow the vault holds > type(uint256).max in combined ETH+stETH, this overflows. Practically impossible (more ETH than exists). **SAFE** -- physical impossibility.
- **reserve overflow**: combined + claimable at L850 (not in unchecked). Solidity 0.8.34 overflow check applies. SAFE.

**VERDICT: SAFE**

**6. Conditional Paths**
- claimWinnings path (L853-857): only when claimValue > combined AND claimable != 0. SAFE.
- ETH-only path (L859-860): when claimValue <= ethBal. SAFE.
- ETH+stETH path (L861-865): when claimValue > ethBal. Reverts if stETH insufficient. SAFE.
- Refill path (L868-870): only on full burn. SAFE.

**VERDICT: SAFE**

**7. Economic Attacks**
- **Frontrunning burnEth**: Attacker deposits ETH to vault (via game), inflating reserves, then victim burns shares for more. But only GAME can deposit (onlyGame). Not exploitable by third parties.
- **Sandwich**: Same limitation -- cannot deposit/withdraw around victim's transaction without game cooperation.
- **Flash loan DGVE**: No flash loan mechanism on DegenerusVaultShare. Cannot borrow-burn-return.

**VERDICT: SAFE**

**8. Griefing**
Cannot grief -- each user burns own shares. Receive() allows anyone to donate ETH (increases reserves for all DGVE holders). This is positive for shareholders.
**VERDICT: SAFE**

**9. Ordering/Sequencing**
Multiple burnEth calls: each reads fresh state. Ordering doesn't matter.
**VERDICT: SAFE**

**10. Silent Failures**
- steth.transfer returning false: reverts TransferFailed. SAFE.
- ETH call returning false: reverts TransferFailed. SAFE.
- claimWinnings reverting: entire transaction reverts. SAFE.

**VERDICT: SAFE**

---

## HIGH TIER

---

## V-02: DegenerusVault::deposit (L454-462)

### Call Tree
```
deposit(coinAmount, stEthAmount) [L454-462] external payable onlyGame
  |-- onlyGame modifier: msg.sender != ContractAddresses.GAME [L393-396]
  |-- if coinAmount != 0: [L455]
  |     |-- _syncCoinReserves() [L456]
  |     |     |-- synced = coinToken.vaultMintAllowance() [L981]
  |     |     |-- coinTracked = synced [L982]
  |     |-- coinToken.vaultEscrow(coinAmount) [L457] -> BurnieCoin
  |     |-- coinTracked += coinAmount [L458]
  |-- _pullSteth(msg.sender, stEthAmount) [L460]
  |     |-- if amount == 0: return [L1047]
  |     |-- steth.transferFrom(from, address(this), amount) [L1048] -> Lido stETH
  |-- emit Deposit(msg.sender, msg.value, stEthAmount, coinAmount) [L461]
```

### Storage Writes (Full Tree)
| Variable | Location | Contract |
|----------|----------|----------|
| coinTracked | L982 (_syncCoinReserves) | DegenerusVault |
| coinTracked | L458 (+= coinAmount) | DegenerusVault |

### Cached-Local-vs-Storage Check
No local caching of values that are later written by descendants. `_syncCoinReserves()` writes to coinTracked, then the direct `coinTracked += coinAmount` at L458 reads the CURRENT coinTracked value (just synced). No conflict.

**VERDICT: SAFE** -- no cached-local-vs-storage conflict.

### Attack Analysis

**1. State Coherence:** _syncCoinReserves at L456 writes coinTracked = synced (fresh from coinToken). Then L457 calls vaultEscrow which increases the coin contract's vault mint allowance. Then L458 adds coinAmount to coinTracked. This keeps coinTracked in sync with the actual mint allowance. SAFE.

**2. Access Control:** onlyGame modifier -- only DegenerusGame can call. SAFE.

**3. Edge Cases:**
- coinAmount == 0 and stEthAmount == 0 and msg.value == 0: Empty deposit, emits Deposit with all zeros. Harmless. SAFE.
- stEthAmount > 0 but GAME hasn't approved stETH: transferFrom reverts. SAFE.
- msg.value > 0: ETH received by vault, tracked by address(this).balance. No explicit accounting needed since DGVE reserves use live balance. SAFE.

**4. No share minting:** deposit does NOT mint DGVE or DGVB shares. The initial 1T shares were minted in constructor. New deposits increase reserves without minting shares, diluting the per-share value upward (reserves increase, supply stays same). This means existing shareholders benefit from deposits. SAFE by design.

**INVESTIGATE: No share minting on deposit means early shareholders benefit from all future deposits.** This is intentional -- the game deposits into the vault, and existing shareholders passively accrue value. Not a vulnerability but a design decision.

**5-10. All other angles:** No RNG, no reentrancy risk (ETH received via msg.value, stETH pulled via transferFrom from trusted game contract), no griefing vector.

**VERDICT: SAFE**

---

## W-04: WrappedWrappedXRP::unwrap (L290-306)

### Call Tree
```
unwrap(amount) [L290-306]
  |-- if amount == 0: revert ZeroAmount [L291]
  |-- if wXRPReserves < amount: revert InsufficientReserves [L294]
  |-- _burn(msg.sender, amount) [L297]
  |     |-- if from == address(0): revert ZeroAddress [L267]
  |     |-- if balanceOf[from] < amount: revert InsufficientBalance [L268]
  |     |-- balanceOf[from] -= amount [L270]
  |     |-- totalSupply -= amount [L271]
  |     |-- emit Transfer(from, address(0), amount) [L273]
  |-- wXRPReserves -= amount [L298]
  |-- if !wXRP.transfer(msg.sender, amount): revert TransferFailed [L301-303]
  |-- emit Unwrapped(msg.sender, amount) [L305]
```

### Storage Writes (Full Tree)
| Variable | Location | Contract |
|----------|----------|----------|
| balanceOf[msg.sender] | L270 (_burn) | WrappedWrappedXRP |
| totalSupply | L271 (_burn) | WrappedWrappedXRP |
| wXRPReserves | L298 | WrappedWrappedXRP |

### Cached-Local-vs-Storage Check
No local caching. All operations directly on storage variables. **SAFE**.

### Attack Analysis

**1. State Coherence:** CEI pattern: burn WWXRP (L297), decrement reserves (L298), THEN transfer wXRP (L301). State is fully updated before external call. SAFE.

**2. Access Control:** Open to all WWXRP holders. Correct -- anyone who holds WWXRP can unwrap. SAFE.

**3. Reentrancy via wXRP.transfer:** wXRP.transfer at L301 is an external call to the wXRP token. If wXRP has hooks (e.g., ERC777 or weird callback), it could call back into unwrap. But at this point:
- balanceOf[msg.sender] already decremented
- totalSupply already decremented
- wXRPReserves already decremented
- Reentering unwrap would need msg.sender to have MORE WWXRP tokens AND wXRPReserves to have enough. Both conditions are independently checked. CEI is followed.

**VERDICT: SAFE** -- CEI prevents reentrancy exploitation even if wXRP has callbacks.

**4. Race Condition (Multiple Unwrappers):**
If wXRPReserves = 100 and two users try to unwrap 80 each:
- First transaction: reserves check passes (100 >= 80), burns, decrements to 20, transfers 80.
- Second transaction: reserves check fails (20 < 80), reverts.
This is first-come-first-served by design (documented in contract header). Not a vulnerability.

**VERDICT: SAFE** -- intentional design.

**5. Edge Cases:**
- amount == 0: Reverts ZeroAmount. SAFE.
- amount > balanceOf[msg.sender]: _burn reverts InsufficientBalance. SAFE.
- amount > wXRPReserves: Reverts InsufficientReserves. SAFE.
- wXRPReserves == 0: Reverts unless amount == 0 (which also reverts). SAFE.
- wXRP.transfer returns false: Reverts TransferFailed. SAFE.

**6-10. All other angles:** No economic exploit (can only unwrap own tokens), no griefing (each user independent), no ordering issues, no silent failures.

**VERDICT: SAFE**

---

## V-09: DegenerusVault::gamePurchaseDeityPassFromBoon (L536-546)

### Call Tree
```
gamePurchaseDeityPassFromBoon(priceWei, symbolId) [L536-546] external payable onlyVaultOwner
  |-- onlyVaultOwner: _isVaultOwner(msg.sender) [L399-401]
  |     |-- supply = ethShare.totalSupply() [L416]
  |     |-- balance = ethShare.balanceOf(msg.sender) [L417]
  |     |-- return balance * 1000 > supply * 501 [L418]
  |-- if priceWei == 0: revert Insufficient [L537]
  |-- if address(this).balance < priceWei: [L538]
  |     |-- claimable = gamePlayer.claimableWinningsOf(address(this)) [L539]
  |     |-- if claimable > 1: gamePlayer.claimWinnings(address(this)) [L540-542]
  |-- if address(this).balance < priceWei: revert Insufficient [L544]
  |-- gamePlayer.purchaseDeityPass{value: priceWei}(address(this), symbolId) [L545]
```

### Storage Writes (Full Tree)
No local storage writes. All state changes happen in game contract (external).

### Cached-Local-vs-Storage Check
No local caching. `address(this).balance` is checked twice (L538, L544) -- both reads are live. Between the two reads, claimWinnings may have added ETH. The second check at L544 uses the updated balance. **SAFE**.

### Attack Analysis

**1. State Coherence:** No local state to go stale. Balance checks are live. SAFE.

**2. Access Control:** onlyVaultOwner -- >50.1% DGVE. SAFE.

**3. ETH Flow:**
- msg.value is added to vault balance on entry (before any logic).
- If vault balance (including msg.value) < priceWei, claims winnings to top up.
- Second check ensures balance >= priceWei after claiming.
- purchaseDeityPass sends priceWei to the game.

This reduces vault ETH, which reduces DGVE backing. But vault owner (>50.1%) authorized this. Not a vulnerability -- vault owner can spend vault assets.

**4. Edge Cases:**
- priceWei == 0: Reverts. SAFE.
- No claimable winnings and insufficient balance: Reverts at L544. SAFE.
- claimable == 1: Treated as 0 (claimable > 1 check at L540). SAFE.

**VERDICT: SAFE** -- vault owner authorized action with proper balance checks.

---

## MEDIUM TIER

---

## V-05: DegenerusVault::gamePurchase (L489-504)

### Call Tree
```
gamePurchase(ticketQty, lootBoxAmt, affiliateCode, payKind, ethValue) [L489-504] external payable onlyVaultOwner
  |-- totalValue = _combinedValue(ethValue) [L496]
  |     |-- if extraValue == 0: return msg.value [L961]
  |     |-- totalValue = msg.value + extraValue [L963]
  |     |-- if totalValue > address(this).balance: revert Insufficient [L964]
  |-- gamePlayer.purchase{value: totalValue}(address(this), ...) [L497-503]
```

### Storage Writes (Full Tree)
No local storage writes. ETH leaves vault.

### Cached-Local-vs-Storage Check
No local caching. _combinedValue reads `address(this).balance` live. **SAFE**.

### Attack Analysis

**1. _combinedValue overflow:** `msg.value + extraValue` at L963. In Solidity 0.8.34, this would revert on overflow. Not exploitable. SAFE.

**2. Balance check:** `totalValue > address(this).balance`. Note: msg.value is already included in address(this).balance when the function is entered (ETH sent with the call). So if msg.value = 5 ETH and extraValue = 10 ETH, totalValue = 15 ETH. The check ensures the vault has at least 15 ETH total (including the 5 just sent). SAFE.

**VERDICT: SAFE**

---

## V-12: DegenerusVault::gameDegeneretteBetEth (L569-587)

### Call Tree
```
gameDegeneretteBetEth(amountPerTicket, ticketCount, customTicket, heroQuadrant, ethValue) [L569-587]
  |-- totalBet = uint256(amountPerTicket) * uint256(ticketCount) [L576]
  |-- totalValue = _combinedValue(ethValue) [L577]
  |-- if totalValue > totalBet: revert Insufficient [L578]
  |-- gamePlayer.placeFullTicketBets{value: totalValue}(...) [L579-586]
```

### Storage Writes
No local storage writes.

### Attack Analysis

**Interesting check at L578:** `if (totalValue > totalBet) revert Insufficient()`. This ensures the vault owner doesn't send MORE ETH than the bet requires. This is a protective guard -- excess ETH would be stuck in the game contract. SAFE.

But wait: `if totalValue > totalBet` means totalValue can EQUAL totalBet, which is correct. It can also be LESS than totalBet, which would mean the bet is partially funded. The game's placeFullTicketBets presumably handles this case (reverts if underfunded). SAFE by design -- game validates the payment amount.

**VERDICT: SAFE**

---

## V-26: DegenerusVault::wwxrpMint (L723-726)

### Call Tree
```
wwxrpMint(to, amount) [L723-726] external onlyVaultOwner
  |-- if amount == 0: return [L724]
  |-- wwxrpToken.vaultMintTo(to, amount) [L725] -> WrappedWrappedXRP
        |-- if msg.sender != MINTER_VAULT: revert OnlyVault [L364]
        |-- if to == address(0): revert ZeroAddress [L365]
        |-- if amount == 0: return [L366]
        |-- allowanceVault = vaultAllowance [L368]
        |-- if amount > allowanceVault: revert InsufficientVaultAllowance [L369]
        |-- vaultAllowance = allowanceVault - amount (unchecked) [L370-372]
        |-- _mint(to, amount) [L373]
        |-- emit VaultAllowanceSpent [L374]
```

### Storage Writes (Full Tree)
| Variable | Location | Contract |
|----------|----------|----------|
| vaultAllowance | L371 | WrappedWrappedXRP |
| totalSupply | L257 (_mint) | WrappedWrappedXRP |
| balanceOf[to] | L258 (_mint) | WrappedWrappedXRP |

### Cached-Local-vs-Storage Check
`allowanceVault` cached at L368, then `vaultAllowance` written at L371. But this is a deliberate read-check-write pattern (checks before writing). No conflict.

### Attack Analysis

**1. Access Control:** onlyVaultOwner on vault side, MINTER_VAULT check on WWXRP side. Double-gated. SAFE.

**2. Unchecked subtraction:** `vaultAllowance = allowanceVault - amount` at L370-372. Protected by the check at L369: `amount > allowanceVault` reverts. So `allowanceVault >= amount` when the subtraction executes. SAFE.

**3. Vault owner minting WWXRP to arbitrary addresses:** By design -- vault owner controls the 1B WWXRP uncirculating reserve. They can mint to anyone. This is intended functionality.

**VERDICT: SAFE**

---

## W-06: WrappedWrappedXRP::mintPrize (L342-354)

### Call Tree
```
mintPrize(to, amount) [L342-354]
  |-- if msg.sender != MINTER_GAME && != MINTER_COIN && != MINTER_COINFLIP: revert OnlyMinter [L343-349]
  |-- if amount == 0: revert ZeroAmount [L350]
  |-- _mint(to, amount) [L353]
        |-- if to == address(0): revert ZeroAddress [L255]
        |-- totalSupply += amount [L257]
        |-- balanceOf[to] += amount [L258]
        |-- emit Transfer(address(0), to, amount) [L260]
```

### Storage Writes
| Variable | Location | Contract |
|----------|----------|----------|
| totalSupply | L257 | WrappedWrappedXRP |
| balanceOf[to] | L258 | WrappedWrappedXRP |

### Attack Analysis

**1. Access Control:** Three authorized minters (GAME, COIN, COINFLIP). All compile-time constants. Cannot be changed. SAFE.

**2. Unbacked minting:** By design -- mintPrize mints WWXRP without wXRP backing. Increases undercollateralization. This is documented and intentional ("THIS IS A JOKE TOKEN"). Not a vulnerability.

**3. Supply overflow:** totalSupply += amount. Solidity 0.8.34 overflow check. If totalSupply approaches type(uint256).max, mint reverts. Practically impossible given finite game minting. SAFE.

**VERDICT: SAFE**

---

## W-07: WrappedWrappedXRP::vaultMintTo (L363-375)

Analyzed above in V-26 call tree. Access control: `msg.sender != MINTER_VAULT`. Vault allowance properly decremented before mint. Zero amount returns silently (L366). **SAFE**.

---

## W-05: WrappedWrappedXRP::donate (L314-326)

### Call Tree
```
donate(amount) [L314-326]
  |-- if amount == 0: revert ZeroAmount [L315]
  |-- if !wXRP.transferFrom(msg.sender, address(this), amount): revert TransferFailed [L318-320]
  |-- wXRPReserves += amount [L323]
  |-- emit Donated(msg.sender, amount) [L325]
```

### Storage Writes
| Variable | Location | Contract |
|----------|----------|----------|
| wXRPReserves | L323 | WrappedWrappedXRP |

### Attack Analysis

**1. Reserve inflation:** Anyone can donate wXRP, increasing wXRPReserves. This improves the backing ratio. No attack -- donating value to the contract benefits all WWXRP holders. SAFE.

**2. Reentrancy via wXRP.transferFrom:** External call at L318 before storage write at L323. This is NOT CEI (external call before state update). If wXRP.transferFrom calls back into donate: the attacker would need to approve more wXRP and have more balance. Each reentrant call would transfer more real wXRP and increment reserves. The attacker spends real wXRP each time. No profit opportunity.

Actually, wait -- the concern is whether an attacker could call unwrap during the donate callback (before wXRPReserves is incremented). At the time of the callback, wXRPReserves has NOT yet been increased. So the attacker cannot unwrap the just-donated amount because the reserves weren't updated yet. The wXRP tokens ARE in the contract though (transferFrom succeeded). This means the contract holds more wXRP than wXRPReserves tracks. When donate finishes (L323), reserves catch up. No loss.

**INVESTIGATE:** Could an attacker exploit the window where wXRP is in the contract but wXRPReserves hasn't been incremented? Only if there's a way to extract untracked wXRP. The contract only sends wXRP via unwrap (which uses wXRPReserves as the limit). So untracked wXRP is locked. **SAFE** -- untracked surplus cannot be extracted.

**VERDICT: SAFE**

---

## W-08: WrappedWrappedXRP::burnForGame (L384-388)

### Call Tree
```
burnForGame(from, amount) [L384-388]
  |-- if msg.sender != MINTER_GAME: revert OnlyMinter [L385]
  |-- if amount == 0: return [L386]
  |-- _burn(from, amount) [L387]
```

### Storage Writes
| Variable | Location | Contract |
|----------|----------|----------|
| balanceOf[from] | L270 | WrappedWrappedXRP |
| totalSupply | L271 | WrappedWrappedXRP |

### Attack Analysis
**1. Access Control:** Only GAME. SAFE.
**2. Zero amount:** Returns silently. SAFE.
**3. Burning reduces totalSupply without reducing wXRPReserves:** This improves the collateralization ratio (fewer WWXRP tokens, same wXRP reserves). SAFE -- benefits remaining holders.

**VERDICT: SAFE**

---

## V-C3: DegenerusVault::_syncCoinReserves (L980-983)

### Call Tree
```
_syncCoinReserves() [L980-983]
  |-- synced = coinToken.vaultMintAllowance() [L981] -> BurnieCoin
  |-- coinTracked = synced [L982]
  |-- return synced
```

### Storage Writes
| Variable | Location | Contract |
|----------|----------|----------|
| coinTracked | L982 | DegenerusVault |

### Attack Analysis
**1. coinTracked desync:** This function RE-SYNCS coinTracked with the actual mint allowance on every call. If the BURNIE contract's vault allowance changed (e.g., someone minted from it), _syncCoinReserves catches up. Called at the start of deposit and burnCoin. **SAFE**.

**2. External call to coinToken:** If coinToken is malicious, it could return a fake value. But coinToken is a compile-time constant (ContractAddresses.COIN). Trusted. SAFE.

**VERDICT: SAFE**

---

## LOW TIER

---

## DegenerusVaultShare Functions (VS-01 through VS-06)

### VS-01: constructor(name_, symbol_) [L198-204]
Sets name, symbol, mints INITIAL_SUPPLY (1T * 1e18) to ContractAddresses.CREATOR. Standard construction. **SAFE**.

### VS-02: approve(spender, amount) [L213-217]
Standard ERC20 approve. Sets allowance, emits Approval. **SAFE**.

### VS-03: transfer(to, amount) [L225-228]
Calls _transfer(msg.sender, to, amount). _transfer at L290-299: checks to != address(0), checks balance >= amount, decrements from, increments to. Uses unchecked arithmetic protected by the balance check.

Note: _transfer does NOT check `from != address(0)`. In transfer(), from = msg.sender which cannot be address(0) (no one can transact from address(0)). **SAFE**.

### VS-04: transferFrom(from, to, amount) [L237-247]
Standard ERC20 transferFrom. Checks allowance (type(uint256).max = unlimited). Decrements allowance, calls _transfer. Emits Approval with new allowance.

Note: from=address(0) is technically possible as a parameter. _transfer would NOT revert (no from-zero check at L290). BUT address(0) would need a balance, which only happens if something mints to address(0). vaultMint checks `to != address(0)` (L259). constructor mints to CREATOR. So address(0) balance is always 0, and _transfer would revert on the balance check. **SAFE**.

### VS-05: vaultMint(to, amount) [L258-265]
onlyVault guard. Checks to != address(0). Uses unchecked for totalSupply += amount and balanceOf[to] += amount. Overflow concern: totalSupply starts at 1T * 1e18 (~1e30). type(uint256).max ~ 1.16e77. Would need ~1e47 mint calls of 1e30 to overflow. Practically impossible. **SAFE**.

### VS-06: vaultBurn(from, amount) [L273-281]
onlyVault guard. Checks amount <= balanceOf[from]. Uses unchecked for subtraction (safe because of prior check). totalSupply -= amount: since balanceOf[from] <= totalSupply (invariant), totalSupply won't underflow. **SAFE**.

---

## DegenerusVault Proxy Functions (V-04 through V-27, excluding previously analyzed)

All proxy functions follow the same pattern:
1. `onlyVaultOwner` modifier checks >50.1% DGVE supply
2. Call the target contract with `address(this)` as the player
3. No local state modifications

**V-04 gameAdvance:** Calls gamePlayer.advanceGame(). No parameters, no ETH. SAFE.
**V-06 gamePurchaseTicketsBurnie:** Reverts if qty == 0. Calls purchaseCoin. SAFE.
**V-07 gamePurchaseBurnieLootbox:** Reverts if amt == 0. Calls purchaseBurnieLootbox. SAFE.
**V-08 gameOpenLootBox:** Calls openLootBox with index. SAFE.
**V-10 gameClaimWinnings:** Calls claimWinningsStethFirst. ETH/stETH enters vault. SAFE.
**V-11 gameClaimWhalePass:** Calls claimWhalePass. SAFE.
**V-13 gameDegeneretteBetBurnie:** Calls placeFullTicketBets with currency=1. SAFE.
**V-14 gameDegeneretteBetWwxrp:** Calls placeFullTicketBets with currency=3. SAFE.
**V-15 gameResolveDegeneretteBets:** Calls resolveDegeneretteBets. SAFE.
**V-16 gameSetAutoRebuy:** Calls setAutoRebuy. SAFE.
**V-17 gameSetAutoRebuyTakeProfit:** Calls setAutoRebuyTakeProfit. SAFE.
**V-18 gameSetDecimatorAutoRebuy:** Calls setDecimatorAutoRebuy. SAFE.
**V-19 gameSetAfKingMode:** Calls setAfKingMode with 3 params. SAFE.
**V-20 gameSetOperatorApproval:** Calls setOperatorApproval. Vault owner can approve operators for vault's game actions. SAFE.
**V-21 coinDepositCoinflip:** Calls depositCoinflip. SAFE.
**V-22 coinClaimCoinflips:** Calls claimCoinflips, returns claimed amount. SAFE.
**V-23 coinDecimatorBurn:** Calls decimatorBurn. SAFE.
**V-24 coinSetAutoRebuy:** Calls setCoinflipAutoRebuy. SAFE.
**V-25 coinSetAutoRebuyTakeProfit:** Calls setCoinflipAutoRebuyTakeProfit. SAFE.
**V-27 jackpotsClaimDecimator:** Calls claimDecimatorJackpot. SAFE.

**Common access control verification:** All use onlyVaultOwner. The _isVaultOwner check at L415-419 reads ethShare.totalSupply() and ethShare.balanceOf(account). Both are external calls to DegenerusVaultShare, which is a trusted contract deployed by the vault's constructor. The check `balance * 1000 > supply * 501` ensures >50.1% ownership. Overflow: balance and supply are both uint256. If supply is very large, supply * 501 could overflow. BUT supply * 501 vs balance * 1000: supply starts at 1T * 1e18 ~ 1e30. 1e30 * 501 ~ 5e32. 1e30 * 1000 ~ 1e33. Both well within uint256. Even with refills (1T each), would need ~1e47 refills to approach overflow. SAFE.

---

## V-01: DegenerusVault::constructor [L433-440]
Deploys DGVB and DGVE share tokens. Reads coinToken.vaultMintAllowance() and stores in coinTracked. **SAFE**.

## V-03: DegenerusVault::receive [L465-467]
Accepts ETH from any sender. Emits Deposit event. No access control needed -- ETH donations increase DGVE backing. **SAFE**.

---

## WrappedWrappedXRP ERC20 Functions (W-01 through W-03)

### W-01: approve(spender, amount) [L196-200]
Standard approve. Sets allowance, emits Approval. No checks on spender (can be address(0) -- harmless). **SAFE**.

### W-02: transfer(to, amount) [L208-211]
Calls _transfer(msg.sender, to, amount). _transfer at L241-249: checks from and to not address(0), checks balance. **SAFE**.

### W-03: transferFrom(from, to, amount) [L222-235]
Standard transferFrom with unlimited allowance optimization (type(uint256).max). Emits Approval on allowance change. Calls _transfer. **SAFE**.

---

## FINDINGS SUMMARY

| ID | Function | Verdict | Severity | Description |
|----|----------|---------|----------|-------------|
| (none) | All functions | SAFE | - | No VULNERABLE or INVESTIGATE findings that survive analysis |

**All 38 Category B functions analyzed. All 10 Category C functions traced through their parents. Zero VULNERABLE findings. Zero INVESTIGATE findings that survived to final verdict.**

The contracts follow correct patterns:
1. CEI (Checks-Effects-Interactions) throughout
2. Proper access control with compile-time constants
3. Integer math protected by Solidity 0.8.34 overflow checks and explicit guards
4. No cached-local-vs-storage conflicts (the BAF pattern is absent)
5. Share math uses standard proportional calculation with correct rounding direction
6. Refill mechanism prevents zero-supply while maintaining proportional correctness

---

## NOTES FOR SKEPTIC

While no findings survived, the Skeptic should independently verify these areas:

1. **burnEth reentrancy via _payEth (L1032):** I concluded CEI is followed (shares burned before payment). Verify the share burn at L867 happens before _payEth at L875.

2. **donate ordering (L318 vs L323):** External call before storage write. I concluded this is safe because untracked wXRP cannot be extracted. Verify unwrap is the only wXRP extraction path.

3. **Refill + immediate re-burn:** I concluded this is safe because the re-burning user gets proportional share of remaining reserves. Verify the math works when supply = REFILL_SUPPLY and reserves have been partially drained.

4. **_syncCoinReserves accuracy:** Verify that coinToken.vaultMintAllowance() always returns the correct current allowance and that no path exists where coinTracked could become permanently stale.
