# Phase 166: RNG & Gas Verification - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Re-verify VRF commitment windows for all new/modified VRF-dependent paths introduced in v11.0-v14.0, and prove new computation paths (score calculation, quest roll, drip projection, PriceLookupLib) are within gas ceilings. No code changes — audit and documentation only.

</domain>

<decisions>
## Implementation Decisions

### VRF Consumer Scope
- **D-01:** Delta only — audit VRF paths that are new or modified in v11.0-v14.0. Cite prior audit verdicts (v1.2, v3.8) for unchanged paths. Do not re-trace paths already proven safe in prior milestones.

### Gas Profiling Method
- **D-02:** Static analysis — count SLOADs, MSTOREs, external calls, and loop iterations from source. No test execution required. Consistent with prior gas audits in this project.

### Commitment Window Trace Depth
- **D-03:** Full call-chain trace — for each new VRF consumer, trace backward through the entire call chain from consumer to VRF fulfillment callback, documenting every intermediate state that touches the word. Not just one-hop.

### RNG Methodology (locked from prior feedback)
- **D-04:** Every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time.
- **D-05:** Every RNG audit must check what player-controllable state can change between VRF request and fulfillment.

### Claude's Discretion
- Report structure and formatting
- Which prior audit verdicts to cite for unchanged paths
- How to organize the gas analysis (by function, by contract, or by path)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 165 Audit Results (input to this phase)
- `.planning/phases/165-per-function-adversarial-audit/165-01-FINDINGS.md` — AdvanceModule + DegenerusGame audit (covers advanceGame loop, entropy derivation, drip projection)
- `.planning/phases/165-per-function-adversarial-audit/165-02-FINDINGS.md` — MintModule + LootboxModule audit (covers purchase path, score computation)
- `.planning/phases/165-per-function-adversarial-audit/165-03-FINDINGS.md` — DegenerusQuests audit (covers quest roll entropy, affiliate PRNG, access control)
- `.planning/phases/165-per-function-adversarial-audit/165-04-FINDINGS.md` — Consolidated findings + storage layout

### Prior RNG Audits (for citing unchanged-path verdicts)
- `.planning/phases/162-changelog-extraction/162-CHANGELOG.md` — Function-level changelog identifying all VRF-dependent changes

### Contracts (VRF consumers)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — advanceGame loop, VRF request/fulfillment, entropy derivation for quests
- `contracts/DegenerusQuests.sol` — rollLevelQuest, rollDailyQuest, _bonusQuestType (entropy consumers)
- `contracts/DegenerusAffiliate.sol` — payAffiliate (PRNG, known tradeoff)
- `contracts/modules/DegenerusGameMintModule.sol` — _computeActivityScore, _purchaseFor, _callTicketPurchase
- `contracts/libraries/MintStreakUtils.sol` — _mintCountBonusPoints
- `contracts/libraries/PriceLookupLib.sol` — priceForLevel (pure function, gas target)

</canonical_refs>

<code_context>
## Existing Code Insights

### VRF Architecture
- VRF request in AdvanceModule via Chainlink VRF v2
- `rngWordByDay[day]` stores VRF words per day
- `_finalizeRngRequest` consumes words at level transition
- Quest rolls derive entropy from VRF words passed by AdvanceModule

### Gas-Heavy New Paths
- `_computeActivityScore` — new in v14.0, runs on every purchase
- `handlePurchase` — consolidated quest handler, replaces per-handler calls
- `rollLevelQuest` / `clearLevelQuest` — new in v13.0, runs at level transitions
- `_processDripProjection` — new in v11.0, WAD math for endgame flag
- `PriceLookupLib.priceForLevel` — pure function replacing storage variable

### Phase 147 Baseline
- advanceGame gas ceiling was established in Phase 147 (ticket mint gas optimization)
- Safety margin target: well under 14M block gas limit

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard audit methodology applies with the decisions above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 166-rng-gas-verification*
*Context gathered: 2026-04-02*
