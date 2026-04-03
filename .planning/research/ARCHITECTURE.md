# Architecture Patterns

**Domain:** EndgameModule elimination and storage repack in delegatecall-based Solidity module system
**Researched:** 2026-04-02

## Current Architecture

### EndgameModule Integration Map

EndgameModule (`DegenerusGameEndgameModule`) extends `DegenerusGamePayoutUtils` (which extends `DegenerusGameStorage`). It exposes 3 external functions, all invoked via delegatecall:

```
DegenerusGame
  |
  +-- claimWhalePass(player)
  |     dispatched from DegenerusGame.sol:1640 (_claimWhalePassFor)
  |     callers: DegenerusGame.claimWhalePass (external, user-facing)
  |              DegenerusVault.sol:596 (via gamePlayer.claimWhalePass)
  |              StakedDegenerusStonk.sol:309,353 (via game.claimWhalePass(address(0)))
  |
  +-- AdvanceModule (delegatecall from Game)
        |
        +-- _runRewardJackpots(lvl, rngWord)    [AdvanceModule.sol:554]
        |     dispatched to GAME_ENDGAME_MODULE via delegatecall
        |     called at: level transition, after pool consolidation (line 359)
        |
        +-- _rewardTopAffiliate(lvl)            [AdvanceModule.sol:541]
              dispatched to GAME_ENDGAME_MODULE via delegatecall
              called at: end of jackpot phase (line 401), after final day cap reached
```

### Call Chain Complexity: runRewardJackpots

This is the most complex function. Its call chain involves a **delegatecall-to-external-call-to-delegatecall** trampoline:

```
advanceGame() [AdvanceModule, delegatecall context]
  -> _runRewardJackpots(lvl, rngWord) [AdvanceModule private]
    -> delegatecall EndgameModule.runRewardJackpots() [EndgameModule code, Game storage]
      -> _runBafJackpot() [private, uses _addClaimableEth, _awardJackpotTickets, etc.]
      -> IDegenerusGame(address(this)).runDecimatorJackpot()  [EXTERNAL CALL TO SELF]
        -> Game.runDecimatorJackpot() [Game.sol:1052, msg.sender==address(this) guard]
          -> delegatecall DecimatorModule.runDecimatorJackpot()
```

The `IDegenerusGame(address(this))` pattern exists because EndgameModule cannot directly delegatecall DecimatorModule (modules don't hold other module addresses as delegatecall targets -- only DegenerusGame does that routing). The self-call bounces back through Game's external function which routes to DecimatorModule.

### Storage Access Patterns by EndgameModule

**runRewardJackpots reads/writes:**
- `_getFuturePrizePool()` / `_setFuturePrizePool()` -- prizePoolsPacked (slot 3)
- `claimablePool` (slot 7)
- `level` (slot 0, read-only for auto-rebuy)
- `gameOver` (slot 0, read-only in claimWhalePass)
- `autoRebuyState[player]` (mapping)
- `claimableWinnings[player]` (mapping)
- `whalePassClaims[player]` (mapping)
- `_getNextPrizePool()` / `_setNextPrizePool()` -- prizePoolsPacked (slot 3)
- Various ticket queue writes via `_queueTickets`, `_queueLootboxTickets`, `_queueTicketRange`

**rewardTopAffiliate reads/writes:**
- `dgnrs.poolBalance()` / `dgnrs.transferFromPool()` -- external calls to sDGNRS
- `affiliate.affiliateTop()` -- external call to Affiliate contract
- `levelDgnrsAllocation[lvl]` (mapping write)

**claimWhalePass reads/writes:**
- `gameOver` (slot 0, read)
- `whalePassClaims[player]` (mapping read+write)
- `level` (slot 0, read)
- Ticket queue writes via `_queueTicketRange`
- `_applyWhalePassStats` -- writes to `whalePassStats` mapping

### Current Storage Layout (Slots 0-2)

```
SLOT 0 (30/32 bytes used):
  [0:6]   levelStartTime       uint48
  [6:12]  dailyIdx             uint48
  [12:18] rngRequestTime       uint48
  [18:21] level                uint24
  [21:22] jackpotPhaseFlag     bool
  [22:23] jackpotCounter       uint8
  [23:24] lastPurchaseDay      bool
  [24:25] decWindowOpen        bool
  [25:26] rngLockedFlag        bool
  [26:27] phaseTransitionActive bool
  [27:28] gameOver             bool
  [28:29] dailyJackpotCoinTicketsPending bool
  [29:30] compressedJackpotFlag uint8
  --- 2 bytes padding ---

SLOT 1 (10/32 bytes used):
  [0:6]   purchaseStartDay     uint48
  [6:7]   ticketWriteSlot      uint8
  [7:8]   ticketsFullyProcessed bool
  [8:9]   prizePoolFrozen      bool
  [9:10]  gameOverPossible     bool
  --- 22 bytes padding ---

SLOT 2 (32/32 bytes):
  [0:32]  currentPrizePool     uint256
```

## Recommended Architecture

### Function Redistribution Strategy

**Principle:** Move each function to the module whose parent class already provides the helpers it needs, minimizing new code and eliminating the EndgameModule contract entirely.

| Function | Target Module | Rationale |
|----------|--------------|-----------|
| `runRewardJackpots` | JackpotModule | Already extends PayoutUtils. BAF logic uses `_addClaimableEth`, `_awardJackpotTickets`, `_queueWhalePassClaimCore` -- all from PayoutUtils. Decimator self-call stays unchanged. JackpotModule is the natural home for jackpot distribution. |
| `rewardTopAffiliate` | AdvanceModule | Pure external calls to `dgnrs` and `affiliate` (both already constants in Storage). Single mapping write. No PayoutUtils dependency. AdvanceModule is the sole caller -- inlining avoids a delegatecall hop entirely. |
| `claimWhalePass` | JackpotModule | Uses `whalePassClaims` mapping, `_applyWhalePassStats`, `_queueTicketRange` -- all from Storage. But JackpotModule already writes `whalePassClaims` (line 1574). Keeping claim logic co-located with the write site is cleanest. |

### Why NOT Other Options

| Alternative | Why Rejected |
|-------------|-------------|
| Move all 3 to JackpotModule | `rewardTopAffiliate` has zero payout logic; it's purely affiliate DGNRS distribution. Putting it in JackpotModule adds conceptual noise to an already large module. |
| Move all 3 to AdvanceModule | AdvanceModule inherits DegenerusGameStorage directly (NOT PayoutUtils). Moving `runRewardJackpots` there would require either (a) changing AdvanceModule's parent to PayoutUtils, or (b) duplicating PayoutUtils helpers. Both are worse than JackpotModule. |
| Create a new smaller module | Adds deployment cost and another ContractAddresses entry. The point is elimination, not replacement. |
| Inline all 3 into DegenerusGame | Game.sol is already the largest contract. Inlining complex BAF logic there would push contract size toward the 24KB limit. |

### Detailed Redistribution

#### 1. rewardTopAffiliate -> AdvanceModule (INLINE)

This function is trivial (25 lines) and has a single caller (`_rewardTopAffiliate` in AdvanceModule). It makes external calls to `dgnrs` and `affiliate` (already Storage constants) and writes one mapping entry. **Inline directly into AdvanceModule**, eliminating the delegatecall wrapper entirely.

**Change type:** AdvanceModule MODIFIED
- Delete `_rewardTopAffiliate` private delegatecall wrapper
- Inline the function body at call site (or as a new private function in AdvanceModule)
- Move `AFFILIATE_POOL_REWARD_BPS` and `AFFILIATE_DGNRS_LEVEL_BPS` constants
- Move `AffiliateDgnrsReward` event

**Dependencies:** None on PayoutUtils. Uses only `dgnrs`, `affiliate`, `levelDgnrsAllocation` (all in Storage).

#### 2. runRewardJackpots -> JackpotModule (MOVE)

This is the heaviest function (~400 lines including private helpers). JackpotModule already extends PayoutUtils, giving it access to `_creditClaimable`, `_queueWhalePassClaimCore`, and `_calcAutoRebuy`.

**Change type:** JackpotModule MODIFIED, EndgameModule interface MODIFIED
- Move `runRewardJackpots`, `_addClaimableEth`, `_runBafJackpot`, `_awardJackpotTickets`, `_jackpotTicketRoll` to JackpotModule
- Move constants: `SMALL_LOOTBOX_THRESHOLD`
- Move events: `AutoRebuyExecuted`, `RewardJackpotsSettled`
- Update AdvanceModule's `_runRewardJackpots` wrapper to target `GAME_JACKPOT_MODULE` instead of `GAME_ENDGAME_MODULE`
- Update interface: Move `runRewardJackpots` from `IDegenerusGameEndgameModule` to `IDegenerusGameJackpotModule`

**The IDegenerusGame(address(this)).runDecimatorJackpot() self-call pattern is preserved unchanged.** This trampoline exists because delegatecall modules cannot directly delegatecall other modules -- only the Game contract routes. The call path becomes:

```
AdvanceModule._runRewardJackpots
  -> delegatecall JackpotModule.runRewardJackpots  (changed target)
    -> IDegenerusGame(address(this)).runDecimatorJackpot()  (unchanged)
      -> delegatecall DecimatorModule.runDecimatorJackpot()  (unchanged)
```

#### 3. claimWhalePass -> JackpotModule (MOVE)

Simple function (20 lines). JackpotModule already writes `whalePassClaims` during daily jackpot processing.

**Change type:** JackpotModule MODIFIED, DegenerusGame MODIFIED
- Move `claimWhalePass` to JackpotModule
- Move `WhalePassClaimed` event
- Update `DegenerusGame._claimWhalePassFor` to target `GAME_JACKPOT_MODULE` instead of `GAME_ENDGAME_MODULE`
- Update IDegenerusGameJackpotModule interface
- Remove from IDegenerusGameEndgameModule interface

### Storage Repack Design

#### Target Layout

```
SLOT 0 (32/32 bytes -- FULL):
  [0:6]   levelStartTime       uint48   (unchanged)
  [6:12]  dailyIdx             uint48   (unchanged)
  [12:18] rngRequestTime       uint48   (unchanged)
  [18:21] level                uint24   (unchanged)
  [21:22] jackpotPhaseFlag     bool     (unchanged)
  [22:23] jackpotCounter       uint8    (unchanged)
  [23:24] lastPurchaseDay      bool     (unchanged)
  [24:25] decWindowOpen        bool     (unchanged)
  [25:26] rngLockedFlag        bool     (unchanged)
  [26:27] phaseTransitionActive bool    (unchanged)
  [27:28] gameOver             bool     (unchanged)
  [28:29] dailyJackpotCoinTicketsPending bool (unchanged)
  [29:30] compressedJackpotFlag uint8   (unchanged)
  [30:31] ticketsFullyProcessed bool    (MOVED from slot 1)
  [31:32] gameOverPossible     bool     (MOVED from slot 1)

SLOT 1 (32/32 bytes -- repacked):
  [0:6]   purchaseStartDay     uint48   (unchanged position in slot)
  [6:7]   ticketWriteSlot      uint8    (unchanged position in slot)
  [7:8]   prizePoolFrozen      bool     (SHIFTED from byte 8 to byte 7)
  [8:24]  currentPrizePool     uint128  (MOVED from slot 2, downsized from uint256)
  --- 8 bytes padding ---

SLOT 2: ELIMINATED (was currentPrizePool uint256)
```

#### Why uint128 for currentPrizePool

uint128 max = ~3.4e38 wei = ~3.4e20 ETH. Total ETH supply is ~120M ETH = 1.2e26 wei. The prize pool for a single level cannot physically exceed total ETH supply. uint128 provides 12 orders of magnitude headroom beyond total ETH supply. This is the same reasoning already used for `prizePoolsPacked` (next+future pools are both uint128).

#### Access Pattern Impact by Module

| Module | Slot 0 Access | Slot 1 Access | Slot 2 Access | Impact |
|--------|--------------|--------------|--------------|--------|
| **AdvanceModule** | Heavy R/W (all FSM flags) | R/W ticketsFullyProcessed, gameOverPossible, purchaseStartDay | R/W currentPrizePool | ticketsFullyProcessed and gameOverPossible move to slot 0 -- **SAVES 1 SLOAD per advanceGame call** when reading these alongside other slot 0 flags. currentPrizePool moves to slot 1 -- neutral (still 1 SLOAD, different slot). Net: **gas improvement**. |
| **JackpotModule** | R level, gameOver, FSM flags | R ticketsFullyProcessed (now slot 0) | R/W currentPrizePool (now slot 1) | ticketsFullyProcessed reads co-locate with slot 0 reads. currentPrizePool R/W moves from dedicated slot to slot 1 sharing -- **requires uint128 masking on read/write**. |
| **MintModule** | R level, flags | R gameOverPossible (now slot 0), prizePoolFrozen (slot 1) | W currentPrizePool (indirect via pool writes) | gameOverPossible check co-locates with slot 0. |
| **LootboxModule** | R level | R gameOverPossible (now slot 0) | - | gameOverPossible moves to slot 0 -- cheaper co-read with level. |
| **DecimatorModule** | R level | R prizePoolFrozen (slot 1) | - | No change to access pattern. |
| **GameOverModule** | R/W gameOver, level | - | W currentPrizePool = 0 (now slot 1) | Needs updated write pattern for packed slot 1. |
| **DegenerusGame** | R various | R prizePoolFrozen | R currentPrizePool (views) | View function updated for uint128 extraction from slot 1. |

#### Critical: currentPrizePool Packing Requires Helper Functions

Currently `currentPrizePool` is a plain `uint256` variable with direct reads/writes everywhere. After packing into slot 1, **all access must go through helper functions** that mask/shift within the packed slot. This is the same pattern used for `prizePoolsPacked` (next+future pools).

Affected write sites:
- JackpotModule: `currentPrizePool -= dailyLootboxBudget` (line 353), `currentPrizePool -= paidDailyEth` (line 433), `currentPrizePool += ...` (lines 721, 732)
- GameOverModule: `currentPrizePool = 0` (lines 133, 145)

Affected read sites:
- JackpotModule: `uint256 poolSnapshot = currentPrizePool` (line 317), `currentPrizePool` in obligation checks (line 747)
- DegenerusGame: `currentPrizePoolView()` (line 2037), obligation calculation (line 2063)

All must convert to `_getCurrentPrizePool()` / `_setCurrentPrizePool()` helpers defined in DegenerusGameStorage.

### Component Boundaries After Consolidation

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **DegenerusGame** | Entry point, access control, delegatecall routing | All modules (delegatecall), external contracts |
| **AdvanceModule** | Game state machine, VRF lifecycle, level transitions, affiliate rewards (inlined) | JackpotModule (delegatecall), MintModule (delegatecall), DecimatorModule (via Game) |
| **JackpotModule** | All jackpot distribution (daily, BAF, reward), whale pass claims, pool consolidation | DecimatorModule (via Game self-call), Jackpots contract (external) |
| **DecimatorModule** | Decimator burn tracking, snapshot, claims | Called by Game (routed from JackpotModule/GameOverModule) |
| **MintModule** | Purchase processing, ticket minting, lootbox purchases | Various external contracts |
| **GameOverModule** | Terminal state, final jackpot, sweep | DecimatorModule (via Game), JackpotModule (via Game) |
| ~~EndgameModule~~ | **ELIMINATED** | N/A |

### Data Flow After Repack

```
Purchase ETH -> split to pools:
  nextPrizePool (slot 3 packed) ---level-transition---> currentPrizePool (slot 1 packed)
  futurePrizePool (slot 3 packed) --drawdown/BAF/dec--> claimablePool (slot 7)
  currentPrizePool (slot 1 packed) --daily-jackpot----> claimableWinnings[player]
```

## Build Order (Dependency-Aware)

### Phase 1: Storage Repack (Foundation)

Must come first because every subsequent change depends on the new layout.

1. Add `_getCurrentPrizePool()` / `_setCurrentPrizePool()` helpers to DegenerusGameStorage
2. Move `ticketsFullyProcessed` and `gameOverPossible` declarations to slot 0 position
3. Move `currentPrizePool` from uint256 slot 2 into uint128 packed in slot 1
4. Remove `prizePoolFrozen` gap (shift from byte 8 to byte 7 in slot 1)
5. Update slot header comments throughout DegenerusGameStorage.sol
6. Replace all direct `currentPrizePool` reads/writes with helper calls across ALL modules

**Why first:** All modules inherit Storage. Changing the layout in isolation before moving functions means each change is testable independently. If function moves happen first, the moved code would need to be changed twice (once for the move, once for the repack).

### Phase 2: Inline rewardTopAffiliate into AdvanceModule

Simplest move. Zero PayoutUtils dependency. Single caller.

1. Copy function body and constants into AdvanceModule
2. Replace delegatecall wrapper with direct inline
3. Move event declaration
4. Remove from IDegenerusGameEndgameModule interface

### Phase 3: Move runRewardJackpots + helpers to JackpotModule

The heavy lift. ~400 lines of code moving.

1. Move all 5 functions + constants + events to JackpotModule
2. Update AdvanceModule `_runRewardJackpots` wrapper: change target from `GAME_ENDGAME_MODULE` to `GAME_JACKPOT_MODULE`
3. Update IDegenerusGameJackpotModule interface with `runRewardJackpots` signature
4. Verify decimator self-call trampoline still works (no change needed -- `IDegenerusGame(address(this))` is address-agnostic)

### Phase 4: Move claimWhalePass to JackpotModule

Small move. Depends on Phase 3 being done (to avoid two separate migrations into JackpotModule).

1. Move function + event to JackpotModule
2. Update DegenerusGame._claimWhalePassFor: change target from `GAME_ENDGAME_MODULE` to `GAME_JACKPOT_MODULE`
3. Update IDegenerusGameJackpotModule interface
4. Remove from IDegenerusGameEndgameModule interface

### Phase 5: Eliminate EndgameModule

1. Delete `DegenerusGameEndgameModule.sol`
2. Delete `IDegenerusGameEndgameModule` from interfaces file
3. Remove `GAME_ENDGAME_MODULE` from ContractAddresses.sol
4. Remove EndgameModule from DegenerusGameStorage NatSpec header
5. Remove all stale references across codebase
6. Update deploy scripts (one fewer contract to deploy)

## Anti-Patterns to Avoid

### Anti-Pattern 1: Splitting the Move and Repack Across Multiple PRs Without a Test Gate
**What:** Doing the storage repack in one PR and function moves in another, with broken intermediate state.
**Why bad:** If slot 2 is eliminated but code still references `currentPrizePool` as uint256, the compiler will catch it -- but assembly blocks or `forge inspect` might not.
**Instead:** Each phase must be independently compilable and testable. Phase 1 (repack) must update ALL consumers before Phase 2 begins.

### Anti-Pattern 2: Forgetting the prizePoolFrozen Shift
**What:** Moving ticketsFullyProcessed and gameOverPossible out of slot 1 but leaving prizePoolFrozen at byte offset 8 with a gap at bytes 7-8.
**Why bad:** Wastes the freed bytes. The whole point is to make room for currentPrizePool in slot 1.
**Instead:** Shift prizePoolFrozen to byte 7 when ticketsFullyProcessed vacates byte 7.

### Anti-Pattern 3: Leaving the Decimator Self-Call Trampoline in EndgameModule's Former Location
**What:** After moving runRewardJackpots to JackpotModule, forgetting that `IDegenerusGame(address(this)).runDecimatorJackpot()` is address-independent.
**Why bad:** Nothing actually breaks -- `address(this)` always resolves to the Game contract regardless of which module's code is executing. But failing to verify this causes unnecessary worry.
**Instead:** Confirm: in delegatecall context, `address(this)` = DegenerusGame. The self-call routes through Game.runDecimatorJackpot which delegates to DecimatorModule. Module identity is irrelevant.

## Sources

- DegenerusGameStorage.sol: canonical storage layout (slots 0-2 verified by reading declaration order)
- DegenerusGameEndgameModule.sol: all 3 functions and their private helpers (571 lines total)
- DegenerusGameAdvanceModule.sol: delegatecall dispatch wrappers (lines 541-565), call sites (lines 359, 401)
- DegenerusGame.sol: claimWhalePass dispatch (lines 1635-1650), runDecimatorJackpot trampoline (lines 1052-1071)
- DegenerusGameJackpotModule.sol: PayoutUtils inheritance, existing whalePassClaims write (line 1574)
- DegenerusGamePayoutUtils.sol: _creditClaimable, _queueWhalePassClaimCore, _calcAutoRebuy helpers
- IDegenerusGameModules.sol: interface definitions for all modules
- Confidence: HIGH -- all findings verified directly from contract source code
