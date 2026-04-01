# Phase 126: Delta Extraction + Plan Reconciliation - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Map every v6.0 contract change (12 files, +1026/-198 lines since v5.0), catalog all changed functions, and reconcile against v6.0 phase plans (120-125) to produce a precise audit scope for Phases 127-128. Flag any commit that doesn't trace to a v6.0 phase plan.

</domain>

<decisions>
## Implementation Decisions

### Drift Classification
- **D-01:** Binary classification per plan item: MATCH (plan intent matches final contract state) or DRIFT (discrepancy between plan and reality)
- **D-02:** Every DRIFT item gets a review flag: NEEDS_ADVERSARIAL_REVIEW (yes/no) indicating whether Phase 128 should specifically audit it
- **D-03:** No severity scaling — the adversarial audit (Phases 127/128) determines actual severity of any issues found

### Unplanned Changes
- **D-04:** DegenerusAffiliate change (commit a3e2341f "add default referral codes — every address is an affiliate") is intentional but was done outside the v6.0 phase structure. Document as "unplanned but intentional" with full function-level catalog for Phase 128 adversarial review
- **D-05:** Any other commits not traceable to phases 120-125 are flagged similarly

### Output Format
- **D-06:** Per-contract function checklist as primary deliverable — each changed/new/deleted function listed with its change type and originating v6.0 phase (or "unplanned")
- **D-07:** Per-plan reconciliation table as secondary deliverable — each v6.0 plan item gets a MATCH/DRIFT verdict with the review flag

### Claude's Discretion
- Exact format and layout of tables/checklists
- How to handle trivial NatSpec-only changes (likely INFO, no adversarial review needed)
- Whether to include test-only changes in the catalog (out of scope for adversarial audit but worth noting)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### v6.0 Phase Plans (reconciliation targets)
- `.planning/phases/120-test-suite-cleanup/120-CONTEXT.md` — Test suite fix scope
- `.planning/phases/121-storage-and-gas-fixes/121-CONTEXT.md` — Storage/gas fix scope
- `.planning/phases/122-degenerette-freeze-fix/122-CONTEXT.md` — Degenerette freeze fix scope
- `.planning/phases/123-degeneruscharity-contract/123-CONTEXT.md` — DegenerusCharity contract scope
- `.planning/phases/124-game-integration/124-CONTEXT.md` — Game integration hooks scope
- `.planning/phases/125-test-suite-pruning/125-CONTEXT.md` — Test pruning scope

### v6.0 Phase Plan Files (all plans within each phase)
- `.planning/phases/120-test-suite-cleanup/120-01-PLAN.md`, `120-02-PLAN.md`
- `.planning/phases/121-storage-and-gas-fixes/121-01-PLAN.md`, `121-02-PLAN.md`, `121-03-PLAN.md`
- `.planning/phases/122-degenerette-freeze-fix/122-01-PLAN.md`
- `.planning/phases/123-degeneruscharity-contract/123-01-PLAN.md`, `123-02-PLAN.md`, `123-03-PLAN.md`
- `.planning/phases/124-game-integration/124-01-PLAN.md`
- `.planning/phases/125-test-suite-pruning/125-01-PLAN.md`, `125-02-PLAN.md`

### v6.0 Requirements (what was supposed to be built)
- `.planning/REQUIREMENTS.md` — v6.0 requirements with traceability (now overwritten with v7.0, but git history has v6.0 version)

### Git Reference
- Tag `v5.0` is the baseline — all diffs are `v5.0..HEAD -- contracts/`
- Commit `a3e2341f` is the unplanned DegenerusAffiliate change

</canonical_refs>

<code_context>
## Existing Code Insights

### Changed Contracts (12 files, excluding mocks + ContractAddresses)
- `contracts/DegenerusCharity.sol` — 538 new lines (entirely new contract)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — 296 insertions (Phase 122 fix)
- `contracts/DegenerusAffiliate.sol` — 76 changes (unplanned, intentional)
- `contracts/modules/DegenerusGameGameOverModule.sol` — 74 changes (Phase 124 hooks)
- `contracts/DegenerusStonk.sol` — 54 insertions (Phase 123/124 integration)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — 35 changes (Phase 121/124 fixes)
- `contracts/modules/DegenerusGameJackpotModule.sol` — 30 changes (Phase 121 fixes)
- `contracts/modules/DegenerusGameLootboxModule.sol` — 29 changes (Phase 121/124 hooks)
- `contracts/DegenerusGame.sol` — 13 changes (Phase 124 integration)
- `contracts/modules/DegenerusGameEndgameModule.sol` — 5 changes (Phase 121 fix)
- `contracts/storage/DegenerusGameStorage.sol` — 5 deletions (Phase 121 lastLootboxRngWord)
- `contracts/libraries/BitPackingLib.sol` — 2 changes (Phase 121 NatSpec)

### Established Patterns
- v5.0 audit used per-contract function checklists with category tags (A/B/C/D)
- Prior delta audits (v3.2, v3.8) used git diff with line-level citation
- v4.0 used cross-reference tables against prior audit claims

### Integration Points
- Phase 126 output feeds directly into Phase 127 (DegenerusCharity audit scope) and Phase 128 (changed contract audit scope)
- The function checklist becomes the Taskmaster coverage target in Phases 127/128

</code_context>

<specifics>
## Specific Ideas

- User observed "commit weirdness" during v6.0 — specifically wants plan-vs-reality verification, not just security audit
- DegenerusAffiliate change is intentional: adds default referral codes so every address is an affiliate without signup

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 126-delta-extraction-plan-reconciliation*
*Context gathered: 2026-03-26*
