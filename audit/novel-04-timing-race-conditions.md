# NOVEL-04: Timing and Race Condition Analysis

**Audit Date:** 2026-03-16
**Auditor:** Claude (AI-assisted security analysis, Claude Opus 4.6)
**Scope:** stETH rebasing interactions with sDGNRS burn mechanics (NOVEL-10) and game-over race conditions (NOVEL-11)
**Methodology:** C4A warden methodology -- hypothesis, attack path trace, economic viability, verdict with line-level evidence
**Prior Audit Reference:** v2.0-delta-core-contracts.md (DELTA-01 through DELTA-08, all PASS), DELTA-I-03 (previewBurn discrepancy by design)

---

## NOVEL-10: stETH Rebasing Interaction Analysis

### Part 1: stETH Rebase Mechanics

Lido stETH is a rebasing token: `balanceOf()` returns a holder's proportional share of the total staked ETH pool. Unlike standard ERC20 tokens, balances change without transfer events when the Lido oracle reports validator rewards.

**Rebase characteristics:**
- **Frequency:** Daily, when the Lido oracle committee submits a report (typically around 12:00 UTC)
- **Positive rebase (normal):** Balances increase proportionally to staking rewards. At ~2.5% APR: daily increase = 2.5% / 365 = ~0.00685% per day
- **Negative rebase (slashing):** Balances decrease if Lido validators are slashed. Rare and unpredictable -- no slashing event has occurred on Lido mainnet as of 2026
- **Mechanism:** stETH internally tracks shares. `balanceOf(account) = shares[account] * totalPooledEther / totalShares`. A rebase updates `totalPooledEther` without changing `shares[]`
- **Rounding:** 1-2 wei per share conversion (documented as I-20 in prior audit / DELTA-I-03 in v2.0 delta)

**Relevance to sDGNRS:** The sDGNRS contract holds stETH as part of its backing reserves. The burn function reads `steth.balanceOf(address(this))` (StakedDegenerusStonk.sol:388) to calculate total reserves. A rebase changes this value without any on-chain transaction touching sDGNRS.

### Part 2: Rebase Impact on burn() Payout

The burn calculation at StakedDegenerusStonk.sol:385-391 reads live balances:

```solidity
uint256 supplyBefore = totalSupply;                          // line 385
uint256 ethBal = address(this).balance;                      // line 387
uint256 stethBal = steth.balanceOf(address(this));           // line 388
uint256 claimableEth = _claimableWinnings();                 // line 389
uint256 totalMoney = ethBal + stethBal + claimableEth;       // line 390
uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;  // line 391
```

**Concrete quantification:**

Assume sDGNRS holds 100 ETH worth of stETH (a reasonable mid-game reserve size):

| Metric | Value |
|--------|-------|
| stETH held by sDGNRS | 100 ETH |
| Annual staking APR | 2.5% |
| Daily rebase amount | 100 * 0.025 / 365 = **0.006849 ETH** (~$17.12 at $2,500/ETH) |
| Hourly rebase equivalent | 0.006849 / 24 = **0.000285 ETH** (~$0.71) |

**Extractable value per burn, by holder size:**

| Holder Share | stETH Rebase Share | Dollar Value | Gas Cost (est.) | Net Profit |
|-------------|-------------------|-------------|----------------|-----------|
| 0.1% of supply | 0.000007 ETH | $0.017 | $0.10-0.50 | **-$0.08 to -$0.48** |
| 1% of supply | 0.000069 ETH | $0.17 | $0.10-0.50 | **-$0.00 to -$0.33** |
| 5% of supply | 0.000342 ETH | $0.86 | $0.10-0.50 | **$0.36 to $0.76** |
| 10% of supply | 0.000685 ETH | $1.71 | $0.10-0.50 | **$1.21 to $1.61** |

**Conclusion:** For holders below ~3% of supply, the extractable value from timing burns around the stETH rebase does not cover gas costs. For larger holders (5-10%), the net profit is marginal ($0.36-$1.61 per burn). Even at 500 ETH in stETH reserves (5x the assumption), a 10% holder extracts only ~$8.55 net -- hardly worth the operational complexity of monitoring Lido oracle submissions.

This scales linearly with reserves. At extreme values (1,000+ ETH in stETH), larger holders could extract meaningful amounts, but the per-burn gain remains bounded by `holder_share * daily_rebase` which is fundamentally constrained by Ethereum staking APR.

### Part 3: previewBurn vs burn Discrepancy

The `previewBurn()` function (StakedDegenerusStonk.sol:454-476) reads the same live balances as `burn()`:

```solidity
uint256 stethBal = steth.balanceOf(address(this));   // previewBurn: line 459
uint256 totalMoney = ethBal + stethBal + claimableEth; // previewBurn: line 461
```

**Discrepancy window analysis:**

If a user calls `previewBurn()` before a stETH rebase and then executes `burn()` after the rebase:

1. `previewBurn()` reads `stethBal = X` (pre-rebase)
2. Lido oracle reports, triggering rebase
3. `burn()` reads `stethBal = X + delta` (post-rebase), where `delta = X * 0.025 / 365`
4. Actual payout exceeds preview by `(delta * amount) / totalSupply`

**Maximum discrepancy:** ~0.00685% of the user's proportional stETH share per day. For a 1% holder burning against 100 ETH of stETH reserves, the discrepancy is 0.0000685 ETH (~$0.17).

**Is this exploitable?** No. The user receives the ACTUAL reserve value at burn time, which is the correct behavior. The preview is informational -- it provides an estimate based on current state. This is identical to how AMM price quotes work: the actual execution price may differ slightly from the quoted price due to state changes between quote and execution.

**Prior documentation:** DELTA-I-03 already documented this previewBurn/burn discrepancy as "By Design." The stETH rebase is one contributor to this discrepancy, alongside claimableWinnings changes and other burns executing between preview and burn.

### Part 4: Branch Condition Flipping

The burn function has a critical branch at StakedDegenerusStonk.sol:410:

```solidity
if (totalValueOwed <= ethBal) {              // line 410
    ethOut = totalValueOwed;                  // line 411 — Pure ETH payout path
} else {
    ethOut = ethBal;                          // line 413 — Mixed ETH + stETH path
    stethOut = totalValueOwed - ethOut;       // line 414
    if (stethOut > stethBal) revert Insufficient();  // line 415
}
```

**Can a stETH rebase flip this branch?**

The branch condition depends on the relationship between `totalValueOwed` and `ethBal`:

- `totalValueOwed = (totalMoney * amount) / supplyBefore` (line 391)
- `totalMoney = ethBal + stethBal + claimableEth` (line 390)
- Therefore: `totalValueOwed = ((ethBal + stethBal + claimableEth) * amount) / supplyBefore`

**Rebase effect on the branch:**

- **Positive rebase:** `stethBal` increases, so `totalMoney` increases, so `totalValueOwed` increases. This makes `totalValueOwed > ethBal` MORE likely, pushing toward the mixed payout path. However, `ethBal` is unchanged.
- **Negative rebase (slashing):** `stethBal` decreases, so `totalValueOwed` decreases. This makes `totalValueOwed <= ethBal` MORE likely, pushing toward the pure ETH path.

**Branch flip scenario:** Consider a burn where `totalValueOwed` is very close to `ethBal`. A positive rebase of 0.00685% on the stETH portion could push `totalValueOwed` above `ethBal`, flipping from pure-ETH to mixed payout.

**Example:** If sDGNRS holds 50 ETH + 50 ETH in stETH, and a user burns 50% of supply:
- Pre-rebase: `totalValueOwed = (50 + 50) * 0.5 = 50 ETH`. Branch: `50 <= 50` = TRUE (pure ETH path).
- Post-rebase: `totalValueOwed = (50 + 50.00342) * 0.5 = 50.00171 ETH`. Branch: `50.00171 <= 50` = FALSE (mixed path). User gets 50 ETH + 0.00171 stETH.

**Is this exploitable?** No. Both payout paths deliver `totalValueOwed` worth of assets:
- Pure ETH path: `ethOut = totalValueOwed` (line 411)
- Mixed path: `ethOut = ethBal`, `stethOut = totalValueOwed - ethBal` (lines 413-414). Total = `ethBal + stethOut = totalValueOwed`.

The branch determines payout COMPOSITION (pure ETH vs ETH + stETH), not total VALUE. The user receives the same total value regardless of which branch executes. The only difference is asset composition: receiving 0.00171 ETH worth of stETH instead of pure ETH is negligible and not exploitable.

**Verdict: SAFE.** Branch flipping changes payout composition, not value. No exploit vector.

### Part 5: stETH Slashing Scenario

**Scenario:** A Lido validator slashing event reduces stETH balances by X%.

**Impact on sDGNRS burns:**
- `stethBal` at StakedDegenerusStonk.sol:388 drops by X%
- `totalMoney` at line 390 decreases proportionally to the stETH fraction of reserves
- Every burn payout's total value drops by `X% * (stETH_fraction_of_reserves)`
- If stETH is 50% of reserves and a 10% slash occurs, burn payouts drop by 5%

**Can an attacker trigger slashing?** No. Lido validator operations are entirely external to the Degenerus protocol. Validator slashing occurs on the Ethereum beacon chain, triggered by validator misbehavior (double-signing, surround votes). No on-chain action within the Degenerus contracts or Ethereum execution layer can cause Lido validator slashing.

**Can an attacker front-run a slashing event?**
- Slashing events originate on the beacon chain, NOT in the Ethereum mempool. They are processed by the Lido oracle committee, which submits reports to the stETH contract.
- An attacker monitoring the beacon chain could detect a slashing event before the Lido oracle reports it. The window is typically hours (oracle reporting latency), not seconds (mempool frontrun window).
- If the attacker holds sDGNRS/DGNRS, they could burn BEFORE the Lido oracle processes the slashing report, preserving their pre-slash value.
- However: this is standard DeFi risk awareness, identical to selling any stETH-backed asset before a known slashing event. It requires (a) monitoring beacon chain, (b) detecting the slashing event, (c) executing before the Lido oracle. This is not a protocol vulnerability -- it is market information asymmetry, same as any defi protocol holding stETH.

**Can slashing cause a revert in burn()?** Yes, in an extreme scenario:
- If stETH drops significantly, `totalValueOwed` could exceed `ethBal + stethBal` in the mixed path at StakedDegenerusStonk.sol:415: `if (stethOut > stethBal) revert Insufficient()`.
- This would require: (a) the burn is on the mixed path, (b) slashing reduces stETH enough that the contract cannot cover the calculated `stethOut`.
- This is a theoretical concern only: it would require a massive slash (>50% of staked ETH), which has never occurred on Lido and would represent a catastrophic Ethereum consensus failure affecting the entire DeFi ecosystem.

**Verdict: KNOWN RISK (stETH inherent), not protocol vulnerability.** The Degenerus protocol inherits stETH's slashing risk by holding stETH as reserves. This is an architectural decision, not a bug. Mitigation would require not holding stETH, which would sacrifice staking yield.

### stETH Timing Summary Table

| Scenario | Extractable Value | Cost to Execute | Net Profit | Verdict |
|----------|-------------------|-----------------|------------|---------|
| Time burn after positive rebase (1% holder, 100 ETH stETH) | $0.17 | $0.10-0.50 gas | -$0.00 to -$0.33 | **SAFE** -- unprofitable |
| Time burn after positive rebase (10% holder, 100 ETH stETH) | $1.71 | $0.10-0.50 gas | $1.21 to $1.61 | **SAFE** -- marginal, not worth operational overhead |
| previewBurn/burn discrepancy from rebase | ~0.007% of stETH share | N/A | N/A | **BY DESIGN** (DELTA-I-03) |
| Branch condition flip from rebase | $0 (composition change only) | N/A | $0 | **SAFE** -- no value difference |
| Front-run Lido slashing event | Preserves pre-slash value | Beacon chain monitoring | Variable | **KNOWN RISK** -- standard DeFi market risk, not protocol vulnerability |
| Massive slashing causes burn revert | N/A (DoS, not profit) | N/A | N/A | **KNOWN RISK** -- catastrophic scenario only, affects entire DeFi |

**NOVEL-10 Overall Verdict: SAFE.** stETH rebasing interactions with sDGNRS burn mechanics do not create economically viable exploits. The daily rebase of ~0.007% creates negligible extractable value relative to gas costs for most holders. The previewBurn/burn discrepancy is by design (DELTA-I-03). Branch condition flipping changes payout composition without affecting total value. Slashing scenarios are inherited stETH risk, not protocol vulnerabilities.

---
