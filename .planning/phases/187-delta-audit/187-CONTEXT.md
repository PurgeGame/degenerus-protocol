# Phase 187: Delta Audit - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify every behavioral change from Phase 186 (pool consolidation, write batching, BAF entry point, self-call guard, Game passthrough, quest entropy fix) is correct and introduces no bugs. The restructuring changed operation order, so pool values may differ slightly from pre-restructuring — this is expected. The audit must prove the new order is sound, not that outputs are byte-identical.

</domain>

<decisions>
## Implementation Decisions

### Equivalence verification approach
- **D-01:** Full variable sweep audit, not strict equivalence. Phase 186 changed the order of pool operations (consolidation inlined into AdvanceModule, batched SSTOREs), so intermediate and possibly final pool values differ slightly from pre-restructuring. The audit must trace every variable through the new flow, verify no bugs were introduced, and sanity-check that the new operation order is logically correct.
- **D-02:** The variable sweep must cover all three level transition paths: normal advance, x10 skip, x100 skip. Each path exercises different branches of the consolidated pool flow (x00 triggers yield dump and keep roll; x10 triggers future-to-next drawdown).

### Audit scope
- **D-03:** All Phase 186 behavioral changes are in scope — not just pool equivalence. This includes:
  - Pool consolidation flow in AdvanceModule (DELTA-01, DELTA-02)
  - Self-call guard on JackpotModule.runBafJackpot
  - DegenerusGame.sol passthrough for runBafJackpot
  - Quest entropy change (rngWordByDay[day] -> rngWord)
  - Interface completeness (IDegenerusGameModules, IDegenerusGame)
  - Dead code removal verification (5 functions + 2 helpers deleted from JackpotModule)
- **D-04:** Test suite regression check covers both Foundry and Hardhat with zero unexpected regressions (DELTA-03).

### Claude's Discretion
- Plan structure and ordering of audit tasks
- Level of detail in pool mutation trace formatting
- Whether to combine smaller checks (quest entropy, interface, dead code) into a single plan or separate them

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 186 implementation (audit target)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — Consolidated pool flow: _consolidatePoolsAndRewardJackpots, batched SSTOREs via _setPrizePools, rebuy delta reconciliation
- `contracts/modules/DegenerusGameJackpotModule.sol` — runBafJackpot external entry point with self-call guard, dead code removed (consolidatePrizePools, runRewardJackpots, _futureKeepBps, _creditDgnrsCoinflip, _drawDownFuturePrizePool)
- `contracts/DegenerusGame.sol` — runBafJackpot passthrough delegatecall
- `contracts/interfaces/IDegenerusGameModules.sol` — Updated interface declarations
- `contracts/interfaces/IDegenerusGame.sol` — Updated interface declarations

### Phase 186 context (what was intended)
- `.planning/phases/186-pool-consolidation-write-batching/186-CONTEXT.md` — Implementation decisions D-01 through D-03, canonical refs to old code locations

### Phase 186 plans (what was executed)
- `.planning/phases/186-pool-consolidation-write-batching/186-01-PLAN.md` — JackpotModule entry points + body gutting + interface update + Game passthrough + quest entropy fix
- `.planning/phases/186-pool-consolidation-write-batching/186-02-PLAN.md` — Inline consolidation + orchestration + drawdown into AdvanceModule with SSTORE batching
- `.planning/phases/186-pool-consolidation-write-batching/186-03-PLAN.md` — Dead code removal from JackpotModule + clean interface
- `.planning/phases/186-pool-consolidation-write-batching/186-04-PLAN.md` — Gap closure: runBafJackpot passthrough + self-call guard

### Prior finding (shapes audit focus)
- v19.0 Phase 185 finding F-185-01 (HIGH): deferred SSTORE overwrote auto-rebuy futurePool additions. Verify the new batched flow handles this correctly via re-read-after-jackpot pattern.

### Requirements
- `.planning/REQUIREMENTS.md` — DELTA-01, DELTA-02, DELTA-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Changes to Audit
- `_consolidatePoolsAndRewardJackpots` in AdvanceModule — the new consolidated flow replacing 2 separate delegatecalls (consolidatePrizePools + runRewardJackpots)
- `_setPrizePools` batch write — single SSTORE replacing multiple intermediate writes
- `runBafJackpot` external entry point — promoted from private `_runBafJackpot` with self-call guard (`msg.sender == address(this)`)
- Quest entropy: `rngWord` replacing `rngWordByDay[day]` at the advance flow

### Git Diff Scope
- `git diff d8dbd9e3^..41786790 -- contracts/` captures all Phase 186 changes: 5 files, 328 insertions, 340 deletions

### Established Audit Patterns
- Prior delta audits (v15.0, v18.0, v19.0) used function-level trace + test regression as the core methodology
- v19.0 Phase 185 found a HIGH severity bug in deferred SSTORE — this validates that delta audits catch real issues in pool restructuring

### Integration Points
- AdvanceModule delegatecalls into JackpotModule for individual jackpot execution (BAF via runBafJackpot, Decimator via runDecimatorJackpot)
- Auto-rebuy writes to futurePool storage mid-execution — handled by re-reading storage after _executeJackpot (F-185-01 pattern)

</code_context>

<specifics>
## Specific Ideas

- User emphasized this is NOT a strict equivalence check — the new order intentionally produces different intermediate values. The audit proves correctness of the new flow, not identity with the old one.
- "Full variable sweep audit" — trace every variable through each path, verify no bugs, sanity-check the operation order makes sense.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 187-delta-audit*
*Context gathered: 2026-04-05*
