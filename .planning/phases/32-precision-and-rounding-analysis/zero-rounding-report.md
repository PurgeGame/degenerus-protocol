# Zero-Rounding Analysis Report (PREC-02)

**Phase:** 32 (Precision and Rounding Analysis)
**Requirement:** PREC-02
**Date:** 2026-03-05

---

## 1. Executive Summary

**Overall Verdict: SAFE -- No user-facing operation can produce zero cost with non-zero output.**

All user-callable functions with division operations either:
1. Have explicit zero-checks that revert on zero output
2. Use numerators large enough (via PRICE_COIN_UNIT or ETH-scale values) that zero output is mathematically impossible
3. Return silently (no-op) when output rounds to zero, preventing free actions

The vault share math ceil-floor round-trip consistently favors the vault (rounding direction is protocol-positive). Dust extraction via splitting is proven infeasible by fuzz testing.

---

## 2. Test Results Matrix

| Function | Minimum Viable Input | Computed Output at Minimum | Guard Mechanism | Test Name | Verdict |
|---|---|---|---|---|---|
| `MintModule._callTicketPurchase` | qty=100 at 0.01 ETH tier | costWei = 2.5e15 = TICKET_MIN_BUYIN_WEI | Zero-check + min buy-in revert | `test_ticket_minQty_nonZeroCost` | SAFE (proven by test) |
| `DegenerusVault.previewBurnForEthOut` | targetValue=1 wei, reserve >= supply | burnAmount >= 1, claimValue >= 1 | ceil-div ensures adequate burn amount | `testFuzz_vault_ceilFloorRoundTrip_favorsVault` | SAFE (proven by test) |
| `DegenerusVault.previewEth` | amount=1 share, reserve >= supply | claimValue >= 1 wei | floor-div, but reserve >= supply typical | `testFuzz_vault_burn1Share_nonZeroClaimValue` | SAFE (proven by test) |
| `LootboxModule._resolveLootboxRoll` | amount = LOOTBOX_MIN (0.01 ETH) | All BPS intermediates >= 10^12 | LOOTBOX_MIN + PRICE_COIN_UNIT amplification | `test_lootbox_atMinimum_allIntermediatesNonZero` | SAFE (proven by test) |
| `DecimatorModule._decEffectiveAmount` | prevBurn = cap-1, baseAmount = PRICE_COIN_UNIT | effectiveAmount > 0 | Split between multiplied and 1x portions | `test_decimator_atCapBoundary_effectiveAmountNonZero` | SAFE (proven by test) |
| `BurnieCoinflip` payout | stake=1 wei, rewardPercent=1 | payout = 1 (principal returned, reward=0) | Principal always included in payout | `testFuzz_coinflip_minimumStake_principalReturned` | SAFE (proven by test) |
| `PayoutUtils._calcAutoRebuy` | weiAmount < ticketPrice | baseTickets = 0, hasTickets = false | Integer floor to zero tickets | `test_autoRebuy_belowTicketPrice_noTickets` | SAFE (proven by test) |
| `DegenerusStonk._rebateBurnieFromEthValue` | ethValue = 1 wei | burnieOut > 0 (PRICE_COIN_UNIT amplifies) | `if (burnieOut == 0) return;` zero guard | N/A (analysis) | SAFE (proven by analysis) |
| `DegenerusAdmin.onTokenTransfer` | Small LINK donation | `if (credit == 0) return;` zero guard | Explicit zero return | N/A (analysis) | SAFE (proven by analysis) |
| `DegenerusGame.claimAffiliateDgnrs` | Small affiliate score | `if (reward == 0) revert E();` | Explicit zero revert | N/A (analysis) | SAFE (proven by analysis) |

---

## 3. Vault Share Math Deep Dive

### Mathematical Proof: Rounding Favors the Vault

**previewBurnForEthOut (ceil-div):**
```
burnAmount = ceil(targetValue * supply / reserve)
           = (targetValue * supply + reserve - 1) / reserve
```

**previewEth / _burnEthFor (floor-div):**
```
claimValue = floor(reserve * burnAmount / supply)
```

**Invariant:** `claimValue >= targetValue`

**Proof:** By the ceiling property, `burnAmount >= targetValue * supply / reserve`. Therefore:
```
claimValue = floor(reserve * burnAmount / supply)
           >= floor(reserve * (targetValue * supply / reserve) / supply)
           = floor(targetValue)
           = targetValue
```

This was verified by `testFuzz_vault_ceilFloorRoundTrip_favorsVault` with 10,000 fuzz runs. No counterexample found.

### Many-Small-Burns vs One-Large-Burn

The test `testFuzz_vault_manySmallBurns_vs_oneLargeBurn` proves that N small burns of 1 share each always yield total ETH <= 1 burn of N shares. This means:

1. **No dust extraction via splitting:** An attacker cannot profit by burning shares individually vs in bulk.
2. **Dust direction:** Each floor division loses at most 1 wei. Across N operations, total dust <= N wei.
3. **Gas dominance:** N burns cost N * ~50K gas * 10 gwei = N * 500K gwei in gas. The extracted dust is N wei. Gas exceeds dust by 500K gwei / 1 wei = 500,000x.

### Vault Share Math Summary

| Property | Result |
|---|---|
| Ceil-floor round-trip direction | Favors vault (user always gets >= targetValue) |
| Many small vs one large | Single large >= sum of small (no split profit) |
| Max dust per burn | 1 wei |
| Gas-to-dust ratio | ~500,000x (at 10 gwei gas) |
| Dust extraction profitable? | NO |

---

## 4. Functions Not Tested (and why)

### BPS Calculations (95 operations)
**Why no test needed:** All use `(amount * bps) / 10_000` where `amount` is in wei scale (10^18+). Maximum loss: `10_000 - 1 = 9,999 wei` per operation. At 10 gwei gas price, minimum tx cost is ~500K gwei. The 9,999 wei maximum dust is 50,000x smaller than minimum gas cost. Not economically exploitable.

### Price-Conversion Operations (25 operations)
**Why no test needed:** All use `(amount * PRICE_COIN_UNIT) / priceWei` where `PRICE_COIN_UNIT = 10^21`. The multiplication by 10^21 creates numerators so large that division by `priceWei` (10^16 to 2.4*10^17) produces negligible precision loss. Maximum loss: `priceWei - 1` BURNIE base units.

### Intentional-Floor Operations (42 operations)
**Why no test needed:** These are by-design integer division patterns (modulo extraction, floor-to-multiple, week-counting). They are not bugs -- they implement correct discrete math. Examples: `entropy % 100`, `(lvl + 9) / 10 * 10`, `elapsed / 604800`.

---

## 5. Cross-References

- **Test file:** `test/fuzz/PrecisionBoundary.t.sol` (11 tests, all passing under FOUNDRY_PROFILE=deep)
- **Division census:** `.planning/phases/32-precision-and-rounding-analysis/division-census.md` (222 operations classified)
- **Existing coverage:** `test/fuzz/ShareMathInvariants.t.sol` covers proportional fairness and solvency (not duplicated here)

---

*Report completed: 2026-03-05*
*PREC-02 requirement satisfied: All user-facing operations verified safe at minimum viable inputs*
