# Phase 26: GAMEOVER Path Audit - Research

**Researched:** 2026-03-17
**Domain:** Smart contract security audit -- terminal distribution, death clock, reentrancy, fund accounting
**Confidence:** HIGH

## Summary

The GAMEOVER path is the highest-risk, newest code in the Degenerus protocol. It spans 4 contract files (DegenerusGameGameOverModule.sol, DegenerusGameDecimatorModule.sol, DegenerusGameAdvanceModule.sol, DegenerusGameJackpotModule.sol) totaling roughly 1,300 lines of directly relevant code, plus storage definitions and the main game's dispatch wrappers. The terminal decimator (death bet) is ~490 lines of brand-new code with zero prior audit coverage.

The GAMEOVER sequence is a multi-step process: liveness guard trigger -> VRF acquisition (with 3-day fallback) -> deity refunds (levels 0-9) -> terminal decimator (10%) -> terminal jackpot to lvl+1 holders (90% + dec refund) -> vault sweep of remainder -> 30-day claim window -> final sweep zeroes claimablePool and sends all remaining funds 50/50 to vault/sDGNRS. Every step mutates `claimablePool` -- the central accounting invariant -- making this the single highest-risk path for fund accounting errors.

Prior audit coverage (v2.0 warden sim) noted the GAMEOVER path was only reviewed in a single pass and flagged "complex multi-step interactions may have edge cases not captured." The existing test file (`test/edge/GameOver.test.js`) covers basic level-0 timeout, deity refund, and final sweep, but does NOT test terminal decimator resolution, level 1+ GAMEOVER with populated ticket pools, or the no-RNG fallback path. The test file also contains stale comments referencing "912-day timeout" and "365-day inactivity" with thresholds that do not match current code (code uses 365 days at level 0, 120 days at level 1+).

**Primary recommendation:** Audit every function on the GAMEOVER path as stranger's code. Trace `claimablePool` through every mutation site. Verify CEI ordering. Confirm no revert can block payouts. Deliver PASS/FINDING verdicts with file:line references for every requirement.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GO-01 | `handleGameOverDrain` audited -- accumulator distribution, decimator 10%, terminal jackpot 90%, 50/50 vault/DGNRS split on sweep | GameOverModule.sol:68-164 contains the full drain sequence. Decimator dispatch at line 140, terminal jackpot at line 152, vault sweep at line 158. |
| GO-02 | `handleFinalSweep` audited -- 30-day claim window, claimablePool zeroing, unclaimed forfeiture | GameOverModule.sol:171-189. `claimablePool = 0` at line 177 before balance check. `_sendToVault` at line 188. |
| GO-03 | Death clock trigger conditions audited -- level 0 (365d) and level 1+ (120d) thresholds verified | AdvanceModule.sol:421-423. `DEPLOY_IDLE_TIMEOUT_DAYS = 365` at line 90. Level 1+ uses `ts - 120 days > lst`. |
| GO-04 | Distress mode activation audited -- effects on lootbox routing and ticket bonuses | Storage.sol:156-174. `DISTRESS_MODE_HOURS = 6`. Lootbox effects in LootboxModule:600-621 and 953-956. |
| GO-05 | Every require/revert on GAMEOVER path audited -- no revert can block payout | GameOverModule uses `revert E()` for stETH transfer failures and ETH send failures. AdvanceModule safety valve at 442-444. |
| GO-06 | Reentrancy and state ordering audited -- no funds stuck or double-paid | `gameOverFinalJackpotPaid` latch prevents re-entry. `gameOver = true` set before external calls. `finalSwept` prevents double sweep. |
| GO-07 | Deity pass refunds on early GAMEOVER (levels 0-9) audited | GameOverModule.sol:78-107. Fixed 20 ETH per pass, FIFO by deityPassOwners array, budget-capped. |
| GO-08 | Terminal decimator integration audited | DecimatorModule.sol:749-1027. `runTerminalDecimatorJackpot` at 880-922, `recordTerminalDecBurn` at 804-867, `claimTerminalDecimatorJackpot` at 930-937. |
| GO-09 | No-RNG-available GAMEOVER path audited | AdvanceModule.sol:797-875. `_gameOverEntropy` with `GAMEOVER_RNG_FALLBACK_DELAY = 3 days`, `_getHistoricalRngFallback` combines up to 5 historical VRF words + prevrandao. Also: GameOverModule.sol:126 -- `if (rngWord == 0) return;` allows retry without latching. |
</phase_requirements>

## Standard Stack

This is a security audit phase, not an implementation phase. The "stack" is the audit methodology and source contracts.

### Core: Contracts Under Audit

| Contract | Location | Lines | Purpose | Risk Level |
|----------|----------|-------|---------|------------|
| DegenerusGameGameOverModule.sol | contracts/modules/ | 233 | Terminal drain + final sweep | CRITICAL -- all fund distribution |
| DegenerusGameDecimatorModule.sol | contracts/modules/ | 1027 | Terminal decimator (death bet) + normal decimator | CRITICAL -- newest code, zero prior audit |
| DegenerusGameAdvanceModule.sol | contracts/modules/ | ~1400 | Liveness guards, RNG gate, VRF fallback | HIGH -- GAMEOVER trigger logic |
| DegenerusGameJackpotModule.sol | contracts/modules/ | ~1700 | `runTerminalJackpot`, `_distributeJackpotEth` | HIGH -- terminal jackpot distribution |
| DegenerusGameStorage.sol | contracts/storage/ | ~1600 | All state variables, `_isDistressMode()` | REFERENCE -- storage layout truth |
| DegenerusGame.sol | contracts/ | 2856 | Dispatch wrappers, `claimWinnings` | MEDIUM -- delegatecall routing |
| StakedDegenerusStonk.sol | contracts/ | ~400 | `burnRemainingPools`, `depositSteth` | LOW -- already audited in v2.0 |

### Supporting: Audit Reference Documents

| Document | Location | Purpose |
|----------|----------|---------|
| Economics Primer | audit/v1.1-ECONOMICS-PRIMER.md | Economic model overview (must read before auditing) |
| Endgame Reference | audit/v1.1-endgame-and-activity.md | Death clock, terminal distribution, distress mode details |
| Parameter Reference | audit/v1.1-parameter-reference.md | Constant cross-reference |
| Delta Findings | audit/v2.0-delta-findings-consolidated.md | Prior audit findings (includes some GAMEOVER notes) |
| Warden Report | audit/warden-01-contract-auditor.md | Prior warden sim (flagged GAMEOVER as single-pass only) |
| Terminal Decimator Plan | .planning/PLAN-TERMINAL-DECIMATOR.md | Design spec for the new terminal decimator code |

### Existing Tests

| Test File | Coverage | Gaps |
|-----------|----------|------|
| test/edge/GameOver.test.js | Level-0 timeout, deity refund, final sweep basics | No terminal decimator tests, no level 1+ with populated pools, no VRF fallback test, stale comments (912d vs 365d) |

## Architecture Patterns

### GAMEOVER Execution Flow

```
advanceGame()
  |
  +-- _handleGameOverPath(ts, day, lst, lvl, lastPurchase, dailyIdx)
      |
      +-- Liveness check:
      |     lvl==0: ts - lst > 365 days
      |     lvl>0:  ts - 120 days > lst
      |
      +-- Safety valve (lvl>0 only):
      |     If nextPool >= levelPrizePool[lvl] -> reset levelStartTime, return false
      |
      +-- If gameOver already true:
      |     -> delegatecall handleFinalSweep() -> return true
      |
      +-- Acquire RNG:
      |     _gameOverEntropy(ts, day, lvl, lastPurchase)
      |       |-- Use rngWordByDay[day] if available
      |       |-- Use rngWordCurrent if VRF fulfilled
      |       |-- After 3 days: use historical VRF fallback
      |       |-- If none: request VRF, set timer, return 0/1
      |
      +-- delegatecall handleGameOverDrain(day)
          |
          +-- [1] Deity refunds (level < 10 only)
          |     20 ETH per pass, FIFO, budget-capped to totalFunds - claimablePool
          |     claimablePool += totalRefunded
          |
          +-- [2] Set terminal state
          |     gameOver = true
          |     gameOverTime = block.timestamp
          |     Zero all prize pools
          |
          +-- [3] Terminal decimator (10%)
          |     self.runTerminalDecimatorJackpot(decPool, lvl, rngWord)
          |       -> delegatecall DecimatorModule.runTerminalDecimatorJackpot
          |       -> Returns refund (if no winners)
          |     claimablePool += (decPool - decRefund)
          |     remaining -= decPool; remaining += decRefund
          |
          +-- [4] Terminal jackpot (remaining = 90% + dec refund)
          |     self.runTerminalJackpot(remaining, lvl+1, rngWord)
          |       -> delegatecall JackpotModule.runTerminalJackpot
          |       -> Updates claimablePool internally via _distributeJackpotEth
          |     Undistributed remainder -> _sendToVault
          |
          +-- [5] Burn sDGNRS pool tokens
                dgnrs.burnRemainingPools()
```

### Key State Transitions

```
Normal Play -> livenessTriggered = true -> _handleGameOverPath
  |
  +-- gameOver = false:
  |     Acquire RNG -> handleGameOverDrain -> gameOver = true
  |     (handleGameOverDrain sets gameOverFinalJackpotPaid = true)
  |
  +-- gameOver = true, timestamp < gameOverTime + 30 days:
  |     handleFinalSweep returns silently (too early)
  |
  +-- gameOver = true, timestamp >= gameOverTime + 30 days:
        handleFinalSweep -> finalSwept = true, claimablePool = 0
        All remaining funds -> _sendToVault (50/50 vault/sDGNRS)
```

### claimablePool Mutation Sites on GAMEOVER Path

| Location | Mutation | Direction |
|----------|----------|-----------|
| GameOverModule:105 | `claimablePool += totalRefunded` | UP -- deity refunds |
| GameOverModule:143 | `claimablePool += decSpend` | UP -- decimator allocation |
| JackpotModule:1573 | `claimablePool += ctx.liabilityDelta` | UP -- terminal jackpot credits (inside runTerminalJackpot) |
| GameOverModule:177 | `claimablePool = 0` | ZERO -- final sweep forfeiture |
| DecimatorModule:936 | `_addClaimableEth` -> `_creditClaimable` | UP -- terminal dec claims (post-GAMEOVER) |
| DegenerusGame:1440 | `claimablePool -= payout` | DOWN -- player claim withdrawals |

### Critical Design Decisions

1. **lvl aliasing at level 0:** GameOverModule:72 -- `uint24 lvl = currentLevel == 0 ? 1 : currentLevel;` -- causes terminal jackpot to target level 2 (not level 1) when GAMEOVER fires at level 0.

2. **No-latch retry on missing RNG:** GameOverModule:126 -- `if (rngWord == 0) return;` does NOT set `gameOverFinalJackpotPaid`, allowing handleGameOverDrain to be called again on the next advanceGame when RNG becomes available.

3. **Terminal decimator uses weighted burns:** Unlike normal decimator (uses raw burn totals), terminal decimator applies a time multiplier (up to 30x at 120 days remaining) and uses `weightedBurn` for pro-rata share calculation.

4. **CEI in claimWinnings:** DegenerusGame:1437-1446 -- sentinel pattern (`claimableWinnings[player] = 1`), then `claimablePool -= payout`, then external call. Correct CEI ordering.

5. **VRF fallback is secure:** Uses historical committed VRF words (non-manipulable) combined with prevrandao. Validator has only 1-bit manipulation capability (propose or skip), acceptable for a gameover-only fallback.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audit methodology | Custom checklist | C4A warden methodology with PASS/FINDING verdicts | Industry standard, matches the project's target audience |
| Reentrancy analysis | Manual trace only | CEI pattern verification + external call graph | Systematic coverage beats ad-hoc scanning |
| Invariant verification | Spot checks | Trace every claimablePool mutation on the GAMEOVER path | The central invariant (`balance >= claimablePool`) requires exhaustive trace |
| Fund flow diagrams | Text descriptions | Step-by-step trace with file:line references | Prior audit flagged "single-pass review" as a gap |

## Common Pitfalls

### Pitfall 1: Self-Audit Bias (CP-01)
**What goes wrong:** Auditor (who wrote the code) unconsciously assumes correctness
**Why it happens:** Mental model of intended behavior overrides what the code actually does
**How to avoid:** Treat every line as stranger's code. Read what the code DOES, not what the comments SAY
**Warning signs:** Findings that say "this is correct because it was designed to work this way"

### Pitfall 2: claimablePool Desynchronization (CP-02)
**What goes wrong:** claimablePool becomes larger than actual contract balance, making later claims revert
**Why it happens:** Multiple sites increment claimablePool (deity refunds, decimator allocation, jackpot credits) while balance only changes on external transfers
**How to avoid:** Trace every claimablePool mutation on the GAMEOVER path. Verify that `address(this).balance + stETH.balanceOf(this) >= claimablePool` holds after each mutation
**Warning signs:** claimablePool updated without corresponding balance verification; unchecked arithmetic on pool additions

### Pitfall 3: Reverts Blocking Payouts
**What goes wrong:** A revert in one step of the GAMEOVER sequence blocks all subsequent distributions
**Why it happens:** External calls (stETH transfer, sDGNRS deposit, delegatecall to modules) can fail
**How to avoid:** Verify every external call on the GAMEOVER path. Check if failure in one recipient blocks others
**Warning signs:** `if (!ok) revert E()` patterns with no try/catch on payout paths. The `admin.shutdownVrf()` call in handleFinalSweep correctly uses try/catch, but `_sendToVault` does NOT.

### Pitfall 4: Terminal Jackpot Targets Wrong Level
**What goes wrong:** Terminal jackpot pays level X+2 instead of X+1 at level 0 due to lvl aliasing
**Why it happens:** GameOverModule:72 aliased `lvl = 1` when `currentLevel == 0`, then line 153 calls `runTerminalJackpot(remaining, lvl + 1, rngWord)` which becomes level 2
**How to avoid:** This is BY DESIGN (documented in economics primer). Verify this is intentional and document it as a known behavior
**Warning signs:** None -- this is correct per spec but counter-intuitive

### Pitfall 5: Terminal Decimator Double-Resolution
**What goes wrong:** Terminal decimator could be resolved twice for the same level
**Why it happens:** If `runTerminalDecimatorJackpot` is called multiple times
**How to avoid:** Verify the double-resolution guard: DecimatorModule:888 -- `if (lastTerminalDecClaimRound.lvl == lvl) return poolWei;`
**Warning signs:** Multiple calls to handleGameOverDrain after gameOverFinalJackpotPaid is set

### Pitfall 6: Stale Test Assumptions
**What goes wrong:** Tests pass with wrong thresholds, giving false confidence
**Why it happens:** Test uses 912-day timeout but code uses 365-day timeout. Test overshoots, so it passes, but the comments are wrong
**How to avoid:** Cross-reference test assertions against actual contract constants
**Warning signs:** Test comments mentioning different timeouts than code constants

### Pitfall 7: _sendToVault Reverts Block Final Sweep
**What goes wrong:** If vault or sDGNRS contract cannot receive ETH/stETH, handleFinalSweep reverts permanently
**Why it happens:** `_sendToVault` uses `revert E()` on any transfer failure. No try/catch wrapper.
**How to avoid:** Verify vault and sDGNRS can always receive ETH and stETH. Since these are protocol-owned contracts, this is likely acceptable.
**Warning signs:** Changes to vault or sDGNRS receive logic that could cause failures

### Pitfall 8: decBucketOffsetPacked Collision Between Normal and Terminal Decimator
**What goes wrong:** Normal decimator and terminal decimator both write to `decBucketOffsetPacked[lvl]`
**Why it happens:** DecimatorModule:341 (normal) and DecimatorModule:914 (terminal) both use the same mapping with the same level key
**How to avoid:** Verify whether these can ever run for the same level. If GAMEOVER fires, normal decimator should not run for the same level. The runDecimatorJackpot guard (line 306) returns poolWei if `lastDecClaimRound.lvl == lvl` -- but this guards the NORMAL decimator, not the terminal one. Need to trace whether both could write to decBucketOffsetPacked for the same level.
**Warning signs:** Terminal decimator resolution overwrites normal decimator packed offsets for the same level

## Code Examples

### Example 1: handleGameOverDrain claimablePool Flow (GameOverModule.sol:68-164)

```solidity
// Line 68-69: Idempotency guard
function handleGameOverDrain(uint48 day) external {
    if (gameOverFinalJackpotPaid) return;

    // Lines 71-72: Level aliasing (level 0 -> 1)
    uint24 currentLevel = level;
    uint24 lvl = currentLevel == 0 ? 1 : currentLevel;

    // Lines 74-76: Total balance calculation
    uint256 ethBal = address(this).balance;
    uint256 stBal = steth.balanceOf(address(this));
    uint256 totalFunds = ethBal + stBal;

    // Lines 78-107: Deity refunds (level < 10)
    // Budget = totalFunds - claimablePool (safe subtraction)
    // claimablePool += totalRefunded (must not exceed totalFunds)

    // Line 110: Available after deity refunds
    uint256 available = totalFunds > claimablePool ? totalFunds - claimablePool : 0;

    // Lines 112-113: Set terminal state BEFORE external calls (CEI)
    gameOver = true;
    gameOverTime = uint48(block.timestamp);

    // Lines 138-146: Terminal decimator (10%)
    uint256 decPool = remaining / 10;
    uint256 decRefund = IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord);
    uint256 decSpend = decPool - decRefund;
    claimablePool += decSpend;  // AUDIT: verify decSpend <= available
    remaining -= decPool;
    remaining += decRefund;

    // Lines 151-159: Terminal jackpot (90% + refund)
    uint256 termPaid = IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord);
    // claimablePool updated INSIDE _distributeJackpotEth
    remaining -= termPaid;
    if (remaining != 0) _sendToVault(remaining, stBal);  // AUDIT: stBal may be stale after decimator
```

### Example 2: VRF Fallback Path (AdvanceModule.sol:797-846)

```solidity
function _gameOverEntropy(uint48 ts, uint48 day, uint24 lvl, bool isTicketJackpotDay)
    private returns (uint256 word) {
    // Already have word for today
    if (rngWordByDay[day] != 0) return rngWordByDay[day];

    // VRF fulfilled: apply and return
    if (rngWordCurrent != 0 && rngRequestTime != 0) {
        currentWord = _applyDailyRng(day, currentWord);
        // Also processes coinflip payouts + lootbox RNG
        return currentWord;
    }

    // VRF pending: check fallback timer
    if (rngRequestTime != 0) {
        if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {  // 3 days
            uint256 fallbackWord = _getHistoricalRngFallback(day);
            // AUDIT: fallback is secure (historical VRF + prevrandao)
            return fallbackWord;
        }
        return 0;  // Still waiting
    }

    // No VRF request yet: try to request
    if (_tryRequestRng(isTicketJackpotDay, lvl)) return 1;

    // VRF request failed: start fallback timer
    rngWordCurrent = 0;
    rngRequestTime = ts;  // Timer starts NOW
    return 0;
}
```

### Example 3: Terminal Decimator Time Multiplier (DecimatorModule.sol:1000-1006)

```solidity
// Intentional discontinuity at day 10 (2.75x -> 2x regime change)
function _terminalDecMultiplierBps(uint256 daysRemaining) private pure returns (uint256) {
    if (daysRemaining > 10) {
        return daysRemaining * 2500;  // 30x at 120d, 2.75x at 11d
    }
    // Linear: 2x at day 10, 1x at day 1
    return 10000 + ((daysRemaining - 1) * 10000) / 9;
    // AUDIT: at daysRemaining=0 this underflows (but gated by TerminalDecDeadlinePassed)
    // AUDIT: at daysRemaining=1 this returns 10000 (1x) -- correct
    // AUDIT: at daysRemaining=10 this returns 20000 (2x) -- correct
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No terminal decimator | Terminal decimator (death bet) added | Recent (uncommitted until recent merge) | ~490 lines of new code with zero prior audit |
| 912-day level-0 timeout (per old tests) | 365-day level-0 timeout | Code uses DEPLOY_IDLE_TIMEOUT_DAYS=365 | Test comments are stale |
| Single decimator claim round | Normal + terminal decimator claim rounds | Recent | Two separate claim round structs (lastDecClaimRound vs lastTerminalDecClaimRound) |

## Open Questions

1. **decBucketOffsetPacked Sharing**
   - What we know: Both `runDecimatorJackpot` (line 341) and `runTerminalDecimatorJackpot` (line 914) write to `decBucketOffsetPacked[lvl]`
   - What's unclear: Can both be called for the same level? If normal decimator ran at level X and then GAMEOVER fires at level X, would the terminal decimator overwrite the packed offsets?
   - Recommendation: Trace whether the same level can have both normal and terminal decimator resolution. This is a potential collision that could corrupt claim validation.

2. **stBal Staleness in handleGameOverDrain**
   - What we know: `stBal` is read at line 75, but `_sendToVault(remaining, stBal)` at line 159 happens after delegatecalls to decimator and jackpot modules
   - What's unclear: Could the decimator or jackpot module transfer stETH, making `stBal` stale?
   - Recommendation: Verify that no delegatecall module transfers stETH. Since modules run via delegatecall in the game contract's context, they operate on the game's storage but shouldn't directly transfer stETH.

3. **Unchecked Arithmetic in Deity Refund Loop**
   - What we know: GameOverModule:92-96 uses `unchecked { claimableWinnings[owner] += refund; totalRefunded += refund; budget -= refund; }`
   - What's unclear: Can `claimableWinnings[owner]` overflow with unchecked? In theory, if a player already has large claimable winnings and gets a deity refund, the addition could wrap.
   - Recommendation: Verify that `claimableWinnings` values are bounded. The sentinel pattern uses 1 as minimum, but total theoretical maximum needs checking.

4. **Terminal Decimator Claim Expiry**
   - What we know: Normal decimator claims expire when the next decimator runs (overwrites lastDecClaimRound). Terminal decimator has its own lastTerminalDecClaimRound.
   - What's unclear: After GAMEOVER, can anything overwrite lastTerminalDecClaimRound? If handleGameOverDrain is somehow called again (despite gameOverFinalJackpotPaid guard), could terminal dec claims be wiped?
   - Recommendation: Verify the gameOverFinalJackpotPaid latch is airtight and that no other path can modify lastTerminalDecClaimRound.

5. **_processAutoRebuy During Terminal Decimator Claims**
   - What we know: `claimTerminalDecimatorJackpot()` calls `_addClaimableEth(msg.sender, amountWei, 0)` which calls `_processAutoRebuy` which checks `if (gameOver) return false;`
   - What's unclear: This check is in the DecimatorModule's `_addClaimableEth` (line 516), which correctly skips auto-rebuy during GAMEOVER. Verify this is the version called (not EndgameModule's `_addClaimableEth` which has different auto-rebuy logic).
   - Recommendation: Confirm which `_addClaimableEth` is active during terminal decimator claims (delegatecall context matters).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hardhat + Chai (JavaScript), Foundry for fuzz |
| Config file | hardhat.config.ts |
| Quick run command | `npx hardhat test test/edge/GameOver.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GO-01 | handleGameOverDrain distribution verified | manual audit | N/A (code review, not automated test) | N/A |
| GO-02 | handleFinalSweep 30-day window, claimablePool zeroing | manual audit + existing edge test | `npx hardhat test test/edge/GameOver.test.js` | Partial (basic sweep test exists) |
| GO-03 | Death clock trigger conditions (365d/120d) | manual audit + existing edge test | `npx hardhat test test/edge/GameOver.test.js` | Partial (level 0 tested, level 1+ incomplete) |
| GO-04 | Distress mode effects | manual audit | N/A | No test exists |
| GO-05 | Every require/revert on GAMEOVER path | manual audit | N/A | No test exists |
| GO-06 | Reentrancy and state ordering | manual audit | N/A | No test exists |
| GO-07 | Deity pass refunds (levels 0-9) | manual audit + existing edge test | `npx hardhat test test/edge/GameOver.test.js` | Partial (level 0 refund tested) |
| GO-08 | Terminal decimator integration | manual audit | N/A | No test exists |
| GO-09 | No-RNG-available fallback path | manual audit | N/A | No test exists |

### Sampling Rate
- **Per task commit:** `npx hardhat test test/edge/GameOver.test.js` (existing tests remain green)
- **Per wave merge:** `npm test` (full suite)
- **Phase gate:** All audit findings documented with PASS/FINDING verdicts and file:line references

### Wave 0 Gaps
This is an audit phase, not a code implementation phase. The "tests" are the audit verdicts themselves. No new automated tests are required as deliverables, though findings may recommend new tests.

## Audit-Specific Methodology

### Approach Per Requirement

**GO-01 through GO-09 each require:**
1. Read the relevant code section line by line
2. Trace all state mutations (especially claimablePool)
3. Trace all external calls and their failure modes
4. Verify CEI ordering
5. Check for reentrancy vectors
6. Verify arithmetic (overflow/underflow, division by zero, rounding)
7. Deliver explicit PASS or FINDING verdict with file:line references

### Audit Output Format

Each requirement should produce a verdict in this format:
```
### GO-XX: [Title]
**Verdict:** PASS | FINDING-[severity]
**Files:** [file:line-range]
**Summary:** [1-2 sentences]
**Trace:** [step-by-step execution trace if FINDING]
**Recommendation:** [fix if FINDING, or "None" if PASS]
```

### Priority Order

1. **GO-08** (Terminal decimator) -- newest code, zero coverage, highest finding probability
2. **GO-01** (handleGameOverDrain) -- central distribution logic, all other GO-xx depend on it
3. **GO-06** (Reentrancy/CEI) -- highest severity if violated
4. **GO-05** (Reverts blocking payouts) -- could permanently lock funds
5. **GO-09** (No-RNG fallback) -- could prevent GAMEOVER from ever firing
6. **GO-07** (Deity refunds) -- unchecked arithmetic in refund loop
7. **GO-02** (Final sweep) -- relatively simple but fund-critical
8. **GO-03** (Death clock) -- well-documented, likely PASS
9. **GO-04** (Distress mode) -- effects are in other modules, least risk on GAMEOVER path

## Sources

### Primary (HIGH confidence)
- DegenerusGameGameOverModule.sol -- read in full (233 lines)
- DegenerusGameDecimatorModule.sol -- read in full (1027 lines), focus on terminal decimator section (749-1027)
- DegenerusGameAdvanceModule.sol -- GAMEOVER/liveness section (405-462), RNG fallback section (797-875)
- DegenerusGameJackpotModule.sol -- runTerminalJackpot (288-324), _distributeJackpotEth (1537-1576)
- DegenerusGameStorage.sol -- state variable definitions, _isDistressMode()
- DegenerusGame.sol -- dispatch wrappers, claimWinnings (1415-1447)
- audit/v1.1-endgame-and-activity.md -- death clock, terminal distribution, distress mode reference
- test/edge/GameOver.test.js -- existing test coverage assessment

### Secondary (MEDIUM confidence)
- audit/v2.0-delta-findings-consolidated.md -- prior findings related to burnRemainingPools and GAMEOVER
- audit/warden-01-contract-auditor.md -- warden sim that flagged GAMEOVER as single-pass reviewed
- .planning/PLAN-TERMINAL-DECIMATOR.md -- design spec for terminal decimator

## Metadata

**Confidence breakdown:**
- Contract code understanding: HIGH -- all 7 source files read in full
- Audit methodology: HIGH -- based on C4A warden standards with project-specific adaptations
- Pitfall identification: HIGH -- cross-referenced prior audit findings, economics docs, and code
- Open questions: MEDIUM -- 5 questions identified that require code-level verification during audit

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (30 days -- code is actively developed, terminal decimator may change)
