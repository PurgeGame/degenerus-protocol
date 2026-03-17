# Known Issues and Design Notes

Pre-disclosure for C4A wardens. If you find something listed here, it's already known.

---

## Known Finding

### M-02: VRF Coordinator Swap Security (Downgraded to Low)

**Original Severity:** MEDIUM (v1.0-v2.0)
**Revised Severity:** LOW (v2.1)
**Contract:** `DegenerusAdmin`

In v2.1, the original single-admin VRF coordinator swap was replaced by a community governance mechanism (propose/vote/execute). The admin (>50.1% DGVE holder) can propose a coordinator swap after 20 hours of VRF stall, but execution requires sDGNRS-weighted community approval with time-decaying threshold. A single reject voter can block any proposal.

**Why downgraded:**
1. Three prerequisites (was two): VRF stall + admin key compromised + community absent for 7 days
2. 7-day defense window for community response (was immediate after 3-day stall)
3. Soulbound sDGNRS prevents vote weight acquisition via market purchase
4. Single reject voter blocks malicious proposals

**Residual governance risks (see WAR-01 and WAR-02 below).**

### WAR-01: Compromised Admin Key + Community Absence (Medium)

**Severity:** MEDIUM
**Contract:** `DegenerusAdmin`
**Source:** Phase 24-07

A compromised admin can propose a malicious VRF coordinator. If the sDGNRS community does not vote to reject within 7 days (full proposal lifetime), the proposal executes via threshold decay (5% at day 6). The DGVE/sDGNRS separation is the primary defense -- admin holds DGVE but cannot acquire sDGNRS voting weight (soulbound).

**Preconditions:** VRF stalled 20+ hours + admin key compromised + community absent for 168 hours.

### WAR-02: Colluding Voter Cartel at Low Threshold (Medium)

**Severity:** MEDIUM
**Contract:** `DegenerusAdmin`
**Source:** Phase 24-07

At day 6 of a proposal's lifetime, threshold decays to 5% (500 BPS). A cartel holding >= 5% of circulating sDGNRS can approve a malicious coordinator swap if no reject voter appears. A single reject voter with sufficient weight blocks.

**Preconditions:** VRF stalled 20+ hours + proposal alive 144+ hours + cartel >= 5% circulating sDGNRS + no reject voter.

### GOV-07: _executeSwap CEI Violation (Low)

**Severity:** LOW
**Contract:** `DegenerusAdmin`
**Source:** Phase 24-04

Theoretical reentrancy via malicious VRF coordinator during `_executeSwap` -- external call to `gameAdmin.updateVrfCoordinatorAndSub()` occurs before `_voidAllActive()` completes. Requires pre-existing governance control to exploit (attacker already controls the coordinator being swapped to). Recommended fix: move `_voidAllActive` before external calls.

### VOTE-03: uint8 activeProposalCount Overflow (Low)

**Severity:** LOW
**Contract:** `DegenerusAdmin`
**Source:** Phase 24-05

`activeProposalCount` (uint8, unchecked increment) wraps to 0 at 256 proposals, causing `anyProposalActive()` to return false and unpausing the death clock. Cost ~$3,000 (256 proposals). Recommended fix: `require(activeProposalCount < 255)`.

### WAR-06: Admin Spam-Propose Gas Griefing (Low)

**Severity:** LOW
**Contract:** `DegenerusAdmin`
**Source:** Phase 24-07

No per-proposer cooldown. Admin can create many proposals, bloating `_voidAllActive` loop gas cost. Recommended fix: per-proposer cooldown or max active proposals.

---

## Intentional Design (Not Bugs)

**BURNIE has multiple mint pathways.** `mintForCoinflip()`, `mintForGame()`, and the vault's 2M virtual reserve. All authorized via `onlyTrustedContracts`. No free-mint path.

**Degenerette is +EV at high activity.** 305% activity score yields ~99.9% ROI. Intentional — bounded by bet limits, 10% pool cap on ETH payouts, and lootbox delivery (future tickets, not liquid value).

**Activity score gap compounds.** 80% lootbox EV (minimum) to 135% (maximum). Intentional incentive for consistent participation.

**stETH rounding strengthens invariant.** 1-2 wei per transfer retained by contract, pushing `balance >= claimablePool` further into safety. Not a leak.

**Deity pass pricing favors early buyers.** Cost is `24 + T(n)` ETH where `T(n) = n(n+1)/2`. GAMEOVER refund (20 ETH/pass, levels 0-9 only, FIFO) partially mitigates but doesn't eliminate early-mover advantage.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

**`previewBurn` and `burn` may differ slightly.** When `claimableEth > 0`, the ETH/stETH split can shift between preview and execution. By design — claimable ETH remains as reserves for future burners.

---

## External Dependencies

**Chainlink VRF V2.5** — sole randomness source. Soft dependency: game stalls but no funds lost if VRF goes down. governance-based coordinator rotation (M-02, downgraded to Low) and 365-day inactivity timeout provide independent recovery paths.

**Lido stETH** — prize pool growth depends on ~2.5% APR yield. If yield goes to zero, positive-sum margin disappears.
