# Unit 8: Degenerette Betting -- Final Findings

## Audit Scope
- **Contract:** DegenerusGameDegeneretteModule.sol (1,179 lines)
- **Inherits:** DegenerusGamePayoutUtils -> DegenerusGameMintStreakUtils (62 lines) -> DegenerusGameStorage (1,613 lines)
- **Audit type:** Three-agent adversarial (Taskmaster + Mad Genius + Skeptic)
- **Coverage verdict:** PASS (27/27 functions, 100%)
- **Functions analyzed:**
  - External state-changing (B): 2 (full analysis per D-02)
  - Internal helpers (C): 10 (via caller call trees; standalone for [MULTI-PARENT] per D-03)
  - View/Pure (D): 15 (computation correctness, overflow checks, bit layout verification)
- **Inherited helpers traced:** 9 (from DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils, DegenerusGameStorage)

## Findings Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 1 |
| INFO | 1 |
| **Total** | **2** |

## Confirmed Findings

### [LOW] F-01: ETH Claimable Pull Uses Strict Inequality Preventing Exact Balance Usage

**Location:** `DegenerusGameDegeneretteModule.sol` line 552
**Found by:** Mad Genius (Attack Report, B1 section)
**Confirmed by:** Skeptic (Review, confirmed LOW)
**Severity:** LOW -- workaround exists, no funds at risk

**Description:**
The claimable pull check at L552 uses `<=` (less-than-or-equal) instead of `<` (strictly-less-than):

```solidity
if (claimableWinnings[player] <= fromClaimable) revert InvalidBet();
```

This means a player cannot use their EXACT full claimable balance to fund a Degenerette bet. If `claimableWinnings[player] == fromClaimable`, the condition evaluates to TRUE and the bet reverts. The player must either:
1. Send at least 1 wei as msg.value (reducing fromClaimable by 1, so claimable > fromClaimable)
2. Place a slightly smaller bet

**Impact:**
- Minor UX friction for players wanting to use their exact claimable balance
- No funds at risk, no state corruption, no exploitable vector
- Does not affect players who send full msg.value with their bets

**Root Cause:**
Likely intentional to prevent a player from having exactly 0 claimable after deduction, but the motivation is unclear since `claimableWinnings[player] = 0` is a valid and common state (e.g., new players who have never won).

**Recommendation:**
Consider changing `<=` to `<` at L552 to allow exact-balance usage. Alternatively, document this as intentional behavior.

**Evidence:**
- Mad Genius: ATTACK-REPORT.md, B1 section, Finding F-01
- Skeptic: SKEPTIC-REVIEW.md, F-01 section (confirmed with trace)

---

### [INFO] F-03: ETH Bet Resolution Transiently Blocked During Prize Pool Freeze

**Location:** `DegenerusGameDegeneretteModule.sol` line 685
**Found by:** Mad Genius (Attack Report, B2 section)
**Confirmed by:** Skeptic (Review, confirmed INFO)
**Severity:** INFO -- by design, no practical impact

**Description:**
The `_distributePayout` function reverts for ETH payouts when `prizePoolFrozen` is true:

```solidity
if (prizePoolFrozen) revert E();
```

This flag is set during `advanceGame` execution in the AdvanceModule while jackpot math is in progress. During this brief window, ETH Degenerette bet resolutions will revert. BURNIE and WWXRP resolutions are unaffected since they don't interact with prize pools.

**Impact:**
- The freeze exists only within a single `advanceGame` transaction
- External callers never observe a frozen state between transactions
- No exploitable DoS vector -- the freeze is transient and bounded
- BURNIE and WWXRP bet resolution is completely unaffected

**Root Cause:**
By design. The freeze prevents payout distributions from corrupting the prize pool snapshot that advanceGame's jackpot math operates on.

**Recommendation:**
No action needed. This is correct defensive behavior.

**Evidence:**
- Mad Genius: ATTACK-REPORT.md, B2 section, Finding F-03
- Skeptic: SKEPTIC-REVIEW.md, F-03 section (confirmed as within-transaction only)

---

## Dismissed Findings (False Positives)

| ID | Title | Mad Genius Verdict | Skeptic Verdict | Reason |
|----|-------|--------------------|-----------------|--------|
| F-02 | WWXRP bets do not track pending amounts | SAFE | -- | By design: WWXRP is burn/mint, no pool solvency tracking needed |
| F-04 | Unchecked pool subtraction across multi-spin | SAFE | -- | Fresh reads per spin + 10% cap guarantee no underflow (0.9^10 = 0.349) |
| F-05 | uint128 cast truncation on totalBet pool addition | INVESTIGATE (INFO) | FALSE POSITIVE | Requires amountPerTicket > 3.4e37 (~3.4e19 ETH per ticket). Total ETH supply is ~120M. Economically impossible precondition |
| F-06 | Delegatecall to LootboxModule state coherence | SAFE | -- | Verified: LootboxModule.resolveLootboxDirect does not write to prizePoolsPacked, claimablePool, or claimableWinnings |

---

## Cache-Overwrite (BAF Pattern) Verification

### Context
The BAF cache-overwrite bug pattern (ancestor caches storage variable, descendant writes to same variable, ancestor writes stale cache back) was the highest-priority concern for this audit. DegenerusGameDegeneretteModule has specific risks due to:
1. Multi-spin resolution loop where _distributePayout is called per-win, modifying futurePrizePool each time
2. Delegatecall to LootboxModule which executes in Game's storage context
3. ETH collection from claimable balance during bet placement

### Verification Results

| Function | Cache Concern | Mad Genius Verdict | Skeptic Verification | Final |
|----------|-------------|-------------------|--------------------|-------|
| placeFullTicketBets (B1) | activityScore computed before fund collection writes | SAFE: activityScore is view-only computation, no descendant writes to inputs | Not challenged: view-only computation confirmed | SAFE |
| placeFullTicketBets (B1) | nonce read before bet storage write | SAFE: nonce incremented then written. Stale local is pre-increment, used as key (correct) | Not challenged | SAFE |
| placeFullTicketBets (B1) | prizePoolsPacked read/write in _collectBetFunds | SAFE: fresh read at L562 immediately before write at L563. No intervening call | Not challenged | SAFE |
| resolveBets (B2) | futurePrizePool read per spin in _distributePayout | SAFE: fresh SLOAD via _getFuturePrizePool() at L687 each call. Previous spin's write committed at L703 | Interrogation Q1: confirmed fresh reads, 10% cap prevents depletion | SAFE |
| resolveBets (B2) | LootboxModule delegatecall after pool write | SAFE: pool committed at L703, claimable at L704, BEFORE delegatecall at L708. LootboxModule does not touch these variables | Interrogation Q2: direct code reading of LootboxModule confirmed | SAFE |

**Overall BAF Verdict: NO cache-overwrite vulnerabilities found in DegenerusGameDegeneretteModule.**

---

## Additional Verification

### RNG Commitment Window
- Bets placed BEFORE RNG word exists (L475 enforces `lootboxRngWordByIndex[index] == 0`)
- All bet parameters (ticket, amount, activity score, hero quadrant) locked at placement time
- Resolution uses stored parameters from packed bet, NOT recomputed values
- No player-controllable state changes between VRF request and fulfillment that affect outcome
- **Verdict: RNG commitment integrity is sound**

### Multi-Currency Payout Path Correctness
- **ETH:** 25% as claimable ETH (capped at 10% of futurePrizePool) + 75% as lootbox (via delegatecall). Pool deduction is only for ETH portion.
- **BURNIE:** Full payout minted via coin.mintForGame. No pool interaction.
- **WWXRP:** Full payout minted via wwxrp.mintPrize. No pool interaction.
- All three paths are independent and correctly isolated.

### Payout Math Overflow Safety
- Maximum multiplication chain: uint128 * 10_000_000 * 11_000 * 4225^4 * 23_500 / (1_000_000 * den * 10_000) -- all intermediate values verified to fit uint256
- EV normalization ratio: num max 4225^4 = 3.18e14, den min 100^4 = 1e8. Ratio max ~31,817x. SAFE.
- ROI curve continuity verified at all 3 breakpoints (7500, 25500, 30500 score).
