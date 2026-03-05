# Function Selector Collision Analysis

**Phase:** 31-01 -- Cross-Contract Composition Analysis
**Generated:** 2026-03-05
**Source:** `forge inspect <Module> methodIdentifiers` for all 10 modules

## Selector Inventory

All function selectors extracted from all 10 delegatecall modules:

### AdvanceModule (8 selectors)
| Selector | Function |
|----------|----------|
| 75b5e924 | advanceGame() |
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| 1fe543e3 | rawFulfillRandomWords(uint256,uint256[]) |
| b9073281 | requestLootboxRng() |
| e068fdb5 | reverseFlip() |
| 049d4020 | updateVrfCoordinatorAndSub(address,uint256,bytes32) |
| 06349d97 | wireVrf(address,uint256,bytes32) |

### MintModule (7 selectors)
| Selector | Function |
|----------|----------|
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| e0a53bd7 | processFutureTicketBatch(uint24) |
| 3f298725 | purchase(address,uint256,uint256,bytes32,uint8) |
| 43886aaf | purchaseBurnieLootbox(address,uint256) |
| 4babe387 | purchaseCoin(address,uint256,uint256) |
| 105ea8e6 | recordMintData(address,uint24,uint32) |

### WhaleModule (6 selectors)
| Selector | Function |
|----------|----------|
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| 7d044328 | handleDeityPassTransfer(address,address) |
| e1e124c5 | purchaseDeityPass(address,uint8) |
| a86176fa | purchaseLazyPass(address) |
| dbf15de3 | purchaseWhaleBundle(address,uint256) |

### LootboxModule (7 selectors)
| Selector | Function |
|----------|----------|
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| 7e067934 | deityBoonSlots(address) |
| 64759067 | issueDeityBoon(address,address,uint8) |
| 4b7b467f | openBurnieLootBox(address,uint48) |
| ca09b1f8 | openLootBox(address,uint48) |
| e3eb359e | resolveLootboxDirect(address,uint256,uint256) |

### DegeneretteModule (5 selectors)
| Selector | Function |
|----------|----------|
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| b0fbe56e | placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8) |
| 5ba5befd | placeFullTicketBetsFromAffiliateCredit(address,uint128,uint8,uint32,uint8) |
| d62ff33c | resolveBets(address,uint64[]) |

### BoonModule (7 selectors)
| Selector | Function |
|----------|----------|
| 98a34e70 | checkAndClearExpiredBoon(address) |
| ebd82faf | consumeActivityBoon(address) |
| 9a0e1436 | consumeCoinflipBoon(address) |
| 01738ebd | consumeDecimatorBoost(address) |
| ef8c2c9f | consumePurchaseBoost(address) |
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |

### DecimatorModule (9 selectors)
| Selector | Function |
|----------|----------|
| c15cc2f3 | claimDecimatorJackpot(uint24) |
| cb8725db | consumeDecClaim(address,uint24) |
| 816f5ee7 | creditDecJackpotClaim(address,uint256,uint256) |
| e3962c02 | creditDecJackpotClaimBatch(address[],uint256[],uint256) |
| 7f8de5f3 | decClaimable(address,uint24) |
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| bd225b88 | recordDecBurn(address,uint24,uint8,uint256,uint256) |
| 275d3a40 | runDecimatorJackpot(uint256,uint24,uint256) |

### JackpotModule (9 selectors)
| Selector | Function |
|----------|----------|
| ecc00965 | awardFinalDayDgnrsReward(uint24,uint256) |
| f69e361d | consolidatePrizePools(uint24,uint256) |
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| 7a50cdf5 | payDailyCoinJackpot(uint24,uint256) |
| 2ef8c646 | payDailyJackpot(bool,uint24,uint256) |
| b1c9ed2d | payDailyJackpotCoinAndTickets(uint256) |
| 2ff3118b | processTicketBatch(uint24) |
| a56efd97 | runTerminalJackpot(uint256,uint24,uint256) |

### EndgameModule (5 selectors)
| Selector | Function |
|----------|----------|
| 210ff5ec | claimWhalePass(address) |
| bdb337d1 | gameOver() |
| 6fd5ae15 | level() |
| 0151fb53 | rewardTopAffiliate(uint24) |
| 9215a840 | runRewardJackpots(uint24,uint256) |

### GameOverModule (4 selectors)
| Selector | Function |
|----------|----------|
| bdb337d1 | gameOver() |
| 68740da8 | handleFinalSweep() |
| 249ae441 | handleGameOverDrain(uint48) |
| 6fd5ae15 | level() |

## Collision Check Results

### Shared Selectors Across Modules

Two selectors appear in ALL 10 modules:

| Selector | Function | Modules | Collision? |
|----------|----------|---------|------------|
| bdb337d1 | gameOver() | ALL 10 | **NO** -- Same function signature, inherited from DegenerusGameStorage. Not a collision. |
| 6fd5ae15 | level() | ALL 10 | **NO** -- Same function signature, inherited from DegenerusGameStorage. Not a collision. |

These are inherited view functions from DegenerusGameStorage. They have identical signatures and identical implementations across all modules. They are NOT used by DegenerusGame's dispatch (DegenerusGame accesses `gameOver` and `level` directly as storage variables, not via delegatecall).

### Unique Selectors (excluding gameOver/level)

Total unique module-specific selectors: 47

After removing the 2 shared inherited selectors (gameOver, level), all remaining 47 selectors are **unique across all modules**. Zero collisions.

**Verification method:** All 47 non-shared selectors were compared pairwise. No 4-byte selector value appears in more than one module (excluding gameOver/level).

### Complete Collision Matrix

```
ADV  MINT WHALE LOOT  DEG  BOON  DEC  JACK  END  OVER
ADV   -   GO,L  GO,L  GO,L GO,L  GO,L GO,L  GO,L GO,L GO,L
MINT  -    -    GO,L  GO,L GO,L  GO,L GO,L  GO,L GO,L GO,L
WHALE -    -     -    GO,L GO,L  GO,L GO,L  GO,L GO,L GO,L
LOOT  -    -     -     -   GO,L  GO,L GO,L  GO,L GO,L GO,L
DEG   -    -     -     -    -    GO,L GO,L  GO,L GO,L GO,L
BOON  -    -     -     -    -     -   GO,L  GO,L GO,L GO,L
DEC   -    -     -     -    -     -    -    GO,L GO,L GO,L
JACK  -    -     -     -    -     -    -     -   GO,L GO,L
END   -    -     -     -    -     -    -     -    -   GO,L
OVER  -    -     -     -    -     -    -     -    -    -

GO = gameOver() [bdb337d1] -- inherited, same signature, NOT a collision
L  = level() [6fd5ae15] -- inherited, same signature, NOT a collision
```

**Result: ZERO collisions across all module boundaries.**

## Dispatch Verification

DegenerusGame.sol dispatches each delegatecall using `abi.encodeWithSelector(IModule.function.selector, ...)`. Each dispatch was verified:

| DegenerusGame Function | Target Module | Dispatched Selector | Correct? |
|------------------------|---------------|---------------------|----------|
| advanceGame() | ADV | IDegenerusGameAdvanceModule.advanceGame.selector | YES |
| wireVrf() | ADV | IDegenerusGameAdvanceModule.wireVrf.selector | YES |
| purchase() | MINT | IDegenerusGameMintModule.purchase.selector | YES |
| purchaseCoin() | MINT | IDegenerusGameMintModule.purchaseCoin.selector | YES |
| purchaseBurnieLootbox() | MINT | IDegenerusGameMintModule.purchaseBurnieLootbox.selector | YES |
| purchaseWhaleBundle() | WHALE | IDegenerusGameWhaleModule.purchaseWhaleBundle.selector | YES |
| purchaseLazyPass() | WHALE | IDegenerusGameWhaleModule.purchaseLazyPass.selector | YES |
| purchaseDeityPass() | WHALE | IDegenerusGameWhaleModule.purchaseDeityPass.selector | YES |
| onDeityPassTransfer() | WHALE | IDegenerusGameWhaleModule.handleDeityPassTransfer.selector | YES |
| openLootBox() | LOOT | IDegenerusGameLootboxModule.openLootBox.selector | YES |
| openBurnieLootBox() | LOOT | IDegenerusGameLootboxModule.openBurnieLootBox.selector | YES |
| issueDeityBoon() | LOOT | IDegenerusGameLootboxModule.issueDeityBoon.selector | YES |
| placeFullTicketBets() | DEG | IDegenerusGameDegeneretteModule.placeFullTicketBets.selector | YES |
| placeFullTicketBetsFromAffiliateCredit() | DEG | IDegenerusGameDegeneretteModule.placeFullTicketBetsFromAffiliateCredit.selector | YES |
| resolveDegeneretteBets() | DEG | IDegenerusGameDegeneretteModule.resolveBets.selector | YES |
| consumeCoinflipBoon() | BOON | IDegenerusGameBoonModule.consumeCoinflipBoon.selector | YES |
| consumeDecimatorBoon() | BOON | IDegenerusGameBoonModule.consumeDecimatorBoost.selector | YES |
| consumePurchaseBoost() | BOON | IDegenerusGameBoonModule.consumePurchaseBoost.selector | YES |
| updateVrfCoordinatorAndSub() | ADV | IDegenerusGameAdvanceModule.updateVrfCoordinatorAndSub.selector | YES |
| requestLootboxRng() | ADV | IDegenerusGameAdvanceModule.requestLootboxRng.selector | YES |
| reverseFlip() | ADV | IDegenerusGameAdvanceModule.reverseFlip.selector | YES |
| rawFulfillRandomWords() | ADV | IDegenerusGameAdvanceModule.rawFulfillRandomWords.selector | YES |
| claimWhalePass() | END | IDegenerusGameEndgameModule.claimWhalePass.selector | YES |
| creditDecJackpotClaimBatch() | DEC | IDegenerusGameDecimatorModule.creditDecJackpotClaimBatch.selector | YES |
| creditDecJackpotClaim() | DEC | IDegenerusGameDecimatorModule.creditDecJackpotClaim.selector | YES |
| recordDecBurn() | DEC | IDegenerusGameDecimatorModule.recordDecBurn.selector | YES |
| runDecimatorJackpot() | DEC | IDegenerusGameDecimatorModule.runDecimatorJackpot.selector | YES |
| runTerminalJackpot() | JACK | IDegenerusGameJackpotModule.runTerminalJackpot.selector | YES |
| consumeDecClaim() | DEC | IDegenerusGameDecimatorModule.consumeDecClaim.selector | YES |
| claimDecimatorJackpot() | DEC | IDegenerusGameDecimatorModule.claimDecimatorJackpot.selector | YES |
| _recordMintDataModule() | MINT | IDegenerusGameMintModule.recordMintData.selector | YES |

**All 31 dispatch sites route to the correct module with the correct selector.**

## Conclusion

**Zero function selector collisions found across all 10 delegatecall module boundaries.**

The only shared selectors (gameOver: `bdb337d1`, level: `6fd5ae15`) are inherited from DegenerusGameStorage with identical signatures and implementations. They are view functions accessed directly by DegenerusGame (not via delegatecall dispatch), so they pose no routing risk.

All 31 delegatecall dispatch sites in DegenerusGame.sol use interface-typed selectors (`IModule.function.selector`) ensuring compile-time correctness. No manual 4-byte encoding is used anywhere.

**Risk: NONE.** Selector collision is not an attack vector for this protocol.
