# Phase 111: Lootbox + Boons - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameLootboxModule.sol and DegenerusGameBoonModule.sol -- the lootbox resolution and boon system modules (Unit 9). This phase examines every state-changing function across both contracts using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The modules handle:

- ETH lootbox opening and resolution (openLootBox, with RNG-dependent reward distribution)
- BURNIE lootbox opening (openBurnieLootBox, BURNIE-to-ETH conversion at 80% rate)
- Direct lootbox resolution for decimator claims (resolveLootboxDirect)
- Redemption lootbox resolution with snapshotted activity score (resolveRedemptionLootbox)
- Lootbox reward rolls: 55% tickets, 10% DGNRS, 10% WWXRP, 25% large BURNIE
- Activity score EV multiplier system (80%-135% EV based on player activity, capped at 10 ETH per level)
- Boon system: lootbox-sourced boons with upgrade semantics and single-active-category constraint
- Deity boon system: 3 daily boon slots per deity, deterministic generation, one-per-recipient-per-day
- Boon consumption: coinflip, purchase, decimator boosts (called by other modules via delegatecall)
- Boon expiry: time-based and deity-day-based expiration across 7 boon categories in 2 packed slots
- Boon maintenance: checkAndClearExpiredBoon (nested delegatecall from LootboxModule)
- Activity boon consumption: consumeActivityBoon (adds to levelCount, awards quest streak bonus)
- Whale pass activation via lootbox boon roll
- Lazy pass discount boons via lootbox boon roll

This phase does NOT re-audit module internals of other modules called via subordinate paths (MintModule ticket queue, BurnieCoin minting, sDGNRS pool transfers). Cross-module calls are traced far enough to verify state coherence in the calling context.

**KEY ARCHITECTURAL FEATURE:** BoonModule is called via nested delegatecall from LootboxModule. Both execute in DegenerusGame's storage context. The nested delegatecall pattern means LootboxModule -> delegatecall -> BoonModule operates on the same storage as the parent. This is by design (EIP-170 size limit split) but creates a surface for cached-local-vs-storage bugs if LootboxModule caches a value that BoonModule then writes.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. These are modules, not the router. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### Two-Contract Scope
- **D-04:** Both DegenerusGameLootboxModule.sol and DegenerusGameBoonModule.sol are audited as a single unit. BoonModule is a delegatecall companion to LootboxModule -- they share storage context and are architecturally one module split for EIP-170 compliance.
- **D-05:** BoonModule consumption functions (consumeCoinflipBoon, consumePurchaseBoost, consumeDecimatorBoost) are external entry points called by OTHER modules (CoinflipModule, MintModule, DecimatorModule) via delegatecall. These are Category B for this unit.

### Nested Delegatecall Investigation
- **D-06:** The nested delegatecall pattern (LootboxModule -> delegatecall -> BoonModule) is a PRIORITY investigation area. The Mad Genius must verify that no storage cached locally in _rollLootboxBoons or _resolveLootboxCommon is written by checkAndClearExpiredBoon or consumeActivityBoon during the nested call.
- **D-07:** The _applyBoon function writes to boonPacked[player].slot0 and slot1. Verify that no caller caches these slots before calling _applyBoon.

### Fresh Analysis Mandate
- **D-08:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. The entire point of v5.0 is catching bugs that survived 24 prior milestones.
- **D-09:** RNG paths (lootbox entropy derivation, boon roll, deity boon generation) get the same full treatment as every other function. No reduced scrutiny for "already audited" code.

### Cross-Module Call Boundary
- **D-10:** When lootbox resolution chains into code from other modules (BurnieCoin.creditFlip, sDGNRS.transferFromPool, WWXRP.mintPrize, quest streak bonus), trace the subordinate calls far enough to verify the parent's state coherence. Full internals of those modules are audited in their own unit phases.
- **D-11:** If a subordinate call (including nested delegatecall to BoonModule) writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in.

### Report Format
- **D-12:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into multiple files if it exceeds reasonable length

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/modules/DegenerusGameLootboxModule.sol` -- Lootbox opening, resolution, boon rolling, deity boon system (1,864 lines)
- `contracts/modules/DegenerusGameBoonModule.sol` -- Boon consumption, expiry management, activity boon application (327 lines)

### Storage Layout (verified in Phase 103)
- `contracts/storage/DegenerusGameStorage.sol` -- Shared storage layout inherited by all modules (includes BoonPacked struct layout, lootbox mappings)

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` -- Module function signatures (IDegenerusGameBoonModule interface used for nested delegatecall)

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (Category A/B/C/D pattern, report format)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Phase 103 Taskmaster output (format reference)
- `audit/unit-01/ATTACK-REPORT.md` -- Phase 103 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

### Library Dependencies
- `contracts/libraries/EntropyLib.sol` -- Entropy derivation (entropyStep used extensively in lootbox rolls)
- `contracts/libraries/PriceLookupLib.sol` -- Level pricing (priceForLevel used for ticket/BURNIE calculations)
- `contracts/libraries/BitPackingLib.sol` -- Bit packing helpers (used by BoonModule for mintPacked_ manipulation)

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions -- LootboxModule (from line-by-line read)

**External Entry Points (Category B candidates):**
- `openLootBox(address player, uint48 index)` (L547) -- ETH lootbox opening with RNG, EV multiplier, full reward resolution
- `openBurnieLootBox(address player, uint48 index)` (L627) -- BURNIE lootbox at 80% ETH-equivalent rate, liveness cutoff logic
- `resolveLootboxDirect(address player, uint256 amount, uint256 rngWord)` (L694) -- Direct resolution for decimator claims
- `resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore)` (L729) -- Redemption path with snapshotted activity score
- `deityBoonSlots(address deity)` (L768) -- View function for deity boon slot display
- `issueDeityBoon(address deity, address recipient, uint8 slot)` (L796) -- Deity boon issuance with access control

**Critical Internal Functions (Category C candidates):**
- `_resolveLootboxCommon(...)` (L872) -- Shared resolution logic: boon budget, split threshold, two rolls, whale/lazy pass, distress bonus
- `_rollLootboxBoons(...)` (L1038) -- Boon probability calculation, nested delegatecall to BoonModule, single-category constraint
- `_resolveLootboxRoll(...)` (L1617) -- Single roll: 55% tickets, 10% DGNRS, 10% WWXRP, 25% BURNIE with variance
- `_applyBoon(...)` (L1396) -- Boon application: upgrade semantics, deity overwrite, 12 boon type handlers
- `_activateWhalePass(...)` (L1116) -- Whale pass: 100-level ticket queue, bonus tickets for early levels
- `_applyEvMultiplierWithCap(...)` (L505) -- EV multiplier with per-account-per-level 10 ETH cap tracking
- `_rollTargetLevel(...)` (L834) -- Target level: 90% near (0-4), 10% far (5-50)
- `_boonPoolStats(...)` (L1139) -- Weighted average boon value for EV budgeting
- `_boonFromRoll(...)` (L1269) -- Weighted random selection from boon pool
- `_activeBoonCategory(...)` (L1339) -- Read packed boon state to determine active category
- `_boonCategory(...)` (L1366) -- Map boon type to category (pure)
- `_lootboxTicketCount(...)` (L1713) -- Ticket count with 5-tier variance
- `_lootboxDgnrsReward(...)` (L1763) -- DGNRS reward from pool with 4-tier probability
- `_creditDgnrsReward(...)` (L1793) -- Credit DGNRS from sDGNRS pool

**View/Pure Helpers (Category D candidates):**
- `_lootboxEvMultiplierBps(address player)` (L465) -- Activity score lookup + EV calculation
- `_lootboxEvMultiplierFromScore(uint256 score)` (L474) -- Linear interpolation for EV multiplier
- `_burnieToEthValue(...)` (L1105) -- BURNIE to ETH conversion
- `_lazyPassPriceForLevel(...)` (L1806) -- Lazy pass value calculation over 10 levels
- `_isDecimatorWindow()` (L1822) -- Simple storage read for decimator window state
- `_deityDailySeed(uint48 day)` (L1830) -- Daily RNG seed with fallback chain
- `_deityBoonForSlot(...)` (L1848) -- Deterministic boon generation per deity/day/slot

### Key Functions -- BoonModule (from line-by-line read)

**External Entry Points (Category B):**
- `consumeCoinflipBoon(address player)` (L41) -- Consume coinflip boon, return bonus BPS
- `consumePurchaseBoost(address player)` (L66) -- Consume purchase boost, return bonus BPS
- `consumeDecimatorBoost(address player)` (L91) -- Consume decimator boost, return bonus BPS
- `checkAndClearExpiredBoon(address player)` (L119) -- Clear all expired boons, report if any remain active
- `consumeActivityBoon(address player)` (L280) -- Consume activity boon, apply to mintPacked_ + quest streak

### Established Pattern (from prior phases)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-09/` directory

### Integration Points
- openLootBox/openBurnieLootBox called via delegatecall from DegenerusGame (triggered by player or advanceGame)
- _resolveLootboxCommon -> nested delegatecall to BoonModule (checkAndClearExpiredBoon, consumeActivityBoon)
- _resolveLootboxRoll -> coin.creditFlip (BURNIE minting via BurnieCoin)
- _resolveLootboxRoll -> dgnrs.transferFromPool (sDGNRS pool transfer)
- _resolveLootboxRoll -> wwxrp.mintPrize (WWXRP prize minting)
- _activateWhalePass -> _queueTickets (ticket queue via shared storage)
- consumeActivityBoon -> quests.awardQuestStreakBonus (external call to Quests contract)
- consumeCoinflipBoon/consumePurchaseBoost/consumeDecimatorBoost called by CoinflipModule/MintModule/DecimatorModule via delegatecall

</code_context>

<specifics>
## Specific Ideas

### Nested Delegatecall State Coherence (PRIORITY)
The nested delegatecall from LootboxModule to BoonModule within _rollLootboxBoons is the primary BAF-class attack surface. Specifically:
1. _rollLootboxBoons calls checkAndClearExpiredBoon which writes boonPacked[player].slot0 and slot1
2. _rollLootboxBoons then reads _activeBoonCategory which reads boonPacked[player].slot0 and slot1
3. If _rollLootboxBoons cached any boon state before the delegatecall, the cache is now stale
4. _resolveLootboxCommon calls consumeActivityBoon which writes boonPacked[player].slot1 AND mintPacked_[player]

### Boon Upgrade vs Overwrite Semantics
Lootbox boons use upgrade semantics (newTier > existingTier). Deity boons use overwrite semantics (isDeity=true). Verify that:
1. A lower-tier deity boon cannot downgrade an existing higher-tier lootbox boon in a way that causes loss
2. The single-active-category constraint properly prevents conflicting boon types

### RNG Entropy Quality
- All lootbox entropy derives from keccak256(rngWord, player, day, amount)
- EntropyLib.entropyStep is used for sequential entropy derivation within a single resolution
- Verify no modulo bias in roll distributions (% 20, % 100, % 1000, % 10_000, % BOON_PPM_SCALE)

### EV Multiplier Cap Tracking
- lootboxEvBenefitUsedByLevel[player][lvl] tracks cumulative EV benefit
- Verify the cap cannot be bypassed by splitting lootboxes across multiple transactions
- Verify the cap tracking is correct when evMultiplierBps < NEUTRAL (penalty case)

### BURNIE Lootbox Liveness Cutoff
- BURNIE lootboxes shift tickets to future levels in last 30 days (90 days for level 0)
- This prevents BURNIE-purchased tickets from competing with ETH-purchased tickets near game-over
- Verify the cutoff calculation is correct and cannot be manipulated

</specifics>

<deferred>
## Deferred Ideas

- **Phase 112 coordination:** BurnieCoin.creditFlip is called by LootboxModule -- Phase 112 (BURNIE Token + Coinflip) should verify the minting authority gate.
- **Phase 107 coordination:** _queueTickets and _queueTicketsScaled are used by LootboxModule for ticket queue writes -- Phase 107 (Mint + Purchase Flow) should verify queue correctness.
- **Phase 109 coordination:** DecimatorModule calls resolveLootboxDirect -- Phase 109 should verify the RNG word passed is legitimate.
- **Phase 118:** Full cross-module state coherence verification is deferred to the integration sweep.

</deferred>

---

*Phase: 111-lootbox-boons*
*Context gathered: 2026-03-25*
