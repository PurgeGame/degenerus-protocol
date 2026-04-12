# Phase 222: External Function Coverage Gap — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 222-external-function-coverage-gap
**Areas discussed:** CSI-08 fix approach, Classification taxonomy, CRITICAL_GAP test depth, Deliverables — gate or one-shot, Scope of deployed contracts

---

## Gray area selection

| Option | Description | Selected |
|--------|-------------|----------|
| CSI-08 fix approach | How to reconcile FuturepoolSkim.t.sol with inlined skim logic | ✓ |
| Classification taxonomy | What counts as COVERED / CRITICAL_GAP / EXEMPT | ✓ |
| CRITICAL_GAP test depth | Realistic path requirement interpretation | ✓ |
| Deliverables — gate or one-shot | Makefile coverage gate vs audit-only | ✓ |

---

## CSI-08 fix approach

### Q1: How should we fix the FuturepoolSkim.t.sol compile error?

| Option | Description | Selected |
|--------|-------------|----------|
| Harness restoration | Extend SkimHarness (test-only) to replicate just the skim block. No contract edits. Preserves all 8 fuzz cases. | |
| Rewrite against parent | Rewrite tests to exercise _consolidatePoolsAndRewardJackpots end-to-end. More realistic integration-flavor path. | ✓ |
| Delete the file | Delete FuturepoolSkim.t.sol if skim invariants are covered elsewhere. | |
| Extract back to private fn | Extract _applyTimeBasedFutureTake back as a private function in DegenerusGameAdvanceModule.sol. Reverses v20.0 + contracts/ change. | |

**User's choice:** Rewrite against parent
**Notes:** Integration-flavor matches the bug class — coverage needs to reach the skim block through the real caller, not through a test-only harness that bypasses production flow.

### Q2: When rewriting, how to isolate the skim block from other _consolidatePools side effects?

| Option | Description | Selected |
|--------|-------------|----------|
| Zero inputs for isolation | Zero out non-skim side effects so tests target skim algebra. | |
| Accept broader scope | Let each test exercise the full pipeline; assertions verify skim + invariants together. | ✓ |
| Split into two files | Focused skim assertions in one file, integration tests in another. | |

**User's choice:** Accept broader scope
**Notes:** Consistent with the CSI-11 "realistic path" framing — broader scope tests catch class-of-bugs better than isolated skim algebra.

---

## Classification taxonomy

### Q1: What threshold makes a function COVERED?

| Option | Description | Selected |
|--------|-------------|----------|
| ≥1 test invocation | Binary — any test calling the function marks it COVERED. | |
| ≥1 test + ≥50% branch | Invocation plus minimum branch coverage. Catches mintPackedFor-class. | |
| ≥1 test + note branch gaps | ≥1 invocation marks COVERED; branch gaps annotated. | |

**User's choice:** "I don't know what any of this is I just need all my functions to work and never bug out"
**Notes:** User intent is clear even without picking from the options — all functions must work, never bug out. Translated to strictest practical threshold: ≥1 test invocation AND ≥50% branch coverage. Invocation alone cannot catch mintPackedFor-class because that bug's function was reachable but the reverting conditional branch was never entered.

### Q2: How broad is CRITICAL_GAP?

| Option | Description | Selected |
|--------|-------------|----------|
| mintPackedFor-class only | Narrow — functions with silent-revert hiding places only. | |
| Any uncovered non-exempt | Broad — every externally-callable non-EXEMPT function without coverage is CRITICAL_GAP. | ✓ |
| Uncovered + severity gate | Every uncovered is catalogued; CRITICAL_GAP reserved for state-changing w/ conditional branches. | |

**User's choice:** Any uncovered non-exempt
**Notes:** Consistent with the "all functions work" intent. Broadest definition ensures no uncovered surface slips through.

### Q3: What auto-exempts a function (no test required)?

| Option | Description | Selected |
|--------|-------------|----------|
| Admin/governance-gated | onlyOwner, onlyAdmin, onlyGovernance, onlyVault paths. | |
| view/pure | No state change — silent revert self-evident. | ✓ |
| Emergency/pause-gated | Paths reachable only after emergency pause or drain triggers. | |
| External-callback targets | rawFulfillRandomWords (VRF), onTokenTransfer (LINK), fallback/receive. | ✓ |

**User's choice:** view/pure + External-callback targets
**Notes:** Admin/governance/emergency paths are NOT auto-exempt — they still require tests. Aligned with user's "all functions work" directive; admin-gated paths can still hide mintPackedFor-class bugs and reach production.

---

## CRITICAL_GAP test depth

### Q1: What test style qualifies for a CRITICAL_GAP?

| Option | Description | Selected |
|--------|-------------|----------|
| Integration via natural caller | Test reaches the function through its actual caller chain. | ✓ |
| Unit test with realistic args | Direct invocation with realistic state. | |
| Fuzz with constrained state | Foundry fuzz with vm.assume() narrowing to realistic ranges. | |

**User's choice:** Integration via natural caller
**Notes:** Matches where mintPackedFor hid — in the conditional entry from a natural caller chain. Unit tests with realistic args wouldn't catch that class.

### Q2: Must each CRITICAL_GAP test hit the conditional-entry branch (not just happy path)?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — branch required | Each test must exercise the non-trivial conditional entry. Verified via forge coverage --report lcov. | |
| Yes for state-changing only | State-changing functions require branch-hit proof. View/pure and trivial setters pass with happy-path. | ✓ |
| No — invocation sufficient | One test per function; branch coverage noted but not required. | |

**User's choice:** Yes for state-changing only
**Notes:** view/pure already EXEMPT anyway. Trivial setters with no conditionals pass on happy-path (branch coverage trivially 100%). State-changing CRITICAL_GAPs must prove conditional-entry coverage.

### Q3: Reuse existing fuzz harnesses or build fresh for CRITICAL_GAP tests?

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse where possible | Extend test/fuzz/handlers/ and integration harnesses. Add fixtures only where no handler covers the target. | ✓ |
| Fresh per file | New dedicated test files per classified gap. | |
| Planner decides | Pattern per function. | |

**User's choice:** Reuse where possible
**Notes:** Minimizes divergence from the established fuzz architecture. Build fresh only when no handler exposes the target surface.

---

## Deliverables — gate or one-shot

### Q1: Should Phase 222 add a Makefile coverage gate?

| Option | Description | Selected |
|--------|-------------|----------|
| Threshold gate (make coverage-check) | Standalone target. Not wired into test-foundry/test-hardhat. Run manually or in CI. | ✓ |
| External-surface drift gate | Lightweight text-level gate blocking new externals without classification. | |
| No gate — audit + tests only | Audit artifact + new tests; no automation. | |
| Both (drift + threshold) | Drift gate per-build + threshold check as CI target. | |

**User's choice:** Threshold gate (make coverage-check)
**Notes:** `forge coverage` is minutes-long — can't run on every `make test`. Standalone target matches the right cadence (per-PR or CI, not per-build).

---

## Scope of deployed contracts (follow-up)

### Q1: Scope of 'deployed contracts' — stick to the 10 listed, or widen?

| Option | Description | Selected |
|--------|-------------|----------|
| 10 per REQUIREMENTS.md | Baseline list only. | |
| All 17 deployable .sol | Widen to every .sol in contracts/ that deploys as own address. | ✓ |
| 10 + admin/deity/trait | Compromise — add user-facing mutators. | |

**User's choice:** All 17 deployable .sol
**Notes:** Widens scope — DegenerusAdmin, DegenerusDeityPass, DeityBoonViewer, GNRUS, WrappedWrappedXRP now IN SCOPE. Planner must filter libraries (ContractAddresses, TraitUtils, Icons32Data) from the classification universe since they don't deploy standalone.

### Q2: More questions or ready for context?

| Option | Description | Selected |
|--------|-------------|----------|
| Ready for context | Write CONTEXT.md now. | ✓ |
| One more area | Explore another gray area. | |

**User's choice:** Ready for context

---

## Claude's Discretion

- Exact numeric ordering of the classification matrix (by contract / verdict / function name)
- Classification matrix format — one file vs per-contract directory
- Fuzz run/depth settings for new integration tests (match existing `foundry.toml` conventions)
- `coverage-check` script output format (colorization, JSON sidecar, plain PASS/FAIL lines)
- Whether to produce a `222-02-REGRESSION.md` companion summarizing existing-test growth vs new files
- How to rank CRITICAL_GAP priorities (call-site count / module criticality / blast radius)

## Deferred Ideas

- Extract `_applyTimeBasedFutureTake` back to private function — rejected (reverses v20.0)
- CI wall-clock budget for coverage-check — future milestone if needed
- Per-function coverage targets above 50% — uniform threshold for v27.0; revisit if hot spots appear
- Deployed bytecode verification — already in Future Requirements
- Revert specificity (`E()` → custom errors) — already in Future Requirements
- `is IXxx` compile-time interface inheritance — already decided out-of-scope in 220/221
