# Phase 176 Comment Audit — Plan 01 Findings
**Contracts:** DegenerusGameStorage, DegenerusGame
**Requirement:** CMT-02
**Date:** 2026-04-03
**Total findings this plan:** 2 LOW, 2 INFO

---

## DegenerusGameStorage

**Scope:** `contracts/storage/DegenerusGameStorage.sol` — 1649 lines read in full.

**Focus areas explicitly checked:**
- Slot 0 layout comment (bit allocation map, field widths, cumulative offsets, 32/32 FULL claim)
- Slot 1 layout (currentPrizePool downsized to uint128, 24/32 bytes used)
- Slot 2 elimination — no live "slot 2" comment found; replaced by "SLOT 2+" header (ACCURATE)
- mintPacked_ bit layout and ETH_* constant reference
- Constants and shift/mask values (TICKET_SLOT_BIT, TICKET_FAR_FUTURE_BIT)
- General NatSpec on all functions

---

### DGST-01 — INFO

**Severity:** INFO
**Location:** `DegenerusGameStorage.sol` lines 427–434 (`mintPacked_` comment)

**Comment says:**
```solidity
/// @dev Bit-packed mint history per player.
///      Layout defined by ETH_* constants in DegenerusGame:
///      - Tracks mint counts, bonuses, and eligibility flags.
///      - Single SLOAD/SSTORE for all mint-related player data.
///
///      SECURITY: Packing reduces gas and storage footprint.
///      Bit manipulation requires careful masking (done in DegenerusGame).
```

**Code does:**
The mintPacked_ layout is now defined by constants in `BitPackingLib` (not by "ETH_* constants in DegenerusGame"). No constants named `ETH_*` exist anywhere in DegenerusGame. All bit manipulation is performed by `BitPackingLib.setPacked()` and inline bit operations — not exclusively "done in DegenerusGame". The comment is also incomplete: it mentions only "mint counts, bonuses, and eligibility flags" but does not mention the affiliate bonus cache (bits 185–208, 209–214) or the deity pass flag (bit 184) added in v17.0.

**Fix:** Replace the `ETH_*` reference with `BitPackingLib` and update the description to include the deity pass flag and affiliate bonus cache fields, or cross-reference `BitPackingLib.sol` for the full layout.

---

### DGST-02 — INFO (Verified Accurate)

**Slot 0 layout comment (lines 44–63):** All 15 field entries were verified. Byte offsets, types, and sizes are correct. The total of 32/32 bytes (0 bytes padding — FULL) is arithmetically exact.

**Slot 1 layout comment (lines 66–75):** currentPrizePool is correctly documented as uint128 (16 bytes). Layout [0:6] purchaseStartDay, [6:7] ticketWriteSlot, [7:8] prizePoolFrozen, [8:24] currentPrizePool, [24:32] padding — all verified against variable declarations. 24 bytes used, 8 bytes padding: CORRECT.

**Slot 2 elimination:** No stale "EVM SLOT 2" comment exists. The section heading "SLOT 2+: Full-Width Balances and Pools" (line 358) accurately describes the post-v16 layout where each full-width variable occupies its own slot from slot 2 onward. ACCURATE.

**TICKET_SLOT_BIT (line 184):** `1 << 23` — comment says "Set bit 23 of the uint24 level key". Numeric value matches. ACCURATE.

**TICKET_FAR_FUTURE_BIT (line 192):** `1 << 22` — comment says "Set bit 22 of the uint24 level key". Numeric value matches. Three-key-space description (Slot0 [0x000000–0x3FFFFF], FF [0x400000–0x7FFFFF], Slot1 [0x800000–0xBFFFFF]) is correct. ACCURATE.

**Boon packed struct (lines 1455–1483):** All tier percentage annotations verified against `_*TierToBps` helper functions. Coinflip (5%/10%/25%), lootbox (5%/15%/25%), purchase (5%/15%/25%), decimator (10%/25%/50%), whale (10%/25%/50%), lazy pass (10%/25%/50%) — all match. ACCURATE.

**No discrepancies in Slot 0, Slot 1, shift constants, boon packed tiers, or slot 2 elimination.**

---

## DegenerusGame

**Scope:** `contracts/DegenerusGame.sol` — 2524 lines read in full.

**Focus areas explicitly checked:**
- Delegatecall routing table (EndgameModule removal / current module set)
- Top-level architecture NatSpec (module list, FSM description)
- Access control comments vs actual modifiers and msg.sender checks
- NatSpec on all public/external functions
- Event emission comments
- Constructor comments
- Error/revert condition comments
- Inline clarifying comments

---

### DGM-01 — LOW

**Severity:** LOW
**Location:** `DegenerusGame.sol` lines 14 and 76 (contract-level NatSpec)

**Comment says (line 14):**
```
 *      - Delegatecall modules: endgame, jackpot, mint (must inherit DegenerusGameStorage)
```

**Comment says (line 76):**
```
 * @dev Inherits DegenerusGameStorage for shared storage layout with delegate modules.
 *      Uses delegatecall pattern for complex logic (endgame, jackpot, mint modules).
```

**Code does:**
DegenerusGame now has 8 delegatecall modules: `GAME_ADVANCE_MODULE`, `GAME_BOON_MODULE`, `GAME_DECIMATOR_MODULE`, `GAME_DEGENERETTE_MODULE`, `GAME_JACKPOT_MODULE`, `GAME_LOOTBOX_MODULE`, `GAME_MINT_MODULE`, and `GAME_WHALE_MODULE`. There is no module named "endgame" — the game-over logic is in `DegenerusGameGameOverModule` (`GAME_GAMEOVER_MODULE`), which is called from AdvanceModule (not directly from DegenerusGame). The comment lists only 3 modules from an earlier architecture and names "endgame" which does not match any current module or contract name.

**Fix:** Replace the stale 3-module list with the current 8-module list. Note that `GAME_GAMEOVER_MODULE` is not called directly by DegenerusGame — it is called indirectly via AdvanceModule — so it can be described separately.

---

### DGM-02 — LOW

**Severity:** LOW
**Location:** `DegenerusGame.sol` lines 168–185 (MINT PACKED BIT LAYOUT comment block)

**Comment says:**
```
|  [160-183] mintStreakLast  - Mint streak last completed level (24b)   |
|  [184-227] (reserved)      - 44 unused bits                          |
|  [228-243] unitsAtLevel    - Mints at current level                  |
|  [244]    (deprecated)     - Previously used for bonus tracking      |
```

**Code does (`BitPackingLib.sol`, lines 10–24):**
- Bit 184: `HAS_DEITY_PASS_SHIFT` — live 1-bit flag indicating deity pass holder (not reserved)
- Bits 185–208: `AFFILIATE_BONUS_LEVEL_SHIFT` — cached affiliate bonus level (24 bits, active)
- Bits 209–214: `AFFILIATE_BONUS_POINTS_SHIFT` — cached affiliate bonus points (6 bits, active)
- Bits 215–227: truly unused (13 bits)
- Bits 228–243: `LEVEL_UNITS_SHIFT` (matches comment label "unitsAtLevel")
- Bits 244–255: reserved (not "deprecated" — no single bit at 244 was ever used for bonus tracking)

The comment marks bits 184–227 as "44 unused bits" but 30 of those 44 bits (184–213) are live storage fields that are read and written in multiple call paths. The deity pass flag and affiliate bonus cache are queried in `claimAffiliateDgnrs`, `ethMintStats`, `hasDeityPass`, and `_hasAnyLazyPass`. A reader relying on this comment would conclude these fields do not exist.

**Fix:** Update the MINT PACKED BIT LAYOUT comment to add:
- `[184]     hasDeityPass    - Deity pass flag (1 bit)`
- `[185-208] affiliateBonusLevel - Cached affiliate bonus level (24 bits)`
- `[209-214] affiliateBonusPoints - Cached affiliate bonus points (6 bits)`
- `[215-227] (reserved)     - 13 unused bits`

Change `[244] (deprecated)` to `[244-255] (reserved)` to match BitPackingLib.

---

### DGM-03 — LOW

**Severity:** LOW
**Location:** `DegenerusGame.sol` line 239 (inside `advanceGame()` module-routing comment)

**Comment says:**
```
|  • RNG must be ready (not locked) or recently stale (18h timeout)
```

**Code does:**
The actual VRF timeout is **12 hours** (`elapsed >= 12 hours` in `DegenerusGameAdvanceModule.sol` line 908). The 18h figure is stale — the timeout was reduced from 18h to 12h in an earlier revision. The top-level security comment at line 26 of the same file correctly states "12h VRF timeout", making this an internal inconsistency within DegenerusGame.sol itself.

**Fix:** Change "18h timeout" to "12h timeout" at line 239.

---

### DGM-04 — INFO (Verified Accurate)

**Delegatecall routing table (lines 955–972):** The delegate module helper block lists 8 modules (`ADVANCE`, `BOON`, `DECIMATOR`, `DEGENERETTE`, `JACKPOT`, `LOOTBOX`, `MINT`, `WHALE`). This is the correct set of modules directly called by DegenerusGame. `GAME_GAMEOVER_MODULE` is omitted because it is called by AdvanceModule internally — not directly by DegenerusGame — so its omission is architecturally correct. ACCURATE.

**Access control comments:** All reviewed `@dev Access: X only` annotations match actual msg.sender checks in the function bodies:
- `wireVrf`: says "ADMIN only" — code checks `ContractAddresses.ADMIN` via delegatecall ✓
- `recordMint`: says "self-call only" — code checks `msg.sender != address(this)` ✓
- `recordMintQuestStreak`: says "GAME contract only" — checks `ContractAddresses.GAME` ✓
- `payCoinflipBountyDgnrs`: says "COIN or COINFLIP only" — code checks both ✓
- `consumeCoinflipBoon`: says "COIN or COINFLIP only" — code checks both ✓
- `consumeDecimatorBoon`: says "COIN contract only" — code checks `ContractAddresses.COIN` ✓
- `consumePurchaseBoost`: says "self-call only" — code checks `msg.sender != address(this)` ✓
- `runDecimatorJackpot`: says "Game-only (self-call)" — code checks `msg.sender != address(this)` ✓
- `runTerminalDecimatorJackpot`: same, ACCURATE ✓
- `runTerminalJackpot`: same, ACCURATE ✓
- `consumeDecClaim`: same, ACCURATE ✓
- `resolveRedemptionLootbox`: says "sDGNRS only" — checks `ContractAddresses.SDGNRS` ✓
- `claimWinningsStethFirst`: says "vault contract" — checks `ContractAddresses.VAULT` ✓
- `adminSwapEthForStEth`: says "ADMIN only" — checks `ContractAddresses.ADMIN` ✓
- `adminStakeEthForStEth`: says "vault owner only" — checks `vault.isVaultOwner(msg.sender)` ✓
- `deactivateAfKingFromCoin`: says "COIN or COINFLIP only" — code checks both ✓
- `syncAfKingLazyPassFromCoin`: says "COINFLIP only" — code checks `ContractAddresses.COINFLIP` ✓

**NatSpec on public/external functions:** All `@param`, `@return`, and `@notice` tags reviewed. No discrepancies found between documented and actual parameter names, types, or return values. All `@custom:reverts` annotations match actual revert conditions in function bodies.

**Constructor comments:** Constructor comment accurately describes levelStartTime initialization to `block.timestamp`, dailyIdx set to `GameTimeLib.currentDayIndex()`, levelPrizePool[0] set to BOOTSTRAP_PRIZE_POOL, and vault/SDGNRS deity pass flag setup. ACCURATE.

**Event emission comments:** `LootboxRngThresholdUpdated`, `OperatorApproval`, `WinningsClaimed`, `ClaimableSpent`, `AffiliateDgnrsClaimed`, `AutoRebuyToggled`, `AutoRebuyTakeProfitSet`, `AfKingModeToggled`, `DecimatorAutoRebuyToggled` — all events described in NatSpec match actual `emit` statements. No omissions or incorrect event descriptions.

**Receive function comment (line 2512):** "Accept ETH and add to the future pool reserve" — code actually adds to futurePrizePool, respecting the freeze state (routes to pendingPool when frozen). During freeze, the ETH goes to future pending pool, not directly to future pool. The comment is a simplification but not misleading for its purpose.

**No additional discrepancies found in access control, NatSpec, events, or inline comments.**
