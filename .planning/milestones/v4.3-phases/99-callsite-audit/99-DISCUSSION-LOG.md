# Phase 99: Callsite Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 99-callsite-audit
**Areas discussed:** Batching scope

---

## Batching Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All 3 auto-rebuy implementations | JackpotModule + DecimatorModule + EndgameModule | |
| Daily ETH path only (JackpotModule _processDailyEth) | Just the 321-winner loop | |
| Any daily jackpot path awarding ETH in large batches | _processDailyEth (321) + _runEarlyBirdLootboxJackpot (100) | ✓ |

**User's choice:** "any of the daily jackpots that award eth in large batches"
**Notes:** User initially said "just worry about the daily jackpots that pay eth", then clarified to include any daily jackpot that awards ETH in large winner batches — which includes both the main daily ETH loop (321 winners) and the earlybird lootbox jackpot (100 winners on Day 1). DecimatorModule and EndgameModule excluded.

---

## Claude's Discretion

- Audit deliverable format (table structure, level of detail)
- Gas baseline calculation methodology

## Deferred Ideas

- DecimatorModule `_processAutoRebuy` batching
- EndgameModule auto-rebuy batching
- Full protocol-wide prizePoolsPacked write map
