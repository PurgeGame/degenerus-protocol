---
phase: 227
plan: 03
requirement: IDX-03
deliverable: Indexer comment-drift audit (Tier A/B) for database/src/indexer/*.ts + database/src/handlers/*.ts
finding_id_block: F-28-227-201..299
direction: comment→code
tier_threshold: A, B (C counted only; D skipped)
date: 2026-04-15
---

# Phase 227 Plan 03 — Indexer Comment Correctness Audit

**Scope:** comment claims about idempotency, reorg safety, backfill, view-refresh trigger semantics in the indexer + delegated handler layer.

**Methodology:** start from the 8 RESEARCH-seeded hits, expand via keyword sweep (`idempoten|on\s*conflict|upsert|re[- ]?org|rollback|canonical|backfill|catch[- ]?up|refresh|materialized|staleness`), classify each comment-drift per D-225-04 / D-227-03 tier rule, apply D-227-10 scope guard before filing.

**Direction:** `comment→code` (per D-227-05).

**Tier rule (reminder):** Tier A = comment describes a specific invariant the code does not / differently implements. Tier B = partial / ambiguous / omits a branch. Tier C = missing comment (counted, not enumerated). Tier D = typo / stale method name (skipped).

**Scope guard (D-227-10):** "Could this finding be described without using the word 'behavior'?" If NO → defer to Phase 228. A comment may be literally accurate about what the code does yet the underlying behavior be wrong — in that case 228 owns the behavior finding.

---

## Audit Table

### Seed rows (all 8 verbatim from RESEARCH.md)

| # | File:line | Comment claim (quoted) | Code reference | Tier | Verdict | Notes |
|---|-----------|------------------------|----------------|------|---------|-------|
| 1 | `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45` | "Uses upsert (ON CONFLICT DO UPDATE) to handle re-initialization safely." | cursor-manager.ts:51-64 | — | PASS | `.insert(indexerCursor).values({id:1,...}).onConflictDoUpdate({target:indexerCursor.id, set:{lastProcessedBlock, updatedAt}})`. Comment literally describes the construct used. Whether "safely" behaviorally protects an existing cursor from being reset to an older `startBlock` is a 228-territory state-machine question — scope-guard: `DEFER-228 (cursor rewind semantics)`. |
| 2 | `/home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts:118` | "chunked to stay under PG's 65535 param limit" + `.onConflictDoNothing()` implicit idempotency on `raw_events` | event-processor.ts:114-119 | — | PASS | 11 cols × 500 rows = 5500 params, well under 65535 (comment at line 116 explicit). Idempotency target is the `raw_events_unique (blockNumber, logIndex, transactionHash)` unique index, confirmed by Phase 226 `226-01-SCHEMA-MIGRATION-DIFF.md:126` (`raw_events_unique` UNIQUE index PASS) and `226-02-MIGRATION-TRACE.md:57`. Comment accurate. |
| 3 | `/home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:33` | "Uses ON CONFLICT DO UPDATE on blockNumber for idempotent re-processing" | reorg-detector.ts:48-66 | — | PASS | `.onConflictDoUpdate({target: blocks.blockNumber, set:{blockHash, parentHash, timestamp, eventCount}})`. Target is `blockNumber` as claimed. Re-processing overwrites hash/parent/ts fields — matches "idempotent re-processing" wording. Behavioral question of whether overwriting a reorg'd block hash before rollback is the correct semantics is 228 territory — `DEFER-228 (reorg-overwrite ordering)`. |
| 4 | `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts:111` | "Ensure materialized view indexes exist (idempotent)" | main.ts:112 → view-refresh.ts:44-55 → `VIEW_UNIQUE_INDEXES` + `ADDITIONAL_INDEXES` | — | PASS | All 4 `VIEW_UNIQUE_INDEXES` entries use `CREATE UNIQUE INDEX IF NOT EXISTS` (views.ts:106-109). All 9 `ADDITIONAL_INDEXES` entries use `CREATE INDEX IF NOT EXISTS` (indexes.ts:8-24). 13/13 idempotent. |
| 5 | `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts:211` | "Refresh materialized views (skip during backfill to avoid redundant work)" | main.ts:212-215 | — | PASS | Gate is `const lag = Number(tip - batchEnd); if (lag <= config.batchSize) { await refreshMaterializedViews(db); }`. During backfill `lag > batchSize`, so refresh is skipped — matches comment. |
| 6 | `/home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:5` | "Refresh is non-fatal -- a stale view for one block is acceptable." | view-refresh.ts:26-34 | — | PASS | try/catch at 28-32 logs `log.error({view, err}, 'Failed to refresh materialized view')` and continues the for-loop over `ALL_VIEWS`. Non-fatal confirmed. |
| 7 | `/home/zak/Dev/PurgeGame/database/src/indexer/block-fetcher.ts:6` | "Backfill: large batch ranges (e.g., 2000 blocks) to catch up from deployment" | `database/src/config/chains.ts:11-12` | — | PASS | Chain defaults: mainnet `batchSize: 2000`, sepolia `2000`, hardhat `10000`. "e.g., 2000" matches the mainnet/sepolia default exactly. |
| 8 | `/home/zak/Dev/PurgeGame/database/src/indexer/purge-block-range.ts:94` | "Excludes: indexerCursor (no blockNumber), materialized views (playerSummary, coinflipTop10, affiliateLeaderboard, bafTop4)" | purge-block-range.ts:98-166 + views.ts:93-98 | — | PASS | `PURGEABLE_TABLES` has exactly 67 entries (verified via `awk ... grep -cE '^\s+[a-zA-Z]+,' == 67`), matching the block comment's "67 tables" count at line 93. ALL_VIEWS exposes exactly `{mv_player_summary, mv_coinflip_top10, mv_affiliate_leaderboard, mv_baf_top4}` — the 4-view exclusion list in the comment matches ALL_VIEWS 1:1. `indexerCursor` is not in PURGEABLE_TABLES — matches "no blockNumber" exclusion. |

### Keyword-sweep expansion rows (new findings beyond the 8 seeds)

| # | File:line | Comment claim (quoted) | Code reference | Tier | Verdict | Notes |
|---|-----------|------------------------|----------------|------|---------|-------|
| 9 | `/home/zak/Dev/PurgeGame/database/src/handlers/new-events.ts:4-5` | "All handlers are simple append-only inserts following the canonical pattern from whale-pass.ts. **No upsert**, no composite logic." | new-events.ts:67-96 (`handleGameOverDrained`) | B | FAIL | `handleGameOverDrained` performs `.insert(prizePools).values({...}).onConflictDoUpdate({target: prizePools.id, set:{…}})` — an upsert with composite side-effect on the `prize_pools` singleton, directly contradicting the file-level "No upsert, no composite logic" claim. Other handlers in the file are append-only as claimed, so this is Tier B (partially correct, omits a branch). → F-28-227-201. |
| 10 | `/home/zak/Dev/PurgeGame/database/src/handlers/lootbox.ts:5` | "All handlers are append-only (insert, no upsert). Each event creates a new historical record." | lootbox.ts + handlers/index.ts:191-194 (`handleTraitsGeneratedComposite`) and handlers/traits-generated.ts:46-63 | B | FAIL | Lootbox's `handleTraitsGenerated` is registered through the `handleTraitsGeneratedComposite` which also invokes `handleTraitsGeneratedBuckets` (traits-generated.ts) that DOES upsert into `trait_burn_tickets` via `.onConflictDoUpdate({target:[level,traitId,player], set:{ticketCount: existing + c}})`. The claim "All handlers are append-only" in lootbox.ts's own docstring holds strictly for the lootbox.ts module itself, but the file header doesn't qualify "within this module" — it reads as a blanket property of the lootbox event-handling surface. Given TraitsGenerated is documented as a lootbox event (line 15 lists `handleTraitsGenerated` as a lootbox-file handler) and the composite adds an upsert branch, the comment is incomplete. Tier B. → F-28-227-202. |
| 11 | `/home/zak/Dev/PurgeGame/database/src/handlers/coinflip.ts:91` | "for the resolved day. Uses onConflictDoNothing for idempotency." | coinflip.ts:117 | — | PASS | Line 117 is `.onConflictDoNothing()` — matches. |
| 12 | `/home/zak/Dev/PurgeGame/database/src/handlers/traits-generated.ts:8-10` | "Idempotency: each event's (blockNumber, logIndex) is recorded in trait_burn_ticket_processed_logs and checked up front. Replay/backfill against an already-processed log is a no-op." | traits-generated.ts:33-63 | — | PASS | Upfront existence check at 33-41 short-circuits via `if ((existing as any[]).length > 0) return;`. Post-work insert at 60-63 uses `.onConflictDoNothing()`. Matches. |
| 13 | `/home/zak/Dev/PurgeGame/database/src/handlers/degenerette.ts:4` | "All handlers are append-only (insert, no upsert)." | degenerette.ts full file | — | PASS | Zero `onConflict` matches in file — matches claim. |
| 14 | `/home/zak/Dev/PurgeGame/database/src/handlers/gnrus-governance.ts:4-5` | "All handlers are simple append-only inserts ... No upsert, no composite logic." | gnrus-governance.ts full file | — | PASS | Zero `onConflict` matches in file — matches claim. |
| 15 | `/home/zak/Dev/PurgeGame/database/src/handlers/token-balances.ts:5-6` | "onConflictDoUpdate to avoid read-before-write race conditions." | token-balances.ts:67,88,108,128,212 | — | PASS | 5 distinct `.onConflictDoUpdate` call sites; claim accurate. |

---

## Finding Stubs (FAIL rows → F-28-227-201+)

#### F-28-227-201: `new-events.ts` file header claims "No upsert" but `handleGameOverDrained` upserts `prize_pools`

- **Severity:** INFO (Tier B — comment partially correct, omits composite branch)
- **Direction:** comment→code
- **Phase:** 227
- **Requirement:** IDX-03
- **File:** `/home/zak/Dev/PurgeGame/database/src/handlers/new-events.ts:4-5`
- **Comment claim:** "All handlers are simple append-only inserts following the canonical pattern from whale-pass.ts. No upsert, no composite logic."
- **Actual code:** `handleGameOverDrained` (lines 67-96) performs an `.onConflictDoUpdate` upsert on `prize_pools` (singleton id=1), zeroing all pool fields when a `GameOverDrained` event fires — this is both an upsert AND composite side-effect on a table outside the event's primary target.
- **Resolution:** RESOLVED-DOC (patch the header comment to note the GameOverDrained upsert branch on prize_pools, or split new-events.ts into pure append-only vs composite).
- **Scope-guard:** Describes comment→code drift, not behavior. The upsert on prize_pools is presumably intentional per on-chain semantics. Per D-227-10, whether zeroing pools on `GameOverDrained` is the correct state-machine action is out of scope (Phase 228 / contract audit territory).

#### F-28-227-202: `lootbox.ts` file header claims "All handlers are append-only" but the registered composite path includes a `trait_burn_tickets` upsert

- **Severity:** INFO (Tier B)
- **Direction:** comment→code
- **Phase:** 227
- **Requirement:** IDX-03
- **File:** `/home/zak/Dev/PurgeGame/database/src/handlers/lootbox.ts:5`
- **Comment claim:** "All handlers are append-only (insert, no upsert). Each event creates a new historical record."
- **Actual code:** `handleTraitsGenerated` is listed in the file docstring as a lootbox handler (line 15), but its registry entry (`handlers/index.ts:191-194`) wraps it in `handleTraitsGeneratedComposite`, which also calls `handleTraitsGeneratedBuckets` (traits-generated.ts:46-56) — that performs `.onConflictDoUpdate` on `trait_burn_tickets` with SQL-side ticketCount addition. The lootbox.ts file header thus mis-states the full dispatch surface for one of its listed handlers.
- **Resolution:** RESOLVED-DOC (add a caveat line in lootbox.ts's file docstring noting the TraitsGenerated composite dispatch and its upsert branch, or scope the "All handlers are append-only" claim to exclude `handleTraitsGenerated`).
- **Scope-guard:** Describes comment→code drift about what the dispatch surface does, not whether the upsert itself is correct. Per D-227-10, correctness of the `ticket_count` running-sum semantics is 228 / replay-layer territory.

---

## Deferred to Phase 228

Scope-guard D-227-10 flagged the following claims for Phase 228 state-machine analysis (NOT filed as 227 findings — their comments accurately describe the code construct used, but the underlying behavior may still warrant a behavioral finding):

| File:line | Claim | Reason deferred |
|-----------|-------|-----------------|
| `/home/zak/Dev/PurgeGame/database/src/indexer/cursor-manager.ts:45` | "handle re-initialization safely" | `initializeCursor(db, startBlock)` called on an existing row overwrites `lastProcessedBlock = startBlock` unconditionally — behavioral question whether a re-init should rewind a cursor that was already ahead. This is IDX-04/IDX-05 state-machine territory, not comment-drift. Comment PASSes as-written; behavioral concern is 228. |
| `/home/zak/Dev/PurgeGame/database/src/indexer/reorg-detector.ts:33` | "idempotent re-processing" on blocks | `storeBlock` overwrites `blockHash`, `parentHash`, `timestamp`, `eventCount` for an existing `blockNumber` — if called during a reorg WITHOUT a prior rollback, the stored hash silently changes. Comment's construct claim (ON CONFLICT DO UPDATE on blockNumber) PASSes; behavioral ordering concern (whether rollback is guaranteed to precede re-store) is 228. |
| `/home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts:5` | "a stale view for one block is acceptable" | Construct confirmed (try/catch swallows). Behavioral question: is one-block staleness actually the only failure mode, or can failures persist across many blocks without observation (the only feedback is a log.error)? Refresh debounce / staleness policy is 228. |
| `/home/zak/Dev/PurgeGame/database/src/indexer/main.ts:211` | "skip during backfill to avoid redundant work" | Gate `lag <= config.batchSize` PASSes. Behavioral: whether the threshold is the correct boundary (e.g., last non-backfill batch may still skip if cursor lands on block == tip - batchSize) is 228. |

---

## Tier Tallies

- **Tier A (enumerated):** 0
- **Tier B (enumerated):** 2 (F-28-227-201, F-28-227-202)
- **Tier C (counted, not enumerated):** see below
- **Tier D (skipped):** 0 notable (no obvious stale-method-name drift found during sweep)

### Tier C count — missing-docstring functions touching idempotency / reorg / backfill / view-refresh semantics

Counted, per D-227-03, not enumerated. Based on reading `indexer/*.ts` + `handlers/*.ts`:

- **indexer/** (8 files): every public function has at least a brief docstring. Tier C within indexer/ = **0**.
- **handlers/** (30 files, sampled): handlers consistently have function-level JSDoc. File-level "pattern" comments exist on the top of most files. No systematically missing docstring on a handler that writes with `onConflict*`. Tier C within handlers/ ≈ **0 systemic; spot-checks found 0 bare handlers without idempotency-relevant comment**.

**Tier C total: 0 systemic gaps identified.**

---

## Verdict Summary

| Verdict | Count |
|---------|-------|
| PASS    | 13 (seeds 1-8 + rows 11-15) |
| FAIL    | 2 (rows 9-10 → F-28-227-201, F-28-227-202) |

**Findings consumed:** F-28-227-201, F-28-227-202.
**Next available finding ID in reserved block:** F-28-227-203.
**Collision check:** disjoint from 227-01 (`F-28-227-01+`) and 227-02 (`F-28-227-101+`) per D-227-11.

---

## Scope-Boundary Reminder

This plan audits COMMENT correctness only. Cursor rewind behavior, reorg-overwrite ordering, view-refresh debounce semantics, and backfill-gate boundary correctness are Phase 228 territory (IDX-04 / IDX-05). See Deferred-to-228 section for the handoff list.
