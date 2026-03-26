# Phase 38: RNG Delta Security - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Audit all RNG-adjacent code changes since v3.1 for security. Primary focus: rngLocked guard removal from coinflip claim paths and its safety implications. Secondary: decimator claim expiry removal (correctness only). Produce verdicts with severity classification per finding.

</domain>

<decisions>
## Implementation Decisions

### Attack model
- Two attacker scenarios modeled separately: (1) MEV-aware attacker who can see VRF word in mempool before fulfillRandomWords executes, and (2) compromised VRF operator who knows the word early
- Attacker budget: 1000 ETH (consistent with prior C4A warden model)
- Multi-block attacks: Claude's discretion based on whether consecutive-block control is relevant per scenario

### Carry isolation verification
- Full code trace of every write to autoRebuyCarry and claimableStored to prove they never cross
- Plus a written formal invariant: "carry ETH is never reachable from any claim path"
- Both the trace and invariant are required deliverables

### BAF guard analysis
- Full enumeration of all bypass scenarios (timing, reentrancy, state manipulation)
- sDGNRS path: verify sDGNRS is ineligible for BAF entirely (not just that the guard is skipped). If sDGNRS is truly ineligible for BAF, no further BAF guard analysis needed for that path

### Cross-contract scope
- Audit ALL rngLocked consumers across all contracts (not just the 4 removed paths)
- Produce a dependency matrix: contract, function, whether it assumed claims were blocked during RNG lock, whether it's still safe without that assumption
- Decimator claim persistence: correctness check only (double-claim prevention, ETH accounting works across rounds). Not treated as a new attack vector — same security posture as before, just different storage layout

### Claude's Discretion
- Deliverable structure and finding grouping
- Whether to model multi-block MEV attacks (per-scenario judgment)
- Depth of decimator correctness checks beyond double-claim and ETH accounting

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### RNG-adjacent contracts (primary)
- `contracts/BurnieCoinflip.sol` — All claim functions, BAF guard, _claimCoinflipsInternal, sDGNRS claim path
- `contracts/modules/DegenerusGameAdvanceModule.sol` — rngLockedFlag set/clear, VRF request/fulfill flow
- `contracts/modules/DegenerusGameDecimatorModule.sol` — Per-level decClaimRounds mapping, _consumeDecClaim

### rngLocked consumers (cross-contract)
- `contracts/DegenerusGame.sol` — rngLocked() view, mint/purchase guards
- `contracts/BurnieCoin.sol` — spendable() calculation uses rngLocked
- `contracts/modules/DegenerusGameWhaleModule.sol` — rngLocked guard on whale actions
- `contracts/storage/DegenerusGameStorage.sol` — rngLockedFlag storage slot

### Interfaces (deleted functions)
- `contracts/interfaces/IBurnieCoinflip.sol` — claimCoinflipsTakeProfit removed
- `contracts/interfaces/IDegenerusGame.sol` — futurePrizePoolTotalView removed

### Prior audit context
- `.planning/milestones/` — v2.1 governance audit verdicts (26 verdicts, WAR-01/02/06)

</canonical_refs>

<code_context>
## Existing Code Insights

### Key changes since v3.1
- `rngLocked()` check removed from: claimCoinflips, claimCoinflipsFromBurnie, consumeCoinflipsForBurn (4 call sites)
- `claimCoinflipsTakeProfit` and `_claimCoinflipsTakeProfit` deleted entirely (function + interface)
- `flipsClaimableDay` comment changed from "RNG state" to "Last resolved day"
- Decimator: `lastDecClaimRound` (single-slot struct) replaced with `decClaimRounds[lvl]` (per-level mapping)
- `TerminalDecAlreadyClaimed` error removed (terminal decimator uses weightedBurn=0 as claimed flag)

### rngLocked still enforced in
- DegenerusGame: mint functions (lines 1542, 1563, 1578, 1643)
- AdvanceModule: advance function (line 673), VRF retry (line 1295)
- WhaleModule: whale actions (line 470)
- BurnieCoin: spendable calculation (line 273)
- BurnieCoinflip: BAF guard within _claimCoinflipsInternal (lines 551-559), leaderboard update (line 630), depositCoinflip (line 691), withdrawal (line 741)

### Safety architecture after changes
- BAF guard: epoch-based, blocks claims only during BAF resolution window (not all RNG locks)
- Carry isolation: autoRebuyCarry stored separately from claimableStored
- sDGNRS claims: skip BAF section entirely (line 845) — needs verification of BAF ineligibility

</code_context>

<specifics>
## Specific Ideas

- "sDGNRS shouldn't be eligible for BAF at all — verify that is the case, and if so, other BAF guards don't really matter for that path"
- "Decimator claims are not a real issue — just verify they work. Not an attack vector any more than before"
- Dependency matrix format: contract | function | assumes-claims-blocked | still-safe-without

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 38-rng-delta-security*
*Context gathered: 2026-03-19*
