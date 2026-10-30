# EIP-170 module map

Generated from the compiler AST, inheritance order, ABI selectors and deployment aliases by
[generate-audit-references.py](../scripts/generate-audit-references.py). The tables enumerate
external/public entries, including generated getters. A route is a possible edge, not a promise
that every branch executes. Follow the destination host table for nested delegatecalls.

Game delegates retain Game storage; Craps lifecycle delegates retain CrapsBattle storage.
Ordinary external calls (including the stateless Craps engine) are separate call contexts.
An exposed worker selector does not imply permission to call that worker directly; inspect guards.

```sh
python3 scripts/generate-audit-references.py --output-dir "$AUDIT_SCRATCH/references"
python3 scripts/generate-audit-references.py --output-dir "$AUDIT_SCRATCH/references" --check
```

Set `AUDIT_SCRATCH` as in [Testing](TESTING.md). The compiler output stays in that directory.

## Game facade

### DegenerusGame

Deployment aliases: `GAME`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `acquiredBuyer(uint32)` (`0xedc0f18c`) | [GameFacade.acquiredBuyer](../contracts/modules/GameFacade.sol) | None |
| `adminStakeEthForStEth(uint256)` (`0x847aea94`) | [GameFacade.adminStakeEthForStEth](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`adminStakeEthForStEth` |
| `adminSwapEthForStEth(address,uint256)` (`0x7b01dc1e`) | [GameFacade.adminSwapEthForStEth](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`adminSwapEthForStEth` |
| `advanceDue()` (`0xc0000e3f`) | [GameFacade.advanceDue](../contracts/modules/GameFacade.sol) | None |
| `afkingFundingOf(address)` (`0x4bf2d128`) | [GameFacade.afkingFundingOf](../contracts/modules/GameFacade.sol) | None |
| `betDegenerette(uint32,uint8,uint128,uint8,uint8)` (`0x16c6bd96`) | [GameFacade.betDegenerette](../contracts/modules/GameFacade.sol) | [Eip170Degenerette](#eip170degenerette).`betDegenerette` |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `borrow(uint32,uint24,uint256,uint256)` (`0x03604169`) | [GameFacade.borrow](../contracts/modules/GameFacade.sol) | [Eip170Purchase](#eip170purchase).`borrow` |
| `bountyEligible(address)` (`0x3f53905e`) | [GameFacade.bountyEligible](../contracts/modules/GameFacade.sol) | None |
| `boxIndexComplete(uint48)` (`0x26841fed`) | [GameFacade.boxIndexComplete](../contracts/modules/GameFacade.sol) | None |
| `boxesPending()` (`0x76d3a34d`) | [GameFacade.boxesPending](../contracts/modules/GameFacade.sol) | None |
| `claimAffiliateDgnrs(uint32)` (`0x352ace58`) | [GameFacade.claimAffiliateDgnrs](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`claimAffiliateDgnrs` |
| `claimAffiliateDgnrs(uint32[])` (`0xd3bd6f6f`) | [GameFacade.claimAffiliateDgnrs](../contracts/modules/GameFacade.sol) | None |
| `claimAfkingFlip(uint32[])` (`0xaadb9666`) | [GameFacade.claimAfkingFlip](../contracts/modules/GameFacade.sol) | [Eip170Afking](#eip170afking).`claimAfkingFlip` |
| `claimBingo(uint32,uint24,uint8,uint32[8])` (`0x4543bd57`) | [GameFacade.claimBingo](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`claimBingo` |
| `claimClaimable(uint32)` (`0x23276f8d`) | [GameFacade.claimClaimable](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`claimClaimable` |
| `claimDeadVrf(uint32,uint256[])` (`0xe1b52c71`) | [GameFacade.claimDeadVrf](../contracts/modules/GameFacade.sol) | [Eip170Endgame](#eip170endgame).`claimDeadVrf` |
| `claimFoilMatch(uint32,uint256,uint256)` (`0xbb653777`) | [GameFacade.claimFoilMatch](../contracts/modules/GameFacade.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`claimFoilMatch` |
| `claimFoilMatchMany(uint32[],uint24[],uint8[])` (`0x2c77c55e`) | [GameFacade.claimFoilMatchMany](../contracts/modules/GameFacade.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`claimFoilMatchMany` |
| `claimGoldenTicket(uint32,uint24)` (`0x9dbc39f6`) | [GameFacade.claimGoldenTicket](../contracts/modules/GameFacade.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`claimGoldenTicket` |
| `claimWhalePass(uint32)` (`0x947219fc`) | [GameFacade.claimWhalePass](../contracts/modules/GameFacade.sol) | [Eip170Whale](#eip170whale).`claimWhalePass` |
| `claimWinnings(uint32,uint256)` (`0x3046f499`) | [GameFacade.claimWinnings](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`claimWinnings` |
| `claimWinningsStethFirst()` (`0xafbb79e8`) | [GameFacade.claimWinningsStethFirst](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`claimWinningsStethFirst` |
| `claimablePoolView()` (`0xb9b1adcb`) | [GameFacade.claimablePoolView](../contracts/modules/GameFacade.sol) | None |
| `claimableWinningsOf(address)` (`0x282f19b8`) | [GameFacade.claimableWinningsOf](../contracts/modules/GameFacade.sol) | None |
| `clearDebtNow(uint32)` (`0x23e87f7e`) | [GameFacade.clearDebtNow](../contracts/modules/GameFacade.sol) | [Eip170Purchase](#eip170purchase).`clearDebtNow` |
| `consumeCoinflipBoon_g2902(uint32)` (`0x000af7d3`) | [GameFacade.consumeCoinflipBoon_g2902](../contracts/modules/GameFacade.sol) | None |
| `consumeDecimatorBoon(uint32)` (`0x19c5bdb1`) | [GameFacade.consumeDecimatorBoon](../contracts/modules/GameFacade.sol) | [Eip170Boon](#eip170boon).`consumeDecimatorBoon` |
| `createSmurf(bytes32,uint8)` (`0xf4824be2`) | [GameFacade.createSmurf](../contracts/modules/GameFacade.sol) | [Eip170Purchase](#eip170purchase).`createSmurf` |
| `creditMiddayRng(address,uint256)` (`0xc319ce1a`) | [GameFacade.creditMiddayRng](../contracts/modules/GameFacade.sol) | [Eip170MinerRng](#eip170minerrng).`creditMiddayRng` |
| `creditRedemptionDirect(uint32,uint256)` (`0xca0519e7`) | [GameFacade.creditRedemptionDirect](../contracts/modules/GameFacade.sol) | [Eip170Lootbox](#eip170lootbox).`creditRedemptionDirect` |
| `currentDayView_g542950()` (`0x000002ea`) | [GameFacade.currentDayView_g542950](../contracts/modules/GameFacade.sol) | None |
| `currentLvl()` (`0x095e9593`) | [GameFacade.currentLvl](../contracts/modules/GameFacade.sol) | None |
| `currentPrizePoolView()` (`0x9a6a9109`) | [GameFacade.currentPrizePoolView](../contracts/modules/GameFacade.sol) | None |
| `currentWallDayView()` (`0xd63990d4`) | [GameFacade.currentWallDayView](../contracts/modules/GameFacade.sol) | None |
| `curseCountOf(address)` (`0x951b8f37`) | [GameFacade.curseCountOf](../contracts/modules/GameFacade.sol) | None |
| `dailyScheduleOpen_g214()` (`0x1ff1a440`) | [GameFacade.dailyScheduleOpen_g214](../contracts/modules/GameFacade.sol) | None |
| `dailySessionState()` (`0x2c44076f`) | [GameFacade.dailySessionState](../contracts/modules/GameFacade.sol) | None |
| `decimatorActive()` (`0x27078201`) | [GameFacade.decimatorActive](../contracts/modules/GameFacade.sol) | None |
| `decurse(uint32)` (`0x778b5824`) | [GameFacade.decurse](../contracts/modules/GameFacade.sol) | [Eip170Afking](#eip170afking).`decurse` |
| `degeneretteBetInfo(uint48,uint64)` (`0xe3dcb538`) | [GameFacade.degeneretteBetInfo](../contracts/modules/GameFacade.sol) | None |
| `degenesisCreditOf(address)` (`0x464cbcf2`) | [GameFacade.degenesisCreditOf](../contracts/modules/GameFacade.sol) | None |
| `deityBoonData(address)` (`0xf5082cee`) | [GameFacade.deityBoonData](../contracts/modules/GameFacade.sol) | None |
| `deityBoonDataById(uint32)` (`0x42767274`) | [GameFacade.deityBoonDataById](../contracts/modules/GameFacade.sol) | None |
| `depositAfkingFunding(uint32)` (`0x76cc141c`) | [GameFacade.depositAfkingFunding](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`depositAfkingFunding` |
| `drainAffiliateBases(uint256,uint256)` (`0x12bb1641`) | [GameFacade.drainAffiliateBases](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`drainAffiliateBases` |
| `emitDailyWinningTraits(uint256)` (`0x68a81770`) | [GameFacade.emitDailyWinningTraits](../contracts/modules/GameFacade.sol) | [Eip170Jackpot](#eip170jackpot).`emitDailyWinningTraits` |
| `entriesOwedView(uint24,address)` (`0x6a567760`) | [GameFacade.entriesOwedView](../contracts/modules/GameFacade.sol) | None |
| `ethMintStats(address)` (`0x163f6f70`) | [GameFacade.ethMintStats](../contracts/modules/GameFacade.sol) | None |
| `extsload_g2807007(bytes32)` (`0x0000025f`) | [GameFacade.extsload_g2807007](../contracts/modules/GameFacade.sol) | None |
| `floorAfkingStreakBase(uint32,uint16)` (`0x49e92b29`) | [GameFacade.floorAfkingStreakBase](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`floorAfkingStreakBase` |
| `futurePrizePoolView()` (`0xba5f711f`) | [GameFacade.futurePrizePoolView](../contracts/modules/GameFacade.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `gameOverTimestamp()` (`0x1133421d`) | [GameFacade.gameOverTimestamp](../contracts/modules/GameFacade.sol) | None |
| `getDailyHeroWager(uint24,uint8,uint8)` (`0x879ae8b9`) | [GameFacade.getDailyHeroWager](../contracts/modules/GameFacade.sol) | None |
| `getDailyHeroWinner(uint24)` (`0x84aa54cc`) | [GameFacade.getDailyHeroWinner](../contracts/modules/GameFacade.sol) | None |
| `getEntries(uint8,uint24,uint32,uint32,address)` (`0x61581a52`) | [GameFacade.getEntries](../contracts/modules/GameFacade.sol) | None |
| `getGrowth(uint24)` (`0x27434294`) | [GameFacade.getGrowth](../contracts/modules/GameFacade.sol) | None |
| `getPlayerPurchases(address)` (`0x181490da`) | [GameFacade.getPlayerPurchases](../contracts/modules/GameFacade.sol) | None |
| `getWinnings()` (`0x70b7596b`) | [GameFacade.getWinnings](../contracts/modules/GameFacade.sol) | None |
| `giveBoon(uint32,uint32,uint8)` (`0x281aaad8`) | [GameFacade.giveBoon](../contracts/modules/GameFacade.sol) | [Eip170Boon](#eip170boon).`giveBoon` |
| `hasDeityPass(address)` (`0x7c327d34`) | [GameFacade.hasDeityPass](../contracts/modules/GameFacade.sol) | None |
| `initProtocolDeity()` (`0xc8ff239c`) | [GameFacade.initProtocolDeity](../contracts/modules/GameFacade.sol) | [Eip170Boon](#eip170boon).`initProtocolDeity` |
| `initVrf(address,uint256,bytes32)` (`0xc7cd0e48`) | [GameFacade.initVrf](../contracts/modules/GameFacade.sol) | [Eip170Endgame](#eip170endgame).`initVrf` |
| `isFinalSwept()` (`0xfd287f01`) | [GameFacade.isFinalSwept](../contracts/modules/GameFacade.sol) | None |
| `isRngFulfilled()` (`0xabd9f3da`) | [GameFacade.isRngFulfilled](../contracts/modules/GameFacade.sol) | None |
| `jackpotDuration()` (`0xf3fff5ff`) | [GameFacade.jackpotDuration](../contracts/modules/GameFacade.sol) | None |
| `jackpotPhase()` (`0x9a0c6557`) | [GameFacade.jackpotPhase](../contracts/modules/GameFacade.sol) | None |
| `lastVrfProcessed()` (`0xeb9ade67`) | [GameFacade.lastVrfProcessed](../contracts/modules/GameFacade.sol) | None |
| `latestDailyResultDay()` (`0xf7055abf`) | [GameFacade.latestDailyResultDay](../contracts/modules/GameFacade.sol) | None |
| `livenessTriggered()` (`0x72d98d96`) | [GameFacade.livenessTriggered](../contracts/modules/GameFacade.sol) | None |
| `middayRngCredits(address)` (`0x0b7923ef`) | [GameFacade.middayRngCredits](../contracts/modules/GameFacade.sol) | None |
| `mineRun(uint32)` (`0x03431f36`) | [GameFacade.mineRun](../contracts/modules/GameFacade.sol) | [Eip170MinerRng](#eip170minerrng).`mineRun` |
| `minerAction()` (`0x45af5e2d`) | [GameFacade.minerAction](../contracts/modules/GameFacade.sol) | [Eip170MinerRng](#eip170minerrng).`minerAction` |
| `mintPackedFor(address)` (`0x4947e860`) | [GameFacade.mintPackedFor](../contracts/modules/GameFacade.sol) | None |
| `mintPackedOfId_g5372(uint32)` (`0x000b805a`) | [GameFacade.mintPackedOfId_g5372](../contracts/modules/GameFacade.sol) | None |
| `mintPrice()` (`0x6817c76c`) | [GameFacade.mintPrice](../contracts/modules/GameFacade.sol) | None |
| `nextMinerAction()` (`0x6ade4b77`) | [GameFacade.nextMinerAction](../contracts/modules/GameFacade.sol) | None |
| `nextPrizePoolView()` (`0x849c258c`) | [GameFacade.nextPrizePoolView](../contracts/modules/GameFacade.sol) | None |
| `payRecordSdgnrs(uint32,uint256)` (`0x207400a5`) | [GameFacade.payRecordSdgnrs](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`payRecordSdgnrs` |
| `playerActivityScore(address)` (`0x1d671cfb`) | [GameFacade.playerActivityScore](../contracts/modules/GameFacade.sol) | None |
| `playerActivityScoreById(uint32)` (`0xe869ad7d`) | [GameFacade.playerActivityScoreById](../contracts/modules/GameFacade.sol) | None |
| `playerActivityScoreCached(address)` (`0xb4ba4c48`) | [GameFacade.playerActivityScoreCached](../contracts/modules/GameFacade.sol) | None |
| `playerActivityScoreCachedById_g975(uint32)` (`0x20144d28`) | [GameFacade.playerActivityScoreCachedById_g975](../contracts/modules/GameFacade.sol) | None |
| `prizePoolTargetView()` (`0xfea12770`) | [GameFacade.prizePoolTargetView](../contracts/modules/GameFacade.sol) | None |
| `pullAfkingSteth(uint32,address,uint256)` (`0x1145ef7d`) | [GameFacade.pullAfkingSteth](../contracts/modules/GameFacade.sol) | [Eip170Afking](#eip170afking).`pullAfkingSteth` |
| `purchaseDegenesisBox(uint32,uint256)` (`0x28c6ca52`) | [GameFacade.purchaseDegenesisBox](../contracts/modules/GameFacade.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`buyDegenesisBox_g1442` |
| `purchaseDeityPass(uint32,uint8,bytes32)` (`0x0d359801`) | [GameFacade.purchaseDeityPass](../contracts/modules/GameFacade.sol) | [Eip170Whale](#eip170whale).`purchaseDeityPass` |
| `purchaseInfo_g1027()` (`0x1ffa73d9`) | [GameFacade.purchaseInfo_g1027](../contracts/modules/GameFacade.sol) | None |
| `purchaseLazyPass(uint32,bytes32)` (`0x0811f604`) | [GameFacade.purchaseLazyPass](../contracts/modules/GameFacade.sol) | [Eip170Whale](#eip170whale).`purchaseLazyPass` |
| `purchaseOrderFor(uint32,uint256,uint256,bytes32,uint8,bool)` (`0x0049ad2f`) | [GameFacade.purchaseOrderFor](../contracts/modules/GameFacade.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`purchaseWithFoil`; [Eip170Purchase](#eip170purchase).`purchase` |
| `purchaseWhalePass(uint32,uint256,bytes32)` (`0x9e2dbae4`) | [GameFacade.purchaseWhalePass](../contracts/modules/GameFacade.sol) | [Eip170Whale](#eip170whale).`purchaseWhalePass` |
| `raiseSmurfBaseAllowance(uint32,uint16)` (`0x9f244a6f`) | [GameFacade.raiseSmurfBaseAllowance](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`raiseSmurfBaseAllowance` |
| `rawFulfillRandomWords(uint256,uint256[])` (`0x1fe543e3`) | [GameFacade.rawFulfillRandomWords](../contracts/modules/GameFacade.sol) | None |
| `recordAfkingSecondary_g3316(uint32,uint16)` (`0x204154c4`) | [GameFacade.recordAfkingSecondary_g3316](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`recordAfkingSecondary_g3316` |
| `recordDecBurn_g1271(uint32,uint24,uint256,uint256,uint32)` (`0x205fb9a2`) | [GameFacade.recordDecBurn_g1271](../contracts/modules/GameFacade.sol) | [Eip170Decimator](#eip170decimator).`recordDecBurn_g1271` |
| `redeemFlip(uint32,uint256)` (`0x377a4803`) | [GameFacade.redeemFlip](../contracts/modules/GameFacade.sol) | [Eip170Purchase](#eip170purchase).`redeemFlip` |
| `redemptionReserve()` (`0xc05fb724`) | [GameFacade.redemptionReserve](../contracts/modules/GameFacade.sol) | None |
| `registerWalletIdentity(address)` (`0x78b5a06a`) | [GameFacade.registerWalletIdentity](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`registerWalletIdentity` |
| `registerWallet_g9539(address,bool)` (`0x0007480c`) | [GameFacade.registerWallet_g9539](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`registerWallet_g9539` |
| `resolveAccount_g7029(uint32,address)` (`0x20500d49`) | [GameFacade.resolveAccount_g7029](../contracts/modules/GameFacade.sol) | None |
| `resolveRedemptionLootbox(uint32,uint256,uint256,uint16,uint32)` (`0x85e304f0`) | [GameFacade.resolveRedemptionLootbox](../contracts/modules/GameFacade.sol) | [Eip170Lootbox](#eip170lootbox).`resolveRedemptionLootbox` |
| `retryRng()` (`0x5132993a`) | [GameFacade.retryRng](../contracts/modules/GameFacade.sol) | [Eip170MinerRng](#eip170minerrng).`retryRng` |
| `reverseFlip(uint256)` (`0xe24c82cf`) | [GameFacade.reverseFlip](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`reverseFlip` |
| `rngComplete()` (`0xe879ebd1`) | [GameFacade.rngComplete](../contracts/modules/GameFacade.sol) | None |
| `rngConsumerStage_g379()` (`0x0004b9e3`) | [GameFacade.rngConsumerStage_g379](../contracts/modules/GameFacade.sol) | None |
| `rngLocked()` (`0x0f3b90b5`) | [GameFacade.rngLocked](../contracts/modules/GameFacade.sol) | None |
| `rngNudgeQuote()` (`0xe81620df`) | [GameFacade.rngNudgeQuote](../contracts/modules/GameFacade.sol) | None |
| `rngWordForDay(uint24)` (`0xd12c6c79`) | [GameFacade.rngWordForDay](../contracts/modules/GameFacade.sol) | None |
| `runBafJackpot(uint256,uint24,uint256)` (`0x4181af8e`) | [GameFacade.runBafJackpot](../contracts/modules/GameFacade.sol) | [Eip170JackpotDraw](#eip170jackpotdraw).`runBafJackpot` |
| `runDecimatorJackpot(uint256,uint24,uint256)` (`0x275d3a40`) | [GameFacade.runDecimatorJackpot](../contracts/modules/GameFacade.sol) | [Eip170Decimator](#eip170decimator).`runDecimatorJackpot` |
| `runTerminalJackpotWork(uint256,uint24,uint256,uint256)` (`0x45f2191b`) | [GameFacade.runTerminalJackpotWork](../contracts/modules/GameFacade.sol) | [Eip170Jackpot](#eip170jackpot).`runTerminalJackpotWork` |
| `sampleFarFutureTickets(uint256,uint24,uint24)` (`0x31e724b5`) | [GameFacade.sampleFarFutureTickets](../contracts/modules/GameFacade.sol) | None |
| `sampleTraitEntries(bool,uint8,uint256)` (`0x344e5d8c`) | [GameFacade.sampleTraitEntries](../contracts/modules/GameFacade.sol) | None |
| `setCrapsRngPending_g1406(uint48,bool)` (`0x0007265c`) | [GameFacade.setCrapsRngPending_g1406](../contracts/modules/GameFacade.sol) | None |
| `setLootboxRngThreshold(uint256)` (`0xb2542c6a`) | [GameFacade.setLootboxRngThreshold](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`setLootboxRngThreshold` |
| `setMiddayMaxBasefee(uint256)` (`0xfd719d0b`) | [GameFacade.setMiddayMaxBasefee](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`setMiddayMaxBasefee` |
| `setOperatorApproval(uint32,address,bool)` (`0x4deb7c36`) | [GameFacade.setOperatorApproval](../contracts/modules/GameFacade.sol) | [Eip170Actions](#eip170actions).`setOperatorApproval` |
| `setThanosLevel(uint24,uint8)` (`0x6b20479b`) | [GameFacade.setThanosLevel](../contracts/modules/GameFacade.sol) | [Eip170Endgame](#eip170endgame).`setThanosLevel` |
| `smite(uint256,uint32)` (`0xd470bfde`) | [GameFacade.smite](../contracts/modules/GameFacade.sol) | [Eip170Afking](#eip170afking).`smite` |
| `spendDegenesis(uint32,bool,uint256,uint256,uint256)` (`0x551708ad`) | [GameFacade.spendDegenesis](../contracts/modules/GameFacade.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`spendDegenesis` |
| `subscribe(uint32,bool,uint8,uint256)` (`0x4ee59ad5`) | [GameFacade.subscribe](../contracts/modules/GameFacade.sol) | [Eip170Afking](#eip170afking).`subscribe` |
| `subscriberSetLength()` (`0x01d596b7`) | [GameFacade.subscriberSetLength](../contracts/modules/GameFacade.sol) | None |
| `sweepAccounts(uint32[])` (`0xe85e8a9b`) | [GameFacade.sweepAccounts](../contracts/modules/GameFacade.sol) | [Eip170Purchase](#eip170purchase).`sweepAccounts` |
| `updateVrfCoordinatorAndSub(address,uint256,bytes32,uint32)` (`0x6c812791`) | [GameFacade.updateVrfCoordinatorAndSub](../contracts/modules/GameFacade.sol) | [Eip170Endgame](#eip170endgame).`updateVrfCoordinatorAndSub` |
| `walletIdOf_g3120(address)` (`0x00045daf`) | [GameFacade.walletIdOf_g3120](../contracts/modules/GameFacade.sol) | None |
| `walletIdentityOf_g8516(address)` (`0x202faa59`) | [GameFacade.walletIdentityOf_g8516](../contracts/modules/GameFacade.sol) | None |
| `whalePassClaimAmount(address)` (`0x344d3f57`) | [GameFacade.whalePassClaimAmount](../contracts/modules/GameFacade.sol) | None |
| `withdrawAfkingFunding(uint32,uint256)` (`0x4f00fd3f`) | [GameFacade.withdrawAfkingFunding](../contracts/modules/GameFacade.sol) | [Eip170Purchase](#eip170purchase).`withdrawAfkingFunding` |
| `yieldAccumulatorView()` (`0x3a6eec6c`) | [GameFacade.yieldAccumulatorView](../contracts/modules/GameFacade.sol) | None |
| `yieldPoolView()` (`0x898a5ac3`) | [GameFacade.yieldPoolView](../contracts/modules/GameFacade.sol) | None |

## Game delegates

### Eip170Actions

Deployment aliases: `GAME_ACTIONS_MODULE, GAME_BINGO_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `adminStakeEthForStEth(uint256)` (`0x847aea94`) | [GameActionEntries.adminStakeEthForStEth](../contracts/modules/GameActionEntries.sol) | None |
| `adminSwapEthForStEth(address,uint256)` (`0x7b01dc1e`) | [GameActionEntries.adminSwapEthForStEth](../contracts/modules/GameActionEntries.sol) | None |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `claimAffiliateDgnrs(uint32)` (`0x352ace58`) | [GameBingoEntries.claimAffiliateDgnrs](../contracts/modules/GameBingoEntries.sol) | None |
| `claimBingo(uint32,uint24,uint8,uint32[8])` (`0x4543bd57`) | [GameBingoEntries.claimBingo](../contracts/modules/GameBingoEntries.sol) | None |
| `claimClaimable(uint32)` (`0x23276f8d`) | [GameActionEntries.claimClaimable](../contracts/modules/GameActionEntries.sol) | None |
| `claimWinnings(uint32,uint256)` (`0x3046f499`) | [GameActionEntries.claimWinnings](../contracts/modules/GameActionEntries.sol) | None |
| `claimWinningsStethFirst()` (`0xafbb79e8`) | [GameActionEntries.claimWinningsStethFirst](../contracts/modules/GameActionEntries.sol) | None |
| `depositAfkingFunding(uint32)` (`0x76cc141c`) | [GameActionEntries.depositAfkingFunding](../contracts/modules/GameActionEntries.sol) | None |
| `drainAffiliateBases(uint256,uint256)` (`0x12bb1641`) | [GameActionEntries.drainAffiliateBases](../contracts/modules/GameActionEntries.sol) | None |
| `floorAfkingStreakBase(uint32,uint16)` (`0x49e92b29`) | [GameActionEntries.floorAfkingStreakBase](../contracts/modules/GameActionEntries.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `payRecordSdgnrs(uint32,uint256)` (`0x207400a5`) | [GameActionEntries.payRecordSdgnrs](../contracts/modules/GameActionEntries.sol) | None |
| `raiseSmurfBaseAllowance(uint32,uint16)` (`0x9f244a6f`) | [GameAllowanceEntries.raiseSmurfBaseAllowance](../contracts/modules/GameAllowanceEntries.sol) | None |
| `recordAfkingSecondary_g3316(uint32,uint16)` (`0x204154c4`) | [GameActionEntries.recordAfkingSecondary_g3316](../contracts/modules/GameActionEntries.sol) | None |
| `registerWalletIdentity(address)` (`0x78b5a06a`) | [GameActionEntries.registerWalletIdentity](../contracts/modules/GameActionEntries.sol) | None |
| `registerWallet_g9539(address,bool)` (`0x0007480c`) | [GameActionEntries.registerWallet_g9539](../contracts/modules/GameActionEntries.sol) | None |
| `reverseFlip(uint256)` (`0xe24c82cf`) | [GameActionEntries.reverseFlip](../contracts/modules/GameActionEntries.sol) | None |
| `setLootboxRngThreshold(uint256)` (`0xb2542c6a`) | [GameActionEntries.setLootboxRngThreshold](../contracts/modules/GameActionEntries.sol) | None |
| `setMiddayMaxBasefee(uint256)` (`0xfd719d0b`) | [GameActionEntries.setMiddayMaxBasefee](../contracts/modules/GameActionEntries.sol) | None |
| `setOperatorApproval(uint32,address,bool)` (`0x4deb7c36`) | [GameActionEntries.setOperatorApproval](../contracts/modules/GameActionEntries.sol) | None |

### Eip170Purchase

Deployment aliases: `GAME_PURCHASE_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `borrow(uint32,uint24,uint256,uint256)` (`0x03604169`) | [GamePurchaseEntries.borrow](../contracts/modules/GamePurchaseEntries.sol) | None |
| `clearDebtNow(uint32)` (`0x23e87f7e`) | [GamePurchaseEntries.clearDebtNow](../contracts/modules/GamePurchaseEntries.sol) | None |
| `createSmurf(bytes32,uint8)` (`0xf4824be2`) | [GamePurchaseEntries.createSmurf](../contracts/modules/GamePurchaseEntries.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `purchase(uint32,uint256,uint256,bytes32,uint8)` (`0x291c59d0`) | [GamePurchaseEntries.purchase](../contracts/modules/GamePurchaseEntries.sol) | None |
| `redeemFlip(uint32,uint256)` (`0x377a4803`) | [GamePurchaseEntries.redeemFlip](../contracts/modules/GamePurchaseEntries.sol) | None |
| `sweepAccounts(uint32[])` (`0xe85e8a9b`) | [GamePurchaseEntries.sweepAccounts](../contracts/modules/GamePurchaseEntries.sol) | None |
| `withdrawAfkingFunding(uint32,uint256)` (`0x4f00fd3f`) | [GamePurchaseEntries.withdrawAfkingFunding](../contracts/modules/GamePurchaseEntries.sol) | None |

### Eip170Mint

Deployment aliases: `GAME_MINT_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `purchaseWith(uint32,uint256,uint256,bytes32,uint8,uint256,uint32)` (`0x6a290c34`) | [DegenerusGameMintModule.purchaseWith](../contracts/modules/DegenerusGameMintModule.sol) | None |

### Eip170DegenesisFoil

Deployment aliases: `GAME_FOILPACK_MODULE, GAME_DEGENESIS_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `buyDegenesisBox_g1442(uint32,uint256)` (`0x000d72a5`) | [DegenerusGameDegenesisModule.buyDegenesisBox_g1442](../contracts/modules/DegenerusGameDegenesisModule.sol) | None |
| `claimFoilMatch(uint32,uint256,uint256)` (`0xbb653777`) | [DegenerusGameFoilUserModule.claimFoilMatch](../contracts/modules/DegenerusGameFoilUserModule.sol) | [Eip170Degenerette](#eip170degenerette).`resolveWwxrpSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveEthSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveFlipSpinsFromBox` |
| `claimFoilMatchMany(uint32[],uint24[],uint8[])` (`0x2c77c55e`) | [DegenerusGameFoilUserModule.claimFoilMatchMany](../contracts/modules/DegenerusGameFoilUserModule.sol) | None |
| `claimGoldenTicket(uint32,uint24)` (`0x9dbc39f6`) | [DegenerusGameFoilUserModule.claimGoldenTicket](../contracts/modules/DegenerusGameFoilUserModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `prepareDegenesis_g47(uint24)` (`0x00074e47`) | [DegenerusGameDegenesisModule.prepareDegenesis_g47](../contracts/modules/DegenerusGameDegenesisModule.sol) | None |
| `purchaseWithFoil(uint32,uint256,uint256,bytes32,uint8)` (`0x436bd2dc`) | [DegenerusGameFoilUserModule.purchaseWithFoil](../contracts/modules/DegenerusGameFoilUserModule.sol) | [Eip170Mint](#eip170mint).`purchaseWith` |
| `runDegenesisWork_g1860(uint256)` (`0x000245ca`) | [DegenerusGameDegenesisModule.runDegenesisWork_g1860](../contracts/modules/DegenerusGameDegenesisModule.sol) | [Eip170Boon](#eip170boon).`rollDegenesisBoons` |
| `spendDegenesis(uint32,bool,uint256,uint256,uint256)` (`0x551708ad`) | [DegenerusGameDegenesisModule.spendDegenesis](../contracts/modules/DegenerusGameDegenesisModule.sol) | [Eip170Mint](#eip170mint).`purchaseWith`; [Eip170Whale](#eip170whale).`purchaseWhalePassForDegenesis` |
| `splitDegenesis()` (`0xfefabe93`) | [DegenerusGameDegenesisModule.splitDegenesis](../contracts/modules/DegenerusGameDegenesisModule.sol) | None |
| `topUpSdgnrsAfking_g318()` (`0x00094cc9`) | [DegenerusGameDegenesisModule.topUpSdgnrsAfking_g318](../contracts/modules/DegenerusGameDegenesisModule.sol) | None |

### Eip170Advance

Deployment aliases: `GAME_ADVANCE_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `applyDailyWord_g1652()` (`0x00067d07`) | [DegenerusGameAdvanceModule.applyDailyWord_g1652](../contracts/modules/DegenerusGameAdvanceModule.sol) | [Eip170Boon](#eip170boon).`resolveProtocolBoonDraws` |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `prepareRequestBoundary(uint24)` (`0x2d89146c`) | [DegenerusGameAdvanceModule.prepareRequestBoundary](../contracts/modules/DegenerusGameAdvanceModule.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`prepareDegenesis_g47` |
| `runDailyPhase_g2582(uint256)` (`0x00095b45`) | [DegenerusGameAdvanceModule.runDailyPhase_g2582](../contracts/modules/DegenerusGameAdvanceModule.sol) | [Eip170Advance](#eip170advance).`stakeExcessEth`; [Eip170Afking](#eip170afking).`runSubDraw_g1232`; [Eip170Jackpot](#eip170jackpot).`runDailyJackpot`; [Eip170Jackpot](#eip170jackpot).`runPurchaseDailyTickets`; [Eip170Jackpot](#eip170jackpot).`payDailyFlipJackpot`; [Eip170Jackpot](#eip170jackpot).`distributeYieldSurplus`; [Eip170Jackpot](#eip170jackpot).`runEarlyBirdTickets`; [Eip170Jackpot](#eip170jackpot).`runBafAwards`; [Eip170Jackpot](#eip170jackpot).`runDailyJackpotTickets`; [Eip170JackpotDraw](#eip170jackpotdraw).`runPurchaseJackpotBattle`; [Eip170TicketFoil](#eip170ticketfoil).`queuePerpetualTickets` |
| `runLoanSeizureWork(uint256)` (`0xb18da899`) | [DegenerusGameAdvanceModule.runLoanSeizureWork](../contracts/modules/DegenerusGameAdvanceModule.sol) | [Eip170Endgame](#eip170endgame).`seizeLoan` |
| `runTerminalPhase(uint256)` (`0x56dd4651`) | [DegenerusGameAdvanceModule.runTerminalPhase](../contracts/modules/DegenerusGameAdvanceModule.sol) | [Eip170Afking](#eip170afking).`runSubDraw_g1232`; [Eip170Endgame](#eip170endgame).`runGameOverAdvance`; [Eip170Endgame](#eip170endgame).`seizeLoan` |
| `stakeExcessEth(uint256)` (`0x8cac9629`) | [DegenerusGameAdvanceModule.stakeExcessEth](../contracts/modules/DegenerusGameAdvanceModule.sol) | None |

### Eip170Jackpot

Deployment aliases: `GAME_JACKPOT_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `distributeYieldSurplus(uint256)` (`0x74307d12`) | [DegenerusGameJackpotModule.distributeYieldSurplus](../contracts/modules/DegenerusGameJackpotModule.sol) | None |
| `emitDailyWinningTraits(uint256)` (`0x68a81770`) | [DegenerusGameJackpotModule.emitDailyWinningTraits](../contracts/modules/DegenerusGameJackpotModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `payDailyFlipJackpot(uint24,uint256,uint24,uint24)` (`0x6fc6b504`) | [DegenerusGameJackpotModule.payDailyFlipJackpot](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170JackpotDraw](#eip170jackpotdraw).`awardDailyFlipJackpot` |
| `payGoldenTicketGrand(uint32,uint24,uint8)` (`0x91ac65cb`) | [DegenerusGameJackpotModule.payGoldenTicketGrand](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170JackpotDraw](#eip170jackpotdraw).`payGoldenTicket` |
| `runBafAwards(uint256,uint256)` (`0xc0ccc81e`) | [DegenerusGameJackpotModule.runBafAwards](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170JackpotDraw](#eip170jackpotdraw).`runBafAwards` |
| `runDailyJackpot(bool,uint24,uint256,uint256)` (`0x0254169e`) | [DegenerusGameJackpotModule.runDailyJackpot](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170Decimator](#eip170decimator).`runDecimatorJackpotAwards`; [Eip170JackpotDraw](#eip170jackpotdraw).`payGoldenTicket`; [Eip170Whale](#eip170whale).`awardWhalePass_g5502` |
| `runDailyJackpotTickets(uint256,uint256)` (`0xd306ef4b`) | [DegenerusGameJackpotModule.runDailyJackpotTickets](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170TicketFoil](#eip170ticketfoil).`runJackpotTicketAwards`; [Eip170Whale](#eip170whale).`awardWhalePass_g5502` |
| `runEarlyBirdTickets(uint256,uint256)` (`0x91ae808f`) | [DegenerusGameJackpotModule.runEarlyBirdTickets](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170TicketFoil](#eip170ticketfoil).`runJackpotTicketAwards`; [Eip170Whale](#eip170whale).`awardWhalePass_g5502` |
| `runPurchaseDailyTickets(uint256,uint256)` (`0x3a34a2f8`) | [DegenerusGameJackpotModule.runPurchaseDailyTickets](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170TicketFoil](#eip170ticketfoil).`runJackpotTicketAwards`; [Eip170Whale](#eip170whale).`awardWhalePass_g5502` |
| `runTerminalJackpotWork(uint256,uint24,uint256,uint256)` (`0x45f2191b`) | [DegenerusGameJackpotModule.runTerminalJackpotWork](../contracts/modules/DegenerusGameJackpotModule.sol) | [Eip170Decimator](#eip170decimator).`runDecimatorJackpotAwards`; [Eip170Whale](#eip170whale).`awardWhalePass_g5502` |

### Eip170JackpotDraw

Deployment aliases: `GAME_JACKPOT_DRAW_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `awardDailyFlipJackpot(uint24,uint24,uint32,uint256,uint256)` (`0xa080a87d`) | [DegenerusGameJackpotDrawModule.awardDailyFlipJackpot](../contracts/modules/DegenerusGameJackpotDrawModule.sol) | None |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `payGoldenTicket(uint32,uint24,uint8,uint8,bool)` (`0xe44e030e`) | [DegenerusGameJackpotDrawModule.payGoldenTicket](../contracts/modules/DegenerusGameJackpotDrawModule.sol) | None |
| `runBafAwards(uint256,uint256,uint8[3])` (`0x918f2af4`) | [DegenerusGameJackpotDrawModule.runBafAwards](../contracts/modules/DegenerusGameJackpotDrawModule.sol) | None |
| `runBafJackpot(uint256,uint24,uint256)` (`0x4181af8e`) | [DegenerusGameJackpotDrawModule.runBafJackpot](../contracts/modules/DegenerusGameJackpotDrawModule.sol) | None |
| `runPurchaseJackpotBattle(uint24,uint256,uint256)` (`0x31ad2c2e`) | [DegenerusGameJackpotDrawModule.runPurchaseJackpotBattle](../contracts/modules/DegenerusGameJackpotDrawModule.sol) | None |

### Eip170Whale

Deployment aliases: `GAME_WHALE_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `awardWhalePass_g5502(uint24,uint8,uint256,uint256,bool)` (`0x000a7c73`) | [DegenerusGameWhaleModule.awardWhalePass_g5502](../contracts/modules/DegenerusGameWhaleModule.sol) | None |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `claimWhalePass(uint32)` (`0x947219fc`) | [DegenerusGameWhaleModule.claimWhalePass](../contracts/modules/DegenerusGameWhaleModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `purchaseDeityPass(uint32,uint8,bytes32)` (`0x0d359801`) | [DegenerusGameWhaleModule.purchaseDeityPass](../contracts/modules/DegenerusGameWhaleModule.sol) | [Eip170Lootbox](#eip170lootbox).`recordCoverBox` |
| `purchaseLazyPass(uint32,bytes32)` (`0x0811f604`) | [DegenerusGameWhaleModule.purchaseLazyPass](../contracts/modules/DegenerusGameWhaleModule.sol) | [Eip170Lootbox](#eip170lootbox).`recordCoverBox` |
| `purchaseWhalePass(uint32,uint256,bytes32)` (`0x9e2dbae4`) | [DegenerusGameWhaleModule.purchaseWhalePass](../contracts/modules/DegenerusGameWhaleModule.sol) | [Eip170Lootbox](#eip170lootbox).`recordCoverBox` |
| `purchaseWhalePassForDegenesis(uint32,uint256)` (`0x742e5d82`) | [DegenerusGameWhaleModule.purchaseWhalePassForDegenesis](../contracts/modules/DegenerusGameWhaleModule.sol) | [Eip170Lootbox](#eip170lootbox).`recordCoverBox` |
| `purchaseWhalePassForSdgnrs_g470(uint24)` (`0x00094bef`) | [DegenerusGameWhaleModule.purchaseWhalePassForSdgnrs_g470](../contracts/modules/DegenerusGameWhaleModule.sol) | [Eip170Lootbox](#eip170lootbox).`recordCoverBox` |

### Eip170TicketFoil

Deployment aliases: `GAME_TICKET_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `queuePerpetualTickets(uint24)` (`0x62a48d51`) | [DegenerusGameFoilWorkerModule.queuePerpetualTickets](../contracts/modules/DegenerusGameFoilWorkerModule.sol) | None |
| `runFoilWork(uint256)` (`0x545778b9`) | [DegenerusGameFoilWorkerModule.runFoilWork](../contracts/modules/DegenerusGameFoilWorkerModule.sol) | [Eip170Jackpot](#eip170jackpot).`payGoldenTicketGrand` |
| `runJackpotTicketAwards((uint24,uint24,uint8,uint256,uint256,uint256,uint8[4],uint16[4],uint256[4],uint32[4]),uint256)` (`0x5feb9f41`) | [DegenerusGameTicketModule.runJackpotTicketAwards](../contracts/modules/DegenerusGameTicketModule.sol) | None |
| `runTicketWork_g1150(uint24,uint256)` (`0x000269f2`) | [DegenerusGameTicketModule.runTicketWork_g1150](../contracts/modules/DegenerusGameTicketModule.sol) | [Eip170Jackpot](#eip170jackpot).`payGoldenTicketGrand` |

### Eip170Lootbox

Deployment aliases: `GAME_LOOTBOX_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `creditRedemptionDirect(uint32,uint256)` (`0xca0519e7`) | [DegenerusGameLootboxModule.creditRedemptionDirect](../contracts/modules/DegenerusGameLootboxModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `recordCoverBox(uint32,uint256,uint16,bool,uint8)` (`0xbad18d5f`) | [DegenerusGameLootboxModule.recordCoverBox](../contracts/modules/DegenerusGameLootboxModule.sol) | None |
| `resolveAfkingBox(uint32,uint256,uint24,uint256,uint16)` (`0x60e6c9ac`) | [DegenerusGameLootboxModule.resolveAfkingBox](../contracts/modules/DegenerusGameLootboxModule.sol) | [Eip170Boon](#eip170boon).`rollBoxBoons`; [Eip170Degenerette](#eip170degenerette).`resolveWwxrpSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveEthSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveFlipSpinsFromBox` |
| `resolveHumanBoxOrder(uint48,uint256,uint256,uint256,uint24)` (`0xb5de189f`) | [DegenerusGameLootboxModule.resolveHumanBoxOrder](../contracts/modules/DegenerusGameLootboxModule.sol) | [Eip170Boon](#eip170boon).`rollBoxBoons`; [Eip170Degenerette](#eip170degenerette).`resolveWwxrpSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveEthSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveFlipSpinsFromBox` |
| `resolveLootboxDirect(uint32,uint256,uint256,uint16)` (`0xf9bcbe56`) | [DegenerusGameLootboxModule.resolveLootboxDirect](../contracts/modules/DegenerusGameLootboxModule.sol) | [Eip170Boon](#eip170boon).`rollBoxBoons`; [Eip170Degenerette](#eip170degenerette).`resolveWwxrpSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveEthSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveFlipSpinsFromBox` |
| `resolveRedemptionLootbox(uint32,uint256,uint256,uint16,uint32)` (`0x85e304f0`) | [DegenerusGameLootboxModule.resolveRedemptionLootbox](../contracts/modules/DegenerusGameLootboxModule.sol) | [Eip170Boon](#eip170boon).`rollBoxBoons`; [Eip170Degenerette](#eip170degenerette).`resolveWwxrpSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveEthSpinFromBox`; [Eip170Degenerette](#eip170degenerette).`resolveFlipSpinsFromBox` |

### Eip170Boon

Deployment aliases: `GAME_BOON_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `checkAndClearExpiredBoon(uint32)` (`0x20ec0dea`) | [DegenerusGameBoonModule.checkAndClearExpiredBoon](../contracts/modules/DegenerusGameBoonModule.sol) | None |
| `consumeCoinflipBoon_g2902(uint32)` (`0x000af7d3`) | [GameBoonActionsEntries.consumeCoinflipBoon_g2902](../contracts/modules/GameBoonActionsEntries.sol) | None |
| `consumeDecimatorBoon(uint32)` (`0x19c5bdb1`) | [GameBoonActionsEntries.consumeDecimatorBoon](../contracts/modules/GameBoonActionsEntries.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `giveBoon(uint32,uint32,uint8)` (`0x281aaad8`) | [GameBoonActionsEntries.giveBoon](../contracts/modules/GameBoonActionsEntries.sol) | None |
| `initProtocolDeity()` (`0xc8ff239c`) | [DegenerusGameBoonModule.initProtocolDeity](../contracts/modules/DegenerusGameBoonModule.sol) | None |
| `resolveProtocolBoonDraws(uint24)` (`0x1584735e`) | [DegenerusGameBoonModule.resolveProtocolBoonDraws](../contracts/modules/DegenerusGameBoonModule.sol) | None |
| `rollBoxBoons(uint32,uint256,uint256,uint256,uint24,uint256,uint256)` (`0x46791e04`) | [DegenerusGameBoonModule.rollBoxBoons](../contracts/modules/DegenerusGameBoonModule.sol) | None |
| `rollDegenesisBoons(uint32,uint256,uint256)` (`0xc2dd4718`) | [DegenerusGameBoonModule.rollDegenesisBoons](../contracts/modules/DegenerusGameBoonModule.sol) | None |

### Eip170Degenerette

Deployment aliases: `GAME_DEGENERETTE_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `betDegenerette(uint32,uint8,uint128,uint8,uint8)` (`0x16c6bd96`) | [GameBetEntries.betDegenerette](../contracts/modules/GameBetEntries.sol) | None |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `resolveEthSpinFromBox(uint32,uint256,uint16,uint256,uint8)` (`0x34a26246`) | [DegenerusGameDegeneretteModule.resolveEthSpinFromBox](../contracts/modules/DegenerusGameDegeneretteModule.sol) | [Eip170Lootbox](#eip170lootbox).`resolveLootboxDirect` |
| `resolveFlipSpinsFromBox(uint32,uint256,uint16,uint256,uint8)` (`0x72c23b93`) | [DegenerusGameDegeneretteModule.resolveFlipSpinsFromBox](../contracts/modules/DegenerusGameDegeneretteModule.sol) | None |
| `resolveWwxrpSpinFromBox(uint32,uint256,uint16,uint256,uint8)` (`0x0753b760`) | [DegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox](../contracts/modules/DegenerusGameDegeneretteModule.sol) | None |
| `runDegeneretteWork_g670(uint256)` (`0x000d3465`) | [DegenerusGameDegeneretteModule.runDegeneretteWork_g670](../contracts/modules/DegenerusGameDegeneretteModule.sol) | [Eip170Lootbox](#eip170lootbox).`resolveLootboxDirect` |

### Eip170Afking

Deployment aliases: `GAME_AFKING_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `cancelLiquidatedSubscriptions(uint32,bool)` (`0x5c6ad7eb`) | [GameAfkingModule.cancelLiquidatedSubscriptions](../contracts/modules/GameAfkingModule.sol) | None |
| `claimAfkingFlip(uint32[])` (`0xaadb9666`) | [GameAfkingModule.claimAfkingFlip](../contracts/modules/GameAfkingModule.sol) | None |
| `decurse(uint32)` (`0x778b5824`) | [GameAfkingModule.decurse](../contracts/modules/GameAfkingModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `pullAfkingSteth(uint32,address,uint256)` (`0x1145ef7d`) | [GameAfkingModule.pullAfkingSteth](../contracts/modules/GameAfkingModule.sol) | None |
| `runAfkingWork_g8553(uint256)` (`0x000007be`) | [GameAfkingModule.runAfkingWork_g8553](../contracts/modules/GameAfkingModule.sol) | [Eip170Lootbox](#eip170lootbox).`resolveAfkingBox` |
| `runHumanBoxWork_g315(uint256)` (`0x00024af5`) | [GameAfkingModule.runHumanBoxWork_g315](../contracts/modules/GameAfkingModule.sol) | [Eip170Lootbox](#eip170lootbox).`resolveHumanBoxOrder` |
| `runSubDraw_g1232(uint24)` (`0x0007e202`) | [GameAfkingModule.runSubDraw_g1232](../contracts/modules/GameAfkingModule.sol) | None |
| `runSubscriberWork_g6352(uint24,uint256)` (`0x000e1558`) | [GameAfkingModule.runSubscriberWork_g6352](../contracts/modules/GameAfkingModule.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`topUpSdgnrsAfking_g318`; [Eip170Whale](#eip170whale).`purchaseWhalePassForSdgnrs_g470` |
| `smite(uint256,uint32)` (`0xd470bfde`) | [GameAfkingModule.smite](../contracts/modules/GameAfkingModule.sol) | None |
| `subscribe(uint32,bool,uint8,uint256)` (`0x4ee59ad5`) | [GameAfkingModule.subscribe](../contracts/modules/GameAfkingModule.sol) | None |

### Eip170Endgame

Deployment aliases: `GAME_GAMEOVER_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `claimDeadVrf(uint32,uint256[])` (`0xe1b52c71`) | [DegenerusGameGameOverModule.claimDeadVrf](../contracts/modules/DegenerusGameGameOverModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `initVrf(address,uint256,bytes32)` (`0xc7cd0e48`) | [DegenerusGameGameOverModule.initVrf](../contracts/modules/DegenerusGameGameOverModule.sol) | None |
| `runGameOverAdvance(uint24,uint24,uint256)` (`0x431a2267`) | [DegenerusGameGameOverModule.runGameOverAdvance](../contracts/modules/DegenerusGameGameOverModule.sol) | [Eip170DegenesisFoil](#eip170degenesisfoil).`splitDegenesis`; [Eip170TicketFoil](#eip170ticketfoil).`runTicketWork_g1150` |
| `seizeLoan(uint32,uint32)` (`0xdedfd2e3`) | [DegenerusGameGameOverModule.seizeLoan](../contracts/modules/DegenerusGameGameOverModule.sol) | [Eip170Afking](#eip170afking).`cancelLiquidatedSubscriptions` |
| `setThanosLevel(uint24,uint8)` (`0x6b20479b`) | [DegenerusGameGameOverModule.setThanosLevel](../contracts/modules/DegenerusGameGameOverModule.sol) | None |
| `updateVrfCoordinatorAndSub(address,uint256,bytes32,uint32)` (`0x6c812791`) | [DegenerusGameGameOverModule.updateVrfCoordinatorAndSub](../contracts/modules/DegenerusGameGameOverModule.sol) | None |

### Eip170Decimator

Deployment aliases: `GAME_DECIMATOR_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `recordDecBurn_g1271(uint32,uint24,uint256,uint256,uint32)` (`0x205fb9a2`) | [DegenerusGameDecimatorModule.recordDecBurn_g1271](../contracts/modules/DegenerusGameDecimatorModule.sol) | None |
| `runDecimatorJackpot(uint256,uint24,uint256)` (`0x275d3a40`) | [DegenerusGameDecimatorModule.runDecimatorJackpot](../contracts/modules/DegenerusGameDecimatorModule.sol) | None |
| `runDecimatorJackpotAwards((uint256,uint256[4],uint16[4],uint8),uint256)` (`0xd4c8fc87`) | [DegenerusGameDecimatorModule.runDecimatorJackpotAwards](../contracts/modules/DegenerusGameDecimatorModule.sol) | None |
| `runDecimatorWork(uint256)` (`0xc59bf72d`) | [DegenerusGameDecimatorModule.runDecimatorWork](../contracts/modules/DegenerusGameDecimatorModule.sol) | None |

### Eip170MinerRng

Deployment aliases: `GAME_MINER_MODULE, GAME_RNG_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `creditMiddayRng(address,uint256)` (`0xc319ce1a`) | [DegenerusGameRngModule.creditMiddayRng](../contracts/modules/DegenerusGameRngModule.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `mineRun(uint32)` (`0x03431f36`) | [GameMinerEntries.mineRun](../contracts/modules/GameMinerEntries.sol) | [Eip170Advance](#eip170advance).`applyDailyWord_g1652`; [Eip170Advance](#eip170advance).`runDailyPhase_g2582`; [Eip170Advance](#eip170advance).`runTerminalPhase`; [Eip170Advance](#eip170advance).`runLoanSeizureWork`; [Eip170Afking](#eip170afking).`runAfkingWork_g8553`; [Eip170Afking](#eip170afking).`runHumanBoxWork_g315`; [Eip170Afking](#eip170afking).`runSubscriberWork_g6352`; [Eip170Decimator](#eip170decimator).`runDecimatorWork`; [Eip170Degenerette](#eip170degenerette).`runDegeneretteWork_g670`; [Eip170DegenesisFoil](#eip170degenesisfoil).`runDegenesisWork_g1860`; [Eip170MinerRng](#eip170minerrng).`publishRng_g4514`; [Eip170MinerRng](#eip170minerrng).`requestMinerRng_g4954`; [Eip170MinerRng](#eip170minerrng).`requestDailyRng_g8190`; [Eip170TicketFoil](#eip170ticketfoil).`runTicketWork_g1150` |
| `minerAction()` (`0x45af5e2d`) | [GameMinerEntries.minerAction](../contracts/modules/GameMinerEntries.sol) | None |
| `publishRng_g4514()` (`0x00090a23`) | [DegenerusGameRngModule.publishRng_g4514](../contracts/modules/DegenerusGameRngModule.sol) | None |
| `requestDailyRng_g8190(uint24)` (`0x000b6663`) | [DegenerusGameRngModule.requestDailyRng_g8190](../contracts/modules/DegenerusGameRngModule.sol) | [Eip170Advance](#eip170advance).`prepareRequestBoundary` |
| `requestMinerRng_g4954()` (`0x000a48e4`) | [DegenerusGameRngModule.requestMinerRng_g4954](../contracts/modules/DegenerusGameRngModule.sol) | None |
| `retryRng()` (`0x5132993a`) | [DegenerusGameRngModule.retryRng](../contracts/modules/DegenerusGameRngModule.sol) | None |

## Craps table, lifecycle and engine

### CrapsBattle

Deployment aliases: `CRAPS, JACKPOT_BATTLE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `admitCustom(uint64)` (`0x290b28a0`) | [CrapsLifecycleRouter.admitCustom](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`admitCustom` |
| `amendSlip(uint32,uint256,uint32)` (`0x547e3a1e`) | [CrapsBattleCore.amendSlip](../contracts/modules/CrapsBattleCore.sol) | None |
| `appendJackpotBattle(uint256[],uint256,bool)` (`0x9889c3c0`) | [CrapsLifecycleRouter.appendJackpotBattle](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`appendJackpotBattle` |
| `applyCrapsPasses(uint32,uint24,uint8,bool,uint32)` (`0xa78ef42a`) | [CrapsBattleCore.applyCrapsPasses](../contracts/modules/CrapsBattleCore.sol) | None |
| `buyFutureCrapsDays(uint32,uint24,uint8,bool,uint32)` (`0xf658fd3a`) | [CrapsBattleCore.buyFutureCrapsDays](../contracts/modules/CrapsBattleCore.sol) | None |
| `closeBattle(uint64)` (`0x0d995e31`) | [CrapsLifecycleRouter.closeBattle](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`closeBattle` |
| `convertNormalToHigh(uint32,uint32)` (`0xee3dac1b`) | [CrapsLifecycleRouter.convertNormalToHigh](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`convertNormalToHigh` |
| `createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)` (`0x9ab26cb4`) | [CrapsLifecycleRouter.createBattle](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`createBattle` |
| `creditPasses(uint32,uint32,uint32)` (`0x83a9c5e9`) | [CrapsBattleCore.creditPasses](../contracts/modules/CrapsBattleCore.sol) | None |
| `deliverPasses(uint32,uint32,uint32)` (`0x54e89742`) | [CrapsBattleCore.deliverPasses](../contracts/modules/CrapsBattleCore.sol) | None |
| `donate(bool,uint256,uint24)` (`0x6435323d`) | [CrapsLifecycleRouter.donate](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`donate` |
| `enterBattle(uint32,uint64,uint32,uint16)` (`0x96781e21`) | [CrapsBattleCore.enterBattle](../contracts/modules/CrapsBattleCore.sol) | None |
| `extsload(bytes32[])` (`0xdbd035ff`) | [CrapsBattleCore.extsload](../contracts/modules/CrapsBattleCore.sol) | None |
| `extsload_g2807007(bytes32)` (`0x0000025f`) | [CrapsBattleCore.extsload_g2807007](../contracts/modules/CrapsBattleCore.sol) | None |
| `finalizeBattle_g3665((bytes32,uint128,uint128,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint48,uint32,uint64,uint32,uint32,uint256,uint256),uint256,uint256)` (`0x000b9195`) | [CrapsLifecycleRouter.finalizeBattle_g3665](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`finalizeBattle_g3665` |
| `jackpotProgress()` (`0xece0fe2e`) | [CrapsLifecycleViews.jackpotProgress](../contracts/modules/CrapsLifecycleViews.sol) | None |
| `lockJackpotBattle(uint24,uint256,uint24)` (`0xd5bc13d9`) | [CrapsLifecycleRouter.lockJackpotBattle](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`lockJackpotBattle` |
| `minerMaintenancePending_g11976()` (`0x0003284a`) | [CrapsBattleCore.minerMaintenancePending_g11976](../contracts/modules/CrapsBattleCore.sol) | None |
| `openBonusDay()` (`0x6d5b0ca1`) | [CrapsBattleCore.openBonusDay](../contracts/modules/CrapsBattleCore.sol) | None |
| `payBattlePot(uint64,bytes32,uint256,uint256,uint256,uint256)` (`0x39f806fc`) | [CrapsLifecycleRouter.payBattlePot](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`payBattlePot` |
| `playCraps(uint32,uint32,uint16)` (`0x2879e121`) | [CrapsBattleCore.playCraps](../contracts/modules/CrapsBattleCore.sol) | None |
| `prepareJackpotBattle(uint24,uint256)` (`0x446d0285`) | [CrapsLifecycleRouter.prepareJackpotBattle](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`prepareJackpotBattle` |
| `registerRngSlot_g709(uint48,uint64,bytes32)` (`0x000a1a10`) | [CrapsLifecycleRouter.registerRngSlot_g709](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`registerRngSlot_g709` |
| `resolveRngSlot_g1079(uint64,uint256)` (`0x000ca6e2`) | [CrapsBattleCore.resolveRngSlot_g1079](../contracts/modules/CrapsBattleCore.sol) | None |
| `runCrapsMaintenance_g10712(uint256)` (`0x000a549c`) | [CrapsLifecycleRouter.runCrapsMaintenance_g10712](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`runCrapsMaintenance_g10712` |
| `runCrapsReadWork(uint48,uint256)` (`0x34b53453`) | [CrapsLifecycleRouter.runCrapsReadWork](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`runCrapsReadWork` |
| `runDailyBattleWork(uint256)` (`0x94ce3a4b`) | [CrapsLifecycleRouter.runDailyBattleWork](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`runDailyBattleWork` |
| `setBattleCreator(address,bool)` (`0x5a276aa5`) | [CrapsLifecycleRouter.setBattleCreator](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`setBattleCreator` |
| `setPreferredBoard(uint32,uint32)` (`0x1ead86c2`) | [CrapsBattleCore.setPreferredBoard](../contracts/modules/CrapsBattleCore.sol) | None |
| `settleHighRollerReserve(uint64)` (`0xb28839e0`) | [CrapsLifecycleRouter.settleHighRollerReserve](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`settleHighRollerReserve` |
| `throwCraps(uint32,uint256,uint32,uint16)` (`0x02374dad`) | [CrapsBattleCore.throwCraps](../contracts/modules/CrapsBattleCore.sol) | None |
| `upgradeDayWindows(uint32,uint24,uint8)` (`0x426f7ed2`) | [CrapsBattleCore.upgradeDayWindows](../contracts/modules/CrapsBattleCore.sol) | None |
| `upgradeReservedDay(uint32,uint24)` (`0x2f04a86b`) | [CrapsLifecycleRouter.upgradeReservedDay](../contracts/modules/CrapsLifecycleRouter.sol) | [Eip170JackpotBattle](#eip170jackpotbattle).`upgradeReservedDay` |
| `vaultComp(uint256)` (`0xe0bb3a28`) | [CrapsBattleCore.vaultComp](../contracts/modules/CrapsBattleCore.sol) | None |

### Eip170JackpotBattle

Deployment aliases: `CRAPS_LIFECYCLE_MODULE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `admitCustom(uint64)` (`0x290b28a0`) | [JackpotBattle.admitCustom](../contracts/JackpotBattle.sol) | None |
| `appendJackpotBattle(uint256[],uint256,bool)` (`0x9889c3c0`) | [JackpotBattle.appendJackpotBattle](../contracts/JackpotBattle.sol) | None |
| `closeBattle(uint64)` (`0x0d995e31`) | [JackpotBattle.closeBattle](../contracts/JackpotBattle.sol) | None |
| `convertNormalToHigh(uint32,uint32)` (`0xee3dac1b`) | [JackpotBattle.convertNormalToHigh](../contracts/JackpotBattle.sol) | None |
| `createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)` (`0x9ab26cb4`) | [JackpotBattle.createBattle](../contracts/JackpotBattle.sol) | None |
| `donate(bool,uint256,uint24)` (`0x6435323d`) | [JackpotBattle.donate](../contracts/JackpotBattle.sol) | None |
| `finalizeBattle_g3665((bytes32,uint128,uint128,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint48,uint32,uint64,uint32,uint32,uint256,uint256),uint256,uint256)` (`0x000b9195`) | [JackpotBattle.finalizeBattle_g3665](../contracts/JackpotBattle.sol) | None |
| `jackpotProgress()` (`0xece0fe2e`) | [CrapsLifecycleViews.jackpotProgress](../contracts/modules/CrapsLifecycleViews.sol) | None |
| `lockJackpotBattle(uint24,uint256,uint24)` (`0xd5bc13d9`) | [JackpotBattle.lockJackpotBattle](../contracts/JackpotBattle.sol) | None |
| `payBattlePot(uint64,bytes32,uint256,uint256,uint256,uint256)` (`0x39f806fc`) | [JackpotBattle.payBattlePot](../contracts/JackpotBattle.sol) | None |
| `prepareJackpotBattle(uint24,uint256)` (`0x446d0285`) | [JackpotBattle.prepareJackpotBattle](../contracts/JackpotBattle.sol) | None |
| `registerRngSlot_g709(uint48,uint64,bytes32)` (`0x000a1a10`) | [JackpotBattle.registerRngSlot_g709](../contracts/JackpotBattle.sol) | None |
| `runCrapsMaintenance_g10712(uint256)` (`0x000a549c`) | [JackpotBattle.runCrapsMaintenance_g10712](../contracts/JackpotBattle.sol) | None |
| `runCrapsReadWork(uint48,uint256)` (`0x34b53453`) | [JackpotBattle.runCrapsReadWork](../contracts/JackpotBattle.sol) | None |
| `runDailyBattleWork(uint256)` (`0x94ce3a4b`) | [JackpotBattle.runDailyBattleWork](../contracts/JackpotBattle.sol) | None |
| `setBattleCreator(address,bool)` (`0x5a276aa5`) | [JackpotBattle.setBattleCreator](../contracts/JackpotBattle.sol) | None |
| `settleHighRollerReserve(uint64)` (`0xb28839e0`) | [JackpotBattle.settleHighRollerReserve](../contracts/JackpotBattle.sol) | None |
| `upgradeReservedDay(uint32,uint24)` (`0x2f04a86b`) | [JackpotBattle.upgradeReservedDay](../contracts/JackpotBattle.sol) | None |

### Eip170CrapsEngine

Deployment aliases: `CRAPS_ENGINE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `customDefinition(uint32,uint8,uint16,uint24,uint40,bool,uint16)` (`0xbd6c7232`) | [CrapsEngine.customDefinition](../contracts/CrapsEngine.sol) | None |
| `settleBattle(uint256,uint256,uint256,uint256,uint256,uint48,uint256,uint256)` (`0x05abe21d`) | [CrapsEngine.settleBattle](../contracts/CrapsEngine.sol) | None |
| `settleBattleCompact_g439244(uint256,uint256,uint256,uint256,uint256,uint48,uint256,uint256)` (`0x0000024e`) | [CrapsEngine.settleBattleCompact_g439244](../contracts/CrapsEngine.sol) | None |
| `settleSlip(uint256,uint256,uint256,uint256,bytes32,uint256,uint256,uint256,uint256)` (`0xf792bd99`) | [CrapsEngine.settleSlip](../contracts/CrapsEngine.sol) | None |
| `settleSlipBounded(uint256,uint256,uint256,uint256,bytes32,uint256,uint256,uint256,uint256)` (`0x786c4e15`) | [CrapsEngine.settleSlipBounded](../contracts/CrapsEngine.sol) | None |

## Credits and side games

### Coinflip

Deployment aliases: `COINFLIP`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `armBafDraw(uint24)` (`0x0e0b46f4`) | [CoinflipCore.armBafDraw](../contracts/modules/CoinflipCore.sol) | None |
| `armDiceRunRecord(uint32,uint256)` (`0xca744938`) | [CoinflipCore.armDiceRunRecord](../contracts/modules/CoinflipCore.sol) | None |
| `armRecord(uint8,uint32,uint256)` (`0xf5b3660d`) | [CoinflipCore.armRecord](../contracts/modules/CoinflipCore.sol) | None |
| `bafDrawEntryAt(uint24,uint32)` (`0xa7bc8a35`) | [CoinflipCore.bafDrawEntryAt](../contracts/modules/CoinflipCore.sol) | None |
| `bafDrawInfo()` (`0x676271fc`) | [CoinflipCore.bafDrawInfo](../contracts/modules/CoinflipCore.sol) | None |
| `bafDrawWinner(uint256)` (`0xe93f5eca`) | [CoinflipCore.bafDrawWinner](../contracts/modules/CoinflipCore.sol) | None |
| `biggestBuyEver()` (`0xa0336fc0`) | Compiler-generated getter | None |
| `biggestDiceRunEver()` (`0xd7c49d85`) | Compiler-generated getter | None |
| `biggestFlipEver()` (`0xa391e7d7`) | Compiler-generated getter | None |
| `biggestLuckboxEver()` (`0x14a6160d`) | Compiler-generated getter | None |
| `biggestSpinEver()` (`0xfd08ba20`) | Compiler-generated getter | None |
| `claimCoinflipCarry(uint32,uint256)` (`0x6d11aab9`) | [CoinflipCore.claimCoinflipCarry](../contracts/modules/CoinflipCore.sol) | None |
| `claimCoinflips(uint32,uint256)` (`0x011cfdd7`) | [CoinflipCore.claimCoinflips](../contracts/modules/CoinflipCore.sol) | None |
| `claimCoinflipsFromFlip(address,uint256)` (`0xe38d1a47`) | [CoinflipCore.claimCoinflipsFromFlip](../contracts/modules/CoinflipCore.sol) | None |
| `coinflipAmount(address)` (`0x5562c868`) | [CoinflipCore.coinflipAmount](../contracts/modules/CoinflipCore.sol) | None |
| `coinflipAmountById(uint32)` (`0x0dd18774`) | [CoinflipCore.coinflipAmountById](../contracts/modules/CoinflipCore.sol) | None |
| `coinflipAutoRebuyInfo(address)` (`0x787074c0`) | [CoinflipCore.coinflipAutoRebuyInfo](../contracts/modules/CoinflipCore.sol) | None |
| `coinflipAutoRebuyInfoById(uint32)` (`0x26f9ea34`) | [CoinflipCore.coinflipAutoRebuyInfoById](../contracts/modules/CoinflipCore.sol) | None |
| `consumeCoinflipsForBurn(address,uint256)` (`0x0ff6b6fc`) | [CoinflipCore.consumeCoinflipsForBurn](../contracts/modules/CoinflipCore.sol) | None |
| `consumeFlipBacking(address,uint256)` (`0xa26e0461`) | [CoinflipCore.consumeFlipBacking](../contracts/modules/CoinflipCore.sol) | None |
| `creditFlipBatch(uint32[],uint256[])` (`0xc7a80d4f`) | [CoinflipCore.creditFlipBatch](../contracts/modules/CoinflipCore.sol) | None |
| `creditFlipPair_g578(uint32,uint256,uint32,uint256)` (`0x000fae5a`) | [CoinflipCore.creditFlipPair_g578](../contracts/modules/CoinflipCore.sol) | None |
| `creditFlip_g317(uint32,uint256)` (`0x0003fb63`) | [CoinflipCore.creditFlip_g317](../contracts/modules/CoinflipCore.sol) | None |
| `creditSdgnrsBacking(uint256)` (`0x5afd079c`) | [CoinflipCore.creditSdgnrsBacking](../contracts/modules/CoinflipCore.sol) | None |
| `degenerusGame()` (`0xf07efe3c`) | Compiler-generated getter | None |
| `flip()` (`0xcde4efa9`) | Compiler-generated getter | None |
| `flipResolvedToday()` (`0x3742ed77`) | [CoinflipCore.flipResolvedToday](../contracts/modules/CoinflipCore.sol) | None |
| `fundRecordPool(uint256)` (`0x62d9d8c1`) | [CoinflipCore.fundRecordPool](../contracts/modules/CoinflipCore.sol) | None |
| `getCoinflipDayResult(uint24)` (`0xa98f1009`) | [CoinflipCore.getCoinflipDayResult](../contracts/modules/CoinflipCore.sol) | None |
| `jackpots()` (`0x77d70b1f`) | Compiler-generated getter | None |
| `onDailyRequest(uint24)` (`0x07f8ef5d`) | [CoinflipCore.onDailyRequest](../contracts/modules/CoinflipCore.sol) | None |
| `playCoinflip(uint32,uint256)` (`0x07d3289f`) | [CoinflipCore.playCoinflip](../contracts/modules/CoinflipCore.sol) | None |
| `previewClaimCoinflips(address)` (`0x0e75a93e`) | [CoinflipCore.previewClaimCoinflips](../contracts/modules/CoinflipCore.sol) | None |
| `previewClaimCoinflipsById(uint32)` (`0x936d6bf6`) | [CoinflipCore.previewClaimCoinflipsById](../contracts/modules/CoinflipCore.sol) | None |
| `previewFlipBacking(address)` (`0xd42d9cd0`) | [CoinflipCore.previewFlipBacking](../contracts/modules/CoinflipCore.sol) | None |
| `previewFlipBackingById(uint32)` (`0x7c41a917`) | [CoinflipCore.previewFlipBackingById](../contracts/modules/CoinflipCore.sol) | None |
| `processCoinflipPayouts(uint8,uint256,uint24)` (`0xffa84f76`) | [CoinflipCore.processCoinflipPayouts](../contracts/modules/CoinflipCore.sol) | None |
| `recordPool()` (`0xf7530e1a`) | Compiler-generated getter | None |
| `redeemableFlipBacking()` (`0x39f3cf32`) | [CoinflipCore.redeemableFlipBacking](../contracts/modules/CoinflipCore.sol) | None |
| `requestedDailyIdx()` (`0x79ab254f`) | Compiler-generated getter | None |
| `setCoinflipAutoRebuy(uint32,bool,uint256)` (`0xfebdad87`) | [CoinflipCore.setCoinflipAutoRebuy](../contracts/modules/CoinflipCore.sol) | None |
| `setCoinflipAutoRebuyTakeProfit(uint32,uint256)` (`0xd64053b0`) | [CoinflipCore.setCoinflipAutoRebuyTakeProfit](../contracts/modules/CoinflipCore.sol) | None |
| `sweepAccountCoinflips(uint32)` (`0xe08b0751`) | [CoinflipCore.sweepAccountCoinflips](../contracts/modules/CoinflipCore.sol) | None |
| `withdrawRedeemedFlip(uint256)` (`0x63f29eea`) | [CoinflipCore.withdrawRedeemedFlip](../contracts/modules/CoinflipCore.sol) | None |
| `wwxrp()` (`0x89075b15`) | Compiler-generated getter | None |

### Eip170Quests

Deployment aliases: `QUESTS`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `awardQuestStreakBonus(uint32,uint16,uint24)` (`0x9509f9f8`) | [DegenerusQuests.awardQuestStreakBonus](../contracts/DegenerusQuests.sol) | None |
| `awardQuestStreakShield(uint32,uint16)` (`0x20be0bcb`) | [DegenerusQuests.awardQuestStreakShield](../contracts/DegenerusQuests.sol) | None |
| `beginAfking(uint32,uint24)` (`0x571a031f`) | [DegenerusQuests.beginAfking](../contracts/DegenerusQuests.sol) | None |
| `effectiveBaseStreak(uint32)` (`0x736cadc0`) | [DegenerusQuests.effectiveBaseStreak](../contracts/DegenerusQuests.sol) | None |
| `effectiveBaseStreakAndAfking_g1521(uint32,uint24)` (`0x000c1a8e`) | [DegenerusQuests.effectiveBaseStreakAndAfking_g1521](../contracts/DegenerusQuests.sol) | None |
| `finalizeAfking(uint32,uint24,uint24)` (`0x2891ee09`) | [DegenerusQuests.finalizeAfking](../contracts/DegenerusQuests.sol) | None |
| `getActiveQuests()` (`0x029a8c58`) | [DegenerusQuests.getActiveQuests](../contracts/DegenerusQuests.sol) | None |
| `getPlayerLevelQuestView(uint32)` (`0x325989fd`) | [DegenerusQuests.getPlayerLevelQuestView](../contracts/DegenerusQuests.sol) | None |
| `getPlayerQuestView(uint32)` (`0x853a6d29`) | [DegenerusQuests.getPlayerQuestView](../contracts/DegenerusQuests.sol) | None |
| `handleAffiliate_g2566281(uint32,uint256,uint24)` (`0x00000cdf`) | [DegenerusQuests.handleAffiliate_g2566281](../contracts/DegenerusQuests.sol) | None |
| `handleDecimator(uint32,uint256)` (`0x8fb2877a`) | [DegenerusQuests.handleDecimator](../contracts/DegenerusQuests.sol) | None |
| `handleDegenerette_g3(uint32,uint256,bool,uint256,uint24)` (`0x04b66367`) | [DegenerusQuests.handleDegenerette_g3](../contracts/DegenerusQuests.sol) | None |
| `handleFlip_g217(uint32,uint256,uint24)` (`0x00b2999a`) | [DegenerusQuests.handleFlip_g217](../contracts/DegenerusQuests.sol) | None |
| `handleFoilPurchase(uint32,uint256,uint32,uint256,uint256,uint256)` (`0x384a1bc8`) | [DegenerusQuests.handleFoilPurchase](../contracts/DegenerusQuests.sol) | None |
| `handlePurchase_g23478(uint24,uint32,uint256,uint32,uint256,uint256,uint256)` (`0x0006beb0`) | [DegenerusQuests.handlePurchase_g23478](../contracts/DegenerusQuests.sol) | None |
| `marketBetGates(uint32,uint24)` (`0x1763307e`) | [DegenerusQuests.marketBetGates](../contracts/DegenerusQuests.sol) | None |
| `playerQuestStates(uint32)` (`0xbe62dca0`) | [DegenerusQuests.playerQuestStates](../contracts/DegenerusQuests.sol) | None |
| `questCompletionToday(uint32)` (`0x5be3177d`) | [DegenerusQuests.questCompletionToday](../contracts/DegenerusQuests.sol) | None |
| `recordCrapsAction_g14623(uint32,uint8)` (`0x000d8fdf`) | [DegenerusQuests.recordCrapsAction_g14623](../contracts/DegenerusQuests.sol) | None |
| `recordGrowthBet(uint32,uint24,uint256)` (`0xbbba9e50`) | [DegenerusQuests.recordGrowthBet](../contracts/DegenerusQuests.sol) | None |
| `rollDailyQuest(uint24,uint256,bool,bool,bool)` (`0x4738bb88`) | [DegenerusQuests.rollDailyQuest](../contracts/DegenerusQuests.sol) | None |
| `rollLevelQuest(uint256)` (`0x5911b2a2`) | [DegenerusQuests.rollLevelQuest](../contracts/DegenerusQuests.sol) | None |
| `shieldsOf(uint32)` (`0x18a7bf77`) | [DegenerusQuests.shieldsOf](../contracts/DegenerusQuests.sol) | None |

### Eip170Affiliate

Deployment aliases: `AFFILIATE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `affiliateBonusPointsBest_g3878(uint24,uint32)` (`0x0000c243`) | [DegenerusAffiliate.affiliateBonusPointsBest_g3878](../contracts/DegenerusAffiliate.sol) | None |
| `affiliateCode(bytes32)` (`0x0d133122`) | [DegenerusAffiliate.affiliateCode](../contracts/DegenerusAffiliate.sol) | None |
| `affiliateScore(uint24,uint32)` (`0x97254aaa`) | [DegenerusAffiliate.affiliateScore](../contracts/DegenerusAffiliate.sol) | None |
| `affiliateScoreAndTotal_g4013(uint24,uint32)` (`0xfff3ab9b`) | [DegenerusAffiliate.affiliateScoreAndTotal_g4013](../contracts/DegenerusAffiliate.sol) | None |
| `affiliateTop(uint24)` (`0xd4b88ae6`) | [DegenerusAffiliate.affiliateTop](../contracts/DegenerusAffiliate.sol) | None |
| `claim(uint32[])` (`0x2f85a4a0`) | [DegenerusAffiliate.claim](../contracts/DegenerusAffiliate.sol) | None |
| `createAffiliateCode(bytes32,uint8)` (`0x4d3d3168`) | [DegenerusAffiliate.createAffiliateCode](../contracts/DegenerusAffiliate.sol) | None |
| `defaultCode(address)` (`0x4558bc7e`) | [DegenerusAffiliate.defaultCode](../contracts/DegenerusAffiliate.sol) | None |
| `defaultCodeById(uint32)` (`0xc8a0ea88`) | [DegenerusAffiliate.defaultCodeById](../contracts/DegenerusAffiliate.sol) | None |
| `getReferrer(address)` (`0x4a9fefc7`) | [DegenerusAffiliate.getReferrer](../contracts/DegenerusAffiliate.sol) | None |
| `getReferrerById(uint32)` (`0x1738a1bd`) | [DegenerusAffiliate.getReferrerById](../contracts/DegenerusAffiliate.sol) | None |
| `getReferrerId(address)` (`0xbd4b77ee`) | [DegenerusAffiliate.getReferrerId](../contracts/DegenerusAffiliate.sol) | None |
| `getReferrerIdById(uint32)` (`0x8551d245`) | [DegenerusAffiliate.getReferrerIdById](../contracts/DegenerusAffiliate.sol) | None |
| `payAffiliate(uint256,bytes32,uint32,uint256,bool,uint16)` (`0xbfbadbc7`) | [DegenerusAffiliate.payAffiliate](../contracts/DegenerusAffiliate.sol) | None |
| `payAffiliateCombined_g3742656(bytes32,uint32,uint256,uint256,uint256,uint256,uint256,uint16)` (`0x00000005`) | [DegenerusAffiliate.payAffiliateCombined_g3742656](../contracts/DegenerusAffiliate.sol) | None |
| `referPlayer(bytes32)` (`0xfb0b2610`) | [DegenerusAffiliate.referPlayer](../contracts/DegenerusAffiliate.sol) | None |
| `referSmurf(uint32,uint32)` (`0xf3eb67cc`) | [DegenerusAffiliate.referSmurf](../contracts/DegenerusAffiliate.sol) | None |
| `referrerIds(address)` (`0x06bb8ae6`) | [DegenerusAffiliate.referrerIds](../contracts/DegenerusAffiliate.sol) | None |
| `referrerIdsById(uint32)` (`0xd7668d88`) | [DegenerusAffiliate.referrerIdsById](../contracts/DegenerusAffiliate.sol) | None |
| `totalAffiliateScore(uint24)` (`0x2bc165f4`) | [DegenerusAffiliate.totalAffiliateScore](../contracts/DegenerusAffiliate.sol) | None |

### DegenerusJackpots

Deployment aliases: `JACKPOTS`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `bafConsolationOf(address,uint24)` (`0x2c777194`) | [DegenerusJackpots.bafConsolationOf](../contracts/DegenerusJackpots.sol) | None |
| `bafConsolationOfId(uint32,uint24)` (`0xe0293ca2`) | [DegenerusJackpots.bafConsolationOfId](../contracts/DegenerusJackpots.sol) | None |
| `bafHeadWinner(uint24,uint256,uint8)` (`0x1a0f4693`) | [DegenerusJackpots.bafHeadWinner](../contracts/DegenerusJackpots.sol) | None |
| `bafPairWinners(uint24,uint256,uint256,uint256,uint8[3])` (`0x5d90c7e0`) | [DegenerusJackpots.bafPairWinners](../contracts/DegenerusJackpots.sol) | None |
| `beginBafOn(uint24)` (`0xa7076c3f`) | [DegenerusJackpots.beginBafOn](../contracts/DegenerusJackpots.sol) | None |
| `claimBafConsolation(uint32,uint24)` (`0x4629462e`) | [DegenerusJackpots.claimBafConsolation](../contracts/DegenerusJackpots.sol) | None |
| `finalizeBaf(uint24)` (`0xdce14dce`) | [DegenerusJackpots.finalizeBaf](../contracts/DegenerusJackpots.sol) | None |
| `getLastBafResolvedDay()` (`0x41ee28b1`) | [DegenerusJackpots.getLastBafResolvedDay](../contracts/DegenerusJackpots.sol) | None |
| `markBafSkippedAt(uint24,uint24)` (`0xaf8ab053`) | [DegenerusJackpots.markBafSkippedAt](../contracts/DegenerusJackpots.sol) | None |
| `recordBafFlip(uint32,uint24,uint256)` (`0x850d8d47`) | [DegenerusJackpots.recordBafFlip](../contracts/DegenerusJackpots.sol) | None |

### DegenerusParimutuel

Deployment aliases: `PARIMUTUEL`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `QUEST_BASE()` (`0x9e4a23f2`) | Compiler-generated getter | None |
| `STAKE()` (`0x125fdbbc`) | Compiler-generated getter | None |
| `marketState(address,uint24)` (`0xc1ca0ce7`) | [DegenerusParimutuel.marketState](../contracts/DegenerusParimutuel.sol) | None |
| `marketStateById(uint32,uint24)` (`0x9f013dbb`) | [DegenerusParimutuel.marketStateById](../contracts/DegenerusParimutuel.sol) | None |
| `placeBet(uint32,bool)` (`0x03746b9e`) | [DegenerusParimutuel.placeBet](../contracts/DegenerusParimutuel.sol) | None |
| `recordGrowth(uint24,bool)` (`0xa126a091`) | [DegenerusParimutuel.recordGrowth](../contracts/DegenerusParimutuel.sol) | None |
| `runGrowthWork(uint256)` (`0xc3510b73`) | [DegenerusParimutuel.runGrowthWork](../contracts/DegenerusParimutuel.sol) | None |

### DegenerusRecordBounty

Deployment aliases: `RECORD_BOUNTY`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `approve(address,uint256)` (`0x095ea7b3`) | [DegenerusRecordBounty.approve](../contracts/DegenerusRecordBounty.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | [DegenerusRecordBounty.balanceOf](../contracts/DegenerusRecordBounty.sol) | None |
| `getApproved(uint256)` (`0x081812fc`) | [DegenerusRecordBounty.getApproved](../contracts/DegenerusRecordBounty.sol) | None |
| `isApprovedForAll(address,address)` (`0xe985e9c5`) | [DegenerusRecordBounty.isApprovedForAll](../contracts/DegenerusRecordBounty.sol) | None |
| `name()` (`0x06fdde03`) | [DegenerusRecordBounty.name](../contracts/DegenerusRecordBounty.sol) | None |
| `ownerOf(uint256)` (`0x6352211e`) | [DegenerusRecordBounty.ownerOf](../contracts/DegenerusRecordBounty.sol) | None |
| `recordInfo(uint256)` (`0xb0ee7710`) | [DegenerusRecordBounty.recordInfo](../contracts/DegenerusRecordBounty.sol) | None |
| `recordSet(uint8,address,uint256,uint24)` (`0x89af1b30`) | [DegenerusRecordBounty.recordSet](../contracts/DegenerusRecordBounty.sol) | None |
| `renderColors()` (`0x6242303a`) | [DegenerusRecordBounty.renderColors](../contracts/DegenerusRecordBounty.sol) | None |
| `renderer()` (`0x8ada6b0f`) | Compiler-generated getter | None |
| `safeTransferFrom(address,address,uint256)` (`0x42842e0e`) | [DegenerusRecordBounty.safeTransferFrom](../contracts/DegenerusRecordBounty.sol) | None |
| `safeTransferFrom(address,address,uint256,bytes)` (`0xb88d4fde`) | [DegenerusRecordBounty.safeTransferFrom](../contracts/DegenerusRecordBounty.sol) | None |
| `setApprovalForAll(address,bool)` (`0xa22cb465`) | [DegenerusRecordBounty.setApprovalForAll](../contracts/DegenerusRecordBounty.sol) | None |
| `setRenderColors(string,string)` (`0x67939c5d`) | [DegenerusRecordBounty.setRenderColors](../contracts/DegenerusRecordBounty.sol) | None |
| `setRenderer(address)` (`0x56d3163d`) | [DegenerusRecordBounty.setRenderer](../contracts/DegenerusRecordBounty.sol) | None |
| `supportsInterface(bytes4)` (`0x01ffc9a7`) | [DegenerusRecordBounty.supportsInterface](../contracts/DegenerusRecordBounty.sol) | None |
| `symbol()` (`0x95d89b41`) | [DegenerusRecordBounty.symbol](../contracts/DegenerusRecordBounty.sol) | None |
| `tokenURI(uint256)` (`0xc87b56dd`) | [DegenerusRecordBounty.tokenURI](../contracts/DegenerusRecordBounty.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [DegenerusRecordBounty.transferFrom](../contracts/DegenerusRecordBounty.sol) | None |

## Custody, governance and tokens

### DegenerusVault

Deployment aliases: `VAULT`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `afkingSeatMint(address,uint256)` (`0x6933e2d8`) | [DegenerusVault.afkingSeatMint](../contracts/DegenerusVault.sol) | None |
| `burnCoin(uint256)` (`0xa3262e57`) | [DegenerusVault.burnCoin](../contracts/DegenerusVault.sol) | None |
| `burnEth(uint256)` (`0x680b376a`) | [DegenerusVault.burnEth](../contracts/DegenerusVault.sol) | None |
| `crapsComp(uint256[])` (`0x8ce7a983`) | [DegenerusVault.crapsComp](../contracts/DegenerusVault.sol) | None |
| `crapsCompAllowanceOf(address)` (`0x5dc4af82`) | Compiler-generated getter | None |
| `crapsCompDonate(bool,uint256,uint24)` (`0x4c320e63`) | [DegenerusVault.crapsCompDonate](../contracts/DegenerusVault.sol) | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `dgnrsUnwrapTo(address,uint256)` (`0x46b07623`) | [DegenerusVault.dgnrsUnwrapTo](../contracts/DegenerusVault.sol) | None |
| `dgve()` (`0xeef07008`) | [DegenerusVault.dgve](../contracts/DegenerusVault.sol) | None |
| `isVaultOwner(address)` (`0x8a66b2f3`) | [DegenerusVault.isVaultOwner](../contracts/DegenerusVault.sol) | None |
| `liquidationBuyConfig()` (`0x693adc7f`) | [DegenerusVault.liquidationBuyConfig](../contracts/DegenerusVault.sol) | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `playerAction(address,bytes,uint256)` (`0x2dfaf494`) | [DegenerusVault.playerAction](../contracts/DegenerusVault.sol) | None |
| `previewBurnForCoinOut(uint256)` (`0xa5f1d959`) | [DegenerusVault.previewBurnForCoinOut](../contracts/DegenerusVault.sol) | None |
| `previewBurnForEthOut(uint256)` (`0xaad73d08`) | [DegenerusVault.previewBurnForEthOut](../contracts/DegenerusVault.sol) | None |
| `previewCoin(uint256)` (`0x9a64b5fb`) | [DegenerusVault.previewCoin](../contracts/DegenerusVault.sol) | None |
| `previewEth(uint256)` (`0x52861cdc`) | [DegenerusVault.previewEth](../contracts/DegenerusVault.sol) | None |
| `setCrapsCompAllowance(address,uint256)` (`0x309f6641`) | [DegenerusVault.setCrapsCompAllowance](../contracts/DegenerusVault.sol) | None |
| `setLiquidationBuyFallback(bool,uint256)` (`0x450d28c9`) | [DegenerusVault.setLiquidationBuyFallback](../contracts/DegenerusVault.sol) | None |
| `spendDegenesis(uint32,bool,uint256,uint256,uint256)` (`0x551708ad`) | [DegenerusVault.spendDegenesis](../contracts/DegenerusVault.sol) | None |
| `sweepNft(address,address,uint256)` (`0x41de3f5a`) | [DegenerusVault.sweepNft](../contracts/DegenerusVault.sol) | None |
| `sweepToken(address,address,uint256)` (`0x64aff9ec`) | [DegenerusVault.sweepToken](../contracts/DegenerusVault.sol) | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `wwxrpMint(address,uint256)` (`0xf07e721a`) | [DegenerusVault.wwxrpMint](../contracts/DegenerusVault.sol) | None |

### DegenerusVaultShare

Deployment aliases: `created by Vault constructor (DGVE and DGVF)`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `INITIAL_SUPPLY()` (`0x2ff2e9dc`) | Compiler-generated getter | None |
| `allowance(address,address)` (`0xdd62ed3e`) | Compiler-generated getter | None |
| `approve(address,uint256)` (`0x095ea7b3`) | [DegenerusVaultShare.approve](../contracts/DegenerusVault.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | Compiler-generated getter | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `totalSupply()` (`0x18160ddd`) | Compiler-generated getter | None |
| `transfer(address,uint256)` (`0xa9059cbb`) | [DegenerusVaultShare.transfer](../contracts/DegenerusVault.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [DegenerusVaultShare.transferFrom](../contracts/DegenerusVault.sol) | None |
| `vaultBurn(address,uint256)` (`0xc2d57a5c`) | [DegenerusVaultShare.vaultBurn](../contracts/DegenerusVault.sol) | None |
| `vaultMint(address,uint256)` (`0xaa8c5c95`) | [DegenerusVaultShare.vaultMint](../contracts/DegenerusVault.sol) | None |

### sDGNRS

Deployment aliases: `SDGNRS`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `MIN_REDEMPTION_VALUE()` (`0xff1e793c`) | Compiler-generated getter | None |
| `balanceOf(address)` (`0x70a08231`) | Compiler-generated getter | None |
| `burn(uint256)` (`0x42966c68`) | [sDGNRS.burn](../contracts/sDGNRS.sol) | None |
| `burnAtGameOver()` (`0xc152fc45`) | [sDGNRS.burnAtGameOver](../contracts/sDGNRS.sol) | None |
| `burnForLiquidation(address)` (`0x2360a42c`) | [sDGNRS.burnForLiquidation](../contracts/sDGNRS.sol) | None |
| `burnWrapped(uint256)` (`0x3a9d8ed5`) | [sDGNRS.burnWrapped](../contracts/sDGNRS.sol) | None |
| `centurySupplyCheckpoint()` (`0x200bfe73`) | Compiler-generated getter | None |
| `claimRedemption(uint32,uint32)` (`0xbe2938d6`) | [sDGNRS.claimRedemption](../contracts/sDGNRS.sol) | None |
| `closeRedemptionBatch_g165517(uint256)` (`0x000027d8`) | [sDGNRS.closeRedemptionBatch_g165517](../contracts/sDGNRS.sol) | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `depositSteth(uint256)` (`0xe2cd1bb0`) | [sDGNRS.depositSteth](../contracts/sDGNRS.sol) | None |
| `flipReserve()` (`0x882f8ab0`) | [sDGNRS.flipReserve](../contracts/sDGNRS.sol) | None |
| `gameAdvance(uint32)` (`0xaae6655c`) | [sDGNRS.gameAdvance](../contracts/sDGNRS.sol) | None |
| `lastRecycledCentury()` (`0x45bab513`) | Compiler-generated getter | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `pendingRedemptionEthValue()` (`0x13e20fe5`) | [sDGNRS.pendingRedemptionEthValue](../contracts/sDGNRS.sol) | None |
| `pendingRedemptions(uint32,uint32)` (`0xf8d0a692`) | [sDGNRS.pendingRedemptions](../contracts/sDGNRS.sol) | None |
| `poolBalance(uint8)` (`0x96d8abb3`) | [sDGNRS.poolBalance](../contracts/sDGNRS.sol) | None |
| `previewBurnValue(uint256)` (`0x4ccf0c1c`) | [sDGNRS.previewBurnValue](../contracts/sDGNRS.sol) | None |
| `recycleCentury(uint24,uint256)` (`0x5290e525`) | [sDGNRS.recycleCentury](../contracts/sDGNRS.sol) | None |
| `recyclingClosed()` (`0x9e79c28e`) | Compiler-generated getter | None |
| `redemptionBatchState()` (`0x3ed762fe`) | [sDGNRS.redemptionBatchState](../contracts/sDGNRS.sol) | None |
| `redemptionBatches(uint32)` (`0x7c88d06b`) | [sDGNRS.redemptionBatches](../contracts/sDGNRS.sol) | None |
| `redemptionSettlementPending_g153837()` (`0x00003c46`) | [sDGNRS.redemptionSettlementPending_g153837](../contracts/sDGNRS.sol) | None |
| `resolveTerminalRedemptions()` (`0x85661984`) | [sDGNRS.resolveTerminalRedemptions](../contracts/sDGNRS.sol) | None |
| `runRedemptionWork(uint256,uint256)` (`0x2968e7c0`) | [sDGNRS.runRedemptionWork](../contracts/sDGNRS.sol) | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `totalSupply()` (`0x18160ddd`) | [sDGNRS.totalSupply](../contracts/sDGNRS.sol) | None |
| `transferFromPool_g106128(uint8,address,uint256)` (`0x00001d96`) | [sDGNRS.transferFromPool_g106128](../contracts/sDGNRS.sol) | None |
| `votingSupply()` (`0xe79dfcff`) | [sDGNRS.votingSupply](../contracts/sDGNRS.sol) | None |
| `wrapperTransferTo(address,uint256)` (`0xb6fb0ded`) | [sDGNRS.wrapperTransferTo](../contracts/sDGNRS.sol) | None |

### DGNRS

Deployment aliases: `DGNRS`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `allowance(address,address)` (`0xdd62ed3e`) | Compiler-generated getter | None |
| `approve(address,uint256)` (`0x095ea7b3`) | [DGNRS.approve](../contracts/DGNRS.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | Compiler-generated getter | None |
| `burn(uint256)` (`0x42966c68`) | [DGNRS.burn](../contracts/DGNRS.sol) | None |
| `burnForSdgnrs(address,uint256)` (`0x9a9be9c0`) | [DGNRS.burnForSdgnrs](../contracts/DGNRS.sol) | None |
| `claimVested()` (`0xd01c44cd`) | [DGNRS.claimVested](../contracts/DGNRS.sol) | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `previewBurnValue(uint256)` (`0x4ccf0c1c`) | [DGNRS.previewBurnValue](../contracts/DGNRS.sol) | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `totalSupply()` (`0x18160ddd`) | Compiler-generated getter | None |
| `totalUnwrapped()` (`0x1303bfb0`) | Compiler-generated getter | None |
| `transfer(address,uint256)` (`0xa9059cbb`) | [DGNRS.transfer](../contracts/DGNRS.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [DGNRS.transferFrom](../contracts/DGNRS.sol) | None |
| `unwrapTo(address,uint256)` (`0xc12ea3ca`) | [DGNRS.unwrapTo](../contracts/DGNRS.sol) | None |
| `yearSweep()` (`0xd2aa22aa`) | [DGNRS.yearSweep](../contracts/DGNRS.sol) | None |

### DegenerusAdmin

Deployment aliases: `ADMIN`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `activeProposalId(address)` (`0x6ad18550`) | [DegenerusAdmin.activeProposalId](../contracts/DegenerusAdmin.sol) | None |
| `canExecute(uint256)` (`0xcc63604a`) | [DegenerusAdmin.canExecute](../contracts/DegenerusAdmin.sol) | None |
| `coordinator()` (`0x0a009097`) | Compiler-generated getter | None |
| `donateVrf()` (`0x04722392`) | [DegenerusAdmin.donateVrf](../contracts/DegenerusAdmin.sol) | None |
| `proposalCount()` (`0xda35c664`) | Compiler-generated getter | None |
| `proposals(uint256)` (`0x013cf08b`) | Compiler-generated getter | None |
| `propose(address,bytes32,uint32)` (`0x2ac58877`) | [DegenerusAdmin.propose](../contracts/DegenerusAdmin.sol) | None |
| `retryGameRng()` (`0xbc9cc681`) | [DegenerusAdmin.retryGameRng](../contracts/DegenerusAdmin.sol) | None |
| `retrySubCancel(address,uint256)` (`0xeadc4120`) | [DegenerusAdmin.retrySubCancel](../contracts/DegenerusAdmin.sol) | None |
| `shutdownVrf()` (`0x9c2ea8cc`) | [DegenerusAdmin.shutdownVrf](../contracts/DegenerusAdmin.sol) | None |
| `subscriptionId()` (`0x09c1ba2e`) | Compiler-generated getter | None |
| `swapGameEthForStEth(address)` (`0x1f3e5e7a`) | [DegenerusAdmin.swapGameEthForStEth](../contracts/DegenerusAdmin.sol) | None |
| `threshold(uint256)` (`0x31eb7a1a`) | [DegenerusAdmin.threshold](../contracts/DegenerusAdmin.sol) | None |
| `vote(uint256,bool)` (`0xc9d27afe`) | [DegenerusAdmin.vote](../contracts/DegenerusAdmin.sol) | None |
| `voteWeight(uint256,address)` (`0x2b0a999d`) | [DegenerusAdmin.voteWeight](../contracts/DegenerusAdmin.sol) | None |
| `votes(uint256,address)` (`0xd23254b4`) | [DegenerusAdmin.votes](../contracts/DegenerusAdmin.sol) | None |
| `vrfKeyHash()` (`0x041d443e`) | Compiler-generated getter | None |

### GNRUS

Deployment aliases: `GNRUS`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `activeCount()` (`0x4331ed1f`) | [GNRUS.activeCount](../contracts/GNRUS.sol) | None |
| `activeCountAfterFlush()` (`0x1db86c1a`) | [GNRUS.activeCountAfterFlush](../contracts/GNRUS.sol) | None |
| `approve(address,uint256)` (`0x095ea7b3`) | [GNRUS.approve](../contracts/GNRUS.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | Compiler-generated getter | None |
| `burn(uint256)` (`0x42966c68`) | [GNRUS.burn](../contracts/GNRUS.sol) | None |
| `burnAtGameOver()` (`0xc152fc45`) | [GNRUS.burnAtGameOver](../contracts/GNRUS.sol) | None |
| `castBallot(uint8)` (`0x172d1121`) | [GNRUS.castBallot](../contracts/GNRUS.sol) | None |
| `currentActiveBitmap()` (`0xbf5967d7`) | Compiler-generated getter | None |
| `currentLevel()` (`0x9dc4b9c9`) | Compiler-generated getter | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `finalized()` (`0xb3f05b97`) | Compiler-generated getter | None |
| `getActiveSlots()` (`0x87e71768`) | [GNRUS.getActiveSlots](../contracts/GNRUS.sol) | None |
| `getCharity(uint8)` (`0x255535c8`) | [GNRUS.getCharity](../contracts/GNRUS.sol) | None |
| `getPendingEdits()` (`0x24d4db2f`) | [GNRUS.getPendingEdits](../contracts/GNRUS.sol) | None |
| `hasVoted(uint24,address,uint8)` (`0xa1fff7e3`) | [GNRUS.hasVoted](../contracts/GNRUS.sol) | None |
| `lastWinningRecipient()` (`0xf903c54d`) | Compiler-generated getter | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `onFinalSweep()` (`0xa4686a3d`) | [GNRUS.onFinalSweep](../contracts/GNRUS.sol) | None |
| `pendingEditSet()` (`0x19b73fca`) | Compiler-generated getter | None |
| `pickCharity(uint24)` (`0xa414074d`) | [GNRUS.pickCharity](../contracts/GNRUS.sol) | None |
| `setCharity(uint8,address)` (`0x74ea0124`) | [GNRUS.setCharity](../contracts/GNRUS.sol) | None |
| `slotApproveWeight(uint24,uint8)` (`0x4d68be86`) | [GNRUS.slotApproveWeight](../contracts/GNRUS.sol) | None |
| `sweepResidualToVault()` (`0x00560cd6`) | [GNRUS.sweepResidualToVault](../contracts/GNRUS.sol) | None |
| `sweptAt()` (`0xd887f2f5`) | Compiler-generated getter | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `totalSupply()` (`0x18160ddd`) | Compiler-generated getter | None |
| `transfer(address,uint256)` (`0xa9059cbb`) | [GNRUS.transfer](../contracts/GNRUS.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [GNRUS.transferFrom](../contracts/GNRUS.sol) | None |
| `vaultRedeemFor(address)` (`0x6aabf13f`) | [GNRUS.vaultRedeemFor](../contracts/GNRUS.sol) | None |

### FLIP

Deployment aliases: `COIN`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `allowance(address,address)` (`0xdd62ed3e`) | Compiler-generated getter | None |
| `approve(address,uint256)` (`0x095ea7b3`) | [FLIP.approve](../contracts/FLIP.sol) | None |
| `autoDecimatorBurn(uint24,uint256)` (`0xcc7a7e90`) | [FLIP.autoDecimatorBurn](../contracts/FLIP.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | Compiler-generated getter | None |
| `balanceOfWithClaimable(address)` (`0xc22000eb`) | [FLIP.balanceOfWithClaimable](../contracts/FLIP.sol) | None |
| `burnCoinForCraps_g292454(address,uint32,uint256)` (`0x0000ac1e`) | [FLIP.burnCoinForCraps_g292454](../contracts/FLIP.sol) | None |
| `burnCoin_g27673(address,uint256)` (`0x00007f29`) | [FLIP.burnCoin_g27673](../contracts/FLIP.sol) | None |
| `burnForCoinflip(address,uint256)` (`0x4e40540c`) | [FLIP.burnForCoinflip](../contracts/FLIP.sol) | None |
| `crapsCompAllowance()` (`0x5885b23e`) | [FLIP.crapsCompAllowance](../contracts/FLIP.sol) | None |
| `creditCrapsComps_g37225(uint256)` (`0x000038c2`) | [FLIP.creditCrapsComps_g37225](../contracts/FLIP.sol) | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `decimatorBurn(uint32,uint256,uint32)` (`0x62eb3fdb`) | [FLIP.decimatorBurn](../contracts/FLIP.sol) | None |
| `mintForGame_g152734(address,uint256)` (`0x000016e3`) | [FLIP.mintForGame_g152734](../contracts/FLIP.sol) | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `supplyIncUncirculated()` (`0x878bb039`) | [FLIP.supplyIncUncirculated](../contracts/FLIP.sol) | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `tombstoneAtGameOver()` (`0x5439615f`) | [FLIP.tombstoneAtGameOver](../contracts/FLIP.sol) | None |
| `totalSupply()` (`0x18160ddd`) | [FLIP.totalSupply](../contracts/FLIP.sol) | None |
| `transfer(address,uint256)` (`0xa9059cbb`) | [FLIP.transfer](../contracts/FLIP.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [FLIP.transferFrom](../contracts/FLIP.sol) | None |
| `vaultMintAllowance()` (`0x72f95142`) | [FLIP.vaultMintAllowance](../contracts/FLIP.sol) | None |
| `vaultMintTo(address,uint256)` (`0x8e48a2fa`) | [FLIP.vaultMintTo](../contracts/FLIP.sol) | None |

### WWXRP

Deployment aliases: `WWXRP`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `BIG_PRIZE()` (`0x0c713236`) | Compiler-generated getter | None |
| `BUCKET_COUNT()` (`0x08677959`) | Compiler-generated getter | None |
| `MIN_BURN()` (`0x49844b1c`) | Compiler-generated getter | None |
| `SMALL_PRIZE()` (`0xb8b3b48d`) | Compiler-generated getter | None |
| `allowance(address,address)` (`0xdd62ed3e`) | Compiler-generated getter | None |
| `approve(address,uint256)` (`0x095ea7b3`) | [WWXRP.approve](../contracts/WWXRP.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | Compiler-generated getter | None |
| `bucketInfo(uint24,uint8)` (`0x7e8c4ede`) | [WWXRP.bucketInfo](../contracts/WWXRP.sol) | None |
| `bucketOf(uint24,uint32)` (`0x1cbd4a7e`) | [WWXRP.bucketOf](../contracts/WWXRP.sol) | None |
| `burnForAccount(uint32,uint256)` (`0xd57c99a5`) | [WWXRP.burnForAccount](../contracts/WWXRP.sol) | None |
| `burnForGame(address,uint256)` (`0x3e39cad0`) | [WWXRP.burnForGame](../contracts/WWXRP.sol) | None |
| `claim(uint24,uint32)` (`0x31297217`) | [WWXRP.claim](../contracts/WWXRP.sol) | None |
| `claimable(uint32)` (`0xd2b6d422`) | [WWXRP.claimable](../contracts/WWXRP.sol) | None |
| `consumeBoon(uint32)` (`0x0d75832a`) | [WWXRP.consumeBoon](../contracts/WWXRP.sol) | None |
| `creditPrize(uint32,uint256)` (`0x109debc7`) | [WWXRP.creditPrize](../contracts/WWXRP.sol) | None |
| `dayClaimed(uint24)` (`0xab52858e`) | [WWXRP.dayClaimed](../contracts/WWXRP.sol) | None |
| `decimals()` (`0x313ce567`) | Compiler-generated getter | None |
| `drawMultBps(uint256)` (`0xda3e60b3`) | [WWXRP.drawMultBps](../contracts/WWXRP.sol) | None |
| `enterDraw(uint32,uint256)` (`0x0724b15a`) | [WWXRP.enterDraw](../contracts/WWXRP.sol) | None |
| `entryAt(uint24,uint8,uint32)` (`0x01618a98`) | [WWXRP.entryAt](../contracts/WWXRP.sol) | None |
| `findWinningEntry(uint24)` (`0x75fbcbe0`) | [WWXRP.findWinningEntry](../contracts/WWXRP.sol) | None |
| `gameMintScale()` (`0x700849e2`) | Compiler-generated getter | None |
| `incineratorEntryAt(uint24,uint32)` (`0xf8a1f35b`) | [WWXRP.incineratorEntryAt](../contracts/WWXRP.sol) | None |
| `incineratorInfo(uint24)` (`0x08a85132`) | [WWXRP.incineratorInfo](../contracts/WWXRP.sol) | None |
| `mintPrize(address,uint256)` (`0xa5a2e99f`) | [WWXRP.mintPrize](../contracts/WWXRP.sol) | None |
| `name()` (`0x06fdde03`) | Compiler-generated getter | None |
| `previewOutcome(uint24)` (`0xad29b4c6`) | [WWXRP.previewOutcome](../contracts/WWXRP.sol) | None |
| `resolveIncinerator(uint24,uint256)` (`0xb47cc919`) | [WWXRP.resolveIncinerator](../contracts/WWXRP.sol) | None |
| `setGameMintScale(uint256)` (`0xefd4f157`) | [WWXRP.setGameMintScale](../contracts/WWXRP.sol) | None |
| `setTrustedMinter(address,bool)` (`0xb5ab8766`) | [WWXRP.setTrustedMinter](../contracts/WWXRP.sol) | None |
| `symbol()` (`0x95d89b41`) | Compiler-generated getter | None |
| `totalSupply()` (`0x18160ddd`) | Compiler-generated getter | None |
| `transfer(address,uint256)` (`0xa9059cbb`) | [WWXRP.transfer](../contracts/WWXRP.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [WWXRP.transferFrom](../contracts/WWXRP.sol) | None |
| `trustedMinter(address)` (`0x538e5162`) | Compiler-generated getter | None |
| `vaultMintTo(address,uint256)` (`0x8e48a2fa`) | [WWXRP.vaultMintTo](../contracts/WWXRP.sol) | None |
| `withdraw(uint32,uint256)` (`0x0e19dc3a`) | [WWXRP.withdraw](../contracts/WWXRP.sol) | None |
| `withdrawAcquired(uint32)` (`0x3785d09d`) | [WWXRP.withdrawAcquired](../contracts/WWXRP.sol) | None |

### DegenerusOwnerGovernance

Deployment aliases: `OWNER_GOVERNANCE`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `PROPOSAL_LIFETIME()` (`0x582109ad`) | Compiler-generated getter | None |
| `canExecute(uint256)` (`0xcc63604a`) | [DegenerusOwnerGovernance.canExecute](../contracts/DegenerusOwnerGovernance.sol) | None |
| `clearVote(address)` (`0x5ae61f92`) | [DegenerusOwnerGovernance.clearVote](../contracts/DegenerusOwnerGovernance.sol) | None |
| `deposit(uint256,address)` (`0x6e553f65`) | [DegenerusOwnerGovernance.deposit](../contracts/DegenerusOwnerGovernance.sol) | None |
| `dgve()` (`0xeef07008`) | Compiler-generated getter | None |
| `directAction(bytes,address[])` (`0x04a8a5e0`) | [DegenerusOwnerGovernance.directAction](../contracts/DegenerusOwnerGovernance.sol) | None |
| `execute(uint256,bytes)` (`0x59efcb15`) | [DegenerusOwnerGovernance.execute](../contracts/DegenerusOwnerGovernance.sol) | None |
| `isAllowed(address,bytes4)` (`0xab15ce83`) | [DegenerusOwnerGovernance.isAllowed](../contracts/DegenerusOwnerGovernance.sol) | None |
| `positions(address)` (`0x55f57510`) | Compiler-generated getter | None |
| `proposal(uint256)` (`0x30326c17`) | [DegenerusOwnerGovernance.proposal](../contracts/DegenerusOwnerGovernance.sol) | None |
| `proposalCount()` (`0xda35c664`) | Compiler-generated getter | None |
| `propose(address,address,uint256,bytes,uint256)` (`0x49abfe44`) | [DegenerusOwnerGovernance.propose](../contracts/DegenerusOwnerGovernance.sol) | None |
| `setVotingDelegate(address)` (`0xd8939127`) | [DegenerusOwnerGovernance.setVotingDelegate](../contracts/DegenerusOwnerGovernance.sol) | None |
| `settledWeight(uint256)` (`0x8854e941`) | [DegenerusOwnerGovernance.settledWeight](../contracts/DegenerusOwnerGovernance.sol) | None |
| `support(address,uint256,uint256)` (`0x77641456`) | [DegenerusOwnerGovernance.support](../contracts/DegenerusOwnerGovernance.sol) | None |
| `totalEscrowed()` (`0xf9168231`) | Compiler-generated getter | None |
| `withdraw()` (`0x3ccfd60b`) | [DegenerusOwnerGovernance.withdraw](../contracts/DegenerusOwnerGovernance.sol) | None |

### DegenerusDeityPass

Deployment aliases: `DEITY_PASS`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `approve(address,uint256)` (`0x095ea7b3`) | [DegenerusDeityPass.approve](../contracts/DegenerusDeityPass.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | [DegenerusDeityPass.balanceOf](../contracts/DegenerusDeityPass.sol) | None |
| `getApproved(uint256)` (`0x081812fc`) | [DegenerusDeityPass.getApproved](../contracts/DegenerusDeityPass.sol) | None |
| `isApprovedForAll(address,address)` (`0xe985e9c5`) | [DegenerusDeityPass.isApprovedForAll](../contracts/DegenerusDeityPass.sol) | None |
| `mint(address,uint256)` (`0x40c10f19`) | [DegenerusDeityPass.mint](../contracts/DegenerusDeityPass.sol) | None |
| `name()` (`0x06fdde03`) | [DegenerusDeityPass.name](../contracts/DegenerusDeityPass.sol) | None |
| `ownerOf(uint256)` (`0x6352211e`) | [DegenerusDeityPass.ownerOf](../contracts/DegenerusDeityPass.sol) | None |
| `renderColors()` (`0x6242303a`) | [DegenerusDeityPass.renderColors](../contracts/DegenerusDeityPass.sol) | None |
| `renderer()` (`0x8ada6b0f`) | Compiler-generated getter | None |
| `safeTransferFrom(address,address,uint256)` (`0x42842e0e`) | [DegenerusDeityPass.safeTransferFrom](../contracts/DegenerusDeityPass.sol) | None |
| `safeTransferFrom(address,address,uint256,bytes)` (`0xb88d4fde`) | [DegenerusDeityPass.safeTransferFrom](../contracts/DegenerusDeityPass.sol) | None |
| `seize(uint256,address)` (`0xa7dab972`) | [DegenerusDeityPass.seize](../contracts/DegenerusDeityPass.sol) | None |
| `setApprovalForAll(address,bool)` (`0xa22cb465`) | [DegenerusDeityPass.setApprovalForAll](../contracts/DegenerusDeityPass.sol) | None |
| `setRenderColors(string,string,string)` (`0x86a036bc`) | [DegenerusDeityPass.setRenderColors](../contracts/DegenerusDeityPass.sol) | None |
| `setRenderer(address)` (`0x56d3163d`) | [DegenerusDeityPass.setRenderer](../contracts/DegenerusDeityPass.sol) | None |
| `supportsInterface(bytes4)` (`0x01ffc9a7`) | [DegenerusDeityPass.supportsInterface](../contracts/DegenerusDeityPass.sol) | None |
| `symbol()` (`0x95d89b41`) | [DegenerusDeityPass.symbol](../contracts/DegenerusDeityPass.sol) | None |
| `tokenURI(uint256)` (`0xc87b56dd`) | [DegenerusDeityPass.tokenURI](../contracts/DegenerusDeityPass.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [DegenerusDeityPass.transferFrom](../contracts/DegenerusDeityPass.sol) | None |

### AFKingSubscriptionToken

Deployment aliases: `AFKING_SUB_TOKEN`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `FREE_TRANCHE()` (`0x3dbf579c`) | Compiler-generated getter | None |
| `SEAT_CAP()` (`0x7e24c68f`) | Compiler-generated getter | None |
| `approve(address,uint256)` (`0x095ea7b3`) | [AFKingSubscriptionToken.approve](../contracts/AFKingSubscriptionToken.sol) | None |
| `balanceOf(address)` (`0x70a08231`) | [AFKingSubscriptionToken.balanceOf](../contracts/AFKingSubscriptionToken.sol) | None |
| `consumeSeat(address,uint256)` (`0xa1c94ef7`) | [AFKingSubscriptionToken.consumeSeat](../contracts/AFKingSubscriptionToken.sol) | None |
| `freeClaims()` (`0x860347d5`) | Compiler-generated getter | None |
| `getApproved(uint256)` (`0x081812fc`) | [AFKingSubscriptionToken.getApproved](../contracts/AFKingSubscriptionToken.sol) | None |
| `isApprovedForAll(address,address)` (`0xe985e9c5`) | [AFKingSubscriptionToken.isApprovedForAll](../contracts/AFKingSubscriptionToken.sol) | None |
| `mintSeatFor(address)` (`0x3ea24bdc`) | [AFKingSubscriptionToken.mintSeatFor](../contracts/AFKingSubscriptionToken.sol) | None |
| `name()` (`0x06fdde03`) | [AFKingSubscriptionToken.name](../contracts/AFKingSubscriptionToken.sol) | None |
| `nextSerial()` (`0x08ae6377`) | Compiler-generated getter | None |
| `ownerOf(uint256)` (`0x6352211e`) | [AFKingSubscriptionToken.ownerOf](../contracts/AFKingSubscriptionToken.sol) | None |
| `renderer()` (`0x8ada6b0f`) | Compiler-generated getter | None |
| `safeTransferFrom(address,address,uint256)` (`0x42842e0e`) | [AFKingSubscriptionToken.safeTransferFrom](../contracts/AFKingSubscriptionToken.sol) | None |
| `safeTransferFrom(address,address,uint256,bytes)` (`0xb88d4fde`) | [AFKingSubscriptionToken.safeTransferFrom](../contracts/AFKingSubscriptionToken.sol) | None |
| `seatTraits(uint256)` (`0x8cae5297`) | [AFKingSubscriptionToken.seatTraits](../contracts/AFKingSubscriptionToken.sol) | None |
| `setApprovalForAll(address,bool)` (`0xa22cb465`) | [AFKingSubscriptionToken.setApprovalForAll](../contracts/AFKingSubscriptionToken.sol) | None |
| `setRenderer(address)` (`0x56d3163d`) | [AFKingSubscriptionToken.setRenderer](../contracts/AFKingSubscriptionToken.sol) | None |
| `setSeatTraits(uint256,uint8,uint24,uint24)` (`0x927fde01`) | [AFKingSubscriptionToken.setSeatTraits](../contracts/AFKingSubscriptionToken.sol) | None |
| `supportsInterface(bytes4)` (`0x01ffc9a7`) | [AFKingSubscriptionToken.supportsInterface](../contracts/AFKingSubscriptionToken.sol) | None |
| `symbol()` (`0x95d89b41`) | [AFKingSubscriptionToken.symbol](../contracts/AFKingSubscriptionToken.sol) | None |
| `tokenURI(uint256)` (`0xc87b56dd`) | [AFKingSubscriptionToken.tokenURI](../contracts/AFKingSubscriptionToken.sol) | None |
| `totalSupply()` (`0x18160ddd`) | [AFKingSubscriptionToken.totalSupply](../contracts/AFKingSubscriptionToken.sol) | None |
| `transferFrom(address,address,uint256)` (`0x23b872dd`) | [AFKingSubscriptionToken.transferFrom](../contracts/AFKingSubscriptionToken.sol) | None |
| `vaultMintSeats(address,uint256)` (`0x3869dc24`) | [AFKingSubscriptionToken.vaultMintSeats](../contracts/AFKingSubscriptionToken.sol) | None |

## Readers and display dependencies

### DegenerusGameLens

Deployment aliases: `optional reader/renderer`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `accountBalances(address,uint32)` (`0xab701ef1`) | [DegenerusGameLens.accountBalances](../contracts/DegenerusGameLens.sol) | None |
| `accountInfo(address,uint32)` (`0x0aebfb53`) | [DegenerusGameLens.accountInfo](../contracts/DegenerusGameLens.sol) | None |
| `activeTicketLevelOf(address)` (`0xdad8c618`) | [DegenerusGameLens.activeTicketLevelOf](../contracts/DegenerusGameLens.sol) | None |
| `activityScoreBreakdown(address,address)` (`0x65b2b9b5`) | [DegenerusGameLens.activityScoreBreakdown](../contracts/DegenerusGameLens.sol) | None |
| `activityScoreBreakdownById(address,uint32)` (`0x9a96ca9f`) | [DegenerusGameLens.activityScoreBreakdownById](../contracts/DegenerusGameLens.sol) | None |
| `afkingSnapshot(address,address[])` (`0x6d72803b`) | [DegenerusGameLens.afkingSnapshot](../contracts/DegenerusGameLens.sol) | None |
| `boonPacked(uint32)` (`0x401fe997`) | Compiler-generated getter | None |
| `decBattleRoundOf(address,uint24)` (`0x5daa5825`) | [DegenerusGameLens.decBattleRoundOf](../contracts/DegenerusGameLens.sol) | None |
| `decBurnOf(address,uint24,address)` (`0xb4c6b580`) | [DegenerusGameLens.decBurnOf](../contracts/DegenerusGameLens.sol) | None |
| `decBurnOfById(address,uint24,uint32)` (`0xe00c92e9`) | [DegenerusGameLens.decBurnOfById](../contracts/DegenerusGameLens.sol) | None |
| `decBurnReferenceOf(address)` (`0xb2ab340d`) | [DegenerusGameLens.decBurnReferenceOf](../contracts/DegenerusGameLens.sol) | None |
| `decEntryAt(address,uint24,uint64)` (`0x04854d5d`) | [DegenerusGameLens.decEntryAt](../contracts/DegenerusGameLens.sol) | None |
| `decJackpotPlanOf(address,uint24)` (`0xde7f74d8`) | [DegenerusGameLens.decJackpotPlanOf](../contracts/DegenerusGameLens.sol) | None |
| `decSettleCursorOf(address)` (`0xea41cd43`) | [DegenerusGameLens.decSettleCursorOf](../contracts/DegenerusGameLens.sol) | None |
| `decSurvivorAt(uint256,uint24,uint64,uint16)` (`0x629105aa`) | [DegenerusGameLens.decSurvivorAt](../contracts/DegenerusGameLens.sol) | None |
| `decWinnerAt(address,uint24,uint8)` (`0x1c0d992f`) | [DegenerusGameLens.decWinnerAt](../contracts/DegenerusGameLens.sol) | None |
| `deityOwnerAt(address,uint256)` (`0xdc68dc74`) | [DegenerusGameLens.deityOwnerAt](../contracts/DegenerusGameLens.sol) | None |
| `deityPassSalesCount(address)` (`0x2b4d5eab`) | [DegenerusGameLens.deityPassSalesCount](../contracts/DegenerusGameLens.sol) | None |
| `findProtocolBoonWinners(address,address,uint24)` (`0xcec64726`) | [DegenerusGameLens.findProtocolBoonWinners](../contracts/DegenerusGameLens.sol) | None |
| `findQueueEntry(address,uint24,uint32,uint32,uint16)` (`0x6e646f55`) | [DegenerusGameLens.findQueueEntry](../contracts/DegenerusGameLens.sol) | None |
| `findTraitEntry(address,uint24,uint8,uint32[],uint32,uint16)` (`0xbf3d77bf`) | [DegenerusGameLens.findTraitEntry](../contracts/DegenerusGameLens.sol) | None |
| `foilRecordOf(address,uint24,address)` (`0x45aca8c4`) | [DegenerusGameLens.foilRecordOf](../contracts/DegenerusGameLens.sol) | None |
| `foilRecordOfById(address,uint24,uint32)` (`0x43f64659`) | [DegenerusGameLens.foilRecordOfById](../contracts/DegenerusGameLens.sol) | None |
| `gameOver()` (`0xbdb337d1`) | Compiler-generated getter | None |
| `levelDgnrsInfo(address,uint24)` (`0xa9729857`) | [DegenerusGameLens.levelDgnrsInfo](../contracts/DegenerusGameLens.sol) | None |
| `loanOf(address,uint32)` (`0x569f744e`) | [DegenerusGameLens.loanOf](../contracts/DegenerusGameLens.sol) | None |
| `loansDue(address,uint24)` (`0x46a4e58a`) | [DegenerusGameLens.loansDue](../contracts/DegenerusGameLens.sol) | None |
| `previewBorrow(address,uint32,uint24,uint256)` (`0x8a824b7d`) | [DegenerusGameLens.previewBorrow](../contracts/DegenerusGameLens.sol) | None |
| `protocolBoonEntryAt(address,address,uint24,uint32)` (`0xa3821ec4`) | [DegenerusGameLens.protocolBoonEntryAt](../contracts/DegenerusGameLens.sol) | None |
| `protocolBoonPool(address,address,uint24)` (`0xf8e3adf9`) | [DegenerusGameLens.protocolBoonPool](../contracts/DegenerusGameLens.sol) | None |
| `protocolBoonQuote(address,address,uint256)` (`0xf4a91043`) | [DegenerusGameLens.protocolBoonQuote](../contracts/DegenerusGameLens.sol) | None |
| `protocolBoonQuoteById(address,uint32,uint256)` (`0xf7deb3a9`) | [DegenerusGameLens.protocolBoonQuoteById](../contracts/DegenerusGameLens.sol) | None |
| `smurfCreationInfo(address,uint32)` (`0x65435796`) | [DegenerusGameLens.smurfCreationInfo](../contracts/DegenerusGameLens.sol) | None |
| `smurfsOf(address,uint32)` (`0xa3b9325d`) | [DegenerusGameLens.smurfsOf](../contracts/DegenerusGameLens.sol) | None |
| `subInfoFull(address,address)` (`0x13cc169c`) | [DegenerusGameLens.subInfoFull](../contracts/DegenerusGameLens.sol) | None |
| `subInfoFullById(address,uint32)` (`0xdc58db5e`) | [DegenerusGameLens.subInfoFullById](../contracts/DegenerusGameLens.sol) | None |
| `walletIdOf(address,address)` (`0xbc27d0bd`) | [DegenerusGameLens.walletIdOf](../contracts/DegenerusGameLens.sol) | None |
| `walletOfId(address,uint32)` (`0x61ca53aa`) | [DegenerusGameLens.walletOfId](../contracts/DegenerusGameLens.sol) | None |

### CrapsLens

Deployment aliases: `optional reader/renderer`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `highRollerDrawOf(uint64)` (`0xfd6993a8`) | [CrapsLens.highRollerDrawOf](../contracts/CrapsLens.sol) | None |
| `highRollerReserve()` (`0xf7e4173d`) | [CrapsLens.highRollerReserve](../contracts/CrapsLens.sol) | None |
| `jackpotBattleOf(uint64)` (`0x2091119a`) | [CrapsLens.jackpotBattleOf](../contracts/CrapsLens.sol) | None |
| `jackpotEntryPrice()` (`0x1621ffbf`) | [CrapsLens.jackpotEntryPrice](../contracts/CrapsLens.sol) | None |
| `jackpotEntryPriceOf(uint64)` (`0xe15f1772`) | [CrapsLens.jackpotEntryPriceOf](../contracts/CrapsLens.sol) | None |
| `preferredBoardOf(uint32)` (`0x76330a19`) | [CrapsLens.preferredBoardOf](../contracts/CrapsLens.sol) | None |
| `progressivePool()` (`0xa8a62831`) | [CrapsLens.progressivePool](../contracts/CrapsLens.sol) | None |

### DeityBoonViewer

Deployment aliases: `optional reader/renderer`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `deityBoonSlots(address,address)` (`0x10ac38b1`) | [DeityBoonViewer.deityBoonSlots](../contracts/DeityBoonViewer.sol) | None |
| `deityBoonSlotsById(address,uint32)` (`0xdf1662b4`) | [DeityBoonViewer.deityBoonSlotsById](../contracts/DeityBoonViewer.sol) | None |
| `deityBoonSlotsTomorrow(address,address)` (`0xbc66d14b`) | [DeityBoonViewer.deityBoonSlotsTomorrow](../contracts/DeityBoonViewer.sol) | None |
| `deityBoonSlotsTomorrowById(address,uint32)` (`0x05893ca8`) | [DeityBoonViewer.deityBoonSlotsTomorrowById](../contracts/DeityBoonViewer.sol) | None |

### Icons32Data

Deployment aliases: `ICONS_32`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `COMPLETE_MASK()` (`0x1ccb3d66`) | Compiler-generated getter | None |
| `bootstrapClosed()` (`0x10ce1da3`) | Compiler-generated getter | None |
| `data(uint256)` (`0xf0ba8440`) | [Icons32Data.data](../contracts/Icons32Data.sol) | None |
| `finalize()` (`0x4bb278f3`) | [Icons32Data.finalize](../contracts/Icons32Data.sol) | None |
| `finalizeOnBootstrap()` (`0x7a639f3e`) | Compiler-generated getter | None |
| `finalized()` (`0xb3f05b97`) | [Icons32Data.finalized](../contracts/Icons32Data.sol) | None |
| `initializedMask()` (`0xf5ff334c`) | Compiler-generated getter | None |
| `setPaths(uint256,string[])` (`0xf79618c9`) | [Icons32Data.setPaths](../contracts/Icons32Data.sol) | None |
| `setSymbols(uint256,string[8])` (`0xfc5bcc13`) | [Icons32Data.setSymbols](../contracts/Icons32Data.sol) | None |
| `symbol(uint256,uint8)` (`0x23b67b08`) | [Icons32Data.symbol](../contracts/Icons32Data.sol) | None |

### DeityPassCustomizationRenderer

Deployment aliases: `optional reader/renderer`.

| External entry (selector) | Implementing function | Direct delegate destinations |
| --- | --- | --- |
| `BACKGROUND()` (`0x9d3b6ec8`) | Compiler-generated getter | None |
| `BADGE_BACKGROUND()` (`0xf7625e77`) | Compiler-generated getter | None |
| `GEOMETRY()` (`0x8efc09e9`) | Compiler-generated getter | None |
| `OUTLINE()` (`0x016dd65c`) | Compiler-generated getter | None |
| `RIM()` (`0x72e53389`) | Compiler-generated getter | None |
| `SYMBOL()` (`0xf76f8d78`) | Compiler-generated getter | None |
| `clearTokenColors(uint256)` (`0x95a999c2`) | [DeityPassCustomizationRenderer.clearTokenColors](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `clearTokenCustomization(uint256)` (`0x82e29692`) | [DeityPassCustomizationRenderer.clearTokenCustomization](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `clearTokenGeometry(uint256)` (`0xbecd6591`) | [DeityPassCustomizationRenderer.clearTokenGeometry](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `effectiveTokenStyle(uint256)` (`0x075f6afb`) | [DeityPassCustomizationRenderer.effectiveTokenStyle](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `geometryBounds()` (`0xc282a953`) | [DeityPassCustomizationRenderer.geometryBounds](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `isValidGeometry(uint16,int16,int16)` (`0x6075d4db`) | [DeityPassCustomizationRenderer.isValidGeometry](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `pass()` (`0xa7a1ed72`) | Compiler-generated getter | None |
| `positionBounds(uint16)` (`0x178cdc85`) | [DeityPassCustomizationRenderer.positionBounds](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `render(uint256,uint8,uint8,string,string,bool,string,string,string)` (`0x32d1c5f6`) | [DeityPassCustomizationRenderer.render](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `setTokenColors(uint256,(string,string,string,string,string))` (`0xc79dd5aa`) | [DeityPassCustomizationRenderer.setTokenColors](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `setTokenGeometry(uint256,(uint16,int16,int16))` (`0x423b52cf`) | [DeityPassCustomizationRenderer.setTokenGeometry](../contracts/DeityPassCustomizationRenderer.sol) | None |
| `tokenCustomization(uint256)` (`0x01ce8bcb`) | [DeityPassCustomizationRenderer.tokenCustomization](../contracts/DeityPassCustomizationRenderer.sol) | None |
