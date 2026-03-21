# 51-02: Daily Cap Enforcement & PendingRedemption Slot Packing Findings

**Date:** 2026-03-21
**Auditor:** Claude (automated audit)
**Contract:** StakedDegenerusStonk.sol
**Requirements:** REDM-03 (160 ETH daily cap), REDM-05 (PendingRedemption slot packing)

---

## REDM-03: 160 ETH Daily Cap Enforcement

### Verdict: SAFE

The 160 ETH daily cap per wallet is correctly enforced with no bypass via multiple calls, cross-period stacking, or timestamp manipulation.

### Evidence

#### 1. Cap Check (Line 753)

```solidity
// StakedDegenerusStonk.sol:753
if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();
```

- `MAX_DAILY_REDEMPTION_EV` = `160 ether` (line 227) = 1.6e20 wei
- `claim.ethValueOwed` is `uint96` read from storage (max 7.922e28), promoted to `uint256` for the addition
- `ethValueOwed` is `uint256` computed on line 725: `(totalMoney * amount) / supplyBefore`
- The addition `uint96 + uint256` operates in `uint256` context -- no overflow possible (uint96.max + uint256 < uint256.max)
- The check is CUMULATIVE: `claim.ethValueOwed` accumulates all burns within the same period, so the comparison `accumulated + new > 160 ETH` correctly enforces the cap across multiple calls
- **Critical ordering:** The cap check on line 753 occurs BEFORE the uint96 cast on line 755 (`claim.ethValueOwed += uint96(ethValueOwed)`). This means the check operates on the full uint256 value, not a potentially truncated one.

#### 2. Period Gating (Lines 747-750)

```solidity
// StakedDegenerusStonk.sol:747-750
PendingRedemption storage claim = pendingRedemptions[beneficiary];
if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) {
    revert UnresolvedClaim();
}
```

- `periodIndex == 0` means "no active claim" -- this is the fresh state after `delete pendingRedemptions[player]` in `claimRedemption()` (all struct fields zero-initialized)
- `periodIndex == currentPeriod` means "same period, can stack additional burns up to the cap"
- `periodIndex != 0 && periodIndex != currentPeriod` means "claim from a different period exists but hasn't been claimed yet" -- REVERTS
- This prevents cross-period stacking: a player MUST call `claimRedemption()` (which deletes the struct) before burning in a new period
- The `delete` in `claimRedemption()` resets `periodIndex` to 0, enabling the next period's burns

#### 3. Multiple Calls Within Same Period

**Trace:**
1. First burn: `amount = X`, `ethValueOwed = E1`. Line 753 checks `0 + E1 <= 160 ETH`. Line 755: `claim.ethValueOwed = 0 + uint96(E1) = E1`.
2. Second burn: `amount = Y`, `ethValueOwed = E2`. Line 753 checks `E1 + E2 <= 160 ETH`. Line 755: `claim.ethValueOwed = E1 + uint96(E2)`.
3. Third burn: `amount = Z`, `ethValueOwed = E3`. Line 753 checks `(E1 + E2) + E3 <= 160 ETH`.

**Concrete example:** Two burns of 80 ETH each, then a third burn of any amount:
- After burn 1: `claim.ethValueOwed = 80 ETH`
- After burn 2: `claim.ethValueOwed = 160 ETH` (cap check: 80 + 80 = 160 <= 160, passes)
- Burn 3 of 1 wei: cap check: `160 ETH + 1 > 160 ETH`, REVERTS with `ExceedsDailyRedemptionCap()`

The cumulative cap is enforced correctly.

#### 4. Cross-Day Boundary Analysis (Pitfall 4)

**GameTimeLib (lines 21-34):**
```solidity
// GameTimeLib.sol:31-33
function currentDayIndexAt(uint48 ts) internal pure returns (uint48) {
    uint48 currentDayBoundary = uint48((ts - JACKPOT_RESET_TIME) / 1 days);
    return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
}
```

- Day index resets at `JACKPOT_RESET_TIME = 82620` seconds from midnight = **22:57 UTC** (not midnight)
- `currentPeriod` on line 709 comes from `game.currentDayView()` which uses this library

**Scenario: Burn 160 ETH at 22:56:59 UTC, then 160 ETH at 22:57:01 UTC**

This scenario requires:
1. First burn at 22:56:59 UTC (period N): `claim.ethValueOwed = 160 ETH`, `claim.periodIndex = N`
2. Period boundary passes at 22:57:00 UTC: `currentDayView()` now returns N+1
3. Second burn at 22:57:01 UTC (period N+1): The `UnresolvedClaim` check on line 748 fires because `claim.periodIndex = N` and `N != N+1` --> **REVERTS with `UnresolvedClaim()`**

The player must first call `claimRedemption()` to resolve period N. But `claimRedemption()` requires the period to be resolved (the `redemptionPeriods[periodIndex].roll` must be non-zero, set by `resolveRedemptionPeriod` during `advanceGame`). The `advanceGame` call requires RNG fulfillment, so the window between periods is NOT instant.

**Verdict on cross-day:** This is by-design. Each period gets its own 160 ETH cap. Rapid period transitions require:
1. RNG request + fulfillment for period resolution
2. `advanceGame` call
3. `claimRedemption` call
4. Then new `burn` in the next period

This is not an exploitable attack vector -- it is the intended per-period cap behavior.

#### 5. 50% Supply Cap Per Period (Lines 708-716)

```solidity
// StakedDegenerusStonk.sol:708-716
uint48 currentPeriod = game.currentDayView();
if (redemptionPeriodIndex != currentPeriod) {
    redemptionPeriodSupplySnapshot = totalSupply;
    redemptionPeriodIndex = currentPeriod;
    redemptionPeriodBurned = 0;
}
if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();
redemptionPeriodBurned += amount;
```

This is a separate cap on TOKEN AMOUNT burned per period (not ETH value). It restricts how many sDGNRS tokens can be burned in a single period to 50% of the total supply at the start of that period.

**Interaction with 160 ETH cap:** These are independent guards. A player could burn tokens worth less than 160 ETH and still hit the 50% supply cap (if they hold a large share of supply). Conversely, a player with a small share could burn all their tokens and still be under the 160 ETH cap. Neither cap can be used to bypass the other -- they are both enforced sequentially (supply cap first at line 715, ETH cap second at line 753).

---

## REDM-05: PendingRedemption Slot Packing

### Verdict: SAFE (with informational note on burnieOwed)

The PendingRedemption struct packs to exactly 256 bits (1 EVM storage slot) with no bit overlap. All cast sites are safe under the protocol's economic constraints.

### Evidence

#### 1. Struct Definition (Lines 182-187)

```solidity
// StakedDegenerusStonk.sol:182-187
struct PendingRedemption {
    uint96  ethValueOwed;   // bits [0:95]    - base (100%) ETH-equivalent owed
    uint96  burnieOwed;     // bits [96:191]  - base (100%) BURNIE owed
    uint48  periodIndex;    // bits [192:239] - which daily period
    uint16  activityScore;  // bits [240:255] - snapshotted activity score + 1
}
```

**Bit width verification:** 96 + 96 + 48 + 16 = **256 bits exactly**.

**Solidity compiler packing rule:** For structs used in storage, Solidity packs fields in declaration order, starting a new slot only when the next field does not fit in the remaining space of the current 256-bit slot. Since all four fields sum to exactly 256 bits, they fill one slot completely with no padding.

**No bit overlap:** Each field occupies a distinct, contiguous range:
- `ethValueOwed`: bits [0:95] (96 bits)
- `burnieOwed`: bits [96:191] (96 bits)
- `periodIndex`: bits [192:239] (48 bits)
- `activityScore`: bits [240:255] (16 bits)

No gaps, no overlap, no wasted bits.

#### 2. uint96 Cast for ethValueOwed (Line 755)

```solidity
// StakedDegenerusStonk.sol:755
claim.ethValueOwed += uint96(ethValueOwed);
```

- `ethValueOwed` is computed on line 725: `(totalMoney * amount) / supplyBefore`
- The cap check on line 753 ensures `claim.ethValueOwed + ethValueOwed <= MAX_DAILY_REDEMPTION_EV = 160 ether = 1.6e20 wei`
- Therefore the maximum value of `ethValueOwed` in a single call is at most `1.6e20` (when `claim.ethValueOwed == 0`)
- The maximum accumulated value of `claim.ethValueOwed` after the `+= uint96()` is at most `1.6e20`

**Arithmetic proof:**
- `uint96.max = 2^96 - 1 = 79,228,162,514,264,337,593,543,950,335` (~7.922e28)
- `MAX_DAILY_REDEMPTION_EV = 160 ether = 160,000,000,000,000,000,000` (1.6e20)
- `1.6e20 << 7.922e28` -- the cap is 8 orders of magnitude below uint96.max

**SAFE:** No truncation possible for `ethValueOwed`.

#### 3. uint96 Cast for burnieOwed (Line 756)

```solidity
// StakedDegenerusStonk.sol:756
claim.burnieOwed += uint96(burnieOwed);
```

- `burnieOwed` is computed on line 731: `(totalBurnie * amount) / supplyBefore`
- **There is no explicit cap on `burnieOwed`** analogous to `MAX_DAILY_REDEMPTION_EV`

**Worst-case analysis:**

BURNIE token (BurnieCoin.sol):
- 18 decimals
- `totalSupply` is `uint128` (max ~3.4e38)
- Constructor mints 2,000,000 BURNIE = 2e24 raw units to sDGNRS (line 272)
- Vault allowance starts at 2,000,000 BURNIE = 2e24 (line 203)
- `supplyIncUncirculated` = `totalSupply + vaultAllowance`, initial total = 4e24
- Additional minting occurs via `mintForCoinflip`, `mintForGame`, and vault operations

The maximum possible `totalBurnie` held by sDGNRS:
- `totalBurnie = coin.balanceOf(sDGNRS) + coinflip.previewClaimCoinflips(sDGNRS) - pendingRedemptionBurnie` (line 730-731)
- The `uint128` constraint on `_supply.totalSupply` means `coin.balanceOf(sDGNRS)` cannot exceed `uint128.max` = ~3.4e38
- `coinflip.previewClaimCoinflips(sDGNRS)` is bounded by coinflip mechanics (minted tokens)

The worst-case `burnieOwed`:
- `burnieOwed = (totalBurnie * amount) / supplyBefore`
- If `amount / supplyBefore` approaches 1 (player burns nearly all sDGNRS supply), then `burnieOwed` approaches `totalBurnie`
- If `totalBurnie` > `uint96.max` (7.922e28), then `burnieOwed` could exceed `uint96.max` and the `uint96()` cast would silently truncate

**Can totalBurnie exceed 7.922e28 (79.2 billion BURNIE)?**
- Initial BURNIE minted to sDGNRS: 2M = 2e24. This is ~0.003% of uint96.max.
- BURNIE is minted via game payouts (`mintForGame`), coinflip wins (`mintForCoinflip`), and vault operations. These are bounded by game activity and ETH inflows.
- At 18 decimals, 7.922e28 raw = 79.22 billion BURNIE tokens.
- The initial total supply is 4M BURNIE. Reaching 79B would require a ~20,000x increase in supply.
- The `uint128` type on `_supply.totalSupply` permits up to ~3.4e38 raw = 340 billion billion BURNIE -- far above uint96.max.

**Economic feasibility:** While `uint128` allows it theoretically, reaching 79B+ BURNIE held by sDGNRS would require extraordinary game activity over extended periods. The protocol's economic design does not appear to create a mechanism for rapid BURNIE accumulation to this scale. However, the theoretical possibility exists because `burnieOwed` has no explicit cap.

**Practical mitigation:** The 50% supply cap per period (line 715) limits `amount / supplyBefore` to at most 0.5, meaning `burnieOwed <= totalBurnie / 2`. This doubles the threshold to ~158B BURNIE before truncation. Additionally, `pendingRedemptionBurnie` (subtracted on line 730) reduces `totalBurnie` for subsequent burns in the same period.

**Verdict: SAFE (INFO)** -- The uint96 truncation for `burnieOwed` is theoretically possible if BURNIE supply grows to extreme levels (~79B+ tokens held by sDGNRS), but this would require a ~20,000x increase from the initial 2M BURNIE allocation. Under realistic economic parameters, the risk is negligible. No explicit cap exists, which is a design observation rather than a vulnerability.

#### 4. uint48 for periodIndex (Line 757)

```solidity
// StakedDegenerusStonk.sol:757
claim.periodIndex = currentPeriod;
```

- `currentPeriod` is returned by `game.currentDayView()` as `uint48` (see GameTimeLib.sol:21 return type)
- No cast is needed -- the return type matches the struct field type
- `uint48.max` = 281 trillion days from deploy, which is ~770 billion years. No overflow risk.

**SAFE:** No truncation possible.

#### 5. uint16 Cast for activityScore (Lines 760-761)

```solidity
// StakedDegenerusStonk.sol:760-761
if (claim.activityScore == 0) {
    claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
}
```

- `game.playerActivityScore()` returns `uint256 scoreBps` (interface at line 87, implementation at line 2490)
- The `uint16()` cast truncates to the lower 16 bits before the `+ 1`
- `uint16.max = 65535`

**Maximum possible `playerActivityScore` (from `_playerActivityScore` at DegenerusGame.sol:2488-2563):**

**Deity pass path** (highest possible):
| Component | Max Value (bps) | Source |
|-----------|----------------|--------|
| Streak (deity) | 5,000 | `50 * 100` (line 2514) |
| Mint count (deity) | 2,500 | `25 * 100` (line 2515) |
| Quest streak | 10,000 | `100 * 100` (line 2543, capped at 100) |
| Affiliate bonus | 5,000 | `50 * 100` (line 2548, capped at AFFILIATE_BONUS_MAX=50) |
| Deity pass bonus | 8,000 | `DEITY_PASS_ACTIVITY_BONUS_BPS` (line 2552) |
| **Total** | **30,500** | |

**Non-deity path** (highest possible):
| Component | Max Value (bps) | Source |
|-----------|----------------|--------|
| Streak | 5,000 | `50 * 100` (capped at 50 on line 2518) |
| Mint count | 2,500 | Max 25 points (line 2520-2523) |
| Quest streak | 10,000 | `100 * 100` (capped at 100) |
| Affiliate bonus | 5,000 | `50 * 100` (capped at 50) |
| Whale bundle bonus | 4,000 | 100-level bundle (line 2558) |
| **Total** | **26,500** | |

**Maximum activity score = 30,500 bps.** `uint16(30500) + 1 = 30501`. This fits in `uint16` (max 65535) with substantial headroom. No overflow or truncation.

**SAFE:** The activity score cannot overflow uint16.

---

## New Findings

### INFO-01: burnieOwed Has No Explicit Cap (Informational)

**Severity:** INFO
**Location:** StakedDegenerusStonk.sol:731, 756
**Description:** Unlike `ethValueOwed` which is bounded by `MAX_DAILY_REDEMPTION_EV` (160 ETH) before the uint96 cast, `burnieOwed` has no analogous cap. The uint96 truncation is prevented only by economic assumptions about BURNIE supply growth. If sDGNRS ever holds more than ~79.2 billion BURNIE (7.922e28 raw units), and a player burns a significant share of sDGNRS supply, the `uint96()` cast on line 756 would silently truncate, causing the player to receive less BURNIE than they are owed.

**Mitigation:** The initial BURNIE allocation to sDGNRS is 2M (2e24 raw), which is 4 orders of magnitude below the threshold. The 50% supply cap per period further limits exposure. Under realistic protocol economics, this is not exploitable.

**Recommendation:** Consider adding an explicit `burnieOwed` cap check before the uint96 cast, similar to the ethValueOwed cap, or document this as a known design constraint.

---

## Summary

| Requirement | Verdict | Key Evidence |
|-------------|---------|-------------|
| REDM-03: 160 ETH Daily Cap | **SAFE** | Cap check (L753) uses cumulative uint256 comparison before uint96 cast (L755). Period gating (L748) prevents cross-period stacking. Cross-day boundary analysis confirms by-design behavior with RNG gate. |
| REDM-05: Slot Packing | **SAFE** | 96 + 96 + 48 + 16 = 256 bits exactly. ethValueOwed safe (1.6e20 << 7.9e28). burnieOwed safe under realistic economics (2e24 << 7.9e28). periodIndex natively uint48. activityScore max 30,501 << 65,535. |

**New findings:** 1 (INFO-01: burnieOwed lacks explicit cap)
