---
phase: 03b-vrf-dependent-modules
plan: 03b-06
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md
autonomous: true
requirements:
  - DOS-03

must_haves:
  truths:
    - "sampleTraitTickets (DegenerusGame:2625) is confirmed bounded to max 4 tickets per call"
    - "_randTraitTicket and _randTraitTicketWithIndices iterate exactly numWinners times (max 255 as uint8, capped at MAX_BUCKET_WINNERS=250)"
    - "MAX_BUCKET_WINNERS=250 is confirmed enforced at every call site that determines winner count"
    - "unitsBudget in _distributeDailyEthBucket caps per-call gas consumption for jackpot distribution"
    - "deityPassOwners.length is bounded by DEITY_PASS_MAX_TOTAL=24 in GameOverModule"
    - "No unbounded .push() exists in GameOverModule or JackpotModule that could grow arrays past their caps"
    - "Gas cost at maximum realistic iteration counts (250 winners * 4 buckets = 1000 iterations) is estimated and confirmed within block gas limits"
  artifacts:
    - path: ".planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md"
      provides: "Complete iteration bound analysis for trait operations, jackpot distribution, and game-over loops; gas ceiling estimates; DOS-03 verdict"
      contains: "DOS-03"
  key_links:
    - from: "contracts/DegenerusGame.sol:sampleTraitTickets"
      to: "min(len, 4)"
      via: "Bounded take parameter"
      pattern: "sampleTraitTickets"
    - from: "contracts/modules/DegenerusGameJackpotModule.sol:_distributeDailyEthBucket"
      to: "MAX_BUCKET_WINNERS"
      via: "Winner count cap"
      pattern: "MAX_BUCKET_WINNERS"
    - from: "contracts/modules/DegenerusGameGameOverModule.sol:handleGameOverDrain"
      to: "deityPassOwners.length"
      via: "Bounded by DEITY_PASS_MAX_TOTAL=24"
      pattern: "deityPassOwners"
---

<objective>
Verify that all trait-related iteration in DegenerusGame, JackpotModule, and GameOverModule is bounded, and compute gas ceilings at maximum realistic iteration counts to confirm no phase transition or jackpot distribution can exhaust the block gas limit.

Purpose: DOS-03 requires proving that trait burn ticket iteration is bounded and large trait counts cannot block phase transitions. This plan systematically enumerates every loop that iterates over trait-related data structures, confirms each has an explicit bound, and computes worst-case gas consumption to verify it stays within block limits.

Output: `03b-06-FINDINGS-trait-burn-iteration-bounds.md` containing the complete iteration bound inventory, gas ceiling estimates, and DOS-03 verdict.
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
<!-- Audit targets across three contracts -->

DegenerusGame.sol (2786 lines):
  sampleTraitTickets (line ~2625): samples max 4 tickets
  _randTraitTicket: iterates exactly numWinners times
  _randTraitTicketWithIndices: iterates exactly numWinners times

DegenerusGameJackpotModule.sol (2740 lines):
  _distributeDailyEthBucket: iterates over buckets (4) and winners per bucket (max 250)
  MAX_BUCKET_WINNERS = 250
  unitsBudget: gas guard for per-call work cap
  processTicketBatch: batched airdrop processing

DegenerusGameGameOverModule.sol (287 lines):
  deityPassOwners loop: bounded by deityPassOwners.length
  DEITY_PASS_MAX_TOTAL = 24

Known bounds from research:
  - sampleTraitTickets: max take = min(len, 4) = 4
  - _randTraitTicket: numWinners is uint8 (max 255)
  - MAX_BUCKET_WINNERS = 250: enforced at call sites
  - deityPassOwners: max 24 entries
  - unitsBudget: caps per-call gas in jackpot distribution
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Enumerate all trait-related and jackpot distribution loops; verify explicit bounds at each site</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. DegenerusGame.sol Iteration Audit**

Read the relevant sections of `contracts/DegenerusGame.sol` (around lines 2618-2663 for sampleTraitTickets).

a. `sampleTraitTickets`:
   - Locate the function. What is the iteration bound?
   - Research says `take = min(len, 4)`. Verify this exact logic.
   - What is `len`? Is it a storage array length that could be manipulated to be very large?
   - Even if len is huge, take is capped at 4. Confirm this.

b. `_randTraitTicket`:
   - Locate the function. What controls the loop count?
   - Parameter `numWinners` is uint8 (max 255). Is it further bounded by MAX_BUCKET_WINNERS=250?
   - What does each iteration do? (Expected: entropyStep + modular selection + storage read)
   - Gas per iteration estimate: ~5000-10000 gas (SLOAD + entropyStep + arithmetic)

c. `_randTraitTicketWithIndices`:
   - Same analysis as _randTraitTicket. What is the difference?
   - Same loop bound? Same gas per iteration?

d. Are there other loops in DegenerusGame.sol that iterate over trait data?
   - Grep for `for (uint` or `while` in the file. Check each loop's bound.

**2. JackpotModule Iteration Audit**

Read the relevant sections of `contracts/modules/DegenerusGameJackpotModule.sol`.

a. `_distributeDailyEthBucket`:
   - Locate the outer loop (over buckets). Bound? (Expected: 4 trait buckets)
   - Locate the inner loop (over winners per bucket). Bound? (Expected: MAX_BUCKET_WINNERS=250)
   - Total worst-case iterations: 4 * 250 = 1000. But unitsBudget may split across calls.

b. `unitsBudget` mechanism:
   - How is it initialized? (Fixed constant or dynamic?)
   - What counts as one "unit"? (One winner processed? One ETH transfer?)
   - When unitsBudget hits 0: cursor saved, function returns
   - What is the typical unitsBudget value? How many winners can be processed per call?

c. `processTicketBatch`:
   - What does this iterate over? (Batched ticket airdrop)
   - What is the batch size bound?
   - Gas per batch item?

d. Locate `MAX_BUCKET_WINNERS`:
   - Where is it defined? What is its value? (Expected: 250)
   - Grep for all reference sites. Is it enforced at every point where winner count is determined?
   - Can any code path set a winner count above MAX_BUCKET_WINNERS?

e. Are there other loops in JackpotModule?
   - Grep for `for (uint` or `while` in the file. Check each loop's bound.

**3. GameOverModule Iteration Audit**

Read `contracts/modules/DegenerusGameGameOverModule.sol` completely.

a. Deity pass refund loop:
   - Iterates `ownerCount = deityPassOwners.length` times
   - Where is deityPassOwners.push() called? (Expected: in whale module or deity pass purchase)
   - Is there a guard: `if (deityPassOwners.length >= DEITY_PASS_MAX_TOTAL) revert`?
   - Confirm DEITY_PASS_MAX_TOTAL = 24. Max iterations = 24.

b. BAF/Decimator distribution:
   - `_payGameOverBafEthOnly`: does it iterate? Over what? Bounded?
   - `_payGameOverDecimatorEthOnly`: does it iterate? Over what? Bounded?

c. Any other loops in GameOverModule?

Write as Section 1 of the findings document: "Iteration Bound Inventory".
  </action>
  <verify>
    <automated>
      cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
      grep -n "MAX_BUCKET_WINNERS\|sampleTraitTickets\|_randTraitTicket\|DEITY_PASS_MAX_TOTAL\|unitsBudget\|processTicketBatch" contracts/DegenerusGame.sol contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameGameOverModule.sol | wc -l
    </automated>
  </verify>
  <done>
    Every loop in the three target contracts is enumerated with its explicit bound.
    sampleTraitTickets confirmed bounded to 4.
    MAX_BUCKET_WINNERS=250 confirmed at all enforcement sites.
    unitsBudget mechanism documented.
    deityPassOwners confirmed bounded at 24.
    processTicketBatch bound documented.
    No unbounded loop found (or flagged as finding).
  </done>
</task>

<task type="auto">
  <name>Task 2: Compute gas ceilings at maximum iteration counts; verify block gas limit safety; write DOS-03 verdict</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. Gas Ceiling Estimates**

For each bounded loop identified in Task 1, estimate the worst-case gas:

a. `sampleTraitTickets` (4 iterations):
   - Per iteration: SLOAD (2100 cold) + entropy computation + modular arithmetic
   - Estimate: ~4 * 5000 = ~20,000 gas
   - This is called within view functions — gas limit is less critical (no state change)
   - BUT: if called within a state-changing function, include in total

b. `_randTraitTicket` / `_randTraitTicketWithIndices` (max 250 iterations):
   - Per iteration: entropyStep (minimal CPU) + SLOAD for trait data + modular selection
   - Estimate: ~250 * 8000 = ~2,000,000 gas per bucket
   - 4 buckets: ~8,000,000 gas total if all in one call
   - But unitsBudget prevents all 4 buckets in one call

c. `_distributeDailyEthBucket` (max 4 * 250 = 1000 iterations):
   - Per iteration: winner selection + ETH credit (SSTORE ~20,000 for zero-to-nonzero, ~5,000 for update)
   - Worst case per winner: ~25,000 gas (SLOAD + SSTORE + arithmetic)
   - 1000 winners: ~25,000,000 gas — exceeds block gas limit (30M)
   - BUT: unitsBudget splits across calls. What is the per-call cap?
   - If unitsBudget = 100: ~100 * 25,000 = 2,500,000 gas per call — safe

d. `processTicketBatch`:
   - Per batch item: storage writes for ticket allocation
   - What is the batch size? Gas per item?
   - Total gas estimate

e. GameOver refund loop (max 24 iterations):
   - Per iteration: 2 SLOAD + 1 SSTORE = ~25,000 gas
   - 24 iterations: ~600,000 gas — safe

**2. Block Gas Limit Analysis**

a. Current Ethereum block gas limit: ~30,000,000 gas
b. For each loop, is the worst-case gas:
   - < 1M: Trivially safe
   - 1M - 10M: Safe but notable
   - 10M - 30M: Risk zone — requires gas budgeting
   - > 30M: UNSAFE — must be split across transactions

c. Verify the unitsBudget mechanism prevents any single advanceGame call from exceeding ~10M gas (leaving headroom for the rest of advanceGame logic).

**3. Unbounded Push Analysis**

a. Search for `.push(` in all three contracts:
   ```
   grep -n "\.push(" contracts/DegenerusGame.sol contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameGameOverModule.sol
   ```
b. For each push: what array is being pushed to? Is there a length guard?
c. Specifically verify `deityPassOwners.push()`:
   - Where is it called? (Expected: in deity pass purchase logic, possibly in WhaleModule)
   - Is it guarded by `deityPassOwners.length < DEITY_PASS_MAX_TOTAL`?
   - Could a bypass exist? (e.g., calling from an unexpected module)

**4. Worst-Case Scenario**

Construct the worst-case gas scenario for a single advanceGame call:
- Daily jackpot distribution with maximum winners per bucket
- Processing ticket batch
- Any other loops triggered during advanceGame

Total gas = sum of all loops that fire in a single call. Is this < 30M? If unitsBudget is working correctly, it should cap the total.

**5. Write Complete Findings Document**

Sections:
1. Iteration Bound Inventory (from Task 1)
   - Table: Function | Location | Bound | Max Iterations | Gas/Iteration | Max Gas
2. Gas Ceiling Estimates (from this task)
3. Block Gas Limit Safety Analysis
4. unitsBudget Mechanism Verification
5. Unbounded Push Analysis
6. Worst-Case Scenario
7. DOS-03 Verdict: Trait burn iteration bound safety
8. Findings (any issues rated by severity)
  </action>
  <verify>
    <automated>
      test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md && \
      grep -c "DOS-03\|gas.*limit\|MAX_BUCKET_WINNERS\|unitsBudget\|block gas\|30.*000.*000\|iteration" /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md
    </automated>
  </verify>
  <done>
    03b-06-FINDINGS-trait-burn-iteration-bounds.md exists and contains:
    - Iteration bound inventory table with all loops, bounds, and gas estimates
    - Gas ceiling estimates at maximum iteration counts
    - Block gas limit safety analysis
    - unitsBudget mechanism verified
    - Unbounded push analysis completed
    - Worst-case scenario gas estimate for single advanceGame call
    - DOS-03 verdict with complete reasoning
    - Any findings rated by severity
    - No contract files were modified
  </done>
</task>

</tasks>

<verification>
```bash
# Verify findings document exists
test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md && echo "File exists"

# Verify DOS-03 verdict present
grep -E "DOS-03.*(PASS|FAIL|Verdict)" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md

# Verify gas analysis present
grep -c "gas\|block.*limit\|iteration\|bounded\|MAX_BUCKET_WINNERS" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-06-FINDINGS-trait-burn-iteration-bounds.md

# Cross-check: search for any .push() in target contracts
cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
grep -rn "\.push(" contracts/DegenerusGame.sol contracts/modules/DegenerusGameJackpotModule.sol contracts/modules/DegenerusGameGameOverModule.sol | wc -l
```
</verification>

<success_criteria>
- 03b-06-FINDINGS-trait-burn-iteration-bounds.md exists in the phase directory
- sampleTraitTickets confirmed bounded to max 4
- MAX_BUCKET_WINNERS=250 confirmed enforced at every call site
- unitsBudget gas mechanism verified
- deityPassOwners confirmed bounded at 24
- No unbounded .push() found (or flagged as finding)
- Gas ceiling estimates computed for all bounded loops
- Worst-case single-call gas confirmed within block gas limit
- DOS-03 verdict rendered with complete reasoning
- Any findings rated by severity
- No contract files were modified
</success_criteria>

<output>
After completion, create `.planning/phases/03b-vrf-dependent-modules/03b-06-SUMMARY.md` following the standard summary template.
</output>
