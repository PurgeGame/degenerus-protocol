# Phase 177 Comment Audit — Plan 03 Findings
**Contracts:** EntropyLib, GameTimeLib, JackpotBucketLib, PriceLookupLib, BitPackingLib,
              IDegenerusAffiliate, IBurnieCoinflip, IDegenerusJackpots, IStakedDegenerusStonk,
              IDegenerusCoin, IDegenerusGame, IDegenerusQuests, IDegenerusGameModules,
              IStETH, IVaultCoin, IVRFCoordinator
**Requirement:** CMT-05
**Date:** 2026-04-03
**Total findings this plan:** 3 LOW, 7 INFO

---

## BitPackingLib

**Finding BP-01 — INFO**
**Location:** `contracts/libraries/BitPackingLib.sol` header table, line 18; `contracts/modules/DegenerusGameMintStreakUtils.sol` line 10
**Comment says:** Header table lists `[160-183] MINT_STREAK_LAST_COMPLETED` as if it is defined in BitPackingLib, using the name without the `_SHIFT` suffix.
**Code does:** The constant is defined in `DegenerusGameMintStreakUtils.sol` as `MINT_STREAK_LAST_COMPLETED_SHIFT = 160` — not in BitPackingLib. A reader consulting BitPackingLib to enumerate all packed-word field constants will not find this one; they must also look in MintStreakUtils. The header table is descriptively accurate for the bit range, but does not signal that the constant lives elsewhere, or that the name differs.

**Finding BP-02 — INFO**
**Location:** `contracts/libraries/BitPackingLib.sol` lines 65-66 (WHALE_BUNDLE_TYPE_SHIFT) and lines 68-69 (HAS_DEITY_PASS_SHIFT)
**Comment says:** The library defines named mask constants (MASK_16, MASK_24, MASK_32, MASK_6) for most field widths but no named constant for the 2-bit or 1-bit fields. The header table describes WHALE_BUNDLE_TYPE as "2 bits" and HAS_DEITY_PASS as "1 bit".
**Code does:** Call sites use inline literals (`& 3` for WHALE_BUNDLE_TYPE, `& 1` for HAS_DEITY_PASS) rather than a named constant. This is inconsistent with the rest of the library's mask constant pattern. If callers ever need to extend or verify these field widths, they must grep for inline literals rather than referencing a named constant.

---

## JackpotBucketLib

No discrepancies found.

All function NatSpec, inline comments, and constant descriptions were verified against the implementation:
- `traitBucketCounts` base counts [25, 15, 8, 1] correct.
- `scaleTraitBucketCountsWithCap` scale thresholds (10/50/200 ETH, 1x/2x/maxScale) correct.
- `soloBucketIndex` entropy rotation formula comment accurate.
- `bucketShares` remainder description accurate.
- `capBucketCounts` comment about keeping solo bucket fixed verified.
- `getRandomTraits` quadrant offsets and 6-bit per quadrant comments accurate.

---

## PriceLookupLib

No discrepancies found.

The `@dev` comment describing the 100-level cycle with intro tier overrides was verified entry by entry:
- Levels 0-4 → 0.01 ETH (intro) ✓
- Levels 5-9 → 0.02 ETH (intro) ✓
- Levels 10-29 → 0.04 ETH ✓
- Levels 30-59 → 0.08 ETH ✓
- Levels 60-89 → 0.12 ETH ✓
- Levels 90-99 → 0.16 ETH ✓
- Levels x00 (cycle milestone) → 0.24 ETH ✓
- Levels x01-x29 → 0.04 ETH ✓
- Levels x30-x59 → 0.08 ETH ✓
- Levels x60-x89 → 0.12 ETH ✓
- Levels x90-x99 → 0.16 ETH ✓

The v14.0 change moved price lookup from storage reads to argument-passing via `priceForLevel`. All comments describe this as a pure function with no storage reads — accurate.

---

## EntropyLib

No discrepancies found.

The xorshift parameters (left 7, right 9, left 8) match the implementation exactly. The description "Seeded from VRF, so ultimately secure" is an architectural statement, not a per-invocation claim. The `@param`/`@return` tags match the function signature.

---

## GameTimeLib

No discrepancies found.

`JACKPOT_RESET_TIME = 82620` seconds: 82620 ÷ 3600 = 22.95 hours = 22:57 UTC — confirmed accurate. The `currentDayIndexAt` formula and 1-indexed return description are correct. The `@return` says "1-indexed from deploy day" and the formula adds 1 to the difference, confirming 1-indexing.

---

## IDegenerusAffiliate

**Finding AFF-01 — LOW**
**Location:** `contracts/interfaces/IDegenerusAffiliate.sol` lines 50-54 (`affiliateBonusPointsBest` @dev)
**Interface says:** `"Awards 1 point (1%) per 1 ETH of summed score, capped at 50."`
**Code does:** The implementation (`DegenerusAffiliate.sol` lines 679-684) uses a tiered rate:
- Sum ≤ 5 ETH: `points = (sum * 4) / 1 ether` → 4 points per ETH (cap: 20 pts)
- Sum > 5 ETH: `points = 20 + ((sum - 5 ether) * 3) / 2 ether` → 1.5 points per ETH on excess (cap: 50 pts at 25 ETH)

The interface states a flat rate of 1 pt/ETH, which is neither the correct initial rate (4 pts/ETH) nor the correct marginal rate (1.5 pts/ETH). An auditor computing the expected bonus from the interface alone would underestimate the bonus for players with small affiliate volumes and overestimate for players with large volumes. The correct behavior was introduced in v17.1.

---

## IBurnieCoinflip

**Finding BCF-01 — LOW**
**Location:** `contracts/interfaces/IBurnieCoinflip.sol` lines 110-114 (`creditFlip` @dev)
**Interface says:** `"Called by authorized creditors (LazyPass, DegenerusGame, or BurnieCoin) for rewards."`
**Code does:** The `onlyFlipCreditors` modifier in `BurnieCoinflip.sol` (lines 192-203) allows: GAME, QUESTS, AFFILIATE, ADMIN. None of the three named callers in the interface comment appear in the actual modifier:
- "LazyPass" — no contract named LazyPass is a creditor; LazyPass purchases route through GAME
- "BurnieCoin" — COIN (BurnieCoin) is not in the creditor list
- QUESTS, AFFILIATE, and ADMIN are all valid creditors but are not mentioned

An auditor assessing whether AFFILIATE or QUESTS can be griefed or manipulated via `creditFlip` would not find them in the interface NatSpec.

**Finding BCF-02 — INFO**
**Location:** `contracts/interfaces/IBurnieCoinflip.sol` lines 172-178 (`claimCoinflipsForRedemption` @notice)
**Interface says:** `"skips RNG lock"` (absolute statement in the notice)
**Code does:** The rngLocked guard inside `_claimCoinflipsInternal` (line 589 of BurnieCoinflip.sol) is bypassed only when the player's address equals `ContractAddresses.SDGNRS`. For any player whose address is not the sDGNRS contract itself, the BAF processing path can still encounter the rngLocked guard and revert. Since `claimCoinflipsForRedemption` can be called by the sDGNRS contract for any player address, the RNG lock bypass is conditional, not absolute. The notice gives the impression that this path is always lock-free.

---

## IDegenerusJackpots

No discrepancies found.

`runTerminalJackpot` is not declared in this interface (it is in IDegenerusGame and IDegenerusGameModules). The three declared functions (`runBafJackpot`, `recordBafFlip`, `getLastBafResolvedDay`) have accurate NatSpec. No stale EndgameModule caller attribution present.

---

## IStakedDegenerusStonk

**Finding SDG-01 — INFO**
**Location:** `contracts/interfaces/IStakedDegenerusStonk.sol` lines 47-52 (`burn` @notice, @param, @return)
**Interface says:** `"Burn sDGNRS to claim proportional share of backing assets"` with `@return` listing ethOut, stethOut, burnieOut without qualification.
**Code does:** `StakedDegenerusStonk.burn` (lines 479-486) has two entirely different behaviors:
- Post-gameOver: calls `_deterministicBurn`, returns actual ETH/stETH amounts. `burnieOut` is always 0.
- During game: calls `_submitGamblingClaim` and returns `(0, 0, 0)`. The player receives nothing immediately; they must call `claimRedemption()` after the gambling period resolves with an RNG roll.

An auditor or integrator reading the interface would expect `burn()` to immediately return backing assets proportional to the amount burned. The gambling path returning `(0, 0, 0)` and the requirement to call `claimRedemption()` later are not mentioned.

---

## IDegenerusCoin

No discrepancies found.

`vaultEscrow` NatSpec "Only callable by GAME or VAULT contract" matches the implementation check (GAME or VAULT). `mintForGame` and `burnCoin` NatSpec are accurate. No caller misattribution.

---

## IDegenerusGame

**Finding DGM-01 — INFO**
**Location:** `contracts/interfaces/IDegenerusGame.sol` lines 68-69 (`recordMint` @dev access note)
**Interface says:** `"Access restricted to authorized contracts (COIN or GAME self-call)."`
**Code does:** `DegenerusGame.recordMint` (line 341) guards with `if (msg.sender != address(this)) revert E()`. Only self-calls from delegatecall modules (which execute in the context of the Game contract) reach this function. The COIN contract cannot call `recordMint` directly. Mentioning COIN as an authorized caller is inaccurate and could mislead an auditor checking access control completeness for BurnieCoin's integration.

---

## IDegenerusQuests

**Finding QST-01 — INFO**
**Location:** `contracts/interfaces/IDegenerusQuests.sol` lines 43-44 (`rollDailyQuest` @dev)
**Interface says:** `"Called by JackpotModule (via GAME delegatecall)"`
**Code does:** `rollDailyQuest` is called by `DegenerusGameAdvanceModule` (AdvanceModule), not JackpotModule. See `DegenerusGameAdvanceModule.sol` line 275: `quests.rollDailyQuest(day, rngWord)`. JackpotModule does not call this function. The stale attribution would direct an auditor auditing JackpotModule's call surface to expect a quest roll that is not there.

**Finding QST-02 — LOW**
**Location:** `contracts/interfaces/IDegenerusQuests.sol` lines 49, 63, 77, 93, 101, 113 (handler function @dev lines for `handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`)
**Interface says:** Each handler has `"Called by the game contract"` in its @dev notice.
**Code does:** The `onlyCoin` modifier in `DegenerusQuests.sol` (lines 307-316) allows: COIN, COINFLIP, GAME, AFFILIATE. The actual callers for each function are:
- `handleMint`: BurnieCoin (via BurnieCoin.sol line 1123)
- `handleFlip`: BurnieCoinflip (via BurnieCoinflip.sol line 279)
- `handleDecimator`: BurnieCoin (via BurnieCoin.sol line 607)
- `handleAffiliate`: DegenerusAffiliate (via DegenerusAffiliate.sol line 607)
- `handleLootBox`: BurnieCoin (indirectly, via MintModule path)
- `handleDegenerette`: DegenerusGameDegeneretteModule (via DegenerusGameDegeneretteModule.sol line 406)

The DegenerusGame contract is permitted by the modifier but is not the actual runtime caller for any of these handlers. An auditor reviewing access control for the quest handler entry points would search for GAME calls that do not exist, and might miss the actual callers (COIN, COINFLIP, AFFILIATE). This is the most systematic comment discrepancy in this sweep.

---

## IDegenerusGameModules

**Finding MOD-01 — INFO**
**Location:** `contracts/interfaces/IDegenerusGameModules.sol` lines 333-336 (`IDegenerusGameBoonModule.consumeCoinflipBoon` @return) and `contracts/interfaces/IDegenerusGame.sol` line 87 (`consumeCoinflipBoon` @return)
**Interface says (IDegenerusGameBoonModule):** `@return boonBps Boon value in basis points`
**Interface says (IDegenerusGame):** `@return boostBps Boost amount in basis points` (line 87 uses `boostBps` parameter name)
**Code does:** The BoonModule implementation (`DegenerusGameBoonModule.sol` line 39) returns `boonBps`. The name "boostBps" in IDegenerusGame is a mismatch — the coinflip function uses a boon (granted by a deity or lootbox), not a generic boost. Minor inconsistency between the two interface layers for the same logical return value. The decimator function has a reciprocal naming split: "consumeDecimatorBoost" in IDegenerusGameBoonModule vs "consumeDecimatorBoon" in IDegenerusGame (and DegenerusGame implementation). While these are two distinct function names with different 4-byte selectors, DegenerusGame.consumeDecimatorBoon delegates via the module's consumeDecimatorBoost selector, so they refer to the same logic — but the public-facing name and module-facing name diverge.

No EndgameModule references were found in IDegenerusGameModules. All module interfaces (AdvanceModule, GameOverModule, JackpotModule, DecimatorModule, WhaleModule, MintModule, LootboxModule, BoonModule, DegeneretteModule) reflect the current v16.0 contract set with EndgameModule removed.

---

## IStETH

No discrepancies found in scope.

No Degenerus-specific annotations are present. All declared functions match the standard Lido stETH ABI used in production. Deep cross-checking against the external Lido implementation is out of scope per plan specification.

---

## IVaultCoin

No discrepancies found.

All five declared functions (`vaultEscrow`, `vaultMintTo`, `vaultMintAllowance`, `balanceOf`, `transfer`) have accurate NatSpec. The `@dev` header description "Interface for tokens with vault mint allowance (BURNIE)" correctly identifies the primary implementing contract. No Degenerus-specific annotations diverge from BurnieCoin behavior.

---

## IVRFCoordinator

No discrepancies found in scope.

No Degenerus-specific annotations are present. The `VRFRandomWordsRequest` struct fields match Chainlink VRF V2.5 Plus `VRFV2PlusClient.RandomWordsRequest`. The `getSubscription` return values (balance, nativeBalance, reqCount, owner, consumers) match the Chainlink coordinator ABI. Deep cross-checking against the external Chainlink coordinator implementation is out of scope per plan specification.
