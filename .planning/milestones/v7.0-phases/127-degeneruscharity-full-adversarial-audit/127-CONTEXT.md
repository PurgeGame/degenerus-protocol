# Phase 127: DegenerusCharity Full Adversarial Audit - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Full adversarial audit of DegenerusCharity.sol (538 lines, 17 functions) using the v5.0-style three-agent system (Mad Genius/Skeptic/Taskmaster). Covers all functions, GNRUS token economics, governance mechanism, game integration hooks, and storage layout. This is the only entirely new contract in v6.0.

</domain>

<decisions>
## Implementation Decisions

### Audit Partitioning
- **D-01:** Split audit by functional domain to match requirement groupings: (1) token operations (totalSupply, balanceOf, transfer, transferFrom, approve, burn, _mint, claimWinnings, claimableWinningsOf), (2) governance (propose, vote, resolveLevel, getProposal, getLevelProposals), (3) game hooks + storage (handleGameOver, gameOver, isVaultOwner + storage layout verification)
- **D-02:** Each domain gets its own plan with Mad Genius attack analysis, Skeptic validation, and Taskmaster coverage check

### Governance Attack Surface Depth
- **D-03:** Full depth — flash-loan vote manipulation, threshold gaming, cross-contract governance interactions, and vote weight conservation all in scope
- **D-04:** Governance analysis must consider sDGNRS as the voting token — check for vote delegation, snapshot timing, and proposal lifecycle exploits

### GNRUS Token Invariant Proofs
- **D-05:** Analytical proof with code-cite verification (consistent with v3.8/v4.0 methodology): soulbound enforcement (transfer/transferFrom must revert), proportional redemption math (burn should return proportional ETH/stETH), and total supply invariants
- **D-06:** Verify redemption math handles edge cases: last burner gets remaining dust, zero-supply state, and rounding precision

### Game Hook Boundary Analysis
- **D-07:** Trace full call paths from game modules (DegenerusGameAdvanceModule, DegenerusGameLootboxModule, DegenerusGameGameOverModule) through resolveLevel and handleGameOver hooks
- **D-08:** Verify CEI pattern on all external calls, check for state inconsistency across module boundaries, and confirm no reentrancy vectors exist through the hook interface

### Storage Layout
- **D-09:** Run `forge inspect DegenerusCharity storage-layout` to verify no slot collisions (per STOR-02)
- **D-10:** Cross-reference storage slots against DegenerusGame's storage to ensure no overlap in delegate-call context (if applicable) or verify Charity is called via regular CALL (not delegatecall)

### Claude's Discretion
- Exact number of plans (2-3 based on natural grouping)
- Whether to combine game hooks + storage into one plan or split them
- How to present the Taskmaster coverage matrix
- Whether trivial view functions (getProposal, getLevelProposals) need full Mad Genius analysis or can be fast-tracked

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Contract Under Audit
- `contracts/DegenerusCharity.sol` — The complete contract (538 lines)

### Phase 126 Deliverables (audit scope definition)
- `.planning/phases/126-delta-extraction-plan-reconciliation/FUNCTION-CATALOG.md` §1 — DegenerusCharity function table (17 entries)
- `.planning/phases/126-delta-extraction-plan-reconciliation/DELTA-INVENTORY.md` — File-level diff inventory and commit trace
- `.planning/phases/126-delta-extraction-plan-reconciliation/PLAN-RECONCILIATION.md` — Plan-vs-reality reconciliation

### Original Design Plans
- `.planning/phases/123-degeneruscharity-contract/123-01-PLAN.md` — GNRUS token + burn redemption plan
- `.planning/phases/123-degeneruscharity-contract/123-02-PLAN.md` — Governance mechanism plan
- `.planning/phases/123-degeneruscharity-contract/123-03-PLAN.md` — Game integration plan
- `.planning/phases/124-game-integration/124-01-PLAN.md` — resolveLevel + handleGameOver hook wiring

### v5.0 Adversarial Audit Methodology
- `.planning/ULTIMATE-AUDIT-DESIGN.md` — Three-agent system design doc
- `.planning/phases/103-game-router-storage-layout/103-01-PLAN.md` — Example unit plan for reference

### Prior Audit Deliverables (cross-reference)
- `.planning/phases/119-final-deliverables/FINDINGS.md` — v5.0 master findings (0 actionable, 29 INFO)
- `.planning/phases/119-final-deliverables/STORAGE-WRITE-MAP.md` — v5.0 storage write map (verify Charity doesn't conflict)

</canonical_refs>

<code_context>
## Existing Code Insights

### Contract Structure
- DegenerusCharity.sol is a standalone contract (not a module, not delegatecall)
- Uses sDGNRS for governance vote weighting
- GNRUS is a soulbound ERC-20 (transfer/transferFrom revert)
- Receives ETH via handleGameOver hook and allows proportional burn redemption

### Established Patterns
- v5.0 audit used per-function Mad Genius/Skeptic analysis with explicit VULNERABLE/INVESTIGATE/SAFE verdicts
- BAF-class cache-overwrite checks on every function that reads then writes storage
- Taskmaster enforces 100% function coverage with no gaps

### Integration Points
- Called by DegenerusGameGameOverModule (handleGameOver)
- Called by DegenerusGameAdvanceModule (resolveLevel — via game router)
- Called by DegenerusGameLootboxModule (resolveLevel — via game router)
- References DegenerusStonk for sDGNRS governance weighting

</code_context>

<specifics>
## Specific Ideas

- Phase 126 reconciliation found 5 DRIFT items — check if any affect DegenerusCharity
- Commit e4833ac7 bundled Phase 123 + partial Phase 124 content — verify nothing was missed
- handleGameOver was removed from Path A of handleGameOverDrain (behavioral drift from Phase 126 reconciliation) — verify this is intentional and safe

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 127-degeneruscharity-full-adversarial-audit*
*Context gathered: 2026-03-26*
