# Phase 51 Plan 01: 50/50 Split Routing and GameOver Bypass Findings

**Audited:** 2026-03-21
**Contracts:** StakedDegenerusStonk.sol, DegenerusGame.sol
**Requirements:** REDM-01, REDM-02

---

## REDM-01: 50/50 Split Routing

### Verdict: SAFE

The 50/50 split correctly routes half of rolled ETH to direct payout and half to lootbox resolution, with exact conservation of the total amount.

### Evidence

#### 1. totalRolledEth Computation (Line 584)

```solidity
// StakedDegenerusStonk.sol:584
uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;
```

- **roll range:** `roll` is `uint16` sourced from `RedemptionPeriod.roll` (line 579: `uint16 roll = period.roll;`). Set in `resolveRedemptionPeriod` (line 557-560) which receives `roll` from the AdvanceModule. The AdvanceModule generates roll in range [25, 175] via `25 + (rng % 151)`.
- **Overflow check:** `claim.ethValueOwed` is `uint96` (max 7.9e28). `roll` is `uint16` (max 65535, actual max 175). Product: `7.9e28 * 175 = 1.38e31`, well within `uint256.max` (1.15e77). No overflow possible.
- **Division:** Integer division by 100 truncates toward zero. The truncated remainder (up to 99 wei) is not accounted for -- this is dust loss by design and is <= 1 wei per ETH of claim value.

#### 2. Split Logic (Lines 592-594)

```solidity
// StakedDegenerusStonk.sol:592-594 (else branch, !isGameOver)
ethDirect = totalRolledEth / 2;
lootboxEth = totalRolledEth - ethDirect;
```

**Arithmetic proof of conservation:**

Let `x = totalRolledEth` (any non-negative uint256).

```
ethDirect     = floor(x / 2)
lootboxEth    = x - floor(x / 2)

ethDirect + lootboxEth
  = floor(x / 2) + (x - floor(x / 2))
  = x
```

This identity holds for ALL non-negative integers. The `floor(x/2) + (x - floor(x/2)) = x` cancellation is algebraically exact.

**Rounding behavior:**
- Even `totalRolledEth` (e.g., 100): `ethDirect = 50`, `lootboxEth = 50`. Equal split.
- Odd `totalRolledEth` (e.g., 101): `ethDirect = 50`, `lootboxEth = 51`. Extra 1 wei goes to lootbox.

**Conservation: ethDirect + lootboxEth == totalRolledEth for ALL values.** Proven.

#### 3. Lootbox Resolution Call (Lines 619-624)

```solidity
// StakedDegenerusStonk.sol:620-624
if (lootboxEth != 0) {
    uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0;
    uint256 rngWord = game.rngWordForDay(claimPeriodIndex);
    uint256 entropy = uint256(keccak256(abi.encode(rngWord, player)));
    game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore);
}
```

- **Guard:** `if (lootboxEth != 0)` on line 620 prevents spurious calls. `lootboxEth` is only non-zero when `isGameOver` is false (line 594 only reached in `else` branch at line 592). When `isGameOver` is true, `lootboxEth` retains its default `uint256` value of 0, so the guard prevents the call. SAFE.
- **Activity score reversal (line 621):** `claimActivityScore > 0 ? claimActivityScore - 1 : 0` correctly reverses the `+1` encoding from storage (line 761: `uint16(game.playerActivityScore(beneficiary)) + 1`). The `> 0` check prevents underflow on the subtraction. The `0` fallback handles the theoretical case where `activityScore` was never set (should not occur in practice since `_submitGamblingClaimFrom` always sets it on line 760-762, but the guard is defensive). SAFE.
- **Entropy derivation (lines 622-623):** Uses `game.rngWordForDay(claimPeriodIndex)` to get the VRF-derived entropy for the claim's period, then hashes with the player address for per-player uniqueness. This is standard entropy derivation -- each player gets a deterministic but unique entropy from the same VRF word. SAFE.

#### 4. pendingRedemptionEthValue Deduction (Line 609)

```solidity
// StakedDegenerusStonk.sol:609
pendingRedemptionEthValue -= totalRolledEth;
```

**Context:** This releases the FULL segregated amount (both direct and lootbox portions). Since `ethDirect + lootboxEth == totalRolledEth`, deducting `totalRolledEth` correctly releases both halves from the segregated pool.

**Underflow analysis (CRITICAL CHECK):**

The concern: when `roll > 100`, `totalRolledEth = (ethValueOwed * roll) / 100 > ethValueOwed`. But `pendingRedemptionEthValue` originally had only `ethValueOwed` added (line 741). Could aggregate deductions exceed the aggregate balance?

**Resolution via resolveRedemptionPeriod (line 546):**

```solidity
// StakedDegenerusStonk.sol:546
pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;
```

Where `rolledEth = (pendingRedemptionEthBase * roll) / 100` (line 545).

This line adjusts `pendingRedemptionEthValue` from face-value to rolled-value at resolution time. After resolution:

```
pendingRedemptionEthValue_after = pendingRedemptionEthValue_before
                                 - pendingRedemptionEthBase
                                 + floor(pendingRedemptionEthBase * roll / 100)
```

The base is the sum of all individual `ethValueOwed` values for the period:
```
pendingRedemptionEthBase = sum_i(ethValueOwed_i)
```

After resolution, the rolled amount added to `pendingRedemptionEthValue` is:
```
rolledEth = floor(sum_i(ethValueOwed_i) * roll / 100)
```

Each individual claim deducts:
```
totalRolledEth_i = floor(ethValueOwed_i * roll / 100)
```

**Key inequality:** For non-negative integers `a`, `b`, and positive integer `d`:
```
floor(a/d) + floor(b/d) <= floor((a+b)/d)
```

Therefore:
```
sum_i( floor(ethValueOwed_i * roll / 100) ) <= floor( sum_i(ethValueOwed_i) * roll / 100 )
```

The total deducted from individual claims is always <= the total added during resolution. **No underflow is possible.** The difference (at most `n-1` wei for `n` claims in the period) is rounding dust that remains in `pendingRedemptionEthValue` permanently, which is harmless (it slightly over-reserves, benefiting solvency).

**Numerical example:**
- 3 claimants: ethValueOwed = [53, 47, 100] wei. Base = 200 wei.
- roll = 175.
- Resolution: `rolledEth = floor(200 * 175 / 100) = 350`. Added to pendingRedemptionEthValue.
- Claims: `floor(53*175/100) + floor(47*175/100) + floor(100*175/100) = 92 + 82 + 175 = 349`.
- Net: 350 - 349 = 1 wei dust remains. No underflow.

**Verdict on line 609: SAFE.** The checked subtraction (`-=`) will revert on underflow (Solidity 0.8.34), but underflow cannot occur due to the floor-division inequality.

### REDM-01 Summary

All four audit points are SAFE:
1. `totalRolledEth` computation: no overflow, correct arithmetic
2. 50/50 split: conservation algebraically proven (ethDirect + lootboxEth == totalRolledEth)
3. Lootbox resolution: correct guards, correct activity score reversal
4. `pendingRedemptionEthValue` deduction: no underflow due to floor-division inequality

---

## REDM-02: gameOver Bypass

### Verdict: SAFE

GameOver burns bypass lootbox entirely. The `claimRedemption` path routes 100% to direct ETH when `isGameOver` is true. The `_deterministicBurnFrom` path provides pure ETH/stETH with no BURNIE or lootbox allocation.

### Evidence

#### 1. claimRedemption gameOver Branch (Line 590)

```solidity
// StakedDegenerusStonk.sol:587-595
bool isGameOver = game.gameOver();
uint256 ethDirect;
uint256 lootboxEth;
if (isGameOver) {
    ethDirect = totalRolledEth;
} else {
    ethDirect = totalRolledEth / 2;
    lootboxEth = totalRolledEth - ethDirect;
}
```

- **`ethDirect = totalRolledEth`**: 100% of rolled ETH goes to direct payout. SAFE.
- **`lootboxEth` remains 0**: Declared as `uint256 lootboxEth;` on line 589 -- default value is 0. The `if (isGameOver)` branch never assigns to `lootboxEth`. SAFE.
- **`resolveRedemptionLootbox` never called**: The guard on line 620 (`if (lootboxEth != 0)`) prevents the call because `lootboxEth == 0` when `isGameOver == true`. SAFE.
- **No lootbox-related side effects**: The lootbox chunk loop in `Game.resolveRedemptionLootbox` (lines 1825-1844) is never entered. No tickets or BURNIE are awarded. SAFE.

#### 2. _deterministicBurnFrom (Lines 479-521)

```solidity
// StakedDegenerusStonk.sol:479-521
function _deterministicBurnFrom(address beneficiary, address burnFrom, uint256 amount)
    private returns (uint256 ethOut, uint256 stethOut, uint256)
```

**Entry conditions verified:**
- `burn()` (line 443-450): Calls `_deterministicBurn` (which calls `_deterministicBurnFrom`) only when `game.gameOver()` is true (line 444). Otherwise enters gambling path. SAFE.
- `burnWrapped()` (line 460-468): Calls `_deterministicBurnFrom` only when `game.gameOver()` is true (line 462). Otherwise enters gambling path. SAFE.

**No BURNIE payout:**
```solidity
// StakedDegenerusStonk.sol:519-520
// No BURNIE payout for gameOver burns -- pure ETH/stETH only
emit Burn(beneficiary, amount, ethOut, stethOut, 0);
```

The function signature returns `(uint256 ethOut, uint256 stethOut, uint256)` -- the third return is always 0 (no `burnieOut` assignment anywhere in the function body). The `Burn` event emits `0` for `burnieOut`. SAFE.

**No call to _submitGamblingClaimFrom or resolveRedemptionLootbox:**
The function body (lines 479-521) contains:
- Balance checks, supply computation
- `address(this).balance` + `steth.balanceOf` + `_claimableWinnings()` for total value
- Token burn (lines 490-494)
- `game.claimWinnings` fallback (lines 496-500)
- ETH/stETH transfer to beneficiary (lines 502-517)
- Burn event (lines 519-520)

No call to `_submitGamblingClaimFrom`, `resolveRedemptionLootbox`, `coinflip`, or any gambling-related function. SAFE.

**pendingRedemptionEthValue deducted from totalMoney (line 487, CP-08 fix):**
```solidity
// StakedDegenerusStonk.sol:487
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
```

This correctly excludes ETH reserved for pending gambling burn claimants from the deterministic burn computation. Without this subtraction (the CP-08 vulnerability), post-gameOver burns would consume ETH reserved for gambling claimants. The fix ensures deterministic burns only distribute unreserved backing assets. SAFE.

#### 3. gameOver Transition During Active Claims (Pitfall 6)

**Scenario:** Player submits gambling burn during active game (enters `_submitGamblingClaimFrom`), game advances, gameOver triggers before or during resolution, player calls `claimRedemption()`.

**Analysis:**

1. **Burn submission (during game):** Player calls `burn(amount)` while `game.gameOver() == false`. `_submitGamblingClaimFrom` records the claim. This is valid.

2. **Resolution:** `advanceGame` calls `resolveRedemptionPeriod` with a roll [25-175]. If gameOver triggers during this advance (via `_gameOverEntropy`), the redemption period is still resolved (CP-06 fix: lines 862, 891 in AdvanceModule).

3. **Claim (after gameOver):** Player calls `claimRedemption()`. `game.gameOver()` now returns true. Line 590: `ethDirect = totalRolledEth` (100% direct ETH). No lootbox split.

**Impact on player:**
- Player receives 100% of rolled ETH as direct payout instead of 50/50 split.
- This is **favorable to the player** (they get full ETH instead of half ETH + lootbox rewards).
- The lootbox rewards (tickets, BURNIE bonuses) are forfeited, but the ETH value equivalent goes directly to the player.

**Impact on protocol:**
- `resolveRedemptionLootbox` is never called, so no ETH is debited from `claimableWinnings[SDGNRS]` or credited to `futurePrizePool`.
- The ETH comes from `pendingRedemptionEthValue` segregation (line 609 deduction) and is paid via `_payEth` (line 635).
- Since the lootbox path is skipped, no internal reclassification occurs. The ETH stays in sDGNRS's balance/claimable and is paid directly.

**Safety:** This is intentional design behavior. Post-gameOver, there are no future levels to spend tickets on, and no future prize pools to credit. Routing 100% to direct ETH is the correct behavior. The player benefits from the full rolled amount without lootbox intermediation.

**BURNIE during gameOver transition:**
- `burniePayout` still depends on coinflip resolution (lines 598-606). The coinflip resolves independently of gameOver.
- If the coinflip is resolved and the player won, they still get BURNIE (lines 628-629).
- If the coinflip is unresolved, partial claim logic applies: ETH is cleared (`claim.ethValueOwed = 0`) but BURNIE portion is kept for a second claim (lines 614-617).

This is correct -- the split-claim design (CP-07 fix) handles the coinflip dependency independently of the gameOver state. SAFE.

### REDM-02 Summary

All three audit points are SAFE:
1. `claimRedemption` gameOver branch: 100% direct ETH, no lootbox call
2. `_deterministicBurnFrom`: pure ETH/stETH, no BURNIE, no gambling, pendingRedemptionEthValue excluded (CP-08)
3. gameOver transition during active claims: intentional design, favorable to player, fully safe

---

## Verdicts

| Requirement | Verdict | Summary |
|-------------|---------|---------|
| REDM-01 | **SAFE** | 50/50 split is algebraically correct. ethDirect + lootboxEth == totalRolledEth for all inputs. Rounding extra wei goes to lootbox. pendingRedemptionEthValue deduction is underflow-safe due to floor-division inequality. |
| REDM-02 | **SAFE** | gameOver bypass is correct. claimRedemption routes 100% to direct ETH with no lootbox call. _deterministicBurnFrom is pure ETH/stETH with zero BURNIE. gameOver transition during active claims is safe by design. |

## New Findings

### FINDING (INFO): Rounding Dust Accumulation in pendingRedemptionEthValue

**Location:** StakedDegenerusStonk.sol, line 609 (claim deduction) vs line 546 (period resolution)

**Description:** When multiple claimants share a period, the sum of individual `floor(ethValueOwed_i * roll / 100)` deductions is less than the aggregate `floor(base * roll / 100)` added during resolution. The difference (at most `n-1` wei for `n` claimants) accumulates permanently in `pendingRedemptionEthValue`.

**Impact:** Negligible. Over thousands of periods, accumulated dust could reach a few thousand wei (fractions of a cent). This slightly over-reserves ETH in `_deterministicBurnFrom` (line 487) and `_submitGamblingClaimFrom` (line 724), meaning deterministic burns and new gambling claims see marginally less `totalMoney` than the true unreserved amount.

**Severity:** INFO -- no economic impact, no exploit vector, no user harm.

**Recommendation:** None required. The dust accumulation is a natural consequence of integer arithmetic and is harmless. If desired, a periodic dust sweep could set `pendingRedemptionEthValue = 0` when no claims exist, but this is unnecessary given the magnitude.

---

## Open Questions Resolution

### Pitfall 5 (Rounding)

**Confirmed:** `ethDirect + lootboxEth == totalRolledEth` always holds. The algebraic proof `floor(x/2) + (x - floor(x/2)) = x` is universally true for non-negative integers. The extra wei on odd values goes to `lootboxEth`. No rounding loss occurs in the split itself.

### Pitfall 6 (gameOver Transition)

**Documented:** When gameOver triggers between burn submission and claim, `claimRedemption()` detects `game.gameOver() == true` and routes 100% to direct ETH. This is safe and favorable to the player. The lootbox path is never entered (guard at line 620). The coinflip/BURNIE path operates independently. This is a deliberate design decision -- post-gameOver, there are no future levels for lootbox rewards, so 100% direct ETH is correct.

### Line 609 Underflow Risk

**Resolved:** No underflow is possible. The `resolveRedemptionPeriod` function (line 546) adjusts `pendingRedemptionEthValue` by replacing the base with the rolled aggregate. Individual claim deductions are bounded by the floor-division inequality:

```
sum_i(floor(a_i * r / d)) <= floor(sum_i(a_i) * r / d)
```

The aggregate deduction from claims never exceeds the aggregate addition from resolution. The checked subtraction on line 609 provides a runtime safety net, but it will never revert under correct program flow.
