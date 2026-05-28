# 337 — RNG-Audit-Kit Anchor Attestation (HEAD-Resolved)

**Authored:** 2026-05-28
**Purpose:** A fresh, HEAD-resolved attestation table for every `contracts/` anchor the RNG-Audit Kit cites, so no pre-v50 line leaks into the deliverable. The 334 sketch + `334-GREP-ATTESTATION` cite the *pre-v50* baseline `b0511ca2`; several anchors MOVED in the three v50-touched code files (`DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGame.sol`). Every line below was re-resolved with `grep -n` / `sed -n 'Np'` against the working tree at the authoring HEAD.

**This table is the source of truth the kit's locators are drawn from, and the set the 337-04 anchor-resolution lint checks against.** It carries LOCATORS ONLY — there is deliberately no freeze-status / verdict column.

## Frozen-Subject Fact

- **Authoring HEAD:** `dc8f9ed4` (`dc8f9ed495e61929c667d8b69105729d82926367`).
- **Subject byte-frozen:** `git diff e756a6f3 HEAD -- contracts/` is **empty** — the contract tree is byte-identical to the v50.0 IMPL commit `e756a6f3`. Every line cited here therefore resolves identically at the v50.0 IMPL point and at the kit's authoring HEAD.
- **v50 diff touched exactly 5 files:** `AfKing.sol`, `BurnieCoin.sol`, `DegenerusGame.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`. **`DegenerusGameAdvanceModule.sol` and `DegenerusGameStorage.sol` were NOT touched** — every lock-lifecycle / VRF-entry / consume-driver / write-gate anchor in those two files is byte-identical to `b0511ca2`. This is the load-bearing simplification: **the VRF machinery itself did not move.**

## DRIFT INDEX — cite the NEW line, NEVER the pre-v50 sketch line

The kit's later plans (337-02 / 337-03) and any executor MUST cite the NEW line for each of these six items. Copying a stale line from the 334 sketch misdirects the future external auditor.

| # | Pre-v50 sketch said | Cite at HEAD | Note |
|---|---------------------|--------------|------|
| 1 | `MintModule` within-player advance `processed += writesUsed >> 1` (pre-v50 line) | **`DegenerusGameMintModule.sol:720` `processed += take;`** | DRIFTED. The suspect gas-budget heuristic no longer executes; the within-player advance now matches the reference loop `:502`. The old heuristic survives only as documentary text in the comment at `:718`. |
| 2 | `LootboxModule` inline 100-iteration `_queueTickets` loop (the pre-v50 line range) | **`DegenerusGameLootboxModule.sol:1253` `whalePassClaims[player] += 1;`** | DRIFTED. The loop is retired; box-open now does one O(1) accumulator write. `_activateWhalePass` def `:1250` no longer returns a `ticketStartLevel`. |
| 3 | `_applyWhalePassStats` had 3 call sites (incl. the LootboxModule box-open caller) | **2 call sites: `WhaleModule:1032` + `DecimatorModule:588`** | DRIFTED. The box-open caller was deleted with the loop. |
| 4 | `autoOpen` at the pre-v50 line; `enqueueBoxForAutoOpen` at the pre-v50 line; the `OPEN_NORMAL_GAS_UNIT` gas-weight carve-out constant present | **`autoOpen` `DegenerusGame.sol:1695`; `enqueueBoxForAutoOpen` `DegenerusGame.sol:1588`; the `OPEN_NORMAL_GAS_UNIT` constant DELETED** | DRIFTED. The gas-weight constant is gone; the autoOpen budget is flat (`opened < maxCount`). |
| 5 | (not in the pre-v50 tree) | **`lazyPassHorizon(address)` view NEW at `DegenerusGame.sol:1540`** | NEW IN v50. Reads the `mintPacked_` deity bit; non-VRF-participating; AfKing reads it for pass-gating. |
| 6 | (the pre-v50 whale-bonus constants) | **`WHALE_PASS_BONUS_TICKETS_PER_LEVEL` + `WHALE_PASS_BONUS_END_LEVEL` DELETED** | DRIFTED. Both constants were removed with the inline loop. |

---

## A. Lock Lifecycle + Write-Time Gate

`DegenerusGameStorage.sol` + `DegenerusGameAdvanceModule.sol` — both UNCHANGED by v50, byte-identical to `b0511ca2`.

| Anchor (symbol / role) | Confirmed `file:line` at HEAD | Status |
|------------------------|-------------------------------|--------|
| `rngLockedFlag` declaration | `contracts/storage/DegenerusGameStorage.sol:279` (`bool internal rngLockedFlag;`) | unchanged |
| `rngLockedFlag` bit-doc | `contracts/storage/DegenerusGameStorage.sol:55` (`[21:22] rngLockedFlag`) | unchanged |
| `_queueTickets` def | `contracts/storage/DegenerusGameStorage.sol:560` | unchanged |
| `_queueTickets` liveness gate | `contracts/storage/DegenerusGameStorage.sol:571` (`if (_livenessTriggered()) revert E();`) | unchanged |
| `_queueTickets` write-time gate | `contracts/storage/DegenerusGameStorage.sol:573` (`if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();`) | unchanged |
| `_queueTicketsScaled` def | `contracts/storage/DegenerusGameStorage.sol:594` | unchanged |
| `_queueTicketsScaled` liveness gate | `contracts/storage/DegenerusGameStorage.sol:602` | unchanged |
| `_queueTicketsScaled` write-time gate | `contracts/storage/DegenerusGameStorage.sol:605` (`if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();`) | unchanged |
| `_queueTicketRange` def | `contracts/storage/DegenerusGameStorage.sol:647` | unchanged |
| `_queueTicketRange` liveness gate | `contracts/storage/DegenerusGameStorage.sol:655` | unchanged |
| `_queueTicketRange` write-time gate | `contracts/storage/DegenerusGameStorage.sol:661` (`if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();`) | unchanged |
| `_livenessTriggered` def | `contracts/storage/DegenerusGameStorage.sol:1213` | unchanged |
| `_VRF_GRACE_PERIOD = 14 days` | `contracts/storage/DegenerusGameStorage.sol:198` | unchanged |
| lock set-true | `contracts/modules/DegenerusGameAdvanceModule.sol:1640` (`rngLockedFlag = true;`) | unchanged |
| `_unlockRng` def | `contracts/modules/DegenerusGameAdvanceModule.sol:1719` | unchanged |
| unlock set-false | `contracts/modules/DegenerusGameAdvanceModule.sol:1721` (`rngLockedFlag = false;`) | unchanged |

## B. VRF Entry + Gate + Consume Driver (the 4 EXEMPT entries)

`DegenerusGameAdvanceModule.sol` — UNCHANGED by v50.

| Anchor (symbol / role) | Confirmed `file:line` at HEAD | Status |
|------------------------|-------------------------------|--------|
| `advanceGame()` — consume driver (EXEMPT) | `contracts/modules/DegenerusGameAdvanceModule.sol:154` | unchanged |
| `rawFulfillRandomWords` — VRF callback entry (EXEMPT) | `contracts/modules/DegenerusGameAdvanceModule.sol:1735` | unchanged |
| `retryLootboxRng()` — lootbox failsafe (EXEMPT) | `contracts/modules/DegenerusGameAdvanceModule.sol:1105` | unchanged |
| `rngGate(...)` — returns `(uint256 word, uint32 gapDays)` | `contracts/modules/DegenerusGameAdvanceModule.sol:1152` | unchanged |
| facade dispatch `retryLootboxRng` | `contracts/DegenerusGame.sol:2177` (selector `:2182`) | unchanged |
| facade dispatch `rawFulfillRandomWords` | `contracts/DegenerusGame.sol:2226` (selector `:2234`) | unchanged |
| `rngLocked()` view | `contracts/DegenerusGame.sol:2471` | confirmed |

## C. VRF-Word Consume Sites (where the resolution word flows)

`rngGate` returns the word into `advanceGame`; the consume sites below are the LOCATIONS the word reaches. AdvanceModule UNCHANGED; the module readers as noted.

| Consume site (symbol) | Confirmed `file:line` at HEAD | Status |
|-----------------------|-------------------------------|--------|
| `_processFutureTicketBatch` def | `contracts/modules/DegenerusGameAdvanceModule.sol:1418` (called with `rngWord` at `:398`) | unchanged |
| `_emitDailyWinningTraits` def | `contracts/modules/DegenerusGameAdvanceModule.sol:955` (called with `rngWord` at `:355`) | unchanged |
| `payDailyJackpot` def | `contracts/modules/DegenerusGameAdvanceModule.sol:888` (called with `rngWord` at `:367` / `:450`) | unchanged |
| `payDailyJackpot` (module body) | `contracts/modules/DegenerusGameJackpotModule.sol:320` | unchanged |
| `_distributeYieldSurplus` def | `contracts/modules/DegenerusGameAdvanceModule.sol:675` (called with `rngWord` at `:407`) | unchanged |
| `quests.rollLevelQuest` call | `contracts/modules/DegenerusGameAdvanceModule.sol:426`; def `contracts/DegenerusQuests.sol:1781` (`function rollLevelQuest(uint256 entropy)`) | unchanged |
| `_gameOverEntropy` def | `contracts/modules/DegenerusGameAdvanceModule.sol:1241` (called at `:531`) | unchanged |
| lootbox path slot decl `lootboxRngWordByIndex` | `contracts/storage/DegenerusGameStorage.sol:1401` (`mapping(uint48 => uint256) internal lootboxRngWordByIndex;`) | unchanged |
| `lootboxRngWordByIndex` reader | `contracts/modules/DegenerusGameLootboxModule.sol:510` (`uint256 rngWord = lootboxRngWordByIndex[index];`) | unchanged |
| `lootboxRngWordByIndex` reader | `contracts/modules/DegenerusGameLootboxModule.sol:587` (`uint256 rngWord = lootboxRngWordByIndex[index];`) | unchanged |
| `lootboxRngWordByIndex` reader | `contracts/modules/DegenerusGameLootboxModule.sol:616` (`uint256 rngWord = lootboxRngWordByIndex[index];`) | unchanged |
| `lootboxRngWordByIndex` reader (trait consume) | `contracts/modules/DegenerusGameMintModule.sol:696` | unchanged |
| `lootboxRngWordByIndex` gate | `contracts/modules/DegenerusGameMintModule.sol:1414` (`if (lootboxRngWordByIndex[index] != 0) revert E();`) | unchanged |
| `rngWordCurrent` slot decl | `contracts/storage/DegenerusGameStorage.sol:374` | unchanged |
| `rngWordByDay` slot decl | `contracts/storage/DegenerusGameStorage.sol:436` | unchanged |

## D. MINTDIV Within-Player Advance (DRIFTED — item 1)

`DegenerusGameMintModule.sol` — TOUCHED by v50 (the fix landed).

| Anchor (symbol / role) | Confirmed `file:line` at HEAD | Status |
|------------------------|-------------------------------|--------|
| `processFutureTicketBatch` (reference-correct loop) def | `contracts/modules/DegenerusGameMintModule.sol:393` | unchanged |
| reference within-player advance | `contracts/modules/DegenerusGameMintModule.sol:502` (`processed += take;`) | unchanged |
| `processTicketBatch` def | `contracts/modules/DegenerusGameMintModule.sol:671` (`function processTicketBatch(uint24 lvl) external returns (bool finished)`) | unchanged |
| `_raritySymbolBatch` (startIndex/LCG trait gen) def | `contracts/modules/DegenerusGameMintModule.sol:546` | unchanged |
| **within-player advance (the v50 realignment)** | **`contracts/modules/DegenerusGameMintModule.sol:720` (`processed += take;`)** | **DRIFTED** — was `processed += writesUsed >> 1` pre-v50; now matches `:502`. |
| `_processOneTicketEntry` def | `contracts/modules/DegenerusGameMintModule.sol:766` (signature widened to a 3-tuple return) | unchanged-location |

## E. Whale-Pass O(1) Claim (DRIFTED — items 2, 3, 6)

`DegenerusGameLootboxModule.sol` TOUCHED; `DegenerusGameWhaleModule.sol` / `DegenerusGameStorage.sol` / `DegenerusGamePayoutUtils.sol` / `DegenerusGameJackpotModule.sol` / `DegenerusGameDecimatorModule.sol` UNCHANGED.

| Anchor (symbol / role) | Confirmed `file:line` at HEAD | Status |
|------------------------|-------------------------------|--------|
| `_activateWhalePass` (box-open record) def | `contracts/modules/DegenerusGameLootboxModule.sol:1250` | location confirmed |
| **box-open O(1) write** | **`contracts/modules/DegenerusGameLootboxModule.sol:1253` (`whalePassClaims[player] += 1;`)** | **DRIFTED** — replaces the retired inline 100-iteration `_queueTickets` loop. |
| `whalePassClaims` slot decl | `contracts/storage/DegenerusGameStorage.sol:955` (`mapping(address => uint256) internal whalePassClaims;`) | unchanged |
| `whalePassClaims` writer (box-open) | `contracts/modules/DegenerusGameLootboxModule.sol:1253` (`+= 1`) | v50 NEW writer |
| `whalePassClaims` writer (payout) | `contracts/modules/DegenerusGamePayoutUtils.sol:52` (`+= fullHalfPasses`) | unchanged |
| `whalePassClaims` writer (jackpot) | `contracts/modules/DegenerusGameJackpotModule.sol:1410` (`+= whalePassCount`) | unchanged |
| `whalePassClaims` reader (claim) | `contracts/modules/DegenerusGameWhaleModule.sol:1020` (`uint256 halfPasses = whalePassClaims[player];`) | unchanged |
| `whalePassClaims` zero-write (claim) | `contracts/modules/DegenerusGameWhaleModule.sol:1024` (`whalePassClaims[player] = 0;`) | unchanged |
| `whalePassClaims` public getter | `contracts/DegenerusGame.sol:2645` (`whalePassClaimAmount(`) | unchanged |
| `claimWhalePass(address player)` def | `contracts/modules/DegenerusGameWhaleModule.sol:1018` | unchanged |
| `claimWhalePass` liveness gate | `contracts/modules/DegenerusGameWhaleModule.sol:1019` (`if (_livenessTriggered()) revert E();`) | unchanged |
| `claimWhalePass` target start level | `contracts/modules/DegenerusGameWhaleModule.sol:1030` (`uint24 startLevel = level + 1;`) | unchanged |
| `claimWhalePass` stats-at-claim | `contracts/modules/DegenerusGameWhaleModule.sol:1032` (`_applyWhalePassStats(player, startLevel);`) | unchanged |
| `claimWhalePass` far-future queue | `contracts/modules/DegenerusGameWhaleModule.sol:1034` (`_queueTicketRange(player, startLevel, 100, uint32(halfPasses), false);`) | unchanged |
| `_applyWhalePassStats` def | `contracts/storage/DegenerusGameStorage.sol:1111` | unchanged |
| `_applyWhalePassStats` call site (claim) | `contracts/modules/DegenerusGameWhaleModule.sol:1032` | unchanged |
| `_applyWhalePassStats` call site (decimator) | `contracts/modules/DegenerusGameDecimatorModule.sol:588` (`_applyWhalePassStats(winner, startLevel);`) | unchanged |
| `_applyWhalePassStats` call-site count | **2** (the box-open caller is gone post-v50) | **DRIFTED** from 3 |

## F. lazyPassHorizon / autoOpen (DRIFTED — items 4, 5)

`DegenerusGame.sol` — TOUCHED by v50.

| Anchor (symbol / role) | Confirmed `file:line` at HEAD | Status |
|------------------------|-------------------------------|--------|
| **`lazyPassHorizon(address)` view** | **`contracts/DegenerusGame.sol:1540` (`function lazyPassHorizon(address player) external view returns (uint24)`)** | **NEW IN v50** (non-VRF-participating). |
| `enqueueBoxForAutoOpen` | `contracts/DegenerusGame.sol:1588` | **DRIFTED** line. |
| `autoOpen(uint256 maxCount)` | `contracts/DegenerusGame.sol:1695` (`function autoOpen(uint256 maxCount) external returns (uint256 opened)`) | **DRIFTED** line. |
| `_autoOpenBox` | `contracts/DegenerusGame.sol:1762` | confirmed |
| `OPEN_NORMAL_GAS_UNIT` carve-out | **DELETED** (no occurrence in `contracts/`) | **DRIFTED** — retired; autoOpen budget is now flat. |
| `level` public auto-getter | `contracts/storage/DegenerusGameStorage.sol:245` (`uint24 public level = 0;`) | unchanged |

## G. BurnieCoin rngLocked() Mirror (coinflip-timing gate locator)

`BurnieCoin.sol` — TOUCHED by v50 (the `burnForKeeper`/keeper path was removed), but the `rngLocked()` mirror reads are preserved.

| Anchor (symbol / role) | Confirmed `file:line` at HEAD | Status |
|------------------------|-------------------------------|--------|
| `degenerusGame.rngLocked()` consume (claim-shortfall) | `contracts/BurnieCoin.sol:455` (`if (degenerusGame.rngLocked()) return;`) | unchanged |
| `degenerusGame.rngLocked()` consume (consume-shortfall) | `contracts/BurnieCoin.sol:470` (`if (degenerusGame.rngLocked()) revert Insufficient();`) | unchanged |

---

## Module Inventory Confirmation

`contracts/modules/` contains exactly **11** module files (re-confirmed by directory listing):
`DegenerusGameAdvanceModule.sol`, `DegenerusGameBoonModule.sol`, `DegenerusGameDecimatorModule.sol`, `DegenerusGameDegeneretteModule.sol`, `DegenerusGameGameOverModule.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameMintStreakUtils.sol`, `DegenerusGamePayoutUtils.sol`, `DegenerusGameWhaleModule.sol`. (The legacy "10 modules" framing in older audit docs is stale — there is no separate `EndgameModule.sol` file at HEAD.)
