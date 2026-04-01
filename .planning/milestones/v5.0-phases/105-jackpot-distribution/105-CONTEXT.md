# Phase 105: Jackpot Distribution - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameJackpotModule.sol and DegenerusGamePayoutUtils.sol — the jackpot distribution and payout infrastructure. This phase examines every state-changing function using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The module handles:
- Terminal jackpot execution (runTerminalJackpot — end-of-level ETH distribution)
- Daily ETH jackpot payments (payDailyJackpot, _processDailyEth, _distributeJackpotEth)
- Daily coin jackpot (payDailyCoinJackpot, _awardDailyCoinToTraitWinners, _awardFarFutureCoinJackpot)
- Daily ticket jackpot (payDailyJackpotCoinAndTickets, _distributeTicketJackpot, _distributeTicketsToBuckets)
- Prize pool consolidation (consolidatePrizePools, _distributeYieldSurplus)
- Auto-rebuy processing (_processAutoRebuy — THE ORIGINAL BAF BUG LOCATION)
- Claimable ETH crediting (_addClaimableEth — BAF PATTERN CRITICAL PATH)
- Ticket batch processing (processTicketBatch, _processOneTicketEntry, _generateTicketBatch)
- Lootbox/earlybird jackpots (_runEarlyBirdLootboxJackpot)
- Trait-based winner selection (_resolveTraitWinners, _getWinningTraits, _randTraitTicket)
- Payout utility functions (_creditClaimable, _calcAutoRebuy, _queueWhalePassClaimCore)

This phase does NOT re-audit the caller-side of advanceGame() -> JackpotModule (audited in Phase 104). Cross-module calls from JackpotModule into other modules are traced for state coherence only.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only — no Category A. Both contracts are modules, not routers. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. Standalone analysis only for MULTI-PARENT helpers (called from multiple parents with different cached-local states).

### Two-Contract Scope
- **D-04:** DegenerusGameJackpotModule.sol (2,715 lines) and DegenerusGamePayoutUtils.sol (92 lines) are audited as a single unit. PayoutUtils is an internal helper contract inherited by JackpotModule — its 3 functions (_creditClaimable, _calcAutoRebuy, _queueWhalePassClaimCore) get Category C treatment within JackpotModule's call trees.
- **D-05:** The Taskmaster checklist covers both contracts in a single document. Function counts from both contracts are summed for the unit total.

### BAF Pattern Priority
- **D-06:** _addClaimableEth and _processAutoRebuy are where the original BAF cache-overwrite bug lived. These functions AND every function that calls them get Tier 1 priority in the Mad Genius attack queue. The cached-local-vs-storage check is the #1 priority for these paths.
- **D-07:** The v4.4 BAF fix (rebuyDelta reconciliation in EndgameModule) is NOT trusted. The Mad Genius re-audits the entire _addClaimableEth -> _processAutoRebuy -> futurePrizePool chain from scratch as if the fix doesn't exist. Fresh adversarial analysis per D-06 from Phase 104.

### Cross-Module Call Boundary
- **D-08:** When JackpotModule functions call into other modules or external contracts, trace subordinate calls far enough to verify the parent's state coherence (cached-local-vs-storage check). Full internals of other modules are in their own unit phases.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in.

### VRF/RNG Audit Approach
- **D-10:** Fresh adversarial analysis on all functions — do not trust prior Phase 104 findings on RNG words passed to JackpotModule. The RNG words arrive as parameters; the jackpot module's use of those words (for winner selection, trait rolls, etc.) is this phase's responsibility.

### Report Format
- **D-11:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Function analysis ordering within risk tiers
- Level of detail in cross-module subordinate call traces
- Whether to split the attack report if it exceeds reasonable length (2,715-line contract may produce a very large report)
- Handling of the ~55 Category C private helpers — grouping by subsystem (ETH flow, coin flow, ticket flow) may improve readability

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` — Three-agent system design, attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/modules/DegenerusGameJackpotModule.sol` — Primary audit target (2,715 lines, ~55 functions)
- `contracts/modules/DegenerusGamePayoutUtils.sol` — Secondary audit target (92 lines, 3 functions)

### Storage Layout (verified in Phase 103)
- `contracts/storage/DegenerusGameStorage.sol` — Shared storage layout

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` — Module function signatures

### Prior Phase Outputs (methodology reference — do NOT trust findings)
- `.planning/phases/104-day-advancement-vrf/104-CONTEXT.md` — Phase 104 decisions (function categorization pattern, cross-module boundary rules)
- `audit/unit-01/COVERAGE-CHECKLIST.md` — Phase 103 Taskmaster output (format reference)
- `audit/unit-02/ATTACK-REPORT.md` — Phase 104 Mad Genius output (format reference)

### Prior Audit Context (known issues — do not re-report)
- `audit/KNOWN-ISSUES.md` — Known issues from v1.0-v4.4

### BAF Bug Context
- Phase 100-102 audit found the BAF cache-overwrite in _addClaimableEth -> _processAutoRebuy -> futurePrizePool path. The fix is in EndgameModule. This phase re-verifies the JackpotModule side independently.

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from grep, ~58 total across both contracts)
**Category B candidates (external/public state-changing):**
- `runTerminalJackpot()` (L272) — Terminal jackpot at level end
- `payDailyJackpot()` (L313) — Daily ETH jackpot (called from advanceGame)
- `payDailyJackpotCoinAndTickets()` (L652) — Daily coin+ticket jackpot
- `awardFinalDayDgnrsReward()` (L744) — Final day DGNRS reward
- `consolidatePrizePools()` (L850) — Prize pool rebalancing
- `processTicketBatch()` (L1812) — Ticket processing batch
- `payDailyCoinJackpot()` (L2283) — Daily coin jackpot

**BAF-critical paths (Category C but Tier 1 priority):**
- `_addClaimableEth()` (L928) — Credits claimable ETH to winners
- `_processAutoRebuy()` (L959) — Auto-rebuy logic (ORIGINAL BAF BUG)
- `_creditClaimable()` (PayoutUtils L30) — Low-level claimable crediting

**High-complexity subsystems:**
- Ticket distribution: _distributeTicketJackpot -> _distributeTicketsToBuckets -> _distributeTicketsToBucket -> _processOneBucket -> _resolveTraitWinners (deep call chain)
- ETH flow: _executeJackpot -> _runJackpotEthFlow -> _processDailyEth -> _distributeJackpotEth (budget/distribution pipeline)
- Coin jackpot: payDailyCoinJackpot -> _awardDailyCoinToTraitWinners -> _awardFarFutureCoinJackpot (trait-based selection)

### Established Pattern (from Phases 103-104)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers
- Taskmaster must achieve 100% coverage before Skeptic review
- Output goes to `audit/unit-03/` directory

### Integration Points
- Called by advanceGame() via delegatecall (Phase 104 verified the caller side)
- _addClaimableEth writes to claimable mapping (consumed by claimWinnings in DegenerusGame.sol, audited in Phase 103)
- _processAutoRebuy interacts with ticket/purchase state (MintModule scope)
- consolidatePrizePools manages prize pool balances (read by many modules)
- JackpotBucketLib.sol is used for bucket-based ticket distribution

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system drives the workflow. The BAF-critical paths (_addClaimableEth, _processAutoRebuy) deserve extra attention given they are the exact location where the original BAF cache-overwrite bug was found.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 106 coordination**: _addClaimableEth is also called from EndgameModule/GameOverModule. Phase 106 should verify the EndgameModule-side BAF fix independently.
- **Phase 117 coordination**: JackpotBucketLib.sol is used by JackpotModule for bucket distribution. Full library audit in Phase 117.
- **Phase 118**: Full cross-module state coherence verification deferred to integration sweep.

</deferred>

---

*Phase: 105-jackpot-distribution*
*Context gathered: 2026-03-25*
