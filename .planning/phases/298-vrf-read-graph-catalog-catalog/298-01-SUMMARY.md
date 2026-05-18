---
phase: 298-vrf-read-graph-catalog-catalog
plan: 01
subsystem: vrf-read-graph-catalog
tags: [audit-only, rng-lock, daily-jackpot, jackpot-module, freshness-violation, F-41-02-class, F-41-03-class]
requires: []
provides:
  - "§1 catalog entry for JackpotModule.payDailyJackpot"
  - "18 VIOLATION rows across 6 distinct participating-slot writer surfaces"
  - "Participating-slot enumeration scope inheritance for Wave-2 unique-slot dedup"
affects: []
key-files:
  created:
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-01-CATALOG-section.md
    - .planning/phases/298-vrf-read-graph-catalog-catalog/298-01-SUMMARY.md
  modified: []
decisions:
  - "D-1 VIOLATION cluster (autoRebuyState): 5 writer-callsites total — 3 have rngLockedFlag gates already in place (rows 9,10,11,16), 2 are MISSING gates (rows 12, 13: deactivateAfKingFromCoin + syncAfKingLazyPassFromCoin); coverage gap concentrated in BurnieCoin/BurnieCoinflip-routed entries"
  - "D-2 VIOLATION cluster (prizePoolsPacked): 6+ writer-entries from purchase/whale/decimator/lootbox paths; MintModule.purchase has NO blanket rngLockedFlag revert (only the line :1221 target-level redirect on last jackpot day); WhaleModule.purchaseWhaleBundle/purchaseLazyPass also missing top-level gate"
  - "D-3 VIOLATION cluster (dailyHeroWagers): 3 entries (DegeneretteModule:367, DegenerusGame:714, DegenerusVault:607) — but day-key separation (dailyIdx==D while _simulatedDayIndex()==D+1 inside the resolution window) structurally freezes slot D; remediation tactic (b) snapshot/anchor with explicit day-index attestation"
  - "D-4 VIOLATION (sDGNRS poolBalances[Pool.Reward]): cross-contract race — final-day DGNRS reward amount at JackpotModule:1493-:1502 reads live sDGNRS balance instead of a snapshotted value; non-advanceGame writers can mutate the pool between commitment and resolution; tactic (b) snapshot-at-freeze"
  - "D-5 Structural protections identified: ticketWriteSlot double-buffer (Storage.sol:684-746) + far-future _queueTickets revert gate (Storage.sol:572) + dailyIdx day-key separation jointly block several classes of mid-window injection that would otherwise be VIOLATIONs"
  - "E-1 remediation tactic distribution: (a) gated-revert × 14, (b) snapshot/anchor × 6, (c)/(d) × 0 — heavily skewed toward (a) per D-298-RECOMMEND-DEPTH-01"
metrics:
  duration_minutes: 12
  tasks: 1
  files_created: 2
  source_mutations: 0
  test_mutations: 0
completed: 2026-05-18
---

# Phase 298 Plan 01: VRF Read-Graph Catalog — JackpotModule.payDailyJackpot Summary

VRF-derived-entropy backward-trace from `payDailyJackpot` (daily ETH/whalepass distribution; Phase 287 JPSURF prior coverage) enumerated 58 reachable functions, 24 distinct SLOAD slots (14 participating + 10 non-participating with attestation), and 18 VIOLATION (slot × writer × callsite) rows across 6 participating-slot writer surfaces, with remediation tactics concentrated in (a) rngLockedFlag-gated revert (×14) and (b) snapshot/anchor (×6).

## Outputs

- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-01-CATALOG-section.md` — §A traced-fn set (58 rows) + §B SLOAD table (24 slots, full Participating?/Attestation columns) + §C per-participating-slot writer enumeration (14 slots × all reachable writer-callsites) + §D verdict matrix (43 rows total: 25 EXEMPT-ADVANCEGAME + 18 VIOLATION) + §E remediation tactic per VIOLATION (18 rows).

## Trace Result

- **Consumer:** `DegenerusGameJackpotModule.payDailyJackpot` at `contracts/modules/DegenerusGameJackpotModule.sol:339`.
- **Reach pattern:** Three execution profiles traced — (P1) `isJackpotPhase=true, resumeEthPool==0` fresh daily jackpot; (P2) `isJackpotPhase=true, resumeEthPool!=0` call-2 resume via `_resumeDailyEth`; (P3) `isJackpotPhase=false` purchase-phase BAF-style daily. All three reach via `AdvanceModule.advanceGame` delegatecall (`AdvanceModule.sol:383/454/473` → `:915` → `:924`).
- **VRF word source:** `rngWord` parameter sourced from `rngGate(...)` return at `AdvanceModule.sol:290`, which is the cached `rngWordCurrent` (nudge-mixed at `_applyDailyRng:1840`). Word is parameter-passed through the consumer's resolution stack — no mid-resolution re-SLOAD of `rngWordCurrent` inside `payDailyJackpot`'s reachable set.
- **Reachable function count (§A):** 58 (entry + storage helpers + pure libraries + cross-module hops to sDGNRS).
- **Reachable SLOAD count (§B):** 24 distinct slots.
- **Participating-slot count (after two-tier classification per D-298-SLOT-CLASSIFICATION-01):** 14.
- **Non-participating attestations:** 10 slots (`claimableWinnings`, `claimablePool`, `whalePassClaims`, `lastPurchaseDay`, `jackpotPhaseFlag`, `purchaseStartDay`, `rngRequestTime`, `rngLockedFlag` read-side bypass, `ticketWriteSlot` write-side routing, `ticketsOwedPacked`+`ticketQueue` length — all carry explicit 1-line F-41-02/03-class attestation).

## Writer Enumeration

| Participating Slot | Writer Callsites (External/Public Entry) | Notes |
|--------------------|-------------------------------------------|-------|
| `dailyIdx` | `_unlockRng` (AdvanceModule:1729, 5 advanceGame-stack callsites) + constructor | All EXEMPT-ADVANCEGAME |
| `dailyHeroWagers[D][q]` | `placeDegeneretteBet` × 3 entries (Module:367, Game:714, Vault:607) | Day-key separation = structural freeze; recommended tactic (b) attestation |
| `level` | `_requestRng → _finalizeRngRequest` (advanceGame-stack only) | EXEMPT |
| `gameOver` | `handleGameOverDrain` (advanceGame-stack); plus mock-only test contract excluded | EXEMPT |
| `autoRebuyState[beneficiary]` | 5 writer entries: `setAutoRebuy`, `setAutoRebuyTakeProfit`, `setAfKingMode` (all gated at :1513/:1528/:1575); `deactivateAfKingFromCoin`, `syncAfKingLazyPassFromCoin` (BOTH ungated — VIOLATION rows 12/13) | 2 missing gates |
| `traitBurnTicket[lvl][trait]` | `_raritySymbolBatch` (assembly-sstore inside MintModule:537) reached only via `processTicketBatch`/`processFutureTicketBatch` from advanceGame | EXEMPT (delegatecall-only mutation) |
| `deityBySymbol[fullSymId]` | `_purchaseDeityPass` (gated at :543) | VIOLATION row 16 — gate-by-revert |
| `currentPrizePool` | `_setCurrentPrizePool` from JackpotModule self + `_consolidatePoolsAndRewardJackpots` | EXEMPT |
| `prizePoolsPacked` (next/future) | 9+ external entries: `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` (NO blanket gate), `purchaseWhaleBundle`/`purchaseLazyPass` (no gate), `purchaseDeityPass` (gated), `recordDecBurn` (no gate), `placeDegeneretteBet` (no gate), `openLootBox`/`openBurnieLootBox` (lootbox-VRF domain-separated), `claimWhalePass` (effective gate via `_queueTicketRange` revert) | 8 VIOLATION rows (22-30); structural protection: writes are not consumed by THIS resolution because (i) double-buffer routes `ticketQueue` writes to opposite slot, (ii) the future-pool slot itself does not feed winner selection at this consumer — it influences only `dailyEthBudget` which was already snapshotted to a local at line :385. Verdict-strict still VIOLATION per `D-298-EXEMPT-REACH-01`. |
| `jackpotCounter` | `payDailyJackpotCoinAndTickets` (advanceGame-stack), phase-transition cleanup | EXEMPT |
| `compressedJackpotFlag` | `advanceGame` self-write × 3 sites | EXEMPT |
| `resumeEthPool` | `_processDailyEth` SPLIT_CALL1/CALL2 sites (self-stack) | EXEMPT |
| `dailyTicketBudgetsPacked` | `payDailyJackpot` P1 write + Phase-2 clear | EXEMPT |
| sDGNRS `poolBalances[Pool.Reward]` (cross-contract) | `transferFromPool` (multiple GAME callsites incl. non-advanceGame), `transferBetweenPools`, sDGNRS-internal admin distribution | 2 VIOLATION rows (41, 43) — cross-contract race |

## Verdict

- **VIOLATION rows (§D total):** 18 — distributed across 6 participating-slot writer surfaces.
  - dailyHeroWagers: 3 rows (gate-by-day-key tactic (b))
  - autoRebuyState: 5 rows (3 gated + 2 missing)
  - deityBySymbol: 1 row (gated)
  - prizePoolsPacked: 7 rows (mix of gated/ungated)
  - sDGNRS poolBalances: 2 rows (cross-contract)
- **EXEMPT-ADVANCEGAME rows:** 25 — every writer-callsite reachable from `advanceGame()`'s static call-graph descendancy.
- **EXEMPT-VRFCALLBACK rows:** 0 — the VRF callback (`rawFulfillRandomWords`) does NOT invoke `payDailyJackpot` directly; it only writes `rngWordCurrent` and returns. The consumer is reached on the NEXT `advanceGame` invocation.
- **EXEMPT-RETRYLOOTBOXRNG rows:** 0 — `retryLootboxRng` targets a separate VRF domain per `D-42N-RETRY-RNG-DOMAIN-SEP-01` and does not reach this daily-jackpot consumer.
- **No discretionary classifications** per `D-43N-AUDIT-ONLY-01` + `D-298-EXEMPT-REACH-01`.

## Remediation

Per `D-298-RECOMMEND-DEPTH-01`: one tactic + ≤80-char rationale per VIOLATION row. Distribution:

- **(a) `rngLockedFlag`-gated revert:** 14 rows — autoRebuyState (5), deityBySymbol (1), prizePoolsPacked purchase/whale/decimator/whalepass/degenerette entries (8). Pattern reference: `MintModule.sol:1221`, `BurnieCoinflip.sol:730`, `StakedDegenerusStonk.sol:492`.
- **(b) snapshot/anchor pattern:** 6 rows — dailyHeroWagers day-key separation attestation (3 rows), openLootBox/openBurnieLootBox snapshot-prizePool-at-buy-time (1), sDGNRS poolBalances snapshot-at-freeze (2). Pattern reference: Phase 281 owed-salt, Phase 288 dailyIdx structural snapshot at lock-time.
- **(c) pre-lock reorder:** 0 rows.
- **(d) immutable:** 0 rows.

## Deferred / Out-of-Scope (Wave-2 integration handles)

- **Phase-2 consumer (`payDailyJackpotCoinAndTickets`)** is the §2 consumer per `D-298-CONSUMER-LIST-01` — its SLOAD set will overlap (jackpotCounter, dailyTicketBudgetsPacked, traitBurnTicket, deityBySymbol, dailyHeroWagers, level) but at distinct read sites. Wave-2 unique-slot dedup will merge those reads into a single §14 entry.
- **sDGNRS internal writers** are enumerated structurally (`transferFromPool`, `transferBetweenPools`, ERC20 surface) but per-callsite expansion of sDGNRS-internal writers requires reading `contracts/StakedDegenerusStonk.sol` exhaustively — deferred to the unique-slot integration step.
- **`yieldAccumulator`** is OUT OF TRACE for §1 — it lives in the `distributeYieldSurplus` consumer and the gameOver drain; not reached from `payDailyJackpot`'s call graph.
- **`level` cached-vs-storage discrepancy:** The auto-rebuy `_calcAutoRebuy(... currentLevel: level ...)` SLOADs the storage `level` slot at the call site (PayoutUtils:51 receives `level` as parameter; the caller `_processAutoRebuy` at JackpotModule:828 reads storage `level` at the callsite). Pre-incremented `level` would change `targetLevel = currentLevel + uint24(levelOffset)` and shift which `ticketQueue[wk]` slot receives the bonus tickets. This is flagged in CAT-02 with NO attestation noting "write-side routing only, no read-back into VRF flow" — defer to Wave-2 reviewer to confirm the routing-only attestation holds.

## Self-Check: PASSED

- File exists: `.planning/phases/298-vrf-read-graph-catalog-catalog/298-01-CATALOG-section.md` — confirmed.
- All 5 CAT sub-headings present (CAT-01, CAT-02, CAT-03, CAT-04, CAT-06) — confirmed via `grep -q`.
- Zero `SAFE_BY_DESIGN` tokens — confirmed.
- Zero "by construction" / "covered by single fn" shortcuts — confirmed.
- Every §D row carries a classification token ∈ {EXEMPT-ADVANCEGAME, EXEMPT-VRFCALLBACK, EXEMPT-RETRYLOOTBOXRNG, VIOLATION} — 43/43 rows, confirmed.
- Every §E VIOLATION row carries a tactic ∈ {(a), (b), (c), (d)} + ≤80-char rationale — 18/18 rows, confirmed.
- Zero `contracts/` + zero `test/` mutations — confirmed by `git status --short`.
