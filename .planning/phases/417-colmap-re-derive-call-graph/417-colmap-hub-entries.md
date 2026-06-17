# 417 COLMAP — HUB: entries + dispatch stubs

Subject tree: frozen `contracts/` @ `0dd445a6` (HEAD at map time `77b66bee`).
File: `contracts/DegenerusGame.sol` (2485 lines).
Scope: external/public ENTRY POINTS + thin delegatecall DISPATCH STUBS only. The `advanceGame` BODY, VRF body, and module internals are owned by other slices; here I map only the `advanceGame` external signature + every other entry/stub. `DegenerusGame` IS the delegatecall HOST (`address(this)`), so all module storage writes invoked through these stubs land in THIS contract's slots — but the writes themselves live in the callee modules, not this slice.

Convention: every stub follows the pattern
```
(bool ok, bytes data) = ContractAddresses.<MODULE>.delegatecall(<calldata>);
if (!ok) _revertDelegate(data);     // bubbles callee revert; empty-reason -> revert E()
[optional] if (data.length == 0) revert E();  // for return-decoding stubs
[optional] return abi.decode(data, (...));
```
`_revertDelegate` (947-953): `if (reason.length==0) revert E(); else assembly revert(reason)`. So EVERY stub re-raises the callee's revert verbatim (or `E()` if the callee gave no reason). The HUB adds NO revert of its own beyond the access guards listed below.

---

## 1. CALL GRAPH

### 1a. The one BODY function the HUB owns (signature only)
| fn:line | guard / payable | dispatch |
|---|---|---|
| `advanceGame()` :279 | none (permissionless); returns uint8 | delegatecall `GAME_ADVANCE_MODULE` with raw `msg.data`. BODY owned by ADVANCE slice. |

### 1b. Pure delegatecall DISPATCH STUBS (forward `msg.data`, no re-encode)
All forward raw `msg.data`. "Selector match" = stub signature == module fn selector.
| fn:line | access guard | payable | module → selector |
|---|---|---|---|
| `wireVrf(address,uint256,bytes32)` :302 | none at stub (ADMIN gate in module) | no | ADVANCE_MODULE.wireVrf |
| `claimBingo(uint24,uint8,uint32[8])` :317 | none | no | BINGO_MODULE.claimBingo |
| `subscribe(address,bool,bool,uint8,uint8,address)` :357 | none at stub (consent gates in module; msg.sender preserved) | **payable** | AFKING_MODULE.subscribe |
| `mintFlip()` :376 | none (permissionless router) | no | AFKING_MODULE.mintFlip |
| `claimAfkingFlip(address[])` :389 | none | no | AFKING_MODULE.claimAfkingFlip |
| `drainAffiliateBase(address)` :402 | none at stub (AFFILIATE gate in module); returns uint256; **`if (data.length==0) revert E()`** | no | AFKING_MODULE.drainAffiliateBase |
| `decurse(address)` :416 | none | no | AFKING_MODULE.decurse |
| `smite(uint256,address)` :428 | none at stub (deity gate in module) | no | AFKING_MODULE.smite |
| `recordAfkingSecondary(address)` :439 | none at stub (QUESTS gate in module) | no | AFKING_MODULE.recordAfkingSecondary |
| `consumeCoinflipBoon(address)` :827 | **`msg.sender==COIN||COINFLIP else revert E()`** :830; returns uint16 | no | BOON_MODULE (raw msg.data) |
| `recordDecBurn(address,uint24,uint8,uint256,uint256)` :968 | none at stub (COIN gate in module); returns uint8; **`if (data.length==0) revert E()`** | no | DECIMATOR_MODULE.recordDecBurn |
| `runDecimatorJackpot(uint256,uint24,uint256)` :991 | **`msg.sender==this else revert E()`** :996; returns uint256; data.length guard | no | DECIMATOR_MODULE.runDecimatorJackpot |
| `runBafJackpot(uint256,uint24,uint256)` :1013 | **`msg.sender==this else revert E()`** :1018; returns uint256; data.length guard | no | JACKPOT_MODULE.runBafJackpot |
| `recordTerminalDecBurn(address,uint24,uint256)` :1038 | none at stub (COIN gate in module) | no | DECIMATOR_MODULE.recordTerminalDecBurn |
| `boostTerminalDecimator()` :1053 | none (permissionless; credits msg.sender) | no | DECIMATOR_MODULE.boostTerminalDecimator |
| `runTerminalDecimatorJackpot(uint256,uint24,uint256)` :1068 | **`msg.sender==this else revert E()`** :1073; returns uint256; data.length guard | no | DECIMATOR_MODULE.runTerminalDecimatorJackpot |
| `runTerminalJackpot(uint256,uint24,uint256)` :1099 | **`msg.sender==this else revert E()`** :1104; returns uint256; data.length guard | no | JACKPOT_MODULE.runTerminalJackpot |
| `emitDailyWinningTraits(uint24,uint256,uint24)` :1121 | **`msg.sender==this else revert E()`** :1126 | no | JACKPOT_MODULE.emitDailyWinningTraits |
| `claimDecimatorJackpot(address,uint24)` :1138 | none | no | DECIMATOR_MODULE.claimDecimatorJackpot |
| `claimDecimatorJackpotMany(address[],uint24)` :1150 | none | no | DECIMATOR_MODULE.claimDecimatorJackpotMany |
| `claimTerminalDecimatorJackpot()` :1164 | none (post-GAMEOVER, enforced in module) | no | DECIMATOR_MODULE.claimTerminalDecimatorJackpot |
| `claimAffiliateDgnrs(address)` :1304 | none | no | BINGO_MODULE.claimAffiliateDgnrs |
| `resolveRedemptionLootbox(address,uint256,uint256,uint16)` :1532 | none at stub (SDGNRS gate in module) | **payable** | LOOTBOX_MODULE.resolveRedemptionLootbox |
| `creditRedemptionDirect(address,uint256)` :1552 | none at stub (SDGNRS gate in module) | **payable** | LOOTBOX_MODULE.creditRedemptionDirect |
| `previewSellFarFutureTickets(address,uint32[],uint256[])` :1648 | none (view-ish; NOT `view` — delegatecalls); returns 5×uint256 | no | MINT_MODULE.previewSellFarFutureTickets |
| `updateVrfCoordinatorAndSub(address,uint256,bytes32)` :1776 | none at stub (ADMIN gate in module) | no | ADVANCE_MODULE.updateVrfCoordinatorAndSub |
| `requestLootboxRng()` :1792 | none | no | ADVANCE_MODULE.requestLootboxRng |
| `retryLootboxRng()` :1804 | none | no | ADVANCE_MODULE.retryLootboxRng |
| `rawFulfillRandomWords(uint256,uint256[])` :1856 | none at stub (VRF coordinator gate in module) | no | ADVANCE_MODULE.rawFulfillRandomWords |

### 1c. Re-encoding DISPATCH STUBS (resolve player, then `abi.encodeWithSelector`)
These call a `private` wrapper or inline-encode. `_resolvePlayer(p)` (509): `p==0 -> msg.sender`; else `_requireApproved` -> `revert NotApproved()` if `msg.sender!=p && !operatorApprovals[p][msg.sender]`.
| fn:line | guard / payable | private wrapper → module.selector |
|---|---|---|
| `purchase(...)` :552 | `_resolvePlayer(buyer)`; **payable** | `_purchaseFor` :569 → MINT_MODULE.purchase |
| `redeemFlip(address,uint256)` :596 | `_resolvePlayer(buyer)`; no | inline → MINT_MODULE.redeemFlip |
| `buyPresaleBox(address,uint256)` :618 | `_resolvePlayer(buyer)`; **payable** | inline → MINT_MODULE.buyPresaleBox |
| `buyLootboxAndPresaleBox(...)` :646 | `_resolvePlayer(buyer)`; **payable** | inline → MINT_MODULE.buyLootboxAndPresaleBox |
| `openBox(address,uint48)` :676 | `_resolvePlayer(player)`; no | inline → LOOTBOX_MODULE.openBox |
| `purchaseWhaleBundle(address,uint256)` :704 | `_resolvePlayer(buyer)`; **payable** | `_purchaseWhaleBundleFor` :712 → WHALE_MODULE.purchaseWhaleBundle |
| `purchaseLazyPass(address)` :729 | `_resolvePlayer(buyer)`; **payable** | `_purchaseLazyPassFor` :734 → WHALE_MODULE.purchaseLazyPass |
| `purchaseDeityPass(address,uint8)` :749 | `_resolvePlayer(buyer)`; **payable** | `_purchaseDeityPassFor` :754 → WHALE_MODULE.purchaseDeityPass |
| `placeDegeneretteBet(...)` :774 | `_resolvePlayer(player)` inline; **payable** | inline → DEGENERETTE_MODULE.placeDegeneretteBet |
| `resolveDegeneretteBets(address,uint64[])` :803 | `_resolvePlayer(player)` inline; no | inline → DEGENERETTE_MODULE.resolveBets |
| `consumeDecimatorBoon(address)` :846 | **`msg.sender==COIN else revert E()`** :849; returns uint16 | inline → BOON_MODULE.consumeDecimatorBoost |
| `issueDeityBoon(address,address,uint8)` :898 | `_resolvePlayer(deity)`; **`recipient==deity -> revert E()`** :904 | inline → LOOTBOX_MODULE.issueDeityBoon |
| `claimWinnings(address)` :1209 | `_resolvePlayer(player)` | calls `_claimWinningsInternal` (see 1e), THEN inline delegatecall → AFKING_MODULE.maybeCurse |
| `claimWhalePass(address)` :1503 | `_resolvePlayer(player)`; no | `_claimWhalePassFor` :1508 → WHALE_MODULE.claimWhalePass |
| `sellFarFutureTickets(...)` :1610 | `_resolvePlayer(player)`; no | inline → MINT_MODULE.sellFarFutureTickets |
| `openBoxes(uint256)` :1442 | none; returns uint256 | TWO sequential delegatecalls: AFKING_MODULE.drainAfkingBoxes, THEN (if budget left) LOOTBOX_MODULE.openHumanBoxes |
| `_degeneretteResolveBet(address,uint64)` :1479 | **`msg.sender==this else revert E()`** :1480 (external self-call target of `degeneretteResolve`) | inline → DEGENERETTE_MODULE.resolveBets |

### 1d. HUB-LOCAL entry points (NO delegatecall — logic runs in this slice)
| fn:line | guard / payable | external/internal calls |
|---|---|---|
| `initPerpetualTickets()` :216 | **`msg.sender!=SDGNRS && !=VAULT -> revert E()`** :218 | loop 1..100 → `_queueTickets` (internal; storage writes) |
| `payCoinflipBountyDgnrs(address,uint256,uint256)` :453 | **`msg.sender!=COIN && !=COINFLIP -> revert E()`** :461 | **EXTERNAL** `dgnrs.poolBalance(Reward)` :465, `dgnrs.transferFromPool(...)` :471 (sDGNRS) |
| `setOperatorApproval(address,bool)` :486 | **`operator==0 -> revert E()`** :487 | writes `operatorApprovals` |
| `setLootboxRngThreshold(uint256)` :530 | **EXTERNAL** `vault.isVaultOwner(msg.sender)` :531 -> revert E if false; **`newThreshold==0 -> revert E()`** :532 | writes packed LR_THRESHOLD |
| `degeneretteResolve(address[],uint64[])` :1339 | **`len==0 || betIds.length!=len -> revert E()`** :1344; **`betPacked==0 -> revert BatchAlreadyTaken()`** :1351; **`totalResolved==0 -> revert NoWork()`** :1378 | loop of `try this._degeneretteResolveBet(...)`; **EXTERNAL** `coinflip.creditFlip(msg.sender, RESOLVE_FLAT_FLIP)` :1379 (Coinflip) |
| `reverseFlip()` :1817 | **`rngLockedFlag -> revert RngLocked()`** :1818 | **EXTERNAL** `coin.burnCoin(msg.sender, cost)` :1821 (DegenerusCoin); writes `totalFlipReversals` |
| `depositAfkingFunding(address)` :1263 | **`player==0 -> revert E()`** :1264; **payable** | `_creditAfkingValue` (internal; storage) |
| `withdrawAfkingFunding(uint256)` :1275 | GO_SWEPT guard :1276 -> revert E; `amount==0 -> return`; **`amount>bal -> revert E()`** :1279; checked `claimablePool -= amount` :1281; **EXTERNAL** `msg.sender.call{value}` :1282 -> **`!ok -> revert E()`** :1283 | writes afking + claimablePool |
| `adminSwapEthForStEth(address,uint256)` :1705 | **`msg.sender!=ADMIN -> revert E()`** :1709; `recipient==0` :1710; `amount==0 \|\| msg.value!=amount` :1711; `stBal<amount` :1714; **payable** | **EXTERNAL** `steth.balanceOf` :1713, `steth.transfer` :1715 -> revert E if false |
| `adminStakeEthForStEth(uint256)` :1726 | **EXTERNAL** `vault.isVaultOwner` :1727 -> revert E; `amount==0` :1728; `ethBal<amount` :1731; `ethBal<=reserve` :1738; `amount>stakeable` :1740 | **EXTERNAL** `steth.balanceOf` :1733/1734, `steth.submit{value}` :1743 in try/catch -> **catch revert E()** :1744 |
| `receive()` :2481 | **`gameOver -> revert E()`** :2482; **payable** | `_creditAfkingValue` (internal; storage) |

### 1e. HUB-LOCAL private payout helpers (reached from claimWinnings paths)
| fn:line | external calls / reverts |
|---|---|
| `_claimWinningsInternal(address,bool)` :1229 | GO_SWEPT guard :1230 -> revert E; **`amount<=1 && afking==0 -> revert E()`** :1237; `_debitClaimableAndAfking`; checked `claimablePool -= payout` :1248; → `_payoutWithStethFallback` or `_payoutWithEthFallback` |
| `_payoutWithStethFallback(to,amount)` :1888 | → `_transferSteth`; **EXTERNAL** `payable(to).call{value}` :1913 LAST -> **`!ok -> revert E()`** :1914 |
| `_payoutWithEthFallback(to,amount)` :1922 | → `_transferSteth`; `ethBal<remaining -> revert E()` :1933; **EXTERNAL** `payable(to).call{value}` :1934 -> `!ok -> revert E()` :1935 |
| `_transferSteth(to,amount)` :1873 | if `to==SDGNRS`: **EXTERNAL** `steth.approve` :1876 -> revert E if false, `dgnrs.depositSteth` :1877; else **EXTERNAL** `steth.transfer` :1880 -> revert E if false |

### 1f. Pure VIEW entries (no delegatecall, read-only — enumerated, not deep-mapped)
`isOperatorApproved` :496, `currentDayView` :522, `deityBoonData` :869, `advanceDue` :1386, `bountyEligible` :1403, `boxesPending` :1412, `boxIndexComplete` :1428, `terminalDecWindow` :1085, `afkingFundingOf` :1290, `previewSellFarFutureTickets` (NOT view — see 1b), `prizePoolTargetView` :1951, `nextPrizePoolView` :1959, `futurePrizePoolView` :1965, `ticketsOwedView` :1973, `lootboxStatus` :1985, `degeneretteBetInfo` :1998, `lootboxPresaleActiveFlag` :2007, `presaleBoxCreditOf` :2014, `presaleBoxEthRemaining` :2020, `currentPrizePoolView` :2028, `claimablePoolView` :2034, `isFinalSwept` :2040, `gameOverTimestamp` :2045, `livenessTriggered` :2053, `yieldPoolView` :2060 (**EXTERNAL** `steth.balanceOf`), `yieldAccumulatorView` :2074, `mintPrice` :2081, `rngWordForDay` :2089, `rngLocked` :2096, `isRngFulfilled` :2102, `lastVrfProcessed` :2108, `decWindow` :2119, `jackpotCompressionTier` :2124, `jackpotPhase` :2129, `purchaseInfo` :2141, `ethMintStats` :2172, `curseCountOf` :2188, `playerActivityScore` :2215, `getWinnings` :2235, `claimableWinningsOf` :2247, `afkingSnapshot` :2263 (loop), `whalePassClaimAmount` :2282, `hasDeityPass` :2289, `mintPackedFor` :2297, `sampleTraitTicketsAtLevel` :2314 (loop, **EXTERNAL** none), `sampleFarFutureTickets` :2341 (loops), `getTickets` :2395 (loop), `getPlayerPurchases` :2421, `getDailyHeroWager` :2436, `getDailyHeroWinner` :2451 (nested loop).

---

## 2. REVERT-SITE INVENTORY

Legend: TRANSIENT = a different caller / actor / next block can still make progress (advanceGame liveness unaffected). PERMANENT-CANDIDATE = could wedge `advanceGame` progress or `gameOver` finalization. NOTE: every delegatecall stub ALSO bubbles the callee module's revert via `_revertDelegate`; those callee reverts are owned by the module slices — only the HUB-LOCAL guard reverts and the bubble mechanics are listed here.

| fn:line | trigger | error | class |
|---|---|---|---|
| `initPerpetualTickets` :218 | caller not SDGNRS/VAULT | `E()` | TRANSIENT (one-time deploy wiring) |
| `_queueTickets` (via init) :617 | `_livenessTriggered()` true | `E()` | TRANSIENT for init; see note in §5 |
| `_revertDelegate` :949 | callee gave empty reason | `E()` | passthrough — class = whatever the callee revert was |
| `advanceGame` :283/284 | callee !ok / decode | bubbles callee | **owned by ADVANCE slice** (the spinal revert surface) |
| `wireVrf` :306 | callee !ok | bubbles (ADMIN gate) | TRANSIENT (admin-only setup) |
| `claimBingo` :325 | callee !ok | bubbles | TRANSIENT (player claim) |
| `subscribe` :368 | callee !ok | bubbles (consent/funding) | TRANSIENT |
| `mintFlip` :380 | callee !ok | bubbles | **see §5** — this is the permissionless advance+afking router; a callee revert here that is *always* hit would deny the bounty path (advance still callable via `advanceGame`) |
| `claimAfkingFlip` :393 | callee !ok | bubbles | TRANSIENT |
| `drainAffiliateBase` :407 | callee !ok OR empty return | `E()` | TRANSIENT (affiliate-only) |
| `decurse` :420 | callee !ok | bubbles | TRANSIENT |
| `smite` :432 | callee !ok | bubbles (deity gate) | TRANSIENT |
| `recordAfkingSecondary` :443 | callee !ok | bubbles (QUESTS gate) | TRANSIENT |
| `payCoinflipBountyDgnrs` :461 | caller not COIN/COINFLIP | `E()` | TRANSIENT |
| `payCoinflipBountyDgnrs` :471 | `dgnrs.transferFromPool` revert (external) | bubbles sDGNRS revert | TRANSIENT (early-returns on zero pool/payout; only reverts if sDGNRS transfer reverts) |
| `setOperatorApproval` :487 | operator==0 | `E()` | TRANSIENT |
| `consumeCoinflipBoon` :833 | caller not COIN/COINFLIP | `E()` | TRANSIENT |
| `consumeCoinflipBoon` :837 | callee !ok | bubbles | TRANSIENT (coinflip stake path) |
| `setLootboxRngThreshold` :531/532 | not vault owner / zero | `E()` | TRANSIENT |
| `purchase`/`_purchaseFor` :588 | callee !ok (RNG-lock, payment, etc. in module) | bubbles | TRANSIENT |
| `redeemFlip` :610 | callee !ok | bubbles | TRANSIENT |
| `buyPresaleBox` :632 | callee !ok | bubbles | TRANSIENT |
| `buyLootboxAndPresaleBox` :668 | callee !ok | bubbles | TRANSIENT |
| `openBox` :687 | callee !ok | bubbles | TRANSIENT |
| `_resolvePlayer`/`_requireApproved` :505 | not self & not approved operator | `NotApproved()` | TRANSIENT (per-caller; the real player can still act) |
| `purchaseWhaleBundle` :722 | callee !ok | bubbles | TRANSIENT |
| `purchaseLazyPass` :743 | callee !ok | bubbles | TRANSIENT |
| `purchaseDeityPass` :764 | callee !ok | bubbles | TRANSIENT |
| `placeDegeneretteBet` :797 | callee !ok | bubbles | TRANSIENT |
| `resolveDegeneretteBets` :816 | callee !ok | bubbles | TRANSIENT |
| `consumeDecimatorBoon` :849 | caller not COIN | `E()` | TRANSIENT |
| `consumeDecimatorBoon` :858 | callee !ok | bubbles | TRANSIENT |
| `issueDeityBoon` :904 | recipient==deity | `E()` | TRANSIENT |
| `issueDeityBoon` :915 | callee !ok | bubbles | TRANSIENT |
| `recordDecBurn` :978/979 | callee !ok / empty return | `E()` | TRANSIENT (COIN gate; burn path) |
| `runDecimatorJackpot` :996 | caller != this | `E()` | **PERMANENT-CANDIDATE** if reachable from advance orchestration with a callee revert (self-call from advance; see §5) |
| `runDecimatorJackpot` :1000/1001 | callee !ok / empty | `E()` | **PERMANENT-CANDIDATE** — reverting jackpot resolution mid-advance can wedge the level transition |
| `runBafJackpot` :1018/1022/1023 | not this / callee !ok / empty | `E()` | **PERMANENT-CANDIDATE** — BAF resolution is in the advance/transition chain |
| `recordTerminalDecBurn` :1046 | callee !ok | bubbles (COIN gate) | TRANSIENT |
| `boostTerminalDecimator` :1057 | callee !ok | bubbles | TRANSIENT |
| `runTerminalDecimatorJackpot` :1073/1077/1078 | not this / callee !ok / empty | `E()` | **PERMANENT-CANDIDATE** — terminal decimator runs during `handleGameOverDrain`; a revert here could wedge gameOver finalization |
| `runTerminalJackpot` :1104/1108/1109 | not this / callee !ok / empty | `E()` | **PERMANENT-CANDIDATE** — terminal jackpot in the gameOver/transition chain |
| `emitDailyWinningTraits` :1126/1130 | not this / callee !ok | `E()`/bubbles | **PERMANENT-CANDIDATE** — self-call in advance at purchaseLevel==1 |
| `claimDecimatorJackpot` :1157 | callee !ok | bubbles | TRANSIENT (player claim) |
| `claimDecimatorJackpotMany` :1157 | callee !ok | bubbles | TRANSIENT |
| `claimTerminalDecimatorJackpot` :1168 | callee !ok | bubbles | TRANSIENT |
| `claimWinnings` :1219 | maybeCurse callee !ok | bubbles | **see §5** — maybeCurse is a delegatecall AFTER the payout; a revert would block the *claim*, not advance |
| `claimWinningsStethFirst` :1225 | caller != VAULT | `E()` | TRANSIENT |
| `_claimWinningsInternal` :1230 | GO_SWEPT set | `E()` | TRANSIENT (post-final-sweep; intended) |
| `_claimWinningsInternal` :1237 | amount<=1 && afking==0 | `E()` | TRANSIENT (nothing to claim) |
| `_claimWinningsInternal` :1248 | `claimablePool -= payout` underflow | checked-arith panic 0x11 | **PERMANENT-CANDIDATE** if pool accounting can be driven below a player's debit (solvency invariant break) — but isolated to the claim tx, not advance |
| `depositAfkingFunding` :1264 | player==0 | `E()` | TRANSIENT |
| `withdrawAfkingFunding` :1276 | GO_SWEPT set | `E()` | TRANSIENT |
| `withdrawAfkingFunding` :1279 | amount>bal | `E()` | TRANSIENT |
| `withdrawAfkingFunding` :1281 | `claimablePool -= amount` underflow | checked panic 0x11 | TRANSIENT (per-caller; guarded by amount>bal) |
| `withdrawAfkingFunding` :1283 | ETH `.call` !ok | `E()` | TRANSIENT (caller's own receiver) |
| `claimAffiliateDgnrs` :1308 | callee !ok | bubbles | TRANSIENT |
| `degeneretteResolve` :1344 | len==0 \|\| length mismatch | `E()` | TRANSIENT |
| `degeneretteResolve` :1351 | probe slot==0 (competitor won) | `BatchAlreadyTaken()` | TRANSIENT (by design — loser-gas cap) |
| `degeneretteResolve` :1378 | totalResolved==0 | `NoWork()` | TRANSIENT |
| `degeneretteResolve` :1379 | `coinflip.creditFlip` revert (external) | bubbles Coinflip revert | TRANSIENT (only on >=3 success; reward leg) |
| `_degeneretteResolveBet` :1480 | caller != this | `E()` | TRANSIENT (per-item; caught by outer try/catch) |
| `_degeneretteResolveBet` :1492 | callee !ok | bubbles (caught by outer try) | TRANSIENT |
| `openBoxes` :1454 | afking-leg callee !ok | bubbles | **see §5** — permissionless box drain; a persistent revert denies the liveness valve but advance still runs |
| `openBoxes` :1468 | human-leg callee !ok | bubbles | see §5 |
| `resolveRedemptionLootbox` :1541 | callee !ok | bubbles (SDGNRS gate) | TRANSIENT |
| `creditRedemptionDirect` :1556 | callee !ok | bubbles (SDGNRS gate) | TRANSIENT |
| `pullRedemptionReserve` :1573 | caller != SDGNRS | `E()` | TRANSIENT |
| `pullRedemptionReserve` :1583 | `claimablePool -= amount` underflow | checked panic | TRANSIENT (guarded by `_claimableOf>=amount`) |
| `pullRedemptionReserve` :1585 | ETH `.call` to SDGNRS !ok | `E()` | TRANSIENT |
| `pullRedemptionReserve` :1599 | neither pure leg covers | `E()` | TRANSIENT (fail-closed; sDGNRS-only) |
| `sellFarFutureTickets` :1628 | callee !ok | bubbles | TRANSIENT |
| `previewSellFarFutureTickets` :1665 | callee !ok | bubbles | TRANSIENT (quote) |
| `reverseFlip` :1818 | rngLockedFlag | `RngLocked()` | TRANSIENT (by design — nudge only while unlocked) |
| `reverseFlip` :1821 | `coin.burnCoin` revert (external) | bubbles Coin revert | TRANSIENT |
| `adminSwapEthForStEth` :1709-1714 | not ADMIN / zero / mismatch / low stETH | `E()` | TRANSIENT |
| `adminSwapEthForStEth` :1715 | `steth.transfer` false | `E()` | TRANSIENT |
| `adminStakeEthForStEth` :1727-1740 | not vault / zero / low ETH / reserve guard | `E()` | TRANSIENT |
| `adminStakeEthForStEth` :1744 | `steth.submit` catch | `E()` | TRANSIENT |
| `updateVrfCoordinatorAndSub` :1784 | callee !ok | bubbles (ADMIN gate) | TRANSIENT |
| `requestLootboxRng` :1796 | callee !ok | bubbles | TRANSIENT |
| `retryLootboxRng` :1808 | callee !ok | bubbles | TRANSIENT |
| `rawFulfillRandomWords` :1863 | callee !ok | bubbles (coordinator gate) | **see §5** — VRF callback; a persistent revert here would block word delivery -> wedge advance (owned by ADVANCE slice, flagged for cross-ref) |
| `_transferSteth` :1876 | `steth.approve` false | `E()` | reachable from claim/payout — TRANSIENT (per-claim) |
| `_transferSteth` :1880 | `steth.transfer` false | `E()` | TRANSIENT |
| `_payoutWithStethFallback` :1914 | ETH `.call` to claimant !ok | `E()` | TRANSIENT (claimant's own receiver) |
| `_payoutWithEthFallback` :1933/1935 | low ETH / `.call` !ok | `E()` | TRANSIENT |

---

## 3. LOOP INVENTORY

| fn:line | iteration bound | per-iter touch | class |
|---|---|---|---|
| `initPerpetualTickets` :219 | fixed `1..100` (100 iters) | `_queueTickets` (1 SSTORE-heavy push + packed write per level) | **BOUNDED** (constant 100; one-time per protocol address) |
| `_currentNudgeCost` :1838 | `reversals` (current nudge count) | pure arith, no storage | INPUT/STATE-SIZED but economically capped — each nudge burns >=100 FLIP compounding +50%, so `totalFlipReversals` is supply-bounded (`<<2^64`); effectively BOUNDED by token supply |
| `degeneretteResolve` :1356 (do-while) | `players.length` (caller-supplied) | per item: 1 SLOAD of `degeneretteBets[p][id]` + external self-call `_degeneretteResolveBet` (try/catch isolates) | **UNBOUNDED / INPUT-SIZED** — caller picks list length; caller pays own gas; reverting/stale items skip, so no wedge, but gas is caller-bounded only |
| `afkingSnapshot` :2270 | `players.length` (caller-supplied, view) | 2 reads per player | UNBOUNDED/INPUT-SIZED (view; no gas-wedge risk) |
| `sampleTraitTicketsAtLevel` :2328 | `take` = min(len,4) | array read | BOUNDED (<=4; view) |
| `sampleFarFutureTickets` :2349 | fixed `<10` (and found<4) | keccak + 1 SLOAD queue.length + read | BOUNDED (<=10; view) |
| `sampleFarFutureTickets` :2371 | `found` (<=4) | copy | BOUNDED (view) |
| `getTickets` :2409 | `[offset, min(offset+limit,total))` | array read + compare | BOUNDED by caller `limit` (paginated; view) |
| `getDailyHeroWinner` :2458 nested :2460 | fixed 4×8 = 32 | packed read | BOUNDED (view) |

No loops appear in the `advanceGame` BODY here (owned by ADVANCE slice). The only state-mutating loops in this slice are `initPerpetualTickets` (bounded 100) and `degeneretteResolve` (caller-sized, self-paying, per-item isolated).

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (modules only)

**N/A for the bulk of this slice by ROLE.** `DegenerusGame` is the HOST contract (`address(this)`), not a module. Module storage writes that *land* in these slots are authored in the callee module slices (MINT, WHALE, LOOTBOX, DEGENERETTE, DECIMATOR, JACKPOT, BOON, BINGO, AFKING, ADVANCE) and must be inventoried there. This HUB slice only WRITES storage in its own non-delegatecall bodies. Those direct HUB writes are:

| fn:line | Game-storage variable/field written | packed? |
|---|---|---|
| constructor :200 | `purchaseStartDay` | slot-0 region field |
| constructor :201 | `dailyIdx` | slot-0 region field |
| constructor :202 | `levelPrizePool[0]` | mapping value |
| constructor :204 | `mintPacked_[SDGNRS]` (HAS_DEITY_PASS bit set via BitPackingLib) | **PACKED** — mintPacked_ keyed by address, HAS_DEITY_PASS_SHIFT offset |
| constructor :205 | `mintPacked_[VAULT]` (HAS_DEITY_PASS bit) | **PACKED** — same field, VAULT key |
| `initPerpetualTickets`→`_queueTickets` :619/626 | `ticketQueue[wk]` (push), `ticketsOwedPacked[wk][buyer]` | **PACKED** ticketsOwedPacked keyed by (level-derived wk, buyer): `owed<<8 \| rem` |
| `setOperatorApproval` :488 | `operatorApprovals[msg.sender][operator]` | bool mapping |
| `setLootboxRngThreshold` :538 | LR_THRESHOLD field via `_lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, ...)` | **PACKED** — `_lr*` lootbox-RNG packed slot, THRESHOLD offset |
| `_claimWinningsInternal` :1247 | per-player claimable+afking via `_debitClaimableAndAfking(player, claimDebit, afking)` | **PACKED** — single per-player slot holds BOTH claimableWinnings and afkingFunding halves |
| `_claimWinningsInternal` :1248 | `claimablePool` (checked `-= payout`) | slot field (uint128) |
| `depositAfkingFunding`→`_creditAfkingValue` :1265 | per-player afkingFunding half + `claimablePool` (in tandem) | **PACKED** afking half of per-player slot |
| `withdrawAfkingFunding` :1280/1281 | `_debitAfking(msg.sender, amount)` afking half; `claimablePool -= amount` | **PACKED** afking half |
| `pullRedemptionReserve` :1582/1583 | `_debitClaimable(SDGNRS, amount)` claimable half; `claimablePool -= amount` | **PACKED** claimable half (SDGNRS key) |
| `reverseFlip` :1826 | `totalFlipReversals` (uint64, masked RMW preserving co-resident `lastVrfProcessedTimestamp`) | **PACKED** — shares slot with `lastVrfProcessedTimestamp` (RMW aliasing hotspot) |
| `receive`→`_creditAfkingValue` :2483 | per-player afkingFunding half + `claimablePool` (tandem) | **PACKED** afking half |

(`_creditAfkingValue`, `_debitAfking`, `_debitClaimable`, `_debitClaimableAndAfking`, `_lrWrite` bodies live in `DegenerusGameStorage` — their exact packed layout is the synthesizer's slot-map job; named here precisely.)

---

## 5. HUNT-RELEVANT NOTES (418-425)

- **Self-call jackpot resolvers are the PERMANENT-CANDIDATE cluster.** `runDecimatorJackpot` :991, `runBafJackpot` :1013, `runTerminalDecimatorJackpot` :1068, `runTerminalJackpot` :1099, `emitDailyWinningTraits` :1121 are all `onlySelf` (`msg.sender==this`) and are invoked by the ADVANCE/JACKPOT orchestration DURING a level transition / gameOver drain. Each does `delegatecall` then `if(!ok) _revertDelegate(data)` and (for the uint-returning four) `if(data.length==0) revert E()`. If the callee module reverts deterministically for a given level/pool/rngWord, the bubble re-raises and can WEDGE the advance/gameOver step that called it. The HUB stub adds NO catch — it is a hard bubble. Cross-check the callee module bodies (DECIMATOR/JACKPOT slices) for any input/state combo that always reverts.
- **`mintFlip()` :376 is the permissionless advance+afking bounty router** (note: it is the AFKING module fn, NOT the legacy mint). A persistent callee revert denies the *bounty path* but `advanceGame()` :279 is a separate stub into ADVANCE_MODULE, so core liveness is not gated by mintFlip.
- **`rawFulfillRandomWords` :1856 bubbles the VRF callback.** A deterministic revert in the ADVANCE module's fulfillment body would block word delivery and wedge the RNG gate. Owned by ADVANCE slice; flagged here because the HUB stub is the entry and offers no fallback.
- **No nested delegatecall and no `delegatecall(msg.data)`-as-dispatch found in this slice.** Every stub targets a FIXED `ContractAddresses.GAME_*_MODULE` constant with either raw `msg.data` or a known `abi.encodeWithSelector`. No selector is attacker-chosen; no proxy-style `delegatecall(msg.data)` to an arbitrary target. (The modules MAY themselves delegatecall further — that is a module-slice question; from the HUB every delegatecall is depth-1 into a constant module.) `openBoxes` :1442 and `claimWinnings` :1209 each issue TWO depth-1 delegatecalls in one tx, but neither is nested.
- **External-call revert that bubbles into a column tx:** the only synchronous external calls reachable from column-adjacent permissionless entries are `degeneretteResolve`→`coinflip.creditFlip` :1379 (Coinflip) and `reverseFlip`→`coin.burnCoin` :1821 (Coin) — both in HUB-local entries that are NOT in the advanceGame chain, so a revert bricks only that one user tx. The payout helpers' ETH `.call`s (1282/1584/1913/1934) are to the claimant/sDGNRS and bubble `E()` on failure but are isolated to the claim/withdraw tx. `adminStakeEthForStEth` wraps `steth.submit` in try/catch (no bubble). `_transferSteth`→`dgnrs.depositSteth` :1877 / `steth.approve/transfer` could revert on a claim payout to SDGNRS/VAULT but isolated to that claim.
- **Packed-write aliasing hotspots to watch:** `reverseFlip` :1826 RMW-masks `totalFlipReversals` while preserving co-resident `lastVrfProcessedTimestamp` (the VRF-stall clock the liveness guard reads) — a wrong mask here could corrupt the stall timer that gates `livenessTriggered()`. The per-player claimable+afking single-slot (`_debitClaimableAndAfking`, `_creditAfkingValue`, `_debitAfking`, `_debitClaimable`) is debited/credited in tandem with `claimablePool` across claimWinnings/deposit/withdraw/pullRedemptionReserve — the solvency invariant `balance >= claimablePool` rides on these staying consistent.
- **`initPerpetualTickets` :216** queues 100 levels via `_queueTickets`, which itself reverts on `_livenessTriggered()` :617. Since this is one-time deploy wiring by VAULT/SDGNRS, liveness can't yet be triggered — not a wedge in practice, but noted as the one state-mutating bounded loop.
