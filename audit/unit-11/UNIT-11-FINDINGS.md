# Unit 11: sDGNRS + DGNRS -- Final Findings Report

**Phase:** 113 (v5.0 Ultimate Adversarial Audit)
**Contracts:** StakedDegenerusStonk.sol (839 lines), DegenerusStonk.sol (251 lines)
**Date:** 2026-03-25
**Auditors:** Taskmaster (coverage), Mad Genius (attack), Skeptic (validation)

---

## Executive Summary

Unit 11 audited the sDGNRS (soulbound token with reserves) and DGNRS (transferable ERC20 wrapper) contracts through the full three-agent adversarial pipeline. Every state-changing function was analyzed with complete recursive call trees, storage-write maps, and cached-local-vs-storage checks per ULTIMATE-AUDIT-DESIGN.md.

**Result: No CRITICAL, HIGH, or MEDIUM findings. 3 INFO-severity confirmed findings.**

The gambling burn redemption pipeline (submit/resolve/claim) -- the highest-risk subsystem -- was traced end-to-end. The multi-step flow with segregated ETH/BURNIE accounting is correctly implemented. Cross-contract interactions between sDGNRS and DGNRS are clean with no stale-cache patterns. The VRF stall guard on unwrapTo is effective.

---

## Audit Statistics

| Metric | Value |
|--------|-------|
| Total functions | 37 (26 sDGNRS + 11 DGNRS) |
| Category B analyzed | 19 |
| Category C (MULTI-PARENT) analyzed | 4 |
| Category D (view/pure) reviewed | 6+ |
| Constructors verified | 2 |
| Call trees built | 23 |
| Storage write maps | 23 |
| Cache checks | 23 |
| VULNERABLE findings | 0 |
| INVESTIGATE findings | 4 (from Mad Genius) |
| Skeptic CONFIRMED | 3 (all INFO) |
| Skeptic FALSE POSITIVE | 1 |
| Coverage verdict | PASS (100%) |

---

## Confirmed Findings

### FINDING-11-01: Dust Accumulation in Pending Redemption ETH Tracking

**Severity:** INFO
**Contracts:** StakedDegenerusStonk.sol
**Lines:** L547-548 (resolveRedemptionPeriod), L587 (claimRedemption), L612 (claimRedemption)
**Mad Genius ID:** MG-11-01
**Skeptic Verdict:** CONFIRMED

**Description:**
Per-claimant floor division during `claimRedemption()` causes up to (n-1) wei dust to remain in `pendingRedemptionEthValue` per period. `resolveRedemptionPeriod` computes the period total as `(pendingRedemptionEthBase * roll) / 100`, but each claimant independently computes `(claim.ethValueOwed * roll) / 100`. The sum of per-claimant values is <= the period total. The difference (dust) remains in `pendingRedemptionEthValue` permanently.

**Impact:**
Over the game's lifetime with ~1000 periods and ~100 claimants each, total dust would be ~99,000 wei (~0.0000000000001 ETH). This dust slightly reduces the `totalMoney` available in `_deterministicBurnFrom` and `previewBurn`, but the effect is immeasurable.

**Recommendation:** No action required. The contract already documents this in comments (L585-586). The accumulation is monotonic but economically zero.

---

### FINDING-11-02: uint96 BURNIE Truncation Theoretical Possibility

**Severity:** INFO
**Contracts:** StakedDegenerusStonk.sol
**Lines:** L760
**Mad Genius ID:** MG-11-03
**Skeptic Verdict:** CONFIRMED (downgraded from LOW)

**Description:**
`claim.burnieOwed += uint96(burnieOwed)` performs an unchecked narrowing cast. If `burnieOwed` exceeds `type(uint96).max` (~7.9e28), the value silently truncates. The Skeptic verified this requires the wallet's proportional BURNIE share to exceed ~49 quintillion tokens (4.9e37 wei) given the 160 ETH daily EV cap -- far beyond any realistic BURNIE supply.

**Impact:** None under any realistic scenario. BURNIE supply is governed by game economics and is orders of magnitude below the threshold.

**Recommendation:** No action required. Could add a comment documenting the implicit bound, but the existing comment at L759 already addresses this.

---

### FINDING-11-03: View Function Revert on Negative stETH Rebase

**Severity:** INFO
**Contracts:** StakedDegenerusStonk.sol
**Lines:** L660 (previewBurn), L691 (burnieReserve)
**Mad Genius ID:** MG-11-04
**Skeptic Verdict:** CONFIRMED

**Description:**
`previewBurn()` computes `totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue`. If a stETH negative rebase (validator slashing event) reduces `stethBal` such that the subtraction underflows, the view function reverts instead of returning data. Similarly, `burnieReserve()` could revert if `pendingRedemptionBurnie` exceeds available BURNIE.

**Impact:** View-only. State-changing functions (`_deterministicBurnFrom`, `_submitGamblingClaimFrom`) use the actual balances and would still function correctly -- they would just pay less if backing decreased. The revert only affects preview/query callers. stETH negative rebases are extremely rare (validator slashing) and small in magnitude.

**Recommendation:** No action required. A defensive `if (pendingRedemptionEthValue > total) return (0,0,0)` could prevent the revert, but is unnecessary given the rarity.

---

## Dismissed Findings

### MG-11-02: Effects-Before-Checks in DGNRS.burn()

**Skeptic Verdict:** FALSE POSITIVE

**Reason:** The `_burn()` at L172 is an internal function with no external calls, executed before the `gameOver()` check at L173. Due to Solidity's atomic transaction model, a revert at L173 fully unwinds L172. There is no reentrancy window, no observable state change on revert, and the ordering serves as a gas optimization (fail fast on invalid amount before making an external view call). Not a vulnerability by any standard.

---

## Key Subsystem Verdicts

### Gambling Burn Redemption Pipeline: SAFE
- Submit (L707-769): Correctly segregates ETH/BURNIE, enforces 50% supply cap and 160 ETH daily cap, properly tracks period boundaries
- Resolve (L540-565): Correctly adjusts segregation by roll, releases BURNIE reservation, stores period result
- Claim (L573-639): Correctly computes per-claimant payout with roll, handles partial claims (ETH paid, BURNIE deferred), proper lootbox routing

### Cross-Contract Burns: SAFE
- sDGNRS.burn() -> deterministic/gambling: no stale cache
- sDGNRS.burnWrapped() -> DGNRS.burnForSdgnrs() -> sDGNRS burn: atomic, no desync
- DGNRS.burn() -> sDGNRS.burn() -> ETH back to DGNRS: correct receive() guard
- DGNRS.unwrapTo() -> sDGNRS.wrapperTransferTo(): VRF guard effective

### Pool Management: SAFE
- transferFromPool, transferBetweenPools, burnRemainingPools: all onlyGame, correct accounting

### Soulbound Enforcement: SAFE
- No transfer function in sDGNRS (only pool distributions and wrapper transfers, both game-controlled)
- DGNRS provides the liquidity layer with standard ERC20

### Access Control: SAFE
- sDGNRS: onlyGame for deposits/pools/resolve, DGNRS-only for wrapperTransferTo, anyone for burn/claim
- DGNRS: CREATOR-only for unwrapTo, sDGNRS-only for burnForSdgnrs, sDGNRS-only for receive, anyone for ERC20 + burn

---

## BAF-Class Bug Check

The BAF (cache-overwrite) pattern was the primary target of this audit. For every function:

**Checked:** Does any ancestor cache a storage value that a descendant (including cross-contract calls) overwrites?

**Result:** No BAF-class bugs found. The contracts follow a clean pattern of:
1. Cache local values
2. Perform all computations
3. Write to storage
4. Make external calls (which may read but not write to sDGNRS/DGNRS storage)

The one exception -- `_deterministicBurnFrom` calling `game.claimWinnings()` which sends ETH to sDGNRS -- properly re-reads `ethBal` after the call (L500).

---

## Conclusion

StakedDegenerusStonk.sol and DegenerusStonk.sol pass the adversarial audit with no actionable findings. The 3 INFO-level observations are documented for completeness. The gambling burn redemption system is correctly implemented with proper segregation accounting, period management, and multi-asset payout logic.
