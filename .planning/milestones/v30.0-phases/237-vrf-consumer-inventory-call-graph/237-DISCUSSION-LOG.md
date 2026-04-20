# Phase 237: VRF Consumer Inventory & Call Graph — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `237-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 237 — VRF Consumer Inventory & Call Graph
**Areas discussed:** 4 gray areas presented; user chose "Auto-decide using precedents" — Claude applied Phase 230/235 defaults without interactive drill-down.

---

## Selection Mode

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-decide using precedents | Apply prior-milestone defaults (Phase 230/235) to all 4 gray areas, write CONTEXT.md, flag any choice needing user review. | ✓ |
| Pick 1-2 to discuss | Show 4 gray areas; user picks only highest-stakes ones to weigh in on; Claude auto-defaults the rest. | |
| Walk through all 4 | Standard interactive discussion for row granularity, taxonomy edge cases, output shape, plan split. | |

**User's choice:** "Auto-decide using precedents"
**Notes:** User was initially confused — thought they were in a different (DB-related) repo. After reorientation, chose the fastest path trusting v29.0 pattern carryforward. No interactive questioning occurred beyond the selection-mode prompt.

---

## Consumer Row Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Fine-grained (each file:line consumption site = one row) | ~40-80 rows. Matches Phase 235 D-07 "each site is its own row, no equivalence-class shortcuts". | ✓ (auto) |
| Coarse (each logical consumer function = one row) | ~10-20 rows. Collapses repeated call sites; simpler to scan but hides per-site freeze differences. | |

**Auto-applied rationale:** Phase 238/239/240 downstream proofs operate per-site; collapsing would lose resolution. The 17 hash2/keccak sites from commit `c2e5e0a9` each already treated as their own RNG consumer in v29.0 Phase 235.

---

## Path-Family Taxonomy Edge Cases

| Option | Description | Selected |
|--------|-------------|----------|
| KI exceptions INCLUDED with cross-ref column | Affiliate / prevrandao fallback / F-29-04 path / EntropyLib sites appear as inventory rows with subcategory + KI cross-ref. Phase 241 EXC-01..04 uses them as proof subjects. | ✓ (auto) |
| KI exceptions EXCLUDED from inventory | Shorter list, but Phase 241 would have to re-locate exception sites manually. | |
| Prior-artifact cross-check: two-pass (fresh then reconcile) | Plan 01 derives fresh WITHOUT glancing at priors; then reconciles. Every delta gets verdict. | ✓ (auto) |
| Prior-artifact cross-check: fresh-only (never glance) | Pure fresh-eyes; risk of missing a consumer prior audits caught. | |

**Auto-applied rationale:** Inventory must be exhaustive (ROADMAP criterion 1). Excluding KI exceptions would break the "scope definition" invariant downstream phases depend on. Two-pass cross-check preserves fresh-eyes signal while catching misses.

---

## Output Shape & Call-Graph Format

| Option | Description | Selected |
|--------|-------------|----------|
| Single `audit/v30-CONSUMER-INVENTORY.md` with call graphs inline | Matches Phase 230 D-05 single-file catalog pattern. Companion `audit/v30-237-CALLGRAPH-*.md` files only for oversized graphs (~30-line soft threshold). | ✓ (auto) |
| Per-family file split (4-5 files) | Smaller per-file surface; harder for downstream phases to cross-reference. | |
| Tabular columns (grep-friendly, Phase 230 D-08) | No mermaid. Columns: Row ID, File:Line, Function, Path Family, Subcategory, VRF Request Origin, Fulfillment Site, Call Graph Ref, KI Cross-Ref, Notes. | ✓ (auto) |
| Mermaid / tree diagrams | Visual but harder to grep and cite. | |
| Consumer Index at end (Phase 230 D-11) | Maps every v30.0 requirement → inventory row IDs. Saves Phase 238-242 planners lookup work. | ✓ (auto) |
| No Consumer Index (planners derive themselves) | Slightly less upfront work in Phase 237; more work in each downstream plan. | |

**Auto-applied rationale:** Phase 230's consolidated-catalog-with-index pattern shipped cleanly through v29.0 with no downstream-phase rework. No new reason to deviate.

---

## Plan Split

| Option | Description | Selected |
|--------|-------------|----------|
| 1 consolidated plan | Single INV-01+02+03 plan. Phase 230 precedent. Heavier reviewer surface per plan. | |
| 2 plans | Enumeration+classify / call-graph. Reasonable middle ground. | |
| 3 plans (wave 1: 01 enumeration; wave 2: 02 classify, 03 call-graph parallel) | Matches ROADMAP "expected 2-3 plans". 237-02 and 237-03 independent after 237-01 commits. Clean parallelism. | ✓ (auto) |

**Auto-applied rationale:** ROADMAP explicitly targets 2-3 plans; 3-plan split mirrors v29.0 Phase 233/234 "all parallel after enumeration" topology and keeps per-plan reviewer surface small.

---

## Claude's Discretion

- Exact section ordering within `audit/v30-CONSUMER-INVENTORY.md`
- Whether to produce a companion path-family reference card
- Hive-off threshold for oversized call graphs (~30-line soft threshold suggested)
- Row ID format (suggested `INV-237-NNN`)
- Whether plan SUMMARIES preserve raw `grep` commands for reviewer sanity-checks

## Deferred Ideas

- Row-count ceiling/floor enforcement (planner-discretion, not locked)
- Cross-cycle VRF chaining audit (out of INV-03 depth; Phase 238 FWD scope)
- Automated invariant runner against inventory rows (future-milestone, out of v30.0 READ-only scope)

---

*Note: Selection-mode choice was made in response to user clarification after they initially mistook the repo for a DB project. The alternate answer ("just do it plz? I don't know anything about dbs it just needs to be 100% mirrored with on chain state") was acknowledged as intended for a different repo and not applied here.*
