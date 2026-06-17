# Phase 417 COLMAP — Summary

**Done:** 2026-06-17 · **Requirements:** COLMAP-01..04 ✅ · **Method:** 12-slice parallel Workflow fan-out (wf_7cad471d-472) → synthesis. Tree re-verified frozen `0dd445a6` after the fan-out.

## Authoritative column map (`417-COLMAP.md`, 499 L) + 12 slice maps

| Metric | Count |
|--------|------:|
| Column-reachable functions | 322 |
| Revert sites | 393 |
| Loops | 81 (17 unbounded/input-sized) |
| Permanent-revert candidates | 58 |
| Delegatecall storage-writes | 192 |
| Nested delegatecalls | 36 |

- **COLMAP-01** call graph: every entry (`advanceGame`, `mintFlip`, `rawFulfillRandomWords`, the buy/purchase paths, the onlySelf terminal stubs, etc.) → internal → delegatecall (13 modules + nested Boon + raw afking `delegatecall(msg.data)`) → synchronous external (FLIP/Coinflip/Vault/sDGNRS/Affiliate).
- **COLMAP-02** revert-site inventory (393, tagged transient vs permanent-candidate).
- **COLMAP-03** loop inventory (81, bounded vs unbounded) — 17 unbounded feed BRICK-04 gas ceiling.
- **COLMAP-04** delegatecall-write → slot table mapped to the authoritative `forge inspect DegenerusGame storageLayout` (87 slots); multi-module packed slots flagged (slot 5, 7, 20, 34, 40, 44, 51, 54…).

## Load-bearing hunt handoff (seeds 418-423)

The synth produced a per-phase hotspot list + 9 sharp openQuestions. Top leads:
- **BRICK #1 (P20):** `sDGNRS resolveRedemptionPeriod:756` uint96 underflow fires on EVERY advance with a stamped pool — if the cumulative scalar can drift below the reconstructed segregatedMax, **advance wedges forever** (CATASTROPHE-class). → 418.
- **BRICK-04 unbounded loops:** `_backfillOrphanedLootboxIndices:1894` + ≤120 `_backfillGapDays` same tx; `runBafJackpot:1930`; `resolveRedemptionLootbox:951` (no budget cap); `handleGameOverDrain:106` deity loop vs 16.7M. → 418.
- **DELEGATE:** nested/payable DC `msg.value`-in-flight sites; depth≥3 recirc (Game→Lootbox→Degenerette→Lootbox); layout alignment vs slot table. → 419.
- **CORRUPT:** slot 7 `balancesPacked` (8+ modules) solvency half-writes; slot 44 DEC-ALIAS regular[lvl] vs terminal[lvl+1]; slot 5 `totalFlipReversals`/`lastVrfProcessedTimestamp` masked RMW. → 420.
- **MIDRNG / GAMEOVER / VRFSWAP:** frozen-word index binding; gameOver latch-before-burn all-or-nothing; rotation atomicity vs in-flight `vrfRequestId`. → 421/422/423.

Deliverable `417-COLMAP.md` is the load-bearing map every later phase reads against. No contract change. NEXT = 418 BRICK (dominant; cross-model council + Claude NET-2 seeded by these leads).
