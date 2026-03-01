---
phase: 03a-core-eth-flow-modules
plan: 05
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md
autonomous: true
requirements: [MATH-02]

must_haves:
  truths:
    - "Deity pass T(n) = DEITY_PASS_BASE + k*(k+1)*1 ether/2 cannot overflow at k=31 (actual max), k=100, or k=1000"
    - "The symbolId < 32 bound in WhaleModule enforces k <= 31 as the actual maximum deity pass count"
    - "Arithmetic verification shows exact ETH values at k=0, k=1, k=10, k=31, k=100, k=1000"
    - "The unchecked or checked context of the T(n) multiplication is documented"
  artifacts:
    - path: ".planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md"
      provides: "Deity pass T(n) audit findings document"
      contains: "## Findings"
  key_links:
    - from: "contracts/modules/DegenerusGameWhaleModule.sol"
      to: "contracts/storage/DegenerusGameStorage.sol"
      via: "deityPassOwners.length determines k"
      pattern: "deityPassOwners"
---

<objective>
Verify deity pass triangular pricing formula T(n) = 24 + n*(n+1)/2 ETH at n=100 and n=1000 for overflow safety, and verify the actual k bound (symbolId < 32) that limits pass count.

Purpose: Deity passes are the highest-value single purchase in the protocol (up to 520 ETH at k=31). Overflow in the pricing formula would allow purchasing at an incorrect price, directly affecting ETH accounting.
Output: 03a-05-FINDINGS.md with complete arithmetic verification and bound analysis.
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
@contracts/modules/DegenerusGameWhaleModule.sol (lines 436-511: _purchaseDeityPass)
@contracts/storage/DegenerusGameStorage.sol (deityPassOwners array)

<interfaces>
<!-- Deity pass formula from WhaleModule -->

WhaleModule._purchaseDeityPass (lines 441-442):
  uint256 k = deityPassOwners.length;
  uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
  // DEITY_PASS_BASE = 24 ether

  symbolId < 32 check (line ~440): bounds k to max 31

Key values:
  k=0:  24 + 0 = 24 ETH
  k=1:  24 + 1 = 25 ETH
  k=10: 24 + 55 = 79 ETH
  k=31: 24 + 496 = 520 ETH (actual max)
  k=100: 24 + 5050 = 5074 ETH (theoretical)
  k=1000: 24 + 500500 = 500524 ETH (theoretical)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Verify deity pass T(n) formula arithmetic and overflow safety</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Read the exact formula implementation:**
   - Read WhaleModule._purchaseDeityPass() (lines 436-511)
   - Document the exact Solidity expression: `DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2`
   - Note whether the multiplication is in a checked or unchecked block
   - Document DEITY_PASS_BASE value (24 ether = 24000000000000000000)

2. **k bound verification:**
   - Read the `symbolId < 32` check (around line 440)
   - Verify: deityPassOwners is an array, k = deityPassOwners.length
   - Confirm: when k reaches 32, the symbolId check prevents further purchases. This bounds k to [0, 31].
   - Verify the revert condition: what error fires when symbolId >= 32?
   - Document: the requirement asks about n=100 and n=1000, but actual max k=31. Both must be verified.

3. **Arithmetic verification at each k value:**
   Compute k * (k + 1) * 1e18 / 2 exactly for each requested k:

   | k | k*(k+1) | k*(k+1)*1e18 | /2 | +24e18 | Total ETH |
   |---|---------|--------------|-----|--------|-----------|
   | 0 | 0 | 0 | 0 | 24e18 | 24 |
   | 1 | 2 | 2e18 | 1e18 | 25e18 | 25 |
   | 10 | 110 | 110e18 | 55e18 | 79e18 | 79 |
   | 31 | 992 | 992e18 | 496e18 | 520e18 | 520 |
   | 100 | 10100 | 10100e18 | 5050e18 | 5074e18 | 5074 |
   | 1000 | 1001000 | 1001000e18 | 500500e18 | 500524e18 | 500524 |

   All intermediate values:
   - Max intermediate product at k=1000: 1001000 * 1e18 = 1.001e24
   - uint256 max: ~1.16e77
   - Headroom: 1.16e77 / 1.001e24 = ~1.16e53 orders of magnitude
   - Conclusion: overflow is impossible even at k=1000

4. **Division correctness:**
   - k * (k + 1) is always even (product of two consecutive integers)
   - Therefore (k * (k + 1) * 1 ether) / 2 produces an exact result (no rounding)
   - Document this as a mathematical property, not a code assumption

5. **msg.value comparison:**
   - After computing basePrice, verify how it is compared against msg.value
   - Verify: msg.value < basePrice reverts (underpayment protection)
   - Verify: what happens with overpayment? Is excess refunded or kept?

Write findings to 03a-05-FINDINGS.md with MATH-02 verdict.
  </action>
  <verify>
    <automated>test -f .planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md && grep -c "k=100\|k=1000\|overflow\|MATH-02" .planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md | xargs test 3 -le</automated>
  </verify>
  <done>T(n) formula verified at k=0, 1, 10, 31, 100, 1000 with exact arithmetic. Overflow impossibility proven with uint256 headroom analysis. k bound (symbolId < 32) confirmed. Division exactness documented. MATH-02 verdict assigned.</done>
</task>

<task type="auto">
  <name>Task 2: Verify deity pass purchase flow end-to-end</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **End-to-end purchase flow:**
   - Trace _purchaseDeityPass from entry to completion
   - Verify state updates: deityPassOwners.push(buyer), symbolId assignment, any pool accounting
   - Verify ETH routing: where does the deity pass payment go? (nextPrizePool? futurePrizePool? claimable?)
   - Document the full flow: msg.value check -> price computation -> state update -> ETH routing

2. **Edge cases:**
   - k=0 (first deity pass): basePrice = 24 ETH, simplest case. Verify correct.
   - k=31 (last deity pass): basePrice = 520 ETH. Verify symbolId check allows k=31 but blocks k=32.
   - k=32 (should revert): verify the revert fires BEFORE any state mutation
   - Duplicate buyer: can the same address buy multiple deity passes? If so, do they get different symbolIds?

3. **Interaction with whale bundle system:**
   - Deity pass purchasers may also have whale bundles
   - Read whether _purchaseDeityPass interacts with whale bundle state (frozen levels, bundle type)
   - Document any interaction or confirm independence

4. **DGNRS (NFT) award flow:**
   - Read what happens after deity pass purchase — is a DGNRS NFT minted?
   - Trace the symbolId selection: symbolId < 32 implies 32 unique deity symbols
   - Verify no double-claim: once a symbolId is taken, it cannot be re-purchased
   - Check: is there a mapping from symbolId to owner that prevents duplicates?

Append findings to 03a-05-FINDINGS.md. Include final MATH-02 summary.
  </action>
  <verify>
    <automated>grep -c "deityPass\|symbolId\|MATH-02" .planning/phases/03a-core-eth-flow-modules/03a-05-FINDINGS.md | xargs test 3 -le</automated>
  </verify>
  <done>Full deity pass purchase flow traced. Edge cases at k=0, k=31, k=32 verified. ETH routing documented. symbolId uniqueness verified. MATH-02 final verdict assigned in summary.</done>
</task>

</tasks>

<verification>
- 03a-05-FINDINGS.md exists with severity-rated findings
- T(n) arithmetic table with exact values at k=0, 1, 10, 31, 100, 1000
- Overflow impossibility proven with uint256 headroom analysis
- k bound (symbolId < 32) verified from source
- Division exactness (even product) documented
- End-to-end purchase flow traced
- MATH-02 mapped to verdict
</verification>

<success_criteria>
- Deity pass T(n) formula verified non-overflowing at all required k values
- Actual k bound (31) identified and verified from symbolId check
- Exact arithmetic shown for n=100 and n=1000 as requirement specifies
- End-to-end purchase flow traced with ETH routing documented
- MATH-02 has clear PASS or finding verdict
</success_criteria>

<output>
After completion, create `.planning/phases/03a-core-eth-flow-modules/03a-05-SUMMARY.md`
</output>
