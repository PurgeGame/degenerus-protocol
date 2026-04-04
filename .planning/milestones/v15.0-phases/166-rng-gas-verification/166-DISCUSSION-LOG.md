# Phase 166: RNG & Gas Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 166-rng-gas-verification
**Areas discussed:** VRF consumer scope, Gas profiling method, Commitment window depth

---

## VRF Consumer Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Delta only (Recommended) | Only audit VRF paths new/modified in v11.0-v14.0. Cite prior audit verdicts for unchanged paths. | ✓ |
| Full fresh trace | Re-trace every VRF consumer from scratch regardless of prior coverage. | |
| Delta + spot-check | Delta audit plus spot-check 2-3 unchanged paths for silent regressions. | |

**User's choice:** Delta only
**Notes:** Phase 165 already traced entropy usage for rollLevelQuest, rollDailyQuest, _bonusQuestType, and payAffiliate PRNG. Prior audits (v1.2, v3.8) proved existing paths safe.

---

## Gas Profiling Method

| Option | Description | Selected |
|--------|-------------|----------|
| Static analysis (Recommended) | Count SLOADs, MSTOREs, external calls, and loop iterations from source. No test execution needed. | ✓ |
| Forge gas snapshots | Run forge test --gas-report with worst-case inputs. Exact numbers but requires compilation. | |
| Both | Static analysis for report, forge snapshots to validate. Most thorough. | |

**User's choice:** Static analysis
**Notes:** Consistent with prior gas audits in this project.

---

## Commitment Window Trace Depth

| Option | Description | Selected |
|--------|-------------|----------|
| One-hop consumer trace (Recommended) | Identify VRF word source, verify consuming input committed before VRF request, check player-controllable state. Same depth as v3.8. | |
| Full call-chain trace | Trace backward through entire call chain from consumer to VRF fulfillment callback, documenting every intermediate state. | ✓ |
| Consumer + refactoring check | One-hop trace plus verify refactored code didn't move state writes into commitment window. | |

**User's choice:** Full call-chain trace
**Notes:** User preferred more thorough approach over recommended one-hop for the delta audit.

---

## Claude's Discretion

- Report structure and formatting
- Which prior audit verdicts to cite for unchanged paths
- Gas analysis organization (by function, by contract, or by path)

## Deferred Ideas

None
