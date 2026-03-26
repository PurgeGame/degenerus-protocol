# Phase 122: Degenerette Freeze Fix - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix I-12: allow degenerette ETH resolution during `prizePoolFrozen` by routing payouts through the pending pool side-channel. Isolated in its own phase due to BAF cache-overwrite reintroduction risk. Single requirement: FIX-04.

</domain>

<decisions>
## Implementation Decisions

### FIX-04: Degenerette ETH resolution during freeze
- **D-01:** In `_distributePayout` (DegenerusGameDegeneretteModule.sol L685), instead of reverting with `E()` when `prizePoolFrozen` is true, check if the pending future accumulator (`_getPendingPools().pFuture`) can cover the payout amount.
- **D-02:** If `pFuture >= payoutAmount`, deduct from the pending accumulator via `_setPendingPools(pNext, pFuture - payoutAmount)` and proceed with the payout. If `pFuture < payoutAmount`, revert as before.
- **D-03:** This mirrors the existing bet-placement pattern at DegeneretteModule L558-561 which already uses `_setPendingPools` during freeze.
- **D-04:** BURNIE and WWXRP resolutions are unaffected — they don't touch prize pools.
- **D-05:** The live `futurePrizePool` snapshot that `advanceGame`/`runRewardJackpots` operates on remains untouched. Only the pending accumulator (being filled by purchases during freeze) is debited.

### BAF cache-overwrite safety
- **D-06:** After the fix, run a BAF cache-overwrite re-scan of all `_getFuturePrizePool()` read-then-write paths in DegeneretteModule to confirm zero reintroduction of the v4.4 bug class.
- **D-07:** Write a Foundry test proving ETH conservation across a resolution-during-freeze scenario (total ETH in = total ETH out + total ETH held).
- **D-08:** Load v4.4 Phase 100-102 deliverables to bound the re-scan scope before implementation.

### Claude's Discretion
- Exact Foundry test structure and helper setup
- Whether to inline the BAF scan as a code comment or a separate audit document

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Contract file being modified
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — L685 (_distributePayout freeze guard), L558-561 (existing bet-placement pending pool pattern)

### BAF context from v4.4
- `.planning/phases/100-protocol-wide-pattern-scan/` — BAF cache-overwrite scan methodology
- `.planning/phases/101-bug-fix/` — rebuyDelta reconciliation fix in EndgameModule
- `.planning/phases/102-verification/` — BAF fix verification

### Prior audit findings
- `audit/FINDINGS.md` — v5.0 master findings
- `.planning/research/SUMMARY.md` — Pitfall #1: BAF reintroduction via I-12

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_getPendingPools()` / `_setPendingPools()` — existing pending pool accessors in DegeneretteModule
- Bet-placement pattern at L558-561 — exact template for the fix
- `BafRebuyReconciliation.t.sol` — existing BAF test that can be extended

### Established Patterns
- Pending pool side-channel: purchases during freeze accumulate in `_getPendingPools()`, merged into live pool when freeze lifts
- BAF cache-overwrite: a function reads futurePrizePool into a local, does work that modifies futurePrizePool, then writes the stale local back — clobbering the modification

### Integration Points
- Only `_distributePayout` in DegeneretteModule is modified
- No other modules or contracts change
- ETH flow: payout debits pending accumulator instead of live pool

</code_context>

<specifics>
## Specific Ideas

- User emphasized this is the highest-risk change in the milestone — hence isolation in its own phase
- The fix should be minimal: check pFuture, debit if sufficient, revert if not
- The BAF scan is the verification gate, not the code change itself

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 122-degenerette-freeze-fix*
*Context gathered: 2026-03-26*
