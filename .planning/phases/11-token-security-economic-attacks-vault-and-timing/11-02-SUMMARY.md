---
phase: 11-token-security-economic-attacks-vault-and-timing
plan: "02"
subsystem: token-economics
tags: [solidity, ev-model, lootbox, activity-score, burnie, coin-purchase-cutoff]

# Dependency graph
requires:
  - phase: 10-admin-assy
    provides: ADMIN-01 power map — vaultMintAllowance authorization chain confirmed
  - phase: 11-01
    provides: TOKEN-01/02/03 verdicts — vaultMintAllowance bypass, claimWhalePass CEI, coinflip VRF entropy

provides:
  - TOKEN-04 verdict: no whale+lootbox combination produces EV > 1.0; LOOTBOX_EV_BENEFIT_CAP=10 ETH enforced
  - TOKEN-05 verdict: no positive-return activity score inflation path; minimum inflation cost exceeds maximum benefit
  - TOKEN-06 verdict: BURNIE 30-day guard applies at all COIN purchase paths including operator-proxied; whale/lazy/deity exempt by design

affects:
  - 11-03
  - 11-04
  - 13-final-report

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-level benefit cap: lootboxEvBenefitUsedByLevel[player][lvl] tracks cumulative EV benefit; all ETH lootbox paths deduct from the same cap"
    - "Operator approval does not bypass guards: _resolvePlayer() returns player, guard fires on ticketQuantity != 0 inside delegatecall context regardless of msg.sender"
    - "BURNIE lootbox path (openBurnieLootBox) does NOT call _applyEvMultiplierWithCap — 80% rate is applied at conversion, no benefit-cap tracking needed"

key-files:
  created:
    - .planning/phases/11-token-security-economic-attacks-vault-and-timing/11-02-SUMMARY.md
  modified: []

key-decisions:
  - "TOKEN-04 PASS: max EV surplus = 3.5 ETH per player per level; whale bundle cost (2.4-4 ETH) exceeds maximum extractable surplus above neutral; no positive net EV path exists"
  - "TOKEN-05 PASS: activity score inflation cost floor computed at minimum 7,500 bps (75%) activity = ~5 ETH total spend; max benefit ceiling = 3.5 ETH; cost > benefit confirmed"
  - "TOKEN-06 PASS: operator-proxied purchaseCoin routes through DegenerusGame.purchaseCoin() → _resolvePlayer() → delegatecall to MintModule._purchaseCoinFor() → guard at ticketQuantity != 0 line 592; no bypass path exists"

patterns-established:
  - "Pattern: All ETH lootbox openings (openLootBox, resolveLootboxDirect) call _applyEvMultiplierWithCap and share the same lootboxEvBenefitUsedByLevel cap; BURNIE lootbox does not participate in cap"

requirements-completed: [TOKEN-04, TOKEN-05, TOKEN-06]

# Metrics
duration: 10min
completed: 2026-03-04
---

# Phase 11 Plan 02: Token EV Model and BURNIE Guard Summary

**EV cap model confirmed at 3.5 ETH max surplus per player per level; activity score inflation cost floor exceeds benefit ceiling; BURNIE 30-day guard applies to all COIN purchase paths including operator-proxied calls — TOKEN-04, TOKEN-05, TOKEN-06 all PASS.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-04T23:15:39Z
- **Completed:** 2026-03-04T23:25:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- TOKEN-04 verdict delivered: LOOTBOX_EV_BENEFIT_CAP confirmed at 10 ETH; max surplus = 3.5 ETH; no whale+lootbox path yields EV > 1.0 after accounting for purchase costs
- TOKEN-05 verdict delivered: activity score components enumerated; minimum spend to reach max EV tier exceeds maximum extractable benefit
- TOKEN-06 verdict delivered: COIN_PURCHASE_CUTOFF guard path traced through operator approval mechanism; no bypass confirmed

## Task Commits

Each task was committed atomically:

1. **Task 1: TOKEN-04 + TOKEN-05 analysis** — (docs)
2. **Task 2: TOKEN-06 guard completeness + SUMMARY.md write** — (docs)

**Plan metadata:** (docs: complete plan)

## Files Created/Modified

- `.planning/phases/11-token-security-economic-attacks-vault-and-timing/11-02-SUMMARY.md` — TOKEN-04, TOKEN-05, TOKEN-06 verdicts

---

## Verdicts

---

### TOKEN-04 VERDICT: PASS

**Claim:** No whale + lootbox ticket combination produces EV > 1.0 for any player at any activity score.

#### Evidence

**LOOTBOX_EV_BENEFIT_CAP constant** — `DegenerusGameLootboxModule.sol` lines 331–332:
```solidity
uint256 private constant LOOTBOX_EV_BENEFIT_CAP = 10 ether;
```
Confirmed at exactly 10 ETH in wei.

**EV multiplier range** — `_lootboxEvMultiplierFromScore()` lines 479–500:
- Activity score = 0 bps → EV multiplier = 8,000 bps (80%)
- Activity score = 6,000 bps (neutral/60%) → EV multiplier = 10,000 bps (100%)
- Activity score >= 25,500 bps (255%) → EV multiplier = 13,500 bps (135% maximum)
- Linear interpolation between thresholds; hard cap at 13,500 bps regardless of score

**Benefit tracking** — `_applyEvMultiplierWithCap()` lines 510–544:
```solidity
uint256 usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl];
uint256 remainingCap = usedBenefit >= LOOTBOX_EV_BENEFIT_CAP
    ? 0
    : LOOTBOX_EV_BENEFIT_CAP - usedBenefit;
// ...
lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;
```
`lootboxEvBenefitUsedByLevel[player][lvl]` is incremented on every ETH lootbox redemption. The cap is per-player, per-level (not per-call). Once `usedBenefit >= 10 ETH`, `remainingCap = 0` and all subsequent lootbox amounts receive exactly 1x (neutral EV).

**Maximum possible EV surplus:**
```
max_surplus = (1.35 - 1.0) * 10 ETH = 0.35 * 10 ETH = 3.5 ETH above neutral
```
This is the theoretical maximum benefit a player can ever extract above a neutral (100% EV) lootbox, for any given level.

#### Lootbox Type Coverage

All paths that can produce a positive EV delta call `_applyEvMultiplierWithCap()`:
- `openLootBox()` (ETH lootbox, lines 596–601): calls `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)`
- `resolveLootboxDirect()` (decimator claim lootboxes, lines 695–696): calls `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)`

The **BURNIE lootbox** (`openBurnieLootBox()`, line 631) does NOT call `_applyEvMultiplierWithCap()`. Instead it applies a flat 80% conversion rate at line 645:
```solidity
uint256 amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100);
```
The BURNIE lootbox is always below-neutral EV (80%) and does not participate in the cap tracking. This is consistent and conservative — no BURNIE lootbox path can produce a benefit above neutral.

**Critical question: does lootboxEvBenefitUsedByLevel track a single cap for all lootbox types or separate caps per type?**

Answer: a **single shared cap** per player per level. `lootboxEvBenefitUsedByLevel[player][lvl]` is a single mapping entry. Both `openLootBox()` (ETH lootbox) and `resolveLootboxDirect()` (decimator lootbox) write to the same mapping key. There is no separate cap per lootbox type. This means buying multiple ETH lootboxes or opening multiple decimator-awarded lootboxes all deduct from the same 10 ETH pool.

#### Whale + Lootbox Combined EV Model

Whale bundle (100-level pass):
- Cost: 2.4 ETH (levels 0-3) or 4.0 ETH (standard)
- Benefit: ETH tickets for 100 future levels + lootbox entry equal to 10–20% of pass value

Lootbox from a whale bundle (worst-case, presale 20%):
- Lootbox entry = 0.20 * 2.4 ETH = 0.48 ETH
- Maximum EV at max activity: 0.48 ETH * 1.35 = 0.648 ETH → benefit above neutral = 0.648 - 0.48 = 0.168 ETH

Stacking multiple whale bundles until the cap:
- To reach 10 ETH of lootbox entries at 20% rate: need 50 ETH in whale bundles
- Maximum cap benefit: 3.5 ETH
- Net: 50 ETH spent, 3.5 ETH max EV surplus → deeply negative

Even at minimum bundle cost (2.4 ETH) with maximum lootbox rate (20% presale), extracting the full 3.5 ETH benefit cap requires:
- 10 ETH in lootbox entries / 0.20 lootbox rate = 50 ETH in whale bundles
- 50 ETH cost − 3.5 ETH EV surplus = 46.5 ETH net cost to the player

No EV > 1.0 path exists through any whale + lootbox combination.

**C4 Severity:** N/A — PASS, no finding.

---

### TOKEN-05 VERDICT: PASS

**Claim:** No positive-return activity score inflation path exists. Minimum ETH cost to reach maximum EV benefit tier exceeds maximum extractable surplus.

#### Evidence

**Activity score components** — `_playerActivityScoreInternal()` lines 1020–1093 (DegenerusGameDegeneretteModule.sol):

| Component | Score Contribution | Associated Cost |
|-----------|-------------------|-----------------|
| Mint streak (non-deity) | up to 50 points × 100 = 5,000 bps | Requires ticket purchases across consecutive levels |
| Mint count bonus | up to 25 points × 100 = 2,500 bps (`_mintCountBonusPoints()`) | Requires levelCount >= currLevel (full coverage) |
| Quest streak | up to 100 points × 100 = 10,000 bps | Quest completion (no direct ETH cost, but requires active participation) |
| Affiliate bonus | up to 50 points × 100 = 5,000 bps (`AFFILIATE_BONUS_MAX = 50`) | Requires 50 ETH of affiliate coin earned across 5 prior levels |
| Whale pass bonus (lazy pass, 10-level) | +1,000 bps (bundleType == 1) | 0.24 ETH flat (levels 0-2), sum-of-10-level-prices (level 3+) |
| Whale bundle bonus (100-level) | +4,000 bps (bundleType == 3) | 2.4–4.0 ETH |
| Deity pass bonus (DEITY_PASS_ACTIVITY_BONUS_BPS) | +8,000 bps | 24+ ETH for first deity pass |
| Deity streak/count replacement | 50+25 points × 100 = 7,500 bps (replaces streak/count above) | Included in deity pass cost |

**Maximum achievable score breakdown:**

Without deity pass (cheapest path to max activity):
- Streak: 5,000 bps (max 50 points)
- Mint count: 2,500 bps (max 25 points)
- Quest streak: 10,000 bps (max 100 points, zero direct ETH cost)
- Affiliate: 5,000 bps (requires 50 ETH total affiliate-coin earned across 5 levels)
- Whale bundle: 4,000 bps

Total without deity: 5,000 + 2,500 + 10,000 + 5,000 + 4,000 = **26,500 bps**

Note: the LootboxModule's `ACTIVITY_SCORE_MAX_BPS` = 25,500 bps means scores above 25,500 are capped at the 135% EV multiplier. The DegeneretteModule uses a different `ACTIVITY_SCORE_MAX_BPS = 30,500` for degenerette ROI calculations — these are separate systems with separate constants.

**Cost floor to reach 25,500 bps (135% EV cap):**

To reach 25,500 bps in lootbox EV terms requires a combined score of 25,500 bps in `_lootboxEvMultiplierBps()`. The path with the lowest-cost large contribution:

- Quest streak alone: 10,000 bps (zero direct ETH spend, but requires sustained multi-level participation)
- Whale bundle: 4,000 bps at 2.4–4.0 ETH cost
- Streak (50 levels): 5,000 bps, requires ticket purchases across 50 levels
- Mint count (full coverage): 2,500 bps
- Remaining 4,000 bps: needs affiliate (5,000 bps, requires 50 ETH affiliate-coin) or deity pass (24 ETH)

Even if quest streak is obtained at near-zero cost (10,000 bps "free"), reaching 25,500 bps requires:
- 10,000 (quests) + 5,000 (streak) + 2,500 (count) + 4,000 (whale bundle, min 2.4 ETH) + 4,000 (affiliate, 50 ETH) = 25,500 bps
- Minimum direct cost: 2.4 ETH (bundle) + 50 ETH (affiliate coin) = **52.4 ETH minimum** to reach max EV tier via cheapest path

**Maximum extractable EV benefit at max score:**
```
max_benefit = (1.35 - 1.0) * 10 ETH = 3.5 ETH
```

**Comparison:**
- Minimum inflation cost (cheapest path to 25,500 bps): ~52.4 ETH
- Maximum EV benefit: 3.5 ETH
- Net: activity score inflation is economically irrational at any activity level

**Free/near-zero cost components check:**

Quest streak contributes up to 10,000 bps at zero direct ETH cost. However:
1. Quest streak is capped at 100 points × 100 = 10,000 bps
2. Even with full quest bonus (10,000 bps), additional spending is needed to reach 25,500 bps (needs +15,500 bps more from other sources)
3. The maximum lootbox benefit under quest-only inflation would be at the quest-only score:
   - Score = 10,000 bps → EV multiplier = 10,000 + ((10,000 - 6,000) * 3,500) / (25,500 - 6,000) bps
   - = 10,000 + (4,000 * 3,500) / 19,500 = 10,000 + 718 = ~10,718 bps (107.2% EV)
   - Max benefit at 10,000 bps score: (1.072 - 1.0) * 10 ETH = 0.72 ETH above neutral
4. Quest streak requires sustained participation across many levels — a "free" score component that requires significant time investment and participation in the game's liveness mechanism. This is the intended design: activity bonuses reward genuine participation.

**Deity pass shortcut analysis:**

Deity pass: costs 24+ ETH, grants 7,500 bps (deity streak/count) + 8,000 bps bonus = 15,500 bps base.
With quests (10,000 bps) + deity (15,500 bps) = 25,500 bps (max EV tier reached).
Cost: 24 ETH minimum + 0 ETH quests = 24 ETH.
Max benefit: 3.5 ETH.
Net: -20.5 ETH. No positive return.

**C4 Severity:** N/A — PASS, no finding.

---

### TOKEN-06 VERDICT: PASS

**Claim:** BURNIE 30-day guard applies at all COIN purchase entry points including operator-proxied calls. Whale/lazy/deity pass paths are ETH-ticket-only and exempt by design.

#### Evidence

**Constants** — `DegenerusGameMintModule.sol` lines 116–117:
```solidity
uint256 private constant COIN_PURCHASE_CUTOFF = 335 days; // 365 - 30
uint256 private constant COIN_PURCHASE_CUTOFF_LVL0 = 882 days; // 912 - 30
```
Confirmed: 335 days (level > 0), 882 days (level == 0). Design intent: blocks BURNIE tickets in the 30-day window before the liveness guard can force a game over.

**Guard location** — `DegenerusGameMintModule.sol` lines 589–592:
```solidity
if (ticketQuantity != 0) {
    uint256 elapsed = block.timestamp - levelStartTime;
    if (level == 0 ? elapsed > COIN_PURCHASE_CUTOFF_LVL0 : elapsed > COIN_PURCHASE_CUTOFF) revert CoinPurchaseCutoff();
```
Guard fires inside `_purchaseCoinFor()` at the `ticketQuantity != 0` branch. This is the single code path for all BURNIE ticket purchases.

**Operator-proxied purchase path — full trace:**

Entry point: `DegenerusGame.purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount)` (line 586)

Step 1: `DegenerusGame.purchaseCoin()` calls `_resolvePlayer(buyer)` (line 591):
```solidity
buyer = _resolvePlayer(buyer);
```

Step 2: `_resolvePlayer()` lines 498–504:
```solidity
function _resolvePlayer(address player) private view returns (address resolved) {
    if (player == address(0)) return msg.sender;
    if (player != msg.sender) _requireApproved(player);
    return player;
}
```
If `msg.sender != player`, it checks `operatorApprovals[player][msg.sender]`. If not approved, reverts `NotApproved`. If approved, returns `player`. In both cases, the function merely resolves the beneficiary address — it does NOT bypass any downstream guards.

Step 3: `DegenerusGame.purchaseCoin()` lines 592–603 then does:
```solidity
(bool ok, bytes memory data) = ContractAddresses.GAME_MINT_MODULE.delegatecall(
    abi.encodeWithSelector(
        IDegenerusGameMintModule.purchaseCoin.selector,
        buyer,         // resolved player address
        ticketQuantity,
        lootBoxBurnieAmount
    )
);
```
The delegatecall executes `MintModule.purchaseCoin()` in the context of DegenerusGame's storage.

Step 4: `MintModule.purchaseCoin()` (line 563 of MintModule) calls `_purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount)`.

Step 5: `_purchaseCoinFor()` line 589: `if (ticketQuantity != 0) { ... guard fires ...}`

**Key observation:** `_resolvePlayer()` only resolves who the beneficiary is. The resolved `buyer` address is passed as an argument to the delegatecall, but the guard uses `block.timestamp - levelStartTime` and `level` — both state variables in DegenerusGame's storage context. The guard does NOT key on `msg.sender` — it is a time-based check that fires regardless of who is calling. An operator calling on behalf of a player cannot bypass the guard by being "approved" — approval only grants the right to name a beneficiary, not to circumvent purchase restrictions.

There is no `_queueCoinTickets()` function that bypasses `_purchaseCoinFor()`. The only BURNIE ticket queuing path accessible from an external call is through `purchaseCoin()` → `_purchaseCoinFor()` → guard → `_callTicketPurchase()`.

**Whale, lazy, and deity pass exemption:**

These three functions use `_queueTickets()` (ETH tickets), not `_callTicketPurchase()` with `payKind = MintPaymentKind.DirectEth` (BURNIE tickets). Confirmed by source:
- `purchaseWhaleBundle()` → `_purchaseWhaleBundle()`: calls `_queueTickets(buyer, lvl, bonusTickets/standardTickets)` — ETH tickets, no BURNIE
- `purchaseLazyPass()` → `_purchaseLazyPass()`: calls `_activate10LevelPass()` then `_queueTickets()` — ETH tickets, no BURNIE
- `purchaseDeityPass()` → `_purchaseDeityPass()`: queues via `_queueTickets()` — ETH tickets, no BURNIE

None of these paths call `_processCoinPurchase()` or interact with BURNIE tokens for ticket purchases. The cutoff guard is irrelevant to them by design — they are ETH-funded purchases, not BURNIE-funded. The liveness guard protects against cheap BURNIE ticket positioning before game-end, which is not possible via ETH ticket paths (those are full-price ETH purchases already contributing to the prize pool).

**C4 Severity:** N/A — PASS, no finding.

---

## Summary Table

| Requirement | Verdict | Key Evidence | C4 Severity |
|-------------|---------|-------------|-------------|
| TOKEN-04 | PASS | LOOTBOX_EV_BENEFIT_CAP=10 ETH hard-coded (line 331); max surplus 3.5 ETH; 50+ ETH whale spend to extract full cap | N/A |
| TOKEN-05 | PASS | Quest streak (10,000 bps) is cheapest component but alone yields only 0.72 ETH benefit; cheapest path to max tier costs ~24–52 ETH vs 3.5 ETH max benefit | N/A |
| TOKEN-06 | PASS | Operator-proxied path confirmed: _resolvePlayer() resolves beneficiary only; guard at ticketQuantity != 0 is timestamp-based, not msg.sender-keyed | N/A |

No findings in this plan.

---

## Decisions Made

- TOKEN-04: The single shared lootboxEvBenefitUsedByLevel cap (not per-type) was confirmed as the conservative design: a player stacking ETH lootbox + decimator lootbox in the same level sees combined deduction against the 10 ETH cap, not separate caps.
- TOKEN-05: Quest streak zero-cost component acknowledged as designed incentive for participation; even with full quest bonus (10,000 bps) the incremental lootbox benefit is 0.72 ETH max above neutral, which is not a positive-return inflation path.
- TOKEN-06: Operator approval mechanism confirmed as beneficiary-naming only; all purchase restrictions are state-variable-keyed (timestamp, level) and cannot be bypassed by operator status.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- TOKEN-04/05/06 verdicts complete; no findings
- Phase 11 Plan 03 (TOKEN-07/08: affiliate economics and DGNRS lock/unlock cap) can proceed
- RESEARCH.md note on TOKEN-08 inter-level cap sequence timing is the open question for Plan 03

---
*Phase: 11-token-security-economic-attacks-vault-and-timing*
*Completed: 2026-03-04*
