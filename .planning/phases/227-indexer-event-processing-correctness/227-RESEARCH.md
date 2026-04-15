# Phase 227: Indexer Event Processing Correctness — Research

**Researched:** 2026-04-15
**Domain:** Solidity event declarations ↔ TypeScript viem/Drizzle indexer; catalog-only audit
**Confidence:** HIGH — all findings sourced from direct file inspection of `contracts/*.sol` and `database/src/{indexer,handlers}/`

## Summary

Methodology + plan shape are locked by CONTEXT.md (D-227-06..11). This research closes the six tactical gaps that the planner will hit: event-regex shape, event-processor dispatch shape (it is NOT a switch — it is an object-map `HANDLER_REGISTRY`), arg→field extraction patterns in delegated handlers, type-coercion traps, IDX-03 comment sweep keywords, and the inheritance/interface-event question.

**Primary recommendation:** Extract the event universe with a two-pass ripgrep (single-line then multi-line) against `contracts/*.sol`; build the coverage matrix by cross-referencing the extracted event names against the single object-map in `database/src/handlers/index.ts` (`HANDLER_REGISTRY`); classify missing keys as `UNHANDLED` and commented block-lead comments (`// Admin events (log-only, no handler needed ...`) as `INTENTIONALLY-SKIPPED`. For IDX-02, each handler file in `database/src/handlers/*.ts` follows a strict shape — `parseBigInt(ctx.args.X)` → `.insert(table).values({...}).onConflictDoUpdate(...)` — which makes arg→column mapping extractable via `ctx.args.<arg>` grep plus the target-column names from the Drizzle `.values({...})` literal.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-227-01:** Cross-repo READ-only on `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/` and `/home/zak/Dev/PurgeGame/database/`. Writes only to `.planning/phases/227-indexer-event-processing-correctness/`.
- **D-227-02:** Catalog-only. No runtime gate, no CI wiring, no code edits to audit targets.
- **D-227-03:** Tier A/B threshold for comment-drift (IDX-03). Tier C counted not enumerated; Tier D skipped.
- **D-227-04:** Finding IDs `F-28-227-NN` fresh counter; Phase 229 consolidates into flat `F-28-NN`.
- **D-227-05:** Default finding direction `schema↔handler`; IDX-03 uses `comment→code`. Default resolution `RESOLVED-CODE` unless INFO-ACCEPTED.
- **D-227-06:** Three plans — 227-01 (IDX-01 coverage matrix), 227-02 (IDX-02 arg-field mapping), 227-03 (IDX-03 comment audit).
- **D-227-07:** Event enumeration via regex-parse of `contracts/*.sol`. No ABI JSON dependency. All 17 files in scope.
- **D-227-08:** Case counts as valid coverage if it delegates to `handlers/*.ts` OR processes inline. Missing = UNHANDLED; INTENTIONALLY-SKIPPED requires a justifying comment.
- **D-227-09:** Verdict depth = (1) field-name, (2) type, (3) coercion. All three must PASS for a case to PASS.
- **D-227-10:** View-refresh audited ONLY as IDX-03 comment drift. State-machine semantics stay Phase 228.
- **D-227-11:** Finding-ID blocks — 227-01 from `01`, 227-02 reserves `101+`, 227-03 reserves `201+`.

### Claude's Discretion

- Wave structure, regex specifics, inheritance-flattening strategy, IDX-02 table partitioning, severity thresholds.

### Deferred Ideas (OUT OF SCOPE)

- IDX-04 / IDX-05 state-machine correctness (Phase 228).
- Runtime event-replay harness.
- Contract-side event-emission correctness.
- Indexer performance / latency.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IDX-01 | Every contract event has a `HANDLER_REGISTRY` entry OR a justified skip comment | §Event Extraction, §Classification Rules |
| IDX-02 | Each case handler maps args→schema fields correctly (name + type + coercion) | §Handler Shape, §Arg Mapping Extraction, §Coercion Gotchas |
| IDX-03 | Indexer comments on idempotency/reorg/backfill/view-refresh match code | §Comment-Sweep Patterns |

## Dispatch-Shape Reality Check (critical — overrides stale assumption)

**`event-processor.ts` is NOT a `switch` statement.** It is a two-stage pipeline:

1. `processBlockBatch()` decodes every log via viem, serializes BigInts to decimal strings, batch-inserts into `raw_events` with `.onConflictDoNothing()`.
2. It then loops `decodedRows` and dispatches via `const handler = HANDLER_REGISTRY[row.eventName]; if (handler) await handler(ctx)`.

`HANDLER_REGISTRY` is a flat object-map defined in `database/src/handlers/index.ts` (line 227): `Record<string, EventHandler>` keyed by `eventName`. Missing key = silently skipped (row still lives in `raw_events` but no domain table is written).

**Implication for IDX-01 classification — use these four buckets with these grep anchors:**

| Class | Detection rule | Grep anchor |
|-------|---------------|-------------|
| **PROCESSED** | Event name appears as a key in `HANDLER_REGISTRY`, handler body contains `.insert(` or `.update(` on a schema-imported table | `rg -n "^\s*<EventName>:\s*handle" database/src/handlers/index.ts` |
| **DELEGATED** | Handler in registry routes by `ctx.contractAddress` to sub-calls (e.g., `handleTransferRouter`, `handleQuestCompletedRouter`, `handleDepositRouter`, `handleVaultAllowanceSpentRouter`) | `rg -n "Router\b" database/src/handlers/index.ts` then read function body for `ADDRESS_TO_CONTRACT` / `if (contractName === …)` |
| **INTENTIONALLY-SKIPPED** | Event name appears inside a comment block inside `HANDLER_REGISTRY` body explaining non-registration, e.g. lines 66-68: `// Admin events (log-only, no handler needed -- recorded in raw_events) // LootBoxPresaleStatus, LootboxRngMinLinkBalanceUpdated, LootboxRngThresholdUpdated, // VrfCoordinatorUpdated, StEthStakeFailed, ReverseFlip, OperatorApproval` | `rg -n "^\s*//\s*\w+(\s*,\s*\w+)*\s*$" database/src/handlers/index.ts` inside the `HANDLER_REGISTRY` braces |
| **UNHANDLED** | Event name found in `contracts/*.sol` ∧ NOT a key in `HANDLER_REGISTRY` ∧ NOT in any skip-comment list | set-difference of (event universe) − (PROCESSED ∪ DELEGATED ∪ INTENTIONALLY-SKIPPED) |

**Finding promotion rule (D-227-08):** UNHANDLED is a finding candidate; INTENTIONALLY-SKIPPED requires the justification comment to be within the `HANDLER_REGISTRY` object literal itself (lines 227..end of file) — a comment elsewhere does NOT count as a skip justification.

## Event Extraction from `contracts/*.sol`

### Empirical observations

- All 17 files in `contracts/` have `.sol` extension. No subdirectories.
- Events appear inside `contract` blocks (not inside `interface` blocks — verified: `IDegenerusVaultOwnerGame` interface in `DegenerusGame.sol:62` has no events; no `IDegenerusEvents.sol` style interface-only event file exists). **This simplifies inheritance handling: event declarations are always at the concrete-contract level.**
- Two syntactic forms observed:
  - Single-line: `event AutoRebuyToggled(address indexed player, bool enabled);` (e.g., `DegenerusGame.sol:1468`).
  - Multi-line: `event QuestCompleted(\n    address indexed player,\n    ...\n);` (e.g., `BurnieCoinflip.sol`, and ~30+ others). Multi-line is the majority for events with ≥3 args.
- Event args follow Solidity type syntax: `(uint<N>|int<N>|address|bool|bytes<N>|bytes|string|<UserType>) (indexed )?<name>`.
- No operator overloading on `event` keyword observed; no `event`-named locals or structs observed (grep confirms the keyword `event` is only used for declarations).

### Recommended two-pass extraction

**Pass 1 — single-line events:**

```bash
rg -nH --no-heading \
  '^\s*event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*;' \
  /home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol
```

**Pass 2 — multi-line events** (ripgrep `-U` multiline; stops at first `);`):

```bash
rg -nHU --no-heading --multiline-dotall \
  'event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*;' \
  /home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol
```

Pass 2 is a superset of Pass 1; the planner may use Pass 2 alone and dedupe by file:line. Keep both if they want clean single-line confirmation first.

**Event name extraction (for the coverage-matrix left column):**

```bash
rg -oNU --multiline-dotall \
  'event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(' \
  /home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol \
  --replace '$1' | sort -u
```

**Arg extraction** (for IDX-02 per-event arg list) — capture everything between `(` and `);` and split on `,`:

```bash
# Emits "File:Line  EventName  (raw-args-block)" per event for downstream arg-splitter.
rg -nHU --multiline-dotall --no-heading \
  'event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^;]*?)\)\s*;' \
  /home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol \
  --replace '$1 | $2'
```

Per-arg split rule: split the capture-group on `,`, trim whitespace, then regex each element with `^(\w+(?:\s*\[\s*\])?)\s+(indexed\s+)?(\w+)$` → `(solidityType, indexedFlag, argName)`.

### False-positive traps

| Trap | Mitigation |
|------|-----------|
| `// event Foo(...);` inside a comment | Anchor with `^\s*event\s` (excludes leading `//` / `/*`). Solidity single-line comments start at `//`, block comments span `/* ... */` — the anchor with explicit `^\s*event\s` rejects both. |
| `event` as a struct/variable name | Verified absent in this codebase (`rg -n "\bevent\s+\w+\s*(?:\{|=)" contracts/*.sol` returns zero). Keep the check in the plan as a defensive step. |
| Events declared but never emitted | Out of 227 scope — D-227-10 boundary. Planner may flag in a side-note but NOT as a finding. |
| Duplicate event names across contracts (e.g., `Transfer` in `BurnieCoin`, `DegenerusStonk`, `StakedDegenerusStonk`, `WrappedWrappedXRP`, `DegenerusDeityPass`) | HANDLER_REGISTRY stores one entry keyed by event name. The repo solves this with a ROUTER — see `handleTransferRouter` which dispatches by `ctx.contractAddress`. Coverage matrix must cross-join `(contract, event)` NOT just event — otherwise a `Transfer` on an uncovered contract will look PROCESSED when it is actually routed to the default-branch (likely no-op). |
| Inherited events | None observed — every event lives on the concrete contract that emits it. Confirm during 227-01 by running the extraction and comparing to the `HANDLER_REGISTRY` keys. |

### Duplicate-name cross-join requirement (important)

Events that share a name across contracts (e.g., `Transfer`, `Approval`, `Burn`, `Claim`, `Deposit`) must be classified per-contract, not per-event-name, because routing functions (`handleTransferRouter`, `handleVaultAllowanceSpentRouter`, etc.) gate on `ctx.contractAddress`. The coverage matrix key is `(contractFile, eventName)`; the registry key is `eventName`. A single registry entry may cover 5 contract×event pairs via the router, OR may silently skip some contracts if the router's `ADDRESS_TO_CONTRACT` map omits them.

**Planner action:** For any shared-name event, chase the router's `ADDRESS_TO_CONTRACT` (pattern visible in `handlers/quests.ts:25-29` — lowercased address → contract name → dispatch branch). An address missing from that map is a silent UNHANDLED route, even though the event appears in `HANDLER_REGISTRY`.

## Handler Shape (IDX-02 arg→field extraction)

Every handler file in `database/src/handlers/*.ts` follows the same shape — verified against `quests.ts` and confirmed by inspection of the registry imports:

```typescript
export async function handle<Event>(ctx: HandlerContext): Promise<void> {
  const <fieldX> = parseAddress(ctx.args.<argX>);              // address coercion
  const <fieldY> = Number(parseBigInt(ctx.args.<argY>));       // narrowing coercion
  const <fieldZ> = parseBigInt(ctx.args.<argZ>).toString();    // string-preserving coercion

  await ctx.tx
    .insert(<schemaTable>)
    .values({ <fieldX>, <fieldY>, <fieldZ>, blockNumber: ctx.blockNumber, blockHash: ctx.blockHash })
    .onConflictDoUpdate({ target: [...], set: { ... } });
}
```

### Extraction patterns for IDX-02

| Target | Grep pattern | What it gives you |
|--------|--------------|-------------------|
| Every event-arg read | `rg -n "ctx\.args\.\w+" database/src/handlers/*.ts` | LHS = handler function, RHS = arg name (must match Solidity event-arg name) |
| Coercion wrapper used | `rg -n "(parseBigInt|parseAddress|Number\(parseBigInt|parseBigInt\(.*\)\.toString)" database/src/handlers/*.ts` | Classifies coercion as narrowing / string-preserving / address-lowercase |
| Target table | `rg -n "\.insert\(\w+\)\.values" database/src/handlers/*.ts` | Identifies the schema table the handler writes |
| Target columns | extract the keys of the `.values({...})` object literal following `.insert(...).values(` | Right-hand side of arg→field mapping; cross-check against Phase 226 locked schema model |
| Router dispatch | `rg -n "ADDRESS_TO_CONTRACT|contractName === " database/src/handlers/*.ts` | Identifies delegated-handler branches |

### Idiomatic types / wrappers (verified from `utils/bigint-utils.ts`)

| Wrapper | Input | Output | Semantics |
|---------|-------|--------|-----------|
| `parseBigInt(v)` | `bigint | string | number` | `bigint` | Decimal-string round-trip survivor |
| `parseAddress(v)` | `string` | `string (lowercased)` | **Lowercases** — no EIP-55 checksum preserved. Matches the `event-processor.ts:101` `rawLog.address.toLowerCase()` convention — consistent lowercase everywhere. |
| `Number(parseBigInt(...))` | — | JS `number` | **Narrowing** — unsafe for `uint256`, safe for `uint32`/`uint8`/`uint16` per-field. |
| `parseBigInt(...).toString()` | — | decimal string | **Safe for `uint256`** — target column must be Drizzle `numeric` or `text`, never `integer`/`bigint`. |

## Type-Coercion Gotchas (drop-in list for 227-02)

| Solidity type | Safe TS coercion | Unsafe (finding candidate) | Target column |
|---------------|-----------------|---------------------------|---------------|
| `uint8` / `uint16` / `uint24` / `uint32` | `Number(parseBigInt(x))` | direct `ctx.args.x as number` (works for small ints but loses provenance) | `smallint` / `integer` |
| `uint48` / `uint56` / `uint64` | `parseBigInt(x).toString()` or Drizzle `bigint({mode:'bigint'})` | `Number(parseBigInt(x))` — JS `Number` safe only to 2^53-1 | `bigint` or `numeric`/`text` |
| `uint96` / `uint128` / `uint256` | `parseBigInt(x).toString()` | `Number(parseBigInt(x))` — **silent truncation** past 2^53 | `numeric` or `text` |
| `address` | `parseAddress(x)` (lowercased) | raw `ctx.args.x` (mixed case from viem) — breaks FK joins against other lowercased columns | `text` |
| `bytes32` | `ctx.args.x as string` (viem returns `0x`-prefixed hex) | hex-decode to Buffer | `text` |
| `bool` | `Boolean(ctx.args.x)` or direct (viem already returns `boolean`) | `Number(ctx.args.x)` | `boolean` |
| enum / `uint8` treated as enum | `Number(parseBigInt(x))` with a named enum guard | raw `parseBigInt` (returns `bigint` — Drizzle `smallint` will accept but type surface leaks) | `smallint` |
| `int256` (signed) | `parseBigInt(x).toString()` (decimal handles negatives correctly) | `Number(...)` | `numeric` |

**Key silent-truncation grep** — flag every occurrence where a value-block writes `uint`-wide fields with `Number(...)`:

```bash
rg -nB2 -A1 "Number\(parseBigInt\(ctx\.args\.\w+\)\)" database/src/handlers/*.ts
```

Inspect each hit against the Solidity event-arg type. If the arg is `uint64+`, that's a candidate LOW-severity finding (per D-227-09 coercion-correctness). If the arg is `uint32` or narrower, that's a PASS.

**Address-case drift grep** — flag every ctx.args address read that skips `parseAddress`:

```bash
rg -n "ctx\.args\.\w+" database/src/handlers/*.ts | \
  rg -v "parseAddress|parseBigInt|\.toString"
```

Inspect each hit — if the Solidity arg type is `address`, that's a LOW-severity finding (checksum drift vs the rest of the schema).

## Comment-Sweep Patterns for IDX-03

**Surface:** `database/src/indexer/*.ts` (8 files) + every delegated handler file in `database/src/handlers/*.ts` (the handlers ARE the dispatched behavior — their comments are in-scope per CONTEXT.md "indexer comments ... and delegated handler files").

### Keyword sweep (runs across both directories)

```bash
rg -nBi --pcre2 \
  '(idempoten|on\s*conflict|upsert|re[- ]?org|rollback|canonical|backfill|catch[- ]?up|refresh|materialized|staleness)' \
  /home/zak/Dev/PurgeGame/database/src/indexer/ \
  /home/zak/Dev/PurgeGame/database/src/handlers/ \
  -g '*.ts'
```

Verified seed hits (from this research):

| File:Line | Claim | Code to verify against |
|-----------|-------|------------------------|
| `indexer/cursor-manager.ts:45` | "Uses upsert (ON CONFLICT DO UPDATE) to handle re-initialization safely." | Line 58 `.onConflictDoUpdate({...})` — PASS on first glance; planner confirms the update SET clause matches claim. |
| `indexer/event-processor.ts:118` | (implicit) "chunked to stay under PG's 65535 param limit" `.onConflictDoNothing()` | Is `raw_events` idempotent on (blockHash, transactionHash, logIndex)? Confirm the unique index on `raw_events`. |
| `indexer/reorg-detector.ts:33` | "Uses ON CONFLICT DO UPDATE on blockNumber for idempotent re-processing" | Line 57 `.onConflictDoUpdate` — confirm `target` is `blockNumber`. |
| `indexer/main.ts:111` | "Ensure materialized view indexes exist (idempotent)" | `ensureViewIndexes` — `view-refresh.ts:46` uses `sql.raw(indexSql)` — idempotency depends on `IF NOT EXISTS` in each indexSql string (claim made in `view-refresh.ts:40`). Planner grep `VIEW_UNIQUE_INDEXES` body. |
| `indexer/main.ts:211` | "Refresh materialized views (skip during backfill to avoid redundant work)" | Verify the conditional guarding the `refreshMaterializedViews(db)` call at 214. |
| `indexer/view-refresh.ts:5` | "Refresh is non-fatal -- a stale view for one block is acceptable." | Verify try/catch at lines 28-32 swallows and continues. |
| `indexer/block-fetcher.ts:6` | "Backfill: large batch ranges (e.g., 2000 blocks) to catch up from deployment" | Verify batch-size constant. |
| `indexer/purge-block-range.ts:94` | "Excludes: indexerCursor (no blockNumber), materialized views (playerSummary, ...)" | Verify the purge function's exclusion set matches the comment's list. |

### Tier A/B decision rule (inheriting D-225-04)

- **Tier A** — comment describes a specific invariant (idempotency target, reorg depth, refresh trigger) and the code EITHER (a) does not implement it, OR (b) implements a DIFFERENT invariant. Example: comment says "idempotent on (player, day)" but `.onConflictDoUpdate` target is `[player]`.
- **Tier B** — comment is partially correct / ambiguous / omits a branch. Example: comment says "upserts streak" but code has a conditional branch that SETS streak only under certain contractName values.
- **Tier C** — missing comment entirely. Counted, not enumerated. D-227-03.
- **Tier D** — typo, stale method name. Skipped.

### Scope-boundary enforcement (D-227-10)

If a comment claim falls under IDX-04/IDX-05 territory (cursor state-machine correctness, reorg-depth enforcement, view-refresh debounce logic) — log as a 227 comment-drift finding ONLY if the COMMENT itself is wrong about observable behavior. Do NOT expand into a finding about whether the refresh/cursor/rollback logic is correct. That is Phase 228.

**Decision test:** "Could this finding be described without using the word 'behavior'?" If no, it's 228. If yes (it's about what the comment *says*), it's 227.

## Arg→Field Mapping Extraction (concrete recipe for 227-02)

For each event in the universe:

1. From `contracts/*.sol`: extract `(argName, solidityType, indexed)` tuples via the multi-line regex above.
2. From `handlers/index.ts`: locate `HANDLER_REGISTRY[<EventName>]` → handler function symbol.
3. From the handler file: read the function body. Extract `(ctx.args.<argName>, coercion wrapper, TS variable name)` and `.values({...})` object-literal keys.
4. From Phase 226 schema model (`226-01-SCHEMA-MIGRATION-DIFF.md`): look up the target table's column definitions.
5. Build a per-event row:

   | Event | Arg | Solidity type | Coercion wrapper | TS field | Schema column | Schema type | Name match? | Type match? | Coercion safe? | Verdict |
   |---|---|---|---|---|---|---|---|---|---|---|
   | `QuestSlotRolled` | `day` | `uint32` | `Number(parseBigInt(…))` | `day` | `day` | `integer` | ✓ | ✓ | ✓ | PASS |
   | `QuestSlotRolled` | `slot` | `uint8` | `Number(parseBigInt(…))` | `slot` | `slot` | `smallint` | ✓ | ✓ | ✓ | PASS |

6. FAIL any row = event-level FAIL → F-28-227-101+ finding.

## Inherited Events

**Finding:** Zero interface-only event declarations in this codebase. Every event lives on a concrete contract. `IDegenerusVaultOwnerGame` (the only interface in `DegenerusGame.sol`) declares functions, not events. No `IDegenerusEvents.sol` file.

**Implication:** The planner does NOT need a flattening pass. Events map 1:1 to their declaring contract file. Shared event names (`Transfer`, `Approval`, `Burn`, `Claim`, `Deposit`, `QuestCompleted`) are NOT inheritance — they are independent declarations on independent contracts, routed at runtime by `ctx.contractAddress`.

Cross-join `(contractFile, eventName)` is still required for these shared names (see §Duplicate-Name Cross-Join Requirement).

## Known Pitfalls

1. **Assuming `switch/case`** — old indexer patterns use switch statements; this one uses a `Record<string, EventHandler>` object-map. Any plan task that says "find the case statement" will return zero results. Use "find the registry entry."
2. **Assuming every event in `contracts/*.sol` is emitted** — out of scope per CONTEXT.md. An event declared but never emitted still counts for IDX-01 (the indexer's job is to have a registered case OR a justified skip). Whether the contract emits it is 220/221/222/223 territory.
3. **`raw_events` is the unconditional landing zone** — every decoded event hits `raw_events` via line 118. HANDLER_REGISTRY only controls *domain-table* writes. "Silently skipped" means "no domain table write" — the raw row is always there. IDX-01 UNHANDLED classification is about domain-table coverage.
4. **Router-hidden gaps** — `handleTransferRouter` routes Transfer events by contract. If the router's address map omits a contract that DOES emit Transfer, the registry appears to cover it but the dispatched code falls through. Read every router body.
5. **`new-events.ts`** — confirmed present; contains Phase 16 / v1.3 additions (`DeityPassPurchased`, `GameOverDrained`, `FinalSwept`, `BoonConsumed`, `AdminSwapEthForStEth`, `AdminStakeEthForStEth`, `LinkEthFeedUpdated`, `DailyWinningTraits`). Natural candidate for IDX-01 gaps if Phase 21 added GNRUS events without updating this file (but `gnrus-governance.ts` is also imported, so a quick check suffices).
6. **Empty `args` vs missing `args`** — viem's `decodeLog` may produce an `args` object without all expected keys if the ABI is stale. `parseBigInt(undefined)` throws. That's a runtime failure mode, not a comment-drift or coverage finding — note as INFO if observed.

## Validation Architecture

**Test framework:** None for this audit. Catalog-only per D-227-02 — no test execution, no CI gate.

### Phase-audit validation rubric (self-check per plan)

| Plan | Audit verification | Spot re-check sampling |
|------|-------------------|------------------------|
| 227-01 | All contracts/*.sol events extracted + classified exactly once as PROCESSED / DELEGATED / INTENTIONALLY-SKIPPED / UNHANDLED | Spot-check 5 random events end-to-end: grep contract for `emit <EventName>`, confirm the registry key, read the handler, confirm domain-table write OR justified skip |
| 227-02 | Every PROCESSED/DELEGATED event has a full arg-row verdict | Spot-check 3 random handlers: manually walk each arg through coercion + target-column type against Phase 226's schema model |
| 227-03 | Every Tier-A/B comment claim has a PASS/FAIL verdict + file:line citation on both sides | Spot-check 2 random claims by reading the full surrounding function body, not just the claimed lines |

### Sampling rate

- Per plan: spot-recheck ≥3 rows at random after the full pass to catch systemic extraction bugs.
- Phase gate: 227-VERIFICATION.md must cite (a) event-universe count, (b) classification sum = universe count, (c) handler-registry key count, and confirm the set-theoretic closure.

### Coverage completeness check

The sum `|PROCESSED| + |DELEGATED| + |INTENTIONALLY-SKIPPED| + |UNHANDLED|` must equal the event-universe count extracted in 227-01 Step 1. Any discrepancy means the extraction or classification missed a row — rerun the regex.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `contracts/` has no subdirectories and only 17 `.sol` files | §Event Extraction | Planner misses events in subdirs — low risk, `ls` confirmed flat |
| A2 | No events declared inside `interface` blocks | §Inherited Events | Planner undercounts the event universe; mitigation is trivial — add `rg "interface.*\{"` sanity check |
| A3 | `HANDLER_REGISTRY` is the sole dispatch map | §Dispatch-Shape | If a second dispatch path exists (e.g., called directly from `main.ts`), PROCESSED rate is underestimated. Low risk — verified by reading `event-processor.ts` |
| A4 | Coverage matrix must key by `(contract, event)` not `event` alone | §Duplicate-Name Cross-Join | If planner keys by event name only, shared-name events hide silent gaps. Medium risk — explicit in §Duplicate-Name |

## Open Questions

1. **Does `raw_events` have a unique index on `(blockHash, transactionHash, logIndex)`?** The `.onConflictDoNothing()` at `event-processor.ts:118` is only meaningful if such a unique exists. Relevant for an IDX-03 comment-claim check. Planner confirms against Phase 226's schema model during 227-03.
2. **Does `handleTransferRouter` have a fall-through warn/log for unknown contractAddresses?** If not, unknown-contract Transfer events are silently dropped (finding candidate). Read during 227-01 router analysis.
3. **Are Phase 16 `new-events.ts` events all emitted by contracts in the current `contracts/*.sol`?** If any are emitted only by contracts removed during the v27.x audit, they're orphan handlers (the inverse IDX-01 direction — handler with no event). CONTEXT.md doesn't mark this direction in scope, but it's cheap to catch.

## Sources

### Primary (HIGH confidence — direct inspection 2026-04-15)

- `/home/zak/Dev/PurgeGame/database/src/indexer/event-processor.ts` — dispatch shape (object-map, not switch)
- `/home/zak/Dev/PurgeGame/database/src/handlers/index.ts` lines 1-227+ — `HANDLER_REGISTRY` definition, composite handlers, import surface
- `/home/zak/Dev/PurgeGame/database/src/handlers/types.ts` — HandlerContext type, EventHandler type
- `/home/zak/Dev/PurgeGame/database/src/handlers/quests.ts` — canonical handler shape (ctx.args → parseX → .insert().values().onConflictDoUpdate())
- `/home/zak/Dev/PurgeGame/database/src/utils/bigint-utils.ts` — `parseBigInt` / `parseAddress` coercion semantics
- `/home/zak/Dev/PurgeGame/database/src/indexer/view-refresh.ts` — comment claims for IDX-03 seed list
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/*.sol` (17 files) — event declarations, both single-line and multi-line
- `.planning/phases/226-schema-migration-orphan-audit/226-RESEARCH.md` — format precedent and Drizzle schema conventions
- `.planning/phases/226-schema-migration-orphan-audit/226-01-SCHEMA-MIGRATION-DIFF.md` — target-column ground truth for IDX-02

### Secondary (MEDIUM)

- `.planning/phases/227-indexer-event-processing-correctness/227-CONTEXT.md` — locked decisions D-227-01..11
- Project `CLAUDE.md` memory references — audit conventions, no-code-changes rule

## Metadata

**Confidence breakdown:**

- Event extraction: HIGH — two-pass regex validated against actual contract output
- Dispatch shape: HIGH — reading `event-processor.ts` and `handlers/index.ts` confirms object-map, not switch
- Handler shape: HIGH — `quests.ts` canonical, pattern consistent across imports
- Coercion gotchas: HIGH — `bigint-utils.ts` read verbatim
- Comment sweep: HIGH — seed list extracted by live ripgrep
- Inherited events: HIGH — grep confirms no interface events
- Shared-name routing: HIGH — router pattern visible in `quests.ts:25-29`, `ADDRESS_TO_CONTRACT` idiom

**Research date:** 2026-04-15
**Valid until:** stable until either `HANDLER_REGISTRY` is refactored or `contracts/*.sol` adds a new interface-event pattern — 30 days.

## RESEARCH COMPLETE

**Phase:** 227 — Indexer Event Processing Correctness
**Confidence:** HIGH

### Key Findings

- Dispatch is `HANDLER_REGISTRY: Record<string, EventHandler>` in `database/src/handlers/index.ts:227`, NOT a switch statement. Classification grep must target the object-map, not a switch.
- Zero interface-only event declarations — no inheritance-flattening needed. Events live on concrete contracts.
- Shared-name events (`Transfer`, `Approval`, `Burn`, `Claim`, `Deposit`, `QuestCompleted`) require `(contract, event)` cross-join because runtime routing happens via `ctx.contractAddress` through `ADDRESS_TO_CONTRACT` maps in router handlers.
- Coercion wrappers `parseBigInt` / `parseAddress` are standardized in `utils/bigint-utils.ts`; silent-truncation risk concentrates in `Number(parseBigInt(...))` calls against `uint48`+ args.
- `INTENTIONALLY-SKIPPED` justification comments live INSIDE the `HANDLER_REGISTRY` object literal (see line 66-68 admin-events block); comments elsewhere don't count.
- `raw_events` is the unconditional landing zone — missing registry key = no domain table write, but raw log row is still stored.

### File Created

`/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/227-indexer-event-processing-correctness/227-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Event extraction | HIGH | Two-pass regex verified against multi-line examples in BurnieCoinflip.sol |
| Dispatch shape | HIGH | Direct read of event-processor.ts + handlers/index.ts |
| Handler shape / coercion | HIGH | quests.ts canonical + bigint-utils.ts read verbatim |
| Comment sweep | HIGH | Seed hits enumerated from live ripgrep |
| Inheritance | HIGH | grep confirms zero interface-declared events |

### Open Questions

- Unique index on `raw_events` (confirm in 227-03 via Phase 226 schema).
- Router fall-through behavior for unknown contract addresses.
- `new-events.ts` inverse-orphan check (handler with no live event).

### Ready for Planning

Research complete. Planner can draft 227-01 (event universe + classification), 227-02 (arg-row verdicts), 227-03 (Tier A/B comment audit) using the regex patterns, classification rules, and coercion table above.
