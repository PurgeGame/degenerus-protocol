# Phase 230: Delta Extraction & Scope Map - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce the authoritative v29.0 audit-surface catalog: function-level changelog, cross-module interaction map, and interface-drift catalog covering the 10 contract-touching commits between v27.0 phase-execution completion (`14cb45e1`, 2026-04-12 21:55) and HEAD. Phases 231-235 consume this catalog as their scope definition — no additional discovery required downstream.

Scope is strictly READ-only: no `contracts/` or `test/` writes.

</domain>

<decisions>
## Implementation Decisions

### Diff Boundary
- **D-01:** Baseline is commit `14cb45e1` (v27.0 phase execution complete, 2026-04-12 21:55). HEAD is the current `main` tip including today's commit `20a951df` (earlybird trait-alignment). Range: `14cb45e1..HEAD`.
- **D-02:** Fresh `git diff 14cb45e1..HEAD -- contracts/` is the single authoritative source. No synthesis of intermediate commit messages or prior catalogs.

### Change Significance
- **D-03:** Only execution-affecting changes count as MODIFIED. Comment-only, NatSpec-only, or pure-whitespace-formatting changes are classified UNCHANGED. Carries forward the v25.0 Phase 213 D-03 convention.
- **D-04:** Function-level granularity includes `private` and `internal` functions when they appear in the delta — they are part of the audit surface whenever called by external/public entry points.

### Output Structure
- **D-05:** Single consolidated file `230-01-DELTA-MAP.md` with three sections (changelog / interaction map / interface drift). Matches v28.0 Phase 224 single-file pattern for bounded scope. One plan expected.
- **D-06:** Phase-230 output file is READ-only after commit. If downstream phases (231-235) find a gap, they record a scope-guard deferral (D-227-10 → D-228-09 pattern) rather than editing 230-01 in-place.

### Changelog Section Format
- **D-07:** Organized by owning contract, grouped by contract category (`modules/` → `contracts/*.sol` → `interfaces/`). Each changed function gets: file path, function signature, visibility, change type (NEW / MODIFIED / DELETED), originating commit SHA(s), and a one-line description of what changed semantically.

### Interaction Map Format
- **D-08:** Tabular layout — columns: `Caller Function` | `Callee Function` | `Call Type` (direct / delegatecall / self-call) | `Commit SHA` | `What Changed`. Greppable by downstream phases. No mermaid diagrams.
- **D-09:** Only cross-module call chains are catalogued. Intra-module calls are implicit in the changelog and do not need their own interaction rows.

### Interface Drift Format
- **D-10:** Per-method PASS/FAIL row per signature across `IDegenerusGame`, `IDegenerusQuests`, and `IDegenerusGameModules`. Columns: `Interface` | `Method Signature` | `Implementer Contract` | `Verdict` | `Notes`. Matches v27.0 Phase 220 delegatecall-alignment catalog style.

### Consumer Index
- **D-11:** 230-01 ends with a "Consumer Index" section mapping every downstream v29.0 requirement (DELTA-01..FIND-03, TRNX-01) to the specific sections/rows of 230-01 it will cite. Saves lookup work in phases 231-236.

### Claude's Discretion
- Exact section ordering within 230-01 (changelog first vs interaction map first, etc.) — planner can choose most readable order
- Whether to produce a small companion markdown file listing raw commit↔file matrix for future agent reference
- How deeply to annotate "what changed semantically" per function (one line required; longer notes optional when the change is non-obvious)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope
- `.planning/REQUIREMENTS.md` — DELTA-01, DELTA-02, DELTA-03 + full requirement catalog this phase defines the surface for
- `.planning/ROADMAP.md` — Phase 230 success criteria (4 items)
- `.planning/PROJECT.md` — Current Milestone section lists the 10 in-scope commits

### In-scope commits (baseline `14cb45e1` → HEAD)
- `2471f8e7` phase transition fix — `_unlockRng(day)` removal at `DegenerusGameAdvanceModule:425`
- `52242a10` refactor: explicit entropy passthrough to `processFutureTicketBatch`
- `f20a2b5e` refactor(earlybird): finalize at level transition, unify award call per purchase
- `3ad0f8d3` fix(decimator): key burns by resolution level, consolidate jackpot block
- `104b5d42` feat(jackpot): tag BAF wins with `traitId=420` sentinel
- `67031e7d` feat(decimator): emit `DecimatorClaimed` and `TerminalDecimatorClaimed`
- `858d83e4` feat(game): expose `claimTerminalDecimatorJackpot` passthrough
- `d5284be5` fix(quests): credit fresh ETH wei 1:1 to `mint_ETH` quest
- `e0a7f7bc` feat(boons): expose `boonPacked` mapping for UI reads
- `20a951df` feat(earlybird): align trait roll with coin jackpot, fix queue level

### In-scope files (12)
- `contracts/DegenerusGame.sol`
- `contracts/DegenerusQuests.sol`
- `contracts/BurnieCoin.sol`
- `contracts/modules/DegenerusGameJackpotModule.sol`
- `contracts/modules/DegenerusGameAdvanceModule.sol`
- `contracts/modules/DegenerusGameDecimatorModule.sol`
- `contracts/modules/DegenerusGameMintModule.sol`
- `contracts/modules/DegenerusGameWhaleModule.sol`
- `contracts/storage/DegenerusGameStorage.sol`
- `contracts/interfaces/IDegenerusGame.sol`
- `contracts/interfaces/IDegenerusQuests.sol`
- `contracts/interfaces/IDegenerusGameModules.sol`

### Methodology precedent
- `.planning/milestones/v25.0-phases/213-delta-extraction/213-CONTEXT.md` — prior delta-extraction phase
- `.planning/milestones/v28.0-phases/224-api-route-openapi-alignment/224-CONTEXT.md` — prior single-file catalog pattern
- `.planning/milestones/v27.0-phases/220-delegatecall-target-alignment/` (if archived) — interface drift catalog style reference (per-method PASS/FAIL)

### Prior audit outputs to regression-check against (not Phase 230's job, but Phase 236's)
- `audit/FINDINGS-v25.0.md`
- `audit/FINDINGS-v26.0.md` equivalent delta conclusions in `.planning/milestones/v26.0-phases/`
- `audit/FINDINGS-v27.0.md`
- `audit/KNOWN-ISSUES.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Delta Surface Snapshot (10-commit range)
- 12 contract/interface files touched (see canonical_refs)
- Known substantive changes per commit already enumerated in REQUIREMENTS.md
- Approximate line counts available via `git diff --stat 14cb45e1..HEAD -- contracts/` at plan-phase time

### Git Infrastructure
- All 10 commits present on local `main`; branch is 6 commits ahead of origin (pre-commit state at milestone start)
- `git diff --name-status 14cb45e1..HEAD -- contracts/` → per-file A/M/D status
- `git diff 14cb45e1..HEAD -- contracts/` → full diff for function-level analysis
- Per-commit diffs via `git show {sha} -- contracts/`

### Interface Implementer Map (for drift catalog)
- `IDegenerusGame` → implemented by `DegenerusGame.sol` + used via `IDegenerusGame(address(this))` self-calls inside modules
- `IDegenerusQuests` → implemented by `DegenerusQuests.sol`
- `IDegenerusGameModules` → used for delegatecall selector references (not inherited); verify against `DegenerusGameAdvanceModule`, `DegenerusGameJackpotModule`, `DegenerusGameMintModule`, `DegenerusGameWhaleModule`, `DegenerusGameDecimatorModule` as the module set

### Existing Makefile Gates (already cover parts of the surface, do not duplicate)
- `check-interfaces` — detects interface↔implementation signature drift at compile time
- `check-delegatecall` — verifies delegatecall target alignment across 43 call sites
- `check-raw-selectors` — catches raw selector literals

Phase 230 is a human-readable catalog for downstream audit agents; the Makefile gates are the automated counterpart. The catalog documents WHAT changed, the gates enforce that references stay aligned.

</code_context>

<specifics>
## Specific Ideas

Single consolidated `230-01-DELTA-MAP.md` with four top-level sections in this order:
1. **Function-Level Changelog** (by contract, grouped by category)
2. **Cross-Module Interaction Map** (tabular)
3. **Interface Drift Catalog** (per-method PASS/FAIL)
4. **Consumer Index** (requirement → section-of-this-doc map)

Matches the user's preference for greppable / single-file catalogs established in v28.0 Phase 224.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 230-delta-extraction-scope-map*
*Context gathered: 2026-04-17*
