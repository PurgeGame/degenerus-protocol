# Phase 300: Admin Path Enumeration Audit (ADMA) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning
**Posture:** AUDIT-ONLY repurpose per `D-43N-AUDIT-ONLY-01` (user-authorization 2026-05-18). Pre-pivot admin-revert-gating contract changes deferred to v44.0 FIX-MILESTONE.

<domain>
## Phase Boundary

Analysis-only phase that produces `.planning/ADMIN-AUDIT.md` enumerating every `onlyOwner` / `onlyAdmin` / role-gated external function across all modules in `contracts/`. For each admin function, cross-references with Phase 298 CAT-03 writer table; marks which functions write participating slots at any non-EXEMPT callsite. For each admin function reaching a participating slot, produces per-admin-function recommendation entry covering: which participating slot(s) reached + recommended gating mechanism (`RngLocked` custom error revert preferred per existing MintModule:1221 / BurnieCoinflip:730 / sStonk:492 convention) + admin-class classification (governance / parameter-update / charity-allowlist / decimator-config / presale-config) + v44.0 FIX-MILESTONE handoff anchor `D-43N-V44-ADMA-NN`. Single AGENT-COMMITTED artifact bundle. **Zero `contracts/` + `test/` mutations** per audit-only posture. Replaces the pre-pivot Admin Lockdown contract-change wave. Requirements ADMA-01..04 (4).

</domain>

<decisions>
## Implementation Decisions

### ADMA Artifact Structure

- **D-300-ADMA-LAYOUT-01:** **Per-admin-function recommendation table** in `.planning/ADMIN-AUDIT.md`. Sections:
  - §0 — Executive Summary (admin function count by role-gate; participating-slot-writer subset count; recommendation count by admin-class)
  - §1 — Complete admin function enumeration (file:line + role-gate annotation + admin-class classification) per ADMA-01
  - §2 — Participating-slot cross-reference table (each admin function → which participating slot(s) it writes at which callsite(s); cross-referenced against Phase 298 RNGLOCK-CATALOG.md §15 per-slot writer enumeration) per ADMA-02
  - §3 — Per-admin-function recommendation table (for each admin function reaching a participating slot: recommended gating mechanism + rationale + admin-class disposition + v44.0 handoff anchor) per ADMA-03 + ADMA-04
  - §4 — v44.0 FIX-MILESTONE consolidated handoff register (deduplicated `D-43N-V44-ADMA-NN` ID list)
  - §5 — Grep completeness gate attestation (independent fresh sweep for `onlyOwner` / `onlyAdmin` / `onlyRole` / role-modifier patterns to confirm enumeration completeness)

  **Why:** §1 + §2 + §3 mirror the Phase 298 catalog's per-consumer + per-slot + verdict-matrix shape but at admin-function granularity. §5 grep gate prevents missed admin functions (same discipline as Phase 298 CAT-06). v44.0 handoff register (§4) is load-bearing for v44 plan-phase ADM-NN sub-phase planning.

### Admin Function Enumeration Scope

- **D-300-ENUM-SCOPE-01:** **All-source `onlyOwner` / `onlyAdmin` / role-gated externals.** Enumeration includes: explicit `onlyOwner` modifier (OZ + custom); `onlyAdmin` modifier; any role-gated modifier (e.g., `onlyRole(GOVERNANCE_ROLE)`); admin-only initializers + setters; admin-callable upgrade functions; `setX(...)` patterns gated by access-control modifier. Excludes: pure-view admin functions (no SSTORE); internal-only admin helpers (no external/public entry point). Scope-boundary: external/public surface of `contracts/` (every Solidity contract under `contracts/`, including modules + libraries + storage + top-level contracts).

### Recommendation Mechanism

- **D-300-GATING-MECHANISM-01:** **`RngLocked` custom error revert preferred** per existing codebase convention. Recommendation column documents the preferred mechanism + cites the existing implementation pattern (MintModule:1221 / BurnieCoinflip:730 / sStonk:492). Alternative tactics (snapshot-anchor, pre-lock reorder, immutable) are NOT typically applicable to admin functions (admin functions are user-callable, not consumer-resolution-path — gating via revert is the natural shape). If a specific admin function has a non-revert tactic that's better (e.g., admin config slot becomes immutable post-launch), the recommendation column documents the exception with rationale.

### Claude's Discretion (planner & executor latitude)

- **D-300-WAVE-SHAPE-01 — Single AGENT-COMMITTED ADMA artifact bundle.** Audit-only posture. Zero `contracts/` + `test/` mutations. Bundle includes `.planning/ADMIN-AUDIT.md` + per-admin-function sub-agent outputs (if parallelized) + planning artifacts.

- **D-300-EXEC-SHAPE-01 — Main-context end-to-end (default) vs parallel sub-agents per module (optional).** ADMA scope is bounded by the admin-function count (likely 20-40 functions across all modules) — main-context end-to-end is feasible. Plan-phase 300 chooses based on Phase 298 CATALOG output size (if Phase 298 produces a large catalog and the grep-cross-reference work is heavy, parallel sub-agents per module may help; otherwise main-context is simpler).

- **D-300-RESEARCH-AGENT-01 — Plan-phase skips research-agent dispatch.** Methodology locked by this CONTEXT.md + REQUIREMENTS ADMA-01..04 + Phase 298 catalog output.

- **D-300-KI-01 — KNOWN-ISSUES.md UNMODIFIED.** Phase 303 TERMINAL handles per `D-43N-KI-01`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 300 Anchors
- `.planning/ROADMAP.md` — Phase 300 entry (ADMA analysis-only repurpose)
- `.planning/REQUIREMENTS.md` — ADMA-01..04 verbatim (post-pivot)
- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md` — Phase 298 CATALOG context; CAT-03 writer-enumeration is the cross-reference input
- `.planning/RNGLOCK-CATALOG.md` (TO BE PRODUCED by Phase 298) — load-bearing input; §15 per-slot writer enumeration drives ADMA §2 cross-reference

### Source Anchors for Admin Function Enumeration (D-300-ENUM-SCOPE-01)
- `contracts/DegenerusAdmin.sol` — primary admin contract; expected enumeration target
- `contracts/DegenerusGame.sol` — top-level admin gates + initializer paths
- `contracts/modules/*.sol` — module-level admin setters (e.g., parameter updates, charity allowlist, decimator config, presale config)
- `contracts/storage/DegenerusGameStorage.sol` — storage layout reference
- `contracts/DegenerusAffiliate.sol` — affiliate admin setters
- `contracts/StakedDegenerusStonk.sol` + `contracts/BurnieCoinflip.sol` + `contracts/BurnieCoin.sol` + `contracts/GNRUS.sol` + `contracts/WrappedWrappedXRP.sol` — admin functions in token contracts

### Existing `RngLocked` Gating Pattern (D-300-GATING-MECHANISM-01)
- `contracts/modules/DegenerusGameMintModule.sol:1221` — `if (cachedJpFlag && rngLockedFlag) {revert RngLocked();}` reference implementation
- `contracts/BurnieCoinflip.sol:730, 780` — `if (degenerusGame.rngLocked()) revert RngLocked();`
- `contracts/StakedDegenerusStonk.sol:492, 513` — `if (game.rngLocked()) revert BurnsBlockedDuringRng();`

### v44.0 FIX-MILESTONE Forward Handoff
- v44.0 plan-phase consumes `.planning/ADMIN-AUDIT.md` §4 consolidated handoff register. One v44.0 sub-phase per per-admin-function recommendation OR per-class grouping per v44 plan-phase discretion.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`RngLocked` custom error pattern** — well-established across 3+ contracts; consistent shape for v44.0 to land additional admin gates
- **Phase 298 CAT-03 writer enumeration** — direct cross-reference input; no re-enumeration needed

### Established Patterns
- **AGENT-COMMITTED audit bundle** — Phase 287 + Phase 296 + Phase 298 precedent
- **Grep-completeness gate (§5)** — Phase 298 CAT-06 precedent (main-context fresh sweep with literal patterns)

### Integration Points
- **Phase 298 → Phase 300**: CAT-03 writer table is ADMA-02 cross-reference input
- **Phase 300 → Phase 301**: ADMA-01 admin function enumeration feeds FUZZ-02 action set (every admin/owner function)
- **Phase 300 → Phase 303**: §3.E ADMA roll-up in FINDINGS-v43.0.md
- **Phase 300 → v44.0**: §4 consolidated handoff register is v44.0 plan-phase input

</code_context>

<specifics>
## Specific Ideas

- **Admin-class classification**: governance / parameter-update / charity-allowlist / decimator-config / presale-config + a "general" catch-all
- **v44.0 handoff anchor ID convention** — `D-43N-V44-ADMA-NN` where NN matches the §3 row number

</specifics>

<deferred>
## Deferred Ideas

- **Cross-admin-class FIX wave grouping at v44.0** — defer to v44.0 plan-phase (admin functions of the same class likely share gating pattern; v44 sub-phase planning may group by class)
- **Regression test scaffold for admin lockdown** — defer to v44.0 plan-phase (Phase 301 FUZZ harness exercises every admin function per FUZZ-02; v44 adds per-admin-function unit tests asserting revert)

</deferred>

---

*Phase: 300-Admin-Path-Enumeration-Audit-ADMA*
*Context gathered: 2026-05-18*
