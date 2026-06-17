# Adversarial Mid-Day RNG Review — Degenerus Protocol spinal column (v67.0 phase 421 MIDRNG)

You are an independent senior smart-contract auditor reviewing **mid-day RNG edge cases** on a real-money on-chain ETH game. Read-only. Subject = the **frozen `contracts/` working tree in this repo at commit `0bb7deca` / tree `4a67209a`** (clean — read files under `contracts/` directly; cite `file:line`). Assume **honest admin/governance** (key-compromise out of scope). The broad RNG-freeze surface was already closed in a prior milestone (v66) — THIS phase is scoped to the mid-day RNG paths that can **BRICK or CORRUPT the column** (not general manipulability).

## The structure under test

The game uses Chainlink VRF. The DAILY word advances the game; a separate **mid-day lootbox RNG** stream resolves boxes/tickets/bets intra-day. The two share VRF plumbing and are split by `rngLockedFlag`. Key state (Game storage, written by `DegenerusGameAdvanceModule.sol` under delegatecall):
- `lootboxRngPacked` (slot 34): `LR_INDEX | LR_PENDING_ETH | LR_THRESHOLD | LR_PENDING_FLIP | LR_MID_DAY`.
- `lootboxRngWordByIndex[index]` (slot 35): the per-index resolved word (0 = unresolved).
- `rngWordByDay[day]` (slot 10), `rngWordCurrent` (slot 3), `vrfRequestId` (slot 4), `rngLockedFlag` (slot 0), `rngRequestTime` (slot 0), `dailyIdx` (slot 0).
- Relevant fns: `requestLootboxRng` (~Advance:1132/1792), `retryLootboxRng` (~:1804), `rawFulfillRandomWords` (~:1844/1856 — daily vs mid-day split by `rngLockedFlag`), `_finalizeLootboxRng` (~:1284), `_backfillOrphanedLootboxIndices` (~:1894/1901), `_lrAdvanceIndexClearPending` (~:1666), `openHumanBoxes` (~:682/728).

## CLAIMS (find any reachable counterexample)

### MIDRNG-01 — Mid-day swap / retry cannot brick or mis-bind
A mid-day lootbox request that stalls can ALWAYS be retried/resolved, and the retry cannot bind a box/ticket/bet to the WRONG (in-flight) word or strand the index. Verify: `requestLootboxRng` → `retryLootboxRng` recovery is reachable from any stalled mid-day state; the retry does not advance/replace `LR_INDEX` in a way that orphans an already-committed but unresolved `lootboxRngWordByIndex[index]`; `rawFulfillRandomWords` routes a fulfilled word to the correct index/day (no daily word written to a mid-day index or vice versa). Note: box seeds bind to `lootboxRngWordByIndex[index]` (no live day in the seed for direct/redemption/afking boxes); `issueDeityBoon`/`_rollLootboxBoons` read a live day for EXPIRY only, not the outcome roll — verify a mid-day swap cannot change an outcome by shifting the index.

### MIDRNG-02 — Partial-drain read slot is consistent (resumable)
A mid-day partial advance (the chunked drain) leaves the queue/index/cursor in a state the NEXT advance resumes correctly — NO double-drain and NO skipped ticket/box. Verify the resumability latches: `STAGE_GAP_BACKFILLED`, `STAGE_SUBS_BACKFILL_DEFERRED`, the ticket-cursor (slot 14), `_backfillOrphanedLootboxIndices` backfilling below `LR_INDEX`, and the `advanceGame` L185-187 clamp of a new wall-day to `dailyIdx+1` when that day's word is recorded-but-unsealed (the RNG-reuse guard). Show the per-tx-ceiling decouples hold under VRF-stall sequencing (a stall between chunks does not lose or replay a chunk).

### MIDRNG-03 — Mid-day word binding (placed-after-request binds to live index/day)
Boxes/tickets/bets placed mid-day AFTER a request bind to the LIVE index/day, not the in-flight word — across gap-backfill and retry interleavings (the `RngIndexDrainBinding` concern). Specifically: Degenerette placement requires `lootboxRngWordByIndex[index]==0` and resolution requires `!=0` — verify the index cannot be advanced/replaced mid-flight to let a placer re-pick a winning word, or to let a resolution read a word bound to a different placement set. Verify `openHumanBoxes:682 word!=0` break prevents marooning if a coordinator rotation orphans an index word.

## Priority hotspots
- The `rngLockedFlag` daily/mid-day split in `rawFulfillRandomWords` — can a fulfillment land on the wrong branch (daily word stored as mid-day, or vice versa) under any request interleaving?
- `_lrAdvanceIndexClearPending` advancing `LR_INDEX` while a placement for the old index is in flight.
- The clamp at `advanceGame` L185-187 (recorded-but-unsealed day) — can a wall-day jump skip or reuse a word?
- Index-orphaning on stall (`openHumanBoxes` word!=0 break + `_backfillOrphanedLootboxIndices`) — can an index be permanently marooned (brick) or double-resolved?

## Output
For EACH of MIDRNG-01..03 and each hotspot: verdict (**REAL / REFUTED / UNCERTAIN**), severity (**CATASTROPHE** for a mid-day brick or a word-rebind that changes an outcome; else HIGH/MED/LOW/INFO), `reachable` under honest governance, the concrete trigger if REAL, and reasoning with `file:line`. Default to REFUTED only when the guard/latch covers the whole reachable window. Also report any **newVectors** outside MIDRNG-01..03. Be concrete and skeptical.
