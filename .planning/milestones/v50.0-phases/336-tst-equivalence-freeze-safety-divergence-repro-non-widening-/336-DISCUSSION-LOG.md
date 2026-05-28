# Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `336-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-05-28
**Phase:** 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-
**Areas discussed:** TST-03 MINTDIV regression shape

**Selected for discussion:** TST-03 only. Three other areas (TST-01 freeze-fuzz home/depth, TST-01/TST-02 explicit oracles, TST-04 ledger format + commit cadence) were presented at gray-area selection but un-selected — Claude defaults locked in CONTEXT.md per the 334+335 locked context and the v49 332 D-precedent.

---

## Gray-Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| TST-01 freeze-fuzz home & depth | Where to author the freeze-invariant fuzz extension + depth/profile gating | |
| TST-01/TST-02 explicit oracles | Whether 336 adds dedicated TST-01 claim-time-grant oracle + uniform-O(1) gas-equivalence + TST-02 no-pass-SLOAD oracle | |
| TST-03 MINTDIV regression shape | Test shape, oracle methodology, anchor scenario, file home | ✓ |
| TST-04 ledger format + commit cadence | `test/REGRESSION-BASELINE-v50.md` shape + worktrees/commit posture | |

**User's choice:** TST-03 MINTDIV regression shape
**Notes:** The other three areas were locked to Claude defaults per the 334+335 SPEC/IMPL context + v49 332 D-precedent. CONTEXT.md documents each default with rationale.

---

## TST-03 MINTDIV regression shape

### Test shape — deterministic anchor only, fuzz overlay, or both?

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic anchor only | Single pinned test at the 334-research scenario (owed=300, warm 550). Easy to read, directly cites the reachability verdict. | |
| Deterministic anchor + boundary fuzz | Anchor as audit pin + fuzz overlay over owed ∈ [maxT+1, maxT+200]. v49 332 both-rails precedent for invariant proofs. | ✓ |
| Pure fuzz across owed values | Fuzz only — maximum coverage, but loses the named-scenario audit anchor and harder to triage when red. | |

**User's choice:** Deterministic anchor + boundary fuzz
**Notes:** Both-rails mirrors the v49 332 invariant-proof precedent. Deterministic test = audit anchor citing the 334 verdict; fuzz overlay = LCG-boundary surprise catcher.

### Oracle methodology — how does the test prove byte-identical traits?

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-path equality (across-split == contiguous) | Same scenario, two paths: N narrow slices vs. one fat-budget contiguous. Assert per-ticket trait byte-identity. Cleanest invariant statement. | ✓ |
| Reference-loop equality (vs processFutureTicketBatch:502) | Use the already-correct +=take loop as oracle. Anchors on canonical reference; risks coupling. | |
| Startindex-advance assertion | Assert processed advances by exactly `take`. Tightest binding to the fix; weakest as traits invariant. | |
| Cross-path equality + advance-assertion combined | Cross-path as headline + advance-assertion as fail-fast inner. Defense-in-depth. | |

**User's choice:** Cross-path equality (across-split == contiguous)
**Notes:** Pure cross-path equality without coupling to `processFutureTicketBatch` or extra advance-assertion. The LCG-output equivalence proof is stronger than the arithmetic — chosen for cleanest invariant statement.

### Deterministic-anchor scenario inputs

| Option | Description | Selected |
|--------|-------------|----------|
| 334-research scenario verbatim (owed=300, warm 550) | Exact replay of `334-MINTDIV01-REACHABILITY-VERDICT.md`: owed=300, WRITES_BUDGET_SAFE=550, maxT=292. Audit-traceable; test docstring cites the verdict by path. | ✓ |
| Minimum-reachable boundary (owed = maxT+1 = 293) | Smallest scenario that forces the split. Tightest test surface but loses the verdict's chosen owed=300. | |
| Both: owed=300 as headline + owed=293 as edge | Two deterministic test functions. Most thorough. | |

**User's choice:** 334-research scenario verbatim (owed=300, warm 550)
**Notes:** Single deterministic function with 1:1 verdict-to-test mapping. The boundary edge (owed=293) is delegated to the fuzz overlay from the shape decision.

### Test file home

| Option | Description | Selected |
|--------|-------------|----------|
| New dedicated file: test/fuzz/MintModuleDivergenceAcrossSplit.t.sol | Brand-new test file named for purpose. Easiest to grep, clearest audit lineage. | |
| Co-locate inside test/fuzz/RngFreezeAndRemovalProofs.t.sol | Add to the file 335 already touched. Single freeze-adjacent home. Risk: conflates MINTDIV (non-RNG) with RNG-freeze proofs. | |
| Pattern-mapper picks during planning | Defer to planner's pattern-mapper agent. Scans closest analog. Lower risk of authoring parallel structure. | ✓ |

**User's choice:** Pattern-mapper picks during planning
**Notes:** Mirrors v49 332's "you decide" delegation for proof-file homes. Planner authors the pattern-mapping decision against the live test tree, with a new dedicated file as the fallback if no close analog exists.

---

## Claude's Discretion

Three full gray areas were un-selected at the area-selection step and locked to Claude defaults per the 334+335 SPEC/IMPL context + v49 332 D-precedent. Each default is documented in `336-CONTEXT.md` `<decisions>` with rationale — review and override is invited there before planning.

The user-discussed area (TST-03) also surfaced one Claude's-discretion item: the TST-03 file home (D-TST03-04), delegated to the planner's pattern-mapper.

---

## Deferred Ideas

- The external RNG-audit protocol package + cold-start context pack — Phase 337 deliverable.
- The 3-skill genuine-PARALLEL adversarial sweep + the internal delta-audit + `audit/FINDINGS-v50.0.md` — Phase 338 TERMINAL.
- Hardhat-side parity beyond "stay-green-at-v49-last-known" — out of v50.0 scope.
- Full MintModule loop dedup — D-15 rejected for v50.
- A dedicated `refreshPass()` entrypoint regression test — D-10 rejected `refreshPass()`.
- The ≤level-10 whale-pass bonus band regression test — D-21 DROPPED the band; no test needed for removed code.
