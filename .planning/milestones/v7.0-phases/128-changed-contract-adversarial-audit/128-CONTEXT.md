# Phase 128: Changed Contract Adversarial Audit - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Three-agent adversarial audit (Mad Genius/Skeptic/Taskmaster) of every modified function across the 11 non-Charity changed contracts (47 functions total), plus BAF-class cache-overwrite checks, storage layout verification, and cross-contract integration seam analysis. DegenerusCharity (17 functions) is excluded — already audited in Phase 127.

</domain>

<decisions>
## Implementation Decisions

### Audit Partitioning
- **D-01:** Partition by originating v6.0 phase into 5 plans:
  - Plan 1: Phase 121 storage/gas fixes (11 functions across AdvanceModule, JackpotModule, LootboxModule, EndgameModule, GameStorage, BitPackingLib)
  - Plan 2: Phase 122 degenerette freeze fix (18 functions in DegeneretteModule)
  - Plan 3: Phase 124 game integration hooks (10 functions across GameOverModule, Stonk, Game, AdvanceModule, JackpotModule, LootboxModule)
  - Plan 4: Unplanned affiliate changes (8 functions in DegenerusAffiliate)
  - Plan 5: Cross-contract integration seams (v6.0 change boundaries only)
- **D-02:** Functions that appear in multiple originating phases (e.g., `advanceGame` touched by both 121 and 124) are audited in the plan where the higher-risk change originated, with cross-reference to the other plan

### DegenerusAffiliate Depth
- **D-03:** Standard three-agent treatment — no enhanced scrutiny beyond what Mad Genius/Skeptic/Taskmaster already provide. The unplanned status does not warrant a different methodology.

### Degenerette Freeze Fix Triage
- **D-04:** Each of the 18 DegeneretteModule functions is triaged before audit: classify as "logic change" or "formatting-only" based on the actual diff
- **D-05:** Logic changes get full Mad Genius attack analysis with Skeptic validation
- **D-06:** Formatting-only functions get fast-track verification: confirm no logic change, mark SAFE, Taskmaster counts as covered

### Cross-Contract Integration
- **D-07:** Dedicated 5th plan for cross-contract seams scoped to v6.0 changes:
  - Fund split arithmetic end-to-end (handleGameOverDrain 33/33/34 split → DegenerusStonk + DegenerusVault + DegenerusCharity)
  - Yield surplus redistribution (23% charity + 23% accumulator in _distributeYieldSurplus → charity receiver)
  - yearSweep timing vs gameOver state (DegenerusStonk.yearSweep interacting with gameOverTimestamp)
  - claimWinningsStethFirst access control change impact (VAULT+SDGNRS → VAULT-only)
  - resolveLevel call path from AdvanceModule/LootboxModule → DegenerusCharity (Phase 127 GOV-01 context)

### Storage Verification
- **D-08:** Run `forge inspect` on all modified contracts to verify storage layout changes (STOR-01)
- **D-09:** Verify lastLootboxRngWord deletion has zero stale references (STOR-03) — grep for all consumers
- **D-10:** Storage verification can be included in whichever plan touches the relevant contract, or consolidated in Plan 5

### Claude's Discretion
- How to handle functions appearing in multiple originating phases (assign to one plan, cross-reference in the other)
- Whether BitPackingLib natspec-only change needs any audit beyond confirming no logic change
- Exact format of triage classification for DegeneretteModule functions
- How to structure the Taskmaster coverage matrix (per-plan or consolidated)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 126 Deliverables (audit scope definition)
- `.planning/phases/126-delta-extraction-plan-reconciliation/FUNCTION-CATALOG.md` — Complete function catalog (65 entries, 64 NEEDS_ADVERSARIAL_REVIEW) — this is the Taskmaster coverage target
- `.planning/phases/126-delta-extraction-plan-reconciliation/DELTA-INVENTORY.md` — File-level diff inventory and commit trace
- `.planning/phases/126-delta-extraction-plan-reconciliation/PLAN-RECONCILIATION.md` — Plan-vs-reality reconciliation (23 MATCH, 5 DRIFT, 1 UNPLANNED)

### Phase 127 Deliverables (sibling audit — cross-reference)
- `audit/unit-charity/01-TOKEN-OPS-AUDIT.md` — DegenerusCharity token ops audit (for cross-contract integration context)
- `audit/unit-charity/02-GOVERNANCE-AUDIT.md` — DegenerusCharity governance audit (GOV-01 finding relevant to Plan 5)
- `audit/unit-charity/03-GAME-HOOKS-STORAGE-AUDIT.md` — Game hooks + storage audit (handleGameOver/resolveLevel call paths)

### Contracts Under Audit
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — 18 functions (Phase 122 freeze fix)
- `contracts/DegenerusAffiliate.sol` — 8 functions (unplanned)
- `contracts/modules/DegenerusGameGameOverModule.sol` — 4 functions (Phase 124)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 4 functions (Phase 121/124)
- `contracts/modules/DegenerusGameJackpotModule.sol` — 4 functions (Phase 121/124)
- `contracts/DegenerusStonk.sol` — 2 functions (Phase 123/124)
- `contracts/DegenerusGame.sol` — 2 functions (Phase 124)
- `contracts/modules/DegenerusGameLootboxModule.sol` — 2 functions (Phase 121)
- `contracts/modules/DegenerusGameEndgameModule.sol` — 1 function (Phase 121)
- `contracts/storage/DegenerusGameStorage.sol` — 1 variable deletion (Phase 121)
- `contracts/libraries/BitPackingLib.sol` — 1 constant natspec-only (Phase 121)

### v5.0 Adversarial Audit Methodology
- `.planning/ULTIMATE-AUDIT-DESIGN.md` — Three-agent system design doc
- `.planning/phases/103-game-router-storage-layout/103-01-PLAN.md` — Example unit plan for reference

### v5.0 Prior Audit Deliverables (cross-reference for regression)
- `.planning/phases/119-final-deliverables/FINDINGS.md` — v5.0 master findings
- `.planning/phases/119-final-deliverables/STORAGE-WRITE-MAP.md` — v5.0 storage write map

### Original v6.0 Design Plans
- `.planning/phases/121-storage-and-gas-fixes/121-CONTEXT.md` — Storage/gas fix design intent
- `.planning/phases/122-degenerette-freeze-fix/122-CONTEXT.md` — Degenerette freeze fix design intent
- `.planning/phases/124-game-integration/124-CONTEXT.md` — Game integration hooks design intent

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 126 FUNCTION-CATALOG.md provides the complete Taskmaster coverage target — no need to re-derive
- Phase 127 audit deliverables provide DegenerusCharity context for cross-contract seam analysis
- v5.0 STORAGE-WRITE-MAP.md provides baseline storage layout for regression checks

### Established Patterns
- v5.0 audit: per-function Mad Genius/Skeptic analysis with explicit VULNERABLE/INVESTIGATE/SAFE verdicts
- BAF-class cache-overwrite checks on every function that reads then writes storage (from v4.4)
- Taskmaster enforces 100% function coverage with no gaps
- Storage layout verification via `forge inspect` (from Phase 127)

### Integration Points
- Phase 128 output feeds into Phase 129 (Consolidated Findings)
- Phase 127 GOV-01 finding (permissionless resolveLevel desync) is relevant context for Plan 5 integration seams
- Plan-vs-reality drift items from Phase 126 PLAN-RECONCILIATION.md should be cross-referenced during audit

</code_context>

<specifics>
## Specific Ideas

- handleGameOver was removed from Path A of handleGameOverDrain (behavioral drift flagged in Phase 126) — Phase 128 must verify this is safe in the GameOverModule plan
- DegenerusAffiliate change (commit a3e2341f) adds "every address is an affiliate" — verify no ETH flow manipulation possible through default referral codes
- Phase 121 advanceBounty was rewritten from upfront computation to payout-time inline — verify no precision/overflow change
- claimWinningsStethFirst access control narrowed from VAULT+SDGNRS to VAULT-only — verify SDGNRS path still works correctly without stETH-first

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 128-changed-contract-adversarial-audit*
*Context gathered: 2026-03-26*
