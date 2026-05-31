# Phase 351: TST — Freeze/Determinism + Revert-Free + EV-Cap + Two-Path + Set-Mutation + Non-Widening + Gas - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-31
**Phase:** 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
**Areas discussed:** Test-corpus disposition, New-proof rigor, Box same-results oracle (Regression-baseline scope offered but carried on precedent)

---

## Gray-area selection

| Option | Selected |
|--------|----------|
| AfKing test-corpus disposition | ✓ |
| New-proof rigor (unit vs fuzz) | ✓ |
| Box same-results oracle | ✓ |
| Regression-baseline scope | (unpicked — carried on precedent: Foundry-focused ledger, Hardhat as sanity check) |

---

## Test-corpus disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid, adapt-biased | Adapt every test whose property survives; delete only dead-mechanism tests; log deletions BY NAME (the v49 '17 deleted + 5 renamed' precedent). *Claude's recommendation.* | |
| Hybrid, lean-delete | Delete the corpus that doesn't cleanly map; write fresh only for TST-01..06. | |
| Adapt everything | Rewrite all ~13 files + the fixture to the GameAfkingModule path; preserve maximum coverage. | ✓ |

**User's choice:** Adapt everything.
**Notes:** USER chose maximum coverage retention over the recommended hybrid — an audit repo shouldn't lose battle-tested edge coverage. Claude's interpretation (confirmed by the user): reframe each property onto its v55 successor mechanism (epoch→stamped-day, staticcall→SLOAD, doWork→mintBurnie, cold-ledger→warm-stamp); the ONLY permitted deletion is a test whose entire subject is a fully-removed surface with no behavioral successor (the deleted AF_KING.batchPurchase/BatchBuy/onlyFlipCreditors entry), logged BY NAME with the removal reason. Bias = adapt/preserve, never silent-delete. Fixture-repair (`DeployProtocol.sol` → 64-file compile cascade) is Wave 0. → CONTEXT D-351-01/02/03.

---

## New-proof rigor

| Option | Description | Selected |
|--------|-------------|----------|
| Unit + fuzz where it strengthens | Targeted unit scenarios + fuzz layered on freeze/determinism, revert-free, set-mutation. *Claude's recommendation.* | ✓ |
| Targeted unit throughout | Deterministic unit scenarios for all of TST-01..04, no fuzz. | |
| Deep fuzz/invariant across the board | FOUNDRY_PROFILE=deep campaigns for all four properties (v44 precedent). | |

**User's choice:** Unit + fuzz where it strengthens.
**Notes:** Fuzz targets the properties where randomness genuinely strengthens the proof — TST-01 (random open-timing/block + mid-day index-advance), TST-02 (random funded slice inputs), TST-04 (random subscribe/evict/swap-pop orderings). TST-03/two-path are unit-shaped with optional light fuzz. Not a blanket deep-fuzz. → CONTEXT D-351-04.

---

## Box same-results oracle

| Option | Description | Selected |
|--------|-------------|----------|
| Differential | Run the afking stamp→open AND a manual openLootBox for the same (amount,level,rngWord,score); assert byte-identical traits. *Claude's recommendation.* | ✓ |
| Differential + golden tripwire | Differential primary + a few pinned golden trait arrays as a same-direction-drift tripwire. | |
| Golden values | Pin expected trait arrays as constants. | |

**User's choice:** Differential.
**Notes:** Robust to any future resolution refactor; the v48 'byte-reproduced' / v49 same-results precedent. → CONTEXT D-351-05.

---

## Claude's Discretion

- **Regression-baseline scope** (unpicked gray area) — Foundry-focused BY-NAME ledger; Hardhat `.test.js` suite confirmed still compiling/passing as a sanity check, not the primary ledger (v55's blast radius is narrower than v48's). Planner may confirm.
- **Gas-harness file placement/naming** — reframe the existing `test/gas/Keeper*WorstCaseGas.t.sol` instruments into the afking marginal harness per the 350 spec; exact filenames the planner's call.
- **`REGRESSION-BASELINE-v55.md` location** — `test/` by precedent (alongside v48/v49/v50); planner confirms.
- **Plan posture** — skip research, plan directly (`--skip-research`) per the test-phase posture.

## Deferred Ideas

- The Outcome-B `claimablePool` per-slice-vs-batch oracle + forced-underflow test — N/A under 350's Outcome A (GAS-03 REJECTED, no diff).
- v52 consolidated cross-model audit (v50+v51 debt) — separate post-v55 track.
- v56 affiliate/quest batching — separate post-ship milestone with its own economic review.
- 352 TERMINAL (delta-audit + 3-skill sweep + FINDINGS-v55.0 + closure) — the NEXT phase, not 351.
