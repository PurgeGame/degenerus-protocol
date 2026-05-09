# Phase 260: Gold Solo Priority Injection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 260-gold-solo-priority-injection
**Areas discussed:** Helper visibility & test access, Tie-break uniformity for goldCount=3, effectiveEntropy substitution shape

---

## Gray-Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Helper visibility & test access | SOLO-01 spec'd `private pure` but SOLO-08 needs unit tests; resolve via internal-pure + tester wrapper, library extraction, or JS reimplementation. | ✓ |
| Tie-break uniformity for goldCount=3 | Spec'd formula `((entropy >> 4) & 3) % goldCount` is biased 50/25/25 for goldCount=3; fix or accept. | ✓ |
| Plan slicing | 1, 2, or 3 plans for Phase 260 atomicity. | |
| effectiveEntropy substitution shape | Local variable per site vs inline at each library call vs second helper. | ✓ |

**User's choice:** Three areas selected (visibility, uniformity, substitution shape). Plan slicing deferred to the planner per the Phase 259 mechanical-phase precedent (D-12).

---

## Helper visibility & test access

### Q1 — How do we resolve the private-pure-vs-testability conflict?

| Option | Description | Selected |
|--------|-------------|----------|
| Internal pure + module-side tester | Change SOLO-01 to `internal pure`; add `contracts/test/JackpotSoloTester.sol` inheriting the module and exposing `pickSoloQuadrant` as `external pure`. Smallest spec deviation; tests hit real production bytes. | ✓ |
| Extract to JackpotSoloLib library | Move helper into a new library `contracts/libraries/JackpotSoloLib.sol`. Tester wraps the library exactly like `TraitUtilsTester` wraps `DegenerusTraitUtils`. SOLO-07 only locks `JackpotBucketLib`, so a NEW library is technically allowed — but adds an architectural unit. | |
| Keep private pure, reimplement formula in JS | Strict spec compliance; tests assert the formula in JS, not the actual Solidity bytes. Loses fidelity. | |

**User's choice:** Internal pure + module-side tester (Recommended).
**Notes:** Captured as **D-01** (visibility change) and **D-02** (tester contract).

### Q2 — Where does the test wrapper live?

| Option | Description | Selected |
|--------|-------------|----------|
| Inherit the full module | `JackpotSoloTester is DegenerusGameJackpotModule` with one `external pure` passthrough. No constructor in chain → deploys cleanly. | ✓ |
| Extract to abstract base + inherit base | New abstract base contract holds `_pickSoloQuadrant`; module inherits it; tester inherits ONLY the base. Smaller tester surface but adds an abstract base for one function. | |

**User's choice:** Inherit the full module (Recommended).
**Notes:** Verified inheritance chain (`DegenerusGameStorage` → `DegenerusGamePayoutUtils` → `DegenerusGameJackpotModule`) has no constructor anywhere; tester deploys with default zero-arg ctor. Captured as **D-02 / D-03**.

---

## Tie-break uniformity for goldCount=3

### Q1 — How do we resolve the goldCount=3 modulo bias?

| Option | Description | Selected |
|--------|-------------|----------|
| Use full upper bits: `(entropy >> 4) % goldCount` | Drops the `& 3` mask; `entropy >> 4` is 252 bits; bias < 2^-250 per goldCount. Tiny gas delta. | ✓ |
| Use 16-bit window: `((entropy >> 4) & 0xFFFF) % goldCount` | 65536 mod 3 = 21845 r 1; max bias ~1.5e-5. More conservative. | |
| Accept the 50/25/25 bias for 3-gold | Document as accepted-design bias (rare — ~0.5% of multi-gold draws); re-spec SOLO-08(c) and STAT-04 to skip the 3-gold case. | |
| Use 8-bit window: `((entropy >> 4) & 0xFF) % goldCount` | 256 mod 3 = 85 r 1; max bias ~6e-3. Compromise option. | |

**User's choice:** Use full upper bits (Recommended).
**Notes:** Captured as **D-04** (formula), **D-05** (SOLO-08(d) wording), **D-06** (bias bound). Spec amendments tracked in D-13 / D-14 for the eventual REQUIREMENTS.md edit.

---

## effectiveEntropy substitution shape

### Q1 — How should the effectiveEntropy substitution be expressed at each site?

| Option | Description | Selected |
|--------|-------------|----------|
| Local `effectiveEntropy` once per site | Compute `soloQuadrant` then `effectiveEntropy` at the top of each site; pass `effectiveEntropy` everywhere downstream. Single source of truth; SOLO-09 split-mode parity is line-for-line obvious. | ✓ |
| Inline at each library call | Pass `(entropy & ~uint256(3)) | uint256((3 - _pickSoloQuadrant(...)) & 3)` directly to each `JackpotBucketLib` call. Same gas; reviewer must manually verify all 4-6 sub-expressions per site match. | |
| Helper `_effectiveEntropy(traitIds, entropy)` wrapping both | Add a second `internal pure` helper that wraps `_pickSoloQuadrant` plus the substitution. One-liner per site but expands the SOLO-08 test surface. | |

**User's choice:** Local `effectiveEntropy` once per site (Recommended).
**Notes:** Captured as **D-07** (shape), **D-08** (canonical block), **D-09** (substitution-correctness reasoning for `_processDailyEth` / `_executeJackpot`).

---

## Done check

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context | Write CONTEXT.md and DISCUSSION-LOG.md with the decisions captured. | ✓ |
| Discuss plan slicing now | Lock 1/2/3-plan slicing in CONTEXT.md. | |
| Explore another gray area | SOLO-09 fixture design, helper file placement, gas-budget pre-check, REQUIREMENTS.md edit timing. | |

**User's choice:** I'm ready for context.

---

## Claude's Discretion

- Local-variable naming inside the 4 site blocks beyond the canonical `traitIds` / `entropy` / `soloQuadrant` / `effectiveEntropy` quartet.
- Helper placement within `DegenerusGameJackpotModule.sol` (planner default: adjacent to `_processDailyEth` / `_runJackpotEthFlow` cluster, ~L1080–1190).
- Hardhat fixture pattern for SOLO-09 integration test (reference: `test/integration/GameLifecycle.test.js`).

## Deferred Ideas

- Plan slicing (1 / 2 / 3 plans) — deferred to the planner per Phase 259 D-11 mechanical-phase precedent.
- Phase 261 deliverables (Monte Carlo, chi-squared, pack-feel CIs, cross-surface, gas regression).
- Phase 262 deliverables (`audit/FINDINGS-v34.0.md`).
- REQUIREMENTS.md SOLO-01 / SOLO-08(d) text edits land alongside the helper implementation in the same plan that introduces it.
