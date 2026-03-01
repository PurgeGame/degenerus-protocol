---
phase: 03a-core-eth-flow-modules
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md
autonomous: true
requirements: [DOS-01]

must_haves:
  truths:
    - "Every for/while loop in JackpotModule is bounded by an explicit constant or gas budget"
    - "Daily jackpot chunked resume state cannot be corrupted by partial completion"
    - "consolidatePrizePools correctly merges next->current without wei leak"
    - "_addClaimableEth auto-rebuy path correctly adjusts pool accounting via claimableDelta return value"
    - "90/10 prize pool conceptual split is enforced at purchase time and maintained through consolidation"
  artifacts:
    - path: ".planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md"
      provides: "JackpotModule audit findings document"
      contains: "## Findings"
  key_links:
    - from: "contracts/modules/DegenerusGameJackpotModule.sol"
      to: "contracts/storage/DegenerusGameStorage.sol"
      via: "dailyEthPhase, dailyEthBucketCursor, dailyEthWinnerCursor, dailyEthPoolBudget resume state"
      pattern: "dailyEthPhase|dailyEthBucketCursor"
    - from: "contracts/modules/DegenerusGameJackpotModule.sol"
      to: "contracts/modules/DegenerusGamePayoutUtils.sol"
      via: "_addClaimableEth -> _calcAutoRebuy"
      pattern: "_addClaimableEth|_calcAutoRebuy"
---

<objective>
Audit DegenerusGameJackpotModule for ETH outflow correctness: prize pool consolidation, daily jackpot chunked distribution, gas-budgeted loop bounds, and auto-rebuy pool accounting.

Purpose: JackpotModule distributes all prize pool ETH to winners. Incorrect distribution, unbounded loops, or corrupted resume state could lock funds, skip winners, double-pay, or exhaust block gas limits.
Output: 03a-02-FINDINGS.md documenting all confirmed findings, false positives, and PASS verdicts.
</objective>

<execution_context>
@/home/zak/.claude/get-shit-done/workflows/execute-plan.md
@/home/zak/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/03a-core-eth-flow-modules/03a-RESEARCH.md

Source files to audit (READ-ONLY — do NOT modify):
@contracts/modules/DegenerusGameJackpotModule.sol (2740 lines)
@contracts/modules/DegenerusGamePayoutUtils.sol (94 lines)
@contracts/storage/DegenerusGameStorage.sol (resume state variables, pool variables)
@contracts/libraries/JackpotBucketLib.sol (286 lines — bucket sizing and share calculations)

<interfaces>
<!-- Key constants the executor must verify as loop bounds -->

JackpotModule constants:
  WRITES_BUDGET_SAFE = 550
  DAILY_JACKPOT_UNITS_SAFE = 1000
  DAILY_JACKPOT_UNITS_AUTOREBUY = 3
  MAX_BUCKET_WINNERS = 250
  JACKPOT_MAX_WINNERS = 300
  DAILY_ETH_MAX_WINNERS = 321
  DAILY_CURRENT_BPS_MIN = 600 (6%)
  DAILY_CURRENT_BPS_MAX = 1400 (14%)

Resume state fields (DegenerusGameStorage):
  dailyEthPhase (uint8) — which phase (0=current ETH, 1=carryover, 2=coin+tickets)
  dailyEthBucketCursor (uint8) — which bucket in current phase
  dailyEthWinnerCursor (uint16) — which winner in current bucket
  dailyEthPoolBudget (uint256) — remaining ETH to distribute

Key functions to trace:
  consolidatePrizePools() — merges next->current, future->current rebalance
  payDailyJackpot() — three-phase daily distribution
  _processDailyEthChunk() — inner loop with gas budget
  _addClaimableEth() — credits player or auto-rebuy with claimableDelta return
  processTicketBatch() — ticket owed batch processing with writes budget
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit prize pool consolidation and daily jackpot state machine</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **consolidatePrizePools correctness:**
   - Read consolidatePrizePools() (around line 835)
   - Trace: nextPrizePool merges into currentPrizePool — verify no wei lost (exact transfer, no BPS)
   - Trace time-based and RNG-based future->current rebalance
   - Verify futurePrizePool dump mechanics: 1-in-1e15 chance (FUTURE_DUMP_ODDS) on non-milestone, weighted random keep-roll at milestone-100
   - Verify that after consolidation: nextPrizePool == 0, and currentPrizePool + futurePrizePool == pre-consolidation sum

2. **Daily jackpot three-phase state machine:**
   - Read payDailyJackpot() entry point — map the three phases (0: current ETH, 1: carryover ETH, 2: coin+tickets)
   - Trace resume detection (lines 287-289): OR of four resume fields. Verify that a partial state (one non-zero, others zero) cannot cause corruption
   - For Phase 0: verify _dailyCurrentPoolBps correctly computes 6-14% random draw. Verify Day 5 (counter >= 4) gives 100%
   - For Phase 1: verify carryover ETH draws from futurePrizePool at 1% (100 BPS). Verify carryover winner cap = DAILY_ETH_MAX_WINNERS - daily winners
   - Verify that all four resume fields are cleared together on phase completion. Check lines 474-481 and 540-546 for complete clearing

3. **_addClaimableEth auto-rebuy path:**
   - Read _addClaimableEth() (line 911) — trace both paths: direct claimable credit and auto-rebuy
   - Verify claimableDelta return value is correctly used by ALL callers
   - If auto-rebuy consumes the ETH, verify: claimableDelta == 0 AND the ETH is correctly routed to the appropriate pool (futurePrizePool or nextPrizePool via _processAutoRebuy)
   - Verify _calcAutoRebuy from PayoutUtils (94 lines) — check bonus BPS values, confirm no overflow in bonus calculation
   - Compare JackpotModule's _addClaimableEth (line 911) with EndgameModule's version (line 217) — document any differences

Write findings to 03a-02-FINDINGS.md with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md && grep -c "consolidatePrizePools\|dailyEthPhase\|_addClaimableEth" .planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md | xargs test 1 -le</automated>
  </verify>
  <done>Prize pool consolidation verified for wei-exact transfer. Daily jackpot state machine phases fully traced. Resume state clearing verified. Auto-rebuy claimableDelta handling verified at all call sites. JackpotModule vs EndgameModule _addClaimableEth compared.</done>
</task>

<task type="auto">
  <name>Task 2: Verify all loop bounds and unchecked blocks in JackpotModule (DOS-01)</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Systematic loop bound enumeration (DOS-01):**
   Enumerate EVERY for/while loop in JackpotModule (2740 lines). For each loop, document:
   - Location (line number)
   - Loop variable and termination condition
   - Maximum iteration count
   - What bounds it (constant, gas budget, or input parameter)
   - Whether the bound is explicitly enforced or assumed

   Expected loops (from research — verify completeness):
   - _runEarlyBirdLootboxJackpot (line 770): for i < maxWinners, max=100
   - _processDailyEthChunk (line 1384): for i < 4 (bucket count)
   - _processDailyEthChunk (line 1420): for i < len, len <= MAX_BUCKET_WINNERS=250, also bounded by unitsBudget=1000
   - processTicketBatch (line 1888): while-loop bounded by WRITES_BUDGET_SAFE=550
   - _distributeTicketJackpot (line 1100): for i < 4 (trait count)
   - _distributeTicketsToBucket (line 1148): for i < count, count <= MAX_BUCKET_WINNERS=250
   - _randTraitTicket (line 2225): for i < numWinners, uint8 max 250
   - All 5-iteration early-bird price loops

   CRITICAL: Search for any loop NOT in this list. Any loop without an explicit bound is a potential DOS-01 finding.

2. **Gas budget verification:**
   - _processDailyEthChunk uses unitsBudget = DAILY_JACKPOT_UNITS_SAFE = 1000. Each winner costs _winnerUnits() (1 normal, 3 auto-rebuy). Verify: worst case = all auto-rebuy = 1000/3 = 333 winners max. Is 333 * gas_per_winner safe under block gas limit?
   - processTicketBatch uses WRITES_BUDGET_SAFE = 550. Verify cold-storage scaling. Verify that a single player with a very large owed count advances the cursor and does not loop forever.

3. **All unchecked blocks audit:**
   - Enumerate every `unchecked` block in JackpotModule (39 occurrences found via grep)
   - Group by category: loop counters (safe — bounded increment), pool arithmetic (verify no underflow), BPS calculations (verify inputs bounded)
   - Focus on pool accounting unchecked blocks: any subtraction from currentPrizePool or futurePrizePool must be verified as safe (amount <= pool balance)
   - Document each unchecked block's safety justification or raise a finding

4. **Winner selection fairness (informational):**
   - _randTraitTicket uses entropy from VRF word to select trait-based winners
   - Verify numWinners parameter is always bounded by MAX_BUCKET_WINNERS or JACKPOT_MAX_WINNERS
   - Verify no off-by-one in winner selection range

Append findings to 03a-02-FINDINGS.md. Include a loop bounds summary table: location, max iterations, bounding mechanism.
  </action>
  <verify>
    <automated>grep -c "for\|while\|loop\|iteration" .planning/phases/03a-core-eth-flow-modules/03a-02-FINDINGS.md | xargs test 5 -le</automated>
  </verify>
  <done>Every loop in JackpotModule enumerated with max iteration count and bounding mechanism. All 39 unchecked blocks assessed. No unbounded loop found (or finding raised if one exists). Gas budget analysis confirms safe under block gas limit. Summary table maps DOS-01 to verdict.</done>
</task>

</tasks>

<verification>
- 03a-02-FINDINGS.md exists with severity-rated findings
- Complete loop inventory for JackpotModule (every for/while enumerated)
- Gas budget analysis with worst-case iteration counts
- consolidatePrizePools wei-exact verification
- Daily jackpot resume state clearing completeness verified
- All 39 unchecked blocks individually assessed
- DOS-01 mapped to verdict in summary table
</verification>

<success_criteria>
- Prize pool consolidation verified as wei-exact (no loss)
- Daily jackpot state machine fully traced with all phase transitions
- Every loop in JackpotModule has documented max iterations and bounding mechanism
- All 39 unchecked blocks individually assessed as safe or finding raised
- No unbounded iteration found (or DOS-01 finding documented with severity)
- Auto-rebuy claimableDelta handling verified at all call sites
</success_criteria>

<output>
After completion, create `.planning/phases/03a-core-eth-flow-modules/03a-02-SUMMARY.md`
</output>
