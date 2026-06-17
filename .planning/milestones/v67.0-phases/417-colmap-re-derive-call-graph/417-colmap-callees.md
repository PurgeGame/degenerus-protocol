# Slice 417 — Synchronous Callees (Coinflip / Vault / FLIP / sDGNRS / Affiliate)

Subject tree: frozen `contracts/` @ `0dd445a6`. Read-only map.

Scope: ONLY the entrypoints the GAME column (mintFlip / advanceGame spine + the player/purchase/redemption flows that the spine and its callees reach) synchronously calls into the five callee contracts. A revert inside any of these BRICKS the calling column tx — that is the highest-value output here. "GAME column" = either `msg.sender == ContractAddresses.GAME` (a GAME delegatecall module pays AS the GAME), or a callee that is itself invoked by the GAME and re-enters a second callee in the same tx (e.g. Coinflip.processCoinflipPayouts → Jackpots/WWXRP; sDGNRS.claimRedemption → GAME callbacks).

Note on caller↔callee direction: the GAME modules execute via DELEGATECALL in the GAME's storage; a "module → callee" call is a real CALL out of the GAME to a SEPARATE deployed contract (Coinflip/Vault/FLIP/sDGNRS/Affiliate). These callees do NOT delegatecall back — they are normal contracts with their own storage. So none of the writes below are GAME-storage writes (that is the modules' slice). The DELEGATECALL STORAGE-WRITE INVENTORY section is therefore empty for this slice; the relevant write inventory for these contracts is each callee's OWN storage, summarized for aliasing context.

---

## 0. Column → callee entrypoint INDEX (which spine/flow reaches each)

| Callee.fn | Reached from (GAME column site) | Sync? on advance spine? |
|---|---|---|
| Coinflip.processCoinflipPayouts | AdvanceModule:1234,1306,1341,1877 | YES — every advance day-resolve + gap backfill |
| Coinflip.creditFlip | Advance:984; Decimator:365; Bingo:196,259; Lootbox:779,1374; Mint:1147,1316; Afking:1615; Game:1379; Jackpot(batch) | partial (advance:984 yes; rest player/jackpot flows) |
| Coinflip.creditFlipBatch | Jackpot:1678,1752 | YES — BAF jackpot resolution (advance-triggered) |
| Coinflip.consumeCoinflipBoon (via game.consumeCoinflipBoon — GAME-resident; NOT a callee here) | — | — |
| Coinflip.redeemableFlipBacking | sDGNRS._submitGamblingClaimFrom:1077 (callee→callee, NOT spine) | no |
| Coinflip.withdrawRedeemedFlip | sDGNRS._submitGamblingClaimFrom:1124 | no |
| Coinflip.getCoinflipDayResult | sDGNRS._claimRedemptionFor:888 | no |
| Coinflip.previewClaimCoinflips / coinflipAutoRebuyInfo | sDGNRS views/burn (1000,1001,985,986); FLIP.balanceOfWithClaimable; Vault reserves views | view |
| Coinflip.consumeFlipForSalvage | FLIP.burnCoinForSalvage:619 (← Mint:1315 salvage) | no |
| Coinflip.claimCoinflipsFromFlip | FLIP._transfer:389 (shortfall top-up) | no |
| Coinflip.consumeCoinflipsForBurn | FLIP._consumeCoinflipShortfall:493 | no |
| FLIP.mintForGame | Coinflip (claim/rebuy paths); Degenerette:447,1387 | partial |
| FLIP.burnForCoinflip | Coinflip._depositCoinflip:292; Coinflip.withdrawRedeemedFlip:1035 | no |
| FLIP.burnCoin | Game:1821; Degenerette:613; Afking:1779,1803; Mint:2193 | no |
| FLIP.burnCoinForSalvage | Mint:1315 | no |
| FLIP.vaultEscrow / vaultMintTo / tombstoneAtGameOver | GAME flows / GameOverModule:142 (tombstone YES on gameOver) | tombstone YES |
| sDGNRS.processCoinflip… N/A | — | — |
| sDGNRS.pendingResolveDay (view) | Advance:1253,1315,1350 | YES — every advance |
| sDGNRS.resolveRedemptionPeriod | Advance:1258,1320,1355 | YES — every advance with a stamped pool |
| sDGNRS.hasPendingRedemptions (view) | advance/derive | YES |
| sDGNRS.transferFromPool | Bingo:189,240; Degenerette:1229; Advance:748; Lootbox:798,834,2273; Whale:721-833; Game:471 | partial (advance:748 yes) |
| sDGNRS.transferBetweenPools | (rebalance flows) | — |
| sDGNRS.burnAtGameOver | GameOverModule:140 | YES on gameOver |
| sDGNRS.depositSteth | Game:1877 | no |
| sDGNRS.claimRedemption / claimRedemptionMany | player/keeper (callee→GAME callbacks) | no (NOT spine) |
| Affiliate.payAffiliate | Mint:1736,1746,2126-2169 | no (purchase flow) |
| Affiliate.claim | permissionless afking-affiliate settle (→ GAME.drainAffiliateBase) | no |
| Vault.* | NONE called by the GAME column. Vault is a CALLER of the GAME (gamePurchase/gameAdvance/etc.), not a callee. Its receive()/recoverAfkingFunding are reached only when the GAME pushes ETH back to it (claimWinnings → .call). | see §Vault |

---

## 1. CALL GRAPH (column-reachable callee fns → internal calls; sync external CALLs)

### Coinflip.sol

- **processCoinflipPayouts(bonus,rngWord,epoch)** `onlyDegenerusGameContract` (853)
  - internal: `_storeDayResult` (889, write), `_addDailyFlip` (905, on bounty win), `_claimCoinflipsInternal` (942 armed-sDGNRS), `_claimCoinflipsAmount` (944 seed-window sDGNRS), `_emitClaimState` (960)
  - external CALLs OUT:
    - `game.payCoinflipBountyDgnrs(to, slice, currentBounty_)` (907) — GAME callback (sDGNRS pool transfer of bounty in DGNRS)
    - via `_addDailyFlip`→`game.consumeCoinflipBoon` only when `recordAmount!=0`; here recordAmount=0 so NOT reached
    - via `_claimCoinflipsInternal` (for sDGNRS): `jackpots.getLastBafResolvedDay` (548) — but the BAF block is **skipped for sDGNRS** (591 guard `player != SDGNRS`), so `jackpots.recordBafFlip` and the `game.purchaseInfo` RngLocked guard are NOT reached on the sDGNRS auto-claim; `wwxrp.mintPrize` (638) IS reachable if sDGNRS books a loss; `flip.mintForGame` reachable via `_claimCoinflipsAmount` seed-window branch (447)
  - **This is THE coinflip leg of the advance spine.** A revert here wedges advanceGame.

- **_claimCoinflipsInternal(player,deep)** internal (455)
  - external: `jackpots.getLastBafResolvedDay` (548); `game.purchaseInfo` (598, only if winningBafCredit!=0 AND player!=SDGNRS); `jackpots.recordBafFlip` (624); `wwxrp.mintPrize` (638, if lossCount!=0)
- **_claimCoinflipsAmount(player,amount,mint)** private (423) → `_claimCoinflipsInternal`; `flip.mintForGame` (447, if mint && toClaim!=0); `_emitClaimState`
- **_addDailyFlip** private (649) → `game.consumeCoinflipBoon` (660, only recordAmount!=0); `game.rngLocked` (686); `_flipStake/_setFlipStake/_updateTopDayBettor`
- **creditFlip(player,amount)** `onlyFlipCreditors` (970) → `_addDailyFlip(...,recordAmount=0,...)` → NO external boon/rng calls (both gated on recordAmount!=0). Pure ledger add.
- **creditFlipBatch(players[],amounts[])** `onlyFlipCreditors` (981) → loop `_addDailyFlip` (recordAmount=0)
- **redeemableFlipBacking()** sDGNRS-only (1005) → `_claimCoinflipsInternal` (settles), `_emitClaimState`
- **withdrawRedeemedFlip(base)** sDGNRS-only (1025) → `flip.balanceOf` (1032), `flip.burnForCoinflip` (1035), `_claimCoinflipsAmount` (1042), `_emitClaimState`
- **consumeFlipForSalvage(player,amount)** `onlyFLIP` (394) → `_claimCoinflipsAmount(mint=false)` then carry decrement
- **claimCoinflipsFromFlip / consumeCoinflipsForBurn** `onlyFLIP` (356,377) → `_claimCoinflipsAmount`
- **getCoinflipDayResult(day)** view (367) → `_dayResult`

### FLIP.sol

- **mintForGame(to,amount)** COINFLIP|GAME (475) → `_mint` (zero-addr revert; uint128 cap)
- **burnForCoinflip(from,amount)** COINFLIP (466) → `_burn`
- **burnCoin(target,amount)** `onlyGame` (593) → `_consumeCoinflipShortfall` (594; → `coinflip.consumeCoinflipsForBurn` 493, reverts Insufficient under rngLock if balance short), `_burn` (595)
- **burnCoinForSalvage(target,amount)** `onlyGame` (609) → `_burn` (615), `game.rngLocked` (618), `coinflip.consumeFlipForSalvage` (619)
- **vaultEscrow(amount)** GAME|VAULT (541) → `_toUint128` add
- **tombstoneAtGameOver()** `onlyGame` (559) → `_toUint128` add (one-shot latch)
- **vaultMintTo(to,amount)** `onlyVault` (573) — VAULT-only, not GAME column
- **_transfer** (384) → `game.rngLocked` (387), `coinflip.claimCoinflipsFromFlip` (389)
- **balanceOfWithClaimable / balanceOfSpendableForSalvage** views (244,267) → `coinflip.previewClaimCoinflips` / `previewSalvageFlipBacking`

### sDGNRS.sol

- **resolveRedemptionPeriod(roll,dayToResolve)** GAME-only (742) — pure storage: lowers `_pendingRedemptionEthValue`, writes `redemptionPeriods`, deletes `pendingByDay`, clears `_pendingResolveDay`. NO external CALL out. **Advance-spine leg.**
- **pendingResolveDay() / hasPendingRedemptions()** views (538,728)
- **transferFromPool(pool,to,amount)** GAME-only (559) — pure storage; NO external CALL
- **transferBetweenPools** GAME-only (590) — pure storage
- **burnAtGameOver()** GAME-only (609) — pure storage (`delete poolBalances`)
- **depositSteth(amount)** GAME-only (508) → `steth.transferFrom` (509)
- **claimRedemption(player,day)** permissionless (782) → `game.gameOver` (786); `_claimRedemptionFor` →
  - `coinflip.getCoinflipDayResult(day+1)` (888); `coinflip.creditFlip(player, flipPaid)` (893)
  - GAME callbacks: `game.rngWordForDay(day+1)` (916); `game.resolveRedemptionLootbox{value}` (920); `game.creditRedemptionDirect{value}` (928,938); `_payEth` (902, post-gameOver, untrusted `.call`)
- **claimRedemptionMany(players[],day)** permissionless (798) → loop `_claimRedemptionFor`; `game.mintPrice` (823); `coinflip.creditFlip` (821)
- **_submitGamblingClaimFrom** private (1021) → `game.rngWordForDay` (1036); `steth.balanceOf` (1066); `_claimableWinnings`→`game.claimableWinningsOf` (1176); `coinflip.redeemableFlipBacking` (1077); `game.pullRedemptionReserve` (1110); `coinflip.withdrawRedeemedFlip` (1124); `game.playerActivityScore` (1141)
- **burn / burnWrapped** public (633,653) → `game.gameOver/livenessTriggered/rngLocked`; `_deterministicBurnFrom` (→ `game.claimWinnings` 695, `steth.transfer`, `.call`) OR `_submitGamblingClaim`

### Affiliate.sol

- **payAffiliate(amount,code,sender,lvl,isFreshEth,actScore)** GAME-only (406) → `quests.handleAffiliate` (571); `coinflip.creditFlip` (554,572); internal resolve/leaderboard writes
- **claim(subs[])** permissionless (598) → `afkingDrain.drainAffiliateBase` (624, GAME callback, AFFILIATE-gated read-and-zero); `afkingDrain.level` (654); `coinflip.creditFlip` (643,644,667,668,669)

### Vault.sol

- NO Vault function is on the GAME column. Vault is a CALLER into the GAME, not a GAME callee. The only GAME→Vault entry is value transfer: the GAME pushing ETH to the vault hits `receive()` (480) which only `emit Deposit`. `recoverAfkingFunding` (490) is permissionless but re-enters the GAME (`withdrawAfkingFunding`). Included only for completeness; no revert here can bubble into the advance spine because the GAME never synchronously CALLs a Vault function during advance.

---

## 2. REVERT-SITE INVENTORY (column-reachable callee reverts)

T = TRANSIENT (caller/another actor can still progress). P = PERMANENT-CANDIDATE (could wedge advanceGame or gameOver finalization).

### Coinflip

| fn:line | trigger | error | T/P |
|---|---|---|---|
| processCoinflipPayouts:857 | caller != GAME | OnlyDegenerusGame | T (only GAME calls it; never trips on spine) |
| _claimCoinflipsInternal:615 | sDGNRS path is SKIPPED (591 guard) so this RngLocked **cannot fire for the spine's sDGNRS auto-claim**; fires only for a non-sDGNRS winning-BAF claim during a locked x10 jackpot window | RngLocked | T (player claim; not on advance spine) |
| _claimCoinflipsInternal:638 | wwxrp.mintPrize bubble (see WWXRP) | (callee) | P-candidate (sDGNRS loss on advance auto-claim mints WWXRP — a WWXRP revert here bubbles into processCoinflipPayouts → advance) |
| _claimCoinflipsInternal:624 | jackpots.recordBafFlip bubble | (callee) | T (skipped for sDGNRS; non-spine) |
| _claimCoinflipsAmount:447 / various | flip.mintForGame bubble (uint128 cap / zero-addr) | (callee) | P-candidate (seed-window sDGNRS auto-claim at 944 mints — see FLIP._mint) |
| _addDailyFlip:660/686 | game.consumeCoinflipBoon / game.rngLocked bubble | (callee) | T (recordAmount=0 on all spine creditFlip; boon path unreached) |
| creditFlip:973 / creditFlipBatch:984 | caller not in {GAME,QUESTS,AFFILIATE,ADMIN,SDGNRS} | OnlyFlipCreditors | T (authorized callers only) |
| creditFlipBatch (implicit) | array OOB if players.len != amounts.len | (index/panic) | P-candidate — Jackpot batch (1678,1752) builds both arrays itself so equal length by construction; flagged for verification |
| _addDailyFlip arithmetic | `biggestFlipEver = uint128(recordAmount)` etc. | (checked) | T |
| withdrawRedeemedFlip:1050 | remainder > carry after held+claimable drain | Insufficient | P-candidate — fires inside sDGNRS submit, NOT the advance spine; but a revert wedges that player's redemption submit only (T for advance). Comment asserts unreachable (sized from same backing). |
| withdrawRedeemedFlip:1006 / redeemableFlipBacking:1006 / consumeFlipForSalvage / claimCoinflipsFromFlip / consumeCoinflipsForBurn | wrong caller | OnlysDGNRS / OnlyFLIP | T |
| _setCoinflipAutoRebuy:752 etc. | rngLocked | RngLocked | T (player config; not spine) |

### FLIP

| fn:line | trigger | error | T/P |
|---|---|---|---|
| _mint:418 / _toUint128:372 | to==0 / value > uint128.max | ZeroAddress / SupplyOverflow | P-candidate — mintForGame is called on the advance spine (Coinflip seed-window sDGNRS claim 447→mintForGame; Degenerette). A uint128 supply overflow would brick. Bounded: supply ceiling far under uint128; tombstone +1e36 keeps ~340x headroom. |
| _burn:442 | VAULT burn > vaultAllowance | Insufficient | P-candidate — burnCoinForSalvage held leg uses vaultAllowance; salvage is NOT on advance spine (T for advance). |
| _burn:449 | balanceOf[from] < amount (underflow) | (checked) | T — burnCoin/burnForCoinflip on player action; shortfall first topped up from coinflip (skipped under rngLock → Insufficient) |
| _consumeCoinflipShortfall:491 | rngLocked AND balance short | Insufficient | T (player burn during lock) |
| _consumeCoinflipShortfall:498 | balance+consumed < amount | Insufficient | T |
| burnForCoinflip:467 / burnCoin:593 / vaultMintTo:573 / tombstoneAtGameOver:560 / vaultEscrow:546 | wrong caller | OnlyGame/OnlyVault | T |
| tombstoneAtGameOver:563 | `_toUint128(vaultAllowance + 1e36)` overflow | SupplyOverflow | P-candidate — called in GameOverModule:142 during gameOver finalization. Overflow would brick gameOver. Bounded ~340x headroom; latch no-ops re-entry. |
| burnCoinForSalvage:618,620 | rngLocked / remainder>consumed | Insufficient | T (salvage, not spine) |

### sDGNRS

| fn:line | trigger | error | T/P |
|---|---|---|---|
| resolveRedemptionPeriod:743 | caller != GAME | Unauthorized | T (only GAME) |
| resolveRedemptionPeriod:749 | ethBase == 0 | **early return, NOT revert** | — (defensive; advance passes a no-op) |
| resolveRedemptionPeriod:756 | `_pendingRedemptionEthValue - segregatedMax + rolledEth` underflow on the uint96 subtraction (checked) | (panic 0x11) | **P-candidate — HIGHEST VALUE.** Called on advance spine (Advance:1258/1320/1355). If the cumulative scalar and the per-day pool ever disagree (segregatedMax > stored), this underflows and **bricks every future advance** (the stamped day can never resolve → advanceGame wedged forever). Telescoping-delta accounting at submit (1108) is designed to make it reconcile exactly; depends on that invariant holding across gwei-snap truncation. |
| resolveRedemptionPeriod:756 | `uint96(...)` narrowing | (safe per comment) | T |
| transferFromPool:561 | to==0 | ZeroAddress | P-candidate — called on advance:748 and jackpot/whale/bingo flows. A zero `to` would brick that distribution; `to` is derived from winner addresses, in principle nonzero. Pool-empty path RETURNS 0 (no revert) — good. |
| transferFromPool:574 / :570 | `_totalSupply - amount` / `balanceOf[this] -= amount` underflow (self-win burn / pool debit) | (checked panic) | P-candidate — amount is clamped to `available = poolBalances[idx]` (565) so `balanceOf[this]` underflow needs balance < pooled (an internal-accounting break). Flagged: pool↔balance invariant is load-bearing for advance distributions. |
| transferBetweenPools:602 | `poolBalances[toIdx] + amount` (uint128 checked add inside `uint128(...)`) | (checked) | T (rebalance; bounded by supply) |
| burnAtGameOver:609 | wrong caller | Unauthorized | T |
| burnAtGameOver:614 | `_totalSupply - bal` underflow | (checked) | P-candidate — gameOver finalization (GameOverModule:140). bal is this contract's own balance ≤ supply; underflow would brick gameOver. |
| depositSteth:509 | steth.transferFrom returns false | TransferFailed | P-candidate — Game:1877 stETH forward; live-game not advance. T for advance spine. |
| claimRedemption:784 | roll == 0 (period not resolved) | NotResolved | T (claim path; player retries after resolve) |
| claimRedemption:787 | gameOver && player != msg.sender | Unauthorized | T |
| claimRedemption:789 | _claimRedemptionFor returns false (empty slot) | NoClaim | T |
| _claimRedemptionFor:868 | `_pendingRedemptionEthValue - totalRolledEth` underflow (uint96) | (panic) | P-candidate — same cumulative-scalar invariant as resolve; here a break bricks that player's claim (T for advance, but a stuck claim leaves segregated ETH locked). |
| _claimRedemptionFor:893 | coinflip.creditFlip bubble | (callee — none) | T |
| _claimRedemptionFor (GAME callbacks 920/928/938) | resolveRedemptionLootbox / creditRedemptionDirect revert (GAME-resident, OUT of slice) | (GAME) | NOTE: these bubble into claimRedemption (player claim), NOT the advance spine. Mapped in modules slice. |
| _payEth:1158/1165/1168 | `.call`/steth.transfer fails | TransferFailed | T (gameOver self-claim; player-controlled recipient) |
| _submitGamblingClaimFrom:1023/1024/1036/1042/1050(via withdrawRedeemedFlip)/1057/1132 | various submit guards (Insufficient / BurnTooSmall / BurnsBlockedBeforeDailyRng / PriorDayUnresolved / ExceedsDailyRedemptionCap) | listed | T (player submit; never on advance spine) |
| _submitGamblingClaimFrom:1106 | `pool.ethBase += uint64(...)` / scalar add bubbles to game.pullRedemptionReserve | (callee) | T (submit) |
| _deterministicBurnFrom:679/705 | amount==0\|>bal / stethOut>stethBal | Insufficient | T (gameOver player burn) |

### Affiliate

| fn:line | trigger | error | T/P |
|---|---|---|---|
| payAffiliate:418 | caller != GAME | OnlyAuthorized | T |
| payAffiliate:571 | quests.handleAffiliate bubble | (callee) | T — purchase flow, not advance spine |
| payAffiliate:554/572 | coinflip.creditFlip bubble | (callee — creditFlip can only OnlyFlipCreditors-revert, AFFILIATE is authorized) | T |
| claim:621 | mixed-affiliate batch (`_referrerAddress(sub) != a`) | Insufficient | T (permissionless settle; caller controls batch) |
| claim:624 | afkingDrain.drainAffiliateBase bubble (GAME-resident) | (GAME) | T |
| claim arithmetic 649-651 | share split (no revert; floored) | — | — |

### WWXRP / Jackpots (reached transitively from Coinflip on the spine)

| fn:line | trigger | error | T/P |
|---|---|---|---|
| WWXRP.mintPrize:230 | caller not GAME/COINFLIP | OnlyMinter | T (Coinflip is authorized) |
| WWXRP._mint (ZeroAddress) | to==0 | ZeroAddress | P-candidate — Coinflip.mintPrize(player,...) on sDGNRS loss during advance auto-claim; player is sDGNRS (nonzero). Practically unreachable but on the spine. |
| Jackpots.recordBafFlip:191 | caller != COIN | (onlyCoin) | T — and SKIPPED for sDGNRS so not on the sDGNRS advance leg |

---

## 3. LOOP INVENTORY (column-reachable callee loops)

| fn:line | bound | per-iter touch | BOUNDED / UNBOUNDED |
|---|---|---|---|
| Coinflip._claimCoinflipsInternal:521 `while (remaining!=0 && cursor<=latest)` | `remaining` = `windowDays` (365 normal / 180 first) OR deep `min(latest-start, AUTO_REBUY_OFF_CLAIM_DAYS_MAX=1460)` | `_dayResult` SLOAD, `_flipStake`/`_setFlipStake` SLOAD/SSTORE, conditional `jackpots.getLastBafResolvedDay` (once, cached) | **BOUNDED** by constant (max 1460 iters deep; 365 normal). On the advance spine the sDGNRS auto-claim runs this each day — bounded but a multi-day stall makes it walk up to the window. Gas-relevant. |
| Coinflip._viewClaimableCoin:1139 | windowDays (365) | `_dayResult`,`_flipStake` SLOAD | BOUNDED (view) |
| Coinflip.constructor:203 | SEED_FLIP_DAYS=20 | 2 `_setFlipStake` SSTORE | BOUNDED (deploy only) |
| Coinflip.creditFlipBatch:986 | `players.length` (caller-supplied; Jackpot batches build fixed-size) | `_addDailyFlip` | **INPUT-SIZED** — but the only column callers (Jackpot:1678/1752) batch in module-bounded chunks; external creditors could pass arbitrary length. Bound depends on caller; flagged. |
| sDGNRS.claimRedemptionMany:804 | `players.length` (caller-supplied) | `_claimRedemptionFor` (+ GAME callbacks per settled box) | **INPUT-SIZED / UNBOUNDED** — permissionless keeper batch; gas-bounded only by caller's own gas budget. NOT on advance spine; cannot wedge advance. |
| Affiliate.claim:617 | `subs.length` (caller-supplied) | `_referrerAddress` SLOADs + `afkingDrain.drainAffiliateBase` CALL per sub | **INPUT-SIZED / UNBOUNDED** — permissionless; not on advance spine. |
| Affiliate.affiliateBonusPointsBest:725 | fixed 5 | SLOAD | BOUNDED (view) |
| Affiliate.constructor:276,288 | bootstrap array lengths | code writes | BOUNDED (deploy only) |

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (modules only)

**EMPTY for this slice.** These five contracts are CALL targets, not delegatecall modules of the GAME. They write only their OWN storage. No write here lands in a GAME slot. (The GAME-storage writes triggered transitively are the GAME callbacks — resolveRedemptionLootbox / creditRedemptionDirect / pullRedemptionReserve / payCoinflipBountyDgnrs / consumeCoinflipBoon / drainAffiliateBase — which are GAME-resident and belong to the modules slice.)

For aliasing context only, the callees' own packed-slot writes that the column drives:

- **sDGNRS slot 0** packs `_totalSupply`(uint128) + `_pendingRedemptionEthValue`(uint96) + `_pendingResolveDay`(uint24). The advance spine writes `_pendingRedemptionEthValue` and `_pendingResolveDay` in `resolveRedemptionPeriod` (756,767); `transferFromPool`/`burnAtGameOver` write `_totalSupply` (574,614). Submit path writes all three. **Aliasing-relevant: three independently-masked fields in one slot; a miscomputed mask would corrupt a sibling.** Each is a fresh masked SLOAD/SSTORE per the design.
- **sDGNRS `pendingByDay[day]` (DayPending)** packs `ethBase`/`supplySnapshot`/`burned` (3×uint64) in one slot, keyed by **day**. Written at submit (1051,1058,1106), `delete`d at resolve (764). Keyed-by-day packed write.
- **sDGNRS `poolBalances[5]`** (uint128 lanes, 3 slots) — written by `transferFromPool`/`transferBetweenPools` (column flows), `delete`d at gameOver.
- **Coinflip `coinflipDayResultPacked[day>>5]`** — 32 days/slot 8-bit lanes, keyed by **day**, masked write in `_storeDayResult` (1200) on the advance spine.
- **Coinflip `coinflipStakePacked[day>>1][p]`** — 2 days/slot 128-bit lanes, keyed by **day & player**, masked write in `_setFlipStake` (1180).
- **Coinflip `playerState[p]` (PlayerCoinflipState)** — `claimableStored`/`lastClaim`/`autoRebuyStartDay`/`autoRebuyEnabled`/`autoRebuyStop`/`autoRebuyCarry` packed; written across claim/rebuy/submit paths. The sDGNRS entry is written on every advance (auto-claim).
- **FLIP `_supply`** packs `totalSupply`+`vaultAllowance` (2×uint128) one slot — mint/burn/escrow/tombstone all masked-write this slot.
- **Affiliate** `affiliateTopByLevel[lvl]` (PlayerScore: address+uint96, 1 slot, keyed by **level**), `affiliateCoinEarned[lvl][aff]`, `_totalAffiliateScore[lvl]` — written in payAffiliate/claim (purchase + afking flows).

---

## 5. KEY HUNT NOTES

- **Spine-bricking single point**: `sDGNRS.resolveRedemptionPeriod` (756) checked `uint96` subtraction. Runs on EVERY advance that has a stamped pool. If the cumulative `_pendingRedemptionEthValue` scalar ever drifts below the reconstructed `segregatedMax` for the resolving day, the advance underflow-reverts and the stamped day can NEVER be cleared → permanent advance wedge. The whole telescoping-delta + gwei-snap accounting in `_submitGamblingClaimFrom` exists to guarantee exact reconciliation. This is the #1 candidate to verify against the modules' resolve call sites (Advance:1258/1320/1355) and the single-pool invariant (INV-13).
- **Coinflip processCoinflipPayouts** is the only Coinflip fn truly on the advance spine. The sDGNRS auto-claim it performs (942/944) is the one place a callee-of-callee revert (FLIP.mintForGame uint128 overflow at the seed-window claim, or WWXRP.mintPrice on a loss) could bubble into advance. Both are bounded far under their caps but are genuine spine-bubble paths.
- **The sDGNRS BAF-skip guard (591, `player != SDGNRS`)** is explicitly load-bearing: it keeps the sDGNRS advance auto-claim off the `RngLocked` revert (615) and off `jackpots.recordBafFlip`. If that guard were ever wrong, the advance auto-claim could hit RngLocked and wedge.
- **transferFromPool / burnAtGameOver** are on the gameOver finalization path (GameOverModule:139-140) and selected advance distributions (advance:748). Their pool↔balance internal-accounting underflows (570/574/614) would brick finalization if the invariant breaks. Pool-empty is a safe early-return, not a revert.
- **FLIP.tombstoneAtGameOver** (GameOverModule:142) is a one-shot checked add with ~340x uint128 headroom; latch makes re-entry a no-op. Low risk but on the gameOver path.
- **No nested delegatecall and no raw `delegatecall(msg.data)`** in any of the five callee contracts — they are plain CALL targets, so there is no delegatecall dispatch to map in this slice.
- **Unbounded input-sized loops** (`claimRedemptionMany`, `Affiliate.claim`, `creditFlipBatch` with an arbitrary creditor) are all OFF the advance spine — permissionless player/keeper batches gas-bounded by the caller's own budget; they cannot wedge advance or gameOver.
- **Vault contributes no callee on the GAME column** — it is a caller into the GAME. Its only GAME-driven entry is `receive()` (ETH push), which cannot revert-bubble into advance because the GAME never synchronously CALLs a Vault function during the spine.
