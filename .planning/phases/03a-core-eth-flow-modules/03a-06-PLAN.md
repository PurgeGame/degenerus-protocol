---
phase: 03a-core-eth-flow-modules
plan: 06
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md
autonomous: true
requirements: [INPT-01, INPT-02, INPT-03, INPT-04]

must_haves:
  truths:
    - "Ticket quantity bounds (type(uint32).max, costWei==0, TICKET_MIN_BUYIN_WEI) are enforced on every purchase path"
    - "Lootbox amount minimum (LOOTBOX_MIN = 0.01 ETH) is enforced; no upper bound issue exists or is documented"
    - "MintPaymentKind enum is validated by both Solidity ABI decoder and explicit else-revert in application code"
    - "Zero-address guards exist on all external-facing functions accepting addresses, or missing guards are documented as findings"
    - "No input validation bypass exists via delegatecall parameter forwarding"
  artifacts:
    - path: ".planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md"
      provides: "Input validation sweep findings document"
      contains: "## Findings"
  key_links:
    - from: "contracts/modules/DegenerusGameMintModule.sol"
      to: "contracts/DegenerusGame.sol"
      via: "purchase() delegatecall dispatch with raw parameter forwarding"
      pattern: "purchase|_purchaseFor"
    - from: "contracts/DegenerusGame.sol"
      to: "contracts/interfaces/IDegenerusGame.sol"
      via: "MintPaymentKind enum ABI encoding"
      pattern: "MintPaymentKind"
---

<objective>
Systematic input validation sweep across MintModule, JackpotModule, and EndgameModule to verify all external-facing parameters are bounds-checked.

Purpose: Missing input validation is a common source of exploits in Solidity contracts. This sweep ensures no parameter to any user-callable function can cause overflow, state corruption, or gas exhaustion via malicious input values.
Output: 03a-06-FINDINGS.md with a complete input validation matrix for all three modules.
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
@contracts/modules/DegenerusGameJackpotModule.sol (2740 lines)
@contracts/modules/DegenerusGameEndgameModule.sol (517 lines)
@contracts/DegenerusGame.sol (purchase entry point, _resolvePlayer, _processMintPayment)
@contracts/interfaces/IDegenerusGame.sol (MintPaymentKind enum)

<interfaces>
<!-- Input validation inventory from research -->

MintModule entry points:
  purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)
  purchaseBurnieLootbox(buyer, burnieAmount)
  recordMintData(player, ...) — internal via self-call
  processFutureTicketBatch(lvl) — called via advanceGame

JackpotModule entry points:
  payDailyJackpot(isDaily, lvl, randWord) — internal delegatecall
  processTicketBatch(lvl) — internal delegatecall
  consolidatePrizePools(lvl, rngWord) — internal delegatecall

EndgameModule entry points:
  rewardTopAffiliate(lvl) — internal delegatecall
  runRewardJackpots(lvl, rngWord) — internal delegatecall
  claimWhalePass(player) — external via DegenerusGame

Known validations:
  buyer: _resolvePlayer converts address(0) to msg.sender
  ticketQuantity: > type(uint32).max reverts
  lootBoxAmount: < LOOTBOX_MIN reverts when non-zero
  payKind: ABI decoder + else-revert
  burnieAmount: < BURNIE_LOOTBOX_MIN reverts
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: MintModule input validation matrix (INPT-01, INPT-02, INPT-03)</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Build complete MintModule input validation matrix:**
   For EVERY external-facing function parameter, document:
   - Parameter name and type
   - Validation present? (yes/no)
   - Validation mechanism (explicit check, ABI decoder, type constraint)
   - Bypass possible? (via delegatecall forwarding, type casting, etc.)
   - Line number of validation

   Functions to audit:
   - purchase(address buyer, uint256 ticketQuantity, uint256 lootBoxAmount, uint256 affiliateCode, MintPaymentKind payKind)
   - purchaseBurnieLootbox(address buyer, uint256 burnieAmount)

2. **Ticket quantity bounds deep dive (INPT-01):**
   - Verify: ticketQuantity > type(uint32).max reverts (line 613)
   - Question: what about ticketQuantity == 0? Does costWei == 0 catch it? Trace: (priceWei * 0) / 400 = 0, and costWei == 0 reverts. Confirm.
   - Question: what about ticketQuantity == 1? costWei = (priceWei * 1) / 400. At priceWei = 0.01 ether: costWei = 10000000000000000 / 400 = 25000000000000 = 0.000025 ETH. Is this >= TICKET_MIN_BUYIN_WEI (0.0025 ETH)? No — 0.000025 < 0.0025. So ticketQuantity=1 is rejected by the min buyin check. What is the minimum ticketQuantity that passes? Compute: 0.0025 ETH * 400 / 0.01 ETH = 100. So minimum ticketQuantity = 100 (at level 0 price).
   - Document the minimum valid ticketQuantity at each price tier

3. **Lootbox amount bounds (INPT-02):**
   - Minimum: LOOTBOX_MIN = 0.01 ether, enforced at line 608
   - Maximum: NO explicit maximum. Investigate implications:
     - lootBoxAmount is added to pool splits. At very large values (e.g., 10000 ETH), verify no overflow in BPS calculation
     - Max: (10000e18 * 9000) / 10000 = 9000e18 — well within uint256
     - Verify lootboxRngPendingEth accumulator can hold large values (uint256)
   - Document: no upper bound, but overflow is impossible due to uint256 arithmetic. Rate as INFORMATIONAL or PASS.

4. **MintPaymentKind enum validation (INPT-03):**
   - Solidity 0.8+ ABI decoder: reverts on out-of-range enum values during abi.decode of calldata
   - Application-level: _callTicketPurchase (line 870) has else-revert for unknown payKind
   - Application-level: _processMintPayment (DegenerusGame line 1077) has else-revert
   - Defense-in-depth: TWO layers of validation. Document as PASS.
   - Edge case: can a direct delegatecall (bypassing ABI encoding) pass a raw uint8 value > 2? Verify: modules are called via DegenerusGame's dispatch which decodes the enum from calldata. Direct external calls to modules revert due to access control. Document.

Write findings to 03a-06-FINDINGS.md.
  </action>
  <verify>
    <automated>test -f .planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md && grep -c "INPT-01\|INPT-02\|INPT-03" .planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md | xargs test 3 -le</automated>
  </verify>
  <done>Complete input validation matrix for MintModule. Ticket quantity minimum computed at each price tier. Lootbox amount upper bound analysis complete. MintPaymentKind defense-in-depth documented. INPT-01, INPT-02, INPT-03 mapped to verdicts.</done>
</task>

<task type="auto">
  <name>Task 2: JackpotModule, EndgameModule, and zero-address sweep (INPT-04)</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **JackpotModule input validation:**
   - JackpotModule functions are ALL internal (called via delegatecall from game advance logic)
   - No direct user input — parameters come from game state
   - Document: JackpotModule trusts caller (DegenerusGame) for all inputs. This is correct because:
     a) Functions are not externally callable (no external visibility)
     b) DegenerusGame validates inputs before dispatching delegatecall
   - Verify: are there ANY external/public functions on JackpotModule? If so, document their validation.
   - Check processTicketBatch: can lvl parameter ever be wrong? It comes from game state, not user input.

2. **EndgameModule input validation:**
   - Same pattern as JackpotModule — internal delegatecall functions
   - claimWhalePass(player): verify address validation — does _resolvePlayer apply? Or is it called with a validated address?
   - rewardTopAffiliate(lvl): returns early on address(0). Document.
   - runRewardJackpots(lvl, rngWord): internal, trusts caller. Document.

3. **Zero-address guard sweep (INPT-04):**
   Enumerate ALL functions across all three modules that accept an address parameter:

   MintModule:
   - purchase(buyer, ...): routed through _resolvePlayer (address(0) -> msg.sender). GUARDED.
   - purchaseBurnieLootbox(buyer, ...): explicit address(0) check (line 568). GUARDED.

   JackpotModule:
   - _addClaimableEth(player, ...): internal function. Does it check for address(0)?
   - _processAutoRebuy(player, ...): internal function. Does it check for address(0)?
   - Read both functions and verify whether address(0) could reach them and what would happen.

   EndgameModule:
   - claimWhalePass(player): does it check address(0)? If halfPasses[address(0)] == 0, early return handles it. But could someone set halfPasses for address(0)?
   - rewardTopAffiliate: checks top == address(0) and returns early. GUARDED.
   - _addClaimableEth(player, ...): same question as JackpotModule version.

   For each function: document whether address(0) is handled, how, and whether a missing guard matters (e.g., internal function only called with validated addresses is PASS).

4. **Delegatecall parameter forwarding analysis:**
   - DegenerusGame dispatches to modules via delegatecall with abi.encodeWithSelector
   - Verify: parameters are ABI-encoded by the compiler — no raw byte manipulation that could introduce type confusion
   - Verify: the function selector matches the intended module function
   - Check: could a malicious msg.data bypass DegenerusGame's dispatch and reach a module function directly? No — modules inherit DegenerusGameStorage, they are separate contracts called via delegatecall from DegenerusGame only.

Append findings to 03a-06-FINDINGS.md. Include summary table mapping INPT-01, INPT-02, INPT-03, INPT-04 to verdicts.
  </action>
  <verify>
    <automated>grep -c "INPT-04\|zero.address\|address(0)" .planning/phases/03a-core-eth-flow-modules/03a-06-FINDINGS.md | xargs test 2 -le</automated>
  </verify>
  <done>JackpotModule and EndgameModule input validation documented (internal functions trust caller). Zero-address guard sweep complete for all three modules. Delegatecall parameter forwarding analyzed. All INPT requirements (01-04) mapped to verdicts in summary table.</done>
</task>

</tasks>

<verification>
- 03a-06-FINDINGS.md exists with severity-rated findings
- Complete input validation matrix for all external-facing parameters
- Ticket quantity minimum at each price tier computed
- Lootbox amount upper bound analysis complete
- MintPaymentKind double-validation documented
- Zero-address guard for every address-accepting function documented
- All INPT requirements mapped to verdicts
</verification>

<success_criteria>
- Every external-facing parameter has a documented validation status
- Ticket quantity bounds verified with minimum valid values computed
- Lootbox amount maximum analyzed (no explicit cap, but overflow impossible)
- MintPaymentKind validated at ABI layer AND application layer
- Zero-address sweep covers all address parameters in all three modules
- INPT-01, INPT-02, INPT-03, INPT-04 all have clear verdicts
</success_criteria>

<output>
After completion, create `.planning/phases/03a-core-eth-flow-modules/03a-06-SUMMARY.md`
</output>
