# Phase 291: MINTCLN Regression Fixture (TST-MINTCLN) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-17
**Phase:** 291-mintcln-regression-fixture-tst-mintcln
**Areas discussed:** Empirical gas measurement

---

## Areas Presented (user selected one)

| Gray Area | Selected for Discussion |
|-----------|-------------------------|
| TST-MINTCLN-01 oracle model | |
| TST-MINTCLN-04 storage byte-identity technique | |
| Test file shape & location | |
| Empirical gas measurement | ✓ |

User selected only "Empirical gas measurement." The other three areas were implicitly delegated to planner discretion using the sister Phase 282 `test/edge/MintBatchDeterminism.test.js` pattern as the default — captured under "Claude's Discretion" in CONTEXT.md.

---

## Empirical Gas Measurement

| Option | Description | Selected |
|--------|-------------|----------|
| Informational `console.log` (Phase 282 pattern) | Add a single `console.log` measurement against the whale-bundle drain scenario — logs per-call gas + cumulative drain gas + emit count. No hard assertion. Honors the "test it" half of `feedback_gas_worst_case.md`. | |
| Hard regression assertion with hardcoded v41 baseline | Add TST-MINTCLN-06 (de-facto scope expansion): one-time measure v41 baseline drain gas via `git worktree add` at SHA `315978a0...`, hardcode as `DRAIN_GAS_V41_BASELINE = <N>`, assert measured v42 within X% of `v41 − theoretical_delta`. Brittle to toolchain upgrades. | |
| Skip empirical entirely | Treat 290-MEASUREMENT.md §3 theoretical attestation as complete. "Handed off to Phase 291" wording non-load-bearing. TST-MINTCLN-01..05 ship as specified; no gas test added. | ✓ |

**User's choice:** Skip empirical entirely.
**Notes:** Preserves tight scope on a mechanical test phase. The theoretical-first attestation under `feedback_gas_worst_case.md` is sufficient for a cleanup-shape phase with no production capital at risk; Phase 297 §3.A cites 290-MEASUREMENT.md §3 directly for the gas attestation. Locked as **D-291-GAS-01** in CONTEXT.md `<decisions>`.

---

## Claude's Discretion

The following gray areas were presented but NOT selected by the user — planner uses default dispositions documented in CONTEXT.md `<decisions>` → "Claude's Discretion":

- **TST-MINTCLN-01 oracle model** → JS-replay oracle (Phase 282 TST-FIX-01 ALGORITHM_VERIFIED pattern); extend `test/helpers/raritySymbolBatchRef.mjs` with v42 3-input variant; the "v41 owed-salt multiset" reference reads as the algorithmic invariant (cross-call seed separation), not bit-identical hash output.
- **TST-MINTCLN-04 storage byte-identity technique** → `eth_getStorageAt` direct slot reads against the post-patch deployment; structural "pre + post-MINTCLN" comparison already attested by Phase 290 MINTCLN-08 (`forge inspect storageLayout` EMPTY diff at 290-MEASUREMENT.md §2).
- **Test file shape & location** → new file `test/edge/MintCleanupRegression.test.js`; do NOT extend Phase 282 file in-place (keep it as a frozen v41-closure artifact); do NOT create `test/mint/` for a single file.
- **B2 path-coverage strategy** → reuse Phase 282 whale-bundle scenario shape (lvl=1 Path B + lvl=2..5 Path A in one drain); inline duplication of scenario setup acceptable up to ~50 LOC.
- **TST-MINTCLN-05 indexer-migration note placement** → JSDoc header at top of new test file; cites both topic hashes from 290-MEASUREMENT.md §5 + inherited D-40N-EVT-BREAK-01 posture; documentation-only.

## Deferred Ideas

- Empirical gas regression bench — explicitly skipped per D-291-GAS-01; not promoted to backlog.
- Hard regression assertion against theoretical gas bound (TST-MINTCLN-06 candidate) — out of scope per D-291-GAS-01.
- Phase 282 file refactor / scenario-helper extraction — Phase 282 is a frozen v41-closure artifact; refactor deferred to v43+ test-maintenance bundle if ever load-bearing.
