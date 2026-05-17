# Phase 294: Deity-Pass Gold Nerf (DPNERF) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-17
**Phase:** 294-deity-pass-gold-nerf-dpnerf
**Areas discussed:** Caller-uniformity disposition, Plan-artifact sidecar shape, Research at plan-phase, NatSpec wording for the gold branch

---

## Caller-Uniformity Disposition

The roadmap names only "ETH + BURNIE coin jackpot paths" but `_randTraitTicket` has 4 actual callsites (L698 early-bird lootbox + L988 ticket distribution helper + L1296 ETH daily + L1399 ETH trait-winner resolution). The function-body change applies to all callers by construction. REQUIREMENTS.md DPNERF-03 framing "deity earns less total EV across all 8 colors" implicitly requires uniform application.

| Option | Description | Selected |
|--------|-------------|----------|
| Uniform — all 4 callsites nerfed | Lock D-42N-PATH-COVERAGE-01 as ALL-CALLER scope. CONTEXT.md enumerates all 4 callsites. Phase 296 SWEEP red-teams all 4 paths; Phase 297 §3.A/B/C audit attests all 4. By-construction caller-uniform; matches REQUIREMENTS.md DPNERF-03 "total EV across all 8 colors" framing. | ✓ |
| Carve out the early-bird lootbox path | Keep gold-tier on the v41 max(len/50, 2) floor for the early-bird lootbox path (L698) only. Requires a callsite flag or path-discrimination logic inside _randTraitTicket. Violates roadmap's "no callsite flag or path-discrimination logic" wording. | |
| Surface for explicit per-callsite review | Don't lock yet. Walk through each callsite (L698, L988, L1296, L1399) one at a time and decide per-path whether the nerf applies. | |

**User's choice:** Uniform — all 4 callsites nerfed
**Notes:** Locked as **D-294-CALLER-UNIFORM-01**. Extends the roadmap-named D-42N-PATH-COVERAGE-01 from "ETH + BURNIE" to "ALL-4-CALLER" scope. Phase 296 SWEEP hypothesis surface expanded from "ETH vs BURNIE differential-behavior" to "all-4-callsite uniformity + incentive-shift across early-bird-lootbox + carryover-ticket-distribution paths." Phase 297 §3.A delta-surface table cites all 4 callsites under the DPNERF row.

---

## Plan-Artifact Sidecar Shape

Phase 290 (MINTCLN) + Phase 292 (HRROLL) sister contract phases each shipped 3 sidecars (PLAN + DESIGN-INTENT-TRACE + MEASUREMENT). DPNERF is mechanically simpler (single-branch add vs full-function-replace), raising the question of whether the 3-sidecar pattern is overkill.

| Option | Description | Selected |
|--------|-------------|----------|
| Full 3-sidecar pattern | Match Phase 290/292 precedent: PLAN + DESIGN-INTENT-TRACE (DPNERF-06 4-section trace) + MEASUREMENT (storage byte-identity + ABI byte-identity + theoretical bytecode delta + all-4-callsite enumeration). All AGENT-COMMITTED pre-patch per feedback_design_intent_before_deletion.md. | ✓ |
| PLAN + DESIGN-INTENT-TRACE only | Skip MEASUREMENT.md; fold byte-identity attestation + callsite enumeration + bytecode delta inline into PLAN.md §2. | |
| PLAN only | Collapse design-intent + measurement into PLAN.md sections. | |

**User's choice:** Full 3-sidecar pattern
**Notes:** Locked as **D-294-SIDECARS-01**. Sidecar symmetry across the 3 v42.0 contract surface phases (290/292/294) is the coherence anchor; produces clean artifact citations for Phase 296 SWEEP adversarial pass + Phase 297 §3.A delta-surface table.

---

## Research at Plan-Phase

`feedback_skip_research_test_phases.md` says skip research for obvious/mechanical phases. Phase 294 has fully-specified scope (exact file path + line range + 3 decision anchors locked + 6 requirements + all 4 callsites enumerated in this discussion). Research adds latency with no value.

| Option | Description | Selected |
|--------|-------------|----------|
| Skip research — plan directly | Per feedback_skip_research_test_phases.md. Run /gsd:plan-phase 294 --skip-research. | ✓ |
| Run full research | Match Phase 290 + 292 sister contract phases (both ran research). Researcher reads contracts/, identifies caller paths, attests storage/ABI invariants, produces 294-01-RESEARCH.md. | |

**User's choice:** Skip research — plan directly
**Notes:** Locked as **D-294-RESEARCH-SKIP-01**. The codebase-scout work done in this CONTEXT discussion (4-callsite enumeration + upstream trace + gold-color semantic confirmation + idiom precedent at L1105) covers every input the planner would otherwise commission research to gather.

---

## NatSpec Wording for the Gold Branch

Current comment at `DegenerusGameJackpotModule.sol:1721-1723` describes only the v41 common-tier path ("floor(2% of bucket tickets), minimum 2"). After DPNERF this is stale. Per `feedback_no_history_in_comments.md`, the new comment must describe what IS (both branches) with no "previously/v41/used to" wording.

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit two-tier description | Rewrite the block to describe both tiers explicitly: gold tier flat 1 + common tier floor(2%) min 2. Clearest "what IS" framing; both branches self-documenting. | ✓ |
| Inline single-line gold branch | Keep the existing comment block + add a tight single-line comment above the gold branch. Compact but the block above still reads as if only the common-tier path exists. | |
| Defer wording to planner | Lock the constraint (feedback_no_history_in_comments.md) but let the planner pick exact prose at 294-01-PLAN.md. | |

**User's choice:** Explicit two-tier description
**Notes:** Locked as **D-294-NATSPEC-01**. Exact 5-line target shape:
```
// Virtual deity entries (if a deity exists for this symbol):
//   Gold tier (color == 7): flat 1 virtual entry.
//   Common tier (color in [0..6]): floor(2% of bucket), minimum 2.
// traitId layout: (quadrant << 6) | (color << 3) | symIdx
// fullSymId = quadrant * 8 + symIdx
```
No "previously/v41/was max(len/50,2)" wording. No D-42N-GOLD-FLOOR-01 / DPNERF / Phase 294 citation in the source comment. Planner records the exact shape in 294-01-PLAN.md; executor implements verbatim.

---

## Claude's Discretion

The following gray areas were considered but resolved at planner-discretion using established precedent (not surfaced to user):

- **Color-extraction idiom** — inline `((trait >> 3) & 7) == 7` matching the existing precedent at `DegenerusGameJackpotModule.sol:1105` in `_pickSoloQuadrant`. No `GOLD_COLOR = 7` named constant (rejected per `feedback_frozen_contracts_no_future_proofing.md`); no `uint8 color = (trait >> 3) & 7;` local variable cache (rejected per branch-fires-once invocation pattern).
- **Branch shape** — `if (((trait >> 3) & 7) == 7) { virtualCount = 1; } else { virtualCount = len / 50; if (virtualCount < 2) virtualCount = 2; }` inside the existing `if (deity != address(0))` block at L1729 (gold-tier nerf only applies when a deity exists, matching v41 conditional shape).
- **Bytecode-delta methodology** — theoretical-first attestation per `feedback_gas_worst_case.md` (analytical derivation in `294-01-MEASUREMENT.md` §5; expected ~10-30 byte addition); no empirical-second attestation needed (no gas-regression test in Phase 295 TST-DPNERF-01..05 scope; runtime cost is negligible).
- **`_pickSoloQuadrant` adjacency** — UNRELATED gold-tier code path at L1080-1130; byte-identical post-patch attestation in `294-01-MEASUREMENT.md`.
- **`_randTraitTicket` function-level docstring** — keep existing `/// @dev Selects random winners from a trait's ticket pool, returning both addresses and indices.` at L1706 unchanged (internal-behavior-only change).
- **Decision-anchor citation in source comments** — NONE per `feedback_no_history_in_comments.md`.
- **`KNOWN-ISSUES.md` posture** — UNMODIFIED at Phase 294 (mirrors D-281-KI-01 + D-291-KI-01 + D-293-STALE-VIEW-01 disposition for surface-mutation phases).
- **Commit message format** — `feat(294): deity-pass gold nerf via flat-1 virtualCount on color==7 [DPNERF-01..06]`.

## Deferred Ideas

- Common-tier compensation logic (excluded per D-42N-DEITY-EV-01; not a Phase 294/296/297 candidate)
- Deity-pass holder economic adjustment if SWEEP surfaces destabilization (F-42-NN candidate at Phase 297; default zero-finding outcome assumed)
- `GOLD_COLOR = 7` named constant extraction (v43+ if proliferation justifies; not v42.0 candidate)
- `color` local-variable cache (v43+ if `_randTraitTicket` evolves to need multiple color-derived branches)
- `_pickSoloQuadrant` refactor (orthogonal v43+ candidate)
- Empirical gas/bytecode regression test (not in Phase 295 TST-DPNERF scope; v43+ if future deity-virtual-count change has non-negligible gas impact)
- Phase 296 SWEEP hypothesis expansion beyond D-294-CALLER-UNIFORM-01 (SWEEP-discretion at Phase 296 execution; default zero-widening assumed)
- `_runEarlyBirdLootboxJackpot` independent regression in TST-DPNERF (not in Phase 295 scope; SWEEP attests behavior at Phase 296; v43+ test-maintenance bundle candidate)
