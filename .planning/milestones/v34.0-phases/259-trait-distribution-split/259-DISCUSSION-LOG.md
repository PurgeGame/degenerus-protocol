# Phase 259: Trait Distribution Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 259-trait-distribution-split
**Areas discussed:** Test harness location & scope, Comment/natspec terminology, TRAIT-04 grep verification command, Test file structure

---

## Test Harness Location & Scope

| Option | Description | Selected |
|--------|-------------|----------|
| TraitUtilsTester exposes all 3 | `contracts/test/TraitUtilsTester.sol` exposes `weightedColorBucket(uint32)`, `traitFromWord(uint64)`, and `packedTraitsFromSeed(uint256)` as `external pure` passthroughs. Matches `PriceLookupTester` pattern; all three needed for TRAIT-05/06 coverage. | ✓ |
| Expose only the 2 changed functions | Harness exposes only `weightedColorBucket` + `traitFromWord`; `packedTraitsFromSeed` exercised indirectly via existing `DegeneretteFreezeResolution.t.sol` fuzz. | |
| No new harness — reuse fuzz t.sol | Skip Hardhat boundary tests; put unit assertions inside a Foundry `.t.sol`. (Conflicts with success criterion #4.) | |

**User's choice:** TraitUtilsTester exposes all 3
**Notes:** Aligns with the existing `contracts/test/PriceLookupTester.sol` pattern already consumed by `test/validation/PaperParity.test.js`. Fold all three functions into a single harness contract so the new Hardhat test file has direct access without secondary fixtures.

---

## Comment / Natspec Terminology

| Option | Description | Selected |
|--------|-------------|----------|
| Switch fully to color/symbol | Rewrite top-of-file comment block, natspec, and local var names (`category` → `color`, `sub` → `symbol`) to match REQUIREMENTS.md/ROADMAP language; rewrite the WEIGHTED DISTRIBUTION ASCII table to the new heavy-tail percentages. | ✓ |
| Color/symbol in code, keep ASCII block neutral | Use color/symbol in natspec + variables, but keep header ASCII block abstract (e.g., `tier`/`sub-tier`) decoupled from product terminology. | |
| Keep category/sub-bucket terminology | Update probabilities/thresholds only; preserve legacy vocabulary. Risks comment↔spec drift. | |

**User's choice:** Switch fully to color/symbol
**Notes:** Per `feedback_no_history_in_comments.md`, comments describe what IS — the new distribution justifies new terms. No legacy bucket table preserved as "previously was". Function `weightedBucket` is structurally removed; no commented-out body.

---

## TRAIT-04 Grep Verification Command

| Option | Description | Selected |
|--------|-------------|----------|
| Word-boundary grep | `grep -rwn 'weightedBucket' contracts/` — `-w` prevents `weightedColorBucket` false-match. Single command, semantically precise. | ✓ |
| Filtered grep | `grep -rn 'weightedBucket' contracts/ \| grep -v 'weightedColorBucket'` — explicit two-stage filter. | |
| Both as belt-and-suspenders | Run both forms in CI/verification; both must return zero hits. | |

**User's choice:** Word-boundary grep
**Notes:** Locked verification command for TRAIT-04 acceptance. Must return zero hits at phase close.

---

## Test File Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Single DegenerusTraitUtils.test.js | `test/unit/DegenerusTraitUtils.test.js` with three `describe` blocks: `weightedColorBucket` boundaries (16 cases), `traitFromWord` composition (TRAIT-06 isolated-bit), `packedTraitsFromSeed` byte layout. Matches per-contract convention. | ✓ |
| Split per function | Three separate files: `WeightedColorBucket.test.js`, `TraitFromWord.test.js`, `PackedTraitsFromSeed.test.js`. Cleaner isolation but breaks convention. | |
| Boundary tests in unit, layout test in integration | Boundary tests in `test/unit/DegenerusTraitUtils.test.js`; `packedTraitsFromSeed` byte-layout assertion folded into an existing integration test. | |

**User's choice:** Single DegenerusTraitUtils.test.js
**Notes:** Aligns with existing per-contract test convention in `test/unit/`. Existing Foundry fuzz `test/fuzz/DegeneretteFreezeResolution.t.sol:354` is the implicit byte-layout regression and runs unchanged at phase close.

---

## Claude's Discretion

- Math used to construct boundary `rnd` inputs that map cleanly to the requested `scaled` values — mechanical, planner picks the form.
- Exact natspec doc-comment prose after the terminology switch — semantics locked, prose incidental.
- Whether to preserve the file-header ASCII border style (`+==...==+`); planner default is "preserve for visual consistency."

## Deferred Ideas

- `_pickSoloQuadrant` helper + 4-site ETH-distribution injection — Phase 260.
- 1M-sample empirical frequency + chi-squared independence + symbol uniformity tests (`test/stat/`) — Phase 261.
- Pack-feel CIs over 100K 10-ticket packs — Phase 261.
- Cross-surface verification (Hero override, deity-pass, Degenerette, 8 non-injection bonus-jackpot sites) — Phase 261.
- Gas regression vs v33.0 baseline (`weightedColorBucket` ±100 gas, top-level entry deltas < 2000 gas) — Phase 261. `feedback_gas_worst_case.md` applies — theoretical worst case derived FIRST.
- Delta-audit findings consolidation (`audit/FINDINGS-v34.0.md`) — Phase 262.
