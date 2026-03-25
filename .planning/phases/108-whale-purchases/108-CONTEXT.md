# Phase 108: Whale Purchases - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameWhaleModule.sol -- the whale bundle, lazy pass, and deity pass purchase module. This phase examines every state-changing function in the module using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The module handles:
- Whale bundle purchases (100-level coverage bundles with tiered pricing and boon discounts)
- Lazy pass purchases (10-level passes with level-gated availability and boon discounts)
- Deity pass purchases (symbol-specific passes with triangular pricing and ERC721 minting)
- DGNRS reward distribution to buyers and affiliate chains (whale pool + affiliate pool)
- Lootbox entry recording with boost boon application
- Prize pool fund distribution (future/next split with pre-game vs post-game ratios)
- Ticket queuing across 100-level ranges (whale/deity) and 10-level ranges (lazy)

This phase does NOT re-audit module internals of other modules or inherited storage helpers called via subordinate paths (those are in their own unit phases). Cross-module calls are traced far enough to verify state coherence in the calling context.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. This is a module, not the router. Category A (delegatecall dispatchers) does not apply. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### Fresh Analysis Mandate
- **D-06:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v3.7/v3.8 or any prior audit. The entire point of v5.0 is catching bugs that survived 24 prior milestones. Prior audit results are not input to this phase.

### Cross-Module Call Boundary
- **D-08:** When whale/lazy/deity purchase functions chain into inherited helpers (_queueTickets, _activate10LevelPass, _awardEarlybirdDgnrs, _setPrizePools, _setPendingPools) or external contracts (sDGNRS, affiliate, DeityPass NFT), trace the subordinate calls far enough to verify the parent's state coherence -- specifically the cached-local-vs-storage check. Full internals of those contracts are audited in their own unit phases.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in. The BAF pattern is what we're hunting.

### Report Format
- **D-10:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

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

### Target Contract
- `contracts/modules/DegenerusGameWhaleModule.sol` -- The audit target (817 lines, 3 external entry points, multiple private helpers)

### Inherited Contracts
- `contracts/modules/DegenerusGameMintStreakUtils.sol` -- Parent class (62 lines, mint streak tracking)
- `contracts/storage/DegenerusGameStorage.sol` -- Shared storage layout and helpers (_queueTickets, _activate10LevelPass, _awardEarlybirdDgnrs, _setPrizePools, etc.)

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` -- Module function signatures

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (Category B/C/D pattern, report format)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Phase 103 Taskmaster output (format reference)
- `audit/unit-02/ATTACK-REPORT.md` -- Phase 104 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from source)
- `purchaseWhaleBundle(address buyer, uint256 quantity)` (L183) -- External entry point, 100-level whale bundle purchase
- `_purchaseWhaleBundle(address, uint256)` (L187) -- Private implementation, 124 lines of logic
- `purchaseLazyPass(address buyer)` (L325) -- External entry point, 10-level lazy pass purchase
- `_purchaseLazyPass(address)` (L329) -- Private implementation, 122 lines of logic
- `purchaseDeityPass(address buyer, uint8 symbolId)` (L470) -- External entry point, deity pass with ERC721 mint
- `_purchaseDeityPass(address, uint8)` (L474) -- Private implementation, 92 lines of logic
- `_lazyPassCost(uint24)` (L573) -- Pure helper, computes 10-level sum of ticket prices
- `_rewardWhaleBundleDgnrs(address, address, address, address)` (L587) -- DGNRS distribution for whale bundle
- `_rewardDeityPassDgnrs(address, address, address, address)` (L652) -- DGNRS distribution for deity pass
- `_recordLootboxEntry(address, uint256, uint24, uint256)` (L714) -- Lootbox entry recording
- `_maybeRequestLootboxRng(uint256)` (L762) -- Lootbox RNG pending accumulator
- `_applyLootboxBoostOnPurchase(address, uint48, uint256)` (L773) -- Lootbox boost boon application
- `_recordLootboxMintDay(address, uint32, uint256)` (L808) -- Lootbox mint day tracking

### Inherited Helpers (from DegenerusGameStorage)
- `_queueTickets(address, uint24, uint32)` (Storage L528) -- Far-future ticket queuing with RNG lock check
- `_activate10LevelPass(address, uint24, uint32)` (Storage L982) -- 10-level pass stat updates + ticket range queuing
- `_awardEarlybirdDgnrs(address, uint256, uint24)` (Storage L914) -- Earlybird DGNRS distribution
- `_setPrizePools(uint128, uint128)` (Storage L651) -- Prize pool writes
- `_getPrizePools()` (Storage L655) -- Prize pool reads
- `_setPendingPools(uint128, uint128)` (Storage L661) -- Pending pool writes
- `_getPendingPools()` (Storage L665) -- Pending pool reads
- `_simulatedDayIndex()` (Storage L1134) -- Current day index
- `_currentMintDay()` (Storage L1144) -- Current mint day
- `_setMintDay(uint256, uint32, uint256, uint256)` (Storage L1153) -- Mint day setter
- `_whaleTierToBps(uint8)` (Storage L1551) -- Whale boon tier to discount BPS
- `_lazyPassTierToBps(uint8)` (Storage L1559) -- Lazy pass boon tier to discount BPS
- `_lootboxTierToBps(uint8)` (Storage L1527) -- Lootbox boost tier to BPS
- `_isDistressMode()` (Storage L171) -- Distress mode check

### Established Pattern (from Phase 103-105)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-06/` directory

### Integration Points
- All three purchase functions use `_queueTickets` which writes to ticketQueue and ticketsOwedPacked storage
- All three use `_setPrizePools` or `_setPendingPools` depending on `prizePoolFrozen` state
- All three call `_awardEarlybirdDgnrs` which makes external calls to sDGNRS contract
- Whale and deity purchases call `_rewardWhaleBundleDgnrs` / `_rewardDeityPassDgnrs` which make external calls to sDGNRS for whale pool and affiliate pool transfers
- Deity pass mints an ERC721 via IDegenerusDeityPassMint external call
- All three record lootbox entries via `_recordLootboxEntry` -> `_applyLootboxBoostOnPurchase` -> `_maybeRequestLootboxRng`
- Lazy pass calls `_activate10LevelPass` in Storage which does its own mintPacked_ write (POTENTIAL CACHE CONCERN -- lazy pass reads mintPacked_ before calling this)
- Boon consumption reads/writes boonPacked[buyer].slot0 and .slot1

</code_context>

<specifics>
## Specific Ideas

No priority investigations beyond the standard methodology. The three-agent system (Taskmaster checklist -> Mad Genius attack -> Skeptic review) drives the workflow, same as Phases 103-105.

Key areas of concern for this module:
1. **Cached-local-vs-storage in lazy pass:** `_purchaseLazyPass` reads `mintPacked_[buyer]` indirectly (via frozenUntilLevel unpack) then calls `_activate10LevelPass` which ALSO reads and writes `mintPacked_[buyer]`. The Mad Genius must verify no stale writeback occurs.
2. **Boon consumption atomicity:** Each purchase function reads boonPacked slots, conditionally clears them, then proceeds with pricing. Verify no reentrancy window or double-consumption path exists.
3. **Deity pass triangular pricing:** Price = 24 + T(k) where k = deityPassOwners.length. Verify no manipulation of k between price calculation and payment validation.
4. **DGNRS reward pool drain:** Both reward functions read poolBalance and compute shares. Verify the reserved-allocation subtraction prevents affiliate pool drain.
5. **Lootbox entry recording:** `_recordLootboxEntry` uses `cachedPacked` parameter from the caller but also reads `mintPacked_[buyer]` via `_recordLootboxMintDay`. Verify the cached value and fresh read don't conflict.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 107 coordination**: Lazy pass calls `_activate10LevelPass` which calls `_queueTicketRange`. Phase 107 (Mint + Purchase Flow) audits the ticket queuing internals. Cross-reference findings at Phase 118.
- **Phase 111 coordination**: Lootbox entry recording (`_recordLootboxEntry`) creates entries that Phase 111 (Lootbox + Boons) resolves. Verify lootbox lifecycle coherence at Phase 118.
- **Phase 118**: Full cross-module state coherence verification is deferred to the integration sweep.

</deferred>

---

*Phase: 108-whale-purchases*
*Context gathered: 2026-03-25*
