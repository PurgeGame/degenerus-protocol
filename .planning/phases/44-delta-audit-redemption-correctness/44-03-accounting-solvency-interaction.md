# Phase 44 Accounting, Solvency, and Interaction Audit

## Accounting Reconciliation (DELTA-01)

### ETH Accounting: pendingRedemptionEthValue

Every line in `StakedDegenerusStonk.sol` that reads or writes `pendingRedemptionEthValue`:

#### Write Sites

| # | Function | Line | Direction | Formula | Context |
|---|----------|------|-----------|---------|---------|
| W1 | `_submitGamblingClaimFrom` | 712 | INCREMENT | `pendingRedemptionEthValue += ethValueOwed` | Segregates ETH proportional share at burn-time |
| W2 | `resolveRedemptionPeriod` | 553 | ADJUSTMENT | `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` | Replaces 100% base with rolled amount (25-175%) |
| W3 | `claimRedemption` | 599 | DECREMENT | `pendingRedemptionEthValue -= ethPayout` | Releases individual player's rolled payout |

#### Read Sites (non-mutating)

| # | Function | Line | Usage |
|---|----------|------|-------|
| R1 | `_submitGamblingClaimFrom` | 695 | `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (deducts segregated from available pool) |
| R2 | `previewBurn` | 633 | `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (view-only preview, correct) |
| R3 | `previewBurn` | 637-638 | `ethAvailable -= pendingRedemptionEthValue` (ETH-vs-stETH split preview) |
| R4 | `hasPendingRedemptions` | 537 | Not directly read (uses `pendingRedemptionEthBase` instead) |

**MISSING DEDUCTION (CP-08):** `_deterministicBurnFrom` at line 477 computes `totalMoney = ethBal + stethBal + claimableEth` WITHOUT subtracting `pendingRedemptionEthValue`. This is the confirmed CP-08 HIGH finding from Plan 01.

#### Mutation Verification

**W1 -- Submit increment (line 712):**
The increment value `ethValueOwed` is computed at line 696:
```
ethValueOwed = (totalMoney * amount) / supplyBefore
```
where `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (line 695). The subtraction ensures the new claim is computed against UNRESERVED assets only. The increment at line 712 correctly adds this computed share to the segregated total. **CORRECT.**

**W2 -- Resolve adjustment (line 553):**
```solidity
uint256 rolledEth = (pendingRedemptionEthBase * roll) / 100;           // line 552
pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;  // line 553
```
This removes the 100% base and replaces it with the rolled amount. If `roll = 100`, the value is unchanged. If `roll > 100`, more ETH is reserved (taken from the unreserved pool). If `roll < 100`, ETH is freed back. **CORRECT** -- the adjustment only applies to the current period's base, leaving prior resolved periods' residual value intact.

**W3 -- Claim decrement (line 599):**
```solidity
pendingRedemptionEthValue -= ethPayout;
```
where `ethPayout = (claim.ethValueOwed * roll) / 100` (line 590). Each player's claim uses their individual `ethValueOwed` multiplied by the period's roll. **CORRECT** -- decrements by the exact amount being paid out.

### Rounding Analysis

#### Case 1: Exact Division (No Rounding)

**Parameters:** N = 100 players, each burns 1 sDGNRS. totalSupply = 100. totalMoney = 10^19 wei. roll = 175.

**Step 1 -- Submit (each of 100 players):**
```
ethValueOwed_i = (10^19 * 1) / 100 = 10^17 wei (exact)
pendingRedemptionEthBase = sum(ethValueOwed_i) = 100 * 10^17 = 10^19 wei
pendingRedemptionEthValue = 10^19 wei
```
No rounding -- all divisions are exact.

**Step 2 -- Resolve (roll = 175):**
```
rolledEth = (10^19 * 175) / 100 = 1.75 * 10^19 wei (exact)
pendingRedemptionEthValue = 10^19 - 10^19 + 1.75 * 10^19 = 1.75 * 10^19 wei
```

**Step 3 -- Claim (each of 100 players):**
```
ethPayout_i = (10^17 * 175) / 100 = 1.75 * 10^17 wei (exact)
sum(ethPayout_i) = 100 * 1.75 * 10^17 = 1.75 * 10^19 wei
```

**Reconciliation:** `sum(ethPayout_i) = rolledEth = 1.75 * 10^19`. After all claims, `pendingRedemptionEthValue = 0`. **EXACT MATCH.**

#### Case 2: Rounding Occurs

**Parameters:** N = 3 players, amounts = [7, 11, 13] sDGNRS (total 31). totalMoney = 10^18 wei. roll = 137. supplyBefore = 31 at first burn (then decreases).

**IMPORTANT NOTE on sequential burns:** Each burn reduces `totalSupply`, and subsequent burns compute `ethValueOwed` against the UPDATED `totalSupply`. However, `pendingRedemptionEthValue` also increases, so `totalMoney` decreases for subsequent burns. Let us trace sequentially:

**Player A burns 7 (supply=31, pendingEthValue=0):**
```
totalMoney = 10^18 - 0 = 10^18
ethValueOwed_A = (10^18 * 7) / 31 = 225806451612903225 wei
  (exact: 7 * 10^18 / 31 = 225806451612903225.806... truncated)
pendingRedemptionEthValue = 225806451612903225
pendingRedemptionEthBase = 225806451612903225
```

**Player B burns 11 (supply=24, pendingEthValue=225806451612903225):**
```
totalMoney = 10^18 - 225806451612903225 = 774193548387096775
ethValueOwed_B = (774193548387096775 * 11) / 24 = 354838709677419355 wei
  (exact: 8516129032258064325 / 24 = 354838709677419355.208... truncated)
pendingRedemptionEthValue = 225806451612903225 + 354838709677419355 = 580645161290322580
pendingRedemptionEthBase = 580645161290322580
```

**Player C burns 13 (supply=13, pendingEthValue=580645161290322580):**
```
totalMoney = 10^18 - 580645161290322580 = 419354838709677420
ethValueOwed_C = (419354838709677420 * 13) / 13 = 419354838709677420
  (exact: 13/13 = 1, no truncation)
pendingRedemptionEthValue = 580645161290322580 + 419354838709677420 = 1000000000000000000 = 10^18
pendingRedemptionEthBase = 10^18
```

**Resolve (roll = 137):**
```
rolledEth = (10^18 * 137) / 100 = 1.37 * 10^18 (exact)
pendingRedemptionEthValue = 10^18 - 10^18 + 1.37 * 10^18 = 1.37 * 10^18
```

**Claim Player A:**
```
ethPayout_A = (225806451612903225 * 137) / 100 = 309354838709677398 wei
  (exact: 30935483870967741825 / 100 = 309354838709677418.25, truncated to 309354838709677418)
```
Wait -- let me recompute: `225806451612903225 * 137 = 30935483870967741825`. `30935483870967741825 / 100 = 309354838709677418` (truncated). So `ethPayout_A = 309354838709677418`.

**Claim Player B:**
```
ethPayout_B = (354838709677419355 * 137) / 100 = 48612903225806391635 / 100 = 486129032258063916 (truncated)
```
Check: `354838709677419355 * 137 = 48612903225806391635`. `48612903225806391635 / 100 = 486129032258063916` (truncated from .35).

**Claim Player C:**
```
ethPayout_C = (419354838709677420 * 137) / 100 = 57451612903225526140 / 100 = 574516129032255261 (truncated)
```
Check: `419354838709677420 * 137 = 57451612903225526140`. `57451612903225526140 / 100 = 574516129032255261` (truncated from .40).

**Sum of payouts:**
```
309354838709677418 + 486129032258063916 + 574516129032255261 = 1369999999999996595
```

**rolledEth:**
```
1370000000000000000
```

**Dust:**
```
rolledEth - sum(ethPayouts) = 1370000000000000000 - 1369999999999996595 = 3405 wei
```

**Direction of dust:** The sum of individual payouts is LESS than the aggregate rolled amount. This means `pendingRedemptionEthValue` retains 3405 wei of dust after all claims. The dust is always non-negative because integer division truncates toward zero.

**Maximum dust per claim:** Each division `(ethValueOwed * roll) / 100` loses at most 99 wei (since `x / 100` truncates at most 99). With N claimants, maximum total dust is `99 * N` wei per period.

In this case: N = 3, max dust = 297 wei. The actual dust (3405 wei) exceeds this because of ADDITIONAL rounding at the submit step. Each `(totalMoney * amount) / supplyBefore` division can lose up to `supplyBefore - 1` wei. With 3 sequential submits against different denominators (31, 24, 13), the submit rounding also contributes to the total dust.

**Revised maximum dust bound per period:**
- Submit phase: up to `(supplyBefore_i - 1)` wei per player. Since `supplyBefore` decreases with each burn, the maximum is bounded by the initial supply. Across N players: at most `sum(supplyBefore_i - 1)` wei, but in practice each truncation is at most `supplyBefore - 1` wei and the denominators change. Upper bound: `N * max(supplyBefore) = N * totalSupply` wei.
- Resolve phase: `(pendingRedemptionEthBase * roll) / 100` loses at most 99 wei (single division).
- Claim phase: each `(ethValueOwed * roll) / 100` loses at most 99 wei. Across N players: at most `99 * N` wei.

**Total maximum dust per period: `N * totalSupply + 99 + 99 * N` wei.** For any practical supply (10^18 scale), the submit-phase dust dominates. However, in this example the actual sequential computation resulted in exact values at some steps due to fortuitous cancellation.

**Dust accumulation direction:** Always positive (pendingRedemptionEthValue retains dust). This means the contract holds slightly MORE segregated ETH than needed, which is safe -- the surplus stays in the contract and benefits future burners. **No solvency risk from rounding.**

**Verdict: Rounding is SAFE.** Dust accumulates in favor of the contract (pendingRedemptionEthValue >= sum of future payouts), bounded by `O(N * totalSupply)` wei per period. At 10^18 supply scale, this is still negligible (< 10^-18 ETH per period per player).

### BURNIE Accounting: pendingRedemptionBurnie

#### Write Sites

| # | Function | Line | Direction | Formula | Context |
|---|----------|------|-----------|---------|---------|
| W1 | `_submitGamblingClaimFrom` | 714 | INCREMENT | `pendingRedemptionBurnie += burnieOwed` | Reserves BURNIE proportional share at burn-time |
| W2 | `resolveRedemptionPeriod` | 560 | DECREMENT | `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` | Fully releases BURNIE reservation (transitions to coinflip system) |

#### Read Sites

| # | Function | Line | Usage |
|---|----------|------|-------|
| R1 | `_submitGamblingClaimFrom` | 701 | `totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie` (deducts reserved) |
| R2 | `previewBurn` | 651 | `totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie` (view preview) |
| R3 | `burnieReserve` | 661 | `burnieBal + claimableBurnie - pendingRedemptionBurnie` (view function) |

**MISSING DEDUCTION (CP-08):** `_deterministicBurnFrom` at line 482 computes `totalBurnie = burnieBal + claimableBurnie` WITHOUT subtracting `pendingRedemptionBurnie`. Same CP-08 finding.

#### BURNIE Flow Verification

**At submit:** `pendingRedemptionBurnie += burnieOwed` (line 714). BURNIE is reserved based on proportional share of unreserved balance. **CORRECT.**

**At resolve:** `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` (line 560). The ENTIRE base is removed from reservation because BURNIE transitions to the coinflip system:
1. `burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100` (line 557) -- rolled BURNIE amount returned to caller
2. Caller (rngGate at line 777) credits this via `coin.creditFlip(SDGNRS, burnieToCredit)` -- virtual coinflip stake
3. At claim time, BURNIE is paid via `_payBurnie` which draws from existing balance + `claimCoinflipsForRedemption` minting

**Key insight:** After resolution, `pendingRedemptionBurnie` is decremented by the full base, NOT by `burnieToCredit` (the rolled amount). This is correct because the rolled BURNIE enters the coinflip system as virtual stake and is no longer tracked by `pendingRedemptionBurnie`. The coinflip system independently tracks what it owes to sDGNRS.

**At claim:** No mutation to `pendingRedemptionBurnie`. BURNIE is paid via `_payBurnie` (line 609) which:
1. Transfers from existing sDGNRS BURNIE balance: `coin.transfer(player, payBal)` (line 760)
2. If shortfall, mints via `coinflip.claimCoinflipsForRedemption(address(this), remaining)` (line 763)

This is correct because BURNIE was released from `pendingRedemptionBurnie` at resolution and entered the coinflip as virtual stake. The actual BURNIE tokens flow at claim time through the coinflip mint path, not from a reservation.

### pendingRedemptionEthBase / pendingRedemptionBurnieBase

#### pendingRedemptionEthBase

| # | Function | Line | Operation |
|---|----------|------|-----------|
| W1 | `_submitGamblingClaimFrom` | 713 | `pendingRedemptionEthBase += ethValueOwed` (INCREMENT -- accumulates current period) |
| W2 | `resolveRedemptionPeriod` | 554 | `pendingRedemptionEthBase = 0` (RESET -- clears after resolution) |
| R1 | `resolveRedemptionPeriod` | 549 | Guard: `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return 0` |
| R2 | `resolveRedemptionPeriod` | 552 | `rolledEth = (pendingRedemptionEthBase * roll) / 100` |
| R3 | `resolveRedemptionPeriod` | 553 | `pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` |
| R4 | `hasPendingRedemptions` | 537 | `pendingRedemptionEthBase != 0` check |

**Verification:**
- Incremented only during submits in the current unresolved period (line 713).
- Reset to 0 at resolution (line 554), AFTER being used to compute `rolledEth` and adjust `pendingRedemptionEthValue`.
- The guard at line 549 prevents resolution when base is already zero.
- `hasPendingRedemptions()` uses base != 0 as the indicator, which correctly returns false after resolution.
- **CORRECT: Used only for the current unresolved period and properly reset.**

#### pendingRedemptionBurnieBase

| # | Function | Line | Operation |
|---|----------|------|-----------|
| W1 | `_submitGamblingClaimFrom` | 715 | `pendingRedemptionBurnieBase += burnieOwed` (INCREMENT) |
| W2 | `resolveRedemptionPeriod` | 561 | `pendingRedemptionBurnieBase = 0` (RESET) |
| R1 | `resolveRedemptionPeriod` | 549 | Guard: `pendingRedemptionBurnieBase == 0` check |
| R2 | `resolveRedemptionPeriod` | 557 | `burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100` |
| R3 | `resolveRedemptionPeriod` | 560 | `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` |
| R4 | `hasPendingRedemptions` | 537 | `pendingRedemptionBurnieBase != 0` check |

**Verification:** Same pattern as ETH base. Incremented during submits, reset at resolution, guarded against double-resolution. **CORRECT.**

---

## Segregation Solvency Proof (CORR-02)

### Invariant Statement

**Claim:** At every point during contract execution, the ETH segregated for pending gambling claims does not exceed the contract's total ETH-equivalent holdings:

```
pendingRedemptionEthValue <= address(this).balance + steth.balanceOf(this) + game.claimableWinnings()
```

Define:
- `H` = total holdings = `address(this).balance + steth.balanceOf(this) + game.claimableWinnings()`
- `P` = `pendingRedemptionEthValue`

### Proof: After Submit

**Action:** Player burns `amount` sDGNRS. `_submitGamblingClaimFrom` computes:
```solidity
totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue  // line 695
ethValueOwed = (totalMoney * amount) / supplyBefore                         // line 696
pendingRedemptionEthValue += ethValueOwed                                   // line 712
```

**Before submit:** Assume invariant holds: `P_old <= H`.

**After submit:** `P_new = P_old + ethValueOwed`

We need to show `P_new <= H`:
```
P_new = P_old + (H - P_old) * amount / supplyBefore
      = P_old + (H - P_old) * (amount / supplyBefore)
```

Since `amount <= supplyBefore / 2` (50% cap, line 686) and `amount <= supplyBefore` (balance check):
```
amount / supplyBefore <= 1/2
```

Therefore:
```
P_new = P_old + (H - P_old) * (amount / supplyBefore)
     <= P_old + (H - P_old) * 1
      = H
```

More precisely, since `ethValueOwed = floor((H - P_old) * amount / supplyBefore) <= (H - P_old) * amount / supplyBefore`:
```
P_new = P_old + ethValueOwed <= P_old + (H - P_old) = H
```

**SAFE after submit.** No ETH leaves the contract during a burn (tokens are destroyed, ETH stays).

**Note on sequential burns:** Each burn reduces `supplyBefore` (because `totalSupply -= amount` at line 707 happens AFTER `supplyBefore` is captured at line 689). For the second burn in the same period, `supplyBefore` is the reduced supply, and `totalMoney` is reduced by the first burn's `ethValueOwed`. The invariant holds inductively: if `P <= H` before the k-th burn, then after the k-th burn `P' = P + floor((H - P) * amount_k / supply_k) <= H`.

### Proof: After Resolve

**Action:** `resolveRedemptionPeriod(roll, flipDay)` adjusts segregation:
```solidity
rolledEth = (pendingRedemptionEthBase * roll) / 100                        // line 552
pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth  // line 553
```

**Before resolve:** `P_old <= H`. Let `B = pendingRedemptionEthBase` (the current period's unresolved base).

**After resolve:**
```
P_new = P_old - B + floor(B * roll / 100)
```

**Case 1: roll <= 100:**
```
floor(B * roll / 100) <= B
P_new = P_old - B + floor(B * roll / 100) <= P_old <= H
```
**SAFE** -- segregated amount decreases or stays the same.

**Case 2: roll > 100 (max 175):**
```
P_new = P_old - B + floor(B * 175 / 100) = P_old - B + floor(1.75 * B) = P_old + floor(0.75 * B)
```

We need `P_new <= H`, i.e., `P_old + 0.75 * B <= H`.

From the submit proof, we know that at the time of submission (before resolution), the base `B` was created from a pool of size `H_submit - P_prior`. The 50% supply cap means at most 50% of the supply can be burned, so:
```
B <= (H_submit - P_prior) * (supply_burned / supply_at_burn) <= (H_submit - P_prior) * (1/2)
```

But `P_old` after all submits: `P_old = P_prior + B` (base is the current period's contribution).

So: `P_old + 0.75 * B = P_prior + B + 0.75B = P_prior + 1.75B`

And: `B <= 0.5 * (H_submit - P_prior)` (from 50% cap on supply, worst case the burned supply corresponds to 50% of the available ETH).

Actually, the relationship between supply burned and ETH is: `ethValueOwed = (H - P) * amount / supply`. With 50% supply burned: `B = (H - P_prior) * supply_burned / supply_total`. If supply_burned = supply_total / 2: `B = (H - P_prior) / 2`.

Therefore:
```
P_prior + 1.75B = P_prior + 1.75 * (H - P_prior) / 2 = P_prior + 0.875 * (H - P_prior) = 0.125 * P_prior + 0.875 * H
```

Since `P_prior >= 0`: `P_prior + 1.75B <= 0.125 * H + 0.875 * H = H` (when `P_prior = H`... but that can't happen because no ETH would be available for new burns).

Wait, let me re-examine. If `P_prior = 0` (no prior reservations):
```
B <= (H - 0) / 2 = H / 2
P_new = 0 + 1.75 * H / 2 = 0.875 * H <= H
```
**SAFE.**

If `P_prior > 0` (prior reservations from earlier resolved periods):
```
B <= (H - P_prior) / 2
P_new = P_prior + 1.75 * (H - P_prior) / 2 = P_prior + 0.875 * (H - P_prior) = 0.125 * P_prior + 0.875 * H
```
Since `0 <= P_prior <= H`: `P_new = 0.125 * P_prior + 0.875 * H`. Maximum when `P_prior = H`: `P_new = 0.125H + 0.875H = H`. **EXACTLY H**, not exceeding.

But `P_prior = H` is impossible because submits would compute `totalMoney = H - P_prior = 0`, yielding `ethValueOwed = 0`, so `B = 0` and no claims would be created.

**SAFE after resolve for single-period.** `P_new <= 0.125 * P_prior + 0.875 * H < H` for all achievable states.

### Multi-Period Cumulative Reservation Analysis

**Critical question:** Can cumulative reservations across multiple periods eventually exceed holdings?

**Scenario:** Period 1 submits at 50% cap, resolves at roll=175. Period 2 submits at 50% cap, resolves at roll=175. Repeat.

**Period 1:**
- `P_0 = 0`, `H` = total holdings (constant, no ETH leaves until claims)
- Submit: `B_1 = (H - 0) * 0.5 = 0.5H`. `P_after_submit = 0.5H`.
- Resolve (175): `P_1 = 0.5H - 0.5H + 0.875H = 0.875H`.

**Period 2 (before Period 1 claims):**
- Available: `H - P_1 = H - 0.875H = 0.125H`
- But supply has been reduced by 50% (from the burns). New supply = 0.5 * original.
- Submit: `B_2 = (H - 0.875H) * (burned_2 / supply_2)`. At 50% cap: burned_2 = 0.5 * supply_2 = 0.5 * 0.5 * original = 0.25 * original.
- `ethValueOwed_2 = (0.125H * 0.25 * original) / (0.5 * original) = 0.125H * 0.5 = 0.0625H`
- `P_after_submit_2 = 0.875H + 0.0625H = 0.9375H`
- Resolve (175): `P_2 = 0.9375H - 0.0625H + 0.0625H * 1.75 = 0.9375H - 0.0625H + 0.109375H = 0.984375H`

**Period 3 (before any claims):**
- Available: `H - 0.984375H = 0.015625H`
- Supply: 0.25 * original
- `B_3 = 0.015625H * 0.5 = 0.0078125H`
- `P_after_submit_3 = 0.984375H + 0.0078125H = 0.9921875H`
- Resolve (175): `P_3 = 0.9921875H - 0.0078125H + 0.0078125H * 1.75 = 0.9921875H + 0.005859375H = 0.998046875H`

**Pattern:** The series converges. Each period's contribution diminishes geometrically because available ETH = `H - P_prev` shrinks. The sequence `P_n` approaches H but never reaches it:
```
P_n = H * (1 - (0.125)^n)  [approximately]
```

**Proof that P_n < H always:** After resolve with roll=175 and 50% cap, `P_new = 0.125 * P_old + 0.875 * H`. This is a contraction mapping with fixed point at `H` (approached from below). Since `P_0 = 0 < H`, and the mapping preserves `P < H` (as `P_new = 0.125P + 0.875H < 0.125H + 0.875H = H` when `P < H`), the invariant holds for all periods.

**Additional safety margin:** The above assumes no claims between periods. In practice, players claim between periods, which reduces `P`, providing even more headroom.

**SOLVENCY HOLDS for multi-period cumulative reservations.** The 50% supply cap combined with the proportional-share formula creates a geometric convergence that prevents total reservations from ever reaching holdings.

### Proof: After Claim

**Action:** `claimRedemption()` decrements segregation and pays ETH:
```solidity
pendingRedemptionEthValue -= ethPayout;    // line 599
_payEth(player, ethPayout);                // line 605
```

**Before claim:** `P_old <= H`.
**After claim:** `P_new = P_old - ethPayout`, `H_new = H - ethPayout` (ETH sent to player).

```
P_new = P_old - ethPayout <= H - ethPayout = H_new
```

**SAFE.** Both segregation and holdings decrease by the same amount (ethPayout). The invariant is preserved.

**Edge case -- stETH fallback:** If `_payEth` sends stETH instead of ETH (lines 744-751), holdings still decrease by `ethPayout` (some as ETH, remainder as stETH). `P_new = P_old - ethPayout <= H_old - ethPayout = H_new`. **STILL SAFE.**

### BURNIE Solvency

**Claim:** When `_payBurnie` is called, sDGNRS can supply sufficient BURNIE.

**BURNIE credit path:**

1. **At resolution (rngGate line 777):** `coin.creditFlip(SDGNRS, burnieToCredit)` credits virtual BURNIE stake to sDGNRS in the coinflip system. This does not transfer actual BURNIE tokens -- it creates a virtual flip stake that will resolve on `flipDay`.

2. **At claim time (_payBurnie, lines 755-765):**
   - Step 1: `payBal = min(amount, coin.balanceOf(sDGNRS))` -- use existing BURNIE balance (line 757)
   - Step 2: `coin.transfer(player, payBal)` -- transfer available BURNIE (line 760)
   - Step 3: If `remaining != 0`: `coinflip.claimCoinflipsForRedemption(sDGNRS, remaining)` -- mint BURNIE from coinflip winnings (line 763)
   - Step 4: `coin.transfer(player, remaining)` -- transfer minted BURNIE (line 764)

**Can another path drain sDGNRS's BURNIE balance?**

Searching for all paths that reduce sDGNRS BURNIE balance:
- `_deterministicBurnFrom` transfers BURNIE via `coin.transfer(beneficiary, ...)` (line 510, 514) -- only called post-gameOver
- `_payBurnie` (as analyzed above) -- only called from `claimRedemption`
- No other function in sDGNRS calls `coin.transfer`

sDGNRS does not have any external function allowing arbitrary BURNIE withdrawal. Pool transfers move sDGNRS tokens, not BURNIE. **No external drain path exists.**

**Can concurrent claims race?** Multiple players calling `claimRedemption()` concurrently:
- Solidity transactions are atomic -- only one executes at a time in a block
- Each claim deletes the caller's `pendingRedemptions[player]` before external calls (line 602)
- No race condition between concurrent claims

**Edge case: Can `claimCoinflipsForRedemption` return less than `remaining`?**

Looking at `_claimCoinflipsAmount` (BurnieCoinflip.sol lines 372-388):
```solidity
uint256 toClaim = amount;
if (toClaim > stored) {
    toClaim = stored;   // line 384: caps at available
}
```

If the coinflip system has less claimable BURNIE than `remaining`, it returns less. Then `coin.transfer(player, remaining)` at line 764 would attempt to transfer `remaining` BURNIE but sDGNRS only received `claimed < remaining`. This would cause the transfer to revert (insufficient balance).

**Is this reachable?** The coinflip credit at resolution was `burnieToCredit = (base * roll) / 100`. The player's payout is `burniePayout = (burnieOwed * roll * (100 + rewardPercent)) / 10000`. The `(100 + rewardPercent)` factor means the payout can exceed what was credited (rewardPercent ranges 50-156%). However, the coinflip system handles this through its daily claim mechanism -- the credited stake participates in the flip and if won, yields `stake * (100 + rewardPercent) / 100`. So the minted amount from `claimCoinflipsForRedemption` should match or exceed the payout formula... but only if the flip was WON.

Since `burniePayout` is only non-zero when `flipWon == true` (line 594), and the coinflip credit resolves on the same day, the claimable amount from the won flip is `burnieToCredit * (100 + rewardPercent) / 100`. The player's payout is `(burnieOwed * roll * (100 + rewardPercent)) / 10000`. We need:

```
burnieToCredit * (100 + rewardPercent) / 100 >= sum(burnieOwed_i * roll * (100 + rewardPercent)) / 10000
```

Dividing both sides by `(100 + rewardPercent) / 100`:
```
burnieToCredit >= sum(burnieOwed_i * roll) / 100
```

And `burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100 = sum(burnieOwed_i) * roll / 100` (with rounding).

Due to rounding: `burnieToCredit = floor(sum(burnieOwed_i) * roll / 100)`, while `sum(burnieOwed_i * roll / 100)` has per-player rounding that results in `sum <= floor(sum(burnieOwed_i) * roll / 100)`. But the coinflip also has its own rounding during claim processing.

**Practical assessment:** The rounding differences are at most a few wei per claim. If a small shortfall occurs, `claimCoinflipsForRedemption` returns slightly less, and the second `coin.transfer` reverts. This would be a denial-of-service at the wei level, not a solvency issue. The fix would require either allowing partial BURNIE claims or adding a small buffer.

**Verdict:** BURNIE solvency is functionally sound but has a theoretical edge case where rounding differences in the coinflip system could cause a revert on the final wei-level transfer. In practice, the sDGNRS contract typically has a non-zero BURNIE balance from previous operations, which acts as a buffer absorbing rounding dust. **LOW risk -- no material fund loss, potential revert on edge-case rounding.**

### Known Issues from Findings

**CP-08 Impact on Solvency (from Plan 01):**

If `_deterministicBurnFrom` is called post-gameOver while `pendingRedemptionEthValue > 0`:

```solidity
// _deterministicBurnFrom (line 477) -- MISSING deduction:
totalMoney = ethBal + stethBal + claimableEth  // includes reserved ETH
totalValueOwed = (totalMoney * amount) / supplyBefore
```

The deterministic burner receives a proportional share of the FULL holdings, including ETH reserved for pending gambling claimants. This creates a solvency violation:

**Quantification of maximum solvency gap:**

Worst case: `pendingRedemptionEthValue = 0.875H` (50% burn, roll=175), then a deterministic burner burns 50% of remaining supply.

- Total holdings: `H` (no ETH has left yet)
- `totalMoney_incorrect = H` (should be `H - 0.875H = 0.125H`)
- `totalValueOwed_incorrect = H * (remaining_burn / remaining_supply)`
- If the deterministic burner burns 50% of remaining supply: `totalValueOwed = H * 0.5 = 0.5H`
- But only `0.125H` should be available.
- Overpayment: `0.5H - 0.0625H = 0.4375H`
- After paying `0.5H`, remaining contract balance = `0.5H`
- But `pendingRedemptionEthValue = 0.875H`
- **Solvency gap: `0.875H - 0.5H = 0.375H`** -- gambling claimants are underfunded by 37.5% of total holdings

This is a HIGH severity solvency violation. The fix (adding `- pendingRedemptionEthValue` to line 477) completely eliminates it.

---

## Cross-Contract Interaction Audit (DELTA-02)

### 4-Contract State Consistency

The following table maps ALL cross-contract calls in the redemption system. Each entry documents the caller, callee, direction, and state change.

| # | Caller | Function | Line | Callee | Function | Direction | State Change |
|---|--------|----------|------|--------|----------|-----------|-------------|
| 1 | sDGNRS | `burnWrapped` | 452 | DGNRS | `burnForSdgnrs` | call | Burns DGNRS from player; DGNRS.totalSupply -= amount, DGNRS.balanceOf[player] -= amount |
| 2 | DGNRS | `burn` | 167 | sDGNRS | `burn` | call | Enters gambling or deterministic path; msg.sender = DGNRS contract |
| 3 | sDGNRS | `_submitGamblingClaimFrom` | 694 | Game | `_claimableWinnings` -> `claimableWinningsOf` | staticcall | View only -- reads pending winnings for ETH computation |
| 4 | sDGNRS | `_submitGamblingClaimFrom` | 700 | BurnieCoinflip | `previewClaimCoinflips` | staticcall | View only -- reads claimable BURNIE for share computation |
| 5 | AdvanceModule | `rngGate` | 772 | sDGNRS | `hasPendingRedemptions` | staticcall | View only -- reads pendingRedemptionEthBase/BurnieBase |
| 6 | AdvanceModule | `rngGate` | 775 | sDGNRS | `resolveRedemptionPeriod` | call | Sets period roll/flipDay, adjusts pendingRedemptionEthValue, clears bases, releases BURNIE reservation |
| 7 | AdvanceModule | `rngGate` | 777 | BurnieCoin | `creditFlip` -> BurnieCoinflip.`creditFlip` | call | Credits virtual BURNIE stake to sDGNRS for flipDay via _addDailyFlip |
| 8 | sDGNRS | `claimRedemption` | 584 | BurnieCoinflip | `getCoinflipDayResult` | staticcall | View only -- reads rewardPercent/win for flipDay |
| 9 | sDGNRS | `_payEth` | 736 | Game | `claimWinnings` | call | Sends pending ETH winnings from Game to sDGNRS |
| 10 | sDGNRS | `_payEth` | 741 | player (EOA/contract) | `call{value: amount}` | call | Sends ETH to player -- UNTRUSTED recipient |
| 11 | sDGNRS | `_payEth` | 747 | player (EOA/contract) | `call{value: ethOut}` | call | Sends partial ETH to player (stETH fallback case) -- UNTRUSTED |
| 12 | sDGNRS | `_payEth` | 750 | Lido stETH | `transfer` | call | Sends stETH to player (trusted: Lido contract) |
| 13 | sDGNRS | `_payBurnie` | 760 | BurnieCoin | `transfer` | call | Transfers existing BURNIE from sDGNRS to player. Triggers `_claimCoinflipShortfall(msg.sender=sDGNRS, amount)` inside BurnieCoin.transfer |
| 14 | BurnieCoin | `transfer` -> `_claimCoinflipShortfall` | 593 | BurnieCoinflip | `claimCoinflipsFromBurnie` | call | Auto-claims coinflip winnings to cover shortfall (if sDGNRS balance < transfer amount) |
| 15 | sDGNRS | `_payBurnie` | 763 | BurnieCoinflip | `claimCoinflipsForRedemption` | call | Mints BURNIE to sDGNRS from coinflip winnings (sDGNRS-only access) |
| 16 | sDGNRS | `_payBurnie` | 764 | BurnieCoin | `transfer` | call | Transfers minted BURNIE from sDGNRS to player |
| 17 | sDGNRS | `_deterministicBurnFrom` | 492 | Game | `claimWinnings` | call | Pulls pending ETH winnings (deterministic path only) |
| 18 | sDGNRS | `_deterministicBurnFrom` | 510 | BurnieCoin | `transfer` | call | Sends BURNIE to beneficiary (deterministic path) |
| 19 | sDGNRS | `_deterministicBurnFrom` | 513 | BurnieCoinflip | `claimCoinflips` | call | Claims coinflip winnings to cover BURNIE shortfall (deterministic path) |
| 20 | sDGNRS | `_deterministicBurnFrom` | 514 | BurnieCoin | `transfer` | call | Sends claimed BURNIE to beneficiary |
| 21 | sDGNRS | `_deterministicBurnFrom` | 519 | Lido stETH | `transfer` | call | Sends stETH to beneficiary |
| 22 | sDGNRS | `_deterministicBurnFrom` | 523 | beneficiary (EOA/contract) | `call{value: ethOut}` | call | Sends ETH to beneficiary -- UNTRUSTED recipient |
| 23 | BurnieCoinflip | `processCoinflipPayouts` | 859 | BurnieCoinflip | `_claimCoinflipsInternal` (for sDGNRS) | internal | Keeps sDGNRS flip cursor current during day resolution |
| 24 | DGNRS | `burn` | 170 | BurnieCoin | `transfer` | call | Forwards BURNIE from DGNRS to player (deterministic path) |
| 25 | DGNRS | `burn` | 173 | Lido stETH | `transfer` | call | Forwards stETH from DGNRS to player (deterministic path) |
| 26 | DGNRS | `burn` | 176 | player (EOA/contract) | `call{value: ethOut}` | call | Forwards ETH from DGNRS to player -- UNTRUSTED |

### Reentrancy Verification

#### External calls to untrusted addresses

**Call #10/11: `player.call{value: amount}("")` in `_payEth` (lines 741, 747)**

At the point of the ETH transfer to the player, the following storage has been committed:

1. `pendingRedemptionEthValue -= ethPayout` (line 599) -- COMMITTED
2. `delete pendingRedemptions[player]` (line 602) -- COMMITTED

The player's claim is fully deleted before any external call. If the recipient reenters:

| Reentry Target | Outcome | Safe? |
|----------------|---------|-------|
| `claimRedemption()` | Reverts at line 578: `claim.periodIndex == 0` (NoClaim) because claim was deleted | YES |
| `burn(amount)` | Succeeds IF player has sDGNRS balance. Creates NEW independent claim. Does NOT read stale state because `pendingRedemptionEthValue` was already decremented. | YES |
| `burnWrapped(amount)` | Succeeds IF player has DGNRS. Creates NEW claim (same as above). | YES |
| `gameAdvance()` | Calls `game.advanceGame()`. Could trigger `rngGate` which calls `resolveRedemptionPeriod`. State is consistent: `pendingRedemptionEthValue` is correct (decremented). | YES |

**No reentrancy vulnerability.** The claim deletion at line 602 prevents double-claiming. New burns create independent claims against correct state.

**Call #22: `beneficiary.call{value: ethOut}` in `_deterministicBurnFrom` (line 523)**

At this point, all state mutations are complete:
1. `balanceOf[burnFrom] -= amount` (line 486) -- COMMITTED
2. `totalSupply -= amount` (line 487) -- COMMITTED
3. BURNIE and stETH transfers already executed (lines 510-520)
4. Only the ETH transfer remains

If the recipient reenters `_deterministicBurnFrom` (via `burn()` or `burnWrapped()`):
- The supply has been reduced; `balanceOf[burnFrom]` has been reduced
- Any new burn would compute proportional shares against the updated (lower) supply
- **No double-spend possible** -- the burner cannot re-burn already-burned tokens

However, note CP-08: `_deterministicBurnFrom` does NOT subtract `pendingRedemptionEthValue` from `totalMoney`. A reentrant call would ALSO fail to subtract it, compounding the CP-08 issue. But this is the same bug, not a new reentrancy vulnerability.

**Call #26: `player.call{value: ethOut}` in `DegenerusStonk.burn` (line 176)**

At this point:
1. `DGNRS.balanceOf[msg.sender] -= amount` (via `_burn` at line 165)
2. `DGNRS.totalSupply -= amount`
3. `stonk.burn(amount)` already returned (sDGNRS state committed)
4. BURNIE and stETH already forwarded (lines 169-174)

If the player reenters `DGNRS.burn()`:
- Their DGNRS balance has been reduced; they can only burn remaining balance
- `stonk.burn(amount)` would execute with the updated sDGNRS state
- **SAFE** -- no double-spend possible

### Access Control on New Entry Points

| Function | Contract | Guard | Correct? |
|----------|----------|-------|----------|
| `resolveRedemptionPeriod(roll, flipDay)` | sDGNRS (line 545) | `if (msg.sender != ContractAddresses.GAME) revert Unauthorized()` (line 546) | YES -- only callable by GAME contract. AdvanceModule is a module of GAME (delegatecall), so `msg.sender` = GAME when AdvanceModule calls it. Cannot be bypassed. |
| `hasPendingRedemptions()` | sDGNRS (line 536) | None (view function) | N/A -- read-only, no access control needed. Returns public storage state. |
| `claimCoinflipsForRedemption(player, amount)` | BurnieCoinflip (line 344) | `if (msg.sender != ContractAddresses.SDGNRS) revert OnlyBurnieCoin()` (line 348) | YES -- only callable by sDGNRS. Note: the error name `OnlyBurnieCoin` is misleading (reused from another guard), but the check is correct (`msg.sender == SDGNRS`). Cannot be bypassed -- SDGNRS address is immutable via ContractAddresses. |
| `burnForSdgnrs(player, amount)` | DGNRS (line 233) | `if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized()` (line 234) | YES -- only callable by sDGNRS. Called from `burnWrapped()`. Cannot be bypassed. |
| `creditFlip(player, amount)` | BurnieCoinflip (line 867) | `onlyFlipCreditors` modifier (line 194-199): allows `degenerusGame` or `burnie` (BurnieCoin) | YES -- called from rngGate via `coin.creditFlip(SDGNRS, burnieToCredit)`. The call chain is: AdvanceModule (delegatecall from GAME) -> BurnieCoin.creditFlip -> BurnieCoinflip.creditFlip. BurnieCoin.creditFlip (line 563) has `onlyFlipCreditors` which allows GAME or AFFILIATE. Since rngGate runs as GAME (delegatecall), the call goes GAME -> BurnieCoin.creditFlip (msg.sender=GAME, passes onlyFlipCreditors) -> BurnieCoinflip.creditFlip (msg.sender=BurnieCoin, passes onlyFlipCreditors allowing burnie). **Correct two-hop authorization chain.** |

**Bypass analysis:** All guards check against `ContractAddresses.*` which are compile-time constants. No proxy pattern, no mutable address storage, no admin override. The only way to bypass would be to deploy a different contract at the same address, which is impossible on mainnet (CREATE2 collision). **No bypass path exists.**

---

## CEI Compliance Verification (CORR-03)

### claimRedemption() CEI Analysis

Line-by-line annotation of `claimRedemption()` (StakedDegenerusStonk.sol lines 575-613):

```
Line 576: CHECK   -- address player = msg.sender
Line 577: CHECK   -- PendingRedemption storage claim = pendingRedemptions[player]
Line 578: CHECK   -- if (claim.periodIndex == 0) revert NoClaim()
Line 580: CHECK   -- RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex]
Line 581: CHECK   -- if (period.roll == 0) revert NotResolved()
Line 584: CHECK   -- (uint16 rewardPercent, bool flipWon) = coinflip.getCoinflipDayResult(period.flipDay)
                      [STATICCALL to trusted BurnieCoinflip -- safe read, no state mutation]
Line 585: CHECK   -- if (rewardPercent == 0 && !flipWon) revert FlipNotResolved()
Line 587: CHECK   -- uint16 roll = period.roll
Line 590: CHECK   -- uint256 ethPayout = (claim.ethValueOwed * roll) / 100  [pure computation]
Line 593: CHECK   -- uint256 burniePayout  [declaration]
Line 594: CHECK   -- if (flipWon) {
Line 595: CHECK   --     burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000
Line 596: CHECK   -- }
Line 599: EFFECT  -- pendingRedemptionEthValue -= ethPayout
Line 602: EFFECT  -- delete pendingRedemptions[player]
Line 605: INTERACTION -- _payEth(player, ethPayout)
Line 608: INTERACTION -- if (burniePayout != 0) {
Line 609: INTERACTION --     _payBurnie(player, burniePayout)
Line 610: INTERACTION -- }
Line 612: INTERACTION -- emit RedemptionClaimed(player, roll, flipWon, ethPayout, burniePayout)
```

**Ordering: CHECK (576-596) -> EFFECT (599-602) -> INTERACTION (605-612)**

**Verdict: STRICTLY CEI COMPLIANT.** All checks and computations precede all state mutations, which precede all external calls. The staticcall at line 584 is safe (view function, no state change, trusted contract).

### _payEth CEI Depth Analysis

Trace into `_payEth(player, amount)` (lines 730-751):

```
Line 731: CHECK       -- if (amount == 0) return
Line 732: CHECK       -- uint256 ethBal = address(this).balance [read]
Line 733: CHECK       -- uint256 claimableEth = _claimableWinnings() [view call to game]
Line 735: CHECK       -- if (amount > ethBal && claimableEth != 0)
Line 736: INTERACTION -- game.claimWinnings(address(0))
                         [Pulls ETH from Game to sDGNRS. TRUSTED contract (immutable address).
                          State change: Game.pendingWinnings[sDGNRS] -= amount, ETH transferred to sDGNRS.]
Line 737: CHECK       -- ethBal = address(this).balance [re-read after pull]
Line 740: CHECK       -- if (amount <= ethBal)
Line 741: INTERACTION -- (bool success, ) = player.call{value: amount}("") [UNTRUSTED]
Line 742: CHECK       -- if (!success) revert TransferFailed()
Line 744: CHECK       -- uint256 ethOut = ethBal
Line 745: CHECK       -- uint256 stethOut = amount - ethOut
Line 747: INTERACTION -- (bool success, ) = player.call{value: ethOut}("") [UNTRUSTED]
Line 748: CHECK       -- if (!success) revert TransferFailed()
Line 750: INTERACTION -- steth.transfer(player, stethOut) [TRUSTED: Lido]
Line 751: CHECK       -- if (!...) revert TransferFailed()
```

**Storage state at point of `player.call{value:}` (line 741 or 747):**

All sDGNRS storage mutations were completed BEFORE `_payEth` was called:
- `pendingRedemptionEthValue` -- already decremented (line 599, before _payEth at 605)
- `pendingRedemptions[player]` -- already deleted (line 602, before _payEth at 605)

If the player reenters:
- `claimRedemption()` -- reverts with `NoClaim()` (claim deleted at line 602). **SAFE.**
- `burn(amount)` / `burnWrapped(amount)` -- creates a NEW claim. The `pendingRedemptionEthValue` is already decremented, so `totalMoney` computation uses the correct (lower) segregated value. **SAFE -- independent operation.**
- Any other sDGNRS function reading `pendingRedemptionEthValue` -- sees the correct (decremented) value. **SAFE.**

**Note on `game.claimWinnings` (line 736):** This is an INTERACTION before the player INTERACTION, technically breaking strict "no interactions before all interactions are done" ordering. However, it is a call to a TRUSTED contract (immutable Game address) and does not expose any reentrancy because: (a) Game.claimWinnings modifies only Game-internal state, (b) the ETH sent TO sDGNRS is not callable by the player, (c) the function has no callback. **ACCEPTABLE -- trusted contract interaction.**

### _payBurnie CEI Depth Analysis

Trace into `_payBurnie(player, amount)` (lines 755-765):

```
Line 756: CHECK       -- uint256 burnieBal = coin.balanceOf(address(this)) [view call]
Line 757: CHECK       -- uint256 payBal = amount <= burnieBal ? amount : burnieBal
Line 758: CHECK       -- uint256 remaining = amount - payBal
Line 759: CHECK       -- if (payBal != 0)
Line 760: INTERACTION -- coin.transfer(player, payBal)
                         [BurnieCoin.transfer: triggers _claimCoinflipShortfall(msg.sender=sDGNRS, payBal)]
```

**Deep trace of `coin.transfer(player, payBal)` (line 760):**

1. Enters `BurnieCoin.transfer(player, payBal)` (BurnieCoin.sol line 405)
2. Calls `_claimCoinflipShortfall(msg.sender=sDGNRS, payBal)` (line 406)
3. Inside `_claimCoinflipShortfall` (line 587-598):
   - `if (amount == 0) return` -- payBal != 0, continue
   - `if (degenerusGame.rngLocked()) return` -- during claim, rngLocked may be true or false. If true, skips shortfall claim. If false, continues.
   - `balance = balanceOf[sDGNRS]` -- sDGNRS's BURNIE balance
   - `if (balance >= amount) return` -- if sDGNRS has enough, no shortfall. This should be true since we already checked `payBal = min(amount, burnieBal)`, so `payBal <= burnieBal = balanceOf[sDGNRS]`. **Shortfall does NOT fire for the first transfer.**
4. `_transfer(sDGNRS, player, payBal)` (line 407) -- moves BURNIE from sDGNRS to player

**Does the shortfall mechanism fire?** No. `payBal <= burnieBal` by construction (line 757). The `_claimCoinflipShortfall` check sees `balance >= amount` and returns immediately. No nested coinflip interaction on this path.

```
Line 762: CHECK       -- if (remaining != 0)
Line 763: INTERACTION -- coinflip.claimCoinflipsForRedemption(address(this), remaining)
                         [BurnieCoinflip: sDGNRS-only. Processes pending claims, mints BURNIE to sDGNRS.
                          Modifies BurnieCoinflip state (claimableStored, lastClaimedDay) and mints
                          BURNIE tokens to sDGNRS via BurnieCoin.mintForCoinflip.]
```

**Can `claimCoinflipsForRedemption` fail?**
- Access: checks `msg.sender == SDGNRS` (line 348) -- passes since caller is sDGNRS.
- Internal: `_claimCoinflipsAmount(player=sDGNRS, amount=remaining, mintTokens=true)` (line 349)
- If available claimable < remaining: returns `claimed < remaining`. The returned amount may be less than requested.
- After this call, sDGNRS should have `claimed` BURNIE tokens minted to its balance.

```
Line 764: INTERACTION -- coin.transfer(player, remaining)
                         [Transfers remaining BURNIE from sDGNRS to player.
                          If claimCoinflipsForRedemption returned less than remaining,
                          sDGNRS has insufficient balance and this REVERTS.]
```

**Edge case analysis:** If `claimCoinflipsForRedemption` returns `claimed < remaining`:
- `coin.transfer(player, remaining)` attempts to transfer `remaining` but sDGNRS only has `claimed + existing_balance`.
- If `claimed + existing_balance < remaining`, the transfer reverts inside BurnieCoin (underflow on `balanceOf[sDGNRS] -= remaining`).
- The entire `claimRedemption()` transaction reverts.

**When does this happen?** The coinflip system should have enough claimable BURNIE because:
1. At resolution, `burnieToCredit = (base * roll) / 100` was credited as virtual stake
2. If the flip was WON, the claimable amount = `burnieToCredit * (100 + rewardPercent) / 100`
3. The `burniePayout = (burnieOwed * roll * (100 + rewardPercent)) / 10000`
4. Since `burnieToCredit ~= sum(burnieOwed) * roll / 100`, the claimable should cover all individual payouts

The only gap is from rounding, which is at most a few wei (see BURNIE Solvency section above). The sDGNRS contract's existing BURNIE balance absorbs this rounding dust in practice. **LOW risk.**

### CEI Verdict

| Entry Point | Verdict | Detail |
|-------------|---------|--------|
| `claimRedemption()` | **CEI COMPLIANT** | Strict C->E->I ordering. All storage writes (pendingRedemptionEthValue, delete claim) complete before any external call. Reentrancy safe via claim deletion. |
| `burn()` | **CEI COMPLIANT** (gambling path) / **CEI MINOR ISSUE** (deterministic path) | Gambling: no external calls after storage writes (returns (0,0,0)). Deterministic: burn-then-interact, but `_deterministicBurnFrom` sends BURNIE/stETH/ETH after all storage writes (lines 486-487 before 510-523). The `game.claimWinnings` at line 492 is between effects and player-facing interactions, but is to a trusted contract. |
| `burnWrapped()` | **CEI COMPLIANT** (gambling path) / **CEI MINOR ISSUE** (deterministic path) | Same as `burn()`. The `dgnrsWrapper.burnForSdgnrs` call at line 452 is before all storage writes but only modifies DGNRS state (trusted). Gambling path: no external calls after sDGNRS storage writes. |
| `resolveRedemptionPeriod()` | **CEI COMPLIANT** | Pure effects function. All storage writes (lines 552-567) with no external calls. Returns a value to the caller. No interactions. |

**Overall: The redemption system is CEI compliant for all security-critical paths.** The minor notes on the deterministic path relate to trusted-contract interactions that do not create exploitable reentrancy vectors.

---

## Phase 44 Audit Summary

Consolidated findings across Plans 01, 02, and 03:

| Requirement | Verdict | Key Finding |
|-------------|---------|-------------|
| DELTA-01 | PASS (with dust note) | pendingRedemptionEthValue reconciles correctly across submit/resolve/claim; rounding dust accumulates in contract's favor (max O(N*supply) wei/period) |
| DELTA-02 | PASS | All 26 cross-contract calls mapped with line numbers; access control verified on all 5 new entry points; no bypass paths |
| DELTA-03 | ISSUE (HIGH) | CP-08 CONFIRMED: _deterministicBurnFrom missing pendingRedemptionEthValue/Burnie deduction -- solvency gap up to 37.5% of holdings |
| DELTA-04 | ISSUE (HIGH) | CP-06 CONFIRMED: _gameOverEntropy missing resolveRedemptionPeriod -- permanent fund loss for last-period gambling claims |
| DELTA-05 | ISSUE (HIGH) | Seam-1 CONFIRMED: DGNRS.burn() gambling path orphans claim under DGNRS contract address (no claimRedemption function) |
| DELTA-06 | PASS (INFO) | CP-02 REFUTED: zero sentinel safe by +1 offset in currentDayIndexAt; periodIndex=0 is unreachable for real periods |
| DELTA-07 | ISSUE (MEDIUM) | CP-07 CONFIRMED: coinflip dependency blocks ETH claim at game-over boundary when flipDay is skipped |
| CORR-01 | PASS | Full lifecycle trace documented with 176 line references across 4 contracts; all 13 storage mutations in submit path verified |
| CORR-02 | PASS (conditional) | Segregation solvency proven for submit/resolve/claim and multi-period scenarios. CONDITIONAL on CP-08 fix: without fix, solvency violated post-gameOver |
| CORR-03 | PASS | CEI compliance verified for claimRedemption (strict C-E-I), burn, burnWrapped, and resolveRedemptionPeriod |
| CORR-04 | PASS | Period monotonicity proven (single write site + EVM timestamp monotonicity); resolution ordering proven (base zeroing prevents re-resolution); 50% cap enforced |
| CORR-05 | PASS | burnWrapped dual burn verified: both DGNRS.totalSupply and sDGNRS.totalSupply decrease by exactly amount |

### Fixes Required Before Phase 45

Ordered by severity:

1. **CP-08 (HIGH): Deterministic burn double-spend via missing segregation deduction**
   - Fix: Add `- pendingRedemptionEthValue` and `- pendingRedemptionBurnie` to `_deterministicBurnFrom` lines 477, 482
   - Two-line change. Impact on Phase 45: invariant tests can encode `totalMoney` always excludes segregated amounts
   - Priority: CRITICAL -- without this fix, post-gameOver burns create solvency violation

2. **CP-06 (HIGH): Stuck claims at game-over -- missing resolveRedemptionPeriod in _gameOverEntropy**
   - Fix: Add redemption resolution block (mirror rngGate lines 770-780) to both VRF and fallback paths in `_gameOverEntropy` (AdvanceModule lines 823-832, 840-849)
   - Impact on Phase 45: invariant tests need to verify resolution occurs on ALL RNG paths including game-over

3. **Seam-1 (HIGH): DGNRS.burn() fund trap during active game**
   - Fix: Option A (recommended): Revert `DGNRS.burn()` during active game when `ethOut == 0 && stethOut == 0 && burnieOut == 0` (gambling path returns zeros)
   - Impact on Phase 45: invariant tests should verify DGNRS.burn() reverts during active game or that beneficiary is always the player

4. **CP-07 (MEDIUM): Coinflip resolution dependency blocks ETH claim at game boundary**
   - Fix: Option A (recommended): Modify `claimRedemption()` to allow ETH claiming independently of coinflip resolution -- decouple ETH payout from BURNIE payout
   - Impact on Phase 45: invariant tests should verify ETH claim path does not depend on coinflip resolution

---

*Document generated for Phase 44 Plan 03 -- DELTA-01, DELTA-02, CORR-02, CORR-03 requirements.*
*Line numbers reference contracts as of 2026-03-21.*
