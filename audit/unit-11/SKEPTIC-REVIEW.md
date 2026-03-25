# Unit 11: sDGNRS + DGNRS -- Skeptic Review

**Reviewer Identity:** Skeptic (per ULTIMATE-AUDIT-DESIGN.md)
**Date:** 2026-03-25
**Method:** Independent code verification of every INVESTIGATE finding from the Mad Genius

---

## Findings Review

---

### MG-11-01: Dust accumulation in pendingRedemptionEthValue

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** CONFIRMED -- INFO

**Analysis:**

I traced the math independently:

1. **At resolve (L547-548):** `rolledEth = (pendingRedemptionEthBase * roll) / 100`. This is the total rolled ETH for the period. `pendingRedemptionEthValue` is adjusted to: `pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth`.

2. **At claim (L587):** Each claimant computes: `totalRolledEth = (claim.ethValueOwed * roll) / 100`. Then at L612: `pendingRedemptionEthValue -= totalRolledEth`.

3. **The discrepancy:** `rolledEth = (sum_of_all_ethValueOwed * roll) / 100` at resolve. But `sum(per_claimant_rolledEth) = sum((ethValueOwed_i * roll) / 100)`. Due to floor division, `sum((a_i * r) / 100) <= (sum(a_i) * r) / 100`. The difference is at most (n-1) wei per period where n = number of claimants.

4. **Accumulation:** This dust is never reclaimed. Over the lifetime of the game, with say 1000 periods and 100 claimants each, total dust would be ~99,000 wei = 0.000000000000099 ETH. Truly negligible.

5. **Impact on deterministic burns:** In `_deterministicBurnFrom` (L489), `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`. The accumulated dust in `pendingRedemptionEthValue` means slightly less totalMoney is available for deterministic burns. The effect is fractional wei -- zero economic impact.

**Confirmed as INFO.** The dust accumulation is real, mathematically provable, and completely inconsequential. No fix needed.

---

### MG-11-02: Effects-before-checks in DGNRS.burn()

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** FALSE POSITIVE

**Analysis:**

I read DGNRS.burn() at L171-189:

```solidity
function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    _burn(msg.sender, amount);                                    // L172: effects
    if (!IDegenerusGame(ContractAddresses.GAME).gameOver()) revert GameNotOver(); // L173: checks
    ...
}
```

The Mad Genius flagged this as "effects-before-checks." However:

1. **Solidity atomicity:** If L173 reverts, the `_burn` at L172 is unwound. No state is persisted. This is standard Solidity behavior.

2. **This is not actually effects-before-checks in the security sense.** The CEI (Checks-Effects-Interactions) pattern exists to prevent reentrancy. Here, `_burn` is an internal function with no external calls -- there is no reentrancy window between L172 and L173. The `gameOver()` view call at L173 cannot be influenced by the `_burn` at L172.

3. **Why this ordering exists:** The developer chose to burn first so that if the `burn` fails (zero amount, insufficient balance), the revert happens before the external call to `game.gameOver()`, saving gas on the view call in the failure case. This is a valid optimization pattern.

**Dismissed as FALSE POSITIVE.** The ordering is intentional, safe due to atomicity, and has no reentrancy implications. The `_burn` internal function makes no external calls.

---

### MG-11-03: uint96 truncation of burnieOwed

**Mad Genius Verdict:** INVESTIGATE (LOW)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**

I examined the truncation at L760:
```solidity
claim.burnieOwed += uint96(burnieOwed);
```

The Mad Genius calculated that BURNIE reserves would need to exceed ~158 trillion tokens (1.58e29 wei) for truncation to occur. Let me verify:

1. `burnieOwed = (totalBurnie * amount) / supplyBefore`
2. For single-wallet truncation (160 ETH cap): `amount` is capped such that `ethValueOwed <= 160 ETH`. The corresponding `amount` depends on the price ratio.
3. With supplyBefore = 1e30 (1T tokens) and ethValueOwed = 160 ETH (1.6e20 wei):
   - `amount = (ethValueOwed * supplyBefore) / totalMoney`
   - If totalMoney = 100 ETH: `amount = 1.6e21` (1,600 tokens)
   - `burnieOwed = (totalBurnie * 1.6e21) / 1e30 = totalBurnie * 1.6e-9`
   - For overflow: `totalBurnie * 1.6e-9 > 7.9e28` -> `totalBurnie > 4.9e37`
   - This is 49 quintillion tokens. BURNIE maxSupply is governed by game economics -- nowhere near this.

4. Even without the 160 ETH cap, the 50% supply cap means `amount <= supplyBefore / 2`:
   - `burnieOwed = (totalBurnie * supplyBefore/2) / supplyBefore = totalBurnie / 2`
   - For overflow: `totalBurnie / 2 > 7.9e28` -> `totalBurnie > 1.58e29`
   - But this is the TOTAL for the period across ALL wallets, not a single wallet's claim.

5. **Real constraint:** The per-wallet truncation requires the single wallet's burnieOwed > uint96.max. With 160 ETH cap and reasonable BURNIE pricing, this is unreachable by many orders of magnitude.

**Downgraded to INFO.** The truncation is theoretically possible but requires BURNIE reserves exceeding 49 quintillion tokens in a single wallet's proportional share, which is far beyond any realistic scenario. The implicit bound from the 160 ETH cap makes this a documentation-only concern.

---

### MG-11-04: View function underflow potential

**Mad Genius Verdict:** INVESTIGATE (INFO)
**Skeptic Verdict:** CONFIRMED -- INFO

**Analysis:**

I examined `previewBurn` (L660) and `burnieReserve` (L691):

1. `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`
2. `return burnieBal + claimableBurnie - pendingRedemptionBurnie`

Both can underflow if pending reserves exceed actual balances. When could this happen?

- **Normal operation:** pendingRedemptionEthValue is always <= totalMoney at submission time. But if ETH is removed (burns, claims) between periods, the ratio could shift. Specifically, if a deterministic burn (post-gameOver) pays out ETH while gambling claims are still pending, the remaining ETH could be less than pendingRedemptionEthValue. But: deterministic burns only happen during gameOver, and gambling burns are blocked during gameOver (rngLocked check would need to pass, but more importantly, the flow goes to deterministic path). So during active game, ETH is only removed by _payEth in claimRedemption, which decrements pendingRedemptionEthValue simultaneously. **Cannot underflow during normal operation.**

- **Edge case:** If stETH rebases DOWN (negative rebase), the steth balance could decrease, making `ethBal + stethBal + claimableEth < pendingRedemptionEthValue`. This is a genuine edge case that could cause the view to revert. However, stETH negative rebases are slashing events -- extremely rare and small in magnitude.

**Confirmed as INFO.** View-only impact. The underflow is technically possible during stETH negative rebase but has no state-changing consequences -- the view simply reverts, and callers get no preview. The state-changing burn functions would still work (they use the actual balances).

---

## Summary

| ID | Mad Genius Verdict | Skeptic Verdict | Final Severity |
|----|-------------------|----------------|----------------|
| MG-11-01 | INVESTIGATE | CONFIRMED | INFO |
| MG-11-02 | INVESTIGATE | FALSE POSITIVE | -- |
| MG-11-03 | INVESTIGATE (LOW) | DOWNGRADE TO INFO | INFO |
| MG-11-04 | INVESTIGATE | CONFIRMED | INFO |

**Confirmed findings:** 3 (all INFO severity)
**False positives:** 1 (MG-11-02)
**CRITICAL/HIGH/MEDIUM findings:** 0

**Overall Assessment:** Both contracts are well-constructed with robust access control, correct accounting, and proper separation of concerns. The gambling burn redemption pipeline -- the most complex subsystem -- has been traced end-to-end through all three phases (submit/resolve/claim) and the accounting is sound. The cross-contract interaction between sDGNRS and DGNRS is clean with no stale-cache patterns. The VRF stall guard on unwrapTo is effective.
