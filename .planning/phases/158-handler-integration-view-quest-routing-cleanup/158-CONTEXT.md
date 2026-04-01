# Phase 158: Handler Integration, View & Quest Routing Cleanup - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning
**Source:** Auto-mode (decisions derived from prior phases + success criteria)

<domain>
## Phase Boundary

Wire the 6 existing quest handlers to call `_handleLevelQuestProgress` for level quest tracking, then remove the BurnieCoin `notify*` middleman functions so game modules call DegenerusQuests handlers directly. Also expose `getPlayerLevelQuestView` (already implemented in Phase 157).

</domain>

<decisions>
## Implementation Decisions

### Level Quest Handler Wiring (6 handlers)
- **D-01:** Each of the 6 handlers (handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette) gets a `_handleLevelQuestProgress` call AFTER existing daily quest logic, BEFORE the return statement. This matches the integration map Section 5.1 pattern.
- **D-02:** Handler type matching: each handler passes its own quest type constant. handleMint passes `QUEST_TYPE_MINT_ETH` or `QUEST_TYPE_MINT_BURNIE` based on `paidWithEth`. handleDegenerette passes `QUEST_TYPE_DEGENERETTE_ETH` or `QUEST_TYPE_DEGENERETTE_BURNIE` based on `paidWithEth`.
- **D-03:** Delta values: handleMint ETH uses `uint256(quantity) * mintPrice`, handleMint BURNIE uses `quantity` (ticket count). handleFlip/handleDecimator/handleAffiliate/handleDegenerette_BURNIE use their existing BURNIE-denominated amounts. handleLootBox/handleDegenerette_ETH use their ETH amounts.
- **D-04:** `mintPrice` parameter: handlers that don't need it for daily quests may still need it for `_handleLevelQuestProgress` (the function needs it for ETH-based targets). handleFlip/handleDecimator/handleAffiliate pass `0` since their targets are BURNIE-denominated (20,000 ether constant). handleMint ETH, handleLootBox, and handleDegenerette_ETH pass `questGame.mintPrice()` (already loaded in some handlers for daily quest logic).
- **D-05:** Return values unchanged — handlers still return `(uint256 reward, uint8 questType, uint32 streak, bool completed)` reflecting daily quest status. Level quest completion is signaled via `LevelQuestCompleted` event and direct `creditFlip` call inside `_handleLevelQuestProgress`.

### Quest Routing Cleanup (BurnieCoin middleman removal)
- **D-06:** Remove from BurnieCoin.sol: `notifyQuestMint`, `notifyQuestLootBox`, `notifyQuestDegenerette`, `affiliateQuestReward`, `_questApplyReward`, and the `QuestCompleted` event. These are pure forwarding wrappers that add gas for a cross-contract hop. `affiliateQuestReward` is called from DegenerusAffiliate.sol line 607 — same pattern as the others.
- **D-07:** Game modules (MintModule, LootboxModule, DegeneretteModule) and DegenerusAffiliate call DegenerusQuests handlers directly instead of going through BurnieCoin. This requires adding `IDegenerusQuests` import and `quests` constant to each calling contract. DegenerusAffiliate.sol line 607 currently calls `coin.affiliateQuestReward(winner, affiliateShareBase)` — rewire to `quests.handleAffiliate(winner, affiliateShareBase)` and handle the reward/creditFlip inline.
- **D-08:** `decimatorBurn` in BurnieCoin keeps the burn logic but calls `quests.handleDecimator()` for the quest portion instead of inlining it. BurnieCoin remains the caller for decimator/flip/affiliate handlers since these actions originate from BurnieCoin itself.
- **D-09:** The `handleFlip` call in BurnieCoinflip.sol already calls DegenerusQuests directly (line 279) — no change needed there.
- **D-10:** BurnieCoin `_questApplyReward` currently emits `QuestCompleted` and returns the reward amount. After removal, the quest reward + creditFlip logic moves INTO the DegenerusQuests handlers. Each handler already calls `_questCompleteWithPair` which handles daily quest rewards. The creditFlip call for daily rewards moves from BurnieCoin into DegenerusQuests.
- **D-11:** Access control changes: handlers currently use `onlyCoin` modifier (COIN + COINFLIP). After rewiring, game modules call directly, so handlers need `onlyGame` OR the modifier needs to accept GAME as a caller. The simplest path: add GAME to the `onlyCoin` modifier check (rename to `onlyAuthorized` or keep as-is with GAME added).

### View Function
- **D-12:** `getPlayerLevelQuestView` is already fully implemented in Phase 157. No changes needed — it reads `levelQuestGlobal` and returns (questType, progress, target, completed, eligible).

### Claude's Discretion
- Order of handler modifications (all 6 are independent, can be done in any order)
- Whether to batch the BurnieCoin cleanup into the same plan as handler wiring or separate plans
- Exact wording of NatSpec updates on modified functions
- Whether `onlyCoin` gets renamed or just expanded

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Level Quest Design Spec
- `.planning/phases/153-core-design/153-01-LEVEL-QUEST-SPEC.md` — Eligibility (Section 1), quest roll (Section 2), 10x targets (Section 3), per-player progress (Section 4), storage (Section 5), completion flow (Section 6)

### Integration Map (PRIMARY — per-handler specs in Section 5)
- `.planning/phases/154-integration-mapping/154-01-INTEGRATION-MAP.md` — Handler modification pattern (Section 5), per-handler specifics (5.3-5.8), reward path options (Section 7), roll trigger path (Section 6)

### Phase 157 Gap Closure (IMPORTANT — storage changes)
- `.planning/phases/157-quest-logic-roll-chain/157-03-PLAN.md` — MINT_BURNIE moved to 9, levelQuestType mapping replaced with levelQuestGlobal packed uint256, questGame.level() eliminated from handler path
- `.planning/phases/157-quest-logic-roll-chain/157-VERIFICATION.md` — Re-verification confirming all 5 must-haves pass after gap closure

### Contract References
- `contracts/DegenerusQuests.sol` — All 6 handlers (447-788), `_handleLevelQuestProgress` (1682-1732), levelQuestGlobal (283), onlyCoin modifier (291-294), _questCompleteWithPair (daily quest completion)
- `contracts/BurnieCoin.sol` — notifyQuestMint (633-659), notifyQuestLootBox (665-685), notifyQuestDegenerette (692-720), _questApplyReward (897-913), QuestCompleted event, decimatorBurn
- `contracts/BurnieCoinflip.sol` — handleFlip call (279), onlyFlipCreditors
- `contracts/modules/DegenerusGameAdvanceModule.sol` — Already has quests import + constant (Phase 157)
- `contracts/interfaces/IDegenerusQuests.sol` — Handler signatures, LevelQuestCompleted event
- `contracts/interfaces/DegenerusGameModuleInterfaces.sol` — Module interface definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_handleLevelQuestProgress(player, handlerQuestType, delta, mintPrice)` — Phase 157 shared handler, reads levelQuestGlobal (1 SLOAD), checks type match, checks eligibility, accumulates progress, triggers completion
- `_questCompleteWithPair` — Existing daily quest completion flow that handles rewards/streaks
- `questGame.mintPrice()` — Already called in ETH-related handlers for daily quests (can share the value)

### Established Patterns
- All 6 handlers follow identical structure: load activeQuests, get currentDay, get state, sync, check type, accumulate, complete
- `onlyCoin` modifier gates all handlers — accepts COIN + COINFLIP addresses
- Event + creditFlip pattern for completion (daily uses BurnieCoin hop, level quest does it directly in _handleLevelQuestProgress)

### Integration Points
- MintModule calls `coin.notifyQuestMint()` at 4 call sites (lines ~804, 910, 944, 1049)
- MintModule calls `coin.notifyQuestLootBox()` at 1 site (line 810)
- DegeneretteModule calls `coin.notifyQuestDegenerette()` at 2 sites (lines 446, 448)
- DegenerusAffiliate calls `coin.affiliateQuestReward()` at 1 site (line 607)
- BurnieCoin.decimatorBurn calls `questModule.handleDecimator()` directly
- BurnieCoinflip.flip calls `module.handleFlip()` directly

</code_context>

<specifics>
## Specific Ideas

- The BurnieCoin cleanup (D-06 through D-11) is a significant change touching multiple contracts. Plan should verify all callers are rewired before removing the middleman functions.
- handleMint is the most complex handler (loops both quest slots, branches on paidWithEth). The level quest block should use the same mintPrice already loaded for daily quest ETH branch.
- Grep for all `notifyQuest` call sites across all contracts before removing to ensure none are missed.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 158-handler-integration-view-quest-routing-cleanup*
*Context gathered: 2026-04-01 via auto mode*
