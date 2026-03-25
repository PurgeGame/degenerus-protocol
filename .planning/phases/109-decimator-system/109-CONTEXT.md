# Phase 109: Decimator System - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameDecimatorModule.sol -- the decimator jackpot tracking, resolution, claim, and terminal death-bet module. This phase examines every state-changing function in the module using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The module handles:
- Decimator burn recording with bucket/subbucket assignment and multiplier caps (recordDecBurn)
- Decimator jackpot resolution via VRF-selected winning subbuckets (runDecimatorJackpot)
- Decimator claim flow with 50/50 ETH/lootbox split and auto-rebuy integration (claimDecimatorJackpot)
- Game-initiated claim consumption (consumeDecClaim)
- Terminal decimator (death-bet) burn tracking with time multiplier and activity-score bucket (recordTerminalDecBurn)
- Terminal decimator GAMEOVER resolution (runTerminalDecimatorJackpot)
- Terminal decimator claims post-GAMEOVER (claimTerminalDecimatorJackpot)
- Auto-rebuy path converting ETH winnings to tickets with bonus BPS (_processAutoRebuy -> _addClaimableEth)

This phase does NOT re-audit module internals of other modules called via subordinate paths (those are in their own unit phases). Cross-module calls are traced far enough to verify state coherence in the calling context.

**PRIORITY INVESTIGATION:** Auto-rebuy paths in this module have the SAME BAF pattern risk as the Endgame bug. The claimDecimatorJackpot -> _creditDecJackpotClaimCore -> _addClaimableEth -> _processAutoRebuy chain writes to futurePrizePool and nextPrizePool. Must verify no ancestor caches these values before the subordinate writes.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. This is a module, not the router. Category A (delegatecall dispatchers) does not apply. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### Auto-Rebuy BAF Pattern (PRIORITY)
- **D-04:** The auto-rebuy chain (_processAutoRebuy -> _calcAutoRebuy -> _setFuturePrizePool/_setNextPrizePool -> _queueTickets) is the PRIMARY hunt target. This is the exact same pattern as the original BAF cache-overwrite bug. Every call chain reaching _addClaimableEth must be traced for stale-cache writes.
- **D-05:** claimDecimatorJackpot has a critical read-then-write pattern: it reads _getFuturePrizePool(), then calls _creditDecJackpotClaimCore which chains into _addClaimableEth -> _processAutoRebuy which writes _setFuturePrizePool(). The Mad Genius must verify whether the outer futurePrizePool read is cached in a local before the inner write occurs.

### Fresh Analysis Mandate
- **D-06:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from any prior audit phase. The entire point of v5.0 is catching bugs that survived 24 prior milestones. Prior audit results are not input to this phase.
- **D-07:** Auto-rebuy paths get the same full treatment as every other function. No reduced scrutiny for "already fixed in v4.4."

### Cross-Module Call Boundary
- **D-08:** When decimator functions chain into inherited helpers (_creditClaimable, _calcAutoRebuy, _queueTickets, _queueWhalePassClaimCore, _setFuturePrizePool, _setNextPrizePool) or delegatecall to LootboxModule (resolveLootboxDirect), trace the subordinate calls far enough to verify the parent's state coherence. Full internals of those modules are audited in their own unit phases.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in. The BAF pattern is what we're hunting.

### Terminal Decimator Special Concerns
- **D-10:** Terminal decimator uses a different storage schema (TerminalDecEntry with uint80 totalBurn + uint88 weightedBurn vs DecEntry with uint192 burn). Verify saturation arithmetic is correct at each boundary.
- **D-11:** Terminal decimator resolution reuses decBucketOffsetPacked[lvl] (same slot as regular decimator). Verify these cannot collide at the same level.

### Report Format
- **D-12:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering as in prior phases)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into multiple files if it exceeds reasonable length

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contract
- `contracts/modules/DegenerusGameDecimatorModule.sol` -- The audit target (930 lines, 28 functions)

### Inherited Contracts
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- Shared payout helpers (92 lines): _creditClaimable, _calcAutoRebuy, _queueWhalePassClaimCore
- `contracts/storage/DegenerusGameStorage.sol` -- Shared storage layout inherited by all modules

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` -- Module function signatures

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/108-whale-purchases/108-CONTEXT.md` -- Phase 108 context (format reference)
- `audit/unit-06/COVERAGE-CHECKLIST.md` -- Phase 108 Taskmaster output (format reference)
- `audit/unit-06/ATTACK-REPORT.md` -- Phase 108 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from source, line numbers verified)
- `recordDecBurn()` (L129) -- External, called by COIN on Decimator burn, assigns bucket/subbucket, accumulates burn
- `runDecimatorJackpot()` (L205) -- External, called by GAME, selects winning subbuckets via VRF, snapshots claim round
- `consumeDecClaim()` (L301) -- External, called by GAME, game-initiated claim consumption
- `claimDecimatorJackpot()` (L316) -- External, player-callable, 50/50 ETH/lootbox split, auto-rebuy path [BAF-CRITICAL]
- `recordTerminalDecBurn()` (L707) -- External, called by COIN, terminal death-bet burn with time multiplier
- `runTerminalDecimatorJackpot()` (L783) -- External, called by GAME, GAMEOVER resolution
- `claimTerminalDecimatorJackpot()` (L833) -- External, player-callable, GAMEOVER claim, calls _addClaimableEth [BAF-CRITICAL]
- `decClaimable()` (L346) -- External view, UI helper
- `terminalDecClaimable()` (L846) -- External view, UI helper

### Inheritance Chain
DegenerusGameDecimatorModule -> DegenerusGamePayoutUtils -> DegenerusGameStorage

### Contract Size
930 lines total, 28 functions (7 external state-changing, 13 internal/private state-changing, 8 view/pure)

### Integration Points
- claimDecimatorJackpot -> _creditDecJackpotClaimCore -> _addClaimableEth -> _processAutoRebuy (BAF-CRITICAL chain)
- claimDecimatorJackpot -> _awardDecimatorLootbox -> delegatecall LootboxModule.resolveLootboxDirect
- _processAutoRebuy -> _setFuturePrizePool / _setNextPrizePool / _queueTickets (storage writes in descendant)
- recordTerminalDecBurn -> IDegenerusGame(address(this)).playerActivityScore (self-call via interface)

</code_context>

<specifics>
## Specific Ideas

The auto-rebuy chain in claimDecimatorJackpot is the #1 priority. The pattern is:
1. claimDecimatorJackpot reads _getFuturePrizePool() at L336
2. _creditDecJackpotClaimCore calls _addClaimableEth which may trigger _processAutoRebuy
3. _processAutoRebuy calls _setFuturePrizePool() at L387
4. Back in claimDecimatorJackpot at L336, the lootboxPortion is added to a value that was read BEFORE the _processAutoRebuy write

This is the exact BAF pattern. Mad Genius must determine: is the L336 read actually cached, or is it re-read from storage after the subordinate call returns?

Terminal decimator has separate storage (terminalDecEntries vs decBurn, terminalDecBucketBurnTotal vs decBucketBurnTotal) but shares decBucketOffsetPacked[lvl]. Collision analysis needed.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 112 coordination**: Auto-rebuy is triggered from BurnieCoin paths too. Phase 112 (BURNIE Token + Coinflip) should coordinate with this phase's auto-rebuy findings.
- **Phase 118**: Full cross-module state coherence verification is deferred to the integration sweep. The delegatecall to LootboxModule.resolveLootboxDirect is traced for state coherence here but full lootbox resolution audit is in Phase 111.

</deferred>

---

*Phase: 109-decimator-system*
*Context gathered: 2026-03-25*
