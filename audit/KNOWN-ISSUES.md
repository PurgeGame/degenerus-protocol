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

### GO-05-F01: _sendToVault Hard Reverts Can Block Terminal Distribution (Medium)

**Severity:** MEDIUM
**Contract:** `DegenerusGameGameOverModule`
**Source:** Phase 26-02

`_sendToVault` (GameOverModule:195-231) uses hard `revert E()` on any ETH or stETH transfer failure. 7 dangerous revert sites (lines 201, 205, 210-211, 218, 219, 228-229). If the vault or sDGNRS contract cannot receive funds (e.g., Lido stETH pause), both `handleGameOverDrain` and `handleFinalSweep` revert permanently, stranding all terminal distribution.

**Why Medium (not Critical):** Vault and sDGNRS are immutable protocol-owned contracts with simple, unconditional `receive()` functions. sDGNRS's `receive()` has an `onlyGame` modifier permanently satisfied. Lido stETH has never paused transfers. The risk is operational (infrastructure failure), not exploitable by external attackers.

**Recommended fix:** Consider wrapping `_sendToVault` in try/catch or using a pull-based pattern for vault sweep. Alternatively, accept as known risk given immutable recipients.

---

## Phase 27 Payout/Claim Path Audit: No New Known Issues

All 19 normal-gameplay payout requirements (PAY-01 through PAY-19) received PASS verdicts with no findings above INFORMATIONAL severity. No new entries required in the Known Finding section.

---

## Intentional Design (Not Bugs)

**BURNIE has multiple mint pathways.** `mintForCoinflip()`, `mintForGame()`, and the vault's 2M virtual reserve. All authorized via `onlyTrustedContracts`. No free-mint path.

**Degenerette is +EV at high activity.** 305% activity score yields ~99.9% ROI. Intentional — bounded by bet limits, 10% pool cap on ETH payouts, and lootbox delivery (future tickets, not liquid value).

**Activity score gap compounds.** 80% lootbox EV (minimum) to 135% (maximum). Intentional incentive for consistent participation.

**stETH rounding strengthens invariant.** 1-2 wei per transfer retained by contract, pushing `balance >= claimablePool` further into safety. Not a leak.

**Deity pass pricing favors early buyers.** Cost is `24 + T(n)` ETH where `T(n) = n(n+1)/2`. GAMEOVER refund (20 ETH/pass, levels 0-9 only, FIFO) partially mitigates but doesn't eliminate early-mover advantage.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

**`previewBurn` and `burn` may differ slightly.** When `claimableEth > 0`, the ETH/stETH split can shift between preview and execution. By design -- claimable ETH remains as reserves for future burners.

**Level aliasing at level 0 targets level 2 for terminal jackpot.** GameOverModule:72 aliases `lvl = 1` when `currentLevel == 0`, causing `runTerminalJackpot(remaining, lvl + 1, rngWord)` to target level 2. At level 0 no tickets exist for level 1, so level 2 (pre-sale/early-bird tickets) is the correct target. BY DESIGN per economics specification.

**30-day claim window forfeiture applies to all claimable winnings.** After GAMEOVER + 30 days, `handleFinalSweep` sets `claimablePool = 0` and sweeps all remaining balance to vault/sDGNRS. Deity refunds, terminal decimator claims, and terminal jackpot credits are all subject to this window. Unclaimed funds are permanently forfeited. BY DESIGN.

**Stale test comments (912d vs 365d).** `test/edge/GameOver.test.js` references 912-day timeout but code uses 365 days at level 0 and 120 days at level 1+. Tests pass by overshooting. INFORMATIONAL -- defer to Phase 29.

**Decimator claim expiry is by-design.** `lastDecClaimRound` overwrites on each resolution, permanently expiring prior unclaimed decimator rewards. Documented in v1.1-transition-jackpots.md Section 8. Players who do not claim before the next decimator resolution lose their entitlement. BY DESIGN.

**Coinflip claim window asymmetry (30d first-time vs 90d returning) is by-design.** First-time claimants who deposit and wait 31+ days without claiming lose their winnings. Returning claimants (who have previously claimed) get 90 days. Documented in v1.1-burnie-coinflip.md Section 7. Absent from contract natspec. BY DESIGN.

**Whale pass claims have no expiry.** `whalePassClaims[player]` accumulates indefinitely until `claimWhalePass()` is called (EndgameModule:515-534). Unlike decimator claims, whale pass entitlements persist across level transitions. Only GAMEOVER disables claiming (`if (gameOver) revert`). BY DESIGN.

**Affiliate DGNRS uses fixed allocation, not sequential depletion.** The v1.1 affiliate doc describes sequential pool depletion, but the code uses `levelDgnrsAllocation[currLevel]` (snapshot at level transition) with `totalAffiliateScore[currLevel]` as proportional denominator. This eliminates first-mover advantage. The natspec confirms: "eliminating first-mover advantage." Code is authoritative; v1.1 doc is stale on this point. BY DESIGN.

---

## External Dependencies

**Chainlink VRF V2.5** — sole randomness source. Soft dependency: game stalls but no funds lost if VRF goes down. governance-based coordinator rotation (M-02, downgraded to Low) and 365-day inactivity timeout provide independent recovery paths.

**Lido stETH** — prize pool growth depends on ~2.5% APR yield. If yield goes to zero, positive-sum margin disappears.
