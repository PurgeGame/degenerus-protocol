# Unit 1: Game Router + Storage Layout -- Attack Report

**Agent:** Mad Genius (Attacker)
**Contracts:** DegenerusGame.sol (2,848 lines), DegenerusGameStorage.sol (1,613 lines), DegenerusGameMintStreakUtils.sol (62 lines)
**Date:** 2026-03-25

---

## Findings Summary

| ID | Function | Verdict | Severity | Title |
|----|----------|---------|----------|-------|
| F-01 | resolveRedemptionLootbox | INVESTIGATE | MEDIUM | Unchecked subtraction on claimableWinnings[SDGNRS] relies on mutual-exclusion assumption |
| F-02 | receive | INVESTIGATE | LOW | uint128 truncation of msg.value silently discards high bits for donations > 2^128 wei |
| F-03 | recordMint | INVESTIGATE | LOW | uint128 truncation on prize pool shares for extreme costWei values |
| F-04 | resolveRedemptionLootbox | INVESTIGATE | LOW | uint128 truncation on amount when crediting future prize pool |
| F-05 | claimAffiliateDgnrs | INVESTIGATE | INFO | price used as BURNIE conversion divisor -- zero-price edge at deploy |
| F-06 | _setAfKingMode | INVESTIGATE | INFO | coinflip.setCoinflipAutoRebuy external call before state.afKingMode write |
| F-07 | adminStakeEthForStEth | INVESTIGATE | INFO | Steth submit return value intentionally ignored -- 1-2 wei rounding |

**All 19 Category B functions and 30 Category A dispatchers analyzed. No VULNERABLE findings. 7 INVESTIGATE findings (1 MEDIUM, 2 LOW, 4 INFO).**

---

## Part 1: Direct State-Changing Functions (Category B)

---

## DegenerusGame::constructor() (lines 242-256) [B1]

### Call Tree
```
constructor() [line 242]
  +-- levelStartTime = uint48(block.timestamp) [line 243]
  +-- levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL [line 244]
  +-- deityPassCount[SDGNRS] = 1 [line 246]
  +-- deityPassCount[VAULT] = 1 [line 247]
  +-- for i = 1..100:
       +-- _queueTickets(SDGNRS, i, 16) [line 250]
       |    +-- ticketsOwedPacked[wk][buyer] read [Storage line 538]
       |    +-- ticketQueue[wk].push(buyer) [Storage line 542]
       |    +-- ticketsOwedPacked[wk][buyer] write [Storage line 547-548]
       +-- _queueTickets(VAULT, i, 16) [line 251]
            +-- (same as above)
```

### Storage Writes (Full Tree)
- `levelStartTime` (slot 0, offset 0) -- written by constructor at line 243
- `levelPrizePool[0]` (slot 30, mapping) -- written by constructor at line 244
- `deityPassCount[SDGNRS]` (slot 34, mapping) -- written by constructor at line 246
- `deityPassCount[VAULT]` (slot 34, mapping) -- written by constructor at line 247
- `ticketQueue[wk]` (slot 15, mapping) -- written by _queueTickets via push at Storage line 542 (200 pushes: 100 levels x 2 addresses)
- `ticketsOwedPacked[wk][buyer]` (slot 16, mapping) -- written by _queueTickets at Storage line 547-548 (200 writes)

### Cached-Local-vs-Storage Check
No locals cache any storage variable that is later written by a descendant. The constructor writes directly to storage in every case. `_queueTickets` reads `ticketsOwedPacked` into `packed`/`owed`/`rem` locals (Storage lines 538-540), but the only subsequent write is to that same mapping entry for that same key -- the parent (constructor) does not re-read or write-back any of these values.

**Verdict: SAFE** -- No BAF-class pattern. No ancestor caches any value that a descendant overwrites.

### Attack Analysis

**State Coherence:** Constructor runs once at deploy time. No re-entrancy possible. VERDICT: SAFE

**Access Control:** Only callable during deployment (Solidity constructor semantics). Cannot be re-invoked. VERDICT: SAFE

**RNG Manipulation:** No RNG used in constructor. VERDICT: N/A

**Cross-Contract State Desync:** No external calls. All state is local to this contract. VERDICT: SAFE

**Edge Cases:** `level` is 0 at deploy (default). `_queueTickets` with `targetLevel > level + 5` would trigger far-future key space. For i=1, level=0, so targetLevel=1 > 0+5=5 is false for i=1..5, true for i=6..100. The rngLockedFlag is false at deploy (default), so the RngLocked guard in _queueTickets (Storage line 536) never triggers. VERDICT: SAFE

**Conditional Paths:** Single path -- the for loop always runs 100 iterations. No branches. VERDICT: SAFE

**Economic/MEV:** Deploy is a single-shot transaction. No front-running possible. VERDICT: SAFE

**Griefing:** N/A -- constructor is deploy-only. VERDICT: SAFE

**Ordering/Sequencing:** Constructor runs before any other function. VERDICT: SAFE

**Silent Failures:** _queueTickets returns early if quantity==0, but quantity is hardcoded 16. No silent failures. VERDICT: SAFE

---

## DegenerusGame::recordMint() (lines 374-419) [B2]

### Call Tree
```
recordMint(player, lvl, costWei, mintUnits, payKind) [line 374]
  +-- require msg.sender == address(this) [line 385]
  +-- _processMintPayment(player, costWei, payKind) [line 387-391]
  |    +-- if DirectEth: require msg.value >= amount [line 937]
  |    +-- if Claimable: read claimableWinnings[player] [line 943]
  |    |    +-- write claimableWinnings[player] [line 949]
  |    +-- if Combined: read claimableWinnings[player] [line 957]
  |    |    +-- write claimableWinnings[player] [line 967]
  |    +-- write claimablePool -= claimableUsed [line 979]
  +-- if prizeContribution != 0: [line 392]
  |    +-- compute futureShare, nextShare [lines 393-395]
  |    +-- if prizePoolFrozen: [line 396]
  |    |    +-- _getPendingPools() [Storage line 665] -- read prizePoolPendingPacked
  |    |    +-- _setPendingPools() [Storage line 661] -- write prizePoolPendingPacked
  |    +-- else: [line 402]
  |         +-- _getPrizePools() [Storage line 655] -- read prizePoolsPacked
  |         +-- _setPrizePools() [Storage line 651] -- write prizePoolsPacked
  +-- _recordMintDataModule(player, lvl, mintUnits) [line 411]
  |    +-- delegatecall to GAME_MINT_MODULE with recordMintData.selector [line 1038-1048]
  |    |    (writes mintPacked_[player] inside module -- Storage slot 12)
  +-- if DirectEth or Combined: compute earlybirdEth [lines 412-416]
  +-- _awardEarlybirdDgnrs(player, earlybirdEth, lvl) [line 418]
       +-- if lvl >= EARLYBIRD_END_LEVEL(3): [Storage line 921]
       |    +-- if earlybirdDgnrsPoolStart != max: [Storage line 923]
       |         +-- write earlybirdDgnrsPoolStart = max [Storage line 924]
       |         +-- dgnrs.poolBalance() (external view) [Storage line 928]
       |         +-- dgnrs.transferBetweenPools() (external call) [Storage line 932]
       +-- else (lvl < 3): [Storage line 941+]
            +-- read earlybirdDgnrsPoolStart [Storage line 942]
            +-- if 0: read dgnrs.poolBalance() and write earlybirdDgnrsPoolStart [Storage lines 944-948]
            +-- read earlybirdEthIn [Storage line 952]
            +-- compute payout via quadratic curve [Storage lines 960-964]
            +-- write earlybirdEthIn [Storage line 966]
            +-- dgnrs.transferFromPool() (external call) [Storage line 969-973]
```

### Storage Writes (Full Tree)
- `claimableWinnings[player]` (slot 9, mapping) -- written by _processMintPayment at line 949 or 967
- `claimablePool` (slot 10) -- written by _processMintPayment at line 979
- `prizePoolsPacked` (slot 3) -- written by _setPrizePools at line 404 (non-frozen path)
- `prizePoolPendingPacked` (slot 14) -- written by _setPendingPools at line 398 (frozen path)
- `mintPacked_[player]` (slot 12, mapping) -- written by delegatecall to GAME_MINT_MODULE via _recordMintDataModule
- `earlybirdDgnrsPoolStart` (slot 40) -- written by _awardEarlybirdDgnrs at Storage line 924 or 948
- `earlybirdEthIn` (slot 41) -- written by _awardEarlybirdDgnrs at Storage line 966

### Cached-Local-vs-Storage Check

**Critical pair: `prizeContribution` local vs `prizePoolsPacked`/`prizePoolPendingPacked` writes.**

1. `(prizeContribution, newClaimableBalance) = _processMintPayment(...)` at line 387. This caches the return value from _processMintPayment. Then at lines 392-408, the code uses `prizeContribution` to compute `futureShare` and `nextShare`, then reads the packed pools via `_getPrizePools()` / `_getPendingPools()` (fresh SLOAD), adds the shares, and writes back.

   The descendant calls after this (line 411: `_recordMintDataModule`, line 418: `_awardEarlybirdDgnrs`) do NOT write to `prizePoolsPacked` or `prizePoolPendingPacked`. The delegatecall to GAME_MINT_MODULE writes `mintPacked_[player]`, not pools. The `_awardEarlybirdDgnrs` writes `earlybirdDgnrsPoolStart` and `earlybirdEthIn`, not pools.

   **Verdict: SAFE** -- Pool writes happen BEFORE any descendant calls. No descendant writes to pools.

2. `newClaimableBalance` returned from `_processMintPayment`. The function writes `claimableWinnings[player]` and `claimablePool` directly inside `_processMintPayment`. The `newClaimableBalance` local is only used as a return value and is not written back to storage by the parent. It is the return value of `recordMint()` itself.

   **Verdict: SAFE** -- `newClaimableBalance` is only a return value, not written back to storage.

3. _awardEarlybirdDgnrs caches `poolStart = earlybirdDgnrsPoolStart` and `ethIn = earlybirdEthIn` as locals. It then computes payout and writes `earlybirdEthIn = nextEthIn`. No descendant call modifies these variables (the external calls are `dgnrs.transferFromPool` and `dgnrs.transferBetweenPools`, which are on a different contract and cannot modify DegenerusGame's storage).

   **Verdict: SAFE**

**F-03: uint128 truncation risk.** At lines 399-400 and 404-406, `nextShare` and `futureShare` are cast to `uint128` when added to the pool values. If `costWei` were astronomically large (> 2^128 wei, i.e., ~340 undecillion wei, far exceeding total ETH supply of ~120M ETH = ~1.2e26 wei), the cast would silently truncate. In practice, `costWei` is bounded by `price` which is `uint128` (line 311 of Storage), and `msg.value` which is bounded by contract balance. **VERDICT: INVESTIGATE (LOW)** -- Theoretically possible, practically unreachable. No real-world exploit.

### Attack Analysis

**State Coherence:** Pool writes (lines 392-408) happen before the delegatecall to _recordMintDataModule (line 411) and _awardEarlybirdDgnrs (line 418). Neither descendant writes to pools. VERDICT: SAFE

**Access Control:** `msg.sender != address(this)` check at line 385. Only callable via delegatecall from modules executing in Game's context. No external caller can invoke this directly. VERDICT: SAFE

**RNG Manipulation:** No RNG used. VERDICT: N/A

**Cross-Contract State Desync:** _awardEarlybirdDgnrs makes external calls to dgnrs (SDGNRS contract). These calls transfer tokens from pools. If the external call fails (e.g., pool empty), the function returns early (Storage line 946, 967). No state inconsistency results. VERDICT: SAFE

**Edge Cases:**
- `costWei == 0`: `_processMintPayment` with DirectEth and `msg.value < 0` is impossible (uint). With Claimable and amount=0, `claimable <= 0` is always true for non-negative claimable, so it reverts (line 945). Combined with amount=0, remaining=0, no claimable used. `prizeContribution=0`, pool writes skipped. VERDICT: SAFE
- `payKind` invalid enum: Hits the else at line 974, reverts E(). VERDICT: SAFE

**Conditional Paths:**
- DirectEth path (line 935): msg.value >= amount check, prizeContribution = amount.
- Claimable path (line 940): msg.value must be 0, claimable > amount (preserving sentinel), writes to claimableWinnings and claimablePool.
- Combined path (line 952): ETH first then claimable remainder, must fully cover cost.
- prizePoolFrozen branch (line 396): Routes to pending pools instead of live pools.
- earlybirdEth computation (lines 412-416): Different for DirectEth vs Combined. DirectEth: min(costWei, msg.value). Combined: msg.value.

All paths verified -- each either reverts or correctly updates state. VERDICT: SAFE

**Economic/MEV:** recordMint is only callable from self-call (delegatecall modules). Not directly accessible to external attackers. VERDICT: SAFE

**Griefing:** Cannot be called externally. VERDICT: SAFE

**Ordering/Sequencing:** Called only from mint modules during purchase flow. Order is enforced by the module logic. VERDICT: SAFE

**Silent Failures:** All error paths revert. The only "silent" path is `prizeContribution == 0` (line 392) which correctly skips pool writes when no contribution is made. VERDICT: SAFE

---

## DegenerusGame::recordMintQuestStreak() (lines 424-428) [B3]

### Call Tree
```
recordMintQuestStreak(player) [line 424]
  +-- require msg.sender == COIN [line 425]
  +-- _activeTicketLevel() [line 426]
  |    +-- returns jackpotPhaseFlag ? level : level + 1 [line 2292]
  +-- _recordMintStreakForLevel(player, mintLevel) [MintStreakUtils line 17]
       +-- read mintPacked_[player] [line 19]
       +-- if lastCompleted == mintLevel: return (idempotent) [line 23]
       +-- compute newStreak [lines 25-40]
       +-- write mintPacked_[player] = updated [line 45]
```

### Storage Writes (Full Tree)
- `mintPacked_[player]` (slot 12, mapping) -- written by _recordMintStreakForLevel at MintStreakUtils line 45

### Cached-Local-vs-Storage Check
`mintData` is cached from `mintPacked_[player]` at MintStreakUtils line 19. It is modified locally (lines 42-44) and written back at line 45. No descendant calls exist -- `_recordMintStreakForLevel` is a leaf function with no further calls. The parent `recordMintQuestStreak` does nothing after the call returns.

**Verdict: SAFE** -- Single read-modify-write with no intervening calls.

### Attack Analysis

**State Coherence:** Single storage write, no intervening calls. VERDICT: SAFE

**Access Control:** msg.sender must be COIN (ContractAddresses.COIN). Verified at line 425 -- the address is a compile-time constant. Only the COIN contract can call this. VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:** No external calls. VERDICT: SAFE

**Edge Cases:**
- `player == address(0)`: _recordMintStreakForLevel returns early (MintStreakUtils line 18). Silent no-op. Not exploitable -- the COIN contract controls what player address it passes.
- Level overflow: `level + 1` in _activeTicketLevel could overflow uint24.max, but level is uint24 and reaching 16M+ levels is unrealistic. VERDICT: SAFE

**Conditional Paths:**
- Idempotent check: If `lastCompleted == mintLevel`, returns without writing. Prevents double-counting. VERDICT: SAFE
- Streak continuation vs reset: If lastCompleted + 1 == mintLevel, streak increments. Otherwise resets to 1. Both paths write correctly. VERDICT: SAFE

**Economic/MEV:** Only COIN can call. VERDICT: SAFE
**Griefing:** Only COIN can call. VERDICT: SAFE
**Ordering/Sequencing:** Idempotent per level. VERDICT: SAFE
**Silent Failures:** Returns silently for address(0) -- by design. VERDICT: SAFE

---

## DegenerusGame::payCoinflipBountyDgnrs() (lines 435-458) [B4]

### Call Tree
```
payCoinflipBountyDgnrs(player, winningBet, bountyPool) [line 435]
  +-- require msg.sender == COIN or COINFLIP [line 440-443]
  +-- if player == address(0): return [line 444]
  +-- if winningBet < MIN_BET: return [line 445]
  +-- if bountyPool < MIN_POOL: return [line 446]
  +-- dgnrs.poolBalance(Pool.Reward) (external view) [line 447-449]
  +-- if poolBalance == 0: return [line 450]
  +-- compute payout = (poolBalance * 20) / 10000 [line 451]
  +-- if payout == 0: return [line 452]
  +-- dgnrs.transferFromPool(Pool.Reward, player, payout) (external call) [line 453-457]
```

### Storage Writes (Full Tree)
None. This function makes no storage writes to DegenerusGame. It only calls external `dgnrs.transferFromPool` which modifies SDGNRS contract storage.

### Cached-Local-vs-Storage Check
No storage is cached or written. No BAF-class risk.

**Verdict: SAFE** -- No storage writes in this contract.

### Attack Analysis

**State Coherence:** No storage writes. VERDICT: SAFE

**Access Control:** msg.sender must be COIN or COINFLIP. Both are compile-time constant addresses. VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:** Reads `dgnrs.poolBalance()` (view) then calls `dgnrs.transferFromPool()`. If the pool balance changes between the view call and the transfer (impossible in a single transaction context since SDGNRS is the only writer), it would not affect correctness -- transferFromPool would simply transfer less if the pool was drained. VERDICT: SAFE

**Edge Cases:**
- `poolBalance == 0`: Early return, no payout. VERDICT: SAFE
- `payout == 0`: Early return (possible if poolBalance < 500 since 20/10000 rounds down). VERDICT: SAFE
- `player == address(0)`: Early return. VERDICT: SAFE

**Conditional Paths:** All early returns are correct gate checks. The only action path is the transferFromPool call. VERDICT: SAFE

**Economic/MEV:** Only callable by COIN/COINFLIP. Cannot be front-run by external actors. VERDICT: SAFE
**Griefing:** Only callable by trusted contracts. VERDICT: SAFE
**Ordering/Sequencing:** Stateless -- no ordering dependencies. VERDICT: SAFE
**Silent Failures:** Multiple early returns for zero/below-minimum values. These are by design (gas optimization -- no need to revert). VERDICT: SAFE

---

## DegenerusGame::setOperatorApproval() (lines 468-472) [B5]

### Call Tree
```
setOperatorApproval(operator, approved) [line 468]
  +-- if operator == address(0): revert E() [line 469]
  +-- write operatorApprovals[msg.sender][operator] = approved [line 470]
  +-- emit OperatorApproval [line 471]
```

### Storage Writes (Full Tree)
- `operatorApprovals[msg.sender][operator]` (slot 29, mapping) -- written at line 470

### Cached-Local-vs-Storage Check
No locals cache storage. Direct write.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** Single direct storage write. VERDICT: SAFE
**Access Control:** Any address can set their own operator approvals. msg.sender is the owner. VERDICT: SAFE
**RNG Manipulation:** No RNG. VERDICT: N/A
**Cross-Contract State Desync:** No external calls. VERDICT: SAFE
**Edge Cases:** `operator == address(0)` correctly reverts. VERDICT: SAFE
**Conditional Paths:** Single path after zero-address check. VERDICT: SAFE
**Economic/MEV:** Player controls their own approvals. No MEV vector. VERDICT: SAFE
**Griefing:** Cannot affect other players' approvals. VERDICT: SAFE
**Ordering/Sequencing:** Setting then unsetting is idempotent. VERDICT: SAFE
**Silent Failures:** None -- reverts on zero address, otherwise always succeeds. VERDICT: SAFE

---

## DegenerusGame::setLootboxRngThreshold() (lines 512-522) [B6]

### Call Tree
```
setLootboxRngThreshold(newThreshold) [line 512]
  +-- require msg.sender == ADMIN [line 513]
  +-- require newThreshold != 0 [line 514]
  +-- read prev = lootboxRngThreshold [line 515]
  +-- if newThreshold == prev: emit + return [lines 516-519]
  +-- write lootboxRngThreshold = newThreshold [line 520]
  +-- emit LootboxRngThresholdUpdated [line 521]
```

### Storage Writes (Full Tree)
- `lootboxRngThreshold` (slot 47) -- written at line 520

### Cached-Local-vs-Storage Check
`prev` caches `lootboxRngThreshold` at line 515. If `newThreshold == prev`, the function returns early without writing (line 518). Otherwise, it writes the new value. No descendant calls modify this variable.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** Single storage write. VERDICT: SAFE
**Access Control:** msg.sender == ADMIN (compile-time constant). Admin trust assumption. VERDICT: SAFE
**RNG Manipulation:** No RNG. VERDICT: N/A
**Cross-Contract State Desync:** No external calls. VERDICT: SAFE
**Edge Cases:** newThreshold=0 reverts. newThreshold=prev emits event but doesn't write (optimization). VERDICT: SAFE
**Conditional Paths:** Two paths -- same-value (emit + return) and new-value (write + emit). Both correct. VERDICT: SAFE
**Economic/MEV:** Admin-only. VERDICT: SAFE
**Griefing:** Admin-only. VERDICT: SAFE
**Ordering/Sequencing:** No ordering dependencies. VERDICT: SAFE
**Silent Failures:** None. VERDICT: SAFE

---

## DegenerusGame::claimWinnings() (lines 1345-1348) [B7]

### Call Tree
```
claimWinnings(player) [line 1345]
  +-- _resolvePlayer(player) [line 1346]
  |    +-- if player == address(0): return msg.sender [line 494]
  |    +-- if player != msg.sender: _requireApproved(player) [line 495]
  |         +-- if msg.sender != player && !operatorApprovals[player][msg.sender]: revert NotApproved [line 486-488]
  +-- _claimWinningsInternal(player, false) [line 1347]
       +-- if finalSwept: revert E() [line 1362]
       +-- read amount = claimableWinnings[player] [line 1363]
       +-- if amount <= 1: revert E() [line 1364]
       +-- write claimableWinnings[player] = 1 (sentinel) [line 1367]
       +-- payout = amount - 1 [line 1368]
       +-- write claimablePool -= payout [line 1370]
       +-- emit WinningsClaimed [line 1371]
       +-- _payoutWithStethFallback(player, payout) [line 1375]
            +-- if amount == 0: return [line 1976]
            +-- ethBal = address(this).balance [line 1979]
            +-- ethSend = min(amount, ethBal) [line 1980]
            +-- if ethSend != 0: payable(to).call{value: ethSend} [line 1982]
            +-- remaining = amount - ethSend [line 1985]
            +-- if remaining == 0: return [line 1986]
            +-- stBal = steth.balanceOf(this) [line 1989]
            +-- stSend = min(remaining, stBal) [line 1990]
            +-- _transferSteth(to, stSend) [line 1991]
            |    +-- if to == SDGNRS: steth.approve + dgnrs.depositSteth [lines 1962-1965]
            |    +-- else: steth.transfer(to, amount) [line 1967]
            +-- leftover = remaining - stSend [line 1994]
            +-- if leftover != 0: retry ETH [lines 1995-2001]
```

### Storage Writes (Full Tree)
- `claimableWinnings[player]` (slot 9, mapping) -- written at line 1367 (set to 1, sentinel)
- `claimablePool` (slot 10) -- written at line 1370 (decremented by payout)

### Cached-Local-vs-Storage Check
1. `amount = claimableWinnings[player]` cached at line 1363. Then `claimableWinnings[player] = 1` at line 1367. No descendant writes to `claimableWinnings[player]` -- the payout functions are pure ETH/stETH transfer helpers.

2. No descendant writes to `claimablePool`. The payout helpers only make external calls (ETH send, stETH transfer).

**Verdict: SAFE** -- CEI pattern correctly applied. State updates (lines 1367, 1370) happen before external calls (line 1375+).

### Attack Analysis

**State Coherence:** CEI pattern: checks (lines 1362-1364), effects (lines 1367-1370), interactions (line 1375+). VERDICT: SAFE

**Access Control:** _resolvePlayer resolves player address. If player is address(0), uses msg.sender. If player != msg.sender, requires operator approval. VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:** External calls to payable(to).call and steth.transfer/approve happen AFTER state updates. If the ETH send fails (e.g., to a contract with no receive), it reverts at line 1983. The entire transaction reverts, undoing state changes. If stETH transfer fails, similarly reverts at line 1967. VERDICT: SAFE

**Edge Cases:**
- `amount == 1` (only sentinel): Reverts at line 1364 (amount <= 1). VERDICT: SAFE
- `finalSwept == true`: Reverts at line 1362. VERDICT: SAFE
- `payout > address(this).balance && payout > steth.balanceOf`: Falls through to leftover retry at line 1997. If ethRetry < leftover, reverts at line 1998. The claim reverts if insufficient combined balance. VERDICT: SAFE
- Recipient is a contract that reverts on ETH receive: The `.call{value:}` returns false, reverts at line 1983. VERDICT: SAFE

**Conditional Paths:**
- stethFirst=false: ETH first, stETH fallback (via _payoutWithStethFallback).
- The leftover retry path (lines 1994-2001) handles edge case where stETH balance was short but ETH arrived during the stETH call (e.g., if stETH approve triggered a callback that sent ETH). VERDICT: SAFE

**Economic/MEV:** Claiming does not affect other players' balances. No sandwich opportunity. VERDICT: SAFE
**Griefing:** A player can only claim their own balance (or via approved operator). VERDICT: SAFE
**Ordering/Sequencing:** Claim is idempotent after first claim (amount resets to 1). VERDICT: SAFE
**Silent Failures:** All failure paths revert. VERDICT: SAFE

---

## DegenerusGame::claimWinningsStethFirst() (lines 1352-1359) [B8]

### Call Tree
```
claimWinningsStethFirst() [line 1352]
  +-- player = msg.sender [line 1353]
  +-- require player == VAULT or player == SDGNRS [lines 1354-1357]
  +-- _claimWinningsInternal(player, true) [line 1358]
       +-- (same as B7 call tree, but stethFirst=true)
       +-- _payoutWithEthFallback(player, payout) [line 1373]
            +-- stBal = steth.balanceOf(this) [line 2011]
            +-- stSend = min(amount, stBal) [line 2012]
            +-- _transferSteth(to, stSend) [line 2013]
            +-- remaining = amount - stSend [line 2015]
            +-- if remaining == 0: return [line 2016]
            +-- ethBal = address(this).balance [line 2018]
            +-- if ethBal < remaining: revert E() [line 2019]
            +-- payable(to).call{value: remaining} [line 2020]
```

### Storage Writes (Full Tree)
Same as B7:
- `claimableWinnings[player]` (slot 9) -- written at line 1367
- `claimablePool` (slot 10) -- written at line 1370

### Cached-Local-vs-Storage Check
Same analysis as B7. No BAF pattern.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** Same CEI as B7. VERDICT: SAFE

**Access Control:** Restricted to VAULT and SDGNRS addresses (compile-time constants, lines 1355-1356). msg.sender must BE one of those contracts. No operator approval -- self-claim only. VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:** stETH transfer to SDGNRS uses special path: `steth.approve(SDGNRS, amount)` then `dgnrs.depositSteth(amount)` (lines 1962-1965). If depositSteth fails, the approve remains but the tx reverts. No state leak. VERDICT: SAFE

**Edge Cases:** Same as B7. VERDICT: SAFE

**Conditional Paths:**
- stethFirst=true: stETH first via _payoutWithEthFallback. If stETH insufficient, falls back to ETH. If neither sufficient, reverts.
- _transferSteth special path for SDGNRS (approve + depositSteth). VERDICT: SAFE

**Economic/MEV:** Only VAULT/SDGNRS can call. VERDICT: SAFE
**Griefing:** Only VAULT/SDGNRS. VERDICT: SAFE
**Ordering/Sequencing:** Same as B7. VERDICT: SAFE
**Silent Failures:** All failures revert. VERDICT: SAFE

---

## DegenerusGame::claimAffiliateDgnrs() (lines 1388-1431) [B9]

### Call Tree
```
claimAffiliateDgnrs(player) [line 1388]
  +-- _resolvePlayer(player) [line 1389]
  +-- read currLevel = level [line 1391]
  +-- if currLevel == 0: revert [line 1392]
  +-- read affiliateDgnrsClaimedBy[currLevel][player] [line 1394]
  +-- if claimed: revert [line 1394]
  +-- affiliate.affiliateScore(currLevel, player) (external view) [line 1396]
  +-- read deityPassCount[player] [line 1397]
  +-- if !hasDeityPass && score < MIN_SCORE: revert [line 1398]
  +-- affiliate.totalAffiliateScore(currLevel) (external view) [line 1400]
  +-- if denominator == 0: revert [line 1401]
  +-- read levelDgnrsAllocation[currLevel] [line 1403]
  +-- if allocation == 0: revert [line 1404]
  +-- compute reward = (allocation * score) / denominator [line 1405]
  +-- if reward == 0: revert [line 1406]
  +-- dgnrs.transferFromPool(Pool.Affiliate, player, reward) (external call) [line 1408-1412]
  +-- if paid == 0: revert [line 1413]
  +-- write levelDgnrsClaimed[currLevel] += paid [line 1415]
  +-- if hasDeityPass && score != 0: [line 1417]
  |    +-- compute bonus = (score * 2000) / 10000 [line 1418]
  |    +-- compute cap = (5 ether * PRICE_COIN_UNIT) / price [line 1419-1420]
  |    +-- if bonus > cap: bonus = cap [line 1421-1422]
  |    +-- if bonus != 0: coin.creditFlip(player, bonus) (external call) [line 1424-1425]
  +-- write affiliateDgnrsClaimedBy[currLevel][player] = true [line 1429]
  +-- emit AffiliateDgnrsClaimed [line 1430]
```

### Storage Writes (Full Tree)
- `levelDgnrsClaimed[currLevel]` (slot 33, mapping) -- written at line 1415
- `affiliateDgnrsClaimedBy[currLevel][player]` (slot 31, mapping) -- written at line 1429

### Cached-Local-vs-Storage Check
1. `currLevel = level` cached at line 1391. No descendant writes to `level`. External calls to `dgnrs.transferFromPool` and `coin.creditFlip` are on different contracts. VERDICT: SAFE

2. `score`, `denominator`, `allocation` are all read from external views or storage and used locally. No descendant writes to any of these. VERDICT: SAFE

3. `price` is read implicitly at line 1420 (`PRICE_COIN_UNIT / price`). No descendant writes to `price`. VERDICT: SAFE

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** No BAF pattern. All locals are consumed before external calls, and external calls don't write to Game storage. VERDICT: SAFE

**Access Control:** _resolvePlayer: anyone can claim for themselves or approved operators can claim for others. VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:**
- `affiliate.affiliateScore()` and `affiliate.totalAffiliateScore()` are view calls on the Affiliate contract. They read immutable per-level data (affiliate scores route to level+1 during gameplay, so at transition time all scores for currLevel are frozen). No desync risk.
- `dgnrs.transferFromPool()` returns the actual amount transferred (may be less if pool is depleted). The function checks `if (paid == 0) revert E()` at line 1413. `levelDgnrsClaimed` is incremented by `paid` (actual transferred amount), not `reward` (requested amount). VERDICT: SAFE

**Edge Cases:**
- `currLevel == 0`: Reverts at line 1392. VERDICT: SAFE
- `allocation == 0`: Reverts at line 1404. This happens if `rewardTopAffiliate` hasn't been called for this level yet (which it should be during level transition). VERDICT: SAFE
- `denominator == 0`: Reverts at line 1401 (no affiliate activity at all for this level). VERDICT: SAFE

**F-05: price == 0 edge at deploy.** `price` is initialized to `0.01 ether` in Storage (line 311-312). Division by zero at line 1420 is impossible because `price` is set at compile time. However, at level 0, `currLevel == 0` triggers the revert at line 1392, so this code is never reached when price could theoretically be 0 (it isn't). **VERDICT: INVESTIGATE (INFO)** -- Not exploitable, but the price=0 safety relies on the level check, not a direct price check.

**Conditional Paths:**
- Deity pass holder: Skips minimum score check (line 1398). Gets bonus BURNIE flip credit (lines 1417-1426). Cap is price-dependent.
- Non-deity: Must meet minimum score (10 ETH). No bonus.
Both paths fully analyzed. VERDICT: SAFE

**Economic/MEV:** Score-proportional payout from fixed allocation. All claimants for the same level share a fixed pot. No first-mover advantage. The claim flag prevents double-claims. VERDICT: SAFE
**Griefing:** Cannot affect other players' claims. VERDICT: SAFE
**Ordering/Sequencing:** One claim per player per level (enforced by claim flag). VERDICT: SAFE
**Silent Failures:** All failures revert. VERDICT: SAFE

---

## DegenerusGame::setAutoRebuy() (lines 1460-1463) [B10]

### Call Tree
```
setAutoRebuy(player, enabled) [line 1460]
  +-- _resolvePlayer(player) [line 1461]
  +-- _setAutoRebuy(player, enabled) [line 1462]
       +-- if rngLockedFlag: revert RngLocked [line 1492]
       +-- read autoRebuyState[player] [line 1493]
       +-- if state.autoRebuyEnabled != enabled: write state.autoRebuyEnabled = enabled [line 1494-1495]
       +-- emit AutoRebuyToggled [line 1497]
       +-- if !enabled: _deactivateAfKing(player) [line 1498-1499]
            +-- read autoRebuyState[player] [line 1679]
            +-- if !state.afKingMode: return [line 1680]
            +-- read activationLevel = state.afKingActivatedLevel [line 1681]
            +-- if activationLevel != 0: check unlock level [lines 1682-1684]
            +-- coinflip.settleFlipModeChange(player) (external call) [line 1686]
            +-- write state.afKingMode = false [line 1687]
            +-- write state.afKingActivatedLevel = 0 [line 1688]
            +-- emit AfKingModeToggled [line 1689]
```

### Storage Writes (Full Tree)
- `autoRebuyState[player].autoRebuyEnabled` (slot 25, mapping struct field) -- written at line 1495
- `autoRebuyState[player].afKingMode` (slot 25, mapping struct field) -- written by _deactivateAfKing at line 1687
- `autoRebuyState[player].afKingActivatedLevel` (slot 25, mapping struct field) -- written by _deactivateAfKing at line 1688

### Cached-Local-vs-Storage Check
1. `state` at line 1493 is a `storage` pointer (not a memory copy), so reads through `state.X` are fresh SLOADs. The `autoRebuyState[player]` is accessed via storage pointer. When _deactivateAfKing at line 1499 accesses `autoRebuyState[player]` again (line 1679), it gets a fresh storage pointer.

   Actually -- let me trace more carefully. At line 1493: `AutoRebuyState storage state = autoRebuyState[player]`. This is a storage pointer. Then at line 1495: `state.autoRebuyEnabled = enabled`. This writes through the storage pointer. Then at line 1499: `_deactivateAfKing(player)` is called. Inside _deactivateAfKing, line 1679: `AutoRebuyState storage state = autoRebuyState[player]`. This is a NEW storage pointer to the same slot. Reads through this pointer see the updated `autoRebuyEnabled` from line 1495.

   No conflict -- both pointers reference the same storage slot, and Solidity storage pointers always read/write directly to storage.

**Verdict: SAFE** -- Storage pointers, not memory copies. No stale cache.

### Attack Analysis

**State Coherence:** Storage pointers ensure fresh reads. VERDICT: SAFE

**Access Control:** _resolvePlayer with operator approval check. rngLockedFlag prevents changes during VRF window. VERDICT: SAFE

**RNG Manipulation:** Blocked during RNG lock (line 1492). VERDICT: SAFE

**Cross-Contract State Desync:** `coinflip.settleFlipModeChange(player)` is called in _deactivateAfKing (line 1686) BEFORE state writes (lines 1687-1688). If the external call fails, the entire transaction reverts, so state changes are undone. This is technically not CEI (external call before state write), but the external call is to a trusted contract (COINFLIP, compile-time constant) and cannot callback to Game to exploit the pre-write state. VERDICT: SAFE

**Edge Cases:**
- Disabling when afKing is active with lock period: _deactivateAfKing checks `level < unlockLevel` and reverts AfKingLockActive (line 1684). VERDICT: SAFE
- Disabling when afKing is inactive: _deactivateAfKing returns early at line 1680. VERDICT: SAFE

**Conditional Paths:**
- enabled=true: Just sets autoRebuyEnabled=true. No afKing deactivation.
- enabled=false: Sets autoRebuyEnabled=false, then deactivates afKing if active.
Both fully traced. VERDICT: SAFE

**Economic/MEV:** Player controls their own auto-rebuy. VERDICT: SAFE
**Griefing:** Cannot affect others. VERDICT: SAFE
**Ordering/Sequencing:** RNG lock prevents manipulation during sensitive windows. VERDICT: SAFE
**Silent Failures:** None -- reverts on locked RNG, reverts on lock period. VERDICT: SAFE

---

## DegenerusGame::setDecimatorAutoRebuy() (lines 1469-1477) [B11]

### Call Tree
```
setDecimatorAutoRebuy(player, enabled) [line 1469]
  +-- _resolvePlayer(player) [line 1470]
  +-- if rngLockedFlag: revert RngLocked [line 1471]
  +-- disabled = !enabled [line 1472]
  +-- if decimatorAutoRebuyDisabled[player] != disabled: write [line 1473-1474]
  +-- emit DecimatorAutoRebuyToggled [line 1476]
```

### Storage Writes (Full Tree)
- `decimatorAutoRebuyDisabled[player]` (slot 26, mapping) -- written at line 1474

### Cached-Local-vs-Storage Check
No locals cache storage for later writeback. Direct conditional write.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** Single direct write. VERDICT: SAFE
**Access Control:** _resolvePlayer + rngLocked guard. VERDICT: SAFE
**RNG Manipulation:** Blocked during RNG lock. VERDICT: SAFE
**Cross-Contract State Desync:** No external calls. VERDICT: SAFE
**Edge Cases:** Default is `false` (enabled). Setting to same value is a no-op (line 1473 check). VERDICT: SAFE
**Conditional Paths:** Write only if value changes. VERDICT: SAFE
**Economic/MEV:** Player controls own setting. VERDICT: SAFE
**Griefing:** Cannot affect others. VERDICT: SAFE
**Ordering/Sequencing:** No ordering dependencies. VERDICT: SAFE
**Silent Failures:** None. VERDICT: SAFE

---

## DegenerusGame::setAutoRebuyTakeProfit() (lines 1483-1489) [B12]

### Call Tree
```
setAutoRebuyTakeProfit(player, takeProfit) [line 1483]
  +-- _resolvePlayer(player) [line 1487]
  +-- _setAutoRebuyTakeProfit(player, takeProfit) [line 1488]
       +-- if rngLockedFlag: revert RngLocked [line 1507]
       +-- read autoRebuyState[player] via storage pointer [line 1508]
       +-- takeProfitValue = uint128(takeProfit) [line 1509]
       +-- if state.takeProfit != takeProfitValue: write state.takeProfit [line 1510-1511]
       +-- emit AutoRebuyTakeProfitSet [line 1513]
       +-- if takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_ETH: [line 1514]
            +-- _deactivateAfKing(player) [line 1515]
                 +-- (same as B10 call tree for _deactivateAfKing)
```

### Storage Writes (Full Tree)
- `autoRebuyState[player].takeProfit` (slot 25) -- written at line 1511
- `autoRebuyState[player].afKingMode` (slot 25) -- written by _deactivateAfKing at line 1687 (conditional)
- `autoRebuyState[player].afKingActivatedLevel` (slot 25) -- written by _deactivateAfKing at line 1688 (conditional)

### Cached-Local-vs-Storage Check
`takeProfitValue = uint128(takeProfit)` is a local derived from a function parameter, not from storage. Storage pointer `state` gives fresh reads. Same analysis as B10.

**Note:** `takeProfit` parameter is uint256 but `takeProfitValue` is `uint128(takeProfit)`. If `takeProfit > type(uint128).max`, the cast silently truncates. However, `takeProfit` represents ETH wei, and uint128 max is ~3.4e38 wei (~3.4e20 ETH) which far exceeds total ETH supply. Not exploitable.

**Verdict: SAFE**

### Attack Analysis
Same pattern as B10. All angles SAFE. The _deactivateAfKing path triggers when takeProfit is set to a value below AFKING_KEEP_MIN_ETH (5 ETH) but non-zero. This correctly deactivates afKing mode when take profit would be too low for afKing requirements. VERDICT: SAFE across all angles.

---

## DegenerusGame::setAfKingMode() (lines 1556-1564) [B13]

### Call Tree
```
setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit) [line 1556]
  +-- _resolvePlayer(player) [line 1562]
  +-- _setAfKingMode(player, enabled, ethTakeProfit, coinTakeProfit) [line 1563]
       +-- if rngLockedFlag: revert RngLocked [line 1572]
       +-- if !enabled: _deactivateAfKing(player) + return [lines 1573-1575]
       +-- if !_hasAnyLazyPass(player): revert E() [line 1577]
       +-- read autoRebuyState[player] via storage pointer [line 1579]
       +-- adjust ethKeep (clamp to AFKING_KEEP_MIN_ETH if non-zero) [lines 1580-1583]
       +-- adjust coinKeep (clamp to AFKING_KEEP_MIN_COIN if non-zero) [lines 1584-1587]
       +-- if !state.autoRebuyEnabled: write + emit [lines 1589-1591]
       +-- if state.takeProfit != adjustedEthKeep: write + emit [lines 1593-1595]
       +-- coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep) (external call) [line 1597]
       +-- if !state.afKingMode: [line 1599]
            +-- coinflip.settleFlipModeChange(player) (external call) [line 1600]
            +-- write state.afKingMode = true [line 1601]
            +-- write state.afKingActivatedLevel = level [line 1602]
            +-- emit AfKingModeToggled [line 1603]
```

### Storage Writes (Full Tree)
- `autoRebuyState[player].autoRebuyEnabled` (slot 25) -- written at line 1590 (conditional)
- `autoRebuyState[player].takeProfit` (slot 25) -- written at line 1594 (conditional)
- `autoRebuyState[player].afKingMode` (slot 25) -- written at line 1601 (conditional)
- `autoRebuyState[player].afKingActivatedLevel` (slot 25) -- written at line 1602 (conditional)
- (If disabling) `autoRebuyState[player].afKingMode` and `afKingActivatedLevel` via _deactivateAfKing

### Cached-Local-vs-Storage Check
Storage pointer `state` is used throughout. All reads are fresh SLOADs through the pointer.

**F-06: External call before state write.** At line 1597, `coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep)` is called before the `state.afKingMode = true` write at line 1601. If the coinflip call were to callback into Game and check `autoRebuyState[player].afKingMode`, it would see `false` (the old value). However, `coinflip.setCoinflipAutoRebuy` is a trusted contract call (COINFLIP is compile-time constant) and BurnieCoinflip does not callback to Game during setCoinflipAutoRebuy.

Similarly at line 1600, `coinflip.settleFlipModeChange(player)` is called before the state writes. Same trust assumption applies.

**VERDICT: INVESTIGATE (INFO)** -- External calls before state writes violate CEI pattern, but the callee is trusted and does not callback.

### Attack Analysis

**State Coherence:** Storage pointer reads are fresh. External calls to trusted contracts before state writes. VERDICT: SAFE (with trust assumption noted in F-06)

**Access Control:** _resolvePlayer + rngLocked guard. Lazy pass required for enabling (line 1577). VERDICT: SAFE

**RNG Manipulation:** Blocked during RNG lock. VERDICT: SAFE

**Cross-Contract State Desync:** The coinflip contract stores its own auto-rebuy state per player. The Game contract stores afKingMode. These must stay in sync. _setAfKingMode calls `coinflip.setCoinflipAutoRebuy` to set the coinflip side. If this external call reverts, the entire transaction reverts. VERDICT: SAFE

**Edge Cases:**
- Enabling without lazy pass: Reverts at line 1577. VERDICT: SAFE
- Already enabled (state.afKingMode == true): The activation block (lines 1599-1603) is skipped. Only takeProfit and autoRebuy fields are updated. VERDICT: SAFE
- Disabling with lock active: _deactivateAfKing reverts AfKingLockActive. VERDICT: SAFE

**Conditional Paths:**
- Enable path: Checks lazy pass, adjusts take profits, sets auto-rebuy on both Game and Coinflip, activates afKing with level stamp.
- Disable path: Calls _deactivateAfKing which checks lock period, settles coinflip, clears afKing state.
Both fully traced. VERDICT: SAFE

**Economic/MEV:** Player controls own afKing. Cannot manipulate others'. VERDICT: SAFE
**Griefing:** Cannot affect others. VERDICT: SAFE
**Ordering/Sequencing:** RNG lock prevents changes during sensitive windows. Lock period prevents rapid on/off cycling. VERDICT: SAFE
**Silent Failures:** None -- reverts on missing pass, locked RNG, active lock. VERDICT: SAFE

---

## DegenerusGame::deactivateAfKingFromCoin() (lines 1649-1655) [B14]

### Call Tree
```
deactivateAfKingFromCoin(player) [line 1649]
  +-- require msg.sender == COIN or COINFLIP [lines 1650-1653]
  +-- _deactivateAfKing(player) [line 1654]
       +-- (same as B10 call tree)
```

### Storage Writes (Full Tree)
- `autoRebuyState[player].afKingMode` (slot 25) -- at line 1687
- `autoRebuyState[player].afKingActivatedLevel` (slot 25) -- at line 1688

### Cached-Local-vs-Storage Check
Same as _deactivateAfKing analysis in B10.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** SAFE (same as B10)
**Access Control:** msg.sender must be COIN or COINFLIP. Compile-time constants. VERDICT: SAFE
**RNG Manipulation:** No rngLocked check here -- COIN/COINFLIP can deactivate afKing even during RNG lock. This is intentional: the coin/coinflip contracts need to deactivate afKing when the player's lazy pass expires during a coinflip operation. VERDICT: SAFE
**Cross-Contract State Desync:** Same as B10. VERDICT: SAFE
**Edge Cases:** Same as B10. VERDICT: SAFE
**Conditional Paths:** Same as B10. VERDICT: SAFE
**Economic/MEV:** Only trusted contracts can call. VERDICT: SAFE
**Griefing:** Only trusted contracts. VERDICT: SAFE
**Ordering/Sequencing:** No ordering issues. VERDICT: SAFE
**Silent Failures:** If afKing not active, _deactivateAfKing returns silently (line 1680). By design. VERDICT: SAFE

---

## DegenerusGame::syncAfKingLazyPassFromCoin() (lines 1662-1676) [B15]

### Call Tree
```
syncAfKingLazyPassFromCoin(player) [line 1662]
  +-- require msg.sender == COINFLIP [line 1665]
  +-- read autoRebuyState[player] via storage pointer [line 1666]
  +-- if !state.afKingMode: return false [line 1667]
  +-- _hasAnyLazyPass(player) [line 1668]
  |    +-- read deityPassCount[player] [line 1608]
  |    +-- if != 0: return true [line 1608]
  |    +-- read mintPacked_[player] >> FROZEN_UNTIL_LEVEL_SHIFT [line 1610-1612]
  |    +-- return frozenUntilLevel > level [line 1614]
  +-- if has pass: return true [line 1668]
  +-- write state.afKingMode = false [line 1672]
  +-- write state.afKingActivatedLevel = 0 [line 1673]
  +-- emit AfKingModeToggled [line 1674]
  +-- return false [line 1675]
```

### Storage Writes (Full Tree)
- `autoRebuyState[player].afKingMode` (slot 25) -- at line 1672
- `autoRebuyState[player].afKingActivatedLevel` (slot 25) -- at line 1673

### Cached-Local-vs-Storage Check
Storage pointer `state` is used for fresh reads. `_hasAnyLazyPass` reads `deityPassCount` and `mintPacked_` but does not write them. No descendant writes to any cached value.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** SAFE
**Access Control:** msg.sender must be COINFLIP only (line 1665). Not COIN, only COINFLIP. This is different from deactivateAfKingFromCoin which accepts both. The distinction is intentional: sync is called from coinflip deposit/claim paths. VERDICT: SAFE
**RNG Manipulation:** No rngLocked check (same reasoning as B14). VERDICT: SAFE
**Cross-Contract State Desync:** No external calls. Reads only local storage. VERDICT: SAFE
**Edge Cases:** If afKing not active, returns false immediately. If player has lazy pass, returns true without modifying state. VERDICT: SAFE
**Conditional Paths:** Three paths: afKing off (return false), has pass (return true), no pass (deactivate, return false). All correct. VERDICT: SAFE
**Economic/MEV:** Only COINFLIP can call. VERDICT: SAFE
**Griefing:** Only COINFLIP. VERDICT: SAFE
**Ordering/Sequencing:** Comment at line 1670 explains why settleFlipModeChange is not called here -- it's already being called by the coinflip operation that triggered this sync. VERDICT: SAFE
**Silent Failures:** Returns false when afKing not active -- by design. VERDICT: SAFE

---

## DegenerusGame::resolveRedemptionLootbox() (lines 1729-1779) [B16]

### Call Tree
```
resolveRedemptionLootbox(player, amount, rngWord, activityScore) [line 1729]
  +-- require msg.sender == SDGNRS [line 1735]
  +-- if amount == 0: return [line 1736]
  +-- read claimable = claimableWinnings[SDGNRS] [line 1743]
  +-- UNCHECKED: write claimableWinnings[SDGNRS] = claimable - amount [line 1744-1745]
  +-- write claimablePool -= amount [line 1747]
  +-- if prizePoolFrozen: [line 1750]
  |    +-- _getPendingPools() [line 1751]
  |    +-- _setPendingPools(pNext, pFuture + uint128(amount)) [line 1752]
  +-- else: [line 1753]
  |    +-- _getPrizePools() [line 1754]
  |    +-- _setPrizePools(next, future + uint128(amount)) [line 1755]
  +-- while remaining != 0: [line 1760]
       +-- box = min(remaining, 5 ether) [line 1761]
       +-- delegatecall to GAME_LOOTBOX_MODULE with resolveRedemptionLootbox.selector [lines 1762-1774]
       +-- remaining -= box [line 1776]
       +-- rngWord = keccak256(rngWord) [line 1777]
```

### Storage Writes (Full Tree)
- `claimableWinnings[SDGNRS]` (slot 9, mapping) -- written at line 1745 (unchecked subtraction)
- `claimablePool` (slot 10) -- written at line 1747
- `prizePoolsPacked` (slot 3) -- written via _setPrizePools at line 1755 (non-frozen path)
- `prizePoolPendingPacked` (slot 14) -- written via _setPendingPools at line 1752 (frozen path)
- (Via delegatecall to GAME_LOOTBOX_MODULE): Various lootbox-related storage writes (tickets, boons, etc.) -- these are module-internal

### Cached-Local-vs-Storage Check

**CRITICAL ANALYSIS:**

1. `claimable = claimableWinnings[SDGNRS]` cached at line 1743. Written back as `claimable - amount` at line 1745. No descendant writes to `claimableWinnings[SDGNRS]` BEFORE this writeback -- the writeback happens immediately after the read. The delegatecall loop (lines 1760-1778) happens AFTER. If the delegatecall to GAME_LOOTBOX_MODULE writes to `claimableWinnings[SDGNRS]`, the parent's writeback has already completed. Let me check: the loop calls `resolveRedemptionLootbox` on the lootbox module. Inside the module, does it credit claimableWinnings? The module resolves lootbox rewards -- this could credit `claimableWinnings[player]` (the player, NOT SDGNRS). So no BAF conflict.

2. Prize pools: `_getPrizePools()` / `_getPendingPools()` read and `_setPrizePools()` / `_setPendingPools()` write happen at lines 1750-1756, BEFORE the delegatecall loop. The delegatecall to GAME_LOOTBOX_MODULE could write to `prizePoolsPacked` or `prizePoolPendingPacked` (e.g., if lootbox resolution credits the future pool). If the module writes to these packed pools, the parent's earlier write would NOT be overwritten because the parent wrote BEFORE the loop, and the module would read the parent's already-written values.

   Wait -- the parent writes `future + uint128(amount)` to the prize pool at line 1755. Then the delegatecall module resolves a lootbox, which might also add to the future pool (for auto-rebuy, etc.). The module would read the already-updated pool (parent's write is visible), add its own contribution, and write back. This is correct -- there's no stale cache because the parent completed its write before the module runs.

   **Verdict: SAFE** -- Parent writes pools before delegatecall loop. Module reads fresh values.

3. `amount` is a parameter (not from storage), used for `claimablePool -= amount` at line 1747 and pool credit. No caching issue.

**F-01: Unchecked subtraction safety assumption.** Line 1744-1745 uses `unchecked { claimableWinnings[SDGNRS] = claimable - amount }`. The comment (lines 1739-1742) explains the mutual-exclusion argument: the only other path that drains `claimableWinnings[SDGNRS]` is `_deterministicBurnFrom -> game.claimWinnings()` which only fires at gameOver. This function is only called during active game. The two paths are claimed to be mutually exclusive.

However, if any other code path credits AND then debits `claimableWinnings[SDGNRS]` between the time funds were credited and this function is called, the `claimable >= amount` assumption could break. Since `claimableWinnings[SDGNRS]` is credited by jackpot distributions (in JackpotModule, EndgameModule, etc.) and debited only by claimWinnings or this function, and claimWinnings for SDGNRS only fires at gameOver (via claimWinningsStethFirst at line 1352), the mutual exclusion holds.

**VERDICT: INVESTIGATE (MEDIUM)** -- The unchecked subtraction is safe given the mutual-exclusion argument, but the safety depends on an invariant that spans multiple contracts. A future code change that introduces another debit path for `claimableWinnings[SDGNRS]` during active game would break this silently. The checked subtraction on `claimablePool` at line 1747 would catch this (would underflow and revert), providing a safety net. Flagging for Skeptic review of the mutual-exclusion argument.

**F-04: uint128 truncation.** At lines 1752 and 1755, `uint128(amount)` cast. If `amount > type(uint128).max`, truncation occurs. Same analysis as F-02/F-03: practically impossible since `amount` represents ETH in the contract. **VERDICT: INVESTIGATE (LOW)**

### Attack Analysis

**State Coherence:** Parent writes pools before delegatecall loop. No stale cache writeback. VERDICT: SAFE (with F-01 flagged for unchecked path)

**Access Control:** msg.sender must be SDGNRS (line 1735). Compile-time constant. VERDICT: SAFE

**RNG Manipulation:** `rngWord` is passed in and rotated via keccak256 in the loop (line 1777). The caller (SDGNRS) provides the initial rngWord from the VRF-derived redemption resolution. VERDICT: SAFE

**Cross-Contract State Desync:** The delegatecall to GAME_LOOTBOX_MODULE executes in Game's storage context. Module writes are directly to Game storage. No cross-contract desync. VERDICT: SAFE

**Edge Cases:**
- `amount == 0`: Returns immediately at line 1736. VERDICT: SAFE
- `amount < 5 ether`: Single loop iteration with box = amount. VERDICT: SAFE
- `amount == 5 ether`: Single iteration with box = 5 ether, remaining = 0. VERDICT: SAFE
- `amount > 5 ether`: Multiple iterations, 5 ETH each, last iteration with remainder. VERDICT: SAFE

**Conditional Paths:**
- prizePoolFrozen true: Routes to pending pools. VERDICT: SAFE
- prizePoolFrozen false: Routes to live pools. VERDICT: SAFE
- Multiple loop iterations: Each uses a different rngWord (keccak256 rotation). VERDICT: SAFE

**Economic/MEV:** Only callable by SDGNRS during redemption claim. VERDICT: SAFE
**Griefing:** Only SDGNRS can call. VERDICT: SAFE
**Ordering/Sequencing:** Called as part of sDGNRS claimRedemption flow. VERDICT: SAFE
**Silent Failures:** amount=0 returns silently. By design. VERDICT: SAFE

---

## DegenerusGame::adminSwapEthForStEth() (lines 1813-1824) [B17]

### Call Tree
```
adminSwapEthForStEth(recipient, amount) [line 1813]
  +-- require msg.sender == ADMIN [line 1817]
  +-- require recipient != address(0) [line 1818]
  +-- require amount != 0 && msg.value == amount [line 1819]
  +-- stBal = steth.balanceOf(this) (external view) [line 1821]
  +-- require stBal >= amount [line 1822]
  +-- steth.transfer(recipient, amount) (external call) [line 1823]
```

### Storage Writes (Full Tree)
None. No storage writes to DegenerusGame. Only external stETH transfer.

### Cached-Local-vs-Storage Check
No storage cached or written.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** No storage writes. VERDICT: SAFE
**Access Control:** Admin only. Admin trust assumption. VERDICT: SAFE
**RNG Manipulation:** No RNG. VERDICT: N/A
**Cross-Contract State Desync:** Admin sends ETH in (msg.value) and receives stETH out (steth.transfer). Value-neutral swap. The contract's ETH balance increases by `amount` and stETH balance decreases by `amount` (minus 1-2 wei rounding). VERDICT: SAFE
**Edge Cases:** Zero amount reverts. Zero recipient reverts. msg.value mismatch reverts. Insufficient stETH reverts. VERDICT: SAFE
**Conditional Paths:** Single path. VERDICT: SAFE
**Economic/MEV:** Admin-only, value-neutral. VERDICT: SAFE
**Griefing:** Admin-only. VERDICT: SAFE
**Ordering/Sequencing:** No ordering issues. VERDICT: SAFE
**Silent Failures:** All failures revert. VERDICT: SAFE

---

## DegenerusGame::adminStakeEthForStEth() (lines 1833-1853) [B18]

### Call Tree
```
adminStakeEthForStEth(amount) [line 1833]
  +-- require msg.sender == ADMIN [line 1834]
  +-- require amount != 0 [line 1835]
  +-- ethBal = address(this).balance [line 1837]
  +-- require ethBal >= amount [line 1838]
  +-- stethSettleable = claimableWinnings[VAULT] + claimableWinnings[SDGNRS] [lines 1840-1841]
  +-- reserve = claimablePool > stethSettleable ? claimablePool - stethSettleable : 0 [lines 1842-1844]
  +-- require ethBal > reserve [line 1845]
  +-- stakeable = ethBal - reserve [line 1846]
  +-- require amount <= stakeable [line 1847]
  +-- steth.submit{value: amount}(address(0)) (external call) [line 1850]
```

### Storage Writes (Full Tree)
None. Reads `claimableWinnings[VAULT]`, `claimableWinnings[SDGNRS]`, and `claimablePool` but does not write to any Game storage. The `steth.submit` call sends ETH and receives stETH.

### Cached-Local-vs-Storage Check
`stethSettleable` and `reserve` are computed from storage reads but not written back. No BAF pattern.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** No storage writes. VERDICT: SAFE

**Access Control:** Admin only. VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:** Reads `claimableWinnings` and `claimablePool` which could change if another transaction modifies them between the read and the steth.submit call. But within a single transaction, these values are stable. VERDICT: SAFE

**Edge Cases:**
- `claimablePool < stethSettleable`: reserve = 0, all ETH is stakeable. This happens when VAULT + SDGNRS claimable exceeds total claimablePool. In practice, this shouldn't happen because those claimables are a subset of claimablePool. If it did, reserve = 0 means the admin could stake all ETH, potentially leaving insufficient ETH for non-VAULT/SDGNRS claims. However, those claimants can receive stETH via the fallback mechanism in _payoutWithStethFallback. VERDICT: SAFE

**F-07:** `steth.submit` return value ignored (line 1850). Comment explains: Lido mints 1:1 for ETH. The 1-2 wei rounding from stETH rebasing is a known issue (per KNOWN-ISSUES.md: "stETH rounding strengthens invariant"). **VERDICT: INVESTIGATE (INFO)**

**Conditional Paths:** Single path with guards. VERDICT: SAFE
**Economic/MEV:** Admin-only. Cannot extract funds (value-preserving: ETH -> stETH). VERDICT: SAFE
**Griefing:** Admin-only. VERDICT: SAFE
**Ordering/Sequencing:** No ordering issues. VERDICT: SAFE
**Silent Failures:** steth.submit wrapped in try/catch; on failure, reverts E(). VERDICT: SAFE

---

## DegenerusGame::receive() (lines 2838-2847) [B19]

### Call Tree
```
receive() external payable [line 2838]
  +-- if gameOver: revert E() [line 2839]
  +-- if prizePoolFrozen: [line 2840]
  |    +-- _getPendingPools() [Storage line 665] -- read prizePoolPendingPacked
  |    +-- _setPendingPools(pNext, pFuture + uint128(msg.value)) [Storage line 661]
  +-- else: [line 2843]
       +-- _getPrizePools() [Storage line 655] -- read prizePoolsPacked
       +-- _setPrizePools(next, future + uint128(msg.value)) [Storage line 651]
```

### Storage Writes (Full Tree)
- `prizePoolsPacked` (slot 3) -- written via _setPrizePools at line 2845 (non-frozen)
- `prizePoolPendingPacked` (slot 14) -- written via _setPendingPools at line 2842 (frozen)

### Cached-Local-vs-Storage Check
`_getPrizePools()` and `_getPendingPools()` return fresh values from a single SLOAD each. The returned values are used to compute new values and immediately written back. No intervening calls between read and write.

**Verdict: SAFE**

### Attack Analysis

**State Coherence:** Single read-modify-write. No intervening calls. VERDICT: SAFE

**Access Control:** Anyone can send ETH. This is by design (allows donations to the prize pool). VERDICT: SAFE

**RNG Manipulation:** No RNG. VERDICT: N/A

**Cross-Contract State Desync:** No external calls. VERDICT: SAFE

**Edge Cases:**
- gameOver: Reverts. VERDICT: SAFE
- msg.value = 0: `uint128(0)` = 0, adds 0 to future pool. No-op but wastes gas. VERDICT: SAFE

**F-02: uint128 truncation.** `uint128(msg.value)` at lines 2842 and 2845. If `msg.value > type(uint128).max` (~3.4e38 wei = ~3.4e20 ETH), the cast silently truncates. The ETH would be received by the contract but only the truncated amount would be added to the pool. The difference would be stranded in the contract as untracked ETH. In practice, no one can send more than the total ETH supply (~120M ETH = ~1.2e26 wei), which is far below uint128 max. **VERDICT: INVESTIGATE (LOW)** -- Theoretically exploitable with astronomical ETH amounts (impossible in practice). The untracked ETH would eventually benefit players via yield surplus.

**Conditional Paths:**
- prizePoolFrozen true: Routes to pending pools. VERDICT: SAFE
- prizePoolFrozen false: Routes to live pools. VERDICT: SAFE

**Economic/MEV:** Donations increase the future prize pool for all players. A donation during frozen state routes to pending pools, which merge on unfreeze. No exploit vector. VERDICT: SAFE
**Griefing:** Sending ETH increases the pool, benefiting players. Cannot be used to grief. VERDICT: SAFE
**Ordering/Sequencing:** No ordering dependencies. VERDICT: SAFE
**Silent Failures:** None -- either reverts (gameOver) or succeeds. VERDICT: SAFE

---

## Part 2: Internal Helpers (Category C) -- Standalone Analysis

The following helpers were already analyzed as part of their callers' call trees in Part 1. For completeness, helpers with complex logic that warrant standalone discussion are noted here.

### _processMintPayment() (lines 929-988) [C1]
Fully analyzed in B2 (recordMint) call tree. Three payment mode branches, sentinel preservation, claimablePool accounting. No standalone findings beyond what B2 covers.

### _recordMintDataModule() (lines 1033-1049) [C2]
Fully analyzed in B2. Pure delegatecall to GAME_MINT_MODULE with recordMintData.selector. No pre/post logic beyond the standard dispatch pattern.

### _claimWinningsInternal() (lines 1361-1377) [C3]
Fully analyzed in B7 and B8. CEI pattern with sentinel, stETH/ETH payout routing.

### _setAutoRebuy() (lines 1491-1501) [C4]
Fully analyzed in B10. Storage pointer writes, conditional _deactivateAfKing.

### _setAutoRebuyTakeProfit() (lines 1503-1517) [C5]
Fully analyzed in B12. uint128 cast on takeProfit, conditional _deactivateAfKing when below minimum.

### _setAfKingMode() (lines 1566-1605) [C6]
Fully analyzed in B13. Multiple conditional writes, external calls to coinflip, activation level stamp.

### _deactivateAfKing() (lines 1678-1690) [C7]
Fully analyzed in B10, B12, B13, B14. Lock period check, coinflip settle, state clearing.

### _payoutWithStethFallback() (lines 1975-2003) [C16]
Fully analyzed in B7. ETH-first with stETH fallback, retry mechanism for edge cases.

### _payoutWithEthFallback() (lines 2008-2035) [C17]
Fully analyzed in B8. stETH-first with ETH fallback.

### _transferSteth() (lines 1960-1968) [C15]
Fully analyzed in B7 and B8. Special SDGNRS path (approve + depositSteth).

### _queueTickets() (Storage lines 528-549) [C18]
Fully analyzed in B1 (constructor). Far-future key space routing, rngLocked guard with phaseTransitionActive exemption. Ticket queue push and packed owed update.

### _queueTicketsScaled() (Storage lines 556-594) [C19]
Remainder accumulation with promotion to whole tickets when remainder >= TICKET_SCALE. Same far-future guard as _queueTickets.

### _queueTicketRange() (Storage lines 602-632) [C21]
Loop version of _queueTickets for contiguous level ranges. Caches `level` as `currentLevel` outside loop (line 609) to avoid repeated SLOADs. No write to `level` in the loop. SAFE.

### _setPrizePools() / _setPendingPools() (Storage lines 651-663) [C22/C23]
Pack two uint128 values into a single uint256. Pure write helpers.

### _setNextPrizePool() / _setFuturePrizePool() (Storage lines 740-755) [C27/C28]
Read-modify-write on prizePoolsPacked to update single component. Each reads the packed value, extracts the other component, and writes both back. No intervening calls. SAFE.

### _awardEarlybirdDgnrs() (Storage lines 914-974) [C29]
Fully analyzed in B2. Quadratic emission curve, external calls to dgnrs for token transfers/pool moves.

### _recordMintStreakForLevel() (MintStreakUtils lines 17-46) [C32]
Fully analyzed in B3. Read-modify-write on mintPacked_ with idempotent guard.

---

## Part 3: Delegatecall Dispatch Verification (Category A)

---

## DegenerusGame::advanceGame() [DISPATCH] (lines 308-317) [A1]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ADVANCE_MODULE` = `0xA4AD4f68d0b91CFD19687c881e50f3A00242828c`
- Selector encoded: `IDegenerusGameAdvanceModule.advanceGame.selector`
- Parameters forwarded: None (no parameters)
- Return value decoded: No (result ignored, only revert propagation)
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (module checks internally -- tiered daily gate, liveness guards)

### Verdict: CORRECT

---

## DegenerusGame::wireVrf() [DISPATCH] (lines 332-348) [A2]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ADVANCE_MODULE` = `0xA4AD4f68d0b91CFD19687c881e50f3A00242828c`
- Selector encoded: `IDegenerusGameAdvanceModule.wireVrf.selector`
- Parameters forwarded: `coordinator_` (address), `subId` (uint256), `keyHash_` (bytes32) -- matches interface signature
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (admin check in module)

### Verdict: CORRECT

---

## DegenerusGame::updateVrfCoordinatorAndSub() [DISPATCH] (lines 1880-1898) [A3]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ADVANCE_MODULE`
- Selector encoded: `IDegenerusGameAdvanceModule.updateVrfCoordinatorAndSub.selector`
- Parameters forwarded: `newCoordinator` (address), `newSubId` (uint256), `newKeyHash` (bytes32) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (admin check in module)

### Verdict: CORRECT

---

## DegenerusGame::requestLootboxRng() [DISPATCH] (lines 1903-1912) [A4]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ADVANCE_MODULE`
- Selector encoded: `IDegenerusGameAdvanceModule.requestLootboxRng.selector`
- Parameters forwarded: None
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (module checks internally)

### Verdict: CORRECT

---

## DegenerusGame::reverseFlip() [DISPATCH] (lines 1920-1929) [A5]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ADVANCE_MODULE`
- Selector encoded: `IDegenerusGameAdvanceModule.reverseFlip.selector`
- Parameters forwarded: None
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (module checks internally)

### Verdict: CORRECT

---

## DegenerusGame::rawFulfillRandomWords() [DISPATCH] (lines 1937-1951) [A6]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ADVANCE_MODULE`
- Selector encoded: `IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector`
- Parameters forwarded: `requestId` (uint256), `randomWords` (uint256[] calldata) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (VRF coordinator address check in module)

### Verdict: CORRECT

---

## DegenerusGame::purchase() [DISPATCH] (lines 534-549) [A7]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_MINT_MODULE` (via _purchaseFor)
- Selector encoded: `IDegenerusGameMintModule.purchase.selector`
- Parameters forwarded: `buyer` (address, resolved), `ticketQuantity` (uint256), `lootBoxAmount` (uint256), `affiliateCode` (bytes32), `payKind` (MintPaymentKind) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `buyer = _resolvePlayer(buyer)` at line 541 (pre-dispatch player resolution)
- Access control owner: ROUTER (_resolvePlayer checks operator approval)

### Verdict: CORRECT

---

## DegenerusGame::purchaseCoin() [DISPATCH] (lines 579-596) [A8]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_MINT_MODULE`
- Selector encoded: `IDegenerusGameMintModule.purchaseCoin.selector`
- Parameters forwarded: `buyer` (address, resolved), `ticketQuantity` (uint256), `lootBoxBurnieAmount` (uint256) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `buyer = _resolvePlayer(buyer)` at line 584
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::purchaseBurnieLootbox() [DISPATCH] (lines 601-616) [A9]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_MINT_MODULE`
- Selector encoded: `IDegenerusGameMintModule.purchaseBurnieLootbox.selector`
- Parameters forwarded: `buyer` (address, resolved), `burnieAmount` (uint256) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `buyer = _resolvePlayer(buyer)` at line 605
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::purchaseWhaleBundle() [DISPATCH] (lines 632-638) [A10]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_WHALE_MODULE` (via _purchaseWhaleBundleFor)
- Selector encoded: `IDegenerusGameWhaleModule.purchaseWhaleBundle.selector`
- Parameters forwarded: `buyer` (address, resolved), `quantity` (uint256) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `buyer = _resolvePlayer(buyer)` at line 636
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::purchaseLazyPass() [DISPATCH] (lines 657-660) [A11]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_WHALE_MODULE` (via _purchaseLazyPassFor)
- Selector encoded: `IDegenerusGameWhaleModule.purchaseLazyPass.selector`
- Parameters forwarded: `buyer` (address, resolved) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `buyer = _resolvePlayer(buyer)` at line 658
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::purchaseDeityPass() [DISPATCH] (lines 677-680) [A12]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_WHALE_MODULE` (via _purchaseDeityPassFor)
- Selector encoded: `IDegenerusGameWhaleModule.purchaseDeityPass.selector`
- Parameters forwarded: `buyer` (address, resolved), `symbolId` (uint8) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `buyer = _resolvePlayer(buyer)` at line 678
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::openLootBox() [DISPATCH] (lines 698-701) [A13]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_LOOTBOX_MODULE` (via _openLootBoxFor)
- Selector encoded: `IDegenerusGameLootboxModule.openLootBox.selector`
- Parameters forwarded: `player` (address, resolved), `lootboxIndex` (uint48) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `player = _resolvePlayer(player)` at line 699
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::openBurnieLootBox() [DISPATCH] (lines 706-709) [A14]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_LOOTBOX_MODULE` (via _openBurnieLootBoxFor)
- Selector encoded: `IDegenerusGameLootboxModule.openBurnieLootBox.selector`
- Parameters forwarded: `player` (address, resolved), `lootboxIndex` (uint48) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `player = _resolvePlayer(player)` at line 707
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::placeFullTicketBets() [DISPATCH] (lines 747-771) [A15]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DEGENERETTE_MODULE`
- Selector encoded: `IDegenerusGameDegeneretteModule.placeFullTicketBets.selector`
- Parameters forwarded: `_resolvePlayer(player)` (address, resolved inline), `currency` (uint8), `amountPerTicket` (uint128), `ticketCount` (uint8), `customTicket` (uint32), `heroQuadrant` (uint8) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `_resolvePlayer(player)` called inline in abi.encodeWithSelector (line 762)
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::resolveDegeneretteBets() [DISPATCH] (lines 776-790) [A16]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DEGENERETTE_MODULE`
- Selector encoded: `IDegenerusGameDegeneretteModule.resolveBets.selector`
- Parameters forwarded: `_resolvePlayer(player)` (address, resolved inline), `betIds` (uint64[] calldata) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `_resolvePlayer(player)` inline (line 785)
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::consumeCoinflipBoon() [DISPATCH] (lines 797-814) [A17]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_BOON_MODULE`
- Selector encoded: `IDegenerusGameBoonModule.consumeCoinflipBoon.selector`
- Parameters forwarded: `player` (address) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint16))` at line 813 returns `boostBps`
- Pre/post-delegatecall code: Access control check at lines 800-803 (msg.sender == COIN or COINFLIP)
- Access control owner: ROUTER (msg.sender check before dispatch)

### Verdict: CORRECT

---

## DegenerusGame::consumeDecimatorBoon() [DISPATCH] (lines 821-835) [A18]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_BOON_MODULE`
- Selector encoded: `IDegenerusGameBoonModule.consumeDecimatorBoost.selector` (line 829)
- Parameters forwarded: `player` (address) -- matches interface for `consumeDecimatorBoost`
- Return value decoded: Yes -- `abi.decode(data, (uint16))` at line 834 returns `boostBps`
- Pre/post-delegatecall code: Access control check at line 824 (msg.sender == COIN only)
- Access control owner: ROUTER

**NAME/SELECTOR MISMATCH INVESTIGATION:** The router function is named `consumeDecimatorBoon` but dispatches to `IDegenerusGameBoonModule.consumeDecimatorBoost.selector`. Checking the interface at IDegenerusGameModules.sol line 355: `function consumeDecimatorBoost(address player) external returns (uint16 boostBps)`. The selector is correctly encoded from the interface. The BoonModule implements `consumeDecimatorBoost`. The name difference between the router (`Boon`) and the module (`Boost`) is cosmetic -- the selector is what matters for dispatch, and it is correctly wired.

### Verdict: CORRECT (name mismatch is cosmetic, selector is correct)

---

## DegenerusGame::consumePurchaseBoost() [DISPATCH] (lines 842-856) [A19]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_BOON_MODULE`
- Selector encoded: `IDegenerusGameBoonModule.consumePurchaseBoost.selector`
- Parameters forwarded: `player` (address) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint16))`
- Pre/post-delegatecall code: Access control at line 845 (msg.sender == address(this))
- Access control owner: ROUTER (self-call only)

### Verdict: CORRECT

---

## DegenerusGame::issueDeityBoon() [DISPATCH] (lines 894-912) [A20]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_LOOTBOX_MODULE`
- Selector encoded: `IDegenerusGameLootboxModule.issueDeityBoon.selector`
- Parameters forwarded: `deity` (address, resolved), `recipient` (address), `slot` (uint8) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `deity = _resolvePlayer(deity)` at line 899; self-issue check at line 900 (`if recipient == deity revert E()`)
- Access control owner: ROUTER (resolvePlayer + self-issue block)

### Verdict: CORRECT

---

## DegenerusGame::recordDecBurn() [DISPATCH] (lines 1063-1085) [A21]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DECIMATOR_MODULE`
- Selector encoded: `IDegenerusGameDecimatorModule.recordDecBurn.selector`
- Parameters forwarded: `player` (address), `lvl` (uint24), `bucket` (uint8), `baseAmount` (uint256), `multBps` (uint256) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint8))` returns `bucketUsed`; also checks `data.length == 0` at line 1083
- Pre/post-delegatecall code: NONE (no router-level access control; module checks COIN)
- Access control owner: MODULE (module checks msg.sender == COIN)

### Verdict: CORRECT

---

## DegenerusGame::runDecimatorJackpot() [DISPATCH] (lines 1093-1112) [A22]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DECIMATOR_MODULE`
- Selector encoded: `IDegenerusGameDecimatorModule.runDecimatorJackpot.selector`
- Parameters forwarded: `poolWei` (uint256), `lvl` (uint24), `rngWord` (uint256) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint256))` returns `returnAmountWei`; `data.length == 0` check
- Pre/post-delegatecall code: Self-call check at line 1098 (msg.sender == address(this))
- Access control owner: ROUTER (self-call only)

### Verdict: CORRECT

---

## DegenerusGame::recordTerminalDecBurn() [DISPATCH] (lines 1120-1136) [A23]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DECIMATOR_MODULE`
- Selector encoded: `IDegenerusGameDecimatorModule.recordTerminalDecBurn.selector`
- Parameters forwarded: `player` (address), `lvl` (uint24), `baseAmount` (uint256) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (module checks COIN)

### Verdict: CORRECT

---

## DegenerusGame::runTerminalDecimatorJackpot() [DISPATCH] (lines 1140-1159) [A24]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DECIMATOR_MODULE`
- Selector encoded: `IDegenerusGameDecimatorModule.runTerminalDecimatorJackpot.selector`
- Parameters forwarded: `poolWei` (uint256), `lvl` (uint24), `rngWord` (uint256) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint256))`; `data.length == 0` check
- Pre/post-delegatecall code: Self-call check at line 1145
- Access control owner: ROUTER (self-call only)

### Verdict: CORRECT

---

## DegenerusGame::runTerminalJackpot() [DISPATCH] (lines 1176-1195) [A25]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_JACKPOT_MODULE`
- Selector encoded: `IDegenerusGameJackpotModule.runTerminalJackpot.selector`
- Parameters forwarded: `poolWei` (uint256), `targetLvl` (uint24), `rngWord` (uint256) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint256))`; `data.length == 0` check
- Pre/post-delegatecall code: Self-call check at line 1181
- Access control owner: ROUTER (self-call only)

### Verdict: CORRECT

---

## DegenerusGame::consumeDecClaim() [DISPATCH] (lines 1202-1219) [A26]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DECIMATOR_MODULE`
- Selector encoded: `IDegenerusGameDecimatorModule.consumeDecClaim.selector`
- Parameters forwarded: `player` (address), `lvl` (uint24) -- matches interface
- Return value decoded: Yes -- `abi.decode(data, (uint256))`; `data.length == 0` check
- Pre/post-delegatecall code: Self-call check at line 1206
- Access control owner: ROUTER (self-call only)

### Verdict: CORRECT

---

## DegenerusGame::claimDecimatorJackpot() [DISPATCH] (lines 1223-1235) [A27]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_DECIMATOR_MODULE`
- Selector encoded: `IDegenerusGameDecimatorModule.claimDecimatorJackpot.selector`
- Parameters forwarded: `lvl` (uint24) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: MODULE (module checks msg.sender internally for claim authorization)

### Verdict: CORRECT

---

## DegenerusGame::claimWhalePass() [DISPATCH] (lines 1700-1703) [A28]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_ENDGAME_MODULE` (via _claimWhalePassFor)
- Selector encoded: `IDegenerusGameEndgameModule.claimWhalePass.selector`
- Parameters forwarded: `player` (address, resolved) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: `player = _resolvePlayer(player)` at line 1701
- Access control owner: ROUTER

### Verdict: CORRECT

---

## DegenerusGame::_recordMintDataModule() [DISPATCH] (lines 1033-1049) [A29]

### Dispatch Verification
- Module address: `ContractAddresses.GAME_MINT_MODULE`
- Selector encoded: `IDegenerusGameMintModule.recordMintData.selector`
- Parameters forwarded: `player` (address), `lvl` (uint24), `mintUnits` (uint32) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: NONE
- Access control owner: ROUTER (private function, callable only from recordMint which requires self-call)

### Verdict: CORRECT

---

## DegenerusGame::resolveRedemptionLootbox() [DISPATCH] (lines 1729-1779) [A30] -- HYBRID

### Dispatch Verification (delegatecall portion, lines 1760-1778)
- Module address: `ContractAddresses.GAME_LOOTBOX_MODULE`
- Selector encoded: `IDegenerusGameLootboxModule.resolveRedemptionLootbox.selector`
- Parameters forwarded: `player` (address), `box` (uint256, chunked amount), `rngWord` (uint256, rotated per iteration), `activityScore` (uint16) -- matches interface
- Return value decoded: No
- Pre/post-delegatecall code: YES -- significant pre-dispatch code (lines 1735-1756: access control, claimable debit, pool credit). Post-dispatch: `remaining -= box` and `rngWord = keccak256(rngWord)`.
- Access control owner: ROUTER (msg.sender == SDGNRS at line 1735)

Full state-change analysis in Part 1, section B16.

### Verdict: CORRECT (dispatch portion correct; state-change analysis in B16)

---

## Summary of Dispatch Verification

| # | Function | Module | Selector Match | Params Match | Return Decoded | Access Control | Verdict |
|---|----------|--------|---------------|-------------|----------------|---------------|---------|
| A1 | advanceGame | ADVANCE | YES | N/A (none) | No | MODULE | CORRECT |
| A2 | wireVrf | ADVANCE | YES | YES (3) | No | MODULE | CORRECT |
| A3 | updateVrfCoordinatorAndSub | ADVANCE | YES | YES (3) | No | MODULE | CORRECT |
| A4 | requestLootboxRng | ADVANCE | YES | N/A (none) | No | MODULE | CORRECT |
| A5 | reverseFlip | ADVANCE | YES | N/A (none) | No | MODULE | CORRECT |
| A6 | rawFulfillRandomWords | ADVANCE | YES | YES (2) | No | MODULE | CORRECT |
| A7 | purchase | MINT | YES | YES (5) | No | ROUTER | CORRECT |
| A8 | purchaseCoin | MINT | YES | YES (3) | No | ROUTER | CORRECT |
| A9 | purchaseBurnieLootbox | MINT | YES | YES (2) | No | ROUTER | CORRECT |
| A10 | purchaseWhaleBundle | WHALE | YES | YES (2) | No | ROUTER | CORRECT |
| A11 | purchaseLazyPass | WHALE | YES | YES (1) | No | ROUTER | CORRECT |
| A12 | purchaseDeityPass | WHALE | YES | YES (2) | No | ROUTER | CORRECT |
| A13 | openLootBox | LOOTBOX | YES | YES (2) | No | ROUTER | CORRECT |
| A14 | openBurnieLootBox | LOOTBOX | YES | YES (2) | No | ROUTER | CORRECT |
| A15 | placeFullTicketBets | DEGENERETTE | YES | YES (6) | No | ROUTER | CORRECT |
| A16 | resolveDegeneretteBets | DEGENERETTE | YES | YES (2) | No | ROUTER | CORRECT |
| A17 | consumeCoinflipBoon | BOON | YES | YES (1) | YES (uint16) | ROUTER | CORRECT |
| A18 | consumeDecimatorBoon | BOON | YES* | YES (1) | YES (uint16) | ROUTER | CORRECT |
| A19 | consumePurchaseBoost | BOON | YES | YES (1) | YES (uint16) | ROUTER | CORRECT |
| A20 | issueDeityBoon | LOOTBOX | YES | YES (3) | No | ROUTER | CORRECT |
| A21 | recordDecBurn | DECIMATOR | YES | YES (5) | YES (uint8) | MODULE | CORRECT |
| A22 | runDecimatorJackpot | DECIMATOR | YES | YES (3) | YES (uint256) | ROUTER | CORRECT |
| A23 | recordTerminalDecBurn | DECIMATOR | YES | YES (3) | No | MODULE | CORRECT |
| A24 | runTerminalDecimatorJackpot | DECIMATOR | YES | YES (3) | YES (uint256) | ROUTER | CORRECT |
| A25 | runTerminalJackpot | JACKPOT | YES | YES (3) | YES (uint256) | ROUTER | CORRECT |
| A26 | consumeDecClaim | DECIMATOR | YES | YES (2) | YES (uint256) | ROUTER | CORRECT |
| A27 | claimDecimatorJackpot | DECIMATOR | YES | YES (1) | No | MODULE | CORRECT |
| A28 | claimWhalePass | ENDGAME | YES | YES (1) | No | ROUTER | CORRECT |
| A29 | _recordMintDataModule | MINT | YES | YES (3) | No | ROUTER | CORRECT |
| A30 | resolveRedemptionLootbox | LOOTBOX | YES | YES (4) | No | ROUTER | CORRECT |

*A18: Router name `consumeDecimatorBoon` dispatches to `consumeDecimatorBoost.selector`. Name mismatch is cosmetic; selector is correctly wired to the module's `consumeDecimatorBoost` function.

**30/30 dispatchers: CORRECT.**
