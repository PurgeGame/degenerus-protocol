---
phase: 03b-vrf-dependent-modules
plan: 03b-04
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md
autonomous: true
requirements:
  - MATH-06

must_haves:
  truths:
    - "The commit-reveal pattern is confirmed: _placeFullTicketBetsCore requires lootboxRngWordByIndex[index] == 0 (word unknown), resolution requires lootboxRngWordByIndex[index] != 0 (word known)"
    - "Activity score is confirmed snapshotted at bet time and read from packed storage at resolution time — no recalculation path exists"
    - "The ROI curve (_roiBpsFromScore) is traced through all three segments: quadratic 90-95% (0-75%), linear 95-99.5% (75-255%), linear 99.5-99.9% (255-305%)"
    - "The EV normalization ratio (_evNormalizationRatio) product-of-4-ratios math is verified to produce equal EV regardless of trait selection"
    - "Degenerette ETH payout cap (25% ETH capped at 10% of futurePrizePool, 75% as lootbox) is traced with the futurePrizePool depletion concern addressed"
    - "No timing window exists where a bet can be placed with knowledge of the VRF word that will resolve it"
    - "The lootboxRngIndex lifecycle is traced: when it increments, who can request the word, and when the word is stored"
  artifacts:
    - path: ".planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md"
      provides: "Complete degenerette bet timing audit, commit-reveal verification, ROI curve trace, EV normalization verification, MATH-06 verdict"
      contains: "MATH-06"
  key_links:
    - from: "contracts/modules/DegenerusGameDegeneretteModule.sol:_placeFullTicketBetsCore"
      to: "lootboxRngWordByIndex[index]"
      via: "Guard: reverts RngNotReady if word != 0 at bet time"
      pattern: "lootboxRngWordByIndex\\[index\\].*!=.*0.*revert"
    - from: "contracts/modules/DegenerusGameDegeneretteModule.sol:_resolveFullTicketBet"
      to: "lootboxRngWordByIndex[index]"
      via: "Read: requires word != 0 at resolution time"
      pattern: "lootboxRngWordByIndex\\[.*\\]"
    - from: "contracts/modules/DegenerusGameDegeneretteModule.sol:_placeFullTicketBetsCore"
      to: "packed bet storage"
      via: "Activity score snapshot packed into bet at FT_ACTIVITY_SHIFT=220"
      pattern: "FT_ACTIVITY_SHIFT"
---

<objective>
Audit the DegenerusGameDegeneretteModule (~1176 lines) bet placement and resolution timing to verify the commit-reveal pattern prevents any form of foreknowledge exploitation. Verify the ROI curve produces the documented payout scaling, the EV normalization ensures equal EV across trait selections, and the ETH payout cap protects the futurePrizePool.

Purpose: MATH-06 requires proving that no bet timing relative to VRF creates an advantaged position. This is the critical security property of the degenerette system: bets must be placed before the outcome is determinable, and resolution must occur after the VRF word is known. Any gap in this commit-reveal pattern would allow risk-free extraction.

Output: `03b-04-FINDINGS-degenerette-bet-timing.md` containing the complete timing audit, ROI curve verification, EV normalization analysis, and MATH-06 verdict.
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
<!-- Primary audit target: contracts/modules/DegenerusGameDegeneretteModule.sol (1176 lines) -->

Commit-reveal guards (from research):
  Bet placement (line ~487-500):
    lootboxRngIndex -> current epoch
    Guard: if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()
    Activity score snapshot: uint16 activityScore = uint16(_playerActivityScoreInternal(player))
    Packed into bet storage

  Resolution (line ~617-623):
    rngWord = lootboxRngWordByIndex[index]
    if (rngWord == 0) revert RngNotReady()

  This creates: bet when word==0, resolve when word!=0

VRF word derivation (from research):
  keccak256(rngWord, index, QUICK_PLAY_SALT) --> result ticket seed (spin 0)
  keccak256(rngWord, index, spinIdx, QUICK_PLAY_SALT) --> result ticket seed (spin 1+)
  DegenerusTraitUtils.packedTraitsFromSeed(seed) --> result ticket
  _countMatches(playerTicket, resultTicket) --> match count (0-8)
  _fullTicketPayout(matches, ROI, EV normalization) --> payout

ROI curve (_roiBpsFromScore):
  Quadratic 90%->95% (score 0 to 7500 BPS = 0% to 75%)
  Linear 95%->99.5% (score 7500 to 25500 BPS = 75% to 255%)
  Linear 99.5%->99.9% (score 25500 to 30500 BPS = 255% to 305%)

Activity score snapshot (Research Pitfall #2):
  Packed at bet time: FT_ACTIVITY_SHIFT=220, 16 bits
  Read at resolution: uint16 activityScore = uint16((packed >> FT_ACTIVITY_SHIFT) & MASK_16)

ETH payout cap (Research Open Question #4):
  25% ETH (capped at 10% of futurePrizePool), 75% as lootbox credit
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Verify commit-reveal pattern, activity score snapshot, and lootboxRngIndex lifecycle</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

Read `contracts/modules/DegenerusGameDegeneretteModule.sol` in its entirety (~1176 lines).

**1. Commit-Reveal Pattern Verification**

a. Locate `_placeFullTicketBetsCore` and trace:
   - How is `lootboxRngIndex` read? Is it a storage variable or computed?
   - What is the exact guard? `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady()` — verify this is checking that the word does NOT yet exist
   - Can a player place a bet when index == 0? (Research says `if (index == 0) revert E()`)
   - After the guard passes, what data is stored in the bet? (index, player ticket, amount, activity score)

b. Locate the resolution function (`_resolveFullTicketBet` or equivalent) and trace:
   - How is the bet's index retrieved?
   - What is the exact guard? `rngWord = lootboxRngWordByIndex[index]; if (rngWord == 0) revert RngNotReady()` — verify this requires the word to exist
   - Is the bet's stored index used (not the current lootboxRngIndex)?

c. The critical question: can a player place a bet for index N, then before the VRF word for N is stored, somehow learn the word?
   - The VRF word is stored by rawFulfillRandomWords callback from Chainlink (async, separate tx)
   - The word is stored atomically — there is no partial state
   - The player cannot call rawFulfillRandomWords (only the coordinator can)
   - Verdict: is foreknowledge impossible?

**2. lootboxRngIndex Lifecycle**

a. Where is lootboxRngIndex incremented? (Expected: during daily advanceGame when a new lootbox RNG is requested)
b. Where is lootboxRngWordByIndex[index] written? (Expected: in rawFulfillRandomWords callback)
c. Trace the full lifecycle:
   - advanceGame -> requestLootboxRng -> VRF request submitted, lootboxRngIndex incremented
   - Chainlink fulfills -> rawFulfillRandomWords -> lootboxRngWordByIndex[index] = word
   - Players can bet during the window between increment and fulfillment (word == 0)
   - After fulfillment (word != 0), no new bets on this index; existing bets can be resolved
d. Is there a race condition? Can a player see the fulfillment tx in mempool and front-run with a bet?
   - NO: the bet requires word == 0, but the fulfillment sets word != 0
   - A front-run bet would be placed BEFORE the fulfillment, so word is still 0 — the bet is valid but the player still doesn't know the word

**3. Activity Score Snapshot Verification**

a. At bet placement: locate where `_playerActivityScoreInternal(player)` is called and the result is packed into the bet storage.
b. At resolution: locate where the score is READ from the packed bet storage (not recalculated).
c. Verify the field position: FT_ACTIVITY_SHIFT, MASK_16 — confirm these extract the correct 16 bits.
d. Can a player manipulate their activity score between bet and resolution?
   - Even if they can, does it matter? (Answer: NO, because the snapshot is used at resolution)
   - Verify there is NO code path that recalculates the score at resolution time

**4. Bet Currency and Amount Validation**

a. What currencies can degenerette bets use? (ETH, BURNIE, WWXRP?)
b. How is the minimum bet enforced? (`_validateMinBet`)
c. How is the maximum spin count enforced? (`MAX_SPINS_PER_BET`)
d. Can a player place a zero-amount bet?

Write as Section 1 of the findings document.
  </action>
  <verify>
    <automated>
      cd /home/zak/Dev/PurgeGame/degenerus-contracts && \
      grep -n "lootboxRngWordByIndex\|lootboxRngIndex\|RngNotReady\|_placeFullTicketBetsCore\|_resolveFullTicketBet\|FT_ACTIVITY_SHIFT" contracts/modules/DegenerusGameDegeneretteModule.sol | wc -l
    </automated>
  </verify>
  <done>
    Commit-reveal pattern verified with exact line numbers for both guards.
    lootboxRngIndex lifecycle fully traced (increment, write, bet window).
    Activity score snapshot confirmed at bet time and read from storage at resolution.
    No recalculation path found at resolution time.
    Front-running analysis completed.
  </done>
</task>

<task type="auto">
  <name>Task 2: Verify ROI curve, EV normalization math, ETH payout cap, and futurePrizePool safety; write MATH-06 verdict</name>
  <files>.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md</files>
  <action>
READ-ONLY audit. Do NOT modify any contract files.

**1. ROI Curve Verification (_roiBpsFromScore)**

a. Locate `_roiBpsFromScore` function. Read it completely.
b. Verify the three segments:
   - Segment 1 (score 0 to 7500 BPS): Quadratic from 90% to 95%. Verify the quadratic formula.
   - Segment 2 (score 7500 to 25500 BPS): Linear from 95% to 99.5%. Verify slope.
   - Segment 3 (score 25500 to 30500 BPS): Linear from 99.5% to 99.9%. Verify slope.
   - Score > 30500: capped at 99.9%.
c. Spot-check numeric values:
   - score = 0: should return 9000 BPS (90%)
   - score = 7500: should return 9500 BPS (95%)
   - score = 25500: should return 9950 BPS (99.5%)
   - score = 30500: should return 9990 BPS (99.9%)
d. Check for integer division precision loss at segment boundaries.
e. The ROI represents the house edge: at 90% ROI, the house keeps 10%. At 99.9%, the house keeps 0.1%.

**2. EV Normalization (_evNormalizationRatio)**

a. Locate `_evNormalizationRatio` function. This is a product-of-4-ratios calculation that ensures equal EV regardless of which traits a player selects for their ticket.
b. Understand the problem it solves: different trait selections have different match probabilities (some traits are more common than others). Without normalization, selecting rare traits would have higher EV.
c. Verify the ratio computation:
   - For each of the 4 trait buckets: compute the ratio of total traits to selected traits
   - Multiply the 4 ratios together
   - This gives a normalization factor that scales the payout to equalize EV
d. Check for overflow: 4 ratios multiplied together could be large. What are the maximum values?
   - Each bucket has 8, 9, or 10 traits. Ratio is at most bucket_size / 1 = 10.
   - Product of 4: max 10^4 = 10,000. This fits in uint256.
e. Check for division truncation: the final payout divides by this normalization. Significant precision loss?

**3. Match Count and Payout Verification**

a. Locate `_countMatches` — how does it compare playerTicket to resultTicket?
b. Locate `_fullTicketPayout` — how does match count (0-8) map to payout?
   - 0 matches: 0 payout (total loss)
   - 8 matches: maximum jackpot
   - Intermediate: scaled by match count
c. Verify the payout formula accounts for ROI and EV normalization.
d. Can a player with 8 matches extract more than the futurePrizePool?

**4. ETH Payout Cap and futurePrizePool Safety**

a. Locate the ETH payout path for degenerette wins.
b. Verify the split: 25% paid in ETH, 75% credited as lootbox.
c. Verify the ETH portion cap: capped at 10% of futurePrizePool.
d. Research Open Question #4: Can a sequence of degenerette jackpot wins drain futurePrizePool to zero?
   - If capped at 10% per payout, the pool decreases geometrically: pool * 0.9^N after N max-cap payouts
   - This converges to zero but never reaches it — is there a minimum balance guard?
   - What happens when futurePrizePool approaches 0? All payouts become lootbox-only?
e. Can a player grief by placing many small bets to drain the pool in small increments?

**5. Additional Timing Checks**

a. Can a player cancel or modify a bet after placement but before resolution?
b. Can a player resolve someone else's bet? (Operator permissions?)
c. What happens if the VRF word for an index is never fulfilled? (Bet stuck forever or timeout?)
d. Can a player have multiple concurrent bets on the same index?

**6. Write Complete Findings Document**

Sections:
1. Commit-Reveal Pattern Verification (from Task 1)
2. lootboxRngIndex Lifecycle Trace
3. Activity Score Snapshot Verification
4. ROI Curve Verification (all three segments)
5. EV Normalization Math
6. Match Count and Payout Formula
7. ETH Payout Cap and futurePrizePool Safety
8. Additional Timing and Safety Checks
9. MATH-06 Verdict: Bet resolution timing safety
10. Findings (any issues rated by severity)
  </action>
  <verify>
    <automated>
      test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md && \
      grep -c "MATH-06\|commit-reveal\|_roiBpsFromScore\|_evNormalizationRatio\|futurePrizePool" /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md
    </automated>
  </verify>
  <done>
    03b-04-FINDINGS-degenerette-bet-timing.md exists and contains:
    - Commit-reveal pattern verified with both guards traced
    - lootboxRngIndex lifecycle fully traced
    - Activity score snapshot confirmed (no recalculation at resolution)
    - ROI curve verified at all segment boundaries
    - EV normalization product-of-4-ratios verified
    - ETH payout cap and futurePrizePool depletion analysis
    - MATH-06 verdict with complete reasoning
    - Any findings rated by severity
    - No contract files were modified
  </done>
</task>

</tasks>

<verification>
```bash
# Verify findings document exists
test -f /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md && echo "File exists"

# Verify MATH-06 verdict present
grep -E "MATH-06.*(PASS|FAIL|Verdict)" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md

# Verify commit-reveal analysis present
grep -c "commit-reveal\|foreknowledge\|RngNotReady\|lootboxRngWordByIndex" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md

# Verify ROI curve verified
grep -c "_roiBpsFromScore\|90%\|95%\|99.5%\|99.9%" \
  /home/zak/Dev/PurgeGame/degenerus-contracts/.planning/phases/03b-vrf-dependent-modules/03b-04-FINDINGS-degenerette-bet-timing.md
```
</verification>

<success_criteria>
- 03b-04-FINDINGS-degenerette-bet-timing.md exists in the phase directory
- Commit-reveal pattern confirmed with exact guards (word==0 at bet, word!=0 at resolve)
- lootboxRngIndex lifecycle traced (increment, fulfillment, bet window)
- Activity score snapshot confirmed at bet time, read from storage at resolution
- ROI curve verified at all segment boundaries with numeric spot-checks
- EV normalization product-of-4-ratios verified for correctness
- ETH payout cap traced with futurePrizePool depletion analysis
- Front-running analysis completed
- MATH-06 verdict rendered with complete reasoning
- Any findings rated by severity
- No contract files were modified
</success_criteria>

<output>
After completion, create `.planning/phases/03b-vrf-dependent-modules/03b-04-SUMMARY.md` following the standard summary template.
</output>
