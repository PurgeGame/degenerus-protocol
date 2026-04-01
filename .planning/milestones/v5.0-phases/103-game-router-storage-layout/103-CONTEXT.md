# Phase 103: Game Router + Storage Layout - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGame.sol (the main game router) and DegenerusGameStorage.sol (the shared storage layout inherited by all modules). This phase examines:
- Delegatecall routing correctness (does each external function dispatch to the right module?)
- Access control on all entry points (who can call what?)
- Storage layout alignment (are slots correctly laid out?)
- State-changing functions in Game.sol itself (claimWinnings, setAutoRebuy, setOperatorApproval, etc.)

This phase does NOT re-audit the module internals — those are covered in Phases 104-117. The router's job is to dispatch correctly; the modules' job is to execute correctly.

</domain>

<decisions>
## Implementation Decisions

### Audit Granularity
- **D-01:** Audit the router's own logic (delegatecall dispatch, access control, direct state-changing functions) thoroughly. For delegatecall targets, trace only far enough to verify the dispatch reaches the correct module function — full module internals are audited in their respective phases.
- **D-02:** Functions that live directly in DegenerusGame.sol (not delegated) get full Mad Genius treatment: call tree, storage writes, cache checks, all attack angles.

### Storage Layout Verification
- **D-03:** Use `forge inspect DegenerusGame storage-layout` to get authoritative slot assignments. Cross-reference against the manual slot comments in DegenerusGameStorage.sol.
- **D-04:** Verify all modules that inherit DegenerusGameStorage use the exact same base contract (no rogue storage variables added by any module).

### Report Format
- **D-05:** Follow the ULTIMATE-AUDIT-DESIGN.md format: per-function sections with call tree, storage-write map, cached-local-vs-storage check, attack analysis with verdicts.

### Cross-Module Coherence
- **D-06:** This phase proves the storage layout is correct and that DegenerusGameStorage is the single source of truth. Per-module alignment verification is deferred to Phase 118 (Cross-Contract Integration Sweep).

### Claude's Discretion
- Ordering of function analysis within the report
- Level of detail in delegatecall dispatch traces (enough to prove correctness, no more)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` — Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Core Contracts (audit targets)
- `contracts/DegenerusGame.sol` — Main game router, delegatecall dispatch, direct state-changing functions
- `contracts/storage/DegenerusGameStorage.sol` — Shared storage layout inherited by all modules

### Module Interfaces
- `contracts/interfaces/IDegenerusGameModules.sol` — Module function signatures for delegatecall targets
- `contracts/interfaces/IDegenerusGame.sol` — Game external interface

### Prior Audit Context
- `audit/KNOWN-ISSUES.md` — Known issues from v1.0-v4.4 (do not re-report)

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Architecture
- DegenerusGame.sol is a router that dispatches to 10 modules via delegatecall
- All modules inherit DegenerusGameStorage and execute in Game's storage context
- Storage layout is defined once in DegenerusGameStorage.sol with manual slot comments
- ContractAddresses.sol provides immutable addresses baked at compile time

### Integration Points
- Every external purchase/claim/bet function in Game.sol delegates to a module
- claimWinnings and claimWinningsStethFirst are direct (not delegated)
- rawFulfillRandomWords is the VRF callback entry point
- setOperatorApproval manages the operator permission system

### Storage Structure
- Slots 0-109+ defined in DegenerusGameStorage.sol
- Packed structs and bit fields throughout
- Multiple inheritance: DegenerusGameMintStreakUtils -> DegenerusGameStorage

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system (Taskmaster checklist -> Mad Genius attack -> Skeptic review) drives the workflow.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 103-game-router-storage-layout*
*Context gathered: 2026-03-25*
