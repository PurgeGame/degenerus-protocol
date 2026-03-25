# Unit 14: Affiliate + Quests + Jackpots -- Taskmaster Coverage Checklist

**Phase:** 116
**Contracts:** DegenerusAffiliate.sol, DegenerusQuests.sol, DegenerusJackpots.sol
**Audit Model:** Opus (claude-opus-4-6)
**Date:** 2026-03-25

---

## Contract Overview

| Contract | File | Lines | External/Public | Internal/Private | View/Pure |
|----------|------|-------|-----------------|-----------------|-----------|
| DegenerusAffiliate | contracts/DegenerusAffiliate.sol | ~840 | 3 state-changing + 4 view | 8 state-changing + 3 view/pure | 7 |
| DegenerusQuests | contracts/DegenerusQuests.sol | ~1598 | 8 state-changing + 3 view | 12 state-changing + 8 view/pure | 20 |
| DegenerusJackpots | contracts/DegenerusJackpots.sol | ~650 | 2 state-changing + 1 view | 2 state-changing + 3 view/pure | 5 |
| **TOTAL** | | **~3088** | **13 state-changing** | **22 state-changing** | **32** |

---

## Function Categorization

### Category B: External/Public State-Changing Functions (Full Mad Genius Attack)

These functions get full treatment: call tree, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.

#### DegenerusAffiliate (3 functions)

| # | Function | Lines | Access Control | Risk Tier | Rationale |
|---|----------|-------|---------------|-----------|-----------|
| B-01 | `createAffiliateCode(bytes32, uint8)` | L304-306 | Open (anyone) | MEDIUM | Permissionless code creation; validates reserves and kickback cap |
| B-02 | `referPlayer(bytes32)` | L321-331 | Open (anyone) | HIGH | Player self-assigns referrer; locking logic, presale mutability |
| B-03 | `payAffiliate(uint256, bytes32, address, uint24, bool, uint16)` | L386-617 | onlyAuthorized (coin/game) | CRITICAL | Core reward flow: referral resolution, scaling, commission cap, lootbox taper, multi-tier distribution, external calls to BurnieCoin |

#### DegenerusQuests (8 functions)

| # | Function | Lines | Access Control | Risk Tier | Rationale |
|---|----------|-------|---------------|-----------|-----------|
| B-04 | `rollDailyQuest(uint48, uint256)` | L313-318 | onlyCoin | HIGH | VRF entropy quest seeding; controls quest availability for all players |
| B-05 | `awardQuestStreakBonus(address, uint16, uint48)` | L331-349 | onlyGame | MEDIUM | Direct streak manipulation; clamps at uint24 max |
| B-06 | `handleMint(address, uint32, bool)` | L440-523 | onlyCoin | MEDIUM | Mint progress tracking; iterates both slots |
| B-07 | `handleFlip(address, uint256)` | L538-579 | onlyCoin | MEDIUM | Flip progress; single-slot lookup |
| B-08 | `handleDecimator(address, uint256)` | L593-631 | onlyCoin | LOW | Decimator progress; identical pattern to handleFlip |
| B-09 | `handleAffiliate(address, uint256)` | L644-682 | onlyCoin | LOW | Affiliate progress; identical pattern to handleFlip |
| B-10 | `handleLootBox(address, uint256)` | L697-736 | onlyCoin | MEDIUM | Lootbox progress; uses mintPrice for target |
| B-11 | `handleDegenerette(address, uint256, bool)` | L750-789 | onlyCoin | MEDIUM | Degenerette progress; ETH and BURNIE variants |

#### DegenerusJackpots (2 functions)

| # | Function | Lines | Access Control | Risk Tier | Rationale |
|---|----------|-------|---------------|-----------|-----------|
| B-12 | `recordBafFlip(address, uint24, uint256)` | L166-181 | onlyCoin | HIGH | Leaderboard recording; unchecked arithmetic; epoch lazy-reset |
| B-13 | `runBafJackpot(uint256, uint24, uint256)` | L220-491 | onlyGame | CRITICAL | Full BAF distribution: 7 prize slices, scatter rounds, external game calls, leaderboard cleanup |

---

### Category C: Internal/Private State-Changing Helpers

These are traced as part of their parent's call tree. Functions marked **MULTI-PARENT** get standalone sections.

#### DegenerusAffiliate (8 functions)

| # | Function | Lines | Called By | Multi-Parent? |
|---|----------|-------|-----------|--------------|
| C-01 | `_createAffiliateCode(address, bytes32, uint8)` | L721-739 | B-01 (createAffiliateCode), constructor | YES -- constructor + external |
| C-02 | `_bootstrapReferral(address, bytes32)` | L742-749 | constructor only | NO |
| C-03 | `_setReferralCode(address, bytes32)` | L696-706 | B-02, B-03, C-01, C-02 | YES -- called by 4 parents |
| C-04 | `_routeAffiliateReward(address, uint256)` | L754-760 | B-03 (payAffiliate) | NO |
| C-05 | `_updateTopAffiliate(address, uint256, uint24)` | L785-792 | B-03 (payAffiliate) | NO |
| C-06 | `constructor(...)` | L232-283 | Deploy-time only | NO (analyzed as standalone) |

#### DegenerusQuests (12 functions)

| # | Function | Lines | Called By | Multi-Parent? |
|---|----------|-------|-----------|--------------|
| C-07 | `_rollDailyQuest(uint48, uint256)` | L366-407 | B-04 (rollDailyQuest) | NO |
| C-08 | `_seedQuestType(DailyQuest storage, uint48, uint8)` | L1578-1586 | C-07 | NO |
| C-09 | `_nextQuestVersion()` | L1039-1041 | C-08 | NO |
| C-10 | `_questSyncState(PlayerQuestState storage, address, uint48)` | L1111-1143 | B-05 through B-11 (all handle* functions) | YES -- called by 7 parents |
| C-11 | `_questSyncProgress(PlayerQuestState storage, uint8, uint48, uint24)` | L1156-1168 | B-07 through B-11, C-14 | YES -- called by 6 parents |
| C-12 | `_questComplete(address, PlayerQuestState storage, uint8, DailyQuest memory)` | L1388-1435 | C-13, C-15 | YES -- called by 2 parents |
| C-13 | `_questCompleteWithPair(...)` | L1453-1492 | B-06 through B-11 | YES -- called by 6 parents |
| C-14 | `_questHandleProgressSlot(...)` | L1063-1091 | B-06, B-11 | YES -- called by 2 parents |
| C-15 | `_maybeCompleteOther(...)` | L1506-1533 | C-13 | NO |

#### DegenerusJackpots (2 functions)

| # | Function | Lines | Called By | Multi-Parent? |
|---|----------|-------|-----------|--------------|
| C-16 | `_updateBafTop(uint24, address, uint256)` | L555-613 | B-12 (recordBafFlip) | NO |
| C-17 | `_clearBafTop(uint24)` | L629-640 | B-13 (runBafJackpot) | NO |

---

### Category D: View/Pure Functions

These are catalogued but not attack-analyzed (no state changes).

#### DegenerusAffiliate (7 functions)

| # | Function | Lines | Visibility |
|---|----------|-------|-----------|
| D-01 | `affiliateTop(uint24)` | L631-634 | external view |
| D-02 | `affiliateScore(uint24, address)` | L643-645 | external view |
| D-03 | `totalAffiliateScore(uint24)` | L654-656 | external view |
| D-04 | `affiliateBonusPointsBest(uint24, address)` | L667-683 | external view |
| D-05 | `getReferrer(address)` | L339-341 | external view |
| D-06 | `_vaultReferralMutable(bytes32)` | L690-693 | private view |
| D-07 | `_referrerAddress(address)` | L714-718 | private view |
| D-08 | `_score96(uint256)` | L769-775 | private pure |
| D-09 | `_applyLootboxTaper(uint256, uint16)` | L796-804 | private pure |
| D-10 | `_rollWeightedAffiliateWinner(...)` | L807-839 | private view |

#### DegenerusQuests (20 functions)

| # | Function | Lines | Visibility |
|---|----------|-------|-----------|
| D-11 | `getActiveQuests()` | L801-811 | external view |
| D-12 | `playerQuestStates(address)` | L829-851 | external view |
| D-13 | `getPlayerQuestView(address)` | L861-894 | external view |
| D-14 | `_materializeActiveQuestsForView()` | L817-819 | private view |
| D-15 | `_questViewData(...)` | L914-930 | private view |
| D-16 | `_questRequirements(DailyQuest, uint8)` | L941-956 | private view |
| D-17 | `_currentDayQuestOfType(...)` | L970-987 | private pure |
| D-18 | `_canRollDecimatorQuest()` | L1002-1011 | private view |
| D-19 | `_clampedAdd128(uint128, uint256)` | L1024-1032 | private pure |
| D-20 | `_questProgressValid(...)` | L1178-1189 | private pure |
| D-21 | `_questProgressValidStorage(...)` | L1199-1210 | private view |
| D-22 | `_questCompleted(...)` | L1219-1229 | private pure |
| D-23 | `_questTargetValue(...)` | L1242-1271 | private pure |
| D-24 | `_bonusQuestType(...)` | L1293-1363 | private pure |
| D-25 | `_questReady(...)` | L1543-1565 | private view |
| D-26 | `_currentQuestDay(...)` | L1593-1597 | private pure |

#### DegenerusJackpots (5 functions)

| # | Function | Lines | Visibility |
|---|----------|-------|-----------|
| D-27 | `getLastBafResolvedDay()` | L647-649 | external view |
| D-28 | `_creditOrRefund(...)` | L507-521 | private pure |
| D-29 | `_bafScore(address, uint24)` | L533-536 | private view |
| D-30 | `_score96(uint256)` | L541-547 | private pure |
| D-31 | `_bafTop(uint24, uint8)` | L620-625 | private view |

---

## Coverage Requirements

### Mandatory Analysis for Each Category B Function

- [ ] Full recursive call tree with line numbers
- [ ] Storage writes map (full tree -- every storage variable written by any function in the call tree)
- [ ] Cached-local-vs-storage check (explicit list of every ancestor_local/descendant_write pair)
- [ ] 10-angle attack analysis with verdicts (VULNERABLE / INVESTIGATE / SAFE)

### Mandatory Analysis for Each MULTI-PARENT Category C Function

- [ ] Standalone call tree section
- [ ] Storage writes for each calling context
- [ ] Cached-local-vs-storage check for each calling parent

### Cross-Contract Call Sites to Trace

| # | Caller | External Call | Target |
|---|--------|--------------|--------|
| X-01 | B-03 (payAffiliate) | `coin.creditFlip(player, amount)` | BurnieCoin |
| X-02 | B-03 (payAffiliate) | `coin.affiliateQuestReward(player, amount)` | BurnieCoin |
| X-03 | B-03 (payAffiliate) | `game.lootboxPresaleActiveFlag()` | DegenerusGame (via _vaultReferralMutable) |
| X-04 | B-13 (runBafJackpot) | `degenerusGame.sampleFarFutureTickets(entropy)` | DegenerusGame |
| X-05 | B-13 (runBafJackpot) | `degenerusGame.sampleTraitTicketsAtLevel(lvl, entropy)` | DegenerusGame |
| X-06 | B-13 (runBafJackpot) | `coin.coinflipTopLastDay()` | BurnieCoinflip |
| X-07 | B-13 (runBafJackpot) | `degenerusGame.currentDayView()` | DegenerusGame |
| X-08 | C-10 (_questSyncState) | `questStreakShieldCount[player]` (storage read) | Internal |
| X-09 | Various quest handlers | `questGame.mintPrice()` | DegenerusGame |
| X-10 | C-18 (_canRollDecimatorQuest) | `game_.decWindowOpenFlag()`, `game_.level()` | DegenerusGame |

---

## Storage Variable Inventory

### DegenerusAffiliate Storage

| # | Variable | Type | Written By |
|---|----------|------|-----------|
| S-01 | `affiliateCode[bytes32]` | mapping(bytes32 => AffiliateCodeInfo) | C-01, constructor |
| S-02 | `affiliateCoinEarned[uint24][address]` | mapping(uint24 => mapping(address => uint256)) | B-03 |
| S-03 | `playerReferralCode[address]` | mapping(address => bytes32) | C-03 |
| S-04 | `affiliateTopByLevel[uint24]` | mapping(uint24 => PlayerScore) | C-05 |
| S-05 | `_totalAffiliateScore[uint24]` | mapping(uint24 => uint256) | B-03 |
| S-06 | `affiliateCommissionFromSender[uint24][address][address]` | mapping(uint24 => mapping(address => mapping(address => uint256))) | B-03 |

### DegenerusQuests Storage

| # | Variable | Type | Written By |
|---|----------|------|-----------|
| S-07 | `activeQuests[slot]` | DailyQuest[2] | C-08 |
| S-08 | `questPlayerState[address]` | mapping(address => PlayerQuestState) | C-10, C-11, C-12, B-05 |
| S-09 | `questStreakShieldCount[address]` | mapping(address => uint16) | C-10 |
| S-10 | `questVersionCounter` | uint24 | C-09 |

### DegenerusJackpots Storage

| # | Variable | Type | Written By |
|---|----------|------|-----------|
| S-11 | `bafTotals[uint24][address]` | mapping(uint24 => mapping(address => uint256)) | B-12 |
| S-12 | `bafTop[uint24]` | mapping(uint24 => PlayerScore[4]) | C-16, C-17 |
| S-13 | `bafTopLen[uint24]` | mapping(uint24 => uint8) | C-16, C-17 |
| S-14 | `bafEpoch[uint24]` | mapping(uint24 => uint256) | B-13 |
| S-15 | `bafPlayerEpoch[uint24][address]` | mapping(uint24 => mapping(address => uint256)) | B-12 |
| S-16 | `lastBafResolvedDay` | uint48 | B-13 |

---

## Priority Investigation Areas

1. **Unchecked overflow in recordBafFlip (L176):** `unchecked { total += amount; }` -- can an attacker overflow bafTotals to manipulate leaderboard?
2. **Deterministic PRNG in affiliate winner selection:** `_rollWeightedAffiliateWinner` uses keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode) -- can a player pre-compute and choose optimal timing?
3. **Self-referral loop prevention:** Verify the _referrerAddress chain from affiliate -> upline1 -> upline2 cannot loop back to the sender
4. **Quest slot 1 ordering dependency:** Slot 1 requires slot 0 completion first (`if (slotIndex == 1 && (state.completionMask & 1) == 0)`) -- verify no bypass
5. **BAF scatter level targeting with century levels:** L391-398 has `maxBack = lvl > 99 ? 99 : lvl - 1` -- verify edge case when lvl == 0 or lvl < 100
6. **Commission cap bypass:** Can an attacker rotate affiliate codes to circumvent MAX_COMMISSION_PER_REFERRER_PER_LEVEL?
7. **Affiliate quest reward reentrancy path:** payAffiliate calls coin.affiliateQuestReward which may call back into quests -- trace full path

---

## Taskmaster Verdict

**Status:** CHECKLIST COMPLETE

All state-changing functions across all 3 contracts have been inventoried:
- **13 Category B** functions requiring full Mad Genius attack analysis
- **17 Category C** functions requiring call-tree tracing (8 are MULTI-PARENT, requiring standalone sections)
- **31 Category D** view/pure functions catalogued
- **16 storage variables** mapped across all 3 contracts
- **10 cross-contract call sites** identified for tracing
- **7 priority investigation areas** flagged

The Mad Genius MUST analyze all 13 Category B functions and all 8 MULTI-PARENT Category C functions with full call trees, storage-write maps, and 10-angle attack analysis. No shortcuts. No "similar to above."
