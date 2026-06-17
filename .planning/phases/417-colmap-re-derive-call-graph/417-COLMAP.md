# 417-COLMAP — Authoritative Spinal-Column Map (current HEAD)

Subject tree: frozen `contracts/` @ `0dd445a6`. Read-only synthesis of the 12 per-slice
call-graph maps (417-colmap-*.md) + the authoritative `DegenerusGame` storage layout
(`417-game-storage-layout.json`). This is the load-bearing input for phases
**418 BRICK · 419 DELEGATE · 420 CORRUPT · 421 MIDRNG · 422 GAMEOVER · 423 VRFSWAP**.

## Architecture in one paragraph

`DegenerusGame.sol` is a **dispatch HUB** (`address(this)` = the delegatecall HOST). Every
external entry is either (a) a HUB-local body, or (b) a thin `delegatecall` stub into a fixed
`ContractAddresses.GAME_*_MODULE` constant. **All 13 module bodies execute in Game storage** —
so every "module storage write" below lands in a Game slot from `417-game-storage-layout.json`.
The real **spine** is `advanceGame()` → `GAME_ADVANCE_MODULE` (raw `msg.data` DC), which itself
self-calls (Game CALL → DC) the Jackpot/Decimator/GameOver modules for level transitions and
terminal finalization, producing **nested delegatecalls** (Game→Advance→{Jackpot|Decimator|
GameOver|Mint|Afking}). There is **NO** `delegatecall(msg.data)` to an attacker-chosen
target/selector anywhere; every DC target is a compile-time module constant.

> RECONCILE NOTE: `hub-entries` and `hub-statemachine` are two views of the SAME file
> (`DegenerusGame.sol`). `hub-entries` is the SUPERSET (all 64 entry/stub fns). `hub-statemachine`
> is the 38-fn advance/VRF/gameOver-focused subset of those same functions — it is NOT additive.
> All HUB counts below use `hub-entries` as canonical; PERMANENT-CANDIDATE classifications from
> `hub-statemachine` are merged into the single HUB row set.

---

# COLMAP-01 — COLUMN CALL GRAPH (merged, by entry point)

Legend: `DC` = delegatecall into a fixed module constant · `DC(msg.data)` = raw calldata-forward
DC · `nested DC` = DC issued from inside a module that is itself running under DC · `→X` =
synchronous external CALL to FLIP(COIN)/Coinflip/Vault/sDGNRS/Affiliate/Quests/stETH/WWXRP/GNRUS.

## A. THE SPINE — `advanceGame()` :279 → `DC(msg.data)` GAME_ADVANCE_MODULE

Body lives in `DegenerusGameAdvanceModule.advanceGame()` :168. Reachable also via the
permissionless router `mintFlip()` :376 → `DC` GAME_AFKING_MODULE → `mintFlip` self-calls
`IGameRouter(this).advanceGame()` (Afking:1589).

```
advanceGame (HUB :279)
└─ DC(msg.data) GAME_ADVANCE_MODULE.advanceGame (:168)         [spine body]
   ├─ _runProcessTicketBatch (:1539)  ── nested DC → GAME_MINT_MODULE.processTicketBatch
   ├─ _processFutureTicketBatch (:1470) nested DC → GAME_MINT_MODULE.processFutureTicketBatch
   ├─ _prepareFutureTickets (:1495, ×4) nested DC → GAME_MINT_MODULE.processFutureTicketBatch
   ├─ _runSubscriberStage (:796)       nested DC → GAME_AFKING_MODULE.processSubscriberStage (:1152)
   │     └─ →X QUESTS.finalizeAfking (evict / funding-kill legs only)
   ├─ rngGate (:1195)                                          [new-day RNG seal]
   │     ├─ _backfillGapDays (:1869, ≤120)  →X coinflip.processCoinflipPayouts (per gap day)
   │     ├─ _backfillOrphanedLootboxIndices (:1894, UNBOUNDED)
   │     ├─ →X coinflip.processCoinflipPayouts (:1234)
   │     ├─ →X quests.rollDailyQuest (:1239)
   │     ├─ →X IsDGNRS(SDGNRS).pendingResolveDay/resolveRedemptionPeriod (:1253/:1258)
   │     └─ _requestRng → VRF request (sets rngLockedFlag)
   ├─ _consolidatePoolsAndRewardJackpots (:822)                [level-transition leg]
   │     ├─ →X coinflip.creditFlip(SDGNRS) (:984)
   │     ├─ →X dgnrs.poolBalance / dgnrs.transferFromPool  (_rewardTopAffiliate :742/:748)
   │     ├─ →X jackpots.markBafSkipped (:934)
   │     ├─ self-CALL runBafJackpot (:926) → Game stub :1013 → DC GAME_JACKPOT_MODULE [nested]
   │     └─ self-CALL runDecimatorJackpot (:948) → Game stub :991 → DC GAME_DECIMATOR_MODULE [nested]
   ├─ self-CALL emitDailyWinningTraits (:468) → Game stub :1121 → DC GAME_JACKPOT_MODULE [nested]
   ├─ payDailyJackpot / payDailyJackpotCoinAndTickets / _payDailyCoinJackpot
   │     nested DC → GAME_JACKPOT_MODULE
   │     └─ →X coinflip.creditFlipBatch (Jackpot _awardDaily*/_awardFarFuture* :1678/:1752)
   ├─ _distributeYieldSurplus (:772) nested DC → GAME_JACKPOT_MODULE
   │     └─ →X steth.balanceOf (Jackpot :683)
   ├─ →X quests.rollLevelQuest (:537)
   ├─ _unlockRng (:1799)  →X steth.balanceOf (day-seal snapshot emit :1815)
   ├─ _finalizeRngRequest (:1693)  →X charityResolve.pickCharity (:1745) [level-increment leg]
   └─ _handleGameOverPath (:605)                               [terminal path — see section B]
```

VRF stubs into GAME_ADVANCE_MODULE: `wireVrf` :302, `updateVrfCoordinatorAndSub` :1776,
`requestLootboxRng` :1792, `retryLootboxRng` :1804, `rawFulfillRandomWords` :1856 (VRF callback;
`lootboxRngWordByIndex[index]=word`).

## B. TERMINAL FINALIZATION — `_handleGameOverPath` (Advance :605) → GameOver module

```
_handleGameOverPath (Advance :605)
├─ nested DC GAME_GAMEOVER_MODULE.handleFinalSweep (:621)
├─ nested DC GAME_MINT_MODULE.processTicketBatch(lvl+1) (:664)  [revert SWALLOWED on !dOk]
├─ _gameOverEntropy (:1293)  →X coinflip.processCoinflipPayouts / IsDGNRS.resolveRedemptionPeriod
└─ nested DC GAME_GAMEOVER_MODULE.handleGameOverDrain(day) (:692)
      GameOver.handleGameOverDrain (:73)
      ├─ →X charityGameOver.burnAtGameOver() / dgnrs.burnAtGameOver() / flip.tombstoneAtGameOver()
      │     (:139/:140/:142 — NO try/catch)
      ├─ →X steth.balanceOf(this) (:78/:157/:165)
      ├─ deity-refund loop (:106, ≤ deityPassOwners.length) → _creditClaimable
      ├─ self-CALL runTerminalDecimatorJackpot (:177) → Game stub :1068 → DC GAME_DECIMATOR_MODULE [nested]
      │     └─ Decimator.runTerminalDecimatorJackpot (:978) — writes decBucketOffsetPacked[lvl+1]
      └─ self-CALL runTerminalJackpot (:191) → Game stub :1099 → DC GAME_JACKPOT_MODULE [nested]
GameOver.handleFinalSweep (:203)  [30-day final sink sweep]
├─ →X admin.shutdownVrf() (:220, try/catch — swallowed)
├─ →X steth.balanceOf(this) (:223)
└─ _sendStethFirst (:250) ×3 → →X steth.transfer (:253/:257) + payable(VAULT/SDGNRS/GNRUS).call{value} (:261)
```

## C. CLAIM / PAYOUT (HUB-local, touches solvency aggregate)

```
claimWinnings (:1209) → _claimWinningsInternal (:1229) → _debitClaimableAndAfking + claimablePool -=
   → _payoutWithStethFallback (:1888) | _payoutWithEthFallback (:1922)
      → _transferSteth (:1873): if to==SDGNRS →X steth.approve + dgnrs.depositSteth; else →X steth.transfer
      → →X payable(to).call{value} LAST (CEI)
   THEN DC GAME_AFKING_MODULE.maybeCurse(player) (:1217)  [post-payout; maybeCurse has NO revert site]
claimWinningsStethFirst (:1224, VAULT-only) → _claimWinningsInternal(stethFirst=true)
depositAfkingFunding (:1263, payable) / receive (:2481, payable) → _creditAfkingValue (afking half + claimablePool +=)
withdrawAfkingFunding (:1275) → _debitAfking + claimablePool -= → →X msg.sender.call{value}
pullRedemptionReserve (:1572, SDGNRS-only) → _debitClaimable + claimablePool -= → →X SDGNRS.call{value} | steth.balanceOf(SDGNRS)
```

## D. PURCHASE / MINT legs (user/keeper; share spine storage)

```
purchase (:552, payable) → _purchaseFor → MINT_MODULE.purchase (_purchaseForWithCached :1491)
   ├─ nested DC GAME_BOON_MODULE.consumePurchaseBoost (Mint :2062, payable, msg.value in flight)
   ├─ →X quests.handlePurchase (:1677)
   ├─ →X affiliate.payAffiliate ×≤2 / affiliate.affiliateBonusPointsBest (view)
   └─ →X coinflip.creditFlip (:1830)
redeemFlip :596 · buyPresaleBox :618 (payable) · buyLootboxAndPresaleBox :646 (payable) → MINT_MODULE
purchaseWhaleBundle :704 (payable) → WHALE_MODULE.purchaseWhaleBundle
   └─ →X sDGNRS.transferFromPool/poolBalance ×up to ~100×6 · Affiliate.getReferrer · Quests.effectiveBaseStreakAndAfking
purchaseLazyPass :729 / purchaseDeityPass :749 (payable) → WHALE_MODULE  (deityPass gated on rngLockedFlag)
sellFarFutureTickets :1610 → MINT_MODULE → →X VAULT.salvageBuyConfig · coin.burnCoinForSalvage · coinflip.creditFlip → _purchaseFor chain
```

## E. LOOTBOX / DEGENERETTE / BOX-OPEN (permissionless valves + recirc)

```
openBoxes (:1442) → DC GAME_AFKING_MODULE.drainAfkingBoxes  THEN  DC GAME_LOOTBOX_MODULE.openHumanBoxes
   GameAfkingModule._openAfkingBox (:1463) nested DC GAME_LOOTBOX_MODULE.resolveAfkingBox (:1474)
   LootboxModule.openHumanBoxes (:656) → _resolveLootboxCommon (:1247):
      ├─ nested DC GAME_BOON_MODULE.consumeActivityBoon (:1281) / checkAndClearExpiredBoon (:1418)
      ├─ nested DC GAME_DEGENERETTE_MODULE.resolveWwxrpSpinFromBox/resolveFlipSpinsFromBox/resolveEthSpinFromBox
      │     (:2098/:2117/:2136)  [Game→Lootbox→Degenerette; resolveEthSpin issues a FURTHER recirc DC → depth ≥3]
      └─ →X coinflip.creditFlip · dgnrs.poolBalance/transferFromPool · wwxrp.mintPrize · QUESTS.awardQuestStreakShield
openBox (:676) → DC GAME_LOOTBOX_MODULE.openBox  (manual both-leg)
resolveRedemptionLootbox (:1532, payable, SDGNRS-only) → DC GAME_LOOTBOX_MODULE  → →X steth.transferFrom; 5-ETH while-loop (UNBOUNDED)
creditRedemptionDirect (:1552, payable, SDGNRS-only) → DC GAME_LOOTBOX_MODULE → →X steth.transferFrom
issueDeityBoon (:898) → DC GAME_LOOTBOX_MODULE.issueDeityBoon
degeneretteResolve (:1339) → do-while → this._degeneretteResolveBet (:1479, onlySelf) → DC GAME_DEGENERETTE_MODULE.resolveBets
   → →X coinflip.creditFlip(msg.sender) (:1379, ≥3-success reward)
placeDegeneretteBet :774 (payable) / resolveDegeneretteBets :803 → DC GAME_DEGENERETTE_MODULE
```

## F. DECIMATOR record/claim + boon dispatch (COIN/self-gated)

```
recordDecBurn :968 / recordTerminalDecBurn :1038 (COIN-gated) → DC GAME_DECIMATOR_MODULE
   recordTerminalDecBurn → self-STATICCALL IDegenerusGame(this).playerActivityScore → →X QUESTS.effectiveBaseStreakAndAfking
boostTerminalDecimator :1053 → DC GAME_DECIMATOR_MODULE → self-STATICCALL playerActivityScore (→QUESTS)
claimDecimatorJackpot[Many] :1138/:1150 / claimTerminalDecimatorJackpot :1164 → DC GAME_DECIMATOR_MODULE
   _awardDecimatorLootbox (:645) nested DC GAME_LOOTBOX_MODULE.resolveLootboxDirect (:669)
   claimDecimatorJackpotMany → →X coinflip.creditFlip (keeper bounty :365)
consumeCoinflipBoon :827 (COIN/COINFLIP-gated) → DC(msg.data) GAME_BOON_MODULE  [raw calldata forward, single-depth]
consumeDecimatorBoon :846 (COIN-gated) → DC GAME_BOON_MODULE.consumeDecimatorBoost
payCoinflipBountyDgnrs :453 (COIN/COINFLIP-gated) → →X dgnrs.poolBalance / dgnrs.transferFromPool
```

## G. BINGO / AFFILIATE / AFKING-SUB (claim leaves)

```
claimBingo :317 → DC GAME_BINGO_MODULE → →X dgnrs.transferFromPool · coinflip.creditFlip  (reverts E() once gameOver)
claimAffiliateDgnrs :1304 → DC GAME_BINGO_MODULE → →X affiliate.affiliateScore/totalAffiliateScore · dgnrs.transferFromPool · coinflip.creditFlip
subscribe :357 (payable) / mintFlip :376 / claimAfkingFlip :389 / drainAffiliateBase :402 / decurse :416 / smite :428 / recordAfkingSecondary :439 → DC GAME_AFKING_MODULE
   subscribe → →X AFFILIATE.claim([sub]) (reentrant) · QUESTS.beginAfking · COINFLIP.creditFlip
```

## H. SYNCHRONOUS-EXTERNAL CALLEE leaves (`callees` slice — plain CALL, write only their own storage)

The advance spine's ONLY Coinflip entry is `processCoinflipPayouts`; the ONLY callee-of-callee
revert that reaches advance is its sDGNRS auto-claim (mints FLIP/WWXRP). Cross-contract callees:
- **Coinflip** `processCoinflipPayouts` (on spine) · `creditFlip`/`creditFlipBatch` · `consumeCoinflipsForBurn`
- **sDGNRS** `resolveRedemptionPeriod` (on spine, every advance with a stamped pool) · `transferFromPool` · `burnAtGameOver` · `claimRedemption`/`Many` · `depositSteth`
- **FLIP (COIN)** `mintForGame` (reached by sDGNRS seed-window auto-claim on spine) · `burnCoin`/`burnCoinForSalvage` · `tombstoneAtGameOver`
- **Affiliate** `payAffiliate` · `claim` · `affiliateScore`/`affiliateBonusPointsBest`/`getReferrer`
- **Vault** — NO callee ON the column (Vault is a CALLER into Game; its `receive()` push cannot revert-bubble into advance)

---

# COLMAP-02 — REVERT-SITE INVENTORY (merged; input to 418 BRICK-01)

Legend: **PERM** = PERMANENT-CANDIDATE (can wedge `advanceGame` progress or `gameOver`
finalization, OR permanently brick a non-spine column path post-liveness). **TRANS** = transient
(another actor/retry/next block makes progress; the spine is unaffected).

## PERMANENT-CANDIDATE set (the 418 BRICK-01 work list)

| # | slice | site | trigger | error | why PERM |
|---|---|---|---|---|---|
| P1 | hub/advance | `advanceGame:283` (HUB) / Advance `advanceGame:283` | module DC `!ok` (rngGate/batch/drain/jackpot) bubbles | bubbled `E()` | any unconditional-revert state in GAME_ADVANCE_MODULE wedges the daily spine |
| P2 | hub/advance | `rawFulfillRandomWords:1863` (HUB) / Advance VRF body | VRF callback module DC `!ok` (coordinator-gate / stale requestId / nudge math) | bubbled | no word lands → rngLock never clears → spine stalls until 12h/14d bailout |
| P3 | hub/advance/jackpot | `runTerminalJackpot:1104/1108/1109` | onlySelf from `handleGameOverDrain:191`; module `!ok`/empty | `E()`/bubbled | wedges terminal-jackpot payout/finalization |
| P4 | hub/advance/decimator | `runTerminalDecimatorJackpot:1073/1077/1078` | onlySelf from `handleGameOverDrain:177`; `!ok`/empty | `E()`/bubbled | wedges terminal-decimator finalization |
| P5 | hub/advance/jackpot | `runDecimatorJackpot:996/1000/1001` | onlySelf from advance orchestration (x00 levels); `!ok`/empty | `E()`/bubbled | wedges advance at decimator levels |
| P6 | hub/advance/jackpot | `runBafJackpot:1018/1022/1023` | onlySelf from advance (L%100==0 / L%10); `!ok`/empty | `E()`/bubbled | wedges advance at BAF levels |
| P7 | hub/jackpot | `emitDailyWinningTraits:1126/1130` | onlySelf from advance at purchaseLevel==1; `!ok` | `E()`/bubbled | wedges first-coin-distribution advance step |
| P8 | advance | `_runProcessTicketBatch:1553` | MintModule returns 0-len data (or inner revert) | `E()` | wedges the daily ticket-drain gate every new-day advance crosses |
| P9 | advance | `_processFutureTicketBatch:1484` | MintModule returns 0-len data (or inner revert) | `E()` | wedges FF/near-future processing on every transition/jackpot advance leg |
| P10 | advance | `_consolidatePoolsAndRewardJackpots:846` | `(memFuture*100)/memNext` div-by-zero if next pool==0 | Panic 0x12 | reverts the lastPurchase level-transition leg |
| P11 | advance | `_consolidatePoolsAndRewardJackpots:899` | `memNext -= take + skim` underflow (caps bound to 81%) | Panic 0x11 | invariant break wedges the transition |
| P12 | advance | `_unlockRng:1815` | `steth.balanceOf(this)` reverts inside day-seal snapshot emit | bubbles | day-seal chokepoint EVERY completed day crosses |
| P13 | advance | `_finalizeRngRequest:1745` | `charityResolve.pickCharity(lvl-1)` reverts at level-transition RNG request | bubbles | blocks the level-increment leg |
| P14 | advance/hub | `advanceGame:283` (Advance) pre-RNG drain gate | `rngWordCurrent==0` while read ticket slot non-empty | `RngNotReady()` | new-day drain gate; no LOCAL timeout — recovery rides on rngGate(12h)/`_gameOverEntropy`(14d) |
| P15 | jackpot | `payDailyJackpot:446/451/530` | checked `curPool/futureBal -= budget` underflow (paid > cached budget) | Panic 0x11 | solvency break panics → reverts whole payDailyJackpot → advanceGame |
| P16 | decimator/gameover | `handleGameOverDrain:94` | `preRefundAvailable!=0 && rngWordByDay[day]==0` | `E()` | game-over finalization reverts; caller word-set guarantee load-bearing |
| P17 | decimator/gameover | `handleGameOverDrain:139-142` | `GNRUS.burnAtGameOver()`/`sDGNRS.burnAtGameOver()`/`FLIP.tombstoneAtGameOver()` revert (NO try/catch) | bubbles | any reverting callee bricks game-over finalization (gameOver=true rolls back) |
| P18 | decimator/gameover | `handleGameOverDrain:177/191` | nested terminal jackpot/decimator self-call reverts | bubbles | whole drain reverts; gameOver cannot finalize |
| P19 | decimator/gameover | `_sendStethFirst:253/257/261` | `steth.transfer()==false` / `payable(VAULT|SDGNRS|GNRUS).call{value}` rejected | `E()` | hard-revert wedges `handleFinalSweep` (30-day sink sweep) until sink accepts |
| P20 | callees | sDGNRS `resolveRedemptionPeriod:756` | checked uint96 `(_pendingRedemptionEthValue - segregatedMax + rolledEth)` underflow | Panic 0x11 | runs on EVERY advance with a stamped pool — a cumulative-scalar drift wedges advanceGame forever |
| P21 | callees | sDGNRS `burnAtGameOver:614` | checked `(_totalSupply - bal)` underflow at gameOver | Panic 0x11 | bricks gameOver |
| P22 | callees | FLIP `tombstoneAtGameOver:563` | checked uint128 add `(vaultAllowance+1e36)` overflow at gameOver | Panic 0x11 | bricks gameOver (one-shot latch, ~340× headroom) |
| P23 | callees | FLIP `mintForGame` `_toUint128:372` / WWXRP `_mint` | SupplyOverflow / ZeroAddress on the spine sDGNRS seed-window auto-claim (Coinflip :447/:638) | bubbles | bubbles into `processCoinflipPayouts` → advance |
| P24 | afking | `_queueTicketsScaled:650` (callee, on STAGE) | `_livenessTriggered()` latches during a TICKET-mode afking sub buy | `E()` | STAGE runs inside advanceGame; the STAGE buy is NOT liveness-gated → bubbles into advance |
| P25 | afking | `_finalizeAfking:1073` (on STAGE evict/funding-kill) | `QUESTS.finalizeAfking` not total for evicted player | bubbles | bubbles into advanceGame |
| P26 | afking | `_deliverAfkingBuy:804/805/811/812` (on STAGE) | `_debitAfking`/`claimablePool -=` underflow (fail-loud SOLVENCY-01) | Panic 0x11 | permanently wedges advance if solvency ever violated (intended signal; kept unreachable by 1-wei sentinel) |
| P27 | afking | `mintFlip:1589` self-call advanceGame + `:1615` CEI-last `COINFLIP.creditFlip` | advance revert OR creditFlip revert for caller | bubbles | a caller for whom creditFlip reverts does the advance work then loses it every tx (must confirm creditFlip total) |
| P28 | hub | `_claimWinningsInternal:1248` | checked `claimablePool -= payout` underflow | Panic 0x11 | solvency-accounting break (ISOLATED to claim tx, not advance — PERM only for that claim) |
| P29 | callees | sDGNRS `_claimRedemptionFor:868` | checked uint96 `(_pendingRedemptionEthValue - totalRolledEth)` underflow | Panic 0x11 | bricks that player's claim + locks segregated ETH (off advance spine) |

### Non-spine PERMANENT-CANDIDATEs — wedge a permissionless column path, not advance

| # | slice | site | trigger | note |
|---|---|---|---|---|
| P30 | lootbox | `_resolveLootboxCommon:1284` (`consumeActivityBoon !okAct`) | persistent BoonModule revert on a ready box (owner has pending activity bonus) | wedges the openHumanBoxes sweep cursor (never skips a failing entry) |
| P31 | lootbox | `_rollLootboxBoons:1421` (`checkAndClearExpiredBoon !okClr`) | owner holds a non-zero boon slot | same sweep-wedge |
| P32 | lootbox/degenerette | `_callWwxrpSpin:2107`/`_callFlipSpins:2126`/`_callEthSpin:2145` | persistent Degenerette spin revert on a roll box | sweep-wedge / direct-open box revert |
| P33 | lootbox | `_openLootBoxLegWith:545` | `rngWord==0` (manual `openBox`/`_openLootBoxLeg`) | PERM until index word lands (TRANSIENT in sweep — L682 pre-gate) |
| P34 | lootbox/mint/afking/jackpot/decimator | `_queueTickets:618` / `_queueTicketRange:715` (post-liveness) | `_livenessTriggered()` true on resolveLootboxDirect/resolveAfkingBox/redemption/whale-queue | INTENDED anti-manipulation; permanently reverts those claim paths post-liveness — verify the gameOver drain settles those funds |
| P35 | degenerette | `resolveBets:435` | `_livenessTriggered()` true | EVERY resolveBets (incl. onlySelf `_degeneretteResolveBet`) reverts post-liveness — verify drain settles pending degenerette bets |
| P36 | degenerette | `resolveEthSpinFromBox→_distributePayout:884` | frozen pool `acc.pendingFuture < ethShare` | runs inside nested box-open (afking auto-open / advance recirc) — could brick the surrounding open/advance tx |
| P37 | degenerette | `_resolveFullTicketBet:777` | `acc.flipMint -= totalPayout` underflow (cross-bet accumulator order in multi-id resolveBets) | underflow reverts the whole batch |
| P38 | mint | `_callTicketPurchase:2070` (nested BoonModule `consumePurchaseBoost`) | any unconditional revert added to consumePurchaseBoost | would brick EVERY ETH-purchase ticket leg (frozen target is non-reverting) |
| P39 | mint | `processTicketBatch:840` | `lootboxRngWordByIndex[uint48(LR_INDEX)-1]` underflow if LR_INDEX==0 with non-empty queue | LR_INDEX init=1 + monotonic → unreachable; only arithmetic in the otherwise revert-free current-ticket drain |
| P40 | decimator | `_decRemoveSubbucket:618` / `_creditDecJackpotClaimCore:462` / `boostTerminalDecimator:942` | subbucket/claimable/weight underflow (off-column) | conservation-invariant guarded; blocks only that burn/claim/boost |
| P41 | small | `consumeActivityBoon:331` (`quests.awardQuestStreakBonus` revert) | runs nested inside lootbox/redemption resolution | bubbles to LootboxModule:1284 → bricks that player's claim |
| P42 | small | `_playerActivityScore*:344` (`affiliate.affiliateBonusPointsBest` revert) | called ON the spine via Afking:827/874 + Mint:1710 when affiliate-bonus cache misses | bubbles into mintFlip/afking advance work |
| P43 | small | `_bountyEligible:79` (`Vault.isVaultOwner` revert) | advance-bounty gate (GameAfking:1582) cold-path view | reverts the bounty-eligibility tx (advance work still permitted) |

## TRANSIENT set (representative — full per-slice rows in the source maps)

HUB access/input gates (all TRANS): `initPerpetualTickets:218` · `_revertDelegate:949` ·
`wireVrf/updateVrfCoordinatorAndSub/requestLootboxRng/retryLootboxRng` admin/side bubbles ·
`payCoinflipBountyDgnrs:461/471` · `setOperatorApproval:487` · `consumeCoinflipBoon:833` ·
`consumeDecimatorBoon:849` · `_resolvePlayer/_requireApproved:505` (NotApproved) ·
`degeneretteResolve:1344/1351(BatchAlreadyTaken)/1378(NoWork)/1379` ·
`reverseFlip:1818(RngLocked)/1821` · `withdrawAfkingFunding:1276/1279/1281/1283` ·
`pullRedemptionReserve:1573/1585/1599` · `adminSwap/StakeEthForStEth` gates ·
`_payoutWithStethFallback:1914`/`_payoutWithEthFallback:1933/1935`/`_transferSteth:1876/1880`
(claimant-receiver reverts — pull pattern, isolated). Advance side: `advanceGame:230(RngNotReady)`
/`:251(NotTimeYet)` · `rngGate:1273(12h)` · `_gameOverEntropy:1364(14d)` ·
`requestLootboxRng/retryLootboxRng` standalone gates. Mint: all `_purchaseForWithCached`/
`_buyPresaleBoxFor`/`sellFarFutureTickets`/`_redeemFlipFor` input+liveness+RngLock gates.
Whale: all `_rewardWhaleBundleDgnrs`/`_rewardDeityPassDgnrs` sDGNRS reverts (brick only that
purchase). Afking: all subscribe/decurse/smite input+auth gates; **`maybeCurse` has ZERO revert
sites** (every gate is an early return — can NEVER brick a winnings cashout). Decimator/GameOver:
all `claim*` access/state gates; `admin.shutdownVrf()` (try/catch swallowed). Callees: all
`RngLocked`/`BurnsBlockedBeforeDailyRng`/`livenessTriggered` player-path gates (none on spine).

---

# COLMAP-03 — LOOP INVENTORY (merged; input to 418 BRICK-04 gas ceiling)

| slice | site | bound | class | per-iter cost / note |
|---|---|---|---|---|
| **advance** | `_backfillOrphanedLootboxIndices:1894` | consecutive empty `lootboxRngWordByIndex[i]` below LR_INDEX (grows with un-fulfilled mid-day reservations during a VRF stall) | **UNBOUNDED** | 1 SSTORE + emit/iter; **only uncapped loop on/near the spine**; runs SAME tx as the ≤120 gap backfill (rngGate gap branch) |
| advance | `_backfillGapDays:1869` | `endDay-startDay`, capped 120 | BOUNDED(120)/input-sized | each iter: SSTORE + `→X coinflip.processCoinflipPayouts` + emit → up to 120 external calls in one tx |
| advance | `_getHistoricalRngFallback:1394` | `min(currentDay,30)`, early-break found==5 | BOUNDED(≤30) | SLOAD + hash2 |
| advance | `_prepareFutureTickets:1513` | fixed 4 (lvl+1..lvl+4) | BOUNDED(4) | nested DC MintModule batch per iter |
| advance | `_queueTicketRange:713` (storage) | `numLevels` | BOUNDED | off this slice's column (whale-pass) |
| **afking** | `processSubscriberStage:1185` | `min(weightBudget-derived, _subscribers.length≤1000)` | BOUNDED | weights: lootbox 2/ticket 4/evict 1/skip 1; chunked via `_subCursor`; **ON SPINE** |
| afking | `_autoOpen:1523` | `min(maxCount=OPEN_BATCH 80, _subscribers.length≤1000)` | BOUNDED | ~74k/box × 80 ≈ 9.15M < 16.7M; nested DC resolveAfkingBox/box |
| afking | `claimAfkingFlip:1691` | `subs.length` (calldata) | UNBOUNDED/input | off spine; caller pays gas |
| **mint** | `processTicketBatch:878` / `processFutureTicketBatch:586` | `WRITES_BUDGET_SAFE=550` (×0.65 first batch) | BOUNDED | **revert-free**, `ticketCursor`-resumable; the spine ticket drain |
| mint | `_raritySymbolBatch:737/753/788/805` | write-budget-derived (≤256 traits; Σoccurrences ≤ count) | BOUNDED | assembly bulk SSTORE into traitBurnTicket |
| mint | `sellFarFutureTickets:1293` | `len` ≤32 (checked :1253) | BOUNDED/input | off spine |
| mint | `previewSellFarFutureTickets:1188` / `_quoteFarFutureSwap:187` | `levels.length` | UNBOUNDED/input | VIEW-only |
| **lootbox** | `resolveRedemptionLootbox:951` | `ceil(amount / 5 ether)` (sDGNRS-burn-sized) | **UNBOUNDED/input** | each chunk = full `_resolveLootboxCommon` (2 nested DC + several →X) + hash1; **NO per-tx budget cap** (unlike openHumanBoxes); off spine but can exceed block gas for a large single claim |
| lootbox | `openHumanBoxes:675/686` (outer+inner) | `budget` (caller `steps` cap) | BOUNDED | persistent `(boxCursorIndex, boxCursor)` |
| lootbox | `_lazyPassPriceForLevel:2288` / `_boonFromRoll` | fixed 10 / fixed weight count | BOUNDED | pure |
| **jackpot** | `runBafJackpot:1930` | `winnersArr.length` (returned by external `jackpots.runBafJackpot`; cap enforced INSIDE DegenerusJackpots, not here) | UNBOUNDED-at-this-layer | **gas-brick of advance BAF leg gated on a cross-contract cap** — verify the cap |
| jackpot | (19 other loops in slice) | fixed bracket/symbol counts (4×8 hero, trait winners, etc.) | BOUNDED | parent rngWord-derived |
| **decimator** | `runDecimatorJackpot:243` / `runTerminalDecimatorJackpot:995` | fixed 11 (denom 2..12) | BOUNDED | pure resolution; no revert |
| decimator | `handleGameOverDrain:106` (deity refund) | `deityPassOwners.length` (only lvl<10) | STATE-SIZED, **ON COLUMN** | design-capped ~32 (1/symbol) but NO in-body cap; budget `break`; **runs inside gameOver finalization** — verify deityPassOwners cannot grow unbounded |
| decimator | `claimDecimatorJackpotMany:343` | `players.length` (calldata) | UNBOUNDED/input | off column; nested lootbox DC per settled box |
| **degenerette** | `resolveBets:439` | `betIds.length` (calldata, no cap) | UNBOUNDED/input | gas = len × ticketCount; player self-DoS; off spine |
| **whale** | `_purchaseWhaleBundle:339` | `quantity` ≤100 (:179) | BOUNDED/input | up to ~6 sDGNRS calls/iter → ~600 cross-contract calls/tx |
| **callees** | Coinflip `creditFlipBatch:986` / sDGNRS `claimRedemptionMany:804` / Affiliate `claim:617` | `players.length`/`subs.length` (caller) | UNBOUNDED/input | all OFF the advance spine; gas-bounded by caller's own budget |
| **hub** | `initPerpetualTickets:219` | fixed 1..100 | BOUNDED | one-time deploy wiring (VAULT/SDGNRS) |
| hub | `degeneretteResolve:1356` (do-while) | `players.length` (caller) | UNBOUNDED/input | per-item try/catch isolated, self-paying |
| hub | `_currentNudgeCost:1838` | `totalFlipReversals` (FLIP-supply-bounded) | STATE-SIZED, economically capped | pure arith |
| hub | `afkingSnapshot:2270` / `getTickets:2409` / `sampleFarFutureTickets` / `getDailyHeroWinner` | players.length / caller limit / fixed | VIEW-only | no spine gas-wedge |

**Gas-ceiling (16.7M) brick-relevant compositions for 418 BRICK-04:**
1. `_backfillGapDays`(≤120 ext coinflip) + `_backfillOrphanedLootboxIndices`(UNBOUNDED) in ONE tx (rngGate gap branch, L1220+L1224) — the two are NOT decoupled from each other.
2. `runBafJackpot:1930` winner loop — bound lives in the external DegenerusJackpots cap.
3. `resolveRedemptionLootbox:951` 5-ETH while-loop — no per-tx budget cap.
4. `handleGameOverDrain:106` deity-refund loop — sized by `deityPassOwners.length`.

---

# COLMAP-04 — DELEGATECALL STORAGE-WRITE → SLOT TABLE (input to 419 DELEGATE-01 + 420 CORRUPT-01)

Every module runs in Game storage. Below maps each Game-storage variable a module writes to its
authoritative slot/offset from `417-game-storage-layout.json`. **PACKED slot, multi-module, or
offset/level/day-keyed writes are flagged** — those are the CORRUPT-01 / DEC-ALIAS surface.

## Slot/offset reference (from the layout JSON)

| slot | offset(byte) | field | type | writers (modules) |
|---|---|---|---|---|
| **0** | 0 | purchaseStartDay | uint24 | HUB(ctor), Advance(:426 + `+=gapCount`) |
| 0 | 3 | dailyIdx | uint24 | HUB(ctor), Advance `_unlockRng:1798` |
| 0 | 6 | rngRequestTime | uint48 | Advance (`_finalizeRngRequest`/`_unlockRng`/`requestLootboxRng`/`retryLootboxRng`/`_gameOverEntropy`/`updateVrfCoordinatorAndSub`) |
| 0 | 12 | level | uint24 | Advance `_finalizeRngRequest:1727` (level increment) |
| 0 | 15 | jackpotPhaseFlag | bool | Advance (:532=true / via transition) |
| 0 | 16 | jackpotCounter | uint8 | Jackpot `payDailyJackpotCoinAndTickets:610`; Advance `_endPhase:711=0` |
| 0 | 17 | lastPurchaseDay | bool | Advance (:202/:492/:534) |
| 0 | 18 | decWindowOpen | bool | Advance `_finalizeRngRequest:1733/1737` |
| 0 | 19 | rngLockedFlag | bool | Advance `_finalizeRngRequest:1696=true`/`_unlockRng:1799=false` |
| 0 | 20 | phaseTransitionActive | bool | Advance (:424=false / `_endPhase:707=true`) |
| 0 | 21 | gameOver | bool | **GameOver `handleGameOverDrain:135=true` ONLY** (Advance reads only) |
| 0 | 22 | dailyJackpotCoinTicketsPending | bool | Jackpot `payDailyJackpot:463`/`payDailyJackpotCoinAndTickets:614` |
| 0 | 23 | compressedJackpotFlag | uint8 | Advance (:203/:494; `_endPhase`=0) |
| 0 | 24 | ticketsFullyProcessed | bool | Advance (:241/:300/:456; `_handleGameOverPath:685`; `_swapTicketSlot:800`) |
| 0 | 25 | ticketWriteSlot | bool | Advance `_swapTicketSlot:799` |
| 0 | 26 | prizePoolFrozen | bool | Advance `_swapAndFreeze:812=true`/`_unfreezePool:832=false` |
| 0 | 27 | presaleOver | bool | Mint `_buyPresaleBoxFor:1971=true` |
| 0 | 28 | subsFullyProcessed | bool | Advance (:325/:347/:360) |
| 0 | 29 | presaleDrained | bool | Lootbox `openHumanBoxes:728=true` |
| 0 | 30 | ticketRedemptionOpen | bool | Mint `_redeemFlipFor:1109=true`; Advance `_finalizeRngRequest:1715=false` |
| **1** | 0 | currentPrizePool | uint128 | Advance `_consolidate:999`; Jackpot (:360/:446/:451); GameOver `_setCurrentPrizePool:147=0` |
| 1 | 16 | claimablePool | uint128 | **6+ modules** — Advance `_consolidate:1002`; Mint `_processMintPayment:297`/`_settleShortfall`/`_creditAfkingValue`; Lootbox `creditRedemptionDirect:1014`; Jackpot `_processDailyEth:1119`/`distributeYieldSurplus:713`; Decimator `_creditDecJackpotClaimCore:462`; GameOver(:130/:180/:217=0); Afking(:354/:805/:812); Whale; Degenerette; HUB(claim/deposit/withdraw/pull) |
| **2** | 0 | prizePoolsPacked | uint256 [next128\|future128] | **5+ modules** — Advance `_setPrizePools`; Mint; Lootbox(:946); Jackpot(:361/:386/:448/:530); Decimator `_setFuturePrizePool:414`; GameOver(:145/:146=0); Afking `_routeAfkingPoolEth:1423`; Degenerette `_setFuturePrizePool` |
| **3** | 0 | rngWordCurrent | uint256 | Advance only (`_applyDailyRng`/`_unlockRng=0`/`requestLootboxRng`/`_finalizeRngRequest`/`_gameOverEntropy`/`rawFulfillRandomWords`) |
| **4** | 0 | vrfRequestId | uint256 | Advance only |
| **5** | 0 | totalFlipReversals | uint64 | **HUB `reverseFlip:1826` (masked RMW)** + Advance `_applyDailyRng:1921=0` |
| 5 | 8 | lastVrfProcessedTimestamp | uint48 | Advance `_applyDailyRng:1925`/`wireVrf:592` — **CO-RESIDENT with totalFlipReversals in slot 5** |
| **6** | 0 | dailyTicketBudgetsPacked | uint256 (packed counterStep\|units\|carryover) | Jackpot(:399/:615) |
| **7** | 0 | balancesPacked[addr] | mapping→uint256 [claimable low128\|afking high128] | **8+ modules** — HUB; Mint; Lootbox `_creditClaimable:936`; Jackpot `_creditClaimable:936`; Decimator/PayoutUtils `_creditBoxProceeds`/`_creditClaimable`; GameOver(deity `_creditClaimable:117`, sweep `_debitClaimable:214-216`); Afking(:353/:804/:811); Whale; Degenerette |
| **8** | 0 | traitBurnTicket[lvl][traitId] | mapping→address[][256] | Mint `_raritySymbolBatch:799/810` (keyed lvl+traitId) |
| **9** | 0 | mintPacked_[addr] | mapping→uint256 (multi-field packed) | **5 modules** — HUB(ctor SDGNRS/VAULT deity bit); Mint(`_recordMintData`/`_recordMintStreakForLevel`/`_clearCurse`/`_recordLootboxMintDay`); Whale(`_purchaseWhaleBundle:302`/`_activate10LevelPass:1346`/`_applyWhalePassStats:1425`/`_purchaseDeityPass:598`); Decimator `_applyWhalePassStats`; Afking(`_applyCurseStack`/`_clearCurse` CURSE_COUNT); Small/MintStreakUtils |
| **10** | 0 | rngWordByDay[day] | mapping→uint256 | Advance (`_applyDailyRng:1924`/`_backfillGapDays:1874`) keyed by day |
| **11** | 0 | prizePoolPendingPacked | uint256 [next128\|future128] | Advance `_setPendingPools`; Mint; Lootbox(:943); Afking `_routeAfkingPoolEth:1417`; Degenerette; Whale `_setPendingPools` |
| **12** | 0 | ticketQueue[wk] | mapping→address[] | HUB(`_queueTickets`); Advance; Mint; Lootbox `_queueTickets:629`; Decimator `_queueTicketRange`; Afking `_queueTicketsScaled:661`; Whale |
| **13** | 0 | ticketsOwedPacked[wk][buyer] | mapping→mapping→uint40 [owed32<<8\|rem8] | **6 modules** keyed by (level-derived wk, buyer) — HUB; Advance(:1564/:1570); Mint; Lootbox(:634); Decimator(`_queueTicketRange:726`); Afking(`_queueTicketsScaled:685`); Whale |
| **14** | 0/4 | ticketCursor / ticketLevel | uint32/uint24 | Advance + Mint (batch processors) |
| **15** | 0 | lootboxEth[index][buyer] | mapping→mapping→uint256 [amount128\|adj64\|score16\|distress48] | Mint `_purchaseForWithCached:1801`; Lootbox `_openLootBoxLegWith:579=0`; Afking `_recordAfkingCoverBox:1035`; Whale `_recordLootboxEntry:927` — keyed (index, buyer) |
| **16** | 0 | presaleBoxEthSold | uint96 | Mint `_buyPresaleBoxFor:1967` |
| **17** | 0 | presaleBoxCredit[buyer] | mapping→uint256 | Mint(+= :1809 / -= :1931); Afking `_settlePendingFlip:1104` |
| **18** | 0 | presaleBoxEth[index][buyer] | mapping→mapping→uint256 [closing255\|sold96\|applied96] | Mint `_buyPresaleBoxFor:1960`; Lootbox(:632/:707=0) keyed (index,buyer) |
| **19** | 0 | presaleStatePacked | uint256 [active8\|mintEth128] | Mint `_purchaseForWithCached:1623`; Advance `_psWrite:528` |
| **20** | 0 | gameOverStatePacked | uint256 [GO_TIME 0:47\|GO_JACKPOT_PAID 48:55\|GO_SWEPT 56:63] | **GameOver ONLY** — `handleGameOverDrain:136/144`, `handleFinalSweep:209` (3 offsets, same slot) |
| **21** | 0 | whalePassClaims[player] | mapping→uint256 | Lootbox `_activateWhalePass:1489`; Whale; Decimator/PayoutUtils `_queueWhalePassClaimCore` |
| 22 | 0 | wwxrpJackpotWhalePassBracketAwarded | mapping→bool | Jackpot |
| **23** | 0 | operatorApprovals | mapping→mapping→bool | HUB `setOperatorApproval:488` |
| **24** | 0 | levelPrizePool[lvl] | mapping→uint256 | Advance(:517 / `_endPhase:709`) keyed by lvl |
| 25 | 0 | affiliateDgnrsClaimedBy | mapping→mapping→bool | Bingo (claimAffiliateDgnrs) |
| **26** | 0 | levelDgnrsPacked[lvl] | mapping→uint256 [alloc128\|claimed128] | Advance `_setLevelDgnrsAllocation:762` (alloc half); Small `_addLevelDgnrsClaimed:1179` (claimed half) — keyed by lvl |
| 27 | 0 | deityPassPricePaid[addr] | mapping→uint96 | Whale `_purchaseDeityPass` |
| 28 | 0 | deityPassOwners | address[] | Whale (push) — read by GameOver deity-refund loop |
| 29 | 0 | deityBySymbol | mapping→address | Whale |
| 30 | 0 | presaleBoxDgnrsPoolStart | uint256 | Lootbox `_presaleBoxDgnrsReward:826` (snapshot latch) |
| **31** | 0 | vrfCoordinator | contract | Advance `_setVrfConfig` (admin/VRF-swap) |
| **32** | 0 | vrfKeyHash | bytes32 | Advance `_setVrfConfig` |
| **33** | 0 | vrfSubscriptionId | uint256 | Advance `_setVrfConfig` |
| **34** | 0 | lootboxRngPacked | uint256 [LR_INDEX\|LR_PENDING_ETH\|LR_THRESHOLD\|LR_PENDING_FLIP\|LR_MID_DAY] | **5 modules, field-masked RMW** — HUB `setLootboxRngThreshold:538`(THRESHOLD); Advance(:242/`_lrAdvanceIndexClearPending:1666`/`requestLootboxRng:1132`); Mint(:1611 PENDING_ETH); Afking `_recordAfkingCoverBox:1041`(PENDING_ETH); Whale `_recordLootboxEntry:916`(PENDING_ETH); Degenerette `_collectBetFunds:609/:614`(pendingEth/pendingFlip) |
| **35** | 0 | lootboxRngWordByIndex[index] | mapping→uint256 | Advance(:289/`_finalizeLootboxRng:1284`/`_backfillOrphanedLootboxIndices:1901`/`rawFulfillRandomWords:1844`) keyed by index |
| **36** | 0 | deityBoonPacked[deity] | mapping→uint32 [day0:24\|usedSlot24:32] | Lootbox `issueDeityBoon:1151` keyed by DAY |
| 37 | 0 | deityBoonRecipientDay[recipient] | mapping→uint24 | Lootbox `issueDeityBoon:1154` |
| 38 | 0 | degeneretteBets | mapping→mapping→uint256 | Degenerette `_placeDegeneretteBetCore` |
| 39 | 0 | degeneretteBetNonce | mapping→uint64 | Degenerette |
| **40** | 0 | lootboxEvCapPacked[player] | mapping→uint256 [two 88-bit windows {used64+level24}] | **Mint(:1774/:1795 level+1); Lootbox `_applyEvMultiplierWithCap:503`(currentLevel); Afking(:998/:1024 level+1); Whale(:879/:903)** — keyed by LEVEL; buy(level+1) vs open(currentLevel) alias the same slot |
| **41** | 0 | decBurn[lvl][player] | mapping→mapping→DecEntry [burn192\|bucket8\|subBucket8\|claimed8] | Decimator `recordDecBurn`(:159/:160/:167/:168/:169/:190), `_claimDecimatorJackpotFor:399`(claimed) keyed (lvl,player) |
| 42 | 0 | decBucketBurnTotal[lvl][denom][sub] | mapping→uint256[13][13] | Decimator `_decUpdateSubbucket:601`/`_decRemoveSubbucket:619` keyed (lvl,denom,sub) |
| **43** | 0 | decClaimRounds[lvl] | mapping→DecClaimRound [poolWei96\|totalBurn128\|rngWord32] | Decimator `runDecimatorJackpot:273-277` keyed by lvl |
| **44** | 0 | decBucketOffsetPacked[lvl] | mapping→uint64 (4 bits/denom) | **DEC-ALIAS PAIR** — Decimator `runDecimatorJackpot:269`(key=lvl) vs `runTerminalDecimatorJackpot:1024`(key=**lvl+1**); the +1 is the deliberate isolation |
| 45 | 0 | dailyHeroWagers[day] | mapping→uint256[4] | Degenerette `_placeDegeneretteBetCore:581` (8× uint32 saturating, keyed day+heroQuadrant); read by daily-hero-reward on spine |
| 46 | 0 | yieldAccumulator | uint256 | Advance `_consolidate:1000`; GameOver(:148=0) |
| **47** | 0 | centuryBonusUsed[player] | mapping→uint256 [level<<224\|used] | Mint `_setCenturyUsedFor:1722`; Afking `_deliverAfkingBuy:842` keyed by x00 level |
| **48** | 0 | terminalDecEntries[player] | mapping→TerminalDecEntry [totalBurn80\|weightedBurn88\|bucket8\|subBucket8\|burnLevel48\|boosted] | Decimator `recordTerminalDecBurn`(:808/:824/:825/:841/:851), `boostTerminalDecimator`(:931/:932), `_consumeTerminalDecClaim:1113` keyed by player |
| 49 | 0 | terminalDecBucketBurnTotal[hash] | mapping→uint256 | Decimator(:855 +=; boost re-key :942-:945) keyed keccak(lvl,denom,sub) |
| **50** | 0 | lastTerminalDecClaimRound | TerminalDecClaimRound [lvl24\|poolWei96\|totalBurn128] | Decimator `runTerminalDecimatorJackpot:1027-1029` |
| **51** | 0 | boonPacked[player] | mapping→{slot0,slot1} | **Boon(small)/Lootbox/Mint/Whale, field-shift RMW** — Lootbox `_applyBoon`(slot0 :1732/:1756/:1785/:1811/:1836; slot1 :1867/:1890/:1932); Mint `consumePurchaseBoost`(slot0)/`_applyLootboxBoostOnPurchase`(slot0); Whale(`_applyLootboxBoostOnPurchase`/`_purchaseWhaleBundle:233`/`_purchaseLazyPass`/`_purchaseDeityPass:581`); Small(`consumeCoinflipBoon`/`consumePurchaseBoost`/`consumeDecimatorBoost`/`checkAndClearExpiredBoon`/`consumeActivityBoon`) keyed by FIELD-SHIFT+day |
| 52 | 0 | bingoClaimed | mapping→mapping→uint8 | Bingo |
| **53** | 0 | bingoFirsts[level] | mapping→uint64 [quadrant 32:36\|symbol 0:32] | Small/Bingo `claimBingo:167/175` keyed by level |
| **54** | 0 | _subOf[player] | mapping→Sub (13 packed fields, 1 slot) | Afking — see Sub-field table below |
| 55 | 0 | _fundingSourceOf[player] | mapping→address | Afking `subscribe:439/442` |
| 56 | 0 | _subscribers | address[] | Afking (push/swap-pop) |
| 57 | 0 | _subscriberIndex[player] | mapping→uint256 | Afking |
| 58 | 0/2/4/7/13/19 | _subCursor/_subOpenCursor/_afkingResetDay/boxCursor/boxCursorIndex/presaleCloseIndex | uint16/uint16/uint24/uint48/uint48/uint48 | Afking (cursors); Lootbox `openHumanBoxes:722/723`(boxCursorIndex/boxCursor); Mint `_buyPresaleBoxFor:1975`(presaleCloseIndex); Advance(`_afkingResetDay:324`) — **6 fields packed in slot 58** |
| 59 | 0 | boxPlayers[index] | mapping→address[] | Mint(:1600); Lootbox; Afking `_recordAfkingCoverBox:1004`; Whale `_recordLootboxEntry:888` |

### Sub struct (slot 54, `_subOf[player]` — all 13 fields packed in ONE word; Afking writes)

`dailyQuantity(0)`, `validThroughLevel(1)`, `reinvestPct(4)`, `flags(5)`, `score(6)`,
`amount(8)`, `lastAutoBoughtDay(11)`, `lastOpenedDay(14)`, `afkCoveredThroughDay(17)`,
`afkingStartDay(20)`, `affiliateBase(23)`, `pendingFlip(27)`, `subStreakLatch(31)`.
**Marker sub-slot** (`lastAutoBoughtDay`/`lastOpenedDay`/`afkCoveredThroughDay`/`afkingStartDay`,
all uint24) written by THREE legs keyed by processDay/stampDay (`subscribe`,`_deliverAfkingBuy`,
`_openAfkingBox`). **Accumulator sub-slot** (`affiliateBase`/`pendingFlip`/`subStreakLatch`)
cross-written by `_deliverAfkingBuy` and independently zeroed by `drainAffiliateBase:1718` /
`_settlePendingFlip:1099`. Prime CORRUPT-01 ordering/aliasing target.

## CORRUPT-01 / DELEGATE-01 flag summary (the multi-module packed-slot surface)

1. **slot 1** `currentPrizePool|claimablePool` — both halves written within single Jackpot/Advance/GameOver calls; raw-slot write must preserve both.
2. **slot 5** `totalFlipReversals|lastVrfProcessedTimestamp` — HUB `reverseFlip` masked RMW shares the slot with the VRF-stall clock `livenessTriggered()` reads. A dropped mask corrupts stall detection. (MIDRNG/VRFSWAP-relevant.)
3. **slot 7** `balancesPacked[addr]` claimable128|afking128 — 8+ modules; the solvency invariant `balance+steth >= claimablePool` rides on consistent half-writes.
4. **slot 0** packs `level` + ~13 advance flags + 4 module-owned bools (`presaleOver` Mint, `presaleDrained` Lootbox, `ticketRedemptionOpen` Mint+Advance, `gameOver` GameOver) — cross-module RMW of the same word.
5. **slot 34** `lootboxRngPacked` — 5 modules field-mask RMW (HUB/Advance/Mint/Afking/Whale/Degenerette); MIDRNG-relevant (LR_INDEX/LR_MID_DAY).
6. **slot 40** `lootboxEvCapPacked[player]` — buy(level+1) vs open(currentLevel) alias the same two-window slot across Mint/Lootbox/Afking/Whale.
7. **slot 44** `decBucketOffsetPacked` — **DEC-ALIAS**: regular `[lvl]` vs terminal `[lvl+1]`; verify `lvl+1` can never collide with a future regular round's `[lvl+1]` write.
8. **slot 51** `boonPacked[player]` slot0/slot1 — field-shift masked clears by Boon/Lootbox/Mint/Whale; isolation is claimed but multi-module.
9. **slots 2/11** `prizePoolsPacked`/`prizePoolPendingPacked` next|future — `_setFuturePrizePool` RMWs `next`; written by Advance/Mint/Jackpot/Decimator/GameOver/Afking/Degenerette/Whale.
10. **slot 13** `ticketsOwedPacked[wk][buyer]` owed<<8|rem — 6 modules, key=(level-derived wk, buyer); key-derivation aliasing.
11. **slot 9** `mintPacked_[player]` — 5 modules write co-resident fields (LEVEL_COUNT/CURSE/streak/day/deity); field isolation is load-bearing.
12. **slot 20** `gameOverStatePacked` — single-owner (GameOver) but 3 offsets in one slot (GO_TIME/GO_JACKPOT_PAID/GO_SWEPT).
13. **slot 26** `levelDgnrsPacked[lvl]` alloc|claimed — Advance(alloc) vs Small(claimed) write different halves of the same keyed slot.

**Nested-delegatecall inventory for 419 DELEGATE-01** (Game→module→module; NO raw
`delegatecall(msg.data)` to attacker-chosen target anywhere):
- Advance→{Jackpot,Mint,Afking,GameOver} (10 nested DC sites; all bubble via `_revertDelegate`).
- Game→Advance self-CALL→Game stub→DC for runBaf/runDecimator/emitDailyWinningTraits/terminal* (re-enter pattern).
- Lootbox→{Boon (consumeActivityBoon/checkAndClearExpiredBoon), Degenerette (3 spin fns)}.
- Degenerette→Lootbox (`_resolveLootboxDirect` recirc — reaches **depth ≥3** via resolveEthSpinFromBox→resolveLootboxDirect).
- Afking→Lootbox (`resolveAfkingBox`).
- Mint→Boon (`consumePurchaseBoost`, **payable, msg.value in flight**).
- Decimator→Lootbox (`resolveLootboxDirect`).
- HUB→Boon raw `consumeCoinflipBoon:836` (single-depth `delegatecall(msg.data)`).
- **msg.value-in-flight DC stubs** (payable nested DC — the documented nested-delegatecall
  callvalue trap): `subscribe`, `resolveRedemptionLootbox`, `creditRedemptionDirect`,
  `resolveLootboxDirect`, `consumePurchaseBoost`, `consumeActivityBoon`,
  `checkAndClearExpiredBoon` — value guards must live in the module bodies.

---

# LOAD-BEARING HANDOFF (per downstream phase)

## 418 BRICK — permanent-revert / unbounded-loop / gas-ceiling

Examine the **29 spine + 14 non-spine PERMANENT-CANDIDATE** sites in COLMAP-02 (P1–P43), priority:
- **Spine wedge cluster**: the 7 onlySelf bubbled stubs (P1–P7) — cross-check the module bodies for any reachable state where they revert UNCONDITIONALLY.
- **Empty-return stubs** P8/P9 (`_runProcessTicketBatch:1553`, `_processFutureTicketBatch:1484`) — any MintModule return-shape change wedges; contrast `_handleGameOverPath:664` where the revert is deliberately SWALLOWED.
- **Arithmetic wedges on the transition leg**: P10 (div0 next==0 :846), P11 (skim underflow :899), P15 (payDailyJackpot budget underflow), P20 (sDGNRS `resolveRedemptionPeriod:756` — fires on EVERY advance with a stamped pool; verify telescoping-delta + gwei-snap reconciliation), P26 (afking STAGE fail-loud solvency).
- **External-callee bubbles on the seal/transition**: P12 (`steth.balanceOf` in `_unlockRng:1815`), P13 (`charityResolve.pickCharity:1745`), P23 (FLIP/WWXRP overflow via `processCoinflipPayouts`), P25 (`QUESTS.finalizeAfking` on STAGE), P24 (STAGE ticket buy post-liveness), P27 (mintFlip CEI-last creditFlip).
- **Pre-RNG gate** P14 (`advanceGame:283 RngNotReady`) — confirm 12h/14d recovery paths reachable.
- **Unbounded loops** (BRICK-04): `_backfillOrphanedLootboxIndices:1894` (+ ≤120 gap backfill same tx), `runBafJackpot:1930` (cross-contract cap), `resolveRedemptionLootbox:951` (no budget cap), `handleGameOverDrain:106` deity loop, `processSubscriberStage`/`_autoOpen` budget bounds vs 16.7M.

## 419 DELEGATE — nested-delegatecall / raw-dispatch / layout-alignment

- Walk the **nested-DC inventory** in COLMAP-04. Confirm NO `delegatecall(msg.data)` reaches an attacker-chosen target/selector (current finding: NONE — all targets are fixed module constants).
- **Depth-≥3** path: Game→Lootbox→Degenerette `resolveEthSpinFromBox`→Lootbox `resolveLootboxDirect` recirc — verify `allowEthSpin=false` truly blocks a cascade and no `address(this)`/msg.sender assumption breaks at depth.
- **msg.value-in-flight** payable nested DCs (the 7 listed) — confirm value guards live in module bodies, not the stubs; a future ETH-moving op in `consumePurchaseBoost`/`consumeActivityBoon`/`checkAndClearExpiredBoon` would silently double-spend the in-flight value.
- **Layout alignment**: every module writes by NAMED field via BitPackingLib shifts; cross-check the shifts against the slot/offset table above (esp. multi-module slots 0/1/5/7/9/34/40/51).

## 420 CORRUPT — packed-write / write-ordering / reentrancy

- The **13 CORRUPT-01 flagged slots** above. Top: slot 5 (`reverseFlip` mask vs `lastVrfProcessedTimestamp`), slot 7 (`balancesPacked` half-write solvency), slot 40 (`lootboxEvCapPacked` buy/open level aliasing), slot 51 (`boonPacked` field-shift), slot 44 (DEC-ALIAS), slot 54 (Sub marker/accumulator sub-slots written by 3 legs).
- **Write-ordering**: Mint `mintPacked_` 4-helper sequence within one purchase (`_recordMintData` before `_recordMintStreakForLevel`/`_clearCurse`/`_recordLootboxMintDay`) — ordering load-bearing for the cached-score read at Mint:1710. Degenerette pool read-once-flush-once vs box-ETH-spin flush-BEFORE-recirc (:1441).
- **Reentrancy** (LOW per threat model but confirmatory): `claimWinnings` runs payout (CEI) THEN `maybeCurse` DC — `maybeCurse` has no revert site (confirmed). subscribe→`AFFILIATE.claim` reentrant callback. The yield-surplus/stETH-first CEI ordering (prior council HIGH) — re-confirm `_payoutWithStethFallback` leaves no in-flight stETH a reentrant advance counts as backing.

## 421 MIDRNG — mid-day RNG swap / retry / partial-drain

- `requestLootboxRng:1792`/`retryLootboxRng:1804` (Advance bodies) + `rawFulfillRandomWords:1856` daily-vs-mid-day split by `rngLockedFlag`.
- **Frozen-word binding**: box seeds bind to `lootboxRngWordByIndex[index]` (no live day in seed for direct/redemption/afking); `issueDeityBoon`/`_rollLootboxBoons` read a live day for EXPIRY only, not the outcome roll. Degenerette placement requires `lootboxRngWordByIndex[index]==0`, resolution requires `!=0` — verify the index can't be advanced/replaced mid-flight to re-pick a winning word.
- **Orphan-index coupling**: `openHumanBoxes:682 word!=0` break prevents marooning if a coordinator rotation orphans an index word; `_backfillOrphanedLootboxIndices` backfills below LR_INDEX.
- **Partial-drain decouples**: `STAGE_GAP_BACKFILLED`, `STAGE_SUBS_BACKFILL_DEFERRED`, ticket-cursor resumability — verify per-tx-ceiling decouples hold under VRF-stall sequencing. `advanceGame` L185-187 clamps a new wall-day to dailyIdx+1 when that day's word is recorded-but-unsealed (RNG-reuse guard).

## 422 GAMEOVER — terminal-branch finalization

- `_handleGameOverPath` (Advance :605) → GameOver `handleGameOverDrain:73` / `handleFinalSweep:203`.
- **All-or-nothing**: `gameOver=true` latched at `:135` BEFORE the un-try/catch external burns (P17 :139-142), nested terminal jackpot/decimator (P18 :177/:191), and the RNG-word gate (P16 :94) — any revert rolls back the whole finalization including the latch.
- **Final-sweep hard-revert** P19 (`_sendStethFirst:253/257/261`) — a sink (VAULT/SDGNRS/GNRUS) rejecting stETH/ETH wedges the sweep; GO_SWEPT written before transfers but rolls back on revert (retries cleanly). Confirm sinks always accept.
- **gameOver callee invariants** P21/P22 (sDGNRS `burnAtGameOver:614` / FLIP `tombstoneAtGameOver:563` checked over/underflow).
- **Liveness bailout**: `_livenessTriggered()` fires after 14d with `rngRequestTime!=0`, GATED OFF while `lastPurchaseDay||jackpotPhaseFlag` (the Storage:1437-1446 deadlock-window comment) — confirm `_handleGameOverPath` unreachable in that window.
- **Stranded-funds checks** (P34/P35): post-liveness `_queueTickets`/`resolveBets` revert permanently — verify the gameOver drain actually settles every pending degenerette bet + lootbox/redemption claim into claimable (GAMEOVER-01 lazy afking merge depends on the final sweep zeroing claimablePool with no underflow).

## 423 VRFSWAP — coordinator-rotation

- `updateVrfCoordinatorAndSub:1776` (HUB stub) → Advance `:1755` — re-issues in-flight requests, intentionally preserves `totalFlipReversals` (nudges carry to first post-swap word, :1786-1789), routes by LR_MID_DAY / rngLockedFlag / rngWordCurrent. If the module body reverts under a needed rotation during rngLock, recovery is blocked below the grace threshold.
- `rawFulfillRandomWords` rejects stale requestIds (:1833, silent return — no revert), splits daily/mid-day by rngLockedFlag. `_gameOverEntropy` fallback (:1337) pre-subtracts `totalFlipReversals` to cancel a committer-steerable nudge since the VRF-dead fallback never set rngLockedFlag.
- **slot 5 co-residence** (`totalFlipReversals`/`lastVrfProcessedTimestamp`) is the corruption surface that crosses MIDRNG/VRFSWAP/CORRUPT — `reverseFlip:1826` masked RMW.
- VRF state slots 31/32/33 (`vrfCoordinator`/`vrfKeyHash`/`vrfSubscriptionId`) + 4 (`vrfRequestId`) are Advance-only writers; confirm rotation atomicity vs an in-flight `vrfRequestId`.

---

## OPEN QUESTIONS (slice-flagged ambiguities for the hunt to resolve)

1. **sDGNRS `resolveRedemptionPeriod:756` uint96 underflow (P20)** — does the telescoping-delta submit math (callees:1108) + gwei-snap (1083/1106) + INV-13 single-pool guarantee the cumulative scalar never drifts below the day's reconstructed `segregatedMax`? If it can, advance wedges forever on a stamped day. (callees slice #1 brick candidate.)
2. **DEC-ALIAS (slot 44):** can terminal `decBucketOffsetPacked[lvl+1]` ever collide with a FUTURE regular round's `[lvl+1]` write? Comment argues the regular round at `lvl+1` can only resolve once level reaches `lvl+1`, precluded by this gameover — verify no regular round resolves post-gameover.
3. **Afking STAGE ticket buy (P24):** does `advanceGame`'s own liveness/gameover branch short-circuit `processSubscriberStage` BEFORE a ticket-mode sub can reach `_queueTicketsScaled:650` post-liveness? The STAGE buy is NOT `_livenessTriggered`-gated (only the open leg is).
4. **mintFlip CEI-last `creditFlip` (P27)** + **subscribe-affiliate `creditFlip`**: is `COINFLIP.creditFlip` total for ANY `msg.sender` (pure ledger add, recordAmount=0)? If not, a blocked caller does the advance work then loses it every crank.
5. **Degenerette stranded funds (P35):** does the gameOver drain settle every pending degenerette bet into claimable, given `resolveBets:435` reverts permanently post-liveness?
6. **Liveness deadlock window:** is `_handleGameOverPath` truly unreachable while `lastPurchaseDay||jackpotPhaseFlag` (the Storage:1437-1446 target-met→phase-close multi-call window)?
7. **deityPassOwners growth (GameOver :106 loop):** is `deityPassOwners.length` hard-bounded (≤ ~32 symbols, 1/symbol) so the in-column deity-refund loop cannot OOG `handleGameOverDrain`?
8. **runBafJackpot:1930 winner cap:** is the winner-count ceiling enforced inside DegenerusJackpots provably ≤ the per-tx gas budget for the advance BAF leg?
9. **resolveEthSpinFromBox depth-≥3 recirc:** does `allowEthSpin=false` on the recirc truly block a cascade, and do all `address(this)`/msg.value assumptions hold at delegatecall depth ≥3?
