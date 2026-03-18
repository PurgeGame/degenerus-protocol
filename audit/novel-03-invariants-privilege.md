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
- ~~`resolveCoinflips()` (line 271)~~: **Removed.** sDGNRS flips now resolve daily inside `BurnieCoinflip.processCoinflipPayouts()`.
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

## NOVEL-09: Privilege Escalation Audit

This section enumerates every address capable of triggering state changes in the sDGNRS/DGNRS system, analyzes how each address is authorized, whether that authorization can be changed post-deployment, and whether any escalation path exists to bypass the access control.

### Part 1: Complete Privilege Map

The following table lists every address type that can trigger state changes (non-view mutations) in StakedDegenerusStonk.sol or DegenerusStonk.sol, along with the exact access control mechanism, source location, and mutability.

| Address | Functions Accessible | Modifier/Check | Source Line | Can Be Changed? |
|---------|---------------------|----------------|-------------|-----------------|
| GAME contract (`0x3381...440f`) | `transferFromPool`, `transferBetweenPools`, `burnRemainingPools`, `depositSteth`, `receive()` (ETH deposit) | `onlyGame` modifier: `msg.sender != ContractAddresses.GAME` | StakedDegenerusStonk.sol:181-184 (modifier), :315, :340, :359, :291, :282 | **No -- immutable.** `ContractAddresses.GAME` is a compile-time `address internal constant` (ContractAddresses.sol:28). Cannot be modified post-deployment. |
| DGNRS contract (`0xDA5A...4C2d`) | `wrapperTransferTo` | `msg.sender != ContractAddresses.DGNRS` check | StakedDegenerusStonk.sol:243 | **No -- immutable.** `ContractAddresses.DGNRS` is a compile-time constant (ContractAddresses.sol:30). |
| CREATOR address (`0x7FA9...1496`) | `unwrapTo` (on DGNRS contract) | `msg.sender != ContractAddresses.CREATOR` check | DegenerusStonk.sol:140 | **No -- immutable.** `ContractAddresses.CREATOR` is a compile-time constant (ContractAddresses.sol:36). |
| Any address (public) | `burn` (own tokens) | None -- public. Guards: `amount > 0`, `amount <= balanceOf[msg.sender]` | StakedDegenerusStonk.sol:381, :384 | N/A -- public function, anyone with sDGNRS balance can call |
| Any address (public) | `gameAdvance`, `gameClaimWhalePass` | None -- public permissionless helpers | StakedDegenerusStonk.sol:259, :264 | N/A -- delegate to game, which handles its own auth. (`resolveCoinflips` removed — sDGNRS flips now resolve daily inside `processCoinflipPayouts`.) |
| Any address (public, DGNRS) | `transfer`, `transferFrom`, `approve`, `burn` | Standard ERC20 checks | DegenerusStonk.sol:101, :113, :128, :153 | N/A -- public ERC20 functions |

**Per-address detailed analysis:**

#### GAME Contract (`ContractAddresses.GAME`)

**How address is set:** Compile-time constant in ContractAddresses.sol:28: `address internal constant GAME = address(0x3381cD18e2Fb4dB236BF0525938AB6E43Db0440f)`. The ContractAddresses library is imported at StakedDegenerusStonk.sol:4 and used in the `onlyGame` modifier at line 182.

**Can the address be changed post-deployment?** No. `ContractAddresses.GAME` is a Solidity `constant`, meaning the value is inlined into the bytecode at compile time. There is no storage slot, no setter function, and no proxy indirection. The only way to change it would be to deploy a new sDGNRS contract.

**What is the worst-case action this address can take?**
- Drain all pool balances via repeated `transferFromPool` calls (StakedDegenerusStonk.sol:315-332). This could transfer up to 800B sDGNRS (80% of initial supply) from pools to arbitrary addresses.
- Burn all undistributed pool tokens via `burnRemainingPools` (StakedDegenerusStonk.sol:359-367), permanently destroying up to 800B sDGNRS.
- Deposit arbitrary amounts of stETH via `depositSteth` (StakedDegenerusStonk.sol:291-293).
- Deposit arbitrary amounts of ETH via `receive()` (StakedDegenerusStonk.sol:282-284).

**Is this a concern?** The game contract is a trusted protocol contract deployed by the same development team. If the game contract is compromised or has a bug, the entire protocol is compromised regardless of sDGNRS access control. The game contract's own security is audited separately across Phases 1-18 of the audit.

#### DGNRS Contract (`ContractAddresses.DGNRS`)

**How address is set:** Compile-time constant in ContractAddresses.sol:30: `address internal constant DGNRS = address(0xDA5A5ADC64C8013d334A0DA9e711B364Af7A4C2d)`. Used at StakedDegenerusStonk.sol:243.

**Can the address be changed post-deployment?** No. Same reasoning as GAME -- compile-time constant, no storage slot, no setter.

**What is the worst-case action this address can take?**
- Move sDGNRS from `balanceOf[DGNRS]` to any recipient via `wrapperTransferTo` (StakedDegenerusStonk.sol:242-252). Limited to `sDGNRS.balanceOf[DGNRS]` (initially 200B sDGNRS, the creator's 20% allocation).
- Cannot create new tokens (no mint function accessible).
- Cannot access pool balances, reserves, or other users' tokens.

**Is this a concern?** The DGNRS contract is a thin ERC20 wrapper. Its `wrapperTransferTo` is called only from `unwrapTo` (DegenerusStonk.sol:143), which is CREATOR-only. No path in DGNRS calls `wrapperTransferTo` without the CREATOR authorization check.

#### CREATOR Address (`ContractAddresses.CREATOR`)

**How address is set:** Compile-time constant in ContractAddresses.sol:36: `address internal constant CREATOR = address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496)`. Used at DegenerusStonk.sol:140.

**Can the address be changed post-deployment?** No. Compile-time constant.

**What is the worst-case action this address can take?**
- Call `DGNRS.unwrapTo(recipient, amount)` to burn their own DGNRS and send the underlying sDGNRS to any recipient. Limited to CREATOR's DGNRS balance.
- This is intentional functionality: the creator can convert their transferable DGNRS back to soulbound sDGNRS for specific recipients (e.g., team members, advisors).
- Cannot access other users' tokens. Cannot exceed their own DGNRS balance (DegenerusStonk.sol:204 reverts on insufficient balance).

**Is this a concern?** No. This is a feature with correct authorization. The creator can only affect their own tokens.

---

### Part 2: Escalation Path Analysis

Four potential escalation vectors are analyzed to determine if any non-authorized address can call privileged functions.

#### Escalation 1: Delegatecall to sDGNRS

**Hypothesis:** Could any contract delegatecall into sDGNRS to bypass access control (e.g., execute `transferFromPool` with a spoofed `msg.sender`)?

**Analysis:**

1. **sDGNRS as delegatecall target:** For a delegatecall into sDGNRS to be meaningful, an attacker would need to delegatecall sDGNRS's code from their own contract. In delegatecall, the code runs in the caller's storage context. The `onlyGame` check at StakedDegenerusStonk.sol:182 reads `msg.sender != ContractAddresses.GAME`. In a delegatecall, `msg.sender` is the original transaction sender (preserved through the delegatecall chain), NOT the attacker's contract address. So the attacker's `msg.sender` would need to equal `ContractAddresses.GAME` -- i.e., the original caller of the attacker's contract must BE the game contract. This is not a useful escalation path.

2. **More importantly:** Even if an attacker delegatecalled sDGNRS code, the code would run against the ATTACKER's storage, not sDGNRS's storage. The attacker would be modifying their own `totalSupply`, `balanceOf`, and `poolBalances` mappings -- not the real sDGNRS contract's state. No escalation.

3. **Game's delegatecall to modules:** DegenerusGame.sol uses delegatecall extensively (lines 324, 352, 589, 616, 637, etc.) to execute module code in the game's storage context. When a module (e.g., WhaleModule at line 639) calls `dgnrs.transferFromPool(...)`, this is a regular external call FROM the game contract's address. Since the module code runs in the game's context (via delegatecall), the external call to sDGNRS has `msg.sender = game_contract_address`. This correctly passes the `onlyGame` check.

   **Detailed trace:** User -> Game.advanceGame() (external call, msg.sender=User) -> delegatecall to AdvanceModule.advanceGame() (module code runs in Game's storage context) -> sDGNRS.transferFromPool(...) (external call, msg.sender=Game_address). The `onlyGame` modifier at StakedDegenerusStonk.sol:182 checks `msg.sender != ContractAddresses.GAME`, which passes because the external call comes from the game contract's address. This is the intended behavior.

4. **Can an attacker get the game to delegatecall malicious code?** No. All delegatecall targets are compile-time constants from ContractAddresses.sol (e.g., `GAME_ADVANCE_MODULE`, `GAME_MINT_MODULE`, etc. at ContractAddresses.sol:12-21). There is no setter function, no dynamic module registration, and no proxy upgrade mechanism.

**Verdict: NO ESCALATION.** Delegatecall into sDGNRS executes against the caller's storage (useless). The game's delegatecall modules correctly call sDGNRS as the game contract, passing the `onlyGame` check. Module addresses are immutable compile-time constants.

---

#### Escalation 2: Proxy Upgrade

**Hypothesis:** Could sDGNRS or DGNRS be upgraded to a malicious implementation that bypasses access control?

**Analysis:**

1. **StakedDegenerusStonk.sol:** The contract is a plain Solidity contract (line 48: `contract StakedDegenerusStonk {`). No inheritance from any proxy base class. No UUPS, no TransparentProxy, no ERC1967, no diamond pattern. No `fallback()` function that could redirect calls.

2. **DegenerusStonk.sol:** Same -- plain contract (line 24: `contract DegenerusStonk {`). No proxy patterns. No `fallback()` function.

3. **DegenerusGame.sol:** Uses delegatecall to modules but is NOT a proxy. The game contract itself has its own logic and delegates specific function calls to module contracts. The module addresses are compile-time constants (ContractAddresses.sol:12-21). The game contract explicitly documents itself as non-upgradeable (DegenerusGameStorage.sol:84: "Append-only additions are safe for non-upgradeable contracts", line 109: "This contract is NOT upgradeable (no proxy pattern)").

4. **Compile-time constants:** All cross-contract references (GAME, DGNRS, SDGNRS, CREATOR, module addresses) are `address internal constant` in ContractAddresses.sol. These are inlined into bytecode at compile time. No storage variable, no admin setter, no governance function can change them.

**Verdict: NO ESCALATION.** None of the contracts use proxy patterns. All addresses are compile-time constants. The contracts cannot be upgraded post-deployment.

---

#### Escalation 3: CREATE2/Selfdestruct Address Collision

**Hypothesis:** Could an attacker deploy a malicious contract at the same address as the game contract (after it selfdestructs), then call sDGNRS's `onlyGame` functions?

**Analysis:**

1. **Selfdestruct in the protocol:** A search of all contract source files finds ZERO occurrences of `selfdestruct` in any protocol contract (StakedDegenerusStonk.sol, DegenerusStonk.sol, DegenerusGame.sol, all modules, storage contracts). The game contract will never selfdestruct.

2. **Post-Cancun EIP-6780:** Since the Dencun upgrade (March 2024), `selfdestruct` only clears contract state when called in the same transaction as contract creation. Outside the creation transaction, `selfdestruct` only transfers remaining ETH but does NOT remove the contract code or reset the nonce. This means:
   - Even if the game contract HAD a selfdestruct, post-Cancun it would not be cleared (assuming it's not called in the creation tx).
   - Even pre-Cancun, re-deploying at the same address via CREATE2 requires the exact same `salt` and `initcode`. An attacker cannot control the deployed bytecode while matching the address.

3. **CREATE2 collision attack:** For an attacker to deploy at `ContractAddresses.GAME = 0x3381cD18e2Fb4dB236BF0525938AB6E43Db0440f`, they would need to find a CREATE2 factory address + salt combination that produces this address with their malicious bytecode. This requires a 160-bit preimage attack (computationally infeasible: ~2^80 operations with birthday attack, well beyond practical capability).

**Verdict: NO ESCALATION.** The game contract has no `selfdestruct`. Post-Cancun EIP-6780 limits selfdestruct's clearing behavior. CREATE2 address collision is computationally infeasible. This attack vector is purely theoretical.

---

#### Escalation 4: msg.sender Spoofing via tx.origin

**Hypothesis:** Could an attacker spoof `msg.sender` to impersonate the game contract, using `tx.origin` confusion or other EVM-level tricks?

**Analysis:**

1. **tx.origin in sDGNRS:** A search of StakedDegenerusStonk.sol finds ZERO occurrences of `tx.origin`. All access control uses `msg.sender` exclusively:
   - `onlyGame` modifier at line 182: `if (msg.sender != ContractAddresses.GAME) revert Unauthorized()`
   - `wrapperTransferTo` at line 243: `if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized()`

2. **tx.origin in DGNRS:** A search of DegenerusStonk.sol finds ZERO occurrences of `tx.origin`. The `unwrapTo` check at line 140 uses `msg.sender`: `if (msg.sender != ContractAddresses.CREATOR) revert Unauthorized()`.

3. **tx.origin in the broader protocol:** A search of all contract source files finds ZERO occurrences of `tx.origin` anywhere in the protocol codebase.

4. **EVM msg.sender guarantees:** In the EVM, `msg.sender` for an external call is always the address of the contract (or EOA) that made the call. It cannot be spoofed:
   - Direct calls: `msg.sender` = caller address
   - Delegatecall: `msg.sender` = the original external caller (preserved)
   - Staticcall: `msg.sender` = caller address
   - No EVM opcode allows setting `msg.sender` to an arbitrary value

5. **Could a malicious contract trick the game into calling sDGNRS?** Only if the game contract has a function that:
   a. Accepts user-controlled calldata, AND
   b. Forwards it as an external call to sDGNRS with the game as `msg.sender`.

   The game contract does NOT have generic call-forwarding functions. All delegatecall targets are hardcoded module addresses with specific function selectors (e.g., `IDegenerusGameAdvanceModule.advanceGame.selector` at DegenerusGame.sol:326). The game never uses `address.call(userProvidedData)` with arbitrary calldata.

**Verdict: NO ESCALATION.** All access control is `msg.sender`-based. No `tx.origin` usage anywhere. `msg.sender` cannot be spoofed at the EVM level. The game contract has no generic call-forwarding that could be exploited.

---

### Part 3: Worst-Case Privileged Actions

For each privileged address, the maximum possible damage is documented below, assuming the privileged address acts maliciously or is compromised.

#### GAME Contract -- Worst Case

| Action | Maximum Damage | Mechanism |
|--------|---------------|-----------|
| Drain all pools | Transfer up to 800B sDGNRS to attacker-controlled addresses | Repeated `transferFromPool` calls for each pool |
| Destroy undistributed tokens | Burn up to 800B sDGNRS permanently | `burnRemainingPools()` |
| Inflate reserves | Deposit unlimited stETH/ETH to sDGNRS reserves | `depositSteth` + `receive()` |
| Rebalance pools arbitrarily | Move tokens between pools | `transferBetweenPools` |

**Assessment:** The game contract has the highest privilege level. A compromised game contract could drain all pool tokens and manipulate reserves. However, the game is a trusted protocol contract deployed by the same team. If the game is compromised, the entire protocol (including jackpot pools, affiliate rewards, quest rewards, etc.) is compromised regardless of sDGNRS access control. The game contract is a **trust anchor** -- its correctness is a prerequisite for the entire system.

The game contract itself is protected by:
- Immutable module addresses (ContractAddresses.sol:12-21)
- No admin upgrade mechanism (DegenerusGameStorage.sol:109: "NOT upgradeable")
- VRF-based randomness preventing state manipulation (DegenerusGame.sol:14)
- Access control on admin functions (ADMIN address at ContractAddresses.sol:31)

#### DGNRS Contract -- Worst Case

| Action | Maximum Damage | Mechanism |
|--------|---------------|-----------|
| Move sDGNRS from wrapper balance | Transfer up to `sDGNRS.balanceOf[DGNRS]` (initially 200B) to arbitrary address | `wrapperTransferTo(to, amount)` |

**Assessment:** The DGNRS contract can only move tokens that are already in its own sDGNRS balance -- the creator's 20% allocation. It cannot create new tokens, access pool balances, or interact with reserves. The DGNRS contract's `wrapperTransferTo` is called only from `unwrapTo` (DegenerusStonk.sol:143), which requires the CREATOR's DGNRS balance to cover the amount. The DGNRS contract has no path to call `wrapperTransferTo` without burning the corresponding DGNRS tokens first.

#### CREATOR Address -- Worst Case

| Action | Maximum Damage | Mechanism |
|--------|---------------|-----------|
| Unwrap DGNRS to arbitrary recipients | Send up to CREATOR's DGNRS balance worth of soulbound sDGNRS to any address | `unwrapTo(recipient, amount)` |

**Assessment:** The CREATOR can only affect their own tokens. They cannot access other users' DGNRS balances, pool tokens, or reserves. The `unwrapTo` function burns from CREATOR's DGNRS balance first (DegenerusStonk.sol:142: `_burn(msg.sender, amount)` which checks `amount <= balanceOf[msg.sender]` at line 204), then moves the corresponding sDGNRS. The maximum amount is bounded by CREATOR's DGNRS holdings, which starts at 200B (20% of supply) and decreases with every burn or unwrap.

---

### Privilege Assessment Summary

**Overall Verdict: NO PRIVILEGE ESCALATION PATHS EXIST.**

The sDGNRS/DGNRS privilege model is based on three principles, all of which hold:

1. **Immutable authorization:** All privileged addresses (GAME, DGNRS, CREATOR) are compile-time constants in ContractAddresses.sol, inlined into contract bytecode. No setter function, no admin override, no governance mechanism can change them post-deployment.

2. **msg.sender-only access control:** All authorization checks use `msg.sender`, which cannot be spoofed at the EVM level. No `tx.origin` is used anywhere in the protocol. No generic call-forwarding exists that could be exploited.

3. **No upgrade mechanism:** None of the contracts (sDGNRS, DGNRS, Game) use proxy patterns (UUPS, TransparentProxy, diamond). The contracts are plain Solidity with no `fallback()` function, no `selfdestruct`, and no dynamic module registration.

**Escalation vector summary:**

| Vector | Analyzed | Verdict | Key Evidence |
|--------|----------|---------|-------------|
| Delegatecall to sDGNRS | Yes | **NO ESCALATION** | Delegatecall runs against caller's storage; game modules correctly use external calls with msg.sender = game address |
| Proxy Upgrade | Yes | **NO ESCALATION** | No proxy patterns; explicitly non-upgradeable (DegenerusGameStorage.sol:109); all addresses are compile-time constants |
| CREATE2/Selfdestruct collision | Yes | **NO ESCALATION** | No selfdestruct in any contract; post-Cancun EIP-6780 limits clearing; 160-bit preimage attack infeasible |
| msg.sender spoofing / tx.origin | Yes | **NO ESCALATION** | Zero tx.origin usage; msg.sender is EVM-guaranteed; no generic call-forwarding in game contract |

The privilege model is minimal, immutable, and correctly enforced. The only trust assumption is the correctness of the game contract itself, which is a necessary trust anchor for the entire protocol.

---
