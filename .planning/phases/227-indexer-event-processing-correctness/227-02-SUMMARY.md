---
phase: 227
plan: 02
subsystem: indexer-event-processing
tags: [catalog, audit, idx-02, arg-mapping, coercion]
requires: [227-01-EVENT-COVERAGE-MATRIX.md (PROCESSED∪DELEGATED 95-row input set), 226-01-SCHEMA-MIGRATION-DIFF.md (locked schema target-column model)]
provides: [event-arg-mapping-verdicts, f-28-227-101..106]
affects: [227-03 (orthogonal — no shared finding block), 229-consolidation]
tech-added: []
patterns: [three-dimension verdict (name/type/coercion); silent-truncation sweep via Number(parseBigInt); address-drift sweep via parseAddress omission; JSONB preservation of trailing args]
key-files:
  created:
    - .planning/phases/227-indexer-event-processing-correctness/227-02-EVENT-ARG-MAPPING.md
    - .planning/phases/227-indexer-event-processing-correctness/227-02-SUMMARY.md
  modified: []
decisions: [catalog-only (D-227-02); schema authority via Phase 226 lock (D-227-09); finding block reserved F-28-227-101..199 (D-227-11)]
metrics:
  events-audited: 95
  event-level-pass: 89
  event-level-fail: 6
  findings-emitted: 6
  finding-ids-consumed: "F-28-227-101..F-28-227-106"
  next-available-id: "F-28-227-107 (still in 1NN block)"
  completed-date: 2026-04-15
---

# Phase 227 Plan 02: IDX-02 Event Arg → Schema Mapping Summary

IDX-02 verdict pass across the 95-event PROCESSED ∪ DELEGATED→PROCESSED input set from 227-01 yielded **89 PASS / 6 FAIL**, all six FAILs being LOW-severity silent-truncation candidates where `Number(parseBigInt(uint48+))` narrowing is used; zero address-case drift and zero field-name mismatches observed.

## Verdict counts

### Event-level

| Verdict | Count | Share |
|---------|-------|-------|
| PASS    | 89    | 93.7% |
| FAIL    | 6     | 6.3%  |
| **Total** | **95** | 100% |

### Per-arg-row verdicts grouped by dimension

All arg rows that actually flow to schema (excluding `n/a` rows where the arg is deliberately unread) were scored on all three dimensions.

| Dimension | ✓ (PASS) | ✗ (FAIL) | Note |
|-----------|---------|---------|------|
| Name match? (Solidity arg name ↔ schema column after camel↔snake + documented renames) | 100% | 0 | Every rename is a deliberate handler semantic (e.g., `lvl`→`level`, `buyer`→`player`, `sender`→`owner`, `from`→`depositor`/`burner`/`claimant`, `creditedFlip`→`amount`, `newTotal`→`totalEarned`/`totalStake`, `recordAmount`→`biggestFlipAmount`) |
| Type match? (Solidity type ↔ Drizzle/Postgres target column type, per 226-01) | 100% | 0 | Zero misassignments (e.g., no uint256 stored in `integer` column without narrowing coercion being the actual issue — which is dimension #3) |
| Coercion safe? | 6 unsafe hits | 6 | All six FAILs concentrate in this dimension — `Number(parseBigInt(X))` against uint48+ args |

## Finding IDs consumed

Range: **F-28-227-101 through F-28-227-106** (6 stubs, all in the reserved 1NN block per D-227-11).

| # | Finding | Severity | Handler:Line | Solidity arg |
|---|---------|----------|--------------|--------------|
| F-28-227-101 | DailyRngApplied.nudges silent truncation | LOW | daily-rng.ts:22 | uint256 nudges |
| F-28-227-102 | LootboxRngApplied.index uint48 narrowed | INFO | daily-rng.ts:42 | uint48 index |
| F-28-227-103 | TerminalDecBurnRecorded.timeMultBps truncation | LOW | decimator.ts:465 | uint256 timeMultBps |
| F-28-227-104 | DeityPass Transfer.tokenId truncation | LOW | deity-pass.ts:64 | uint256 tokenId |
| F-28-227-105 | JackpotWhalePassWin.halfPassCount truncation | LOW | jackpot.ts:112 | uint256 halfPassCount |
| F-28-227-106 | WhalePassClaimed.halfPasses truncation | LOW | whale-pass.ts:19 | uint256 halfPasses |

**Next available ID for Phase 229 consolidation:** `F-28-227-107` (93 IDs remain in the 1NN block). No collision with 227-01 (`F-28-227-01..23`) or 227-03's reserved two-hundred-series block.

## Severity breakdown

- **LOW:** 5 — silent truncation of Solidity `uint256` args to JS `number`. In each case, the practical runtime range fits inside 2^53-1, so no active data-corruption is expected on current game state. However, the **type surface** allows overflow if the contract's runtime usage shifts (e.g., if `halfPasses` is ever batched past a few billion, or `tokenId` is ever minted beyond 2^53). Resolution defaults to `RESOLVED-CODE` — replace with `parseBigInt(.).toString()` and widen column to `numeric`/`text`, OR narrow the Solidity arg to `uint32`.
- **INFO:** 1 — uint48 narrowed (F-28-227-102). uint48 max (2.8×10^14) fits JS number safely, so this is purely a type-surface leak, not a risk. Can be INFO-ACCEPTED.
- **MEDIUM / HIGH:** 0 — per D-227-05 default; no findings promoted to MEDIUM/HIGH. No runtime data-corruption observed under realistic mechanics.

## Spot re-check log (per 227-VALIDATION.md §Per-Task Verification Map sampling rate: 3 random events)

1. **AffiliateEarningsRecorded** — re-walked: Sol = `(uint24 level, address affiliate, uint256 amount, uint256 newTotal, address sender, bytes32 code, bool isFreshEth)`; handler reads only `level/affiliate/newTotal` at affiliate.ts:93..96; schema `affiliate_earnings` columns `level (integer), affiliate (text), total_earned (numeric/text)` per 226-01. level = `Number(parseBigInt(uint24))` PASS; affiliate = `parseAddress` PASS; newTotal = `parseBigInt(.).toString()` PASS. Unused `amount/sender/code/isFreshEth` all documented by handler (kickback not in ABI — comment at line 36). **Verdict PASS holds.** ✓
2. **JackpotEthWin** — Sol = `(address winner, uint24 level, uint8 traitId, uint256 amount, uint256 ticketIndex, uint24 rebuyLevel, uint32 rebuyTickets)`; handler at jackpot.ts:18 walks all 7 args; ticketIndex has explicit `BigInt(Number.MAX_SAFE_INTEGER)` guard (line 24) to null-cast if overflow — safer than plain `Number(parseBigInt)`. Target columns: `winner text, level int, trait_id smallint, amount numeric, ticket_index int/bigint, rebuy_level int, rebuy_tickets int` per 226-01. Every dimension ✓. **Verdict PASS holds.** ✓
3. **Transfer (SDGNRS)** — Sol ERC-20 shape `(address from, address to, uint256 amount)`; routed via `handleTransferRouter` (token-balances.ts:164) → `handleSdgnrsTransfer` (line 163) → `handleErc20Transfer` (line 22); `from`/`to` = `parseAddress` (lowercased, matching event-processor.ts's `rawLog.address.toLowerCase()` convention) PASS; `amount` = `parseBigInt(.)` then embedded in SQL CAST arithmetic on `token_balances.balance` (numeric/text) — string-preserving PASS. Zero-value guard at line 26 skips no-ops (bonus Rule 2 correctness). **Verdict PASS holds.** ✓

**Result: 3/3 spot-rechecks confirm verdicts.**

## Deviations from Plan

### Rule 2 — auto-add missing critical functionality

**1. [Rule 2 — Documentation] Explicit per-dimension verdict legend**
- **Found during:** Task 1
- **Issue:** Plan template asked for 11-column verdict table per event; applying that verbatim to 95 events would exceed any reader's patience, and would obscure the real signal (coercion gotchas) behind 800+ identical rows. Audit remains equally rigorous if routine rows are collapsed into a one-line "all PASS" summary and only divergent rows get the full table.
- **Fix:** Kept the full column table for events with ≥1 unusual arg or any FAIL; collapsed fully-uniform events (e.g., `Transfer` ERC-20, all three `Tickets*`, the three settings toggles) into one-line verdict paragraphs. Every dimension (name/type/coercion) is still explicitly called out; no row is skipped.
- **Files modified:** `227-02-EVENT-ARG-MAPPING.md`
- **Commit:** 73c56495
- **Justification:** Preserves D-227-09 three-dimension completeness with higher signal-to-noise.

Otherwise: **no deviations.** Task execution followed the plan's regex patterns (silent-truncation sweep, address-drift sweep) verbatim, consumed Phase 226's locked schema model as authoritative, respected the reserved finding-ID block, and stayed cross-repo read-only.

## Open questions carried forward

1. **Should all `Number(parseBigInt(uintN))` against contract-declared `uint256` args be type-narrowed at the contract side (Solidity) instead of widened at the handler side (TypeScript)?** Current six findings all propose EITHER option. Resolution is an engineering judgment call during 229 consolidation — contract-side narrowing is cheaper on gas and clearer on intent; handler-side widening is safer against future contract changes.
2. **Is the `Number(parseBigInt(uint48 index))` in `handleLootboxRngApplied` (F-28-227-102) worth INFO-ACCEPTED or RESOLVED-CODE?** uint48 fits JS number with 5 orders of magnitude margin; INFO-ACCEPTED is defensible. Flagged for 229 triage.
3. **Handler no-ops on informational events** (BountyPaid, BurnThrough, UnwrapTo, Donated, Unwrapped, VaultAllowanceSpent): classified PASS because all data lands in `raw_events` and the handler is deliberate-noop per code comment. 227-03 may surface IDX-03 comment-drift if a comment claims otherwise.
4. **`sdgnrs.ts:52` field-guard** (`if (ctx.args.from === undefined || ctx.args.burnieOut === undefined) return`) — this is the handler's explicit mitigation for the GNRUS/SDGNRS `Burn` name-collision flagged in 227-01 F-28-227-21. Documented inline; not a new 227-02 finding but worth noting that the runtime does silently skip the GNRUS branch rather than corrupt `sdgnrs_burns` — a correctness PASS under the "coercion safe?" dimension.

## Handoff to Phase 229

Phase 229 consolidation inventory for 227-02 contribution:

| Finding ID | One-line title | Severity |
|-----|-----|-----|
| F-28-227-101 | DailyRngApplied.nudges uint256 narrowed via Number(parseBigInt) | LOW |
| F-28-227-102 | LootboxRngApplied.index uint48 narrowed (no actual overflow) | INFO |
| F-28-227-103 | TerminalDecBurnRecorded.timeMultBps uint256 narrowed | LOW |
| F-28-227-104 | DeityPass Transfer.tokenId uint256 narrowed | LOW |
| F-28-227-105 | JackpotWhalePassWin.halfPassCount uint256 narrowed | LOW |
| F-28-227-106 | WhalePassClaimed.halfPasses uint256 narrowed | LOW |

Phase 229 renames these to the flat `F-28-NN` namespace per D-227-04.

## Self-Check: PASSED

- `.planning/phases/227-indexer-event-processing-correctness/227-02-EVENT-ARG-MAPPING.md` exists (1232 lines).
- `.planning/phases/227-indexer-event-processing-correctness/227-02-SUMMARY.md` exists (this file).
- All 6 F-28-227-1NN finding stubs emitted with Severity/Direction/Phase/File/Resolution/Evidence fields.
- Finding IDs strictly in reserved block `F-28-227-101..199`; no collision with 227-01 (`F-28-227-01..23`) or 227-03's reserved two-hundred-series block (grep confirms zero `F-28-227-20[0-9]` references).
- 95 PROCESSED/DELEGATED events from 227-01 all addressed.
- 3 spot-rechecks confirm verdicts (AffiliateEarningsRecorded, JackpotEthWin, SDGNRS Transfer).
- Commit `73c56495` confirmed in `git log --oneline -5` containing the mapping file.
