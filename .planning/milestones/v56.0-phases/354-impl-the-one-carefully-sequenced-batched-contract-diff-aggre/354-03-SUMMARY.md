---
phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre
plan: 03
subsystem: contracts (afking aggregator hot-path)
tags: [solidity, foundry, afking, aggregator, gas-01, agg, qst, aff-pull, accrue, settle]

# Dependency graph
requires:
  - phase: 354-01
    provides: "the re-packed single-slot Sub accumulator (affiliateBase uint32 whole-BURNIE / questProgress uint8 / buyerOwedBurnie uint32 / hasEverSubscribed 1-bit / afkCoveredThroughDay uint24) + the milli-ETH amount helpers (_packEthToMilliEth/_unpackMilliEthToWei)"
  - phase: 354-02
    provides: "DegenerusQuests.settleAfkingQuest(player, uint16 deliveredStreakDays, uint32 currentDay) onlyGame streak-settle entrypoint + the O1 single-credit invariant"
provides:
  - "GameAfkingModule mode-agnostic per-buy ACCRUE — ONE warm in-slot SSTORE (affiliateBase += flat-7% whole-BURNIE with 100M clamp BEFORE +=; questProgress++; afkCoveredThroughDay debit-gated monotone advance), ZERO cross-contract on the hot path (the per-buy quests.handlePurchase / affiliate.payAffiliate ×2 / coinflip.creditFlip STORM is removed — GAS-01 collapse)"
  - "drainAffiliateBase(address) — the AFFILIATE-only atomic read-and-zero PRODUCER the 354-04 affiliate claim CONSUMES (AFF-PULL guardrail 1)"
  - "_settleQuest(player, sub, currentDay) — the ONE quest-settle path (mints questProgress × QUEST_SLOT0_REWARD + buyerOwedBurnie in ONE creditFlip to the SUB + advances the streak via settleAfkingQuest + zeroes both counters; self-marking, idempotent) shared by the STAGE-riding settle-day hook, the permissionless claimQuest fallback, and the unsub-settle"
  - "the SETTLE_PERIOD (~10) global epoch + the STAGE settle hook (processDay % SETTLE_PERIOD == 0) + the first-sub-only +daysToNextSettle (+0..+9) head-start gated on hasEverSubscribed"
affects: [354-04 (consumes drainAffiliateBase), 354-05 (replaces the ticket purchaseWith leg + accrues buyerOwedBurnie), 355 GAS (SUB_STAGE_BATCH shrink + SETTLE_PERIOD tune), 356 TST (SEC-01/02), 357 TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mode-agnostic per-buy accrue placed AFTER the ticket/lootbox if/else so the ONE warm in-slot SSTORE covers BOTH modes off the already-warm Sub slot"
    - "Single shared internal _settleQuest fired from three call sites (settle-day STAGE hook / claimQuest / unsub) — self-marking running balances make a double-fire a no-op (no per-sub day marker, AGG-05)"
    - "Atomic read-and-zero at the storage owner (drainAffiliateBase) — no separate read accessor, so the affiliate-claim consumer can never pre-load bases to memory (the duplicate-sub double-credit guard)"

key-files:
  created:
    - .planning/phases/354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre/354-03-SUMMARY.md
  modified:
    - contracts/modules/GameAfkingModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol

key-decisions:
  - "Activity-score quest-streak input sourced from the PRE-action questView.playerQuestStates(player).streak (the post-buy handler that previously returned it is GONE — the per-buy handlePurchase DISAPPEARS under the aggregator, SPEC QST-05/RESEARCH §5.3). FREEZE-03 preserved: the stamped score matches a manual buy's activity-score path."
  - "Defined a local QUEST_SLOT0_REWARD = 100 ether constant in the module (DegenerusQuests.QUEST_SLOT0_REWARD is `private`, not cross-contract visible) mirroring DegenerusQuests.sol:144 — values the BURNIE mint only (the streak-machinery half rides the onlyGame entrypoint)."
  - "deliveredStreakDays passed to settleAfkingQuest = questProgress (the debit-gated delivered-day counter IS the per-window delivered-day count); the in-core QST-03 guard bounds it against a same-day manual completion."
  - "buyerOwedBurnie (whole BURNIE) → base units via × 1 ether in the _settleQuest mint; QUEST_SLOT0_REWARD is already base units. The ticket buyerOwedBurnie ACCRUAL itself is OWNED by 354-05 (which replaces the purchaseWith leg) — this plan only adds the settle-side drain so _settleQuest is complete."
  - "Unsub streak reset = the natural gap-reset via _questSyncState on the next interaction (no new player-callable streak lever introduced, per the plan); the unsub only drains the quest counters + advances the delivered-day streak, never flushing affiliateBase."
  - "First-sub head-start daysToNextSettle = (SETTLE_PERIOD - (currentDay % SETTLE_PERIOD)) % SETTLE_PERIOD — the outer % maps a subscribe ON a settle boundary to +0 (never a full extra window), enforcing the bounded +0..+9."

patterns-established:
  - "GAS-01 hot-path collapse: the per-buy cross-contract storm → ONE warm in-slot accrue + deferred settle (affiliate PULL / quest PUSH)"

requirements-completed: []

# Metrics
duration: 11min
completed: 2026-06-01
---

# Phase 354 Plan 03: Mode-Agnostic Aggregator — Accrue + drainAffiliateBase + _settleQuest + claimQuest + Unsub-Settle + First-Sub Head-Start Summary

**Collapsed the afking per-buy cross-contract storm (`quests.handlePurchase` + `affiliate.payAffiliate` ×2 + per-buy `coinflip.creditFlip`) into ONE warm in-slot accrue (flat-7% `affiliateBase` with the 100M clamp applied BEFORE the `+=`, `questProgress++`, and the debit-gated `afkCoveredThroughDay` high-water advance), added the AFFILIATE-only atomic `drainAffiliateBase` producer the 354-04 claim consumes, and wired the inline `_settleQuest` (the slot-0 quest BURNIE + the accrued ticket buyer-bonus in ONE `creditFlip` to the sub, riding the STAGE on the global settle day) + the permissionless `claimQuest` fallback + the unsub-settle + the first-sub-only `+0..+9` streak head-start — all on top of the re-packed Sub slot (354-01) and the `settleAfkingQuest` entrypoint (354-02); the SOLVENCY-01 ETH/`claimablePool` debit is byte-unchanged and `forge build` exits 0.**

## Performance
- **Duration:** ~11 min
- **Started:** 2026-06-01T17:58:05Z
- **Completed:** 2026-06-01T18:09Z
- **Tasks:** 3
- **Files modified:** 2 (contracts — left UNCOMMITTED for the 354-06 USER batched-commit gate)

## Accomplishments
- **Task 1 (AGG-01/04/05, QST-03, AFF-PULL guardrail 1):** removed the lootbox per-buy storm; KEPT the box stamp (`scorePlus1` + `amount`, sourcing the activity-score quest-streak from the pre-action `questView.playerQuestStates`); added the mode-agnostic accrue AFTER the ticket/lootbox if/else (ONE warm SSTORE covering BOTH modes: `affiliateBase` flat-7% with the 100M saturating clamp BEFORE the `+=`, `++questProgress`, and `afkCoveredThroughDay = processDay` on the DELIVERED-day branch only); added the AFFILIATE-gated `drainAffiliateBase(address)` atomic read-and-zero accessor + its `IGameAfkingModule` declaration. The SOLVENCY-01 debit (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);`) is BYTE-UNCHANGED.
- **Task 2 (AGG-02):** added the internal `_settleQuest(player, sub, currentDay)` (mints `questProgress × QUEST_SLOT0_REWARD + buyerOwedBurnie` in ONE `creditFlip` to the SUB, advances the streak via `settleAfkingQuest`, zeroes both counters; self-marking no-op when both are zero) + the SETTLE_PERIOD (~10) global epoch + the STAGE settle hook (`processDay % SETTLE_PERIOD == 0`, riding the warm slot) + the permissionless `claimQuest(address[])` fallback (runs the SAME path, always credits the sub) + its interface decl. NO affiliate call inside `_settleQuest`.
- **Task 3 (AGG-03 / QST-01 / QST-02):** the CANCEL branch calls `_settleQuest` BEFORE the tombstone (drains `questProgress` + `buyerOwedBurnie`, does NOT flush `affiliateBase`); the UPSERT branch grants the first-sub-only `+daysToNextSettle` (+0..+9) head-start via the `onlyGame` entrypoint, gated on and setting the `hasEverSubscribed` set-once latch.
- `forge build` exits 0 across the working tree (only pre-existing out-of-scope `unsafe-typecast` lint warnings in untouched files).

## Task Commits

Per the **Phase 354 contract-commit override**: the contract edits (`GameAfkingModule.sol`, `IDegenerusGameModules.sol`) are intentionally left UNCOMMITTED in the working tree — they accumulate with the 354-01 (`DegenerusGameStorage.sol`) + 354-02 (`DegenerusQuests.sol`, `IDegenerusQuests.sol`) producers for the SINGLE USER-approved batched `contracts/*.sol` commit at the 354-06 hand-review gate. There are intentionally ZERO production-code commits in this plan.

1. **Task 1: per-buy storm → in-slot accrue + drainAffiliateBase** — working-tree edit, no commit (contract gate)
2. **Task 2: _settleQuest + STAGE settle hook + claimQuest** — working-tree edit, no commit (contract gate)
3. **Task 3: unsub-settle + first-sub head-start** — working-tree edit, no commit (contract gate)

**Plan metadata (docs):** see the `docs(354-03)` commit (this SUMMARY + STATE.md + ROADMAP.md).

## Files Created/Modified
- `contracts/modules/GameAfkingModule.sol` — **(UNCOMMITTED, contract gate)** removed the per-buy lootbox storm; added the mode-agnostic accrue (affiliateBase flat-7% + 100M clamp-before-`+=`, questProgress++, debit-gated afkCoveredThroughDay), `drainAffiliateBase`, `_settleQuest`, `claimQuest`, the SETTLE_PERIOD + local QUEST_SLOT0_REWARD constants, the STAGE settle hook, the unsub-settle, and the first-sub head-start. Dropped the now-unused `IDegenerusGame` import (only `MintPaymentKind` remains used).
- `contracts/interfaces/IDegenerusGameModules.sol` — **(UNCOMMITTED, contract gate)** added the `claimQuest(address[])` and `drainAffiliateBase(address) returns (uint256)` declarations on `IGameAfkingModule`.
- `.planning/phases/354-.../354-03-SUMMARY.md` — this summary (committed).

## Decisions Made
See `key-decisions` in the frontmatter — the load-bearing ones: (1) pre-action quest-streak source via `questView.playerQuestStates` (the post-buy handler is gone), (2) the local `QUEST_SLOT0_REWARD` mirror (the quests constant is `private`), (3) `deliveredStreakDays = questProgress`, (4) the unsub uses the natural gap-reset (no new streak lever), (5) the `% SETTLE_PERIOD`-wrapped head-start for the +0..+9 bound.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Defined a local `QUEST_SLOT0_REWARD` constant in the module**
- **Found during:** Task 2 (verification — `forge build` failed: `Undeclared identifier QUEST_SLOT0_REWARD`)
- **Issue:** The plan's `_settleQuest` math references `QUEST_SLOT0_REWARD`, but `DegenerusQuests.QUEST_SLOT0_REWARD` (DegenerusQuests.sol:144) is a `private` constant — not visible cross-contract — so the module did not compile.
- **Fix:** Added `uint256 internal constant QUEST_SLOT0_REWARD = 100 ether;` to the module (mirroring the quests value), used only to value the BURNIE mint. The streak-machinery half still rides the `settleAfkingQuest` onlyGame entrypoint (which owns its own copy). Documented with a NatSpec note.
- **Files modified:** `contracts/modules/GameAfkingModule.sol` (UNCOMMITTED, accumulates for the 354-06 batch)
- **Verification:** `forge build` exits 0.
- **Committed in:** NOT committed — left in the working tree per the Phase 354 contract-commit override.

**2. [Rule 3 - Blocking] Dropped the now-unused `IDegenerusGame` import**
- **Found during:** Task 1 (removing the storm)
- **Issue:** `IDegenerusGame` was imported only for the removed `recordMintQuestStreak` call inside the deleted quest block. Leaving it would introduce an unused-import lint warning.
- **Fix:** Narrowed the import to `import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";` (`MintPaymentKind` is still used by `_resolveBuy`).
- **Files modified:** `contracts/modules/GameAfkingModule.sol` (UNCOMMITTED).
- **Verification:** `forge build` exits 0.
- **Committed in:** NOT committed (contract gate).

---

**Total deviations:** 2 auto-fixed (both blocking-compile). **Impact on plan:** none on scope/behavior — both are mechanical compile-correctness fixes required by the plan's `forge build` exit-0 criterion; semantically aligned with the LOCKED design.

## Issues Encountered
- **Working tree carried the 354-01/02 producers UNCOMMITTED** (as required by the sequential-execution note). I built ON TOP of the current on-disk state, read each file fresh (the plan's `<interfaces>` line numbers had shifted), and did NOT touch/revert/stash any accumulated edit. The `DegenerusGameStorage.sol` re-packed Sub fields (`affiliateBase`/`questProgress`/`buyerOwedBurnie`/`hasEverSubscribed`/`afkCoveredThroughDay`) and `DegenerusQuests.settleAfkingQuest` were already present and were CONSUMED, not re-declared.
- **Pre-existing out-of-scope lint warnings** — `forge build` emits `unsafe-typecast` warnings in untouched files (e.g. `DegenerusGameLootboxModule.sol`, test files). Baseline, not introduced by this plan, `forge build` exits 0. Already tracked in `deferred-items.md` (354-02). Not fixed (SCOPE BOUNDARY).

## Known Stubs
None. The ticket-mode `buyerOwedBurnie` ACCRUAL is intentionally NOT authored here — it is OWNED by 354-05 (which replaces the ticket `purchaseWith` leg with the minimal-write primitive). This plan adds the settle-side drain of `buyerOwedBurnie` in `_settleQuest` so the settle is complete, and leaves the `purchaseWith` call in place (a NatSpec NOTE marks the 354-05 handoff). This is the intended producer-before-consumer wave split, not a stub.

## Threat Flags
None. No new network endpoint / auth path / file-access / schema surface beyond the plan's `<threat_model>` (the new `drainAffiliateBase` is AFFILIATE-gated and `claimQuest` always credits the sub — both inside the plan's STRIDE register).

## User Setup Required
None.

## Next Phase Readiness
- **354-04 (Wave 3, the affiliate PULL):** consumes `drainAffiliateBase` (the producer authored here) — atomic read-and-zero at the storage owner; the `claim`/`withdraw` + `pendingClaim` ledger live in `DegenerusAffiliate.sol`.
- **354-05 (the ticket minimal-write primitive):** replaces the `purchaseWith` delegatecall and ACCRUES `buyerOwedBurnie` (10%/20%) per buy; the settle-side drain (`_settleQuest`) is already complete here.
- **355 GAS:** the `SETTLE_PERIOD` cadence + the `SUB_STAGE_BATCH` shrink (so the heavier settle-day chunk fits 16.7M) + the C5 micro-opts are deferred there (carried at the locked ~10-day value, not pinned).
- **Contract gate:** all four producers (`GameAfkingModule.sol`, `IDegenerusGameModules.sol` [this plan] + `DegenerusGameStorage.sol` [354-01] + `DegenerusQuests.sol`/`IDegenerusQuests.sol` [354-02]) remain UNCOMMITTED, accumulating for the single USER-approved batched commit at 354-06.

## Self-Check: PASSED

- FOUND: `.planning/phases/354-.../354-03-SUMMARY.md`
- MODIFIED (uncommitted, per Phase 354 override): `contracts/modules/GameAfkingModule.sol`, `contracts/interfaces/IDegenerusGameModules.sol`
- Storm removed from the STAGE body (0 real `quests.handlePurchase`/`affiliate.payAffiliate`/`coinflip.creditFlip` calls; the only 2 grep hits are in a descriptive comment); accrue writes `affiliateBase` + `questProgress` + `afkCoveredThroughDay`; SOLVENCY-01 debit byte-unchanged (`git diff` shows no change on those 2 lines); `drainAffiliateBase` AFFILIATE-gated + atomic + interface-declared; `_settleQuest` + `claimQuest` present (1 each) + `claimQuest` interface-declared; settle gate uses `% SETTLE_PERIOD`; `_settleQuest` has 0 `affiliate.` calls; CANCEL branch calls `_settleQuest` before the tombstone and does NOT flush `affiliateBase`; UPSERT gates on/sets `hasEverSubscribed` using `daysToNextSettle`.
- `forge build` exit 0.

No commit hashes to verify for contract files — they are intentionally left uncommitted per the Phase 354 contract-commit override (single USER-approved batched commit deferred to 354-06).

---
*Phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre*
*Completed: 2026-06-01*
