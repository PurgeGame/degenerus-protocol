# v30.0 Phase 237 Plan 03 — INV-03 Per-Consumer Call Graphs

**Audit baseline:** HEAD `7ab515fe` (contract tree identical to v29.0 `1646d5af`; post-v29 commits are docs-only per D-17).
**Requirement addressed:** INV-03 — per-consumer call graph from VRF request origination through `rawFulfillRandomWords` to consumption site, including all intermediate storage touchpoints.
**Depth rule (per D-11):** request → fulfillment → consumption. STOP at consumption; forward SSTORE of consumption result is Phase 238 FWD scope. Delegatecalls traced to target module; library calls traced to library function signature.
**Presentation (per D-09):** tabular + prose. No mermaid.
**Companion files (per D-12):** oversized graphs (>~30 lines) hived off to `audit/v30-237-CALLGRAPH-{slug}.md` companion files (none created — all 146 graphs fit inline via aggressive shared-prefix deduplication; see Shared-Prefix Notes).
**Input:** `audit/v30-237-01-UNIVERSE.md` (146 Row IDs) and `audit/v30-237-02-CLASSIFICATION.md` (path-family assignments). READ-only per D-16 — this plan does not edit them.

## Call Graph Conventions

| Hop Type | Meaning |
|---|---|
| `request-origination` | VRF `requestRandomWords(...)` call site |
| `storage-mutation (request commitment)` | SSTORE writing request-side state (e.g., `vrfRequestId`, `rngLockedFlag = true`, lootbox index advance) |
| `vrf-callback` | VRF coordinator calls back into the contract via `rawFulfillRandomWords` — external contract hop, not traced further |
| `storage-sstore (fulfillment commitment)` | SSTORE writing the VRF word into storage (`rngWordCurrent`, `rngWordByDay[day]`, `lootboxRngWordByIndex[idx]`) |
| `direct-call` | Solidity `fn(...)` or `IContract.fn(...)` call on same or external address |
| `delegatecall` | `address.delegatecall(abi.encodeWithSelector(IFACE.fn.selector, ...))` — traced to target module per D-11 |
| `library-call` | library-function invocation (e.g., `EntropyLib.hash2(a, b)`) — traced to library function signature per D-11 |
| `storage-sload` | SLOAD of VRF-derived state (`rngWordByDay[day]`, `lootboxRngWordByIndex[idx]`, `rngWordCurrent`) on the consumption chain |
| `consumption` | the consumption site — D-11 STOP boundary |
| `ki-exception` | KI-documented deviation (non-VRF seed / prevrandao mix / F-29-04 substitution / EntropyLib XOR-shift PRNG) — not a separate Hop Type semantically, a flag appended to an underlying Hop Type |

## Shared-Prefix Notes

Most consumers share one of four upstream chains. To avoid repeating them across 146 entries, each shared prefix is defined once here; per-row entries reference `[PREFIX-X shared, see above]` for rows 1-N of their tabular body.

**PREFIX-DAILY — Shared daily-path prefix (applies to `daily` family rows via rngGate → rngWordCurrent):**

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:156 | `advanceGame()` entry | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:283-289 | `rngGate(ts, day, purchaseLevel, lastPurchase, bonusFlip)` daily-RNG gate invocation | direct-call |
| 3 | contracts/modules/DegenerusGameAdvanceModule.sol:1519-1532 | `_requestRng(isTicketJackpotDay, lvl)` origination via `vrfCoordinator.requestRandomWords(...)` at :1521 (hard-revert branch) | request-origination |
| 4 | contracts/modules/DegenerusGameAdvanceModule.sol:1555-1614 | `_finalizeRngRequest(isTicketJackpotDay, lvl, requestId)` — `vrfRequestId = requestId` at :1576, `rngWordCurrent = 0` at :1577, `rngRequestTime = block.timestamp` at :1578, `rngLockedFlag = true` at :1579 | storage-mutation (request commitment) |
| 5 | [VRF coordinator — external contract, not traced] | `rawFulfillRandomWords(requestId, randomWords)` re-entry | vrf-callback |
| 6 | contracts/modules/DegenerusGameAdvanceModule.sol:1690-1710 | `rawFulfillRandomWords` callback: daily branch SSTORE `rngWordCurrent = word;` at :1702 (daily branch, `rngLockedFlag` true) | storage-sstore (fulfillment commitment) |
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1133-1199 | `rngGate(...)` body re-entry on next advanceGame call — reads `rngWordCurrent` at :1143, applies nudges via `_applyDailyRng(day, currentWord)` at :1164, writes `rngWordByDay[day]` and `rngWordCurrent=0` inside _applyDailyRng | storage-sload |
| 8 | [per-consumer continuation below] | [consumption chain for this specific row] | [varies] |

**PREFIX-MIDDAY — Shared mid-day-lootbox prefix (applies to `mid-day-lootbox` family rows, gated by index-advance isolation, NOT `rngLockedFlag`):**

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:1030 | `requestLootboxRng()` external entry (permissionless when index condition met) | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1082 | `_swapTicketSlot(purchaseLevel_)` — write-buffer swap (F-29-04 surface; see INV-237-045) | storage-mutation (request commitment) / ki-exception |
| 3 | contracts/modules/DegenerusGameAdvanceModule.sol:1088 | `vrfCoordinator.requestRandomWords(...)` mid-day VRF origination | request-origination |
| 4 | contracts/modules/DegenerusGameAdvanceModule.sol:1555-1614 | `_finalizeRngRequest(...)` — advances `lootboxRngIndex` at :1568 (mid-day request: `rngLockedFlag` NOT set; mid-day does not claim daily lock) | storage-mutation (request commitment) |
| 5 | [VRF coordinator — external contract, not traced] | `rawFulfillRandomWords(requestId, randomWords)` re-entry | vrf-callback |
| 6 | contracts/modules/DegenerusGameAdvanceModule.sol:1690-1710 | `rawFulfillRandomWords` callback: mid-day branch SSTORE `lootboxRngWordByIndex[index] = word;` at :1706 (mid-day branch — `rngLockedFlag` false, index decoded at :1705) | storage-sstore (fulfillment commitment) |
| 7 | [per-consumer continuation below] | SLOAD `lootboxRngWordByIndex[...]` at consumer's site | storage-sload |

**PREFIX-GAMEOVER — Shared gameover-entropy prefix (applies to `gameover-entropy` family rows):**

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:156 | `advanceGame()` entry (game-over branch when `gameOver == true`) | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1213-1288 | `_gameOverEntropy(ts, day, lvl, isTicketJackpotDay)` gate | direct-call |
| 3a | contracts/modules/DegenerusGameAdvanceModule.sol:1280 / :1534-1553 | `_tryRequestRng(...)` try/catch VRF origination via `vrfCoordinator.requestRandomWords(...)` at :1539 (branch when no rngRequestTime) | request-origination |
| 3b | contracts/modules/DegenerusGameAdvanceModule.sol:1248-1277 | Fallback branch: after GAMEOVER_RNG_FALLBACK_DELAY, `_getHistoricalRngFallback(day)` at :1252 supplies prevrandao-mixed `fallbackWord` (KI exception — see PREFIX-PREVRANDAO below) | ki-exception |
| 4 | contracts/modules/DegenerusGameAdvanceModule.sol:1555-1614 | `_finalizeRngRequest(...)` (same as daily — sets vrfRequestId / rngLockedFlag = true) | storage-mutation (request commitment) |
| 5 | [VRF coordinator — external contract, not traced] | `rawFulfillRandomWords(requestId, randomWords)` re-entry (daily branch — gameover uses the daily rngWordCurrent route) | vrf-callback |
| 6 | contracts/modules/DegenerusGameAdvanceModule.sol:1702 | `rngWordCurrent = word;` SSTORE (daily branch of callback — rngLockedFlag true) | storage-sstore (fulfillment commitment) |
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1221-1223 | `_gameOverEntropy` re-entry reads `rngWordCurrent` at :1221, applies nudges via `_applyDailyRng(day, currentWord)` at :1223; returns `currentWord` at :1245 | storage-sload |
| 8 | contracts/modules/DegenerusGameGameOverModule.sol:97 | `handleGameOverDrain` SLOAD `rngWordByDay[day]` (written by `_applyDailyRng` above) | storage-sload |
| 9 | [per-consumer continuation below] | [consumption chain for this specific gameover row] | [varies] |

**PREFIX-PREVRANDAO — KI-exception gameover fallback (applies to `other / exception-prevrandao-fallback` rows 55-62; replaces PREFIX-GAMEOVER steps 3-7 when VRF has stalled ≥ GAMEOVER_RNG_FALLBACK_DELAY):**

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:1248-1250 | Fallback-gate: `if (rngRequestTime != 0 && elapsed >= GAMEOVER_RNG_FALLBACK_DELAY)` | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1301-1325 | `_getHistoricalRngFallback(currentDay)` internal view; iterates `rngWordByDay[searchDay]` SLOAD at :1308 (up to 5 historical words), builds `combined = keccak(combined, w)` at :1310, then final `keccak(combined, currentDay, block.prevrandao)` at :1322 | library-call (keccak) / ki-exception |
| 3 | contracts/modules/DegenerusGameAdvanceModule.sol:1253 | `fallbackWord = _applyDailyRng(day, fallbackWord)` — nudges applied, `rngWordByDay[day] = fallbackWord` written inside `_applyDailyRng` | storage-mutation (request commitment) |
| 4 | [per-consumer continuation below — per fallback consumer at :1257 / :1268 / :1274] | [consumption chain] | [varies] |

**PREFIX-AFFILIATE — KI-exception non-VRF seed (applies to `other / exception-non-VRF-seed` rows 5-6; no VRF hop at all):**

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | [payment entry — `processAffiliatePayment(...)` called from Game / purchase paths] | Payment flow invokes affiliate split | direct-call |
| 2 | contracts/DegenerusAffiliate.sol (seed construction) | `keccak256(abi.encodePacked(AFFILIATE_ROLL_TAG, currentDayIndex(), sender, storedCode))` — deterministic, non-VRF (KI exception) | library-call (keccak) / ki-exception |
| 3 | [per-row consumption — 50/50 flip or 75/20/5 winner roll] | [see per-row body] | consumption |

**PREFIX-GAP — Shared gap-backfill prefix (applies to `gap-backfill` family rows 67-69):**

Identical to PREFIX-DAILY steps 1-6 (daily VRF origination + fulfillment); divergence begins at step 7 inside `rngGate` when `day > dailyIdx + 1`:

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1148-1161 | `rngGate` body: detects `day > idx + 1`, computes `gapCount`, invokes `_backfillGapDays(currentWord, idx + 1, day, bonusFlip)` at :1151 and `_backfillOrphanedLootboxIndices(currentWord)` at :1155 | direct-call |
| 8 | [per-consumer continuation — specific gap entropy derivation below] | [varies] | [varies] |

## Per-Consumer Call Graphs

Each entry: Consumption site + Path family + short tabular body + KI Cross-Ref. All per-consumer graphs STOP at the consumption site per D-11 (no forward SSTORE of the consumption result is traced — that is Phase 238 FWD scope). All `contracts/` line anchors verified at HEAD `7ab515fe`.

### INV-237-001 — processCoinflipPayouts (daily)

**Consumption site:** contracts/BurnieCoinflip.sol:808
**Path family:** daily
**Upstream:** PREFIX-DAILY shared (steps 1-7 above) — `rngWordCurrent` = daily VRF word at step 6, applied into `rngWordByDay[day]` at step 7.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1165 | `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)` inside `rngGate` | direct-call |
| 9 | contracts/BurnieCoinflip.sol:808 | Seed derivation `keccak(rngWord, epoch)` for rewardPercent / bounty resolution entry | consumption |

**KI Cross-Ref:** N/A

### INV-237-002 — processCoinflipPayouts (daily)

**Consumption site:** contracts/BurnieCoinflip.sol:813
**Path family:** daily
**Upstream:** PREFIX-DAILY + shared step 8 as per INV-237-001 (`processCoinflipPayouts` entered at L808).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/BurnieCoinflip.sol:813 | `seedWord % 20` rewardPercent tier roll | consumption |

**KI Cross-Ref:** N/A

### INV-237-003 — processCoinflipPayouts (daily)

**Consumption site:** contracts/BurnieCoinflip.sol:822
**Path family:** daily
**Upstream:** PREFIX-DAILY + `processCoinflipPayouts` entry as per INV-237-001.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/BurnieCoinflip.sol:822 | `seedWord % COINFLIP_EXTRA_RANGE` rewardPercent normal-range | consumption |

**KI Cross-Ref:** N/A

### INV-237-004 — processCoinflipPayouts (daily)

**Consumption site:** contracts/BurnieCoinflip.sol:834
**Path family:** daily
**Upstream:** PREFIX-DAILY + `processCoinflipPayouts` entry as per INV-237-001.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/BurnieCoinflip.sol:834 | `rngWord & 1` win/loss bit | consumption |

**KI Cross-Ref:** N/A

### INV-237-005 — processAffiliatePayment (no-referrer branch) (other / exception-non-VRF-seed)

**Consumption site:** contracts/DegenerusAffiliate.sol:568
**Path family:** other (exception-non-VRF-seed)
**Upstream:** PREFIX-AFFILIATE (no VRF hop at all — KI exception, deterministic seed).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 3 | contracts/DegenerusAffiliate.sol:568 | 50/50 flip VAULT/DGNRS from deterministic `keccak(AFFILIATE_ROLL_TAG, currentDayIndex(), sender, storedCode)` | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Non-VRF entropy for affiliate winner roll"]

### INV-237-006 — processAffiliatePayment (referred branch) (other / exception-non-VRF-seed)

**Consumption site:** contracts/DegenerusAffiliate.sol:585
**Path family:** other (exception-non-VRF-seed)
**Upstream:** PREFIX-AFFILIATE.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 3 | contracts/DegenerusAffiliate.sol:585 | 75/20/5 weighted winner roll (affiliate / upline1 / upline2) from deterministic seed | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Non-VRF entropy for affiliate winner roll"]

### INV-237-007 — deityBoonData (view helper) (daily)

**Consumption site:** contracts/DegenerusGame.sol:849
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 7 (rngWordByDay[day] recorded).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/DegenerusGame.sol:849 | `rngWordByDay[day]` SLOAD used as dailySeed for boon slot derivation | consumption |

**KI Cross-Ref:** N/A

### INV-237-008 — deityBoonData (view helper) (daily)

**Consumption site:** contracts/DegenerusGame.sol:850
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 6 (rngWordCurrent written; rngWordByDay[day] not yet written).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/DegenerusGame.sol:850 | Fallback SLOAD `rngWordCurrent` when `rngWordByDay[day] == 0` (pre-record window) | consumption |

**KI Cross-Ref:** N/A

### INV-237-009 — deityBoonData (view helper) (other / view-deterministic-fallback)

**Consumption site:** contracts/DegenerusGame.sol:852
**Path family:** other (view-deterministic-fallback)
**Upstream:** None — deterministic pre-genesis fallback, reachable only when both `rngWordByDay[day] == 0` AND `rngWordCurrent == 0` (pre-first-advance).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/DegenerusGame.sol:852 | `keccak(day, this)` deterministic fallback seed (zero-history pre-genesis branch) | consumption |

**KI Cross-Ref:** N/A — NOTE: this row is a KI-exception degenerate case (no VRF chain; view-only fallback). At HEAD runtime unreachable post-level-1.

### INV-237-010 — resolveRedemptionLootbox (re-hashing loop) (daily)

**Consumption site:** contracts/DegenerusGame.sol:1769
**Path family:** daily
**Upstream:** PREFIX-DAILY + `sDGNRS.claimRedemption` path which passes `keccak(rngWordForDay(claimPeriodIndex), player)` as entropy (same source as INV-237-020).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/StakedDegenerusStonk.sol:660 | `keccak(rngWordForDay(claimPeriodIndex), player)` entropy seed constructed (see INV-237-020) | library-call (keccak) |
| 9 | contracts/DegenerusGame.sol:1769 | Iterative `rngWord = keccak(rngWord)` per 5 ETH chunk in `resolveRedemptionLootbox` loop | consumption |

**KI Cross-Ref:** N/A

### INV-237-011 — sampleFarFutureTickets (view) (daily)

**Consumption site:** contracts/DegenerusGame.sol:2436
**Path family:** daily
**Upstream:** PREFIX-DAILY + `runBafJackpot` entropy argument chain (see INV-237-013/INV-237-014).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/DegenerusJackpots.sol:287/329 | `runBafJackpot` computes entropy salt for far-future draws | direct-call |
| 9 | contracts/DegenerusGame.sol:2436 | Iterative `keccak(word, s)` to step through 10 far-future level candidates | consumption |

**KI Cross-Ref:** N/A

### INV-237-012 — runBafJackpot (slice B pick) (daily)

**Consumption site:** contracts/DegenerusJackpots.sol:270
**Path family:** daily
**Upstream:** PREFIX-DAILY + `_consolidatePoolsAndRewardJackpots` → self-call `runBafJackpot(...)` at AdvanceModule:820.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:820 | `IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord)` self-call (delegatecall-routed through DegenerusGame shell) | delegatecall |
| 9 | contracts/DegenerusJackpots.sol:270 | `keccak(entropy, salt)` for 3rd/4th BAF leaderboard pick | consumption |

**KI Cross-Ref:** N/A

### INV-237-013 — runBafJackpot (slice D far-future 1st draw) (daily)

**Consumption site:** contracts/DegenerusJackpots.sol:287
**Path family:** daily
**Upstream:** PREFIX-DAILY + `runBafJackpot` entry per INV-237-012.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/DegenerusJackpots.sol:287 | `keccak(entropy, salt)` entropy advance before `sampleFarFutureTickets` call 1 | consumption |

**KI Cross-Ref:** N/A

### INV-237-014 — runBafJackpot (slice D2 far-future 2nd draw) (daily)

**Consumption site:** contracts/DegenerusJackpots.sol:329
**Path family:** daily
**Upstream:** PREFIX-DAILY + `runBafJackpot` entry per INV-237-012.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/DegenerusJackpots.sol:329 | `keccak(entropy, salt)` entropy advance before `sampleFarFutureTickets` call 2 | consumption |

**KI Cross-Ref:** N/A

### INV-237-015 — runBafJackpot (scatter per-round) (daily)

**Consumption site:** contracts/DegenerusJackpots.sol:385
**Path family:** daily
**Upstream:** PREFIX-DAILY + `runBafJackpot` entry per INV-237-012.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/DegenerusJackpots.sol:385 | Per-round `keccak(entropy, salt)` chain seeding 50 BAF scatter rounds | consumption |

**KI Cross-Ref:** N/A

### INV-237-016 — rollDailyQuest (daily)

**Consumption site:** contracts/DegenerusQuests.sol:342
**Path family:** daily
**Upstream:** PREFIX-DAILY + `rngGate` inside body.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1166 | `quests.rollDailyQuest(day, currentWord)` direct-call | direct-call |
| 9 | contracts/DegenerusQuests.sol:342 | `bonusEntropy = rotate-128 of rngWord` → `_bonusQuestType` weighted roll for slot 1 | consumption |

**KI Cross-Ref:** N/A

### INV-237-017 — _bonusQuestType (weighted roll helper) (other / library-wrapper)

**Consumption site:** contracts/DegenerusQuests.sol:1521
**Path family:** other (library-wrapper)
**Upstream:** per-caller rows carry upstream. Callers: `rollDailyQuest` (INV-237-016) and `rollLevelQuest` (INV-237-018) — both daily.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| N | contracts/DegenerusQuests.sol:1521 | `entropy % total` weighted roll on caller-supplied entropy | consumption |

**KI Cross-Ref:** N/A

### INV-237-018 — rollLevelQuest (daily)

**Consumption site:** contracts/DegenerusQuests.sol:1781
**Path family:** daily
**Upstream:** PREFIX-DAILY + `advanceGame` level-transition call at AdvanceModule:438.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:438 | `quests.rollLevelQuest(rngWord)` direct-call at level transition (inside jackpot-phase entry) | direct-call |
| 9 | contracts/DegenerusQuests.sol:1781 | `rngWord` drives levelQuestType selection | consumption |

**KI Cross-Ref:** N/A

### INV-237-019 — deityBoonSlots (pure view) (daily)

**Consumption site:** contracts/DeityBoonViewer.sol:109
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 7 (rngWordByDay[day] recorded); view-only re-read.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/DeityBoonViewer.sol (caller entry via IDeityBoonDataSource) | Reads dailySeed via `IDeityBoonDataSource` interface bound to DegenerusGame — ultimately SLOAD `rngWordByDay[day]` | storage-sload |
| 9 | contracts/DeityBoonViewer.sol:109 | `keccak(dailySeed, deity, d, i)` boon slot reconstruction | consumption |

**KI Cross-Ref:** N/A

### INV-237-020 — claimRedemption (lootbox-portion path) (daily)

**Consumption site:** contracts/StakedDegenerusStonk.sol:660
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 7 (rngWordByDay[claimPeriodIndex] recorded for that claim period).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/StakedDegenerusStonk.sol (prior to :660) | `rngWordForDay(claimPeriodIndex)` → SLOAD `rngWordByDay[claimPeriodIndex]` via IDegenerusGame view | storage-sload |
| 9 | contracts/StakedDegenerusStonk.sol:660 | `keccak(rngWordForDay(claimPeriodIndex), player)` entropy passed to `resolveRedemptionLootbox` | consumption |

**KI Cross-Ref:** N/A

### INV-237-021 — advanceGame (mid-day lootbox gate check) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:204
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY through step 6 (lootboxRngWordByIndex[index] written at :1706).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:204-208 | SLOAD `lootboxRngWordByIndex[index-1]` and `revert RngNotReady()` if zero — gate for ticket-batch processing | consumption (storage-sload gate) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-022 — advanceGame (daily-drain gate pre-check) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:261
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 6.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:260-261 | SLOAD `lootboxRngWordByIndex[preIdx]` — decides whether to finalize via `rngWordCurrent` before draining read slot (gated by index-advance, not `rngLockedFlag`) | consumption (storage-sload decision gate) |

**KI Cross-Ref:** N/A

### INV-237-023 — advanceGame (daily-drain gate pre-check) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:262
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:262 | SLOAD `rngWordCurrent` seeds `_finalizeLootboxRng(cw + totalFlipReversals)` when index slot is empty | consumption |

**KI Cross-Ref:** N/A

### INV-237-024 — advanceGame (ticket-buffer swap for daily RNG) (other / exception-mid-cycle-substitution)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:292
**Path family:** other (exception-mid-cycle-substitution)
**Upstream:** PREFIX-DAILY through step 3 (this is a write-buffer swap that happens BEFORE the daily VRF request is emitted via step 3 `_requestRng`).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 3a | contracts/modules/DegenerusGameAdvanceModule.sol:292 | `_swapAndFreeze(purchaseLevel)` — F-29-04 surface: write-buffer swap before daily VRF request, mid-cycle substitution exception | storage-mutation (request commitment) / ki-exception |
| 3b | [continues PREFIX-DAILY step 3] | VRF request issued afterwards | request-origination |

**KI Cross-Ref:** [KI: "Gameover RNG substitution for mid-cycle write-buffer tickets"]

### INV-237-025 — advanceGame (FF drain processing) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:317
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 7 (rngWord available).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:315-318 | `_processFutureTicketBatch(ffLevel, rngWord)` — wrapper that delegatecalls MintModule.processFutureTicketBatch (IM-13 boundary per 230-01) | delegatecall |
| 9 | contracts/modules/DegenerusGameMintModule.sol:568 / :652 | MintModule receiver — consumed downstream at INV-237-143 (_raritySymbolBatch) and INV-237-144 (_rollRemainder) | direct-call |
| 10 | contracts/modules/DegenerusGameAdvanceModule.sol:317 | rngWord passed into the FF batch processing entropy chain | consumption |

**KI Cross-Ref:** N/A

### INV-237-026 — advanceGame (near-future ticket prep) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:339
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:336-341 | `_prepareFutureTickets(inJackpot ? lvl : purchaseLevel, rngWord)` delegatecall wrapper | delegatecall |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:339 | rngWord argument supplied to near-future ticket prep (consumed downstream in MintModule) | consumption |

**KI Cross-Ref:** N/A

### INV-237-027 — advanceGame (L1 emitDailyWinningTraits) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:364
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:364 | `_emitDailyWinningTraits(1, rngWord, 1)` — L1 special case | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1705-1707 | Downstream consumption (see INV-237-113..115) | consumption |

**KI Cross-Ref:** N/A

### INV-237-028 — advanceGame (L1 main coin jackpot) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:365
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:365 | `_payDailyCoinJackpot(1, rngWord, 1, 1)` at purchaseLevel==1 main slot | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1679-1686 | Downstream consumption in `payDailyCoinJackpot` (see INV-237-111/112) | consumption |

**KI Cross-Ref:** N/A

### INV-237-029 — advanceGame (L1 bonus coin jackpot) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:367-374
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:366-373 | `saltedRng = keccak(rngWord, keccak("BONUS_TRAITS"))` domain-separated seed for 2nd (bonus) coin jackpot call at L1 | library-call (keccak) |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:374 | `_payDailyCoinJackpot(1, saltedRng, 2, 5)` | consumption |

**KI Cross-Ref:** N/A

### INV-237-030 — advanceGame (purchase-phase daily jackpot) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:376
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:376 | `payDailyJackpot(false, purchaseLevel, rngWord)` (levels ≥ 2) | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:343+ | Downstream consumption in `payDailyJackpot` body (see INV-237-082..091) | consumption |

**KI Cross-Ref:** N/A

### INV-237-031 — advanceGame (purchase-phase near-future coin jackpot) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:377-382
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:377-382 | `_payDailyCoinJackpot(purchaseLevel, rngWord, purchaseLevel+1, purchaseLevel+4)` over near-future range | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1679-1686 | Downstream consumption per INV-237-111/112 | consumption |

**KI Cross-Ref:** N/A

### INV-237-032 — advanceGame (purchase-phase consolidation yieldSurplus) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:416
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:416 | `_distributeYieldSurplus(rngWord)` — auto-rebuy entropy | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:736-746 | Downstream consumption — threaded into 3× `_addClaimableEth` (INV-237-099) | consumption |

**KI Cross-Ref:** N/A

### INV-237-033 — advanceGame (purchase-phase pool consolidation) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:417-423
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:417-423 | `_consolidatePoolsAndRewardJackpots(lvl, purchaseLevel, day, rngWord, psd)` — internal function at :721 | direct-call |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:721+ | Consolidation body — drives BAF, Decimator, keep-roll (INV-237-038..043) | consumption |

**KI Cross-Ref:** N/A

### INV-237-034 — advanceGame (rollLevelQuest call) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:438
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:438 | `quests.rollLevelQuest(rngWord)` at level transition | direct-call |
| 9 | contracts/DegenerusQuests.sol:1781 | Downstream consumption (INV-237-018) | consumption |

**KI Cross-Ref:** N/A

### INV-237-035 — advanceGame (jackpot-phase resume) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:450
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:450 | `payDailyJackpot(true, lvl, rngWord)` resume branch | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:343+ | Resume branch body (INV-237-104..106) | consumption |

**KI Cross-Ref:** N/A

### INV-237-036 — advanceGame (jackpot-phase coin+tickets) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:458
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:458 | `payDailyJackpotCoinAndTickets(rngWord)` Phase 2 of split | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:592-610 | Phase-2 consumers (INV-237-093..096) | consumption |

**KI Cross-Ref:** N/A

### INV-237-037 — advanceGame (jackpot-phase fresh daily) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:470
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:470 | `payDailyJackpot(true, lvl, rngWord)` fresh branch | direct-call |
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:343+ | Fresh branch body (INV-237-082..091) | consumption |

**KI Cross-Ref:** N/A

### INV-237-038 — _consolidatePoolsAndRewardJackpots (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:767
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-033 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:767 | `rngWord % (ADDITIVE_RANDOM_BPS + 1)` additive 0-10% bps | consumption |

**KI Cross-Ref:** N/A

### INV-237-039 — _consolidatePoolsAndRewardJackpots (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:781
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-033 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:781 | `(rngWord >> 64) % range` roll1 triangular variance | consumption |

**KI Cross-Ref:** N/A

### INV-237-040 — _consolidatePoolsAndRewardJackpots (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:782
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-033 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:782 | `(rngWord >> 192) % range` roll2 triangular variance | consumption |

**KI Cross-Ref:** N/A

### INV-237-041 — _consolidatePoolsAndRewardJackpots (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:820
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-033 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:820 | `IDegenerusGame(address(this)).runBafJackpot(...)` self-call at x10 levels — passes rngWord | delegatecall |
| 10 | contracts/DegenerusJackpots.sol:270/287/329/385 | Consumed at INV-237-012..015 | consumption |

**KI Cross-Ref:** N/A

### INV-237-042 — _consolidatePoolsAndRewardJackpots (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:840
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-033 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:840 | `IDegenerusGame(address(this)).runDecimatorJackpot(...)` self-call at x5/x00 window-close — passes rngWord | delegatecall |
| 10 | contracts/modules/DegenerusGameDecimatorModule.sol:228 | Consumed at INV-237-070 | consumption |

**KI Cross-Ref:** N/A

### INV-237-043 — _consolidatePoolsAndRewardJackpots (keep-roll seed) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:849-850
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-033 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:849-850 | `seed = keccak(rngWord, FUTURE_KEEP_TAG)` x00 keep-roll 5d4 dice seed | consumption |

**KI Cross-Ref:** N/A

### INV-237-044 — requestLootboxRng (VRF request origination, mid-day) (other / request-origination)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1088
**Path family:** other (request-origination)
**Upstream:** none — this IS the request-origination site itself (PREFIX-MIDDAY step 3).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:1030 | `requestLootboxRng()` external permissionless entry | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1088 | `vrfCoordinator.requestRandomWords(...)` origination | consumption (origination) |

**KI Cross-Ref:** N/A — NOTE: This row is a request-origination infrastructure row per D-11 (not a VRF consumer itself); recorded per D-06 traceability.

### INV-237-045 — requestLootboxRng (ticket buffer swap) (other / exception-mid-cycle-substitution)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1082
**Path family:** other (exception-mid-cycle-substitution)
**Upstream:** PREFIX-MIDDAY step 2 (this is the write-buffer swap that immediately precedes the mid-day VRF request at step 3).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1082 | `_swapTicketSlot(purchaseLevel_)` — F-29-04 write-buffer swap before mid-day VRF request | consumption (storage-mutation) / ki-exception |

**KI Cross-Ref:** [KI: "Gameover RNG substitution for mid-cycle write-buffer tickets"]

### INV-237-046 — rngGate (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1141
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1141 | `if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);` — idempotent same-day re-entry | consumption (storage-sload) |

**KI Cross-Ref:** N/A

### INV-237-047 — rngGate (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1143
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1143 | `uint256 currentWord = rngWordCurrent;` SLOAD — feeds full daily processing chain below | consumption (storage-sload) |

**KI Cross-Ref:** N/A

### INV-237-048 — rngGate (_applyDailyRng call) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1164
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1164 | `currentWord = _applyDailyRng(day, currentWord)` — nudge adjustment; records `rngWordByDay[day]` and clears `rngWordCurrent` | consumption |

**KI Cross-Ref:** N/A

### INV-237-049 — rngGate (redemption roll) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1175
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1175 | `redemptionRoll = ((currentWord >> 8) % 151) + 25` — sDGNRS gambling burn roll | consumption |

**KI Cross-Ref:** N/A

### INV-237-050 — rngGate (_finalizeLootboxRng call) (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1182
**Path family:** daily
**Upstream:** PREFIX-DAILY.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1182 | `_finalizeLootboxRng(currentWord)` — writes daily VRF word into `lootboxRngWordByIndex[index-1]` (dual-use slot) | consumption |

**KI Cross-Ref:** N/A

### INV-237-051 — _finalizeLootboxRng (daily)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1204
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-050 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1201-1206 | `_finalizeLootboxRng` body checks `lootboxRngWordByIndex[index] != 0`, then writes | direct-call |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:1204 | `lootboxRngWordByIndex[index] = rngWord;` SSTORE (zero-state) | consumption |

**KI Cross-Ref:** N/A

### INV-237-052 — _gameOverEntropy (short-circuit) (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1219
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER through step 7.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1219 | `if (rngWordByDay[day] != 0) return rngWordByDay[day];` — fast-return when already recorded | consumption (storage-sload) |

**KI Cross-Ref:** N/A

### INV-237-053 — _gameOverEntropy (fresh VRF word) (other / exception-mid-cycle-substitution)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1221-1223
**Path family:** other (exception-mid-cycle-substitution)
**Upstream:** PREFIX-GAMEOVER through step 7.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1221 | `uint256 currentWord = rngWordCurrent;` — SLOAD | storage-sload |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:1223 | `currentWord = _applyDailyRng(day, currentWord)` — KI exception: currentWord substitutes for mid-day expectation at gameover (F-29-04) | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover RNG substitution for mid-cycle write-buffer tickets"]

### INV-237-054 — _gameOverEntropy (consumer cluster) (other / exception-mid-cycle-substitution)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1222-1246
**Path family:** other (exception-mid-cycle-substitution)
**Upstream:** PREFIX-GAMEOVER + INV-237-053.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameAdvanceModule.sol:1225 | `coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day)` — coinflip processing block | consumption / ki-exception |
| 11 | contracts/modules/DegenerusGameAdvanceModule.sol:1237-1239 | `redemptionRoll = ((currentWord >> 8) % 151) + 25` — redemption roll under gameover substitution | consumption / ki-exception |
| 12 | contracts/modules/DegenerusGameAdvanceModule.sol:1244 | `_finalizeLootboxRng(currentWord)` — lootbox finalization under substitution | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover RNG substitution for mid-cycle write-buffer tickets"]

### INV-237-055 — _gameOverEntropy (historical fallback call) (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1252
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:1248-1250 | Gate: elapsed since rngRequestTime ≥ GAMEOVER_RNG_FALLBACK_DELAY | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1252 | `fallbackWord = _getHistoricalRngFallback(day)` — KI exception prevrandao-fallback invocation | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-056 — _gameOverEntropy (fallback apply) (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1253
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO + INV-237-055.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 3 | contracts/modules/DegenerusGameAdvanceModule.sol:1253 | `fallbackWord = _applyDailyRng(day, fallbackWord)` — nudges + `rngWordByDay[day] = fallbackWord` | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-057 — _gameOverEntropy (fallback coinflip) (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1257
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO + INV-237-055..056.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 4 | contracts/modules/DegenerusGameAdvanceModule.sol:1255-1260 | `coinflip.processCoinflipPayouts(isTicketJackpotDay, fallbackWord, day)` (guarded by `lvl != 0`) | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-058 — _gameOverEntropy (fallback redemption roll) (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1268
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO + INV-237-055..056.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 4 | contracts/modules/DegenerusGameAdvanceModule.sol:1267-1269 | `redemptionRoll = ((fallbackWord >> 8) % 151) + 25` | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-059 — _gameOverEntropy (fallback lootbox finalize) (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1274
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO + INV-237-055..056.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 4 | contracts/modules/DegenerusGameAdvanceModule.sol:1274 | `_finalizeLootboxRng(fallbackWord)` — lootbox finalization under prevrandao fallback | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-060 — _getHistoricalRngFallback (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1308
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO step 2 body.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 2a | contracts/modules/DegenerusGameAdvanceModule.sol:1301-1307 | `_getHistoricalRngFallback(currentDay)` entry, search loop init | direct-call |
| 2b | contracts/modules/DegenerusGameAdvanceModule.sol:1308 | `uint256 w = rngWordByDay[searchDay];` — SLOAD bulk historical words (up to 5) | consumption (storage-sload) / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-061 — _getHistoricalRngFallback (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1310
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO + INV-237-060.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 2c | contracts/modules/DegenerusGameAdvanceModule.sol:1310 | `combined = uint256(keccak256(abi.encodePacked(combined, w)));` — cumulative hash of historical words | library-call (keccak) / ki-exception |
| 2d | [L1311-1319 iterate up to 5 historical words] | Iterative body | - |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-062 — _getHistoricalRngFallback (other / exception-prevrandao-fallback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1322
**Path family:** other (exception-prevrandao-fallback)
**Upstream:** PREFIX-PREVRANDAO + INV-237-060/061.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 2e | contracts/modules/DegenerusGameAdvanceModule.sol:1321-1323 | `word = keccak(abi.encodePacked(combined, currentDay, block.prevrandao))` — THE prevrandao-mix site (canonical KI subject) | consumption / ki-exception |

**KI Cross-Ref:** [KI: "Gameover prevrandao fallback"]

### INV-237-063 — _requestRng (VRF request origination, daily) (other / request-origination)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1521
**Path family:** other (request-origination)
**Upstream:** none — request-origination itself (PREFIX-DAILY step 3).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:1519 | `_requestRng(isTicketJackpotDay, lvl)` private entry | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1521-1530 | `vrfCoordinator.requestRandomWords(VRFRandomWordsRequest{...})` hard-revert daily VRF request | consumption (origination) |

**KI Cross-Ref:** N/A — request-origination infrastructure (not a consumer per D-11).

### INV-237-064 — _tryRequestRng (VRF request origination, try branch) (other / request-origination)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1539
**Path family:** other (request-origination)
**Upstream:** none — try/catch origination used only in `_gameOverEntropy` path (PREFIX-GAMEOVER step 3a).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 1 | contracts/modules/DegenerusGameAdvanceModule.sol:1534 | `_tryRequestRng(...)` private entry | direct-call |
| 2 | contracts/modules/DegenerusGameAdvanceModule.sol:1538-1552 | `try vrfCoordinator.requestRandomWords(...)` at :1539 — gameover-only try/catch | consumption (origination) |

**KI Cross-Ref:** N/A — request-origination infrastructure.

### INV-237-065 — rawFulfillRandomWords (daily branch SSTORE) (other / fulfillment-callback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1702
**Path family:** other (fulfillment-callback)
**Upstream:** PREFIX-DAILY steps 4-5 (coordinator callback).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 5 | [VRF coordinator external hop] | `rawFulfillRandomWords(requestId, randomWords)` external callback | vrf-callback |
| 6 | contracts/modules/DegenerusGameAdvanceModule.sol:1694-1700 | Validates `msg.sender == vrfCoordinator` at :1694, matches `requestId == vrfRequestId` at :1695, zero-guards at :1697-1698 | storage-sload |
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1700-1702 | Daily branch (`rngLockedFlag == true`): `rngWordCurrent = word;` SSTORE | consumption (storage-sstore fulfillment commitment) |

**KI Cross-Ref:** N/A — fulfillment-callback infrastructure.

### INV-237-066 — rawFulfillRandomWords (mid-day branch SSTORE) (other / fulfillment-callback)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1706
**Path family:** other (fulfillment-callback)
**Upstream:** PREFIX-MIDDAY steps 5-6.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 5 | [VRF coordinator external hop] | `rawFulfillRandomWords` callback | vrf-callback |
| 6 | contracts/modules/DegenerusGameAdvanceModule.sol:1700 | `if (rngLockedFlag)` branch taken = false (mid-day path — rngLockedFlag not claimed) | direct-call |
| 7 | contracts/modules/DegenerusGameAdvanceModule.sol:1705 | `uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;` decode index | direct-call |
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1706 | `lootboxRngWordByIndex[index] = word;` SSTORE (mid-day branch — no rngLockedFlag lock; isolation by index advance per KI) | consumption (storage-sstore fulfillment commitment) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-067 — _backfillGapDays (gap-backfill)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1735
**Path family:** gap-backfill
**Upstream:** PREFIX-GAP.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1724-1744 | `_backfillGapDays(vrfWord, startDay, endDay, bonusFlip)` iterates gap days | direct-call |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:1734-1735 | `derivedWord = keccak(abi.encodePacked(vrfWord, gapDay))` per-day entropy derivation | library-call (keccak) |
| 10 | contracts/modules/DegenerusGameAdvanceModule.sol:1738 | `rngWordByDay[gapDay] = derivedWord;` SSTORE | consumption |

**KI Cross-Ref:** N/A

### INV-237-068 — _backfillGapDays (coinflip payouts) (gap-backfill)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1739
**Path family:** gap-backfill
**Upstream:** PREFIX-GAP + INV-237-067.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameAdvanceModule.sol:1739 | `coinflip.processCoinflipPayouts(bonusFlip, derivedWord, gapDay)` — coinflip consumes derived entropy | consumption |

**KI Cross-Ref:** N/A

### INV-237-069 — _backfillOrphanedLootboxIndices (gap-backfill)

**Consumption site:** contracts/modules/DegenerusGameAdvanceModule.sol:1760
**Path family:** gap-backfill
**Upstream:** PREFIX-GAP — called alongside `_backfillGapDays` at rngGate:1155.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameAdvanceModule.sol:1751-1770 | `_backfillOrphanedLootboxIndices(vrfWord)` scans orphaned indices backwards | direct-call |
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:1759-1761 | `fallbackWord = keccak(abi.encodePacked(vrfWord, i))` orphaned-index fallback | library-call (keccak) |
| 10 | contracts/modules/DegenerusGameAdvanceModule.sol:1763 | `lootboxRngWordByIndex[i] = fallbackWord;` SSTORE | consumption |

**KI Cross-Ref:** N/A

### INV-237-070 — runDecimatorJackpot (daily)

**Consumption site:** contracts/modules/DegenerusGameDecimatorModule.sol:228
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-042 self-call (rngWord passed).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameDecimatorModule.sol:228 | Per-denom `_decWinningSubbucket(entropy, denom)` call | consumption |

**KI Cross-Ref:** N/A

### INV-237-071 — _decWinningSubbucket (library-wrapper helper) (other / library-wrapper)

**Consumption site:** contracts/modules/DegenerusGameDecimatorModule.sol:427
**Path family:** other (library-wrapper)
**Upstream:** per-caller (INV-237-070 daily caller, INV-237-072 gameover caller).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| N | contracts/modules/DegenerusGameDecimatorModule.sol:427 | `keccak(entropy, denom) % denom` — wraps caller entropy into bucket index | consumption |

**KI Cross-Ref:** N/A

### INV-237-072 — runTerminalDecimatorJackpot (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameDecimatorModule.sol:773
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER + `handleGameOverDrain` (INV-237-078) → self-call.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameGameOverModule.sol:162 | `handleGameOverDrain` invokes `runTerminalDecimatorJackpot` passing `rngWord` (INV-237-078) | direct-call |
| 11 | contracts/modules/DegenerusGameDecimatorModule.sol:773 | Per-denom `_decWinningSubbucket(entropy, denom)` at GAMEOVER using gameover rngWord | consumption |

**KI Cross-Ref:** N/A

### INV-237-073 — _placeFullTicketBetCore (gate) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameDegeneretteModule.sol:430
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY through step 6 (lootboxRngWordByIndex[index] state — empty or filled).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameDegeneretteModule.sol:430 | SLOAD `lootboxRngWordByIndex[index]` — gate: reverts RngNotReady when non-zero (ensures bet placed during pending window — opposite polarity from INV-237-021's gate) | consumption (storage-sload gate) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-074 — _resolveFullTicketBet (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameDegeneretteModule.sol:574
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY through step 7.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameDegeneretteModule.sol:574 | SLOAD `lootboxRngWordByIndex[index]` for bet resolution (gated by index-advance, not rngLockedFlag) | consumption (storage-sload) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-075 — _resolveFullTicketBet (spin 0) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameDegeneretteModule.sol:595
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-074.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameDegeneretteModule.sol:595 | `keccak(rngWord, index, QUICK_PLAY_SALT)` spin-0 seed | consumption |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-076 — _resolveFullTicketBet (spin N>0) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameDegeneretteModule.sol:598-605
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-074.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameDegeneretteModule.sol:598-605 | Per-spin `keccak(rngWord, index, spinIdx, QUICK_PLAY_SALT)` chain | consumption |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-077 — handleGameOverDrain (rngWord SLOAD) (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameGameOverModule.sol:97
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER through step 7 + :8 (rngWordByDay[day] recorded).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameGameOverModule.sol:97 | SLOAD `rngWordByDay[day]` — reverts if zero; seeds terminal decimator + terminal jackpot | consumption (storage-sload) |

**KI Cross-Ref:** N/A

### INV-237-078 — handleGameOverDrain (terminal decimator) (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameGameOverModule.sol:162
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER + INV-237-077.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameGameOverModule.sol:162 | `runTerminalDecimatorJackpot(..., rngWord, ...)` passes rngWord (10% of remaining funds) | consumption |

**KI Cross-Ref:** N/A

### INV-237-079 — handleGameOverDrain (terminal jackpot) (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameGameOverModule.sol:175
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER + INV-237-077.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameGameOverModule.sol:175 | `runTerminalJackpot(..., rngWord, ...)` passes rngWord (Day-5 style bucket distribution) | consumption |

**KI Cross-Ref:** N/A

### INV-237-080 — runTerminalJackpot (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:277
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER + INV-237-079 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:277 | `EntropyLib.hash2(rngWord, targetLvl)` — library call: `hash2(uint256, uint256) → uint256` signature inside EntropyLib | library-call |
| 12 | contracts/libraries/EntropyLib.sol | `hash2(uint256 a, uint256 b) → uint256` returns `keccak256(abi.encode(a, b))` | consumption |

**KI Cross-Ref:** N/A

### INV-237-081 — runTerminalJackpot (_rollWinningTraits) (gameover-entropy)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:276
**Path family:** gameover-entropy
**Upstream:** PREFIX-GAMEOVER + INV-237-079 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:276 | `_rollWinningTraits(rngWord, false)` — library-wrapper call (see INV-237-122 for body) | direct-call |
| 12 | contracts/modules/DegenerusGameJackpotModule.sol:1864+ | `_rollWinningTraits` body — 4-trait packing | consumption |

**KI Cross-Ref:** N/A

### INV-237-082 — payDailyJackpot (jackpot phase main _rollWinningTraits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:343
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-035/037 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:343 | `_rollWinningTraits(randWord, false)` jackpot-phase main traits | consumption |

**KI Cross-Ref:** N/A

### INV-237-083 — payDailyJackpot (source-level offset) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:408-415
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller (INV-237-030/035/037).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:408-415 | `keccak(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter) % DAILY_CARRYOVER_MAX_OFFSET + 1` — source-level offset | consumption |

**KI Cross-Ref:** N/A

### INV-237-084 — payDailyJackpot (jackpot phase entropyDaily) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:443
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:443 | `EntropyLib.hash2(randWord, lvl)` entropyDaily seed | library-call |
| 10 | contracts/libraries/EntropyLib.sol | `hash2` returns keccak256(abi.encode(a, b)) | consumption |

**KI Cross-Ref:** N/A

### INV-237-085 — payDailyJackpot (solo bucket index) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:478
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-084 entropyDaily.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:478 | `uint8(entropyDaily & 3)` — solo-bucket rotation for shareBpsByBucket | consumption |

**KI Cross-Ref:** N/A

### INV-237-086 — payDailyJackpot (jackpot phase bonus traits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:507
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:507 | `_rollWinningTraits(randWord, true)` for DailyWinningTraits event emission | consumption |

**KI Cross-Ref:** N/A

### INV-237-087 — payDailyJackpot (bonus target level) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:508-509
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:508-509 | `coinEntropy = keccak(randWord, lvl, COIN_JACKPOT_TAG)` → `bonusTargetLevel = lvl + 1 + coinEntropy % 4` | consumption |

**KI Cross-Ref:** N/A

### INV-237-088 — payDailyJackpot (purchase phase _rollWinningTraits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:518
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:518 | `_rollWinningTraits(randWord, false)` purchase-phase winning traits | consumption |

**KI Cross-Ref:** N/A

### INV-237-089 — payDailyJackpot (purchase phase bonus traits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:521
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:521 | `_rollWinningTraits(randWord, true)` purchase-phase bonus traits event | consumption |

**KI Cross-Ref:** N/A

### INV-237-090 — payDailyJackpot (purchase phase bonus target level) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:522-523
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:522-523 | `keccak(randWord, lvl, COIN_JACKPOT_TAG)` → purchase-phase bonusTargetLevel | consumption |

**KI Cross-Ref:** N/A

### INV-237-091 — payDailyJackpot (purchase phase _executeJackpot entropy) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:544
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:544 | `EntropyLib.hash2(randWord, lvl)` entropy inside JackpotParams struct | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-092 — payDailyJackpot (_distributeLootboxAndTickets rngWord passthrough) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:562
**Path family:** daily
**Upstream:** PREFIX-DAILY + caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:562 | Passes rngWord to `_distributeLootboxAndTickets` helper (consumed at INV-237-100) | consumption (passthrough) |

**KI Cross-Ref:** N/A

### INV-237-093 — payDailyJackpotCoinAndTickets (Phase 2 trait rolls) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:592-593
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-036 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:592-593 | `_rollWinningTraits(randWord, false)` main + `_rollWinningTraits(randWord, true)` bonus for Phase 2 split | consumption |

**KI Cross-Ref:** N/A

### INV-237-094 — payDailyJackpotCoinAndTickets (entropyDaily) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:594
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-036 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:594 | `EntropyLib.hash2(randWord, lvl)` entropyDaily for Phase 2 | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-095 — payDailyJackpotCoinAndTickets (entropyNext) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:596
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-036 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:596 | `EntropyLib.hash2(randWord, sourceLevel)` entropyNext for Phase 2 carryover | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-096 — payDailyJackpotCoinAndTickets (near-future coin) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:607-610
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-036 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:607-610 | `keccak(randWord, lvl, COIN_JACKPOT_TAG)` coinEntropy → `lvl + 1 + coinEntropy % 4` near-future targetLevel | consumption |

**KI Cross-Ref:** N/A

### INV-237-097 — _runEarlyBirdLootboxJackpot (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:677
**Path family:** daily
**Upstream:** PREFIX-DAILY + `_consolidatePoolsAndRewardJackpots` caller chain (early-bird triggered during pool-consolidation).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:677 | `_rollWinningTraits(rngWord, true)` bonus traits for early-bird | consumption |

**KI Cross-Ref:** N/A

### INV-237-098 — _runEarlyBirdLootboxJackpot (_randTraitTicket call) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:686
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-097 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:686 | `_randTraitTicket(...)` per-trait using rngWord as randomWord | consumption (library-wrapper per INV-237-110) |

**KI Cross-Ref:** N/A

### INV-237-099 — distributeYieldSurplus (_addClaimableEth entropy passthrough) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:736-746
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-032 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:736-746 | 3× `_addClaimableEth(VAULT/SDGNRS/GNRUS, amount, rngWord, ...)` auto-rebuy entropy driver | consumption |
| 10 | contracts/modules/DegenerusGamePayoutUtils.sol:68 | Downstream consumed at INV-237-146 (`_calcAutoRebuy`) | consumption |

**KI Cross-Ref:** N/A

### INV-237-100 — _distributeLootboxAndTickets (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:874
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-092 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:874 | `EntropyLib.hash2(randWord, lvl)` entropy for ticket-jackpot distribution | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-101 — _distributeTicketsToBuckets (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:937
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-100 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:937 | `keccak(entropy, traitIdx, ticketUnits)` per-trait entropy rotation | consumption |

**KI Cross-Ref:** N/A

### INV-237-102 — _executeJackpot (solo bucket shares) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1087
**Path family:** daily
**Upstream:** PREFIX-DAILY + payDailyJackpot execution chain (INV-237-091 entropy into JackpotParams).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1087 | `uint8(jp.entropy & 3)` solo-bucket rotation | consumption |

**KI Cross-Ref:** N/A

### INV-237-103 — _runJackpotEthFlow (offset) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1102
**Path family:** daily
**Upstream:** PREFIX-DAILY + _executeJackpot caller chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1102 | `uint8(jp.entropy & 3)` bucket-count offset rotation | consumption |

**KI Cross-Ref:** N/A

### INV-237-104 — _resumeDailyEth (entropy) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1134
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-035 resume caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1134 | `EntropyLib.hash2(randWord, lvl)` entropy for resume branch | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-105 — _resumeDailyEth (_rollWinningTraits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1139
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-035 resume caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1139 | `_rollWinningTraits(randWord, false)` trait re-roll for resume | consumption |

**KI Cross-Ref:** N/A

### INV-237-106 — _resumeDailyEth (shareBpsByBucket) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1143
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-035 resume caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:1143 | `uint8(entropy & 3)` share rotation for resume | consumption |

**KI Cross-Ref:** N/A

### INV-237-107 — _processDailyEth (remainderIdx) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1204
**Path family:** daily
**Upstream:** PREFIX-DAILY + _executeJackpot chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:1204 | `JackpotBucketLib.soloBucketIndex(entropy)` library-wrapper (% 4 on entropy) | library-call |
| 12 | contracts/libraries/JackpotBucketLib.sol | `soloBucketIndex(uint256) → uint256` signature | consumption |

**KI Cross-Ref:** N/A

### INV-237-108 — _processDailyEth (bucket entropy rotation) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1239
**Path family:** daily
**Upstream:** PREFIX-DAILY + _executeJackpot chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:1239 | `keccak(entropyState, traitIdx, share)` per-bucket entropy advance | consumption |

**KI Cross-Ref:** N/A

### INV-237-109 — _resolveTraitWinners (entropy advance) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1346
**Path family:** daily
**Upstream:** PREFIX-DAILY + _executeJackpot chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:1346 | `keccak(entropyState, traitIdx, traitShare)` entropy advance before `_randTraitTicket` | consumption |

**KI Cross-Ref:** N/A

### INV-237-110 — _randTraitTicket (winner selection) (other / library-wrapper)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1642
**Path family:** other (library-wrapper)
**Upstream:** per-caller — 5 call sites (INV-237-098 early-bird daily; L974/L1248/L1351/L1747 within _executeJackpot chain — all daily; plus gameover via INV-237-081 → runTerminalJackpot entropy chain).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| N | contracts/modules/DegenerusGameJackpotModule.sol:1642 | `keccak(randomWord, trait, salt, i) % effectiveLen` winner index | consumption |

**KI Cross-Ref:** N/A

### INV-237-111 — payDailyCoinJackpot (bonus traits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1679
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-028/031 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1679 | `_rollWinningTraits(randWord, true)` bonus traits for coin jackpot dispatch | consumption |

**KI Cross-Ref:** N/A

### INV-237-112 — payDailyCoinJackpot (entropy + target) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1681-1686
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-028/031 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1681-1686 | `keccak(randWord, lvl, COIN_JACKPOT_TAG)` entropy → `targetLevel ∈ [minLevel, maxLevel]` | consumption |

**KI Cross-Ref:** N/A

### INV-237-113 — emitDailyWinningTraits (main traits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1705
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-027 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1705 | `_rollWinningTraits(randWord, true)` main traits for L1 emission | consumption |

**KI Cross-Ref:** N/A

### INV-237-114 — emitDailyWinningTraits (salted rng) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1706
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-027 caller.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameJackpotModule.sol:1706 | `saltedRng = keccak(randWord, BONUS_TRAITS_TAG)` | consumption |

**KI Cross-Ref:** N/A

### INV-237-115 — emitDailyWinningTraits (bonus traits) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1707
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-027 caller + INV-237-114 salted seed.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1707 | `_rollWinningTraits(saltedRng, true)` bonus traits for L1 emission | consumption |

**KI Cross-Ref:** N/A

### INV-237-116 — _awardDailyCoinToTraitWinners (cursor) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1735
**Path family:** daily
**Upstream:** PREFIX-DAILY + payDailyCoinJackpot caller chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1735 | `entropy % cap` cursor anchor | consumption |

**KI Cross-Ref:** N/A

### INV-237-117 — _awardDailyCoinToTraitWinners (per-trait advance) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1741
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-116 cursor.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:1741 | `keccak(entropy, traitIdx, coinBudget)` per-trait entropy rotation | consumption |

**KI Cross-Ref:** N/A

### INV-237-118 — _awardFarFutureCoinJackpot (entropy seed) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1798-1800
**Path family:** daily
**Upstream:** PREFIX-DAILY + payDailyCoinJackpot chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1798-1800 | `keccak(rngWord, lvl, FAR_FUTURE_COIN_TAG)` entropy seed | consumption |

**KI Cross-Ref:** N/A

### INV-237-119 — _awardFarFutureCoinJackpot (per-sample advance) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1808
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-118 seed.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:1808 | `EntropyLib.hash2(entropy, s)` per-sample advance across 10 far-future candidates | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-120 — _awardFarFutureCoinJackpot (level pick) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1811
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-119 advance.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 12 | contracts/modules/DegenerusGameJackpotModule.sol:1811 | `entropy % 95` far-future candidate level | consumption |

**KI Cross-Ref:** N/A

### INV-237-121 — _awardFarFutureCoinJackpot (ticket pick) (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1817
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-119 advance.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 12 | contracts/modules/DegenerusGameJackpotModule.sol:1817 | `(entropy >> 32) % len` per-level winner index within ticketQueue | consumption |

**KI Cross-Ref:** N/A

### INV-237-122 — _rollWinningTraits (bonus salted path) (other / library-wrapper)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1870
**Path family:** other (library-wrapper)
**Upstream:** per-caller — 6 call sites spanning daily + jackpot-phase + gameover (via runTerminalJackpot INV-237-081).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| N | contracts/modules/DegenerusGameJackpotModule.sol:1870 | `keccak(randWord, BONUS_TRAITS_TAG)` bonus-domain salted variant | consumption |

**KI Cross-Ref:** N/A

### INV-237-123 — _dailyCurrentPoolBps (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:1894-1898
**Path family:** daily
**Upstream:** PREFIX-DAILY + payDailyJackpot caller chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameJackpotModule.sol:1894-1898 | `keccak(randWord, DAILY_CURRENT_BPS_TAG, counter) % range` — daily-pool bps roll 6-14% | consumption |

**KI Cross-Ref:** N/A

### INV-237-124 — _jackpotTicketRoll (daily)

**Consumption site:** contracts/modules/DegenerusGameJackpotModule.sol:2119
**Path family:** daily
**Upstream:** PREFIX-DAILY + _executeJackpot chain (small/medium lootbox ticket target-level roll).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameJackpotModule.sol:2119 | `EntropyLib.entropyStep(entropy)` library-call: `entropyStep(uint256 state) → uint256` XOR-shift PRNG step (KI exception — seeded per keccak) | library-call / ki-exception |
| 12 | contracts/libraries/EntropyLib.sol | `entropyStep` XOR-shift body returns advanced state | consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-125 — openLootBox (SLOAD rngWord) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:533
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY through step 6.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameLootboxModule.sol:533 | SLOAD `lootboxRngWordByIndex[index]` at ETH lootbox open (gated by index-advance, not rngLockedFlag) | consumption (storage-sload) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-126 — openLootBox (entropy derivation) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:554
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-125.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameLootboxModule.sol:554 | `keccak(rngWord, player, day, amount)` entropy seeds `_rollTargetLevel` + downstream | consumption |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-127 — openBurnieLootBox (SLOAD rngWord) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:611
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY through step 6.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameLootboxModule.sol:611 | SLOAD `lootboxRngWordByIndex[index]` at BURNIE lootbox open | consumption (storage-sload) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-128 — openBurnieLootBox (entropy derivation) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:628
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-127.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameLootboxModule.sol:628 | `keccak(rngWord, player, day, amountEth)` entropy seeds `_rollTargetLevel` + downstream | consumption |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-129 — resolveLootboxDirect (entropy derivation) (other / library-wrapper)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:673
**Path family:** other (library-wrapper)
**Upstream:** per-caller — daily callers (sDGNRS redemption INV-237-010/INV-237-020) and gameover callers (DecimatorModule `_awardDecimatorLootbox` via runTerminalDecimatorJackpot chain).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| N | contracts/modules/DegenerusGameLootboxModule.sol:673 | `keccak(rngWord, player, day, amount)` entropy derivation (shared helper) | consumption |

**KI Cross-Ref:** N/A

### INV-237-130 — resolveRedemptionLootbox (entropy derivation) (daily)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:708
**Path family:** daily
**Upstream:** PREFIX-DAILY + `sDGNRS.claimRedemption` chain (INV-237-020).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:708 | `keccak(rngWord, player, day, amount)` from sDGNRS claimRedemption flow | consumption |

**KI Cross-Ref:** N/A

### INV-237-131 — _rollTargetLevel (first entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:813
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + openLootBox entropy chain (INV-237-126 / INV-237-128 / INV-237-129).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:813 | `EntropyLib.entropyStep(entropy)` initial XOR-shift step (KI exception) | library-call / ki-exception |
| 10 | contracts/libraries/EntropyLib.sol | `entropyStep(uint256)` XOR-shift body | consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-132 — _rollTargetLevel (far-future entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:817
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-131.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 11 | contracts/modules/DegenerusGameLootboxModule.sol:817 | `EntropyLib.entropyStep(levelEntropy)` far-future XOR-shift step (KI exception) | library-call / ki-exception → consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-133 — _rollLootboxBoons (roll) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1059
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + lootbox-open chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:1059 | `entropy % BOON_PPM_SCALE` roll determines boon awarding | consumption |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-134 — _resolveLootboxRoll (entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1548
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + lootbox-open chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:1548 | `EntropyLib.entropyStep(entropy)` + `nextEntropy % 20` reward-tier roll | library-call / ki-exception → consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-135 — _resolveLootboxRoll (DGNRS entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1569
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-134.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameLootboxModule.sol:1569 | `EntropyLib.entropyStep(nextEntropy)` DGNRS-tier sub-roll | library-call / ki-exception → consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-136 — _resolveLootboxRoll (WWXRP entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1585
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-134.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameLootboxModule.sol:1585 | `EntropyLib.entropyStep(nextEntropy)` WWXRP-tier sub-roll | library-call / ki-exception → consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-137 — _resolveLootboxRoll (large BURNIE entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1599-1600
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + INV-237-134.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameLootboxModule.sol:1599-1600 | `EntropyLib.entropyStep(nextEntropy)` + `nextEntropy % 20` varianceRoll for large-BURNIE tier | library-call / ki-exception → consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-138 — _lootboxTicketCount (entropyStep) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1635-1636
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + lootbox-open chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:1635-1636 | `EntropyLib.entropyStep(entropy)` + `varianceRoll % 10_000` ticket-count tier | library-call / ki-exception → consumption |

**KI Cross-Ref:** [KI: "EntropyLib XOR-shift PRNG for lootbox outcome rolls"]

### INV-237-139 — _lootboxDgnrsReward (tier selection) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1680
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY + lootbox-open chain.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:1680 | `entropy % 1000` tier-roll for DGNRS reward amount | consumption |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-140 — deityBoonSlots (rngWord gate view) (daily)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:746
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 7.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameLootboxModule.sol:746 | SLOAD `rngWordByDay[day] != 0` gate (view) | consumption (storage-sload gate) |

**KI Cross-Ref:** N/A

### INV-237-141 — issueDeityBoon (rngWord gate) (daily)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:778
**Path family:** daily
**Upstream:** PREFIX-DAILY through step 7.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 8 | contracts/modules/DegenerusGameLootboxModule.sol:778 | SLOAD `rngWordByDay[day] != 0` gate before issuing boon | consumption (storage-sload gate) |

**KI Cross-Ref:** N/A

### INV-237-142 — _deityBoonForSlot (daily)

**Consumption site:** contracts/modules/DegenerusGameLootboxModule.sol:1753
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-141 issuance.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameLootboxModule.sol:1753 | `keccak(rngWordByDay[day], deity, day, slot)` boon-type derivation seed | consumption |

**KI Cross-Ref:** N/A

### INV-237-143 — _raritySymbolBatch (daily)

**Consumption site:** contracts/modules/DegenerusGameMintModule.sol:568
**Path family:** daily
**Upstream:** PREFIX-DAILY + INV-237-025 (FF drain) / INV-237-026 (near-future prep) caller chain via `processFutureTicketBatch` delegatecall (IM-13 boundary). Dual-trigger note from Classification: `_processOneTicketEntry` mid-day-lootbox read-slot ticket processing is a sibling trigger context (Phase 238 BWD will bifurcate if needed).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 9 | contracts/modules/DegenerusGameAdvanceModule.sol:1390-1394 | `delegatecall(abi.encodeWithSelector(IDegenerusGameMintModule.processFutureTicketBatch.selector, lvl, entropy))` (IM-13 boundary) | delegatecall |
| 10 | contracts/modules/DegenerusGameMintModule.sol:568 | `keccak(baseKey, entropyWord, groupIdx)` seed for LCG trait generation | consumption |

**KI Cross-Ref:** N/A

### INV-237-144 — _rollRemainder (daily)

**Consumption site:** contracts/modules/DegenerusGameMintModule.sol:652
**Path family:** daily
**Upstream:** PREFIX-DAILY + same IM-13 delegatecall boundary as INV-237-143. Dual-trigger note same as INV-237-143.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 10 | contracts/modules/DegenerusGameMintModule.sol:652 | `EntropyLib.hash2(entropy, rollSalt)` per-ticket fractional remainder roll | library-call → consumption |

**KI Cross-Ref:** N/A

### INV-237-145 — processTicketBatch (entropy SLOAD) (mid-day-lootbox)

**Consumption site:** contracts/modules/DegenerusGameMintModule.sol:690
**Path family:** mid-day-lootbox
**Upstream:** PREFIX-MIDDAY through step 6.

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| 7 | contracts/modules/DegenerusGameMintModule.sol:690 | SLOAD `lootboxRngWordByIndex[index-1]` — seeds current-level ticket rarity + remainder rolls (gated by index-advance, not rngLockedFlag) | consumption (storage-sload) |

**KI Cross-Ref:** [KI: "Lootbox RNG uses index advance isolation instead of rngLockedFlag"]

### INV-237-146 — _calcAutoRebuy (other / library-wrapper)

**Consumption site:** contracts/modules/DegenerusGamePayoutUtils.sol:68
**Path family:** other (library-wrapper)
**Upstream:** per-caller — multiple `_addClaimableEth` callers (primarily daily via INV-237-099 yieldSurplus chain).

| Step | File:Line | Site | Hop Type |
|---|---|---|---|
| N | contracts/modules/DegenerusGamePayoutUtils.sol:68 | `keccak(entropy, beneficiary, weiAmount) & 3` level-offset 1-4 for auto-rebuy | consumption |

**KI Cross-Ref:** N/A

## Finding Candidates

Per D-15. Anomalies surfaced during call-graph construction. No finding IDs emitted — Phase 242 owns ID assignment.

- contracts/modules/DegenerusGameAdvanceModule.sol:1390-1394 — `_processFutureTicketBatch` delegatecall boundary (IM-13) — MintModule.processFutureTicketBatch receiver consumers (INV-237-143 / INV-237-144) are classified `daily` at HEAD but carry a dual-trigger note (mid-day-lootbox sibling context via `_processOneTicketEntry` read-slot path). Call-graph construction confirmed the two trigger contexts share the same MintModule consumer body but receive different entropy sources (`rngWordCurrent` vs `lootboxRngWordByIndex[idx]`). Recommend Phase 238 BWD emit two distinct proof rows for each of INV-237-143 and INV-237-144 to cover both triggers — suggested severity: INFO
- contracts/modules/DegenerusGameLootboxModule.sol:673 — `resolveLootboxDirect` (INV-237-129) is a library-wrapper with both a daily caller (sDGNRS redemption via INV-237-010/-020) and a gameover caller (DecimatorModule `_awardDecimatorLootbox` via runTerminalDecimatorJackpot INV-237-072/-078 chain). Universe List did NOT emit a separate `gameover-entropy` row for the decimator-award caller context (absorbed via INV-237-078). Call-graph construction confirmed the plumbing is complete but would benefit from an explicit Phase 238 BWD marker that `resolveLootboxDirect` sees the gameover rngWord via the decimator-winner lootbox award path — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:1301-1325 — `_getHistoricalRngFallback` prevrandao-mix cluster (INV-237-060..062) — the graph terminates at the prevrandao SHA3-mix at :1322; subsequent SLOAD of `rngWordByDay[searchDay]` at :1308 is itself a consumption of an already-committed VRF word (prior day's fulfilled rngWord). That is recursion-free but creates a consumer-of-consumer citation cross-reference for Phase 241 EXC-02. Recommend Phase 241 EXC-02 explicitly note that fallback entropy is a deterministic function of (committed historical words × block.prevrandao × currentDay) rather than present as a single monolithic prevrandao-mix — suggested severity: INFO
- contracts/modules/DegenerusGameJackpotModule.sol:2119 — `_jackpotTicketRoll` (INV-237-124) is the sole `daily`-family row carrying the `EntropyLib XOR-shift PRNG` KI Cross-Ref. All other EntropyLib.entropyStep caller rows (INV-237-131, -132, -134..138) are `mid-day-lootbox`. Phase 241 EXC-04 proof subject set therefore spans BOTH families — the KI title ("for lootbox outcome rolls") under-describes the actual consumer surface. Call-graph construction confirms the EntropyLib XOR-shift PRNG caller universe is exactly 8 rows (1 daily + 7 mid-day-lootbox) — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:1082 / :292 — F-29-04 write-buffer-swap sites (INV-237-024 `_swapAndFreeze` daily path; INV-237-045 `_swapTicketSlot` mid-day path) — call-graph construction confirms both swap sites sit BEFORE the VRF request origination in their respective prefix chains (PREFIX-DAILY step 3 / PREFIX-MIDDAY step 3). The "substitution" occurs because tickets routed into the frozen write buffer eventually drain under a different word (gameover or mid-day). Recommend Phase 241 EXC-03 proof of liveness that no alternative substitution path exists — suggested severity: INFO

## Scope-Guard Deferrals

None surfaced during call-graph construction.

Zero gaps in 237-01 or 237-02 outputs discovered. All 146 Row IDs have complete upstream/downstream anchors. Dual-trigger observations for INV-237-143 / -144 / -129 recorded under Finding Candidates above (NOT as scope-guard deferrals per D-16 — the observations are downstream-handoff guidance for Phase 238 BWD, not gaps in 237-01 or 237-02 themselves).

## Downstream Hand-offs

- **Task 3 of this plan:** merges this file + `audit/v30-237-01-UNIVERSE.md` + `audit/v30-237-02-CLASSIFICATION.md` → `audit/v30-CONSUMER-INVENTORY.md` with full Consumer Index per D-08/D-10.
- **Phase 238 BWD/FWD:** every backward-trace / forward-enumeration proof cites an INV-237-NNN Row ID as its scope anchor. BWD-01 specifically uses the intermediate storage-touchpoint lists in each shared prefix (PREFIX-DAILY step 4 / PREFIX-MIDDAY step 4 vrfRequestId + rngLockedFlag + lootbox-index commitments).
- **Phase 239 RNG-02:** permissionless-sweep classification uses call graphs to identify which permissionless functions touch any step on any RNG-consumer chain. `requestLootboxRng` at AdvanceModule:1030 is the canonical permissionless VRF-request entry.
- **Phase 239 RNG-03:** index-advance isolation re-justification uses the 13 mid-day-lootbox family rows plus INV-237-066 fulfillment-callback row.
- **Phase 240 GO-01:** gameover-entropy call graphs become GO-01's consumer inventory — specifically the gameover-shared-prefix branching (PREFIX-GAMEOVER 3a vs PREFIX-PREVRANDAO fallback branch).
- **Phase 241 EXC-02:** prevrandao-fallback call graph (PREFIX-PREVRANDAO + INV-237-055..062) becomes EXC-02's proof subject.
- **Phase 241 EXC-04:** `EntropyLib.entropyStep()` caller graphs (INV-237-124, -131, -132, -134..138) become EXC-04's proof subject.

## Attestation

- Audit baseline HEAD: `7ab515fe`
- `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` returned empty at task start and end
- `git status --porcelain contracts/ test/` returned empty before and after this task
- Input file `audit/v30-237-01-UNIVERSE.md` was present and committed before this task started (commit: `20ed1c75`)
- Input file `audit/v30-237-02-CLASSIFICATION.md` was present and committed before this task started (commit: `f142adaf`)
- Input Row ID integrity: this file contains a Per-Consumer Call Graphs entry for every one of the 146 INV-237-NNN Row IDs in 237-01 (row count match: `grep -Eo 'INV-237-[0-9]{3}' audit/v30-237-01-UNIVERSE.md | sort -u | wc -l` = 146; `grep -cE '^### INV-237-[0-9]{3}' audit/v30-237-03-CALLGRAPH.md` = 146)
- Companion files created (if any): None — all graphs inline via aggressive shared-prefix deduplication (per D-12, companion files are planner's discretion; inline was chosen because every per-consumer tail is typically 1-3 rows when prefixed with shared PREFIX-DAILY/MIDDAY/GAMEOVER/PREVRANDAO/AFFILIATE/GAP notes).
- Contract source reads limited to `contracts/**/*.sol` at HEAD `7ab515fe`
- `audit/v30-237-01-UNIVERSE.md` and `audit/v30-237-02-CLASSIFICATION.md` NOT modified by this task (per D-16)
- Zero finding IDs emitted in the Phase-242 namespace (per D-15 — Phase 242 FIND-01..03 owns ID assignment)
- Zero mermaid code fences emitted (per D-09 tabular-only)
- Zero placeholder tokens remain in the committed file
