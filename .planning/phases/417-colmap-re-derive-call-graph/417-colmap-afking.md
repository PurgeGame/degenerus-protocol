# Column Map — GameAfkingModule (slice 417-colmap-afking)

Subject: frozen `contracts/` tree `0dd445a6`.
File: `contracts/modules/GameAfkingModule.sol` (1813 lines).
Context: every function runs in **DegenerusGame's** storage via DELEGATECALL (the module
inherits `DegenerusGameMintStreakUtils` → `DegenerusGameStorage`). All storage names below
land in the GAME's slots. `msg.sender` is the ORIGINAL external caller throughout (delegatecall
preserves it), which the auth gates (`maybeCurse`/`smite`/`decurse`/`drainAffiliateBase`/
`recordAfkingSecondary`, operator-approval in `subscribe`) rely on.

## 0. Column-reachability summary

Two entrypoints sit on the spinal column:

- **`processSubscriberStage(processDay, weightBudget)`** — the REQUIRED-PATH pre-RNG stamp/buy
  pass. The AdvanceModule STAGE delegatecalls this *inside* `advanceGame` (349-05), so a revert
  here BUBBLES INTO advanceGame and can wedge the daily heartbeat. **Highest-criticality leg.**
- **`mintFlip()`** — permissionless router: self-calls `advanceGame` (the advance leg drives the
  STAGE) or runs the post-RNG `_autoOpen`. Reverts here only brick the *caller's* crank tx, but
  the advance self-call can carry a STAGE revert outward.

Secondary (off the advance chain but state-machine relevant): `subscribe` (FREEZE-gated; can run a
cover-buy `_deliverAfkingBuy` + a synchronous AFFILIATE `claim`), `drainAfkingBoxes`,
`claimAfkingFlip`, `drainAffiliateBase`, `recordAfkingSecondary`, `maybeCurse` (delegatecall target
from `claimWinnings`), `decurse`, `smite`.

`maybeCurse` is reached via delegatecall from the Game's `claimWinnings` path — its revert WOULD
bubble into a winnings claim, but it has NO revert site (every gate is an early `return`), so it
cannot brick a cashout.

---

## 1. CALL GRAPH (column-reachable functions)

Notation: `→i` internal/inherited call · `→d` delegatecall · `→x` synchronous external call
to a pinned `ContractAddresses.*` contract · `→self` Game self-call.

### `subscribe(player, drainGameCreditFirst, useTickets, dailyQuantity, reinvestPct, fundingSource)` — external payable (306)
- →i `_creditAfking` (353), `_settlePendingFlip` (369,408), `_finalizeAfking` (378), `_addToSet` (583)
- →i `_simulatedDayIndex` (378,448), `_passHorizonOf` (425), `_mintPriceInContext` (463,534),
  `_resolveBuy` (470,541), `_afkingOf` (480,551), `_goRead` (474,545), `_deliverAfkingBuy` (483,555),
  `_setStreakBase` (520,522,532,554,572)
- →x **AFFILIATE.claim([subscriber])** (375) — synchronous; reentrant-callback into
  `drainAffiliateBase` + `creditFlip`. Reverts bubble into the cancel.
- →x **QUESTS.beginAfking(subscriber, today)** (508) — new-run snapshot + sets afkingActive.
- →x **QUESTS.questCompletionToday(subscriber)** via `IQuestCompletionView` (515) — view.
- (via `_settlePendingFlip`) →x **COINFLIP.creditFlip** ; (via `_finalizeAfking`) →x **QUESTS.finalizeAfking**
- (via `_deliverAfkingBuy` cover-buy) — see that node (queues tickets / records indexed box, NO delegatecall on the cover path)

### `processSubscriberStage(processDay, weightBudget)` — external (1152) — **ON ADVANCE CHAIN**
- →i `_mintPriceInContext` (1156), `_goRead` (1164), `_resolveBuy` (1292), `_afkingOf` (1313),
  `_passHorizonOf` (1258), `_finalizeAfking` (1269,1332), `_removeFromSet` (1228,1271,1334),
  `_deliverAfkingBuy` (1354, coverBuy=false), `_routeAfkingPoolEth` (1387)
- →x (via `_finalizeAfking`) **QUESTS.finalizeAfking** (eviction / funding-kill legs only)
- NO delegatecall in this function. NO direct external call except the finalize path.

### `_deliverAfkingBuy(...)` — private (789)
- →i `_debitAfking` (804), `_debitClaimable` (811), `_playerActivityScore` (827,874),
  `_afkingStreak` (827,874), `_centuryUsedFor`/`_setCenturyUsedFor` (838,842),
  `PriceLookupLib.priceForLevel` (833), `_queueTicketsScaled` (849, ticket mode),
  `_recordAfkingCoverBox` (891, lootbox cover mode), `_packEthToMilliEth` (905, daily-stamp),
  `_ethToFlip` (917), `_routeAfkingPoolEth` (943,944, cover only), `_setStreakBase` (931)
- NO external call, NO delegatecall.

### `_recordAfkingCoverBox(...)` — private (968)
- →i `_lootboxEvMultiplierFromScore`, `_lootboxEvUsedFor`/`_setLootboxEvUsedFor`,
  `_unpackLootbox`, `_packLootbox`, `_packEthToMilliEth`, `_psRead`. No call/delegatecall.

### `_finalizeAfking(player, sub, currentDay)` — private (1065)
- →i `_streakBaseOf` (1071), `_setStreakBase` (1080)
- →x **QUESTS.finalizeAfking(player, earned, covered, currentDay)** (1073)

### `_settlePendingFlip(player, s)` — private (1096)
- →x **COINFLIP.creditFlip(player, owed*1e18)** (1106). Writes `presaleBoxCredit[player]` (1104).

### `mintFlip()` — external (1570) — **ON ADVANCE CHAIN (router)**
- →i `_advanceDueInContext` (1576), `_bountyEligible` (1582), `_mintPriceInContext` (1585,1601),
  `_autoOpen` (1596)
- →self **`IGameRouter(address(this)).advanceGame()`** (1589) — re-enters the Game's advance
  dispatch (which delegatecalls AdvanceModule, which drives `processSubscriberStage` in-context).
- →x **COINFLIP.creditFlip(msg.sender, bountyEarned)** (1615) — CEI-last bounty payout.

### `_autoOpen(maxCount)` — internal (1502)
- →i `_livenessTriggered` (1505), `_openAfkingBox` (1544)
- reads `rngWordByDay[stampDay]` (1537). No external call.

### `_openAfkingBox(player, sub, word)` — private (1463)
- →d **`ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(resolveAfkingBox.selector, ...)`** (1474)
  — **NESTED delegatecall** (this whole module is already executing under delegatecall from the
  Game). On failure →i `_revertDelegate` (1486) which re-raises the callee's revert bytes.

### `drainAfkingBoxes(count)` — external (1626)
- →i `_autoOpen(count)` (1627). (Reached via Game `openBoxes()` liveness valve.)

### `claimAfkingFlip(address[] subs)` — external (1683)
- loop →i `_settlePendingFlip` (1693) → →x **COINFLIP.creditFlip** per sub.

### `drainAffiliateBase(sub)` — external (1714)
- AFFILIATE-only gate (1715). Zeroes `_subOf[sub].affiliateBase`. No call.

### `recordAfkingSecondary(player)` — external (1728)
- QUESTS-only gate (1729). →i `_streakBaseOf`/`_setStreakBase` (1733).

### `maybeCurse(player)` — external (1747) — delegatecall target from `claimWinnings`
- →i `_currentMintDay` (1758), `_applyCurseStack` (1769). All gates are early `return`; NO revert.

### `decurse(target)` — external (1775)
- →x **COIN.burnCoin(msg.sender, PRICE_COIN_UNIT/10)** (1779). →i `_clearCurse` (1780).

### `smite(deityId, smitee)` — external (1789)
- →x **DEITY_PASS.ownerOf(deityId)** (1791, view) · **COIN.burnCoin(msg.sender, PRICE_COIN_UNIT/5)** (1803)
- →i `_applyCurseStack` (1804).

---

## 2. REVERT-SITE INVENTORY

| fn:line | trigger | error | TRANSIENT / PERMANENT-CANDIDATE |
|---|---|---|---|
| subscribe:317 | `rngLockedFlag` set (RNG freeze window) | `RngLocked()` | TRANSIENT — caller retries after unlock; does not block advance/open |
| subscribe:318 | `reinvestPct > 100` | `InvalidReinvestPct()` | TRANSIENT — caller-input; only this subscribe |
| subscribe:323-325 | third-party, caller not operator-approved | `NotApproved()` | TRANSIENT — caller-input |
| subscribe:331-337 | non-self `fundingSource` not operator-approved by subscriber | `NotApproved()` | TRANSIENT — caller-input |
| subscribe:354 | `claimablePool += uint128(msg.value)` checked add overflow | Panic 0x11 | TRANSIENT — needs ~3.4e38 wei pool; not column |
| subscribe:363 | cancel with no active sub (`_subscriberIndex==0`) | `NotSubscribed()` | TRANSIENT — caller-input |
| subscribe:433-434 | upsert, non-exempt sub's pass horizon `==0` or `< level` | `NoPass()` | TRANSIENT — caller-input; protocol subs exempt |
| subscribe:577 | NEW run, non-exempt, unfunded day-0 cover-buy | `MustPurchaseToBeginAfking()` | TRANSIENT — caller-input |
| subscribe:375 (callee) | AFFILIATE.claim reverts (`Insufficient` / `creditFlip` revert) | bubbles | TRANSIENT — single-elem array can't trip mixed-affiliate; only the canceller's tx |
| subscribe:508/1073 (callee) | QUESTS.beginAfking / finalizeAfking revert | bubbles | see §"externalCallRevertRisks" — finalize is on the STAGE path |
| _addToSet:626-627 | NEW insert at `_subscribers.length >= SUBSCRIBER_CAP` (1000) | `SubscriberCapReached()` | TRANSIENT — only blocks a *new* subscribe; re-subscribe exempt; cap-bounds the advance walk |
| _resolveBuy:744-747 | (none — view, no revert; built revert-free by construction per REVERT-01) | — | n/a |
| _debitClaimable:944 (callee, Storage) | `uint128(balancesPacked[player]) < weiAmount` | `E()` | PERMANENT-CANDIDATE if reachable on STAGE — fail-loud solvency guard; by construction unreachable (1-wei sentinel) |
| _deliverAfkingBuy:804 (callee `_debitAfking`) | afking high-half underflow (debit > afkingFunding) | Panic 0x11 | PERMANENT-CANDIDATE on STAGE — caller pre-checks `afkingFunding[src] >= ethValue`, so a revert means solvency already broken (must propagate) |
| _deliverAfkingBuy:805,812 | `claimablePool -= uint128(...)` underflow | Panic 0x11 | PERMANENT-CANDIDATE on STAGE — fail-loud SOLVENCY-01; by construction debit ≤ pool reservation |
| _deliverAfkingBuy:842 | `_setCenturyUsedFor` / `adjustedQty += bonusQty` — uint32 add | Panic 0x11 | TRANSIENT/unreachable — bonus clamped to `remaining` ≤ cap |
| _queueTicketsScaled:650 (callee) | `_livenessTriggered()` (ticket mode buy) | `E()` | PERMANENT-CANDIDATE on STAGE — a ticket sub's buy reverts once liveness-timeout latches → see riskNotes |
| _queueTicketsScaled:653 (callee) | far-future + `rngLockedFlag` + !bypass | `RngLocked()` | TRANSIENT on STAGE — afking targets level/level+1 (never far-future > level+5), so unreachable on this path |
| _finalizeAfking:1073 (callee QUESTS.finalizeAfking) | callee revert | bubbles | PERMANENT-CANDIDATE on STAGE — runs on evict/funding-kill legs inside the advance chain |
| _routeAfkingPoolEth:1417-1426 | `pNext/pFuture + uint128(...)` overflow | Panic 0x11 | TRANSIENT/unreachable — pools bounded by total ETH supply ≪ 2^128 |
| _settlePendingFlip:1104 | `presaleBoxCredit[player] += credit` overflow | Panic 0x11 | TRANSIENT — unreachable size |
| _settlePendingFlip:1106 (callee COINFLIP.creditFlip) | callee revert | bubbles | TRANSIENT on claimAfkingFlip/subscribe; NOT reached from STAGE |
| _openAfkingBox:1486 | LootboxModule `resolveAfkingBox` delegatecall returns `!ok` | re-raises callee bytes via `_revertDelegate` (1437-1442 → `E()` or raw) | PERMANENT-CANDIDATE for the OPEN leg only — see riskNotes; pre-gated (word!=0, level live) to be non-reverting |
| _revertDelegate:1438 | empty reason bytes | `E()` | n/a (helper) |
| mintFlip:1607 | both router categories empty | `NoWork()` | TRANSIENT — clean no-work signal; advance/open already had no work |
| mintFlip:1589 (self-call advanceGame) | advance reverts | bubbles | PERMANENT-CANDIDATE — if advanceGame (→STAGE) can revert, the crank tx bricks; STAGE revert is the wedge vector |
| mintFlip:1615 (COINFLIP.creditFlip) | bounty creditFlip reverts | bubbles | TRANSIENT — only the crank's bounty payout; work already done before this CEI-last call (but a revert would undo the whole tx incl. the advance — see riskNotes) |
| claimAfkingFlip:1693 (creditFlip per sub) | callee revert | bubbles | TRANSIENT — caller-batched; one bad sub fails the batch, retry per-sub |
| drainAffiliateBase:1715 | `msg.sender != AFFILIATE` | `NotApproved()` | TRANSIENT — access gate |
| recordAfkingSecondary:1729 | `msg.sender != QUESTS` | `NotApproved()` | TRANSIENT — access gate |
| decurse:1778 | target has no curse (`curse==0`) | `E()` | TRANSIENT — caller-input |
| decurse:1779 (COIN.burnCoin) | insufficient FLIP to burn | bubbles | TRANSIENT — caller balance |
| smite:1791-1793 | `DEITY_PASS.ownerOf(deityId) != msg.sender` | `E()` | TRANSIENT — auth |
| smite:1794 | smitee is an active afker (immunity) | `E()` | TRANSIENT — caller-input |
| smite:1797 | smitee curse `>= 10` (5-stack ceiling) | `E()` | TRANSIENT — caller-input |
| smite:1798-1802 | smitee is VAULT/SDGNRS/GNRUS | `E()` | TRANSIENT — caller-input |
| smite:1803 (COIN.burnCoin) | insufficient FLIP | bubbles | TRANSIENT — caller balance |
| maybeCurse | (NONE — all gates early-return) | — | maybeCurse can NEVER revert → cannot brick claimWinnings |

NOTE on inherited checked-arithmetic in helpers reachable on the column:
- `_afkingStreak` (Storage:2273-2277): `covered - sub.afkingStartDay` — subscribe pins
  `afkCoveredThroughDay >= afkingStartDay` (512-513) and the delivery only advances `afkCovered`,
  so the subtraction never underflows. `_finalizeAfking:1072` `covered - sub.afkingStartDay`
  likewise safe.
- `_livenessTriggered` (Storage:1469-1470): `currentDay - psd` — `currentDay >= purchaseStartDay`
  by construction (psd is set in the past), no underflow.

---

## 3. LOOP INVENTORY

| fn:line | iteration bound | per-iter storage/gas | BOUNDED / UNBOUNDED |
|---|---|---|---|
| processSubscriberStage:1185 `while (weight < weightBudget && cursor < len)` | min(weightBudget-derived, `_subscribers.length`) | per iter: `_subscribers[cursor]` SLOAD, `_subOf[player]` (struct), up to: reclaim delete+swap-pop, finalize (QUESTS.finalizeAfking xcall), `_resolveBuy` (2 SLOADs), `_deliverAfkingBuy` (debits + stamp/queue + accrue), pool-accrue. Weight per op: lootbox 2, ticket 4, evict 1, skip 1. | **BOUNDED** by `weightBudget` (caller-set, gas-DoS guard) AND by `SUBSCRIBER_CAP=1000`. Worst-case chunk gas governed by weightBudget; full-set drain spans multiple chunks via `_subCursor`. |
| _autoOpen:1523 `while (cursor < len && opened < maxCount)` | min(`maxCount` [default OPEN_BATCH=80], `_subscribers.length`) | per iter: `_subscribers[cursor]` SLOAD, `_subOf[player]`, possibly `rngWordByDay[stampDay]` SLOAD (day-cached), and a NESTED delegatecall (`_openAfkingBox`→resolveAfkingBox) per materialized box | **BOUNDED** by `maxCount`/OPEN_BATCH (80) and `_subscribers.length` (≤1000). Per-box ~74k → 80 boxes ≈ 9.15M < 16.7M ceiling. |
| claimAfkingFlip:1691 `for (i; i < len; )` | `subs.length` (caller calldata) | per iter: `_settlePendingFlip` → COINFLIP.creditFlip xcall + presaleBoxCredit write | **UNBOUNDED / INPUT-SIZED** — caller-supplied array; off the advance chain (permissionless claim), caller pays own gas; cannot wedge column. |
| subscribe:373 `new address[](1)` (not a loop; single-elem array for AFFILIATE.claim) | 1 | — | n/a |

No other `for`/`while` in the slice.

---

## 4. DELEGATECALL STORAGE-WRITE INVENTORY (Game slots written by this module)

Per-subscriber `Sub` record fields (`_subOf[player]`, struct `Sub` @ Storage:2174) — these are
**packed** (config 48b + stamp 48b + markers 72b + accumulators 72b across the struct's slots):

| field | written at | packing-key note |
|---|---|---|
| `Sub.dailyQuantity` (uint8) | subscribe:379 (cancel tombstone=0), 410 (upsert) | packed config slot |
| `Sub.flags` (uint8, bits: DRAIN/USE_TICKETS/EXTERNAL_FUNDING) | subscribe:411-414,440,443 | packed config slot |
| `Sub.reinvestPct` (uint8) | subscribe:415 | packed config slot |
| `Sub.validThroughLevel` (uint24) | subscribe:425; processSubscriberStage:1261 (REFRESH) | packed config slot; keyed by `level` crossing |
| `Sub.afkCoveredThroughDay` (uint24) | subscribe:512; _deliverAfkingBuy:933 | packed markers slot; **keyed by `processDay`** |
| `Sub.afkingStartDay` (uint24) | subscribe:513; _deliverAfkingBuy:930; _finalizeAfking:1079 | packed markers slot; keyed by day |
| `Sub.lastAutoBoughtDay` (uint24) | subscribe:523; _deliverAfkingBuy:936 | packed markers slot; **keyed by `processDay`** (also the box seed `day`) |
| `Sub.lastOpenedDay` (uint24) | subscribe:524; _deliverAfkingBuy:867,898; _openAfkingBox:1468 | packed markers slot; **keyed by `processDay`/stampDay** |
| `Sub.score` (uint16) | _deliverAfkingBuy:904 (daily-stamp lootbox) | packed stamp slot |
| `Sub.amount` (uint24, milli-ETH) | _deliverAfkingBuy:905 (daily-stamp lootbox) | packed stamp slot |
| `Sub.affiliateBase` (uint32, whole FLIP, 100M clamp) | _deliverAfkingBuy:921; drainAffiliateBase:1718 (zero) | packed accumulator slot |
| `Sub.pendingFlip` (uint32, whole FLIP, 100M clamp) | _deliverAfkingBuy:862,927; _settlePendingFlip:1099 (zero) | packed accumulator slot |
| `Sub.subStreakLatch` (uint8, via `_setStreakBase`) | subscribe:520/522/532/554/572; _deliverAfkingBuy:931; _finalizeAfking:1080; recordAfkingSecondary:1733 | packed accumulator slot |
| whole `Sub` slot | `delete _subOf[player]` — processSubscriberStage:1227,1270,1333 | wipes all fields |

Iterable-set / cursor storage:
- `_subscribers` (address[]) — `.push` (_addToSet:629), swap-pop (`_removeFromSet:647,650`)
- `_subscriberIndex[player]` (mapping) — write (_addToSet:630), update mover (_removeFromSet:648), `delete` (652)
- `_subCursor` (uint16) — processSubscriberStage:1385
- `_subOpenCursor` (uint16) — _autoOpen:1550
- `_fundingSourceOf[player]` — subscribe:439 (set), 442 (delete)

Balance / pool storage (SOLVENCY-01 invariant pairs):
- `balancesPacked[player]` — via `_creditAfking` (subscribe:353; high 128b), `_debitAfking`
  (_deliverAfkingBuy:804; high 128b), `_debitClaimable` (_deliverAfkingBuy:811; low 128b).
  **PACKED: claimable=low128 / afking=high128 of the SAME slot** — debit/credit must guard each half.
- `claimablePool` (uint128) — `+=` subscribe:354; `-=` _deliverAfkingBuy:805,812.
- `prizePoolsPacked` — via `_setPrizePools` (_routeAfkingPoolEth:1423). **PACKED: next=low128 / future=high128.**
- `prizePoolPendingPacked` — via `_setPendingPools` (_routeAfkingPoolEth:1417). **PACKED next/future.**

Lootbox / EV-cap / century storage (cover-buy + ticket-century legs):
- `lootboxEth[index][player]` (packed amount128/adj64/score16/distress48) — _recordAfkingCoverBox:1035.
  **PACKED 4-field slot, keyed by (index, player).**
- `lootboxRngPacked` (PENDING_ETH field RMW) — _recordAfkingCoverBox:1041. **PACKED slot, field-masked write.**
- `boxPlayers[index]` (.push) — _recordAfkingCoverBox:1004.
- `lootboxEvCapPacked[player]` — via `_setLootboxEvUsedFor` (_recordAfkingCoverBox:998,1024).
  **PACKED two-window slot, keyed by level (capKey = currentLevel+1).**
- `centuryBonusUsed[player]` — via `_setCenturyUsedFor` (_deliverAfkingBuy:842). **PACKED (level<<224 | used), keyed by x00 level.**

Ticket-queue storage (ticket-mode daily buy):
- `ticketQueue[wk]` (.push) — `_queueTicketsScaled:661` (only when packed==0).
- `ticketsOwedPacked[wk][buyer]` — `_queueTicketsScaled:685`. **PACKED (owed32<<8 | rem8), keyed by write-key `wk`(level-derived).**

Curse storage (curse/smite/decurse legs — `mintPacked_[player]`):
- `mintPacked_[target]` (CURSE_COUNT field, bits 215-222) — via `_applyCurseStack`
  (maybeCurse:1769, smite:1804) and `_clearCurse` (decurse:1780). **PACKED field-isolated write
  via `BitPackingLib.setPacked`, keyed by CURSE_COUNT_SHIFT; saturating +2.**

presale credit:
- `presaleBoxCredit[player]` (+=) — _settlePendingFlip:1104.

---

## 5. HUNT-RELEVANT NOTES

- **Nested delegatecall:** `_openAfkingBox:1474` delegatecalls `GAME_LOOTBOX_MODULE.resolveAfkingBox`
  while this module is ITSELF executing under delegatecall from the Game → a true nested
  delegatecall. `msg.sender` is preserved as the original crank caller; storage is the Game's.
  No raw `delegatecall(msg.data)` dispatch exists in this slice (the focus-prompt shape is absent
  here — the only delegatecall is the typed selector-encoded `resolveAfkingBox`).

- **STAGE-on-advance-chain revert wedge candidates** (the high-value 418-423 targets):
  1. `_queueTicketsScaled:650` reverts `E()` once `_livenessTriggered()` latches — a *ticket-mode*
     afking sub processed on the STAGE would revert, and since the STAGE runs inside `advanceGame`,
     that revert bubbles into advance. MUST verify the STAGE cannot reach a ticket buy after the
     liveness timeout (the open leg gates on `_livenessTriggered`, but the STAGE buy does NOT).
  2. `_finalizeAfking → QUESTS.finalizeAfking` (1073) runs on evict/funding-kill legs of the STAGE;
     a revert in QUESTS would bubble into advance. Cross-contract callee — verify it is total.
  3. `_debitAfking`/`claimablePool -=` underflow (804/805/811/812) are fail-loud by design; if ever
     reachable with debit > balance they wedge advance permanently (intended: signals broken
     solvency). The 1-wei sentinel + caller pre-check are the only thing keeping them unreachable.

- **mintFlip CEI-last bounty (1615):** `COINFLIP.creditFlip(msg.sender, bountyEarned)` runs AFTER
  the advance self-call. If creditFlip can revert for a particular `msg.sender`, the whole tx
  (including the advance) reverts — but advance is liveness-critical. A non-eligible/blocked
  caller could in principle make every crank revert AFTER doing the advance work, never persisting
  it. Verify creditFlip is total for any address (it is a pure ledger add per the affiliate
  comment, recordAmount=0) — flagged as the column-bubbling external-call risk.

- **Open-leg delegatecall revert (1486):** `_autoOpen` claims the body "cannot revert under the
  entry-gate" (word!=0, level live, not frozen). If `resolveAfkingBox` CAN revert post-gate (e.g. a
  packed-field overflow or an EV-cap edge), `_revertDelegate` re-raises and bricks the OPEN leg /
  the `mintFlip` open category / `drainAfkingBoxes`. Off the advance chain (open is post-RNG router
  work), so it bricks opens, not advance — but a permanently-unopenable box = stranded paid-for box.

- **Packed-slot aliasing hotspots** (day/level/offset-keyed writes that 418-423 should watch for
  cross-field corruption): `balancesPacked` (claimable/afking halves), `Sub` marker slot
  (`lastAutoBoughtDay`/`lastOpenedDay`/`afkCoveredThroughDay`/`afkingStartDay` all uint24 in one
  slot, written across `_deliverAfkingBuy`/`subscribe`/`_openAfkingBox` keyed by processDay),
  `Sub` accumulator slot (`affiliateBase`/`pendingFlip`/`subStreakLatch` written by different
  legs + zeroed independently by `drainAffiliateBase`/`_settlePendingFlip`), `lootboxEth` 4-field
  word, `lootboxRngPacked` PENDING_ETH field-mask RMW, `lootboxEvCapPacked` two-window level-keyed,
  `centuryBonusUsed` level-keyed, `ticketsOwedPacked` level-key+frac, `mintPacked_` CURSE field.

- **VAULT/SDGNRS exemption** keys on the pinned `ContractAddresses` identity applied to `player`
  (never `src`), at subscribe:420-421 and processSubscriberStage:1316-1318 — an exempt sub is never
  funding-killed/evicted, so a perpetually-underfunded protocol sub stays in-set forever (intended;
  bounds: it's 2 fixed addresses, no DoS). `maybeCurse`/`smite` also skip VAULT/SDGNRS/GNRUS.
