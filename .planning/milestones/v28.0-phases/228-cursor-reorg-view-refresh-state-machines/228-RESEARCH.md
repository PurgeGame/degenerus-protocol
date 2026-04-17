# Phase 228: Cursor, Reorg & View Refresh State Machines — Research

**Researched:** 2026-04-15
**Domain:** Indexer state-machine behavioral audit (cursor-manager, reorg-detector, view-refresh)
**Confidence:** HIGH (all primary sources READ; all file:line anchors verified against current code)

## Summary

This is a behavioral-audit phase, not a design phase. The locked context (D-228-01..11) already fixes scope (catalog-only, cross-repo READ-only, 2 plans, finding-ID blocks 01+/101+, INFO/LOW/MEDIUM severity). This research closes the control-flow / tracing gaps so the planner can write concrete per-transition rows.

Key findings:

1. **Cursor-manager has only 3 public operations** (`getCursorPosition`, `initializeCursor`, `advanceCursor`). "State machine" is implicit in how `main.ts` sequences these calls — the file itself has no state enum, no invariants, no documented ordering. All state is in `indexer_cursor` singleton row. [VERIFIED: cursor-manager.ts:29-83]
2. **Reorg-detector has 3 public operations** (`storeBlock`, `detectReorg`, `rollbackToBlock`) and one documented invariant: `MAX_REORG_DEPTH = 128`. No explicit state enum. The critical ordering question (rollback BEFORE storeBlock on reorg'd block) is controlled by `main.ts:155-161`, NOT by reorg-detector itself. [VERIFIED: reorg-detector.ts:27, main.ts:155-161]
3. **View-refresh has exactly 1 trigger site** (`main.ts:214`, inside the `lag <= config.batchSize` branch at `main.ts:213`). All 4 materialized views are refreshed in a single loop; none is refreshed on demand, and none has a per-view trigger. Error path is `log.error + continue` — no metric, no counter, no backoff, no alert. [VERIFIED: view-refresh.ts:26-34, main.ts:211-215]
4. **227 deferral #1 (cursor rewind):** `initializeCursor` UNCONDITIONALLY overwrites `lastProcessedBlock = startBlock` via ON CONFLICT DO UPDATE. It is called in 3 distinct contexts from `main.ts` (startup init, reindex reset, reindex-restore), and two of those are INTENTIONAL rewinds. The behavioral question is whether the startup context can rewind a healthy cursor. [VERIFIED: cursor-manager.ts:50-65, main.ts:103, 133, 225]
5. **227 deferral #2 (reorg overwrite ordering):** Rollback strictly precedes any subsequent `storeBlock` on reorg'd blocks because `detectReorg` runs BEFORE `processBlockBatch` in every iteration (`main.ts:155` before `main.ts:188-201`). After rollback, `cursor = forkBlock` then `continue` — no storeBlock executes in the same iteration. Appears CORRECT pending MEDIUM-severity edge-case check on intra-batch reorg between `detectReorg` and `processBlockBatch`. [VERIFIED: main.ts:155-161, 188-201]
6. **227 deferral #4 (backfill gate boundary):** Predicate is `const lag = Number(tip - batchEnd); if (lag <= config.batchSize)`. Edge case `batchEnd == tip - batchSize` yields `lag == batchSize`, which triggers refresh. Comment intent "skip during backfill" is satisfied iff "backfill" means `lag > batchSize` strictly. The `<=` is the INCLUSIVE follow-mode boundary. [VERIFIED: main.ts:211-215]
7. **No `CREATE MATERIALIZED VIEW` exists in any `.sql` migration** (from 226-01 findings) — the runtime creation path is unclear; this is a 228 context note (INFO), not a finding, per D-226-07 handoff. [CITED: 226-01-SCHEMA-MIGRATION-DIFF.md:708-717]

**Primary recommendation:** Two plans exactly as D-228-06 specifies; each plan produces a per-transition / per-trigger PASS/FAIL table seeded by the enumerations below. No additional research needed before planning.

## User Constraints (from CONTEXT.md)

### Locked Decisions (copied verbatim)

- **D-228-01:** Cross-repo READ-only. Reads target `/home/zak/Dev/PurgeGame/database/`. Zero writes there. Artifacts in `.planning/phases/228-cursor-reorg-view-refresh-state-machines/`.
- **D-228-02:** Catalog-only. No runtime gate, no CI.
- **D-228-03:** Tier A/B comment-drift threshold applies when findings are comment-side. IDX-04/05 findings also include behavior-side findings (documented invariant violated) which use INFO / LOW / MEDIUM severity.
- **D-228-04:** Finding IDs `F-28-228-NN` fresh counter from 01. Phase 229 consolidates.
- **D-228-05:** Direction defaults — `comment→code` for comment drift; `docs→code` for state-machine invariant violations against ROADMAP/REQUIREMENTS claims; `schema↔view` for view-definition drift.
- **D-228-06:** Two plans: 228-01 (IDX-04, cursor+reorg), 228-02 (IDX-05, view-refresh). Deliverables `228-01-CURSOR-REORG-TRACE.md` and `228-02-VIEW-REFRESH-AUDIT.md`.
- **D-228-07:** Enumerate every observable transition — documented AND undocumented.
- **D-228-08:** IDX-05 compares `view-refresh.ts` against (1) in-source comments in `indexer/*.ts` AND (2) `views.ts`. Downstream API consumers OUT OF SCOPE.
- **D-228-09:** Absorb 4 Phase 227 deferrals: #1→228-01, #2→228-01, #3→228-02, #4→228-01. Each becomes a pre-assigned audit row, NOT a pre-assigned finding ID.
- **D-228-10:** Finding ID reservation blocks — 228-01: `F-28-228-01+`; 228-02: `F-28-228-101+`.
- **D-228-11:** Severity: INFO (doc match / Tier B comment drift), LOW (behavior diverges from comment, no data risk), MEDIUM (silent data corruption or missed reorg recovery risk). HIGH/CRITICAL reserved for Phase 229 promotion.

### Claude's Discretion

- Wave structure — default: 228-01 and 228-02 both Wave 1 (independent).
- State-transition enumeration strategy.
- Whether to add a 3rd plan for SC-4 sweep — default: satisfy via 228-01/02 file-touch coverage.

### Deferred Ideas (OUT OF SCOPE)

- Runtime simulation / property tests.
- Reorg-depth / batch-size tuning recommendations.
- Observability build-out for swallowed refresh errors — document as INFO with `RESOLVED-CODE-FUTURE`.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IDX-04 | Cursor + reorg behave as documented (block ordering, gap, reorg depth, stall-recovery) | §Cursor State Machine, §Reorg-Detector State Machine, §Control-Flow Map |
| IDX-05 | View refresh triggers match staleness model in comments AND `views.ts` | §View-Refresh Trigger Map, §View Staleness Cross-Ref |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cursor checkpoint persistence | DB (indexer_cursor singleton) | Indexer control loop | Single row, advanced transactionally with events |
| Reorg detection | Indexer (reorg-detector.ts) | RPC (viem PublicClient) | Parent-hash compare against stored + RPC data |
| Reorg rollback | DB transaction (rollbackToBlock) | Indexer orchestrator | Atomic delete across PURGEABLE_TABLES + cursor reset |
| Backfill / follow mode switching | Indexer control loop (main.ts) | — | Decided by `lag` computation at main.ts:212 |
| View refresh | Indexer post-batch side-effect | DB (refreshMaterializedView CONCURRENTLY) | Out-of-transaction, non-fatal |
| View definition | Drizzle schema (views.ts) | Runtime creation path UNCLEAR (no CREATE MATERIALIZED VIEW in .sql migrations) | Context note from 226-01, Phase 228 INFO only |

---

## Cursor State Machine (IDX-04, 228-01)

### Public operations

| # | Function | File:line | Signature | Effect |
|---|----------|-----------|-----------|--------|
| C1 | `getCursorPosition(db)` | cursor-manager.ts:29 | `(db) -> bigint \| null` | Pure read of `indexer_cursor.id=1`. Returns `null` if row absent. |
| C2 | `initializeCursor(db, startBlock)` | cursor-manager.ts:50 | `(db, bigint) -> void` | INSERT `id=1, lastProcessedBlock=startBlock` with ON CONFLICT DO UPDATE → **unconditional overwrite**. |
| C3 | `advanceCursor(tx, toBlock)` | cursor-manager.ts:75 | `(tx, bigint) -> void` | UPDATE `lastProcessedBlock = toBlock` WHERE `id=1`. Requires transaction per docstring. |

### Observable states (derived from singleton row + caller contexts)

| State | Definition | Entry transition | Exit transition | Anchor |
|-------|------------|------------------|-----------------|--------|
| `absent` | No row in `indexer_cursor` | initial DB state | C2 (initializeCursor) | main.ts:99 `existingCursor === null` |
| `initialized` | Row exists; `lastProcessedBlock = startBlock` (min deploy block) | C2 from `absent` | C3 (advanceCursor) | main.ts:103 |
| `resuming` | Row exists with lastProcessedBlock > 0 at startup | DB persistence across restarts | enters main loop (no code transition) | main.ts:106-109 |
| `advancing` | main loop iteration: batch committed, cursor advanced | C3 inside `processBlockBatch` tx | next loop iteration or `reorging` | main.ts:188-201 (C3 indirect via processBlockBatch — needs verification in event-processor.ts; `cursor = batchEnd` in-memory at main.ts:203) |
| `reorging` | `detectReorg` returned non-null forkBlock | C3 (via `rollbackToBlock`'s tx setting cursor) | in-memory `cursor = forkBlock` then `continue` | main.ts:155-161 |
| `reindex-reset` | `--from-block` CLI: cursor forcibly rewound to `fromBlock - 1` | C2 (overwrite) | main loop starts at new cursor | main.ts:132-134 |
| `reindex-restored` | Post-reindex: original cursor restored if bounded and originalCursor > toBlock | C2 (overwrite) | process exits | main.ts:224-226 |
| `follow-wait` | `cursor >= safeBlock` → poll sleep | main loop continue | wakes to re-check tip | main.ts:143-146 |

**Note:** "stalled" and "recovering" from the requirement text (IDX-04 "recovery-after-stall") have NO dedicated code path. The only "recovery-like" mechanism is the catch-block sleep at main.ts:216-220 (5-second retry on loop error). No max-stall timeout, no dead-cursor detector, no backfill-recovery gate exists. This is itself a `docs→code` finding candidate (requirement claims "recovery-after-stall", code has none).

### Invariants (documented vs code)

| Invariant | Documented? | Code enforces? | Anchor |
|-----------|-------------|----------------|--------|
| Cursor advances only within tx containing event inserts | Yes (cursor-manager.ts:70 "MUST be called inside a database transaction") | Caller-enforced only; `advanceCursor` type-signature accepts `DbOrTx` — runtime doesn't verify tx | cursor-manager.ts:70-83 |
| Cursor monotonicity (never rewinds implicitly) | NOT documented | C2 unconditionally overwrites — no `WHERE lastProcessedBlock <= excluded` guard | cursor-manager.ts:58-64 |
| `initializeCursor` is safe on re-init | Yes (cursor-manager.ts:45 "handle re-initialization safely") | Overwrites, no guard | cursor-manager.ts:50-65 |
| Max reorg depth | 128 blocks | reorg-detector.ts:27 const + throw at :140 | reorg-detector.ts:27, 140-143 |
| Gap handling | Implicit: main loop advances `cursor + 1` to `batchEnd`; no gap detector | main.ts:152 `batchStart = cursor + 1n` — never skips | main.ts:152 |

### 227 Deferral #1 (cursor rewind) — Concrete trace

**Call sites of `initializeCursor`:**

| # | main.ts line | Context | Is rewind intentional? |
|---|--------------|---------|------------------------|
| a | 103 | Startup, `existingCursor === null` only | N/A — row didn't exist |
| b | 133 | `fromBlock !== null` reindex mode; rewinds to `fromBlock - 1` | YES (user-requested) |
| c | 225 | Post-reindex: `originalCursor > toBlock` restore | YES (restore to ahead position) |

**Key observation:** None of the 3 call sites is a startup re-init against an existing healthy cursor — call (a) only fires when `existingCursor === null`. So the theoretical "silent rewind" bug in cursor-manager.ts:50-65 is NOT reachable from the current `main.ts` wiring. Expected verdict: LOW finding on the docstring ("safely" is overbroad / misleading) with behavioral PASS. A defensive `WHERE lastProcessedBlock IS NULL OR lastProcessedBlock < excluded` guard would harden against future callers; recommend as INFO `RESOLVED-CODE-FUTURE`.

---

## Reorg-Detector State Machine (IDX-04, 228-01)

### Public operations

| # | Function | File:line | Signature | Effect |
|---|----------|-----------|-----------|--------|
| R1 | `storeBlock(tx, blockData)` | reorg-detector.ts:38 | `(tx, BlockData) -> void` | INSERT `blocks` row with ON CONFLICT DO UPDATE on `blockNumber` — overwrites hash/parentHash/timestamp/eventCount. |
| R2 | `detectReorg(db, client, blockNumber)` | reorg-detector.ts:83 | `(db, client, bigint) -> bigint \| null` | Compares RPC `parentHash` of `blockNumber` against stored hash at `blockNumber - 1`. Walks back up to 128 blocks to find fork. Returns forkBlock or null. Throws if depth > 128. |
| R3 | `rollbackToBlock(db, forkBlock, logger)` | reorg-detector.ts:157 | `(db, bigint, logger) -> void` | Atomic tx: delete from every `PURGEABLE_TABLES` entry where `blockNumber > forkBlock`, update `indexer_cursor.lastProcessedBlock = forkBlock`. |

### Observable states

| State | Definition | Entry | Exit | Anchor |
|-------|------------|-------|------|--------|
| `pre-detect` | Batch fetched, reorg check pending | main loop head | R2 call | main.ts:155 |
| `no-reorg` | R2 returned null | R2 null return | `process-batch` | main.ts:155 → 164 |
| `reorg-detected` | R2 returned forkBlock ≥ 0 | R2 non-null | `rolling-back` | main.ts:156-157 |
| `rolling-back` | R3 tx running | R3 call | `post-rollback` | main.ts:158 |
| `post-rollback` | cursor in-memory set to forkBlock; `continue` | R3 return | next loop iteration | main.ts:159-161 |
| `reorg-depth-exceeded` | R2 threw (MAX_REORG_DEPTH=128) | R2 throw | caught at main.ts:216 `log.error + 5s sleep + retry` | main.ts:216-220, reorg-detector.ts:140-143 |
| `storing-block` | R1 called inside `processBlockBatch` tx | R1 call | tx commit → cursor advances | event-processor.ts (assumed), main.ts:188-201 |

### Invariants (documented vs code)

| Invariant | Documented? | Code behavior | Match? |
|-----------|-------------|---------------|--------|
| MAX_REORG_DEPTH = 128 | Yes (reorg-detector.ts:26, 81) | `for (let depth = 1; depth <= MAX_REORG_DEPTH; depth++)` at :113 | ✓ |
| `storeBlock` idempotent re-processing | Yes (reorg-detector.ts:33) | ON CONFLICT DO UPDATE overwrites hash/parent/timestamp/eventCount | ✓ construct; behavioral question below |
| `rollbackToBlock` atomicity | Yes (reorg-detector.ts:149 "all within a single transaction") | `db.transaction!(async (tx) => { ... })` at :167-181 | ✓ |
| Rollback BEFORE any storeBlock on reorg'd range | NOT documented in reorg-detector.ts; implied by main loop | See trace below | PASS pending edge check |
| Fork point walk-back semantics | Yes (docstring :70-82) | Walks back comparing stored vs rpc at `checkBlock + 1` | ✓ |
| Fork-below-stored-history case | Yes (:127 "No stored block this far back — use this as the fork point") | Returns `checkBlock` when stored empty | ✓ |
| Reorg-to-genesis | Yes (:116 "Reorg all the way to genesis") | `if (checkBlock < 0n) return 0n;` | ✓ |

### 227 Deferral #2 (reorg overwrite ordering) — Full control-flow trace

**Question:** Does `rollbackToBlock(forkBlock)` strictly precede any `storeBlock` on `blockNumber > forkBlock`?

**Trace path in `main.ts` per iteration (lines 138-220):**

1. **L140-141:** `tip = getLatestBlockNumber(client)`; `safeBlock = tip - confirmations`.
2. **L143-147:** If `cursor >= safeBlock`, sleep and `continue` (no storeBlock called).
3. **L150-152:** Compute `batchStart = cursor + 1n`, `batchEnd`.
4. **L155:** `forkBlock = detectReorg(db, client, batchStart)`.
5. **L156-161:** **If `forkBlock !== null`:** log, `rollbackToBlock(db, forkBlock, log)`, set `cursor = forkBlock`, `continue`. **NO storeBlock call in this iteration.**
6. **L164 onward:** Only reached when `forkBlock === null` (no reorg detected) — fetch logs, fetch headers, `processBlockBatch` inside `db.transaction`. `processBlockBatch` invokes `storeBlock` (per event-processor.ts; not re-read in this research but referenced at main.ts:189).
7. **L216-220:** Any thrown error falls to catch, sleep, next iteration.

**Conclusion:** storeBlock in the current iteration is UNREACHABLE when reorg detected. `continue` at main.ts:161 guarantees the only code path to storeBlock (via processBlockBatch at main.ts:189) is gated by `forkBlock === null`. **Expected verdict: PASS for strict ordering.**

**Potential MEDIUM edge case to exercise:** `detectReorg` checks `blockNumber = batchStart` only. The batch spans `[batchStart, batchEnd]`. If a reorg occurs AT a later block in the batch (e.g., at `batchStart + 5`) between the detectReorg call at :155 and the block-header fetch at :178, the stored hash at batchStart passes, but a mid-batch reorg could have `storeBlock` overwrite a canonical row for block `batchStart + 5` without prior rollback. Plan 228-01 should call this out as the edge-case audit row. Likely MEDIUM severity if not mitigated by confirmations (config.confirmations provides the safety margin — document the reliance).

---

## View-Refresh State Machine (IDX-05, 228-02)

### Public operations

| # | Function | File:line | Signature | Effect |
|---|----------|-----------|-----------|--------|
| V1 | `refreshMaterializedViews(db)` | view-refresh.ts:26 | `(db) -> void` | For each view in `ALL_VIEWS`: `db.refreshMaterializedView(view).concurrently()` wrapped in try/catch — errors logged and swallowed. |
| V2 | `ensureViewIndexes(db)` | view-refresh.ts:44 | `(db) -> void` | Creates all `VIEW_UNIQUE_INDEXES` + `ADDITIONAL_INDEXES` with IF NOT EXISTS. Fatal on error (throw at :51). |

### Trigger map

| Trigger site | Condition | Views refreshed | Error handling | Debounce / rate-limit |
|--------------|-----------|-----------------|----------------|-----------------------|
| main.ts:214 `refreshMaterializedViews(db)` | `lag = Number(tip - batchEnd); lag <= config.batchSize` (main.ts:212-213) — i.e., follow-mode (not backfill) | ALL 4 (mv_player_summary, mv_coinflip_top10, mv_affiliate_leaderboard, mv_baf_top4) via `ALL_VIEWS` iteration | per-view try/catch; log.error + continue; overall function never throws | NONE — refresh fires every batch while in follow mode |
| main.ts:112 `ensureViewIndexes(db)` | Startup once (not a refresh trigger; index bootstrap only) | N/A | Fatal on index creation error | N/A |

**Per-view trigger count:** 1 (single collective refresh). Out of `ALL_VIEWS` listing:
| View | Defined at | Has trigger? | On-demand? |
|------|-----------|--------------|------------|
| `mv_player_summary` | views.ts:16-40 | ✓ via V1 loop | No |
| `mv_coinflip_top10` | views.ts:45-56 | ✓ via V1 loop | No |
| `mv_affiliate_leaderboard` | views.ts:61-72 | ✓ via V1 loop | No |
| `mv_baf_top4` | views.ts:77-88 | ✓ via V1 loop | No |

All 4 views covered — no "orphan" view without a trigger.

### 227 Deferral #3 (refresh-failure observability) — Concrete trace

**Code path on refresh failure (view-refresh.ts:26-34):**

```ts
for (const { view, name } of ALL_VIEWS) {
  try {
    await db.refreshMaterializedView(view).concurrently();
  } catch (err) {
    log.error({ view: name, err }, 'Failed to refresh materialized view');
  }
}
```

**Observability inventory:**

| Channel | Present? | Notes |
|---------|----------|-------|
| `log.error` | ✓ | Pino-structured; emits `{view, err}` |
| Prometheus / metric counter | ✗ | No `Counter`, `Gauge`, `histogram` anywhere in `view-refresh.ts` or main.ts post-refresh |
| Alert / PagerDuty / webhook | ✗ | None |
| Retry / backoff | ✗ | Only the next follow-mode batch re-triggers the full refresh |
| Per-view staleness timestamp in DB | ✗ | No `view_refresh_state` table tracked |
| Health check / `/healthz` surface | ✗ | Not exposed |

**Staleness bound on sustained failure:**
- Best case: next batch succeeds (≤ `pollingIntervalMs + batchTime` later).
- Worst case: view never refreshes for an indefinite period; the only signal is a repeating log.error line. A caller of the stale materialized view (API route) sees old data with no indication it's stale.

**Expected verdict:** LOW severity behavioral finding — comment ("a stale view for one block is acceptable") misrepresents the operational bound (could be "stale forever, with only a log line as evidence"). Per D-140 / deferred-ideas, resolution is `RESOLVED-CODE-FUTURE` — planner does NOT design an alerting system in this phase.

### Views.ts ↔ view-refresh.ts cross-reference (D-228-08 second source)

| Source | Staleness claim | Matches code? |
|--------|-----------------|---------------|
| views.ts:4-11 (file header) | "pre-compute expensive joins/aggregations so API endpoints can read directly" — no staleness SLA stated | N/A (no claim to contradict) |
| views.ts:9-10 (header) | "Each view has a corresponding UNIQUE index to enable REFRESH CONCURRENTLY (non-blocking refresh)" | ✓ view-refresh.ts:29 calls `.concurrently()`; ensureViewIndexes covers the UNIQUE index prerequisite |
| view-refresh.ts:1-8 (file header) | "Called after each block batch commit (outside the transaction)" — main.ts:214 IS outside the processBlockBatch tx (tx closes at :201; refresh at :214) | ✓ |
| view-refresh.ts:4-5 | "Refresh is non-fatal — a stale view for one block is acceptable" | ✓ construct; ✗ behavioral bound (see deferral #3) |
| main.ts:211 | "Refresh materialized views (skip during backfill to avoid redundant work)" | ✓ gate at :213 |

**INFO context (not a 228 finding per 226-01 handoff):** `views.ts` declares 4 `pgMaterializedView` entries but no `CREATE MATERIALIZED VIEW` appears in any `.sql` migration file [CITED: 226-01-SCHEMA-MIGRATION-DIFF.md:708-717]. The runtime path for view materialization is therefore assumed to be `drizzle-kit` snapshot-replay OR implicit pushSchema — unverified. Plan 228-02 records this as a single INFO row with `Resolution: INFO-ACCEPTED` or `RESOLVED-CODE-FUTURE`, not a finding.

---

## Backfill-Gate Boundary (227 Deferral #4, 228-01)

**Code at main.ts:211-215:**

```ts
// Refresh materialized views (skip during backfill to avoid redundant work)
const lag = Number(tip - batchEnd);
if (lag <= config.batchSize) {
  await refreshMaterializedViews(db);
}
```

**Concrete edge-case matrix** (`config.batchSize = 2000`, mainnet default):

| Scenario | `tip` | `batchEnd` | `lag` | `lag <= batchSize`? | Intent = follow? | Verdict |
|----------|-------|------------|-------|---------------------|------------------|---------|
| Deep backfill | 1,000,000 | 10,000 | 990,000 | false | No (backfill) | ✓ skip matches intent |
| One batch behind | 1,000,000 | 998,000 | 2,000 | TRUE (2000 ≤ 2000) | Ambiguous — could be "caught up enough" or "still backfilling" | **Boundary case** |
| Follow mode fresh | 1,000,000 | 999,999 | 1 | true | Yes (follow) | ✓ refresh matches intent |
| Exact cursor-at-tip | 1,000,000 | 1,000,000 | 0 | true | Yes (follow) | ✓ |
| One-block-past-safe (confirmations=12, so batchEnd = tip - 12 or earlier) | 1,000,000 | 999,988 | 12 | true | Yes (follow) | ✓ |

**Interpretation of `<=`:**
- `<=` means: "on the LAST backfill batch (where we close the gap within one batchSize), we ALSO refresh."
- `<` would mean: "only refresh strictly inside follow mode (lag < batchSize), skipping the final catch-up batch."

**Behavioral impact of each choice:**
- `<=` (current): 1 extra refresh per backfill completion — `refreshMaterializedViews` is CONCURRENTLY + non-fatal, so even if views are partially unbuilt post-backfill, cost is bounded.
- `<`: skips the catch-up-batch refresh; user must wait for the next follow-mode batch (which may not arrive until after `pollingIntervalMs`) to see fresh views. Worse UX for a healthy chain.

**Expected verdict:** PASS — `<=` is the correct inclusive boundary given the comment's intent ("skip during backfill"). The ambiguous `lag == batchSize` case resolves in favor of refresh, which is conservative. Plan 228-01 audit row: PASS with rationale.

---

## Control-Flow Map: main.ts Wires Everything

Planner trace tasks should reference this map (all anchors verified):

| Stage | main.ts line | State-machine node | Downstream call |
|-------|--------------|--------------------|-----------------|
| Config load | 78 | — | loadConfig |
| DB connect | 82 | — | createDb |
| Viem client | 86 | — | createViemClient |
| ABI registry | 89-90 | — | getAbiForAddress |
| Shutdown hook | 94 | — | setupShutdownHandlers |
| Cursor read | 97 | cursor `absent` vs `resuming` decision | getCursorPosition |
| Cursor init (absent branch) | 103 | cursor: `absent` → `initialized` | initializeCursor |
| Cursor resume | 107-108 | cursor: `resuming` (no code transition) | (none) |
| View-index bootstrap | 112 | view-refresh state: ready | ensureViewIndexes |
| Reindex arg parse | 117 | — | parseReindexArgs |
| Reindex purge | 129 | domain-state: purged | purgeBlockRange |
| Reindex cursor reset | 132-133 | cursor: `reindex-reset` | initializeCursor (context b) |
| Loop head / tip fetch | 140 | — | getLatestBlockNumber |
| Follow-wait guard | 143-147 | cursor: `follow-wait` | setTimeout |
| Batch range compute | 150-152 | — | — |
| Reorg detect | 155 | reorg: `pre-detect` → `no-reorg` or `reorg-detected` | detectReorg |
| Reorg rollback | 158 | reorg: `reorg-detected` → `rolling-back` → `post-rollback`; cursor: mutated to forkBlock | rollbackToBlock |
| Fetch logs | 164 | — | fetchLogs (block-fetcher) |
| Fetch headers | 178 | — | client.getBlock |
| Process batch tx | 188-201 | cursor: `advancing`; reorg: `storing-block` inside tx | processBlockBatch → storeBlock + advanceCursor |
| In-memory cursor bump | 203 | cursor: `advancing` committed | — |
| Reindex termination | 206-209 | — | break |
| View-refresh gate | 212-213 | view-refresh: trigger decision | — |
| View refresh call | 214 | view-refresh: `refreshing-all-views` | refreshMaterializedViews |
| Catch error | 216-220 | loop: `error-backoff` | setTimeout 5000ms |
| Reindex cursor restore | 225 | cursor: `reindex-restored` | initializeCursor (context c) |
| Shutdown | 230-232 | — | pool.end |

---

## Documented-Invariant vs Code-Behavior Matrix

Direct input for plan audit rows. Each row is a pre-assigned 228 plan row.

| # | File:line | Claim (comment or docstring) | Code behavior | Expected verdict | Plan |
|---|-----------|------------------------------|---------------|------------------|------|
| M1 | cursor-manager.ts:45 | "handle re-initialization safely" | Unconditional overwrite; no rewind guard | LOW (comment overclaims); behavioral PASS — no live caller rewinds healthy cursor | 228-01 |
| M2 | cursor-manager.ts:70-72 | "MUST be called inside a database transaction" | Type signature accepts `DbOrTx`; no runtime enforcement | INFO (Tier B — wording accurate but enforcement is convention-only) | 228-01 |
| M3 | reorg-detector.ts:33 | "ON CONFLICT DO UPDATE on blockNumber for idempotent re-processing" | Overwrites hash/parentHash/timestamp/eventCount | PASS construct. Behavioral PASS for ordering (see M4). | 228-01 |
| M4 | reorg-detector.ts (undocumented invariant) | (No comment) — rollback must precede storeBlock on reorg'd block | `main.ts:155-161` guarantees `continue` after rollback | PASS — strict ordering holds for same-iteration. Intra-batch mid-range reorg: MEDIUM-risk edge case; likely mitigated by `config.confirmations`. | 228-01 |
| M5 | reorg-detector.ts:26-27 | `MAX_REORG_DEPTH = 128` | Loop bound at :113; throw at :140 | PASS | 228-01 |
| M6 | reorg-detector.ts:73-76 | Walk-back semantics (compare stored vs rpc at checkBlock+1) | :113-137 implements exactly as described | PASS | 228-01 |
| M7 | reorg-detector.ts:149 "all within a single database transaction" | db.transaction! wraps purge + cursor reset | PASS | 228-01 |
| M8 | main.ts:211 / view-refresh.ts:4 "skip during backfill" | `lag <= config.batchSize` inclusive boundary | PASS (see §Backfill-Gate) | 228-01 |
| M9 | view-refresh.ts:4-5 "Refresh is non-fatal — a stale view for one block is acceptable" | try/catch per view; no metric/alert/retry | LOW — staleness bound is not "one block" under sustained failure | 228-02 |
| M10 | views.ts:9-10 "UNIQUE index to enable REFRESH CONCURRENTLY" | VIEW_UNIQUE_INDEXES × 4; all CREATE UNIQUE INDEX; view-refresh.ts calls .concurrently() | PASS | 228-02 |
| M11 | view-refresh.ts:1-8 "Called after each block batch commit (outside the transaction)" | Call at main.ts:214 is after `await db.transaction(...)` closes at :201 | PASS | 228-02 |
| M12 | (undocumented) Per-view trigger granularity | All 4 views refreshed together, every trigger | INFO — document as design choice, no finding | 228-02 |
| M13 | ROADMAP IDX-04 claim "recovery-after-stall" | No stall detector; only 5-second catch-retry at main.ts:216-220 | INFO/LOW — requirement claims capability not present in code; RESOLVED-DOC or RESOLVED-CODE-FUTURE | 228-01 |
| M14 | REQUIREMENTS IDX-04 "gap handling" | No explicit gap detection; `batchStart = cursor + 1` never skips | INFO (implicit by construction — continuous cursor advance = no gaps); PASS | 228-01 |

---

## Concrete Grep Patterns (for planner tasks)

```bash
# All cursor state transitions — callers of cursor-manager
rg -n 'initializeCursor|advanceCursor|getCursorPosition' /home/zak/Dev/PurgeGame/database/src/

# All reorg-detector call sites
rg -n 'detectReorg|rollbackToBlock|storeBlock' /home/zak/Dev/PurgeGame/database/src/

# View-refresh triggers (exhaustive)
rg -n 'refreshMaterializedViews|refreshMaterializedView|ensureViewIndexes' /home/zak/Dev/PurgeGame/database/src/

# Materialized view declarations (expect exactly 4)
rg -n 'pgMaterializedView' /home/zak/Dev/PurgeGame/database/src/db/schema/

# ON CONFLICT semantics in state-machine files
rg -n 'onConflictDoUpdate|onConflictDoNothing' /home/zak/Dev/PurgeGame/database/src/indexer/

# Invariant / staleness comments
rg -n 'MAX_REORG_DEPTH|idempoten|non-fatal|staleness|concurrently' /home/zak/Dev/PurgeGame/database/src/indexer/ /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts

# Confirmations / safe-block logic
rg -n 'confirmations|safeBlock' /home/zak/Dev/PurgeGame/database/src/indexer/main.ts

# Backfill-gate boundary
rg -n 'lag\s*(<|<=|>)' /home/zak/Dev/PurgeGame/database/src/indexer/main.ts
```

---

## Runtime State Inventory

Not applicable — this is a READ-ONLY behavioral audit. No rename / refactor / migration in scope.

**Nothing found in category:** None of the 5 categories applies. Audit artifacts live entirely under `.planning/phases/228-cursor-reorg-view-refresh-state-machines/`.

---

## Environment Availability

Not applicable — audit phase. All files read from local filesystem (`/home/zak/Dev/PurgeGame/database/`). No external tools, no CI, no runtime. `rg` used for grep patterns — already available.

---

## Validation Architecture

Per 228-CONTEXT.md D-228-02 (catalog-only, no runtime gate, no CI), full unit/integration test validation is not applicable. Spot-recheck per 225/226/227 pattern applies.

### Spot-Recheck Sample Protocol

After each plan completes, the plan executor re-reads 2 randomly-selected audit rows in full and re-verifies the verdict against the nearest 15-line code window. Mirrors 227-03's Re-check 1 / Re-check 2 format.

| Plan | Minimum re-check sample | Evidence bar |
|------|--------------------------|--------------|
| 228-01 | 2 of {M1, M3, M4, M5, M8} | Re-read enclosing function body + caller in main.ts with line anchors |
| 228-02 | 2 of {M9, M10, M11, M12} | Re-read view-refresh.ts full + at least 1 consumer call site in main.ts |

### Quick validation commands

```bash
# Confirm cursor-manager call surface unchanged (expect 3 exports)
rg -n '^export (async )?function' /home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts
# Confirm reorg-detector call surface (expect 3 exports)
rg -n '^export (async )?function' /home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts
# Confirm view-refresh call surface (expect 2 exports)
rg -n '^export (async )?function' /home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts
# Confirm 4 materialized views
rg -c 'pgMaterializedView' /home/zak/Dev/PurgeGame/database/src/db/schema/views.ts
```

---

## Security Domain

`security_enforcement` not enabled for this audit milestone — omitted per config guidance. Incidental security observations (e.g., cursor-rewind as a potential DoS vector) are captured as INFO findings under normal severity taxonomy.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `processBlockBatch` invokes `storeBlock` for each fetched block header (from event-processor.ts) | Cursor State Machine / Control-Flow Map M4 | LOW — `main.ts:189` references `processBlockBatch`; if it doesn't call storeBlock, the reorg ordering invariant is vacuously true. Plan 228-01 trace should re-confirm by reading event-processor.ts. |
| A2 | `advanceCursor` is called inside `processBlockBatch` (i.e., cursor moves transactionally with events) | Cursor state `advancing` | LOW — docstring claim at cursor-manager.ts:70-72; if not, this is itself a MEDIUM behavioral finding. Planner should grep `advanceCursor` usage. |
| A3 | `config.confirmations` is a positive integer ≥ 1 (mitigating intra-batch reorg edge case) | M4 MEDIUM-edge-case | MEDIUM if wrong — if `confirmations === 0`, the intra-batch reorg window is real. Planner should read `config/chains.ts` once. |

---

## Open Questions

1. **Does `processBlockBatch` call `advanceCursor`?** Not verified in this research (event-processor.ts not re-read). Plan 228-01 Wave-1 task should grep + confirm in a single 1-minute spot check.
2. **Runtime creation path for materialized views** — no `CREATE MATERIALIZED VIEW` in `.sql` per 226-01. Is it drizzle-kit `push` or snapshot? Record as INFO context in 228-02; do not pursue as a finding.
3. **`config.confirmations` default values** — not verified here. Plan 228-01 should fetch once for M4 severity calibration.

These are 5-minute verification tasks for the plan executor, not research blockers.

---

## Sources

### Primary (HIGH confidence)

- `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts` (full file read 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts` (full file read 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts` (full file read 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts` (full file read 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/src/indexer/block-fetcher.ts` (full file read 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/src/indexer/purge-block-range.ts` (full file read 2026-04-15)
- `/home/zak/Dev/PurgeGame/database/src/db/schema/views.ts` (full file read 2026-04-15)

### Secondary (HIGH — internal planning artifacts)

- `.planning/phases/228-cursor-reorg-view-refresh-state-machines/228-CONTEXT.md`
- `.planning/phases/227-indexer-event-processing-correctness/227-03-SUMMARY.md` (full deferrals handoff)
- `.planning/phases/227-indexer-event-processing-correctness/227-03-INDEXER-COMMENT-AUDIT.md` (comment-seed table, rows 1-15)
- `.planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md` §Views (lines 708-778)
- `.planning/REQUIREMENTS.md` §IDX-04, IDX-05

### Tertiary

- None — no web lookups needed; this is a pure source-code / internal-docs audit.

## Metadata

**Confidence breakdown:**

- Cursor state machine enumeration: HIGH — full file read + all main.ts callers traced.
- Reorg state machine + ordering invariant: HIGH — full file read + main.ts trace definitive.
- View-refresh triggers + observability inventory: HIGH — only 1 trigger site, exhaustively enumerated.
- Backfill-gate boundary: HIGH — concrete edge-case matrix constructed.
- `processBlockBatch` internal behavior: MEDIUM — not re-read (Assumption A1/A2); plan verifies in first task.
- View runtime creation path: LOW — known gap from 226-01, explicitly deferred.

**Research date:** 2026-04-15
**Valid until:** 2026-05-15 (30 days; state-machine code paths change rarely).

---

## RESEARCH COMPLETE
