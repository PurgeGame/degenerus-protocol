# Phase 115: Admin + Governance - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusAdmin.sol -- the central administration and governance contract. This phase examines every state-changing function in the contract using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The contract handles:
- VRF subscription ownership and management (create, fund, cancel, shutdown)
- sDGNRS-holder governance for emergency VRF coordinator swaps (propose/vote/execute)
- LINK token donation handling with reward multipliers (ERC-677 callback)
- LINK/ETH price feed management for reward valuation
- Liquidity management pass-throughs (ETH->stETH swap, stake, lootbox threshold)
- Game-over VRF shutdown (called by GAME contract)

This is a MULTI-PARENT STANDALONE contract -- not a delegatecall module. It has its own storage layout. No delegatecall concerns. Categories B/C/D apply (no Category A).

**SPECIAL NOTE:** This contract was previously audited in v2.1 (Phases 24-25: VRF Governance Audit). Per v5.0 methodology, all prior audit results are ignored. Fresh adversarial analysis is required on every function. The governance system (propose/vote/execute with decaying thresholds) is the highest-risk surface.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. This is a standalone contract, not a delegatecall module. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They get standalone attack sections ONLY if called from multiple parents with different state contexts.

### Governance Deep Dive
- **D-04:** The governance system (propose/vote/execute) is the HIGHEST RISK surface. The Mad Genius must produce exhaustive analysis of: vote weight manipulation via sDGNRS transfers between votes, threshold decay exploitation (50% -> 5% over 7 days), circulating supply snapshot manipulation, proposal spam/griefing, and VRF stall check bypass.
- **D-05:** The _executeSwap internal function gets standalone attack analysis despite being Category C, because it performs the actual VRF coordinator swap -- the most dangerous action in the contract.

### Cross-Contract Interactions
- **D-06:** DegenerusAdmin makes external calls to: VRF Coordinator (subscription management), GAME (wireVrf, updateVrfCoordinatorAndSub, adminSwapEthForStEth, adminStakeEthForStEth, setLootboxRngThreshold), LINK token (transferAndCall, transfer, balanceOf), Coin contract (creditLinkReward), Vault (isVaultOwner), sDGNRS (totalSupply, balanceOf), and Chainlink price feed (latestRoundData, decimals). Each external call site must be traced for state coherence.
- **D-07:** Since DegenerusAdmin has its OWN storage (not delegatecall), cached-local-vs-storage checks focus on: (1) local variables cached before external calls that could be stale when used after the call returns, and (2) storage reads that could be stale if an external call modifies state in another contract that this contract later reads again.

### Fresh Eyes Requirement
- **D-08:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v2.1 (Phases 24-25). The entire point of v5.0 is catching bugs that survived 24 prior milestones.
- **D-09:** Known issues from KNOWN-ISSUES.md (VRF swap governance design, gameover prevrandao fallback) are design decisions, not re-reportable bugs. But the Mad Genius must verify the implementation matches the stated design.

### Report Format
- **D-10:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering as in prior phases)
- Level of detail in external call traces (enough to verify state coherence, no more)
- Whether to combine closely related pass-through functions (swapGameEthForStEth, stakeGameEthToStEth, setLootboxRngThreshold) into a single section or keep separate

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contract
- `contracts/DegenerusAdmin.sol` -- The audit target (803 lines, ~20 functions)

### External Interfaces Called
- `contracts/ContractAddresses.sol` -- Precomputed addresses for all protocol contracts
- `contracts/interfaces/IDegenerusGameModules.sol` -- Game module function signatures (for tracing wireVrf, updateVrfCoordinatorAndSub calls)

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/104-day-advancement-vrf/104-CONTEXT.md` -- Phase 104 context (Category B/C/D pattern, report format)
- `audit/unit-12/COVERAGE-CHECKLIST.md` -- Phase 114 Taskmaster output (format reference)
- `audit/unit-12/ATTACK-REPORT.md` -- Phase 114 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from contract analysis)
- `constructor()` (L331-349) -- Deploys VRF subscription, wires Game contract
- `setLinkEthPriceFeed(feed)` (L357-368) -- Owner-only price feed config
- `swapGameEthForStEth()` (L374-377) -- Owner-only ETH->stETH pass-through
- `stakeGameEthToStEth(amount)` (L379-381) -- Owner-only staking pass-through
- `setLootboxRngThreshold(newThreshold)` (L383-385) -- Owner-only threshold pass-through
- `propose(newCoordinator, newKeyHash)` (L398-445) -- VRF swap proposal creation (Admin or Community path)
- `vote(proposalId, approve)` (L452-517) -- sDGNRS-weighted voting with stall re-check
- `circulatingSupply()` (L520-524) -- View: circulating sDGNRS (excludes sDGNRS contract + DGNRS wrapper)
- `threshold(proposalId)` (L530-539) -- View: decaying approval threshold
- `canExecute(proposalId)` (L544-556) -- View: execution readiness check
- `_executeSwap(proposalId)` (L566-627) -- Internal: actual VRF coordinator swap
- `_voidAllActive(exceptId)` (L631-643) -- Internal: kill all active proposals except the executed one
- `shutdownVrf()` (L651-674) -- Game-only: cancel subscription and sweep LINK on game-over
- `onTokenTransfer(from, amount, data)` (L683-727) -- ERC-677 callback: LINK donation handling
- `linkAmountToEth(amount)` (L734-755) -- External view: LINK->ETH conversion via price feed
- `_linkRewardMultiplier(subBal)` (L758-774) -- Private pure: reward multiplier based on sub balance
- `_feedHealthy(feed)` (L777-802) -- Private view: price feed health check

### Contract Architecture
- Standalone contract with own storage (NOT a delegatecall module)
- Ownership via DGVE token majority (vault.isVaultOwner check)
- Governance: propose -> vote -> execute pattern for VRF coordinator swaps
- Two proposal paths: Admin (DGVE owner, 20h stall) and Community (0.5% sDGNRS, 7d stall)
- Decaying threshold: 50% -> 40% -> 30% -> 20% -> 10% -> 5% -> expired over 7 days
- ERC-677 callback for LINK donations with multiplier-based BURNIE rewards

### Integration Points
- constructor() calls vrfCoordinator.createSubscription, addConsumer, gameAdmin.wireVrf
- _executeSwap() calls old coordinator cancelSubscription, new coordinator createSubscription/addConsumer, gameAdmin.updateVrfCoordinatorAndSub, linkToken.transferAndCall
- shutdownVrf() calls coordinator.cancelSubscription, linkToken.transfer
- onTokenTransfer() calls linkToken.transferAndCall, this.linkAmountToEth, gameAdmin.purchaseInfo, coinLinkReward.creditLinkReward
- setLinkEthPriceFeed() calls IAggregatorV3.decimals
- swapGameEthForStEth() calls gameAdmin.adminSwapEthForStEth
- stakeGameEthToStEth() calls gameAdmin.adminStakeEthForStEth
- setLootboxRngThreshold() calls gameAdmin.setLootboxRngThreshold
- propose() calls gameAdmin.lastVrfProcessed, gameAdmin.gameOver, vault.isVaultOwner, sDGNRS.balanceOf, circulatingSupply
- vote() calls gameAdmin.lastVrfProcessed, sDGNRS.balanceOf, threshold

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system (Taskmaster checklist -> Mad Genius attack -> Skeptic review) drives the workflow, same as all prior unit phases.

The GOVERNANCE SYSTEM is the main high-risk surface. Key attack angles to investigate:
1. Can sDGNRS holders manipulate vote weights by transferring tokens between votes?
2. Can an attacker exploit the decaying threshold to pass a proposal with minimal support?
3. Can circulatingSupply() be manipulated to skew thresholds?
4. Can an attacker create proposals that cannot be killed?
5. Can the _voidAllActive loop be griefed (gas exhaustion with many proposals)?
6. Is the stall re-check in vote() sufficient to prevent governance during normal VRF operation?
7. Can _executeSwap be front-run or sandwich attacked?

</specifics>

<deferred>
## Deferred Ideas

- **Phase 118 coordination**: Cross-contract integration sweep should verify that gameAdmin.updateVrfCoordinatorAndSub correctly updates Game storage when called from DegenerusAdmin governance execution.
- **Phase 112 coordination**: BURNIE token creditLinkReward called from onTokenTransfer -- verify the Coin contract correctly handles the credited amount (audited in Phase 112).

</deferred>

---

*Phase: 115-admin-governance*
*Context gathered: 2026-03-25*
