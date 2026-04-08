# Phase 200: Payout Reference Rewrite - Context

**Gathered:** 2026-04-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Rewrite JACKPOT-PAYOUT-REFERENCE.md to reflect the unified `_processDailyEth` with skip-split architecture (Phase 198). Update JACKPOT-EVENT-CATALOG.md to current commit. Fix all stale references to deleted `_distributeJackpotEth`.

</domain>

<decisions>
## Implementation Decisions

### Document Structure
- **D-01:** Clear and rewrite JACKPOT-PAYOUT-REFERENCE.md. Keep organization by jackpot type (current structure is already correct). Add skip-split path documentation alongside three-call split.
- **D-02:** The three-call split section must document both SPLIT_NONE (single call, <= 160 winners) and SPLIT_CALL1+CALL2 (two calls, > 160 winners) as conditional paths.

### Stale References
- **D-03:** Fix audit findings F-02 and F-03: replace all `_distributeJackpotEth` references with `_processDailyEth(SPLIT_NONE, isJackpotPhase=false)`.
- **D-04:** Fix stale contract comment F-01 (GameOverModule.sol:170) and test comments F-04/F-05 (AdvanceGameGas.test.js:1053-1054) — these are contract/test file changes requiring user approval before commit.

### Event Catalog
- **D-05:** Update JACKPOT-EVENT-CATALOG.md verified-against commit hash to current HEAD. Verify all line numbers and emitting paths still match.

### Claude's Discretion
- Prose style, section ordering within jackpot types, level of detail in code path traces.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Current Documents (to rewrite/update)
- `docs/JACKPOT-PAYOUT-REFERENCE.md` — Current payout reference (stale three-call-only description)
- `docs/JACKPOT-EVENT-CATALOG.md` — Current event catalog (stale commit reference)

### Audit Findings (source of required changes)
- `.planning/phases/199-delta-audit-skip-split-gas/199-02-AUDIT.md` — Section F lists all 5 stale references with exact line numbers and recommended fixes
- `.planning/phases/199-delta-audit-skip-split-gas/199-01-GAS-DERIVATION.md` — Gas figures for skip-split vs split paths

### Contract Source (ground truth)
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_processDailyEth`, `payDailyJackpot`, split mode logic
- `contracts/modules/DegenerusGameAdvanceModule.sol` — Stage machine, caller paths
- `contracts/modules/DegenerusGameGameOverModule.sol` — Terminal jackpot caller (F-01 stale comment location)

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Changes from Phase 198
- `_distributeJackpotEth` and `_processOneBucket` deleted — replaced by unified `_processDailyEth`
- `splitMode` enum: SPLIT_NONE (all buckets in one call), SPLIT_CALL1 (largest+solo), SPLIT_CALL2 (mid buckets)
- Skip-split triggers when `totalWinners <= JACKPOT_MAX_WINNERS` (160)
- `isJackpotPhase` flag gates whale pass and DGNRS awards (false for early-burn/terminal)

### Integration Points
- JACKPOT-PAYOUT-REFERENCE.md is referenced by audit reports and external documentation
- JACKPOT-EVENT-CATALOG.md cross-references payout reference section numbers

</code_context>

<specifics>
## Specific Ideas

No specific requirements — rewrite is dictated by current contract code.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 200-payout-reference-rewrite*
*Context gathered: 2026-04-08*
