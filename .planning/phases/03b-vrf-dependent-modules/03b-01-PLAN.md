---
phase: 03b-vrf-dependent-modules
plan: 03b-01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md
autonomous: true
requirements:
  - MATH-05

must_haves:
  truths:
    - "Every VRF word derivation path in LootboxModule is traced from lootboxRngWordByIndex[index] through keccak256 mixing to each entropyStep consumer"
    - "The lootbox reward probability distribution (55% tickets / 10% DGNRS / 10% WWXRP / 25% BURNIE) is confirmed from the `roll % 20` logic with exact range boundaries"
    - "The ticket variance tier probabilities (1%/4%/20%/45%/30%) and their multipliers (4.6x/2.3x/1.1x/0.651x/0.45x) are verified from source constants"
    - "The BURNIE reward variance (80% low 58-134% / 20% high 307-590%) is traced through both paths with exact BPS constants"
    - "The EV multiplier formula (_lootboxEvMultiplierFromScore) is confirmed piecewise-linear with correct numeric behavior at boundaries (0%->80%, 60%->100%, 305%->135%)"
    - "The 10 ETH per-level cap in _applyEvMultiplierWithCap is confirmed enforced on all three resolution paths: openLootBox, openBurnieLootBox, resolveLootboxDirect"
    - "Boon weight consistency between _boonPoolStats totalWeight and _boonFromRoll cumulative cursor is verified for all 16 boolean flag combinations (decimatorAllowed x deityEligible x allowWhalePass x allowLazyPass)"
  artifacts:
    - path: ".planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md"
      provides: "Complete LootboxModule VRF derivation trace, reward distribution verification, EV multiplier analysis, boon weight audit"
      contains: "MATH-05"
  key_links:
    - from: "contracts/modules/DegenerusGameLootboxModule.sol:openLootBox"
      to: "lootboxRngWordByIndex[index]"
      via: "VRF word read for entropy derivation"
      pattern: "lootboxRngWordByIndex"
    - from: "contracts/modules/DegenerusGameLootboxModule.sol:_lootboxEvMultiplierFromScore"
      to: "_applyEvMultiplierWithCap"
      via: "EV multiplier computed then applied with per-level cap"
      pattern: "_applyEvMultiplierWithCap"
    - from: "contracts/modules/DegenerusGameLootboxModule.sol:_boonPoolStats"
      to: "_boonFromRoll"
      via: "totalWeight from stats must match cursor range in roll selection"
      pattern: "_boonPoolStats.*_boonFromRoll"
---

<objective>
Audit the DegenerusGameLootboxModule (~1749 lines) for VRF word derivation correctness, reward probability distribution accuracy, EV multiplier formula integrity, and boon weight consistency.

Purpose: MATH-05 requires verifying that the lootbox EV multiplier produces expected values and that no activity score can create guaranteed positive-EV extraction. This plan traces every path from VRF word to payout, verifies the probability distributions match documented expectations, and checks the critical boon weight consistency between pool stats computation and roll selection.

Output: `03b-01-FINDINGS-lootbox-module-audit.md` containing complete VRF derivation traces, probability verification, EV multiplier analysis, boon weight audit, and MATH-05 partial verdict (EV formula correctness; the full EV model is in 03b-03).
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
<!-- Primary audit target: contracts/modules/DegenerusGameLootboxModule.sol (1749 lines) -->

VRF word derivation chain (from research):
  lootboxRngWordByIndex[index] --> keccak256(rngWord, player, day, amount) --> initial entropy
  --> EntropyLib.entropyStep(entropy) chain for: target level, reward type, variance tier, boon roll

Reward type distribution (roll % 20):
  0-10 = tickets (55%), 11-12 = DGNRS (10%), 13-14 = WWXRP (10%), 15-19 = BURNIE (25%)

EV multiplier (lines 469-490):
  _lootboxEvMultiplierFromScore(score):
    score <= 6000 BPS: 8000 + (score * 2000 / 6000) -- linear 80% to 100%
    score >= 30500 BPS: 13500 -- capped at 135%
    else: 10000 + ((score - 6000) * 3500 / 24500) -- linear 100% to 135%

Per-level cap (lines 500-534):
  _applyEvMultiplierWithCap(player, lvl, amount, evMultiplierBps):
    Tracks lootboxEvBenefitUsedByLevel[player][lvl], cap = 10 ether
    Cap depleted: falls back to 100% EV

Three resolution entry points:
  openLootBox -- ETH lootbox
  openBurnieLootBox -- BURNIE lootbox
  resolveLootboxDirect -- direct resolution

Boon system:
  _boonPoolStats(flags) -- returns (totalWeight, ...)
  _boonFromRoll(roll, totalWeight, flags) -- returns boon type
  16 flag combinations from: decimatorAllowed, deityEligible, allowWhalePass, allowLazyPass
  Fallback return DEITY_BOON_ACTIVITY_50 should never fire if weights are consistent

Phase 2 prerequisite: EntropyLib.entropyStep() validated in 02-06-FINDINGS (non-exploitable with VRF seed)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Trace all VRF word derivation paths and verify reward probability distributions</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

Read `contracts/modules/DegenerusGameLootboxModule.sol` in its entirety (~1749 lines).

**1. VRF Word Derivation Trace**

For each of the three resolution entry points (openLootBox, openBurnieLootBox, resolveLootboxDirect):
a. Identify where `lootboxRngWordByIndex[index]` is read
b. Trace the keccak256 mixing: what inputs are hashed with the VRF word? (player, day, amount expected)
c. Count how many sequential entropyStep() calls derive outcomes from a single initial entropy
d. For each entropyStep consumer, document: what selection it drives, what modular range is used, whether entropy threading is correct (each call uses previous output)

Verify the per-player independence property: each player gets a unique seed via keccak256(rngWord, player, ...).

**2. Reward Type Distribution (roll % 20)**

a. Locate the `_resolveLootboxRoll` function or equivalent that branches on reward type
b. Confirm the exact boundaries: which roll values map to tickets, DGNRS, WWXRP, BURNIE
c. Verify: is it `roll % 20` and are the ranges exactly 0-10(55%), 11-12(10%), 13-14(10%), 15-19(25%)?
d. Flag any off-by-one that changes probabilities

**3. Ticket Variance Tiers**

a. Locate the variance tier selection logic
b. Confirm the five tiers: 1% get 4.6x, 4% get 2.3x, 20% get 1.1x, 45% get 0.651x, 30% get 0.45x
c. Verify the BPS constants match these multipliers (e.g., 46000 BPS = 4.6x, 23000 BPS = 2.3x, etc.)
d. Confirm the tier boundaries sum to 100%

**4. BURNIE Reward Variance**

a. Locate the BURNIE path branching logic (80% low path, 20% high path)
b. For the low path (58%-130%): extract all 16 BPS values, verify they are the expected range
c. For the high path (307%-590%): extract all BPS values, verify range
d. Confirm the low/high branch probability (expected: 80%/20% or similar from a roll boundary)

**5. Target Level Roll**

a. Locate `_rollTargetLevel` or equivalent
b. Confirm: 95% chance 0-5 levels ahead, 5% chance 5-50 levels ahead
c. Verify the modular arithmetic and boundary handling

Write as Section 1 of the findings document: "VRF Derivation and Probability Distribution Audit".
  </action>
  <verify>
    <automated>
      cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
      grep -n "lootboxRngWordByIndex\|entropyStep\|roll.*%.*20\|_resolveLootbox\|_rollTarget" contracts/modules/DegenerusGameLootboxModule.sol | wc -l
    </automated>
  </verify>
  <done>
    Every VRF word read in LootboxModule is traced with exact line numbers.
    Reward type probabilities are confirmed with exact roll boundaries.
    Ticket variance tier BPS constants and probabilities are verified.
    BURNIE low/high path BPS constants are documented.
    Target level roll distribution is confirmed.
    Any discrepancy from documented expectations is flagged as a finding.
  </done>
</task>

<task type="auto">
  <name>Task 2: Audit EV multiplier formula, per-level cap enforcement, and boon weight consistency; write verdicts</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. EV Multiplier Formula Verification**

a. Read `_lootboxEvMultiplierFromScore` (lines 469-490). Verify the piecewise-linear formula:
   - score = 0: should return 8000 BPS (80% EV)
   - score = 6000: should return 10000 BPS (100% EV, neutral)
   - score = 18250 (midpoint): should return 11750 BPS (117.5% EV)
   - score = 30500: should return 13500 BPS (135% EV)
   - score > 30500: should still return 13500 BPS (capped)
b. Check for integer division truncation issues: does `(score * 2000) / 6000` or `(excess * 3500) / 24500` lose significant precision?
c. Check boundary condition: what happens at score = 6000 exactly? Both branches should return 10000 — verify no discontinuity.

**2. Per-Level Cap Enforcement (_applyEvMultiplierWithCap)**

a. Read `_applyEvMultiplierWithCap` (lines 500-534). Trace the logic:
   - If evMultiplierBps == 10000 (neutral): returns amount unchanged, no tracking
   - Otherwise: computes remaining cap from lootboxEvBenefitUsedByLevel[player][lvl]
   - Splits amount into adjustedPortion (up to remaining cap) and neutralPortion
   - adjustedPortion gets EV multiplier, neutralPortion stays at 1x
b. CRITICAL: Verify this function is called on ALL three resolution paths:
   - openLootBox: trace from entry to _applyEvMultiplierWithCap call
   - openBurnieLootBox: trace from entry to _applyEvMultiplierWithCap call
   - resolveLootboxDirect: trace from entry to _applyEvMultiplierWithCap call
   - If ANY path bypasses the cap, flag as HIGH finding
c. Verify the cap tracks raw amount (adjustedPortion), NOT benefit delta (adjustedValue - adjustedPortion)
   - Research Open Question #2 flags this as potentially intentional vs. bug
   - Document which interpretation is implemented and the economic impact

**3. Boon Weight Consistency Audit**

a. Locate `_boonPoolStats` function. For each of the 16 flag combinations (4 booleans: decimatorAllowed, deityEligible, allowWhalePass, allowLazyPass), compute the totalWeight returned.
b. Locate `_boonFromRoll` function. For each of the 16 flag combinations, trace the cumulative cursor logic and determine the maximum roll value that maps to a valid boon.
c. For each combination: does _boonPoolStats.totalWeight == the cursor range expected by _boonFromRoll?
d. If any mismatch exists: the fallback `return DEITY_BOON_ACTIVITY_50` could fire, and a roll that should map to one boon type would map to the fallback instead. Flag as a finding.
e. If weights are consistent: confirm the fallback is unreachable and classify as dead code (Informational).

**4. Additional Checks**

a. Verify that `openLootBox` and `openBurnieLootBox` require `lootboxRngWordByIndex[index] != 0` before resolution (VRF word must exist)
b. Verify the lootbox amount is validated (non-zero, within bounds)
c. Check for reentrancy vectors: does lootbox resolution make external calls before updating state?

**5. Write Complete Findings Document**

Sections:
1. VRF Derivation and Probability Distribution Audit (from Task 1)
2. EV Multiplier Formula Verification (numeric boundary checks)
3. Per-Level Cap Enforcement Audit (all three paths checked)
4. Boon Weight Consistency Audit (16 flag combinations)
5. Additional Safety Checks
6. MATH-05 Partial Verdict: EV formula correctness and cap enforcement (full EV model deferred to 03b-03)
7. Findings (any issues rated by severity)
  </action>
  <verify>
    <automated>
      test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md && \
      grep -c "MATH-05\|_applyEvMultiplierWithCap\|_boonPoolStats\|_boonFromRoll" /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md
    </automated>
  </verify>
  <done>
    03b-01-FINDINGS-lootbox-module-audit.md exists and contains:
    - EV multiplier numeric verification at all boundary points
    - Per-level cap enforcement confirmed (or bypass flagged) on all three resolution paths
    - Boon weight consistency verified across all 16 flag combinations
    - MATH-05 partial verdict (formula correctness)
    - Any findings rated by severity
    - No contract files were modified
  </done>
</task>

</tasks>

<verification>
```bash
# Verify findings document exists and has substantive content
wc -l /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md

# Verify MATH-05 verdict present
grep -E "MATH-05" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md

# Verify boon weight audit was performed
grep -c "_boonPoolStats\|_boonFromRoll\|totalWeight" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md

# Cross-check: confirm all three resolution entry points are documented
grep -c "openLootBox\|openBurnieLootBox\|resolveLootboxDirect" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-01-FINDINGS-lootbox-module-audit.md
```
</verification>

<success_criteria>
- 03b-01-FINDINGS-lootbox-module-audit.md exists in the phase directory
- Every VRF word derivation path in LootboxModule is traced with line numbers
- Reward type probability distribution (55/10/10/25) is confirmed or corrected
- Ticket variance tier probabilities and multipliers are verified from source constants
- BURNIE low/high path BPS constants are documented
- EV multiplier formula is verified at all boundary points (0%, 60%, 305%)
- Per-level 10 ETH cap is confirmed enforced on all three resolution paths
- Boon weight consistency is verified across all 16 flag combinations
- MATH-05 partial verdict is documented
- Any findings rated by severity
- No contract files were modified
</success_criteria>

<output>
After completion, create `.planning/phases/03b-vrf-dependent-modules/03b-01-SUMMARY.md` following the standard summary template.
</output>
