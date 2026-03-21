# Phase 47: Gas Analysis

## Variable Liveness Analysis (GAS-01)

Analysis of the 7 new state variables added to StakedDegenerusStonk.sol for the gambling burn / redemption system (declared at lines 193-200). Each variable is traced for every write, read, and delete site through the contract.

### Summary Table

| Variable | Type | Slot | Write Sites | Read Sites | Delete Sites | Verdict |
|----------|------|------|-------------|------------|--------------|---------|
| pendingRedemptionEthValue | uint256 | 9 | 3 | 5 | 0 | ALIVE |
| pendingRedemptionBurnie | uint256 | 10 | 2 | 3 | 0 | ALIVE |
| pendingRedemptionEthBase | uint256 | 11 | 2 | 4 | 0 | ALIVE |
| pendingRedemptionBurnieBase | uint256 | 12 | 2 | 4 | 0 | ALIVE |
| redemptionPeriodSupplySnapshot | uint256 | 13 | 1 | 1 | 0 | ALIVE |
| redemptionPeriodIndex | uint48 | 14 | 1 | 2 | 0 | ALIVE |
| redemptionPeriodBurned | uint256 | 15 | 2 | 1 | 0 | ALIVE |

### 1. pendingRedemptionEthValue

**Declaration:** StakedDegenerusStonk.sol:193 -- `uint256 public pendingRedemptionEthValue;`

**Write sites:**
- StakedDegenerusStonk.sol:553 -- `resolveRedemptionPeriod`: `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` (adjusts segregated ETH by roll percentage)
- StakedDegenerusStonk.sol:599 -- `claimRedemption`: `pendingRedemptionEthValue -= ethPayout` (releases ETH segregation when player claims)
- StakedDegenerusStonk.sol:712 -- `_submitGamblingClaimFrom`: `pendingRedemptionEthValue += ethValueOwed` (segregates proportional ETH for new claim)

**Read sites:**
- StakedDegenerusStonk.sol:477 -- `_deterministicBurnFrom`: `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (excludes segregated ETH from deterministic burn calculation)
- StakedDegenerusStonk.sol:553 -- `resolveRedemptionPeriod`: read as part of the ETH adjustment computation (also a write site)
- StakedDegenerusStonk.sol:633 -- `previewBurn`: `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (excludes segregated ETH from preview)
- StakedDegenerusStonk.sol:637 -- `previewBurn`: `if (ethAvailable > pendingRedemptionEthValue)` (determines available ETH for preview)
- StakedDegenerusStonk.sol:638 -- `previewBurn`: `ethAvailable -= pendingRedemptionEthValue` (subtract segregated from available)
- StakedDegenerusStonk.sol:695 -- `_submitGamblingClaimFrom`: `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue` (excludes segregated ETH when computing new claim's share)

**Delete sites:** None (decremented on claim, never bulk-zeroed)

**Verdict:** ALIVE -- Core segregation accounting variable for ETH. Removing it would break solvency: deterministic burns and gambling claims would double-count ETH reserved for pending redemptions.

---

### 2. pendingRedemptionBurnie

**Declaration:** StakedDegenerusStonk.sol:194 -- `uint256 internal pendingRedemptionBurnie;`

**Write sites:**
- StakedDegenerusStonk.sol:560 -- `resolveRedemptionPeriod`: `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` (releases BURNIE reservation when period is resolved, since BURNIE is now handled via coinflip)
- StakedDegenerusStonk.sol:714 -- `_submitGamblingClaimFrom`: `pendingRedemptionBurnie += burnieOwed` (reserves proportional BURNIE for new claim)

**Read sites:**
- StakedDegenerusStonk.sol:482 -- `_deterministicBurnFrom`: `totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie` (excludes reserved BURNIE from deterministic burn)
- StakedDegenerusStonk.sol:651 -- `previewBurn`: `totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie` (excludes reserved BURNIE from preview)
- StakedDegenerusStonk.sol:661 -- `burnieReserve`: `return burnieBal + claimableBurnie - pendingRedemptionBurnie` (net BURNIE reserve view)
- StakedDegenerusStonk.sol:701 -- `_submitGamblingClaimFrom`: `totalBurnie = burnieBal + claimableBurnie - pendingRedemptionBurnie` (excludes reserved BURNIE when computing new claim's share)

**Delete sites:** None (decremented on resolution, never bulk-zeroed)

**Verdict:** ALIVE -- Core segregation accounting variable for BURNIE. Removing it would allow deterministic burns and new gambling claims to consume BURNIE already reserved for pending redemptions.

---

### 3. pendingRedemptionEthBase

**Declaration:** StakedDegenerusStonk.sol:195 -- `uint256 internal pendingRedemptionEthBase;`

**Write sites:**
- StakedDegenerusStonk.sol:554 -- `resolveRedemptionPeriod`: `pendingRedemptionEthBase = 0` (zeroes after applying roll to the accumulated base)
- StakedDegenerusStonk.sol:713 -- `_submitGamblingClaimFrom`: `pendingRedemptionEthBase += ethValueOwed` (accumulates ETH base for current unresolved period)

**Read sites:**
- StakedDegenerusStonk.sol:537 -- `hasPendingRedemptions`: `pendingRedemptionEthBase != 0` (check if unresolved period exists)
- StakedDegenerusStonk.sol:549 -- `resolveRedemptionPeriod`: `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return 0` (early exit if nothing to resolve)
- StakedDegenerusStonk.sol:552 -- `resolveRedemptionPeriod`: `rolledEth = (pendingRedemptionEthBase * roll) / 100` (compute rolled ETH from base)
- StakedDegenerusStonk.sol:553 -- `resolveRedemptionPeriod`: used in `pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` (adjust segregation from base to rolled)

**Delete sites:** None (zeroed via assignment `= 0`, not Solidity `delete`)

**Verdict:** ALIVE -- Tracks the unresolved period's ETH accumulator. Without it, `resolveRedemptionPeriod` cannot compute the rolled ETH value or adjust the global segregation from base to rolled.

---

### 4. pendingRedemptionBurnieBase

**Declaration:** StakedDegenerusStonk.sol:196 -- `uint256 internal pendingRedemptionBurnieBase;`

**Write sites:**
- StakedDegenerusStonk.sol:561 -- `resolveRedemptionPeriod`: `pendingRedemptionBurnieBase = 0` (zeroes after computing rolled BURNIE for coinflip credit)
- StakedDegenerusStonk.sol:715 -- `_submitGamblingClaimFrom`: `pendingRedemptionBurnieBase += burnieOwed` (accumulates BURNIE base for current unresolved period)

**Read sites:**
- StakedDegenerusStonk.sol:537 -- `hasPendingRedemptions`: `pendingRedemptionBurnieBase != 0` (check if unresolved period exists)
- StakedDegenerusStonk.sol:549 -- `resolveRedemptionPeriod`: `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return 0` (early exit)
- StakedDegenerusStonk.sol:557 -- `resolveRedemptionPeriod`: `burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100` (compute rolled BURNIE)
- StakedDegenerusStonk.sol:560 -- `resolveRedemptionPeriod`: `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` (release base from total reservation)

**Delete sites:** None (zeroed via assignment `= 0`)

**Verdict:** ALIVE -- Tracks the unresolved period's BURNIE accumulator. Without it, `resolveRedemptionPeriod` cannot compute BURNIE to credit to the coinflip or release the BURNIE reservation.

---

### 5. redemptionPeriodSupplySnapshot

**Declaration:** StakedDegenerusStonk.sol:198 -- `uint256 internal redemptionPeriodSupplySnapshot;`

**Write sites:**
- StakedDegenerusStonk.sol:682 -- `_submitGamblingClaimFrom`: `redemptionPeriodSupplySnapshot = totalSupply` (snapshots supply at start of new period)

**Read sites:**
- StakedDegenerusStonk.sol:686 -- `_submitGamblingClaimFrom`: `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient()` (enforces 50% supply cap per period)

**Delete sites:** None (overwritten on new period start, never zeroed)

**Verdict:** ALIVE -- Enforces the 50% supply cap per redemption period. Without it, the cap check at line 686 has no reference point, allowing unbounded burns within a single period.

---

### 6. redemptionPeriodIndex

**Declaration:** StakedDegenerusStonk.sol:199 -- `uint48 internal redemptionPeriodIndex;`

**Write sites:**
- StakedDegenerusStonk.sol:683 -- `_submitGamblingClaimFrom`: `redemptionPeriodIndex = currentPeriod` (sets current period index on new period boundary)

**Read sites:**
- StakedDegenerusStonk.sol:548 -- `resolveRedemptionPeriod`: `uint48 period = redemptionPeriodIndex` (reads period index to store resolution result in `redemptionPeriods[period]`)
- StakedDegenerusStonk.sol:681 -- `_submitGamblingClaimFrom`: `if (redemptionPeriodIndex != currentPeriod)` (detects period boundary to reset accumulators)

**Delete sites:** None (overwritten, never zeroed)

**Verdict:** ALIVE -- Tracks which day/period the current accumulation batch belongs to. Without it, the contract cannot detect period boundaries (line 681) or map resolution results to the correct period (line 548).

---

### 7. redemptionPeriodBurned

**Declaration:** StakedDegenerusStonk.sol:200 -- `uint256 internal redemptionPeriodBurned;`

**Write sites:**
- StakedDegenerusStonk.sol:684 -- `_submitGamblingClaimFrom`: `redemptionPeriodBurned = 0` (reset on new period start)
- StakedDegenerusStonk.sol:687 -- `_submitGamblingClaimFrom`: `redemptionPeriodBurned += amount` (accumulates burned amount within current period)

**Read sites:**
- StakedDegenerusStonk.sol:686 -- `_submitGamblingClaimFrom`: `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient()` (enforces 50% supply cap per period)

**Delete sites:** None (zeroed via assignment `= 0` on period boundary)

**Verdict:** ALIVE -- Tracks how much sDGNRS has been burned in the current period to enforce the 50% supply cap. Without it, the cap check at line 686 cannot compare accumulated burns against the snapshot.

---

## Liveness Summary

| Variable | Verdict | Rationale |
|----------|---------|-----------|
| pendingRedemptionEthValue | ALIVE | Core ETH segregation accounting; read by 4 functions, written by 3 |
| pendingRedemptionBurnie | ALIVE | Core BURNIE reservation accounting; read by 4 functions, written by 2 |
| pendingRedemptionEthBase | ALIVE | Unresolved period ETH accumulator; required for roll computation and segregation adjustment |
| pendingRedemptionBurnieBase | ALIVE | Unresolved period BURNIE accumulator; required for rolled BURNIE and reservation release |
| redemptionPeriodSupplySnapshot | ALIVE | 50% supply cap enforcement; no alternative reference for the per-period bound |
| redemptionPeriodIndex | ALIVE | Period boundary detection and resolution mapping; only mechanism for period tracking |
| redemptionPeriodBurned | ALIVE | Per-period burn accumulator; no alternative for 50% cap enforcement |

**GAS-04 Status:** CLOSED -- no dead variables found. All 7 variables are actively used in the gambling burn lifecycle. Each variable has at least one write site and at least one read site, with clear functional purpose that cannot be derived from other state. No variables can be eliminated.

---

## Current Storage Layout

Storage slot assignments for StakedDegenerusStonk.sol, derived from declaration order and Solidity packing rules.

```
Slot  Variable                          Type        Bytes  Wasted  Category
----  --------                          ----        -----  ------  --------
0     totalSupply                       uint256     32     0       ERC20
1     balanceOf                         mapping     32     0       ERC20
2     poolBalances[0] (Whale)           uint256     32     0       Pool
3     poolBalances[1] (Affiliate)       uint256     32     0       Pool
4     poolBalances[2] (Lootbox)         uint256     32     0       Pool
5     poolBalances[3] (Reward)          uint256     32     0       Pool
6     poolBalances[4] (Earlybird)       uint256     32     0       Pool
7     pendingRedemptions                mapping     32     0       Gambling Burn
8     redemptionPeriods                 mapping     32     0       Gambling Burn
9     pendingRedemptionEthValue         uint256     32     0       Gambling Burn
10    pendingRedemptionBurnie           uint256     32     0       Gambling Burn
11    pendingRedemptionEthBase          uint256     32     0       Gambling Burn
12    pendingRedemptionBurnieBase       uint256     32     0       Gambling Burn
13    redemptionPeriodSupplySnapshot    uint256     32     0       Gambling Burn
14    redemptionPeriodIndex             uint48      6      26      Gambling Burn
15    redemptionPeriodBurned            uint256     32     0       Gambling Burn
```

**Total slots used:** 16 (slots 0-15)
**Total wasted bytes in gambling burn state:** 26 (slot 14 only)

### PendingRedemption Struct Layout (per-user, in mapping at slot 7)

```
Struct Slot  Field           Type      Bytes  Wasted
-----------  -----           ----      -----  ------
0            ethValueOwed    uint256   32     0
1            burnieOwed      uint256   32     0
2            periodIndex     uint48    6      26
```

**3 slots per user, 26 bytes wasted per user in slot 2.**

### RedemptionPeriod Struct Layout (per-period, in mapping at slot 8)

```
Struct Slot  Field     Type    Bytes  Wasted
-----------  -----     ----    -----  ------
0            roll      uint16  2      0
0            flipDay   uint48  6      24 (already packed -- good)
```

**1 slot per period, already efficiently packed. No optimization needed.**

---

## Storage Packing Opportunities (GAS-02)

### Opportunity 1: Pack redemptionPeriodIndex + redemptionPeriodBurned (save 1 storage slot)

**Current layout:**
- Slot 14: `redemptionPeriodIndex` (uint48, 6 bytes) -- 26 bytes wasted
- Slot 15: `redemptionPeriodBurned` (uint256, 32 bytes)

**Proposed layout:**
- Slot 14: `redemptionPeriodIndex` (uint48, 6 bytes) + `redemptionPeriodBurned` (uint208, 26 bytes)

**Bit-width safety proof:**
- `redemptionPeriodBurned` max value = `totalSupply / 2` (enforced at StakedDegenerusStonk.sol:686)
- `totalSupply` starts at `INITIAL_SUPPLY` = 1,000,000,000,000 * 1e18 = 1e30 (declared at StakedDegenerusStonk.sol:207)
- `totalSupply` can only decrease (burns reduce it, no mint function after constructor)
- Max `redemptionPeriodBurned` = 1e30 / 2 = 5e29
- 5e29 requires ceil(log2(5e29)) = 100 bits
- uint208 max = 2^208 = ~4.1e62
- 5e29 < 4.1e62: fits with 108 bits of headroom
- The 50% supply cap at line 686 guarantees this bound and is enforced by a revert

**Co-access pattern:** Both variables are always accessed together within `_submitGamblingClaimFrom`:
- StakedDegenerusStonk.sol:681 -- read `redemptionPeriodIndex` (period boundary check)
- StakedDegenerusStonk.sol:682 -- conditional write to `redemptionPeriodSupplySnapshot` (not packed)
- StakedDegenerusStonk.sol:683 -- write `redemptionPeriodIndex = currentPeriod`
- StakedDegenerusStonk.sol:684 -- write `redemptionPeriodBurned = 0`
- StakedDegenerusStonk.sol:686 -- read `redemptionPeriodBurned` (cap check)
- StakedDegenerusStonk.sol:687 -- write `redemptionPeriodBurned += amount`

`redemptionPeriodIndex` is also read independently in `resolveRedemptionPeriod` (line 548), but that path does not access `redemptionPeriodBurned`. Packing still saves a slot on the hot path (`_submitGamblingClaimFrom`), and the cold read in `resolveRedemptionPeriod` adds only a masking cost (~3 gas).

**Gas savings (theoretical):**
- Cold path (first `_submitGamblingClaimFrom` call in a transaction): 1 SSTORE saved (20,000 gas) + 1 SLOAD saved (2,100 gas) = 22,100 gas
- Warm path (subsequent calls in same transaction): 1 SSTORE saved (5,000 gas) + 1 SLOAD saved (100 gas) = 5,100 gas

**Risk:** LOW. Variables always co-accessed on hot path. uint208 has 108 bits of headroom. No external interface exposes `redemptionPeriodBurned`.

**Code change:**
```solidity
// BEFORE (2 slots):
uint48  internal redemptionPeriodIndex;    // slot 14
uint256 internal redemptionPeriodBurned;   // slot 15

// AFTER (1 slot):
uint48  internal redemptionPeriodIndex;    // slot 14, offset 0
uint208 internal redemptionPeriodBurned;   // slot 14, offset 6
```

No other code changes required -- Solidity handles the packing automatically. All arithmetic on `redemptionPeriodBurned` uses `+=`, `=`, and comparison operators which work identically with uint208. The `/ 2` in the cap check (line 686) also works correctly since uint208 supports division.

---

### Opportunity 2: Pack pendingRedemptionEthBase + pendingRedemptionBurnieBase (save 1 storage slot)

**Current layout:**
- Slot 11: `pendingRedemptionEthBase` (uint256, 32 bytes)
- Slot 12: `pendingRedemptionBurnieBase` (uint256, 32 bytes)

**Proposed layout:**
- Slot 11: `pendingRedemptionEthBase` (uint128, 16 bytes) + `pendingRedemptionBurnieBase` (uint128, 16 bytes)

**Bit-width safety proof:**
- `pendingRedemptionEthBase`: accumulates `ethValueOwed` per period. Max = `(totalMoney * totalSupply/2) / totalSupply` = `totalMoney / 2`. Realistic max totalMoney: ~100,000 ETH = 1e23 wei. Max value = 5e22 (87 bits). Even with 10x growth: 1e24 wei = 87 bits. uint128 max = 2^128 = 3.4e38. Fits with 41+ bits of headroom.
- `pendingRedemptionBurnieBase`: accumulates `burnieOwed` per period. Max = `(totalBurnie * totalSupply/2) / totalSupply` = `totalBurnie / 2`. BURNIE total supply = 1e30 (similar token economics). Max value = 5e29 (100 bits). uint128 max = 3.4e38. Fits with 28 bits of headroom.
- Both are bounded by the 50% supply cap per period (StakedDegenerusStonk.sol:686) AND by total contract holdings (ETH + stETH + claimables for ETH side, BURNIE balance + claimables for BURNIE side).
- `INITIAL_SUPPLY` is a private constant (StakedDegenerusStonk.sol:207) with no upgrade path -- max cannot increase.

**Co-access pattern:** Both variables are always read and written together:
- StakedDegenerusStonk.sol:537 -- `hasPendingRedemptions`: both read (`!= 0` check)
- StakedDegenerusStonk.sol:549 -- `resolveRedemptionPeriod`: both read (early exit check `== 0`)
- StakedDegenerusStonk.sol:552-554 -- `resolveRedemptionPeriod`: `pendingRedemptionEthBase` read (compute rolled ETH) then written `= 0`
- StakedDegenerusStonk.sol:557 -- `resolveRedemptionPeriod`: `pendingRedemptionBurnieBase` read (compute rolled BURNIE)
- StakedDegenerusStonk.sol:560-561 -- `resolveRedemptionPeriod`: `pendingRedemptionBurnieBase` read (subtract from total) then written `= 0`
- StakedDegenerusStonk.sol:713 -- `_submitGamblingClaimFrom`: `pendingRedemptionEthBase += ethValueOwed`
- StakedDegenerusStonk.sol:715 -- `_submitGamblingClaimFrom`: `pendingRedemptionBurnieBase += burnieOwed`

They are never accessed independently. Every function that touches one also touches the other.

**Gas savings (theoretical):**
- Cold path: 1 SSTORE saved (20,000 gas) + 1 SLOAD saved (2,100 gas) = 22,100 gas per function call
- Warm path: 1 SSTORE saved (5,000 gas) + 1 SLOAD saved (100 gas) = 5,100 gas
- Applies to: `hasPendingRedemptions` (read only, saves 1 SLOAD), `resolveRedemptionPeriod` (read+write, saves SLOAD+SSTORE), `_submitGamblingClaimFrom` (write only, saves 1 SSTORE)

**Risk:** LOW-MEDIUM. uint128 is safe for all realistic values. Theoretical max for BURNIE base is ~100 bits, well within 128-bit capacity. `INITIAL_SUPPLY` is immutable constant so max cannot increase. The only conceivable risk is if the protocol held > 3.4e20 ETH (~$680 trillion at $2000/ETH), which is physically impossible.

**Code change:**
```solidity
// BEFORE (2 slots, slots 11-12):
uint256 internal pendingRedemptionEthBase;      // slot 11
uint256 internal pendingRedemptionBurnieBase;    // slot 12

// AFTER (1 slot):
uint128 internal pendingRedemptionEthBase;       // slot 11, offset 0
uint128 internal pendingRedemptionBurnieBase;    // slot 11, offset 16
```

Solidity 0.8.x overflow protection applies to uint128 arithmetic identically to uint256. The `+= ethValueOwed` and `+= burnieOwed` operations will correctly revert on overflow. The `= 0` assignments work identically. The `-= pendingRedemptionBurnieBase` subtraction at line 560 operates on `pendingRedemptionBurnie` (uint256) so no truncation risk there -- the subtracted value is already uint128-bounded.

Note: `pendingRedemptionEthBase` and `pendingRedemptionBurnieBase` appear in arithmetic with uint256 values (e.g., line 552: `pendingRedemptionEthBase * roll`). Solidity will widen uint128 to uint256 for the multiplication, so no precision loss occurs.

---

### Opportunity 3: Pack PendingRedemption struct (save 1 slot per user)

**Current layout (3 slots per user):**
```solidity
struct PendingRedemption {
    uint256 ethValueOwed;   // 32 bytes, struct slot 0
    uint256 burnieOwed;     // 32 bytes, struct slot 1
    uint48  periodIndex;    // 6 bytes, struct slot 2 (26 bytes wasted)
}
```

**Proposed layout (2 slots per user):**
```solidity
struct PendingRedemption {
    uint128 ethValueOwed;   // 16 bytes \  struct slot 0
    uint128 burnieOwed;     // 16 bytes /
    uint48  periodIndex;    // 6 bytes, struct slot 1
}
```

**Bit-width safety proof:**
- `ethValueOwed` per user: bounded by the user's proportional share of total ETH. Even if a single user burned 50% of total supply (the period cap), their max `ethValueOwed` = `totalMoney / 2`. Realistic max totalMoney = ~1e23 wei (100K ETH). Max per-user ethValueOwed = 5e22 (87 bits). uint128 max = 3.4e38. Fits with 41+ bits of headroom.
- `burnieOwed` per user: bounded by the user's proportional share of total BURNIE. Max = `totalBurnie / 2`. Realistic max totalBurnie = ~1e30. Max per-user burnieOwed = 5e29 (100 bits). uint128 max = 3.4e38. Fits with 28 bits of headroom.
- Individual user claims are strictly smaller than the period accumulator totals (which are themselves bounded by supply cap).
- The `+=` accumulation (StakedDegenerusStonk.sol:722-723) only accumulates within the SAME period for the SAME user. A user can only have one active claim (UnresolvedClaim revert at line 720). Within a period, a user can call `burn()` multiple times, each adding to their claim. But the total across all users is bounded by the 50% supply cap.

**Co-access pattern:**
- StakedDegenerusStonk.sol:578 -- `claimRedemption`: read `claim.periodIndex` (NoClaim check)
- StakedDegenerusStonk.sol:580 -- `claimRedemption`: read `claim.periodIndex` (load period data)
- StakedDegenerusStonk.sol:590 -- `claimRedemption`: read `claim.ethValueOwed` (compute ETH payout)
- StakedDegenerusStonk.sol:595 -- `claimRedemption`: read `claim.burnieOwed` (compute BURNIE payout)
- StakedDegenerusStonk.sol:602 -- `claimRedemption`: `delete pendingRedemptions[player]` (clear all fields)
- StakedDegenerusStonk.sol:719 -- `_submitGamblingClaimFrom`: read `claim.periodIndex` (check for existing claim)
- StakedDegenerusStonk.sol:722 -- `_submitGamblingClaimFrom`: write `claim.ethValueOwed += ethValueOwed`
- StakedDegenerusStonk.sol:723 -- `_submitGamblingClaimFrom`: write `claim.burnieOwed += burnieOwed`
- StakedDegenerusStonk.sol:724 -- `_submitGamblingClaimFrom`: write `claim.periodIndex = currentPeriod`

In both functions, all three struct fields are accessed together. Packing `ethValueOwed` + `burnieOwed` into one slot means the read at lines 590+595 becomes 1 SLOAD instead of 2, and the write at lines 722+723 becomes 1 SSTORE instead of 2.

**Gas savings (theoretical):**
- Cold path: 1 SSTORE saved (20,000 gas) + 1 SLOAD saved (2,100 gas) = 22,100 gas per user operation
- Warm path: 1 SSTORE saved (5,000 gas) + 1 SLOAD saved (100 gas) = 5,100 gas
- `delete pendingRedemptions[player]` at line 602: Solidity `delete` correctly zeros all struct fields regardless of packing -- no behavior change.

**Risk:** LOW-MEDIUM. Same uint128 bounds as Opportunity 2. The `+=` accumulation at lines 722-723 works identically with uint128 since Solidity 0.8.x overflow checks still apply. The packed write requires the compiler to handle masking/shifting, which adds ~20 gas per write but saves ~5,000-20,000 gas from the eliminated slot access. Net savings are strongly positive.

**Code change:**
```solidity
// BEFORE (3 slots per user):
struct PendingRedemption {
    uint256 ethValueOwed;   // 32 bytes, slot 0
    uint256 burnieOwed;     // 32 bytes, slot 1
    uint48  periodIndex;    // 6 bytes, slot 2
}

// AFTER (2 slots per user):
struct PendingRedemption {
    uint128 ethValueOwed;   // 16 bytes \  slot 0
    uint128 burnieOwed;     // 16 bytes /
    uint48  periodIndex;    // 6 bytes, slot 1
}
```

Additional code changes required:
- StakedDegenerusStonk.sol:128 -- `RedemptionSubmitted` event: `ethValueOwed` and `burnieOwed` params should remain uint256 in the event (events are not storage-constrained). The emit at line 726 will widen uint128 to uint256 automatically.
- No changes needed to `claimRedemption` arithmetic -- lines 590 and 595 compute into local uint256 variables, so the uint128 read is widened without truncation.

---

## Packing Summary

| # | Opportunity | Slots Saved | Cold Gas Saved | Warm Gas Saved | Risk |
|---|-------------|-------------|----------------|----------------|------|
| 1 | Pack index + burned | 1 (global) | ~22,100 | ~5,100 | LOW |
| 2 | Pack ethBase + burnieBase | 1 (global) | ~22,100 | ~5,100 | LOW-MEDIUM |
| 3 | Pack PendingRedemption struct | 1 per user | ~22,100 | ~5,100 | LOW-MEDIUM |
| **Total** | | **2 global + 1/user** | **~66,300** | **~15,300** | -- |

**Combined impact on `_submitGamblingClaimFrom` (hot path):** All 3 opportunities apply to this function. A single gambling burn call touches: ethBase+burnieBase (Opp 2), index+burned (Opp 1), and PendingRedemption struct (Opp 3). With all 3 packed, the function saves 3 SSTOREs + 3 SLOADs on cold path = ~66,300 gas, or 3 SSTOREs + 3 SLOADs on warm path = ~15,300 gas.

---

## Implementation Recommendations

1. **Implement Opportunity 1 first** (lowest risk: `redemptionPeriodIndex` uint48 + `redemptionPeriodBurned` uint208). Single declaration change, no arithmetic changes needed, 108 bits of headroom.

2. **Implement Opportunity 2 second** (`pendingRedemptionEthBase` uint128 + `pendingRedemptionBurnieBase` uint128). Two declaration changes, no arithmetic changes needed, 28+ bits of headroom on the tighter bound.

3. **Implement Opportunity 3 last** (PendingRedemption struct: `ethValueOwed` uint128, `burnieOwed` uint128). Struct change, no arithmetic changes needed, same uint128 bounds as Opportunity 2. Most impactful per-user.

4. **After each change:** Run `forge build --skip test` to verify compilation, then `npm run test:unit` for regression. Only one change at a time to isolate any issues.

5. **Use `forge snapshot --diff` against GAS-03 baseline** to measure actual vs theoretical savings per opportunity. This is the authoritative measure.

6. **If any packing INCREASES gas** (possible due to `via_ir` optimizer with `optimizer_runs = 2`), revert that specific change. The optimizer is tuned for deployment size, not runtime, so masking/shifting overhead may not be eliminated.

---

## Pitfall: via_ir Optimizer Interaction

This project uses `via_ir = true` with `optimizer_runs = 2` (configured in `foundry.toml`). This combination optimizes for deployment size over runtime gas. Storage packing introduces masking and shifting operations that the optimizer may not eliminate when `optimizer_runs` is low.

**Concrete risk:** Each packed read/write adds ~3-20 gas of masking overhead. When the SLOAD/SSTORE savings are 2,100-20,000 gas, the net is always positive. However, if the optimizer inlines poorly and generates redundant mask operations across multiple accesses in the same function, savings could be lower than theoretical.

**Mitigation:** The `forge snapshot --diff` (GAS-03 baseline) is the authoritative measure. Theoretical savings in this document are upper bounds. If actual savings are < 500 gas for any opportunity, that opportunity should be reverted as not worth the code complexity.
