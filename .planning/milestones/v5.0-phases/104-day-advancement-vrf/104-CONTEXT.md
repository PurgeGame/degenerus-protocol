# Phase 104: Day Advancement + VRF - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameAdvanceModule.sol — the day advancement and VRF lifecycle module. This phase examines every state-changing function in the module using the three-agent system (Taskmaster → Mad Genius → Skeptic). The module handles:
- Day advancement logic (advanceGame entry point and all subordinate state transitions)
- VRF request/fulfillment lifecycle (requestRng, rawFulfillRandomWords, rngGate, backfill)
- Daily jackpot payments (ETH, coin, ticket)
- Future ticket processing (prepareFutureTickets, processFutureTicketBatch)
- Lootbox RNG requests (requestLootboxRng, finalizeLootboxRng)
- Phase/level transitions (processPhaseTransition, endPhase)
- Auto-stake excess ETH

This phase does NOT re-audit module internals of other modules called via subordinate paths (those are in Phases 105-117). Cross-module calls are traced far enough to verify state coherence in the calling context.

**PRIORITY INVESTIGATION:** 3 TicketLifecycle Foundry tests fail with `Read queue not drained for level 1: 2 != 0`. Mad Genius must trace `_prepareFutureTickets` and `processFutureTicketBatch` end-to-end to produce a CONFIRMED BUG or PROVEN SAFE verdict with full evidence.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only — no Category A. This is a module, not the router. Category A (delegatecall dispatchers) does not apply. External/public state-changing functions → Category B. Internal/private state-changing helpers → Category C. View/pure functions → Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states.

### Ticket Queue Drain Investigation
- **D-04:** The ticket queue drain investigation is a PRIORITY item. The Mad Genius must produce a dedicated section tracing `_prepareFutureTickets` and `processFutureTicketBatch` end-to-end with a standalone verdict: CONFIRMED BUG or PROVEN SAFE.
- **D-05:** The investigation must trace the full ticket lifecycle: queue write → batch processing → consumption. The 3 failing tests (testFiveLevelIntegration, testMultiLevelZeroStranding, testZeroStrandingSweepAfterTransitions) must be examined to determine whether the failure is a contract bug or test setup issue.

### VRF Audit Overlap
- **D-06:** Fresh adversarial analysis on ALL functions — do not reference or trust prior findings from v3.7/v3.8. The entire point of v5.0 is catching bugs that survived 24 prior milestones. Prior audit results are not input to this phase.
- **D-07:** VRF paths (requestRng, rawFulfillRandomWords, rngGate, backfillGapDays) get the same full treatment as every other function. No reduced scrutiny for "already audited" code.

### Cross-Module Call Boundary
- **D-08:** When advanceGame() or other functions chain into code from other modules (jackpot, endgame, mint), trace the subordinate calls far enough to verify the parent's state coherence — specifically the cached-local-vs-storage check. Full internals of those modules are audited in their own unit phases (105-117).
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
- `.planning/ULTIMATE-AUDIT-DESIGN.md` — Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contract
- `contracts/modules/DegenerusGameAdvanceModule.sol` — The audit target (1571 lines, 30+ functions)

### Storage Layout (verified in Phase 103)
- `contracts/storage/DegenerusGameStorage.sol` — Shared storage layout inherited by all modules

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` — Module function signatures

### Prior Phase Outputs (methodology reference only — do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` — Phase 103 context (Category A/B/C/D pattern, report format)
- `audit/unit-01/COVERAGE-CHECKLIST.md` — Phase 103 Taskmaster output (format reference)
- `audit/unit-01/ATTACK-REPORT.md` — Phase 103 Mad Genius output (format reference)

### Prior Audit Context (known issues — do not re-report)
- `audit/KNOWN-ISSUES.md` — Known issues from v1.0-v4.4

### Ticket Queue Drain (priority investigation)
- `test/foundry/TicketLifecycle.t.sol` — The 3 failing tests that motivate the investigation

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from grep)
- `advanceGame()` (L125) — Main entry point, external, the primary state-changing function
- `wireVrf()` (L412) — Admin VRF setup
- `payDailyJackpot()` (L587) — Daily ETH jackpot distribution
- `payDailyJackpotCoinAndTickets()` (L609) — Daily coin/ticket jackpot
- `requestLootboxRng()` (L689) — Mid-day lootbox RNG request (external)
- `rngGate()` (L783) — VRF callback router
- `rawFulfillRandomWords()` (L1455) — VRF callback entry point
- `reverseFlip()` (L1438) — Reverse flip action (external)
- `updateVrfCoordinatorAndSub()` (L1390) — Admin VRF config update
- `_prepareFutureTickets()` (L1171) — PRIORITY: future ticket queue preparation
- `_processFutureTicketBatch()` (L1149) — PRIORITY: batch ticket processing
- `_handleGameOverPath()` (L433) — Game over transition
- `_endPhase()` (L487) — Phase transition
- `_requestRng()` (L1276) — VRF request initiation
- `_backfillGapDays()` (L1489) — Gap day RNG backfill
- `_applyDailyRng()` (L1536) — Daily RNG application

### Established Pattern (from Phase 103)
- 4-plan structure: Taskmaster checklist → Mad Genius attack → Skeptic review → Final report
- Category A/B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-02/` directory

### Integration Points
- advanceGame() calls into jackpot module (payDailyJackpot chains to JackpotModule)
- advanceGame() calls into endgame module (_handleGameOverPath)
- _prepareFutureTickets interacts with mint module's ticket queue
- rawFulfillRandomWords feeds RNG words to multiple downstream consumers
- rngGate() routes VRF callbacks to appropriate handlers

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system (Taskmaster checklist → Mad Genius attack → Skeptic review) drives the workflow, same as Phase 103.

The PRIORITY INVESTIGATION on ticket queue drain is the main differentiator from the standard unit audit flow.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 107 coordination**: `processFutureTicketBatch` lives in AdvanceModule but the ticket queue write path lives in MintModule. Phase 107 (Mint + Purchase Flow) should coordinate with this phase's ticket queue drain findings.
- **Phase 118**: Full cross-module state coherence verification is deferred to the integration sweep.

</deferred>

---

*Phase: 104-day-advancement-vrf*
*Context gathered: 2026-03-25*
