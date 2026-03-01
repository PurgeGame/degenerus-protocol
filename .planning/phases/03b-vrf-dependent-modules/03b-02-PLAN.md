---
phase: 03b-vrf-dependent-modules
plan: 03b-02
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md
autonomous: true
requirements:
  - MATH-05

must_haves:
  truths:
    - "The gameOverFinalJackpotPaid guard is confirmed to prevent re-entry into handleGameOverDrain"
    - "All three deity pass refund tiers are traced: level 0 (full refund), level 1-9 (20 ETH/pass), level 10+ (no refund)"
    - "The `available = totalFunds - claimablePool` computation is confirmed safe against underflow when totalRefunded pushes claimablePool above totalFunds"
    - "The BAF/Decimator 50% split is verified with exact fund flow from available balance to jackpot contract credits"
    - "The _sendToVault 50/50 split between VAULT and DGNRS is confirmed with no rounding loss beyond 1 wei"
    - "handleFinalSweep 30-day guard is confirmed: the time check prevents premature sweeping and claimablePool is preserved for pending claims"
    - "The deityPassOwners iteration is bounded by DEITY_PASS_MAX_TOTAL=24 with no unbounded .push() path"
  artifacts:
    - path: ".planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md"
      provides: "Complete GameOverModule terminal settlement audit, fund distribution verification, re-entry guard confirmation"
      contains: "MATH-05"
  key_links:
    - from: "contracts/modules/DegenerusGameGameOverModule.sol:handleGameOverDrain"
      to: "gameOverFinalJackpotPaid"
      via: "Guard flag prevents double execution"
      pattern: "gameOverFinalJackpotPaid"
    - from: "contracts/modules/DegenerusGameGameOverModule.sol:handleGameOverDrain"
      to: "claimableWinnings[owner]"
      via: "Deity pass refund credits"
      pattern: "claimableWinnings.*refund"
    - from: "contracts/modules/DegenerusGameGameOverModule.sol:handleFinalSweep"
      to: "_sendToVault"
      via: "Remaining funds swept to vault/DGNRS after 30 days"
      pattern: "_sendToVault"
---

<objective>
Audit the DegenerusGameGameOverModule (~287 lines) for terminal settlement correctness, fund distribution safety, re-entry prevention, and iteration bounds.

Purpose: GameOver is a one-shot irreversible operation that distributes all remaining protocol funds. Any bug in the refund calculation, available balance computation, or distribution split permanently locks or misallocates ETH. This plan verifies every path through terminal settlement produces correct outcomes and the 30-day final sweep correctly handles residual funds.

Output: `03b-02-FINDINGS-gameover-module-audit.md` containing the complete terminal settlement trace, fund distribution verification, and findings.
</objective>

<execution_context>
@/home/zak/.claude/get-shit-done/workflows/execute-plan.md
@/home/zak/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/phases/03b-vrf-dependent-modules/03b-RESEARCH.md

<interfaces>
<!-- Primary audit target: contracts/modules/DegenerusGameGameOverModule.sol (287 lines) -->

Terminal settlement architecture (from research):
  handleGameOverDrain(day):
    1. Level check determines refund tier
    2. Deity pass refund loop (bounded by deityPassOwners.length)
    3. available = totalFunds - claimablePool
    4. 50% to BAF, 50% to Decimator
    5. gameOver = true, gameOverFinalJackpotPaid = true

  handleFinalSweep():
    After 30 days, sweep remaining balance to vault/DGNRS

Refund tiers (from contract lines 77-121):
  Level 0 + no jackpot phase: full refund (deityPassPaidTotal[owner])
  Level 1-9: 20 ETH per pass (DEITY_PASS_EARLY_GAMEOVER_REFUND)
  Level 10+: no refund

Constants:
  DEITY_PASS_MAX_TOTAL = 24
  DEITY_PASS_EARLY_GAMEOVER_REFUND = 20 ether

Key concern from research Open Question #3:
  If totalRefunded exceeds available, does available go negative (underflow)?
  Or is claimablePool updated to prevent this?

Phase 2 finding FSM-F02 (LOW):
  handleGameOverDrain receives stale dailyIdx -- may skip BAF/Decimator distribution.
  Funds preserved for final sweep. Already documented.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Trace all terminal settlement paths including refund tiers, fund distribution, and re-entry guards</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

Read `contracts/modules/DegenerusGameGameOverModule.sol` in its entirety (~287 lines).

**1. Re-Entry Guard Analysis**

a. Locate the `gameOverFinalJackpotPaid` check at entry to `handleGameOverDrain`
b. Confirm the guard is checked BEFORE any state mutation or external call
c. Confirm the guard is set AFTER all distributions are complete (or at the point of no-revert)
d. Is there any path through handleGameOverDrain that exits without setting the guard?

**2. Deity Pass Refund Tier Audit**

For each of the three tiers:

a. **Level 0 (full refund):**
   - What are the exact conditions? `currentLevel == 0 && !jackpotPhaseFlag`?
   - Verify refund = `deityPassPaidTotal[owner]` (what each deity actually paid)
   - Verify `claimableWinnings[owner] += refund` uses unchecked — can this overflow? Maximum per-owner: ~300 ETH (at k=23). Maximum total: 24 * 300 = 7200 ETH. uint256 safe.
   - Verify `deityPassPaidTotal[owner] = 0` and `deityPassRefundable[owner] = 0` are zeroed after credit
   - What happens if `deityPassPaidTotal[owner]` is 0 for some owners? (Skipped by `if (refund != 0)`)

b. **Level 1-9 (20 ETH/pass):**
   - What are the exact conditions? `currentLevel >= 1 && currentLevel < 10`?
   - Verify refund = `20 ether * uint256(purchasedCount)` — can this overflow? Max 24 passes * 20 ETH = 480 ETH. Safe.
   - Verify `deityPassPurchasedCount[owner]` is the correct field (not deityPassPaidTotal)
   - What happens if purchasedCount is 0? (Skipped by `if (purchasedCount != 0)`)

c. **Level 10+ (no refund):**
   - Confirm this branch does nothing — no loop, no credit
   - Verify there is no fallthrough from level 1-9 branch

**3. Available Balance Safety**

a. After refunds, trace: `totalRefunded` is added to `claimablePool` (or is it added via claimableWinnings?)
b. Compute: `available = totalFunds - claimablePool`
   - If refunds pushed claimablePool above totalFunds (because funds were spent on jackpots before game-over), does this underflow?
   - Check: is there a `totalFunds > claimablePool ? ... : 0` guard, or does it use unchecked subtraction?
   - If raw subtraction: FLAG AS HIGH (underflow wraps to huge number, distributes phantom ETH)
   - If guarded: confirm the guard is correct

c. Verify `totalFunds` meaning: is it `address(this).balance` or a tracked accounting variable? This determines if external ETH deposits (selfdestruct, coinbase) could inflate it.

**4. BAF/Decimator Distribution**

a. Trace the 50% BAF path: `_payGameOverBafEthOnly(available / 2, ...)`
   - What external call does this make? (Expected: credit winners via jackpots contract)
   - What happens if the jackpots contract reverts?
b. Trace the Decimator path: remaining to `_payGameOverDecimatorEthOnly`
   - What happens to unclaimed Decimator funds? (Expected: _sendToVault)
c. Verify: does `available / 2` lose 1 wei on odd amounts? Where does the dust go?

**5. Final State Mutations**

a. Confirm `gameOver = true` is set (irreversible terminal state)
b. Confirm `gameOverFinalJackpotPaid = true` is set (re-entry guard)
c. Are there any state mutations AFTER external calls? (CEI violation check)

Write as Sections 1-3 of the findings document.
  </action>
  <verify>
    <automated>
      cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
      grep -n "gameOverFinalJackpotPaid\|handleGameOverDrain\|handleFinalSweep\|claimableWinnings\|_sendToVault" contracts/modules/DegenerusGameGameOverModule.sol | wc -l
    </automated>
  </verify>
  <done>
    Every path through handleGameOverDrain is traced with exact line numbers.
    All three refund tiers verified with overflow analysis.
    Available balance underflow risk assessed (guarded or flagged).
    BAF/Decimator split verified with dust handling documented.
    Re-entry guard placement confirmed correct.
  </done>
</task>

<task type="auto">
  <name>Task 2: Audit handleFinalSweep, iteration bounds, and cross-reference Phase 2 findings; write verdicts</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. handleFinalSweep Audit**

a. Read the handleFinalSweep function completely.
b. Verify the 30-day time guard:
   - What timestamp is compared? (Expected: block.timestamp vs gameOver timestamp + 30 days)
   - Can this be called before 30 days elapse? (Must revert)
   - Can this be called multiple times after 30 days? (Should be safe — check guard)
c. Verify fund routing:
   - `available = totalFunds - claimablePool` — same underflow concern as handleGameOverDrain
   - `_sendToVault(available)` — trace the 50/50 split to VAULT and DGNRS
d. Verify claimablePool is NOT zeroed — players must still be able to claim winnings after sweep
e. Check: what if `available == 0`? (No funds to sweep — should be a no-op or harmless)

**2. _sendToVault Function**

a. Locate and read `_sendToVault` completely.
b. Verify the 50/50 split: half to VAULT contract, half to DGNRS contract
c. How is ETH sent? (call, transfer, or send?) Check for gas stipend adequacy
d. What happens if either recipient reverts? Does the entire sweep fail?
e. Rounding: on odd wei amounts, where does the 1 wei dust go?

**3. Iteration Bound Verification**

a. Verify `deityPassOwners` array length is bounded:
   - Find where `deityPassOwners.push(owner)` is called
   - Confirm max length = `DEITY_PASS_MAX_TOTAL` = 24
   - Confirm no unbounded push exists that could grow the array past 24
b. The refund loops iterate `ownerCount = deityPassOwners.length` times — max 24 iterations. Gas cost: ~24 * (2 SLOAD + 1 SSTORE) = ~24 * 25,000 = ~600,000 gas. Well within block limit.
c. Check: are there any other loops in GameOverModule? If so, what bounds them?

**4. Cross-Reference with Phase 2**

a. Phase 2 finding FSM-F02 (LOW): handleGameOverDrain receives stale dailyIdx. Verify the impact:
   - Does a stale dailyIdx cause the BAF/Decimator distribution to use wrong trait buckets?
   - Confirm funds are preserved for final sweep even if daily distribution is skipped
b. Phase 2 FSM-03 (PASS): multi-step game-over handles all intermediate states. Does GameOverModule correctly handle being called at any point in the multi-step sequence?

**5. Edge Cases**

a. What if handleGameOverDrain is called with zero deity pass owners? (ownerCount = 0, no loop executed, available = totalFunds - claimablePool, all funds to BAF/Decimator split)
b. What if the game ends at level 0 with deity passes BUT jackpotPhaseFlag is true? (Falls through to level 1-9 tier even though level is 0 — verify this is correct behavior)
c. What if handleGameOverDrain is called but totalFunds == claimablePool? (available = 0, no distribution, but gameOver still set — correct)

**6. Write Complete Findings Document**

Sections:
1. Terminal Settlement Path Trace (from Task 1)
2. handleFinalSweep and _sendToVault Audit
3. Iteration Bound Verification
4. Available Balance Safety Analysis (underflow assessment)
5. Edge Case Analysis
6. Cross-Reference with Phase 2 Findings
7. MATH-05 Partial Verdict: Terminal settlement fund distribution correctness
8. Findings (any issues rated by severity)
  </action>
  <verify>
    <automated>
      test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md && \
      grep -c "handleFinalSweep\|_sendToVault\|DEITY_PASS_MAX_TOTAL\|underflow\|gameOverFinalJackpotPaid" /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md
    </automated>
  </verify>
  <done>
    03b-02-FINDINGS-gameover-module-audit.md exists and contains:
    - Complete handleGameOverDrain path trace with all refund tiers
    - handleFinalSweep 30-day guard verified
    - _sendToVault 50/50 split verified
    - deityPassOwners iteration confirmed bounded at 24
    - Available balance underflow risk assessed
    - Cross-reference with Phase 2 FSM-F02 documented
    - Edge cases analyzed
    - Any findings rated by severity
    - No contract files were modified
  </done>
</task>

</tasks>

<verification>
```bash
# Verify findings document exists
test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md && echo "File exists"

# Verify key audit areas covered
grep -E "gameOverFinalJackpotPaid|handleFinalSweep|deityPassOwners|underflow" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md

# Verify all three refund tiers documented
grep -c "level 0\|level 1-9\|level 10\|Level 0\|Level 1\|Level 10" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-02-FINDINGS-gameover-module-audit.md
```
</verification>

<success_criteria>
- 03b-02-FINDINGS-gameover-module-audit.md exists in the phase directory
- gameOverFinalJackpotPaid re-entry guard is confirmed correct
- All three deity pass refund tiers are traced with overflow analysis
- available = totalFunds - claimablePool underflow safety is verified
- BAF/Decimator 50% split is verified with dust handling
- handleFinalSweep 30-day guard is confirmed
- _sendToVault 50/50 split is verified
- deityPassOwners iteration is confirmed bounded (max 24)
- Phase 2 FSM-F02 cross-reference is documented
- Any findings rated by severity
- No contract files were modified
</success_criteria>

<output>
After completion, create `.planning/phases/03b-vrf-dependent-modules/03b-02-SUMMARY.md` following the standard summary template.
</output>
