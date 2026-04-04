# Phase 177 Comment Audit — Plan 01 Findings
**Contracts:** DegenerusAdmin, DegenerusVault, DegenerusAffiliate, DegenerusDeityPass
**Requirement:** CMT-04
**Date:** 2026-04-03
**Total findings this plan:** 2 LOW, 2 INFO

---

## DegenerusAdmin

### Finding ADM-01 (LOW) — `_applyVote` NatSpec claims three return values but function returns two

**Location:** `contracts/DegenerusAdmin.sol` lines 789-793 (NatSpec), line 798 (signature)

**Comment says:**
```
/// @dev Calculate new cumulative weights after a vote, handling vote changes.
///      Returns (newApprove, newReject, scaledWeight) — caller applies to storage.
```

**Code does:**
The function signature is `returns (uint40, uint40)` — only two values: `newApprove` and `newReject`. There is no third return value `scaledWeight`. The stale mention of `scaledWeight` suggests this function once returned a third value (possibly the weight used) which was removed. A reader following the NatSpec expecting a third return value would misunderstand the function's interface.

---

### Finding ADM-02 (INFO) — `threshold()` NatSpec says decay happens "over 7 days" but the 5% floor is reached at 6 days

**Location:** `contracts/DegenerusAdmin.sol` line 38 (architecture overview)

**Comment says:**
```
/// - Approval voting with decaying threshold (50% → 5% over 7 days)
```

**Code does:**
The `threshold()` function decays from 50% to 5% over **6 days (144 hours)** — `if (elapsed >= 144 hours) return 500` (5%). The proposal **expires** (threshold = 0) at 168 hours (7 days). The 7-day figure refers to the lifetime, not the decay window. A warden might argue the 5% floor exists for only 1 day before expiry — the current description conflates the decay endpoint with the lifetime. INFO because it does not materially mislead about the security model (the actual thresholds are correct in the implementation).

---

### Finding ADM-03 (INFO) — `onTokenTransfer` uses invalid NatSpec param tag `@param ---`

**Location:** `contracts/DegenerusAdmin.sol` lines 990

**Comment says:**
```
/// @param --- Unused calldata (required by ERC-677 interface).
```

**Code does:**
The third parameter is unnamed (`bytes calldata`) in the function signature, which is valid Solidity. However, `@param ---` is not a valid NatSpec param tag — a doc generator would either ignore it or produce a warning. The unused calldata should simply be omitted from NatSpec or documented as `@dev Third param is unused calldata (required by ERC-677 interface).` INFO because it is a documentation tooling issue only.

---

## DegenerusVault

### Finding VLT-01 (LOW) — `gamePurchaseDeityPassFromBoon` NatSpec says "msg.value is retained in the vault" which is misleading

**Location:** `contracts/DegenerusVault.sol` line 571

**Comment says:**
```
/// @dev Uses vault ETH + claimable winnings; msg.value is retained in the vault.
```

**Code does:**
`msg.value` flows into the vault's `address(this).balance` when the payable function is called. The function then sends exactly `priceWei` out via `purchaseDeityPass{value: priceWei}`. If `msg.value == priceWei`, the entire amount is forwarded out and nothing is retained. If `msg.value > priceWei`, the surplus stays. The comment "msg.value is retained" implies the caller's ETH stays in the vault unconditionally, but the vault's balance is immediately reduced by `priceWei`. The intended meaning (that the function does not forward all ETH, unlike a pure pass-through) is not clearly expressed. A reader could conclude the function accepts ETH and keeps it, which is only partially true.

---

No additional discrepancies found in DegenerusVault. The vault accounting comments, access control descriptions, stETH integration comments, and NatSpec on all public/external functions accurately describe code behavior. The refill mechanism, reserve calculation formulas, share class token descriptions, and deposit/claim flow documentation are all correct.

---

## DegenerusAffiliate

### Accuracy confirmation — v17.1 tiered bonus rate

**Location:** `contracts/DegenerusAffiliate.sol` lines 659-684 (`affiliateBonusPointsBest`)

The NatSpec states: "Tiered rate: 4 points per ETH for the first 5 ETH (20 pts), then 1.5 points per ETH for the next 20 ETH (30 pts). Cap: 50 at 25 ETH."

Code at lines 679-684:
```solidity
if (sum <= 5 ether) {
    points = (sum * 4) / 1 ether;
} else {
    points = 20 + ((sum - 5 ether) * 3) / 2 ether;
}
return points > AFFILIATE_BONUS_MAX ? AFFILIATE_BONUS_MAX : points;
```

`(sum * 3) / 2 ether` = 1.5 points/ETH for the second tier. `AFFILIATE_BONUS_MAX = 50`. Cap is reached at 5+20=25 ETH. **All values verified correct.**

### Accuracy confirmation — 3-tier referral split

**Location:** `contracts/DegenerusAffiliate.sol` lines 14, 596-603

The architecture comment "3-tier referral: Player → Affiliate (75%) / Upline1 (20%) / Upline2 (5%) winner-takes-all roll" is confirmed by code:
```solidity
uint256 roll = ... % 20;
// 0-14 = affiliate (75%), 15-18 = upline1 (20%), 19 = upline2 (5%)
```
**Correct.**

### Accuracy confirmation — affiliate reward percentages

**Location:** `contracts/DegenerusAffiliate.sol` lines 20-21, 164-166, 492-504

Architecture block: "Fresh ETH rewards: 25% (levels 0-3), 20% (levels 4+)" and "Recycled ETH rewards: 5% (all levels)"

Constants: `REWARD_SCALE_FRESH_L1_3_BPS = 2_500`, `REWARD_SCALE_FRESH_L4P_BPS = 2_000`, `REWARD_SCALE_RECYCLED_BPS = 500`.

Code selection logic (lines 496-503): `lvl <= 3 ? REWARD_SCALE_FRESH_L1_3_BPS : REWARD_SCALE_FRESH_L4P_BPS` for fresh ETH, `REWARD_SCALE_RECYCLED_BPS` otherwise. **All values verified correct.**

### Accuracy confirmation — affiliate bonus cache (MINT-CMT-01 related check)

No comment in DegenerusAffiliate claims the bonus is "tracked separately" or "read fresh from storage each time." The contract provides `affiliateBonusPointsBest()` as a view function called externally. No discrepancy with the mintPacked_ cache behavior (the cache lives in MintModule, not here). **No issue found.**

No comment discrepancies found in DegenerusAffiliate. All reward rates, tier logic, access control descriptions (`payAffiliate` restricted to coin or game), leaderboard comments, and NatSpec are accurate.

---

## DegenerusDeityPass

No discrepancies found in DegenerusDeityPass.

The contract's comments and NatSpec are accurate:
- Contract header: "Soulbound ERC721 for deity passes. 32 tokens max. tokenId = symbolId (0-31)." — Correct (tokenId < 32 enforced at line 382).
- `mint()`: "Only callable by the game contract during purchase." — Correct (`msg.sender != ContractAddresses.GAME` at line 381).
- Transfer-blocking functions (`approve`, `setApprovalForAll`, `transferFrom`, `safeTransferFrom`): All accurately documented as soulbound.
- `tokenURI()`: "Uses internal renderer by default; optional external renderer can override but never break tokenURI due to bounded staticcall + fallback." — Correct via `try/catch` in `_tryRenderExternal`.
- `setRenderer()` and `setRenderColors()`: Accurate NatSpec.
- No comment in DegenerusDeityPass describes the HAS_DEITY_PASS_SHIFT bit — that logic lives in BitPackingLib/MintModule. No discrepancy.

---

## Summary

| ID | Severity | Contract | Description |
|----|----------|----------|-------------|
| ADM-01 | LOW | DegenerusAdmin | `_applyVote` NatSpec claims 3 return values but function returns 2 |
| ADM-02 | INFO | DegenerusAdmin | Architecture doc says "50%→5% over 7 days" but 5% is reached at day 6 |
| ADM-03 | INFO | DegenerusAdmin | `onTokenTransfer` uses invalid `@param ---` NatSpec tag |
| VLT-01 | LOW | DegenerusVault | `gamePurchaseDeityPassFromBoon` NatSpec "msg.value is retained" is misleading |

**Total: 2 LOW, 2 INFO** (VLT-02 retracted after re-read confirmed documentation was accurate)
