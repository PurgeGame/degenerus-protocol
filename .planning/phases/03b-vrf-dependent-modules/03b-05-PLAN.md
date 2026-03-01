---
phase: 03b-vrf-dependent-modules
plan: 03b-05
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md
autonomous: true
requirements:
  - DOS-02

must_haves:
  truths:
    - "All cursor-related storage variables are enumerated: dailyEthPhase, dailyEthBucketCursor, dailyEthWinnerCursor, dailyEthPoolBudget"
    - "The resume detection logic is traced: isResuming = (dailyEthPoolBudget != 0 || dailyEthPhase != 0 || dailyEthBucketCursor != 0 || dailyEthWinnerCursor != 0)"
    - "Fresh start initialization is confirmed: all cursor variables are set to their correct initial values before distribution begins"
    - "Cursor save on gas exhaustion is verified: _distributeDailyEthBucket saves exact cursor position (bucket index + winner index) when unitsBudget is exceeded"
    - "Cursor resume correctly restores exact position on next call — no bucket or winner is skipped or repeated"
    - "No external function outside of handleDailyJackpot/advanceGame delegatecall can write to cursor variables"
    - "Complete cursor reset at end of distribution is verified — no stale cursor state persists between daily distributions"
    - "Phase transition (Phase 0 current level -> Phase 1 carryover -> reset) is traced with no skip path"
  artifacts:
    - path: ".planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md"
      provides: "Complete daily ETH distribution cursor audit, griefing resistance verification, resume/save/reset trace, DOS-02 verdict"
      contains: "DOS-02"
  key_links:
    - from: "contracts/modules/DegenerusGameJackpotModule.sol:handleDailyJackpot"
      to: "dailyEthBucketCursor"
      via: "Cursor initialization and resume detection"
      pattern: "dailyEthBucketCursor"
    - from: "contracts/modules/DegenerusGameJackpotModule.sol:_distributeDailyEthBucket"
      to: "dailyEthBucketCursor + dailyEthWinnerCursor"
      via: "Cursor save on gas budget exhaustion"
      pattern: "dailyEthBucketCursor.*=.*j"
    - from: "contracts/modules/DegenerusGameJackpotModule.sol:handleDailyJackpot"
      to: "advanceGame delegatecall"
      via: "Only callable via delegatecall from DegenerusGame.advanceGame"
      pattern: "handleDailyJackpot"
---

<objective>
Audit the daily ETH distribution bucket cursor logic in DegenerusGameJackpotModule for griefing resistance. Verify that the cursor system correctly initializes, saves, resumes, and resets across multiple advanceGame calls, and that no external caller can advance the cursor independently to skip distributions.

Purpose: DOS-02 requires proving the daily ETH distribution bucket cursor cannot be griefed to skip distributions. The cursor system spans multiple advanceGame calls (gas-budgeted to avoid block limit issues), so correctness depends on atomic consistency of the cursor state across calls. Any inconsistency could cause winners to be skipped, distributions to be repeated, or funds to be permanently stuck.

Output: `03b-05-FINDINGS-daily-eth-cursor-griefing.md` containing the complete cursor lifecycle trace, griefing resistance analysis, and DOS-02 verdict.
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
<!-- Primary audit target: contracts/modules/DegenerusGameJackpotModule.sol (2740 lines) -->
<!-- Focus: lines 280-550 (daily ETH distribution) and 1350-1465 (bucket distribution inner loop) -->

Cursor variables (from research):
  dailyEthPhase: 0 = current level distribution, 1 = carryover distribution
  dailyEthBucketCursor: which trait bucket is being processed (0-3)
  dailyEthWinnerCursor: which winner within the current bucket
  dailyEthPoolBudget: remaining ETH to distribute in current phase

Resume detection (from research):
  isResuming = dailyEthPoolBudget != 0 || dailyEthPhase != 0 || dailyEthBucketCursor != 0 || dailyEthWinnerCursor != 0
  Any non-zero value triggers resume mode

Gas budgeting (from research):
  unitsBudget caps per-call work in _distributeDailyEthBucket
  When budget exceeded: save cursors, return, continue on next advanceGame call

Access control:
  handleDailyJackpot is only callable via delegatecall from DegenerusGame
  No external function can write cursor variables directly
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Trace complete cursor lifecycle: initialization, save, resume, reset, and phase transitions</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

Read `contracts/modules/DegenerusGameJackpotModule.sol`, focusing on lines 280-550 (handleDailyJackpot / daily ETH entry point) and lines 1350-1465 (_distributeDailyEthBucket inner loop).

**1. Cursor Variable Inventory**

a. Grep for all references to `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `dailyEthPoolBudget` across the entire contracts/ directory.
b. For each variable: list every READ site (file:line) and every WRITE site (file:line).
c. Confirm that ALL write sites are within JackpotModule (called via delegatecall from DegenerusGame).
d. If any write site exists outside JackpotModule, flag as HIGH finding (external cursor manipulation possible).

**2. Fresh Start Initialization**

a. Trace what happens when a daily ETH distribution starts from scratch (not resuming):
   - How is `isResuming` computed? Verify the exact condition.
   - When NOT resuming: what are the cursors initialized to?
   - How is `dailyEthPoolBudget` computed? (Expected: a portion of the prize pool based on level/day)
   - Are all four cursor variables written atomically, or could a revert leave partial state?

**3. Cursor Save on Gas Exhaustion**

a. Trace `_distributeDailyEthBucket` inner loop:
   - How does the `unitsBudget` work? (Expected: decremented per unit of work; when exhausted, save and return)
   - What exact values are saved? (dailyEthBucketCursor = current bucket index j, dailyEthWinnerCursor = current winner index i)
   - Is `dailyEthPoolBudget` updated atomically with the cursor positions?
   - What happens if the function reverts after some winners are paid but before cursors are saved? (Are winners double-paid on resume?)

b. Verify the save is correct:
   - After saving cursor at (bucket=2, winner=15), the next call resumes at exactly (bucket=2, winner=15)
   - No winner is skipped (winner 15 is not reprocessed AND winner 16 is processed next)
   - No bucket is skipped (bucket 2 completes before bucket 3 starts)

**4. Cursor Resume**

a. Trace what happens when `isResuming` is true:
   - Does it read `dailyEthBucketCursor` and `dailyEthWinnerCursor` from storage?
   - Does it pass these as the starting positions to `_distributeDailyEthBucket`?
   - Does it reuse the stored `dailyEthPoolBudget`?
   - Does the resumed call continue distributing from the exact saved position?

**5. Complete Reset**

a. After all buckets and all winners in a phase are processed:
   - Are ALL cursor variables reset to zero?
   - Is `dailyEthPoolBudget` zeroed?
   - If Phase 0 completes, does it transition to Phase 1 (carryover) with fresh cursor initialization?
   - After Phase 1 completes, is everything reset for the next day?

**6. Phase Transitions**

a. Trace Phase 0 (current level) -> Phase 1 (carryover) transition:
   - When Phase 0 completes: cursors reset, dailyEthPhase set to 1, new pool budget computed for carryover
   - Phase 1 executes: same distribution logic with different winners
   - When Phase 1 completes: all variables reset to 0

b. Can Phase 1 be skipped? (If carryover pool is 0, is Phase 1 skipped gracefully?)
c. Can the phase counter go beyond 1? (Is there a Phase 2? Or does it reset after 1?)

Write as Sections 1-3 of the findings document.
  </action>
  <verify>
    <automated>
      cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
      grep -rn "dailyEthBucketCursor\|dailyEthWinnerCursor\|dailyEthPhase\|dailyEthPoolBudget" contracts/ --include="*.sol" | grep -v "contracts-testnet" | wc -l
    </automated>
  </verify>
  <done>
    All cursor variable references enumerated with file:line for every read and write.
    Fresh start initialization traced with all four variables documented.
    Cursor save verified at exact (bucket, winner) position.
    Resume verified to continue from exact saved position.
    Complete reset verified after distribution completes.
    Phase 0 -> Phase 1 transition traced.
  </done>
</task>

<task type="auto">
  <name>Task 2: Analyze griefing vectors, edge cases, and unitsBudget gas mechanism; write DOS-02 verdict</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. Griefing Vector Analysis**

a. Can an external caller advance the cursor without distributing ETH?
   - handleDailyJackpot is only callable via delegatecall from advanceGame
   - advanceGame is publicly callable — but does it always trigger handleDailyJackpot?
   - If advanceGame can be called by anyone, can a griefer call it repeatedly to exhaust gas budgets?

b. Can a caller manipulate the gas budget to cause premature cursor save?
   - The `unitsBudget` is internally computed — can an external caller influence it?
   - If advanceGame is called with minimal gas, does the cursor save correctly?
   - Could a low-gas call cause a save at an incorrect position?

c. Can a caller force the cursor past unfilled buckets?
   - If a bucket has zero winners, is the cursor incremented past it correctly?
   - If all buckets have zero winners, does the distribution complete without writing corrupt state?

d. Can a caller prevent distribution by never calling advanceGame?
   - The game requires someone to call advanceGame to progress
   - If no one calls advanceGame, the distribution is delayed but not skipped
   - Once called, the cursor resumes from where it left off

**2. unitsBudget Gas Mechanism**

a. How is `unitsBudget` computed?
   - Is it a fixed constant or dynamically computed based on remaining work?
   - What is its value? (Expected: a number that ensures the function stays within gas limits)
b. How is it decremented?
   - Per winner processed? Per bucket? Per ETH transfer?
c. What happens when it reaches 0?
   - The function saves cursors and returns — does it return cleanly or revert?
   - Is the caller (advanceGame) able to detect that distribution is incomplete?
d. Is there a minimum unitsBudget that prevents any work from being done?
   - Could a griefer force unitsBudget to 0 on entry, causing an infinite loop of no-progress calls?

**3. Edge Cases**

a. Zero-budget distribution: What if `dailyEthPoolBudget` is computed as 0?
   - Does the distribution skip gracefully?
   - Are cursors still reset correctly?

b. Single-winner bucket: What if a bucket has exactly 1 winner?
   - Is the winner paid and cursor advanced correctly?

c. Maximum-winner bucket: What if a bucket has 250 winners (MAX_BUCKET_WINNERS)?
   - Is the distribution split across multiple advanceGame calls?
   - Are all 250 winners paid exactly once?

d. Day boundary: What if advanceGame is called at a new day before the previous day's distribution completes?
   - Does the previous day's distribution complete first? (resume before new day)
   - Or does the new day overwrite the cursor state? (DATA LOSS — flag as HIGH)

e. Concurrent modification: Can ticket purchases or other state changes during distribution affect the cursor or winner list?
   - If a player gets new tickets during distribution, are they included or excluded?
   - Is the winner list snapshot at distribution start?

**4. Write Complete Findings Document**

Sections:
1. Cursor Variable Inventory and Access Control
2. Cursor Lifecycle Trace (init, save, resume, reset, phase transition)
3. Griefing Vector Analysis
4. unitsBudget Gas Mechanism
5. Edge Case Analysis
6. DOS-02 Verdict: Daily ETH distribution cursor griefing resistance
7. Findings (any issues rated by severity)
  </action>
  <verify>
    <automated>
      test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md && \
      grep -c "DOS-02\|griefing\|unitsBudget\|cursor\|resume\|dailyEthBucketCursor" /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md
    </automated>
  </verify>
  <done>
    03b-05-FINDINGS-daily-eth-cursor-griefing.md exists and contains:
    - All cursor variable references enumerated (reads and writes)
    - Cursor lifecycle fully traced (init, save, resume, reset, phase transition)
    - Griefing vector analysis with concrete attack scenarios assessed
    - unitsBudget gas mechanism verified
    - Edge cases analyzed (zero budget, single winner, max winners, day boundary)
    - DOS-02 verdict with complete reasoning
    - Any findings rated by severity
    - No contract files were modified
  </done>
</task>

</tasks>

<verification>
```bash
# Verify findings document exists
test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md && echo "File exists"

# Verify DOS-02 verdict present
grep -E "DOS-02.*(PASS|FAIL|Verdict)" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md

# Verify griefing analysis present
grep -c "griefing\|griefable\|griefer\|manipulation\|advance cursor" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-05-FINDINGS-daily-eth-cursor-griefing.md

# Cross-check: confirm cursor variables searched comprehensively
cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
grep -rn "dailyEthBucketCursor\|dailyEthWinnerCursor" contracts/ --include="*.sol" | grep -v "contracts-testnet" | wc -l
```
</verification>

<success_criteria>
- 03b-05-FINDINGS-daily-eth-cursor-griefing.md exists in the phase directory
- All cursor variables enumerated with every read/write site
- Cursor lifecycle traced: initialization, save, resume, reset, phase transition
- All write sites confirmed within JackpotModule (delegatecall only)
- Griefing vectors analyzed with concrete scenarios
- unitsBudget gas mechanism verified
- Edge cases analyzed (zero budget, day boundary, max winners)
- DOS-02 verdict rendered with complete reasoning
- Any findings rated by severity
- No contract files were modified
</success_criteria>

<output>
After completion, create `.planning/phases/03b-vrf-dependent-modules/03b-05-SUMMARY.md` following the standard summary template.
</output>
