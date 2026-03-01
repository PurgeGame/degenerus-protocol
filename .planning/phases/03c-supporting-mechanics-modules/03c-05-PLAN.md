---
phase: 03c-supporting-mechanics-modules
plan: 05
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md
autonomous: true
requirements: [MATH-07]

must_haves:
  truths:
    - "Base rewardPercent range is [50, 150] covering the documented 50-150% range"
    - "Normal roll range is [78, 115] via (seedWord % 38) + 78"
    - "Presale bonus +6 can push maximum rewardPercent to 156 -- documented whether this is intentional"
    - "_applyEvToRewardPercent correctly clamps to 0 when adjustedBps goes negative"
    - "_applyEvToRewardPercent cannot overflow uint16 (max 65535)"
    - "Payout formula (stake + stake*rewardPercent/100) at rewardPercent=0 returns just stake (no loss)"
    - "Payout formula at rewardPercent=150 returns 2.5x stake correctly"
    - "Unresolved day detection (rewardPercent==0 && !win) does not collide with legitimate win at rewardPercent=0"
    - "View function _viewClaimableCoin uses same formula as claim loop -- no divergence"
  artifacts:
    - path: ".planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md"
      provides: "BurnieCoinflip bonus range audit findings"
      min_lines: 80
  key_links:
    - from: "contracts/BurnieCoinflip.sol (processCoinflipPayouts)"
      to: "coinflipDayResult mapping"
      via: "CoinflipDayResult{rewardPercent, win}"
      pattern: "coinflipDayResult.*CoinflipDayResult"
    - from: "contracts/BurnieCoinflip.sol (_applyEvToRewardPercent)"
      to: "rewardPercent"
      via: "BPS conversion and delta adjustment"
      pattern: "_applyEvToRewardPercent"
---

<objective>
Audit BurnieCoinflip's bonus range logic, focusing on edge cases at the 50% and 150% boundaries, presale bonus pushing above 150%, EV adjustment edge cases, and payout formula correctness. Verify the claim path uses the same formula as the view function.

Purpose: MATH-07 requires confirming "Coinflip 50-150% bonus range is correctly bounded -- edge cases at 50% and 150% do not over/underpay." The presale bonus (+6) can push rewardPercent to 156%, which may or may not violate the documented range. The _applyEvToRewardPercent function can push rewardPercent to 0 on a win day, creating an edge case where payout equals just the principal.
Output: FINDINGS document with boundary analysis
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
@contracts/BurnieCoinflip.sol
</context>

<tasks>

<task type="auto">
  <name>Task 1: Trace processCoinflipPayouts reward generation and verify boundary behavior</name>
  <files>.planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md</files>
  <action>
READ-ONLY AUDIT. Do not modify any contract files.

**Section 1: Base Reward Percent Generation (processCoinflipPayouts)**

1. Read processCoinflipPayouts (line 794+). Trace the full rewardPercent generation:
   - seedWord = keccak256(rngWord, epoch) -- unique per day
   - roll = seedWord % 20
   - roll==0 (5% chance): rewardPercent = 50
   - roll==1 (5% chance): rewardPercent = 150
   - roll>=2 (90% chance): rewardPercent = (seedWord % 38) + 78 = [78, 115]

   Note: seedWord is reused for both roll and normal-range computation. When roll>=2, `seedWord % COINFLIP_EXTRA_RANGE` is computed. But seedWord was already used for `seedWord % 20` to determine roll. These are DIFFERENT modular operations on the same seed. The roll check only branches on the mod-20 result, then the mod-38 uses the full seedWord. This means seedWord values that give roll>=2 map to a non-uniform subset of mod-38 outcomes (since mod-20 and mod-38 share the same seed). Analyze whether this creates any meaningful bias in the [78,115] distribution. For security audit purposes, any bias < 1% is informational.

2. Verify the range table:
   | Condition | rewardPercent | Probability |
   |-----------|---------------|-------------|
   | roll==0 | 50 | 5% |
   | roll==1 | 150 | 5% |
   | roll>=2 | 78-115 | 90% |

   All values within [50, 150]. PASS for base range.

**Section 2: Presale Bonus**

3. Read lines 817-821. If `bonusFlip && lootboxPresaleActive`, rewardPercent += 6 (unchecked).
   - Lucky roll + presale: 150 + 6 = 156. This EXCEEDS the documented 150% range.
   - Unlucky roll + presale: 50 + 6 = 56.
   - Normal roll + presale: [78, 115] + 6 = [84, 121].

   Document whether MATH-07's "50-150% range" refers to the base range (before adjustments) or the final range (after all adjustments). The NatSpec comments say "50% bonus (1.5x total)" and "150% bonus (2.5x total)" for the base range. Presale is a separate intentional bonus. Rate this as INFORMATIONAL if the 50-150% refers to base range, or LOW if it should cap the final value.

4. Note: presaleBonus and EV adjustment are mutually exclusive (line 824: `if (bonusFlip && !presaleBonus)`). So rewardPercent is either: base, base+6 (presale), or EV-adjusted. Never both presale and EV-adjusted.

**Section 3: EV Adjustment (_applyEvToRewardPercent)**

5. Read _applyEvToRewardPercent (line 1117-1131). Trace the formula:
   - targetRewardBps = BPS_DENOMINATOR + (evBps * 2) = 10000 + evBps*2
   - deltaBps = targetRewardBps - COINFLIP_REWARD_MEAN_BPS = 10000 + evBps*2 - 9685
   - adjustedBps = rewardPercent * 100 + deltaBps
   - If adjustedBps <= 0: return 0
   - rounded = (adjustedBps + 50) / 100
   - If rounded > uint16 max: return uint16 max

   Compute boundary values:
   - evBps range: from _coinflipTargetEvBps. Read that function. COINFLIP_EV_EQUAL_BPS = 0, COINFLIP_EV_TRIPLE_BPS = 300. The function interpolates between these based on prevTotal/currentTotal ratio. So evBps is in [0, 300].
   - At evBps=0: deltaBps = 10000 - 9685 = 315. adjustedBps = rewardPercent*100 + 315. At rewardPercent=50: 5315, rounded=53. At rewardPercent=150: 15315, rounded=153.
   - At evBps=300: deltaBps = 10600 - 9685 = 915. adjustedBps = rewardPercent*100 + 915. At rewardPercent=50: 5915, rounded=59. At rewardPercent=150: 15915, rounded=159.

   Can adjustedBps go negative? Only if deltaBps < -rewardPercent*100. Since deltaBps >= 315 (evBps >= 0), and rewardPercent >= 50, adjustedBps >= 5315. So adjustedBps CANNOT go negative when evBps is in [0, 300]. The clamp to 0 is a safety net.

   BUT: what if _coinflipTargetEvBps could return negative evBps? Read the interpolation function. The range is [COINFLIP_EV_EQUAL_BPS, COINFLIP_EV_TRIPLE_BPS] = [0, 300]. Both endpoints are >= 0. But check: could prevTotal > currentTotal produce a ratio > COINFLIP_RATIO_BPS_TRIPLE? If so, the interpolation might extrapolate beyond 300. Read the clamp logic. Document whether evBps can go negative or exceed 300.

6. uint16 overflow: max adjustedBps = 150*100 + 915 = 15915. rounded = 159. Well within uint16 (65535). SAFE.

**Section 4: Payout Formula Verification**

7. Read the claim loop (around line 505-535). The payout formula:
   ```
   payout = stake + (stake * rewardPercent) / 100
   ```
   - At rewardPercent=0: payout = stake + 0 = stake. Player gets principal back. Not a loss.
   - At rewardPercent=50: payout = stake + stake*50/100 = 1.5x stake.
   - At rewardPercent=100: payout = stake + stake = 2x stake.
   - At rewardPercent=150: payout = stake + stake*150/100 = 2.5x stake.
   - At rewardPercent=156 (max presale): payout = stake + stake*156/100 = 2.56x stake.

   Verify no integer overflow: stake is coinflipBalance[day][player] (uint256). stake * 150 max: if stake is 1e30 (extremely large), product is 1.5e32. Safe in uint256.

8. **Unresolved day detection**: Line 511: `if (rewardPercent == 0 && !win)` is used to detect unresolved days (skip). But could a resolved day have rewardPercent=0 AND win=false? From processCoinflipPayouts, rewardPercent is always set to >= 50 before adjustments, and _applyEvToRewardPercent can return 0. So a resolved day CAN have rewardPercent=0 if EV adjustment clamps it. But if win=false, the claim path should return principal anyway (on a loss day, payout = 0 or depends on loss handling). Trace the full loss path to confirm no collision between "unresolved" and "resolved with rewardPercent=0 and loss=true".

9. **View/claim consistency**: Read _viewClaimableCoin and the claim loop. Verify both use the same formula: `stake + (stake * rewardPercent) / 100` for wins, and the same loss handling. Any divergence means view shows different amount than actual claim.

**Section 5: Win/Loss Determination**

10. Read line 832: `bool win = (rngWord & 1) == 1`. This uses the ORIGINAL rngWord (before keccak mixing), not seedWord. Verify this is intentional and independent of the reward percent generation (which uses seedWord = keccak256(rngWord, epoch)). The LSB of VRF output is uniformly distributed, so win probability is exactly 50%. SAFE.

Document all findings with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md && grep -c "Section" .planning/phases/03c-supporting-mechanics-modules/03c-05-FINDINGS-coinflip-bonus-range.md</automated>
  </verify>
  <done>
    - Base range [50, 150] verified for 50-150% documented range
    - Presale +6 edge case documented (max 156%) with intent assessment
    - _applyEvToRewardPercent boundary behavior computed at all extreme inputs
    - Payout formula verified at rewardPercent = 0, 50, 100, 150, 156
    - Unresolved day detection collision analysis completed
    - View/claim formula consistency verified
    - Win/loss independence from reward percent generation confirmed
    - FINDINGS document exists with all 5 sections
  </done>
</task>

</tasks>

<verification>
- FINDINGS document contains all 5 sections with concrete arithmetic
- MATH-07 is addressed with a clear PASS/FAIL/CONDITIONAL determination
- Presale 156% edge case has an explicit severity rating and intent assessment
- No contract files were modified
</verification>

<success_criteria>
- MATH-07 determination documented: base range [50,150] confirmed, adjustments documented
- _applyEvToRewardPercent boundary values computed
- Payout formula verified at all boundary rewardPercent values
- Unresolved day detection verified collision-free
</success_criteria>

<output>
After completion, create `.planning/phases/03c-supporting-mechanics-modules/03c-05-SUMMARY.md`
</output>
