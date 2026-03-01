# EndgameModule Audit Findings (03a-03)

**Audited:** 2026-03-01
**Module:** `contracts/modules/DegenerusGameEndgameModule.sol` (517 lines)
**Supporting:** `contracts/modules/DegenerusGamePayoutUtils.sol` (94 lines), `contracts/DegenerusGame.sol` (runDecimatorJackpot dispatch, claimWhalePass entry), `contracts/storage/DegenerusGameStorage.sol`

---

## Task 1: Level Transition Guards and BAF/Decimator Pool Accounting

### 1.1 Level-to-Action Mapping Table

Source: `runRewardJackpots()` (line 132-204)

Guards:
- BAF: `prevMod10 == 0` (line 143) -- fires at levels divisible by 10
- Decimator (level 100 special): `prevMod100 == 0` (line 169) -- fires at every 100th level
- Decimator (normal): `prevMod10 == 5 && prevMod100 != 95` (line 184) -- fires at x5 levels except x95

| Level | BAF? | BAF % | Decimator? | Dec % | Source Pool | Notes |
|-------|------|-------|------------|-------|-------------|-------|
| 1-4   | No   | -     | No         | -     | -           | No jackpots |
| 5     | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 6-9   | No   | -     | No         | -     | -           | |
| 10    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 11-14 | No   | -     | No         | -     | -           | |
| 15    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 16-19 | No   | -     | No         | -     | -           | |
| 20    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 25    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 30    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 35    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 40    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 45    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 50    | Yes  | 25%   | No         | -     | baseFuturePool | Level 50 bonus BAF |
| 55    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 60    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 65    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 70    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 75    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 80    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 85    | No   | -     | Yes        | 10%   | futurePoolLocal | Normal decimator |
| 90    | Yes  | 10%   | No         | -     | baseFuturePool | Normal BAF |
| 91-94 | No   | -     | No         | -     | -           | |
| 95    | No   | -     | No         | -     | -           | Decimator explicitly excluded |
| 96-99 | No   | -     | No         | -     | -           | |
| 100   | Yes  | 20%   | Yes        | 30%   | baseFuturePool (both) | BOTH fire at milestone |

**Pattern repeats every 100 levels** with the following exceptions:
- Level 50 gets 25% BAF (line 144: `lvl == 50`). Levels 150, 250, etc. get only 10% BAF because the condition checks `lvl == 50` exactly, not `prevMod100 == 50`.
- Every 100th level (100, 200, 300...) gets both BAF 20% + Decimator 30% via the `prevMod100 == 0` condition.

**Verdict: Level 50 BAF bonus is one-time only**

The 25% BAF percentage applies exclusively to level 50. At level 150, 250, etc., the condition `lvl == 50` is false, so the 10% default applies. This appears intentional (level 50 is a first-cycle milestone) but is worth noting as design intent vs. potential oversight.

**Severity:** INFORMATIONAL
**Classification:** Design observation -- level 50 is the only non-100-milestone to receive enhanced BAF percentage. If the intent was every 50th level, the condition should be `prevMod100 == 50 || prevMod100 == 0`.

### 1.2 BAF/Decimator Mutual Exclusion

For non-milestone levels (1-99), BAF and Decimator are mutually exclusive:
- BAF fires at `prevMod10 == 0`: levels 10, 20, 30, 40, 50, 60, 70, 80, 90
- Decimator fires at `prevMod10 == 5 && prevMod100 != 95`: levels 5, 15, 25, 35, 45, 55, 65, 75, 85
- No level has both `prevMod10 == 0` and `prevMod10 == 5` simultaneously

At level 100 (`prevMod100 == 0`), BOTH fire:
- BAF via `prevMod10 == 0` block (line 143), bafPct = 20%
- Decimator via `prevMod100 == 0` block (line 169), decPoolWei = 30% of baseFuturePool
- The normal Decimator block (line 184) does NOT fire because `prevMod10 = 0, not 5`

Total draw at level 100: up to 50% of baseFuturePool (20% BAF + 30% Decimator). This is safe because `futurePoolLocal` starts at `baseFuturePool` and decreases by at most 50%.

**Verdict: PASS** -- mutual exclusion holds for non-milestone levels; dual-fire at level 100 is intentional and arithmetically safe.

### 1.3 BAF Jackpot Pool Draw Correctness

Source: `_runBafJackpot()` (line 305-383)

**Percentage selection (line 144):**
```solidity
uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 25 : 10);
```
- Level 100, 200, ...: `prevMod100 == 0` -> 20%. Correct.
- Level 50: `prevMod100 == 50, lvl == 50` -> 25%. Correct.
- All others (10, 20, 30, 40, 60, 70, 80, 90): 10%. Correct.

**Pool draw and deduction (lines 145-162):**
```solidity
uint256 bafPoolWei = (baseFuturePool * bafPct) / 100;
futurePoolLocal -= bafPoolWei;  // Full deduction BEFORE distribution
```
The full pool draw is deducted from `futurePoolLocal` BEFORE calling `_runBafJackpot`. This is correct CEI ordering.

**Refund path (lines 156-162):**
```solidity
if (netSpend != bafPoolWei) {
    futurePoolLocal += (bafPoolWei - netSpend);  // Refund unspent
}
if (lootboxToFuture != 0) {
    futurePoolLocal += lootboxToFuture;  // Recycle lootbox ETH
}
```

**Inside `_runBafJackpot` (line 305-383):**
- `jackpots.runBafJackpot(poolWei, lvl, rngWord)` returns winners, amounts, and `refund` (undistributed pool)
- `netSpend = poolWei - refund` (line 381) -- correct calculation
- `lootboxToFuture = lootboxTotal` (line 379) -- lootbox portions stay in future pool
- Winners loop processes each winner, splitting large winners 50/50 ETH/lootbox, alternating small winners

**Wei conservation analysis:**
- poolWei enters the function
- Winners receive: ETH (via `_addClaimableEth`) or lootbox tickets (via `_awardJackpotTickets` or `_queueWhalePassClaimCore`)
- `refund` = amount returned by jackpots contract as undistributed
- `netSpend = poolWei - refund` = total distributed to winners
- `lootboxToFuture` = ETH routed to lootbox (stays in future pool since it was already in future pool)

Net effect on `futurePoolLocal`:
```
futurePoolLocal -= bafPoolWei                    // Deduct full draw
futurePoolLocal += (bafPoolWei - netSpend)        // Refund unspent
futurePoolLocal += lootboxToFuture                // Recycle lootbox
= baseFuturePool - netSpend + lootboxToFuture
```

ETH that goes to claimable: `netSpend - lootboxToFuture` (the non-lootbox portion of netSpend)
ETH that stays in future pool: `baseFuturePool - netSpend + lootboxToFuture`

This correctly accounts for all ETH. No wei leak.

**Verdict: PASS** -- BAF pool draw percentages correct, deduction-before-distribution follows CEI, refund path preserves all unspent wei.

### 1.4 Decimator Delegation via Self-Call

Source: `runRewardJackpots()` lines 169-195, `DegenerusGame.runDecimatorJackpot()` line 1256

**Self-call mechanism (EndgameModule line 172-173):**
```solidity
uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
```

Since EndgameModule executes via `delegatecall` from DegenerusGame, `address(this)` is the DegenerusGame address. The call `IDegenerusGame(address(this)).runDecimatorJackpot(...)` is a regular CALL to DegenerusGame, not a delegatecall.

**DegenerusGame.runDecimatorJackpot (line 1256-1275):**
```solidity
function runDecimatorJackpot(...) external returns (uint256 returnAmountWei) {
    if (msg.sender != address(this)) revert E();  // Self-call guard
    (bool ok, bytes memory data) = ContractAddresses.GAME_DECIMATOR_MODULE.delegatecall(...);
    if (!ok) _revertDelegate(data);
    if (data.length == 0) revert E();
    return abi.decode(data, (uint256));
}
```

This is indeed a CALL (not delegatecall). DegenerusGame receives the CALL, verifies `msg.sender == address(this)`, then does a delegatecall to the Decimator module. The Decimator module executes in DegenerusGame's storage context.

**Return value accounting (level 100, line 170-177):**
```solidity
uint256 decPoolWei = (baseFuturePool * 30) / 100;
if (decPoolWei != 0) {
    uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
    uint256 spend = decPoolWei - returnWei;
    futurePoolLocal -= spend;
    claimableDelta += spend;
}
```

Net effect: `futurePoolLocal -= (decPoolWei - returnWei)`. Only the amount actually spent (not returned) is deducted. Correct.

**Return value accounting (normal decimator, line 186-194):**
```solidity
uint256 decPoolWei = (futurePoolLocal * 10) / 100;
if (decPoolWei != 0) {
    uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
    uint256 spend = decPoolWei - returnWei;
    futurePoolLocal -= spend;
    claimableDelta += spend;
}
```

Same pattern. Note: normal decimator uses `futurePoolLocal` (not `baseFuturePool`) as the source. Since normal Decimator levels (x5) never overlap with BAF levels (x0), `futurePoolLocal == baseFuturePool` at this point, so the difference is moot for non-level-100 cases.

**Reentrancy analysis of the self-call:**

The self-call goes through DegenerusGame.runDecimatorJackpot, which does a delegatecall to the Decimator module. Could this re-enter:
1. `purchase()`: No direct guard, but the MintModule does not check `jackpotPhaseFlag` for rejection. However, `purchase()` is an `external` function and the Decimator module's delegatecall does not call `purchase`. The self-call only dispatches to `GAME_DECIMATOR_MODULE.delegatecall(runDecimatorJackpot.selector, ...)` -- it cannot re-enter purchase.
2. `advanceGame()`: The AdvanceModule checks `day == dailyIdx` (line 140) and requires VRF word via `rngGate()`. Re-entry would fail because the daily gate prevents same-block re-entry.
3. `claimWhalePass()`: This is externally callable but the Decimator module has no reason to call it. The delegatecall dispatches only to `runDecimatorJackpot.selector`.

The `msg.sender != address(this)` guard at line 1261 ensures only self-calls can invoke `runDecimatorJackpot`. The Decimator module's delegatecall operates in game storage context and can modify storage, but it does NOT make external calls that could trigger callbacks into EndgameModule.

**Verdict: PASS** -- Self-call is correctly a CALL (not delegatecall). Return value accounting is correct. Reentrancy is not possible because the self-call dispatches to a specific module selector with no external callbacks.

### 1.5 rewardTopAffiliate Audit

Source: `rewardTopAffiliate()` (line 100-113)

```solidity
function rewardTopAffiliate(uint24 lvl) external {
    (address top, ) = affiliate.affiliateTop(lvl);
    if (top == address(0)) return;                              // Zero-address guard

    uint256 poolBalance = dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate);
    uint256 dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) / 10_000;  // 100/10000 = 1%
    uint256 paid = dgnrs.transferFromPool(IDegenerusStonk.Pool.Affiliate, top, dgnrsReward);
    emit AffiliateDgnrsReward(top, lvl, paid);
}
```

**Checks:**
1. Zero-address guard: `top == address(0)` returns early. **PASS.**
2. BPS calculation: `AFFILIATE_POOL_REWARD_BPS = 100` (line 90). `100 / 10_000 = 1%`. **PASS.**
3. Pool deduction: `dgnrs.transferFromPool()` handles the actual transfer and pool deduction atomically. The reward is calculated as 1% of the CURRENT pool balance, not a stale cached value. **PASS.**
4. The `paid` return value (actual transferred amount) is emitted, not the calculated `dgnrsReward`. This correctly handles cases where the pool has insufficient balance. **PASS.**

**Observation:** No per-level guard prevents `rewardTopAffiliate` from being called multiple times for the same level. However, the caller (AdvanceModule line 270) calls it only once during the level-end sequence (`_rewardTopAffiliate(lvl)` inside `jackpotCounter >= JACKPOT_LEVEL_CAP` block), and this block only executes once per level transition. If called externally via delegatecall somehow, the `affiliateTop` query is idempotent (returns same address) and the DGNRS pool would just be drawn down further. This is mitigated by the fact that only the AdvanceModule's delegatecall path reaches this function.

**Verdict: PASS** -- Zero-address guard present, 1% calculation correct, actual transfer amount emitted.

---

## Task 2: claimWhalePass CEI, Loop Bounds, _addClaimableEth Comparison, Unchecked Blocks

### 2.1 claimWhalePass CEI Pattern

Source: `claimWhalePass()` (line 493-511)

```solidity
function claimWhalePass(address player) external {
    uint256 halfPasses = whalePassClaims[player];       // CHECK: read state
    if (halfPasses == 0) return;                         // CHECK: early return

    whalePassClaims[player] = 0;                         // EFFECT: clear state BEFORE interactions

    uint24 startLevel = level + 1;                       // EFFECT: compute parameters
    _applyWhalePassStats(player, startLevel);             // EFFECT: update mint stats
    emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel);  // EFFECT: emit event
    _queueTicketRange(player, startLevel, 100, uint32(halfPasses));     // EFFECT: queue tickets
}
```

**CEI Analysis:**
1. **Check:** `whalePassClaims[player]` read and `halfPasses == 0` guard. **Correct.**
2. **Effect:** `whalePassClaims[player] = 0` clears state BEFORE any downstream operations. **Correct CEI.**
3. **Interaction:** `_applyWhalePassStats` and `_queueTicketRange` are internal functions that modify storage only -- no external calls. There is no ETH transfer or external contract callback in this path.

**Reentrancy analysis:** None of the functions called after the state clear (`_applyWhalePassStats`, `_queueTicketRange`) make external calls. They only write to storage (`mintPacked_`, `ticketsOwedPacked`, `ticketQueue`). There is no callback vector.

**Entry point context (DegenerusGame line 1777-1792):**
```solidity
function claimWhalePass(address player) external {
    player = _resolvePlayer(player);
    _claimWhalePassFor(player);
}
function _claimWhalePassFor(address player) private {
    (...).delegatecall(IDegenerusGameEndgameModule.claimWhalePass.selector, player);
}
```

The `_resolvePlayer` converts `address(0)` to `msg.sender`. The delegatecall to EndgameModule operates in DegenerusGame storage context. The `player` parameter is the resolved address, not an arbitrary caller-controlled external contract.

**halfPasses cast safety:** `uint32(halfPasses)` -- halfPasses is a uint256 from `whalePassClaims[player]`. The whale pass claim amount comes from `_queueWhalePassClaimCore` (PayoutUtils line 80): `fullHalfPasses = amount / HALF_WHALE_PASS_PRICE` where `HALF_WHALE_PASS_PRICE = 2.175 ether`. To overflow uint32 (4.29 billion), a player would need `4.29e9 * 2.175 ETH = 9.33 billion ETH`. This exceeds total ETH supply by orders of magnitude.

**startLevel = level + 1:** This avoids giving tickets for the current active level. At level 0, tickets start at level 1. At level 99, tickets start at level 100. The +1 offset is correct for preventing players from gaining tickets on a level where ticket processing may have already occurred.

**Verdict: PASS** -- CEI pattern correctly implemented. State cleared before effects. No external calls in the effect chain. Cast to uint32 is safe given ETH supply limits.

### 2.2 EndgameModule Loop Bound Inventory (DOS-01)

**Claim:** Research notes state "EndgameModule has NO for/while loops in its own code."

**Verification:** Grep for all `for` and `while` keywords in EndgameModule (517 lines):

Only one loop found at line 336:
```solidity
for (uint256 i; i < winnersLen; ) {
    // ... process winners ...
    unchecked { ++i; }
}
```

This loop is in `_runBafJackpot()`. Research claim is INCORRECT -- there IS one for-loop in EndgameModule.

**Loop bound analysis:**

`winnersLen = winnersArr.length` where `winnersArr` comes from `jackpots.runBafJackpot(poolWei, lvl, rngWord)` (line 319-323).

In `DegenerusJackpots.runBafJackpot()` (line 221-234):
```solidity
address[] memory tmpW = new address[](106);  // Fixed-size array, max 106 entries
```

The function populates `tmpW` up to index `n` (tracked counter), then returns a trimmed copy. The maximum `n` is 106 (array capacity). The actual winner count is bounded by:
- 1 top BAF bettor
- 1 top coinflip bettor
- 1 random pick (3rd or 4th BAF)
- 3 affiliate achievers (4 slots, but merged into 3 effective)
- Up to 50+50 scatter bucket winners
= Max 106 entries

**Verdict:** The loop iterates at most 106 times. Each iteration performs storage reads/writes (claimable credits, ticket queuing) but no external calls that could amplify gas. 106 iterations with storage operations is well within block gas limits.

**Downstream loops called from EndgameModule:**

1. `_queueTicketRange(player, startLevel, 100, ...)` in `claimWhalePass`: Loop of exactly 100 iterations (fixed constant, line 586: `for (uint24 i = 0; i < numLevels; )`). Each iteration does 1 SLOAD + 1 SSTORE + potentially 1 array push. At ~20k gas per iteration (cold SSTORE), this costs roughly 2M gas for 100 iterations -- well within limits.

2. `_awardJackpotTickets` / `_jackpotTicketRoll`: No loops. These call `_queueLootboxTickets` which is a single storage write.

3. `_queueWhalePassClaimCore`: No loops. Single storage increment.

**DOS-01 Verdict for EndgameModule:**

| Location | Loop Type | Max Iterations | Bounded By | Gas Estimate |
|----------|-----------|----------------|------------|--------------|
| `_runBafJackpot` (line 336) | for | 106 | `DegenerusJackpots.runBafJackpot` fixed-size array (106) | ~3M gas (storage writes per winner) |
| `_queueTicketRange` via `claimWhalePass` (Storage line 586) | for | 100 | Fixed constant passed from `claimWhalePass` | ~2M gas |

All loops in EndgameModule are bounded by fixed constants or fixed-size arrays from external contracts. No unbounded iteration exists.

**DOS-01: PASS** -- EndgameModule has no unbounded loops. All iteration is bounded by fixed constants (100 for ticket range) or fixed-size arrays (106 for BAF winners).

### 2.3 _addClaimableEth Dual Implementation Comparison

**EndgameModule version** (line 217-266): Inline implementation with direct pool writes.
**JackpotModule version** (line 911-978): Delegates to `_processAutoRebuy` helper.

**Shared elements (identical in both):**
- Same bonus BPS: `13_000` and `14_500` for normal and afKing modes
- Same `_calcAutoRebuy` call from PayoutUtils (same parameters)
- Same `_creditClaimable` call for non-auto-rebuy path
- Same pool routing: `futurePrizePool += calc.ethSpent` vs `nextPrizePool += calc.ethSpent` based on `calc.toFuture`
- Same zero-check: `weiAmount == 0 return 0`

**Differences:**

| Aspect | EndgameModule | JackpotModule |
|--------|---------------|---------------|
| `claimablePool` management | Increments `claimablePool += calc.reserved` internally (line 251), returns 0 | Does NOT increment `claimablePool` internally, returns `calc.reserved` for caller to handle |
| Return value (auto-rebuy with tickets) | Returns `0` | Returns `calc.reserved` |
| Caller responsibility | Caller adds returned `claimableDelta` to `claimablePool` (line 201-203). Since return is 0, no double-count. | Caller adds returned `claimableDelta` to `claimablePool` via `liabilityDelta` accumulator. Returns `calc.reserved`, caller adds to pool. |
| Pool routing order | Pool increment before `_queueTickets` | `_queueTickets` before pool increment |
| Event | `AutoRebuyExecuted` | `AutoRebuyProcessed` (different event name) |

**Critical correctness analysis:**

EndgameModule: When auto-rebuy fires with tickets, `_addClaimableEth` does:
1. Routes `calc.ethSpent` to future/next pool
2. Queues tickets
3. Credits `calc.reserved` to claimable and increments `claimablePool`
4. Returns 0

Caller (`_runBafJackpot`): `claimableDelta += _addClaimableEth(...)` adds 0. Then `runRewardJackpots` does `claimablePool += claimableDelta`. Since the internal increment already happened, there is no double-counting. **Correct.**

JackpotModule: When auto-rebuy fires with tickets, `_processAutoRebuy` does:
1. Queues tickets
2. Routes `calc.ethSpent` to future/next pool
3. Credits `calc.reserved` to claimable (but does NOT increment `claimablePool`)
4. Returns `calc.reserved`

Caller: `claimableDelta = _addClaimableEth(...)` gets `calc.reserved`. Accumulates into `liabilityDelta`. Eventually `claimablePool += liabilityDelta`. **Correct.**

**Observation:** The two implementations achieve the same net effect through different internal patterns. The EndgameModule version handles `claimablePool` internally; the JackpotModule version delegates it to the caller. Both are correct but the divergence creates maintenance risk -- a change to one without the other could introduce an accounting bug.

**Severity:** INFORMATIONAL
**Classification:** Code duplication with divergent patterns. Both implementations are currently correct. The maintenance risk is that future modifications to one version without updating the other could break `claimablePool` invariants.

### 2.4 Unchecked Block Analysis

Source: Single unchecked block at line 373-375:

```solidity
unchecked {
    ++i;
}
```

This is the loop counter increment for the BAF winners loop (`for (uint256 i; i < winnersLen; )`).

**Overflow analysis:** `i` is `uint256`, starting at 0, incremented by 1 each iteration. The loop terminates when `i >= winnersLen` where `winnersLen <= 106` (from the fixed-size array). `uint256` cannot overflow from incrementing a counter that reaches at most 106. The `unchecked` block is a gas optimization that saves ~20 gas per iteration.

**Verdict: PASS** -- Unchecked increment of a bounded loop counter. Overflow is impossible.

---

## Findings Summary

| # | Severity | Category | Description | Location | Verdict |
|---|----------|----------|-------------|----------|---------|
| F01 | INFORMATIONAL | Design | Level 50 BAF 25% bonus is one-time only (not every 50 levels) | line 144: `lvl == 50` | By design (document) |
| F02 | INFORMATIONAL | Maintenance | `_addClaimableEth` dual implementation diverges in `claimablePool` management pattern | EndgameModule:217, JackpotModule:911 | Both correct, maintenance risk |
| - | PASS | Security | BAF/Decimator mutual exclusion (non-milestone levels) | line 143, 169, 184 | Correct |
| - | PASS | Accounting | BAF pool draw percentages (10/25/20%) | line 144-145 | Correct |
| - | PASS | Accounting | BAF refund path preserves all unspent wei | line 156-162 | Correct |
| - | PASS | Accounting | Decimator self-call return value accounting | line 170-177, 186-194 | Correct |
| - | PASS | Security | Self-call reentrancy not possible | line 172-173, Game:1261 | Correct |
| - | PASS | Security | claimWhalePass CEI pattern | line 493-511 | Correct |
| - | PASS | Security | rewardTopAffiliate zero-address guard and 1% calculation | line 100-113 | Correct |
| - | PASS | DOS-01 | EndgameModule loop bounds (max 106 BAF winners, 100 ticket range) | line 336, Storage:586 | Bounded |
| - | PASS | Safety | Unchecked loop counter increment | line 373-375 | Safe |

**DOS-01 Final Verdict: PASS** -- All loops in EndgameModule are bounded by fixed constants or fixed-size arrays. No denial-of-service via gas exhaustion is possible through EndgameModule code paths.

---

## Level 100 Combined Draw Analysis

At level 100, both BAF and Decimator fire. Total maximum draw from `futurePrizePool`:
- BAF: 20% of `baseFuturePool`
- Decimator: 30% of `baseFuturePool`
- Total: 50% of `baseFuturePool`

Both use `baseFuturePool` (the snapshot taken at function entry, line 134). The BAF draw is processed first, modifying `futurePoolLocal`. The Decimator draw at line 170 uses `baseFuturePool` (not `futurePoolLocal`), so BAF refunds/lootbox recycling do not affect the Decimator pool size.

After both complete:
```
futurePoolLocal = baseFuturePool
  - bafNetSpend + bafLootboxToFuture     // BAF effect
  - decimatorSpend                        // Decimator effect
```

Maximum deduction: 50% of baseFuturePool (when both fully spend their allocations with no refunds and no lootbox recycling). The remaining 50%+ is preserved. This is arithmetically safe and cannot underflow.
