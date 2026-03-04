# Architecture Research: Degenerus Protocol — Adversarial Audit (v2.0)

**Domain:** On-chain lottery/game — delegatecall module pattern with VRF, ETH pool accounting, and pull-withdraw
**Researched:** 2026-03-04
**Confidence:** HIGH (direct source analysis of 113,562 lines Solidity)

---

## System Overview

```
+-------------------------------------------------------------------------+
|                      EXTERNAL ENTRY LAYER                               |
|  Players / Bots / Chainlink VRF Coordinator / Admin (CREATOR key)       |
+----------------------------------+--------------------------------------+
                                   | msg.call
+----------------------------------v--------------------------------------+
|                       DegenerusGame (19KB)                              |
|  * State machine owner (PURCHASE <-> JACKPOT -> GAMEOVER)               |
|  * Holds all ETH + stETH for the protocol                               |
|  * 135 storage variables across shared DegenerusGameStorage             |
|  * Every complex function is a delegatecall wrapper                     |
|  * Direct: recordMint, claimWinnings, operator approvals, view funcs    |
+--+------------+------------+------------+------------+-----------------+-+
   | delegatecall| delegatecall| delegatecall| delegatecall| delegatecall
   |            |            |            |            |
+--v------+ +---v----+ +----v---+ +----v--+ +------v-----------------+
|Advance  | |Jackpot | |  Mint  | | Whale | |  Endgame / GameOver /  |
|Module   | |Module  | | Module | |Module | |  Lootbox / Boon /      |
|         | |        | |        | |       | |  Decimator / Degnrt.   |
+---------+ +--------+ +--------+ +-------+ +------------------------+
   (VRF mgmt + FSM tick)  (payout math)  (ticket batching)  (all others)

+-------------------------------------------------------------------------+
|                    SHARED STORAGE (DegenerusGameStorage)                |
|  Slot 0: levelStartTime | dailyIdx | rngRequestTime | level | phase     |
|  Slot 1: jackpotCounter | flags | cursors | purchaseStartDay            |
|  Slot 2: price (uint128)                                                |
|  Slots 3+: pools (currentPrize/next/future/claimable) | mappings        |
|  Key mappings: claimableWinnings[addr] | ticketQueue[lvl][addr[]]       |
|                traitBurnTicket[lvl][traitId][addr[]] | rngWordByDay[day]|
+-------------------------------------------------------------------------+

+-------------------------------------------------------------------------+
|                    PERIPHERAL CONTRACTS                                 |
|  BurnieCoin (COIN)   -- ERC20, coinflip credits, burn interface         |
|  BurnieCoinflip      -- Wager settlement, calls Game.processCoinflip()  |
|  DegenerusAdmin      -- VRF subscription owner, emergency recovery      |
|  DegenerusVault      -- Perpetual ETH staker, DGVE token                |
|  DegenerusStonk      -- DGNRS token, affiliate/reward pool              |
|  DegenerusAffiliate  -- Referral tracking, score, top-affiliate query   |
|  DegenerusQuests     -- Quest streak tracking                           |
|  DegenerusJackpots   -- BAF/Decimator jackpot resolution, claim credits |
|  DegenerusDeityPass  -- ERC721 for deity pass, calls Game.onTransfer()  |
|  DegenerusNFT        -- Player NFT (non-critical path)                  |
+-------------------------------------------------------------------------+

External: Chainlink VRF V2.5 coordinator | Lido stETH | LINK token
```

---

## Component Responsibilities

| Component | Responsibility | Audit Surface |
|-----------|----------------|---------------|
| DegenerusGame | FSM orchestrator, ETH custody, delegatecall dispatcher | ALL ETH flows, access control, reentrancy entry |
| DegenerusGameAdvanceModule | advanceGame() tick logic, VRF request/receive, RNG gate | Gas budget, RNG manipulation, griefing |
| DegenerusGameJackpotModule | Daily ETH distribution, ticket batch processing, pool consolidation | O(n) loops, winner selection bias, accounting |
| DegenerusGameMintModule | Purchase recording, trait generation, future ticket activation | Batch gas, Sybil bloat, lootbox EV |
| DegenerusGameWhaleModule | Whale bundle / lazy pass / deity pass purchases | Level eligibility (F01), pricing bugs |
| DegenerusGameEndgameModule | BAF/Decimator jackpot resolution, auto-rebuy, affiliate reward | ETH accounting, pool deduction order |
| DegenerusGameGameOverModule | Liveness-triggered drain, final sweep, deity refunds | Loop over deityPassOwners (O(n)) |
| DegenerusGameLootboxModule | Lootbox open, deity boon issuance | RNG index assignment, boon slot bugs |
| DegenerusGameBoonModule | Boon consumption (coinflip/decimator/purchase) | Cross-call state transitions |
| DegenerusGameDecimatorModule | Dec burn recording, jackpot snapshot, deferred claims | Bucket math, claim window, accounting |
| DegenerusGameDegeneretteModule | Full-ticket bet placement and resolution | RNG derivation, ETH transfer on resolve |
| DegenerusGamePayoutUtils | Shared credit helpers, auto-rebuy calc | Pool invariant violations |
| DegenerusGameMintStreakUtils | Streak computation helpers (inherited, not delegatecalled) | Bit-packing correctness |
| DegenerusAdmin | VRF subscription owner, emergency coordinator rotation | Admin abuse, 3-day stall bypass |
| DegenerusGameStorage | Canonical storage layout (135 vars, slot map) | Collision correctness |

---

## advanceGame() Complete Call Graph

`advanceGame()` in DegenerusGame is a single delegatecall into AdvanceModule. The AdvanceModule then calls back into Game or delegates into sub-modules.

### Tier 1: DegenerusGame.advanceGame()

```
DegenerusGame.advanceGame()
  └─ delegatecall -> AdvanceModule.advanceGame()   [runs in Game's storage]
```

### Tier 2: AdvanceModule.advanceGame() — internal branching (do-while, break on each path)

```
AdvanceModule.advanceGame()
  |
  +-- _handleGameOverPath(ts, day, levelStartTime, lvl, lastPurchase, dailyIdx)
  |     +-- [gameOver=true] delegatecall -> GameOverModule.handleFinalSweep()
  |     +-- [liveness triggered] delegatecall -> GameOverModule.handleGameOverDrain(day)
  |           +-- Loop: for each deityPassOwner -> creditClaimable [O(n) over deityPassOwners]
  |
  +-- _enforceDailyMintGate(caller, purchaseLevel, dailyIdx)   [view, no delegatecall]
  |
  +-- rngGate(ts, day, purchaseLevel, lastPurchase)
  |     +-- [word exists] -> return cached rngWordByDay[day]
  |     +-- [word received] -> _applyDailyRng(day, word)
  |     |                      -> coinflip.processCoinflipPayouts()  [external call: COINFLIP]
  |     |                      -> _finalizeLootboxRng()
  |     |                      -> return word
  |     +-- [timeout 18h] -> _requestRng() -> vrfCoordinator.requestRandomWords()  [external]
  |     +-- [waiting] -> revert RngNotReady
  |
  +-- [phaseTransitionActive] _processPhaseTransition(purchaseLevel)
  |     +-- _queueTickets(DGNRS, targetLevel, 16)   [SSTORE x 2]
  |     +-- _queueTickets(VAULT, targetLevel, 16)   [SSTORE x 2]
  |     +-- _autoStakeExcessEth()  -> steth.submit{value}()  [external call: Lido, try/catch]
  |
  +-- [final jackpot day] _prepareFinalDayFutureTickets(lvl)
  |     +-- Loop: levels lvl+2..lvl+5 -> delegatecall -> MintModule.processFutureTicketBatch(lvl)
  |                                       [O(WRITES_BUDGET_SAFE=550) writes per call]
  |
  +-- _runProcessTicketBatch(purchaseLevel)
  |     +-- delegatecall -> JackpotModule.processTicketBatch(lvl)
  |           +-- Pops ticketQueue[lvl] entries batch-by-batch (cursor-based)
  |           +-- For each player: generates traits, writes traitBurnTicket entries
  |              [O(WRITES_BUDGET_SAFE) writes per call]
  |
  +-- === PURCHASE PHASE (inJackpot=false) ===
  |     +-- [!lastPurchaseDay] payDailyJackpot(false, lvl, word)
  |     |     +-- delegatecall -> JackpotModule.payDailyJackpot()
  |     |           +-- Selects bucket winners from traitBurnTicket[lvl][traitId]
  |     |           |   [O(DAILY_ETH_MAX_WINNERS) credits, cross-call resume via cursors]
  |     |           +-- _creditClaimable(winner, amount) x N  [N<=cursor cap]
  |     +-- [!lastPurchaseDay] _payDailyCoinJackpot(lvl, word)
  |     |     +-- delegatecall -> JackpotModule.payDailyCoinJackpot()
  |     |           +-- coin.creditFlip(winner, amount)  [external: COIN]
  |     +-- [lastPurchaseDay, activating] _processFutureTicketBatch(nextLevel)
  |     |     +-- delegatecall -> MintModule.processFutureTicketBatch()  [batch limited]
  |     +-- _consolidatePrizePools(lvl, word)
  |     |     +-- delegatecall -> JackpotModule.consolidatePrizePools()
  |     |           +-- Merges next->current, calculates future take
  |     |           +-- steth.submit / steth.balanceOf calls  [external: Lido]
  |     |           +-- coinflip.recordAfKingRng()  [external: COINFLIP]
  |     +-- jackpotPhaseFlag = true  [JACKPOT phase entered]
  |
  +-- === JACKPOT PHASE (inJackpot=true) ===
        +-- [resume cursors] payDailyJackpot(true, lastDailyJackpotLevel, word)
        |     +-- delegatecall -> JackpotModule.payDailyJackpot() [resuming]
        +-- [dailyJackpotCoinTicketsPending] payDailyJackpotCoinAndTickets(word)
        |     +-- delegatecall -> JackpotModule.payDailyJackpotCoinAndTickets()
        |           +-- coin.creditFlip(winner, amount)  [external: COIN]
        |           +-- [jackpotCounter >= CAP] finalDay sequence:
        |                 +-- _awardFinalDayDgnrsReward() -> JackpotModule.awardFinalDayDgnrsReward()
        |                 |     +-- dgnrs.transferFromPool()  [external: DGNRS]
        |                 +-- _rewardTopAffiliate() -> EndgameModule.rewardTopAffiliate()
        |                 |     +-- affiliate.affiliateTop()  [external: AFFILIATE]
        |                 |     +-- dgnrs.transferFromPool()  [external: DGNRS]
        |                 +-- _runRewardJackpots() -> EndgameModule.runRewardJackpots()
        |                 |     +-- BAF: jackpots.runBafJackpot(pool, lvl, rng)  [external: JACKPOTS]
        |                 |     |    -> callback: game.creditDecJackpotClaimBatch()
        |                 |     +-- Decimator: game.runDecimatorJackpot(pool, lvl, rng)  [self-call]
        |                 |           +-- delegatecall -> DecimatorModule.runDecimatorJackpot()
        |                 +-- _endPhase()  [level transition, phaseTransitionActive = true]
        +-- [fresh daily] payDailyJackpot(true, lvl, word)
              +-- delegatecall -> JackpotModule.payDailyJackpot()
```

### VRF Callback Path (async, from Chainlink)

```
Chainlink VRF Coordinator
  +-- DegenerusGame.rawFulfillRandomWords(requestId, words[])
        +-- delegatecall -> AdvanceModule.rawFulfillRandomWords()
              +-- Guard: msg.sender != vrfCoordinator -> revert E()
              +-- Guard: requestId != vrfRequestId -> silent return
              +-- Guard: rngWordCurrent != 0 -> silent return (already fulfilled)
              +-- [rngLockedFlag=true (daily)] -> rngWordCurrent = word  [SSTORE]
              +-- [rngLockedFlag=false (lootbox)] -> lootboxRngWordByIndex[index] = word  [SSTORE]
                                                     + emit LootboxRngApplied
                                                     + clear vrfRequestId, rngRequestTime
```

---

## Gas Accounting: Code Path Complexity

| Path | Complexity | State Variables Controlling It | Worst Case |
|------|-----------|--------------------------------|------------|
| `rngGate()` -> request new VRF | O(1) | vrfCoordinator, vrfKeyHash, vrfSubscriptionId | ~150K gas |
| `rngGate()` -> apply cached word | O(1) | rngWordCurrent, totalFlipReversals | ~80K gas |
| `_runProcessTicketBatch()` | O(WRITES_BUDGET_SAFE = 550) | ticketQueue[lvl].length, ticketCursor | ~15M gas at cap |
| `_processFutureTicketBatch()` x 4 | O(550 x 4 = 2200 writes across calls) | ticketQueue[lvl+2..lvl+5].length | 4 separate calls each ~15M |
| `payDailyJackpot()` ETH distribution | O(DAILY_ETH_MAX_WINNERS x 4 buckets) | dailyEthBucketCursor, dailyEthWinnerCursor | ~8M gas; resumes via cursors |
| `payDailyJackpotCoinAndTickets()` | O(ticket winners) | dailyTicketBudgetsPacked | ~3M gas |
| `handleGameOverDrain()` -> level 0 | O(deityPassOwners.length) | deityPassOwners[] (max ~26) | ~26 iterations, bounded |
| `_endPhase()` + `_runRewardJackpots()` | O(1) + O(BAF/Dec winners) | futurePrizePool, jackpots contract | variable, external-limited |
| `_prepareFinalDayFutureTickets()` | O(4 x 550) across calls | ticketQueue[lvl+2..lvl+5].length, ticketCursor | multi-call; each ~15M |
| `_currentNudgeCost()` | O(totalFlipReversals) | totalFlipReversals | Economically self-limiting but O(n) |
| `_consolidatePrizePools()` | O(1) | pool variables | ~200K gas |
| `processTicketBatch()` -- trait burn write | O(WRITES_BUDGET_SAFE) SSTOREs cold | ticketQueue[lvl].length | 550 x ~20K = 11M gas (cold) |

### Critical Gas Pressure Points

**1. processTicketBatch (WRITES_BUDGET_SAFE = 550)**
Each batch writes up to 550 entries to `traitBurnTicket[lvl][traitId]` (dynamic arrays).
First write to a new traitId array slot is cold: ~20K gas SSTORE.
550 cold writes = 11M gas. Warm writes = 550 x 5K = 2.75M gas.
If ticketQueue[lvl].length grows large (Sybil bloat), many advanceGame calls are needed before the level can proceed.
Key variable: `ticketCursor` — if griefed (forced to be non-zero from previous level's queue at same level slot), batches silently skip to wrong level.

**2. payDailyJackpot winner loop**
Iterates over bucket winners up to DAILY_ETH_MAX_WINNERS per bucket, 4 buckets.
Each winner credit is one `_creditClaimable` = one SSTORE to `claimableWinnings`.
Resumes mid-bucket via `dailyEthBucketCursor` + `dailyEthWinnerCursor` if gas is exhausted.
Attack surface: if a bucket has 0 holders (all trait arrays empty), the cursor may not advance — potential stuck-state path (verify zero-holder guard in JackpotModule).

**3. _prepareFinalDayFutureTickets (levels lvl+2..lvl+5)**
Calls `_processFutureTicketBatch` up to 4 times per advanceGame call.
Each can consume full WRITES_BUDGET_SAFE. On high-Sybil days this means 4 sequential 15M-gas calls just for this sub-step before the actual jackpot runs.
Cannot proceed to final jackpot until all 4 future-level queues are fully processed.

**4. _currentNudgeCost() (O(totalFlipReversals))**
Linear loop over nudge count for cost computation. Economically bounded (exponential cost) but technically O(n).
If `totalFlipReversals` somehow grows large without economic pressure, this burns gas in AdvanceModule.

**5. handleGameOverDrain (O(deityPassOwners.length))**
Iterates over `deityPassOwners` array to credit refunds.
Capped at 24 deity passes + 2 vault addresses = 26 max. O(1) in practice.
Risk: if cap is not enforced correctly in WhaleModule, malicious actors could push more entries.

---

## ETH Flow Architecture and claimWinnings() CEI Analysis

### ETH Inflow Paths

```
Player.purchase() -> DegenerusGame.recordMint()
  +-- _processMintPayment() -> splits ETH to:
        +-- nextPrizePool += (prizeContribution x 90%) / 100
        +-- futurePrizePool += (prizeContribution x 10%) / 100

Player.purchaseWhaleBundle() -> WhaleModule
  +-- ETH split: level 1: 50%/25%/25%; other levels: 50%F/45%R/5%N

Player.purchaseDeityPass() -> WhaleModule -> futurePrizePool + nextPrizePool

Lido stETH yield -> rebases into steth.balanceOf(GAME)
  +-- counted in _payoutWithStethFallback() but NOT in claimablePool tracking
```

### ETH Outflow Paths

```
claimWinnings(player)
  -> _claimWinningsInternal()
      1. amount = claimableWinnings[player]          [CHECK]
      2. claimableWinnings[player] = 1               [EFFECT: sentinel left]
      3. claimablePool -= (amount-1)                 [EFFECT: before external call]
      4. emit WinningsClaimed                         [EFFECT]
      5. _payoutWithStethFallback(player, amount-1)  [INTERACTION]
          +-- payable(player).call{value: ethSend}("")  <- REENTRANCY ENTRY POINT 1
          +-- steth.transfer(player, stSend)            <- REENTRANCY ENTRY POINT 2 (ERC20)

refundDeityPass(buyer)
  -> state cleared before _payoutWithStethFallback  [CEI compliant]
  +-- _payoutWithStethFallback(buyer, refundAmount)  <- REENTRANCY ENTRY POINT
```

### Reentrancy Analysis

**claimWinnings() — CEI verification:**
- Check: `amount <= 1` reverts (correctly gates)
- Effect: `claimableWinnings[player] = 1` (sentinel) before transfer
- Effect: `claimablePool -= payout` before transfer
- Interaction: `payable(to).call{value}`
- Verdict: Properly CEI. Re-entrant call to `claimWinnings` sees sentinel `1`, reverts on `amount <= 1`.

**Cross-function reentrancy risk (HIGH priority for audit):**
A re-entrant call during `_payoutWithStethFallback` could call functions OTHER than `claimWinnings`:
- `purchase()` -> MintModule -> `recordMint()` — writes to nextPrizePool, futurePrizePool, claimableWinnings
- `purchaseWhaleBundle()` -> WhaleModule — writes pool variables
- `advanceGame()` -> AdvanceModule — reads claimablePool for solvency checks
- `setAutoRebuy()` — guarded by rngLockedFlag, not re-entrancy guard
- `openLootBox()` -> LootboxModule — credits claimableWinnings

**Key cross-function reentrancy question:**
Can attacker during `_payoutWithStethFallback` callback call `purchase()` with Combined payment mode?
Answer: Safe. Claimable path requires `claimableWinnings[attacker] > ticketCost`. During reentry, `claimableWinnings[attacker] = 1` (sentinel), so `1 > ticketCost` fails. Blocked.

**stETH reentrancy path:**
`steth.transfer()` is an ERC20 call. Lido stETH does not have transfer hooks (not ERC777). No reentrancy vector via stETH transfer.

**delegatecall reentrancy:**
All modules execute in Game's storage context. A module cannot trigger a second delegatecall to the same module via re-entrancy since `delegatecall` does not change `address(this)`. However, modules do call external contracts (COIN, DGNRS, JACKPOTS, AFFILIATE) which could theoretically call back to Game. All such callbacks have their own access control but do write to shared storage — cross-contract storage-write races are the concern, not call depth.

**Finding in PayoutUtils (_creditClaimable does not update claimablePool):**
`DegenerusGamePayoutUtils._creditClaimable(beneficiary, amount)` only writes to `claimableWinnings[beneficiary]`, NOT `claimablePool`. The solvency invariant `claimablePool >= sum(claimableWinnings)` depends on all credit paths also updating `claimablePool`. If any caller of `_creditClaimable` does not separately increment `claimablePool`, aggregate liability exceeds the tracked pool, breaking solvency. This is a HIGH-PRIORITY verification target for the CEI/accounting phase.

---

## Admin Privilege Surface

| Function | Caller | Effect | Rug/Grief Vector |
|----------|--------|--------|-----------------|
| `wireVrf(coordinator, subId, keyHash)` | ADMIN contract only | Sets VRF config once | One-time only; ADMIN contract mediates |
| `updateVrfCoordinatorAndSub()` | ADMIN only, 3-day stall gate | Replaces VRF config entirely, resets rngLockedFlag | If ADMIN abuses stall detection: could reset RNG lock mid-jackpot |
| `setLootboxRngThreshold(threshold)` | ADMIN only | Raises/lowers lootbox RNG trigger | Could set to uint256.max, permanently blocking lootbox RNG (grief) |
| `adminSwapEthForStEth()` | ADMIN -> Game | Swaps Game-held ETH for CREATOR-provided stETH | Only moves between ETH and stETH, not extraction |
| `adminStakeEthForStEth()` | ADMIN -> Game | Stakes game ETH into Lido | Reduces liquid ETH; no guard checking balance vs claimablePool |
| `emergencyRecover()` (Admin contract) | CREATOR only | Creates new VRF subscription, wires to Game | Requires 3-day stall; CREATOR controlled |
| `cancelSubscription()` (Admin contract) | CREATOR, post-gameOver | Cancels VRF sub, returns LINK to creator | Requires gameOver flag |
| `setLinkEthPriceFeed()` (Admin contract) | CREATOR, only if feed unhealthy | Replaces LINK/ETH price oracle | Oracle manipulation risk for LINK donation credit |
| `endLootboxPresale()` | CREATOR only | Closes presale (one-way) | Cannot re-enable presale; minor timing lever |

**Admin contract CREATOR access (via DegenerusAdmin):**
- Cannot extract ETH from Game directly
- Cannot change game state (jackpot outcomes, ticket counts)
- CAN: stall VRF by not funding subscription (grief), force emergency rotation after 3-day gap (could change randomness source), manipulate LINK/ETH price feed (affects LINK donation credit math)
- 3-day stall bypass concern: CREATOR can simply not call advanceGame for 3 days to create the stall condition, then trigger emergency rotation with a custom coordinator address.

---

## Sybil Impact on State: O(n) Growth Analysis

| Data Structure | Grows With | Key | Access Pattern in advanceGame |
|----------------|-----------|-----|-------------------------------|
| `ticketQueue[lvl]` (address[]) | Unique buyers per level | per level | Iterated fully by processTicketBatch before jackpot starts |
| `traitBurnTicket[lvl][traitId]` (address[][]) | Ticket purchases per trait | per level x 256 traits | Randomly sampled for winner selection; no full iteration |
| `mintPacked_[addr]` | 1 slot per player | per player | SLOAD per advanceGame call gate; O(1) |
| `claimableWinnings[addr]` | 1 slot per winner | per player | SLOAD/SSTORE on credit; O(1) |
| `deityPassOwners[]` | Deity pass purchases | global array | Iterated in handleGameOverDrain (max 26) |
| `rngWordByDay[day]` | One entry per game day | per day | O(1) lookup |
| `ticketsOwedPacked[lvl][addr]` | Unique buyers per level | per level x player | O(1) per player |

**Critical Sybil bloat vector:**
`ticketQueue[lvl]` grows by 1 per unique buyer who has never purchased at that level before.
A Sybil attack creating N unique addresses at level L means `processTicketBatch` must iterate N entries, each consuming ~20K gas (cold `traitBurnTicket` SSTORE).
At 550-write budget, it takes ceil(N/550) advanceGame calls before the game can process jackpots at that level.
Each advanceGame call is publicly callable but requires the caller to have minted today (or have a lazy/deity pass), so pure-Sybil attackers cannot continuously spam without paying ticket prices.
Bloat calculation: With 10K Sybil addresses at minimum ticket cost (0.0025 ETH each), total cost = 25 ETH. Game is delayed by ceil(10K/550) = 19 advanceGame calls = potentially 19 days if each requires one call.

---

## New Analysis Approaches for Adversarial Audit Phases

### Phase A: advanceGame() Call Graph (this document)
Status: COMPLETE — full call graph documented above.
Methodology: Static source trace + cross-reference with advance module constants.
Output: Identifies all external calls and delegatecall sites within one advanceGame tick.

### Phase B: Gas Accounting (priority — must precede Sybil analysis)
Methodology:
1. Instrument each code path branch with estimated gas (cold vs warm SSTORE counts).
2. Identify worst-case path: `_prepareFinalDayFutureTickets` x 4 + `processTicketBatch` on cold queue + `payDailyJackpot` with full winner cap.
3. Verify 16M block gas limit is never exceeded in a single call on any realistic path.
4. Key constants to locate: DAILY_ETH_MAX_WINNERS (in JackpotModule — not yet read), VRF_CALLBACK_GAS_LIMIT = 300_000.
5. Special concern: Is `dailyEthWinnerCursor` properly bounded when a bucket has 0 holders?

### Phase C: Reentrancy Proof (ETH transfer sites)
ETH transfer sites requiring CEI verification:

| Site | Function | Pattern | Status |
|------|----------|---------|--------|
| `claimWinnings` | `_payoutWithStethFallback` | CEI: sentinel set before call | Verified safe from source |
| `refundDeityPass` | `_payoutWithStethFallback` | State cleared before call | Verify pool deduction order |
| `_payoutWithEthFallback` | `claimWinningsStethFirst` | stETH first, ETH second | Verify VAULT/DGNRS re-entrancy |
| GameOverModule drain | Internal credits only, no immediate transfer | Pull-pattern | Low risk |
| DecimatorModule claim | `claimDecimatorJackpot` -> Dec module | Verify CEI in module | Needs DecimatorModule read |
| EndgameModule auto-rebuy | Credits claimable first | Pull-pattern | Low risk |

Cross-function reentrancy matrix to verify:
- During `_payoutWithStethFallback` callback: call `purchase()` with Combined payment -> Safe (sentinel blocks Claimable path).
- During callback: call `advanceGame()` -> Reads claimablePool (already decremented). No invariant violation during purchase phase.
- During callback: call `openLootBox()` -> Credits claimableWinnings. Verify PayoutUtils._creditClaimable separately increments claimablePool (HIGH PRIORITY — suspected missing).

### Phase D: VRF Security Analysis
Key concerns to verify:
1. requestId matching on retry: When VRF request is retried after 18h timeout, `vrfRequestId` is overwritten. Previous request fulfilling late is silently dropped. Verify lootbox index remapping in `_finalizeRngRequest` is correct.
2. Nudge manipulation: `reverseFlip()` adds +1 per nudge to the VRF word. Only available before RNG lock. Well-funded attacker can influence outcomes within a known range. By design, but verify nudge cost is truly exponential (O(n) loop might have integer rounding that makes it cheaper than expected at large n).
3. Coordinator spoofing: `rawFulfillRandomWords` checks `msg.sender != address(vrfCoordinator)`. If coordinator updated via emergency rotation right before Chainlink fulfills, the old request is lost and 18h timeout triggers retry. Verify this does not cause indefinite retry loops.
4. Mid-day lootbox RNG race: `requestLootboxRng()` can only be called when daily RNG consumed and `rngLockedFlag=false`. If daily RNG word arrives for day D but `requestLootboxRng` was called with a stale request, verify lootbox index remapping via `_reserveLootboxRngIndex` assigns correct index on retry.

### Phase E: Admin Power / Rug Vector Analysis
Key findings from source:
- `adminStakeEthForStEth(amount)` — ADMIN can stake any amount up to game's ETH balance. No guard checking `amount <= address(this).balance - claimablePool`. This could break solvency invariant if abused. Verify whether Game enforces guard before staking.
- 3-day stall bypass: CREATOR controls whether advanceGame is called. By not calling it for 3 days and not funding VRF, CREATOR can trigger the emergency rotation condition, then supply a custom coordinator. This effectively gives CREATOR control over the next RNG word.
- `wireVrf` is called once but `updateVrfCoordinatorAndSub` is callable multiple times (after each 3-day gap). The game could be stuck in a cycle of VRF stalls and coordinator rotations controlled by CREATOR.

### Phase F: Sybil + MEV Attack Modeling
Build order dependency: Must complete gas accounting (Phase B) first to know exact cost per advanceGame tick in Sybil scenarios.

Attack surface to model:
1. Queue bloat griefing: Cost to delay level N by K advanceGame calls = K x (minimum ticket price x ~unique_players_needed) where unique_players = K x 550.
2. Ticket cursor manipulation: `ticketCursor` is shared between `processTicketBatch` and `processFutureTicketBatch`. Verify switching between levels does not corrupt cursor state.
3. lastPurchaseDay racing: On the tick where `nextPrizePool >= levelPrizePool[purchaseLevel-1]` becomes true, `lastPurchaseDay` is set. A block proposer seeing this could front-run advanceGame to buy last-minute tickets before the level ends, knowing they will participate in the upcoming jackpot phase.
4. Compressed jackpot gaming: `compressedJackpotFlag` triggers 3-day instead of 5-day jackpot when target is met within 2 days. If a whale can hit the target on day 1, they compress the jackpot window, reducing competition from slower players.

---

## Integration Points

### External Service Boundaries

| Service | Integration Pattern | Failure Mode | Audit Concern |
|---------|---------------------|-------------|---------------|
| Chainlink VRF V2.5 | `requestRandomWords()` + `rawFulfillRandomWords()` callback | VRF stall -> 18h retry, then 3-day emergency | requestId replay, coordinator spoofing |
| Lido stETH | `submit{value}()` for auto-staking; `balanceOf()` for solvency | Lido pause -> try/catch in autoStake; transfer reverts in payout | stETH balance counting, rebase accounting |
| COIN (BurnieCoin) | `creditFlip`, `burnCoin`, `processCoinflipPayouts`, callbacks | Revert propagates back to advanceGame | COIN callbacks to Game create re-entrancy vectors |
| COINFLIP | `processCoinflipPayouts`, `recordAfKingRng` | Revert propagates | Same as COIN |
| JACKPOTS | `runBafJackpot`, `creditDecJackpotClaimBatch` callbacks | Credits flow back via creditDecJackpotClaimBatch | JACKPOTS calling back into Game during level transition |
| AFFILIATE | `affiliateTop`, `affiliateScore` | View calls; revert propagates | Only view calls; low risk |
| DGNRS | `poolBalance`, `transferFromPool` | Pool exhausted -> 0 payment, not revert | Pool drain could break affiliate rewards |
| DEITY_PASS | `burn(tokenId)` callback + `onDeityPassTransfer` | Revert propagates | WhaleModule storage writes from transfer hook |

### Internal Module Boundaries

| Boundary | Communication | Key Risk |
|----------|--------------|---------|
| DegenerusGame <-> AdvanceModule | delegatecall (shared storage) | Module cannot add own storage vars |
| DegenerusGame <-> JackpotModule | delegatecall (shared storage) | Pool variable accounting split between callers |
| DegenerusGame <-> MintModule | delegatecall (shared storage) | Ticket queue cursor shared with JackpotModule |
| DegenerusGame <-> EndgameModule | delegatecall (shared storage) | External calls to JACKPOTS mid-delegatecall |
| DegenerusGame <-> GameOverModule | delegatecall (shared storage) | Iterates deityPassOwners array |
| AdvanceModule -> JackpotModule | via Game internal function call within delegatecall context | payDailyJackpot is called as internal delegatecall from AdvanceModule |
| Game.recordMint <-> MintModule | Self-call guard: msg.sender != address(this) | WhaleModule calls recordMint via Game interface |
| Game.runDecimatorJackpot | Self-call then delegatecall to DecimatorModule | Double-delegatecall chain; verify storage coherence |

---

## Anti-Patterns Found in Codebase

### Anti-Pattern 1: Shared Cursor Between Unrelated Batch Operations

What: `ticketCursor` and `ticketLevel` are used by both `processTicketBatch` (current-level tickets) and `processFutureTicketBatch` (future-level tickets). They are documented as "mutually exclusive" but both code paths read/write these same variables.

Why it is risky: If `_prepareFinalDayFutureTickets` leaves `ticketCursor` non-zero at `ticketLevel = lvl+3`, and the next advanceGame call enters `_runProcessTicketBatch(purchaseLevel)`, the cursor check at the start of `processTicketBatch` must handle the level mismatch correctly. If it proceeds with the stale cursor, it starts mid-batch at the wrong level.

Verification needed: Read JackpotModule.processTicketBatch to confirm it resets cursor when `ticketLevel != lvl`.

### Anti-Pattern 2: _creditClaimable Does Not Update claimablePool

What: `DegenerusGamePayoutUtils._creditClaimable(beneficiary, amount)` only writes to `claimableWinnings[beneficiary]` without incrementing `claimablePool`. The solvency invariant depends on all credit paths also updating `claimablePool`.

Where used: `_creditClaimable` is called by JackpotModule winner payouts (daily jackpot), EndgameModule auto-rebuy, and PayoutUtils whale pass queue. Some callers separately update `claimablePool`, others may not.

Risk: If any caller of `_creditClaimable` does not separately increment `claimablePool`, the aggregate liability exceeds the tracked pool, breaking solvency. This is carried from the v1.0 Phase 4 gap.

Verification needed: Audit every call site of `_creditClaimable` and confirm corresponding `claimablePool +=` exists in the same code path.

### Anti-Pattern 3: O(n) Nudge Cost Computation in Hot Path

What: `_currentNudgeCost()` uses a while loop over `totalFlipReversals` to compute the exponential nudge cost. Called inside AdvanceModule which is inside a delegatecall.

Why acceptable but notable: The exponential cost makes large n economically impossible in practice (~100 nudges costs astronomically). But the function is technically O(n) and cannot be gas-bounded by the protocol. A closed-form calculation would be O(1) and safer.

### Anti-Pattern 4: adminStakeEthForStEth Without Solvency Guard

What: Game exposes `adminStakeEthForStEth(amount)` callable by ADMIN with no guard checking `address(this).balance - amount >= claimablePool`.

Risk: If ADMIN stakes ETH exceeding the non-claimable balance, the contract holds stETH but not enough liquid ETH for immediate `claimWinnings` calls. Players receive stETH instead of ETH. The `_payoutWithStethFallback` function handles this gracefully but it is an unexpected admin lever.

Severity: Medium — not a rug since stETH is equivalent value, but it is an admin vector that degrades UX and breaks the implied ETH-first payout guarantee.

---

## Suggested Phase Build Order for Adversarial Audit

Based on architecture dependencies, the correct ordering is:

1. **Gas analysis first** — Gas bounds determine whether Sybil attacks are feasible and constrain DoS analysis scope. Without knowing DAILY_ETH_MAX_WINNERS and confirming worst-case paths, Sybil analysis is incomplete.

2. **CEI / accounting invariant** — `claimablePool` divergence from `sum(claimableWinnings)` is a foundational invariant. Verify _creditClaimable call sites before analyzing any downstream reentrancy claims. This is the largest v1.0 gap (Phase 4, 8 of 9 plans unexecuted).

3. **Reentrancy analysis** — Build from CEI proof. If invariant holds, reentrancy surface is limited to the specific external call sites documented above. If invariant is broken, reentrancy window widens.

4. **Sybil + MEV modeling** — Uses gas bounds from step 1. Models cost to execute attacks across realistic player counts.

5. **Admin power map** — Documents CREATOR capabilities against the 3-day stall window, VRF manipulation, and liquidity controls. Builds on understanding of game-halt vectors from Sybil analysis.

6. **VRF/RNG security** — Final layer: requestId matching, nudge influence model, mid-day lootbox race conditions. References CEI findings from steps 2 and 3.

7. **Synthesis report** — Consolidates all findings with severity ratings and remediation guidance (plan 07-05 from v1.0).

---

## Sources

- Direct source analysis: `contracts/DegenerusGame.sol` (lines 1-2750+)
- Direct source analysis: `contracts/modules/DegenerusGameAdvanceModule.sol` (lines 1-1247)
- Direct source analysis: `contracts/modules/DegenerusGameJackpotModule.sol` (lines 1-150+)
- Direct source analysis: `contracts/modules/DegenerusGameEndgameModule.sol` (lines 1-150+)
- Direct source analysis: `contracts/modules/DegenerusGamePayoutUtils.sol` (full)
- Direct source analysis: `contracts/modules/DegenerusGameGameOverModule.sol` (lines 1-80+)
- Direct source analysis: `contracts/storage/DegenerusGameStorage.sol` (full layout, lines 1-550)
- Direct source analysis: `contracts/DegenerusAdmin.sol` (lines 1-350+)
- Confidence: HIGH — all claims derived directly from source code

---
*Architecture research for: Degenerus Protocol adversarial audit (v2.0)*
*Researched: 2026-03-04*
