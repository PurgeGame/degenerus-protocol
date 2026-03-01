---
phase: 03a-core-eth-flow-modules
plan: 04
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md
autonomous: true
requirements: [MATH-01, MATH-04]

must_haves:
  truths:
    - "PriceLookupLib prices are monotonically increasing within each 100-level cycle"
    - "The saw-tooth drop from 0.24 ETH (level x00) to 0.04 ETH (level x01) is documented as by-design"
    - "PriceLookupLib cannot overflow — all return values are fixed constants, input is uint24"
    - "Lazy pass pricing (sum of 10 consecutive level prices) produces correct totals at representative levels"
    - "No downstream code assumes strict global monotonicity across all levels"
  artifacts:
    - path: ".planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md"
      provides: "PriceLookupLib audit findings document"
      contains: "## Findings"
  key_links:
    - from: "contracts/libraries/PriceLookupLib.sol"
      to: "contracts/modules/DegenerusGameMintModule.sol"
      via: "priceForLevel() called in _callTicketPurchase cost formula"
      pattern: "priceForLevel|PriceLookupLib"
    - from: "contracts/libraries/PriceLookupLib.sol"
      to: "contracts/modules/DegenerusGameWhaleModule.sol"
      via: "priceForLevel() called in _lazyPassCost() summation loop"
      pattern: "_lazyPassCost|priceForLevel"
---

<objective>
Verify PriceLookupLib ticket price escalation for intra-cycle monotonicity, boundary correctness, overflow safety, and document the intentional saw-tooth pattern. Verify lazy pass pricing (sum-of-10-level-prices) correctness.

Purpose: PriceLookupLib determines the cost of every ticket in the game. Incorrect pricing at tier boundaries, unexpected non-monotonicity, or overflow would directly affect ETH inflow accounting and player fairness.
Output: 03a-04-FINDINGS.md with complete price tier verification and lazy pass summation checks.
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
@contracts/libraries/PriceLookupLib.sol (47 lines — complete library)
@contracts/modules/DegenerusGameWhaleModule.sol (line 584: _lazyPassCost summation loop)
@contracts/modules/DegenerusGameMintModule.sol (line 810: cost formula using priceForLevel)

<interfaces>
<!-- Complete PriceLookupLib source (47 lines) -->

PriceLookupLib.priceForLevel(uint24 targetLevel) -> uint256:
  Level 0-4:   0.01 ether
  Level 5-9:   0.02 ether
  Level 10-29: 0.04 ether
  Level 30-59: 0.08 ether
  Level 60-89: 0.12 ether
  Level 90-99: 0.16 ether
  Level x00 (100+): 0.24 ether (milestone)
  Level x01-x29: 0.04 ether
  Level x30-x59: 0.08 ether
  Level x60-x89: 0.12 ether
  Level x90-x99: 0.16 ether

WhaleModule._lazyPassCost(uint24 startLevel) -> uint256:
  Sums priceForLevel(startLevel + i) for i = 0..9
  Fixed loop of 10 iterations
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Verify PriceLookupLib monotonicity, boundaries, and overflow safety</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Complete tier boundary verification (MATH-01):**
   Read PriceLookupLib.sol (47 lines). Verify every tier boundary transition:

   Build a complete price table for representative levels:
   | Level | Price (ETH) | Tier | Transition |
   |-------|-------------|------|------------|
   | 0     | 0.01        | Intro low | - |
   | 4     | 0.01        | Intro low | last in tier |
   | 5     | 0.02        | Intro high | boundary: 0.01 -> 0.02 (increasing) |
   | 9     | 0.02        | Intro high | last in tier |
   | 10    | 0.04        | Cycle early | boundary: 0.02 -> 0.04 (increasing) |
   | 29    | 0.04        | Cycle early | last in tier |
   | 30    | 0.08        | Cycle mid | boundary: 0.04 -> 0.08 (increasing) |
   | 59    | 0.08        | Cycle mid | last in tier |
   | 60    | 0.12        | Cycle late | boundary: 0.08 -> 0.12 (increasing) |
   | 89    | 0.12        | Cycle late | last in tier |
   | 90    | 0.16        | Cycle final | boundary: 0.12 -> 0.16 (increasing) |
   | 99    | 0.16        | Cycle final | last in tier |
   | 100   | 0.24        | Milestone | boundary: 0.16 -> 0.24 (increasing) |
   | 101   | 0.04        | Cycle early | SAW-TOOTH: 0.24 -> 0.04 (decreasing!) |
   | 129   | 0.04        | Cycle early | - |
   | 130   | 0.08        | Cycle mid | boundary: 0.04 -> 0.08 (increasing) |
   | 199   | 0.16        | Cycle final | - |
   | 200   | 0.24        | Milestone | boundary: 0.16 -> 0.24 (increasing) |
   | 201   | 0.04        | Cycle early | SAW-TOOTH: 0.24 -> 0.04 (decreasing!) |

   Verify: within each 100-level cycle (x00-x99), prices are strictly non-decreasing. The ONLY decrease is at x00->x01 boundary between cycles.

2. **Overflow analysis:**
   - Input: uint24 (max 16,777,215)
   - All return values are fixed constants (0.01 to 0.24 ether) — no arithmetic, no multiplication
   - The `targetLevel % 100` operation: uint24 % 100 cannot overflow
   - Conclusion: PriceLookupLib CANNOT overflow. Document as PASS.

3. **Downstream monotonicity assumption search:**
   - Grep the codebase for any code that assumes priceForLevel(n+1) >= priceForLevel(n) for all n
   - Search patterns: `priceForLevel.*\+.*1`, comparison of consecutive prices, sorting by price
   - If any code assumes global monotonicity, document as a finding (severity depends on impact)
   - Check MintModule cost formula: does it use absolute price or relative price difference?

4. **Edge case: uint24 max level:**
   - priceForLevel(16777215): 16777215 % 100 = 15, which is < 30, returns 0.04 ether
   - Verify this is correct behavior (no special handling needed for extreme levels)

Write findings to 03a-04-FINDINGS.md.
  </action>
  <verify>
    <automated>test -f .planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md && grep -c "0.01\|0.02\|0.04\|0.08\|0.12\|0.16\|0.24" .planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md | xargs test 5 -le</automated>
  </verify>
  <done>Complete price tier boundary table produced. Intra-cycle monotonicity confirmed or finding raised. Saw-tooth at x00->x01 documented as by-design. No overflow possible (pure constants). Downstream monotonicity assumptions searched.</done>
</task>

<task type="auto">
  <name>Task 2: Verify lazy pass pricing summation (MATH-04)</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **_lazyPassCost formula correctness (MATH-04):**
   - Read WhaleModule._lazyPassCost() (around line 584)
   - Verify: sums priceForLevel(startLevel + i) for i = 0 to 9
   - Verify loop is exactly 10 iterations (fixed, not variable)
   - Verify no overflow: max sum = 10 * 0.24 ether = 2.4 ether, well within uint256

2. **Compute reference lazy pass prices at representative levels:**
   Using the verified PriceLookupLib tier table, compute expected sums:

   | Start Level | Levels Summed | Individual Prices | Total |
   |-------------|---------------|-------------------|-------|
   | 0 (intro) | 0-9 | 5 * 0.01 + 5 * 0.02 | 0.15 ETH |
   | 3 (level 3+) | 3-12 | 2*0.01 + 5*0.02 + 3*0.04 | 0.24 ETH |
   | 10 | 10-19 | 10 * 0.04 | 0.40 ETH |
   | 25 | 25-34 | 5*0.04 + 5*0.08 | 0.60 ETH |
   | 55 | 55-64 | 5*0.08 + 5*0.12 | 1.00 ETH |
   | 90 | 90-99 | 10 * 0.16 | 1.60 ETH |
   | 95 | 95-104 | 5*0.16 + 1*0.24 + 4*0.04 | 1.20 ETH |
   | 96 | 96-105 | 4*0.16 + 1*0.24 + 5*0.04 | 1.08 ETH |
   | 100 | 100-109 | 1*0.24 + 9*0.04 | 0.60 ETH |

   Note: lazy pass spanning the saw-tooth boundary (e.g., start=95) gives a LOWER total than start=90 because it includes post-milestone 0.04 ETH levels. This is expected behavior from the saw-tooth pattern.

3. **Boundary interaction with whale bundle:**
   - Read how _lazyPassCost is called in _purchaseLazyPass
   - At level 3+, verify startLevel is the CURRENT game level (not level+1 or similar offset)
   - Verify the caller uses the returned cost correctly for msg.value comparison
   - Document whether the saw-tooth effect at level boundaries is expected or creates a pricing anomaly

4. **Where lazy pass pricing gates exist (levels 0-2 vs 3+):**
   - Read WhaleModule lazy pass entry: levels 0-2 use flat 0.24 ETH pricing
   - Level 3+ uses _lazyPassCost() summation
   - Verify the level gate condition is correct (no off-by-one)
   - Verify flat pricing at levels 0-2 matches the sum (5*0.01 + 5*0.02 = 0.15 ETH is LESS than 0.24 ETH flat — intentional premium for early lazy passes)

Append findings to 03a-04-FINDINGS.md. Include summary table mapping MATH-01 and MATH-04 to verdicts.
  </action>
  <verify>
    <automated>grep -c "lazyPass\|_lazyPassCost\|MATH-04" .planning/phases/03a-core-eth-flow-modules/03a-04-FINDINGS.md | xargs test 2 -le</automated>
  </verify>
  <done>Lazy pass summation formula verified with reference prices at representative levels. Saw-tooth boundary interaction documented. Level gate (0-2 flat vs 3+ sum) verified. MATH-01 and MATH-04 mapped to verdicts in summary table.</done>
</task>

</tasks>

<verification>
- 03a-04-FINDINGS.md exists with severity-rated findings
- Complete price tier boundary table with all transitions
- Intra-cycle monotonicity confirmed
- Saw-tooth at x00->x01 explicitly documented as by-design
- Overflow analysis documents impossibility (pure constants)
- Lazy pass summation verified at representative levels with arithmetic
- MATH-01 and MATH-04 mapped to verdicts
</verification>

<success_criteria>
- PriceLookupLib intra-cycle monotonicity confirmed with boundary table
- Saw-tooth pattern documented as intentional game design
- No overflow possible (verified — pure constant returns)
- Lazy pass pricing at 8+ representative levels computed and verified
- Saw-tooth boundary interaction on lazy pass pricing documented
- Both MATH-01 and MATH-04 have clear verdicts
</success_criteria>

<output>
After completion, create `.planning/phases/03a-core-eth-flow-modules/03a-04-SUMMARY.md`
</output>
