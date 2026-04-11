# rngLocked Mutual Exclusion Verification + Phase 215 Synthesis (RNG-05)

**Audit date:** 2026-04-11
**Source:** contracts at current HEAD
**Methodology:** Exhaustive enumeration of every rngLockedFlag reference, coverage analysis of every external/public function, plus cross-reference synthesis of plans 01-04.

---

## Part A: rngLocked Mutual Exclusion Verification

### Section 1: rngLockedFlag Lifecycle

The `rngLockedFlag` is declared at DegenerusGameStorage.sol line 279 as `bool internal rngLockedFlag`. Its NatSpec (lines 275-278) states: "True when daily RNG is locked (jackpot resolution in progress). Set when daily VRF is requested, cleared when daily processing completes. Mid-day lootbox RNG does NOT set this flag."

**SET (1 site):**

| Action | File | Line | Context |
|--------|------|------|---------|
| `rngLockedFlag = true` | DegenerusGameAdvanceModule.sol | 1442 | Inside `_finalizeRngRequest()`, called from `_requestRng()` at line 1399. Fires when daily VRF request is sent to Chainlink coordinator. |

**CLEAR (3 sites):**

| Action | File | Line | Context |
|--------|------|------|---------|
| `rngLockedFlag = false` | DegenerusGameAdvanceModule.sol | 1515 | Inside `_unlockRng(day)`. Called after daily processing completes -- after `payDailyJackpot`, `_payDailyCoinJackpot`, coinflip resolution, and all daily housekeeping. Normal daily unlock path. |
| `rngLockedFlag = false` | DegenerusGameAdvanceModule.sol | 1492 | Inside `updateVrfCoordinatorAndSub()`. Emergency admin function (line 1484: `msg.sender != ContractAddresses.ADMIN` check) to rotate VRF coordinator when Chainlink stalls. Clears the lock to allow game to continue after coordinator swap. |
| Implicit clear via gameover | N/A | N/A | `_handleGameOverPath()` calls `_unlockRng(day)` at AdvanceModule line 524 after gameover drain completes. Same `_unlockRng` as the normal path (line 1515). |

**BRANCH (1 site):**

| Action | File | Line | Context |
|--------|------|------|---------|
| `if (rngLockedFlag)` | DegenerusGameAdvanceModule.sol | 1540 | Inside `rawFulfillRandomWords()`. When `true`: daily path -- stores word to `rngWordCurrent` (line 1542). When `false`: mid-day lootbox path -- stores word directly to `lootboxRngWordByIndex[index]` (line 1546) and clears `vrfRequestId`/`rngRequestTime`. |

**Lifecycle summary:**
1. Lock SET at daily VRF request (line 1442)
2. VRF callback stores word to staging (`rngWordCurrent`, line 1542) -- flag remains true
3. Next `advanceGame()` call enters `rngGate()`, processes daily RNG, runs all jackpot/coinflip/redemption/lootbox finalization
4. Lock CLEARED by `_unlockRng()` (line 1515) after all daily processing completes
5. Emergency CLEAR via admin `updateVrfCoordinatorAndSub()` (line 1492) when VRF coordinator is dead

**Edge case: rawFulfillRandomWords called when rngLockedFlag is already false**
This is the mid-day lootbox path (line 1543-1550). When `rngLockedFlag == false`, the VRF callback stores the word directly to `lootboxRngWordByIndex[index]` and clears `vrfRequestId`/`rngRequestTime`. This is the intended behavior for mid-day lootbox RNG requests issued by `requestLootboxRng()`.

**Edge case: _requestRng fails after setting rngLockedFlag = true**
Impossible. `_requestRng()` (line 1386) calls `vrfCoordinator.requestRandomWords()` FIRST (line 1388-1398), then calls `_finalizeRngRequest()` (line 1399) which sets `rngLockedFlag = true` at line 1442. If the VRF coordinator call reverts, the entire transaction reverts -- the flag is never set. The NatSpec at line 1387 confirms: hard revert is intentional to halt game progress.

**Edge case: stale/duplicate VRF callback**
The `rawFulfillRandomWords` callback at line 1535 checks `requestId != vrfRequestId || rngWordCurrent != 0` and silently returns if either is true. This prevents stale callbacks from overwriting a delivered word and prevents duplicate callbacks from having any effect.

---

### Section 2: Guard Site Catalogue

Every site in the codebase where `rngLockedFlag` is read:

| # | File | Line | Function | Guard Pattern | Effect |
|---|------|------|----------|---------------|--------|
| 1 | DegenerusGameStorage.sol | 566 | `_queueTickets()` | `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()` | Blocks far-future ticket queue writes (targetLevel > level + 5) during daily VRF window. Near-future tickets (within +5) are unblocked. |
| 2 | DegenerusGameStorage.sol | 596 | `_queueTicketsScaled()` | `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()` | Same as #1 for scaled (fractional) ticket queue writes. |
| 3 | DegenerusGameStorage.sol | 650 | `_queueTicketRange()` | `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()` | Same as #1 for range-based ticket queuing (whale bundles, whale passes). Checked per-level in loop. |
| 4 | DegenerusGame.sol | 1480 | `_setAutoRebuy()` | `if (rngLockedFlag) revert RngLocked()` | Blocks auto-rebuy toggle. Prevents changing rebuy state during jackpot resolution (rebuy affects next payout distribution). |
| 5 | DegenerusGame.sol | 1495 | `_setAutoRebuyTakeProfit()` | `if (rngLockedFlag) revert RngLocked()` | Blocks take-profit config change. Prevents changing payout reservation during jackpot resolution. |
| 6 | DegenerusGame.sol | 1542 | `_setAfKingMode()` | `if (rngLockedFlag) revert RngLocked()` | Blocks afKing mode toggle (combined rebuy + lazy pass mode). |
| 7 | DegenerusGame.sol | 1882 | `reverseFlip()` | `if (rngLockedFlag) revert RngLocked()` | Blocks RNG nudge (BURNIE burn to add +1 to VRF word). Prevents nudging AFTER the VRF request is in-flight (and potentially after seeing the fulfillment tx in mempool). |
| 8 | DegenerusGameWhaleModule.sol | 543 | `_purchaseDeityPass()` | `if (rngLockedFlag) revert RngLocked()` | Blocks deity pass purchase during daily VRF window. Prevents acquiring deity status that could affect jackpot resolution. |
| 9 | DegenerusGameAdvanceModule.sol | 908 | `requestLootboxRng()` | `if (rngLockedFlag) revert RngLocked()` | Blocks mid-day lootbox VRF request during daily VRF window. Prevents overlapping VRF requests. |

**Non-revert rngLockedFlag references:**

| # | File | Line | Function | Pattern | Effect |
|---|------|------|----------|---------|--------|
| 10 | DegenerusGameMintModule.sol | 1231 | `_callTicketPurchase()` | `if (cachedJpFlag && rngLockedFlag)` | Routing adjustment: on last jackpot day with rngLocked, redirects ticket purchases to `level + step` instead of current level. Prevents stranded tickets at a level that will not have another daily draw. NOT a revert guard -- a routing decision. |
| 11 | DegenerusGameAdvanceModule.sol | 177 | `advanceGame()` | `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1` | Purchase level calculation: when `lastPurchaseDay == true` and rngLocked, uses `lvl` instead of `lvl + 1` because the level was already incremented at VRF request time (line 1451). NOT a revert guard -- a level correction. |
| 12 | DegenerusGameAdvanceModule.sol | 1540 | `rawFulfillRandomWords()` | `if (rngLockedFlag)` | Branch selector: `true` -> daily path (store to rngWordCurrent). `false` -> mid-day lootbox path (store to lootboxRngWordByIndex). NOT a guard -- routing logic. |
| 13 | DegenerusGameAdvanceModule.sol | 1442 | `_finalizeRngRequest()` | `rngLockedFlag = true` | SET site. |
| 14 | DegenerusGameAdvanceModule.sol | 1492 | `updateVrfCoordinatorAndSub()` | `rngLockedFlag = false` | CLEAR site (admin emergency). |
| 15 | DegenerusGameAdvanceModule.sol | 1515 | `_unlockRng()` | `rngLockedFlag = false` | CLEAR site (normal daily processing). |
| 16 | DegenerusGame.sol | 2136 | `rngLocked()` | `return rngLockedFlag` | View function (read-only). |
| 17 | DegenerusGame.sol | 2194 | `purchaseInfo()` | `rngLocked_ = rngLockedFlag` | View function (read-only). |

**Modules with ZERO rngLockedFlag references:**
- DegenerusGameJackpotModule.sol -- no references
- DegenerusGameDegeneretteModule.sol -- no references
- DegenerusGameLootboxModule.sol -- no references
- DegenerusGameGameOverModule.sol -- no references
- DegenerusGameDecimatorModule.sol -- no references

These modules execute via delegatecall during daily processing (when rngLockedFlag is true). They are internal to the processing pipeline and do not need guards because they are invoked by `advanceGame()` or self-call, not by external user transactions.

---

### Section 2a: rngBypass Analysis

The Storage guards at lines 566, 596, and 650 use the three-term condition `isFarFuture && rngLockedFlag && !rngBypass`. The `rngBypass` parameter is a `bool` passed to `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`, and `_queueLootboxTickets`.

**Who passes rngBypass = true (bypass the guard)?**

| Caller | File | Line | Context |
|--------|------|------|---------|
| `_processPhaseTransition()` | AdvanceModule | 1347, 1353 | Vault perpetual tickets (sDGNRS + VAULT, 16 tickets each at level + 99). Called during jackpot-to-purchase phase transition inside `advanceGame()`. Internal protocol operation. |
| `_executeAutoRebuy()` | JackpotModule | 821 | Jackpot winner auto-rebuy ticket queuing. Called during `payDailyJackpot` -> `_processDailyEth` -> `_executeAutoRebuy`. Internal jackpot processing. |
| `_awardWinnersTickets()` | JackpotModule | 991 | Direct ticket awards to jackpot winners. Called during `payDailyJackpot` -> `_processDailyEth` -> `_awardWinnersTickets`. Internal jackpot processing. |
| `_resolveLootboxRoll()` | JackpotModule | 2154 | Lootbox ticket awards to winners. Called during lootbox resolution. Internal resolution processing. |

**Who passes rngBypass = false (subject to the guard)?**

All user-facing paths:
- `DegenerusGame.constructor()` (line 226-227): initial protocol tickets
- `DegenerusGameMintModule._callTicketPurchase()` (line 1140): player purchase tickets
- `DegenerusGameWhaleModule.purchaseWhaleBundle()` (line 313, 482, 625): whale bundle tickets
- `DegenerusGameWhaleModule.claimWhalePass()` (line 973): whale pass claim tickets
- `DegenerusGameLootboxModule._resolveLootboxRoll()` (line 974): lootbox future tickets
- `DegenerusGameLootboxModule._runEarlyBirdLootboxJackpot()` (line 1097): early-bird tickets
- `DegenerusGameDecimatorModule._executeDecimatorJackpot()` (line 560): decimator tickets
- `DegenerusGameStorage._applyWhalePassStats()` (line 1180): lazy pass tickets

**Can rngBypass be set by anyone other than admin?**

No. `rngBypass` is a function parameter, not a storage variable. It is hardcoded at each call site. Every `true` call originates from internal protocol processing (JackpotModule during daily resolution, AdvanceModule during phase transition). No external caller can influence the `rngBypass` value -- it is compiled into the bytecode at each call site.

**Trust assumption:** The rngBypass mechanism allows internal jackpot processing to queue far-future tickets while rngLockedFlag is set. This is safe because:
1. The tickets queued via bypass go to the WRITE slot (frozen read slot is processed), so they target the NEXT cycle
2. The internal callers execute within the same atomic `advanceGame()` transaction
3. No player can invoke these paths directly -- they run inside delegatecall from the Game contract during jackpot processing

---

### Section 3: Coverage Analysis

Every external/public function on DegenerusGame.sol, classified by whether it is guarded by rngLockedFlag and whether it touches RNG-affecting state.

#### State-Changing Functions: BLOCKED by rngLockedFlag

| Function | Guard Site | What is Blocked | Why it Matters |
|----------|-----------|-----------------|----------------|
| `setAutoRebuy(player, enabled)` | Game L1480 | Auto-rebuy toggle | Rebuy affects payout distribution during next jackpot |
| `setAutoRebuyTakeProfit(player, takeProfit)` | Game L1495 | Take-profit config | Take-profit reservation affects ETH distribution |
| `setAfKingMode(player, enabled, ethTP, coinTP)` | Game L1542 | Combined rebuy + lazy pass mode | Compound state change affecting payout + ticket routing |
| `reverseFlip()` | Game L1882 | RNG nudge (BURNIE burn) | Must not nudge after VRF request -- would allow reacting to pending/visible VRF fulfillment |
| `purchaseDeityPass(buyer, symbolId)` | Whale L543 | Deity pass purchase | Deity status affects jackpot distribution (deity virtual slots) |
| `requestLootboxRng()` | Advance L908 | Mid-day lootbox VRF request | Prevents overlapping VRF requests that could corrupt state |
| `purchaseWhaleBundle(buyer, quantity)` (far-future tickets) | Storage L650 | Far-future ticket range writes | Far-future tickets go to levels beyond +5, which could contaminate frozen ticket state. Near-future proceeds normally. |
| `purchase/purchaseCoin/purchaseBurnieLootbox` (far-future tickets) | Storage L566/596 | Far-future ticket queue writes | Same as above: far-future blocked, near-future allowed via write slot |

#### State-Changing Functions: NOT BLOCKED -- Does Not Affect RNG Outcomes

| Function | Rationale |
|----------|-----------|
| `advanceGame()` | The intended consumer of the VRF word. During daily window: processes tickets on mid-day path or waits for VRF word (reverts `RngNotReady()`). When word arrives, consumes it atomically. |
| `claimWinnings(player)` | Pull-pattern ETH claim. Reads `claimableWinnings[player]`, transfers ETH. Amounts already determined by prior RNG. |
| `claimWinningsStethFirst()` | Same as `claimWinnings` but stETH-priority path. |
| `claimAffiliateDgnrs(player)` | Claims DGNRS from affiliate score. Per-level affiliate data, mints DGNRS. No RNG dependency. |
| `claimDecimatorJackpot(lvl)` | Claims from decimator pool. Winning sub-bucket already determined by prior RNG. |
| `claimWhalePass(player)` | Whale pass ticket grant. Routes through `_queueTicketRange` with `rngBypass = false`. Tickets go to future levels via write slot -- does not affect current RNG cycle. |
| `openLootBox(player, index)` | Opens a lootbox using `lootboxRngWordByIndex[index]` for a PRIOR index. Word was committed before current daily window. Does not change pending RNG state. |
| `openBurnieLootBox(player, index)` | Same as `openLootBox` for BURNIE lootboxes. |
| `resolveDegeneretteBets(player, betIds)` | Resolves bets using `lootboxRngWordByIndex[index]` where index was captured at bet placement. Word was committed before current window. |
| `setOperatorApproval(operator, approved)` | Authorization-only. No game state or RNG interaction. |
| `recordMintQuestStreak(player)` | Access: self-call only. Quest tracking. No RNG interaction. |
| `payCoinflipBountyDgnrs(...)` | Access: COIN or COINFLIP only. DGNRS bounty. No RNG interaction. |
| `consumeCoinflipBoon(player)` | Access: COIN or COINFLIP only. Boon consumption. No RNG interaction. |
| `consumeDecimatorBoon(player)` | Access: COIN only. Boon consumption. No RNG interaction. |
| `consumePurchaseBoost(player)` | Access: self-call only. Boost consumption. No RNG interaction. |
| `deactivateAfKingFromCoin(player)` | Access: COIN or COINFLIP only. Deactivation only (not activation). No RNG interaction. |
| `syncAfKingLazyPassFromCoin(player)` | Access: COINFLIP only. Status sync. No RNG interaction. |
| `purchaseLazyPass(buyer)` | Lazy pass (10-level ticket grant). Routes through WhaleModule. Ticket queuing targets write slot via `rngBypass = false`. Far-future keys blocked by guard #3; near-future allowed (write slot isolation). |
| `runBafJackpot(...)` | Access: self-call guard. Delegatecall to JackpotModule. Internal to daily processing pipeline. |
| `runDecimatorJackpot(...)` | Access: self-call guard. Delegatecall to JackpotModule. Internal to daily processing pipeline. |
| `runTerminalDecimatorJackpot(...)` | Access: self-call guard. Delegatecall for gameover. |
| `runTerminalJackpot(...)` | Access: self-call guard. Delegatecall for gameover. |
| `rawFulfillRandomWords(requestId, randomWords)` | Access: VRF coordinator only (line 1534). The VRF callback -- stores the word. It IS the RNG delivery mechanism. |
| `issueDeityBoon(deity, recipient, slot)` | Deity boon issuance. Boon types determined by `_deityDailySeed(day)` which reads existing word. Boons are consumable bonuses, not RNG inputs. |

#### State-Changing Functions: NOT BLOCKED -- Could Affect RNG-Adjacent State (Detailed Analysis)

| Function | State Changed | RNG Impact | Verdict |
|----------|--------------|------------|---------|
| `purchase(buyer, ticketQty, lootBoxAmt, ...)` | Ticket queue (write slot), lootbox amounts (new index), pool balances (pending accumulators when frozen) | SAFE -- all writes target post-window state. Write slot isolated by `_swapAndFreeze`. Lootbox index advanced at request time. Pool frozen. |
| `purchaseCoin(buyer, ticketQty, lootBoxBurnieAmt)` | Same as `purchase` but BURNIE-funded | SAFE -- same isolation mechanisms |
| `purchaseBurnieLootbox(buyer, burnieAmt)` | Lootbox BURNIE amount at new index | SAFE -- writes to `lootboxBurnie[index][player]` at new index (post-increment) |
| `purchaseWhaleBundle(buyer, quantity)` (near-future) | Ticket range (write slot), lootbox amounts (new index) | SAFE -- near-future tickets go to write slot. Far-future blocked by guard #3. Lootbox at new index. |
| `placeDegeneretteBet(player, currency, ...)` | `degeneretteBets[player][nonce]`, `dailyHeroWagers`, lootbox pending counters | SAFE -- bet captures current lootbox index at placement (DegeneretteModule L446). Guard at L430 (`lootboxRngWordByIndex[index] != 0 revert`) ensures word for current index does not yet exist. Hero wagers affect NEXT day (current day's jackpot already processed). |

#### Admin-Only Functions

| Function | Access | Effect |
|----------|--------|--------|
| `wireVrf(...)` | ADMIN | VRF config setup. One-time initialization. |
| `updateVrfCoordinatorAndSub(...)` | ADMIN (line 1484) | Emergency VRF coordinator rotation. Sets `rngLockedFlag = false`. |
| `adminStakeEthForStEth(amount)` | Vault owner | ETH staking. No RNG interaction. |
| `adminSwapEthForStEth(recipient, amount)` | Vault owner | stETH swap. No RNG interaction. |
| `setLootboxRngThreshold(newThreshold)` | Vault owner | Updates lootbox RNG trigger threshold. Config only, no RNG outcome interaction. |

#### View Functions (Read-Only, Cannot Change State)

All functions with `view` or `pure` modifier: `currentDayView`, `prizePoolTargetView`, `nextPrizePoolView`, `futurePrizePoolView`, `lootboxPresaleActiveFlag`, `currentPrizePoolView`, `claimablePoolView`, `isFinalSwept`, `gameOverTimestamp`, `yieldPoolView`, `yieldAccumulatorView`, `mintPrice`, `rngWordForDay`, `rngLocked`, `isRngFulfilled`, `lastVrfProcessed`, `decWindow`, `jackpotCompressionTier`, `jackpotPhase`, `purchaseInfo`, `terminalDecWindow`, `getWinnings`, `hasDeityPass`, `afKingModeFor`, `isVaultOwner`.

**Coverage verdict:** Every external/public function is classified. No unguarded function touches state that could affect the outcome of pending RNG resolution.

---

### Section 4: Edge Cases

**Q1: What happens if rawFulfillRandomWords is called when rngLockedFlag is already false?**

This is the mid-day lootbox fulfillment path (AdvanceModule line 1543-1550). The word is stored directly to `lootboxRngWordByIndex[index]` and VRF state is cleared. This is the designed behavior for `requestLootboxRng()` callbacks.

If called spuriously (no pending request): the guard at line 1535 (`requestId != vrfRequestId || rngWordCurrent != 0`) causes a silent return. If `vrfRequestId == 0` (no pending request), the requestId check fails and the function returns without writing anything.

**Q2: What happens if _requestRng fails after setting rngLockedFlag = true?**

Cannot happen. `_requestRng()` calls `vrfCoordinator.requestRandomWords()` at line 1388 BEFORE `_finalizeRngRequest()` at line 1399. If the VRF coordinator call reverts, the entire transaction reverts. The flag is never set because `_finalizeRngRequest()` (which contains `rngLockedFlag = true` at line 1442) is never reached.

**Q3: Can rngBypass be set by anyone other than admin?**

No. `rngBypass` is a compile-time parameter at each call site, not a storage variable. All `true` callers are internal protocol functions (JackpotModule and AdvanceModule), executing within the same `advanceGame()` transaction during daily processing. No external user can influence the bypass value. See Section 2a for the complete call site inventory.

**Q4: The AdvanceModule line 177 pattern `(lastPurchase && rngLockedFlag)` -- is this a guard or a different use?**

This is a level correction, not a guard. When `lastPurchaseDay == true` and `rngLockedFlag == true`, the level was already incremented at VRF request time (line 1451: `level = lvl`). The pattern `? lvl : lvl + 1` prevents double-incrementing the level by using `lvl` (current `level`) instead of `lvl + 1`. Without this, `purchaseLevel` would overshoot by 1 during the daily VRF window after `lastPurchaseDay`.

**Q5: Stuck lock -- VRF never delivers and no admin intervention?**

After 12 hours with no VRF delivery, `rngGate()` (line 1057-1063) retries via `_requestRng()`. This sends a new VRF request (same lock holds). If VRF is permanently dead, the gameover path (`_gameOverEntropy`, line 1083) eventually triggers after `GAMEOVER_RNG_FALLBACK_DELAY = 3 days` (line 109), using historical VRF + prevrandao fallback. As last resort, ADMIN can call `updateVrfCoordinatorAndSub()` (line 1479) to rotate the coordinator and clear the lock.

---

### Threat Register Disposition (Part A)

| Threat ID | Disposition | Evidence |
|-----------|-------------|---------|
| T-215-13 (rngBypass elevation of privilege) | **MITIGATED** | `rngBypass` is a compile-time parameter at each call site, not settable by external callers. All `true` callers are internal protocol functions executing within `advanceGame()`. Complete call site inventory in Section 2a. |
| T-215-14 (Stuck rngLockedFlag) | **MITIGATED** | Three recovery paths: (a) 12-hour retry in `rngGate` (line 1060), (b) 3-day gameover fallback in `_gameOverEntropy` (line 1123), (c) admin `updateVrfCoordinatorAndSub` (line 1492) clears flag. |
| T-215-15 (Unguarded state-changing paths) | **MITIGATED** | Coverage analysis (Section 3) proves every external function is either: guarded by rngLockedFlag, writes only to post-window state (write slot, new index, pending accumulators), is admin-only, is view-only, or does not touch RNG-affecting state. Zero unguarded paths that could affect pending RNG outcomes. |

---

## Part B: Phase 215 Synthesis

### Section 5: Consolidated Findings

All findings from plans 01-04 collected:

| Finding ID | Source Plan | Chain | Severity | Description | Status |
|------------|-----------|-------|----------|-------------|--------|
| F-215-01 | 215-01 (VRF Lifecycle) | N/A | INFO | rngLockedFlag asymmetry: set for daily VRF but NOT for mid-day lootbox RNG requests. Lootbox window relies on index advance isolation instead of flag. | BY DESIGN -- documented at Storage L277. Lootbox isolation via index advance proven in 215-03 Section 2. |
| F-215-02 | 215-02 (Backward Trace) | RNG-08 | INFO | `_gameOverEntropy` fallback uses historical VRF + `block.prevrandao`. Validator can bias by 1 bit (include/skip block). | ACCEPTED -- gameover-only path, triggers after 3-day VRF stall, documented in code NatSpec (AdvanceModule L1168-1174). At level 0: minimal funds. At level 1+: historical VRF words dilute bias. |
| F-215-03 | 215-03 (Commitment Window) | Gameover | INFO | Gameover prevrandao window: block proposer knows `block.prevrandao` for their block. 1-bit manipulation (propose/skip). | Same root cause as F-215-02. Terminal one-time event. |
| F-215-04 | 215-04 (Word Derivation) | RNG-08f | MIXED | `_gameOverEntropy` branch 3: historical VRF + `block.prevrandao`. Mixed entropy source. | Same root cause as F-215-02/03. All three findings trace to the same gameover prevrandao fallback design decision. |
| F-215-05 | 215-04 (Word Derivation) | RNG-10f | NON-VRF | `_deityDailySeed` tier-3 fallback: `keccak256(day, address(this))` when no VRF word exists. Fully predictable. | BY DESIGN -- only fires before first `advanceGame` or during VRF stall. Affects deity boon display only (cosmetic/utility), not ETH payouts. Not an economic attack vector. |

**Plan 215-01 (VRF Lifecycle):** 17 TRACED verdicts across 6 sections. Zero CONCERN findings. Write-once word storage proven. rngLockedFlag asymmetry documented.

**Plan 215-02 (Backward Trace):** 13 consumer read sites across 11 RNG chains. 12 SAFE + 1 INFO (RNG-08 prevrandao). Zero VULNERABLE. Three independent commitment isolation mechanisms documented (index advance, buffer swap, explicit guard).

**Plan 215-03 (Commitment Window):** 4 VRF windows analyzed. 3 SAFE + 1 INFO (gameover prevrandao). 9 rngLockedFlag guard sites verified. 4 isolation mechanisms confirmed (rngLockedFlag, double-buffer, index advance, pool freeze).

**Plan 215-04 (Word Derivation):** 16 derivation paths traced. 14 VRF-SOURCED + 1 MIXED (gameover prevrandao) + 1 NON-VRF (deity pre-VRF fallback). Zero findings. LCG seed provenance confirmed (XOR with VRF word).

**Plan 215-05 (rngLocked, this plan):** 9 revert guard sites + 8 non-revert references catalogued. Complete coverage analysis of every external/public function. Zero unguarded paths touching RNG state. rngBypass limited to internal protocol operations.

### Deduplicated Finding Count

The five findings above reduce to **two root causes:**
1. **Gameover prevrandao fallback** (F-215-02, F-215-03, F-215-04): Single design decision -- `_getHistoricalRngFallback()` uses `block.prevrandao` when VRF is dead for 3+ days at gameover. Severity: INFO. Accepted tradeoff per code NatSpec.
2. **Deity boon deterministic fallback** (F-215-05): `_deityDailySeed` uses `keccak256(day, address(this))` when no VRF word exists. Severity: INFO. Cosmetic/utility only -- no ETH impact.

**Zero VULNERABLE findings across the entire phase.**
**Zero CONCERN findings across the entire phase.**

---

### Section 6: Phase Verdict

**Success Criterion 1: VRF lifecycle traced end-to-end?**
YES. Plan 215-01 traced all 6 VRF paths (daily request, daily fulfillment, rngGate retrieval, gap day backfill, lootbox request/fulfillment, gameover fallback) with 17 TRACED verdicts. Every state mutation documented with line numbers. Write-once word storage proven via dual guards (`rngWordCurrent != 0` at callback, `rngWordByDay[day] != 0` at rngGate entry).

**Success Criterion 2: Every consumer backward traced?**
YES. Plan 215-02 traced all 13 consumer read sites across 11 RNG chains backward to their input commitment points. VRF word proven unknown at commitment time for all 12 SAFE chains. The single INFO (RNG-08 gameover prevrandao) has documented 1-bit validator bias in a terminal fallback-only path.

**Success Criterion 3: Commitment windows analyzed?**
YES. Plan 215-03 analyzed all 4 VRF windows (daily, lootbox, between-day, gameover). Every external/public function classified as BLOCKED or NOT BLOCKED with detailed state-change analysis. 4 independent isolation mechanisms documented. 3 SAFE + 1 INFO windows.

**Success Criterion 4: Word derivations verified?**
YES. Plan 215-04 traced all 16 derivation paths from VRF source word to game outcome. 14 VRF-SOURCED, 1 MIXED (gameover prevrandao fallback), 1 NON-VRF (deity pre-VRF deterministic fallback). Every keccak256, bit shift, mask, modulo, and XOR operation documented with exact Solidity code and line numbers. Domain separation confirmed for all keccak calls.

**Success Criterion 5: rngLocked mutual exclusion verified?**
YES. This plan (215-05) catalogued all 17 rngLockedFlag reference sites (9 revert guards + 8 non-revert uses). Coverage analysis classified every external/public function on DegenerusGame.sol. rngBypass traced to internal protocol operations only. Three edge cases analyzed (stuck lock, stale callback, double-increment prevention). Zero unguarded paths touching RNG-affecting state found.

**Supporting evidence from Phase 214 (per D-04):**
- Phase 214-01 (Reentrancy/CEI): Zero VULNERABLE verdicts on RNG-touching functions. All external calls in `advanceGame`, `rngGate`, `_requestRng`, `requestLootboxRng`, and `rawFulfillRandomWords` follow CEI ordering. `rngLockedFlag` confirmed as mutual exclusion guard blocking re-entry via purchase/lootboxRng paths during RNG window.
- Phase 214-03 (State Corruption): No state corruption in RNG packed fields.
- Phase 214-05 (Attack Chains): Zero VULNERABLE attack chains involving RNG entry points.

---

## Phase Verdict: SOUND

The Degenerus Protocol's VRF/RNG system is **SOUND** from first principles.

**Rationale:**
1. **Complete VRF lifecycle integrity.** The request/fulfillment cycle is fully traced with write-once word storage, caller validation, and zero-word protection. No path exists to overwrite, skip, or corrupt a VRF word.

2. **Universal commitment-before-revelation.** Every RNG consumer's inputs are committed before the VRF word exists. Three independent isolation mechanisms (index advance, ticket buffer swap, pool freeze) ensure new activity during VRF windows cannot contaminate pending resolution.

3. **Effective mutual exclusion.** 9 rngLockedFlag guard sites block all functions that could influence pending daily RNG outcomes. Every external/public function is classified and accounted for. The lootbox VRF window (which does not set rngLockedFlag) achieves equivalent isolation via index advance.

4. **Clean derivation chains.** Every game outcome traces to a VRF source word through documented keccak256, XOR, or bit extraction operations. No non-VRF entropy enters game-outcome decisions except two documented edge cases (gameover prevrandao fallback, deity pre-VRF deterministic boon display) which are both INFO severity.

5. **No findings requiring remediation.** The two root causes identified (gameover prevrandao, deity deterministic fallback) are accepted design tradeoffs documented in the code NatSpec. Neither creates an economically exploitable attack vector.

---

*Audit: 215-05 rngLocked Mutual Exclusion + Phase 215 Synthesis (RNG-05)*
*Phase: 215-rng-fresh-eyes*
