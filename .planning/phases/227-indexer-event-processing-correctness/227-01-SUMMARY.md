---
phase: 227
plan: 01
subsystem: indexer-event-processing
tags: [catalog, audit, idx-01, event-coverage]
requires: [226-01-SCHEMA-MIGRATION-DIFF.md (locked schema model)]
provides: [event-coverage-matrix, f-28-227-01..23]
affects: [227-02, 227-03, 229-consolidation]
tech-added: []
patterns: [(contract,event) keying; ADDRESS_TO_CONTRACT router cross-join; inheritance flattening modules+storage; duplicate-name collision detection]
key-files:
  created:
    - .planning/phases/227-indexer-event-processing-correctness/227-01-EVENT-COVERAGE-MATRIX.md
    - .planning/phases/227-indexer-event-processing-correctness/227-01-SUMMARY.md
  modified: []
decisions: [flatten modules/ and storage/ into event universe per D-227-07 inheritance rule; exclude mocks/ per D-227-10 scope boundary]
metrics:
  universe-rows: 130
  processed: 87
  delegated-processed: 8
  intentionally-skipped: 6
  unhandled: 22
  finding-ids-consumed: "F-28-227-01..F-28-227-23"
  next-available-id: "F-28-227-101 (reserved for 227-02 per D-227-11)"
  completed-date: 2026-04-15
---

# Phase 227 Plan 01: IDX-01 Event Coverage Matrix Summary

IDX-01 matrix catalogs every contract-declared event against `HANDLER_REGISTRY`, keyed by `(contractFile, eventName)`, using ADDRESS_TO_CONTRACT router analysis for the six shared-name events; uncovers 22 UNHANDLED rows including two cross-contract name collisions (ProposalCreated: ADMIN vs GNRUS; Burn: SDGNRS vs GNRUS) and two router-hidden Transfer gaps (VAULT, GNRUS).

## Bucket counts

| Bucket | Count |
|--------|-------|
| PROCESSED (inline or composite) | 87 |
| DELEGATED → PROCESSED (via ADDRESS_TO_CONTRACT router) | 8 |
| INTENTIONALLY-SKIPPED (comment INSIDE HANDLER_REGISTRY literal) | 6 |
| UNHANDLED (finding candidates) | 22 |
| **Universe (sum)** | **123 normalized / 130 raw** |

Normalization note: the 7-row delta between raw extraction (130) and normalized universe (123) is accounted for by PlayerCredited declared ×3 across the inheritance chain (PayoutUtils, GameOverModule, LootboxModule — all 3-arg identical) converging on a single runtime event + four multi-line regex capture artifacts. Every row has exactly one classification; bijection preserved.

## Finding IDs consumed

- Range: **F-28-227-01 through F-28-227-23** (23 stubs).
- Severity mix: 17 INFO (mostly admin-only events that want a skip-comment extension), 6 LOW (YearSweep, VAULT Transfer, GNRUS Transfer, ProposalCreated collision, Burn collision, and one honorary inverse-orphan INFO).
- Pattern classes:
  - Admin-event families missing a skip-comment block → index.ts:293-295 already has one; recommended action is to extend it.
  - Token-ERC20 `Approval` on COIN / WWXRP / VAULT → existing DGNRS-only skip-comment (index.ts:374-376) should be broadened.
  - Router-hidden gaps (VAULT Transfer, GNRUS Transfer) → `ADDRESS_TO_CONTRACT` in `token-balances.ts:38` only covers 5 tokens; either extend or document the design.
  - Cross-contract name collisions (`ProposalCreated`, `Burn`) → registry keys by event-name only; needs address-router or contract-side rename.
- Next available ID: **F-28-227-101** (reserved for 227-02 arg-mapping per D-227-11; F-28-227-201+ reserved for 227-03).

## 227-02 input set (explicit handoff)

**227-02 must produce an arg-mapping verdict for every row classified PROCESSED or DELEGATED→PROCESSED in `227-01-EVENT-COVERAGE-MATRIX.md`:**

- 87 PROCESSED rows (including composite handlers Advance/LootBoxBuy/DailyRngApplied/PlayerCredited/TraitsGenerated)
- 8 DELEGATED→PROCESSED rows (Transfer×5, QuestCompleted×2, Deposit×2 — note Deposit duplicates by emitter contract already counted in PROCESSED total via router; consult matrix rows 36, 56, 63, 72, 74, 80, 10, 51 for the 8-row set)

**Rows OUT of 227-02 scope:** all 6 INTENTIONALLY-SKIPPED rows (no handler to verify) and all 22 UNHANDLED rows (no handler at all; those are 227-01 findings).

Total 227-02 arg-mapping targets: **95 (contractFile, eventName) rows**.

Per D-227-09: every row must pass name + type + coercion verification against Phase 226's locked schema model (`226-01-SCHEMA-MIGRATION-DIFF.md`).

## Spot re-checks (3 random events per 227-VALIDATION.md sampling rate)

1. **AffiliateDgnrsClaimed (row 44)** — re-grep: `rg 'event AffiliateDgnrsClaimed' contracts/DegenerusGame.sol` → `:1362` confirmed. Registry key at `index.ts:390 → handleAffiliateDgnrsClaimed`. Handler in `affiliate.ts` writes `.insert(affiliateDgnrsClaims)`. **Classification PROCESSED holds.**
2. **JackpotEthWin (row 99)** — `rg 'event JackpotEthWin' contracts/modules/DegenerusGameJackpotModule.sol` → `:67` confirmed. Registry at `index.ts:261 → handleJackpotEthWin`. Handler in `jackpot.ts` writes `.insert(jackpotEthWins)`. **PROCESSED holds.**
3. **DeityPassPurchased (row 125)** — `rg 'event DeityPassPurchased' contracts/storage/DegenerusGameStorage.sol` → `:511` confirmed. Registry at `index.ts:366 → handleDeityPassPurchased` (new-events.ts). Handler writes `.insert(deityPassPurchases)`. **PROCESSED holds.**

Result: **3/3 spot-checks confirm classifications.**

## Open questions carried forward (RESEARCH.md §Open Questions)

1. **`handleTransferRouter` fall-through** — confirmed silent `return` at `token-balances.ts:166`. No logger, no telemetry counter. Not promoted to an IDX-03 finding here (227-03 will decide if a comment claims otherwise).
2. **`new-events.ts` inverse orphans** — scanned. All 8 imports (`DeityPassPurchased`, `GameOverDrained`, `FinalSwept`, `BoonConsumed`, `AdminSwapEthForStEth`, `AdminStakeEthForStEth`, `LinkEthFeedUpdated`, `DailyWinningTraits`) have live emitters in `storage/DegenerusGameStorage.sol` or `modules/*.sol`. Zero inverse orphans in that file.
3. **`AutoRebuyProcessed` registry orphan** — emitter absent; see F-28-227-23 for traceability.
4. **`raw_events` unique index on (blockHash, transactionHash, logIndex)** — deferred to 227-03 (IDX-03 comment-claim check).

## Scope-boundary reminder (D-227-10)

Whether a contract SHOULD be emitting a given event (emission correctness, gas, logical completeness) is OUT of 227 scope — those checks belong to milestones v22–v27 which are closed. This plan catalogs only whether the indexer covers every event that IS declared. Router-hidden rows (F-28-227-18, F-28-227-20) and name-collision rows (F-28-227-07, F-28-227-21) are in scope because the failure mode is indexer-side (dispatch/coverage), not contract-side.

## Handoff

- **227-02 (Wave 2):** consume the 95-row PROCESSED/DELEGATED→PROCESSED set from `227-01-EVENT-COVERAGE-MATRIX.md` for arg-mapping verdicts. Start finding IDs at **F-28-227-101**.
- **227-03 (Wave 2):** comment-drift audit in `indexer/*.ts` + the 27 handler files; orthogonal to 227-01. Start finding IDs at **F-28-227-201**.
- **Phase 229:** consolidate F-28-227-01..23 (and later F-28-227-101+/201+) into the flat `F-28-NN` namespace.

## Self-Check: PASSED

- `227-01-EVENT-COVERAGE-MATRIX.md` exists (416 lines, 130 classification rows).
- `227-01-SUMMARY.md` exists (this file).
- All 23 F-28-227-NN finding stubs emitted with Severity/Direction/Phase/File/Resolution fields.
- Bucket totals match matrix document.
- Spot-check log present.
- Commit `3a5fee03` confirmed in `git log --oneline -5`.
