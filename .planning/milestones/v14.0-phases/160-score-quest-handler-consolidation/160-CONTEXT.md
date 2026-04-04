# Phase 160: Score & Quest Handler Consolidation - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

playerActivityScore is computed exactly once per purchase transaction with quest streak forwarded from handlers (no cross-contract call), the purchase path uses a unified quest handler covering both daily and level quest progress, mintPrice is passed from the caller on all ETH-aware handlers, daily + level quest storage writes are batched across all 6 handlers, and the DegeneretteModule duplicate is eliminated.

This phase implements the architecture decisions locked in the Phase 159 spec. No architectural re-decisions — only implementation choices.

</domain>

<decisions>
## Implementation Decisions

### Handler Merging (QUEST-01)
- **D-01:** New `handlePurchase` function in DegenerusQuests replaces separate `handleMint` + `handleLootBox` on the purchase path. Single external call that takes both mint quantity and lootbox amount. Loads `activeQuests`, syncs state, processes both quest types, writes once. Saves duplicate state loading + one external call base cost (2,600 gas).
- **D-02:** Non-purchase handlers (handleFlip, handleDecimator, handleAffiliate, handleDegenerette) remain as separate functions — they serve distinct call sites and don't benefit from merging.
- **D-03:** Whether standalone `handleMint` / `handleLootBox` are kept or removed is Claude's discretion based on whether any non-purchase callers exist.

### mintPrice Passthrough (QUEST-02)
- **D-04:** mintPrice passed as parameter to ALL ETH-aware handlers — `handlePurchase` (new), `handleDegenerette`, and any retained standalone `handleMint` / `handleLootBox`. Eliminates `questGame.mintPrice()` STATICCALL from quest handlers entirely.
- **D-05:** Non-ETH handlers (handleFlip, handleDecimator, handleAffiliate) don't use mintPrice — no change needed.

### Batched Quest Writes (QUEST-03)
- **D-06:** Refactor shared internals (`_questHandleProgressSlot` + `_handleLevelQuestProgress`) so daily quest progress and level quest progress are written in a single storage write path. Applies to ALL 6 handlers since they all call the same shared helpers.

### Score Compute-Once (SCORE-02, from Phase 159 spec)
- **D-07:** `playerActivityScore` computed exactly once per purchase, AFTER quest handlers execute. Cached result reused by all downstream consumers (lootbox EV at L709, affiliate routing at L781, x00 century bonus at L886).
- **D-08:** Post-action score ordering accepted — score reflects all quest progress within the current purchase transaction. Minor behavioral change (~0.2% EV per streak level on lootbox path). Document as intentional.

### Quest Streak Forwarding (SCORE-03, from Phase 159 spec §5a)
- **D-09:** Capture `streak` return value from `handlePurchase` (already returned by handlers, currently discarded). Forward as parameter to `_playerActivityScore`. Eliminates `questView.playerQuestStates(player)` STATICCALL (6,800-8,900 gas).
- **D-10:** External `playerActivityScore(address)` view preserved as backward-compatible wrapper that fetches streak via questView internally. BurnieCoin and StakedDegenerusStonk callers unchanged.

### Affiliate STATICCALL (SCORE-04, from Phase 159 spec §5b)
- **D-11:** ACCEPT the affiliate STATICCALL. Not eliminated — co-location more expensive than the warm-address 100 gas base cost. Conscious architectural decision.

### DegeneretteModule Duplicate (SCORE-05, from Phase 159 spec §7)
- **D-12:** Shared `_playerActivityScore` with `streakBaseLevel` parameter. 3-arg internal version in shared base contract (DegenerusGameStorage). DegeneretteModule passes `level + 1`; standard callers pass `_activeTicketLevel()`. 2-arg convenience wrapper for standard callers.
- **D-13:** `_playerActivityScoreInternal` in DegeneretteModule deleted entirely.

### deityPassCount Packing (from Phase 159 spec §3a)
- **D-14:** `deityPassCount` packed into `mintPacked_` at bits 184-199 (uint16, 16 bits). Eliminates 1 cold mapping SLOAD (2,100 gas) per score computation. All read/write sites migrated to bit extraction.

### Claude's Discretion
- Return value structure from `_callTicketPurchase` (multiple returns vs struct) — decide based on stack depth constraints
- Parameter naming conventions (cachedLevel, cachedScore, questStreak, streakBaseLevel suggested in spec)
- Whether `handleMint` / `handleLootBox` are removed entirely or kept as standalone fallbacks
- Plan decomposition and ordering within this phase
- `handlePurchase` signature details beyond what's decided above (e.g., additional return values for reward tracking)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture Spec (PRIMARY — read first)
- `.planning/phases/159-storage-analysis-architecture-design/159-01-ARCHITECTURE-SPEC.md` — Locked architecture: score input map, consumer catalog, packed struct layout, caching strategy, parameter forwarding chain, cross-contract elimination, SLOAD catalog, DegeneretteModule elimination, phase dependencies, gas savings summary

### Activity Score Implementation
- `contracts/DegenerusGame.sol` L2267-2349 — `playerActivityScore` + `_playerActivityScore` (canonical implementation to modify)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` L1069-1142 — `_playerActivityScoreInternal` (duplicate to eliminate)

### Purchase Path (Hot Path)
- `contracts/modules/DegenerusGameMintModule.sol` L631-710 — `_purchaseFor` (entry point)
- `contracts/modules/DegenerusGameMintModule.sol` L836-1021 — `_callTicketPurchase` (ticket processing, score call sites)
- `contracts/modules/DegenerusGameMintModule.sol` L741-834 — `_callLootbox` (lootbox processing, handleLootBox call site)
- `contracts/modules/DegenerusGameMintModule.sol` L1114-1123 — `_questMint` (handleMint call site)

### Quest Handlers (to merge/modify)
- `contracts/DegenerusQuests.sol` L415-509 — `handleMint`
- `contracts/DegenerusQuests.sol` L697-743 — `handleLootBox`
- `contracts/DegenerusQuests.sol` L757-801 — `handleDegenerette` (mintPrice passthrough target)
- `contracts/DegenerusQuests.sol` L523-568 — `handleFlip` (batched writes target)
- `contracts/DegenerusQuests.sol` L582-627 — `handleDecimator` (batched writes target)
- `contracts/DegenerusQuests.sol` L640-682 — `handleAffiliate` (batched writes target)
- `contracts/interfaces/IDegenerusQuests.sol` — Handler signatures (interface changes needed)

### Shared Quest Internals (batched write targets)
- `contracts/DegenerusQuests.sol` — `_questHandleProgressSlot`, `_handleLevelQuestProgress`, `_questSyncState`, `_questCompleteWithPair`

### Cross-Contract Call Targets
- `contracts/DegenerusAffiliate.sol` — `affiliateBonusPointsBest` (kept as STATICCALL per D-11)
- `contracts/interfaces/IDegenerusQuestView.sol` — `playerQuestStates` (eliminated from hot path per D-09, kept in external view wrapper per D-10)

### Score Consumers (non-purchase, benefit indirectly)
- `contracts/modules/DegenerusGameLootboxModule.sol` L457 — lootbox open
- `contracts/modules/DegenerusGameWhaleModule.sol` L735 — whale bundle
- `contracts/modules/DegenerusGameDecimatorModule.sol` L718 — decimator burn
- `contracts/BurnieCoin.sol` L611 — external consumer (signature unchanged)
- `contracts/StakedDegenerusStonk.sol` L800 — external consumer (signature unchanged)

### Storage & Packing
- `contracts/storage/DegenerusGameStorage.sol` — Shared base contract for internal functions + storage layout
- `contracts/libraries/BitPackingLib.sol` — Bit packing constants/utils (add DEITY_PASS_COUNT_SHIFT = 184)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BitPackingLib` provides shift/mask constants and `setPacked` pattern for bit packing — reuse for deityPassCount at bits 184-199
- `_questHandleProgressSlot` is the shared helper used by most handlers — modifying it for batched writes propagates to all handlers
- `_handleLevelQuestProgress` already exists as separate function for level quest tracking — merge target for batching
- `DegenerusGameStorage` already contains ~20 internal utility functions — established home for shared `_playerActivityScore`

### Established Patterns
- All Game modules share storage via delegatecall — internal functions in DegenerusGameStorage are callable by all modules
- Quest handlers follow uniform structure: load activeQuests → sync state → find quest type → update progress → complete
- Score computation reads `level` from storage directly (not parameter) — will change to parameter per architecture spec
- Modules call `IDegenerusGame(address(this)).playerActivityScore(player)` for external self-call — DegeneretteModule will switch to internal call after consolidation
- Named return variables used throughout quest handlers (implicit return at function end)

### Integration Points
- `_questMint` in MintModule is the single wrapper for handleMint — replace with handlePurchase call
- `quests.handleLootBox` called directly in `_callLootbox` — fold into handlePurchase
- `handlePurchase` requires new IDegenerusQuests interface entry
- `onlyCoin` modifier on handlers accepts COIN + COINFLIP + GAME + AFFILIATE — new handlePurchase needs same access

</code_context>

<specifics>
## Specific Ideas

- handlePurchase signature: `(address player, uint32 mintQty, uint256 lootBoxAmount, bool paidWithEth, uint256 mintPrice)` — combines both handler inputs + eliminates callback
- The 3-arg `_playerActivityScore(player, questStreak, streakBaseLevel)` goes in DegenerusGameStorage.sol since it already has internal helpers and all modules inherit from it
- Quest write batching may require restructuring `_questHandleProgressSlot` and `_handleLevelQuestProgress` to share a single state write — the exact mechanism is implementation detail
- Architecture spec Section 10 Open Question #2: `_callTicketPurchase` return structure — planner should check stack depth before choosing multiple returns vs struct

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 160-score-quest-handler-consolidation*
*Context gathered: 2026-04-01*
