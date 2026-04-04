# Phase 159: Storage Analysis & Architecture Design - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning
**Source:** Auto-mode (decisions derived from codebase analysis + requirements + success criteria)

<domain>
## Phase Boundary

Map the current storage layout, cross-contract call graph, and SLOAD patterns for activity score computation and quest handling on the purchase path. Produce a concrete architecture design (packed struct layout or justified rejection, caching strategy, handler consolidation plan) that locks all structural decisions for Phases 160-162.

This phase produces a design spec only -- no code changes.

</domain>

<decisions>
## Implementation Decisions

### Analysis Depth
- **D-01:** Purchase-path-first analysis with a complete consumer catalog. The purchase path (MintModule._purchaseFor + _callTicketPurchase) is the hot path and primary optimization target, but the design must enumerate ALL playerActivityScore consumers to ensure no non-purchase path breaks.
- **D-02:** Current known consumers: MintModule (3 sites: lootbox EV score L709, claimable payment L781, x00 century bonus L886), LootboxModule (L457), DegeneretteModule (L473, uses duplicate _playerActivityScoreInternal), WhaleModule (L735), BurnieCoin.sol (L611), StakedDegenerusStonk (L800).

### Struct Packing Investigation
- **D-03:** Investigate BOTH score-only packing AND combined score+quest packing, then recommend based on gas savings vs complexity. The quest data lives in DegenerusQuests (separate contract), so combined packing requires either data co-location or parameter passing -- needs analysis to determine if worthwhile.
- **D-04:** The packed struct analysis must account for: mintPacked_ (already packed per-player), deityPassCount, level, quest streak (currently external call to questView.playerQuestStates), affiliate bonus (currently external call to affiliate.affiliateBonusPointsBest).

### Caching Mechanism
- **D-05:** Stack-passed parameters as primary caching strategy. Paris EVM target means NO transient storage (EIP-1153 requires Cancun+). Within-function local vars are fine; cross-function reuse requires explicit parameter passing.
- **D-06:** The design must specify WHERE the score is computed once (which function), and HOW it reaches all downstream consumers (parameter passing chain). Current hot path: _purchaseFor calls _callTicketPurchase (which calls playerActivityScore at x00 levels), then separately lootbox path calls playerActivityScore again.

### Cross-Contract Call Elimination
- **D-07:** Parameter forwarding as primary approach, with data co-location as fallback if forwarding proves infeasible. On the purchase path, quest handlers (quests.handleMint, quests.handleLootBox) already execute before or alongside score computation -- they could return quest streak data for forwarding into the score function.
- **D-08:** Two external calls to eliminate from _playerActivityScore: (1) questView.playerQuestStates(player) for quest streak, (2) affiliate.affiliateBonusPointsBest(currLevel, player) for affiliate bonus. Each costs ~2600 gas base + internal SLOADs.

### SLOAD Deduplication Catalog
- **D-09:** The design spec must catalog every duplicate SLOAD on the purchase path with exact line numbers and read counts. Known duplicates from initial scan: level (4x), price (2x), compressedJackpotFlag (2x), jackpotCounter (2x), jackpotPhaseFlag (2x), claimableWinnings[buyer] (2-3x).
- **D-10:** For each duplicate, the spec must propose: (a) where the single read occurs, (b) how the cached value reaches all consumers, (c) whether the fix is parameter-passing or local-variable-based.

### DegeneretteModule Duplicate
- **D-11:** _playerActivityScoreInternal (DegeneretteModule:1069) is a near-exact duplicate of _playerActivityScore (DegenerusGame:2273). Difference: streak base uses `level + 1` vs `_activeTicketLevel()`. The design must specify how to eliminate this duplicate while preserving the streak base difference.

### Claude's Discretion
- Whether to use static SLOAD counting from source code or supplement with forge gas traces for actual numbers
- Format and structure of the design spec document
- Level of detail in the packed struct bit allocation map
- Whether to include a gas savings estimate per optimization or just structural decisions

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Activity Score Implementation
- `contracts/DegenerusGame.sol` L2267-2349 -- playerActivityScore + _playerActivityScore (canonical implementation)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` L1069-1130 -- _playerActivityScoreInternal (duplicate to eliminate)

### Purchase Path (Hot Path)
- `contracts/modules/DegenerusGameMintModule.sol` L631-710 -- _purchaseFor (entry point, reads level/price/claimableWinnings)
- `contracts/modules/DegenerusGameMintModule.sol` L836-1021 -- _callTicketPurchase (reads level/price/jackpotPhaseFlag/compressedJackpotFlag/jackpotCounter, calls playerActivityScore)
- `contracts/modules/DegenerusGameMintModule.sol` L1114-1123 -- _questMint (calls quests.handleMint)

### Quest Handlers
- `contracts/DegenerusQuests.sol` L415+ -- handleMint, L640+ handleAffiliate, L697+ handleLootBox
- `contracts/interfaces/IDegenerusQuests.sol` -- Handler signatures
- `contracts/interfaces/IDegenerusQuestView.sol` -- playerQuestStates view used by score

### Cross-Contract Call Targets
- `contracts/DegenerusAffiliate.sol` -- affiliateBonusPointsBest (called by score computation)
- `contracts/DegenerusQuests.sol` -- playerQuestStates (called by score computation via questView)

### Other Score Consumers
- `contracts/modules/DegenerusGameLootboxModule.sol` L457 -- lootbox purchase score
- `contracts/modules/DegenerusGameWhaleModule.sol` L735 -- whale bundle score
- `contracts/modules/DegenerusGameDecimatorModule.sol` L718 -- decimator burn score
- `contracts/BurnieCoin.sol` L611 -- BurnieCoin decimator burn score
- `contracts/StakedDegenerusStonk.sol` L800 -- sDGNRS claim score

### Prior Gas Analysis
- `.planning/phases/152-delta-audit/152-02-GAS-ANALYSIS.md` -- advanceGame gas ceiling baseline
- `.planning/phases/155-economic-gas-analysis/155-CONTEXT.md` -- Phase 153 spec references

### Storage Layout
- `contracts/storage/DegenerusGameStorage.sol` -- All Game storage variables including mintPacked_, level, price, jackpotPhaseFlag, etc.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `mintPacked_[player]` already packs levelCount + frozenUntilLevel + bundleType per player via BitPackingLib -- pattern for additional packing
- `BitPackingLib` provides shift/mask constants for existing packed fields
- Phase 153 spec (153-01-LEVEL-QUEST-SPEC.md) has SLOAD/SSTORE gas budgets per quest operation

### Established Patterns
- Score computation reads `level` as storage var, not parameter -- all modules use `level` directly
- Cross-contract calls use immutable address constants (questView, affiliate) -- no proxy overhead
- Quest handlers follow uniform structure: load activeQuests, get currentDay, sync, check type, accumulate, complete
- All modules within DegenerusGame delegate-call into storage, so storage vars (level, price, etc.) are shared

### Integration Points
- _purchaseFor is the single entry point for all ETH ticket purchases
- _callTicketPurchase is called from _purchaseFor (ETH tickets) and _purchaseBurnieLootboxFor (BURNIE tickets)
- playerActivityScore is an external view on DegenerusGame that delegates to _playerActivityScore -- modules call it via IDegenerusGame(address(this))
- DegeneretteModule cannot call _playerActivityScore because it's in DegenerusGame.sol, not a shared storage module

### Key Constraint
- Paris EVM target -- no transient storage (EIP-1153), no PUSH0. Caching must use stack/memory/calldata passing.
- All modules share storage via delegatecall, so a "cached" storage slot written by one module is readable by another within the same tx -- but that's SSTORE+SLOAD (20K+2.1K gas), far worse than parameter passing.

</code_context>

<specifics>
## Specific Ideas

- The duplicate _playerActivityScoreInternal in DegeneretteModule exists because DegeneretteModule is a separate file that can't call DegenerusGame's internal function. The fix is likely to make _playerActivityScore a shared function in GameStorage or pass the score as a parameter.
- Quest streak is only used once in score computation (L2324). If handleMint/handleLootBox already runs before score is needed, the streak could be returned from the handler call and forwarded.
- affiliate.affiliateBonusPointsBest is a pure view that reads affiliate storage. The only way to avoid this cross-contract call is to either co-locate the data or accept the call overhead.
- The x00 century bonus at MintModule:885 is the primary purchase-path consumer of playerActivityScore -- it only fires at century levels (every 100 levels). Other consumers (lootbox EV, whale) are on different paths.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 159-storage-analysis-architecture-design*
*Context gathered: 2026-04-01*
