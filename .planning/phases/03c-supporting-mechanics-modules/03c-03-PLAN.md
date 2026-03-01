---
phase: 03c-supporting-mechanics-modules
plan: 03
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03c-supporting-mechanics-modules/03c-03-FINDINGS-boon-decimator-audit.md
autonomous: true
requirements: [MATH-08]

must_haves:
  truths:
    - "Every consumeXxxBoon function clears all associated state variables (bps, timestamp, deityDay) atomically"
    - "checkAndClearExpiredBoon handles all 10+ boon types with correct expiry logic"
    - "Deity-granted boons use day-based expiry and lootbox-rolled boons use timestamp-based expiry consistently"
    - "DecimatorModule recordDecBurn bucket migration correctly removes from old and adds to new aggregate"
    - "Decimator uint192 burn saturation prevents overflow"
    - "_decEffectiveAmount multiplier cap split logic handles all edge cases (remaining=0, remaining=1 wei, maxMultBase rounding)"
    - "Decimator 4-bit subbucket packing cannot overflow (max sub value = 11 < 16)"
    - "Double-claim prevention via e.claimed=1 is effective across all claim paths"
  artifacts:
    - path: ".planning/phases/03c-supporting-mechanics-modules/03c-03-FINDINGS-boon-decimator-audit.md"
      provides: "BoonModule and DecimatorModule audit findings"
      min_lines: 100
  key_links:
    - from: "contracts/modules/DegenerusGameBoonModule.sol (consumeCoinflipBoon)"
      to: "coinflipBoonBps, coinflipBoonTimestamp, deityCoinflipBoonDay"
      via: "triple state clear"
      pattern: "coinflipBoonBps.*= 0.*coinflipBoonTimestamp.*= 0.*deityCoinflipBoonDay.*= 0"
    - from: "contracts/modules/DegenerusGameDecimatorModule.sol (_decSubbucketFor)"
      to: "keccak256(player, lvl, bucket) % bucket"
      via: "deterministic subbucket assignment"
      pattern: "_decSubbucketFor"
---

<objective>
Audit BoonModule for boon consumption completeness and expiry consistency, and DecimatorModule for burn tracking correctness, multiplier cap arithmetic, subbucket packing safety, and double-claim prevention.

Purpose: BoonModule manages 10+ distinct boon types with two different expiry mechanisms (day-based vs timestamp-based). Incomplete clearing could leave stale boon state that enables unintended discounts. DecimatorModule uses 4-bit packing for subbuckets and uint192 saturation -- both require boundary verification.
Output: FINDINGS document covering both modules
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
@contracts/modules/DegenerusGameBoonModule.sol
@contracts/modules/DegenerusGameDecimatorModule.sol
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit BoonModule consumption completeness and expiry consistency</name>
  <files>.planning/phases/03c-supporting-mechanics-modules/03c-03-FINDINGS-boon-decimator-audit.md</files>
  <action>
READ-ONLY AUDIT. Do not modify any contract files.

**Part A: BoonModule Audit**

1. **Consumption completeness**: For each consume function (consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost, consumeActivityBoon), verify that ALL associated state variables are zeroed on consumption:
   - consumeCoinflipBoon: must clear coinflipBoonBps, coinflipBoonTimestamp, deityCoinflipBoonDay
   - consumePurchaseBoost: must clear purchaseBoostBps, purchaseBoostTimestamp, deityPurchaseBoostDay
   - consumeDecimatorBoost: must clear decimatorBoostBps, deityDecimatorBoostDay (note: no timestamp var for decimator?)
   - consumeActivityBoon: must clear activityBoonPending, activityBoonTimestamp, deityActivityBoonDay

   For each function, trace every return path and confirm all three state variables are zeroed on EVERY path that consumes or expires the boon.

2. **Expiry logic consistency**: Verify the two expiry mechanisms:
   - Deity-granted boons: `deityDay != 0 && deityDay != currentDay` (same-day expiry)
   - Lootbox-rolled boons: `ts > 0 && nowTs > ts + EXPIRY_SECONDS` (duration-based)
   Confirm each consume function correctly applies the right mechanism for its boon source. Document any boon type that could use BOTH mechanisms.

3. **checkAndClearExpiredBoon completeness**: Enumerate all boon types handled. Confirm the function covers:
   - Coinflip boon (coinflipBoonBps)
   - Lootbox boosts x3 (25%, 15%, 5%)
   - Purchase boost
   - Decimator boost
   - Whale boon
   - Lazy pass boon
   - Deity pass boon
   - Activity boon
   Count: should be 10 distinct boon categories. Verify return value (`hasAnyBoon`) correctly OR's all surviving boon states.

4. **Stale boon edge case**: Can a deity-granted boon survive across day boundaries if `_simulatedDayIndex()` returns 0? Check if currentDay==0 is handled safely in the `deityDay != currentDay` comparison.

5. **consumeActivityBoon levelCount overflow**: Line 340-342 checks `countSum > type(uint24).max` and caps. Verify the cap is applied correctly and that the setPacked call uses the capped value.

**Part B: DecimatorModule Audit**

6. **recordDecBurn bucket migration**: When a player provides a strictly better (lower) bucket, verify:
   - Old subbucket aggregate is decremented by prevBurn via _decRemoveSubbucket
   - New subbucket is computed via _decSubbucketFor
   - If prevBurn != 0, new subbucket aggregate is incremented via _decUpdateSubbucket
   - Player's entry is updated with new bucket/subBucket
   Trace line-by-line to confirm no aggregate leak (burn removed from old but not added to new, or vice versa).

7. **uint192 saturation**: Line 259-261 `if (updated > type(uint192).max) updated = type(uint192).max`. Verify `prevBurn + effectiveAmount` cannot produce a value that, when saturated, creates inconsistency between the player entry and the subbucket aggregate. Specifically, the delta `newBurn - prevBurn` is what gets added to the aggregate. If saturation kicks in, delta = type(uint192).max - prevBurn, which is smaller than effectiveAmount. This is correct. Confirm.

8. **_decEffectiveAmount edge cases**: Verify the multiplier cap split logic:
   - Edge: prevBurn == DECIMATOR_MULTIPLIER_CAP: returns baseAmount (1x). Correct.
   - Edge: prevBurn == DECIMATOR_MULTIPLIER_CAP - 1: remaining=1, fullEffective > remaining, maxMultBase = (1 * 10000) / multBps. If multBps = 20000 (2x), maxMultBase = 0.5 rounds to 0. Then multiplied = 0, effectiveAmount = baseAmount (entire at 1x). Correct.
   - Edge: multBps = 10001 (just above 1x): verify formula produces slightly above baseAmount.
   - Edge: baseAmount = 0: returns 0 immediately. Correct.

9. **4-bit subbucket packing**: _packDecWinningSubbucket uses `(denom - 2) << 2` for shift. For denom=2, shift=0. For denom=12, shift=40. Total bits used = 44 (fits in uint64). _decSubbucketFor returns `hash % bucket` where bucket (denom) is max 12. So max sub = 11 = 0b1011 = 4 bits. Sub=11 fits in 4-bit mask 0xF. Confirm no value > 15 can appear.

10. **Double-claim prevention**: In _decClaimable and claimDecimatorWinnings, verify `e.claimed != 0` prevents re-entry. Trace where `e.claimed` is set to 1 (should be in the claim function after payout). Verify no path can reach payout without setting claimed.

Document all findings with severity ratings.
  </action>
  <verify>
    <automated>test -f .planning/phases/03c-supporting-mechanics-modules/03c-03-FINDINGS-boon-decimator-audit.md && grep -c "## " .planning/phases/03c-supporting-mechanics-modules/03c-03-FINDINGS-boon-decimator-audit.md</automated>
  </verify>
  <done>
    - All 4 consume functions verified for complete state clearing
    - checkAndClearExpiredBoon verified to cover all 10 boon categories
    - Expiry consistency (day vs timestamp) documented per boon type
    - DecimatorModule bucket migration verified leak-free
    - uint192 saturation confirmed consistent with aggregate tracking
    - _decEffectiveAmount edge cases verified
    - 4-bit subbucket packing confirmed safe (max sub=11 < 16)
    - Double-claim prevention confirmed effective
    - FINDINGS document exists
  </done>
</task>

</tasks>

<verification>
- FINDINGS document covers both BoonModule and DecimatorModule
- Every boon type in checkAndClearExpiredBoon is enumerated
- DecimatorModule arithmetic edge cases computed with concrete values
- No contract files were modified
</verification>

<success_criteria>
- BoonModule consumption completeness confirmed for all 4 consume functions
- DecimatorModule burn tracking verified: no aggregate leak on migration
- 4-bit subbucket packing confirmed safe with arithmetic proof
- All findings severity-rated
</success_criteria>

<output>
After completion, create `.planning/phases/03c-supporting-mechanics-modules/03c-03-SUMMARY.md`
</output>
