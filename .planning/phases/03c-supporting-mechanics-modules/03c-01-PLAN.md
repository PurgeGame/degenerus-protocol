---
phase: 03c-supporting-mechanics-modules
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03c-supporting-mechanics-modules/03c-01-FINDINGS-whale-pricing-enforcement.md
autonomous: true
requirements: [MATH-07, MATH-08]

must_haves:
  truths:
    - "Every external path into _purchaseWhaleBundle is traced from DegenerusGame entry point through delegatecall"
    - "Level eligibility (levels 0-3, x49/x99, or boon) enforcement is confirmed present or documented as a finding"
    - "All three pricing branches (boon, early, standard) are verified to produce correct unitPrice values"
    - "msg.value == totalPrice is confirmed enforced on every path through _purchaseWhaleBundle"
    - "Boon consumption (delete after use) is confirmed atomic with pricing"
    - "Lazy pass level eligibility (levels 0-3, x9, or boon) check at line 335 is verified correct"
    - "Lazy pass flat 0.24 ETH path cannot underflow at any eligible level"
    - "Deity pass pricing T(n) formula is verified against NatSpec"
  artifacts:
    - path: ".planning/phases/03c-supporting-mechanics-modules/03c-01-FINDINGS-whale-pricing-enforcement.md"
      provides: "Complete pricing enforcement audit for WhaleModule"
      min_lines: 100
  key_links:
    - from: "contracts/DegenerusGame.sol (line 648)"
      to: "contracts/modules/DegenerusGameWhaleModule.sol (_purchaseWhaleBundle)"
      via: "delegatecall"
      pattern: "GAME_WHALE_MODULE.*delegatecall"
    - from: "contracts/modules/DegenerusGameWhaleModule.sol (line 242)"
      to: "msg.value"
      via: "msg.value != totalPrice revert"
      pattern: "msg\\.value != totalPrice.*revert"
---

<objective>
Audit WhaleModule pricing enforcement across all three purchase functions: whale bundle, lazy pass, and deity pass. Trace every external entry point from DegenerusGame through delegatecall to verify level eligibility is enforced, pricing branches are exhaustive, msg.value checks are present on all paths, and boon discounts are safely bounded and atomically consumed.

Purpose: Research finding #4 flagged that _purchaseWhaleBundle may not enforce level eligibility (levels 0-3, x49/x99, or boon). The NatSpec documents this restriction but the code may allow purchases at any level for 4 ETH. This plan confirms or refutes this as a finding.
Output: FINDINGS document with per-function pricing enforcement trace
</objective>

<execution_context>
@/home/zak/.claude/get-shit-done/workflows/execute-plan.md
@/home/zak/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/03c-supporting-mechanics-modules/3c-RESEARCH.md

Source files (READ-ONLY -- do NOT modify):
@contracts/modules/DegenerusGameWhaleModule.sol
@contracts/DegenerusGame.sol (lines 638-757 for dispatcher)
@contracts/modules/DegenerusGameBoonModule.sol
</context>

<tasks>

<task type="auto">
  <name>Task 1: Trace all three WhaleModule purchase paths from external entry to pricing enforcement</name>
  <files>.planning/phases/03c-supporting-mechanics-modules/03c-01-FINDINGS-whale-pricing-enforcement.md</files>
  <action>
READ-ONLY AUDIT. Do not modify any contract files.

For each of the three purchase functions (purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass):

1. **Trace entry point**: Start from DegenerusGame.sol external function, through _resolvePlayer, through delegatecall to WhaleModule. Document whether any access control or eligibility check exists in the dispatcher BEFORE delegation.

2. **Level eligibility check**:
   - purchaseWhaleBundle: NatSpec says "Available at levels 0-3, x49/x99, or any level with a valid whale boon". Search the function body for any revert/require that enforces this. The pricing code has `if (hasValidBoon)` then `else if (passLevel <= 4)` then `else unitPrice = WHALE_BUNDLE_STANDARD_PRICE`. At level 5 without boon, the code falls through to 4 ETH standard price with NO revert. Confirm whether this is intentional (any level allowed at full price) or a missing guard (should revert). Cross-reference with the existing test file test/edge/WhaleBundle.test.js to see if tests cover level 5+ purchases.
   - purchaseLazyPass: Line 335 checks `if (currentLevel > 3 && currentLevel % 10 != 9 && !hasValidBoon) revert E()`. Verify this correctly gates to levels 0-3 and x9 (9, 19, 29...).
   - purchaseDeityPass: No level restriction documented. Confirm it is available at any level.

3. **Pricing branch exhaustiveness**:
   - Whale bundle: Three branches (boon discount, early 2.4 ETH, standard 4 ETH). Verify no fourth branch or fallthrough exists. Verify `unitPrice * quantity` cannot overflow (max 4 ETH * 100 = 400 ETH, well within uint256).
   - Lazy pass: Two paths (flat 0.24 ETH for levels 0-2 without boon, baseCost otherwise). Verify `totalPrice - baseCost` cannot underflow for levels 0-2 by computing baseCost at each eligible level.
   - Deity pass: Single path with optional boon discount. Verify `basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2` at k=0 gives 24 ETH, at k=31 gives 520 ETH.

4. **msg.value enforcement**: Confirm `if (msg.value != totalPrice) revert E()` exists in each function and is reached on every path.

5. **Boon consumption atomicity**: For each purchase function with boon support, verify that boon state (day, discount BPS, tier, timestamp) is deleted/zeroed AFTER pricing but before any external calls. Verify no path can consume a boon without applying the discount, or apply the discount without consuming the boon.

6. **Quantity bounds**: Whale bundle checks `quantity == 0 || quantity > 100`. Lazy pass has no quantity parameter (fixed at 1). Deity pass has no quantity (fixed at 1 per symbol).

Document findings with severity ratings:
- CRITICAL: Allows purchase below intended price
- HIGH: Missing access control on intended restriction
- MEDIUM: Edge case in pricing arithmetic
- LOW: Documentation inconsistency
- INFORMATIONAL: Code quality observations

For the whale bundle level eligibility issue specifically: if no guard exists, rate this as either HIGH (if x49/x99 restriction is genuine and missing) or INFORMATIONAL (if any-level purchase at 4 ETH is intentional design). Cite the NatSpec vs code discrepancy either way.
  </action>
  <verify>
    <automated>test -f .planning/phases/03c-supporting-mechanics-modules/03c-01-FINDINGS-whale-pricing-enforcement.md && grep -c "## Finding" .planning/phases/03c-supporting-mechanics-modules/03c-01-FINDINGS-whale-pricing-enforcement.md</automated>
  </verify>
  <done>
    - All three purchase functions have entry-to-pricing traces documented
    - Level eligibility enforcement is confirmed present (with code reference) or documented as a finding with severity
    - All pricing branches verified with concrete arithmetic
    - msg.value enforcement confirmed on every path
    - Boon consumption atomicity verified
    - FINDINGS document exists with severity-rated findings
  </done>
</task>

</tasks>

<verification>
- FINDINGS document exists at expected path
- Every purchase function in WhaleModule has a corresponding trace
- The whale bundle level eligibility question from Research Finding #4 is definitively answered
- No contract files were modified
</verification>

<success_criteria>
- Complete pricing enforcement trace for all 3 purchase functions
- Whale bundle level eligibility finding documented with severity and code references
- All pricing arithmetic verified (no overflow, no underflow, no underpricing)
- msg.value == totalPrice confirmed on every path
</success_criteria>

<output>
After completion, create `.planning/phases/03c-supporting-mechanics-modules/03c-01-SUMMARY.md`
</output>
