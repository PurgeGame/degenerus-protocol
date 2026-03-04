---
phase: 11-token-security-economic-attacks-vault-and-timing
plan: "03"
subsystem: security-audit
tags: [affiliate, rakeback, circular-ring, wash-trading, dgnrs, lock, unlock, cap-reset, timing]

# Dependency graph
requires:
  - phase: 11-token-security-economic-attacks-vault-and-timing
    provides: RESEARCH.md with TOKEN-07 and TOKEN-08 open questions
provides:
  - TOKEN-07 verdict: affiliate self-referral and ring EV analysis — PASS
  - TOKEN-08 verdict: lockForLevel/unlock level-transition timing — PASS
affects: [phase-13-final-report]

# Tech tracking
tech-stack:
  added: []
  patterns: [source-trace-and-arithmetic-analysis, c4-severity-assignment]

key-files:
  created:
    - .planning/phases/11-token-security-economic-attacks-vault-and-timing/11-03-SUMMARY.md
  modified: []

key-decisions:
  - "TOKEN-07 PASS: Self-referral blocked at both referPlayer() line 394 and payAffiliate() line 486; REF_CODE_LOCKED = bytes32(1) (not VAULT address) permanently blocks re-registration; circular ring is bounded, not positive-EV beyond rakeback design; wash trading is a 20% discount, not extraction"
  - "TOKEN-08 PASS: Same-level unlock guarded by LockStillActive revert at unlock() line 469; auto-unlock in lockForLevel() resets spent counters atomically but does NOT credit level-N claimables before clearing them; _lockedClaimableValues is view-only, never updated by lockForLevel; no double-cap path exists"

patterns-established:
  - "Affiliate referral is one-way and one-time: each player has exactly one referrer slot; once filled (including REF_CODE_LOCKED), only presale-mutable VAULT referrals can update"
  - "DGNRS lock semantics: same-level guard via LockStillActive on unlock(); inter-level cap reset is intentional design, not exploitable"

requirements-completed: [TOKEN-07, TOKEN-08]

# Metrics
duration: 15min
completed: 2026-03-04
---

# Phase 11 Plan 03: TOKEN-07 and TOKEN-08 Affiliate/DGNRS Lock Verdicts Summary

**TOKEN-07 PASS and TOKEN-08 PASS: affiliate self-referral permanently blocked via REF_CODE_LOCKED sentinel, circular ring EV bounded below solo play, DGNRS same-level double-cap ruled out by LockStillActive guard and atomic counter reset**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-04T23:15:03Z
- **Completed:** 2026-03-04T23:30:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- TOKEN-07: confirmed self-referral block at two independent code paths; traced REF_CODE_LOCKED sentinel value and permanence; modeled 3-wallet ring EV and wash trading discount mathematically
- TOKEN-08: confirmed LockStillActive same-level guard; traced auto-unlock branch in lockForLevel() and demonstrated no claimable-credit bypass; resolved level-transition timing window with specific code citation

## TOKEN-07 VERDICT: PASS

**Affiliate Economic Exploits — No extractable positive EV beyond designed rakeback**

### Self-Referral Block

Two independent self-referral checks exist:

**1. `referPlayer()` — DegenerusAffiliate.sol line 394**
```solidity
if (referrer == address(0) || referrer == msg.sender) revert Insufficient();
```
Compares `affiliateCode[code_].owner` to `msg.sender`. If the caller owns the code they are trying to register under, the transaction reverts. No bypass path exists because the check is against the resolved owner address, not the code bytes.

**2. `payAffiliate()` — DegenerusAffiliate.sol lines 483–489**
```solidity
if (
    candidate.owner == address(0) ||
    candidate.owner == sender
) {
    // Invalid/self-referral: lock to VAULT as default.
    _setReferralCode(sender, REF_CODE_LOCKED);
    ...
}
```
The implicit registration path during gameplay also blocks self-referral and permanently locks the player's referral slot to the `REF_CODE_LOCKED` sentinel.

### REF_CODE_LOCKED Sentinel

**Value:** `bytes32 private constant REF_CODE_LOCKED = bytes32(uint256(1));` (line 207)

This is NOT the VAULT address — it is the scalar value `1` cast to bytes32. The comment in the plan describing it as "VAULT address" was imprecise; the actual sentinel is `bytes32(1)`.

**Permanence:** Once `playerReferralCode[player]` is set to `REF_CODE_LOCKED`, the mutability check in `_vaultReferralMutable()` (line 721) only permits updates when the stored code is `REF_CODE_LOCKED` OR `AFFILIATE_CODE_VAULT` AND the game's `lootboxPresaleActiveFlag()` returns true. After presale ends, even the locked-to-VAULT players are frozen. A player who received `REF_CODE_LOCKED` via invalid/self-referral attempt during an active game cannot re-register ever — the sentinel persists and routes rewards to VAULT permanently.

**`_referrerAddress()` behavior (line 745–749):**
```solidity
if (code == REF_CODE_LOCKED || code == AFFILIATE_CODE_VAULT) return ContractAddresses.VAULT;
```
VAULT receives affiliate earnings; VAULT has no human recipient to extract value — the funds go to the protocol treasury.

### Circular Ring EV Analysis

**Can a circular ring be formed?**

Referral assignment is one-way and one-per-player:
- A's referrer is set when A registers (once).
- B's referrer is set when B registers (once).
- Setting B's referrer to A does NOT change A's referrer.

Scenario: Actor controls wallets A, B, C.
- B registers under A's code → B's upline1 = A.
- C registers under B's code → C's upline1 = B, upline2 = A.
- A attempts to register under C's code → **allowed** (A has not yet registered a referral, and C != A). A's upline1 = C, upline2 = B.

A true 3-ring is achievable if A, B, and C are all unregistered when the ring is set up. However:

**EV Analysis for 3-ring A→C→B→A (each player registered under the next):**

Each player's purchase of `amount` ETH triggers:
- Direct affiliate (code owner): receives `scaledAmount * (1 - rakeback%)`
- Upline1: receives `scaledAmount * 20%`
- Upline2: receives `scaledAmount * 4%`

For fresh ETH levels 1-3, `scaledAmount = amount * 25%`. Total outflow from protocol per `amount` spent:
- Direct affiliate: up to 25% of scaledAmount (if rakeback=0)
- Upline1: 20% of scaledAmount = 5% of amount
- Upline2: 4% of scaledAmount = 1% of amount

Maximum total rakeback pool = 25% + 20% + 4% = 49% of `scaledAmount` = 12.25% of `amount` (fresh ETH, levels 1-3).

In a 3-ring, each player spends `amount` and receives rakeback payments from the other two players' spending. Because the chain is 2-hop maximum, in a 3-ring:
- When B spends: A gets upline1 share, C (if A's upline) gets upline2 share
- When C spends: B gets upline1 share, A gets upline2 share
- When A spends: C gets upline1 share, B gets upline2 share

Total recirculation within the ring = upline1 + upline2 = 24% of scaledAmount = 6% of amount (fresh ETH level 1-3).

**Net EV of ring vs. solo:**
- Solo play with VAULT referral: 0% recirculated to participants (goes to VAULT)
- Ring play: 6% of spend recirculated among ring members

The ring is strictly positive compared to solo play — participants collectively retain 6% of their spend that would otherwise go to VAULT. However:

1. This is **not an extraction vector** — participants still net-spend ETH (receive tickets at their EV, plus 6% of spend back to ring). No ETH is created from nothing.
2. The 6% rakeback flow is a designed feature (referral rewards exist to incentivize code promotion). A circular ring is just a pathological use of an intended mechanism — equivalent to friends referring each other.
3. The VAULT's referral earnings are reduced, not the prize pool. Prize pool ETH is separately tracked and unaffected.
4. Severity: **INFO** — Intended mechanics used for maximum personal benefit. No protocol insolvency risk, no double-spend, no prize pool drainage.

### Wash Trading Analysis

An actor controls wallets A and B. A creates an affiliate code; B registers under A's code. B spends `amount`:
- A receives 25% of `scaledAmount` (if rakeback=0, levels 1-3)
- Actor net: spent `amount`, received `0.25 * 0.25 * amount = 6.25% of amount` back

This is a 6.25% effective discount. No amplification exists — the rakeback is strictly bounded by the BPS constants (`REWARD_SCALE_FRESH_L1_3_BPS = 2500`, i.e., 25%). Maximum discount = 25% × 25% (max rakeback) = 6.25%. No recursive multiplication.

**TOKEN-07 VERDICT: PASS** — No affiliate path produces positive net ETH extraction (net ETH out > net ETH in from non-prize-pool sources). Ring and wash discount are bounded, designed-for mechanics. Circular ring arbitrage rated INFO.

---

## TOKEN-08 VERDICT: PASS

**DGNRS lockForLevel/unlock Level-Transition Timing — No double-cap exploit**

### Same-Level Unlock Guard

**`unlock()` — DegenerusStonk.sol line 469:**
```solidity
if (lockedLevel[msg.sender] == currentLevel) revert LockStillActive();
```
A player who locked at level N cannot call `unlock()` while still at level N. This definitively blocks the same-level double-spend pattern:
- Lock at level N → spend cap → call unlock() → revert LockStillActive ✓
- Lock at level N → spend cap → call lockForLevel() at level N again → does NOT trigger auto-unlock (condition: `currentLockedLevel != currentLevel` is false) → tokens are additive, spend counter is NOT reset ✓

### Auto-Unlock Branch in lockForLevel() — Lines 442–448

```solidity
if (currentLocked > 0 && currentLockedLevel != currentLevel) {
    emit Unlocked(msg.sender, currentLocked);
    currentLocked = 0;
    ethSpentThisLevel[msg.sender] = 0;
    burnieSpentThisLevel[msg.sender] = 0;
}
```

This branch triggers ONLY when `currentLockedLevel != currentLevel` — i.e., only at a genuine level transition. It:
1. Resets `currentLocked` (local variable) to 0
2. Clears `ethSpentThisLevel[msg.sender]` and `burnieSpentThisLevel[msg.sender]`
3. Continues to set `lockedBalance[msg.sender] = newLocked` and `lockedLevel[msg.sender] = currentLevel`

**Critical: `lockedBalance[msg.sender]` is NOT cleared in the auto-unlock branch** — only the local `currentLocked` variable is set to 0. The storage write at line 454 (`lockedBalance[msg.sender] = newLocked`) overwrites with `0 + amount = amount`. This is correct behavior: the old lock is conceptually released and a new lock of `amount` is opened at the new level.

### Level-Transition Timing Window Resolution

**The RESEARCH.md open question:** Can a player call `lockForLevel()` immediately after a level transition (same block) to get both the level-N partial cap already spent AND a fresh level-N+1 cap?

**Answer: This is correct, intended behavior — not an exploit.**

Sequence:
1. Player locks at level N, spends some cap
2. Game transitions to level N+1 (via `advanceGame()`)
3. Player calls `lockForLevel(amount)`:
   - `currentLevel = game.level()` = N+1
   - `currentLockedLevel = lockedLevel[player]` = N
   - Condition `currentLocked > 0 && N != N+1` is **true** → auto-unlock fires
   - `ethSpentThisLevel` and `burnieSpentThisLevel` are cleared
   - New lock is set at level N+1 with fresh cap

This gives the player: level-N partial spend (already done, irreversible) + fresh level-N+1 cap. This is exactly the same outcome as:
- Calling `unlock()` explicitly after level N
- Calling `lockForLevel()` at level N+1

The same-block compression does NOT provide any additional benefit. The level-N cap was bounded by level-N lock. The level-N+1 cap is computed from `_lockedClaimableValues(locked)` at the time of level N+1 — a fresh calculation based on current contract state.

### _lockedClaimableValues() — No Bypass Path

**`_lockedClaimableValues()` — DegenerusStonk.sol lines 950–966:**
```solidity
function _lockedClaimableValues(
    uint256 locked
) private view returns (uint256 ethValue, uint256 burnieValue) {
    uint256 supply = totalSupply;
    if (supply == 0 || locked == 0) return (0, 0);
    uint256 ethBal = address(this).balance;
    uint256 stethBal = steth.balanceOf(address(this));
    uint256 claimableEth = _claimableWinnings();
    ...
    ethValue = (totalMoney * locked) / supply;
    ...
}
```

This is a **pure computation** — it does not credit, transfer, or alter any state. The cap computation is: `10 × (locked / totalSupply) × (ETH + stETH + claimableWinnings of DGNRS contract)`.

The auto-unlock in `lockForLevel()` clears `ethSpentThisLevel` but does NOT call `_lockedClaimableValues()` or credit any claimable values to the player. There is no path where calling `lockForLevel()` at a level boundary simultaneously:
- Claims level-N claimable value (these are never "claimed" by lockForLevel — they remain in the DGNRS contract's claimable pool)
- Opens a fresh level-N+1 cap

The claimable ETH (`_claimableWinnings()`) refers to the DGNRS *contract's* claimable winnings from the game, not any individual player's winnings.

### Same-Block Double-Cap Attempt

Formally: Can a player spend level-N cap AND level-N+1 cap in the same block?

- To spend level-N+1 cap, player must call `lockForLevel()` at level N+1 → sets `lockedLevel[player] = N+1`
- Then call `gamePurchase()` → `_checkAndRecordEthSpend()` requires `lockedLevel[player] == currentLevel` (N+1) ✓
- Level-N spending was already done before the transition — cap was bounded by level-N lock amount

No double-cap extraction exists. The transition is atomic and sequential. Executing it in one block vs. multiple blocks changes nothing about the total cap available.

**TOKEN-08 VERDICT: PASS** — Same-level unlock correctly blocked by `LockStillActive` revert. Auto-unlock in `lockForLevel()` at level transition resets spend counters atomically without crediting any claimable values. Level-transition timing window is clean: same-block `lockForLevel()` is functionally identical to separate-block unlock + re-lock. No double-cap exploit path exists.

---

## Task Commits

Each task was committed atomically:

1. **Task 1: TOKEN-07 affiliate analysis** — analysis embedded in SUMMARY.md
2. **Task 2: TOKEN-08 lockForLevel/unlock analysis** — analysis embedded in SUMMARY.md

**Plan metadata:** (docs commit — see final commit)

## Files Created/Modified
- `.planning/phases/11-token-security-economic-attacks-vault-and-timing/11-03-SUMMARY.md` — TOKEN-07 and TOKEN-08 verdicts with line-level evidence

## Decisions Made
- TOKEN-07: REF_CODE_LOCKED sentinel is `bytes32(1)` not VAULT address — plan comment was imprecise; code is correct
- TOKEN-07: Circular 3-ring is achievable (not blocked) but non-extractive; rated INFO
- TOKEN-08: Auto-unlock in lockForLevel() does NOT credit claimable values; _lockedClaimableValues is view-only; PASS verdict confirmed
- TOKEN-08: Level-transition timing window resolved as intended mechanics — same-block sequence identical to multi-block sequence

## Deviations from Plan

None — plan executed exactly as written. Both verdicts delivered with contract/line evidence and C4 severity assignments.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- TOKEN-07 and TOKEN-08 verdicts are PASS — no new findings for Phase 13 report from this plan
- Circular ring INFO finding documented for completeness
- Phase 11 plans 01 and 02 verdicts (TOKEN-01 through TOKEN-06) needed for full Phase 11 picture

---
*Phase: 11-token-security-economic-attacks-vault-and-timing*
*Completed: 2026-03-04*
