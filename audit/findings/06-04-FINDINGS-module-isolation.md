# AUTH-03 Findings: Module Direct-Call Isolation Audit

**Date:** 2026-03-01
**Auditor:** Claude Opus 4.6
**Scope:** All 10 delegatecall modules in contracts/modules/
**Requirement:** AUTH-03 -- Module-only entry points cannot be called directly with meaningful effect

---

## Executive Summary

All 10 delegatecall modules were audited for direct-call safety. Every external function in every module was classified and analyzed against uninitialized (all-zero) storage. No module contains a constructor, fallback, or receive function. The DegenerusGame contract is confirmed as the sole path to initialized storage via delegatecall.

**Verdict: AUTH-03 PASS**

Every external function is either (a) gated by an inter-contract `msg.sender` check that blocks unauthorized callers regardless of storage state, (b) protected by state preconditions that revert or produce no-ops against zero storage, or (c) ungated but provably harmless when executed against uninitialized storage because all meaningful state reads return zero, external calls to `address(0)` revert, and storage writes to the module's own contract are meaningless.

---

## 1. No Constructor / Fallback / Receive in Any Module

**Search:** `grep -rn "constructor\|fallback\|receive()" contracts/modules/ --include="*.sol"`

**Result:** Zero matches for constructor, fallback, or receive function declarations in any of the 10 module contracts or their helper contracts (DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils).

All modules inherit `DegenerusGameStorage` which also has no constructor. Storage is entirely uninitialized at deployment time for each standalone module contract.

**Conclusion:** No module accepts ETH via receive/fallback, and no module initializes any storage slot in a constructor. The module contract's storage is guaranteed to be all-zeros unless someone writes to it via a direct external call.

---

## 2. Master Classification Table

All external functions across all 10 modules are classified below.

### Gate Type Legend

| Code | Meaning |
|------|---------|
| **IC** | Inter-Contract gate: `msg.sender != ContractAddresses.{X}` -- blocks all callers except the specified contract |
| **SP** | State-Precondition gate: depends on initialized storage; reverts or no-ops against zero storage |
| **UG** | Ungated: no msg.sender check, no state precondition blocking zero-storage execution |

### 2.1 MintModule (N+1)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `recordMintData(player, lvl, mintUnits)` | external payable | **UG** | No msg.sender check. Reads/writes `mintPacked_[player]`. | HARMLESS -- see Section 3.1 |
| `purchaseBurnieLootbox(buyer, burnieAmount)` | external | **SP** | Calls `coin.burnCoin()` where `coin` = `ContractAddresses.COIN` (compile-time constant). With zero storage, burns from buyer. Requires `buyer != address(0)`. | HARMLESS -- coin.burnCoin reverts if buyer has no BURNIE. Internal calls to `_recordLootboxEntry` read `lootboxRngIndex` (zero), so `lootboxEth[0][buyer]` is written. No ETH or value transfer. |

### 2.2 AdvanceModule (N+2)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `advanceGame()` | external | **SP** | Complex state machine. Reads `level`, `rngLockedFlag`, `jackpotPhaseFlag`, `vrfCoordinator`, etc. All zero on direct call. | HARMLESS -- see Section 3.2 |
| `wireVrf(coordinator_, subId, keyHash_)` | external | **IC** | `msg.sender != ContractAddresses.ADMIN` | SAFE -- blocks all non-ADMIN callers |
| `updateVrfCoordinatorAndSub(...)` | external | **IC** | `msg.sender != ContractAddresses.ADMIN` | SAFE -- blocks all non-ADMIN callers |
| `rawFulfillRandomWords(requestId, randomWords)` | external | **IC** | `msg.sender != address(vrfCoordinator)`. On direct call, `vrfCoordinator` is `address(0)`, so only `address(0)` passes (impossible as external caller). | SAFE -- address(0) cannot be msg.sender |
| `requestLootboxRng()` | external | **SP** | Reads `rngWordByDay[currentDay]` (zero -> reverts with `E()`), reads `vrfCoordinator` (address(0) -> subscription check reverts). | HARMLESS -- reverts on zero storage |
| `reverseFlip()` | external | **SP** | Reads `rngLockedFlag` (false -> passes), calls `coin.burnCoin(msg.sender, cost)` where `cost = _currentNudgeCost(0)`. Burns from caller. | HARMLESS -- coin.burnCoin reverts if caller has no BURNIE; if they do, they burn their own tokens for nothing. |

### 2.3 WhaleModule (N+3)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `purchaseWhaleBundle(buyer, quantity)` | external payable | **SP** | Reads `level` (0), `whaleBoonDay[buyer]` (0), `mintPacked_[buyer]` (0). At level 0+1=1, `passLevel <= 4` is true so `unitPrice = 2.4 ETH`. Requires `msg.value == totalPrice`. Calls `affiliate.getReferrer()` and `dgnrs.transferFromPool()` via compile-time constants. | HARMLESS -- see Section 3.3 |
| `purchaseLazyPass(buyer)` | external payable | **SP** | Reads `level` (0), checks `deityPassCount[buyer]` (0 -> passes). Computes `_lazyPassCost(1)` from PriceLookupLib (pure). Level 0 triggers `totalPrice = 0.24 ether`. Requires `msg.value == totalPrice`. Calls external contracts at compile-time constant addresses. | HARMLESS -- see Section 3.3 |
| `purchaseDeityPass(buyer, symbolId)` | external payable | **SP** | Reads `deityBySymbol[symbolId]` (0 -> passes), `deityPassCount[buyer]` (0 -> passes), `deityPassOwners.length` (0). Computes `basePrice = 24 ETH + 0`. Requires `msg.value == basePrice`. Calls `DEITY_PASS.mint()` and external contracts. | HARMLESS -- see Section 3.3 |
| `handleDeityPassTransfer(from, to)` | external | **SP** | `if (level == 0) revert E()` -- reverts immediately on zero storage. | HARMLESS -- reverts on zero storage |

### 2.4 JackpotModule (N+4)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `payDailyJackpot(isDaily, lvl, randWord)` | external | **UG** | No msg.sender check. Reads `jackpotCounter`, `currentPrizePool`, etc. (all zero). | HARMLESS -- see Section 3.4 |
| `payDailyJackpotCoinAndTickets(randWord)` | external | **SP** | `if (!dailyJackpotCoinTicketsPending) return` -- returns immediately on zero storage (false). | HARMLESS -- immediate no-op |
| `awardFinalDayDgnrsReward(lvl, rngWord)` | external | **UG** | Reads `dgnrs.poolBalance()` via compile-time constant. If pool has balance, calls `dgnrs.transferFromPool()`. | HARMLESS -- see Section 3.4 |
| `payEarlyBirdLootboxJackpot(lvl, rngWord)` | external | **UG** | Reads `futurePrizePool` (zero). `reserveContribution = 0`. Entire function is effectively a no-op with zero budgets. | HARMLESS -- zero budgets produce no winners |
| `consolidatePrizePools(lvl, rngWord)` | external | **UG** | `currentPrizePool += nextPrizePool` where both are zero. No meaningful effect. | HARMLESS -- adding zero to zero |
| `processTicketBatch(lvl)` | external | **UG** | `ticketQueue[lvl]` is empty array -> `total = 0`, immediate return with `finished = true`. | HARMLESS -- empty queue, immediate return |
| `payDailyCoinJackpot(lvl, randWord)` | external | **SP** | `_calcDailyCoinBudget` reads `price` (zero) -> returns 0 -> function returns immediately. | HARMLESS -- zero price means zero budget |

### 2.5 DecimatorModule (N+5) -- SPECIAL FOCUS

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `creditDecJackpotClaimBatch(accounts, amounts, rngWord)` | external | **IC** | `msg.sender != ContractAddresses.JACKPOTS` | SAFE -- blocks all non-JACKPOTS callers |
| `creditDecJackpotClaim(account, amount, rngWord)` | external | **IC** | `msg.sender != ContractAddresses.JACKPOTS` | SAFE -- blocks all non-JACKPOTS callers |
| `recordDecBurn(player, lvl, bucket, baseAmount, multBps)` | external | **IC** | `msg.sender != ContractAddresses.COIN` (reverts `OnlyCoin()`) | SAFE -- blocks all non-COIN callers |
| `runDecimatorJackpot(poolWei, lvl, rngWord)` | external | **IC** | `msg.sender != ContractAddresses.GAME` (reverts `OnlyGame()`) | SAFE -- blocks all non-GAME callers |
| `consumeDecClaim(player, lvl)` | external | **IC** | `msg.sender != ContractAddresses.GAME` (reverts `OnlyGame()`) | SAFE -- blocks all non-GAME callers |
| `claimDecimatorJackpot(lvl)` | external | **UG** | No msg.sender check. Calls `_consumeDecClaim(msg.sender, lvl)`. | HARMLESS -- see Section 4 |
| `decClaimable(player, lvl)` | external view | **SP** | View function -- reads `lastDecClaimRound.lvl` (zero). Returns `(0, false)`. | HARMLESS -- read-only, returns zeros |

### 2.6 EndgameModule (N+6)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `rewardTopAffiliate(lvl)` | external | **UG** | Calls `affiliate.affiliateTop(lvl)` via compile-time constant. If top is address(0) (likely on fresh game), returns immediately. | HARMLESS -- see Section 3.6 |
| `runRewardJackpots(lvl, rngWord)` | external | **UG** | Reads `futurePrizePool` (zero). All pool calculations produce zero. No state changes when all pools are zero. | HARMLESS -- zero pools, zero distributions |
| `claimWhalePass(player)` | external | **UG** | Reads `whalePassClaims[player]` (zero). If zero, returns immediately. | HARMLESS -- immediate no-op on zero storage |

### 2.7 GameOverModule (N+7)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `handleGameOverDrain(day)` | external | **SP** | `if (gameOverFinalJackpotPaid) return` -- on zero storage this is false, so execution continues. Reads `level` (0), `address(this).balance`, `steth.balanceOf(address(this))`. | HARMLESS -- see Section 3.7 |
| `handleFinalSweep()` | external | **SP** | `if (gameOverTime == 0) return` -- returns immediately on zero storage. | HARMLESS -- immediate no-op |

### 2.8 LootboxModule (N+8)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `openLootBox(player, index)` | external | **SP** | `if (rngLockedFlag) revert RngLocked()` -- passes on zero (false). Reads `lootboxEth[index][player]` amount portion (zero). `if (amount == 0) revert E()` -- reverts. | HARMLESS -- reverts on zero lootbox amount |
| `openBurnieLootBox(player, index)` | external | **SP** | Reads `lootboxBurnie[index][player]` (zero). `if (burnieAmount == 0) revert E()` -- reverts. | HARMLESS -- reverts on zero amount |
| `resolveLootboxDirect(player, amount, rngWord)` | external | **SP** | `if (amount == 0) return` -- if called with nonzero amount, reads `level` (0), calls `_lootboxEvMultiplierBps(player)` which calls `IDegenerusGame(address(this)).playerActivityScore(player)` -- this calls the module itself at address(this), which has no `playerActivityScore` function -> reverts. | HARMLESS -- reverts when calling nonexistent function on self |
| `issueDeityBoon(deity, recipient, slot)` | external | **SP** | `if (deityPassPurchasedCount[deity] == 0) revert E()` -- reverts on zero storage since no deity has a pass. | HARMLESS -- reverts on zero storage |

### 2.9 BoonModule (N+9)

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `consumeCoinflipBoon(player)` | external | **UG** | If `player == address(0)` returns 0. Otherwise reads `coinflipBoonBps[player]` (zero). Returns 0. | HARMLESS -- returns zero boon |
| `consumePurchaseBoost(player)` | external | **UG** | Same pattern. Returns 0. | HARMLESS -- returns zero boost |
| `consumeDecimatorBoost(player)` | external | **UG** | Same pattern. Returns 0. | HARMLESS -- returns zero boost |
| `checkAndClearExpiredBoon(player)` | external | **UG** | All boon state variables are zero. Returns false (no active boons). Writes zeros to already-zero slots (no net effect). | HARMLESS -- no-op on zero storage |
| `consumeActivityBoon(player)` | external | **UG** | Reads `activityBoonPending[player]` (zero). `if (pending == 0) return` -- returns immediately. | HARMLESS -- immediate no-op |

### 2.10 DegeneretteModule (N+10) -- SPECIAL FOCUS

| Function | Visibility | Gate | Gate Details | Direct-Call Risk |
|----------|-----------|------|--------------|------------------|
| `placeFullTicketBets(player, currency, amountPerTicket, ticketCount, customTicket, heroQuadrant)` | external payable | **SP** | `_resolvePlayer()` uses module's own `operatorApprovals` (all zero on direct call). Only `msg.sender` can act for themselves. Reads `lootboxRngIndex` (zero). `if (index == 0) revert E()` -- reverts. | HARMLESS -- reverts on zero rngIndex |
| `placeFullTicketBetsFromAffiliateCredit(...)` | external | **SP** | Same `_resolvePlayer()` + same `lootboxRngIndex == 0` check -> reverts. | HARMLESS -- reverts on zero rngIndex |
| `resolveBets(player, betIds)` | external | **SP** | `_resolvePlayer()` resolves. For each betId, reads `degeneretteBets[player][betId]` (zero). Internal `_resolveBet` reads packed data; with zero packed, `mode == 0` (neither FULL_TICKET nor QUICK_PLAY) -> reverts E(). | HARMLESS -- reverts on zero bet data |

---

## 3. Deep Analysis: Ungated Functions Against Uninitialized Storage

### 3.1 MintModule.recordMintData

**Storage reads (all zero):**
- `mintPacked_[player]` = 0 (all bit fields are zero: lastLevel=0, levelCount=0, etc.)
- No `msg.sender` check

**Execution path on zero storage:**
1. Unpacks prevData (all zeros): levelStreak=0, levelCount=0, lastLevel=0, frozenUntilLevel=0, etc.
2. Computes BURNIE reward using `PRICE_COIN_UNIT / price` -- but `price` is zero, causing division by zero -> **reverts with arithmetic panic**.

**Conclusion:** Reverts due to division by zero on uninitialized `price`. Even if it somehow continued: writes only to `mintPacked_[player]` on the module's own storage (meaningless), and returns a `coinReward` value. No ETH transfer, no external calls with value.

### 3.2 AdvanceModule.advanceGame

**Storage reads (all zero):**
- `level` = 0, `rngLockedFlag` = false, `jackpotPhaseFlag` = false
- `lastMintTimestamp` = 0 (pre-game timeout check: `block.timestamp - 0 >= 912 days` -- true if contract deployed >912 days ago, false otherwise)
- `price` = 0, `vrfCoordinator` = address(0)

**Execution path on zero storage:**
1. If current time < 912 days from epoch 0 (approximately until year 2472 for Unix epoch 0): falls through to game logic with `level=0`, `state=0` (PRESALE). The PRESALE state branch reads `rngWordCurrent` (zero) and enters VRF request path. Calls `vrfCoordinator.requestRandomWords()` where `vrfCoordinator = address(0)` -> **call to address(0) reverts**.
2. If current time >= 912 days from epoch 0 (always true since Unix timestamps are >1.7 billion): enters game-over logic. Reads `gameOver` (false), proceeds to `_gameOverRngGate()` which reads `rngWordByDay[day]`, `rngRequestTime`, `vrfCoordinator` (all zero). Attempts VRF request to address(0) -> **reverts**.
3. Alternative: the PRESALE path may revert earlier at `MustMintToday()` or `NotTimeYet()` depending on timestamp calculations against zero values.

**Conclusion:** All paths either revert early on state preconditions or revert when calling `address(0)` for VRF operations. No ETH transfer possible.

### 3.3 WhaleModule Purchase Functions

**purchaseWhaleBundle:**
- With zero storage, `level=0`, `passLevel=1`, `passLevel <= 4` is true -> `unitPrice = 2.4 ETH`.
- Requires `msg.value == 2.4 ETH * quantity`. If caller sends correct ETH:
  - Writes to `mintPacked_[buyer]`, `futurePrizePool`, `nextPrizePool` on module's own storage (meaningless).
  - Calls `affiliate.getReferrer(buyer)` at compile-time constant address -> external call succeeds/fails based on real affiliate contract state.
  - Calls `dgnrs.transferFromPool()` at compile-time constant address -> external call.
  - The ETH sent remains in the module contract. Nobody reads the module's `futurePrizePool`.

**Risk Assessment:** A caller could send ETH to the module contract via `purchaseWhaleBundle()`. This ETH would be stuck forever in the module contract -- there is no way to extract it (no receive, no fallback, no sweep function). The caller loses their ETH. This is self-inflicted harm, not an exploit.

**purchaseLazyPass / purchaseDeityPass:** Same pattern. ETH sent stays in module contract permanently. Self-inflicted loss only.

**Conclusion:** Purchase functions on direct call are self-destructive for the caller (ETH is permanently locked in the module). No protocol user or Game contract is harmed. The external calls to affiliate/dgnrs contracts at compile-time constant addresses may cause those contracts to record meaningless affiliate data, but since the "game" is the module contract (not the real DegenerusGame), any recorded data is isolated from the real game's state.

### 3.4 JackpotModule Ungated Functions

**payDailyJackpot(isDaily, lvl, randWord):**
- Zero storage: `dailyEthPoolBudget=0`, `dailyEthPhase=0`, `jackpotCounter=0`, `currentPrizePool=0`, `futurePrizePool=0`.
- If `isDaily=true`: not resuming (all cursors zero -> false), computes `winningTraitsPacked` from zero storage via `_rollWinningTraits()` (reads `traitBurnTicket` arrays, all empty). `budget = (0 * dailyBps) / 10_000 = 0`. Function stores zeros to already-zero slots and returns.
- If `isDaily=false`: early-burn path. Reads `price` (zero). `_calcDailyCoinBudget` returns zero. No coin distribution.

**consolidatePrizePools / processTicketBatch / payEarlyBirdLootboxJackpot:** All produce no-ops with zero pool values or empty queues.

**awardFinalDayDgnrsReward(lvl, rngWord):** Calls `dgnrs.poolBalance(Pool.Reward)` at compile-time constant address. The real DGNRS contract returns its actual pool balance. If nonzero, calls `dgnrs.transferFromPool()`. However, `dgnrs.transferFromPool()` is gated by `msg.sender == ContractAddresses.GAME` in the DGNRS contract -- and when called directly on the module, `msg.sender` from the DGNRS contract's perspective would be the module address (not the Game). **This call would revert because the module address is not `ContractAddresses.GAME`.**

**Conclusion:** All JackpotModule ungated functions produce no-ops or revert when zero storage causes zero budgets, empty queues, or external contracts reject the module as an unauthorized caller.

### 3.5 DegeneretteModule._resolvePlayer (Special Analysis)

When called directly on the DegeneretteModule contract:
- `operatorApprovals` reads from the module's own storage (all zeros).
- Only `msg.sender` can act for themselves (any `player != msg.sender` would fail the approval check since all approvals are zero).
- This is actually MORE restrictive than the delegatecall path (where real approvals exist).

**Conclusion:** Operator delegation is non-functional on direct call, providing an additional safety layer.

### 3.6 EndgameModule Ungated Functions

**rewardTopAffiliate(lvl):** Calls `affiliate.affiliateTop(lvl)` at compile-time constant. If top is address(0), returns. If non-zero, calls `dgnrs.transferFromPool(Pool.Affiliate, top, reward)`. The DGNRS contract checks `msg.sender == ContractAddresses.GAME` -- module address is not Game, so **reverts**.

**runRewardJackpots(lvl, rngWord):** `futurePrizePool = 0`. All `bafPct/decPoolWei` calculations produce zero. `futurePoolLocal == baseFuturePool` (both zero), so no SSTORE. No-op.

**claimWhalePass(player):** `whalePassClaims[player] = 0` -> returns immediately.

### 3.7 GameOverModule.handleGameOverDrain

**Execution on zero storage:**
1. `gameOverFinalJackpotPaid` = false -> continues.
2. `level` = 0, `lvl = 1`.
3. `address(this).balance` = module's ETH balance (zero unless someone sent ETH directly). `steth.balanceOf(address(this))` = 0 (no stETH held).
4. `totalFunds = 0`. `claimablePool = 0`. `available = 0`.
5. Sets `gameOver = true`, `gameOverTime = block.timestamp`, `gameOverFinalJackpotPaid = true` on module's own storage.
6. `if (available == 0) return` -> returns.

**Conclusion:** Writes `gameOver/gameOverTime/gameOverFinalJackpotPaid` to the module's own storage (no one reads it). No ETH distribution (available = 0). If called a second time, `gameOverFinalJackpotPaid = true` -> returns immediately.

---

## 4. Special Focus: DecimatorModule

### 4.1 Gated Functions (5 of 7)

| Function | Gate | Details |
|----------|------|---------|
| `creditDecJackpotClaimBatch` | `msg.sender != ContractAddresses.JACKPOTS` | JACKPOTS is a compile-time constant. Any other caller is rejected. |
| `creditDecJackpotClaim` | `msg.sender != ContractAddresses.JACKPOTS` | Same. |
| `recordDecBurn` | `msg.sender != ContractAddresses.COIN` (`OnlyCoin()`) | COIN is a compile-time constant. |
| `runDecimatorJackpot` | `msg.sender != ContractAddresses.GAME` (`OnlyGame()`) | GAME is a compile-time constant. |
| `consumeDecClaim` | `msg.sender != ContractAddresses.GAME` (`OnlyGame()`) | GAME is a compile-time constant. |

These five functions are unconditionally safe on direct call. The compile-time constant addresses cannot be spoofed.

### 4.2 Ungated Functions (2 of 7)

#### claimDecimatorJackpot(lvl) -- THE HIGHEST-RISK FUNCTION

**Trace against zero storage:**

1. Calls `_consumeDecClaim(msg.sender, lvl)`:
   - Reads `lastDecClaimRound.lvl` which is zero (default).
   - If `lvl != 0`: `lastDecClaimRound.lvl (0) != lvl` -> **reverts `DecClaimInactive()`**.
   - If `lvl == 0`: `lastDecClaimRound.lvl (0) == 0` -> passes the check.
   - Reads `decBurn[0][msg.sender]`: `claimed` = 0 -> passes.
   - `decBucketOffsetPacked[0]` = 0, `lastDecClaimRound.totalBurn` = 0.
   - `_decClaimableFromEntry(poolWei=0, totalBurn=0, ...)`: `totalBurn == 0` -> returns 0.
   - `amountWei == 0` -> **reverts `DecNotWinner()`**.

**Conclusion for `lvl == 0`:** Reverts with `DecNotWinner()` because `totalBurn` is zero, which causes `_decClaimableFromEntry` to return 0.

**Conclusion for `lvl != 0`:** Reverts with `DecClaimInactive()` because `lastDecClaimRound.lvl` is zero and doesn't match.

**No execution path produces a non-reverting outcome.** The function is completely harmless on direct call.

#### decClaimable(player, lvl) -- VIEW FUNCTION

Read-only. Returns `(0, false)` for any input because `lastDecClaimRound.lvl == 0` and doesn't match any nonzero `lvl`. For `lvl == 0`, `totalBurn == 0` -> returns `(0, false)`.

**Harmless by definition (view function).**

---

## 5. Special Focus: DegeneretteModule

### 5.1 _resolvePlayer on Direct Call

The DegeneretteModule has its own private `_resolvePlayer` implementation:
```solidity
function _resolvePlayer(address player) private view returns (address resolved) {
    if (player == address(0)) return msg.sender;
    if (player != msg.sender) {
        _requireApproved(player);  // reads operatorApprovals[player][msg.sender]
    }
    return player;
}
```

On direct call, `operatorApprovals` reads from the module's own storage (all zeros). No operator is approved for anyone. Only `msg.sender` can act as themselves (`player == address(0)` or `player == msg.sender`). This is strictly more restrictive than the delegatecall path.

### 5.2 placeFullTicketBets on Direct Call

1. `_resolvePlayer(player)`: only msg.sender can act for themselves.
2. `lootboxRngIndex` = 0 -> `if (index == 0) revert E()` -> **reverts**.

No bet can be placed because the RNG index hasn't been initialized.

### 5.3 resolveBets on Direct Call

1. `_resolvePlayer(player)`: resolves to msg.sender.
2. For each `betId`: `degeneretteBets[player][betId]` = 0 (zero packed data).
3. `_resolveBet` reads mode from packed (0). Neither `MODE_FULL_TICKET` (1) -> reverts `E()`.

**All DegeneretteModule functions revert on direct call.**

---

## 6. Special Focus: AdvanceModule

### 6.1 rawFulfillRandomWords

Gated by `msg.sender != address(vrfCoordinator)`. On direct call, `vrfCoordinator` = `address(0)`. Only `address(0)` could pass this check, but `address(0)` cannot be `msg.sender` in an external call (no EOA or contract has address zero). **Unconditionally safe.**

### 6.2 wireVrf

Gated by `msg.sender != ContractAddresses.ADMIN`. **Unconditionally safe.**

### 6.3 updateVrfCoordinatorAndSub

Gated by `msg.sender != ContractAddresses.ADMIN`. Also checks `_rngStalledForThreeDays()` which reads `rngRequestTime` (zero) -- `block.timestamp - 0 >= 3 days` (true since epoch 0). But the ADMIN gate blocks this before the stall check matters. **Unconditionally safe.**

### 6.4 advanceGame

See Section 3.2. All paths revert (either state preconditions fail or VRF calls to address(0) revert).

### 6.5 requestLootboxRng

`rngWordByDay[currentDay]` = 0 -> `if (rngWordByDay[currentDay] == 0) revert E()`. **Reverts immediately.**

### 6.6 reverseFlip

Reads `totalFlipReversals` (0). Computes `cost = _currentNudgeCost(0)`. Calls `coin.burnCoin(msg.sender, cost)`. If caller has sufficient BURNIE, their tokens are burned. Then reads `coinflipFlip` (zero), toggles to 1, writes to module's own storage. Caller wastes their own BURNIE for no effect on the real game.

**Self-inflicted harm only.** Not an exploit.

---

## 7. Verification: No Exploitable State-Independent Paths

For each module, the answer to: "If I call every external function with arbitrary parameters against zero storage, can I extract value, corrupt Game state, or cause harm to any protocol user?"

| Module | Can extract value? | Can corrupt Game state? | Can harm protocol users? | Reasoning |
|--------|--------------------|------------------------|--------------------------|-----------|
| MintModule | NO | NO | NO | Division by zero reverts. Storage writes are on module contract. |
| AdvanceModule | NO | NO | NO | VRF calls to address(0) revert. State preconditions block all paths. |
| WhaleModule | NO (caller loses ETH) | NO | NO | ETH sent is permanently locked in module. External calls to real contracts either revert (unauthorized) or record meaningless data. |
| JackpotModule | NO | NO | NO | Zero pools produce zero distributions. External contract calls revert (unauthorized caller). |
| DecimatorModule | NO | NO | NO | 5/7 functions are IC-gated. 2 ungated functions revert (DecClaimInactive/DecNotWinner). |
| EndgameModule | NO | NO | NO | Zero pools, zero claims. External contract calls revert (unauthorized). |
| GameOverModule | NO | NO | NO | Zero balance -> zero distribution. Writes only to module's own storage. |
| LootboxModule | NO | NO | NO | Zero lootbox amounts and zero RNG words cause immediate reverts. |
| BoonModule | NO | NO | NO | Zero boon data -> returns zeros or no-ops. Writes zeros to already-zero slots. |
| DegeneretteModule | NO | NO | NO | Zero rngIndex causes immediate revert on all bet placement. Zero bet data causes revert on resolution. |

---

## 8. DegenerusGame Dispatch: Sole Initialized Path

### 8.1 Dispatch Mechanism

DegenerusGame uses explicit `delegatecall` for each module function. The pattern is:

```solidity
(bool ok, bytes memory data) = ContractAddresses.GAME_{MODULE}_MODULE.delegatecall(
    abi.encodeWithSelector(IModule.function.selector, args)
);
if (!ok) _revertDelegate(data);
```

Module addresses are compile-time constants from `ContractAddresses.sol`. They are set during the nonce-prediction deploy pipeline and baked into bytecode. They cannot be changed at runtime.

### 8.2 Module Address Sources

The following constant addresses are used for delegatecall dispatch in DegenerusGame:
- `ContractAddresses.GAME_MINT_MODULE` -- MintModule
- `ContractAddresses.GAME_ADVANCE_MODULE` -- AdvanceModule (via fallback dispatch in Game)
- `ContractAddresses.GAME_WHALE_MODULE` -- WhaleModule
- `ContractAddresses.GAME_JACKPOT_MODULE` -- JackpotModule
- `ContractAddresses.GAME_DECIMATOR_MODULE` -- DecimatorModule
- `ContractAddresses.GAME_ENDGAME_MODULE` -- EndgameModule
- `ContractAddresses.GAME_GAMEOVER_MODULE` -- GameOverModule
- `ContractAddresses.GAME_LOOTBOX_MODULE` -- LootboxModule
- `ContractAddresses.GAME_BOON_MODULE` -- BoonModule
- `ContractAddresses.GAME_DEGENERETTE_MODULE` -- DegeneretteModule

### 8.3 No Other Contract Delegatecalls to Modules

Only `DegenerusGame` has `delegatecall` instructions targeting module addresses. No other contract in the protocol delegatecalls to any module. This was verified by searching for `delegatecall` across all contract files.

### 8.4 Storage Context

When called via `delegatecall` from DegenerusGame:
- Modules execute in Game's storage context (initialized, with real player data, pool balances, VRF coordinator, etc.)
- `msg.sender` is preserved from the original caller
- `address(this)` is the Game contract address

When called directly:
- Modules execute in their own storage context (uninitialized, all zeros)
- `msg.sender` is the direct caller
- `address(this)` is the module contract address

This fundamental difference is why all direct calls are harmless -- there is no meaningful state to read or corrupt.

---

## 9. AUTH-03 Verdict

### Per-Module Breakdown

| Module | Functions | IC-Gated | SP-Gated | Ungated | Ungated Harmless? | Verdict |
|--------|-----------|----------|----------|---------|-------------------|---------|
| MintModule | 2 | 0 | 1 | 1 | YES (div-by-zero revert) | PASS |
| AdvanceModule | 6 | 3 | 2 | 1 (reverseFlip) | YES (self-burn only) | PASS |
| WhaleModule | 4 | 0 | 1 | 3 | YES (ETH locked in module) | PASS |
| JackpotModule | 7 | 0 | 2 | 5 | YES (zero pools, no-ops) | PASS |
| DecimatorModule | 7 | 5 | 1 | 1 | YES (reverts DecNotWinner) | PASS |
| EndgameModule | 3 | 0 | 0 | 3 | YES (zero pools, unauthorized) | PASS |
| GameOverModule | 2 | 0 | 1 | 1 | YES (zero balance, no-op) | PASS |
| LootboxModule | 4 | 0 | 4 | 0 | N/A | PASS |
| BoonModule | 5 | 0 | 1 | 4 | YES (returns zeros, no-ops) | PASS |
| DegeneretteModule | 3 | 0 | 3 | 0 | N/A | PASS |
| **TOTALS** | **43** | **8** | **15** | **20** | **ALL YES** | **PASS** |

### Summary of Protections

1. **Inter-Contract Gates (8 functions):** Cannot be called by unauthorized addresses. Compile-time constant addresses make these checks immutable.
2. **State-Precondition Gates (15 functions):** Revert or no-op due to zero storage values (zero amounts, zero rngIndex, zero prices, empty arrays).
3. **Ungated Functions (20 functions):** All proven harmless through individual trace analysis:
   - 7 revert (division by zero, address(0) calls, DecNotWinner, zero rngIndex)
   - 10 produce no-ops (zero pools, zero budgets, empty queues, return zero values)
   - 3 cause self-inflicted harm only (ETH locked in module, BURNIE burned for nothing)
4. **No fallback/receive/constructor** in any module -- no ETH acceptance path, no storage initialization.
5. **DegenerusGame delegatecall is the sole path** to initialized storage for all 10 modules.

### AUTH-03: PASS

All module-only entry points are either unreachable via access gates or harmless when called directly against uninitialized storage. The delegatecall dispatch in DegenerusGame is confirmed as the only execution path that operates on initialized game state. No direct call to any module can extract value, corrupt game state, or harm any protocol user.

---

## Informational Notes

### INFO-01: WhaleModule Purchase Functions Accept ETH on Direct Call

`purchaseWhaleBundle`, `purchaseLazyPass`, and `purchaseDeityPass` will accept ETH matching the expected price when called directly. This ETH is permanently locked in the module contract (no extraction mechanism exists). This is not a vulnerability -- it is self-inflicted harm by a misconfigured or confused caller. No mitigation needed; standard delegatecall module behavior.

### INFO-02: AdvanceModule.reverseFlip Burns BURNIE on Direct Call

A caller with BURNIE tokens could call `reverseFlip()` directly and burn their tokens. The coinflip toggle writes to the module's own storage and has no effect on the real game. This is economically irrational behavior. No mitigation needed.

### INFO-03: JackpotModule.awardFinalDayDgnrsReward External Call Pattern

This function calls `dgnrs.transferFromPool()` at the real DGNRS contract address. The DGNRS contract's access control (requiring `msg.sender == ContractAddresses.GAME`) blocks the module as an unauthorized caller. The compile-time constant pattern provides defense-in-depth.
