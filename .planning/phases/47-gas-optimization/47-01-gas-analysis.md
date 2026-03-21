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
