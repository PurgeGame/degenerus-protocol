---
phase: 10-admin-power-vrf-griefing-and-assembly-safety
plan: "03"
subsystem: vrf
tags: [chainlink-vrf, rng, admin, griefing, front-running, liveness]

requires:
  - phase: 10-admin-power-vrf-griefing-and-assembly-safety
    provides: admin privilege surface map (ADMIN-01), wireVrf coordinator substitution analysis (ADMIN-02)
provides:
  - ADMIN-03: 3-day stall trigger enumeration — 5 distinct paths, active wireVrf griefing sequence documented
  - ADMIN-04: 18h RNG lock window analysis — blocked/permitted call table, front-running risk assessed PASS
affects:
  - 13-final-report
  - 10-04 (ADMIN-05 subscription drain economics)
  - 10-05 (ADMIN-06 player-targeting analysis)

tech-stack:
  added: []
  patterns:
    - "Source-analysis verdict format: ADMIN-NN: SEVERITY — one-line summary suitable for Phase 13 report citation"

key-files:
  created:
    - .planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-03-SUMMARY.md
  modified: []

key-decisions:
  - "ADMIN-03 classified MEDIUM (C4 methodology): requires ADMIN key compromise, halts game but funds remain safe; griefing loop is bounded by 3 game days per cycle"
  - "ADMIN-04 classified PASS: 18h lock window does not create front-running surface because pending VRF word is inaccessible until Chainlink fulfills it"
  - "wireVrf is idempotent-repeatable with no guard: active stall requires only one ADMIN call with a reverting coordinator address"
  - "openLootBox() and openBurnieLootBox() are both BLOCKED during rngLockedFlag — RESEARCH.md was partially incorrect; these functions check rngLockedFlag directly"
  - "purchase() (ticket-only path) remains permitted during lock; lootbox component of purchase() is blocked at jackpot levels (purchaseLevel % 5 == 0 && lastPurchaseDay)"
  - "setDecimatorAutoRebuy(), _setAutoRebuy(), _setAutoRebuyTakeProfit(), _setAfKingMode() are all BLOCKED by rngLockedFlag"
  - "GAS-07-I2 (VRF stall liveness dependency) forwarded: 18h retry is the grace period but does not help if _requestRng always reverts (Path D)"

patterns-established:
  - "rngLockedFlag semantics: set by _finalizeRngRequest at VRF request time; cleared by _unlockRng after daily processing or updateVrfCoordinatorAndSub after emergency rotation"

requirements-completed: [ADMIN-03, ADMIN-04]

duration: 18min
completed: 2026-03-04
---

# Phase 10 Plan 03: VRF Stall Trigger Enumeration + 18h Lock Window Analysis Summary

**5-path stall trigger enumeration (ADMIN-03 MEDIUM) and complete 18h RNG lock window blocked/permitted call audit (ADMIN-04 PASS) — front-running risk confirmed absent for all unblocked operations**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-04T22:26:00Z
- **Completed:** 2026-03-04T22:44:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Confirmed `_requestRng` hard-reverts on coordinator failure (comment: "Hard revert if Chainlink request fails; this intentionally halts game progress") — all 5 stall paths produce the same game-halt effect
- Discovered RESEARCH.md had an error: `openLootBox()` and `openBurnieLootBox()` are BLOCKED by `rngLockedFlag`, not permitted. Corrected in this summary.
- Confirmed `wireVrf` is callable any number of times by ADMIN with no guard — admin can point to reverting coordinator at any time, halting `advanceGame()` within the same game day
- Confirmed `updateVrfCoordinatorAndSub` resets all RNG state (`rngLockedFlag=false`, `vrfRequestId=0`, `rngRequestTime=0`, `rngWordCurrent=0`) — recovery cycle works cleanly for griefing loop
- Delivered ADMIN-03 MEDIUM and ADMIN-04 PASS verdicts in Phase 13-citable format

## Task Commits

Each task was committed atomically:

1. **Task 1: Read stall gate source and enumerate all 3-day stall trigger paths** - (analysis task, no code changes — findings recorded in SUMMARY)
2. **Task 2: Enumerate 18h lock window calls and deliver ADMIN-03 + ADMIN-04 verdicts** - see commit hash below

**Plan metadata:** see final commit

---

## ADMIN-03: 3-Day Emergency Stall Trigger Enumeration

### Background

The `_threeDayRngGap` function gates `updateVrfCoordinatorAndSub`. It returns `true` when `rngWordByDay[day]`, `rngWordByDay[day-1]`, and `rngWordByDay[day-2]` are all zero — three consecutive game days with no VRF word recorded.

```solidity
function _threeDayRngGap(uint48 day) private view returns (bool) {
    if (rngWordByDay[day] != 0) return false;
    if (rngWordByDay[day - 1] != 0) return false;
    if (day < 2 || rngWordByDay[day - 2] != 0) return false;
    return true;
}
```

The root cause common to all stall paths: `_requestRng` hard-reverts on any coordinator failure, which prevents `rngWordByDay[day]` from ever being set. The source comment is explicit: *"Hard revert if Chainlink request fails; this intentionally halts game progress until VRF funding/config is fixed."*

### Stall Trigger Path Table

| Path | Name | Mechanism | Admin Key Required | External Action Required | Min Time to Stall | Reversibility |
|------|------|-----------|-------------------|--------------------------|-------------------|---------------|
| A | Subscription balance drain | LINK subscription exhausted; VRF coordinator reverts with insufficient-balance error; `_requestRng` hard-reverts; no words recorded | No | Yes (drain LINK sub) | 3 game days | Admin funds sub → normal operation resumes |
| B | Chainlink coordinator outage | External VRF infrastructure fails; same revert path as Path A | No | External (Chainlink) | 3 game days | Chainlink recovery → auto-resumes; or admin calls `updateVrfCoordinatorAndSub` |
| C | Admin subscription neglect | Admin never funds LINK subscription after deployment; same effect as Path A from day 0 | No (passive) | No (admin inaction) | 3 game days from deployment | Admin funds sub → operation resumes |
| D | Admin deploys reverting coordinator via `wireVrf` | Admin calls `wireVrf(revertingCoordinatorAddr, subId, keyHash)` — any subsequent `_requestRng` call reverts; `advanceGame()` stalls | **Yes** | No | 3 game days (1 call to `wireVrf`) | Admin calls `wireVrf` again with real coordinator (before stall) OR waits for `updateVrfCoordinatorAndSub` after stall |
| E | Admin-induced recovery loop | After Path D produces 3-day stall, admin calls `updateVrfCoordinatorAndSub` with real coordinator to resume, then repeats Path D; indefinitely repeatable griefing cycle | **Yes** | No | 3 game days per cycle | Each cycle recoverable by admin; only admin can stop the loop |

### Active Admin-Caused Stall: Step-by-Step Attack (Paths D + E)

**Prerequisites:** Attacker controls ADMIN key (or CREATOR key, or holds >30% DGVE tokens per the `isVaultOwner` check).

**Cycle execution:**

1. **Day 0 (any game day):** Attacker calls `wireVrf(revertingAddr, validSubId, validKeyHash)` where `revertingAddr` is a contract that reverts on `requestRandomWords`. No guard: `wireVrf` checks only `msg.sender == ContractAddresses.ADMIN`.

2. **Same day or next day:** Any caller attempts `advanceGame()`. The `rngGate` function calls `_requestRng`, which calls `vrfCoordinator.requestRandomWords`. The reverting coordinator causes a hard revert. `advanceGame()` reverts. No progress.

3. **Days D+1, D+2:** Same result — `advanceGame()` continues to revert. `rngWordByDay[D]`, `rngWordByDay[D+1]`, `rngWordByDay[D+2]` remain zero.

4. **Day D+3 or later:** `_threeDayRngGap` returns `true`. `updateVrfCoordinatorAndSub` is now callable.

5. **Recovery (optional):** Attacker calls `updateVrfCoordinatorAndSub(realCoordinatorAddr, subId, keyHash)`. This resets `rngLockedFlag=false`, `vrfRequestId=0`, `rngRequestTime=0`, `rngWordCurrent=0`. Game resumes.

6. **Repeat:** After any number of normal game days, attacker returns to step 1 and repeats the cycle.

**Effect per cycle:** 3+ game days of complete game halt (no `advanceGame()`, no VRF fulfillment, no level progression). Purchases may continue but cannot be processed.

**Forward note on GAS-07-I2:** The 18h retry mechanism in `rngGate` (`elapsed >= 18 hours → _requestRng()`) does not mitigate Path D. The retry calls `_requestRng` again, which again hard-reverts. The retry path extends delay but does not resolve it.

### Severity Assessment

Path D / Path E require ADMIN key compromise. Funds are not directly at risk — ETH accounting is unaffected by stalls. The attack halts game progress and could be used to:
- Delay jackpot resolution indefinitely
- Repeat stalls to frustrate players without causing fund loss

**ADMIN-03: MEDIUM** — 5 stall trigger paths enumerated; active path via `wireVrf` + reverting coordinator halts game in 3 game days without stall gate; recovery cycle exploitable as repeated griefing loop. Requires ADMIN key compromise; no direct fund loss.

---

## ADMIN-04: 18h RNG Lock Window Analysis

### rngLockedFlag Lifecycle

**Set by:** `_finalizeRngRequest` (called from both `_requestRng` and `_tryRequestRng` success path) — set at the moment a VRF request is recorded.

**Cleared by:**
- `_unlockRng(day)` — called after daily RNG processing completes in `advanceGame()`
- `updateVrfCoordinatorAndSub` — explicitly clears as part of emergency rotation

**Window duration:** From the VRF request submission until `rawFulfillRandomWords` delivers the word AND `advanceGame()` processes it. During normal Chainlink operation this is minutes to hours. During network delays or subscription issues, this can extend to the 18h retry boundary.

### Complete Blocked vs. Permitted Call Table

| Function | Location | Blocked by rngLockedFlag? | Check | Notes |
|----------|----------|--------------------------|-------|-------|
| `advanceGame()` | DegenerusGameAdvanceModule | YES (indirect) | `rngGate` → `revert RngNotReady()` | Reverts within 18h of request |
| `reverseFlip()` | DegenerusGameAdvanceModule | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | BURNIE nudge blocked during lock |
| `requestLootboxRng()` | DegenerusGameAdvanceModule | YES (direct) | `if (rngLockedFlag) revert E()` | Mid-day lootbox RNG request blocked |
| `openLootBox()` | DegenerusGameLootboxModule | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | **Note:** RESEARCH.md listed this as permitted; source confirms it is BLOCKED |
| `openBurnieLootBox()` | DegenerusGameLootboxModule | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | **Note:** RESEARCH.md listed this as permitted; source confirms it is BLOCKED |
| Whale ticket purchase in jackpot phase | DegenerusGameMintModule | YES (direct) | `if (rngLockedFlag) revert E()` (line 815) | Whale/claimable ticket purchases during jackpot phase blocked |
| Lootbox component of `purchase()` at jackpot levels | DegenerusGameMintModule | YES (conditional) | `if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E()` | Only blocked when all conditions met |
| `setDecimatorAutoRebuy()` | DegenerusGame | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | Preference change blocked |
| `_setAutoRebuy()` (via `setAutoRebuy`) | DegenerusGame | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | Auto-rebuy toggle blocked |
| `_setAutoRebuyTakeProfit()` | DegenerusGame | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | Take-profit setting blocked |
| `_setAfKingMode()` (via `setAfKingMode`) | DegenerusGame | YES (direct) | `if (rngLockedFlag) revert RngLocked()` | AfKing mode toggle blocked |
| `purchase()` (ticket-only, non-jackpot) | DegenerusGameMintModule | **NO** | No check on ticket path when not at jackpot level | Ticket purchases continue |
| `purchaseBurnieLootbox()` | DegenerusGame | **NO** | No rngLockedFlag check | BURNIE lootbox purchase queues; outcome pending separate RNG |
| `purchaseDeityPass()` | DegenerusGame | **NO** | No rngLockedFlag check | Pricing based on passes-sold counter; no RNG dependency |
| `claimWinnings()` | DegenerusGame | **NO** | No rngLockedFlag check | Uses pre-finalized `claimableWinnings[player]` |
| `claimDecimatorJackpot()` | DegenerusGame | **NO** | No rngLockedFlag check | Uses already-computed jackpot values |
| `resolveDegeneretteBets()` | DegenerusGameDegeneretteModule | **NO** | No rngLockedFlag check (flag read for context only at line 504) | Bet resolution uses daily word already recorded |
| `adminStakeEthForStEth()` | DegenerusAdmin | **NO** | No rngLockedFlag check | Admin staking operation; no RNG dependency |
| `setOperatorApproval()` | DegenerusGame | **NO** | No rngLockedFlag check | Access control setting; no RNG dependency |

### Front-Running Risk Assessment: Permitted Calls During 18h Lock

The critical question: can any operation permitted during the 18h lock window benefit from knowledge of the pending VRF word?

**`purchase()` (ticket-only path):**
Tickets purchased during the lock are recorded in `ticketsByDay[level][player]`. They are resolved in the next `advanceGame()` call using `rngWordByDay[day]`. The pending VRF word determines trait rarity and jackpot outcomes. Theoretically, a player with advance knowledge of the VRF word could purchase tickets to maximize favorable outcomes.

Assessment: **NO RISK.** The pending VRF word is the Chainlink coordinator's output from a committed random seed. It is inaccessible to anyone — including admin, validators, and Chainlink operators — until `rawFulfillRandomWords` is called. The 18h window is an extended wait period for unfulfilled requests; during this period the VRF word does not exist on-chain and cannot be known. When fulfillment occurs, `rngLockedFlag` remains `true` (the word is stored in `rngWordCurrent`, not yet applied) — but `advanceGame()` still reverts with `RngNotReady` until the next call after fulfillment. No purchase racing is possible.

**`purchaseBurnieLootbox()`:**
Queues a BURNIE lootbox. Outcome determined by a *separate* lootbox RNG word (`lootboxRngWordByIndex[index]`), not the daily game word. The daily game word pending in the 18h window has no effect on lootbox resolution.

Assessment: **NO RISK.** Different RNG source; no dependency on pending daily word.

**`purchaseDeityPass()`:**
Pricing uses the `passes sold` counter (`deityPassesSold`). Fixed formula: 24 + T(n) ETH. No RNG dependency.

Assessment: **NO RISK.** Entirely deterministic; VRF word irrelevant.

**`claimWinnings()`:**
Uses `claimableWinnings[player]` — values written by the previous `advanceGame()` call. These are finalized figures; the pending VRF word for the current day does not affect already-credited winnings.

Assessment: **NO RISK.** Pre-finalized values; no exposure to pending RNG.

**`claimDecimatorJackpot()`:**
Uses computed jackpot allocations set during jackpot resolution. Same reasoning as `claimWinnings()`.

Assessment: **NO RISK.** Pre-finalized values.

**`resolveDegeneretteBets()`:**
Uses `rngWordByDay[day]` for the current day. The check at line 504 reads `rngLockedFlag` only to set `jackpotResolutionActive` context — the resolution itself proceeds using the daily word if already recorded. If the daily word is not yet recorded (lock window active with no fulfilled word), `rngWordByDay[currentDay]` is zero and the resolution would either be skipped or use a prior day's word. No forward-looking RNG dependency.

Assessment: **NO RISK.** Resolution uses already-recorded words; cannot peek at pending word.

### ADMIN-04 Overall Verdict

The 18h RNG lock window does not create a front-running or oracle-exploitation window because:

1. The pending VRF word is cryptographically inaccessible until Chainlink fulfills the request — it exists only in the coordinator's off-chain computation.
2. All operations that continue during the lock (`purchase` tickets, `claimWinnings`, `purchaseBurnieLootbox`, `purchaseDeityPass`, `resolveDegeneretteBets`) use either pre-finalized values or separate RNG sources.
3. No validator/miner manipulation applies: ticket outcomes are determined by the Chainlink VRF word, not by `block.timestamp` or `prevrandao`.

**Correction note:** RESEARCH.md listed `openLootBox()` and `openBurnieLootBox()` as permitted during the 18h lock. Source inspection shows both functions check `if (rngLockedFlag) revert RngLocked()` as their first statement. They are BLOCKED. This does not affect the ADMIN-04 verdict — it reduces the attack surface further.

**ADMIN-04: PASS** — No state-changing call permitted during 18h lock can produce an outcome advantaged by knowledge of the pending VRF word; ticket purchases, withdrawals, and bet resolutions during the lock are all resolved against already-finalized or separately-sourced RNG. The blocked call list is broader than previously documented (auto-rebuy settings and lootbox opens also blocked).

### GAS-07-I2 Forwarded Finding Integration

The Phase 09 GAS-07-I2 forwarded finding — "VRF stall liveness dependency: if `_requestRng` always reverts, retry doesn't help" — maps directly to ADMIN-03 Path D. The 18h retry mechanism is the correct context for GAS-07-I2: it is a grace period for network delays, not a recovery mechanism for a deliberately misconfigured coordinator. Path D confirms the exact failure mode GAS-07-I2 anticipated.

---

## Files Created/Modified

- `.planning/phases/10-admin-power-vrf-griefing-and-assembly-safety/10-03-SUMMARY.md` — this document; ADMIN-03 + ADMIN-04 verdicts

## Decisions Made

- ADMIN-03 rated MEDIUM (C4 methodology): admin-key-required attack with game-halt consequence but no direct fund loss. If fund loss were possible (e.g., admin could drain ETH during stall), this would be HIGH.
- ADMIN-04 rated PASS: the 18h window analysis is primarily a "no-risk" confirmation, not a finding. The correction to the blocked call list (openLootBox blocked, not permitted) is informational.
- RESEARCH.md error documented but not a material impact — the openLootBox/openBurnieLootBox blocks strengthen the PASS verdict for ADMIN-04.

## Deviations from Plan

None — plan executed exactly as written. One factual correction found (RESEARCH.md listed openLootBox as permitted; source shows it is blocked). Correction documented above; it does not change any verdict.

## Issues Encountered

None.

## Next Phase Readiness

- ADMIN-03 and ADMIN-04 verdicts are complete and Phase 13-citable.
- ADMIN-05 (subscription drain economics) is next: depends on LINK cost per VRF request, subscription model, and MIN_LINK_FOR_LOOTBOX_RNG=40 LINK.
- ADMIN-06 (player-targeting) follows ADMIN-05.
- Phase 10-04 and 10-05 can proceed without blockers.

---

*Phase: 10-admin-power-vrf-griefing-and-assembly-safety*
*Completed: 2026-03-04*
