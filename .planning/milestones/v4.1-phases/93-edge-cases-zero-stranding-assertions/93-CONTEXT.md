# Phase 93: Edge Cases + Zero-Stranding Assertions - Context

**Gathered:** 2026-03-23
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Add edge case tests and comprehensive zero-stranding assertion sweeps to test/fuzz/TicketLifecycle.t.sol. Verify boundary routing (level+5 → write key, level+6 → FF key), FF drain timing (at phase transition not daily cycle), jackpot-phase read-slot processing after _swapAndFreeze, last-day routing fix, and multi-level zero-stranding across all key spaces.

Requirements: EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-06, ZSA-01, ZSA-02, ZSA-03

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP success criteria and Phase 92 patterns.

Key constraints from user:
- advanceGame is NOT considered permissionless (resolver, not manipulator)
- Purchase routing ALWAYS writes to write slot regardless of rngLocked
- Near/far boundary: > level + 5 (level+5 = near, level+6 = far)
- FF drain at transition: purchaseLevel + 4 = level + 5
- _prepareFutureTickets: +1..+4 from base (read queues only, no FF)
- Last-day fix: rngLocked + jackpotCounter+step >= JACKPOT_LEVEL_CAP routes to level+1

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (from Phase 92)
- test/fuzz/TicketLifecycle.t.sol — 15 passing tests, TLKeyComputer, all helpers
- Helpers: _driveToLevel, _buyTickets, _fulfillVrfIfPending, _seedNextPrizePool, _ffQueueLength, _queueLength, _readKeyForLevel, _writeKeyForLevel, _getWriteSlot, _purchaseWithLootbox, _openLootbox, _storeLootboxRngWord, _driveAdvanceCycle, _flushAdvance, _buyWhaleBundle
- Existing boundary test: testBoundaryRoutingAtDeployment (checks level 5 vs 6 at deploy)

### Patterns
- Storage inspection: vm.load for queue lengths, ticketsOwedPacked
- Level driving: _driveToLevel seeds pool + buys + loops advanceGame/VRF
- _flushAdvance: drives advanceGame in tight loop until NotTimeYet

### Key Contract Logic
- _swapAndFreeze (DGS:719): ticketWriteSlot ^= 1, write becomes read
- _endPhase (AM:491): sets phaseTransitionActive, resets jackpotCounter
- _processPhaseTransition (AM:1235): queues vault perpetual, returns true
- FF drain (AM:240-265): at phaseTransitionActive, drains FF at purchaseLevel+4
- _prepareFutureTickets (AM:1172): +1..+4 from base level (read queues only)
- _processDirectPurchase (MM:848): jackpotPhaseFlag ? level : level+1, with last-day override

</code_context>

<specifics>
## Specific Ideas

Phase 92 already has testBoundaryRoutingAtDeployment (EDGE-01/02 at level 0). Phase 93 should add boundary tests at non-zero levels to be thorough.

For ZSA-03 (multi-level zero-stranding), the existing testMultiLevelZeroStranding + testFiveLevelIntegration provide partial coverage. Phase 93 should add a definitive sweep using multiple ticket sources simultaneously.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
