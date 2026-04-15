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

## Cursor-Manager Observable States

| State | Definition | Entry transition | Exit transition | Anchor |
|-------|------------|------------------|-----------------|--------|
| `absent` | No row in `indexer_cursor` | initial DB state | C2 (initializeCursor) | main.ts:99 `existingCursor === null` |
| `initialized` | Row exists; `lastProcessedBlock = startBlock` (min deploy block) | C2 from `absent` | C3 (advanceCursor) | main.ts:103 |
| `resuming` | Row exists with lastProcessedBlock > 0 at startup | DB persistence across restarts | enters main loop (no code transition) | main.ts:106-109 |
| `advancing` | main loop iteration: batch committed, cursor advanced | C3 inside `processBlockBatch` tx | next loop iteration or `reorging` | main.ts:188-201 (C3 indirect via event-processor.ts:161; `cursor = batchEnd` in-memory at main.ts:203) |
| `reorging` | `detectReorg` returned non-null forkBlock | C3 (via `rollbackToBlock`'s tx setting cursor) | in-memory `cursor = forkBlock` then `continue` | main.ts:155-161 |
| `reindex-reset` | `--from-block` CLI: cursor forcibly rewound to `fromBlock - 1` | C2 (overwrite) | main loop starts at new cursor | main.ts:132-134 |
| `reindex-restored` | Post-reindex: original cursor restored if bounded and originalCursor > toBlock | C2 (overwrite) | process exits | main.ts:224-226 |
| `follow-wait` | `cursor >= safeBlock` → poll sleep | main loop continue | wakes to re-check tip | main.ts:143-146 |

## Reorg-Detector Observable States

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
| M1 | 227-deferral-1 | /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45 | "handle re-initialization safely" | Unconditional overwrite; no rewind guard | LOW (comment overclaims); behavioral PASS | PASS-with-LOW | `initializeCursor` (cursor-manager.ts:50-65) unconditionally overwrites `lastProcessedBlock` via `onConflictDoUpdate`. The 3 live call sites in main.ts are (a) :103 startup only when `existingCursor === null` (unreachable against healthy cursor), (b) :133 intentional reindex rewind, (c) :225 intentional post-reindex restore. No live caller silently rewinds a healthy cursor — behavioral PASS. The "safely" docstring is still misleading: no runtime guard exists against future callers. | F-28-228-01 |
| M2 | — | /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:70-72 | "MUST be called inside a database transaction" | Type signature accepts `DbOrTx`; no runtime enforcement | INFO (Tier B) | PASS-with-INFO | Docstring at cursor-manager.ts:68-73 is accurate prescriptively; `advanceCursor` (cursor-manager.ts:75-83) accepts the union type `DbOrTx` (cursor-manager.ts:15-19) with no runtime check. In practice event-processor.ts:161 invokes it inside `db.transaction` opened at main.ts:188 (tx-scoped object). Convention-only enforcement — Tier B drift. | F-28-228-02 |
| M3 | 227-deferral-2 | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:33 | "ON CONFLICT DO UPDATE on blockNumber for idempotent re-processing" | Overwrites hash/parentHash/timestamp/eventCount | PASS construct | PASS | `storeBlock` (reorg-detector.ts:38-66) uses `onConflictDoUpdate` keyed on `blocks.blockNumber` (line 58) and overwrites the four mutable columns (lines 59-64). Idempotent by construction: repeated invocation with identical inputs yields identical state. | — |
| M4 | 227-deferral-2 | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts (undocumented invariant) | (No comment) — rollback must precede storeBlock on reorg'd block | main.ts:155-161 guarantees `continue` after rollback | PASS — intra-batch edge case MEDIUM-risk | PASS | Control-flow trace: detectReorg at main.ts:155 precedes every storeBlock path. When `forkBlock !== null` (main.ts:156), rollbackToBlock runs (main.ts:158), cursor is reset in-memory (main.ts:159), and `continue` (main.ts:160) skips the `processBlockBatch` call at main.ts:189 → event-processor.ts:151 storeBlock. Ordering invariant holds for same-iteration reorgs. Intra-batch mid-range reorg is tracked separately as E1. | — |
| M5 | — | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:26-27 | `MAX_REORG_DEPTH = 128` | Loop bound at :113; throw at :140 | PASS | PASS | Constant declared at reorg-detector.ts:27. Loop `for (let depth = 1; depth <= MAX_REORG_DEPTH; depth++)` at :113 iterates 1..128 inclusive. On loop exhaustion (depth > 128 without match), throw at :140-143 with block number context. Documented invariant matches code. | — |
| M6 | — | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:73-76 | Walk-back semantics (compare stored vs rpc at checkBlock+1) | :113-137 implements exactly as described | PASS | PASS | For each depth, compute `checkBlock = blockNumber - 1 - depth` (reorg-detector.ts:114); bail to genesis at :115-117 (`checkBlock < 0n` → return 0n); if no stored block, return checkBlock as fork (:126-129); otherwise fetch `rpcCheck = client.getBlock({ blockNumber: checkBlock + 1n })` (:132) and compare `rpcCheck.parentHash === storedCheck[0].blockHash` (:134). Matches docstring :71-82. | — |
| M7 | — | /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:149 | "all within a single database transaction" | db.transaction! wraps purge + cursor reset | PASS | PASS | `rollbackToBlock` body at reorg-detector.ts:167-181 invokes `db.transaction!(async (tx) => { ... })`; within the callback it iterates PURGEABLE_TABLES (:169-171) deleting `blockNumber > forkBlock` and resets `indexer_cursor.lastProcessedBlock = forkBlock` (:174-180). Atomic all-or-nothing. | — |
| M8 | 227-deferral-4 | /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:211 | "skip during backfill" | `lag <= config.batchSize` inclusive boundary | PASS | PASS | Code at main.ts:211-215: `const lag = Number(tip - batchEnd); if (lag <= config.batchSize) { await refreshMaterializedViews(db); }`. The `<=` inclusive boundary treats the final catch-up batch (lag == batchSize) as follow-mode, which refreshes once at the end of backfill. RESEARCH §Backfill-Gate edge-case matrix shows all 5 scenarios intent-match; the ambiguous `lag == batchSize` case resolves conservatively in favor of refresh. | — |
| M13 | — | ROADMAP IDX-04 | "recovery-after-stall" | No stall detector; only 5-second catch-retry at main.ts:216-220 | INFO/LOW — RESOLVED-DOC or RESOLVED-CODE-FUTURE | PASS-with-INFO | Grep across `/home/zak/Dev/PurgeGame/database/src/indexer/` surfaces no stall timer, no dead-cursor watchdog, no backfill-recovery gate. The only "recovery-like" mechanism is the try/catch + 5-second setTimeout retry at main.ts:216-220. Requirement text is aspirational — code satisfies a single failure-mode (throw/retry) but not "stall" (hanging RPC, dead TCP). Resolution: RESOLVED-DOC (scope out term) or RESOLVED-CODE-FUTURE. | F-28-228-03 |
| M14 | — | REQUIREMENTS IDX-04 | "gap handling" | No explicit gap detection; `batchStart = cursor + 1` never skips | INFO / PASS by construction | PASS-with-INFO | main.ts:152 `const batchStart = cursor + 1n;` — cursor advances only via `advanceCursor(tx, batchEnd)` at event-processor.ts:161 inside the same tx that inserts events. There is no code path that skips blocks; gap handling is vacuous by the monotonic advance invariant. No explicit detector is needed. | — |
| E1 | intra-batch-edge | /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:155-201 | (undocumented) — reorg occurring mid-batch between detectReorg(:155) and processBlockBatch(:188) could storeBlock a canonical row without rollback | Mitigation relies on `config.confirmations` — see A3 | MEDIUM unless confirmations ≥ 1 default | PASS-with-LOW | `detectReorg(db, client, batchStart)` at main.ts:155 checks only `batchStart`. The batch spans `[batchStart, batchEnd]` (main.ts:151-152, up to batchSize=2000). A reorg at `batchStart + k` (k>0) occurring between the detectReorg call and the block-header fetch at main.ts:178 will not be detected in this iteration; storeBlock at event-processor.ts:151 would ON CONFLICT DO UPDATE the reorg'd block row with pre-reorg hash. **Confirmations window mitigates on mainnet (64) and sepolia (5) per `/home/zak/Dev/PurgeGame/database/src/config/chains.ts:11-12`**; **anvil local dev has `confirmations: 0` (chains.ts:13)** — the race window is real on local dev. Next iteration's detectReorg at new `batchStart` would notice hash mismatch and rollback via walk-back, so the defect is self-healing on the subsequent loop; severity LOW (not MEDIUM) because recovery is automatic and no silent permanent corruption results. | F-28-228-04 |

**Note:** Row E1 is the intra-batch reorg edge case surfaced in 228-RESEARCH.md §Reorg-Detector State Machine M4 trace. Severity calibrated to LOW (not MEDIUM) after A3 resolved: while anvil runs with confirmations=0, the next-iteration detectReorg self-heals via walk-back — no permanent divergence, only transient stale-view.

## Assumption-Check Worklist

| # | Assumption | How to verify | Resolution |
|---|------------|---------------|------------|
| A1 | `processBlockBatch` invokes `storeBlock` | `rg -n 'storeBlock' /home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` | **RESOLVED PASS** — `storeBlock` imported at event-processor.ts:21; invoked at event-processor.ts:151 inside the `blockHeaders` loop (event-processor.ts:149-158). Argument `tx as any` — same tx passed from main.ts:188. |
| A2 | `processBlockBatch` invokes `advanceCursor` inside a tx | `rg -n 'advanceCursor' /home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` | **RESOLVED PASS** — `advanceCursor` imported at event-processor.ts:20; invoked at event-processor.ts:161 with `(tx as any, toBlock)`. Enclosing scope is the `processBlockBatch` function body (event-processor.ts, called from main.ts:189 inside `db.transaction(async (tx) => ...)` at main.ts:188). Transactional with event inserts. |
| A3 | `config.confirmations` default value ≥ 1 | Read `/home/zak/Dev/PurgeGame/database/src/config/chains.ts` | **RESOLVED MIXED** — `chains.ts:11` mainnet `confirmations: 64`; `chains.ts:12` sepolia `confirmations: 5`; `chains.ts:13` anvil(31337) `confirmations: 0`. The E1 intra-batch reorg edge case is mitigated on mainnet and sepolia (confirmations window >> batchSize=2000 race exposure) but is NOT mitigated on anvil local dev. Rationale for E1 severity (LOW rather than MEDIUM): self-healing via next-iteration detectReorg walk-back. |

## SC-4 File-Touch Evidence

| Indexer file | Touched by 228-01? | Where |
|--------------|---------------------|-------|
| cursor-manager.ts | ✓ | M1 (cursor-manager.ts:45 rationale cites :50-65), M2 (:70-72 + :15-19 type alias) |
| reorg-detector.ts | ✓ | M3 (:33, :38-66), M4 (undocumented), M5 (:26-27, :113, :140-143), M6 (:73-76, :113-137), M7 (:149, :167-181) |
| main.ts | ✓ | M4 (:155-161), M8 (:211-215), E1 (:151-178), M13 (:216-220), M14 (:152), A2 (:188-189) |
| block-fetcher.ts | ✓ | `fetchLogs` (block-fetcher.ts:74) invoked at main.ts:164; `getLatestBlockNumber` (block-fetcher.ts:154) invoked at main.ts:140 — tip/safeBlock computation feeding the E1 confirmations-window mitigation |
| purge-block-range.ts | ✓ | `PURGEABLE_TABLES` (purge-block-range.ts:98) iterated by `rollbackToBlock` at reorg-detector.ts:169-171 (M7); `purgeBlockRange` (purge-block-range.ts:181) invoked by main.ts:129 reindex path (M1 context-c call-site setup) |

## Spot-Recheck Log

Per 228-VALIDATION.md §Sampling Rate — 2 rows re-verified by re-reading enclosing function bodies.

### Re-check 1 — Row M4 (reorg ordering, undocumented invariant)

Re-read main.ts:138-220 full loop body AND event-processor.ts:140-167 (storeBlock call-site + advanceCursor call-site). Confirmed the complete trace: main.ts:155 `const forkBlock = await detectReorg(db, client, batchStart);` → :156 `if (forkBlock !== null)` → :158 rollbackToBlock → :159 `cursor = forkBlock;` → :160 `continue;`. The `continue` unconditionally skips lines 163-215 of the loop body, which means neither the `fetchLogs` at :164, nor the block-header fetch at :178, nor the `db.transaction` at :188 (which contains the `processBlockBatch` call at :189 that would reach `storeBlock` at event-processor.ts:151) is reachable in a reorg iteration. Ordering invariant holds strictly for same-iteration. **Verdict confirmed: PASS.**

### Re-check 2 — Row M8 (backfill gate `<=` boundary)

Re-read main.ts:188-220 around the gate. Confirmed `cursor = batchEnd;` at :203 precedes the gate; `lag` is computed on the post-batch state (:212 `const lag = Number(tip - batchEnd);`). With `batchSize=2000` and mainnet `confirmations=64`: the largest in-flight lag is bounded by `tip - safeBlock = confirmations = 64` once caught up, which is ≤ 2000 → refresh always fires in follow mode, consistent with intent. During backfill with lag in tens-of-thousands, refresh correctly skips. The `<=` boundary provides one refresh at backfill-exit (when the final catch-up batch has `lag == batchSize`) which is conservative and desirable (no materialized-view staleness window at transition). **Verdict confirmed: PASS.**

## Findings

#### F-28-228-01: `initializeCursor` "safely" docstring overclaims — no runtime rewind guard

- **Severity:** LOW
- **Direction:** comment→code
- **Phase:** 228
- **Requirement:** IDX-04
- **Origin row:** M1 (227-deferral-1)
- **File:** /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45
- **Resolution (proposed):** RESOLVED-DOC (retitle docstring to "handle re-initialization idempotently") OR RESOLVED-CODE-FUTURE (add `WHERE indexer_cursor.lastProcessedBlock IS NULL OR indexer_cursor.lastProcessedBlock < excluded.lastProcessedBlock` guard to the `onConflictDoUpdate`)
- **Evidence:** cursor-manager.ts:50-65 unconditionally overwrites; no live caller triggers silent rewind (main.ts:103/133/225 trace in M1). Risk is latent: a future caller that inadvertently re-invokes `initializeCursor` against a healthy cursor would silently truncate progress.

#### F-28-228-02: `advanceCursor` transactional requirement unenforced at runtime

- **Severity:** INFO
- **Direction:** comment→code
- **Phase:** 228
- **Requirement:** IDX-04
- **Origin row:** M2
- **File:** /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:70
- **Resolution (proposed):** INFO-ACCEPTED (convention-only is standard in the codebase — duck-typed `DbOrTx` is deliberate) OR RESOLVED-CODE-FUTURE (split into `advanceCursorInTx(tx: Tx)` with a distinct type that only a transaction satisfies)
- **Evidence:** cursor-manager.ts:15-19 `DbOrTx` type union, cursor-manager.ts:75-83 `advanceCursor` accepts the union. Current call at event-processor.ts:161 passes the tx arg from main.ts:188 `db.transaction(async (tx) => ...)` — convention holds today; no type-system enforcement.

#### F-28-228-03: ROADMAP IDX-04 "recovery-after-stall" requirement unbacked by code

- **Severity:** INFO
- **Direction:** docs→code
- **Phase:** 228
- **Requirement:** IDX-04
- **Origin row:** M13
- **File:** /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:216-220 (site of the only "recovery-like" mechanism — 5s catch-retry)
- **Resolution (proposed):** RESOLVED-DOC (remove "recovery-after-stall" from ROADMAP IDX-04 scope OR narrow to "5-second error backoff") OR RESOLVED-CODE-FUTURE (add watchdog timer, dead-cursor detector)
- **Evidence:** No `stall`, `watchdog`, `deadCursor`, `timeout` detector exists in `/home/zak/Dev/PurgeGame/database/src/indexer/`. The try/catch at main.ts:216-220 handles thrown errors only, not hangs.

#### F-28-228-04: Intra-batch reorg edge case — unmitigated on anvil (confirmations=0)

- **Severity:** LOW
- **Direction:** docs→code
- **Phase:** 228
- **Requirement:** IDX-04
- **Origin row:** E1
- **File:** /home/zak/Dev/PurgeGame/database/src/indexer/main.ts:155 (detectReorg only checks `batchStart`, not the full `[batchStart, batchEnd]` range)
- **Resolution (proposed):** RESOLVED-CODE-FUTURE (either reduce batchSize when confirmations=0, or run detectReorg against `batchEnd` after block-header fetch) OR INFO-ACCEPTED for dev-chain configs (local-only impact; next-iteration detectReorg walk-back self-heals the stored hash within one batch)
- **Evidence:** `/home/zak/Dev/PurgeGame/database/src/config/chains.ts:13` — anvil `confirmations: 0`. Race window: a reorg at `batchStart + k` (k>0) between main.ts:155 and main.ts:178 would storeBlock a pre-reorg hash. Self-healing confirmed via walk-back in next iteration (reorg-detector.ts:113-137) but the transient stale-hash exists for one batch cycle. Severity LOW (self-healing, no permanent divergence).
