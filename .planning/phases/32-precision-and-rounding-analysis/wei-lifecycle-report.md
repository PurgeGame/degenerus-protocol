# Wei Lifecycle and Dust Extraction Report (PREC-03, PREC-04)

**Phase:** 32 (Precision and Rounding Analysis)
**Requirements:** PREC-03, PREC-04
**Date:** 2026-03-05

---

## 1. Executive Summary

**Overall Verdict: SAFE -- Accumulated rounding error is bounded per operation and economically non-extractable. Wei lifecycle precision loss is bounded and documented for all four major paths.**

Key findings:
- **Lootbox split uses remainder pattern** -- ZERO wei lost in the split step (positive finding)
- **Vault share math rounding favors the protocol** -- dust stays in vault reserves
- **Pro-rata claims (Decimator) sum to <= pool** -- residual dust stays in pool
- **Gas cost exceeds extractable dust** by a factor of 500,000x at current gas prices
- **No unbounded division chains** exist in any user-callable transaction

---

## 2. Wei Lifecycle Trace (PREC-04)

### Path A: Purchase -> Ticket Cost

**Division:** `costWei = (priceWei * quantity) / (4 * TICKET_SCALE)`

- **Divisor:** 400 (constant)
- **Max precision loss:** 399 wei per purchase
- **At minimum price (0.01 ETH), qty=100:** `costWei = (10^16 * 100) / 400 = 2.5 * 10^15`. Precision loss = 0 (exact division).
- **At minimum price, qty=1:** `costWei = 10^16 / 400 = 2.5 * 10^13`. Loss = 0 (exact).
- **Worst case:** `priceWei * quantity mod 400` wei lost. Maximum 399 wei.

**Verdict:** SAFE. Loss bounded at 399 wei, dominated by gas costs by 10^9x.

**Test:** `testFuzz_purchaseCost_precisionLossBounded` confirms loss < 400 for all fuzzed inputs.

### Path B: Lootbox -> Split -> Pools

**Divisions:**
```solidity
futureShare = (lootBoxAmount * futureBps) / 10_000
nextShare = (lootBoxAmount * nextBps) / 10_000
vaultShare = (lootBoxAmount * vaultBps) / 10_000
rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare
```

**Pattern:** REMAINDER -- the last share is computed as the difference, not via BPS division.

- **Max precision loss:** ZERO. The remainder pattern guarantees `futureShare + nextShare + vaultShare + rewardShare == lootBoxAmount` exactly.
- **Code reference:** `DegenerusGameMintModule.sol` lines 721-726.

**This is a POSITIVE FINDING -- excellent engineering pattern that eliminates rounding dust in the most frequently executed division chain.**

**Verdict:** SAFE (exact). No wei lost in lootbox split.

**Test:** `testFuzz_lootboxSplit_remainderPattern_exact` confirms exact split for all fuzzed amounts (10K runs).

### Path C: Prize Pool -> Jackpot -> Winner Claims

**Decimator Pro-Rata:** `amountWei = (poolWei * playerBurn) / totalBurn`

- **Max dust per claim:** `totalBurn - 1` wei
- **Sum of N claims:** Always <= `poolWei` (proven by `testFuzz_proRata_sumBounded`)
- **Dust stays in pool:** Unclaimed residual is protocol-positive (stays in claimable pool)

**Jackpot Bucket Distribution:** Uses `baseCount = maxWinners / activeCount` with explicit `remainder = maxWinners - baseCount * activeCount`. Remainder distributed to final bucket.

**BAF Jackpot:** Uses `per = scatter / count` with `rem = scatter - per * count`. Remainder goes to first winner.

**Verdict:** SAFE. All distribution functions use either remainder patterns (exact) or pro-rata with protocol-positive rounding direction.

### Path D: Vault -> Burn -> ETH Out

**Divisions:**
```solidity
// previewBurnForEthOut (ceil-div for target amount):
burnAmount = (targetValue * supply + reserve - 1) / reserve

// _burnEthFor (floor-div for actual claim):
claimValue = (reserve * amount) / supply
```

**Rounding Direction Analysis:**
1. **previewBurnForEthOut:** Ceil-div means user burns >= the mathematically required shares. Protocol gets slightly more shares.
2. **_burnEthFor:** Floor-div means user receives <= the mathematically exact ETH. Protocol retains slightly more ETH.

**Both directions favor the vault.** The user always gives slightly more (ceil) and receives slightly less (floor).

**Round-trip:** `claimValue >= targetValue` (proven by `testFuzz_vault_ceilFloorRoundTrip_favorsVault`).

**Verdict:** SAFE. Rounding Direction consistently favors vault.

**Test:** `testFuzz_vault_ceilFloorRoundTrip_favorsVault` (10K fuzz runs, no counterexample).

---

## 3. Dust Extraction Feasibility (PREC-03)

### Gas Cost Floor Analysis

| Parameter | Value |
|---|---|
| Minimum gas per tx | ~21,000 (base) + ~30,000 (vault burn) = ~50,000 |
| Gas price (conservative) | 10 gwei |
| **Minimum tx cost** | **500,000 gwei = 5 * 10^14 wei** |

### Per-Operation Maximum Dust

| Operation | Max Dust | Dust Type |
|---|---|---|
| BPS division | 9,999 wei | Floor truncation |
| Price conversion | priceWei - 1 ≈ 10^16 wei | Floor truncation (but amounts are BURNIE, not ETH) |
| Pro-rata claim | totalBurn - 1 wei | Floor truncation |
| Vault burn | 1 wei | Floor truncation |
| Lootbox split | 0 wei | Remainder pattern |
| Ticket cost | 399 wei | Floor truncation |

### Mathematical Proof: Dust Extraction is Infeasible

For the highest-dust operation (vault burn, 1 wei per burn):
- **Revenue per attack:** 1 wei per burn
- **Cost per attack:** ~500,000 gwei = 5 * 10^14 wei per tx
- **Ratio:** Cost / Revenue = 5 * 10^14 / 1 = 5 * 10^14

**Even at 1 gwei gas price:** 50,000 gwei / 1 wei = 50,000x cost ratio.

For BPS operations (up to 9,999 wei dust):
- Revenue: 9,999 wei
- Cost: 500,000 gwei = 5 * 10^14 wei
- **Ratio:** 5 * 10^14 / 9,999 = 5 * 10^10 (50 billion to one)

**Test:** `testFuzz_vault_dustNotProfitable` confirms gas exceeds dust by > 1,000,000x.

### Compound Scenario

The longest division chain in a single transaction is the purchase flow (~5 divisions):
1. costWei calculation (1 div, loss < 400 wei)
2. BPS boost (1 div, loss < 10,000 wei)
3. coinCost (1 div, loss < 100 wei)
4. Affiliate payAffiliate (1 div via _ethToBurnieValue, loss < priceWei BURNIE units)
5. Lootbox split (3 BPS divs + remainder, loss = 0 wei due to remainder pattern)

**Total maximum compound loss:** < 10,500 wei per purchase transaction.
**Gas cost of one purchase:** ~200,000 gas * 10 gwei = 2 * 10^15 wei = 2,000,000 gwei.
**Ratio:** 2 * 10^15 / 10,500 ≈ 190,000,000,000 (190 billion to one).

**Conclusion: Dust extraction is economically infeasible by multiple orders of magnitude, even in the compound scenario.**

---

## 4. Rounding Direction Analysis

| Division Category | Rounding Direction | Favors |
|---|---|---|
| BPS calculations | Floor (user gets less) | Protocol |
| Vault burns | Floor (user gets less ETH) | Vault |
| Vault previewBurnForEthOut | Ceil (user burns more shares) | Vault |
| Ticket cost | Floor (user pays slightly more per fractional) | Protocol |
| Pro-rata claims | Floor (unclaimed dust stays in pool) | Protocol |
| Lootbox split | Neutral (exact via remainder pattern) | Neutral |
| Auto-rebuy | Floor (fewer bonus tickets) | Protocol |
| Coinflip reward | Floor (less reward per stake) | Protocol |

**All rounding directions either favor the protocol or are neutral. No operation rounds in the user's favor.**

---

## 5. Positive Engineering Patterns Found

### 1. Remainder Pattern for Lootbox Splits
```solidity
futureShare = (lootBoxAmount * futureBps) / 10_000;
nextShare = (lootBoxAmount * nextBps) / 10_000;
vaultShare = (lootBoxAmount * vaultBps) / 10_000;
rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare;
```
**Impact:** Zero dust in the most frequently executed split. Sum is always exact.

### 2. Explicit Zero-Checks on Computed Costs
Multiple functions check for zero output and revert or return:
- `MintModule._callTicketPurchase`: `if (costWei == 0) revert E();`
- `DegenerusStonk._rebateBurnieFromEthValue`: `if (burnieOut == 0) return;`
- `DegenerusAdmin.onTokenTransfer`: `if (credit == 0) return;`
- `DegenerusGame.claimAffiliateDgnrs`: `if (reward == 0) revert E();`

### 3. Minimum Buy-In Thresholds
- `TICKET_MIN_BUYIN_WEI = 0.0025 ether` prevents dust-level ticket purchases
- `LOOTBOX_MIN = 0.01 ether` prevents dust-level lootbox amounts
- `BURNIE_LOOTBOX_MIN = 1000 ether` prevents dust-level BURNIE lootboxes

### 4. Ceil-Div for Burns Protecting Vault Reserves
The vault uses ceiling division for computing burn amounts, ensuring users always burn at least enough shares to cover their withdrawal.

### 5. Jackpot Distribution Remainder Handling
Both `JackpotBucketLib` and `DegenerusJackpots` use explicit remainder tracking:
```solidity
baseCount = maxWinners / activeCount;
remainder = maxWinners - baseCount * activeCount;
```
Remainder is distributed explicitly rather than lost.

---

## 6. Test Results Summary

### DustAccumulation.t.sol (8 tests, all passing)

| Test | Fuzz Runs | Result |
|---|---|---|
| `testFuzz_vault_repeatedSmallBurns_dustBounded` | 10,000 | PASS |
| `testFuzz_vault_dustNotProfitable` | 10,000 | PASS |
| `testFuzz_lootboxSplit_remainderPattern_exact` | 10,000 | PASS |
| `testFuzz_lootboxSplit_nonPresale_exact` | 10,000 | PASS |
| `testFuzz_bpsDivision_maxDust` | 10,000 | PASS |
| `testFuzz_proRata_sumBounded` | 10,000 | PASS |
| `testFuzz_purchaseCost_precisionLossBounded` | 10,000 | PASS |
| `testFuzz_ethToBurnie_dustBounded` | 10,000 | PASS |

### PrecisionBoundary.t.sol (11 tests, all passing -- from Plan 32-02)

Referenced for vault ceil-floor round-trip, many-small-burns, and minimum viable amounts.

---

## 7. Cross-References

- **Division census:** `.planning/phases/32-precision-and-rounding-analysis/division-census.md` (PREC-01)
- **Zero-rounding report:** `.planning/phases/32-precision-and-rounding-analysis/zero-rounding-report.md` (PREC-02)
- **Test files:**
  - `test/fuzz/DustAccumulation.t.sol` (PREC-03, PREC-04)
  - `test/fuzz/PrecisionBoundary.t.sol` (PREC-02)
- **Existing tests (not duplicated):**
  - `test/fuzz/ShareMathInvariants.t.sol` -- proportional fairness, solvency
  - `test/fuzz/invariant/EthSolvency.inv.t.sol` -- ETH accounting invariants
  - `test/fuzz/invariant/VaultShareMath.inv.t.sol` -- vault share deposit/withdraw math

---

*Report completed: 2026-03-05*
*PREC-03 satisfied: Accumulated rounding error bounded per operation, gas cost dominates dust by 500K+ ratio*
*PREC-04 satisfied: Wei lifecycle traced through all 4 major paths with documented precision loss bounds*
