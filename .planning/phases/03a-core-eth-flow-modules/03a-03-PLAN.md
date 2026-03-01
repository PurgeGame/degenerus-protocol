---
phase: 03a-core-eth-flow-modules
plan: 03
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md
autonomous: true
requirements: [DOS-01]

must_haves:
  truths:
    - "Level transition guards in EndgameModule correctly gate BAF and Decimator jackpots to their designated levels"
    - "BAF jackpot pool draw percentages (10%, 25%, 20%) are correctly applied at the right levels"
    - "Decimator delegation via self-call correctly deducts pool spend from futurePrizePool"
    - "claimWhalePass CEI pattern prevents reentrancy — state cleared before external effects"
    - "EndgameModule has no unbounded loops (all iteration delegated to bounded external calls)"
  artifacts:
    - path: ".planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md"
      provides: "EndgameModule audit findings document"
      contains: "## Findings"
  key_links:
    - from: "contracts/modules/DegenerusGameEndgameModule.sol"
      to: "contracts/DegenerusGame.sol"
      via: "self-call: IDegenerusGame(address(this)).runDecimatorJackpot()"
      pattern: "runDecimatorJackpot"
    - from: "contracts/modules/DegenerusGameEndgameModule.sol"
      to: "contracts/modules/DegenerusGamePayoutUtils.sol"
      via: "_addClaimableEth -> _calcAutoRebuy"
      pattern: "_addClaimableEth"
---

<objective>
Audit DegenerusGameEndgameModule for level transition correctness, BAF/Decimator jackpot pool accounting, claimWhalePass CEI safety, and loop bound verification.

Purpose: EndgameModule runs reward jackpots at milestone levels (every 5 or 10 levels). Incorrect level guards, pool draw percentages, or decimator delegation could distribute wrong amounts or skip distributions entirely.
Output: 03a-03-FINDINGS.md documenting all confirmed findings, false positives, and PASS verdicts.
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
@contracts/modules/DegenerusGameEndgameModule.sol (517 lines)
@contracts/modules/DegenerusGamePayoutUtils.sol (94 lines)
@contracts/DegenerusGame.sol (runDecimatorJackpot dispatch, claimWhalePass entry)
@contracts/storage/DegenerusGameStorage.sol (whalePassClaims, pool variables)

<interfaces>
<!-- Key architecture from research -->

EndgameModule key functions:
  runRewardJackpots(lvl, rngWord) — dispatches BAF and Decimator based on level
  _runBafJackpot() — 50% ETH / 50% lootbox for large winners, alternating for small
  rewardTopAffiliate(lvl) — 1% of DGNRS affiliate pool to top affiliate
  claimWhalePass(player) — awards tickets for 100 levels, CEI pattern

BAF pool draw percentages:
  Normal (every 10 levels): 10% of futurePrizePool
  Level 50: 25% of futurePrizePool
  Level 100: 20% of futurePrizePool

Decimator levels: 5, 15, 25, 35, 45, 55, 65, 75, 85 (NOT 95)
  Normal: 10% of futurePrizePool
  Level 100: 30% of futurePrizePool

Decimator delegation: self-call IDegenerusGame(address(this)).runDecimatorJackpot()
  Return value `returnWei` is unspent pool refund
  Net spend = poolWei - returnWei
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit level transition guards and BAF/Decimator pool accounting</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **Level transition guard correctness:**
   - Read runRewardJackpots(lvl, rngWord) (around line 132)
   - Map which levels trigger BAF: every 10 levels (10, 20, 30, ..., 100). Verify the modulo condition.
   - Map which levels trigger Decimator: 5, 15, 25, 35, 45, 55, 65, 75, 85 (NOT 95). Verify the condition excludes 95.
   - Verify no level triggers BOTH BAF and Decimator simultaneously (BAF at multiples of 10, Decimator at 5+10k where k != 9)
   - Verify level 100 milestone applies correct special percentages for both BAF (20%) and Decimator (30%)
   - Document the full level-to-action mapping table

2. **BAF jackpot pool draw correctness:**
   - Read _runBafJackpot() (around line 336)
   - Trace pool draw: poolWei = futurePrizePool * percentage / 10000
   - Verify percentage selection: 10% normal, 25% at level 50, 20% at level 100
   - Verify futurePrizePool is decremented by poolWei BEFORE distribution begins
   - Verify refund path: any unspent pool (from insufficient winners or lootbox routing) is returned to futurePrizePool
   - Verify netSpend = poolWei - refund is correct and no wei leak exists

3. **Decimator delegation via self-call:**
   - Read the self-call: IDegenerusGame(address(this)).runDecimatorJackpot(lvl, rngWord, poolWei)
   - Verify this is a CALL (not delegatecall) — the decimator module runs in DegenerusGame context via its own delegatecall dispatch
   - Verify return value `returnWei` (unspent refund) is correctly subtracted: spend = poolWei - returnWei
   - Verify futurePrizePool accounting: deducted by poolWei before call, credited by returnWei after call. Net effect: futurePrizePool -= spend.
   - Check for reentrancy: the self-call could re-enter EndgameModule or other game functions. Verify game state (rngLocked, level) prevents re-entrancy into purchase or advance paths.

4. **rewardTopAffiliate audit:**
   - Read rewardTopAffiliate(lvl) (around line 102)
   - Verify early return when top == address(0) prevents zero-address reward
   - Verify 1% of DGNRS affiliate pool is correctly calculated (AFFILIATE_POOL_REWARD_BPS = 100)
   - Verify reward is deducted from the pool and credited correctly

Write findings to 03a-03-FINDINGS.md with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md && grep -c "BAF\|Decimator\|level" .planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md | xargs test 3 -le</automated>
  </verify>
  <done>Level transition guards mapped for all 100 levels. BAF and Decimator pool draw percentages verified. Self-call delegation accounting traced. rewardTopAffiliate verified.</done>
</task>

<task type="auto">
  <name>Task 2: Audit claimWhalePass CEI pattern and loop bounds (DOS-01)</name>
  <files>.planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

1. **claimWhalePass CEI (Checks-Effects-Interactions) pattern:**
   - Read claimWhalePass(player) (around line 495)
   - Verify: whalePassClaims[player] is cleared BEFORE awarding tickets (CEI pattern)
   - Verify halfPasses == 0 early return prevents empty claims
   - Verify tickets awarded for 100 levels at level + 1 — correct level offset
   - Verify halfPasses correctly determines ticket count per level
   - Check: could a malicious contract re-enter claimWhalePass via a callback during ticket awarding? Trace whether any external call happens during the award.

2. **EndgameModule loop bound verification (DOS-01):**
   - Enumerate ALL for/while loops in EndgameModule (517 lines)
   - Research notes: "EndgameModule has NO for/while loops in its own code. All iteration happens through called modules"
   - Verify this claim by reading the entire module. If any loop exists, document its bounds.
   - For _runBafJackpot: trace winnersArr.length — where does the array come from? Verify it is bounded by the jackpots contract return (JACKPOT_MAX_WINNERS=300 or similar constant)
   - For _purchaseDeityPass loop (line 497 — for 100 levels): verify this is a FIXED constant (100 iterations)
   - Document: "EndgameModule iteration is bounded by: (a) fixed constants, (b) external array lengths from bounded jackpot queries"

3. **_addClaimableEth implementation (EndgameModule version):**
   - Read EndgameModule._addClaimableEth() (line 217)
   - Compare with JackpotModule._addClaimableEth() (line 911) — both use _calcAutoRebuy from PayoutUtils
   - Document any differences: different bonus BPS values, different routing logic, different error handling
   - Verify both versions correctly handle: claimableDelta == 0 (auto-rebuy consumed all), claimableDelta == amount (no auto-rebuy)
   - Check: do both versions have the same auto-rebuy bonus BPS (13000/14500)? If different, document whether intentional.

4. **Unchecked blocks in EndgameModule:**
   - Only 1 unchecked block found (line 373). Read and document the arithmetic operation.
   - Verify the operation cannot overflow/underflow given its inputs.
   - Rate as PASS or finding.

Append findings to 03a-03-FINDINGS.md. Include summary table for DOS-01 verdict.
  </action>
  <verify>
    <automated>grep -c "claimWhalePass\|CEI\|loop\|DOS-01" .planning/phases/03a-core-eth-flow-modules/03a-03-FINDINGS.md | xargs test 2 -le</automated>
  </verify>
  <done>claimWhalePass CEI pattern verified. EndgameModule loop inventory complete (fixed constants and bounded externals confirmed). _addClaimableEth dual implementation compared. Single unchecked block assessed. DOS-01 mapped to verdict.</done>
</task>

</tasks>

<verification>
- 03a-03-FINDINGS.md exists with severity-rated findings
- Level-to-action mapping table (which levels trigger which jackpots)
- BAF/Decimator pool draw percentages verified with arithmetic
- claimWhalePass CEI order confirmed
- EndgameModule loop inventory complete
- _addClaimableEth JackpotModule vs EndgameModule comparison documented
- DOS-01 mapped to verdict
</verification>

<success_criteria>
- All level transition guards mapped and verified correct
- BAF pool draw percentages (10/25/20%) confirmed at correct levels
- Decimator self-call accounting (poolWei - returnWei) verified
- claimWhalePass CEI pattern confirmed (state cleared before effects)
- EndgameModule confirmed to have no unbounded loops
- Dual _addClaimableEth implementations compared and differences documented
</success_criteria>

<output>
After completion, create `.planning/phases/03a-core-eth-flow-modules/03a-03-SUMMARY.md`
</output>
