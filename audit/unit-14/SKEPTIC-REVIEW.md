# Unit 14: Affiliate + Quests + Jackpots -- Skeptic Review

**Phase:** 116
**Contracts:** DegenerusAffiliate.sol, DegenerusQuests.sol, DegenerusJackpots.sol
**Audit Model:** Opus (claude-opus-4-6)
**Date:** 2026-03-25

---

## Review Methodology

The Skeptic independently read every line of code cited by the Mad Genius, traced execution paths, verified guard conditions, and evaluated whether each finding and SAFE verdict is justified. Findings are only dismissed when the exact code preventing the attack can be cited.

---

## Findings Review

### F-01: uint24 Underflow in BAF Scatter at lvl==0

**Mad Genius Verdict:** INVESTIGATE (LOW)
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:**

The Mad Genius correctly identifies that at L396 of DegenerusJackpots.sol:
```solidity
uint24 maxBack = lvl > 99 ? 99 : lvl - 1;
```
When `lvl == 0`, `lvl - 1` underflows to `16777215` (uint24 max).

However, the Skeptic traces the calling context:

1. `runBafJackpot` is ONLY called by `DegenerusGameEndgameModule._runBafJackpot` at L373, which is called by `runRewardJackpots` at L195.

2. `runRewardJackpots` fires BAF when `prevMod10 == 0` (L185), where `prevMod10 = lvl % 10` (L177). For `lvl == 0`, this is indeed `0 % 10 == 0`, so the BAF path IS entered.

3. **However:** At level 0, the `baseFuturePool` (L176) would contain only the initial ETH from the first few purchases. The `bafPoolWei = (baseFuturePool * bafPct) / 100` could be non-zero.

4. **The critical guard:** Even with the underflow producing `targetLvl = some huge number`, the call to `degenerusGame.sampleTraitTicketsAtLevel(targetLvl, entropy)` at L404 would return empty arrays for non-existent levels. The scatter loop would simply produce no winners, and the unawarded amounts flow to `toReturn` via L456-457.

5. **No ETH loss.** All unawarded scatter prizes are returned to the caller via `returnAmountWei` and recycled back into the future prize pool by the endgame module (L198-200).

6. **No revert.** The sampleTraitTicketsAtLevel function returns empty arrays for non-existent levels rather than reverting, so the transaction completes successfully.

**Practical Impact:** At level 0 BAF resolution (transition from level 0 to level 1), scatter rounds 12-49 (38 rounds) would query non-existent levels, producing zero scatter winners for those rounds. The per-round prize amounts flow back to the future prize pool. Rounds 0-3 (lvl itself) and 4-11 (lvl+1..lvl+3) work correctly.

**The underflow is real but the impact is purely cosmetic/informational.** Fewer scatter winners at the first-ever BAF resolution, with no fund loss. Given that level 0 has minimal prize pool (game just started), the practical effect is negligible.

**Recommendation:** For correctness, add a guard: `if (lvl == 0) { targetLvl = lvl; }` before the maxBack calculation. However, this is a code-quality improvement, not a security fix.

---

## SAFE Verdict Verification

### B-13 runBafJackpot -- SAFE Verdicts Confirmed

1. **State Coherence:** Independently verified. All bafTop reads via `_bafTop()` return values consumed into memory arrays. `_clearBafTop` at L487 deletes storage after all reads are complete. No ancestor has a stale local copy. **CONFIRMED SAFE.**

2. **Access Control:** `onlyGame` modifier at L148-151 checks `msg.sender != ContractAddresses.GAME`. ContractAddresses is a constants file, not mutable. **CONFIRMED SAFE.**

3. **RNG:** VRF word from Chainlink via the game contract. Salt-chained entropy derivation at L270/287/329/385 produces cryptographically independent subkeys. **CONFIRMED SAFE.**

4. **Cross-contract reads:** Verified `coin.coinflipTopLastDay()` (L256) is a view call to BurnieCoinflip that reads historical snapshot data (previous day window top bettor). Not affected by current-transaction state changes. `sampleFarFutureTickets` and `sampleTraitTicketsAtLevel` are view calls reading game storage. **CONFIRMED SAFE.**

5. **Silent failures:** Verified assembly at L481-484 correctly truncates arrays to actual winner count. `toReturn` captures all unawarded amounts. **CONFIRMED SAFE.**

### B-03 payAffiliate -- SAFE Verdicts Confirmed

1. **State Coherence:** Traced `storedCode` local: read at L406, potentially written via `_setReferralCode` at L419/430/436/446. After each `_setReferralCode` call, the local `storedCode` is reassigned (L420/431/438/448). Verified no stale local writeback. **CONFIRMED SAFE.**

2. **Deterministic PRNG:** Verified the comment at L572 acknowledges the design trade-off. The weighted roll at L827 ensures each recipient's probability equals their share of totalAmount. Manipulation can only redistribute between affiliates (EV-neutral). **CONFIRMED SAFE by design.**

3. **Self-referral loop:** Independently traced. `_referrerAddress` at L714-718 is a single-hop lookup, not recursive. Even with circular referrals (A refers B, B refers A), the upline chain is only followed 2 hops (affiliate -> upline1 -> upline2), so no infinite loop. The `winner != sender` guard at L609 prevents self-enrichment. **CONFIRMED SAFE.**

4. **Commission cap:** Verified the cap at L498-512 is per-affiliate per-sender per-level. Referral locking prevents code rotation after presale. `_vaultReferralMutable` only returns true when `game.lootboxPresaleActiveFlag()` is true AND the current code is VAULT/LOCKED. **CONFIRMED SAFE.**

5. **External call ordering:** All affiliate-local state updates (commission tracking at L511, leaderboard at L516-517, top affiliate at L527) complete BEFORE external calls to `coin.affiliateQuestReward` at L578/585/592 and `_routeAffiliateReward` at L568/611. No state reads from affiliate storage after external calls. **CONFIRMED SAFE.**

### B-12 recordBafFlip -- SAFE Verdicts Confirmed

1. **Unchecked overflow:** uint256 max is 1.15 * 10^77. BURNIE total supply with 18 decimals would need to exceed 10^77 / 10^18 = 10^59 tokens to overflow. Even with billions of coins and millions of flips, this is impossible. **CONFIRMED SAFE.**

2. **Epoch lazy-reset:** Verified at L169-173: when `bafPlayerEpoch[lvl][player] != currentEpoch`, the player's total is reset to 0 before adding. This correctly prevents stale scores from carrying across BAF epochs. **CONFIRMED SAFE.**

### B-01/B-02 createAffiliateCode/referPlayer -- SAFE Verdicts Confirmed

1. **Code squatting:** Verified reserved values (0x0, REF_CODE_LOCKED) cannot be claimed (L728). Existing codes cannot be overwritten (L733). Kickback capped at 25% (L730). **CONFIRMED SAFE.**

2. **Referral locking:** Verified `referPlayer` checks existing code (L326-328) and only allows update during presale via `_vaultReferralMutable`. Self-referral reverts (L325). **CONFIRMED SAFE.**

### B-04 rollDailyQuest -- SAFE Verdicts Confirmed

1. **Quest version invalidation:** `_seedQuestType` bumps version via `_nextQuestVersion()` at L1585, which increments `questVersionCounter` at L1040. All player progress with stale version is automatically invalidated by `_questSyncProgress` at L1163. **CONFIRMED SAFE.**

2. **Entropy usage:** Slot 0 is always MINT_ETH (fixed, L376). Slot 1 uses VRF-derived entropy with swapped halves (L374). Even if quest type is predictable, targets are fixed -- no economic advantage. **CONFIRMED SAFE.**

### B-05 awardQuestStreakBonus -- SAFE Verdicts Confirmed

1. **Overflow protection:** `uint32 updated = uint32(prevStreak) + uint32(amount)` at L338. Max uint24 streak + max uint16 bonus = 16777215 + 65535 = 16842750, which fits in uint32. Clamped at uint24 max (L339-343). **CONFIRMED SAFE.**

### B-06 through B-11 Quest Handlers -- SAFE Verdicts Confirmed

1. **Slot ordering:** Verified all handlers enforce `if (slotIndex == 1 && (state.completionMask & 1) == 0)` before allowing slot 1 completion. Slot 0 must be complete first. **CONFIRMED SAFE.**

2. **Double completion:** `_questComplete` at L1401 checks `(mask & slotMask) != 0` before allowing completion. Once a slot bit is set in completionMask, it cannot trigger rewards again within the same day. `_questSyncState` resets completionMask at day boundaries (L1141). **CONFIRMED SAFE.**

3. **Progress clamping:** `_clampedAdd128` at L1024-1032 correctly handles uint256 -> uint128 overflow by capping at uint128 max. No arithmetic overflow possible. **CONFIRMED SAFE.**

4. **Paired completion:** `_questCompleteWithPair` -> `_maybeCompleteOther` correctly checks both the completion mask AND `_questReady` (progress >= target) before auto-completing the paired slot. The double-completion guard in `_questComplete` prevents any double-reward. **CONFIRMED SAFE.**

---

## Interrogation Questions

**Q1: The Mad Genius says `_referrerAddress` is a single-hop lookup. But payAffiliate calls it twice (L583, L590) to build a 3-deep chain. Is there a risk of address(0) appearing in the amounts array?**

A: Verified. If an affiliate has no upline, `_referrerAddress` returns `ContractAddresses.VAULT` (L716). If upline1 also has no upline, upline2 is also VAULT. The amounts array always has valid addresses. VAULT receives the overflow rewards, which is by design.

**Q2: In handleMint (B-06), the function iterates both slots and can potentially complete both. Is there double-reward risk?**

A: The function returns early on the first completion (`anyCompleted` flag at L509-513). Even if both slots match (both MINT_ETH or both MINT_BURNIE), the loop checks completion sequentially and the `_questComplete` mask prevents double-completion of the same slot. The `anyCompleted` aggregation at L520-522 correctly sums rewards from both slots.

**Q3: The scatter section in runBafJackpot allocates fixed-size arrays (`address[50] memory`) but uses variable counts (firstCount, secondCount). Is there an array out-of-bounds risk?**

A: The loop runs exactly `BAF_SCATTER_ROUNDS = 50` iterations, and each iteration adds at most 1 entry to firstWinners and 1 to secondWinners. So firstCount <= 50 and secondCount <= 50. The arrays are perfectly sized. No out-of-bounds risk.

**Q4: `bafEpoch[lvl]` is incremented with `unchecked { ++bafEpoch[lvl]; }` at L488. Can this overflow?**

A: `bafEpoch` is uint256. One increment per BAF resolution (every 10 levels). To overflow, the game would need 1.15 * 10^77 BAF resolutions. At one per 10 levels, this requires 1.15 * 10^78 levels. Effectively impossible.

---

## Final Skeptic Verdict

| Finding | Mad Genius | Skeptic | Final |
|---------|-----------|---------|-------|
| F-01: uint24 underflow at lvl==0 scatter | INVESTIGATE (LOW) | DOWNGRADE TO INFO | **INFO** |

**All SAFE verdicts independently confirmed.** The audit covered:
- 13 Category B functions with full call tree verification
- 8 MULTI-PARENT Category C functions
- 10 cross-contract call site traces
- 7 priority investigation areas

**No CRITICAL, HIGH, MEDIUM, or LOW findings.** One INFO-level observation (cosmetic edge case at first BAF resolution).
