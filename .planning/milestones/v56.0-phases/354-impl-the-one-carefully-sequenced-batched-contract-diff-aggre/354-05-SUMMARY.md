---
phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre
plan: 05
subsystem: contracts (afking ticket primitive + open re-verification)
tags: [solidity, foundry, afking, tickets, buyer-bonus, century-bonus, tkt, open, evcap, freeze]

# Dependency graph
requires:
  - phase: 354-01
    provides: "the re-packed single-slot Sub accumulator (buyerOwedBurnie uint32 whole-BURNIE / questProgress uint8 / affiliateBase uint32 / afkCoveredThroughDay uint24) + the milli-ETH amount helpers (_packEthToMilliEth/_unpackMilliEthToWei) + the OPEN-path milli-ETH→wei rescale already applied"
  - phase: 354-03
    provides: "the mode-agnostic per-buy accrue (affiliateBase flat-7% + questProgress++ + afkCoveredThroughDay) placed AFTER the ticket/lootbox if/else; _settleQuest (which already drains buyerOwedBurnie); claimQuest; the SETTLE_PERIOD epoch"
provides:
  - "GameAfkingModule ticket MINIMAL-WRITE PRIMITIVE — REPLACES the ~262k purchaseWith delegatecall with a direct _queueTicketsScaled(player, targetLevel, adjustedQty, false) resolution-equivalent queue write; the SOLVENCY-01 debit is the ONLY ETH/claimablePool accounting (byte-unchanged), no recordMint, no purchaseWith, no cross-contract storm"
  - "the 10%/20% ticket buyer-bonus ACCRUED per buy into Sub.buyerOwedBurnie (live DegenerusGameMintModule.sol:1653-1659 magnitude MINUS the affiliate-kickback leg; base-BURNIE→whole-BURNIE /1e18; 100M saturating clamp BEFORE the +=) — closing the v55-style dropped-bonus regression; paid to the SUB via the quest PUSH (_settleQuest), not the affiliate PULL"
  - "the century/x00 quantity bonus at PARITY (targetLevel % 100 == 0) reusing the existing centuryBonusLevel/centuryBonusUsed storage (NO new slot) + reusing _playerActivityScore (pre-action quest streak, FREEZE-03 parity); boons/boost-OFF (the per-player purchase-boost multiplier deliberately NOT applied — XMODEL C3-b)"
  - "the afking OPEN-end RE-VERIFIED unmanipulable (OPEN-01/02) after the accrual/settle refactor: effects-first lastOpenedDay marker, frozen rngWordByDay[lastAutoBoughtDay] stamp-day word, LIVE currentLevel=level+1 + single EV-cap RMW in resolveAfkingBox, accumulator fields disjoint from the open markers — UNCHANGED except the 354-01 milli-ETH→wei rescale"
affects: [354-06 (the single USER batched-commit gate), 355 GAS, 356 TST (TKT/OPEN parity + SEC-02), 357 TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Ticket minimal-write primitive mirroring the lootbox box-stamp: SOLVENCY-01 debit (the only ETH accounting, byte-unchanged) + a direct _queueTicketsScaled resolution-equivalent queue write + the warm in-slot buyerOwedBurnie accrue — the per-buy recordMint/purchaseWith storm removed (BURNIE-emission-timing + gas change only)"
    - "Ticket-mode-specific buyer-bonus accrued into the same warm Sub slot (clamped before the +=) and paid via the quest PUSH; the lootbox leg accrues NONE (it gets the lootbox boon path)"

key-files:
  created:
    - .planning/phases/354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre/354-05-SUMMARY.md
  modified:
    - contracts/modules/GameAfkingModule.sol

key-decisions:
  - "No recordMint / prize-pool contribution on the afking ticket primitive — the SPEC/READS-WRITES design (the 'irreducible afking buy' = debit + minimal queue-write + 1 accrue SSTORE) explicitly removes the purchaseWith heavyweight (which dragged in recordMint→_processMintPayment). The SOLVENCY-01 debit (afkingFunding[src] -= ethValue; claimablePool -= ethValue) is the ONLY ETH accounting and is byte-unchanged — exactly mirroring the lootbox branch, which also debits then defers (no recordMint at stamp; the box pays at open)."
  - "buyerOwedBurnie accrues on the PRE-bonus ticket `amount` (matching the manual leg's `coinCost`, which uses the input ticket `quantity`, not the century-adjusted qty). The century bonus only inflates the queued ticket quantity, not the buyer-bonus base."
  - "targetLevel reuses the hoisted `currentLevel` (= the loop's single `level` SLOAD) rather than a second SLOAD: jackpotPhaseFlag ? currentLevel : currentLevel + 1 (mirrors _callTicketPurchase:1518)."
  - "IDegenerusGameMintModule import NARROWED out (the only consumer was the removed purchaseWith delegatecall) — IDegenerusGameLootboxModule (the resolveAfkingBox open seam) is the sole remaining import from IDegenerusGameModules. GAME_MINT_MODULE is no longer referenced by GameAfkingModule (still defined in ContractAddresses for other modules)."
  - "ContractAddresses.sol NOT modified — Task 1 REMOVED a delegatecall (no new cross-contract surface) and the 354-03/04 claim/withdraw/claimQuest/drainAffiliateBase calls use the already-existing ContractAddresses.AFFILIATE constant; _queueTicketsScaled is an inherited internal (no wiring). forge build exit 0 is the wiring-resolves proof."
  - "The OPEN path needed ZERO change in this plan — 354-01 already applied the milli-ETH→wei rescale (_unpackMilliEthToWei(uint64(sub.amount)) at the resolveAfkingBox call). Task 2 is a pure re-verification: freeze/parity intact, accumulator fields disjoint from the open markers."

patterns-established:
  - "TKT regression-close: the afking ticket primitive reaches buyer-bonus PARITY (10%/20%) with the manual ticket buyer, dropping ONLY the affiliate-kickback leg (deferred to the PULL) and the boon-derived purchase-boost (boons-OFF by design)"

requirements-completed: [TKT-01, TKT-02, OPEN-01, OPEN-02]

# Metrics
duration: 28min
completed: 2026-06-01
---

# Phase 354 Plan 05: Ticket Minimal-Write Primitive + buyerOwedBurnie Accrual + Century Parity + Open Re-Verification Summary

**Replaced the afking ticket-mode `purchaseWith` heavyweight (~262k, which dragged in `recordMint` + the whole quests/affiliate/coinflip storm) with a minimal-write primitive that mirrors the lootbox box-stamp shape — a direct `_queueTicketsScaled(player, targetLevel, adjustedQty, false)` resolution-equivalent queue write behind the byte-unchanged SOLVENCY-01 debit — accruing the 10%/20% ticket buyer-bonus per buy into `Sub.buyerOwedBurnie` (live `:1653-1659` magnitude minus the affiliate-kickback leg, /1e18 to whole BURNIE, 100M saturating clamp BEFORE the `+=`), keeping the century/x00 quantity bonus at parity (reusing `centuryBonusLevel`/`centuryBonusUsed`, no new slot, reusing `_playerActivityScore`), staying boons/boost-OFF (the per-player purchase-boost deliberately NOT applied — XMODEL C3-b), and advancing the SAME shared `questProgress` counter the lootbox leg does via the mode-agnostic accrue (no double-accrue); then RE-VERIFIED the afking open-end stays completely unmanipulable (OPEN-01/02) with only the 354-01 milli-ETH→wei rescale forced. `forge build` exits 0.**

## Performance

- **Duration:** ~28 min
- **Started:** 2026-06-01T18:40Z
- **Completed:** 2026-06-01T19:08Z
- **Tasks:** 2
- **Files modified:** 1 (`contracts/modules/GameAfkingModule.sol`) — left UNCOMMITTED for the 354-06 USER batched-commit gate

## Accomplishments

- **Task 1 (TKT-01/TKT-02):** Replaced the `if (isTicket)` `purchaseWith` delegatecall with a custom minimal-write primitive:
  - **(1) targetLevel** = `jackpotPhaseFlag ? currentLevel : currentLevel + 1` (mirrors `_callTicketPurchase:1518`), reusing the hoisted `currentLevel` (no second `level` SLOAD).
  - **(2) Century/x00 quantity bonus at PARITY** — replicated `DegenerusGameMintModule.sol:1243-1259` BEFORE queuing (`targetLevel % 100 == 0`, `bonusQty = adjustedQty × min(score,30500) / 30500` clamped to the per-level `maxBonus` remaining), REUSING the existing `centuryBonusLevel` (uint24) + `centuryBonusUsed` (mapping) storage — NO new slot. The activity score is computed via `_playerActivityScore(player, questStreak, targetLevel)` sourcing the pre-action quest streak from `questView.playerQuestStates(player)` (FREEZE-03 parity with the lootbox stamp). **boons/boost-OFF:** the per-player `consumePurchaseBoost` multiplier is DELIBERATELY NOT applied (the LOCKED v55 afking design, XMODEL C3-b — consistent with the boons-OFF lootbox leg).
  - **(3) QUEUE** resolution-equivalent ticket entries via the SAME `_queueTicketsScaled(player, targetLevel, adjustedQty, false)` the manual leg uses (`DegenerusGameMintModule.sol:1263`) — byte-equivalent placement/quantity.
  - **(4) ACCRUE** the 10%/20% ticket buyer-bonus into `Sub.buyerOwedBurnie`: `coinCost = (amount × (PRICE_COIN_UNIT/4)) / TICKET_SCALE`, `bonusBase = coinCost/10` (flat 10%), `+= (amount × PRICE_COIN_UNIT) / (40 × TICKET_SCALE)` when `amount >= 10×4×TICKET_SCALE` (→20% on ≥10 tickets) — the live `:1653-1659` magnitude MINUS the affiliate-kickback leg. Valued base-BURNIE→whole-BURNIE (`/1 ether`), 100M saturating clamp applied BEFORE the `+=` (guardrail 2, under-credit-only). The bonus uses the PRE-century `amount`, matching the manual `coinCost`.
  - **(5) lastOpenedDay = processDay** so the open-leg/no-orphan guard never treats a ticket sub as box-pending.
  - The mode-agnostic accrue (354-03, AFTER the if/else) advances `affiliateBase`/`questProgress`/`afkCoveredThroughDay` for BOTH modes — NOT re-accrued in the ticket branch (no double-accrue). `buyerOwedBurnie` is ticket-mode-specific (the lootbox leg accrues none).
  - The SOLVENCY-01 debit (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`) is BYTE-UNCHANGED vs `453f8073` (the `git diff` shows no `+/-` on those two lines).
- **Task 2 (OPEN-01/OPEN-02):** RE-VERIFIED the afking open-end (`_openAfkingBox` → `resolveAfkingBox`) stays unmanipulable after the refactor — NO change required (354-01 already applied the one forced milli-ETH→wei rescale):
  - `sub.lastOpenedDay = sub.lastAutoBoughtDay` advances effects-first, BEFORE the resolve delegatecall (a re-entrant open re-checks the now-equal marker → no-op).
  - The box word is `rngWordByDay[day]` with `day = sub.lastAutoBoughtDay` (the FROZEN stamp-day word); the frozen activity score is `uint16(sub.scorePlus1) - 1`.
  - The spend is `_unpackMilliEthToWei(uint64(sub.amount))` (the ONE forced change, 354-01 — the milli-ETH stamp widened+rescaled to wei).
  - `_afkingBoxReady` gates on `lastOpenedDay < lastAutoBoughtDay && rngWordByDay[...] != 0`.
  - `resolveAfkingBox` (LootboxModule:894/902): `currentLevel = level + 1` LIVE + the SINGLE `_applyEvMultiplierWithCap(player, currentLevel, ...)` RMW keyed `[player][currentLevel]` — UNCHANGED.
  - The accumulator fields (`affiliateBase`/`questProgress`/`buyerOwedBurnie`) are DISJOINT from the open markers (`lastOpenedDay`/`lastAutoBoughtDay`) in the shared Sub slot (different fields, per-field SLOAD-mask-SSTORE) — no collision.
  - Wiring resolves with NO `ContractAddresses.sol` change (Task 1 removed a delegatecall; no new cross-contract surface).
- `forge build` exits 0 across the working tree (only the pre-existing out-of-scope `unsafe-typecast` lint warnings in untouched files).

## Task Commits

Per the **Phase 354 contract-commit override**: the contract edit (`GameAfkingModule.sol`) is intentionally left UNCOMMITTED in the working tree — it accumulates with the 354-01/02/03/04 producers for the SINGLE USER-approved batched `contracts/*.sol` commit at the 354-06 hand-review gate. There are intentionally ZERO production-code commits in this plan.

1. **Task 1: ticket minimal-write primitive + buyerOwedBurnie accrual + century parity** — working-tree edit, no commit (contract gate)
2. **Task 2: open-end re-verification + wiring confirmation** — re-verification only; no code change (354-01 owned the one forced rescale); no commit

**Plan metadata (docs):** see the `docs(354-05)` commit (this SUMMARY + STATE.md + ROADMAP.md + REQUIREMENTS.md).

## Files Created/Modified

- `contracts/modules/GameAfkingModule.sol` — **(UNCOMMITTED, contract gate)** the ticket `purchaseWith` delegatecall REPLACED by the minimal-write primitive (targetLevel + century parity reusing existing storage + `_queueTicketsScaled` + `buyerOwedBurnie` 10%/20% accrual clamped); the `IDegenerusGameMintModule` import narrowed out (its only consumer was the removed delegatecall). The OPEN path is unchanged (354-01 owned its milli-ETH rescale; this plan re-verifies it).
- `contracts/ContractAddresses.sol` — **NOT modified** (no new cross-contract surface; wiring resolves against existing constants).
- `.planning/phases/354-.../354-05-SUMMARY.md` — this summary (committed).

## Decisions Made

See `key-decisions` in the frontmatter — the load-bearing ones: (1) NO `recordMint`/prize-pool contribution on the afking ticket primitive (the SPEC's "irreducible afking buy" removes the `purchaseWith` heavyweight; the SOLVENCY-01 debit is the only ETH accounting, byte-unchanged, mirroring the lootbox branch); (2) `buyerOwedBurnie` accrues on the PRE-century `amount` (matching the manual `coinCost` base); (3) `targetLevel` reuses the hoisted `currentLevel` (no extra SLOAD); (4) the `IDegenerusGameMintModule` import narrowed out (dead after the delegatecall removal); (5) `ContractAddresses.sol` NOT modified (no new wiring); (6) the OPEN path needed ZERO change (354-01 owned the rescale) — Task 2 is a pure re-verification.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Narrowed the now-unused `IDegenerusGameMintModule` import**
- **Found during:** Task 1 (after removing the `purchaseWith` delegatecall — its only consumer)
- **Issue:** `IDegenerusGameMintModule` was imported solely for the `purchaseWith.selector` call. Once the ticket primitive replaces that delegatecall, the import is unused (an unused-import lint warning, and dead surface).
- **Fix:** Narrowed `import {IDegenerusGameLootboxModule, IDegenerusGameMintModule}` → `import {IDegenerusGameLootboxModule}` (the `resolveAfkingBox` open seam is the sole remaining consumer). `GAME_MINT_MODULE` is no longer referenced by `GameAfkingModule` (it stays defined in `ContractAddresses` for other modules). Mirrors the 354-03 `IDegenerusGame` import narrowing.
- **Files modified:** `contracts/modules/GameAfkingModule.sol` (UNCOMMITTED, accumulates for the 354-06 batch)
- **Verification:** `forge build` exits 0.
- **Committed in:** NOT committed — left in the working tree per the Phase 354 contract-commit override.

---

**Total deviations:** 1 auto-fixed (1 blocking). **Impact on plan:** none on scope/behavior — a mechanical dead-import cleanup forced by the `purchaseWith` removal; semantically aligned with the LOCKED minimal-write design. **No other deviation:** the plan listed `contracts/ContractAddresses.sol` as a possible file, but no change was needed (Task 1 removed a delegatecall, no new cross-contract surface; the 354-03/04 cross-contract calls use the existing `ContractAddresses.AFFILIATE`). The plan's Task-2 "adjust ONLY if the milli-ETH rescale requires it" was satisfied by 354-01 already applying it — Task 2 reduced to a pure re-verification.

## Issues Encountered

- **Working tree carried the 354-01/02/03/04 producers UNCOMMITTED** (as required by the sequential-execution note). I built ON TOP of the current on-disk state, read each file fresh (the plan's `<interfaces>` line numbers had shifted — the MintModule century bonus was at `:1243-1259`, the buyer-bonus at `:1653-1659`, `_queueTicketsScaled` at `:1263`), and did NOT touch/revert/stash any accumulated edit. The mode-agnostic accrue (354-03) and `_settleQuest`'s `buyerOwedBurnie` drain were already present and were CONSUMED (the ticket branch only adds the ticket-specific `buyerOwedBurnie` accrual + the queue write + the century parity), not re-authored.
- **The DOUBLE-ACCRUE GUARD held:** the ticket branch adds ONLY the `buyerOwedBurnie` accrual + the century parity + the queue write; `affiliateBase`/`questProgress`/`afkCoveredThroughDay` are advanced exactly once by the 354-03 mode-agnostic accrue after the if/else (which already covers tickets).
- **Pre-existing out-of-scope lint warnings** — `forge build` emits `unsafe-typecast` warnings in untouched files (e.g. `DegenerusQuests.sol`, `DegenerusGameLootboxModule.sol`). Baseline, not introduced by this plan; `forge build` exits 0. Already tracked in `deferred-items.md`. Not fixed (SCOPE BOUNDARY).

## Known Stubs

None. The ticket buyer-bonus accrual is now wired end-to-end: the per-buy accrual lands here (354-05); the settle-side drain (`_settleQuest`, which mints `buyerOwedBurnie × 1 ether` aggregated into the slot-0 quest reward in ONE `creditFlip` to the sub) was authored in 354-03. The producer-before-consumer split is complete.

## Threat Flags

None. No new network endpoint / auth path / file-access / schema surface beyond the plan's `<threat_model>`. The ticket primitive REMOVES a delegatecall (shrinks surface); the buyer-bonus is BURNIE-off-the-solvency-path (the SOLVENCY-01 debit is byte-unchanged). The OPEN path is unchanged (re-verified). The T-354-05-TKT-REGRESSION, T-354-05-TKT-BOOST, T-354-05-OPEN02, and T-354-05-SEC02-RNG dispositions in the plan's STRIDE register are all satisfied (mitigate / accept-by-design / mitigate-re-verified).

## User Setup Required

None.

## Next Phase Readiness

- **354-06 (the single USER batched-commit gate):** all five producers remain UNCOMMITTED, accumulating for the ONE USER-approved batched `contracts/*.sol` commit: `GameAfkingModule.sol` (354-01/03/05), `DegenerusGameStorage.sol` (354-01), `DegenerusQuests.sol`/`IDegenerusQuests.sol` (354-02), `IDegenerusGameModules.sol` (354-03), `DegenerusAffiliate.sol`/`IDegenerusAffiliate.sol` (354-04).
- **355 GAS:** the ticket primitive's marginals (the removed ~262k `purchaseWith` → a queue write + an in-slot accrue) + the C5 micro-opts + `SUB_STAGE_BATCH` re-tune are measured/applied there.
- **356 TST:** TKT-356 (afking-ticket buyer-bonus at live parity minus kickback; quantity == manual MINUS the boon-boost, century bonus present), OPEN-02 (the two-path open coexistence), SEC-02 (the SOLVENCY-01 debit byte-unchanged delta-audit).

## Self-Check: PASSED

- FOUND: `.planning/phases/354-.../354-05-SUMMARY.md`
- MODIFIED (uncommitted, per Phase 354 override): `contracts/modules/GameAfkingModule.sol`
- (a) The ticket `purchaseWith` storm is GONE — `grep -c "purchaseWith.selector"` returns 0 file-wide; tickets do NOT double-accrue (the ticket branch adds only `buyerOwedBurnie` + century + queue; the 354-03 mode-agnostic accrue covers `affiliateBase`/`questProgress`/`afkCoveredThroughDay` once).
- (b) SOLVENCY-01 debit BYTE-UNCHANGED — `git diff 453f8073 -- GameAfkingModule.sol` shows NO `+/-` on `afkingFunding[src] -= ethValue` / `claimablePool -= uint128(ethValue)`.
- (c) The OPEN path is freeze/parity-intact bar the milli-ETH→wei rescale — effects-first marker, frozen stamp-day word, LIVE level + single EV-cap RMW, accumulator fields disjoint from the open markers.
- `forge build` exit 0 (only pre-existing out-of-scope lint warnings).

No commit hashes to verify for contract files — they are intentionally left uncommitted per the Phase 354 contract-commit override (single USER-approved batched commit deferred to 354-06).

---
*Phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre*
*Completed: 2026-06-01*
