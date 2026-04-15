# 228-01 Cursor & Reorg State-Machine Trace (IDX-04)

**Phase:** 228 | **Plan:** 01 | **Requirement:** IDX-04
**Deliverable for:** D-228-06 (228-01 deliverable)
**Finding block:** F-28-228-01+ (per D-228-10; disjoint from 228-02's F-28-228-101+)
**Severity taxonomy:** INFO / LOW / MEDIUM (per D-228-11)
**Scope:** cross-repo READ-only per D-228-01; catalog-only per D-228-02.
**Audit surface:** `/home/zak/Dev/PurgeGame/database/src/indexer/{cursor-manager,reorg-detector,main,block-fetcher,purge-block-range}.ts`

## Absorbed Phase 227 Deferrals (D-228-09)

| # | 227 deferral | File:line | Handled by row |
|---|--------------|-----------|----------------|
| 1 | cursor-manager.ts:45 `initializeCursor` rewind guardrail | `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45` | M1 (annotated `227-deferral-1`) |
| 2 | reorg-detector.ts:33 `storeBlock` ON CONFLICT ordering | `/home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:33` | M3 + M4 (annotated `227-deferral-2`) |
| 4 | main.ts:211 backfill gate `<=` boundary | `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts:211` | M8 (annotated `227-deferral-4`) |

## Cursor-Manager Observable States (from 228-RESEARCH.md §Cursor State Machine)

| State | Definition | Entry transition | Exit transition | Anchor |
|-------|------------|------------------|-----------------|--------|
| `absent` | No row in `indexer_cursor` | initial DB state | C2 (initializeCursor) | main.ts:99 `existingCursor === null` |
| `initialized` | Row exists; `lastProcessedBlock = startBlock` (min deploy block) | C2 from `absent` | C3 (advanceCursor) | main.ts:103 |
| `resuming` | Row exists with lastProcessedBlock > 0 at startup | DB persistence across restarts | enters main loop (no code transition) | main.ts:106-109 |
| `advancing` | main loop iteration: batch committed, cursor advanced | C3 inside `processBlockBatch` tx | next loop iteration or `reorging` | main.ts:188-201 (C3 indirect via processBlockBatch — event-processor.ts:161; `cursor = batchEnd` in-memory at main.ts:203) |
| `reorging` | `detectReorg` returned non-null forkBlock | C3 (via `rollbackToBlock`'s tx setting cursor) | in-memory `cursor = forkBlock` then `continue` | main.ts:155-161 |
| `reindex-reset` | `--from-block` CLI: cursor forcibly rewound to `fromBlock - 1` | C2 (overwrite) | main loop starts at new cursor | main.ts:132-134 |
| `reindex-restored` | Post-reindex: original cursor restored if bounded and originalCursor > toBlock | C2 (overwrite) | process exits | main.ts:224-226 |
| `follow-wait` | `cursor >= safeBlock` → poll sleep | main loop continue | wakes to re-check tip | main.ts:143-146 |

## Reorg-Detector Observable States (from 228-RESEARCH.md §Reorg-Detector State Machine)

| State | Definition | Entry | Exit | Anchor |
|-------|------------|-------|------|--------|
| `pre-detect` | Batch fetched, reorg check pending | main loop head | R2 call | main.ts:155 |
| `no-reorg` | R2 returned null | R2 null return | `process-batch` | main.ts:155 → 164 |
| `reorg-detected` | R2 returned forkBlock ≥ 0 | R2 non-null | `rolling-back` | main.ts:156-157 |
| `rolling-back` | R3 tx running | R3 call | `post-rollback` | main.ts:158 |
| `post-rollback` | cursor in-memory set to forkBlock; `continue` | R3 return | next loop iteration | main.ts:159-161 |
| `reorg-depth-exceeded` | R2 threw (MAX_REORG_DEPTH=128) | R2 throw | caught at main.ts:216 `log.error + 5s sleep + retry` | main.ts:216-220, reorg-detector.ts:140-143 |
| `storing-block` | R1 called inside `processBlockBatch` tx | R1 call | tx commit → cursor advances | event-processor.ts:151, main.ts:188-201 |

## Audit Rows (M-matrix — verbatim from 228-RESEARCH.md)

| Row ID | Annotations | File:line | Claim | Code behavior | Expected verdict | Final verdict | Rationale | Finding ID (if FAIL) |
|--------|-------------|-----------|-------|---------------|------------------|---------------|-----------|----------------------|
| M1 | 227-deferral-1 | /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45 | "handle re-initialization safely" | Unconditional overwrite; no rewind guard | LOW (comment overclaims); behavioral PASS | TBD-Task2 | TBD | TBD |
| M2 | — | /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:70-72 | "MUST be called inside a database transaction" | Type signature accepts `DbOrTx`; no runtime enforcement | INFO (Tier B) | TBD | TBD | TBD |
| M3 | 227-deferral-2 | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:33 | "ON CONFLICT DO UPDATE on blockNumber for idempotent re-processing" | Overwrites hash/parentHash/timestamp/eventCount | PASS construct | TBD | TBD | TBD |
| M4 | 227-deferral-2 | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts (undocumented invariant) | (No comment) — rollback must precede storeBlock on reorg'd block | main.ts:155-161 guarantees `continue` after rollback | PASS — intra-batch edge case MEDIUM-risk | TBD | TBD | TBD |
| M5 | — | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:26-27 | `MAX_REORG_DEPTH = 128` | Loop bound at :113; throw at :140 | PASS | TBD | TBD | TBD |
| M6 | — | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:73-76 | Walk-back semantics (compare stored vs rpc at checkBlock+1) | :113-137 implements exactly as described | PASS | TBD | TBD | TBD |
| M7 | — | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:149 | "all within a single database transaction" | db.transaction! wraps purge + cursor reset | PASS | TBD | TBD | TBD |
| M8 | 227-deferral-4 | /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:211 | "skip during backfill" | `lag <= config.batchSize` inclusive boundary | PASS | TBD | TBD | TBD |
| M13 | — | ROADMAP IDX-04 | "recovery-after-stall" | No stall detector; only 5-second catch-retry at main.ts:216-220 | INFO/LOW — RESOLVED-DOC or RESOLVED-CODE-FUTURE | TBD | TBD | TBD |
| M14 | — | REQUIREMENTS IDX-04 | "gap handling" | No explicit gap detection; `batchStart = cursor + 1` never skips | INFO / PASS by construction | TBD | TBD | TBD |
| E1 | intra-batch-edge | /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:155-201 | (undocumented) — reorg occurring mid-batch between detectReorg(:155) and processBlockBatch(:188) could storeBlock a canonical row without rollback | Mitigation relies on `config.confirmations` — see A3 | MEDIUM unless confirmations ≥ 1 default | TBD | TBD | TBD |

**Note:** Row E1 is the intra-batch reorg edge case surfaced in 228-RESEARCH.md §Reorg-Detector State Machine M4 trace. It must be audited explicitly and its severity calibrated against the verified `config.confirmations` default (Assumption A3).

## Assumption-Check Worklist (must resolve before Task 2 closes)

| # | Assumption | How to verify | Resolution |
|---|------------|---------------|------------|
| A1 | `processBlockBatch` invokes `storeBlock` | `rg -n 'storeBlock' /home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` | TBD |
| A2 | `processBlockBatch` invokes `advanceCursor` inside a tx | `rg -n 'advanceCursor' /home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` | TBD |
| A3 | `config.confirmations` default value ≥ 1 | Read `/home/zak/Dev/PurgeGame/database/src/config/chains.ts` | TBD |

## SC-4 File-Touch Evidence

| Indexer file | Touched by 228-01? | Where |
|--------------|---------------------|-------|
| cursor-manager.ts | ✓ | M1, M2 |
| reorg-detector.ts | ✓ | M3, M4, M5, M6, M7 |
| main.ts | ✓ | M8, E1, M13 (control-flow trace), assumption-check worklist |
| block-fetcher.ts | TBD | Task 2 verifies fetchLogs call site |
| purge-block-range.ts | TBD | Task 2 verifies rollbackToBlock → PURGEABLE_TABLES delete |
