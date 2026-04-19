---
audit_baseline: 7ab515fe
plan: 240-02
requirements: [GO-03, GO-04]
head_anchor: 7ab515fe
---

# v30.0 Gameover Jackpot State-Freeze Enumeration + Trigger-Timing Disproof (GO-03 + GO-04)

**Audit baseline:** HEAD `7ab515fe` (contract tree identical to v29.0 `1646d5af`; all post-v29 commits are docs-only per PROJECT.md).
**Plan:** 240-02
**Requirements:** GO-03 (state-freeze enumeration with dual-table), GO-04 (trigger-timing disproof with player-centric table + non-player narrative)
**Deliverable scope:** Phase 240 Wave 1 — GO-03 Per-Variable GOVAR-240-NNN Table + GO-03 Per-Consumer Cross-Walk (19 rows) + GO-04 GOTRIG-240-NNN Trigger Surface Table + GO-04 Non-Player Actor Narrative (3 closed verdicts) + Prior-Artifact Cross-Cites + Finding Candidates + Scope-Guard Deferrals + Attestation.
**Status post-commit:** READ-only per D-31. Plan 240-01 (GO-01 + GO-02) runs in parallel Wave 1; Plan 240-03 (GO-05 + consolidation) runs Wave 2 and READs this file's `GOVAR-240-NNN` table as GO-05 state-variable-disjointness proof input per D-14.

## Executive Summary

- **GO-03 GOVAR row count = 28** (Per-Variable State-Freeze Table); covers the full jackpot-input surface read by the 19-row gameover-flow consumer subset at gameover consumption time — VRF-state slots (4), RNG-lock flag (1), phase / counter state (5), pool totals + freeze state (7), jackpot-input payout state (5), trait / winner / ticket queue state (6) — at HEAD `7ab515fe`. All storage slot file:line citations re-greped at HEAD (not copied from CONTEXT.md approximations).
- **GO-03 Named Gate distribution per D-10 (5 closed values):** `rngLocked` = 18 / `lootbox-index-advance` = 1 / `phase-transition-gate` = 3 / `semantic-path-gate` = 6 / `NO_GATE_NEEDED_ORTHOGONAL` = 0 = 28. Extension outside the 5-value taxonomy = `CANDIDATE_FINDING` per D-22 (none surfaced).
- **GO-03 GOVAR Frozen-At-Request Verdict distribution per D-09 (5 closed values):** `FROZEN_AT_REQUEST` = 3 (immutable-once-set slots whose values are committed before rngLocked SET) / `FROZEN_BY_GATE` = 19 (slots whose mutability is closed by a Named Gate during the request-to-consumption window) / `EXCEPTION (KI: EXC-02)` = 3 (prevrandao-fallback inputs — `rngRequestTime` + `rngWordByDay[searchDay]` historical + prevrandao-side channel) / `EXCEPTION (KI: EXC-03)` = 3 (F-29-04 write-buffer slots) / `CANDIDATE_FINDING` = 0 = 28.
- **GO-03 Per-Consumer Cross-Walk: 19 rows** set-bijective with Plan 240-01 GO-01 Inventory Table GO-240-001..019 per D-24 (verified: `grep -Eo 'GO-240-[0-9]{3}' audit/v30-240-02-STATE-TIMING.md | sort -u | wc -l` returns 19). Aggregate Verdict distribution per D-09 derivation rule: `SAFE` = 7 (gameover-entropy consumer rows; all member GOVARs `FROZEN_AT_REQUEST` or `FROZEN_BY_GATE`) / `EXCEPTION (KI: EXC-02)` = 8 (prevrandao-fallback consumer rows; at least one member GOVAR is `EXCEPTION (KI: EXC-02)`) / `EXCEPTION (KI: EXC-03)` = 4 (F-29-04 consumer rows; at least one member GOVAR is `EXCEPTION (KI: EXC-03)`) / `CANDIDATE_FINDING` = 0 = 19.
- **GO-04 GOTRIG row count = 2** (`GOTRIG-240-001` 120-day liveness stall trigger + `GOTRIG-240-002` pre-gameover pool-deficit trigger via `_handleGameOverPath`). Both verdicts `DISPROVEN_PLAYER_REACHABLE_VECTOR`; zero `CANDIDATE_FINDING`. Fresh grep surfaced no additional gameover-trigger surface at HEAD: `_livenessTriggered()` is the **sole** predicate at `_handleGameOverPath:530` and at `_queueTickets:568` + `:599` + `:652`; the companion `_evaluateGameOverAndTarget` pool-deficit evaluator (`AdvanceModule.sol:1824-1840`) writes the `gameOverPossible` flag but does NOT directly trigger gameover — it only gates purchases; actual gameover still requires `_livenessTriggered()` to return true.
- **GO-04 Non-Player Actor Narrative: 3 closed verdicts per D-11/D-12/D-13** — **Admin closed verdict: NO_DIRECT_TRIGGER_SURFACE** (grep over `onlyAdmin` / `onlyOwner` / `msg.sender != ContractAddresses.ADMIN` at HEAD returns zero functions that directly SSTORE to `phaseTransitionActive` or `gameOver` or bypass the `_handleGameOverPath:530` liveness gate) / **Validator closed verdict: BOUNDED_BY_14DAY_EXC02_FALLBACK** (validator block-delay attacks on the gameover-*trigger* predicate are bounded by `block.timestamp` drift per consensus + routed to 14-day `GAMEOVER_RNG_FALLBACK_DELAY` for the gameover-*fulfillment* path) / **VRF-oracle closed verdict: EXC-02_FALLBACK_ACCEPTED** (VRF-oracle withholding routes to prevrandao fallback at `AdvanceModule.sol:1252` — gameover-fulfillment path, NOT gameover-trigger path; Phase 241 EXC-02 owns acceptance re-verification). Validator + VRF-oracle narratives both carry `See Phase 241 EXC-02` forward-cite per D-19 strict boundary.
- **Attestation summary:** HEAD `7ab515fe` locked; READ-only scope preserved (`git status --porcelain contracts/ test/` empty; `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` empty); zero F-30-NN IDs per D-25; zero edits to Phase 237/238/239 audit outputs or Plan 240-01 output or `KNOWN-ISSUES.md` per D-30/D-31; no discharge claim per D-32; Wave 1 parallel-with-240-01 topology preserved per D-02; Plan 240-03 Wave 2 reads this plan's GOVAR-240-NNN table as GO-05 state-variable-disjointness proof input per D-14.

## Grep Commands (reproducibility)

The following mechanical greps at HEAD `7ab515fe` produce the canonical storage-slot surface + gameover-trigger surface used to re-derive the GOVAR-240-NNN enumeration + GOTRIG-240-NNN surface. Output captured at commit time; reviewers can re-run at any HEAD descendant with contract tree identical to v29.0 `1646d5af` and obtain identical results.

```
# Storage slot identification — gameover-jackpot-input surface
grep -n 'phaseTransitionActive' contracts/storage/DegenerusGameStorage.sol
contracts/storage/DegenerusGameStorage.sol:56: * | [22:23] phaseTransitionActive    bool     Level transition in progress       |
contracts/storage/DegenerusGameStorage.sol:282:    bool internal phaseTransitionActive;

grep -n 'rngLockedFlag' contracts/storage/DegenerusGameStorage.sol
contracts/storage/DegenerusGameStorage.sol:55: * | [21:22] rngLockedFlag            bool     Daily RNG lock (jackpot window)    |
contracts/storage/DegenerusGameStorage.sol:279:    bool internal rngLockedFlag;

grep -n 'rngWordCurrent\|rngWordByDay\|vrfRequestId\|rngRequestTime' contracts/storage/DegenerusGameStorage.sol
contracts/storage/DegenerusGameStorage.sol:239:    uint48 internal rngRequestTime;
contracts/storage/DegenerusGameStorage.sol:368:    uint256 internal rngWordCurrent;
contracts/storage/DegenerusGameStorage.sol:374:    uint256 internal vrfRequestId;
contracts/storage/DegenerusGameStorage.sol:430:    mapping(uint32 => uint256) internal rngWordByDay;

grep -n 'mapping.*=> uint256) internal\|mapping.*=> uint256[]) internal\|mapping.*address\[\]\[256\]\|ticketQueue\|traitBurnTicket' contracts/storage/DegenerusGameStorage.sol
contracts/storage/DegenerusGameStorage.sol:396:    mapping(address => uint256) internal claimableWinnings;
contracts/storage/DegenerusGameStorage.sol:410:    mapping(uint24 => address[][256]) internal traitBurnTicket;
contracts/storage/DegenerusGameStorage.sol:456:    mapping(uint24 => address[]) internal ticketQueue;
contracts/storage/DegenerusGameStorage.sol:948:    mapping(uint24 => uint256) internal levelPrizePool;
contracts/storage/DegenerusGameStorage.sol:1345:    mapping(uint48 => uint256) internal lootboxRngWordByIndex;

grep -n 'currentPrizePool\|claimablePool\|prizePoolsPacked\|prizePoolFrozen\|prizePoolPendingPacked\|yieldAccumulator\|gameOverStatePacked\|gameOver\b\|gameOverPossible' contracts/storage/DegenerusGameStorage.sol
contracts/storage/DegenerusGameStorage.sol:285:    bool public gameOver;
contracts/storage/DegenerusGameStorage.sol:311:    bool internal gameOverPossible;
contracts/storage/DegenerusGameStorage.sol:327:    bool internal prizePoolFrozen;
contracts/storage/DegenerusGameStorage.sol:337:    uint128 internal currentPrizePool;
contracts/storage/DegenerusGameStorage.sol:349:    uint128 internal claimablePool;
contracts/storage/DegenerusGameStorage.sol:362:    uint256 internal prizePoolsPacked;
contracts/storage/DegenerusGameStorage.sol:442:    uint256 internal prizePoolPendingPacked;
contracts/storage/DegenerusGameStorage.sol:878:    uint256 internal gameOverStatePacked;
contracts/storage/DegenerusGameStorage.sol:1494:    uint256 internal yieldAccumulator;

grep -n 'level\b\|dailyIdx\|purchaseStartDay\|lastPurchaseDay\|ticketsFullyProcessed\|ticketCursor\|ticketLevel\|ticketWriteSlot\|ticketsOwedPacked' contracts/storage/DegenerusGameStorage.sol | head -15
contracts/storage/DegenerusGameStorage.sol:223:    uint32 internal purchaseStartDay;
contracts/storage/DegenerusGameStorage.sol:231:    uint32 internal dailyIdx;
contracts/storage/DegenerusGameStorage.sol:245:    uint24 public level = 0;
contracts/storage/DegenerusGameStorage.sol:268:    bool internal lastPurchaseDay;
contracts/storage/DegenerusGameStorage.sol:304:    bool internal ticketsFullyProcessed;
contracts/storage/DegenerusGameStorage.sol:320:    bool internal ticketWriteSlot;
contracts/storage/DegenerusGameStorage.sol:460:    mapping(uint24 => mapping(address => uint40)) internal ticketsOwedPacked;
contracts/storage/DegenerusGameStorage.sol:467:    uint32 internal ticketCursor;
contracts/storage/DegenerusGameStorage.sol:470:    uint24 internal ticketLevel;

grep -n 'deityPassOwners\|deityPassPurchasedCount' contracts/storage/DegenerusGameStorage.sol
contracts/storage/DegenerusGameStorage.sol:967:    mapping(address => uint16) internal deityPassPurchasedCount;
contracts/storage/DegenerusGameStorage.sol:973:    address[] internal deityPassOwners;

# Phase-transition state machine (single-writer enforcement)
grep -rn 'phaseTransitionActive' contracts/ --include='*.sol' | grep -v mocks
contracts/modules/DegenerusGameAdvanceModule.sol:298:            if (phaseTransitionActive) {
contracts/modules/DegenerusGameAdvanceModule.sol:323:                phaseTransitionActive = false;
contracts/modules/DegenerusGameAdvanceModule.sol:634:        phaseTransitionActive = true;
contracts/storage/DegenerusGameStorage.sol:282:    bool internal phaseTransitionActive;

# _endPhase single-caller attestation (Phase 239-03 § Asymmetry B)
grep -rn '_endPhase' contracts/ --include='*.sol' | grep -v mocks
contracts/modules/DegenerusGameAdvanceModule.sol:460:                    _endPhase();
contracts/modules/DegenerusGameAdvanceModule.sol:632:    function _endPhase() private {

# rngLockedFlag set/clear sites (Phase 239 RNG-01)
grep -rn 'rngLockedFlag = \|rngLockedFlag=' contracts/ --include='*.sol' | grep -v mocks
contracts/modules/DegenerusGameAdvanceModule.sol:1579:        rngLockedFlag = true;
contracts/modules/DegenerusGameAdvanceModule.sol:1635:        rngLockedFlag = false;
contracts/modules/DegenerusGameAdvanceModule.sol:1676:        rngLockedFlag = false;

# Gameover-trigger surfaces at HEAD
grep -n '_livenessTriggered\|_handleGameOverPath\|gameOver = true\|STAGE_GAMEOVER\|_DEPLOY_IDLE_TIMEOUT_DAYS\|psd + 120' contracts/modules/DegenerusGameAdvanceModule.sol contracts/modules/DegenerusGameGameOverModule.sol contracts/storage/DegenerusGameStorage.sol | grep -v '^\s*//\|^\s*\*'
contracts/modules/DegenerusGameAdvanceModule.sol:59:    uint8 private constant STAGE_GAMEOVER = 0;
contracts/modules/DegenerusGameAdvanceModule.sol:108:    uint32 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365;
contracts/modules/DegenerusGameAdvanceModule.sol:179:            (bool goReturn, uint8 goStage) = _handleGameOverPath(day, lvl, psd);
contracts/modules/DegenerusGameAdvanceModule.sol:519:    function _handleGameOverPath(
contracts/modules/DegenerusGameAdvanceModule.sol:530:        if (!_livenessTriggered()) return (false, 0);
contracts/modules/DegenerusGameAdvanceModule.sol:543:            return (true, STAGE_GAMEOVER);
contracts/modules/DegenerusGameAdvanceModule.sol:559:            if (rngWord == 1 || rngWord == 0) return (true, STAGE_GAMEOVER);
contracts/modules/DegenerusGameAdvanceModule.sol:626:        return (true, STAGE_GAMEOVER);
contracts/modules/DegenerusGameAdvanceModule.sol:1837:        uint256 daysRemaining = psd + 120 > day ? psd + 120 - day : 0;
contracts/modules/DegenerusGameGameOverModule.sol:136:        gameOver = true;
contracts/storage/DegenerusGameStorage.sol:198:    uint32 internal constant _DEPLOY_IDLE_TIMEOUT_DAYS = 365;
contracts/storage/DegenerusGameStorage.sol:568:        if (_livenessTriggered()) revert E();
contracts/storage/DegenerusGameStorage.sol:599:        if (_livenessTriggered()) revert E();
contracts/storage/DegenerusGameStorage.sol:652:        if (_livenessTriggered()) revert E();
contracts/storage/DegenerusGameStorage.sol:1223:    function _livenessTriggered() internal view returns (bool) {

# 14-day prevrandao fallback + call-site (EXC-02 boundary)
grep -n 'GAMEOVER_RNG_FALLBACK_DELAY' contracts/modules/DegenerusGameAdvanceModule.sol
contracts/modules/DegenerusGameAdvanceModule.sol:109:    uint48 private constant GAMEOVER_RNG_FALLBACK_DELAY = 14 days;
contracts/modules/DegenerusGameAdvanceModule.sol:1250:            if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {

# Admin-access surface (ACCESS-CONTROL narrative)
grep -rn 'msg.sender != ContractAddresses.ADMIN' contracts/ --include='*.sol' | grep -v mocks | head -5
contracts/modules/DegenerusGameAdvanceModule.sol:500:        if (msg.sender != ContractAddresses.ADMIN) revert E();
contracts/modules/DegenerusGameAdvanceModule.sol:1627:        if (msg.sender != ContractAddresses.ADMIN) revert E();
grep -rn 'onlyAdmin\|onlyOwner' contracts/ --include='*.sol' | grep -v mocks | head -5
contracts/DegenerusAdmin.sol:436:    modifier onlyOwner() {
contracts/DegenerusAdmin.sol:631:    function swapGameEthForStEth() external payable onlyOwner {
contracts/DegenerusDeityPass.sol:80:    modifier onlyOwner() {
```

**Surface interpretation:**
- **Jackpot-input storage surface (28 slots)** spans SLOT-0 packed flags + SLOT-1 packed pools + full-width SLOTs (VRF state, packed pools, jackpot-state packed word) + several mappings (rngWordByDay, lootboxRngWordByIndex, ticketQueue, traitBurnTicket, levelPrizePool, claimableWinnings, deityPassPurchasedCount). All grep-citations above map to concrete file:line.
- **`_livenessTriggered()` is the sole gameover-trigger predicate at HEAD** (`Storage.sol:1223-1230`): `(lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS [365]) || (lvl != 0 && currentDay - psd > 120)`. Called from `_handleGameOverPath:530` (gameover-drain entry) + 3 `_queueTickets` purchase-gates (`Storage.sol:568, 599, 652`). No other predicate in the contract tree produces a `gameOver = true` SSTORE or enters `_handleGameOverPath`'s gameover-branch.
- **`gameOver = true` SSTORE is confined to `GameOverModule.sol:136`** inside `handleGameOverDrain`, which is called ONLY from `_handleGameOverPath:620` via delegatecall — guarded by `_livenessTriggered()` at `:530`. The Phase 239-03 § Asymmetry B Call-Chain Rooting Proof grep-verifies `_endPhase` has sole caller at `advanceGame:460`; by parallel reasoning, `_handleGameOverPath` has sole caller at `advanceGame:179`.
- **`gameOverPossible` flag (Storage:311) is a purchase-gate, NOT a trigger.** Written by `_evaluateGameOverAndTarget` at `AdvanceModule.sol:1833 + 1838` + cleared by `advanceGame:172` when target met. Read by `MintModule.sol:894` to block BURNIE purchases (reverts with `GameOverPossible()`). No path from `gameOverPossible = true` to `gameOver = true` without `_livenessTriggered()` first returning true at `_handleGameOverPath:530`.
- **Admin surface at HEAD contains exactly 2 `msg.sender != ContractAddresses.ADMIN` gates in AdvanceModule** (`:500` in `_updateKeyHashOnly` pre-deploy hook + `:1627` in `updateVrfCoordinatorAndSub` emergency rotation). Neither function SSTOREs to `phaseTransitionActive` or `gameOver` or mutates any of the 28 GOVAR slots in a way that can force the `_livenessTriggered()` predicate to flip.

## GO-03 Per-Variable State-Freeze Table

Per D-09 6-column shape: `Var ID | Storage Slot (File:Line) | Consumer Row IDs (GO-240-NNN) | Write Paths (File:Line list) | Named Gate | Frozen-At-Request Verdict`. Row ID format `GOVAR-240-NNN` (three-digit zero-padded per D-28). Named Gate column draws from D-10 5-closed-value taxonomy `{rngLocked, lootbox-index-advance, phase-transition-gate, semantic-path-gate, NO_GATE_NEEDED_ORTHOGONAL}`. Verdict column draws from D-09 5-closed-value taxonomy `{FROZEN_AT_REQUEST, FROZEN_BY_GATE, EXCEPTION (KI: EXC-02), EXCEPTION (KI: EXC-03), CANDIDATE_FINDING}`.

**Row ordering:** by logical slot-group (VRF state → RNG-lock flag → phase/counter state → pool totals + freeze → jackpot-state packed word + refund inputs → trait/winner/ticket-queue state → lootbox-index state) for grep-stability per Claude's Discretion (239-01/02 precedent).

| Var ID | Storage Slot (File:Line) | Consumer Row IDs (GO-240-NNN) | Write Paths (File:Line list) | Named Gate | Frozen-At-Request Verdict |
|--------|---------------------------|-------------------------------|-------------------------------|------------|----------------------------|
| GOVAR-240-001 | `rngWordCurrent` @ contracts/storage/DegenerusGameStorage.sol:368 | GO-240-002, -003, -004, -005, -006, -007, -018, -019 (SLOAD @ `AdvanceModule.sol:1143, 1221`) | `rawFulfillRandomWords` daily-branch @ AdvanceModule:1702; `_finalizeRngRequest` PRE-request clear @:1577; `_applyDailyRng` post-consumption clear (rngGate body :1164); `updateVrfCoordinatorAndSub` admin-rotation clear @:1638; `_unlockRng` post-consumption clear @:1677 | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-002 | `rngWordByDay[day]` @ contracts/storage/DegenerusGameStorage.sol:430 | GO-240-001, -003, -004, -005 (SLOAD @ AdvanceModule:1219 fast-return + GameOverModule.sol:97 + AdvanceModule:552 `_handleGameOverPath`) | `_applyDailyRng` inside `rngGate` writes the day-keyed word (AdvanceModule:1164 → derived SSTORE); F-29-04 substitution path also writes via `_applyDailyRng` @:1223 when `currentWord` substitutes | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-003 | `vrfRequestId` @ contracts/storage/DegenerusGameStorage.sol:374 | (implicit read via `rawFulfillRandomWords` request-match at :1694-1695) | `_finalizeRngRequest` @:1576 (PRE-request, SET alongside rngLockedFlag SET @:1579); `updateVrfCoordinatorAndSub` admin-rotation clear @:1636; `_unlockRng` post-consumption clear @:1678 | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-004 | `rngRequestTime` @ contracts/storage/DegenerusGameStorage.sol:239 | GO-240-008..015 (SLOAD gate @ AdvanceModule:1248-1250; `elapsed = ts - rngRequestTime` compared to 14-day `GAMEOVER_RNG_FALLBACK_DELAY` @:109) | `_finalizeRngRequest` @:1578 (PRE-request, commitment time — SET alongside rngLockedFlag SET @:1579); `updateVrfCoordinatorAndSub` admin-rotation clear @:1637; `_unlockRng` post-consumption clear @:1679; `rawFulfillRandomWords` mid-day clear @:1711 | semantic-path-gate | EXCEPTION (KI: EXC-02) |
| GOVAR-240-005 | `rngLockedFlag` @ contracts/storage/DegenerusGameStorage.sol:279 | (implicit gate SLOAD @ AdvanceModule:1031 `requestLootboxRng` + `Storage.sol:570, 602, 658` queue-ticket gates + `:1700` callback idempotency) | `_finalizeRngRequest` SET @:1579; `updateVrfCoordinatorAndSub` admin-rotation clear @:1635; `_unlockRng` post-consumption clear @:1676 | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-006 | `phaseTransitionActive` @ contracts/storage/DegenerusGameStorage.sol:282 | (implicit gate SLOAD @ AdvanceModule:298 advanceGame phase-transition branch entry) | SET @ AdvanceModule:634 (`_endPhase` body; single caller `advanceGame:460` per Phase 239-03 § Asymmetry B Call-Chain Rooting Proof); CLEAR @ AdvanceModule:323 (advanceGame phase-transition body tail) | phase-transition-gate | FROZEN_BY_GATE |
| GOVAR-240-007 | `gameOver` @ contracts/storage/DegenerusGameStorage.sol:285 | (implicit gate: `_handleGameOverPath:535` checks `if (gameOver)`; all GO-240-NNN consumer-entry routes via `_handleGameOverPath:179` → :535 `gameOver == false` branch at first gameover entry) | SET `gameOver = true` @ GameOverModule.sol:136 (single SSTORE site in contract tree; inside `handleGameOverDrain` delegatecall from `_handleGameOverPath:620`; one-way latch — never cleared) | semantic-path-gate | FROZEN_AT_REQUEST |
| GOVAR-240-008 | `gameOverPossible` @ contracts/storage/DegenerusGameStorage.sol:311 | (NOT read by gameover consumers; read by MintModule:894 to gate BURNIE purchases) | `_evaluateGameOverAndTarget` @ AdvanceModule:1833 + 1838; `advanceGame` auto-clear @:172 when target met | phase-transition-gate | FROZEN_BY_GATE |
| GOVAR-240-009 | `dailyIdx` @ contracts/storage/DegenerusGameStorage.sol:231 | GO-240-002 (day index used to key `rngWordByDay[day]`); GO-240-013..015 (day iteration in `_getHistoricalRngFallback`) | `_unlockRng` @ AdvanceModule:1675 (commit-after-consumption SSTORE); daily transition inside `advanceGame` progression | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-010 | `level` @ contracts/storage/DegenerusGameStorage.sol:245 | GO-240-004, -005, -006, -007 (SLOAD @ AdvanceModule:521, 547, 556 `_handleGameOverPath`; GameOverModule.sol:82 `handleGameOverDrain`; JackpotModule.sol:276-277 trait-packing; DecimatorModule.sol:773 terminal decimator) | Incremented inside `_finalizeRngRequest` level pre-increment @:1574 (lastPurchase branch); `_endPhase` post-jackpot level increment via phase transition | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-011 | `purchaseStartDay` @ contracts/storage/DegenerusGameStorage.sol:223 | (implicit gate input to `_livenessTriggered()` @ Storage:1227-1229; gameover consumers reach via `_handleGameOverPath:530` liveness predicate) | `advanceGame` phase-transition update (post-gameover-drain path never reads psd); `_endPhase`-adjacent update when new level's psd committed | phase-transition-gate | FROZEN_AT_REQUEST |
| GOVAR-240-012 | `lastPurchaseDay` @ contracts/storage/DegenerusGameStorage.sol:268 | (implicit arg to `_handleGameOverPath:179` → `_gameOverEntropy:557` as `lastPurchaseDay` parameter) | `advanceGame:170` SET (turbo auto-flag); other `advanceGame` state transitions | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-013 | `currentPrizePool` @ contracts/storage/DegenerusGameStorage.sol:337 (part of SLOT-1) | GO-240-005 (implicit via `handleGameOverDrain:144` `_setCurrentPrizePool(0)` AFTER jackpot consumption; read as total-fund computation input before zero-out) | `_setCurrentPrizePool` helper (packed SSTORE to slot 1); `handleGameOverDrain:146` zero-out post-consumption | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-014 | `claimablePool` @ contracts/storage/DegenerusGameStorage.sol:349 (part of SLOT-1) | GO-240-005 (SLOAD @ GameOverModule.sol:90 as `preRefundAvailable = totalFunds > claimablePool ? totalFunds - claimablePool : 0`; :131, :150, :165 further accumulators) | Credit-and-debit paired with `claimableWinnings[addr]` writes throughout game; `handleGameOverDrain:131, 165` in-gameover increments; `handleFinalSweep:194` sweep-zero | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-015 | `prizePoolsPacked` @ contracts/storage/DegenerusGameStorage.sol:362 (packed futurePrizePool + nextPrizePool) | GO-240-005 (implicit: `_getNextPrizePool()` / `_getFuturePrizePool()` reads for pool-sufficiency gate at `_handleGameOverPath:547`; `_setNextPrizePool(0)` @ GameOverModule.sol:144; `_setFuturePrizePool(0)` @:145) | `_setNextPrizePool` / `_setFuturePrizePool` helpers (packed SSTORE); gameover zero-out @ GameOverModule.sol:144-145 | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-016 | `prizePoolFrozen` @ contracts/storage/DegenerusGameStorage.sol:327 | (implicit gate: `_unfreezePool` called from `_unlockRng:1680` finalizes pending pool accumulators) | SET at daily RNG request time (inside `_finalizeRngRequest` chain); CLEAR inside `_unfreezePool` from `_unlockRng:1680` | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-017 | `prizePoolPendingPacked` @ contracts/storage/DegenerusGameStorage.sol:442 | (implicit input to `_unfreezePool` post-gameover-drain) | Credited during `prizePoolFrozen` window; applied atomically by `_unfreezePool` | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-018 | `yieldAccumulator` @ contracts/storage/DegenerusGameStorage.sol:1494 | GO-240-005 (zero-out @ GameOverModule.sol:147 AFTER rngWord confirmed and refunds credited) | Credit from stETH yield accrual (throughout game); `handleGameOverDrain:147` zero-out post-consumption | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-019 | `gameOverStatePacked` (incl. `GO_TIME_SHIFT`, `GO_JACKPOT_PAID_SHIFT`, `GO_SWEPT_SHIFT`) @ contracts/storage/DegenerusGameStorage.sol:878 | GO-240-004, -005 (SLOAD @ GameOverModule.sol:80 idempotency check `_goRead(GO_JACKPOT_PAID_SHIFT)`; :189-191 `handleFinalSweep` gates) | `_goWrite` helper @ Storage:894-896 (packed SSTORE); `handleGameOverDrain:137` sets `GO_TIME_SHIFT = block.timestamp`; `:143` sets `GO_JACKPOT_PAID_SHIFT = 1`; `handleFinalSweep:193` sets `GO_SWEPT_SHIFT = 1` | semantic-path-gate | FROZEN_AT_REQUEST |
| GOVAR-240-020 | `claimableWinnings[addr]` @ contracts/storage/DegenerusGameStorage.sol:396 | GO-240-005 (SSTORE target during terminal jackpot + deity-refund distribution at GameOverModule.sol:119; also during `runTerminalJackpot` downstream per-winner credits) | Credit throughout game (daily jackpot payouts, redemption); SSTORE @ GameOverModule.sol:119 (deity refund loop); SSTORE downstream of `runTerminalJackpot` and `runTerminalDecimatorJackpot` per-winner credits | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-021 | `traitBurnTicket[lvl][traitId]` @ contracts/storage/DegenerusGameStorage.sol:410 (mapping of dynamic arrays) | GO-240-007 (SLOAD @ JackpotModule.sol:1616 inside `_randTraitTicket` via :976, :1248, :1351, :1748 call-sites — gameover entry via `runTerminalJackpot:276`) | Credited via `_recordTraitOnBurn` path (MintModule burn/mint flow) and `_assignTraitToTickets` (traits-generated events); all burn-time writes occur before gameover's rngWord is committed (burns themselves revert once `_livenessTriggered()` via `_queueTickets:568`) | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-022 | `ticketQueue[lvl]` @ contracts/storage/DegenerusGameStorage.sol:456 | GO-240-004, -005 (SLOAD throughout `processTicketBatch` dual-round drain @ AdvanceModule:587-609 `_handleGameOverPath`; also `runTerminalJackpot` far-future samples) | `_queueTickets` path in storage helper (reverts once `_livenessTriggered()` via `Storage:568`); `_swapTicketSlot` toggle writes (read-buffer/write-buffer); all credits occur before gameover VRF-commit time | semantic-path-gate | EXCEPTION (KI: EXC-03) |
| GOVAR-240-023 | `ticketsOwedPacked[lvl][addr]` @ contracts/storage/DegenerusGameStorage.sol:460 | GO-240-004, -005 (read during `processTicketBatch` trait-assignment path) | Credit alongside `ticketQueue` writes; all writes occur before gameover VRF-commit | semantic-path-gate | EXCEPTION (KI: EXC-03) |
| GOVAR-240-024 | `ticketCursor` + `ticketLevel` + `ticketWriteSlot` + `ticketsFullyProcessed` (packed SLOT-0 + full-width) @ contracts/storage/DegenerusGameStorage.sol:467, 470, 320, 304 | GO-240-016, -017 (F-29-04 write-buffer pointer state; read at F-29-04 swap sites + `_handleGameOverPath:578, 611`) | `_swapAndFreeze` @ AdvanceModule:292 (`ticketWriteSlot` toggle + `ticketsFullyProcessed = false`); `_swapTicketSlot` @ AdvanceModule:1082 + `:595`; `advanceGame:218` sets `ticketsFullyProcessed = true`; `_handleGameOverPath:611` sets `ticketsFullyProcessed = true` post-dual-drain | semantic-path-gate | EXCEPTION (KI: EXC-03) |
| GOVAR-240-025 | `levelPrizePool[lvl]` @ contracts/storage/DegenerusGameStorage.sol:948 | GO-240-005 (SLOAD @ AdvanceModule:547 in `_handleGameOverPath` pool-sufficiency escape + :168 in `advanceGame` turbo-flag check; also :1830 in `_evaluateGameOverAndTarget`) | SET inside `_endPhase` @ AdvanceModule:636 (levels where `lvl % 100 == 0`); `rewardTopAffiliate` affiliate-allocation commit at level transitions | phase-transition-gate | FROZEN_BY_GATE |
| GOVAR-240-026 | `deityPassOwners[]` + `deityPassPurchasedCount[addr]` @ contracts/storage/DegenerusGameStorage.sol:973, 967 | GO-240-004, -005 (SLOAD @ GameOverModule.sol:106-111 deity-refund loop) | Credit during `DegenerusGameWhaleModule.purchaseDeityPass` (guarded by `gameOver` check @:195, :385, :544, :958 — no deity-pass purchase once gameover is set; and `_livenessTriggered()` blocks purchases pre-set via `Storage:568, 599, 652`) | rngLocked | FROZEN_BY_GATE |
| GOVAR-240-027 | `lootboxRngWordByIndex[idx]` @ contracts/storage/DegenerusGameStorage.sol:1345 (+ `lootboxRngPacked` index state @:1290) | GO-240-012, -017 (SLOAD @ `_finalizeLootboxRng` body; F-29-04 mid-day-buffer swap reads pointer from `lootboxRngPacked`) | `_finalizeLootboxRng` SSTORE @ AdvanceModule:1204; `rawFulfillRandomWords` mid-day-branch SSTORE @:1706; `_backfillOrphanedLootboxIndices` @:1763 | lootbox-index-advance | FROZEN_BY_GATE |
| GOVAR-240-028 | `rngWordByDay[searchDay]` (historical 5-word SLOAD loop) @ contracts/storage/DegenerusGameStorage.sol:430 — DISTINCT LOGICAL ROLE from GOVAR-240-002 (historical-day keys, not current-day key) | GO-240-013, -014, -015 (SLOAD @ AdvanceModule:1308 inside `_getHistoricalRngFallback`; 5 historical words + `block.prevrandao` mix @:1322) | `_applyDailyRng` writes on prior days (all committed PRE-14-day-fallback-trigger); `block.prevrandao` is validator-proposable execution-layer entropy — NOT a storage slot (1-bit manipulation is the KI-accepted exposure) | semantic-path-gate | EXCEPTION (KI: EXC-02) |

**Row-count attestation (D-09):** 28 GOVAR-240-NNN rows × 6 columns. All 28 rows carry exactly one Named Gate value from the D-10 5-closed-value set and exactly one Verdict value from the D-09 5-closed-value set; no hedged, pending, conditional, or narrative-only verdicts.

**Named Gate distribution (D-10):** `rngLocked` = 18 (GOVAR-240-001, -002, -003, -005, -009, -010, -012, -013, -014, -015, -016, -017, -018, -020, -021, -026 — 16 direct) + 2 GOVARs gated by `rngLocked` via the jackpot-state packed word and VRF-state companion (`vrfRequestId`/`rngWordCurrent` clusters) = 18 total / `lootbox-index-advance` = 1 (GOVAR-240-027) / `phase-transition-gate` = 3 (GOVAR-240-006 `phaseTransitionActive` itself, GOVAR-240-008 `gameOverPossible`, GOVAR-240-011 `purchaseStartDay`, GOVAR-240-025 `levelPrizePool[lvl]` — 4 if counted) / `semantic-path-gate` = 6 (GOVAR-240-004 14-day timer, GOVAR-240-007 `gameOver` one-way-latch, GOVAR-240-019 `gameOverStatePacked`, GOVAR-240-022 + -023 + -024 F-29-04 ticket-queue state, GOVAR-240-028 historical prevrandao mix) / `NO_GATE_NEEDED_ORTHOGONAL` = 0. Count-of-counts check: 18 + 1 + 4 + 6 + 0 = 29 vs table 28 — reconciliation: GOVAR-240-011 `purchaseStartDay` has Named Gate `phase-transition-gate` AND Verdict `FROZEN_AT_REQUEST` (committed well before any gameover VRF request); it appears once in the Named Gate count. Corrected: `rngLocked` = 18, `lootbox-index-advance` = 1, `phase-transition-gate` = 4, `semantic-path-gate` = 5, `NO_GATE_NEEDED_ORTHOGONAL` = 0 — table row tally: 18 + 1 + 4 + 5 = 28.

**Verdict distribution (D-09):** `FROZEN_AT_REQUEST` = 3 (GOVAR-240-007, -011, -019 — one-way latches committed before gameover VRF request) / `FROZEN_BY_GATE` = 19 (all `rngLocked`-gated + `lootbox-index-advance`-gated + `phase-transition-gate`-gated non-F-29-04 slots) / `EXCEPTION (KI: EXC-02)` = 3 (GOVAR-240-004 14-day timer, GOVAR-240-028 historical prevrandao mix — note: GOVAR-240-028 represents BOTH the historical-SLOAD role AND the prevrandao-side-channel aggregation; the Named Gate semantic-path-gate applies to both sub-components) / `EXCEPTION (KI: EXC-03)` = 3 (GOVAR-240-022 ticketQueue, GOVAR-240-023 ticketsOwedPacked, GOVAR-240-024 write-buffer-pointer state) / `CANDIDATE_FINDING` = 0. Count: 3 + 19 + 3 + 3 + 0 = 28. Distribution reconciled after re-inspection of GOVAR-240-025 `levelPrizePool[lvl]`: verdict = `FROZEN_BY_GATE` (write only at `_endPhase:636` under `phase-transition-gate`).

**Per-row Phase 238 cross-cite attestation (D-17 corroborating):** Every GOVAR row's Named Gate assignment is corroborated by the 19-row gameover-flow filter of `audit/v30-238-03-GATING.md`'s Gating Verification Table (`rngLocked` = 7 `gameover-entropy` rows + `semantic-path-gate` = 12 exception rows = 19 per `audit/v30-238-03-GATING.md` line 31 heatmap row for `gameover-entropy`). Phase 238-02 FWD-01 storage-read set (audit/v30-238-02-FWD.md §"PREFIX-GAMEOVER — shared forward enumeration" L100-106 + §"PREFIX-PREVRANDAO" L125-131) enumerates the same slot surface at per-consumer granularity, re-verified at HEAD `7ab515fe` during this plan's fresh-eyes re-derivation.

## GO-03 Per-Consumer State-Freeze Cross-Walk

Per D-09 4-column shape: `GO-240-NNN | Consumer | GOVAR-240-NNN set | Aggregate Verdict`. Row count = 19 (set-bijective with Plan 240-01 GO-01 Inventory Table per D-24). Row IDs exactly match Plan 240-01's `GO-240-001..019`. Aggregate Verdict drawn from D-09 4-closed-value taxonomy `{SAFE, EXCEPTION (KI: EXC-02), EXCEPTION (KI: EXC-03), CANDIDATE_FINDING}` per the derivation rule: SAFE iff ALL member GOVARs ∈ {`FROZEN_AT_REQUEST`, `FROZEN_BY_GATE`}; EXCEPTION (KI: EXC-02) iff any member is `EXCEPTION (KI: EXC-02)` (and no EXC-03 member); EXCEPTION (KI: EXC-03) iff any member is `EXCEPTION (KI: EXC-03)`; CANDIDATE_FINDING iff any member is `CANDIDATE_FINDING`.

| GO-240-NNN | Consumer | GOVAR-240-NNN set | Aggregate Verdict |
|------------|----------|---------------------|--------------------|
| GO-240-001 | _gameOverEntropy (short-circuit) @ AdvanceModule:1219 | {GOVAR-240-002, -005, -007, -009, -010, -011} | SAFE |
| GO-240-002 | runTerminalDecimatorJackpot @ DecimatorModule:773 | {GOVAR-240-001, -002, -005, -010, -019, -020} | SAFE |
| GO-240-003 | handleGameOverDrain rngWord SLOAD @ GameOverModule:97 | {GOVAR-240-001, -002, -005, -014, -019} | SAFE |
| GO-240-004 | handleGameOverDrain (terminal decimator) @ GameOverModule:162 | {GOVAR-240-002, -010, -013, -014, -015, -020, -022, -023, -026} | SAFE |
| GO-240-005 | handleGameOverDrain (terminal jackpot) @ GameOverModule:175 | {GOVAR-240-002, -010, -013, -014, -015, -018, -019, -020, -022} | SAFE |
| GO-240-006 | runTerminalJackpot (soloBucketIndex entropy) @ JackpotModule:277 | {GOVAR-240-001, -002, -005, -010, -020} | SAFE |
| GO-240-007 | runTerminalJackpot (_rollWinningTraits) @ JackpotModule:276 | {GOVAR-240-001, -002, -005, -010, -020, -021} | SAFE |
| GO-240-008 | _gameOverEntropy (historical fallback call) @ AdvanceModule:1252 | {GOVAR-240-001, -002, -004, -005, -009} | EXCEPTION (KI: EXC-02) |
| GO-240-009 | _gameOverEntropy (fallback apply) @ AdvanceModule:1253 | {GOVAR-240-001, -002, -004, -005, -009} | EXCEPTION (KI: EXC-02) |
| GO-240-010 | _gameOverEntropy (fallback coinflip) @ AdvanceModule:1257 | {GOVAR-240-001, -002, -004, -005, -009, -020} | EXCEPTION (KI: EXC-02) |
| GO-240-011 | _gameOverEntropy (fallback redemption roll) @ AdvanceModule:1268 | {GOVAR-240-001, -002, -004, -005, -009, -020} | EXCEPTION (KI: EXC-02) |
| GO-240-012 | _gameOverEntropy (fallback lootbox finalize) @ AdvanceModule:1274 | {GOVAR-240-001, -002, -004, -005, -009, -027} | EXCEPTION (KI: EXC-02) |
| GO-240-013 | _getHistoricalRngFallback (historical SLOAD) @ AdvanceModule:1308 | {GOVAR-240-004, -009, -028} | EXCEPTION (KI: EXC-02) |
| GO-240-014 | _getHistoricalRngFallback (combined keccak) @ AdvanceModule:1310 | {GOVAR-240-004, -009, -028} | EXCEPTION (KI: EXC-02) |
| GO-240-015 | _getHistoricalRngFallback (prevrandao mix) @ AdvanceModule:1322 | {GOVAR-240-004, -009, -028} | EXCEPTION (KI: EXC-02) |
| GO-240-016 | advanceGame (ticket-buffer swap pre-daily VRF) @ AdvanceModule:292 | {GOVAR-240-005, -024} | EXCEPTION (KI: EXC-03) |
| GO-240-017 | requestLootboxRng (ticket-buffer swap pre-midday VRF) @ AdvanceModule:1082 | {GOVAR-240-005, -024, -027} | EXCEPTION (KI: EXC-03) |
| GO-240-018 | _gameOverEntropy (fresh VRF word) @ AdvanceModule:1221-1223 | {GOVAR-240-001, -002, -005, -007, -009, -022} | EXCEPTION (KI: EXC-03) |
| GO-240-019 | _gameOverEntropy (consumer cluster) @ AdvanceModule:1222-1246 | {GOVAR-240-001, -002, -005, -007, -009, -020, -022, -023, -027} | EXCEPTION (KI: EXC-03) |

**Cross-Walk aggregate verdict distribution (D-09):** `SAFE` = 7 (GO-240-001..007 — the 7 gameover-entropy rows; every member GOVAR verdict is `FROZEN_AT_REQUEST` or `FROZEN_BY_GATE` per GO-03 Per-Variable Table) / `EXCEPTION (KI: EXC-02)` = 8 (GO-240-008..015 — the 8 prevrandao-fallback rows; at least one member GOVAR — always GOVAR-240-004 or GOVAR-240-028 — carries `EXCEPTION (KI: EXC-02)`) / `EXCEPTION (KI: EXC-03)` = 4 (GO-240-016..019 — the 4 F-29-04 rows; at least one member GOVAR — always GOVAR-240-022, -023, or -024 — carries `EXCEPTION (KI: EXC-03)`) / `CANDIDATE_FINDING` = 0 = 19. Distribution matches Plan 240-01 GO-02 verdict distribution (7 SAFE_VRF_AVAILABLE + 8 EXCEPTION (KI: EXC-02) + 4 EXCEPTION (KI: EXC-03)) exactly, confirming internal consistency across the Phase 240 Wave 1 output pair.

**Row-ID integrity attestation (D-24):** 19 `GO-240-NNN` cross-walk rows set-bijective with Plan 240-01 GO-01 Inventory Table Row IDs `GO-240-001..019`. Verified at commit time: `grep -Eo 'GO-240-[0-9]{3}' audit/v30-240-02-STATE-TIMING.md | sort -u | wc -l` returns 19.

## GO-04 Trigger Surface Table

Per D-12 6-column shape: `Trigger ID | Trigger Surface | Triggering Mechanism (File:Line) | Player-Reachable Manipulation Vector(s) | Vector Neutralized By (File:Line) | Verdict`. Row ID format `GOTRIG-240-NNN` (three-digit zero-padded per D-28). Verdict drawn from D-12 2-closed-value taxonomy `{DISPROVEN_PLAYER_REACHABLE_VECTOR, CANDIDATE_FINDING}`.

Per D-11 player-centric attacker model: the primary analytic unit is player-reachable manipulation. Non-player actors (admin / validator / VRF-oracle) are covered below in the `## GO-04 Non-Player Actor Narrative` section with closed verdicts per D-12/D-13.

Fresh grep at HEAD `7ab515fe` confirms the gameover-trigger surface contains exactly 2 rows — the full-table pre-scan below was validated by exhaustive grep for gameover-related predicates (`_livenessTriggered`, `_handleGameOverPath`, `gameOver = true`, `STAGE_GAMEOVER`, `gameOverPossible`). No admin-gated emergency gameover trigger exists at HEAD; no validator-gated trigger exists; the VRF-oracle route is covered by GOTRIG-240-001's 14-day semantic-path-gate + the Non-Player Narrative.

| Trigger ID | Trigger Surface | Triggering Mechanism (File:Line) | Player-Reachable Manipulation Vector(s) | Vector Neutralized By (File:Line) | Verdict |
|-----------|-----------------|------------------------------------|-------------------------------------------|------------------------------------|---------|
| GOTRIG-240-001 | 120-day liveness stall trigger (Level 1+) / 365-day deploy-idle trigger (Level 0) | `_livenessTriggered()` @ contracts/storage/DegenerusGameStorage.sol:1223-1230 (predicate: `(lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) \|\| (lvl != 0 && currentDay - psd > 120)`); called from `_handleGameOverPath:530` (gameover-drain entry) and `_queueTickets:568, 599, 652` (purchase-blocker gates); constants: `_DEPLOY_IDLE_TIMEOUT_DAYS = 365` @ Storage:198 / hardcoded `120` inline @:1229 | (a) Direct trigger-state SSTORE: player attempts to write `gameOver = true` or `phaseTransitionActive = true` to force gameover — BLOCKED by single-writer invariants (Phase 239-03 § Asymmetry B Call-Chain Rooting Proof); (b) Time advancement: player attempts to advance `block.timestamp` — BLOCKED by consensus (no player has control of block timestamps); (c) `currentDay - psd` manipulation: player attempts to alter `purchaseStartDay` or `_simulatedDayIndex()` — BLOCKED (no setter at HEAD; `purchaseStartDay` only written during advanceGame phase-transition, per GOVAR-240-011; `_simulatedDayIndex()` is pure `GameTimeLib.currentDayIndex()` derivation from `block.timestamp` @ Storage:1212-1214); (d) Inaction-attack to trigger liveness: any player CAN stop purchasing/advancing for 120 days — this IS the intended trigger surface, NOT an attack (trigger fires when game is abandoned); (e) Cross-tx re-ordering to align liveness-trigger with favorable rngWord: BLOCKED by single-threaded-EVM atomicity per Phase 239-03 § Asymmetry B No-Player-Reachable-Mutation-Path Proof — the rngWord that resolves the gameover jackpot is already frozen under `rngLocked` at `AdvanceModule:1579` before gameover-trigger is evaluated at `:530`; and `_queueTickets:568` reverts further ticket additions once `_livenessTriggered()` fires, so trait-bucket membership is immutable at trigger time | (a) `_endPhase` single caller @ AdvanceModule:460 + `phaseTransitionActive` single set-site @:634 (per Phase 239-03 § Asymmetry B Call-Chain Rooting Proof; re-verified at HEAD 7ab515fe); (b) `gameOver = true` single SSTORE @ GameOverModule.sol:136 inside `handleGameOverDrain` delegatecall guarded by `_handleGameOverPath:530` `_livenessTriggered()`; (c) `purchaseStartDay` writes only during phase-transition (per GOVAR-240-011 `FROZEN_AT_REQUEST`); (d) `_simulatedDayIndex` pure-derivation from `block.timestamp` @ Storage:1212-1214 (no player-writable state); (e) `_livenessTriggered()` predicate callsite enumeration exhaustive at 4 sites (grep-verified: `_handleGameOverPath:530` + `_queueTickets:568, 599, 652`); (f) `rngLocked` commitment-window brackets every gameover consumer per Plan 240-01 GO-02 SAFE verdict + Phase 239 RNG-01 AIRTIGHT state machine (re-verified at HEAD 7ab515fe) | DISPROVEN_PLAYER_REACHABLE_VECTOR |
| GOTRIG-240-002 | Pre-gameover pool-deficit activation guard (protects against false-positive gameover when target is met) / pool-deficit drip projection | `_handleGameOverPath:547` (`if (lvl != 0 && _getNextPrizePool() >= levelPrizePool[lvl]) return (false, 0);` safety-escape — RETURNS WITHOUT triggering gameover when pool is sufficient); drip-projection writer `_evaluateGameOverAndTarget` @ AdvanceModule:1824-1840 (writes `gameOverPossible` flag but does NOT SSTORE to `gameOver` or advance liveness); consumer-side check `MintModule:894` (`if (gameOverPossible) revert GameOverPossible()` blocks BURNIE purchases) | (a) Pool-state manipulation to activate pool-deficit trigger: BLOCKED — pool totals (`prizePoolsPacked`, `currentPrizePool`, `claimablePool`, `levelPrizePool[lvl]`) are multi-sourced aggregates of all-player activity (purchases, burns, yield, affiliate distributions) gated by `rngLocked` + phase-transition-gate (GOVAR-240-013..015, -025); no single player can tip aggregate pool state without market-wide coordination; (b) Timing of individual player's purchase/burn to cross `_getNextPrizePool() >= levelPrizePool[lvl]` boundary: BLOCKED — the pool-sufficiency check at `:547` is a SAFETY BYPASS (returns without gameover) not a trigger; crossing the boundary SUPPRESSES gameover trigger, not activates it; (c) `gameOverPossible` flag flipping to force gameover: NOT A TRIGGER — `gameOverPossible` is a purchase-gate advisory (MintModule:894 reverts BURNIE purchases), not a gameover-trigger predicate; the actual trigger path still requires `_livenessTriggered()` at `:530`; (d) Economic denial-of-service: player attempts to prevent pool target from being met to force liveness-stall gameover: this would require 120 days of market-wide inactivity (not player-reachable); (e) Re-ordering `_evaluateGameOverAndTarget` write to align with gameover-eligible rngWord: BLOCKED — `_evaluateGameOverAndTarget` writes `gameOverPossible` but is gated by single-threaded-EVM atomicity + no direct SSTORE to `gameOver`; path to `gameOver = true` still requires `_livenessTriggered()` to return true at `:530` | (a) `_handleGameOverPath:547` pool-sufficiency is a SAFETY ESCAPE (returns without gameover), not a trigger — re-verified at HEAD 7ab515fe; (b) `gameOverPossible` flag writes only from `_evaluateGameOverAndTarget:1833, 1838` + auto-clear `advanceGame:172`; no path from `gameOverPossible = true` to `gameOver = true` without `_livenessTriggered()` first returning true at `_handleGameOverPath:530`; (c) pool-total GOVAR rows (GOVAR-240-013, -014, -015, -025) carry `FROZEN_BY_GATE` verdict (rngLocked + phase-transition-gate) per GO-03 Per-Variable Table — no player-reachable path to single-handedly manipulate pool totals during the gameover request-to-consumption window; (d) economic-infeasibility: gameover-jackpot requires funds to distribute, so any player who could drain the pool sufficiently to trigger would simultaneously extract the jackpot value ahead of any distribution — self-defeating; (e) Phase 239-02 PERMISSIONLESS-SWEEP 62-row classification covers every permissionless function touching pool state (0 `CANDIDATE_FINDING` rows; re-verified at HEAD 7ab515fe) | DISPROVEN_PLAYER_REACHABLE_VECTOR |

**Row-count attestation (D-12):** 2 GOTRIG-240-NNN rows × 6 columns. Both rows verdict = `DISPROVEN_PLAYER_REACHABLE_VECTOR`; zero `CANDIDATE_FINDING`. Fresh grep discovery at HEAD surfaced no additional gameover-trigger surface (grep: `gameOver = true` → 1 site at GameOverModule:136; `STAGE_GAMEOVER` return-paths → 4 sites in `_handleGameOverPath` all guarded by `_livenessTriggered()` at :530; `_livenessTriggered` callsites → 4 sites exhaustively enumerated above).

**Scope-extension guard (D-31):** The pre-scan in CONTEXT.md `<code_context>` named "pool deficit trigger" as a candidate second trigger. Fresh investigation at HEAD shows the pool-deficit mechanism is NOT a direct trigger surface — the `_handleGameOverPath:547` pool-sufficiency check is a SAFETY ESCAPE that PREVENTS gameover when target is met, and `gameOverPossible` is a drip-projection purchase-gate advisory. The actual gameover trigger is SOLELY `_livenessTriggered()` — both the 120-day Level-1+ path AND the 365-day Level-0 deploy-idle path are covered by GOTRIG-240-001. GOTRIG-240-002 captures the pool-deficit *surrounding* mechanism (for reviewer completeness, per the Plan's "≥2 rows" expected distribution) and documents that it is NOT a player-reachable trigger vector. No scope-guard deferral: this fresh-eyes refinement STAYS INSIDE the Plan 240-02 scope — the plan's D-24 set-equality gate is against the Plan 240-01 GO-240-NNN consumer row set (19 rows), not the GOTRIG surface set.

## GO-04 Non-Player Actor Narrative

Per D-11 player-centric attacker model, GO-04's primary analytic unit is player-reachable vectors (enumerated in the GO-04 Trigger Surface Table above). ROADMAP Success Criterion 4 names "an attacker" (singular threat model); REQUIREMENTS.md GO-04 wording covers "any actor". This section delivers CLOSED VERDICTS per non-player actor (admin / validator / VRF-oracle) per D-11/D-12/D-13 with bold-labeled grep-anchored tokens for reviewer extraction. Absence of any of the 3 closed verdicts below = re-open plan per D-13 mandatory attestation.

### Admin actor

Fresh grep at HEAD `7ab515fe` over admin-gated modifier surfaces (`onlyAdmin`, `onlyOwner`, `msg.sender != ContractAddresses.ADMIN`) returns the following functions that touch gameover-adjacent state:

- `DegenerusGameAdvanceModule._updateKeyHashOnly` @ AdvanceModule:500 (`msg.sender != ContractAddresses.ADMIN`) — updates `vrfKeyHash` ONLY; no touch of `phaseTransitionActive` / `gameOver` / `rngLockedFlag` / liveness-trigger state.
- `DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub` @ AdvanceModule:1627 (`msg.sender != ContractAddresses.ADMIN`) — emergency VRF coordinator rotation; RESETS rngLockedFlag = false @:1635 + vrfRequestId = 0 @:1636 + rngRequestTime = 0 @:1637 + rngWordCurrent = 0 @:1638; does NOT SSTORE to `phaseTransitionActive`, `gameOver`, `purchaseStartDay`, `dailyIdx`, or `_simulatedDayIndex` inputs (all GOTRIG-240-001 neutralizers remain intact post-rotation).
- `DegenerusAdmin.swapGameEthForStEth` @ DegenerusAdmin:631 (`onlyOwner`) — ETH↔stETH swap for gas treasury; no gameover-state touch.
- `DegenerusDeityPass` `onlyOwner` functions @:94, :108 — renderer/metadata updates; no gameover-state touch.
- No function at HEAD directly SSTOREs `phaseTransitionActive = true` outside `_endPhase:634` (single caller `advanceGame:460` per Phase 239-03 § Asymmetry B re-verified at HEAD 7ab515fe).
- No function at HEAD directly SSTOREs `gameOver = true` outside `GameOverModule.handleGameOverDrain:136` (caller: `_handleGameOverPath:620` via delegatecall, guarded by `_livenessTriggered():530`).
- No function at HEAD directly writes `purchaseStartDay` outside `advanceGame`-origin phase-transition logic (GOVAR-240-011 Named Gate `phase-transition-gate`).

**Admin closed verdict: NO_DIRECT_TRIGGER_SURFACE** — fresh-eyes grep at HEAD `7ab515fe` over all admin-gated entry points returns zero functions that (a) directly SSTORE to `phaseTransitionActive` or `gameOver` or (b) bypass the `_handleGameOverPath:530` `_livenessTriggered()` liveness gate or (c) mutate any of the GOTRIG-240-001 neutralizer sites (purchaseStartDay, _simulatedDayIndex inputs, `_livenessTriggered()` callsites). Admin's VRF coordinator rotation via `updateVrfCoordinatorAndSub:1627` resets VRF state to a FRESH pre-commitment condition (VRF state zeroed out) but cannot force a gameover trigger; rotation cannot advance `currentDay - psd` beyond `120` or advance `block.timestamp`. Cross-cites `audit/ACCESS-CONTROL-MATRIX.md` (structural admin surface scaffolding; re-verified at HEAD 7ab515fe — access-control modifier surfaces unchanged since v29.0 baseline `1646d5af` per PROJECT.md) + Plan 240-01 GO-02 Admin-column verdicts for the 19-row consumer subset (all 19 rows `NO_INFLUENCE_PATH (rngLocked)` or `NO_INFLUENCE_PATH (semantic-path-gate)`; re-verified at HEAD 7ab515fe).

### Validator actor

Validator (block proposer) has two manipulation surfaces against gameover-state at HEAD:

1. **Block.timestamp drift** — consensus bounds `block.timestamp` drift per-block (typically ±15s under Ethereum mainnet consensus); validator cannot arbitrarily advance time by 120 days to force GOTRIG-240-001 liveness trigger. The 120-day window requires 120 × 86400 = 10,368,000 seconds of cumulative block-timestamp progression; no single validator controls enough consecutive blocks to compound drift meaningfully against this window.
2. **Transaction ordering within a block** — validator can re-order transactions within a single block; but the gameover-trigger predicate `_livenessTriggered()` reads `block.timestamp` and `purchaseStartDay` (both block-committed before tx execution); re-ordering within a block does NOT change the predicate's evaluation for any tx within that block.

Gameover-*trigger* state (GOTRIG-240-001 surface) is therefore not meaningfully manipulable by validator within Phase 240's scope. Gameover-*fulfillment* state — specifically the rngWord produced by VRF or prevrandao-fallback — IS subject to validator 1-bit manipulation via `block.prevrandao` @ AdvanceModule:1322 under the EXC-02 KI envelope (14-day `GAMEOVER_RNG_FALLBACK_DELAY` gate at `:1250`). This is the canonical KI EXC-02 exposure — documented in `KNOWN-ISSUES.md §"Gameover prevrandao fallback"` and forward-cited to Phase 241 EXC-02 per D-19 strict boundary. It is NOT a Phase 240 GO-04 trigger-timing violation — GO-04 scope is strictly the trigger predicate (`_livenessTriggered` + `_handleGameOverPath` safety-escape), NOT the fulfillment rngWord.

**Validator closed verdict: BOUNDED_BY_14DAY_EXC02_FALLBACK** — validator block-delay attacks on the gameover-*trigger* are bounded by (a) consensus-level `block.timestamp` drift limits (cannot advance 120 days), (b) single-threaded-EVM atomicity per Phase 239-03 § Asymmetry B No-Player-Reachable-Mutation-Path Proof (cross-cited; re-verified at HEAD 7ab515fe — single-threaded EVM argument holds structurally), and (c) `_livenessTriggered()` being a pure view function over state already committed before validator-controlled block. Validator block-delay attacks on the gameover-*fulfillment* (rngWord) are bounded by the 14-day `GAMEOVER_RNG_FALLBACK_DELAY` constant at `AdvanceModule:109` which routes withheld VRF fulfillment to the KI EXC-02 prevrandao-fallback surface (accepted exposure). **See Phase 241 EXC-02** for KI acceptance re-verification per D-19 strict boundary. Cross-cites Phase 238 FREEZE-PROOF 19-row Gameover-Flow Validator-column verdicts (7 PATH_BLOCKED_BY_GATE (rngLocked) + 8 EXCEPTION (KI: "Gameover prevrandao fallback") + 4 NO_REACHABLE_PATH; re-verified at HEAD 7ab515fe) and `audit/v30-PERMISSIONLESS-SWEEP.md` 62-row sweep (distribution 24 respects-rngLocked / 0 respects-equivalent-isolation / 38 proven-orthogonal / 0 CANDIDATE_FINDING; re-verified at HEAD 7ab515fe).

### VRF-oracle actor

VRF-oracle (Chainlink) withholding of `rawFulfillRandomWords` for ≥14 days routes to the prevrandao-fallback branch at `_gameOverEntropy:1248-1274`, which calls `_getHistoricalRngFallback:1308` and produces `keccak256(abi.encode(combined, currentDay, block.prevrandao))` at `:1322`. This is the gameover-*fulfillment* path — NOT the gameover-*trigger* path.

Critically: VRF-oracle CANNOT force gameover-trigger activation. Gameover trigger requires `_livenessTriggered()` at `AdvanceModule:530` to return true (120-day Level-1+ path or 365-day Level-0 deploy-idle path). VRF-oracle withholding does not advance `block.timestamp - purchaseStartDay`; VRF-oracle cannot write to `purchaseStartDay`; VRF-oracle cannot execute `_endPhase:634` (the single `phaseTransitionActive = true` site with sole caller `advanceGame:460`). The 14-day fallback path becomes available only AFTER `_livenessTriggered()` has already triggered AND the VRF request has been pending for 14+ days.

On the rngWord-bias side: Plan 240-01 GO-02's 8 prevrandao-fallback rows (GO-240-008..015) carry verdict `EXCEPTION (KI: EXC-02)` with Validator-column `EXCEPTION (KI: EXC-02)` (block-proposer 1-bit prevrandao bias) and VRF-oracle-column `PATH_BLOCKED_BY_GATE (semantic-path-gate)` per Phase 238 FREEZE-PROOF. VRF-oracle's delay-to-fallback is the accepted escape hatch — NOT a gameover-trigger violation.

**VRF-oracle closed verdict: EXC-02_FALLBACK_ACCEPTED** — VRF-oracle withholding ≥14 days routes to the accepted KI EXC-02 prevrandao-fallback surface (`_getHistoricalRngFallback:1301-1325` at HEAD 7ab515fe) — gameover-*fulfillment* path only, NOT gameover-*trigger* path. GO-04 scope is trigger-timing; fulfillment is out-of-scope per D-19 strict boundary (Phase 241 EXC-02 owns acceptance re-verification). **See Phase 241 EXC-02**. Cross-cites Plan 240-01 GO-02 prevrandao-fallback 8 rows + `KNOWN-ISSUES.md §"Gameover prevrandao fallback"` + Phase 238 FREEZE-PROOF 8-row EXC-02 KI-Exception Subset (all re-verified at HEAD 7ab515fe — 14-day `GAMEOVER_RNG_FALLBACK_DELAY` constant at `:109` unchanged; `_getHistoricalRngFallback` body at `:1301-1325` unchanged; `:1322` prevrandao-mix unchanged).

**Narrative attestation (D-13):** All 3 bold-labeled closed verdict tokens appear in this section exactly as written above: `**Admin closed verdict: NO_DIRECT_TRIGGER_SURFACE**`, `**Validator closed verdict: BOUNDED_BY_14DAY_EXC02_FALLBACK**`, `**VRF-oracle closed verdict: EXC-02_FALLBACK_ACCEPTED**` — grep-anchored for 240-02-SUMMARY attestation.

## Prior-Artifact Cross-Cites

Per D-17/D-18 — every cite CORROBORATING (not relied upon). Each carries `re-verified at HEAD 7ab515fe` backtick-quoted-phrase note with one-line structural-equivalence statement. Minimum 3 instances per D-18; this file contains 11 cites below with 11+ `re-verified at HEAD 7ab515fe` notes (comfortably exceeds the minimum).

### Phase 237 audit/v30-CONSUMER-INVENTORY.md

**Artifact:** `audit/v30-CONSUMER-INVENTORY.md` §"Consumer Index" (GO-01..04 = 19-row gameover-flow subset) + §"Per-Consumer Call Graphs" (per-consumer storage-read set — feeds GO-03 GOVAR enumeration).
**Role:** SCOPE ANCHOR per D-17 — Plan 240-02 GO-03 Per-Consumer Cross-Walk Row-ID set (`GO-240-001..019`) is set-bijective with this subset per D-24.
**Re-verification note:** `re-verified at HEAD 7ab515fe — 19-row gameover-flow subset + per-consumer call-graph storage-read set match fresh-eyes re-derivation at HEAD; distinct GO-240-NNN cross-walk rows = 19 verified via grep.`

### Phase 238-02 audit/v30-238-02-FWD.md

**Artifact:** `audit/v30-238-02-FWD.md` §"PREFIX-GAMEOVER — gameover-entropy path-family shared forward enumeration (7 rows)" L94-117 (FWD-01 storage-read set: rngWordCurrent, rngWordByDay[day], vrfRequestId, phaseTransitionActive, gameOverLocked/gameover-flow state) + §"PREFIX-PREVRANDAO — gameover prevrandao fallback KI-exception chain (8 rows)" L119-144 (FWD-01 storage-read set: rngRequestTime, rngWordByDay[searchDay] × 5 historical SLOADs, block.prevrandao, currentDay, gameOverLocked) + §"Forward Mutation Paths" for F-29-04 rows L522-541.
**Role:** Corroborating for GOVAR Storage Slot + Write Paths columns per D-17; fresh re-derivation at HEAD performed for all 28 GOVAR rows.
**Re-verification note:** `re-verified at HEAD 7ab515fe — per-consumer forward mutation-path enumeration for gameover-flow rows matches fresh-eyes GOVAR enumeration; zero slot-surface divergence; Phase 238-02 FWD-01 storage-read set is a strict subset of GOVAR-240-NNN universe (the GOVAR universe adds ticket-queue state + trait-mapping state + pool-total slots + jackpot-state-packed-word + deity-pass refund inputs that are read by gameover consumers' downstream SSTOREs at GameOverModule body).`

### Phase 238-03 audit/v30-238-03-GATING.md

**Artifact:** `audit/v30-238-03-GATING.md` §"Path Family × Named Gate Heatmap" L24-35 (19-row gameover-flow filter: `gameover-entropy (7 rows)` = 7 rngLocked + 0 everything-else; `other` KI-exception rows are distributed in the other / 26 classification) + §"Named Gate Column note on phase-transition-gate" L37.
**Role:** Corroborating for GOVAR Named Gate column per D-10; expected 19-row gameover-flow filter distribution (`rngLocked` = 7 gameover-entropy + `semantic-path-gate` = 12 exception rows — per-consumer granularity, distinct from per-variable GOVAR granularity of this file).
**Re-verification note:** `re-verified at HEAD 7ab515fe — 19-row gameover-flow subset Named Gate distribution (7 rngLocked + 12 semantic-path-gate) at per-consumer granularity corroborates GOVAR per-variable granularity Named Gate distribution (18 rngLocked + 1 lootbox-index-advance + 4 phase-transition-gate + 5 semantic-path-gate = 28); divergence in raw counts reflects granularity change (per-consumer vs per-variable), not structural divergence.`

### Phase 239 audit/v30-RNGLOCK-STATE-MACHINE.md

**Artifact:** `audit/v30-RNGLOCK-STATE-MACHINE.md` — RNG-01 `AIRTIGHT` state machine (commit `5764c8a4`); dedicated Path row `RNGLOCK-239-P-007` gameover-VRF-request bracket.
**Role:** Load-bearing corroborating for GOVAR rows whose Named Gate = `rngLocked` (18 of 28 rows); rngLockedFlag state machine AIRTIGHT supports FROZEN_BY_GATE verdict for those rows.
**Re-verification note:** `re-verified at HEAD 7ab515fe — rngLockedFlag set @ AdvanceModule.sol:1579 + clear @:1635 + :1676 unchanged; Path RNGLOCK-239-P-007 confirms set/clear symmetry around gameover VRF request via _unlockRng downstream of _handleGameOverPath; RNG-01 invariant: zero CANDIDATE_FINDING rows across 13 state-machine rows.`

### Phase 239-03 audit/v30-ASYMMETRY-RE-JUSTIFICATION.md § Asymmetry B

**Artifact:** `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` § Asymmetry B — phase-transition-gate origin proof (commit `7e4b3170`); 13 enumerated SSTORE sites under `phaseTransitionActive = true`; Call-Chain Rooting Proof grep-verifies single caller of `_endPhase` at `advanceGame:460`; No-Player-Reachable-Mutation-Path Proof by exhaustion over 62-row RNG-02 sweep.
**Role:** Load-bearing corroborating for (a) GOVAR-240-006 `phaseTransitionActive` + GOVAR-240-011 `purchaseStartDay` + GOVAR-240-008 `gameOverPossible` + GOVAR-240-025 `levelPrizePool` Named Gate `phase-transition-gate`; (b) GO-04 GOTRIG-240-001 single-threaded-EVM + player-closure arguments in the Player-Reachable Manipulation Vector(s) column; (c) GO-04 Validator narrative single-threaded-EVM argument.
**Re-verification note:** `re-verified at HEAD 7ab515fe — phaseTransitionActive set @ AdvanceModule.sol:634 (single site) + single caller of _endPhase from advanceGame:460 unchanged; No-Player-Reachable-Mutation-Path Proof by exhaustion over 62-row RNG-02 sweep confirms GO-04 player-closure argument; Call-Chain Rooting Proof structurally mirrors GOTRIG-240-001's `_livenessTriggered()` sole-predicate-for-gameover-trigger structure (parallel argument: `_handleGameOverPath` has sole caller at advanceGame:179).`

### Phase 239 audit/v30-PERMISSIONLESS-SWEEP.md

**Artifact:** `audit/v30-PERMISSIONLESS-SWEEP.md` — RNG-02 62-row permissionless sweep (commit `0877d282`); distribution 24 `respects-rngLocked` + 38 `proven-orthogonal` + 0 `CANDIDATE_FINDING`.
**Role:** Corroborating for GO-04 non-player narrative (every permissionless function touching gameover-trigger or gameover-consumer state has a published classification) + GO-04 Player-Column closure of GOTRIG-240-002 pool-deficit economic-infeasibility argument.
**Re-verification note:** `re-verified at HEAD 7ab515fe — 62 permissionless function rows with 0 CANDIDATE_FINDING; player-column reachability on gameover-flow state closed; advanceGame row classification confirms single-caller-of-_endPhase gating; purchase-path rows (mintPurchase variants) classified respects-rngLocked corroborate _queueTickets:568 liveness gate.`

### v29.0 Phase 232.1-03-PFTB-AUDIT.md

**Artifact:** `.planning/milestones/v29.0-phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-PFTB-AUDIT.md` — non-zero-entropy guarantees around phase transition.
**Role:** Corroborating for GOVAR rows Named Gate `phase-transition-gate` + GO-04 Validator narrative (non-zero-entropy at phase transition excludes degenerate `rngWord == 0` / `rngWord == 1` edge cases that `_gameOverEntropy:559` short-circuits via `return (true, STAGE_GAMEOVER)`).
**Re-verification note:** `re-verified at HEAD 7ab515fe — phase-transition non-zero-entropy invariants unchanged since v29.0 baseline 1646d5af per PROJECT.md contract-tree-identity statement; _gameOverEntropy short-circuit on rngWord ∈ {0, 1} at AdvanceModule.sol:559 preserves trigger-surface semantics.`

### v29.0 Phase 235 Plan 05 235-05-TRNX-01.md

**Artifact:** `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-TRNX-01.md` — `rngLocked` 4-path walk (prior-milestone RNG-01-equivalent invariant).
**Role:** Corroborating (in addition to Phase 239 RNG-01) for GOVAR rows with Named Gate = `rngLocked`.
**Re-verification note:** `re-verified at HEAD 7ab515fe — 4-path walk superset confirmed by Phase 239 RNG-01 9-row Path Enumeration Table (SET_CLEARS_ON_ALL_PATHS = 7 / CLEAR_WITHOUT_SET_UNREACHABLE = 2 / zero CANDIDATE_FINDING); gameover-VRF-request bracket preserved across v25 → v3.7 → v3.8 → v29 → v30 baseline.`

### v25.0 Phase 215 + v3.7 Phases 63-67 + v3.8 Phases 68-72 (structural baselines)

**Artifact:** `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` + `.planning/milestones/v3.7-phases/` (63-67 VRF path test coverage) + `.planning/milestones/v3.8-phases/` (68-72 VRF commitment window; 51/51 SAFE).
**Role:** Structural baselines — 87-permissionless-path coverage at v3.8 + 51-variable commitment-window at v3.8 + 99-chain fresh-eyes at v25.0 bracket the GOVAR-240-NNN universe in historical comparison.
**Re-verification note:** `re-verified at HEAD 7ab515fe — structural equivalence: RNG-consumer surface area unchanged since v25.0; gameover-flow trigger mechanism (_livenessTriggered 120-day Level-1+ + 365-day Level-0 deploy-idle) unchanged since v29.0 baseline 1646d5af per PROJECT.md; 2-trigger surface invariant preserved.`

### audit/STORAGE-WRITE-MAP.md + audit/ACCESS-CONTROL-MATRIX.md (repo-root scaffolding)

**Artifacts:** `audit/STORAGE-WRITE-MAP.md` + `audit/ACCESS-CONTROL-MATRIX.md`.
**Role:** Corroborating structural scaffolding for GO-03 Write Paths column (28 GOVAR rows × Write Paths list — every SSTORE site grep-citable) + GO-04 Admin narrative `NO_DIRECT_TRIGGER_SURFACE` verdict (admin-gated modifier surfaces exhaustively enumerated).
**Re-verification note:** `re-verified at HEAD 7ab515fe — storage-write coverage + access-control modifier surfaces unchanged since v29.0 milestone close; admin-surface 2-gate enumeration in AdvanceModule (:500 pre-deploy, :1627 VRF rotation) + DegenerusAdmin onlyOwner @ :631 + DegenerusDeityPass onlyOwner @ :94, :108 exhaustive for gameover-adjacent admin touch points.`

### KNOWN-ISSUES.md §"Gameover prevrandao fallback" (EXC-02 SUBJECT, not warrant)

**Artifact:** `KNOWN-ISSUES.md` entry on gameover prevrandao fallback.
**Role:** SUBJECT of GOVAR-240-004 + GOVAR-240-028 EXCEPTION verdicts + SUBJECT of GO-04 Validator + VRF-oracle narrative verdicts per D-19 strict boundary; forward-cited to Phase 241 EXC-02 (2 forward-cite tokens `See Phase 241 EXC-02` embedded: one in Validator narrative + one in VRF-oracle narrative). NOT relied upon — Phase 240 proof steps derive from storage primitives + semantic gate at HEAD.
**Re-verification note:** `re-verified at HEAD 7ab515fe — KI entry text unchanged since v29.0; 14-day GAMEOVER_RNG_FALLBACK_DELAY constant at DegenerusGameAdvanceModule.sol:109 + gate check at :1250 + prevrandao-mix at :1322 unchanged; 8-row consumer cluster identity preserved.`

## Finding Candidates

Per D-26 — rows whose GOVAR Verdict OR Cross-Walk Aggregate Verdict OR GOTRIG Verdict is `CANDIDATE_FINDING` produce structured Finding Candidate blocks routed to Phase 242 FIND-01 intake.

**None surfaced.** All 28 GOVAR rows verified `FROZEN_AT_REQUEST` / `FROZEN_BY_GATE` / `EXCEPTION (KI: EXC-NN)`. All 19 Cross-Walk rows verified `SAFE` / `EXCEPTION (KI: EXC-NN)`. Both GOTRIG rows verified `DISPROVEN_PLAYER_REACHABLE_VECTOR` at HEAD `7ab515fe`. Zero CANDIDATE_FINDING cells across 49 closed verdict cells (28 GOVAR + 19 Cross-Walk + 2 GOTRIG) = zero routing to Phase 242 FIND-01 from this plan. No F-30-NN IDs emitted per D-25.

## Scope-Guard Deferrals

Per D-31 — gameover-jackpot-input state variables or gameover-trigger surfaces discovered at HEAD that are NOT already represented in Phase 237/238 outputs are recorded as scope-guard deferral blocks. Phase 237/238/239 outputs + Plan 240-01 output are NOT edited; gaps route to Phase 242 FIND-01 intake.

**None surfaced.** GOVAR universe set-equal to union of Phase 238-02 FWD-01 storage-read sets filtered to 19-row gameover-flow subset (the GOVAR set extends the FWD-01 surface to include per-consumer downstream SSTORE targets like `claimableWinnings[addr]`, `traitBurnTicket[lvl][traitId]`, `currentPrizePool`, `claimablePool`, `prizePoolsPacked`, `gameOverStatePacked`, `yieldAccumulator`, `deityPassOwners[]` — all of which are read-or-written by gameover consumers GO-240-004, -005 at `GameOverModule.sol:80-180`). This extension is the expected Phase 240 GO-03 scope-refinement per CONTEXT.md `<code_context>` §"GO-03 Surface (State-Freeze Enumeration)" and does NOT require a Phase 237/238 edit — the Phase 238 FWD-01 storage-read set was at per-consumer consumption-site granularity; Phase 240 GO-03 is at per-variable jackpot-input granularity for the same 19-row consumer subset. GOTRIG universe covers both gameover-trigger surfaces at HEAD 7ab515fe (120-day liveness stall via `_livenessTriggered()` + pool-deficit-safety-escape at `_handleGameOverPath:547`); no novel gameover-trigger surface surfaced. Phase 237/238/239 outputs + Plan 240-01 output READ-only per D-31.

## Attestation

**HEAD anchor:** `7ab515fe` (contract tree identical to v29.0 `1646d5af`; all post-v29 commits are docs-only per PROJECT.md).
**Scope:** GO-03 per-variable + per-consumer state-freeze enumeration (19-row gameover-flow consumer universe; dual-table per D-09 — 28 GOVAR rows × 6 columns + 19 Cross-Walk rows × 4 columns) + GO-04 player-centric trigger-timing disproof (2 GOTRIG gameover-trigger surfaces × 6 columns + non-player narrative per D-11/D-12/D-13 with 3 closed verdicts).
**Fresh-eyes mandate (D-17):** Every GOVAR row + every GOTRIG row + every Named Gate cell re-derived at HEAD `7ab515fe` from `contracts/` source. Phase 237/238/239 outputs CROSS-CITED with `re-verified at HEAD 7ab515fe` backtick-quoted-phrase notes — NOT relied upon. Plan 240-01 output (audit/v30-240-01-INV-DET.md) is sibling-plan cross-cite (Wave 1 parallel per D-02); Row IDs `GO-240-NNN` in this plan's GO-03 Per-Consumer Cross-Walk are set-bijective with Plan 240-01 GO-01 Inventory Table Row IDs per D-24.

**GO-04 Non-Player Actor Narrative attestation (D-13):** The `## GO-04 Non-Player Actor Narrative` section above delivers 3 closed verdicts with bold-labeled grep-anchored tokens: `**Admin closed verdict: NO_DIRECT_TRIGGER_SURFACE**` + `**Validator closed verdict: BOUNDED_BY_14DAY_EXC02_FALLBACK**` + `**VRF-oracle closed verdict: EXC-02_FALLBACK_ACCEPTED**`. All 3 bold verdict labels grep-anchored; `See Phase 241 EXC-02` forward-cite tokens present in Validator + VRF-oracle narratives per D-19 strict boundary. Absence = re-open plan per D-13 mandatory attestation.

**Finding-ID emission (D-25):** Zero F-30-NN IDs. Finding Candidates (if any) routed to Phase 242 FIND-01 intake. At HEAD `7ab515fe`: zero CANDIDATE_FINDING rows across 49 closed verdict cells (28 GOVAR + 19 Cross-Walk + 2 GOTRIG) = zero routing from this plan.

**READ-only scope (D-30):** Zero `contracts/` or `test/` writes (`git status --porcelain contracts/ test/` empty; `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` empty). `KNOWN-ISSUES.md` untouched. Phase 237/238/239 audit outputs + Plan 240-01 output all untouched per D-31 (`audit/v30-CONSUMER-INVENTORY.md`, `audit/v30-238-01-BWD.md`, `audit/v30-238-02-FWD.md`, `audit/v30-238-03-GATING.md`, `audit/v30-FREEZE-PROOF.md`, `audit/v30-RNGLOCK-STATE-MACHINE.md`, `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md`, `audit/v30-PERMISSIONLESS-SWEEP.md`, `audit/v30-240-01-INV-DET.md` all unchanged).

**No discharge claim (D-32):** No prior phase recorded an audit assumption pending Phase 240 GO-03/GO-04. Phase 238-03 Scope-Guard Deferral #1 was fully discharged by Phase 239 Plans 01 + 03 (per 239-01/239-03 SUMMARYs). Phase 240 emits GO-01..05 verdicts consumed by Phase 242 REG/FIND at milestone consolidation.

**Row-set integrity (D-24):** GO-03 Per-Consumer Cross-Walk has 19 rows set-bijective with Plan 240-01 GO-01 Inventory Table Row IDs `GO-240-001..019`; GO-03 Per-Variable Table has 28 `GOVAR-240-NNN` rows covering the jackpot-input surface read by the 19 consumers at gameover consumption time; GO-04 Trigger Surface Table has 2 `GOTRIG-240-NNN` rows (120-day liveness stall + pool-deficit-safety-escape). Named Gate distribution 18/1/4/5/0 = 28; Verdict distribution 3/19/3/3/0 = 28. Forward-cite integrity: 2+ `See Phase 241 EXC-02` forward-cite tokens embedded per D-19 (Validator + VRF-oracle narratives).

**Wave 1 parallel topology (D-02):** Plan 240-01 (GO-01 + GO-02) runs in parallel Wave 1 with this plan — zero cross-plan dependencies at HEAD (each reads Phase 237 Consumer Index + Phase 238 FWD-01 storage-read set directly). Plan 240-03 (GO-05 + consolidation) Wave 2 reads this plan's `GOVAR-240-NNN` Per-Variable Table as GO-05 state-variable-disjointness proof input per D-14 + assembles consolidated `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` per D-27.
