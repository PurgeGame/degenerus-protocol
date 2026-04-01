# Phase 107: Mint + Purchase Flow - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameMintModule.sol and DegenerusGameMintStreakUtils.sol -- the mint, purchase, and ticket queue write module. This phase examines every state-changing function in both contracts using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The module handles:
- ETH ticket purchases (`purchase`, `_purchaseFor`, `_callTicketPurchase`)
- BURNIE token ticket purchases (`purchaseCoin`, `_purchaseCoinFor`)
- Lootbox purchases (ETH and BURNIE: `_purchaseBurnieLootboxFor`, lootbox pool splits)
- Ticket queue WRITE path (`_queueTicketsScaled` via `_callTicketPurchase`)
- Future ticket batch processing / READ drain (`processFutureTicketBatch`, `_raritySymbolBatch`)
- Mint data recording and activity score tracking (`recordMintData`)
- Mint streak tracking (`_recordMintStreakForLevel`, `_mintStreakEffective`)
- Lootbox boost application (`_applyLootboxBoostOnPurchase`)
- Affiliate payment integration (calls to `affiliate.payAffiliate`)
- Earlybird DGNRS rewards (calls to `_awardEarlybirdDgnrs`)
- Century bonus ticket calculation

This phase does NOT re-audit module internals of other modules called via subordinate paths (those are in Phases 105-117). Cross-module calls are traced far enough to verify state coherence in the calling context.

**TICKET LIFECYCLE COORDINATION:** `processFutureTicketBatch` lives in this module. Phase 104 audited the READ/drain side and declared the ticket queue drain PROVEN SAFE (test setup issue, not contract bug -- see F-06 in Phase 104 ATTACK-REPORT). This phase audits the WRITE side of the ticket lifecycle: how tickets enter the queue through purchases. Mad Genius must trace the full ticket lifecycle from queue write through batch processing to ensure no tickets can be silently stranded.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. This is a module, not the router. Category A (delegatecall dispatchers) does not apply. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### Ticket Queue Write Path
- **D-04:** The ticket queue WRITE path analysis is a focus item. Mad Genius must trace how `_callTicketPurchase` routes tickets to `_queueTicketsScaled`, verifying correct level targeting (especially the jackpotPhaseFlag/rngLockedFlag routing at lines 842-851) and ensuring no tickets can be silently lost.
- **D-05:** `processFutureTicketBatch` is the READ/drain side. Phase 104 declared this PROVEN SAFE. This phase re-verifies independently but focuses primarily on the write paths and the batch processing correctness (trait generation, remainder rolling, budget management).

### Fresh Analysis
- **D-06:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v3.7/v3.8. The entire point of v5.0 is catching bugs that survived 24 prior milestones. Prior audit results are not input to this phase.

### Cross-Module Call Boundary
- **D-08:** When purchase functions chain into code from other modules/contracts (affiliate, BurnieCoin, sDGNRS), trace the subordinate calls far enough to verify the parent's state coherence -- specifically the cached-local-vs-storage check. Full internals of those contracts are audited in their own unit phases.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in. The BAF pattern is what we're hunting.

### Report Format
- **D-10:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering as in Phase 103)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into multiple files if it exceeds reasonable length

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/modules/DegenerusGameMintModule.sol` -- Primary audit target (~1,167 lines, 16 functions)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` -- Secondary audit target (62 lines, 2 functions)

### Storage Layout (verified in Phase 103)
- `contracts/storage/DegenerusGameStorage.sol` -- Shared storage layout inherited by all modules. Contains `_queueTicketsScaled`, `_awardEarlybirdDgnrs`, prize pool helpers, ticket queue key encoding, and other helper functions called by MintModule.

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` -- Module function signatures
- `contracts/interfaces/IDegenerusGame.sol` -- MintPaymentKind enum, playerActivityScore, consumePurchaseBoost, recordMint

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (Category A/B/C/D pattern, report format)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Phase 103 Taskmaster output (format reference)
- `audit/unit-02/ATTACK-REPORT.md` -- Phase 104 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

### Ticket Queue Drain (coordination with Phase 104)
- `audit/unit-02/ATTACK-REPORT.md` -- Phase 104 F-06: Ticket queue drain PROVEN SAFE verdict. This phase audits the write side independently.

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from source)

**DegenerusGameMintModule.sol:**
- `recordMintData()` (L175-284) -- External, records mint metadata and activity score, bit-packed storage
- `processFutureTicketBatch()` (L295-434) -- External, drains future-pool ticket queue, trait generation
- `purchase()` (L560-574) -- External, ETH ticket + lootbox purchase entry point
- `purchaseCoin()` (L581-591) -- External, BURNIE ticket + lootbox purchase entry point
- `purchaseBurnieLootbox()` (L595-598) -- External, BURNIE-only lootbox purchase
- `_purchaseFor()` (L628-829) -- Private, core ETH purchase logic (lootbox + ticket routing)
- `_purchaseCoinFor()` (L600-626) -- Private, core BURNIE purchase logic
- `_callTicketPurchase()` (L831-1024) -- Private, ticket purchase + affiliate + queue write
- `_raritySymbolBatch()` (L443-537) -- Private, inline Yul assembly for trait generation
- `_rollRemainder()` (L540-547) -- Private pure, fractional ticket probability roll
- `_coinReceive()` (L1026-1031) -- Private, burns BURNIE via coin.burnCoin
- `_ethToBurnieValue()` (L1034-1037) -- Private pure, ETH-to-BURNIE conversion
- `_purchaseBurnieLootboxFor()` (L1039-1071) -- Private, BURNIE lootbox core logic
- `_maybeRequestLootboxRng()` (L1073-1075) -- Private, accumulates lootbox RNG pending ETH
- `_calculateBoost()` (L1078-1083) -- Private pure, boost amount calculation
- `_applyLootboxBoostOnPurchase()` (L1085-1112) -- Private, applies and consumes lootbox boost boon

**DegenerusGameMintStreakUtils.sol:**
- `_recordMintStreakForLevel()` (L17-46) -- Internal, records consecutive-level mint streak
- `_mintStreakEffective()` (L49-61) -- Internal view, returns effective streak (resets if level missed)

### Key Storage Variables Written by MintModule
- `mintPacked_[player]` -- Bit-packed mint data (level count, streak, whale bundle, units)
- `ticketQueue[key]` -- Address queue for ticket processing
- `ticketsOwedPacked[key][player]` -- Packed ticket owed count + remainder
- `claimableWinnings[buyer]` / `claimablePool` -- During claimable payment path
- `lootboxEth[index][buyer]` -- Lootbox ETH amount per player per index
- `lootboxDay[index][buyer]` -- Lootbox purchase day
- `lootboxBaseLevelPacked` / `lootboxEvScorePacked` -- Lootbox metadata
- `lootboxEthBase` / `lootboxDistressEth` -- Lootbox accounting
- `lootboxBurnie[index][buyer]` -- BURNIE lootbox amount
- `lootboxRngPendingEth` / `lootboxRngPendingBurnie` -- RNG trigger accumulators
- `lootboxPresaleMintEth` -- Presale cap tracking
- `prizePoolsPacked` / `prizePoolPendingPacked` -- Prize pool updates (via lootbox splits)
- `centuryBonusLevel` / `centuryBonusUsed[buyer]` -- Century bonus tracking
- `traitBurnTicket[level][trait]` -- Trait ticket arrays (via assembly in _raritySymbolBatch)
- `ticketCursor` / `ticketLevel` -- Batch processing state
- `boonPacked[player].slot0` -- Lootbox boost consumption
- `earlybirdDgnrsPoolStart` / `earlybirdEthIn` -- Earlybird DGNRS tracking

### Established Pattern (from Phase 103-105)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-05/` directory

### Integration Points
- `purchase()` / `purchaseCoin()` are called via delegatecall from DegenerusGame
- `_callTicketPurchase()` calls back into DegenerusGame via `IDegenerusGame(address(this)).recordMint{value}()`
- `_callTicketPurchase()` calls `IDegenerusGame(address(this)).consumePurchaseBoost()`
- `_callTicketPurchase()` calls `IDegenerusGame(address(this)).playerActivityScore()`
- `_purchaseFor()` calls `_awardEarlybirdDgnrs()` (defined in GameStorage, touches sDGNRS)
- Affiliate payments via `affiliate.payAffiliate()` (external call to DegenerusAffiliate)
- BURNIE operations via `coin.creditFlip()`, `coin.burnCoin()`, `coin.notifyQuestMint()`, `coin.notifyQuestLootBox()`
- Lootbox pool splits write to `prizePoolsPacked` / `prizePoolPendingPacked` (shared with JackpotModule)
- `processFutureTicketBatch` is called from AdvanceModule via delegatecall to JackpotModule which delegates to this module
- Vault ETH transfer during presale lootbox split

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system (Taskmaster checklist -> Mad Genius attack -> Skeptic review) drives the workflow, same as Phase 103-105.

The TICKET LIFECYCLE WRITE PATH is the main differentiator from standard unit audit flow. The write side (this phase) complements Phase 104's read/drain investigation.

Key areas requiring extra scrutiny:
1. **Inline Yul assembly** in `_raritySymbolBatch` -- storage slot calculation, array length accounting
2. **Cached-local-vs-storage** in `_purchaseFor` (caches `price`, `level`, `claimableWinnings[buyer]`)
3. **Century bonus** level targeting and per-player cap tracking
4. **Lootbox boost** consumption and expiry logic
5. **Ticket level routing** in `_callTicketPurchase` (jackpotPhaseFlag + rngLockedFlag edge cases)

</specifics>

<deferred>
## Deferred Ideas

- **Phase 118**: Full cross-module state coherence verification is deferred to the integration sweep.
- **Phase 111**: Lootbox resolution internals (this phase only covers lootbox purchase/accumulation, not resolution).
- **Phase 116**: Affiliate internal logic (this phase traces affiliate calls for state coherence only).

</deferred>

---

*Phase: 107-mint-purchase-flow*
*Context gathered: 2026-03-25*
