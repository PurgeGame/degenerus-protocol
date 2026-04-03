# Phase 175 Comment Audit — Plan 05 Findings
**Contracts:** DegenerusGameWhaleModule, DegenerusGameGameOverModule, DegenerusGamePayoutUtils
**Requirement:** CMT-01
**Date:** 2026-04-03
**Total findings this plan:** 2 LOW, 4 INFO

---

## DegenerusGameWhaleModule

### W05-01 — LOW — claimWhalePass: stale two-path comment, code is unconditionally level+1

**Location:** `DegenerusGameWhaleModule.sol` lines 971–973

**Comment says:**
```solidity
// Start level depends on game state:
// - Jackpot phase: tickets won't be processed this level, start at level+1
// - Otherwise: tickets can be processed this level, start at current level
```

**Code does:**
```solidity
uint24 startLevel = level + 1;
```

The code unconditionally assigns `startLevel = level + 1`. The comment describes two conditional branches — one for jackpot phase (level+1) and one for otherwise (current level) — but only the first branch was retained. The second branch (`start at current level`) no longer exists. A reader expecting a conditional would look for a branch that is absent.

This discrepancy also conflicts with the accurate NatSpec at line 960: "Tickets start at current level + 1 to avoid giving tickets for an already-active level."

---

### W05-02 — INFO — purchaseWhaleBundle: ticket count comment omits quantity multiplier

**Location:** `DegenerusGameWhaleModule.sol` line 305

**Comment says:**
```solidity
// Queue tickets: 40/lvl for bonus levels (passLevel to 10), 2/lvl for the rest
```

**Code does:**
```solidity
uint32 bonusTickets = uint32(WHALE_BONUS_TICKETS_PER_LEVEL * quantity);
uint32 standardTickets = uint32(WHALE_STANDARD_TICKETS_PER_LEVEL * quantity);
```

The comment says "40/lvl" and "2/lvl" but the actual ticket counts are `40 × quantity` per level and `2 × quantity` per level. For a single-bundle purchase (quantity=1) the comment is accurate, but for multi-bundle purchases (up to quantity=100) it understates the ticket count by a factor of `quantity`. The comment should read "40×Q/lvl … 2×Q/lvl" or "WHALE_BONUS_TICKETS_PER_LEVEL × quantity per bonus level."

---

### W05-03 — INFO — _lazyPassCost: parenthetical "(4 tickets per level)" is ambiguous

**Location:** `DegenerusGameWhaleModule.sol` lines 679–680

**Comment says:**
```solidity
/// @dev Compute the total ETH cost of a 10-level lazy pass starting at startLevel.
///      Cost equals the sum of per-level ticket prices (4 tickets per level).
```

**Code does:**
```solidity
for (uint24 i = 0; i < LAZY_PASS_LEVELS; ) {
    total += PriceLookupLib.priceForLevel(startLevel + i);
```

`priceForLevel` returns the price of 1 ticket at a given level. The cost sums this across 10 levels (1-ticket price × 10 levels). The parenthetical "(4 tickets per level)" describes the *pass benefit* (4 tickets queued per level), not the cost calculation. A reader could misread this as "the sum of 4-ticket prices per level," which would imply a 4× higher cost than the actual implementation. The comment should clearly separate the benefit description from the cost formula, e.g. "…the sum of 1-ticket prices across 10 levels (the pass grants 4 tickets per level as a benefit)."

---

### W05-04 — INFO — purchaseWhaleBundle NatSpec: "levels passLevel-10" ambiguously describes the bonus tier range

**Location:** `DegenerusGameWhaleModule.sol` line 172

**Comment says:**
```
*      - Queues 40 × quantity bonus tickets/lvl for levels passLevel-10, 2 × quantity standard tickets/lvl for the rest.
```

**Code does:**
```solidity
bool isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL);
// WHALE_BONUS_END_LEVEL = 10
```

The notation "passLevel-10" is ambiguous. It could be read as "levels (passLevel minus 10)" (i.e., a subtraction) rather than the intended "levels passLevel through 10." If passLevel > 10, the isBonus condition is always false (all tickets are standard), a case the comment does not address. The comment should read "for levels passLevel through 10 (empty range when passLevel > 10)."

---

## DegenerusGameGameOverModule

### G05-01 — LOW — handleFinalSweep / _sendToVault: comments say "DGNRS" but code sends to SDGNRS (sDGNRS / StakedDegenerusStonk)

**Location:** `DegenerusGameGameOverModule.sol` lines 73, 182, 207, 219

**Comment says (line 182):**
```
/// @dev Forfeits all unclaimed winnings and sweeps entire balance.
///      Funds are split 33% DGNRS / 33% vault / 34% GNRUS.
```

**Comment says (line 207):**
```
/// @dev Send funds to DGNRS (33%), vault (33%), and GNRUS (34%), stETH-first for all.
```

**Comment says (line 73):**
```
///      - Any uncredited remainder swept to vault and DGNRS
```

**Code does (line 219):**
```solidity
stethBal = _sendStethFirst(ContractAddresses.SDGNRS, thirdShare, stethBal);
```

`ContractAddresses.SDGNRS` is the StakedDegenerusStonk (sDGNRS) contract, not DegenerusStonk (DGNRS). The two are separate contracts with distinct addresses. All three comments say "DGNRS" where the actual recipient is "sDGNRS." An auditor or developer who checks the DGNRS token contract would be looking at the wrong contract.

**Fix:** Replace "DGNRS" with "sDGNRS" in all three comment sites (lines 73, 182, 207).

---

### G05-02 — INFO — handleGameOverDrain NatSpec: VRF fallback description describes AdvanceModule logic, not this function

**Location:** `DegenerusGameGameOverModule.sol` lines 74–76

**Comment says:**
```
///      VRF fallback: Uses rngWordByDay which may use historical VRF word as secure
///      fallback if Chainlink VRF is stalled (after 3 day wait period).
```

**Code does (lines 139–140):**
```solidity
uint256 rngWord = rngWordByDay[day];
if (rngWord == 0) return; // RNG not ready yet — don't latch, allow retry
```

`handleGameOverDrain` only reads `rngWordByDay[day]` and exits early if it is zero. The VRF fallback logic (historical word selection, 3-day wait period) lives in `_gameOverEntropy` in AdvanceModule, which is called before `handleGameOverDrain`. The comment in this function's NatSpec misleads readers into thinking the fallback is implemented here; it is not — this function only consumes a pre-computed word.

---

## DegenerusGamePayoutUtils

No discrepancies found.

All comments in `DegenerusGamePayoutUtils.sol` (106 lines) were verified against the code:

- `PlayerCredited` event NatSpec: correct (player == recipient in `_creditClaimable`).
- `HALF_WHALE_PASS_PRICE = 2.25 ether` comment ("each half-pass = 1 ticket/level for 100 levels"): matches `claimWhalePass` behavior.
- `_creditClaimable` NatSpec: accurate to the storage write and event emission.
- `_calcAutoRebuy` NatSpec: "1-4 levels ahead" matches `(entropy & 3) + 1`. "+1 → next (25%), +2/+3/+4 → future (75%)" is numerically correct. `ticketPrice = priceForLevel >> 2` (quarter-price divisor) is unlabeled but consistent with the bonus-scaled ticket math.
- `_queueWhalePassClaimCore` NatSpec: accurate to the division-by-`HALF_WHALE_PASS_PRICE` and remainder-to-claimable logic.
- Math in all three functions cross-checked: no denominator errors, no mislabeled percentage values, no incorrect recipients.
