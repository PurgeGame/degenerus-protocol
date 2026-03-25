# Phase 118: Cross-Contract Integration Sweep - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

**This is a META-ANALYSIS phase.** It does NOT re-audit individual functions (that was done in Units 1-15). Instead, it examines cross-contract interactions, shared state, and composition risks that individual unit audits could not catch.

### Focus Areas

1. **Delegatecall State Coherence Across All 10 Module Boundaries**
   - DegenerusGame dispatches to 10 modules via delegatecall. All 10 execute in Game's storage context.
   - Verify no module writes to storage that another module has cached locally during the same top-level transaction.
   - Verify the nested delegatecall pattern (LootboxModule -> BoonModule) does not create cross-module cache conflicts.

2. **Shared Storage Consistency**
   - DegenerusGameStorage defines 102 variables across slots 0-78.
   - Map which storage variables are written by multiple modules.
   - Identify any variable where two modules could write conflicting values within the same transaction path.

3. **Cross-Contract Call Chains**
   - Trace every external call from Game/modules to standalone contracts (BurnieCoin, BurnieCoinflip, sDGNRS, DGNRS, Vault, WWXRP, Affiliate, Quests, Jackpots, Admin).
   - Trace every callback from standalone contracts back into Game.
   - Identify any bidirectional call chains that could create state desync.

4. **ETH Flow Tracing**
   - Every wei that enters the protocol (msg.value on purchase paths, VRF bounties, vault deposits).
   - Every wei that exits (claimable withdrawals, affiliate payments, vault burns, game-over drain).
   - Conservation: does total ETH in = total ETH distributed + total ETH held?

5. **Access Control Matrix Verification**
   - For every external function across all contracts, document what prevents an arbitrary EOA from calling it.
   - Verify all access control gates use compile-time constants (ContractAddresses.*), not configurable addresses.

6. **Token Supply Invariants**
   - BURNIE: Can it be minted without corresponding game action? Can it be burned without proper authorization?
   - DGNRS: totalSupply backed by sDGNRS pool? Unwrap/wrap round-trip correct?
   - sDGNRS: Pool accounting (Whale, Affiliate, Claims) + reserves = totalMoney?
   - WWXRP: Supply vs wXRPReserves -- intentional undercollateralization documented?

7. **State Machine Consistency**
   - Can the game get stuck in an unreachable state?
   - Can jackpotPhase and currentDay become inconsistent?
   - Can rngLocked and prizePoolFrozen get permanently stuck?

</domain>

<decisions>
## Implementation Decisions

### Meta-Analysis Methodology
- **D-01:** This phase synthesizes findings from all 15 unit reports. It does NOT re-read contract source unless verifying a specific cross-contract interaction hypothesis.
- **D-02:** The output format is organized by interaction pattern, NOT by function. Each section covers a cross-contract concern with evidence from multiple units.
- **D-03:** Findings are rated at the integration level. A pattern that is SAFE within one module but UNSAFE when modules compose is a new finding.

### Unit Findings Input
- **D-04:** Read all 15 UNIT-XX-FINDINGS.md files as primary input. Additionally reference ATTACK-REPORT.md and SKEPTIC-REVIEW.md from individual units when deeper evidence is needed for cross-contract claims.
- **D-05:** Cross-reference all "Recommendations for Integration Phase" sections from unit findings (e.g., Unit 10 F-04 recommendations, Unit 9 nested delegatecall notes).

### Scope Boundaries
- **D-06:** Individual function-level bugs that were caught in Units 1-15 are NOT re-reported here. Only composition-level issues are new findings.
- **D-07:** The one exception: if a finding was dismissed as "safe within this module" but is UNSAFE when considering cross-module interaction, it is escalated here as a new integration finding.
- **D-08:** Pre-existing known issues from KNOWN-ISSUES.md are not re-reported.

### Report Structure (adapted for integration sweep)
- **D-09:** Instead of per-function sections, the integration report uses per-concern sections:
  - Cross-Contract Call Map
  - Shared Storage Write Map
  - ETH Flow Conservation Analysis
  - Token Supply Invariant Analysis
  - Access Control Matrix
  - State Machine Consistency
  - Integration Findings (new issues found during composition analysis)

### Claude's Discretion
- Ordering of concern sections within the report
- Depth of evidence citation (enough to prove the claim, no more)
- Whether to reference specific unit report line numbers or summarize the evidence

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design, Unit 16 scope definition, coverage metrics

### All 15 Unit Findings Reports (PRIMARY INPUT)
- `audit/unit-01/UNIT-01-FINDINGS.md` -- Game Router + Storage Layout (177 functions, 0 findings, storage layout PASS)
- `audit/unit-02/UNIT-02-FINDINGS.md` -- Day Advancement + VRF (40 functions, 3 INFO, ticket queue PROVEN SAFE)
- `audit/unit-03/UNIT-03-FINDINGS.md` -- Jackpot Distribution (55 functions, 5 INFO, BAF chains all SAFE)
- `audit/unit-04/UNIT-04-FINDINGS.md` -- Endgame + Game Over (21 functions, 2 INFO, rebuyDelta PROVEN CORRECT)
- `audit/unit-05/UNIT-05-FINDINGS.md` -- Mint + Purchase Flow (20 functions, 0 findings, self-call re-entry SAFE)
- `audit/unit-06/UNIT-06-FINDINGS.md` -- Whale Purchases (16 functions, 1 INFO, cache patterns SAFE)
- `audit/unit-07/UNIT-07-FINDINGS.md` -- Decimator System (32 functions, 1 MEDIUM, decBucketOffsetPacked collision)
- `audit/unit-08/UNIT-08-FINDINGS.md` -- Degenerette Betting (27 functions, 1 LOW + 1 INFO, multi-spin SAFE)
- `audit/unit-09/UNIT-09-FINDINGS.md` -- Lootbox + Boons (32 functions, 1 INFO, nested delegatecall SAFE)
- `audit/unit-10/UNIT-10-FINDINGS.md` -- BURNIE Token + Coinflip (71 functions, 3 INFO, supply invariant SAFE)
- `audit/unit-11/UNIT-11-FINDINGS.md` -- sDGNRS + DGNRS (37 functions, 3 INFO, redemption pipeline SAFE)
- `audit/unit-12/UNIT-12-FINDINGS.md` -- Vault + WWXRP (64 functions, 1 INFO, share math SAFE)
- `audit/unit-13/UNIT-13-FINDINGS.md` -- Admin + Governance (17 functions, 1 LOW + 3 INFO, governance SAFE)
- `audit/unit-14/UNIT-14-FINDINGS.md` -- Affiliate + Quests + Jackpots (61 functions, 1 INFO, epoch mechanism SAFE)
- `audit/unit-15/UNIT-15-FINDINGS.md` -- Libraries (18 functions, 2 INFO, entropy/bit-packing SAFE)

### Storage Layout (verified in Unit 1)
- `contracts/storage/DegenerusGameStorage.sol` -- 102 variables, slots 0-78, all 10 modules EXACT MATCH

### Known Issues (do NOT re-report)
- `audit/KNOWN-ISSUES.md` -- Pre-disclosed design decisions and accepted trade-offs

### Contract Architecture
- `contracts/DegenerusGame.sol` -- Router contract (2,848 lines), dispatches to 10 modules
- `contracts/modules/*.sol` -- 10 delegatecall modules (all share DegenerusGameStorage)
- `contracts/BurnieCoin.sol`, `contracts/BurnieCoinflip.sol` -- Standalone BURNIE ecosystem
- `contracts/StakedDegenerusStonk.sol`, `contracts/DegenerusStonk.sol` -- sDGNRS/DGNRS tokens
- `contracts/DegenerusVault.sol`, `contracts/WrappedWrappedXRP.sol` -- Vault + WWXRP
- `contracts/DegenerusAdmin.sol` -- Admin + governance
- `contracts/DegenerusAffiliate.sol`, `contracts/DegenerusQuests.sol`, `contracts/DegenerusJackpots.sol` -- Peripherals
- `contracts/libraries/*.sol` -- 5 shared libraries

</canonical_refs>

<code_context>
## Existing Code Insights

### Protocol Architecture Summary
- **DegenerusGame** is the central router. All 10 game modules execute via delegatecall in Game's storage context.
- **Standalone contracts** (BurnieCoin, Coinflip, sDGNRS, DGNRS, Vault, WWXRP, Admin, Affiliate, Quests, Jackpots) have their own storage and are called externally.
- **Libraries** (EntropyLib, BitPackingLib, GameTimeLib, JackpotBucketLib, PriceLookupLib) are stateless internal pure/view.

### Cross-Contract Call Patterns Identified in Unit Audits
- Game -> BurnieCoin (creditFlip, mintForGame, burnForGame)
- Game -> Coinflip (setCoinflipAutoRebuy, settleFlipModeChange, claimCoinflipsForRedemption)
- Game -> sDGNRS (deposit, transferFromPool, transferBetweenPools, burnRemainingPools)
- Game -> DGNRS (pool reads for reward calculation)
- Game -> Vault (deposit, ETH sends)
- Game -> WWXRP (mintPrize)
- Game -> Affiliate (payAffiliate, referPlayer)
- Game -> Quests (rollDailyQuest, awardQuestStreakBonus)
- Game -> Jackpots (recordBafFlip, runBafJackpot)
- Game -> Admin (shutdownVrf)
- BurnieCoin -> Coinflip (auto-claim callback chain)
- BurnieCoin -> Quests (handleMint, handleFlip, etc.)
- BurnieCoin -> Jackpots (recordBafFlip)
- sDGNRS -> DGNRS (cross-contract burn path)
- DGNRS -> sDGNRS (wrapperTransferTo, burnForSdgnrs)
- Vault -> BurnieCoin (vaultMintTo, vaultEscrow)
- Admin -> VRF Coordinator (createSubscription, cancelSubscription, requestRandomWords)
- LootboxModule -> BoonModule (nested delegatecall within same storage context)

### Aggregate Findings Across All 15 Units
- **Total functions analyzed:** 693
- **CRITICAL findings:** 0
- **HIGH findings:** 0
- **MEDIUM findings:** 1 (Unit 7: decBucketOffsetPacked collision)
- **LOW findings:** 2 (Unit 8: strict inequality; Unit 13: missing LINK recovery)
- **INFO findings:** 29
- **BAF cache-overwrite checks:** ALL SAFE across all units
- **Storage layout:** EXACT MATCH across all 10 modules (Unit 1)
- **Taskmaster coverage:** 100% PASS in all 15 units

</code_context>

<specifics>
## Specific Ideas

### Priority Investigation Targets for Integration Sweep

1. **The decBucketOffsetPacked collision (Unit 7 MEDIUM):** Verify whether the EndgameModule -> DecimatorModule -> GameOverModule call chain actually triggers this at the GAMEOVER level. This is a cross-module composition question.

2. **ETH conservation proof:** The most critical deliverable. Trace every msg.value entry point and every ETH exit across all contracts. Verify the protocol cannot lose or create ETH.

3. **Token supply chain of custody:** For each token (BURNIE, DGNRS, sDGNRS, WWXRP), verify the complete mint/burn authority chain. Can any contract mint without proper authorization?

4. **State machine termination:** Can the game reach a state where advanceGame() always reverts? Can rngLocked get stuck permanently? Can prizePoolFrozen get stuck?

5. **Cross-unit callback safety:** The BurnieCoin auto-claim callback (transfer -> coinflip claim -> mint -> transfer resumes) was verified safe within Unit 10. Verify it remains safe when considering all possible Game states that could trigger this chain.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 119 (Final Deliverables):** Master findings aggregation, access control matrix, storage write map, ETH flow map -- formal deliverables that build on this phase's integration analysis.
- Gas optimization recommendations are out of scope for the security audit.

</deferred>

---

*Phase: 118-cross-contract-integration-sweep*
*Context gathered: 2026-03-25*
