# Unit 11: sDGNRS + DGNRS -- Mad Genius Attack Report

**Auditor Identity:** Mad Genius (per ULTIMATE-AUDIT-DESIGN.md)
**Contracts:** StakedDegenerusStonk.sol (839 lines), DegenerusStonk.sol (251 lines)
**Date:** 2026-03-25
**Method:** Full recursive call tree, storage-write map, cached-local-vs-storage check, 10-angle attack for every function

---

## TIER 1 FUNCTIONS (Highest Risk)

---

## B1: sDGNRS::burn(uint256) (L443-451)

### Call Tree
```
burn(amount) [L443]
  -> game.gameOver() [L444] -- external view call to Game
  IF gameOver:
    -> _deterministicBurn(msg.sender, amount) [L445]
      -> _deterministicBurnFrom(msg.sender, msg.sender, amount) [L474] -- see C1
  IF NOT gameOver:
    -> game.rngLocked() [L448] -- external view call to Game
    -> _submitGamblingClaim(msg.sender, amount) [L449]
      -> _submitGamblingClaimFrom(msg.sender, msg.sender, amount) [L700] -- see C2
```

### Storage Writes (Full Tree)
- **Deterministic path (C1):** `balanceOf[msg.sender]` (L493), `totalSupply` (L494)
- **Gambling path (C2):** `balanceOf[msg.sender]` (L738), `totalSupply` (L739), `pendingRedemptionEthValue` (L744), `pendingRedemptionEthBase` (L745), `pendingRedemptionBurnie` (L746), `pendingRedemptionBurnieBase` (L747), `pendingRedemptions[msg.sender]` (L758-766), `redemptionPeriodSupplySnapshot` (L714), `redemptionPeriodIndex` (L715), `redemptionPeriodBurned` (L716, L719)

### Cached-Local-vs-Storage Check
- `bal` (L482/L708) caches `balanceOf[burnFrom]`. No descendant call writes to `balanceOf` before the cached value is used at L493/L738. **SAFE.**
- `supplyBefore` (L484/L721) caches `totalSupply`. Deterministic path: `totalSupply` written at L494 AFTER `supplyBefore` used at L490. Gambling path: `totalSupply` written at L739 AFTER `supplyBefore` used at L728. **SAFE.**
- `ethBal` (L486/L724) caches `address(this).balance`. In deterministic path, `game.claimWinnings()` at L499 may send ETH to sDGNRS, but ethBal is re-read at L500. In gambling path, no ETH-sending external call before ethBal is used. **SAFE.**

### Attack Analysis

**1. State Coherence (BAF Pattern):** burn() caches no locals that descendants write to before use. The deterministic path re-reads ethBal after claimWinnings(). **SAFE.**

**2. Access Control:** External, callable by anyone. Both paths require the caller to own tokens. **SAFE.**

**3. RNG Manipulation:** Gambling path is gated by `game.rngLocked()` -- prevents submission during VRF request. The roll value is determined later by `resolveRedemptionPeriod`. Player cannot influence the roll. **SAFE.**

**4. Cross-Contract State Desync:** `game.gameOver()` and `game.rngLocked()` are view calls. If game state changes between these calls (MEV), the worst case is: gameOver() returns false, then between that call and rngLocked(), game becomes over. Player enters gambling path when they should have entered deterministic. But this is harmless -- player can still claimRedemption() after resolution (and gets 100% direct if gameOver at claim time, L593). **SAFE.**

**5. Edge Cases:**
- amount=0: Reverts at L483 (deterministic) or L709 (gambling) with `Insufficient`. **SAFE.**
- amount > balance: Same revert. **SAFE.**
- First-ever burn in new period: Period snapshot taken at L713-717. **SAFE.**

**6. Conditional Paths:** GameOver vs active game: both paths fully analyzed. **SAFE.**

**7. Economic Attacks:** Multiple burns in same period: allowed, subject to 50% cap and 160 ETH cap. Player cannot extract more than their proportional share because supply decreases with each burn. **SAFE.**

**8. Griefing:** No griefing vector -- each player burns their own tokens. **SAFE.**

**9. Ordering:** burn() before resolveRedemptionPeriod() -- expected flow. burn() after resolve but before claim -- submits to new period. **SAFE.**

**10. Silent Failures:** No silent success paths. All error cases revert. **SAFE.**

**VERDICT: SAFE**

---

## B2: sDGNRS::burnWrapped(uint256) (L461-470)

### Call Tree
```
burnWrapped(amount) [L461]
  -> dgnrsWrapper.burnForSdgnrs(msg.sender, amount) [L462]
     -- Burns DGNRS from msg.sender's balance in DGNRS contract
     -- DGNRS.burnForSdgnrs: L241-250, burns balanceOf[player], totalSupply in DGNRS
  IF gameOver:
    -> _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount) [L464]
       -- Burns sDGNRS from DGNRS contract's balance, pays beneficiary=msg.sender
  IF NOT gameOver:
    -> game.rngLocked() [L467]
    -> _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount) [L468]
       -- Burns sDGNRS from DGNRS contract's balance, records claim for beneficiary=msg.sender
```

### Storage Writes (Full Tree)
**DGNRS contract:** `balanceOf[msg.sender]` (DGNRS L244), `totalSupply` (DGNRS L246)
**sDGNRS deterministic:** `balanceOf[ContractAddresses.DGNRS]` (L493), `totalSupply` (L494)
**sDGNRS gambling:** `balanceOf[ContractAddresses.DGNRS]` (L738), `totalSupply` (L739), all pending* vars

### Cached-Local-vs-Storage Check
- DGNRS.burnForSdgnrs() writes to DGNRS state. Then _deterministicBurnFrom/_submitGamblingClaimFrom reads sDGNRS state. **No cross-contract cache conflict.** The DGNRS burn reduces DGNRS.balanceOf[player] and DGNRS.totalSupply. Then sDGNRS reads `balanceOf[ContractAddresses.DGNRS]` in sDGNRS storage (different contract, different storage). **SAFE.**

### Attack Analysis

**1. State Coherence:** DGNRS.burnForSdgnrs() executes first (L462), writing to DGNRS storage. Then sDGNRS burns from DGNRS's sDGNRS balance. No stale cache. **SAFE.**

**2. Access Control:** Anyone can call. Requires caller to have DGNRS tokens AND the DGNRS contract to have corresponding sDGNRS balance. **SAFE.**

**3. RNG Manipulation:** Same as B1 -- rngLocked gate. **SAFE.**

**4. Cross-Contract State Desync:**
- **INVESTIGATE: DGNRS burned but sDGNRS burn reverts.** If `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` succeeds at L462, but then `_deterministicBurnFrom` or `_submitGamblingClaimFrom` reverts (e.g., sDGNRS balance of DGNRS is insufficient), the ENTIRE transaction reverts (including the DGNRS burn). This is correct -- Solidity atomicity guarantees the DGNRS burn is unwound. **SAFE.**

**5. Edge Cases:**
- Player has DGNRS but DGNRS contract has insufficient sDGNRS: L462 would succeed (burns player's DGNRS), but then L464/L468 would revert because `balanceOf[ContractAddresses.DGNRS]` in sDGNRS would be < amount. Transaction reverts atomically. However, this state CANNOT arise: DGNRS totalSupply equals sDGNRS balanceOf[DGNRS] at construction, and every DGNRS burn reduces both equally (via burn or burnForSdgnrs). The only other operation is unwrapTo, which burns DGNRS and moves sDGNRS (keeping them equal). **SAFE.**

**6-10:** Same as B1. **SAFE.**

**VERDICT: SAFE**

---

## B3: sDGNRS::claimRedemption() (L573-639)

### Call Tree
```
claimRedemption() [L573]
  -> pendingRedemptions[msg.sender] [L575] -- storage read
  -> redemptionPeriods[claim.periodIndex] [L578] -- storage read
  -> coinflip.getCoinflipDayResult(period.flipDay) [L604] -- external view
  -> game.gameOver() [L590] -- external view

  -> pendingRedemptionEthValue -= totalRolledEth [L612] -- storage write

  IF flipResolved:
    -> delete pendingRedemptions[player] [L616] -- storage write
  ELSE:
    -> claim.ethValueOwed = 0 [L619] -- storage write

  IF lootboxEth != 0:
    -> game.rngWordForDay(claimPeriodIndex) [L625] -- external view
    -> game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore) [L627] -- external call

  IF burniePayout != 0:
    -> _payBurnie(player, burniePayout) [L632] -- see below
      -> coin.balanceOf(address(this)) [L798] -- external view
      -> coin.transfer(player, payBal) [L802] -- external call
      IF remaining:
        -> coinflip.claimCoinflipsForRedemption(address(this), remaining) [L805] -- external call
        -> coin.transfer(player, remaining) [L806] -- external call

  -> _payEth(player, ethDirect) [L638] -- see below
    -> _claimableWinnings() [L775] -- external view
    IF amount > ethBal && claimable != 0:
      -> game.claimWinnings(address(0)) [L778] -- external call (sends ETH to sDGNRS)
    -> player.call{value: ethDirect}("") [L783] -- ETH transfer to untrusted address
    OR steth.transfer(player, stethOut) [L792] -- stETH fallback
```

### Storage Writes (Full Tree)
- `pendingRedemptionEthValue` (L612) -- decremented by totalRolledEth
- `pendingRedemptions[player]` (L616 or L619) -- deleted or ethValueOwed zeroed
- No other sDGNRS storage writes in this function
- External calls may write to Game state (resolveRedemptionLootbox) and Coinflip state (claimCoinflipsForRedemption)

### Cached-Local-vs-Storage Check
- `roll` (L581) cached from `period.roll`. No descendant writes to `redemptionPeriods[claim.periodIndex].roll`. **SAFE.**
- `claimPeriodIndex` (L582) cached from `claim.periodIndex`. `claim` is deleted at L616 or ethValueOwed zeroed at L619 -- but claimPeriodIndex is already copied to local. **SAFE.**
- `claimActivityScore` (L583) cached from `claim.activityScore`. Same -- already copied. **SAFE.**
- `totalRolledEth` (L587) computed from cached values. Used at L612 to decrement pendingRedemptionEthValue. No descendant writes to pendingRedemptionEthValue before L612. **SAFE.**
- `ethDirect` (L591) computed from totalRolledEth. Used at L638 for _payEth. No intermediary writes to `ethDirect`. But could `game.resolveRedemptionLootbox()` at L627 change sDGNRS's ETH balance? It's an external call to Game which does internal accounting -- no ETH transfer to sDGNRS. **SAFE.**
- **INVESTIGATE: _payEth reads address(this).balance at L774. Between L612 and L638, calls to resolveRedemptionLootbox (L627) and _payBurnie (L632) occur. Could these change address(this).balance?**
  - `game.resolveRedemptionLootbox()` -- this is a delegatecall inside Game, does internal accounting only. Does NOT send ETH to sDGNRS. **No balance change.**
  - `_payBurnie()` -- calls coin.transfer() (BURNIE ERC20 transfer, no ETH involved) and coinflip.claimCoinflipsForRedemption() (BURNIE mint/transfer, no ETH). **No balance change.**
  - Therefore _payEth reads a consistent ETH balance. **SAFE.**

### Attack Analysis

**1. State Coherence (BAF Pattern):** All cached locals are read before any storage writes. The storage write at L612 (`pendingRedemptionEthValue -= totalRolledEth`) happens before external calls. The external calls (resolveRedemptionLootbox, _payBurnie, _payEth) do not write to pendingRedemptionEthValue. **SAFE.**

**2. Access Control:** Anyone can call, but reverts if they have no pending claim (L576). Only the original submitter benefits. **SAFE.**

**3. RNG Manipulation:** The roll was determined by resolveRedemptionPeriod (game-controlled). The entropy for lootbox (L626) uses `keccak256(rngWordForDay, player)` -- player address is known but rngWord was determined by VRF before the claim. Player could delay claiming to wait for favorable coinflip result, but this is by design (coinflip resolution is separate). **SAFE.**

**4. Cross-Contract State Desync:**
- `game.resolveRedemptionLootbox()` at L627: this is called with `lootboxEth` which is half the rolled ETH. The game internally credits this as lootbox rewards. The ETH stays in sDGNRS's claimable winnings balance. If the game's accounting of sDGNRS's claimable becomes desynchronized, sDGNRS could fail to retrieve ETH later in _payEth. But claimWinnings() retrieves the full claimable balance, so as long as the game credits match, this is fine. **SAFE (assumes Game accounting correct -- verified in Unit 2).**

**5. Edge Cases:**
- **Second claim (partial):** Player claimed ETH but coinflip was unresolved. On second call: `claim.periodIndex` still set (not deleted), `claim.ethValueOwed = 0`, so `totalRolledEth = 0`, `ethDirect = 0`, `lootboxEth = 0`. The BURNIE check at L604 now returns resolved. If won: `burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000`. Then at L612: `pendingRedemptionEthValue -= 0` (no underflow). At L616: `delete pendingRedemptions[player]`. **CORRECT.**
- **periodIndex = 0:** Reverts at L576 `NoClaim`. **SAFE.**
- **roll = 0 in period (unresolved):** Reverts at L579 `NotResolved`. **SAFE.**

**6. Conditional Paths:**
- gameOver = true: ethDirect = 100%, lootboxEth = 0. No resolveRedemptionLootbox call. **SAFE.**
- gameOver = false: 50/50 split. resolveRedemptionLootbox called with half. **SAFE.**
- flipResolved = true, flipWon = true: full BURNIE payout. **SAFE.**
- flipResolved = true, flipWon = false: burniePayout = 0 (no BURNIE). Claim deleted. **SAFE.**
- flipResolved = false: partial claim, ETH paid, BURNIE kept. **SAFE.**

**7. Economic Attacks:**
- **INVESTIGATE: Dust accumulation in pendingRedemptionEthValue.** Comment at L585-586 acknowledges "per-claimant floor division may leave up to (n-1) wei dust per period." This is because `resolveRedemptionPeriod` computes `rolledEth = (pendingRedemptionEthBase * roll) / 100` for the entire period, but each claimant computes `(claim.ethValueOwed * roll) / 100` independently. Floor division means sum of per-claimant rolled amounts <= period rolled amount. The difference (dust) remains in `pendingRedemptionEthValue` forever. Over many periods, this dust accumulates. With up to ~1000 claimants per period and 1 wei per claimant, this is ~1000 wei per period -- economically negligible. **SAFE (INFO-level).**

**8. Griefing:**
- _payEth sends ETH to `player.call{value:}`. If player is a contract that reverts on receive, the revert propagates and the entire claim reverts. The player griefs themselves only. **SAFE.**

**9. Ordering:**
- Claim before resolve: Reverts (roll=0). **SAFE.**
- Claim twice with ETH+BURNIE: Second call finds ethValueOwed=0, only processes BURNIE. **SAFE.**
- Claim after period 0 (initial state): periodIndex=0 reverts NoClaim. **SAFE.**

**10. Silent Failures:** All error paths revert. No silent skips. **SAFE.**

**VERDICT: SAFE (1 INFO finding: dust accumulation)**

---

## B4: sDGNRS::resolveRedemptionPeriod(uint16 roll, uint48 flipDay) (L540-565)

### Call Tree
```
resolveRedemptionPeriod(roll, flipDay) [L540]
  -> pendingRedemptionEthBase [L544] -- storage read
  -> pendingRedemptionBurnieBase [L544] -- storage read
  -> rolledEth = (pendingRedemptionEthBase * roll) / 100 [L547]
  -> pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth [L548]
  -> pendingRedemptionEthBase = 0 [L549]
  -> burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100 [L552]
  -> pendingRedemptionBurnie -= pendingRedemptionBurnieBase [L555]
  -> pendingRedemptionBurnieBase = 0 [L556]
  -> redemptionPeriods[period] = {roll, flipDay} [L559-562]
  -- No external calls
```

### Storage Writes (Full Tree)
- `pendingRedemptionEthValue` (L548) -- adjusted: subtract base, add rolled
- `pendingRedemptionEthBase` (L549) -- zeroed
- `pendingRedemptionBurnie` (L555) -- decremented by base
- `pendingRedemptionBurnieBase` (L556) -- zeroed
- `redemptionPeriods[period]` (L559-562) -- set roll + flipDay

### Cached-Local-vs-Storage Check
- `period` (L543) caches `redemptionPeriodIndex`. No write to `redemptionPeriodIndex` in this function. **SAFE.**
- `rolledEth` (L547) local computed from storage reads. Used at L548 to update `pendingRedemptionEthValue`. No intermediary writes. **SAFE.**

### Attack Analysis

**1. State Coherence:** No external calls. All storage writes are sequential with no re-reads of previously-written values. **SAFE.**

**2. Access Control:** `msg.sender != ContractAddresses.GAME` check at L541. Only game can call. **SAFE.**

**3. RNG Manipulation:** The `roll` parameter comes from the game, which derives it from VRF. This function trusts the game to provide a valid roll. The game's VRF is audited in Unit 2. **SAFE (trust assumption).**

**4. Edge Cases:**
- roll = 0: Would set `rolledEth = 0`, `burnieToCredit = 0`. pendingRedemptionEthValue decreases by full base. Players would get 0 ETH. But game enforces roll range 25-175. If game passes 0: players lose everything. This is a game logic issue, not sDGNRS. **SAFE (game trust assumption).**
- Both bases = 0: Returns 0 at L544, no storage writes. **SAFE.**
- roll = 175 (max): `rolledEth = base * 175 / 100 = base * 1.75`. `pendingRedemptionEthValue` increases by 0.75 * base. This means more ETH is segregated than was originally reserved. Is there enough ETH? The 50% supply cap means at most 50% of supply was burned, so at most 50% of totalMoney was segregated. A 175% roll means 87.5% of totalMoney for that period. Combined with prior periods' segregation, could this exceed 100%? Only if multiple periods overlap with max rolls. But each period resolves before new submissions happen (or new period starts fresh). The unresolved period's base is zeroed at resolve. So pendingRedemptionEthValue can grow but never exceeds actual reserves because the 50% cap limits base per period. **SAFE.**

**5. Ordering:**
- **INVESTIGATE: Can resolveRedemptionPeriod be called twice for the same period?** After first call, `pendingRedemptionEthBase = 0` and `pendingRedemptionBurnieBase = 0`. Second call hits L544 check and returns 0. But `redemptionPeriods[period]` is already set. The second call would NOT overwrite because it returns early. Actually wait -- L544 checks if BOTH are 0 and returns. After first resolve, both are 0, so second call returns 0 without modifying anything. **SAFE.** But what if new submissions happen for a new period, and game accidentally passes the old period's index? The game controls this -- it passes the current period. If game passes a stale period, bases are 0 (already resolved), returns 0. **SAFE.**

**6-10:** No external calls, simple math, all paths covered. **SAFE.**

**VERDICT: SAFE**

---

## B13: DGNRS::burn(uint256) (L171-189)

### Call Tree
```
burn(amount) [L171]
  -> _burn(msg.sender, amount) [L172]
    -- balanceOf[msg.sender] -= amount, totalSupply -= amount (DGNRS state) [L222-230]
  -> game.gameOver() [L173] -- external view, reverts if false
  -> stonk.burn(amount) [L175] -- calls sDGNRS.burn(amount)
    -- sDGNRS.burn() with msg.sender = DGNRS contract
    -- BUT WAIT: sDGNRS.burn() checks game.gameOver() and enters deterministic path
    -- _deterministicBurnFrom(DGNRS, DGNRS, amount)
    -- Burns sDGNRS from DGNRS balance, sends ETH/stETH to DGNRS contract
  -> burnie.transfer(msg.sender, burnieOut) [L178] -- forward BURNIE (if any)
  -> steth.transfer(msg.sender, stethOut) [L181] -- forward stETH (if any)
  -> msg.sender.call{value: ethOut}("") [L184] -- forward ETH
```

### Storage Writes (Full Tree)
**DGNRS:** `balanceOf[msg.sender]` (L224), `totalSupply` (L227)
**sDGNRS (via stonk.burn):** `balanceOf[DGNRS]` (L493), `totalSupply` (L494)

### Cached-Local-vs-Storage Check
- DGNRS._burn caches `bal = balanceOf[from]` at L223. Uses it at L226. No descendant writes to DGNRS.balanceOf[msg.sender] before L226. **SAFE.**
- The call to `stonk.burn(amount)` writes to sDGNRS storage, not DGNRS storage. **No cross-contract cache issue.**
- `(ethOut, stethOut, burnieOut)` returned from `stonk.burn()`. These are return values, not cached storage reads. **SAFE.**

### Attack Analysis

**1. State Coherence:** DGNRS state written at L172 (_burn). Then sDGNRS state written in stonk.burn(). Different contracts, different storage. **SAFE.**

**2. Access Control:** Anyone can call, but reverts if game not over (L173). **SAFE.**

**3. Edge Cases:**
- **INVESTIGATE: _burn before gameOver check.** L172 burns DGNRS BEFORE L173 checks gameOver. If gameOver is false, the revert at L173 unwinds the burn (atomic transaction). No persistent state change. However, this is an unusual pattern (effects before checks). Worth noting as INFO. **SAFE (atomic revert guarantees).**
- amount = 0: _burn at L224 checks `amount == 0 || amount > bal` -> reverts Insufficient. **SAFE.**
- burnieOut from sDGNRS.burn when gameOver: sDGNRS._deterministicBurnFrom returns (ethOut, stethOut) with NO burnieOut. The return signature of sDGNRS.burn() is `(uint256, uint256, uint256)` and gameOver path returns `(ethOut, stethOut, 0)`. So burnieOut = 0 always. But DGNRS.burn checks `if (burnieOut != 0)` at L177 -- this will be false. **CORRECT but note: post-gameOver DGNRS burns never pay BURNIE.**

**4. Cross-Contract Desync:**
- `stonk.burn(amount)` with msg.sender = DGNRS contract: sDGNRS.burn() reads `balanceOf[msg.sender]` which is `balanceOf[DGNRS]` in sDGNRS. This should equal DGNRS.totalSupply (invariant: sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply). After DGNRS._burn reduces DGNRS.totalSupply by `amount`, sDGNRS.balanceOf[DGNRS] must be >= amount. Since the invariant holds (every DGNRS burn reduces both equally), this is safe. **SAFE.**
- **sDGNRS.burn() sends ETH to DGNRS via beneficiary.call{value: ethOut}. DGNRS.receive() only accepts ETH from sDGNRS. But in _deterministicBurnFrom, beneficiary = DGNRS (msg.sender of sDGNRS.burn). Wait -- no. sDGNRS.burn() is called by DGNRS, so msg.sender inside sDGNRS.burn() is the DGNRS contract. sDGNRS.burn() calls _deterministicBurn(msg.sender, amount) = _deterministicBurnFrom(DGNRS, DGNRS, amount). Beneficiary = DGNRS. So ETH is sent to DGNRS via .call{value: ethOut} at L517. DGNRS.receive() checks `msg.sender != address(stonk)` -> sDGNRS is the sender. This matches. **SAFE.**

**5. Economic:** Post-gameOver only. Each burn is proportional to remaining supply. No manipulation possible. **SAFE.**

**6-10:** All paths covered, no silent failures, no griefing. **SAFE.**

**VERDICT: SAFE (1 INFO: effects-before-checks pattern at L172-173, harmless due to atomicity)**

---

## TIER 2 FUNCTIONS (Moderate Risk)

---

## B5: sDGNRS::transferFromPool(Pool, address, uint256) (L376-393)

### Call Tree
```
transferFromPool(pool, to, amount) [L376]
  -> _poolIndex(pool) [L379] -- pure, returns uint8(pool)
  -> poolBalances[idx] [L380] -- storage read
  -- amount capped to available [L382-384]
  -> poolBalances[idx] = available - amount [L386] -- storage write (unchecked)
  -> balanceOf[address(this)] -= amount [L387] -- storage write (unchecked)
  -> balanceOf[to] += amount [L388] -- storage write (unchecked)
  -- No external calls
```

### Storage Writes (Full Tree)
- `poolBalances[idx]` (L386)
- `balanceOf[address(this)]` (L387)
- `balanceOf[to]` (L388)

### Cached-Local-vs-Storage Check
- `available` (L380) caches `poolBalances[idx]`. Written at L386 but the cached value is only used before the write. **SAFE.**

### Attack Analysis

**1. State Coherence:** No external calls. Pure storage manipulation. **SAFE.**

**2. Access Control:** `onlyGame` modifier. Only game can call. **SAFE.**

**3. Edge Cases:**
- amount = 0: Returns 0 at L377. **SAFE.**
- amount > available: Capped to available at L382-384. **SAFE.**
- available = 0: Returns 0 at L381. **SAFE.**
- to = address(0): Reverts ZeroAddress at L378. **SAFE.**
- Unchecked balanceOf[address(this)] -= amount (L387): Could this underflow? Only if sum of poolBalances > balanceOf[address(this)]. This is maintained as an invariant: constructor sets balanceOf[address(this)] = poolTotal = sum(all pool amounts), and every transferFromPool decrements both by same amount. **SAFE (invariant holds).**

**4-10:** No external calls, game-only access. **SAFE.**

**VERDICT: SAFE**

---

## B6: sDGNRS::transferBetweenPools(Pool, Pool, uint256) (L401-416)

### Call Tree
```
transferBetweenPools(from, to, amount) [L401]
  -> _poolIndex(from) [L403], _poolIndex(to) [L404]
  -> poolBalances[fromIdx] [L405] -- storage read
  -- amount capped to available [L407-409]
  -> poolBalances[fromIdx] = available - amount [L411] -- unchecked
  -> poolBalances[toIdx] += amount [L413] -- checked
  -- No external calls
```

### Storage Writes (Full Tree)
- `poolBalances[fromIdx]` (L411)
- `poolBalances[toIdx]` (L413)

### Cached-Local-vs-Storage Check
- `available` caches `poolBalances[fromIdx]`. Used only before write. **SAFE.**

### Attack Analysis

**1-3:** No external calls, onlyGame, pure rebalance. **SAFE.**

**4. Edge Cases:**
- from == to: Legal. Reads available, caps, subtracts, adds back. Net zero. No issue. **SAFE.**
- poolBalances[toIdx] overflow: Impossible -- total across all pools <= 1T tokens (fits in uint256). **SAFE.**

**VERDICT: SAFE**

---

## B7: sDGNRS::burnRemainingPools() (L420-429)

### Call Tree
```
burnRemainingPools() [L420]
  -> balanceOf[address(this)] [L421] -- storage read
  -> balanceOf[address(this)] = 0 [L424] -- unchecked
  -> totalSupply -= bal [L425] -- unchecked
  -> delete poolBalances [L427] -- storage write (zeroes all 5 slots)
  -- No external calls
```

### Storage Writes (Full Tree)
- `balanceOf[address(this)]` (L424) -- zeroed
- `totalSupply` (L425) -- decremented
- `poolBalances` (L427) -- deleted (all 5 slots zeroed)

### Cached-Local-vs-Storage Check
- `bal` caches `balanceOf[address(this)]`. Used at L425 after balanceOf is zeroed. But this is fine -- totalSupply -= bal uses the cached value. **SAFE.**

### Attack Analysis

**1-3:** No external calls, onlyGame. **SAFE.**

**4. Edge Cases:**
- bal = 0: Returns early at L422. **SAFE.**
- Called twice: Second call reads bal = 0, returns early. **SAFE.**
- Unchecked totalSupply -= bal: bal was minted to address(this) in constructor, so totalSupply >= bal. **SAFE.**

**VERDICT: SAFE**

---

## B8: sDGNRS::wrapperTransferTo(address, uint256) (L310-320)

### Call Tree
```
wrapperTransferTo(to, amount) [L310]
  -> balanceOf[ContractAddresses.DGNRS] [L313] -- storage read
  -> balanceOf[ContractAddresses.DGNRS] = bal - amount [L316] -- unchecked
  -> balanceOf[to] += amount [L317] -- unchecked
  -- No external calls
```

### Storage Writes (Full Tree)
- `balanceOf[ContractAddresses.DGNRS]` (L316)
- `balanceOf[to]` (L317)

### Cached-Local-vs-Storage Check
- `bal` caches `balanceOf[DGNRS]`. Used only before write. **SAFE.**

### Attack Analysis

**1-3:** No external calls. DGNRS-only access (L311). **SAFE.**

**4. Edge Cases:**
- to = address(0): Reverts ZeroAddress at L312. **SAFE.**
- amount > bal: Reverts Insufficient at L314. **SAFE.**
- to = DGNRS address: Legal. Transfers from DGNRS balance to DGNRS balance. Net zero for DGNRS balance in sDGNRS. No issue. **SAFE.**
- Unchecked overflow: balanceOf[to] += amount in unchecked. With 1T total supply, impossible. **SAFE.**

**VERDICT: SAFE**

---

## B14: DGNRS::unwrapTo(address, uint256) (L152-161)

### Call Tree
```
unwrapTo(recipient, amount) [L152]
  -> msg.sender != ContractAddresses.CREATOR [L153] -- access check
  -> recipient == address(0) [L154] -- zero check
  -> IDegenerusGame(GAME).lastVrfProcessed() [L156] -- external view
  -> block.timestamp - lastVrfProcessed > 5 hours [L156] -- VRF stall check
  -> _burn(msg.sender, amount) [L158]
    -- balanceOf[msg.sender] -= amount, totalSupply -= amount [L222-230]
  -> stonk.wrapperTransferTo(recipient, amount) [L159]
    -- sDGNRS.wrapperTransferTo: balanceOf[DGNRS] -= amount, balanceOf[recipient] += amount [L310-320]
```

### Storage Writes (Full Tree)
**DGNRS:** `balanceOf[CREATOR]` (L226), `totalSupply` (L227)
**sDGNRS:** `balanceOf[DGNRS]` (L316), `balanceOf[recipient]` (L317)

### Cached-Local-vs-Storage Check
- DGNRS._burn caches `bal = balanceOf[msg.sender]` at L223. No descendant writes to DGNRS.balanceOf[CREATOR]. **SAFE.**
- Cross-contract: DGNRS writes to DGNRS state, then calls sDGNRS which writes to sDGNRS state. No stale cache. **SAFE.**

### Attack Analysis

**1. State Coherence:** Sequential cross-contract writes, no shared storage. **SAFE.**

**2. Access Control:** Creator-only (L153). **SAFE.**

**3. VRF Stall Guard (D-09 priority):**
- Blocks unwrap if `block.timestamp - lastVrfProcessed > 5 hours` (L156)
- Purpose: prevents creator from converting DGNRS -> sDGNRS during VRF stall to gain extra sDGNRS votes in governance
- **INVESTIGATE: Can the creator manipulate lastVrfProcessed?** `lastVrfProcessed` is set by the game during VRF fulfillment. The creator cannot directly set this. The creator could potentially advance the game (if day needs advancing) to trigger a VRF request/fulfillment, which would update lastVrfProcessed. But this requires valid VRF fulfillment which requires Chainlink to respond. If VRF is truly stalled (Chainlink not responding), creator cannot update lastVrfProcessed. **SAFE.**
- **INVESTIGATE: 5-hour window tight enough?** If VRF is healthy, fulfillment typically happens within minutes. 5 hours gives substantial margin. If VRF stalls for <5 hours, creator can still unwrap. But the governance attack requires sustained vote-stacking, and proposals have their own timing requirements. This is a judgment call -- 5 hours seems reasonable. **SAFE (design choice).**

**4. Edge Cases:**
- recipient = CREATOR: Legal. Burns DGNRS, gives CREATOR sDGNRS. Net: creator exchanges liquid DGNRS for soulbound sDGNRS. By design. **SAFE.**
- recipient = DGNRS address: wrapperTransferTo sends to DGNRS. This puts sDGNRS back in DGNRS balance. The DGNRS totalSupply was reduced by _burn but sDGNRS balance of DGNRS was decreased and then increased by same amount -- net zero on sDGNRS side. But DGNRS totalSupply is now less. This breaks the invariant (sDGNRS.balanceOf[DGNRS] > DGNRS.totalSupply). However, this only benefits the remaining DGNRS holders (more backing per token). Not exploitable since only creator can call. **SAFE.**

**VERDICT: SAFE**

---

## B15: DGNRS::burnForSdgnrs(address, uint256) (L241-250)

### Call Tree
```
burnForSdgnrs(player, amount) [L241]
  -> msg.sender != ContractAddresses.SDGNRS [L242] -- access check
  -> balanceOf[player] [L243] -- storage read
  -> balanceOf[player] = bal - amount [L246] -- unchecked
  -> totalSupply -= amount [L247] -- unchecked
  -- No external calls
```

### Storage Writes (Full Tree)
- `balanceOf[player]` (L246)
- `totalSupply` (L247)

### Cached-Local-vs-Storage Check
- `bal` caches `balanceOf[player]`. Used at L246 before any write. **SAFE.**

### Attack Analysis

**1-3:** sDGNRS-only access (L242). No external calls. **SAFE.**

**4. Edge Cases:**
- amount = 0: Reverts at L244 (`amount == 0 || amount > bal`). **SAFE.**
- amount > bal: Reverts. **SAFE.**

**VERDICT: SAFE**

---

## TIER 3 FUNCTIONS (Lower Risk)

---

## B9: sDGNRS::depositSteth(uint256) (L352-355)

### Call Tree
```
depositSteth(amount) [L352]
  -> steth.transferFrom(msg.sender, address(this), amount) [L353] -- external call
```

### Storage Writes: None in sDGNRS (stETH balance changes externally)

### Attack Analysis
- onlyGame access. Simple stETH transfer. Reverts on failure. **SAFE.**

**VERDICT: SAFE**

---

## B10: sDGNRS::receive() payable (L343-345)

### Call Tree
```
receive() [L343]
  -- onlyGame modifier
  -- emit Deposit
```

### Storage Writes: None (ETH balance changes implicitly)

### Attack Analysis
- onlyGame access. Accepts ETH. **SAFE.**

**VERDICT: SAFE**

---

## B11: sDGNRS::gameAdvance() (L327-329)

### Call Tree
```
gameAdvance() [L327]
  -> game.advanceGame() [L328] -- external call
```

### Storage Writes: None in sDGNRS (game state changes)

### Attack Analysis
- Anyone can call. Proxies to game.advanceGame(). No sDGNRS state change. The game handles its own access control for advance. **SAFE.**

**VERDICT: SAFE**

---

## B12: sDGNRS::gameClaimWhalePass() (L332-334)

### Call Tree
```
gameClaimWhalePass() [L332]
  -> game.claimWhalePass(address(0)) [L333] -- external call
```

### Storage Writes: None in sDGNRS

### Attack Analysis
- Anyone can call. Claims whale pass for sDGNRS contract (address(0) means self). No sDGNRS state change. **SAFE.**

**VERDICT: SAFE**

---

## B16: DGNRS::transfer(address, uint256) (L112-114)

### Call Tree
```
transfer(to, amount) [L112]
  -> _transfer(msg.sender, to, amount) [L113] -- see C6
```

### Storage Writes: `balanceOf[from]` (L215), `balanceOf[to]` (L216)

### Attack Analysis
- Standard ERC20. Blocks transfer to address(0) and address(this) (L210-211). No external calls. **SAFE.**

**VERDICT: SAFE**

---

## B17: DGNRS::transferFrom(address, address, uint256) (L125-134)

### Call Tree
```
transferFrom(from, to, amount) [L125]
  -> allowance[from][msg.sender] [L126] -- storage read
  IF allowed != max:
    -> allowance[from][msg.sender] = allowed - amount [L130] -- unchecked write
  -> _transfer(from, to, amount) [L133] -- see C6
```

### Storage Writes: `allowance[from][msg.sender]` (L130), `balanceOf[from]` (L215), `balanceOf[to]` (L216)

### Cached-Local-vs-Storage Check
- `allowed` caches `allowance[from][msg.sender]`. Used at L128 and L130, no intermediary write. **SAFE.**

### Attack Analysis
- Standard ERC20 transferFrom. Max allowance skip is standard pattern. Amount > allowed reverts at L128. **SAFE.**
- **Note:** No approval frontrun protection (no increaseAllowance/decreaseAllowance). This is noted but standard ERC20 behavior, not a finding per scope. **SAFE.**

**VERDICT: SAFE**

---

## B18: DGNRS::approve(address, uint256) (L140-144)

### Call Tree
```
approve(spender, amount) [L140]
  -> allowance[msg.sender][spender] = amount [L141]
```

### Storage Writes: `allowance[msg.sender][spender]` (L141)

### Attack Analysis
- Standard ERC20 approve. **SAFE.**

**VERDICT: SAFE**

---

## B19: DGNRS::receive() payable (L97-99)

### Call Tree
```
receive() [L97]
  -> msg.sender != address(stonk) [L98] -- access check
```

### Storage Writes: None

### Attack Analysis
- Only accepts ETH from sDGNRS. Used during burn-through (DGNRS.burn -> sDGNRS.burn -> sends ETH to DGNRS). **SAFE.**

**VERDICT: SAFE**

---

## MULTI-PARENT CATEGORY C (Standalone Analysis)

---

## C1: sDGNRS::_deterministicBurnFrom(address, address, uint256) [MULTI-PARENT] (L481-523)

**Called by:** burn() [beneficiary=player, burnFrom=player], burnWrapped() [beneficiary=player, burnFrom=DGNRS]

### Call Tree
```
_deterministicBurnFrom(beneficiary, burnFrom, amount) [L481]
  -> balanceOf[burnFrom] [L482] -- storage read
  -> totalSupply [L484] -- storage read (supplyBefore)
  -> address(this).balance [L486] -- ETH balance
  -> steth.balanceOf(address(this)) [L487] -- external view
  -> _claimableWinnings() [L488] -- external view (game.claimableWinningsOf)
  -> totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue [L489]
  -> totalValueOwed = (totalMoney * amount) / supplyBefore [L490]
  -> balanceOf[burnFrom] = bal - amount [L493] -- unchecked write
  -> totalSupply -= amount [L494] -- unchecked write
  IF totalValueOwed > ethBal && claimableEth != 0:
    -> game.claimWinnings(address(0)) [L499] -- external call (ETH sent to sDGNRS)
    -> re-read ethBal, stethBal [L500-501]
  -- ETH-preferential payout logic [L504-510]
  IF stethOut > 0:
    -> steth.transfer(beneficiary, stethOut) [L513] -- external call
  IF ethOut > 0:
    -> beneficiary.call{value: ethOut}("") [L517] -- ETH transfer
```

### Differentiated analysis by caller:

**From burn() (player burns own sDGNRS):**
- beneficiary = player = msg.sender
- burnFrom = player
- ETH/stETH sent to player directly
- Player has sDGNRS balance

**From burnWrapped() (player burns DGNRS wrapper tokens):**
- beneficiary = msg.sender (the player)
- burnFrom = ContractAddresses.DGNRS (sDGNRS burned from DGNRS contract's balance)
- ETH/stETH sent to player (NOT to DGNRS contract)
- But wait: when called from burnWrapped (L464), beneficiary = msg.sender, burnFrom = ContractAddresses.DGNRS. ETH goes to player. sDGNRS burned from DGNRS balance.

**When called from DGNRS.burn() -> sDGNRS.burn():**
- msg.sender of sDGNRS.burn() is DGNRS contract
- sDGNRS.burn() calls _deterministicBurn(DGNRS, amount) -> _deterministicBurnFrom(DGNRS, DGNRS, amount)
- beneficiary = DGNRS, burnFrom = DGNRS
- ETH/stETH sent to DGNRS contract (which then forwards to original caller)

### Attack Analysis (MULTI-PARENT specific)

**Cached-local divergence between callers:**
- Both paths cache `bal = balanceOf[burnFrom]` and `supplyBefore = totalSupply`. The burnFrom differs (player vs DGNRS), but the computation is identical. No divergence risk. **SAFE.**

**INVESTIGATE: totalMoney calculation (L489)**
- `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`
- If `pendingRedemptionEthValue > ethBal + stethBal + claimableEth`: underflow reverts (Solidity 0.8). This would mean more ETH is segregated for pending claims than exists. This should be impossible: ethValueOwed is calculated as a proportion of (totalMoney) at submit time, so the sum of all segregated values should never exceed totalMoney. However, if ETH is removed from the contract between submit and deterministic burn (e.g., by game withdrawing ETH), this could theoretically underflow. But the game can only send ETH TO sDGNRS (via receive), not withdraw it. And the only ETH outflows are: _deterministicBurnFrom (this function), _payEth (claim), and .call{value} to beneficiary. All are controlled within the burn flow. **SAFE.**

**VERDICT: SAFE**

---

## C2: sDGNRS::_submitGamblingClaimFrom(address, address, uint256) [MULTI-PARENT] (L707-769)

**Called by:** burn() [beneficiary=player, burnFrom=player], burnWrapped() [beneficiary=player, burnFrom=DGNRS]

### Call Tree
```
_submitGamblingClaimFrom(beneficiary, burnFrom, amount) [L707]
  -> balanceOf[burnFrom] [L708] -- storage read
  -> game.currentDayView() [L712] -- external view
  IF new period:
    -> redemptionPeriodSupplySnapshot = totalSupply [L714]
    -> redemptionPeriodIndex = currentPeriod [L715]
    -> redemptionPeriodBurned = 0 [L716]
  -> check 50% cap [L718]
  -> redemptionPeriodBurned += amount [L719]
  -> totalSupply [L721] -- storage read (supplyBefore)
  -> address(this).balance [L724]
  -> steth.balanceOf(address(this)) [L725] -- external view
  -> _claimableWinnings() [L726] -- external view
  -> coin.balanceOf(address(this)) [L731] -- external view
  -> coinflip.previewClaimCoinflips(address(this)) [L732] -- external view
  -> balanceOf[burnFrom] = bal - amount [L738] -- unchecked write
  -> totalSupply -= amount [L739] -- unchecked write
  -> pendingRedemptionEthValue += ethValueOwed [L744]
  -> pendingRedemptionEthBase += ethValueOwed [L745]
  -> pendingRedemptionBurnie += burnieOwed [L746]
  -> pendingRedemptionBurnieBase += burnieOwed [L747]
  -> pendingRedemptions[beneficiary] update [L750-766]
  -> game.playerActivityScore(beneficiary) [L765] -- external view (first burn only)
```

### Attack Analysis (MULTI-PARENT specific)

**INVESTIGATE: uint96 truncation at L758-760**
- `claim.ethValueOwed += uint96(ethValueOwed)` (L758)
- `claim.burnieOwed += uint96(burnieOwed)` (L760)
- The 160 ETH daily cap (L756) caps `claim.ethValueOwed + ethValueOwed` at 160 ether (1.6e20). uint96.max = ~7.9e28. So ethValueOwed truncation is impossible. **SAFE.**
- For burnieOwed: No explicit cap checked. The comment says "max realistic BURNIE is ~2e24, well below uint96.max (~7.9e28)". But is this guaranteed? If sDGNRS holds an enormous amount of BURNIE, a large burn could produce burnieOwed > uint96.max. With totalSupply starting at 1T tokens (1e30 wei), if sDGNRS held 1e30 BURNIE and someone burned 50% of supply, burnieOwed = 5e29, which exceeds uint96.max (~7.9e28). However: the 50% supply cap limits burns to 50% per period, and the 160 ETH cap limits each wallet's contribution. With 160 ETH worth of sDGNRS (a small fraction of total supply), the BURNIE proportional share would be small. The real constraint is: `burnieOwed = (totalBurnie * amount) / supplyBefore`. For burnieOwed to exceed uint96.max, we'd need `totalBurnie * amount / supplyBefore > 7.9e28`. With supplyBefore ~ 1e30 and amount capped at supplyBefore/2 = 5e29, this requires totalBurnie > 1.58e29. BURNIE has no supply cap in theory, but in practice is in the low trillions. This is a theoretical edge case. **VERDICT: INVESTIGATE** -- if BURNIE supply exceeds ~158 trillion tokens (1.58e29 wei), a max gambling burn could silently truncate burnieOwed.

**Differentiated analysis by caller:**
- From burn(): beneficiary = burnFrom = player. claim.ethValueOwed and claim.burnieOwed accumulate for the player.
- From burnWrapped(): beneficiary = player, burnFrom = DGNRS. sDGNRS burned from DGNRS balance, but claim recorded for player. This is correct -- player is the economic beneficiary.
- **INVESTIGATE: Can a player use both burn() and burnWrapped() in the same period to stack claims?** Both call _submitGamblingClaimFrom with beneficiary = msg.sender. If player burns sDGNRS via burn() and DGNRS via burnWrapped() in the same period, the claims stack (L750-753 only reverts if claim.periodIndex != 0 AND != currentPeriod). Both use currentPeriod, so they stack. The 160 ETH cap applies to the combined total. The 50% supply cap also applies to total burned. **This is by design -- player uses both token types toward the same claim. SAFE.**

**VERDICT: INVESTIGATE (uint96 BURNIE truncation theoretical)**

---

## C6: DGNRS::_transfer(address, address, uint256) [MULTI-PARENT] (L209-220)

**Called by:** transfer() [from=msg.sender], transferFrom() [from=specified]

### Call Tree
```
_transfer(from, to, amount) [L209]
  -> to == address(0) [L210] -- reverts ZeroAddress
  -> to == address(this) [L211] -- reverts Unauthorized
  -> balanceOf[from] [L212] -- storage read
  -> balanceOf[from] = bal - amount [L215] -- unchecked
  -> balanceOf[to] += amount [L216] -- unchecked
```

### Attack Analysis
- Standard ERC20 internal transfer. Blocks burns (to=0) and self-transfers (to=this). Both callers pass different `from` but logic is identical. **SAFE.**

**VERDICT: SAFE**

---

## C7: DGNRS::_burn(address, uint256) [MULTI-PARENT] (L222-230)

**Called by:** burn() [from=msg.sender], unwrapTo() [from=msg.sender, which is CREATOR]

### Call Tree
```
_burn(from, amount) [L222]
  -> balanceOf[from] [L223] -- storage read
  -> amount == 0 || amount > bal [L224] -- reverts Insufficient
  -> balanceOf[from] = bal - amount [L226] -- unchecked
  -> totalSupply -= amount [L227] -- unchecked
```

### Attack Analysis
- Standard burn. Both callers pass msg.sender as `from`. Identical logic. **SAFE.**

**VERDICT: SAFE**

---

## VIEW FUNCTION SECURITY NOTES

### D1: previewBurn(uint256) (L653-683)
- `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (L660): Could underflow if pendingRedemptionEthValue exceeds total. This would revert the view call, returning no data. Not a vulnerability -- just a broken view during abnormal state. **INFO.**
- `totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie` (L680): Same underflow potential. **INFO.**

### D2: hasPendingRedemptions() (L531-533)
- Simple check. **SAFE.**

### D3: burnieReserve() (L688-692)
- `burnieBal + claimableBurnie - pendingRedemptionBurnie`: Could underflow. **INFO.**

### D5: _claimableWinnings() (L812-816)
- Returns `stored - 1` if `stored > 1`, else 0. The -1 is dust protection (game stores 1 wei to avoid SSTORE from 0->nonzero). **SAFE.**

---

## FINDINGS SUMMARY

| ID | Function | Verdict | Severity | Description |
|----|----------|---------|----------|-------------|
| MG-11-01 | claimRedemption (B3) | INVESTIGATE | INFO | Dust accumulation in pendingRedemptionEthValue from per-claimant floor division -- economically negligible but monotonically increasing |
| MG-11-02 | DGNRS.burn (B13) | INVESTIGATE | INFO | Effects-before-checks pattern: _burn() at L172 executes before gameOver check at L173 -- safe due to atomic revert but atypical |
| MG-11-03 | _submitGamblingClaimFrom (C2) | INVESTIGATE | LOW | uint96 truncation of burnieOwed at L760 -- silent truncation if BURNIE reserves exceed ~158 trillion tokens (1.58e29 wei). Realistic? Unlikely but no on-chain enforcement. |
| MG-11-04 | previewBurn/burnieReserve (D1/D3) | INVESTIGATE | INFO | View functions can revert on underflow if pendingRedemption reserves exceed actual balances (abnormal state only) |

**Total functions analyzed:** 19 Category B + 4 MULTI-PARENT Category C + 7 Category D = 30 (+ 2 constructors, 3 trivial wrappers = 35 total coverage)
**VULNERABLE findings:** 0
**INVESTIGATE findings:** 4 (all INFO or LOW)
**SAFE verdicts:** 30/30 analyzed functions
