# Feature Landscape

**Domain:** Solidity delegatecall module consolidation + storage slot repacking
**Researched:** 2026-04-02
**Milestone:** v16.0 Module Consolidation & Storage Repack

## Table Stakes

Features that MUST ship for the milestone to be valid. Missing any = incomplete consolidation.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Absorb `runRewardJackpots` into JackpotModule | Eliminates EndgameModule's largest function; JackpotModule already inherits PayoutUtils and handles all other jackpot logic | **High** | ~260 lines including `_runBafJackpot`, `_addClaimableEth`, `_awardJackpotTickets`, `_jackpotTicketRoll`. Heavy internal dependency on PayoutUtils helpers (`_creditClaimable`, `_calcAutoRebuy`, `_queueWhalePassClaimCore`, `_queueLootboxTickets`). JackpotModule already inherits PayoutUtils -- direct code move. |
| Absorb `rewardTopAffiliate` into AdvanceModule | Small self-contained function (25 lines), only caller is AdvanceModule's `_rewardTopAffiliate` wrapper. Eliminates a delegatecall hop. | **Low** | Reads `affiliate.affiliateTop()`, calls `dgnrs.transferFromPool()` + `dgnrs.poolBalance()`, writes `levelDgnrsAllocation[lvl]`. All dependencies available via DegenerusGameStorage inheritance. AdvanceModule currently extends Storage directly (not PayoutUtils) -- this function needs zero PayoutUtils helpers, so it fits cleanly. |
| Absorb `claimWhalePass` into JackpotModule | Called via delegatecall from DegenerusGame; reads `whalePassClaims`, writes ticket ranges. JackpotModule already has ticket-queue access. | **Medium** | Uses `_applyWhalePassStats` (defined in Storage) and `_queueTicketRange` (defined in Storage). Needs no PayoutUtils helpers. Could also go in DegenerusGame directly, but JackpotModule is the natural home since whale passes are jackpot rewards. |
| Move `ticketsFullyProcessed` from slot 1 to slot 0 | Slot 0 has 2 bytes free (30/32 used). Bool = 1 byte. Fits. | **Low** | Move declaration after `compressedJackpotFlag` in slot 0. Slot 1 drops from 10 to 9 bytes used. |
| Move `gameOverPossible` from slot 1 to slot 0 | Slot 0 has 2 bytes free, need 2 bools = 2 bytes, fills slot 0 exactly to 32/32. | **Low** | Move declaration after `ticketsFullyProcessed` in new slot 0. Slot 0 becomes fully packed (32/32 bytes). |
| Downsize `currentPrizePool` from uint256 to uint128, pack into slot 1 | uint128 max = 3.4e38 wei = ~3.4e20 ETH. Total ETH supply is ~120M ETH. Massively safe. | **Medium** | Move `currentPrizePool` as uint128 into slot 1 alongside `purchaseStartDay` (6) + `ticketWriteSlot` (1) + `prizePoolFrozen` (1) + currentPrizePool (16) = 24 bytes. Kills slot 2 entirely. Every `currentPrizePool` read/write must change from uint256 to uint128. |
| Kill slot 2 | After packing currentPrizePool into slot 1, slot 2 is empty. `prizePoolsPacked` (was slot 3) becomes slot 2. All subsequent slots shift down by 1. | **Low** | No code references slots by number -- Solidity handles layout. But NatSpec slot comments throughout DegenerusGameStorage.sol must be updated. |
| Fix stale slot header comments | Slot header comments in DegenerusGameStorage.sol reference old layouts. Must reflect new packing. | **Low** | Pure documentation task. Must update the slot layout diagram at top of file and per-section headers. |
| Remove EndgameModule contract + deploy address | After all 3 functions absorbed, delete the .sol file and remove GAME_ENDGAME_MODULE from ContractAddresses.sol | **Low** | Also remove IDegenerusGameEndgameModule interface. Update DegenerusGameStorage NatSpec that lists module contracts. |
| Rewire AdvanceModule delegatecall sites | `_rewardTopAffiliate` and `_runRewardJackpots` in AdvanceModule currently delegatecall to EndgameModule. After absorption: `_rewardTopAffiliate` becomes inline code; `_runRewardJackpots` delegatecalls to JackpotModule instead. | **Medium** | AdvanceModule already delegatecalls JackpotModule for daily jackpots. Adding `runRewardJackpots` to that module is consistent. |
| Rewire DegenerusGame claimWhalePass delegatecall | `_claimWhalePassFor` in DegenerusGame delegatecalls EndgameModule. After absorption, delegatecall target changes to JackpotModule. | **Low** | Single-site change: ContractAddresses.GAME_ENDGAME_MODULE -> ContractAddresses.GAME_JACKPOT_MODULE, selector unchanged. |

## Differentiators

Features that add value beyond the minimum viable consolidation.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Inline `_rewardTopAffiliate` directly in AdvanceModule (no delegatecall) | Saves ~2,600 gas per level transition (delegatecall overhead eliminated). Function is only 25 lines with no PayoutUtils dependency. | **Low** | AdvanceModule extends DegenerusGameStorage which provides `affiliate`, `dgnrs`, and `levelDgnrsAllocation`. All constants (AFFILIATE_POOL_REWARD_BPS, AFFILIATE_DGNRS_LEVEL_BPS) move inline. Events must be declared in AdvanceModule. |
| Inline `claimWhalePass` directly in DegenerusGame (no delegatecall) | Saves ~2,600 gas per whale pass claim. Function is 20 lines, uses only Storage-level helpers. | **Medium** | Depends on `_applyWhalePassStats` and `_queueTicketRange` being accessible from DegenerusGame. Both are defined in DegenerusGameStorage (internal), so DegenerusGame inherits them. Would eliminate the delegatecall entirely. Trade-off: adds ~20 lines to an already large DegenerusGame contract. |

## Anti-Features

Features to explicitly NOT build as part of this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Repack slots 3+ (prizePoolsPacked, rngWordCurrent, etc.) | Slot renumbering beyond killing slot 2 risks introducing bugs for negligible gas savings. Full-width uint256 variables don't benefit from repacking. | Only repack slots 0-2 as specified. Let Solidity handle natural slot renumbering when slot 2 dies. |
| Change prizePoolsPacked encoding | Already optimally packed as two uint128s. Touching encoding risks cache-overwrite class bugs (BAF-class, proven dangerous in v4.4). | Leave encoding untouched. |
| Merge JackpotModule into AdvanceModule | Would create a monolithic module exceeding Spurious Dragon 24KB limit. AdvanceModule is already the largest module. | Keep them separate; delegatecall from AdvanceModule to JackpotModule is the established pattern. |
| Add new features alongside consolidation | Mixing structural refactoring with feature additions creates compound risk. Delta audit becomes intractable. | Pure consolidation milestone. Features belong in subsequent milestones. |
| Touch auto-rebuy logic during move | `_addClaimableEth` with its AutoRebuy integration is complex. Temptation to "clean up" during move. | Copy verbatim. Any auto-rebuy changes belong in a separate milestone with dedicated testing. |

## Feature Dependencies

```
Move ticketsFullyProcessed to slot 0 ──┐
Move gameOverPossible to slot 0 ───────┤
                                        ├──> Downsize currentPrizePool to uint128 in slot 1
                                        │         │
                                        │         └──> Kill slot 2
                                        │                   │
                                        │                   └──> Fix stale slot header comments
                                        │
Absorb runRewardJackpots ──────────────>├──> Rewire AdvanceModule delegatecall sites
Absorb rewardTopAffiliate ─────────────>│         │
Absorb claimWhalePass ────────────────>│         └──> Remove EndgameModule contract + deploy address
                                        │                   │
                                        │                   └──> Remove IDegenerusGameEndgameModule interface
Rewire DegenerusGame claimWhalePass ───>┘
```

**Two independent workstreams that can proceed in parallel:**
1. **Storage repack** (slots 0-2)
2. **Function redistribution** (EndgameModule elimination)

They converge at the end: removing EndgameModule and updating comments.

## Natural Homes for Each Function

### `runRewardJackpots` -> JackpotModule

**Why JackpotModule:**
- JackpotModule already inherits DegenerusGamePayoutUtils (which provides `_creditClaimable`, `_calcAutoRebuy`, `_queueWhalePassClaimCore`)
- JackpotModule already handles all other jackpot types (daily ETH, daily coin, daily tickets, earlybird, degenerette)
- `runRewardJackpots` calls `IDegenerusGame(address(this)).runDecimatorJackpot()` which routes through the game contract -- no coupling to EndgameModule-specific state
- AdvanceModule already delegatecalls JackpotModule via `ContractAddresses.GAME_JACKPOT_MODULE`
- All private helpers (`_runBafJackpot`, `_addClaimableEth`, `_awardJackpotTickets`, `_jackpotTicketRoll`) move together as a unit

**What moves:** `runRewardJackpots` (external), `_runBafJackpot` (private), `_addClaimableEth` (private), `_awardJackpotTickets` (private), `_jackpotTicketRoll` (private). Events: `AutoRebuyExecuted`, `RewardJackpotsSettled`. Constants: `SMALL_LOOTBOX_THRESHOLD`. Interface import: `IDegenerusJackpots` (for `jackpots.runBafJackpot`), `IDegenerusGame` (for `runDecimatorJackpot`). Library imports: `EntropyLib`, `PriceLookupLib` (JackpotModule already imports both).

### `rewardTopAffiliate` -> AdvanceModule (inline, no delegatecall)

**Why inline in AdvanceModule:**
- Only 25 lines of code
- Zero dependency on PayoutUtils -- uses only Storage-level interfaces (`affiliate`, `dgnrs`, `levelDgnrsAllocation`)
- Only caller is AdvanceModule's `_rewardTopAffiliate` private wrapper
- Saves delegatecall overhead (~2,600 gas) on every level transition
- AdvanceModule already imports IStakedDegenerusStonk and IDegenerusAffiliate via Storage

**What moves:** `rewardTopAffiliate` body inlined into AdvanceModule's existing `_rewardTopAffiliate` private function. Event: `AffiliateDgnrsReward` (declare in AdvanceModule). Constants: `AFFILIATE_POOL_REWARD_BPS` (100), `AFFILIATE_DGNRS_LEVEL_BPS` (500).

### `claimWhalePass` -> JackpotModule

**Why JackpotModule:**
- Whale passes are awarded by BAF jackpot logic (which is moving to JackpotModule)
- Uses `_applyWhalePassStats` and `_queueTicketRange` from Storage (available to all modules)
- JackpotModule already handles ticket distribution patterns
- DegenerusGame's `_claimWhalePassFor` already uses delegatecall pattern -- just retarget to JackpotModule

**What moves:** `claimWhalePass` (external), `WhalePassClaimed` event declaration.

## Storage Repack: Concrete Layout

### Current Layout

| Slot | Bytes Used | Contents |
|------|-----------|----------|
| 0 | 30/32 | levelStartTime(6) + dailyIdx(6) + rngRequestTime(6) + level(3) + jackpotPhaseFlag(1) + jackpotCounter(1) + lastPurchaseDay(1) + decWindowOpen(1) + rngLockedFlag(1) + phaseTransitionActive(1) + gameOver(1) + dailyJackpotCoinTicketsPending(1) + compressedJackpotFlag(1) |
| 1 | 10/32 | purchaseStartDay(6) + ticketWriteSlot(1) + ticketsFullyProcessed(1) + prizePoolFrozen(1) + gameOverPossible(1) |
| 2 | 32/32 | currentPrizePool (uint256) |

### Target Layout

| Slot | Bytes Used | Contents |
|------|-----------|----------|
| 0 | **32/32** | levelStartTime(6) + dailyIdx(6) + rngRequestTime(6) + level(3) + jackpotPhaseFlag(1) + jackpotCounter(1) + lastPurchaseDay(1) + decWindowOpen(1) + rngLockedFlag(1) + phaseTransitionActive(1) + gameOver(1) + dailyJackpotCoinTicketsPending(1) + compressedJackpotFlag(1) + **ticketsFullyProcessed(1)** + **gameOverPossible(1)** |
| 1 | **24/32** | purchaseStartDay(6) + ticketWriteSlot(1) + prizePoolFrozen(1) + **currentPrizePool(16 = uint128)** |
| ~~2~~ | **KILLED** | ~~currentPrizePool~~ -- absorbed into slot 1 |

**Gas impact:** Every `advanceGame` call touches slot 0 and slot 1. Packing `ticketsFullyProcessed` and `gameOverPossible` into slot 0 eliminates separate warm SLOADs when they are read alongside other slot-0 fields (already loaded). Killing slot 2 by packing `currentPrizePool` into slot 1 co-locates it with `prizePoolFrozen` and `purchaseStartDay`, which are frequently accessed in the same code paths.

## MVP Recommendation

**Phase 1 -- Storage repack (do first):**
1. Move `ticketsFullyProcessed` + `gameOverPossible` into slot 0
2. Downsize `currentPrizePool` to uint128, pack into slot 1
3. Update all slot header comments and layout diagram

**Phase 2 -- Function redistribution:**
1. Move `runRewardJackpots` + all private helpers to JackpotModule
2. Inline `rewardTopAffiliate` into AdvanceModule
3. Move `claimWhalePass` to JackpotModule
4. Rewire all delegatecall sites
5. Delete EndgameModule, interface, and ContractAddresses entry

**Rationale for this order:** Storage repack changes the slot layout, which affects `forge inspect` verification. Doing it first gives a clean baseline. Function redistribution is pure code movement with no storage layout impact (delegatecall modules share the same layout via inheritance).

**Defer:** Inlining `claimWhalePass` directly in DegenerusGame (differentiator). The delegatecall to JackpotModule is sufficient -- inlining saves gas but adds contract size to an already large Game contract.

## Sources

- Direct code analysis of DegenerusGameEndgameModule.sol, DegenerusGameJackpotModule.sol, DegenerusGameAdvanceModule.sol, DegenerusGamePayoutUtils.sol, DegenerusGameStorage.sol
- Inheritance chains verified: EndgameModule -> PayoutUtils -> Storage; JackpotModule -> PayoutUtils -> Storage; AdvanceModule -> Storage
- Storage slot layout from DegenerusGameStorage.sol header comments (lines 38-73)
- Delegatecall callsites traced via grep across all contracts/
