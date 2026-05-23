---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 05
subsystem: contracts
tags: [solidity, jackpot, vrf-freeze, auto-rebuy-removal, daily-eth-split, afking-removal, sub-09, storage-slot-shift]

# Dependency graph
requires:
  - phase: 317-01
    provides: "RM-02/JGAS-02 footprint ledgers with confirmed live lines, _budgetToTicketUnits NOT-orphaned finding, JGAS PRESERVE set, J5 freeze trace, pre-deletion test baseline (71 failing / 446 passing)"
  - phase: 317-02
    provides: "IBurnieCoinflip.settleFlipModeChange decl removal (RM-05 cross-contract coherence)"
  - phase: 317-03
    provides: "IDegenerusGame afKing decl removal + hasAnyLazyPass ADD; preserved DegenerusGame ctor permanent-deity grant (SUB-09 free-renew basis)"
  - phase: 317-04
    provides: "AfKing.sol live subscribe(address,bool,bool,uint8,uint8) signature (SUB-09 self-subscribe conformance)"
provides:
  - "RM-02: free ETH auto-rebuy fully removed (AutoRebuyState struct + autoRebuyState mapping in storage; _processAutoRebuy + _calcAutoRebuy + AutoRebuyCalc; entropy param dropped from the 3-arg _addClaimableEth at all 8 consume sites); ETH jackpot winnings always credit to claimable; the jackpot credit path no longer consumes a VRF word"
  - "JGAS-02: daily-ETH two-call split removed across JackpotModule + AdvanceModule; the daily ETH jackpot completes in ONE call at the preserved 305-winner ceiling with zero winner-count/scaling/EV change"
  - "RM-05: Vault gameSet* wrappers + local iface decls removed (coinSet* KEPT); sStonk setAfKingMode init + local decl removed (:404 re-claim preserved)"
  - "SUB-09: sDGNRS + Vault self-subscribe at init via player==msg.sender self-consent, matching the live AfKing.subscribe signature"
  - "Post-deletion storage layout (AutoRebuyState slot 19 + resumeEthPool slot 33 removed) — the input to Plan 06's combined forge inspect / SLOT_* re-derivation (the -2 compounded shift)"
affects: [317-06, 318, 320, vrf-freeze-invariant, slot-re-derivation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mechanism-only removal: delete the two-call split routing while byte-preserving the bucket-count/scaling/EV PRESERVE set (305 / 63_600 / 159+95+50+1)"
    - "Protocol-owned self-subscription via player==msg.sender self-consent + permanent-deity free-renew (no new deity write)"
    - "Stack-depth-driven helper extraction (_processBucket) to keep the single-call _processDailyEth loop within the EVM stack limit after removing the split locals"

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGamePayoutUtils.sol
    - contracts/DegenerusVault.sol
    - contracts/StakedDegenerusStonk.sol

key-decisions:
  - "Reduced 3-arg _addClaimableEth(beneficiary, weiAmount, entropy) returning (claimableDelta, rebuyLevel, rebuyTickets) to _addClaimableEth(beneficiary, weiAmount) returning a single claimableDelta — ETH always credits to claimable; the rebuyLevel/rebuyTickets fields were dropped from the JackpotEthWin event (benign ABI break)"
  - "Kept distributeYieldSurplus(uint256) signature (delegatecall selector + IDegenerusGameModules decl stable) but un-named the now-unused VRF-word param — the surplus split is deterministic and consumes no entropy after the rebuy roll deletion"
  - "Removed PriceLookupLib import from PayoutUtils (only _calcAutoRebuy used it)"
  - "Renumbered AdvanceModule stages 9/10/11 -> 8/9/10 after deleting STAGE_JACKPOT_ETH_RESUME=8 (cosmetic; stage values are function-local, never compared, only emitted)"
  - "Extracted a per-bucket _processBucket helper from _processDailyEth to resolve a 'variable 1 too deep' stack error introduced by collapsing the split path; entropy-derivation order preserved byte-for-byte"
  - "SUB-09 sDGNRS = subscribe(self, drainGameCreditFirst=true, useTickets=false, dailyQuantity=1, reinvestPct=2) + coinflip.setCoinflipAutoRebuy(self, true, 0); Vault = subscribe(self, true, false, 1, 0), no BURNIE rebuy — both rely on the existing permanent-deity bit for the free-renew path"

patterns-established:
  - "VRF-consumer retirement: removing a co-consumed entropy input (auto-rebuy roll) without moving _unlockRng keeps the freeze invariant intact"
  - "Single-call jackpot collapse: same-word re-consumption (call1 -> call2) folded into one consumption removes the cross-tx resumeEthPool carry"

requirements-completed: [RM-02, RM-05, JGAS-01, JGAS-02, SUB-09]

# Metrics
duration: ~40min
completed: 2026-05-23
---

# Phase 317 Plan 05: Shared Modules/Storage/Vault/sStonk Removal-and-Fold Summary

**Removed the free ETH auto-rebuy (RM-02) and the daily-ETH two-call split (JGAS-02) across the shared storage + Jackpot/Advance/PayoutUtils modules, pruned the Vault/sStonk afKing cascade (RM-05), and wired the sDGNRS + Vault SUB-09 self-subscriptions — all at the byte-preserved 305-winner ceiling with the v45 VRF-freeze invariant re-confirmed intact.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3 of 3 completed
- **Files modified:** 6 (the plan's owned set, and ONLY that set)
- **Build:** `forge build --skip test` passes (only pre-existing unrelated lint warnings)

## Accomplishments

- **RM-02** — Deleted `struct AutoRebuyState` + `mapping autoRebuyState` (storage slot 19); deleted `_processAutoRebuy` (JackpotModule) and `_calcAutoRebuy` + `struct AutoRebuyCalc` (PayoutUtils); reduced the 3-arg `_addClaimableEth` to a 2-arg credit-claimable-only form and dropped the `entropy` arg at all 8 consume sites; trimmed `rebuyLevel`/`rebuyTickets` from `JackpotEthWin`. ETH winnings now always credit to claimable; the jackpot credit path consumes no VRF word.
- **JGAS-02** — Deleted `SPLIT_NONE/CALL1/CALL2`, `JACKPOT_MAX_WINNERS`, all `resumeEthPool` reads/writes + the storage decl (slot 33), `_resumeDailyEth`, the `splitMode` param + routing, the `call1Bucket` mask, and the split-threshold branch (JackpotModule); deleted `STAGE_JACKPOT_ETH_RESUME=8`, its assignment, and the whole `if (resumeEthPool != 0) { ... }` resume-check block (AdvanceModule). The daily ETH jackpot now completes in ONE unconditional `_processDailyEth` call.
- **RM-05** — Removed the Vault `gameSetAutoRebuy`/`gameSetAutoRebuyTakeProfit`/`gameSetAfKingMode` wrappers + their local `IDegenerusGamePlayerActions` decls (kept `coinSetAutoRebuy`/`coinSetAutoRebuyTakeProfit`); removed the sStonk `setAfKingMode` decl + its constructor init call (kept the `:417` public `gameClaimWhalePass()` re-claim).
- **SUB-09** — Both protocol contracts now self-subscribe at init via `afKing.subscribe(address(this), ...)` (player==msg.sender self-consent). No new deity-bit write was added; the permanent-deity free-renew relies on the existing DegenerusGame constructor grant (preserved by Plan 03).

## Task Commits

**ALL COMMITS DEFERRED.** This repo's PreToolUse commit-guard hook blocks every git commit while any `contracts/*.sol` is dirty, by design. No `git commit` was run for any task; the hook was not bypassed. The six owned files are left UNCOMMITTED in the working tree for the single batched contract commit at the Phase-317 Wave-5 approval gate (which requires explicit USER review of the diff).

1. **Task 1: RM-02 storage + jackpot entropy/auto-rebuy removal (with orphan checks)** — applied, uncommitted
2. **Task 2: JGAS-02 daily-ETH two-call split removal across JackpotModule + AdvanceModule** — applied, uncommitted
3. **Task 3: RM-05 Vault/sStonk cascade prune + SUB-09 self-subscribe init wiring** — applied, uncommitted

## Files Modified

- `contracts/storage/DegenerusGameStorage.sol` — deleted `AutoRebuyState` struct + `autoRebuyState` mapping (slot 19) and `resumeEthPool` (slot 33). These two deletions are the input to Plan 06's combined `-2` slot re-derivation.
- `contracts/modules/DegenerusGameJackpotModule.sol` — RM-02 entropy/auto-rebuy removal + JGAS-02 split removal at the preserved 305 ceiling; extracted `_processBucket` to keep the single-call loop within the stack limit.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — deleted `STAGE_JACKPOT_ETH_RESUME` + its assignment + the resume-check block; renumbered the trailing jackpot stages 9/10/11 -> 8/9/10.
- `contracts/modules/DegenerusGamePayoutUtils.sol` — deleted `_calcAutoRebuy` + `struct AutoRebuyCalc`; removed the now-unused `PriceLookupLib` import (kept `_creditClaimable` + `_queueWhalePassClaimCore`).
- `contracts/DegenerusVault.sol` — removed the 3 `gameSet*` wrappers + their local iface decls; added an `IAfKingSubscribe` interface + `afKing` constant; added the Vault SUB-09 self-subscribe to the constructor.
- `contracts/StakedDegenerusStonk.sol` — removed the `setAfKingMode` decl + constructor init call; added `setCoinflipAutoRebuy` to the coinflip interface + an `IAfKingSubscribe` interface + `afKing` constant; replaced the deleted init with the sDGNRS SUB-09 self-subscribe + `setCoinflipAutoRebuy(self, true, 0)`.

## Load-Bearing Constraints Honored

- **`_budgetToTicketUnits` PRESERVED** (4 references: decl + 3 live callers at the daily-ticket budget path :400/:435/:889, OUTSIDE the deleted auto-rebuy chain). Orphan-grep confirmed it is NOT orphaned before any deletion.
- **JGAS PRESERVE set untouched:** `DAILY_ETH_MAX_WINNERS = 305`, `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600`, and the 159+95+50+1 bucket derivation remain byte-faithful. Only the two-call routing was removed.
- **Pitfall 4:** the DegeneretteModule 2-arg `_addClaimableEth(beneficiary, weiAmount)` overload is in a different file (not owned by this plan) and was never touched.
- **Orphan checks recorded BEFORE deletion:** `_calcAutoRebuy` (sole caller JackpotModule, deleted), `_processAutoRebuy` (sole caller the deleted auto-rebuy block), `AutoRebuyCalc` (sole consumers `_calcAutoRebuy` + the deleted `_processAutoRebuy`) — all confirmed zero surviving callers post-cut.
- **No new deity-bit write** added; SUB-09 relies on the existing ctor grant (Plan 03).

## Freeze-Invariant Re-Confirmation (v45 North-Star, HARD FLOOR)

The J5 trace from the 317-LEDGER held that `_unlockRng` is NOT called inside the daily-ETH resume branch. Re-verified after the fold:

- `_unlockRng` call sites in `DegenerusGameAdvanceModule.sol` are now `:328`, `:399`, `:457`, `:619`, and the decl `:1762`. These shifted ONLY because the 9-line resume block + the stage constant above them were deleted — none were relocated relative to their enclosing logic.
- The coin+tickets-stage `_unlockRng(day)` (was `:467`, now `:457`) is still inside the `dailyJackpotCoinTicketsPending` branch, AFTER `payDailyJackpotCoinAndTickets`, gated by the `jackpotCounter >= JACKPOT_LEVEL_CAP` end-phase check. **No `_unlockRng` was pulled into or before the (now-removed) resume path.**
- The fresh-daily path (`payDailyJackpot(true, lvl, rngWord)` -> `STAGE_JACKPOT_DAILY_STARTED`) does NOT call `_unlockRng` — same as before.
- The single-call collapse folds two same-word consumptions (call1 -> next advanceGame -> call2 re-reading the identical held `randWord` via `resumeEthPool`) into ONE consumption. This removes a VRF-word re-consumption point and the cross-tx `resumeEthPool` carry — strictly LESS rotation-exposed than the two-call split (a rotation-robustness IMPROVEMENT).
- RM-02's entropy drop removed the only consumer of the threaded `entropy` in the jackpot credit path (the auto-rebuy roll); no other reader of that threaded entropy survives (grep-confirmed). `distributeYieldSurplus` no longer consumes the VRF word at all (deterministic split).

**VERDICT: freeze invariant intact.** No path now unlocks rng earlier, and no VRF-derived/co-consumed value that was previously frozen is read on a newly-unfrozen path. Routed to 320 AUDIT for emergency-rotation re-attestation (JGAS-04 / T-317-05-01).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `_processDailyEth` "variable 1 too deep" stack error after the split collapse**
- **Found during:** Task 2 (compile after removing `splitMode` + `call1Bucket` + the SPLIT_CALL2 read and SPLIT_CALL1 write).
- **Issue:** Solc 0.8.34 reported `Variable size is 1 too deep in the stack` in the single-call `_processDailyEth` loop (the solo-bucket destructure of `_handleSoloBucketWinner`'s 3-tuple plus the loop frame).
- **Fix:** Extracted the per-bucket winner-selection + solo/normal dispatch into a private `_processBucket(lvl, traitId, traitIdx, count, share, entropy, isFinalDay, isSolo)` helper returning `(paidDelta, claimDelta, newEntropy)`. The per-bucket `keccak256(entropyState, traitIdx, share)` mix stays in the loop BEFORE the call, so the entropy-derivation order is byte-identical to the original. The loop frame now holds only the accumulators.
- **Files modified:** `contracts/modules/DegenerusGameJackpotModule.sol`
- **Commit:** deferred (Wave-5 batch)

**2. [Rule 3 - Blocking] Unused `PriceLookupLib` import + unused `distributeYieldSurplus` VRF param after the entropy drop**
- **Found during:** Task 1.
- **Issue:** Deleting `_calcAutoRebuy` left `PriceLookupLib` unused in PayoutUtils; dropping the entropy threading left `distributeYieldSurplus`'s VRF-word param unused.
- **Fix:** Removed the dead `PriceLookupLib` import from PayoutUtils; un-named the `distributeYieldSurplus(uint256)` param (selector + interface signature kept stable for the delegatecall path, which is owned by another plan). Comments updated to describe what IS (no history prose).
- **Files modified:** `contracts/modules/DegenerusGamePayoutUtils.sol`, `contracts/modules/DegenerusGameJackpotModule.sol`
- **Commit:** deferred (Wave-5 batch)

**3. [Rule 3 - Blocking] Stale comment reference + extra `_processDailyEth` call sites**
- **Found during:** Task 2.
- **Issue:** `LOOTBOX_MAX_WINNERS`'s doc referenced the deleted `JACKPOT_MAX_WINNERS`; two additional `_processDailyEth(... SPLIT_NONE ...)` call sites (`runTerminalJackpot`, `_executeJackpot`) still passed the deleted `splitMode` arg.
- **Fix:** Rewrote the comment to describe the daily ETH winner ceiling without the deleted symbol; dropped the `SPLIT_NONE` arg at both call sites (collapse to the new 8-arg signature).
- **Files modified:** `contracts/modules/DegenerusGameJackpotModule.sol`
- **Commit:** deferred (Wave-5 batch)

## Known Stubs

None. The SUB-09 self-subscribe configs are concrete (sDGNRS `(self, true, false, 1, 2)` + `setCoinflipAutoRebuy(self, true, 0)`; Vault `(self, true, false, 1, 0)`), matching the live AfKing.subscribe signature. No empty-value / placeholder / TODO stubs introduced.

## Storage-Layout Note (handed to Plan 06)

The two storage deletions land HERE (slot 19 `autoRebuyState`, slot 33 `resumeEthPool`). The combined `-2` slot re-derivation for the `vrf*`/`lootboxRng*`/`degeneretteBets`/`boonPacked` family (slot >= 34 shifts -2; [20,33) shifts -1) is OWNED BY Plan 06 via ONE combined `forge inspect` on this post-deletion tree — NEVER blind -1, NEVER patch-by-arithmetic. No test-side `SLOT_*` constants were touched by this plan. Contract source carries zero numeric slot literals, so this plan introduces no slot-literal edits.

## Self-Check: PASSED

- `forge build --skip test` compiles (all 6 owned files), only pre-existing unrelated lint warnings remain.
- All three plan verify gates return their required values (TASK1/TASK2/TASK3 PASS).
- All 6 owned files are DIRTY in the working tree; the only other dirty `contracts/` files are the 7 pre-existing sibling-wave edits + the untracked `AfKing.sol` — none authored or reverted by this plan.
- `_budgetToTicketUnits` and the JGAS PRESERVE set (305 / 63_600 / 159+95+50+1) verified present.
- No `git commit` was run; the commit-guard hook was not bypassed; `STATE.md` / `ROADMAP.md` untouched.
- This SUMMARY exists on disk at the plan directory, UNCOMMITTED.
