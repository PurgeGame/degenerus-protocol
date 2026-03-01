---
phase: 03c-supporting-mechanics-modules
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03c-supporting-mechanics-modules/03c-02-FINDINGS-pricing-formula-arithmetic.md
autonomous: true
requirements: [MATH-07]

must_haves:
  truths:
    - "Whale bundle unitPrice * quantity overflow analysis completed for max values (4 ETH * 100)"
    - "Deity pass T(n) pricing verified at n=0, n=31 (max), with overflow analysis"
    - "Lazy pass _lazyPassCost sum verified at levels 0, 1, 2, 3, 10, 50, 100 with concrete arithmetic"
    - "Lazy pass flat 0.24 ETH balance = totalPrice - baseCost verified non-negative for levels 0-2"
    - "Boon discount BPS bounded: all issuance sites verified to prevent discountBps >= 10000"
    - "All conditional pricing branches mapped to a decision tree"
  artifacts:
    - path: ".planning/phases/03c-supporting-mechanics-modules/03c-02-FINDINGS-pricing-formula-arithmetic.md"
      provides: "Arithmetic verification of all whale/lazy/deity pricing formulas"
      min_lines: 80
  key_links:
    - from: "contracts/modules/DegenerusGameWhaleModule.sol (_lazyPassCost)"
      to: "contracts/libraries/PriceLookupLib.sol (priceForLevel)"
      via: "sum of 10 level prices"
      pattern: "_lazyPassCost.*priceForLevel"
    - from: "contracts/modules/DegenerusGameWhaleModule.sol (line 442)"
      to: "DEITY_PASS_BASE"
      via: "basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2"
      pattern: "DEITY_PASS_BASE.*k.*k.*1"
---

<objective>
Verify whale bundle, lazy pass, and deity pass pricing formulas arithmetically. Trace all conditional pricing branches and compute concrete values at boundary levels to confirm no overflow, underflow, or zero-price paths exist.

Purpose: Pricing formulas involve level-dependent branching and BPS discount application. Arithmetic edge cases (underflow in lazy pass balance, overflow in deity pass T(n), zero-price from extreme boon discounts) must be confirmed safe.
Output: FINDINGS document with arithmetic proofs per formula
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
@contracts/libraries/PriceLookupLib.sol
</context>

<tasks>

<task type="auto">
  <name>Task 1: Verify whale bundle and deity pass pricing arithmetic at boundary values</name>
  <files>.planning/phases/03c-supporting-mechanics-modules/03c-02-FINDINGS-pricing-formula-arithmetic.md</files>
  <action>
READ-ONLY AUDIT. Do not modify any contract files.

**Section A: Whale Bundle Pricing**

1. Compute unitPrice for each pricing branch:
   - Boon with discountBps=1000 (default): (4e18 * 9000) / 10000 = 3.6 ETH
   - Boon with discountBps=2500: (4e18 * 7500) / 10000 = 3.0 ETH
   - Boon with discountBps=5000: (4e18 * 5000) / 10000 = 2.0 ETH
   - Early (passLevel<=4): 2.4 ETH (constant)
   - Standard: 4 ETH (constant)

2. Overflow check on totalPrice = unitPrice * quantity:
   - Max: 4e18 * 100 = 4e20 (400 ETH). uint256 max = ~1.15e77. SAFE.
   - Verify no intermediate multiplication can overflow.

3. Draw a decision tree mapping (hasValidBoon, passLevel, discountBps) to unitPrice. Document every leaf.

**Section B: Deity Pass Pricing**

1. Verify T(n) formula: `basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2`
   - At k=0: 24e18 + 0 = 24 ETH
   - At k=1: 24e18 + 1e18 = 25 ETH
   - At k=31 (max, 32 symbols): 24e18 + (31 * 32 * 1e18) / 2 = 24e18 + 496e18 = 520 ETH
   - Overflow check: 31 * 32 = 992. 992 * 1e18 = 9.92e20. Well within uint256.

2. Deity boon discount tiers: verify the three tiers (1=10%, 2=25%, 3=50%) with concrete arithmetic:
   - Tier 1: (520e18 * 9000) / 10000 = 468 ETH (at max k=31)
   - Tier 2: (520e18 * 7500) / 10000 = 390 ETH
   - Tier 3: (520e18 * 5000) / 10000 = 260 ETH
   - All positive, no underflow risk.

3. Verify boonTier range is bounded. In WhaleModule._purchaseDeityPass, boonTier comes from `deityPassBoonTier[buyer]` (uint8). Discount calculation: `boonTier == 3 ? 5000 : (boonTier == 2 ? 2500 : 1000)`. Any boonTier value not 2 or 3 maps to 1000 (10%). Verify no boonTier value can produce discountBps >= 10000.

**Section C: Lazy Pass Pricing**

1. Compute _lazyPassCost(startLevel) for representative levels using PriceLookupLib.priceForLevel:
   - Level 0 (startLevel=1): levels 1-4 at 0.01 + levels 5-9 at 0.02 + level 10 at 0.04 = 4*0.01 + 5*0.02 + 1*0.04 = 0.04 + 0.10 + 0.04 = 0.18 ETH
   - Level 1 (startLevel=2): levels 2-4 at 0.01 + levels 5-9 at 0.02 + levels 10-11 at 0.04 = 3*0.01 + 5*0.02 + 2*0.04 = 0.03 + 0.10 + 0.08 = 0.21 ETH
   - Level 2 (startLevel=3): levels 3-4 at 0.01 + levels 5-9 at 0.02 + levels 10-12 at 0.04 = 2*0.01 + 5*0.02 + 3*0.04 = 0.02 + 0.10 + 0.12 = 0.24 ETH
   - Level 3 (startLevel=4): levels 4 at 0.01 + levels 5-9 at 0.02 + levels 10-13 at 0.04 = 1*0.01 + 5*0.02 + 4*0.04 = 0.01 + 0.10 + 0.16 = 0.27 ETH
   - Level 9 (startLevel=10): levels 10-19 at 0.04 = 10*0.04 = 0.40 ETH
   - Level 99 (startLevel=100): level 100 at 0.24 + levels 101-109 at 0.04 = 0.24 + 9*0.04 = 0.60 ETH

2. Verify flat 0.24 ETH path (levels 0-2 without boon):
   - Level 0: balance = 0.24 - 0.18 = 0.06 ETH. bonusTickets = (0.06e18 * 4) / 0.01e18 = 24.
   - Level 1: balance = 0.24 - 0.21 = 0.03 ETH. bonusTickets = (0.03e18 * 4) / 0.01e18 = 12.
   - Level 2: balance = 0.24 - 0.24 = 0 ETH. bonusTickets = 0 (branch not entered).
   - All non-negative. No underflow.

3. Verify lazy pass boon discount: boonDiscountBps comes from `lazyPassBoonDiscountBps[buyer]` (uint16). Default fallback to 1000 if zero. Trace all issuance sites for lazyPassBoonDiscountBps to confirm values are bounded below 10000 (search BoonModule and LootboxModule for writes to this storage variable).

4. Verify bonusTickets calculation cannot overflow uint32: max balance = 0.06 ETH, ticketPrice min = 0.01 ETH. bonusTickets = (0.06e18 * 4) / 0.01e18 = 24. Well within uint32.

**Section D: Boon Discount BPS Safety**

Search ALL writes to whaleBoonDiscountBps, lazyPassBoonDiscountBps, and deityPassBoonTier across the entire codebase. For each write site, document the value written and verify it cannot reach or exceed 10000 BPS (which would make the discount formula `(price * (10_000 - discountBps)) / 10_000` underflow or produce zero).

Document all findings with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03c-supporting-mechanics-modules/03c-02-FINDINGS-pricing-formula-arithmetic.md && grep -c "Section" .planning/phases/03c-supporting-mechanics-modules/03c-02-FINDINGS-pricing-formula-arithmetic.md</automated>
  </verify>
  <done>
    - All whale bundle pricing branches computed with concrete ETH values
    - Deity pass T(n) verified at k=0 and k=31 with overflow analysis
    - Lazy pass baseCost computed at levels 0, 1, 2, 3, 9, 99
    - Flat 0.24 ETH balance subtraction confirmed non-negative at levels 0-2
    - All boon discount BPS issuance sites verified bounded below 10000
    - FINDINGS document exists with arithmetic proofs
  </done>
</task>

</tasks>

<verification>
- FINDINGS document contains concrete arithmetic for all three purchase types
- Every formula boundary value is computed with exact wei amounts
- No contract files were modified
</verification>

<success_criteria>
- Complete arithmetic verification for whale, lazy, and deity pricing
- Lazy pass balance subtraction proven safe at all eligible levels
- Boon discount BPS bounded at all issuance sites
- All overflow/underflow risks documented with severity
</success_criteria>

<output>
After completion, create `.planning/phases/03c-supporting-mechanics-modules/03c-02-SUMMARY.md`
</output>
