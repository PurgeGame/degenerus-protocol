# Phase 100 Plan 01: Cache-Overwrite Pattern Scan Inventory

## Scan Methodology

Every function across all 29 protocol contracts was examined for the **three-leg cache-overwrite pattern**:

1. **READ-LOCAL**: A storage variable is cached into a local (`uint256 xLocal = _getStorageVar()`)
2. **NESTED-WRITE**: A function called after the cache can write to the same storage slot
3. **STALE-WRITEBACK**: The local is written back to storage after the nested call returns

A function is **VULNERABLE** if all three legs are present. A function is **SAFE** if any leg is absent.

## Auto-Rebuy Write Surface

The auto-rebuy path is the primary vector for nested writes to prize pool storage. When a player has auto-rebuy enabled, crediting ETH via `_addClaimableEth` triggers `_processAutoRebuy`, which writes:

| Storage Slot | Variable | Write Function | Condition |
|---|---|---|---|
| `prizePoolsPacked` high-128 | `futurePrizePool` | `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` | `calc.toFuture == true` (75% probability: level offsets +2, +3, +4) |
| `prizePoolsPacked` low-128 | `nextPrizePool` | `_setNextPrizePool(_getNextPrizePool() + calc.ethSpent)` | `calc.toFuture == false` (25% probability: level offset +1) |
| `claimableWinnings[beneficiary]` mapping | per-player claimable | `_creditClaimable(beneficiary, calc.reserved)` | `calc.reserved != 0` (take-profit remainder) |
| `claimablePool` (uint256) | aggregate claimable | `claimablePool += calc.reserved` | `calc.reserved != 0` (EndgameModule path only) |
| `ticketQueue` mappings | ticket queue entries | `_queueTickets(beneficiary, calc.targetLevel, calc.ticketCount)` | `calc.hasTickets == true` |

**Note:** The `_addClaimableEth` / `_processAutoRebuy` pattern exists in three separate contracts with slightly different implementations:
- **EndgameModule** (line 256): Returns `claimableDelta`, caller manages `claimablePool`
- **JackpotModule** (line 928): Returns `claimableDelta`, caller manages `claimablePool`
- **DecimatorModule** (line 414): Void return, manages `claimablePool` internally (subtracts `calc.ethSpent` from pre-reserved pool)
- **DegeneretteModule** (line 1153): NO auto-rebuy path -- simple `claimablePool += weiAmount` only

## Candidate Inventory

### VULNERABLE Instances

#### 1. `runRewardJackpots` in DegenerusGameEndgameModule -- VULNERABLE

- **Cached variable:** `futurePoolLocal` = `_getFuturePrizePool()` at line 169
- **Base snapshot:** `baseFuturePool` = `futurePoolLocal` at line 170 (copy of initial cache)
- **Nested write path:**
  - Line 189: `_runBafJackpot(bafPoolWei, lvl, rngWord)`
  - -> Line 385/405: `_addClaimableEth(winner, ethPortion, rngWord)` / `_addClaimableEth(winner, amount, rngWord)`
  - -> Line 265-284: If auto-rebuy enabled, `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` (75%) or `_setNextPrizePool(_getNextPrizePool() + calc.ethSpent)` (25%)
- **Stale write-back:** Line 235: `_setFuturePrizePool(futurePoolLocal)` -- writes the pre-computed local, overwriting any auto-rebuy contributions
- **Storage slot corrupted:** `prizePoolsPacked` high-128 bits (`futurePrizePool`)
- **Impact:** Every auto-rebuy contribution to `futurePrizePool` during BAF jackpot distribution is silently lost. The ETH disappears from accounting -- solvency invariant broken.
- **Secondary exposure:** The Decimator path at lines 208-213 and 224-231 calls `IDegenerusGame(address(this)).runDecimatorJackpot(...)` via delegatecall. The DecimatorModule's `runDecimatorJackpot` credits winners via `_addClaimableEth` which has its own auto-rebuy path. However, this delegatecall returns to EndgameModule, and any `_setFuturePrizePool` writes inside DecimatorModule happen in the same storage context. These writes are also overwritten by the stale `futurePoolLocal` at line 235.

### SAFE Instances

#### 2. `payDailyJackpot` (`poolSnapshot`) in DegenerusGameJackpotModule -- SAFE

- **Cached variable:** `poolSnapshot` = `currentPrizePool` at line 353
- **Nested calls that reach `_addClaimableEth`:** `_processDailyEth` (line 495) -> `_distributeJackpotEth` -> `_resolveTraitWinners` / `_processOneBucket` -> `_addClaimableEth`. Auto-rebuy writes to `futurePrizePool` and `nextPrizePool` only -- NOT `currentPrizePool`.
- **Write-back check:** `poolSnapshot` is never written back to `currentPrizePool`. It is only used to compute `budget` at line 364: `budget = (poolSnapshot * dailyBps) / 10_000`. The actual `currentPrizePool` mutation at line 503 subtracts `paidDailyEth` (a freshly computed value), not the snapshot.
- **Reason SAFE:** Local is read-only -- never written back to storage. No stale overwrite possible.

#### 3. `_applyTimeBasedFutureTake` in DegenerusGameAdvanceModule -- SAFE

- **Cached variables:** `nextPoolBefore` = `_getNextPrizePool()` at line 1055; `futurePoolBefore` = `_getFuturePrizePool()` at line 1056
- **Intervening calls:** Lines 1055-1117 contain only pure arithmetic (ratio computation, bps calculation, variance rolls). No function calls between the cache reads and the write-backs can reach `_setFuturePrizePool` or `_setNextPrizePool`.
- **Write-back pattern:** Lines 1116-1117 compute `_setNextPrizePool(nextPoolBefore - take - insuranceSkim)` and `_setFuturePrizePool(futurePoolBefore + take)`. These are arithmetic transformations of the snapshots, not literal re-writes of stale values.
- **Reason SAFE:** No function calls between cache and write-back; all intervening code is pure arithmetic. No nested write path exists.

#### 4. `consolidatePrizePools` (`fp`) in DegenerusGameJackpotModule -- SAFE

- **Cached variable:** `fp` = `_getFuturePrizePool()` at line 865 (inside the `(lvl % 100) == 0` block)
- **Intervening code:** Lines 866-873 are pure arithmetic (keepBps multiplication, subtraction). No function calls between `fp` read and `_setFuturePrizePool(keepWei)` at line 870.
- **Note:** `_creditDgnrsCoinflip` (line 876) and `_distributeYieldSurplus` (line 878) are called AFTER the `fp` block completes. `_distributeYieldSurplus` calls `_addClaimableEth` (lines 901-909) which can trigger auto-rebuy writing to `futurePrizePool`. But `fp` is not written back after those calls -- the only write-back is at line 870 inside the if-block.
- **Reason SAFE:** Local `fp` is written back (line 870) before any nested function calls. Subsequent `_distributeYieldSurplus` call is after the write-back, not between cache and write-back.

#### 5. `_distributeYieldSurplus` in DegenerusGameJackpotModule -- SAFE (no cached pool locals)

- **Analysis:** This function reads `currentPrizePool`, `_getNextPrizePool()`, `_getFuturePrizePool()` at lines 886-889 to compute `obligations`, but stores the result in `obligations` (a derived value, not a pool cache). It then calls `_addClaimableEth` (lines 901-909) which can write to `futurePrizePool`/`nextPrizePool` via auto-rebuy. However, `obligations` is never written back to any storage slot.
- **Reason SAFE:** The locals (`obligations`, `yieldPool`, `stakeholderShare`) are derived values used for computation only -- none are written back to pool storage.

#### 6. `_distributePayout` in DegenerusGameDegeneretteModule -- SAFE

- **Cached variable:** `pool` = `_getFuturePrizePool()` at line 687
- **Write-back:** `_setFuturePrizePool(pool)` at line 703 (after deducting `ethPortion`)
- **Subsequent calls:** `_addClaimableEth(player, ethPortion)` at line 704 and `_resolveLootboxDirect` at line 708
- **Critical distinction:** DegeneretteModule's `_addClaimableEth` (line 1153) does NOT have an auto-rebuy path. It only does `claimablePool += weiAmount; _creditClaimable(beneficiary, weiAmount)` -- no writes to `futurePrizePool` or `nextPrizePool`.
- **Reason SAFE:** The `_setFuturePrizePool(pool)` write-back at line 703 happens BEFORE `_addClaimableEth` is called. And DegeneretteModule's `_addClaimableEth` cannot write to `prizePoolsPacked` anyway (no auto-rebuy). No stale overwrite possible.

#### 7. `_autoStakeExcessEth` (`reserve`) in DegenerusGameAdvanceModule -- SAFE

- **Cached variable:** `reserve` = `claimablePool` at line 1262
- **Usage:** `if (ethBal <= reserve) return; uint256 stakeable = ethBal - reserve;` then `steth.submit{value: stakeable}(address(0))` -- an external call to Lido.
- **Write-back check:** `reserve` is never written back to `claimablePool`. It is read-only for computing `stakeable`.
- **Reason SAFE:** Local is read-only -- never written back to storage.

#### 8. `manualStakeEth` (`reserve`) in DegenerusGame -- SAFE

- **Cached variable:** `reserve` derived from `claimablePool` at lines 1842-1844
- **Usage:** Used for arithmetic check `if (ethBal <= reserve) revert E()` and computing `stakeable`.
- **Write-back check:** `reserve` is never written back to `claimablePool`.
- **Reason SAFE:** Local is read-only -- never written back to storage.

#### 9. `_drawDownFuturePrizePool` in DegenerusGameAdvanceModule -- SAFE

- **Pattern:** Reads `_getFuturePrizePool()` at line 1126, computes `reserved`, then at lines 1130-1131 calls `_setFuturePrizePool(_getFuturePrizePool() - reserved)` and `_setNextPrizePool(_getNextPrizePool() + reserved)`.
- **Key observation:** This function does NOT cache into a local and write the local back. It re-reads storage fresh (`_getFuturePrizePool()`) at the write-back site (line 1130). The `reserved` local is a computed delta, not a pool snapshot.
- **Reason SAFE:** No stale local -- storage is re-read at the write site.

#### 10. `_runEarlyBirdLootboxJackpot` in DegenerusGameJackpotModule -- SAFE

- **Pattern:** Lines 774-778: reads `_getFuturePrizePool()` to compute `reserveContribution`, then immediately calls `_setFuturePrizePool(_getFuturePrizePool() - reserveContribution)`. No cached local -- both reads are fresh.
- **Subsequent code:** Lines 800-830 iterate over winners calling `_queueTickets` (writes to ticket queue only, not pool storage). Line 834 calls `_setNextPrizePool(_getNextPrizePool() + totalBudget)`.
- **Reason SAFE:** No stale local -- fresh storage reads at every write site. No `_addClaimableEth` calls in this function.

#### 11. `payDailyJackpot` (purchase reward path, `ethDaySlice`) in DegenerusGameJackpotModule -- SAFE

- **Pattern:** Lines 601-604: reads `_getFuturePrizePool()` twice (line 601 for computation, line 604 for write). Does NOT cache into a local that is written back later.
- **Subsequent call:** `_executeJackpot` (line 617) calls `_distributeJackpotEth` -> `_addClaimableEth`. But the `futurePrizePool` write at line 604 already happened BEFORE `_executeJackpot` is called.
- **Reason SAFE:** Write-back occurs before any nested calls that could modify the same slot.

#### 12. `payDailyJackpot` (daily jackpot init, `reserveSlice`) in DegenerusGameJackpotModule -- SAFE

- **Pattern:** Lines 415-418: reads `_getFuturePrizePool()` to compute `reserveSlice`, then immediately writes `_setFuturePrizePool(_getFuturePrizePool() - reserveSlice)`. No stale local.
- **Reason SAFE:** Fresh re-read at write site; no intervening calls between read and write.

## Contracts With No Candidates

The following contracts were scanned and contain no functions that cache a prize pool storage variable into a local:

| Contract | Reason No Candidates |
|---|---|
| DegenerusGame.sol | Pool reads are either view-only (getters) or use fresh reads at write sites. `manualStakeEth` reserve is read-only. Mint/lootbox paths use `_setPrizePools`/`_setPendingPools` with fresh reads. |
| DegenerusGameMintModule.sol | Uses `_getPrizePools`/`_setPrizePools` with fresh reads at each write site. `claimablePool -= shortfall` at line 675 is a direct storage write, no cache. |
| DegenerusGameBoonModule.sol | No pool storage reads or writes at all. |
| DegenerusGameWhaleModule.sol | Uses `_getPrizePools`/`_setPrizePools` with fresh reads at each write site. No caching pattern. |
| DegenerusGameLootboxModule.sol | No pool storage reads or writes. |
| DegenerusGameMintStreakUtils.sol | No pool storage reads or writes. |
| DegenerusGameGameOverModule.sol | Zeroes all pools (`_setNextPrizePool(0)`, `_setFuturePrizePool(0)`, `currentPrizePool = 0`) at game over. No cache-and-writeback pattern. `claimablePool` updates are additive, not cached. |
| DegenerusAdmin.sol | No pool storage access (different contract, not delegatecall module). |
| DegenerusAffiliate.sol | No pool storage access (different contract). |
| DegenerusJackpots.sol | No pool storage access (different contract, called via normal call not delegatecall). |
| DegenerusVault.sol | No pool storage access (different contract). |
| DegenerusQuests.sol | No pool storage access (different contract). |
| DegenerusStonk.sol | No pool storage access (different contract). |
| StakedDegenerusStonk.sol | No pool storage access (different contract). |
| BurnieCoin.sol | No pool storage access (different contract). |
| BurnieCoinflip.sol | No pool storage access (different contract). |
| DegenerusDeityPass.sol | No pool storage access (different contract). |
| DegenerusTraitUtils.sol | No pool storage access (library-like utility). |
| DeityBoonViewer.sol | No pool storage access (view-only helper). |
| WrappedWrappedXRP.sol | No pool storage access (different contract). |
| Icons32Data.sol | No pool storage access (data-only contract). |
| DegenerusGameModuleInterfaces.sol | Interface definitions only (no implementation). |
| ContractAddresses.sol | Constants only. |

**Libraries scanned (no pool storage access):**
- BitPackingLib.sol, EntropyLib.sol, GameTimeLib.sol, JackpotBucketLib.sol, PriceLookupLib.sol

**Interfaces scanned (no implementation, no pool access):**
- IBurnieCoinflip.sol, IDegenerusAffiliate.sol, IDegenerusCoin.sol, IDegenerusGameModules.sol, IDegenerusGame.sol, IDegenerusJackpots.sol, IDegenerusQuests.sol, IStakedDegenerusStonk.sol, IStETH.sol, IVaultCoin.sol, IVRFCoordinator.sol

## Summary Table

| # | Function | Contract | Cached Variable | Verdict | Reason |
|---|---|---|---|---|---|
| 1 | `runRewardJackpots` | EndgameModule | `futurePoolLocal` (futurePrizePool) | **VULNERABLE** | Auto-rebuy writes to futurePrizePool; stale local written back at line 235 |
| 2 | `payDailyJackpot` (init) | JackpotModule | `poolSnapshot` (currentPrizePool) | SAFE | Read-only local; never written back to storage |
| 3 | `_applyTimeBasedFutureTake` | AdvanceModule | `nextPoolBefore`, `futurePoolBefore` | SAFE | No function calls between cache and write-back; pure arithmetic |
| 4 | `consolidatePrizePools` | JackpotModule | `fp` (futurePrizePool) | SAFE | Write-back at line 870 before any nested calls |
| 5 | `_distributeYieldSurplus` | JackpotModule | `obligations` (derived) | SAFE | Derived value only; never written back to pool storage |
| 6 | `_distributePayout` | DegeneretteModule | `pool` (futurePrizePool) | SAFE | Write-back before `_addClaimableEth`; module's `_addClaimableEth` has no auto-rebuy |
| 7 | `_autoStakeExcessEth` | AdvanceModule | `reserve` (claimablePool) | SAFE | Read-only local; never written back |
| 8 | `manualStakeEth` | DegenerusGame | `reserve` (derived from claimablePool) | SAFE | Read-only local; never written back |
| 9 | `_drawDownFuturePrizePool` | AdvanceModule | (none -- fresh re-reads) | SAFE | Re-reads storage at write site; no stale local |
| 10 | `_runEarlyBirdLootboxJackpot` | JackpotModule | (none -- fresh re-reads) | SAFE | Fresh reads at write sites; no `_addClaimableEth` calls |
| 11 | `payDailyJackpot` (purchase reward) | JackpotModule | `ethDaySlice` (derived) | SAFE | Write-back before nested calls |
| 12 | `payDailyJackpot` (reserveSlice init) | JackpotModule | `reserveSlice` (derived) | SAFE | Fresh re-read at write site |
