# Novel Attack Surface Analysis: Composition, Griefing, and Edge Cases

**Audit Date:** 2026-03-16
**Auditor:** Claude (AI-assisted security analysis, Claude Opus 4.6)
**Scope:** Cross-contract composition attacks (NOVEL-02), griefing vectors (NOVEL-03), edge case boundaries (NOVEL-04)
**Methodology:** C4A warden-style deep code tracing with file:line citations, gas/cost analysis, boundary condition matrix
**Prior Reports:** `v2.0-delta-core-contracts.md` (DELTA-01 through DELTA-03), `v2.0-delta-consumer-callsites.md` (DELTA-04 through DELTA-08)

---

## NOVEL-02: Composition Attack Analysis

This section maps every cross-contract call chain involving the sDGNRS/DGNRS dual-token system, traces state changes at each step, assesses CEI compliance and reentrancy risk, and identifies any state consistency issues.

### Call Chain 1: DGNRS.burn() -> sDGNRS.burn() -> game.claimWinnings() -> sDGNRS.receive()

This is the most complex call chain in the system -- a burn-through that can trigger up to 8 external calls across 4 contracts.

**Complete call sequence:**

| Step | Location | Action | State Change |
|------|----------|--------|--------------|
| 1 | DegenerusStonk.sol:154 | `_burn(msg.sender, amount)` | DGNRS.balanceOf[user] -= amount; DGNRS.totalSupply -= amount |
| 2 | DegenerusStonk.sol:156 | `stonk.burn(amount)` | Control passes to sDGNRS |
| 3 | StakedDegenerusStonk.sol:385 | `supplyBefore = totalSupply` | Snapshot BEFORE any sDGNRS state change |
| 4 | StakedDegenerusStonk.sol:387-390 | Read `ethBal`, `stethBal`, `claimableEth`, compute `totalMoney` | Balance reads -- no state change |
| 5 | StakedDegenerusStonk.sol:391 | `totalValueOwed = (totalMoney * amount) / supplyBefore` | Payout calculation locked to pre-burn snapshot |
| 6 | StakedDegenerusStonk.sol:393-396 | Read `burnieBal`, `claimableBurnie`, compute `burnieOut` | Balance reads -- no state change |
| 7 | StakedDegenerusStonk.sol:398-401 | `balanceOf[player] -= amount; totalSupply -= amount` | **STATE COMMITTED** -- player is DGNRS contract; sDGNRS.balanceOf[DGNRS] and sDGNRS.totalSupply reduced |
| 8 | StakedDegenerusStonk.sol:402 | `emit Transfer(player, address(0), amount)` | Event only |
| 9 | StakedDegenerusStonk.sol:404 | Check: `totalValueOwed > ethBal && claimableEth != 0` | Branch condition |
| 10 | StakedDegenerusStonk.sol:405 | `game.claimWinnings(address(0))` | **EXTERNAL CALL to game** |
| 10a | DegenerusGame.sol:1397-1399 | `_resolvePlayer(address(0))` returns `msg.sender` = sDGNRS | Address resolution |
| 10b | DegenerusGame.sol:1419 | `claimableWinnings[sDGNRS] = 1` (sentinel) | Game state committed BEFORE payout |
| 10c | DegenerusGame.sol:1422 | `claimablePool -= payout` | Game state committed |
| 10d | DegenerusGame.sol:1427 | `_payoutWithStethFallback(sDGNRS, payout)` | ETH-first payout to sDGNRS |
| 10e | DegenerusGame.sol:1972 | `ethSend = amount <= ethBal ? amount : ethBal` | ETH available check |
| 10f | DegenerusGame.sol:1974 | `payable(sDGNRS).call{value: ethSend}` | ETH sent to sDGNRS.receive() |
| 10g | StakedDegenerusStonk.sol:282-283 | `receive() external payable onlyGame` | ETH accepted; `address(this).balance` increases |
| 10h | DegenerusGame.sol:1981-1983 | If `remaining > 0`: stETH fallback | **CRITICAL PATH** -- see stETH analysis below |
| 11 | StakedDegenerusStonk.sol:406 | `ethBal = address(this).balance` | **RE-READ** after claimWinnings |
| 12 | StakedDegenerusStonk.sol:407 | `stethBal = steth.balanceOf(address(this))` | **RE-READ** after claimWinnings |
| 13 | StakedDegenerusStonk.sol:410-416 | ETH-preferential payout split | Uses post-claim balances |
| 14 | StakedDegenerusStonk.sol:418-428 | BURNIE payout (balance + coinflip claim) | See Call Chain 2 |
| 15 | StakedDegenerusStonk.sol:431-432 | stETH transfer to player | If stethOut > 0 |
| 16 | StakedDegenerusStonk.sol:435-437 | ETH transfer to player | **LAST external call** |
| 17 | DegenerusStonk.sol:158-167 | DGNRS forwards BURNIE, stETH, ETH to user | Asset forwarding from DGNRS to actual user |

**CEI compliance:** All state changes (steps 1, 7) precede all external calls (steps 10-17). The game's own state changes (steps 10b, 10c) precede its payout call (step 10d). **PASS.**

**Critical question: Can claimWinnings change stethBal?**

YES. The call path from step 10d is:

1. `_payoutWithStethFallback(sDGNRS, payout)` at DegenerusGame.sol:1967
2. If ETH balance in the game contract is insufficient to cover `payout`, the function falls back to stETH at DegenerusGame.sol:1981-1983
3. `_transferSteth(sDGNRS, stSend)` at DegenerusGame.sol:1983
4. Inside `_transferSteth` at DegenerusGame.sol:1952-1960: **special routing for sDGNRS**
   - Line 1954: `if (to == ContractAddresses.SDGNRS)` -- YES, `to` is sDGNRS
   - Line 1955: `steth.approve(ContractAddresses.SDGNRS, amount)` -- approve sDGNRS to pull stETH
   - Line 1956: `dgnrs.depositSteth(amount)` -- calls sDGNRS.depositSteth()
   - StakedDegenerusStonk.sol:291-293: `steth.transferFrom(msg.sender, address(this), amount)` -- stETH transferred to sDGNRS
5. After return from claimWinnings, `steth.balanceOf(address(this))` at sDGNRS has INCREASED

**Is this properly accounted for?**

YES. The accounting chain is:

- At step 4-5: `totalMoney = ethBal + stethBal + claimableEth`. The `claimableEth` term pre-counts the game winnings that will be claimed.
- At step 10d-10h: game pays out `payout` worth of ETH+stETH to sDGNRS. This converts `claimableEth` from "virtual" to "actual" (ETH or stETH in sDGNRS balance).
- At steps 11-12: `ethBal` and `stethBal` are RE-READ. The re-read captures both the ETH and the stETH deposited during claimWinnings.
- At step 13: the payout split uses `totalValueOwed` (calculated at step 5 from pre-claim state including `claimableEth`) against post-claim `ethBal` and `stethBal`.

The total money available (`ethBal + stethBal` post-claim) should equal `ethBal_pre + stethBal_pre + claimableEth` minus any rounding. The `totalValueOwed` was calculated using `totalMoney` which included `claimableEth`, so the available funds match or exceed the obligation.

**Potential discrepancy:** The stETH fallback path introduces stETH 1-2 wei rounding (Lido's known behavior). If `_payoutWithStethFallback` transfers `X` stETH via `transferFrom`, the actual stETH received by sDGNRS could be `X - 1` due to share rounding. This creates a 1-2 wei gap between the expected and actual stETH balance. However, at step 12 the actual `stethBal` is read (not assumed), so the payout split at step 13 uses the real balance. The 1-2 wei gap only manifests if `stethOut > stethBal` at StakedDegenerusStonk.sol:415, which triggers `revert Insufficient()`. This is analyzed in detail under NOVEL-04 (stETH rounding edge case).

**Reentrancy risk:**
- Step 10g: sDGNRS.receive() has `onlyGame` modifier and only emits `Deposit` event. No state mutation, no callback. **SAFE.**
- Step 16: ETH sent to player (DGNRS contract). DGNRS.receive() is `receive() external payable {}` -- a no-op. **SAFE.**
- Step 17 (DGNRS forwarding ETH to actual user): If user is a malicious contract, re-entry into DGNRS.burn() sees already-reduced DGNRS balance (step 1). Re-entry into sDGNRS.burn() sees already-reduced sDGNRS.totalSupply (step 7). Both are proportionally correct. **SAFE.**

**Verdict: SAFE.** State changes before all external calls. claimWinnings can deposit both ETH and stETH into sDGNRS, but the re-read at steps 11-12 accounts for both. No exploitable state inconsistency.

---

### Call Chain 2: DGNRS.burn() -> sDGNRS.burn() -> coinflip.claimCoinflips()

**Complete call sequence:**

| Step | Location | Action | State Change |
|------|----------|--------|--------------|
| 1 | StakedDegenerusStonk.sol:393 | `burnieBal = coin.balanceOf(address(this))` | Read existing BURNIE balance |
| 2 | StakedDegenerusStonk.sol:394 | `claimableBurnie = coinflip.previewClaimCoinflips(address(this))` | Read claimable BURNIE (view call) |
| 3 | StakedDegenerusStonk.sol:396 | `burnieOut = (totalBurnie * amount) / supplyBefore` | BURNIE owed to burner |
| 4 | StakedDegenerusStonk.sol:398-401 | Balance and supply state changes committed | **STATE COMMITTED** |
| 5 | StakedDegenerusStonk.sol:418-420 | `remainingBurnie = burnieOut; payBal = min(remainingBurnie, burnieBal)` | Calculate from existing balance first |
| 6 | StakedDegenerusStonk.sol:423 | `coin.transfer(player, payBal)` | Transfer existing BURNIE to player (DGNRS contract) |
| 7 | StakedDegenerusStonk.sol:425-426 | If `remainingBurnie != 0`: `coinflip.claimCoinflips(address(0), remainingBurnie)` | **EXTERNAL CALL**: claims BURNIE from coinflip, minted to sDGNRS |
| 8 | StakedDegenerusStonk.sol:427 | `coin.transfer(player, remainingBurnie)` | Transfer claimed BURNIE to player |

**CEI compliance:** State changes (step 4) precede all BURNIE-related external calls (steps 6-8). **PASS.**

**Critical question: Can coinflip.claimCoinflips() change sDGNRS state?**

The call path is: sDGNRS -> BurnieCoinflip.claimCoinflips(address(0), remainingBurnie) -> `_resolvePlayer(address(0))` returns sDGNRS -> `_claimCoinflipsAmount(sDGNRS, remainingBurnie, true)` -> `_claimCoinflipsInternal` (iterates storage, computes claimable) -> `burnie.mintForCoinflip(sDGNRS, toClaim)`.

`mintForCoinflip` is a standard ERC20 mint in BurnieCoin -- updates `balanceOf[sDGNRS]` and `totalSupply`, emits Transfer. No ERC-777 hooks. No callback into sDGNRS.

**Verify BURNIE payout accounting:** The `burnieOut` at step 3 is calculated as `(totalBurnie * amount) / supplyBefore` where `totalBurnie = burnieBal + claimableBurnie`. The function first pays from `burnieBal` (step 6), then claims the remainder from coinflip (step 7). After step 7, sDGNRS has `burnieBal - payBal + remainingBurnie` BURNIE, and step 8 sends `remainingBurnie` to the player. The total BURNIE sent is `payBal + remainingBurnie = burnieOut`. This matches the calculated entitlement. **No excess BURNIE relative to what was promised.**

**Edge case:** If `claimableBurnie` at step 2 (view call) differs from the actual claimable at step 7 (state-changing call) due to a concurrent transaction, the claim at step 7 could return less than `remainingBurnie`. In this case, `coin.transfer(player, remainingBurnie)` at step 8 would fail because sDGNRS doesn't hold enough BURNIE. The entire transaction reverts. No fund loss, but the burn is blocked. This is a benign edge case -- the user retries and the preview recalculates.

**Reentrancy risk:** `mintForCoinflip` mints BURNIE to sDGNRS without any callback. `coin.transfer` is standard ERC20 (BurnieCoin has no hooks). **SAFE.**

**Verdict: SAFE.** No callbacks. BURNIE accounting is correct. Pre-calculated `burnieOut` matches actual total payout.

---

### Call Chain 3: DGNRS.unwrapTo() -> sDGNRS.wrapperTransferTo()

**Complete call sequence:**

| Step | Location | Action | State Change |
|------|----------|--------|--------------|
| 1 | DegenerusStonk.sol:140 | `msg.sender != ContractAddresses.CREATOR` check | Auth gate |
| 2 | DegenerusStonk.sol:141 | `recipient == address(0)` check | Input validation |
| 3 | DegenerusStonk.sol:142 | `_burn(msg.sender, amount)` | DGNRS.balanceOf[CREATOR] -= amount; DGNRS.totalSupply -= amount |
| 4 | DegenerusStonk.sol:143 | `stonk.wrapperTransferTo(recipient, amount)` | **EXTERNAL CALL** to sDGNRS |
| 5 | StakedDegenerusStonk.sol:243 | `msg.sender != ContractAddresses.DGNRS` check | Auth gate -- DGNRS is caller |
| 6 | StakedDegenerusStonk.sol:244 | `to == address(0)` check | Input validation |
| 7 | StakedDegenerusStonk.sol:245-246 | `bal = balanceOf[DGNRS]; if (amount > bal) revert` | Balance check |
| 8 | StakedDegenerusStonk.sol:248-249 | `balanceOf[DGNRS] -= amount; balanceOf[to] += amount` | **STATE CHANGE**: sDGNRS moved from DGNRS to recipient |
| 9 | StakedDegenerusStonk.sol:251 | `emit Transfer(DGNRS, to, amount)` | Event |

**CEI compliance:** DGNRS._burn() commits state (step 3) before the external call to sDGNRS (step 4). Inside sDGNRS, all checks (steps 5-7) precede state changes (step 8). No external calls after state changes. **PASS.**

**Supply invariant preservation:**
- Before: `sDGNRS.balanceOf[DGNRS] = X`, `DGNRS.totalSupply = Y`, invariant `X >= Y`
- After step 3: `DGNRS.totalSupply = Y - amount`
- After step 8: `sDGNRS.balanceOf[DGNRS] = X - amount`
- After: `(X - amount) >= (Y - amount)` iff `X >= Y` -- invariant preserved. **CORRECT.**

**Reentrancy risk:** No external calls after step 8. The `wrapperTransferTo` function has no callbacks. **SAFE.**

**Verdict: SAFE.** Simple two-step operation with correct CEI ordering. Supply invariant preserved. No external callbacks.

---

### Call Chain 4: game -> sDGNRS.transferFromPool() -> (leaf call)

**Complete call sequence:**

| Step | Location | Action | State Change |
|------|----------|--------|--------------|
| 1 | StakedDegenerusStonk.sol:315 | `onlyGame` modifier check | Auth gate |
| 2 | StakedDegenerusStonk.sol:316 | `if (amount == 0) return 0` | Zero-amount guard |
| 3 | StakedDegenerusStonk.sol:317 | `if (to == address(0)) revert ZeroAddress()` | Zero-address guard |
| 4 | StakedDegenerusStonk.sol:318-323 | Read pool balance, cap amount to available | Balance check |
| 5 | StakedDegenerusStonk.sol:324-328 | `poolBalances[idx] -= amount; balanceOf[this] -= amount; balanceOf[to] += amount` | **STATE CHANGE**: tokens moved from pool to recipient |
| 6 | StakedDegenerusStonk.sol:329-331 | Emit Transfer and PoolTransfer events, return `amount` | Events + return |

**CEI compliance:** This is a leaf call -- no external interactions at all. All state changes are internal to sDGNRS. The function is called by the game contract via delegatecall, and the `onlyGame` modifier ensures no unauthorized caller. **PASS.**

**Reentrancy risk:** No external calls. **SAFE.**

**Verdict: SAFE.** Pure internal state manipulation. No cross-contract interaction from this function.

---

### Call Chain 5: game -> sDGNRS.burnRemainingPools()

**Complete call sequence:**

| Step | Location | Action | State Change |
|------|----------|--------|--------------|
| 1 | StakedDegenerusStonk.sol:359 | `onlyGame` modifier check | Auth gate |
| 2 | StakedDegenerusStonk.sol:360 | `bal = balanceOf[address(this)]` | Read contract's own balance |
| 3 | StakedDegenerusStonk.sol:361 | `if (bal == 0) return` | Zero-balance guard |
| 4 | StakedDegenerusStonk.sol:363-364 | `balanceOf[address(this)] = 0; totalSupply -= bal` | **STATE CHANGE**: all pool tokens burned |
| 5 | StakedDegenerusStonk.sol:366 | `emit Transfer(address(this), address(0), bal)` | Event |

**CEI compliance:** No external calls at all. **PASS.**

**State impact on burn value:**
- Before: `totalSupply = holder_total + pool_total`. Burn value per token = `reserves / totalSupply`
- After: `totalSupply = holder_total`. Burn value per token = `reserves / holder_total`
- Since `reserves` did not decrease, each remaining token is now backed by MORE reserves.
- This is **intentional by design** -- undistributed pool tokens are removed so that holders get proportionally more.

**Stale poolBalances issue (DELTA-I-01):** After `burnRemainingPools`, the `poolBalances[]` array retains stale nonzero values, but `balanceOf[address(this)] = 0`. If `transferFromPool` were called after this, the unchecked `balanceOf[address(this)] -= amount` at StakedDegenerusStonk.sol:326 would underflow. This is prevented because `burnRemainingPools` is only called during game over (DegenerusGameGameOverModule.sol:163), after which `gameOver = true` blocks all game entry points that call `transferFromPool`.

**Reentrancy risk:** No external calls. **SAFE.**

**Verdict: SAFE.** Leaf call with no external interactions. State changes increase per-token burn value as designed. DELTA-I-01 acknowledged.

---

### Cross-Chain State Consistency Summary

**Question:** Are there any scenarios where a state read at step N becomes stale due to an external call at step N+1?

**Analysis of all read-then-call patterns in sDGNRS.burn():**

| Read | Line | External Call After | Line | Stale? | Mitigation |
|------|------|-------------------|------|--------|------------|
| `ethBal = address(this).balance` | 387 | `game.claimWinnings()` | 405 | YES -- claimWinnings sends ETH to sDGNRS | **RE-READ at line 406**: `ethBal = address(this).balance` |
| `stethBal = steth.balanceOf(this)` | 388 | `game.claimWinnings()` | 405 | YES -- stETH fallback can deposit stETH (via DegenerusGame.sol:1954-1956) | **RE-READ at line 407**: `stethBal = steth.balanceOf(address(this))` |
| `claimableEth = _claimableWinnings()` | 389 | `game.claimWinnings()` | 405 | YES -- claimable goes to sentinel (1) after claim | NOT re-read, but not needed: claimableEth was pre-counted in totalMoney, now converted to actual ETH+stETH |
| `burnieBal = coin.balanceOf(this)` | 393 | `coinflip.claimCoinflips()` | 426 | YES -- claimCoinflips mints BURNIE to sDGNRS | Used only at line 420 to determine pre-claim payable amount; remaining claimed separately |
| `claimableBurnie = previewClaimCoinflips()` | 394 | `coinflip.claimCoinflips()` | 426 | YES -- claimable changes after claim | Used only for burnieOut calculation before claim; actual claim amount is `remainingBurnie` (pre-calculated) |
| `supplyBefore = totalSupply` | 385 | None before state change | N/A | NO -- totalSupply is set from local read, then immediately used for calculation | N/A |

**Key finding:** All stale reads that are material to payout calculation are either RE-READ after the stale-causing call (ethBal at line 406, stethBal at line 407) or pre-counted into the aggregate value (claimableEth included in totalMoney). No stale read produces an exploitable accounting discrepancy.

**Inter-transaction consistency:** Two burns in the same block are processed sequentially by the EVM. The second burn reads post-state from the first burn (reduced totalSupply, reduced reserves). There is no parallel read of stale state between transactions. Each burn gets its proportionally correct share.

**Overall composition verdict: SAFE.** All 5 call chains verified. No exploitable state inconsistency. The mid-burn balance changes from claimWinnings (both ETH and stETH paths) are correctly handled by re-reading balances after the call. CEI pattern holds across all chains.

