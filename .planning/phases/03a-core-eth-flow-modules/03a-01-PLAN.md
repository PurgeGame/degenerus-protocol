---
phase: 03a-core-eth-flow-modules
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md
autonomous: true
requirements: [MATH-01, MATH-03, INPT-01, INPT-02, INPT-03]

must_haves:
  truths:
    - "Ticket cost formula (priceWei * quantity) / (4 * TICKET_SCALE) cannot overflow at max inputs"
    - "Lootbox BPS split (90/10 normal, 40/40/20 presale) sums to exactly the input amount for every tx"
    - "MintPaymentKind routing (DirectEth, Claimable, Combined) correctly credits ETH to the right pool in all three paths"
    - "Whale bundle and lazy pass purchase costs are correctly forwarded through _callTicketPurchase without loss or inflation"
    - "All unchecked blocks in MintModule are justified — no silent overflow/underflow possible"
  artifacts:
    - path: ".planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md"
      provides: "MintModule audit findings document"
      contains: "## Findings"
  key_links:
    - from: "contracts/modules/DegenerusGameMintModule.sol"
      to: "contracts/DegenerusGame.sol"
      via: "recordMint() self-call from delegatecall context"
      pattern: "recordMint|_processMintPayment"
    - from: "contracts/modules/DegenerusGameMintModule.sol"
      to: "contracts/interfaces/IDegenerusAffiliate.sol"
      via: "affiliate.payAffiliate() for rakeback"
      pattern: "payAffiliate"
---

<objective>
Audit DegenerusGameMintModule for ETH inflow correctness: ticket purchase cost formula, lootbox BPS pool splits, MintPaymentKind routing, and whale/lazy pass cost forwarding.

Purpose: MintModule is the primary ETH inflow path for the protocol. Every purchase routes through this module. Incorrect cost formulas, BPS split rounding, or payment kind routing errors would directly cause ETH accounting violations.
Output: 03a-01-FINDINGS.md documenting all confirmed findings, false positives, and PASS verdicts for each audit point.
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
@contracts/modules/DegenerusGameMintModule.sol (1114 lines)
@contracts/DegenerusGame.sol (lines 370-420: _processMintPayment, lines 547-580: purchase dispatch)
@contracts/storage/DegenerusGameStorage.sol (constants: TICKET_SCALE, pool variables)
@contracts/interfaces/IDegenerusGame.sol (MintPaymentKind enum)
@contracts/libraries/PriceLookupLib.sol (47 lines — price lookup used by cost formula)

<interfaces>
<!-- Key constants and functions the executor must trace -->

MintModule constants (lines 79-114):
  WRITES_BUDGET_SAFE = 550
  LOOTBOX_MIN = 0.01 ether
  BURNIE_LOOTBOX_MIN = 1000 ether
  TICKET_MIN_BUYIN_WEI = 0.0025 ether
  LOOTBOX_SPLIT_FUTURE_BPS = 9000
  LOOTBOX_SPLIT_NEXT_BPS = 1000

DegenerusGame constants (line 202):
  PURCHASE_TO_FUTURE_BPS = 1000

Cost formula (MintModule line 810):
  costWei = (priceWei * quantity) / (4 * TICKET_SCALE)

MintPaymentKind enum: { DirectEth: 0, Claimable: 1, Combined: 2 }

Key functions to trace:
  MintModule._purchaseFor() — lootbox BPS split (lines 704-719)
  MintModule._callTicketPurchase() — cost formula, quantity validation (lines 795-880)
  DegenerusGame.recordMint() — called via self-call from delegatecall context
  DegenerusGame._processMintPayment() — ETH/claimable routing (lines 1020-1090)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Trace ticket purchase cost formula and payment routing</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Cost formula overflow analysis (MATH-01 partial):**
   - Read MintModule._callTicketPurchase() (line 810): `costWei = (priceWei * quantity) / (4 * TICKET_SCALE)`
   - Compute max product: priceWei_max=0.24 ether (240000000000000000) * quantity_max=type(uint32).max (4294967295)
   - Product = 240000000000000000 * 4294967295 = ~1.03e27, well within uint256 (max ~1.16e77). Document PASS or finding.
   - Verify the `/400` division cannot produce costWei=0 for non-zero inputs (line 811 check: `costWei == 0` reverts)
   - Verify TICKET_MIN_BUYIN_WEI check (line 812) catches sub-dust purchases

2. **MintPaymentKind routing (INPT-03 partial):**
   - Read DegenerusGame._processMintPayment() (lines 1020-1090)
   - Trace all three paths: DirectEth (msg.value >= amount), Claimable (claimable > amount, preserves 1-wei sentinel), Combined (ETH first, then claimable)
   - For DirectEth: confirm overpay is allowed (line 1039: only checks `msg.value < amount`)
   - For Claimable: confirm 1-wei sentinel preserved (line 1047: `claimable <= amount` reverts, meaning claimable must be STRICTLY greater)
   - For Combined: confirm `msg.value > amount` reverts (no overpay in Combined mode)
   - Verify `prizeContribution` is correctly computed and split: 10% to futurePrizePool, 90% to nextPrizePool

3. **Whale/lazy pass cost forwarding (MATH-03 partial):**
   - Trace how WhaleModule purchase costs reach _callTicketPurchase(). Read WhaleModule._purchaseWhaleBundle() and _purchaseLazyPass() to identify how they call back into purchase/mint flow
   - Verify the cost value is not inflated or lost during the delegatecall chain
   - Document whether whale bundle prices (2.4 ETH, 4 ETH) correctly flow through the same BPS split logic

4. **Input validation on purchase entry (INPT-01, INPT-02):**
   - Read MintModule.purchase() entry point (around line 600-650)
   - Confirm ticketQuantity > type(uint32).max reverts (line 613)
   - Confirm lootBoxAmount < LOOTBOX_MIN reverts when non-zero (line 608)
   - Confirm totalCost == 0 reverts (line 618)
   - Read purchaseBurnieLootbox() — confirm buyer == address(0) reverts (line 568), burnieAmount < BURNIE_LOOTBOX_MIN reverts (line 956)

Write initial findings to 03a-01-FINDINGS.md with sections for each audit point. Use severity ratings: CRITICAL / HIGH / MEDIUM / LOW / INFORMATIONAL / PASS.
  </action>
  <verify>
    <automated>test -f .planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md && grep -c "PASS\|CRITICAL\|HIGH\|MEDIUM\|LOW\|INFORMATIONAL" .planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md</automated>
  </verify>
  <done>Cost formula overflow analysis complete with arithmetic shown. All three MintPaymentKind paths traced with correct/incorrect verdict. Whale/lazy pass cost forwarding verified. Input validation on purchase entry confirmed or findings documented.</done>
</task>

<task type="auto">
  <name>Task 2: Audit lootbox BPS split and unchecked block safety</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Lootbox BPS split correctness (MATH-01 partial):**
   - Read MintModule._purchaseFor() lines 700-720
   - Normal split: futureShare = (lootBoxAmount * 9000) / 10000, nextShare = (lootBoxAmount * 1000) / 10000, vaultShare = 0
   - Verify: futureShare + nextShare + rewardShare == lootBoxAmount for all inputs (rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare)
   - Compute BPS rounding at edge cases: 1 wei, 3 wei, 7 wei, 11 wei, 1 ETH, 1000 ETH
   - For 1 wei: futureShare = (1 * 9000) / 10000 = 0, nextShare = (1 * 1000) / 10000 = 0, rewardShare = 1. ALL goes to futurePrizePool. Document.
   - Presale split: 40% future, 40% next, 20% vault. Verify same remainder property.
   - Confirm the unchecked subtraction on line 712 is safe: prove futureShare + nextShare + vaultShare <= lootBoxAmount always holds (since all BPS < 10000 and sum to 10000).

2. **All unchecked blocks audit:**
   - Enumerate every `unchecked` block in MintModule (15 occurrences found via grep)
   - For each: document the arithmetic operation, why overflow/underflow is impossible, and rate as PASS or finding
   - Pay special attention to: line 258 (loop counter), line 629 (pool accounting), line 712 (BPS remainder), line 998 (cost calculation)

3. **Affiliate rakeback integration:**
   - Trace affiliate.payAffiliate() calls in purchase flow (lines 883-899)
   - Verify return value (rakeback in BURNIE, not ETH) is handled correctly — not added to any ETH pool
   - In Combined payment mode, verify affiliate is called separately for fresh-ETH and claimable portions

4. **processTicketBatch loop bounds (INPT-02 partial, DOS-01 partial):**
   - Read processFutureTicketBatch() (line 310+)
   - Verify WRITES_BUDGET_SAFE=550 bounds the while-loop
   - Verify cold-storage scaling (65% first batch) correctly reduces budget
   - Verify _raritySymbolBatch inner loop is bounded by group size 16 and max 256 traits

Append findings to 03a-01-FINDINGS.md. Include a summary table at the end: requirement ID, verdict, severity, notes.
  </action>
  <verify>
    <automated>grep -c "unchecked" .planning/phases/03a-core-eth-flow-modules/03a-01-FINDINGS.md | xargs test 1 -le</automated>
  </verify>
  <done>Lootbox BPS split verified with edge-case arithmetic. All 15 unchecked blocks individually assessed. Affiliate integration confirmed safe. processTicketBatch loop bounds verified. Summary table maps each requirement (MATH-01, MATH-03, INPT-01, INPT-02, INPT-03) to a verdict.</done>
</task>

</tasks>

<verification>
- 03a-01-FINDINGS.md exists with severity-rated findings for all audit points
- Every unchecked block in MintModule is individually assessed
- Cost formula overflow arithmetic is shown with concrete numbers
- BPS split rounding is verified at edge cases (1 wei, small values)
- Summary table maps MATH-01, MATH-03, INPT-01, INPT-02, INPT-03 to verdicts
</verification>

<success_criteria>
- Ticket cost formula overflow analysis complete with max-input arithmetic
- All three MintPaymentKind paths traced with correct/incorrect verdict
- Lootbox BPS split verified to sum to input for all values including edge cases
- All 15 unchecked blocks individually assessed as safe or finding raised
- processTicketBatch loop bounds confirmed bounded
- Findings document complete with severity ratings and requirement mapping
</success_criteria>

<output>
After completion, create `.planning/phases/03a-core-eth-flow-modules/03a-01-SUMMARY.md`
</output>
