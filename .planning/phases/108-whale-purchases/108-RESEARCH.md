# Phase 108: Whale Purchases - Research

## Contract Under Audit

**DegenerusGameWhaleModule.sol** -- 817 lines (including constants, events, interface)
- Inherits: DegenerusGameMintStreakUtils -> DegenerusGameStorage
- Executed via delegatecall from DegenerusGame.sol (all storage reads/writes operate on Game's storage)
- 3 external entry points, 3 private implementations, 7 private helpers

## Complete Function Inventory

### Category B: External State-Changing Functions (3)

| # | Function | Lines | Access Control | Risk Tier | Key Concern |
|---|----------|-------|---------------|-----------|-------------|
| B1 | `purchaseWhaleBundle(address,uint256)` | 183-185 | any (via delegatecall from router) | Tier 1 | Complex pricing, 100-level ticket queuing loop, boon consumption, DGNRS rewards, lootbox entry |
| B2 | `purchaseLazyPass(address)` | 325-327 | any (via delegatecall from router) | Tier 1 | Boon discount logic, mintPacked_ cache concern with _activate10LevelPass, level-gated availability |
| B3 | `purchaseDeityPass(address,uint8)` | 470-472 | any (via delegatecall from router) | Tier 1 | Triangular pricing, ERC721 external mint, rngLockedFlag check, symbol uniqueness, DGNRS rewards |

**Risk tier justification:** All three are Tier 1 because each involves ETH payment with complex pricing logic, multiple storage writes, external calls, boon consumption, and fund distribution. The module handles high-value transactions (whale bundles up to 400 ETH, deity passes up to 520 ETH).

### Category C: Internal/Private State-Changing Helpers (10)

| # | Function | Lines | Called By | Key Storage Writes | Flags |
|---|----------|-------|-----------|-------------------|-------|
| C1 | `_purchaseWhaleBundle(address,uint256)` | 187-310 | B1 | boonPacked[].slot0, mintPacked_[], ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxRngPendingEth, lootboxDistressEth[][] | |
| C2 | `_purchaseLazyPass(address)` | 329-450 | B2 | boonPacked[].slot1, mintPacked_[], ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxRngPendingEth, lootboxDistressEth[][] | |
| C3 | `_purchaseDeityPass(address,uint8)` | 474-565 | B3 | boonPacked[].slot1, deityPassPaidTotal[], deityPassCount[], deityPassPurchasedCount[], deityPassOwners[], deityPassSymbol[], deityBySymbol[], mintPacked_[] (via earlybird), prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxRngPendingEth, lootboxDistressEth[][] | |
| C4 | `_rewardWhaleBundleDgnrs(address,address,address,address)` | 587-644 | C1 (loop) | External: dgnrs.transferFromPool (Whale pool, Affiliate pool) | [MULTI-PARENT: called per-quantity in loop] |
| C5 | `_rewardDeityPassDgnrs(address,address,address,address)` | 652-712 | C3 | External: dgnrs.transferFromPool (Whale pool, Affiliate pool) | |
| C6 | `_recordLootboxEntry(address,uint256,uint24,uint256)` | 714-758 | C1, C2, C3 | lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxEth[][], lootboxRngPendingEth, lootboxDistressEth[][], mintPacked_[] (via _recordLootboxMintDay), boonPacked[].slot0 (via _applyLootboxBoostOnPurchase) | [MULTI-PARENT] |
| C7 | `_maybeRequestLootboxRng(uint256)` | 762-764 | C6 | lootboxRngPendingEth | |
| C8 | `_applyLootboxBoostOnPurchase(address,uint48,uint256)` | 773-802 | C6 | boonPacked[].slot0 (lootbox fields cleared on consumption/expiry) | |
| C9 | `_recordLootboxMintDay(address,uint32,uint256)` | 808-815 | C6 | mintPacked_[] (day field only) | [MULTI-PARENT: called from C6 which is called by C1, C2, C3] |
| C10 | `_lazyPassCost(uint24)` | 573-580 | C2 | None (pure computation) | RECLASSIFY to D |

**Note on C10:** `_lazyPassCost` is declared `private pure` -- it reads no storage and writes no storage. It should be Category D. Included here for completeness; reclassified below.

### Category D: View/Pure Functions (3)

| # | Function | Lines | Reads/Computes | Security Note |
|---|----------|-------|---------------|---------------|
| D1 | `_lazyPassCost(uint24)` | 573-580 | Sums PriceLookupLib.priceForLevel over 10 levels | Pure computation; verify PriceLookupLib correctness is in Phase 117 (Libraries) |
| D2 | `_whaleTierToBps(uint8)` | Storage L1551-1557 | Maps tier (1/2/3) to discount BPS (1000/2500/5000) | Inherited from Storage; verify mapping correctness |
| D3 | `_lazyPassTierToBps(uint8)` | Storage L1559-1565 | Maps tier (1/2/3) to discount BPS (1000/2500/5000) | Inherited from Storage; verify mapping correctness |

**Additional inherited helpers traced in call trees (not standalone D entries -- these are audited in their own unit phases):**
- `_simulatedDayIndex()` (Storage L1134) -- view, returns current day
- `_currentMintDay()` (Storage L1144) -- view, returns current mint day
- `_setMintDay()` (Storage L1153) -- internal, updates day in packed data
- `_isDistressMode()` (Storage L171) -- view, checks distress mode flag
- `_lootboxTierToBps(uint8)` (Storage L1527) -- pure, maps boost tier to BPS

### Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 3 | Full Mad Genius (per D-02) |
| C: Internal Helpers (State-Changing) | 9 (C10 reclassified to D) | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 4 (including reclassified C10) | Minimal; verify computation correctness |
| **TOTAL** | **16** (in WhaleModule itself) | |

Plus ~12 inherited helpers from Storage/MintStreakUtils traced within call trees.

## Cross-Module Delegatecall Map

DegenerusGameWhaleModule is called via delegatecall from DegenerusGame.sol router:
- `purchaseWhaleBundle` dispatched from `_purchaseWhaleBundleFor()` in Game.sol (L632-638)
- `purchaseLazyPass` dispatched from `_purchaseLazyPassFor()` in Game.sol (L657-660)
- `purchaseDeityPass` dispatched from `_purchaseDeityPassFor()` in Game.sol (L677-680)

All storage reads/writes execute in Game's storage context.

## External Calls Made by This Module

| Call | From | Target Contract | State Impact |
|------|------|----------------|-------------|
| `affiliate.getReferrer(address)` | C1, C3 | IDegenerusAffiliate | View only (reads referrer mapping) |
| `dgnrs.poolBalance(Pool)` | C4, C5 | IStakedDegenerusStonk | View only (reads pool balance) |
| `dgnrs.transferFromPool(Pool,address,uint256)` | C4, C5 | IStakedDegenerusStonk | Transfers sDGNRS tokens from pool to recipient |
| `IDegenerusDeityPassMint.mint(address,uint256)` | C3 | DeityPass NFT | Mints ERC721 token |
| `IDegenerusGame(address(this)).playerActivityScore(address)` | C6 | Self (delegatecall context) | View only (reads player activity score) |
| `PriceLookupLib.priceForLevel(uint24)` | D1 | Library (inlined) | Pure computation |

## Risk Tiers for Category B Functions

All three Category B functions are Tier 1 (highest risk) because:

**B1 - purchaseWhaleBundle:**
- Handles up to 400 ETH per transaction (100 bundles x 4 ETH)
- Complex pricing with boon discount on first bundle only
- 100-iteration ticket queuing loop
- DGNRS reward loop (quantity iterations of external calls)
- x99 level guard for minimum 2 bundles
- Multiple storage writes across boonPacked, mintPacked_, ticket queues, prize pools, lootbox data

**B2 - purchaseLazyPass:**
- Cached-local-vs-storage concern: reads mintPacked_ then calls _activate10LevelPass which reads/writes mintPacked_
- Complex boon validation with deity-day cross-check
- Level-gated availability with multiple conditions (0-2, x9, x99 exclusion, boon override)
- Frozen level renewal window check (7-level threshold)
- Dual pricing path: flat 0.24 ETH at early levels vs computed sum at level 3+

**B3 - purchaseDeityPass:**
- Highest single-purchase value (up to 520 ETH for 32nd pass)
- Triangular pricing formula dependent on deityPassOwners.length
- ERC721 external mint call (potential callback vector)
- rngLockedFlag check (unique to deity pass, not on whale/lazy)
- Symbol uniqueness enforcement (32 symbols, first-come-first-served)

## Key Pitfalls

### 1. mintPacked_ Cache Incoherence (Lazy Pass) -- HIGH PRIORITY
`_purchaseLazyPass` reads `mintPacked_[buyer]` at L361 to unpack `frozenUntilLevel`, then calls `_activate10LevelPass` at L417 which reads mintPacked_ again at Storage L987, modifies it, and writes back at Storage L1059. After that, `_purchaseLazyPass` calls `_recordLootboxEntry` at L449 passing the OLD `mintPacked_[buyer]` value. Inside `_recordLootboxEntry`, `_recordLootboxMintDay` at L723 may write to mintPacked_ using the old cached value, potentially overwriting the `_activate10LevelPass` update.

**However:** The lazy pass does NOT directly write mintPacked_ after calling _activate10LevelPass -- it reads `mintPacked_[buyer]` FRESH at L449 for the lootbox call. This needs careful verification.

### 2. _recordLootboxEntry cachedPacked Parameter
All three purchase functions pass a `cachedPacked` value (from `mintPacked_[buyer]` or `data`) to `_recordLootboxEntry`. Inside, `_recordLootboxMintDay` at L808-815 may overwrite mintPacked_ using this cached value. If the cached value is stale (from before a write to mintPacked_), the overwrite could revert changes.

**Whale bundle (C1):** Writes `mintPacked_[buyer] = data` at L262, then passes `data` to `_recordLootboxEntry` at L309. The `data` variable IS the just-written value, so no staleness concern here.

**Lazy pass (C2):** Calls `_activate10LevelPass` at L417 which writes mintPacked_. Then at L449, reads `mintPacked_[buyer]` FRESH. No staleness.

**Deity pass (C3):** Calls `_awardEarlybirdDgnrs` at L512 which may write mintPacked_ via Storage. Then at L563, reads `mintPacked_[buyer]` FRESH. No staleness.

### 3. Deity Pass ERC721 Callback
`_purchaseDeityPass` calls `IDegenerusDeityPassMint.mint(buyer, symbolId)` at L521. If the DeityPass contract implements `_safeMint`, the `onERC721Received` callback to the buyer could re-enter. However, all critical state (deityPassCount, deityBySymbol, deityPassOwners) is written BEFORE the mint call, so re-entry into purchaseDeityPass would fail the `deityPassCount[buyer] != 0` check at L479.

### 4. DGNRS Pool Drain via Whale Purchases
Both `_rewardWhaleBundleDgnrs` (C4) and `_rewardDeityPassDgnrs` (C5) read `affiliateReserve` from sDGNRS, then subtract `reserved = levelDgnrsAllocation[level] - levelDgnrsClaimed[level]`. If `reserved >= affiliateReserve`, the function returns early, preventing drain. But whale bundle calls C4 in a loop (once per quantity). Each iteration reads a FRESH poolBalance -- after the previous iteration's transfer reduced it. This is correct behavior (diminishing returns per iteration) but needs verification that the total across iterations can't exceed what's safe.

### 5. Boon Consumption Atomicity
Each purchase function reads boonPacked, checks expiry, computes discount, then clears the boon fields. The clear happens before price validation (msg.value check). If msg.value is wrong, the transaction reverts, rolling back the boon clear. This is correct -- atomicity is guaranteed by the EVM transaction model.

## Validation Architecture

### Price Validation
All three purchase functions enforce `msg.value == totalPrice` with revert on mismatch. No partial payment or overpayment paths exist.

### Access Control
All three external functions are called via delegatecall from the router, which resolves the `buyer` address from operator approval logic. The functions themselves have no additional access control beyond:
- `gameOver` check (all three)
- `rngLockedFlag` check (deity pass only)
- Level-gated availability (lazy pass: levels 0-2 or x9 excluding x99, unless boon)
- Deity pass uniqueness (one per player, one per symbol)
- Whale bundle quantity (1-100)

### Fund Distribution
All three split funds between next/future prize pools:
- Pre-game (level 0): 30% next, 70% future
- Post-game (level > 0): 5% next, 95% future
- Lazy pass uses fixed 10% future, 90% next

Distribution uses `prizePoolFrozen` flag to select between active and pending pools.

### Lootbox Recording
All three record lootbox entries via shared `_recordLootboxEntry`:
- Amount = price * lootboxBps (20% presale, 10% post)
- Boost boon applied if active (5/15/25% bonus capped at 10 ETH base)
- Day coherence enforced (same RNG index, same day or revert)
- Distress mode ETH tracked separately

---

*Research complete: 2026-03-25*
