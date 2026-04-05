# Phase 190: ETH Flow + Rebuy Delta + Event Audit - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Code-level behavioral equivalence verification of commit `a2d1c585` (BAF simplification). Prove that `runBafJackpot` returning only `claimableDelta` (was 3 values), the removed rebuy delta reconciliation, and unconditional `RewardJackpotsSettled` emission produce identical ETH flow outcomes for every winner path. Storage layout and test regression verification are Phase 191.

</domain>

<decisions>
## Implementation Decisions

### Audit Methodology
- **D-01:** Per-path code trace with verdict table — established pattern from v18.0, v20.0, v21.0 delta audits
- **D-02:** Each FLOW/DELTA/EVT requirement gets its own section with explicit EQUIVALENT/NOT-EQUIVALENT/KNOWN verdict
- **D-03:** Algebraic proof where applicable (e.g., showing `memFuture -= claimed` equals the old `memFuture -= bafPoolWei; memFuture += (bafPoolWei - netSpend); memFuture += lootboxToFuture` expansion)

### Off-Chain Consumer Check (EVT-01)
- **D-04:** Search contracts and test files for `RewardJackpotsSettled` consumers. Off-chain indexer code is not in this repo — note as out-of-scope if no on-chain consumers found

### Pre-Existing Issues
- **D-05:** Only verify the delta — pre-existing issues unchanged by this commit are out of scope. Note them as KNOWN/PRE-EXISTING if encountered but do not flag as findings

### Auto-Rebuy Write Chain (DELTA-01/DELTA-02)
- **D-06:** Trace the full BAF sub-call chain (runBafJackpot -> _awardJackpotTickets -> _purchaseTicketsOnBehalf -> futurePool write) and prove the removed `storageBaseFuture` reconciliation is redundant because `_setPrizePools` at function end overwrites the same storage slot

### Claude's Discretion
- Audit document structure and section ordering
- Level of detail in algebraic proofs
- Whether to include inline code snippets or reference line numbers

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source commit
- Commit `a2d1c585` — the BAF simplification diff (5 files, 79 deletions, 16 additions)

### Changed contracts
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `_consolidatePoolsAndRewardJackpots` caller-side changes (memFuture deduction, rebuy delta removal, unconditional event)
- `contracts/modules/DegenerusGameJackpotModule.sol` — `runBafJackpot` return value simplification, lootboxTotal/netSpend removal
- `contracts/DegenerusGame.sol` — `runBafJackpot` proxy passthrough signature change
- `contracts/interfaces/IDegenerusGame.sol` — interface signature change
- `contracts/interfaces/IDegenerusGameModules.sol` — interface signature change

### External jackpots contract
- `contracts/DegenerusJackpots.sol` — `runBafJackpot` (unchanged, returns winnersArr/amountsArr/refund)
- `contracts/interfaces/IDegenerusJackpots.sol` — interface (unchanged)

### Requirements
- `.planning/REQUIREMENTS.md` — FLOW-01 through FLOW-05, DELTA-01, DELTA-02, EVT-01

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Change Points
- `DegenerusGameAdvanceModule._consolidatePoolsAndRewardJackpots` (~line 704): BAF section now does `memFuture -= claimed` instead of multi-step netSpend/lootboxToFuture/refund adjustment. Rebuy delta fold-back (`memFuture += _getFuturePrizePool() - storageBaseFuture`) removed entirely.
- `DegenerusGameJackpotModule.runBafJackpot` (~line 2485): Returns only `claimableDelta`. Lootbox/whale pass ETH stays in futurePool implicitly (no explicit return). `netSpend` calculation removed.

### Winner Paths to Trace
- Top winners (i < 5): `claimableDelta += amount` (direct ETH claim)
- Big winners with lootbox (i >= 5, amount >= threshold): lootbox portion via `_awardJackpotTickets`, remainder via `_queueWhalePassClaimCore`
- Small winners even index: direct ETH claim
- Small winners odd index: full lootbox via `_awardJackpotTickets`
- Refund: returned by `jackpots.runBafJackpot` but no longer tracked as netSpend

### Integration Points
- `_setPrizePools` at end of `_consolidatePoolsAndRewardJackpots` writes `memFuture` to storage — this is where the final futurePool value lands
- `_awardJackpotTickets` calls `_purchaseTicketsOnBehalf` which writes to futurePool STORAGE during execution
- Decimator path uses `baseMemFuture` snapshot (pre-jackpot), separate from BAF

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard delta audit methodology applies.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 190-eth-flow-rebuy-delta-event-audit*
*Context gathered: 2026-04-05*
