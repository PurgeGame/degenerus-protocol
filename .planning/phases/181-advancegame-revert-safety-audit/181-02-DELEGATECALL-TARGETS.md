# 181-02: Delegatecall Target Revert Audit (AGSAFE-02)

**Scope:** Every revert path inside delegatecall targets reachable from `AdvanceModule.advanceGame` -- JackpotModule (7 entry points), MintModule (1 entry point), GameOverModule (2 entry points).

**Solidity version:** 0.8.34 (checked arithmetic by default; overflow/underflow reverts unless `unchecked`).

**Key principle:** All 10 entry points are called via `delegatecall` from AdvanceModule, which means they execute in the DegenerusGame contract's storage context. Any revert inside a delegatecall target causes `(ok, data)` to return `ok=false`, and AdvanceModule's `_revertDelegate(data)` bubbles the revert up, reverting the entire `advanceGame` transaction.

---

## JackpotModule Entry Points

### DCALL-01: payDailyJackpot (line 305)

**Called from:** `AdvanceModule.payDailyJackpot` (line 648) via delegatecall.

**Explicit reverts:** None. No `require`, `revert`, or `assert` statements in this function or any private function it calls that are unique to this path.

**Checked arithmetic analysis:**

All arithmetic in this function uses either:
- `unchecked` blocks for safe loop counters (`++i`, `++j`)
- Division operations that cannot produce overflow
- Multiplication of BPS values against pool balances (both bounded by total ETH supply ~120M ETH << uint256 max)

Specific paths:
- Line 346: `(poolSnapshot * dailyBps) / 10_000` -- poolSnapshot is bounded by contract balance, dailyBps <= 20_000 (doubled compressed). Product bounded well within uint256.
- Line 371: `_getCurrentPrizePool() - dailyLootboxBudget` -- dailyLootboxBudget is `budget / 5` where budget comes from poolSnapshot, and only deducted from current pool when `dailyTicketUnits != 0`. Since dailyLootboxBudget <= budget <= poolSnapshot <= currentPrizePool, underflow is impossible.
- Line 451: `_getCurrentPrizePool() - paidDailyEth` -- paidDailyEth is bounded by dailyEthBudget which was computed as a fraction of currentPrizePool. Safe: paid cannot exceed the pool it was drawn from.
- Line 480: `(futurePool * poolBps) / 10_000` where poolBps=100. Cannot overflow.
- Line 483: `futurePool - ethDaySlice` where ethDaySlice = futurePool/100. Safe by construction.

**Division-by-zero analysis:**
- `PriceLookupLib.priceForLevel()` always returns non-zero (minimum 0.01 ether). All `/ ticketPrice` operations are safe.
- `/ 10_000`, `/ 200`, `/ 100`, `/ 5` -- all constant divisors, never zero.
- `perWinner = share / totalCount` -- totalCount is checked `!= 0` before use.

**Array access analysis:**
- `traitBurnTicket[lvl][trait]` accesses are bounded by the storage array length (checked inside `_randTraitTicket`/`_randTraitTicketWithIndices`).
- `winners[i]` loops use `len = winners.length` as bound.

**External calls:**
- `coinflip.creditFlip` / `coinflip.creditFlipBatch` -- external calls to BurnieCoinflip. If these revert, the delegatecall reverts. These are trusted protocol contracts; creditFlip has no revert conditions when called with valid addresses.
- `jackpots.runBafJackpot` -- not called from this path (only from `runRewardJackpots`).

**Verdict: SAFE** -- No revert can fire during normal game progression. All arithmetic is bounded by pool balances. All external calls target trusted protocol contracts.

---

### DCALL-02: payDailyJackpotCoinAndTickets (line 530)

**Called from:** `AdvanceModule.payDailyJackpotCoinAndTickets` (line 670) via delegatecall.

**Explicit reverts:** None.

**Early exit:** Line 531: `if (!dailyJackpotCoinTicketsPending) return;` -- graceful no-op.

**Checked arithmetic analysis:**
- Line 552: `(coinBudget * FAR_FUTURE_COIN_BPS) / 10_000` -- both bounded constants. Safe.
- Line 555: `coinBudget - farBudget` -- farBudget = coinBudget * 2500 / 10000, always <= coinBudget. Safe.
- Line 593: `jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP` -- both uint8, sum << 256. Safe.
- Line 607 (unchecked): `jackpotCounter += counterStep` -- both uint8, sum <= JACKPOT_LEVEL_CAP (5). Safe within uint8 range.

**Division-by-zero analysis:**
- Same as DCALL-01: `PriceLookupLib.priceForLevel` always returns non-zero. All BPS divisions use constant non-zero divisors.

**External calls:**
- `coinflip.creditFlip` / `coinflip.creditFlipBatch` -- trusted protocol, no revert in normal flow.

**Verdict: SAFE** -- No revert can fire during normal game progression.

---

### DCALL-03: payDailyCoinJackpot (line 2164)

**Called from:** `AdvanceModule._payDailyCoinJackpot` (line 689) via delegatecall.

**Explicit reverts:** None.

**Early exits:** Returns early if coinBudget is 0 (line 2166), nearBudget is 0 (line 2176), targetLevel is 0 (line 2197).

**Checked arithmetic analysis:**
- Line 2169: `(coinBudget * FAR_FUTURE_COIN_BPS) / 10_000` -- bounded. Safe.
- Line 2170: `coinBudget - farBudget` -- farBudget derived from coinBudget. Safe.
- Line 2243: `coinBudget / cap` and `coinBudget % cap` -- cap is min(DAILY_COIN_MAX_WINNERS=50, coinBudget), always > 0. Safe.

**Division-by-zero analysis:**
- `_calcDailyCoinBudget` (line 2453): `priceWei * 200` -- priceWei always non-zero from PriceLookupLib. Safe.

**External calls:**
- `coinflip.creditFlipBatch` -- trusted protocol contract. No revert in normal flow.

**Verdict: SAFE** -- No revert can fire during normal game progression.

---

### DCALL-04: consolidatePrizePools (line 730)

**Called from:** `AdvanceModule._consolidatePrizePools` (line 614) via delegatecall.

**Explicit reverts:** None.

**Checked arithmetic analysis:**
- Line 734: `acc >> 1` -- shift, cannot overflow. `acc - half` where half = acc >> 1, so half <= acc. Safe.
- Line 740: `_getCurrentPrizePool() + _getNextPrizePool()` -- both bounded by total ETH in contract. Sum bounded well within uint256.
- Line 748: `(fp * keepBps) / 10_000` -- keepBps from _futureKeepBps is 3000-6500 range. Safe.
- Line 749: `fp - keepWei` where keepWei = (fp * keepBps) / 10_000 with keepBps < 10_000. So keepWei < fp. Safe.
- Line 775 (_distributeYieldSurplus): `totalBal - obligations` -- only computed when `totalBal > obligations`. Safe.

**Division-by-zero analysis:**
- `/ 10_000`, `/ 100` -- constant divisors. Safe.
- `PriceLookupLib.priceForLevel` (via `_creditDgnrsCoinflip`) always returns non-zero. `priceWei * 20` cannot be zero.

**External calls:**
- `steth.balanceOf(address(this))` (line 764 via `_distributeYieldSurplus`) -- read-only, no revert in normal Lido operation.
- `coinflip.creditFlip` (line 2155 via `_creditDgnrsCoinflip`) -- trusted protocol.

**Verdict: SAFE** -- No revert can fire during normal game progression.

---

### DCALL-05: awardFinalDayDgnrsReward (line 620)

**Called from:** `AdvanceModule._awardFinalDayDgnrsReward` (line 628) via delegatecall.

**Explicit reverts:** None.

**Early exit:** Line 625: returns early if reward is 0.

**Checked arithmetic analysis:**
- Line 624: `(dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000` -- FINAL_DAY_DGNRS_BPS = 100. Product bounded by DGNRS supply. Safe.

**External calls:**
- `dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward)` (line 621) -- read-only, trusted protocol.
- `dgnrs.transferFromPool(...)` (line 641) -- trusted protocol. TransferFromPool is designed to handle insufficient balance gracefully (transfers min of request and available).

**Verdict: SAFE** -- No revert can fire during normal game progression.

---

### DCALL-06: runRewardJackpots (line 2516)

**Called from:** `AdvanceModule._runRewardJackpots` (line 589) via delegatecall.

**Explicit reverts:** None directly.

**Checked arithmetic analysis:**
- Line 2531: `(baseFuturePool * bafPct) / 100` -- bafPct is 10 or 20. Safe.
- Line 2534: `futurePoolLocal -= bafPoolWei` -- bafPoolWei = baseFuturePool * (10 or 20) / 100, always <= baseFuturePool = futurePoolLocal. Safe.
- Line 2556: `(baseFuturePool * 30) / 100` -- Safe.
- Line 2560-2561: `decPoolWei - returnWei` -- returnWei is the refund from DecimatorModule, always <= decPoolWei. Safe.
- Line 2572: `(futurePoolLocal * 10) / 100` -- Safe.
- Line 2590: `_getFuturePrizePool() - baseFuturePool` -- this reads the STORAGE value of futurePrizePool (which may have been incremented by auto-rebuy writes during BAF/Decimator resolution). Since auto-rebuy only ADDS to futurePrizePool, the storage value is always >= baseFuturePool. Safe.

**Sub-calls:**
- `_runBafJackpot` (line 2539) -- calls `jackpots.runBafJackpot` (external call to DegenerusJackpots). This is a trusted protocol contract. If it reverts (e.g., due to a bug in the jackpots contract), the entire advanceGame reverts. No revert conditions in normal operation.
- `IDegenerusGame(address(this)).runDecimatorJackpot(...)` (lines 2558, 2574) -- regular call (NOT delegatecall) to self. This goes through the DegenerusGame proxy which delegatecalls to DecimatorModule. The DecimatorModule has its own revert safety (audited in 181-01). The `msg.sender` for this call is the DegenerusGame contract itself (since we're in a delegatecall context, `address(this)` is the game contract). This satisfies the `onlyGame` modifier.

**Verdict: SAFE** -- No revert can fire during normal game progression. External calls target trusted protocol contracts.

---

### DCALL-07: processTicketBatch (line 1693)

**Called from:** `AdvanceModule._runProcessTicketBatch` (line 1271) via delegatecall.

**Explicit reverts:** None within processTicketBatch itself.

**Note on caller check:** Line 1285 in AdvanceModule: `if (data.length == 0) revert E();` -- this fires if the delegatecall returns empty data. Since processTicketBatch always returns a `bool`, the ABI-encoded return is always 32 bytes. This revert is unreachable.

**Checked arithmetic analysis:**
- Line 1715: `writesBudget -= (writesBudget * 35) / 100` -- writesBudget = WRITES_BUDGET_SAFE = 550. Result is 357. Safe.
- Line 1719: `lootboxRngWordByIndex[lootboxRngIndex - 1]` -- this reads the most recent lootbox RNG word. If `lootboxRngIndex` were 0, this would underflow. However, `lootboxRngIndex` is initialized during the first VRF fulfillment and incremented on each lootbox RNG request. By the time processTicketBatch is called during advanceGame, at least one VRF word has been fulfilled (the advance requires a valid RNG word). So `lootboxRngIndex >= 1`. Safe.
- Lines 1733-1741 (unchecked): Loop counter increments. Safe by construction (bounded by writesBudget and queue length).

**Array access analysis:**
- `queue[idx]` -- idx is checked `< total` in while condition. Safe.
- Internal `_processOneTicketEntry` and `_generateTicketBatch` operate on bounded arrays.

**Assembly blocks (lines 1991-2025):**
- Storage writes to traitBurnTicket arrays using computed slots. The assembly correctly extends dynamic arrays and writes player addresses. No revert paths in assembly.

**Division-by-zero analysis:**
- `perWinner = share / totalCount` in called functions -- totalCount checked != 0 before division.
- `/ ticketPrice` in `_budgetToTicketUnits` -- returns 0 when ticketPrice is 0 (early exit). PriceLookupLib always returns non-zero anyway.

**Verdict: SAFE** -- No revert can fire during normal game progression. All storage accesses are bounded, loop iteration is gas-budgeted.

---

## MintModule Entry Point

### DCALL-08: processFutureTicketBatch (MintModule line 302)

**Called from:** `AdvanceModule._processFutureTicketBatch` (line 1210) via delegatecall.

**Explicit reverts:** None within processFutureTicketBatch itself. All `revert E()` statements in MintModule (lines 606, 615, 619, 635, 642, 651, 667, 674, 713, 762, 883, 884, 901, 902, 944, 947, 950, 953, 1045, 1046, 1048) are in other functions (`mintAndPurchase`, `purchaseBurnieTickets`, `purchaseBurnieLootbox`), not in `processFutureTicketBatch` or any function it calls.

**Note on caller check:** Line 1222 in AdvanceModule: `if (data.length == 0) revert E();` -- processFutureTicketBatch always returns `(bool, bool, uint32)` (96 bytes ABI-encoded). This revert is unreachable.

**Checked arithmetic analysis:**
- Line 331-332: `writesBudget -= (writesBudget * 35) / 100` -- same safe pattern as processTicketBatch.
- Lines 396-397 (unchecked): `remainingOwed = owed - take` -- take is capped to min(owed, maxT). take <= owed. Safe.
- Lines 409-411 (unchecked): `processed += take`, `used += writesThis`, `++idx` -- all bounded by budget and queue length.

**Internal calls:**
- `_raritySymbolBatch` (line 380) -- shared code with JackpotModule, no reverts. Assembly block writes to storage; no revert paths.
- `_rollRemainder` (lines 357, 400) -- pure function, no reverts.

**Division-by-zero analysis:**
- `room / 2` (line 376) -- room is checked > baseOv first, so room >= 1. Safe.

**Verdict: SAFE** -- No revert can fire during normal game progression. The function only processes queued ticket entries using bounded iteration with a gas budget.

---

## GameOverModule Entry Points

### DCALL-09: handleGameOverDrain (line 79)

**Called from:** `AdvanceModule._handleGameOverPath` (line 514) via delegatecall.

**Explicit reverts:**
1. **Line 232 (in `_sendStethFirst`):** `if (!steth.transfer(to, amount)) revert E();` -- stETH transfer to sDGNRS fails.
2. **Line 236 (in `_sendStethFirst`):** `if (!steth.transfer(to, stethBal)) revert E();` -- stETH transfer fails (partial stETH path).
3. **Line 241 (in `_sendStethFirst`):** `if (!ok) revert E();` -- ETH transfer via `.call{value: ethAmount}("")` fails.

**Early exits (non-revert):**
- Line 80: `if (gameOverFinalJackpotPaid) return;` -- already processed, graceful no-op.
- Line 140: `if (rngWord == 0) return;` -- RNG not ready, graceful retry on next call.

**Checked arithmetic analysis:**
- Line 91: `totalFunds > claimablePool ? totalFunds - claimablePool : 0` -- ternary prevents underflow. Safe.
- Line 97: `refundPerPass * uint256(purchasedCount)` -- refundPerPass = 20 ETH, purchasedCount is uint16 (max 65535). Product max ~1.3M ETH, well within uint256. Safe.
- Lines 102-106 (unchecked): `claimableWinnings[owner] += refund` -- practically safe (uint256 overflow requires ~10^59 ETH). `totalRefunded += refund` -- same. `budget -= refund` -- refund capped to budget (line 98-99). Safe.
- Line 154: `remaining / 10` -- constant divisor. Safe.
- Line 157: `decPool - decRefund` -- decRefund is the return value from runTerminalDecimatorJackpot, which returns the portion NOT spent. Always <= decPool. Safe.
- Line 162: `remaining += decRefund` -- adding refund back. Cannot overflow (bounded by original balance). Safe.
- Line 171: `remaining -= termPaid` -- termPaid is the amount distributed by runTerminalJackpot, which cannot exceed the pool it received. Safe.

**External calls:**
- `charityGameOver.burnAtGameOver()` (line 126) -- calls GNRUS.burnAtGameOver(). Trusted protocol. If GNRUS has no tokens to burn, this is a no-op.
- `dgnrs.burnAtGameOver()` (line 127) -- calls DegenerusStonk.burnAtGameOver(). Trusted protocol.
- `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(...)` (line 156) -- regular call to self, routed through DegenerusGame proxy. msg.sender = game contract (satisfies onlyGame). Trusted.
- `IDegenerusGame(address(this)).runTerminalJackpot(...)` (line 168-169) -- regular call to self. msg.sender = game contract (satisfies OnlyGame at JackpotModule line 255). Trusted.
- `_sendToVault` -> `_sendStethFirst` -> `steth.transfer` / ETH `.call` -- see revert analysis below.

**Revert classification for _sendStethFirst (lines 232, 236, 241):**

These reverts fire when stETH transfer or ETH transfer to the recipient fails. The recipients are:
- `ContractAddresses.SDGNRS` -- StakedDegenerusStonk contract (can receive ETH and stETH)
- `ContractAddresses.VAULT` -- DegenerusVault contract (can receive ETH and stETH)
- `ContractAddresses.GNRUS` -- GNRUS contract (can receive ETH and stETH)

All three are protocol-controlled contracts designed to receive these assets. The only scenario where these fail:
- **stETH transfer paused by Lido:** Lido has a pause mechanism. If stETH transfers are paused, all three transfer attempts fail, blocking game-over processing.
- **Recipient contract rejects ETH:** All three recipients have `receive()` fallbacks. Not possible in normal operation.

**Classification:** **INTENTIONAL** -- The NatSpec at line 209 explicitly documents this: "Hard-reverts on stETH/ETH transfer failure. Because game-over sets terminal state flags that roll back on revert, a stuck stETH transfer would block game-over processing until the transfer succeeds." This is a deliberate design choice: game-over waits for external conditions (Lido unfreezing) rather than silently dropping funds.

**Verdict: SAFE** -- All reverts in the transfer path are INTENTIONAL guards. No revert can fire unexpectedly during normal game progression. The stETH/ETH transfer reverts are documented as deliberate blocking behavior that resolves when external conditions normalize.

---

### DCALL-10: handleFinalSweep (line 185)

**Called from:** `AdvanceModule._handleGameOverPath` (line 492) via delegatecall.

**Explicit reverts:**
1. **Line 232 (in `_sendStethFirst`):** `if (!steth.transfer(to, amount)) revert E();` -- same as DCALL-09.
2. **Line 236 (in `_sendStethFirst`):** `if (!steth.transfer(to, stethBal)) revert E();` -- same as DCALL-09.
3. **Line 241 (in `_sendStethFirst`):** `if (!ok) revert E();` -- same as DCALL-09.

**Early exits (non-revert):**
- Line 186: `if (gameOverTime == 0) return;` -- game not over yet. Graceful no-op.
- Line 187: `if (block.timestamp < uint256(gameOverTime) + 30 days) return;` -- too early. Graceful no-op.
- Line 188: `if (finalSwept) return;` -- already swept. Graceful no-op.
- Line 202: `if (totalFunds == 0) return;` -- nothing to sweep. Graceful no-op.

**Checked arithmetic analysis:**
- Line 187: `uint256(gameOverTime) + 30 days` -- gameOverTime is uint48, 30 days is a constant. Sum well within uint256. Safe.
- Line 215-216 (in `_sendToVault`): `amount / 3` and `amount - thirdShare - thirdShare` -- standard integer division. Safe.

**External calls:**
- `admin.shutdownVrf()` (line 194) -- wrapped in try/catch, so failure cannot revert. Deliberate fire-and-forget.
- `steth.balanceOf(address(this))` (line 197) -- read-only. Safe.
- `_sendToVault` -> `_sendStethFirst` -- same transfer reverts as DCALL-09.

**Revert classification:** Same as DCALL-09 -- all three `_sendStethFirst` reverts are **INTENTIONAL** guards for stETH/ETH transfer failures. Final sweep will retry on subsequent advanceGame calls until transfers succeed.

**Verdict: SAFE** -- All reverts are INTENTIONAL. No revert can fire unexpectedly during normal game progression.

---

## Shared Observations

### OnlyGame() Guard (JackpotModule line 255)

The `OnlyGame()` revert exists at line 255 inside `runTerminalJackpot`. This function is NOT one of the 7 delegatecall entry points -- it is called via `IDegenerusGame(address(this))` (a regular `CALL`, not `DELEGATECALL`) from both:
- `GameOverModule.handleGameOverDrain` (line 168-169) -- inside a delegatecall context
- `JackpotModule.runRewardJackpots` is NOT a direct caller; runRewardJackpots calls `runDecimatorJackpot`, which is on DecimatorModule

Since `handleGameOverDrain` executes via delegatecall, `address(this)` resolves to the DegenerusGame proxy. The `IDegenerusGame(address(this)).runTerminalJackpot(...)` call is therefore a regular call FROM the game proxy TO itself. The `msg.sender` for this call is `ContractAddresses.GAME`, satisfying the `OnlyGame()` guard. **This guard cannot fire in the delegatecall path.**

### Unchecked Blocks

All `unchecked` blocks across all 10 entry points are used for:
1. Loop counter increments (`++i`, `++j`, `++idx`) -- bounded by array lengths or gas budgets
2. Claimable balance additions (`claimableWinnings[addr] += amount`) -- documented as safe because uint256 max (~10^77 wei) is unreachable with real ETH amounts (~10^26 wei max)
3. Budget counter subtractions where the subtrahend is verified <= the minuend by prior logic

No unchecked block presents a realistic overflow/underflow risk.

### External Call Trust Model

All external calls from these delegatecall targets go to trusted protocol contracts:
- `coinflip` (BurnieCoinflip) -- creditFlip/creditFlipBatch
- `dgnrs` (StakedDegenerusStonk) -- poolBalance/transferFromPool/burnAtGameOver
- `steth` (Lido stETH) -- balanceOf/transfer
- `jackpots` (DegenerusJackpots) -- runBafJackpot
- `admin` (DegenerusAdmin) -- shutdownVrf (wrapped in try/catch)
- Self-calls via `IDegenerusGame(address(this))` -- routed through DegenerusGame proxy

None of these can be replaced by an attacker (all are immutable `ContractAddresses` constants).

---

## Overall Verdict

**AGSAFE-02: VERIFIED** -- 10 entry points audited, 3 explicit revert sites traced (all in GameOverModule._sendStethFirst), 3 classified INTENTIONAL (documented stETH/ETH transfer guards), 0 FINDINGS.

| ID | Entry Point | Module | Explicit Reverts | Verdict |
|----|-------------|--------|-----------------|---------|
| DCALL-01 | payDailyJackpot | JackpotModule | 0 | SAFE |
| DCALL-02 | payDailyJackpotCoinAndTickets | JackpotModule | 0 | SAFE |
| DCALL-03 | payDailyCoinJackpot | JackpotModule | 0 | SAFE |
| DCALL-04 | consolidatePrizePools | JackpotModule | 0 | SAFE |
| DCALL-05 | awardFinalDayDgnrsReward | JackpotModule | 0 | SAFE |
| DCALL-06 | runRewardJackpots | JackpotModule | 0 | SAFE |
| DCALL-07 | processTicketBatch | JackpotModule | 0 | SAFE |
| DCALL-08 | processFutureTicketBatch | MintModule | 0 | SAFE |
| DCALL-09 | handleGameOverDrain | GameOverModule | 3 (INTENTIONAL) | SAFE |
| DCALL-10 | handleFinalSweep | GameOverModule | 3 (INTENTIONAL) | SAFE |

**Summary:** No revert inside any delegatecall target can fire unexpectedly during normal game progression when called from advanceGame. The only explicit reverts (GameOverModule stETH/ETH transfers) are intentionally designed to block game-over processing until external transfer conditions normalize. All JackpotModule and MintModule entry points are revert-free: checked arithmetic cannot overflow with realistic values, division-by-zero is prevented by PriceLookupLib's always-nonzero returns, and all external calls target trusted immutable protocol contracts.
