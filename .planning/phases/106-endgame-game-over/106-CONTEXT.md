# Phase 106: Endgame + Game Over - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameEndgameModule.sol and DegenerusGameGameOverModule.sol -- the endgame reward jackpots and game-over drain modules. This phase examines every state-changing function in both modules using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The modules handle:
- BAF (Big-Ass Flip) jackpot execution during level transitions (every 10 levels)
- Decimator jackpot execution during level transitions (levels ending in 5, plus level 100 special)
- Auto-rebuy ticket conversion on jackpot winnings (THE BAF BUG FIX LIVES HERE)
- Lootbox ticket awards from jackpot wins (tiered: small/medium/large)
- Whale pass claim system (deferred large lootbox rewards)
- Top affiliate DGNRS reward distribution at level transitions
- Game-over drain: deity pass refunds, terminal decimator, terminal jackpot
- Final sweep: 30-day post-gameover vault/DGNRS fund transfer
- Affiliate DGNRS per-level allocation segregation

**CRITICAL PRIORITY:** This is where the BAF cache-overwrite bug's FIX lives. The `runRewardJackpots()` function in EndgameModule uses a `rebuyDelta` reconciliation mechanism (lines 244-246) to prevent `futurePoolLocal` from overwriting auto-rebuy contributions that `_addClaimableEth` -> `_processAutoRebuy` wrote directly to `futurePrizePool` storage. The Mad Genius must prove this fix is correct AND that no other BAF-class patterns exist in these modules.

This phase does NOT re-audit module internals of JackpotModule, DecimatorModule, or MintModule called via `IDegenerusGame(address(this))` delegatecall chains (those are in their own unit phases). Cross-module calls are traced far enough to verify state coherence in the calling context.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. These are modules, not the router. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### BAF Fix Verification (CRITICAL)
- **D-04:** The `rebuyDelta` reconciliation in `runRewardJackpots()` (EndgameModule lines 244-246) is the HIGHEST PRIORITY analysis target. The Mad Genius must independently prove this mechanism is correct: `rebuyDelta = _getFuturePrizePool() - baseFuturePool` captures exactly the auto-rebuy writes, and `_setFuturePrizePool(futurePoolLocal + rebuyDelta)` correctly reconciles.
- **D-05:** Every call chain from `runRewardJackpots` through `_runBafJackpot` -> `_addClaimableEth` -> auto-rebuy must be traced with full storage-write mapping to verify no other stale-cache pattern exists.

### Fresh Analysis
- **D-06:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. The entire point of v5.0 is catching bugs that survived 24 prior milestones. Prior audit results are not input to this phase.

### Cross-Module Call Boundary
- **D-08:** When `runRewardJackpots()` chains into JackpotModule (via `runDecimatorJackpot`) or when `handleGameOverDrain()` chains into JackpotModule (via `runTerminalJackpot`, `runTerminalDecimatorJackpot`), trace the subordinate calls far enough to verify the parent's state coherence. Full internals of those modules are audited in their own unit phases.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in. The BAF pattern is what we are hunting.

### Report Format
- **D-10:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report if it exceeds reasonable length

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/modules/DegenerusGameEndgameModule.sol` -- Endgame module (565 lines, ~10 functions)
- `contracts/modules/DegenerusGameGameOverModule.sol` -- Game over module (235 lines, ~4 functions)
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- Shared payout helpers inherited by EndgameModule (92 lines, 3 functions)

### Storage Layout (verified in Phase 103)
- `contracts/storage/DegenerusGameStorage.sol` -- Shared storage layout inherited by all modules

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` -- Module function signatures

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/105-jackpot-distribution/105-CONTEXT.md` -- Phase 105 context (Category B/C/D pattern)
- `audit/unit-03/COVERAGE-CHECKLIST.md` -- Phase 105 Taskmaster output (format reference)
- `audit/unit-03/ATTACK-REPORT.md` -- Phase 105 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### EndgameModule Key Functions (from source read)
- `rewardTopAffiliate(uint24 lvl)` (L130) -- External, affiliate DGNRS distribution + level allocation segregation
- `runRewardJackpots(uint24 lvl, uint256 rngWord)` (L172) -- External, BAF/Decimator jackpot execution (BAF FIX HERE)
- `_addClaimableEth(address, uint256, uint256)` (L267) -- Private, auto-rebuy branch writes futurePrizePool [BAF-CRITICAL]
- `_runBafJackpot(uint256, uint24, uint256)` (L356) -- Private, BAF winner distribution loop
- `_awardJackpotTickets(address, uint256, uint24, uint256)` (L448) -- Private, tiered ticket award
- `_jackpotTicketRoll(address, uint256, uint24, uint256)` (L498) -- Private, single roll resolution
- `claimWhalePass(address player)` (L540) -- External, deferred large lootbox claim

### GameOverModule Key Functions (from source read)
- `handleGameOverDrain(uint48 day)` (L68) -- External, game-over fund distribution
- `handleFinalSweep()` (L170) -- External, 30-day post-gameover vault sweep
- `_sendToVault(uint256, uint256)` (L197) -- Private, ETH/stETH split transfer

### Inheritance Chain
- EndgameModule -> DegenerusGamePayoutUtils -> DegenerusGameStorage
- GameOverModule -> DegenerusGameStorage

### PayoutUtils Inherited Functions (from source read)
- `_creditClaimable(address, uint256)` (L30) -- Internal, claimableWinnings write
- `_calcAutoRebuy(...)` (L38) -- Internal pure, auto-rebuy calculation
- `_queueWhalePassClaimCore(address, uint256)` (L75) -- Internal, whale pass claims + remainder to claimable

### Established Pattern (from Phases 103-105)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-04/` directory

### Cross-Module Integration Points
- `runRewardJackpots()` calls `IDegenerusGame(address(this)).runDecimatorJackpot()` (delegatecall through router to DecimatorModule)
- `handleGameOverDrain()` calls `IDegenerusGame(address(this)).runTerminalDecimatorJackpot()` and `runTerminalJackpot()` (delegatecall through router to JackpotModule/DecimatorModule)
- `_addClaimableEth()` calls `_queueTickets()` (inherited from Storage) for auto-rebuy ticket queuing
- `_runBafJackpot()` calls `jackpots.runBafJackpot()` (external call to DegenerusJackpots contract)
- `rewardTopAffiliate()` calls `affiliate.affiliateTop()` and `dgnrs.transferFromPool()` (external calls)
- `handleFinalSweep()` calls `admin.shutdownVrf()` (external call, fire-and-forget)

### BAF Fix Mechanism (rebuyDelta reconciliation)
```
// At entry: baseFuturePool = _getFuturePrizePool()
// futurePoolLocal = baseFuturePool (cached)
// ... BAF/Decimator resolution modifies futurePoolLocal locally ...
// ... _addClaimableEth -> auto-rebuy may write to storage futurePrizePool ...
// At write-back:
//   rebuyDelta = _getFuturePrizePool() - baseFuturePool  // captures storage-side writes
//   _setFuturePrizePool(futurePoolLocal + rebuyDelta)     // reconciles both
```

</code_context>

<specifics>
## Specific Ideas

### BAF Fix Correctness Proof Requirements
The Mad Genius must answer these specific questions:
1. Can `_getFuturePrizePool()` at line 245 ever differ from `baseFuturePool` by MORE than the auto-rebuy writes? (i.e., can anything else write futurePrizePool between entry and write-back?)
2. Can `_getFuturePrizePool()` at line 245 ever be LESS than `baseFuturePool`? (underflow risk)
3. Is the condition `if (futurePoolLocal != baseFuturePool)` correct? What if the only change was a rebuyDelta but futurePoolLocal happens to equal baseFuturePool?
4. Does the `lootboxToFuture` return from `_runBafJackpot` correctly exclude auto-rebuy ETH? (double-counting risk)

### Game Over Module Attack Vectors
- Can `handleGameOverDrain()` be called multiple times to drain funds?
- Is the `gameOverFinalJackpotPaid` guard sufficient?
- Can an attacker manipulate `rngWordByDay[day]` to influence game-over jackpot distribution?
- Can stETH transfer failures permanently block game-over processing?
- Can `handleFinalSweep()` be front-run to claim before sweep executes?

</specifics>

<deferred>
## Deferred Ideas

- **Phase 109 coordination**: `runDecimatorJackpot` internals are audited in Unit 7. This phase only traces the return value for state coherence.
- **Phase 105 coordination**: `runTerminalJackpot` internals are audited in Unit 3. This phase only traces the return value and claimablePool update.
- **Phase 118**: Full cross-module state coherence verification is deferred to the integration sweep.

</deferred>

---

*Phase: 106-endgame-game-over*
*Context gathered: 2026-03-25*
