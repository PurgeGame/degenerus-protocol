# Phase 215: RNG Fresh Eyes - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Ground-up VRF/RNG audit proving the system sound from first principles. Covers the full VRF lifecycle (request, fulfillment, word distribution), backward traces from every RNG consumer, commitment window analysis, word derivation verification, and rngLocked mutual exclusion. No reliance on prior RNG audit conclusions from v3.7/v3.8/v3.9 milestones.

</domain>

<decisions>
## Implementation Decisions

### Audit Plan Structure
- **D-01:** Split by requirement, not by RNG chain. Five plans mapping 1:1 to RNG-01 through RNG-05:
  1. VRF lifecycle end-to-end trace (RNG-01)
  2. Backward trace from every RNG consumer (RNG-02)
  3. Commitment window analysis (RNG-03)
  4. Word derivation verification (RNG-04)
  5. rngLocked mutual exclusion + synthesis (RNG-05)
- Plans 01-04 are independent and run as Wave 1 (parallel). Plan 05 depends on 01-04 and runs as Wave 2.

### LCG/PRNG Analysis Depth
- **D-02:** Seed provenance only. For the assembly LCG PRNG in _raritySymbolBatch (RNG-07), prove the seed derives from VRF and cannot be influenced post-commitment. Do NOT analyze LCG statistical properties, bias, period length, or correlation -- that is a game balance concern, not a security concern.

### Prior Audit Reuse
- **D-03:** Fresh from scratch for RNG conclusions. Do NOT reference or rely on prior RNG audit artifacts from v3.7, v3.8, or v3.9 milestones. Audit the VRF system as if no prior RNG work exists. This eliminates inherited assumptions that allowed the ticket queue swap vulnerability to survive 10+ prior audit passes.

### Phase 214 Cross-Reference
- **D-04:** Phase 215 CAN reference Phase 214 adversarial audit findings as supporting evidence. The "fresh eyes" constraint applies to PRIOR RNG AUDITS (v3.7/v3.8/v3.9), not to Phase 214 which covered different vulnerability classes (reentrancy, access control, state corruption). E.g., citing "rngLocked verified as mutual exclusion guard in 214-01" is acceptable.

### Mandatory Methodology (from established feedback)
- **D-05:** Every RNG consumer MUST be traced BACKWARD to verify the word was unknown at input commitment time. Do not only trace forward from VRF delivery. This is the methodology that caught the ticket queue swap vulnerability after 10+ forward-trace audits missed it.
- **D-06:** Every path between VRF request and fulfillment MUST have an analysis of what player-controllable state can change in that window. Think like an attacker who sees the VRF request tx and asks "what can I change before fulfillment lands?"

### Claude's Discretion
- Per-chain audit format and finding numbering scheme
- How to organize the backward trace document (by consumer, by contract, by chain ID)
- How to present commitment window analysis (timeline diagrams, tables, prose)
- Whether to include a "VRF assumptions" section documenting Chainlink VRF trust model

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 213 deliverables (RNG chain definitions)
- `.planning/phases/213-delta-extraction/213-DELTA-EXTRACTION.md` -- Contains RNG-01 through RNG-11 chain definitions in cross-module interaction map
- `.planning/phases/213-delta-extraction/213-01-DELTA-MODULES.md` -- Module function changelog (RNG-related function changes)
- `.planning/phases/213-delta-extraction/213-02-DELTA-CORE.md` -- Core function changelog

### Phase 214 deliverables (can reference as supporting evidence per D-04)
- `.planning/phases/214-adversarial-audit/214-01-REENTRANCY-CEI.md` -- Reentrancy verdicts for RNG-touching functions
- `.planning/phases/214-adversarial-audit/214-03-STATE-COMPOSITION.md` -- State corruption verdicts for RNG state
- `.planning/phases/214-adversarial-audit/214-05-ATTACK-CHAINS-CALLGRAPH.md` -- Call graphs for RNG entry points

### Requirements
- `.planning/REQUIREMENTS.md` -- RNG-01, RNG-02, RNG-03, RNG-04, RNG-05

### Contract source (current HEAD)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- VRF request/fulfillment, rngGate, _requestRng, rawFulfillRandomWords, requestLootboxRng, _finalizeLootboxRng, _backfillGapDays, _gameOverEntropy
- `contracts/modules/DegenerusGameJackpotModule.sol` -- _randTraitTicket, _runJackpotEthFlow, payDailyJackpot carryover, _rollWinningTraits, _applyHeroOverride
- `contracts/modules/DegenerusGameMintModule.sol` -- _raritySymbolBatch (LCG PRNG, moved from JackpotModule)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` -- _placeDegeneretteBetCore (bet resolution via daily word)
- `contracts/modules/DegenerusGameLootboxModule.sol` -- openLootbox/openBurnieLootbox, _rollLootboxBoons, _deityDailySeed, _deityBoonForSlot
- `contracts/modules/DegenerusGameGameOverModule.sol` -- handleGameOverDrain (terminal resolution)
- `contracts/storage/DegenerusGameStorage.sol` -- rngLocked flag, rngWordByDay, lastLootboxRngWord, lootboxRngWordByIndex

</canonical_refs>

<code_context>
## Existing Code Insights

### RNG Surface (from Phase 213 cross-module map)
- 11 RNG chains identified (RNG-01 through RNG-11)
- 2 VRF request paths: daily word (_requestRng) and lootbox word (requestLootboxRng)
- 1 fallback path: _gameOverEntropy uses prevrandao when VRF unavailable
- RNG consumers spread across 6 module contracts
- rngLocked flag provides mutual exclusion for state-changing paths

### Key RNG Patterns (from delta extraction)
- Daily RNG: requested at end of advanceGame, fulfilled at start of next advanceGame via rngGate
- Lootbox RNG: separate VRF request/fulfillment cycle with per-index word storage
- Gap day backfill: uses keccak256 of existing word + gap index for entropy when days are skipped
- LCG PRNG: assembly-level linear congruential generator in _raritySymbolBatch, seeded from lootbox word
- Gameover entropy: reverts RngNotReady() instead of returning 0 when VRF word unavailable

### Phase 214 Findings Relevant to RNG
- Zero reentrancy VULNERABLE findings on RNG-touching functions (214-01)
- rngLocked flag verified as mutual exclusion guard (214-01)
- No access control issues on VRF callback path (214-02)
- No state corruption in RNG packed fields (214-03)

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches within the locked methodology (backward trace + commitment window).

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 215-rng-fresh-eyes*
*Context gathered: 2026-04-10*
