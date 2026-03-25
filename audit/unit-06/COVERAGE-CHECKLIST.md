# Unit 6: Whale Purchases -- Coverage Checklist

## Contracts Under Audit
- contracts/modules/DegenerusGameWhaleModule.sol (817 lines)
- Inherits: DegenerusGameMintStreakUtils (62 lines) -> DegenerusGameStorage (1,613 lines)

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- this is a module, not the router)
- Per D-02: Category B functions get full Mad Genius treatment
- Per D-03: Category C functions traced via caller call tree; standalone for [MULTI-PARENT]
- Per D-06: Fresh adversarial analysis -- no trusting prior findings
- Per D-08/D-09: Cross-module subordinate calls traced for state coherence

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 3 | Full Mad Genius (per D-02) |
| C: Internal Helpers (State-Changing) | 9 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 4 | Minimal; verify computation correctness |
| **TOTAL** | **16** | |

**Note:** _lazyPassCost (originally C10 in research) reclassified to D1 because it is declared `private pure` with zero storage reads or writes.

---

## Category B: External State-Changing Functions

| # | Function | Lines | Access Control | Primary Storage Writes | External Calls | Risk Tier | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------------|----------------|-----------|-----------|------------|-------------|-------------|
| B1 | `purchaseWhaleBundle(address,uint256)` | 183-310 | any (via router delegatecall, operator-approved) | boonPacked[].slot0, mintPacked_[], ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxRngPendingEth, lootboxDistressEth[][] | affiliate.getReferrer, dgnrs.poolBalance, dgnrs.transferFromPool, IDegenerusGame.playerActivityScore | Tier 1 | YES | YES | YES | YES |
| B2 | `purchaseLazyPass(address)` | 325-450 | any (via router delegatecall, operator-approved) | boonPacked[].slot1, mintPacked_[], ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxRngPendingEth, lootboxDistressEth[][] | IDegenerusGame.playerActivityScore | Tier 1 | YES | YES | YES | YES |
| B3 | `purchaseDeityPass(address,uint8)` | 470-565 | any (via router delegatecall, operator-approved), rngLockedFlag gate | deityPassPaidTotal[], deityPassCount[], deityPassPurchasedCount[], deityPassOwners[], deityPassSymbol[], deityBySymbol[], boonPacked[].slot1, mintPacked_[], ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxRngPendingEth, lootboxDistressEth[][] | affiliate.getReferrer, dgnrs.poolBalance, dgnrs.transferFromPool, IDegenerusDeityPassMint.mint, IDegenerusGame.playerActivityScore | Tier 1 | YES | YES | YES | YES |

### Risk Tier Justification
- **B1 (Tier 1):** Up to 400 ETH per tx (100 qty x 4 ETH). Complex pricing (boon discount first bundle only, early vs standard). 100-iteration ticket queuing loop. DGNRS reward loop with external calls. Multiple storage writes across boonPacked, mintPacked_, ticket queues, prize pools, lootbox data.
- **B2 (Tier 1):** mintPacked_ cache concern -- reads mintPacked_ then calls _activate10LevelPass which reads/writes mintPacked_. Complex boon validation with deity-day cross-check. Level-gated availability (0-2, x9, x99 exclusion). Dual pricing path.
- **B3 (Tier 1):** Up to 520 ETH per tx. Triangular pricing from deityPassOwners.length. ERC721 external mint (callback vector). rngLockedFlag guard. Symbol uniqueness. 6 deity-specific storage writes.

---

## Category C: Internal Helpers (State-Changing)

| # | Function | Lines | Called By | Key Storage Writes | Flags | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|-----------|-------------------|-------|-----------|------------|-------------|-------------|
| C1 | `_purchaseWhaleBundle(address,uint256)` | 187-310 | B1 | boonPacked[].slot0, mintPacked_[], ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxRngPendingEth, lootboxDistressEth[][] | | YES | YES | YES | YES |
| C2 | `_purchaseLazyPass(address)` | 329-450 | B2 | boonPacked[].slot1, mintPacked_[] (via _activate10LevelPass), ticketsOwedPacked[][], ticketQueue[][], prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxRngPendingEth, lootboxDistressEth[][] | | YES | YES | YES | YES |
| C3 | `_purchaseDeityPass(address,uint8)` | 474-565 | B3 | deityPassPaidTotal[], deityPassCount[], deityPassPurchasedCount[], deityPassOwners[], deityPassSymbol[], deityBySymbol[], boonPacked[].slot1, prizePoolsPacked/pendingPoolsPacked, lootboxEth[][], lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxRngPendingEth, lootboxDistressEth[][] | | YES | YES | YES | YES |
| C4 | `_rewardWhaleBundleDgnrs(address,address,address,address)` | 587-644 | C1 (loop, per quantity) | External only: dgnrs.transferFromPool (Whale pool, Affiliate pool) | | YES | YES | YES | YES |
| C5 | `_rewardDeityPassDgnrs(address,address,address,address)` | 652-712 | C3 | External only: dgnrs.transferFromPool (Whale pool, Affiliate pool) | | YES | YES | YES | YES |
| C6 | `_recordLootboxEntry(address,uint256,uint24,uint256)` | 714-758 | C1, C2, C3 | lootboxDay[][], lootboxBaseLevelPacked[][], lootboxEvScorePacked[][], lootboxEthBase[][], lootboxEth[][], lootboxRngPendingEth, lootboxDistressEth[][], mintPacked_[] (via C9), boonPacked[].slot0 (via C8) | [MULTI-PARENT] | YES | YES | YES | YES |
| C7 | `_maybeRequestLootboxRng(uint256)` | 762-764 | C6 | lootboxRngPendingEth | | YES | YES | YES | YES |
| C8 | `_applyLootboxBoostOnPurchase(address,uint48,uint256)` | 773-802 | C6 | boonPacked[].slot0 (lootbox fields cleared on consume/expiry) | | YES | YES | YES | YES |
| C9 | `_recordLootboxMintDay(address,uint32,uint256)` | 808-815 | C6 | mintPacked_[] (day field only, conditional on day mismatch) | [MULTI-PARENT] (via C6, called from C1/C2/C3) | YES | YES | YES | YES |

---

## Category D: View/Pure Functions

| # | Function | Lines | Reads/Computes | Security Note | Reviewed? |
|---|----------|-------|---------------|---------------|-----------|
| D1 | `_lazyPassCost(uint24)` | 573-580 | Sums PriceLookupLib.priceForLevel over 10 levels | Pure; verify PriceLookupLib correctness (Phase 117). No overflow risk: 10 levels x max price. | YES |
| D2 | `_whaleTierToBps(uint8)` | Storage L1551-1557 | Maps tier 1->1000, 2->2500, 3->5000 | Inherited from Storage. Tier 0 returns 0. | YES |
| D3 | `_lazyPassTierToBps(uint8)` | Storage L1559-1565 | Maps tier 1->1000, 2->2500, 3->5000 | Inherited from Storage. Tier 0 returns 0. | YES |
| D4 | `_lootboxTierToBps(uint8)` | Storage L1527-1533 | Maps tier 1->500, 2->1500, 3->2500 | Inherited from Storage. Used by C8 for boost calculation. | YES |

---

## Inherited Helper Functions (Traced in Call Trees)

These are defined in DegenerusGameStorage and DegenerusGameMintStreakUtils. They are NOT standalone audit targets for this phase -- they are traced within their callers' call trees to verify state coherence per D-08/D-09. Full audit of these functions occurs in their respective unit phases (Phase 103 for Storage, Phase 107 for MintModule).

| Function | Source | Lines | Called By | State Impact | Cache Concern |
|----------|--------|-------|-----------|-------------|---------------|
| `_queueTickets(address,uint24,uint32)` | Storage | 528-549 | C1 (100-iter loop), C2 (via bonus), C3 (100-iter loop) | ticketsOwedPacked[][], ticketQueue[][] | Far-future ticket RNG lock check |
| `_activate10LevelPass(address,uint24,uint32)` | Storage | 982-1062 | C2 | mintPacked_[] (levelCount, frozenUntilLevel, bundleType, lastLevel, day), ticketsOwedPacked[][], ticketQueue[][] | **KEY CONCERN:** Reads/writes mintPacked_[buyer]. C2 reads frozenUntilLevel from mintPacked_ BEFORE calling this. |
| `_awardEarlybirdDgnrs(address,uint256,uint24)` | Storage | 914-974 | C1, C2, C3 | earlybirdDgnrsPoolStart, earlybirdEthIn. External: dgnrs.transferFromPool(Earlybird), dgnrs.transferBetweenPools | May dump earlybird pool to lootbox pool |
| `_setPrizePools(uint128,uint128)` | Storage | 651-653 | C1, C2, C3 | prizePoolsPacked | Packed 128+128 write |
| `_getPrizePools()` | Storage | 655-659 | C1, C2, C3 | None (view) | |
| `_setPendingPools(uint128,uint128)` | Storage | 661-663 | C1, C2, C3 | pendingPoolsPacked | Packed 128+128 write |
| `_getPendingPools()` | Storage | 665-669 | C1, C2, C3 | None (view) | |
| `_simulatedDayIndex()` | Storage | 1134-1137 | C1, C2, C3 | None (view) | |
| `_currentMintDay()` | Storage | 1144-1151 | C1 (via _setMintDay) | None (view) | |
| `_setMintDay(uint256,uint32,uint256,uint256)` | Storage | 1153-1161 | C1 | Returns modified packed data (no storage write itself) | Pure transformation |
| `_isDistressMode()` | Storage | 171-173 | C6 | None (view) | |
| `_queueTicketRange(address,uint24,uint24,uint32)` | Storage | ~1061 | _activate10LevelPass | ticketsOwedPacked[][], ticketQueue[][] | Called from within _activate10LevelPass |

---

## Cross-Module External Calls

| Call | From Functions | Target Contract | State Impact on External Contract |
|------|---------------|----------------|----------------------------------|
| `affiliate.getReferrer(address)` | C1, C3 | IDegenerusAffiliate | View only |
| `dgnrs.poolBalance(Pool)` | C4, C5 | IStakedDegenerusStonk | View only |
| `dgnrs.transferFromPool(Pool,address,uint256)` | C4, C5, _awardEarlybirdDgnrs | IStakedDegenerusStonk | Transfers sDGNRS tokens |
| `dgnrs.transferBetweenPools(Pool,Pool,uint256)` | _awardEarlybirdDgnrs (one-shot) | IStakedDegenerusStonk | Moves earlybird -> lootbox pool |
| `IDegenerusDeityPassMint.mint(address,uint256)` | C3 | DeityPass NFT | Mints ERC721 token |
| `IDegenerusGame(address(this)).playerActivityScore(address)` | C6 | Self (delegatecall context) | View only |

---

## Key Audit Flags

### mintPacked_ Cache Concern (B2/C2)
`_purchaseLazyPass` reads `mintPacked_[buyer]` at line 361 to unpack `frozenUntilLevel`. Later calls `_activate10LevelPass` (Storage L982) which ALSO reads `mintPacked_[buyer]` at Storage L987, modifies it, and writes back at Storage L1059. The Mad Genius MUST verify:
1. Does _purchaseLazyPass write to mintPacked_ after _activate10LevelPass returns?
2. Does the lootbox call at L449 pass a stale mintPacked_ value?

### _recordLootboxMintDay Cache Parameter (C9)
All three purchase paths pass a `cachedPacked` value to `_recordLootboxEntry` -> `_recordLootboxMintDay`. If `cachedPacked` is stale relative to the actual `mintPacked_[player]` state, the conditional write at L813-814 could overwrite fresh data. Verify each caller passes a current value.

### Deity Pass ERC721 Callback (B3/C3)
External `IDegenerusDeityPassMint.mint(buyer, symbolId)` at L521 could trigger `onERC721Received` callback. All deity-specific state writes (deityPassCount, deityBySymbol, etc.) occur BEFORE the mint call. Verify re-entry is blocked.

### DGNRS Pool Drain via Loop (C4)
`_rewardWhaleBundleDgnrs` is called in a loop (once per quantity, up to 100). Each iteration reads fresh poolBalance but the pool diminishes per transfer. Verify total drain is bounded and reserved allocation is respected per iteration.

---

*Checklist built: 2026-03-25*
*Updated: 2026-03-25 -- All Analyzed columns set to YES after Mad Genius attack report and Taskmaster coverage verification. Coverage: PASS (16/16).*
