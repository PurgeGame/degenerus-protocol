# 417 Column Map — Slice: MintModule (`DegenerusGameMintModule`)

Subject = frozen `contracts/` tree `0dd445a6` (worktree HEAD `77b66bee`).
File: `contracts/modules/DegenerusGameMintModule.sol` (2256 lines), parents
`DegenerusGamePayoutUtils` + `DegenerusGameMintStreakUtils` → `DegenerusGameStorage`.

Module runs via **DELEGATECALL** from `DegenerusGame` → all storage writes land in the GAME's slots.
Focus: mint/purchase payment + ticket-enqueue, the nested delegatecall into BoonModule, the
msg.value-in-flight path, and the current/future ticket-batch processors that the advanceGame
chain drives.

External contract aliases (compile-time constants in `DegenerusGameStorage`):
`coin`=COIN (FLIP/DGNRS token), `coinflip`=COINFLIP, `affiliate`=AFFILIATE, `quests`=QUESTS,
`dgnrs`=SDGNRS, plus `ContractAddresses.VAULT` / `ContractAddresses.SDGNRS` read in salvage paths.

Column reachability note: the **advanceGame/mintFlip spine** reaches this slice via
`processTicketBatch` / `processFutureTicketBatch` (current+future ticket drain) — those are the
load-bearing column entrypoints. The purchase/salvage entrypoints (`purchase`, `purchaseWith`,
`redeemFlip`, `buyPresaleBox`, `buyLootboxAndPresaleBox`, `sellFarFutureTickets`) are
user/keeper-driven mint legs that share the same storage and are mapped for completeness (their
reverts are TRANSIENT to the spine unless noted).

---

## 1. CALL GRAPH

Legend: `→i` internal/private same-frame call · `→X` synchronous external call · `→D(nested)`
nested delegatecall (msg.value kept in flight) · writes land in GAME storage.

### Column-spine entrypoints (driven by advance/mintFlip chain)

- **`processTicketBatch(uint24 lvl) external → (bool finished)`** (845)
  - →i `_tqReadKey` · `_livenessTriggered`-free (no liveness gate here) · `_lrRead`
  - →i `_processOneTicketEntry` (loop body)
    - →i `_resolveZeroOwedRemainder` →i `_rollRemainder` (pure)
    - →i `_raritySymbolBatch` (assembly bulk SSTORE of `traitBurnTicket`)
    - emits `TraitsGenerated`
  - reads `lootboxRngWordByIndex[index-1]` as entropy; writes `ticketQueue`/`ticketCursor`/`ticketLevel`/`ticketsOwedPacked`/`traitBurnTicket`
  - **No external calls. No delegatecall.**

- **`processFutureTicketBatch(uint24 lvl, uint256 entropy) external → (bool worked, bool finished, uint32 writesUsed)`** (544)
  - →i `_tqFarFutureKey` / `_tqReadKey`
  - →i `_rollRemainder` (pure) · `_raritySymbolBatch`
  - emits `TraitsGenerated`
  - entropy is passed in by caller (today's daily RNG word) — RNG-freeze safe
  - writes `ticketQueue`/`ticketCursor`/`ticketLevel`/`ticketsOwedPacked`/`traitBurnTicket`
  - **No external calls. No delegatecall.**

### Purchase entrypoints (user/keeper mint legs)

- **`purchase(...) external payable`** (1036) →i `_purchaseFor`
- **`purchaseWith(..., uint256 ethValue) external`** (1057) →i `_purchaseForWith` (afking STAGE; reached via delegatecall from GameAfkingModule)
- **`buyPresaleBox(address,uint256) external payable`** (1840) →i `_buyPresaleBoxFor(buyer, boxAmount, msg.value)`
- **`buyLootboxAndPresaleBox(...) external payable`** (1854) →i `_purchaseCostInputs`, →i `_purchaseForWithCached`, →i `_buyPresaleBoxFor` (splits one msg.value across both legs)
- **`redeemFlip(address,uint256) external`** (1081) →i `_redeemFlipFor`

- **`_purchaseFor`** (1404) →i `_purchaseCostInputs`, `_creditAfkingValue` (overpay→afking), `_purchaseForWithCached`. **Reads `msg.value`.**
- **`_purchaseForWith`** (1460) →i `_purchaseCostInputs`, `_purchaseForWithCached` (no msg.value; explicit `ethValue`).
- **`_purchaseForWithCached`** (1491) — CORE PURCHASE BODY:
  - →i `_livenessTriggered`, `_claimableOf`, `_settleShortfall`, `_recordLootboxMintDay`, `_applyLootboxBoostOnPurchase`, `_packEthToMilliEth`, `_isDistressMode`, `_getPrizePools/_setPrizePools` or `_getPendingPools/_setPendingPools`, `_liveAfkingStreak`, `_recordMintStreakForLevel`, `_activeTicketLevel`, `_clearCurse`, `_playerActivityScore`, `_centuryUsedFor`/`_setCenturyUsedFor`, `_queueTicketsScaled`, `_ethToFlipValue`, `_lootboxEvMultiplierFromScore`, `_lootboxEvUsedFor`/`_setLootboxEvUsedFor`, `_packLootbox`, `_lrRead`, `_unpackLootbox`
  - →i `_callTicketPurchase` (ticket leg) — see below (contains the nested BoonModule delegatecall)
  - →X `quests.handlePurchase(...)` (QUESTS) (1677)
  - →X `affiliate.payAffiliate(...)` (AFFILIATE) ×2 lootbox legs (1736, 1746)
  - →X `coinflip.creditFlip(buyer, lootboxFlipCredit)` (COINFLIP) (1830)
  - emits `LootBoxBuy`
- **`_callTicketPurchase`** (2001) — ticket leg:
  - →i `_coinReceive` →X `coin.burnCoin(payer,amount)` (COIN) (2193) [coin-pay path]
  - **→D(nested) `ContractAddresses.GAME_BOON_MODULE.delegatecall(consumePurchaseBoost(buyer))`** (2062) — the nested delegatecall; on failure →i `_revertDelegate` (bubbles)
  - →i `_recordMintPayment` (ETH path) → →i `_processMintPayment` →i `_claimableOf`, `_debitClaimableAndAfking`; writes `claimablePool`; then →i `_getPrizePools/_setPrizePools` or pending
  - →i `_recordMintData` →X `affiliate.affiliateBonusPointsBest(lvl,player)` (AFFILIATE, view) (508)
  - →X `affiliate.payAffiliate(...)` (AFFILIATE) ×up-to-2 (Combined/DirectEth/Claimable affiliate legs) (2126/2136/2146/2158/2169)
- **`_recordMintPayment`** (188) →i `_processMintPayment`, pool getters/setters.
- **`_processMintPayment`** (235) →i `_claimableOf`, `_debitClaimableAndAfking`; writes `claimablePool`; emits `ClaimableSpent`/`AfkingSpent`.
- **`_recordMintData`** (336) →i `_currentMintDay`, `_setMintDay`; →X `affiliate.affiliateBonusPointsBest` (view); writes `mintPacked_`.

### BoonModule nested-delegatecall target (executes in GAME storage)

- **`consumePurchaseBoost(address player) external payable → uint16`** (BoonModule:68)
  - →i `_simulatedDayIndex`, `_purchaseTierToBps`
  - writes `boonPacked[player].slot0` (clears purchase-boost field) · emits `BoonConsumed`
  - **payable** — msg.value kept in flight by delegatecall (no value spend here; pure storage clear).

### Salvage entrypoints (sDGNRS / Vault counterparty)

- **`sellFarFutureTickets(player, levels[], quantities[], queueIndices[]) external`** (1241)
  - →i `_livenessTriggered`, `_activeTicketLevel`, `_farFutureSeed`, `_quoteFarFutureSwap`, `_resolveSalvageBuyer`, `_quoteFarFutureFlipSplit`, `_debitSalvageEth`, `_creditClaimable`, `_removeFarFutureTickets`, `_queueTickets`, `_purchaseFor`
  - →X (in `_resolveSalvageBuyer`): `IDegenerusVaultOwner(VAULT).salvageBuyConfig()` (VAULT, view) (1342)
  - →X (in `_quoteFarFutureFlipSplit`): `coin.balanceOfSpendableForSalvage(buyer)` (COIN, view) (MintStreakUtils:240)
  - →X `coin.burnCoinForSalvage(buyer, flipTokens)` (COIN) (1315)
  - →X `coinflip.creditFlip(player, flipTokens)` (COINFLIP) (1316)
  - →i `_purchaseFor` → (full purchase chain above, Claimable mode; can reach quests/affiliate/coinflip externally)
  - emits `FarFutureSwap`
- **`previewSellFarFutureTickets(...) external view`** (1188) — read-only twin; same quote helpers; →X VAULT view + `coin.balanceOfSpendableForSalvage` view. (view; not column-spine)
- **`_resolveSalvageBuyer`** (1338) →i `_claimableOf`, `_afkingOf`; →X VAULT `salvageBuyConfig()` view.
- **`_debitSalvageEth`** (1360) →i `_claimableOf`, `_debitClaimable`, `_debitClaimableAndAfking`.
- **`_removeFarFutureTickets`** (1378) writes `ticketsOwedPacked`, `ticketQueue` (swap-pop).

---

## 2. REVERT-SITE INVENTORY

`E()` is the shared bare custom error; `RngLocked()` is the RNG-window guard. "PERMANENT-CANDIDATE"
= could wedge the advanceGame ticket-drain spine or gameOver finalization. "TRANSIENT" = only this
caller's tx reverts; another actor/retry still makes progress.

| fn:line | trigger | error | class |
|---|---|---|---|
| `_processMintPayment:250` | `payKind==Claimable && ethForLeg != 0` | `E()` | TRANSIENT (bad caller input) |
| `_processMintPayment:263` | `payKind==Combined && ethForLeg > amount` | `E()` | TRANSIENT |
| `_processMintPayment:281` | unknown payKind enum | `E()` | TRANSIENT |
| `_processMintPayment:297` | checked `claimablePool -= uint128(claimableUsed)+uint128(afkingUsed)` underflow | Panic 0x11 | TRANSIENT (solvency-tracking; underflow would signal accounting bug, not a spine wedge — reverts only the offending mint) |
| `_debitClaimableAndAfking:973/974` (via `_processMintPayment`/`_debitSalvageEth`) | claimable half < amt OR afking half < amt | `E()` | TRANSIENT (insufficient balance → that mint/salvage tx reverts) |
| `_recordMintData:472` | `total+1` — guarded `< type(uint24).max` before unchecked add | (none; guarded) | n/a |
| `processFutureTicketBatch` | — no revert/require in body — | none | n/a (drain-safe; budget-bounded, returns flags) |
| `processTicketBatch` | — no revert/require in body — | none | n/a (drain-safe) |
| `_raritySymbolBatch` | assembly SSTORE loop; `counts[traitId]++`/`touchedTraits[touchedLen++]` bounded ≤256 | none | n/a |
| `_redeemFlipFor:1092` | `_livenessTriggered()` | `E()` | TRANSIENT (FLIP-redemption leg; not the drain) |
| `_redeemFlipFor:1108` | `rngLockedFlag \|\| nextPrizePool < levelPrizePool[level]` (window-not-open) | `E()` | TRANSIENT (by-design: FLIP redemption gated to jackpot window) |
| `_callTicketPurchase:2019` | `quantity == 0` | `E()` | TRANSIENT |
| `_callTicketPurchase:2054` | `costWei == 0` | `E()` | TRANSIENT |
| `_callTicketPurchase:2055` | `costWei < TICKET_MIN_BUYIN_WEI` (0.0025 ETH) | `E()` | TRANSIENT |
| `_callTicketPurchase:2070` | nested BoonModule delegatecall failed → `_revertDelegate(boostData)` | bubbled / `E()` if empty | **PERMANENT-CANDIDATE** (see §5: a BoonModule revert bubbles into every ETH-purchase ticket leg; not on the drain spine, but bricks all mints if the module reverts unconditionally) |
| `_purchaseForWithCached:1503` | `_livenessTriggered()` | `E()` | TRANSIENT (blocks new buys after liveness fires — intended) |
| `_purchaseForWithCached:1506` | `lootBoxAmount != 0 && < LOOTBOX_MIN` (0.01 ETH) | `E()` | TRANSIENT |
| `_purchaseForWithCached:1509` | `totalCost == 0` | `E()` | TRANSIENT |
| `_buyPresaleBoxFor:1908` | `presaleOver` | `E()` | TRANSIENT (by-design terminal latch) |
| `_buyPresaleBoxFor:1909` | `_livenessTriggered()` | `E()` | TRANSIENT |
| `_buyPresaleBoxFor:1912` | `boxAmount < PRESALE_BOX_MIN` | `E()` | TRANSIENT |
| `_buyPresaleBoxFor:1921` | `remaining == 0` (sold out) | `E()` | TRANSIENT |
| `_buyPresaleBoxFor:1929` | `applied > presaleBoxCredit[buyer]` (over-credit) | `E()` | TRANSIENT |
| `_buyPresaleBoxFor:1931` | checked `presaleBoxCredit[buyer] -= applied` (guarded above; unchecked) | (none) | n/a |
| `_buyPresaleBoxFor:1950` | `index == 0` (LR index uninit) | `E()` | TRANSIENT |
| `_buyPresaleBoxFor:1951` | `lootboxRngWordByIndex[index] != 0` (post-entropy) | `E()` | TRANSIENT (RNG-freeze guard) |
| `_buyPresaleBoxFor:1955` | `presaleBoxEth[index][buyer] != 0` (one box per index/player) | `E()` | TRANSIENT |
| `sellFarFutureTickets:1247` | `rngLockedFlag` | `RngLocked()` | TRANSIENT (salvage paused in RNG window — freeze) |
| `sellFarFutureTickets:1248` | `gameOver` | `E()` | TRANSIENT |
| `sellFarFutureTickets:1249` | `_livenessTriggered()` | `E()` | TRANSIENT |
| `sellFarFutureTickets:1251-1256` | bad lengths (`len==0 \|\| >32 \|\| mismatched arrays`) | `E()` | TRANSIENT |
| `sellFarFutureTickets:1267` | `totalBudget < oneTicketWei` (too small) | `E()` | TRANSIENT |
| `sellFarFutureTickets:1277` | `buyer == address(0)` (no funder) | `E()` | TRANSIENT |
| `_removeFarFutureTickets:1387` | `owed < entries` (over-sell / ownership) | `E()` | TRANSIENT |
| `_removeFarFutureTickets:1392` | `q[idx] != player` (stale queue index) | `E()` | TRANSIENT |
| `_quoteFarFutureSwap:190` (MintStreakUtils) | `d < 6 \|\| d > 100` (bad distance, `L<cl` underflows first at :189) | `E()` / Panic 0x11 | TRANSIENT |
| `_quoteFarFutureSwap:192` | `n == 0 \|\| n > type(uint32).max` | `E()` | TRANSIENT |
| `_settleShortfall:906` (storage) | `_afkingOf(buyer) < remaining` (tiers fall short) | `E()` | TRANSIENT |
| `_settleShortfall:900/909` | checked `claimablePool -= uint128(...)` | Panic 0x11 | TRANSIENT |
| `_debitClaimable:944` (storage) | `uint128(balancesPacked[player]) < weiAmount` | `E()` | TRANSIENT |
| `_queueTicketsScaled:650` / `_queueTickets:618` (storage) | `_livenessTriggered()` | `E()` | TRANSIENT (intended block after liveness) |
| `_queueTicketsScaled:653` / `_queueTickets:621` | far-future && `rngLockedFlag` && !bypass | `RngLocked()` | TRANSIENT (freeze; far-future only) |
| `_revertDelegate:1989` | delegatecall reason empty | `E()` | (rethrow helper) |
| `_creditClaimable` / `_creditAfking` / `balancesPacked +=` | checked add overflow (≈impossible: per-player ETH ≪ 2^128) | Panic 0x11 | TRANSIENT (unreachable in practice) |

**Spine-drain observation:** `processTicketBatch` and `processFutureTicketBatch` contain **no
revert/require sites** — the ticket-drain path the advanceGame chain depends on cannot revert from
within this slice (work is write-budget-bounded and returns flags). The only arithmetic in the
drain is `unchecked` LCG/index math and assembly SSTORE. This is the strongest liveness property of
the slice: the column's mint drain through this module is revert-free.

---

## 3. LOOP INVENTORY

| fn:line | count bound | per-iter storage/gas | class |
|---|---|---|---|
| `processFutureTicketBatch:586` (`while idx<total && used<writesBudget`) | min(queue length, write-budget consumption) | per queue entry: 1 `owedMap` SLOAD, conditional `owedMap` SSTORE, calls `_raritySymbolBatch` (SSTOREs to `traitBurnTicket`) | **BOUNDED** by `writesBudget` (`WRITES_BUDGET_SAFE=550`, ×0.65 on first batch). Each entry charges ≥1 budget unit (skip) so a sparse queue cannot run unbounded; mid-queue stop persists `ticketCursor`. |
| `processTicketBatch:878` (`while idx<total && used<writesBudget`) | same | →i `_processOneTicketEntry` per entry (SLOAD+conditional SSTORE+`_raritySymbolBatch`) | **BOUNDED** by `writesBudget`; resumable via `ticketCursor`. |
| `_raritySymbolBatch:737` (`while i<endIndex`) | `count` (= `take`, capped by remaining write budget per entry, ≤ owed) | groups of 16; keccak per group; `counts[]`/`touchedTraits[]` memory writes | **BOUNDED** — `count`=`take` is write-budget-derived (room/2 or room-256), never input-sized at call. |
| `_raritySymbolBatch:753` (inner `for j=offset; j<16`) | ≤16 per group | memory `counts[traitId]++`, `touchedTraits[]` | **BOUNDED** (≤16). |
| `_raritySymbolBatch:788` (`for u<touchedLen`) | `touchedLen` ≤ 256 (distinct trait ids) | assembly: per traitId 1 SLOAD len + SSTORE len + `occurrences`× SSTORE player into `traitBurnTicket` data slots | **BOUNDED** ≤256 outer; inner SSTORE count = `occurrences` (≤ `count`, budget-bounded). |
| `_raritySymbolBatch:805` (assembly inner `for k<occurrences`) | `occurrences` for that trait | 1 SSTORE per occurrence (player addr appended to `traitBurnTicket[lvl][traitId]`) | **BOUNDED** — Σ occurrences = `count` ≤ write budget. |
| `sellFarFutureTickets:1293` (`for i<len`) | `len` ≤ 32 (checked at :1253) | →i `_removeFarFutureTickets` (SLOAD/SSTORE+swap-pop), `_queueTickets` (SSTORE) | **BOUNDED** ≤32 (input-sized but hard-capped). |
| `_quoteFarFutureSwap:187` (MintStreakUtils, `for i<len`) | `len` = `levels.length` (≤32 enforced by caller `sellFarFutureTickets`; preview caps at calldata size) | pure arithmetic + `priceForLevel` (pure) | **BOUNDED** in exec (≤32). Preview view is INPUT-SIZED but view-only (no spine impact). |

**No UNBOUNDED loop reaches the advanceGame drain.** All spine loops are write-budget-bounded and
checkpoint-resumable (`ticketCursor`/`ticketLevel`). The only input-sized loops are the salvage path
(hard-capped ≤32) and the preview view (read-only).

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (this module writes GAME slots)

Variables named as declared in `DegenerusGameStorage` / module. Packed-slot writes flagged.

### Ticket queue / drain state
- **`ticketCursor`** (uint32, slot ~500) — written `processTicketBatch` (853,908,915), `processFutureTicketBatch` (555,561,568,687,690,694,701).
- **`ticketLevel`** (uint24) — written same fns (incl. `lvl | TICKET_FAR_FUTURE_BIT` at 686).
- **`ticketQueue[rk]`** (`mapping(uint24 => address[])`) — `push` in `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange`; `delete`/swap-pop in `processTicketBatch`/`processFutureTicketBatch`/`_removeFarFutureTickets`. **Keyed by ticket-queue key (level | slot/far-future bit).**
- **`ticketsOwedPacked[rk][player]`** (`mapping(uint24 => mapping(address => uint40))`) — **PACKED** uint40 = `owed(32)<<8 | rem(8)`. Written in batch processors (599,620,663,1020,1396,1398) and `_queueTickets*`. **Keyed by (rk, player); rk packs level + slot/far-future bit.**
- **`traitBurnTicket[lvl][traitId]`** (`mapping(uint24 => address[][256])`) — assembly bulk append in `_raritySymbolBatch` (799 len SSTORE, 810 element SSTOREs). **Keyed by level + traitId (offset 0-255).**

### Mint history / activity score
- **`mintPacked_[player]`** (`mapping(address => uint256)`) — **PACKED** multi-field word (lastLevel/levelCount/levelStreak/lastMintDay/unitsLevel/frozenUntilLevel/whaleBundleType/mintStreakLast/hasDeityPass/affBonusLevel/affBonusPoints/levelUnits/curseCount). Written:
  - `_recordMintData` (399,434,528) — units, level-count, level, day, frozen-flag clear, whale-bundle-type clear, affiliate bonus cache. **Packed, keyed by player; sub-fields keyed by level (FROZEN_UNTIL_LEVEL, AFFILIATE_BONUS_LEVEL) and day (DAY_SHIFT).**
  - `_recordMintStreakForLevel` (MintStreakUtils:113) — LEVEL_STREAK + MINT_STREAK_LAST_COMPLETED fields. **Packed, keyed by player; field keyed by mintLevel.**
  - `_applyCurseStack` (MintStreakUtils:409) / `_clearCurse` (MintStreakUtils:422) — CURSE_COUNT field. **Packed.** (`_clearCurse` reached from purchase; `_applyCurseStack` not reached from this slice's purchase path.)
  - `_recordLootboxMintDay` (MintStreakUtils:444) — DAY_SHIFT field. **Packed, keyed by day.**

### Balances / solvency
- **`balancesPacked[player]`** (`mapping(address => uint256)`) — **PACKED** claimable(low 128) + afking(high 128). Written via `_creditClaimable`/`_debitClaimable`/`_creditAfking`/`_debitAfking`/`_debitClaimableAndAfking`/`_creditAfkingValue` — reached from `_processMintPayment`, `_settleShortfall`, `_purchaseFor` (overpay→afking), `_buyPresaleBoxFor`, salvage `_debitSalvageEth`/`_creditClaimable`/`_creditBoxProceeds`. **PACKED HALVES (offset: low=claimable, high=afking).**
- **`claimablePool`** (uint128, slot-0 packed region [16:32]) — RMW in `_processMintPayment:297`, `_settleShortfall:900/909`, `_creditAfkingValue:989`, `_creditBoxProceeds:22`. **PACKED into slot 0.**

### Prize pools
- **`prizePoolsPacked`** (uint256) — **PACKED** next(low128)+future(high128); `_setPrizePools` from `_recordMintPayment` + lootbox split (`_purchaseForWithCached`).
- **`prizePoolPendingPacked`** (uint256) — **PACKED** next+future; `_setPendingPools` (frozen-pool branch of the same writes).

### Lootbox / presale state
- **`lootboxEth[lbIndex][buyer]`** (`mapping(uint48=>mapping(address=>uint256))`) — **PACKED** amount(128)+adj(64)+score(16)+distressUnits(48); written `_purchaseForWithCached:1801` (`_packLootbox`). **Keyed by (lbIndex, buyer).**
- **`lootboxRngPacked`** (uint256) — **PACKED** index/pendingEth/threshold/pendingFlip/midDay; RMW of LR_PENDING_ETH field in `_purchaseForWithCached:1611`. **PACKED, field = pending-ETH (milli-ETH).**
- **`presaleStatePacked`** (uint256) — **PACKED** active(8)+mintEth(128); RMW of PS_MINT_ETH + conditional clear of PS_ACTIVE in `_purchaseForWithCached:1623`. **PACKED.**
- **`lootboxEvCapPacked[player]`** (uint256) — **PACKED** two level-stamped windows (used64+level24 ×2); `_setLootboxEvUsedFor` from `_purchaseForWithCached:1774/1795`. **PACKED, keyed by level (window stamp = cachedLevel+1).**
- **`centuryBonusUsed[player]`** (uint256) — **PACKED** (level<<224 | used); `_setCenturyUsedFor` from `_purchaseForWithCached:1722`. **PACKED, keyed by century targetLevel.**
- **`presaleBoxCredit[buyer]`** (`mapping(address=>uint256)`) — `+= (ticketCost+lootBoxAmount)/4` (`_purchaseForWithCached:1809`); `-= applied` (`_buyPresaleBoxFor:1931`).
- **`presaleBoxEth[index][buyer]`** (`mapping(uint48=>mapping(address=>uint256))`) — **PACKED** closing(bit255)+sold(96)+applied(96); `_buyPresaleBoxFor:1960`. **Keyed by (index, buyer).**
- **`presaleBoxEthSold`** (uint96) — `_buyPresaleBoxFor:1967`.
- **`boxPlayers[index]`** (`mapping(uint48=>address[])`) — `push` in `_purchaseForWithCached:1600` (lootbox first-deposit) and `_buyPresaleBoxFor:1965`. **Keyed by index.**

### Slot-0 packed booleans (each write is a slot-0 RMW; aliasing-relevant)
- **`ticketRedemptionOpen`** (bool, slot0 [30:31]) — set true `_redeemFlipFor:1109`. **PACKED slot-0.**
- **`presaleOver`** (bool, slot0 [27:28]) — set true `_buyPresaleBoxFor:1971`. **PACKED slot-0.**
- **`presaleCloseIndex`** (uint48) — `_buyPresaleBoxFor:1975`.
- (`prizePoolFrozen` [26:32], `ticketWriteSlot` [25:26] are READ here, not written by this slice.)

### BoonModule (nested delegatecall target — writes GAME slots)
- **`boonPacked[player].slot0`** — `consumePurchaseBoost` clears the purchase-boost field (BoonModule:78,83,87). **PACKED slot0 of the BoonPacked struct, keyed by player.**
- **`boonPacked[player].slot0`** — `_applyLootboxBoostOnPurchase` (this module, 2233,2242,2251) clears lootbox fields (this is a normal internal call, NOT the nested delegatecall). **PACKED.**

---

## 5. HUNT-RELEVANT NOTES (418–423)

- **The drain spine is revert-free.** `processTicketBatch` / `processFutureTicketBatch` (and the
  `_raritySymbolBatch` they drive) contain zero revert/require sites; all loops are
  write-budget-bounded and `ticketCursor`-resumable. The advanceGame ticket drain through MintModule
  cannot wedge from inside this slice. Worth confirming the callers always pass a valid `entropy`
  (future) / read `lootboxRngWordByIndex[index-1]` non-zero (current) so traits don't degenerate —
  but that's an entropy-quality, not a liveness, concern.

- **Nested delegatecall into BoonModule** (`_callTicketPurchase:2062`,
  `GAME_BOON_MODULE.consumePurchaseBoost`, **payable**, msg.value-in-flight): on failure
  `_revertDelegate` bubbles the reason into EVERY ETH-purchase ticket leg. `consumePurchaseBoost`
  itself only reads `boonPacked.slot0` + day and clears a field — no value spend, no external call,
  no revert site of its own — so it is non-bricking under the frozen code. The risk surface is
  (a) the nested target executes in GAME storage and writes `boonPacked` (storage-aliasing must be
  correct), and (b) any future BoonModule change that adds an unconditional revert would brick all
  ETH mints. Not on the drain spine.

- **Packed slot-0 RMW hotspots** (aliasing-relevant): `claimablePool` [16:32], `ticketRedemptionOpen`
  [30:31], `presaleOver` [27:28] all live in slot 0; this slice RMWs claimablePool on every paid
  mint and flips the two booleans on their latch events. Any concurrent slot-0 writer
  (`ticketWriteSlot`, `prizePoolFrozen`, `level`, `gameOver` if co-located) must be checked for
  read-modify-write interleaving — but within a single delegatecall frame these are sequential.

- **`mintPacked_` is the most multiply-written packed word** — written by `_recordMintData`,
  `_recordMintStreakForLevel`, `_clearCurse`, `_recordLootboxMintDay` within one purchase, each a
  full-word load+masked-merge+store. Field keys: FROZEN_UNTIL_LEVEL / AFFILIATE_BONUS_LEVEL (level),
  DAY_SHIFT (day), LEVEL_STREAK/MINT_STREAK_LAST_COMPLETED (mintLevel), CURSE_COUNT. A stale read
  between two of these in-frame writes would corrupt activity score; they are sequential, but the
  ordering (`_recordMintData` runs before `_recordMintStreakForLevel`/`_clearCurse` in the purchase
  body) is load-bearing for the cached-score read at :1710.

- **Salvage path reaches sDGNRS/Vault/COIN/COINFLIP synchronously** (`sellFarFutureTickets`):
  `coin.burnCoinForSalvage` + `coinflip.creditFlip` + VAULT `salvageBuyConfig` view +
  `coin.balanceOfSpendableForSalvage` view. A revert in any of these callees bubbles up and reverts
  the salvage tx (TRANSIENT — not the spine). It then calls `_purchaseFor` which can reach
  `quests.handlePurchase` / `affiliate.payAffiliate` / `coinflip.creditFlip` — so a salvage tx
  transitively depends on QUESTS/AFFILIATE/COINFLIP liveness too. None of this is on the advance
  drain.

- **`buyLootboxAndPresaleBox` splits one `msg.value`** across the mint leg
  (`_purchaseForWithCached`, fresh = min(msg.value, mintCost)) and the box leg
  (`_buyPresaleBoxFor`, valueForBox = msg.value - mintFresh). The mint leg's nested BoonModule
  delegatecall keeps the FULL outer msg.value in flight (delegatecall preserves callvalue), but the
  accounting binds to the explicit `fresh`/`ethForLeg` params, never `msg.value`, inside the legs —
  the msg.value-in-flight only matters for the payable signature, not for funds routing. Overpay is
  routed to afking (`_creditAfkingValue`), never reverted/stranded.

- **`processTicketBatch` reads entropy from `lootboxRngWordByIndex[index-1]`** (840) — uses the
  prior committed index's word (RNG-freeze: current index word is uncommitted). If `index==0` this
  underflows the `uint48(...) - 1` (Panic) — but `index` (LR_INDEX) is initialized to 1 and only
  increments, so unreachable. Worth a sanity check that no path can leave LR_INDEX at 0 when a
  current-level ticket queue is non-empty.
