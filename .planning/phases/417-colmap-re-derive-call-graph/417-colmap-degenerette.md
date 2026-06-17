# Column Map — Slice: DegeneretteModule (`DegenerusGameDegeneretteModule.sol`)

Subject: FROZEN `contracts/` tree `0dd445a6`. Read-only enumeration.
File: `contracts/modules/DegenerusGameDegeneretteModule.sol` (1466 lines).
Inheritance: `DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils` → ... → `DegenerusGameStorage`. Helpers cited from `contracts/storage/DegenerusGameStorage.sol` and `contracts/modules/DegenerusGameMintStreakUtils.sol`.

## DELEGATECALL CONTEXT (load-bearing)

Every function here runs in **DegenerusGame's storage** via delegatecall. The module is reached through two distinct delegatecall reach-paths:

1. **Player-bet path (single delegatecall depth)** — `DegenerusGame.placeDegeneretteBet`/`resolveDegeneretteBets`/`_degeneretteResolveBet` (`DegenerusGame.sol:782-797,807-816,1483-1492`) `.delegatecall` → `placeDegeneretteBet` / `resolveBets`. NOT on the advanceGame spinal chain itself; player-driven.
2. **Box-spin path (NESTED delegatecall)** — `DegenerusGameLootboxModule` (itself reached via delegatecall from Game/afking/advance) does `GAME_DEGENERETTE_MODULE.delegatecall(...)` at `DegenerusGameLootboxModule.sol:2098 / 2117 / 2136` → `resolveWwxrpSpinFromBox` / `resolveFlipSpinsFromBox` / `resolveEthSpinFromBox`. These three are **delegatecall-reached-from-a-delegatecalled-module** = NESTED. Lootbox opens occur inside afking auto-open and advanceGame jackpot/recirc, so the box-spin entries ARE column-reachable.
3. `resolveEthSpinFromBox` then does a further nested `_resolveLootboxDirect` → `GAME_LOOTBOX_MODULE.delegatecall` (`:924-936`) — a delegatecall issued from inside a nested delegatecall (depth ≥ 3).

`address(this) != ContractAddresses.GAME` guard on the three box-spin entries (`:1298,1353,1408`) rejects any non-delegatecall (direct) invocation of the deployed module instance.

---

## 1. CALL GRAPH (column-reachable functions)

### `placeDegeneretteBet(address,uint8,uint128,uint8,uint32,uint8)` external payable — `:383`
- internal: `_resolvePlayer` (`:165`), `_placeDegeneretteBet` (`:467`).

### `_placeDegeneretteBet(...)` private — `:467`
- internal: `_placeDegeneretteBetCore` (`:501`), `_collectBetFunds` (`:587`), `PriceLookupLib.priceForLevel` (lib, pure).
- **external sync call:** `quests.handleDegenerette(player,totalBet,bool,mintPrice)` (`:490`) — to Quests contract (only for ETH/FLIP).

### `_placeDegeneretteBetCore(...)` private — `:501`
- internal: `_lrRead` (`:531`), `_effectiveQuestStreak` (`:541`), `_playerActivityScore` (`:543`), `_packFullTicketBet` (`:547`), `_simulatedDayIndex` (`:569`).
- **external sync calls (transitive, view):** via `_effectiveQuestStreak` → `quests.effectiveBaseStreakAndAfking` (Quests); via `_playerActivityScore`→`_playerActivityScoreAt` → `affiliate.affiliateBonusPointsBest` (Affiliate, only when cache stale).
- writes: `degeneretteBetNonce`, `degeneretteBets`, `dailyHeroWagers` (see §4).

### `_collectBetFunds(...)` private — `:587`
- internal: `_settleShortfall` (`:598`), `_getPendingPools`/`_setPendingPools` or `_getPrizePools`/`_setPrizePools` (`:602-608`), `_lrAdd` (`:609,614`), `_packEthToMilliEth`, `_packFlipToWhole`.
- **external sync calls:** `coin.burnCoin(player,totalBet)` (`:613`, FLIP); `wwxrp.burnForGame(player,totalBet)` (`:616`, WWXRP) to WWXRP token.

### `resolveBets(address,uint64[])` external — `:429`
- internal: `_livenessTriggered` (`:435`), `_resolvePlayer`, loop→`_resolveBet` (`:440`), `_addClaimableEth` (`:449`), `_setPendingPools`/`_setFuturePrizePool` (`:455,457`).
- **external sync calls (flush):** `coin.mintForGame(player,acc.flipMint)` (`:447`); `wwxrp.mintPrize(player,acc.wwxrpMint)` (`:448`).

### `_resolveBet(...)` private — `:621` → `_resolveFullTicketBet` (`:629`).

### `_resolveFullTicketBet(...)` private — `:635`
- internal: `_roiBpsFromScore`, `_wwxrpHighValueRoi`, `_countGoldQuadrants`, loop→`DegenerusTraitUtils.packedTraitsDegenerette` (lib), `_score`, `_fullTicketPayout`, `_distributePayout` (`:725`), `_awardDegeneretteDgnrs` (`:738`), `EntropyLib.hash2` (lib), `_resolveLootboxDirect` (`:788`).
- writes: `delete degeneretteBets` (`:655`), `whalePassClaims`, `wwxrpJackpotWhalePassBracketAwarded` (`:752-753`). Accumulator-mutating (acc memory): `acc.flipMint` (`:774,777`).
- **external sync call (NESTED via `_resolveLootboxDirect`):** `GAME_LOOTBOX_MODULE.delegatecall(resolveLootboxDirect)` (`:924`).

### `_distributePayout(...)` private — `:837`
- internal: `_getPendingPools`/`_getFuturePrizePool` (`:871,873`); mutates `acc` only (no storage write — pool flush deferred to caller). Emits `PayoutCapped` (`:895`).

### `_resolveLootboxDirect(...)` private — `:917`
- **NESTED delegatecall:** `GAME_LOOTBOX_MODULE.delegatecall(IDegenerusGameLootboxModule.resolveLootboxDirect)` (`:924-936`); bubbles via `_revertDelegate(data)` (`:936`).

### `_addClaimableEth(...)` private — `:1203`
- writes `claimablePool` (`:1204`); internal `_creditClaimable` (`:1205`) → writes `balancesPacked` (`DegenerusGameStorage.sol:936`), emits `PlayerCredited`.

### `_awardDegeneretteDgnrs(...)` private — `:1210`
- **external sync calls:** `sdgnrs.poolBalance(Pool.Reward)` (`:1220`, view); `sdgnrs.transferFromPool(Pool.Reward,player,reward)` (`:1229`) to sDGNRS.

### `resolveWwxrpSpinFromBox(address,uint256,uint16,uint256)` external payable — `:1292` (NESTED entry)
- internal: `_boxBetId`, `_roiBpsFromScore`, `_wwxrpHighValueRoi`, `DegenerusTraitUtils.packedTraitsDegenerette`, `EntropyLib.hash2`, `_score`, `_countGoldQuadrants`, `_fullTicketPayout`, `_packSpin`.
- **external sync call:** `wwxrp.mintPrize(player,payout)` (`:1319`). Writes `whalePassClaims`, `wwxrpJackpotWhalePassBracketAwarded` (`:1326-1327`). Emits `BoxSpin`.

### `resolveFlipSpinsFromBox(address,uint256,uint16,uint256)` external payable — `:1347` (NESTED entry)
- internal: same trait/score helpers; loop `i<BOX_FLIP_SPINS(=3)`.
- **external sync call:** `coin.mintForGame(player,total)` (`:1387`). Emits `BoxSpin`. No storage write (mint-only).

### `resolveEthSpinFromBox(address,uint256,uint16,uint256)` external payable — `:1402` (NESTED entry)
- internal: trait/score helpers, `_distributePayout` (`:1436`), `_awardDegeneretteDgnrs` (`:1437`, → sDGNRS external), `_addClaimableEth` (`:1440`), `_setPendingPools`/`_setFuturePrizePool` (`:1443,1445`), `_resolveLootboxDirect` (`:1456`, **further NESTED delegatecall, recirc, allowEthSpin=false**).
- writes: `claimablePool`, `balancesPacked`, `prizePoolsPacked`/`prizePoolPendingPacked`. Emits `BoxSpin`.

### Pure helpers (no calls/writes): `_packFullTicketBet`, `_countGoldQuadrants`, `_score`, `_wwxrpBonusBucket`, `_wwxrpFactor`, `_fullTicketPayout`, `_getBasePayoutBps`, `_roiBpsFromScore`, `_wwxrpHighValueRoi`, `_boxBetId`, `_packSpin`, `_revertDelegate`.

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | T/P |
|---|---|---|---|
| `_revertDelegate:155` | bubbled delegatecall reason empty | `E()` | TRANSIENT (re-raises callee failure) |
| `_resolvePlayer:170` | player≠sender & not operator-approved | `NotApproved()` | TRANSIENT (bad operator input) |
| `resolveBets:435` | `_livenessTriggered()` true (game-over drain armed) | `E()` | **PERMANENT-CANDIDATE** — once liveness latches, ALL `resolveBets` (incl. `_degeneretteResolveBet` self-call) revert forever. By design pending bets settle via game-over drain, but this is a hard permanent block on the resolve path post-liveness. |
| `_placeDegeneretteBetCore:525` | currency ∉ {0,1,3} | `UnsupportedCurrency()` | TRANSIENT (placement only; bad input) |
| `_placeDegeneretteBetCore:527` | ticketCount 0 or > per-cur cap | `InvalidBet()` | TRANSIENT |
| `_placeDegeneretteBetCore:528` | amountPerTicket < min | `InvalidBet()` | TRANSIENT |
| `_placeDegeneretteBetCore:529` | heroQuadrant ≥ 4 | `InvalidBet()` | TRANSIENT |
| `_placeDegeneretteBetCore:532` | lootbox RNG index == 0 | `E()` | TRANSIENT (placement only; index re-seeds next cycle) |
| `_placeDegeneretteBetCore:533` | `lootboxRngWordByIndex[index] != 0` (word already landed) | `RngNotReady()` | TRANSIENT (placement only — misnamed; blocks placing into an already-resolved index) |
| `_placeDegeneretteBetCore:561` | `++nonce` overflow (unchecked block — wraps, no revert) | — (no revert; uint64, unreachable) | n/a |
| `_collectBetFunds:596` | ethPaid > totalBet | `InvalidBet()` | TRANSIENT |
| `_collectBetFunds` via `_settleShortfall` (`Storage:906`) | claimable+afking can't cover shortfall | `E()` | TRANSIENT (placement; insufficient player funds) |
| `_collectBetFunds:607` | `future + uint128(totalBet)` overflow | checked-arith panic 0x11 | TRANSIENT (would need pool > 2^128 wei; unreachable) |
| `_collectBetFunds:609/614` `_lrAdd` | field+delta wraps at mask (NO revert — masked) | — | n/a (silent wrap on 64/40-bit pending field) |
| `_resolveBet:627` | `degeneretteBets[player][betId] == 0` (unknown/already-resolved id) | `InvalidBet()` | TRANSIENT (one bad id in array reverts whole `resolveBets`; caller drops it & retries) |
| `_resolveFullTicketBet:653` | `lootboxRngWordByIndex[index] == 0` (RNG word not landed) | `RngNotReady()` | TRANSIENT (resolution waits for VRF; one un-ready id reverts the whole batch) |
| `_resolveFullTicketBet:777` | `acc.flipMint -= totalPayout` survival-flip-loss subtraction | checked-arith panic 0x11 if `acc.flipMint < totalPayout` | TRANSIENT — see riskNotes; per-bet flipMint was added in the same call (`:907`/`:774`) so balanced, but cross-bet ordering is the audit-relevant edge. |
| `_distributePayout:884` | frozen pool: `acc.pendingFuture < ethShare` | `E()` | TRANSIENT (insufficient pending future during freeze; one spin reverts batch) |
| `_distributePayout:898` `pool -= ethShare` | unchecked (post-cap `ethShare ≤ 10% pool`, no underflow) | — | n/a |
| `_addClaimableEth:1204` | `claimablePool += uint128(weiAmount)` overflow | checked-arith panic 0x11 | TRANSIENT (needs pool > 2^128; unreachable) |
| `_creditClaimable` (`Storage:936`) | `balancesPacked += weiAmount` carry into afking half | (commented safe; no revert) | n/a |
| `resolveWwxrpSpinFromBox:1298` | `address(this) != GAME` | `E()` | TRANSIENT (rejects direct call; never true under delegatecall) |
| `resolveFlipSpinsFromBox:1353` | `address(this) != GAME` | `E()` | TRANSIENT |
| `resolveEthSpinFromBox:1408` | `address(this) != GAME` | `E()` | TRANSIENT |
| `resolveEthSpinFromBox` via `_distributePayout:884` | frozen pool pending insufficient during box ETH-spin | `E()` | **PERMANENT-CANDIDATE (callee-revert-bubbles)** — box ETH-spin runs INSIDE lootbox-open which runs inside afking/advance; a revert here bubbles up the nested delegatecall and can brick the surrounding open/advance tx. See externalCallRevertRisks. |
| `_resolveLootboxDirect:936` | nested lootbox delegatecall failed | bubbles via `_revertDelegate` | **PERMANENT-CANDIDATE (bubbles)** — any revert inside `resolveLootboxDirect` (lootbox module) propagates through here into resolveBets / box-spin / advance. |
| external `coin.mintForGame` / `coin.burnCoin` / `wwxrp.mintPrize` / `wwxrp.burnForGame` / `sdgnrs.transferFromPool` | callee reverts (paused, cap, insufficient pool, etc.) | bubbles | TRANSIENT for player paths; **PERMANENT-CANDIDATE on the box-spin path** (bubbles into the column open/advance tx — see externalCallRevertRisks). |
| external `quests.handleDegenerette` (`:490`) | Quests callee reverts | bubbles | TRANSIENT (placement only) |
| `_getBasePayoutBps` / `_fullTicketPayout` arithmetic | `betAmount * basePayout * effectiveRoi` (`:1100`) checked-mul | panic 0x11 if product > 2^256 | TRANSIENT (betAmount uint128 × ~2e7 × ~3e4 ≪ 2^256; unreachable) |

Notes:
- The deployed-instance `address(this)!=GAME` guards are NOT permanent blockers — under the real delegatecall path `address(this)==GAME` always holds; they only reject misuse.
- `RngNotReady` at `:653` and the per-id `InvalidBet` at `:627` revert the WHOLE `resolveBets` batch; a single un-ready / stale id wedges the batch but the player can resubmit a filtered list — TRANSIENT at the system level. The Game-side `_degeneretteResolveBet` (`DegenerusGame.sol:1479`) isolates per-betId, so the per-item path tolerates one bad id.

---

## 3. LOOP INVENTORY

| fn:line | bound expr | per-iter storage/gas | B/U |
|---|---|---|---|
| `resolveBets:439` | `betIds.length` (calldata) | per id: `_resolveBet` → full spin loop + 1 box delegatecall + ≤2 SSTOREs (whalePass) + external sDGNRS calls | **UNBOUNDED / INPUT-SIZED** — caller-supplied array length, unbounded; each element runs the inner spin loop and a lootbox delegatecall. Gas scales `len × ticketCount`. Player-driven (not advanceGame), but a large `betIds` self-DoS / griefing surface. |
| `_resolveFullTicketBet:673` | `ticketCount` (≤25 ETH / ≤15 FLIP / ≤5 WWXRP, validated at placement `:527`) | per spin: keccak, trait derive, `_score` loop (4), `_fullTicketPayout`, `_distributePayout` (acc-only), emit `FullTicketResult`; conditional `_awardDegeneretteDgnrs` (sDGNRS view+transfer) + whalePass SSTOREs | **BOUNDED** (≤25). NB: the per-spin `_awardDegeneretteDgnrs` makes up to `ticketCount` external sDGNRS calls. |
| `_countGoldQuadrants:986` | `q < 4` const | none (pure) | BOUNDED |
| `_score:1006` | `q < 4` const | none (pure) | BOUNDED |
| `resolveFlipSpinsFromBox:1362` | `BOX_FLIP_SPINS == 3` const | per iter: 2 keccak/hash2, 2 trait derive, `_score`, `_fullTicketPayout` (pure), pack | BOUNDED |
| `_wwxrpFactor` / `_getBasePayoutBps` | branch dispatch, no loop | — | n/a |

Only `resolveBets:439` is truly input-sized/unbounded; everything else is constant- or placement-capped.

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots written by this module)

| fn:line | variable (as declared) | packed? / key |
|---|---|---|
| `_placeDegeneretteBetCore:561` | `degeneretteBetNonce[player]` (`mapping(address=>uint64)`) | keyed by player |
| `_placeDegeneretteBetCore:563` | `degeneretteBets[player][nonce]` (`mapping=>mapping=>uint256`) | full word, keyed player/nonce |
| `_placeDegeneretteBetCore:581` | `dailyHeroWagers[day][heroQuadrant]` (`mapping=>mapping=>uint256`) | **PACKED** — 8× uint32 sub-counters by `heroSymbol` (`shift = heroSymbol*32`), keyed by **day** + **heroQuadrant**. Saturating per-symbol slot at 0xFFFFFFFF. |
| `_collectBetFunds:604` (frozen) | `prizePoolPendingPacked` via `_setPendingPools(pNext, pFuture+totalBet)` | **PACKED** uint128 next(low)\|uint128 future(high) |
| `_collectBetFunds:607` (unfrozen) | `prizePoolsPacked` via `_setPrizePools(next, future+totalBet)` | **PACKED** next\|future |
| `_collectBetFunds:609` (ETH) | `lootboxRngPacked` via `_lrAdd(LR_PENDING_ETH_SHIFT, mask)` | **PACKED** — 64-bit pendingEth field @ bit 48, masked wrap |
| `_collectBetFunds:614` (FLIP) | `lootboxRngPacked` via `_lrAdd(LR_PENDING_FLIP_SHIFT, mask)` | **PACKED** — 40-bit pendingFlip field @ bit 184, masked wrap |
| `_resolveFullTicketBet:655` | `delete degeneretteBets[player][betId]` | full word zero |
| `_resolveFullTicketBet:752` | `whalePassClaims[player]` (`+= 1`) | keyed by player (WWXRP S=9 jackpot) |
| `_resolveFullTicketBet:753` | `wwxrpJackpotWhalePassBracketAwarded[bracket]` (`=true`) | keyed by `level/10` **bracket** |
| `resolveBets:455` (frozen flush) | `prizePoolPendingPacked` via `_setPendingPools(acc.pendingNext,acc.pendingFuture)` | **PACKED** next\|future |
| `resolveBets:457` (unfrozen flush) | `prizePoolsPacked` (future half) via `_setFuturePrizePool(acc.runningFuture)` | **PACKED** — future half only (`_setFuturePrizePool` RMWs the next half) |
| `_addClaimableEth:1204` | `claimablePool` (`uint128`, `+=`) | solvency-total accumulator |
| `_addClaimableEth:1205`→`_creditClaimable` (Storage:936) | `balancesPacked[beneficiary]` (`+= weiAmount`) | **PACKED** — claimable(low128)\|afking(high128), low-half credit |
| `_settleShortfall` (Storage:899-909) [via `_collectBetFunds:598`] | `balancesPacked[buyer]` (`_debitClaimable`/`_debitAfking`) + `claimablePool` (`-=`) | **PACKED** balances both halves + solvency-total |
| `resolveWwxrpSpinFromBox:1326` | `whalePassClaims[player]` (`+= 1`) | keyed by player |
| `resolveWwxrpSpinFromBox:1327` | `wwxrpJackpotWhalePassBracketAwarded[bracket]` (`=true`) | keyed by `level/10` bracket |
| `resolveEthSpinFromBox:1440`→`_addClaimableEth` | `claimablePool`, `balancesPacked[player]` | as above |
| `resolveEthSpinFromBox:1443` (frozen) | `prizePoolPendingPacked` via `_setPendingPools` | **PACKED** next\|future |
| `resolveEthSpinFromBox:1445` (unfrozen) | `prizePoolsPacked` future half via `_setFuturePrizePool` | **PACKED** future half (RMW) |

`resolveFlipSpinsFromBox` writes NO storage (mint-only; `coin.mintForGame` + `BoxSpin` event).

The nested `_resolveLootboxDirect` delegatecall (resolveBets bet-win recirc `:788`, box ETH-spin recirc `:1456`) writes Game storage inside the **LootboxModule** slice — out of this slice; flagged here as the nested-write entry point.

---

## CROSS-REFERENCES FOR SYNTHESIZER

- Packed slots this slice writes that other slices also touch (aliasing): `prizePoolsPacked` / `prizePoolPendingPacked` (advance/jackpot/purchase), `lootboxRngPacked` (RNG/lootbox slices), `balancesPacked[*]` + `claimablePool` (payout/claim/afking), `mintPacked_[player]` (read-only here via activity score), `whalePassClaims` + `wwxrpJackpotWhalePassBracketAwarded` (whale-pass slice).
- `dailyHeroWagers[day][heroQuadrant]` packed by `heroSymbol*32` is degenerette-local but read by the daily-hero-reward settlement (advance chain) — write-here / read-there.
