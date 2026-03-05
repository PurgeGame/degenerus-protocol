# Storage Slot Ownership Matrix

**Phase:** 31-01 -- Cross-Contract Composition Analysis
**Generated:** 2026-03-05
**Source:** `forge inspect DegenerusGame storageLayout` + manual module source analysis

## Slot Layout

All 10 delegatecall modules inherit `DegenerusGameStorage` and declare **no module-local storage**. All modules share identical slot assignments. There are no slot collisions by construction.

### Slot 0 (32 bytes) -- Timing, Batching, FSM

| Offset | Bytes | Type   | Name                          | Writers         | Readers           |
|--------|-------|--------|-------------------------------|-----------------|-------------------|
| 0      | 6     | uint48 | levelStartTime                | ADV             | ADV               |
| 6      | 6     | uint48 | dailyIdx                      | ADV             | ADV, MINT, WHALE  |
| 12     | 6     | uint48 | rngRequestTime                | ADV             | ADV               |
| 18     | 3     | uint24 | level                         | ADV             | ALL (read)        |
| 21     | 1     | bool   | jackpotPhaseFlag              | ADV             | ALL (read)        |
| 22     | 1     | uint8  | jackpotCounter                | ADV             | ADV               |
| 23     | 1     | uint8  | earlyBurnPercent              | ADV             | ADV, JACK         |
| 24     | 1     | bool   | poolConsolidationDone         | ADV             | ADV               |
| 25     | 1     | bool   | lastPurchaseDay               | ADV             | ADV, DegenerusGame|
| 26     | 1     | bool   | decWindowOpen                 | ADV             | DEC, DegenerusGame|
| 27     | 1     | bool   | rngLockedFlag                 | ADV             | ALL (guard checks)|
| 28     | 1     | bool   | phaseTransitionActive         | ADV             | ADV               |
| 29     | 1     | bool   | gameOver                      | OVER            | ALL (guard checks)|
| 30     | 1     | bool   | dailyJackpotCoinTicketsPending| ADV, JACK       | ADV, JACK         |
| 31     | 1     | uint8  | dailyEthBucketCursor          | JACK            | JACK              |

### Slot 1 (32 bytes) -- Phase, Price

| Offset | Bytes | Type    | Name                  | Writers   | Readers        |
|--------|-------|---------|-----------------------|-----------|----------------|
| 0      | 1     | uint8   | dailyEthPhase         | JACK      | JACK           |
| 1      | 1     | bool    | compressedJackpotFlag | ADV       | ADV, JACK      |
| 2      | 6     | uint48  | purchaseStartDay      | ADV       | ADV, MINT      |
| 8      | 16    | uint128 | price                 | ADV       | MINT, WHALE, DEG|

### Slots 2-8 -- Prize Pools, RNG, Budgets

| Slot | Type    | Name                     | Writers              | Readers           | SHARED-WRITE |
|------|---------|--------------------------|----------------------|-------------------|--------------|
| 2    | uint256 | currentPrizePool         | ADV, JACK, END, OVER | ADV, JACK, MINT   | **SHARED-WRITE** |
| 3    | uint256 | nextPrizePool            | ADV, MINT, JACK      | ADV, JACK         | **SHARED-WRITE** |
| 4    | uint256 | rngWordCurrent           | ADV                  | ADV, LOOT, DEC, DEG|              |
| 5    | uint256 | vrfRequestId             | ADV                  | ADV               |              |
| 6    | uint256 | totalFlipReversals       | ADV                  | ADV               |              |
| 7    | uint256 | dailyTicketBudgetsPacked | ADV, JACK            | ADV, JACK         | **SHARED-WRITE** |
| 8    | uint256 | dailyEthPoolBudget       | ADV, JACK            | JACK              | **SHARED-WRITE** |

### Slots 9-16 -- Claimable, Mint, Lootbox

| Slot | Type         | Name                     | Writers                 | Readers              | SHARED-WRITE |
|------|--------------|--------------------------|-------------------------|----------------------|--------------|
| 9    | mapping      | claimableWinnings        | JACK, DEC, END, OVER    | DegenerusGame (claim)| **SHARED-WRITE** |
| 10   | uint256      | claimablePool            | JACK, DEC, END, OVER, ADV| ADV, DegenerusGame  | **SHARED-WRITE** |
| 11   | mapping      | traitBurnTicket          | JACK, MINT              | JACK                 | **SHARED-WRITE** |
| 12   | mapping      | mintPacked_              | MINT, WHALE, BOON, MintStreakUtils | MINT, WHALE, DEG, ADV, BOON | **SHARED-WRITE** |
| 13   | mapping      | rngWordByDay             | ADV                     | ADV, LOOT, DegenerusGame |          |
| 14   | uint256      | lastPurchaseDayFlipTotal | DegenerusGame           | ADV                  |              |
| 15   | uint256      | lastPurchaseDayFlipTotalPrev | ADV                 | ADV                  |              |
| 16   | uint256      | futurePrizePool          | ADV, MINT, JACK         | ADV, JACK            | **SHARED-WRITE** |

### Slots 17-21 -- Ticket Queue, Cursors

| Slot | Type    | Name                    | Writers                        | Readers    | SHARED-WRITE |
|------|---------|-------------------------|--------------------------------|------------|--------------|
| 17   | mapping | ticketQueue             | MINT, WHALE, END, DegenerusGame| ADV, JACK, MINT | **SHARED-WRITE** |
| 18   | mapping | ticketsOwedPacked       | MINT, WHALE, END               | MINT       | **SHARED-WRITE** |
| 19:0 | uint32  | ticketCursor            | ADV, JACK                      | ADV, JACK  | **SHARED-WRITE** |
| 19:4 | uint24  | ticketLevel             | ADV                            | ADV        |              |
| 19:7 | uint16  | dailyEthWinnerCursor    | JACK                           | JACK       |              |
| 20   | uint256 | dailyCarryoverEthPool   | JACK                           | JACK       |              |
| 21:0 | uint16  | dailyCarryoverWinnerCap | JACK                           | JACK       |              |

### Slots 22-27 -- Lootbox, GameOver, Whale Pass

| Slot | Type    | Name                    | Writers           | Readers | SHARED-WRITE |
|------|---------|-------------------------|-------------------|---------|--------------|
| 22   | mapping | lootboxEth              | MINT, LOOT, DEC, DEG | LOOT | **SHARED-WRITE** |
| 23   | bool    | lootboxPresaleActive    | ADV               | MINT, LOOT |            |
| 24   | uint256 | lootboxEthTotal         | LOOT, DEC, MINT   | LOOT   | **SHARED-WRITE** |
| 25   | uint256 | lootboxPresaleMintEth   | MINT              | MINT   |              |
| 26:0 | uint48  | gameOverTime            | OVER              | OVER   |              |
| 26:6 | bool    | gameOverFinalJackpotPaid| OVER              | OVER   |              |
| 27   | mapping | whalePassClaims         | END               | END    |              |

### Slots 28-44 -- Boon State

| Slot | Type    | Name                  | Writers | Readers | SHARED-WRITE |
|------|---------|-----------------------|---------|---------|--------------|
| 28   | mapping | coinflipBoonDay       | BOON    | BOON    |              |
| 29   | mapping | lootboxBoon5Active    | BOON    | BOON, LOOT |          |
| 30   | mapping | lootboxBoon5Day       | BOON    | BOON    |              |
| 31   | mapping | lootboxBoon15Active   | BOON    | BOON, LOOT |          |
| 32   | mapping | lootboxBoon15Day      | BOON    | BOON    |              |
| 33   | mapping | lootboxBoon25Active   | BOON    | BOON, LOOT |          |
| 34   | mapping | lootboxBoon25Day      | BOON    | BOON    |              |
| 35   | mapping | whaleBoonDay          | BOON    | BOON    |              |
| 36   | mapping | whaleBoonDiscountBps  | BOON    | BOON, WHALE |          |
| 37   | mapping | activityBoonPending   | BOON    | BOON    |              |
| 38   | mapping | activityBoonDay       | BOON    | BOON    |              |
| 39   | mapping | autoRebuyState        | DegenerusGame | ADV |            |
| 40   | mapping | decimatorAutoRebuyDisabled | DegenerusGame | DEC |       |
| 41   | mapping | purchaseBoostBps      | BOON    | BOON    |              |
| 42   | mapping | purchaseBoostDay      | BOON    | BOON    |              |
| 43   | mapping | decimatorBoostBps     | BOON    | BOON    |              |
| 44   | mapping | coinflipBoonBps       | BOON    | BOON    |              |

### Slots 45-70+ -- Jackpot, Lootbox Extended, VRF, Deity

| Slot | Type    | Name                       | Writers    | Readers    |
|------|---------|----------------------------|------------|------------|
| 45   | packed  | lastDailyJackpot*          | JACK       | JACK       |
| 46   | mapping | lootboxEthBase             | MINT, LOOT | LOOT       |
| 47   | mapping | operatorApprovals          | DegenerusGame | DegenerusGame |
| 48   | packed  | ethPerkLevel/burniePerk... | ADV        | ADV        |
| 49   | mapping | levelPrizePool             | ADV        | DegenerusGame, JACK |
| 50   | mapping | affiliateDgnrsClaimedBy    | DegenerusGame | DegenerusGame |
| 51   | uint24  | perkExpectedCount          | ADV        | ADV        |
| 52-57| mappings| deityPass* (6 mappings)    | WHALE      | WHALE, BOON, DegenerusGame |
| 58-59| uint256 | earlybirdDgnrs*            | DegenerusGame | DegenerusGame |
| 60   | address | vrfCoordinator             | ADV        | ADV        |
| 61   | bytes32 | vrfKeyHash                 | ADV        | ADV        |
| 62   | uint256 | vrfSubscriptionId          | ADV        | ADV        |
| 63-70| various | lootboxRng* (8 slots)      | ADV, LOOT  | ADV, LOOT  |

## Shared-Write Variables

Variables written by 2+ modules are the composition risk points. Each is analyzed below:

| Variable             | Slot | Writers                  | Risk Level | Rationale |
|----------------------|------|--------------------------|------------|-----------|
| currentPrizePool     | 2    | ADV, JACK, END, OVER     | LOW | All writes occur within advanceGame() orchestration sequence -- sequential, not concurrent |
| nextPrizePool        | 3    | ADV, MINT, JACK          | LOW | MINT writes during purchase (separate tx); ADV/JACK write during advance (sequential) |
| dailyTicketBudgetsPacked | 7 | ADV, JACK               | LOW | Both within advanceGame() sequence, JACK reads after ADV sets |
| dailyEthPoolBudget   | 8    | ADV, JACK                | LOW | Same as above |
| claimableWinnings    | 9    | JACK, DEC, END, OVER     | LOW | All are additive (+=), different entry paths, no read-modify-write races |
| claimablePool        | 10   | JACK, DEC, END, OVER, ADV| LOW | All additive within orchestrated sequence |
| traitBurnTicket      | 11   | JACK, MINT               | LOW | Different levels, no overlap within tx |
| mintPacked_          | 12   | MINT, WHALE, BOON        | **MEDIUM** | 3 writers to same packed word. Separate entry points mitigate. See Plan 31-02 |
| futurePrizePool      | 16   | ADV, MINT, JACK          | LOW | MINT writes during purchase; ADV/JACK during advance (separate txs) |
| ticketQueue          | 17   | MINT, WHALE, END, Game   | LOW | Append-only (push to array), no truncation or overwrite |
| ticketsOwedPacked    | 18   | MINT, WHALE, END         | LOW | Per-player per-level, separate entry points |
| ticketCursor         | 19   | ADV, JACK                | LOW | Sequential within advanceGame() |
| lootboxEth           | 22   | MINT, LOOT, DEC, DEG     | LOW | Per-index per-player; MINT allocates, LOOT/DEC/DEG credit |
| lootboxEthTotal      | 24   | LOOT, DEC, MINT          | LOW | Additive accounting |

## Delegatecall Site Inventory

All 31 delegatecall sites in DegenerusGame.sol:

### External Entry Points (19 sites)

| # | Function | Target Module | Storage Written |
|---|----------|---------------|-----------------|
| 1 | advanceGame() | ADV | level, jackpotPhaseFlag, rngLockedFlag, currentPrizePool, nextPrizePool, futurePrizePool, claimablePool, ticketCursor, rngWordCurrent, vrfRequestId, + orchestrated sub-calls |
| 2 | wireVrf() | ADV | vrfCoordinator, vrfKeyHash, vrfSubscriptionId |
| 3 | purchase() | MINT | mintPacked_, nextPrizePool, futurePrizePool, ticketQueue, ticketsOwedPacked, lootboxEth, lootboxRng* |
| 4 | purchaseCoin() | MINT | mintPacked_, ticketQueue, ticketsOwedPacked |
| 5 | purchaseBurnieLootbox() | MINT | lootboxEth, lootboxRng* |
| 6 | purchaseWhaleBundle() | WHALE | mintPacked_, nextPrizePool, futurePrizePool, ticketQueue, ticketsOwedPacked, lootboxEth, deityPass* |
| 7 | purchaseLazyPass() | WHALE | mintPacked_, ticketQueue, ticketsOwedPacked |
| 8 | purchaseDeityPass() | WHALE | deityPass*, mintPacked_, ticketQueue, ticketsOwedPacked |
| 9 | onDeityPassTransfer() | WHALE | deityPass*, mintPacked_ |
| 10 | openLootBox() | LOOT | lootboxEth, lootboxEthTotal, claimableWinnings, claimablePool, boon state (via BOON sub-call) |
| 11 | openBurnieLootBox() | LOOT | (coin effects only, no ETH storage writes) |
| 12 | issueDeityBoon() | LOOT | deityBoonDay, deityBoonUsedMask, boon state |
| 13 | placeFullTicketBets() | DEG | degenerette bet state, lootboxEth |
| 14 | placeFullTicketBetsFromAffiliateCredit() | DEG | degenerette bet state |
| 15 | resolveDegeneretteBets() | DEG | claimableWinnings, claimablePool, lootboxEth (via LOOT sub-call) |
| 16 | consumeCoinflipBoon() | BOON | coinflipBoonBps, coinflipBoonDay |
| 17 | consumeDecimatorBoon() | BOON | decimatorBoostBps |
| 18 | consumePurchaseBoost() | BOON | purchaseBoostBps, purchaseBoostDay |
| 19 | updateVrfCoordinatorAndSub() | ADV | vrfCoordinator, vrfKeyHash, vrfSubscriptionId |

### Additional Entry Points (7 sites)

| # | Function | Target Module | Storage Written |
|---|----------|---------------|-----------------|
| 20 | requestLootboxRng() | ADV | lootboxRng* |
| 21 | reverseFlip() | ADV | totalFlipReversals |
| 22 | rawFulfillRandomWords() | ADV | rngWordCurrent, rngWordByDay, rngLockedFlag, lootboxRng* |
| 23 | claimWhalePass() | END | whalePassClaims, claimableWinnings, claimablePool, ticketQueue |
| 24 | creditDecJackpotClaimBatch() | DEC | claimableWinnings, claimablePool, lootboxEth |
| 25 | creditDecJackpotClaim() | DEC | claimableWinnings, claimablePool, lootboxEth |
| 26 | recordDecBurn() | DEC | decBurn mapping |
| 27 | claimDecimatorJackpot() | DEC | decBurn (claimed flag), claimableWinnings, claimablePool |

### Internal/Self-Call Sites (4 sites)

| # | Function | Target Module | Called From |
|---|----------|---------------|-------------|
| 28 | recordMintData() | MINT | DegenerusGame._recordMintDataModule (self-call from purchase flow) |
| 29 | runDecimatorJackpot() | DEC | Self-call from advanceGame orchestration |
| 30 | runTerminalJackpot() | JACK | Self-call from advanceGame orchestration |
| 31 | consumeDecClaim() | DEC | Self-call from advanceGame orchestration |

**Total: 31 delegatecall sites** (exceeds original 30 count by 1 -- the additional site is `consumeDecClaim` which was not counted in initial research).

## Composition Risk Assessment

### Architecture Mitigations

1. **Single storage source:** All modules inherit DegenerusGameStorage. No module declares local storage. Slot collision is structurally impossible.

2. **Sequential orchestration:** The AdvanceModule orchestrates multi-module sequences (JACK, MINT, END, OVER) within advanceGame(). All shared-write variables modified during advance are written sequentially by one module at a time. No concurrent write risk.

3. **Separate entry points for MINT vs WHALE:** The highest-risk shared variable (mintPacked_) is written by MINT and WHALE through separate external entry points. Within a single transaction, only one can execute for a given player (no call path chains both for the same player's mintPacked_).

4. **Additive-only patterns:** claimableWinnings and claimablePool are only ever incremented (+=) by modules, never decremented. Decrements happen only in DegenerusGame.claimWinnings (pull pattern, not delegatecall).

### Remaining Risk: mintPacked_ (MEDIUM)

The mintPacked_ mapping is the only MEDIUM risk. Three modules (MINT, WHALE, BOON) write to the same packed uint256 for a given player. The risk is mitigated by separate entry points, but the complexity of bit field packing means a shift/mask error could corrupt adjacent fields. This is analyzed in detail in Plan 31-02.

### Conclusion

**No storage slot collision is possible** in the current architecture. All shared-write variables are either (a) modified sequentially within advanceGame() orchestration, (b) additive-only (+= operations), or (c) accessed through separate external entry points. The mintPacked_ packed word is the single composition risk point requiring detailed bit-level verification (Plan 31-02).
