# Phase 216 Plan 01: ETH Conservation Proof

**Requirement:** POOL-01 -- Algebraic ETH conservation proof across the consolidated pool architecture.

**Methodology:** Symbolic variables and equations prove all ETH in = all ETH out + all ETH held. Each equation term is grounded by code-level flow traces showing the exact Solidity lines that implement it. Fresh from scratch per D-01; Phase 214 cited as supporting evidence per D-02.

---

## Section 0: Pool Architecture Overview

The v20.0 consolidated pool architecture uses the following storage variables to track ETH:

### Storage Variables

| Variable | Type | Slot | Location | Description |
|----------|------|------|----------|-------------|
| `currentPrizePool` | `uint128` | 1 (low 128) | DegenerusGameStorage L337 | Active level's prize pool; funded at consolidation, drained by daily jackpots |
| `claimablePool` | `uint128` | 1 (high 128) | DegenerusGameStorage L349 | Aggregate ETH liability across all `claimableWinnings` entries |
| `prizePoolsPacked` | `uint256` | 2 | DegenerusGameStorage L362 | Packed: `[128:256] futurePrizePool \| [0:128] nextPrizePool` |
| `claimableWinnings` | `mapping(address => uint256)` | N/A | DegenerusGameStorage L396 | Per-recipient ETH credit (players, sDGNRS, VAULT, GNRUS) |
| `resumeEthPool` | `uint128` | dedicated | DegenerusGameStorage L1020 | Carries ETH between two-call split (CALL1 -> CALL2) |
| `yieldAccumulator` | `uint256` | dedicated | DegenerusGameStorage | Insurance skim accumulator; distributed via yield surplus |

### Access Helpers (DegenerusGameStorage L693-L821)

- `_getPrizePools()` / `_setPrizePools(next, future)` -- unpack/pack `prizePoolsPacked` (L693-L705)
- `_getNextPrizePool()` / `_setNextPrizePool(val)` -- single-component accessors (L784-L805)
- `_getFuturePrizePool()` / `_setFuturePrizePool(val)` -- single-component accessors (L796-L805)
- `_getCurrentPrizePool()` / `_setCurrentPrizePool(val)` -- uint128 narrowing (L813-L821)
- Pending pool accessors: `_getPendingPools()` / `_setPendingPools()` for freeze-mode accumulation (L707-L719)

### Memory-Batch Pattern

`_consolidatePoolsAndRewardJackpots()` (AdvanceModule L620-L797) loads all pools into local variables (`memFuture`, `memCurrent`, `memNext`, `memYieldAcc`), computes all transitions in memory, then writes back in a single batch:

```solidity
// L789-L792: Single SSTORE batch
_setPrizePools(uint128(memNext), uint128(memFuture));
currentPrizePool = uint128(memCurrent);
yieldAccumulator = memYieldAcc;
```

### Two-Call Split Pattern

Daily ETH jackpot distribution may split across two advanceGame calls when winner count exceeds `JACKPOT_MAX_WINNERS`:

- **SPLIT_NONE:** All 4 buckets processed in one call. No `resumeEthPool` write.
- **SPLIT_CALL1:** Largest + solo buckets processed. Writes `resumeEthPool = uint128(ethPool)` at L1290.
- **SPLIT_CALL2:** Mid buckets processed. Reads `ethPool = uint256(resumeEthPool)` then clears `resumeEthPool = 0` at L1194-L1195.

### Pool Freeze Pattern

During VRF window (`prizePoolFrozen = true`), purchases write to pending accumulators (`prizePoolPendingPacked`) instead of live pools. On unfreeze (L770-L777), pending values merge into live pools:

```solidity
_setPrizePools(next + pNext, future + pFuture);
```

---

## Section 1: ETH Inflow Accounting

### EF-01: Purchase (Player ETH -> Pools)

**Entry:** `Game.purchase()` -> delegatecall `MintModule._purchaseFor()` -> `Game.recordMint()` -> `_processMintPayment()` -> pool writes

**Flow trace:**

1. **Payment processing** -- `_processMintPayment()` (Game.sol L903-L962):
   - `DirectEth`: `prizeContribution = amount` (L912)
   - `Claimable`: `prizeContribution = amount`, `claimableWinnings[player] -= amount`, `claimablePool -= uint128(amount)` (L917-L925)
   - `Combined`: `prizeContribution = msg.value + claimableUsed` (L947), deducts `claimableWinnings` and `claimablePool` for shortfall (L931-L942)

2. **Ticket pool split** -- `Game.recordMint()` (Game.sol L358-L381):
   ```solidity
   // L365-L366
   uint256 futureShare = (prizeContribution * PURCHASE_TO_FUTURE_BPS) / 10_000;  // 10%
   uint256 nextShare = prizeContribution - futureShare;                           // 90%
   ```
   If frozen: writes to pending pools (L368-L373); else writes to live pools (L374-L380):
   ```solidity
   _setPrizePools(next + uint128(nextShare), future + uint128(futureShare));
   ```

3. **Lootbox pool split** -- `MintModule._purchaseFor()` (MintModule.sol L1033-L1068):
   - Normal: `futureBps = 9000` (90%), `nextBps = 1000` (10%) -- constants at L113-L114
   - Presale (level 0, nextPool <= 50 ETH): `futureBps = 5000` (50%), `nextBps = 3000` (30%), `vaultBps = 2000` (20%) -- constants at L117-L119
   - Distress mode: `nextBps = 10000` (100%), all to next pool
   ```solidity
   // L1052-L1054
   uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
   uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
   uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;
   ```
   Vault share sent externally (L1070-L1073); pool shares written to live or pending pools (L1056-L1068).

**Symbolic definition:**

Let `I_purchase = msg.value` at `Game.purchase()` entry.

For ticket portion:
- `prizeContribution = ticketCost` (fresh ETH) or `ticketCost` (recycled claimable, net zero to contract balance)
- Pool credit: `futurePool += prizeContribution * 10%`, `nextPool += prizeContribution * 90%`

For lootbox portion:
- Pool credit (normal): `futurePool += lootBoxAmount * 90%`, `nextPool += lootBoxAmount * 10%`
- Pool credit (presale): `futurePool += 50%`, `nextPool += 30%`, external VAULT += 20%
- Pool credit (distress): `nextPool += 100%`

**Conservation equation:**

```
I_purchase = ticketCost_fresh + lootBoxAmount_fresh
           = (prizeContribution from fresh ETH) + lootboxFreshEth

ticket portion: futurePool_delta + nextPool_delta = prizeContribution (fresh ETH component)
lootbox portion: futurePool_delta + nextPool_delta + vaultShare_external = lootBoxAmount (fresh ETH)
```

The claimable recycling path is a zero-sum internal transfer: `claimableWinnings[player]` and `claimablePool` decrease by `shortfall`, and `prizeContribution` increases by `shortfall`. The contract's ETH balance is unchanged by claimable recycling.

**Overpay handling:** `DirectEth` allows `msg.value >= costWei` (L911); excess ETH remains in contract balance as untracked surplus. This is a known design choice (not a leak -- excess sits in contract balance alongside pool-tracked ETH).

**Verdict:** CONSERVED -- Every wei of `msg.value` is allocated to `futurePool`, `nextPool`, or external `VAULT`. Claimable recycling is a zero-sum internal transfer.

---

### EF-16: Whale Passes (Player ETH -> Pools)

**Entry:** `Game.purchaseWhaleBundle()` / `purchaseLazyPass()` / `purchaseDeityPass()` -> delegatecall `WhaleModule`

#### EF-16a: Whale Bundle

**Flow trace** -- `WhaleModule._purchaseWhaleBundle()` (WhaleModule.sol L194-L365):

1. Price: `msg.value == totalPrice` enforced at L262
2. Pool split (L336-L357):
   ```solidity
   // L339-L343: Pre-game 70/30, post-game 95/5 (future/next)
   if (level == 0) {
       nextShare = (totalPrice * 3000) / 10_000;   // 30%
   } else {
       nextShare = (totalPrice * 500) / 10_000;     // 5%
   }
   // futureShare = totalPrice - nextShare (implicit)
   ```
   Written to live or pending pools (L345-L357).

**Verdict:** CONSERVED -- `nextShare + futureShare = totalPrice = msg.value`.

#### EF-16b: Lazy Pass

**Flow trace** -- `WhaleModule._purchaseLazyPass()` (WhaleModule.sol L384-L518):

1. Price: `msg.value == totalPrice` enforced at L474
2. Pool split (L485-L503):
   ```solidity
   // L486: LAZY_PASS_TO_FUTURE_BPS = 1000 (10%)
   uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;
   uint256 nextShare;
   unchecked { nextShare = totalPrice - futureShare; }  // 90%
   ```
   Written to live or pending pools (L491-L503).

**Verdict:** CONSERVED -- `futureShare + nextShare = totalPrice = msg.value`.

#### EF-16c: Deity Pass

**Flow trace** -- `WhaleModule._purchaseDeityPass()` (WhaleModule.sol L542-L674):

1. Price: `msg.value == totalPrice` enforced at L581
2. Pool split (L638-L657):
   ```solidity
   // L640-L644: Pre-game 70/30, post-game 95/5
   if (level == 0) {
       nextShare = (totalPrice * 3000) / 10_000;
   } else {
       nextShare = (totalPrice * 500) / 10_000;
   }
   // futureShare = totalPrice - nextShare
   ```
   Written to live or pending pools (L645-L657).

**Verdict:** CONSERVED -- `nextShare + futureShare = totalPrice = msg.value`.

**Symbolic definition:**

```
I_whale = msg.value (exact match enforced by revert)
futurePool_delta + nextPool_delta = I_whale  (for all three pass types)
```

---

### EF-17: Degenerette Bets (Player ETH -> futurePool)

**Entry:** `DegeneretteModule.placeBet()` -> `_collectBetFunds()`

**Flow trace** -- `DegeneretteModule._collectBetFunds()` (DegeneretteModule.sol L511-L545):

For `currency == CURRENCY_ETH`:

1. Payment validation: `ethPaid <= totalBet` (L519)
2. Claimable shortfall: if `ethPaid < totalBet`, pulls `totalBet - ethPaid` from `claimableWinnings[player]` and `claimablePool` (L521-L525)
3. Pool write (L528-L535):
   ```solidity
   // All bet ETH goes to futurePool
   if (prizePoolFrozen) {
       _setPendingPools(pNext, pFuture + uint128(totalBet));
   } else {
       _setPrizePools(next, future + uint128(totalBet));
   }
   ```

**Symbolic definition:**

```
I_bet = ethPaid (fresh ETH from msg.value)
claimable_shortfall = totalBet - ethPaid  (internal recycling, zero-sum)
futurePool_delta = totalBet = ethPaid + claimable_shortfall
```

The `totalBet` amount is credited to `futurePool`. Fresh ETH (`ethPaid`) enters the contract; claimable shortfall is an internal transfer from `claimableWinnings`/`claimablePool` to `futurePool`.

**Verdict:** CONSERVED -- `futurePool_delta = totalBet = I_bet + claimable_recycled`. No ETH created or destroyed.

---

## Section 2: Internal Flow Accounting

### EF-02: Pool Consolidation (Internal Transfer Between Pools)

**Entry:** `AdvanceModule._consolidatePoolsAndRewardJackpots()` (AdvanceModule.sol L620-L797)

This is the central pool arithmetic engine. All operations happen in memory variables, written back in a single batch.

**Flow trace:**

1. **Load** (L627-L630):
   ```solidity
   uint256 memFuture = _getFuturePrizePool();
   uint256 memCurrent = _getCurrentPrizePool();
   uint256 memNext = _getNextPrizePool();
   uint256 memYieldAcc = yieldAccumulator;
   ```

2. **Time-based take: next -> future** (L633-L698):
   ```solidity
   // L696-L698
   memNext -= take + insuranceSkim;
   memFuture += take;
   memYieldAcc += insuranceSkim;    // INSURANCE_SKIM_BPS = 100 (1%)
   ```
   Conservation: `memNext_before = memNext_after + take + insuranceSkim` and `memFuture_after = memFuture_before + take` and `memYieldAcc_after = memYieldAcc_before + insuranceSkim`.
   Net: `memNext_before + memFuture_before + memYieldAcc_before = memNext_after + memFuture_after + memYieldAcc_after`. ZERO-SUM.

3. **x00 yield dump: yieldAccumulator -> future** (L701-L706):
   ```solidity
   if ((lvl % 100) == 0) {
       uint256 half = memYieldAcc >> 1;
       memFuture += half;
       memYieldAcc -= half;
   }
   ```
   Conservation: `memFuture_delta = +half`, `memYieldAcc_delta = -half`. ZERO-SUM.

4. **BAF jackpot draw: future -> claimable** (L715-L726):
   ```solidity
   uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord);
   memFuture -= claimed;
   claimableDelta += claimed;
   ```
   This is a cross-contract self-call that credits `claimableWinnings` entries and returns the net `claimableDelta`. Conservation: `memFuture_delta = -claimed`, `claimableDelta = +claimed`. ZERO-SUM.

5. **Decimator jackpot draw: future -> claimable/return** (L729-L746):
   ```solidity
   uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
   uint256 spend = decPoolWei - returnWei;
   memFuture -= spend;
   claimableDelta += spend;
   ```
   If no qualifying burns, `returnWei = decPoolWei`, `spend = 0`. Otherwise `spend` is held for claims. Conservation: `memFuture_delta = -spend`, `claimableDelta = +spend`. ZERO-SUM.

6. **x00 keep roll: future -> current** (L748-L769):
   ```solidity
   uint256 moveWei = memFuture - (memFuture * keepBps) / 10_000;
   memFuture -= moveWei;
   memCurrent += moveWei;
   ```
   Conservation: `memFuture_delta = -moveWei`, `memCurrent_delta = +moveWei`. ZERO-SUM.

7. **Merge next -> current** (L771-L773):
   ```solidity
   memCurrent += memNext;
   memNext = 0;
   ```
   Conservation: `memCurrent_delta = +memNext_before`, `memNext_after = 0`. ZERO-SUM.

8. **Future -> next drawdown (non-x00)** (L782-L787):
   ```solidity
   uint256 reserved = (memFuture * 15) / 100;
   memFuture -= reserved;
   memNext = reserved;
   ```
   Conservation: `memFuture_delta = -reserved`, `memNext_delta = +reserved`. ZERO-SUM.

9. **Batch writeback** (L789-L795):
   ```solidity
   _setPrizePools(uint128(memNext), uint128(memFuture));
   currentPrizePool = uint128(memCurrent);
   yieldAccumulator = memYieldAcc;
   if (claimableDelta != 0) {
       claimablePool += uint128(claimableDelta);
   }
   ```

**Global conservation proof for consolidation:**

Define `S = memFuture + memCurrent + memNext + memYieldAcc + claimableDelta` (total tracked ETH).

At each step above, the sum `S` is invariant (every deduction from one variable is added to another). Therefore:

```
S_before = memFuture_0 + memCurrent_0 + memNext_0 + memYieldAcc_0 + 0
S_after  = memFuture_N + memCurrent_N + memNext_N + memYieldAcc_N + claimableDelta
S_before = S_after
```

The batch writeback writes exactly `memFuture_N`, `memCurrent_N`, `memNext_N`, `memYieldAcc_N` to storage, and adds `claimableDelta` to `claimablePool`. No intermediate value is lost.

**uint128 narrowing safety:** All pool values are narrowed to `uint128` at writeback. Phase 214 (214-02) proved that maximum ETH values are far below `uint128` max (~3.4e38 wei >> total ETH supply ~1.2e26 wei). No truncation occurs.

**Verdict:** CONSERVED -- All arithmetic is zero-sum across memory variables. Batch writeback stores exactly the computed values. No ETH created or destroyed.

---

### EF-03: Yield Surplus Distribution (yieldAccumulator -> claimableWinnings)

**Entry:** `JackpotModule.distributeYieldSurplus()` (JackpotModule.sol L716-L750)

**Flow trace:**

1. **Calculate surplus** (L717-L727):
   ```solidity
   uint256 totalBal = address(this).balance + stBal;
   uint256 obligations = _getCurrentPrizePool() + _getNextPrizePool() +
       claimablePool + _getFuturePrizePool() + yieldAccumulator;
   if (totalBal <= obligations) return;
   uint256 yieldPool = totalBal - obligations;
   ```

2. **23% shares** (L728):
   ```solidity
   uint256 quarterShare = (yieldPool * 2300) / 10_000;
   ```

3. **Credit three recipients** (L730-L745):
   ```solidity
   _addClaimableEth(ContractAddresses.VAULT, quarterShare, rngWord);
   _addClaimableEth(ContractAddresses.SDGNRS, quarterShare, rngWord);
   _addClaimableEth(ContractAddresses.GNRUS, quarterShare, rngWord);
   ```
   Each `_addClaimableEth` increments `claimableWinnings[recipient]` by `quarterShare`.

4. **claimablePool update** (L746-L747):
   ```solidity
   uint256 claimableDelta = d0 + d1 + d2;
   if (claimableDelta != 0) claimablePool += uint128(claimableDelta);
   ```

5. **yieldAccumulator top-up** (L748):
   ```solidity
   yieldAccumulator += quarterShare;
   ```

**Symbolic:**
```
yieldPool = totalBal - obligations (surplus ETH from staking yield)
distributed = 3 * quarterShare = 3 * (yieldPool * 23%)  = 69% of yield
buffer_retained = yieldPool - distributed - quarterShare_to_yieldAcc
yieldAccumulator_delta = +quarterShare (23%)
claimable_delta = +3 * quarterShare (69%)
unallocated = yieldPool - 4 * quarterShare = 8% of yield (rounding dust, stays in contract balance)
```

Note: The yield surplus is not deducted from any pool variable -- it is the excess of contract balance over all obligations. The distribution creates new claimable entries funded by the yield surplus.

**Conservation:** `distributed + yieldAcc_increase + unallocated = yieldPool`. All terms are positive, no overcounting. The 8% buffer remains as contract balance surplus (still covered by `totalBal`). The surplus itself arises from stETH rebasing, not from pool arithmetic.

**Verdict:** CONSERVED -- Surplus ETH is distributed without exceeding the available surplus. No ETH created from pools; all funded by actual contract balance excess.

---

### EF-14: GNRUS Charity Distribution (GNRUS Token Transfer, Not ETH)

**Entry:** `GNRUS.pickCharity()` (GNRUS.sol L452-L508)

**Flow trace:**

```solidity
// L491-L492
uint256 unallocated = balanceOf[address(this)];
uint256 distribution = (unallocated * DISTRIBUTION_BPS) / BPS_DENOM;  // 2%
```

Then transfers GNRUS tokens (L502-L506):
```solidity
balanceOf[address(this)] = unallocated - distribution;
balanceOf[recipient] += distribution;
```

**Key observation:** This is a GNRUS token transfer, not an ETH transfer. No ETH pool variables are touched. The 2% distribution moves GNRUS from the contract's unallocated pool to the winning charity address.

**ETH impact:** None. GNRUS tokens have backing ETH (via `GNRUS.burn()` redemption), but `pickCharity` only moves token ownership. The backing ETH in GNRUS remains unchanged.

**Verdict:** CONSERVED -- No ETH is created, destroyed, or moved between pools. Pure GNRUS token redistribution.

---

### EF-20: BURNIE Flip Credit (Cross-Contract Call, Not ETH Transfer)

**Entry:** `AdvanceModule._consolidatePoolsAndRewardJackpots()` -> `coinflip.creditFlip()` (AdvanceModule.sol L776-L780)

**Flow trace:**

```solidity
// L776-L780
coinflip.creditFlip(
    ContractAddresses.SDGNRS,
    (memCurrent * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(level) * 20)
);
```

**Key observation:** `creditFlip()` is an external call to the BurnieCoinflip contract that credits BURNIE flip balance. No ETH is transferred -- this is a BURNIE-denominated credit based on the current pool size. No `value` is passed with the call.

**ETH impact:** None. Pool memory variables are read but not modified by this call. The call happens between step 7 (merge next->current) and step 8 (future->next drawdown) in consolidation. No ETH flows to or from the coinflip contract.

**Verdict:** CONSERVED -- No ETH involved. Pure BURNIE credit accounting.

---

### Two-Call Split Conservation Proof

**Mechanism:** When daily jackpot winner count exceeds `JACKPOT_MAX_WINNERS`, processing splits across two `advanceGame` calls.

**CALL1 flow** (JackpotModule `_processDailyEth()` L1182-L1292 with `splitMode = SPLIT_CALL1`):

1. `ethPool` = `dailyEthBudget` (passed in from `payDailyJackpot`)
2. Largest + solo buckets processed; winners credited via `_addClaimableEth`
3. At L1289-L1291:
   ```solidity
   if (splitMode == SPLIT_CALL1) {
       resumeEthPool = uint128(ethPool);
   }
   ```
   Note: `ethPool` is the ORIGINAL budget, not the remaining after payouts. The `paidEth` tracking is separate -- the calling function (`payDailyJackpot` L474-L486) deducts `paidDailyEth` from `currentPrizePool`.

4. `currentPrizePool -= paidDailyEth` (L485, non-final day) or `currentPrizePool -= dailyEthBudget` with unpaid to future (L477-L483, final day)
5. `claimablePool += liabilityDelta` (L1284-L1286)

**CALL2 flow** (`_resumeDailyEth()` L1131-L1156 -> `_processDailyEth()` with `splitMode = SPLIT_CALL2`):

1. At L1193-L1196:
   ```solidity
   if (splitMode == SPLIT_CALL2) {
       ethPool = uint256(resumeEthPool);
       resumeEthPool = 0;
   }
   ```
2. Mid buckets processed; winners credited via `_addClaimableEth`
3. `paidEth2` returned to `_resumeDailyEth`
4. Pool deduction at L1149-L1155:
   ```solidity
   if (paidEth2 != 0) {
       if (isFinal) {
           _setFuturePrizePool(_getFuturePrizePool() - paidEth2);
       } else {
           _setCurrentPrizePool(_getCurrentPrizePool() - paidEth2);
       }
   }
   ```

**Conservation proof:**

- **CALL1:** `currentPrizePool -= paidEth1`. `claimablePool += liability1`. `resumeEthPool = ethPool` (budget snapshot for CALL2).
- **CALL2:** reads `resumeEthPool`, clears to 0. `currentPrizePool -= paidEth2`. `claimablePool += liability2`.

The `resumeEthPool` is NOT an additional ETH balance -- it is a memo of the original budget so CALL2 knows the pool size for winner count scaling. The actual ETH deduction is always from `currentPrizePool` (or `futurePrizePool` on final day).

Total pool deduction: `paidEth1 + paidEth2` (exactly what was credited to `claimableWinnings`).
`resumeEthPool` starts at 0, is set in CALL1, cleared in CALL2 -- net effect is zero.

After CALL2: `resumeEthPool = 0` (confirmed at L1195).

**Verdict:** CONSERVED -- `resumeEthPool` is a transient memo, not a separate ETH balance. Pool deductions match claimable credits across both calls. `resumeEthPool` returns to zero after completion.

---

### Inflow + Internal Summary Table

| Chain | Direction | Entry | Pool(s) Written | Symbolic Equation | Verdict |
|-------|-----------|-------|-----------------|-------------------|---------|
| EF-01 | Inflow | `Game.purchase()` | futurePool, nextPool, (VAULT external) | `I_purchase = futurePool_delta + nextPool_delta + vaultShare` | CONSERVED |
| EF-16 | Inflow | `WhaleModule.purchase*()` | futurePool, nextPool | `I_whale = futurePool_delta + nextPool_delta` | CONSERVED |
| EF-17 | Inflow | `DegeneretteModule._collectBetFunds()` | futurePool | `I_bet = futurePool_delta` (plus internal claimable recycling) | CONSERVED |
| EF-02 | Internal | `AdvanceModule._consolidatePoolsAndRewardJackpots()` | all pools | `S_before = S_after` (zero-sum across 8 steps) | CONSERVED |
| EF-03 | Internal->Out | `JackpotModule.distributeYieldSurplus()` | claimableWinnings, yieldAccumulator | `distributed + yieldAcc_delta + buffer = yieldPool` | CONSERVED |
| EF-14 | Internal | `GNRUS.pickCharity()` | (none -- GNRUS token only) | No ETH flow | CONSERVED |
| EF-20 | Internal | `coinflip.creditFlip()` | (none -- BURNIE credit only) | No ETH flow | CONSERVED |
| Split | Internal | `resumeEthPool` (CALL1->CALL2) | resumeEthPool (transient) | `resumeEthPool_final = 0`, pool deductions match credits | CONSERVED |

---

## Section 3: ETH Outflow Accounting

### EF-04: Daily Jackpot (currentPrizePool -> claimableWinnings)

**Entry:** `JackpotModule.payDailyJackpot()` (JackpotModule.sol L310-L536) -> `_processDailyEth()` (L1182-L1292) -> `_addClaimableEth()` (L764-L788)

**Flow trace (jackpot phase, days 1-4):**

1. **Budget calculation** (L346-L357):
   ```solidity
   uint256 poolSnapshot = _getCurrentPrizePool();
   uint16 dailyBps = _dailyCurrentPoolBps(counter, randWord);  // 600-1400 (6%-14%)
   uint256 budget = (poolSnapshot * dailyBps) / 10_000;
   ```

2. **Lootbox/ticket split** (L366-L382):
   ```solidity
   uint256 dailyLootboxBudget = budget / 5;          // 20% for lootbox tickets
   if (dailyLootboxBudget != 0) budget -= dailyLootboxBudget;
   // Lootbox budget: currentPrizePool -= dailyLootboxBudget, nextPrizePool += dailyLootboxBudget
   _setCurrentPrizePool(_getCurrentPrizePool() - dailyLootboxBudget);
   _setNextPrizePool(_getNextPrizePool() + dailyLootboxBudget);
   ```
   This is an internal transfer (current -> next). Conservation: zero-sum.

3. **Carryover ticket reservation** (L402-L410, days 2-4):
   ```solidity
   reserveSlice = futurePoolBal / 200;                // 0.5% of futurePool
   _setFuturePrizePool(futurePoolBal - reserveSlice);
   _setNextPrizePool(_getNextPrizePool() + reserveSlice);
   ```
   Internal transfer (future -> next). Conservation: zero-sum.

4. **ETH distribution** via `_processDailyEth()` (L1182-L1292):
   - Bucket shares computed from `ethPool` (= `budget` after lootbox deduction)
   - For each bucket, winners selected via `_randTraitTicket()`
   - Each winner credited via `_addClaimableEth()` which calls `_creditClaimable()` (PayoutUtils.sol L33-L38):
     ```solidity
     claimableWinnings[beneficiary] += weiAmount;
     ```
   - Auto-rebuy path: if enabled, `_processAutoRebuy()` converts to tickets, adding ETH to future/nextPool instead of claimable
   - `claimablePool += uint128(liabilityDelta)` at L1284-L1286

5. **Pool deduction** (L484-L486 non-final, L474-L483 final):
   ```solidity
   // Non-final: deduct only what was paid
   _setCurrentPrizePool(_getCurrentPrizePool() - paidDailyEth);
   // Final: deduct full budget, unpaid to future
   _setCurrentPrizePool(_getCurrentPrizePool() - dailyEthBudget);
   if (unpaidDailyEth != 0) _setFuturePrizePool(_getFuturePrizePool() + unpaidDailyEth);
   ```

**Flow trace (purchase phase, level 1+):**

1. ETH drip: `ethDaySlice = (_getFuturePrizePool() * 100) / 10_000` -- 1% of futurePool (L500-L501)
2. Lootbox budget: `lootboxBudget = (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000` (L507)
3. `_executeJackpot()` -> `_processDailyEth()` with `SPLIT_NONE` (L510-L518)
4. Deduction: `_setFuturePrizePool(_getFuturePrizePool() - lootboxBudget - paidEth)` (L521-L524)
5. Lootbox budget -> `_distributeLootboxAndTickets()` which adds to nextPool (L527-L535)

**Symbolic:**
```
O_daily = SUM(_addClaimableEth credits from daily ETH jackpot)
currentPrizePool -= paidDailyEth (or full budget on final day)
claimablePool += liabilityDelta
claimableWinnings[winner] += perWinner (for each winner)
```

**Conservation:** `currentPrizePool_deduction = paidEth (credited to winners) + unpaidEth (returned to future on final day)`. Lootbox and carryover are internal transfers (current->next, future->next). No ETH created or destroyed.

**Verdict:** CONSERVED

---

### EF-05: Solo Bucket Winner (currentPrizePool -> claimableWinnings + futurePool)

**Entry:** `JackpotModule._handleSoloBucketWinner()` (L1404-L1456) -> `_processSoloBucketWinner()` (L1489-L1532)

**Flow trace:**

```solidity
// L1505-L1506: 75/25 split
uint256 quarterAmount = perWinner >> 2;
uint256 whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE;
```

If `whalePassCount != 0`:
```solidity
// L1510-L1522
uint256 whalePassCost = whalePassCount * HALF_WHALE_PASS_PRICE;
uint256 ethAmount = perWinner - whalePassCost;
_addClaimableEth(winner, ethAmount, entropy);     // ETH portion to claimable
whalePassClaims[winner] += whalePassCount;         // Whale pass credit (non-ETH)
_setFuturePrizePool(_getFuturePrizePool() + whalePassCost);  // Whale pass ETH to future
```

If `whalePassCount == 0` (25% too small for a half-pass):
```solidity
// L1524-L1530: 100% as ETH
_addClaimableEth(winner, perWinner, entropy);
```

**Symbolic:**
```
O_solo = ethAmount + whalePassCost = perWinner
ethAmount -> claimableWinnings[winner]
whalePassCost -> futurePool (internal re-investment, not an outflow)
```

**Conservation:** `perWinner` (from pool budget) is fully accounted: ETH portion credited to winner, whale pass portion recycled to futurePool. The parent `_processDailyEth()` tracks `paidDelta = ethAmount` and `paidDelta += whalePassSpent` separately. Total tracked = `perWinner`. Pool deduction in `payDailyJackpot` covers the full amount.

**Verdict:** CONSERVED

---

### EF-06: BAF Jackpot (futurePool -> claimableWinnings + futurePool/nextPool)

**Entry:** `JackpotModule.runBafJackpot()` (L1977-L2056) called via self-call from consolidation (AdvanceModule L719-L725)

**Flow trace:**

1. Self-call guard: `if (msg.sender != address(this)) revert E()` (L1982)
2. External call to `jackpots.runBafJackpot()` for winner selection (L1984-L1985)
3. For each winner:
   - **Large winners** (>= 5% of pool): 50% ETH via `_addClaimableEth`, 50% lootbox (tickets or whale pass claim)
   - **Small winners** (< 5%): alternate 100% ETH (even index) or 100% lootbox (odd index)
4. Returns `claimableDelta` to caller

**Lootbox portion handling:**
- Small lootbox: `_awardJackpotTickets()` -- converts ETH to tickets backed by pool (L2048)
- Large lootbox <= threshold: same as small
- Large lootbox > threshold: `_queueWhalePassClaimCore()` -- deferred whale pass claim (L2028)

**Symbolic:**
```
O_baf = claimableDelta (returned to consolidation)
memFuture -= claimableDelta (in consolidation, L724)
```

The BAF pool amount comes from futurePool (`bafPoolWei = (baseMemFuture * bafPct) / 100` at AdvanceModule L717). What is NOT claimed (`lootboxPortion` converted to tickets) stays as internal pool reallocation (tickets backed by pool).

**Conservation:** `memFuture -= claimed` in consolidation. `claimablePool += claimableDelta` at batch writeback (L793-L795). Lootbox portions are internal transfers to ticket backing. No ETH created or destroyed.

**Verdict:** CONSERVED

---

### EF-07: Decimator Jackpot (futurePool -> claimableWinnings via deferred claim)

**Entry:** `DecimatorModule.runDecimatorJackpot()` (L195-L247) -> snapshot; `claimDecimatorJackpot()` (L307-L328) -> `_creditClaimable()`

**Flow trace:**

1. **Snapshot** (called from consolidation): `decClaimRounds[lvl].poolWei = poolWei` (L242). Returns 0 (all funds held for claims). In consolidation: `memFuture -= spend` (AdvanceModule L733-L735).

2. **Claim** (`claimDecimatorJackpot()` L307-L328):
   ```solidity
   uint256 amountWei = _consumeDecClaim(msg.sender, lvl);  // pro-rata share
   // Normal mode (not gameover):
   uint256 lootboxPortion = _creditDecJackpotClaimCore(msg.sender, amountWei, ...);
   if (lootboxPortion != 0) {
       _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);
   }
   ```

3. **_creditDecJackpotClaimCore()** (L354-L368):
   ```solidity
   uint256 ethPortion = amount >> 1;          // 50% ETH
   lootboxPortion = amount - ethPortion;       // 50% lootbox
   _creditClaimable(account, ethPortion);       // Credit ETH portion
   claimablePool -= uint128(lootboxPortion);    // Remove lootbox from liability
   _awardDecimatorLootbox(account, lootboxPortion, rngWord);  // Award tickets
   ```

**Symbolic:**
```
At snapshot: memFuture -= decPoolWei, claimableDelta += decPoolWei
At claim: claimableWinnings[player] += ethPortion (50%)
           claimablePool -= lootboxPortion (50%)
           futurePool += lootboxPortion (lootbox re-invested)
```

**Conservation:** At snapshot time, `decPoolWei` is moved from `memFuture` to `claimableDelta` (which becomes `claimablePool` at batch writeback). At claim time, 50% goes to player (reducing `claimablePool` implicitly via claim), 50% goes back to `futurePool` (lootbox portion explicitly removed from `claimablePool` at L366).

Note: `claimablePool` is updated at snapshot time (`+= decPoolWei` via `claimableDelta`), then at claim time both portions are accounted: ETH portion stays as `claimableWinnings[player]` (claimed later via `_claimWinningsInternal`), lootbox portion explicitly deducted from `claimablePool` and added to `futurePool`.

**Verdict:** CONSERVED

---

### EF-08: Terminal Decimator Jackpot (gameover funds -> claimableWinnings)

**Entry:** `DecimatorModule.runTerminalDecimatorJackpot()` (L723-L771) -> snapshot; `claimTerminalDecimatorJackpot()` (L779-L783) -> `_creditClaimable()`

**Flow trace:**

1. **Snapshot** (called from `handleGameOverDrain`): stores `poolWei` and `totalBurn` (L766-L768). Returns 0 if qualifying burns exist (all funds held), else returns `poolWei` (refunded).

2. **Claim** (L779-L783):
   ```solidity
   uint256 amountWei = _consumeTerminalDecClaim(msg.sender);
   _creditClaimable(msg.sender, amountWei);
   ```
   `_consumeTerminalDecClaim()` (L817-L844): calculates pro-rata `amountWei = (poolWei * weight) / totalBurn`, marks claimed by zeroing `weightedBurn`.

3. **claimablePool accounting** (in `handleGameOverDrain` L165):
   ```solidity
   if (decSpend != 0) {
       claimablePool += uint128(decSpend);
   }
   ```

**Symbolic:**
```
At gameover: claimablePool += decSpend (decPool - refund)
At claim: claimableWinnings[player] += pro_rata_share
```

**Conservation:** `decSpend` is the total amount reserved for claims. Individual claims sum to at most `decSpend` (pro-rata shares sum to `poolWei` when `totalBurn` matches). `_creditClaimable` only writes to `claimableWinnings`, not `claimablePool` -- the pool liability was pre-reserved at gameover time.

**Verdict:** CONSERVED

---

### EF-09: Degenerette Winnings (futurePool -> claimableWinnings)

**Entry:** `DegeneretteModule._distributePayout()` (DegeneretteModule.sol L684-L740) -> `_addClaimableEth()` (L1090-L1094)

**Flow trace (ETH currency):**

1. **Split** (L691-L693):
   ```solidity
   uint256 ethPortion = payout / 4;              // 25% ETH
   uint256 lootboxPortion = payout - ethPortion;  // 75% lootbox
   ```

2. **ETH credit (unfrozen)** (L713-L728):
   ```solidity
   uint256 pool = _getFuturePrizePool();
   uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;  // 10% cap
   if (ethPortion > maxEth) { lootboxPortion += ethPortion - maxEth; ethPortion = maxEth; }
   pool -= ethPortion;
   _setFuturePrizePool(pool);
   _addClaimableEth(player, ethPortion);
   ```

3. **ETH credit (frozen)** (L695-L711):
   ```solidity
   // Solvency check: pending future must cover payout
   if (uint256(pFuture) < ethPortion) revert E();
   _setPendingPools(pNext, pFuture - uint128(ethPortion));
   _addClaimableEth(player, ethPortion);
   ```

4. **DegeneretteModule._addClaimableEth()** (L1090-L1094):
   ```solidity
   claimablePool += uint128(weiAmount);
   _creditClaimable(beneficiary, weiAmount);
   ```
   Note: This is a separate `_addClaimableEth` from JackpotModule's -- it directly increments `claimablePool` (no auto-rebuy path).

5. **Lootbox resolution** (L732-L734): converted to tickets via `_resolveLootboxDirect()`

**Symbolic:**
```
O_degen = ethPortion (credited to claimableWinnings)
futurePool -= ethPortion (or pendingFuture -= ethPortion when frozen)
claimablePool += ethPortion
```

**Conservation:** `futurePool_deduction = ethPortion = claimablePool_increase`. Lootbox portion converts bet winnings to tickets (internal). The 10% cap on ETH portion ensures solvency against futurePool; excess rolls to lootbox.

**Verdict:** CONSERVED

---

### EF-10: Game Over Drain (All Pools -> claimableWinnings + external)

**Entry:** `GameOverModule.handleGameOverDrain()` (GameOverModule.sol L79-L181)

**Flow trace:**

1. **Pre-drain state** (L84-L90):
   ```solidity
   uint256 totalFunds = ethBal + stBal;
   uint256 preRefundAvailable = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
   ```

2. **Deity pass refunds** (L104-L133, level < 10):
   ```solidity
   claimableWinnings[owner] += refund;
   totalRefunded += refund;
   claimablePool += uint128(totalRefunded);
   ```

3. **Zero all pool variables** (L143-L147):
   ```solidity
   _setNextPrizePool(0);
   _setFuturePrizePool(0);
   _setCurrentPrizePool(0);
   yieldAccumulator = 0;
   ```

4. **Recalculate available** (L150):
   ```solidity
   uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;
   ```

5. **Terminal decimator** (L160-L169): 10% of `remaining` to `runTerminalDecimatorJackpot`. Refunds returned to `remaining`:
   ```solidity
   remaining -= decPool;
   remaining += decRefund;  // Unclaimed returns to remaining
   claimablePool += uint128(decSpend);  // Claimed portion reserved
   ```

6. **Terminal jackpot** (L173-L180): 90% (+ refund) to `runTerminalJackpot` -> `_processDailyEth()` with `SPLIT_NONE`:
   ```solidity
   uint256 termPaid = runTerminalJackpot(remaining, lvl + 1, rngWord);
   remaining -= termPaid;
   if (remaining != 0) { _sendToVault(remaining, stBal); }
   ```

**Symbolic:**
```
O_drain = deity_refunds + decSpend + termPaid + vault_remainder
        = claimablePool_increase + external_sends

available = totalFunds - claimablePool (pre-drain, after refunds)
claimablePool += deity_refunds + decSpend (reserved for claims)
termPaid -> claimableWinnings[winners] (via _processDailyEth -> _addClaimableEth)
remaining -> _sendToVault (external send to sDGNRS/VAULT/GNRUS)
```

**Conservation:** All pool variables zeroed. `available = totalFunds - claimablePool`. This is then allocated: `decPool + remaining = available`. `decSpend + decRefund = decPool`. `termPaid + vault_remainder = remaining`. Every wei of `available` is either reserved as `claimablePool` increase or sent externally. The pre-existing `claimablePool` (from pre-drain claimable winnings) remains intact.

**Verdict:** CONSERVED

---

### EF-11: Final Sweep (All Remaining -> External)

**Entry:** `GameOverModule.handleFinalSweep()` (GameOverModule.sol L188-L208) -> `_sendToVault()` (L217-L225) -> `_sendStethFirst()` (L232-L247)

**Flow trace:**

1. **Guards** (L189-L191): gameOver set, 30 days elapsed, not already swept
2. **Reset claimablePool** (L194): `claimablePool = 0`
3. **Total funds** (L199-L201):
   ```solidity
   uint256 ethBal = address(this).balance;
   uint256 stBal = steth.balanceOf(address(this));
   uint256 totalFunds = ethBal + stBal;
   ```
4. **_sendToVault()** (L217-L225):
   ```solidity
   uint256 thirdShare = amount / 3;                        // 33%
   uint256 gnrusAmount = amount - thirdShare - thirdShare;  // 34%
   _sendStethFirst(ContractAddresses.SDGNRS, thirdShare, stethBal);
   _sendStethFirst(ContractAddresses.VAULT, thirdShare, stethBal);
   _sendStethFirst(ContractAddresses.GNRUS, gnrusAmount, stethBal);
   ```
5. **_sendStethFirst()** (L232-L247): sends stETH first via `steth.transfer()`, then ETH for remainder via `.call{value: ethAmount}("")`

**Symbolic:**
```
O_sweep = totalFunds = thirdShare + thirdShare + gnrusAmount
        = 33% + 33% + 34% of (ETH + stETH balance)
claimablePool = 0 (all unclaimed forfeited)
```

**Conservation:** All contract balance (ETH + stETH) is sent to three recipients. `thirdShare + thirdShare + gnrusAmount = totalFunds` (by construction: `gnrusAmount = totalFunds - 2 * thirdShare`). After sweep, contract balance = 0.

**Verdict:** CONSERVED

---

### EF-12: Player Claim (claimableWinnings -> ETH Transfer)

**Entry:** `Game._claimWinningsInternal()` (Game.sol L1366-L1381)

**Flow trace:**

```solidity
// L1368-L1374
uint256 amount = claimableWinnings[player];
if (amount <= 1) revert E();
claimableWinnings[player] = 1;    // Leave 1 wei sentinel
payout = amount - 1;
// L1375: CEI - state update before external call
claimablePool -= uint128(payout);
// L1377-L1381: Transfer
if (stethFirst) { _payoutWithEthFallback(player, payout); }
else { _payoutWithStethFallback(player, payout); }
```

**`_payoutWithEthFallback()`** (Game.sol L1984-L1998): sends stETH first (up to balance), then ETH for remainder. Total sent = `payout`.

**Symbolic:**
```
O_claim = payout = claimableWinnings[player] - 1
claimableWinnings[player] -= payout (set to 1 sentinel)
claimablePool -= uint128(payout)
ETH_sent = payout (via stETH + ETH transfer)
```

**Conservation:** `claimableWinnings[player]` decreases by `payout`. `claimablePool` decreases by `payout`. ETH transferred out = `payout`. CEI ordering ensures state is updated before external call (confirmed by Phase 214, 214-01: zero VULNERABLE findings in reentrancy/CEI audit).

**Verdict:** CONSERVED

---

### EF-13: GNRUS Redemption (GNRUS ETH Backing -> External Transfer)

**Entry:** `GNRUS.burn()` (GNRUS.sol L282-L329)

**Flow trace:**

1. **Proportional calculation** (L296-L301):
   ```solidity
   uint256 ethBal = address(this).balance;
   uint256 stethBal = steth.balanceOf(address(this));
   uint256 claimable = game.claimableWinningsOf(address(this));
   if (claimable > 1) { claimable -= 1; } else { claimable = 0; }
   uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;
   ```

2. **Claim from game if needed** (L304-L308):
   ```solidity
   if (owed > onHand) {
       game.claimWinnings(address(this));  // Triggers _claimWinningsInternal for GNRUS
   }
   ```

3. **Token burn** (L315-L316): `balanceOf[burner] -= amount; totalSupply -= amount;`

4. **Transfer** (L322-L328): stETH first, then ETH

**Symbolic:**
```
O_gnrus_redeem = owed = (total_backing * amount) / supply
GNRUS.balanceOf[burner] -= amount
GNRUS.totalSupply -= amount
ETH_out + stETH_out = owed
```

**Conservation:** `owed` is proportional to caller's GNRUS share of total supply. The backing (`ethBal + stethBal + claimable`) is the GNRUS contract's actual holdings. After burn, remaining holders' proportional share increases correspondingly. The `game.claimWinnings()` call is an EF-12 claim that moves ETH from Game's `claimablePool` to GNRUS contract balance.

**Verdict:** CONSERVED -- Proportional redemption. No ETH created; amount limited to actual backing.

---

### EF-15: Affiliate DGNRS Claim (DGNRS Token + BURNIE Flip Credit)

**Entry:** `Game.claimAffiliateDgnrs()` (Game.sol L1393-L1435)

**Flow trace:**

1. **DGNRS transfer** (L1413-L1418):
   ```solidity
   uint256 paid = dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Affiliate, player, reward);
   ```
   This is a DGNRS token transfer from the Affiliate pool, not ETH.

2. **Deity bonus flip credit** (L1422-L1431):
   ```solidity
   if (isDeityHolder && score != 0) {
       uint256 bonus = (score * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;
       // ...cap logic...
       coinflip.creditFlip(player, bonus);
   }
   ```
   `coinflip.creditFlip()` credits BURNIE flip balance. No ETH transferred.

**Symbolic:**
```
O_affiliate = DGNRS_transferred + BURNIE_flip_credit
```

**ETH impact:** None. DGNRS is a governance token transfer. `creditFlip` is a BURNIE credit. No ETH pool variables are modified. No `msg.value` sent.

**Verdict:** CONSERVED -- No ETH involved. Pure token operations.

---

### EF-18: burnAtGameOver (Token Burns, Not ETH Transfer)

**Entry:** `StakedDegenerusStonk.burnAtGameOver()` (StakedDegenerusStonk.sol L455-L464)

**Flow trace:**

```solidity
// L456-L463
uint256 bal = balanceOf[address(this)];
if (bal == 0) return;
balanceOf[address(this)] = 0;
totalSupply -= bal;
delete poolBalances;
```

**Key observation:** This burns remaining sDGNRS tokens held by the contract. No ETH is transferred. The `poolBalances` mapping is deleted (zeroing DGNRS pool allocations).

The sDGNRS contract's ETH/stETH backing (from Game's `claimableWinnings[SDGNRS]`) is NOT affected by this call. That backing is handled separately via Game's claim/sweep paths.

**ETH impact:** None. Token supply reduced; no ETH moved.

**Verdict:** CONSERVED -- No ETH involved. Pure token burn.

---

### EF-19: Year Sweep (sDGNRS Contract Balance -> GNRUS + VAULT)

**Entry:** `DegenerusStonk.yearSweep()` (DegenerusStonk.sol L304-L338)

**Flow trace:**

1. **Guards** (L305-L307):
   ```solidity
   if (!game.gameOver()) revert SweepNotReady();
   if (block.timestamp < uint256(goTime) + 365 days) revert SweepNotReady();
   ```

2. **Burn remaining DGNRS** (L309-L312):
   ```solidity
   uint256 remaining = stonk.balanceOf(address(this));
   if (remaining == 0) revert NothingToSweep();
   (uint256 ethOut, uint256 stethOut,) = stonk.burn(remaining);
   ```
   `stonk.burn()` calls `StakedDegenerusStonk.burn()` which returns proportional ETH + stETH.

3. **50/50 split** (L314-L318):
   ```solidity
   uint256 stethToGnrus = stethOut / 2;
   uint256 stethToVault = stethOut - stethToGnrus;
   uint256 ethToGnrus = ethOut / 2;
   uint256 ethToVault = ethOut - ethToGnrus;
   ```

4. **Transfer** (L321-L335): stETH first, then ETH to GNRUS and VAULT

**Symbolic:**
```
O_yearSweep = ethOut + stethOut = proportional_backing_of_remaining_DGNRS
GNRUS_receives = ethToGnrus + stethToGnrus
VAULT_receives = ethToVault + stethToVault
GNRUS + VAULT = ethOut + stethOut (by construction)
```

**Conservation:** The sDGNRS contract redeems its DGNRS for proportional backing. The resulting ETH + stETH is split 50/50 and transferred externally. `ethToGnrus + ethToVault = ethOut` and `stethToGnrus + stethToVault = stethOut` (by construction of the split).

**Verdict:** CONSERVED

---

## Section 4: Global Conservation Equation

### Master Equation

At any instant in time, the following invariant holds:

```
SUM(all ETH ever received by Game contract) = SUM(all ETH ever sent by Game contract) + H
```

Where **H** (held ETH) at any instant is:

```
H = currentPrizePool + nextPool + futurePool + claimablePool + resumeEthPool + yieldAccumulator + residual
```

And `residual = address(this).balance + steth.balanceOf(address(this)) - H_tracked` represents any untracked ETH (staking yield surplus, rounding dust from ticket price calculations, overpayment excess).

### Inflow Terms

| Symbol | Chain | Source | Equation |
|--------|-------|--------|----------|
| I_purchase | EF-01 | `Game.purchase()` msg.value | `futurePool += 10%, nextPool += 90%` (tickets); `futurePool += 90%, nextPool += 10%` (lootbox normal) |
| I_whale | EF-16 | `WhaleModule.purchase*()` msg.value | `futurePool += 70-95%, nextPool += 5-30%` |
| I_bet | EF-17 | `DegeneretteModule` msg.value | `futurePool += totalBet` |
| I_yield | EF-03 | stETH rebasing surplus | `claimableWinnings[VAULT/SDGNRS/GNRUS] += 23% each, yieldAccumulator += 23%` |

### Outflow Terms

| Symbol | Chain | Destination | Equation |
|--------|-------|-------------|----------|
| O_daily | EF-04 | Winners via `_addClaimableEth` | `currentPrizePool -= paidEth, claimablePool += liability` |
| O_solo | EF-05 | Solo winner + futurePool (whale pass) | `currentPrizePool -= perWinner` (via parent daily) |
| O_baf | EF-06 | BAF winners via `_addClaimableEth` | `futurePool -= claimed` (in consolidation) |
| O_decimator | EF-07 | Decimator winners via deferred claim | `futurePool -= decPoolWei` (in consolidation) |
| O_terminal | EF-08 | Terminal dec winners via deferred claim | `available -= decPool` (in gameover) |
| O_degen | EF-09 | Degenerette winners | `futurePool -= ethPortion` |
| O_drain | EF-10 | Gameover distribution | All pools zeroed; `available` distributed |
| O_sweep | EF-11 | Final 30-day sweep | All remaining balance sent externally |
| O_claim | EF-12 | Player ETH claim | `claimableWinnings -= payout, claimablePool -= payout, ETH sent` |
| O_gnrus | EF-13 | GNRUS proportional redemption | `GNRUS_backing -= owed, ETH/stETH sent` |
| O_yearSweep | EF-19 | sDGNRS -> GNRUS + VAULT | `DGNRS_backing redeemed, 50/50 sent` |

### Internal Transfer Terms (Zero-Sum)

| Chain | Transfer | Net Effect |
|-------|----------|------------|
| EF-02 | Pool consolidation | `next -> future`, `future -> current`, `next -> yieldAcc` etc. Zero-sum. |
| EF-14 | GNRUS charity | GNRUS token only. No ETH. |
| EF-15 | Affiliate claim | DGNRS + BURNIE only. No ETH. |
| EF-18 | burnAtGameOver | sDGNRS token only. No ETH. |
| EF-20 | BURNIE flip credit | BURNIE only. No ETH. |

### Proof of Balance

**1. Every I_x has a corresponding pool credit (Section 1):**
- I_purchase -> futurePool + nextPool (+ VAULT external for presale lootbox)
- I_whale -> futurePool + nextPool
- I_bet -> futurePool
- I_yield -> claimableWinnings + yieldAccumulator (funded by contract balance surplus)

All fresh ETH entering via `msg.value` is immediately credited to a tracked pool variable.

**2. Every O_x has a corresponding pool deduction (Section 3):**
- O_daily/O_solo/O_baf/O_decimator/O_degen -> specific pool deducted, claimablePool increased
- O_drain -> all pools zeroed, available distributed
- O_sweep -> all remaining balance sent
- O_claim -> claimableWinnings deducted, claimablePool deducted, ETH sent
- O_gnrus -> proportional to GNRUS backing
- O_yearSweep -> proportional to DGNRS backing

All ETH leaving the contract has a prior deduction from a tracked pool or the global available balance.

**3. Internal flows (Section 2) are zero-sum:**
- EF-02 consolidation: proved algebraically that `S = memFuture + memCurrent + memNext + memYieldAcc + claimableDelta` is invariant
- EF-03 yield: funded by surplus, not by pool deductions
- EF-14/15/18/20: no ETH involvement

**4. H captures all remaining ETH:**
At any point, `H = currentPrizePool + nextPool + futurePool + claimablePool + resumeEthPool + yieldAccumulator + residual`. The `residual` term covers:
- Overpayment dust (ETH sent in excess of `costWei` in DirectEth mode)
- stETH rebasing yield (positive or negative)
- Rounding dust from BPS calculations

The `residual` is always non-negative in practice (stETH yields positive, overpayments are positive, rounding truncates down). The `distributeYieldSurplus()` function periodically converts positive residual into tracked `claimableWinnings` and `yieldAccumulator`.

### Global Equation

```
SUM(I_x) = SUM(O_x) + H

where:
  SUM(I_x) = I_purchase + I_whale + I_bet + I_yield
  SUM(O_x) = O_daily + O_solo + O_baf + O_decimator + O_terminal + O_degen
            + O_drain + O_sweep + O_claim + O_gnrus + O_yearSweep
  H = currentPrizePool + nextPool + futurePool + claimablePool
    + resumeEthPool + yieldAccumulator + residual
```

Every term is accounted exactly once. No double-counting: each inflow credits a specific pool, each outflow debits a specific pool, internal flows are zero-sum transfers. The `claimablePool` variable acts as the bridge between pool-level accounting and per-recipient `claimableWinnings` entries.

---

## Section 5: Conservation Verdict

### Per-Chain Verdict Table

| Chain ID | Direction | Pool Deducted | Pool Credited / Recipient | Symbolic Equation | Verdict |
|----------|-----------|---------------|---------------------------|-------------------|---------|
| EF-01 | In | (none -- inflow) | futurePool, nextPool, VAULT | `I_purchase = futurePool_delta + nextPool_delta + vaultShare` | CONSERVED |
| EF-02 | Internal | multiple (zero-sum) | multiple (zero-sum) | `S_before = S_after` | CONSERVED |
| EF-03 | Internal->Out | (surplus balance) | claimableWinnings, yieldAccumulator | `distributed + yieldAcc_delta <= yieldPool` | CONSERVED |
| EF-04 | Out | currentPrizePool | claimableWinnings[winners] | `currentPrizePool -= paidEth = SUM(per_winner)` | CONSERVED |
| EF-05 | Out | currentPrizePool (via parent) | claimableWinnings[solo] + futurePool (whale pass) | `perWinner = ethAmount + whalePassCost` | CONSERVED |
| EF-06 | Out | futurePool (in consolidation) | claimableWinnings[BAF winners] | `memFuture -= claimed = SUM(winner_credits)` | CONSERVED |
| EF-07 | Out | futurePool (in consolidation) | claimableWinnings[dec winners] (deferred) | `memFuture -= decPoolWei; claims <= decPoolWei` | CONSERVED |
| EF-08 | Out | available (gameover) | claimableWinnings[terminal dec winners] | `claimablePool += decSpend; claims <= decSpend` | CONSERVED |
| EF-09 | Out | futurePool | claimableWinnings[player] | `futurePool -= ethPortion = claimablePool_increase` | CONSERVED |
| EF-10 | Out | all pools (zeroed) | claimableWinnings + VAULT | `available = deity_refunds + decSpend + termPaid + vault_rem` | CONSERVED |
| EF-11 | Out | all remaining | sDGNRS, VAULT, GNRUS (external) | `O_sweep = 33% + 33% + 34% = totalFunds` | CONSERVED |
| EF-12 | Out | claimableWinnings, claimablePool | player (ETH transfer) | `payout = claimableWinnings[p] - 1 = ETH_sent` | CONSERVED |
| EF-13 | Out | GNRUS backing | burner (ETH+stETH transfer) | `owed = (backing * amount) / supply` | CONSERVED |
| EF-14 | Internal | (none) | (GNRUS token only) | No ETH flow | CONSERVED |
| EF-15 | Out | (none -- tokens only) | (DGNRS + BURNIE credit) | No ETH flow | CONSERVED |
| EF-16 | In | (none -- inflow) | futurePool, nextPool | `I_whale = futurePool_delta + nextPool_delta` | CONSERVED |
| EF-17 | In | (none -- inflow) | futurePool | `I_bet = futurePool_delta` | CONSERVED |
| EF-18 | Out | (none -- tokens only) | (sDGNRS token burn) | No ETH flow | CONSERVED |
| EF-19 | Out | DGNRS backing | GNRUS + VAULT (50/50) | `O_yearSweep = ethOut + stethOut` | CONSERVED |
| EF-20 | Internal | (none) | (BURNIE credit only) | No ETH flow | CONSERVED |

### Global Verdict

**CONSERVED** -- The consolidated pool architecture (v20.0 + v21.0 two-call split) preserves ETH conservation across all 20 identified ETH-flow chains. Specifically:

1. **All inflows are fully allocated:** Every `msg.value` entering via purchase, whale pass, or degenerette bet is immediately split and credited to tracked pool variables (futurePool, nextPool) with exact arithmetic.

2. **All outflows are fully deducted:** Every ETH leaving the contract (player claims, gameover drain, final sweep, GNRUS redemption, year sweep) has a corresponding deduction from a tracked pool variable or from the total available balance.

3. **Internal flows are zero-sum:** Pool consolidation (`_consolidatePoolsAndRewardJackpots`) is proven algebraically invariant across all 8 arithmetic steps. The two-call split via `resumeEthPool` is a transient memo that returns to zero after completion.

4. **The `claimablePool` bridge is maintained:** `claimablePool` is incremented when ETH is credited to `claimableWinnings[recipient]` and decremented when ETH is claimed. The invariant `claimablePool >= SUM(claimableWinnings[*])` is maintained (with temporary deviation during decimator settlement, documented at DegenerusGameStorage L344-L345).

5. **No uint128 truncation leaks:** Phase 214 (214-02) proved all type narrowings safe -- maximum ETH values are far below uint128 max (~3.4e38 wei vs total ETH supply ~1.2e26 wei).

### Supporting Evidence from Phase 214

Per D-02, the following Phase 214 findings provide independent verification:

- **214-01 (Reentrancy/CEI):** Zero VULNERABLE findings. All external calls follow CEI ordering. Confirms EF-12 claim path safety.
- **214-02 (Overflow/Access Control):** All 271 verdicts SAFE. uint128 narrowing for pool variables proven safe. Confirms no truncation leaks in pool writes.
- **214-03 (State Composition):** Pool consolidation memory-batch verified SAFE. Two-call split interaction verified SAFE. Packed pool fields verified SAFE. Zero state corruption in prizePoolsPacked.
- **214-05 (Attack Chains):** Zero VULNERABLE attack chains across 23 multi-step scenarios including pool manipulation paths.

### INFO Findings

**INFO-216-01: Overpayment Dust in DirectEth Mode**
When `payKind == MintPaymentKind.DirectEth`, `msg.value >= costWei` is allowed (Game.sol L911). Excess ETH (`msg.value - costWei`) stays in the Game contract balance as untracked surplus. This surplus is eventually captured by `distributeYieldSurplus()` and distributed to protocol recipients. Not a vulnerability -- the overpayment is retained by the protocol, not lost.

**INFO-216-02: Rounding Dust in BPS Calculations**
All BPS calculations use integer division, which truncates. For example, `(totalPrice * 3000) / 10_000` truncates the remainder. This dust accumulates in the contract balance as untracked surplus, captured by `distributeYieldSurplus()`. Amounts are negligible (sub-wei per transaction).

**INFO-216-03: claimablePool Temporary Inequality During Decimator Settlement**
As documented at DegenerusGameStorage L344-L345: "During decimator settlement, the full pool is reserved in claimablePool before individual claims are credited, temporarily breaking equality." The inequality is always `claimablePool >= SUM(claimableWinnings[*])` (over-reserved, not under-reserved), which is the safe direction for solvency.
