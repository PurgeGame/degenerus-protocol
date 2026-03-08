# Known Issues and Design Notes

Pre-disclosure for external auditors. All findings from the internal AI-assisted audit
(7 phases, 4 adversarial sessions) have been addressed. This document covers the
remaining open items and intentional design decisions that may appear unusual.

---

## Open Findings

### M-02: Admin + VRF Failure Scenarios

**Severity:** Medium
**Contract:** `DegenerusGame` / `DegenerusAdmin`
**Requirement:** FSM-02 (stuck state recovery)
**Status:** Acknowledged design trade-off

When Chainlink VRF fails for 3+ consecutive days, the admin (any address holding >50.1%
DGVE) gains the ability to call `emergencyRecover`, which migrates the game to a new VRF
coordinator. This creates two distinct failure scenarios:

**Scenario A — Admin absent + VRF failure (availability):**
If the admin key is lost, DGVE is fragmented below the >50.1% threshold with no
coordination path, or remaining holders cannot consolidate to a single address, then
`emergencyRecover` cannot be called. The only recovery is the 365-day inactivity timeout.
Winnings remain claimable throughout; no fund loss risk.

**Scenario B — Hostile admin + VRF failure (integrity):**
A compromised admin can use `emergencyRecover` to point the game at an attacker-controlled
VRF coordinator contract. This coordinator can return chosen random words, giving the
attacker control over jackpot winners, lootbox outcomes, and all other RNG-dependent
mechanics. This is the more severe scenario — it is an integrity violation, not just an
availability issue.

**Clarification on LINK subscription exhaustion:** This is NOT a contributing factor.
Anyone can donate LINK to the VRF subscription via `LINK.transferAndCall(adminAddr,
amount, "0x")` and the protocol incentivizes this with above-par BURNIE rewards when the
subscription balance is low.

**Both scenarios require:**
1. Chainlink VRF stalled for 3+ consecutive days — Chainlink itself must be down, not
   just that nobody called `advanceGame`. The function is permissionless; anyone with
   pending jackpot winnings has direct economic incentive to call it.
2. Plus either: admin key lost / DGVE fragmented (Scenario A), or admin key compromised
   (Scenario B)

**Mitigating factors:**
- The 3-day VRF stall requirement means a hostile admin cannot act opportunistically —
  Chainlink must genuinely be down for 3 days first
- All `emergencyRecover` calls emit `EmergencyRecovered` events on-chain, making
  coordinator swaps publicly detectable
- The admin is neutered during normal VRF operation — no admin function can influence RNG
  outcomes while Chainlink is operational

**Incentive note:** The game is designed for infinite play — a rational admin with >50.1%
DGVE is economically better off letting the game run as designed. However, a >50.1% DGVE holder with sufficiently high time preference may value a
one-time RNG extraction over the ongoing value of their governance position.

**GAMEOVER RNG fallback (dead VRF, no admin):** When GAMEOVER triggers with a dead VRF
coordinator and no admin to call `emergencyRecover`, the game needs entropy to finalize
the drain. After a 3-day wait, `_getHistoricalRngFallback` combines up to 5 early
historical VRF words (committed on-chain, non-manipulable) with `currentDay` and
`block.prevrandao`. This provides unpredictability to non-validators at the cost of 1-bit
validator influence (propose or skip their slot). This is the strongest fallback available
without an external oracle — the context is disaster recovery, so the trade-off is
acceptable given the alternative of permanent fund lock.

---

### Historical RNG Fallback With Zero VRF History

**Severity:** Informational (unrealistic precondition)
**Contract:** `DegenerusGameAdvanceModule` (`_getHistoricalRngFallback`)
**Status:** Resolved — revert removed, falls through to prevrandao-only entropy

Previously reverted when no historical VRF words existed. Now falls through to
`keccak256(0, currentDay, block.prevrandao)` — prevrandao-only entropy. This can only trigger
at level 0 (zero VRF history = zero completed advances = zero level progression), where the
1-bit validator manipulation on prevrandao is irrelevant to game outcomes.

---

## Design Decisions That May Look Like Bugs

### BURNIE has multiple mint pathways

BURNIE is created via `mintForCoinflip()` (coinflip wins) and `mintForGame()` (Degenerette
wins, other game payouts). The vault also has a 2M BURNIE virtual reserve that mints on
withdrawal. These are all authorized pathways — there is no "free mint" path.

### Degenerette is +EV at high activity score

High-activity players (305% score) achieve ~99.9% ROI on Degenerette with additional ETH
bonus redistribution. This is the primary intended +EV path for engaged players. Extraction
is bounded by bet size limits, the 10% pool cap on ETH payouts, and the fact that
Degenerette EV is delivered largely through lootboxes — which pay out as future tickets
that require continued play to realize their value.

### Activity score gap compounds over time

The ROI spread between minimum activity (80% lootbox EV) and maximum activity (135%
lootbox EV) creates a compounding advantage for engaged players. This is the intended
incentive structure — the protocol rewards consistent participation.

### stETH rounding strengthens invariant

stETH transfer rounding (1-2 wei per transfer) is retained by the contract, strengthening
the `balance >= claimablePool` invariant rather than weakening it.

---

## Protocol-Level Design Trade-offs

### Dependency on external rational actors

The protocol's resilience assumes at least one rational actor monitors on-chain prize
pools and acts on profitable opportunities. If all participants simultaneously become
inactive, the 365-day (912-day at level 0) timeout triggers GAMEOVER. This is a terminal
condition with well-defined but irreversible settlement.

### Chainlink VRF dependency (soft)

The protocol depends on Chainlink VRF V2.5 for randomness. This is a soft dependency —
if Chainlink goes down, the game stalls but no funds are lost. The 3-day emergency
fallback (M-02) and 365-day inactivity timeout provide two independent recovery paths.
LINK subscription top-up is permissionless, so subscription exhaustion is not a failure
mode.

### Lido stETH yield dependency

Prize pool growth depends on stETH yield (~2.5% APR). If Lido staking yield permanently
goes to zero, the positive-sum margin disappears. This would affect any stETH-dependent
protocol equally.

### Deity pass quadratic pricing favors early buyers

Deity passes cost 24 + T(n) ETH where T(n) = n(n+1)/2. Early buyers pay substantially
less than late buyers. The 20 ETH/pass GAMEOVER refund (levels 0-9 only, budget-capped,
FIFO priority) partially mitigates this but does not eliminate the early-mover advantage.

### Admin is neutered by design

The admin (>50% DGVE holder) has almost no power during normal operation. The only
meaningful admin capability is the 3-day VRF emergency fallback: if Chainlink VRF fails
for 3 consecutive days, the admin can call `emergencyRecover` to set a new VRF coordinator.

This is an intentional trade-off:
- **Upside:** No admin can rug, manipulate game outcomes, or extract funds during normal play.
- **Downside:** If a severe contract bug is discovered post-deploy, the admin cannot patch
  or pause — the contracts are effectively immutable. The 3-day fallback also means the
  admin could theoretically influence one RNG resolution if Chainlink goes down, which is
  a reasonable amount of trust given the alternative (game dies permanently from no RNG).

---

## Adversarial Session Results (All Clean)

| Session | Attack Vector | Result |
|---------|--------------|--------|
| ADVR-01 | ETH Extraction | No Medium+ findings |
| ADVR-02 | Brick advanceGame | No Medium+ findings |
| ADVR-03 | claimWinnings Overflow | No Medium+ findings |
| ADVR-04 | Delegatecall Reentrancy | No Medium+ findings |
