# Novel Attack Surface: Invariant Analysis & Privilege Escalation Audit

**Audit Date:** 2026-03-17
**Auditor:** Claude (AI-assisted security analysis, Claude Opus 4.6)
**Scope:** StakedDegenerusStonk.sol (sDGNRS), DegenerusStonk.sol (DGNRS), DegenerusGame.sol, ContractAddresses.sol
**Methodology:** Formal invariant proofs with exhaustive path enumeration; complete privilege map with escalation vector analysis
**Prior Work:** v2.0-delta-core-contracts.md (Phase 19 proofs), 20-03 edge case tests, 21-RESEARCH.md attack taxonomy

---

## NOVEL-05: Invariant Analysis

This section formally states and proves four critical invariants that underpin the security of the sDGNRS/DGNRS dual-token system. Each invariant is proven by exhaustive enumeration of every code path that could modify the relevant state variables, with line-number citations to the source contracts.

### Invariant 1: sDGNRS Supply Conservation

**Formal Statement:**

```
For all states S reachable from the constructor:
  sDGNRS.totalSupply == SUM(sDGNRS.balanceOf[addr]) for all addr in ADDRESS_SPACE
```

**Proof by exhaustive path enumeration:**

Every function in StakedDegenerusStonk.sol that modifies `totalSupply` or any `balanceOf` entry is enumerated below. The invariant holds if every such function preserves the sum equality.

**Path 1: `_mint(to, amount)` -- StakedDegenerusStonk.sol:510-517**

```solidity
function _mint(address to, uint256 amount) private {
    if (to == address(0)) revert ZeroAddress();       // line 511
    unchecked {
        totalSupply += amount;                         // line 513
        balanceOf[to] += amount;                       // line 514
    }
    emit Transfer(address(0), to, amount);             // line 516
}
```

- `totalSupply` increases by `amount`.
- `balanceOf[to]` increases by `amount`.
- Net effect on `SUM(balanceOf) - totalSupply`: `+amount - amount = 0`.
- **Sum preserved.**

Note: `_mint` is `private` and called only in the constructor (StakedDegenerusStonk.sol:212-213), with two calls: `_mint(DGNRS, creatorAmount)` and `_mint(address(this), poolTotal)`. No post-construction minting is possible.

**Path 2: `burn(amount)` -- StakedDegenerusStonk.sol:379-441**

```solidity
uint256 bal = balanceOf[player];                       // line 383
if (amount == 0 || amount > bal) revert Insufficient(); // line 384
unchecked {
    balanceOf[player] = bal - amount;                  // line 399
    totalSupply -= amount;                             // line 400
}
```

- `balanceOf[player]` decreases by `amount`.
- `totalSupply` decreases by `amount`.
- Net effect on `SUM(balanceOf) - totalSupply`: `-amount - (-amount) = 0`.
- **Sum preserved.**

**Path 3: `burnRemainingPools()` -- StakedDegenerusStonk.sol:359-367**

```solidity
uint256 bal = balanceOf[address(this)];                // line 360
if (bal == 0) return;                                  // line 361
unchecked {
    balanceOf[address(this)] = 0;                      // line 363
    totalSupply -= bal;                                // line 364
}
```

- `balanceOf[address(this)]` decreases by `bal` (set to 0).
- `totalSupply` decreases by `bal`.
- Net effect: `-bal - (-bal) = 0`.
- **Sum preserved.**

**Path 4: `wrapperTransferTo(to, amount)` -- StakedDegenerusStonk.sol:242-252**

```solidity
uint256 bal = balanceOf[ContractAddresses.DGNRS];      // line 245
if (amount > bal) revert Insufficient();               // line 246
unchecked {
    balanceOf[ContractAddresses.DGNRS] = bal - amount; // line 248
    balanceOf[to] += amount;                           // line 249
}
```

- `balanceOf[DGNRS]` decreases by `amount`.
- `balanceOf[to]` increases by `amount`.
- `totalSupply` unchanged.
- Net effect on SUM: `-amount + amount = 0`.
- **Sum preserved.**

**Path 5: `transferFromPool(pool, to, amount)` -- StakedDegenerusStonk.sol:315-332**

```solidity
unchecked {
    poolBalances[idx] = available - amount;             // line 325
    balanceOf[address(this)] -= amount;                // line 326
    balanceOf[to] += amount;                           // line 327
}
```

- `balanceOf[address(this)]` decreases by `amount`.
- `balanceOf[to]` increases by `amount`.
- `totalSupply` unchanged.
- Net effect on SUM: `-amount + amount = 0`.
- **Sum preserved.**

Note: `poolBalances` is a separate internal accounting array that does not affect the ERC20 supply invariant. Its consistency is covered by Invariant 4.

**Path 6: `transferBetweenPools(from, to, amount)` -- StakedDegenerusStonk.sol:340-355**

```solidity
unchecked {
    poolBalances[fromIdx] = available - amount;        // line 350
}
poolBalances[toIdx] += amount;                         // line 352
```

- Only `poolBalances` entries are modified.
- No `balanceOf` or `totalSupply` changes.
- **Sum trivially preserved (no relevant state change).**

**Completeness check:** Are there any other functions that could modify `totalSupply` or `balanceOf`?

- `receive()` (line 282): Only accepts ETH, no balance/supply changes.
- `depositSteth()` (line 291): Only transfers stETH, no balance/supply changes.
- `gameAdvance()` (line 259): Delegates to game, no balance/supply changes in sDGNRS.
- `gameClaimWhalePass()` (line 264): Delegates to game, no balance/supply changes.
- `resolveCoinflips()` (line 271): Delegates to coinflip, no balance/supply changes.
- `previewBurn()` (line 454): View function, no state changes.
- `burnieReserve()` (line 481): View function, no state changes.
- `poolBalance()` (line 303): View function, no state changes.

No Solidity `fallback()` function exists. The `receive()` function only handles ETH deposits.

**Verdict: INVARIANT HOLDS.** Every code path that modifies `totalSupply` correspondingly modifies `balanceOf` by the same amount, and every code path that moves `balanceOf` between addresses nets to zero. The supply conservation invariant is maintained across all 6 modification paths (Paths 1-6) and is unreachable from all remaining functions.

---

### Invariant 2: Cross-Contract Supply Invariant

**Formal Statement:**

```
For all states S reachable from post-deployment:
  sDGNRS.balanceOf[DGNRS_ADDRESS] >= DGNRS.totalSupply
```

The gap `G = sDGNRS.balanceOf[DGNRS] - DGNRS.totalSupply >= 0` represents the cumulative amount unwrapped via `unwrapTo()`.

**Proof by exhaustive path enumeration:**

This proof builds on the Phase 19 analysis in v2.0-delta-core-contracts.md (Cross-Contract Supply Invariant, DELTA-03) and confirms completeness against all code paths.

**Initial state (constructors):**

1. sDGNRS constructor: `_mint(ContractAddresses.DGNRS, creatorAmount)` at StakedDegenerusStonk.sol:212 sets `sDGNRS.balanceOf[DGNRS] = creatorAmount = 200,000,000,000 * 1e18`.
2. DGNRS constructor: reads `deposited = stonk.balanceOf(address(this)) = creatorAmount` at DegenerusStonk.sol:80, then sets `totalSupply = deposited` at DegenerusStonk.sol:82 and `balanceOf[CREATOR] = deposited` at DegenerusStonk.sol:83.
3. **At genesis: `sDGNRS.balanceOf[DGNRS] == DGNRS.totalSupply == creatorAmount`. Gap G = 0. Invariant holds (equality).**

**Modification Path 1: DGNRS.burn(amount) -- burn-through**

1. DGNRS._burn(msg.sender, amount): `DGNRS.totalSupply -= amount` at DegenerusStonk.sol:207.
2. stonk.burn(amount): `sDGNRS.balanceOf[DGNRS] -= amount` at StakedDegenerusStonk.sol:399 (player = msg.sender = DGNRS contract).
3. Both sides decrease by exactly `amount`. Gap unchanged: `G' = G`.
4. **Invariant preserved.**

**Modification Path 2: DGNRS.unwrapTo(recipient, amount) -- DegenerusStonk.sol:139-145**

1. DGNRS._burn(CREATOR, amount): `DGNRS.totalSupply -= amount` at DegenerusStonk.sol:207.
2. stonk.wrapperTransferTo(recipient, amount): `sDGNRS.balanceOf[DGNRS] -= amount` at StakedDegenerusStonk.sol:248.
3. Both sides decrease by exactly `amount`. Gap unchanged: `G' = G`.
4. **Invariant preserved.**

**Modification Path 3: DGNRS.transfer / DGNRS.transferFrom**

1. Modifies `DGNRS.balanceOf` mappings only (DegenerusStonk.sol:190-200).
2. `DGNRS.totalSupply` unchanged.
3. `sDGNRS.balanceOf[DGNRS]` unchanged (no sDGNRS function called).
4. **Neither side of invariant changes. Preserved.**

**Modification Path 4: sDGNRS.transferFromPool(pool, to, amount)**

1. Transfers from `sDGNRS.balanceOf[address(this)]` (sDGNRS contract's own pools) to recipient at StakedDegenerusStonk.sol:326-327.
2. Does NOT modify `sDGNRS.balanceOf[DGNRS]` (the DGNRS contract's sDGNRS balance).
3. Does NOT modify `DGNRS.totalSupply`.
4. **Neither side of invariant changes. Preserved.**

Edge consideration: Could `to == ContractAddresses.DGNRS`? Technically yes, but `transferFromPool` is `onlyGame` (StakedDegenerusStonk.sol:315), and the game distributes pool tokens to player addresses, not the DGNRS contract. Even if it did, it would INCREASE `sDGNRS.balanceOf[DGNRS]` while `DGNRS.totalSupply` stays the same, widening the gap -- this STRENGTHENS the invariant.

**Modification Path 5: sDGNRS.burnRemainingPools()**

1. Burns `sDGNRS.balanceOf[address(this)]` at StakedDegenerusStonk.sol:363 (the sDGNRS contract's own pool balance).
2. Does NOT modify `sDGNRS.balanceOf[DGNRS]`.
3. Does NOT modify `DGNRS.totalSupply`.
4. **Neither side of invariant changes. Preserved.**

**Modification Path 6: sDGNRS.burn() called by a direct sDGNRS holder (not DGNRS)**

1. Burns from `balanceOf[holder]` where `holder != ContractAddresses.DGNRS` at StakedDegenerusStonk.sol:399.
2. Does NOT modify `sDGNRS.balanceOf[DGNRS]`.
3. Does NOT modify `DGNRS.totalSupply`.
4. **Neither side of invariant changes. Preserved.**

**Monotonicity argument:**

- `DGNRS.totalSupply` is monotonically non-increasing after construction. DGNRS has no `_mint` function (DegenerusStonk.sol contains only `_burn` at line 202, no mint). The only code path that creates DGNRS supply is the constructor.
- `sDGNRS.balanceOf[DGNRS]` can only decrease via: `burn()` (Path 1), `wrapperTransferTo()` (Path 2). Both paths correspondingly decrease `DGNRS.totalSupply` by the same amount.

**Verdict: INVARIANT HOLDS across all 6 modification paths.** The gap G is always >= 0 and represents the cumulative amount unwrapped via `unwrapTo()`. The gap can only remain constant or increase (if pool tokens were ever sent to the DGNRS address). No path exists to make `DGNRS.totalSupply > sDGNRS.balanceOf[DGNRS]`.

---

### Invariant 3: Backing Solvency

**Formal Statement:**

```
For any burn of `amount` tokens from total supply `S` with backing reserves
{ethBal, stethBal, claimableEth}:

  The proportional payout (totalMoney * amount) / S can always be fulfilled
  by actual reserves, OR the burn reverts.

Where: totalMoney = ethBal + stethBal + claimableEth
       ethBal     = address(this).balance      (StakedDegenerusStonk.sol:387)
       stethBal   = steth.balanceOf(this)       (StakedDegenerusStonk.sol:388)
       claimableEth = _claimableWinnings()      (StakedDegenerusStonk.sol:389)
```

Equivalently: the protocol NEVER pays out more backing assets than it actually holds. The worst case is that a burn reverts, which is safe (no state changes committed, no funds lost).

**Proof:**

**Step 1: Payout calculation (StakedDegenerusStonk.sol:385-396)**

```solidity
uint256 supplyBefore = totalSupply;                    // line 385
uint256 ethBal = address(this).balance;                // line 387
uint256 stethBal = steth.balanceOf(address(this));     // line 388
uint256 claimableEth = _claimableWinnings();           // line 389
uint256 totalMoney = ethBal + stethBal + claimableEth; // line 390
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore; // line 391
```

The payout `totalValueOwed` is the proportional share: `amount / supplyBefore` of `totalMoney`.

Since `amount <= supplyBefore` (enforced by `amount <= balanceOf[player] <= totalSupply` at line 384), we have `totalValueOwed <= totalMoney`.

**Step 2: ETH-preferential payout logic (StakedDegenerusStonk.sol:404-416)**

Case A -- `totalValueOwed <= ethBal` (line 410):
- `ethOut = totalValueOwed`. Paid from `address(this).balance`.
- Since `totalValueOwed <= ethBal = address(this).balance`, the contract has sufficient ETH. **Solvent.**

Case B -- `totalValueOwed > ethBal` (lines 404-416):
- First, if `claimableEth != 0`, calls `game.claimWinnings(address(0))` at line 405.
- Re-reads: `ethBal = address(this).balance` (line 406), `stethBal = steth.balanceOf(address(this))` (line 407).
- `ethOut = ethBal` (line 413).
- `stethOut = totalValueOwed - ethOut` (line 414).
- **Critical check:** `if (stethOut > stethBal) revert Insufficient()` at StakedDegenerusStonk.sol:415.

This revert is the **solvency backstop**. If the combined ETH + stETH after claiming winnings cannot cover the proportional payout, the burn reverts. No funds are lost, no state is permanently changed (the `balanceOf` and `totalSupply` modifications at lines 399-400 are reverted by the EVM's atomic transaction model).

**Step 3: Can `ethBal + stethBal < totalValueOwed` after claimWinnings?**

After `game.claimWinnings(address(0))` at line 405:
- ETH from claimable winnings flows to sDGNRS via `receive()` (line 282), increasing `address(this).balance`.
- The re-read at line 406 captures this new ETH.
- `totalValueOwed` was calculated using `totalMoney = ethBal_old + stethBal_old + claimableEth`.
- After claiming: new `ethBal` should be approximately `ethBal_old + claimableEth` (minus any dust/sentinel).
- Therefore `ethBal_new + stethBal_new >= totalValueOwed` should hold.

However, edge cases exist:
- `_claimableWinnings()` returns `stored - 1` at StakedDegenerusStonk.sol:496 (1 wei dust reduction). The game's claimWinnings may send `stored - 1` wei too (sentinel handling). This could create a 1-2 wei shortfall.
- stETH rebasing: between the `stethBal` read (line 388) and the re-read (line 407), a Lido rebase could change the balance. A positive rebase increases stETH (helps solvency). A negative rebase (slashing event, extremely rare) could reduce stETH.
- `game.claimWinnings` may use `_payoutWithStethFallback`, which could send stETH instead of ETH. The re-read of both `ethBal` and `stethBal` at lines 406-407 accounts for this.

In all edge cases, the `Insufficient()` revert at line 415 acts as the final backstop: if the math doesn't work out, the burn simply fails rather than overpaying.

**Step 4: BURNIE solvency (StakedDegenerusStonk.sol:393-428)**

```solidity
uint256 burnieBal = coin.balanceOf(address(this));     // line 393
uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this)); // line 394
uint256 totalBurnie = burnieBal + claimableBurnie;     // line 395
burnieOut = (totalBurnie * amount) / supplyBefore;     // line 396
```

BURNIE payout `burnieOut <= totalBurnie` (since `amount <= supplyBefore`).
- First pays from existing balance (lines 420-424).
- If insufficient, claims from coinflip (line 426) which mints BURNIE to sDGNRS.
- Then transfers the remainder (line 427).

If coinflip.claimCoinflips does not mint enough BURNIE, the `coin.transfer` at line 427 would revert (standard ERC20 insufficient balance), preventing overpayment. **Solvent.**

**Step 5: Concurrent burn safety**

Two burns in the same block are processed sequentially (EVM transactions are serialized). The first burn reduces `totalSupply` and `balanceOf[player]` at lines 399-400 BEFORE any external calls. The second burn reads the already-reduced `totalSupply`, receiving a proportionally correct (smaller absolute) payout. No concurrent double-spend is possible.

**Verdict: INVARIANT HOLDS.** The protocol never pays out more backing assets than it holds. The `Insufficient()` revert at StakedDegenerusStonk.sol:415 is the ultimate backstop: if any edge case (stETH rounding, dust, rebase timing) causes a shortfall, the burn reverts safely. For BURNIE, standard ERC20 transfer reverts prevent overpayment. The worst case is a reverted burn, which is a safe outcome (no state changes committed, no funds lost).

---

### Invariant 4: Pool Balance Consistency (Pre-GameOver)

**Formal Statement:**

```
For all states S reachable before burnRemainingPools() is called:
  sDGNRS.balanceOf[address(this)] == SUM(poolBalances[i]) for i in {Whale, Affiliate, Lootbox, Reward, Earlybird}

Post-gameOver (after burnRemainingPools): balanceOf[address(this)] = 0,
  but poolBalances entries retain stale values. This is SAFE because all
  pool-consuming paths revert when gameOver == true.
```

**Proof by exhaustive path enumeration:**

**Initial state (constructor, StakedDegenerusStonk.sol:194-219):**

```solidity
_mint(address(this), poolTotal);                       // line 213

poolBalances[uint8(Pool.Whale)] = whaleAmount;         // line 215
poolBalances[uint8(Pool.Affiliate)] = affiliateAmount; // line 216
poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;     // line 217
poolBalances[uint8(Pool.Reward)] = rewardAmount;       // line 218
poolBalances[uint8(Pool.Earlybird)] = earlybirdAmount; // line 219
```

Where `poolTotal = whaleAmount + earlybirdAmount + affiliateAmount + lootboxAmount + rewardAmount` (computed at StakedDegenerusStonk.sol:209-210).

Therefore: `balanceOf[address(this)] = poolTotal = SUM(poolBalances[i])`. **Invariant holds at genesis.**

**Path 1: `transferFromPool(pool, to, amount)` -- StakedDegenerusStonk.sol:315-332**

```solidity
poolBalances[idx] = available - amount;                // line 325
balanceOf[address(this)] -= amount;                    // line 326
```

Both `poolBalances[idx]` and `balanceOf[address(this)]` decrease by `amount`. Other pool entries unchanged. SUM(poolBalances) decreases by `amount`, `balanceOf[address(this)]` decreases by `amount`. **Invariant preserved.**

**Path 2: `transferBetweenPools(from, to, amount)` -- StakedDegenerusStonk.sol:340-355**

```solidity
poolBalances[fromIdx] = available - amount;            // line 350
poolBalances[toIdx] += amount;                         // line 352
```

Zero-sum rebalance between pools. SUM(poolBalances) unchanged. No `balanceOf` modification. **Invariant preserved.**

**Path 3: `burnRemainingPools()` -- StakedDegenerusStonk.sol:359-367**

Sets `balanceOf[address(this)] = 0` (line 363) and `totalSupply -= bal` (line 364), but does NOT zero `poolBalances[]`. After this call, `poolBalances` entries contain stale nonzero values while `balanceOf[address(this)] = 0`.

**Why this is safe:** `burnRemainingPools()` is called only by the game contract during game over (DegenerusGameGameOverModule.sol:163). After `gameOver = true` (set at line 112 of the same module), all game entry points that call `transferFromPool` check `if (gameOver) revert E()` and revert. No path to `transferFromPool` or `transferBetweenPools` is reachable after `burnRemainingPools`. The stale `poolBalances` values are effectively dead code.

If hypothetically `transferFromPool` were called after `burnRemainingPools`, the unchecked `balanceOf[address(this)] -= amount` at line 326 would underflow (0 - positive wraps to ~2^256 in unchecked arithmetic). This would be catastrophic. However, the game-over guard makes this path unreachable. See DELTA-I-01.

**Completeness check:** No other function modifies `poolBalances` or `balanceOf[address(this)]` in ways that affect this invariant:
- `burn()` modifies `balanceOf[player]` where `player != address(this)` (a user cannot hold tokens at `address(this)` -- only the contract's own pool balance is there, and users cannot call `burn()` as the contract itself).
- `wrapperTransferTo()` modifies `balanceOf[DGNRS]` and `balanceOf[to]`, not `balanceOf[address(this)]`.
- `_mint()` is only in constructor.

**Verdict: INVARIANT HOLDS (pre-gameOver).** The pool balance consistency invariant is maintained across all pre-gameOver modification paths (transferFromPool, transferBetweenPools). Post-gameOver, `poolBalances` becomes stale but is unreachable due to the `gameOver` terminal guard. Already documented as finding DELTA-I-01 (Informational).

---

### Invariant Summary Table

| # | Invariant | Formal Statement | Holds? | Backstop | Evidence |
|---|-----------|------------------|--------|----------|----------|
| 1 | sDGNRS Supply Conservation | `totalSupply == SUM(balanceOf[addr])` | **HOLDS** | None needed -- algebraically proven across all 6 paths | StakedDegenerusStonk.sol:399-400 (burn), :510-517 (_mint), :248-249 (wrapperTransferTo), :326-327 (transferFromPool), :350-352 (transferBetweenPools), :363-364 (burnRemainingPools) |
| 2 | Cross-Contract Supply | `sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply` | **HOLDS** | Monotonicity: DGNRS has no mint function | StakedDegenerusStonk.sol:212 (genesis mint to DGNRS), DegenerusStonk.sol:80-83 (constructor reads sDGNRS balance), :207 (only supply-reducing path) |
| 3 | Backing Solvency | `burn payout <= actual reserves, OR burn reverts` | **HOLDS** | `Insufficient()` revert at StakedDegenerusStonk.sol:415 | StakedDegenerusStonk.sol:387-391 (proportional calculation), :410-416 (ETH/stETH split), :415 (solvency revert), :393-396 (BURNIE calculation) |
| 4 | Pool Balance Consistency | `balanceOf[this] == SUM(poolBalances[i])` pre-gameOver | **HOLDS** | gameOver terminal guard prevents post-burn pool access | StakedDegenerusStonk.sol:209-219 (constructor), :325-326 (transferFromPool), :350-352 (transferBetweenPools), DegenerusGameGameOverModule.sol:112 (gameOver flag), :163 (burnRemainingPools call) |

All four invariants hold across all reachable states. The protocol's fundamental guarantees -- supply conservation, cross-contract consistency, backing solvency, and pool accounting -- are mathematically sound.

---
