---
phase: 03c-supporting-mechanics-modules
plan: 04
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03c-supporting-mechanics-modules/03c-04-FINDINGS-degenerette-mintstreak-audit.md
autonomous: true
requirements: [MATH-08]

must_haves:
  truths:
    - "MintStreakUtils _recordMintStreakForLevel is idempotent per level (lastCompleted == mintLevel guard)"
    - "MintStreakUtils streak resets to 1 when levels are non-consecutive (gap detection confirmed)"
    - "MintStreakUtils uint24 overflow protection verified (streak < type(uint24).max check)"
    - "DegeneretteModule activity score calculation components are all bounded"
    - "DegeneretteModule _fullTicketPayout EV normalization is mathematically correct"
    - "DegeneretteModule ETH payout pool cap (10% of futurePool) is enforced per-spin, not per-bet"
    - "DegeneretteModule hero quadrant boost/penalty is EV-neutral per match count"
  artifacts:
    - path: ".planning/phases/03c-supporting-mechanics-modules/03c-04-FINDINGS-degenerette-mintstreak-audit.md"
      provides: "DegeneretteModule and MintStreakUtils audit findings"
      min_lines: 80
  key_links:
    - from: "contracts/modules/DegenerusGameMintStreakUtils.sol (_recordMintStreakForLevel)"
      to: "mintPacked_ storage"
      via: "MINT_STREAK_LAST_COMPLETED_SHIFT at bit 160"
      pattern: "MINT_STREAK_LAST_COMPLETED_SHIFT"
    - from: "contracts/modules/DegenerusGameDegeneretteModule.sol (_distributePayout)"
      to: "futurePrizePool"
      via: "ETH_WIN_CAP_BPS cap"
      pattern: "ETH_WIN_CAP_BPS"
---

<objective>
Audit DegeneretteModule symbol-roll bet mechanics and MintStreakUtils streak accounting. Verify streak idempotency, gap detection, and overflow protection. Verify activity score bounds, payout formula EV normalization, ETH pool cap enforcement, and hero quadrant multiplier neutrality.

Purpose: DegeneretteModule is the largest module (1176 lines) and handles multi-currency betting with complex payout formulas. MintStreakUtils feeds into activity score which affects lootbox EV. Streak accounting errors could inflate activity scores, creating economic extraction vectors.
Output: FINDINGS document covering both components
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
@contracts/modules/DegenerusGameDegeneretteModule.sol
@contracts/modules/DegenerusGameMintStreakUtils.sol
@contracts/libraries/BitPackingLib.sol
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit MintStreakUtils streak accounting correctness</name>
  <files>.planning/phases/03c-supporting-mechanics-modules/03c-04-FINDINGS-degenerette-mintstreak-audit.md</files>
  <action>
READ-ONLY AUDIT. Do not modify any contract files.

**Part A: MintStreakUtils (62 lines)**

1. **Idempotency per level**: Verify `_recordMintStreakForLevel` returns early when `lastCompleted == mintLevel`. This prevents a player from calling the function multiple times for the same level to inflate streak. Confirm the check uses `==` not `>=`.

2. **Consecutive detection**: When `lastCompleted + 1 == mintLevel`, streak increments. When `lastCompleted != 0 && lastCompleted + 1 != mintLevel`, streak resets to 1 (gap detected). When `lastCompleted == 0`, streak sets to 1 (first completion). Verify all three branches in the code.

3. **uint24 overflow protection**: Line 31 checks `if (streak < type(uint24).max)` before incrementing. In the unchecked block, `streak + 1` would overflow if streak == type(uint24).max. The guard prevents this. Verify the else branch returns `newStreak = streak` (keeps at max, does not wrap).

4. **Packed storage write**: Line 42-45 uses a combined mask to clear both MINT_STREAK_LAST_COMPLETED (shift 160) and LEVEL_STREAK (shift 48) in one operation, then ORs both new values. Verify:
   - MINT_STREAK_FIELDS_MASK correctly combines both fields
   - The OR operation places mintLevel at shift 160 and newStreak at shift 48
   - No adjacent field is corrupted by the mask

5. **_mintStreakEffective view function**: Verifies streak is still valid relative to currentMintLevel. If `currentMintLevel > lastCompleted + 1`, returns 0 (streak expired because a level was skipped). Confirm this logic is consistent with _recordMintStreakForLevel behavior.

6. **Caller analysis**: Grep for all call sites of _recordMintStreakForLevel. It should only be called from MintModule or DegeneretteModule when a player completes a level. Verify no path allows arbitrary callers to invoke it.

**Part B: DegeneretteModule**

7. **Activity score bounds**: Read _playerActivityScoreInternal. Enumerate all components that contribute to scoreBps:
   - Deity pass: flat 50*100 + 25*100 = 7500 BPS
   - Non-deity: streak contribution + levelCount contribution + quest streak + affiliate + pass active bonus
   - Verify each component has a cap or natural bound
   - Compute maximum possible scoreBps and verify it doesn't overflow uint16 (max 65535)
   - The activityScore stored in packed bet data is uint16. Confirm capping.

8. **_fullTicketPayout formula trace**: For a representative case (4 matches, 100% ROI, ETH bet):
   - basePayoutBps from _getBasePayoutBps (packed lookup table)
   - payout = (betAmount * basePayoutBps * effectiveRoi) / 1_000_000
   - evNum/evDen from _evNormalizationRatio (product of per-quadrant probability ratios)
   - payout = (payout * evNum) / evDen
   - Hero multiplier if applicable
   Verify no intermediate overflow for max betAmount (uint128 max). betAmount * basePayoutBps * effectiveRoi: uint128 * uint256 * uint256. basePayoutBps max is ~100000 for 8 matches. effectiveRoi max is ~30000. Product: 2^128 * 10^5 * 3*10^4 = ~10^53. uint256 max = ~10^77. SAFE.

9. **ETH payout pool cap**: In _distributePayout, ETH payouts are split 25/75 (ETH/lootbox). The ETH portion is capped at 10% of futurePrizePool. Verify:
   - This cap is per-spin (called inside the spin loop), not per-bet
   - After capping, ethPortion is subtracted from futurePrizePool. The cap ensures ethPortion <= pool*10% < pool, so the subtraction cannot underflow
   - Multiple spins in one bet could each extract up to 10% of the REMAINING pool (which shrinks each spin). Document whether this creates an issue at max spins (10).

10. **Hero quadrant EV neutrality**: The hero boost is applied when both color AND symbol match in the hero quadrant. Penalty is applied otherwise. The system claims EV neutrality per match count: `P(hero|M)*boost(M) + (1-P(hero|M))*penalty = 1`. Read the HERO_BOOST_PACKED and HERO_PENALTY constants. For at least one match count (e.g., M=4), compute P(hero match | 4 total matches) and verify boost*P + penalty*(1-P) = HERO_SCALE.

Document all findings with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03c-supporting-mechanics-modules/03c-04-FINDINGS-degenerette-mintstreak-audit.md && grep -c "Part" .planning/phases/03c-supporting-mechanics-modules/03c-04-FINDINGS-degenerette-mintstreak-audit.md</automated>
  </verify>
  <done>
    - MintStreakUtils: idempotency, gap detection, overflow protection all verified
    - MintStreakUtils: packed storage write verified correct with no field corruption
    - DegeneretteModule: activity score bounded with max value documented
    - DegeneretteModule: _fullTicketPayout overflow analysis completed
    - DegeneretteModule: ETH pool cap confirmed per-spin enforcement
    - DegeneretteModule: hero quadrant EV neutrality verified for at least one match count
    - FINDINGS document exists
  </done>
</task>

</tasks>

<verification>
- FINDINGS document covers both MintStreakUtils and DegeneretteModule
- Streak accounting verified with all three branches (first, consecutive, gap)
- Activity score max value computed
- ETH pool cap enforcement scope (per-spin) documented
- No contract files were modified
</verification>

<success_criteria>
- MintStreakUtils fully verified (5 checks)
- DegeneretteModule payout formula traced with overflow analysis
- ETH pool cap enforcement scope documented
- Hero quadrant EV neutrality proven for at least one match count
</success_criteria>

<output>
After completion, create `.planning/phases/03c-supporting-mechanics-modules/03c-04-SUMMARY.md`
</output>
