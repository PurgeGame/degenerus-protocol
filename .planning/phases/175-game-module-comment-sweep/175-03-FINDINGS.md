# Phase 175 Comment Audit — Plan 03 Findings
**Contracts:** DegenerusGameLootboxModule, DegenerusGameMintStreakUtils
**Requirement:** CMT-01
**Date:** 2026-04-03
**Total findings this plan:** 1 LOW, 4 INFO

---

## DegenerusGameLootboxModule

Contract: `contracts/modules/DegenerusGameLootboxModule.sol` (1778 lines)
Swept: full contract, end-to-end

---

### Finding 1

**Severity:** LOW
**Location:** `DegenerusGameLootboxModule.sol` lines 110-111

**Comment says:**
```
/// @notice Emitted when a lootbox awards a lazy pass
/// @param player The player who received the lazy pass
```

**Code does:**
No event follows this NatSpec block. The comment is an orphaned/dangling NatSpec stub — the event declaration was never written (or was removed). Lazy pass discount boons are emitted via `LootBoxReward(player, day, 11, originalAmount, bps)` rather than a dedicated event. The dangling comment misleads a reader into searching for a `LootBoxLazyPassAwarded` (or similar) event that does not exist.

---

### Finding 2

**Severity:** INFO
**Location:** `DegenerusGameLootboxModule.sol` line 140

**Comment says:**
```
/// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15,
///                   6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon,
///                   10=ActivityBoon/DeityPassBoon)
```

**Code does:**
`_applyBoon` emits `LootBoxReward(..., 11, ...)` for all three lazy pass discount boon tiers (types 29, 30, 31) at line 1513:
```solidity
if (!isDeity) emit LootBoxReward(player, day, 11, originalAmount, bps);
```
`rewardType=11` is missing from the `@param rewardType` description. Off-chain indexers and dashboards relying solely on the NatSpec will not map this value correctly.

---

### Finding 3

**Severity:** INFO
**Location:** `DegenerusGameLootboxModule.sol` line 314

**Comment says:**
```
/// @dev Maximum EV at 260%+ activity (135%)
uint16 private constant LOOTBOX_EV_MAX_BPS = 13_500;
```

**Code does:**
The threshold that triggers maximum EV is `ACTIVITY_SCORE_MAX_BPS = 25_500` (bps), which represents 255%, not 260%. The comment on the adjacent constant declaration (line 308: `/// @dev 255%+ activity score = maximum 135% EV`) and the function docstring (line 444: `255%+ activity → 135% EV`) both correctly state 255%. Only line 314 says 260%. The value 260% does not correspond to any constant or threshold in the contract.

---

### Finding 4

**Severity:** INFO
**Location:** `DegenerusGameLootboxModule.sol` lines 1005-1006

**Comment says:**
```
/// @dev Roll for lootbox boons. Lootbox can award at most one boon.
///      If a boon is already active, only refresh or upgrade that same category.
```

**Code does:**
The second sentence is misleading. `_rollLootboxBoons` does not check what boon category is currently active before rolling. It rolls from the full eligible boon pool unconditionally. The upgrade semantics ("only if higher tier replaces lower") are applied inside `_applyBoon` after the roll, within the new boon's own category — not constrained to a pre-existing active category. A player with a 5% coinflip boon can receive a purchase boost, lootbox boost, decimator boost, or any other category. The comment implies a restriction that does not exist.

More accurate phrasing: "Within each category, upgrade semantics apply — a new boon replaces an existing one only if it is a higher tier."

---

### Storage Repack Verification (v16.0)

No references to `currentPrizePool`, `prizePoolsPacked`, or `uint256 prizePool` appear in `DegenerusGameLootboxModule.sol`. The module does not declare or comment on prize pool storage variables. No stale uint256/uint128 prize pool comments exist in this file.

### Activity Score / Quest Trigger Verification

No references to `_processQuestCompletion`, `_playerActivityScore`, or quest handlers appear in `DegenerusGameLootboxModule.sol`. The module does not comment on activity score contributions or quest-triggering behavior — consistent with lootbox resolution not triggering quest logic directly. No findings.

### Redemption Lootbox (v3.4) Verification

`resolveRedemptionLootbox` at line 699 is correctly described in its NatSpec:
- Uses provided `activityScore` instead of reading current (snapshotted at submission): accurate.
- Called via delegatecall from Game when sDGNRS sends lootbox ETH: accurate.
No findings.

### BURNIE Endgame Gate (v11.0) Verification

Lines 634-638 correctly redirect current-level BURNIE lootbox tickets to far-future key space when `gameOverPossible`. The inline comment `// ENF-02: When gameOverPossible, redirect current-level BURNIE lootbox` accurately describes the behavior. No findings.

### HAS_DEITY_PASS_SHIFT Read (line 1040) Verification

Line 1040 uses `BitPackingLib.HAS_DEITY_PASS_SHIFT` directly in a shift expression with no adjacent comment. There is no misleading comment to flag. The symbolic name is self-documenting. No findings.

---

## DegenerusGameMintStreakUtils

Contract: `contracts/modules/DegenerusGameMintStreakUtils.sol` (173 lines)
Swept: full contract, end-to-end

---

### Finding 5

**Severity:** INFO
**Location:** `DegenerusGameMintStreakUtils.sol` line 7

**Comment says:**
```
/// @dev Shared mint streak helpers (credits on completed 1x price ETH quest).
```

**Code does:**
The contract contains more than mint streak helpers. It also houses the complete `_playerActivityScore` computation (lines 81-161) — a significant multi-component scoring function covering mint streak, mint count, quest streak, affiliate bonus cache, deity pass bonus, and whale pass bonus. Describing the contract solely as "mint streak helpers" understates its actual scope. A reader expecting to find activity score logic here would need to search to discover it. The parenthetical "(credits on completed 1x price ETH quest)" is also opaque — it is unclear what quest or credit mechanism is being referenced.

---

### Affiliate Bonus Cache Reader (Phase 173) Verification

Lines 136-146 contain the affiliate bonus cache block:

```solidity
// Affiliate bonus (cached in mintPacked_ on level transitions)
{
    uint256 cachedLevel = (packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) & BitPackingLib.MASK_24;
    uint256 affPoints;
    if (cachedLevel == uint256(currLevel)) {
        affPoints = (packed >> BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT) & BitPackingLib.MASK_6;
    } else {
        affPoints = affiliate.affiliateBonusPointsBest(currLevel, player);
    }
    bonusBps += affPoints * 100;
}
```

The comment accurately describes the cache: hit when `cachedLevel == currLevel`, miss falls through to the live `affiliateBonusPointsBest` call. The comment does not claim the path always calls the affiliate contract; the fallback live-lookup on miss is explicitly shown in the `else` branch. No finding.

### Activity Score Components Verification

The `_playerActivityScore` function comments accurately describe all components:
- Mint streak: `// Mint streak: 1% per consecutive level minted, max 50%` — code caps at 50 (`streak > 50 ? 50 : streak`). Accurate.
- Mint count: `// Mint count bonus: 1% each` — accurate; `_mintCountBonusPoints` returns a count added at 100 bps each.
- Quest streak: `// Quest streak: 1% per quest streak, max 100%` — code caps at 100 (`questStreak > 100 ? 100 : questStreak`). Accurate.
- Affiliate bonus: `// Affiliate bonus (cached in mintPacked_ on level transitions)` — accurate (see above).
No findings.

### _updateMintStreak / _recordMintStreakForLevel Verification

The function name in the contract is `_recordMintStreakForLevel` (not `_updateMintStreak`). The NatSpec at line 16: `/// @dev Record a mint streak completion for a given level (idempotent per level).` is accurate:
- Idempotency: `if (lastCompleted == mintLevel) return;` at line 23. Correct.
- Streak increment condition: `lastCompleted != 0 && lastCompleted + 1 == mintLevel` — increment only if previous level was exactly one behind. Correct.
- Streak reset: else branch sets `newStreak = 1`. Correct.
No findings.

### Frozen Level Handling Verification

`frozenUntilLevel` is read at lines 95-98 and used at line 102:
```solidity
bool passActive = frozenUntilLevel > currLevel &&
    (bundleType == 1 || bundleType == 3);
```
No comment describes the frozen level handling specifically. The `passActive` flag is used to enforce floor values on streak and mint count points (lines 121-127). The inline comment `// Active pass = full participation credit` at line 119 accurately describes the effect. No misleading comment present. No finding.

### General NatSpec Verification

- `_mintStreakEffective` (line 48): `/// @dev Effective mint streak (resets if a level was missed).` — accurate; returns 0 if `currentMintLevel > lastCompleted + 1`. No finding.
- `_activeTicketLevel` (line 67): `/// @dev Returns the active ticket level for direct ticket purchases.` — accurate; returns `level` during jackpot phase, `level + 1` during purchase phase. No finding.
- Convenience `_playerActivityScore(player, questStreak)` wrapper (line 163): NatSpec matches the delegation to the three-argument form. No finding.
