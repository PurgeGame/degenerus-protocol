# Phase 124: Game Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 124-game-integration
**Areas discussed:** scope reduction, resolveLevel hook, handleGameOver wiring

---

## Gray Areas Presented

| Area | Description | User Response |
|------|-------------|---------------|
| resolveLevel hook design | Gas cap, placement, level sync timing | "rng requests are low gas, it should be fine" — no gas cap, just wire it |
| handleGameOver wiring | Where in gameover flow, revert handling | "do the gameover wiring" — wire it |
| claimYield mechanics | Permissionless pull function | "I don't want claimyield functions" — dropped |
| Gas ceiling impact | advanceGame headroom verification | "it should be fine" — no verification needed |

**User's choice:** "do the gameover wiring and the resolvelevel wiring" — rejected gas caps, claimYield, and gas ceiling analysis. Phase scoped to two mechanical hooks.

## Scope Reduction

INTG-01 and INTG-03 were identified as already complete (pulled forward to Phase 123). User approved ROADMAP update to reflect this.

INTG-04 (claimYield) explicitly dropped — lazy pull in burn() is sufficient.

## Claude's Discretion

- Test design and organization
- NatSpec for hook calls
- Exact handleGameOver placement within handleGameOverDrain

## Deferred Ideas

- INTG-04 claimYield() — explicitly dropped by user
