# Column Map — Slice: WhaleModule

Subject: frozen `contracts/` tree `0dd445a6`.
File: `contracts/modules/DegenerusGameWhaleModule.sol` (inherits `DegenerusGameMintStreakUtils` → `DegenerusGameStorage`).

## Dispatch context

`DegenerusGameWhaleModule` runs **via DELEGATECALL** from `DegenerusGame` in the GAME's storage. The four public entrypoints are reached by ONE (non-nested) delegatecall each from `DegenerusGame`:

| Game wrapper (DegenerusGame.sol) | delegatecall → module fn |
|---|---|
| `purchaseWhaleBundle` :712-723 → `GAME_WHALE_MODULE.delegatecall(IDegenerusGameWhaleModule.purchaseWhaleBundle.selector,…)` | `purchaseWhaleBundle` :168 |
| `purchaseLazyPass` :734-744 | `purchaseLazyPass` :388 |
| `purchaseDeityPass` :754-765 | `purchaseDeityPass` :539 |
| `claimWhalePass` :1508-… | `claimWhalePass` :991 |

`buyer = _resolvePlayer(buyer)` resolves in the Game wrapper BEFORE delegatecall. `msg.sender` / `msg.value` are preserved (a single delegatecall, NOT nested). On a module revert the Game wrapper bubbles it via `_revertDelegate(data)` — i.e. **any revert inside this slice propagates to the caller's tx**. This slice is purchase-initiated; it is NOT itself part of the `advanceGame` tick chain (no entrypoint here is called from `advanceGame`).

`_revertDelegate` (Game) on `ok == false` re-raises the module's returndata — so a callee external-call revert inside this slice bricks the calling purchase tx, but it CANNOT wedge `advanceGame` (these fns are not in the advance chain). The relevant liveness concern is the opposite: shared helpers in this slice (`_queueTicketRange`, `_queueTickets`) carry the `_livenessTriggered()` revert that IS load-bearing for the broader column.

---

## 1. CALL GRAPH (column-reachable functions in this slice)

Legend: [INT]=internal/private call · [EXT]=synchronous external call to FLIP/Coinflip/Vault/sDGNRS/Affiliate/DeityPass/Quests · [LIB]=pure library. No NESTED delegatecall and no raw `delegatecall(msg.data)` anywhere in this slice.

### `purchaseWhaleBundle` :168 → `_purchaseWhaleBundle` :175
- [INT] `_livenessTriggered` :176 (base :1464) — view; reads `lastPurchaseDay,jackpotPhaseFlag,level,purchaseStartDay,rngRequestTime`; calls [INT]`_simulatedDayIndex`→`GameTimeLib.currentDayIndex()` (pure-ish time lib, no external contract).
- [INT] `_simulatedDayIndex` :187 (boon-validity day).
- [INT] `_whaleTierToBps` :229 [LIB-like pure base helper].
- [INT] `_creditAfkingValue` :249 (base :986) — writes `balancesPacked`, `claimablePool`.
- [INT] `_settleShortfall` :250 (base :888) — reads/writes `balancesPacked`, `claimablePool`; may [INT]`_debitClaimable`/`_debitAfking`; **revert E()** if afking can't cover.
- [LIB] `BitPackingLib.setPacked` ×4 :260-283.
- [INT] `_currentMintDay` :286 (base :1481).
- [INT] `_setMintDay` :287 (base :1490) [pure].
- [INT] `_withPassStreakFrontLoad` :295 (base :1216) [pure].
- [INT] `_queueTicketRange` :313, :321 (base :695) — **revert E()** via `_livenessTriggered`; **revert RngLocked()** on far-future during lock; loop over `numLevels`; writes `ticketQueue`, `ticketsOwedPacked`.
- [EXT] `affiliate.getReferrer(buyer)` :329 — Affiliate. (×up to 3: :329,:333,:335)
- [INT] `_rewardWhaleBundleDgnrs` :340 (in a `for i < quantity` loop) — see below; makes sDGNRS [EXT] calls.
- [INT] `_getPendingPools`/`_setPendingPools` :356-359 OR `_getPrizePools`/`_setPrizePools` :362-366 — writes `prizePoolPendingPacked` or `prizePoolsPacked`.
- [INT] `_recordLootboxEntry` :371 — see below.

### `_rewardWhaleBundleDgnrs` :708
- [EXT] `dgnrs.poolBalance(Pool.Whale)` :714 — sDGNRS.
- [EXT] `dgnrs.transferFromPool(Pool.Whale, buyer, minterShare)` :721 — sDGNRS.
- [EXT] `dgnrs.poolBalance(Pool.Affiliate)` :729 — sDGNRS.
- [INT] `_getLevelDgnrs(level)` :735 (base :1156) — reads `levelDgnrsPacked`.
- [EXT] `dgnrs.transferFromPool(Pool.Affiliate, affiliateAddr/upline/upline2, …)` :745,:756,:764 — sDGNRS (×up to 3).

### `purchaseLazyPass` :388 → `_purchaseLazyPass` :392
- [INT] `_livenessTriggered` :393.
- [INT] `_lazyPassTierToBps` :399 [pure base].
- [INT] `_simulatedDayIndex` :402 (boon validity); writes `boonPacked[buyer].slot1` on expiry :405,:411.
- [INT] `_lazyPassCost` :440 (this file :692) — **loop** 10 iters; [LIB]`PriceLookupLib.priceForLevel` ×10.
- [LIB] `PriceLookupLib.priceForLevel` :454 (bonus-ticket sizing).
- [INT] `_creditAfkingValue` :478; `_settleShortfall` :479 (**revert E()** possible).
- [INT] `_activate10LevelPass` :485 (base :1261) — writes `mintPacked_`; calls [INT]`_currentMintDay`,`_setMintDay`,`_withPassStreakFrontLoad`,`_queueTicketRange` (loop 10, **revert E()/RngLocked()**).
- [INT] `_queueTickets` :489 (base :608) — **revert E()** via `_livenessTriggered`; **revert RngLocked()**; writes `ticketQueue`,`ticketsOwedPacked`.
- [INT] `_getPendingPools/_setPendingPools` or `_getPrizePools/_setPrizePools` :498-509.
- [INT] `_recordLootboxEntry` :514.

### `purchaseDeityPass` :539 → `_purchaseDeityPass` :543
- **revert RngLocked()** :544 if `rngLockedFlag`.
- [INT] `_livenessTriggered` :545.
- [INT] `_simulatedDayIndex` :566,:571 (boon expiry); writes `boonPacked[buyer].slot1` :581.
- [INT] `_creditAfkingValue` :585; `_settleShortfall` :586 (**revert E()** possible).
- writes `deityPassPricePaid`,`presaleBoxCredit`,`mintPacked_`,`deityPassOwners`,`deityBySymbol`.
- [EXT] `IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId)` :608 — DeityPass ERC721 (external mint; **bubbles on revert**).
- [EXT] `affiliate.getReferrer` :614,:617,:619 — Affiliate (×up to 3).
- [INT] `_rewardDeityPassDgnrs` :623 — sDGNRS [EXT] (poolBalance ×2 + transferFromPool ×up to 4); `_getLevelDgnrs`.
- [INT] `_queueTicketRange` :636,:644 (affiliateAddr; loop, **revert E()/RngLocked()**).
- [INT] `_applyWhalePassStats` :651 (base :1354) — writes `mintPacked_`; calls `_currentMintDay`,`_setMintDay`,`_withPassStreakFrontLoad` (NO ticket queue, NO loop, NO external call).
- [INT] pools set :661-673.
- [INT] `_recordLootboxEntry` :677.
- emits `DeityPassPurchased` :683.

### `_rewardDeityPassDgnrs` :777
- [EXT] `dgnrs.poolBalance(Pool.Whale)` :783; `dgnrs.transferFromPool(Pool.Whale, buyer, totalReward)` :790 — sDGNRS.
- [EXT] `dgnrs.poolBalance(Pool.Affiliate)` :798.
- [INT] `_getLevelDgnrs(level)` :804.
- [EXT] `dgnrs.transferFromPool(Pool.Affiliate, …)` :814,:825,:833 — sDGNRS (×up to 3).

### `_recordLootboxEntry` :841 (shared by all three purchase paths)
- reads `lootboxRngPacked` :850; `level` :852.
- [INT] `_recordLootboxMintDay` :854 (base :434) — writes `mintPacked_` (DAY_SHIFT) when day changed.
- reads `lootboxEth[index][buyer]` :856.
- [INT] `_playerActivityScore(buyer, _effectiveQuestStreak(buyer))` :867 (base :380 view) — reads `mintPacked_`; **[EXT]`affiliate.affiliateBonusPointsBest`** :345 (only when affiliate cache stale).
- [INT] `_effectiveQuestStreak(buyer)` :867 (base :2300) — **[EXT]`quests.effectiveBaseStreakAndAfking(player)`** :2305 — Quests; may [INT]`_liveAfkingStreak`→`_afkingStreak` (reads `_subOf`).
- [INT] `_lootboxEvMultiplierFromScore` :872,:895 [pure].
- [INT] `_lootboxEvUsedFor` :874,:897 (base :1714) — reads `lootboxEvCapPacked`.
- [INT] `_setLootboxEvUsedFor` :879,:903 (base :1728) — writes `lootboxEvCapPacked`.
- [INT] `_unpackLootbox` :892 [pure].
- writes `boxPlayers[index]` (push) :888 (first deposit only).
- [INT] `_applyLootboxBoostOnPurchase` :912 — see below.
- [INT] `_isDistressMode` :923 (base :591) — reads `gameOver,purchaseStartDay,level`; [INT]`_simulatedDayIndex`.
- [INT] `_packEthToMilliEth` :915 [pure].
- writes `lootboxRngPacked` :916 (LR_PENDING_ETH field).
- [INT] `_packLootbox` :927 [pure]; writes `lootboxEth[index][buyer]` :927.
- emits `LootBoxBuy` :931.

### `_applyLootboxBoostOnPurchase` :941
- reads `boonPacked[player].slot0`.
- [INT] `_simulatedDayIndex` :952.
- [INT] `_lootboxTierToBps` :970 [pure].
- writes `boonPacked[player].slot0` :956,:965,:978 (BP_LOOTBOX_CLEAR — consume/expire).
- emits `LootBoxBoostConsumed` :980.

### `claimWhalePass` :991
- [INT] `_livenessTriggered` :992 (**revert E()**).
- reads/writes `whalePassClaims[player]` :993,:997.
- [INT] `_applyWhalePassStats` :1005 (writes `mintPacked_`).
- emits `WhalePassClaimed` :1006.
- [INT] `_queueTicketRange(player, startLevel, 100, …)` :1007 (loop 100, **revert E()/RngLocked()**).

**External-call surface of this slice (all synchronous, all under the single delegatecall):** Affiliate (`getReferrer`, `affiliateBonusPointsBest`), sDGNRS (`poolBalance`, `transferFromPool`), Quests (`effectiveBaseStreakAndAfking`), DeityPass (`mint`), Coin/FLIP — NONE here (the `coin.balanceOfSpendableForSalvage` external is in the base salvage path, NOT reached by any WhaleModule entrypoint). `IDegenerusVaultOwner.isVaultOwner` (Vault) is only in `_bountyEligible`, NOT reached by this slice.

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | T/P |
|---|---|---|---|
| `_purchaseWhaleBundle`:176 | `_livenessTriggered()` true | `E()` | TRANSIENT — purchase-side only; once liveness fires the game routes to game-over drain. Cannot wedge advance. |
| `_purchaseWhaleBundle`:179 | `quantity==0 \|\| quantity>100` | `E()` | TRANSIENT (input). |
| `_purchaseWhaleBundle`:240 | x99 century (`passLevel%100==0`) & `quantity<2` | `E()` | TRANSIENT (input). |
| `_purchaseLazyPass`:393 | `_livenessTriggered()` | `E()` | TRANSIENT. |
| `_purchaseLazyPass`:425 | level not eligible & no boon | `E()` | TRANSIENT (input/timing). |
| `_purchaseLazyPass`:431 | buyer has deity pass bit | `E()` | TRANSIENT (input). |
| `_purchaseLazyPass`:437 | `frozenUntilLevel > currentLevel+7` (active pass) | `E()` | TRANSIENT (input). |
| `_purchaseDeityPass`:544 | `rngLockedFlag` set | `RngLocked()` | TRANSIENT — clears each daily cycle; purchase-side gate. |
| `_purchaseDeityPass`:545 | `_livenessTriggered()` | `E()` | TRANSIENT. |
| `_purchaseDeityPass`:546 | `symbolId>=32` | `E()` | TRANSIENT (input). |
| `_purchaseDeityPass`:547 | `deityBySymbol[symbolId]!=0` (taken) | `E()` | TRANSIENT (input). |
| `_purchaseDeityPass`:551 | buyer already has deity pass | `E()` | TRANSIENT (input). |
| `_settleShortfall`:906 (base) | afking < remaining shortfall | `E()` | TRANSIENT — buyer underpaid; reachable from all 3 purchase paths (:250,:479,:586). |
| `_debitClaimable`:944 (base) | claimable < amount | `E()` | TRANSIENT — reached via `_settleShortfall`. |
| `_queueTickets`:618 / `_queueTicketsScaled`:650 / `_queueTicketRange`:703 (base) | `_livenessTriggered()` | `E()` | **PERMANENT-CANDIDATE for the BROADER column** — these helpers are shared with advance/mint paths and gate ALL queuing on liveness; if liveness flips on while a column path still needs to queue, those paths revert. WITHIN this slice it is transient (purchase only). |
| `_queueTickets`:621 / `_queueTicketsScaled`:653 / `_queueTicketRange`:715 (base) | far-future target & `rngLockedFlag` & !bypass | `RngLocked()` | TRANSIENT — far-future writes blocked during VRF commit window; clears each cycle. |
| `dgnrs.poolBalance` / `dgnrs.transferFromPool` (sDGNRS) :714-833 | callee reverts (e.g. insufficient pool, paused) | bubbles via `_revertDelegate` | **callee-revert risk** — would brick the calling purchase tx; NOT in advance chain so cannot wedge `advanceGame`. |
| `IDegenerusDeityPassMint.mint` :608 (DeityPass) | callee mint reverts | bubbles | callee-revert risk — bricks the deity purchase tx only; symbol not yet recorded so retriable after callee recovers. |
| `affiliate.getReferrer` / `affiliate.affiliateBonusPointsBest` (Affiliate) | callee reverts | bubbles | callee-revert risk — purchase-tx only. |
| `quests.effectiveBaseStreakAndAfking` :2305 (Quests) | callee reverts | bubbles | callee-revert risk — reached via `_recordLootboxEntry` → `_effectiveQuestStreak`; purchase-tx only. |
| checked-arith `uint128(...)` casts at pool writes :356-366,:499-509,:661-672 | a `uint128(next/future + share)` truncation (NOT a revert — silent narrowing) | n/a | NOTE: explicit `uint128(...)` casts truncate rather than revert; bounded by total-ETH-supply ≪ 2^128 per the storage invariant. Not a revert site. |
| checked-arith `_currentMintDay`/day fields | none reachable (all masked/`unchecked`) | — | — |
| `_livenessTriggered`:1469-1470 (base) | `currentDay - psd` underflow if `currentDay < psd` | panic 0x11 | TRANSIENT — `purchaseStartDay` is set to a past day at deploy/level-start, so `currentDay >= psd` holds; would only trip on a clock regression. Reachable from every entrypoint's liveness guard. |

No `revert` site in this slice can wedge `advanceGame` or `gameOver` finalization: none of the four entrypoints is in the advance/gameOver chain. The only column-load-bearing reverts touched here are the SHARED base `_queueTicket*` liveness/RngLock guards, flagged as a candidate because they are reused by advance-side queuing.

---

## 3. LOOP INVENTORY

| fn:line | iteration-count bound | per-iter storage/gas | BOUNDED? |
|---|---|---|---|
| `_purchaseWhaleBundle`:339 `for i < quantity` | `quantity` ∈ [1,100] (input, capped at :179) | each iter calls `_rewardWhaleBundleDgnrs` → up to 2 `dgnrs.poolBalance` + up to 4 `dgnrs.transferFromPool` EXTERNAL sDGNRS calls + `_getLevelDgnrs` SLOAD | **BOUNDED** (≤100) but **EXTERNAL-CALL-HEAVY** — ≤100×(≤6 sDGNRS calls). Input-sized within a hard 100 cap. Gas-relevant: worst case ~600 cross-contract calls in one tx. |
| `_purchaseWhaleBundle`:313 `_queueTicketRange(bonusCount)` | `bonusCount` = `WHALE_BONUS_END_LEVEL - passLevel + 1` ≤ 10 (0 when passLevel>10) | per-iter: `ticketsOwedPacked` SLOAD+SSTORE, conditional `ticketQueue.push` | BOUNDED (≤10). |
| `_purchaseWhaleBundle`:321 `_queueTicketRange(100 - bonusCount)` | `100 - bonusCount` ∈ [90,100] | same | BOUNDED (≤100). |
| `_purchaseLazyPass`:485 `_activate10LevelPass`→`_queueTicketRange(…,10,…)` :1348 | fixed 10 | ticketsOwedPacked SLOAD+SSTORE + cond push | BOUNDED (10). |
| `_purchaseLazyPass`:489 `_queueTickets` | single call (no loop) | one ticketsOwedPacked RMW | BOUNDED (1). |
| `_lazyPassCost`:695 `for i < LAZY_PASS_LEVELS` | fixed 10 | pure `PriceLookupLib.priceForLevel` (no SLOAD) | BOUNDED (10). |
| `_purchaseDeityPass`:636 `_queueTicketRange(bonusCount)` | `bonusCount` ≤ 10 | as above | BOUNDED (≤10). |
| `_purchaseDeityPass`:644 `_queueTicketRange(100 - bonusCount)` | ∈ [90,100] | as above | BOUNDED (≤100). |
| `claimWhalePass`:1007 `_queueTicketRange(…,100,…)` | fixed 100 | ticketsOwedPacked RMW + cond push per level | BOUNDED (100). |
| `_queueTicketRange`:713 (base, the actual loop body) | `numLevels` (caller-passed: 10, ≤10, 90-100, or 100) | `ticketsOwedPacked[wk][buyer]` SLOAD+SSTORE; `ticketQueue[wk].push` on first | BOUNDED — every caller in this slice passes a constant ≤100. |

No UNBOUNDED / unbounded-input-sized loop in this slice. The only input-sized loop is the whale-bundle `quantity` loop, hard-capped at 100; its concern is the **multiplicative external-call count** (≤100 × ≤6 sDGNRS calls), not unbounded growth.

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game-storage fields written under delegatecall)

All writes land in `DegenerusGame`'s storage (module has no own storage). Packed-slot writes flagged.

### Slot-0 packed fields (one 32-byte slot) — written here:
- `presaleOver` — NOT written here (read only at :252,:481,:594).
- `prizePoolFrozen` — read only here (branch selector at :355,:498,:661).
- (no slot-0 boolean is *written* by this slice.)

### Packed-word writes (PACKED HOTSPOTS):
- **`mintPacked_[buyer/player/affiliateAddr]`** — packed per-player word; written via:
  - `_purchaseWhaleBundle`:302 (LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE=3, LAST_LEVEL, DAY, MINT_STREAK_LAST_COMPLETED+LEVEL_STREAK).
  - `_activate10LevelPass`:1346 (LEVEL_COUNT, FROZEN_UNTIL_LEVEL, WHALE_BUNDLE_TYPE→1, LAST_LEVEL, DAY, streak).
  - `_applyWhalePassStats`:1425 (same fields, bundleType=3) — keyed to **affiliateAddr** in the deity path.
  - `_purchaseDeityPass`:598 (HAS_DEITY_PASS bit set).
  - `_recordLootboxMintDay`:444 (DAY_SHIFT only).
  - PACKED-OFFSET keyed: all fields are sub-word offsets within one player word; multiple writers (deity bit vs streak vs day) touch the SAME word — aliasing-relevant. In the deity path the affiliate's `mintPacked_` is written by `_applyWhalePassStats` while the buyer's is written by the deity-bit set — distinct keys.
- **`boonPacked[buyer].slot0`** — `_purchaseWhaleBundle`:233 (BP_WHALE_CLEAR consume); `_applyLootboxBoostOnPurchase`:956,:965,:978 (BP_LOOTBOX_CLEAR). PACKED by boon-category offset.
- **`boonPacked[buyer].slot1`** — `_purchaseLazyPass`:405,:411,:474 (BP_LAZY_PASS_CLEAR); `_purchaseDeityPass`:581 (BP_DEITY_PASS_CLEAR). PACKED by boon-category offset.
- **`balancesPacked[*]`** (afking high128 / claimable low128) — via `_creditAfkingValue`:249,:478,:585 (`_creditAfking` adds `<<128`) and `_settleShortfall` (`_debitClaimable`/`_debitAfking`). PACKED by claimable|afking halves; keyed per `msg.sender` (afking credit) AND per `buyer` (shortfall debit) — two different keys can touch the same word if msg.sender==buyer.
- **`claimablePool`** (uint128, packed in slot-1 with `currentPrizePool`) — `_creditAfkingValue` `+=`, `_settleShortfall` `-=` (paired with each balance debit). PACKED slot-1 hotspot.
- **`prizePoolsPacked`** (next|future uint128|uint128) — `_setPrizePools` at :363,:505,:669. PACKED by next/future halves.
- **`prizePoolPendingPacked`** (next|future) — `_setPendingPools` at :357,:500,:663 (frozen branch). PACKED by next/future halves.
- **`lootboxRngPacked`** — `_recordLootboxEntry`:916 (LR_PENDING_ETH field only, masked write). PACKED by LR field offset (index/pendingEth/threshold/pendingFlip/midDay share this slot).
- **`lootboxEth[index][buyer]`** — `_recordLootboxEntry`:927 (`_packLootbox`: amount|adj|score|distress). PACKED by lootbox-field offset; keyed (uint48 index, address buyer).
- **`lootboxEvCapPacked[buyer]`** — `_setLootboxEvUsedFor`:879,:903 (window A/B used+level). PACKED by EV-window offset, **keyed by level** (window A vs B selected by level stamp — aliasing-relevant: eviction of the smaller-level window).

### Full-slot / array / mapping writes:
- **`ticketQueue[wk]`** (`.push(buyer)` first deposit) — base `_queueTickets`:629 / `_queueTicketsScaled`:661 / `_queueTicketRange`:721. Key `wk` = level | writeSlotBit | farFutureBit (double-buffer / far-future keyspace) — **keyed by level+slot-bit**.
- **`ticketsOwedPacked[wk][buyer]`** — base queue helpers; `[32 owed | 8 rem]` packed. Keyed (wk, buyer).
- **`presaleBoxCredit[buyer]`** `+=` — :253,:482,:595 (presale-open branch). Keyed by buyer.
- **`deityPassPricePaid[buyer]`** `= uint96(totalPrice)` — :592. Keyed by buyer.
- **`deityPassOwners`** (`.push(buyer)`) — :604.
- **`deityBySymbol[symbolId]`** `= buyer` — :605. Keyed by symbolId.
- **`whalePassClaims[player]`** `= 0` — `claimWhalePass`:997. Keyed by player.
  - (NOTE: `whalePassClaims` is the read/cleared deferred-claim mapping; it is READ at :993 and zeroed at :997. Its writer-side population lives outside this slice.)

PACKED-WRITE HOTSPOTS keyed by offset/level/day (aliasing-relevant for phases 418-425):
1. `mintPacked_[player]` — multiple sub-word writers (streak/day/bundleType/deity-bit/freeze) on ONE word; deity path writes buyer (deity bit) AND affiliate (whale stats) separately.
2. `lootboxEvCapPacked[buyer]` — keyed by LEVEL (window A/B), eviction picks smaller level.
3. `lootboxRngPacked` — only LR_PENDING_ETH masked-written here; the shared slot also holds the live RNG index (read-only here).
4. `lootboxEth[index][buyer]` — keyed by (lootbox RNG index, buyer); packed 4-field word.
5. `boonPacked[*].slot0/.slot1` — keyed by boon-category bit offset.
6. `balancesPacked[*]` / `claimablePool` — claimable|afking halves; tandem solvency mutation.

---

## Hunt-relevant notes (418-425)

- **brick/midrng:** `_purchaseDeityPass` is the ONLY entrypoint gated on `rngLockedFlag` (:544); whale-bundle and lazy-pass are NOT — they remain purchasable mid-RNG-lock (their far-future ticket leg is separately blocked by `RngLocked()` inside `_queueTicket*`). A buyer can therefore mutate `mintPacked_`/pools/lootbox state during the daily RNG window via whale/lazy purchase; only far-future queue writes are fenced.
- **gameover/liveness:** every entrypoint calls `_livenessTriggered()` early and all queuing calls re-check it — so once liveness fires, the whole slice is inert (cannot add tickets to a known terminal word). This is the intended freeze; no path here can ADD a ticket after liveness.
- **vrfswap/orphan-index:** `_recordLootboxEntry` pushes to `boxPlayers[index]` (:888) and bumps `lootboxRngPacked` pending-ETH at the LIVE `index` — producer-only; the comment notes the consumer gates on `lootboxRngWordByIndex[index]!=0` so an orphaned index is skipped. The box binds to the live open level at open, not at deposit (no stored day on subsequent deposits).
- **corrupt (delegatecall storage):** module declares NO storage; all writes are by name into the shared layout — verified field names against `BitPackingLib` shifts and `DegenerusGameStorage`. No raw `delegatecall(msg.data)`, no nested delegatecall.
- **external-call revert bubble:** the whale-bundle `quantity` loop drives up to ~100×6 sDGNRS calls in one tx; any single `dgnrs.transferFromPool` revert bricks the whole purchase (bubbles via `_revertDelegate`). Not an advance-chain wedge, but a purchase-DoS surface if sDGNRS pool logic can revert under attacker-reachable state. Same for `quests.effectiveBaseStreakAndAfking` (reached on EVERY purchase via the lootbox-entry activity score) and the deity `DeityPass.mint`.
- **century-farm deterrent:** :240 forces ≥2 whale bundles at x99 century levels — an input revert, transient.
