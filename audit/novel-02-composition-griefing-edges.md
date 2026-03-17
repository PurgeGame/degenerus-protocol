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

---

## NOVEL-03: Griefing Vector Enumeration

This section enumerates all griefing vectors on the new sDGNRS/DGNRS entry points. For each vector: description, attack cost, victim impact, duration, verdict, and mitigation status.

### Griefing Vector 1: Dust Burn Spam

**Description:** An attacker calls `DGNRS.burn(1)` or `sDGNRS.burn(1)` repeatedly with the minimum non-zero amount (1 wei of tokens), attempting to waste reserves or bloat state.

**Attack cost:**
- Gas per DGNRS.burn(1) tx: ~150,000-250,000 gas (DGNRS._burn + sDGNRS.burn with up to 5 external calls)
- At 30 gwei base fee: ~0.0045-0.0075 ETH per tx (~$15-25 at ETH=$3,000)
- 1,000 spam burns: ~$15,000-25,000

**Victim impact:**
- Each dust burn reduces totalSupply by 1 wei, claims `(totalMoney * 1) / supplyBefore` reserves
- With supplyBefore ~1T * 1e18 = 1e30, the claim is `totalMoney / 1e30` -- effectively 0 for any realistic reserve amount (even 1B ETH = 1e27 wei yields 0 due to integer division)
- No state bloat: same storage slots updated (balanceOf, totalSupply -- O(1) state changes per burn)
- No impact on other users' burn values -- totalSupply decreased by dust, reserves decreased by 0

**Code path:** StakedDegenerusStonk.sol:384 -- `if (amount == 0 || amount > bal) revert Insufficient()`. burn(0) reverts. burn(1) proceeds but claims effectively nothing due to integer division rounding down to zero.

**Duration:** Temporary (only during active spam). No lasting state damage.

**Verdict: NEGLIGIBLE.** Attacker wastes $15,000+ in gas for zero impact on other users. Reserves unchanged. State not bloated.

**Mitigation status:** Inherent -- integer division rounds dust claims to 0. No fix needed.

---

### Griefing Vector 2: Gas Limit Attack on Burn

**Description:** An attacker calls `DGNRS.burn()` with carefully calculated gas to execute the `DGNRS._burn()` state change but run out of gas during the sDGNRS.burn() call chain, leaving DGNRS balances reduced without the corresponding sDGNRS burn.

**Attack cost:** Minimal gas fee for a reverting transaction.

**Code path:**
- DegenerusStonk.sol:154: `_burn(msg.sender, amount)` -- DGNRS state changes
- DegenerusStonk.sol:156: `stonk.burn(amount)` -- if gas runs out here, EVM reverts ENTIRE transaction

**Victim impact:** NONE. The EVM processes transactions atomically. If gas runs out at ANY point during the transaction, ALL state changes revert -- including the DGNRS._burn() at line 154. There is no partial execution of a transaction.

**Duration:** N/A -- the attack cannot succeed.

**Verdict: BLOCKED.** EVM atomicity prevents partial burn execution. Out-of-gas reverts all state changes. No cross-contract inconsistency possible.

**Mitigation status:** Inherent -- EVM transaction atomicity.

---

### Griefing Vector 3: Block Stuffing Before Burns

**Description:** An attacker fills blocks with high-gas transactions to delay other users' burns (e.g., before a known `gameOver` event to prevent burning at pre-gameOver prices, or before a stETH rebase).

**Attack cost:**
- Full block gas limit (30M gas) at 30 gwei = 0.9 ETH per block (~$2,700)
- Sustaining for N blocks: $2,700 * N. For 100 blocks (~20 minutes): $270,000

**Victim impact:**
- Temporary delay of burn execution
- Does NOT change burn payout values -- reserves and totalSupply remain unchanged while blocks are stuffed
- After block stuffing ends, delayed burns execute at current (not stale) proportional values

**Duration:** Only during active block stuffing. No lasting impact.

**Verdict: NEGLIGIBLE.** Cost vastly exceeds any conceivable benefit. Standard blockchain DoS vector not specific to DGNRS. Burns are not time-sensitive in a way that makes delay profitable for the attacker.

**Mitigation status:** Not addressable at the contract level -- this is a network-layer concern.

---

### Griefing Vector 4: Approval Front-Running (ERC20 Race Condition)

**Description:** An attacker monitors pending `DGNRS.approve()` transactions, front-runs with `transferFrom()` to spend the old allowance, then the victim's `approve()` sets the new allowance which the attacker can also spend.

**Attack cost:** Gas for one `transferFrom()` (~50,000 gas) + MEV priority fee.

**Code path:**
- DegenerusStonk.sol:128-132: `approve(spender, amount)` -- directly sets `allowance[msg.sender][spender] = amount`
- DegenerusStonk.sol:113-122: `transferFrom(from, to, amount)` -- checks and decrements allowance
- Line 115: `if (allowed != type(uint256).max)` -- max uint256 approvals are not decremented (infinite approval pattern)

**Victim impact:** Only affects users who change a non-zero allowance to a different non-zero amount (the standard ERC20 approve race condition). This is not specific to DGNRS.

**Duration:** Single event per affected approve transaction.

**Verdict: KNOWN.** This is the standard ERC20 approval race condition documented across the industry. DGNRS follows the standard ERC20 pattern (no increaseAllowance/decreaseAllowance helpers). Already documented under DELTA-L-01 context.

**Mitigation status:** Acknowledged as standard ERC20 behavior. Users should set approval to 0 before changing to a new value, or use the infinite approval pattern (type(uint256).max).

---

### Griefing Vector 5: Pool Exhaustion Racing

**Description:** An attacker front-runs legitimate pool transfers by triggering their own pool claims first, exhausting the pool balance before intended recipients.

**Attack cost:** Depends on what triggers pool transfers.

**Code path:**
- StakedDegenerusStonk.sol:315: `transferFromPool` has `onlyGame` modifier
- StakedDegenerusStonk.sol:340: `transferBetweenPools` has `onlyGame` modifier
- All pool operations are restricted to the game contract

**Victim impact:** NONE. Users cannot directly call `transferFromPool`. All pool transfers are initiated by the game contract during specific game events (whale pass purchases, lootbox wins, jackpot distributions, etc.). The game contract's own logic determines who gets pool tokens and when. A user cannot trigger a pool transfer for themselves unless they meet the game's qualification criteria.

**Duration:** N/A -- the attack vector does not exist.

**Verdict: BLOCKED.** `onlyGame` restriction prevents public access to pool operations. The game contract's internal logic handles all distribution decisions.

**Mitigation status:** Inherent -- access control prevents the attack.

---

### Griefing Vector 6: Forced ETH Donation to Inflate/Deflate Burn Values

**Description:** An attacker force-sends ETH to the sDGNRS contract via `selfdestruct` (or post-Cancun, create+selfdestruct in the same transaction per EIP-6780) to inflate `address(this).balance` and thus inflate the per-token burn value.

**Attack cost:** The ETH amount force-sent + gas for the factory contract deployment and selfdestruct (~100,000 gas).

**Code path:**
- StakedDegenerusStonk.sol:282: `receive() external payable onlyGame` -- blocks direct ETH sends from non-game addresses
- BUT: `selfdestruct` bypasses `receive()` and forces ETH into the contract regardless of code at the target address
- StakedDegenerusStonk.sol:387: `ethBal = address(this).balance` -- includes force-sent ETH
- StakedDegenerusStonk.sol:390-391: `totalMoney = ethBal + stethBal + claimableEth; totalValueOwed = (totalMoney * amount) / supplyBefore` -- payout includes force-sent ETH

**Victim impact:** The force-sent ETH increases `totalMoney` for ALL burners proportionally. If the attacker holds X% of the supply, they can burn to reclaim X% of the force-sent ETH. They lose (1-X%) of the donation. This is a NET LOSS for the attacker unless they hold 100% of the supply.

**Economic analysis:**
- Attacker holds 10% of supply, force-sends 10 ETH
- Attacker burns all their tokens, claims 10% of the extra 10 ETH = 1 ETH
- Net loss: 10 - 1 = 9 ETH donated to other holders
- This is a pure donation, not an exploit

**Duration:** Permanent -- the forced ETH cannot be removed except through burns.

**Verdict: NEGLIGIBLE.** Force-sending ETH is a donation to all holders proportionally. The attacker always loses (1 - their_share_percentage) of the donation. Not profitable for any attacker holding less than 100% of supply.

**Mitigation status:** Inherent -- proportional redemption formula makes donation attacks unprofitable. No fix needed.

---

### Griefing Summary Table

| # | Vector | Attack Cost | Victim Impact | Duration | Verdict |
|---|--------|-------------|---------------|----------|---------|
| 1 | Dust burn spam | ~$15k+ per 1k burns | None (claims round to 0) | Temporary | NEGLIGIBLE |
| 2 | Gas limit attack on burn | Minimal (reverts) | None (EVM atomicity) | N/A | BLOCKED |
| 3 | Block stuffing before burns | ~$2,700/block | Temporary delay only | Active spam only | NEGLIGIBLE |
| 4 | Approval front-running | Gas + MEV fee | Standard ERC20 race | Single event | KNOWN |
| 5 | Pool exhaustion racing | N/A | None (onlyGame) | N/A | BLOCKED |
| 6 | Forced ETH donation | ETH sent (lost) | Positive (donation) | Permanent | NEGLIGIBLE |

**Summary:** No exploitable griefing vectors found. Two vectors are completely blocked (gas limit, pool racing). Three are economically negligible (dust spam, block stuffing, forced donation). One is a known ERC20 limitation (approval race). No new griefing surface introduced by the sDGNRS/DGNRS architecture beyond standard ERC20 patterns.

---

## NOVEL-04: Edge Case Matrix

This section provides a complete edge case matrix for all public/external functions in sDGNRS and DGNRS, covering zero amounts, max uint256, dust (1 wei), amount > balance, amount == totalSupply, and stETH rounding boundaries. Existing test coverage from Phase 20-03 (DGNRSLiquid.test.js) is cross-referenced.

### Edge Case Matrix

| # | Function | Input | Expected Behavior | Code Path | Tested? |
|---|----------|-------|-------------------|-----------|---------|
| 1 | `sDGNRS.burn(0)` | amount = 0 | Revert `Insufficient` | StakedDegenerusStonk.sol:384 -- `if (amount == 0 \|\| amount > bal) revert Insufficient()` | YES (DGNRSLiquid.test.js:254 -- "reverts on zero amount") |
| 2 | `sDGNRS.burn(1)` | amount = 1 wei | Execute, claim 0 reserves (rounding to 0 for dust), burn 1 wei of supply | StakedDegenerusStonk.sol:391 -- `totalValueOwed = (totalMoney * 1) / supplyBefore` rounds to 0 for any supply > totalMoney | Partial (burn tests exist but no explicit 1-wei test) |
| 3 | `sDGNRS.burn(totalSupply)` | amount = all remaining tokens | Last burn, claims 100% of reserves. `totalValueOwed = totalMoney` (exact). No division by zero because `supplyBefore > 0` when entering burn (checked at line 384). | StakedDegenerusStonk.sol:391 -- `(totalMoney * totalSupply) / totalSupply = totalMoney`. After burn, `totalSupply = 0`. | NO (not tested -- requires all other holders to have burned first) |
| 4 | `sDGNRS.burn(balance + 1)` | amount > caller's balance | Revert `Insufficient` | StakedDegenerusStonk.sol:384 -- `amount > bal` triggers revert | YES (DGNRSLiquid.test.js:261 -- "reverts when amount exceeds balance") |
| 5 | `DGNRS.burn(0)` | amount = 0 | Revert `Insufficient` at DGNRS level | DegenerusStonk.sol:204 -- `_burn` checks `if (amount == 0 \|\| amount > bal) revert Insufficient()`. DGNRS reverts before sDGNRS is ever called. | YES (DGNRSLiquid.test.js:254 -- "reverts on zero amount") |
| 6 | `DGNRS.burn(1)` | amount = 1 wei | Burns 1 wei of DGNRS, triggers sDGNRS.burn(1) which claims dust (0 reserves). DGNRS forwards 0 ETH, 0 stETH, 0 BURNIE. | DegenerusStonk.sol:154 -- `_burn(msg.sender, 1)` succeeds; line 156: `stonk.burn(1)` -> sDGNRS processes dust burn | Partial (burn tests exist but no explicit 1-wei burn-through test) |
| 7 | `DGNRS.transfer(address(0), amount)` | to = zero address | Revert `ZeroAddress` | DegenerusStonk.sol:191 -- `if (to == address(0)) revert ZeroAddress()` | YES (implicit via transfer tests) |
| 8 | `DGNRS.transfer(DGNRS_address, amount)` | to = DGNRS contract itself | Tokens permanently locked in DGNRS contract. No recovery mechanism. | DegenerusStonk.sol:190-198 -- `_transfer` does not check `to != address(this)`. Tokens are debited from sender and credited to the DGNRS contract's own balance. | YES (DGNRSLiquid.test.js:164 -- "transfer to self does not change balance (DELTA-L-01)") |
| 9 | `DGNRS.approve(addr, type(uint256).max)` | Infinite allowance | Sets max uint256 approval. `transferFrom` at line 115 skips allowance decrement for `type(uint256).max`. | DegenerusStonk.sol:128-132 -- `allowance[msg.sender][spender] = amount` sets to max. Line 115: `if (allowed != type(uint256).max)` skips decrement. | Partial (approve test exists at DGNRSLiquid.test.js:150 but not explicit max-uint test) |
| 10 | `sDGNRS.burn(amount)` where stETH rounding causes `stethOut > stethBal` | stETH 1-2 wei rounding | Revert `Insufficient` | StakedDegenerusStonk.sol:415 -- `if (stethOut > stethBal) revert Insufficient()` | NO (requires specific stETH balance setup with rounding) |
| 11 | `sDGNRS.burn(amount)` with zero reserves | All reserves are 0 | `totalValueOwed = 0`, `burnieOut = 0`. No transfers executed. Balance and supply reduced. Burn event emitted. | StakedDegenerusStonk.sol:391 -- `totalMoney = 0 + 0 + 0 = 0; totalValueOwed = (0 * amount) / supplyBefore = 0`. Lines 410-437: all conditional transfers skipped. | Partial (burn tests exist but reserves are sometimes 0 in base tests) |
| 12 | `DGNRS.transfer(to, type(uint256).max)` | Max uint256 transfer | Revert `Insufficient` (no address holds max uint256 tokens) | DegenerusStonk.sol:193 -- `if (amount > bal) revert Insufficient()`. Max supply is 200B * 1e18 = 2e29, far below type(uint256).max = ~1.16e77. | NO (not tested -- trivially safe) |
| 13 | `sDGNRS.depositSteth(0)` | Zero stETH deposit | `steth.transferFrom(msg.sender, this, 0)` -- executes as no-op. StakedDegenerusStonk.sol:292 -- Lido stETH transferFrom(0) returns true. Deposit event emitted with amount 0. | StakedDegenerusStonk.sol:291-293 -- onlyGame, then transferFrom call with 0. | YES (confirmed as no-op in Phase 20-03) |
| 14 | `sDGNRS.transferFromPool(pool, to, 0)` | Zero amount pool transfer | Returns 0 immediately | StakedDegenerusStonk.sol:316 -- `if (amount == 0) return 0` | NO (onlyGame, not directly testable by users) |
| 15 | `sDGNRS.wrapperTransferTo(to, 0)` | Zero amount wrapper transfer | Succeeds with 0 transfer (no explicit zero check) | StakedDegenerusStonk.sol:242-251 -- no `amount == 0` check. `bal - 0 = bal`, `balanceOf[to] += 0`. Transfer event emitted with amount 0. | NO (only callable by DGNRS contract) |

### stETH Rounding Revert Scenario (Edge Case #10) -- Detailed Analysis

**Background:** Lido stETH uses a shares-based accounting system. `balanceOf()` returns `(shares * totalPooledEther) / totalShares`, which introduces 1-2 wei rounding errors on every balance read and transfer. This is documented in the Lido integration guide and in the project's existing I-20 / XCON-06 finding.

**The revert scenario:**

The revert at StakedDegenerusStonk.sol:415 (`if (stethOut > stethBal) revert Insufficient()`) can trigger when:

1. `totalValueOwed > ethBal` (the burn requires some stETH payout)
2. `stethOut = totalValueOwed - ethOut` (line 414)
3. The calculated `stethOut` exceeds `stethBal` by 1-2 wei due to rounding

**When does this happen?**

**Scenario A: Last burner (100% of remaining supply)**
- `totalValueOwed = totalMoney = ethBal + stethBal + claimableEth` (exact equality at 100%)
- After claimWinnings (if triggered): `ethBal` captures ETH + claimed ETH, `stethBal` captures stETH (possibly with 1-2 wei rounding loss from depositSteth)
- `stethOut = totalMoney - ethBal_post`
- If `totalMoney` was computed using pre-claim `stethBal` that was 1 wei higher than post-claim `stethBal` (due to rebase rounding between the read at line 388 and the actual balance at line 407), then `stethOut` could exceed actual `stethBal` by 1 wei
- **This scenario CAN trigger the revert** -- but only if claimWinnings deposits stETH via the fallback path AND the share rounding causes a 1-2 wei discrepancy

**Scenario B: Normal burn (< 100% of supply)**
- `totalValueOwed = (totalMoney * amount) / supplyBefore` -- integer division rounds DOWN
- `stethOut = totalValueOwed - ethOut` -- also subject to the rounding from step above
- The downward rounding in the proportional calculation provides a natural buffer: the calculated `stethOut` is slightly LESS than the true proportional share
- For this to trigger the revert, the rounding error from stETH transfers would need to exceed the integer division buffer
- With 18-decimal precision and supply in the range of 1e29-1e30, the integer division rounding provides many orders of magnitude of buffer
- **This scenario is practically impossible** for any burn amount < 100% of supply

**Scenario C: stETH rebase between line 388 and line 407**
- If a Lido rebase occurs between the initial `stethBal` read (line 388, used in `totalMoney`) and the re-read (line 407), `stethBal` could either increase or decrease
- Lido rebases occur once daily (~12:00 UTC) in a single transaction
- The sDGNRS.burn() transaction is atomic -- a rebase cannot occur mid-transaction
- The re-read at line 407 is in the same transaction as the read at line 388
- **This scenario CANNOT trigger** -- no rebase within a single transaction

**Conditions for the revert:**
1. Must be the last (or near-last) burner claiming nearly 100% of stETH reserves
2. The claimWinnings call must trigger the stETH fallback path (game has insufficient ETH)
3. The stETH `depositSteth()` via `transferFrom` must lose 1-2 wei to share rounding
4. The proportional calculation must not provide sufficient integer division buffer

**Frequency:** Extremely rare. Only the very last burner in a specific game state (ETH-depleted game forcing stETH fallback) could encounter this. The 1-2 wei error is the maximum per Lido documentation.

**Impact:** The burn reverts, but no state is corrupted (EVM atomicity). The user can retry with `amount - 1` to leave 1 wei of sDGNRS unburned, which provides sufficient rounding buffer. Alternatively, the user can wait for any ETH inflow (game advance, direct ETH deposit) that shifts the payout to pure ETH, bypassing the stETH path entirely.

**Mitigation status:** Acknowledged. The revert is a conservative safety check -- it prevents paying out more stETH than is available. The 1-2 wei stuck dust is economically negligible. No code change recommended.

---

### Existing Test Coverage Cross-Reference

The following tests from `test/unit/DGNRSLiquid.test.js` (Phase 20-03, 80 passing tests) cover edge cases in the matrix above:

| Edge Case | Test Location | Test Name | Status |
|-----------|--------------|-----------|--------|
| #1: sDGNRS.burn(0) | DGNRSLiquid.test.js:254 | "reverts on zero amount" | COVERED |
| #4: sDGNRS.burn(bal+1) | DGNRSLiquid.test.js:261 | "reverts when amount exceeds balance" | COVERED |
| #5: DGNRS.burn(0) | DGNRSLiquid.test.js:254 | "reverts on zero amount" | COVERED |
| #7: DGNRS.transfer(0x0) | DGNRSLiquid.test.js (implicit) | Transfer tests check ZeroAddress revert | COVERED |
| #8: DGNRS.transfer(self) | DGNRSLiquid.test.js:164 | "transfer to self does not change balance (DELTA-L-01)" | COVERED |
| #8b: DGNRS.transferFrom(self) | DGNRSLiquid.test.js:179 | "transferFrom to self does not change balance" | COVERED |
| #13: depositSteth(0) | Phase 20-03 verification | "depositSteth(0) confirmed as no-op" | COVERED |

**Coverage gaps identified:**
- Edge Case #2 (sDGNRS.burn(1) dust): Not explicitly tested. Behavior is trivially correct (integer division rounds to 0).
- Edge Case #3 (burn entire supply): Not tested. Requires complex fixture setup where all other holders have burned first.
- Edge Case #6 (DGNRS.burn(1) through): Not explicitly tested. Trivially correct (forwards 0 reserves).
- Edge Case #9 (max uint256 approve): Not explicitly tested. Standard ERC20 behavior.
- Edge Case #10 (stETH rounding revert): Not tested. Requires real Lido stETH with share rounding, not achievable with mock stETH in unit tests.
- Edge Case #12 (max uint256 transfer): Not tested. Trivially reverts (no address holds that many tokens).

All untested edge cases are either trivially correct (provable by code inspection) or require specific environmental conditions not reproducible in unit tests (Lido stETH share rounding). No high-risk coverage gaps identified.

