---
phase: 03b-vrf-dependent-modules
plan: 03b-03
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md
autonomous: true
requirements:
  - MATH-05

must_haves:
  truths:
    - "A mathematical EV model is computed for each of the four lootbox reward paths (tickets, DGNRS, WWXRP, BURNIE) using exact BPS constants from the contract"
    - "The composite EV at neutral activity score (60% / 6000 BPS) is computed and compared to the expected ~100%"
    - "The composite EV at maximum activity score (305% / 30500 BPS) is computed and confirmed <= 135%"
    - "The 10 ETH per-level cap is modeled: maximum extractable benefit per level at 135% EV is confirmed as 3.5 ETH"
    - "Activity score components are enumerated with their individual caps to determine the minimum investment required to reach each EV tier"
    - "The _applyEvMultiplierWithCap tracking behavior is modeled: cap depletes by raw input amount (not benefit delta), making effective extraction even lower than the nominal 3.5 ETH"
    - "A verdict is rendered on whether any activity score reachable through normal play can produce guaranteed positive-EV extraction exceeding the investment cost"
  artifacts:
    - path: ".planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md"
      provides: "Complete mathematical EV model of lootbox rewards, activity score cost analysis, extraction limit analysis, MATH-05 verdict"
      contains: "MATH-05"
  key_links:
    - from: "Activity score components"
      to: "_lootboxEvMultiplierFromScore"
      via: "Score maps to EV multiplier BPS"
      pattern: "_lootboxEvMultiplierFromScore"
    - from: "EV multiplier"
      to: "_applyEvMultiplierWithCap"
      via: "Multiplied amount capped at 10 ETH raw input per level"
      pattern: "_applyEvMultiplierWithCap"
---

<objective>
Build a complete mathematical model of the lootbox expected value across all four reward paths, using exact BPS constants from the contract. Compute the EV at each activity score tier, model the per-level cap's effect on extraction, and analyze whether any achievable activity score creates a guaranteed positive-EV extraction opportunity that exceeds the cost of achieving that score.

Purpose: MATH-05 requires proving that no activity score can create guaranteed positive-EV extraction. This plan provides the rigorous mathematical analysis to support that verdict: computing the base EV, modeling the cap mechanism, and comparing extraction potential against the cost of reaching high activity scores (deity pass = 24+ ETH, quest streaks = daily participation, etc.).

Output: `03b-03-FINDINGS-lootbox-ev-model.md` containing the complete EV model, activity score cost analysis, extraction limit computation, and MATH-05 final verdict.
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
<!-- Key constants from DegenerusGameLootboxModule.sol for EV calculation -->

EV Multiplier Constants:
  ACTIVITY_SCORE_NEUTRAL_BPS = 6000     (60% = neutral/break-even)
  ACTIVITY_SCORE_MAX_BPS = 30500        (305% = maximum)
  LOOTBOX_EV_MIN_BPS = 8000             (80% EV at score 0)
  LOOTBOX_EV_NEUTRAL_BPS = 10000        (100% EV at score 60%)
  LOOTBOX_EV_MAX_BPS = 13500            (135% EV at score 305%)
  LOOTBOX_EV_BENEFIT_CAP = 10 ether     (per-account per-level cap)

Reward Distribution (roll % 20):
  Tickets: rolls 0-10 = 55%
  DGNRS: rolls 11-12 = 10%
  WWXRP: rolls 13-14 = 10%
  BURNIE: rolls 15-19 = 25%

Ticket Variance Tiers:
  1% = 4.6x (46000 BPS)
  4% = 2.3x (23000 BPS)
  20% = 1.1x (11000 BPS)
  45% = 0.651x (6510 BPS)
  30% = 0.45x (4500 BPS)

Research pre-computed: E[variance] = 0.01*4.6 + 0.04*2.3 + 0.20*1.1 + 0.45*0.651 + 0.30*0.45 = 0.786

Tickets: E[ticket_value] = 0.55 * 1.61 * 0.786 = 0.696 (69.6% of input -- 1.61x is level target multiplier)

BURNIE Variance:
  Low path (80%): 16 BPS values from ~5808 to ~13440, avg ~9624 BPS = 96.24%
  High path (20%): BPS values from ~30705 to ~59000, avg ~44852 BPS = 448.5%
  E[burnie] = 0.25 * (0.80 * 0.9624 + 0.20 * 4.485) = 0.25 * 1.667 = 0.417

Activity Score Components (from DegeneretteModule:1020-1093):
  - Mint count bonus (based on level + 1)
  - Quest streak bonus (daily quests)
  - Affiliate bonus
  - Deity pass bonus (80% activity = 24000 BPS if deity pass holder)
  - Whale bundle bonus
  - Other bonuses
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Compute exact EV for each reward path using contract BPS constants; build composite EV model</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

Read the constants section of `contracts/modules/DegenerusGameLootboxModule.sol` (approximately lines 265-450) to extract ALL BPS constants used in reward calculations.

**1. Ticket Path EV (55% probability)**

a. Extract the exact ticket variance tier BPS constants from the contract. Verify they match: 46000, 23000, 11000, 6510, 4500.
b. Extract the tier probability boundaries. How is the tier selected? (entropy % 100 with boundaries at 1, 5, 25, 70, 100?)
c. Compute E[ticket_variance] = sum(probability_i * multiplier_i) using exact values.
d. Extract the level target multiplier. Research says 1.61x — verify from `_rollTargetLevel` logic. How is the target level converted to a value multiplier? (Is it the ratio of target level price to current level price?)
e. Compute E[ticket_path] = 0.55 * target_level_multiplier * E[ticket_variance]
f. Note: ticket rewards are in future tickets at the target level, not ETH. Their "value" is the price of those tickets. Document this distinction.

**2. BURNIE Path EV (25% probability)**

a. Extract ALL 16 low-path BPS values from the contract (the array or sequential constants).
b. Compute the low-path mean: avg(BPS_0 through BPS_15) / 10000.
c. Extract ALL high-path BPS values from the contract.
d. Compute the high-path mean: avg(high_BPS_0 through high_BPS_N) / 10000.
e. What determines the low/high split? (Expected: 80%/20% from entropy % 5 == 0 or similar)
f. Compute E[burnie_path] = 0.25 * (low_prob * low_mean + high_prob * high_mean)
g. Note: BURNIE rewards are in BURNIE tokens, not ETH. Their "value" depends on BURNIE/ETH exchange rate. Document this assumption.

**3. DGNRS Path EV (10% probability)**

a. Extract the DGNRS reward calculation from the contract.
b. Is it a fixed amount, pool-dependent, or variance-tiered?
c. Compute E[dgnrs_path] = 0.10 * E[dgnrs_reward_value]
d. Note: DGNRS rewards are in DGNRS tokens. Value depends on DGNRS/ETH price. Document.

**4. WWXRP Path EV (10% probability)**

a. Extract the WWXRP reward: research says fixed 1 token per lootbox.
b. Compute E[wwxrp_path] = 0.10 * wwxrp_value
c. Note: WWXRP value depends on market price. Document.

**5. Composite Base EV (at neutral 100% multiplier)**

a. E[composite] = E[ticket_path] + E[burnie_path] + E[dgnrs_path] + E[wwxrp_path]
b. For the purposes of MATH-05, the critical paths are tickets (ETH-equivalent value from price curve) and BURNIE (potentially high value). DGNRS and WWXRP are secondary.
c. State the composite EV as a percentage of input amount.
d. At 100% EV multiplier: the composite should be approximately 100% if the system is designed to break even at neutral score.

**6. EV at Each Multiplier Level**

Compute E[adjusted] = E[composite] * evMultiplier for:
- score = 0: multiplier = 80% -> E = composite * 0.80
- score = 6000: multiplier = 100% -> E = composite * 1.00
- score = 18250: multiplier = 117.5% -> E = composite * 1.175
- score = 30500: multiplier = 135% -> E = composite * 1.35

Write as Sections 1-4 of the findings document.
  </action>
  <verify>
    <automated>
      cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
      grep -n "BPS\|VARIANCE\|TIER\|BURNIE.*BPS\|TICKET.*BPS" contracts/modules/DegenerusGameLootboxModule.sol | head -40 | wc -l
    </automated>
  </verify>
  <done>
    All BPS constants extracted from contract source with exact values.
    EV computed for each of the four reward paths with full arithmetic shown.
    Composite EV computed at neutral and maximum multiplier levels.
    All value-denomination assumptions documented (tickets in price-curve value, BURNIE in token value).
  </done>
</task>

<task type="auto">
  <name>Task 2: Model per-level cap extraction limit and activity score cost; write MATH-05 verdict</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. Per-Level Cap Extraction Analysis**

a. From _applyEvMultiplierWithCap logic:
   - Cap = 10 ETH of raw input amount (NOT 10 ETH of benefit)
   - At 135% EV: 10 ETH input * 1.35 = 13.5 ETH output = 3.5 ETH benefit
   - After cap exhausted: all subsequent lootboxes at this level get 100% EV (no benefit)
b. Model the total extractable benefit across N levels:
   - Per level: max 3.5 ETH benefit (at max score)
   - Total across L levels: L * 3.5 ETH
   - But: reaching level L requires ticket purchases at each level. Is the ticket cost > 3.5 ETH per level at any point? (PriceLookupLib escalation means higher levels cost more per ticket)
c. Compute the break-even: at what level does the ticket cost per level exceed 3.5 ETH?
d. CRITICAL from Research Open Question #2: The cap tracks raw amount, NOT benefit delta. This means:
   - A 10 ETH lootbox at 135% EV uses the entire cap (10 ETH tracked)
   - The benefit is only 3.5 ETH but the cap is fully consumed
   - If the cap tracked benefit instead, you could process 10/3.5 = 2.86x more before cap exhaustion
   - Document which interpretation is implemented and confirm it is MORE conservative (safer for the protocol)

**2. Activity Score Cost Analysis**

Read `_playerActivityScoreInternal` in DegeneretteModule (lines ~1020-1093) to enumerate ALL score components with their caps.

For each component:
a. What is the maximum BPS contribution?
b. What is the minimum investment/effort to reach that maximum?
c. Is the investment recoverable (e.g., deity pass has some game value beyond score)?

Key components to trace:
- Deity pass holder bonus: expected 24000 BPS (80% of 30000). Cost: 24+ ETH for first pass.
- Quest streak bonus: what BPS cap? Cost: daily participation over time.
- Mint count bonus: what BPS cap? Cost: buying tickets.
- Affiliate bonus: what BPS cap? Cost: creating referrals.
- Whale bundle bonus: what BPS cap? Cost: 2.4-4 ETH per bundle.

Compute the MINIMUM COST to reach 305% activity score (30500 BPS).

**3. Extraction vs. Investment Analysis**

a. Total investment to reach 305% score: deity pass (24+ ETH) + other components
b. Maximum extraction per level: 3.5 ETH (from cap analysis)
c. How many levels of 3.5 ETH extraction needed to recoup investment?
   - 24 ETH / 3.5 ETH = ~7 levels of max extraction
   - But player must also buy tickets at each level, which is additional cost
d. Is this extraction guaranteed or probabilistic?
   - Lootbox rewards have variance (not every lootbox pays > 100%)
   - The 135% is an EV (expected value), not a guaranteed multiplier
   - Over many lootboxes the variance smooths out, but the cap limits total volume

**4. EV Multiplier Level-Advance Reset Concern**

From Research Pitfall #1:
- The cap is keyed on `currentLevel`, which resets when the player advances
- A player could theoretically extract 3.5 ETH benefit per level indefinitely
- BUT: advancing to the next level requires the entire game to advance (all players)
- A single player cannot control when levels advance
- And ticket costs escalate with level, increasing the cost of participation

**5. MATH-05 Final Verdict**

Synthesize:
a. Base EV at neutral score: ~100% (by design)
b. Maximum EV at 305% score: ~135%
c. Maximum benefit per level: 3.5 ETH
d. Cost to reach 305% score: 24+ ETH minimum
e. Guaranteed extraction? No — EV is probabilistic, not guaranteed
f. Can a player extract more than they invest through lootboxes alone? Model the total lifecycle:
   - Investment: deity pass (24 ETH) + ticket purchases + other costs
   - Extraction: sum of lootbox benefits across levels (3.5 ETH * levels played)
   - Break-even: requires ~7+ levels of max extraction
   - The game ends or the player must keep buying tickets, which is additional cost

MATH-05 Verdict: PASS/FAIL with complete reasoning.

Write the complete findings document with sections:
1. Per-Path EV Computation (from Task 1)
2. Composite EV Model (from Task 1)
3. Per-Level Cap Extraction Analysis
4. Activity Score Cost Analysis
5. Extraction vs. Investment Analysis
6. Level-Advance Cap Reset Analysis
7. MATH-05 Final Verdict
8. Findings (any issues rated by severity)
  </action>
  <verify>
    <automated>
      test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md && \
      grep -c "MATH-05\|extraction\|activity score\|per-level cap\|3.5 ETH\|135%" /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md
    </automated>
  </verify>
  <done>
    03b-03-FINDINGS-lootbox-ev-model.md exists and contains:
    - Complete per-path EV computation with exact BPS constants
    - Composite EV at neutral and maximum activity scores
    - Per-level cap extraction limit (3.5 ETH at max score)
    - Activity score component enumeration with cost analysis
    - Extraction vs. investment lifecycle model
    - Level-advance cap reset analysis
    - MATH-05 final verdict with complete reasoning
    - Any findings rated by severity
    - No contract files were modified
  </done>
</task>

</tasks>

<verification>
```bash
# Verify findings document exists and has substantive content
wc -l /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md

# Verify MATH-05 verdict present
grep -E "MATH-05.*(PASS|FAIL|Verdict)" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md

# Verify all four reward paths computed
grep -c "ticket.*EV\|BURNIE.*EV\|DGNRS.*EV\|WWXRP.*EV\|ticket.*path\|BURNIE.*path\|DGNRS.*path\|WWXRP.*path" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md

# Verify activity score cost analysis included
grep -c "deity pass\|quest streak\|activity score.*cost\|investment" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-03-FINDINGS-lootbox-ev-model.md
```
</verification>

<success_criteria>
- 03b-03-FINDINGS-lootbox-ev-model.md exists in the phase directory
- EV computed for all four reward paths using exact contract BPS constants
- Composite EV at neutral score is approximately 100%
- Composite EV at maximum score (305%) is confirmed <= 135%
- Per-level cap limits extraction to 3.5 ETH benefit at maximum score
- Activity score components enumerated with investment costs
- Total extraction vs. investment analysis shows the threshold
- MATH-05 verdict rendered with complete mathematical reasoning
- Any findings rated by severity
- No contract files were modified
</success_criteria>

<output>
After completion, create `.planning/phases/03b-vrf-dependent-modules/03b-03-SUMMARY.md` following the standard summary template.
</output>
